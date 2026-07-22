#!/usr/bin/env python3
"""Static audit for GDScript runtime structure and safe redundancy candidates."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

CLASS_RE = re.compile(r"(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")
EXTENDS_RE = re.compile(r"(?m)^\s*extends\s+(?:\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*))")

IGNORED_PARTS = {".git", ".godot", "builds", "data", "addons"}
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".cfg", ".json", ".md", ".ps1", ".py", ".yml", ".yaml"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--fail-on-hard-findings", action="store_true")
    return parser.parse_args()


def included(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    return not any(part in IGNORED_PARTS for part in relative.parts)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def line_count(text: str) -> int:
    return text.count("\n") + (0 if text.endswith("\n") else 1)


def audit(root: Path) -> dict:
    root = root.resolve()
    scripts = sorted(
        path for path in (root / "scripts").rglob("*.gd")
        if included(path, root)
    )
    tests = sorted(
        path for path in (root / "tests").rglob("*.gd")
        if included(path, root)
    )
    all_text_files = sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES and included(path, root)
    )
    text_by_path = {path: read_text(path) for path in all_text_files}

    class_locations: dict[str, list[str]] = defaultdict(list)
    class_by_path: dict[Path, str] = {}
    extends_by_path: dict[Path, str] = {}
    hashes: dict[str, list[str]] = defaultdict(list)
    large_files: list[dict] = []

    for path in scripts:
        text = text_by_path[path]
        relative = path.relative_to(root).as_posix()
        class_match = CLASS_RE.search(text)
        if class_match:
            class_name = class_match.group(1)
            class_locations[class_name].append(relative)
            class_by_path[path] = class_name
        extends_match = EXTENDS_RE.search(text)
        if extends_match:
            extends_by_path[path] = extends_match.group(1) or extends_match.group(2) or ""
        normalized = text.replace("\r\n", "\n").strip()
        if normalized:
            hashes[hashlib.sha256(normalized.encode("utf-8")).hexdigest()].append(relative)
        lines = line_count(text)
        if lines >= 650:
            large_files.append({"path": relative, "lines": lines})

    duplicate_classes = {
        name: paths for name, paths in sorted(class_locations.items()) if len(paths) > 1
    }
    exact_duplicate_scripts = [
        paths for paths in hashes.values() if len(paths) > 1
    ]
    exact_duplicate_scripts.sort(key=lambda group: group[0])

    combined_text = "\n".join(text_by_path.values())
    orphan_candidates: list[dict] = []
    thin_subclasses: list[dict] = []
    for path in scripts:
        relative = path.relative_to(root).as_posix()
        text = text_by_path[path]
        class_name = class_by_path.get(path, "")
        path_token = f"res://{relative}"
        path_references = combined_text.count(path_token) - text.count(path_token)
        class_references = 0
        if class_name:
            class_references = combined_text.count(class_name) - text.count(class_name)
        if path_references == 0 and class_references == 0:
            orphan_candidates.append({
                "path": relative,
                "class_name": class_name,
                "reason": "no path or class token reference outside the file",
            })
        nonblank = [
            line for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        function_count = len(re.findall(r"(?m)^\s*func\s+", text))
        if path in extends_by_path and len(nonblank) <= 36 and function_count <= 4:
            thin_subclasses.append({
                "path": relative,
                "class_name": class_name,
                "extends": extends_by_path[path],
                "nonblank_lines": len(nonblank),
                "functions": function_count,
            })

    result = {
        "summary": {
            "production_scripts": len(scripts),
            "test_scripts": len(tests),
            "class_names": len(class_locations),
            "duplicate_class_names": len(duplicate_classes),
            "exact_duplicate_groups": len(exact_duplicate_scripts),
            "orphan_candidates": len(orphan_candidates),
            "large_files": len(large_files),
            "thin_subclasses": len(thin_subclasses),
        },
        "hard_findings": {
            "duplicate_class_names": duplicate_classes,
            "exact_duplicate_scripts": exact_duplicate_scripts,
        },
        "review_findings": {
            "orphan_candidates": orphan_candidates,
            "large_files": sorted(large_files, key=lambda item: (-item["lines"], item["path"])),
            "thin_subclasses": thin_subclasses,
        },
        "removed_in_current_audit": [
            ".github/workflows/cleanup-nondefault-branches.yml",
        ],
        "policy": {
            "hard_findings_fail_ci": True,
            "orphan_candidates_require_manual_review": True,
            "quarantined_alpha_is_not_auto_deleted": True,
        },
    }
    return result


def markdown(result: dict) -> str:
    summary = result["summary"]
    lines = [
        "# Runtime code audit",
        "",
        "## Summary",
        "",
        f"- Production GDScript files: {summary['production_scripts']}",
        f"- Test GDScript files: {summary['test_scripts']}",
        f"- Duplicate class names: {summary['duplicate_class_names']}",
        f"- Exact duplicate script groups: {summary['exact_duplicate_groups']}",
        f"- Zero-reference candidates: {summary['orphan_candidates']}",
        f"- Files with at least 650 lines: {summary['large_files']}",
        f"- Thin subclass candidates: {summary['thin_subclasses']}",
        "",
        "## Deterministic hard findings",
        "",
    ]
    hard = result["hard_findings"]
    if not hard["duplicate_class_names"] and not hard["exact_duplicate_scripts"]:
        lines.append("No duplicate class declarations or byte-equivalent production scripts were found.")
    for name, paths in hard["duplicate_class_names"].items():
        lines.append(f"- Duplicate class `{name}`: {', '.join(paths)}")
    for group in hard["exact_duplicate_scripts"]:
        lines.append(f"- Exact duplicate scripts: {', '.join(group)}")
    lines += ["", "## Manual review candidates", ""]
    for item in result["review_findings"]["orphan_candidates"]:
        lines.append(f"- Zero-reference candidate: `{item['path']}` ({item['class_name'] or 'no class_name'})")
    for item in result["review_findings"]["thin_subclasses"]:
        lines.append(
            f"- Thin subclass: `{item['path']}` extends `{item['extends']}`; "
            f"{item['functions']} functions, {item['nonblank_lines']} nonblank lines"
        )
    lines += [
        "",
        "## Applied cleanup",
        "",
        "- Removed the one-time non-default branch cleanup workflow after its task completed.",
        "- Generated city shards and quarantined Alpha fixtures are excluded from automatic deletion.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    result = audit(args.root)
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.markdown_output:
        args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
        args.markdown_output.write_text(markdown(result), encoding="utf-8")
    print(json.dumps(result["summary"], ensure_ascii=False, sort_keys=True))
    hard = result["hard_findings"]
    if args.fail_on_hard_findings and (
        hard["duplicate_class_names"] or hard["exact_duplicate_scripts"]
    ):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
