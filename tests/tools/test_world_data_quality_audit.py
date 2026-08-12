from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools import world_data_quality_audit as audit  # noqa: E402


def test_world_data_quality_contract_passes() -> None:
    report = audit.build_report(ROOT)
    assert report["valid"], report["issues"]
    assert report["error_count"] == 0
    assert report["metrics"]["actual_shards"] == 156
    assert report["metrics"]["referenced_shards"] == 156
    assert report["metrics"]["shard_record_count"] == 88927
    assert report["metrics"]["france_shard_count"] == 13
    assert report["metrics"]["france_shard_record_count"] == 36871


def test_quality_backlog_is_explicit_and_bounded() -> None:
    report = audit.build_report(ROOT)
    assert [item["id"] for item in report["backlog"]] == ["B4-01", "B4-02", "B4-03", "B4-04", "B4-05"]
    assert all(item["trigger"] for item in report["backlog"])
    assert report["metrics"]["stable_id_missing"] == 0
    assert report["metrics"]["duplicate_city_ids"] == 0


if __name__ == "__main__":
    test_world_data_quality_contract_passes()
    test_quality_backlog_is_explicit_and_bounded()
    print("World-data quality audit tests: 2 passed")
