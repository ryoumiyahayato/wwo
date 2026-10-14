# DEAN_TDSP_UNDATED

[Shortest Paths in FIFO Time-Dependent Networks: Theory and Algorithms](https://people.csail.mit.edu/bdean/tdsp.pdf)

实际阅读：§2 (printedp2), §3.4 (p5–6), §4.1/Figure3 (p7–8); selected §4.2–4.3 boundary。版本：undated author-hosted MIT PDF; often cited2004 but year not verified on title page。

原问题：已知时变路网从指定出发时刻的最早到达。输入有向图和边到达函数a_ij(t)≥t；FIFO要求a非递减。状态为各节点最早到达标签及待处理集合；选最小标签，再以a_ij(EA_i)松弛邻点。输出各节点到达标签/对应路径，时间为共同时间轴。参数是实例函数与出发时刻，无行为遗忘参数。§3.4说明在此FIFO最早到达域等待无益；不等同所有运输制度。§4.1给Fibonacci堆O(m+n log n)、FIFO队列label-correcting O(mn)，函数求值成本须计入；全出发时刻函数问题成本不能套单次界。证据为理论及伪代码。

最小适配可为公开时刻表子图的离线基准；未来事件未知时不得读取后台真值函数。WWO的共享载重、排队拥堵和批次承诺不是外生a(t)自动解决。独立反例：0时出发10时到，1时出发2时到，a下降违反FIFO；不能以此域的“无需等待”排除等待。本轮不建中央调度器。

许可/再分发：UNKNOWN; author-hosted reading only。仅保存自写笔记，无全文、图片或代码复制。

暂定：TEST_AS_REFERENCE；任何运行机制均DEFER，本轮未实现或运行。
