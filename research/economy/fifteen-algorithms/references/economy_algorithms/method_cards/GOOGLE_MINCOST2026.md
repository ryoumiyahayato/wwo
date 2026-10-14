# GOOGLE_MINCOST2026

[Minimum Cost Flows](https://developers.google.com/optimization/flow/mincostflow)

实际阅读：Overview/flow conservation; define data/add arcs/set supplies/solve/status; complete Python example; footer license。版本：official documentation last updated2026-03-18UTC; not installed package version。

原问题：给定网络的低成本可行货流。输入每边端点、容量、单位成本及节点带符号供给；状态为求解器图和流，输出逐边流/成本/状态。约束是流出−流入=节点供给、边流不超容量，目标Σ单位成本×流量。示例采用整数数据，同质单一货流、静态容量及已给出的完整图；成本是货币/货物单位，供需容量必须同单位。参数属于实例而非新增学习旋钮；实现为SimpleMinCostFlow接口示范。文档未给内部算法渐近复杂度，记UNKNOWN，不猜求解器界。

最小用途是已知小图的离线可行性基准；全世界路网、未知offer、未来供需不能借求解器注入企业。该静态示例不定义装运/抵达事件或共享容量跨期预留；多商品体积换算另需模型。独立反例：两买方各自找到容量1的同一桥，却各承诺1，分别最优不构成联合可行；流出供给亦不能凭计划生产物资。

许可/再分发：page CC BY4.0; code examples Apache2.0, except otherwise noted。仅保存自写笔记，无全文、图片或代码复制。

暂定：TEST_AS_REFERENCE；任何运行机制均DEFER，本轮未实现或运行。
