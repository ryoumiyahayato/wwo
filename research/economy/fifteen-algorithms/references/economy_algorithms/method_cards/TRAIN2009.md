# TRAIN2009

[Discrete Choice Methods with Simulation, second edition](https://eml.berkeley.edu/books/choice2.html)

实际阅读：Chapter3 §3.1 pp34–37; §3.3.2 pp46–47; Chapter6 §6.1 pp134–136。版本：Author-hosted second edition;Cambridge2009。

原问题是离散选择概率与估计。研究者观察属性而非全部随机效用；纯logit假设独立同分布极值误差，规则Pi=exp(Vi)/Σexp(Vj)，V由β和属性构成。输入备选集/属性/β，状态为效用参数，输出无量纲概率；效用只识别差与尺度，货币属性系数需单位声明。混合logit另以f(β)积分条件logit，容许异质性与相关，但增加分布参数与模拟抽样。正文红蓝公交例指出IIA限制。证据为理论章节，未复现估计。原文完整复杂度UNKNOWN；独立单次softmax O(J)、R次抽样O(RJ)，不含估计训练。

WWO最小入口（独立）：先按known供应商/预算过滤，再比较选择；不是强制引入随机数。反例预算5、商品价10，有限效用仍获正概率；复制相同报价又会膨胀份额。报价身份去重与硬可行性必须先于效用。TEST_AS_REFERENCE反例；logit/混合logit运行选择DEFER。两章计同一书一个来源。
