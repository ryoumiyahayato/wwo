#!/usr/bin/env python3
"""Fail-closed gates for Wave 1's actual product Spatial composition/evidence."""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
import sys
from pathlib import Path

MENU = "res://scenes/formal/formal_world_menu.tscn"
MAIN = "res://scenes/formal/formal_world_main.tscn"
APP = "scripts/formal/formal_world_application.gd"
PROJECTION = "scripts/formal/product_spatial_projection.gd"
SPATIAL_SOURCES = (
    "data/world_map/regions.json",
    "data/world_map/cities.json",
    "data/world_map/ports.json",
    "data/world_map/road_segments.json",
    "data/world_map/rail_segments.json",
    "data/world_map/shipping_routes.json",
)
SCREENSHOTS = {
    "01_BOOT": "01_boot.png",
    "02_WORLD": "02_world.png",
    "03_SPATIAL_RUNTIME_PROVENANCE": "03_spatial_runtime_provenance.png",
    "04_COUNTRY_SELECTED": "04_country_selected.png",
    "05_LOCAL_GEOGRAPHY_ACTUAL_STATE": "05_local_geography_actual_state.png",
    "06_CITY_ACTUAL_STATE": "06_city_actual_state.png",
    "07_CITY_SUPPORTED_FIELDS_IF_ANY": "07_city_supported_fields_if_any.png",
    "08_INFRASTRUCTURE_ACTUAL_STATE": "08_infrastructure_actual_state.png",
    "09_REFERENCE_ONLY_OR_UNAVAILABLE_EXAMPLE": "09_reference_only_or_unavailable_example.png",
    "10_TIME_BEFORE": "10_time_before.png",
    "11_TIME_AFTER": "11_time_after.png",
}
OWNER_LABELS = {
    "WORLD/POLITICAL OWNER",
    "POLITICAL GEOMETRY PROJECTION",
    "VNEXT SPATIAL OWNER",
    "HISTORICAL LOCAL GEOGRAPHY STATUS",
    "HISTORICAL CITY DATA STATUS",
    "INFRASTRUCTURE HISTORICAL STATUS",
    "TIME OWNER",
    "ECONOMY OWNER",
    "POPULATION OWNER",
    "ORGANIZATION OWNER",
    "POLITICS OWNER",
    "MILITARY OWNER",
}


def _head(root: Path) -> str:
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, check=True,
        capture_output=True, text=True,
    ).stdout.strip()


def validate_product(root: Path) -> list[str]:
    failures: list[str] = []
    project = (root / "project.godot").read_text(encoding="utf-8")
    app = (root / APP).read_text(encoding="utf-8")
    projection = (root / PROJECTION).read_text(encoding="utf-8")
    if f'run/main_scene="{MENU}"' not in project:
        failures.append("default entry is not the Formal menu")
    menu = (root / "scripts/formal/formal_world_menu.gd").read_text(encoding="utf-8")
    if MAIN not in menu:
        failures.append("Formal menu does not enter the actual main")
    if app.count("VNextSpatialWorld.create(catalog)") != 1:
        failures.append("actual product must construct exactly one vNext Spatial owner")
    for token in (
        "POLITICAL GEOMETRY PROJECTION", "VNEXT SPATIAL OWNER",
        "HISTORICAL LOCAL GEOGRAPHY STATUS", "HISTORICAL CITY DATA STATUS",
        "INFRASTRUCTURE HISTORICAL STATUS",
    ):
        if token not in app:
            failures.append(f"runtime provenance missing {token}")
    for token in (
        ".reserve_capacity(", ".request_capacity(",
        ".request_capacity_batch(", ".set_nominal_capacity(",
    ):
        if token in projection:
            failures.append(f"production projection reaches legacy capacity API: {token}")
    for source in SPATIAL_SOURCES:
        document = json.loads((root / source).read_text(encoding="utf-8"))
        if document.get("prototype_only") is not True:
            failures.append(f"audit assumption changed without applicability review: {source}")
    if "normal_region_views" not in projection or "normal_city_views" not in projection:
        failures.append("normal presentation eligibility queries are missing")
    if "may_present_as_normal_truth" not in projection:
        failures.append("projection does not enforce explicit applicability")
    return failures


def _png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not PNG")
    return struct.unpack(">II", header[16:24])


def validate_manifest(root: Path, path: Path) -> list[str]:
    failures: list[str] = []
    document = json.loads(path.read_text(encoding="utf-8"))
    records = document.get("screenshots", [])
    by_id = {r.get("screenshot_id"): r for r in records if isinstance(r, dict)}
    if set(by_id) != set(SCREENSHOTS):
        failures.append("screenshot ID set does not match Wave 1 requirement")
    expected_head = _head(root)
    for screenshot_id, filename in SCREENSHOTS.items():
        record = by_id.get(screenshot_id)
        if not record:
            continue
        if record.get("HEAD") != expected_head:
            failures.append(f"{screenshot_id}: HEAD mismatch")
        if record.get("entry") != MENU:
            failures.append(f"{screenshot_id}: alternate entry")
        if record.get("runtime_scene") != (MENU if screenshot_id == "01_BOOT" else MAIN):
            failures.append(f"{screenshot_id}: alternate runtime scene")
        if record.get("fixture_used") != "NO":
            failures.append(f"{screenshot_id}: fixture used")
        if record.get("filename") != filename:
            failures.append(f"{screenshot_id}: filename mismatch")
        if set(record.get("actual_runtime_owners", {})) < OWNER_LABELS:
            failures.append(f"{screenshot_id}: incomplete runtime owners")
        for field in (
            "historical_applicability_class", "exact_supported_facts_visible",
            "exact_unavailable_facts",
        ):
            if not record.get(field):
                failures.append(f"{screenshot_id}: missing {field}")
        image = path.parent / filename
        try:
            if image.stat().st_size < 10_000 or _png_size(image) != (1280, 720):
                failures.append(f"{screenshot_id}: invalid 1280x720 evidence")
        except (OSError, ValueError):
            failures.append(f"{screenshot_id}: image missing/invalid")
    before = by_id.get("10_TIME_BEFORE", {}).get("formal_total_minutes")
    after = by_id.get("11_TIME_AFTER", {}).get("formal_total_minutes")
    if not isinstance(before, int) or not isinstance(after, int) or after <= before:
        failures.append("time screenshots do not prove forward Formal time")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).parents[1])
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    root = args.project_root.resolve()
    failures = validate_product(root)
    if args.manifest:
        failures += validate_manifest(root, args.manifest.resolve())
    for failure in failures:
        print("FAIL:", failure)
    if failures:
        return 1
    print("Wave 1 Spatial product gate: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
