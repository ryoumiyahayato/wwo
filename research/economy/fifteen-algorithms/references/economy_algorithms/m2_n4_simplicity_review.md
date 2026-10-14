# M2 N4静态简洁性审查

结论：**NO_JUSTIFIED_CHANGE（M2阶段决策）**。保持原N2/N3/N4定义；目前没有已执行的Cycle03因果反例证明新增行为规则值得其代价。M3可能改变此判断。没有实现等价重构，没有运行经济代码或测试，也没有证明N4最优。

审查基点：7e4f54bc2177929f6bbb7a5d7de54b9fd439d3d9。源码定位相对于仓库根：`economy_quantity_lab/goal_cycle02_candidate/learning.py:19–63`（L），`goal_cycle01/pricing.py:15–28`（P），`goal_cycle01/payment_policy.py:122–161`（PP），`goal_cycle02/causal.py:116–143`（T），`goal_cycle02/causal_audit.py:47–55,163–211`（A）；完整路径/hash见m2_static_review.json。

## 输入、状态和规则

设G为已配置卖方×商品数，K为本窗口独特(buyer,need_id)总数，A为到窗口结束仍未过期的interest数，L为实际request lines数。以下成本是静态代码分析，不是计时或论文复杂度保证。

| 项目 | N3继承部分 | N4增量及成本 |
|---|---|---|
| 持久跨窗口行为状态 | 当前/初始价格、下一日pending价格、既有金融/库存/订单账 | `refusal_ceiling[key]`一个整数/卖方商品，初始化4×initial；O(G)，无买方索引，无时间戳 |
| 窗口状态 | shipped计数、interest字典(date及三类拒绝max)、information集合；窗口内按buyer/need去重 | `window_accepts[key]`一个接受量整数/卖方商品；每响应累加，完成窗口清空；O(G)增量 |
| 自由参数 | initial/tick；固定7日窗口、2%步长、1/4地板和4倍上限；原反馈开关 | 0个新数值调参量；1个`candidate_enabled`行为开关；current−tick沿用tick尺度，不是另一个连续参数 |
| 核心接口 | current/initial/tick+LocalWindow六字段 | 增加accepted、previous_ceiling、enabled；共7个形参。新增结果字段用于追溯，不是额外行为记忆 |
| 独立经济规则（本审查的语义计数） | 原N3四路优先条件及HOLD、量化和上下限 | R1严格学习门；R2上界限制目标并保留单步界；R3无信息保持；R4关闭候选回N3，共4项。不是把校验/日志if算行为规则 |
| 特殊分支 | 原整数/tick域检查、NO_NEW_INFORMATION等 | 上界域检查；enabled/info门；学习门；price不同才改reason。AST local_quote为4个if语句+1个三元式，含校验/诊断，故不等于4项经济规则 |
| 外部查询 | 窗口末读取本卖方free stock和已收到窗口事实 | 新增0个世界/买方/未来查询；request_result仅累加真实响应accepted，local_quote没有world参数 |
| 每次响应 | PP逐line去重/分配排他拒绝原因，平均哈希O(L) | 接受量累加O(1)额外；不重新查询买方限价 |
| 每次窗口 | sort G为O(G log G)，过滤K再作3次A求和；输出G项下一日报价 | 逐key纯函数O(1)，总增量O(G)，重置接受量O(G)。总O(G log G+K)，常数含多遍扫描；临时active列表O(A) |
| 普通非边界日 | 原事件/订单行为 | end_day先检查feedback/日数，O(1)返回；不全历史扫记忆 |
| 历史长度依赖 | window每7日重置；订单/identity/报告档案有各自寿命 | ceiling不随天数增长，接受量只在窗口存活。不能由此说整个引擎或审计O(1)内存 |
| 解释/审计成本 | 有独立财务/物理和日期因果检查 | 必须重建每窗accepted、PRICE/CASH/PHYSICAL、ceiling与生效日；每seller-good增加一个审计ceiling，不用runtime函数算期望 |
| 依赖与引擎 | 标准库及已有Lab模块 | 0新第三方依赖、0第二CashAccounts/Simulation物理权威；wrap复用原对象字典 |

**精确规则**：先按P算base、step。enabled且information_count>0时，只有PRICE拒绝>0、整个真实窗口accepted=0、窗口末free_stock>0、active CASH拒绝=0才令C'=max(low,min(C,current−tick))；否则C'=C。目标min(base,C')仍受current±step及low/high约束。无信息且enabled时保持current/C；disabled回base。所有有效路径C'≤C，永不自动上调。

free_stock>0不等于每个需求有及时运输；accepted涵盖整窗，拒绝求和只用date≥结束日的interest。一个已过期需求的窗口接受仍可能阻止学习。PP对同need/reason保存max，不是逐次求和、最终一次状态或概率；同一need在下一窗口重新出现仍计一项information。该字段表示窗内实际请求身份，不表示IID样本、首次遇见买方或私人估值发生变化。

## 边界与诊断

- 高限价买方有一次真实接受即阻止本窗进一步降C；**不会解除已存在的C**。N3 base仍可能降价，不能把“未学习”写成“报价未变化”。
- 有PRICE标签且没有请求/接受的故事不合法：卖方学习信号来自真实request_result。买方未查询、未选择、报价被日期过滤、无ATP等属于不同因果阶段。
- N4只取得聚合窗口量；上游结算用买方自有限价分类，并不把该数值传给local_quote。观察器包含私人/世界诊断，必须保持只读。
- `lower_hit/upper_hit/unclamped`继承base提案；记忆挡价用base_price与实际price单列，不能将旧标志算成记忆触顶。
- step可能为0（例如p49,initial100,tick1），或ceiling低于current−step。量化/单步限制可令报价高于ceiling；这是原规则，不作为修复理由。
- C较低仅说明状态受限；低价可能改变金额、资金或分配，也可能完全不改变交付。须证明`memory→posted quote→visible feasible choice→accepted order→shipment/arrival→production→sink`链，再报告总量和逐sink差异。

## A：行为等价简化候选，均未执行

| 候选 | 可成立的静态观察 | 未采纳理由及未来必需验证 |
|---|---|---|
| A1从interest.keys推导information集合 | PP每line同时插入同key、重置同时进行，正常路径看似重复事实 | 会改继承接口及trace消费点；必须穷举所有写入口、异常路径与trace开关，保持已过期key仍计information及完整记录。若把active keys当information会改变行为。尚无资源必要性，不为少一个集合改旧接口 |
| A2一次循环代替active列表加三次sum | 固定三个计数可单遍累积，减少常数/临时列表 | 不减少持久状态/参数/经济规则；代码可读性和真实收益未测，不能叫已简化。若以后做，需包含价格、订单、付款、物资、逐sink的差分验证 |
| A3抽取N3/N4重复end_day骨架 | 两者观察收集/清窗相近 | 跨冻结N3/N4布局变更扩大范围，且容易混用独立audit；不准为去重共享被审计公式。拒绝当前实施 |
| A4以bool取代accepted量 | 行为门只比较0 | 真实接受量还用于诊断和独立审计；转bool会丢证据。不能用trace计数替runtime计数，trace可关闭 |

这些都是待证明等价的候选，不是SIMPLIFIED_EQUIVALENT结果。保留原校验、命名、审计独立性。

## B：会改变行为的候选，当前均不成立

| 候选 | 新增代价 | 目前缺失的必要证据 |
|---|---|---|
| 固定寿命/衰减上界 | 年龄/最后更新时间及寿命或衰减参数；时间流逝触发行为 | 空窗不等于新经济证据；无数据支持某个遗忘窗口 |
| 新买方/接受即释放 | 买方历史或新旧判定、释放门与幅度 | 新ID/在低价接受不证明愿付高于C；混合拒绝/接受依然混淆 |
| 周期报价探测 | 时钟/阶段状态、周期和幅度、探测成本 | 必须作为主动干预单独策略ID；先有M3值得解决的可复现服务代价与成本目标 |
| 买方分别记忆 | O(买方×卖方×商品)状态、归属/合并规则 | 公共单一卖方报价如何汇总、分配及遗忘仍未定义，不是小重构 |
| ADWIN/CPDP/CappedUCB整体 | 桶/估计/动作状态、多参数和统计假设 | 重复相关请求、截断与非收入目标不满足已读保证；本轮DEFER或范围拒绝 |

**审计成本不能隐去**：A虽逐行读取压缩日志，仍保存requests/decisions/orders/updates等累计结构，`recorded_event_facts`保存按日free/shipped，具有历史长度依赖。T也保存自己的独立窗口接受计数，不能并入runtime。compact observer按日清price_records，full保留历史；将流式文件格式说成全流程常数内存是错误。M3先量测一个小场景的输出/RSS，再决定M4保留层级，不在M2重写审计。
