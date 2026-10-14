# WWO M2.6.1 — Arabia authority coverage closure

施工完成，等待人工视觉验收。**没有标记 MAP RECOVERY CLOSED。** 本轮目标日期 1900-01-01，仅解决原 neutral feature 的 authority coverage。

## 【NEUTRAL BEFORE】

`arabia_undelimited_desert_1900`：15 exterior，全为 GEOGRAPHY_PRESENT_NO_POLITY。下表索引从 0 开始，顺序绑定冻结 geography SHA256，不是 15 个新国家。

| component | location | longitude bounds | latitude bounds | decision |
|---|---|---|---|---|
| 0 | Aqaba 海岸边缘 | 34.9000—35.0037 | 29.3158—29.5315 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 1 | Yanbu／北 Hejaz 沿海 | 35.9164—37.2572 | 24.8633—26.9671 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 2 | Hejaz—Tihama 红海沿岸带 | 37.6016—43.4673 | 12.7263—24.2822 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 3 | 北部游牧区—Najd 外缘—东南部连续内陆残余 | 36.3515—55.6661 | 14.5660—33.9068 | APPROXIMATE_AUTHORITY_ASSIGNED；内部小残余仍未知 |
| 4 | Mahra 东部／Qishn—Nishtun 边缘 | 51.5861—52.4870 | 15.5465—16.2329 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 5 | Masirah 对岸／Janabah 沿海 | 57.8154—58.2552 | 20.1700—20.6128 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 6 | Sur／Janabah 沿海 | 58.6622—59.5295 | 22.6337—23.5689 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 7 | Hajar／Batinah 地方部落边缘 | 56.1531—58.4803 | 23.6599—25.9009 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 8 | Ras-al-Khaimah／Qasimi 沿海 | 55.5651—56.0168 | 25.4835—25.9668 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 9 | Abu Dhabi 东北岸小残余 | 54.6982—55.0352 | 24.7854—25.0568 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 10 | Abu Dhabi／Bani Yas 沿海 | 53.4067—54.6451 | 24.0442—24.7258 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 11 | Dhafrah／Bainunah 西缘 | 51.7367—52.3528 | 23.9560—24.2294 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 12 | Al-Hasa 沿海小残余 | 50.1486—50.2634 | 25.6015—25.6987 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 13 | Al-Hasa／Qatif 沿海 | 49.9939—50.2500 | 25.7170—26.7425 | APPROXIMATE_AUTHORITY_ASSIGNED |
| 14 | 北 Al-Hasa／Jubail 沿海 | 48.5386—50.0514 | 26.7472—28.6549 | APPROXIMATE_AUTHORITY_ASSIGNED |

## 【AUTHORITY RESOLUTION】

所有新增记录保留 authority_confidence、authority_basis、source_date、target_date=1900-01-01、approximate=true。只声明游戏地图的近似地方行政/影响范围，不声称测绘边界、排他性主权或现代 nation-state。没有 nearest-country / Voronoi / 现代边界输入。

| component | assigned authority / type | confidence | representative visual | source |
|---|---|---|---|---|
| 0 | 汉志沿海行政 / LOCAL_DYNASTIC_AUTHORITY | 0.7 | res://assets/historical_flags/1900/ottoman_1844.png / METROPOLITAN_FLAG | [1900](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_206) |
| 1 | 汉志沿海行政 / LOCAL_DYNASTIC_AUTHORITY | 0.7 | res://assets/historical_flags/1900/ottoman_1844.png / METROPOLITAN_FLAG | [1900](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_206) |
| 2 | 汉志沿海行政 / LOCAL_DYNASTIC_AUTHORITY<br>帖哈麦地方部落 / LOCAL_TRIBAL_AUTHORITY | 0.7, 0.55 | res://assets/historical_flags/1900/ottoman_1844.png / METROPOLITAN_FLAG<br>#927348 / COLOR_FALLBACK | [1900](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_206)<br>[1892 events / 1900 account](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_213) |
| 3 | 阿纳扎地方部落联盟 / TRIBAL_CONFEDERATION<br>巴尼亚斯／马纳西尔 / TRIBAL_CONFEDERATION<br>达瓦西尔绿洲与部落 / LOCAL_TRIBAL_AUTHORITY<br>哈尔卜／朱海纳地方部落 / LOCAL_TRIBAL_AUTHORITY<br>穆拉／哈杰尔地方部落 / LOCAL_TRIBAL_AUTHORITY<br>奈季兰／阿西尔地方权威 / LOCAL_TRIBAL_AUTHORITY<br>沙马尔／拉希德影响区 / LOCAL_DYNASTIC_AUTHORITY<br>南阿拉伯地方谢赫与部落 / LOCAL_TRIBAL_AUTHORITY | 0.65, 0.65, 0.65, 0.55, 0.55, 0.55, 0.6, 0.4 | #ab8152 / COLOR_FALLBACK<br>#ae9453 / COLOR_FALLBACK<br>#bd9658 / COLOR_FALLBACK<br>#818c48 / COLOR_FALLBACK<br>#ab7059 / COLOR_FALLBACK<br>#96714f / COLOR_FALLBACK<br>res://assets/historical_liveries/1900/rashidi_authority_1900.svg / APPROXIMATE_HISTORICAL_VISUAL<br>#9a7baa / COLOR_FALLBACK | [1900; nineteenth-century observations synthesized](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_154)<br>[1908; earlier Al Nahyan continuity corroborated by 1904 historical precis](https://www.qdl.qa/en/archive/81055/vdc_100023515713.0x00003d)<br>[1873 observations / 1900 synthesis](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Footnote_44)<br>[1917 synthesis explicitly referencing nineteenth-century travelers](https://qdl.qa/en/archive/81055/vdc_100023514406.0x00003a)<br>[1873-1904 historical precis; earlier events documented](https://www.qdl.qa/en/archive/81055/vdc_100023526379.0x000047)<br>[1870 journey / 1900 account](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_145)<br>[1900](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_154)<br>[1900 contemporary synthesis](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_143) |
| 4 | 马赫拉地方行政边缘 / SULTANATE | 0.6 | res://assets/historical_flags/1900/uk_union_1801.png / METROPOLITAN_FLAG | [1886 treaty / 1933 compilation](https://qdl.qa/en/archive/81055/vdc_100023462215.0x00000b) |
| 5 | 贾纳巴地方部落 / LOCAL_TRIBAL_AUTHORITY | 0.65 | #5b8a80 / COLOR_FALLBACK | [1898](https://www.qdl.qa/en/archive/81055/vdc_100000000831.0x00024d) |
| 6 | 贾纳巴地方部落 / LOCAL_TRIBAL_AUTHORITY | 0.65 | #5b8a80 / COLOR_FALLBACK | [1898](https://www.qdl.qa/en/archive/81055/vdc_100000000831.0x00024d) |
| 7 | 阿曼哈杰尔地方谢赫 / LOCAL_TRIBAL_AUTHORITY | 0.6 | #698048 / COLOR_FALLBACK | [1900](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_78) |
| 8 | 卡西米沿海地方行政 / LOCAL_DYNASTIC_AUTHORITY | 0.55 | #93545a / COLOR_FALLBACK | [1892 exclusive agreement; official retrospective history](https://rakheritage.rak.ae/chapters/the-beginnings-of-the-uae/) |
| 9 | 巴尼亚斯／马纳西尔 / TRIBAL_CONFEDERATION | 0.65 | #ae9453 / COLOR_FALLBACK | [1908; earlier Al Nahyan continuity corroborated by 1904 historical precis](https://www.qdl.qa/en/archive/81055/vdc_100023515713.0x00003d) |
| 10 | 巴尼亚斯／马纳西尔 / TRIBAL_CONFEDERATION | 0.65 | #ae9453 / COLOR_FALLBACK | [1908; earlier Al Nahyan continuity corroborated by 1904 historical precis](https://www.qdl.qa/en/archive/81055/vdc_100023515713.0x00003d) |
| 11 | 巴尼亚斯／马纳西尔 / TRIBAL_CONFEDERATION | 0.65 | #ae9453 / COLOR_FALLBACK | [1908; earlier Al Nahyan continuity corroborated by 1904 historical precis](https://www.qdl.qa/en/archive/81055/vdc_100023515713.0x00003d) |
| 12 | 哈萨沿海行政 / APPROXIMATE_HISTORICAL_AUTHORITY | 0.7 | res://assets/historical_flags/1900/ottoman_1844.png / METROPOLITAN_FLAG | [1900 / observed journey](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_110) |
| 13 | 哈萨沿海行政 / APPROXIMATE_HISTORICAL_AUTHORITY | 0.7 | res://assets/historical_flags/1900/ottoman_1844.png / METROPOLITAN_FLAG | [1900 / observed journey](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_110) |
| 14 | 哈萨沿海行政 / APPROXIMATE_HISTORICAL_AUTHORITY | 0.7 | res://assets/historical_flags/1900/ottoman_1844.png / METROPOLITAN_FLAG | [1900 / observed journey](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_110) |

第 3 块约占原 neutral mesh 面积的 92.6%，不能整块视为单一 authority。本轮按北部 Anazeh/Ruwalla、Shammar/Rashidi 贡属影响、Hejaz 西缘 Harb/Juhaynah、Dawasir 绿洲、Najran/Asir 地方权威、Al Murrah/Bani Hajir、Bani Yas/Manasir 和南部地方谢赫的历史影响区解析。南部记录是多个独立地方社区的地图聚合，**不是新创设的部落联盟或统一政府**；其边缘延伸依据最弱，confidence=0.40。

source_date 区分观察/事件与出版年：Janabah 为 1898 档案；Murrah/Hajir 为 1904 汇编记录的更早活动；Dhafrah 为 1908 附近日期资料，Al Nahyan 连续性另由 1904 historical précis支持；Harb 的 1917 handbook 明确援引较早 Burton/Doughty 观察，仅回用长期部落分布，不回写 1916 年 Hejaz 王国身份。Qasimi 使用政府博物馆对 1892 exclusive agreement 和十九世纪王朝连续性的历史说明。

label_anchor 只是地图文字位置，不伪称地方部落拥有国家首都。帝国/宗主关系在 sovereignty_imperial_relation 中另记；controller_id 和 diplomacy_identity 为空，is_runtime_polity=false，没有 economy / population / save 实体。

## 【TRULY UNRESOLVED】

仅剩第 3 个 exterior 内一处中央沙漠小残余。证据范围：49.5—50.2°E、20.0—20.7°N；在冻结 mesh 分辨率上对应一片既有 source triangle，sample=50.1248°E、20.4457°N。

1900 年当代记述明确缺乏该深沙漠内部的地方权威信息；检索的部落/沿海资料能证明外围水井、绿洲、季节迁徙与地方控制，却不能可靠推出此核心由哪个谢赫管理。因此继续标为 TRULY_UNRESOLVED；这是知识缺口，不是断言这里历史上没有人类政治关系。

## 【MAP RESULT】

原连续 neutral gray ring 已消失。按冻结 source mesh 的球面三角形面积统计：

- before neutral：约 1,284,967 km²。
- after neutral：约 9,257 km²。
- neutral 减少：**99.28%**；剩余约 0.72%。

这些面积只度量现有游戏 geography/mesh 的覆盖变化，**不是历史国土面积估计**。影响区由 historical content 决定。既有三角形整体按照其经纬度采样归属分配；没有切割、增加三角形或 exterior。分区边缘因此呈现既有 mesh 的近似分辨率，不声称其锯齿是历史国界。新增影响区交界不制造 geographic boundary，也没有改变冻结的细边界绘制。

视觉全部调用既有 HistoricalVisualResolver：Hejaz / Hasa 采用 Ottoman metropolitan authority visual，Mahra 小边缘复用英国保护关系 visual，Shammar 外缘复用既有 Rashidi livery，其余地方 authority 使用命名、稳定的政治色 fallback。fallback 色不宣称历史旗色，没有新建旗资产或 flag 系统。

## 【GEOMETRY ACCOUNTING】

| count | before | after |
|---|---:|---:|
| features | 161 | 161 |
| source exteriors | 1634 | 1634 |
| loader | 1634 | 1634 |
| projection retained components | 1634 | 1634 |
| render retained components | 1634 | 1634 |
| geometry_lost | 0 | 0 |

原 neutral feature 的 15 exterior 未改。冻结 baseline hash 对比确认：两个 geography JSON、原始政治记录、M2.6 的 12 条 authority、GeographyLoader、GlobeProjection、GlobeController、shader、flag tone/UV配置和抽查的 Formal 脚本均未改变。原有所有 visual records 和 bindings 的内容比较均相等；catalog 仅追加新 authority bindings。

[Formal manifest](D:/WWO/wwo/local-artifacts/arabia-authority-closure/after_manifest.json) / [冻结 baseline](D:/WWO/wwo/local-artifacts/arabia-authority-closure/frozen_baseline.json)。source、projection、render 计数指 exterior 组件保留，不要求背面地块在当前视图可见。

## Modified files

- `data/world_map/historical/arabia_authority_coverage_1900.json`：15 条分区 authority、15 个 exterior 决策、一个局部 unresolved mask；独立于 geography。
- `data/world_map/historical/political_visuals_1900.json`：只追加地方 authority bindings / 稳定 fallback 色。
- `data/provenance/historical_source_registry.json`、`historical_fact_evidence.json`：新增一组内容 hash admission。
- `scripts/content/administrative_loader.gd`：读取新证据，校验冻结 geography hash，按 component 与历史影响区解析 authority；JSON component 索引显式转为整数。
- `scripts/presentation/map/political_layer.gd`：允许同一 feature 的部分 authority 记录，并支持显式 label_anchor。
- `scripts/presentation/map/globe_renderer.gd`：为既有 triangle 消费 content 返回的 authority；不改变 source mesh、triangulation、projection、horizon、shader 或 UV。没有让 renderer 推断政治事实。
- `tools/historical_data/build_arabia_authority_coverage.py`：可重复生成 authority 内容/绑定/provenance，不写 geography。
- `tools/map/capture_arabia_authority.gd`：正式 scene 截图和只读覆盖/accounting；Godot 生成 `.uid`。
- `docs/map/arabia_authority_coverage_closure_m2_6_1.md`：本报告。
- `local-artifacts/arabia-authority-closure/`：六张截图、manifest、日志、冻结 baseline、`.gdignore`。

没有改 scripts/formal、UI、simulation、economy、population 或 save/load；没有新增 geography、flag asset 或大战略系统。Southern Africa / BSAC 保持原样；重复公司旗只记为以后 visual-group polish。

## Validation

最终 `git diff --check`、Godot 4.6.3 headless editor parse 与 Formal capture 均退出 0。日志扫描未发现解析、类型、脚本加载或运行错误。Formal capture 再次确认 161 features、1634 source/loader/projection/render exteriors、geometry_lost=0。没有 benchmark、长时间 simulation 或大型新测试体系。

## 【SCREENSHOTS】

全部来自正式 Formal scene，1900-01-01 00:00，1280×720。before 是 M2.6 最终 Formal capture 的原像素副本（相同 Arabia focus/zoom）；没有重建或编辑 before 图片。

### Arabia before

![Arabia before](D:/WWO/wwo/local-artifacts/arabia-authority-closure/before_arabia.png)

### Arabia after

![Arabia after](D:/WWO/wwo/local-artifacts/arabia-authority-closure/after_arabia.png)

### Nejd / Rashidi close-up

![Nejd / Rashidi close-up](D:/WWO/wwo/local-artifacts/arabia-authority-closure/after_nejd_rashidi.png)

### Gulf

![Gulf](D:/WWO/wwo/local-artifacts/arabia-authority-closure/after_gulf.png)

### Yemen / Hadramaut

![Yemen / Hadramaut](D:/WWO/wwo/local-artifacts/arabia-authority-closure/after_yemen_hadramaut.png)

### World scale

![World scale](D:/WWO/wwo/local-artifacts/arabia-authority-closure/after_world.png)

停止施工，等待人工验收。不进入 M3，不开始 Formal Legacy Severance。验收通过后再标记 MAP RECOVERY CLOSED。
