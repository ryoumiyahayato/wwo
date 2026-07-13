# 存档格式

M8 实现版本 1 JSON 存档。权威实现位于 `scripts/save/game_save_service.gd`。

## 目标要求

- 路径仅使用 `user://`。
- 包含存档版本、配置版本、权威游戏时间、玩家人物 ID、国家、地区、控制单元、人物、组织、关系、当前行动、随机状态和开发模式标记。
- 所有实体使用稳定 ID；引用通过 ID 连接。
- 加载前验证顶层结构、类型、版本和必要引用。
- 新字段缺失时使用明确默认值；不支持的未来版本必须给出错误而不是崩溃。
- 保存先写临时文件，再用安全替换保护已有存档。

## 路径和槽位

- 手动档：`user://saves/manual.json`。
- 自动档：`user://saves/autosave.json`，只有一个槽位；每个权威游戏周边界更新一次，也可从开发面板立即写入。
- 任意非 `user://` 路径在写入前被拒绝。

## 版本 1 顶层字段

```text
save_version: 1
config_versions: {world, clock, character, action, society}
game_time: {year, month, day, hour, total_hours, is_paused, speed_multiplier,
            real_seconds_remainder, event_queue}
player_character_id
selected_country_id
world: {regions, control_units}
characters: {player_character_id, background, active, exited, activation_seeds}
organizations
relationships: {records, id_state}
ai_states
settlement_state: {paused_categories}
current_action
random_state: {action_id_service}
developer_mode
settlement_log
performance_metrics
```

`game_time.event_queue` 保存事件 ID、到期小时、插入序号、载荷和下一序号。地区只保存可变社会影响，控制单元只保存控制者、控制强度、争夺度和敌方压力；法理、邻接和铁路仍来自已验证的配置数据。前线在加载后从控制单元重建。

人物按背景、活跃和已退出三层分别保存，保持同一稳定人物 ID。背景人物可选字段 `persistent_core` 保存技能、隐藏资质、气质权重、真实/已知倾向和随机生成核心，使人物降级后再次升级不会回滚成长；旧版本 1 存档缺失该字段时按稳定激活种子补全。

当前行动保存全部进度、效率、上次结算小时、上下文、结果和幂等标记。正式玩家行动上下文新增 `funding_cost`、`funding_committed` 和 `wealth_before_funding`，用于证明费用与行动创建属于同一事务。旧版本 1 存档可缺失整组资金审计字段，并在下一权威小时更新上下文；只出现部分审计字段则视为损坏。已完成的领域行动必须在保存前完成 `domain_effect_applied` 权威写回，不允许把半完成领域结算留到加载后重放。

关系与行动的稳定 ID 计数器一并保存，使加载后的下一 ID 连续。

## 验证、默认值和错误

加载先解析 JSON，再验证根类型、精确存档版本、必要集合、玩家引用和记录形状；只有重建临时社会服务成功后才替换会话。未知版本、断裂引用和非法数值返回错误，不把异常暴露给 UI。

版本 1 的核心世界字段必须存在。新增的可选诊断字段采用明确默认值：缺少 `developer_mode` 时为 `false`；缺少 `settlement_state` 时无暂停类别；缺少 `settlement_log` 时建立 200 条上限的空日志；缺少 `performance_metrics` 时建立空统计。背景人物缺少 `persistent_core` 和旧行动缺少完整资金审计字段也使用上述兼容路径。

稳定错误码包括 `not_found`、`malformed_json`、`invalid_snapshot`、`broken_reference`、`unsafe_path`、`write_error`、`replace_error` 和 `restore_error`。

## 安全写入

先把完整 JSON 写到同目录 `.tmp` 并刷新；已有目标先改名为 `.bak`，再把临时文件改名为正式文件。替换失败时尝试恢复备份，验证失败则完全不触碰已有文件。成功后删除备份。该流程已在当前 Windows 11 环境验证；其他平台语义留待对应真机测试。
