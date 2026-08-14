#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "refactors" / "variable_refactor_plan.md"
TEXT = r'''# 第一批变量重构实施记录：玩家所属国家所有权

第一批实现基于基础提交`b4a9d637e294aa53b0c0e2525260421dce3b5182`，由PR #30实施。

## 已完成的所有权决定

- 唯一玩家对象：`GameSessionService.player_character`。
- 玩家所属国家：有玩家时只由`player_character.country_id`取得；无玩家时为空字符串。
- 已删除会话服务中重复的`selected_country_id`运行期成员。
- 半球地图自己的同名字段仍表示地图选择，未修改。
- 未新增替代成员、getter缓存、兼容别名、Dictionary字段、Autoload、Manager、同步信号、fallback或双写逻辑。

## 生产代码变更

### `scripts/character/game_session_service.gd`

- 删除一个`static var`成员。
- `set_player()`、`clear()`和`transfer_player()`不再维护国家副本。
- 其余清理和提交顺序保持不变。

### `scripts/character/succession_service.gd`

- 继承事务回滚仍依次恢复名册、组织、关系和AI状态。
- 恢复玩家后只提交`GameSessionService.player_character = restored_player`。
- 未改变其他回滚内容或顺序。

### `scripts/save/game_save_service.gd`

- `SAVE_VERSION`保持1，存档schema不变。
- 旧JSON键`"selected_country_id"`继续保留。
- `build_snapshot()`直接从`GameSessionService.player_character.country_id`生成旧键。
- `restore_snapshot()`继续验证旧键所指国家存在，且等于`restored_player.country_id`。
- 函数局部候选值机械改名为`saved_player_country_id`。
- 验证通过后只提交恢复后的玩家对象，不写入第二个运行期国家字段。

## 行为基线保持

以下PR #29产物保持字节级不变：

- `tests/fixtures/save/current_save_v1.json`
- `tests/variable_state/generate_current_save_v1_fixture.gd`
- `tests/variable_state/variable_state_behavior_baseline_test.gd`

行为基线继续覆盖：

1. 当前SAVE_VERSION=1服务级fixture生成、加载和恢复。
2. 保存旧键等于玩家人物国家。
3. 旧键不一致时`restore_snapshot()`拒绝恢复，且事务前后完整状态一致。
4. `transfer_player()`。
5. 人物继承成功。
6. 人物继承事务回滚。
7. 半球地图选择与玩家国家双向隔离。
8. `clear()`后玩家为空且派生国家为空。

## 审计净变化

现有扫描器生成的删除前后指标：

| 指标 | 删除前 | 删除后 | 净变化 |
|---|---:|---:|---:|
| 生产成员字段 | 1,613 | 1,612 | -1 |
| 可写成员字段 | 1,243 | 1,242 | -1 |
| 进程级全局可写字段 | 16 | 15 | -1 |
| 持久化关联候选（静态启发式） | 472 | 510 | 不可直接比较 |
| 可推导成员候选 | 61 | 60 | -1 |
| 新增可写成员 | 0 | 0 | 0 |

扫描器扫描`.gd`、`.tscn`、`.tres`、`.godot`、`.json`和`.cfg`；PR #29新增的测试GDScript和SAVE_VERSION=1 JSON fixture扩大了词法证据范围。`persisted_by_name`是在全部扫描源中，按同名字段与save、load、restore、snapshot等词推断的启发式，因此批准基线472和当前值510不能作为生产持久化字段的净变化比较；本记录不声称已经精确证明每一项增量的来源。

qualified所有权结论同时减少一份重复可写事实。其他状态组没有重新设计或修改。

## 验收与停止边界

- 全仓库不得再出现已删除会话成员的qualified引用。
- `selected_country_id`只继续用于SAVE_VERSION=1旧JSON键和半球地图场景选择字段。
- 不修改正式时间、导航、经济映射、玩法、UI或其他变量。
- 不修改PR #29的fixture、生成器和行为测试。
- 完整验证、fixture比较、行为基线和审计CI全部通过后停止。
- 本实施记录仅覆盖PR #30实施的第一批删除，不授权开始下一变量组。'''


def main() -> None:
    OUTPUT.write_bytes((TEXT + "\n").encode("utf-8"))
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
