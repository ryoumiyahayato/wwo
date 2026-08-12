#!/usr/bin/env python3
"""Validate the mechanically-safe Batch 3 provenance review backlog."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import generate_review_backlog  # noqa: E402


REQUIRED_ITEM_FIELDS = {
    "rank",
    "key",
    "target_type",
    "path",
    "priority",
    "issues",
    "category",
    "action",
    "safety",
    "evidence",
    "review_status",
}
KNOWN_ISSUES = set(generate_review_backlog.SEVERITY) | {"CANDIDATE_NOT_CANONICAL"}


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def owner_key(value: Any) -> str:
    if isinstance(value, list):
        return ",".join(str(item) for item in value)
    return str(value)


def validate_backlog(backlog: dict[str, Any], root: Path) -> dict[str, Any]:
    findings: list[dict[str, str]] = []

    def error(code: str, path: str, message: str) -> None:
        findings.append({"severity": "ERROR", "code": code, "path": path, "message": message})

    def warning(code: str, path: str, message: str) -> None:
        findings.append({"severity": "WARNING", "code": code, "path": path, "message": message})

    if backlog.get("schema_version") != 1:
        error("BACKLOG_SCHEMA", "", "schema_version must be 1")
    if backlog.get("backlog_kind") != "wwo_provenance_review_backlog":
        error("BACKLOG_SCHEMA", "", "backlog_kind is not recognized")
    if backlog.get("audit_batch") != "BATCH_3":
        error("BACKLOG_SCHEMA", "", "audit_batch must be BATCH_3")
    policy = backlog.get("policy")
    if not isinstance(policy, dict):
        error("BACKLOG_SCHEMA", "policy", "policy must be an object")
    else:
        for key in ("mechanically_safe_only", "license_inference", "authoritative_data_modification", "automatic_asset_regeneration"):
            if policy.get(key) is not ({"mechanically_safe_only": True, "license_inference": False, "authoritative_data_modification": False, "automatic_asset_regeneration": False}[key]):
                error("UNSAFE_POLICY", key, "policy does not enforce the safe Batch 3 boundary")

    manifest_path = root / generate_review_backlog.MANIFEST_RELATIVE
    matrix_path = root / generate_review_backlog.MATRIX_RELATIVE
    if not manifest_path.is_file():
        error("SOURCE_MISSING", str(manifest_path), "manifest source is missing")
    if not matrix_path.is_file():
        error("SOURCE_MISSING", str(matrix_path), "matrix source is missing")
    try:
        manifest = load_json(manifest_path)
        matrix = load_json(matrix_path)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        error("SOURCE_SYNTAX", "sources", str(exc))
        manifest = {}
        matrix = {}

    entries = manifest.get("entries", []) if isinstance(manifest, dict) else []
    entry_paths = {entry.get("path") for entry in entries if isinstance(entry, dict)}
    matrix_unresolved = matrix.get("unresolved", []) if isinstance(matrix, dict) else []
    matrix_issue_keys = {
        (
            item.get("type"),
            owner_key(item.get("owner", item.get("generator", ""))),
            item.get("target", item.get("output", "")),
        )
        for item in matrix_unresolved
        if isinstance(item, dict)
    }
    items = backlog.get("items")
    if not isinstance(items, list):
        error("BACKLOG_SYNTAX", "items", "items must be a list")
        items = []
    if [item.get("rank") for item in items if isinstance(item, dict)] != list(range(1, len(items) + 1)):
        error("BACKLOG_ORDER", "items", "ranks must be contiguous and ordered")
    if len({item.get("key") for item in items if isinstance(item, dict)}) != len(items):
        error("DUPLICATE_KEY", "items", "backlog keys must be unique")
    for index, item in enumerate(items):
        label = f"items[{index}]"
        if not isinstance(item, dict):
            error("BACKLOG_SYNTAX", label, "item must be an object")
            continue
        missing = sorted(REQUIRED_ITEM_FIELDS - set(item))
        if missing:
            error("MISSING_REQUIRED_FIELD", label, ", ".join(missing))
            continue
        if not isinstance(item["priority"], int) or item["priority"] < 0:
            error("INVALID_PRIORITY", label, "priority must be a non-negative integer")
        if not isinstance(item["issues"], list) or not all(isinstance(issue, str) for issue in item["issues"]):
            error("BACKLOG_SYNTAX", label, "issues must be a list of strings")
            issues = []
        else:
            issues = item["issues"]
        unknown = sorted(set(issues) - KNOWN_ISSUES)
        for issue in unknown:
            error("UNKNOWN_ISSUE", f"{label}:{issue}", "issue is not recognized")
        if item["target_type"] == "file" and item["path"] not in entry_paths:
            error("BROKEN_TARGET", item["path"], "file backlog target is absent from manifest")
        if item["target_type"] == "reference":
            owner = item.get("owner", "")
            key_candidates = {
                (issue, owner_key(owner), item["path"])
                for issue in issues
            }
            if not key_candidates.intersection(matrix_issue_keys):
                error("BROKEN_TARGET", item["path"], "reference backlog target is absent from matrix unresolved evidence")
        if item["target_type"] == "dependency_edge" and not item.get("owner"):
            error("BACKLOG_SYNTAX", label, "dependency edge must retain generator evidence")
        if "Do not" not in item["safety"] and "review" not in item["safety"].lower():
            warning("SAFETY_TEXT", label, "safety note should remind reviewers this is not an automatic mutation")
        if "LICENSE_UNKNOWN" in issues:
            warning("LICENSE_UNKNOWN", item["path"], "license unknown remains a review warning")

    summary = backlog.get("summary")
    if not isinstance(summary, dict):
        error("BACKLOG_SCHEMA", "summary", "summary must be an object")
        summary = {}
    expected = {
        "items": len(items),
        "top_priority": max((item.get("priority", 0) for item in items if isinstance(item, dict)), default=0),
        "source_missing_items": sum("SOURCE_MISSING" in item.get("issues", []) for item in items if isinstance(item, dict)),
        "generator_unknown_items": sum("GENERATOR_UNKNOWN" in item.get("issues", []) for item in items if isinstance(item, dict)),
        "broken_reference_items": sum("BROKEN_REFERENCE" in item.get("issues", []) for item in items if isinstance(item, dict)),
    }
    for key, value in expected.items():
        if summary.get(key) != value:
            error("SUMMARY_MISMATCH", key, f"expected {value}, got {summary.get(key)}")
    errors = sum(item["severity"] == "ERROR" for item in findings)
    warnings = sum(item["severity"] == "WARNING" for item in findings)
    return {"valid": errors == 0, "errors": errors, "warnings": warnings, "findings": findings, "summary": summary}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backlog", type=Path)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    path = args.backlog if args.backlog.is_absolute() else root / args.backlog
    try:
        backlog = load_json(path)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(json.dumps({"valid": False, "errors": 1, "warnings": 0, "findings": [{"severity": "ERROR", "code": "BACKLOG_SYNTAX", "path": str(path), "message": str(exc)}]}, ensure_ascii=False))
        return 1
    result = validate_backlog(backlog, root)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
