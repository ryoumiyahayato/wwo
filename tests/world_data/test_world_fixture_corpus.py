"""Focused tests for the Batch 1 world-data golden fixture corpus."""

from __future__ import annotations

import json
import unittest

from tools.world_fixture import canonical_hash, canonical_json, load_corpus, materialize_fixture, validate_fixture
from tools.world_fixture.corpus import DOCUMENT_COLLECTIONS


class WorldFixtureCorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.corpus = load_corpus()
        cls.fixtures = {item["fixture_id"]: item for item in cls.corpus["fixtures"]}

    def test_corpus_has_required_valid_invalid_and_warning_coverage(self) -> None:
        categories = {item["category"] for item in self.fixtures.values()}
        self.assertTrue({"minimal_valid_hierarchy", "port_shipping", "road_graph", "rail_graph", "multimodal_transport"} <= categories)
        self.assertTrue({"historical_entity", "organization_institution_relation", "geometry_metadata", "names_alias_collision"} <= categories)
        self.assertEqual(sum(item["classification"] == "VALID" for item in self.fixtures.values()), 8)
        self.assertEqual(sum(item["classification"] == "INVALID" for item in self.fixtures.values()), 8)
        self.assertEqual(sum(item["classification"] == "WARNING" for item in self.fixtures.values()), 1)

    def test_fixture_documents_are_loader_shaped_json_objects(self) -> None:
        for fixture_id in self.fixtures:
            documents = materialize_fixture(self.corpus, fixture_id)
            self.assertTrue(documents, fixture_id)
            for dataset, document in documents.items():
                self.assertIsInstance(document, dict, dataset)
                self.assertIn(DOCUMENT_COLLECTIONS[dataset], document, dataset)

    def test_expected_results_and_codes_replay(self) -> None:
        for fixture_id, fixture in self.fixtures.items():
            findings = validate_fixture(materialize_fixture(self.corpus, fixture_id))
            result = "INVALID" if any(item["severity"] == "ERROR" for item in findings) else "WARNING" if findings else "VALID"
            codes = sorted({item["code"] for item in findings})
            self.assertEqual(result, fixture["expected"]["result"], fixture_id)
            self.assertEqual(codes, sorted(fixture["expected"]["codes"]), fixture_id)

    def test_malformed_cases_are_single_controlled_defects(self) -> None:
        for fixture in self.fixtures.values():
            if fixture["classification"] != "INVALID":
                continue
            findings = validate_fixture(materialize_fixture(self.corpus, fixture["fixture_id"]))
            self.assertEqual(len(findings), 1, fixture["fixture_id"])
            self.assertEqual(findings[0]["code"], fixture["expected"]["codes"][0], fixture["fixture_id"])

    def test_canonical_serialization_and_hash_replay_are_deterministic(self) -> None:
        for fixture_id in self.fixtures:
            materialized = materialize_fixture(self.corpus, fixture_id)
            first = canonical_json(materialized)
            second = canonical_json(json.loads(first))
            self.assertEqual(first, second, fixture_id)
            self.assertEqual(canonical_hash(materialized), canonical_hash(json.loads(first)), fixture_id)

    def test_provenance_is_present_and_production_tree_is_not_referenced_as_output(self) -> None:
        self.assertEqual(self.corpus["source"]["master_sha"], "4b738ab8b0a21e8685aae95381717e9efd2327a8")
        for fixture in self.fixtures.values():
            self.assertTrue(fixture.get("provenance", {}).get("transform"), fixture["fixture_id"])
            self.assertNotIn("data/world_map", json.dumps(fixture.get("documents", {})))


if __name__ == "__main__":
    unittest.main()
