#!/usr/bin/env python3
"""Validate the Batch 2 repository producer/consumer reference matrix."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import scan_reference_matrix


BROKEN_REFERENCE = scan_reference_matrix.BROKEN_REFERENCE
CANDIDATE_NOT_CANONICAL = scan_reference_matrix.CANDIDATE_NOT_CANONICAL
INTENTIONAL_TEST_FIXTURE = scan_reference_matrix.INTENTIONAL_TEST_FIXTURE
LICENSE_UNKNOWN = scan_reference_matrix.LICENSE_UNKNOWN
OUTPUT_MISSING = scan_reference_matrix.OUTPUT_MISSING
SOURCE_MISSING = scan_reference_matrix.SOURCE_MISSING
TARGET_NOT_IN_BATCH_1 = scan_reference_matrix.TARGET_NOT_IN_BATCH_1
MATRIX_KIND = scan_reference_matrix.MATRIX_KIND
MANIFEST_RELATIVE = scan_reference_matrix.MANIFEST_RELATIVE
SCOPE_ROOTS = scan_reference_matrix.SCOPE_ROOTS
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
KNOWN_REFERENCE_ISSUES = {
    BROKEN_REFERENCE,
    CANDIDATE_NOT_CANONICAL,
    INTENTIONAL_TEST_FIXTURE,
    LICENSE_UNKNOWN,
    OUTPUT_MISSING,
    SOURCE_MISSING,
    TARGET_NOT_IN_BATCH_1,
    scan_reference_matrix.PROVENANCE_INCOMPLETE,
}
REQUIRED_FILE_FIELDS = {
    "path",
    "file_type",
    "size_bytes",
    "sha256",
    "role",
    "reference_count",
    "write_site_count",
    "issues",
}
REQUIRED_REFERENCE_FIELDS = {
    "id",
    "owner",
    "target",
    "reference_kind",
    "literal",
    "line",
    "column",
    "context",
    "reference_scope",
    "exists",
    "target_type",
    "target_sha256",
    "target_manifest_kind",
    "target_license",
    "issues",
    "evidence",
}


def add_finding(
    findings: list[dict[str, str]],
    severity: str,
    code: str,
    path: str,
    message: str,
) -> None:
    findings.append({"severity": severity, "code": code, "path": path, "message": message})


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_matrix(matrix: dict[str, Any], root: Path) -> dict[str, Any]:
    findings: list[dict[str, str]] = []
    if matrix.get("schema_version") != 1:
        add_finding(findings, "ERROR", "MATRIX_SCHEMA", "", "schema_version must be 1")
    if matrix.get("matrix_kind") != MATRIX_KIND:
        add_finding(findings, "ERROR", "MATRIX_SCHEMA", "", "matrix_kind is not recognized")
    if matrix.get("audit_batch") != "BATCH_2":
        add_finding(findings, "ERROR", "MATRIX_SCHEMA", "", "audit_batch must be BATCH_2")
    scope = matrix.get("scope")
    if not isinstance(scope, dict) or scope.get("tracked_files_only") is not True:
        add_finding(findings, "ERROR", "MATRIX_SCHEMA", "scope", "matrix must declare tracked_files_only=true")

    files = matrix.get("files")
    references = matrix.get("references")
    candidate_edges = matrix.get("candidate_edges")
    unresolved = matrix.get("unresolved")
    duplicate_groups = matrix.get("duplicate_hash_groups")
    if not isinstance(files, list):
        add_finding(findings, "ERROR", "MATRIX_SYNTAX", "files", "files must be a list")
        files = []
    if not isinstance(references, list):
        add_finding(findings, "ERROR", "MATRIX_SYNTAX", "references", "references must be a list")
        references = []
    if not isinstance(candidate_edges, list):
        add_finding(findings, "ERROR", "MATRIX_SYNTAX", "candidate_edges", "candidate_edges must be a list")
        candidate_edges = []
    if not isinstance(unresolved, list):
        add_finding(findings, "ERROR", "MATRIX_SYNTAX", "unresolved", "unresolved must be a list")
        unresolved = []
    if not isinstance(duplicate_groups, list):
        add_finding(findings, "ERROR", "MATRIX_SYNTAX", "duplicate_hash_groups", "duplicate_hash_groups must be a list")
        duplicate_groups = []

    file_by_path: dict[str, dict[str, Any]] = {}
    hash_groups: dict[str, list[str]] = defaultdict(list)
    for index, record in enumerate(files):
        label = f"files[{index}]"
        if not isinstance(record, dict):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "file record must be an object")
            continue
        missing = sorted(REQUIRED_FILE_FIELDS - set(record))
        if missing:
            add_finding(findings, "ERROR", "MISSING_REQUIRED_FIELD", label, f"missing fields: {', '.join(missing)}")
            continue
        relative = record["path"]
        if not isinstance(relative, str) or scan_reference_matrix.normalize_path(relative) != relative:
            add_finding(findings, "ERROR", "INVALID_PATH", label, "file path must be normalized")
            continue
        if not relative.startswith(tuple(f"{root_name}/" for root_name in SCOPE_ROOTS)):
            add_finding(findings, "ERROR", "INVALID_PATH", relative, "file is outside matrix scope")
        if relative in file_by_path:
            add_finding(findings, "ERROR", "DUPLICATE_FILE_PATH", relative, "file path is duplicated")
        file_by_path[relative] = record
        actual = root / Path(relative)
        if not actual.is_file():
            add_finding(findings, "ERROR", "MISSING_FILE", relative, "matrix file does not exist")
            continue
        if record["size_bytes"] != actual.stat().st_size:
            add_finding(findings, "ERROR", "SIZE_MISMATCH", relative, "recorded size differs from filesystem")
        recorded_hash = record["sha256"]
        if not isinstance(recorded_hash, str) or not HASH_RE.fullmatch(recorded_hash):
            add_finding(findings, "ERROR", "INVALID_HASH", relative, "sha256 must be a lowercase SHA-256")
        elif file_sha256(actual) != recorded_hash:
            add_finding(findings, "ERROR", "HASH_MISMATCH", relative, "recorded hash differs from filesystem")
        hash_groups[str(recorded_hash)].append(relative)
        if not isinstance(record["issues"], list) or not all(isinstance(item, str) for item in record["issues"]):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", relative, "file issues must be a list of strings")

    expected_duplicates = [
        sorted(paths)
        for paths in hash_groups.values()
        if len(paths) > 1 and not all(Path(path).name == ".gitkeep" for path in paths)
    ]
    expected_duplicates.sort(key=lambda paths: (paths[0], len(paths)))
    if duplicate_groups != expected_duplicates:
        add_finding(findings, "ERROR", "DUPLICATE_GROUP_MISMATCH", "duplicate_hash_groups", "duplicate groups do not match file hashes")
    if duplicate_groups:
        add_finding(findings, "WARNING", "DUPLICATE_HASH", "duplicate_hash_groups", f"{len(duplicate_groups)} duplicate hash groups recorded")

    reference_by_id: dict[str, dict[str, Any]] = {}
    actual_reference_issues: list[dict[str, Any]] = []
    for index, reference in enumerate(references):
        label = f"references[{index}]"
        if not isinstance(reference, dict):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "reference must be an object")
            continue
        missing = sorted(REQUIRED_REFERENCE_FIELDS - set(reference))
        if missing:
            add_finding(findings, "ERROR", "MISSING_REQUIRED_FIELD", label, f"missing fields: {', '.join(missing)}")
            continue
        reference_id = reference["id"]
        if not isinstance(reference_id, str) or not reference_id:
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "reference id is required")
        elif reference_id in reference_by_id:
            add_finding(findings, "ERROR", "DUPLICATE_REFERENCE_ID", reference_id, "reference id is duplicated")
        else:
            reference_by_id[reference_id] = reference
        owner = reference["owner"]
        target = reference["target"]
        if owner not in file_by_path:
            add_finding(findings, "ERROR", "BROKEN_OWNER", str(owner), "reference owner is not in files")
        if not isinstance(target, str) or scan_reference_matrix.normalize_path(target) != target:
            add_finding(findings, "ERROR", "INVALID_TARGET", str(target), "reference target must be normalized")
        issue_values = reference["issues"]
        if not isinstance(issue_values, list) or not all(isinstance(item, str) for item in issue_values):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "reference issues must be a list of strings")
            issue_values = []
        unknown_issues = sorted(set(issue_values) - KNOWN_REFERENCE_ISSUES)
        for issue in unknown_issues:
            add_finding(findings, "ERROR", "UNKNOWN_ISSUE", f"{reference_id}:{issue}", "reference issue is not recognized")
        actual = root / Path(target) if isinstance(target, str) else root
        scope_name = reference.get("reference_scope")
        if scope_name == "test_fixture_relative":
            if reference.get("exists") is not None or reference.get("target_type") != "test_fixture_relative":
                add_finding(findings, "ERROR", "CONTRADICTORY_REFERENCE", reference_id, "fixture-relative reference must use null existence")
            if INTENTIONAL_TEST_FIXTURE not in issue_values:
                add_finding(findings, "ERROR", "CONTRADICTORY_REFERENCE", reference_id, "fixture-relative reference lacks intentional-fixture marker")
        else:
            exists = actual.exists()
            if reference.get("exists") is not exists:
                add_finding(findings, "ERROR", "EXISTENCE_MISMATCH", reference_id, "reference existence differs from filesystem")
            if exists:
                expected_type = "file" if actual.is_file() else "directory" if actual.is_dir() else "missing"
                if reference.get("target_type") != expected_type:
                    add_finding(findings, "ERROR", "TYPE_MISMATCH", reference_id, "reference target type differs from filesystem")
                if actual.is_file() and reference.get("target_sha256") != file_sha256(actual):
                    add_finding(findings, "ERROR", "TARGET_HASH_MISMATCH", reference_id, "reference target hash differs from filesystem")
                if actual.is_file() and target not in load_manifest_paths(root):
                    if TARGET_NOT_IN_BATCH_1 not in issue_values:
                        add_finding(findings, "ERROR", "CONTRADICTORY_REFERENCE", reference_id, "file target is absent from Batch 1 manifest without marker")
                    add_finding(findings, "WARNING", TARGET_NOT_IN_BATCH_1, reference_id, "target is outside the linked Batch 1 manifest")
            elif BROKEN_REFERENCE not in issue_values:
                add_finding(findings, "ERROR", "CONTRADICTORY_REFERENCE", reference_id, "missing target lacks BROKEN_REFERENCE marker")
            if BROKEN_REFERENCE in issue_values:
                add_finding(findings, "WARNING", BROKEN_REFERENCE, reference_id, "repository reference target is missing")
            if TARGET_NOT_IN_BATCH_1 in issue_values:
                add_finding(findings, "WARNING", TARGET_NOT_IN_BATCH_1, reference_id, "reference target is outside the linked Batch 1 manifest")
            if reference.get("target_license") in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"}:
                if LICENSE_UNKNOWN not in issue_values:
                    add_finding(findings, "ERROR", "CONTRADICTORY_REFERENCE", reference_id, "unknown target license lacks marker")
                add_finding(findings, "WARNING", LICENSE_UNKNOWN, reference_id, "target license is unknown")
        for issue in issue_values:
            actual_reference_issues.append({"type": issue, "owner": owner, "target": target, "evidence": reference["evidence"]})

    for index, edge in enumerate(candidate_edges):
        label = f"candidate_edges[{index}]"
        if not isinstance(edge, dict):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "candidate edge must be an object")
            continue
        for field in ("source", "generator", "output", "evidence", "confidence", "review_status", "canonical_graph_match", "issues"):
            if field not in edge:
                add_finding(findings, "ERROR", "MISSING_REQUIRED_FIELD", label, f"missing field: {field}")
        generator_values = edge.get("generator", [])
        if not isinstance(generator_values, list) or not generator_values:
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "generator must be a non-empty list")
        else:
            for generator in generator_values:
                if generator not in file_by_path:
                    add_finding(findings, "ERROR", "BROKEN_GENERATOR", str(generator), "candidate generator is not in files")
        edge_issues = edge.get("issues", [])
        if not isinstance(edge_issues, list) or not all(isinstance(item, str) for item in edge_issues):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", label, "candidate edge issues must be strings")
            edge_issues = []
        if edge.get("canonical_graph_match") is not True and CANDIDATE_NOT_CANONICAL not in edge_issues:
            add_finding(findings, "ERROR", "CONTRADICTORY_EDGE", label, "non-canonical edge lacks marker")
        output = edge.get("output")
        if isinstance(output, str) and not (root / Path(output)).exists() and OUTPUT_MISSING not in edge_issues:
            add_finding(findings, "ERROR", "CONTRADICTORY_EDGE", label, "missing output lacks OUTPUT_MISSING marker")
        if edge.get("source") == SOURCE_MISSING and SOURCE_MISSING not in edge_issues:
            add_finding(findings, "ERROR", "CONTRADICTORY_EDGE", label, "SOURCE_MISSING source lacks marker")
        if CANDIDATE_NOT_CANONICAL in edge_issues:
            add_finding(findings, "WARNING", CANDIDATE_NOT_CANONICAL, label, "candidate edge requires provenance review")
        if SOURCE_MISSING in edge_issues:
            add_finding(findings, "WARNING", SOURCE_MISSING, label, "candidate edge has no static source")
        if OUTPUT_MISSING in edge_issues:
            add_finding(findings, "WARNING", OUTPUT_MISSING, label, "candidate output is missing")

    unresolved_keys = {
        (item.get("type"), str(item.get("owner", item.get("generator", [""]))), item.get("target", item.get("output", "")))
        for item in unresolved
        if isinstance(item, dict)
    }
    expected_keys = {
        (item["type"], str(item.get("owner", item.get("generator", [""]))), item.get("target", item.get("output", "")))
        for item in actual_reference_issues
        if item["type"] in {BROKEN_REFERENCE, TARGET_NOT_IN_BATCH_1, INTENTIONAL_TEST_FIXTURE}
    }
    for edge in candidate_edges:
        for issue in edge.get("issues", []):
            if issue in {SOURCE_MISSING, OUTPUT_MISSING}:
                expected_keys.add((issue, str(edge.get("generator", [""])), edge.get("output", edge.get("source", ""))))
    if unresolved_keys != expected_keys:
        add_finding(findings, "ERROR", "UNRESOLVED_MISMATCH", "unresolved", "unresolved list does not match embedded issue markers")

    summary = matrix.get("summary")
    if not isinstance(summary, dict):
        add_finding(findings, "ERROR", "MATRIX_SYNTAX", "summary", "summary must be an object")
        summary = {}
    expected_summary = {
        "files_scanned": len(files),
        "files_with_references": sum(record.get("reference_count", 0) > 0 for record in files if isinstance(record, dict)),
        "references": len(references),
        "existing_targets": sum(reference.get("exists") is True for reference in references if isinstance(reference, dict)),
        "fixture_references": sum(reference.get("reference_scope") == "test_fixture_relative" for reference in references if isinstance(reference, dict)),
        "broken_references": sum(BROKEN_REFERENCE in reference.get("issues", []) for reference in references if isinstance(reference, dict)),
        "intentional_test_fixtures": sum(INTENTIONAL_TEST_FIXTURE in reference.get("issues", []) for reference in references if isinstance(reference, dict)),
        "target_directories": sum(reference.get("target_type") == "directory" for reference in references if isinstance(reference, dict)),
        "target_not_in_batch_1_manifest": sum(TARGET_NOT_IN_BATCH_1 in reference.get("issues", []) for reference in references if isinstance(reference, dict)),
        "unknown_license_references": sum(LICENSE_UNKNOWN in reference.get("issues", []) for reference in references if isinstance(reference, dict)),
        "producer_candidate_files": sum(record.get("role") in {"producer_candidate", "producer_and_consumer_candidate"} for record in files if isinstance(record, dict)),
        "candidate_edges": len(candidate_edges),
        "candidate_edges_matching_canonical": sum(edge.get("canonical_graph_match") is True for edge in candidate_edges if isinstance(edge, dict)),
        "candidate_edges_source_missing": sum(SOURCE_MISSING in edge.get("issues", []) for edge in candidate_edges if isinstance(edge, dict)),
        "duplicate_hash_groups": len(duplicate_groups),
    }
    for key, expected in expected_summary.items():
        if summary.get(key) != expected:
            add_finding(findings, "ERROR", "SUMMARY_MISMATCH", key, f"expected {expected}, got {summary.get(key)}")
    if not isinstance(summary.get("write_sites"), int) or summary["write_sites"] < 0:
        add_finding(findings, "ERROR", "SUMMARY_MISMATCH", "write_sites", "write_sites must be a non-negative integer")

    for item in unresolved:
        if not isinstance(item, dict) or not isinstance(item.get("evidence"), list):
            add_finding(findings, "ERROR", "MATRIX_SYNTAX", "unresolved", "unresolved records need evidence lists")

    errors = sum(item["severity"] == "ERROR" for item in findings)
    warnings = sum(item["severity"] == "WARNING" for item in findings)
    return {"valid": errors == 0, "errors": errors, "warnings": warnings, "findings": findings, "summary": summary}


def load_manifest_paths(root: Path) -> set[str]:
    path = root / MANIFEST_RELATIVE
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return set()
    return {
        entry["path"]
        for entry in manifest.get("entries", [])
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matrix", type=Path)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    matrix_path = args.matrix if args.matrix.is_absolute() else root / args.matrix
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(json.dumps({"valid": False, "errors": 1, "warnings": 0, "findings": [{"severity": "ERROR", "code": "MATRIX_SYNTAX", "path": str(matrix_path), "message": str(exc)}]}, ensure_ascii=False))
        return 1
    result = validate_matrix(matrix, root)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
