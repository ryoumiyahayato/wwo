#!/usr/bin/env python3
"""Execute every case in the deterministic Batch 2 QA corpus."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPOSITORY_ROOT / "tools" / "world_data" / "validate_world_data.py"
CORPUS_PATH = REPOSITORY_ROOT / "tests" / "world_data" / "fixtures" / "qa_corpus.json"


def load_validator() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wwo_batch2_corpus_validator", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load validator: {VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


validator = load_validator()


class Batch2CorpusExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.corpus = json.loads(CORPUS_PATH.read_text(encoding="utf-8"))

    def test_every_corpus_case_matches_its_expected_outcome(self) -> None:
        for case in self.corpus["cases"]:
            with self.subTest(case=case["id"]):
                expected = case["expected"]
                if case["kind"] == "json":
                    with tempfile.TemporaryDirectory() as temp_dir:
                        data_root = Path(temp_dir)
                        (data_root / "fixture.json").write_text(case["text"], encoding="utf-8")
                        documents, findings, _ = validator.load_json_documents(data_root)
                    self.assertEqual(bool(findings), expected["json_parse_error"])
                    if expected["json_parse_error"]:
                        self.assertEqual([finding.code for finding in findings], ["JSON_PARSE_ERROR"])
                    else:
                        self.assertIn("fixture.json", documents)
                elif case["kind"] == "ring":
                    ring = case["ring"]
                    self.assertEqual(validator.ring_self_intersects(ring), expected["self_intersects"])
                    self.assertEqual(validator.ring_area(ring) != 0.0, expected["nonzero_area"])
                elif case["kind"] == "ring_equivalence":
                    self.assertEqual(
                        validator.canonical_ring(case["ring"]),
                        validator.canonical_ring(case["rotated_ring"]),
                    )
                else:
                    self.fail(f"unknown corpus case kind: {case['kind']}")


if __name__ == "__main__":
    unittest.main()
