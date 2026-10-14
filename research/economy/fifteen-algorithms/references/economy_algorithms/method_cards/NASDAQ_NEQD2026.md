# NASDAQ_NEQD2026

[Nasdaq Derivatives Markets: Market Model & Functionality](https://www.nasdaq.com/docs/2026/09/14/NEQD-Market-Model-3.3.0.pdf)

实际阅读：§5.2.1.1.1 printedp36; §5.2.1.2.3–4 printedp45–46; selected closing-auction information rules。版本：revision3.3.0 effective14September2026;130pages。

原问题：特定衍生品订单分配制度。输入产品/交易阶段及已接受订单，状态为同价队列、显示/隐藏/隐含数量与时间戳，输出成交和剩余量。部分产品按价格时间，期权可按比例且按显示量降序依次计算、剩余比例向上取整；不能缩成统一FIFO。集中撮合按最大成交量、最小不平衡等顺序选单一价格；边际量再依其优先规则分配。参数为产品规则、tick、时段等，单位合约与货币/合约。证据为交易所规则，复杂度UNKNOWN，未实现全部细节。

WWO只能把分配制度差异作为研究参照，不能因产品规则权威而证明买方公平。独立反例：同价大单与两小单在FIFO/比例分配下得到不同份额，即使总量守恒，sink损失仍不同。证券撮合不定义煤钢住房的日期/运输或雇佣合同。2026规则不能反推2019ABIDES完全实现同一交易所版本。

许可/再分发：Nasdaq document; license not established, no fulltext/code retained。仅保存自写笔记，无全文、图片或代码复制。

暂定：TEST_AS_REFERENCE；任何运行机制均DEFER，本轮未实现或运行。
