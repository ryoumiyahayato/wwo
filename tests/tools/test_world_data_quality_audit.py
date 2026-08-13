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
    assert report["metrics"]["runtime_supporting_file_count"] == 2
    assert report["metrics"]["runtime_supporting_missing"] == []
    assert report["metrics"]["runtime_supporting_bad_schema"] == []


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

def _write_city_fixture(root: Path, records_by_path: dict[str, list[dict[str, object]]]) -> None:
    city_root = root / "city_detail"
    for relative, records in records_by_path.items():
        path = city_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"count": len(records), "bounds": [0, 0, 1, 1], "cities": records}),
            encoding="utf-8",
        )
    shards = []
    total = 0
    for relative, records in sorted(records_by_path.items()):
        total += len(records)
        shards.append({"id": Path(relative).stem, "path": relative, "count": len(records), "bounds": [0, 0, 1, 1]})
    (city_root / "index.json").write_text(
        json.dumps({"countries": [{"country_code": "FR", "count": total, "municipality_count": 0, "shards": shards}]}),
        encoding="utf-8",
    )


def _city_issues(root: Path) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []
    audit._check_city_shards(root, issues, {})
    return issues


def test_city_detail_missing_id_fails_closed_with_locator() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        _write_city_fixture(root, {"france/FR-01.json": [{"lon_lat": [0.5, 0.5]}]})
        issues = _city_issues(root)
        issue = next(item for item in issues if item["code"] == "CITY_ID_MISSING")
        assert issue["path"] == "city_detail/france/FR-01.json#cities[0]"
        assert "missing stable id" in issue["message"]


def test_city_detail_empty_id_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        _write_city_fixture(root, {"france/FR-01.json": [{"id": "", "lon_lat": [0.5, 0.5]}]})
        assert any(item["code"] == "CITY_ID_EMPTY" for item in _city_issues(root))



def test_city_detail_whitespace_and_malformed_ids_fail_closed() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        _write_city_fixture(root, {"france/FR-01.json": [{"id": "   ", "lon_lat": [0.1, 0.1]}, {"id": "not geonames", "lon_lat": [0.2, 0.2]}]})
        issues = _city_issues(root)
        codes = [item["code"] for item in issues]
        assert "CITY_ID_WHITESPACE" in codes
        assert "CITY_ID_MALFORMED" in codes

def test_city_detail_same_shard_duplicate_reports_both_locations() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        records = [
            {"id": "geonames:1", "lon_lat": [0.1, 0.1]},
            {"id": "geonames:1", "lon_lat": [0.2, 0.2]},
        ]
        _write_city_fixture(root, {"france/FR-01.json": records})
        issue = next(item for item in _city_issues(root) if item["code"] == "CITY_DUPLICATE_ID_SAME_SHARD")
        assert "city_detail/france/FR-01.json#cities[0]" in issue["message"]
        assert "city_detail/france/FR-01.json#cities[1]" in issue["message"]


def test_city_detail_cross_shard_duplicate_reports_both_locations() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        records = {"id": "geonames:1", "lon_lat": [0.1, 0.1]}
        _write_city_fixture(root, {"france/FR-01.json": [records], "france/FR-02.json": [records]})
        issue = next(item for item in _city_issues(root) if item["code"] == "CITY_DUPLICATE_ID_CROSS_SHARD")
        assert "france/FR-01.json#cities[0]" in issue["message"]
        assert "france/FR-02.json#cities[0]" in issue["message"]


def test_city_detail_clean_distinct_ids_passes() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        _write_city_fixture(
            root,
            {
                "france/FR-01.json": [{"id": "geonames:1", "lon_lat": [0.1, 0.1]}],
                "france/FR-02.json": [{"id": "geonames:2", "lon_lat": [0.2, 0.2]}],
            },
        )
        assert not [item for item in _city_issues(root) if item["severity"] == "error"]


def test_city_detail_required_orphan_is_invalid() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        _write_city_fixture(root, {"france/FR-01.json": [{"id": "geonames:1", "lon_lat": [0.1, 0.1]}]})
        orphan = root / "city_detail" / "france" / "orphan.json"
        orphan.write_text(json.dumps({"count": 1, "bounds": [0, 0, 1, 1], "cities": [{"id": "geonames:2", "lon_lat": [0.2, 0.2]}]}), encoding="utf-8")
        issues = _city_issues(root)
        issue = next(item for item in issues if item["code"] == "CITY_UNREFERENCED_SHARD")
        assert issue["severity"] == "error"
        assert "classification=required runtime shard" in issue["message"]


def test_city_detail_explicit_optional_orphan_is_warning_only() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        _write_city_fixture(root, {"france/FR-01.json": [{"id": "geonames:1", "lon_lat": [0.1, 0.1]}]})
        optional = root / "city_detail" / "france" / "optional.json"
        optional.write_text(json.dumps({"optional": True, "count": 1, "bounds": [0, 0, 1, 1], "cities": [{"id": "geonames:2", "lon_lat": [0.2, 0.2]}]}), encoding="utf-8")
        issues = _city_issues(root)
        assert any(item["code"] == "CITY_OPTIONAL_ORPHAN_SHARD" and item["severity"] == "warning" for item in issues)
        assert not [item for item in issues if item["severity"] == "error"]

if __name__ == "__main__":
    test_world_data_quality_contract_passes()
    test_quality_backlog_is_explicit_and_bounded()
    test_quality_audit_reports_invalid_shard_geometry_and_coordinates()
    test_city_detail_missing_id_fails_closed_with_locator()
    test_city_detail_empty_id_fails_closed()
    test_city_detail_whitespace_and_malformed_ids_fail_closed()
    test_city_detail_same_shard_duplicate_reports_both_locations()
    test_city_detail_cross_shard_duplicate_reports_both_locations()
    test_city_detail_clean_distinct_ids_passes()
    test_city_detail_required_orphan_is_invalid()
    test_city_detail_explicit_optional_orphan_is_warning_only()
    print("World-data quality audit tests: 11 passed")
