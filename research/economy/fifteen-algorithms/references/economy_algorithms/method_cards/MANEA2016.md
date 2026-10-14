# MANEA2016

[Matching Theory](https://ocw.mit.edu/courses/14-16-strategy-and-information-spring-2016/53dbe8d681978367f9c04182aa3c9b97_MIT14_16S16_Matching.pdf)

实际阅读：Slides7–8,12–13,18–19: marriage model, DA steps/Theorems1–3。版本：MIT14.16 Spring2016; slides datedJune27,2016。

原问题为双边一对一偏好匹配。输入各方严格偏好与可接受对象，状态为暂持proposal及已拒集合，输出无阻挡对匹配；提议方逐次提给未拒最佳对象，接受方暂持最喜欢proposal并拒其余。参数为偏好/配对域而非可调价格；主体不需读他方完整排序但集中执行者取得偏好档案。前提固定偏好和一对一、暂持可被替换；证据为课堂定理/算法，不是实体交付。原文复杂度此阅读范围UNKNOWN；独立每边至多提议一次O(|E|)提议数，若比较索引预处理另计。

WWO已有accept形成真实责任，不能当可任意替换暂持proposal。独立反例：将已accept订单在新更好offer来时直接拒掉，会重复释放库存/资金。纯离线偏好反例可用，生产交易runtime DEFER；稳定不是公平、最小费用或按日履约。TEST_AS_REFERENCE。
