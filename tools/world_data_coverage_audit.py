#!/usr/bin/env python3
"""Deterministic, read-only coverage audit for all world-map JSON inputs.

This tool inventories every JSON file below data/world_map without changing
authoritative data. It emits a stable machine-readable manifest and a human
coverage matrix. Files are parsed one at a time so large city-detail shards do
not accumulate in memory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
TOOL_ID = "wwo_world_data_coverage_audit_batch_2"
DEFAULT_JSON = "docs/performance/world_data_coverage_matrix_20260812.json"
DEFAULT_MARKDOWN = "docs/performance/world_data_coverage_matrix_20260812.md"

RUNTIME_LOADER_PATHS = (
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

RECORD_ARRAY_KEYS = {
    "countries",
    "regions",
    "administrative_units",
    "cities",
    "ports",
    "segments",
    "routes",
    "features",
    "institutions",
    "catalog",
    "characters",
    "organizations",
    "relationships",
    "shards",
    "flags",
    "units",
    "records",
    "political_entities",
    "region_profiles",
    "identities",
    "overrides",
}

GEOMETRY_KEYS = {
    "polygons",
    "holes",
    "outer",
    "points",
    "coordinates",
    "graticule",
    "triangles",
    "lods",
    "geometry",
    "geometry_cache",
}


def _category(relative: str) -> str:
    if relative in RUNTIME_LOADER_PATHS:
        return "runtime_loader"
    if relative == "country_flag_palettes.json":
        return "runtime_supporting"
    if relative.startswith("historical/") or relative in {
        "historical_political_entities_1900.json",
        "world_admin1.json",
    }:
        return "historical"
    if relative in {"city_detail/index.json", "city_detail/LICENSE.json"}:
        return "city_detail_metadata"
    if relative.startswith("city_detail/countries/"):
        return "city_detail_country_shard"
    if relative.startswith("city_detail/france/"):
        return "city_detail_region_shard"
    return "uncategorized"


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _numeric_pair(value: Any) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(
        _is_number(item) for item in value
    )


def _count_geometry_points(value: Any) -> int:
    if _numeric_pair(value):
        return 1
    if isinstance(value, list):
        return sum(_count_geometry_points(item) for item in value)
    return 0


def _profile_value(
    value: Any,
    path: str,
    stats: dict[str, Any],
    largest_arrays: list[dict[str, Any]],
    largest_maps: list[dict[str, Any]],
    largest_records: list[dict[str, Any]],
    key_hint: str = "",
    geometry_context: bool = False,
) -> None:
    if isinstance(value, dict):
        stats["decoded_object_count"] += 1
        largest_maps.append({"path": path, "count": len(value)})
        for key, child in value.items():
            child_path = f"{path}.{key}"
            _profile_value(
                child,
                child_path,
                stats,
                largest_arrays,
                largest_maps,
                largest_records,
                str(key),
                geometry_context or str(key) in GEOMETRY_KEYS,
            )
        return
    if isinstance(value, list):
        stats["decoded_array_count"] += 1
        is_record_array = key_hint in RECORD_ARRAY_KEYS
        if is_record_array:
            stats["record_count"] += len(value)
            largest_records.append(
                {"path": path, "count": len(value), "key": key_hint}
            )
        if geometry_context:
            stats["geometry_vertex_count"] += _count_geometry_points(value)
        largest_arrays.append(
            {
                "path": path,
                "count": len(value),
                "record_like": is_record_array,
                "geometry_context": geometry_context,
            }
        )
        for index, child in enumerate(value):
            _profile_value(
                child,
                f"{path}[{index}]",
                stats,
                largest_arrays,
                largest_maps,
                largest_records,
                key_hint,
                geometry_context,
            )
        return
    stats["decoded_scalar_count"] += 1


def _top(items: Iterable[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    return sorted(
        items,
        key=lambda item: (-int(item.get("count", 0)), str(item.get("path", ""))),
    )[:limit]


def _estimate_decoded_bytes(value: Any) -> int:
    """A transparent lower-bound-ish recursive estimate, not allocator RSS."""
    if isinstance(value, dict):
        return 64 + sum(32 + len(str(key)) + _estimate_decoded_bytes(child) for key, child in value.items())
    if isinstance(value, list):
        return 32 + 8 * len(value) + sum(_estimate_decoded_bytes(child) for child in value)
    if isinstance(value, str):
        return 49 + len(value.encode("utf-8"))
    if isinstance(value, (int, float)):
        return 24
    if value is None or isinstance(value, bool):
        return 16
    return 32


def _profile_file(root: Path, path: Path) -> dict[str, Any]:
    relative = path.relative_to(root).as_posix()
    raw = path.read_bytes()
    result: dict[str, Any] = {
        "path": relative,
        "category": _category(relative),
        "file_size_bytes": len(raw),
        "sha256": _sha256(raw),
        "parse_status": "ok",
        "root_type": "",
        "top_level_keys": [],
        "record_count": 0,
        "decoded_object_count": 0,
        "decoded_array_count": 0,
        "decoded_scalar_count": 0,
        "geometry_vertex_count": 0,
        "decoded_data_bytes_estimate": 0,
        "largest_arrays": [],
        "largest_maps": [],
        "largest_records": [],
    }
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        result["parse_status"] = f"error: {type(exc).__name__}: {exc}"
        return result
    result["root_type"] = type(parsed).__name__
    if isinstance(parsed, dict):
        result["top_level_keys"] = sorted(str(key) for key in parsed.keys())
    stats: dict[str, Any] = {
        "record_count": 0,
        "decoded_object_count": 0,
        "decoded_array_count": 0,
        "decoded_scalar_count": 0,
        "geometry_vertex_count": 0,
    }
    arrays: list[dict[str, Any]] = []
    maps: list[dict[str, Any]] = []
    records: list[dict[str, Any]] = []
    _profile_value(parsed, "$", stats, arrays, maps, records)
    result.update(stats)
    result["decoded_data_bytes_estimate"] = _estimate_decoded_bytes(parsed)
    result["largest_arrays"] = _top(arrays)
    result["largest_maps"] = _top(maps)
    result["largest_records"] = _top(records)
    return result


def _aggregate_category(files: list[dict[str, Any]]) -> dict[str, Any]:
    total = {
        "file_count": len(files),
        "file_size_bytes": sum(int(item["file_size_bytes"]) for item in files),
        "record_count": sum(int(item["record_count"]) for item in files),
        "decoded_object_count": sum(int(item["decoded_object_count"]) for item in files),
        "decoded_array_count": sum(int(item["decoded_array_count"]) for item in files),
        "decoded_scalar_count": sum(int(item["decoded_scalar_count"]) for item in files),
        "geometry_vertex_count": sum(int(item["geometry_vertex_count"]) for item in files),
        "decoded_data_bytes_estimate": sum(
            int(item["decoded_data_bytes_estimate"]) for item in files
        ),
        "parse_error_count": sum(item["parse_status"] != "ok" for item in files),
        "largest_files": sorted(
            [
                {"path": item["path"], "bytes": int(item["file_size_bytes"])}
                for item in files
            ],
            key=lambda item: (-item["bytes"], item["path"]),
        )[:10],
    }
    arrays: list[dict[str, Any]] = []
    maps: list[dict[str, Any]] = []
    records: list[dict[str, Any]] = []
    for item in files:
        arrays.extend(
            {**entry, "file": item["path"]} for entry in item["largest_arrays"]
        )
        maps.extend({**entry, "file": item["path"]} for entry in item["largest_maps"])
        records.extend(
            {**entry, "file": item["path"]} for entry in item["largest_records"]
        )
    total["largest_arrays"] = _top(arrays)
    total["largest_maps"] = _top(maps)
    total["largest_records"] = _top(records)
    return total


def _validation(manifest: dict[str, Any], root: Path) -> list[str]:
    errors: list[str] = []
    files = manifest.get("files")
    if manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version mismatch")
    if manifest.get("tool_id") != TOOL_ID:
        errors.append("tool_id mismatch")
    if not isinstance(files, list):
        return ["files must be an array"]
    paths = [item.get("path") for item in files if isinstance(item, dict)]
    if len(paths) != len(set(paths)):
        errors.append("duplicate file paths")
    actual = sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*.json")
        if path.is_file()
    )
    if sorted(paths) != actual:
        missing = sorted(set(actual) - set(paths))
        extra = sorted(set(paths) - set(actual))
        if missing:
            errors.append(f"missing files: {missing[:5]}")
        if extra:
            errors.append(f"extra files: {extra[:5]}")
    for required in RUNTIME_LOADER_PATHS:
        if required not in paths:
            errors.append(f"runtime loader file missing: {required}")
    for item in files:
        if item.get("parse_status") != "ok":
            errors.append(f"parse failure: {item.get('path')}")
    category_total = sum(int(value.get("file_count", 0)) for value in manifest.get("categories", {}).values())
    if category_total != len(files):
        errors.append("category file counts do not cover files")
    return errors


def build_manifest(repository_root: Path) -> dict[str, Any]:
    root = repository_root / "data" / "world_map"
    files = [_profile_file(root, path) for path in sorted(root.rglob("*.json")) if path.is_file()]
    categories: dict[str, list[dict[str, Any]]] = defaultdict(list)
    family_files: dict[tuple[str, tuple[str, ...]], int] = Counter()
    for item in files:
        categories[str(item["category"])].append(item)
        family_files[(str(item["root_type"]), tuple(item["top_level_keys"]))] += 1
    category_summary = {
        key: _aggregate_category(categories[key]) for key in sorted(categories)
    }
    schema_families = [
        {
            "root_type": root_type,
            "top_level_keys": list(keys),
            "file_count": count,
        }
        for (root_type, keys), count in sorted(family_files.items())
    ]
    manifest: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "tool_id": TOOL_ID,
        "input_root": "data/world_map",
        "runtime_loader_paths": list(RUNTIME_LOADER_PATHS),
        "file_count": len(files),
        "total_file_size_bytes": sum(int(item["file_size_bytes"]) for item in files),
        "categories": category_summary,
        "schema_families": schema_families,
        "files": files,
    }
    errors = _validation(manifest, root)
    manifest["validation"] = {"valid": not errors, "errors": errors}
    return manifest


def _json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _format_bytes(value: int) -> str:
    if value < 1024:
        return f"{value} B"
    if value < 1024 * 1024:
        return f"{value / 1024:.1f} KiB"
    return f"{value / 1048576:.2f} MiB"


def render_markdown(manifest: dict[str, Any]) -> str:
    lines = [
        "# WWO WORLD DATA COVERAGE MATRIX — BATCH 2",
        "",
        "Read-only deterministic inventory of every JSON file below `data/world_map`.",
        "",
        f"- Tool: `{manifest['tool_id']}` schema v{manifest['schema_version']}",
        f"- Files: **{manifest['file_count']}**; raw size: **{_format_bytes(int(manifest['total_file_size_bytes']))}**",
        f"- Manifest validation: **{'PASS' if manifest['validation']['valid'] else 'FAIL'}**",
        "- Authoritative world-map JSON was not modified.",
        "",
        "## Category coverage",
        "",
        "| Category | Files | Raw bytes | Records | Objects | Arrays | Geometry vertices | Decoded estimate | Parse errors |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for category, summary in manifest["categories"].items():
        lines.append(
            "| %s | %d | %s | %d | %d | %d | %d | %s | %d |"
            % (
                category,
                summary["file_count"],
                _format_bytes(summary["file_size_bytes"]),
                summary["record_count"],
                summary["decoded_object_count"],
                summary["decoded_array_count"],
                summary["geometry_vertex_count"],
                _format_bytes(summary["decoded_data_bytes_estimate"]),
                summary["parse_error_count"],
            )
        )
    lines.extend(["", "## Runtime-loader matrix", "", "| Path | Present | Category | Bytes | SHA-256 prefix | Parse |", "|---|---|---|---:|---|---|"])
    by_path = {item["path"]: item for item in manifest["files"]}
    for path in manifest["runtime_loader_paths"]:
        item = by_path.get(path, {})
        lines.append(
            "| `%s` | %s | %s | %s | `%s` | %s |"
            % (
                path,
                "yes" if item else "NO",
                item.get("category", ""),
                _format_bytes(int(item.get("file_size_bytes", 0))),
                str(item.get("sha256", ""))[:12],
                item.get("parse_status", "missing"),
            )
        )
    lines.extend(["", "## Largest structures", "", "| Kind | File | Path | Count |", "|---|---|---|---:|"])
    for category, summary in manifest["categories"].items():
        for entry in summary["largest_files"][:3]:
            lines.append(f"| file | `{entry['path']}` | — | {entry['bytes']} |")
        for entry in summary["largest_records"][:3]:
            lines.append(f"| records | `{entry.get('file', '')}` | `{entry['path']}` | {entry['count']} |")
        for entry in summary["largest_arrays"][:2]:
            lines.append(f"| array | `{entry.get('file', '')}` | `{entry['path']}` | {entry['count']} |")
    lines.extend(["", "## Schema-family matrix", "", "| Root type | Top-level key signature | Files |", "|---|---|---:|"])
    for family in manifest["schema_families"]:
        signature = ", ".join(family["top_level_keys"]) or "(none)"
        lines.append(f"| {family['root_type']} | `{signature}` | {family['file_count']} |")
    lines.extend(
        [
            "",
            "## Determinism and safety",
            "",
            "- Files are traversed in sorted relative-path order and each file is parsed sequentially.",
            "- SHA-256, sizes, category summaries, schema families and validation fields are stable for unchanged inputs.",
            "- No synthetic or copied authoritative data is written; output is a manifest/report only.",
            "- Real process RSS/heap is outside this audit's reliable measurement boundary: **NOT MEASURED**.",
            "",
            "## Validation",
            "",
            f"- Full JSON coverage: {'PASS' if manifest['validation']['valid'] else 'FAIL'}.",
            f"- Runtime loader coverage: {len(manifest['runtime_loader_paths'])}/{len(manifest['runtime_loader_paths'])} paths declared and present.",
            "- Focused validator and deterministic replay are tracked separately in the Batch 2/3 test tooling.",
        ]
    )
    return "\n".join(lines) + "\n"


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json-output", type=Path, default=None)
    parser.add_argument("--markdown-output", type=Path, default=None)
    parser.add_argument("--check-existing", type=Path, default=None)
    args = parser.parse_args(argv)
    repository_root = args.root.resolve()
    if args.check_existing:
        manifest = json.loads(args.check_existing.read_text(encoding="utf-8"))
        root = repository_root / "data" / "world_map"
        errors = _validation(manifest, root)
        print(f"World-data coverage manifest: {'PASS' if not errors else 'FAIL'}")
        for error in errors:
            print(f"ERROR: {error}")
        return 0 if not errors else 1
    manifest = build_manifest(repository_root)
    json_output = (repository_root / (args.json_output or DEFAULT_JSON)).resolve()
    markdown_output = (repository_root / (args.markdown_output or DEFAULT_MARKDOWN)).resolve()
    _write(json_output, _json_text(manifest))
    _write(markdown_output, render_markdown(manifest))
    print(f"World-data coverage manifest: {'PASS' if manifest['validation']['valid'] else 'FAIL'}")
    print(f"Files: {manifest['file_count']}; bytes: {manifest['total_file_size_bytes']}")
    print(f"JSON: {json_output}")
    print(f"Markdown: {markdown_output}")
    return 0 if manifest["validation"]["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
