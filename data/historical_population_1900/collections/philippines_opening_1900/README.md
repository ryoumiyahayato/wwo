# 菲律宾群岛近 1900 年人口

## 正式开局总数

`observations.jsonl` 的 `ph1900_plehn_archipelago` 引用 `ph_us_census_1900_plehn`。总量为 6,961,339 人。它由 1896 年覆盖人口估计 6,261,339 人，加未查群体 700,000 人组成。前项基于 496 个两期可比镇的增长，并补计新镇。后项是高值估计。美国公报表列日期为 1900-06-01。原方法没有 1896 至 1900 的时间调整。v29 以这项历史估计作为 1900-01-01 开局总数，分省、性别和年龄均留未知。见 [美国第十二次普查公报 149，表 13 后说明及表 17](https://www2.census.gov/library/publications/decennial/1900/bulletins/operations/149-methods-results-area-population.pdf)。

户口统计范围为菲律宾群岛近似，政治范围候选 `cshapes_gw_840`。1900 年 11 月补充条约于 1901 年 3 月 23 日生效。该条约纳入巴黎条约线外的岛屿，包括 Mapun 和 Sibutu。两岛的 1903 年人数为 2,000 和 280。1900 年人数及附岛仍未知。见 [美国国务院条约沿革](https://fam.state.gov/fam/08FAM/08FAM010205.html)及 [1903 普查公报，表 2](https://www2.census.gov/library/publications/decennial/island-areas/1903/philippine-bulletin-1-population.pdf)。

`raw/national_controls.csv` 保存同期替代与后世重建的数值。Federico–Tena v5 开局估计为 7,486,031 人，区间为 6,269,549–8,702,512，质量 D。1899/1900 年中原数为 7,464,696.308 和 7,507,017.458。年份内插使用权重 184/365。1903 端点沿用 1903 年普查的 7,635,426 人，不能从平滑年份值提取战时人口变化。原观测已在 `collections/world` 下。现有 `residual:philippines` 旧估 7,600,000 已退出开局账。西班牙本国省账、美国本土和阿拉斯加的统计范围均排除菲律宾。见 [Federico–Tena 原工作簿及方法](https://www.uc3m.eu/investigacion/federico-tena-population)。

## 地方来源

- `raw/gazetteer_island_groups.csv` 录入陆军部地名辞典印页 27 的八个岛群。公布总人口列合计 6,975,073 人，含原表“Unaligned”24,838 人。原表常住基数源自 1887 年登记，并混合后来的补估。Visayan Islands 的公布总量比两项原列之和多 1,703 人。该数也见于下级 Masbate 组的独立数字。保留印数，不改列值。各岛群份额只作研究。见 [陆军部地名辞典，印页 25–31](https://upload.wikimedia.org/wikipedia/commons/f/f0/A_pronouncing_gazetteer_and_geographical_dictionary_of_the_Philippine_islands_.._%28IA_pronouncinggazet00unit%29.pdf)。
- `raw/atlas_provinces_and_districts.csv` 保存 77 个省、军政区和其他辖区。67 行有数，已报数值之和为 6,654,231。10 行缺报，保留印刷标记。原表无共同调查日，也无全国合计。表前委员会提出的 8,000,000 人为另一次估计。1903 年报告转引 1899 年 Algué 估值 6,703,311 人。未见同表省级加总。各项保持原口径。见 [地图册印页 4–5](https://www.davidrumsey.com/luna/servlet/detail/RUMSEY~8~1~34713~1180326%3AStatistics-and-Description--Atlas-o)及 [1903 普查卷二印页 17–19](https://www2.census.gov/library/publications/decennial/island-areas/1903/1903-census-phillipine-islands-vol2.pdf)。
- `geography_crosswalk.csv` 保存有来源的辖区对应与变更。Batangas、Cebu、Bohol、Leyte、Negros Occidental、Antique 有早期法规延续旧省的证据。岛屿明细和统计定义仍有差异。Negros Oriental 两期都包括 Siquijor。Cavite 在 1903 年包含原表单列的 Corregidor。Mindoro、Tayabas、Manila/Rizal 发生合并或划界。Marinduque 的行政归属改变，1903 仍单列。参见 [1903 普查卷二，表 1–3](https://www2.census.gov/library/publications/decennial/island-areas/1903/1903-census-phillipine-islands-vol2.pdf)。
- 1896 年部分回报在 37 个地区共有 2,790,746 人，男 1,380,256、女 1,410,490。19 个省或岛地区没有回报。已报区亦缺镇。晚期西班牙年鉴原件可从 [西班牙文化部 1898 年年鉴影像](https://prensahistorica.mcu.es/va/catalogo_imagenes/grupo.do?path=350377&posicion=1)和 [美国国会图书馆 1897 年年鉴](https://www.loc.gov/resource/gdc.00519793040/?st=brief)查找。1903 年普查卷二印页 18 转录 1897 年年鉴 5,490,229 人及 1898 年年鉴 5,279,955 人，并标注早期数据覆盖不全。两期年鉴的地方人群与原表合计仍须核对。见 [陆军部地名辞典，印页 31–49](https://upload.wikimedia.org/wikipedia/commons/f/f0/A_pronouncing_gazetteer_and_geographical_dictionary_of_the_Philippine_islands_.._%28IA_pronouncinggazet00unit%29.pdf)。

1916 年政府重印将 Algué 估值归于基督教人口序列。见 [Population of the Philippine Islands in 1916，Previous Censuses and Estimates](https://upload.wikimedia.org/wikipedia/commons/6/62/Population_of_the_Philippine_islands_in_1916_%28poblaci%C3%B3n_de_las_islas_Filipinas_en_1916%29_%28IA_afp8308.0001.001.umich.edu%29.pdf)。

## v42 地域分配

沿用 6,961,339 人的群岛控制。1900 年地图册的六个省合计 1,746,237 人，作为开局估计从未定位余额划出。安蒂克 114,483 人，八打雁 312,192 人，保和 248,000 人，宿务省 504,076 人，莱特 270,491 人，西内格罗斯 296,995 人。地图册没有公布各省的登记日和覆盖定义。1901 年条文用于核对省域延续。地图册对宿务、保和和莱特的邻岛列各有自己的口径。1903 年普查保留原日期与地域，供比较。[1900 年地图册印页 4–5](https://www.davidrumsey.com/luna/servlet/detail/RUMSEY~8~1~34713~1180326%3AStatistics-and-Description--Atlas-o) · [省域对照](geography_crosswalk.csv)

苏里高 89,691 人的早期开局分区继续独立保留。群岛余额为 5,125,411 人。首都与同名城市的范围另查。各省可在 F7 按统计 ID 查询。省的地图边界尚未接入。

## 1903 年普查

已有 `collections/philippines` 保存 1903-03-02 全国、军区和省级观测。全国 7,635,426 人由 6,987,686 个主表登记者和 647,740 个单列村级回报或补估组成。年龄细表覆盖主表。两期地理对应只支持比较。开局至普查日之间的出生、死亡、迁入迁出缺少同范围资料。1903 年龄保留原期。见 [1903 普查卷二，表 1、14、17–18](https://www2.census.gov/library/publications/decennial/island-areas/1903/1903-census-phillipine-islands-vol2.pdf)。
