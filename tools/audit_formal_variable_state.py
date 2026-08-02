#!/usr/bin/env python3
"""Deterministic, conservative inventory of WWO variables and state.

The scanner never edits production files. Outputs are written only when their
paths are supplied explicitly. Static evidence is not treated as proof that a
dynamic call, scene injection, or semantic distinction is absent.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable

import audit_variable_state as legacy


FIXED_BASE = "277a6d801a6eae762e4f6963ceb995a909f80bd9"
MASTER_SHA = "92bbf22d05d8f1ba31fc2559f8b41d01a002e823"
AUDIT_DATE = "2026-08-03"

FUNC_RE = re.compile(r"^\s*func\s+([A-Za-z_]\w*)")
LOCAL_RE = re.compile(
    r"^\s+(?:@[A-Za-z_]\w*(?:\([^)]*\))?\s+)*"
    r"(?:var|const)\s+(?P<name>[A-Za-z_]\w*)"
    r"(?:\s*:\s*(?P<type>[^=:]+?))?"
    r"(?:\s*(?::=|=)\s*(?P<init>.*))?$"
)
PROPERTY_RE = re.compile(
    r"^(?P<mods>(?:static\s+|@[A-Za-z_]\w*(?:\([^)]*\))?\s+)*)"
    r"(?P<kind>var|const)\s+(?P<name>[A-Za-z_]\w*)"
    r"\s*:\s*(?P<type>[^:]+?)\s*:\s*$"
)
TOKEN_RE = re.compile(r"\b[A-Za-z_]\w*\b")
DYNAMIC_RE = re.compile(
    r"(?<![A-Za-z0-9_])(?P<kind>get|set|call|call_deferred|load|preload)"
    r"\s*\((?P<args>.*)"
)
SIGNAL_RE = re.compile(
    r"\b(?:signal\s+|connect\s*\(|\.connect\s*\(|emit_signal\s*\(|\.emit\s*\()"
)
KEY_PATTERNS = (
    re.compile(r"\.get\(\s*[\"']([A-Za-z_]\w*)[\"']"),
    re.compile(r"\.has\(\s*[\"']([A-Za-z_]\w*)[\"']"),
    re.compile(r"\[\s*[\"']([A-Za-z_]\w*)[\"']\s*\]"),
    re.compile(r"[\"']([A-Za-z_]\w*)[\"']\s*:"),
    re.compile(r"\bset\(\s*[\"']([A-Za-z_]\w*)[\"']"),
)
STRING_RE = re.compile(r"[\"']([A-Za-z_]\w*)[\"']")

PERSISTENCE_WORDS = (
    "save", "load", "restore", "snapshot", "serialize", "deserialize",
    "migration", "migrate", "schema", "rollback", "persistent",
    "to_dict", "from_dict", "validate_snapshot", "read_document",
    "write_document",
)
IMPORTANT_LOCAL_WORDS = (
    "candidate", "previous", "restored", "snapshot", "rollback", "pending",
    "current", "before", "after", "transaction", "temporary", "legacy",
    "migration", "selected", "active", "committed", "replacement",
)
MUTATING_METHODS = (
    "append", "append_array", "assign", "clear", "erase", "insert", "merge",
    "push_back", "push_front", "pop_back", "pop_front", "resize", "sort",
    "sort_custom", "shuffle", "fill",
)
UI_WORDS = (
    "selected", "hover", "focus", "displayed", "visible", "panel_open",
    "drawer_open", "workspace_open", "info_open", "tooltip", "label_text",
    "animation", "screen_", "ui_", "active_tab", "activity_unread",
)
CACHE_WORDS = ("cache", "cached", "memo", "prewarm", "lookup", "index_by_")
COMPAT_WORDS = (
    "legacy", "compat", "deprecated", "migration", "migrated", "old_schema",
    "previous_schema", "v2_2", "save_version",
)
DERIVED_WORDS = (
    "summary", "computed", "projected", "resolved", "display_name", "bounds",
    "breadcrumb", "total_count", "unread_count", "screen_polygons", "report",
)
MANUAL_CATEGORIES = {
    "FormalWorldSimulation._minute_remainder": (
        "B", "由 FormalWorldSimulation.total_minutes % 60 计算的只读 getter。"
    ),
    "FormalWorldEconomyService.total_hour": (
        "B", "通过注入 Callable 从 FormalWorldSimulation.total_minutes 派生。"
    ),
    "FormalWorldEconomyService.economy_polity_ids": (
        "D", "由 crosswalk 建立的经济体到政治单元正向索引；方向与反向索引不同。"
    ),
    "FormalWorldEconomyService.economy_by_polity_id": (
        "D", "由 crosswalk 建立的政治单元到经济体反向索引；不是正向索引的同义字段。"
    ),
    "FormalWorldEconomyService._crosswalk_records": (
        "D", "从固定 crosswalk 配置建立的加载期记录缓存。"
    ),
    "FormalWorldEconomyService._last_day_index": (
        "A", "最近完成日结的日序号；恢复值会影响后续结算边界。"
    ),
    "FormalWorldApplication._last_summary": (
        "C", "正式世界应用保存的最近一次展示摘要；属于 UI 刷新生命周期，不是独立模拟事实。"
    ),
    "holographic_workspace_admin1._world_admin1_bounds": (
        "D", "由行政区几何计算的展示边界缓存。"
    ),
    "PrototypeV2MapCanvas.WORLD_BOUNDS": (
        "A", "地图坐标系的不可变输入边界，不是运行期派生状态。"
    ),
    "PrototypeV2SpatialIndex._world_bounds": (
        "A", "构造时注入的空间索引边界配置，不是可独立删除的派生副本。"
    ),
    "holographic_workspace_runtime.active_character_key": (
        "G", "展示层人物档案选择键；与 GameSessionService.player_character 的权威玩家对象边界不清。"
    ),
    "holographic_workspace_runtime._world_events": (
        "C", "展示层播种的世界事件列表；正式产品继承该成员但未连接正式事件服务。"
    ),
    "holographic_workspace_runtime.activity_unread": (
        "C", "展示层对播种事件维护的未读计数。"
    ),
}

MANUAL_CACHES = {
    "FormalWorldEconomyService.economy_polity_ids": "由 political_economy_crosswalk_1900.json 构建；正式运行期没有增量失效入口。",
    "FormalWorldEconomyService.economy_by_polity_id": "由 political_economy_crosswalk_1900.json 构建；正式运行期没有增量失效入口。",
    "FormalWorldEconomyService._crosswalk_records": "由 political_economy_crosswalk_1900.json 加载；正式运行期没有增量失效入口。",
    "holographic_workspace_admin1._world_admin1_bounds": "由行政区多边形计算；行政几何重新加载时重建。",
}

EVIDENCE_REFERENCE_KEYS = {
    "ambiguous_external_read_sites", "ambiguous_external_write_sites",
    "cache_build_sites", "dynamic_access_sites", "evidence",
    "formal_product_reference_sites", "formal_reference_sites", "locations",
    "persistence_sites", "read_sites", "runtime_write_sites",
    "scene_node_paths", "scene_reference_sites", "signal_candidates",
    "signal_reference_sites", "sites", "test_tool_config_reference_sites",
    "write_sites",
}


def git(root: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", *args], cwd=root, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return completed.stdout.strip()


def rel(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def scope_files(root: Path) -> list[Path]:
    result: set[Path] = set()
    for pattern in (
        "scripts/**/*.gd", "scenes/**/*.tscn", "resources/**/*",
        "data/**/*.json", "data/**/*.cfg", "tests/**/*.gd", "tests/**/*.json",
        ".github/workflows/**/*", "tools/**/*",
    ):
        result.update(
            path for path in root.glob(pattern)
            if path.is_file()
            and "__pycache__" not in path.parts
            and path.suffix.lower() not in (".pyc", ".pyo")
        )
    for name in ("project.godot", "export_presets.cfg"):
        path = root / name
        if path.is_file():
            result.add(path)
    return sorted(result, key=lambda path: rel(root, path))


def read_text(path: Path) -> str:
    data = path.read_bytes()
    if b"\x00" in data:
        return ""
    return data.decode("utf-8", errors="replace")


def mask_code(line: str) -> str:
    output: list[str] = []
    quote = ""
    escaped = False
    for index, char in enumerate(line):
        if quote:
            output.append(" ")
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in ("\"", "'"):
            quote = char
            output.append(" ")
        elif char == "#":
            output.extend(" " for _ in range(len(line) - index))
            break
        else:
            output.append(char)
    return "".join(output)


def functions_by_line(text: str) -> dict[int, str]:
    current = ""
    result: dict[int, str] = {}
    for line_number, raw in enumerate(text.splitlines(), 1):
        match = FUNC_RE.match(mask_code(raw))
        if match:
            current = match.group(1)
        result[line_number] = current
    return result


def infer_type(initializer: str) -> str:
    value = initializer.strip()
    if value in ("true", "false"):
        return "bool"
    if re.fullmatch(r"-?\d+", value):
        return "int"
    if re.fullmatch(r"-?(?:\d+\.\d*|\d*\.\d+)", value):
        return "float"
    if value.startswith(("\"", "'")):
        return "String"
    if value.startswith("["):
        return "Array"
    if value.startswith("{"):
        return "Dictionary"
    if value == "null":
        return "Variant/null"
    match = re.search(r"([A-Za-z_]\w*)\.new\(", value)
    return match.group(1) if match else "由初始化表达式推断"


def system_for(path: str, name: str) -> str:
    value = f"{path}/{name}".lower()
    routes = (
        (("scripts/formal", "formal_world"), "正式世界"),
        (("save", "snapshot", "migration"), "存档/恢复"),
        (("clock", "time", "date", "minute", "hour"), "正式时间"),
        (("econom", "cash", "price", "wage", "inventory", "tax", "market"), "经济"),
        (("character", "person", "player", "succession"), "人物/玩家"),
        (("organization", "relation", "society"), "组织/社会关系"),
        (("world_map", "/map/", "polity", "territory", "admin", "city"), "地图/政治单元"),
        (("action",), "行动"),
        (("/ai/", "ai_"), "AI"),
        (("event", "message", "notification", "inbox"), "事件/消息"),
        (("interface", "menu", "hud", "workspace", "canvas", "ui_"), "导航/UI"),
        (("alpha",), "Alpha"),
        (("v2_2",), "V2.2"),
        (("v2_3",), "V2.3"),
    )
    for needles, label in routes:
        if any(needle in value for needle in needles):
            return label
    return "核心/其他"


def meaning_for(owner: str, name: str, declared_type: str, initializer: str, system: str) -> str:
    lower = name.lower().lstrip("_")
    exact = {
        "total_minutes": "从 1900-01-01 起累计的正式模拟分钟数。",
        "player_character": "当前由玩家控制的权威人物对象。",
        "current_action": "当前玩家人物正在执行的行动实例。",
        "world_clock": "会话绑定的模拟时钟服务。",
        "selected_country_id": "地图当前选择的政治单元 ID，不等同于玩家所属国。",
        "selected_person_id": "界面或旧模拟当前选择的人物 ID。",
        "active_character_key": "展示层当前人物档案的键。",
    }
    if lower in exact:
        return exact[lower]
    patterns = (
        (("cash", "balance"), "持有者的货币余额或结算余额。"),
        (("inventory", "stock"), "持有者拥有或展示的商品库存。"),
        (("wage",), "工资率、应付工资或劳动报酬。"),
        (("price",), "价格状态或定价规则。"),
        (("income", "revenue"), "收入累计或结算结果。"),
        (("expense", "expenditure", "cost"), "支出、费用或结算成本。"),
        (("tax",), "税率、税额或税收结算状态。"),
        (("country_id", "polity_id"), "政治单元的稳定 ID 或映射。"),
        (("territory", "admin1", "region_id", "city_id"), "地图空间或行政单元标识/集合。"),
        (("selected",), "当前交互选择状态。"),
        (("hover",), "当前指针悬停状态。"),
        (("focus",), "当前界面焦点状态。"),
        (("visible", "displayed"), "展示层可见或已显示状态。"),
        (("pending",), "尚未越过提交边界的候选状态。"),
        (("previous", "last_"), "比较、回滚或边沿检测使用的上一状态。"),
        (("cache", "cached", "lookup"), "由其他状态建立的查询或绘制缓存。"),
        (("service", "manager"), "特定职责的服务实例引用。"),
        (("label", "button", "panel", "viewport", "camera"), "场景节点或界面组件引用/状态。"),
        (("path", "scene"), "资源、场景或存档位置配置。"),
        (("config", "rules"), "系统规则或配置输入。"),
    )
    for needles, text in patterns:
        if any(needle in lower for needle in needles):
            return text
    resolved_type = declared_type or infer_type(initializer)
    return f"{owner} 在“{system}”中持有的 `{name}` 状态或依赖（{resolved_type}）；仓库没有更具体的领域注释。"


def lifecycle_for(extends: str, is_static: bool, is_const: bool, persisted: bool) -> str:
    if is_const:
        return "进程内不可变规则/稳定资源引用"
    if is_static:
        value = "进程/会话级静态状态"
    elif any(word in extends.lower() for word in ("node", "control", "canvas", "scene")):
        value = "场景节点生命周期"
    elif any(word in extends.lower() for word in ("resource", "refcounted")):
        value = "服务/资源实例生命周期"
    else:
        value = "对象实例生命周期"
    return value + ("；字段名进入磁盘存档候选" if persisted else "")


def is_write(name: str, raw: str) -> bool:
    code = mask_code(raw)
    escaped = re.escape(name)
    assignment = r"(?:[+\-*/%|&^]=|=(?!=))"
    if re.search(rf"\b{escaped}\s*(?:\[[^\]]+\]\s*)?{assignment}", code):
        return True
    if re.search(rf"\.\s*{escaped}\s*{assignment}", code):
        return True
    if re.search(rf"\bset\(\s*[\"']{escaped}[\"']", raw):
        return True
    methods = "|".join(MUTATING_METHODS)
    return bool(re.search(rf"\b{escaped}\s*\.\s*(?:{methods})\s*\(", code))


def external_reference_confidence(
    owner: str, name: str, raw: str, receiver_types: dict[str, set[str]],
) -> str:
    """Return exact, ambiguous, or empty for a cross-file member reference."""
    code = mask_code(raw)
    escaped = re.escape(name)
    owner_name = re.escape(owner)
    if re.search(rf"\b{owner_name}\s*\.\s*{escaped}\b", code):
        return "exact"
    receivers = re.findall(rf"\b([A-Za-z_]\w*)\s*\.\s*{escaped}\b", code)
    for receiver in receivers:
        if owner in receiver_types.get(receiver, set()):
            return "exact"
    if receivers or re.search(rf"\b(?:get|set)\(\s*[\"']{escaped}[\"']", raw):
        return "ambiguous"
    return ""


def collect_receiver_types(masked_file_text: str) -> dict[str, set[str]]:
    result: dict[str, set[str]] = defaultdict(set)
    for match in re.finditer(
        r"\b(?P<receiver>[A-Za-z_]\w*)\s*:\s*(?P<type>[A-Za-z_]\w*)\b",
        masked_file_text,
    ):
        result[match.group("receiver")].add(match.group("type"))
    for match in re.finditer(
        r"\b(?P<receiver>[A-Za-z_]\w*)\s*(?::[^=\n]+)?\s*(?::=|=)\s*"
        r"(?P<type>[A-Za-z_]\w*)\s*\.\s*new\s*\(",
        masked_file_text,
    ):
        result[match.group("receiver")].add(match.group("type"))
    return result


def site(path: str, line: int, function: str, raw: str) -> str:
    scope = f"::{function}" if function else ""
    return f"{path}:{line}{scope}: {raw.strip()[:260]}"


def json_keys(value: object, prefix: str = "$") -> Iterable[tuple[str, str]]:
    if isinstance(value, dict):
        for key in sorted(value):
            yield str(key), f"{prefix}.{key}"
            yield from json_keys(value[key], f"{prefix}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from json_keys(item, f"{prefix}[{index}]")


def semantic_key(name: str) -> str:
    value = name.lower().lstrip("_")
    for prefix in (
        "current_", "selected_", "active_", "displayed_", "cached_",
        "last_", "pending_", "player_", "formal_",
    ):
        if value.startswith(prefix):
            return value[len(prefix):]
    return value


def collect_evidence(
    root: Path, text_by_path: dict[str, str], member_names: set[str]
) -> tuple[
    dict[str, list[tuple[str, int, str, str]]], list[dict[str, object]],
    dict[str, list[str]], list[str], list[str], list[dict[str, object]],
]:
    occurrences: dict[str, list[tuple[str, int, str, str]]] = defaultdict(list)
    dynamic: list[dict[str, object]] = []
    persistence: dict[str, list[str]] = defaultdict(list)
    scene_nodes: list[str] = []
    signals: list[str] = []
    important_locals: list[dict[str, object]] = []
    for path, text in sorted(text_by_path.items()):
        functions = functions_by_line(text) if path.endswith(".gd") else {}
        for line_number, raw in enumerate(text.splitlines(), 1):
            code = mask_code(raw)
            function = functions.get(line_number, "")
            for token in set(TOKEN_RE.findall(code)).intersection(member_names):
                occurrences[token].append((path, line_number, function, raw.strip()[:300]))
            dynamic_match = DYNAMIC_RE.search(raw)
            if dynamic_match:
                literal = re.match(r"\s*[\"']([^\"']+)[\"']", dynamic_match.group("args"))
                dynamic.append({
                    "path": path,
                    "line": line_number,
                    "function": function,
                    "kind": dynamic_match.group("kind"),
                    "literal_argument": literal.group(1) if literal else None,
                    "unresolved_argument": literal is None,
                    "evidence": site(path, line_number, function, raw),
                })
            if any(word in function.lower() for word in PERSISTENCE_WORDS):
                keys: set[str] = set()
                for pattern in KEY_PATTERNS:
                    keys.update(pattern.findall(raw))
                if any(word in raw.lower() for word in ("required", "schema", "keys", "fields")):
                    keys.update(STRING_RE.findall(raw))
                for key in sorted(keys):
                    persistence[key].append(site(path, line_number, function, raw))
            if path.endswith(".tscn") and ("[node " in raw or "NodePath(" in raw):
                scene_nodes.append(f"{path}:{line_number}: {raw.strip()[:260]}")
            if SIGNAL_RE.search(code):
                signals.append(site(path, line_number, function, raw))
            local = LOCAL_RE.match(raw)
            if path.startswith("scripts/") and local and function:
                name = local.group("name")
                if any(word in name.lower() for word in IMPORTANT_LOCAL_WORDS) or any(
                    word in function.lower() for word in PERSISTENCE_WORDS
                ):
                    owner = Path(path).stem
                    important_locals.append({
                        "qualified_name": f"{owner}.{function}.{name}",
                        "path": path,
                        "line": line_number,
                        "owner": owner,
                        "function": function,
                        "name": name,
                        "declared_type": (local.group("type") or "").strip() or "推断",
                        "initializer": (local.group("init") or "").strip() or "无显式默认值",
                        "system": system_for(path, name),
                        "lifecycle": "单次函数调用/事务边界",
                        "persistence": "局部值本身不持久化；可能参与快照候选或恢复提交",
                        "reason_selected": "名称或所在函数表明它参与候选、恢复、回滚、选择或持久化边界",
                        "evidence": site(path, line_number, function, raw),
                    })
    for path in sorted(root.glob("tests/**/*.json")):
        path_string = rel(root, path)
        if not any(word in path_string.lower() for word in ("save", "snapshot", "legacy", "migration", "fixture")):
            continue
        try:
            document = json.loads(read_text(path))
        except json.JSONDecodeError:
            continue
        for key, json_path in json_keys(document):
            if re.fullmatch(r"[A-Za-z_]\w*", key):
                persistence[key].append(f"{path_string}:{json_path}")
    return (
        occurrences,
        dynamic,
        {key: sorted(set(values)) for key, values in sorted(persistence.items())},
        sorted(scene_nodes),
        sorted(signals),
        sorted(important_locals, key=lambda item: (str(item["path"]), int(item["line"]))),
    )


def classify(
    row: dict[str, object], strong_unused: bool, formal_reachable: bool,
) -> tuple[str, str]:
    qualified = str(row["qualified_name"])
    if qualified in MANUAL_CATEGORIES:
        return MANUAL_CATEGORIES[qualified]
    path_name = f"{row['path']}/{row['name']}".lower()
    name = str(row["name"]).lower()
    if strong_unused:
        return "H", "未发现直接读写、字面反射、场景/资源、信号、存档或测试/工具引用；仍不得据此删除。"
    if path_name.startswith("scripts/alpha/") and not formal_reachable:
        return "F", "Alpha 状态且未发现正式脚本直接读取；正式产品不可达性仍需入口链证据。"
    if any(word in path_name for word in COMPAT_WORDS):
        return "E", "名称或路径表明属于旧版本、迁移或兼容边界。"
    if any(word in name for word in CACHE_WORDS):
        return "D", "名称表明是可重建索引或缓存候选。"
    if bool(row["is_onready"]) or any(word in name for word in UI_WORDS):
        return "C", "场景绑定、交互选择或展示生命周期状态。"
    if any(word in name for word in DERIVED_WORDS) and not row["persistence_sites"]:
        return "B", "名称表明是汇总、投影或可计算候选；计算来源仍需逐写入点确认。"
    if bool(row["is_const"]):
        return "A", "不可变规则、稳定 ID 或资源路径，作为正式输入而非可写状态记录。"
    if str(row["system"]) in (
        "正式世界", "正式时间", "经济", "人物/玩家", "组织/社会关系",
        "地图/政治单元", "行动", "AI", "事件/消息", "存档/恢复",
    ):
        return "A", "位于领域服务，作为正式状态候选保守保留。"
    if row["runtime_write_sites"] or row["read_sites"]:
        return "A", "存在运行期读写，未证明为缓存、UI、兼容或派生副本。"
    return "I", "仓库静态证据不足以确定业务含义或产品可达性。"


def recommendation(category: str) -> str:
    return {
        "A": "保留正式状态/规则并维持权威写入边界",
        "B": "进一步调查计算来源、独立写入与调用性能",
        "C": "保留交互语义；行为测试证明可由 Node 状态推导后再评估",
        "D": "保留并补全来源、建立、失效和性能证据",
        "E": "保留兼容边界；先确认版本、当前读写和迁移条件",
        "F": "保留隔离夹具；持续证明不进入正式产品运行链",
        "G": "下一轮比较语义、写入时机、精度、存档和失败处理",
        "H": "进入下一轮动态/场景/导出验证；本轮不得删除",
        "I": "证据不足；补充调用链或产品规则",
    }[category]


def write_scope(value: str) -> str:
    """Collapse a lexical write site to its file/function ownership scope."""
    prefix = value.split(": ", 1)[0]
    match = re.match(r"^(?P<path>.*?):\d+(?:::(?P<function>.*))?$", prefix)
    if not match:
        return prefix
    function = match.group("function") or "<top-level>"
    return f"{match.group('path')}::{function}"


def build_payload(root: Path, expected_base: str) -> dict[str, object]:
    head = git(root, "rev-parse", "HEAD")
    if head != expected_base:
        raise SystemExit(f"fixed Base changed: expected {expected_base}, found {head}")
    files = scope_files(root)
    text_by_path = {rel(root, path): read_text(path) for path in files}
    masked_text_by_path = {
        path: "\n".join(mask_code(line) for line in text.splitlines())
        for path, text in text_by_path.items()
    }
    receiver_types_by_path = {
        path: collect_receiver_types(text) for path, text in masked_text_by_path.items()
    }
    autoloads = legacy.parse_autoloads(text_by_path.get("project.godot", ""))
    production_paths = sorted(root.glob("scripts/**/*.gd"))
    parsed_members: list[legacy.Member] = []
    for path in production_paths:
        parsed_members.extend(
            legacy.parse_members(path, read_text(path), set(autoloads.values()))
        )
    parsed_locations = {(member.path, member.line) for member in parsed_members}
    members_by_path: dict[str, list[legacy.Member]] = defaultdict(list)
    for member in parsed_members:
        members_by_path[member.path].append(member)
    for path in production_paths:
        path_string = rel(root, path)
        template = members_by_path.get(path_string, [])
        owner = template[0].owner if template else path.stem
        extends = template[0].extends if template else ""
        for line_number, raw in enumerate(read_text(path).splitlines(), 1):
            if raw and raw[0].isspace() or (path_string, line_number) in parsed_locations:
                continue
            match = PROPERTY_RE.match(raw.strip())
            if not match:
                continue
            mods = match.group("mods") or ""
            annotations = re.findall(r"@[A-Za-z_]\w*(?:\([^)]*\))?", mods)
            name = match.group("name")
            is_static = "static" in mods.split()
            is_const = match.group("kind") == "const"
            lifecycle = legacy.infer_lifecycle(
                path_string, extends, is_static, set(autoloads.values())
            )
            category, category_reason, flags = legacy.infer_category(
                name=name,
                declared_type=match.group("type").strip(),
                initializer="",
                annotations=annotations,
                is_static=is_static,
                is_const=is_const,
                lifecycle=lifecycle,
            )
            parsed_members.append(legacy.Member(
                name=name,
                path=path_string,
                line=line_number,
                owner=owner,
                extends=extends,
                declaration_kind=match.group("kind"),
                declared_type=match.group("type").strip(),
                initializer="",
                annotations=annotations,
                is_static=is_static,
                is_export=any(value.startswith("@export") for value in annotations),
                is_onready=any(value.startswith("@onready") for value in annotations),
                is_const=is_const,
                is_production=True,
                lifecycle=lifecycle,
                category=category,
                category_reason=category_reason,
                derivation_candidate=flags["derivation_candidate"],
                cache_candidate=flags["cache_candidate"],
                compatibility_candidate=flags["compatibility_candidate"],
                ui_copy_candidate=flags["ui_copy_candidate"],
                unclear=flags["unclear"],
            ))
    parsed_members.sort(key=lambda member: (member.path, member.line, member.name))
    member_names = {member.name for member in parsed_members}
    occurrences, dynamic, persistence, scene_nodes, signals, important_locals = collect_evidence(
        root, text_by_path, member_names
    )
    formal_sources = {
        path: text for path, text in text_by_path.items()
        if path.startswith("scripts/formal/")
    }
    formal_functions = {
        path: functions_by_line(text) for path, text in formal_sources.items()
    }
    exact_groups: dict[str, list[legacy.Member]] = defaultdict(list)
    near_groups: dict[str, list[legacy.Member]] = defaultdict(list)
    for member in parsed_members:
        exact_groups[member.name].append(member)
        near_groups[semantic_key(member.name)].append(member)
    rows: list[dict[str, object]] = []
    for member in parsed_members:
        writes: list[str] = []
        reads: list[str] = []
        ambiguous_writes: list[str] = []
        ambiguous_reads: list[str] = []
        supporting_references: list[str] = []
        for path, line_number, function, raw in occurrences.get(member.name, []):
            if path == member.path and line_number == member.line:
                continue
            write = is_write(member.name, raw)
            evidence = site(path, line_number, function, raw)
            if not path.startswith("scripts/"):
                supporting_references.append(evidence)
                continue
            if path == member.path:
                (writes if write else reads).append(evidence)
                continue
            confidence = external_reference_confidence(
                member.owner, member.name, raw, receiver_types_by_path.get(path, {})
            )
            if confidence == "exact":
                (writes if write else reads).append(evidence)
            elif confidence == "ambiguous":
                (ambiguous_writes if write else ambiguous_reads).append(evidence)
        exact_dynamic = [
            str(item["evidence"]) for item in dynamic
            if item["kind"] in ("get", "set") and item["literal_argument"] == member.name
            and item["path"] == member.path
        ]
        dynamic_unresolved = any(
            item["kind"] in ("get", "set")
            and bool(item["unresolved_argument"])
            and item["path"] == member.path
            for item in dynamic
        )
        scene_refs = [
            value for value in scene_nodes
            if re.search(rf"\b{re.escape(member.name)}\b", value)
        ]
        signal_refs = [
            value for value in signals
            if re.search(rf"\b{re.escape(member.name)}\b", value)
        ]
        persistence_sites = persistence.get(member.name, [])
        same_name = [
            f"{item.owner}.{item.name}" for item in exact_groups[member.name]
            if item is not member
        ]
        near = [
            f"{item.owner}.{item.name}" for item in near_groups[semantic_key(member.name)]
            if item is not member
        ]
        similar = list(dict.fromkeys(same_name + near))[:30]
        writer_files = sorted({value.split(":", 1)[0] for value in writes})
        reader_files = sorted({value.split(":", 1)[0] for value in reads})
        formal_reference_sites = [
            site(path, line_number, formal_functions[path].get(line_number, ""), raw)
            for path, text in formal_sources.items()
            for line_number, raw in enumerate(text.splitlines(), 1)
            if re.search(rf"\b{re.escape(member.owner)}\b", mask_code(raw))
            or member.path in raw
            or f"res://{member.path}" in raw
        ]
        persisted = bool(persistence_sites)
        row: dict[str, object] = {
            "qualified_name": f"{member.owner}.{member.name}",
            "owner": member.owner,
            "name": member.name,
            "path": member.path,
            "line": member.line,
            "declaration_kind": member.declaration_kind,
            "declared_type": member.declared_type,
            "inferred_type": member.declared_type or infer_type(member.initializer),
            "initializer": member.initializer or "无显式默认值",
            "initializer_source": f"{member.path}:{member.line} 声明",
            "annotations": member.annotations,
            "extends": member.extends,
            "is_static": member.is_static,
            "is_const": member.is_const,
            "is_export": member.is_export,
            "is_onready": member.is_onready,
            "system": system_for(member.path, member.name),
            "meaning": meaning_for(
                member.owner, member.name, member.declared_type,
                member.initializer, system_for(member.path, member.name),
            ),
            "runtime_write_sites": sorted(set(writes)),
            "read_sites": sorted(set(reads)),
            "ambiguous_external_write_sites": sorted(set(ambiguous_writes)),
            "ambiguous_external_read_sites": sorted(set(ambiguous_reads)),
            "test_tool_config_reference_sites": sorted(set(supporting_references)),
            "writer_files": writer_files,
            "reader_files": reader_files,
            "formal_product_reference_sites": sorted(set(formal_reference_sites)),
            "persistence_sites": persistence_sites,
            "dynamic_access_sites": sorted(set(exact_dynamic)),
            "dynamic_access_unresolved": dynamic_unresolved,
            "scene_reference_sites": scene_refs,
            "signal_reference_sites": signal_refs,
            "persisted": (
                "兼容字段" if persisted and any(word in f"{member.path}/{member.name}".lower() for word in COMPAT_WORDS)
                else "是（静态字段名证据；需领域校验）" if persisted
                else "不确定（声明文件存在非字面 get/set）" if dynamic_unresolved
                else "否（未发现静态字段名证据）"
            ),
            "lifecycle": lifecycle_for(
                member.extends, member.is_static, member.is_const, persisted
            ),
            "computable": "否（静态证据未证明可完全重算）",
            "computed_from": [],
            "cache": "否",
            "cache_source": "",
            "cache_build_sites": [],
            "cache_invalidation": "不适用",
            "ui_state": "否",
            "similar_variables": similar,
            "similar_basis": (
                "同名成员；不同 owner/生命周期不能据此判定等价" if same_name
                else "去除 current/selected/active/player 等前缀后的近似名；前缀可能是必要语义" if near
                else "无静态近似分组"
            ),
        }
        owner_names = {
            item.name for item in parsed_members if item.owner == member.owner
        }
        computed_from = sorted(
            token for token in set(TOKEN_RE.findall(member.initializer))
            if token in owner_names and token != member.name
        )
        if any(word in member.name.lower() for word in DERIVED_WORDS) or row["qualified_name"] in (
            "FormalWorldSimulation._minute_remainder",
            "FormalWorldEconomyService.total_hour",
        ):
            row["computable"] = (
                "候选是；来源：" + (", ".join(computed_from) if computed_from else "getter/写入函数读取的正式字段")
            )
            row["computed_from"] = computed_from
        if any(word in member.name.lower() for word in CACHE_WORDS) or row["qualified_name"] in MANUAL_CACHES:
            row["cache"] = "是（静态命名/人工证据）"
            row["cache_source"] = MANUAL_CACHES.get(
                str(row["qualified_name"]),
                ", ".join(computed_from) if computed_from else "由缓存建立函数输入决定",
            )
            row["cache_build_sites"] = row["runtime_write_sites"]
            row["cache_invalidation"] = (
                "行政区几何重新加载时重建。"
                if row["qualified_name"] == "holographic_workspace_admin1._world_admin1_bounds"
                else "仅在正式经济初始化时重建；运行期 crosswalk 不可变。"
                if row["qualified_name"] in MANUAL_CACHES
                else "按所有写入/clear/erase 位置失效；无集中入口时存在过期风险"
            )
        if member.is_onready:
            row["ui_state"] = "场景节点绑定"
        else:
            ui_word = next((word for word in UI_WORDS if word in member.name.lower()), "")
            if ui_word:
                row["ui_state"] = ui_word
        write_scopes = sorted(set(
            write_scope(value) for value in row["runtime_write_sites"]
        ))
        row["current_unique_modifier"] = (
            "仅声明初始化；未发现运行期直接写入" if not write_scopes
            else write_scopes[0] if len(write_scopes) == 1
            else f"否；发现 {len(write_scopes)} 个候选写入作用域"
        )
        strong_unused = not (
            row["runtime_write_sites"] or row["read_sites"]
            or row["ambiguous_external_write_sites"]
            or row["ambiguous_external_read_sites"]
            or row["test_tool_config_reference_sites"]
            or row["dynamic_access_sites"] or dynamic_unresolved
            or scene_refs or signal_refs or persistence_sites
        )
        formal_reachable = (
            any(path.startswith("scripts/formal/") for path in reader_files)
            or bool(formal_reference_sites)
        )
        category, reason = classify(
            row, strong_unused, formal_reachable
        )
        row["category"] = category
        row["category_reason"] = reason
        row["recommendation"] = recommendation(category)
        if persisted and len(writer_files) > 1:
            risk = "P1"
        elif category in ("E", "G") or (category == "B" and len(write_scopes) > 1):
            risk = "P1"
        elif category in ("B", "C", "D", "H", "I"):
            risk = "P2"
        else:
            risk = "P3" if member.is_const else "P2"
        if row["qualified_name"] in (
            "FormalWorldEconomyService._last_day_index",
            "GameSessionService.player_character",
            "holographic_workspace_runtime.active_character_key",
            "holographic_workspace_runtime._world_events",
            "holographic_workspace_runtime.activity_unread",
        ):
            risk = "P1"
        row["risk"] = risk
        row["evidence"] = (
            [f"{member.path}:{member.line}: declaration"]
            + list(row["runtime_write_sites"][:5])
            + list(row["read_sites"][:5])
            + list(row["ambiguous_external_write_sites"][:2])
            + list(row["ambiguous_external_read_sites"][:2])
            + list(row["test_tool_config_reference_sites"][:2])
            + list(persistence_sites[:4])
            + list(row["dynamic_access_sites"][:3])
        )
        rows.append(row)
    categories = Counter(str(row["category"]) for row in rows)
    persistence_fields = [
        {
            "field": key,
            "sites": sites,
            "source": "持久化语义函数中的字符串键或受版本控制 JSON 存档/夹具键",
        }
        for key, sites in persistence.items()
    ]
    repeated = [
        {
            "name": name,
            "count": len(group),
            "members": [f"{item.owner}.{item.name}" for item in group],
            "locations": [f"{item.path}:{item.line}" for item in group],
            "warning": "同名不等于同义；必须比较 owner、生命周期、写入边界和存档关系。",
        }
        for name, group in sorted(exact_groups.items()) if len(group) > 1
    ]
    near = [
        {
            "semantic_key": key,
            "members": [f"{item.owner}.{item.name}" for item in group],
            "warning": "current/selected/active/player 等前缀可能正是必要语义，不得自动合并。",
        }
        for key, group in sorted(near_groups.items())
        if len(group) > 1 and len({item.name for item in group}) > 1
    ]
    member_names_set = {str(row["name"]) for row in rows}
    metrics: dict[str, object] = {
        "scanned_files": len(files),
        "production_gdscript_files": len(production_paths),
        "member_variables": sum(not bool(row["is_const"]) for row in rows),
        "static_variables": sum(bool(row["is_static"]) and not bool(row["is_const"]) for row in rows),
        "constants": sum(bool(row["is_const"]) for row in rows),
        "member_inventory_rows": len(rows),
        "persistence_fields": len(persistence_fields),
        "dynamic_call_candidates": sum(item["kind"] in ("get", "set", "call", "call_deferred") for item in dynamic),
        "dynamic_resource_path_candidates": sum(item["kind"] in ("load", "preload") for item in dynamic),
        "signal_candidates": len(signals),
        "scene_node_path_candidates": len(scene_nodes),
        "important_locals": len(important_locals),
        "category_counts": {letter: categories.get(letter, 0) for letter in "ABCDEFGHI"},
    }
    focus_words = {
        "formal_time": ("minute", "hour", "date", "clock", "speed", "pause"),
        "player_character": ("player", "character", "person", "succession", "country_id"),
        "map_polity": ("polity", "economy_id", "region", "city", "admin", "territory", "control"),
        "economy": ("cash", "inventory", "wage", "price", "income", "expense", "tax", "revenue", "transport"),
        "save": ("save", "snapshot", "restore", "migration", "schema", "rollback"),
        "navigation_ui": ("selected", "hover", "focus", "active", "visible", "displayed", "panel", "animation"),
        "event_message_ai": ("event", "message", "notification", "unread", "candidate", "plan", "ai_"),
    }
    focus = {
        group: [
            str(row["qualified_name"]) for row in rows
            if any(word in f"{row['path']}/{row['name']}".lower() for word in words)
        ]
        for group, words in focus_words.items()
    }
    high_risk = {
        "multi_writer_state": [
            {
                "member": row["qualified_name"],
                "location": f"{row['path']}:{row['line']}",
                "writer_files": row["writer_files"],
                "risk": row["risk"],
            }
            for row in rows
            if not row["is_const"] and len(row["writer_files"]) > 1
        ],
        "formal_ui_state_mix": [
            {
                "group": "player identity",
                "members": [
                    "GameSessionService.player_character",
                    "holographic_workspace_runtime.active_character_key",
                ],
                "evidence": [
                    "scripts/character/game_session_service.gd:8",
                    "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:36",
                    "scripts/formal/formal_world_application.gd:2",
                ],
            },
            {
                "group": "formal-looking events generated by presentation",
                "members": [
                    "holographic_workspace_runtime._world_events",
                    "holographic_workspace_runtime.activity_unread",
                ],
                "evidence": [
                    "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:48",
                    "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:68",
                    "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:475",
                    "scripts/formal/formal_world_application.gd:2",
                ],
            },
        ],
        "derived_value_independent_writes": [
            {
                "member": row["qualified_name"],
                "location": f"{row['path']}:{row['line']}",
                "write_sites": row["runtime_write_sites"],
            }
            for row in rows if row["category"] == "B" and row["runtime_write_sites"]
        ],
        "persistence_keys_without_same_named_runtime_member": [
            item for item in persistence_fields if item["field"] not in member_names_set
        ],
        "alpha_v23_formal_boundary": [
            {
                "member": row["qualified_name"],
                "location": f"{row['path']}:{row['line']}",
                "formal_reference_sites": row["formal_product_reference_sites"],
            }
            for row in rows
            if str(row["path"]).startswith(("scripts/alpha/", "scripts/v2_3/"))
            and row["formal_product_reference_sites"]
        ],
        "same_spelling_different_owner": repeated,
        "near_semantic_state": near,
        "manual_high_risk": [
            {
                "id": "formal_last_day_index_restore",
                "risk": "P1",
                "members": ["FormalWorldEconomyService._last_day_index", "FormalWorldSimulation.total_minutes"],
                "evidence": [
                    "scripts/formal/formal_world_economy_service.gd:219-220",
                    "scripts/formal/formal_world_economy_service.gd:237-255",
                    "scripts/formal/formal_world_economy_service.gd:805-838",
                ],
                "finding": "last_day_index 可从存档独立恢复，_validate_state 未见与权威 total_hour 的一致性校验；篡改或旧值可能影响日结边界。",
            },
            {
                "id": "juridical_control_alias",
                "risk": "P1",
                "members": ["political unit controller_id", "UI projection sovereign_id"],
                "evidence": [
                    "data/world_map/historical/political_units_1900.json:1",
                    "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd:118-120",
                ],
                "finding": "展示投影把 controller_id 同时写成 sovereign_id；当前 schema 没有独立法理归属字段，不能声称法理与实际控制已经分离。",
            },
        ],
    }
    return {
        "schema_version": "variable-state-audit/v1",
        "audit_date": AUDIT_DATE,
        "baseline": {
            "fixed_base_sha": expected_base,
            "checked_out_head": head,
            "branch": git(root, "branch", "--show-current"),
            "integration_branch_sha": expected_base,
            "master_sha": MASTER_SHA,
            "merge_base": MASTER_SHA,
            "initial_status": "clean; git status --short produced no output",
        },
        "scope": [rel(root, path) for path in files],
        "methodology": {
            "classification": "Every production member declaration, including constants, has exactly one A-I primary category. Constants are immutable A inputs unless stronger E/F/H evidence applies.",
            "read_write_evidence": "Production-script same-file lexical references plus owner-qualified or receiver-type-resolved external references; unresolved .member receivers are retained separately as ambiguous candidates. Tests, tools and configuration references are supporting evidence, not production writers. Declaration initialization is separate from runtime writes.",
            "persistence_evidence": "String keys in persistence-named functions plus tracked JSON save/fixture keys.",
            "dynamic_limitations": "Non-literal get/set/call/call_deferred, Variant dispatch, external scripts, engine callbacks, scene injection and UID/resource indirection cannot be exhaustively resolved statically.",
            "deletion_policy": "No category authorizes deletion, merge, rename, type change or production behavior change.",
        },
        "metrics": metrics,
        "members": rows,
        "important_locals": important_locals,
        "persistence_fields": persistence_fields,
        "dynamic_access_candidates": dynamic,
        "scene_node_paths": scene_nodes,
        "signal_candidates": signals,
        "repeated_name_groups": repeated,
        "focus_groups": focus,
        "high_risk_findings": high_risk,
    }


def cell(value: object, limit: int = 900) -> str:
    if isinstance(value, list):
        text = "<br>".join(str(item) for item in value) if value else "—"
    else:
        text = str(value) if value not in (None, "") else "—"
    return text.replace("|", "\\|").replace("\r", " ").replace("\n", " ")[:limit]


def inventory_markdown(payload: dict[str, object]) -> str:
    metrics = payload["metrics"]
    baseline = payload["baseline"]
    assert isinstance(metrics, dict) and isinstance(baseline, dict)
    lines = [
        "# WWO 全仓库变量与状态可追溯清单（2026-08-03）",
        "",
        f"> 固定 Base：`{baseline['fixed_base_sha']}`。由 `tools/audit_formal_variable_state.py` 确定性生成；静态候选不等于删除结论。",
        "",
        "## 范围与限制",
        "",
        f"- 扫描文件：{metrics['scanned_files']}；生产 GDScript：{metrics['production_gdscript_files']}。",
        f"- 生产成员变量：{metrics['member_variables']}；静态变量：{metrics['static_variables']}；常量：{metrics['constants']}。",
        f"- 持久化字段候选：{metrics['persistence_fields']}；动态调用候选：{metrics['dynamic_call_candidates']}；重要局部状态：{metrics['important_locals']}。",
        "- 写入/读取位置是保守的词法证据。非字面反射、Variant、引擎回调、场景注入和外部脚本可能产生静态不可见调用。",
        "",
        "## 每个生产成员变量与常量",
        "",
        "| 完整名称 / 声明 | 类型 / 初值 | 系统 / 实际含义 | 写入者 / 读取者 | 生命周期 / 存档 | 可计算 / 缓存 / UI | 近似变量 / 修改者 | 分类 / 风险 / 建议 | 证据 |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    members = payload["members"]
    assert isinstance(members, list)
    for row in members:
        assert isinstance(row, dict)
        values = (
            f"`{row['qualified_name']}`<br>`{row['path']}:{row['line']}`<br>{row['declaration_kind']}",
            f"{row['declared_type'] or row['inferred_type']}<br>初值：{row['initializer']}<br>来源：{row['initializer_source']}",
            f"{row['system']}<br>{row['meaning']}",
            f"生产写：{cell(row['runtime_write_sites'], 320)}<br>生产读：{cell(row['read_sites'], 320)}<br>跨 owner 未解析：写 {cell(row['ambiguous_external_write_sites'], 150)}；读 {cell(row['ambiguous_external_read_sites'], 150)}<br>测试/工具/配置：{cell(row['test_tool_config_reference_sites'], 160)}",
            f"{row['lifecycle']}<br>存档：{row['persisted']}",
            f"计算：{row['computable']}<br>缓存：{row['cache']}；失效：{row['cache_invalidation']}<br>UI：{row['ui_state']}",
            f"{row['similar_basis']}<br>{cell(row['similar_variables'], 340)}<br>修改者：{row['current_unique_modifier']}",
            f"{row['category']} / {row['risk']}<br>{row['category_reason']}<br>{row['recommendation']}",
            cell(row["evidence"], 520),
        )
        lines.append("| " + " | ".join(cell(value) for value in values) + " |")
    lines.extend([
        "", "## 重要局部状态", "",
        "这些局部值按名称或所在函数进入事务、恢复、回滚、候选或选择边界；不计入成员变量。", "",
        "| 完整名称 | 位置 | 类型 / 初值 | 系统 | 生命周期 / 持久化 | 证据 |",
        "|---|---|---|---|---|---|",
    ])
    locals_rows = payload["important_locals"]
    assert isinstance(locals_rows, list)
    for row in locals_rows:
        assert isinstance(row, dict)
        lines.append("| " + " | ".join(cell(value) for value in (
            f"`{row['qualified_name']}`", f"`{row['path']}:{row['line']}`",
            f"{row['declared_type']} / {row['initializer']}", row["system"],
            f"{row['lifecycle']} / {row['persistence']}", row["evidence"],
        )) + " |")
    lines.extend([
        "", "## 持久化字段候选", "",
        "这些键可能是嵌套字段、校验字段或兼容字段，不保证存在同名运行期成员。", "",
        "| 字段 | 来源 | 位置 |", "|---|---|---|",
    ])
    fields = payload["persistence_fields"]
    assert isinstance(fields, list)
    for row in fields:
        assert isinstance(row, dict)
        lines.append(
            f"| `{cell(row['field'])}` | {cell(row['source'])} | {cell(row['sites'], 850)} |"
        )
    return "\n".join(lines) + "\n"


def normalized_artifact(payload: dict[str, object]) -> dict[str, object]:
    """Deduplicate evidence strings without dropping any inventory evidence."""
    evidence_values: set[str] = set()

    def collect(value: object, key: str = "") -> None:
        if key in EVIDENCE_REFERENCE_KEYS:
            if isinstance(value, str):
                evidence_values.add(value)
            elif isinstance(value, list):
                for item in value:
                    collect(item, key)
            elif isinstance(value, dict):
                for item in value.values():
                    collect(item, key)
            return
        if isinstance(value, dict):
            for child_key, item in value.items():
                collect(item, str(child_key))
        elif isinstance(value, list):
            for item in value:
                collect(item, key)

    collect(payload)
    evidence_table = sorted(evidence_values)
    evidence_ids = {value: index for index, value in enumerate(evidence_table)}

    def encode(value: object, key: str = "") -> object:
        if key in EVIDENCE_REFERENCE_KEYS:
            if isinstance(value, str):
                return evidence_ids[value]
            if isinstance(value, list):
                return [encode(item, key) for item in value]
            if isinstance(value, dict):
                return {
                    child_key: encode(item, key)
                    for child_key, item in value.items()
                }
        if isinstance(value, dict):
            return {
                child_key: encode(item, str(child_key))
                for child_key, item in value.items()
            }
        if isinstance(value, list):
            return [encode(item, key) for item in value]
        return value

    result = encode(payload)
    assert isinstance(result, dict)
    result["schema_version"] = "variable-state-audit/v2-normalized"
    result["artifact_encoding"] = {
        "evidence_reference": (
            "Integer values in evidence-bearing fields index evidence_table."
        ),
        "evidence_reference_fields": sorted(EVIDENCE_REFERENCE_KEYS),
        "evidence_table_entries": len(evidence_table),
    }
    result["evidence_table"] = evidence_table
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--base-sha", default=FIXED_BASE)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    return parser.parse_args()


def write_explicit(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def main() -> None:
    args = parse_args()
    payload = build_payload(args.root.resolve(), args.base_sha)
    if args.json_output:
        write_explicit(
            args.json_output.resolve(),
            json.dumps(
                normalized_artifact(payload), ensure_ascii=False, sort_keys=True,
                separators=(",", ":"),
            ) + "\n",
        )
    if args.markdown_output:
        write_explicit(args.markdown_output.resolve(), inventory_markdown(payload))
    print(json.dumps(payload["metrics"], ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
