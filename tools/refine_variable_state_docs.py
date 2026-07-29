#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs" / "refactors"
AUDIT_PATH = DOCS / "variable_state_audit.md"
PLAN_PATH = DOCS / "variable_refactor_plan.md"

OLD_D01 = "| P0 | D01 正式时间三重表示 | 半球继承层写 `sim_year/month/day/hour/minute`；`FormalWorldSimulation` 写 `total_minutes/_minute_remainder`；经济服务写 `total_hour`。一次计时器回调推进两套时间，存档也保存可互推字段。 | `holographic_workspace_runtime.gd`; `formal_world_application.gd`; `formal_world_simulation.gd`; `formal_world_economy_service.gd` | 单独批次统一到正式时钟；UI 只读快照，经济接收小时推进。先建旧存档 fixture。 |"
NEW_D01 = "| P0 | D01 正式时间三重表示及已确认初始错位 | 半球 UI 初始为 `1900-03-12 08:00`；`FormalWorldSimulation` 与 `FormalWorldEconomyService` 从 `1900-01-01 00:00` 开始。`FormalWorldApplication` 每次计时分别推进半球时钟与正式模拟时钟；新游戏建立时已经不一致，读取正式存档后也没有把半球 UI 时间恢复为存档时间。 | `holographic_workspace_runtime.gd:48-54`; `formal_world_application.gd:17-41,62-69`; `formal_world_simulation.gd:13-17,20-44,59-70,74-89`; `formal_world_economy_service.gd:21-38,40-55`; `v2_datetime.gd:3-18` | 已确认的现存正确性缺陷，P0。当前审计批不得顺带修复；必须单独建立新游戏、计时、保存和恢复行为基线后处理。 |"

OLD_D02 = "| P0 | D02 经济体—政治单元映射五份可写表示 | 交叉表、`country_states[*].polity_ids`、`economy_polity_ids`、`economy_by_polity_id`、`polity_records[*].economy_entity_id`表达同一关系，恢复时还会补写。 | `formal_world_economy_service.gd` | 规定一个加载后的只读源和必要索引；国家状态、政权记录不得再保存关系副本。 |"
NEW_D02 = "| P0 | D02 经济体—政治单元关系的来源、索引与持久化混合 | 权威原始来源是 `major_economy_polity_crosswalk_1900.json`，一对一关系另由政治单元 ID 直接解析；`economy_polity_ids`是经济体→政治单元正向只读索引；`economy_by_polity_id`是政治单元→经济体反向只读索引；`country_states[*].polity_ids`是随存档保存并在恢复时补写的重复字段；`polity_records[*].economy_entity_id`是供政治单元摘要和 UI 展示使用的投影。索引本身可能是必要的，不能预设全部删除。 | `major_economy_polity_crosswalk_1900.json`; `formal_world_economy_service.gd:21-38,159-195,202-246`; `formal_world_economy_service.gd:46-64,115-163` | 先确定原始来源在加载后是否保持不可变，并分别评估正向/反向索引的查询成本与失效条件；优先审计持久化重复字段和 UI 投影，不以“字段数量”作为删除索引的理由。 |"

CORRECTNESS_MARKER_START = "<!-- BEGIN CONFIRMED CORRECTNESS DEFECTS -->"
CORRECTNESS_MARKER_END = "<!-- END CONFIRMED CORRECTNESS DEFECTS -->"
CORRECTNESS_SECTION = f"""{CORRECTNESS_MARKER_START}
## 2.1 已确认的现存正确性缺陷：正式时间初始错位（P0）

该问题是审计发现的现存行为缺陷，不是本审计批引入，也不得在本批顺带修复。

1. 半球 UI 继承层把初始时间保存为 `sim_year = 1900`、`sim_month = 3`、`sim_day = 12`、`sim_hour = 8`、`sim_minute = 0`，即 **1900-03-12 08:00**（`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:48-54`）。
2. `FormalWorldSimulation.total_minutes`与`_minute_remainder`初始化为 0；`FormalWorldEconomyService.total_hour`也初始化并在 `configure()` 中重置为 0（`scripts/formal/formal_world_simulation.gd:13-23`；`scripts/formal/formal_world_economy_service.gd:21-28,40-55`）。`V2DateTime`明确把累计小时 0 定义为 **1900-01-01 00:00**（`scripts/v2_2/v2_datetime.gd:3-18`）。
3. `FormalWorldApplication._on_clock_timer_timeout()`先调用继承层 `_advance_clock(minutes)`，随后调用 `formal_simulation.advance_minutes(minutes)`，因此每次计时分别推进两套已经错位的时间（`scripts/formal/formal_world_application.gd:34-41`）。
4. 新游戏初始化只调用 `formal_simulation.initialize()`并读取世界摘要，没有将半球 `sim_*`字段设置为正式模拟时间。因此场景第一次进入时，两套时间已经相差 70 天 8 小时。
5. 读取正式存档时只调用 `formal_simulation.load_from_user()`并刷新 `_last_summary`；没有从 `formal_simulation.date_time()`恢复半球 `sim_year/month/day/hour/minute`（`scripts/formal/formal_world_application.gd:23-30,62-69`）。

风险：HUD日期、经济结算日期、保存后的正式累计时间和玩家看到的时间可以长期表示不同日期。修复必须作为独立“正式时间所有权”批次执行，并先建立新游戏、连续计时、保存及读取行为特征测试。
{CORRECTNESS_MARKER_END}
"""

FIRST_BATCH_SECTION = """## 4. 推荐第一批范围（尚未实施）

### 4.1 子系统与唯一事实源

第一批仅处理 `GameSessionService` 的“玩家所属国家”运行期副本。候选唯一事实源是 `GameSessionService.player_character.country_id`。半球地图的 `selected_country_id`属于用户地图选择，语义不同，第一批不得修改。

旧存档键 `selected_country_id`暂时保留：保存边界从玩家对象推导，加载边界继续验证旧键与恢复后玩家国家一致。运行期间不应继续保存第二份可写国家 ID。

### 4.2 qualified 引用清单

以下清单来自按所有者、限定名和词法作用域逐项核验，不使用纯名称扫描结论。

#### `GameSessionService.selected_country_id`成员声明

- `scripts/character/game_session_service.gd:9`：`static var selected_country_id: String = ""`。

#### 合格读取点

- `scripts/save/game_save_service.gd:229`：`build_snapshot()`把 `GameSessionService.selected_country_id`写入旧存档键。全仓库未发现其他合格运行期读取点。

#### 合格写入点

- `scripts/character/game_session_service.gd:27`：`set_player()`按 `character.country_id`赋值。
- `scripts/character/game_session_service.gd:45`：`clear()`写空字符串。
- `scripts/character/game_session_service.gd:80`：`transfer_player()`按 `character.country_id`赋值。
- `scripts/character/succession_service.gd:280`：继承事务回滚后按 `restored_player.country_id`恢复。
- `scripts/save/game_save_service.gd:509`：存档恢复通过一致性验证后，把函数局部 `selected_country_id`写回会话成员。

成员声明的空字符串初始化单独视为初始化值，不重复计入上述五个运行期写入点。

#### 存档键及其边界引用

- `scripts/save/game_save_service.gd:229`：生成 `"selected_country_id"`键。
- `scripts/save/game_save_service.gd:455-460`：读取旧键，验证国家存在并要求其等于 `restored_player.country_id`。
- `scripts/save/game_save_service.gd:603`：验证快照必须包含非空旧键。

#### 同名但属于其他对象的成员字段

- `scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:23`：半球场景成员 `selected_country_id`，表示用户选中的地图政治单元。其写入发生在半球选择/返回流程，测试中的 `view.selected_country_id`也限定到该场景对象。它不是玩家所属国家副本，本批必须保持不变。

全仓库成员声明核验只发现上述两个 `selected_country_id`成员。

#### 函数局部同名变量

- `scripts/save/game_save_service.gd:455`：`restore_snapshot()`局部变量 `selected_country_id`，保存从快照读取、尚未提交的候选值。它不是成员字段；本批可以保留或在实现时改为更精确的局部名称，但不计入成员变量删除数量。

全仓库词法核验未发现其他 `var selected_country_id`函数局部声明。

### 4.3 实施前必须创建的测试

1. **现有版本存档 fixture**：使用当前 `SAVE_VERSION = 1`结构，包含有效玩家、国家、地图、人物和行动状态；重构前必须可以实际加载。
2. **保存键推导测试**：保存后 `snapshot["selected_country_id"] == GameSessionService.player_character.country_id`。
3. **旧键不一致拒绝测试**：修改 fixture 的旧键，使其与恢复玩家的 `country_id`不同；加载必须返回失败且不得提交任何部分恢复状态。
4. **玩家转移测试**：`transfer_player()`后派生玩家国家立即等于新玩家的 `country_id`，不依赖第二次同步调用。
5. **人物继承成功测试**：继承成功后玩家对象、roster玩家ID和派生国家一致。
6. **人物继承事务回滚测试**：在可控制的中途失败点触发回滚，玩家对象、roster、组织、关系、AI和派生国家恢复到事务前状态。
7. **地图选择隔离测试**：改变半球场景 `selected_country_id`不得改变玩家所属国家；转移玩家也不得改变当前地图选择。
8. **清理测试**：`GameSessionService.clear()`后 `player_character == null`，派生玩家国家为空字符串。

测试只在下一次批准后创建。本次修订只记录测试计划。

### 4.4 第一批预计数量

| 项目 | 预计数量 |
|---|---:|
| 删除可写成员 | 1 |
| 保留 `GameSessionService`其他 `static var` | 14（本批不处理） |
| 新增可写成员 | 0 |
| 减少重复可写事实 | 1 |
| 删除兼容存档键 | 0 |
| 删除 fallback | 0 |
| 删除同步函数 | 0 |
| 预计生产文件 | 3-5 |
| 计划新增测试场景/脚本 | 1-3，按现有测试组织方式确定 |

### 4.5 停止条件

在现有版本存档 fixture、上述测试基线和完整 qualified 搜索没有完成前，不得删除成员。若继承回滚无法在不新增兼容层或双写状态的情况下验证，第一批必须停止并报告阻塞。

"""

PLAN_TEXT = """# 第一批变量重构计划：玩家所属国家所有权

状态：仅计划，未批准实施。基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。

## 当前问题

`GameSessionService.selected_country_id`是 `player_character.country_id`的运行期可写副本。存档加载已经要求两者一致，因此该成员没有独立语义。半球地图同名字段表示地图选择，不属于本批。

## 目标唯一事实源

- 所有者：`GameSessionService.player_character`。
- 玩家所属国家：由 `player_character.country_id`只读推导；无玩家时为空字符串。
- 写入入口：`set_player()`、`transfer_player()`、继承事务提交/回滚和存档恢复只修改玩家对象或提交恢复后的玩家对象。
- 存档边界：继续输出和验证旧 `selected_country_id`键；内部不保留第二份成员状态。

## qualified 引用范围

- 成员：`scripts/character/game_session_service.gd:9`。
- 类内写入：`:27`、`:45`、`:80`。
- 外部写入：`scripts/character/succession_service.gd:280`、`scripts/save/game_save_service.gd:509`。
- 合格读取：`scripts/save/game_save_service.gd:229`。
- 存档边界：`scripts/save/game_save_service.gd:229,455-460,603`。
- 同名地图成员：`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:23`，不得修改。
- 函数局部同名：`scripts/save/game_save_service.gd:455`，不计入成员删除。

## 实施前行为基线与测试

1. 提交一个当前 `SAVE_VERSION = 1`存档 fixture，并证明现有代码可以加载。
2. 断言保存键等于 `player_character.country_id`。
3. 断言旧键与玩家国家不一致时加载失败且事务不提交。
4. 覆盖 `transfer_player()`。
5. 覆盖继承成功。
6. 覆盖继承中途失败后的完整事务回滚。
7. 证明地图 `selected_country_id`和玩家国家互不影响。
8. 证明 `GameSessionService.clear()`后派生国家为空。

## 预计变更

- 删除可写成员：1。
- 新增可写成员：0。
- 保留存档键：1。
- 减少重复可写事实：1。
- 不新增 Autoload、Manager、Dictionary状态容器、同步信号、fallback或兼容别名。

## 风险与停止条件

- fixture不能代表当前真实存档时停止。
- 无法证明继承回滚的原子性时停止。
- 任何地图选择行为变化时停止。
- 需要同时维护新旧运行期状态时停止。
- 需要修改玩法、UI或正式半球导航时停止。
"""


def replace_section(text: str, start_heading: str, end_heading: str, replacement: str) -> str:
    start = text.index(start_heading)
    end = text.index(end_heading, start)
    return text[:start] + replacement.rstrip() + "\n\n" + text[end:]


def main() -> None:
    text = AUDIT_PATH.read_text(encoding="utf-8")
    if OLD_D01 in text:
        text = text.replace(OLD_D01, NEW_D01, 1)
    elif NEW_D01 not in text:
        raise RuntimeError("D01 audit row was not found")
    if OLD_D02 in text:
        text = text.replace(OLD_D02, NEW_D02, 1)
    elif NEW_D02 not in text:
        raise RuntimeError("D02 audit row was not found")

    if CORRECTNESS_MARKER_START in text:
        start = text.index(CORRECTNESS_MARKER_START)
        end = text.index(CORRECTNESS_MARKER_END, start) + len(CORRECTNESS_MARKER_END)
        text = text[:start] + CORRECTNESS_SECTION.rstrip() + text[end:]
    else:
        insertion = text.index("## 3. 多写入者、UI/缓存副本与停止项")
        text = text[:insertion] + CORRECTNESS_SECTION + "\n" + text[insertion:]

    text = replace_section(
        text,
        "## 4. 推荐第一批范围（尚未实施）",
        "## 5. 分类",
        FIRST_BATCH_SECTION,
    )
    AUDIT_PATH.write_text(text, encoding="utf-8")
    PLAN_PATH.write_text(PLAN_TEXT, encoding="utf-8")
    print("refined variable_state_audit.md and generated variable_refactor_plan.md")


if __name__ == "__main__":
    main()
