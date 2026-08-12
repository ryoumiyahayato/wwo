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
    assert result["file_count"] == 183
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


if __name__ == "__main__":
    test_corpus_covers_all_files_and_validates()
    test_corpus_replay_is_deterministic()
    test_corpus_has_representative_runtime_and_geometry_samples()
    print("World-data regression corpus tests: 3 passed")
