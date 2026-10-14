# ABIDES2019

[ABIDES: Towards High-Fidelity Market Simulation for AI Research](https://arxiv.org/html/1904.12066v1)

实际阅读：§3.1,§3.4–3.5; §8 license; same-seed claim and simultaneous-event caveat both read。版本：arXiv1904.12066v1,26April2019; HTML rendering of v1。

原问题：含消息延迟的证券市场仿真。状态为事件队列、每主体时钟和每证券订单簿；输入带ID/方向/限价/量的消息及延迟，输出成交、剩余接受、撤销确认。最优价格优先、同价最早；部分执行扣余量，撤销只移未成交余量。参数含计算延迟、两两网络延迟/噪声、交易时段、随机种子；单位股份、货币/股、纳秒。主体不能看到GVT，信息随消息交付。论文同时称同种子同配置单线程可重放、同纳秒事件任意排序；前者不证明容器置换或跨版本稳定tie。工程实现证据；复杂度原文UNKNOWN，未运行或复现案例。

最小借鉴为事件先后和余量责任的审计问题，不复制其Simulation。独立反例：把证券fill直接当煤炭到货会跳过运输；将撤销剩余订单误写成撤销已成交部分会破坏账。WWO必须保留accept、shipment、receive和确认的不同事件，确定性需自己的显式验证。

许可/再分发：paper arXiv perpetual non-exclusive license; §8 says code BSD3-clause, current repository not independently inspected。仅保存自写笔记，无全文、图片或代码复制。

暂定：TEST_AS_REFERENCE；任何运行机制均DEFER，本轮未实现或运行。
