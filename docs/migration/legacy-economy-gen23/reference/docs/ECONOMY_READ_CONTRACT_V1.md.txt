# Formal 只读经济接口 v1

本合同供原有 Formal 经营界面读取；不新增地图、GUI、命令、世界时钟或数据库。入口：`EconomyR1Slice.economy_read_view(authenticated_actor, firm_id, site_id)`，实现为 `scripts/world/economy_read_contract.gd`。不改主 WWO。接口投影可按需读取，禁止以持续轮询或后台进程运行研究世界。

## 身份、权限与时点

宿主必须用原有认证/当前玩家上下文提供 `authenticated_actor`；**不得从网页参数直接接受任意 actor/firm 身份**。`_manager` 与本站所有权检查不通过时返回 `{}`。原 Formal 内部企业操作者可用其稳定 firm ID；这不允许玩家冒充企业操作者。所有返回对象均为副本；修改返回值不改变原权威。

根 `format=economy_read_v1`；`minute` 是原 GameClock 的总分钟，`day` 是已结算原生日；根 `visibility=AUTHORIZED_CURRENT_MANAGER_OWN_BUSINESS`。发生于历史时点的订单、付款、交付保留各自时戳，不把它们改成查询时刻。没有墙钟实时性承诺。源码版本由宿主加载的精确 Git SHA 标记，配置版本由 `configuration_source.case_id` 和活动 `process.source.id` 追溯；不要把开发配方出处写成历史事实出处。

## 字段与权威

| 字段 | 来源、含义与单位 | 可知范围 |
|---|---|---|
| `firm_id`, `site_id`, `place_id` | `_spec`、`_owner`、正式地点目录；稳定字符串ID | 本企业本站 |
| `configuration_source` | 原配置 case、正式身份绑定方式、规范化配方出处 | 本企业；开发配置标识须显示 |
| `units.goods` | `_good_units()` 中实际货批计量单位ID；本试验质量商品为 kg，布为 m，食品、成衣和工具为 piece；配比未历史标定 | 本业务商品目录 |
| `activities[].recipe` | 原规范化 outputs/materials/hours/capacity_units + 可选 process | 本站配方，不是全球技术树 |
| `planned_batches`, `actual_batches`, `cumulative_batches` | 原 `_plans` 和 `_site_state`；整数批次 | 计划不当作实际产出 |
| `actual_inputs`, `actual_outputs` | 当日已执行批次乘原材料/合格品系数；商品单位 | 用 source/portion 成本记录核对；没有执行则为0 |
| `declared_non_saleable_rejects` | 已执行批次乘合同 rejects；单位同相应产品 | 确定性工艺损耗观察，不是可售货批，不创建废料商品 |
| `allocated_person_hours` | 实际批次乘原 hours | 分配到生产的人时，不是全部已工作小时 |
| `capacity_available_units`, `capacity_used_units`, `capacity_utilization` | 原资本池及实际活动用量；能力单位/合格生产日；无能力时利用率 null | 各活动共享池，不可将每行可用能力再相加当总能力 |
| `process_status` | 合同当前周期/额度/不可用检查 | 查询时下一批资格；完成最后一批后可能已显示额度耗尽 |
| `observed_constraints` | 查询时周期、计划/实际缺口、末日现场材料与劳动观察 | 是观察依据，非完整反事实归因；材料名标明 CURRENT |
| `physical_totals` | `_physical_totals` 的累计实耗/产出 | 本站，含所有活动 |
| `inventory` | 原 `_inventory_view` / StockLots 投影 | 本站可知库存与责任；沿用原界面对货运信息的可知性 |
| `inventory_status` | 原本站 StockLots、`_committed`、已接受订单及 delivery；含现场、现场预留、未预留、已接受入库、合同在途、累计实交付 | 不依赖成本核算开启；合同在途不冒称远端现存实物 |
| `finance.account_cash` | 原 Ledger balance/reserved/available | 货币面额分开；金额为整数最小单位 |
| `finance.wages_incurred/paid/unpaid`、`wage_claims_latest8` | 实际 work_records、工资 claim 和 Ledger；人时、货币、工作日/到期日 | 已发生、已付及未付责任分开；未到期未付不等于拖欠 |
| `finance.direct_costs` | 原 EconomyCostAllocation | 已知直接成本、未知成本数量、有限毛贡献；不叫净利润 |
| `seller_quotes` | 原本企业 `_managed_listing_view` | 当前卖方报价、生效/到期时间；不是成交价 |
| `actual_trade_prices_latest8` | 本企业订单关联的真实 delivery_receipt 和订单锁价 | 商品、数量、面额、实际交付分钟；不是宏观估计价 |
| `orders_latest8` | 原 `_order_view`，只取本企业参与的订单 | accepted/分批/取消/已交付、路径和资金责任沿用原语义 |
| `payments_latest8` | 原 Ledger.own_transactions | transaction_id、reference_id、金额、effective_minute；不伪造付款 |
| `npc_results_latest8` | 本企业 `_commands` 中真实 envelope/result | action_id、是否 accepted、原 reason；未提交行动不能伪造成拒单 |
| `truncation` | 历史列表仅最近8条 | 不是全历史接口；累计量及财务窗口另有说明 |
| `excluded_internal_state` | 明确的排除类别 | 其他企业私账、未送达信息、宏观估计流及未确认货运结局不提供 |

`inventory` 为本站各商品的密集数量表，包含现场已预留数量；`inventory_status` 明确区分未预留与现场预留。站点 quantity 不等于可售 surplus；预留、承诺、运输、交付必须按原字段读取。货物处于 CARGO 的所有权和实际保管地点分开；有线路或 accepted 订单均不代表已交付。累计交付以真实 receipt 为准。财务 `classification_basis`、直接成本 `basis` 和 `unknown` 必须保留。

## 研究专用证据，禁止接入玩家可见接口

`production_network_check.gd` 直接访问的 `_spec`、全网 `_stocks`、全部账户、全部命令、未接收信息、真实内部 shipment 状态、资源计数和跨企业对照，只供有限开发研究。研究 JSON 中 `initial_stock`、`result.firms`、`marks`、`counts`、`resources`、`evidence` 均为 `DEVELOPER_RESEARCH_ONLY`；不因被记录便成为玩家可知。

导出的 `readonly_sample` 已通过入口权限核对，但其样本身份是正式内部企业操作者，主工应以真实当前玩家身份再次查询。样本不是授予玩家的新权限。研究序列化字节包含内部状态，绝不能直接绑定公开GUI。

## 可选生产 process 合同

既有 `activities` 的 product/output 单位在全局 goods 表中；生产主体、站点、合法地点来自原 firm/site/`place_id`；`outputs` 为每批合格品，`materials` 为每批货批消耗，`hours` 为整数人时，`capacity_units` 为原共享设备池消耗。岗位技能由原 job 的 skill 门槛与原入职检查执行；**活动级岗位隔离尚不支持**，必须声明 `ACTIVITY_LABOR_ROLE: UNAVAILABLE` 才能要求这种约束。

`process` 是严格字段校验对象，缺省保持旧行为并显示 `LEGACY_UNSPECIFIED`。声明时包含：

| 字段 | 语义 |
|---|---|
| `format` | `production_process_v1` |
| `technology_id` | 初始静态工艺ID；不实现运行中研发、迁移或免费升级 |
| `batch_unit` | 批次单位，如 development_batch |
| `source` | id、basis、estimated（bool）、hours_unit=person_hour、capacity_unit=capacity_unit_per_eligible_day |
| `gross_outputs`, `rejects` | 与 outputs 同键；gross−rejects 必须精确等于可售 outputs，非负整数 |
| `first_day`, `cycle_days` | 仅在 `day>=first_day && (day−first_day)%cycle_days==0` 的每日边界执行 |
| `max_batches_per_cycle` | 每个合格日的批次上限；不是额外设备能力 |
| `lifetime_batch_limit` | 该活动整个存续期累计批次上限，用原 `_site_state.activities.batches` 扣减 |
| `constraints[]` | kind/availability/source/unit；任何 UNAVAILABLE 必须使计划和实际执行为0 |

周期只表达“允许开工的离散日期”，**不是多日连续施工或在制品系统**；若需要后者，声明 `MULTIDAY_WIP: UNAVAILABLE`。批次上限不是土地面积或矿藏吨数；二者必须有独立资源权威后才能适配。本轮 LAND、BIOLOGICAL_CYCLE、MINERAL_DEPOSIT、ACTIVITY_LABOR_ROLE、SPECIFIC_EQUIPMENT、FUEL、SERVICE_OUTPUT、MULTIDAY_WIP 均可显式声明不可用，不能填成无限供应。运输的车船/燃料要求应接原 SharedTransport/CapitalTransport；无实物输出的服务应接原 ServiceMarket，不强制生成库存。本轮未将这些行业全部实现。

本轮食品是使用原 bread ID 的有限开发口粮替身；按件计数，不声称已经模拟真实面包烘焙的水、燃料、烤炉和热过程。若配方声明这些必要条件，则必须通过现有材料/设备机制满足，或明确 UNAVAILABLE。

工资及采购支付责任继续由原岗位、Ledger、订单和运输合同承担；合同不凭参数再扣一份钱。设备折旧和通用间接费用尚无配置，净利润字段不可伪造为0。实际损耗是净收率约束，不把不合格品当第二份可售产出。

## 三个实际状态样本

随本轮运行证据另附正常经营、缺料停产、资金/订单失败样本及精确 minute、source SHA、Actions URL。主工只将其中经权限投影的字段映射到已有界面；研究额外字段用开发标签显示，不能绕过当前玩家原有权限。不需要复制实验工程或地图资源，也不要求本地启动新的验收程序。
