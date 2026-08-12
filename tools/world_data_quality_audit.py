#!/usr/bin/env python3
"""Read-only structural QA for the world-map JSON boundary.

The audit validates mechanical contracts between the city-detail index and
shards, runtime-loader document metadata, stable city IDs, coordinates,
declared counts and bounds. It reports actionable gaps without rewriting data.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
TOOL_ID = "wwo_world_data_quality_audit_batch_4"
DEFAULT_JSON = "docs/performance/world_data_quality_audit_20260812.json"
DEFAULT_MARKDOWN = "docs/performance/world_data_quality_audit_20260812.md"
CITY_ID_PATTERN = re.compile(r"^geonames:[0-9]+$")

RUNTIME_FILES = (
    "world_coastlines.json",
    "countries.json",
    "regions.json",
    "cities.json",
    "ports.json",
    "rail_segments.json",
    "road_segments.json",
    "shipping_routes.json",
    "characters.json",
    "name_pool_fr.json",
    "relationships.json",
    "organizations.json",
    "institutions.json",
    "world_activity.json",
    "map_modes.json",
    "map_geometry_cache.json",
)


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _bounds_valid(bounds: Any) -> bool:
    return (
        isinstance(bounds, list)
        and len(bounds) == 4
        and all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in bounds)
        and bounds[0] <= bounds[2]
        and bounds[1] <= bounds[3]
        and -180 <= bounds[0] <= 180
        and -180 <= bounds[2] <= 180
        and -90 <= bounds[1] <= 90
        and -90 <= bounds[3] <= 90
    )


def _point_valid(point: Any) -> bool:
    return (
        isinstance(point, list)
        and len(point) == 2
        and all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in point)
        and -180 <= point[0] <= 180
        and -90 <= point[1] <= 90
    )


def _issue(code: str, severity: str, path: str, message: str) -> dict[str, str]:
    return {"code": code, "severity": severity, "path": path, "message": message}


def _city_record_locator(relative: str, record_index: int) -> str:
    return f"city_detail/{relative}#cities[{record_index}]"


def _validate_city_id(
    record: dict[str, Any],
    locator: str,
    issues: list[dict[str, str]],
) -> str | None:
    if "id" not in record:
        issues.append(_issue("CITY_ID_MISSING", "error", locator, "reason=missing stable id"))
        return None
    value = record["id"]
    if not isinstance(value, str):
        issues.append(_issue("CITY_ID_MALFORMED", "error", locator, "reason=stable id must be a string"))
        return None
    if value == "":
        issues.append(_issue("CITY_ID_EMPTY", "error", locator, "reason=stable id is empty"))
        return None
    if value.strip() == "":
        issues.append(_issue("CITY_ID_WHITESPACE", "error", locator, "reason=stable id is whitespace-only"))
        return None
    if value != value.strip() or CITY_ID_PATTERN.fullmatch(value) is None:
        issues.append(_issue("CITY_ID_MALFORMED", "error", locator, "reason=stable id must match geonames:<numeric-id>"))
        return None
    return value


def _check_city_shards(root: Path, issues: list[dict[str, str]], metrics: dict[str, Any]) -> None:
    city_root = root / "city_detail"
    index_path = city_root / "index.json"
    index = _load(index_path)
    if not isinstance(index, dict):
        issues.append(_issue("CITY_INDEX_ROOT", "error", "city_detail/index.json", "index root is not an object"))
        return
    index_countries = index.get("countries", [])
    if not isinstance(index_countries, list):
        issues.append(_issue("CITY_INDEX_COUNTRIES", "error", "city_detail/index.json", "countries is not an array"))
        return
    referenced: dict[str, dict[str, Any]] = {}
    index_counts = 0
    for country in index_countries:
        if not isinstance(country, dict):
            issues.append(_issue("CITY_INDEX_ENTRY", "error", "city_detail/index.json", "non-object country entry"))
            continue
        country_code = str(country.get("country_code", ""))
        if not country_code:
            issues.append(_issue("CITY_INDEX_CODE", "error", "city_detail/index.json", "country entry lacks country_code"))
        shards = country.get("shards", [])
        if not isinstance(shards, list):
            issues.append(_issue("CITY_INDEX_SHARDS", "error", f"city_detail/index.json:{country_code}", "shards is not an array"))
            continue
        for shard in shards:
            if not isinstance(shard, dict):
                issues.append(_issue("CITY_INDEX_SHARD", "error", "city_detail/index.json", "non-object shard reference"))
                continue
            shard_path = str(shard.get("path", ""))
            if shard_path in referenced:
                issues.append(_issue("CITY_DUPLICATE_REF", "error", shard_path, "shard referenced more than once"))
            referenced[shard_path] = {"index": shard, "country": country_code}
            index_counts += int(shard.get("count", 0))
    actual_shards = sorted(
        path.relative_to(city_root).as_posix()
        for path in city_root.rglob("*.json")
        if path.name not in {"index.json", "LICENSE.json"}
    )
    actual_set = set(actual_shards)
    ref_set = set(referenced)
    for missing in sorted(ref_set - actual_set):
        issues.append(_issue("CITY_MISSING_SHARD", "error", missing, "index references missing shard"))
    shard_documents: dict[str, Any] = {
        relative: _load(city_root / relative) for relative in actual_shards
    }
    optional_orphans = 0
    required_orphans = 0
    for unreferenced in sorted(actual_set - ref_set):
        document = shard_documents.get(unreferenced)
        if isinstance(document, dict) and document.get("optional") is True:
            optional_orphans += 1
            issues.append(_issue("CITY_OPTIONAL_ORPHAN_SHARD", "warning", f"city_detail/{unreferenced}", "classification=explicitly optional/non-runtime; shard is not referenced by index"))
        else:
            required_orphans += 1
            issues.append(_issue("CITY_UNREFERENCED_SHARD", "error", f"city_detail/{unreferenced}", "classification=required runtime shard; shard is not referenced by index"))
    total_records = 0
    city_id_locations: dict[str, list[str]] = {}
    invalid_coordinates = 0
    count_mismatches = 0
    invalid_bounds = 0
    for relative in actual_shards:
        document = shard_documents[relative]
        if not isinstance(document, dict):
            issues.append(_issue("CITY_SHARD_ROOT", "error", f"city_detail/{relative}", "shard root is not an object"))
            document = {}
        cities = document.get("cities", [])
        if not isinstance(cities, list):
            issues.append(_issue("CITY_RECORDS_ROOT", "error", f"city_detail/{relative}#cities", "reason=cities must be an array"))
            cities = []
        if document.get("count") != len(cities):
            count_mismatches += 1
            issues.append(_issue("CITY_COUNT_MISMATCH", "error", f"city_detail/{relative}", f"declared {document.get('count')} != actual {len(cities)}"))
        if not _bounds_valid(document.get("bounds")):
            invalid_bounds += 1
            issues.append(_issue("CITY_BOUNDS", "error", f"city_detail/{relative}", "invalid geographic bounds"))
        for record_index, item in enumerate(cities):
            locator = _city_record_locator(relative, record_index)
            if not isinstance(item, dict):
                issues.append(_issue("CITY_RECORD", "error", locator, "reason=city record must be an object"))
                invalid_coordinates += 1
                issues.append(_issue("CITY_COORDINATE", "error", locator, "invalid lon_lat"))
                continue
            city_id = _validate_city_id(item, locator, issues)
            if city_id is not None:
                city_id_locations.setdefault(city_id, []).append(locator)
            if not _point_valid(item.get("lon_lat")):
                invalid_coordinates += 1
                issues.append(_issue("CITY_COORDINATE", "error", locator, "invalid lon_lat"))
        total_records += len(cities)
        reference = referenced.get(relative)
        if reference:
            if reference["index"].get("count") != len(cities):
                issues.append(_issue("CITY_INDEX_COUNT", "error", f"city_detail/index.json:{relative}", "index count differs from shard"))
            if reference["index"].get("bounds") != document.get("bounds"):
                issues.append(_issue("CITY_INDEX_BOUNDS", "error", f"city_detail/index.json:{relative}", "index bounds differ from shard"))
    same_shard_duplicate_ids = 0
    cross_shard_duplicate_ids = 0
    duplicate_city_ids = 0
    for city_id in sorted(city_id_locations):
        locations = sorted(city_id_locations[city_id])
        if len(locations) < 2:
            continue
        duplicate_city_ids += len(locations) - 1
        shard_paths = sorted({location.split("#", 1)[0] for location in locations})
        if len(shard_paths) == 1:
            same_shard_duplicate_ids += 1
            code = "CITY_DUPLICATE_ID_SAME_SHARD"
            reason = "reason=stable id occurs more than once within one shard"
        else:
            cross_shard_duplicate_ids += 1
            code = "CITY_DUPLICATE_ID_CROSS_SHARD"
            reason = "reason=stable id occurs across different shards"
        issues.append(_issue(code, "error", locations[0], f"stable_id={city_id!r}; {reason}; conflicting_locations={'; '.join(locations)}"))
    france = next((item for item in index_countries if isinstance(item, dict) and item.get("country_code") == "FR"), None)
    france_paths = [relative for relative in actual_shards if relative.startswith("france/") and relative in ref_set]
    france_sum = sum(int(shard_documents[relative].get("count", 0)) for relative in france_paths if isinstance(shard_documents[relative], dict))
    if not isinstance(france, dict):
        issues.append(_issue("FR_INDEX_ENTRY", "error", "city_detail/index.json", "France aggregate entry is missing"))
    else:
        if int(france.get("count", -1)) != france_sum:
            issues.append(_issue("FR_COUNT", "error", "city_detail/index.json:FR", f"aggregate count {france.get('count')} != shard sum {france_sum}"))
        if int(france.get("municipality_count", -1)) > int(france.get("count", -1)):
            issues.append(_issue("FR_MUNICIPALITY_COUNT", "error", "city_detail/index.json:FR", "municipality count exceeds aggregate count"))
    metrics.update({
        "index_country_entries": len(index_countries),
        "referenced_shards": len(ref_set),
        "actual_shards": len(actual_shards),
        "index_record_count": index_counts,
        "shard_record_count": total_records,
        "duplicate_city_ids": duplicate_city_ids,
        "same_shard_duplicate_ids": same_shard_duplicate_ids,
        "cross_shard_duplicate_ids": cross_shard_duplicate_ids,
        "city_stable_id_records_checked": sum(len(locations) for locations in city_id_locations.values()),
        "invalid_city_coordinates": invalid_coordinates,
        "count_mismatches": count_mismatches,
        "invalid_bounds": invalid_bounds,
        "france_shard_count": len(france_paths),
        "france_shard_record_count": france_sum,
        "optional_orphan_shards": optional_orphans,
        "required_orphan_shards": required_orphans,
    })

def _check_runtime_files(root: Path, issues: list[dict[str, str]], metrics: dict[str, Any]) -> None:
    missing = []
    bad_schema = []
    missing_prototype_flag = []
    schema_versions = Counter()
    root_types = Counter()
    for relative in RUNTIME_FILES:
        path = root / relative
        if not path.is_file():
            missing.append(relative)
            issues.append(_issue("RUNTIME_MISSING", "error", relative, "runtime loader path is missing"))
            continue
        document = _load(path)
        root_types[type(document).__name__] += 1
        version = document.get("schema_version") if isinstance(document, dict) else None
        if not isinstance(version, int) or isinstance(version, bool) or version <= 0:
            bad_schema.append(relative)
            issues.append(_issue("RUNTIME_SCHEMA", "error", relative, "expected object with a positive integer schema_version"))
        else:
            schema_versions[str(version)] += 1
        if not isinstance(document, dict) or document.get("prototype_only") is not True:
            missing_prototype_flag.append(relative)
            issues.append(_issue("RUNTIME_PROTOTYPE_FLAG", "warning", relative, "runtime document lacks prototype_only=true"))
    metrics.update({
        "runtime_file_count": len(RUNTIME_FILES),
        "runtime_missing": missing,
        "runtime_bad_schema": bad_schema,
        "runtime_schema_versions": dict(sorted(schema_versions.items())),
        "runtime_missing_prototype_flag": missing_prototype_flag,
        "runtime_root_types": dict(root_types),
    })


def _check_stable_ids(root: Path, issues: list[dict[str, str]], metrics: dict[str, Any]) -> None:
    checks = {
        "countries.json": "countries",
        "regions.json": "regions",
        "cities.json": "cities",
        "ports.json": "ports",
        "institutions.json": "institutions",
        "organizations.json": "catalog",
    }
    checked = 0
    duplicate_arrays = 0
    missing_ids = 0
    for relative, key in checks.items():
        document = _load(root / relative)
        values = document.get(key, []) if isinstance(document, dict) else []
        ids = []
        for index, item in enumerate(values):
            checked += 1
            value = item.get("id") if isinstance(item, dict) else None
            if not value:
                missing_ids += 1
                issues.append(_issue("STABLE_ID_MISSING", "error", f"{relative}:{key}[{index}]", "record lacks id"))
            else:
                ids.append(str(value))
        if len(ids) != len(set(ids)):
            duplicate_arrays += 1
            issues.append(_issue("STABLE_ID_DUPLICATE", "error", f"{relative}:{key}", "duplicate id in primary record array"))
    metrics.update({"stable_id_records_checked": checked, "stable_id_missing": missing_ids, "stable_id_duplicate_arrays": duplicate_arrays})


def build_report(repository_root: Path) -> dict[str, Any]:
    root = repository_root / "data" / "world_map"
    issues: list[dict[str, str]] = []
    metrics: dict[str, Any] = {}
    _check_city_shards(root, issues, metrics)
    _check_runtime_files(root, issues, metrics)
    _check_stable_ids(root, issues, metrics)
    errors = [issue for issue in issues if issue["severity"] == "error"]
    warnings = [issue for issue in issues if issue["severity"] == "warning"]
    return {
        "schema_version": SCHEMA_VERSION,
        "tool_id": TOOL_ID,
        "input_root": "data/world_map",
        "valid": not errors,
        "error_count": len(errors),
        "warning_count": len(warnings),
        "metrics": metrics,
        "issues": issues,
        "backlog": [
            {
                "id": "B4-01",
                "status": "no_action_needed" if metrics.get("duplicate_city_ids", 0) == 0 else "investigate",
                "item": "Preserve unique stable IDs across city-detail shards.",
                "trigger": "duplicate_city_ids > 0",
            },
            {
                "id": "B4-02",
                "status": "no_action_needed" if metrics.get("count_mismatches", 0) == 0 else "investigate",
                "item": "Keep shard declared counts and index counts synchronized.",
                "trigger": "count_mismatches > 0 or CITY_INDEX_COUNT issue",
            },
            {
                "id": "B4-03",
                "status": "no_action_needed" if metrics.get("invalid_city_coordinates", 0) == 0 else "investigate",
                "item": "Reject non-finite or out-of-range city coordinates before shard generation.",
                "trigger": "invalid_city_coordinates > 0",
            },
            {
                "id": "B4-04",
                "status": "no_action_needed" if not metrics.get("runtime_bad_schema") else "investigate",
                "item": "Keep all runtime-loader documents at schema_version 1 until an explicit migration exists.",
                "trigger": "runtime_bad_schema is non-empty",
            },
            {
                "id": "B4-05",
                "status": "review_only",
                "item": "Review any runtime document that lacks prototype_only=true before promoting it to authoritative runtime input.",
                "trigger": "runtime_missing_prototype_flag is non-empty",
            },
        ],
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# WWO WORLD DATA QUALITY AUDIT — BATCH 4",
        "",
        "Read-only structural QA for city-detail references, runtime metadata and stable IDs.",
        "",
        f"- Result: **{'PASS' if report['valid'] else 'FAIL'}**; errors: **{report['error_count']}**; warnings: **{report['warning_count']}**",
        "- Authoritative world-map JSON modified: **NO**",
        "",
        "## Metrics",
        "",
        "| Metric | Value |",
        "|---|---:|",
    ]
    for key, value in report["metrics"].items():
        if isinstance(value, (dict, list)):
            value = json.dumps(value, ensure_ascii=False, sort_keys=True)
        lines.append(f"| {key} | {value} |")
    lines.extend(["", "## Issues", "", "| Severity | Code | Path | Message |", "|---|---|---|---|"])
    if report["issues"]:
        for issue in report["issues"]:
            lines.append(f"| {issue['severity']} | {issue['code']} | `{issue['path']}` | {issue['message']} |")
    else:
        lines.append("| — | — | — | No issues found. |")
    lines.extend(["", "## Mechanically safe backlog", "", "| ID | Status | Item | Revisit trigger |", "|---|---|---|---|"])
    for item in report["backlog"]:
        lines.append(f"| {item['id']} | {item['status']} | {item['item']} | `{item['trigger']}` |")
    lines.extend(["", "- Any future source-data change should rerun the Batch 2 manifest and Batch 3 corpus before review.", "- This audit intentionally does not infer historical correctness or gameplay balance."])
    return "\n".join(lines) + "\n"


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json-output", type=Path, default=None)
    parser.add_argument("--markdown-output", type=Path, default=None)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    report = build_report(root)
    _write(root / (args.json_output or DEFAULT_JSON), json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    _write(root / (args.markdown_output or DEFAULT_MARKDOWN), render_markdown(report))
    print(f"World-data quality audit: {'PASS' if report['valid'] else 'FAIL'}")
    print(f"Errors: {report['error_count']}; warnings: {report['warning_count']}")
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
