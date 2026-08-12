#!/usr/bin/env python3
"""Validate committed world-name staging artifacts without rebuilding them."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Sequence

from . import review_candidates as rc
from . import world_names as wn


ARTIFACT_SPECS: tuple[tuple[str, str], ...] = (
    ("aliases.json", "alias staging"),
    ("collision_report.json", "collision report"),
    ("name_inventory.json", "entity inventory"),
    ("search_index.json", "stable-id search index"),
    ("coverage_manifest.json", "repository coverage manifest"),
    ("remaining_gaps.json", "remaining-gap ledger"),
    ("deterministic_corpus.json", "deterministic regression corpus"),
    ("review_candidates.json", "non-authoritative review candidates"),
    ("candidate_collision_ledger.json", "review-candidate collision ledger"),
    ("performance_benchmark.json", "performance benchmark"),
)


def _canonical_json(document: Any) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + chr(10)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_json(path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    if not path.exists():
        return None, [f"missing artifact: {path.as_posix()}"]
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, [f"could not read JSON artifact {path.as_posix()}: {error}"]
    if not isinstance(document, dict):
        return None, [f"artifact is not a JSON object: {path.as_posix()}"]
    if path.read_text(encoding="utf-8") != _canonical_json(document):
        errors.append(f"artifact is not canonical JSON: {path.as_posix()}")
    return document, errors


def _artifact_documents(root: Path) -> tuple[dict[str, dict[str, Any]], list[str]]:
    artifact_root = root / "data/staging/world_names"
    documents: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for filename, _role in ARTIFACT_SPECS:
        document, read_errors = _read_json(artifact_root / filename)
        errors.extend(read_errors)
        if document is not None:
            documents[filename] = document
    return documents, errors


def _validate_benchmark(document: dict[str, Any], base: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if document.get("schema_version") != wn.SCHEMA_VERSION:
        errors.append("performance benchmark schema_version mismatch")
    if document.get("operation") != "world_names.build_artifacts":
        errors.append("performance benchmark operation mismatch")
    if document.get("skipped") is False:
        repetitions = document.get("repetitions")
        elapsed = document.get("elapsed_seconds")
        minimum = document.get("min_seconds")
        maximum = document.get("max_seconds")
        if not isinstance(repetitions, int) or repetitions <= 0:
            errors.append("performance benchmark repetitions are invalid")
        if not all(isinstance(value, (int, float)) and value >= 0 for value in (elapsed, minimum, maximum)):
            errors.append("performance benchmark timing values are invalid")
        elif not (minimum <= maximum and maximum <= elapsed):
            errors.append("performance benchmark timing bounds are invalid")
    expected_counts = {
        "entities": len(base["inventory"]["entities"]),
        "aliases": len(base["aliases"]["aliases"]),
        "coverage_files": len(base["coverage_manifest"]["files"]),
    }
    if document.get("artifact_counts") != expected_counts:
        errors.append("performance benchmark artifact counts mismatch")
    return errors


def validate_staged(root: Path) -> list[str]:
    documents, errors = _artifact_documents(root)
    required = {filename for filename, _role in ARTIFACT_SPECS}
    if set(documents) != required:
        return errors + ["staged artifact set is incomplete"]

    base = {
        key: documents[key]
        for key in ("name_inventory.json", "aliases.json", "collision_report.json", "search_index.json")
    }
    base_errors = wn.validate_artifacts(
        base["name_inventory.json"],
        base["aliases.json"],
        base["collision_report.json"],
        base["search_index.json"],
    )
    errors.extend(base_errors)
    coverage = documents["coverage_manifest.json"]
    gaps = documents["remaining_gaps.json"]
    corpus = documents["deterministic_corpus.json"]
    candidates = documents["review_candidates.json"]
    ledger = documents["candidate_collision_ledger.json"]
    errors.extend(wn.validate_coverage_manifest(coverage))
    errors.extend(wn.validate_remaining_gaps(gaps, coverage))
    errors.extend(
        wn.validate_deterministic_corpus(
            corpus,
            base["name_inventory.json"],
            base["aliases.json"],
            base["collision_report.json"],
            base["search_index.json"],
            coverage,
        )
    )
    errors.extend(rc.validate_review_candidates(candidates, ledger, coverage))
    if ledger != rc.build_candidate_collision_ledger(candidates["candidates"]):
        errors.append("candidate collision ledger replay mismatch")
    errors.extend(_validate_benchmark(documents["performance_benchmark.json"], {
        "inventory": base["name_inventory.json"],
        "aliases": base["aliases.json"],
        "coverage_manifest": coverage,
    }))

    for row in coverage.get("files", []):
        source_path = root / row["source_file"]
        if not source_path.exists():
            errors.append(f"coverage source file is missing: {row['source_file']}")
        elif _sha256(source_path) != row.get("sha256"):
            errors.append(f"coverage source hash mismatch: {row['source_file']}")

    manifest_path = root / "data/staging/world_names/artifact_manifest.json"
    if manifest_path.exists():
        manifest, manifest_errors = _read_json(manifest_path)
        errors.extend(manifest_errors)
        if manifest is not None:
            expected_manifest = build_artifact_manifest(root, [])
            if manifest != expected_manifest:
                errors.append("artifact manifest does not replay from staged files")
    return errors


def build_artifact_manifest(
    root: Path,
    validation_errors: Sequence[str],
) -> dict[str, Any]:
    artifact_root = root / "data/staging/world_names"
    files: list[dict[str, Any]] = []
    for filename, role in ARTIFACT_SPECS:
        path = artifact_root / filename
        document = json.loads(path.read_text(encoding="utf-8"))
        files.append(
            {
                "path": f"data/staging/world_names/{filename}",
                "role": role,
                "bytes": path.stat().st_size,
                "sha256": _sha256(path),
                "schema_version": document.get("schema_version"),
            }
        )
    files.sort(key=lambda item: item["path"])
    inventory = json.loads((artifact_root / "name_inventory.json").read_text(encoding="utf-8"))
    coverage = json.loads((artifact_root / "coverage_manifest.json").read_text(encoding="utf-8"))
    candidates = json.loads((artifact_root / "review_candidates.json").read_text(encoding="utf-8"))
    return {
        "schema_version": wn.SCHEMA_VERSION,
        "manifest_kind": "world_names_staging",
        "policy": {
            "authoritative_production_data_rewritten": False,
            "manifest_excludes_itself": True,
            "no_unsourced_translation": True,
        },
        "summary": {
            "artifact_file_count": len(files),
            "coverage_source_file_count": len(coverage["files"]),
            "entity_count": len(inventory["entities"]),
            "review_candidate_count": len(candidates["candidates"]),
        },
        "validation": {
            "status": "PASS" if not validation_errors else "FAIL",
            "errors": list(validation_errors),
        },
        "files": files,
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--manifest-path",
        default="data/staging/world_names/artifact_manifest.json",
    )
    args = parser.parse_args(argv or sys.argv[1:])
    root = args.root.resolve()
    errors = validate_staged(root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    manifest_path = (root / args.manifest_path).resolve()
    manifest = build_artifact_manifest(root, [])
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(_canonical_json(manifest), encoding="utf-8")
    final_errors = validate_staged(root)
    if final_errors:
        for error in final_errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        json.dumps(
            {
                "artifact_files": manifest["summary"]["artifact_file_count"],
                "coverage_source_files": manifest["summary"]["coverage_source_file_count"],
                "review_candidates": manifest["summary"]["review_candidate_count"],
                "validator": "PASS",
                "manifest": manifest_path.relative_to(root).as_posix()
                if manifest_path.is_relative_to(root)
                else manifest_path.as_posix(),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())