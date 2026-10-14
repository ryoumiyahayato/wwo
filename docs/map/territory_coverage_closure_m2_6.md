# WWO MAP RECOVERY M2.6 — territory coverage closure

施工完成，等待人工视觉验收。目标日期 **1900-01-01 00:00**。尚未宣称人工验收通过，也尚未进入 Formal Legacy Severance R1 / M3。

七个 Arabia / Gulf 检查点已从 SOURCE_NOT_PRESENT 变为有 geography、有历史行政 authority、有 representative visual。全部新增边界属于 **APPROXIMATE_HISTORICAL_GEOGRAPHY_ADDED**，没有冒充 exact GIS。Rhodesia 三块使用已有 geography，1900-01-01 的地图行政身份改由 BSAC 前置行政记录闭合。原始 CShapes 数据、原始 polity validity 和 151 / 1604 geometry 没有改动。

## 【ARABIA / GULF】

共同 old_status：SOURCE_NOT_PRESENT。共同 new_status：APPROXIMATE_HISTORICAL_GEOGRAPHY_ADDED + APPROXIMATE_HISTORICAL_AUTHORITY。共同 geometry source：[Zwemer《Arabia: The Cradle of Islam》1900 年折叠地图](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Arabia)，巴林另有同书 p.98 群岛地图。source_date = 1900（年精度；包括 1899 年观察），target_date = 1900-01-01，geography_confidence = APPROXIMATE，geography_basis = BOUNDED_HISTORICAL_MAP。

坐标来自历史地图经纬网、海岸与命名区域的粗略解释，内陆行政边缘是有界游戏近似，未经过测绘级地理配准。不是现代国界倒推，不是 OHM exact polygon。地理轮廓与行政依据分别记录。

| 检查点 / lon, lat | geometry_added / feature | 政治行政 authority、关系 | authority source / source_date / confidence | representative_visual / display_role |
|---|---|---|---|---|
| Riyadh / Nejd / 46.675, 24.713 | 是；arabia_rashidi_1900，1 exterior；与 Hail 共用 | Rashidi emirate；当地王朝管理，奥斯曼联盟/贡属关系；没有倒推 1902 年 Saud 夺取 Riyadh | [1900 年当代记述 p.200](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_200)；1900；0.85 | rashidi_authority_1900；APPROXIMATE_HISTORICAL_VISUAL / AUTHORITY_LIVERY |
| Hail / 41.683, 27.521 | 是；同一 Rashidi feature，非重复地块 | Rashidi emirate / Hail 行政中心 | 同上及 p.26–28；1900；0.85 | 同上；整幅绿紫历史近似 livery |
| Aden / 45.03, 12.78 | 是；arabia_aden_settlement_1900，1 exterior | Aden Residency / Bombay Presidency；英属居留地，与内陆条约诸邦分开 | [1900 年 p.218](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_218)；1900；0.90 | uk_union_1801；METROPOLITAN_FLAG，行政代表 fallback，非当地独立国旗 |
| Hadramaut / 49.1, 15.9 | 是；检查点属 arabia_kathiri_1900，1 exterior；另增 Quaiti 沿海与 Mahra 各 1 exterior | Kathiri 内陆本地苏丹国；Quaiti 沿海保护关系；Mahra 本地统治/英国条约关系。没有把整个 Hadramaut 当作英国殖民地 | [India Office 条约汇编](https://www.qdl.qa/en/archive/81055/vdc_100023462214.0x000011)；Quaiti 1888、Kathiri 1918 仅作区别，1933 回溯出版；Kathiri 0.70、Quaiti 0.80、Mahra 0.75 | Kathiri：#b48a46、COLOR_FALLBACK；稳定、有命名身份，非假造旗。Quaiti / Mahra：uk_union_1801、METROPOLITAN_FLAG |
| Kuwait / 47.98, 29.37 | 是；arabia_kuwait_1900，4 exterior；港湾与有限腹地，非 1922 / 现代边界 | Mubarak Al Sabah 当地行政；1899 英国专属协议，奥斯曼名义主张另记为争议 | [Kuwait 政府历史](https://e.gov.kw/sites/kgoenglish/Pages/Visitors/AboutKuwait/GoverningBodyOverView.aspx)；1899-01-23；0.90 | uk_union_1801；METROPOLITAN_FLAG，保护关系 representative fallback |
| Qatar / 51.53, 25.29 | 是；arabia_qatar_1900，1 exterior；历史半岛海岸与近似南部接界 | Jassim Al Thani 实际当地行政；奥斯曼驻军/名义关系；没有提前使用 1916 英国保护关系 | [Amiri Diwan](https://www.diwan.gov.qa/about-qatar/qatars-rulers/sheikh-jassim-bin-mohammed-bin-thani)；1893 事件及 1900 连续性；0.85 | ottoman_1844；METROPOLITAN_FLAG，当地 authority 与上级关系分别保留 |
| Bahrain / 50.586, 26.223 | 是；arabia_bahrain_1900，4 exterior，历史主要岛屿；无现代填海 | Sheikh Isa Al Khalifa；本地行政/英国保护关系 | [1900 年 p.219](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_219)；1899 观察 / 1900 出版；0.90 | bahrain_authority_1900；APPROXIMATE_HISTORICAL_VISUAL / AUTHORITY_LIVERY；红白历史近似，确切 1900 年比例未证实 |

其他补充：arabia_aden_treaty_states_1900 是一块条约诸邦地图聚合，**不是统一 sovereign nation**；1888/1895/1896 保护条约与当地统治者分别记载。Mahra 的 [1886-04-23 Socotra / Qishn 条约原文](https://qdl.qa/en/archive/81055/vdc_100023462215.0x00000b)保留本地统治意义。Dhofar 已在现有 Oman / gw_698 geography 内，没有重复新增或重写整个 Oman 的行政身份。

未划定专属 authority 的沙漠、部落地带新增 arabia_undelimited_desert_1900：15 exterior，维持 GEOGRAPHY_PRESENT_NO_POLITY / neutral geography。土地存在与排他性政治主张不互相替代。这里的中性色是有意保留的地理状态，不是有 polity 却丢失旗帜。

## 【SOUTHERN AFRICA】

共同：1900-01-01 geography = PRESENT（已有 March 12 CShapes snapshot，回用于 Jan 1 标为 NEARBY_DATE / APPROXIMATE_FOR_1900_01_01）；authority_type = COMPANY_ADMINISTRATION；representative_visual = bsac_company_1893 / COMPANY_FLAG。没有新建 BSAC sovereign nation，也没有全部写成 Britain。本轮没有新增南部非洲 geometry。

| territory / feature | 1900-01-01 administrator | sovereignty / imperial relation | source / source_date | confidence |
|---|---|---|---|---|
| Rhodesia / gw_552 | BSAC southern administration | 英国皇家特许/帝国关系，实际公司行政 | [National Army Museum：BSAC 管理 Rhodesia 1890–1923](https://collection.nam.ac.uk/detail.php?acc=1998-03-21-1)；1890–1923 的历史对象说明 | authority 0.90；Jan 1 边界近似 |
| North-Eastern Rhodesia / gw_5518 | BSAC deputy administration / Codrington / Fort Jameson | 公司实际行政；1900-01-29 正式 Order 另列，未提前声称其法律生效 | [Derbyshire Record Office D3287/BSA/8/6](https://calmview.derbyshire.gov.uk/CalmView/Record.aspx?id=D3287%2FBSA%2F8%2F6&src=calmview.catalog)；1899-04-24 | authority 0.85；Jan 1 边界近似 |
| North-Western Rhodesia / gw_5519 | BSAC Barotse / north-western administration | 公司行政与 Lewanika / 本地司法并存；英国保护关系；非排他性公司主权 | [Barotziland–North-Western Rhodesia Order, SR&O 1901/567](https://upload.wikimedia.org/wikipedia/commons/a/ab/UKSRO_1901.pdf)；1899-11-28 签署、1901 印刷汇编 | authority 0.85；Jan 1 边界近似 |

source date / Order signature 并不自动证明所有条款的正式 commencement。本轮闭合的是历史实际行政连续性。公司旗复用 M2.5 既有完整旗资产、既有 resolver 和 UV mapping。

## 【DATE HANDLING】

- **1900-01-01**：Formal runtime 当前日期；新的 content authority mapping 从这一天解析，12 条记录通过 provenance hash admission，以 APPROXIMATE_HISTORICAL_AUTHORITY 显示。
- **1900-01-29**：三条原始 CShapes record 的 valid_from 原样保留。新资料中的 predecessor_assignment_window = [1900-01-01, 1900-01-29)，并记录 later_source_historical_id。它表示 source boundary/entity period 的起点，不能推断此前无行政。NE 正式 Order 与另外两区的真实前置行政也不混为同一日期。
- **1900-03-12**：原始 CShapes geometry snapshot；地图左下原有 source 文本仍显示这一日期。该文字不是 Formal runtime 当前日。南部非洲 geography 在 Jan 1 属 nearby-date approximation，未伪称 exact Jan 1 polygon。
- 新增行政记录限定在 [1900-01-01, 1901-01-01) 的 1900 地图证据窗口，不因 March 12 snapshot 次日而失去行政显示。exclusive end 是本次内容适用范围，**不是历史政权解散日期**。本轮不宣称后续年代边界完成。
- PoliticalLayer 优先消费实际 runtime polity；缺少该记录且存在 geography 时，消费已通过 admission、日期有效的行政记录。没有把后来 CShapes polity 直接塞回 Jan 1 runtime registry。

## 【GEOMETRY ACCOUNTING】

| count | before | after |
|---|---:|---:|
| Source features | 151 | 161 |
| Source exteriors | 1604 | 1634 |
| Loader exteriors | 1604 | 1634 |
| Projection retained components | 1604 | 1634 |
| Render mesh retained components | 1604 | 1634 |
| geometry_lost | 0 | 0 |

新增 10 features / 30 exteriors：9 个行政地域与 1 个未划定沙漠地理聚合。原始 151 features / 1604 exteriors 全部保留。新 supplement 始终先扣除旧 geography，然后扣除已分配新地域；没有在 renderer 中制造 polygon。只对新增 overlay 使用 0.00001° 坐标精度与 0.00001 平方度小碎片下限，均写入 provenance。

这些 accounting 是 source exterior 在 loader / projection / renderer mesh 中的组件保留计数，不是要求背面与 horizon 外的地块也在当前帧可见。Formal 截图工具对七个检查点逐一读取真实 loader geometry（外环减内洞），每点恰好命中预期一个 feature。

证据：[before manifest](D:/WWO/wwo/local-artifacts/territory-closure/before_manifest.json)、[after manifest](D:/WWO/wwo/local-artifacts/territory-closure/after_manifest.json)。

## 【UNRESOLVED】

七个指定检查点的 geography closure 没有 UNRESOLVED_AFTER_SOURCE_SEARCH。

经过来源搜索后仍没有准确复原的，是内陆部落边缘、Rashidi 外围实际控制范围、Hadramaut 苏丹国精确接界、Kuwait 未划定腹地、Qatar 南部接界及 Bahrain 更小岛礁。它们以明确的 bounded approximation 或 neutral geography 处理，没有宣称测绘级 exact closure。Kathiri 未找到可可靠用于 1900 的当地旗，继续使用已有 resolver 的命名稳定政治色 fallback。

先查 source registry / 已下载 assets / staging / pinned files：未找到可直接接入这七处的历史 polygon。没有重复下载已有 source。随后检索 CShapes 原始有效期资料、OHM 和当代地图、条约/档案。OHM Overpass 实际返回 403，不能把此结果写成“OHM 无数据”；改用历史地图解释。这次并非因 CShapes 缺失而直接结束为 unresolved。

## 【VISUAL NOTE】

Nepal / Bukhara 的亮白部分不是 geography hole。快速检查源 PNG alpha 和既有 shader：透明旗区会混合到已有政治白底，其中一些像素达到接近 UI 的纯白；所以不能全部说成正常 flag white。单调 highlight_compression 参数无法覆盖 alpha=0 的白底分支。记录 **POST-M2.6 VISUAL POLISH**，本轮保持冻结 shader / tone / UV；没有国家亮度特判。

Afghanistan charcoal black、Sudan B 联合 authority livery、Russia / Ottoman / Qing 整幅旗、colonial resolver、细边界、Quaternion / camera / projection / triangulation / clipping 均保持 M2.5 状态。

## Responsibilities

GeographyLoader 只追加经过 source admission 的 geometry。AdministrativeLoader 提供日期有效、证据独立的 authority。已有 runtime Political State 保持不变。controller_id 空值明确表示本 supplement 不推断战争/模拟控制者。既有 HistoricalVisualResolver 仅解析视觉，没有另建旗帜系统。

PoliticalLayer 做 content → presentation 的只读投影；仅在 runtime 未提供该 feature 时使用历史 authority，不把它写入 nation-state registry。新增行政地块没有 economy / population / save 实体。GlobeRenderer 仅增加一行对显式 runtime_entity_id 的读取：这些历史行政记录的值为空，所以点击不会请求一个不存在的模拟国家详情；没有改 draw / material / UV / boundary / geometry 函数。UI、scripts/formal、simulation、economy、population、save/load 没有本轮改动。

## 【MODIFIED FILES】

本轮文件如下；工作区此前已有的 Formal 重构/删除、M2.5 改动不计入本轮。

- `data/world_map/historical/arabia_gulf_geography_1900.json` — 新增 geography supplement。
- `data/world_map/historical/historical_authorities_1900.json` — 12 条独立行政记录。
- `data/world_map/historical/political_visuals_1900.json` — 新增行政绑定与两张明确标为近似的 livery；旧 Sudan B 等记录保留。
- `data/world_map/historical/sources/arabia_1900_traces.json`、`ATTRIBUTION.md` 与三张 `*_zwemer_1900_*.jpg` — 输入与来源。
- `data/world_map/territory_source_registry.json` — supplement 来源与许可记录。
- `data/provenance/historical_source_registry.json`、`historical_fact_evidence.json` — 两组来源/事实及完整输出 hash。
- `assets/historical_liveries/1900/rashidi_authority_1900.svg`、`bahrain_authority_1900.svg`、`ATTRIBUTION.md` — 完整 livery 与近似性说明；Godot 生成对应 `.import`。
- `scripts/content/geography_loader.gd`、`administrative_loader.gd`、`historical_loader.gd` — 小范围既有 loader 支持。
- `scripts/presentation/map/political_layer.gd`、`globe_renderer.gd` — 消费行政 content 与一行合法详情 ID 适配。
- `tools/historical_data/build_territory_closure_1900.py` — 离线可重复生成，需 Shapely；不修改原始 CShapes。
- `tools/map/capture_territory_closure.gd` — 正式 scene 截图/accounting，不推进时间；Godot 生成 `.uid`。
- `docs/map/territory_coverage_closure_m2_6.md` — 本报告。
- `local-artifacts/territory-closure/` — 前后截图、manifest、日志、`.gdignore`（避免截图/临时只读下载被当作游戏资产导入）。

原始 `cshapes_1900_snapshot.json`、`political_units_1900.json` 未改。本轮未修改 `scripts/formal/**`、shader、UI、economy、population、save/load，也未提交、导出或执行大型测试体系。

## Validation

`git diff --check` exit = 0；指定 Godot 4.6.3 `--headless --editor --quit` exit = 0。最终 headless parse 与 Formal capture 的 stdout / stderr 扫描 ERROR、Parse Error、SCRIPT ERROR、Failed to load、Type Error，无匹配。Formal capture exit = 0；source / loader / projection / render 均为 1634，geometry_lost = 0。Formal scene 使用 Compatibility 真机渲染，截图为 1280×720，runtime 固定 Jan 1 00:00，未运行长时间 simulation / benchmark。Git 仅有换行格式提示，没有 diff whitespace 错误。

## 【SCREENSHOTS】

全部来自 `res://scenes/formal/formal_world_main.tscn`。前后 overview 使用相同位置、zoom 和无标签视图；近景调用现有标签/focus/zoom，不修改 UI 或 camera 逻辑。

1. Arabia / Gulf before

![Arabia / Gulf before](D:/WWO/wwo/local-artifacts/territory-closure/before_arabia_gulf.png)

2. Arabia / Gulf after

![Arabia / Gulf after](D:/WWO/wwo/local-artifacts/territory-closure/after_arabia_gulf.png)

3. Riyadh / Nejd

![Riyadh / Nejd](D:/WWO/wwo/local-artifacts/territory-closure/after_riyadh_nejd.png)

4. Aden / Hadramaut

![Aden / Hadramaut](D:/WWO/wwo/local-artifacts/territory-closure/after_aden_hadramaut.png)

5. Qatar / Bahrain / Kuwait

![Qatar / Bahrain / Kuwait](D:/WWO/wwo/local-artifacts/territory-closure/after_qatar_bahrain_kuwait.png)

6. Southern Africa before

![Southern Africa before](D:/WWO/wwo/local-artifacts/territory-closure/before_southern_africa.png)

7. Southern Africa after

![Southern Africa after](D:/WWO/wwo/local-artifacts/territory-closure/after_southern_africa.png)

8. Rhodesia close-up

![Rhodesia](D:/WWO/wwo/local-artifacts/territory-closure/after_rhodesia.png)

9. World scale

![World scale](D:/WWO/wwo/local-artifacts/territory-closure/after_world_scale.png)

Additional white surface note

![Nepal / Bukhara white surface review](D:/WWO/wwo/local-artifacts/territory-closure/after_white_visual_note.png)

完成后停止施工，等待用户人工验收；验收通过后标记 MAP RECOVERY CLOSED。没有提前开始下一轮 Formal Legacy Severance。
