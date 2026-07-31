#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import deque
from pathlib import Path

import audit_formal_v23_dependencies as engine

V23_PREFIXES = (
    "scripts/v2_3/",
    "scenes/v2_3/",
    "resources/v2_3/",
    "data/v2_3/",
    "tests/v2_3/",
    "tools/v2_3/",
)
RELATED_PREFIXES = ("scripts/", "scenes/", "resources/", "data/", "tests/", "tools/")
EXCLUDED_PATHS = {
    "tools/audit_formal_v23_dependencies.py",
    "tools/generate_formal_v23_dependency_audit.py",
    "tests/tools/test_audit_formal_v23_dependencies.py",
    "tests/tools/test_generate_formal_v23_dependency_audit.py",
    ".github/workflows/formal-v23-dependency-audit.yml",
    "docs/refactors/formal_v23_dependency_audit.md",
    "docs/refactors/formal_v23_dependency_inventory.json",
}
COMPAT_RE = re.compile(r"(?i)(?:^|[/_])(save|migration|legacy|compat)(?:[/_.]|$)")
PERF_150_RE = re.compile(
    r"(?i)(?:150.{0,100}(?:second|秒|three.?year|performance)|"
    r"(?:second|秒|three.?year|performance).{0,100}150)"
)


def reverse_graph(nodes: dict[str, engine.Node]) -> dict[str, set[str]]:
    reverse: dict[str, set[str]] = {}
    for source, node in nodes.items():
        for target in node.references:
            reverse.setdefault(target, set()).add(source)
    return reverse


def reverse_closure(path: str, reverse: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    queue: deque[str] = deque(sorted(reverse.get(path, set())))
    while queue:
        current = queue.popleft()
        if current in seen:
            continue
        seen.add(current)
        queue.extend(sorted(reverse.get(current, set()) - seen))
    return seen


def candidate_paths(nodes: dict[str, engine.Node]) -> list[str]:
    v23_targets = {path for path in nodes if path.startswith(V23_PREFIXES) and not path.endswith(".uid")}
    candidates: set[str] = set(v23_targets)
    for path, node in nodes.items():
        if path.endswith(".uid") or path in EXCLUDED_PATHS or not path.startswith(RELATED_PREFIXES):
            continue
        if engine.TOKEN_RE.search(path) or any(engine.TOKEN_RE.search(name) for name in node.class_names):
            candidates.add(path)
            continue
        if path.startswith("tests/") and node.references.intersection(v23_targets):
            candidates.add(path)
    return sorted(candidates - EXCLUDED_PATHS)


def incoming_dynamic_sites(
    path: str,
    node: engine.Node,
    nodes: dict[str, engine.Node],
) -> list[str]:
    terms = ["res://" + path, path, *node.class_names]
    sites: list[str] = []
    for caller_path, caller in sorted(nodes.items()):
        if caller_path.startswith("docs/") or caller_path in EXCLUDED_PATHS:
            continue
        for number, line in enumerate(caller.text.splitlines(), 1):
            if not engine.DYNAMIC_RE.search(line):
                continue
            if any(term and term in line for term in terms):
                sites.append(f"{caller_path}:{number}: {line.strip()[:240]}")
    return sorted(set(sites))


def clean_paths(paths: set[str] | list[str]) -> list[str]:
    return sorted(
        path for path in set(paths)
        if not path.endswith(".uid")
        and not path.startswith("docs/")
        and path not in EXCLUDED_PATHS
    )


def candidate_evidence(
    path: str,
    node: engine.Node,
    nodes: dict[str, engine.Node],
    reverse: dict[str, set[str]],
) -> list[str]:
    terms = [re.escape("res://" + path), re.escape(path)]
    terms.extend(rf"\b{re.escape(name)}\b" for name in node.class_names)
    pattern = re.compile("|".join(terms))
    sites: list[str] = []
    for caller in sorted(reverse.get(path, set())):
        sites.extend(engine.line_sites(caller, nodes[caller].text, pattern))
    return sorted(set(sites))


def classify(
    path: str,
    node: engine.Node,
    nodes: dict[str, engine.Node],
    reverse: dict[str, set[str]],
    roots: dict[str, set[str]],
    reach: dict,
    dynamic_sites: list[str],
) -> tuple[str, str]:
    direct_formal = any(path in nodes[root].references for root in roots["formal_product"] if root in nodes)
    if direct_formal:
        return "A", "正式产品根节点直接加载、继承或调用"
    if path in reach["formal_product"][1] and reach["formal_product"][1][path] > 0:
        return "B", "从正式产品根节点经静态依赖图传递可达"
    if path.startswith("tests/"):
        return "F", "文件本身是测试或测试辅助，未进入正式运行时"
    compat_subject = " ".join([path, *node.class_names])
    if COMPAT_RE.search(compat_subject):
        return "E", "文件自身明确属于保存、迁移、旧格式或兼容边界"
    if path in reach["alpha_fixture"][0]:
        return "C", "仅从 Alpha、fixture 或 Alpha 门禁根可达"
    if path in reach["ui_spike"][0]:
        return "D", "仅从非正式 UI 样机或原型根可达"
    callers = clean_paths(reverse.get(path, set()))
    if path.startswith("tools/") or path in reach["tests"][0] or (
        callers and all(caller.startswith(("tests/", "tools/", ".github/workflows/")) for caller in callers)
    ):
        return "F", "仅由测试、测试工具或测试 workflow 使用"
    if dynamic_sites:
        return "U", "存在指向该候选的动态加载、反射或字符串调用证据，静态图无法闭合"
    if not callers:
        return "G", "没有生产、场景、测试、工具、workflow、存档或动态加载证据"
    return "U", "存在未归属于正式、Alpha、样机、兼容或测试根的静态调用者"


def token_status(token: str, nodes: dict[str, engine.Node], reach: dict) -> dict:
    pattern = re.compile(re.escape(token), re.I)
    files: set[str] = set()
    evidence: list[str] = []
    for path, node in sorted(nodes.items()):
        if path.startswith("docs/") or path in EXCLUDED_PATHS:
            continue
        sites = engine.line_sites(path, node.text, pattern)
        if sites:
            files.add(path)
            evidence.extend(sites)
    production_files = sorted(path for path in files if path.startswith(engine.PRODUCTION_PREFIXES))
    formal_files = sorted(path for path in production_files if path in reach["formal_product"][0])
    alpha_files = sorted(path for path in production_files if path in reach["alpha_fixture"][0])
    ui_files = sorted(path for path in production_files if path in reach["ui_spike"][0])
    return {
        "token": token,
        "files": sorted(files),
        "production_files": production_files,
        "formal_reachable_files": formal_files,
        "alpha_or_fixture_files": alpha_files,
        "ui_spike_files": ui_files,
        "formal_reachable": bool(formal_files),
        "alpha_or_fixture_reachable": bool(alpha_files),
        "ui_spike_reachable": bool(ui_files),
        "evidence": sorted(set(evidence)),
    }


def build_audit(root: Path) -> dict:
    root = root.resolve()
    nodes, _, uid_to_path = engine.build_nodes(root)
    main_scene = engine.project_main_scene(nodes, uid_to_path)
    roots = engine.build_roots(nodes, main_scene)
    reach = {name: engine.bfs_paths(group, nodes) for name, group in roots.items()}
    reverse = reverse_graph(nodes)
    paths = candidate_paths(nodes)
    entries: list[dict] = []

    for path in paths:
        node = nodes[path]
        dynamic_sites = incoming_dynamic_sites(path, node, nodes)
        category, reason = classify(path, node, nodes, reverse, roots, reach, dynamic_sites)
        direct_callers = clean_paths(reverse.get(path, set()))
        indirect_callers = clean_paths(reverse_closure(path, reverse) - set(direct_callers))
        formal_path = reach["formal_product"][0].get(path, [])
        evidence = [
            site for site in candidate_evidence(path, node, nodes, reverse)
            if not site.startswith(tuple(EXCLUDED_PATHS)) and ".uid:" not in site
        ]
        entries.append({
            "file_path": path,
            "class_names": node.class_names,
            "resource_type": node.resource_type,
            "direct_callers": direct_callers,
            "indirect_callers": indirect_callers,
            "formal_reachable": bool(formal_path),
            "formal_paths": [formal_path] if formal_path else [],
            "formal_startup": bool(formal_path),
            "formal_tick": bool(formal_path) and any(
                token in "\n".join(nodes[p].text for p in formal_path if p in nodes).lower()
                for token in ("_on_clock_timer_timeout", "advance_minutes", "settle_hour_range", "_process(", "_physics_process(")
            ),
            "formal_economy": path in reach["formal_save"][0] and any(
                "econom" in item.lower() for item in reach["formal_save"][0].get(path, [])
            ),
            "formal_save_or_load": path in reach["formal_save"][0],
            "formal_hud_or_map": bool(formal_path) and any(
                token in item.lower()
                for item in formal_path
                for token in ("hud", "map", "hemisphere", "workspace")
            ),
            "formal_ten_year": path in reach["formal_long_term"][0],
            "alpha_three_year_gate": path in reach["alpha_fixture"][0],
            "alpha_only": category == "C",
            "fixture_only": category == "C" and (
                "fixture" in path.lower() or any("fixture" in caller.lower() for caller in direct_callers)
            ),
            "test_only": category == "F",
            "ui_spike_only": category == "D",
            "compatibility_boundary": category == "E",
            "dynamic_loading_evidence": dynamic_sites,
            "classification": category,
            "classification_label": engine.CLASS_LABELS[category],
            "classification_reason": reason,
            "evidence_locations": sorted(set(evidence)),
            "recommendation": engine.RECOMMENDATIONS[category],
            "confidence": "low" if category == "U" else "high",
        })

    counts_by_category = {
        key: sum(item["classification"] == key for item in entries)
        for key in engine.CLASS_LABELS
    }
    deprecated_pattern = re.compile(
        "|".join(re.escape(token) for token in engine.DEPRECATED_ENTRY_TOKENS), re.I
    )
    deprecated_workflow_evidence: list[str] = []
    for path, node in sorted(nodes.items()):
        if path.startswith(engine.WORKFLOW_PREFIX) and path not in EXCLUDED_PATHS:
            deprecated_workflow_evidence.extend(engine.line_sites(path, node.text, deprecated_pattern))

    old_150_evidence: list[str] = []
    other_150_timeouts: list[str] = []
    for path, node in sorted(nodes.items()):
        if path.startswith("tests/"):
            old_150_evidence.extend(engine.line_sites(path, node.text, PERF_150_RE))
        elif path.startswith(engine.WORKFLOW_PREFIX):
            other_150_timeouts.extend(
                engine.line_sites(path, node.text, re.compile(r"(?i)timeout.{0,40}150s|150s.{0,40}timeout"))
            )

    standalone_paths = [
        "scenes/v2_3/v2_3_life_loop_main.tscn",
        "scenes/v2_3/v2_3_life_loop_menu.tscn",
        "scripts/v2_3/v2_3_life_loop_main.gd",
        "scripts/v2_3/v2_3_life_loop_menu.gd",
        "scripts/v2_3/v2_3_formal_main.gd",
        "scripts/v2_3/v2_3_player_interface.gd",
    ]
    export_text = nodes.get("export_presets.cfg", engine.Node("", "", "")).text
    standalone = [{
        "path": path,
        "exists": path in nodes,
        "formal_reachable": path in reach["formal_product"][0],
        "workflow_referenced": any(
            path in node.text or Path(path).stem in node.text
            for caller, node in nodes.items()
            if caller.startswith(engine.WORKFLOW_PREFIX) and caller not in EXCLUDED_PATHS
        ),
        "export_referenced": path in export_text,
    } for path in standalone_paths]

    time_pattern = re.compile(r"\b(?:" + "|".join(map(re.escape, engine.TIME_RESIDUAL_TOKENS)) + r")\b")
    time_residuals = sorted(set(
        site
        for entry in entries
        if entry["formal_reachable"]
        for site in engine.line_sites(entry["file_path"], nodes[entry["file_path"]].text, time_pattern)
    ))
    contract_path = root / "tests/variable_state/formal_time_stable_contract_test.gd"
    contract_blob = engine.git_blob_sha(contract_path.read_bytes()) if contract_path.exists() else None

    return {
        "schema_version": engine.SCHEMA_VERSION,
        "fixed_base_sha": engine.EXPECTED_BASE_SHA,
        "scan": {
            "source_file_count": len(nodes),
            "suffixes": sorted(engine.SCAN_SUFFIXES),
            "ignored_parts": sorted(engine.IGNORED_PARTS),
            "main_scene": main_scene,
            "documentation_is_evidence": False,
            "candidate_rule": "V2.3 directories, V2.3/V23-named definitions, and tests with direct static references to those definitions; .uid sidecars and the audit implementation itself are excluded.",
        },
        "formal_time_contract": {
            "path": "tests/variable_state/formal_time_stable_contract_test.gd",
            "expected_blob_sha": engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB,
            "actual_blob_sha": contract_blob,
            "unchanged": contract_blob == engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB,
        },
        "roots": {name: sorted(group) for name, group in roots.items()},
        "counts": {
            "v23_related_production_files": sum(
                item["file_path"].startswith(engine.PRODUCTION_PREFIXES) for item in entries
            ),
            "v23_related_test_files": sum(item["file_path"].startswith("tests/") for item in entries),
            "formal_direct_A": counts_by_category["A"],
            "formal_indirect_B": counts_by_category["B"],
            "alpha_fixture_C": counts_by_category["C"],
            "ui_spike_D": counts_by_category["D"],
            "compatibility_E": counts_by_category["E"],
            "test_only_F": counts_by_category["F"],
            "unused_G": counts_by_category["G"],
            "uncertain_U": counts_by_category["U"],
            "formal_scene_direct_paths": sum(
                any(item["file_path"] in nodes[root].references for root in roots["formal_scene"] if root in nodes)
                for item in entries
            ),
            "formal_runtime_transitive_paths": sum(item["formal_reachable"] for item in entries),
            "formal_save_dependencies": sum(item["formal_save_or_load"] for item in entries),
            "formal_long_term_dependencies": sum(item["formal_ten_year"] for item in entries),
            "deprecated_v23_product_workflow_gates": len({
                site.split(":", 1)[0] for site in deprecated_workflow_evidence
            }),
            "candidate_total": len(entries),
        },
        "candidates": entries,
        "special_checks": {
            "old_150_second_performance_test": {
                "evidence": sorted(set(old_150_evidence)),
                "other_150_second_workflow_timeouts": sorted(set(other_150_timeouts)),
                "recommendation": "旧 `alpha_three_year_performance_test.gd` 不应继续作为独立产品门禁；保留同跑者 Base/Head 五轮门禁作为权威性能验收，并在下一清理 PR 删除或改名该旧测试。",
            },
            "loran": token_status("Loran", nodes, reach),
            "vesta": token_status("Vesta", nodes, reach),
            "prototype_map": token_status("PrototypeMap", nodes, reach),
            "standalone_v23_entries": standalone,
            "windows_export": {
                "config_exists": "export_presets.cfg" in nodes,
                "deprecated_entry_references": sorted(
                    site
                    for token in engine.DEPRECATED_ENTRY_TOKENS
                    for site in engine.line_sites(
                        "export_presets.cfg", export_text, re.compile(re.escape(token), re.I)
                    )
                ),
            },
            "deprecated_workflow_evidence": sorted(set(deprecated_workflow_evidence)),
            "d01_formal_time_residuals": time_residuals,
        },
        "static_analysis_limits": [
            "字符串拼接形成的资源路径只有在同一行保留候选路径或类名时才能归因。",
            "ClassDB、反射、call/callv、运行时工厂和生成文件只作为动态证据；未闭合时分类为 U，不会归入 G。",
            "文档、审计器自身和 .uid sidecar 不作为候选或生产依赖证据。",
            "静态可达性不证明运行时条件分支一定执行；A/B 仍需行为基线保护后迁移。",
        ],
    }


def render_markdown(audit: dict) -> str:
    text = engine.render_markdown(audit)
    return text.replace(
        "本报告由 `tools/audit_formal_v23_dependencies.py` 从仓库内容确定性生成。",
        "本报告由 `tools/audit_formal_v23_dependencies.py` 扫描依赖图，并由 `tools/generate_formal_v23_dependency_audit.py` 应用严格候选与分类规则后确定性生成。",
    )


def write_or_check(root: Path, audit: dict, check: bool) -> int:
    targets = {
        root / "docs/refactors/formal_v23_dependency_inventory.json": engine.serialize_json(audit),
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
    parser = argparse.ArgumentParser(description="Generate the strict formal V2.3 dependency audit.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--print-summary", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    audit = build_audit(args.root)
    if not audit["formal_time_contract"]["unchanged"]:
        print(
            "D01 formal-time stable contract blob changed: "
            f"expected {engine.EXPECTED_FORMAL_TIME_CONTRACT_BLOB}, got {audit['formal_time_contract']['actual_blob_sha']}",
            file=sys.stderr,
        )
        return 2
    if args.print_summary:
        print(json.dumps(audit["counts"], ensure_ascii=False, sort_keys=True))
    return write_or_check(args.root.resolve(), audit, check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
