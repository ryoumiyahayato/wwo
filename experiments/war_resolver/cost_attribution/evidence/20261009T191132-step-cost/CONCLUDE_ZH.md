本轮保留原运行算法，归因为PARTIAL；没有实施候选，未接入生产。

完整Task8树已核验，取得远端冻结43f35…完整树；用户ZIP声明的47个运行/依赖文件逐项一致，按源码等价恢复。未取得b411846…和文档36e629d…原对象。真实运行HEAD、冻结指纹与本地诊断提交见HEADS_AND_SOURCE.json；外部ZIP校验期望值未取得，只记录实算值及包内45项匹配。

既有main、71/109、1800秒反馈场景重复显示如下工作。累计值来自诊断ON，采样估计有偏差，不能当作OFF占比：

|阶段|每run频次|累计口径/典型观测|对象和实际工作|证据|
|---|---:|---|---|---|
|prepare:candidate_query|4596|1/16估计约21ms|本地scope/源unit游标；最终663候选|工作强，时间探索|
|prepare:candidates|942|1/16估计约18–19ms；采样max142µs|663实际候选检查，源unit ID可关联|部分|
|apply_units|349|全采约14ms；max2.445ms|279次写入/复制，9493顶层键及210路线历史项|数量强，复制内因未隔离|
|due决策|99中6次|同call父原语和五个child span|company六次机会，62个claim输入计数|选定窗口支持|
|release_jobs/末次|420/1|释放段约2ms，末次8个incoming项|279个plan项及阶段间550个incoming项|本窗口非主因|

宽诊断扰动从约翻倍降到约30–40%，仍过大；最终窄配对中位变化为71 −0.72%、109 +8.86%，负值不表示加速。OFF完成同区间API中位166/175ms；全样本保留，五次不保证稳定p95。新增数据有界且不保留world/unit/job强引用；句柄、诊断数据和公开结果释放分别复核，非native回收承诺。API边界pending峰值6、末尾0、提交滞后0。

唯一聚合对照的候选663→658、单位读取4467→4435，同时物理/知识变化，无法隔离收益。决策成本又分散于构建、复制/provider、验证和发令回调，故不进入最小修正；5%采纳门未改、未启用。

Windows完整门及24h/seeds71、109/normal、quota1/7/31通过，本机旧测试失败0；旧资源退出诊断保留。正式因果/状态契约通过，原始混合trace逐序列仍不同。历史37ms未归因，当前偶发约7ms外层值也仍有未知墙钟成分。没有目标帧预算、全容量组合或正式玩法结论；因证据不足以支持修改而封存，完成后停止。

云端10项文本实际字节已核验；压缩证据已创建且Git blob SHA一致，但两次有界读取未成功，未取得远端原始字节复核，因此云端封存为PENDING，完整交付包留本地，停止重试。

SOURCE=VERIFIED_SOURCE_EQUIVALENT；WINDOWS_BASELINE=ESTABLISHED；ATTRIBUTION=PARTIAL；RUNTIME_CHANGE=NONE；VALIDATION=PASSED_WITH_DECLARED_BASELINE_LIMITS；CLOUD_EVIDENCE=PENDING；PRODUCTION_INTEGRATION=NONE。
