#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE_PATH = ROOT / "tools" / "audit_formal_v23_dependencies.py"
GENERATOR_PATH = ROOT / "tools" / "generate_formal_v23_dependency_audit.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class StrictFormalV23DependencyAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = load_module("audit_formal_v23_dependencies", ENGINE_PATH)
        self.generator = load_module("generate_formal_v23_dependency_audit", GENERATOR_PATH)

    def write(self, root: Path, path: str, content: str) -> None:
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")

    def make_repo(self, root: Path) -> None:
        self.write(root, "project.godot", '[application]\nrun/main_scene="res://scenes/formal/formal_world_main.tscn"\n')
        self.write(
            root,
            "scenes/formal/formal_world_main.tscn",
            '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/formal/formal_world_application.gd" id="1"]\n',
        )
        self.write(
            root,
            "scripts/formal/formal_world_application.gd",
            'extends Node\nconst SERVICE = preload("res://scripts/v2_3/v2_3_retained_service.gd")\n',
        )
        self.write(root, "scripts/v2_3/v2_3_retained_service.gd", "class_name V23RetainedService\nextends RefCounted\n")
        self.write(root, "scripts/v2_3/v2_3_retained_service.gd.uid", "uid://retained\n")
        self.write(root, "scripts/v2_3/v2_3_alpha_service.gd", "class_name V23AlphaService\nextends RefCounted\n")
        self.write(
            root,
            "tests/alpha/alpha_test.gd",
            'extends SceneTree\nconst A = preload("res://scripts/v2_3/v2_3_alpha_service.gd")\n',
        )
        self.write(root, "scripts/v2_3/v2_3_save_service.gd", "class_name V23SaveService\nextends RefCounted\n")
        self.write(root, "scripts/v2_3/v2_3_unused_service.gd", "class_name V23UnusedService\nextends RefCounted\n")
        self.write(root, "scripts/v2_3/v2_3_dynamic_service.gd", "class_name V23DynamicService\nextends RefCounted\n")
        self.write(
            root,
            "scripts/factory.gd",
            'extends RefCounted\nfunc f(path):\n    return load(path) # scripts/v2_3/v2_3_dynamic_service.gd\n',
        )
        self.write(
            root,
            "tests/v2_3/v2_3_service_test.gd",
            'extends SceneTree\nconst S = preload("res://scripts/v2_3/v2_3_retained_service.gd")\n',
        )
        self.write(
            root,
            "tests/formal/formal_world_long_term_balance_test.gd",
            'extends SceneTree\nconst F = preload("res://scripts/formal/formal_world_application.gd")\n',
        )
        self.write(
            root,
            "tests/formal/formal_world_integration_test.gd",
            'extends SceneTree\nconst F = preload("res://scripts/formal/formal_world_application.gd")\n',
        )
        self.write(root, "tests/variable_state/formal_time_stable_contract_test.gd", "stable\n")

    def test_strict_candidates_and_classification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_repo(root)
            contract = root / "tests/variable_state/formal_time_stable_contract_test.gd"
            blob = self.engine.git_blob_sha(contract.read_bytes())
            self.engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = blob
            self.generator.engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = blob
            audit = self.generator.build_audit(root)
            by_path = {item["file_path"]: item for item in audit["candidates"]}
            self.assertEqual(by_path["scripts/v2_3/v2_3_retained_service.gd"]["classification"], "A")
            self.assertEqual(by_path["scripts/v2_3/v2_3_alpha_service.gd"]["classification"], "C")
            self.assertEqual(by_path["scripts/v2_3/v2_3_save_service.gd"]["classification"], "E")
            self.assertEqual(by_path["scripts/v2_3/v2_3_unused_service.gd"]["classification"], "G")
            self.assertEqual(by_path["scripts/v2_3/v2_3_dynamic_service.gd"]["classification"], "U")
            self.assertEqual(by_path["tests/v2_3/v2_3_service_test.gd"]["classification"], "F")
            self.assertNotIn("scripts/v2_3/v2_3_retained_service.gd.uid", by_path)
            self.assertNotIn("tools/audit_formal_v23_dependencies.py", by_path)
            self.assertTrue(audit["formal_time_contract"]["unchanged"])

    def test_deterministic_write_and_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_repo(root)
            contract = root / "tests/variable_state/formal_time_stable_contract_test.gd"
            blob = self.engine.git_blob_sha(contract.read_bytes())
            self.engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = blob
            self.generator.engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = blob
            first = self.generator.build_audit(root)
            second = self.generator.build_audit(root)
            self.assertEqual(
                json.dumps(first, ensure_ascii=False, sort_keys=True),
                json.dumps(second, ensure_ascii=False, sort_keys=True),
            )
            self.assertEqual(self.generator.write_or_check(root, first, check=False), 0)
            self.assertEqual(self.generator.write_or_check(root, first, check=True), 0)
            report = (root / "docs/refactors/formal_v23_dependency_audit.md").read_text(encoding="utf-8")
            self.assertNotIn(directory, report)
            (root / "docs/refactors/formal_v23_dependency_inventory.json").write_text("{}\n", encoding="utf-8")
            self.assertEqual(self.generator.write_or_check(root, first, check=True), 1)


if __name__ == "__main__":
    unittest.main()
