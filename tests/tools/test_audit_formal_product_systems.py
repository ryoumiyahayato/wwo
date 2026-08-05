#!/usr/bin/env python3
"""Regression tests for the formal product system completeness audit."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = ROOT / "tools" / "audit_formal_product_systems.py"
ARTIFACT_PATH = ROOT / "artifacts" / "formal-product-system-completeness.json"

SPEC = importlib.util.spec_from_file_location(
    "audit_formal_product_systems", TOOL_PATH
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot import audit tool: {TOOL_PATH}")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class FormalProductSystemAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.payload = AUDIT.build_artifact(ROOT)

    def test_generation_is_byte_deterministic(self) -> None:
        first = AUDIT.canonical_bytes(AUDIT.build_artifact(ROOT))
        second = AUDIT.canonical_bytes(AUDIT.build_artifact(ROOT))
        self.assertEqual(first, second)

    def test_committed_artifact_matches_generation(self) -> None:
        self.assertTrue(ARTIFACT_PATH.is_file())
        self.assertEqual(
            ARTIFACT_PATH.read_bytes(), AUDIT.canonical_bytes(self.payload)
        )

    def test_formal_boundary_and_dependencies_are_explicit(self) -> None:
        scanner = self.payload["scanner"]
        self.assertEqual(
            scanner["project"]["main_scene"],
            "res://scenes/formal/formal_world_menu.tscn",
        )
        self.assertEqual(scanner["project"]["autoloads"], [])
        runtime = set(scanner["formal_runtime_files"])
        self.assertIn(
            "scripts/ui_spikes/holographic_workspace/"
            "holographic_workspace_runtime.gd",
            runtime,
        )
        self.assertIn(
            "scripts/alpha/alpha_historical_world_economy_data.gd", runtime
        )
        self.assertIn("scripts/v2_2/v2_datetime.gd", runtime)

    def test_inventory_is_complete_without_inflated_maturity(self) -> None:
        systems = self.payload["systems"]
        self.assertEqual([row["id"] for row in systems], list("ABCDEFGHIJKLMNO"))
        self.assertNotIn(
            "PLAYER_LOOP_COMPLETE", {row["maturity"] for row in systems}
        )
        self.assertEqual(
            self.payload["system_counts"]["by_maturity"],
            {
                "ABSENT": 0,
                "IMPLEMENTED_ISOLATED": 6,
                "INTEGRATED_UNVERIFIED": 0,
                "INTEGRATED_VERIFIED": 4,
                "PLAYER_LOOP_COMPLETE": 0,
                "PLAYER_LOOP_PARTIAL": 5,
                "SCAFFOLD_ONLY": 0,
            },
        )

    def test_gap_register_has_stable_priority_counts(self) -> None:
        self.assertEqual(
            self.payload["gap_counts"],
            {
                "blocking_formal_release": 21,
                "blocking_playable_loop": 12,
                "by_priority": {"P0": 4, "P1": 9, "P2": 8, "P3": 3},
                "total": 24,
            },
        )

    def test_no_unresolved_literal_resource_in_formal_runtime(self) -> None:
        unresolved = [
            row
            for row in self.payload["scanner"][
                "missing_literal_resource_references"
            ]
            if "FORMAL_RUNTIME" in row["source_classifications"]
            and not row["expected_negative_or_generated_output"]
        ]
        self.assertEqual(unresolved, [])

    def test_unreached_core_service_is_not_reported_as_formal_runtime(self) -> None:
        rows = {
            row["path"]: row["classifications"]
            for row in self.payload["scanner"]["files"]
        }
        self.assertEqual(
            rows["scripts/simulation/society_simulation_service.gd"],
            ["UNRESOLVED"],
        )

    def test_stale_test_entry_references_remain_visible(self) -> None:
        missing_sources = {
            row["source"]
            for row in self.payload["scanner"][
                "missing_literal_resource_references"
            ]
        }
        self.assertIn("tests/test_runner.gd", missing_sources)
        self.assertIn("tests/p0_r1_player_journey_current.gd", missing_sources)

    def test_artifact_and_documents_pass_reference_validation(self) -> None:
        AUDIT.validate_artifact(ROOT, self.payload)
        self.assertEqual(
            AUDIT.validate_audit_documents(ROOT, self.payload), []
        )


if __name__ == "__main__":
    unittest.main()
