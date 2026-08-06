#!/usr/bin/env python3
"""Generate the deterministic formal-product system completeness audit.

Scanner-derived reachability is deliberately separated from reviewed product
judgements. The scanner never treats a filename, class name, test, or document
claim as proof that a player loop is complete.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, deque
from pathlib import Path
from typing import Iterable, Sequence

sys.dont_write_bytecode = True


REPORT_BASE_SHA = "0feed6add253cead359a9e41f85e09bdf84c24e7"
AUDIT_DATE = "2026-08-04"
SCHEMA_VERSION = "formal-product-system-completeness/v1"
FORMAL_MAIN_SCENE = "res://scenes/formal/formal_world_menu.tscn"

DIMENSIONS = (
    "implementation",
    "runtime_reachability",
    "integration",
    "player_surface",
    "state_ownership",
    "lifecycle",
    "persistence",
    "causal_feedback",
    "data_readiness",
    "verification",
    "observability",
    "maintainability",
)
DIMENSION_STATUSES = {
    "VERIFIED", "PARTIAL", "MISSING", "NOT_APPLICABLE", "UNKNOWN",
}
MATURITIES = {
    "ABSENT",
    "SCAFFOLD_ONLY",
    "IMPLEMENTED_ISOLATED",
    "INTEGRATED_UNVERIFIED",
    "INTEGRATED_VERIFIED",
    "PLAYER_LOOP_PARTIAL",
    "PLAYER_LOOP_COMPLETE",
}
REACHABILITY_CLASSES = {
    "FORMAL_RUNTIME",
    "FORMAL_DEPENDENCY",
    "TEST_ONLY",
    "LEGACY_REFERENCE",
    "SPIKE_ONLY",
    "TOOLING_ONLY",
    "UNRESOLVED",
}
LOOP_STATUSES = {"VERIFIED", "PARTIAL", "MISSING", "UNKNOWN"}
CLAIM_STATUSES = {
    "CODE_VERIFIED",
    "TEST_VERIFIED",
    "PARTIALLY_SUPPORTED",
    "DESIGN_ONLY",
    "STALE",
    "CONTRADICTED",
    "UNKNOWN",
}
PRIORITIES = {"P0", "P1", "P2", "P3"}

RESOURCE_RE = re.compile(r"res://[A-Za-z0-9_./@+ -]+")
CLASS_NAME_RE = re.compile(r"(?m)^\s*class_name\s+([A-Za-z_]\w*)\s*$")
TOKEN_RE = re.compile(r"\b[A-Za-z_]\w*\b")
MAIN_SCENE_RE = re.compile(r'(?m)^run/main_scene="([^"]+)"\s*$')
RES_SECTION_RE = re.compile(r"(?m)^\[autoload\]\s*$")
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")

AUDITABLE_PREFIXES = (
    ".github/",
    "assets/",
    "data/",
    "scenes/",
    "scripts/",
    "shaders/",
    "tests/",
    "tools/",
)
AUDITABLE_ROOT_FILES = {"project.godot", "export_presets.cfg"}
LEGACY_PARTS = {"alpha", "v2_2", "v2_3", "prototype_v2"}
SPIKE_PARTS = {"ui_spikes", "probe", "capture"}

AUDIT_DOCS = (
    "docs/audits/formal_product_system_completeness_20260804.md",
    "docs/audits/formal_product_system_inventory_20260804.md",
    "docs/audits/formal_product_gap_register_20260804.md",
    "docs/refactors/formal_product_system_ownership.md",
    "docs/refactors/formal_product_dependency_map.md",
)


class AuditError(RuntimeError):
    """Raised for an invalid checkout or non-reproducible invocation."""


def _git(root: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=root,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise AuditError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout.strip()


def _normalize_checkout(root: Path) -> Path:
    resolved = root.resolve()
    if not resolved.is_dir():
        raise AuditError(f"repository root does not exist: {root}")
    top_level = Path(_git(resolved, "rev-parse", "--show-toplevel")).resolve()
    if os.path.normcase(str(top_level)) != os.path.normcase(str(resolved)):
        raise AuditError(
            f"--root must be the repository top level: got {resolved}, "
            f"expected {top_level}"
        )
    if not (resolved / "project.godot").is_file():
        raise AuditError("project.godot is missing from --root")
    return resolved


def _validate_sha(root: Path, expected_head: str, report_base_sha: str) -> None:
    sha_pattern = re.compile(r"^[0-9a-f]{40}$")
    if not sha_pattern.fullmatch(expected_head):
        raise AuditError("--expected-head must be a lowercase 40-character SHA")
    if not sha_pattern.fullmatch(report_base_sha):
        raise AuditError("--report-base-sha must be a lowercase 40-character SHA")
    actual_head = _git(root, "rev-parse", "HEAD")
    if actual_head != expected_head:
        raise AuditError(
            f"HEAD mismatch: expected {expected_head}, found {actual_head}"
        )
    _git(root, "cat-file", "-e", f"{report_base_sha}^{{commit}}")


def _tracked_files(root: Path) -> list[str]:
    output = _git(root, "ls-files", "-z")
    files = [item for item in output.split("\0") if item]
    return sorted(path.replace("\\", "/") for path in files)


def _read_text(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8", errors="replace")


def _strip_gd_comments_and_strings(text: str) -> str:
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
            width = 3 if triple else 1
            output.extend(" " * width)
            index += width
            quote = character
            continue
        output.append(character)
        index += 1
    return "".join(output)


def _line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _resource_references(text: str) -> list[tuple[str, int]]:
    references: set[tuple[str, int]] = set()
    for match in RESOURCE_RE.finditer(text):
        value = match.group(0).rstrip(".,;:)]}'\"")
        references.add((value, _line_number(text, match.start())))
    return sorted(references, key=lambda item: (item[0], item[1]))


def _resource_kind(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix == ".gd":
        return "script"
    if suffix in {".tscn", ".tres"}:
        return "scene_or_resource"
    if suffix in {".json", ".cfg", ".godot"}:
        return "data_or_config"
    if suffix == ".gdshader":
        return "shader"
    if suffix in {".png", ".svg", ".jpg", ".jpeg", ".webp"}:
        return "asset"
    if suffix in {".yml", ".yaml", ".ps1", ".py"}:
        return "tooling"
    return "other"


def _is_auditable(path: str) -> bool:
    return path in AUDITABLE_ROOT_FILES or path.startswith(AUDITABLE_PREFIXES)


def _path_parts(path: str) -> set[str]:
    return {part.lower() for part in Path(path).parts}


def _path_provenance(path: str) -> list[str]:
    parts = _path_parts(path)
    provenance: list[str] = []
    if parts & LEGACY_PARTS:
        provenance.append("LEGACY_NAMED")
    if parts & SPIKE_PARTS or "ui_spikes" in path.lower():
        provenance.append("SPIKE_NAMED")
    if not provenance:
        provenance.append("NEUTRAL")
    return provenance


def _extract_main_scene(project_text: str) -> str:
    match = MAIN_SCENE_RE.search(project_text)
    if not match:
        raise AuditError("project.godot does not declare application/run/main_scene")
    return match.group(1)


def _extract_autoloads(project_text: str) -> list[str]:
    if not RES_SECTION_RE.search(project_text):
        return []
    section = project_text.split("[autoload]", 1)[1]
    section = section.split("\n[", 1)[0]
    output: list[str] = []
    for line in section.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith(";") and "=" in stripped:
            output.append(stripped.split("=", 1)[0].strip())
    return sorted(output)


def _class_index(root: Path, tracked: Iterable[str]) -> dict[str, str]:
    index: dict[str, str] = {}
    duplicates: dict[str, list[str]] = {}
    for path in tracked:
        if not path.startswith("scripts/") or not path.endswith(".gd"):
            continue
        match = CLASS_NAME_RE.search(_read_text(root, path))
        if not match:
            continue
        name = match.group(1)
        if name in index:
            duplicates.setdefault(name, [index[name]]).append(path)
        else:
            index[name] = path
    if duplicates:
        detail = "; ".join(
            f"{name}: {', '.join(paths)}"
            for name, paths in sorted(duplicates.items())
        )
        raise AuditError(f"duplicate class_name declarations: {detail}")
    return index


def _build_formal_graph(
    root: Path, tracked: list[str], class_index: dict[str, str]
) -> dict[str, object]:
    tracked_set = set(tracked)
    project_text = _read_text(root, "project.godot")
    main_scene = _extract_main_scene(project_text)
    if main_scene != FORMAL_MAIN_SCENE:
        raise AuditError(
            f"formal main scene changed: expected {FORMAL_MAIN_SCENE}, found {main_scene}"
        )
    main_relative = main_scene.removeprefix("res://")
    if main_relative not in tracked_set:
        raise AuditError(f"formal main scene is not tracked: {main_relative}")

    queue: deque[str] = deque(["project.godot"])
    visited: set[str] = set()
    dependencies: set[str] = set()
    edges: set[tuple[str, str, str, int]] = set()

    while queue:
        source = queue.popleft()
        if source in visited:
            continue
        visited.add(source)
        source_path = root / source
        if not source_path.is_file():
            continue
        text = source_path.read_text(encoding="utf-8", errors="replace")
        for resource, line in _resource_references(text):
            target = resource.removeprefix("res://")
            if target not in tracked_set:
                continue
            kind = "main_scene" if source == "project.godot" else "resource_reference"
            edges.add((source, target, kind, line))
            if target not in visited:
                queue.append(target)
        if source.endswith(".gd"):
            code = _strip_gd_comments_and_strings(text)
            tokens = set(TOKEN_RE.findall(code))
            for class_name in sorted(tokens & class_index.keys()):
                target = class_index[class_name]
                if target == source:
                    continue
                match = re.search(rf"\b{re.escape(class_name)}\b", code)
                line = _line_number(code, match.start()) if match else 1
                edges.add((source, target, "class_name_reference", line))
                dependencies.add(target)
                if target not in visited:
                    queue.append(target)

    edge_rows = [
        {"from": source, "to": target, "kind": kind, "line": line}
        for source, target, kind, line in sorted(edges)
    ]
    return {
        "main_scene": main_scene,
        "autoloads": _extract_autoloads(project_text),
        "formal_runtime_files": sorted(visited),
        "formal_dependency_files": sorted(dependencies),
        "edges": edge_rows,
    }


def _classifications(
    path: str, formal_runtime: set[str], formal_dependencies: set[str]
) -> list[str]:
    roles: set[str] = set()
    parts = _path_parts(path)
    if path in formal_runtime:
        roles.add("FORMAL_RUNTIME")
    if path in formal_dependencies:
        roles.add("FORMAL_DEPENDENCY")
    if path not in formal_runtime:
        if path.startswith("tests/"):
            roles.add("TEST_ONLY")
        if parts & LEGACY_PARTS:
            roles.add("LEGACY_REFERENCE")
        if parts & SPIKE_PARTS or "ui_spikes" in path.lower():
            roles.add("SPIKE_ONLY")
        if path.startswith(("tools/", ".github/")) or path == "export_presets.cfg":
            roles.add("TOOLING_ONLY")
    if not roles:
        roles.add("UNRESOLVED")
    unknown = roles - REACHABILITY_CLASSES
    if unknown:
        raise AuditError(f"unknown reachability classifications: {sorted(unknown)}")
    return sorted(roles)


def _scan_missing_resource_references(
    root: Path,
    tracked: list[str],
    classifications_by_path: dict[str, list[str]],
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    tracked_set = set(tracked)
    source_suffixes = {".gd", ".tscn", ".tres", ".godot"}
    for source in tracked:
        if Path(source).suffix.lower() not in source_suffixes:
            continue
        if not source.startswith(("scripts/", "scenes/", "tests/")) and source != "project.godot":
            continue
        text = _read_text(root, source)
        for resource, line in _resource_references(text):
            target = resource.removeprefix("res://")
            if target in tracked_set or (root / target).exists():
                continue
            suffix = Path(target).suffix.lower()
            if not suffix:
                continue
            negative = (
                "does_not_exist" in target
                or "forbidden" in target
                or target.startswith("artifacts/")
            )
            rows.append({
                "source": source,
                "line": line,
                "target": target,
                "source_classifications": classifications_by_path.get(
                    source, ["UNRESOLVED"]
                ),
                "expected_negative_or_generated_output": negative,
            })
    return sorted(rows, key=lambda row: (
        str(row["source"]), int(row["line"]), str(row["target"])
    ))


def _scan_ci(root: Path, tracked: list[str]) -> dict[str, object]:
    workflows = [
        path for path in tracked
        if path.startswith(".github/workflows/")
        and path.endswith((".yml", ".yaml"))
    ]
    formal_workflows: list[str] = []
    for path in workflows:
        text = _read_text(root, path)
        if "tests/formal/" in text or "scenes/formal/" in text:
            formal_workflows.append(path)
    validation_text = _read_text(root, "tools/run_validation.ps1")
    validation_tests = sorted({
        resource.removeprefix("res://")
        for resource, _line in _resource_references(validation_text)
        if resource.endswith(".gd") and "/tests/" in resource
    })
    return {
        "workflow_files": sorted(workflows),
        "formal_workflow_files": sorted(formal_workflows),
        "unified_validation_test_entries": validation_tests,
        "unified_validation_runs_legacy_test_runner": (
            "tests/test_runner.gd" in validation_text
        ),
        "release_workflow": ".github/workflows/windows-prototype-release.yml",
    }


def scanner_payload(root: Path) -> dict[str, object]:
    tracked = _tracked_files(root)
    class_index = _class_index(root, tracked)
    graph = _build_formal_graph(root, tracked, class_index)
    runtime = set(graph["formal_runtime_files"])
    dependencies = set(graph["formal_dependency_files"])
    auditable = [path for path in tracked if _is_auditable(path)]
    files: list[dict[str, object]] = []
    classifications_by_path: dict[str, list[str]] = {}
    for path in auditable:
        roles = _classifications(path, runtime, dependencies)
        classifications_by_path[path] = roles
        files.append({
            "path": path,
            "kind": _resource_kind(path),
            "classifications": roles,
            "path_provenance": _path_provenance(path),
        })
    missing = _scan_missing_resource_references(
        root, tracked, classifications_by_path
    )
    formal_missing = [
        row for row in missing
        if "FORMAL_RUNTIME" in row["source_classifications"]
        and not row["expected_negative_or_generated_output"]
    ]
    if formal_missing:
        raise AuditError(
            "formal runtime contains unresolved literal resources: "
            + json.dumps(formal_missing, ensure_ascii=False, sort_keys=True)
        )
    role_counts = Counter(
        role for row in files for role in row["classifications"]
    )
    runtime_spike = [
        row["path"] for row in files
        if "FORMAL_RUNTIME" in row["classifications"]
        and "SPIKE_NAMED" in row["path_provenance"]
    ]
    runtime_legacy = [
        row["path"] for row in files
        if "FORMAL_RUNTIME" in row["classifications"]
        and "LEGACY_NAMED" in row["path_provenance"]
    ]
    production_scripts = [
        path for path in tracked
        if path.startswith("scripts/") and path.endswith(".gd")
    ]
    unresolved_production_scripts = [
        row["path"] for row in files
        if row["path"] in production_scripts
        and row["classifications"] == ["UNRESOLVED"]
    ]
    return {
        "derivation": {
            "formal_reachability": (
                "Transitive res:// literals plus referenced global class_name "
                "scripts, rooted at project.godot application/run/main_scene."
            ),
            "limitations": (
                "Literal and class-token reachability cannot prove dynamic "
                "reflection, semantic ownership, completeness, or player loops."
            ),
        },
        "project": {
            "main_scene": graph["main_scene"],
            "autoloads": graph["autoloads"],
        },
        "counts": {
            "tracked_auditable_files": len(auditable),
            "production_gd_files": len(production_scripts),
            "formal_runtime_files": len(runtime),
            "formal_dependency_files": len(dependencies),
            "formal_runtime_spike_named_files": len(runtime_spike),
            "formal_runtime_legacy_named_files": len(runtime_legacy),
            "missing_literal_resource_references": len(missing),
            "unresolved_production_scripts": len(unresolved_production_scripts),
        },
        "classification_counts": {
            key: role_counts.get(key, 0) for key in sorted(REACHABILITY_CLASSES)
        },
        "formal_runtime_files": graph["formal_runtime_files"],
        "formal_dependency_files": graph["formal_dependency_files"],
        "formal_runtime_spike_named_files": sorted(runtime_spike),
        "formal_runtime_legacy_named_files": sorted(runtime_legacy),
        "unresolved_production_scripts": sorted(unresolved_production_scripts),
        "reachability_edges": graph["edges"],
        "files": sorted(files, key=lambda row: str(row["path"])),
        "missing_literal_resource_references": missing,
        "ci": _scan_ci(root, tracked),
    }


def _evidence(
    evidence_id: str,
    path: str,
    symbol: str,
    evidence_type: str,
    formal_runtime: bool,
    historical_experimental_or_test_only: bool,
    supports: str,
    cannot_prove: str,
    origin: str = "reviewed",
) -> dict[str, object]:
    return {
        "id": evidence_id,
        "path": path,
        "symbol": symbol,
        "evidence_type": evidence_type,
        "formal_runtime": formal_runtime,
        "historical_experimental_or_test_only": (
            historical_experimental_or_test_only
        ),
        "origin": origin,
        "supports": supports,
        "cannot_prove": cannot_prove,
    }


def reviewed_evidence() -> list[dict[str, object]]:
    rows = [
        _evidence("E001", "project.godot", "application/run/main_scene; [autoload]", "formal_entry", True, False, "默认入口是 formal_world_menu.tscn，且没有 autoload 声明。", "不能证明菜单后的玩家闭环完整。", "scanner-derived"),
        _evidence("E002", "scripts/formal/formal_world_menu.gd", "WORLD_SCENE; _ready; _enter_world; _formal_save_exists", "production_code", True, False, "菜单按存档存在性自动选择 new/load，并切换到正式主场景。", "不能证明损坏存档恢复、显式新游戏/读档选择或退出流程。"),
        _evidence("E003", "scenes/formal/formal_world_main.tscn", "FormalWorldMain; ClockTimer; FlagTimer; ext_resource", "scene_assembly", True, False, "正式场景装配 FormalWorldApplication、半球、两个计时器和 spike 命名 shader。", "不能证明这些节点状态进入权威存档。"),
        _evidence("E004", "scripts/formal/formal_world_application.gd", "_ready; _advance_simulation_minutes; _load_formal_state; _activate_button", "production_code", True, False, "正式应用初始化/恢复 FormalWorldSimulation，并暴露时间、经济面板、保存和读取操作。", "不能证明存在权威玩家行动、旅行、社会或政治写入。"),
        _evidence("E005", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "_on_clock_timer_timeout; _draw_time_panel; _activate_button", "production_code", True, False, "正式继承链提供暂停、1/2/4 倍速和 15 分钟 tick 控制。", "不能证明该 UI 的其他选择状态是模拟状态。"),
        _evidence("E006", "scripts/formal/formal_world_simulation.gd", "total_minutes; initialize; advance_minutes; date_time", "state_ownership", True, False, "FormalWorldSimulation 持有唯一正式累计分钟并按小时驱动经济。", "不能证明非经济系统按同一时间推进。"),
        _evidence("E007", "scripts/formal/formal_world_simulation.gd", "get_persistent_state; restore_persistent_state; save_to_user; load_from_user", "persistence", True, False, "正式 schema v2 保存时间和经济，恢复失败会回滚内存时间/经济。", "不能证明原子文件替换、备份、导航或玩家状态覆盖。"),
        _evidence("E008", "scripts/formal/formal_world_economy_service.gd", "configure; _load_polity_registry; _load_crosswalk; _initialize_country", "production_code", True, False, "经济加载 151 个政治单元、50 个经济聚合体、商品和 crosswalk。", "不能证明家庭、企业、个人账户或玩家职业经济。"),
        _evidence("E009", "scripts/formal/formal_world_economy_service.gd", "_settle_day; _settle_country; _schedule_shortage_shipments; _deliver_shipments", "causal_feedback", True, False, "日结改变生产、消费、库存、价格、短缺、运输和贸易差额。", "不能证明玩家行为改变这些状态。"),
        _evidence("E010", "scripts/formal/formal_world_economy_service.gd", "restore_persistent_state; _last_day_index; _validate_state", "state_ownership", True, False, "_last_day_index 可从存档独立恢复，但 _validate_state 未校验其与权威小时一致。", "静态证据不能量化所有错误值的实际损害。"),
        _evidence("E011", "tests/formal/formal_world_integration_test.gd", "_check_formal_economy; _check_product_scenes; _check_runtime_application", "automated_test", False, True, "测试覆盖正式场景加载、151/50 roster、90 日推进、内存快照恢复和 UI 时钟入口。", "不覆盖完整玩家行动、磁盘损坏恢复、退出重启或社会/旅行闭环。"),
        _evidence("E012", "tests/variable_state/formal_time_stable_contract_test.gd", "_test_pause_and_speed_entry; _test_save_load_round_trip; _test_restore_failure_atomicity", "automated_test", False, True, "测试经生产入口验证时间、磁盘保存读取和失败原子内存回滚。", "不证明文件写入本身具备原子替换。"),
        _evidence("E013", "tests/formal/formal_world_long_term_balance_test.gd", "_run; YEARS = 10", "automated_test", False, True, "十年测试约束经济满足率、数值有效、队列、存档大小、耗时和恢复摘要。", "不覆盖 UI、内存峰值、资源泄漏或其他大型系统。"),
        _evidence("E014", ".github/workflows/windows-prototype-release.yml", "validate-and-export; Windows Desktop export", "ci_release", False, True, "工作流导入、运行正式测试、启动主场景并导出 Windows 可执行文件/安装包。", "工作流定义不等于本次提交已在真实 Windows 安装后完成玩家 smoke。"),
        _evidence("E015", ".github/workflows/release-ui-integration.yml", "Verify formal world runtime; Capture formal title and hemisphere", "ci", False, True, "CI 截图正式标题、半球和政经面板，并运行场景集成回归。", "截图不证明交互式完整玩家旅程。"),
        _evidence("E016", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "_data_errors; _draw_data_errors; _read_document", "observability", True, False, "数据读取/JSON 错误会进入可见错误条。", "不能诊断保存失败原因、因果链或发布环境崩溃。"),
        _evidence("E017", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "_load_all_data; selected_country_id; selected_region_id; selected_city_id", "player_surface", True, False, "正式 UI 加载海岸线、地区、城市、机构和人物档案并支持多层导航。", "导航选择不等于玩家位置或旅行。"),
        _evidence("E018", "scripts/formal/formal_world_simulation.gd", "get_persistent_state", "persistence", True, False, "正式快照只包含 schema_id、total_minutes、minute_remainder 和 economy。", "没有保存继承 UI 的地图选择、角色视角、事件未读或布局状态。"),
        _evidence("E019", "data/world_map/characters.json", "identities", "data_resource", True, False, "正式 UI 使用静态人物档案。", "静态档案不能证明权威玩家实体、需求、健康、资产或行动。"),
        _evidence("E020", "scripts/character/game_session_service.gd", "player_character; set_player; transfer_player; persistent_state", "production_code", False, False, "仓库有权威玩家/会话实现。", "正式入口扫描未命中该服务，因此不能证明正式产品使用它。"),
        _evidence("E021", "scripts/action/action_service.gd", "start_action; update_to_hour; _complete_action", "production_code", False, False, "仓库有强类型行动结算实现。", "正式入口扫描未命中该服务或行动 UI。"),
        _evidence("E022", "scripts/simulation/society_simulation_service.gd", "initialize; attach_clock; _on_day_advanced; _execute_ai_daily_actions", "production_code", False, False, "仓库有社会、组织、关系、AI 和继承组合服务。", "该组合服务不在正式运行可达图中。"),
        _evidence("E023", "scripts/save/atomic_json_file_store.gd", "TEMPORARY_SUFFIX; BACKUP_SUFFIX", "production_code", False, False, "核心存档线具备临时文件与备份原语。", "正式 FormalWorldSimulation 没有调用它。"),
        _evidence("E024", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "_seed_world_events; _world_events; activity_unread; mark_read", "state_ownership", True, False, "正式 UI 从机构 agenda 自行播种事件并维护未读数。", "这些事件不是正式模拟产生，也没有正式持久化。"),
        _evidence("E025", "scripts/simulation/world_activity_service.gd", "add_event; get_persistent_state; restore_persistent_state", "production_code", False, False, "仓库另有可持久化、有界世界活动服务。", "正式 UI 未连接该服务。"),
        _evidence("E026", "scripts/v2_3/travel_execution_service.gd", "TravelExecutionService", "legacy_code", False, True, "V2.3 产品线保留旅行服务及相关通信、知识、关系测试。", "它们没有进入正式入口，不能作为正式闭环证据。"),
        _evidence("E027", "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd", "_build_dated_historical_unit", "state_ownership", True, False, "历史投影同时从 controller_id 派生 sovereign_id 和 controller_id。", "不能证明法理归属与实际控制已经建模分离。"),
        _evidence("E028", "data/world_map/historical/cshapes_1900_snapshot.json", "snapshot_date; source.license; source.commercial_use_allowed", "data_resource", True, False, "正式边界快照日期为 1900-03-12，来源声明 CC BY-NC-SA 4.0 且 commercial_use_allowed=false。", "不能替代正式法律/发布许可审查。"),
        _evidence("E029", "data/world_map/historical/historical_admin1_1900.json", "countries[*].geometry_status", "data_resource", True, False, "多个历史一级行政区仅验证名称，几何仍需数字化或使用现代 crosswalk。", "不能证明完整 1900 下级行政空间。"),
        _evidence("E030", "scripts/formal/formal_world_economy_service.gd", "AlphaHistoricalWorldEconomyData; DataRecordUtils; V2DateTime dependency", "formal_dependency", True, True, "正式运行确实依赖 Alpha 数据类/目录和 V2DateTime。", "不能据目录名把整个 Alpha/V2 产品线视为正式。"),
        _evidence("E031", "scripts/formal/formal_world_economy_service.gd", "country_states; daily_totals; gold_reserve_units", "state_ownership", True, False, "正式经济权威状态是国家/经济聚合层。", "没有个人、家庭、企业或政府独立账本进入正式组合根。"),
        _evidence("E032", "scripts/formal/formal_world_application.gd", "formal_simulation", "runtime_reachability", True, False, "正式应用只组合 FormalWorldSimulation；扫描未发现核心社会、行动、地图控制或 AI 服务引用。", "静态扫描不能排除外部动态注入，但场景和代码没有该证据。", "scanner-derived"),
        _evidence("E033", "tests/test_runner.gd", "_test_project_configuration; _test_main_menu_scene", "automated_test", False, True, "旧总测试仍断言不存在的 scenes/menu/main_menu.tscn 是主入口。", "该文件未被统一验证执行，不能代表当前产品通过。"),
        _evidence("E034", "tools/run_validation.ps1", "$tests; Headless formal product startup", "validation_entry", False, True, "统一验证运行正式经济/场景/十年测试和保留/隔离服务测试。", "它不运行 tests/test_runner.gd 或旧 1280x720 核心玩家旅程。"),
        _evidence("E035", "docs/ARCHITECTURE.md", "目录结构：scenes/menu/main_menu.tscn", "documentation", False, False, "架构文档仍把已不存在的旧菜单描述为基础入口。", "文档陈述不能覆盖 project.godot。"),
        _evidence("E036", "docs/PRODUCT_VISION.md", "产品愿景与长期系统目标", "documentation", False, False, "文档定义社会人物、组织、政治、经济等产品意图。", "愿景不是现有运行行为证据。"),
        _evidence("E037", "export_presets.cfg", "preset.0 Windows Desktop; embed_pck", "build_config", False, True, "仓库配置 Windows Desktop 嵌入式 PCK 导出。", "配置存在不证明本次构建、安装和运行成功。"),
        _evidence("E038", "scenes/formal/formal_world_menu.tscn", "PromptLabel; StatusLabel", "player_surface", True, False, "菜单只有按任意键进入及自动继续提示。", "没有显式新游戏、读取、设置、退出或存档槽选择控件。"),
        _evidence("E039", "scripts/formal/formal_world_application.gd", "formal_simulation calls", "causal_feedback", True, False, "应用对正式模拟的写入入口限于 advance_minutes、save_to_user 和 load_from_user。", "没有玩家职业、移动、社交、政治或组织命令写入正式模拟。"),
        _evidence("E040", "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd", "extends chain to holographic_workspace_runtime.gd", "maintainability", True, True, "正式应用继承 17 个 spike 命名脚本的深链，扫描器逐边确认可达。", "深链本身不证明运行错误，但扩大所有权和修改影响面。", "scanner-derived"),
        _evidence("E041", "scripts/alpha/alpha_historical_world_economy_data.gd", "configure; simulation_countries; coverage", "data_resource", True, True, "正式依赖的数据类验证 schema、覆盖登记、紧凑国家表和运输表，并允许 bounded_estimate 进入 50 国模拟。", "不能把有界估计当作全部历史维度已验证。"),
        _evidence("E042", "tests/p0_r1_player_journey_current.gd", "_run; strategic_map_view.tscn; save/load journey", "automated_test", False, True, "旧旅程描述完整角色/行动/社会/保存闭环。", "其目标场景已不存在且不在统一验证中，不能证明正式产品闭环。"),
        _evidence("E043", "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd", "LOWER_ADMIN_NOTICE; ADMIN1_REFERENCE_NOTICE", "data_resource", True, False, "正式 UI 自身声明下级行政区可能是现代参考而非 1900 历史边界。", "不能证明所有地图层共享同一历史时点。"),
        _evidence("E044", "scripts/formal/formal_world_application.gd", "_selected_polity_entity_id; polity_summary", "integration", True, False, "地图选中的政治单元可查询并展示正式经济摘要。", "查询投影不是地图/经济双向因果连接。"),
        _evidence("E045", "scripts/formal/formal_world_application.gd", "var formal_simulation := FormalWorldSimulation.new()", "state_ownership", True, False, "正式会话模拟由主场景节点局部持有，不依赖 autoload。", "没有统一拥有玩家、地图导航和其他系统的完整会话根。"),
        _evidence("E046", "docs/audits/variable_state_audit_20260803.md", "正式世界、核心、V2.2、V2.3、Alpha 存档协议", "documentation", False, False, "PR #38 变量审计确认仓库存在多条独立状态/存档协议及正式持久化风险。", "不能替代本轮正式可达图和产品闭环审计。"),
        _evidence("E047", "artifacts/variable-state-audit.json", "normalized variable/state inventory", "machine_artifact", False, False, "PR #38 规范化产物提供成员、写入和持久化证据索引。", "成员词法清单不能单独判定系统完整。"),
        _evidence("E048", "tests/formal/formal_world_ui_capture.gd", "_capture", "automated_test", False, True, "截图测试实例化正式菜单和主场景并保存三张 1280x720 表面图。", "预设截图不执行真实鼠标/键盘玩家旅程。"),
        _evidence("E049", ".github/workflows/formal-time-behavior-baseline.yml", "formal-time-baseline", "ci", False, True, "CI 运行正式时间稳定契约、已知缺陷回归和统一验证。", "只覆盖时间相关正式边界。"),
        _evidence("E050", "tests/v2_3/v2_3_player_interface_test.gd", "formal scene surface assertions", "automated_test", False, True, "统一验证中的 retained/UI 测试检查正式场景表面。", "V2.3 服务测试通过不代表这些服务已接入正式运行。"),
        _evidence("E051", "tests/test_runner.gd", "missing res:// scene literals", "runtime_reachability", False, True, "静态扫描发现旧总测试和旅程引用多个已删除场景。", "缺失测试资源不影响当前正式入口启动，但会误导测试覆盖判断。", "scanner-derived"),
        _evidence("E052", "data/world_map/historical/political_units_1900.json", "snapshot_date; unit_count", "data_resource", True, False, "正式政治目录声明 151 个 1900-03-12 单元。", "不能证明所有单元均有经济、行政、社会和玩家内容。"),
    ]
    return sorted(rows, key=lambda row: str(row["id"]))


def _dimensions(
    statuses: dict[str, str], evidence: dict[str, Sequence[str]]
) -> dict[str, dict[str, object]]:
    if set(statuses) != set(DIMENSIONS):
        missing = sorted(set(DIMENSIONS) - set(statuses))
        extra = sorted(set(statuses) - set(DIMENSIONS))
        raise AuditError(f"dimension map mismatch; missing={missing}, extra={extra}")
    result: dict[str, dict[str, object]] = {}
    for name in DIMENSIONS:
        status = statuses[name]
        if status not in DIMENSION_STATUSES:
            raise AuditError(f"invalid status {status} for {name}")
        refs = sorted(set(evidence.get(name, ())))
        if not refs:
            raise AuditError(f"dimension {name} has no evidence")
        result[name] = {"status": status, "evidence": refs}
    return result


def _system(
    system_id: str,
    name: str,
    maturity: str,
    conclusion: str,
    formal_entry: Sequence[str],
    production_files: Sequence[str],
    key_symbols: Sequence[str],
    data: Sequence[str],
    state: str,
    writers: Sequence[str],
    readers: Sequence[str],
    lifecycle: str,
    persistence: str,
    ui: str,
    tests: Sequence[str],
    ci: Sequence[str],
    documents: Sequence[str],
    dependencies: Sequence[str],
    dependents: Sequence[str],
    statuses: dict[str, str],
    dimension_evidence: dict[str, Sequence[str]],
) -> dict[str, object]:
    if maturity not in MATURITIES:
        raise AuditError(f"invalid maturity: {maturity}")
    return {
        "id": system_id,
        "name": name,
        "formal_entry": sorted(set(formal_entry)),
        "production_files": sorted(set(production_files)),
        "key_symbols": sorted(set(key_symbols)),
        "data": sorted(set(data)),
        "state": state,
        "writers": sorted(set(writers)),
        "readers": sorted(set(readers)),
        "lifecycle": lifecycle,
        "persistence": persistence,
        "ui": ui,
        "tests": sorted(set(tests)),
        "ci": sorted(set(ci)),
        "documents": sorted(set(documents)),
        "dependencies": sorted(set(dependencies)),
        "dependents": sorted(set(dependents)),
        "maturity": maturity,
        "conclusion": conclusion,
        "dimensions": _dimensions(statuses, dimension_evidence),
        "judgement_origin": "reviewed",
    }


def _status_map(**overrides: str) -> dict[str, str]:
    result = {name: "PARTIAL" for name in DIMENSIONS}
    result.update(overrides)
    return result


def _evidence_map(default: Sequence[str], **overrides: Sequence[str]) -> dict[str, Sequence[str]]:
    result = {name: default for name in DIMENSIONS}
    result.update(overrides)
    return result


def reviewed_systems() -> list[dict[str, object]]:
    systems = [
        _system(
            system_id="A",
            name="产品入口与会话生命周期",
            maturity="PLAYER_LOOP_PARTIAL",
            conclusion="正式菜单、新建/自动续档、场景切换、初始化、保存和读取可达；缺少权威玩家会话、显式退出、存档故障恢复与完整恢复边界。",
            formal_entry=["project.godot -> scenes/formal/formal_world_menu.tscn"],
            production_files=["scenes/formal/formal_world_menu.tscn", "scenes/formal/formal_world_main.tscn", "scripts/formal/formal_world_menu.gd", "scripts/formal/formal_world_application.gd", "scripts/formal/formal_world_simulation.gd"],
            key_symbols=["FormalWorldMenu._enter_world", "FormalWorldApplication._ready", "FormalWorldSimulation.initialize"],
            data=[],
            state="SceneTree launch-mode metadata, one scene-owned FormalWorldSimulation, and inherited UI navigation state.",
            writers=["FormalWorldMenu", "FormalWorldApplication", "FormalWorldSimulation"],
            readers=["FormalWorldMenu", "FormalWorldApplication", "formal UI draw methods"],
            lifecycle="Menu decides new/load, main scene initializes, timer drives while alive; no explicit session shutdown owner.",
            persistence="Only formal time/economy snapshot is restored; launch and UI/session state are excluded.",
            ui="Any-key menu, automatic continue status, formal map, F5/F9 and on-screen save/load buttons.",
            tests=["tests/formal/formal_world_integration_test.gd", "tests/variable_state/formal_time_known_defects_test.gd"],
            ci=[".github/workflows/windows-prototype-release.yml", ".github/workflows/release-ui-integration.yml"],
            documents=["docs/economy/formal_world_integration.md", "docs/refactors/formal_time_single_source.md"],
            dependencies=["B", "C", "F", "K", "L", "M"],
            dependents=["O"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                player_surface="PARTIAL", state_ownership="PARTIAL",
                lifecycle="PARTIAL", persistence="PARTIAL",
                causal_feedback="PARTIAL", data_readiness="VERIFIED",
                verification="PARTIAL", observability="PARTIAL",
                maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E001", "E002", "E004"],
                implementation=["E001", "E002", "E003", "E004"],
                runtime_reachability=["E001", "E011"],
                integration=["E004", "E006", "E007"],
                player_surface=["E002", "E038"],
                state_ownership=["E045", "E046"],
                lifecycle=["E002", "E004", "E038"],
                persistence=["E007", "E018"],
                causal_feedback=["E039"],
                data_readiness=["E008", "E041"],
                verification=["E011", "E048"],
                observability=["E016"],
                maintainability=["E040", "E046"],
            ),
        ),
        _system(
            system_id="B",
            name="时间与模拟调度",
            maturity="INTEGRATED_VERIFIED",
            conclusion="total_minutes 是正式唯一累计时间，UI 暂停/倍速经计时器推进经济并完整往返；目前只有经济进入正式调度。",
            formal_entry=["FormalWorldApplication._advance_simulation_minutes"],
            production_files=["scripts/formal/formal_world_simulation.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "scripts/v2_2/v2_datetime.gd"],
            key_symbols=["FormalWorldSimulation.total_minutes", "FormalWorldSimulation.advance_minutes", "holographic_workspace_runtime._on_clock_timer_timeout"],
            data=[],
            state="FormalWorldSimulation owns total_minutes; inherited UI owns pause/speed controls; economy reads an injected authoritative hour.",
            writers=["FormalWorldSimulation.advance_minutes", "FormalWorldSimulation.restore_persistent_state", "holographic_workspace_runtime._activate_button"],
            readers=["FormalWorldApplication", "FormalWorldEconomyService", "formal time HUD"],
            lifecycle="Initialized at scene ready, advanced by ClockTimer while unpaused, restored from formal save.",
            persistence="total_minutes plus validated minute remainder and economy hour.",
            ui="Date/time panel, pause, 1x/2x/4x controls.",
            tests=["tests/variable_state/formal_time_stable_contract_test.gd", "tests/variable_state/formal_time_known_defects_test.gd", "tests/formal/formal_world_integration_test.gd"],
            ci=[".github/workflows/formal-time-behavior-baseline.yml"],
            documents=["docs/refactors/formal_time_behavior_baseline.md", "docs/refactors/formal_time_single_source.md"],
            dependencies=["A", "F"],
            dependents=["F", "K", "L"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="VERIFIED", player_surface="VERIFIED",
                state_ownership="VERIFIED", persistence="VERIFIED",
                causal_feedback="VERIFIED", data_readiness="VERIFIED",
                verification="VERIFIED", observability="PARTIAL",
                maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E005", "E006", "E012"],
                implementation=["E005", "E006"],
                runtime_reachability=["E004", "E005"],
                integration=["E006", "E009"],
                player_surface=["E005"],
                state_ownership=["E006", "E012"],
                lifecycle=["E003", "E005", "E006"],
                persistence=["E007", "E012"],
                causal_feedback=["E006", "E009"],
                data_readiness=["E006"],
                verification=["E011", "E012", "E049"],
                observability=["E016"],
                maintainability=["E030", "E040"],
            ),
        ),
        _system(
            system_id="C",
            name="世界状态与地理空间",
            maturity="PLAYER_LOOP_PARTIAL",
            conclusion="历史半球、国家/行政区/城市浏览与经济查询可用；它是导航投影，不是权威玩家位置、路径或旅行系统，导航状态也不持久化。",
            formal_entry=["FormalWorldApplication inherited holographic workspace draw/input chain"],
            production_files=["scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_history.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"],
            key_symbols=["selected_country_id", "space_level", "_rebuild_historical_political_world", "_selected_polity_entity_id"],
            data=["data/world_map/historical/cshapes_1900_snapshot.json", "data/world_map/historical/political_units_1900.json", "data/world_map/world_admin1.json", "data/world_map/cities.json"],
            state="Multiple UI selection IDs and geometry/index caches; political/economy records are queried separately.",
            writers=["holographic workspace input/navigation methods"],
            readers=["map drawing methods", "FormalWorldApplication._selected_polity_entity_id"],
            lifecycle="Loaded and indexed during scene ready; caches rebuild on navigation/zoom; no simulated travel lifecycle.",
            persistence="No map selection, player location or travel state in formal save.",
            ui="Rotatable historical hemisphere, political focus, admin list, modern reference lower layers and city/institution browsing.",
            tests=["tests/formal/formal_world_integration_test.gd", "tests/v2_3/v2_3_player_interface_test.gd"],
            ci=[".github/workflows/release-ui-integration.yml"],
            documents=["docs/MAP_DATA_AND_RENDERING.md", "docs/SPATIAL_REACH_TRAVEL_AND_COMMUNICATION.md"],
            dependencies=["A", "M"],
            dependents=["F", "K"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="PARTIAL", player_surface="VERIFIED",
                state_ownership="PARTIAL", lifecycle="PARTIAL",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="PARTIAL", maintainability="MISSING",
            ),
            dimension_evidence=_evidence_map(
                ["E017", "E043"],
                implementation=["E003", "E017"],
                runtime_reachability=["E003", "E040"],
                integration=["E044"],
                player_surface=["E017", "E048"],
                state_ownership=["E017", "E046"],
                lifecycle=["E017"],
                persistence=["E018"],
                causal_feedback=["E039", "E044"],
                data_readiness=["E028", "E029", "E043", "E052"],
                verification=["E011", "E048", "E050"],
                observability=["E016"],
                maintainability=["E040", "E043"],
            ),
        ),
        _system(
            system_id="D",
            name="玩家与角色",
            maturity="IMPLEMENTED_ISOLATED",
            conclusion="正式入口只有静态人物档案和视角切换；权威 CharacterData/GameSession/行动栈存在于仓库但未接入正式组合根。",
            formal_entry=["holographic_workspace_runtime._load_all_data -> characters.json"],
            production_files=["scripts/core/models/character_data.gd", "scripts/character/game_session_service.gd", "scripts/action/action_service.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"],
            key_symbols=["active_character_key", "GameSessionService.player_character", "ActionService.start_action"],
            data=["data/world_map/characters.json", "data/characters/character_generation.json"],
            state="Formal UI profile key conflicts conceptually with isolated authoritative player object; no formal needs/health/assets/action state.",
            writers=["formal UI switch_character only", "isolated GameSessionService and ActionService"],
            readers=["formal character HUD", "isolated core systems/tests"],
            lifecycle="Formal profile loaded once; isolated core player lifecycle is not composed.",
            persistence="Static profile/UI selection absent from formal save; isolated core player has a separate save protocol.",
            ui="Read-only static character card and viewpoint switch.",
            tests=["tests/codex_audit_regression.gd", "tests/p0_r1_player_journey_current.gd"],
            ci=["tools/run_validation.ps1 retained-service scope"],
            documents=["docs/PLAYER_LAYERS_AND_PERMISSIONS.md", "docs/TIME_ATTENTION_AND_ACTIVITY_MODEL.md"],
            dependencies=["A", "B", "H"],
            dependents=["E", "F", "I"],
            statuses=_status_map(
                implementation="PARTIAL", runtime_reachability="PARTIAL",
                integration="MISSING", player_surface="PARTIAL",
                state_ownership="MISSING", lifecycle="MISSING",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="MISSING", maintainability="MISSING",
            ),
            dimension_evidence=_evidence_map(
                ["E019", "E020", "E021"],
                implementation=["E019", "E020", "E021"],
                runtime_reachability=["E019", "E032"],
                integration=["E032", "E039"],
                player_surface=["E019"],
                state_ownership=["E020", "E045", "E046"],
                lifecycle=["E019", "E020"],
                persistence=["E018", "E046"],
                causal_feedback=["E039"],
                data_readiness=["E019"],
                verification=["E042", "E050"],
                observability=["E016"],
                maintainability=["E040", "E046"],
            ),
        ),
        _system(
            system_id="E",
            name="家庭与社会",
            maturity="IMPLEMENTED_ISOLATED",
            conclusion="关系、社会、家庭/通信实现和测试分散于核心与 V2.x；正式世界仅显示静态人物/机构议程，没有关系变化—知识—行动—持久化链。",
            formal_entry=["static character and institution projections only"],
            production_files=["scripts/relationship/relationship_service.gd", "scripts/simulation/society_simulation_service.gd", "scripts/v2_2/v2_household_service.gd", "scripts/v2_3/communication_service.gd"],
            key_symbols=["RelationshipService.create_or_update", "SocietySimulationService.initialize", "V2HouseholdService", "CommunicationService"],
            data=["data/world_map/characters.json", "data/world_map/institutions.json", "data/v2_3/communication_channels.json"],
            state="No formal social owner; static UI projections coexist with isolated relationship/communication stores.",
            writers=["isolated services", "formal UI mark_read only"],
            readers=["formal static HUD", "isolated tests and legacy interfaces"],
            lifecycle="No formal social initialization or tick subscription.",
            persistence="Formal save excludes relationships, family, messages and knowledge.",
            ui="Static known-agenda list; no formal relationship or communication command.",
            tests=["tests/v2_3/v2_3_relationship_test.gd", "tests/v2_3/v2_3_communication_test.gd", "tests/v2_3/v2_3_social_sandbox_test.gd"],
            ci=["tools/run_validation.ps1 retained-service regressions"],
            documents=["docs/HOUSEHOLD_AND_FAMILY_MODEL.md", "docs/SOCIAL_ORGANIZATION_INSTITUTION_MODEL.md"],
            dependencies=["D", "H", "I"],
            dependents=["J"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="MISSING",
                integration="MISSING", player_surface="PARTIAL",
                state_ownership="MISSING", lifecycle="MISSING",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="MISSING", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E022", "E025", "E026"],
                implementation=["E022", "E025", "E026"],
                runtime_reachability=["E032"],
                integration=["E024", "E025"],
                player_surface=["E019", "E024"],
                state_ownership=["E024", "E025", "E046"],
                lifecycle=["E022", "E032"],
                persistence=["E018", "E025"],
                causal_feedback=["E024", "E039"],
                data_readiness=["E019", "E024"],
                verification=["E026", "E034", "E042"],
                observability=["E016"],
                maintainability=["E040", "E046"],
            ),
        ),
        _system(
            system_id="F",
            name="经济与市场",
            maturity="PLAYER_LOOP_PARTIAL",
            conclusion="国家聚合商品经济、价格、生产、消费、短缺运输和十年稳定性已正式接入；玩家、家庭、企业、劳动和政治反馈没有接入。",
            formal_entry=["FormalWorldSimulation.economy -> FormalWorldEconomyService"],
            production_files=["scripts/formal/formal_world_economy_service.gd", "scripts/alpha/alpha_historical_world_economy_data.gd"],
            key_symbols=["FormalWorldEconomyService.configure", "_settle_day", "_schedule_shortage_shipments", "world_summary"],
            data=["data/alpha/commodity_market_1900.json", "data/alpha/historical_world_economy_1900.json", "data/alpha/historical_transport_network_1900.json", "data/world_map/historical/major_economy_polity_crosswalk_1900.json"],
            state="FormalWorldEconomyService owns country_states, routes, shipments, history, indexes and settlement boundary.",
            writers=["FormalWorldEconomyService configure/settle/restore"],
            readers=["FormalWorldSimulation", "FormalWorldApplication polity/economy panel"],
            lifecycle="Configured at new/load initialization; settles at crossed hour/day boundaries; restores inside formal transaction.",
            persistence="Time-coupled economy schema v1-v3; direct outer file overwrite and last_day_index consistency gap.",
            ui="World fulfillment and selected-polity economic summary; no buy/work/produce/invest command.",
            tests=["tests/formal/formal_world_integration_test.gd", "tests/formal/formal_world_long_term_balance_test.gd"],
            ci=[".github/workflows/alpha-commodity-economy.yml", ".github/workflows/windows-prototype-release.yml"],
            documents=["docs/economy/formal_world_integration.md", "docs/economy/1900_economy_integration_phase2_validation.md"],
            dependencies=["B", "C", "M"],
            dependents=["A", "K", "L"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="VERIFIED", player_surface="PARTIAL",
                state_ownership="PARTIAL", lifecycle="VERIFIED",
                persistence="PARTIAL", causal_feedback="PARTIAL",
                data_readiness="PARTIAL", verification="VERIFIED",
                observability="PARTIAL", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E008", "E009", "E013"],
                implementation=["E008", "E009"],
                runtime_reachability=["E004", "E006"],
                integration=["E006", "E044"],
                player_surface=["E004", "E031", "E039"],
                state_ownership=["E010", "E031"],
                lifecycle=["E006", "E008", "E009"],
                persistence=["E007", "E010", "E023"],
                causal_feedback=["E009", "E039"],
                data_readiness=["E028", "E041"],
                verification=["E011", "E013", "E014"],
                observability=["E016"],
                maintainability=["E030", "E040", "E046"],
            ),
        ),
        _system(
            system_id="G",
            name="政治、法律与国家能力",
            maturity="IMPLEMENTED_ISOLATED",
            conclusion="正式运行展示 151 个政治单元、控制/关系和静态概况，但没有政治变迁、法律、政策、国家能力或玩家响应模拟；旧 Alpha 政治代码未正式接入。",
            formal_entry=["historical political map and polity summary projection"],
            production_files=["scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd", "scripts/formal/formal_world_economy_service.gd", "scripts/alpha/alpha_politics_service.gd"],
            key_symbols=["_build_dated_historical_unit", "polity_summary", "AlphaPoliticsService"],
            data=["data/world_map/historical/political_units_1900.json", "data/world_map/historical/major_state_profiles_1900.json", "data/alpha/politics.json"],
            state="Political records are mostly immutable projections; controller/sovereign semantics are not separated; no formal political mutation owner.",
            writers=["formal data loaders only", "isolated AlphaPoliticsService"],
            readers=["historical map UI", "formal polity/economy panel"],
            lifecycle="Loaded at scene/economy initialization; no formal political tick or transition lifecycle.",
            persistence="No mutable formal politics/law state in save.",
            ui="Political borders, status, relationship, controller and state profile text.",
            tests=["tests/formal/formal_world_integration_test.gd", "tests/alpha/alpha_organization_politics_test.gd"],
            ci=["formal tests plus quarantined Alpha fixture"],
            documents=["docs/POLITICS_COALITIONS_AND_LEGITIMACY.md", "docs/LAW_RIGHTS_AND_STATE_CAPACITY.md"],
            dependencies=["C", "M"],
            dependents=["F", "H", "J"],
            statuses=_status_map(
                implementation="PARTIAL", runtime_reachability="PARTIAL",
                integration="PARTIAL", player_surface="PARTIAL",
                state_ownership="MISSING", lifecycle="MISSING",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="PARTIAL", maintainability="MISSING",
            ),
            dimension_evidence=_evidence_map(
                ["E027", "E052"],
                implementation=["E027", "E052"],
                runtime_reachability=["E008", "E017"],
                integration=["E044"],
                player_surface=["E004", "E017"],
                state_ownership=["E027", "E046"],
                lifecycle=["E032", "E039"],
                persistence=["E018"],
                causal_feedback=["E039"],
                data_readiness=["E028", "E029", "E043", "E052"],
                verification=["E011", "E034"],
                observability=["E016"],
                maintainability=["E027", "E040"],
            ),
        ),
        _system(
            system_id="H",
            name="组织、机构与职业",
            maturity="IMPLEMENTED_ISOLATED",
            conclusion="正式 UI 读取静态机构，核心组织/职位/权限服务与 Alpha 企业存在但不可达；没有正式雇佣、职业、成员决策或组织持久化。",
            formal_entry=["holographic_workspace_runtime institutions projection"],
            production_files=["scripts/organization/organization_service.gd", "scripts/simulation/society_simulation_service.gd", "scripts/alpha/alpha_enterprise_service.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"],
            key_symbols=["OrganizationService.join_organization", "assign_position", "_seed_world_events"],
            data=["data/world_map/institutions.json", "data/world_map/organizations.json"],
            state="Static institution dictionaries in formal UI; isolated OrganizationService owns mutable membership/positions elsewhere.",
            writers=["formal data loader only", "isolated OrganizationService"],
            readers=["formal map/HUD", "isolated society/action systems"],
            lifecycle="Static load only in formal runtime.",
            persistence="No formal organization/career state; isolated service has separate persistence.",
            ui="Inspect institution and agenda; no join/work/permission/decision command.",
            tests=["tests/alpha/alpha_labor_enterprise_test.gd", "tests/test_runner.gd organization tests"],
            ci=["quarantined/retained service regressions only"],
            documents=["docs/SOCIAL_ORGANIZATION_INSTITUTION_MODEL.md", "docs/STATE_AND_LIFE_ECONOMY.md"],
            dependencies=["D", "E", "G"],
            dependents=["I", "J"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="PARTIAL",
                integration="MISSING", player_surface="PARTIAL",
                state_ownership="MISSING", lifecycle="MISSING",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="MISSING", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E022", "E024"],
                implementation=["E022"],
                runtime_reachability=["E017", "E032"],
                integration=["E024", "E032"],
                player_surface=["E017", "E024"],
                state_ownership=["E022", "E024", "E046"],
                lifecycle=["E017", "E032"],
                persistence=["E018"],
                causal_feedback=["E024", "E039"],
                data_readiness=["E024"],
                verification=["E034", "E042"],
                observability=["E016"],
                maintainability=["E040", "E046"],
            ),
        ),
        _system(
            system_id="I",
            name="信息、知识、媒体与事件",
            maturity="IMPLEMENTED_ISOLATED",
            conclusion="正式界面显示由机构数据播种的事件并可标记已读；权威 WorldActivity、V2.3 知识/通信存在但未接入，事件没有模拟后果或持久化。",
            formal_entry=["holographic_workspace_runtime._seed_world_events"],
            production_files=["scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd", "scripts/simulation/world_activity_service.gd", "scripts/v2_3/knowledge_service.gd", "scripts/v2_3/communication_service.gd"],
            key_symbols=["_world_events", "activity_unread", "WorldActivityService.add_event", "KnowledgeService"],
            data=["data/world_map/institutions.json", "data/v2_3/knowledge_rules.json", "data/v2_3/communication_channels.json"],
            state="UI-owned seeded events/unread count plus isolated authoritative candidates; no selected formal owner.",
            writers=["formal UI seed/mark_read", "isolated WorldActivity/Knowledge/Communication services"],
            readers=["formal activity HUD", "isolated legacy interfaces/tests"],
            lifecycle="Seed once at ready; no formal event trigger or propagation schedule.",
            persistence="Formal save excludes events, knowledge, communication and unread state.",
            ui="Known institution agendas and event location; no communication or knowledge-based action.",
            tests=["tests/v2_3/v2_3_knowledge_test.gd", "tests/v2_3/v2_3_communication_test.gd"],
            ci=["retained service regressions only"],
            documents=["docs/INFORMATION_KNOWLEDGE_AND_MEDIA.md", "docs/EVENT_AND_AI_SIMULATION.md"],
            dependencies=["E", "H"],
            dependents=["J", "K"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="PARTIAL",
                integration="MISSING", player_surface="PARTIAL",
                state_ownership="MISSING", lifecycle="PARTIAL",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="PARTIAL", maintainability="MISSING",
            ),
            dimension_evidence=_evidence_map(
                ["E024", "E025", "E026"],
                implementation=["E024", "E025", "E026"],
                runtime_reachability=["E024", "E032"],
                integration=["E024", "E025"],
                player_surface=["E024"],
                state_ownership=["E024", "E025", "E046"],
                lifecycle=["E024"],
                persistence=["E018", "E025"],
                causal_feedback=["E024", "E039"],
                data_readiness=["E024"],
                verification=["E026", "E034"],
                observability=["E016", "E024"],
                maintainability=["E040", "E046"],
            ),
        ),
        _system(
            system_id="J",
            name="AI 与自主模拟",
            maturity="IMPLEMENTED_ISOLATED",
            conclusion="核心 SimpleAiService、社会 AI 和 Alpha AI 有实现/测试，但正式运行图没有 AI owner、tick、写入或玩家可见后果。",
            formal_entry=[],
            production_files=["scripts/ai/simple_ai_service.gd", "scripts/ai/ai_state_data.gd", "scripts/simulation/society_simulation_service.gd", "scripts/alpha/alpha_ai_service.gd"],
            key_symbols=["SimpleAiService.run_daily_decisions", "SocietySimulationService._execute_ai_daily_actions", "AlphaAiService"],
            data=["data/balance/society_rules.json", "data/alpha/presets.json"],
            state="No formal AI state; isolated services own per-character or Alpha AI states.",
            writers=["isolated AI/society services"],
            readers=["isolated tests and legacy products"],
            lifecycle="No formal registration, budget, decision schedule or shutdown.",
            persistence="Formal save excludes AI; isolated core/Alpha schemas differ.",
            ui="No formal AI intent, action or consequence surface.",
            tests=["tests/alpha/alpha_ai_economy_stability_test.gd", "tests/test_runner.gd society AI tests"],
            ci=["quarantined AI fixture only"],
            documents=["docs/EVENT_AND_AI_SIMULATION.md", "docs/PERFORMANCE_BUDGET.md"],
            dependencies=["B", "D", "E", "G", "H", "I"],
            dependents=[],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="MISSING",
                integration="MISSING", player_surface="MISSING",
                state_ownership="UNKNOWN", lifecycle="MISSING",
                persistence="MISSING", causal_feedback="MISSING",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="MISSING", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E022", "E032"],
                implementation=["E022"],
                runtime_reachability=["E032"],
                integration=["E032", "E039"],
                player_surface=["E039"],
                state_ownership=["E022", "E046"],
                lifecycle=["E022", "E032"],
                persistence=["E018", "E046"],
                causal_feedback=["E039"],
                data_readiness=["E022"],
                verification=["E034", "E042"],
                observability=["E016"],
                maintainability=["E040", "E046"],
            ),
        ),
        _system(
            system_id="K",
            name="UI、反馈与可操作性",
            maturity="PLAYER_LOOP_PARTIAL",
            conclusion="正式 1280x720 标题、历史半球、时间与政经查询可见可操作；多数操作只改变 UI 状态，只有时间/保存/读取进入正式模拟。",
            formal_entry=["formal_world_menu.tscn", "formal_world_main.tscn"],
            production_files=["scripts/formal/formal_world_menu.gd", "scripts/formal/formal_world_application.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"],
            key_symbols=["_draw", "_activate_button", "_gui_input", "_draw_formal_polity_panel"],
            data=["data/world_map/*", "data/world_map/historical/*"],
            state="Deep inherited UI selection/cache state plus a _last_summary projection and economy panel flag.",
            writers=["input handlers and button actions", "FormalWorldApplication refresh methods"],
            readers=["draw methods"],
            lifecycle="Scene-ready data load, controlled timer redraws and interaction cache invalidation.",
            persistence="Only simulation time/economy persists; UI state does not.",
            ui="Title, map navigation, info/HUD panels, time controls, polity economy, save/load and visible data errors.",
            tests=["tests/formal/formal_world_ui_capture.gd", "tests/formal/formal_world_integration_test.gd", "tests/v2_3/v2_3_player_interface_test.gd"],
            ci=[".github/workflows/release-ui-integration.yml"],
            documents=["docs/UI_INFORMATION_ARCHITECTURE.md", "docs/ui_spikes/holographic_workspace_spike.md"],
            dependencies=["A", "B", "C", "F", "I", "M"],
            dependents=["O"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="PARTIAL", player_surface="VERIFIED",
                state_ownership="PARTIAL", lifecycle="PARTIAL",
                persistence="MISSING", causal_feedback="PARTIAL",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="PARTIAL", maintainability="MISSING",
            ),
            dimension_evidence=_evidence_map(
                ["E003", "E004", "E017"],
                implementation=["E002", "E003", "E004", "E017"],
                runtime_reachability=["E001", "E011"],
                integration=["E039", "E044"],
                player_surface=["E005", "E017", "E038"],
                state_ownership=["E018", "E024", "E045"],
                lifecycle=["E003", "E005", "E017"],
                persistence=["E018"],
                causal_feedback=["E009", "E039", "E044"],
                data_readiness=["E029", "E043"],
                verification=["E011", "E015", "E048", "E050"],
                observability=["E016"],
                maintainability=["E040"],
            ),
        ),
        _system(
            system_id="L",
            name="保存、加载与兼容性",
            maturity="PLAYER_LOOP_PARTIAL",
            conclusion="正式时间/经济磁盘往返和 v1/v2 兼容已测试；文件非原子覆盖，范围不含玩家/导航/社会/政治，且与核心原子存档线并行。",
            formal_entry=["FormalWorldMenu._formal_save_exists", "FormalWorldSimulation.save_to_user/load_from_user"],
            production_files=["scripts/formal/formal_world_simulation.gd", "scripts/formal/formal_world_economy_service.gd", "scripts/save/game_save_service.gd", "scripts/save/atomic_json_file_store.gd"],
            key_symbols=["SAVE_PATH", "SCHEMA_ID", "get_persistent_state", "restore_persistent_state"],
            data=[],
            state="formal_world_simulation_v2 wraps formal economy v1-v3; separate core/V2/Alpha protocols remain.",
            writers=["FormalWorldSimulation.save_to_user"],
            readers=["FormalWorldMenu", "FormalWorldSimulation.load_from_user"],
            lifecycle="Auto-detect at menu, initialize fresh target, validate then commit restore; no corrupt-file quarantine/backup path.",
            persistence="Complete only for formal time/economy state.",
            ui="Auto continue plus F5/F9 and on-screen save/load result text.",
            tests=["tests/variable_state/formal_time_stable_contract_test.gd", "tests/variable_state/formal_time_known_defects_test.gd", "tests/formal/formal_world_long_term_balance_test.gd"],
            ci=[".github/workflows/formal-time-behavior-baseline.yml", ".github/workflows/windows-prototype-release.yml"],
            documents=["docs/SAVE_FORMAT.md", "docs/refactors/formal_time_single_source.md", "docs/audits/variable_state_audit_20260803.md"],
            dependencies=["A", "B", "F"],
            dependents=["A", "O"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="PARTIAL", player_surface="VERIFIED",
                state_ownership="PARTIAL", lifecycle="PARTIAL",
                persistence="PARTIAL", causal_feedback="NOT_APPLICABLE",
                data_readiness="VERIFIED", verification="VERIFIED",
                observability="PARTIAL", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E007", "E012", "E018"],
                implementation=["E002", "E007"],
                runtime_reachability=["E002", "E004"],
                integration=["E007", "E018", "E046"],
                player_surface=["E004", "E038"],
                state_ownership=["E007", "E023", "E046"],
                lifecycle=["E002", "E004", "E007"],
                persistence=["E007", "E010", "E018", "E023"],
                causal_feedback=["E007"],
                data_readiness=["E007", "E012"],
                verification=["E011", "E012", "E013", "E049"],
                observability=["E004", "E016"],
                maintainability=["E023", "E046", "E047"],
            ),
        ),
        _system(
            system_id="M",
            name="数据、内容与历史基线",
            maturity="INTEGRATED_VERIFIED",
            conclusion="正式地图/经济数据有 schema、来源、覆盖和运行时校验并真实加载；日期口径、bounded estimates、现代下级行政参考及非商业许可边界仍未形成统一发布契约。",
            formal_entry=["formal map data loaders", "FormalWorldEconomyService.configure"],
            production_files=["scripts/alpha/alpha_historical_world_economy_data.gd", "scripts/formal/formal_world_economy_service.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"],
            key_symbols=["AlphaHistoricalWorldEconomyData.configure", "FormalWorldEconomyService._read_document", "_validate_historical_evidence"],
            data=["data/alpha/*1900*.json", "data/world_map/historical/*.json", "data/world_map/*.json"],
            state="Versioned source documents are loaded into separate map/UI and economy caches/indexes.",
            writers=["offline generators only; runtime loaders duplicate into memory"],
            readers=["formal map UI", "formal economy"],
            lifecycle="Loaded and validated during scene/economy initialization; immutable during session.",
            persistence="Source data is packaged input; mutable economy derived from it is saved separately.",
            ui="Source notices, political/admin layers, flags and confidence/admission status.",
            tests=["tests/alpha/alpha_historical_world_economy_data_test.gd", "tests/formal/formal_world_integration_test.gd"],
            ci=[".github/workflows/alpha-commodity-economy.yml", ".github/workflows/windows-prototype-release.yml"],
            documents=["docs/economy/1900_world_data_methodology.md", "docs/economy/1900_world_data_status.md", "docs/MAP_DATA_AND_RENDERING.md"],
            dependencies=[],
            dependents=["C", "F", "G", "K", "O"],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="VERIFIED", player_surface="PARTIAL",
                state_ownership="PARTIAL", lifecycle="VERIFIED",
                persistence="NOT_APPLICABLE", causal_feedback="PARTIAL",
                data_readiness="PARTIAL", verification="VERIFIED",
                observability="PARTIAL", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E008", "E028", "E041", "E052"],
                implementation=["E008", "E041"],
                runtime_reachability=["E008", "E017"],
                integration=["E008", "E044"],
                player_surface=["E004", "E043"],
                state_ownership=["E008", "E017", "E046"],
                lifecycle=["E008", "E017", "E041"],
                persistence=["E007"],
                causal_feedback=["E009", "E044"],
                data_readiness=["E028", "E029", "E041", "E043", "E052"],
                verification=["E011", "E013", "E014"],
                observability=["E016", "E041"],
                maintainability=["E030", "E040", "E043"],
            ),
        ),
        _system(
            system_id="N",
            name="性能、稳定性与可观测性",
            maturity="INTEGRATED_VERIFIED",
            conclusion="正式经济有十年数值/耗时/存档大小门禁和 CI 日志，UI 数据错误可见；缺少完整产品三年旅程、内存/泄漏、资源、因果追踪和发布崩溃诊断。",
            formal_entry=["formal timer/economy loop", "CI validation entries"],
            production_files=["scripts/formal/formal_world_economy_service.gd", "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"],
            key_symbols=["HISTORY_LIMIT", "MAX_SHIPMENTS_PER_DAY", "_draw_data_errors"],
            data=[],
            state="Bounded economy queues/history plus transient UI error strings; no production telemetry owner.",
            writers=["formal economy", "UI data loader"],
            readers=["tests", "UI error panel", "CI logs"],
            lifecycle="Runtime bounds apply continuously; verification runs headless in CI/local clone.",
            persistence="Performance metrics/logs are not product state; economy history is bounded and saved.",
            ui="Only data errors and current summaries; no diagnostics panel for formal product failures.",
            tests=["tests/formal/formal_world_long_term_balance_test.gd", "tests/formal/formal_world_integration_test.gd"],
            ci=[".github/workflows/windows-prototype-release.yml", ".github/workflows/release-ui-integration.yml"],
            documents=["docs/PERFORMANCE_BUDGET.md", "docs/performance/formal_time_d01_validation.md"],
            dependencies=["B", "F", "K"],
            dependents=["O"],
            statuses=_status_map(
                implementation="PARTIAL", runtime_reachability="PARTIAL",
                integration="PARTIAL", player_surface="PARTIAL",
                state_ownership="PARTIAL", lifecycle="PARTIAL",
                persistence="NOT_APPLICABLE", causal_feedback="NOT_APPLICABLE",
                data_readiness="VERIFIED", verification="VERIFIED",
                observability="PARTIAL", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E013", "E014", "E016"],
                implementation=["E009", "E013", "E016"],
                runtime_reachability=["E016"],
                integration=["E013", "E014"],
                player_surface=["E016"],
                state_ownership=["E016", "E046"],
                lifecycle=["E013", "E014"],
                persistence=["E013"],
                causal_feedback=["E013"],
                data_readiness=["E013", "E041"],
                verification=["E013", "E014", "E015", "E034"],
                observability=["E013", "E016"],
                maintainability=["E034", "E040"],
            ),
        ),
        _system(
            system_id="O",
            name="构建、发布与产品交付",
            maturity="INTEGRATED_VERIFIED",
            conclusion="Windows 嵌入式导出、正式入口启动、测试和截图工作流已配置且可验证；安装后玩家 smoke、许可放行和完整数据/玩家闭环仍阻断正式产品发布。",
            formal_entry=["project.godot formal main scene", "Windows Desktop export preset"],
            production_files=["project.godot", "export_presets.cfg", ".github/workflows/windows-prototype-release.yml"],
            key_symbols=["application/run/main_scene", "preset.0", "validate-and-export"],
            data=["packaged res:// resources via embedded PCK"],
            state="Build identity is stamped in CI; no runtime account/network state.",
            writers=["CI build stamp and exporter"],
            readers=["Godot exporter", "Inno Setup workflow"],
            lifecycle="Checkout, stamp, import, tests, startup, export, installer, artifacts/release.",
            persistence="Not applicable to build state; product save quality remains a release dependency.",
            ui="Formal title/main scene and captured screenshots; no installed-package end-to-end player journey.",
            tests=["tests/formal/formal_world_integration_test.gd", "tests/formal/formal_world_long_term_balance_test.gd", "tests/formal/formal_world_ui_capture.gd"],
            ci=[".github/workflows/windows-prototype-release.yml", ".github/workflows/release-ui-integration.yml"],
            documents=["docs/P0_R1_VALIDATION.md", "docs/TEST_PLAN.md"],
            dependencies=["A", "K", "L", "M", "N"],
            dependents=[],
            statuses=_status_map(
                implementation="VERIFIED", runtime_reachability="VERIFIED",
                integration="VERIFIED", player_surface="PARTIAL",
                state_ownership="PARTIAL", lifecycle="PARTIAL",
                persistence="NOT_APPLICABLE", causal_feedback="NOT_APPLICABLE",
                data_readiness="PARTIAL", verification="PARTIAL",
                observability="PARTIAL", maintainability="PARTIAL",
            ),
            dimension_evidence=_evidence_map(
                ["E001", "E014", "E037"],
                implementation=["E014", "E037"],
                runtime_reachability=["E001", "E014"],
                integration=["E014", "E015"],
                player_surface=["E015", "E038", "E048"],
                state_ownership=["E014"],
                lifecycle=["E014"],
                persistence=["E007", "E018"],
                causal_feedback=["E014"],
                data_readiness=["E028", "E029", "E041"],
                verification=["E014", "E015", "E048"],
                observability=["E014", "E016"],
                maintainability=["E034", "E040"],
            ),
        ),
    ]
    return sorted(systems, key=lambda row: str(row["id"]))


def _loop_step(
    step: str, status: str, evidence: Sequence[str], conclusion: str
) -> dict[str, object]:
    if status not in LOOP_STATUSES:
        raise AuditError(f"invalid loop status: {status}")
    if not evidence:
        raise AuditError(f"loop step has no evidence: {step}")
    return {
        "step": step,
        "status": status,
        "evidence": sorted(set(evidence)),
        "conclusion": conclusion,
    }


def reviewed_product_loops() -> list[dict[str, object]]:
    loops = [
        {
            "id": "LOOP-1",
            "name": "启动—操作—保存—重新加载",
            "overall_status": "PARTIAL",
            "steps": [
                _loop_step("启动", "VERIFIED", ["E001", "E014"], "正式 main scene 可启动。"),
                _loop_step("正式菜单", "VERIFIED", ["E002", "E038"], "Any-key 菜单可达。"),
                _loop_step("新游戏", "PARTIAL", ["E002", "E038"], "仅在没有正式存档时自动 new，没有显式选择。"),
                _loop_step("世界初始化", "VERIFIED", ["E004", "E008", "E011"], "正式时间/政治目录/经济初始化经测试。"),
                _loop_step("玩家进入世界", "PARTIAL", ["E019", "E020", "E032"], "进入地图界面，但没有权威玩家实体。"),
                _loop_step("时间推进", "VERIFIED", ["E005", "E006", "E012"], "暂停/倍速驱动唯一正式时间。"),
                _loop_step("玩家执行操作", "PARTIAL", ["E039"], "仅时间、导航、保存/读取和面板操作；没有人物业务行动。"),
                _loop_step("世界状态改变", "PARTIAL", ["E009", "E039"], "时间会改变经济，玩家业务操作不会。"),
                _loop_step("UI 反馈", "PARTIAL", ["E004", "E016", "E044"], "时间/经济/错误有反馈，人物因果没有。"),
                _loop_step("保存", "PARTIAL", ["E007", "E018", "E023"], "时间/经济可保存，范围和耐久性不完整。"),
                _loop_step("退出", "MISSING", ["E038"], "没有正式退出或保存后退出入口。"),
                _loop_step("重新加载", "PARTIAL", ["E002", "E004", "E012"], "自动继续和 F9 可恢复有效存档。"),
                _loop_step("状态继续", "PARTIAL", ["E012", "E018"], "只有时间/经济继续，玩家与 UI 会话状态不存在或未保存。"),
            ],
            "judgement_origin": "reviewed",
        },
        {
            "id": "LOOP-2",
            "name": "生活—工作—市场—长期决策",
            "overall_status": "MISSING",
            "steps": [
                _loop_step("时间推进", "VERIFIED", ["E005", "E006"], "正式时间可推进。"),
                _loop_step("玩家需求或生活状态变化", "MISSING", ["E019", "E031", "E039"], "正式组合根无玩家生活状态。"),
                _loop_step("工作、收入或消费", "MISSING", ["E031", "E039"], "正式经济没有个人/家庭/企业账本或职业命令。"),
                _loop_step("市场或经济状态变化", "VERIFIED", ["E009", "E013"], "国家聚合市场会随日结变化。"),
                _loop_step("玩家后续决策", "MISSING", ["E021", "E032", "E039"], "隔离行动服务未接入正式经济。"),
                _loop_step("长期结果", "PARTIAL", ["E013"], "只证明聚合经济十年稳定，不是玩家长期生活结果。"),
            ],
            "judgement_origin": "reviewed",
        },
        {
            "id": "LOOP-3",
            "name": "移动/旅行—地理上下文—成本—恢复",
            "overall_status": "MISSING",
            "steps": [
                _loop_step("玩家移动或旅行", "MISSING", ["E017", "E026", "E032"], "地图点击是视图导航，旅行服务仅在 V2.3。"),
                _loop_step("地理状态变化", "MISSING", ["E017", "E039"], "没有权威 player location 写入。"),
                _loop_step("地点、城市或国家上下文变化", "PARTIAL", ["E017"], "UI 上下文可浏览，但不改变玩家实体。"),
                _loop_step("可用操作变化", "MISSING", ["E021", "E032", "E039"], "正式操作集合不依位置变化。"),
                _loop_step("成本或时间变化", "MISSING", ["E009", "E026", "E039"], "运输只属于国家货运，玩家旅行成本未接入。"),
                _loop_step("保存恢复", "MISSING", ["E018"], "正式存档没有玩家位置/旅行/UI 地理状态。"),
            ],
            "judgement_origin": "reviewed",
        },
        {
            "id": "LOOP-4",
            "name": "社会/通信—知识—行动—后果—持久化",
            "overall_status": "MISSING",
            "steps": [
                _loop_step("社会关系或通信", "MISSING", ["E022", "E026", "E032"], "实现存在但正式不可达。"),
                _loop_step("信息或知识变化", "PARTIAL", ["E024", "E025"], "UI 仅维护静态事件未读，未连接知识服务。"),
                _loop_step("行动选择变化", "MISSING", ["E021", "E024", "E039"], "事件/知识不影响正式行动选择。"),
                _loop_step("可观察后果", "MISSING", ["E024", "E039"], "播种事件没有模拟后果。"),
                _loop_step("持久化", "MISSING", ["E018", "E025"], "正式存档排除社会/信息状态。"),
            ],
            "judgement_origin": "reviewed",
        },
        {
            "id": "LOOP-5",
            "name": "非玩家变化—玩家获知—应对—世界反馈",
            "overall_status": "PARTIAL",
            "steps": [
                _loop_step("政治、组织、经济或 AI 的非玩家变化", "PARTIAL", ["E009", "E022", "E032"], "只有正式经济会自主变化。"),
                _loop_step("世界状态变化", "VERIFIED", ["E009", "E013"], "经济库存、价格、运输和摘要随时间变化。"),
                _loop_step("玩家能够获知", "PARTIAL", ["E004", "E044"], "玩家可查看选择政权摘要，但无消息因果追踪。"),
                _loop_step("玩家能够应对", "MISSING", ["E039"], "没有正式人物/政治/经济应对命令。"),
                _loop_step("后续世界反馈", "MISSING", ["E039"], "没有玩家响应写回世界再反馈的链。"),
            ],
            "judgement_origin": "reviewed",
        },
    ]
    return sorted(loops, key=lambda row: str(row["id"]))


def _gap(
    gap_id: str,
    system: str,
    priority: str,
    evidence: Sequence[str],
    user_impact: str,
    technical_impact: str,
    dependencies: Sequence[str],
    risk: str,
    acceptance: Sequence[str],
    recommended_order: int,
    blocks_playable_loop: bool,
    blocks_formal_release: bool,
) -> dict[str, object]:
    if priority not in PRIORITIES:
        raise AuditError(f"invalid gap priority: {priority}")
    return {
        "id": gap_id,
        "system": system,
        "priority": priority,
        "evidence": sorted(set(evidence)),
        "user_impact": user_impact,
        "technical_impact": technical_impact,
        "dependencies": sorted(set(dependencies)),
        "risk": risk,
        "acceptance_criteria": list(acceptance),
        "recommended_order": recommended_order,
        "blocks_playable_loop": blocks_playable_loop,
        "blocks_formal_release": blocks_formal_release,
        "judgement_origin": "reviewed",
    }


def reviewed_gaps() -> list[dict[str, object]]:
    gaps = [
        _gap("FPSC-P0-001", "A/D/K", "P0", ["E019", "E020", "E021", "E032", "E039"], "玩家没有一个可持续的权威人物，也不能执行改变世界的业务行动。", "正式组合根缺少玩家身份、行动命令和事务边界。", [], "继续叠加 UI/系统会制造更多孤立状态。", ["正式会话只创建/恢复一个权威玩家实体", "至少一个生产行动经权威校验改变正式世界状态", "UI 只通过命令/查询访问该状态", "新建、推进、行动、反馈、保存、重启继续的自动旅程通过"], 1, True, True),
        _gap("FPSC-P0-002", "A/L", "P0", ["E007", "E018", "E046"], "即使保存成功，也不能恢复完整玩家/地图/社会会话。", "正式 schema 只覆盖时间和经济，其他状态没有 owner/恢复顺序。", ["FPSC-P0-001"], "引入玩家后若不先定快照契约会立即产生不可恢复状态。", ["列出正式会话全部持久/临时状态", "保存覆盖玩家、行动和必需上下文", "恢复顺序与失败回滚有事务测试", "重复状态和全局 ID 不变量验证通过"], 2, True, True),
        _gap("FPSC-P0-003", "L", "P0", ["E007", "E023"], "断电/中断可能损失唯一正式存档，损坏文件会反复触发自动续档。", "FormalWorldSimulation 直接 WRITE 覆盖，未使用已有原子存储/备份能力。", ["FPSC-P0-002"], "存档耐久性不足会破坏连续游玩。", ["临时文件写入、验证、原子替换和备份契约明确", "注入中断/损坏时保留最近有效存档", "菜单能隔离坏档并给出可操作恢复反馈", "保持 formal_world_simulation_v1/v2 兼容"], 3, True, True),
        _gap("FPSC-P0-004", "B/F/L", "P0", ["E010"], "特制或损坏存档可能跳过后续经济日结。", "_last_day_index 可独立于权威小时恢复且未验证一致性。", ["FPSC-P0-002"], "核心经济时间边界可能失真。", ["恢复时验证或从权威小时派生 last_day_index", "跨日前后、过大/过小值和旧 schema 回归通过", "失败恢复不修改当前正式状态"], 4, True, True),

        _gap("FPSC-P1-001", "D/F", "P1", ["E031", "E039"], "玩家需求、工作、收入、消费与市场无关。", "国家聚合经济没有个人/家庭/企业契约或玩家命令入口。", ["FPSC-P0-001", "FPSC-P0-002"], "经济会自行运行但无法形成生活决策。", ["选择一个最小个人生活经济状态 owner", "一条工作/消费行动影响个人与聚合经济", "反馈与存档往返可证明", "不复制国家经济账本"], 10, True, True),
        _gap("FPSC-P1-002", "C/D", "P1", ["E017", "E018", "E026", "E039"], "玩家不能移动或旅行，地图浏览不改变所在地或可用操作。", "V2.3 旅行服务与正式历史地图 ID/时间/存档没有契约。", ["FPSC-P0-001", "FPSC-P0-002"], "直接复用旧服务会造成 ID、状态和时间双写。", ["先定义正式 LocationId/RouteId 与政治单元 crosswalk", "移动命令权威改变玩家位置、时间和成本", "可用行动随上下文变化", "保存恢复同一旅程状态"], 11, True, True),
        _gap("FPSC-P1-003", "E/I/D", "P1", ["E022", "E024", "E025", "E026", "E039"], "关系/通信不会改变知识、行动或长期后果。", "多个隔离社会/知识 owner 未选择正式实现。", ["FPSC-P0-001", "FPSC-P0-002"], "复用前不定契约会重复事件、关系与消息状态。", ["选择唯一关系与知识 owner", "一条通信改变知识并影响行动可用性", "可观察后果和持久化回归通过"], 12, True, True),
        _gap("FPSC-P1-004", "I/K", "P1", ["E024", "E025"], "UI 展示的“事件”不是世界变化，玩家无法判断信息真假或因果。", "展示层播种事件和正式活动服务并存。", ["FPSC-P0-001"], "继续扩展 UI 事件会固化错误所有权。", ["正式事件 owner 与可见性规则确定", "UI 只读事件投影", "事件来源、触发、后果和因果 ID 可追踪", "未读/知识/事件保存边界明确"], 13, True, True),
        _gap("FPSC-P1-005", "G/H/J", "P1", ["E022", "E027", "E032", "E039"], "政治、组织和 AI 不会改变正式世界，也无法影响玩家。", "正式组合根没有这些系统的生命周期/写入契约。", ["FPSC-P0-001", "FPSC-P1-004"], "一次性接入全部旧实现会扩大耦合。", ["按政治/组织/AI 顺序逐一选择唯一 owner", "每阶段只有一个最小非玩家变化进入正式世界", "玩家能获知、应对并看到后续反馈", "每阶段独立存档与确定性回归"], 14, True, True),
        _gap("FPSC-P1-006", "A/D/E/H", "P1", ["E020", "E022", "E032", "E045", "E046"], "玩家身份、组织、关系和正式地图视角互不相认。", "FormalWorldSimulation 与核心 GameSession/Society 是两套未定义边界的组合根。", ["FPSC-P0-001"], "直接拼接将产生双玩家、双时间和双存档。", ["形成正式 session composition contract", "明确哪些核心服务复用、适配或继续隔离", "禁止 UI/legacy 服务持有第二份权威玩家事实"], 15, True, True),
        _gap("FPSC-P1-007", "C/F/G", "P1", ["E017", "E027", "E044"], "地图选中对象可读经济，但地图/政治变化不会驱动经济，反之亦然。", "政治单元、经济体、现代地理层和 UI 选择只通过查询 crosswalk 松散连接。", ["FPSC-P1-006"], "未来旅行/战争/贸易可能写入不同 ID 空间。", ["定义政治单元—经济体—地点的稳定 ID 契约", "至少一条地图变化与经济成本双向反馈通过", "状态一致性和保存恢复验证 crosswalk"], 16, True, True),
        _gap("FPSC-P1-008", "C/G/M", "P1", ["E027", "E028", "E029", "E043", "E052"], "1900-01-01 模拟显示 1900-03-12 快照并混用现代下级行政参考，法理/控制也不分。", "时间语义、地图层级和政治归属数据契约不统一。", [], "政治、旅行和存档后续开发会建立在含混历史语义上。", ["定义正式世界基准时点与快照适用规则", "sovereign/controller 字段和迁移策略明确", "历史/现代参考层在 UI 与数据 schema 可区分", "关键国家跨时点回归通过"], 17, False, True),
        _gap("FPSC-P1-009", "M/O", "P1", ["E028"], "当前历史边界数据可能限制商业发布方式。", "正式运行依赖的数据自述 commercial_use_allowed=false；发布策略未形成机器可检验门禁。", [], "错误发布可能产生许可合规风险。", ["由项目负责人完成许可/发行政策审查", "打包清单包含许可与归属", "商业发布时替换或获得适用授权", "CI 对禁止发行组合提供门禁"], 18, False, True),

        _gap("FPSC-P2-001", "A/C/K", "P2", ["E003", "E040"], "小改动可能跨 17 层继承产生难以预测的 UI/状态影响。", "正式入口直接建立在 ui_spikes 深继承链上。", ["FPSC-P0-001"], "维护者难以识别最终 override 与生命周期 owner。", ["先建立交互/视觉行为特征测试", "把正式组合与可复用视图边界显式化", "不在本任务中重写全部 UI", "正式入口不再依赖未建立正式所有权的 spike-provenance 文件"], 30, False, True),
        _gap("FPSC-P2-002", "N/O", "P2", ["E033", "E042", "E051"], "旧测试名称和大量检查会让维护者误以为完整玩家闭环仍受保护。", "tests/test_runner.gd 和旧旅程引用已删除场景且不在统一验证。", [], "回归覆盖声明不可信。", ["标注、隔离或替换过期测试入口", "所有正式测试资源引用存在", "统一验证只列出真实可运行的测试并说明隔离测试语义"], 31, False, True),
        _gap("FPSC-P2-003", "全局", "P2", ["E035", "E036"], "文档中的入口、完成状态与当前产品不一致。", "愿景、设计、旧里程碑和现有实现未分层。", [], "规划与评审容易把设计目标当成运行事实。", ["保留愿景但为重要声明标注事实级别", "ARCHITECTURE/TEST_PLAN/KNOWN_* 链接到本审计基线", "过期入口不再被称为正式"], 32, False, True),
        _gap("FPSC-P2-004", "N", "P2", ["E011", "E034", "E042", "E048", "E050"], "测试通过仍不能证明五条真实产品闭环。", "正式测试聚焦经济/时间/场景，retained 测试只证明孤立服务，截图不是交互旅程。", ["FPSC-P0-001"], "CI 绿色可能掩盖不可玩状态。", ["为每条正式产品路径建立逐步自动证据", "retained 服务测试明确不计正式成熟度", "至少一条 1280x720 真正玩家旅程进入统一验证"], 33, True, True),
        _gap("FPSC-P2-005", "A/F/L/N", "P2", ["E004", "E016"], "保存/加载失败只显示布尔结果，用户和维护者难以定位原因。", "正式运行缺少结构化错误、因果 ID、阶段和可导出诊断。", [], "现场故障不可复现。", ["初始化、结算、保存、恢复有稳定错误码/阶段", "正式日志有界且不输出逐小时洪水", "发布 smoke 可采集诊断而不含隐私/遥测"], 34, False, True),
        _gap("FPSC-P2-006", "N", "P2", ["E013", "E015"], "十年经济通过不代表完整产品长期稳定。", "没有正式 UI/玩家/社会/AI 三年运行、内存峰值、泄漏和资源生命周期门禁。", ["FPSC-P0-001"], "后续接入系统可能破坏性能而现有门禁不报警。", ["建立完整正式组合的 30 日/一年/三年基线", "记录 CPU、内存、队列、资源和存档大小", "公式变更使历史性能记录显式失效"], 35, False, True),
        _gap("FPSC-P2-007", "B/F/K/M", "P2", ["E030", "E040"], "目录名无法可靠区分正式、历史和试验实现。", "正式代码实际依赖 Alpha、V2 和 ui_spikes 命名空间。", [], "自动清理或维护判断可能误删正式依赖或误接旧系统。", ["为正式依赖建立显式模块/适配器清单", "路径迁移需独立行为等价任务", "禁止仅按目录名删除或判定完成"], 36, False, True),
        _gap("FPSC-P2-008", "L", "P2", ["E023", "E046", "E047"], "不同产品线存档协议难以判断哪一个是正式维护边界。", "正式、核心、V2.2、V2.3、Alpha 保存/迁移并行。", ["FPSC-P0-002"], "误复用迁移或字段会破坏兼容性。", ["正式 schema 注册表和 owner 唯一", "旧协议标注 LEGACY_REFERENCE/TEST_ONLY", "任何复用先通过适配/迁移契约与固定夹具"], 37, False, True),

        _gap("FPSC-P3-001", "C/M", "P3", ["E029", "E043"], "多数国家缺少可导航的 1900 下级行政几何。", "名称目录、现代 crosswalk 与历史几何覆盖不一致。", ["FPSC-P1-008"], "内容扩展前做会继续混合时点。", ["按来源/许可补齐优先国家几何", "UI 明确显示覆盖与置信状态", "不把现代参考静默升级为历史事实"], 50, False, False),
        _gap("FPSC-P3-002", "A/K", "P3", ["E016", "E038"], "菜单、空状态、坏档、退出和存档槽体验不足。", "正式表面只有自动 new/load 和简短状态文本。", ["FPSC-P0-003"], "先做美化会掩盖权威边界问题。", ["P0 会话/存档完成后补显式新建、继续、退出、错误恢复", "键鼠路径和空/错误状态 1280x720 验证"], 51, False, False),
        _gap("FPSC-P3-003", "F/G/H/I/J", "P3", ["E031", "E052"], "96 个背景政治单元和多数社会/政治内容只有展示或聚合层。", "正式高细节模拟与可玩层覆盖有限。", ["FPSC-P1-001", "FPSC-P1-005"], "在核心闭环前扩内容会扩大孤立数据。", ["先完成一个国家/人物完整闭环", "再按数据覆盖和性能预算扩展背景单元", "每批内容有运行、反馈、持久化证据"], 52, False, False),
    ]
    return sorted(gaps, key=lambda row: (int(row["recommended_order"]), str(row["id"])))


def reviewed_document_claims() -> list[dict[str, object]]:
    rows = [
        ("docs/GAME_VISION.md", "长期世界与人物愿景", "DESIGN_ONLY", ["E036"]),
        ("docs/PRODUCT_VISION.md", "玩家作为社会人物影响世界的产品方向", "DESIGN_ONLY", ["E036"]),
        ("docs/GAME_DESIGN.md", "人物、组织、社会、战争与经济形成可玩系统", "PARTIALLY_SUPPORTED", ["E009", "E019", "E032"]),
        ("docs/ARCHITECTURE.md", "scenes/menu/main_menu.tscn 是基础入口", "CONTRADICTED", ["E001", "E035"]),
        ("docs/DATA_MODEL.md", "核心 Character/Country/Region/Organization 模型描述当前产品状态", "PARTIALLY_SUPPORTED", ["E020", "E022", "E032"]),
        ("docs/PLANS.md", "早期里程碑与测试数量代表当前交付状态", "STALE", ["E033", "E034"]),
        ("docs/ROADMAP.md", "旧核心场景/里程碑是当前正式实现顺序", "STALE", ["E001", "E051"]),
        ("docs/KNOWN_GAPS.md", "列出的缺口完整反映当前正式半球", "PARTIALLY_SUPPORTED", ["E032", "E039"]),
        ("docs/KNOWN_ISSUES.md", "列出的已知问题覆盖当前正式入口风险", "PARTIALLY_SUPPORTED", ["E010", "E023", "E040"]),
        ("docs/SAVE_FORMAT.md", "核心 SAVE_VERSION=1 是当前正式产品存档", "CONTRADICTED", ["E007", "E046"]),
        ("docs/TEST_PLAN.md", "正式入口完整玩家旅程受当前自动验证保护", "CONTRADICTED", ["E034", "E042", "E051"]),
        ("docs/UI_INFORMATION_ARCHITECTURE.md", "玩家能够从 UI 访问完整人物/世界信息结构", "PARTIALLY_SUPPORTED", ["E017", "E019", "E039"]),
        ("docs/CAUSALITY_AND_PLAYER_FEEDBACK.md", "跨系统因果与玩家反馈目标", "DESIGN_ONLY", ["E039"]),
        ("docs/TIME_ATTENTION_AND_ACTIVITY_MODEL.md", "时间/注意力/活动设计完整进入正式产品", "PARTIALLY_SUPPORTED", ["E006", "E021", "E032"]),
        ("docs/STATE_AND_LIFE_ECONOMY.md", "生活经济、劳动、家庭预算与市场相连", "DESIGN_ONLY", ["E031", "E039"]),
        ("docs/HOUSEHOLD_AND_FAMILY_MODEL.md", "家庭与亲属模型", "DESIGN_ONLY", ["E022", "E032"]),
        ("docs/SOCIAL_ORGANIZATION_INSTITUTION_MODEL.md", "社会、组织与机构模型", "PARTIALLY_SUPPORTED", ["E022", "E024", "E032"]),
        ("docs/POLITICS_COALITIONS_AND_LEGITIMACY.md", "政治联盟与合法性模拟", "DESIGN_ONLY", ["E027", "E039"]),
        ("docs/LAW_RIGHTS_AND_STATE_CAPACITY.md", "法律、权利与国家能力模拟", "DESIGN_ONLY", ["E032", "E039"]),
        ("docs/INFORMATION_KNOWLEDGE_AND_MEDIA.md", "知识、通信与媒体进入玩家决策", "DESIGN_ONLY", ["E024", "E025", "E032"]),
        ("docs/EVENT_AND_AI_SIMULATION.md", "事件与 AI 形成正式因果循环", "DESIGN_ONLY", ["E022", "E024", "E032"]),
        ("docs/SPATIAL_REACH_TRAVEL_AND_COMMUNICATION.md", "空间、旅行与通信正式接入", "DESIGN_ONLY", ["E017", "E026", "E032"]),
        ("docs/MAP_DATA_AND_RENDERING.md", "地图数据与渲染覆盖", "PARTIALLY_SUPPORTED", ["E028", "E029", "E043", "E052"]),
        ("docs/ALPHA_SYSTEMS.md", "Alpha 入口/系统代表当前正式产品", "STALE", ["E001", "E030"]),
        ("docs/v2_2/V2_2_IMPLEMENTATION_STATUS.md", "V2.2 生活循环是当前正式产品", "STALE", ["E001", "E030"]),
        ("docs/v2_3/V2_3_IMPLEMENTATION_STATUS.md", "V2.3 社会/空间入口是当前正式产品", "STALE", ["E001", "E026", "E032"]),
        ("docs/SOCIAL_SANDBOX_CONFORMANCE_AUDIT_2026-07-20.md", "正式入口已形成社会行动闭环", "CONTRADICTED", ["E001", "E032", "E039"]),
        ("docs/ui_spikes/holographic_workspace_spike.md", "holographic workspace 仅是隔离视觉 spike", "CONTRADICTED", ["E003", "E040"]),
        ("docs/economy/formal_world_integration.md", "正式半球接入 151 政治单元与 50 经济体", "TEST_VERIFIED", ["E008", "E011", "E013"]),
        ("docs/economy/1900_economy_integration_phase2_validation.md", "正式聚合经济通过运行验证", "TEST_VERIFIED", ["E011", "E013"]),
        ("docs/economy/1900_world_data_methodology.md", "1900 经济数据来源/估计方法", "CODE_VERIFIED", ["E041"]),
        ("docs/economy/1900_world_data_status.md", "经济覆盖并非全部严格验证", "CODE_VERIFIED", ["E041"]),
        ("docs/refactors/formal_time_single_source.md", "正式时间单一来源与恢复契约", "TEST_VERIFIED", ["E006", "E012"]),
        ("docs/refactors/formal_time_behavior_baseline.md", "正式时间行为基线受 CI 保护", "TEST_VERIFIED", ["E012", "E049"]),
        ("docs/audits/variable_state_audit_20260803.md", "正式时间/经济/存档与 UI 状态所有权结论", "CODE_VERIFIED", ["E010", "E046", "E047"]),
        ("docs/refactors/variable_state_audit.md", "早期正式时间三重表示仍是当前缺陷", "STALE", ["E006", "E012"]),
    ]
    output = [
        {
            "document": document,
            "claim": claim,
            "classification": classification,
            "evidence": sorted(set(evidence)),
            "judgement_origin": "reviewed",
        }
        for document, claim, classification, evidence in rows
    ]
    return sorted(output, key=lambda row: (str(row["document"]), str(row["claim"])))


def reviewed_roadmap() -> dict[str, object]:
    return {
        "next_phase_single_recommended_task": {
            "title": "建立正式会话权威与完整持久化契约",
            "scope": (
                "以 FormalWorldSimulation 为唯一正式组合根，接入一个权威玩家实体、"
                "一个最小生产行动命令，并先定义覆盖玩家/行动/时间/经济的事务快照。"
            ),
            "must_not_do": (
                "不得恢复旧场景作为第二入口，不得一次性接入全部 V2/Alpha 社会系统，"
                "不得在 UI 中直接写模拟事实。"
            ),
            "definition_of_done": [
                "新建与继续游戏都只产生一个权威玩家实体",
                "至少一个玩家行动经权威重验改变正式状态并得到 UI 反馈",
                "完整状态保存、进程退出、重启加载后继续",
                "有效/无效/中断存档均通过事务与兼容回归",
            ],
            "acceptance_evidence": [
                "1280x720 自动玩家旅程",
                "正式组合根状态一致性回归",
                "磁盘故障注入与原子替换回归",
                "统一验证与 Codex 审计回归",
            ],
        },
        "p0_sequence": [
            "FPSC-P0-001 authoritative player/session/action boundary",
            "FPSC-P0-002 complete formal snapshot and restore order",
            "FPSC-P0-003 atomic durable file replacement and corrupt-save recovery",
            "FPSC-P0-004 economy settlement-boundary validation",
        ],
        "p1_sequence": [
            "FPSC-P1-006 formal/core composition contract",
            "FPSC-P1-001 one personal life-economy loop",
            "FPSC-P1-007 map/economy/political ID and causal contract",
            "FPSC-P1-002 one travel/location loop",
            "FPSC-P1-004 authoritative event pipeline",
            "FPSC-P1-003 one social/knowledge loop",
            "FPSC-P1-005 politics, organization, then AI feedback",
            "FPSC-P1-008 historical semantic/time contract",
            "FPSC-P1-009 release license gate",
        ],
        "parallel_after_contracts": [
            "P2 test/document truth repair can run beside P0 implementation once formal boundaries are fixed.",
            "Historical license review can run independently of code implementation.",
            "Historical lower-admin source research can run independently but must not change runtime contracts.",
        ],
        "must_be_serial": [
            "Player authority before personal economy, travel, social or AI commands.",
            "Snapshot ownership before adding new persistent systems.",
            "Stable geography/political ID contract before travel or map-driven economy.",
            "Authoritative event/knowledge contract before media or autonomous political feedback.",
        ],
        "do_not_expand": [
            "Alpha fictional world/product entry",
            "V2.2/V2.3 product scenes and parallel clocks/saves",
            "UI-seeded world events",
            "holographic spike inheritance as a place for new business state",
        ],
        "formal_unique_implementations": [
            "FormalWorldSimulation for formal session/time composition",
            "FormalWorldEconomyService for current aggregate economy",
            "formal_world_menu.tscn/formal_world_main.tscn for product entry",
            "one future selected player/session service behind the formal composition contract",
        ],
        "contract_first_systems": [
            "player identity and authority",
            "persistence schema/transaction",
            "political unit/economy/location IDs",
            "event/knowledge visibility",
            "organization and AI write permissions",
        ],
        "phases": [
            {
                "phase": 1,
                "name": "Formal session and persistence",
                "definition_of_done": "One player, one command boundary, one complete transactional snapshot.",
                "acceptance": "Full new/save/exit/load/continue journey and invariant/fault tests.",
            },
            {
                "phase": 2,
                "name": "Minimal life-economy loop",
                "definition_of_done": "Needs/work/income/consumption connect one player to aggregate economy.",
                "acceptance": "Causal state diff, visible feedback, deterministic long-run and save roundtrip.",
            },
            {
                "phase": 3,
                "name": "Spatial and social loops",
                "definition_of_done": "One travel loop and one communication/knowledge loop use stable IDs and owners.",
                "acceptance": "Paths 3 and 4 become VERIFIED end to end.",
            },
            {
                "phase": 4,
                "name": "Non-player world feedback",
                "definition_of_done": "One political/organization/AI change is observable, answerable and persistent.",
                "acceptance": "Path 5 becomes VERIFIED with bounded performance and causal IDs.",
            },
        ],
        "judgement_origin": "reviewed",
    }


def reviewed_historical_separation() -> dict[str, object]:
    return {
        "formal_runtime_spike_inheritance": {
            "status": "CONFIRMED_MIXED",
            "evidence": ["E003", "E040"],
            "conclusion": "ui_spikes is not wholly SPIKE_ONLY; a deep subset is FORMAL_RUNTIME.",
        },
        "alpha": {
            "status": "FORMAL_DEPENDENCY_PLUS_LEGACY",
            "evidence": ["E030", "E041"],
            "conclusion": "Historical economy data class/catalog are formal dependencies; fictional Alpha world/services remain legacy or test-only.",
        },
        "v2_2": {
            "status": "FORMAL_DEPENDENCY_PLUS_LEGACY",
            "evidence": ["E006", "E030"],
            "conclusion": "V2DateTime is formal; the V2.2 product loop remains legacy.",
        },
        "v2_3": {
            "status": "LEGACY_REFERENCE",
            "evidence": ["E026", "E032"],
            "conclusion": "Retained travel/social services are tested but not formal runtime.",
        },
        "capture_probe_fixture_debug": {
            "status": "TEST_OR_TOOLING_ONLY_UNLESS_REACHED",
            "evidence": ["E015", "E048", "E051"],
            "conclusion": "Capture/probe/fixture entries are verification aids; scanner reachability overrides directory-name assumptions.",
        },
        "recommended_follow_up": "隔离/归档前先用正式可达图和行为等价测试；本轮不删除。",
        "judgement_origin": "reviewed",
    }


def audit_conclusions() -> list[dict[str, object]]:
    rows = [
        (1, "当前正式产品包含入口、历史半球/地理浏览、权威时间、50 经济体聚合市场、查询 UI、时间/经济存档、数据校验、CI/Windows 导出；其余人物/社会/政治/AI 多为孤立实现。", ["E001", "E008", "E017", "E032"]),
        (2, "核心人物、行动、地图控制、社会、组织、关系、AI、核心原子存档及 V2.3 旅行/知识服务存在代码和测试，但没有进入正式运行链。", ["E020", "E021", "E022", "E023", "E026", "E032"]),
        (3, "正式入口已形成时间—经济—查询—保存的局部闭环，但没有权威玩家业务行动，因此不是完整玩家闭环。", ["E004", "E009", "E039"]),
        (4, "正式时间/经济 owner 相对明确；玩家、事件、导航、政治语义和跨产品存档 owner 仍冲突或缺失。", ["E010", "E024", "E027", "E045", "E046"]),
        (5, "正式测试能证明场景、时间、经济和十年聚合稳定性；旧全量旅程/总测试不可运行或未进入统一验证，retained 测试不能证明正式接入。", ["E011", "E013", "E033", "E034", "E042", "E051"]),
        (6, "时间、聚合经济、数据加载和 Windows 构建门禁已达到可持续开发的局部基线；深继承与跨命名空间依赖仍降低维护性。", ["E012", "E013", "E014", "E030", "E040"]),
        (7, "距离可连续游玩的正式产品，核心缺口是权威玩家/行动、完整事务存档、个人生活经济、旅行、社会知识和非玩家反馈。", ["E018", "E031", "E039"]),
        (8, "后续应先建立会话与持久化契约，再按个人经济、空间、社会、政治/组织/AI 的依赖顺序逐条闭环，避免恢复旧入口或并行 owner。", ["E020", "E022", "E046"]),
    ]
    return [
        {"question": number, "answer": answer, "evidence": evidence, "judgement_origin": "reviewed"}
        for number, answer, evidence in rows
    ]


def _counts(values: Iterable[str], allowed: set[str]) -> dict[str, int]:
    counter = Counter(values)
    return {key: counter.get(key, 0) for key in sorted(allowed)}


def build_artifact(root: Path, report_base_sha: str = REPORT_BASE_SHA) -> dict[str, object]:
    scanner = scanner_payload(root)
    evidence = reviewed_evidence()
    systems = reviewed_systems()
    loops = reviewed_product_loops()
    gaps = reviewed_gaps()
    claims = reviewed_document_claims()
    payload: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "artifact_encoding": {
            "format": "UTF-8 JSON with sorted object keys and LF newline",
            "checkout_head": (
                "Validated at invocation by --expected-head and intentionally "
                "omitted to avoid commit-SHA self-reference."
            ),
            "environment": (
                "Branch, checkout path, username, temporary paths and runtime "
                "timestamps are intentionally omitted."
            ),
        },
        "baseline": {
            "audit_date": AUDIT_DATE,
            "report_base_sha": report_base_sha,
            "engine": "Godot 4.6.3 stable, Compatibility renderer",
        },
        "methodology": {
            "scanner_derived": [
                "project main scene and autoload declarations",
                "transitive literal res:// and global class_name reachability",
                "path provenance and conservative reachability classifications",
                "literal missing-resource references",
                "formal CI and unified-validation entry discovery",
            ],
            "reviewed": [
                "system boundaries and maturity",
                "dimension statuses",
                "state ownership and causal interpretation",
                "product-loop step status",
                "gap severity and roadmap",
                "documentation truth classification",
            ],
            "non_proofs": [
                "filename or class name",
                "comments or TODOs",
                "design documents",
                "test existence without execution and formal reachability",
                "services not referenced by the formal entry",
            ],
        },
        "formal_product_boundary": {
            "entry": "res://scenes/formal/formal_world_menu.tscn",
            "world_scene": "res://scenes/formal/formal_world_main.tscn",
            "application": "FormalWorldApplication",
            "session_owner": "scene-owned FormalWorldSimulation (time plus aggregate economy only)",
            "autoloads": [],
            "formal_save": "user://formal_world_1900.json; formal_world_simulation_v2",
            "formal_data_roots": [
                "data/alpha historical economy inputs explicitly reached by FormalWorldEconomyService",
                "data/world_map historical and visual inputs reached by the formal UI",
            ],
            "formal_test_entries": [
                "tests/formal/formal_world_integration_test.gd",
                "tests/formal/formal_world_long_term_balance_test.gd",
                "tests/variable_state/formal_time_stable_contract_test.gd",
                "tests/variable_state/formal_time_known_defects_test.gd",
            ],
            "release_entries": [
                ".github/workflows/windows-prototype-release.yml",
                ".github/workflows/release-ui-integration.yml",
                "export_presets.cfg",
            ],
            "explicit_exclusions": [
                "Alpha fictional two-country/eight-region product scenes and services except reached historical data dependencies",
                "V2.2 and V2.3 product scenes and parallel simulations except reached V2DateTime",
                "unreached ui_spikes probes/captures",
                "core player/society/map/action/save services until a formal composition contract reaches them",
            ],
            "judgement_origin": "reviewed from scanner boundary plus source inspection",
        },
        "overall_assessment": {
            "current_product": (
                "A tested historical-world and aggregate-economy inspector with "
                "authoritative time, limited controls and partial persistence."
            ),
            "continuous_playable_formal_product": False,
            "formal_release_ready": False,
            "reason": (
                "No authoritative player/business-action loop and no complete, "
                "durable session snapshot; three of five required product paths are missing."
            ),
            "judgement_origin": "reviewed",
        },
        "scanner": scanner,
        "evidence": evidence,
        "systems": systems,
        "system_counts": {
            "total": len(systems),
            "by_maturity": _counts(
                (str(row["maturity"]) for row in systems), MATURITIES
            ),
        },
        "product_loops": loops,
        "product_loop_counts": _counts(
            (str(row["overall_status"]) for row in loops), LOOP_STATUSES
        ),
        "gaps": gaps,
        "gap_counts": {
            "total": len(gaps),
            "by_priority": _counts(
                (str(row["priority"]) for row in gaps), PRIORITIES
            ),
            "blocking_playable_loop": sum(
                1 for row in gaps if bool(row["blocks_playable_loop"])
            ),
            "blocking_formal_release": sum(
                1 for row in gaps if bool(row["blocks_formal_release"])
            ),
        },
        "historical_and_experimental_separation": reviewed_historical_separation(),
        "documentation_truth": {
            "claims": claims,
            "counts": _counts(
                (str(row["classification"]) for row in claims), CLAIM_STATUSES
            ),
            "rule": (
                "Product vision and design intent are preserved, but do not "
                "override implementation, formal runtime or executed-test evidence."
            ),
        },
        "core_questions": audit_conclusions(),
        "implementation_roadmap": reviewed_roadmap(),
        "validation_contract": {
            "static": [
                "tool --help",
                "missing --root negative invocation",
                "wrong --expected-head negative invocation",
                "two independent generations with byte equality",
                "--check against committed artifact",
                "python compileall",
                "tool regression tests",
                "audit Markdown link and evidence-file checks",
                "git diff --check",
                "existing runtime/static audits",
            ],
            "dynamic": [
                "repository unified validation",
                "Codex audit regression when applicable",
                "formal entry startup and Windows export when applicable",
            ],
            "godot_checkout_rule": (
                "All Godot execution must occur in one disposable clone based "
                "on the final branch head, never in a primary worktree."
            ),
        },
    }
    validate_artifact(root, payload)
    return payload


def _all_evidence_references(payload: object) -> set[str]:
    references: set[str] = set()

    def visit(value: object, key: str = "") -> None:
        if (
            key == "evidence"
            and isinstance(value, list)
            and all(isinstance(item, str) for item in value)
        ):
            references.update(str(item) for item in value)
            return
        if isinstance(value, dict):
            for child_key, child in value.items():
                visit(child, str(child_key))
        elif isinstance(value, list):
            for child in value:
                visit(child, key)

    visit(payload)
    return references


def _assert_environment_neutral(value: object) -> None:
    if isinstance(value, dict):
        forbidden_keys = {
            "branch", "checkout_path", "current_user", "runtime_timestamp",
            "temporary_directory", "checked_out_head",
        }
        overlap = forbidden_keys & set(value)
        if overlap:
            raise AuditError(f"environment-dependent artifact keys: {sorted(overlap)}")
        for child in value.values():
            _assert_environment_neutral(child)
    elif isinstance(value, list):
        for child in value:
            _assert_environment_neutral(child)
    elif isinstance(value, str):
        if re.match(r"^[A-Za-z]:[\\/]", value) or value.startswith(("/tmp/", "/home/", "/Users/")):
            raise AuditError(f"absolute environment path in artifact: {value}")


def validate_artifact(root: Path, payload: dict[str, object]) -> None:
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise AuditError("unexpected artifact schema")
    evidence_rows = payload.get("evidence", [])
    if not isinstance(evidence_rows, list):
        raise AuditError("evidence must be a list")
    evidence_ids = [str(row["id"]) for row in evidence_rows]
    if len(evidence_ids) != len(set(evidence_ids)):
        raise AuditError("evidence IDs are not unique")
    evidence_set = set(evidence_ids)
    for row in evidence_rows:
        path = str(row["path"])
        if not (root / path).is_file():
            raise AuditError(f"evidence file is missing: {path}")
        if row.get("origin") not in {"scanner-derived", "reviewed"}:
            raise AuditError(f"invalid evidence origin: {row.get('origin')}")

    references = _all_evidence_references(payload)
    missing_evidence = sorted(references - evidence_set)
    if missing_evidence:
        raise AuditError(f"unknown evidence references: {missing_evidence}")

    systems = payload.get("systems", [])
    if not isinstance(systems, list) or [row["id"] for row in systems] != list("ABCDEFGHIJKLMNO"):
        raise AuditError("systems must contain stable A-O inventory")
    for row in systems:
        maturity = str(row["maturity"])
        if maturity not in MATURITIES:
            raise AuditError(f"invalid system maturity: {maturity}")
        dimensions = row.get("dimensions", {})
        if not isinstance(dimensions, dict) or set(dimensions) != set(DIMENSIONS):
            raise AuditError(f"incomplete dimensions for system {row['id']}")
        for name, result in dimensions.items():
            if result["status"] not in DIMENSION_STATUSES or not result["evidence"]:
                raise AuditError(f"invalid dimension result: {row['id']}.{name}")
        if maturity == "PLAYER_LOOP_COMPLETE":
            required = {
                "implementation", "runtime_reachability", "integration",
                "player_surface", "lifecycle", "persistence", "causal_feedback",
            }
            if any(dimensions[name]["status"] != "VERIFIED" for name in required):
                raise AuditError(
                    f"PLAYER_LOOP_COMPLETE lacks verified dimensions: {row['id']}"
                )
        if maturity in {"INTEGRATED_VERIFIED", "PLAYER_LOOP_PARTIAL", "PLAYER_LOOP_COMPLETE"}:
            if dimensions["runtime_reachability"]["status"] == "MISSING":
                raise AuditError(f"integrated system is not reachable: {row['id']}")

    loops = payload.get("product_loops", [])
    if not isinstance(loops, list) or len(loops) != 5:
        raise AuditError("exactly five product loops are required")
    for loop in loops:
        if loop["overall_status"] not in LOOP_STATUSES:
            raise AuditError(f"invalid loop status: {loop['id']}")
        for step in loop["steps"]:
            if step["status"] not in LOOP_STATUSES or not step["evidence"]:
                raise AuditError(f"invalid loop step: {loop['id']} {step['step']}")

    gaps = payload.get("gaps", [])
    if not isinstance(gaps, list):
        raise AuditError("gaps must be a list")
    gap_ids = [str(row["id"]) for row in gaps]
    if len(gap_ids) != len(set(gap_ids)):
        raise AuditError("gap IDs are not unique")
    if any(row["priority"] not in PRIORITIES for row in gaps):
        raise AuditError("invalid gap priority")
    orders = [int(row["recommended_order"]) for row in gaps]
    if orders != sorted(orders) or len(orders) != len(set(orders)):
        raise AuditError("gap recommended_order must be unique and sorted")

    claims = payload["documentation_truth"]["claims"]
    for row in claims:
        if row["classification"] not in CLAIM_STATUSES:
            raise AuditError(f"invalid claim status: {row['classification']}")
        if not (root / str(row["document"])).is_file():
            raise AuditError(f"claim document missing: {row['document']}")

    scanner = payload.get("scanner", {})
    runtime_files = set(scanner.get("formal_runtime_files", []))
    required_runtime = {
        "project.godot",
        "scenes/formal/formal_world_menu.tscn",
        "scenes/formal/formal_world_main.tscn",
        "scripts/formal/formal_world_application.gd",
        "scripts/formal/formal_world_simulation.gd",
        "scripts/formal/formal_world_economy_service.gd",
        "scripts/alpha/alpha_historical_world_economy_data.gd",
        "scripts/v2_2/v2_datetime.gd",
        "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd",
    }
    missing_runtime = sorted(required_runtime - runtime_files)
    if missing_runtime:
        raise AuditError(f"formal reachability missed required files: {missing_runtime}")
    if scanner["project"]["autoloads"]:
        raise AuditError("autoload boundary changed from audited baseline")

    _assert_environment_neutral(payload)


def canonical_bytes(payload: dict[str, object]) -> bytes:
    return (
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
            separators=(",", ": "),
        )
        + "\n"
    ).encode("utf-8")


def validate_audit_documents(
    root: Path, payload: dict[str, object] | None = None
) -> list[str]:
    errors: list[str] = []
    for relative in AUDIT_DOCS:
        path = root / relative
        if not path.is_file():
            errors.append(f"missing audit document: {relative}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for raw_target in MARKDOWN_LINK_RE.findall(text):
            target = raw_target.strip().strip("<>").split("#", 1)[0]
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            candidate = (path.parent / target).resolve()
            if not candidate.exists():
                errors.append(f"broken Markdown link: {relative} -> {raw_target}")
    if payload is not None:
        for row in payload.get("evidence", []):
            relative = str(row["path"])
            if not (root / relative).is_file():
                errors.append(f"missing evidence reference: {relative}")
        for row in payload.get("systems", []):
            for field in ("production_files", "tests", "documents"):
                for raw in row.get(field, []):
                    relative = str(raw)
                    if any(marker in relative for marker in ("*", " ")):
                        continue
                    if Path(relative).suffix and not (root / relative).exists():
                        errors.append(
                            f"missing system reference: {row['id']}.{field} -> {relative}"
                        )
    return sorted(set(errors))


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate or check the normalized formal-product system "
            "completeness audit artifact."
        )
    )
    parser.add_argument(
        "--root", type=Path, required=True,
        help="explicit repository root; must equal git rev-parse --show-toplevel",
    )
    parser.add_argument(
        "--output", type=Path, required=True,
        help="artifact path, absolute or relative to --root",
    )
    parser.add_argument(
        "--report-base-sha", default=REPORT_BASE_SHA,
        help="fixed report baseline SHA recorded in the artifact",
    )
    parser.add_argument(
        "--expected-head", required=True,
        help="exact commit expected at the currently checked-out HEAD",
    )
    parser.add_argument(
        "--check", action="store_true",
        help="compare regenerated bytes with --output instead of writing",
    )
    return parser.parse_args(argv)


def _resolve_output(root: Path, output: Path) -> Path:
    return output.resolve() if output.is_absolute() else (root / output).resolve()


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        root = _normalize_checkout(args.root)
        _validate_sha(root, args.expected_head, args.report_base_sha)
        payload = build_artifact(root, args.report_base_sha)
        generated = canonical_bytes(payload)
        output = _resolve_output(root, args.output)
        if args.check:
            if not output.is_file():
                raise AuditError(f"--check output does not exist: {args.output}")
            committed = output.read_bytes()
            if committed != generated:
                raise AuditError(
                    "committed artifact differs from deterministic regeneration"
                )
            mode = "check"
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(generated)
            mode = "write"
        print(json.dumps({
            "artifact_bytes": len(generated),
            "gaps": payload["gap_counts"],
            "mode": mode,
            "report_base_sha": args.report_base_sha,
            "systems": payload["system_counts"],
        }, ensure_ascii=False, sort_keys=True))
        return 0
    except (AuditError, OSError, ValueError) as error:
        print(f"audit error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
