#!/usr/bin/env python3
"""Stage non-authoritative name review candidates from excluded repository sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterator, Sequence

from . import world_names as wn


REVIEWABLE_STATUSES = {"world_map_scanned_only", "non_world_map_scanned_only"}
EXCLUDED_REVIEW_PATHS = {
    "data/world_map/world_admin1.json",
    "data/world_map/world_coastlines.json",
    "data/world_map/map_geometry_cache.json",
}
SCHEMA_VERSION = wn.SCHEMA_VERSION


def _canonical_json(document: Any) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _write_json(path: Path, document: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(document), encoding="utf-8")


def _iter_string_values(value: Any, pointer: str) -> Iterator[tuple[str, str]]:
    if isinstance(value, str):
        text = value.strip()
        if text:
            yield pointer, text
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _iter_string_values(child, f"{pointer}[{index}]")


def _iter_name_observations(
    value: Any,
    pointer: str = "$",
) -> Iterator[tuple[str, str, str, dict[str, Any]]]:
    if not isinstance(value, dict):
        return
    for field, field_value in value.items():
        field_pointer = wn._json_pointer(pointer, field)
        if field in wn.NAME_FIELD_BY_KEY:
            for value_pointer, text in _iter_string_values(field_value, field_pointer):
                yield field, text, value_pointer, value
        if isinstance(field_value, (dict, list)):
            if isinstance(field_value, dict):
                yield from _iter_name_observations(field_value, field_pointer)
            else:
                for index, child in enumerate(field_value):
                    yield from _iter_name_observations(child, f"{field_pointer}[{index}]")


def _source_is_reviewable(row: dict[str, Any]) -> bool:
    return (
        row.get("status") in REVIEWABLE_STATUSES
        and row.get("source_file") not in EXCLUDED_REVIEW_PATHS
    )


def build_candidate_collision_ledger(
    candidates: Sequence[dict[str, Any]],
) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for candidate in candidates:
        normalized = candidate["normalized_name"]
        if normalized:
            groups[normalized].append(candidate)

    collisions: list[dict[str, Any]] = []
    for normalized_name, items in sorted(groups.items()):
        candidate_ids = sorted({item["candidate_id"] for item in items})
        if len(candidate_ids) < 2:
            continue
        collisions.append(
            {
                "normalized_name": normalized_name,
                "candidate_ids": candidate_ids,
                "raw_names": sorted({item["alias"] for item in items}),
                "source_files": sorted({item["source_file"] for item in items}),
                "collision_kind": "review_candidate_normalized_collision",
                "authority": "non_authoritative",
            }
        )
    return {
        "schema_version": SCHEMA_VERSION,
        "normalizer_id": wn.NORMALIZER_ID,
        "policy": {
            "one_to_many_mappings_are_preserved": True,
            "candidate_ids_are_not_authoritative": True,
            "no_historical_contradiction_is_inferred": True,
        },
        "summary": {
            "candidate_collision_groups": len(collisions),
            "candidate_ids_in_collision_groups": len(
                {candidate_id for item in collisions for candidate_id in item["candidate_ids"]}
            ),
        },
        "collisions": collisions,
    }


def build_review_candidates(
    root: Path,
    coverage: dict[str, Any],
) -> dict[str, Any]:
    coverage_by_file = {
        row["source_file"]: row
        for row in coverage.get("files", [])
    }
    candidates: list[dict[str, Any]] = []
    for source_file in sorted(coverage_by_file):
        row = coverage_by_file[source_file]
        if not _source_is_reviewable(row):
            continue
        source_path = root / source_file
        data = json.loads(source_path.read_text(encoding="utf-8"))
        for field, alias, pointer, record in _iter_name_observations(data):
            _, alias_type = wn.NAME_FIELD_BY_KEY[field]
            candidate_id = f"source:{source_file}#{pointer}"
            candidates.append(
                {
                    "candidate_id": candidate_id,
                    "entity_id": candidate_id,
                    "entity_id_kind": "source_record_key",
                    "entity_type": "review_name_candidate",
                    "alias": alias,
                    "normalized_name": wn.normalize_name(alias),
                    "language": wn._language_for(field),
                    "script": wn._script_for(alias),
                    "alias_type": alias_type,
                    "valid_from": wn._valid_date_value(record, "valid_from"),
                    "valid_to": wn._valid_date_value(record, "valid_to"),
                    "source": f"{source_file}#{pointer}",
                    "source_file": source_file,
                    "source_field": field,
                    "source_sha256": row["sha256"],
                    "source_status": row["status"],
                    "authority": "non_authoritative",
                    "review_reason": "direct repository evidence only; semantic authority is not asserted",
                }
            )

    candidates.sort(key=lambda item: item["candidate_id"])
    status_counts = Counter(item["source_status"] for item in candidates)
    candidate_document = {
        "schema_version": SCHEMA_VERSION,
        "normalizer_id": wn.NORMALIZER_ID,
        "policy": {
            "stable_ids_are_authoritative": True,
            "source_record_keys_are_non_authoritative": True,
            "no_unsourced_translation": True,
            "modern_reference_sources_excluded": True,
        },
        "summary": {
            "candidate_count": len(candidates),
            "source_file_count": len({item["source_file"] for item in candidates}),
            "world_map_scanned_only_candidates": status_counts.get("world_map_scanned_only", 0),
            "non_world_map_scanned_only_candidates": status_counts.get(
                "non_world_map_scanned_only", 0
            ),
            "normalized_name_count": len(
                {item["normalized_name"] for item in candidates if item["normalized_name"]}
            ),
        },
        "candidates": candidates,
    }
    return candidate_document


def validate_review_candidates(
    candidate_document: dict[str, Any],
    collision_ledger: dict[str, Any],
    coverage: dict[str, Any],
) -> list[str]:
    errors: list[str] = []
    if candidate_document.get("schema_version") != SCHEMA_VERSION:
        errors.append("review candidates schema_version mismatch")
    if candidate_document.get("normalizer_id") != wn.NORMALIZER_ID:
        errors.append("review candidates normalizer_id mismatch")
    candidates = candidate_document.get("candidates")
    if not isinstance(candidates, list):
        return ["review candidates are not a list"]
    candidate_ids = [item.get("candidate_id") for item in candidates]
    if candidate_ids != sorted(candidate_ids):
        errors.append("review candidates are not sorted")
    if len(candidate_ids) != len(set(candidate_ids)):
        errors.append("review candidates contain duplicate candidate_id values")
    coverage_by_file = {row["source_file"]: row for row in coverage.get("files", [])}
    for item in candidates:
        source_file = item.get("source_file")
        row = coverage_by_file.get(source_file)
        if row is None:
            errors.append(f"candidate points to unknown source file: {source_file}")
            continue
        if not _source_is_reviewable(row):
            errors.append(f"candidate source is not reviewable: {source_file}")
        if item.get("entity_id_kind") != "source_record_key":
            errors.append(f"candidate is not source-record keyed: {item.get('candidate_id')}")
        if item.get("authority") != "non_authoritative":
            errors.append(f"candidate asserts authority: {item.get('candidate_id')}")
        if item.get("normalized_name") != wn.normalize_name(str(item.get("alias", ""))):
            errors.append(f"candidate normalizer mismatch: {item.get('candidate_id')}")
        if item.get("source_sha256") != row.get("sha256"):
            errors.append(f"candidate source hash mismatch: {item.get('candidate_id')}")
        if item.get("source") != f"{source_file}#{item.get('candidate_id', '').split('#', 1)[-1]}":
            errors.append(f"candidate source pointer mismatch: {item.get('candidate_id')}")
    expected_ledger = build_candidate_collision_ledger(candidates)
    if collision_ledger != expected_ledger:
        errors.append("candidate collision ledger does not replay deterministically")
    return errors


def benchmark_build(root: Path, repetitions: int) -> dict[str, Any]:
    if repetitions <= 0:
        return {
            "schema_version": SCHEMA_VERSION,
            "operation": "world_names.build_artifacts",
            "skipped": True,
        }
    timings: list[float] = []
    last: dict[str, Any] | None = None
    for _ in range(repetitions):
        start = time.perf_counter()
        last = wn.build_artifacts(root)
        timings.append(time.perf_counter() - start)
    assert last is not None
    return {
        "schema_version": SCHEMA_VERSION,
        "operation": "world_names.build_artifacts",
        "skipped": False,
        "repetitions": repetitions,
        "elapsed_seconds": round(sum(timings), 6),
        "min_seconds": round(min(timings), 6),
        "max_seconds": round(max(timings), 6),
        "python": platform.python_version(),
        "platform": platform.platform(),
        "artifact_counts": {
            "entities": len(last["inventory"]["entities"]),
            "aliases": len(last["aliases"]["aliases"]),
            "coverage_files": len(last["coverage_manifest"]["files"]),
        },
    }


def build_review_artifacts(
    root: Path,
    benchmark_repetitions: int = 0,
) -> dict[str, Any]:
    base = wn.build_artifacts(root)
    candidates = build_review_candidates(root, base["coverage_manifest"])
    ledger = build_candidate_collision_ledger(candidates["candidates"])
    errors = list(base["validation_errors"])
    errors.extend(validate_review_candidates(candidates, ledger, base["coverage_manifest"]))
    benchmark = benchmark_build(root, benchmark_repetitions)
    return {
        "base": base,
        "review_candidates": candidates,
        "collision_ledger": ledger,
        "performance_benchmark": benchmark,
        "validation_errors": errors,
    }


def render_report(
    artifacts: dict[str, Any],
    starting_master: str,
    commit: str,
    push: str,
) -> str:
    base = artifacts["base"]
    candidates = artifacts["review_candidates"]
    ledger = artifacts["collision_ledger"]
    benchmark = artifacts["performance_benchmark"]
    coverage = base["coverage_manifest"]["summary"]
    return "\n".join(
        [
            "# WWO WORLD NAMES & ALIASES - BATCH 3 REPORT",
            "",
            f"Starting master: {starting_master}",
            "",
            "## Safe review candidates",
            "",
            f"- Non-authoritative candidates: {candidates['summary']['candidate_count']}",
            f"- Candidate source files: {candidates['summary']['source_file_count']}",
            f"- World-map scanned-only candidates: {candidates['summary']['world_map_scanned_only_candidates']}",
            f"- Non-world-map scanned-only candidates: {candidates['summary']['non_world_map_scanned_only_candidates']}",
            f"- Candidate normalized collision groups: {ledger['summary']['candidate_collision_groups']}",
            "- Modern reference and geometry sources excluded: YES",
            "- Authority promotion: NO",
            "",
            "## Coverage context",
            "",
            f"- Repository data JSON files in coverage manifest: {coverage['data_json_files_scanned']}",
            f"- Coverage parse errors: {coverage['parse_errors']}",
            f"- Unconfigured name-like occurrences retained as gaps: {coverage['unknown_name_like_field_occurrences']}",
            "",
            "## QA",
            "",
            f"- Base Batch 1/2 validator: {'PASS' if not base['validation_errors'] else 'FAIL'}",
            f"- Candidate validator: {'PASS' if not artifacts['validation_errors'] else 'FAIL'}",
            f"- Benchmark operation: {benchmark['operation']}",
            f"- Benchmark skipped: {benchmark.get('skipped', False)}",
            f"- Benchmark repetitions: {benchmark.get('repetitions', 0)}",
            f"- Benchmark elapsed seconds: {benchmark.get('elapsed_seconds', 0)}",
            "",
            "## Authority and delivery",
            "",
            "- Authoritative IDs changed: NO",
            "- Production catalogs rewritten: NO",
            f"- Checkpoint: {commit}",
            f"- Push: {push}",
            "- Draft PR: none",
            "- No merge performed by this task.",
            "",
        ]
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--output-root",
        type=Path,
        default=None,
        help="staging output directory (default: data/staging/world_names)",
    )
    parser.add_argument("--starting-master", default="unknown")
    parser.add_argument("--commit", default="pending-batch-3-checkpoint")
    parser.add_argument("--push", default="BLOCKED: network unavailable")
    parser.add_argument("--benchmark-repetitions", type=int, default=3)
    parser.add_argument(
        "--report-path",
        default="docs/world_names/BATCH_3_REPORT.md",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    root = args.root.resolve()
    output_root = (args.output_root or root / "data/staging/world_names").resolve()
    artifacts = build_review_artifacts(root, args.benchmark_repetitions)
    if artifacts["validation_errors"]:
        for error in artifacts["validation_errors"]:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    _write_json(output_root / "review_candidates.json", artifacts["review_candidates"])
    _write_json(output_root / "candidate_collision_ledger.json", artifacts["collision_ledger"])
    _write_json(output_root / "performance_benchmark.json", artifacts["performance_benchmark"])
    report_path = (root / args.report_path).resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        render_report(
            artifacts,
            args.starting_master,
            args.commit,
            args.push,
        ),
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "candidates": artifacts["review_candidates"]["summary"]["candidate_count"],
                "candidate_collisions": artifacts["collision_ledger"]["summary"][
                    "candidate_collision_groups"
                ],
                "benchmark_seconds": artifacts["performance_benchmark"].get(
                    "elapsed_seconds", 0
                ),
                "validator": "PASS",
                "output_root": (
                    output_root.relative_to(root).as_posix()
                    if output_root.is_relative_to(root)
                    else output_root.as_posix()
                ),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())