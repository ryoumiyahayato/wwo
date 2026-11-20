# Inventory Round2 研究基线

基线标识：`inventory-round2-2026-10-07`。这是来源保真的首次仓库导入。

## 实际来源

- 来源包：`inventory_comparison_round2.zip`，实际读取于
  `C:\Users\agcrf\Downloads\inventory_comparison_round2.zip`。
- ZIP SHA-256：`81ba17edae1c760322afb9da3a7f5a03de7cc66bc02964cf91a33c5a5213d0c2`。
- 包内 156 个文件，解压文件共 9,129,147 字节；保持全部文件及路径，没有重造缺失代码。
- 所有原始文件 SHA-256：`docs/source_manifest.json`；首次验证的实际命令、版本、
  输出与耗时：`docs/initial_verification.json`。
- 历史报告记载原云端 WWO HEAD 为 `622b260bc641036c23efbf6345a548485ac6c475`。
  这是历史来源字段，并不代表本轮在该检出施工。
- 原 `provenance.json` 列出的 13 个历史文件中，ZIP 仅含必需的 10 个。
  旧 `delivery.json`、`verification.json`、`economy_quantity_lab.zip` 不在来源包内。
  本轮没有获取它们；也没有把新验证记录冒充旧文件。
- 来源包不含报告提到的外置 `package_verification.json`，本轮新增的验证记录
  明确单独命名。历史审计 ZIP 下载失败和未运行独立审计脚本的限制原样保留。

## 复现与字节政策

写仓库辅助文件以前，Windows 上先用 Python 3.14.6 跑原有四个入口，再用
Python 3.12.14 重跑：8+9 项测试通过，2×200 日与 33×600 日实际运行，残差为零。
来源 156 个文件逐字节保持不变。原 4 个 CSV 和 Round2 的 101 个 CSV 直接
逐字节及 SHA-256 匹配；Round2 的 33 份 config.json 和 manifest.json 仅有
Windows 文本模式 CRLF 差异，转为 LF 后全部匹配。首次报告记录原始不匹配哈希。

统一入口保留原始输出，仅对 Windows 生成 JSON 做明确的换行兼容哈希比较。
Linux CI 使用 `--strict-bytes`，不接受此例外。源码不修改，来源 JSON 不修改，
所有 CSV 不转换；已发布 CSV 的 CRLF 使用 Git 路径例外固定。

| 关键输出 | SHA-256 |
|---|---|
| baseline.csv | 828344fa8e1d3169451881ace97fec9c2f8466df8ab6d5c161f4477445d97aa8 |
| transport_shock.csv | c163a79660e9d48e7336f22eff4cd6e34d3a126c5a28d4c8eff24537d203403b |
| baseline_order_trace.csv | 4a8235217f2f433a2cd6da51d923c8f6baa63978cbf5c696195feb74ba80b2a3 |
| transport_shock_order_trace.csv | 6ad6c4896e15f80cc253c65853108a4c5196d9ce1c36da8f1a6746d503232757 |
| inventory_round2/.../summary.csv | 02f43c06496eae20959a1ab89885942bc5dffe272cfb283c17ee70e3ae8c0d02 |
| inventory_round2/.../period_summary.csv | 90731e7f8baec95134c7651d4240a727fd74e8a9ac5fc7de872e733d7d38d336 |

## 算法范围与原结论

继续复用原数量 Simulation。Round2 只计算 H1 目标和读取诊断，没有另一套
到货、生产、发运或记账规则。原 fixture、供应链配方、运输规则、阶段顺序、
H0/H1 和所有原参数保持不变。33 个请求 ID 都独立运行 600 日：A 6、B 24、C 1、D 2。

- H0 固定 B coal 库存位置目标 320。成品目标作用于生产阶段，参数 40 不保证
  日末 B steel 库存为 40。A 的 0/40/80 对照保留这种阶段差异。
- H1 `80 × (lead_time + buffer_days)`，对照时延 2/4/8 与缓冲 0/2/4；L2 b2
  与 H0 等价。增加目标改善某些供货表现，同时增加物资占用，不能宣称总体更优。
- H0 L8 正常末 200 日平均 machine 产出为 5，期末 backlog=2960；H1 b2/b4
  的正常末窗为每日 10，但启动过渡仍有缺口。零缓冲保留周期波动与冲击积压。
- coverage diagnostic 只用当前库存、未发订单年龄、已发 shipment 的数量和 ETA、
  正常计划与已知时延；不为未发订单伪造 ETA，不读取未来运力，也不参与决策。
- 持续停运 C 中库存位置仍为 320，却没有可用来料；期末 backlog=5440。
  旧订单阻止继续补货，长期未发订单没有取消、转单或其他处置机制。
- D 恢复 80 容量时产出回到每日 10，却保留 148 backlog；恢复 100 有余量，
  backlog 第 141 日清零，仓内库存第 156 日匹配原基线。流量恢复、清积压、
  待发余额恢复和仓内缓冲恢复是不同事件。
- 所有组的 coal/steel/machine 数量残差最大绝对值为 0，是按商品和配方的
  账目一致性证据，不是跨商品质量守恒或经济真实性证明。

完整原结论、逐日因果证据与 20 日恢复窗口定义见未改写的
`economy_quantity_lab/inventory_round2/INVENTORY_COMPARISON_REPORT.md`。

## 未实现与尚未验证

没有取消、转单、多供应商匹配、价格、工资、家庭、银行、股票、金融、仓储成本、
需求预测或正式世界集成。没有证明诊断预测实际停产，也没有证明均值代表连续服务。
历史外部独立审计 ZIP 仍不可用，不声称其中脚本已验证本轮。
小实验耗时不能推广为 WWO 全球模拟性能。H1 尚未批准为 WWO 正式经济规则。

本轮没有运行 Godot 游戏旅程、存档、30 日/一年模拟或导出，因为没有修改 WWO。
PR 合并及合并后 annotated tag 不属于本轮已完成状态；后续必须基于实际审批结果。
