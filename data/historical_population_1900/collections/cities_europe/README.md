# 1900 年前后城市、法国与德意志帝国人口

- Chandler 的 AD_1900 栏有 631 个五万人以上城市记录。50–99,999 人为 350 个，100,000–199,999 人为 140 个，200,000–499,999 人为 98 个，500,000 人以上为 43 个。年标来自研究者汇编，各地城市边界不同。原表缺值和五万人以下城市不在本摘录内。[Reba、Reitsma、Seto 数据](https://doi.org/10.6084/m9.figshare.2059494.v3)
- 原表的国家标签和地理编码存在歧义，例如 Riga 被标为 Russian Federation，Dhaka 被标为 India。Barrow、St. Helens 和 Lawrence 对应的美国地理编码存疑。1900 年俄勒冈州 St. Helens 普查 258 人，堪萨斯州 Lawrence 10,862 人。保留原值和争议标记。[美国普查第 65 号公报，表 8](https://www2.census.gov/library/publications/decennial/1900/bulletins/demographic/65-population-incorporated-places.pdf) [堪萨斯州表 5](https://www2.census.gov/library/publications/decennial/1900/bulletins/demographic/24-population-ks.pdf)
- 法国本土 1896 年 3 月 29 日、1901 年 3 月 24 日各有 87 个省级地区、362 个区和国家合计。省级按实际日期线性内插后逐省取整，1900 年 1 月 1 日总数 38,852,684。两次省级原数之和分别比原国表多 48、少 100；开局省级之和比独立国表内插少 62。Savenay 对应后来的 Saint-Nazaire 区，原记录保留表名、区代码和名称。[INSEE 人口普查 DBF](https://www.insee.fr/fr/statistiques/2653233) [法国大西洋卢瓦尔省档案](https://archives.loire-atlantique.fr/44/fonds-conserves/c_20581)
- 德国年鉴列 1895 年 12 月 2 日、1900 年 12 月 1 日在场人口。两期均覆盖 25 邦、帝国直辖的阿尔萨斯－洛林和普鲁士内部 14 区。柏林在普鲁士内部单列。26 个一级单位两期分别合计等于原国表，开局内插分项取整合计 55,619,152，比独立国表内插多 2。[德意志帝国统计年鉴 1902，印刷第 1 页](https://digi.bib.uni-mannheim.de/fileadmin/statjahrb/514401303_1902/pdf/514401303_0010.pdf)

运行 `python extract.py` 从研究者原始 CSV 和法国 DBF 提取选定列。德国原表的人工数字摘录为 german_census.csv。运行 `python build.py` 重建 observations.jsonl 和两国开局，依赖仓库的历史身份目录。来源、精确列号和授权见 sources.json。

city_equivalences.csv 记录跨来源的同城身份和边界关系。city_key 是 Chandler 编号，member_unit_id 指向原观察单位，locator 指向其中一个具名表行。统计城市数时按 city_key 去重。人口仍由原记录的日期和口径解释。纽约合并前市界、合并后的五区及研究者估计同属一个城市身份；加尔各答和开普敦的核心、郊区合计各有单独记录。分立城镇和同名异地保留独立身份。洛桑 1900 年普查为 46,732 人，低于 Chandler 摘录门槛。

city_chinese_names.csv 给出 15 个城市的汉字和历史罗马字名，包括北京／Peking、廣州／Canton、廈門／Amoy。每行列出同一地名实体的 MCGD LocID、中文 NameID 和罗马字 NameID。该表只记录名称对应关系。[Christian Henriot，Modern China Geospatial Database 2.2](https://doi.org/10.5281/zenodo.8063584)


美国普查局 Gibson 表 12、13 的市界人口已和 Chandler 同州同名单位对应。Kansas City 按汇编的 Missouri 标签对应密苏里州，堪萨斯州同名城市独立。两座 Portland 按州分别对应。Dayton、Minneapolis、Richmond、Toledo 的州名可核，但坐标与人口普查局地名表冲突；编者坐标加注存疑并保留。[美国普查局地名表，2024](https://www.census.gov/geographies/reference-files/time-series/geo/gazetteer-files.2024.html)
