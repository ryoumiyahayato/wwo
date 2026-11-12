# 比荷卢地貌、水网与须德海显示参考 R46

此包是地图显示输入，不生成土地、国家、行政、企业、人口、产出或军事属性。现代地表与近1900海湾参考分别保留年代。不存在一套新的比荷卢地形引擎。

## 现代高程与覆盖

三国共用[Copernicus GLO-90公开COG](https://copernicus-dem-90m.s3.amazonaws.com/readme.html)及[产品说明](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM)。主体TanDEM-X 2011—2015，部分填补可能更早；DSM包含植被、建筑，不是裸地DTM。水平WGS84-G1150 / EPSG:4326；EGM2008正高 / EPSG:3855；米。纬向原3角秒，经向随纬度变化。

33份一度DSM先平均为6角秒，再按实际源仿射到1/512度显示格网，约217米南北、121—145米东西。保留负高程，仅显示色阶在零以下取零；不按负高程判水、不放大荷兰为山地。坡向明暗沿用R42固定公制梯度与3倍制图坡度系数，不改高程。

[GLO-90许可](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)：

produced using Copernicus WorldDEM™-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM™-90.

独立自然覆盖来自[ESA WorldCover 2021 v200](https://esa-worldcover.org/en/data-access)，[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。7份三度分类COG读取16倍概览，类别色调先转换为线性值再面积平均。10树木含人工林、20灌丛、30草本、40耕地、60裸露/稀疏、90草本湿地参与显示。其他类别中性，不从DEM推定林地、草原、泥炭、沙丘岩性或历史农田。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.

Zanaga et al., ESA WorldCover 10 m 2021 v200, 2022. [DOI](https://doi.org/10.5281/zenodo.7254221)。WWO做了分类概览提取、色调平均、高程组合、分片和Mip。不是1900森林或土地利用调查。

制作域2°E—8°E、48°N—56°N，是覆盖三国及有限邻区的地理矩形，不是现代或1900政治边界。33份DEM与7份覆盖提取全部直接复用已有研究文件，仅用于读取，不改原件。6份德国细化继续使用原文件和原运行键；新增一个768×1024概览及五份1088×1088细化，共14,158,135字节。目录共12项，包含上述六份共享项。

编码2与R44相同：RGB为独立覆盖色调及中性绝对高程组合，A为固定DSM阴影减0.4。独立地理边沿权重；相同Mip与真实邻区采样。没有新增法线贴图，保留离线坡向明暗和原LOCAL网格法线。

### 已评估但未采用的国家产品

| 官方渠道 | 已确认事项 | 本轮处理 |
|---|---|---|
| [AHN／PDOK](https://www.pdok.nl/introductie/-/article/actueel-hoogtebestand-nederland-ahn) | 荷兰现代高密度高程，可供水务和地表查询；不同批次、DTM/DSM和许可需逐产品核对 | 未下载全国AHN，不将现代圩田高程当1900土地；保留统一跨境GLO-90 |
| [Digitaal Vlaanderen DHM](https://www.vlaanderen.be/digitaal-vlaanderen/onze-diensten-en-platformen/earth-observation-data-science-eodas/het-digitaal-hoogtemodel)／[比利时NGI](https://ngi.be/aanbod/digitale-geodata/digitaal-terrein-model/) | DHM II采集2013—2015；NGI另有DTM产品 | 未取得运行提取，未把某地区产品误当三国统一基准；许可和高程基准未进一步用于本轮 |
| [卢森堡ACT LiDAR 2019 MNT](https://data.public.lu/en/datasets/lidar-2019-modele-numerique-de-terrain-mnt/) | 地面类点生成0.5米MNT，LUREF / EPSG:2169，CC0 | 已评估，未下载全国压缩原件；垂直基准未独立核定，不混入当前EGM2008区域材质 |

## 现代水网

[EU-Hydro River Network Database](https://land.copernicus.eu/en/products/eu-hydro/eu-hydro-river-network-database)，参考2006—2012，版本1.3（2020），个别要素后续更新。实际[ArcGIS服务](https://image.discomap.eea.europa.eu/arcgis/rest/services/EUHydro/EUHydro_RiverNetworkDatabase/MapServer)。服务3857按4326请求，源Z不用于高程。

Generated using European Union's Copernicus Land Monitoring Service information; https://doi.org/10.2909/393359a7-7ebd-4a52-80ac-1a18d5f3db9c

[Copernicus开放政策](https://land.copernicus.eu/en/data-policy)要求署名、说明修改且不暗示欧盟认可。使用影像解译River_Net_l，不用DEM推断Drainage Network。查询范围2.2°E—7.6°E、49.2°N—54.2°N；Strahler≥3，HYP=1。排除间歇、短暂、干涸及未知持续性；按名称排除未经核定的运河、港池和排水设施。N类水面仍可能含现代整治或分类误差，不代表1900天然湖泊调查。

本轮额外排除现代IJsselmeer轴、部分现代或疑似人工水面，以及明确晚于1900的水道。Rijkswaterstaat确认[Bergsche Maas于1904启用](https://www.rijkswaterstaat.nl/water/vaarwegenoverzicht/bergsche-maas)，[Schelde—Rijn连接于1975启用](https://www.rijkswaterstaat.nl/water/vaarwegenoverzicht/schelde-rijnkanaal)，不作为1900水网新增。原Maas旧支的现行名称和调节状态仍只作现代参考，没有补画1900连接线。

主要干流、分流与支流保持源几何；不跨缺口连接，不从中心线猜宽河面。线宽按等级为原制图线宽的0.50、0.90、1.15、1.40倍，不是实际河宽。旧须德海范围内不画现代圩田排水网，水面也不再叠现代淡水湖色。

共4组JSON＋geom，3,419,015字节：一概览、三补充；补充阈值250米/像素。固定水面已离线约束三角化。与R44、原欧洲Rhine重叠的528项旧绘制条目提供离线裁剪结果，保留范围外河段；运行只换旧条目的LOD绘制数组，原查询几何、来源文件、缓存shard与正式身份均不改。没有运行时GIS布尔计算。

## 须德海：明确采用1905资料，不冒充精确1900

[Rijkswaterstaat Kust 1905目录](https://data.overheid.nl/en/dataset/16571-kust-1905)，许可CC0 1.0；[NGR元数据](https://nationaalgeoregister.nl/geonetwork/srv/api/records/130c9742-c782-46d1-b0fd-442317a42869/formatters/xml)。原图由S. Mars于1905修订，RCE保存纸图；RWS数字化干湿界并以RD配准。目录的2021生效字段不是岸线测绘年份。未取得量化比例尺、潮位和配准误差，不称为精密海岸测量。

实际取得[WFS几何](https://geo.rijkswaterstaat.nl/services/ogc/gdr/diepte_ijsselmeergebied/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=kust_1905&srsName=EPSG%3A28992)，13条记录；水平EPSG:28992 / RD，米，无高程用途。ArcGIS FeatureServer初始请求报错后改用公开WFS，没有绕过访问限制。

以实际大陆岸线确定海侧，闭合计算路径全部位于显示窗口之外；窗口RD为110000—198000米、470000—590000米。不将窗口边当历史岸线或堤坝。减去原记录中的岛屿环；Pampus的3.060米、Ameland的0.294米端点缺口仅补同一明确岛屿周界的闭合线段，原端点不移动、原文件不改，过程在制作目录记录。没有跨无关线段吸附或猜造湾口。

得到约5251.07平方公里的有界历史海湾显示参考，包含部分邻接开放水域；面积是该显示窗口内的衍生量，不是“1900须德海精确面积”。Urk、Schokland、Marken、Pampus、Wieringen等来源岛屿保留。它覆盖现代Flevoland、Wieringermeer等后来圩田在该旧海湾内的地表，以及Afsluitdijk位置，恢复未封闭的视觉联系。[RWS资料确认Afsluitdijk完成于1932](https://www.rijkswaterstaat.nl/en/projects/iconic-structures)，[Wieringermeer于1930干出](https://www.rijkswaterstaat.nl/over-ons/onze-organisatie/onze-historie/rijkswaterstaat-in-de-tweede-wereldoorlog)。

通过现有水面三角形路径绘制，显式类别`historical_sea_reference`，颜色与原REGION海洋背景相同。内部`lake`是既有多边形水面的绘制类型，不是新淡水湖身份。没有新Shader、第二地球、海洋材质重制或全屏遮罩。水面完成后才随现有区域内容一起发布。

此项是来源1905的近1900显示替代，不是把IJsselmeer改名；仍有五年年代差与原图误差。它不改Natural Earth原件、政治拾取、LandTopology、经济土地或正式存档。WORLD仍用原现代粗海陆，历史水面只在适用REGION路径请求；不是全球历史海岸体系。后续年代海陆时序未实现，不能据此宣称已模拟1930年代围垦。

泽兰、瓦登海其他海岸没有取得本轮可用的1900配准全覆盖，仍保留现代概化物理参考及不确定性。未新增潮滩、泥炭、堤防或圩田经济属性。

## 制作和资源生命周期

```text
python tools/map/build_benelux_surface_r46.py
python tools/map/build_benelux_hydro_r46.py
```

复用R42—R45的离线DEM、分类、Mip和水网生产函数。研究目录`local-artifacts/benelux-surface-r46/`保留源URL、提取参数、RWS原始岸线、元数据及再生成方法，不纳入EXE。

MapRelief一个线程、最多两份地理概览和四张细片；共享德国文件维持原运行键，不反复创建别名。目录和图像只在REGION地理需求内读取，4500至2500米/像素渐入，750至300细化。WORLD及国家选择不请求三国高精度纹理、历史原图或LOCAL内容。

新增概览完整Mip为4,194,300字节；法国＋比荷卢概览及四张常规细片上限34,952,324字节，低于R44既有全库最大上限。不是显存、工作集或性能实测。离开需求后沿MapRelief、现有材质及R39区域批次解绑释放，没有无限地貌缓存或新RID池。没有新增全国LOCAL DEM、建筑、碰撞体或模型。

## 2026-11-08 城镇与有限海岸补充

后续城镇显示使用[OpenFreeMap](https://openfreemap.org/quick_start/)提供的[OpenMapTiles模式](https://openmaptiles.org/docs/schema/)及© OpenStreetMap contributors数据，ODbL-1.0；不改变上述R46高程、自然覆盖或须德海的来源。TileJSON为https://tiles.openfreemap.org/planet，固定实际取得快照20261101_080013_pt。离线缓存545个使用源片，累计36,796,703字节（预算计入缓存内其他已取得源片）；两路请求，上限3,000片/50,000,000字节。原始PBF和数值中间件位于项目外offline-map-sources/benelux_settlement_reference，不进入运行资源。

z9 landuse/landcover用于三国建成区、工业和林地概化；排除neighbourhood、suburb、quarter等地点区划面。13个城市窗口的z13同类覆盖替换粗面，building轮廓栅格化为两档带Mip的R8覆盖率。名义LOD14并不增加z13源精度；它不是原始建筑数量或逐栋实体。源片坐标为Web Mercator瓦片，经源extent解码为经纬度，再沿原RegionProjection投影。没有屏幕偏移对齐。

z12有限沿海完整片的water/ocean并集用于原物理海岸的闭合修正。只在差异不触及实际覆盖边缘时替换原陆地、海面及岸线，其他部分保留。现代常年river面用于城市及邻接河流显示；lake、reservoir、pond及间歇水面不作为河道补入。现代河口工程、潮位基准、1900港池和河道年代尚未核定，不据现代图形设定运输能力。原R46近1900须德海范围继续覆盖后来圩田；新城镇和河面从该范围扣除。

城市选择见data/local/benelux_city_reference_selection.json：布鲁塞尔、安特卫普、根特、列日、沙勒罗瓦、布鲁日；阿姆斯特丹、鹿特丹、海牙、乌得勒支、格罗宁根、马斯特里赫特；卢森堡市。半径2.5—4.5km只表示有限显示窗口，不是1900市界或人口门槛。其他聚落按来源概化；未获得历史范围的地点不补人口。R46记录的欧本/马尔梅迪政治来源问题未在本次改动中处理。

制作入口为tools/map/build_benelux_city_context.py，沿原save_city_meshes.gd生成原生资源；现有输出默认复用，--rebuild明确重制数值衍生。海岸沿原build_seine_coast_reference.py --area benelux，随后只编译受影响的物理分片。原件、许可证及恢复基线保留。

来源选择与海岸裁切分离：三国参考轮廓外加0.08°邻带，并限于实际取得的完整z9片。这个范围允许近岸城区延续，不能用于主权、土地或岸线认定。真正的海陆由现有物理岸线决定；原1905须德海继续扣除。coverage.geometry供法国概化离线生产器移除与新源的重复显示，不新增运行时GIS。法国IGN在布鲁塞尔也含FXX建成区，已按这个范围接管，避免粗底色覆盖新楼廓。

选择范围派生自既有cshapes_1900_snapshot.json，保留其CC BY-NC-SA 4.0来源声明；现代OSM地物保留ODbL-1.0。物理陆地继承原Natural Earth及已声明局部岸线，须德海仍是RWS CC0资料。不能把混合来源统一写成公共领域。
