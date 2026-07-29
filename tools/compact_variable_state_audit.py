#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "builds" / "variable-state-audit" / "variable_state_inventory.json"
AUDIT_PATH = ROOT / "docs" / "refactors" / "variable_state_audit.md"


def escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def main() -> None:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    metrics = inventory["metrics"]
    members = [item for item in inventory["members"] if item["is_production"]]
    paths = sorted({item["path"] for item in members})
    file_ids = {path: f"F{index + 1:03d}" for index, path in enumerate(paths)}
    repeat_counts = Counter(
        item["name"]
        for item in members
        if not item["is_const"] and not item["is_onready"]
    )

    def lifecycle(item: dict) -> str:
        return {
            "process-global static lifetime": "进程",
            "scene/node lifetime": "场景",
            "service/resource instance": "实例",
        }.get(item["lifecycle"], item["lifecycle"])

    def writer_summary(item: dict) -> str:
        sites = item.get("write_sites") or []
        if not sites:
            return "0"
        own_count = sum(site.startswith(item["path"] + ":") for site in sites)
        external_files: list[str] = []
        for site in sites:
            path = site.split(":", 1)[0]
            if path != item["path"] and path in file_ids:
                file_id = file_ids[path]
                if file_id not in external_files:
                    external_files.append(file_id)
        suffix = ""
        if external_files:
            suffix = "/同名" + ",".join(external_files[:2])
            if len(external_files) > 2:
                suffix += f"+{len(external_files) - 2}"
        return f"本{own_count}{suffix}"

    def reader_summary(item: dict) -> str:
        reader_ids: list[str] = []
        for path in item.get("reader_files") or []:
            if path in file_ids and file_ids[path] not in reader_ids:
                reader_ids.append(file_ids[path])
        if not reader_ids:
            return "0"
        rendered = ",".join(reader_ids[:3])
        if len(reader_ids) > 3:
            rendered += f"+{len(reader_ids) - 3}"
        return rendered

    def duplicate_group(item: dict) -> str:
        path = item["path"]
        name = item["name"]
        if path == "scripts/character/game_session_service.gd" and name == "selected_country_id":
            return "D05"
        if path == "scripts/formal/formal_world_application.gd" and name == "_last_summary":
            return "D-UI"
        if path == "scripts/formal/formal_world_simulation.gd" and name in {
            "total_minutes", "_minute_remainder",
        }:
            return "D01"
        if path == "scripts/formal/formal_world_economy_service.gd" and name in {
            "economy_polity_ids", "economy_by_polity_id", "_crosswalk_records",
            "polity_records", "country_states",
        }:
            return "D02"
        if repeat_counts[name] > 1:
            return f"N×{repeat_counts[name]}"
        return "—"

    def derivation(item: dict) -> str:
        path = item["path"]
        name = item["name"]
        if path == "scripts/character/game_session_service.gd" and name == "selected_country_id":
            return "是:玩家国家"
        if path == "scripts/formal/formal_world_application.gd" and name == "_last_summary":
            return "是:世界摘要"
        return "候选" if item.get("derivation_candidate") else "否"

    def recommendation(item: dict) -> str:
        if (
            item["path"] == "scripts/character/game_session_service.gd"
            and item["name"] == "selected_country_id"
        ):
            return "B1候选"
        return {
            "A": "核对所有权",
            "B": "配置保留",
            "C": "常量保留",
            "D": "引用保留",
            "E": "验证后推导",
            "F": "补失效证据",
            "G": "核对UI镜像",
            "H": "仅加载边界",
            "I": "仅迁移边界",
            "J": "确认后删除",
            "K": "禁止修改",
        }.get(item["category"], "核对")

    header = f"""# 变量、状态所有权与数据流审计

## 0. 审计边界

- 审计基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。
- 引擎：Godot 4.6.3；正式入口：`res://scenes/formal/formal_world_menu.tscn`。
- 本文件只记录审计；未修改 `scripts/`、`scenes/`、`data/` 或 `resources/`。
- 扫描 {metrics['source_files_scanned']} 个源/配置文件、{metrics['gdscript_files_scanned']} 个 GDScript 文件；函数局部变量不进入成员表。
- 静态写入/读取中的“同名外部”只是候选，不能代替 qualified 核验。

## 1. 基线指标

|指标|值|
|---|---:|
|生产成员字段|{metrics['member_fields_total']}|
|可写成员字段|{metrics['writable_member_fields_total']}|
|进程级 `static var`|{metrics['global_writable_fields_total']}|
|Autoload 可写字段|{metrics['autoload_writable_fields_total']}|
|持久化关联候选|{metrics['persisted_member_fields_by_static_evidence']}|
|UI 副本候选|{metrics['ui_copy_candidates']}|
|命名缓存候选|{metrics['cache_candidates']}|
|可推导候选|{metrics['derived_member_candidates']}|
|K 类禁止修改|{metrics['unclear_member_fields']}|

## 2. 最严重的 10 组重复或混乱状态

|等级|组|当前事实与问题|证据|建议|
|---|---|---|---|---|
|P0|D01 正式时间三重表示及已确认初始错位|半球 UI 初始为 `1900-03-12 08:00`；正式模拟与经济从 `1900-01-01 00:00`开始。计时分别推进两套时间；新游戏已经错位，读取正式存档后也未恢复半球 UI 时间。|`holographic_workspace_runtime.gd:48-54`; `formal_world_application.gd:17-41,62-69`; `formal_world_simulation.gd:13-89`; `formal_world_economy_service.gd:21-55`; `v2_datetime.gd:3-18`|P0 现存正确性缺陷；本审计批不得顺带修复。|
|P0|D02 经济体—政治单元关系的来源、索引与持久化混合|权威原始来源是交叉表，一对一关系可直接解析；`economy_polity_ids`是正向只读索引，`economy_by_polity_id`是反向只读索引，`country_states[*].polity_ids`是持久化重复字段，`polity_records[*].economy_entity_id`是 UI/摘要投影。索引可能必要，不能预设全部删除。|`major_economy_polity_crosswalk_1900.json`; `formal_world_economy_service.gd:21-38,46-64,115-246`|分别评估来源不可变性、索引查询成本、持久化副本和 UI 投影。|
|P0|D03 导航层级多个直接写入者|`space_level/world_mode`在继承链多处直接赋值并同步 viewport、渲染与选择清理。|runtime/history/admin1/historical_admin/release|建立明确 transition 命令。|
|P0|D04 一级行政选择平行状态|四个字段服务历史领土、历史几何、现代近似几何和名称目录，ID 空间不同。|history/admin1/polish/historical_admin|先建 ID 命名空间矩阵，不按名称合并。|
|P0|D05 `selected_country_id`同名不同义|会话字段表示玩家所属国家；半球字段表示地图选择。|game_session/runtime/save|绝不能合并；第一批只审计前者。|
|P1|D06 当前玩家/角色/显示身份分立|`player_character`、`active_character_key`、`selected_person_id`语义未对齐。|session/runtime/life simulation|人工定义 active/displayed/selected。|
|P1|D07 事件、消息、未读数缺少正式所有者|半球展示事件与事件队列、通知、通信 inbox 并存。|runtime/event queue/notification/communication|确定正式服务，HUD 只读。|
|P1|D08 旧地图画布—界面双写|Canvas 与 Interface 分别保存模式和选择，Controller 同时写两边。|旧地图三文件|决定删除/隔离；若保留则 UI 只读。|
|P1|D09 跨服务同步复制业务事实|位置、债务、工人/容量/空缺被同步到第二容器。|V2.3/Alpha 同步函数|分别选择空间、金融、劳动所有者。|
|P1|D10 存档兼容/fallback 混入内部状态|多 schema 与缺省补写进入运行结构。|正式存档/分钟时钟|迁移只留在加载边界。|

## 2.1 已确认的现存正确性缺陷：正式时间初始错位（P0）

1. 半球 UI 字段初始为 **1900-03-12 08:00**（`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:48-54`）。
2. `FormalWorldSimulation.total_minutes/_minute_remainder`和`FormalWorldEconomyService.total_hour`从 0 开始；`V2DateTime`将 0 定义为 **1900-01-01 00:00**（`scripts/formal/formal_world_simulation.gd:13-23`; `scripts/formal/formal_world_economy_service.gd:21-28,40-55`; `scripts/v2_2/v2_datetime.gd:3-18`）。
3. `FormalWorldApplication._on_clock_timer_timeout()`先推进继承层时钟，再推进正式模拟（`scripts/formal/formal_world_application.gd:34-41`）。
4. 新游戏初始化没有对齐半球 `sim_*`与正式累计时间，因此初始相差 70 天 8 小时。
5. 读取正式存档只恢复 `formal_simulation`并刷新摘要，没有恢复半球 `sim_year/month/day/hour/minute`（`scripts/formal/formal_world_application.gd:23-30,62-69`）。

风险：HUD日期、经济结算和存档时间可长期表示不同日期。本批只记录，不修复。

## 3. 多写入者、UI/缓存副本与停止项

- 多写入：正式时间、导航层级、各层选择、玩家国家、经济映射、旧地图模式/选择、跨服务位置/债务/劳动副本。
- UI/派生候选：`FormalWorldApplication._last_summary`、旧 Interface 模式/选择/暂停/速度、`activity_unread`。
- 不得修改：所有未建立 fixture 的持久化字段、四种行政选择、玩家/角色/显示身份、导航、无性能基线缓存、previous/边沿检测状态，以及不同语义的 selected/hovered/focused/active/pending/displayed/loaded/visible/enabled。

## 4. 推荐第一批范围（尚未实施）

### 4.1 唯一事实源

第一批只处理 `GameSessionService.selected_country_id`。候选唯一事实源为 `GameSessionService.player_character.country_id`。半球地图同名字段语义不同，不修改。旧存档键继续在保存边界推导、加载边界验证。

### 4.2 qualified 引用清单

- 成员声明：`scripts/character/game_session_service.gd:9`。
- 合格读取：`scripts/save/game_save_service.gd:229`；未发现其他合格运行期读取。
- 合格写入：`scripts/character/game_session_service.gd:27,45,80`；`scripts/character/succession_service.gd:280`；`scripts/save/game_save_service.gd:509`。
- 存档键：生成 `scripts/save/game_save_service.gd:229`；读取与一致性验证 `:455-460`；必需键验证 `:603`。
- 同名其他成员：`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:23`，表示地图政治单元选择；全仓库只发现这一个其他同名成员。
- 函数局部同名：`scripts/save/game_save_service.gd:455`；全仓库未发现其他 `var selected_country_id`局部声明。

### 4.3 实施前测试计划

1. 当前 `SAVE_VERSION = 1`存档 fixture，证明重构前可加载。
2. 保存后旧键等于 `player_character.country_id`。
3. 旧键不一致必须拒绝且事务不提交。
4. 玩家转移测试。
5. 人物继承成功测试。
6. 人物继承事务回滚测试。
7. 地图选择与玩家国家互不影响测试。
8. `GameSessionService.clear()`后派生国家为空。

### 4.4 预计数量

|项目|数量|
|---|---:|
|删除可写成员|1|
|保留其他 session static var|14|
|新增可写成员|0|
|减少重复可写事实|1|
|删除存档键/fallback/同步函数|0|
|预计生产文件|3-5|

实施前仍须建立 fixture 与测试；本次只修订审计。

## 5. 分类与压缩记号

A事实源；B配置；C常量；D引用；E派生；F缓存；G UI副本；H兼容；I迁移；J无用；K语义不明。`本N/同名Fxxx`是静态候选计数，不是 qualified 结论；读取者列使用文件编号，路径见文件索引。

## 6. 完整成员字段清单

|字段|文件|所属类/节点|类型|生命周期|写入者|读取者|持久化|可推导|重复组|分类|建议|
|---|---|---|---|---|---|---|---|---|---|---|---|
"""

    lines = [header]
    for item in sorted(members, key=lambda value: (value["path"], value["line"], value["name"])):
        lines.append(
            "|`{name}`|`{file_id}:{line}`|`{owner}`|`{type}`|{lifecycle}|{writers}|"
            "{readers}|{persisted}|{derived}|{duplicate}|{category}|{recommendation}|\n".format(
                name=escape(item["name"]),
                file_id=file_ids[item["path"]],
                line=item["line"],
                owner=escape(item["owner"]),
                type=escape(item["declared_type"] or "推断"),
                lifecycle=lifecycle(item),
                writers=writer_summary(item),
                readers=reader_summary(item),
                persisted="候选" if item["persisted_by_name"] else "否",
                derived=derivation(item),
                duplicate=duplicate_group(item),
                category=item["category"],
                recommendation=recommendation(item),
            )
        )

    lines.append("\n## 7. 文件索引\n\n|编号|路径|\n|---|---|\n")
    for path in paths:
        lines.append(f"|`{file_ids[path]}`|`{path}`|\n")
    AUDIT_PATH.write_text("".join(lines), encoding="utf-8")
    print(f"wrote {AUDIT_PATH} with {len(members)} member rows")


if __name__ == "__main__":
    main()
