# 西班牙地貌与自然覆盖参考 R45

现代物理显示输入。不是1900年地形、森林、农地、水位或河岸调查。不产生土地、主权、行政、企业、产量、人口或军事属性。

## 范围与共享

既有CShapes快照中的Spain为gwcode 230，要素有效期1886-01-01至2019-12-31，包含游戏初始日。快照参考日1900-03-12与游戏日期分开记录。只用既有几何核对本土、巴利阿里和加那利的需求范围，不重定历史边界。

两个独立地理显示域：本土及巴利阿里为10°W—6°E、34°N—44°N；加那利为20°W—12°W、26°N—30°N。地理外沿渐退，不沿政治边界裁山脉。相邻法国、葡萄牙、直布罗陀海峡的资料是有限显示邻带，不计入邻国全国建设。细化核心只选择涉及既有西班牙范围及0.6度邻带的二度地理单元；材质与真实地势仍连续跨越其政治边缘。

比利牛斯继续采用法国R42同款DEM、垂直基准、绝对高度解释、公制梯度和Mip生成。完整法国核心直接用原资产，不复制一份法国DEM到游戏目录。相同研究提取可用只读硬链接复用，不改原件。法国原材质在其有效地理带保持优先。

## 高程

[Copernicus GLO-90公开COG](https://copernicus-dem-90m.s3.amazonaws.com/readme.html)与[产品说明](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM)：TanDEM-X主体2011—2015，填补可能更早；DSM含树冠和建筑，不是裸地DTM。水平WGS84-G1150 / EPSG:4326，EGM2008正高 / EPSG:3855，米。纬向原3角秒，经向采样随纬度变化，按实际仿射配准，不按文件名拼接。

研究提取为平均6角秒，游戏细化格网1/512度，约217米南北、156—192米东西。采样不等于测量精度，不代表米级LOCAL。原始负高度不改；仅显示色阶对海平面以下取零。3倍坡度只用于继承的离线明暗，不修改实际高度。

[GLO-90许可](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)：

produced using Copernicus WorldDEM™-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM™-90.

[IGN/CNIG MDT25](https://datos.gob.es/es/catalogo/e00125901-spaignmdt25)为25米格网，主要由PNOA地面类LiDAR的5米DTM插值，部分区域使用摄影测量；[IGN许可](https://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf)规定衍生署名及CC BY 4.0条件。已评估，未下载或纳入本轮运行资产。R45优先保持法国跨境同源DSM，没有把现代LiDAR当1900测绘，也没有新全国LOCAL地形。

## 独立土地覆盖

[ESA WorldCover 2021 v200](https://esa-worldcover.org/en/data-access)，原约10米，使用16倍分类概览；先将真实类别转换为线性色调，再面积平均。树木10（含人工林）、灌丛20、草本30、耕地40、裸露/稀疏60、草本湿地90参与显示。其余保持中性，不凭高程推定森林、沙漠、农田、岩性、雪线或冰川。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.

Zanaga et al., ESA WorldCover 10 m 2021 v200, 2022. [DOI](https://doi.org/10.5281/zenodo.7254221)。[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。WWO进行了概览提取、地理重采样、色调组合、分片及Mip制作。不称为1900年正式地态；现代农地不产生粮食，现代森林不产生木材或军事能力。

## 水文

[EU-Hydro River Network Database](https://land.copernicus.eu/en/products/eu-hydro/eu-hydro-river-network-database)，参考2006—2012，版本1.3（2020），部分要素后续更新。来源服务为EPSG:3857，本轮按4326下载，去除无垂直基准保证的Z。使用影像解译River_Net_l，不用DEM推断Drainage Network。

Generated using European Union's Copernicus Land Monitoring Service information; https://doi.org/10.2909/393359a7-7ebd-4a52-80ac-1a18d5f3db9c

[开放政策](https://land.copernicus.eu/en/data-policy)允许开放使用，要求注明来源、修改且不得暗示欧盟认可。实际[下载服务](https://image.discomap.eea.europa.eu/arcgis/rest/services/EUHydro/EUHydro_RiverNetworkDatabase/MapServer)。

只准入源Strahler≥3且HYP=1（常年）中心线。HYP=2间歇、3短暂、4干涸、未知均排除；对象名称本身标明运河、灌渠、水库、barranco、rambla、torrent等时也排除。河段名称常用“从某水坝到某支流”描述范围，不将其中的水坝名称误当整段人工水路。分类仍只是现代来源判断，不证明1900年持续有水；保留现代整治限制。保留源OBJECTID，不跨缺口连接端点。

本土水网采用涉及西班牙及有限邻带的地理单元；命名的Duero/Douro、Tajo/Tejo、Guadiana、Miño/Minho等主干保留查询范围内真实跨境下游，不在西葡国界切断。它们不产生葡萄牙的政治、交通或经济施工事实。巴利阿里及加那利只显示实际取得且通过上述筛选的要素，缺失时不补造蓝线。

只取N类天然水面且面积≥0.25平方公里，不纳入R水库和U未知类型。真实水面显示并集去除报告分区重叠，保留源ID与孔洞，离线约束三角化。没有把现代水库当成1900天然湖泊。河流按等级使用制图线宽，不从中心线扩成任意宽河面。没有精确历史河口岸线、水位或导航事实。

## 制作及运行

```text
python tools/map/build_spain_surface_r45.py
python tools/map/build_spain_hydro_r45.py
```

复用R42的COG提取、仿射配准、metric hillshade、原生Mip打包；R43的独立分类色调、水网分片和湖泊预三角化；R44的完整法国核心识别。没有另一套运行时。研究提取、源URL和参数留在`local-artifacts/spain-surface-r45/`，不打包Python、GeoTIFF或GIS环境。

编码3为本土/巴利阿里，4为加那利：RGB线性覆盖色调与中性高程组合，A固定DSM阴影减0.4。共享Shader既有解码分支，无新增国家专用Shader。不同编码使四张细化只替换对应概览。地理边沿权重独立，不用低阴影冒充资料缺失。

二度细化核心1024×1024，四侧32像元真实邻边，最终1088×1088。四个比利牛斯交接文件只保留42°N—42.25°N核心及相同邻边，尺寸1088×192；其北部使用既有法国细化。共同格网、固定色阶、相同光向、全Mip至1×1；瓦片外沿回接概览，不画矩形框。未新增法线贴图，保留离线坡向明暗及原LOCAL网格法线。

仍是一个MapRelief线程、最多两份地理概览和四张细化。REGION≤4500米/像素才请求相关概览；750至300逐渐细化。加那利只在其地理视野相交且入选邻域时读取，本土观察不要求其图像。水网继续沿StrategicSpatialLoader与现有有界GPU批次安装；250米/像素内请求补充，超过四片使用概览。

WORLD中心不发地区请求，国家选择不预读西班牙细化或LOCAL内容。新纹理完成后刷新现有按需画布，不增加相机等待。离开需求后从MapRelief及可见/隐藏材质解绑，区域批次沿R39退出。没有无限访问缓存、第二地球、独立海岸Mesh或新CanvasItem池。LOCAL没有可靠DEM时继续区域参考，不伪造米级山地。

实际交付：本土/巴利阿里32包（1024×640概览、27份1088×1088、4份1088×192交接），65,738,111字节；加那利9包（512×256概览、8份1088×1088），1,878,478字节。研究输入为本土131份DEM、23份覆盖；加那利17份DEM、5份覆盖；32份相同提取直接复用。水网14组JSON＋geom，15,176,744字节。加那利只取得14段HYP=1无名源线和零个满足筛选的天然湖面，不表示其他季节性水道不存在。
