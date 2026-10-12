# M3 历史实施备忘（11008e8时点）

本文件保留当时计划，不作为当前恢复入口。当前状态以NEXT/RUN_STATE/FINAL_ACCEPTANCE与实际git/evidence为准。

已实现11008e8：原resolver prepare/apply方程唯一移到continuous/segment_work.gd；
原同步wrapper逐primitive驱动。resolver1876/0、Task4 17329/0、combined116/0，
八Linux原hash同平台严格相同，builds/task9-m3-extraction-replays/evidence.json。
复制原块的脚本/tmp/task9_extract_segment.py及/tmp/task9-original-segment.txt仅辅助，
正式代码已commit。M3未通过，M2绿色0c93b66独立保留。

实际before测量builds/task9-m3-profile-before完整78.00s结束，原400dense：
advance median11965.062ms，最大prepare677.986ms/apply667.28ms；100dense
median801.419ms，最大prepare52.527ms/apply69.295ms；1000同刻事件due20.577ms。
源码hash在before evidence，算法与冻结M2一致，仅新增profile脚本，dirty artifact
有明确fingerprint。未来运行profile_before会测当前wrapper，不当作再次before证据。

下一先写continuous/tests.gd独立contract，method不存在时明确FAIL返回，不ScriptError。
要求normal vsquota1/7/31物理精确等价（排除工作/派发诊断计数），第一call quota1
PENDING/committed_time0，between-calls macro/snapshot/knowledge等PENDING旧时间，
写入/zoom/coalesce拒绝。同刻1000事件phase/ID顺序不漂移。再最小实现。

热路径：stable resumable bottom-up merge sort（一步一个比较/写入）；Index begin-build
逐unit examine并append，sort结束后正常range；range二分每步一个probe、gather每步
一个ID、候选ID再增量lex排序，必须保留原target顺序/浮点求和/计数。SegmentWork加
bounded bool；bounded source_begin选择cursor，多次prepare_step驱动cursor；sync仍
用原native candidate数组。Index构建须在Segment.prepare之前，如原Indexed。

推进临时AdvanceWork是算法调用工作记录，不新世界manager/时钟。唯一state.time
在每个内部primitive暂用其待提交boundary坐标，返回外部前恢复last committed；
pending_time_stamp始终明确。内核privileged-work flag仅在resume期间；between-calls
所有public读返回PENDING旧stamp，所有新输入/LOD改变拒绝。可信scenario局部来源
可在内核回调里生产scope-validated观察；provider仍仅在完整原decision phase读取
copied knowledge。raw内部dict不作为observer接口，不能用其读半份成果。

AdvanceWork阶段：initial due（每次最多1，报告due也每次1）；clear request touched once；
select anchored boundary fromsamepolicy/target/event；prepare eachscope逐index/segment；
逐unit原ammo/fuel/route ETA压缩boundary；统一boundary后各scope apply逐incoming/
unit/contact；真实transfer与control逐unit；due原phase/ID逐event；LOD stocks逐cell/
unitfold并原3祖先；全部相关工作结束提交stamp。不要因quota重定边界。
可额外定义metadata native ID snapshot<=1024、domain event受影响<=64的容量背压，
记录最大不可中断输入规模/wall；超范围不截断接触/丢事件、不称硬帧预算。若仍不满足
用户门，就BLOCKED并保留LEVEL_2，不把primitive计数当隐藏批量的借口。

Kernel._process_due拆_one(state,log,changes,areas,fold_reports=true)，同步原while
调用默认true，bounded先逐条报告fold再_one false。Information增加单条due方法、
默认deliver_reports_through仍循环它，知识/消息不改物理边界。事件domain helper最多
64影响对象，phase/ID排序依旧State heap。public guards只opt-in pending时生效。

Authority.advance_bounded维护唯一临时job；返回requested/committed/status/work_units/
actual record counts/callwall/maxprimitive，pending不提供state_delta新事实。摘要fold
成为job内容，不能抛到完成后无限重建。日志诊断ring4096或流式，不积累全天output。
原Authority.advance仍同期完整输出，不能在pending状态另跑。query不追账。

24h输入建议复用spatial/fixtures.gd新增opt-in background输入（所有初态在seal之前），
100cell共400leaf：现有4主leaf，补396；15背景cell活跃，加主范围合计10–20。
背景节点每cell蓝/红端点、3km已知合成路、独立scope/lane，坐标在50x50包络；
main四cell现有scope保持，背景同cellscope一致，独立lane不会互相穿越接触。
每cell蓝/红pair可coalesce；一个异质weapon/mobility pair显式拒绝，报告可聚合比例。
主要细部focus仅1–2cell，其余cohort。Task5各背景platoon2leaf归side company；
facts为400leaf Task6有限库存。主军官cycle end86400/max275、仍315s cadence；
每真实机会host在之后局部observe/report延迟47，收到知识不能预刷新。
预先Task6有限reservations4次ETA每4/8/12/20h，Task5同一leaf临配4次，小scope；
外部桥开闭几次，不增新planner。与M2默认4leaf/6cycle完全隔离。

24h seed71/109 normal及quota1/7/31；性能采样有限5次预热后p50/p95/max；6seed短LOD
单侧coalesce/局部物化/不同切换时点按原20%/0.2km趋势界限。10000sleep/30000
单独构建，active-core delta相同；1000future3due不全扫描；1000same-time混合事件
可用primary fixture合法少量Task5/6/7/8 +大量spatial/area预登记事件补足，不伪造
1000越过actor冷却命令。存储live/pending/身份/知识/diagnostic分开历史线性明报。
