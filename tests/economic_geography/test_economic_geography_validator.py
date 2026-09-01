from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.economic_geography import validate_economic_geography as validator


def load_documents() -> dict[str, object]:
    return {
        "evidence": validator.load_json(ROOT, validator.EVIDENCE_PATH),
        "sources": validator.load_json(ROOT, validator.SOURCE_PATH),
        "calibration": validator.load_json(ROOT, validator.CALIBRATION_PATH),
        "sectors": validator.load_json(ROOT, validator.SECTOR_PATH),
        "compatibility": validator.load_json(ROOT, validator.COMPATIBILITY_PATH),
        "commodities": validator.load_json(ROOT, validator.COMMODITY_PATH),
        "spatial": validator.load_json(ROOT, validator.SPATIAL_PATH),
    }


def validate(documents: dict[str, object]) -> dict[str, object]:
    return validator.validate_documents(
        documents["evidence"],
        documents["sources"],
        documents["calibration"],
        documents["sectors"],
        documents["compatibility"],
        documents["commodities"],
        documents["spatial"],
    )


def assertions(documents: dict[str, object]) -> list[dict[str, object]]:
    evidence = documents["evidence"]
    return [
        assertion
        for record in evidence["evidence_records"]
        for assertion in record["assertions"]
    ]


class EconomicGeographyR1Tests(unittest.TestCase):
    def test_baseline_contract_is_valid_and_stays_pilot_sized(self) -> None:
        result = validate(load_documents())
        self.assertTrue(result["valid"], result["errors"])
        self.assertEqual(result["summary"]["evidence_region_count"], 7)
        self.assertEqual(result["summary"]["historical_quantitative_value_count"], 0)

    def test_r1_01_duplicate_assertion_id_fails(self) -> None:
        documents = load_documents()
        pilot_assertions = assertions(documents)
        pilot_assertions[0]["assertion_id"] = pilot_assertions[1]["assertion_id"]
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[DUPLICATE_ASSERTION_ID]" in error for error in result["errors"]))

    def test_r1_02_unknown_spatial_id_fails(self) -> None:
        documents = load_documents()
        assertions(documents)[0]["spatial_memberships"][0]["spatial_region_id"] = "ZZZ-UNKNOWN"
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[UNKNOWN_SPATIAL_REGION_ID]" in error for error in result["errors"]))

    def test_r1_03_invalid_coverage_bp_fails(self) -> None:
        documents = load_documents()
        assertions(documents)[0]["spatial_memberships"][0]["coverage_bp"] = -1
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[INVALID_COVERAGE_BP]" in error for error in result["errors"]))

    def test_r1_04_invalid_relevance_bp_fails(self) -> None:
        documents = load_documents()
        assertions(documents)[0]["spatial_memberships"][0]["relevance_bp"] = 10001
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[INVALID_RELEVANCE_BP]" in error for error in result["errors"]))

    def test_r1_05_assertion_without_provenance_fails(self) -> None:
        documents = load_documents()
        assertions(documents)[0]["source_ids"] = []
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[ASSERTION_WITHOUT_PROVENANCE]" in error for error in result["errors"]))

    def test_r1_06_unsupported_temporal_basis_fails(self) -> None:
        documents = load_documents()
        assertions(documents)[0]["temporal_basis"] = "PUBLICATION_DATE_1911"
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[UNSUPPORTED_TEMPORAL_BASIS]" in error for error in result["errors"]))

    def test_r1_07_observation_period_invalid_fails(self) -> None:
        documents = load_documents()
        target = assertions(documents)[0]
        target["observation_from"] = "1901-01-01"
        target["observation_to"] = "1900-01-01"
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[INVALID_OBSERVATION_PERIOD]" in error for error in result["errors"]))

    def test_r1_08_calibration_references_unknown_assertion_fails(self) -> None:
        documents = load_documents()
        documents["calibration"]["calibration_records"][0]["source_assertion_ids"] = ["missing_assertion_id"]
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[UNKNOWN_SOURCE_ASSERTION_ID]" in error for error in result["errors"]))

    def test_r1_09_ordinal_prior_used_as_direct_physical_capacity_fails(self) -> None:
        documents = load_documents()
        documents["calibration"]["calibration_records"][0]["calibration_role"] = "DIRECT_PHYSICAL_PRODUCTION_CAPACITY"
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[ORDINAL_PRIOR_AS_DIRECT_CAPACITY]" in error for error in result["errors"]))

    def test_r1_10_unresolved_commodity_or_sector_compatibility_fails(self) -> None:
        documents = load_documents()
        documents["compatibility"]["concepts"] = [
            concept
            for concept in documents["compatibility"]["concepts"]
            if concept["compatibility_key"] != "commodity:potatoes"
        ]
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[UNRESOLVED_COMPATIBILITY_REFERENCE]" in error for error in result["errors"]))

    def test_r1_11_publication_date_does_not_become_observation_date(self) -> None:
        documents = load_documents()
        target = next(assertion for assertion in assertions(documents) if assertion["temporal_basis"] == "RETROSPECTIVE_BUT_APPLICABLE")
        original_period = (target["observation_from"], target["observation_to"])
        source = next(source for source in documents["sources"]["sources"] if source["source_id"] == target["source_ids"][0])
        source["publication_date"] = "1900-01-01"
        result = validate(documents)
        self.assertTrue(result["valid"], result["errors"])
        self.assertEqual((target["observation_from"], target["observation_to"]), original_period)

    def test_r1_12_different_scoped_footprints_are_allowed_in_one_region(self) -> None:
        documents = load_documents()
        pilot = next(record for record in documents["evidence"]["evidence_records"] if record["economic_region_id"] == "economic_region_bengal_delta_jute_rice_1900")
        jute = next(assertion for assertion in pilot["assertions"] if assertion["claim_kind"] == "AGRICULTURAL_PROFILE" and assertion["subject_id"] == "jute")
        coal = next(assertion for assertion in pilot["assertions"] if assertion["claim_kind"] == "EXTRACTION_PROFILE" and assertion["subject_id"] == "coal")
        self.assertNotEqual(
            {membership["spatial_region_id"] for membership in jute["spatial_memberships"]},
            {membership["spatial_region_id"] for membership in coal["spatial_memberships"]},
        )
        result = validate(documents)
        self.assertTrue(result["valid"], result["errors"])

    def test_r1_13_crosswalk_estimate_is_distinguished_from_measurement(self) -> None:
        documents = load_documents()
        membership = next(
            membership
            for assertion in assertions(documents)
            for membership in assertion["spatial_memberships"]
            if membership["allocation_basis"] == "CROSSWALK_ESTIMATE"
        )
        self.assertFalse(membership["is_historical_measurement"])
        self.assertIn("Crosswalk estimate", membership["notes"])
        membership["is_historical_measurement"] = True
        result = validate(documents)
        self.assertFalse(result["valid"])
        self.assertTrue(any("[CROSSWALK_MARKED_HISTORICAL_MEASUREMENT]" in error for error in result["errors"]))

    def test_r1_14_reordered_inputs_remain_deterministic(self) -> None:
        documents = load_documents()
        reordered = copy.deepcopy(documents)
        reordered["sources"]["sources"].reverse()
        reordered["compatibility"]["concepts"].reverse()
        reordered["calibration"]["calibration_records"].reverse()
        reordered["evidence"]["evidence_records"].reverse()
        for record in reordered["evidence"]["evidence_records"]:
            record["assertions"].reverse()
        first = validate(documents)
        second = validate(reordered)
        self.assertEqual(first["valid"], second["valid"])
        self.assertEqual(first["summary"], second["summary"])
        self.assertEqual(first["errors"], second["errors"])

    def test_all_ordinal_records_are_prior_locked(self) -> None:
        documents = load_documents()
        for record in documents["calibration"]["calibration_records"]:
            self.assertEqual(record["calibration_role"], "EVIDENCE_PRIOR_ONLY")
            self.assertEqual(record["runtime_usage"], "NONE")
            self.assertEqual(record["canonical_unit"], "ordinal_capacity_index_0_5")
        self.assertTrue(validate(documents)["valid"])

    def test_pilot_corrections_are_absent_from_assertion_set(self) -> None:
        documents = load_documents()
        by_region = {
            record["economic_region_id"]: record["assertions"]
            for record in documents["evidence"]["evidence_records"]
        }
        self.assertNotIn(
            "coke_production",
            {assertion["subject_id"] for assertion in by_region["economic_region_ruhr_coal_steel_1900"]},
        )
        self.assertNotIn(
            "coke_production",
            {assertion["subject_id"] for assertion in by_region["economic_region_donbas_coal_metals_1900"]},
        )
        self.assertNotIn(
            "copper_ore",
            {
                assertion["subject_id"]
                for assertion in by_region["economic_region_south_wales_coalfield_1900"]
                if assertion["claim_kind"] in {"RESOURCE_ENDOWMENT", "EXTRACTION_PROFILE"}
            },
        )
        self.assertNotIn(
            "food_processing",
            {assertion["subject_id"] for assertion in by_region["economic_region_bengal_delta_jute_rice_1900"]},
        )

    def test_schema_documents_are_valid_json(self) -> None:
        schema_dir = ROOT / "data/economic_geography/schema"
        for schema_path in sorted(schema_dir.glob("*.json")):
            with self.subTest(schema=schema_path.name):
                json.loads(schema_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
