# 04：共同运力、最终分配与真实占用

本文件是本地开发指令。提示词已准备，尚未执行。先读适用AGENTS.md、 `D:/programs/WWO/handoff/economy-review-20261013/REPORT.md` 和01至03真实反馈。核对批次、预算、取消及恢复的新接口，不依据旧提示词臆造方法。未满足的前置写明；不绕过批次和原订单另建运输库存。

## 本地接口与关键语义

正式根 `D:/programs/WWO/wwo`：

- `scripts/vnext/spatial/spatial_world.gd`：`request_capacity(request_id, link_id, window_hour, demand)`、`request_capacity_batch(request_values)`、`reservation_result`、`reservation_results_batch`、`cancel_capacity_request`、`capacity_summary`、`effective_capacity`、`advance_to_hour`、`snapshot` 和 `restore`。
- `scripts/vnext/spatial/spatial_capacity_window.gd`：小时级共享窗口。请求字段为 `request_id`、`link_id`、`window_hour`、`demand`。加入或取消请求会重算分配，`advance_to_hour()` 跨小时清空请求；只接受当前窗口。`reserve_capacity()` 只是请求别名。返回 `accepted=true` 不等于得到全部需求，也不等于分配已固定。
- `scripts/world/economy_r1_slice.gd`：`_cargo_edge_valid()` 的HOST_LINK是实际链接引用验证；`_route_available()` 受首段及已知路线约束；`_dispatch_transport()`、`_enter_transport_leg()`、`_advance_shipments()`、`_set_edge_capacity()`、`_transport` 目前还有经济自己的容量、holds和节点吞吐。关闭边当前限制新进入，已入边保持锁定行程。
- `scripts/simulation/simulation_step.gd`：`_advance_minutes()` 和 `_synchronize_spatial_to_authoritative_hour()` 使用唯一GameClock。当前原生运输主要日结，不能把一天运力自动等同于结算那一个小时的容量。
- `scripts/vnext/economy/market_economy.gd` 与 `scripts/vnext/military/military_service.gd` 已有批量请求和最终查询，可参考调用结构。它们不是当前正式EconomyR1Slice或最新Task6已接通的证明。
- `scripts/world/formal_person_travel.gd` 的实际旅行路径、 `scripts/world/world_state.gd` 的领域引用、 `scripts/content/world_bootstrap.gd` 和 `scripts/persistence/formal_persistence.gd` 的装配/恢复需按当前调用链读取。

独立十五类根 `D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo` 的 `economy_quantity_lab/algorithm_completion/world.py`、 `test_spatial.py` 已有共享边、在途停顿和运费反例。它的路径接受及逐段限制不能直接当成当前小时窗口最终分配。

## 本阶段要实现的连接

1. 先核对实际运行中谁提交、谁查询、谁执行、谁释放链接容量。把原生货运接入既有Spatial权威，清楚区分路径计划/报价、当前窗口候选请求、最终分配、实际进入消耗、未来尚未实现的承诺。未来计划不是既有 `request_capacity_batch` 已支持的未来预留；若需要未来承诺，明确新增状态和验证，不伪调用尚不存在的接口。
2. 在明确共同边界收集接入范围的全部请求，查询最终结果后才采用发运。处理同小时晚到请求、取消和容量变化：不能让前批货物按旧结果已发出，后批又按重分配结果使用同一容量。可扩展窗口的固定采用/已用记录，或在共同调度端分隔未采用与已用池；这是待新增能力。保留原调用方的明确契约，不把既有reserve别名偷偷改成不可撤销锁且忽略其调用方。
3. 采用记录引用原订单、shipment、批次份额、边/节点、窗口和事件ID。重复发运不重复占用；同一批次多任务竞争不得各获一份。未采用取消释放请求；已完成运输不能回吐已用容量；途中放弃按真实离开边界处理未来占用与货物保管。不能把订单取消、货物归属和运力释放合成一个无条件删除动作。
4. 以03实际单位重量与批次可装量计算货物占用。道路/铁路吞吐、载具载重、装卸工时和节点堆存是不同约束，分别建引用，不互相替代。保留承运者、现场工人及现有设备约束；节点装卸与生产/施工若争用同一人员或设备，只能分配一次。先接明确的有限路线与节点，不新造全球路径重算系统。
5. 货运、实际使用同一设施的旅行和现有军事调用方在所选范围共用容量。先核实旅行是否已有容量消费，未接入时报告边界，不能虚写已共享。不同交通模式如使用不同物理资源，应由数据说明共用关系，不强行让所有人和货物相加。
6. 对原生旧capacity/holds给出替代范围。被共同物理容量接管的部分成为引用/投影，不再额外获得一份独立额度。用于报价或订单承诺的记录可保留，但不能在进入时与真实消耗重复扣同一容量。限制路径信息为主体所知；空间权威校验不向玩家或AI泄露未获知路径。
7. 在SimulationStep接入容量结算所必需的边界，保留唯一GameClock和原生日结策略。本阶段只改明确的运输/容量调度，不把全经济改为秒级。不得默认日容量除以24或把全天发运塞入最后一小时。提出实际排班/窗口映射选项，用户选定后再改变原生运输时间安排。

## 用户选择、保存与兼容

需要用户明确：共用设施与容量单位；原生日容量到小时实际安排的映射；装卸由谁提供、工作时段与成本；同窗分配优先规则；迟到请求及入边后断路的处理。默认保留当前明确的入边后锁定行程，除非用户选择改成可中断规则。05再实施细时间模型。公平、军需优先或价格竞标都不是未经选择的要求。

需要变更的窗口采用/已用记录、未完占用、装卸阶段和稳定ID必须进入共同候选恢复，并与03批次、02预算和原shipment一致。小时窗口清空不能销毁尚未完成的跨窗责任；恢复后不能重新获得已用额度或重付运费。旧独立经济holds与Spatial请求不能在迁移时各算一份。真实已入边物资保留原合同及锁定行程；无法映射的旧活动明确迁移或拒绝，不初始化补库存。只改本阶段所需数据格式，不覆盖实际存档。

## 完成标准与针对性验证

用一段共享链接和一个装卸节点的短业务，验证两家企业、民需/军需或货物/旅行的共同竞争。验证批量最终查询、迟到请求、取消重分配、已用不可回吐、同一shipment重试、跨小时及跨窗在途、节点缺人、部分装载、断路和候选恢复。当前边关闭规则与未来中断规则分开断言。

局部参考 `D:/programs/WWO/wwo/tests/vnext/market_economy_spatial_day_window_test.gd`、 `market_economy_spatial_integration_test.gd`、 `military_spatial_capacity_integration_test.gd` 和 `tests/formal/formal_spatial_persistence_integration_test.gd` 的相关短案例。先读运行器和时长，只运行实际受影响部分；必要时在现有测试结构中增加本阶段短业务测试，不整体启动不相关实验或长期模拟。回归01至03实际受影响的发运、支付、取消和恢复案例。不另建门禁、验收矩阵、证据包或哈希清单。

完成标准是接入范围内只有一份可消费的物理容量和装卸能力，真实采用后不被重分配制造超用，订单/批次/付款/占用各有原引用。记录每窗口请求量、分配重算次数、路径访问与活跃占用数；不以存在批量API就宣布性能通过。为05/06交付当前真实时间单位、采用边界和资源端口。

## 执行后反馈要求

实际执行后，生成中文04结果报告和交接摘要，保存本地并上传私有仓库 `ryoumiyahayato/wwo` 的独立文档分支。保留原研究、审议、提示词和他人工作。建议路径为 `docs/research/local-economy-review-20261013/execution-feedback/<实际日期时间>/04-RESULT.md` 及 `04-HANDOFF.md`。

写清改动前后运力分配/采用行为、实际文件与接口签名、旧capacity/holds删除或替代范围、已接与未接调用方、用户选定的单位/窗口/优先规则、保存和迁移、实际验证命令/结果、未运行检查、未完成项及对05时间和06军需链的影响。标明所执行提示词和云端研究版本 `beed4b12c0d0fd0c0a8a04afd9f30481db533918`。只上传反馈文档，不上传源码快照、存档、凭据或无关材料，不创建PR、不合并；远端读回核验并返回链接。部分接入不得报告整个世界已共享运力，计划不能当完成。云端聊天模型下一轮下达指令前必须先读本反馈和摘要，更新容量、时间、取消和恢复接口，再决定后续任务。
