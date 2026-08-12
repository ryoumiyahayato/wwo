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
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(_canonical_json(document))


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


CANDIDATE_DOCUMENT_FIELDS = frozenset({
    "schema_version",
    "normalizer_id",
    "policy",
    "summary",
    "candidates",
})
CANDIDATE_POLICY = {
    "stable_ids_are_authoritative": True,
    "source_record_keys_are_non_authoritative": True,
    "no_unsourced_translation": True,
    "modern_reference_sources_excluded": True,
}
CANDIDATE_FIELDS = frozenset({
    "candidate_id",
    "entity_id",
    "entity_id_kind",
    "entity_type",
    "alias",
    "normalized_name",
    "language",
    "script",
    "alias_type",
    "valid_from",
    "valid_to",
    "source",
    "source_file",
    "source_field",
    "source_sha256",
    "source_status",
    "authority",
    "review_reason",
})
CANDIDATE_AUTHORITY = "non_authoritative"
CANDIDATE_ENTITY_KIND = "source_record_key"
CANDIDATE_ENTITY_TYPE = "review_name_candidate"
CANDIDATE_REVIEW_REASON = "direct repository evidence only; semantic authority is not asserted"


def _is_nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and value == value.lower()
        and all(character in "0123456789abcdef" for character in value)
    )


def _validate_candidate_dates(item: dict[str, Any], candidate_id: str) -> list[str]:
    errors: list[str] = []
    for field in ("valid_from", "valid_to"):
        value = item.get(field)
        if value is not None and (not isinstance(value, str) or wn._parse_date(value) is None):
            errors.append(f"candidate {candidate_id} has invalid {field}")
    valid_from = wn._parse_date(item.get("valid_from"))
    valid_to = wn._parse_date(item.get("valid_to"))
    if valid_from is not None and valid_to is not None and valid_from > valid_to:
        errors.append(f"candidate {candidate_id} has an inverted date range")
    return errors


def validate_candidate_collision_ledger(
    collision_ledger: dict[str, Any],
    candidates: Sequence[dict[str, Any]],
) -> list[str]:
    errors: list[str] = []
    expected_top = {"schema_version", "normalizer_id", "policy", "summary", "collisions"}
    if not isinstance(collision_ledger, dict) or set(collision_ledger) != expected_top:
        return ["candidate collision ledger has an invalid schema"]
    if collision_ledger.get("schema_version") != SCHEMA_VERSION:
        errors.append("candidate collision ledger schema_version mismatch")
    if collision_ledger.get("normalizer_id") != wn.NORMALIZER_ID:
        errors.append("candidate collision ledger normalizer_id mismatch")
    expected_policy = {
        "one_to_many_mappings_are_preserved": True,
        "candidate_ids_are_not_authoritative": True,
        "no_historical_contradiction_is_inferred": True,
    }
    if collision_ledger.get("policy") != expected_policy:
        errors.append("candidate collision ledger policy mismatch")
    collisions = collision_ledger.get("collisions")
    if not isinstance(collisions, list):
        return errors + ["candidate collision ledger collisions are not a list"]
    candidate_ids = {
        item.get("candidate_id")
        for item in candidates
        if isinstance(item.get("candidate_id"), str)
    }
    seen_names: set[str] = set()
    normalized_order = [
        collision.get("normalized_name")
        for collision in collisions
        if isinstance(collision, dict)
    ]
    if normalized_order != sorted(normalized_order, key=lambda value: "" if value is None else str(value)):
        errors.append("candidate collision ledger is not deterministically ordered")
    for index, collision in enumerate(collisions):
        if not isinstance(collision, dict) or set(collision) != {
            "normalized_name", "candidate_ids", "raw_names", "source_files", "collision_kind", "authority"
        }:
            errors.append(f"candidate collision {index} has an invalid schema")
            continue
        normalized = collision.get("normalized_name")
        members = collision.get("candidate_ids")
        raw_names = collision.get("raw_names")
        source_files = collision.get("source_files")
        if not _is_nonempty_string(normalized):
            errors.append(f"candidate collision {index} has an invalid normalized_name")
        if normalized in seen_names:
            errors.append(f"duplicate candidate collision normalized_name: {normalized}")
        seen_names.add(normalized)
        if (
            not isinstance(members, list)
            or any(not isinstance(member, str) for member in members)
            or members != sorted(set(members))
            or len(members) < 2
        ):
            errors.append(f"candidate collision {index} has invalid candidate_ids")
        elif any(member not in candidate_ids for member in members):
            errors.append(f"candidate collision {index} references an unknown member")
        if not isinstance(raw_names, list) or any(not _is_nonempty_string(value) for value in raw_names):
            errors.append(f"candidate collision {index} has invalid raw_names")
        if not isinstance(source_files, list) or any(not _is_nonempty_string(value) for value in source_files):
            errors.append(f"candidate collision {index} has invalid source_files")
        if collision.get("collision_kind") != "review_candidate_normalized_collision":
            errors.append(f"candidate collision {index} kind mismatch")
        if collision.get("authority") != CANDIDATE_AUTHORITY:
            errors.append(f"candidate collision {index} asserts authority")
    summary = collision_ledger.get("summary")
    if not isinstance(summary, dict) or set(summary) != {
        "candidate_collision_groups", "candidate_ids_in_collision_groups"
    }:
        errors.append("candidate collision ledger summary has an invalid schema")
    else:
        if summary.get("candidate_collision_groups") != len(collisions):
            errors.append("candidate collision ledger group count mismatch")
        if summary.get("candidate_ids_in_collision_groups") != len({
            member for collision in collisions if isinstance(collision, dict)
            for member in collision.get("candidate_ids", [])
        }):
            errors.append("candidate collision ledger member count mismatch")
    return errors


def replay_review_candidates(
    root: Path,
    tracked_document: dict[str, Any],
    coverage: dict[str, Any],
) -> list[str]:
    """Rescan source inputs, regenerate candidates, and compare canonical output."""

    try:
        fresh_coverage = wn.scan_repository_name_coverage(root)
        fresh_document = build_review_candidates(root, fresh_coverage)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        return [f"candidate regeneration failed: {error}"]
    if _canonical_json(fresh_document) != _canonical_json(tracked_document):
        return ["tracked review candidates do not match fresh official generation"]
    return []


def validate_review_candidates(
    candidate_document: dict[str, Any],
    collision_ledger: dict[str, Any],
    coverage: dict[str, Any],
    *,
    root: Path | None = None,
) -> list[str]:
    errors: list[str] = []
    if root is None:
        errors.append("review candidates require repository root for source evidence replay")
    if not isinstance(candidate_document, dict) or set(candidate_document) != CANDIDATE_DOCUMENT_FIELDS:
        errors.append("review candidates document has an invalid schema")
    if not isinstance(candidate_document, dict):
        return errors
    if candidate_document.get("schema_version") != SCHEMA_VERSION:
        errors.append("review candidates schema_version mismatch")
    if candidate_document.get("normalizer_id") != wn.NORMALIZER_ID:
        errors.append("review candidates normalizer_id mismatch")
    if candidate_document.get("policy") != CANDIDATE_POLICY:
        errors.append("review candidates policy mismatch")
    candidates = candidate_document.get("candidates")
    if not isinstance(candidates, list):
        return errors + ["review candidates are not a list"]
    candidate_ids = [item.get("candidate_id") if isinstance(item, dict) else None for item in candidates]
    if candidate_ids != sorted(candidate_ids, key=lambda value: "" if not isinstance(value, str) else value):
        errors.append("review candidates are not sorted")
    comparable_ids = [value for value in candidate_ids if isinstance(value, str)]
    if len(comparable_ids) != len(set(comparable_ids)):
        errors.append("review candidates contain duplicate candidate_id values")
    coverage_by_file = {
        row.get("source_file"): row
        for row in coverage.get("files", [])
        if isinstance(row, dict)
    }
    source_cache: dict[str, Any] = {}
    source_hash_cache: dict[str, str] = {}
    for index, item in enumerate(candidates):
        if not isinstance(item, dict):
            errors.append(f"candidate {index} is not an object")
            continue
        candidate_id = item.get("candidate_id")
        label = candidate_id if isinstance(candidate_id, str) else str(index)
        if set(item) != CANDIDATE_FIELDS:
            errors.append(f"candidate {label} has an invalid schema")
        string_fields = (
            "candidate_id", "entity_id", "entity_id_kind", "entity_type", "alias",
            "normalized_name", "language", "script", "alias_type", "source",
            "source_file", "source_field", "source_status", "authority", "review_reason",
        )
        for field in string_fields:
            if not _is_nonempty_string(item.get(field)):
                errors.append(f"candidate {label} field {field} must be a non-empty string")
        errors.extend(_validate_candidate_dates(item, label))
        if not _is_sha256(item.get("source_sha256")):
            errors.append(f"candidate {label} source_sha256 is malformed")
        if item.get("entity_id_kind") != CANDIDATE_ENTITY_KIND:
            errors.append(f"candidate is not source-record keyed: {label}")
        if item.get("entity_type") != CANDIDATE_ENTITY_TYPE:
            errors.append(f"candidate entity_type mismatch: {label}")
        if item.get("authority") != CANDIDATE_AUTHORITY:
            errors.append(f"candidate asserts authority: {label}")
        if item.get("review_reason") != CANDIDATE_REVIEW_REASON:
            errors.append(f"candidate review boundary mismatch: {label}")
        if item.get("normalized_name") != wn.normalize_name(item.get("alias", "")):
            errors.append(f"candidate normalizer mismatch: {label}")
        if item.get("language") not in {"und", "zh"}:
            errors.append(f"candidate language is not an allowed value: {label}")
        if item.get("script") not in {"Arab", "Cyrl", "Grek", "Hans", "Jpan", "Kore", "Latn", "und"}:
            errors.append(f"candidate script is not an allowed value: {label}")
        if item.get("alias_type") not in {value[1] for value in wn.NAME_FIELD_BY_KEY.values()}:
            errors.append(f"candidate alias_type is not an allowed value: {label}")
        source_file = item.get("source_file")
        if not wn._is_repo_relative_path(source_file):
            errors.append(f"candidate {label} source_file is not repo-relative")
        row = coverage_by_file.get(source_file)
        if row is None:
            errors.append(f"candidate points to unknown source file: {source_file}")
            continue
        if not _source_is_reviewable(row):
            errors.append(f"candidate source is not reviewable: {source_file}")
        source = item.get("source")
        pointer = None
        if isinstance(source, str) and "#" in source:
            source_prefix, pointer = source.split("#", 1)
            if source_prefix != source_file:
                errors.append(f"candidate source file/reference mismatch: {label}")
        else:
            errors.append(f"candidate source reference is malformed: {label}")
        if not isinstance(candidate_id, str) or not candidate_id.startswith("source:"):
            errors.append(f"candidate ID syntax is invalid: {label}")
        elif pointer is not None and candidate_id != f"source:{source_file}#{pointer}":
            errors.append(f"candidate source pointer mismatch: {label}")
        if item.get("entity_id") != candidate_id:
            errors.append(f"candidate entity_id does not equal candidate_id: {label}")
        if item.get("source_status") not in REVIEWABLE_STATUSES:
            errors.append(f"candidate source_status is invalid: {label}")
        if item.get("source_status") != row.get("status"):
            errors.append(f"candidate source_status mismatch: {label}")
        source_field = item.get("source_field")
        if source_field not in wn.NAME_FIELD_BY_KEY:
            errors.append(f"candidate source_field is unknown: {label}")
        elif item.get("alias_type") != wn.NAME_FIELD_BY_KEY[source_field][1]:
            errors.append(f"candidate alias_type does not match source_field: {label}")
        if root is None:
            continue
        if not isinstance(source_file, str) or not wn._is_repo_relative_path(source_file):
            continue
        source_path = root / source_file
        if not source_path.is_file():
            errors.append(f"candidate source file is missing: {source_file}")
            continue
        try:
            if source_file not in source_hash_cache:
                source_hash_cache[source_file] = wn._canonical_source_sha256(source_path)
            actual_sha = source_hash_cache[source_file]
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            errors.append(f"candidate source file cannot be read: {source_file}: {error}")
            continue
        if actual_sha != row.get("sha256") or actual_sha != item.get("source_sha256"):
            errors.append(f"candidate source hash does not replay: {label}")
        if pointer is None:
            continue
        try:
            if source_file not in source_cache:
                source_cache[source_file] = json.loads(source_path.read_text(encoding="utf-8"))
            document = source_cache[source_file]
            actual, _parent, _parent_key = wn._resolve_source_pointer(document, pointer)
            record = wn._resolve_source_record(document, pointer)
            tokens = wn._source_pointer_tokens(pointer)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
            errors.append(f"candidate source pointer cannot be replayed: {label}: {error}")
            continue
        field_token = next((token for token in reversed(tokens) if isinstance(token, str)), None)
        if field_token != source_field:
            errors.append(f"candidate source_field does not match source pointer: {label}")
        if not isinstance(actual, str) or actual.strip() != item.get("alias"):
            errors.append(f"candidate source value mismatch: {label}")
        if isinstance(source_field, str) and item.get("language") != wn._language_for(source_field):
            errors.append(f"candidate language does not replay from source_field: {label}")
        if isinstance(actual, str) and item.get("script") != wn._script_for(actual):
            errors.append(f"candidate script does not replay from source value: {label}")
        if not isinstance(record, dict):
            errors.append(f"candidate source record is not an object: {label}")
        else:
            expected_from = wn._valid_date_value(record, "valid_from")
            expected_to = wn._valid_date_value(record, "valid_to")
            if item.get("valid_from") != expected_from or item.get("valid_to") != expected_to:
                errors.append(f"candidate date evidence mismatch: {label}")

    expected_summary = {
        "candidate_count": len(candidates),
        "source_file_count": len({
            item.get("source_file")
            for item in candidates
            if isinstance(item, dict) and isinstance(item.get("source_file"), str)
        }),
        "world_map_scanned_only_candidates": sum(
            1 for item in candidates if isinstance(item, dict) and item.get("source_status") == "world_map_scanned_only"
        ),
        "non_world_map_scanned_only_candidates": sum(
            1 for item in candidates if isinstance(item, dict) and item.get("source_status") == "non_world_map_scanned_only"
        ),
        "normalized_name_count": len({
            item.get("normalized_name") for item in candidates
            if isinstance(item, dict) and item.get("normalized_name")
        }),
    }
    if candidate_document.get("summary") != expected_summary:
        errors.append("review candidates summary does not replay")
    valid_candidate_items = [
        item for item in candidates
        if isinstance(item, dict)
        and isinstance(item.get("normalized_name"), str)
        and isinstance(item.get("candidate_id"), str)
        and isinstance(item.get("alias"), str)
        and isinstance(item.get("source_file"), str)
    ]
    errors.extend(validate_candidate_collision_ledger(collision_ledger, valid_candidate_items))
    try:
        expected_ledger = build_candidate_collision_ledger(valid_candidate_items)
    except (KeyError, TypeError, ValueError) as error:
        errors.append(f"candidate collision ledger replay failed: {error}")
    else:
        if collision_ledger != expected_ledger:
            errors.append("candidate collision ledger does not replay deterministically")
    return errors


def benchmark_build(root: Path, repetitions: int) -> dict[str, Any]:
    if repetitions <= 0:
        return {
            "schema_version": SCHEMA_VERSION,
            "operation": "world_names.build_artifacts",
            "artifact_class": "NON_DETERMINISTIC_OBSERVATIONAL",
            "deterministic": False,
            "tracked": False,
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
        "artifact_class": "NON_DETERMINISTIC_OBSERVATIONAL",
        "deterministic": False,
        "tracked": False,
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
    errors.extend(validate_review_candidates(candidates, ledger, base["coverage_manifest"], root=root))
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
            "- Benchmark: NON_DETERMINISTIC_OBSERVATIONAL (local-only; not tracked)",
            "- Wall-clock timing is excluded from deterministic semantic artifacts and manifest hashes",
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
    with report_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            render_report(
                artifacts,
                args.starting_master,
                args.commit,
                args.push,
            )
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