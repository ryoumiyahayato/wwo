# WWO MAP GEOGRAPHIC FOUNDATION COMPLETION R1

**RESULT: COMPLETED_MAP_FOUNDATION**

本轮只修改地图 Content / Presentation 与离线准备。正式存档保持 v15；巴黎仍有6块土地、454 km²、行政成员 UNRESOLVED。经济、人口、人物、组织、军事、时钟、权威土地和控制规则未改动。原生自动验证通过；人工手动旅程未执行，证据与适用范围见R。历史行政仍是独立BLOCKED_SOURCE，不代表物理地图地理内容获得1900行政权威。

## A. CURRENT MAP COVERAGE

原有124个战略城市、32条历史铁路走廊、30条主要河流、19个自然湖泊/内陆水体；Paris Local 有53城镇、11铁路几何部分、1387河流及657岸线部分。WORLD 的 CShapes历史政治底图与静态 ETOPO2022地形继续使用。

本轮战略城市127个，河流/湖泊/铁路稳定身份数量保留。新增物理岸线与海陆显示修正：24个粗分片、314个非空细分片；未生成虚构地区、人物、企业、行政区、运输线路或正式土地。分片是显示资料打包范围，边缘不绘制。

## B. IDENTIFIED VISUAL PROBLEMS

|分类|施工前实际问题|处理|
|---|---|---|
|DATA_GAP|全球无独立中精度物理岸线；北欧主要城市缺席|新增物理参考与3个有当时证据的城市|
|DATA_FIDELITY_LIMIT|粗政治海岸在斯堪的纳维亚、日本、东亚等放大后粗糙；1:50M水系及其LOD长直段|物理参考保持独立；河流与19水体改用固定1:10M来源|
|DISPLAY_LOD|全球河流中距离再概化到1.5km；不必要的粗LOD先于实际请求LOD准备|物理粗1500m/中300m；直接请求当前LOD|
|VISUAL_STYLE|细岸线单独叠加会与粗政治填色冲突|仅绘制海陆差异色面；新增物理土地使用中性参考色|
|RENDERING_DEFECT|本轮预检发现新差异面极小三角形经float32转换退化|读取离线三角面直接转换；零面积显示面不提交；原事实不修改|
|SOURCE_RESTRICTION|1900行政边界准入仍不足|维持BLOCKED_SOURCE，未开启行政数字化|

施工前先正常启动当前唯一正式包，并检查生产资源一致的原生Release测量旅程。首轮探索测量与离线生成有时间交叠，未用作最终性能基线；重新完成无生成任务并行的 before-clean-release。

## C. SOURCE REVIEW

Natural Earth 官方[许可](https://www.naturalearthdata.com/about/terms-of-use/)允许修改及分发其公有领域数据。固定仓库版本 v5.1.2，commit f1890d9f152c896d250a77557a5751a93d494776；岸线物理层版本5.0.0-pre9、land5.1.1、river5.0.0。1:10M与1:50M是比例尺，不是地面10m/50m精度。版本日期2022-05-13不是统一测量年份；提供方未量化地理误差。

依据官方[河流说明](https://www.naturalearthdata.com/downloads/10m-physical-vectors/10m-rivers-lake-centerlines/)，水库中心线含人为连线，因此只选 River，排除 Lake Centerline 与人工运河。官方指出亚马逊部分与东北俄罗斯对齐存在疑点，未以插值或连接补齐。

海陆差异是既有政治显示足迹与物理land的离线差，属 REFERENCE_ONLY。政治几何本身保持原样。差异衍生数据保留既有 CShapes2.0 的 CC BY-NC-SA4.0 非商业、相同方式共享条件；不能把该部分写成纯Natural Earth公有领域。

Rand McNally1899 [图册](https://archive.org/details/philadelphiapubl00rand)的126/127页已实际查看：Stockholm、Christiania标为Capital，Bergen列为Chief City。仅新增3个显示身份，坐标用现代Natural Earth locator定位；未导入现代人口或行政归属。

完整raw Ocean GeoJSON的整体多多边形存在无效拓扑，因此未整体准入。只选并验证独立、有效的Caspian闭合组件；全球海陆参考使用已验证有效的land/coast。没有静默修复原始来源。

## D. GLOBAL COASTLINE

WORLD继续以历史政治几何显示国家和海陆概貌。REGION按需加入1:10M物理岸线、岛屿、半岛、海峡及群岛参考。两种事实分别保留：主权、控制、国家picking仍取原政治几何；物理岸线不进入土地或行政索引。

物理land减既有显示足迹，绘制中性物理土地；既有足迹减物理land，绘制海洋参考色。差异只解决显示错位，不给新增可见岛屿自动染上邻国政治颜色。参考色与政治色之间可见的窄差异带是明确的来源精度差异。

只画原始岸线片段；打包/裁切边不生成线条。日期线通过包围范围的±360°匹配选择相邻片，跨极点覆盖取全经度。离线处理保持孔洞；相机移动不进行几何简化或三角化。

## E. RIVERS

原30条河流全部保留稳定ID和PHYSICAL_REFERENCE类型。源从1:50M提升为同一固定仓库的1:10M River段；显示粗/中LOD为1500/300m。保持源有的断点及分段，不接水库、湖中心线或未经证实河段。

源顶点对比：Rhine102→493、Danube212→911、Volga220→786、Nile380→1849、Mississippi362→1180、Amazon443→1601、Yangtze361→1538、Yellow347→1921、Ganges323→1617。点数增长表示该参考的几何细化，不表示历史准确度增加。由量化变成零长度的微小LOD段不绘制，原始canonical参考仍保留。

## F. LAKES / INLAND SEAS

19个水体身份不变，18 Lake与1 Inland Sea保持原分类。复用固定1:10M Lake/Alkaline Lake几何；Caspian来自显式闭合Ocean组件并独立解释为内陆海，Black Sea仍为连通海洋。未按名称或面积批量推定类别。

Great Lakes、Baikal、Caspian范围与孔洞按有效源几何准备。1900水位、现代工程、岸线变化仍未知。保留上一轮薄水线、低miter、克制羽化及无alpha三角重叠的水面shader。

## G. SETTLEMENTS / RAILWAYS

新增place:stockholm、place:oslo（历史显示Christiania）、place:bergen，三个ID在既有城市名录中不存在，标注NEW。新城市不激活人物、人口、经济或组织。铁路仍32条显示走廊，不新增无当时审查的北欧铁路线。

铁路维持概略虚线，河流为薄蓝线；标签沿原rank排序和碰撞规则。未扩大为现代城市数据库。巴黎复用原place和铁路身份，避免全球层与Local重复标签及曲线。

## H. SCALE LOD

|尺度|显示与资源|
|---|---|
|WORLD|政治国家/旗帜/粗地形；不加载全球物理岸线分片|
|REGION FAR|重要城市、物理岸线/大水体/主要河流开始显现；只准备粗LOD|
|REGION MID|细物理分片、主要城市/河流/湖泊/概略铁路；只准备medium|
|REGION NEAR|保留300m显示简化的1:10M参考，不伪称Local测量精度|
|Paris LOCAL|沿用原Local资料与相机，释放隐藏的全球层|

当前物理LOD选择阈值1500m/px，GLOBAL近距离继续使用medium；物理岸线在8500m/px以上不准备。原连续缩放与旗帜/地形权重保留，只有当前LOD必要的准备发生。

## I. PARIS COMPATIBILITY

Paris Local内容、正式土地种子、控制状态及行政身份文件与施工前字节一致。REGION内全球河流/岸线按原Paris范围权重交接，城市按稳定ID抑制重复。LOCAL仍只在正式Paris内容支持范围生效；其他地区保持REGION及资料不足提示。

## J. PERFORMANCE

同机1280×720、Compatibility、RTX3050 Laptop、NVIDIA572.83。person/地图idle20s，pan/zoom12s；另外保留同标签开启、同WORLD进入路径的FAR pan/zoom30s复测。帧间隔为实际原生process-frame回调，包含所有长帧；idle回调不是GPU持续绘制的FPS。CPU是全逻辑核归一化进程百分比；板卡值包括整块GPU。OS采样约2s，长阶段剔除首3/末1s，帧时间没有剔除。

|阶段|before median/p95/p99/max ms|after median/p95/p99/max ms|CPU% before→after|process GPU% before→after|board GPU% before→after|W before→after|actual redraw after|
|---|---|---|---|---|---|---|---|
|person_idle|16.692/17.645/18.104/19.171|16.724/17.630/18.149/19.201|0.13→0.14|0.00→0.00|0.00→0.00|3.38→3.37|0|
|world_idle|16.668/17.866/18.172/19.559|16.665/17.740/18.129/18.885|0.14→0.14|0.00→0.00|0.00→0.00|3.38→3.35|0|
|world_pan|16.650/17.651/18.140/21.776|16.655/17.691/18.133/18.617|2.61→2.93|21.08→18.81|38.50→38.00|7.75→7.70|420|
|world_zoom|16.648/17.683/18.141/18.393|16.664/17.646/18.055/18.502|3.01→3.06|20.50→21.15|38.00→39.00|7.75→7.75|420|
|region_far_idle|16.671/17.621/18.080/23.161|16.663/17.766/18.197/23.264|0.10→0.13|0.00→0.00|0.00→0.00|3.43→3.38|0|
|region_far_pan|16.723/18.675/22.724/29.746|16.689/19.057/24.593/33.414|3.40→3.87|19.80→24.74|38.50→43.00|7.73→8.60|431|
|region_far_zoom|16.631/17.681/18.183/19.802|16.819/20.552/22.647/24.510|3.03→4.16|21.44→19.79|39.50→29.00|7.92→9.91|413|
|region_mid_idle|16.655/17.680/18.168/27.321|16.685/17.804/18.175/18.556|0.02→0.08|0.00→0.00|0.00→0.00|3.45→3.40|0|
|region_mid_pan|16.676/17.652/18.079/20.147|16.641/18.033/19.130/21.203|2.63→3.33|19.66→20.84|35.50→37.00|7.88→8.03|420|
|region_mid_zoom|16.620/17.836/19.763/23.965|16.636/18.574/23.906/36.391|3.39→6.67|21.75→21.52|38.50→39.00|7.88→8.01|490|
|region_near_idle|16.663/17.845/18.232/18.716|16.647/17.773/18.223/19.059|0.09→0.13|0.00→0.00|0.00→0.00|3.41→3.41|0|
|region_near_pan|16.625/17.709/18.251/21.894|16.640/17.711/18.113/21.369|3.20→3.42|21.65→21.78|39.00→38.00|7.83→7.97|420|
|region_near_zoom|16.693/17.806/18.991/21.426|16.649/17.768/18.488/20.654|3.35→3.70|20.65→22.91|36.00→40.00|7.82→7.96|420|
|paris_local_idle|16.654/17.658/18.159/20.919|16.686/17.654/18.183/29.814|0.10→0.12|0.00→0.00|0.00→0.00|3.42→3.41|0|
|paris_local_pan|16.630/17.755/18.099/18.642|16.643/17.802/18.652/24.481|2.92→3.14|20.10→20.60|35.50→36.50|7.83→7.85|420|
|paris_local_zoom|16.677/17.672/18.119/20.872|16.682/17.664/18.088/20.263|3.34→3.07|20.38→20.57|41.50→40.00|7.88→7.86|420|
|person_return_idle|16.646/17.783/18.183/20.486|16.686/17.899/18.244/25.001|0.14→0.13|0.00→0.00|0.00→0.00|3.39→3.42|0|

所有idle阶段：GPU0、draw增量0、CPU投影增量0，3.355–3.420W。普通操作median约16.6–16.8ms，除一次FAR zoom外p95为17.6–19.1ms。FAR短测zoom p9520.552ms完整保留；相同标签和进入路径的30s复测pan/zoom分别为16.715/19.057/21.890/35.549 / 16.685/18.559/20.715/32.498ms，没有稳定重现该p95。

施工中的256段小批次确实造成FAR p9521.971/22.332ms回退。改为1024段静态批次后恢复；源几何未删减，Paris Local仍256段。早期“单独FAR复测”未开启相同标签，不能替代同路径最终验收。历史MID pan184.604ms、初版max37.7ms、各次本轮max及失败日志全部保留。最终MID zoom max36.391ms同时伴随分片边缘切换，loads2→8、reads14→45；没有把这段称为完全无准备成本的操作。

原始数据：[before](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/summary.json)、[完整after](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/final-metrics-release/summary.json)、[同路径FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/matched-far-release/summary.json)。正常操作仍接近60FPS基线；静止低功耗保持，FAR操作成本有小幅增加。

## K. MEMORY / RESIDENCY

初版24个大分片使不可见细几何一起准入，MID首次约8s、战略GPU约30MB。测量证明确有成本后才细分既有Content打包；未创建通用GIS/Tile Manager。最终24粗片+314非空medium片，最多2个名录片、64个物理片。典型Paris FAR为6物理片/12.26MB输入/32.3MiB战略GPU，MID为4物理片/2.76MB输入/9.0MiB战略GPU。只准备active LOD，离开地图/Paris LOCAL后战略批次、标签、CPU内容及LOD缓存清空。

|阶段idle|WS before→after MiB|private before→after MiB|video after MiB|texture after MiB|buffer after MiB|active物理片|GPU批次|
|---|---|---|---|---|---|---|---|
|person_idle|489.1→494.9|692.4→704.4|125.7|104.7|21.0|0|0|
|world_idle|503.0→505.5|714.7→721.8|132.7|111.6|21.0|0|0|
|region_far_idle|565.6→778.5|795.2→1049.5|183.0|143.8|39.2|6|111|
|region_mid_idle|566.6→641.4|797.0→903.0|164.8|136.8|28.0|4|37|
|region_near_idle|566.8→652.4|796.9→912.3|164.8|136.8|28.0|4|37|
|paris_local_idle|571.5→627.2|809.6→885.5|160.8|135.1|25.7|0|0|
|person_return_idle|575.2→633.7|803.6→889.3|142.2|112.5|29.8|0|0|

全尺度after高水位：WS 787.4MiB、private 1058.6MiB、进程dedicated GPU 228.4MiB。纹理包含原政治旗帜、地形、字形与viewport；不是仅新增岸线。Return/Local行layer.metrics中的上次prepare统计保留历史值，实际resident以零批次、空active_lod及回归resident_buffer_bytes()==0为准，未把旧统计误作活资源。OS allocator高水位不等同于活跃内容，不声称返回人物页后全部RAM归零。

## L. GLOBAL TRAVEL

实际完成指定10站路径三轮，并补做同路径六轮连续旅行（非虚构地区）。所有完整world snapshot相同、v15，原生Release退出0。每次离开上一地区释放原数据引用和GPU批次；只保留当前有限内容。

|连续六轮的返回Western Europe|WS MiB|private MiB|video MiB|texture MiB|buffer MiB|资源/对象/节点|战略标签/政治标签|批次/物理片|
|---|---|---|---|---|---|---|---|---|
|1|645.0|891.3|169.7|137.3|32.4|162/3197/18|55/159|58/6|
|2|656.2|902.7|169.7|137.3|32.4|162/3197/18|55/159|58/6|
|3|682.5|923.4|169.7|137.3|32.4|162/3197/18|55/159|58/6|
|4|689.9|932.1|169.7|137.3|32.4|162/3197/18|55/159|58/6|
|5|687.4|933.4|169.7|137.3|32.4|162/3197/18|55/159|58/6|
|6|685.0|941.4|169.7|137.3|32.4|162/3197/18|55/159|58/6|

最后三轮WS为689.9→687.4→685.0MiB，对象3197、资源162、标签55/159、批次58与纹理137.3MiB固定；回访欧洲加载3.24–3.47s，没有越来越长。private为932.1→933.4→941.4MiB，未声称它完全持平；这是有限六轮窗口的证据，不能证明任意长运行时间的allocator高水位。未发现按访问次数增长的活跃内容、GPU、字体对象或标签引用。

测量审计发现旧采样器每秒留存整行指标，并在每站反复序列化全部历史。第一次三轮和六轮记录均保留，但不能单独用它们的RAM斜率推定产品泄漏。最终六轮改为磁盘JSONL流式记录，仅结束后组装报告；生产数据和编译脚本仍字节一致。所有全尺度RAM表是实测进程值，包含当时采样器自身的少量历史和序列化开销，没有把它写成纯产品模型字节数。

六轮高水位：{'working_set': 705.0, 'private_bytes': 953.2, 'dedicated_gpu_bytes': 206.6, 'shared_gpu_bytes': 71.8}MiB。最终组装测量报告阶段从高水位统计排除并明确标注measurement_export，所有准备、旅行与idle长帧仍保留。返回人物页战略标签0、批次0、物理片0、idle GPU0/redraw0。记录：[初次三轮](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/final-travel-release/summary.json)、[初次六轮](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/extended-travel-release/summary.json)、[最终流式六轮](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/streamed-travel-release/summary.json)；3秒短站OS采样可能只有0–2个，缺测以“—”记录。

## M. FIRST LOAD / TRANSITIONS

首次_region等待包括固定0.5s稳定等待，不能把它写成纯CPU加载。以下为完整after旅程的四个尺度进入：

|m/px|region等待s|战略worker/gate ms|LOD准备/GPU enqueue ms|战略首可见相对load ms|最大单准备step ms|
|---|---|---|---|---|---|
|4500|7.683|4977.2/4725.8|500.4/610.1|7179.9|12.3|
|1200|2.406|1169.5/1107.7|110.9/192.8|1912.7|15.3|
|400|1.629|1164.0/1096.5|112.6/185.1|1818.4|13.8|
|75|1.762|251.6/235.6|22.0/58.2|511.0|15.4|

LOD/内容首可见指标是该次prepare记录；缓存复用行可能引用先前load，不是又发生一次同等成本的读取。FAR首次约7.18s才显现完整物理资料，主要是证据准入与静态准备，期间原底图保持可见；该成本仍是限制。当前MID首次完整约1.91s，相机只改shader/变换，跨分片/LOD时才进行有限加载。回访欧洲耗时与六轮逐次转换记录留在原始JSON，未隐藏固定等待、gate成本或LOD边缘重新加载。

## N. VISUAL EVIDENCE

施工前/后各49张原生1280×720 PNG。before来自生产内容与旧正式包逐字节一致的Release；after矩阵使用最终同一几何/颜色，随后仅改静态批次分组。最终正式生产代码的原生菜单/滚轮/水体截图另列，二者未混称为人工操作。

|地区|before WORLD/FAR/MID/NEAR|after WORLD/FAR/MID/NEAR|审看结果|
|---|---|---|---|
|western_europe|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/western_europe_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/western_europe_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/western_europe_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/western_europe_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/western_europe_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/western_europe_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/western_europe_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/western_europe_near.png)|海岸与Rhine/Danube细化，虚线铁路可辨|
|scandinavia|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/scandinavia_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/scandinavia_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/scandinavia_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/scandinavia_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/scandinavia_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/scandinavia_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/scandinavia_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/scandinavia_near.png)|峡湾与群岛保留；3个历史城市；未伪造铁路线|
|russia|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/russia_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/russia_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/russia_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/russia_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/russia_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/russia_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/russia_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/russia_near.png)|Volga细化；内陆无岸线属于真实视窗|
|east_asia|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/east_asia_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/east_asia_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/east_asia_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/east_asia_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/east_asia_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/east_asia_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/east_asia_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/east_asia_near.png)|长江口、岛屿及水域改善，保留现代参考限制|
|japan|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/japan_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/japan_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/japan_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/japan_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/japan_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/japan_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/japan_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/japan_near.png)|主要列岛与海湾保留，政治中性色差仍可见|
|india|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/india_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/india_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/india_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/india_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/india_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/india_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/india_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/india_near.png)|Ganges细化；铁路与河流清楚|
|great_lakes|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/great_lakes_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/great_lakes_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/great_lakes_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/great_lakes_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/great_lakes_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/great_lakes_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/great_lakes_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/great_lakes_near.png)|Great Lakes水面、海岸孔洞及Chicago/Toronto清楚|
|amazon|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/amazon_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/amazon_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/amazon_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/amazon_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/amazon_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/amazon_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/amazon_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/amazon_near.png)|Amazon弯曲细化；近距离旷野不强加城市|
|nile|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/nile_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/nile_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/nile_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/nile_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/nile_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/nile_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/nile_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/nile_near.png)|Nile薄线；近距离沙漠不强加城市|
|caspian|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/caspian_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/caspian_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/caspian_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/caspian_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/caspian_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/caspian_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/caspian_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/caspian_near.png)|Caspian为内陆海水面，无内部alpha接缝|
|paris|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/paris_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/paris_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/paris_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/before-clean-release/paris_near.png)|[WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/paris_world.png) / [FAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/paris_far.png) / [MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/paris_mid.png) / [NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/paris_near.png)|巴黎各尺度原Local交接保持|

补充：[paris_local](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/paris_local.png)、[black_sea](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/black_sea.png)、[baikal](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/baikal.png)、[date_line](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/date_line.png)、[polar](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/after-verified-release/polar.png)。Baikal FAR视窗过大，真实水面细节另见[最终MID Baikal](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/baikal.png)。Black Sea/海峡为海洋；Caspian/Baikal明确是不同水体呈现；极区/日期线未观察到错误跨界大面、来源无关的三角接缝或内面重叠。

最终原生实际输入：[菜单](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/product_menu.png)、[巴黎Local](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/paris_local.png)、[实际点击资料卡](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/paris_right_bearing.png)、[滚轮MID](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/wheel_REGION_MID.png)、[滚轮NEAR](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/wheel_REGION_NEAR.png)、[返回WORLD](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/wheel_return_world.png)。

## O. HISTORICAL / SOURCE LIMITS

物理参考为现代概化地理，不重建1900河岸、海岸工程、水位、堤坝及冰川。河源中的断点与不确定对齐未伪造。地形仍静态低分辨率，战略铁路仍概略连接。全球资料不是巴黎Local等级；目前内容准入仍沿用1900年度快照，未猜测1901以后的城市/交通历史。

## P. ADMIN STATUS

**BLOCKED_SOURCE / DATA_GAP**。Seine和Seine-et-Oise身份/首府保留，6块土地成员UNRESOLVED。没有引入现代省界、市镇、固定格网、最近首府或生成土地边缘作为行政界。

APUR2021目录第16页的Atlas1895–1900与Banlieue1900继续是研究线索。Consultable en ligne不代表可再发行，也不能套用其他现代数据的ODbL许可。本轮未重新开展行政栅格配准/数字化，GCP和RMSE保持UNKNOWN。

## Q. WORLD FACTS / SAVE

Content只给Presentation。存档v15、土地6块454km²、初始主权/控制、行政UNRESOLVED均保留。authority、simulation、world、persistence、formal等保护文件及canonical政治几何进行施工前/后字节比较；地图旅程同时比较完整world snapshot。

## R. VALIDATION

统一验证exit0：35个Godot套件，31,659 checks、0 failures；Python62 tests通过。编辑器导入、所有套件、政治快照双进程hash、证据拒绝路径与日志扫描通过。十年206.461073s < 原内部240s上限，10年/87600小时未缩短；外部420s watchdog原已存在并只用于完整打印失败。

|套件|checks|failures|
|---|---|---|
|Formal personal economy and wages|104|0|
|Formal livelihood player journeys|39|0|
|Formal application and main/menu|33|0|
|Formal Person integration|60|0|
|Formal Spatial integration|35|0|
|Formal exact persistence|32|0|
|Formal Population production integration|476|0|
|Presentation content boundary|61|0|
|Administrative foundation R1 (identity + independent synthetic fixture)|87|0|
|Paris formal land pilot R1|387|0|
|Territory source admission|65|0|
|Territory unit catalog|58|0|
|Independent non-production control ledger|131|0|
|Formal map rendering regression|745|0|
|Formal map scale transition|1288|0|
|Formal map Local foundation|68|0|
|Paris Local Content R1|6537|0|
|Map visual scale utilization R1|13577|0|
|Map resource efficiency R2|47|0|
|Global physical relief R1|1192|0|
|Global strategic geography R1|2647|0|
|Hydrography presentation R1|254|0|
|Map geographic foundation R1|536|0|
|Historical provenance foundation|48|0|
|Runtime political identity foundation|1186|0|
|Formal economy 30-day and one-year golden|6|0|
|Formal economic boundary closure|542|0|
|Formal market identity foundation|649|0|
|Organization state|137|0|
|Formal organization composition|99|0|
|Current world domain convergence|32|0|
|Formal Windows export resource contract|374|0|
|Formal world integration|67|0|
|Formal world ten-year balance|42|0|
|Historical world economy data|18|0|

原生最终菜单/地图/滚轮输入旅程39 checks、0 failures；正式EXE普通菜单启动exit0。30日/一年golden、精确存档往返、World/Spatial/land/政治身份、Population、经济、组织与Presentation Boundary均列于套件。没有修改成长、行动/NPC时间边界或模拟公式，因此未新触发旧Codex成长审计范围。

两次旧夹具失败记录保留：Scale Transition只等待Local；Relief travel在全球内容加载期间立即检查idle。更新为有时限地等待有限准备，保留全部原idle/快照/几何/权威检查，并新增终止断言。未放宽十年、删检查或为headless提供模拟规则例外。

原生操作通过隔离autoload与Input.parse_input_event执行；人工手动输入旅程未执行，视觉审看使用真实原生截图。正式模板不允许外部场景覆盖，未绕过：正式EXE测试正常入口，隔离Release验证包的生产资源及编译脚本通过字节等价审计。日志：[最终统一验证](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/validation.log)、[39项原生旅程](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/ui-final-release/journey.json)、[首轮失败](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/validation-first-failed.log)、[第二轮失败](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/validation-second-failed.log)。

## S. RELEASE

最终Windows Release：258,678,488bytes（246.7MiB），before 173,102,200bytes，增加85,576,288bytes。PCK1116项，356个运行时/保护资料逐字节核对；原始新GIS、扫描、OCR、Python环境、开发工具、测试、测量日志均未打包。

SHA256：`91f2bfb046ce5cb6212903bba51a8fd1bcd057fd12f7e8547791c5ce1b32ba4b`。正式包：[wwo-geographic-foundation-r1.exe](D:/WWO/wwo/builds/windows/wwo-geographic-foundation-r1.exe).

原生UI/测量包各956项生产资源、155个编译脚本与正式包逐字节一致；baseline包也与旧正式生产资源相同。新包正式验证通过后清理旧历史水文EXE与本轮测量EXE（共12个EXE、回收2,917,418,096bytes），仅保留最新正式包。保留源码、来源、审计、截图和用户存档；清理清单见[安装产物清理](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/release-cleanup.json)。审计：[PCK](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/package-audit.json)、[348文件独立重生成](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/reproducibility-audit.json)、[347分片/1047显示ID/0非法几何](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/final-data-audit.json)。

## T. MODIFIED / NEW FILES

本轮生产修改仅限以下Content/Presentation；经济、人物、组织、时钟、权威土地控制、行政与持久化实现均与before一致。

|文件|职责|
|---|---|
|[scripts/content/strategic_spatial_loader.gd](D:/WWO/wwo/scripts/content/strategic_spatial_loader.gd)|在已有loader内选择有限粗/细分片；校验字节、来源、几何与显示角色；增加驻留指标|
|[scripts/presentation/map/local_spatial_lod.gd](D:/WWO/wwo/scripts/presentation/map/local_spatial_lod.gd)|读取离线显示三角面；排除float32零面积显示面；海岸静态批次1024段，Paris Local保持256|
|[scripts/presentation/map/local_spatial_layer.gd](D:/WWO/wwo/scripts/presentation/map/local_spatial_layer.gd)|直接准备请求LOD；按kind选择参考色与绘制顺序|
|[scripts/presentation/map/globe_renderer.gd](D:/WWO/wwo/scripts/presentation/map/globe_renderer.gd)|LOD替换期间保留旧显示；调整原政治岸线权重；Paris Local/隐藏时清空全球层；来源提示|
|[scripts/presentation/map/region_view.gd](D:/WWO/wwo/scripts/presentation/map/region_view.gd)|传递已有边界kind，支持政治岸线与物理岸线分别显示|
|[scripts/presentation/map/hydrography_style.gd](D:/WWO/wwo/scripts/presentation/map/hydrography_style.gd)|集中物理差异参考色；显式支持有效NE10 Caspian组件|
|[scripts/presentation/map/map_scale_style.gd](D:/WWO/wwo/scripts/presentation/map/map_scale_style.gd)|复用Content唯一medium阈值|
|[data/strategic/index.json](D:/WWO/wwo/data/strategic/index.json)|9份名录、24粗片、314细片的路径、SHA、bytes与有界LOD索引|
|[tools/map/build_geographic_foundation.py](D:/WWO/wwo/tools/map/build_geographic_foundation.py)|固定输入离线生成，独立输出/审计；不依赖游戏运行时Python|
|[tools/map/geographic_foundation_release_probe.gd](D:/WWO/wwo/tools/map/geographic_foundation_release_probe.gd)|原生尺度、旅行、长帧与资源采样；历史流式写盘，测量后组装报告|
|[tools/map/build_geographic_foundation_measurement.py](D:/WWO/wwo/tools/map/build_geographic_foundation_measurement.py)|冻结生产文件并导出隔离Release验证场景|
|[tools/map/build_geographic_foundation_ui.py](D:/WWO/wwo/tools/map/build_geographic_foundation_ui.py)|保留正式菜单的原生Input滚轮/点击验证包|
|[tools/map/summarize_geographic_foundation.py](D:/WWO/wwo/tools/map/summarize_geographic_foundation.py)|完整帧时间/OS指标与短旅行站汇总；仅排除测量报告组装阶段|
|[tests/formal/formal_geographic_foundation_test.gd](D:/WWO/wwo/tests/formal/formal_geographic_foundation_test.gd)|来源、差异角色、非法控制属性、LOD、日期线/极区、有限驻留/释放、v15快照回归|
|[tests/formal/formal_hydrography_presentation_test.gd](D:/WWO/wwo/tests/formal/formal_hydrography_presentation_test.gd)|实际lake材质断言；新增差异色面不冒充lake|
|[tests/formal/formal_map_scale_transition_test.gd](D:/WWO/wwo/tests/formal/formal_map_scale_transition_test.gd)|等待有限Local与全球内容准备后保留全部idle、几何共享与picking断言|
|[tests/formal/formal_global_physical_relief_test.gd](D:/WWO/wwo/tests/formal/formal_global_physical_relief_test.gd)|快速旅行后的有时限内容等待；保留静态纹理和idle检查|
|[tools/run_validation.ps1](D:/WWO/wwo/tools/run_validation.ps1)|登记新增地理套件，十年内部240s原上限保留|
|[docs/map/geographic_foundation_source_review_r1.json](D:/WWO/wwo/docs/map/geographic_foundation_source_review_r1.json)|来源、许可证、年份、比例尺、方法、历史适用性、不确定性与输入SHA|
|[docs/map/geographic_foundation_completion_r1.md](D:/WWO/wwo/docs/map/geographic_foundation_completion_r1.md)|本轮A–V验收报告|

9份名录/水文JSON与338份物理显示JSON的逐项路径、bytes和SHA见[完整347资产清单](D:/WWO/wwo/local-artifacts/geographic-foundation-r1/final-data-audit.json)。原始研究、冻结生产副本、SourceGeo审查、Python审计、PCK字节证明、失败日志和PNG保留于ignored local-artifacts；均不进入发行包。

## U. REMAINING GAPS

历史行政边界、第二个Local、全球更完整的当时城市/铁路证据、1900海岸/河道工程与水位、原政治岸线的来源精度差异和未量化误差仍保留为明确限制。没有以更多现代点、插值河段或假行政界掩盖这些缺口。

## V. NEXT RECOMMENDATION

本轮完成后停止地图基础设施施工。下一步由用户单独选择1900历史行政资料、第二个Local、地图UI信息架构，或返回玩法系统；不自动进入下一阶段。
