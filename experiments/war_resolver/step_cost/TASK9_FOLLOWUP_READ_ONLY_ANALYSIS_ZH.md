1. 总体判断

SUPPORTED_WITHIN_SCOPE：Task9+ 已建立“有限空间事实 → 局部观察 → 延迟知识 → 人物决策 → 延迟命令 → 实际行动”的隔离实验闭环，以及同一内核的分批推进。LEVEL_3 成立于预登记输入和验收边界，不等于正式军事系统、完整战术语义或生产性能已经成立。

下一轮最值得减少的不确定性是：哪些不可中断步骤仍随容量或所携带的历史数据变大，以及峰值来自实际工作放大、复制/释放，还是运行环境抖动。

建议主目标选 P1。P2 只保留“与最长步骤直接相关的数据复制归因”作为条件性附属项，不启动全面历史存储改造。37ms 的根因目前没有被定位到具体单位、具体复制对象或子调用，不能直接断言由决策历史引起。

本次只有资料读取、静态解析和已有文本指纹核对；没有运行 Godot、测试、benchmark 或新实验，没有改仓库，也没有创建军事后台任务。

2. 冻结版本与证据状态

本次重新读取的 PR 信息：#111 仍为 Open / Draft / 未合并。
Task8 基线：c4731a33177660b83c6490f41fe42dcbe7cfa7bb
最终代码：69fa36d6202b2b0d8e9332406ff57d269749fa0c
文档与证据：3515734e5dfdf4bfa04fc0047764f53c380389ed
验证 checkout：f609b75b4d7711863d8c769f3cfd9667bc84fb59

已读取：
- FINAL_ACCEPTANCE、ACCEPTANCE、REPRODUCE、M3_CONTRACT、M3_IMPLEMENTATION_NOTES、NEXT、continuous/README。
- gate、metrics、raw-index、long、profile、retirement、main、timeline，以及 M0 evidence 和最终已知失败日志。
- advance_work、segment_work、range_cursor、sort_cursor、authority、space、scenario、policy、decision service/context、information service，以及相关长跑、容量、续算测试源码。

源码静态核对：
- 上述14份关键 gd 文件的 SHA-256 与 gate 中的指纹全部一致。
- 代码提交到验证 checkout、到最终文档 HEAD 的比较，均没有新增 gd/py 运行源码变化，差异为文档与证据。
- M0 与最终记录的12组结果 hash 相同；已知 economy 失败日志 hash 相同。
- 最终日志明确是 day30/day365 两项 economy golden 失败；没有证据将原因定为跨平台浮点问题。

RECORDED：95个步骤、43,948项前置检查、640项新增检查，以及“排除已披露基线失败后的实验门通过”。这些是历史记录，不是本轮重跑；检查数不是独立场景数。

未读取/未验证：
- 没有读取整仓库或所有原始运行目录，只读取版本化资料和相关源码。
- 最初尝试的 spatial/service.gd 返回404；按实际引用改读 spatial/space.gd，不构成该主题缺证。
- Windows、七日持续压力、目标设备、人工视觉/试玩、正式接入均未运行。
- 没有验证实际模型元数据；只能保留“创建时请求6.1-sol/xhigh”。

主要可复制入口：
PR：https://github.com/ryoumiyahayato/wwo/pull/111
验收：https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/FINAL_ACCEPTANCE.md
机器门：https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/evidence/final-linux/gate.json
计量：https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/evidence/final-linux/metrics.json
复现说明（本次未执行）：https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/REPRODUCE.md

3. 能力边界表

| 领域 | 已有证据支持 | 仍不能推出 |
|---|---|---|
| 空间 | SUPPORTED_WITHIN_SCOPE：分叉路线、属性地形、断桥、有限相邻接触 | 完整侦察识别、战术地理真实性、全球GIS |
| 联动 | RECORDED：1800秒、至少三轮实际输入闭环 | 完整自主规划或无限持续战争 |
| quota | SUPPORTED_WITHIN_SCOPE：按primitive计数、同输入精确续接 | 硬毫秒上限或吞吐提高 |
| 最大步骤 | RECORDED：37.045ms，apply:apply_units | 已定位子调用、最大容量性能合格 |
| 历史存储 | RECORDED：分类增长，诊断ring有界 | 总历史或总RAM常量 |
| 异质LOD | RECORDED：拒绝不兼容聚合、有限偏差场景 | 任意异质战场无偏、长期切换不碎化 |
| 跨平台 | RECORDED：指定Linux/Godot版本 | Windows或目标设备通过 |
| 玩法语义 | SUPPORTED_WITHIN_SCOPE：到达、任务状态、有效人员存在式control | 完整占领、脱离接触、具名人物生死 |
| 可观察性 | RECORDED：结构化因果trace、时间线、PENDING时间戳 | 玩家可读性、可玩性、正式观察程序 |

4. 四项专题解析

4.1 空间与玩法缺口

a. 路线可达与机动
SUPPORTED_WITHIN_SCOPE：移动沿明确路段，扣实际时间和燃料；断桥后停留，改道需实际返程。
UNVERIFIED：战术选路、风险权衡、队形、拥堵与完整交通物流。备用路线是 scenario.standing_orders 中预置的 fallback_path，不是人物侦察发现或自主搜索出来的路线。

b. 观察与射击
SUPPORTED_WITHIN_SCOPE：通行与接触许可分开。源码 detection 同时要求距离范围以及 lane.observe、lane.fire，返回可用于火力的探测因子。
因此不能把它称为完整独立侦察链：能看见但不能开火、识别错误、射界与观察精度的完整语义尚未形成。

c. 地形有效性
属性确实进入速度、隐蔽、掩护与火力结果；同属性换地形标签不变。SUPPORTED_WITHIN_SCOPE。
真实战术有效性与历史校准为 UNVERIFIED，不应以合成地形名称替代校准。

d. 到达、控制和撤退
main.json 中 unit_000 已到D并完成任务，但 cell_063 为 contested。
静态原因明确：control 根据格内有效人员所属方是否多于一方判断，不以任务是否完成或部队正在hold/withdrawn来决定。因此“路线任务完成但仍交战/争夺”在当前规则下可以解释，不是单凭这一现象就能判错。
问题在未来玩法命名：withdrawn 标志表示路线撤回/结束，不保证敌方不能继续作用；hold 不等于停火；当前control也不是完整占领权。
这些语义必须在未来玩法验收前定义，但不阻塞本轮成本边界研究。性能对照应冻结现有语义，不能借优化修改它们。

e. 人物与AI
policy是固定规则：根据收到的路线/弹药claim选择预置路线、有限补给或keep。它没有全知世界输入，仍不是正式军职玩法或正式AI。
损失字段是宏观数量；没有具名人物伤亡、死亡和视角延续证据。不能宣布普通士兵体验或人物生命系统完成。

f. 读取与真相
已有隐藏桥况不刷新人物知识的反例；provider收到复制的知识和权限元数据。SUPPORTED_WITHIN_SCOPE。
但接口仍需区别：authority.preview_leaf 是预览，read_leaf 会调用 materialize_leaf。两者都不能被笼统宣传成“纯显示、零表示副作用”。未来观察程序应明确用哪类接口，不能把世界诊断接口接进人物决策。

相关源码：
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/spatial/space.gd
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/continuity/scenario.gd

4.2 最大步骤、吞吐与积压

quota限制什么：
SUPPORTED_WITHIN_SCOPE：resume 中每次 _step 计一个工作单位，used达到quota后返回；不是按实际耗时抢占。排序比较、候选读取、接触处理已有游标，但并非所有内部操作都拆分。

仍可能随规模增长的单步：
- State.sorted_ids、keys/ID快照等原生容器工作。
- sort_cursor.configure 一次做两份 values.duplicate。
- segment_work._apply_unit 中 unit.duplicate(true)，以及移动、物流、依赖唤醒等复合子调用。
- 路径完成的 pop_front、traversed增长及携带这些数据的复制。
- 单个领域/人物决策事件内部的context构建、provider调用和复制。
- 清理最后引用时的释放成本。
- 聚合准入、物化、全量snapshot、结果编码等advance以外的工作。

37ms的定位强度：
RECORDED：seed109、quota1 的外层最大调用37.157ms；内部最大primitive37.045ms，标签apply:apply_units。
UNVERIFIED：二者没有共同的调用序号、单位ID和子阶段记录，不能证明它们一定是同一次调用，更不能分解为纯CPU计算。
内部primitive计时围绕 _step；事件回调与log清理发生在这个计时之后。外层advance_bounded还包含封装和完成时清理。因此两种最大值的测量边界不同，不能简单相减当作固定开销。
HYPOTHESIS：深复制、释放、原生调用或宿主调度抖动均可能贡献峰值。不同seed/quota下峰值变化明显，但这不足以选择唯一解释。

容量：
源码确认scope1024、活跃representation/变更metadata4096、cell/scope128、事件影响范围64leaves、已走路线history4096、pending100000及Godot static memory512MiB等检查。
最大已测密集成功规模是400，不是1024满密度。另有1025单位触发BLOCKED的反例；24h的400 underlying leaves多数聚合，不能替代400详细密集交战测量。
而且“≤64 leaves”约束不自动限制事件携带的知识、路径、context字节总量。

BLOCKED：
已测1025反例保留单位、旧提交时间，公开查询仍PENDING。
源码没有把BLOCKED变成完整事务回滚，也没有证明任意阶段容量耗尽都可无损撤销/跨进程恢复。应保留“部分内部工作不可公开”的契约，进一步区分保留状态与可恢复服务能力。

吞吐：
分批增加调度和游标成本，不能从调用变短推出总工作变少。before300秒与after60秒不能相除。
即使long.txt两边都是24h，也不宜直接算加速倍数：long_tests 的bounded wall_ms在结果比对和storage序列化之后才记录，而normal_ms更接近纯advance，边界仍不一致。

积压与公平：
结束pending=0仅适用于该有限输入；未证明持续高输入率下的稳定性。
唯一提交边界保护因果一致性，但一个昂贵scope可能延迟其他区域的共同提交。现有资料未给最坏等待时间或宿主调度公平性保证。
因此P1首先研究单轴最大容量反例是合理的；暂不能宣布37ms合格或不合格。

源码及原日志：
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/continuous/advance_work.gd
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/continuous/segment_work.gd
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/evidence/final-linux/long.txt

4.3 权威历史增长

必须分别看八类：
- 活跃战争：live序列化294,540→297,281 bytes，近似稳定但非严格常量。
- pending：初12、末0，不代表峰值为12或任意输入不积压。
- 去重身份：event ID、information entry ID、物流使用ID、结构退休身份，删除可能允许旧事件重复执行。
- 人物知识：观察、消息、收到的claim及冲突来源，不能替换成当前世界真相。
- 决策历史：决策记录、当时context、proposal、权限验证、已发输入。
- 结构/表示历史：配属、来源、generation、退休身份、mission模板及物化记录。
- 诊断：ring有界，可丢诊断不等于可丢权威事实。
- harness：参考世界、physical/knowledge/messages/decisions深复制和输出，不能算成单个世界常驻RAM。

一个需要纠正的口径：
metrics里的knowledge 2,897→753,833 bytes，是observations、messages和knowledge的组合序列化，不只是received claims数组。
decision_history 104→7,546,263 bytes对应整个decisions._events，也不等于单独context的字节数。两者都不是RAM。

静态证据支持重复context：
decision.service在每个决策记录中保存context深复制，另给provider一份深复制，返回/查询时还会复制记录。
但是context通过knowledge默认只取最近最多64条claim。因此目前不能断言“每次决策扫描并复制全部历史”或必然二次增长。记录总量仍随机会次数增加；每条context还受claim大小、standing_orders和权限目标大小影响。
information的_subjects索引追加同一entry引用，不能仅凭两个索引存在就认定RAM中复制了两份实体记录。

条件性方向：
可以研究不可变claim引用、版本化权限快照、context引用化及分段历史；必须保留“当时看到什么、何时收到、权限当时是什么”的可重建性，且不能让后来的可变数据改写旧决策。
稳定ID和必要来源不能删；移出活跃查询路径不等于总存储有界；归档也要计量。

HYPOTHESIS：这些复制可能增大due步骤，但尚无证据说明它就是apply_units 37ms的来源。单位自身的路线历史与决策历史应分别检验。

源码：
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/decision/service.gd
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/information/service.gd
https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/continuous/long_tests.gd

4.4 LOD与边界正确性

RECORDED：40leaf样本中，同质4/4可聚合、4个表示；异质3/4、13个表示，候选16→169，实际接触8→44。说明兼容性变化会显著削弱收益，不能外推所有战场。
源码拒绝不同武器、状态、路线、任务和部分供应特征的合并；这是保守边界，不应为提高聚合率直接放松。

满足兼容条件可显式coalesce；未见本轮连续推进自动搜索并重新聚合碎片的机制。因此不能承诺表示数量自动恢复低位。

物化会新增mission和materialization记录，generation也增长。重复加载几何与反复物化/再聚合是不同操作；已有少量focus切换不能证明无限循环无额外历史成本。
六seed LOD记录主要比较误差绝对值，最差3.508256%；它支持原预登记界限内的样本，不证明没有有方向的小幅优势或反复切换累积偏差。

相邻接触、空间标号中性和资源守恒有专项证据，但不覆盖任意跨区拓扑和异质军队。
quota变化要求同输入精确等价；LOD近似用原资源/位置/任务容差；真实组织或命令改变则不能要求结果不变。

PENDING期间现有公开写入/LOD操作被拒绝，已入队事件按原phase/ID处理。未来宿主必须定义明确拒绝回执、是否由宿主暂存、如何重新提交及何时计入世界时间；不能由优化偷偷改变事件顺序。

5. 候选优先级

主目标：P1，不可中断步骤的容量放大来源与可验证边界。
条件性附属：P2中“携带历史或重复context导致的单步复制成本”。只有与P1同一因果链得到证据时才实施最小表示调整。

暂缓：
- P3：保留已知碎化和偏差风险；只有P1定位到表示切换/释放为主要峰值时再进入。
- P4：玩法语义重要，但改占领/撤退规则会改变性能对照的世界规律；先冻结。
- P5：目标硬件未给出；未来设备验收必须有独立平台基线，不混进当前算法归因。
- P6：目前trace足够支持研究；正式观察程序待用户授权行为验收。
- P2全面存储工程：已有增长证据但未证明是最长步骤根因，不提前选择数据库或压缩方案。

6. 两个最小可判别反例

以下全部：PROPOSED / NOT RUN / NOT AUTHORIZED。

反例A：原生步骤的单轴容量放大

研究问题：quota=1时，单个primitive的工作是否仍随输入大小增长？
证据缺口：已有400成功/1025拒绝，没有1024内单轴成本曲线和同次调用细分。
H1：排序初始化、ID快照、深复制或释放携带规模相关工作。
H2：极值主要是调度/分配抖动，计数所描述的实际单步工作没有相应放大。

最小初态：一个scope、两个对立方；先2个单位，然后仅增加兼容固定形状单位数至16、64、400、1024。不同时增加历史、地图、事件数量；1025仅作超限拒绝例。
变量：该scope的representation数量。
对照：同初态、同seed的正常推进和quota1；候选修改前后保持同一30游戏秒区间。
事件顺序：t0封存；无外部新命令；完成首个提交和必要退休清理。不靠删除合法接触减少计算。

公开结果：提交时间、状态、单位/资源/接触事实、拒绝理由；PENDING不暴露部分结果。
计量：关联call序号、phase、unit/scope ID；记录原生复制元素数、排序比较/写入数、释放记录数；分别计外层调用、_step、回调、结果清理、构建和查询。每配置一次预热、五次样本，保留全部样本、p50/p95/max和环境负载。
不变量：双边同段首输入、资源身份、phase/ID、提交边界、quota精确等价、纯读无推进。

通过：反例能区分H1/H2，至少定位一个可重复的结构放大路径，或以明确范围否证选定路径。
失败：计量改变经济/战争结果、计数漏掉复制/释放、丢事件或公开半状态。
不足以判定：仅一个wall峰值、没有操作计数关系，或容量运行被环境限制中断。
上限：逐轴阶梯推进；沿现有512MiB门，单配置最多10分钟墙钟、整个反例最多90有效分钟；未完成标RESOURCE_LIMITED，不算性能成功。45分钟无可解释进展就缩小路径。
下一步：H1成立才切分该路径；H2较支持则加强测量，不盲目重构。1025正确BLOCKED只证明边界拒绝。
玩法确认：不需新增玩法语义；硬响应验收需另给目标设备/宿主预算。
预计成本：设计和计量30–45分钟，定位/复核45–90分钟，修改另在G2授权范围内决定。

反例B：相同活跃状态，不同携带历史

研究问题：历史总量增长是否直接放大一次决策/复制步骤，还是主要增加保留存储与导出成本？
证据缺口：现有终点分类字节没有对象级复制量，也没有固定活跃状态的历史长度对照。
H1：旧context、claim或单位历史被反复展开，导致单步工作随历史长度增长。
H2：决策只读取最多64条，单次成本达到窗口后趋稳；主要增长在历史保留/诊断导出，或另一路径。

最小初态：1个人物、1个合法报告来源、1条通道、同一被指挥formation的2个leaf、固定权限；provider只keep，不引入新命令。用合法已送达报告和keep机会产生历史。
变量：历史长度1、16、64、128、256；最近64条可见claim的内容/尺寸和当前战争状态尽量配平。总ID和历史数量差异明确作为处理变量，不声称完整世界相同。
对照：相同目标时刻与下一决策输入；额外设置“历史总量变大而当前窗口相同”和“窗口从16增至64”两组，不混合。
顺序：t0准入→按既有合法时间间隔送达→完成提交→在共同t*执行一次keep决策；不得读取真相替代旧claim。

公开结果：人物知识分页、决策intent/权限结果、提交时间、无新命令；旧消息重放仍被拒绝。
计量：决策context构建/保存/provider复制/返回各自计数与时间；每条context和claim字节、唯一对象/引用数量、累计保留量；序列化、Godot static、RSS若可测分别命名，harness与被测世界分离。
不变量：旧知识不被新真相改写、稳定ID、幂等、权限时态、资源与时间、当前窗口定义。
通过：明确区分总历史效应和64条窗口效应；若提出引用化，必须能重建同一旧context且无可变别名污染。
失败：通过删来源/去重ID/旧决策获得改善，或改人物的有效信息窗口。
不足以判定：活跃状态未配平、只测最终JSON大小、计时混入完整snapshot。
上限：最多五档、每档预热加五次；总75有效分钟，容量超限停止。没有45分钟内可定位的新证据就保留增长说明，不开启全面存储方案。
下一步：若历史确实进入主峰值路径，作为P1附属修正；若只影响导出/常驻量，单列后续P2，当前不扩范围。
玩法确认：维持原知识与历史契约无需新增玩法；任何遗忘、历史裁剪或权限回溯语义变化须单独批准。
预计成本：状态配平与记录30–45分钟，测量归因30–45分钟；正式持久化不在范围。

7. 下一轮阶段验收草案

全部为未来设计，尚未执行。

G0：证据与计量
输入：冻结代码/证据、原允许失败边界。
输出：测量边界表、单轴manifest、确定性结果清单。
证据：版本指纹、各计时是否含callback/复制/导出、环境信息。
允许：隔离诊断与记录；禁止改公式、容差、golden、知识窗口。
失败动作：来源不一致或测量无法对齐则阻断后续修改；可继续只读定位。

G1：反例可判别
输入：冻结A，必要时B。
输出：H1/H2比较和最小放大路径。
证据：操作数量随单轴变化、完整样本、状态不变量。
允许：最小合成fixture与诊断；禁止删合法负载制造提速。
失败动作：不具区分力则修正实验设计并保留旧结果；不足证据不进G2。

G2：最小方案
输入：已定位路径。
输出：至多一条主修正路线、工作单位和公开语义变化清单。
证据：为什么该改动直接针对已测原因；预计总工作和额外存储。
允许：相关游标/数据复制表示的有限改动；禁止新内核、架构重写、玩法改义。
失败动作：若依赖改变知识/身份/提交契约，停止并请求授权；不以更小quota代替方案。

G3：边界与回归
输入：同配置的修正前后版本。
输出：确定性结果、计数、响应与吞吐分别对照。
证据：正常/quota精确等价、原LOD容差不放松、集中事件顺序、纯读、权限、退眠清理、超限保留。
允许：同缺陷的有界修正；禁止刷新旧golden。
失败动作：正确性失败阻断依赖成果；连续两轮无改善转定位/方案比较，不扩大机制。

G4：冻结交付
输入：最终代码、冻结配置及允许失败清单。
输出：完整回归、原始失败和修正记录、复现说明、补丁/bundle、限制报告。
证据：实际命令/退出码/源码指纹、全样本及NOT_RUN。
允许：封存与已授权交付；禁止自动merge/生产接入。
失败动作：如完整回归未完成则PARTIAL，不以“写出代码”结束为成功。

最小成功：指出至少一个关键路径的实际结构上界及代价；对有证据的问题完成有限修正并保持旧契约，或证明无需修改并给出可核对支持包络。
部分交付：可复现归因、计量和未解决边界，但无完整修正/回归。
阻断：来源错误、不可保持因果/身份/时间、需新玩法原则。
停止：目标达到、预算/额度耗尽、用户暂停、权限阻塞；所有未完成项明确记录。

8. 预算草案

A. 最小推荐周期：360有效分钟，最后90分钟封存。
- 来源与基线45
- 计量/最小反例75
- 一条主方案与必要修正75
- 针对验证45
- 最终回归与交付90
- 环境与测量机动30

这是有界研究预算，不保证届时所有容量组合都完成。若基线更贵，缩减尚未启动的可选反例，不压掉最终验证。

B. 如另行批准600有效分钟：
- 来源与基线60
- 最小反例与归因120
- 主方案和必要修正135
- 对应边界验证105
- 环境/计量机动45
- 最终冻结回归与交付135

最后至少90分钟不再开新机制。满足目标可提前结束。约45分钟无明确进展重新分类；两轮无改善停止盲改。当前没有启动这两个预算。

9. 真正需要用户决定的事项

- 是否授权下一轮实施，以及选360还是600有效分钟；本回复不构成启动。
- 若要判定响应性能“合格”，需目标CPU/内存、宿主每次可用时间、期望游戏推进速率、可容忍提交滞后和输入负载。未知时先做结构归因，不设虚构毫秒门。
- 如未来需改变withdrawn、占领、知识遗忘或公开提交语义，必须另行批准；本建议暂不需要修改它们。
- 远端发布权限须在未来授权中明确；当前只读授权不能推导出push/PR权限。

不需要用户替我们判断37ms具体落在哪个子函数，这应由未来计量证据解决。

10. 待授权的下一轮目标描述

本段为下一轮实施目标草案，尚未授权执行。

以代码69fa36d6202b2b0d8e9332406ff57d269749fa0c及证据HEAD3515734e5dfdf4bfa04fc0047764f53c380389ed为冻结起点，研究单一问题：当前不可中断步骤中哪些工作随支持容量或携带历史放大，最小修正是否能在保持原世界规则的条件下明确收紧工作边界。

只允许隔离计量、至多两个预登记反例，以及对已定位路径的一条主修正路线；历史表示仅在与该峰值直接相关时作为附属项。保留单一时间轴、PENDING公开边界、phase/ID顺序、知识与真相分离、权限复验、资源和身份守恒、原golden与已披露失败。

禁止玩法扩展、新战斗内核、正式AI/UI/人物生命系统、生产接入和未经另行授权的远端写入。验收以路径归因、确定性不变量、同口径成本与完整回归为依据，不以测试数或曲线好看为依据。建议360有效分钟，最后90分钟验收；600分钟只能另行批准。达标、预算耗尽、权限或契约阻塞即封存停止，不自动开始后续周期。

分析状态：NEXT_ITERATION_PROPOSAL_READY。

军事只读解析至此结束；没有启动上述反例、修改或下一周期。
