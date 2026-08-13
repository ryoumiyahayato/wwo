#!/usr/bin/env python3
"""Focused tests for the consolidated Batch 4 run manifest."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
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


REPLAY_ARTIFACTS = (
    "batch2_asset_manifest.json",
    "batch2_asset_staging_candidates.json",
    "batch2_data_manifest.json",
    "batch2_gap_report.json",
    "batch2_regression_manifest.json",
    "batch3_gap_report.json",
    "batch3_historical_flag_coverage.json",
    "batch3_loader_contract.json",
    "batch3_record_signature_manifest.json",
    "batch3_staging_candidates.json",
    "batch4_run_manifest.json",
    "coverage.json",
    "findings.json",
    "inventory.json",
    "normalization_candidates.json",
    "staging_candidates.json",
)


def artifact_mismatches(generated: Path, tracked: Path) -> list[str]:
    return [
        name
        for name in REPLAY_ARTIFACTS
        if not (generated / name).is_file()
        or canonical_bytes(generated / name) != canonical_bytes(tracked / name)
    ]


def canonical_bytes(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")


class Batch4RunManifestTests(unittest.TestCase):
    def test_manifest_consolidates_existing_batch_results(self) -> None:
        manifest = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        self.assertEqual(manifest["batch_scope"], ["BATCH 1", "BATCH 2", "BATCH 3", "BATCH 4"])
        self.assertFalse(manifest["authoritative_source_modified"])
        self.assertEqual(manifest["batch_results"]["batch1"]["inventory_files"], 184)
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
        expected_manual_findings = sum(
            1
            for finding in json.loads((OUTPUT_DIR / "findings.json").read_text(encoding="utf-8"))
            if finding["code"] in {"SELF_INTERSECTING_RING", "PLACEHOLDER_FOREIGN_KEY"}
        )
        self.assertEqual(gates["manual_review_findings"], expected_manual_findings)

    def test_resource_policy_is_explicit(self) -> None:
        manifest = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        policy = manifest["batch_results"]["batch4"]
        self.assertEqual(policy["resource_intensive_phases_executed"], [])
        self.assertEqual(policy["concurrency"], "1 process; no process pool or thread pool")
        self.assertEqual(policy["large_temporary_artifacts"], [])

    def test_all_specialized_dangling_codes_feed_the_final_gate(self) -> None:
        self.assertEqual(
            batch4.dangling_reference_count(
                {
                    "DANGLING_FOREIGN_KEY": 2,
                    "DANGLING_ACTIVITY_ID": 1,
                    "DANGLING_CITY_DETAIL_SHARD": 3,
                    "SELF_INTERSECTING_RING": 99,
                }
            ),
            6,
        )

    def test_manifest_is_deterministic_before_adding_itself(self) -> None:
        first = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        second = batch4.build_manifest(REPOSITORY_ROOT, OUTPUT_DIR)
        self.assertEqual(first, second)

    def test_official_generators_replay_tracked_artifacts_and_detect_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "artifacts"
            commands = [
                [
                    sys.executable,
                    str(REPOSITORY_ROOT / "tools" / "world_data" / "validate_world_data.py"),
                    "--root",
                    str(REPOSITORY_ROOT),
                    "--data-root",
                    str(REPOSITORY_ROOT / "data" / "world_map"),
                    "--output-dir",
                    str(output),
                    "--allow-errors",
                ],
                [
                    sys.executable,
                    str(REPOSITORY_ROOT / "tools" / "world_data" / "build_batch2_artifacts.py"),
                    "--root",
                    str(REPOSITORY_ROOT),
                    "--output-dir",
                    str(output),
                ],
                [
                    sys.executable,
                    str(REPOSITORY_ROOT / "tools" / "world_data" / "build_batch3_contracts.py"),
                    "--root",
                    str(REPOSITORY_ROOT),
                    "--output-dir",
                    str(output),
                ],
                [
                    sys.executable,
                    str(REPOSITORY_ROOT / "tools" / "world_data" / "build_batch4_run_manifest.py"),
                    "--root",
                    str(REPOSITORY_ROOT),
                    "--output-dir",
                    str(output),
                ],
            ]
            results = [subprocess.run(command, cwd=REPOSITORY_ROOT, capture_output=True, text=True, check=False) for command in commands]
            self.assertEqual(results[0].returncode, 0, results[0].stderr)
            self.assertEqual(results[1].returncode, 0, results[1].stderr)
            self.assertEqual(results[2].returncode, 0, results[2].stderr)
            self.assertEqual(results[3].returncode, 0, results[3].stderr)
            self.assertEqual(artifact_mismatches(output, OUTPUT_DIR), [])

            inventory = output / "inventory.json"
            inventory.write_bytes(inventory.read_bytes() + b" ")
            self.assertEqual(artifact_mismatches(output, OUTPUT_DIR), ["inventory.json"])


if __name__ == "__main__":
    unittest.main()
