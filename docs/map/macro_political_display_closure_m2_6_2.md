# WWO M2.6.2 FINAL — Macro Political Display Closure

施工完成，等待人工视觉验收。**尚未标记 MAP RECOVERY CLOSED。** 目标日期 1900-01-01。

## 结果

M2.6.1 的地方 authority 调查结果保留，但不再直接成为世界 Political Map 的绘制单元。原 15 exterior 的世界显示收敛为 8 个宏观主体：Rashidi、汉志、哈萨、也门、Oman、Trucial/Gulf sheikhdoms、Hadramaut、Mahra；Kuwait、Qatar、Bahrain、Aden 的既有记录继续保留。

原残余 geography 在世界 Political Map 上：neutral=0、COLOR_FALLBACK faces=0。没有删除土地，没有新增或切割 triangle / polygon，没有把地方 authority 写入 sovereign nation registry。新增 4 条 display-only 记录只是宏观代表性视觉与文字锚点，不是 administration、controller、economy 或 population entity。

## Local authority → map display authority

| local authority | map_display_authority_id | authority_status | map confidence | visual |
|---|---|---|---:|---|
| 汉志沿海行政 | `map_display:hejaz_1900` | LOCAL | 0.70 | 完整 Ottoman authority livery |
| 帖哈麦地方部落 | `map_display:yemen_1900` | NOMINAL | 0.50 | 完整 Ottoman authority livery |
| 马赫拉地方行政边缘 | `map_authority:arabia_mahra_1900` | LOCAL | 0.60 | 既有英国保护关系 representative visual |
| 贾纳巴地方部落 | `sultanate_of_muscat_oman` | AUTONOMOUS | 0.55 | 既有 Muscat/Oman 纯红历史旗 |
| 阿曼哈杰尔地方谢赫 | `sultanate_of_muscat_oman` | NOMINAL | 0.60 | 既有 Muscat/Oman 纯红历史旗 |
| 卡西米沿海地方行政 | `trucial_states` | LOCAL | 0.65 | 既有英国 maritime/protectorate representative visual |
| 巴尼亚斯／马纳西尔 | `trucial_states` | LOCAL | 0.65 | 既有英国 maritime/protectorate representative visual |
| 哈萨沿海行政 | `map_display:hasa_1900` | LOCAL | 0.70 | 完整 Ottoman authority livery |
| 阿纳扎地方部落联盟 | `map_authority:arabia_rashidi_1900` | AUTONOMOUS | 0.40 | 既有完整 Rashidi 绿紫 livery |
| 沙马尔／拉希德影响区 | `map_authority:arabia_rashidi_1900` | TRIBUTARY | 0.60 | 既有完整 Rashidi 绿紫 livery |
| 哈尔卜／朱海纳地方部落 | `map_display:hejaz_1900` | AUTONOMOUS | 0.50 | 完整 Ottoman authority livery |
| 达瓦西尔绿洲与部落 | `map_authority:arabia_rashidi_1900` | AUTONOMOUS | 0.50 | 既有完整 Rashidi 绿紫 livery |
| 奈季兰／阿西尔地方权威 | `map_display:yemen_1900` | NOMINAL | 0.40 | 完整 Ottoman authority livery |
| 穆拉／哈杰尔地方部落 | `map_display:hasa_1900` | AUTONOMOUS | 0.45 | 完整 Ottoman authority livery |
| 南阿拉伯地方谢赫与部落 | `map_authority:arabia_rashidi_1900` | AUTONOMOUS | 0.25 | 既有完整 Rashidi 绿紫 livery |

Southern local 的 default 宏观归属为 Rashidi；显式地理影响区覆盖时，western Oman → Oman、Mahra/Gharah 南部 → Mahra、Hadramaut hinterland → Hadramaut。地方 authority 的原始影响区和历史解释未改，只追加世界地图聚合字段。所有 map_assignment 均为 APPROXIMATE；AUTONOMOUS、TRIBUTARY、NOMINAL、LOCAL 不代表排他性直接统治。

Rashidi 外缘聚合依据[1900 年当代描述的中央阿拉伯政治优势](https://www.gutenberg.org/cache/epub/63928/pg63928-images.html#Page_200)，外围关联仍是近似推断，没有把整个 Arabia 或 Gulf 交给一个国家。该来源不会证明每个部落被直接统治；本轮显示层不作这种主张。

## 原中央沙漠 unresolved

原约 9,257 km² 游戏 mesh 残余显示并入 Rashidi，map confidence=0.25、approximate=true。原本的地方 authority 查询仍返回未知；没有伪造地方 ruler、征税或实际 controller。此面积只用于现有游戏 mesh 统计，不是历史国土面积。

## Representative visuals

| display authority | display_role | display_asset |
|---|---|---|
| `map_authority:arabia_mahra_1900` | METROPOLITAN_FLAG | `res://assets/historical_flags/1900/uk_union_1801.png` |
| `map_authority:arabia_rashidi_1900` | APPROXIMATE_HISTORICAL_VISUAL | `res://assets/historical_liveries/1900/rashidi_authority_1900.svg` |
| `map_display:hadramaut_1900` | APPROXIMATE_HISTORICAL_VISUAL | `res://assets/historical_liveries/1900/quaiti_1880.svg` |
| `map_display:hasa_1900` | METROPOLITAN_FLAG | `res://assets/historical_flags/1900/ottoman_1844.png` |
| `map_display:hejaz_1900` | METROPOLITAN_FLAG | `res://assets/historical_flags/1900/ottoman_1844.png` |
| `map_display:yemen_1900` | METROPOLITAN_FLAG | `res://assets/historical_flags/1900/ottoman_1844.png` |
| `state:sultanate_of_muscat_oman` | LOCAL_OFFICIAL_FLAG | `res://assets/historical_flags/1900/muscat_oman_plain_red.png` |
| `state:trucial_states` | METROPOLITAN_FLAG | `res://assets/historical_flags/1900/uk_union_1801.png` |

Hadramaut 使用[Quaiti 1880–1939 红白旗 SVG 的现代重绘](https://commons.wikimedia.org/wiki/File:Flag_of_Qu%27aiti_State_in_Hadhramaut_(1880-1939).svg)。资产来自 Wikimedia Commons，PD-shape，作者 Dekodrak / Andel；本地 SHA256 与来源记录相连。区域用途明确记为 APPROXIMATE_HISTORICAL_VISUAL / AUTHORITY_LIVERY，historical_national_flag=NOT_ASSERTED，historical_design_claim=false。它不是 Kathiri national flag，不代表统一 Hadramaut 国家，也没有提前宣称 Kathiri 在 1900 年获得英国保护；未使用 1939 年后的徽记旗。

15 条 M2.6.1 micro-authority 色绑定已从世界地图 visual catalog 删除，生成器也不再生成该 palette。HistoricalVisualResolver 未改，仍然解析最终宏观主体的完整旗／livery。没有 disabled flag、alternate mode 或 micro fallback 绘制分支。

## Content / presentation / renderer

- Content：保留 15 条 local authority 的全部原有历史字段；新增 map_display_authority_id、map_assignment、authority_status、map_confidence 和必要的显式 macro influence-region links。provenance admission 用更新内容的完整 hash。
- PoliticalLayer：过滤地方绘制单元，形成最终宏观 records，并将既有 source faces 绑定到这些 records。
- Renderer：只接收 final display authority 和完整旗面 UV；原按 source triangle 查询 local authority 并绘制独立 fallback 色的路径已删除。
- 跨 source feature 的新增覆盖区域使用同一宏观旗面的地理坐标，避免旗帜在每个 donor feature 重新开始。冻结核心 feature 的 source UV 和原 flag bounds 不变；没有修改 uv_scale / uv_offset / uv_rotation、旗 PNG、shader 或 projection。新 display-only 区域正常按完整旗面范围归一化。

## Geometry accounting / freeze verification

| count | before | after |
|---|---:|---:|
| features | 161 | 161 |
| source exteriors | 1634 | 1634 |
| loader | 1634 | 1634 |
| projection retained components | 1634 | 1634 |
| render retained components | 1634 | 1634 |
| geometry_lost | 0 | 0 |

source-face count 与 M2.6.1 完全相同。source / loader / projection / render 计数指全局 exterior 组件保留；当前背面 geography 不要求在单张 screenshot 上可见。冻结文件 hash、原 authority claim 字段、原 visual records 和所有非 micro-authority visual bindings 比较均无变化。Southern Africa / BSAC、Sudan B、Afghanistan、Russia、Ottoman、Qing、shader、projection、Quaternion 和 Formal 代码保持本轮开始时的状态。

[Formal manifest](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_manifest.json) / [冻结验证](D:/WWO/wwo/local-artifacts/arabia-macro-closure/freeze_verification.json)。

## Validation

`git diff --check`、Godot 4.6.3 headless editor parse、正式 Formal scene capture 均退出 0；日志扫描无解析／脚本／运行错误。没有 benchmark、长时间 simulation、新测试框架或平台导出声明。

## Modified files

- [data/world_map/historical/arabia_authority_coverage_1900.json](D:/WWO/wwo/data/world_map/historical/arabia_authority_coverage_1900.json)
- [data/world_map/historical/political_visuals_1900.json](D:/WWO/wwo/data/world_map/historical/political_visuals_1900.json)
- [data/provenance/historical_source_registry.json](D:/WWO/wwo/data/provenance/historical_source_registry.json)
- [data/provenance/historical_fact_evidence.json](D:/WWO/wwo/data/provenance/historical_fact_evidence.json)
- [scripts/content/administrative_loader.gd](D:/WWO/wwo/scripts/content/administrative_loader.gd)
- [scripts/presentation/map/political_layer.gd](D:/WWO/wwo/scripts/presentation/map/political_layer.gd)
- [scripts/presentation/map/globe_renderer.gd](D:/WWO/wwo/scripts/presentation/map/globe_renderer.gd)
- [tools/historical_data/build_arabia_authority_coverage.py](D:/WWO/wwo/tools/historical_data/build_arabia_authority_coverage.py)
- [tools/map/capture_arabia_authority.gd](D:/WWO/wwo/tools/map/capture_arabia_authority.gd)
- [assets/historical_liveries/1900/quaiti_1880.svg](D:/WWO/wwo/assets/historical_liveries/1900/quaiti_1880.svg)
- [docs/map/macro_political_display_closure_m2_6_2.md](D:/WWO/wwo/docs/map/macro_political_display_closure_m2_6_2.md)
- `local-artifacts/arabia-macro-closure/`：正式截图、manifest、日志、baseline、冻结验证。

UI、economy、population、save/load、simulation、scripts/formal 未做本轮修改。没有启动 Formal Legacy Severance 或 M3。

## Screenshots

全部为实际 Formal scene，1900-01-01 00:00，1280×720。Before 是本轮失败的 M2.6.1 正式截图原像素副本；与 corrected Arabia 使用相同 focus / zoom。

### Arabia current failed M2.6.1

![Arabia current failed M2.6.1](D:/WWO/wwo/local-artifacts/arabia-macro-closure/before_failed_m2_6_1.png)

### Arabia corrected M2.6.2

![Arabia corrected M2.6.2](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_arabia.png)

### Nejd / Rashidi

![Nejd / Rashidi](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_nejd_rashidi.png)

### Hejaz

![Hejaz](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_hejaz.png)

### Gulf

![Gulf](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_gulf.png)

### Yemen / Hadramaut

![Yemen / Hadramaut](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_yemen_hadramaut.png)

### World scale

![World scale](D:/WWO/wwo/local-artifacts/arabia-macro-closure/after_world.png)

停止地图施工，等待人工验收。只有验收通过后才标记 MAP RECOVERY CLOSED；本轮不启动下一阶段。
