#!/usr/bin/env python3
"""Tests for the WWO world-name inventory and alias candidate builder."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools.world_names.world_names import (  # noqa: E402
    NORMALIZER_ID,
    build_alias_records,
    build_artifacts,
    build_collision_report,
    build_search_index,
    normalize_name,
    validate_artifacts,
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

    def test_repository_build_is_valid_and_contains_required_entity_classes(self) -> None:
        artifacts = build_artifacts(REPOSITORY_ROOT)
        self.assertEqual(artifacts["validation_errors"], [])
        entity_types = {entity["entity_type"] for entity in artifacts["inventory"]["entities"]}
        self.assertTrue({"character", "organization", "institution", "city", "region", "country", "port"} <= entity_types)
        self.assertGreater(len(artifacts["collision_report"]["normalized_collisions"]), 0)
        self.assertGreater(len(artifacts["search_index"]["entries"]), 0)


if __name__ == "__main__":
    unittest.main()
