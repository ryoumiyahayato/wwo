# 仓库调查与设计依据

## 1. 调查范围和证据口径

读取了用户三份附件及末尾评论，核对普通启动场景、正式模拟、vNext 的运行时、经济、组织、人口、政治、空间、军事、存档边界，以及相关测试和数据加载路径。本报告是架构调查，未声称做过全仓逐行审计或新玩法人工验收。

基线提交：`85c073649e1ed17594f2a41d4f2081feceeabe8b`。`git ls-remote origin refs/heads/master` 返回同一提交。仓库起初工作区干净；实际仓库目录为 `D:\wwo\wwo`，根级 README/AGENTS 中的 `D:\wwo` 命令需要按实际路径覆盖。

下列链接以本地仓库根为相对基准，可在固定提交的 [GitHub 源码](https://github.com/ryoumiyahayato/wwo/tree/85c073649e1ed17594f2a41d4f2081feceeabe8b) 中核对同名文件。

## 2. 已确认事实

| 编号 | 代码证据 | 事实 | 实施含义 |
|---|---|---|---|
| E01 | `project.godot:15`；`scripts/formal/formal_world_application.gd:12` | 普通入口仍创建 FormalWorldSimulation | vNext 独立测试通过不等于进入产品 |
| E02 | `scripts/formal/formal_world_simulation.gd:11,38,89` | 正式组合主要是时间、Formal Economy 及其存档 | 不能假定组织、人口、政治、军事已挂在正式推进链 |
| E03 | `scripts/formal/formal_world_economy_service.gd` 的 `configure`、`_settle_day`、`_settle_country` | 151 个政治单元；50 个详细经济记录；背景政治单元没有相同详细经济结算；日产出包含 demand × production_factor | 正式经济可保留作迁移对照，不能当作已具备企业投入与资金循环的完成品 |
| E04 | `scripts/vnext/world_runtime.gd:95,128` | advance_minutes 只加时间；snapshot 仅含时间、玩家、钱包、位置、事件知识 | 需要真正的世界组合和推进，当前不会自动推进旁边的领域 |
| E05 | `scripts/vnext/economy/market_economy_catalog.gd:205,316` | `_load_world_profiles` 从 Alpha world 加载市场；历史 50 国表用于 source_summary | 配方和核算逻辑可复用；不得把 summary 计数当作实际市场覆盖 |
| E06 | `data/alpha/world.json`、`commodity_market_1900.json` | 静态解析得 2 国、8 地区、49 生产点、67 商品、38 配方；历史政治目录 151 行，经济 compact 50 行 | 新目录必须把可复用商品配方和旧架空地点、企业初值分离 |
| E07 | `scripts/vnext/economy/market_economy.gd:769,845,1510` | 已有投入、产出、库存、运输守恒；居民按 min(库存,需求) 消耗，就业主要从生产结果推算 | 缺少所有者账户付款和先分配劳动再生产，需补足资源制约 |
| E08 | `scripts/vnext/organization/organization_core.gd`；对应说明 | 已有组织结构、成员、职位、授权、严格恢复；没有经济或任职过程联动；每人在同组织当前仅一个任命 | 复用结构，增加任命生效边界和身份选择；不要复制成员表 |
| E09 | `scripts/vnext/population/macro_population.gd`；对应说明 | 有人口、年龄/性别/城乡边际、月结算余数和内部迁移；没有就业分配与具名人口归属 | 不能将三个边际表相乘当成已知联合分布，不能从人口数直接增加士兵 |
| E10 | `scripts/vnext/military/military_service.gd:485,557` | Military 内部收集后分配，再推进 Spatial 窗口；supply_inputs 每小时重新构造供给 | 接入生产经济时需拆开收集/提交/推进；区域供给输入不能成为正式无限物资源 |
| E11 | `scripts/vnext/economy/market_economy.gd:1063`；`spatial_capacity_window.gd:498` | Economy 自行申请日首小时窗口；Spatial 依 request_id 顺序重分配当前请求 | 两个领域内部各自“两阶段”仍不足以跨领域共同竞争。当前 ID 排序也不是有经济含义的优先规则 |
| E12 | `scripts/vnext/spatial/spatial_world.gd:17,204`；`military_state.gd:13` | Spatial 有 territorial facts；Military 另有 region_controls | 必须明确替换为同一控制写入边界、处理 place/region 粒度映射，不能仅同步两份字典 |
| E13 | `scripts/vnext/politics/politics_update_service.gd:79` | 对外部 pressure 输入做确定日步，并可自动改变政策和政府 | 可保留作旧行为对照；新世界需要真实数据适配和有制度程序的职位/政策提交 |
| E14 | `scripts/vnext/identity/stable_id.gd:40` | ID kind 白名单有限；职位、任命使用组织内局部 ID | 新增资源和流程 ID 需扩展契约或使用有类型局部 ID；不能直接声称任意 `loan:*` 已可用 |
| E15 | Formal 初始化分钟 0；政治目录 snapshot_date=1900-03-12 | 当前形式时间起点与所加载政治快照日期不一致 | 新场景头必须声明唯一 start_datetime 和每个数据包的有效日期；不能暗用 Alpha 的另一个日期 |
| E16 | `scripts/vnext/spatial/spatial_catalog.gd:10,60`；加载的 world_map JSON | 实际源数据含32城市、9铁路段、3道路段、3航线、8港口；177国家条目和151历史政治单元口径不同 | 地图显示完整不等于 vNext 物理图完整；R09增加正式场景加载和粗锚点/交通联系的迁移 |

E11 的风险来自代码组合推断，不是在正式入口重现的线上故障：当前这些领域并未一同进入正式入口。应在正式接入前加入跨领域顺序置换测试。

历史交通 compact 另外含50条国内、30条海运、13条河运估计记录，可作为迁移资料候选；不能把它们与 vNext 实际加载的边相加后报告为当前可用路线。

## 3. 复用、改造、退役

| 组件 | 决定 |
|---|---|
| VNextWorldRuntime | 扩展为唯一运行时，保持候选恢复语义 |
| FormalWorldSimulation | 在新入口完成验收后退役运行职责；之前保持旧入口可运行，禁止在同一会话双跑 |
| FormalWorldEconomyService | 提取历史目录与 crosswalk 的加载经验；旧产出公式不接入新资源账 |
| VNextMarketEconomy | 保留商品、配方、守恒、价格回归经验；拆出库存/生产/交易职责，去掉正式模式中的隐式供给与双运力 |
| Spatial | 保留图、设施状态；改成全领域一次分配，明确控制账 |
| OrganizationCore | 保留，围绕它添加有时间边界的命令接口 |
| MacroPopulation | 保留人口权威与迁移守恒；另加互斥劳动状态、具名覆盖映射 |
| Military | 保留部队、路径、命令身份；替换源头补给与一次性战斗结算，移除控制副本 |
| Politics | 保留数据和只读政治摘要；支持变化、制度过程按本规格重接，不自动复制旧阈值为新世界真理 |
| VNextPersonalWallet | 改为 Finance 中 person 对应账户的门面，禁止再保存一份余额 |
| AtomicJsonFileStore、V2DateTime | 直接复用文件安全写入和纯日期转换；保持无业务时钟 |

`docs/vnext/reuse_migration_inventory.md` 已把 FormalWorldSimulation 列为 DELETE_AFTER_REPLACEMENT，和本方案一致。`docs/DECISIONS.md` 中仍含旧时钟/小时权威描述，不能与新分钟架构同时当作现行规则；W00 必须记录替代关系，不静默并存。

## 4. 为什么三份回答还不能编写

它们主要提供了对象命名、原则、职业和阶段。真正未定的是：同一时刻谁先结算；两方争抢同一资源如何裁决；工人和钱到底在哪一张表；交易未完成如何恢复；政策怎样成为执行行为；普通主体如何实际选择行为；性能超预算时怎样继续保持同一世界。把这些交给后续 AI 自行理解，会产生彼此不兼容的实现。

本交付因此选定一种具体可替换的模型：有边界的固定步结算加到期队列、整数分配、显式资源占用、有限候选决策、有时滞的社会反馈。它是可以验证和修订的游戏模型，**不是证明社会现实必然遵循这些公式**。

## 5. 外部依据及使用范围

- [Godot 4.6 GDScript reference](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdscript/gdscript_basics.html)：核对 int、引用传递和整数除法；本方案明确可变容器不能直接交给 UI，并要求发布版显式验证，不能仅用 assert。
- [SimPy Time and Scheduling](https://simpy.readthedocs.io/en/latest/topical_guides/time_and_scheduling.html)：参考离散事件队列与同刻确定次序；WWO 采用自己的领域阶段，不引入 SimPy 运行依赖。
- [Grimm 等，ODD 2020](https://www.jasss.org/23/2/7.html)：参考状态变量、调度、初始化、子模型和可复现描述要求；它不能替代 WWO 的经济和政治规则。
- [Bank of England，Money creation in the modern economy](https://www.bankofengland.co.uk/-/media/boe/files/quarterly-bulletin/2014/money-creation-in-the-modern-economy.pdf)：只用于区分贷款资产、存款负债与跨行结算；不据此声称 1900 年所有国家使用同一种货币制度。

## 6. 本次实际验证

指定 Godot 实测版本为 `4.6.3.stable.official.7d41c59c4`。验证结果及完整命令另见 `verification.md`；原始日志位于 `local-artifacts/architecture-review-20260908/`。设计中的新增验收仍是待实现规格，不能计入现有通过数量。
