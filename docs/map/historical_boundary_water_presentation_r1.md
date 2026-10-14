# WWO HISTORICAL ADMINISTRATIVE BOUNDARY & WATER PRESENTATION R1

2026-10-09；Godot 4.6.3.stable.official.7d41c59c4；Compatibility；Windows x86-64。

## RESULT

总体 **PARTIAL**，两项独立验收。行政部分 **BLOCKED_SOURCE**：核实了历史图幅目录和已有配准栅格服务，但未取得覆盖全部试点、许可明确且误差经审查的历史接界几何。六块土地行政成员仍为 UNRESOLVED，没有新增正式 Département、土地拆分、行政地图或存档版本。

水文部分 **COMPLETED_PRESENTATION**：克制河流/岸线宽度、亮度与尖角；区分湖面与里海；消除水面淡入时公共三角边重复混合。原始地理资料的折线、断段和概化仍有 **DATA_FIDELITY_LIMIT**。下文性能、发行与验证以本轮实际日志为准。

## A. HISTORICAL SOURCE REVIEW

详细字段保存在 [来源审查 JSON](D:/WWO/wwo/docs/map/historical_boundary_source_review_r1.json)。原始访问快照、HTTP 错误及 PDF 保存在忽略目录 `local-artifacts/historical-boundary-water-r1/research/`，不随产品发行。

|候选|实际核实|准入结果|
|---|---|---|
|[BnF Barrère 1895](https://catalogue.bnf.fr/ark:/12148/cb40722120g)|《Plan du département de la Seine》；Paris: H. Barrère；1:12,500；12 幅，82×64 cm；GE BB-52。实际目录 HTTP 200；无公开数字图幅链接，只有纸本预约和购买复制链接|CATALOGUE_ONLY；未取得像素、边界与使用授权|
|[APUR / IGN 历史栅格服务](https://carto2.apur.org/apur/rest/services/PLANS_HISTORIQUES/Atlas_departement_de_Seine_1895_Paris_et_environs/MapServer)|服务和 layer 0 元数据 HTTP 200；Raster Layer、geometryType=null、fields=null；EPSG:2154；没有行政 vector。copyright 为 Apur, IGN；exportTilesAllowed=false|VIEWABLE_REFERENCE；未确定衍生再分发授权或历史定位误差|
|[APUR 地理数据目录第 16 页](https://www.apur.org/sites/default/files/documents/geo-apps/fichiers-attaches/catalogue_donnees_geo_2021.pdf?token=kEwl5G1b)|1895–1900 图集；不绘制中心城区；权限栏为“Consultable en ligne”。同目录的其他开放数据才明确标注 ODbL|不能把一般 [APUR 开放数据说明](https://www.apur.org/fr/donnees-liberees) 扩大为这套历史栅格许可|
|[Seine-Saint-Denis 图集目录](https://patrimoine.seinesaintdenis.fr/Atlas-du-departement-de-la-Seine)|1895–1900、37 幅配准拼图；官方索引页可读，直接快照超时；权限为“communication libre - reproduction soumise à autorisation”|复制授权尚未取得；不是完整试点边界|
|[AD92 的 1900 Seine-et-Oise 馆藏线索](https://applis.hauts-de-seine.fr/adOld/archives.hauts-de-seine.fr/archeologie-patrimoines/patrimoine-culturel/la-cartotheque-historique/principaux-plans-et-cartes-du-xxe-siecle-utiles-en-cartographie-historique/index.html)|Andriveau-Goujon、L. Wuhrer，市镇图幅 1:5,000；AD92 的 Sèvres 图幅 FRAD092_5FI_SEV_001；其他图幅在 BnF。官方索引内容可读，直接页面 502|FINDING_AID_ONLY；不是已取得的一幅完整 département 边界|
|[BnF cb47551279d](https://catalogue.bnf.fr/ark:/12148/cb47551279d)|实际为 1887 年以前的 Dépôt de la Guerre 图，1:20,000|排除误命中，不能标成 1895 或直接证实 1900 接界|
|[1900 Album Artistique 插图](https://commons.wikimedia.org/wiki/File:Eure-et-Loire_-_Seine-et-Oise_-_Seine_-_Seine-et-Marne_-_Album_Artistique_de_la_France_%26_de_ses_Colonies_(1900).jpg)|索引描述为四省艺术性插图并标示法国公有领域；实际 imageinfo API 403，没有取得图像、原始比例尺或定位误差|未数字化；不能用此目录描述分配六块正式土地|
|[SGF / Insee 1900](https://www.insee.fr/fr/statistiques/2659665?sommaire=2591397)|复用此前准入的 Seine / Seine-et-Oise 身份名称；首府证据仍为 Paris / Versailles|身份成立；没有坐标几何|

[BnF 的复制使用说明](https://www.bnf.fr/fr/faire-une-utilisation-commerciale-dune-reproduction) 区分非商业注明来源与商业复制授权。本轮没有购买、发消息申请或推定所有衍生使用均获许可。此处是产品来源准入判断，不声称所有历史地图都不可合法数字化。公开服务可浏览与可打包历史边界是不同证据。

## B. SEINE / SEINE-ET-OISE GEOMETRY

已取得：名称、首府和目录/栅格服务元数据。未取得：经审查的 1900 两省公共接界、多边形、边界不确定区间，以及覆盖整个 454 km² 试点的可复用图幅组合。未将现代 Yvelines、Hauts-de-Seine、Seine-Saint-Denis、现代市镇合并、首府质心或游戏 GENERATED_PARTITION 边替代历史界。

## C. GEOREFERENCING ACCURACY

没有实施本轮配准或数字化，因此控制点、RMSE、独立检核误差、边界不确定性均为 **UNKNOWN / NOT_PERFORMED**，不能写成 0 m。APUR 服务使用 RGF93 / Lambert-93，EPSG:2154（legacy WKID 102110）；未公布本次审查所需的控制点与变换残差。最细服务采样 0.264584 m/px 是 tile 参数，不能称为历史测绘精度。

游戏土地自身的 0.01 m 坐标量化及 1.5 m 显示变换预算继续有效，但都不能作为历史地图配准精度。目录中的原图比例尺也不等于边界已确定误差。

## D. EXISTING LAND INTERSECTION

六块土地、454 km² 完全保持。只能做 APUR **服务外包矩形**与土地的覆盖诊断：约 346.949371 km² 重叠、107.050629 km² 在矩形外。这个结果不代表实际有效栅格像素覆盖，也不代表历史行政几何交集；目录另明确缺少中心城区。

|土地 ID 后缀（完整前缀 territory_unit:paris_pilot_）|面积 km²|服务矩形重叠 km²|Seine / Seine-et-Oise 归属|
|---|---:|---:|---|
|east|60|60|UNRESOLVED|
|north|72|71.999918|UNRESOLVED|
|northwest|76.5|40.388241|UNRESOLVED|
|south|92|82.827594|UNRESOLVED|
|southeast|60|60|UNRESOLVED|
|west|93.5|31.733618|UNRESOLVED|

未执行历史几何与正式土地 intersection，不能声称任何一块完整属于某省或已证明跨界。

## E. REQUIRED LAND SPLITS

本轮实际拆分 0 次；必要拆分集合 **NOT_EVALUATED**，不是“无需拆分”。当前算法只接受受控的两块凸多边形分割；每块 3–64 点、活跃上限 256、停用上限 250。曲折历史界可能要求多个凸片和多次谱系变更，尚未证明在这些限制下可完整表达。没有把曲线改直线，也没有扩建全球 GIS。现有面积守恒、邻接、主权/controller 继承、停用 ID 和精确恢复由正式土地回归继续检查。

## F. ADMINISTRATIVE MEMBERSHIP

两个既有只读身份 `administrative_region:france_seine` / `administrative_region:france_seine_et_oise` 继续为证据引用；type=departement、level=1、polity=state:country_fra、首府 Paris / Versailles。正式可变 Département 为 0；六块成员为 UNRESOLVED。没有引入行政 controller 副本；唯一控制状态仍是 TerritoryState。

## G. WORLDSTATE / PERSISTENCE

保持 `formal_world_simulation_v15`、spatial v3、land topology v1 和原有 18 个顶层字段。本轮新增的是 Presentation 的水面分类，不进入 WorldState，不创建行政持久化空壳。49 个既有地点及六块土地的主权、控制、稳定 ID 保持；原始源 JSON、LOD 坐标和证据文件未修改。完整 native 地图旅程前后的 FormalPersistence snapshot 应严格相同，具体结果见验证记录。

## H. REGION ADMINISTRATIVE DISPLAY

没有经准入的历史几何，WORLD 保持国旗/国家身份，REGION FAR / MID / NEAR 和 LOCAL 不画伪行政界。既有内部 GENERATED_PARTITION 继续默认隐藏，不能将六片土地画成六个省。也没有将未获明确使用条件的栅格嵌入只读参考图层。既有行政资料页仍可看两省身份；正式行政边界淡入和名称展示尚未验收。

AdministrativeBoundaryCache 继续为空，没有每帧 union、成员重算或行政遍历。本轮正式行政成员变更成本 **N/A**，不能用合成夹具成本代替实机功能。

历史资料页的旧来源说明含“尚无可分配土地”，已经不适合当前正式土地试点。仅在 Presentation 中修正为“历史行政边界与土地归属仍待核实”，不修改原历史证据里的旧审查状态或创建正式成员。此文案修正在水文性能采样后完成，未用于那些采样中的地图渲染；由最终实际产品行政资料页截图检查。

## I. RIVER VISUAL DEFECT ANALYSIS

|问题|真实证据|处理|
|---|---|---|
|Seine 和附近支流毛刺、视觉过亮|1280×720 同尺度 MID / NEAR 截图；2.1 px 芯线、1.25 px 羽化，斜接最大 3 倍。密集转折放大成宽亮尖角|river 芯线 1.25 px、羽化 0.70 px、斜接限 1.5；低饱和蓝和 alpha 0.88|
|Paris 海岸边毛刺|共用屏幕线 shader，原 1.8 px 高亮描边|coast 芯线 0.9 px、羽化 0.70、斜接限 1.5；与 river 不同色|
|Rhine / Danube 的长直段与拐角|源为 Natural Earth 1:50,000,000；已有 coarse / medium 概化 5,000 / 1,500 m；NEAR 400 m/px 放大了骨架精度|DATA_FIDELITY_LIMIT；没有平滑造线或运行时细分|
|断段/重叠/接界|典型河源为 MultiLineString；Rhine 5 段、Danube 3、Nile 11、Volga 9；所查典型 canonical/LOD 没有零长度段。不能据此宣称全球水文网络连续|不连接未证明连续的端点；Volga 等受调控河段原有缺口继续披露|
|GPU 投影和线连接|实际 bearing 截图及原有投影/拾取回归；改变的是屏幕描边参数，切片仍共享端点|保持原始投影、horizon clip、网格及 LOD。未改河流经纬度或国家边界默认斜接|

rail 保持原 2.4 px、原色、1.25 羽化和 3 倍斜接；国家/政治线 shader 的默认参数也保留。局部线 chunk 的端点/邻点策略本轮未重写；没有在观察尺度下证实需要修复的断裂，不把源码疑点当成已修复缺陷。

## J. RIVER BEFORE / AFTER

所有 before/after 相同引擎、原始地理坐标、1280×720、相同视角/尺度。截图由真实 Windows Release 的生产场景和渲染器取得；不是概念图、合成省界或浏览器重画。离线 probe 只驱动现有地图相机，不改变世界状态。

|地点 / 尺度|修改前|修改后|
|---|---|---|
|Paris REGION FAR，4500 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/paris_region_far.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/paris_region_far.png)|
|Seine / Paris REGION MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/paris_region_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/paris_region_mid.png)|
|Seine / Paris REGION NEAR，400 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/paris_region_near.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/paris_region_near.png)|
|Paris LOCAL，75 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/paris_local.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/paris_local.png)|
|Rhine MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/rhine_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/rhine_mid.png)|
|Rhine NEAR，400 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/rhine_near.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/rhine_near.png)|
|Danube MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/danube_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/danube_mid.png)|
|Danube NEAR，400 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/danube_near.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/danube_near.png)|
|Nile MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-fade-release/nile_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-fade-release/nile_mid.png)|
|Volga MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-fade-release/volga_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-fade-release/volga_mid.png)|

## K. LAKE / INLAND SEA BEFORE / AFTER

River 是现有 line mesh；Lake 是现有 water surface batch；Caspian 仍保持来源 ID `lake:caspiansea` 和 source kind=lake，但根据原已准入的 `ne_50m_ocean.geojson` 闭合内陆 component 在显示层归为 inland_sea。Great Lakes / Baikal 仍是 lake。海洋继续原有整体海面/背景样式；coast 是单独岸线，不用 river 颜色。

颜色集中于 HydrographyStyle：river=(0.29,0.52,0.61,0.88)，coast=(0.26,0.42,0.48,0.85)，lake=(0.13,0.29,0.36,1)，inland_sea=(0.10,0.21,0.27,1)。没有改 sovereignty、controller、source feature kind 或 territory identity，也没有按面积/名称字符串猜出水体类别。

真实缺陷：6800 m/px 淡入时，旧水面 shader 把每个三角边外扩 0.45 px，alpha 重叠导致里海内部明亮三角网格。新 shader 使用精确投影角点，复用现有每面 12 顶点、24 索引及双 horizon fan，重复角点形成退化三角，其余面按公共边一次光栅化。国家/政治面 shader 不变。没有新增三角化、岸缘 batch、TIME 或水波动画。

|水体 / 尺度|修改前|修改后|
|---|---|---|
|Caspian FAR，4500 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/caspian_far.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/caspian_far.png)|
|Caspian MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/caspian_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/caspian_mid.png)|
|Caspian 淡入，6800 m/px|[before 接缝](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-fade-release/caspian_fade.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-fade-release/caspian_fade.png)|
|Great Lakes FAR，4500 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/great_lakes_far.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/great_lakes_far.png)|
|Great Lakes MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/great_lakes_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/great_lakes_mid.png)|
|Great Lakes 淡入，6800 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-fade-release/great_lakes_fade.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-fade-release/great_lakes_fade.png)|
|Baikal MID，1200 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/baikal_mid.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/baikal_mid.png)|
|Baikal NEAR，400 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/baikal_near.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/baikal_near.png)|
|Baikal 淡入，6800 m/px|[before](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-fade-release/baikal_fade.png)|[after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-fade-release/baikal_fade.png)|

岛屿和岸线仍由来源面/孔洞决定，没有将空洞填平来消除接缝；视觉检查结论见验证。当前产品没有水面名称 label 的新功能，也没有暗示湖区为其他 Local。

## L. HYDROGRAPHY SOURCE LIMITS

Natural Earth 10m / 50m 指 1:10,000,000 / 1:50,000,000 比例尺，不是 10 m / 50 m 地面分辨率。战略 medium 保留了 Rhine 61 顶点/5 段、Danube 142/3、Nile 279/11、Volga 153/9；近景最大线段分别约 53.61、64.09、75.52、69.15 km，按 400 m/px 会成为明显长折线。诊断距离是近似地理计算，不是测绘误差。

Paris Local 的现代自然水系不能证明 1900 年河宽、堤岸、疏浚、桥梁可通行性或湖面高度。Caspian / Great Lakes / Baikal 面同样是现代概化物理参考，历史水位没有重建；受调控水系及既有排除项继续保留。未生产新的全球水文，不删减现有 30 条战略河流、19 个水体或 Paris 的 1387 river / 657 coast 来源 feature。详见忽略目录 `source_geometry_audit.json` 的逐文件 SHA256、数量及典型河流诊断。


## M. IDLE POWER / GPU

RTX 3050 Laptop GPU，NVIDIA 572.83，1280×720；before/after 分别运行原生 Windows Release。五组 idle 各 20 s，pan/zoom 各 12 s；OS 采样剔除前 3 s 与末 1 s，帧 p95/max 保留整段。所有比较期间无其他 Godot 验证并行运行。CPU 为全部逻辑处理器归一化占比；GPU 为该进程 GPU engine 最大值的采样中位数；功耗是整块板卡，不是单进程功率。

|idle|CPU % before → after|process GPU %|板卡 W|地图 redraw Δ|GPU frames Δ|
|---|---|---|---|---|---|
|world_idle|0.108 → 0.097|0.00 → 0.00|3.400 → 3.425|0 → 0|0 → 0|
|paris_region_far_idle|0.122 → 0.097|0.00 → 0.00|3.435 → 3.420|0 → 0|0 → 0|
|paris_region_mid_idle|0.092 → 0.129|0.00 → 0.00|3.440 → 3.455|0 → 0|0 → 0|
|paris_region_near_idle|0.092 → 0.074|0.00 → 0.00|3.440 → 3.450|0 → 0|0 → 0|
|paris_local_idle|0.048 → 0.126|0.00 → 0.00|3.430 → 3.440|0 → 0|0 → 0|

结论：静止进程 GPU 0%、地图 redraw 0、GPU frames 0；after 板卡 3.420–3.455 W，保持约 3.4 W 基线。idle 仍有 probe 的定时记录和引擎回调；它们不等于地图持续绘制。

## N. PAN / ZOOM PERFORMANCE

|场景|p95 ms before → after|max ms|CPU %|process GPU %|板卡 W|
|---|---|---|---|---|---|
|world_pan|18.04 → 17.85|29.00 → 22.93|2.867 → 2.900|20.62 → 19.16|7.87 → 7.80|
|world_zoom|17.71 → 17.74|21.17 → 23.05|2.820 → 2.704|21.29 → 20.74|7.87 → 7.89|
|paris_region_far_pan|18.24 → 17.75|27.51 → 25.82|3.354 → 3.691|20.93 → 21.89|7.81 → 7.78|
|paris_region_far_zoom|20.11 → 18.24|31.46 → 24.55|3.637 → 3.652|20.43 → 21.03|7.86 → 7.81|
|paris_region_mid_pan|17.75 → 17.71|23.60 → 184.60|3.000 → 2.854|19.52 → 19.11|7.88 → 7.71|
|paris_region_mid_zoom|17.74 → 17.76|19.75 → 24.42|3.247 → 3.383|21.02 → 21.05|7.88 → 7.88|
|paris_region_near_pan|17.65 → 17.68|20.18 → 20.69|2.916 → 2.837|21.17 → 21.51|7.85 → 7.82|
|paris_region_near_zoom|17.79 → 17.76|27.30 → 21.54|3.130 → 3.099|21.12 → 20.45|7.81 → 7.83|
|paris_local_pan|17.72 → 17.64|22.57 → 26.79|2.581 → 2.714|24.93 → 19.46|7.87 → 7.88|
|paris_local_zoom|17.59 → 17.53|19.61 → 18.84|2.420 → 2.909|21.84 → 24.95|7.94 → 7.88|

after 各组 p95 17.532–18.242 ms，维持约 18 ms。首轮 MID pan 存在 184.604 ms 单次长帧，保留原始 max，不用 p95 掩盖。为此增加相同 Release 来源的 MID 复测：idle 20 s、pan 30 s、zoom 20 s。

|MID 复测|p95 ms before → after|max ms|process GPU %|板卡 W|WS MiB|private MiB|video MiB|
|---|---|---|---|---|---|---|---|
|paris_region_mid_idle|17.87 → 17.82|18.54 → 18.86|0.00 → 0.00|3.40 → 3.44|599.39 → 598.86|836.21 → 828.06|157.20 → 157.20|
|paris_region_mid_pan|17.84 → 17.99|32.69 → 29.71|20.99 → 21.20|7.90 → 7.88|599.68 → 595.74|836.65 → 824.70|157.20 → 157.20|
|paris_region_mid_zoom|17.81 → 18.08|25.45 → 41.39|21.14 → 20.51|7.94 → 7.85|599.98 → 597.45|836.65 → 826.35|157.20 → 157.20|

复测用于说明采样差异；不能凭一个长帧推定或排除宿主调度/驱动原因。相机操作全过程土地 build=1、revision=0、split=0，行政缓存无 store / invalidation；相同 LOD 的 batch / upload / 几何缓存不因相机重新构建。新 LOD 切换仍允许有限按需加载。

## O. MEMORY / DRAW CALLS

|场景|WS MiB|private MiB|Godot video MiB|OS dedicated MiB|OS shared MiB|draw calls|
|---|---|---|---|---|---|---|
|world_idle|502.00 → 556.84|712.25 → 766.55|132.67 → 132.67|178.43 → 178.43|64.82 → 64.23|265 → 265|
|paris_region_far_idle|557.77 → 616.63|780.92 → 841.97|155.54 → 159.61|189.23 → 189.24|52.59 → 56.59|121 → 121|
|paris_region_mid_idle|563.25 → 621.73|791.95 → 850.87|157.32 → 161.39|195.23 → 193.23|52.59 → 56.59|105 → 105|
|paris_region_near_idle|565.36 → 621.84|795.96 → 850.87|159.33 → 161.36|195.23 → 193.23|54.59 → 56.59|86 → 86|
|paris_local_idle|570.05 → 626.38|806.57 → 865.29|163.03 → 165.06|201.23 → 201.23|54.59 → 56.59|66 → 66|

首轮 after WS 比 before 高约 55–59 MiB；这是实际测值，不声明 RAM 完全不变或已证明减少。补充进程启动采样可见两个版本都有启动分配波动；MID 复测 WS 基本相同（after 低约 0.5–3.9 MiB），private 较低约 8–12 MiB，Godot video / texture / buffer 完全相同。因此首轮的 RAM 增量没有稳定复现。水文性能采样对应七个生产文件差异（含新增 UID）；最终产品另修正历史资料页来源文案，共八个文件。数据、资产和模拟不变；没有证据表明新增持续运行的水文缓存。

可核实的固定资源：strategic FAR 280,392 bytes、MID/NEAR 184,000 bytes；Paris coarse 1,325,360、medium 3,818,312、local 8,731,512 bytes，before/after 完全相同。strategic batch 数 FAR=10、MID/NEAR/LOCAL=6，也完全相同。video 计数差异主要在 texture 统计，原始 texture/buffer 分项保留于 JSON；不宣称驱动内存计数等于逻辑网格大小。Godot Release static memory monitor 返回 0，视为不可用，使用 OS WS/private 数据。

[首轮 before 完整采样](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-release/summary.json)、[首轮 after](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-release/summary.json)、[MID before 复测](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/before-mid-recheck/summary.json)、[MID after 复测](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/after-mid-recheck/summary.json)。原始 results.json/system.jsonl 与所有 max 均保留。

## P. WINDOWS RELEASE

最终 [Windows 安装/运行包](D:/WWO/wwo/builds/windows/wwo-historical-boundary-water-r1.exe)：173,102,200 bytes；SHA256 `fd29b66cbc0767dba7b5021915f227c54852358b63dd55b46a347462f7f99396`。与上一产品相比 +1,816 bytes；embedded PCK 778 entries。

PCK 逐字节核实 17 个正式 JSON / shader；原始地理数据仍匹配本轮前的 SHA256。没有 tools/tests/docs/local-artifacts、研究地图/PDF、geo-env、probe scene 或合成夹具。原有 Windows ProductVersion 0.001a 警告保持，不是运行失败。

最终 EXE 的正常菜单启动已实际运行，OpenGL Compatibility、exit=0、无脚本/资源错误。该标准发行模板禁用 --script / scene path override，不能将外部旅程脚本注入最终 EXE；未改引擎、未重编模板或绕过此限制。完整界面旅程改用独立 Release 验证包，正常生产菜单仍为 main scene，只有隔离 autoload 驱动观察。与最终 PCK 逐字节核对 618 项生产资产、其中 155 个编译脚本完全相同，包含全部界面、渲染和权威模拟脚本。

该 Release 的 Menu → New Game → World/Region/Local/行政资料/水体 → World 旅程为 28 checks、0 failures；debug=false、editor=false，RTX 3050 OpenGL Compatibility。包含真实左键 Paris 选择、Labels 切换、右键 bearing 输入和完整 snapshot 不变。这是脚本驱动的真实产品界面检查，不能声称人手操作或在最终 EXE 上自动完成了全旅程；产品内没有加入测试入口或放宽状态约束。

[生产界面 Release 菜单](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/product-journey/product_menu.png)、[Paris MID](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/product-journey/paris_region_mid.png)、[行政身份资料页](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/product-journey/france_administrative_identity.png)、[右键 bearing](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/product-journey/paris_right_bearing.png)、[旅程记录](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/product-journey/journey.json)、[生产 PCK 等价审计](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/ui-pck-equivalence.json)、[最终 PCK 审计](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/package-audit.json)。

沿用只保留最新安装包的要求：清理 7 个旧产品/临时测量 EXE，释放 1.129 GiB；只保留上方最终产品。源码快照、截图、日志、原始测值和 SHA/PCK 审计继续保留，[清理记录](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/installation-cleanup.json)。

## Q. VALIDATION

统一验证：34 个 Godot suite，31,057 checks，0 failures；Python world-data suite 62 tests 通过；静态经济/来源确定性审计、fresh-process hashes、日志扫描通过。十年正式模拟 228.254171 s < 240 s，门槛没有提高。

包括正式土地拆分/谱系/继承/邻接与精确恢复、49 地点空间权威、political identity、Population/Economy、30 日与一年 golden、精确存档往返、WORLD/REGION/LOCAL 切换、Relief、Strategic、Paris Local、Selection/Labels/bearing。新增 Hydrography presentation R1 为 230 checks；全部 19 水体准入、显示分类未改变源事实、相机不重建/上传/解析当前 LOD、零 idle 重绘、whole-world save 不变。

真实截图检查：Seine 毛刺减少，Rhine/Danube/Nile/Volga 只改描边；里海淡入三角网格消失；Great Lakes / Baikal 面未出现新增可见内部接缝，Olkhon 等来源空洞与岸线仍保留。所有 source/LOD 文件 hash、30 河流/19 水体与 Paris 来源数量保持。原始源精度和历史行政缺口分别披露。

[统一验证日志](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/validation.log)；[本轮生产文件差异](D:/WWO/wwo/local-artifacts/historical-boundary-water-r1/production-changes.json)。before/after 主测量、淡入补充及 MID 复测共六组全世界 save_unchanged=true；采样、复测、界面验收与最终正常启动的 native 进程均 exit=0，无脚本/资源错误。

## R. REMAINING GAPS

行政：实际可复用历史接界图幅、完整试点覆盖、配准控制点/检核误差和边界不确定区间，继而真实 intersection/必要凸分解/成员审查均未完成；正式行政淡入与可变状态尚未实现。水文：NEAR/LOCAL 的资料概化与现代物理参考局限仍存在；本轮未新增测绘精度、1900 水位或全球连续水文网络。资源：首轮 RAM 差异和单次长帧未在复测稳定重现；全部原值仍保留，不把一次测量当作系统层面精确归因。

## S. NEXT RECOMMENDATION

下一步只建议先取得覆盖完整试点且允许衍生几何再分发的 1895–1900 图幅/数据及配准说明，再做带检核的接界数字化。之后评估当前凸土地表达能力，才决定拆分、正式 Département 与 persistence v16。低精度水文需要另立来源精度目标，不能通过放大或样式改善宣称解决。

本轮到此停止；不扩建全法国行政区、不制作行政编辑器、不生产其他 Local 或更多全球水文。
