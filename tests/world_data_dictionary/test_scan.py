#!/usr/bin/env python3
"""Focused tests for the generated dictionary consistency scan."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCAN_PATH = REPOSITORY_ROOT / "tools" / "world_data_dictionary" / "scan.py"


def load_scan():
    spec = importlib.util.spec_from_file_location("world_data_dictionary_scan", SCAN_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load scanner: {SCAN_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


scan = load_scan()


class DictionaryScanTests(unittest.TestCase):
    def write_dictionary(self, root: Path, value: dict) -> Path:
        path = root / "dictionary.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_valid_minimal_dictionary_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            value = {
                "schema_version": 1,
                "datasets": [{
                    "dataset": "sample",
                    "fields": [{
                        "field": "items[].id",
                        "record_scope": "items[]",
                        "record_count": 1,
                        "present_count": 1,
                        "missing_count": 0,
                        "declared": True,
                        "declared_evidence": [{"kind": "DECLARED_TYPE"}],
                    }],
                }],
                "foreign_key_relationships": [],
                "summary": {"input_errors": 0},
                "generation_contract": {"production_data_modified": False},
            }
            self.assertEqual(scan.scan_dictionary(self.write_dictionary(Path(temp_dir), value)), [])

    def test_scan_rejects_inconsistent_coverage_and_missing_declared_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            value = {
                "schema_version": 1,
                "datasets": [{
                    "dataset": "sample",
                    "fields": [{
                        "field": "items[].id",
                        "record_scope": "items[]",
                        "record_count": 2,
                        "present_count": 2,
                        "missing_count": 1,
                        "declared": True,
                        "declared_evidence": [],
                    }],
                }],
                "foreign_key_relationships": [],
                "summary": {"input_errors": 0},
                "generation_contract": {"production_data_modified": False},
            }
            errors = scan.scan_dictionary(self.write_dictionary(Path(temp_dir), value))
            self.assertTrue(any("present + missing does not equal records" in error for error in errors))
            self.assertTrue(any("declared field has no evidence" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
