#!/usr/bin/env python3
"""Build and validate a compact deterministic world-data regression corpus.

The corpus stores references and summaries, never copied authoritative JSON.
It is intended to detect source drift, missing coverage and representative
schema regressions while keeping the artifact small and reviewable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools import world_data_coverage_audit as coverage


SCHEMA_VERSION = 1
TOOL_ID = "wwo_world_data_regression_corpus_batch_3"
DEFAULT_OUTPUT = "docs/performance/world_data_regression_corpus_20260812.json"
DEFAULT_MARKDOWN = "docs/performance/world_data_regression_corpus_20260812.md"


def _stable_id(value: Any) -> str:
    if isinstance(value, dict):
        for key in ("id", "city_id", "country_code", "shard_id", "entity_id", "code"):
            candidate = value.get(key)
            if isinstance(candidate, (str, int)) and str(candidate):
                return str(candidate)
    return ""


def _representative_ids(value: Any, limit: int = 8) -> list[str]:
    candidates: list[str] = []

    def walk(node: Any) -> None:
        if len(candidates) >= limit:
            return
        if isinstance(node, list):
            for child in node:
                walk(child)
                if len(candidates) >= limit:
                    return
        elif isinstance(node, dict):
            candidate = _stable_id(node)
            if candidate and candidate not in candidates:
                candidates.append(candidate)
            for key in sorted(node):
                if key in {"id", "city_id", "country_code", "shard_id", "entity_id", "code"}:
                    continue
                child = node[key]
                if isinstance(child, (list, dict)):
                    walk(child)
                    if len(candidates) >= limit:
                        return

    walk(value)
    return candidates


def _representative_geometry(value: Any, limit: int = 6) -> list[list[float]]:
    points: list[list[float]] = []

    def walk(node: Any) -> None:
        if len(points) >= limit:
            return
        if coverage._numeric_pair(node):
            points.append([float(node[0]), float(node[1])])
            return
        if isinstance(node, list):
            for child in node:
                walk(child)
                if len(points) >= limit:
                    return
        elif isinstance(node, dict):
            for key in sorted(node):
                if key in coverage.GEOMETRY_KEYS or key in {"lon_lat", "bounds"}:
                    walk(node[key])
                    if len(points) >= limit:
                        return

    walk(value)
    return points


def _sample_payload(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            "root_keys": sorted(str(key) for key in value),
            "representative_ids": _representative_ids(value),
            "representative_geometry": _representative_geometry(value),
        }
    if isinstance(value, list):
        return {
            "root_length": len(value),
            "representative_ids": _representative_ids(value),
            "representative_geometry": _representative_geometry(value),
        }
    return {"root_type": type(value).__name__}


def _sample_hash(payload: Any) -> str:
    text = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _records_from_manifest(repository_root: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    root = repository_root / "data" / "world_map"
    records: list[dict[str, Any]] = []
    for file_profile in manifest["files"]:
        path = root / str(file_profile["path"])
        parsed = json.loads(path.read_text(encoding="utf-8"))
        sample = _sample_payload(parsed)
        records.append(
            {
                "path": file_profile["path"],
                "category": file_profile["category"],
                "sha256": file_profile["sha256"],
                "file_size_bytes": file_profile["file_size_bytes"],
                "root_type": file_profile["root_type"],
                "top_level_keys": file_profile["top_level_keys"],
                "record_count": file_profile["record_count"],
                "geometry_vertex_count": file_profile["geometry_vertex_count"],
                "sample": sample,
                "sample_sha256": _sample_hash(sample),
            }
        )
    return records


def _summary(records: list[dict[str, Any]]) -> dict[str, Any]:
    categories: dict[str, dict[str, int]] = {}
    for record in records:
        category = str(record["category"])
        summary = categories.setdefault(
            category,
            {
                "file_count": 0,
                "file_size_bytes": 0,
                "record_count": 0,
                "geometry_vertex_count": 0,
            },
        )
        summary["file_count"] += 1
        summary["file_size_bytes"] += int(record["file_size_bytes"])
        summary["record_count"] += int(record["record_count"])
        summary["geometry_vertex_count"] += int(record["geometry_vertex_count"])
    return {
        "file_count": len(records),
        "total_file_size_bytes": sum(int(record["file_size_bytes"]) for record in records),
        "total_record_count": sum(int(record["record_count"]) for record in records),
        "total_geometry_vertex_count": sum(int(record["geometry_vertex_count"]) for record in records),
        "categories": dict(sorted(categories.items())),
    }


def _records_sha256(records: list[dict[str, Any]]) -> str:
    return hashlib.sha256(
        json.dumps(records, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _expected_projection(repository_root: Path) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, Any]]:
    manifest = coverage.build_manifest(repository_root)
    records = _records_from_manifest(repository_root, manifest)
    return records, sorted({str(record["category"]) for record in records}), _summary(records)


def build_corpus(repository_root: Path) -> dict[str, Any]:
    records, categories, summary = _expected_projection(repository_root)
    corpus: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "tool_id": TOOL_ID,
        "input_root": "data/world_map",
        "source_manifest_tool_id": coverage.TOOL_ID,
        "file_count": len(records),
        "categories": categories,
        "summary": summary,
        "records": records,
        "corpus_sha256": _records_sha256(records),
    }
    errors = _validate_corpus_content(corpus, repository_root)
    corpus["validation"] = {"valid": not errors, "errors": errors}
    return corpus


def _validate_corpus_content(corpus: dict[str, Any], repository_root: Path) -> list[str]:
    errors: list[str] = []
    if corpus.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version mismatch")
    if corpus.get("tool_id") != TOOL_ID:
        errors.append("tool_id mismatch")
    if corpus.get("input_root") != "data/world_map":
        errors.append("input_root mismatch")
    if corpus.get("source_manifest_tool_id") != coverage.TOOL_ID:
        errors.append("source_manifest_tool_id mismatch")
    records = corpus.get("records")
    if not isinstance(records, list):
        return errors + ["records must be an array"]
    if any(not isinstance(record, dict) for record in records):
        errors.append("non-object corpus record")
    paths = [str(record.get("path", "")) for record in records if isinstance(record, dict)]
    if len(paths) != len(set(paths)):
        errors.append("duplicate corpus paths")
    root = repository_root / "data" / "world_map"
    try:
        root_resolved = root.resolve()
    except OSError:
        root_resolved = root
    actual_paths = sorted(path.relative_to(root).as_posix() for path in root.rglob("*.json") if path.is_file())
    actual_set = set(actual_paths)
    tracked_set = set(paths)
    for missing in sorted(actual_set - tracked_set):
        errors.append(f"missing source inventory entry: {missing}")
    for unexpected in sorted(tracked_set - actual_set):
        errors.append(f"unexpected source: {unexpected}")
    if sorted(paths) != actual_paths:
        errors.append("corpus paths do not match current world-map JSON set")
    for record in records:
        if not isinstance(record, dict):
            continue
        path = str(record.get("path", ""))
        source = root / path
        try:
            source.resolve().relative_to(root_resolved)
        except ValueError:
            errors.append(f"unexpected source: {path}")
            continue
        if not source.is_file():
            errors.append(f"missing source: {path}")
    expected_records, expected_categories, expected_summary = _expected_projection(repository_root)
    expected_by_path = {str(record["path"]): record for record in expected_records}
    for record in records:
        if not isinstance(record, dict):
            continue
        path = str(record.get("path", ""))
        expected = expected_by_path.get(path)
        if expected is None:
            continue
        for field in (
            "category",
            "sha256",
            "file_size_bytes",
            "root_type",
            "top_level_keys",
            "record_count",
            "geometry_vertex_count",
            "sample",
            "sample_sha256",
        ):
            if record.get(field) != expected[field]:
                if field == "sha256":
                    errors.append(f"source hash drift: {path}")
                elif field == "sample_sha256":
                    errors.append(f"sample hash drift: {path}")
                elif field == "record_count":
                    errors.append(f"record count drift: {path}")
                elif field in {"sample", "top_level_keys", "root_type", "geometry_vertex_count"}:
                    errors.append(f"derived summary drift: {path}:{field}")
                else:
                    errors.append(f"record metadata drift: {path}:{field}")
        if record.get("sample_sha256") != _sample_hash(record.get("sample")):
            errors.append(f"sample hash does not match stored sample: {path}")
    if corpus.get("file_count") != len(expected_records):
        errors.append("file_count mismatch")
    if corpus.get("categories") != expected_categories:
        errors.append("categories summary mismatch")
    if corpus.get("summary") != expected_summary:
        errors.append("summary mismatch")
    expected_corpus_sha256 = _records_sha256(records)
    if corpus.get("corpus_sha256") != expected_corpus_sha256:
        errors.append("corpus_sha256 mismatch")
    return errors


def validate_corpus(corpus: dict[str, Any], repository_root: Path) -> list[str]:
    errors = _validate_corpus_content(corpus, repository_root)
    expected_validation = {"valid": not errors, "errors": errors}
    if corpus.get("validation") != expected_validation:
        errors.append("validation summary mismatch")
    return errors

def render_markdown(corpus: dict[str, Any]) -> str:
    by_category: dict[str, list[dict[str, Any]]] = {}
    for record in corpus["records"]:
        by_category.setdefault(record["category"], []).append(record)
    lines = [
        "# WWO WORLD DATA REGRESSION CORPUS — BATCH 3",
        "",
        "Compact deterministic references to all world-map JSON inputs; authoritative data is not copied.",
        "",
        f"- Corpus tool: `{corpus['tool_id']}` schema v{corpus['schema_version']}",
        f"- Files covered: **{corpus['file_count']}**",
        f"- Corpus validation: **{'PASS' if corpus['validation']['valid'] else 'FAIL'}**",
        f"- Corpus SHA-256: `{corpus['corpus_sha256']}`",
        "",
        "## Category matrix",
        "",
        "| Category | Files | Records | Geometry vertices |",
        "|---|---:|---:|---:|",
    ]
    for category in sorted(by_category):
        records = by_category[category]
        lines.append(
            f"| {category} | {len(records)} | {sum(int(r['record_count']) for r in records)} | {sum(int(r['geometry_vertex_count']) for r in records)} |"
        )
    lines.extend(["", "## Representative sample matrix", "", "| Category | Path | IDs | Geometry sample points | Source SHA prefix | Sample SHA prefix |", "|---|---|---|---:|---|---|"])
    for record in corpus["records"]:
        sample = record["sample"]
        lines.append(
            "| %s | `%s` | `%s` | %d | `%s` | `%s` |"
            % (
                record["category"],
                record["path"],
                ", ".join(sample.get("representative_ids", [])),
                len(sample.get("representative_geometry", [])),
                record["sha256"][:12],
                record["sample_sha256"][:12],
            )
        )
    lines.extend(
        [
            "",
            "## Replay contract",
            "",
            "- Rebuild with `tools/world_data_regression_corpus.py` and compare `corpus_sha256`.",
            "- Validator checks exact current file set, per-file SHA-256, record counts and sample hashes.",
            "- Any source-data change intentionally fails validation and requires a new reviewed corpus checkpoint.",
            "- No CI gate or runtime integration is added by this corpus.",
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
    root = args.root.resolve()
    if args.check_existing:
        corpus = json.loads(args.check_existing.read_text(encoding="utf-8"))
        errors = validate_corpus(corpus, root)
        print(f"World-data regression corpus: {'PASS' if not errors else 'FAIL'}")
        for error in errors:
            print(f"ERROR: {error}")
        return 0 if not errors else 1
    corpus = build_corpus(root)
    json_output = (root / (args.json_output or DEFAULT_OUTPUT)).resolve()
    markdown_output = (root / (args.markdown_output or DEFAULT_MARKDOWN)).resolve()
    _write(json_output, json.dumps(corpus, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    _write(markdown_output, render_markdown(corpus))
    print(f"World-data regression corpus: {'PASS' if corpus['validation']['valid'] else 'FAIL'}")
    print(f"Files: {corpus['file_count']}; corpus_sha256: {corpus['corpus_sha256']}")
    return 0 if corpus["validation"]["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
