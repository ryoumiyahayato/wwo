# 经济算法研究代理指南

本仓库是独立的 WWO 经济算法研究 Lab。当前固定基线为
`inventory-round2-2026-10-07`，详见 `BASELINE.md`。

1. 不复制另一套核心 Simulation；继续复用 `economy_quantity_lab/economy.py`。
2. 新算法优先实现为明确函数或策略；不为建立仓库重构稳定源码布局。
3. 每个新假设必须与既有基线做对照，记录配置、命令、结果和来源。
4. 不为了得到预期结果修改 fixture、参数、断言或既有结果。
5. 测试通过只证明所列实现约束；不等于经济模型正确。
6. 保留失败实验和异常结果，不强迫每轮实验“改进”。
7. 不自动接入 WWO；研究结论和候选规则需要另行审批。
8. 不扩大到 UI、Globe、正式人物、Political、Military、SaveGame、正式
   GameClock、完整历史数据库或 FormalWorldSimulation 的复制品。
9. 任何经济事实、实验结果和性能说法必须可追溯；缺失输入必须明确记录。
10. 不未经批准重写稳定 baseline；本次 bootstrap 不修改算法、fixture 或原文件。
11. 原始证据按 `docs/source_manifest.json` 保持字节不变。不得刷新 manifest
    掩盖未经批准的修改，也不得通过 headless/测试例外改变产品规则。
12. 在独立短期分支施工，通过 PR 审查；禁止 force push 和改写公开历史。

提交前运行 `python verify_baseline.py`。算法变更还必须报告相对基线的结果变化；
基线升级须有明确授权，新增独立 manifest，不覆盖本轮历史来源。

涉及Round3时还运行`python verify_round3.py`。R0/R1/R2的研究结论见Round3报告；
不得为了改善候选表现添加隐形限单、冷却、优先队列或第二供应商。promise_status
从明确承诺与剩余pending推导；取消只作用pending，原物质结算不重写。

运行输出写入 `.local/` 或 `artifacts/`。当前来源中的完整 135 份 Round2 输出
作为首次导入的固定证据保留，后续批量逐日 CSV 不自动加入 Git。
默认文本为 LF；已发布 CSV 的 CRLF 通过 `.gitattributes` 的具体路径例外保留。
Windows runner 生成 JSON 的 CRLF 与来源 LF 差异由统一入口明确记录，不能用于
忽略内容变化。原源码和来源结果绝不能为跨平台验证而改写。

涉及Round4A时另外运行`python verify_round4a.py`。请求和接受订单分离；
仅接受量进入订单账，拒绝仍为open need。ATP仅为当前运输容量的三日共享槽；
不查询未来场景。取消请求不是取消数量，只有确认才移pending至cancelled。
Round3历史文件及hash保持不变，不通过修改旧结果接受新的行为。

涉及Round4B时运行全部旧入口并加`python verify_round4b.py`。S2只承诺当前
未占用库存和共享运输槽；原FIFO/receive/step不重写。matching只接收known
候选的公开offer，不全局搜索。取消确认前保持跨supplier去重，新增观察用当日索引。

涉及Round4C时运行全部旧入口并加`python verify_round4c.py`。搜索只读粗目录
索引，有时延/数量界/冷却，结果交付才进入known；采购不遍历世界catalog/routes。
分别记录known匹配与物理source/account/export的N成本，不能把接口probe冒充多buyer世界。

涉及Round5时运行全部五个旧入口并加`python verify_round5.py`。Demand是当前已收到
事实；Plan/Requirement/Allocation不制造物资。稳定日期ID配合及时覆盖与真实未结采购
暴露分离，计划过期不能抹掉accepted订单并重新购买同一有限需求组合。P3只用明确ETA；
晚到/无ETA订单保留真实ledger，不覆盖早期投入日期。配方图通用，物理结算不复制。

涉及Round5B时运行全部六个旧入口并加`python verify_round5b.py`。firm生产计划与
projected tail分离；稳定bucket修订不创建第二份责任。先按当前供给日期reconcile，再
按当前公开offer的release-by计算采购；UNKNOWN/late余额仍占真实exposure。
取消请求不释放责任，确认数量上限约束replacement。保持原320 safety、recipe、search、
FIFO、物质结算及全部历史证据。performance分别记录active扫描与只追加的报告档案。
