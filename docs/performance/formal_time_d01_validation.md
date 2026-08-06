# D01 正式时间性能门禁记录

本文件仅使 D01 正式时间实施进入仓库既有的 Alpha 三年性能门禁；不修改门禁工作流、性能目标、Alpha 规则或正式世界平衡规则。

- 固定 Base SHA：`54abacf268e90d86e6fff3a2dc29f3162fd29089`
- 权威时间：`FormalWorldSimulation.total_minutes`
- 经济结算入口：`FormalWorldEconomyService.settle_hour_range(previous_total_hour, current_total_hour)`
- 正式场景、HUD、历史半球、经济、保存、读取和继续游戏均读取同一正式模拟时间。
- 存档 schema 保持 `formal_world_simulation_v2`。
- 稳定契约文件保持字节不变。
- `.uid` 文件不在 D01 差异中。

最终 Head、CI run 编号和门禁结果记录在 PR #33 描述中。
