# 同一 kernel 的有界连续推进（实验）

`Authority.advance_bounded(target, quota)`请求同一world time推进到target；每次最多quota
个明确primitive，返回PENDING/COMPLETE/BLOCKED及committed_time。下一调用保留
target/policy，quota可以改变。只有相关物理、原phase/ID事件和摘要完成才提交边界。
PENDING公开ports返回旧提交时间，不返回部分事实；新输入和LOD改变拒绝。
这是一项进程内实验API；没有新时钟、线程、定时器、守护进程或正式存档。

原prepare/apply方程只在segment_work.gd维护；同步和续算入口复用。单位准备、
索引记录、二分probe、候选读取/排序、目标贡献、单位应用、接触诊断、报告、
domain事件、摘要fold和旧接触/plan/delta清理可续接。先从同一段首生成incoming，
再应用两方，不能先扣一方后计算另一方。quota不是积分边界，也不影响keyed draws。

一个primitive不等于一条机器指令：固定形状的unit操作，最大64leaf的原domain
事件/测试provider，native元数据操作仍有成本。已登记scope最多1024 representation、
活跃cell/scope128、跨scope metadata4096、route traversed history4096、pending总量
100000和Godot static memory512MiB；超限明确BLOCKED并保留事实/旧时间，不删接触。
纯报告heap也计pending。容量是本实验支持包络，不是全球模拟能力或硬wall帧保证。
复合输入/provider只采用本实验有界定义，不承诺任意GDScript插件的执行时间。

current live、pending、event/物流幂等、人物知识、决策context/结构历史分别计数；
诊断trace ring4096、分页256，host重复诊断256。权威历史不压缩、不删、不称总内存常量。
大地图读`lod.spatial.view("region_50")`的已提交摘要；物理snapshot/audit是显式诊断导出，
不能替代大地图接口。恢复编码任务先读iteration的四份检查点并核对git/evidence；
中断的实验推进不算完成世界存档，须按同一输入重新运行。

快速主链（固定Godot4.6.3，先headless import；driver的--output使用不存在的新目录）：

```sh
python3 -B experiments/war_resolver/continuity/run_scenario.py --scenario main --seed 71 --seconds 1800 --quota 7 --output builds/task9-quick-review
```

24小时持续负载：100cell/400leaf，15背景蓝cohort按既定3km合成路缓慢运动；
初始17活跃格、24h末尾15，几何focus2。异质pair保持详细，有限库存与4次外部
ETA以及临配均走Task5/6。具体company人物275次机会后停止；source在每次实际机会
之后形成局部报告，延迟47秒，provider读收到知识。物流ETA独立于空间路径。

```sh
python3 -B experiments/war_resolver/continuity/run_scenario.py --scenario long --seed 109 --seconds 86400 --quota 31 --output builds/task9-stress-review
```

quota0使用同步reference。可选其他case：main/no-cut/slow-reports/no-supply/keep/
cycles-disabled；同CLI支持seed、seconds、quota。更久的目标时间不代表此输入持续
产生新决策（long周期在24h停止）；7日连续负载未执行，不将空闲快进冒充压力测试。

Linux扩大/最终门：

```sh
python3 -B experiments/war_resolver/iteration/cloud_validate.py --mode final --output builds/task9-final-review --baseline-evidence experiments/war_resolver/iteration/evidence/m0-linux/evidence.json --script experiments/war_resolver/spatial/tests.gd --script experiments/war_resolver/continuity/contract_tests.gd --script experiments/war_resolver/continuity/tests.gd --script experiments/war_resolver/continuous/cursor_tests.gd --script experiments/war_resolver/continuous/tests.gd --script experiments/war_resolver/continuous/load_tests.gd --script experiments/war_resolver/continuous/long_tests.gd --script experiments/war_resolver/continuous/profile_after.gd --script experiments/war_resolver/continuous/retirement_tests.gd
```

正式门不能加--skip-unified。该driver执行原PowerShell的等价步骤，原PowerShell
本轮未运行；fatal matcher与原断言保留。16MiB诊断上限或timeout触发显式失败，
截断/中断无PASS。性能probe首样预热、后5样；profile_before历史证据对应M2算法，
当前运行该脚本会测当前版本，不能再称before。after60秒包含第二段的清理，before
300秒；吞吐总耗时不能直接比较，最大不可中断段及所有构建/读/输出成本分别记录。

版本化m0-linux来自本轮冻结Task8的实际运行。driver在.log缺失时读取同名.txt，
仍要求经济失败日志逐字一致，并严格比较旧hash；没有放宽matcher或改golden。
不同平台/环境不要强制沿用本轮Linuxhash：先在冻结Task8的独立worktree建立该平台
基线（薄driver可复制，GDScript保持Task8），再给本分支--baseline-evidence。
本轮实际M0 raw位于builds/task9-m0，最终完整门另实际验证版本化.txt输入可用。

Windows本轮NOT RUN。Linux cloud_validate使用selector读取pipe；不假称它是
Windows官方runner。Windows应使用仓库原PowerShell导入/统一验证、固定Godot
直接运行相同GDScript，run_scenario.py的--godot可指定本机exe；这些本轮未实测。

退眠清理反例门使用独立N*N/2有向接触计数与零弹药/静止初态，覆盖当前contact
表已移除时的逐记录释放，并对照同步物理结果和仍发布的active contact表。
新清理只处理已不发布的旧诊断引用，不退回时间/燃料，不提前丢合法接触。
