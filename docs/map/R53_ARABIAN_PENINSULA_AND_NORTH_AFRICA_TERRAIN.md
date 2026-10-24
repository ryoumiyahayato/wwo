# WWO R53 — Arabian Peninsula and North Africa Terrain Reconstruction

日期：2026-10-19。Godot 4.6.3 Compatibility。先制作阿拉伯半岛，再制作北非。资源进入正式地图的原地貌、水文、图标路径。未启动R53游戏；接入、导入和导出不等于用户视觉或性能验收。

## 实际基线与范围

核对了R39、R41—R52报告及当前MapRelief、GeographyLoader、StrategicSpatialLoader、LocalSpatialLoader、LocalSpatialLod/Layer、GlobeRenderer和地表Shader。R52已实际交付高加索、北欧及唯一预览。R48只完成故障整改，奥匈和意大利未扩库；R49欧洲俄罗斯未建设。R50西伯利亚、R51中亚/远东和R52资源存在，不能把此前未完成国家补记为完成。

继续使用R27物理地球、R37政治预制、R39唯一相机/24份coarse/有界medium、R40地理模式、R47共享图集和原LOCAL路径。R48地理选片、不同编码解码及须德海显示框修正仍在；R50已修正Debug栈确认的水面分支`Array[Dictionary]`赋值错误；线段预算、请求代数及取消检查仍在。未发现需要先解除的新无限请求或上传循环。没有新实机证据证明旧原生访问冲突、全部巴黎无响应、CanvasItem RID和首次上传长帧已消失。

半岛制作外框34—62°E、10—34°N，东侧北缘按实际半岛邻域下降，避免扩建整个伊朗。北非外框20°W—40°E、14—38°N，主要南缘18—20°N，尼罗河/红海邻带延至14—16°N。支持域平滑渐退，不以现代国家边界裁切。包括必要的地中海、红海及沙漠邻带，不等于完成整个苏丹、萨赫勒、西亚或意大利。

历史身份只读取原资料。原`arabia_gulf_geography_1900.json`保留拉希德、亚丁直辖/条约区、Kathiri、Quaiti、Mahra、科威特、卡塔尔、巴林及未定界荒漠等分别记录；不以现代沙特或阿联酋代替。`trucial_states`仍为保护关系，`sultanate_of_muscat_oman`仍为原主权身份。没有把奥斯曼名义权利、英国条约关系与地方实际统治合并成一种状态。现有资料未穷尽全部地方控制和边界，未借地貌补造。

北非继续区分1900摩洛哥苏丹政权、法国统治的阿尔及利亚、法国保护下的突尼斯、奥斯曼利比亚、埃及赫迪夫国及英埃共管苏丹邻区。未提前写入1912保护区、1911意大利利比亚或1922独立埃及。现有埃及记录为`dependency / controlled_territory`，控制关系指向英国；它没有完整表达全部名义宗主权细项，本轮不改政治数据。西撒哈拉宣称、实际控制及撒哈拉内部行政精度仍依原历史资料，不从DEM推定。

## 资料、精度与生成

| 实际输入 | 年代、基准和采样 | 许可与使用限制 |
|---|---|---|
| [NOAA ETOPO 2022 Surface](https://www.ncei.noaa.gov/products/etopo-global-relief-model)既有GeoTIFF | 1998—2022等来源合成；WGS84经纬度、EGM2008正高米；原60角秒，约1853米南北采样 | NOAA公开资料；全域连续高程。不是1900裸地测量，不以负高程判水 |
| [Copernicus GLO-90](https://registry.opendata.aws/copernicus-dem/) | DSM，主体TanDEM-X 2011—2015，有填补；WGS84/G1150、EGM2008米；原纬向3角秒、经向可变；提取600像素/度即6角秒，细片重采样1/512度，约217米南北 | [GLO许可](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)；分发衍生bin并署名。含树冠/建筑，非米级DTM |
| [ESA WorldCover 2021 v200](https://esa-worldcover.org/en/data-access) | 原10米分类，EPSG:4326；本轮多数450×450/3度分类概览，失败回退225，最近邻；实际源仿射保留 | CC BY4.0，[DOI](https://doi.org/10.5281/zenodo.7254221)。树木、灌丛、草本、耕地、裸地/稀疏、湿地等独立参考；不是1900土地利用 |
| [HydroRIVERS v1 Europe/Middle East及Africa](https://www.hydrosheds.org/products/hydrorivers) | 15角秒HydroSHEDS路由网络，主要SRTM2000及辅助资料；EPSG:4326二维；保留HYRIV_ID、NEXT_DOWN、MAIN_RIV和等级 | HydroSHEDS v1专用许可，沿用完整条款和规定署名；不单独分发原数据库。没有河名、实际河宽或逐段常流/季节性字段 |
| [HydroLAKES v1](https://www.hydrosheds.org/products/hydrolakes) | 2016合成，选用SWBD来源自然湖面；EPSG:4326；实际精度依源，不能把小数位当测量精度 | CC BY4.0；Messager等2016，[论文](https://doi.org/10.1038/ncomms13603)。只接入选定自然类，不批量安装所有现代水面 |
| [Natural Earth v5.1.2](https://www.naturalearthdata.com/about/terms-of-use/) | 现代混合年代；EPSG:4326；1:10M不是10米。原海岸、河流/湖心线，以及明确Playa类盐盆 | 公有领域；保留原件和对象ID。不能冒称1900精确岸线、盐湖水位或河岸 |
| [苏伊士运河管理局历史](https://www.suezcanal.gov.eg/English/About/SuezCanal/Pages/CanalHistory.aspx) | 确认1869通航；不提供本轮已取得的1900精确GIS线位 | 只提取历史事实，不复制网页图像。显示NE单轴参考，非现代宽航道或全部扩建 |
| [UNESCO绿洲目录坐标](https://whc.unesco.org/document/160478)、[FAO锡瓦历史说明](https://www.fao.org/giahs/around-the-world/detail/egypt-siwa-oasis/) | 锡瓦代表点29°11′59.3″N、25°31′18.7″E；出版资料未给坐标基准/量化误差 | 只提取名称、坐标事实并署名，无版图/照片/原文复制；不是绿洲边界或1900耕地面积 |

阿拉伯取源305项，北非478项，分别含14项、26项既有缓存复用，最终失败均为0。数量不是783份互不重复原件。GLO原始COG、提取GeoTIFF、仿射及URL记录留在`local-artifacts/arid-surface-r53/`；WorldCover采用合法COG读取和实际分类值。原ETOPO及R42—R52缓存不改。HydroRIVERS Africa原zip为107,873,468字节，HydroLAKES原zip为820,295,132字节，均仅作研究/制作输入，不进入游戏包。

制作入口：

```text
tools/map/build_arid_surface_r53.py arabia
tools/map/build_arid_hydro_r53.py acquire
tools/map/build_arid_hydro_r53.py arabia
tools/map/build_arid_surface_r53.py africa
tools/map/build_arid_hydro_r53.py africa
tools/map/build_arid_surface_r53.py finish
```

高程/覆盖提取及固定材质复用R42、R50、R51函数；旧视觉支持合成复用R52函数。水文复用R43预三角化/分片及R52来源条款。使用真实源仿射和公制距离做离线双向hillshade，不在滚轮时重算阴影。地表采用统一绝对高程解释，没有按国家拉伸高度、随机沙丘、山峰或绿洲模型。

## 阿拉伯半岛

内志与图韦克、内夫得邻区、达赫纳邻区、鲁卜哈利选窗、汉志/阿西尔、也门高地、哈德拉毛、哈杰尔和佐法尔有GLO-90细化；其间使用连续ETOPO。半岛山地、台地、盆地及大尺度沙丘地势来自DEM。不是全半岛90米原生纹理，更不是逐座小沙丘三维重建。

覆盖只用独立WorldCover类别。**60类是裸地/稀疏植被，不区分沙、砾石、裸岩和盐壳。**本轮没有取得可完整准入的沙地子类多边形。NE地理标签区不能代替沙海覆盖，未把它们烘焙成沙地。故内夫得、达赫纳和鲁卜哈利的地形已接入，精确沙地分类边界仍未完成，不能称为1900沙漠普查。

半岛水网保留12,224条源河段，形成349个流域/等级显示组。按真实源出口选择半岛流域，避免顺带重复加入底格里斯/幼发拉底主轴。只合并源相接端点，不补跨缺口直线。源没有河名，Wadi Hanifa、ad-Dawasir、Hadhramaut、Samail、Bani Khalid等名称尚未逐段绑定到源ID，不伪造名称对应。

源未提供水文季节性，故这些路由线统一标记`unknown`并画中性虚线；不是永久蓝河，也不宣称全为干涸河谷。HydrographyStyle已支持季节、间歇、干谷及运河样式，但本轮没有足够逐段属性，未把这些接口写成已完成分类。现代污水/灌溉、地名含Wadi、流量估计为零或所处气候都没有被拿来自动判定1900水文。

科威特湾、巴林、卡塔尔、特鲁西尔海岸、霍尔木兹、红海、曼德及亚丁湾沿用原NE物理岸线。没有新建海洋，没有把负高程低地填水；没有取得完整可配准1900半岛岸线，现代填海、潮滩和港区差异仍未逐段修复。水网也不改变航行、运输或军事能力。

## 北非与历史水文

里夫、中/高/反阿特拉斯、特勒/撒哈拉阿特拉斯、奥雷斯、阿哈加尔、塔西利、阿卡库斯、费赞、利比亚绿山、卡塔拉、尼罗河、西奈及红海西岸有选窗细化。其余连续ETOPO表达沿海平原、台地、山地、沙漠与河谷过渡。大东/西沙海及大沙海没有随机波纹贴图，沙、岩、砾石的精细分类缺口同前。

北非36,651条源河段、1,113个源流域/等级组进入按尺度分片的未知季节性网络。Sebou、Oum Er-Rbia、Moulouya、Draa、Chelif、Medjerda等所在窗口有源网络，但无逐一名称绑定和1900季节性资料；不把所有Wadi画蓝，也不按干旱位置删除源河谷。

### 尼罗河、三角洲和运河

尼罗河采用NE已有River和Lake Centerline轴线。新轴线明确替换旧`river:nile`，并保留制作域之外的原南段，避免替换后丢掉上游。补入`rivernum=19`的Rosetta Branch与`rivernum=20`的Damietta Branch。HydroRIVERS的`MAIN_RIV=10047863 / 10050558`不再次叠加；单流向路由不能覆盖真实三角洲分流。

源Lake Nasser为`Reservoir / ne_id=1159125095`，未生成水面。旧`africa.json`也没有安装纳赛尔湖，原NE陆地在取样点32.85°E/23.7°N仍为陆地。本轮没有只排除新增面、却留下旧蓝湖。现代库区内使用明确注明年代的概化湖心轴线延续尼罗河；它不是1900河岸，也没有反算被淹河谷的原始DEM。不能据此声称恢复了完整历史宽水面或旧坝工程。

苏伊士使用NE `rivernum=209`的单条运河系统，包括其原湖心轴线，样式为人工水道的细蓝灰长虚线。1869存在得到管理局史料支持；**没有取得1900精确线位/河宽，没有将现代扩建宽度或通航能力写入地图**。未据此建立运河企业、费用、贸易或军事规则。

选入HydroLAKES自然类Qarun（1468）、Great Bitter（1455）及Manzala源分量（15200）。后者仅为源中的73.28平方公里分量，不冒充完整曼扎拉湖。Burullus、Bardawil、Manzala取样点在原NE陆地之外，继续由原海岸/海水参考表达；没有将未匹配的湖面补成矩形。部分其他潟湖及现代围垦差异仍受原概化精度限制。现代自然类也不等于1900精确湖岸。

### 盐盆、绿洲与负高程

接入11个明确NE Playa源面，含Chott el Djerid、Fejaj、Melrhir、Gharsa、ech Chergui等及半岛两个源盐盆。采用中性盐盆色，保留岛/孔洞及预计算三角形。Playa本身只证明盐盘/间歇湖盆，未判定某日积水。内部复用既有`lake`多边形载体，显式`water_class=playa_reference`；**不是新天然湖泊身份**。现有物理水陆查询只依原physical land/ocean，盐盆不会因此变成正式水域。

卡塔拉及里海式负海拔地势没有自动填水。锡瓦采用一个有来源的代表点，ID为`geographic_reference:siwa_oasis_r53`，复用R47通用地点图标、避让、拾取及资料卡。沿用旧`settlement`展示载体，不创建正式聚落、人口或市场。没有按点缓冲出绿洲绿斑。巴哈里亚、法拉夫拉、达赫莱、哈尔杰及其他绿洲只保留实际WorldCover现代覆盖；本轮没有取得并安装可靠的1900范围或完整代表点集，不能写成已完成历史绿洲复原。

## 覆盖矩阵

E=ETOPO 60角秒连续基底；G=选定GLO-90提取/重采样窗口；W=WorldCover 2021。所有REGION状态指正式资源已接入，均未实机验收。G不表示整行地区均有原生90米数据；“未新增”不抹去原吉萨等有限LOCAL资料。

### 阿拉伯半岛

| 地区 | 高程来源 | 地貌贴图 | 水文类别 | 自然覆盖 | REGION状态 | LOCAL状态 |
|---|---|---|---|---|---|---|
| 内志高原 | E+G | 台地、坡面、河谷 | 源网络unknown | W | 连续基底+选窗已接入 | 未新增 |
| 图韦克山崖 | E+G | 真实高原边缘 | 河谷阴影、unknown轴 | W | 选定细化；非逐崖测绘 | 未新增 |
| 大内夫得 | E+邻区G | 沙漠宏观地势 | unknown，不猜常流 | W裸地/稀疏，缺沙子类 | 已接入；沙地界不完整 | 未新增 |
| 达赫纳 | E+有限G | 真实地势 | unknown | W；无完整沙带范围 | 已接入地貌；分类缺口 | 未新增 |
| 鲁卜哈利 | E+选窗G | 大尺度沙丘/盆地 | 源网络unknown | W；非精确沙丘覆盖 | 连续参考+有限细化 | 未新增精细沙丘 |
| 汉志 | E+选窗G | 西部山地 | unknown | W | 已接入 | 未新增 |
| 阿西尔 | E+G | 山地向蒂哈马下降 | unknown | W | 已接入选定细化 | 未新增 |
| 也门高地 | E+G | 高山、盆地、坡面 | unknown | W | 已接入 | 未新增 |
| 哈德拉毛 | E+G | 高原/深谷 | unknown；名称未绑定 | W | 已接入；不画永久大河 | 未新增 |
| 阿曼哈杰尔 | E+G | 连续山脉/山谷 | unknown | W | 已接入选窗 | 未新增 |
| 佐法尔 | E+G | 山地/沿海低地 | unknown | W实际类别 | 已接入 | 未新增 |
| 波斯湾沿岸 | E+有限G | 低地、源岸线 | 原NE水陆；不判负高程水 | W | 已接入；无1900岸线重建 | 未新增 |
| 红海沿岸 | E+选窗G | 山坡/狭长低地 | 原海岸、unknown网络 | W | 两岸同格网；岸线概化 | 未新增 |

### 北非

| 地区 | 高程来源 | 地貌贴图 | 水文/水域 | 自然覆盖 | REGION状态 | LOCAL状态 |
|---|---|---|---|---|---|---|
| 摩洛哥沿岸 | E+邻山G | 平原/丘陵/河谷 | 源网络unknown | W | 连续参考已接入 | 未新增 |
| 里夫山地 | E+G | 山地/坡面 | unknown | W | 选窗已接入 | 未新增 |
| 阿特拉斯山脉 | E+G | 主脊/谷地/南坡 | unknown源网络 | W，非1900林界 | 已接入；非全山精测 | 未新增 |
| 阿尔及利亚北部 | E+G | 沿岸至内陆高原 | unknown | W | 已接入 | 未新增 |
| 奥雷斯 | E+G | 高地/坡面 | unknown | W | 已接入选窗 | 未新增 |
| 突尼斯 | E+G | 北部丘陵/南部低地 | unknown、明确Playa盐盆 | W | 已接入；不固定全年湖面 | 未新增 |
| 阿哈加尔 | E+G | 撒哈拉内部山地 | unknown | W裸地/稀疏等 | 已接入选窗 | 未新增 |
| 塔西利 | E+G | 台地/谷地 | unknown、源盐盆 | W；岩性未细分 | 已接入；非小岩壁三维 | 未新增 |
| 费赞及阿卡库斯 | E+G | 沙漠盆地/山地 | unknown | W；缺沙/砾/岩子类 | 已接入选窗 | 未新增 |
| 利比亚绿山 | E+G | 山地/沿海地势 | unknown | W实际树木/其他类 | 已接入现代参考 | 未新增 |
| 利比亚沙漠 | E+有限G | 高原/盆地 | unknown | W | 连续区域参考已接入 | 未新增 |
| 埃及西部沙漠 | E+G选窗 | 卡塔拉等洼地 | 盐盆、锡瓦代表点；不填海 | W；无1900绿洲面积 | 已接入，历史范围缺口 | 未新增 |
| 尼罗河谷 | E+G | 狭长河谷/两侧沙漠 | 完整显示轴，排除Nasser面 | W现代谷地覆盖 | 已接入；缺历史库底DEM | 未新增；原吉萨保留 |
| 尼罗河三角洲 | E+G | 低地/源覆盖 | Rosetta、Damietta、潟湖参考 | W现代分类 | 已接入；非1900岸湖精测 | 未新增 |
| 苏伊士地峡 | E+G | 地峡/沿湖地势 | 人工单轴、Great Bitter源面 | W | 已接入；历史宽度未恢复 | 未新增 |
| 西奈 | E+G | 北部低地/南部高山 | unknown、原两湾 | W | 与半岛共用地理格 | 未新增 |
| 红海西岸 | E+选窗G | 山地/沿海低地 | 原海岸、unknown网络 | W | 与东岸统一坐标 | 未新增 |

## 资源、生命周期和文件

正式新增地貌383个bin：1份共享概览、382张2度细片，75张选定细化窗口。bin合计119,412,235字节。共享概览2700×2280，Mip解压数据32,830,188字节；普通片128×128，细化1088×1088，均有地理邻边。清单`data/presentation/arid_surface_r53.json`为1,589,277字节。

水文94份JSON及94份geom：4份概览、90份近档。JSON共9,782,590字节，geom共3,129,468字节，合计12,912,058字节。源流域/等级组1,462个、原河段48,875条；裁片后的实际内容记录1,790个（1,775条线组、11盐盆面、3湖面、1代表点）。最大单片51条记录。这些是离线逻辑记录，**不是实测GPU draw call**。相接源端点才合并；裁片边不当海岸描画。

R53正式运行输入573个文件，总长度133,916,609字节，含上述bin、清单、水文及3,039字节署名说明。原始GIS、GeoTIFF、全局HydroLAKES、Python和GIS环境不打包。继承的R52/更早资源及EXE长度另计，文件长度不等于显存或常驻内存。

MapRelief仍为**两份概览、四张有效细片、一个后台解码任务**；安装后继时可能短时多持一张。将欧洲/高加索原概览的有效支持合成进一份欧洲—北非—半岛共同概览，复用其原RGB/Alpha；没有为每国加永久槽位或整体模糊法国。真实地理重叠排序和2×2地理格选择不变。同一红海格只保留一个正式ID，邻边与色阶一致；旧支持域需要时合成并记录`surface_replaces`。原R52文件不覆盖，原GeoTIFF不改。

普通区域概览在4500米/像素以内按需进入，2500—4500渐退；细片750米/像素以内请求，300—750渐变。宽视野使用共同ETOPO概览，细片不足时仍有真实粗地貌。离开需求后原路径解绑材质并退休纹理；不会永久缓存旅行过的细片。

水文在物理包安装后、2500米/像素以内才按地理范围请求；近档500以内，所有相交细片合计不超过4才整体准入，否则保留概览。**概览没有统一固定份数上限，按视野相交选取；本轮最多四份新概览**，不能将“四细片”写成所有水文总驻留上限。数据按现有kind/样式/线宽合批，沿用每组1024/256段、每线片最多128边及水面2048面分组；没有每河/每湖独立材质或渲染目标。旧代在GPU创建前丢弃，保留完整旧显示等待后继。

WORLD仍以原全球coarse为基础。新增hydro描述进入原index元数据，但383张地貌、94份水文payload和原始资料不参加初次国家选择的24份coarse完成条件；没有因R53预读全北非。原R52格陵兰可选WORLD宏观显示保留。R51实际支持域与半岛之间仍有西亚未建邻区，继续使用原全球粗参考，不宣称复用不存在的西亚细片或R48意大利全国地貌。

实际修改：`project.godot`、`export_presets.cfg`、`scripts/content/geography_loader.gd`、`scripts/content/strategic_spatial_loader.gd`、`scripts/presentation/map/map_relief.gd`、`hydrography_style.gd`、`local_spatial_lod.gd`、`local_spatial_layer.gd`、`globe_renderer.gd`和`data/strategic/index.json`。样式属性从准入内容传至原分组、安装和重绘，沿用已有虚线Shader；未新建水文引擎或Shader副本。

实际新增：本报告；`tools/map/build_arid_surface_r53.py`、`build_arid_hydro_r53.py`；上述383个正式bin、一个清单、188个水文文件；`assets/licenses/r53/THIRD_PARTY_NOTICE_R53.txt`。具体bin/水文绝对路径可由清单的`path`与index的`arid_hydro_*_r53`项定位，源对象ID在对应事实中保留。

只删除本轮未发布、已被收窄支持域或最终分片替代的18个中间输出，共551,945字节。没有清理任何旧预览、旧地形、原始来源或其他工作线。删除项均在项目内：

```text
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_28_+54.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_28_+56.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_28_+58.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_28_+60.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_30_+52.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_30_+54.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_30_+56.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_30_+58.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_30_+60.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_32_+52.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_32_+54.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_32_+56.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_32_+58.bin
D:/programs/WWO/wwo/assets/maps/relief/arid_r53_32_+60.bin
D:/programs/WWO/wwo/data/strategic/arid_hydro_arabia_32_+40_r53.json
D:/programs/WWO/wwo/data/strategic/arid_hydro_arabia_32_+44_r53.json
D:/programs/WWO/wwo/data/strategic/arid_hydro_arabia_32_+40_r53.geom
D:/programs/WWO/wwo/data/strategic/arid_hydro_arabia_32_+44_r53.geom
```

## 检查、交付与未完成事项

已对LocalSpatialLayer和GlobeRenderer执行Godot局部`--check-only`，均退出0；必要资源导入退出0；383个新bin的头部尺寸、Mip长度和清单文件长度匹配。未运行全仓回归、CI、哈希、压力测试、游戏试跑或时间推进。没有碰真实五槽，没有修改相机、黄铜机械半球仪、正式政治/经济/军事/人口/人物/组织、GameClock或SimulationStep。未新增模型，没有Git提交或推送。

唯一导出目标：

`D:/programs/WWO/wwo/builds/preview_2026-10-19_arid_r53/WWO_1900_Arabia_North_Africa_Terrain_R53_Preview.exe`

使用现有Windows Desktop Internal Landmark Preview预设，x86-64、嵌入PCK。R52直接回退及此前必要版本/正式发布保留。导出退出0。唯一EXE长度1,347,990,216字节；目录内只有这一份EXE，另保留README、署名及HydroSHEDS许可。没有生成额外候选EXE或覆盖正式Release。导出保留两条既有Windows数值版本资源警告：`0.001a`不是纯数值版本；本轮只更新build label/id/sequence，没有修改既有版本识别值。

仍缺：1900精确海岸/潟湖/绿洲面积、沙/砾/岩覆盖子类、逐河段季节属性和名称绑定、完整1900苏伊士线位/河宽及现代库区淹没前地形。没有用猜造几何填补这些缺口。用户仍需检查红海两岸/阿特拉斯与半岛山地的纹理交接、沙漠宏观地势、尼罗河/分流、盐盆颜色、锡瓦定位、符号遮挡，以及巴黎近景和资源安装时的实际响应。R41同阶段7.507秒和后续用户目测约11秒不能当作R53新实测；未宣称帧率、启动、内存或风扇改善。

完成本轮交付后停止，不进入R54或其他地区。
