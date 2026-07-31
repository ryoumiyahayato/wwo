#!/usr/bin/env python3
from __future__ import annotations

import gzip
import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class FormalV23AuditRunnerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        sys.path.insert(0, str(TOOLS))
        load_module("audit_formal_v23_dependencies", TOOLS / "audit_formal_v23_dependencies.py")
        load_module("generate_formal_v23_dependency_audit", TOOLS / "generate_formal_v23_dependency_audit.py")
        cls.runner = load_module("run_formal_v23_dependency_audit", TOOLS / "run_formal_v23_dependency_audit.py")

    def test_deterministic_gzip_round_trip(self) -> None:
        source = b'{"schema_version":1,"items":["alpha","beta"]}\n'
        first = self.runner._deterministic_gzip(source)
        second = self.runner._deterministic_gzip(source)
        self.assertEqual(first, second)
        self.assertEqual(gzip.decompress(first), source)
        self.assertEqual(first[4:8], b"\x00\x00\x00\x00")
        self.assertEqual(first[9], 255)

    def test_shared_indirect_caller_sets_are_complete(self) -> None:
        audit = {
            "scan": {},
            "candidates": [
                {"indirect_callers": ["a.gd", "b.gd"]},
                {"indirect_callers": ["a.gd", "b.gd"]},
                {"indirect_callers": []},
            ],
        }
        self.runner._deduplicate_indirect_callers(audit)
        self.assertEqual(len(audit["indirect_caller_sets"]), 1)
        set_id = audit["candidates"][0]["indirect_callers"]["set_id"]
        self.assertEqual(audit["indirect_caller_sets"][set_id], ["a.gd", "b.gd"])
        self.assertEqual(audit["candidates"][1]["indirect_callers"]["set_id"], set_id)
        self.assertIsNone(audit["candidates"][2]["indirect_callers"]["set_id"])


if __name__ == "__main__":
    unittest.main()
