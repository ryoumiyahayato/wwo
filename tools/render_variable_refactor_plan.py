#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs' / 'refactors' / 'variable_refactor_plan.md'
TEXT = r'''# 第一批变量重构计划：玩家所属国家所有权

状态：仅计划，未批准实施。基线：`agent/formal-world-economy-integration@950512aba6889ff8ffd6f24c4be7559b7ef1f1cd`。

## 当前问题

`GameSessionService.selected_country_id`是`player_character.country_id`的运行期可写副本。存档加载已经要求两者一致，因此该成员没有独立语义。半球地图同名字段表示地图选择，不属于本批。

## 目标唯一事实源

- 所有者：`GameSessionService.player_character`。
- 玩家所属国家：由`player_character.country_id`只读推导；无玩家时为空字符串。
- 写入入口：`set_player()`、`transfer_player()`、继承事务提交/回滚和存档恢复只修改或提交玩家对象。
- 存档边界：继续输出和验证旧`selected_country_id`键；内部不保留第二份成员状态。
- 不新增Autoload、Manager、Dictionary状态容器、同步信号、fallback或兼容别名。

## qualified引用范围

- 成员声明：`scripts/character/game_session_service.gd:11`。
- 类内实际写入：`scripts/character/game_session_service.gd:29`、`:47`、`:82`。
- 外部实际写入：`scripts/character/succession_service.gd:280`、`scripts/save/game_save_service.gd:509`。
- 合格读取：`scripts/save/game_save_service.gd:231`。
- 存档边界：`scripts/save/game_save_service.gd:231,455-460,603`。
- 同名地图成员：`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:23`，不得修改。
- 函数局部同名：`scripts/save/game_save_service.gd:455`，不计入成员删除。

`set_player()`、`clear()`和`transfer_player()`的函数声明分别位于`:27`、`:45`和`:80`；这些声明行不是写入行，不作为qualified写入位置。

## 实施前行为基线与测试

1. 提交一个当前`SAVE_VERSION = 1`存档fixture，并证明现有代码可以加载。
2. 断言保存键等于`player_character.country_id`。
3. 断言旧键与玩家国家不一致时加载失败且事务不提交。
4. 覆盖`transfer_player()`。
5. 覆盖继承成功。
6. 覆盖继承中途失败后的完整事务回滚。
7. 证明地图`selected_country_id`和玩家国家互不影响。
8. 证明`GameSessionService.clear()`后派生国家为空。

上述测试和fixture尚未创建。本轮只修订文档。

## 预计变更

- 删除可写成员：1。
- 新增可写成员：0。
- 保留存档键：1。
- 减少重复可写事实：1。
- 不新增Autoload、Manager、Dictionary状态容器、同步信号、fallback或兼容别名。

## 风险与停止条件

- fixture不能代表当前真实存档时停止。
- 无法证明继承回滚的原子性时停止。
- 任何地图选择行为变化时停止。
- 需要同时维护新旧运行期状态时停止。
- 需要修改玩法、UI或正式半球导航时停止。'''

def main() -> None:
    OUTPUT.write_text(TEXT + '\n', encoding='utf-8')
    print(f'wrote {OUTPUT}')

if __name__ == '__main__':
    main()
