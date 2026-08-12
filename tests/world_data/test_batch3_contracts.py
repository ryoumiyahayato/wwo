#!/usr/bin/env python3
"""Focused tests for Batch 3 loader, flag, and record contracts."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from types import ModuleType


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPOSITORY_ROOT / "tools" / "world_data" / "build_batch3_contracts.py"


def load_tool() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wwo_batch3_contracts", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load Batch 3 contract tool: {TOOL_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


batch3 = load_tool()


class Batch3ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.loader = batch3.build_loader_contract(REPOSITORY_ROOT)
        cls.flags = batch3.build_flag_coverage(REPOSITORY_ROOT)
        cls.signatures = batch3.build_record_signatures(REPOSITORY_ROOT)

    def test_loader_contract_has_no_missing_literal_paths(self) -> None:
        self.assertEqual(self.loader["contract_gate"], "PASS")
        self.assertEqual(self.loader["missing_direct_references"], [])
        self.assertEqual(self.loader["missing_directory_references"], [])
        self.assertGreaterEqual(len(self.loader["world_map_data_loader_entries"]), 16)

    def test_explicit_historical_flag_coverage_has_no_asset_gaps(self) -> None:
        self.assertEqual(self.flags["unit_count"], 151)
        self.assertEqual(self.flags["missing_flag_record_count"], 0)
        self.assertEqual(self.flags["missing_asset_count"], 0)
        self.assertEqual(self.flags["hash_mismatch_count"], 0)
        self.assertEqual(sum(self.flags["status_counts"].values()), 151)
        self.assertEqual(self.flags["status_counts"], {"DOCUMENTED_ABSENCE": 6, "VERIFIED_ASSET": 145})

    def test_record_signature_manifest_covers_all_json_and_surfaces_nested_candidates(self) -> None:
        self.assertEqual(self.signatures["data_json_count"], 183)
        self.assertEqual(self.signatures["duplicate_id_file_count"], 3)
        self.assertEqual(len(self.signatures["record_signature_digest"]), 64)
        candidate_paths = {row["path"] for row in self.signatures["files"] if row["duplicate_ids"]}
        self.assertEqual(
            candidate_paths,
            {
                "data/world_map/characters.json",
                "data/world_map/map_geometry_cache.json",
                "data/world_map/world_coastlines.json",
            },
        )

    def test_contracts_are_deterministic(self) -> None:
        self.assertEqual(self.loader, batch3.build_loader_contract(REPOSITORY_ROOT))
        self.assertEqual(self.flags, batch3.build_flag_coverage(REPOSITORY_ROOT))
        self.assertEqual(self.signatures, batch3.build_record_signatures(REPOSITORY_ROOT))


if __name__ == "__main__":
    unittest.main()
