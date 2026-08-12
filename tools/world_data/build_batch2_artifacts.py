#!/usr/bin/env python3
"""Build deterministic Batch 2 manifests and safe derived staging outputs.

The tool reads repository data and assets only. It never rewrites authoritative
JSON, image files, or loader code. Outputs are deterministic JSON artifacts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path
from typing import Any, Mapping


SCHEMA_VERSION = "wwo_world_data_batch2_artifacts_v1"


def reject_nonfinite(value: str) -> Any:
    raise ValueError(f"non-finite JSON constant: {value}")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_nonfinite)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_text_bytes(path: Path) -> bytes:
    text = path.read_text(encoding="utf-8")
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def sha256_file(path: Path) -> str:
    if path.suffix.lower() in {".json", ".md", ".py", ".gd", ".ps1"}:
        return sha256_bytes(canonical_text_bytes(path))
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_path(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def png_dimensions(path: Path) -> list[int] | None:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", header[16:24])
    return [width, height]


def build_data_manifest(repository_root: Path) -> dict[str, Any]:
    data_root = repository_root / "data" / "world_map"
    rows: list[dict[str, Any]] = []
    parse_errors: list[dict[str, str]] = []
    for path in sorted(data_root.rglob("*.json")):
        rel = relative_path(path, repository_root)
        content = canonical_text_bytes(path)
        row: dict[str, Any] = {
            "path": rel,
            "bytes": len(content),
            "sha256": sha256_bytes(content),
        }
        try:
            document = read_json(path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            row["parse_error"] = str(exc)
            parse_errors.append({"path": rel, "error": str(exc)})
        else:
            if isinstance(document, dict):
                row["top_level_type"] = "object"
                row["top_level_keys"] = sorted(str(key) for key in document)
                row["collection_sizes"] = {
                    str(key): len(value)
                    for key, value in sorted(document.items(), key=lambda item: str(item[0]))
                    if isinstance(value, (dict, list))
                }
                if isinstance(document.get("schema_version"), str):
                    row["schema_version"] = document["schema_version"]
            elif isinstance(document, list):
                row["top_level_type"] = "array"
                row["top_level_keys"] = []
                row["collection_sizes"] = {"$": len(document)}
            else:
                row["top_level_type"] = type(document).__name__
                row["top_level_keys"] = []
                row["collection_sizes"] = {}
        rows.append(row)

    digest_input = "".join(f"{row['path']}\t{row['sha256']}\n" for row in rows).encode("utf-8")
    return {
        "schema_version": SCHEMA_VERSION,
        "root": "data/world_map",
        "file_count": len(rows),
        "files": rows,
        "parse_errors": parse_errors,
        "dataset_sha256": sha256_bytes(digest_input),
    }


def resource_to_local_path(repository_root: Path, resource: Any) -> Path | None:
    if not isinstance(resource, str) or not resource.startswith("res://"):
        return None
    return repository_root / resource[6:]


def build_asset_manifest(repository_root: Path) -> dict[str, Any]:
    flag_path = repository_root / "data" / "world_map" / "historical" / "flags_1900.json"
    flag_document = read_json(flag_path)
    records = flag_document.get("records", {}) if isinstance(flag_document, dict) else {}
    asset_root = repository_root / "assets" / "historical_flags" / "1900"
    asset_files = sorted(asset_root.glob("*.png"))
    references: list[dict[str, Any]] = []
    referenced_paths: set[str] = set()

    for record_id, record in sorted(records.items(), key=lambda item: str(item[0])):
        if not isinstance(record, Mapping):
            continue
        resource = record.get("asset_path")
        local_path = resource_to_local_path(repository_root, resource)
        if local_path is None:
            continue
        resource_path = str(resource)
        referenced_paths.add(resource_path[6:] if resource_path.startswith("res://") else resource_path)
        exists = local_path.is_file()
        actual_sha256 = sha256_file(local_path) if exists else None
        expected_sha256 = record.get("asset_sha256")
        actual_dimensions = png_dimensions(local_path) if exists and local_path.suffix.lower() == ".png" else None
        source_width = record.get("source_width")
        source_height = record.get("source_height")
        source_dimensions = [source_width, source_height] if isinstance(source_width, int) and isinstance(source_height, int) else None
        references.append(
            {
                "id": str(record_id),
                "asset_path": resource_path,
                "exists": exists,
                "sha256": actual_sha256,
                "expected_sha256": expected_sha256,
                "sha256_match": bool(exists and isinstance(expected_sha256, str) and actual_sha256 == expected_sha256),
                "rendered_dimensions": actual_dimensions,
                "source_dimensions": source_dimensions,
                "dimension_comparison": "NOT_COMPARABLE_SOURCE_METADATA",
                "snapshot_date": record.get("snapshot_date"),
                "flag_type": record.get("flag_type"),
                "confidence": record.get("confidence"),
            }
        )

    all_asset_paths = {relative_path(path, repository_root) for path in asset_files}
    missing_assets = [row["id"] for row in references if not row["exists"]]
    hash_mismatches = [row["id"] for row in references if row["exists"] and not row["sha256_match"]]
    orphan_assets = sorted(all_asset_paths - referenced_paths)
    verified = [row["id"] for row in references if row["exists"] and row["sha256_match"]]
    rendered_dimension_counts: dict[str, int] = {}
    for row in references:
        dimensions = row["rendered_dimensions"]
        key = "unknown" if dimensions is None else f"{dimensions[0]}x{dimensions[1]}"
        rendered_dimension_counts[key] = rendered_dimension_counts.get(key, 0) + 1

    return {
        "schema_version": SCHEMA_VERSION,
        "source": "data/world_map/historical/flags_1900.json",
        "asset_root": "assets/historical_flags/1900",
        "dimension_policy": "source_width/source_height describe upstream source metadata; rendered PNG dimensions are recorded, not compared as an equality contract",
        "record_count": len(records),
        "referenced_asset_count": len(references),
        "asset_file_count": len(asset_files),
        "rendered_dimension_counts": dict(sorted(rendered_dimension_counts.items())),
        "references": references,
        "verified_reference_ids": verified,
        "missing_assets": missing_assets,
        "hash_mismatches": hash_mismatches,
        "dimension_mismatches": [],
        "orphan_assets": orphan_assets,
    }


def build_regression_manifest(repository_root: Path) -> dict[str, Any]:
    fixture_path = repository_root / "tests" / "world_data" / "fixtures" / "qa_corpus.json"
    fixture = read_json(fixture_path)
    cases = fixture.get("cases", []) if isinstance(fixture, dict) else []
    return {
        "schema_version": SCHEMA_VERSION,
        "fixture": relative_path(fixture_path, repository_root),
        "fixture_sha256": sha256_file(fixture_path),
        "corpus_schema_version": fixture.get("schema_version") if isinstance(fixture, dict) else None,
        "case_count": len(cases),
        "case_ids": [case.get("id") for case in cases if isinstance(case, Mapping)],
        "expected_outcomes": [
            {"id": case.get("id"), "kind": case.get("kind"), "expected": case.get("expected", {})}
            for case in cases
            if isinstance(case, Mapping)
        ],
    }


def build_gap_report(data_manifest: Mapping[str, Any], asset_manifest: Mapping[str, Any], output_dir: Path) -> dict[str, Any]:
    findings_path = output_dir / "findings.json"
    findings = read_json(findings_path) if findings_path.is_file() else []
    code_counts: dict[str, int] = {}
    if isinstance(findings, list):
        for finding in findings:
            if isinstance(finding, Mapping):
                code = str(finding.get("code", "UNKNOWN"))
                code_counts[code] = code_counts.get(code, 0) + 1
    return {
        "schema_version": SCHEMA_VERSION,
        "data_parse_errors": data_manifest.get("parse_errors", []),
        "asset_gaps": {
            "missing_assets": asset_manifest.get("missing_assets", []),
            "hash_mismatches": asset_manifest.get("hash_mismatches", []),
            "dimension_mismatches": asset_manifest.get("dimension_mismatches", []),
            "orphan_assets": asset_manifest.get("orphan_assets", []),
        },
        "existing_validator_code_counts": dict(sorted(code_counts.items())),
        "manual_or_historical_items_remain": True,
        "notes": [
            "Historical identity ambiguity is not resolved mechanically.",
            "Geometry self-intersection findings remain in authoritative source data for review.",
            "Missing coverage is recorded in coverage.json and is not filled with invented facts.",
            "Source image dimensions are retained as metadata and are not treated as rendered PNG dimensions.",
        ],
    }


def build_asset_staging(asset_manifest: Mapping[str, Any]) -> dict[str, Any]:
    verified_ids = set(asset_manifest.get("verified_reference_ids", []))
    entries = [
        {
            "id": row["id"],
            "asset_path": row["asset_path"],
            "sha256": row["sha256"],
            "rendered_dimensions": row["rendered_dimensions"],
            "snapshot_date": row["snapshot_date"],
        }
        for row in asset_manifest.get("references", [])
        if isinstance(row, Mapping) and row.get("id") in verified_ids
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "authoritative_source_modified": False,
        "candidate_type": "verified_historical_flag_asset_index",
        "entries": entries,
    }


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="repository root")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("local-artifacts/world-data-audit"),
        help="output directory for deterministic artifacts",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repository_root = args.root.resolve()
    output_dir = args.output_dir if args.output_dir.is_absolute() else repository_root / args.output_dir
    data_manifest = build_data_manifest(repository_root)
    asset_manifest = build_asset_manifest(repository_root)
    regression_manifest = build_regression_manifest(repository_root)
    gap_report = build_gap_report(data_manifest, asset_manifest, output_dir)
    asset_staging = build_asset_staging(asset_manifest)

    write_json(output_dir / "batch2_data_manifest.json", data_manifest)
    write_json(output_dir / "batch2_asset_manifest.json", asset_manifest)
    write_json(output_dir / "batch2_regression_manifest.json", regression_manifest)
    write_json(output_dir / "batch2_gap_report.json", gap_report)
    write_json(output_dir / "batch2_asset_staging_candidates.json", asset_staging)

    gate_passed = not data_manifest["parse_errors"] and not any(
        asset_manifest[key] for key in ("missing_assets", "hash_mismatches", "orphan_assets")
    )
    summary = {
        "data_files": data_manifest["file_count"],
        "data_parse_errors": len(data_manifest["parse_errors"]),
        "flag_records": asset_manifest["record_count"],
        "flag_asset_files": asset_manifest["asset_file_count"],
        "verified_flag_assets": len(asset_manifest["verified_reference_ids"]),
        "corpus_cases": regression_manifest["case_count"],
        "mechanical_gate": "PASS" if gate_passed else "REVIEW_REQUIRED",
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0 if gate_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
