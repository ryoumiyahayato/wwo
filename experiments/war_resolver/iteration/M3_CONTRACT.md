# M3 实施前记录：计量与续接边界

先profile-before：dense100/400，6次首样预热不计统计；prepare/apply/events最大段，
construction/normaladvance/query/serialization分别计时。原1000同刻事件批次独立测。
休眠10000area/30000squad的构建与内存另列，活跃核心计数必须相同。
不靠一个原resolve_until总耗时证明峰值解决。

拟路线是原kernel内小步状态机；同步路径也驱动同一运算原语，保持原循环/求和/phase
和ID次序。不得复制另一套战斗公式。准备unit→索引→候选→接触→火力贡献→unit应用→
contact诊断→control→到期事件→LOD摘要。接触遍历和到期事件均可让出。
所有incoming effects先从同一段首状态生成，再应用，不能先扣一方再规划另一方。
外部quota只限制cursor实际工作，不能成为新的积分边界。

一次请求保存唯一目标T和旧已提交时间。部分工作期间公开读接口返回PENDING及旧
时间，不给半份新world/knowledge/authority。内部边界仅是待提交工作的时间坐标，
非第二世界时钟；完成全部相关物理、同刻事件和摘要后才提交那个时刻。不得超越未算
因果工作。外部新写入/zoom/coalesce在pending时拒绝，不能改变段首输入。
内部可信局部观察仍走原scope验证，provider只能在原decision phase收copied knowledge。
诊断signal携带事实不会授权provider读取private状态；public query门始终关闭到提交。

续算的工作单位需明确列实际primitive及计数，index/candidate traversal不能隐藏为
一个整场调用。索引/列表排序若保留native不可中断段，必须记录其实际输入规模、最大
wall time和容量边界；不能称硬帧预算。目标hot sort采用可续接稳定merge，范围二分
和候选逐项读取分开。metadata的native ID列表快照仍需计量并有明确容量背压，不能
扫描全部休眠单位。实验active scope拟上限1024、原domain event受影响范围拟上限64；
超范围可以拒绝该推进请求/报告PENDING_CAPACITY，不能截断真实接触或丢事件。
如果本要求仍不能通过，就BLOCKED该性能门，保留LEVEL_2，不下调验收条件。

集中1000同刻混合space/structure/logistics/communication/decision/旧area事件：
phase/ID原序，分批完成，全部仍在同一游戏时刻，禁止后900条漂移。
纯报告保持独立非物理通知队列；报告due drain也需分批，不能一口吞任意大queue。

24h两个seed71/109，100cell/400leaf、10–20active、1–2详细focus，其余兼容cohort；
混合输入包含有界持续reports/decisions/有限supplies/structure。正常与quota1/7/31
同输入物理精确相同；短LOD六seed包含单侧/局部/不同切换时点，原误差依据不变。
记录构建、普通推进、zoom/物化、query/serialization，p50/p95/max和最大原子步骤。

history分类：live、pending、权威idempot/身份、知识历史、诊断ring；不删除历史或
清幂等。diagnostic<=4096，duplicate host diagnostics<=256，源历史线性增长明报；
512MiB静态监测/pending100000超过则容量背压/停止，不静默丢因果事件。

当前M2绿色代码0c93b66，docs31fa059，M0基线c4731a3。M3未验收。

## 长run持续负载补充（首次24h后、下面新输入运行前）

首个24h case虽初始17活跃cell、精确续算成立，背景运动很快结束；它只证明有限
事件长期闭环。新增更严格的持续移动输入：15背景蓝cohort mobility=0.002 km/min、
已知3km道路，手算24h无抑制上限2.88km，疲劳只能降低移动；因此必须24h仍10–20
活跃cell，不能用大半天空闲代替持续负载。参数是合成慢速能力，未历史校准。
原有限ammo/fuel/geometry/400leaf和原报告/决策/ETA/临配仍相同；正常vsquota1/7/31
继续精确相等。长测试调用上限1000万仅防异常无限循环，不截断合法接触。
