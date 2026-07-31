#!/usr/bin/env python3
"""Static audit for GDScript structure, variable use and safe redundancy candidates."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

CLASS_RE = re.compile(r"(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")
EXTENDS_RE = re.compile(r"(?m)^\s*extends\s+(?:\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*))")
FUNCTION_RE = re.compile(
    r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("
)
VARIABLE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<kind>(?:@onready\s+)?var|const)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b"
)
IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
SPECIAL_NAME_RE = re.compile(
    r"(?:^|_)(?:legacy|compat|compatibility|temporary|temp|special|workaround|"
    r"hack|placeholder|dummy|migration|deprecated|oneoff|one_off)(?:_|$)",
    re.IGNORECASE,
)
SPECIAL_COMMENT_RE = re.compile(
    r"(?:legacy|compat(?:ibility)?|temporary|special|workaround|hack|placeholder|"
    r"dummy|migration|deprecated|one[- ]?off|旧|兼容|临时|特殊|例外|占位|迁移)",
    re.IGNORECASE,
)

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


def strip_comments_and_strings(text: str) -> str:
    """Replace comments and string contents while preserving lines and identifiers."""
    output: list[str] = []
    index = 0
    quote = ""
    triple = False
    while index < len(text):
        character = text[index]
        if quote:
            delimiter = quote * (3 if triple else 1)
            if text.startswith(delimiter, index):
                output.extend(" " * len(delimiter))
                index += len(delimiter)
                quote = ""
                triple = False
            elif character == "\\" and not triple and index + 1 < len(text):
                output.extend("  ")
                index += 2
            else:
                output.append("\n" if character == "\n" else " ")
                index += 1
            continue
        if character == "#":
            line_end = text.find("\n", index)
            if line_end == -1:
                output.extend(" " * (len(text) - index))
                break
            output.extend(" " * (line_end - index))
            index = line_end
            continue
        if character in {'"', "'"}:
            triple = text.startswith(character * 3, index)
            delimiter_length = 3 if triple else 1
            output.extend(" " * delimiter_length)
            index += delimiter_length
            quote = character
            continue
        output.append(character)
        index += 1
    return "".join(output)


def function_ranges(code_lines: list[str]) -> list[tuple[str, int, int]]:
    starts: list[tuple[str, int]] = []
    for line_number, line in enumerate(code_lines, start=1):
        match = FUNCTION_RE.match(line)
        if match:
            starts.append((match.group(1), line_number))
    output: list[tuple[str, int, int]] = []
    for index, (name, start) in enumerate(starts):
        end = starts[index + 1][1] - 1 if index + 1 < len(starts) else len(code_lines)
        output.append((name, start, end))
    return output


def nearest_comment(lines: list[str], declaration_index: int) -> str:
    comments: list[str] = []
    index = declaration_index - 1
    while index >= 0 and len(comments) < 3:
        stripped = lines[index].strip()
        if not stripped:
            if comments:
                break
            index -= 1
            continue
        if not stripped.startswith("#"):
            break
        comments.append(stripped.lstrip("#").strip())
        index -= 1
    inline = lines[declaration_index].split("#", 1)
    if len(inline) == 2:
        comments.insert(0, inline[1].strip())
    comments.reverse()
    return " ".join(comments)


def analyze_variables(path: Path, root: Path, text: str) -> list[dict]:
    original_lines = text.splitlines()
    code_lines = strip_comments_and_strings(text).splitlines()
    ranges = function_ranges(code_lines)
    declarations: list[dict] = []
    for line_number, code_line in enumerate(code_lines, start=1):
        match = VARIABLE_RE.match(code_line)
        if not match:
            continue
        name = match.group("name")
        indent = len(match.group("indent").replace("\t", "    "))
        function_name = ""
        scope_start = 1
        scope_end = len(code_lines)
        for candidate_name, candidate_start, candidate_end in ranges:
            if candidate_start <= line_number <= candidate_end:
                function_name = candidate_name
                scope_start = candidate_start
                scope_end = candidate_end
                break
        scope = "local" if function_name and indent > 0 else "member"
        if scope == "member":
            scope_start = 1
            scope_end = len(code_lines)
        scope_text = "\n".join(code_lines[scope_start - 1:scope_end])
        references = max(
            0,
            sum(1 for token in IDENTIFIER_RE.findall(scope_text) if token == name) - 1,
        )
        comment = nearest_comment(original_lines, line_number - 1)
        declarations.append({
            "path": path.relative_to(root).as_posix(),
            "line": line_number,
            "kind": "onready_var" if match.group("kind").startswith("@onready") else match.group("kind"),
            "name": name,
            "scope": scope,
            "function": function_name,
            "references_in_scope": references,
            "underscore_intentional": name.startswith("_"),
            "special_name": bool(SPECIAL_NAME_RE.search(name)),
            "special_comment": comment if SPECIAL_COMMENT_RE.search(comment) else "",
        })
    return declarations


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
    large_functions: list[dict] = []

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
        code_lines = strip_comments_and_strings(text).splitlines()
        for function_name, start, end in function_ranges(code_lines):
            function_lines = end - start + 1
            if function_lines >= 120:
                large_functions.append({
                    "path": relative,
                    "function": function_name,
                    "line": start,
                    "lines": function_lines,
                })

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
    variable_declarations: list[dict] = []
    for path in scripts:
        relative = path.relative_to(root).as_posix()
        text = text_by_path[path]
        variable_declarations.extend(analyze_variables(path, root, text))
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

    local_variables = [
        item for item in variable_declarations if item["scope"] == "local"
    ]
    unused_locals = [
        item for item in local_variables
        if item["references_in_scope"] == 0 and not item["underscore_intentional"]
    ]
    single_use_locals = [
        item for item in local_variables if item["references_in_scope"] == 1
    ]
    special_variables = [
        item for item in variable_declarations
        if item["special_name"] or item["special_comment"]
    ]
    low_use_by_path = Counter(
        item["path"] for item in unused_locals + single_use_locals
    )
    variable_usage_by_path: list[dict] = []
    declarations_by_path: dict[str, list[dict]] = defaultdict(list)
    for item in variable_declarations:
        declarations_by_path[item["path"]].append(item)
    for path, declarations in declarations_by_path.items():
        locals_in_path = [item for item in declarations if item["scope"] == "local"]
        singles_in_path = [
            item for item in locals_in_path if item["references_in_scope"] == 1
        ]
        variable_usage_by_path.append({
            "path": path,
            "declarations": len(declarations),
            "locals": len(locals_in_path),
            "single_use_locals": len(singles_in_path),
            "single_use_ratio": (
                round(len(singles_in_path) / len(locals_in_path), 4)
                if locals_in_path else 0.0
            ),
        })
    variable_usage_by_path.sort(
        key=lambda item: (-item["single_use_locals"], item["path"])
    )

    path_by_class = {
        class_name: path for path, class_name in class_by_path.items()
    }

    def parent_script(path: Path) -> Path | None:
        parent = extends_by_path.get(path, "")
        if parent.startswith("res://"):
            candidate = root / parent.removeprefix("res://")
            return candidate if candidate in extends_by_path or candidate in class_by_path else None
        return path_by_class.get(parent)

    inheritance_chains: list[dict] = []
    for path in scripts:
        chain: list[Path] = []
        visited: set[Path] = set()
        current: Path | None = path
        while current is not None and current not in visited:
            visited.add(current)
            chain.append(current)
            current = parent_script(current)
        if len(chain) >= 4:
            inheritance_chains.append({
                "path": path.relative_to(root).as_posix(),
                "depth": len(chain),
                "chain": [
                    item.relative_to(root).as_posix() for item in chain
                ],
                "cycle": current is not None,
            })
    inheritance_chains.sort(key=lambda item: (-item["depth"], item["path"]))

    result = {
        "summary": {
            "production_scripts": len(scripts),
            "test_scripts": len(tests),
            "class_names": len(class_locations),
            "duplicate_class_names": len(duplicate_classes),
            "exact_duplicate_groups": len(exact_duplicate_scripts),
            "orphan_candidates": len(orphan_candidates),
            "large_files": len(large_files),
            "large_functions": len(large_functions),
            "thin_subclasses": len(thin_subclasses),
            "deep_inheritance_chains": len(inheritance_chains),
            "maximum_inheritance_depth": (
                inheritance_chains[0]["depth"] if inheritance_chains else 0
            ),
            "variable_declarations": len(variable_declarations),
            "local_variables": len(local_variables),
            "unused_local_candidates": len(unused_locals),
            "single_use_local_variables": len(single_use_locals),
            "special_variable_candidates": len(special_variables),
        },
        "hard_findings": {
            "duplicate_class_names": duplicate_classes,
            "exact_duplicate_scripts": exact_duplicate_scripts,
        },
        "review_findings": {
            "orphan_candidates": orphan_candidates,
            "large_files": sorted(large_files, key=lambda item: (-item["lines"], item["path"])),
            "large_functions": sorted(
                large_functions,
                key=lambda item: (-item["lines"], item["path"], item["line"]),
            ),
            "thin_subclasses": thin_subclasses,
            "inheritance_chains": inheritance_chains,
            "unused_local_candidates": unused_locals,
            "single_use_local_variables": single_use_locals,
            "special_variable_candidates": special_variables,
            "low_use_variable_hotspots": [
                {"path": path, "count": count}
                for path, count in low_use_by_path.most_common()
            ],
            "variable_usage_by_path": variable_usage_by_path,
        },
        "policy": {
            "hard_findings_fail_ci": True,
            "orphan_candidates_require_manual_review": True,
            "low_use_variables_require_scope_aware_review": True,
            "special_names_are_not_automatically_redundant": True,
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
        f"- Functions with at least 120 lines: {summary['large_functions']}",
        f"- Thin subclass candidates: {summary['thin_subclasses']}",
        f"- Script inheritance chains at least 4 layers: {summary['deep_inheritance_chains']}",
        f"- Maximum script inheritance depth: {summary['maximum_inheritance_depth']}",
        f"- Variable declarations: {summary['variable_declarations']}",
        f"- Local variables: {summary['local_variables']}",
        f"- Unused local candidates: {summary['unused_local_candidates']}",
        f"- Single-use local variables: {summary['single_use_local_variables']}",
        f"- Special-name/comment variable candidates: {summary['special_variable_candidates']}",
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
    lines += ["", "### Large functions", ""]
    if not result["review_findings"]["large_functions"]:
        lines.append("- None.")
    for item in result["review_findings"]["large_functions"][:40]:
        lines.append(
            f"- `{item['path']}:{item['line']}` `{item['function']}`: "
            f"{item['lines']} lines"
        )
    lines += ["", "### Deep inheritance chains", ""]
    if not result["review_findings"]["inheritance_chains"]:
        lines.append("- None.")
    for item in result["review_findings"]["inheritance_chains"][:20]:
        lines.append(
            f"- Depth {item['depth']}: "
            + " -> ".join(f"`{path}`" for path in item["chain"])
        )
    lines += [
        "",
        "## Variable-use review",
        "",
    ]
    variable_findings = result["review_findings"]
    if not variable_findings["unused_local_candidates"]:
        lines.append("- No non-underscore local variable with zero in-scope references was found.")
    for item in variable_findings["unused_local_candidates"]:
        lines.append(
            f"- Unused local candidate: `{item['path']}:{item['line']}` "
            f"`{item['function']}.{item['name']}`"
        )
    lines += ["", "### Low-use hotspots", ""]
    for item in variable_findings["low_use_variable_hotspots"][:20]:
        lines.append(f"- `{item['path']}`: {item['count']}")
    lines += ["", "### Special-name or special-comment candidates", ""]
    if not variable_findings["special_variable_candidates"]:
        lines.append("- None.")
    for item in variable_findings["special_variable_candidates"][:80]:
        reason = "name" if item["special_name"] else "comment"
        lines.append(
            f"- `{item['path']}:{item['line']}` `{item['name']}` "
            f"({item['scope']}, {reason})"
        )
    lines += [
        "",
        "Single-use variables are review signals, not automatic deletion targets. "
        "A local alias can still preserve domain meaning, avoid repeated lookups or "
        "make an authoritative boundary explicit.",
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
