# GOOGLE_ASSIGN2026

[Linear Sum Assignment Solver](https://developers.google.com/optimization/assignment/linear_assignment)

实际阅读：Cost matrix/Create solver/Add constraints/Solve/Display results; integer restriction and page license。版本：Official docs updated2026-03-18; installed version not inspected。

原问题为一对一整数费用最小指派。中央求解器知道全部提供的边/费用；输入二部图及费用，状态为solver，输出optimal匹配/总成本或INFEASIBLE、POSSIBLE_OVERFLOW。规则每侧每节点至多一个配对并最小化费用；实例需要全匹配，非多单位煤钢。自由行为参数无，费用/边是实例数据，金额单位需统一并整数化。证据为官方工程示例，未安装/运行；复杂度本页UNKNOWN，不把“更快”量化。

独立WWO最小入口为离线小图基准，仅传已知可行边，runtime中央指派DEFER。反例：未知供应商费用更低，离线选择它不能证明买方可见；两买方各需1而供方容量1，一对一边之外须共享库存再核对。TEST_AS_REFERENCE信息/容量反例。
