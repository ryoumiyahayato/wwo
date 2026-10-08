# 军事算法最新交接索引（2026-10-08，文档与证据发布）

## 当前结论

- Task9+：LEVEL_3 / COMPLETE 仅成立于历史预登记输入和限定实验验收边界。其代码与证据从精确基线直接继承；本次不重新宣布完整仓库全绿、目标设备性能通过或正式游戏接入完成。
- P1 单步成本研究：E / BLOCKED_BY_CONTRACT_OR_ENVIRONMENT。G0 被精确完整来源和当前环境基线阻塞；G1/G2/G3、G4 完整回归均 NOT_RUN。没有新的军事算法、优化代码、Godot 战争实验或 before/after 性能数据。
- 本次是后来获明确授权的独立 docs-only 远端发布，仅增加本目录的报告和证据。它不恢复环境、不重启研究、不改变既有 PR111 分支，也不 merge、tag 或发布生产版本。

## 读取顺序与历史口径

1. [环境阻塞主报告](STEP_COST_LOCAL_VALIDATION.md)：封存时的实际工作、失败原文和 NOT_RUN 边界。
2. [预登记验收与计量要求](ACCEPTANCE_AND_MEASUREMENT.md)：未来恢复后的研究要求，当前未执行。
3. [Task9 后续十项只读分析](TASK9_FOLLOWUP_READ_ONLY_ANALYSIS_ZH.md)：历史资料读取、静态核对和当时提案。P1 优先、P2 条件性归因以及未来游戏接入事项均是分析/建议，不是新性能证据或已实施改动。
4. [封存 HEADS](HEADS.json)、[封存 README](SEALED_README.txt)、[机器结果](evidence/RESULTS.json)、[来源与文件清单](evidence/source/acquired_manifest.json)。
5. [本次发布 manifest](PUBLICATION_MANIFEST.json)：固定来源、Library 交接身份与各发布文件的字节数、Git blob SHA-1 和 SHA-256。

原封存文件逐字节保留。其 NOT_PUBLISHED / NOT_AUTHORIZED、docs_head 未创建和新 commit 为空，描述的是 05:07:52Z 封存时状态；历史只读分析中的“没有改仓库”也只描述该次分析。现在的授权发布另由本索引及远端新 commit/ref 证明，不将历史字段改写为研究通过。

## 精确来源

- 继承基线/Task9 文档 HEAD：[3515734e5dfdf4bfa04fc0047764f53c380389ed](https://github.com/ryoumiyahayato/wwo/commit/3515734e5dfdf4bfa04fc0047764f53c380389ed)。根 tree：4fdbbeb658b96d1d7bb94bc0b0207c782a9b6ee6。
- 历史最终算法代码：[69fa36d6202b2b0d8e9332406ff57d269749fa0c](https://github.com/ryoumiyahayato/wwo/commit/69fa36d6202b2b0d8e9332406ff57d269749fa0c)。历史验证 checkout：f609b75b4d7711863d8c769f3cfd9667bc84fb59。
- [Task9 固定验收报告](https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/FINAL_ACCEPTANCE.md)、[固定机器门](https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/evidence/final-linux/gate.json)、[固定复现说明](https://github.com/ryoumiyahayato/wwo/blob/3515734e5dfdf4bfa04fc0047764f53c380389ed/experiments/war_resolver/iteration/REPRODUCE.md)。
- [PR111](https://github.com/ryoumiyahayato/wwo/pull/111) 在本次发布前回读为 open / draft / 未合并，head 仍精确 3515734；151 个变更文件。它保留历史 Task9 完整代码与证据，不用本次分支覆盖它。

## 只读环境诊断补充

完整 tree 有 1,814 条记录、1,641 条 blob 路径 / 1,611 个唯一 blob。精确 commit、160 个唯一 tree 对象、368 个已恢复唯一 blob 的内容寻址均复核匹配；389 个落盘文件 SHA-256 与封存 acquired_manifest 一致。当前仍缺 1,252 条路径 / 1,243 个唯一 blob，无 tree 对象缺失。skip-worktree 的 1,252 条仅为索引标记，不代表对象存在。

原获取选择集为 1,417 条 blob 路径，仍缺 1,028 条路径 / 1,019 个唯一 blob；另有 224 条被排除路径也未恢复。仅补中断文件或仅补原选择集，都不能据此宣称完整 Git 对象库已经恢复。

world_admin1.json（blob 0ce36f617f565d4d5c9cf4efb445e8b80876ba02，5,897,821 bytes）只是记录中的读取中断位置，绝非唯一缺失。未定位它通往导入或某项回归的调用链。完整回归的直接缺依赖包括：
- cloud_validate.py 的 REGRESSIONS / 统一验证引用的 tests/vnext/military_strategy_test.gd、tests/codex_audit_regression.gd、tools/audit_1900_commodity_economy.py。
- project.godot 指定的 scenes/formal/formal_world_menu.tscn。

因此当前完整回归无法按原门运行；没有实际运行后得到失败的证据。普通本地 docs commit 失败的对象 59cf7f839d294f5201609560c3ce551bbded78b6 是 .github/workflows/alpha-commodity-economy.yml，也确实缺失。

单次 Transport closed 的根因和请求 ID 未知，不证明源码损坏、算法失败或 GitHub 整体不可用。generic github.fetch 对过大/非 UTF-8 响应有限制；原生 github.fetch_blob 是未验证的候选恢复通道。本次未试恢复、未重试世界数据，也不承诺该通道一定成功。远端按原 root tree 增加文档无需本地补齐这些缺失对象；docs-only 发布成功不等于 G0 成功。

## 后续接入边界

精确完整运行源和依赖仍待另行恢复并建立 G0。随后才可按新的明确实施授权开展同 call 关联、合法容量阶梯、计时边界一致的成本归因。完整游戏接入仍需明确定义观察/火力、control/hold/withdrawn、人物身份与伤亡、权限和已提交时间接口，并建立目标设备与完整回归验收。保持现有物理/知识/命令契约，不能通过扩大容差或改 golden 来获得通过。

## 原交接文件身份

- 主报告 Library ID：libfile_4bfc55d68a208191a4045c97f6c133a6。
- 完整交接包 Library ID：libfile_b6c849a8cd388191a43c17616ec23304；war-step-cost-delivery.tar.gz SHA-256：05424c5b02e5ac0b1927fc008f66fc7c3a9dd3cc682c55f63305ab3c5ac5eb8c。
- 交接包中的原 binary patch 仅增加已封存文档/证据，SHA-256：9799a89062154615a0d64a8fcf6b0a8b4128ec2ebc7f9cfa48c5cb169f5dbec7；不是新的算法补丁。
- Library ID 只是交付身份，不是公开下载链接；本索引不公开任何私有 download URL。
