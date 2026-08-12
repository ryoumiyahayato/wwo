#!/usr/bin/env python3
"""Build a deterministic matrix of repository producers and data/asset references.

Batch 1 inventories the data, asset, and documentation records themselves.  This
scanner adds the repository-side evidence that consumes or may generate those
records.  It only reports static literals and write-site candidates; it never
turns a candidate into authoritative provenance and never infers a license.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
MATRIX_KIND = "wwo_provenance_reference_matrix"
DEFAULT_OUTPUT = "docs/data_sources/provenance_reference_matrix.json"
MANIFEST_RELATIVE = "docs/data_sources/provenance_manifest.json"
SCOPE_ROOTS = ("scripts", "scenes", "shaders", "tests", "tools")
TARGET_ROOTS = ("data/", "assets/")

BROKEN_REFERENCE = "BROKEN_REFERENCE"
LICENSE_UNKNOWN = "LICENSE_UNKNOWN"
SOURCE_MISSING = "SOURCE_MISSING"
PROVENANCE_INCOMPLETE = "PROVENANCE_INCOMPLETE"
TARGET_NOT_IN_BATCH_1 = "TARGET_NOT_IN_BATCH_1_MANIFEST"
OUTPUT_MISSING = "OUTPUT_MISSING"
CANDIDATE_NOT_CANONICAL = "CANDIDATE_NOT_CANONICAL"
INTENTIONAL_TEST_FIXTURE = "INTENTIONAL_TEST_FIXTURE"

HASH_RE = re.compile(r"^[0-9a-f]{64}$")
PATH_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_/-])(?P<resource>res://)?(?P<path>(?:data|assets)/[A-Za-z0-9][A-Za-z0-9_./-]*)"
)
OUTPUT_MARKER_PATTERN = re.compile(
    r"\b(?:OUTPUT(?:_PATH|_FILE|_DIR)?|REGISTRY(?:_PATH)?|CACHE(?:_PATH)?|"
    r"SHARD_ROOT|DESTINATION(?:_PATH)?|MANIFEST_OUTPUT|INDEX_OUTPUT)\b",
    re.IGNORECASE,
)
WRITE_PATTERNS = (
    ("python_path_write", re.compile(r"\.write_(?:text|bytes)\s*\(")),
    ("python_json_dump", re.compile(r"\bjson\.dump\s*\(")),
    ("python_open_write", re.compile(r"\bopen\s*\([^\n]*['\"](?:w|a|x)\+?['\"]")),
    ("python_copy", re.compile(r"\b(?:shutil\.)?copy(?:2)?\s*\(")),

    ("godot_store", re.compile(r"\bstore_(?:string|buffer|var)\s*\(")),
    ("godot_resource_save", re.compile(r"\bResourceSaver\.save\s*\(")),
    ("powershell_write", re.compile(r"\b(?:Set-Content|Out-File|Export-Csv|Copy-Item)\b")),
)

MIME_TYPES = {
    ".gd": "text/x-gdscript",
    ".gdshader": "text/x-gdshader",
    ".json": "application/json",
    ".csv": "text/csv",
    ".md": "text/markdown",
    ".py": "text/x-python",
    ".ps1": "text/x-powershell",
    ".tscn": "text/plain",
    ".tres": "text/plain",
    ".sh": "text/x-shellscript",
    ".yml": "text/yaml",
    ".yaml": "text/yaml",
}
TEXT_SUFFIXES = set(MIME_TYPES) | {".txt", ".cfg", ".godot"}


def normalize_path(value: str) -> str:
    return value.replace("\\", "/").removeprefix("./").removeprefix("res://")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_type(path: Path) -> str:
    return MIME_TYPES.get(path.suffix.lower(), "application/octet-stream")


def unique(values: Iterable[str]) -> list[str]:
    return sorted({value for value in values if value})


def git_tracked_files(root: Path) -> list[str]:
    command = ["git", "-C", str(root), "ls-files", "--", *SCOPE_ROOTS]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    return sorted(normalize_path(line) for line in result.stdout.splitlines() if line.strip())


def scoped_files(root: Path) -> list[str]:
    tracked = git_tracked_files(root)
    if tracked:
        return tracked
    files: list[str] = []
    for scope in SCOPE_ROOTS:
        directory = root / scope
        if not directory.exists():
            continue
        for path in directory.rglob("*"):
            if path.is_file() and path.suffix.lower() != ".uid":
                files.append(path.relative_to(root).as_posix())
    return sorted(files)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def read_text(path: Path) -> str:
    if path.suffix.lower() not in TEXT_SUFFIXES:
        return ""
    try:
        data = path.read_bytes()
    except OSError:
        return ""
    if b"\x00" in data:
        return ""
    return data.decode("utf-8", errors="replace")


def clean_target(raw: str) -> str:
    value = normalize_path(raw)
    while value and value[-1] in ".,;:)]}>\"'":
        value = value[:-1]
    return value.rstrip("/")


def target_info(root: Path, target: str, manifest_by_path: dict[str, dict[str, Any]]) -> dict[str, Any]:
    normalized = clean_target(target)
    path = root / Path(normalized)
    exists = path.exists()
    is_file = path.is_file()
    entry = manifest_by_path.get(normalized)
    issues: list[str] = []
    if not exists:
        issues.append(BROKEN_REFERENCE)
    elif is_file and entry is None:
        issues.append(TARGET_NOT_IN_BATCH_1)
    license_name = entry.get("license") if entry else None
    if entry and license_name in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"}:
        issues.append(LICENSE_UNKNOWN)
    return {
        "target": normalized,
        "exists": exists,
        "target_type": "file" if is_file else "directory" if path.is_dir() else "missing",
        "target_sha256": file_sha256(path) if is_file else None,
        "target_manifest_kind": entry.get("kind") if entry else None,
        "target_license": license_name,
        "issues": sorted(set(issues)),
    }


def extract_references(owner: str, text: str) -> list[dict[str, Any]]:
    references: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        for match in PATH_PATTERN.finditer(line):
            raw = match.group(0)
            target = clean_target(match.group("path"))
            if not target or not target.startswith(TARGET_ROOTS):
                continue
            prefix_text = line[: match.start()]
            last_quote = max(prefix_text.rfind('"'), prefix_text.rfind("'"))
            last_scheme = max(prefix_text.rfind("http://"), prefix_text.rfind("https://"))
            if last_scheme > last_quote:
                continue
            has_extension = bool(Path(target).suffix)
            has_nested_path = target.count("/") >= 2
            is_path_constructor = bool(re.search(r"\bPath\s*\(", line))
            if not has_extension and not has_nested_path and not is_path_constructor and not match.group("resource"):
                continue
            prefix = "resource_path" if match.group("resource") else "repository_path_literal"
            stripped = line.strip()
            context = "comment" if stripped.startswith(("#", "//", ";")) else "code_or_text"
            reference_scope = "repository"
            if owner.startswith("tests/") and not match.group("resource"):
                reference_scope = "test_fixture_relative"
            references.append(
                {
                    "owner": owner,
                    "target": target,
                    "reference_kind": prefix,
                    "literal": raw,
                    "line": line_number,
                    "column": match.start("path") + 1,
                    "context": context,
                    "reference_scope": reference_scope,
                    "line_text": line.rstrip(),
                }
            )
    return references


def extract_write_sites(owner: str, text: str) -> list[dict[str, Any]]:
    sites: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        for api_name, pattern in WRITE_PATTERNS:
            if pattern.search(line):
                sites.append(
                    {
                        "owner": owner,
                        "line": line_number,
                        "api": api_name,
                        "evidence": f"{owner}:{line_number}",
                    }
                )
    return sites


def is_output_candidate(reference: dict[str, Any], write_sites: list[dict[str, Any]]) -> bool:
    if not write_sites or reference.get("reference_scope") != "repository":
        return False
    line = reference["line_text"]
    if OUTPUT_MARKER_PATTERN.search(line):
        return True
    return any(site["line"] == reference["line"] for site in write_sites)


def canonical_pairs(manifest: dict[str, Any]) -> set[tuple[str, str]]:
    graph = manifest.get("dependency_graph", {})
    edges = graph.get("edges", []) if isinstance(graph, dict) else []
    pairs: set[tuple[str, str]] = set()
    for edge in edges:
        if not isinstance(edge, dict):
            continue
        output = edge.get("output")
        generators = edge.get("generator", [])
        if not isinstance(output, str) or not isinstance(generators, list):
            continue
        pairs.update((str(generator), output) for generator in generators if isinstance(generator, str))
    return pairs


def build_matrix(root: Path, base_revision: str, manifest_path: Path | None = None) -> dict[str, Any]:
    manifest_path = manifest_path or root / MANIFEST_RELATIVE
    manifest = load_json(manifest_path)
    manifest_entries = manifest.get("entries", [])
    manifest_by_path = {
        entry.get("path"): entry
        for entry in manifest_entries
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }
    canonical = canonical_pairs(manifest)
    files = scoped_files(root)
    file_records: list[dict[str, Any]] = []
    references: list[dict[str, Any]] = []
    write_sites: list[dict[str, Any]] = []
    per_file_references: dict[str, list[dict[str, Any]]] = defaultdict(list)
    per_file_writes: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for relative in files:
        path = root / Path(relative)
        text = read_text(path)
        owner_references = extract_references(relative, text)
        owner_writes = extract_write_sites(relative, text)
        per_file_references[relative].extend(owner_references)
        per_file_writes[relative].extend(owner_writes)
        for reference in owner_references:
            if reference["reference_scope"] == "test_fixture_relative":
                reference.update(
                    {
                        "exists": None,
                        "target_type": "test_fixture_relative",
                        "target_sha256": None,
                        "target_manifest_kind": None,
                        "target_license": None,
                        "issues": [INTENTIONAL_TEST_FIXTURE],
                    }
                )
            else:
                reference.update(target_info(root, reference["target"], manifest_by_path))
            reference["evidence"] = [f"{relative}:{reference['line']}"]
            references.append(reference)
        write_sites.extend(owner_writes)
        file_records.append(
            {
                "path": relative,
                "file_type": file_type(path),
                "size_bytes": path.stat().st_size,
                "sha256": file_sha256(path),
                "role": "unreferenced",
                "reference_count": len(owner_references),
                "write_site_count": len(owner_writes),
                "issues": [],
            }
        )

    references.sort(key=lambda item: (item["owner"], item["line"], item["column"], item["target"], item["literal"]))
    for index, reference in enumerate(references, start=1):
        reference["id"] = f"ref-{index:06d}"

    references_by_owner: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for reference in references:
        references_by_owner[reference["owner"]].append(reference)

    candidate_edges: list[dict[str, Any]] = []
    file_by_path = {record["path"]: record for record in file_records}
    for relative in files:
        owner_references = references_by_owner.get(relative, [])
        owner_writes = per_file_writes.get(relative, [])
        output_references = [
            reference
            for reference in owner_references
            if is_output_candidate(
                next(
                    raw
                    for raw in per_file_references[relative]
                    if raw["line"] == reference["line"]
                    and raw["column"] == reference["column"]
                    and raw["target"] == reference["target"]
                ),
                owner_writes,
            )
        ]
        input_references = [reference for reference in owner_references if reference not in output_references]
        record = file_by_path[relative]
        if output_references:
            record["role"] = "producer_and_consumer_candidate" if input_references else "producer_candidate"
            record["issues"].append(PROVENANCE_INCOMPLETE)
        elif owner_references:
            record["role"] = "consumer"
        elif owner_writes:
            record["role"] = "write_site_without_static_target"

        for output_reference in output_references:
            sources = sorted(
                {
                    reference["target"]
                    for reference in input_references
                    if reference["target"] != output_reference["target"]
                }
            )
            source_values = sources or [SOURCE_MISSING]
            for source in source_values:
                issues = [CANDIDATE_NOT_CANONICAL]
                if source == SOURCE_MISSING:
                    issues.append(SOURCE_MISSING)
                if not output_reference["exists"]:
                    issues.append(OUTPUT_MISSING)
                if (relative, output_reference["target"]) not in canonical:
                    canonical_match = False
                else:
                    canonical_match = True
                candidate_edges.append(
                    {
                        "source": source,
                        "generator": [relative],
                        "output": output_reference["target"],
                        "evidence": [f"{relative}:{output_reference['line']}"],
                        "confidence": "medium" if OUTPUT_MARKER_PATTERN.search(
                            next(
                                raw["line_text"]
                                for raw in per_file_references[relative]
                                if raw["line"] == output_reference["line"]
                                and raw["column"] == output_reference["column"]
                                and raw["target"] == output_reference["target"]
                            )
                        ) else "low",
                        "review_status": "REVIEW_REQUIRED",
                        "canonical_graph_match": canonical_match,
                        "issues": sorted(set(issues)),
                    }
                )

    for record in file_records:
        record["issues"] = sorted(set(record["issues"]))
    for reference in references:
        reference.pop("line_text", None)
    candidate_edges.sort(key=lambda edge: (edge["output"], edge["source"], edge["generator"]))

    hash_groups: dict[str, list[str]] = defaultdict(list)
    for record in file_records:
        hash_groups[record["sha256"]].append(record["path"])
    duplicate_hash_groups = [
        sorted(paths)
        for paths in hash_groups.values()
        if len(paths) > 1 and not all(Path(path).name == ".gitkeep" for path in paths)
    ]
    duplicate_hash_groups.sort(key=lambda paths: (paths[0], len(paths)))

    reference_issues = [
        {
            "type": issue,
            "owner": reference["owner"],
            "target": reference["target"],
            "evidence": reference["evidence"],
        }
        for reference in references
        for issue in reference["issues"]
        if issue in {BROKEN_REFERENCE, TARGET_NOT_IN_BATCH_1, INTENTIONAL_TEST_FIXTURE}
    ]
    candidate_issues = [
        {
            "type": issue,
            "generator": edge["generator"],
            "source": edge["source"],
            "output": edge["output"],
            "evidence": edge["evidence"],
        }
        for edge in candidate_edges
        for issue in edge["issues"]
        if issue in {SOURCE_MISSING, OUTPUT_MISSING}
    ]
    unresolved = sorted(
        reference_issues + candidate_issues,
        key=lambda item: (item["type"], item.get("owner", item.get("generator", [""])), item.get("target", item.get("output", ""))),
    )

    summary = {
        "files_scanned": len(file_records),
        "files_with_references": sum(record["reference_count"] > 0 for record in file_records),
        "references": len(references),
        "write_sites": len(write_sites),
        "existing_targets": sum(reference["exists"] is True for reference in references),
        "fixture_references": sum(reference["reference_scope"] == "test_fixture_relative" for reference in references),
        "broken_references": sum(BROKEN_REFERENCE in reference["issues"] for reference in references),
        "intentional_test_fixtures": sum(INTENTIONAL_TEST_FIXTURE in reference["issues"] for reference in references),
        "target_directories": sum(reference["target_type"] == "directory" for reference in references),
        "target_not_in_batch_1_manifest": sum(TARGET_NOT_IN_BATCH_1 in reference["issues"] for reference in references),
        "unknown_license_references": sum(LICENSE_UNKNOWN in reference["issues"] for reference in references),
        "producer_candidate_files": sum(record["role"] in {"producer_candidate", "producer_and_consumer_candidate"} for record in file_records),
        "candidate_edges": len(candidate_edges),
        "candidate_edges_matching_canonical": sum(edge["canonical_graph_match"] for edge in candidate_edges),
        "candidate_edges_source_missing": sum(SOURCE_MISSING in edge["issues"] for edge in candidate_edges),
        "duplicate_hash_groups": len(duplicate_hash_groups),
    }

    return {
        "schema_version": SCHEMA_VERSION,
        "matrix_kind": MATRIX_KIND,
        "audit_batch": "BATCH_2",
        "audit_base_revision": base_revision,
        "generated_by": "tools/provenance/scan_reference_matrix.py",
        "scope": {
            "included_roots": list(SCOPE_ROOTS),
            "target_roots": list(TARGET_ROOTS),
            "tracked_files_only": True,
            "static_reference_patterns": ["res://data/**", "res://assets/**", "data/**", "assets/**"],
            "write_site_detection": "static API and output-marker candidates only",
        },
        "linked_manifest": MANIFEST_RELATIVE,
        "summary": summary,
        "files": file_records,
        "references": references,
        "candidate_edges": candidate_edges,
        "duplicate_hash_groups": duplicate_hash_groups,
        "unresolved": unresolved,
    }


def write_matrix(matrix: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=Path(DEFAULT_OUTPUT))
    parser.add_argument("--manifest", type=Path, default=Path(MANIFEST_RELATIVE))
    parser.add_argument("--base-revision", default="HEAD")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    output = args.output if args.output.is_absolute() else root / args.output
    manifest = args.manifest if args.manifest.is_absolute() else root / args.manifest
    matrix = build_matrix(root, args.base_revision, manifest)
    write_matrix(matrix, output)
    print(json.dumps(matrix["summary"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
