from __future__ import annotations

import json
import sys
import tempfile
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




def test_quality_audit_reports_invalid_shard_geometry_and_coordinates() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        city_root = root / "city_detail"
        city_root.mkdir()
        (city_root / "index.json").write_text(
            json.dumps({"countries": [{"country_code": "US", "count": 1, "shards": [{"path": "US.json", "count": 1, "bounds": [0, 0, -1, 1]}]}]}),
            encoding="utf-8",
        )
        (city_root / "US.json").write_text(
            json.dumps({"count": 1, "bounds": [0, 0, -1, 1], "cities": [{"id": "city:invalid", "lon_lat": [181, 0]}]}),
            encoding="utf-8",
        )
        issues: list[dict[str, str]] = []
        metrics: dict[str, object] = {}
        audit._check_city_shards(root, issues, metrics)
        codes = {issue["code"] for issue in issues}
        assert "CITY_BOUNDS" in codes
        assert "CITY_COORDINATE" in codes
        assert metrics["invalid_bounds"] == 1
        assert metrics["invalid_city_coordinates"] == 1
if __name__ == "__main__":
    test_world_data_quality_contract_passes()
    test_quality_backlog_is_explicit_and_bounded()
    test_quality_audit_reports_invalid_shard_geometry_and_coordinates()
    print("World-data quality audit tests: 3 passed")
