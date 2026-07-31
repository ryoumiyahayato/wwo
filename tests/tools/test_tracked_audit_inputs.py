#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = ROOT / "tools"
MODULE_PATH = TOOLS_DIR / "sitecustomize.py"
ENGINE_PATH = TOOLS_DIR / "audit_formal_v23_dependencies.py"
GENERATOR_PATH = TOOLS_DIR / "generate_formal_v23_dependency_audit.py"
RUNNER_PATH = TOOLS_DIR / "run_formal_v23_dependency_audit.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class TrackedAuditInputsTest(unittest.TestCase):
    def test_only_tracked_supported_files_are_returned(self) -> None:
        module = load_module("tracked_audit_inputs", MODULE_PATH)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "scripts").mkdir()
            (root / "scripts" / "tracked.gd").write_text("extends RefCounted\n", encoding="utf-8")
            (root / "scripts" / "untracked.gd").write_text("extends RefCounted\n", encoding="utf-8")
            (root / "notes.txt").write_text("not an audit input\n", encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(root), "add", "scripts/tracked.gd", "notes.txt"],
                check=True,
            )
            audit = SimpleNamespace(
                IGNORED_PARTS={".git", ".godot"},
                SCAN_SUFFIXES={".gd", ".json"},
            )
            found = [
                path.relative_to(root).as_posix()
                for path in module.iter_tracked_scan_files(root, audit)
            ]
            self.assertEqual(found, ["scripts/tracked.gd"])

    def test_lf_crlf_and_cr_inputs_produce_identical_audit_outputs(self) -> None:
        sys.path.insert(0, str(TOOLS_DIR))
        try:
            engine = load_module("audit_formal_v23_dependencies", ENGINE_PATH)
            adapter = load_module("tracked_audit_inputs_line_endings", MODULE_PATH)
            generator = load_module("generate_formal_v23_dependency_audit", GENERATOR_PATH)
            runner = load_module("run_formal_v23_dependency_audit", RUNNER_PATH)

            with tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                lf_root = base / "lf"
                crlf_root = base / "crlf"
                cr_root = base / "cr"
                changed_root = base / "changed"
                for root, newline, changed in (
                    (lf_root, "\n", False),
                    (crlf_root, "\r\n", False),
                    (cr_root, "\r", False),
                    (changed_root, "\n", True),
                ):
                    self.make_audit_repo(root, newline=newline, changed=changed)

                expected_contract = self.raw_git_blob_sha(b"stable\n")
                engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = expected_contract
                generator.engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = expected_contract

                lf = self.build_refined_audit(runner, generator, lf_root)
                crlf = self.build_refined_audit(runner, generator, crlf_root)
                cr = self.build_refined_audit(runner, generator, cr_root)
                changed = self.build_refined_audit(runner, generator, changed_root)

                machine_lf = runner._serialize_compact_json(lf)
                report_lf = runner._render_concise_markdown(lf)
                summary_lf = self.tracked_input_summary(adapter, engine, lf_root)
                for root, audit in ((crlf_root, crlf), (cr_root, cr)):
                    self.assertEqual(machine_lf, runner._serialize_compact_json(audit))
                    self.assertEqual(report_lf, runner._render_concise_markdown(audit))
                    self.assertEqual(lf["counts"], audit["counts"])
                    self.assertEqual(summary_lf, self.tracked_input_summary(adapter, engine, root))

                self.assertNotEqual(machine_lf, runner._serialize_compact_json(changed))
                self.assertNotEqual(report_lf, runner._render_concise_markdown(changed))
                self.assertNotEqual(summary_lf, self.tracked_input_summary(adapter, engine, changed_root))
                self.assertFalse(changed["formal_time_contract"]["unchanged"])
        finally:
            if sys.path and sys.path[0] == str(TOOLS_DIR):
                sys.path.pop(0)

    def make_audit_repo(self, root: Path, newline: str, changed: bool) -> None:
        files = {
            "project.godot": '[application]\nrun/main_scene="res://scenes/formal/formal_world_main.tscn"\n',
            "scenes/formal/formal_world_main.tscn": (
                '[gd_scene load_steps=2 format=3]\n'
                '[ext_resource type="Script" path="res://scripts/formal/formal_world_application.gd" id="1"]\n'
            ),
            "scripts/formal/formal_world_application.gd": (
                'extends Node\nconst SERVICE = preload("res://scripts/v2_3/v2_3_retained_service.gd")\n'
            ),
            "scripts/v2_3/v2_3_retained_service.gd": (
                "class_name V23ChangedService\nextends RefCounted\n"
                if changed
                else "class_name V23RetainedService\nextends RefCounted\n"
            ),
            "tests/formal/formal_world_long_term_balance_test.gd": (
                'extends SceneTree\nconst F = preload("res://scripts/formal/formal_world_application.gd")\n'
            ),
            "tests/formal/formal_world_integration_test.gd": (
                'extends SceneTree\nconst F = preload("res://scripts/formal/formal_world_application.gd")\n'
            ),
            "tests/variable_state/formal_time_stable_contract_test.gd": (
                "changed\n" if changed else "stable\n"
            ),
        }
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        for path, logical_text in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(logical_text.replace("\n", newline).encode("utf-8"))
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)

    def build_refined_audit(self, runner, generator, root: Path) -> dict:
        runner._DYNAMIC_INDEX = None
        return runner._refine_audit(root, generator.build_audit(root))

    def tracked_input_summary(self, adapter, engine, root: Path) -> list[tuple[str, str]]:
        return [
            (
                path.relative_to(root).as_posix(),
                hashlib.sha256(adapter.normalize_audit_text_bytes(path.read_bytes())).hexdigest(),
            )
            for path in adapter.iter_tracked_scan_files(root, engine)
        ]

    def raw_git_blob_sha(self, data: bytes) -> str:
        header = f"blob {len(data)}\0".encode("ascii")
        return hashlib.sha1(header + data).hexdigest()


if __name__ == "__main__":
    unittest.main()
