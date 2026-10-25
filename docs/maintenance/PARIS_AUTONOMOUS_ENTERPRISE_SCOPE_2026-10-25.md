# 下一项独立PR：巴黎两家企业的自主经营约束

任务：**现有两家巴黎企业在玩家不操作时的合法原料采购、真实劳动与持续经营约束**。

基线为main中的R57代21源码。本文件只界定后续PR，不实施功能，不移植经济研究线策略，不新增第三家企业或NPC，不调整工资、售价、生产配方或经济算法以制造盈利。

## 已有源码与事实

- `data/formal/paris_employment_opening_r1.json`：现有工坊与面包坊是 `firm:opening_paris_workshop`、`firm:opening_paris_bakery`；玩家0001保持player控制，现有NPC0002自动控制。两家独立资金、货批、岗位及实际销售劳动窗口。工坊初始粮60、面包坊粮24；供货与采购条款分别为SELL/PROCURE，粮价1、累计限8，工坊保底4且保护生产需要。它们是生成的Opening配置，不是历史企业资料。
- `scripts/world/economy_r1_slice.gd`：日边界先采用真实工作、支付工资、分配销售与生产劳动，再生产、采购、交付、消费，最后决策下一轮工作。`_procure_inputs()` 已根据真实缺口和已知供应报价提交原企业命令，不缺另建采购引擎；`_material_trade_reason()`、`_material_remaining()`、`_material_sale_available()` 保留双方授权、存量、承诺、保底和累计额度。`_auto_work()` 仅处理automatic人物，沿用岗位、地点、资格、欠薪与活动约束，不接管玩家。
- `scripts/world/economy_retail_rules.gd` 的 `prepare_labor()` 从已有work记录分配销售工时，并从生产工时扣除；`reason()` 在没有当日实际工时的时候返回 `STORE_NO_ACTUAL_STAFFING`。不能把有库存、有报价、有组织授权当作已有人履约。
- `scripts/world/economy_labor_market.gd`、`scripts/world/formal_personal_economy_state.gd`、`scripts/simulation/simulation_step.gd` 与 `scripts/persistence/formal_persistence.gd` 已承担岗位决策、真实个人财产、权威时间和v15恢复。后续继续沿用这些边界，不另建经济状态或存档服务。
- 代21报告 `docs/map/R57_ORDINARY_MATERIAL_TRADE_2026-10-24.md` 记录：第42日无人履约拒绝；玩家登记2h后第43日交付1粮，第44日采用。销售回款小于工资，补货没有证明盈利；剩余授权7。历史记录不是本轮新实机验收。

## 最小修改边界

1. 先在既有个人经济测试中增加“玩家无apply/work/buy命令”的新Opening场景，跨越缺料日。观察现有NPC、岗位和站点工时实际落在哪家企业，以及企业采购被哪个原领域条件拒绝。既有正例每天主动登记玩家2h，不能代表无人操作正例。
2. 只针对上述场景证实的缺口，在原自动人物劳动选择、岗位知识/通知或Opening授权配置处做最小修改。采购本身已有自动入口；不能重复采购、绕过授权或凭空补库存。一个NPC的真实时间和已存在的合同/活动限制必须允许所选安排；若两家工时无法同时覆盖，应出现合法缺货、停工或切换，不能把同一小时分配两次，也不假定可以自动双重就业。
3. 区分“存在有限合法交易”与“持续经营”：采购额度8会耗尽，粮食和现金有限，工坊也消耗原料。首个PR明确展示额度耗尽、无剩余库存、无人到岗、欠薪或现金不足时的原拒绝/停工结果。扩大授权或增加外部供货属于另行决策，本PR不默认添加。
4. 只在确需保留新事实时扩展原组件快照和恢复验证；旧第30日存档不得被加载时补入新授权。保留来源货批、真实账款、工作记录、零时间恢复与重复请求幂等性。

预期文件范围是上述Opening、`economy_r1_slice.gd`、必要时原劳动/零售实现，以及 `tests/formal/formal_personal_economy_test.gd`。先由失败场景决定实际改动文件，不能预先扩大为全经济重构。UI、地貌、军事、研究策略和导出不在范围内。

## 已有测试入口与后续验收

使用Godot 4.6.3，先导入源码，再运行：

```sh
godot --headless --path . --script res://tests/formal/formal_personal_economy_test.gd
godot --headless --path . --script res://tests/formal/formal_personal_economy_test.gd -- --native-multi-employer
godot --headless --path . --script res://tests/formal/formal_personal_economy_test.gd -- --native-material-trade
```

最后一项读取 `APPDATA/WWO_R57_Visual_Living_UI_20261023/formal_world_1900_manual_3.json`；应将仓库归档 `docs/archive/main-wwo-r57-g21-20261024/checkpoints/30day-main.json` 复制到隔离测试APPDATA的这个路径，不能写真实玩家五槽或使用伪造存档。当前Main validation已这样安排。

后续新增场景必须覆盖无人操作、无授权/未知供应/无劳动/保底不足/现金不足/额度耗尽、拒绝不改变钱货与组织、守恒、存档恢复和零时间不重复结算。测试应允许资源约束下真实失败，不能以始终盈利或永续供货为断言。自动检查后仍须实际游戏验收；R57不因此promote。
