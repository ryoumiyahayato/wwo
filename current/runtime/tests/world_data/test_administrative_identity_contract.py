"""Fail-closed source admission checks for the partial historical identity sample."""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("admin_provenance", ROOT / "tools/provenance/generate_historical_provenance.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AdministrativeIdentityContractTest(unittest.TestCase):
    def setUp(self):
        self.document = MODULE.read_json(MODULE.FRANCE_ADMIN_PATH)
        self.polities = {"country_fra"}
        self.places = {"place:paris", "place:versailles"}

    def validate(self, document):
        MODULE.validate_france_administrative_identity(document, self.polities, self.places)

    def test_admitted_identity_only(self):
        self.validate(self.document)
        self.assertEqual([row["historical_name"] for row in self.document["units"]], ["Seine", "Seine-et-Oise"])

    def test_invalid_scope_references_and_duplicates_fail(self):
        variants = []
        for field, value in [("entity_id", "german_empire"), ("valid_to", "1899-01-01"), ("geometry_status", "ADMITTED"), ("membership_status", "COMPLETE")]:
            document = copy.deepcopy(self.document)
            document[field] = value
            variants.append(document)
        for field, value in [("capital_place_id", "admin_place:paris"), ("source_ids", ["unknown_source"]), ("polity_id", "state:missing"), ("level", True), ("members", ["territory_unit:x"]), ("geometry", {"type": "Polygon"})]:
            document = copy.deepcopy(self.document)
            document["units"][0][field] = value
            variants.append(document)
        document = copy.deepcopy(self.document)
        document["units"][1]["id"] = document["units"][0]["id"]
        variants.append(document)
        for document in variants:
            with self.subTest(document=document), self.assertRaises(MODULE.ProvenanceSourceContractError):
                self.validate(document)

    def test_generated_fact_is_bound_to_full_semantic_content(self):
        registry, catalog = MODULE.build()
        fact = next(row for row in catalog["facts"] if row["fact_id"] == "administrative_identity:france_administrative_identity_1900")
        self.assertEqual(fact["value"], self.document)
        self.assertEqual(fact["review_status"], "VERIFIED")
        source = next(row for row in registry["sources"] if row["source_id"] == fact["source_id"])
        self.assertEqual(source["access_metadata"]["geometry_admission"], "NONE")


if __name__ == "__main__":
    unittest.main()
