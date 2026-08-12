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
        self.assertEqual(government["declared_id_kinds"], ["organization"])
        self.assertEqual(government["declared_foreign_key_targets"], ["world_map.organizations"])

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
