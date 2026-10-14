# MIT_DELS2009

[Dynamic Economic Lot Sizing Model, ESD.273J](https://ocw.mit.edu/courses/esd-273j-logistics-and-supply-chain-management-fall-2009/8c56e1d0cd08c9034a85b72f35ab45a8_MITESD_273JF09_lec04.pdf)

实际阅读：Slides21–28: assumptions/ZIO/consecutive-demand blocks/arc cost/shortest path; graph not visually read。版本：Fall2009 course; some slide copyright2008; author attribution limited to visible credit。

原问题为有限T期单品批量费用最小化。规划者先知全部dt与Kt/ct/ht，状态为期末I/批次，输出逐期下单量；零交期、无短缺、无容量约束。连续需求块用订单起点i到终点j弧计setup+采购+逐期持有费用，最短路径选块；ZIO支持在适用模型中不同时结转库存和开新批。参数费用、确定需求与T，量为同一item单位，费用货币，持有货币/件/期。证据大学算法；slide28提O(T²)及更快算法，文本重叠，不将乱码O(T)读成承诺；独立预计算累计费用后DAG O(T²)。

WWO反例：今天需1、实际交期2，零交期最优计划不能履约；未来dt只能是声明forecast，不冒事实。小函数仅离线费用基准，TEST_AS_REFERENCE；运行优化DEFER，不能移除既有accepted责任。原WW1958未读原方法。
