from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import generate_review_backlog, scan_reference_matrix, validate_reference_matrix  # noqa: E402


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
        self.assertEqual(matrix["summary"]["references"], 4)
        self.assertTrue(any(reference.get("output_resolution") == "resolved_constant" for reference in matrix["references"]))
        self.assertEqual(matrix["summary"]["producer_candidate_files"], 1)
        self.assertEqual(matrix["summary"]["candidate_edges"], 1)
        self.assertEqual(matrix["summary"]["candidate_edges_matching_canonical"], 1)

    def test_matrix_validator_accepts_generated_matrix(self) -> None:
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        result = validate_reference_matrix.validate_matrix(matrix, self.root)
        self.assertTrue(result["valid"], result)
        self.assertEqual(result["errors"], 0)

    def test_source_aware_canonical_mismatch_enters_backlog(self) -> None:
        (self.root / "data/other.json").write_text('{"other": true}\n', encoding="utf-8")
        (self.root / "scripts/generator.py").write_text(
            'SOURCE_A = "data/source.json"\nSOURCE_B = "data/other.json"\n'
            'OUTPUT_PATH = Path("data/output.json")\nOUTPUT_PATH.write_text("{}")\n',
            encoding="utf-8",
        )
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        mismatches = [edge for edge in matrix["candidate_edges"] if edge["source"] == "data/other.json"]
        self.assertTrue(mismatches)
        self.assertTrue(all(edge["canonical_graph_match"] is False for edge in mismatches))
        self.assertTrue(all(scan_reference_matrix.CANDIDATE_NOT_CANONICAL in edge["issues"] for edge in mismatches))
        (self.root / "docs/data_sources/provenance_reference_matrix.json").write_text(
            json.dumps(matrix), encoding="utf-8"
        )
        backlog = generate_review_backlog.build_backlog(self.root, "test-base")
        self.assertTrue(any(
            item["target_type"] == "dependency_edge"
            and item["path"] == "data/output.json"
            and item["issues"] == [scan_reference_matrix.CANDIDATE_NOT_CANONICAL]
            for item in backlog["items"]
        ))
        stale = json.loads(json.dumps(matrix))
        for edge in stale["candidate_edges"]:
            if edge["source"] == "data/other.json":
                edge["canonical_graph_match"] = True
        invalid = validate_reference_matrix.validate_matrix(stale, self.root)
        self.assertFalse(invalid["valid"], invalid)
        self.assertTrue(any(item["code"] == "CANONICAL_MATCH_MISMATCH" for item in invalid["findings"]))

    def test_variable_bound_output_candidate_is_explicit(self) -> None:
        (self.root / "scripts/dynamic.py").write_text(
            'ASSET_DIR = source_specs.ASSET_DIR\nasset_path = ASSET_DIR / f"{name}.json"\n'
            'asset_path.write_text("{}")\n',
            encoding="utf-8",
        )
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        unresolved = [
            item for item in matrix["unresolved"]
            if item["type"] == scan_reference_matrix.DYNAMIC_OUTPUT_UNRESOLVED
            and item["owner"] == "scripts/dynamic.py"
        ]
        self.assertEqual(len(unresolved), 1)
        self.assertEqual(unresolved[0]["target"], "<dynamic-output>")
        self.assertFalse(any(edge["output"] == "<dynamic-output>" for edge in matrix["candidate_edges"]))
        result = validate_reference_matrix.validate_matrix(matrix, self.root)
        self.assertTrue(result["valid"], result)

    def test_invalid_matrix_hash_is_error(self) -> None:
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        matrix["files"][0]["sha256"] = "not-a-hash"
        result = validate_reference_matrix.validate_matrix(matrix, self.root)
        self.assertFalse(result["valid"], result)
        self.assertTrue(any(item["code"] == "INVALID_HASH" for item in result["findings"]))

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

    def test_provenance_json_records_are_not_runtime_references(self) -> None:
        (self.root / "tests").mkdir()
        (self.root / "tests/provenance").mkdir()
        (self.root / "tests/provenance/audit_record.json").write_text(
            '{"path": "data/source.json", "derived_from": ["data/source.json"]}\n',
            encoding="utf-8",
        )
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        self.assertNotIn(
            "tests/provenance/audit_record.json",
            {reference["owner"] for reference in matrix["references"]},
        )
        self.assertNotIn(
            "tests/provenance/audit_record.json",
            {record["path"] for record in matrix["files"]},
        )
    def test_duplicate_gitkeep_placeholders_are_ignored(self) -> None:
        (self.root / "scripts/.gitkeep").write_bytes(b"")
        (self.root / "tools/.gitkeep").write_bytes(b"")
        matrix = scan_reference_matrix.build_matrix(self.root, "test-base")
        self.assertEqual(matrix["duplicate_hash_groups"], [])


if __name__ == "__main__":
    unittest.main()
