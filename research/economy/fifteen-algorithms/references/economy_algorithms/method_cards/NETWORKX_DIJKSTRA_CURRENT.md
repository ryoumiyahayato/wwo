# NETWORKX_DIJKSTRA_CURRENT

[single_source_dijkstra](https://networkx.org/documentation/stable/reference/algorithms/generated/networkx.algorithms.shortest_paths.weighted.single_source_dijkstra.html)

实际阅读：API parameters/returns/Notes, rendered lines93–155。版本：stable documentation displayed NetworkX3.7; accessed2026-10-08, no package installed。

原问题：给定加权图的单源最短路径。输入G、source、可选target/cutoff及边权；输出距离和路径（目标未给时为字典）。权重相加，权重函数收端点和边属性，None隐藏边；文档警告负权及浮点误差。方法为Dijkstra；已读API未读内部实现。状态至少距离/路径结果，其他内部状态UNKNOWN。单位须同一距离、静态时间或成本；cutoff同单位。信息为调用者提供的全图，非自动局部观察。工程文档无渐近界，本卡不将经典堆界冒充该实现测量；全部路径物化成本另计。

最小适配仅离线已知子图路径基准，不安装依赖、不改路由。WWO容量预留、批量单位、日期和shipment责任均在路径函数之外；该weight签名不是到达时间函数。独立反例：当前最快边明日关闭，以当前静态权重作路线不能证明到货日可行；两单共享容量仍需同一资源账。

许可/再分发：UNKNOWN for retrieved page; no source code copied。仅保存自写笔记，无全文、图片或代码复制。

暂定：TEST_AS_REFERENCE；任何运行机制均DEFER，本轮未实现或运行。
