# Provisional group A decisions — not M2 freeze

| Source | Decision | Reason / allowed use |
|---|---|---|
| KL2003 | TEST_AS_REFERENCE | 共同估值前提与异质买方反例；不采用统一私人上界 |
| BG2007 | TEST_AS_REFERENCE | 可见证据与伪变化反例；ADWIN runtime DEFER |
| BDKS2013 | TEST_AS_REFERENCE | 库存与收入目标差异；CappedUCB DEFER |
| LMN2017 | TEST_AS_REFERENCE | 截断观察等价反例；EWF补货 DEFER |
| XWCW2026 | TEST_AS_REFERENCE | 库存截断对照；完整定价器 REJECT_FOR_WWO_SCOPE |
| ZJYC2023 | TEST_AS_REFERENCE | 有成本探索；Lasso/CPDP DEFER |
| G2016 | TEST_AS_REFERENCE | 日期/在途/责任去重边界；改补货 DEFER |
| SCARF1959 | INSUFFICIENT_ACCESS | 仅元数据，不借用未读证明 |
| CLIFF1997 | INSUFFICIENT_ACCESS | 仅元数据，不借用未读ZIP更新 |

ADOPT_FOR_CURRENT_EXPERIMENT=0；未实现或运行任何本组候选。以上WWO反例为本轮独立推导，待M3预注册与实际执行，不能写成论文结论。参考总体尚未冻结；12类未完成前REFERENCE_FREEZE_SHA保持null。

## Group B provisional extension

| Source | Decision | Allowed use / deferred cost |
|---|---|---|
| BOE2014 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| ZEZZA2004 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| SANCHO2024 | DEFER | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| DEBOER2009 | DEFER | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| FAO2004 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| TRAIN2009 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| BEA2009 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| ACOT2012 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |
| WOLITZKY2022 | TEST_AS_REFERENCE | 方法卡中的域/单位/反例；运行模型与额外参数DEFER |

累计7/15主题；零runtime adoption，未进入M2。GroupA末句12类是其当时快照；当前剩8类。

## Group C provisional extension

| Source | Decision | Boundary |
|---|---|---|
| GOOGLE_ASSIGN2026 | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| MANEA2016 | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| JACKSON2001 | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| ATALAY2011 | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| FP_VERSION_AMBIGUOUS | DEFER | 方法卡或访问缺口；零runtime采纳 |
| G_MRP2006 | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| MIT_DELS2009 | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| SAP_MRP_CURRENT | TEST_AS_REFERENCE | 方法卡或访问缺口；零runtime采纳 |
| GS1993_GAP | INSUFFICIENT_ACCESS | 方法卡或访问缺口；零runtime采纳 |
| WHK1992_GAP | INSUFFICIENT_ACCESS | 方法卡或访问缺口；零runtime采纳 |

当前10/15，剩5类；前组计数为当时快照，保留。全部runtime策略仍DEFER，REFERENCE_FREEZE_SHA null。

## Group D provisional extension — M1 final group

| Source | Decision | Boundary |
|---|---|---|
| QE_MCCALL_CURRENT | DEFER | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| ACEMOGLU_DMP2020 | DEFER | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| GOOGLE_MINCOST2026 | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| NETWORKX_DIJKSTRA_CURRENT | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| DEAN_TDSP_UNDATED | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| KM1997 | DEFER | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| EK2002 | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| CPMI_PVP2023 | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| ABIDES2019 | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| NASDAQ_NEQD2026 | TEST_AS_REFERENCE | 仅方法卡的有限假设/独立反例；零runtime采纳 |
| BCS2015 | DEFER | 仅方法卡的有限假设/独立反例；零runtime采纳 |

累计15/15 DONE_WITH_GAPS；旧组计数为阶段快照，不改写。ADOPT_FOR_CURRENT_EXPERIMENT=0。M2须逐一决定真正借用项并冻结；本组不决定N5。

## M2 final decision (supersedes provisional current-use scope only)

See [m2_reference_review.md](m2_reference_review.md) for all39 dispositions and [claim map](m2_claim_design_map.json). KL2003/BG2007/LMN2017/ZJYC2023 are ADOPT_FOR_CURRENT_EXPERIMENT **for preregistered design only**; runtime algorithm adoptions=0 and executed new experiments=0. Other sources remain bounded TEST_AS_REFERENCE/DEFER/INSUFFICIENT_ACCESS as listed. XWCW algorithm remains excluded for this scope and its textual ambiguity is unresolved.

SIMPLICITY_REVIEW=NO_JUSTIFIED_CHANGE at M2: no A refactor or B candidate justified for implementation yet. M3 must establish observability and causal service costs before reconsideration; N5 is optional. Historical stage claims/counts above stay unchanged.
