from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools import world_data_regression_corpus as corpus  # noqa: E402


def test_corpus_covers_all_files_and_validates() -> None:
    result = corpus.build_corpus(ROOT)
    assert result["validation"]["valid"], result["validation"]["errors"]
    assert result["file_count"] == 184
    assert len(result["categories"]) == 6
    assert len(result["corpus_sha256"]) == 64
    assert all(record["sample_sha256"] for record in result["records"])


def test_corpus_replay_is_deterministic() -> None:
    first = corpus.build_corpus(ROOT)
    second = corpus.build_corpus(ROOT)
    first_text = json.dumps(first, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    second_text = json.dumps(second, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    assert first_text == second_text
    assert corpus.render_markdown(first) == corpus.render_markdown(second)


def test_corpus_has_representative_runtime_and_geometry_samples() -> None:
    result = corpus.build_corpus(ROOT)
    by_path = {record["path"]: record for record in result["records"]}
    assert by_path["countries.json"]["sample"]["representative_ids"]
    assert by_path["cities.json"]["sample"]["representative_ids"]
    assert by_path["map_geometry_cache.json"]["sample"]["representative_geometry"]
    assert by_path["city_detail/countries/US.json"]["sample"]["representative_ids"]
    assert by_path["strategic_military_overlay.json"]["category"] == "runtime_supporting"




def test_corpus_validator_detects_changed_source_hash() -> None:
    result = corpus.build_corpus(ROOT)
    result["records"][0]["sha256"] = "0" * 64
    errors = corpus.validate_corpus(result, ROOT)
    assert any(error.startswith("source hash drift:") for error in errors)

def _assert_detects(mutator, expected_fragment: str) -> None:
    result = corpus.build_corpus(ROOT)
    mutator(result)
    errors = corpus.validate_corpus(result, ROOT)
    assert any(expected_fragment in error for error in errors), errors


def test_corpus_validator_detects_corpus_hash_tampering() -> None:
    _assert_detects(lambda result: result.__setitem__("corpus_sha256", "0" * 64), "corpus_sha256 mismatch")


def test_corpus_validator_detects_sample_hash_tampering() -> None:
    _assert_detects(lambda result: result["records"][0].__setitem__("sample_sha256", "0" * 64), "sample hash")


def test_corpus_validator_detects_stale_record_count() -> None:
    _assert_detects(lambda result: result["records"][0].__setitem__("record_count", int(result["records"][0]["record_count"]) + 1), "record count drift")


def test_corpus_validator_detects_missing_source_inventory_entry() -> None:
    def mutate(result: dict[str, object]) -> None:
        result["records"] = result["records"][1:]
    _assert_detects(mutate, "missing source inventory entry")


def test_corpus_validator_detects_unexpected_added_source() -> None:
    def mutate(result: dict[str, object]) -> None:
        record = dict(result["records"][0])
        record["path"] = "added.json"
        result["records"] = [*result["records"], record]
    _assert_detects(mutate, "unexpected source")


def test_corpus_validator_detects_altered_summary() -> None:
    def mutate(result: dict[str, object]) -> None:
        result["summary"] = dict(result["summary"])
        result["summary"]["total_record_count"] += 1
    _assert_detects(mutate, "summary mismatch")


def test_corpus_validator_detects_missing_source_file_without_source_change() -> None:
    result = corpus.build_corpus(ROOT)
    result["records"][0]["path"] = "missing-source.json"
    errors = corpus.validate_corpus(result, ROOT)
    assert any(error.startswith("missing source inventory entry:") for error in errors)
    assert any(error == "unexpected source: missing-source.json" for error in errors)

if __name__ == "__main__":
    test_corpus_covers_all_files_and_validates()
    test_corpus_replay_is_deterministic()
    test_corpus_has_representative_runtime_and_geometry_samples()
    test_corpus_validator_detects_changed_source_hash()
    test_corpus_validator_detects_corpus_hash_tampering()
    test_corpus_validator_detects_sample_hash_tampering()
    test_corpus_validator_detects_stale_record_count()
    test_corpus_validator_detects_missing_source_inventory_entry()
    test_corpus_validator_detects_unexpected_added_source()
    test_corpus_validator_detects_altered_summary()
    test_corpus_validator_detects_missing_source_file_without_source_change()
    print("World-data regression corpus tests: 11 passed")
