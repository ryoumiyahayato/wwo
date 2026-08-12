#!/usr/bin/env python3
"""Focused tests for the consolidated Batch 4 run manifest."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from types import ModuleType


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPOSITORY_ROOT / "tools" / "world_data" / "build_batch4_run_manifest.py"
OUTPUT_DIR = REPOSITORY_ROOT / "local-artifacts" / "world-data-audit"


def load_tool() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wwo_batch4_run_manifest", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load Batch 4 run manifest tool: {TOOL_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


batch4 = load_tool()


class Batch4RunManifestTests(unittest.TestCase):
    def test_manifest_consolidates_existing_batch_results(self) -> None:
        manifest = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        self.assertEqual(manifest["batch_scope"], ["BATCH 1", "BATCH 2", "BATCH 3", "BATCH 4"])
        self.assertFalse(manifest["authoritative_source_modified"])
        self.assertEqual(manifest["batch_results"]["batch1"]["inventory_files"], 183)
        self.assertEqual(manifest["batch_results"]["batch2"]["data_parse_errors"], 0)
        self.assertEqual(manifest["batch_results"]["batch2"]["verified_flag_assets"], 60)
        self.assertEqual(manifest["batch_results"]["batch3"]["loader_missing_direct_references"], 0)
        self.assertEqual(manifest["batch_results"]["batch3"]["historical_units"], 151)

    def test_final_gates_distinguish_clean_mechanical_gates_from_manual_findings(self) -> None:
        manifest = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        gates = manifest["final_gates"]
        self.assertEqual(gates["json_parse_errors"], 0)
        self.assertEqual(gates["dangling_foreign_keys"], 0)
        self.assertEqual(gates["duplicate_catalog_ids"], 0)
        self.assertEqual(gates["flag_asset_gaps"], 0)
        self.assertEqual(gates["loader_contract_gaps"], 0)
        self.assertEqual(gates["manual_review_findings"], 110)

    def test_resource_policy_is_explicit(self) -> None:
        manifest = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        policy = manifest["batch_results"]["batch4"]
        self.assertEqual(policy["resource_intensive_phases_executed"], [])
        self.assertEqual(policy["concurrency"], "1 process; no process pool or thread pool")
        self.assertEqual(policy["large_temporary_artifacts"], [])

    def test_manifest_is_deterministic_before_adding_itself(self) -> None:
        first = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        second = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
