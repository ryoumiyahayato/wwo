# M2 引用边界与采纳决议

本审查限定于M1已读章节和本轮静态源码；没有新增检索、全文通读或论文实验复现。39个去重来源仍为34个普通方法状态+1个版本疑点+4个正文缺口。参考冻结的是笔记、定位和以下边界，不是所有原论文的真实性/适用性认证。

**ADOPT_FOR_CURRENT_EXPERIMENT在本阶段仅表示已采纳为M3预注册设计依据。4项设计采纳、0项运行算法采纳、0项已执行新实验。** 历史adoption_decisions分组是当时状态，本表是M2最终范围；缺口来源和版本冲突不能作实现权威。

| Source | M2 decision | Allowed scope / exclusion |
|---|---|---|
| KL2003 | ADOPT_FOR_CURRENT_EXPERIMENT | 限定拒绝归属/固定估值；D3/D4不能跨买方或跨环境推永久边界 |
| BG2007 | ADOPT_FOR_CURRENT_EXPERIMENT | 可见证据与相关样本边界；D2/D5观察前缀断言，非ADWIN实现 |
| BDKS2013 | TEST_AS_REFERENCE | 有限库存/收入目标边界；仅D6诊断，不借CappedUCB |
| LMN2017 | ADOPT_FOR_CURRENT_EXPERIMENT | 销量截断与实际请求分开；D6同销量不同需求对照 |
| XWCW2026 | TEST_AS_REFERENCE | 仅库存截断解释；算法符号疑点未澄清，任何其算法实现禁用 |
| ZJYC2023 | ADOPT_FOR_CURRENT_EXPERIMENT | 主动探测必须记成本/干预；D2/D3不凭后台变化适应 |
| G2016 | TEST_AS_REFERENCE | D6在途/责任/库存位置解释，不采纳安全库存参数 |
| SCARF1959 | INSUFFICIENT_ACCESS | 只得元数据/发现信息，方法未读；不借用定理或更新规则 |
| CLIFF1997 | INSUFFICIENT_ACCESS | 只得元数据/发现信息，方法未读；不借用定理或更新规则 |
| BOE2014 | DEFER | 记账范围参考保留；不因资金问题加入银行 |
| ZEZZA2004 | TEST_AS_REFERENCE | D6守恒不足以证明正确端点，保留ID关联 |
| SANCHO2024 | DEFER | 家庭需求域/预算条件，本轮无家庭实现 |
| DEBOER2009 | DEFER | 偏好参数/校准尚不具备，需求系统延期 |
| FAO2004 | DEFER | 生理需要不是购买/无限积压，本轮非家庭模块 |
| TRAIN2009 | TEST_AS_REFERENCE | D4硬预算/候选身份先于软偏好；不改选择器 |
| BEA2009 | DEFER | 货币IO不能替物理配方，本轮不全局解逆矩阵 |
| ACOT2012 | DEFER | 全局静态均衡不替局部订单或服务指标 |
| WOLITZKY2022 | DEFER | 固定配方可行性参照保留，不改生产 |
| GOOGLE_ASSIGN2026 | TEST_AS_REFERENCE | D4已知可行图的离线参照，不全知采购 |
| MANEA2016 | DEFER | 暂持匹配不等于accept责任，不换采购 |
| JACKSON2001 | DEFER | 全图反事实收益不作为局部供应商行为 |
| ATALAY2011 | DEFER | 度分布生成不是交付可靠性机制 |
| FP_VERSION_AMBIGUOUS | DEFER | v1 wrapper与正文日期/版本列表冲突；不得作当前实验实现依据 |
| G_MRP2006 | TEST_AS_REFERENCE | D4/D6日期与既有订单责任；净需求符号提取疑点不抄实现 |
| MIT_DELS2009 | DEFER | 全未来确定需求/零交期不满足，批量优化延期 |
| SAP_MRP_CURRENT | TEST_AS_REFERENCE | D6 forecast/order去重与未结责任；不迁移MRP产品 |
| GS1993_GAP | INSUFFICIENT_ACCESS | 只得元数据/发现信息，方法未读；不借用定理或更新规则 |
| WHK1992_GAP | INSUFFICIENT_ACCESS | 只得元数据/发现信息，方法未读；不借用定理或更新规则 |
| QE_MCCALL_CURRENT | DEFER | 已知IID工资/永久岗位，仅未来劳动入口 |
| ACEMOGLU_DMP2020 | DEFER | 宏观流率不分配具体技能职位 |
| GOOGLE_MINCOST2026 | DEFER | 全给定图的静态单货流，不建中央调度器 |
| NETWORKX_DIJKSTRA_CURRENT | DEFER | 静态路径不预留容量，物流实现延期 |
| DEAN_TDSP_UNDATED | DEFER | 已知FIFO时刻函数假设，出版年UNKNOWN；本轮不改路由 |
| KM1997 | DEFER | 未来土地价完全预见，不作为信用实现 |
| EK2002 | DEFER | 连续商品/全来源比较，不建贸易生成器 |
| CPMI_PVP2023 | DEFER | 结算原则，不提供授信或汇率机制 |
| ABIDES2019 | TEST_AS_REFERENCE | 只参照事件时序/部分责任，种子声明不代替WWO确定性证明 |
| NASDAQ_NEQD2026 | TEST_AS_REFERENCE | D4总量和个体分配需分报；不采用其证券分配规则 |
| BCS2015 | DEFER | 证券批量制度，不改实物每日交易 |

## 必须随引用保留的限定

- KL2003 §2.1共同固定估值，不能推出跨买方/未来永久上界；N4并非实现该区间算法或继承收入遗憾定理。
- BG2007允许分布随时间不同但要求独立有界样本；重复请求、内生报价和库存变化不能直接使用其阈值保证。
- LMN2017只见被库存截断的需求，其零交期易腐域不是WWO；WWO收到的真实请求比销量多的可见信息必须保留。
- ZJYC2023的GLM、特征与Lasso/检测/探索参数不迁移；仅采纳探测是一项有成本行动的设计纪律。
- BDKS2013为固定未知IID估值、一次性买方、初始有限不可补货k；目标收入不能替换逐sink服务。
- XWCW2026固定a/b、IID噪声与对抗库存并非一般需求漂移；Algorithm1的≤与Algorithm3的<疑点保留。不得默默改符号。
- G_MRP2006净需求公式提取疑点、MIT_DELS文字重叠、未视觉核验表图，以及Dean年份未知均保留；不据有疑点细节实现。
- FP版本身份冲突独立于“读到了方法”。Scarf/Cliff/Gode/WHK没有方法正文，不能借标题充当算法证据。
- N4的单步tick界、全窗口零接受门和公共ceiling是Lab既有机制；不追认成某篇论文的原算法。所有WWO小反例都是独立推导，须M3验证。

逐条Source→假设→WWO差异→最小适配→否证实验及定位见[m2_claim_design_map.json](m2_claim_design_map.json)。未列当前实验映射的来源只保留其原方法卡与DEFER边界。许可仍按sources逐条记录，不加入全文镜像。
