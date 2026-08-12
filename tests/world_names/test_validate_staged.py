#!/usr/bin/env python3
"""Focused tests for the committed world-name staging validator."""

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

from tools.world_names.validate_staged import (  # noqa: E402
    ARTIFACT_SPECS,
    build_artifact_manifest,
    validate_artifact_manifest,
    validate_staged,
)


class StagedValidatorTests(unittest.TestCase):
    def test_committed_staging_replays_without_rebuild(self) -> None:
        self.assertEqual(validate_staged(REPOSITORY_ROOT), [])



    def test_manifest_and_artifact_negative_mutations_are_rejected(self) -> None:
        manifest = build_artifact_manifest(REPOSITORY_ROOT, [])
        bad_hash = copy.deepcopy(manifest)
        bad_hash["files"][0]["sha256"] = "0" * 64
        self.assertTrue(validate_artifact_manifest(REPOSITORY_ROOT, bad_hash))

        missing = copy.deepcopy(manifest)
        missing["files"] = missing["files"][1:]
        self.assertNotEqual(missing["files"], manifest["files"])

        unexpected = copy.deepcopy(manifest)
        unexpected["files"].append({
            "path": "data/staging/world_names/unexpected.json",
            "role": "unexpected",
            "bytes": 1,
            "sha256": "0" * 64,
            "schema_version": 1,
            "record_count": 0,
        })
        self.assertNotEqual(unexpected, manifest)

        with tempfile.TemporaryDirectory() as directory:
            temp_root = Path(directory)
            staging = temp_root / "data/staging/world_names"
            staging.mkdir(parents=True)
            (staging / "artifact_manifest.json").write_text("{}\n", encoding="utf-8")
            errors = validate_staged(temp_root)
            self.assertTrue(any("missing artifact" in error for error in errors))

        with tempfile.TemporaryDirectory() as directory:
            temp_root = Path(directory)
            errors = validate_staged(temp_root)
            self.assertTrue(any("required artifact manifest is missing" in error for error in errors))

    def test_unexpected_artifact_is_rejected(self) -> None:
        import tools.world_names.validate_staged as module

        artifact_root = REPOSITORY_ROOT / "data/staging/world_names"
        unexpected = artifact_root / "unexpected_negative_fixture.json"
        try:
            unexpected.write_text("{}\n", encoding="utf-8")
            errors = validate_staged(REPOSITORY_ROOT)
            self.assertTrue(any("unexpected staged artifacts" in error for error in errors))
        finally:
            if unexpected.exists():
                unexpected.unlink()

    def test_manifest_has_expected_structural_scope(self) -> None:
        manifest = build_artifact_manifest(REPOSITORY_ROOT, [])
        coverage = json.loads(
            (REPOSITORY_ROOT / "data/staging/world_names/coverage_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        inventory = json.loads(
            (REPOSITORY_ROOT / "data/staging/world_names/name_inventory.json").read_text(
                encoding="utf-8"
            )
        )
        aliases = json.loads(
            (REPOSITORY_ROOT / "data/staging/world_names/aliases.json").read_text(
                encoding="utf-8"
            )
        )
        candidates = json.loads(
            (REPOSITORY_ROOT / "data/staging/world_names/review_candidates.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            manifest["summary"]["artifact_file_count"],
            len(ARTIFACT_SPECS),
        )
        self.assertEqual(manifest["summary"]["entity_count"], len(inventory["entities"]))
        self.assertEqual(manifest["summary"]["review_candidate_count"], len(candidates["candidates"]))
        self.assertEqual(manifest["summary"]["record_counts"]["aliases.json"], len(aliases["aliases"]))
        self.assertEqual(manifest["summary"]["record_counts"]["review_candidates.json"], len(candidates["candidates"]))
        self.assertEqual(manifest["policy"]["observational_benchmark_excluded"], True)
        self.assertEqual(manifest["validation"]["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
