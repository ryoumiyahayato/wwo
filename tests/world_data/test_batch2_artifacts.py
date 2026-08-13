#!/usr/bin/env python3
"""Focused tests for deterministic Batch 2 manifests and asset staging."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPOSITORY_ROOT / "tools" / "world_data" / "build_batch2_artifacts.py"


def load_tool() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wwo_batch2_artifacts", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load Batch 2 artifact tool: {TOOL_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


batch2 = load_tool()


class Batch2ArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data_manifest = batch2.build_data_manifest(REPOSITORY_ROOT)
        cls.asset_manifest = batch2.build_asset_manifest(REPOSITORY_ROOT)
        cls.regression_manifest = batch2.build_regression_manifest(REPOSITORY_ROOT)

    def test_data_manifest_covers_all_json_without_parse_errors(self) -> None:
        self.assertEqual(self.data_manifest["file_count"], 184)
        self.assertEqual(self.data_manifest["parse_errors"], [])
        self.assertEqual(len(self.data_manifest["files"]), 184)
        self.assertEqual(len(self.data_manifest["dataset_sha256"]), 64)

    def test_historical_flag_assets_match_referenced_hashes(self) -> None:
        self.assertEqual(self.asset_manifest["record_count"], 61)
        self.assertEqual(self.asset_manifest["referenced_asset_count"], 60)
        self.assertEqual(self.asset_manifest["asset_file_count"], 60)
        self.assertEqual(len(self.asset_manifest["verified_reference_ids"]), 60)
        self.assertEqual(self.asset_manifest["missing_assets"], [])
        self.assertEqual(self.asset_manifest["hash_mismatches"], [])
        self.assertEqual(self.asset_manifest["dimension_mismatches"], [])
        self.assertEqual(self.asset_manifest["orphan_assets"], [])
        self.assertEqual(self.asset_manifest["rendered_dimension_counts"], {"288x192": 60})

    def test_regression_manifest_is_machine_readable(self) -> None:
        fixture = REPOSITORY_ROOT / self.regression_manifest["fixture"]
        loaded = json.loads(fixture.read_text(encoding="utf-8"))
        self.assertEqual(self.regression_manifest["case_count"], 6)
        self.assertEqual(self.regression_manifest["case_ids"], [case["id"] for case in loaded["cases"]])
        self.assertEqual(len(self.regression_manifest["fixture_sha256"]), 64)

    def test_asset_staging_contains_only_verified_references(self) -> None:
        staging = batch2.build_asset_staging(self.asset_manifest)
        self.assertFalse(staging["authoritative_source_modified"])
        self.assertEqual(len(staging["entries"]), 60)
        self.assertTrue(all(entry["asset_path"].startswith("res://assets/historical_flags/1900/") for entry in staging["entries"]))
        self.assertTrue(all(len(entry["sha256"]) == 64 for entry in staging["entries"]))

    def test_manifests_are_deterministic(self) -> None:
        self.assertEqual(self.data_manifest, batch2.build_data_manifest(REPOSITORY_ROOT))
        self.assertEqual(self.asset_manifest, batch2.build_asset_manifest(REPOSITORY_ROOT))
        self.assertEqual(self.regression_manifest, batch2.build_regression_manifest(REPOSITORY_ROOT))

    def test_changed_asset_hash_is_reported_in_an_independent_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_path = root / "data" / "world_map" / "historical"
            asset_path = root / "assets" / "historical_flags" / "1900" / "flag.png"
            data_path.mkdir(parents=True)
            asset_path.parent.mkdir(parents=True)
            asset_path.write_bytes(b"not-a-real-png-but-a-stable-asset")
            (data_path / "flags_1900.json").write_text(
                json.dumps(
                    {
                        "records": {
                            "flag_a": {
                                "asset_path": "res://assets/historical_flags/1900/flag.png",
                                "asset_sha256": "0" * 64,
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            manifest = batch2.build_asset_manifest(root)
        self.assertEqual(manifest["hash_mismatches"], ["flag_a"])
        self.assertEqual(manifest["missing_assets"], [])

    def test_data_manifest_normalizes_checkout_line_endings(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data_root = root / "data" / "world_map"
            data_root.mkdir(parents=True)
            source = data_root / "countries.json"
            source.write_bytes(b'{\r\n  "countries": []\r\n}\r\n')
            crlf_manifest = batch2.build_data_manifest(root)
            source.write_bytes(b'{\n  "countries": []\n}\n')
            lf_manifest = batch2.build_data_manifest(root)
        self.assertEqual(crlf_manifest, lf_manifest)
        self.assertEqual(lf_manifest["files"][0]["bytes"], len(b'{\n  "countries": []\n}\n'))


if __name__ == "__main__":
    unittest.main()
