#!/usr/bin/env python3
"""Focused tests for non-authoritative Batch 3 review candidates."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools.world_names.review_candidates import (  # noqa: E402
    build_review_artifacts,
    benchmark_build,
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
        self.assertEqual(len(candidates), 727)
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
            ),
            [],
        )

    def test_benchmark_can_be_disabled_for_fast_fixture_runs(self) -> None:
        benchmark = benchmark_build(REPOSITORY_ROOT, repetitions=0)
        self.assertTrue(benchmark["skipped"])


if __name__ == "__main__":
    unittest.main()