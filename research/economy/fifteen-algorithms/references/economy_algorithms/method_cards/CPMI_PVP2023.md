# CPMI_PVP2023

[Facilitating increased adoption of payment versus payment (PvP) – final report](https://www.bis.org/publications/facilitating-increased-adoption-payment-versus-payment-pvp-final-report.pdf)

实际阅读：Introduction printedp6/PDF page6 (zero-based5), settlement mechanism and limits; executive-summary context。版本：BIS/CPMI final report March2023; landing page27March2023。

原问题：降低外汇支付一币却未收到另一币的结算本金风险。PvP要求各币最终结算相互以对方最终结算为条件；报告讨论覆盖、流动性和运行时段等约束，不提供单一软件算法。概念输入为已约定的两币支付义务及结算条件，状态为各腿最终性/资金可用性，输出共同最终结算或尚未完成。币额保留各自单位，汇率为B币/A币；时段、可接入币种属于制度参数。证据为机构机制说明，复杂度N/A，不能把基础设施成本报O(1)。

未来小纯函数可校验paired-finality事件，但这是独立适配建议、非报告代码。WWO没有多币账时不新增；现有支付账也不等同完整信用体系。独立反例：先扣A币再遇B腿失败，不能仍报双方已最终结算；把100A+100B记200“现金”同样无单位意义。PvP不保证汇率稳定、交易盈利或无限流动性。

许可/再分发：BIS copyright; no fulltext retained; redistribution terms not fully reviewed。仅保存自写笔记，无全文、图片或代码复制。

暂定：TEST_AS_REFERENCE；任何运行机制均DEFER，本轮未实现或运行。
