# v44 人口开局估算

纽约市等 107 个美国建制城市使用各州原有普查总额内的份额。原数据取 1900 年 6 月 1 日的市界。各州保留原总额及原州级统计口径。地图以确定的地点 ID 关联，不凭同名猜测。[美国第十二次普查，卷一表 XXVII](https://www2.census.gov/library/publications/decennial/1900/volume-1/volume-1-p2.pdf) · [Census Bureau 城市回溯表 13](https://cdn.www.census.gov/library/working-papers/1998/demo/POP-twps0027.html)

巴黎地图地点直连现有巴黎市账户。该账户使用 1896 和 1901 年法国普查插值得到的 1900 年初人口，保留塞纳省总额。

年龄与性别优先使用 v42 的原有分组。只为原来完全未建组、且有可比资料的开局池引入比例估算。模型保留原资料地域、日期、分组和样本量。原有宽年龄段在计算需求与工时时按区间均分。只有性别的记录保留年龄未分配。

社会属性沿用原有口径。家庭阶层和行业参与率作为单维情景分配，主要区别有证据的建制城市与普通地区账户。原有职业统计可能包含家属、工业身份或非劳动人口。职业和阶层分组不构成个人交叉记录。语言、文化、宗教只对可建立优势群体情景的缺口分配部分人数，其余仍未分配。具体比例是模型参数。1900 年前后的汉语方言、殖民地宗教与菲律宾群体分类用于约束类别选择。[中国语言史研究](https://www.cambridge.org/core/books/dialect-and-nationalism-in-china-18601960/chinese-language/7DC1B2524503429368131985B88E5020) · [菲律宾 1903 年人口普查卷二](https://www2.census.gov/library/publications/decennial/island-areas/1903/1903-census-phillipine-islands-vol2.pdf)

家庭需求由地区食物组合、年龄、职业构成、气候代理、家庭阶层和宗教食物偏好等参数计算。交叉统计缺失时，阶层篮子使用所选范围的平均结构调整，独立边际分布仍保留。燃料和住房按消耗与占用分别计算。同一份主食热量在家庭用面粉、购买成品和其他主食之间分配。商品数量使用正式市场单位。缺少商品或服务 ID 的项目保留物理量。美国 1901 年消费调查、西欧工人账簿、日本住户资料用于约束消费类别与模式，具体日率和阶层系数是游戏情景参数。[美国劳工统计局调查史](https://www.bls.gov/opub/hom/cex/history.htm) · [WWO 原始食品账](HISTORICAL_FOOD_CASES.md)

工时和行业人力为带年龄上限的潜在量。工时参考 1870 至 1913 年工时研究的区间。相邻行业分摊、自用比例和每人 4 公顷是模型条件。美国小麦、黑麦、玉米和马铃薯另保留 1900–1909 年全国平均每公顷吨数。当前生产配方只有每批人数和产物。并行批次由人力上限计算，各配方是互斥情景。行业生产仍取决于土地、设备、投入品和排程。[Huberman 与 Minns，历史工时表](https://personal.lse.ac.uk/minns/huberman_minns_eeh_2007.pdf) · [USDA 历史作物单产表](https://upload.wikimedia.org/wikipedia/commons/d/de/Crops_and_markets_%28IA_cropsmarkets1712unit%29.pdf)
