# V2.3 正式依赖清查

本报告由确定性静态审计工具生成。本 PR 只增加审计工具、测试、机器清单、报告和只读 CI；未迁移、重命名、删除或重构任何生产服务。

## 基线与扫描

- 固定 Base SHA：`db5556125a78a296045cb29c7cba18ff2438af96`
- 默认启动场景：`scenes/formal/formal_world_menu.tscn`
- 扫描文件数：764
- 完整机器清单：`docs/refactors/formal_v23_dependency_inventory.json.gz`（确定性 gzip 压缩 JSON）
- D01 稳定契约 blob：`871d312cd0d8fa4370aa201ad7ac5a863684ab4d`
- D01 稳定契约保持不变：`true`
- 扫描覆盖 `project.godot`、导出配置、脚本、场景、资源、数据、测试、工具和 workflow；文档引用不作为生产依赖证据。

## 数量

|指标|数量|
|---|---:|
|V2.3 相关生产文件|57|
|V2.3 相关测试文件|32|
|A 正式直接依赖|0|
|B 正式间接依赖|0|
|C Alpha/fixture 隔离|46|
|D 非正式样机|0|
|E 兼容边界|2|
|F 测试专用|38|
|G 无有效调用|4|
|U 无法确定|0|
|正式场景直接路径|0|
|正式运行时传递路径|0|
|正式保存依赖|0|
|正式长期模拟依赖|0|
|仍绑定弃用 V2.3 产品语义的 workflow 门禁|1|

## 正式产品根节点

- `project.godot`
- `scenes/formal/formal_world_main.tscn`
- `scenes/formal/formal_world_menu.tscn`
- `scripts/formal/formal_world_application.gd`
- `scripts/formal/formal_world_economy_service.gd`
- `scripts/formal/formal_world_menu.gd`
- `scripts/formal/formal_world_simulation.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd`

结论：静态依赖图中没有任何 V2.3 候选从正式产品根节点直接或间接可达；正式启动、tick、经济、保存、HUD/地图和十年长期模拟中的 V2.3 依赖数量均为 0。

## A：正式产品直接依赖

无。

## B：正式产品间接依赖

无。

## C：Alpha 或 fixture 隔离依赖

- `data/scenarios/v2_3_lille_space_cognition.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/communication_channels.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/cross_border_locations.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/cross_border_travel_graph.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/knowledge_rules.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/lille_finance.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/lille_locations.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/lille_travel_graph.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/minute_clock.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/relationship_rules.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/social_people.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/social_sandbox_rules.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/transport_modes.json` — 保留并明确隔离；置信度：high。
- `data/v2_3/v2_3_balance.json` — 保留并明确隔离；置信度：high。
- `scripts/alpha/alpha_v23_config.gd`（AlphaV23Config） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/communication_service.gd`（CommunicationService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/knowledge_service.gd`（KnowledgeService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/relationship_service.gd`（V23RelationshipService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/route_planner_service.gd`（RoutePlannerService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/social_appointment_service.gd`（SocialAppointmentService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/social_introduction_service.gd`（SocialIntroductionService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/spatial_location_service.gd`（SpatialLocationService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/spatial_npc_routine_service.gd`（SpatialNpcRoutineService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/travel_execution_service.gd`（TravelExecutionService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/travel_graph_service.gd`（TravelGraphService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_config.gd`（V23Config） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_controlled_simulation.gd`（V23ControlledSimulation） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_controlled_ui_binding.gd`（V23ControlledUiBinding） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_controlled_ui_binding_v2.gd`（V23ControlledUiBindingV2） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_finance_config.gd`（V23FinanceConfig） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_finance_service.gd`（V23FinanceService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_formal_simulation.gd`（V23FormalSimulation） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_formal_ui_binding.gd`（V23FormalUiBinding） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_leave_service.gd`（V23LeaveService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_life_loop_simulation.gd`（V23LifeLoopSimulation） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_life_loop_ui_binding.gd`（V23LifeLoopUiBinding） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_minute_clock.gd`（V23MinuteClock） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_minute_controlled_simulation.gd`（V23MinuteControlledSimulation） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_player_ui_binding.gd`（V23PlayerUiBinding） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_product_simulation.gd`（V23ProductSimulation） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_product_simulation_v2.gd`（V23ProductSimulationV2） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_social_sandbox_service.gd`（V23SocialSandboxService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_social_sandbox_service_v2.gd`（V23SocialSandboxServiceV2） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_social_sandbox_service_v3.gd`（V23SocialSandboxServiceV3） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_survival_autonomy_service.gd`（V23SurvivalAutonomyService） — 保留并明确隔离；置信度：high。
- `scripts/v2_3/v2_3_survival_autonomy_service_v2.gd`（V23SurvivalAutonomyServiceV2） — 保留并明确隔离；置信度：high。

## D：非正式样机依赖

无。

## E：兼容边界

- `scripts/v2_3/v2_3_save_migration.gd`（V23SaveMigration） — 保留边界，不作为运行期事实源；置信度：high。
- `scripts/v2_3/v2_3_save_service.gd`（V23SaveService） — 保留边界，不作为运行期事实源；置信度：high。

## F：测试专用

- `scripts/v2_3/v2_3_formal_interface.gd`（V23FormalInterface） — 随被测服务迁移或删除；置信度：high。
- `scripts/v2_3/v2_3_formal_schedule_interface.gd`（V23FormalScheduleInterface） — 随被测服务迁移或删除；置信度：high。
- `scripts/v2_3/v2_3_life_loop_interface.gd`（V23LifeLoopInterface） — 随被测服务迁移或删除；置信度：high。
- `scripts/v2_3/v2_3_minute_formal_interface.gd`（V23MinuteFormalInterface） — 随被测服务迁移或删除；置信度：high。
- `scripts/v2_3/v2_3_minute_formal_interface_v2.gd`（V23MinuteFormalInterfaceV2） — 随被测服务迁移或删除；置信度：high。
- `tests/alpha/alpha_save_and_migration_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/alpha/alpha_world_topology_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_appointment_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_city_detail_performance_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_communication_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_controlled_world_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_determinism_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_entry_hud_capture.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_entry_hud_probe.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_formal_finance_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_formal_leave_location_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_full_loop_smoke.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_knowledge_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_location_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_map_integration_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_npc_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_performance_guard_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_player_interface_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_relationship_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_review_artifact_generator.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_route_planner_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_save_load_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_save_migration_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_schedule_integration_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_social_sandbox_completion_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_social_sandbox_debug.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_social_sandbox_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_social_sandbox_test_base.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_survival_autonomy_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_test_case.gd`（V23TestCase） — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_travel_execution_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tests/v2_3/v2_3_ui_binding_test.gd` — 随被测服务迁移或删除；置信度：high。
- `tools/v2_3/generate_social_review_saves.gd` — 随被测服务迁移或删除；置信度：high。

## G：无有效调用

- `scenes/v2_3/v2_3_entry_hud_capture.tscn` — 候选删除；置信度：high。
  - 无调用证据：没有生产、场景、测试、工具、workflow、存档或动态加载证据。
- `scenes/v2_3/v2_3_entry_hud_probe.tscn` — 候选删除；置信度：high。
  - 无调用证据：没有生产、场景、测试、工具、workflow、存档或动态加载证据。
- `scripts/v2_3/v2_3_minimal_hud_overlay.gd`（V23MinimalHudOverlay） — 候选删除；置信度：high。
  - 无调用证据：仅由同一无入口候选簇调用，整个闭包没有外部根或动态加载证据。
- `scripts/v2_3/v2_3_minimal_hud_overlay_polish.gd` — 候选删除；置信度：high。
  - 无调用证据：没有生产、场景、测试、工具、workflow、存档或动态加载证据。

## U：无法确定

无。

## 专项核对

### 旧独立 150 秒性能测试

- `tests/alpha/alpha_three_year_performance_test.gd:45`
- `tests/alpha/alpha_three_year_performance_test.gd:46`
- 建议：旧 `alpha_three_year_performance_test.gd` 不应继续作为独立产品门禁；保留同跑者 Base/Head 五轮门禁作为权威性能验收，并在下一清理 PR 删除或改名该旧测试。

### Loran

- 涉及文件：37
- 正式可达生产文件：`data/alpha/commodity_market_1900.json`
- Alpha/fixture 文件：21
- 非正式样机文件：0

### Vesta

- 涉及文件：36
- 正式可达生产文件：`data/alpha/commodity_market_1900.json`
- Alpha/fixture 文件：21
- 非正式样机文件：0

### PrototypeMap

- 涉及文件：7
- 正式可达生产文件：无
- Alpha/fixture 文件：0
- 非正式样机文件：0

### 弃用入口、发布和时间链

- `scenes/v2_3/v2_3_life_loop_main.tscn`：存在=false，正式可达=false，workflow 引用=false，导出引用=false。
- `scenes/v2_3/v2_3_life_loop_menu.tscn`：存在=false，正式可达=false，workflow 引用=false，导出引用=false。
- `scripts/v2_3/v2_3_life_loop_main.gd`：存在=false，正式可达=false，workflow 引用=false，导出引用=false。
- `scripts/v2_3/v2_3_life_loop_menu.gd`：存在=false，正式可达=false，workflow 引用=false，导出引用=false。
- `scripts/v2_3/v2_3_formal_main.gd`：存在=false，正式可达=false，workflow 引用=false，导出引用=false。
- `scripts/v2_3/v2_3_player_interface.gd`：存在=false，正式可达=false，workflow 引用=false，导出引用=false。
- Windows 导出弃用入口引用：0
- 弃用 V2.3 产品语义 workflow 证据：`.github/workflows/social-sandbox-diagnostics.yml:62`
- D01 后正式可达 V2.3 时间字段残余：0

## 静态分析限制

- 字符串拼接形成的资源路径只有在同一行保留候选路径或类名时才能归因。
- ClassDB、反射、call/callv、运行时工厂和生成文件只作为动态证据；未闭合时分类为 U，不会归入 G。
- 文档、审计器自身和 .uid sidecar 不作为候选或生产依赖证据。
- 静态可达性不证明运行时条件分支一定执行；A/B 仍需行为基线保护后迁移。

## 后续建议

- C 类继续作为 Alpha/fixture 隔离服务；若其中通用人物、关系、行程、社会和生活需求服务需要进入正式产品，下一 PR 先建立行为基线，再迁移到中性正式目录。
- E 类继续作为旧存档兼容边界，不得成为运行期事实源。
- F 类随对应服务迁移或删除，不得因测试存在而认定为正式依赖。
- G 类在下一 PR 再次确认无动态证据后删除。
- 当前 U 类为 0；未来若出现动态字符串或反射证据，必须归 U 而不是 G。
- 下一项唯一任务：`V2.3 通用服务迁移与无调用内容清理`。
