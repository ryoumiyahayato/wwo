# ATALAY2011

[Network structure of production](https://enghinatalay.github.io/network_structure_of_production.pdf)

实际阅读：Modeling the In-Degree Distribution, printed5199–5200; Estimation opening5201 (PDF2/printed5201); no figures interpreted。版本：PNAS108(13),5199–5202;March29,2011; author PDF includes SI not fully read。

原问题为企业供需关系度分布。全局生成模型知道N、度k、均度m；状态为企业节点/边及度统计，输入上一期网络，输出退出、重接和新增网络。按q均匀退出，失去端点的边以r随机、1−r按度偏好重接，进入边有δ份连旧节点，净增长g；五参数q/m/r/δ/g由关系微数据估计。单位是节点/关系计数和期间概率，不是交付量或可靠性。证据为解析近似及经验校准，未重跑/读完SI。原文计算复杂度UNKNOWN；全图更新须计访问边，不能给本地买方O(1)假保证。

独立WWO反例：两供方同度但一方连续迟交，全局按度模型无法辨识可靠性；更不能给buyer未知端点。最小局部入口仅以实际联系/到货历史更新关系身份，具体可靠性评分DEFER。TEST_AS_REFERENCE统计与行为边界；随机全网重连DEFER。
