#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict, deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

SCHEMA_VERSION = 1
EXPECTED_BASE_SHA = "db5556125a78a296045cb29c7cba18ff2438af96"
EXPECTED_FORMAL_TIME_CONTRACT_BLOB = "871d312cd0d8fa4370aa201ad7ac5a863684ab4d"

SCAN_SUFFIXES = {
    ".gd", ".tscn", ".tres", ".res", ".godot", ".json", ".cfg", ".ini",
    ".yml", ".yaml", ".py", ".ps1", ".sh", ".uid",
}
IGNORED_PARTS = {
    ".git", ".godot", ".ci-godot", "builds", "artifacts", "__pycache__",
    ".pytest_cache", ".mypy_cache",
}
PRODUCTION_PREFIXES = ("scripts/", "scenes/", "resources/", "data/")
TEST_PREFIX = "tests/"
WORKFLOW_PREFIX = ".github/workflows/"
TOOL_PREFIX = "tools/"

TOKEN_RE = re.compile(r"(?i)(?:v2[._ -]?3|v23)")
RES_PATH_RE = re.compile(r"res://[A-Za-z0-9_./@+\-]+")
REPO_PATH_RE = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"(?:project\.godot|export_presets\.cfg|"
    r"(?:scripts|scenes|resources|data|tests|tools|docs|\.github/workflows)/"
    r"[A-Za-z0-9_./@+\-]+\.(?:gd|tscn|tres|res|godot|json|cfg|ini|yml|yaml|py|ps1|sh|uid))"
)
CLASS_RE = re.compile(r"(?m)^\s*class_name\s+([A-Za-z_]\w*)")
EXTENDS_RE = re.compile(r"(?m)^\s*extends\s+([A-Za-z_]\w*|[\"'][^\"']+[\"'])")
UID_RE = re.compile(r"uid://[A-Za-z0-9]+")
MAIN_SCENE_RE = re.compile(r'(?m)^\s*run/main_scene\s*=\s*"([^"]+)"')
DYNAMIC_RE = re.compile(
    r"(?i)\b(?:load|preload|ResourceLoader\.load|ClassDB\.[A-Za-z_]+|"
    r"get_script|set_script|call|callv|instantiate)\s*\("
)
DEPRECATED_ENTRY_TOKENS = (
    "v2_3_life_loop_main", "v2_3_life_loop_menu", "v2_3_formal_main",
    "v2_3_player_interface", "scenes/v2_3/",
)
TIME_RESIDUAL_TOKENS = (
    "sim_year", "sim_month", "sim_day", "sim_hour", "sim_minute", "_advance_clock",
)
CLASS_LABELS = {
    "A": "正式产品直接依赖",
    "B": "正式产品间接依赖",
    "C": "Alpha 或 fixture 隔离依赖",
    "D": "非正式样机依赖",
    "E": "兼容边界",
    "F": "测试专用",
    "G": "无有效调用",
    "U": "无法确定",
}
RECOMMENDATIONS = {
    "A": "迁移到中性正式目录并改名",
    "B": "先建立行为基线，再迁移",
    "C": "保留并明确隔离",
    "D": "保留原型隔离或单独删除",
    "E": "保留边界，不作为运行期事实源",
    "F": "随被测服务迁移或删除",
    "G": "候选删除",
    "U": "补充动态加载、反射或生成路径证据后再分类",
}


@dataclass
class Node:
    path: str
    text: str
    resource_type: str
    class_names: list[str] = field(default_factory=list)
    references: set[str] = field(default_factory=set)
    dynamic_sites: list[str] = field(default_factory=list)


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def iter_scan_files(root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if any(part in IGNORED_PARTS for part in relative.parts):
            continue
        if path.suffix.lower() not in SCAN_SUFFIXES and path.name not in {"project.godot", "export_presets.cfg"}:
            continue
        yield path


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def resource_type(path: str) -> str:
    if path == "project.godot":
        return "project configuration"
    if path == "export_presets.cfg":
        return "export configuration"
    suffix = Path(path).suffix.lower()
    return {
        ".gd": "GDScript", ".tscn": "Godot scene", ".tres": "Godot text resource",
        ".res": "Godot resource", ".json": "JSON data/fixture", ".cfg": "configuration",
        ".ini": "configuration", ".yml": "workflow/configuration", ".yaml": "workflow/configuration",
        ".py": "Python tool/test", ".ps1": "PowerShell tool", ".sh": "shell tool",
        ".uid": "Godot UID sidecar", ".godot": "Godot configuration",
    }.get(suffix, suffix.lstrip(".") or "file")


def line_sites(path: str, text: str, pattern: re.Pattern[str]) -> list[str]:
    return [
        f"{path}:{number}: {line.strip()[:240]}"
        for number, line in enumerate(text.splitlines(), 1)
        if pattern.search(line)
    ]


def normalize_ref(raw: str, source: str, known_paths: set[str]) -> str | None:
    value = raw.strip().strip("\"'")
    if value.startswith("res://"):
        value = value[6:]
    value = value.split("#", 1)[0].split("?", 1)[0].rstrip("),];}'\"")
    if value in known_paths:
        return value
    if value.startswith(("./", "../")):
        candidate = (Path(source).parent / value).as_posix()
        parts: list[str] = []
        for part in candidate.split("/"):
            if part == "..":
                if parts:
                    parts.pop()
            elif part not in ("", "."):
                parts.append(part)
        candidate = "/".join(parts)
        if candidate in known_paths:
            return candidate
    return None


def build_nodes(root: Path) -> tuple[dict[str, Node], dict[str, str], dict[str, str]]:
    text_by_path: dict[str, str] = {}
    for path in iter_scan_files(root):
        path_str = rel(path, root)
        text_by_path[path_str] = path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")

    known_paths = set(text_by_path)
    class_to_path: dict[str, str] = {}
    uid_to_path: dict[str, str] = {}
    nodes: dict[str, Node] = {}
    for path, text in sorted(text_by_path.items()):
        classes = sorted(set(CLASS_RE.findall(text)))
        for class_name in classes:
            class_to_path.setdefault(class_name, path)
        for uid in UID_RE.findall(text):
            uid_to_path.setdefault(uid, path)
        if path.endswith(".uid"):
            token = text.strip()
            target = path[:-4]
            if token.startswith("uid://") and target in known_paths:
                uid_to_path[token] = target
        nodes[path] = Node(path, text, resource_type(path), classes)

    for path, node in sorted(nodes.items()):
        refs: set[str] = set()
        for match in RES_PATH_RE.findall(node.text):
            target = normalize_ref(match, path, known_paths)
            if target and target != path:
                refs.add(target)
        for match in REPO_PATH_RE.findall(node.text):
            target = normalize_ref(match, path, known_paths)
            if target and target != path:
                refs.add(target)
        for uid in UID_RE.findall(node.text):
            target = uid_to_path.get(uid)
            if target and target != path:
                refs.add(target)
        ext = EXTENDS_RE.search(node.text)
        if ext:
            value = ext.group(1).strip("\"'")
            target = normalize_ref(value, path, known_paths) or class_to_path.get(value)
            if target and target != path:
                refs.add(target)
        token_set = set(re.findall(r"\b[A-Za-z_]\w*\b", node.text))
        for class_name, target in class_to_path.items():
            if class_name in token_set and target != path:
                refs.add(target)
        node.references = refs
        node.dynamic_sites = [
            f"{path}:{number}: {line.strip()[:240]}"
            for number, line in enumerate(node.text.splitlines(), 1)
            if DYNAMIC_RE.search(line)
            and (
                TOKEN_RE.search(line)
                or ("load(" in line and not RES_PATH_RE.search(line))
                or ("preload(" in line and not RES_PATH_RE.search(line))
                or "ClassDB." in line
            )
        ]
    return nodes, class_to_path, uid_to_path


def project_main_scene(nodes: dict[str, Node], uid_to_path: dict[str, str]) -> str | None:
    project = nodes.get("project.godot")
    if not project:
        return None
    match = MAIN_SCENE_RE.search(project.text)
    if not match:
        return None
    raw = match.group(1)
    if raw.startswith("res://"):
        path = raw[6:]
        return path if path in nodes else None
    if raw.startswith("uid://"):
        return uid_to_path.get(raw)
    return raw if raw in nodes else None


def existing(nodes: dict[str, Node], *paths: str) -> set[str]:
    return {path for path in paths if path in nodes}


def prefixed(nodes: dict[str, Node], prefixes: tuple[str, ...]) -> set[str]:
    return {path for path in nodes if path.startswith(prefixes)}


def build_roots(nodes: dict[str, Node], main_scene: str | None) -> dict[str, set[str]]:
    formal_runtime = existing(
        nodes,
        "project.godot",
        "scenes/formal/formal_world_menu.tscn",
        "scenes/formal/formal_world_main.tscn",
        "scripts/formal/formal_world_menu.gd",
        "scripts/formal/formal_world_application.gd",
        "scripts/formal/formal_world_simulation.gd",
        "scripts/formal/formal_world_economy_service.gd",
        "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd",
    )
    if main_scene:
        formal_runtime.add(main_scene)
    formal_scene = {path for path in formal_runtime if path.endswith(".tscn") or path == "project.godot"}
    formal_save = existing(
        nodes,
        "scripts/formal/formal_world_application.gd",
        "scripts/formal/formal_world_simulation.gd",
        "scripts/formal/formal_world_economy_service.gd",
        "scripts/save/game_save_service.gd",
    )
    alpha = prefixed(nodes, ("scripts/alpha/", "tests/alpha/", "data/alpha/", "tests/fixtures/"))
    alpha |= existing(nodes, ".github/workflows/alpha-three-year-performance.yml")
    compatibility = {
        path for path in nodes
        if any(token in path.lower() for token in ("save", "migration", "compat", "fixture"))
    }
    compatibility |= {
        path for path, node in nodes.items()
        if any(token in node.text.lower() for token in ("schema_version", "save_version", "legacy", "migration"))
        and (path.startswith(TEST_PREFIX) or path.startswith(PRODUCTION_PREFIXES))
    }
    return {
        "formal_product": formal_runtime,
        "formal_scene": formal_scene,
        "formal_save": formal_save,
        "formal_long_term": existing(nodes, "tests/formal/formal_world_long_term_balance_test.gd"),
        "formal_integration": existing(nodes, "tests/formal/formal_world_integration_test.gd"),
        "alpha_fixture": alpha,
        "ui_spike": prefixed(nodes, ("scripts/ui_spikes/", "scenes/ui_spikes/", "shaders/ui_spikes/")),
        "tests": prefixed(nodes, ("tests/",)),
        "workflows": prefixed(nodes, (WORKFLOW_PREFIX,)),
        "compatibility": compatibility,
    }


def bfs_paths(roots: set[str], nodes: dict[str, Node]) -> tuple[dict[str, list[str]], dict[str, int]]:
    paths: dict[str, list[str]] = {}
    distances: dict[str, int] = {}
    queue: deque[str] = deque()
    for root in sorted(roots):
        if root in nodes:
            paths[root] = [root]
            distances[root] = 0
            queue.append(root)
    while queue:
        current = queue.popleft()
        for target in sorted(nodes[current].references):
            distance = distances[current] + 1
            candidate = paths[current] + [target]
            if target not in distances or distance < distances[target] or (distance == distances[target] and candidate < paths[target]):
                distances[target] = distance
                paths[target] = candidate
                queue.append(target)
    return paths, distances


def reverse_graph(nodes: dict[str, Node]) -> dict[str, set[str]]:
    reverse: dict[str, set[str]] = defaultdict(set)
    for source, node in nodes.items():
        for target in node.references:
            reverse[target].add(source)
    return reverse


def reverse_closure(start: str, reverse: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    queue = deque(sorted(reverse.get(start, set())))
    while queue:
        current = queue.popleft()
        if current in seen:
            continue
        seen.add(current)
        queue.extend(sorted(reverse.get(current, set()) - seen))
    return seen


def path_is_candidate(path: str, node: Node) -> bool:
    if TOKEN_RE.search(path) or any(TOKEN_RE.search(name) for name in node.class_names):
        return True
    if path.startswith(TEST_PREFIX) and TOKEN_RE.search(node.text):
        return True
    return path.startswith(("data/", "resources/")) and TOKEN_RE.search(node.text) is not None


def evidence_sites(path: str, nodes: dict[str, Node], reverse: dict[str, set[str]]) -> list[str]:
    node = nodes[path]
    terms = [re.escape("res://" + path), re.escape(path)] + [rf"\b{re.escape(name)}\b" for name in node.class_names]
    pattern = re.compile("|".join(terms))
    sites: list[str] = []
    for caller in sorted(reverse.get(path, set())):
        sites.extend(line_sites(caller, nodes[caller].text, pattern))
    return sorted(set(sites))


def classify(path: str, nodes: dict[str, Node], reverse: dict[str, set[str]], roots: dict[str, set[str]], reach: dict) -> tuple[str, str]:
    direct_formal = any(path in nodes[root].references for root in roots["formal_product"] if root in nodes)
    if direct_formal:
        return "A", "正式产品根节点直接加载、继承或调用"
    if path in reach["formal_product"][1] and reach["formal_product"][1][path] > 0:
        return "B", "从正式产品根节点经静态依赖图传递可达"
    if path.startswith(TEST_PREFIX):
        return "F", "文件本身位于测试树且没有正式运行时可达路径"
    if path in reach["compatibility"][0]:
        return "E", "仅从保存、迁移、旧配置或兼容验证根可达"
    if path in reach["alpha_fixture"][0]:
        return "C", "仅从 Alpha、fixture 或其门禁根可达"
    if path in reach["ui_spike"][0]:
        return "D", "仅从非正式 UI 样机或原型根可达"
    if path in reach["tests"][0]:
        return "F", "仅从测试根可达"
    incoming_dynamic = [
        site for node in nodes.values() for site in node.dynamic_sites
        if TOKEN_RE.search(site) and (path in node.text or any(name in node.text for name in nodes[path].class_names))
    ]
    if nodes[path].dynamic_sites or incoming_dynamic:
        return "U", "存在动态加载、反射或字符串构造证据，静态图无法闭合"
    if not reverse.get(path):
        return "G", "没有生产、场景、测试、工具、workflow、存档或动态加载引用"
    return "U", "存在静态调用者但无法归入已确认根集合"


def audit_repository(root: Path) -> dict:
    root = root.resolve()
    nodes, _, uid_to_path = build_nodes(root)
    main_scene = project_main_scene(nodes, uid_to_path)
    roots = build_roots(nodes, main_scene)
    reach = {name: bfs_paths(group, nodes) for name, group in roots.items()}
    reverse = reverse_graph(nodes)
    candidates = sorted(path for path, node in nodes.items() if path_is_candidate(path, node))
    entries: list[dict] = []
    for path in candidates:
        node = nodes[path]
        category, reason = classify(path, nodes, reverse, roots, reach)
        direct_callers = sorted(reverse.get(path, set()))
        ancestors = reverse_closure(path, reverse)
        dynamic = sorted(set(node.dynamic_sites + [
            site for caller in direct_callers for site in nodes[caller].dynamic_sites
            if TOKEN_RE.search(site) or path in site or any(name in site for name in node.class_names)
        ]))
        formal_path = reach["formal_product"][0].get(path, [])
        entries.append({
            "file_path": path,
            "class_names": node.class_names,
            "resource_type": node.resource_type,
            "direct_callers": direct_callers,
            "indirect_callers": sorted(ancestors - set(direct_callers)),
            "formal_reachable": bool(formal_path),
            "formal_paths": [formal_path] if formal_path else [],
            "formal_startup": bool(formal_path),
            "formal_tick": bool(formal_path) and any(
                token in "\n".join(nodes[p].text for p in formal_path if p in nodes).lower()
                for token in ("_on_clock_timer_timeout", "advance_minutes", "settle_hour_range", "_process(", "_physics_process(")
            ),
            "formal_economy": path in reach["formal_save"][0] and any("econom" in p.lower() for p in reach["formal_save"][0].get(path, [])),
            "formal_save_or_load": path in reach["formal_save"][0],
            "formal_hud_or_map": bool(formal_path) and any(
                token in p.lower() for p in formal_path for token in ("hud", "map", "hemisphere", "workspace")
            ),
            "formal_ten_year": path in reach["formal_long_term"][0],
            "alpha_three_year_gate": path in reach["alpha_fixture"][0],
            "alpha_only": category == "C",
            "fixture_only": category == "C" and ("fixture" in path.lower() or any("fixture" in caller.lower() for caller in direct_callers)),
            "test_only": category == "F",
            "ui_spike_only": category == "D",
            "compatibility_boundary": category == "E",
            "dynamic_loading_evidence": dynamic,
            "classification": category,
            "classification_label": CLASS_LABELS[category],
            "classification_reason": reason,
            "evidence_locations": evidence_sites(path, nodes, reverse),
            "recommendation": RECOMMENDATIONS[category],
            "confidence": "low" if category == "U" else ("medium" if dynamic else "high"),
        })

    category_counts = {key: sum(entry["classification"] == key for entry in entries) for key in CLASS_LABELS}
    deprecated_workflow_evidence: list[str] = []
    deprecated_pattern = re.compile("|".join(re.escape(token) for token in DEPRECATED_ENTRY_TOKENS), re.I)
    for path, node in sorted(nodes.items()):
        if path.startswith(WORKFLOW_PREFIX):
            deprecated_workflow_evidence.extend(line_sites(path, node.text, deprecated_pattern))

    old_150_evidence: list[str] = []
    perf_150_pattern = re.compile(r"(?i)(?:150.{0,80}(?:second|秒|performance|timeout)|(?:second|秒|performance|timeout).{0,80}150)")
    for path, node in sorted(nodes.items()):
        if path.startswith((TEST_PREFIX, WORKFLOW_PREFIX, TOOL_PREFIX)):
            old_150_evidence.extend(line_sites(path, node.text, perf_150_pattern))

    def token_status(token: str) -> dict:
        pattern = re.compile(re.escape(token), re.I)
        evidence: list[str] = []
        files: set[str] = set()
        for path, node in sorted(nodes.items()):
            sites = line_sites(path, node.text, pattern)
            if sites:
                evidence.extend(sites)
                files.add(path)
        return {
            "token": token,
            "files": sorted(files),
            "formal_reachable": any(path in reach["formal_product"][0] for path in files),
            "alpha_or_fixture_reachable": any(path in reach["alpha_fixture"][0] for path in files),
            "ui_spike_reachable": any(path in reach["ui_spike"][0] for path in files),
            "evidence": evidence,
        }

    standalone_paths = [
        "scenes/v2_3/v2_3_life_loop_main.tscn",
        "scenes/v2_3/v2_3_life_loop_menu.tscn",
        "scripts/v2_3/v2_3_life_loop_main.gd",
        "scripts/v2_3/v2_3_life_loop_menu.gd",
        "scripts/v2_3/v2_3_formal_main.gd",
        "scripts/v2_3/v2_3_player_interface.gd",
    ]
    export_text = nodes.get("export_presets.cfg", Node("", "", "")).text
    standalone_status = [{
        "path": path,
        "exists": path in nodes,
        "formal_reachable": path in reach["formal_product"][0],
        "workflow_referenced": any(
            path in node.text or Path(path).stem in node.text
            for candidate_path, node in nodes.items() if candidate_path.startswith(WORKFLOW_PREFIX)
        ),
        "export_referenced": path in export_text,
    } for path in standalone_paths]

    time_pattern = re.compile(r"\b(?:" + "|".join(map(re.escape, TIME_RESIDUAL_TOKENS)) + r")\b")
    time_residuals = sorted(set(
        site for entry in entries if entry["formal_reachable"]
        for site in line_sites(entry["file_path"], nodes[entry["file_path"]].text, time_pattern)
    ))
    contract_path = root / "tests/variable_state/formal_time_stable_contract_test.gd"
    contract_blob = git_blob_sha(contract_path.read_bytes()) if contract_path.exists() else None

    return {
        "schema_version": SCHEMA_VERSION,
        "fixed_base_sha": EXPECTED_BASE_SHA,
        "scan": {
            "source_file_count": len(nodes),
            "suffixes": sorted(SCAN_SUFFIXES),
            "ignored_parts": sorted(IGNORED_PARTS),
            "main_scene": main_scene,
            "documentation_is_evidence": False,
        },
        "formal_time_contract": {
            "path": "tests/variable_state/formal_time_stable_contract_test.gd",
            "expected_blob_sha": EXPECTED_FORMAL_TIME_CONTRACT_BLOB,
            "actual_blob_sha": contract_blob,
            "unchanged": contract_blob == EXPECTED_FORMAL_TIME_CONTRACT_BLOB,
        },
        "roots": {name: sorted(group) for name, group in roots.items()},
        "counts": {
            "v23_related_production_files": sum(path.startswith(PRODUCTION_PREFIXES) for path in candidates),
            "v23_related_test_files": sum(path.startswith(TEST_PREFIX) for path in candidates),
            "formal_direct_A": category_counts["A"],
            "formal_indirect_B": category_counts["B"],
            "alpha_fixture_C": category_counts["C"],
            "ui_spike_D": category_counts["D"],
            "compatibility_E": category_counts["E"],
            "test_only_F": category_counts["F"],
            "unused_G": category_counts["G"],
            "uncertain_U": category_counts["U"],
            "formal_scene_direct_paths": sum(
                any(path in nodes[root].references for root in roots["formal_scene"] if root in nodes)
                for path in candidates
            ),
            "formal_runtime_transitive_paths": sum(path in reach["formal_product"][0] for path in candidates),
            "formal_save_dependencies": sum(path in reach["formal_save"][0] for path in candidates),
            "formal_long_term_dependencies": sum(path in reach["formal_long_term"][0] for path in candidates),
            "deprecated_v23_product_workflow_gates": len({site.split(":", 1)[0] for site in deprecated_workflow_evidence}),
            "candidate_total": len(entries),
        },
        "candidates": entries,
        "special_checks": {
            "old_150_second_performance_test": {
                "evidence": sorted(set(old_150_evidence)),
                "recommendation": "若该测试只验证旧独立 V2.3 产品入口，应删除；若验证可复用服务性能，应改名并迁移到中性服务性能基线。",
            },
            "loran": token_status("Loran"),
            "vesta": token_status("Vesta"),
            "prototype_map": token_status("PrototypeMap"),
            "standalone_v23_entries": standalone_status,
            "windows_export": {
                "config_exists": "export_presets.cfg" in nodes,
                "deprecated_entry_references": sorted(
                    site for token in DEPRECATED_ENTRY_TOKENS
                    for site in line_sites("export_presets.cfg", export_text, re.compile(re.escape(token), re.I))
                ),
            },
            "deprecated_workflow_evidence": sorted(set(deprecated_workflow_evidence)),
            "d01_formal_time_residuals": time_residuals,
        },
        "static_analysis_limits": [
            "字符串拼接形成的资源路径只有在同一行保留 V2.3 标识时才能标记，无法必然解析到目标文件。",
            "ClassDB、反射、call/callv、运行时工厂和生成文件会记录为动态证据；没有闭合证据时分类为 U，不会擅自归入 G。",
            "文档引用单独统计，不作为生产依赖或可达性证据。",
            "静态图证明的是仓库内可见引用与根节点可达性，不证明运行时条件分支一定执行。",
        ],
    }


def render_markdown(audit: dict) -> str:
    counts = audit["counts"]
    lines = [
        "# V2.3 正式依赖清查", "",
        "本报告由 `tools/audit_formal_v23_dependencies.py` 从仓库内容确定性生成。文档引用不作为生产依赖证据；未实施任何生产服务迁移、重命名、删除或重构。",
        "", "## 基线与保护", "",
        f"- 固定 Base SHA：`{audit['fixed_base_sha']}`",
        f"- 默认启动场景：`{audit['scan']['main_scene'] or '未解析'}`",
        f"- 扫描文件数：{audit['scan']['source_file_count']}",
        f"- D01 稳定契约 blob：`{audit['formal_time_contract']['actual_blob_sha']}`",
        f"- 稳定契约保持不变：`{str(audit['formal_time_contract']['unchanged']).lower()}`",
        "", "## 分类数量", "", "|指标|数量|", "|---|---:|",
    ]
    metrics = [
        ("V2.3 相关生产文件", "v23_related_production_files"),
        ("V2.3 相关测试文件", "v23_related_test_files"),
        ("A 正式直接依赖", "formal_direct_A"), ("B 正式间接依赖", "formal_indirect_B"),
        ("C Alpha/fixture 隔离", "alpha_fixture_C"), ("D 非正式样机", "ui_spike_D"),
        ("E 兼容边界", "compatibility_E"), ("F 测试专用", "test_only_F"),
        ("G 无调用候选", "unused_G"), ("U 无法确定", "uncertain_U"),
        ("正式场景到 V2.3 的直接路径", "formal_scene_direct_paths"),
        ("正式运行时到 V2.3 的传递路径", "formal_runtime_transitive_paths"),
        ("正式保存路径中的 V2.3 依赖", "formal_save_dependencies"),
        ("正式长期模拟中的 V2.3 依赖", "formal_long_term_dependencies"),
        ("仍绑定弃用 V2.3 产品语义的 workflow 门禁", "deprecated_v23_product_workflow_gates"),
    ]
    lines.extend(f"|{label}|{counts[key]}|" for label, key in metrics)
    lines += ["", "## 正式产品根节点", ""]
    lines.extend(f"- `{root}`" for root in audit["roots"]["formal_product"])

    for category, label in CLASS_LABELS.items():
        entries = [entry for entry in audit["candidates"] if entry["classification"] == category]
        lines += ["", f"## {category}：{label}", ""]
        if not entries:
            lines.append("无。")
            continue
        lines += ["|文件|类|直接调用者|正式调用链|建议|置信度|", "|---|---|---|---|---|---|"]
        for entry in entries:
            classes = ", ".join(f"`{name}`" for name in entry["class_names"]) or "—"
            callers = "<br>".join(f"`{caller}`" for caller in entry["direct_callers"]) or "—"
            paths = "<br>".join(" → ".join(f"`{part}`" for part in path) for path in entry["formal_paths"]) or "—"
            lines.append(f"|`{entry['file_path']}`|{classes}|{callers}|{paths}|{entry['recommendation']}|{entry['confidence']}|")
            if category == "G":
                lines.append(f"\n无调用证据：`{entry['file_path']}` 的直接调用者、正式根可达路径、测试/工具/workflow/存档引用和动态加载证据均为空。")
            if category == "U":
                lines.append(f"\n待补证据：`{entry['file_path']}` — {entry['classification_reason']}。")

    checks = audit["special_checks"]
    lines += ["", "## 专项核对", "", "### 旧独立 150 秒性能测试", ""]
    evidence = checks["old_150_second_performance_test"]["evidence"]
    lines.extend(f"- `{site}`" for site in evidence)
    if not evidence:
        lines.append("- 未发现同时包含 150 秒语义与性能/超时语义的有效证据。")
    lines.append(f"- 建议：{checks['old_150_second_performance_test']['recommendation']}")
    for key, title in (("loran", "Loran"), ("vesta", "Vesta"), ("prototype_map", "PrototypeMap")):
        status = checks[key]
        lines += ["", f"### {title}", "",
            f"- 涉及文件：{len(status['files'])}",
            f"- 正式可达：`{str(status['formal_reachable']).lower()}`",
            f"- Alpha/fixture 可达：`{str(status['alpha_or_fixture_reachable']).lower()}`",
            f"- 非正式样机可达：`{str(status['ui_spike_reachable']).lower()}`",
        ]
        lines.extend(f"- `{site}`" for site in status["evidence"])
    lines += ["", "### 弃用入口、发布与 workflow", ""]
    for item in checks["standalone_v23_entries"]:
        lines.append(
            f"- `{item['path']}`：exists={str(item['exists']).lower()}, "
            f"formal_reachable={str(item['formal_reachable']).lower()}, "
            f"workflow_referenced={str(item['workflow_referenced']).lower()}, "
            f"export_referenced={str(item['export_referenced']).lower()}"
        )
    lines.append(f"- Windows 导出中的弃用入口引用：{len(checks['windows_export']['deprecated_entry_references'])}")
    lines.append(f"- workflow 中的弃用产品语义证据：{len(checks['deprecated_workflow_evidence'])}")
    lines.append(f"- D01 后正式可达 V2.3 时间镜像残余：{len(checks['d01_formal_time_residuals'])}")
    lines.extend(f"- `{site}`" for site in checks["d01_formal_time_residuals"])
    lines += ["", "## 静态分析限制", ""]
    lines.extend(f"- {item}" for item in audit["static_analysis_limits"])
    lines += ["", "## 下一步边界", "",
        "下一 PR 只能根据本清单实施 `V2.3 通用服务迁移与无调用内容清理`。A/B 项先迁移并保持行为基线；C/D/E 项继续隔离；G 项在再次确认无动态证据后删除；U 项必须先补齐证据。本 PR 不实施这些修改。", ""]
    return "\n".join(lines)


def serialize_json(audit: dict) -> str:
    return json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def write_or_check(root: Path, audit: dict, check: bool) -> int:
    targets = {
        root / "docs/refactors/formal_v23_dependency_inventory.json": serialize_json(audit),
        root / "docs/refactors/formal_v23_dependency_audit.md": render_markdown(audit),
    }
    failures: list[str] = []
    for path, expected in targets.items():
        if check:
            actual = path.read_text(encoding="utf-8") if path.exists() else None
            if actual != expected:
                failures.append(path.relative_to(root).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(expected, encoding="utf-8", newline="\n")
    if failures:
        print("Out-of-date formal V2.3 dependency artifacts:", file=sys.stderr)
        for path in failures:
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit retained V2.3 dependencies from formal product roots.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--print-summary", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    audit = audit_repository(args.root)
    if not audit["formal_time_contract"]["unchanged"]:
        print(
            "D01 formal-time stable contract blob changed: "
            f"expected {EXPECTED_FORMAL_TIME_CONTRACT_BLOB}, got {audit['formal_time_contract']['actual_blob_sha']}",
            file=sys.stderr,
        )
        return 2
    if args.print_summary:
        print(json.dumps(audit["counts"], ensure_ascii=False, sort_keys=True))
    return write_or_check(args.root.resolve(), audit, check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
