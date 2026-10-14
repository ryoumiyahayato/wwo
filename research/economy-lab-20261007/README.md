# WWO Economy Lab

独立的 WWO 经济数量模型与算法研究仓库。Round2已成为可复现研究基线；
Round5已合并，当前研究分支开展Round5B可执行采购释放与承诺协调实验。原算法、fixture、报告和
Round2实验结果保持不变。

基线标识：`inventory-round2-2026-10-07`。来源和限制见
[BASELINE.md](BASELINE.md)，全部 156 个来源文件的 SHA-256 见
[source_manifest.json](docs/source_manifest.json)。

## 安装与完整验证

只需要 Python 3.12 和标准库，无第三方依赖。已在 Windows Python 3.12.14
运行；GitHub Actions 使用 Ubuntu 和 Python 3.12。

```sh
git clone https://github.com/ryoumiyahayato/wwo-economy-lab.git
cd wwo-economy-lab
python verify_baseline.py
python verify_round3.py
python verify_round4a.py
python verify_round4b.py
python verify_round4c.py
# Round5研究分支新增完整验证。
git switch research/demand-planning-round5
python verify_round5.py
# Round5B独立研究分支。
git switch research/executable-planning-round5b
python verify_round5b.py
```

统一入口协调既有命令，运行原 8 项测试、新 9 项测试、两组 200 日原实验、
全部 33 组 600 日对照，检查来源和全部 139 份输出的 SHA-256 与文件集合。
输出 Python 版本、基线标识、状态、summary hash，并以非零退出码报告失败。
每次运行保留到新的 `.local/verification-*` 目录，包含原始输出、日志及
`verification.json`；不会覆盖来源证据。可指定 `--output-dir artifacts`。

原 runner 用平台默认文本模式写 JSON。Windows 产生 CRLF，来源是 LF；统一
入口仅在 Windows 对生成 JSON 的 CRLF→LF 字节进行额外哈希比较，保留原始
文件和原始哈希，并明确报告哪些文件不是直接字节匹配。CSV 不做任何转换。
`--strict-bytes` 禁止此兼容比较；Linux CI 使用该参数，要求所有输出直接
逐字节匹配。原始 CSV 自带 CRLF，其 Git 路径例外防止自动转换破坏既有哈希。

## 原有入口

以下命令在仓库根目录开始，`python3` 也可替代 `python`。

```sh
cd economy_quantity_lab
python -m unittest -v test_economy.py
python run_experiment.py --output-dir ../artifacts/baseline
cd inventory_round2
python -m unittest -v test_inventory_comparison.py
python run_inventory_comparison.py --output-dir ../../artifacts/round2 --execution-log ../../artifacts/round2_execution_log.json
```

原打包脚本仍保留，可以在各自目录运行 `python package_experiment.py` 或
`python package_inventory_comparison.py`。后者在原始 LF JSON 的 Windows
检出上会严格拒绝 JSON 换行差异；需要完整包的严格复现时使用 Linux，或使用
统一入口查看明确区分原始与换行兼容结果的报告。不要修改原脚本来掩盖差异。

## 研究证据与边界

源码和 import 关系保持来源布局。两份历史报告原样保留：
[原 200 日报告](economy_quantity_lab/REPORT.md)、
[Round2 600 日报告](economy_quantity_lab/inventory_round2/INVENTORY_COMPARISON_REPORT.md)。
本轮保留全部 9,129,147 字节、156 个来源文件，包括原四份 CSV 和 Round2 的
135 份结果，因为既有严格打包验证依赖完整树。后续运行放在忽略目录；CI 将
完整再生输出作为有期限的 Actions artifact 上传，不逐轮提交 ZIP 或大量 CSV。

CI 证明当前提交仍可复现已声明行为。数量残差为零是账目一致性证据，不能证明
模型真实性。H0 固定目标、H1 时延相关目标、buffer 对照与 coverage diagnostic
均属有限实验；诊断只读，H1 尚未批准为 WWO 正式经济规则。

原Round2长期未发订单没有处置机制；后续Round3/4A分别研究取消与确认。
转单、多供应商、价格、工资、家庭、金融均未实现。这里不复制 WWO UI、Globe、人物、政治、军事、SaveGame、GameClock、
完整历史库或正式世界模拟，也不自动整合到 WWO。

PR #1已按明确授权合并，annotated tag `economy-lab-v0.2-baseline`指向实际main
`60278ee7f1703ef5aec6cb7933a2bcf6073e1038`。历史导入结论仍保留于BASELINE。

## Round3订单承诺与处置

新增实验位于`economy_quantity_lab/order_round3/`。四个供给场景分别运行R0/R1/R2，
另加两个无承诺R1控制，共14×600日。18项新增检查、两次完整59文件字节复现及
旧基线验证由CI实际执行。运行`python verify_round3.py`前也运行旧验证。

R1只排除可信供给中的逾期余额；R2显式取消未发余额，再向原供应商FIFO尾部新订。
两者都不能在断运下恢复物质供给。新事实、结果和限制见
[Round3报告](economy_quantity_lab/order_round3/ORDER_COMMITMENT_REPORT.md)与
[当前研究边界](docs/RESEARCH_BOUNDARIES.md)。完整逐日/订单轨迹输出进入忽略目录和
CI artifact，Git保存小型summary、hash manifest及因果证据。

Round3 PR #2已合并，v0.3 annotated tag冻结合并后的基线；其策略仍未获正式采用。

## Round4A供应商准入与取消确认

`economy_quantity_lab/supplier_round4a/`将采购请求与真实接受订单分离，比较S0全接受
和S1基于当前运力的共享三日ATP。拒单不进入订单账，取消请求一日后确认，未确认
仍计入pending。10×600日、四个握手专项、缺货反证探针及29项检查实际运行。
`verify_round4a.py`再生两次44文件并核对冻结hash；提交前运行全部三个统一入口。

实体结果未改善，持续停运S1保留need320而非不可履约pending；超载仍有backlog1470。
运输ATP不能保证供应商有货。报告与Gate见
[Round4A报告](economy_quantity_lab/supplier_round4a/SUPPLIER_ADMISSION_REPORT.md)。
Round4A PR #3已合并，tag `economy-lab-v0.4a-supplier-admission`冻结该基线；
其历史实现及结果保留。Round4A没有第二供应商或WWO集成。

## Round4B有限候选匹配与切换

新增`economy_quantity_lab/multi_round4b/`，S2把当前库存承诺与运输槽同时约束接受量。
D有独立煤矿来源、60/日运力、4日lead；M0只A，M1按已知公开offer依次补remaining
need，M2只在逾期订单取消确认后向另一已知supplier替代。未知D不查询，外部事件显式发现。
原step/FIFO/receive仍复用；新增逐日输出按日索引，历史四轮文件保持不变。

实际14×600日、33项检查、两次115文件直接字节复现由`verify_round4b.py`协调；
提交前运行全部四个验证入口。临时冲击M1改善本轮服务，但D单独不足80 coal/日，
M2在断供case没有改善实体服务。见[Round4B报告](economy_quantity_lab/multi_round4b/MULTI_SUPPLIER_REPORT.md)。
建议下一步研究有限信息获取；独立PR等待审查，没有价格、可靠性score或WWO集成，
本轮不自动开始下一轮。

## Round4C目录、搜索与延展性

Round4B PR #4已合并，tag `economy-lab-v0.4b-multi-supplier`冻结基线。
新增`search_round4c/`支持2/10/50/200煤源、粗目录索引、Q0/Q1、LOCAL/REGIONAL/WIDE、
1/3/7日时延、3个结果与30日scope冷却。交付后才知悉候选，offer仍通过S2；采购只访问known。
实体源/账/全量CSV仍随N增长，matching与这些成本分开计量。
18×600日、32项检查、两次184文件复现及五commodity/双buyer接口probe由
`verify_round4c.py`协调；提交前运行全部五个入口。
EXTENSIBILITY_GATE PASS只支持表达扩展；Wide发现成功但仍backlog1282，下一轮建议
Production Planning / Demand Propagation。见[Round4C报告](economy_quantity_lab/search_round4c/SUPPLIER_SEARCH_REPORT.md)。
独立研究PR等待审查，不自动启动下一轮或接入WWO。

## Round5需求传播与时间化计划

Round4C PR #5已合并；tag `economy-lab-v0.4c-supplier-search`冻结真实合并基线。
新增`planning_round5/`把Demand、ProductionPlan、MaterialRequirement、ProcurementNeed
及原PurchaseRequest分离。P0复现原控制，P1只传播当前backlog，P2使用过去20日需求率，
P3另按明确ETA分配供应。日期ID、共享投入覆盖和真实未结采购暴露防止滚动计划重复承诺。

52×600日包含A–J、恢复与H=5/20探针；另运行三个固定E17信息的因果诊断。
40项检查、两次784文件字节复现由`python verify_round5.py`协调；提交前运行全部六个入口。
WIDE在H10的末backlog为1282/1282/3/1268；P3的时序表达并不保证改善服务。
见[Round5报告](economy_quantity_lab/planning_round5/DEMAND_PLANNING_REPORT.md)。
PLANNING_EXTENSIBILITY_GATE仅检查表达与实现约束；候选未正式采用，不接入WWO。

## Round5B可执行释放与采购承诺协调

Round5 PR #6已合并；annotated tag `economy-lab-v0.5-demand-planning`冻结main
`98ead27160fec2eecb545f3bc9f67e690e13bbf1`。新增`release_round5b/`复用原世界与P3
生产计划，分离firm horizon、projected visibility tail、稳定绝对日期bucket与真实供给暴露。
X0保持旧P3；X1按当前公开offer的release-by协调采购；X2仅确认取消后替代stale pending。

39×600日、45项检查、两次完整629文件直接字节重放由`verify_round5b.py`协调。
施工前后均运行全部六个旧入口；历史169项检查和结果不改写。另有真实12日部分发运
专项、固定E17信息的三组600日因果对照及多lead/多阶段接口probe。
Wide H10最终backlog1268/0/0，但step-up为6/141/141，取消没有改善stale场景服务。
结果、时序证据、性能和结构限制见
[Round5B报告](economy_quantity_lab/release_round5b/EXECUTABLE_PLANNING_REPORT.md)。
EXECUTABLE_PLANNING_GATE只支持扩大研究网络；不批准候选正式采用或集成WWO。
