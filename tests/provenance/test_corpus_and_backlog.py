from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import generate_regression_corpus, generate_review_backlog  # noqa: E402
from tools.provenance import validate_regression_corpus, validate_review_backlog  # noqa: E402


class CorpusAndBacklogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        (self.root / "docs/data_sources").mkdir(parents=True)
        (self.root / "tests/provenance").mkdir(parents=True)
        (self.root / "data").mkdir()
        source = {
            "path": "data/source.json",
            "file_type": "application/json",
            "size_bytes": 2,
            "sha256": "00" * 32,
            "category": "historical_data",
            "kind": "source",
            "known_source": "SOURCE_UNKNOWN",
            "license": "LICENSE_UNKNOWN",
            "derived_from": [],
            "generator": ["GENERATOR_UNKNOWN"],
            "issues": ["SOURCE_UNKNOWN", "LICENSE_UNKNOWN", "PROVENANCE_INCOMPLETE"],
            "evidence": ["data/source.json"],
            "review_status": "REVIEW_REQUIRED",
        }
        (self.root / "data/source.json").write_bytes(b"{}")
        source["sha256"] = __import__("hashlib").sha256(b"{}").hexdigest()
        manifest = {
            "entries": [source],
            "summary": {
                "files_inventoried": 1,
                "source_known": 0,
                "source_unknown": 1,
                "license_known": 0,
                "license_unknown": 1,
                "generated_assets": 0,
                "broken_provenance_chains": 0,
                "duplicate_hash_groups": 0,
            },
            "external_sources": [],
            "dependency_graph": {"edges": []},
        }
        (self.root / "docs/data_sources/provenance_manifest.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )
        matrix = {
            "unresolved": [],
            "candidate_edges": [],
        }
        (self.root / "docs/data_sources/provenance_reference_matrix.json").write_text(
            json.dumps(matrix), encoding="utf-8"
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_corpus_is_valid_and_deterministic(self) -> None:
        first = generate_regression_corpus.build_corpus(self.root, "base")
        second = generate_regression_corpus.build_corpus(self.root, "base")
        self.assertEqual(first, second)
        result = validate_regression_corpus.validate_corpus(first, self.root)
        self.assertTrue(result["valid"], result)

    def test_backlog_is_valid_and_ranked(self) -> None:
        backlog = generate_review_backlog.build_backlog(self.root, "base")
        result = validate_review_backlog.validate_backlog(backlog, self.root)
        self.assertTrue(result["valid"], result)
        self.assertEqual([item["rank"] for item in backlog["items"]], [1])
        self.assertEqual(backlog["items"][0]["path"], "data/source.json")

    def test_corpus_hash_mismatch_fails(self) -> None:
        corpus = generate_regression_corpus.build_corpus(self.root, "base")
        corpus["source_manifest_sha256"] = "0" * 64
        result = validate_regression_corpus.validate_corpus(corpus, self.root)
        self.assertFalse(result["valid"])
        self.assertTrue(any(item["code"] == "HASH_MISMATCH" for item in result["findings"]))


if __name__ == "__main__":
    unittest.main()
