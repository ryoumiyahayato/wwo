# Ten-Year Timing Verification R1

Phase A decision: **INCONCLUSIVE_ENVIRONMENT_SENSITIVITY**.

PRODUCT_CORRECTNESS = PASS。当前14次均满足原240秒检查，但旧统一验证的失败不被改写。Phase B准入条件已满足。

## A. TEN-YEAR CALL PATH

原测试 `tests/formal/formal_world_long_term_balance_test.gd` 调用
`WorldBootstrap.build()` → `SimulationStep.advance_minutes()`，十次各推进
365 × 24 小时。每日顺序为 GameClock → Spatial → Economy → Organization
responsibility review → Personal Economy wages。年度摘要读取及年度检查也在原计时区间内。
完整 snapshot、JSON serialization、恢复与恢复检查在原计时区间之后。

沿 build/simulation/state/persistence 入口保守追踪到的 55 个全局依赖类，与冻结 R2
逐字节相同。现有、未被测试调用的
`WorldBootstrap.prepare_presentation_content()` 是另一个显示内容工厂。
它的类型依赖使 HistoricalLoader / GeographyLoader 脚本在解析阶段可被缓存，
这不等于执行 `load_current()` 或新增的 `decode_relief()`。

实际 Relief 入口是 FormalWorldApplication 安装 renderer 时绑定
`GeographyLoader.decode_relief`，随后 MapRelief.request() 启动显示工作线程。
十年 build/advance/save/fingerprint 路径不调用该入口。

证据：`local-artifacts/ten-year-strategic-r1/static-call-path.json`、
`freeze-comparison.json`、`freeze-manifests.json`。

## B. R2 / RELIEF PAIRED RUNS

全程交替 R2 → Relief。原测试文件、40项检查、十年长度、240秒计时区间和阈值不变。测量副本仅在区间外加入只读读取。第一对 native CPU clock 误用内部线程ID，作为预实验保留，主线程CPU不采信；进程CPU和原计时仍有效。

|Run|原 loop wall s|Main CPU s|Process CPU s|Exit|
|---|---:|---:|---:|---:|
|canonical-01-r2|185.267|INVALID PILOT|185.234|0|
|canonical-01-relief|174.876|INVALID PILOT|174.438|0|
|canonical-02-r2|183.804|180.734|183.000|0|
|canonical-02-relief|207.071|202.969|205.188|0|
|canonical-03-r2|184.495|181.750|184.141|0|
|canonical-03-relief|209.986|205.156|207.766|0|
|canonical-04-r2|203.828|200.000|202.641|0|
|canonical-04-relief|175.233|173.688|175.969|0|
|diagnostic-01-r2|182.094|176.875|179.297|0|
|diagnostic-01-relief|180.415|175.375|177.688|0|
|diagnostic-02-r2|175.943|171.203|173.562|0|
|diagnostic-02-relief|181.315|175.594|177.672|0|
|diagnostic-03-r2|173.191|168.781|171.000|0|
|diagnostic-03-relief|174.586|169.031|171.109|0|

基础2–4为三个已校准配对，另有三个完整domain诊断配对；两种harness分别比较，不能混池。14个完整十年运行约46分钟，故采用最低三对完整domain重复。诊断timer保留同样240秒检查，但额外observer等待不能代替原测试验收。

## C. DOMAIN CPU COST

Windows `GetThreadTimes` 的 kernel + user 时间与 `QueryThreadCycleTime`
通过排除发行的 Python sidecar 读取。线程周期数不换算为 wall-clock 秒数。
原 domain owner 仍执行所有调用；测量 delegator 不持有新的 authoritative state。
SimulationStep、WorldState、Economy、Organization、Spatial、Population、GameClock、
Persistence 正式源码和算法均未修改。

量测分别覆盖 Economy settlement、Organization review / structure snapshot、
Spatial advancement、Personal Economy wage settlement。余项包含 GameClock、
detached Economy view preparation、年度检查及 observer 开销。Population 没有现成的
独立读取 instrumentation，标为不可独立量测。短调用的 CPU attribution 受 Windows
时间量化影响；每次 4,000 次空 observer 的校准结果原样保留。

API 依据：[GetThreadTimes](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreadtimes)、
[QueryThreadCycleTime](https://learn.microsoft.com/en-us/windows/win32/api/realtimeapiset/nf-realtimeapiset-querythreadcycletime)、
[Godot execute_with_pipe](https://docs.godotengine.org/en/4.6/classes/class_os.html#class-os-method-execute-with-pipe)。


|Domain|R2 CPU median s|Relief CPU median s|R2 cycles median|Relief cycles median|Calls/run|
|---|---:|---:|---:|---:|---:|
|economy|132.218750|134.375000|382797182108|392709726320|3650|
|organization_review|21.781250|24.109375|66478822547|67604257290|3650|
|organization_snapshot|0.015625|0.000000|38552323|39200120|10|
|spatial|6.484375|6.250000|18853564244|19286990606|3650|
|personal_economy|0.109375|0.125000|328288135|326691109|3660|

原始CPU刻度观察到15.625ms量化。Organization前两对CPU tick显示+6.19%/+11.12%，但周期数为−1.77%/+2.69%，调用内wall为−1.87%/+2.80%；第二对各主要domain周期均随同一整体速度变化约+3%。Spatial tick的相反偏移同样不能解释为算法改善。短domain归因须连同原始周期、调用wall、空observer校准阅读；不消除、不重写CPU读数。

每次均有Economy3650、Organization review3650、Spatial3650、Organization snapshot10、Personal wages3660次调用。所有目标均委托原authoritative owner执行，没有关闭domain。

## D. WALL-CLOCK VARIANCE

记录总进程 wall time、原 simulation 区间、进程及主线程 CPU、bootstrap、
最终检查、snapshot、serialization、restore/checks。CPU 使用率按一个逻辑核
100% 表达；不冒充整机使用率。

逐秒记录 AC 状态及 Windows power-manager 报告的 P-state，并记录 active power
scheme。另以 Windows Processor Information counters 记录系统聚合的 processor
performance、frequency、performance limit、CPU utilization。
这些聚合值不是运行线程的精确有效频率。温度、真实热降频、Windows power slider
若未可靠量得，继续报告 UNAVAILABLE。

每轮边缘记录后台进程累计 CPU。采样期间观察到另一个用户战争实验 checkout
的 benchmark / 十年测试运行；未停止或干预它，也未调整电源设置。


校准基础pair2–4 loop wall：R2 183.804/184.495/203.828，Relief207.071/209.986/175.233秒，快慢关系反转。完整domain三个pair主线程CPU差(Relief−R2)：−1.500/+4.391/+0.250秒。当前AC均为1，active scheme为Balanced。power-manager P-state与Windows系统聚合counter原样保留，不能证明旧超时的具体物理原因。

## E. RELIEF INVOLVEMENT

各阶段读取 ResourceLoader cache，并以实际被加载的 probe/bootstrap 脚本作为
positive control。全部受测阶段观察到 SceneTree 仅有根节点，MapRelief、GlobeRenderer、
RegionView、relief shader、relief payload 均未缓存，texture/video monitor 为 0。
完整记录在每次 `PRESENTATION_BOUNDARY` 输出中。共享 GeographyLoader 脚本缓存
如实列出，不能把“无解码执行”写成“脚本完全未加载”。

每次还检查完整 save hash、恢复后完整 save hash、authoritative fingerprint、
恢复 fingerprint、最终事实 hash、年度经济结果与 schema。全部14个样本完全相同。


Full save SHA256: `49b506ba3c671e76db6c10c29a673fc7248efe4aee015d0ac2a1d47e5870e288`。

Authoritative fingerprint: `f8ddb8968d598efdc9811b4a761750f3596540f666d9fefa0f6eae523c77bd4a`。

Schema=`formal_world_simulation_v14`，save=699092 bytes，年度fulfillment全部3194bp，87600小时，146政治实体、50主要详细经济、40routes。完整save恢复前后逐字节相同。所有既有canonical data与R2字节相同；正式源码/原测试哈希复核通过。

## F. PHASE A DECISION

**INCONCLUSIVE_ENVIRONMENT_SENSITIVITY**。

未发现Relief进入simulation或新增domain执行路径：实际依赖代码/输入相同，原调用次数相同，完整状态相同，domain周期和调用wall没有专属Relief增量，renderer/relief/image/shader/GPU准备未执行。满足用户给定的C→Phase B条件。

仍不能把旧244/276/286秒等失败明确归因于某个调度、温度或电源因素；本机背景任务有变化，热传感与线程有效频率缺失，样本有限。因此不使用NO_RELIEF_REGRESSION_CONFIRMED替代这一限制，也不把旧NOT_PASS改成PASS。240秒规则继续用于之后正式统一验证。

原始证据位于`local-artifacts/ten-year-strategic-r1/`：各次log/JSON、run-summary.csv、analysis.json、frequency-samples.jsonl、freeze manifests、static-call-path.json、phase-a-decision.json、唯一完整save。测量副本、扫描和归档不进入Release。
