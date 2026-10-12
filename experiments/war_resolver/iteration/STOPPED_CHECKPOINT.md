# WWO WAR ALGORITHM — TASK9+ BOUNDED ITERATION

**用户要求停止并重开，本轮已停止；不是完成验收。** 没有新增实现/测试、定时器、
后台进程或另一写代码者。原测试进程自然结束后已保存全部当前变更和失败证据。

- Base: `c4731a33177660b83c6490f41fe42dcbe7cfa7bb`。
- Final code HEAD: `ed54ef6b68146df4a560b77865d8d47efd077730`（包含未验收反例）。
- Final docs HEAD: 文档保存提交，请以 `git rev-parse HEAD` 核实，不作自引用。
- 工作分支: `experiment/war-spatial-continuity-goal-v0`。
- Environment / Godot: Linux x86_64 `/workspace/wwo`；实际4.6.3.stable.official.7d41c59c4；Python3.12.14。
- 模型/推理: 平台未提供实际运行元数据，无法核实用户请求6.1-sol/xhigh。
- Effective execution budget: 约50分钟已用、约550剩余，墙钟近似；恢复不可重置。
  环境启动等待约13秒单列；断开通知后新的exec及原session均可访问，未观察到可计量停机。
- M0 PASSED / M1 BLOCKED / M2 DEFERRED / M3 DEFERRED / M4 DEFERRED。
- Highest accepted level: **NONE**。Overall: **BLOCKED — USER_REQUESTED_RESTART**。
- 原玩法边界: 生产接入NONE；没有改Task1–8原分支、旧断言、golden或正式源码。
  空间新路径的低cohesion退却有已复现缺陷，因此不能声称全部原玩法约束已验证保留。
- Integrated causal scenario: **NOT RUN**；M1只有空间/移动/接触/LOD测试，M2多轮知识链未实现。
- Longest game-time: 24h仅四leaf休眠对照；100cell/400leaf活跃长期run **NOT RUN**。
- Resource / authority / knowledge / LOD: 原回归43948/0且旧Linuxhash相同；新手算
  .1km/10s/.24fuel通过；断桥在途停/实际返程及材料化当前进度修复通过限定集。
  新路线尚无Task7/8人物命令与知识闭环。新反例仍失败。
- Per-call bound: **NOT IMPLEMENTED**；接触与整个segment仍不可中断，M3没有开始。
- Storage/queue: 三到期空间fact/997未来保持pending的测试通过；持久身份/知识历史
  未压缩，未完成长期增长预算测量；不声称总内存常量。
- Predecessor caveats: M0原Tasks1–8+五回归43948/0，原八组replay和四组正式probe
  双进程一致；audit31/0。官方PowerShell NOT RUN，49等价步骤48过/1失败。
  frozen baseline economy golden 3 checks/2 failures独立重现原Linuxhash；保持失败。
- 最新阻塞及复现: `spatial/tests.gd` 170 checks/3 failures，另有不存在schedule_ground
  的脚本错误。诊断目标fire rate漏乘detection factor；低cohesion仍沿route向外走。
  动态ground API未实现。最后命令已完成exit1，不需为证明状态重复运行。
- 发布: 仅保存独立分支检查点；Draft PR **NOT CREATED**，没有merge/生产发布。
- Human visual acceptance: **NOT REQUIRED / NOT RUN**。Production integration: **NONE**。
- Next smallest follow-up: 尚未授权本任务继续实施；建议新任务先核验源diff/证据/剩余
  预算，再修复这两个已复现缺陷并决定动态地形契约；不得丢弃或覆盖现存反例。

## 证据索引

`evidence/m0-linux/evidence.json` 记录87个实际进程步骤（含重复经济复现）；两个
失败均属于同一个已知经济golden，不重复算成新回归。原日志仍在builds/task9-m0。

`evidence/stopped-linux/task9-m1-gate.json`：ae63fdd限定门，原43948/0+空间160/0，
旧hash逐个匹配当前Linux M0；明确skip_unified=true，不冒充最终完整验收。

`evidence/stopped-linux/task9-m1-counterexamples-executed.json`及同名txt：最后实际
失败。执行时HEAD为ae63，但新增fixture/tests未提交；source_digest已与保存的
ed54代码逐文件核实相符。`STOP_SUMMARY.json`记录该证据对应关系。

## 可恢复源版本

- d84e2a12cf7b4fa40862ab0d0ec2602b6e3ec49d：M0预登记和基线索引。
- ae63fddb25046f02b3095ad70bdded538cdaef26：限定集合通过的空间实现；并非完整M1通过。
- ed54ef6b68146df4a560b77865d8d47efd077730：保存追加反例及修正后的fixture，未验收。

本机复現入口（只有重新授权后再运行）：

`python3 -B experiments/war_resolver/iteration/cloud_validate.py --mode affected --script experiments/war_resolver/spatial/tests.gd --output builds/task9-resume-unique`

Windows本轮 **NOT RUN**。基线取回后先读GOAL/ACCEPTANCE/RUN_STATE/NEXT并核实
真实git diff及日志，而不是相信PASSED字符串。引擎import在生产目录生成的未跟踪
UID保留在原云端且未提交；没有删除未知修改。普通实施任务，原生Goal未启用。
