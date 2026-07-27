#!/usr/bin/env python3
"""Audit the committed 1900 historical GIS and flag evidence without network."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GEOMETRY_PATH = ROOT / "data/world_map/historical/cshapes_1900_snapshot.json"
UNITS_PATH = ROOT / "data/world_map/historical/political_units_1900.json"
FLAGS_PATH = ROOT / "data/world_map/historical/flags_1900.json"
TARGET_DATE = "1900-03-12"
EXPECTED_UNITS = 151
EXPECTED_SOURCE_ASSETS = 60


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    geometry = load_json(GEOMETRY_PATH)
    units = load_json(UNITS_PATH)
    flags = load_json(FLAGS_PATH)

    require(geometry.get("snapshot_date") == TARGET_DATE, "wrong geometry snapshot date")
    require(geometry.get("provider") == "cshapes_2_0", "wrong geometry provider")
    source = geometry.get("source", {})
    require(source.get("license") == "CC BY-NC-SA 4.0", "CShapes license missing")
    require(source.get("commercial_use_allowed") is False, "CShapes commercial restriction missing")
    features = geometry.get("features", [])
    require(len(features) == EXPECTED_UNITS, "expected 151 historical geometry features")
    feature_by_id = {feature["id"]: feature for feature in features}
    require(len(feature_by_id) == EXPECTED_UNITS, "duplicate historical geometry IDs")
    for feature in features:
        require(feature["valid_from"] <= TARGET_DATE <= feature["valid_to"], f"feature outside target date: {feature['id']}")
        require(feature.get("geometry", {}).get("type") in {"Polygon", "MultiPolygon"}, f"unsupported geometry: {feature['id']}")

    unit_records = units.get("units", [])
    require(units.get("unit_count") == EXPECTED_UNITS and len(unit_records) == EXPECTED_UNITS, "expected 151 political units")
    require(units.get("policy", {}).get("modern_geometry_fallback_allowed") is False, "modern geometry fallback enabled")
    require(len({unit["id"] for unit in unit_records}) == EXPECTED_UNITS, "duplicate political unit IDs")
    require(len({unit["gwcode"] for unit in unit_records}) == EXPECTED_UNITS, "duplicate Gleditsch-Ward codes")

    flag_records = flags.get("records", {})
    source_asset_records = [record for record in flag_records.values() if record.get("render_mode") == "source_asset"]
    require(len(source_asset_records) == EXPECTED_SOURCE_ASSETS, "expected 60 source-backed flag assets")
    require(flags.get("policy", {}).get("random_or_hash_flags_allowed") is False, "random flag fallback enabled")
    require("no_single_standard_flag" in flag_records, "documented absence flag record missing")

    mode_counts: dict[str, int] = {}
    referenced_flag_ids: set[str] = set()
    controller_unit_ids = {unit["id"] for unit in unit_records}
    for unit in unit_records:
        require(unit.get("geometry_feature_id") in feature_by_id, f"missing geometry for {unit['id']}")
        require(unit.get("data_quality") == "dated_historical_gis", f"unit not marked dated historical GIS: {unit['id']}")
        require(unit.get("flag_id") not in {"", "research_required"}, f"unresolved flag: {unit['id']}")
        require(unit.get("flag_id") in flag_records, f"flag record missing: {unit['id']}")
        flag_mode = str(unit.get("flag_mode", ""))
        require(flag_mode in {"local_historical_flag", "controller_identification_flag", "documented_absence"}, f"invalid flag mode: {unit['id']}")
        if flag_mode == "controller_identification_flag":
            require(unit.get("controller_id") in controller_unit_ids, f"controller missing: {unit['id']}")
        if flag_mode == "documented_absence":
            require(unit.get("flag_id") == "no_single_standard_flag", f"absence flag mismatch: {unit['id']}")
            require(bool(unit.get("flag_absence_reason")), f"absence reason missing: {unit['id']}")
        mode_counts[flag_mode] = mode_counts.get(flag_mode, 0) + 1
        referenced_flag_ids.add(unit["flag_id"])

    require(sum(mode_counts.values()) == EXPECTED_UNITS, "flag mode coverage incomplete")
    require(mode_counts.get("documented_absence", 0) > 0, "no documented absence cases")
    for flag_id in referenced_flag_ids:
        record = flag_records[flag_id]
        if record.get("render_mode") != "source_asset":
            continue
        for field in ("source_title", "source_page", "source_asset", "source_license", "valid_from", "valid_to", "flag_type", "confidence", "heraldic_zh", "asset_sha256"):
            require(bool(record.get(field)), f"{field} missing for flag {flag_id}")
        asset_path = ROOT / str(record["asset_path"]).removeprefix("res://")
        require(asset_path.is_file(), f"flag asset missing: {flag_id}")
        digest = hashlib.sha256(asset_path.read_bytes()).hexdigest()
        require(digest == record["asset_sha256"], f"flag asset hash mismatch: {flag_id}")

    print(json.dumps({
        "snapshot_date": TARGET_DATE,
        "geometry_features": len(features),
        "political_units": len(unit_records),
        "source_flag_assets": len(source_asset_records),
        "referenced_flag_records": len(referenced_flag_ids),
        "flag_mode_counts": mode_counts,
        "modern_geometry_fallback": False,
        "random_flag_fallback": False,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
