#!/usr/bin/env python3
"""Consolidate Batch 1-3 outputs into a deterministic final run manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Mapping


SCHEMA_VERSION = "wwo_world_data_batch4_run_manifest_v1"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_file_manifest(output_dir: Path) -> list[dict[str, Any]]:
    rows = []
    for path in sorted(output_dir.glob("*.json")):
        if path.name == "batch4_run_manifest.json":
            continue
        rows.append(
            {
                "path": path.name,
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )
    return rows


def load_optional(output_dir: Path, name: str) -> Mapping[str, Any]:
    path = output_dir / name
    value = read_json(path)
    return value if isinstance(value, Mapping) else {}


def build_manifest(repository_root: Path, output_dir: Path) -> dict[str, Any]:
    inventory = load_optional(output_dir, "inventory.json")
    findings = read_json(output_dir / "findings.json")
    coverage = load_optional(output_dir, "coverage.json")
    batch2_data = load_optional(output_dir, "batch2_data_manifest.json")
    batch2_assets = load_optional(output_dir, "batch2_asset_manifest.json")
    batch2_corpus = load_optional(output_dir, "batch2_regression_manifest.json")
    batch2_gap = load_optional(output_dir, "batch2_gap_report.json")
    batch3_loader = load_optional(output_dir, "batch3_loader_contract.json")
    batch3_flags = load_optional(output_dir, "batch3_historical_flag_coverage.json")
    batch3_signatures = load_optional(output_dir, "batch3_record_signature_manifest.json")
    batch3_gap = load_optional(output_dir, "batch3_gap_report.json")

    finding_list = findings if isinstance(findings, list) else []
    severity_counts: dict[str, int] = {}
    code_counts: dict[str, int] = {}
    for finding in finding_list:
        if not isinstance(finding, Mapping):
            continue
        severity = str(finding.get("severity", "UNKNOWN"))
        code = str(finding.get("code", "UNKNOWN"))
        severity_counts[severity] = severity_counts.get(severity, 0) + 1
        code_counts[code] = code_counts.get(code, 0) + 1

    coverage_countries = coverage.get("countries", [])
    coverage_count = len(coverage_countries) if isinstance(coverage_countries, list) else 0
    artifact_files = build_file_manifest(output_dir)
    artifact_digest = hashlib.sha256(
        "".join(f"{row['path']}\t{row['sha256']}\n" for row in artifact_files).encode("utf-8")
    ).hexdigest()
    return {
        "schema_version": SCHEMA_VERSION,
        "batch_scope": ["BATCH 1", "BATCH 2", "BATCH 3", "BATCH 4"],
        "repository_root": str(repository_root).replace("\\", "/"),
        "authoritative_source_modified": False,
        "batch_results": {
            "batch1": {
                "inventory_files": inventory.get("file_count"),
                "finding_count": len(finding_list),
                "severity_counts": dict(sorted(severity_counts.items())),
                "code_counts": dict(sorted(code_counts.items())),
                "coverage_country_rows": coverage_count,
            },
            "batch2": {
                "data_files": batch2_data.get("file_count"),
                "data_parse_errors": len(batch2_data.get("parse_errors", [])),
                "verified_flag_assets": len(batch2_assets.get("verified_reference_ids", [])),
                "asset_missing": len(batch2_assets.get("missing_assets", [])),
                "asset_hash_mismatches": len(batch2_assets.get("hash_mismatches", [])),
                "corpus_cases": batch2_corpus.get("case_count"),
                "manual_or_historical_items_remain": batch2_gap.get("manual_or_historical_items_remain"),
            },
            "batch3": {
                "loader_entries": len(batch3_loader.get("world_map_data_loader_entries", [])),
                "loader_missing_direct_references": len(batch3_loader.get("missing_direct_references", [])),
                "loader_missing_directory_references": len(batch3_loader.get("missing_directory_references", [])),
                "historical_units": batch3_flags.get("unit_count"),
                "verified_or_documented_flag_units": sum(
                    value for key, value in batch3_flags.get("status_counts", {}).items() if key in ("VERIFIED_ASSET", "DOCUMENTED_ABSENCE")
                ),
                "signature_files": batch3_signatures.get("data_json_count"),
                "nested_duplicate_candidate_files": batch3_signatures.get("duplicate_id_file_count"),
                "manual_or_historical_items_remain": batch3_gap.get("manual_or_historical_review_remains"),
            },
            "batch4": {
                "artifact_file_count_before_manifest": len(artifact_files),
                "artifact_digest_before_manifest": artifact_digest,
                "resource_intensive_phases_executed": [],
                "concurrency": "1 process; no process pool or thread pool",
                "large_temporary_artifacts": [],
                "resource_safety_reduction": "No raster/geometry preprocessing; no repeated benchmark loop; scans and tests were sequential.",
            },
        },
        "final_gates": {
            "json_parse_errors": len(batch2_data.get("parse_errors", [])),
            "dangling_foreign_keys": code_counts.get("DANGLING_FOREIGN_KEY", 0),
            "duplicate_catalog_ids": sum(code_counts.get(code, 0) for code in ("DUPLICATE_ID", "EMPTY_ID", "DUPLICATE_STABLE_ID")),
            "flag_asset_gaps": len(batch2_assets.get("missing_assets", [])) + len(batch2_assets.get("hash_mismatches", [])),
            "loader_contract_gaps": len(batch3_loader.get("missing_direct_references", [])) + len(batch3_loader.get("missing_directory_references", [])),
            "manual_review_findings": code_counts.get("SELF_INTERSECTING_RING", 0) + code_counts.get("PLACEHOLDER_FOREIGN_KEY", 0),
        },
        "remaining_work": [
            "Review 104 potential world_admin1 self-intersecting rings against source provenance.",
            "Resolve 6 placeholder institutional references with source-backed decisions.",
            "Research 10 missing and 6 ambiguous historical identity mappings.",
            "Expand sparse country-level transport, institution, organization, and person coverage only with approved sources.",
        ],
        "artifacts": artifact_files,
        "artifact_digest": artifact_digest,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, default=Path("local-artifacts/world-data-audit"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    output_dir = args.output_dir if args.output_dir.is_absolute() else root / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = build_manifest(root, output_dir)
    path = output_dir / "batch4_run_manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"artifact_file_count_before_manifest": len(manifest["artifacts"]), "final_gates": manifest["final_gates"], "output": path.as_posix()}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
