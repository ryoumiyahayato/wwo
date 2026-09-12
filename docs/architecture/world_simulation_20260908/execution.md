# 工作 AI 执行单

> 已根据用户反馈停止将本单作为建议执行顺序。不要据此启动W00→W21整体迁移；请先阅读[组织场景设计](../ORGANIZATION_SCENARIOS_20260908.md)，按新的组织范围开展后续已授权工作。

这份执行单在用户授权实施后使用。本次只交付方案。不要因为本文使用命令式语气，就把当前需求改成直接开发整个游戏。

## 1. 统一任务协议

输入是本目录全部规格、基线提交、指定任务编号、前置任务的验证记录。开始时检查 HEAD 与基线差异，并重查相关调用链；文件存在不代表接入。实现时以当前 AGENTS.md 的引擎、语言、权威状态约束为硬限制。

每项任务必须提交：

- 有限范围的实现和完整配置，数据记录带版本、单位、来源/生成方法；
- 对应 `acceptance.json` 测试 ID 的真实断言，测试直接调用与产品相同的领域和组合接口；
- 修改过的快照字段、读写 owner、旧接口替换情况；
- 可复现命令、提交/工作区状态、引擎版本、退出码、日志路径和限制；
- 如果涉及可操作行为，提供正式命令入口及可读原因/结果，不能仅公开一个测试 setter。

完成是功能/边界成立，不能用文档字数、字段数量、测试条数替代。TODO、空实现、无条件 success、把资金不足自动补满、测试中避开正式约束均使任务未完成。前置数据缺失时先完成可独立验证的算法，准确列出所缺记录；不能宣称完整世界验收通过。

## 2. 依赖图

```text
W00 → W01 → W02 → W03 → W04 → W05 → W06
                                      ↓
W07 → W08 → W09 → W10 → W11 → W12 → W13 → W14
                                                  ↓
                     W15 → W16 → W17 → W18 → W19 → W20 → W21
```

上图是默认串行执行顺序；每项下面列出的依赖是实际门槛。顺序是为了让同一个世界逐渐获得完整的流量和行为，不是另开二十二个互不相干的系统。W06 后仍是未完成开发态；只有 W21 满足整体交付条件。

## 3. 明确工作项

### W00 — 固定基线与现行决策

依赖：无。读取 `project.godot`、`docs/DECISIONS.md`、`docs/vnext/reuse_migration_inventory.md`，复核 audit.md 的 E01..E16。记录当前 HEAD、目录计数、原有验证结果。将“唯一分钟时间、vNext 替换 Formal、历史世界数据范围”的新决策写成有替代对象的记录，不能留下互相冲突的现行说明。

输出：`implementation_baseline.json`（新文件，建议 `local-artifacts/world-simulation/`）、决策条目和现有回归结果。验收：T01、T32 的基线部分。不能直接改普通入口，也不能删除旧世界来减轻测试负担。

### W01 — 单位、ID 和精确数值工具

依赖：W00。修改 `scripts/vnext/identity/stable_id.gd` 与 catalog contract；新增 `scripts/vnext/numeric/fixed_math.gd`、`largest_remainder.gd` 及相应测试。定义 runtime.md R02 的单位和 ID 类型，所有整数乘除检查溢出，明确 signed 舍入。

输出：统一 quanta/LU/minor_units、积分余数、分配函数、幂等序号结构。验收：T02、T03、T04、T35。不能在各领域复制一份“差不多”的 rounding。

### W02 — 从真实世界资料构建可验证场景目录

依赖：W01。修改 `scripts/vnext/economy/market_economy_catalog.gd`，新增 `scripts/vnext/scenario/world_scenario_catalog.gd` 和 `data/vnext/world_1900/manifest.json`。复用历史政治身份、crosswalk、已有地图锚点，分离 Alpha 商品配方与架空地区初值。

逐项给商品/配方增加单位、时长、劳时、载荷、仓容、资源池字段。未知历史数值可以有带方法的模拟估计，身份/空间映射不能靠字符串猜。

输出：151政治单元的覆盖映射、经济分区去重、错误定位到 record_id 的启动检查。验收：T01、T05、T32。禁止用 `historical_country_count` 冒充实际模拟市场计数。

同时修改 `scripts/vnext/spatial/spatial_catalog.gd`，增加R09的正式场景加载、source-derived锚点及显式粗交通联系。现有小型交通图只保留在旧夹具路径；输出连通分量、未连接人口比例与所有推定边清单。

### W03 — 人物与人口的共同归属

依赖：W02。扩展 `scripts/vnext/population/macro_population.gd`；新增 Person 记录、Labor cohort 和 named_claim 映射，保留现有边际与迁移余数。PlayerState 绑定真实 Person；人物技能/健康不塞到 session。

输出：互斥可用人口集合、具名化/死亡/迁移的候选转移。验收：T14、T15、T16。不能在生成玩家时多加一个人，也不能从年龄/性别/城乡边际相乘伪造联合统计。

### W04 — 统一资金、债权、库存和资源预留

依赖：W01..W03。新增 `scripts/vnext/finance/finance_ledger.gd`、`claim_book.gd`、`budget_book.gd`；新增 `scripts/vnext/economy/stock_ledger.gd`。将 `personal_wallet.gd` 改为同一账户门面。建立 opening journal、库存位置/所有权/保管、带期限的 hold 和幂等命令结果。

输出：TradeSettlement、ResourceDispatch、PersonnelTransition 的有类型 prepare/validate/install 协议。验收：T06、T07、T08、T09、T17、T26、T34。不能只保证单张账非负而漏检跨账守恒。

### W05 — 确定边界调度器

依赖：W01、W04。新增 `scripts/vnext/simulation/world_scheduler.gd`、`world_step_coordinator.gd`。实现 R05 六个业务阶段及提交后派发、同刻排序、generation 过期项、依赖索引和不丢任务的分片。

输出：下一边界推进，过程持久头，有积分余数的旧区间结算。验收：T03、T18、T19、T20、T27、T36。测试必须覆盖在30分钟修改计划、同一分钟撤职/签署、空队列、零时长反应循环和预算中断。

### W06 — 扩展唯一运行时和候选恢复

依赖：W02..W05。扩展 `scripts/vnext/world_runtime.gd` 和 `persistence/world_snapshot_store.gd`，显式构造领域 owner；原先 travel 直接推进时间改为创建实际旅行过程，WAIT 通过 coordinator 推进整个世界。

此时先接已经完成的领域，新领域按后续工作项加入同一 schema 版本开发分支。进入发布前由 W18 固定最终字段。

输出：v3 世界组合、只读摘要、原子整体恢复。验收：T18、T26、T27、T34。不在 VNextWorldRuntime 内再 new FormalWorldSimulation；不让旅行把世界其他领域的时间跳过去。

### W07 — 实际就业、工作、工资与居民预算

依赖：W03..W06。新增 `scripts/vnext/labor/labor_service.gd` 和 household demand 服务，接入真实岗位与工资合同。按 A02/A03 应计和支付，已有工作、失业、训练、迁移互斥核验。

输出：工作开始/结束/变更班次命令、群体和具名角色同一工资路径。验收：T06、T07、T14、T18、T39。必须有“缺钱所以欠薪”的路径，不能回滚已工作的时间。

### W08 — 生产/WIP/维护/建设

依赖：W04、W05、W07。从 `market_economy.gd::_run_production` 拆出生产服务，使用真实投入和人分钟，接入 site 所有者、成本与正时长过程。旧反推就业与库存上限删除式修复从正式路径退出。

输出：A04完整排产、取消回收、维修、扩建。验收：T10、T11、T12、T18、T33。改变 site 遍历顺序不能让下游得到未来产出。

### W09 — 付得起才成交的市场

依赖：W04、W07、W08。改造 `_consume_households`、`_update_prices`、地区库存访问，市场聚合改为各 owner 库存的只读求和。实现 A05 需求预算、日界成交、现金预留、税费、价格余数。

输出：可解释的 desired/funded/ordered/delivered/consumed 区分、同价比例成交、买卖配对。验收：T06、T08、T13、T21、T28。居民无钱时不能仍免费吃到市场库存，政府补助要有实际出资。

### W10 — 统一经济、军事、人物运输竞争

依赖：W04..W09。改造 `spatial_capacity_window.gd`、`spatial_world.gd`、`market_economy.gd::_schedule_spatial_shipments` 和 `military_service.gd::_advance_one_hour`。

将各领域方法拆成 `collect_transport_demands → prepare_progress(final_allocations) → install`，仅 coordinator 推进窗口；Spatial finalize 之后拒绝旧窗口新增请求，未来增补按 R05 新窗口剩余规则。迁移现有 military supply fixture 为非正式入口。

输出：共同批次、冻结分配、下一路段运输、真实在途、部分交付和断路恢复。验收：T02、T09、T17、T20、T22、T23、T24。排列 Economy/Military/Travel 的收集顺序至少六种，所有状态 hash 相同。

### W11 — 知识和有限候选决策

依赖：W07..W10。扩展 `events/event_knowledge_state.gd`，新增按角色分离的候选生成/预测服务；声明每个计划的信息来源、硬约束、预测期和确定排序。实现 A07；每个 NPC 与玩家走同一命令入口。

输出：能够自行消费、求职、排产、补货和处理失败的背景主体；报告传递有时长。验收：T25、T28、T29、T30、T39。不能用全局真相选择玩家不知道的供应商或敌军。

### W12 — 政府规则、预算、案件与实际行政服务

依赖：W04、W07、W11。围绕 OrganizationCore 增加任命时间、身份选择和有类型 institutional procedure；新建 `politics/institution_service.gd` 与行政任务过程。数据包明确每国支持的制度类型和权限范围。

输出：税、预算、救济、调拨/征用、补偿、有限执行人员；按 A10 创建和履行实际任务。验收：T07、T19、T31、T37。仅通过法律不能自动完成100%征用，也不能创建新的现金。

### W13 — 工会、媒体、群体支持与正式政治程序

依赖：W07、W11、W12。将现有 PoliticsPressureInput 改成已提交事实/已知报告的派生输入，接入 A09 的压力、偏好、罢工基金、出版、表决、席位与任命。保留旧政治模型在独立比较测试中，退出正式写政策/政府路径。

输出：事实→获知→群体偏好→组织策略→程序→任命/规则→实际执行的闭环。验收：T25、T29、T30、T37、T38。世界变化不得靠写 support 后直接给全国生产 modifier。

### W14 — 受真实人力与补给约束的持续战争

依赖：W03、W04、W10..W13。改造 Military 的建军、补给与 `_resolve_attack`，接入 A11 连续交战、伤亡、撤退、医疗及控制写入。旧 region_controls 改成 Spatial 控制账视图，明确 region/place crosswalk。

输出：战争权限、实际接敌、参战分配、消耗、伤亡、后送、控制变化。验收：T15、T16、T22、T23、T24、T40。不能用默认无限 supply_inputs 为正式部队续命，也不能由战斗 UI 直接提交死亡。

### W15 — 信贷、跨行结算、重组和破产

依赖：W04、W09、W11、W12。新增 `finance/credit_service.gd`、`bank_settlement.gd` 和 insolvency 过程。按 A08 记录贷款/存款/准备/资本，增加利息应计、抵押登记、顺位清偿、零现金失败。

输出：有约束的扩张融资和债务失败后续，而非余额加成。验收：T07、T17、T26、T34、T41。实际部门利润、工资和订单喂给授信，不用随机标签替代偿债计算。

### W16 — 教育、研究、救济、地方关系和犯罪执行

依赖：W07、W08、W10..W15。按 A12 分别增加有类型过程和稀疏关系边，复用资金/人员/库存/行政服务。每种组织交付至少一个具备数据、决策、消耗和正式结果的过程。

输出：服务容量制约、技能/配方采用、真实救济、案件/拘押、财产转移。验收：T14、T16、T25、T31、T39、T42。不要只交付 eleven organization_kind 常量。

### W17 — 填充完整 Current World 并校准开局

依赖：W02..W16。运行 R09 装配管线和R11的G1..G3生成算法。每个 covered 区域需要 population、基本供需、至少一个资金与执行能力成立的 operator 及实际空间引用；小组织可以在 sector pool 聚合运行。

补充政府、政党、企业、军队、工会、银行、媒体、学校、慈善及地方/执法角色的内容配置。特殊制度暂未实现时明确 unsupported，不允许拿另一个国家制度默认补全后称历史复原。

输出：覆盖/估计/无法映射清单，开局资产负债平衡，启动第1日和第30日全世界过程实际运行证据。验收：T05、T14、T17、T32、T33。若必要资料仍缺，完整世界门槛保持失败，其余已完成任务可保留。

### W18 — 固定最终快照和恢复全流程

依赖：W06..W17。固定 v3 最终 schema；为 v2、旧 Formal 与缺失规则包分别提供明确路径；构建全领域候选恢复，不跨 owner 部分加载。实现详细历史归档与活跃事实保留。

输出：日中、运输途中、罢工中、战争中、贷款到期前后的保存继续等价；非法数据拒绝不改当前世界。验收：T18、T26、T27、T34、T36。

### W19 — 切入普通产品入口

依赖：W17、W18。修改 `scripts/formal/formal_world_application.gd` 的组合依赖，保留其地图表现；普通开始/继续/暂停/倍速/保存统一绑定 VNextWorldRuntime。根据选定人物的有效身份列命令，显示持久过程、原因和实际影响。

同时替换现有 economy summary 适配、地图军事/政治投影，清除旧 Formal 的运行实例。旧存档可在兼容路径读取/导出迁移，不双跑两个世界。

输出：普通启动中人物行动与背景世界同跑，镜头/面板开关不改结果。验收：T28、T32、T43；指定引擎下统一验证、1280×720实际旅程和导出烟测。不能只在 `--script` 入口接新运行时。

### W20 — 规模与模型质量验证

依赖：W19。建立分离的数值/行为/世界规模/发布验证通道；长期测试不能仅断言所有数都非负。记录每阶段时间、峰值记录数、待处理请求、延迟和活跃主体覆盖。

输出：T44、T45 的规模、种子、干预、敏感性报告。先运行真实 Current World，再运行明确标注 synthetic 的压力夹具；不得用旧2国模型的一年耗时证明151政治单元的经济、社会、战争性能。

### W21 — 最终验收与移除旧写入通路

依赖：W20。逐项核对T01..T45，`production_ready` 仅在必需的功能/数据/普通入口门槛均通过时为true。检查 UI、开发工具、旧 adapter 是否还能绕过统一资源或时间写入。

输出：可复现总验收报告、未覆盖范围、规则包版本、准确的产品完成声明。旧行为测试仅在规则确已替换且有新断言后更新；不能为追求所有绿灯放宽守恒和权限。

## 4. 给工作 AI 的一次任务指令模板

```text
请执行 docs/architecture/world_simulation_20260908/execution.md 的 Wxx。
先读 README、audit、runtime、algorithms、acceptance.json 及适用 AGENTS.md。
核实 Wxx 前置任务的实际代码和验证记录，不按文字“已完成”直接相信。
按指定 owner、时序、单位、失败语义实现；本任务未要求的系统不重写。
把 acceptance.json 中本任务涉及的样例落实成与产品共用接口的测试。
每个新增配置字段补齐所有正式记录或输出具体缺失记录，禁止悄悄填0。
运行范围匹配的验证，报告真实命令、提交、结果、剩余依赖和产品可达性。
不能把只通过独立夹具的功能报告为已在普通 Current World 运行。
```

## 5. 验证命令和边界

现有命令（当前仓库可用）：

```powershell
$repo = 'D:\wwo\wwo'
$engine = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe'
$pythonExe = 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $pythonExe "$repo\tools\run_vnext_validation.py" --root $repo --godot $engine --suite focused
& $pythonExe "$repo\tools\run_vnext_validation.py" --root $repo --godot $engine --suite long-run
powershell -ExecutionPolicy Bypass -File "$repo\tools\run_validation.ps1" -ProjectPath $repo -GodotPath $engine
```

`run_validation.ps1` 内部调用 PATH 上的 python，当前本机 python 别名不可靠，执行前将上面 `$pythonExe` 的父目录放到本进程 PATH，验证版本；不要修改全局系统配置。新增世界测试由 W01..W19 放进 `tests/vnext/*_test.gd` 自动发现；W20 将真实世界长期/性能测试加入明确独立通道，新增选项必须同时改 runner，不能在报告里编造已可用 CLI 参数。

测试文件应保存/隔离其 user:// 文件，不覆盖用户当前游戏存档。正式发布检查沿用 AGENTS.md 的完整验证要求，并补新世界的实际人物/社会/战争旅程。本次设计调查只执行了原有 focused 通道，其他命令是实施验收要求。
