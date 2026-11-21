# 美洲历史人口

`raw/` 保留原表摘录和普查数字转录。每条观察保留来源、表页、原统计日期和地域说明。运行 `python build.py` 重建观察和开局候选。城市、人口分类及替代版本保留在观察层。

## 1900 年 1 月 1 日

按实际相隔日数从两端线性插值。权重为开局距起点天数除以端点间天数。有分区时先计算总量，再按分区小数部分从大到小分配整数差额。同余时按分区 ID 排序。几何插值一列展示换用等比例增长的影响。历史漏计、区划变化和计数周期造成的误差还有其他来源。

| 范围 | 端点一 | 端点二 | 线性开局 | 几何插值 | 分区 |
| --- | --- | --- | ---: | ---: | ---: |
| 美国相连本土 | 1890-06-02 · 62,947,714 | 1900-06-01 · 75,994,575 | 75,454,976 | 75,404,863 | 49 |
| 墨西哥 | 1895-10-20 · 12,632,427 | 1900-10-28 · 13,607,272 | 13,447,810 | 13,442,811 | 30 |
| 加拿大自治领 | 1891-04-06 · 4,833,239 | 1901-03-31 · 5,371,315 | 5,304,314 | 5,301,177 | 8 |
| 巴西 | 1890-12-31 · 14,333,915 | 1900-12-31 · 17,318,556 | 17,021,073 | 16,995,110 | 21 |
| 阿拉斯加 | 1890-06-02 · 32,052 | 1900-06-01 · 63,592 | 62,288 | 61,815 | — |
| 夏威夷 | 1890-12-28 · 89,990 | 1900-06-01 · 154,001 | 151,193 | 150,414 | — |
| 古巴 | 1899-10-16 · 1,572,797 | 1907-09-30 · 2,048,980 | 1,585,419 | 1,583,862 | — |
| 纽芬兰殖民地 | 1891-06-01 · 202,040 | 1901-06-01 · 220,984 | 218,307 | 218,203 | — |

## 地域和来源

- 美国原表的五大区合计均已核对。1890 采用包括特别普查的列。俄克拉何马领地与印第安领地合并，处理区内转移。阿拉斯加、夏威夷、古巴和波多黎各为本土以外的观察。阿拉斯加使用联邦普查名义日期作插值锚点。实际访问在 1890 年 2 月至 1891 年、1899 年 7 月至 1900 年 10 月进行。 [美国第十二次普查，卷一](https://www2.census.gov/prod2/decennial/documents/33405927v1ch01.pdf) · [阿拉斯加调查历程](https://www.census.gov/library/stories/2019/07/alaska-remote-areas-always-first-counted-decennial-census.html)
- 美国人口排名表 12、13 各存 100 市镇。1900 年前 78 名达到 50,000 人，第 100 名为 38,307 人。1890 年纽约市为 1,515,301 人。1898 年合并后五区口径的 1890 年回估为 2,507,414 人，1900 年实计为 3,437,202 人。火奴鲁鲁 1900 年有 39,306 人，列在表下注。 [Gibson 第 12 表](https://www2.census.gov/library/working-papers/1998/demographics/pop-twps0027/tab12.txt) · [第 13 表](https://www2.census.gov/library/working-papers/1998/demographics/pop-twps0027/tab13.txt)
- 墨西哥合并下加利福尼亚南北两区。1900 年两区总和为 47,624。1996 回顾表互换南北数据，1930 官方表证实北区为 7,583。两端尤卡坦州均包含后来的金塔纳罗奥。 [1941 年年鉴表 11](https://www.inegi.org.mx/contenidos/productos/prod_serv/contenidos/espanol/bvinegi/productos/historicos/1334/702825140410/702825140410_1.pdf) · [1996 年普查回顾，第 68 页](https://internet.contenidos.inegi.org.mx/contenidos/productos/prod_serv/contenidos/espanol/bvinegi/productos/historicos/2104/702825491406/702825491406_1.pdf)
- 加拿大六省保留，合并魁北克与未组织领地以吸收 1898 年北界调整。另四个组织领地按 1901 年选区范围合并。未组织领地 32,168 和 52,709 保留在观察层，1901 年资料包含新增和改进的计数。1901 年报表中的原住民分类 93,319 已在总数内，印第安事务部门另用行政口径。官方最终总量比同时期年鉴多 264。纽芬兰及殖民普查覆盖的拉布拉多另列，采用纽芬兰统计局历史表的 6 月 1 日参考日。 [加拿大普查原卷](https://publications.gc.ca/collections/collection_2016/statcan/CS98-1901-1.pdf) · [加拿大历史边界](https://www.canada.ca/en/canadian-heritage/services/historical-boundaries-canada.html) · [纽芬兰普查](https://collections.mun.ca/digital/collection/cns_tools/id/158303/) · [纽芬兰统计局历史表 A-1](https://www.stats.gov.nl.ca/publications/Historical/PDF/Historical_Statistics_of_Newfoundland_and_Labrador_V2_N7_1994.pdf)
- 巴西按 1908 年统计局州表重建。1900 年里约联邦区实查被废止，州表采用 691,565 的官方回估。后续 IBGE 回顾口径公布 17,438,434，全国合计比选用表高 119,878，保留为另一来源。帕拉州沿用原报告地域。阿克里在 1903 年划入巴西，两个开局端点均排除。 [1908 年统计局州表](https://bibliotecadigital.mj.gov.br/handle/1/7769) · [IBGE 2000 回顾表 1.4](https://biblioteca.ibge.gov.br/visualizacao/periodicos/308/cd_2000_v7.pdf)
- 古巴普查含松树岛和邻近岛屿。波多黎各 1899 年 7 个部门总计 953,243，通过各部门闭合，部门只有单端直接观察。阿根廷 1895、1914 年 14 省与联邦首都的合计分别为 3,851,542 和 7,555,669。国家观察保留国家领地及补计人口口径的差别。 [古巴普查人口表](https://www2.census.gov/library/publications/decennial/1900/cuba-1907/04771803ch4.pdf) · [波多黎各普查](https://www2.census.gov/library/publications/decennial/island-areas/1899/1899-census-porto-rico.pdf) · [阿根廷官方追溯表，第 98 页](https://biblioteca.indec.gob.ar/bases/minde/17_1937_219.pdf)
