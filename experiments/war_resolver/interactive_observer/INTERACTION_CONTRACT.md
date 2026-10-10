# 具体人物交互契约 v0（G0登记，冻结后补充）

本轮起点6be7343，运行祖先3052a0c；242个旧运行文件逐字节核对。新360有效分钟上限；UTC 2026-10-10 11:34:22开始，不复用旧600分钟。旧AGENTS的GUI/人工旅程条款由本轮明确的文本研究范围覆盖；仍运行原统一门。不删除旧UID/缓存，不修改正式检出。

会话是一个Godot场景实例、一个固定session_id、一个已存在人物和一个有限研究时钟。支持S1/squad、S2/platoon、S3/soldier，另S1/company任务分配。身份和职位来自场景登记；输入不含actor/role/rank，不支持换人。选定人物的启动预设脚本被禁用；其它人物的autonomous规则、S3班长撤回、原常驻任务、桥/补给/配属仍保留。无输入对照使用同一初始化和时间计划。

Python标准库客户端解析人工文本和脚本的同一语法，再通过固定8192字节标准输入frame发送有限JSON。Godot固定尺寸读取后验schema/session/ID；只有Godot保存和改写战争。Python不求解战争，不保存可写世界副本。OS.read_buffer_from_stdin的Windows pipe会等待指定字节数，所以发送完整定长frame；它不是每条请求重启。参照[Godot 4.6 OS官方文档](https://docs.godotengine.org/en/4.6/classes/class_os.html#class-os-method-read-buffer-from-stdin)。不新增网络服务或RPC框架。

人物视图只用Information.knowledge（默认20，上限20）、本人既有Participant.view、合法message/个人transition反馈、自己的意图和已登记地图。未送达报告值不显示。军官个人伤病没有overlay时为UNKNOWN；健康0显示失能，不宣布死亡。不会先导出world_result再过滤。自己的职位、有效权限元数据和已知路表不根据隐藏桥open变化。

look/status/reports/events/receipts/help/focus是只读；不推进时间、materialize、发令或改变随机状态。默认20条，before游标分页。人物事件索引最多256条，截断给出缺口；权威Knowledge/消息/ID不因此删除。读取工作只和本人物所选页、少量回执/权限目录有关。诊断计数独立于战争。

advance按已提交时间推进指定增量；resume继续同一target与原bounded游标。AUTO预登记绝对结束时刻（最多86400秒）、固定步长（默认30秒）和倍率“尽快执行”；客户端按该计划pump，不因look次数改变target。手动等待时显示研究时钟暂停。自动无输入也pump；暂停在安全提交边界生效。每请求最多64个原bounded调用；整个会话最多10000000调用。到限BLOCKED，不伪装完成。显式quit/EOF停止实例、释放资源；不是游戏内死亡或停战。

PENDING只给最后已提交的人物视图与PROGRAM_STATUS；新人物意图明确拒绝，READY后显式重试。不能输入游戏时刻，不能倒填。请求收到、决策机会受理、意图接受/拒绝、已发出/待送达、送达权限结果与已知执行报告分开。个人动作走原本地入口，军官走原15秒通信；不加统一延迟。

请求ID限定ASCII且最多48字符。最多128个不同人物意图ID（含被领域拒绝的ID），不得清空以越过上限。同ID同内容只返回原回执；同ID不同内容拒绝。旧session请求不生效。新增ID受PENDING/容量约束；原已受理请求保留。文本最多2048字符，frame内容最多8191字节；负数/非有限时间、额外字段、未知类型、非法actor和过长数据有界拒绝。不会接受位置、健康、库存或伤亡赋值。

受限反馈不复述隐藏世界的诊断细节。权限/时钟/容量拒绝为PROGRAM_STATUS；军事信息只能来自本人反馈或收到报告。精确物理可行性仍由原域校验；无合法来源的拒绝细节显示“意图未获受理”，不补造未知原因。

G4使用71/109/347/2027，全部是回归seed，不再叫holdout。自动验证实际文本进程、同输入headless基准、无人输入AUTO、查询密度、隐藏桥/Knowledge相同、PENDING、重复/跨session、角色边界、送达复验、分页、守恒和退出。成本分构建/常驻、读取、输入、推进/续接、格式化、清理与可选证据导出。原战争政策/倍率/期限/seed不变。带个人/目标叶的split/merge/coalesce仍拒绝，宿主不绕过。

默认不导出DEBUG_TRUTH。研究证据仅在显式diagnostic参数下分目录保存；不是人物输入或输出。最终完整门未通过则PARTIAL。人工玩法与视觉验收NOT_RUN。下一算法缺口仅记录，不实施。

冻结补充：PENDING拒绝全部人物意图重试，READY后同ID仍幂等。focus仅过滤当前20条报告页；无已收条目就是未知，不搜索世界或全部历史。页游标越界给程序拒绝。个人回执ACTION_STARTED/ACTION_FINISHED来自原本人transition；军官DELIVERED_ACCEPTED仅表示送达域受理。实际active/complete/failed/cancelled与BLOCKED/ARRIVED来自另列的已收objective/route报告。原报告没有命令关联，不补造关联或把报告强行归到某个命令ID。

最终导出不会开启计算诊断。显式测试导出仅在会话结束。文本`cancel -`映射原空目标。所有运行改动位于新interactive_observer目录；原战争源码、golden与matcher不改。短文本格式只显示报告与回执；`--json`提供完整受限已知目标和路线目录。人工可读性尚未验收。
