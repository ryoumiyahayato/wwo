# QE_MCCALL_CURRENT

[Job Search I: The McCall Search Model](https://python.quantecon.org/mccall_model.html)

实际阅读：§53.2–53.3.3; equations53.2–53.7 and T/compute_reservation_wage code; rendered lines98–359。版本：maintained QuantEcon lecture; displayed last changed2026-09-12; not original1970 paper。

原问题：失业者何时接受工资。主体看到当期offer并已知有限工资分布q；报价IID，接受后永久同工资，拒绝得c，无限期折现β。状态是当期w/值向量v；输入q,c,β,w集合，输出接受/拒绝及保留工资。Bellman取w/(1−β)与c+βE[v]较大者；反复更新至容差，w≥保留工资时接受。自由参数含β,c,q及工资网格，数值容差另列。w,c单位货币/期；值为折现收入。证据是动态规划教学推导及代码，未复现图表。

成本原文未给渐近界；独立代码计数：共享点积一次，每轮O(n)时间、O(n)值向量，迭代次数受容差/β影响，非总O(n)。可提取离线工资接受纯函数。WWO差异：技能、有限合同、雇主竞争和未知工资分布不在此简化域。独立反例：相同当期工资但一个人看到本地坏行情、另一个拥有完全已知q，不能用统一全球q替二人决策；接受阈值也不产生具体职位。劳动模块以后再研究。

许可/再分发：UNKNOWN for this page; no license inferred from online access。仅保存自写笔记，无全文、图片或代码复制。

暂定：DEFER；任何运行机制均DEFER，本轮未实现或运行。
