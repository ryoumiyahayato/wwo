#!/usr/bin/env python3
"""Focused tests for the committed world-name staging validator."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools.world_names.validate_staged import (  # noqa: E402
    build_artifact_manifest,
    validate_staged,
)


class StagedValidatorTests(unittest.TestCase):
    def test_committed_staging_replays_without_rebuild(self) -> None:
        self.assertEqual(validate_staged(REPOSITORY_ROOT), [])

    def test_manifest_has_expected_structural_scope(self) -> None:
        manifest = build_artifact_manifest(REPOSITORY_ROOT, [])
        self.assertEqual(manifest["summary"]["artifact_file_count"], 10)
        self.assertEqual(manifest["summary"]["coverage_source_file_count"], 224)
        self.assertEqual(manifest["summary"]["review_candidate_count"], 727)
        self.assertEqual(manifest["validation"]["status"], "PASS")


if __name__ == "__main__":
    unittest.main()