#!/usr/bin/env python3
"""Focused tests for the deterministic world-data dictionary generator."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = REPOSITORY_ROOT / "tools" / "world_data_dictionary" / "generate.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("world_data_dictionary_generate", GENERATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load generator: {GENERATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


generator = load_generator()


class SyntheticObservationTests(unittest.TestCase):
    def test_observation_keeps_missing_and_incompatible_types_visible(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_path = root / "data" / "world_map" / "sample.json"
            data_path.parent.mkdir(parents=True)
            data_path.write_text(
                json.dumps({"items": [{"id": "a", "value": 1}, {"id": "b", "value": "one"}, {"id": "c"}]}),
                encoding="utf-8",
            )
            result = generator.build_dictionary(root)
            dataset = next(item for item in result["datasets"] if item["dataset"] == "world_map.sample")
            value = next(item for item in dataset["fields"] if item["field"] == "items[].value")
            self.assertEqual(value["observed_type_variants"], ["integer", "string"])
            self.assertEqual(value["record_count"], 3)
            self.assertEqual(value["missing_count"], 1)
            self.assertFalse(value["required_by_observation"])
            self.assertTrue(any(item["kind"] == "type_inconsistency" for item in result["findings"]))

    def test_declared_loader_default_is_distinct_from_observation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_path = root / "data" / "world_map" / "sample.json"
            source_path = root / "scripts" / "sample_loader.gd"
            data_path.parent.mkdir(parents=True)
            source_path.parent.mkdir(parents=True)
            data_path.write_text(json.dumps({"items": [{"id": "a"}]}), encoding="utf-8")
            source_path.write_text(
                'const PATH = "res://data/world_map/sample.json"\n'
                'var label = record.get("label", "unknown")\n',
                encoding="utf-8",
            )
            result = generator.build_dictionary(root)
            dataset = result["datasets"][0]
            field = next(item for item in dataset["fields"] if item["field"] == "items[].id")
            self.assertFalse(field["declared"])
            self.assertTrue(field["observed"])
            self.assertFalse(any(item["field"] == "label" for item in dataset["fields"]))
            # A loader access without a reliable record path is retained in
            # source evidence, but does not become a guessed observed field.
            self.assertTrue(dataset["loader_evidence"])


class SyntheticReviewRegressionTests(unittest.TestCase):
    def test_full_path_declaration_does_not_collide_on_leaf(self) -> None:
        def access(field_path, line, text):
            return {
                "field": "id",
                "field_path": field_path,
                "line": line,
                "kind": "get",
                "evidence_scope": "LOADER",
                "has_explicit_default": False,
                "default": None,
                "default_expression": None,
                "required": False,
                "id_kind": None,
                "type": "string",
                "text": text,
            }

        sources = [
            {
                "source": "scripts/foo_loader.gd",
                "targets": ["sample"],
                "exact_contract": True,
                "contract_scope": "EXACT_DATASET",
                "field_accesses": [access("foo.id", 10, 'foo.get("id")')],
                "required_blocks": [],
                "enum_constants": [],
            },
            {
                "source": "scripts/multi_loader.gd",
                "targets": ["sample"],
                "exact_contract": False,
                "contract_scope": "MULTI_DATASET_OR_INFERRED",
                "field_accesses": [access(None, 20, 'record.get("id")')],
                "required_blocks": [],
                "enum_constants": [],
            },
        ]
        foo = generator.declared_evidence_for_field("sample", "foo.id", sources)
        bar = generator.declared_evidence_for_field("sample", "bar.id", sources)
        self.assertTrue(foo["declared"])
        self.assertFalse(bar["declared"])
        self.assertTrue(any(item["kind"] == "HEURISTIC_LEAF_MATCH" for item in bar["heuristic_evidence"]))

    def test_geometry_polymorphism_is_conditioned_and_malformed_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_path = root / "data" / "world_map" / "geometry.json"
            data_path.parent.mkdir(parents=True)
            data_path.write_text(json.dumps({
                "features": [
                    {"geometry": {"type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1]]]}},
                    {"geometry": {"type": "MultiPolygon", "coordinates": [[[[0, 0], [1, 0], [1, 1]]]]}},
                    {"geometry": {"type": "Polygon", "coordinates": [1, 2]}},
                ],
            }), encoding="utf-8")
            result = generator.build_dictionary(root)
            dataset = result["datasets"][0]
            geometry = dataset["geometry_evidence"]["by_type"]
            self.assertEqual(geometry["Polygon"]["record_count"], 2)
            self.assertEqual(geometry["MultiPolygon"]["record_count"], 1)
            self.assertEqual(geometry["Polygon"]["invalid_count"], 1)
            coordinates = next(item for item in dataset["fields"] if item["field"] == "features[].geometry.coordinates")
            self.assertTrue(coordinates["geometry_type_conditioned"])
            self.assertFalse(any(
                item["kind"] == "type_inconsistency" and item["field"] == coordinates["field"]
                for item in result["findings"]
            ))
            self.assertTrue(any(item["kind"] == "malformed_geometry_structure" for item in result["findings"]))

    def test_source_config_and_runtime_snapshot_scopes_are_separate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_path = root / "data" / "vnext" / "politics" / "state_politics_1900.json"
            source_path = root / "scripts" / "vnext" / "politics" / "state_politics.gd"
            data_path.parent.mkdir(parents=True)
            source_path.parent.mkdir(parents=True)
            data_path.write_text(json.dumps({"state_id": "state:test", "capacity": {}}), encoding="utf-8")
            source_path.write_text(
                'static func _snapshot_from_config(config: Dictionary) -> Dictionary:\n'
                '    for required_field: String in ["state_id", "capacity"]:\n'
                '        if not config.has(required_field):\n'
                '            return {}\n'
                '    var period_index := _normalize_int(config.get("period_index", 0), 0, 10)\n'
                'static func _validate_snapshot(snapshot_value: Dictionary) -> bool:\n'
                '    for required_field: String in ["period_index", "crisis_stage"]:\n'
                '        if not snapshot_value.has(required_field):\n'
                '            return false\n'
                '    return true\n',
                encoding="utf-8",
            )
            result = generator.build_dictionary(root)
            dataset = next(item for item in result["datasets"] if item["dataset"] == "vnext.politics.state_politics_1900")
            state_id = next(item for item in dataset["fields"] if item["field"] == "state_id")
            runtime_period = next(item for item in dataset["fields"] if item["field"] == "runtime_snapshot.period_index")
            self.assertTrue(state_id["source_config_required"])
            self.assertFalse(state_id["runtime_snapshot_required"])
            self.assertFalse(runtime_period["source_config_required"])
            self.assertTrue(runtime_period["runtime_snapshot_required"])
            self.assertEqual(runtime_period["required_status"], "runtime-snapshot-required")
            self.assertTrue(any(item["kind"] == "runtime_snapshot_field_not_source_config" for item in result["findings"]))

    def test_ambiguous_fk_and_stable_id_kind_remain_non_declared(self) -> None:
        ambiguous_field = {
            "field": "government_id",
            "observed": True,
            "id_field": True,
            "id_kind": "reference_candidate",
            "declared_id_kinds": ["organization"],
            "foreign_key": None,
        }
        stable_kind_field = {
            "field": "stable_id",
            "observed": True,
            "id_field": True,
            "id_kind": "semantic_id",
            "declared_id_kinds": ["organization"],
            "foreign_key": None,
        }
        datasets = [
            {"dataset": "sample", "fields": [ambiguous_field, stable_kind_field]},
            {"dataset": "world_map.organizations", "fields": []},
            {"dataset": "vnext.politics.state_politics_1900", "fields": []},
        ]
        relationships, issues, candidates = generator.attach_foreign_keys(datasets)
        self.assertEqual(relationships, [])
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["evidence"], "HEURISTIC_FK_CANDIDATE")
        self.assertEqual(candidates[0]["confidence"], "ambiguous")
        self.assertTrue(any(item["kind"] == "foreign_key_ambiguous_target" for item in issues))
        self.assertIsNone(stable_kind_field["foreign_key"])

    def test_malformed_json_is_reported_without_fake_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_path = root / "data" / "world_map" / "broken.json"
            data_path.parent.mkdir(parents=True)
            data_path.write_text('{"items": [', encoding="utf-8")
            result = generator.build_dictionary(root)
            self.assertEqual(result["summary"]["input_errors"], 1)
            self.assertEqual(result["datasets"][0]["fields"], [])

    def test_markdown_header_is_a_real_table(self) -> None:
        dataset = {
            "dataset": "sample",
            "description": "Synthetic dataset.",
            "path": "data/world_map/sample.json",
            "record_shape": {"root_type": "object", "primary_record_path": "items[]", "record_collections": []},
            "source_paths": ["data/world_map/sample.json"],
            "record_count": 1,
            "document_count": 1,
            "fields": [{
                "field": "items[].id",
                "record_scope": "items[]",
                "observed": True,
                "observed_type": "string",
                "declared_types": ["string"],
                "nullable": False,
                "required_by_observation": True,
                "source_config_required": True,
                "runtime_snapshot_required": False,
                "required_status": "declared-required",
                "missing_count": 0,
                "record_count": 1,
                "default": None,
                "unique": True,
                "id_kind": "primary_candidate",
                "foreign_key": None,
                "enum_candidates": [],
                "numeric_min": None,
                "numeric_max": None,
                "example_values": ["x"],
                "declared": True,
            }],
            "input_errors": [],
            "geometry_evidence": {"by_type": {}, "invalid_records": []},
            "notes": [],
        }
        markdown = generator.render_dataset_markdown(dataset)
        self.assertIn(
            "| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |",
            markdown,
        )
        self.assertNotIn("evidence || ---", markdown)


class RealRepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.dictionary = generator.build_dictionary(REPOSITORY_ROOT)

    def test_real_scope_and_loader_evidence_are_present(self) -> None:
        datasets = {item["dataset"]: item for item in self.dictionary["datasets"]}
        self.assertIn("world_map.countries", datasets)
        self.assertIn("world_map.city_detail.country_shards", datasets)
        self.assertIn("vnext.politics.state_politics_1900", datasets)
        countries = datasets["world_map.countries"]
        country_id = next(item for item in countries["fields"] if item["field"] == "countries[].id")
        self.assertTrue(country_id["observed"])
        self.assertTrue(country_id["id_field"])
        self.assertTrue(countries["loader_evidence"])
        flags = datasets["world_map.historical.flags_1900"]
        flag_record = next(item for item in flags["fields"] if item["field"] == "records.<key>")
        self.assertEqual(flag_record["record_count"], 61)
        flag_hash = next(item for item in flags["fields"] if item["field"] == "records.<key>.asset_sha256")
        self.assertEqual(flag_hash["missing_count"], 1)
        politics = datasets["vnext.politics.state_politics_1900"]
        regime = next(item for item in politics["fields"] if item["field"] == "regime_type")
        self.assertTrue(regime["declared"])
        self.assertIn("parliamentary_republic", regime["declared_enum_values"])
        government = next(item for item in politics["fields"] if item["field"] == "government_id")
        self.assertEqual(government["declared_id_kinds"], [])
        self.assertEqual(government["declared_foreign_key_targets"], [])
        runtime_government = next(item for item in politics["fields"] if item["field"] == "runtime_snapshot.government_id")
        self.assertEqual(runtime_government["declared_id_kinds"], ["organization"])
        self.assertEqual(government["foreign_key"]["evidence"], "HEURISTIC_FK_CANDIDATE")
        self.assertEqual(government["foreign_key"]["confidence"], "ambiguous")
        self.assertEqual(self.dictionary["summary"]["foreign_key_relationships"], 0)

    def test_rendering_is_deterministic(self) -> None:
        first = generator.render_outputs(self.dictionary)
        second = generator.render_outputs(generator.build_dictionary(REPOSITORY_ROOT))
        self.assertEqual(first, second)
        self.assertIn("dictionary.json", first)
        parsed = json.loads(first["dictionary.json"])
        self.assertEqual(parsed["generation_contract"]["production_data_modified"], False)

    def test_scope_contains_no_production_data_outputs(self) -> None:
        for dataset in self.dictionary["datasets"]:
            for path in dataset["source_paths"]:
                self.assertTrue(path.startswith("data/world_map/") or path.startswith("data/vnext/"))
        self.assertEqual(self.dictionary["summary"]["input_errors"], 0)


if __name__ == "__main__":
    unittest.main()
