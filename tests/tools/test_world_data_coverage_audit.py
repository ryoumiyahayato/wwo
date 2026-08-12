from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools import world_data_coverage_audit as audit  # noqa: E402


def test_full_world_map_coverage_is_valid_and_complete() -> None:
    manifest = audit.build_manifest(ROOT)
    assert manifest["validation"]["valid"], manifest["validation"]["errors"]
    assert manifest["file_count"] == 183
    assert manifest["total_file_size_bytes"] > 49_000_000
    assert len(manifest["runtime_loader_paths"]) == 16
    assert manifest["categories"]["runtime_loader"]["file_count"] == 16
    assert manifest["categories"]["city_detail_country_shard"]["file_count"] == 143
    assert manifest["categories"]["city_detail_region_shard"]["file_count"] == 13
    assert manifest["categories"]["historical"]["file_count"] == 8
    assert all(item["parse_status"] == "ok" for item in manifest["files"])


def test_manifest_serialization_and_report_are_deterministic() -> None:
    first = audit.build_manifest(ROOT)
    second = audit.build_manifest(ROOT)
    first_text = json.dumps(first, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    second_text = json.dumps(second, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    assert first_text == second_text
    assert audit.render_markdown(first) == audit.render_markdown(second)


def test_large_structure_inventory_and_categories_are_present() -> None:
    manifest = audit.build_manifest(ROOT)
    country_records = manifest["categories"]["city_detail_country_shard"]["record_count"]
    region_records = manifest["categories"]["city_detail_region_shard"]["record_count"]
    assert country_records > 40_000
    assert region_records > 30_000
    assert country_records + region_records > 80_000
    assert manifest["categories"]["historical"]["geometry_vertex_count"] > 100_000
    assert manifest["categories"]["runtime_loader"]["geometry_vertex_count"] > 80_000
    assert manifest["schema_families"]
    for summary in manifest["categories"].values():
        assert summary["largest_files"]
        assert summary["parse_error_count"] == 0
if __name__ == "__main__":
    test_full_world_map_coverage_is_valid_and_complete()
    test_manifest_serialization_and_report_are_deterministic()
    test_large_structure_inventory_and_categories_are_present()
    print("World-data coverage audit tests: 3 passed")
