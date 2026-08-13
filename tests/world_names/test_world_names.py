#!/usr/bin/env python3
"""Tests for the WWO world-name inventory and alias candidate builder."""

from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools.world_names import normalize_name as package_normalize_name  # noqa: E402
from tools.world_names import world_names as package_module  # noqa: E402
from tools.world_names.world_names import (  # noqa: E402
    NORMALIZER_ID,
    build_alias_records,
    build_artifacts,
    build_collision_report,
    build_search_index,
    normalize_name,
    validate_artifacts,
    validate_coverage_manifest,
    validate_deterministic_corpus,
)

def minimal_inventory() -> dict:
    return {
        "schema_version": 1,
        "normalizer_id": NORMALIZER_ID,
        "entities": [
            {
                "entity_id": "city_alpha",
                "entity_id_kind": "stable_id",
                "entity_type": "city",
                "canonical_current_name": "Alpha",
                "existing_display_names": ["Alpha"],
                "existing_aliases": [],
                "source_files": ["fixture.json"],
                "historical_period": "current",
                "name_records": [
                    {
                        "value": "Alpha",
                        "field": "name",
                        "name_kind": "canonical",
                        "alias_type": "official",
                        "language": "und",
                        "script": "Latn",
                        "valid_from": None,
                        "valid_to": None,
                        "source": "fixture.json#$.cities[0]/name",
                        "source_file": "fixture.json",
                        "source_class": "current",
                        "historical_period": "current",
                        "confidence": "high",
                    }
                ],
            },
            {
                "entity_id": "city_beta",
                "entity_id_kind": "stable_id",
                "entity_type": "city",
                "canonical_current_name": "alpha",
                "existing_display_names": ["alpha"],
                "existing_aliases": [],
                "source_files": ["fixture.json"],
                "historical_period": "current",
                "name_records": [
                    {
                        "value": "alpha",
                        "field": "name",
                        "name_kind": "canonical",
                        "alias_type": "official",
                        "language": "und",
                        "script": "Latn",
                        "valid_from": None,
                        "valid_to": None,
                        "source": "fixture.json#$.cities[1]/name",
                        "source_file": "fixture.json",
                        "source_class": "current",
                        "historical_period": "current",
                        "confidence": "high",
                    }
                ],
            },
        ],
    }


class PackageImportTests(unittest.TestCase):
    def test_lazy_package_exports_resolve_without_recursion(self) -> None:
        self.assertEqual(package_module.__name__, "tools.world_names.world_names")
        self.assertEqual(package_normalize_name("Alpha"), "alpha")

class NormalizationTests(unittest.TestCase):
    def test_normalization_handles_width_case_punctuation_and_whitespace(self) -> None:
        self.assertEqual(normalize_name("  Ａlpha—Beta  "), "alpha beta")
        self.assertEqual(normalize_name("Alpha Beta"), "alpha beta")
        self.assertNotEqual("  Ａlpha—Beta  ", "alpha beta")

    def test_normalization_does_not_translate_or_strip_script_content(self) -> None:
        self.assertEqual(normalize_name("Köln"), "köln")
        self.assertEqual(normalize_name("北京"), "北京")


class ArtifactTests(unittest.TestCase):
    def test_index_preserves_one_to_many_mapping(self) -> None:
        inventory = minimal_inventory()
        aliases = build_alias_records(inventory)
        index = build_search_index(aliases, inventory)
        alpha = next(entry for entry in index["entries"] if entry["normalized_name"] == "alpha")
        self.assertEqual(alpha["entity_ids"], ["city_alpha", "city_beta"])

        collisions = build_collision_report(inventory, aliases)
        self.assertEqual(collisions["summary"]["normalized_collisions"], 1)

    def test_validator_rejects_inverted_date_range(self) -> None:
        inventory = minimal_inventory()
        aliases = build_alias_records(inventory)
        aliases["aliases"][0]["valid_from"] = "1910-01-01"
        aliases["aliases"][0]["valid_to"] = "1900-01-01"
        index = build_search_index(aliases, inventory)
        collisions = build_collision_report(inventory, aliases)
        errors = validate_artifacts(inventory, aliases, collisions, index)
        self.assertTrue(any("inverted date range" in error for error in errors))


    def test_validator_rejects_duplicate_unknown_and_malformed_alias_records(self) -> None:
        inventory = minimal_inventory()
        aliases = build_alias_records(inventory)
        collisions = build_collision_report(inventory, aliases)
        index = build_search_index(aliases, inventory)

        duplicate_inventory = copy.deepcopy(inventory)
        duplicate_inventory["entities"][1]["entity_id"] = "city_alpha"
        duplicate_aliases = build_alias_records(duplicate_inventory)
        duplicate_errors = validate_artifacts(
            duplicate_inventory,
            duplicate_aliases,
            build_collision_report(duplicate_inventory, duplicate_aliases),
            build_search_index(duplicate_aliases, duplicate_inventory),
        )
        self.assertTrue(any("duplicate inventory entity_id" in error for error in duplicate_errors))

        unknown_aliases = copy.deepcopy(aliases)
        unknown_aliases["aliases"][0]["entity_id"] = "missing_entity"
        unknown_errors = validate_artifacts(
            inventory,
            unknown_aliases,
            collisions,
            build_search_index(unknown_aliases, inventory),
        )
        self.assertTrue(any("unknown entity_id" in error for error in unknown_errors))

        malformed_aliases = copy.deepcopy(aliases)
        del malformed_aliases["aliases"][0]["source_field"]
        malformed_errors = validate_artifacts(
            inventory,
            malformed_aliases,
            collisions,
            index,
        )
        self.assertTrue(any("invalid schema" in error for error in malformed_errors))

    def test_alias_source_replay_rejects_tampering_and_normalization_only_match(self) -> None:
        artifacts = build_artifacts(REPOSITORY_ROOT)
        aliases = copy.deepcopy(artifacts["aliases"])
        alias = next(item for item in aliases["aliases"] if item["script"] == "Latn")
        alias["alias"] = alias["alias"].upper()
        errors = validate_artifacts(
            artifacts["inventory"],
            aliases,
            artifacts["collision_report"],
            artifacts["search_index"],
            root=REPOSITORY_ROOT,
            coverage_manifest=artifacts["coverage_manifest"],
        )
        self.assertTrue(any("source value mismatch" in error for error in errors))

        missing_pointer = copy.deepcopy(artifacts["aliases"])
        missing_pointer["aliases"][0]["source"] = (
            missing_pointer["aliases"][0]["source"].split("#", 1)[0] + "#$.missing/path"
        )
        errors = validate_artifacts(
            artifacts["inventory"],
            missing_pointer,
            artifacts["collision_report"],
            artifacts["search_index"],
            root=REPOSITORY_ROOT,
            coverage_manifest=artifacts["coverage_manifest"],
        )
        self.assertTrue(any("source pointer cannot be replayed" in error for error in errors))

    def test_repository_build_is_valid_and_contains_required_entity_classes(self) -> None:
        artifacts = build_artifacts(REPOSITORY_ROOT)
        self.assertEqual(artifacts["validation_errors"], [])
        entity_types = {entity["entity_type"] for entity in artifacts["inventory"]["entities"]}
        self.assertTrue({"character", "organization", "institution", "city", "region", "country", "port"} <= entity_types)
        self.assertGreater(len(artifacts["collision_report"]["normalized_collisions"]), 0)
        self.assertGreater(len(artifacts["search_index"]["entries"]), 0)
        coverage = artifacts["coverage_manifest"]
        self.assertEqual(coverage["summary"]["parse_errors"], 0)
        self.assertGreaterEqual(coverage["summary"]["data_json_files_scanned"], 200)
        self.assertEqual(validate_coverage_manifest(coverage), [])
        self.assertEqual(artifacts["remaining_gaps"]["summary"]["parse_errors"], 0)
        self.assertEqual(
            validate_deterministic_corpus(
                artifacts["deterministic_corpus"],
                artifacts["inventory"],
                artifacts["aliases"],
                artifacts["collision_report"],
                artifacts["search_index"],
                coverage,
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
