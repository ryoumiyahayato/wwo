#!/usr/bin/env python3
"""Focused tests for the read-only world-data validator."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import math
import tempfile
import unittest
import sys
from pathlib import Path
from types import ModuleType


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPOSITORY_ROOT / "tools" / "world_data" / "validate_world_data.py"


def load_validator() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wwo_world_data_validator", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load validator: {VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


validator = load_validator()


def run_validator_cli(data_root: Path, allow_errors: bool = False) -> tuple[int, dict[str, object]]:
    arguments = [sys.executable, str(VALIDATOR_PATH), "--root", str(REPOSITORY_ROOT), "--data-root", str(data_root)]
    if allow_errors:
        arguments.append("--allow-errors")
    completed = subprocess.run(arguments, cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=False)
    summary = json.loads(completed.stdout.strip().splitlines()[-1])
    return completed.returncode, summary["summary"]


def large_valid_ring() -> list[list[float]]:
    ring = [[math.cos(2.0 * math.pi * index / 304.0), math.sin(2.0 * math.pi * index / 304.0)] for index in range(304)]
    ring.append(list(ring[0]))
    return ring


def large_crossing_ring() -> list[list[float]]:
    return [[0.0, 0.0], [4.0, 4.0], [0.0, 4.0], [4.0, 0.0]] + [
        [0.0, 1.0 - index / 300.0] for index in range(301)
    ]


class WorldDataValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.audit = validator.WorldDataAudit(REPOSITORY_ROOT / "data" / "world_map")
        cls.result = cls.audit.run()

    def test_current_inventory_is_machine_readable_and_counts_core_catalogs(self) -> None:
        counts = self.result["inventory"]["counts"]
        self.assertEqual(counts["country_count"], 177)
        self.assertEqual(counts["region_count"], 9)
        self.assertEqual(counts["city_count"], 32)
        self.assertEqual(counts["port_count"], 8)
        self.assertEqual(counts["road_link_count"], 3)
        self.assertEqual(counts["rail_link_count"], 9)
        self.assertEqual(counts["shipping_link_count"], 3)
        self.assertEqual(counts["historical_political_entity_count"], 61)
        self.assertEqual(counts["organization_count"], 11)
        self.assertEqual(counts["institution_count"], 7)
        self.assertEqual(counts["character_person_like_record_count"], 2)
        self.assertGreater(counts["modern_city_detail_record_count"], 80_000)
        self.assertEqual(self.result["inventory"]["file_count"], 183)

    def test_current_run_has_no_json_parse_errors_and_emits_coverage_and_staging(self) -> None:
        codes = {finding["code"] for finding in self.result["findings"]}
        self.assertNotIn("JSON_PARSE_ERROR", codes)
        self.assertEqual(len(self.result["coverage"]["countries"]), 177)
        self.assertIn("country_to_cities", self.result["staging_candidates"]["derived_indexes"])
        self.assertIn("historical_unit_to_geometry", self.result["staging_candidates"]["derived_indexes"])

    def test_missing_file_empty_and_unrelated_roots_fail_closed_through_cli(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            missing_code, missing_summary = run_validator_cli(root / "missing")
            self.assertNotEqual(missing_code, 0)
            self.assertEqual(missing_summary["code_counts"], {"DATA_ROOT_MISSING": 1})

            file_root = root / "root.json"
            file_root.write_text("{}\n", encoding="utf-8")
            file_code, file_summary = run_validator_cli(file_root)
            self.assertNotEqual(file_code, 0)
            self.assertEqual(file_summary["code_counts"], {"DATA_ROOT_NOT_DIRECTORY": 1})

            empty_root = root / "empty"
            empty_root.mkdir()
            empty_code, empty_summary = run_validator_cli(empty_root)
            self.assertNotEqual(empty_code, 0)
            self.assertEqual(empty_summary["code_counts"], {"DATA_ROOT_EMPTY": 1})

            unrelated_root = root / "unrelated"
            unrelated_root.mkdir()
            (unrelated_root / "README.txt").write_text("not source data\n", encoding="utf-8")
            unrelated_code, unrelated_summary = run_validator_cli(unrelated_root)
            self.assertNotEqual(unrelated_code, 0)
            self.assertEqual(unrelated_summary["code_counts"], {"DATA_ROOT_EMPTY": 1})

            unrelated_json_root = root / "unrelated_json"
            unrelated_json_root.mkdir()
            (unrelated_json_root / "notes.json").write_text("{\"note\": true}\n", encoding="utf-8")
            unrelated_json_code, unrelated_json_summary = run_validator_cli(unrelated_json_root)
            self.assertNotEqual(unrelated_json_code, 0)
            self.assertEqual(unrelated_json_summary["code_counts"], {"DATA_ROOT_EMPTY": 1})

    def test_minimal_contract_source_tree_scans_normally_through_cli(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            data_root = Path(temp_dir)
            (data_root / "countries.json").write_text(
                '{"schema_version": 1, "countries": []}\n', encoding="utf-8"
            )
            exit_code, summary = run_validator_cli(data_root)
        self.assertEqual(exit_code, 0)
        self.assertNotIn("DATA_ROOT_MISSING", summary["code_counts"])
        self.assertNotIn("DATA_ROOT_NOT_DIRECTORY", summary["code_counts"])
        self.assertNotIn("DATA_ROOT_EMPTY", summary["code_counts"])

    def test_nonfinite_json_constants_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_root = root / "data"
            data_root.mkdir()
            (data_root / "countries.json").write_text('{"schema_version": 1, "countries": []}\n', encoding="utf-8")
            (data_root / "bad.json").write_text('{"value": NaN}\n', encoding="utf-8")

            documents, findings, sizes = validator.load_json_documents(data_root)
            expected_size = len('{"value": NaN}\n'.encode("utf-8"))

        self.assertEqual(documents["countries.json"]["countries"], [])
        self.assertNotIn("bad.json", documents)
        self.assertEqual(sizes["bad.json"], expected_size)
        self.assertEqual([finding.code for finding in findings], ["JSON_PARSE_ERROR"])

    def test_configured_catalog_collection_rejects_scalar_or_missing_value(self) -> None:
        for document in ({"schema_version": 1, "countries": "corrupt"}, {"schema_version": 1}):
            with self.subTest(document=document), tempfile.TemporaryDirectory() as temp_dir:
                data_root = Path(temp_dir)
                (data_root / "countries.json").write_text(json.dumps(document), encoding="utf-8")
                result = validator.WorldDataAudit(data_root).run()
                findings = [item for item in result["findings"] if item["code"] == "CATALOG_COLLECTION_TYPE"]
                self.assertEqual(len(findings), 1)
                self.assertEqual(findings[0]["severity"], "ERROR")

    def test_geometry_cache_rejects_malformed_triangulation_payload(self) -> None:
        audit = validator.WorldDataAudit(Path("."))
        audit.ids_by_kind["country"] = {"country_a"}
        audit.documents = {
            "map_geometry_cache.json": {
                "country_lods": {
                    "lod0": [
                        {
                            "country_id": "country_a",
                            "polygons": [{"outer": [[0, 0], [1, 0], [0, 1]], "holes": [], "triangles": [0, 1, 3]}],
                        }
                    ]
                }
            }
        }
        audit._validate_geometry_cache()
        self.assertIn("GEOMETRY_CACHE_TRIANGLES", {finding.code for finding in audit.findings})

    def test_city_detail_shards_must_be_indexed_with_matching_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            data_root = Path(temp_dir)
            shard_dir = data_root / "city_detail" / "countries"
            shard_dir.mkdir(parents=True)
            (data_root / "city_detail" / "index.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "countries": [
                            {
                                "country_code": "AA",
                                "shards": [{"id": "AA", "path": "countries/AA.json", "count": 2, "bounds": [10, 10, 11, 11]}],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (shard_dir / "AA.json").write_text(
                json.dumps({"schema_version": 1, "country_code": "AA", "shard_id": "AA", "count": 1, "cities": [{"id": "city_a", "lon_lat": [0, 0]}]}),
                encoding="utf-8",
            )
            (shard_dir / "BB.json").write_text(
                json.dumps({"schema_version": 1, "country_code": "BB", "shard_id": "BB", "count": 0, "cities": []}),
                encoding="utf-8",
            )
            result = validator.WorldDataAudit(data_root).run()
        codes = {finding["code"] for finding in result["findings"]}
        self.assertIn("UNINDEXED_CITY_DETAIL_SHARD", codes)
        self.assertIn("CITY_DETAIL_INDEX_COUNT_MISMATCH", codes)
        self.assertIn("CITY_DETAIL_INDEX_BOUNDS_MISMATCH", codes)

    def test_unified_validation_invokes_world_data_regressions(self) -> None:
        script = (REPOSITORY_ROOT / "tools" / "run_validation.ps1").read_text(encoding="utf-8")
        self.assertIn('unittest discover -s "$ProjectPath/tests/world_data"', script)

    def test_geometry_helpers_detect_self_intersection_and_rotation_equivalence(self) -> None:
        simple_ring = [[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 0.0]]
        bow_tie = [[0.0, 0.0], [2.0, 2.0], [0.0, 2.0], [2.0, 0.0], [0.0, 0.0]]

        self.assertFalse(validator.ring_self_intersects(simple_ring))
        self.assertTrue(validator.ring_self_intersects(bow_tie))
        self.assertNotEqual(validator.ring_area(simple_ring), 0.0)
        self.assertEqual(
            validator.canonical_ring(simple_ring),
            validator.canonical_ring([[2.0, 0.0], [2.0, 2.0], [0.0, 0.0], [2.0, 0.0]]),
        )

    def test_large_ring_geometry_is_complete_and_deterministic(self) -> None:
        valid_ring = large_valid_ring()
        crossing_ring = large_crossing_ring()
        self.assertEqual(len(crossing_ring), 305)
        self.assertFalse(validator.ring_self_intersects(valid_ring))
        self.assertTrue(validator.ring_self_intersects(crossing_ring))
        candidates = validator.ring_intersection_candidates(valid_ring)
        self.assertEqual(candidates, validator.ring_intersection_candidates(valid_ring))
        self.assertLess(len(candidates), 304 * 303 // 2)

        valid_audit = validator.WorldDataAudit(Path("."))
        valid_ref = validator.RecordRef(
            "modern_admin1", "world_admin1.json", "regions", 0, "valid", {"polygons": [valid_ring]}
        )
        valid_audit._validate_rings_for_ref(valid_ref, True)
        self.assertNotIn("SELF_INTERSECTING_RING", {finding.code for finding in valid_audit.findings})

        crossing_audit = validator.WorldDataAudit(Path("."))
        crossing_ref = validator.RecordRef(
            "modern_admin1", "world_admin1.json", "regions", 0, "crossing", {"polygons": [crossing_ring]}
        )
        crossing_audit._validate_rings_for_ref(crossing_ref, True)
        first_findings = [finding.as_dict() for finding in crossing_audit.findings]
        self.assertIn("SELF_INTERSECTING_RING", {finding.code for finding in crossing_audit.findings})

        repeat_audit = validator.WorldDataAudit(Path("."))
        repeat_ref = validator.RecordRef(
            "modern_admin1", "world_admin1.json", "regions", 0, "crossing", {"polygons": [crossing_ring]}
        )
        repeat_audit._validate_rings_for_ref(repeat_ref, True)
        self.assertEqual(first_findings, [finding.as_dict() for finding in repeat_audit.findings])

    def test_adjacent_closing_and_repeated_vertex_semantics_remain_stable(self) -> None:
        adjacent_ring = [[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0], [0.0, 0.0]]
        repeated_vertex_ring = [[0.0, 0.0], [3.0, 0.0], [3.0, 3.0], [0.0, 3.0], [3.0, 3.0], [0.0, 0.0]]
        self.assertFalse(validator.ring_self_intersects(adjacent_ring))
        self.assertTrue(validator.ring_self_intersects(repeated_vertex_ring))

    def test_duplicate_catalog_id_is_an_error_in_an_independent_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            data_root = Path(temp_dir)
            (data_root / "countries.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "countries": [{"id": "country_a"}, {"id": "country_a"}],
                    }
                ),
                encoding="utf-8",
            )
            result = validator.WorldDataAudit(data_root).run()
        duplicate_findings = [finding for finding in result["findings"] if finding["code"] == "DUPLICATE_ID"]
        self.assertEqual(len(duplicate_findings), 1)
        self.assertEqual(duplicate_findings[0]["severity"], "ERROR")

    def test_dangling_reference_is_an_error_in_an_independent_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            data_root = Path(temp_dir)
            (data_root / "countries.json").write_text(
                json.dumps({"schema_version": 1, "countries": [{"id": "existing_country"}]}),
                encoding="utf-8",
            )
            (data_root / "cities.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "cities": [{"id": "city_a", "parent_country_id": "missing_country"}],
                    }
                ),
                encoding="utf-8",
            )
            result = validator.WorldDataAudit(data_root).run()
        dangling_findings = [finding for finding in result["findings"] if finding["code"] == "DANGLING_FOREIGN_KEY"]
        self.assertEqual(len(dangling_findings), 1)
        self.assertEqual(dangling_findings[0]["severity"], "ERROR")

    def test_placeholder_reference_is_warning_not_automatic_repair(self) -> None:
        audit = validator.WorldDataAudit(Path("."))
        ref = validator.RecordRef(
            "institution",
            "institutions.json",
            "institutions",
            0,
            "prefecture_nord",
            {"parent_institution_id": "interior_ministry_placeholder"},
        )
        audit.ids_by_kind["institution"].add("prefecture_nord")

        audit._check_reference(
            ref,
            "parent_institution_id",
            ("institution",),
            True,
            "parent institution",
        )

        self.assertEqual(len(audit.findings), 1)
        self.assertEqual(audit.findings[0].severity, "WARNING")
        self.assertEqual(audit.findings[0].code, "PLACEHOLDER_FOREIGN_KEY")


if __name__ == "__main__":
    unittest.main()
