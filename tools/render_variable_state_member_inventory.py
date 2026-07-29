#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "builds" / "variable-state-audit" / "variable_state_inventory.json"
OUTPUT_PATH = ROOT / "docs" / "refactors" / "variable_state_member_inventory.md"
PART_BYTE_LIMIT = 4500
CATEGORY_TEXT = {
    "A": "唯一事实源候选",
    "B": "外部配置",
    "C": "不可变常量",
    "D": "节点或资源引用",
    "E": "可推导派生值候选",
    "F": "缓存候选，需核对失效规则",
    "G": "UI显示副本候选",
    "H": "兼容字段候选",
    "I": "临时迁移字段候选",
    "J": "无用字段候选",
    "K": "语义不明确，暂时不得修改",
}


def clean(value: object) -> str:
    return str(value).replace("\t", " ").replace("\n", " ")


def render_path(path: str, records: list[dict]) -> str:
    owners = {record["owner"] for record in records}
    if len(owners) != 1:
        raise RuntimeError(f"multiple owners in {path}")
    owner = next(iter(owners))
    lines = [f"@ {clean(path)} | {clean(owner)}\n"]
    for record in records:
        lines.append(
            f"{record['line']} {record['category']} {clean(record['name'])}\n"
        )
    return "".join(lines)


def partition_paths(grouped: dict[str, list[dict]]) -> list[list[str]]:
    parts: list[list[str]] = []
    current: list[str] = []
    current_size = 0
    for path in sorted(grouped):
        rendered_size = len(render_path(path, grouped[path]).encode("utf-8"))
        if current and current_size + rendered_size > PART_BYTE_LIMIT:
            parts.append(current)
            current = []
            current_size = 0
        current.append(path)
        current_size += rendered_size
    if current:
        parts.append(current)
    return parts


def main() -> None:
    data = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    metrics = data["metrics"]
    members = sorted(
        (item for item in data["members"] if item["is_production"]),
        key=lambda item: (item["path"], item["line"], item["name"]),
    )
    if len(members) != metrics["member_fields_total"]:
        raise RuntimeError("production member count does not match metrics")

    grouped: dict[str, list[dict]] = defaultdict(list)
    for item in members:
        grouped[item["path"]].append(item)

    lines = [f"""# 变量状态成员清单

## 审计基线

- 基线：`agent/remove-duplicated-player-country-state`当前检出提交；基础提交为`b4a9d637e294aa53b0c0e2525260421dce3b5182`。
- 引擎：Godot 4.6.3。
- 范围：`project.godot`、`scripts/`、`scenes/`、`data/`、`resources/`。
- 本文件只提供静态成员索引证据，不持有审计结论、实施方案、多写入状态总结、UI副本总结或停止项。

## 静态扫描限制

- 函数局部变量不进入表；每项只记录文件、所有者、声明行、A–K静态分类和字段名。
- 分类、写入者、读取者和持久化关联均为静态候选，不能代替qualified核验。
- 同名字段不得据此自动合并或删除。

## 基线指标

|成员|可写|全局|Autoload|持久化|兼容|UI|缓存|派生|K类|源文件|GDScript|
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|{metrics['member_fields_total']}|{metrics['writable_member_fields_total']}|{metrics['global_writable_fields_total']}|{metrics['autoload_writable_fields_total']}|{metrics['persisted_member_fields_by_static_evidence']}|{metrics['compatibility_alias_candidates']}|{metrics['ui_copy_candidates']}|{metrics['cache_candidates']}|{metrics['derived_member_candidates']}|{metrics['unclear_member_fields']}|{metrics['source_files_scanned']}|{metrics['gdscript_files_scanned']}|

## A–K分类说明

"""]
    lines.extend(f"- **{key}**：{value}。\n" for key, value in CATEGORY_TEXT.items())
    lines.append(
        f"\n## {metrics['member_fields_total']:,}个生产成员字段逐项表\n\n"
        "每个代码块中的文件标题后依次列出：`声明行 分类 字段`。\n\n"
    )

    parts = partition_paths(grouped)
    for part_index, paths in enumerate(parts, start=1):
        lines.append(
            f"### 第{part_index}段：`{paths[0]}` 至 `{paths[-1]}`\n\n"
            "```text\n"
        )
        for path in paths:
            lines.append(render_path(path, grouped[path]))
        lines.append("```\n\n")

    OUTPUT_PATH.write_text("".join(lines), encoding="utf-8")
    print(
        f"wrote {OUTPUT_PATH} with {len(members)} member rows "
        f"in {len(parts)} deterministic sections"
    )


if __name__ == "__main__":
    main()
