#!/usr/bin/env python3
"""Regression tests for the variable-state runtime discovery boundary."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


AUDIT = load_module("audit_variable_state", ROOT / "tools" / "audit_variable_state.py")
SUMMARY = load_module(
    "render_variable_state_audit_summary",
    ROOT / "tools" / "render_variable_state_audit_summary.py",
)


class VariableStateDiscoveryTests(unittest.TestCase):
    @staticmethod
    def write(root: Path, relative: str, text: str = "{\"active_player\": true}\n") -> None:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    @staticmethod
    def discovered(root: Path) -> list[str]:
        return [
            path.relative_to(root).as_posix()
            for path in AUDIT.iter_source_files(root)
        ]

    @classmethod
    def seed_runtime(cls, root: Path) -> None:
        cls.write(root, "project.godot", "[application]\nconfig/name=\"fixture\"\n")
        cls.write(root, "scripts/runtime_state.gd", "var active_player: String = \"person:1\"\n")
        # The vNext spatial loader consumes this runtime catalog root.
        cls.write(root, "data/world_map/countries.json")
        cls.write(root, "data/vnext/politics/base.json")

    @staticmethod
    def payload(source_count: int, gdscript_count: int) -> dict[str, object]:
        metrics = {
            "member_fields_total": 0,
            "writable_member_fields_total": 0,
            "global_writable_fields_total": 0,
            "autoload_writable_fields_total": 0,
            "persisted_member_fields_by_static_evidence": 0,
            "compatibility_alias_candidates": 0,
            "ui_copy_candidates": 0,
            "cache_candidates": 0,
            "derived_member_candidates": 0,
            "unclear_member_fields": 0,
            "source_files_scanned": source_count,
            "gdscript_files_scanned": gdscript_count,
        }
        return {
            "metrics": metrics,
            "discovery_contract": AUDIT.discovery_contract(),
        }

    def test_non_authoritative_staging_and_review_artifacts_do_not_change_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.seed_runtime(root)
            baseline = self.discovered(root)
            baseline_doc = SUMMARY.render_summary_text(
                self.payload(len(baseline), sum(path.endswith(".gd") for path in baseline))
            )
            # Synthetic PR #69 additions: world_names review staging.
            for relative in (
                "data/staging/world_names/aliases.json",
                "data/staging/world_names/looks_like_state.json",
                # Synthetic PR #63 additions: 1900 historical staging.
                "data/staging/1900/political_unit_records_1900.json",
                "data/staging/1900/looks_like_variable_state.json",
                "tests/fixtures/looks_like_state.json",
                "tools/review_output.json",
                "docs/review.json",
                "artifacts/generated_report.json",
            ):
                self.write(root, relative)
            changed = self.discovered(root)
            changed_doc = SUMMARY.render_summary_text(
                self.payload(len(changed), sum(path.endswith(".gd") for path in changed))
            )
            self.assertEqual(changed, baseline)
            self.assertEqual(changed_doc, baseline_doc)
            self.assertFalse(AUDIT.is_discovery_path("data/staging/world_names/aliases.json"))
            self.assertFalse(AUDIT.is_discovery_path("data/staging/1900/looks_like_state.json"))

    def test_runtime_config_changes_inventory_and_generated_docs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.seed_runtime(root)
            baseline = self.discovered(root)
            baseline_doc = SUMMARY.render_summary_text(
                self.payload(len(baseline), sum(path.endswith(".gd") for path in baseline))
            )
            # A new config in the vNext loader-consumed catalog family must be audited.
            self.write(root, "data/world_map/new_vnext_runtime_config.json")
            changed = self.discovered(root)
            changed_doc = SUMMARY.render_summary_text(
                self.payload(len(changed), sum(path.endswith(".gd") for path in changed))
            )
            self.assertIn("data/world_map/new_vnext_runtime_config.json", changed)
            self.assertNotEqual(changed, baseline)
            self.assertNotEqual(changed_doc, baseline_doc)
            self.assertIn("Runtime config roots:", changed_doc)

    def test_vnext_runtime_config_is_not_path_sensitive(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.seed_runtime(root)
            self.write(root, "data/vnext/deep/reviewed/runtime_config.json")
            self.write(root, "data/not_a_runtime_root/runtime_config.json")
            self.write(root, "runtime_config.json")
            discovered = self.discovered(root)
            self.assertIn("data/vnext/deep/reviewed/runtime_config.json", discovered)
            self.assertNotIn("data/not_a_runtime_root/runtime_config.json", discovered)
            self.assertNotIn("runtime_config.json", discovered)

    def test_discovery_order_and_contract_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.seed_runtime(root)
            self.write(root, "data/world_map/z.json")
            self.write(root, "data/world_map/a.json")
            first = self.discovered(root)
            second = self.discovered(root)
            self.assertEqual(first, second)
            self.assertEqual(first, sorted(first))
            contract = AUDIT.discovery_contract()
            self.assertNotIn("data", contract["runtime_config_roots"])
            self.assertIn("data/staging", contract["non_authoritative_roots"])

    def test_workflow_uses_runtime_paths_instead_of_data_glob(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "variable-state-audit.yml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('"data/**"', workflow)
        for root in AUDIT.RUNTIME_CONFIG_ROOTS:
            self.assertIn(f'"{root}/**"', workflow)


if __name__ == "__main__":
    unittest.main()

