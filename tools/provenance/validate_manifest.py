#!/usr/bin/env python3
"""Validate a WWO provenance manifest without modifying repository assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


SOURCE_UNKNOWN = "SOURCE_UNKNOWN"
LICENSE_UNKNOWN = "LICENSE_UNKNOWN"
GENERATOR_UNKNOWN = "GENERATOR_UNKNOWN"
PROVENANCE_INCOMPLETE = "PROVENANCE_INCOMPLETE"
SOURCE_MISSING = "SOURCE_MISSING"
MANIFEST_RELATIVE = "docs/data_sources/provenance_manifest.json"
SCOPE_ROOTS = ("data/", "assets/", "docs/")
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
REQUIRED_ENTRY_FIELDS = {
    "path",
    "file_type",
    "size_bytes",
    "sha256",
    "category",
    "kind",
    "known_source",
    "source_locator",
    "author_institution",
    "license",
    "derived_from",
    "generator",
    "confidence",
    "review_status",
}
VALID_KINDS = {"generated", "source", "unknown"}


def normalize_path(value: str) -> str:
    return value.replace("\\", "/").removeprefix("./")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def add_finding(
    findings: list[dict[str, str]],
    severity: str,
    code: str,
    path: str,
    message: str,
) -> None:
    findings.append(
        {
            "severity": severity,
            "code": code,
            "path": path,
            "message": message,
        }
    )


def validate_manifest(manifest: dict[str, Any], root: Path) -> dict[str, Any]:
    findings: list[dict[str, str]] = []
    entries = manifest.get("entries")
    external_sources = manifest.get("external_sources")
    graph = manifest.get("dependency_graph")

    if manifest.get("schema_version") != 1:
        add_finding(findings, "ERROR", "MANIFEST_SCHEMA", "", "schema_version must be 1")
    if manifest.get("manifest_kind") != "wwo_data_asset_provenance":
        add_finding(findings, "ERROR", "MANIFEST_SCHEMA", "", "manifest_kind is not recognized")
    if not isinstance(entries, list):
        add_finding(findings, "ERROR", "MANIFEST_SYNTAX", "", "entries must be a list")
        entries = []
    if not isinstance(external_sources, list):
        add_finding(findings, "ERROR", "MANIFEST_SYNTAX", "", "external_sources must be a list")
        external_sources = []
    if not isinstance(graph, dict) or not isinstance(graph.get("edges"), list):
        add_finding(findings, "ERROR", "MANIFEST_SYNTAX", "", "dependency_graph.edges must be a list")
        graph_edges: list[Any] = []
    else:
        graph_edges = graph["edges"]

    source_ids: set[str] = set()
    for source in external_sources:
        if not isinstance(source, dict):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", "external_sources", "source records must be objects")
            continue
        source_id = source.get("id")
        if not isinstance(source_id, str) or not source_id:
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", "external_sources", "source record id is required")
            continue
        if source_id in source_ids:
            add_finding(findings, "ERROR", "DUPLICATE_SOURCE_ID", source_id, "external source id is duplicated")
        source_ids.add(source_id)
        for field in ("source_locator", "license_locator", "evidence"):
            if not isinstance(source.get(field), list) or not all(isinstance(item, str) for item in source[field]):
                add_finding(findings, "ERROR", "MANIFEST_SYNTAX", source_id, f"{field} must be a list of strings")

    entry_by_path: dict[str, dict[str, Any]] = {}
    hash_groups: dict[str, list[str]] = defaultdict(list)
    for index, entry in enumerate(entries):
        label = f"entries[{index}]"
        if not isinstance(entry, dict):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", label, "entry must be an object")
            continue
        missing = sorted(REQUIRED_ENTRY_FIELDS - set(entry))
        if missing:
            add_finding(findings, "ERROR", "MISSING_REQUIRED_FIELD", label, f"missing fields: {', '.join(missing)}")
            continue

        relative = entry.get("path")
        if not isinstance(relative, str):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", label, "path must be a string")
            continue
        relative = normalize_path(relative)
        if relative != entry["path"]:
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, "path must use normalized repository separators")
        if not relative.startswith(SCOPE_ROOTS) or ".." in Path(relative).parts:
            add_finding(findings, "ERROR", "PATH_OUT_OF_SCOPE", relative, "entry is outside the Batch 1 scope")
        if relative == MANIFEST_RELATIVE:
            add_finding(findings, "ERROR", "PATH_OUT_OF_SCOPE", relative, "manifest must not inventory itself")
        if relative in entry_by_path:
            add_finding(findings, "ERROR", "DUPLICATE_ENTRY_PATH", relative, "entry path is duplicated")
        entry_by_path[relative] = entry

        if not isinstance(entry["size_bytes"], int) or entry["size_bytes"] < 0:
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, "size_bytes must be a non-negative integer")
        if not isinstance(entry["sha256"], str) or not HASH_RE.fullmatch(entry["sha256"]):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, "sha256 must be a lowercase SHA-256 hex digest")
        if entry["kind"] not in VALID_KINDS:
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, "kind is not a recognized value")
        for field in ("source_locator", "license_locator", "derived_from"):
            if not isinstance(entry[field], list) or not all(isinstance(item, str) for item in entry[field]):
                add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, f"{field} must be a list of strings")
        generator_value = entry["generator"]
        valid_generator = (
            generator_value == GENERATOR_UNKNOWN
            or (
                isinstance(generator_value, list)
                and bool(generator_value)
                and all(isinstance(item, str) and item != GENERATOR_UNKNOWN for item in generator_value)
            )
        )
        if not valid_generator:
            add_finding(findings, "ERROR", "INVALID_GENERATOR", relative, "generator must be GENERATOR_UNKNOWN or a non-empty list of concrete repository paths")
        for field in ("known_source", "author_institution", "license", "confidence", "review_status"):
            if not isinstance(entry[field], str):
                add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, f"{field} must be a string")

        path = root / Path(relative)
        if not path.is_file():
            add_finding(findings, "ERROR", "MISSING_REPOSITORY_FILE", relative, "manifest path does not exist")
        else:
            actual_size = path.stat().st_size
            if actual_size != entry["size_bytes"]:
                add_finding(findings, "ERROR", "SIZE_MISMATCH", relative, f"manifest={entry['size_bytes']} actual={actual_size}")
            if isinstance(entry["sha256"], str) and HASH_RE.fullmatch(entry["sha256"]):
                actual_hash = file_sha256(path)
                if actual_hash != entry["sha256"]:
                    add_finding(findings, "ERROR", "HASH_MISMATCH", relative, f"manifest={entry['sha256']} actual={actual_hash}")
        if isinstance(entry.get("sha256"), str) and HASH_RE.fullmatch(entry["sha256"]):
            hash_groups[entry["sha256"]].append(relative)

        issues = entry.get("issues", [])
        if not isinstance(issues, list) or not all(isinstance(item, str) for item in issues):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", relative, "issues must be a list of strings")
            issues = []
        issue_set = set(issues)
        if entry["known_source"] == SOURCE_UNKNOWN:
            if entry["source_locator"]:
                add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "SOURCE_UNKNOWN has source locators")
            if SOURCE_UNKNOWN not in issue_set:
                add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "unknown source is missing SOURCE_UNKNOWN")
            else:
                add_finding(findings, "WARNING", SOURCE_UNKNOWN, relative, "no explicit source evidence is recorded")
        elif SOURCE_UNKNOWN in issue_set:
            add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "known source is marked SOURCE_UNKNOWN")
        if entry["license"] in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"}:
            if "LICENSE_UNKNOWN" not in issue_set:
                add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "unknown license is missing LICENSE_UNKNOWN")
            else:
                add_finding(findings, "WARNING", LICENSE_UNKNOWN, relative, "license is not explicitly recorded or is mixed with unknown terms")
        elif "LICENSE_UNKNOWN" in issue_set:
            add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "known license is marked LICENSE_UNKNOWN")
        if entry["kind"] == "generated":
            if not entry["derived_from"]:
                if SOURCE_MISSING not in issue_set:
                    add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "generated entry has no derived_from and no SOURCE_MISSING")
                else:
                    add_finding(findings, "WARNING", SOURCE_MISSING, relative, "generated output has no traceable source")
            elif SOURCE_MISSING in issue_set:
                add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "generated entry has sources but is marked SOURCE_MISSING")
            if entry["generator"] == GENERATOR_UNKNOWN:
                if GENERATOR_UNKNOWN not in issue_set:
                    add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, "unknown generator is missing GENERATOR_UNKNOWN")
                else:
                    add_finding(findings, "WARNING", GENERATOR_UNKNOWN, relative, "generator is not present or not documented")
            elif isinstance(entry["generator"], list) and all(isinstance(generator, str) for generator in entry["generator"]):
                for generator in entry["generator"]:
                    if not (root / Path(normalize_path(generator))).is_file():
                        add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", relative, f"declared generator does not exist: {generator}")
        for issue in sorted(issue_set):
            if issue in {SOURCE_MISSING, "SOURCE_LOCATOR_MISSING", "OBSOLETE_OR_LEGACY_CANDIDATE", "PROVENANCE_INCOMPLETE"}:
                add_finding(findings, "WARNING", issue, relative, f"manifest records {issue}")
            elif issue == "BROKEN_DERIVED_FROM":
                add_finding(findings, "ERROR", issue, relative, "manifest records a broken derived-from relationship")
            elif issue == "CONTRADICTORY_PROVENANCE":
                add_finding(findings, "ERROR", issue, relative, "manifest records contradictory provenance")
            elif issue == "ASSET_REGISTRY_HASH_MISMATCH":
                add_finding(findings, "ERROR", issue, relative, "asset hash disagrees with its source registry")

    for digest, paths in sorted(hash_groups.items()):
        if len(paths) < 2 or all(Path(path).name == ".gitkeep" for path in paths):
            continue
        add_finding(findings, "WARNING", "DUPLICATE_HASH", ", ".join(paths), f"identical SHA-256 {digest} appears under multiple paths")

    expected_edges: set[tuple[str, str]] = set()
    for path, entry in entry_by_path.items():
        for source in entry.get("derived_from", []):
            expected_edges.add((path, source))
            if source not in entry_by_path and source not in source_ids:
                add_finding(findings, "ERROR", "BROKEN_DERIVED_FROM", path, f"derived-from reference does not resolve: {source}")
            if source == path:
                add_finding(findings, "ERROR", "CONTRADICTORY_PROVENANCE", path, "entry derives from itself")

    seen_edges: set[tuple[str, str]] = set()
    for index, edge in enumerate(graph_edges):
        label = f"dependency_graph.edges[{index}]"
        if not isinstance(edge, dict):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", label, "edge must be an object")
            continue
        source = edge.get("source")
        output = edge.get("output")
        generators = edge.get("generator")
        if not isinstance(source, str) or not isinstance(output, str) or not isinstance(generators, list):
            add_finding(findings, "ERROR", "MANIFEST_SYNTAX", label, "edge requires source, generator list, and output")
            continue
        if (output, source) not in expected_edges:
            add_finding(findings, "ERROR", "BROKEN_GRAPH_EDGE", output, "graph edge is not represented by the entry's derived_from")
        seen_edges.add((output, source))
        if output not in entry_by_path:
            add_finding(findings, "ERROR", "BROKEN_GRAPH_EDGE", output, "graph output does not resolve to an entry")
        if source not in entry_by_path and source not in source_ids:
            add_finding(findings, "ERROR", "BROKEN_DERIVED_FROM", output, f"graph source does not resolve: {source}")
    for output, source in sorted(expected_edges - seen_edges):
        add_finding(findings, "ERROR", "BROKEN_GRAPH_EDGE", output, f"missing graph edge for derived-from source: {source}")

    summary = manifest.get("summary")
    if not isinstance(summary, dict):
        add_finding(findings, "ERROR", "MANIFEST_SYNTAX", "summary", "summary must be an object")
        summary = {}
    source_unknown_count = sum(entry.get("known_source") == SOURCE_UNKNOWN for entry in entry_by_path.values())
    license_unknown_count = sum(entry.get("license") in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"} for entry in entry_by_path.values())
    generated_count = sum(entry.get("kind") == "generated" for entry in entry_by_path.values())
    duplicate_groups = sum(
        len(paths) > 1 and not all(Path(path).name == ".gitkeep" for path in paths)
        for paths in hash_groups.values()
    )
    expected_summary = {
        "files_inventoried": len(entry_by_path),
        "source_known": len(entry_by_path) - source_unknown_count,
        "source_unknown": source_unknown_count,
        "license_known": len(entry_by_path) - license_unknown_count,
        "license_unknown": license_unknown_count,
        "generated_assets": generated_count,
        "duplicate_hash_groups": duplicate_groups,
    }
    for key, value in expected_summary.items():
        if summary.get(key) != value:
            add_finding(findings, "ERROR", "SUMMARY_MISMATCH", key, f"manifest={summary.get(key)!r} calculated={value!r}")

    counts = {severity: sum(item["severity"] == severity for item in findings) for severity in ("ERROR", "WARNING", "INFO")}
    return {
        "valid": counts["ERROR"] == 0,
        "errors": counts["ERROR"],
        "warnings": counts["WARNING"],
        "info": counts["INFO"],
        "findings": findings,
        "summary": expected_summary,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--strict", action="store_true", help="treat warnings as a non-zero result")
    args = parser.parse_args()
    manifest_path = args.manifest.resolve()
    root = (args.root.resolve() if args.root else manifest_path.parents[2])
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(json.dumps({"valid": False, "errors": 1, "warnings": 0, "message": str(error)}, ensure_ascii=False))
        return 2
    if not isinstance(manifest, dict):
        print(json.dumps({"valid": False, "errors": 1, "warnings": 0, "message": "manifest root must be an object"}, ensure_ascii=False))
        return 2
    result = validate_manifest(manifest, root)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 1 if result["errors"] or (args.strict and result["warnings"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
