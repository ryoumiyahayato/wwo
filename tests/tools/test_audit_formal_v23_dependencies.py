#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "audit_formal_v23_dependencies.py"


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location("formal_v23_audit", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FormalV23DependencyAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module(MODULE_PATH)

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
        self.write(root, "scripts/v2_3/v2_3_alpha_service.gd", "class_name V23AlphaService\nextends RefCounted\n")
        self.write(
            root,
            "tests/alpha/alpha_test.gd",
            'extends SceneTree\nconst A = preload("res://scripts/v2_3/v2_3_alpha_service.gd")\n',
        )
        self.write(root, "scripts/v2_3/v2_3_unused_service.gd", "class_name V23UnusedService\nextends RefCounted\n")
        self.write(root, "scripts/v2_3/v2_3_dynamic_service.gd", 'extends RefCounted\nfunc f(path):\n    return load(path)\n')
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

    def test_graph_classification_and_determinism(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_repo(root)
            contract = root / "tests/variable_state/formal_time_stable_contract_test.gd"
            self.module.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = self.module.git_blob_sha(contract.read_bytes())
            first = self.module.audit_repository(root)
            second = self.module.audit_repository(root)
            self.assertEqual(self.module.serialize_json(first), self.module.serialize_json(second))
            by_path = {item["file_path"]: item for item in first["candidates"]}
            self.assertEqual(by_path["scripts/v2_3/v2_3_retained_service.gd"]["classification"], "A")
            self.assertEqual(by_path["scripts/v2_3/v2_3_alpha_service.gd"]["classification"], "C")
            self.assertEqual(by_path["scripts/v2_3/v2_3_unused_service.gd"]["classification"], "G")
            self.assertEqual(by_path["scripts/v2_3/v2_3_dynamic_service.gd"]["classification"], "U")
            self.assertEqual(by_path["tests/v2_3/v2_3_service_test.gd"]["classification"], "F")
            self.assertTrue(first["formal_time_contract"]["unchanged"])
            self.assertNotIn(directory, self.module.render_markdown(first))

    def test_write_then_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_repo(root)
            contract = root / "tests/variable_state/formal_time_stable_contract_test.gd"
            self.module.EXPECTED_FORMAL_TIME_CONTRACT_BLOB = self.module.git_blob_sha(contract.read_bytes())
            audit = self.module.audit_repository(root)
            self.assertEqual(self.module.write_or_check(root, audit, check=False), 0)
            self.assertEqual(self.module.write_or_check(root, audit, check=True), 0)
            inventory = json.loads((root / "docs/refactors/formal_v23_dependency_inventory.json").read_text(encoding="utf-8"))
            self.assertEqual(inventory["schema_version"], 1)
            (root / "docs/refactors/formal_v23_dependency_audit.md").write_text("stale\n", encoding="utf-8")
            self.assertEqual(self.module.write_or_check(root, audit, check=True), 1)


if __name__ == "__main__":
    unittest.main()
