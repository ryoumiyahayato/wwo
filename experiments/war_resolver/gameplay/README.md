# 陆战因果片段 v1

独立研究。默认旧 BattleState 的 gameplay_port=null。新场景显式启用 land-gameplay-slice-v1；战斗仍由原 resolver/SegmentWork 计算。没有正式游戏接入。

Windows 已有研究树的演示命令：

```powershell
$lab = 'D:\programs\WWO\research\military\wwo-gameplay-20261010T1217'
$godot = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe'
& $godot --headless --path $lab --script res://experiments/war_resolver/gameplay/run.gd -- --scene=S1 --seed=71 --variant=valid --actor=squad --quota=0 --seconds=1800 --output=D:/programs/WWO/research/military/demo/S1
& $godot --headless --path $lab --script res://experiments/war_resolver/gameplay/run.gd -- --scene=S2 --seed=109 --variant=valid --actor=platoon --quota=7 --seconds=1800 --output=D:/programs/WWO/research/military/demo/S2
& $godot --headless --path $lab --script res://experiments/war_resolver/gameplay/run.gd -- --scene=S3 --seed=71 --variant=valid --actor=soldier --quota=31 --seconds=1800 --output=D:/programs/WWO/research/military/demo/S3
```

新检出先运行 `& $godot --headless --editor --path $lab --quit`。只在研究树运行。seed 为整数；quota 为 0/1/7/31；seconds 为 0..86400。场景使用同一份四节点拓扑、两个许可路线和既有任务/知识/权限/物流接口。没有场景分支计算杀伤。

|参数|含义|
|---|---|
|scene|S1守点；S2隐藏断桥与延迟报告；S3入掩体、自动撤回与持续世界|
|variant|autonomous无玩家意图；valid有效意图；invalid无权限意图；condition改变真实条件；S1 reserve高级分配；S2 wait守住受阻节点、slow_reports延迟信息；no_supply取消有限补给|
|actor|读取已存在人物的合法视图：soldier/scout/squad/platoon/recipient/company。该参数不转移身份、权限、资源或知识，也不改输入脚本|
|inputs|UTF-8 JSON 文件，按既有人物ID配置少量意图，覆盖该人物的默认脚本。每人最多16条；“接受”仍需权限、送达与实际执行|
|output|输出目录；省略则只打印中文摘要。四个输出文件见下表|

一个 S3 个人输入脚本已保存为 `example_inputs.json`。可追加参数：

```powershell
--inputs=D:/programs/WWO/research/military/wwo-gameplay-20261010T1217/experiments/war_resolver/gameplay/example_inputs.json
```

|输出|读取边界|
|---|---|
|person_timeline.json|PERSON_VISIBLE；只含该人物自己的输入、合法反馈、局部身体后果及真正收到的报告|
|debug_truth.json|DEBUG_TRUTH；真实物理和计算原因。禁止交给玩家provider|
|world_result.json|DEBUG_TRUTH；已提交的正式结果、任务、资源账与决策记录|
|summary_zh.txt|人物内容与研究真相分段标记；描述发生、所知、权限和后果|

记录含 event_id、effective_time、learned_time、phase、subject_ref、cause_refs 与前后变化。时间不使用采集顺序。相同边界的因果依赖以 cause_refs 为准；phase 为来源阶段的排序标签，不替代依赖关系。报告保留 observed_at/sent_at/received_at。查询不给世界增加一次结算；PENDING只给旧提交时刻。

行为变化：到达不等于局部控制；守点可完成但继续守位/开火；撤回路线结束不免伤；真正脱离后不吃旧contact伤害；失败、取消和替代有终止与常驻后续规则。隐藏路况先阻挡执行，再由当地来源生成报告。已知路况供人物的下一次机会使用。原空间版本的首次障碍休眠缺口已在新目标路径关闭。

个人后果：绑定已有 ordinary_soldier，占原班 effective 的一份能力。匿名能力+成员健康始终等于原班剩余能力。同一次 incoming 火力剂量按段首份额与暴露分配，合计只一次更新损失/装备/总账。无个人随机死亡账、免费人员、补人或治疗。take_cover 需收到本地掩体报告并完成移动；掩体倍率0.35。wait维持随组。组移动前自动完成一次返回集合点。健康是连续伤病能力，不能解释为具名死亡。

支持包络与数字见 PROTOTYPE_RULES.md。含因果个人/目标的叶不允许不支持的split/merge/coalesce；错误输入被明确拒绝。远处仍可沿原LOD规则聚合。空间与编制层级各自运行。正式存档、完整个人死亡/控制接续、海空协同、正式地图与观察程序留待后续。

局部检查：gameplay/tests.gd、participation_tests.gd、scenario_tests.gd。检验种子用 `scenario_tests.gd -- --holdout`；347/2027在规则固定后才运行。benchmark.gd仅测本轮成本，并且是唯一开启新增窄计时的入口；演示及普通测试关闭计时与上轮probe。最终完整验证状态见本轮 CONCLUDE_ZH.md，不能由本README推断已经通过。

复用来源：Task1–8 README、四份MILITARY_*_REQUIREMENTS、iteration/DESIGN、FINAL_ACCEPTANCE与Windows封存结论。当前检出与本地研究根未找到单独的DESIGN_MAP/TRANSFER_NOTES或参考索引；未用最新main运行源码补齐。采用共享内核、状态/事件、局部索引、收到知识与单次结算；不新增通用规划框架。没有需要新增论文结论的缺口，因此没有重开外部综述。

冻结运行HEAD：3052a0c142b4c97b53e5600ef772ac1bf9887ac0。本机已实跑上列三种场景/人物/quota组合和example_inputs的company查询。原统一门与封存状态以CONCLUDE_ZH.md、FINAL_VALIDATION.json为准。headless有限调用上限10000000；到限返回BLOCKED。新24h检查入口为 `res://experiments/war_resolver/gameplay/long_tests.gd`。
