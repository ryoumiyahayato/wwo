# WWO WAR ALGORITHM — TASK9+ BOUNDED ITERATION

Base / final code HEAD / final docs HEAD: `c4731a33177660b83c6490f41fe42dcbe7cfa7bb` / `69fa36d6202b2b0d8e9332406ff57d269749fa0c` / 文档HEAD见PR最终head及交付`HEADS.json`；不在commit内自引用未知SHA。
Environment / Godot: Linux x86_64，`/workspace/wwo`，Python3.12.14，Godot `4.6.3.stable.official.7d41c59c4`。
Effective execution budget used / estimate quality: 约285/600有效分钟（近似）；恢复未重置。暂停约6分钟、初始平台等待13秒、一次断连不足1分钟及环境切换约1分钟不确定等待单列。提前完成全部必需门，未等待凑满十小时。
M0 / M1 / M2 / M3 / M4: PASSED / PASSED / PASSED / PASSED / PASSED。
Highest accepted level: LEVEL_3。
Overall: COMPLETE（本轮限定实验验收；冻结基线经济golden未通过范围保持，整个仓库并非全绿）。
Original gameplay constraints preserved: 十二条原始约束保持；唯一writer，所有tracked差异仅实验目录；人物有限知识/权限、唯一表示、资源/损伤/关系守恒、同一world time、纯读无推进。
Integrated causal scenario actually run: main seed71，1800秒，118条事实trace；至少三轮原路命令、改道命令、有限补给请求真实走Task5/6/7/8入口。
Longest game-time run actually completed: 24游戏小时，100cell/400underlying leaves，seed71/109各自正常及quota1/7/31；初17/末15活跃格、2几何focus，275个人物机会。7日持续压力DEFERRED / NOT RUN。
Resource / authority / knowledge / LOD findings: 长CLI弹药1508、燃料1640、备件1620的初始量与当前+已耗+在途量相等；临配旧命令t47拒绝，隐藏桥况不进provider，损毁卸载重载不恢复；400leaf始终唯一表示。
Per-call budget bound / largest indivisible step: 每调用≤quota个实际primitive，接触/排序/incoming/事件/报告/fold/退休记录均续接；本次长对照最大调用37.157ms，最大primitive 37.045ms（apply:apply_units，seed109，quota1）。native元数据/容器与原domain/provider步骤有容量包络，非硬wall帧SLA。
Storage/queue growth: 诊断ring4096/分页256，人物知识与权威身份/decision历史保留增长；长run pending初12→末0，Godot static memory≤512MiB门；不称总内存常量。
Predecessor regressions and platform caveats: Tasks1–8/五组43948/0，8旧Linux独立进程hash及4正式探针对相同；新增640/0，audit31/0、WorldData46测试通过。统一等价步骤只有economy golden原两项失败，日志931bytes逐字等于M0；PowerShell与Windows NOT RUN。
New blockers and deterministic reproducers: 无新增blocker。退眠清理反例c8原失败、69fa36d修正、相关43/0及本次完整门均通过；原脚本/失败与修正日志保留。平台中断报告INCOMPLETE，未拼接成PASS。
Draft PR / artifact location / publication status: 唯一Draft PR https://github.com/ryoumiyahayato/wwo/pull/111 ，base为冻结Task8分支；代码、报告和证据已push并只读核实open/draft/unmerged（交付checkpoint e81cfff）；bundle验证与base临时索引patch应用检查通过。最终文档HEAD与SHA256见交付HEADS.json，不merge。
Human visual acceptance: NOT REQUIRED / NOT RUN。
Production integration status: NONE。
Next smallest authorized follow-up: 尚未授权实施，仅列建议。对当前最大支持scope的native元数据/容器操作增加独立最坏容量压力例，先预登记成本与停止条件。

本任务使用普通云端实施与同任务检查点，没有原生Goal控件、定时器、隐藏续跑或守护进程。用户请求6.1-sol/xhigh；未找到实际模型/推理元数据查询入口，实际状态UNVERIFIED。未将提示词当运行元数据。

## 阶段与证据

| 阶段 | 可检出代码检查点 | 本轮结论与证据 |
|---|---|---|
| M0 | d84e2a1（记录；代码起点为Task8） | 实际冻结Linux基线，known failure独立复现；evidence/m0-linux |
| M1 | 069e3f028ddf2dfe2bdb88e05fdad0de1bda2535 | 分叉连通、桥与结构地形、相邻合法接触/标签中性、局部损毁持续；空间190/0 |
| M2 | 0c93b66338c88fb31a05ff66444fa6d423b38f41 | 六seed因果对照，循环契约56/0、联动116/0 |
| M3 | 78d39a4原门；69fa36d最终清理修正 | 可续接同kernel、24h/集中事件/局部性/存储；最终完整门支持修正版本 |
| M4 | code69fa36d / validation checkout f609b75b4d7711863d8c769f3cfd9667bc84fb59 | 完整退出0，95实际步骤中只有1已知经济失败步骤；evidence/final-linux/gate.json |

源码gd/py指纹在最终完整运行前后相同，并严格等于code69fa36d的Git对象。
最终命令在`../continuous/README.md`及gate.json逐步骤记录，未执行原PowerShell，
只执行相同Godot脚本/退出规则/fatal matcher的Linux等价步骤。开发与历史重复运行
不累加成独立check数量；中断的旧wrapper明确NOT_ACCEPTED。关键raw副本和SHA256
映射在`evidence/final-linux/raw-index.json`，完整原日志保留于builds/task9-m4-final-recovered。

## 实际因果链

| 游戏秒 | 实际事实 |
|---:|---|
| 0 | company收到旧桥况AVAILABLE报告；掌握明确合成既定路线，非truth自动刷新 |
| 10 / 25 | 人物提交第一轮路线意图 / Task7延迟送达后执行 |
| 15 / 47 | Task5临配生效 / 旧platoon命令送达时因权限重验拒绝 |
| 120 | bridge_BD外部损毁事实APPLIED，后续通行关闭 |
| 150 / 197 | 执行实际受阻，有资格局部来源观察 / 报告延迟47秒后人物收到 |
| 325 / 340 | 第二轮有限知识改道 / 延迟命令权限重验后执行 |
| 640 / 670 | 第三轮Task6请求10有限弹药 / 预留与外部ETA到达 |
| 732.525 | unit_000实际沿返程、A-C-D到达D，时间/燃料未退回，无位置瞬移 |
| 955 / 1270 / 1585 | 其余常规机会keep，不反复复制同一任务 |

结构化事件ID、原因引用、主体、时刻、输入/执行及scope在main.json；中文timeline.txt
由GDScript事实模板生成。无断桥、慢报告、无补给、纯预览、重复旧报告、关闭循环均
有真实因果对照。keep机会使segment73 vs67，最差物理切分差1.6098922e-6；不称零成本。

## 成本与局部性

原M2 before400dense最大prepare677.986ms、apply667.280ms，同刻1000事件批次20.577ms；
独立before源码指纹和原日志在m3-linux。after下表为60游戏秒两segment，quota256，
6次试验去掉首个预热，表中p50/p95是各次试验内部所有call分位数的5次范围，max跨5次。

| dense表示数 | call p50 μs范围 | call p95 μs范围 | max call ms | max primitive ms | advance总ms范围 |
|---:|---:|---:|---:|---:|---:|
| 100 | 910–950 | 1564–2075 | 5.077 | 4.167 | 1005.414–1064.993 |
| 400 | 888–936 | 1503–1776 | 19.635 | 18.536 | 18215.607–19322.005 |

before总吞吐为300游戏秒，after60秒，不能直接相除。续算分派与GDScript排序有吞吐
成本，不声称更快。真实密集接触仍平方增长，after400计算160000有向接触，未截断。
最大不可中断步骤包括固定unit操作、native容器/ID快照、≤64leaf原domain/测试provider；
scope1024表示、active metadata4096、cell/scope128、route history4096、pending100000
等限制超限明确BLOCKED，保留旧提交time及待算事实。本次最大native ID快照400。
非任意插件执行沙箱；不承诺1024满密度吞吐或用户设备帧率。所有query通过PENDING门，
可信kernel回调可形成局部报告；provider始终只有copied received claims/权限metadata。

10000休眠area/30000squad：活跃areas1、segments1、实际接触800、units examined6760
及total work19280均相同；构建1.218→334.890ms、静态内存约26.9→135.4MB另列。
稀疏400：候选402、实际接触2；1000未来仅3到期不扫997，1000混合同刻事件原phase/ID
保留、全部t10不漂移。大地图100次摘要读不settle/物化；focus重载只额外物化2leaf，
无关cell099两cohort保持；一个空间fact只必要祖先更新。

异质活跃40leaf样本：同质4/4可聚合、4表示、候选16/接触8；异质3/4可聚合、13表示、
候选169/接触44，实际一次推进1.629→8.101ms。长run背景197/198可聚合，异质pair
保留详细；初201/末202表示覆盖唯一400leaf，没有强行聚合。六seed单侧/双侧/局部/
不同切换时点的LOD最差3.508256%（seed733、red单侧、unit_000 casualties），距离
差5.55e-17km；沿既有20%资源尺度floor1/0.20km/趋势界限，不提高容差、不推导普适
observer无偏。加载2几何focus不等于所有格全部高精度。

最终独立CLI长run：构建70.475ms（admission48.768、coalesce/focus20.674、geometry
子集0.023ms，子集不重复相加），advance25566.874ms，query/result114.920ms，JSON
编码25.718ms、stdout6.774ms/1054698bytes。机器证据区分这些成本，未把昂贵整理藏进
advance之外。CLI最近p50/p95只为最后最多4096call，最大值覆盖全运行。原CLI与完整
对照日志都注明不同测量口径。

退眠反例独立手算400单位→80000有向接触：c8旧代码整批释放仅403cleanup，maxcall
41.532ms，exit1；69fa36d逐记录退休后80403cleanup，原quota1反例exit0。
最终新增43条反例断言覆盖三quota、密集400、同步物理等价、当前published表保留。
原失败/测试字段错误/SCRIPT ERROR被driver拒绝的日志均保留，不挑选只绿结果。

## 存储与未做范围

| 类别（seed71 24h） | 初→末 | 净增长/游戏小时 |
|---|---:|---:|
| 权威event身份 | 12→294 | 11.75记录 |
| received知识claim | 2→564 | 23.4167记录 |
| 信息消息 | 3→567 | 23.5记录 |
| decision历史 | 1→275 | 11.4167记录 |
| 诊断trace | 8→2097 | 87.0417记录；ring上限4096 |
| pending因果队列 | 12→0 | 本输入无积压；峰值非逐tick采样 |

live序列化294540→297281bytes，身份7203→37007，知识2897→753833，decision历史
104→7546263bytes；各类完整初末/单位小时增量在metrics.json。序列化字节不是RAM。
独立CLI最终Godot static约89.7MB；对照harness保留参考世界/快照，约百至数百MB，
不可当独立世界常驻内存。权威身份、知识、decision/context未压缩，增长保留；不删
历史使人物失忆、不清幂等造成重放。容量达到512MiB或pending100000明确停止，非
无限时长常量内存承诺。积压不丢事件、不跳消耗、不冻结一方来追目标时间。

空间仅有限局部距离/遮挡许可与分叉图、合成50km包络、属性未历史校准；非完整连续
2D/GIS。外部物流ETA独立既定路径，完整交通物流未完成。旧control语义仍粗，人物
战斗后果、正式AI/doctrine/Organization/Economy/Geography/UI/存档迁移未实现。
7日持续输入、Windows、导出、人类试玩没有运行，生产接入NONE。

领取、Godot导入、quick/acceptance/stress命令与其他平台基线方法见REPRODUCE.md。
工作区只打包实验tracked差异与有限证据；不打包缓存/引擎/整盘，不覆盖未知生产UID。
