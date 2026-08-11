#!/usr/bin/env python3
"""Focused tests for the read-only world-data validator."""

from __future__ import annotations

import importlib.util
import json
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

    def test_nonfinite_json_constants_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_root = root / "data"
            data_root.mkdir()
            (data_root / "bad.json").write_text('{"value": NaN}\n', encoding="utf-8")

            documents, findings, sizes = validator.load_json_documents(data_root)
            expected_size = (data_root / "bad.json").stat().st_size

        self.assertEqual(documents, {})
        self.assertEqual(sizes["bad.json"], expected_size)
        self.assertEqual([finding.code for finding in findings], ["JSON_PARSE_ERROR"])

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
