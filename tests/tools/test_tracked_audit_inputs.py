#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

MODULE_PATH = Path(__file__).resolve().parents[2] / "tools" / "sitecustomize.py"


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location("tracked_audit_inputs", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TrackedAuditInputsTest(unittest.TestCase):
    def test_only_tracked_supported_files_are_returned(self) -> None:
        module = load_module(MODULE_PATH)
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


if __name__ == "__main__":
    unittest.main()
