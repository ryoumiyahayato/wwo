#!/usr/bin/env python3
"""Validate committed world-name staging artifacts and replay their sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
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
)
OBSERVATIONAL_ARTIFACTS: tuple[str, ...] = ("performance_benchmark.json",)
MANIFEST_FILENAME = "artifact_manifest.json"
RECORD_COUNT_KEYS: dict[str, str] = {
    "aliases.json": "aliases",
    "collision_report.json": "normalized_collisions",
    "name_inventory.json": "entities",
    "search_index.json": "entries",
    "coverage_manifest.json": "files",
    "remaining_gaps.json": "source_files",
    "deterministic_corpus.json": "source_hashes",
    "review_candidates.json": "candidates",
    "candidate_collision_ledger.json": "collisions",
}


def _canonical_json(document: Any) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + chr(10)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _source_sha256(path: Path) -> str:
    return wn._canonical_source_sha256(path)


def _read_json(path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    if not path.exists():
        return None, [f"missing artifact: {path.as_posix()}"]
    try:
        raw_bytes = path.read_bytes()
        raw = raw_bytes.decode("utf-8")
        document = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, [f"could not read JSON artifact {path.as_posix()}: {error}"]
    if not isinstance(document, dict):
        return None, [f"artifact is not a JSON object: {path.as_posix()}"]
    if raw != _canonical_json(document):
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


def _validate_artifact_set(root: Path) -> list[str]:
    artifact_root = root / "data/staging/world_names"
    allowed = {filename for filename, _role in ARTIFACT_SPECS}
    allowed.update(OBSERVATIONAL_ARTIFACTS)
    allowed.add(MANIFEST_FILENAME)
    errors: list[str] = []
    if not artifact_root.is_dir():
        return [f"missing staging artifact directory: {artifact_root.as_posix()}"]
    actual = {path.name for path in artifact_root.glob("*.json")}
    unexpected = sorted(actual - allowed)
    if unexpected:
        errors.append(f"unexpected staged artifacts: {unexpected}")
    return errors


def _validate_benchmark(document: dict[str, Any], base: dict[str, Any]) -> list[str]:
    """Validate optional local timing output without treating it as deterministic."""

    errors: list[str] = []
    required = {
        "schema_version",
        "operation",
        "artifact_class",
        "deterministic",
        "tracked",
        "skipped",
    }
    if set(document) < required:
        errors.append("performance benchmark schema is incomplete")
    if document.get("schema_version") != wn.SCHEMA_VERSION:
        errors.append("performance benchmark schema_version mismatch")
    if document.get("operation") != "world_names.build_artifacts":
        errors.append("performance benchmark operation mismatch")
    if document.get("artifact_class") != "NON_DETERMINISTIC_OBSERVATIONAL":
        errors.append("performance benchmark is not marked observational")
    if document.get("deterministic") is not False:
        errors.append("performance benchmark incorrectly claims determinism")
    if document.get("tracked") is not False:
        errors.append("performance benchmark incorrectly claims tracked status")
    skipped = document.get("skipped")
    if not isinstance(skipped, bool):
        errors.append("performance benchmark skipped flag is invalid")
    if skipped is False:
        repetitions = document.get("repetitions")
        elapsed = document.get("elapsed_seconds")
        minimum = document.get("min_seconds")
        maximum = document.get("max_seconds")
        if not isinstance(repetitions, int) or isinstance(repetitions, bool) or repetitions <= 0:
            errors.append("performance benchmark repetitions are invalid")
        values = (elapsed, minimum, maximum)
        if not all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0 for value in values):
            errors.append("performance benchmark timing values are invalid")
        elif not (minimum <= maximum <= elapsed):
            errors.append("performance benchmark timing bounds are invalid")
        for field in ("python", "platform"):
            if not isinstance(document.get(field), str) or not document[field]:
                errors.append(f"performance benchmark {field} is invalid")
        expected_counts = {
            "entities": len(base["inventory"]["entities"]),
            "aliases": len(base["aliases"]["aliases"]),
            "coverage_files": len(base["coverage_manifest"]["files"]),
        }
        if document.get("artifact_counts") != expected_counts:
            errors.append("performance benchmark artifact counts mismatch")
    return errors


def _source_fingerprint(coverage: dict[str, Any]) -> str:
    inputs = [
        {
            "source_file": row.get("source_file"),
            "sha256": row.get("sha256"),
            "status": row.get("status"),
        }
        for row in coverage.get("files", [])
        if isinstance(row, dict)
    ]
    inputs.sort(key=lambda item: str(item["source_file"]))
    return hashlib.sha256(_canonical_json(inputs).encode("utf-8")).hexdigest()


def _record_count(filename: str, document: dict[str, Any]) -> int:
    key = RECORD_COUNT_KEYS[filename]
    value = document.get(key)
    if not isinstance(value, list):
        raise ValueError(f"{filename} record field {key} is not a list")
    return len(value)


def _manifest_files(root: Path) -> list[dict[str, Any]]:
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
                "record_count": _record_count(filename, document),
            }
        )
    files.sort(key=lambda item: item["path"])
    return files


def build_artifact_manifest(
    root: Path,
    validation_errors: Sequence[str],
) -> dict[str, Any]:
    artifact_root = root / "data/staging/world_names"
    files = _manifest_files(root)
    inventory = json.loads((artifact_root / "name_inventory.json").read_text(encoding="utf-8"))
    coverage = json.loads((artifact_root / "coverage_manifest.json").read_text(encoding="utf-8"))
    candidates = json.loads((artifact_root / "review_candidates.json").read_text(encoding="utf-8"))
    return {
        "schema_version": wn.SCHEMA_VERSION,
        "manifest_kind": "world_names_staging",
        "generator": {
            "name": "tools.world_names.world_names",
            "schema_version": wn.SCHEMA_VERSION,
        },
        "source_fingerprint": _source_fingerprint(coverage),
        "policy": {
            "authoritative_production_data_rewritten": False,
            "manifest_excludes_itself": True,
            "no_unsourced_translation": True,
            "observational_benchmark_excluded": True,
            "staging_is_non_authoritative": True,
        },
        "summary": {
            "artifact_file_count": len(files),
            "coverage_source_file_count": len(coverage["files"]),
            "entity_count": len(inventory["entities"]),
            "review_candidate_count": len(candidates["candidates"]),
            "record_counts": {
                item["path"].rsplit("/", 1)[-1]: item["record_count"]
                for item in files
            },
        },
        "validation": {
            "status": "PASS" if not validation_errors else "FAIL",
            "errors": list(validation_errors),
        },
        "files": files,
    }


def validate_artifact_manifest(root: Path, manifest: Any) -> list[str]:
    """Validate manifest shape and hashes independently of source regeneration."""

    errors = _validate_artifact_set(root)
    if not isinstance(manifest, dict):
        return errors + ["artifact manifest is not an object"]
    expected_keys = {
        "schema_version",
        "manifest_kind",
        "generator",
        "source_fingerprint",
        "policy",
        "summary",
        "validation",
        "files",
    }
    if set(manifest) != expected_keys:
        errors.append("artifact manifest has an invalid schema")
    if manifest.get("schema_version") != wn.SCHEMA_VERSION:
        errors.append("artifact manifest schema_version mismatch")
    if manifest.get("manifest_kind") != "world_names_staging":
        errors.append("artifact manifest kind mismatch")
    if not isinstance(manifest.get("source_fingerprint"), str) or len(manifest["source_fingerprint"]) != 64:
        errors.append("artifact manifest source_fingerprint is malformed")
    if not isinstance(manifest.get("files"), list):
        return errors + ["artifact manifest files are not a list"]
    manifest_paths = [
        item.get("path") for item in manifest["files"] if isinstance(item, dict)
    ]
    expected_paths = [
        f"data/staging/world_names/{filename}" for filename, _role in ARTIFACT_SPECS
    ]
    if manifest_paths != sorted(expected_paths):
        errors.append("artifact manifest file set is incomplete or unordered")
    try:
        expected_manifest = build_artifact_manifest(root, [])
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        return errors + [f"artifact manifest cannot be replayed: {error}"]
    if manifest != expected_manifest:
        errors.append("artifact manifest hashes/counts/provenance do not replay")
    return errors


def _replay_core_artifacts(
    root: Path,
    tracked: dict[str, dict[str, Any]],
) -> list[str]:
    try:
        fresh = wn.build_artifacts(root)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        return [f"core artifact regeneration failed: {error}"]
    errors = [f"fresh core generation: {error}" for error in fresh.get("validation_errors", [])]
    mapping = {
        "aliases.json": "aliases",
        "collision_report.json": "collision_report",
        "name_inventory.json": "inventory",
        "search_index.json": "search_index",
        "coverage_manifest.json": "coverage_manifest",
        "remaining_gaps.json": "remaining_gaps",
        "deterministic_corpus.json": "deterministic_corpus",
    }
    for filename, key in mapping.items():
        if filename in tracked and _canonical_json(tracked[filename]) != _canonical_json(fresh[key]):
            errors.append(f"tracked {filename} does not match fresh official generation")
    return errors


def validate_staged(root: Path) -> list[str]:
    errors = _validate_artifact_set(root)
    documents, read_errors = _artifact_documents(root)
    errors.extend(read_errors)
    required = {filename for filename, _role in ARTIFACT_SPECS}
    if set(documents) != required:
        errors.append("staged artifact set is incomplete")
        if not (root / "data/staging/world_names" / MANIFEST_FILENAME).is_file():
            errors.append("required artifact manifest is missing")
        return errors

    base = {
        key: documents[key]
        for key in ("name_inventory.json", "aliases.json", "collision_report.json", "search_index.json")
    }
    coverage = documents["coverage_manifest.json"]
    gaps = documents["remaining_gaps.json"]
    corpus = documents["deterministic_corpus.json"]
    candidates = documents["review_candidates.json"]
    ledger = documents["candidate_collision_ledger.json"]
    errors.extend(
        wn.validate_artifacts(
            base["name_inventory.json"],
            base["aliases.json"],
            base["collision_report.json"],
            base["search_index.json"],
            root=root,
            coverage_manifest=coverage,
        )
    )
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
    errors.extend(rc.validate_review_candidates(candidates, ledger, coverage, root=root))
    errors.extend(rc.replay_review_candidates(root, candidates, coverage))
    if ledger != rc.build_candidate_collision_ledger(candidates["candidates"]):
        errors.append("candidate collision ledger replay mismatch")
    benchmark_path = root / "data/staging/world_names/performance_benchmark.json"
    if benchmark_path.exists():
        benchmark, benchmark_errors = _read_json(benchmark_path)
        errors.extend(benchmark_errors)
        if benchmark is not None:
            errors.extend(_validate_benchmark(benchmark, {
                "inventory": base["name_inventory.json"],
                "aliases": base["aliases.json"],
                "coverage_manifest": coverage,
            }))

    for row in coverage.get("files", []):
        source_file = row.get("source_file")
        if not wn._is_repo_relative_path(source_file):
            errors.append(f"coverage source path is not repo-relative: {source_file!r}")
            continue
        source_path = root / source_file
        if not source_path.exists():
            errors.append(f"coverage source file is missing: {source_file}")
        elif _source_sha256(source_path) != row.get("sha256"):
            errors.append(f"coverage source hash mismatch: {source_file}")

    errors.extend(_replay_core_artifacts(root, documents))
    manifest_path = root / "data/staging/world_names" / MANIFEST_FILENAME
    if not manifest_path.is_file():
        errors.append("required artifact manifest is missing")
    else:
        manifest, manifest_errors = _read_json(manifest_path)
        errors.extend(manifest_errors)
        if manifest is not None:
            errors.extend(validate_artifact_manifest(root, manifest))
    return errors


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
    with manifest_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(_canonical_json(manifest))
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
                "source_fingerprint": manifest["source_fingerprint"],
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
