#!/usr/bin/env python3
"""Focused tests for non-authoritative Batch 3 review candidates."""

from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools.world_names.review_candidates import (  # noqa: E402
    build_review_artifacts,
    benchmark_build,
    replay_review_candidates,
    validate_review_candidates,
)


class ReviewCandidateTests(unittest.TestCase):
    def test_name_observation_pointers_are_source_stable(self) -> None:
        from tools.world_names.review_candidates import _iter_name_observations

        observations = list(
            _iter_name_observations(
                {"cities": [{"name": "Alpha", "aliases": ["A", "A-city"]}]}
            )
        )
        pointers = {item[2] for item in observations}
        self.assertEqual(
            pointers,
            {"$/cities[0]/name", "$/cities[0]/aliases[0]", "$/cities[0]/aliases[1]"},
        )

    def test_repository_candidates_are_non_authoritative_and_valid(self) -> None:
        artifacts = build_review_artifacts(REPOSITORY_ROOT, benchmark_repetitions=0)
        self.assertEqual(artifacts["validation_errors"], [])
        candidates = artifacts["review_candidates"]["candidates"]
        self.assertEqual(
            len(candidates),
            artifacts["review_candidates"]["summary"]["candidate_count"],
        )
        self.assertGreater(len(candidates), 0)
        self.assertTrue(
            all(
                item["entity_id_kind"] == "source_record_key"
                and item["authority"] == "non_authoritative"
                and item["candidate_id"].startswith("source:")
                for item in candidates
            )
        )
        self.assertEqual(
            validate_review_candidates(
                artifacts["review_candidates"],
                artifacts["collision_ledger"],
                artifacts["base"]["coverage_manifest"],
                root=REPOSITORY_ROOT,
            ),
            [],
        )



    def test_negative_mutations_are_rejected_independently(self) -> None:
        artifacts = build_review_artifacts(REPOSITORY_ROOT, benchmark_repetitions=0)
        candidate_doc = artifacts["review_candidates"]
        ledger = artifacts["collision_ledger"]
        coverage = artifacts["base"]["coverage_manifest"]

        cases = []
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["authority"] = "authoritative"
        cases.append(("candidate authority tampering", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["source_file"] = "data/missing.json"
        cases.append(("missing source file", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["source_field"] = "name_missing"
        cases.append(("missing source field", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["alias"] = "tampered"
        cases.append(("source value mismatch", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["valid_from"] = "not-a-date"
        cases.append(("malformed date", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        del mutated["candidates"][0]["source_sha256"]
        cases.append(("malformed evidence", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"].append(copy.deepcopy(mutated["candidates"][0]))
        cases.append(("duplicate candidate ID", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["entity_id"] = "stable_id:wrong"
        cases.append(("stable ID mismatch", mutated, ledger))
        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["normalized_name"] = "same-looking-but-unsupported"
        cases.append(("normalization-only equality", mutated, ledger))

        for label, mutated_doc, mutated_ledger in cases:
            with self.subTest(label=label):
                errors = validate_review_candidates(
                    mutated_doc,
                    mutated_ledger,
                    coverage,
                    root=REPOSITORY_ROOT,
                )
                self.assertTrue(errors, label)

        mutated = copy.deepcopy(ledger)
        mutated["collisions"][0]["candidate_ids"] = ["missing-member", *mutated["collisions"][0]["candidate_ids"][1:]]
        self.assertTrue(
            validate_review_candidates(candidate_doc, mutated, coverage, root=REPOSITORY_ROOT)
        )

        mutated = copy.deepcopy(candidate_doc)
        mutated["candidates"][0]["alias"] = "stale-artifact"
        self.assertTrue(replay_review_candidates(REPOSITORY_ROOT, mutated, coverage))

        self.assertEqual(replay_review_candidates(REPOSITORY_ROOT, candidate_doc, {"files": []}), [])

        malformed = copy.deepcopy(candidate_doc)
        malformed["unexpected"] = True
        self.assertTrue(
            validate_review_candidates(malformed, ledger, coverage, root=REPOSITORY_ROOT)
        )

    def test_source_pointer_missing_and_changed_source_are_rejected(self) -> None:
        artifacts = build_review_artifacts(REPOSITORY_ROOT, benchmark_repetitions=0)
        candidate = copy.deepcopy(artifacts["review_candidates"])
        source = candidate["candidates"][0]["source"]
        candidate["candidates"][0]["source"] = source.rsplit("/", 1)[0] + "/missing"
        candidate["candidates"][0]["candidate_id"] = candidate["candidates"][0]["entity_id"] = (
            "source:" + candidate["candidates"][0]["source_file"] + "#" + candidate["candidates"][0]["source"].split("#", 1)[1]
        )
        self.assertTrue(
            validate_review_candidates(
                candidate,
                artifacts["collision_ledger"],
                artifacts["base"]["coverage_manifest"],
                root=REPOSITORY_ROOT,
            )
        )

        with tempfile.TemporaryDirectory() as directory:
            temp_root = Path(directory)
            source_file = artifacts["base"]["coverage_manifest"]["files"][0]["source_file"]
            source_path = REPOSITORY_ROOT / source_file
            temp_path = temp_root / source_file
            temp_path.parent.mkdir(parents=True, exist_ok=True)
            temp_path.write_bytes(source_path.read_bytes() + b" ")
            coverage = {"files": [next(row for row in artifacts["base"]["coverage_manifest"]["files"] if row["source_file"] == source_file)]}
            source_doc = {
                "schema_version": 1,
                "normalizer_id": "test",
                "policy": {},
                "summary": {},
                "candidates": [],
            }
            self.assertTrue(
                replay_review_candidates(temp_root, source_doc, coverage)
            )

    def test_benchmark_can_be_disabled_for_fast_fixture_runs(self) -> None:
        benchmark = benchmark_build(REPOSITORY_ROOT, repetitions=0)
        self.assertTrue(benchmark["skipped"])


if __name__ == "__main__":
    unittest.main()