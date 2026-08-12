#!/usr/bin/env python3
from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
import json
import re
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

SOURCE_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".json", ".cfg"}
IGNORED_PARTS = {".git", ".godot", "builds", ".ci-godot"}

# The variable-state audit inventories runtime source/config inputs, not every
# text artifact in a checkout. Keep this boundary positive so a review export,
# fixture, or staging batch cannot become an input merely by using a supported
# file suffix. A new runtime data family must be added here when its loader is
# introduced; it must not be discovered implicitly from all of data/**.
RUNTIME_SOURCE_ROOTS = (
    "scripts",
    "scenes",
    "resources",
)
RUNTIME_CONFIG_ROOTS = (
    "data/alpha",
    "data/balance",
    "data/characters",
    "data/scenarios",
    "data/v2_2",
    "data/v2_3",
    "data/vnext",
    "data/world",
    "data/world_map",
)
RUNTIME_EXACT_FILES = ("project.godot",)
NON_AUTHORITATIVE_ROOTS = (
    "artifacts",
    "builds",
    "data/staging",
    "docs",
    "tests",
    "tools",
)
NON_AUTHORITATIVE_EXACT_FILES = ("export_presets.cfg",)
PRODUCTION_ROOTS = set(RUNTIME_SOURCE_ROOTS) | {"data", "resources"}
STATE_CONCEPTS: dict[str, tuple[str, ...]] = {
    "current_player": ("player", "current_player", "active_player"),
    "current_country": ("country", "polity", "nation", "sovereign"),
    "current_character": ("character", "person", "actor"),
    "date_speed_pause": ("hour", "date", "clock", "speed", "pause", "paused", "time"),
    "navigation_level": ("navigation", "space_level", "world_mode", "map_scope", "level"),
    "selected_object": ("selected", "selection"),
    "hovered_object": ("hover", "hovered"),
    "focused_object": ("focus", "focused"),
    "panel_window": ("panel", "window", "drawer", "workspace", "info_open", "expanded"),
    "map_zoom_camera": ("zoom", "camera", "yaw", "pitch", "rotation", "orbit"),
    "region_city": ("region", "city", "admin", "territory"),
    "event_message": ("event", "message", "notification", "intelligence", "inbox"),
    "game_mode_loading_save": ("game_mode", "mode", "loading", "loaded", "save", "slot", "schema"),
    "ui_visibility": ("visible", "displayed", "enabled", "open"),
}

MEMBER_RE = re.compile(
    r"^(?P<mods>(?:(?:static\s+)|(?:@\w+(?:\([^)]*\))?\s+))*)"
    r"(?P<kind>var|const)\s+"
    r"(?P<name>[A-Za-z_]\w*)"
    r"(?:\s*:\s*(?P<type>[^=:]+?))?"
    r"(?:\s*(?::=|=)\s*(?P<init>.*))?$"
)
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_]\w*)")
EXTENDS_RE = re.compile(r"^extends\s+(.+)$")
FUNC_RE = re.compile(r"^func\s+([A-Za-z_]\w*)")
STRING_KEY_PATTERNS = (
    re.compile(r"\.get\(\s*[\"']([^\"']+)[\"']"),
    re.compile(r"\.has\(\s*[\"']([^\"']+)[\"']"),
    re.compile(r"\[\s*[\"']([^\"']+)[\"']\s*\]"),
    re.compile(r"[\"']([^\"']+)[\"']\s*:"),
    re.compile(r"set\(\s*[\"']([^\"']+)[\"']"),
)
PERSISTENCE_FUNC_WORDS = (
    "persistent", "save", "load", "restore", "serialize", "deserialize",
    "migration", "schema", "snapshot", "store_var", "get_var",
)
MUTATING_METHODS = (
    "append", "append_array", "assign", "clear", "erase", "insert", "merge",
    "push_back", "push_front", "pop_back", "pop_front", "resize", "sort",
    "sort_custom", "shuffle", "fill",
)


@dataclass
class Member:
    name: str
    path: str
    line: int
    owner: str
    extends: str
    declaration_kind: str
    declared_type: str
    initializer: str
    annotations: list[str]
    is_static: bool
    is_export: bool
    is_onready: bool
    is_const: bool
    is_production: bool
    lifecycle: str
    category: str
    category_reason: str
    writer_count: int = 0
    reader_count: int = 0
    writer_files: list[str] | None = None
    reader_files: list[str] | None = None
    write_sites: list[str] | None = None
    read_sites: list[str] | None = None
    persisted_by_name: bool = False
    persistence_sites: list[str] | None = None
    string_key_count: int = 0
    derivation_candidate: bool = False
    cache_candidate: bool = False
    compatibility_candidate: bool = False
    ui_copy_candidate: bool = False
    unclear: bool = False


def iter_source_files(root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        if not path.is_file() or path.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        path_name = path.relative_to(root).as_posix()
        if any(part in IGNORED_PARTS for part in path_name.split("/")):
            continue
        if not is_discovery_path(path_name):
            continue
        yield path


def rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def root_name(path: str) -> str:
    return path.split("/", 1)[0]


def _is_path_under(path: str, root: str) -> bool:
    return path == root or path.startswith(root + "/")


def is_discovery_path(path: str) -> bool:
    """Return whether a repository-relative path belongs to the audit input."""
    normalized = path.replace("\\", "/").lstrip("./")
    if normalized in NON_AUTHORITATIVE_EXACT_FILES:
        return False
    if any(_is_path_under(normalized, root) for root in NON_AUTHORITATIVE_ROOTS):
        return False
    if normalized in RUNTIME_EXACT_FILES:
        return True
    return any(
        _is_path_under(normalized, root)
        for root in RUNTIME_SOURCE_ROOTS + RUNTIME_CONFIG_ROOTS
    )


def discovery_contract() -> dict[str, object]:
    return {
        "source_suffixes": sorted(SOURCE_SUFFIXES),
        "runtime_source_roots": list(RUNTIME_SOURCE_ROOTS),
        "runtime_config_roots": list(RUNTIME_CONFIG_ROOTS),
        "runtime_exact_files": list(RUNTIME_EXACT_FILES),
        "non_authoritative_roots": list(NON_AUTHORITATIVE_ROOTS),
        "non_authoritative_exact_files": list(NON_AUTHORITATIVE_EXACT_FILES),
    }


def is_production_path(path: str) -> bool:
    return root_name(path) in PRODUCTION_ROOTS and is_discovery_path(path)


def parse_autoloads(project_text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    section = ""
    for raw in project_text.splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section != "autoload" or not line or line.startswith(";"):
            continue
        if "=" not in line:
            continue
        name, value = line.split("=", 1)
        result[name.strip()] = value.strip().strip('"').lstrip("*")
    return result


def infer_lifecycle(path: str, extends: str, is_static: bool, autoload_paths: set[str]) -> str:
    resource_path = "res://" + path
    if is_static:
        return "process"
    if resource_path in autoload_paths:
        return "autoload/application"
    ext = extends.lower()
    if any(token in ext for token in ("control", "node", "scene")):
        return "scene/node"
    if any(token in ext for token in ("resource", "refcounted")):
        return "service/resource instance"
    return "instance/unclear"


def infer_category(
    *, name: str, declared_type: str, initializer: str, annotations: list[str],
    is_static: bool, is_const: bool, lifecycle: str,
) -> tuple[str, str, dict[str, bool]]:
    lower = name.lower()
    type_lower = declared_type.lower()
    init_lower = initializer.lower()
    joined_annotations = " ".join(annotations).lower()
    flags = {
        "derivation_candidate": False,
        "cache_candidate": False,
        "compatibility_candidate": False,
        "ui_copy_candidate": False,
        "unclear": False,
    }
    if is_const:
        return "C", "immutable constant", flags
    if "@onready" in joined_annotations:
        return "D", "onready node/resource reference", flags
    if "@export" in joined_annotations:
        if any(token in type_lower for token in ("node", "resource", "texture", "material", "packedscene")):
            return "D", "exported node/resource reference", flags
        return "B", "editor configuration", flags
    if any(token in lower for token in ("legacy", "compat", "deprecated", "alias")):
        flags["compatibility_candidate"] = True
        return "H", "name indicates compatibility state", flags
    if any(token in lower for token in ("migration", "migrated", "old_schema", "previous_schema")):
        flags["compatibility_candidate"] = True
        return "I", "name indicates migration-only state", flags
    if any(token in lower for token in ("cache", "cached", "memo", "prewarm")):
        flags["cache_candidate"] = True
        return "F", "name indicates cache; invalidation requires audit", flags
    if any(token in lower for token in (
        "displayed", "label_text", "panel_open", "info_open", "workspace_open",
        "drawer_open", "ui_", "screen_", "visible_",
    )):
        flags["ui_copy_candidate"] = True
        return "G", "name indicates UI presentation state or mirror", flags
    if any(token in lower for token in (
        "count", "summary", "report", "projected", "resolved", "computed", "bounds",
        "screen_polygons", "anchor", "display_name", "breadcrumb",
    )):
        flags["derivation_candidate"] = True
        return "E", "name indicates derived value; recomputation cost requires audit", flags
    if is_static or lifecycle == "autoload/application":
        return "A", "global/static writable state; owner requires verification", flags
    if init_lower in ("null", "{}", "[]", "", "false", "0", "0.0", "\"\""):
        flags["unclear"] = True
        return "K", "generic initialized member; semantics require writer audit", flags
    return "A", "candidate unique source pending writer audit", flags


def parse_members(
    root: Path, path: Path, text: str, autoload_paths: set[str],
) -> list[Member]:
    if path.suffix.lower() != ".gd":
        return []
    path_str = rel(root, path)
    owner = path.stem
    extends = ""
    pending_annotations: list[str] = []
    members: list[Member] = []
    for line_no, raw in enumerate(text.splitlines(), 1):
        if raw.startswith("\t") or raw.startswith(" "):
            pending_annotations.clear()
            continue
        stripped = raw.strip()
        class_match = CLASS_RE.match(stripped)
        if class_match:
            owner = class_match.group(1)
            continue
        extends_match = EXTENDS_RE.match(stripped)
        if extends_match:
            extends = extends_match.group(1).strip()
            continue
        if stripped.startswith("@") and " var " not in f" {stripped} " and not stripped.startswith("@onready var"):
            pending_annotations.append(stripped)
            continue
        match = MEMBER_RE.match(stripped)
        if not match:
            if stripped and not stripped.startswith("#"):
                pending_annotations.clear()
            continue
        mods = match.group("mods") or ""
        annotations = pending_annotations + re.findall(r"@\w+(?:\([^)]*\))?", mods)
        pending_annotations = []
        name = match.group("name")
        declared_type = (match.group("type") or "").strip()
        initializer = (match.group("init") or "").strip()
        is_static = "static" in mods.split()
        is_const = match.group("kind") == "const"
        lifecycle = infer_lifecycle(path_str, extends, is_static, autoload_paths)
        category, reason, flags = infer_category(
            name=name,
            declared_type=declared_type,
            initializer=initializer,
            annotations=annotations,
            is_static=is_static,
            is_const=is_const,
            lifecycle=lifecycle,
        )
        members.append(Member(
            name=name,
            path=path_str,
            line=line_no,
            owner=owner,
            extends=extends,
            declaration_kind=match.group("kind"),
            declared_type=declared_type,
            initializer=initializer,
            annotations=annotations,
            is_static=is_static,
            is_export=any(a.startswith("@export") for a in annotations),
            is_onready=any(a.startswith("@onready") for a in annotations),
            is_const=is_const,
            is_production=is_production_path(path_str),
            lifecycle=lifecycle,
            category=category,
            category_reason=reason,
            derivation_candidate=flags["derivation_candidate"],
            cache_candidate=flags["cache_candidate"],
            compatibility_candidate=flags["compatibility_candidate"],
            ui_copy_candidate=flags["ui_copy_candidate"],
            unclear=flags["unclear"],
        ))
    return members


def build_occurrence_index(text_by_path: dict[str, str]) -> tuple[dict[str, list[tuple[str, int, str]]], Counter[str], dict[str, list[str]]]:
    tokens: dict[str, list[tuple[str, int, str]]] = defaultdict(list)
    key_counts: Counter[str] = Counter()
    key_sites: dict[str, list[str]] = defaultdict(list)
    for path, text in text_by_path.items():
        for line_no, raw in enumerate(text.splitlines(), 1):
            stripped = raw.strip()
            for token in set(re.findall(r"\b[A-Za-z_]\w*\b", raw)):
                tokens[token].append((path, line_no, stripped))
            for pattern in STRING_KEY_PATTERNS:
                for key in pattern.findall(raw):
                    key_counts[key] += 1
                    if len(key_sites[key]) < 12:
                        key_sites[key].append(f"{path}:{line_no}: {stripped[:180]}")
    return tokens, key_counts, key_sites


def is_write_line(name: str, line: str) -> bool:
    escaped = re.escape(name)
    if re.search(rf"\b{escaped}\s*(?:\[[^\]]+\]\s*)?(?:=|\+=|-=|\*=|/=|%=|\|=|&=|\^=)", line):
        return True
    if re.search(rf"\.\s*{escaped}\s*=", line):
        return True
    if re.search(rf"set\(\s*[\"']{escaped}[\"']", line):
        return True
    methods = "|".join(MUTATING_METHODS)
    if re.search(rf"\b{escaped}\s*\.\s*(?:{methods})\s*\(", line):
        return True
    return False


def annotate_occurrences(
    members: list[Member], token_index: dict[str, list[tuple[str, int, str]]],
    key_counts: Counter[str], key_sites: dict[str, list[str]],
) -> None:
    for member in members:
        writes: list[tuple[str, int, str]] = []
        reads: list[tuple[str, int, str]] = []
        persistence_sites: list[str] = []
        for path, line_no, line in token_index.get(member.name, []):
            if path == member.path and line_no == member.line:
                continue
            target = writes if is_write_line(member.name, line) else reads
            target.append((path, line_no, line))
            lower = line.lower()
            if any(word in lower for word in PERSISTENCE_FUNC_WORDS):
                persistence_sites.append(f"{path}:{line_no}: {line[:180]}")
        member.writer_count = len(writes)
        member.reader_count = len(reads)
        member.writer_files = sorted({x[0] for x in writes})
        member.reader_files = sorted({x[0] for x in reads})
        member.write_sites = [f"{p}:{n}: {s[:180]}" for p, n, s in writes[:12]]
        member.read_sites = [f"{p}:{n}: {s[:180]}" for p, n, s in reads[:8]]
        member.string_key_count = key_counts.get(member.name, 0)
        if member.string_key_count:
            persistence_sites.extend(
                site for site in key_sites.get(member.name, [])
                if any(word in site.lower() for word in PERSISTENCE_FUNC_WORDS)
            )
        member.persistence_sites = list(dict.fromkeys(persistence_sites))[:16]
        member.persisted_by_name = bool(member.persistence_sites)


def declaration_metrics(members: list[Member], autoload_paths: set[str]) -> dict[str, int]:
    production = [m for m in members if m.is_production]
    writable = [m for m in production if not m.is_const and not m.is_onready]
    global_writable = [m for m in writable if m.is_static]
    autoload_writable = [m for m in writable if m.lifecycle == "autoload/application"]
    return {
        "member_fields_total": len(production),
        "writable_member_fields_total": len(writable),
        "global_writable_fields_total": len(global_writable),
        "autoload_writable_fields_total": len(autoload_writable),
        "persisted_member_fields_by_static_evidence": sum(m.persisted_by_name for m in writable),
        "compatibility_alias_candidates": sum(m.compatibility_candidate for m in writable),
        "ui_copy_candidates": sum(m.ui_copy_candidate for m in writable),
        "cache_candidates": sum(m.cache_candidate for m in writable),
        "derived_member_candidates": sum(m.derivation_candidate for m in writable),
        "unclear_member_fields": sum(m.unclear for m in writable),
        "autoload_entries": len(autoload_paths),
    }


def repeated_name_groups(members: list[Member]) -> list[dict[str, object]]:
    groups: dict[str, list[Member]] = defaultdict(list)
    for member in members:
        if member.is_production and not member.is_const and not member.is_onready:
            groups[member.name].append(member)
    result = []
    for name, group in groups.items():
        if len(group) < 2:
            continue
        result.append({
            "name": name,
            "count": len(group),
            "locations": [f"{m.path}:{m.line} ({m.owner})" for m in group],
            "warning": "same spelling only; semantic equivalence must be proven manually",
        })
    return sorted(result, key=lambda x: (-int(x["count"]), str(x["name"])))


def concept_inventory(members: list[Member]) -> dict[str, list[dict[str, object]]]:
    result: dict[str, list[dict[str, object]]] = {}
    for concept, needles in STATE_CONCEPTS.items():
        rows = []
        for member in members:
            if not member.is_production or member.is_const or member.is_onready:
                continue
            lower = member.name.lower()
            if any(needle in lower for needle in needles):
                rows.append({
                    "field": member.name,
                    "path": member.path,
                    "line": member.line,
                    "owner": member.owner,
                    "type": member.declared_type,
                    "lifecycle": member.lifecycle,
                    "writers": member.writer_count,
                    "writer_files": member.writer_files,
                    "persisted": member.persisted_by_name,
                    "category": member.category,
                })
        result[concept] = sorted(rows, key=lambda x: (str(x["path"]), int(x["line"])))
    return result


def detect_fallbacks(text_by_path: dict[str, str]) -> list[str]:
    findings: list[str] = []
    patterns = (
        re.compile(r"\.get\([^,]+,\s*(?:\{\}|\[\]|false|true|0(?:\.0)?|[\"']{2}|null)\s*\)"),
        re.compile(r"\bif\s+.*(?:is_empty|==\s*null|not\s+.*has).*"),
        re.compile(r"\breturn\s+(?:\{\}|\[\]|false|0(?:\.0)?|[\"']{2})\b"),
    )
    for path, text in text_by_path.items():
        if not is_production_path(path):
            continue
        for line_no, raw in enumerate(text.splitlines(), 1):
            stripped = raw.strip()
            if any(pattern.search(stripped) for pattern in patterns):
                findings.append(f"{path}:{line_no}: {stripped[:220]}")
    return findings


def detect_sync_functions(text_by_path: dict[str, str]) -> list[str]:
    findings: list[str] = []
    for path, text in text_by_path.items():
        if not path.endswith(".gd") or not is_production_path(path):
            continue
        for line_no, raw in enumerate(text.splitlines(), 1):
            match = FUNC_RE.match(raw.strip())
            if not match:
                continue
            name = match.group(1).lower()
            if any(token in name for token in ("sync", "mirror", "copy_state", "apply_state", "refresh_state")):
                findings.append(f"{path}:{line_no}: {raw.strip()}")
    return findings


def detect_state_containers(members: list[Member]) -> list[str]:
    findings = []
    for member in members:
        if not member.is_production or member.is_const or member.is_onready:
            continue
        type_lower = member.declared_type.lower()
        name_lower = member.name.lower()
        if "dictionary" in type_lower and any(token in name_lower for token in (
            "state", "data", "context", "payload", "snapshot", "document", "records",
        )):
            findings.append(f"{member.path}:{member.line}: {member.name}: {member.declared_type}")
    return findings


def write_markdown_inventory(
    output_dir: Path, members: list[Member], metrics: dict[str, int],
) -> None:
    rows = [m for m in members if m.is_production]
    lines = [
        "# Generated variable state inventory",
        "",
        "> Read-only static inventory. Categories are audit candidates, not automatic refactor decisions.",
        "",
        "## Metrics",
        "",
    ]
    for key, value in metrics.items():
        lines.append(f"- `{key}`: {value}")
    lines.extend([
        "",
        "## Member fields",
        "",
        "| Field | File | Owner | Type | Lifecycle | Writers | Readers | Persisted evidence | Category | Reason |",
        "|---|---|---|---|---|---:|---:|---|---|---|",
    ])
    for m in sorted(rows, key=lambda x: (x.path, x.line)):
        declared_type = m.declared_type.replace("|", "\\|") or "inferred"
        reason = m.category_reason.replace("|", "\\|")
        lines.append(
            f"| `{m.name}` | `{m.path}:{m.line}` | `{m.owner}` | `{declared_type}` | "
            f"{m.lifecycle} | {m.writer_count} | {m.reader_count} | "
            f"{'yes' if m.persisted_by_name else 'no'} | {m.category} | {reason} |"
        )
    (output_dir / "member_inventory.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", type=Path, required=True,
        help="explicit repository root to scan",
    )
    parser.add_argument(
        "--output-dir", type=Path,
        help="output directory; relative paths are resolved from --root",
    )
    return parser.parse_args()


def resolve_from_root(root: Path, path: Path) -> Path:
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    output_dir = (
        resolve_from_root(root, args.output_dir)
        if args.output_dir
        else root / "builds" / "variable-state-audit"
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    files = list(iter_source_files(root))
    text_by_path = {rel(root, path): read_text(path) for path in files}
    project_text = text_by_path.get("project.godot", "")
    autoloads = parse_autoloads(project_text)
    autoload_paths = set(autoloads.values())
    members: list[Member] = []
    for path in files:
        members.extend(
            parse_members(root, path, text_by_path[rel(root, path)], autoload_paths)
        )
    token_index, key_counts, key_sites = build_occurrence_index(text_by_path)
    annotate_occurrences(members, token_index, key_counts, key_sites)
    metrics = declaration_metrics(members, autoload_paths)
    fallbacks = detect_fallbacks(text_by_path)
    sync_functions = detect_sync_functions(text_by_path)
    state_containers = detect_state_containers(members)
    metrics.update({
        "dynamic_string_keys_unique": len(key_counts),
        "dynamic_string_key_occurrences": sum(key_counts.values()),
        "fallback_candidates": len(fallbacks),
        "sync_function_candidates": len(sync_functions),
        "generic_dictionary_state_container_candidates": len(state_containers),
        "source_files_scanned": len(files),
        "gdscript_files_scanned": sum(path.suffix.lower() == ".gd" for path in files),
    })

    payload = {
        "baseline_note": "static scan of checked-out commit",
        "discovery_contract": discovery_contract(),
        "autoloads": autoloads,
        "metrics": metrics,
        "members": [asdict(member) for member in members],
        "repeated_name_groups": repeated_name_groups(members),
        "concept_inventory": concept_inventory(members),
        "dynamic_string_keys": [
            {"key": key, "count": count, "sites": key_sites[key]}
            for key, count in key_counts.most_common()
        ],
        "fallback_candidates": fallbacks,
        "sync_function_candidates": sync_functions,
        "generic_dictionary_state_container_candidates": state_containers,
    }
    (output_dir / "variable_state_inventory.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output_dir / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output_dir / "repository_paths.txt").write_text(
        "\n".join(sorted(text_by_path)) + "\n", encoding="utf-8"
    )
    (output_dir / "fallback_candidates.txt").write_text(
        "\n".join(fallbacks) + "\n", encoding="utf-8"
    )
    (output_dir / "sync_function_candidates.txt").write_text(
        "\n".join(sync_functions) + "\n", encoding="utf-8"
    )
    write_markdown_inventory(output_dir, members, metrics)
    print(json.dumps(metrics, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
