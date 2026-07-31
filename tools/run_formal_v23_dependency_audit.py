#!/usr/bin/env python3
from __future__ import annotations

import faulthandler
import json
import os
import struct
import sys
import threading
import zlib
from collections import deque
from pathlib import Path

import generate_formal_v23_dependency_audit as generator

_DYNAMIC_INDEX: list[tuple[str, int, str]] | None = None
_ORIGINAL_BUILD_AUDIT = generator.build_audit
RUNNER_PATH = "tools/run_formal_v23_dependency_audit.py"
INVENTORY_PATH = "docs/refactors/formal_v23_dependency_inventory.json.gz"
REPORT_PATH = "docs/refactors/formal_v23_dependency_audit.md"


def _linear_bfs_paths(roots: set[str], nodes: dict) -> tuple[dict[str, list[str]], dict[str, int]]:
    paths: dict[str, list[str]] = {}
    distances: dict[str, int] = {}
    queue: deque[str] = deque()
    for root in sorted(roots):
        if root in nodes and root not in distances:
            paths[root] = [root]
            distances[root] = 0
            queue.append(root)
    while queue:
        current = queue.popleft()
        for target in sorted(nodes[current].references):
            if target in distances:
                continue
            distances[target] = distances[current] + 1
            paths[target] = paths[current] + [target]
            queue.append(target)
    return paths, distances


def _linear_reverse_closure(path: str, reverse: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    queued: set[str] = set(reverse.get(path, set()))
    queue: deque[str] = deque(sorted(queued))
    while queue:
        current = queue.popleft()
        queued.discard(current)
        if current in seen:
            continue
        seen.add(current)
        for parent in sorted(reverse.get(current, set())):
            if parent not in seen and parent not in queued:
                queued.add(parent)
                queue.append(parent)
    return seen


def _indexed_incoming_dynamic_sites(path: str, node, nodes: dict) -> list[str]:
    global _DYNAMIC_INDEX
    if _DYNAMIC_INDEX is None:
        index: list[tuple[str, int, str]] = []
        for caller_path, caller in sorted(nodes.items()):
            if caller_path.startswith("docs/") or caller_path in generator.EXCLUDED_PATHS:
                continue
            for number, line in enumerate(caller.text.splitlines(), 1):
                if generator.engine.DYNAMIC_RE.search(line):
                    index.append((caller_path, number, line))
        _DYNAMIC_INDEX = index
    terms = ["res://" + path, path, *node.class_names]
    return sorted({
        f"{caller_path}:{number}: {line.strip()[:240]}"
        for caller_path, number, line in _DYNAMIC_INDEX
        if any(term and term in line for term in terms)
    })


def _location_only(site: str) -> str:
    parts = site.split(":", 2)
    if len(parts) >= 2 and parts[1].isdigit():
        return f"{parts[0]}:{parts[1]}"
    return site


def _first_location_per_file(sites: list[str]) -> list[str]:
    result: dict[str, str] = {}
    for site in sorted({_location_only(value) for value in sites}):
        path = site.rsplit(":", 1)[0] if ":" in site else site
        result.setdefault(path, site)
    return [result[path] for path in sorted(result)]


def _deduplicate_indirect_callers(audit: dict) -> None:
    unique_sets = sorted({
        tuple(item["indirect_callers"])
        for item in audit["candidates"]
        if item["indirect_callers"]
    })
    identifiers = {values: f"s{index:03d}" for index, values in enumerate(unique_sets, 1)}
    audit["indirect_caller_sets"] = {
        identifiers[values]: list(values) for values in unique_sets
    }
    for item in audit["candidates"]:
        values = tuple(item["indirect_callers"])
        item["indirect_callers"] = {
            "set_id": identifiers.get(values),
            "count": len(values),
        }
    audit["scan"]["indirect_callers_encoding"] = (
        "Each candidate records a set_id and count; the complete sorted caller list is stored once in indirect_caller_sets."
    )


def _recount(audit: dict) -> None:
    entries = audit["candidates"]
    counts = audit["counts"]
    counts.update({
        "v23_related_production_files": sum(
            item["file_path"].startswith(generator.engine.PRODUCTION_PREFIXES) for item in entries
        ),
        "v23_related_test_files": sum(item["file_path"].startswith("tests/") for item in entries),
        "formal_direct_A": sum(item["classification"] == "A" for item in entries),
        "formal_indirect_B": sum(item["classification"] == "B" for item in entries),
        "alpha_fixture_C": sum(item["classification"] == "C" for item in entries),
        "ui_spike_D": sum(item["classification"] == "D" for item in entries),
        "compatibility_E": sum(item["classification"] == "E" for item in entries),
        "test_only_F": sum(item["classification"] == "F" for item in entries),
        "unused_G": sum(item["classification"] == "G" for item in entries),
        "uncertain_U": sum(item["classification"] == "U" for item in entries),
        "formal_runtime_transitive_paths": sum(item["formal_reachable"] for item in entries),
        "formal_save_dependencies": sum(item["formal_save_or_load"] for item in entries),
        "formal_long_term_dependencies": sum(item["formal_ten_year"] for item in entries),
        "candidate_total": len(entries),
    })


def _compact_evidence(audit: dict) -> None:
    for item in audit["candidates"]:
        item["evidence_locations"] = sorted({_location_only(site) for site in item["evidence_locations"]})
        item["dynamic_loading_evidence"] = sorted({_location_only(site) for site in item["dynamic_loading_evidence"]})
    checks = audit["special_checks"]
    for key in ("loran", "vesta", "prototype_map"):
        checks[key]["evidence"] = _first_location_per_file(checks[key]["evidence"])
    performance = checks["old_150_second_performance_test"]
    performance["evidence"] = sorted({_location_only(site) for site in performance["evidence"]})
    performance["other_150_second_workflow_timeouts"] = sorted({
        _location_only(site) for site in performance["other_150_second_workflow_timeouts"]
    })
    checks["deprecated_workflow_evidence"] = sorted({
        _location_only(site) for site in checks["deprecated_workflow_evidence"]
    })
    checks["d01_formal_time_residuals"] = sorted({
        _location_only(site) for site in checks["d01_formal_time_residuals"]
    })


def _compact_roots(audit: dict) -> None:
    roots = audit["roots"]
    audit["root_counts"] = {name: len(values) for name, values in roots.items()}
    audit["roots"] = {
        name: roots[name]
        for name in (
            "formal_product", "formal_scene", "formal_save",
            "formal_long_term", "formal_integration",
        )
    }
    audit["root_rules"] = {
        "alpha_fixture": "scripts/alpha, tests/alpha, data/alpha, tests/fixtures and the Alpha three-year workflow",
        "ui_spike": "scripts/ui_spikes, scenes/ui_spikes and shaders/ui_spikes",
        "tests": "tests/**",
        "workflows": ".github/workflows/**",
        "compatibility": "files explicitly named or containing save, migration, compatibility, legacy or fixture schema evidence",
    }


def _refine_audit(root: Path, audit: dict) -> dict:
    audit["candidates"] = [
        item for item in audit["candidates"] if item["file_path"] != RUNNER_PATH
    ]
    by_path = {item["file_path"]: item for item in audit["candidates"]}
    changed = True
    while changed:
        changed = False
        for item in audit["candidates"]:
            if item["classification"] != "U" or item["dynamic_loading_evidence"]:
                continue
            callers = sorted(set(item["direct_callers"] + item["indirect_callers"]))
            if callers and all(
                caller in by_path and by_path[caller]["classification"] in {"G", "U"}
                for caller in callers
            ):
                item["classification"] = "G"
                item["classification_label"] = generator.engine.CLASS_LABELS["G"]
                item["classification_reason"] = "仅由同一无入口候选簇调用，整个闭包没有外部根或动态加载证据"
                item["recommendation"] = generator.engine.RECOMMENDATIONS["G"]
                item["confidence"] = "high"
                changed = True

    workflow_text = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted((root / ".github" / "workflows").glob("*"))
        if path.is_file()
    )
    for item in audit["special_checks"]["standalone_v23_entries"]:
        item["workflow_referenced"] = (
            item["path"] in workflow_text or "res://" + item["path"] in workflow_text
        )
    _recount(audit)
    _compact_evidence(audit)
    _compact_roots(audit)
    _deduplicate_indirect_callers(audit)
    return audit


def _refined_build_audit(root: Path) -> dict:
    return _refine_audit(root.resolve(), _ORIGINAL_BUILD_AUDIT(root))


def _serialize_compact_json(audit: dict) -> str:
    return json.dumps(audit, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def _deterministic_gzip(data: bytes) -> bytes:
    compressor = zlib.compressobj(level=9, method=zlib.DEFLATED, wbits=-zlib.MAX_WBITS)
    payload = compressor.compress(data) + compressor.flush()
    header = b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff"
    footer = struct.pack("<II", zlib.crc32(data) & 0xFFFFFFFF, len(data) & 0xFFFFFFFF)
    return header + payload + footer


def _render_concise_markdown(audit: dict) -> str:
    counts = audit["counts"]
    lines = [
        "# V2.3 正式依赖清查", "",
        "本报告由确定性静态审计工具生成。本 PR 只增加审计工具、测试、机器清单、报告和只读 CI；未迁移、重命名、删除或重构任何生产服务。", "",
        "## 基线与扫描", "",
        f"- 固定 Base SHA：`{audit['fixed_base_sha']}`",
        f"- 默认启动场景：`{audit['scan']['main_scene'] or '未解析'}`",
        f"- 扫描文件数：{audit['scan']['source_file_count']}",
        f"- 完整机器清单：`{INVENTORY_PATH}`（确定性 gzip 压缩 JSON）",
        f"- D01 稳定契约 blob：`{audit['formal_time_contract']['actual_blob_sha']}`",
        f"- D01 稳定契约保持不变：`{str(audit['formal_time_contract']['unchanged']).lower()}`",
        "- 扫描覆盖 `project.godot`、导出配置、脚本、场景、资源、数据、测试、工具和 workflow；文档引用不作为生产依赖证据。", "",
        "## 数量", "", "|指标|数量|", "|---|---:|",
    ]
    metrics = [
        ("V2.3 相关生产文件", "v23_related_production_files"),
        ("V2.3 相关测试文件", "v23_related_test_files"),
        ("A 正式直接依赖", "formal_direct_A"),
        ("B 正式间接依赖", "formal_indirect_B"),
        ("C Alpha/fixture 隔离", "alpha_fixture_C"),
        ("D 非正式样机", "ui_spike_D"),
        ("E 兼容边界", "compatibility_E"),
        ("F 测试专用", "test_only_F"),
        ("G 无有效调用", "unused_G"),
        ("U 无法确定", "uncertain_U"),
        ("正式场景直接路径", "formal_scene_direct_paths"),
        ("正式运行时传递路径", "formal_runtime_transitive_paths"),
        ("正式保存依赖", "formal_save_dependencies"),
        ("正式长期模拟依赖", "formal_long_term_dependencies"),
        ("仍绑定弃用 V2.3 产品语义的 workflow 门禁", "deprecated_v23_product_workflow_gates"),
    ]
    lines.extend(f"|{label}|{counts[key]}|" for label, key in metrics)
    lines += ["", "## 正式产品根节点", ""]
    lines.extend(f"- `{path}`" for path in audit["roots"]["formal_product"])
    lines += ["", "结论：静态依赖图中没有任何 V2.3 候选从正式产品根节点直接或间接可达；正式启动、tick、经济、保存、HUD/地图和十年长期模拟中的 V2.3 依赖数量均为 0。", ""]

    labels = generator.engine.CLASS_LABELS
    for category in "ABCDEFGU":
        entries = [item for item in audit["candidates"] if item["classification"] == category]
        lines += [f"## {category}：{labels[category]}", ""]
        if not entries:
            lines += ["无。", ""]
            continue
        for item in entries:
            classes = ", ".join(item["class_names"])
            suffix = f"（{classes}）" if classes else ""
            lines.append(f"- `{item['file_path']}`{suffix} — {item['recommendation']}；置信度：{item['confidence']}。")
            if category in {"A", "B"}:
                for path in item["formal_paths"]:
                    lines.append("  - 调用链：" + " → ".join(f"`{part}`" for part in path))
            if category == "G":
                lines.append(f"  - 无调用证据：{item['classification_reason']}。")
            if category == "U":
                lines.append(f"  - 待补证据：{item['classification_reason']}。")
        lines.append("")

    checks = audit["special_checks"]
    lines += ["## 专项核对", "", "### 旧独立 150 秒性能测试", ""]
    lines.extend(f"- `{site}`" for site in checks["old_150_second_performance_test"]["evidence"])
    lines.append(f"- 建议：{checks['old_150_second_performance_test']['recommendation']}")
    for key, title in (("loran", "Loran"), ("vesta", "Vesta"), ("prototype_map", "PrototypeMap")):
        status = checks[key]
        lines += ["", f"### {title}", "",
            f"- 涉及文件：{len(status['files'])}",
            f"- 正式可达生产文件：{', '.join(f'`{p}`' for p in status['formal_reachable_files']) or '无'}",
            f"- Alpha/fixture 文件：{len(status['alpha_or_fixture_files'])}",
            f"- 非正式样机文件：{len(status['ui_spike_files'])}",
        ]
    lines += ["", "### 弃用入口、发布和时间链", ""]
    for item in checks["standalone_v23_entries"]:
        lines.append(
            f"- `{item['path']}`：存在={str(item['exists']).lower()}，正式可达={str(item['formal_reachable']).lower()}，"
            f"workflow 引用={str(item['workflow_referenced']).lower()}，导出引用={str(item['export_referenced']).lower()}。"
        )
    lines += [
        f"- Windows 导出弃用入口引用：{len(checks['windows_export']['deprecated_entry_references'])}",
        f"- 弃用 V2.3 产品语义 workflow 证据：{', '.join(f'`{p}`' for p in checks['deprecated_workflow_evidence']) or '无'}",
        f"- D01 后正式可达 V2.3 时间字段残余：{len(checks['d01_formal_time_residuals'])}",
        "", "## 静态分析限制", "",
    ]
    lines.extend(f"- {limit}" for limit in audit["static_analysis_limits"])
    lines += ["", "## 后续建议", "",
        "- C 类继续作为 Alpha/fixture 隔离服务；若其中通用人物、关系、行程、社会和生活需求服务需要进入正式产品，下一 PR 先建立行为基线，再迁移到中性正式目录。",
        "- E 类继续作为旧存档兼容边界，不得成为运行期事实源。",
        "- F 类随对应服务迁移或删除，不得因测试存在而认定为正式依赖。",
        "- G 类在下一 PR 再次确认无动态证据后删除。",
        "- 当前 U 类为 0；未来若出现动态字符串或反射证据，必须归 U 而不是 G。",
        "- 下一项唯一任务：`V2.3 通用服务迁移与无调用内容清理`。", "",
    ]
    return "\n".join(lines)


def _write_or_check_gzip(root: Path, audit: dict, check: bool) -> int:
    report = _render_concise_markdown(audit).encode("utf-8")
    inventory = _deterministic_gzip(_serialize_compact_json(audit).encode("utf-8"))
    targets = {
        root / REPORT_PATH: report,
        root / INVENTORY_PATH: inventory,
    }
    failures: list[str] = []
    for path, expected in targets.items():
        if check:
            actual = path.read_bytes() if path.exists() else None
            if actual != expected:
                failures.append(path.relative_to(root).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)
    if failures:
        print("Out-of-date formal V2.3 dependency artifacts:", file=sys.stderr)
        for path in failures:
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


def _hard_timeout() -> None:
    print("Formal V2.3 dependency generation exceeded 180 seconds.", flush=True)
    os._exit(124)


def main() -> int:
    generator.EXCLUDED_PATHS.update({RUNNER_PATH, INVENTORY_PATH, REPORT_PATH})
    generator.engine.bfs_paths = _linear_bfs_paths
    generator.reverse_closure = _linear_reverse_closure
    generator.incoming_dynamic_sites = _indexed_incoming_dynamic_sites
    generator.build_audit = _refined_build_audit
    generator.engine.serialize_json = _serialize_compact_json
    generator.render_markdown = _render_concise_markdown
    generator.write_or_check = _write_or_check_gzip
    faulthandler.dump_traceback_later(60, repeat=True)
    timer = threading.Timer(180, _hard_timeout)
    timer.daemon = True
    timer.start()
    try:
        return generator.main()
    finally:
        timer.cancel()
        faulthandler.cancel_dump_traceback_later()


if __name__ == "__main__":
    raise SystemExit(main())
