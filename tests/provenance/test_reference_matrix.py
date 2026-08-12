from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import scan_reference_matrix, validate_reference_matrix  # noqa: E402


class ReferenceMatrixTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        for directory in ("scripts", "data", "assets", "tools"):
            (self.root / directory).mkdir()
        (self.root / "data/source.json").write_text('{"source": true}\n', encoding="utf-8")
        (self.root / "data/output.json").write_text('{"output": true}\n', encoding="utf-8")
        (self.root / "scripts/generator.py").write_text(
            'SOURCE = "data/source.json"\nOUTPUT_PATH = Path("data/output.json")\n'
            'OUTPUT_PATH.write_text("{}")\n',
            encoding="utf-8",
        )
        (self.root / "tools/consumer.py").write_text(
            'VALUE = "data/output.json"\n', encoding="utf-8"
        )
        self.manifest = {
            "entries": [
                {"path": "data/source.json", "kind": "source", "license": "CC0"},
                {"path": "data/output.json", "kind": "generated", "license": "CC0"},
            ],
            "dependency_graph": {
                "edges": [
                    {
                        "source": "data/source.json",
                        "generator": ["scripts/generator.py"],
                        "output": "data/output.json",
                    }
                ]
            },
        }
        (self.root / "docs").mkdir()
        (self.root / "docs/data_sources").mkdir()
        (self.root / "docs/data_sources/provenance_manifest.json").write_text(
            json.dumps(self.manifest), encoding="utf-8"
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_matrix_detects_producer_and_consumer(self) -> None:
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        self.assertEqual(matrix["summary"]["files_scanned"], 2)
        self.assertEqual(matrix["summary"]["references"], 3)
        self.assertEqual(matrix["summary"]["producer_candidate_files"], 1)
        self.assertEqual(matrix["summary"]["candidate_edges"], 1)
        self.assertEqual(matrix["summary"]["candidate_edges_matching_canonical"], 1)

    def test_matrix_validator_accepts_generated_matrix(self) -> None:
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        result = validate_reference_matrix.validate_matrix(matrix, self.root)
        self.assertTrue(result["valid"], result)
        self.assertEqual(result["errors"], 0)

    def test_fixture_relative_reference_is_explicit(self) -> None:
        (self.root / "tests").mkdir()
        (self.root / "tests/fixture_test.py").write_text(
            'path = "data/generated-at-runtime.json"\n', encoding="utf-8"
        )
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        fixture_refs = [
            reference
            for reference in matrix["references"]
            if reference["reference_scope"] == "test_fixture_relative"
        ]
        self.assertEqual(len(fixture_refs), 1)
        self.assertIn(scan_reference_matrix.INTENTIONAL_TEST_FIXTURE, fixture_refs[0]["issues"])
        self.assertEqual(matrix["summary"]["broken_references"], 0)

    def test_broken_reference_is_reported(self) -> None:
        (self.root / "tools/missing_consumer.py").write_text(
            'VALUE = "data/missing.json"\n', encoding="utf-8"
        )
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        result = validate_reference_matrix.validate_matrix(matrix, self.root)
        self.assertTrue(result["valid"], result)
        self.assertTrue(any(item["code"] == scan_reference_matrix.BROKEN_REFERENCE for item in result["findings"]))

    def test_duplicate_gitkeep_placeholders_are_ignored(self) -> None:
        (self.root / "scripts/.gitkeep").write_bytes(b"")
        (self.root / "tools/.gitkeep").write_bytes(b"")
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        self.assertEqual(matrix["duplicate_hash_groups"], [])


if __name__ == "__main__":
    unittest.main()
