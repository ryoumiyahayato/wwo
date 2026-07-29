#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "builds" / "variable-state-audit" / "variable_state_inventory.json"
OUTPUT_PATH = ROOT / "docs" / "refactors" / "variable_state_member_inventory.md"
CATEGORY_TEXT = {
    "A": "唯一事实源候选", "B": "外部配置", "C": "不可变常量",
    "D": "节点或资源引用", "E": "可推导派生值候选",
    "F": "缓存候选，需核对失效规则", "G": "UI显示副本候选",
    "H": "兼容字段候选", "I": "临时迁移字段候选",
    "J": "无用字段候选", "K": "语义不明确，暂时不得修改",
}


def clean(value: object) -> str:
    return str(value).replace("\t", " ").replace("\n", " ")


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

- 基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。
- 引擎：Godot 4.6.3。
- 范围：`project.godot`、`scripts/`、`scenes/`、`data/`、`resources/`。
- 本文件只提供静态成员索引证据，不持有审计结论、实施方案、多写入/UI副本总结或停止项。

## 静态扫描限制

- 函数局部变量不进入表；每项只记录声明行、A–K静态分类和字段名。
- 分类是候选证据，不能代替qualified写入、读取和持久化核验。
- 同名字段不得据此自动合并或删除。

## 基线指标

|成员|可写|全局|Autoload|持久化|兼容|UI|缓存|派生|K类|源文件|GDScript|
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|{metrics['member_fields_total']}|{metrics['writable_member_fields_total']}|{metrics['global_writable_fields_total']}|{metrics['autoload_writable_fields_total']}|{metrics['persisted_member_fields_by_static_evidence']}|{metrics['compatibility_alias_candidates']}|{metrics['ui_copy_candidates']}|{metrics['cache_candidates']}|{metrics['derived_member_candidates']}|{metrics['unclear_member_fields']}|{metrics['source_files_scanned']}|{metrics['gdscript_files_scanned']}|

## A–K分类说明

"""]
    lines.extend(f"- **{key}**：{value}。\n" for key, value in CATEGORY_TEXT.items())
    lines.append("\n## 1,613个生产成员字段逐项表\n\n```text\n文件/所有者；随后各行为：声明行 分类 字段\n")
    for path in sorted(grouped):
        records = grouped[path]
        owners = {record["owner"] for record in records}
        if len(owners) != 1:
            raise RuntimeError(f"multiple owners in {path}")
        owner = next(iter(owners))
        lines.append(f"@ {clean(path)} | {clean(owner)}\n")
        for record in records:
            lines.append(f"{record['line']} {record['category']} {clean(record['name'])}\n")
    lines.append("```\n")
    OUTPUT_PATH.write_text("".join(lines), encoding="utf-8")
    print(f"wrote {OUTPUT_PATH} with {len(members)} member rows")


if __name__ == "__main__":
    main()
