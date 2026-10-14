# 正式个人经济实现移交

项目：WWO。记录日期：2026-10-11。

范围：此前加入正式世界的购买、持有、消费、每日安排及关联账务、界面和存档。本文依据源码，不代表运行结果。此次仅阅读经济实现，没有修改、删除、试跑或测试经济代码。保留或替换由独立经济算法工作线决定。

## 实际调用关系

```text
EconomyPage / PersonView → MainShell.action_requested
  → FormalWorldApplication._on_action_requested
  → FormalPersonalEconomyState.purchase / consume / set_daily_consumption

purchase → purchase_quote → FormalWorldEconomyState.personal_purchase_quote
  → purchase_from_existing_stock → FormalLedgerState.transfer
  → 市场库存扣减 → 个人 holding/lot 增加 → living_record 追加

GameClock 时间推进 → SimulationStep.advance_minutes
  → 原 Spatial / FormalWorldEconomySimulation 结算
  → 原组织日结观察 → settle_due_wages → settle_due_consumption

FormalWorldPresenter.refresh_ui → 有关人物、账户、商品、记录和报价
  → 原页面刷新；Application 将本人结果写入右下反馈

FormalPersistence → Ledger 恢复 → Economy 恢复 → PersonalEconomy 恢复
```

UI 不直接修改余额或库存。动作处理使用实际玩家 ID；领域购买和消费接受任意已存在人物 ID，并非仅支持玩家。正式初始化仍沿用原开局资金和工资安排。

## 已写入源码的行为

| 行为 | 状态后果 | 条件和边界 |
| --- | --- | --- |
| 手动购买 | 买方个人账户减少，市场收款账户增加；同一市场的 `inventory` 减少；持有量和购入批次增加；追加购买记录和账务交易 | 存在人物且存活、所在地映射一致、有效库存/价格、现金足够、数量和金额在整数范围内。提交时重新报价，UI 旧单价改变则拒绝 |
| 手动消费 | 个人持有量减少，累计已消费量增加，FIFO 批次扣减；追加含购入批次分配的消费记录 | 仅四类商品支持消费；不足即失败。手动消费不自动购买、不改变市场库存或现金、不推进时间 |
| 设置/停止每日安排 | 每人物、每商品保存一个安排；追加设置/取消记录 | 必须已有该商品持有记录。首次到期为设置时间加 1440 分钟；固定周期 1440 分钟，缺量自动补购开启 |
| 到期安排 | 优先使用持有量，缺量按当时价格购买差额，再消费安排数量 | 失败追加原因，保留现有物品，下一次到期仍加 1440 分钟；无赊账或凭空补货。到期读取原 GameClock |
| 工资 | 原雇主储备账户向个人账户转账 | 原结算函数处理，页面刷新不发薪。现有政策为开局现金 2500、每 7 天工资 1000、雇主初始储备 12000，均为模拟假设 |

购买允许**所有有单位且不是 `local_service` 的商品**，包括尚不支持消费的工业商品。消费类别限定为 `agricultural_food`、`processed_food`、`colonial_consumable`、`household_consumable`。没有饥饿、健康、幸福收益或物品转赠、转卖路径。账务转账用于开局拨款、雇主储备、工资、购买；没有新增任意人物转账 UI。

购买、消费和安排都有领域→Application→页面的执行路径，不只是按钮或结构。尚未确认的是实际 Godot 加载、操作画面、交易执行和读档效果。此次没有运行应用。

## 状态与函数位置

以下位置以文件和函数定位；行号用于查找本次读取的实现。

| 组件 | 位置与职责 |
| --- | --- |
| [FormalWorldEconomyState](../../scripts/world/formal_world_economy_state.gd) | `bind_personal_ledger` :257；`commodity_for_person` :261；`personal_purchase_quote` :282；`purchase_from_existing_stock` :310。拥有原 `market_states[market_id].inventory/prices`，新增 `_personal_sale_accounts` 和对原 Ledger 的 `_personal_ledger` 引用 |
| [FormalPersonalEconomyState](../../scripts/world/formal_personal_economy_state.gd) | `purchase_quote` :145、`purchase` :155；`holding/holding_rows` :171/:181；`living_records/living_record` :193/:200；`consumption_quote/consume` :205/:215；`set_daily_consumption` :236；`settle_due_consumption` :258。拥有实际个人财产与生活记录 |
| [FormalLedgerState](../../scripts/world/formal_ledger_state.gd) | `open_account`、`transfer`、`transactions_for_account`。拥有现金账户和转账记录；新增角色 `market_receipts`、交易种类 `purchase`；`_transactions_by_account` 为原记录的派生索引 |
| [SimulationStep](../../scripts/simulation/simulation_step.gd) | `advance_minutes`。取下一个宏观日边界与个人安排到期分钟的较早者，推进原时钟；没有第二个时钟或独立队列 |
| [WorldBootstrap](../../scripts/content/world_bootstrap.gd) | 原经济初始化后，`economy_state.bind_personal_ledger(ledger_state)`、`personal_economy_state.bind_market(economy_state)`。原 `_configure_personal_economy_composition` 继续建立人物账户与有限工资来源 |
| [FormalPersistence](../../scripts/persistence/formal_persistence.gd) | 原正式文件保存、候选恢复路径；`ledger_state.restore` 在先，`economy_state.restore_persistent_state` 随后，最后 `personal_economy_state.restore`，以恢复收款关系后重建个人财产 |
| [FormalWorldApplication](../../scripts/formal/formal_world_application.gd) | `_on_action_requested` 的 `purchase`、`consume`、`consumption:daily`、`person:market` 分支；`_on_world_changed` 的本人收入/生活反馈；`_install_world` 初始化最近记录 ID，避免加载后重复宣布旧行为 |
| [FormalWorldPresenter](../../scripts/presentation/formal_world_presenter.gd) | `refresh_ui` 中按当前页面查询个人持有、记录、消费条件、安排和市场报价 |
| [MainShell](../../scripts/presentation/ui/main_shell.gd) | `quantity_input` 与数量输入处理、动作分派、持有/生活记录入口及返回上下文；共用一个 SpinBox |
| [PersonView](../../scripts/presentation/ui/person_view.gd) / [EconomyPage](../../scripts/presentation/ui/economy_view.gd) | 人物物品/生活记录/购买账务跳转；市场商品选择、数量、报价与购买。原统计概览仍存在 |

### 个人经济 v2

原有 `_person_accounts`、`_employers`、`_employments` 继续使用。新增：

- `_holdings[person_id][commodity_id]`：`commodity_id`、名称、单位、`quantity_milli`、`consumed_milli`、`lots`。
- 每个 lot：`purchase_record_id`、`market_id`、`remaining_milli`、`effective_minute`。
- `_living_records[person_id]`：有序生活记录。购买包含双方账户、人物、卖方市场、商品、数量、单价、金额、分钟与 `transaction_id`；消费包含 `allocations[{purchase_record_id,quantity_milli}]` 和来源；安排失败包含原因。
- `_arrangements[person_id][commodity_id]`：`quantity_milli`、`period_minutes`、`next_due_minute`、`auto_buy_missing`。
- `_next_record_sequence`：实际生活记录 ID 序列。`_living_by_id` 和 `_next_consumption_minute` 为派生索引，恢复时重建，不单独持久化。

`snapshot` :334 保存 v2 的九个字段：`schema_id`、原 `policy_fingerprint`、`person_accounts`、`employers`、`employments`、`holdings`、`living_records`、`arrangements`、`next_record_sequence`。`restore` :338 接受旧 v1 五字段，旧版财产、记录和安排为空。`_restore_living` :434 按购买和消费记录重建持有，并要求购买引用匹配 Ledger、市场收款关系和保存的持有量。消费后耗尽批次删除，但消费记录保留来源。

### 经济 v6 与账务

v6 新增持久字段 `personal_sale_accounts`，schema 名仍为 `formal_world_economy_state_v6`。`get_persistent_state` :503 / `restore_persistent_state` :523 保持原市场状态路径；旧 v6 缺字段时按空字典读取。

每个首次出售的市场新增零余额账户 `account:market_receipts:<market_id>`，所有者为市场 ID。出售关系记录 `market_id/account_id/inventory_owner_id/stock_scope/basis`，其中 `inventory_owner_id = market_id`、`stock_scope = existing_market_inventory`、`basis = GENERATED_SIMULATION_ASSUMPTION`。这是此次新增的模拟保管/卖方假设，不是从企业、商户或历史财产来源得出的所有权。

Ledger schema 仍为 v1。账户、转账仍保存在原 `accounts/transactions`；转账包含双方引用、整数金额、货币单位、分钟、类型、生活记录引用。商品详情存在个人记录，未塞入账务备注。正式存档仍为 `formal_world_simulation_v15`，原文件 `user://formal_world_1900.json`；新增内容嵌在原 `economy/personal_economy/ledger` 下，没有新存档服务。

## 与经济算法工作线的关系

| 议题 | 源码已确认 | 可能冲突 | 尚不确定 |
| --- | --- | --- | --- |
| 宏观与个人消费 | 原 [FormalWorldEconomySimulation](../../scripts/simulation/formal_world_economy_simulation.gd) `_settle_country` :183 使用 `current_population`，生产后从同一市场库存扣减人口需求。人口总数包含已命名人物，没有个人消费抵扣。个人购买扣市场一次；随后消费只扣个人持有 | 命名人物仍计入宏观需求，又额外购买，可能重复计算需求、额外抽取库存。不能描述为“手动消费把同一批商品再从市场扣一次” | 经济线应如何分离或归并命名人物需求；影响大小未测量 |
| 卖方及库存所有权 | 现有库存是真正可变的模拟库存，初始量由人口需求和产能公式生成；此次把市场当作库存保管/出售主体 | 国家统计池出售与企业、零售商拥有库存的模型可能不一致；所在地只需人口单元映射相同，没有距离、运输或商业渠道限制 | 未来正式卖方、库存批次归属、接近市场的条件 |
| 收款资金循环 | 出售不增发现金；从有限个人账户转入市场账户。新增路径只有收款，没有将市场账户支出接入生产、工资、采购或宏观贸易金储备 | 消费支出可能长期滞留。原 `gold_reserve_units/trade_balance_centimes` 与 Ledger 余额没有此次加入的结算联动 | 经济线是否认可这类账户；谁可使用收入以及如何回流 |
| 单位、价格、取整 | 数量为原商品单位的千分之一；库存为浮点数、个人数量为整数。应付 `(price * quantity_milli + 999) / 1000`，向上取整。模型分币数值直接当作原模拟货币最小单位。宏观运输金额使用 `round(units * price)` | 吨、千件、百头等宏观单位不等于零售包装；多次小额购买与一次合购金额可不同；浮点库存与整数财产、两种取整可能产生差异 | 正式计价币种、单位换算、包装、金额舍入与库存精度方案 |
| 时间顺序 | 到期边界先同步 Spatial 和原经济；日结内部为到货→生产及人口消费/价格→缺货运输安排。随后组织观察、工资、个人安排。个人补购使用日结后的价格和库存；同刻安排按人物/商品 ID 排序。手动动作不推进时间 | 同刻个人争用可能依赖稳定 ID 顺序；未来采购/生产结算顺序可能改变可购数量。新增个人分钟边界也会触发工资结算调用 | 正式消费与工资/生产的优先级；原工资使用到期分钟、Ledger 拒绝倒序日期，欠薪重试与后续交易的组合效果未运行确认 |
| 操作完整性 | 重新报价后，同步调用转账→扣市场库存→增个人财产→追加个人记录；没有 await；购买 ID 已处理时拒绝重复扣库存 | 正常条件失败多发生在变更前，但没有覆盖三组件的回滚或提交机制。收款账户和保管关系先于转账建立，转账失败时可留下零余额关系；转账后中断未见补偿路径 | 普通运行中的跨组件中断、未来并发/多卖方交易需求未确认。不把同步顺序宣称为完整原子事务 |
| 持久化替换 | v2 恢复绑定当前商品、原单位、购买金额公式、市场卖方 ID 和匹配的 Ledger 交易；v6 恢复绑定市场收款角色/所有者 | 替换卖方、币种、数量精度、取整或删除记录后，原恢复条件可能不成立 | 旧财产与账务是否保留、迁移或明确不支持，需经济线决定；本轮不新增兼容包装 |

没有依据将这些潜在冲突判为已发生的运行错误。也不能因代码存在就默认它们是正式经济规则。

## 可复用与待决定部分

可供经济线复用：原人物账户关联、稀疏个人持有、购入批次与消费来源引用、个人生活记录、同一 GameClock 上的安排到期、页面数量/报价/结果入口，以及按有关人物分页读取的方式。复用需要与正式商品、卖方和账户语义一致。

临时模拟假设：市场即卖方及库存保管者、同人口统计单元即能购买、模型分币直接等于个人模拟货币单位、所有非服务商品都能按千分之一单位出售、四类商品可消费、每日缺量必须自动购买。它们不能直接作为企业物流和正式消费需求规则。

经济线需要决定：个人需求如何进入宏观消费；正式卖方及库存所有权；收款资金回流；单位/币种/舍入；同刻结算顺序；跨组件操作提交方式；旧财产记录的后续读档政策。

## 若将来舍弃，涉及的范围

本轮不删除。未来需一并处理以下实际依赖，而非只移除按钮：

- `FormalWorldEconomyState` 的 personal sale 字段、Ledger 绑定、报价/出售函数、持久字段及恢复条件。保留原市场库存、价格和宏观结算所需读取。
- `FormalPersonalEconomyState` 的持有、生活记录、安排、记录序列及其读写/重建函数；v2 财产字段与购买 Ledger 交易匹配。原账户、开局资金和工资路径另行区分。
- `FormalLedgerState` 的 `market_receipts/purchase` 及旧交易、余额的处理。账户索引也被正常账务读取使用，不应因移除购买自动删掉。
- `SimulationStep` 的个人到期边界、消费调用及返回标记；保留原时钟、日结、组织观察、工资结算。
- Bootstrap 的两项经济绑定；Persistence 中经济先于个人财产恢复的依赖；原存档内三个组件中的已发生交易与财产。
- Application 的三类动作、所在地市场导航和生活反馈；Presenter 的财产/报价读取；PersonView 的物品和生活记录、购买账务跳转；EconomyPage 的选择/报价/购买；MainShell 的数量控件、动作与页面返回字段。
- 说明文档中的第一批个人生活声明：`README.md`、`docs/ARCHITECTURE.md`、`docs/UI_INFORMATION_ARCHITECTURE.md`、`docs/SAVE_FORMAT.md` 和 `AGENTS.md` 中相关说明。此次移交报告可继续作为实现记录。

源码完整路径均在上述组件表中。地图与军事控制、历史行政資料、经济实验引擎不属于这批个人交易实现的删除范围。
