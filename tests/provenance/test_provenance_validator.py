from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import generate_manifest, validate_manifest  # noqa: E402


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def entry(root: Path, relative: str, *, kind: str = "source", **overrides: object) -> dict[str, object]:
    path = root / relative
    base: dict[str, object] = {
        "path": relative,
        "file_type": "application/json",
        "size_bytes": path.stat().st_size,
        "sha256": digest(path),
        "category": "test",
        "kind": kind,
        "known_source": "Test source",
        "source_locator": ["https://example.invalid/source"],
        "author_institution": "Test institution",
        "license": "CC0",
        "license_locator": [],
        "derived_from": [],
        "generator": [validate_manifest.GENERATOR_UNKNOWN],
        "confidence": "high",
        "review_status": "REVIEWED",
        "issues": [],
        "evidence": ["test"],
        "notes": [],
    }
    base.update(overrides)
    return base


def valid_manifest(root: Path) -> dict[str, object]:
    source = entry(root, "data/source.json")
    output = entry(
        root,
        "data/output.json",
        kind="generated",
        derived_from=["data/source.json"],
        generator=["tools/generator.py"],
    )
    entries = [source, output]
    return {
        "schema_version": 1,
        "manifest_kind": "wwo_data_asset_provenance",
        "external_sources": [],
        "dependency_graph": {
            "shape": "source -> generator -> generated output",
            "edges": [{"source": "data/source.json", "generator": ["tools/generator.py"], "output": "data/output.json"}],
        },
        "summary": {
            "files_inventoried": 2,
            "source_known": 2,
            "source_unknown": 0,
            "license_known": 2,
            "license_unknown": 0,
            "generated_assets": 1,
            "duplicate_hash_groups": 0,
        },
        "entries": entries,
    }


class ProvenanceValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        (self.root / "data").mkdir()
        (self.root / "tools").mkdir()
        (self.root / "data/source.json").write_text('{"source": true}\n', encoding="utf-8")
        (self.root / "data/output.json").write_text('{"output": true}\n', encoding="utf-8")
        (self.root / "tools/generator.py").write_text("# deterministic test generator\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_valid_manifest_has_no_findings(self) -> None:
        result = validate_manifest.validate_manifest(valid_manifest(self.root), self.root)
        self.assertTrue(result["valid"])
        self.assertEqual(result["errors"], 0)
        self.assertEqual(result["warnings"], 0)

    def test_unknown_license_is_warning(self) -> None:
        manifest = valid_manifest(self.root)
        source = manifest["entries"][0]
        source["license"] = validate_manifest.LICENSE_UNKNOWN
        source["issues"] = [validate_manifest.LICENSE_UNKNOWN, validate_manifest.PROVENANCE_INCOMPLETE]
        manifest["summary"]["license_known"] = 1
        manifest["summary"]["license_unknown"] = 1
        result = validate_manifest.validate_manifest(manifest, self.root)
        self.assertTrue(result["valid"])
        self.assertGreaterEqual(result["warnings"], 1)
        self.assertTrue(any(item["code"] == validate_manifest.LICENSE_UNKNOWN for item in result["findings"]))

    def test_duplicate_hash_is_reported(self) -> None:
        duplicate_path = self.root / "data/duplicate.json"
        duplicate_path.write_bytes((self.root / "data/source.json").read_bytes())
        manifest = valid_manifest(self.root)
        manifest["entries"].append(entry(self.root, "data/duplicate.json"))
        manifest["summary"].update({"files_inventoried": 3, "source_known": 3, "license_known": 3, "duplicate_hash_groups": 1})
        result = validate_manifest.validate_manifest(manifest, self.root)
        self.assertTrue(result["valid"])
        self.assertTrue(any(item["code"] == "DUPLICATE_HASH" for item in result["findings"]))

    def test_broken_derived_from_is_error(self) -> None:
        manifest = valid_manifest(self.root)
        manifest["entries"][1]["derived_from"] = ["data/missing.json"]
        manifest["dependency_graph"]["edges"][0]["source"] = "data/missing.json"
        result = validate_manifest.validate_manifest(manifest, self.root)
        self.assertFalse(result["valid"])
        self.assertTrue(any(item["code"] == "BROKEN_DERIVED_FROM" for item in result["findings"]))

    def test_contradictory_unknown_source_is_error(self) -> None:
        manifest = valid_manifest(self.root)
        source = manifest["entries"][0]
        source["known_source"] = validate_manifest.SOURCE_UNKNOWN
        source["issues"] = [validate_manifest.SOURCE_UNKNOWN, validate_manifest.PROVENANCE_INCOMPLETE]
        manifest["summary"].update({"source_known": 1, "source_unknown": 1})
        result = validate_manifest.validate_manifest(manifest, self.root)
        self.assertFalse(result["valid"])
        self.assertTrue(any(item["code"] == "CONTRADICTORY_PROVENANCE" for item in result["findings"]))

    def test_missing_source_and_generator_are_warnings(self) -> None:
        manifest = valid_manifest(self.root)
        output = manifest["entries"][1]
        output["derived_from"] = []
        output["generator"] = [validate_manifest.GENERATOR_UNKNOWN]
        output["issues"] = [validate_manifest.GENERATOR_UNKNOWN, validate_manifest.SOURCE_MISSING, validate_manifest.PROVENANCE_INCOMPLETE]
        manifest["dependency_graph"]["edges"] = []
        result = validate_manifest.validate_manifest(manifest, self.root)
        self.assertTrue(result["valid"])
        self.assertTrue(any(item["code"] == validate_manifest.SOURCE_MISSING for item in result["findings"]))
        self.assertTrue(any(item["code"] == validate_manifest.GENERATOR_UNKNOWN for item in result["findings"]))

    def test_real_manifest_generation_is_deterministic(self) -> None:
        first = generate_manifest.build_manifest(ROOT, "determinism-test")
        second = generate_manifest.build_manifest(ROOT, "determinism-test")
        first_text = json.dumps(first, ensure_ascii=False, sort_keys=True)
        second_text = json.dumps(second, ensure_ascii=False, sort_keys=True)
        self.assertEqual(first_text, second_text)


if __name__ == "__main__":
    unittest.main()
