# V2.3 测试计划

## 自动化矩阵

统一验证先执行 Headless 编辑器导入并扫描解析/类型/脚本加载错误，然后保留全部 V2.2 回归，
再运行以下 V2.3 专项：

1. `v2_3_location_test.gd`
2. `v2_3_route_planner_test.gd`
3. `v2_3_travel_execution_test.gd`
4. `v2_3_schedule_integration_test.gd`
5. `v2_3_communication_test.gd`
6. `v2_3_knowledge_test.gd`
7. `v2_3_relationship_test.gd`
8. `v2_3_appointment_test.gd`
9. `v2_3_npc_test.gd`
10. `v2_3_save_migration_test.gd`
11. `v2_3_save_load_test.gd`
12. `v2_3_determinism_test.gd`
13. `v2_3_ui_binding_test.gd`
14. `v2_3_map_integration_test.gd`
15. `v2_3_performance_guard_test.gd`
16. `v2_3_full_loop_smoke.gd`

重点覆盖：12 地点和连通图、最快/最省与现金回退、逐段旅行/扣费幂等、地点条件和迟到、
消息延迟/未读/回复、知识来源/可信度/时效、六维关系、介绍、到场与爽约、NPC 非瞬移、
V2.2 迁移、V2.3 原子保存与备份、30 日保存边界确定性、UI 认知过滤、地图 Dirty Flag 和
一年有界性能。

## 必跑专项命令

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script 'res://tests/v2_3/v2_3_full_loop_smoke.gd'
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script 'res://tests/v2_3/v2_3_save_migration_test.gd'
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script 'res://tests/v2_3/v2_3_determinism_test.gd'
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script 'res://tests/v2_3/v2_3_performance_guard_test.gd'
powershell -NoProfile -ExecutionPolicy Bypass -File D:\wwo\tools\run_validation.ps1
```

最终报告记录每条命令的真实退出码、检查/失败数、耗时和未运行项目。涉及权威行动、成长、
NPC 时间边界和存档不变量时另跑 `tests/codex_audit_regression.gd`。

## 真实窗口复验

使用指定 Godot 4.6.3 Compatibility 正常启动主场景，在 1280×720 下检查默认人物、Lille
节点、不同人物认知、正常/现金不足通勤、购买、面对面、约见/爽约、信件、介绍、知识过期、
阿尔贝通勤、迁移、途中保存加载、8 倍 30 日运行和 96 倍地图拖动。

评审证据写入 `artifacts/v2_3_space_cognition_review/`，不得提交。证据必须区分自动状态快照、
真实窗口截图和仍需用户独立判断的体验项。

## 性能预算

- 30 日离线模拟小于 10 秒。
- 一年离线模拟小于 30 秒。
- 单小时结算峰值小于 500 毫秒。
- 活动、消息、旅行、知识、关系、约见和幂等历史保持配置上限。
- 消息/知识变化不重建地图几何；高倍率本地点查询候选有界。

真实窗口记录 96 倍暂停、1 倍/8 倍旅行、面板打开、路线预览、30 日后拖动和快速缩放。没有
外部帧分析器时只报告采样与视觉复验，不把主观流畅声称为精确 FPS。
