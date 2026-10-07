# WWO M2.5 representative political visual closure

视觉日期：1900-01-01。地理来源仍是原有 1900-03-12 CShapes 快照。原政治有效期、运行时政治状态与来源几何均未修改。

【Resolved Visuals】

现有 content / presentation 边界内增加一个 HistoricalVisualResolver。地图仅取最终 resolved visual；历史原始 flag_type、真实 visual_kind、display_role、source、confidence 和近似性分别保留。

优先级为 LOCAL_OFFICIAL_FLAG → COLONIAL_FLAG → PROTECTORATE_FLAG → DOMINION_FLAG → ADMINISTRATIVE_STANDARD → GOVERNOR_STANDARD → COMPANY_FLAG → METROPOLITAN_FLAG → COLOR_FALLBACK。APPROXIMATE_HISTORICAL_VISUAL 另记 priority_role，既保留原用途顺序，也不冒充当日精确史实。

| Territory | Date | display_asset | display_role | Source | Confidence |
|---|---|---|---|---|---|
| Afghanistan | 1900-01-01 | afghanistan_1880.png，原文件 | LOCAL_OFFICIAL_FLAG | [原资产](https://commons.wikimedia.org/wiki/File:Flag_of_Afghanistan_(1880%E2%80%931901).svg) | high |
| Sudan A，仅保留历史／行政资料 | 1900-01-01 | sudan_governor_general_1899.svg | GOVERNOR_STANDARD | [Flag Institute 索引](https://www.flaginstitute.org/wp/wp-content/uploads/2021/02/Badges-of-the-British-Commonwealth.pdf)、[个人旗用途](https://www.fotw.info/flags/sd-hist.html) | medium |
| Sudan B，用户已选定默认 | 1900-01-01 | 两张完整英／埃当局旗，运行时组合 | APPROXIMATE_HISTORICAL_VISUAL；visual_kind=AUTHORITY_LIVERY | [1899 协定 Article II](https://en.wikisource.org/wiki/Sudan_Convention_(1899)) | medium；组合本身为 presentation |
| Cape Colony | 1900-01-01 | cape_colonial_1876.svg | COLONIAL_FLAG | [殖民旗记录](https://www.crwflags.com/fotw/flags/za-c.html)、[馆藏同期商船旗](https://www.rmg.co.uk/collections/objects/rmgc-object-721) | medium |
| Natal | 1900-01-01 | natal_colonial_1905.svg | APPROXIMATE_HISTORICAL_VISUAL | [CO 323/326 通信与 1905 徽章变更](https://www.crwflags.com/fotw/flags/za-n.html) | low |
| British India | 1900-01-01 | india_governor_general_1885.svg | GOVERNOR_STANDARD | [Greenwich AAA0271 馆藏](https://www.rmg.co.uk/collections/objects/rmgc-object-271)、[重绘资产](https://commons.wikimedia.org/wiki/File:Flag_of_the_Governor-General_of_India_(1885%E2%80%931947).svg) | medium |
| French Algeria | 1900-01-01 | algeria_colonial_ensign.svg | APPROXIMATE_HISTORICAL_VISUAL | [重绘资产及其 1844 字典／1908 旗卡出处](https://commons.wikimedia.org/wiki/File:Naval_ensign_of_French_Algeria_(1848%E2%80%931910).svg) | low |
| Swaziland | 1900-01-01 | 完整 transvaal_vierkleur_1857.png | METROPOLITAN_FLAG；protecting-power livery | [保护时期旗帜](https://www.crwflags.com/fotw/Flags/sz_prot.html)、[殖民年报历史概述](https://libsysdigi.library.illinois.edu/ilharvest/Africana/Books2011-05/469190/469190_1929/469190_1929_opt.pdf) | medium |
| Cuba occupation | 1900-01-01 | us_1896_45_star.png | METROPOLITAN_FLAG | 原政治目录 occupation / controller 与原美国旗出处 | medium |
| Maldives / Trucial States | 1900-01-01 | uk_union_1801.png | METROPOLITAN_FLAG | 原政治目录 protectorate / controller 与原英国旗出处 | medium |
| Bhutan | 1900-01-01 | 固定 #8f7449 政治色 | COLOR_FALLBACK | presentation palette；不声称历史旗色 | presentation_only |
| Netherlands / Surinam / Indonesia | 1900-01-01 | netherlands_tricolour.png | LOCAL_OFFICIAL_FLAG / METROPOLITAN_FLAG | 原资产连续设计；保留 before-1900 原日期，单记 display window | high / medium |
| Khiva / Brunei | 1900-01-01 | 原 khiva_historical.png / brunei_yellow_pre1906.png | APPROXIMATE_HISTORICAL_VISUAL | 原来源 before-year 日期不精确，单独标记近似窗口 | 原来源置信度另行保留 |

所有当前 146 个已分配政治实体均有 resolved visual；145 使用完整纹理，Bhutan 使用明确固定色。此数字来自正式场景截图 manifest，不包含未分配 source features。

【Afghanistan】

保留 1880—1901 纯黑 PNG，原 SHA256 一致；纠正文字描述中错误的“中央白色徽记”。统一 MAP TONE TRANSFORM 保留原有 0.70 saturation、0.72 brightness、0.25 highlight compression。暗部使用 weighted RGB perceived luminance 的统一 floor：max(0.18, background_reference luminance + 0.055)，当前黑色输出约 #303030。向中性白按一个标量提升，只缩放 RGB 通道差，保持 hue；白、黄等高于阈值的样本不增加亮度。适用于黑、深蓝、深红、深绿、深棕，shader 无国家 ID 或分支。

原暗色细 political boundary 未修改。未改 PNG，未增加 emblem 或贴纸。

【Sudan】

A 为总督个人旗，历史用途是 afloat administrative standard。Flag Institute 索引将 Sudan governor 记为 1899；现用 SVG 是现代重绘，字体不声称为 1900 原件。用户已选择 B；A 从 territorial visual_ids 移至 administrative_visual_ids，仅保留为历史资料与将来行政／职位 UI 资产，不再作为 Political map 地表候选。review_selection=sudan_joint_authority_1899。

B 的英／埃双旗共同使用有 1899 协定依据。两张完整旗的上下组合仅为 presentation；埃方使用 1914 前的单弯月／星公共旗设计，复用完整 Ottoman 设计资产，不宣称 Ottoman 管理 Sudan，也不把三弯月 khedival personal standard 冒充公共旗。Suakin 的埃旗单独使用例外无法在现有粗粒度 geometry 中独立表现，已记入 metadata。

两者均不是 Sudan national flag。historical_national_flag=NONE；B presentation_visual_kind=AUTHORITY_LIVERY。

【Southern Africa】

| Territory | 当前表现 |
|---|---|
| Cape | COLONIAL_FLAG |
| Natal | APPROXIMATE_HISTORICAL_VISUAL：1905 年简化徽章的同一殖民体系 Blue Ensign；不是精确 1900 旗 |
| Transvaal / Orange Free State | 保留 LOCAL_OFFICIAL_FLAG，未换成战后殖民旗 |
| Rhodesia / North-Eastern / North-Western Rhodesia | 1900-01-01 保持 neutral geography，候选为 COMPANY_FLAG |
| Bechuanaland / Basutoland | METROPOLITAN_FLAG fallback；排除 1931 High Commissioner 旗 |
| Swaziland | ZAR Vierkleur 的 protecting-power livery；保护关系不等于并入共和国 |
| German South West Africa | German imperial METROPOLITAN_FLAG fallback；排除未采用的 1914 提案 |
| Portuguese Mozambique | 1830 Portuguese METROPOLITAN_FLAG fallback；不套 1910 后共和国旗或只适用部分 concession 的公司旗 |

BSAC 候选来自 [Berry 的研究](https://fiav.org/wp-content/uploads/2021/05/15-09Berry-BritishSouthAfricaCompany.pdf)，记载 1893 年 Bulawayo 使用公司旗，并讨论 red ring / lettering 变体。选择现有完整重绘，保留变体不确定性；不使用 1902 年才批准的公司 ensigns。三个原 CShapes 记录 valid_from=1900-01-29 均保持原值，本轮未给 neutral geography 偷加政治表面。候选只有正式 political assignment 后才可消费。

Swaziland 的视觉史料指向 ZAR 保护体系，而当前 runtime legacy controller 仍为英国。此差异明确记在 display 历史上下文中；本轮未修改政治状态或权威关系。

【Colonial Audit】

Cape、Natal、India、Algeria 的单纯宗主国旗已由地方殖民／行政 representative asset 取代；Natal、Algeria 都明确标记近似。Algeria 采用有文献线索的海事 double tricolour 作地图代表，不宣称 1900 当日普遍陆上正式使用；排除被标为 erroneous 的“蓝底法国 canton”旗。

BSAC 已查证并登记，因政治有效期未开始仍只保留候选。Bechuanaland、Basutoland、German Togoland / Kamerun / Tanganyika / South West Africa / New Guinea、Portuguese Cape Verde / Guinea-Bissau / Angola / Mozambique / East Timor 保留明确 METROPOLITAN_FLAG fallback。其他法国殖民区域如 West Africa、Congo、Madagascar、Indochina 继续 French tricolour fallback；本轮有限审计没有选入证据足够的地方完整资产。Tunisia 的原地方历史旗继续保留。

【SOURCE GAPS】

正式 scene loader 对以下城市／位置坐标没有匹配 source polygon：Riyadh / Nejd (46.675,24.713)、Hail (41.683,27.521)、Aden (45.03,12.78)、Hadramaut (49.1,15.9)、Qatar / Doha (51.53,25.29)、Bahrain / Manama (50.586,26.223)、Kuwait City (47.98,29.37)。这些点为 SOURCE_NOT_PRESENT；不是缺 flag，也不是本轮可以补出的地理。没有补画 geometry 或套现代边界。

【Architecture】

Geography 只提供原有地；Political State 仍由当前权威运行时负责；resolver 只选择 display asset / role；renderer 只消费 resolved visual 与纹理；shader 只调整色调与可见性。

未改 Quaternion、rotation、projection、triangulation、horizon、camera、UI、simulation、economy、save/load、海面清 selection 或 boundary。FULL FLAG + 原 territory UV mapping 保持。

截图读取的 source feature=151；source / loader / projection-render source exterior 均=1604；geometry_lost=0。projection-render count 是 renderer 中全部保留的 source components，不是要求当前可见半球同时画出背面的 1604 个 exterior。

【Modified Files】

- scripts/content/historical_visual_resolver.gd：小型解析器。
- scripts/content/evidence_loader.gd：接入解析器。
- scripts/presentation/map/political_layer.gd：保存 resolved visual / texture。
- scripts/presentation/map/globe_renderer.gd：替换 flag_id 直接消费。
- shaders/presentation/map/political_surface.gdshader：统一暗部对比度。
- data/world_map/historical/flags_1900.json：visual_kind / display_role、非精确日期显示窗口、Afghanistan 描述。
- data/world_map/historical/political_visuals_1900.json：地方资产、近似说明、BSAC 候选、来源和角色。
- assets/historical_liveries/1900/：六个完整 SVG 及 ATTRIBUTION.md；Godot import 描述。
- tools/map/capture_representative_visuals.gd：正式 scene 截图工具，无时间推进。
- docs/map/representative_political_visual_closure_m2_5.md：本报告。
- local-artifacts/historical-livery/：截图、manifest 与解析／截图日志。

没有修改已有用户工作区中其他架构改动，也没有开展 Formal Legacy Severance。

【Screenshots】

全部为指定 Godot 4.6.3 Compatibility 在本机 RTX 3050 生成的 1280×720 FormalWorldMain scene 截图。无 UI 替代 scene、模拟推进或新测试体系。

1. local-artifacts/historical-livery/01_afghanistan.png
2. local-artifacts/historical-livery/02_sudan_a_governor.png
3. local-artifacts/historical-livery/03_sudan_b_joint_authority.png
4. local-artifacts/historical-livery/04_southern_africa.png
5. local-artifacts/historical-livery/05_algeria_north_africa.png
6. local-artifacts/historical-livery/06_british_india.png
7. local-artifacts/historical-livery/07_arabia_gulf.png
8. local-artifacts/historical-livery/08_world_scale.png

检查限于 git diff --check、Godot headless editor import/parse、正式 scene 截图及读取其几何／视觉 manifest。未运行统一长期验证、十年模拟或 benchmark。人工视觉验收待用户完成。
