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
