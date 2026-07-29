#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "builds" / "variable-state-audit" / "variable_state_inventory.json"
OUT = ROOT / "docs" / "refactors"
OUT.mkdir(parents=True, exist_ok=True)

data = json.loads(INVENTORY.read_text(encoding="utf-8"))
metrics = data["metrics"]
members = [member for member in data["members"] if member["is_production"]]
repeat_counts = Counter(
    member["name"]
    for member in members
    if not member["is_const"] and not member["is_onready"]
)

TIME_NAMES = {
    "total_minutes", "_minute_remainder", "total_hour", "total_hours", "minute",
    "hour", "day", "month", "year", "sim_minute", "sim_hour", "sim_day",
    "sim_month", "sim_year", "sim_paused", "sim_speed", "is_paused",
    "speed_multiplier",
}
ECONOMY_MAPPING_NAMES = {
    "economy_polity_ids", "economy_by_polity_id", "_crosswalk_records",
    "polity_records", "country_states",
}
NAVIGATION_NAMES = {
    "space_level", "world_mode", "selected_country_id", "selected_region_id",
    "selected_city_id", "selected_event_id", "selected_institution_id",
    "selected_historical_territory_iso", "selected_world_admin1_id",
    "selected_administrative_unit_id", "selected_admin_unit_id",
}


def duplicate_group(member: dict) -> str:
    path = member["path"]
    name = member["name"]
    if path == "scripts/formal/formal_world_simulation.gd" and name in {
        "total_minutes", "_minute_remainder",
    }:
        return "D01 正式时间三重表示"
    if path == "scripts/formal/formal_world_economy_service.gd" and name in ECONOMY_MAPPING_NAMES:
        return "D02 经济体—政治单元多份映射"
    if path.startswith("scripts/ui_spikes/holographic_workspace/") and name in NAVIGATION_NAMES:
        return "D03/D04 半球导航与行政选择分散"
    if name == "selected_country_id" and path in {
        "scripts/character/game_session_service.gd",
        "scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd",
    }:
        return "D05 同名不同义：玩家国家/地图选择"
    if path == "scripts/formal/formal_world_application.gd" and name == "_last_summary":
        return "D09 UI 世界摘要镜像"
    if name in TIME_NAMES:
        return "时间概念同名候选（必须按子系统核对）"
    if repeat_counts[name] > 1:
        return "同名字段候选×%d（不得据此自动合并）" % repeat_counts[name]
    return "—"


def derivation_status(member: dict) -> str:
    path = member["path"]
    name = member["name"]
    if path == "scripts/character/game_session_service.gd" and name == "selected_country_id":
        return "是：player_character.country_id"
    if path == "scripts/formal/formal_world_application.gd" and name == "_last_summary":
        return "是：formal_simulation.world_summary()"
    if path == "scripts/formal/formal_world_economy_service.gd" and name == "_political_unit_count":
        return "候选：polity_records.size()；保留计数校验需另证"
    if member["derivation_candidate"]:
        return "候选：需核对计算成本与一致性"
    return "否/未证明"


def writer_summary(member: dict) -> str:
    sites = member.get("write_sites") or []
    own_sites = [site for site in sites if site.startswith(member["path"] + ":")]
    external_sites = [site for site in sites if not site.startswith(member["path"] + ":")]
    result: list[str] = []
    if own_sites:
        result.append("本文件%d处" % len(own_sites))
    if external_sites:
        files: list[str] = []
        for site in external_sites:
            path = site.split(":", 1)[0]
            if path not in files:
                files.append(path)
        result.append("外部同名候选：" + ", ".join("`%s`" % path for path in files[:3]))
    return "；".join(result) if result else "未发现赋值（可能仅初始化/解析限制）"


def reader_summary(member: dict) -> str:
    files = member.get("reader_files") or []
    if not files:
        return "未发现读取（需确认无用字段）"
    rendered = ", ".join("`%s`" % path for path in files[:4])
    return rendered + (" 等%d文件" % len(files) if len(files) > 4 else "")


def recommendation(member: dict) -> str:
    path = member["path"]
    name = member["name"]
    category = member["category"]
    if path == "scripts/character/game_session_service.gd" and name == "selected_country_id":
        return "第一批候选：内部删除；存档边界由 player_character.country_id 推导并校验"
    if path == "scripts/formal/formal_world_application.gd" and name == "_last_summary":
        return "删除候选：绘制时只读推导，或使用有明确失效事件的只读缓存"
    if path == "scripts/formal/formal_world_simulation.gd" and name in {
        "total_minutes", "_minute_remainder",
    }:
        return "暂不改：先建立正式时间行为与存档 fixture，再统一时钟所有者"
    if path == "scripts/formal/formal_world_economy_service.gd" and name in ECONOMY_MAPPING_NAMES:
        return "暂不改：先规定交叉表源与只读索引，再删除双写"
    if category == "C":
        return "保留：不可变常量"
    if category == "D":
        return "保留：节点/资源引用，不属于业务状态压缩目标"
    if category == "B":
        return "核对场景覆盖后保留为设计器配置；不得在运行时改写"
    if category == "F":
        return "暂保留：补缓存键、失效条件和性能基线；无证据则删除"
    if category == "G":
        return "核对是否业务镜像；可以从所有者刷新则删除可写副本"
    if category in {"H", "I"}:
        return "仅限加载迁移边界；注明支持版本和删除条件"
    if category == "E":
        return "验证推导成本；低成本则改为只读推导"
    if category == "J":
        return "删除候选：先确认无读写、无场景序列化"
    if category == "K":
        return "禁止修改：语义或全部写入者尚未确认"
    return "候选事实源：核对唯一所有者和写入入口"


def escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def write_variable_audit() -> None:
    introduction = f"""# 变量、状态所有权与数据流审计

## 0. 审计边界

- 审计基线：`agent/formal-world-economy-integration` 提交 `950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。
- 引擎：Godot 4.6.3。
- 默认正式入口：`res://scenes/formal/formal_world_menu.tscn`。
- 本文件只包含审计结论；未修改任何 `scripts/`、`scenes/`、`data/` 或 `resources/` 生产内容。
- 扫描范围：`project.godot`、`scripts/`、`scenes/`、`data/`、`resources/`；共 {metrics['source_files_scanned']} 个源/配置文件、{metrics['gdscript_files_scanned']} 个 GDScript 文件。
- 仓库无 `[autoload]` 配置，因此 Autoload 可写字段为 0；`static var` 仍形成进程级全局状态。

### 证据等级与限制

1. **人工确认**：直接读取声明、写入函数、存档边界和场景入口。
2. **静态候选**：按字段名、字符串键和赋值模式扫描。同名字段可能属于不同类，不能自动认定同一事实。
3. **禁止自动处理**：分类 K、不同 ID 命名空间、存档兼容字段、缓存，以及 `selected/hovered/focused/active/pending/previous` 等不同语义状态。
4. 函数局部变量不进入本表；本表只列顶层 GDScript 成员、常量和节点/资源引用。

## 1. 基线指标

| 指标 | 审计值 | 解释 |
|---|---:|---|
| 生产成员字段总数 | {metrics['member_fields_total']} | 包含常量、节点引用和可写成员 |
| 可写成员字段 | {metrics['writable_member_fields_total']} | 排除 `const` 与 `@onready` |
| 进程级全局可写字段 | {metrics['global_writable_fields_total']} | `static var`；主要集中于 `GameSessionService` |
| Autoload 可写字段 | {metrics['autoload_writable_fields_total']} | `project.godot` 无 Autoload |
| 持久化关联候选 | {metrics['persisted_member_fields_by_static_evidence']} | 名称/存档函数静态证据上限，不是精确存档字段数 |
| UI 显示副本候选 | {metrics['ui_copy_candidates']} | 需人工确认业务镜像 |
| 缓存候选 | {metrics['cache_candidates']} | 仅按命名；投影/索引缓存另行人工核对 |
| 可推导成员候选 | {metrics['derived_member_candidates']} | 低成本推导者优先删除可写副本 |
| 兼容/迁移字段候选 | {metrics['compatibility_alias_candidates']} | 必须限定版本和删除条件 |
| 语义不明确、不得修改 | {metrics['unclear_member_fields']} | 分类 K |
| 动态字符串键（唯一） | {metrics['dynamic_string_keys_unique']} | 包含数据配置键，不能直接视为运行时状态数 |
| 动态字符串键出现次数 | {metrics['dynamic_string_key_occurrences']} | 原始宽口径扫描值 |
| fallback 模式候选 | {metrics['fallback_candidates']} | 需区分合法可选值与掩盖必需数据 |
| 同步函数候选 | {metrics['sync_function_candidates']} | 已人工确认部分是跨服务副本同步 |
| 通用 Dictionary 状态容器候选 | {metrics['generic_dictionary_state_container_candidates']} | 需核对键集合是否真正动态 |

## 2. 最严重的 10 组重复或混乱状态

| 等级 | 组 | 当前事实与问题 | 证据文件 | 审计建议 |
|---|---|---|---|---|
| P0 | D01 正式时间三重表示 | 半球继承层写 `sim_year/month/day/hour/minute`；`FormalWorldSimulation` 写 `total_minutes/_minute_remainder`；经济服务写 `total_hour`。一次计时器回调推进两套时间，存档也保存可互推字段。 | `holographic_workspace_runtime.gd`; `formal_world_application.gd`; `formal_world_simulation.gd`; `formal_world_economy_service.gd` | 单独批次统一到正式时钟；UI 只读快照，经济接收小时推进。先建旧存档 fixture。 |
| P0 | D02 经济体—政治单元映射五份可写表示 | 交叉表、`country_states[*].polity_ids`、`economy_polity_ids`、`economy_by_polity_id`、`polity_records[*].economy_entity_id`表达同一关系，恢复时还会补写。 | `formal_world_economy_service.gd` | 规定一个加载后的只读源和必要索引；国家状态、政权记录不得再保存关系副本。 |
| P0 | D03 导航层级多个直接写入者 | `space_level/world_mode`在长继承链多个脚本直接赋值，并手动同步 viewport 可见性、渲染模式和选择清理。 | `holographic_workspace_runtime.gd`; `history.gd`; `admin1.gd`; `historical_admin_runtime.gd`; `release.gd` | 状态留在正式场景控制器；建立明确 transition 命令，其他层不得直接写。 |
| P0 | D04 一级行政选择平行状态 | `selected_historical_territory_iso`、`selected_world_admin1_id`、`selected_administrative_unit_id`、`selected_admin_unit_id`服务不同数据源，其中多项都表示当前一级区。 | `history.gd`; `admin1.gd`; `polish.gd`; `historical_admin_runtime.gd` | 不能按名称合并。先建立 ID 命名空间与 crosswalk/视图路径矩阵。 |
| P0 | D05 `selected_country_id` 同名不同义 | `GameSessionService.selected_country_id`始终跟随玩家国家；半球同名字段是用户地图选择。一个是 active player country，一个是 selected map polity。 | `game_session_service.gd`; `holographic_workspace_runtime.gd`; `game_save_service.gd` | 绝不能合并。第一批删除前者运行时副本；后者后续改成明确地图选择名。 |
| P1 | D06 当前玩家/当前角色/显示身份分立 | `player_character`、`active_character_key`、`selected_person_id`分别代表进程玩家、HUD身份和模拟选中人物，正式组合根未说明关系。 | `game_session_service.gd`; `holographic_workspace_runtime.gd`; `v2_life_loop_simulation.gd` | 先定义 active/displayed/selected；未确认前全部保留。 |
| P1 | D07 事件、消息、未读数缺少业务所有者 | 半球从机构 agenda 生成 `_world_events/_event_by_id` 并写 `activity_unread`；其他系统另有事件队列、通知和通信 inbox。 | `holographic_workspace_runtime.gd`; `simulation_event_queue.gd`; `v2_notification_service.gd`; `communication_service.gd` | 确定正式事件/消息服务；HUD 只读未读投影。 |
| P1 | D08 旧地图画布—界面双写 | Canvas 保存 `current_mode/selected_id/selected_type`，Interface 另存 `current_mode/selected_object`；Controller 每次同时写两边。 | `world_map_canvas_impl.gd`; `world_map_interface_impl.gd`; `world_map_controller_impl.gd` | 决定删除或隔离旧样机；若保留，画布拥有选择/模式，UI 只读。 |
| P1 | D09 跨服务同步复制业务事实 | `_sync_formal_person_states`复制空间位置；`_sync_household_debt`复制债务；`_sync_labor_market`复制工人、容量和空缺到企业/岗位。 | `v2_3_life_loop_simulation.gd`; `v2_3_finance_service.gd`; `alpha_economy_integration_service.gd` | 分别选择空间、金融、劳动所有者；先补行为测试与存档审计。 |
| P1 | D10 存档兼容/fallback 混入内部状态 | 正式存档同时保存可互推时间；恢复支持多 schema，并补 `polity_ids`、分钟、序列号等默认值。 | `formal_world_simulation.gd`; `formal_world_economy_service.gd`; `v2_3_minute_clock.gd` | 兼容转换只在加载边界；转换后内部只能使用新结构。当前不得删除。 |

## 3. 多写入者、UI/缓存副本与停止项

### 已人工确认的多写入状态

- 正式时间、`space_level/world_mode`、国家/大区/城市/事件/机构选择、四种行政选择、玩家与玩家国家、经济映射，以及旧地图模式/选择。
- 跨服务位置、债务、劳动容量与空缺由同步函数写入第二个容器。

### 可直接列为删除候选的 UI/派生副本

- `FormalWorldApplication._last_summary`：来自 `formal_simulation.world_summary()`，在 ready/tick/load 手工刷新。
- `PrototypeV2Interface.current_mode/selected_object`：旧画布状态镜像。
- `PrototypeV2Interface.paused/speed`：有 binding 时是时钟镜像，无 binding 时又自行成为事实源。
- `activity_unread`：展示层自写，未绑定正式通知所有者。

### 当前不得安全修改

1. 所有可能进入正式、V2、V2.3、Alpha 存档的字段，直到 fixture 与 schema 支持范围明确。
2. 四个行政选择字段，直到 ID 命名空间确定。
3. `player_character/active_character_key/selected_person_id`，直到语义确定。
4. `space_level/world_mode`，直到导航行为特征测试覆盖所有转场。
5. 投影、空间索引、可见性、标签缓存，直到记录缓存键、失效条件和性能基线。
6. `_panel_previous_*`、`_activity_panel_was_open`等 previous 状态；它们可能是恢复/边沿检测而非副本。
7. 不得合并 selected、hovered、focused、active、pending、requested、displayed、loaded、visible、enabled。

## 4. 推荐第一批范围（尚未实施）

### 子系统：`GameSessionService` 玩家国家所有权

`GameSessionService.selected_country_id`只在设置、转移、继承和恢复玩家时被写成 `player_character.country_id`；加载还强制验证二者一致。它不是独立地图选择事实。

- 唯一事实源：`GameSessionService.player_character`。
- 玩家国家：只读推导 `player_character.country_id`。
- 旧存档 JSON 键 `selected_country_id`暂时保持，在保存边界推导，在加载边界验证；运行期不保存第二份。
- 不新增 Autoload、Manager、Dictionary 容器或同步信号。

| 项目 | 预计数量 |
|---|---:|
| 删除可写成员 | 1 |
| 保留 GameSessionService 其他 static 可写成员 | 14（本批不处理） |
| 新增可写成员 | 0 |
| 减少重复可写事实 | 1 |
| 删除兼容存档键 | 0 |
| 删除 fallback | 0 |
| 删除同步函数 | 0 |
| 生产文件 | 3–5 |
| 必需测试 | 当前存档 fixture、保存/加载、继承转移、地图选择不受影响 |

阻塞条件：未创建现有存档 fixture、未完成 qualified 全仓库读写搜索前，不开始修改。

## 5. 分类

A 唯一事实源候选；B 外部配置；C 不可变常量；D 节点/资源引用；E 可推导候选；F 缓存；G UI 显示副本；H 兼容；I 迁移；J 无用；K 语义不明确、不得修改。

## 6. 完整成员字段清单

> 写入者/读取者是静态名称扫描证据。不同类同名字段可能进入“外部同名候选”；删除前必须执行 qualified 搜索和人工核对。

| 字段 | 文件 | 所属类/节点 | 类型 | 生命周期 | 写入者 | 读取者 | 是否持久化 | 是否可推导 | 疑似重复组 | 分类 | 建议 |
|---|---|---|---|---|---|---|---|---|---|---|---|
"""
    lines = [introduction]
    for member in sorted(members, key=lambda item: (item["path"], item["line"], item["name"])):
        lines.append(
            "| `{name}` | `{path}:{line}` | `{owner}` | `{type}` | {lifecycle} | "
            "{writers} | {readers} | {persisted} | {derived} | {duplicate} | {category} | {recommendation} |\n".format(
                name=escape(member["name"]),
                path=escape(member["path"]),
                line=member["line"],
                owner=escape(member["owner"]),
                type=escape(member["declared_type"] or "推断"),
                lifecycle=escape(member["lifecycle"]),
                writers=escape(writer_summary(member)),
                readers=escape(reader_summary(member)),
                persisted="是（静态证据）" if member["persisted_by_name"] else "未发现",
                derived=escape(derivation_status(member)),
                duplicate=escape(duplicate_group(member)),
                category=member["category"],
                recommendation=escape(recommendation(member)),
            )
        )
    (OUT / "variable_state_audit.md").write_text("".join(lines), encoding="utf-8")


MATRIX_ROWS = [
    ("当前玩家", "GameSessionService.player_character；roster player_character_id", "set/transfer、继承、存档恢复", "动作、存档、社会服务、HUD", "进程会话", "是", "否", "与 selected_person_id/active_character_key 未对齐", "靠调用顺序", "player_character 对象；roster ID 为持久标识", "第一批只处理派生国家"),
    ("当前国家（玩家所属）", "selected_country_id + player_character.country_id", "set/transfer/succession/load", "存档、国家入口", "进程会话", "是", "是", "2份可写", "加载时要求相等，否则拒绝", "player_character.country_id", "第一批删除运行时副本"),
    ("当前地图选择政权", "半球 selected_country_id", "鼠标、历史焦点、返回、测试", "地图、政经面板、导航", "场景", "否", "否", "与玩家国家同名不同义", "政经面板存在 home/France/首项 fallback", "正式导航控制器 selected_map_polity_id", "先补选择行为测试"),
    ("当前角色/显示身份", "active_character_key、selected_person_id、player_character", "HUD、模拟 select_person、继承", "人物面板、行动服务", "场景/模拟/进程", "部分", "部分", "displayed/selected/active 未区分", "各系统独立", "三个明确语义字段", "K：人工决定"),
    ("当前日期", "sim_*、Formal minutes、Economy total_hour、SimulationClock", "计时器、advance、恢复", "HUD、经济、事件、存档", "场景/模拟", "是", "年月日可由累计分钟推导", "至少3套可写", "Application 同时推进两套", "单一正式时钟", "P0 独立批次"),
    ("游戏速度", "sim_speed、speed_multiplier、UI speed", "输入、binding、恢复", "计时器、HUD", "场景/模拟", "部分", "UI可推导", "多份可写", "binding刷新/手工赋值", "正式时钟 speed_multiplier", "与时间同批"),
    ("暂停状态", "sim_paused、is_paused、UI paused", "输入、阻塞面板、恢复", "计时器、HUD", "场景/模拟", "部分", "UI可推导", "多份可写", "面板结束恢复 previous", "正式时钟 is_paused", "previous临时状态保留"),
    ("世界/大区/城市导航", "space_level + world_mode", "runtime/history/admin/release", "绘制、输入、面包屑、viewport", "场景", "否", "否", "多写入者并手工清理", "分支同步", "正式场景导航控制器", "P0，非第一批"),
    ("当前大区", "selected_region_id", "点击、循环、转场", "区域绘制、城市列表", "场景", "否", "否", "与 territory/admin 关系不清", "转场清空", "selected_region_id", "先映射 ID"),
    ("当前城市", "selected_city_id", "点击、enter、返回", "城市层、机构", "场景", "否", "否", "与 admin1 local 粒度可能不同", "转场清空", "selected_city_id", "补导航冒烟测试"),
    ("历史 territory", "selected_historical_territory_iso", "历史地图点击/默认选择", "历史焦点、admin1", "场景", "否", "否", "与政权/行政区不同", "fallback选择第一个 territory", "明确 historical_territory_id", "K"),
    ("历史几何 admin1", "selected_world_admin1_id", "点击、唯一记录自动进入、返回", "admin1绘制、城市层", "场景", "否", "否", "与目录/近似 admin 字段重叠", "按数据可用性分支", "historical_admin1_geometry_id", "K"),
    ("历史目录 admin", "selected_admin_unit_id", "目录按钮、翻页、返回", "目录、面包屑", "场景", "否", "否", "不是几何 ID", "手工清空", "displayed_admin_catalog_entry_id", "K"),
    ("区域近似行政分区", "selected_administrative_unit_id", "区域几何点击/换区", "区域绘制", "场景", "否", "否", "现代近似与历史数据并存", "视图 fallback", "approximate_subdivision_id", "K，需数据决定"),
    ("悬停对象", "多个 hover_*", "鼠标、缩放/转场清理", "高亮、提示", "指针/帧", "否", "否", "按对象类型分字段合理，清理分散", "各层直接清空", "场景拥有，统一清理入口", "不合并 selected"),
    ("聚焦对象", "历史焦点、camera_focus_id、Control focus", "双击、按钮、UI系统", "相机/绘制/键盘", "场景", "否", "否", "三种 focus 不同义", "各自处理", "明确 political/camera/keyboard focus", "不得合并"),
    ("活动对象", "player_character、current_action、当前活动", "行动开始/结算/选择", "行动、HUD、存档", "会话/行动", "是", "否", "active 跨业务域", "各服务判断", "各业务服务分别拥有", "不建万能 active_object"),
    ("打开面板/窗口", "economy_panel_open、workspace_open、info_open、active_hud_panel、legacy open_panel", "键盘、按钮、导航", "绘制、命中", "场景", "否", "部分", "开关与 Node.visible/viewport mode双写", "手工同步", "各场景一个明确面板选择", "正式 HUD 批次"),
    ("UI展开动画", "info_open + info_progress + Tween", "按钮、动画", "绘制、命中", "场景动画", "否", "progress不可瞬时推导", "目标与动画不同，不是重复", "Tween推进", "两者保留，progress不做业务事实", "保留"),
    ("地图倍率", "world_zoom、旧 zoom", "滚轮、预设、恢复", "相机、投影、标签", "场景", "旧地图部分", "camera.size/半径可推导", "zoom与相机属性双写", "apply geometry", "world_zoom为源", "相机批次"),
    ("相机状态", "yaw/tilt/angular_velocity/drag；旧 pan/focus", "鼠标、惯性、预设", "投影、命中", "场景", "旧地图部分", "屏幕几何可推导", "缓存与相机分散", "dirty重建", "半球拥有 yaw/tilt/zoom", "先做性能基线"),
    ("当前事件", "selected_event_id + _world_events", "HUD/地图、seed", "地图、信息面板", "场景", "否", "事件应来自服务", "展示层生成业务事件", "无跨服务一致性", "正式事件服务；UI只选ID", "事件批次"),
    ("消息/未读", "activity_unread、通知服务、communication inbox", "seed、mark read、通信", "右下HUD、消息面板", "场景/模拟", "部分", "HUD计数可推导", "多套未读事实", "各自独立", "正式消息服务 unread_count()", "事件消息批次"),
    ("游戏模式", "world_mode、layout_mode、旧 current_mode、review/truth/developer", "输入、参数、测试、恢复", "绘制、权限、数据可见性", "场景/会话", "部分", "不同概念不可合并", "mode命名过宽", "分支", "具体命名的独立模式", "分批"),
    ("加载状态", "各服务 initialized/error、SceneTree launch meta、menu _entering", "initialize/load/menu", "菜单、错误UI", "初始化/跨场景一次性", "部分", "部分", "同名 initialized 属不同服务；meta隐式全局", "bool/error/meta", "服务各自拥有；启动请求仅边界存在", "去静默默认"),
    ("存档状态", "Formal save/schema、GameSave snapshots、pending_load_path", "菜单、保存、恢复", "继续游戏、测试", "磁盘/跨场景", "是", "save_exists可查询", "多个存档体系", "各自路径/schema", "产品组合根拥有存档服务", "先建 fixture矩阵"),
    ("缓存", "投影、屏幕多边形、visible/label/text/spatial caches", "数据、相机、resize、dirty", "绘制、命中", "场景/数据版本", "否", "可重算但成本不同", "部分有dirty，部分每帧重建", "混合", "仅保留有证据缓存", "最后处理"),
]


def write_ownership_matrix() -> None:
    lines = ["""# 状态所有权矩阵

## 0. 基线与规则

基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。本矩阵只描述当前与目标所有权，不修改生产代码。

- 同一事实原则上只能有一个可写来源。
- selected、hovered、focused、active、pending、previous、requested、displayed、loaded、visible、enabled保持区分。
- UI只保存交互必需的瞬时状态；业务状态通过只读查询或命令访问。
- 不迁入 Autoload、万能 Context 或字符串键 Dictionary。

| 概念 | 当前可写所有者 | 写入者 | 只读者 | 生命周期 | 存档 | 可推导 | 副本 | 当前不一致处理 | 重构后唯一事实源 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
"""]
    for row in MATRIX_ROWS:
        lines.append("| " + " | ".join(escape(value) for value in row) + " |\n")
    lines.append("""
## 1. 第一批所有权决定

`GameSessionService.player_character`拥有当前玩家人物。玩家所属国家是该对象属性，不再允许会话服务长期保存第二个可写国家 ID。地图选择政权属于正式半球导航场景，必须继续与玩家所属国家区分。

## 2. 仍需人工决定

1. 正式产品是否继续组合 V2/V2.3 人物与社会服务；这决定 `selected_person_id` 与 `player_character`关系。
2. 历史 admin1、现代近似 admin1、历史名称目录是否建立显式 crosswalk，或保持三个视图状态。
3. 事件、消息、情报最终由哪个正式服务提供；半球 seed 当前只能视为展示数据。
4. PR #19 合并后旧 PrototypeV2 地图脚本删除、归档或保留为隔离样机。
5. 支持哪些旧存档 schema，以及每个迁移分支的删除条件。
""")
    (OUT / "state_ownership_matrix.md").write_text("".join(lines), encoding="utf-8")


if __name__ == "__main__":
    write_variable_audit()
    write_ownership_matrix()
    print({
        "variable_state_audit_bytes": (OUT / "variable_state_audit.md").stat().st_size,
        "state_ownership_matrix_bytes": (OUT / "state_ownership_matrix.md").stat().st_size,
        "member_rows": len(members),
    })
