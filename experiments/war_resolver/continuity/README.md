# 有限知识与空间因果联动（M2）

`scenario.gd`只提供合成初态、外部断桥、当地来源、有限仓库及独立ETA响应。
原kernel计算实际运动/火力/损失；Task5改变有效关系、Task6转移有限库存、
Task7送达时重验Role权限，Task8在明确人物机会读取copied knowledge。
`route_intent`是opt-in路径意图，仍经过同一通信/冷却/权限链，不直接跳转位置。
provider只持有自己的有限规则记忆，不持有truth或服务引用；不是正式AI。

公司军官t10起、315秒间隔、最多6次、1800秒期限。t120断桥，局部观察之后
报告47秒、命令15秒。无新知识时keep，旧BLOCKED/LOW语义不会复制同一输入。
紧急票据仍使用原Task8的当前票替换/重复拒绝；暂停、退役和期限结束停止评价。
新机会确实增加物理边界，keep数值切分成本实测，未声称零成本。

临配unit_001于t15至1500；旧platoon命令t47送达拒绝。永久归属保留，
Task6补给责任随有效关系，仓库有限100弹药；请求10、外部运输ETA+30秒。
桥损不改库存或delivery；路线化物流未完成。M2只使用4个underlying leaf，
不把该运行当M3的100cell/400leaf压力验收。

快速因果入口（先按仓库指引执行固定引擎headless import）：

`python3 -B experiments/war_resolver/continuity/run_scenario.py --scenario main --seed 71 --seconds 1800 --quota 0 --output builds/task9-main-unique`

Godot直接入口：

`godot --headless --path . --script res://experiments/war_resolver/continuity/run.gd -- --scenario main --seed 71 --seconds 1800 --quota 0`

场景：main/no-cut/slow-reports/no-supply/keep/cycles-disabled。当前quota=0是原
同步推进；非零会明确拒绝，M3验收前不能宣称预算内续算。
阶段验收使用cloud_validate.py --mode affected，分别--script continuity/tests.gd、
continuity/contract_tests.gd（均填完整experiments/war_resolver路径）。最终M4使用
--mode final且不加--skip-unified，并带全部新增脚本及M0 evidence。

trace字段有id/time/subject/kind/cause_refs/scope/input或execution；命令发出与
送达、报告observed与received、物理受阻与改道分别记录。中文timeline来自事实模板。
诊断ring最多4096，分页最大256；另feedback/host_receipts最大256，超出仅覆盖
诊断。权威消息/知识/身份/结构/物流历史不删，增长另报。Windows本轮NOT RUN。
