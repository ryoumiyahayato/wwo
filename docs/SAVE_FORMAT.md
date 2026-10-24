# 正式存档格式

本文记录当前 Formal 产品实现。入口是 `FormalWorldApplication` → `FormalPersistence`。旧社会会话版本 1、旧手动/自动槽位和已删除的保存宿主不是当前存档路径。

## 路径与表示

- 正式文件：`user://formal_world_1900.json`。
- 临时文件：同路径 `.tmp`。
- 安全备份：同路径 `.bak`。
- 快照 schema：`formal_world_simulation_v15`。

`FormalWorldPersistenceDocument` 将快照通过 `var_to_bytes` 编码。外层 JSON 有三个字段：

```text
persistence_format: "formal_world_exact_variant_v1"
snapshot_schema_id: "formal_world_simulation_v15"
payload_base64: <Godot Variant bytes 的 base64>
```

运行数值由 Variant bytes 恢复，整数类型与浮点位不经过 JSON 数字转换。现有外层读取只接受该容器和 v15 快照，不从旧版本推测土地几何、控制权或谱系。

## v15 快照字段

`FormalPersistence.snapshot()` 返回以下 18 个键：

| 字段 | 内容 |
|---|---|
| `schema_id` | v15 快照标识 |
| `total_minutes` | GameClock 的累计分钟 |
| `minute_remainder` | 累计分钟的小时余量 |
| `historical_evidence` | 历史政治证据 schema 与指纹绑定 |
| `runtime_politics` | 当前政治实体与关联 |
| `markets` | 市场身份、来源聚合体映射与引用 |
| `economy` | 市场运行状态、运输及结算进度 |
| `spatial` | 空间、基础设施、土地几何与分割谱系 |
| `territory` | 当前领土控制者 |
| `population` | 正式可变人口状态 |
| `persons` | 命名人物覆盖层 |
| `player` | 当前玩家身份 |
| `ledger` | 账户与账本状态 |
| `personal_economy` | 账户引用、雇佣、持有批次、购入/消费记录与每日安排 |
| `organization` | 组织结构与关系 |
| `organization_composition` | 组织证据 schema 与指纹绑定 |
| `organization_responsibilities` | 组织职责评估状态 |
| `military_state` | 军事编队、行动、运输、战斗和控制变更记录 |

WorldState 只保存组件引用，不直接序列化整个对象。显示对象、UI 选择、地图相机和运算缓存不属于上述快照。

当前嵌套经济 payload 是 `formal_world_economy_state_v6`。其读取代码仍含 v1–v6 分支，政治 registry 也保留既有嵌套旧版本分支。这些分支不表示顶层读取接受旧社会存档。本轮保留它们。

## 写入与恢复

保存先通过 `AtomicJsonFileStore` 写入并刷新临时文件。临时文档经读取、精确解码及候选恢复后，才替换正式文件；上一份正式文件作为安全备份保留。失败返回读写或恢复错误。

读取先检查文件、JSON 根类型、容器和快照 schema，再通过 `WorldBootstrap` 创建候选世界。各组件恢复时检查字段、ID、引用、数值、人口与账户约束以及时间一致性。全部恢复成功才由 Application 安装候选世界。失败不替换当前世界。

主文件普通读取或恢复失败时可尝试安全备份。`save_format_version_mismatch` 直接返回，不通过备份进行版本迁移。

## 本轮保留的依赖

内部 population、person、personal economy、market、organization 等指纹绑定仍参与快照或恢复。它们尚未清除，部分会约束存档与当前输入的匹配。本轮不修改这些字段，不将其描述为仅有诊断用途。

正常格式识别、引用解析、人口守恒、账户结算、原子写入和读写错误处理继续保留。

## 个人生活新增字段

顶层 v15 与 exact_variant_v1 容器保持。个人经济嵌套 schema 为 `formal_personal_economy_state_v2`，在原五个字段上加入 `holdings`、`living_records`、`arrangements` 与 `next_record_sequence`。原 v1 读取为空财产与安排，不推测曾购买或消费的数量。

holdings 只存实际发生购入的人物/商品，数量为商品原单位的千分之一整数，保留未消费批次与累计消费量。living_records 记录购入的市场/卖方、人物/买方、数量、单位、价格、金额、日期与 Ledger 交易引用；消费记录保存扣除的购入批次引用，失败安排保留原因。每日安排保存数量、下一日期和不足时购买差额的规则。

经济 v6 新增 `personal_sale_accounts`，只记录参与交易的市场、收款账户、库存保管主体及原库存范围。旧经济快照没有该字段时读取为空。Ledger v1 支持零余额 market_receipts 账户和 purchase 收据；预算不因建立账户而增加。派生的账户交易索引、生活记录索引及下一安排日期缓存不单独持久化。

候选恢复先加载 Ledger 与市场库存及保管引用，再恢复个人财产。个人持有量和来源由购入/消费记录恢复，现金由 Ledger 原回放恢复。页面读取与候选安装不执行实际交易或消费。新增字段没有引入内容哈希相等条件；原指纹清理不属于本批。

## 人物旅行与原生范围增量（2026-10-12）

顶层 v15 和 exact_variant_v1 不变。新增可选 `person_travel`，保存显式旅客线路、当前旅行、已接受行动、NPC政策、公告和携带条件。唯一所在地继续保存于 `persons`。没有该字段的旧存档保持没有旅行，不创建路线或收费。恢复旅行不推进时间、扣票款或再次到达。

原生 `economy_native` 保存 `scope_requests` 和 `subject_activation`；旧原生快照缺少时读取为空。原配置、既有经济状态和历史业务不重新初始化。扩容申请保留排队边界、生效分钟和延后原因。新增主体的需要累计只计算生效后的完整日，不补算旧宏观历史。

个人v3可选 `runtime_accounts` 标记运行中开立的零初始资金账户；这些账户不要求开局现金收据，也不扩大初始资金预算。原个人v2/v3、经济v6和Ledger收据保持原义。新领取receipt保存 `delivered_minute`，明确领取另存 `collection_action_id`；旧receipt继续使用 `delivered_day * 1440`。付款、来源和领取只恢复其原状态，不重放业务。

候选恢复仍要求真实人物、账户、地点、批次和资金责任成立；安装后保留原生玩家控制锁。`safe_boundary` 排队保存继续等待完整正式时间推进结束。没有迁移真实玩家存档。


旅行和接管的续接字段保持现有 schema。旅客路线可选 public_notice；已接受旅行行动可选 completion，记录真实完成阶段与到达分钟。初始行动结果保持不变，重复行动不再次收费或旅行。当前行程与完成记录须引用同一原始路线。

旅行付款批次 travel:<action_id> 由原生行动和旅行状态共同验证。旧存档没有旅行字段且没有相关责任时继续按旧模式读取；存在旅行付款或已接受旅行行动时，不能丢弃其旅行状态。扩容的 subject_activation 必须有 APPLIED 请求与原接受行动作为来源；新主体的订单及劳动不能早于生效时间。route_knowledge 作为申请内容保存；实际取得的路线知识保存在原配置及旅客路线中。

job_posting 的 local_notice 来源保存 place_id 和 observed_minute，表示人物在实际地点读取已发布岗位。恢复这些收据只还原知识，不重新观察、申请或工作。旧远程岗位消息保持原有日级送达语义。


## 个人寄存、货运与分批领取

正式 v15、个人 v3、原生 R2 schema 继续使用现有候选恢复入口。人物当前 place 与常住人口 unit 分别校验；合法跨单元旅行不要求二者相等。原生责任仍按常住 unit 排除宏观消费，不在目的地重复排除人口。

个人 native_lots 可含 positions 分配。新增 native_custody 生活记录保存原批次 allocations、来源行动或运输订单/receipt、from_key、to_key、数量、活动地点及实际分钟；候选恢复按原来源和消费记录重建分配，再检查所有权总量、货运占用和每次行动唯一性。新消费记录保存 activity_place_id / present，用于重建当前位置可用 FIFO。旧 v2/v3 批次没有 positions 时保留原随身持有语义，不补造寄存或历史货运。

PERSONAL_FREIGHT 使用原 orders / shipments / delivery_receipts / Ledger reservations。其额外 custody_fact、source_custody_site、destination_custody_site 绑定物主、实际保管地点和原 FIFO 分配。订单的 pending / transit / delivered / cancelled 保留原数量守恒；个人所有权不会因为寄运再次增加。加载检查尚未领取的货运占用等于原订单未结数量，不再次发运、付款或领取。

部分领取 receipt 可带原 shipment_id，ID 为 shipment:N:part:累计领取量。剩余 shipment 沿用原 ID 和路线；同一原批次的剩余数量与各次已领取量共同还原运输边容量。collection_action_id、custody_mode、custody_place_id、实际分钟和原付款批次分别保存。旧整批 receipt 保持原 ID 与完成状态；旧记录不重新拆分执行。

personal_storage 许可及承运路线公告可由既有 expand_scope 在正式经济边界追加。缺少该字段的旧世界不会自动增加寄存服务或初始化物资。正式 Ledger、经济 v6、旧市场收款余额、控制锁和 safe_boundary 的语义不变。


### 常住迁居、单位交接与有限退出

顶层仍使用既有 v15 候选恢复。Population v1 可选 `residence_requests` 保存行动、原单元、目标单元、目标地点、请求/边界/生效时间、许可和延后原因。可选 `place_population_bindings` 保存显式开发地点统计绑定；静态单位映射及迁居许可保留在已保存的原生配置。无字段的旧快照按旧常住归属解释，不从当前物理位置推测迁居。

原生快照可选兼容读取 `property_handovers`。每项交接引用实际接管请求、旧购买FIFO分配、旧毫单位数量、精确新数量、商品映射及地点。个人 v3 同时保存 `legacy_handover` 和 `native_handover` 来源。旧持有减少但不记为消费；原生来源按寄存批次恢复。候选恢复检查原单元历史、行动依据、单位、批次及物资责任，不执行人口转移或物资发放。旧 v2/v3、经济v6、Ledger交易含义不重新计算。

已生效个人退出保存在既有 `scope_requests` 中。主体及其历史仍保留，未来需要统计截至退出边界。原账户不重建，旧宏观从未来边界继续承担常住消费。候选恢复仍保留控制锁、safe_boundary及失败不替换当前世界。

### 当前原生领域状态

`economy_native` 继续保存原配置、行动、订单、shipment、工资、需要及历史来源。多次接管、退出与 REENTER 的有效区间由 `scope_requests` 推导；重新接入不清除过去退出，也不补算退出期间的原生需要。`enterprise_changes`、`employment_ends` 保存管理者、地点及劳动关系的边界变化。

`stock_lots` 保存 sources、portions、losses 和 next_id。真实余量、所有权、保管位置及预留份额只从这些来源恢复；`stock` 是兼容数量投影，不是第二份可写库存。个人 `native_lots` 保留来源和保管描述，不另发一份消费余额。旧数量库存的兼容读取不补造生产日期、货龄或成本。

`procurement_budget` 保存 claims 与 settlements。原窗口和根授权引用留在配置及合同来源中；履行转支出，确认解除只释放未履行部分。恢复不刷新额度，退款不默认恢复授权额度。`cargo_fulfilment` 保存损失、各方处置确认、补运关联、退款/赔付和消息。物理损失不自动消灭原合同、付款或预算责任。

`capital_formation` 保存项目、实际已耗材料与工时、安装资产和状态变化。`shared_transport` 保存 handling、entries、node_uses，并与 Spatial 的已采用资源及真实释放边界交叉校验。人物旅行继续独立保存座位、票款、实际阶段及可选共同资源引用。加载不重建机器、不重复施工、付款、发运、领取或取得已使用容量。

分层cohort的人数、职业、劳动资格和需求结构保留在原配置；实际岗位份额、工时、工资及生活结果仍在既有业务状态中。信用、换汇及企业份额各恢复其原合同和资金引用。账户余额、贷款本金与企业收付分类不重新解释为利润。

正式候选沿原 WorldBootstrap 构造宿主，再恢复 Organization、Ledger、Population、原生领域及人物旅行。配置中的 `development_organizations` 只描述明确的开发公司来源；已保存的组织身份和任命从组织状态恢复，不在加载时重新登记或发资源。派生的订单、收据、供应目录、路线、到期责任、活动项目和产能索引从权威记录重建，不另建缓存存档。

缺少可选字段时沿各模块既有兼容分支读取。坏引用或时间、数量、权限来源不一致时拒绝候选；不替换活世界。未记录的历史损失、迁居、预算或共同资源安排不按当前位置及当前政策推测补造。默认旧经济入口及个人v2/v3、经济v6、Ledger历史语义保留。自然损耗率、全国接管、完整银行和军事Task6没有因这些字段而自动启用。

### 企业资金压力增量

可选 liquidity_policies、labor_response_policies、firm_finance_authorities 属于原生配置。没有字段时不推测历史策略或授予金融权限。经营和劳动决定沿原 commands、enterprise_changes、employment_ends、capital_formation.changes 保存，生效边界不改变。欠薪、贷款及物资仍由原业务状态恢复。

企业金融动作保留 financial_authorization，包含实际控制者、企业、组织、操作、币种、金额、时间及原许可；可选借款限额和组织根授权证明也保留。finance_firm / finance_investment 的 delegated_by 与实际企业信用命令双向核对；内部动作ID不代替权限。恢复对照合同币种、实际金额及许可引用。后续明确授权不反向改写其生效前的旧债务。

50日开发场景在第25日恢复真实未结订单、工资、逾期贷款及共享节点状态后继续推进。短行动检查另覆盖实际部分还款和授权金额不一致的拒绝。加载未放款、发工资、重新进入容量或补发初始资源。缺少新权限的未来行为会被拒绝，既有债务不会因此删除。

### 前向成本归集

原生 snapshot 增加可选 cost_allocation（economy_cost_allocation_v1），保存 start_minute、成本依据 bases、份额绑定 bindings、实际生产归集 productions、已履约成本分配 sales、资本材料 capital_materials、损失分配 loss_allocations 和工时 work_allocations。它们只引用原物资份额、交付、工资、工时、资本及损失记录，不恢复另一份数量或资金。按地点/日期、项目/企业、当期活动的查询索引及排序缓存不进存档。

原 R1 restore 在物资、工资、订单、收据与资本恢复后读取成本分配；FormalPersistence 仍构造独立候选。核对币种、数量区间、所有者、商品、真实来源、工时用途、订单锁价、分摊权重及实际依据金额。累计尾差依靠原分配区间延续，不重新支付、生产、消费、安装或记一次工资成本。坏引用拒绝，不替换活世界。

缺少成本字段时，明确从加载边界开始，原有物资全部保留未知成本；不推测旧货龄、采购价、运费或历史生产工资分配。旧配置没有 cost_accounting 时仍关闭此机制。旧实际债务、已付工资、贷款、股份和个人持有保留。局部第6日和期末候选恢复、缺字段边界及坏成本依据引用拒绝已经运行。

成本生命周期沿用 economy_cost_allocation_v1，不增加顶层存档或重复的运输/应付记录。退款、赔付、补运费用和确认状态从 cargo_fulfilment 与原 Ledger 读取；装卸使用原 shared_transport.handling 和工资分配；设备维护使用原资本项目。主体/日期处置、开放责任、维护和装卸查询索引只在采用或恢复时更新。

恢复拒绝同一份额上的销售、生产、资本耗材和损失成本区间重叠，也拒绝成本边界之后缺失损失分配。旧档的已发生物损、维护材料和工时缺少成本记录时保留未知，不以当前价格补算。12日场景在未结退款及期末恢复后继续，18日设备维护和退役状态恢复成功；重复处置不重复付款、占用预算或计成本。缺失损失引用的候选被拒绝且活世界保留。显式组织参考目录的开发世界继续通过原 FormalPersistence 的 explicit_reference_injection 恢复，不省略组织校验。

### 原生商业服务状态

原生快照可选 `service_market`，格式 `economy_service_market_v1`，保存 `contracts` 与有序 `changes`。合同包含原行动、实际主体、独立采购与供应权限、原报价、仓储对象或原资本资产、锁定费用、开始/结束边界、履行期间、材料份额、工作引用、实际付款、释放金额及暂停状态。资金仍只在 Ledger；商品仍只在 StockLots；设备仍只在 CapitalFormation。

仓储的 `SERVICE|合同ID` 位置和等待入库的 `reserved_for` 必须引用实际服务合同，所有者为原委托企业，保管者为实际服务经营地点。恢复同时核对来源、实际余量、入库/取回/损失事件及历史容量，拒绝坏引用。维修材料与工时须匹配原耗用和工资，设备维护事件须引用同一外修合同。`service_fee` 的原子批次、预留释放和预算支出逐一引用 Ledger 原收据；跨窗口继续使用接受时的原预算窗口。服务材料成本分配进入已有 `cost_allocation.service_materials`，劳动分配的 `SERVICE` 引用绑定真实工时，不另存成本钱包。

服务与货运共用设施时，恢复检查双方采用边界的历史占用；活跃合同、岗位工时、设施占用、主体/日期和付款查询索引由原事实重建，不保存第二份容量。CargoFulfilment 的既有损失/通知可引用 `service_id`，恢复保留实际送达时间；未确定的赔付不补造。

FormalPersistence 沿原候选流程调用原生恢复。加载不重新接受、入库、耗材、计薪、修复或付款。旧快照没有服务状态时保持空合同；旧成本未知仍未知。失败候选不替换活世界，safe_boundary 与玩家控制锁保持。已进行活跃仓储、维修中途、完工、仓储损失及待送达通知的局部候选恢复；没有扩展为完整恢复矩阵。


### 居民服务扩展

沿用`economy_service_market_v1`，DINING/HAIRCUT合同增加`resident`：实际fulfilled份额、带原行动及成员区间的bookings、带稳定序号的receipts。回执保存真实时刻、实际份数、材料份额、原work切片、需要及有效窗口、目标新增满足。客户账户仍在Ledger，原材料仍只由StockLots耗用，员工工时与欠薪仍在原劳动记录。原企业合同不含resident；恢复拒绝混用。

food需要行可选`service_satisfied`。恢复由回执重建食品日期索引及理发成员区间并核对需要总量，不能将实物耗用再算一份餐饮满足。恢复核对原预约、重约、取消行动，提供者独立授权、设施历史容量、成员区间、实际工资工时、材料耗用及原service_fee付款。人物旅行恢复后继续核对现场地点和劳动冲突。序号缺口、超额履约、重复目标或坏来源拒绝候选。活动预约、日期与已知目标索引从合同重建，不重新扣料、计薪、付款或满足需要。

旧档没有resident合同和服务目标时不生成历史消费。旧需要行没有service_satisfied时按0解释；旧来源成本仍未知。读取不初始化新资源，不刷新合同现金或消费窗口。日级预约不迁移成分钟级服务安排。

### 租赁使用权与持续租金

原生快照增加可选`lease_market`，格式`economy_lease_market_v1`。标的、权利来源、报价、独立授权和开发政策保留在原config；合同保存原行动、承租/出租主体、标的、成员份额、站点、锁价、首期预留、交付/结束/交还边界、期间事实、应付/已付/释放和原Ledger付款引用。稳定`lease_rent`付款批次由Ledger保存，预算以LEASE责任引用原窗口；不保存第二份余额或不动产。

恢复核对原已接受行动、当时管理权限与可选正式根授权、真实双方同币账户、合同期限、累计整数租金、付款批次与预留释放。按接受、结束、交还边界检查空间与cohort成员区间不得重叠。期间、支付、主体/日期、活动与站点使用索引从原合同重建。日内快照只要求此前完整日界已结，不提前形成当天租金。人物旅行恢复后再次核对住房交付、交还及住房满足的实际地点；共享运输与居民/租赁宿主引用失败统一返回Native host-reference validation错误，失败候选不替换活世界。

到期且未交还的实际占用、已归还但欠租的付款责任都必须保留。读档不重新签约、交付、移动人口、取得空间、计租或付款，不生成房屋/设备。旧档没有租赁字段时保留无租约语义，不补造历史产权、欠租或住房满足。未配置租赁的原生范围与旧统计经济保持原行为。已运行活动租约、到期占用/欠租、提前交还与新合同、日内边界候选续接；坏期间金额候选被拒绝。未验证完整司法腾退、共享仓储空间、押金或预付租金迁移。

### 建设资产与租赁供给的引用

沿用economy_capital_formation_v1和economy_lease_market_v1。建筑项目复用原材料份额、施工工时、工资、订单、状态、资产和资本事件。building模板在原config保存建设许可、唯一开发空间、产权企业、目标单位、租赁对象与报价；实际项目增加construction_authority，建筑恢复核对原invest行动、独立控制人、有效期和可选正式根授权。恢复重建建设份额的已承诺索引，拒绝同一许可/空间重复建设。建筑项目继续/恢复的新增授权引用留在原资本控制记录，不另建施工存档。

新建筑的LeaseMarket对象与报价由模板投影，实际资产关联在CapitalFormation恢复后重建。不另存建筑数量、租赁容量余额或初始成本。实际建筑必须对应同一已完成项目、产权、地点、容量、材料、完整工时和工期；住宅/商业空间不得进入工业产能池。租约接受、期间可用性及历史占用继续核对原资产事件。资产暂停或退役后，恢复不能重新提供可出租能力，也不能删除原租约、欠租或占用。

lease_market可选offer_changes保存报价暂停/恢复行动、原出租授权和时刻。当前报价状态、按报价历史索引、建设份额及建筑对象引用只在采用或候选恢复时重建。报价变化不重放租约付款或改变旧锁价。旧档没有building或offer_changes时保持原设备、开发授予标的与默认报价语义；不补造过去建设、地籍、折旧或成本。

本轮在建、出租中途、实际交还、退役及日内候选续接已运行。擅改建筑capacity被原资产能力校验拒绝，活世界保持。没有迁移真实玩家存档，没有省略人口、地图、Ledger或组织构造来制造恢复成功。


### 门店营业事实与现场销售

原生可选retail字段为economy_retail_rules_v1，仅保存windows：稳定窗口ID、站点、日期、时刻和原work_records中的营业工时分配。原成本work_allocations支持RETAIL用途，并与每个营业工时相互核对。真实工资仍在原工资债权中；后续支付不再次形成营业成本。已采用营业量由原现场交付回执重建，不保存可自行刷新的容量余额。

现场成交仍是原SALE订单，route_id为onsite加站点ID，route_legs和departures为空，不生成货运进入事实。原delivery_receipts、goods付款、个人来源和批次谱系共同保存实际交付。恢复校验同地点、有效场地、真实工资工作、营业时间及累计采用数量；CostAllocation允许该订单原SITE保留份额作为取得来源，其他运输仍要求原CARGO来源。候选重建经营开停历史，之后暂停不撤销过去合法成交。

旧配置无retail_sites时无零售事实，不补造历史门店。原生产企业直接销售、仓储、服务、租约与建筑来源保持原格式。第12日真实在途采购、第18日已有销售且暂停、第23日租约结束后均恢复并继续推进；营业工时被篡改的候选拒绝，活世界保留。


### 商业公告、原消息与付费发布

原生可选commercial_information字段采用economy_commercial_information_v1，只保存publications。每条包含原行动、合法企业/站点、GOODS或SERVICE、渠道、发布/有效/撤下时刻、发布时观察报价、原商品来源引用或服务offer_id，以及原服务合同ID。自有公告保存实际营业工作引用。没有第二套消息队列、商品库存或可修改的知情总额。

ANNOUNCEMENT沿原service_market合同保存资金承诺、独立购买/供应授权、实际工时、发布履约期间、已履行金额和原Ledger付款。公告只引用该合同。待投递和已送达消息仍在原messages/receipts，以稳定公告+接收者ID去重，记录接触时间、来源、渠道及日级投递时间。恢复重建活动公告、有限受众采用、服务知情、冷却和发行次数；不发新消息、不收费、不生成订单。政策开停由原已接受控制行动重建。

候选校验公告与原行动、报价/库存来源、实际营业/发布工作、原服务付款、合法历史场地和人物到场相互引用，拒绝提前投递、重复受众或越过渠道容量。原订单、工资、预算、租约和批次责任继续由原组件验证。旧档缺少公告字段时不补造历史消息或私人报价知识；缺少公告的已接受发布行动/发布合同不能冒充完整恢复。

本轮第8/14/16/18日正式候选恢复续接，快照一致；提前商业消息投递时间的候选拒绝且活世界保持。策略暂停和公告撤下经原控制行动恢复，第8日继续推进。日结自动现场成交与随后同分钟采用的关店状态按原自动行动身份区分；未放宽真实租期、位置、资金和库存校验。


### 原生动态劳动状态（显式启用）

原economy_native可选labor_market，格式economy_labor_market_v1，保存quotes、amendments、reviews、observations。quotes保存稳定版本、锁定未来名额/时薪、请求与生效边界、期限、状态和独立用工授权的请求/采用凭据。amendments保存原合同、经理提议、劳动者接受行动、未来边界和实际采用状态。reviews和observations仅保存受限策略时点与有限观察窗口，不保存第二份工资或现金总额。

原contracts接受动态条件时增加terms与employment_action_id；原commands的接受结果保存该次完整合同。terms包含报价ID、版本、时薪、工时、币种、工资延迟和接受/生效分钟。work_records引用employment_action_id；工资仍由原wages和Ledger保存。原employment_ends可增加job_id/workers，表示所选岗位的尾部份额释放，历史合同及未付工资不删除。已完成离职和报价索引从原状态重建；日常调度不扫描全部已结束招聘历史。

招聘消息使用原messages/receipts，source=labor_market，保存报价/岗位版本、雇主、站点、技能、时薪、币种、名额、接触和送达边界。恢复校验原报价、实际同地接触和送达，未送达消息不进入已知岗位；不重复发送。公开岗位投影须等于已采用报价，现有合同须等于原接受条款及实际变更/离职结果。恢复检查历史人份不重叠、岗位名额、原请求与采用授权、工资金额/工时/到期日和候选时间。

旧配置没有labor_market时，仍使用原固定岗位和合同。不补造历史工资变化、招聘消息或过去合同。候选恢复不执行录用、支付、劳动、条款采用或补发资源；失败继续保留活世界。住房、租金、服务、商品、贷款和预算的既有保存语义不变。


## 自愿经营收尾（显式启用）

`economy_native.config.wind_down` 保存有限开发授权与可选偿付顺序。没有独立收尾存档或可修改债务总额。`enterprise_changes.permission` 保存请求与生效授权；`before_boundary` 区分日结先于经营变更采用时的原控制者。`commands` 中的 `pay_enterprise_debt` 及适用的原 `pay_lease` 结果保存原债权、金额、授权与 Ledger 收据引用。原工资、贷款、租赁、批次、服务、货损与资本状态继续是各自权威。

候选验证请求、生效时点、当时管理者、原授权、债权到期及真实付款；拒绝同一收据的重复采用。自动偿付当日额度从 Ledger 索引重建。恢复不重卖库存、不重付工资或租金、不重聘员工、不取消债务、不释放未交还场地。没有 `wind_down` 配置的旧档保持原经营状态语义；不补造清算、历史产权或未知库存成本。


### 可移动资本设备

`economy_native.capital_formation` 保留 v1 形成事实，按需增加 `resale.offers/trades`。拆卸、交接、重装保存在原 `projects`，含 `mobility_authority/trade_id`、材料采用/各次工时/完工时点的实际执行授权、实际耗材来源、工时与原行动。原资产的建设企业、地点和项目必须继续严格对应原完工记录；当前产权和安装站点从后续交易与原设备事件重建。旧档没有这些事实时保持原归属。

恢复核对报价、双边联系、独立权限、锁价与期限、Ledger原预留及付款批次、累计预算、真实项目耗材工时、技能、唯一产权保管链及停止/恢复产能事件。已接受行动不能丢失对应项目或合同。同一设备不能被两个未结交易处分，也不能在两站同时生效。付款、交接、重装与工资不在加载时重放。坏候选仍由 FormalPersistence 拒绝，不能替换活世界。跨地点设备运输在可选 economy_native.capital_transport 中保存原资产/交易引用、实际路线、阶段、付款和工时引用，并严格核对原 shared_transport 与 Spatial 采用；不补造旧运输记录。


### 自主资本报价的送达来源

格式仍为 formal_world_simulation_v15 / exact_variant_v1。可选 capital_resale.autonomous_policies 存在原 config 内。该配置的 resale.offers 增加 equipment（稳定类型、报价容量、目标活动），必须等于原资产和明确活动映射。原 messages/receipts 增加 capital_offer，使用现有六字段定向消息，candidate引用原报价；恢复核对唯一消息、原双边联系、发布日、配置延迟及实际送达。接受时点不得早于原收据。缺失或重复消息、伪造声明或提前取得均拒绝。

NPC已执行行为仍保存在原commands、资本项目、交易、运输任务和预算中；购买结果的decision仅为当次经营判断说明。当前报价索引从收据重建；生产比较和最近未购买原因只是当日查询投影，不构成第二份产能或待执行命令。恢复和UI读取不触发策略。旧字段缺失不推断NPC曾交易。装卸、付款、重装及维护继续核对原事实，加载不重放。


### 定向资本竞争的兼容扩展

外层仍为 formal_world_simulation_v15 / formal_world_exact_variant_v1。可选竞争规则仅位于 economy_native.config.capital_resale.competition。启用后，npc_policies、autonomous_policies按卖方/买方对验证；同一买方的经营判断参数必须一致。每个原 resale.offer 仍只有一个明确买方；同资产可有多份合法定向报价，不能把不同收件人的消息误判为重复。每份报价须恰有一条原定向消息或已收凭据，收件者、报价、来源联系及延迟分别核对。

排他责任仍只由原 resale.trades 表达，不保存另一份市场锁。除原未结交易唯一性外，恢复核对同资产全部接受至交割或合法取消的责任区间不重叠。原成功接受行动丢失合同、收据换人、伪造第二个已接受合同、预算或Ledger引用不符均拒绝；失败竞争行动保留在commands，不产生预算承诺。报价到期不终止已接受责任。

各NPC接受尝试继续使用原commands/result/decision，比较说明只引用自己实际获知的报价和自身观察。decision.purchase仅表示购买意图，实际成交仍由result.accepted及原交易决定。日常当前排名、可用性、意图和最近原因从原状态派生；加载不重试失败购买，不重放资金或施工。原单买方/单报价档不补造竞争规则、收件人或历史选择。

连续转售仍在原capital_formation.resale.offers/trades及projects、asset.events中保存历次事实。原形成字段不更新；当前产权、最近安装时刻和本次取得的重装义务从历史派生，不增加保存字段。恢复按时序核对每份报价的当前产权、拆卸地点与排他责任，再核对交易、交接和后续重装；原建设者的旧身份不能授权后续报价。各次capital_transport任务保留各自交易、SharedTransport采用、装卸和付款引用。删除早期交割、伪造原形成主体或复制后续合同均不得形成合法候选。只有一次交易的旧档沿原历史恢复，不补造第二次转售。

玩家资本行动仍保存为原R1 commands/envelope/result、资本项目和交易，actor为当前具名人物。分项根授权、成员与任职继续保存在原Organization快照；资本采用证明引用实际acting_context、任职和根授权。新增可选config.capital_resale.authority_places只在显式玩家资本及联合经营开发配置中有效，必须等于其受授权企业的实际主要经营地点。新建和隔离候选恢复均先验证原生配置及正式Spatial地点，再绑定同一Organization引用目录；加载不重建根授权，不补发资金或执行动作。旧配置缺失该字段时保留原引用范围。界面选择、翻页、报价估算和按钮资格均为派生显示，不新增保存字段；正式v15与exact variant容器不变。

algorithm-workbench的feedback frame与A/B观察文件是外部只读投影，不是正式存档或可恢复的第二份世界。其隔离`.var`检查点保存原v15精确Variant快照，恢复仍必须通过FormalPersistence.restore_candidate；不经过JSON数值回写。正式用户文件、exact variant外层及领域保存字段均不变。第21日重放检查点须标记为历史等价重建，不当作图形进程的内存抓取；也不得用60日期末覆盖待验收图形世界。

恢复待结工时时，居民服务的人份冲突检查使用已经验证的保存劳动合同及labor_start，不读取尚未安装的运行合同。合法的第10、11人份工作不与第0人份用餐混淆；劳动份额重叠仍拒绝。此修复不新增保存字段。

联合经营配置`FORMAL_ECONOMY_FEEDBACK_DEVELOPMENT`沿用上述玩家资本授权地点校验，并保存于原economy_native.config。招聘报价和原条件劳动合同使用已有labor_market、commands、receipts、contracts、work_records及wages；商品、资本、成本和运输仍使用各自现有嵌套事实。联合配置不新增顶层schema、结果账本或反事实分支字段。旧档缺少该配置时不补造招聘、资本行动或居民购买。


局部报价实验保留 formal_world_simulation_v15 / formal_world_exact_variant_v1。仅显式 config.local_quotation_experiment 启用可选 economy_native.local_quotations，格式 LOCAL_QUOTATIONS_EXPERIMENT_V1，保存不可变 quotes。每份条款含站点、商品、连续版本、价格、原行动ID、发布分钟、生效日及到期日；当前报价从历史推导，不另存成交量或现金。初始版本必须等于原开局站点价格。后续版本须逐一匹配原 post_goods_quote 成功命令、企业销售委托、结果、时间及原payload。

定向 goods_quote 信息沿原 messages/receipts 保存并引用 source_receipt；恢复检查实际收件者、已知供应联系、消息延迟及发布时刻。实验SALE须匹配接受时有效且已送达的版本、原购买行动引用及锁价；后续价格不追改合同。伪造报价、移除发布行动、篡改收件者或锁价不得形成合法候选。旧档没有实验配置时不推断曾发生调价，不补造报价或历史收件。恢复、快照及只读查询不发布新报价、不重复成交。

沙盒的 world_id、请求步长、回看位置、待展示事件和检查点选择不是正式经济字段。隔离恢复成功后重建显示游标并标注“恢复的历史观察”，不把重新显示记录当作重新付款。当前地图工作线对未细化开局的首次候选恢复会正规化土地拓扑及控制者；经济适配分别报告完整快照与原生经济/Ledger相等结果，不隐藏差异，也不修改地图迁移以使经济检查通过。


有限股份实验保留v15及exact Variant容器。显式config.equity_call_market启用原economy_native.assets内可选call_market，格式EQUITY_CALL_EXPERIMENT_V1。原assets、orders、trades继续保存唯一股份、卖单及交割；可选结构只保存预留买单、有限发行人报告、每日撮合采用边界与next_bid。买单记录原行动、账户、数量、限价、余量、已付、到期及关闭依据。已成交trade增加bid_id，实际现金及买单预留只由Ledger保存，不存另一份可用资金。

候选先校验配置中的初始分配及股份总量，再从原命令顺序恢复各次锁定、取消、到期及交割。撮合边界记录原GameClock分钟、命令采用游标及真实trade_ids，以区分同分钟撮合前后的新委托。恢复检查价格时间优先、实际对手、部分成交余量、累计付款、Ledger原子批次及释放金额、持有人和当前锁定量；报告须等于原交付与工资来源，收件人与发送延迟必须一致。校验不调用付款、撮合或NPC策略。旧档缺少配置时不补造股份、报告、买单或过去成交；原双边股份接口保留。界面表单与图表不是存档权威。


一级融资保持 formal_world_simulation_v15 与 formal_world_exact_variant_v1。仅 config.equity_primary 启用 economy_native.assets.primary（EQUITY_PRIMARY_EXPERIMENT_V1），记录 issues、subscriptions、settlements。方案保留原项目、固定条款、公告与关闭时间、独立组织授权、原行动和认购引用；认购记录投资者、实际账户、数量、预留或配售/释放状态；结算引用原原子付款批次。没有第二份股份或现金余额。

候选按原R1采用顺序，从初始股份、已完成发行与各次二级成交共同重建现持有人和发行总量。校验实际项目、历史授权、定向送达、认购上限和唯一性、最低生效量、每日撮合采用游标、Ledger付款双方/金额/批次释放，以及当前未结现金预留。取消方案的独立授权也保留。缺少付款批次、提前配售、错误来源、重复结算或股份总量不符均拒绝。读取不执行认购、付款、NPC决策或建设。未启用发行的旧配置不增加字段，也不补造募集历史。


有限现金分配保持 formal_world_simulation_v15 / formal_world_exact_variant_v1。仅 config.equity_distribution 启用可选 economy_native.assets.distributions（SHAREHOLDER_CASH_DISTRIBUTION_V1）。plans保存原决定、独立授权证明、登记分钟与原命令/Ledger游标、已发行总量、每份金额、冻结持有人/收款账户/应收、保护来源、到期分钟、原预留及原子付款引用。冻结名册是本次应收依据，不是第二份可写股份登记。未启用的旧档不增加字段或补造历史分配。

恢复按原命令顺序，从初始股份、一级配售及二级交割重建登记时的真实持有人，再核对冻结应收；登记及付款须位于原每日撮合边界之后。历史现金保护从原Ledger收支前缀及订单、工资、信用、资本项目责任复核。待付方案必须精确对应原现金预留；已付方案必须匹配原执行行动、全部收款账户/金额、实际批次与释放量。错误总量、持有人、账户、币种、登记时刻、保护额、缺失批次、付款换人或重复采用均不得形成合法候选。恢复与只读查询不预留或付款，后续股份转让不重新指定旧分配收款人。


跨业务保护仍使用 SHAREHOLDER_CASH_DISTRIBUTION_V1 和原v15/exact Variant容器。新决定的 protection.basis 为 CROSS_BUSINESS_CASH_PROTECTION_V1。其来源行只保存采用时的脱离式核对依据：原合同/行动、币种、发生/到期/付款/释放金额、原现金预留及未覆盖部分、明确未来保护、阶段与原Ledger收据ID。reservation_sources是核对依据，不是新的可写现金余额。未知责任明确保存来源和未知值，不把未知填为0。

恢复从原命令前缀及Ledger游标重建决定时刻的采购取消、服务期间、租赁期间、设备交割、承运、工资、信用及已确认货损付款，不使用当前合同状态覆盖过去。登记后结束租约不改变原保护证明。缺失取消/释放来源、合同金额或期间被改、承运费用被改、保护引用被换、原付款批次错误等均拒绝。旧计划没有此basis时仍按原有限保护算法复核，不改写其历史决定。当前合同阶段注释只属于脱离视图，不进入已采用证明。恢复、查询和历史回看不执行付款、释放或合同。

Latest-source recovery also accepted the final browser day37 payment candidate and the original30360-minute graphical continuation. Complete-state equality, original-action replay and the tested1440 versus60+600+60+720 minute split passed for the stabilized browser payment candidate. Restoring the graphical continuation does not execute or validate its pending UI actions.

### NPC企业金融观察（2026-10-17）

保留v15、exact Variant及原PRIMARY/CALL/DISTRIBUTION/CROSS_BUSINESS格式。可选 `config.corporate_decisions` 只声明企业、正式NPC控制者、策略开关、周期及管理偏好。旧档缺失时不补造控制者、权限或金融决定。

已采用评估保存在原R1 commands的 `review_corporate_finance` 结果，引用原命令/Ledger游标、历史授权、项目及跨业务保护来源。后续原发行/分配行动的decision引用该评估。恢复从原历史前缀重建观察，核对当时控制人、权限证明、额度、来源和后续业务一致性；不以当前现金或授权失效改写过去。派生recent-review索引在恢复时重建，不写入快照。没有第二份股份、现金或融资历史。

新开发NPC来自原Population背景份额，已有正式人物/组织记录。显式 `ZERO_CASH_DEVELOPMENT_CORPORATE_MANAGER` 标记只允许原PersonalEconomy建立零初资账户；恢复核对该人物及组织引用，不复制玩家初资。未带标记的旧人口和账户规则不变。

已验证发行公告、认购预留、实际配售、分配预留/付款及后续经营候选；授权撤销不重放已采用决定。错actor、伪造现金观察、错代表、超额度、删除原评估及错Ledger引用被拒绝，活世界保持。原行动重放不重新结算，同ID改参数拒绝。实际未决货损仍阻止分配，删除损失来源候选被拒绝。

初始未细化地图的首次恢复仍有既有Spatial正规化差异。本轮同起点对照使用首次评估前的稳定第2日完整候选，仅关闭两个显式策略开关；完整状态比较排除这两个开关后相同。跨第8日配售、第38日付款的1440与60+600+60+720分钟切分相同。查询、研究视图切换及恢复不评估或执行金融行动。
