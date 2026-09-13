#!/usr/bin/env python3
"""Regression coverage for the Historical Provenance source-byte contract."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import unittest
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = ROOT / "tools" / "provenance" / "generate_historical_provenance.py"
SPEC = importlib.util.spec_from_file_location("historical_provenance_generator", GENERATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load Historical Provenance generator")
generator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generator
SPEC.loader.exec_module(generator)

GENERATED_PATHS = (
    "data/provenance/historical_source_registry.json",
    "data/provenance/historical_fact_evidence.json",
)


def repo_path(resource_path: str) -> Path:
    return ROOT / resource_path.removeprefix("res://")


def git_attributes(paths: list[str]) -> dict[str, dict[str, str]]:
    completed = subprocess.run(
        ["git", "check-attr", "text", "eol", "--", *paths],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    result: dict[str, dict[str, str]] = defaultdict(dict)
    for line in completed.stdout.splitlines():
        path, attribute, value = line.split(": ", 2)
        result[path][attribute] = value
    return dict(result)


class HistoricalProvenanceEolContractTest(unittest.TestCase):
    def test_admitted_text_sources_have_effective_lf_policy(self) -> None:
        paths = [
            path.removeprefix("res://")
            for path in sorted(generator.CANONICAL_TEXTUAL_PROVENANCE_SOURCES)
        ]
        attributes = git_attributes(paths)
        self.assertEqual(set(attributes), set(paths))
        for path in paths:
            self.assertEqual(attributes[path].get("text"), "set", path)
            self.assertEqual(attributes[path].get("eol"), "lf", path)
            self.assertNotIn(b"\r", (ROOT / path).read_bytes(), path)

    def test_generated_provenance_has_separate_lf_formatting_policy(self) -> None:
        attributes = git_attributes(list(GENERATED_PATHS))
        self.assertEqual(set(attributes), set(GENERATED_PATHS))
        for path in GENERATED_PATHS:
            self.assertEqual(attributes[path].get("text"), "set", path)
            self.assertEqual(attributes[path].get("eol"), "lf", path)
            self.assertNotIn(b"\r", (ROOT / path).read_bytes(), path)

    def test_generator_rejects_crlf_for_admitted_text_but_not_future_binary(self) -> None:
        sample = b'{\r\n  "schema": 1\r\n}\r\n'
        with self.assertRaisesRegex(
            generator.ProvenanceSourceContractError,
            "provenance source checkout violates canonical LF contract",
        ):
            generator.validate_provenance_source_bytes(generator.POPULATION_PATH, sample)
        self.assertEqual(
            generator.validate_provenance_source_bytes(
                "res://data/provenance/future_binary_source.bin", sample
            ),
            sample,
        )

    def test_registry_hashes_are_exact_canonical_checked_out_bytes(self) -> None:
        registry, _ = generator.build()
        self.assertEqual(len(registry["sources"]), 3)
        for source in registry["sources"]:
            locator = source["locator"]
            raw = repo_path(locator).read_bytes()
            self.assertNotIn(b"\r", raw, locator)
            self.assertEqual(source["content_hash"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(source["content_hash"], generator.file_sha256(locator))

    def test_catalog_shape_review_statuses_and_source_values_are_unchanged(self) -> None:
        registry, catalog = generator.build()
        facts = catalog["facts"]
        self.assertEqual(len(registry["sources"]), 3)
        self.assertEqual(len(facts), 202)
        self.assertEqual(
            Counter(fact["domain"] for fact in facts),
            Counter(
                {
                    "political_identity": 151,
                    "population_aggregate": 50,
                    "spatial_boundary": 1,
                }
            ),
        )
        statuses: dict[str, set[str]] = defaultdict(set)
        for fact in facts:
            statuses[fact["domain"]].add(fact["review_status"])
        self.assertEqual(statuses["political_identity"], {"EVIDENCE_LINKED"})
        self.assertEqual(statuses["population_aggregate"], {"BOUNDED_ESTIMATE"})
        self.assertEqual(statuses["spatial_boundary"], {"EVIDENCE_LINKED"})

        facts_by_id = {fact["fact_id"]: fact for fact in facts}
        political = json.loads(repo_path(generator.POLITICAL_PATH).read_text(encoding="utf-8"))
        for unit in political["units"]:
            expected = {
                "controller_id": unit["controller_id"],
                "geometry_feature_id": unit["geometry_feature_id"],
                "id": unit["id"],
                "relationship": unit["relationship"],
                "source_name": unit["source_name"],
                "status": unit["status"],
                "valid_from": unit["valid_from"],
                "valid_to": unit["valid_to"],
            }
            fact = facts_by_id[f"political_identity:{unit['id']}"]
            self.assertEqual(fact["value"], expected)

        population = json.loads(repo_path(generator.POPULATION_PATH).read_text(encoding="utf-8"))
        indexes = {name: index for index, name in enumerate(population["field_order"])}
        for row in population["rows"]:
            entity_id = row[indexes["entity_id"]]
            fact = facts_by_id[f"population_aggregate:population:{entity_id}"]
            self.assertEqual(fact["value"], row[indexes["population_value"]])
            self.assertEqual(fact["lower_bound"], row[indexes["population_lower"]])
            self.assertEqual(fact["upper_bound"], row[indexes["population_upper"]])
            self.assertEqual(
                fact["confidence"], row[indexes["population_confidence_bp"]] / 10_000.0
            )

        spatial = json.loads(repo_path(generator.SPATIAL_PATH).read_text(encoding="utf-8"))
        spatial_fact = facts_by_id["spatial_boundary:world_boundaries_1900_03_12"]
        self.assertEqual(
            spatial_fact["value"],
            {
                "feature_count": spatial["feature_count"],
                "provider": spatial["provider"],
                "snapshot_date": spatial["snapshot_date"],
                "upstream_content_hash": spatial["source"]["source_sha256"],
            },
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
