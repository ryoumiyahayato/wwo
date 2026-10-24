# 德国欧洲地表参考 R44

本包是现代物理显示资料，不是1900年地形、森林、农地、河岸或水位调查。既有历史政治、行政、土地、经济和军事系统不读取本包来生成事实。

## 范围

既有CShapes德国要素`gw_255 / Germany (Prussia)`的欧洲包围范围为5.7554°E—22.8669°E、47.2747°N—55.4546°N。源快照标注1900-03-12；该德国要素有效期1886-01-01至1919-06-27，包含游戏1900-01-01。这里只据此核对欧洲施工范围，不重选国家、不复制政治轮廓为地表边界。海外殖民地不纳入。

地表制作矩形为4°E—24°E、46°N—58°N，包含东普鲁士、西普鲁士、波森、西里西亚、阿尔萨斯—洛林及必要邻区过渡。运行材质在地理矩形外沿连续淡出，不沿政治线截断。水网取覆盖历史欧洲范围及半度邻边的固定二度地理单元，并保留既有莱茵、多瑙河范围外显示。这不构成相邻国家的全国建设。

## 高程及覆盖

- [Copernicus GLO-90公开COG](https://copernicus-dem-90m.s3.amazonaws.com/readme.html)：DSM，含树冠和建筑。TanDEM-X主体2011—2015，填补可能更早；WGS84-G1150 / EPSG:4326，EGM2008正高 / EPSG:3855，米。
- 原纬向3角秒，经向随纬度变化。220份一度高程源片平均提取为600×600，再按源仿射配准到1/512度显示格网，约217米南北、115—151米东西。采样间距不是测量精度，也不是LOCAL裸地精度。
- 德国BKG DGM200已评估，但它针对现代德国，不能单独覆盖历史东部；本轮未混入，以避免国家边界及垂直基准交接。[BKG产品](https://gdz.bkg.bund.de/index.php/default/digitales-gelandemodell-gitterweite-200-m-dgm200.html)。
- [GLO-90许可，第18—20页](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)；[产品说明](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM)。

produced using Copernicus WorldDEM™-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM™-90.

覆盖独立来自[ESA WorldCover 2021 v200](https://esa-worldcover.org/en/data-access)，[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。34份三度COG读取16倍分类概览，先把真实类别转换为线性色调，再面积平均。10树木含人工林，20灌丛不专指石楠，30草本不等于历史牧场，40耕地不是1900农业用地，60裸露/稀疏不证明岩性，90草本湿地不证明泥炭。未取得的类别保持中性，不由DEM推断。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.

Zanaga et al., ESA WorldCover 10 m 2021 v200, 2022. <https://doi.org/10.5281/zenodo.7254221>。WWO进行了分类概览提取、线性色调平均、地势组合、地理分片和Mip制作。

法国已完整覆盖的4个二度核心继续使用原R42资产；30份相同研究提取以只读硬链接复用，没有重复下载或修改原文件。法国树木分类和原调色保留，不把其余未知类别补成1900年地态。

## 水网

[EU-Hydro River Network Database](https://land.copernicus.eu/en/products/eu-hydro/eu-hydro-river-network-database)，参考2006—2012，版本1.3（2020），部分要素有后续更新。使用影像解译River_Net_l，不用由DEM生成的Drainage Network。服务为EPSG:3857，按4326下载；删除未核对垂直基准的Z，不用于高程。

Generated using European Union's Copernicus Land Monitoring Service information; https://doi.org/10.2909/393359a7-7ebd-4a52-80ac-1a18d5f3db9c

按[Copernicus开放政策](https://land.copernicus.eu/en/data-policy)署名和说明修改，不表示欧盟认可本项目。几何下载服务：<https://image.discomap.eea.europa.eu/arcgis/rest/services/EUHydro/EUHydro_RiverNetworkDatabase/MapServer>。

线数据取源Strahler≥4，按等级和有来源名称分组。保留断开的源组件，不跨缺口造直线。图上线宽仅为制图层级，不是实际河宽。明显含运河、排水沟、人工水路名称的候选排除；其余仍是现代参考，不能逐条宣称1900年天然河道。没有准入现代基尔运河线位。

湖泊主要取源N类天然湖泊、面积至少0.25平方公里。Chiemsee（OBJECTID 45876）、Starnberger See（45865）原标U；[巴伐利亚环境局天然湖资料](https://www.lfu.bayern.de/wasser/seen_in_bayern/index.htm)提供独立依据，故明确列为例外。原U属性不修改为N。没有普遍准入U或水库R。

重叠、相邻的同源实际水面做显示并集，保留原OBJECTID与名称引用，再按真实孔洞进行约束三角化。博登湖源名含“Freiwasser international”，不把名称或分区解释成国界。没有擅定湖泊法理归属。

旧Natural Earth 5.1.2的1:50M莱茵、多瑙河范围外河段保留。只有新可选显示成功准入后才替换范围内旧线和旧博登湖面，防止重复。旧欧洲文件不修改；返回不使用德国细化的视野时仍用原显示。Natural Earth为[Public Domain](https://www.naturalearthdata.com/about/terms-of-use/)。其源观测年代混合、未知；元数据明确标识未知并使用无界日期范围，不把2022版本年份当作测量年份。

1:10M Natural Earth河流仅作资料评估，未新增运行要素：没有取得可用Pregel补充，Neman已有更细EU-Hydro参考，故不再叠绘另一条粗轴。东普鲁士部分现代俄境水网资料仍有缺口。没有伪造潮滩、泥炭或潟湖边界来填补来源不足。

## 制作与运行

```text
python tools/map/build_german_surface_r44.py
python tools/map/build_german_hydro_r44.py
```

复用R42的DEM仿射处理、metric hillshade、原生Mip打包，复用R43的分类色调和水面预三角化生产函数。离线依赖numpy、scipy、Pillow、rasterio、requests、shapely、pyproj、pyshp；不进入玩家运行依赖。

研究资料：`local-artifacts/german-surface-r44/`，包括源URL、实际仿射、提取方法、原高程或有地理配准的研究提取、EU-Hydro结果、来源核对。运行包只纳入`data/presentation/german_surface_r44.json`、57份`german_r44_*.bin`、15组`german_hydro_*_r44.json/.geom`。

地表编码2：RGB线性色调，A固定DSM阴影减0.4。支持范围和边沿权重由地理描述提供，不混进高程或阴影。R42编码0和R43编码1保持原文件和原含义。没有额外法线纹理、第二套陆地或新山峰GLB。3倍坡度系数只用于既有离线明暗，不修改真实高度。

57份为1份1280×768概览、56份1088×1088细化。4个完整法国核心不另写德国细化文件。细化使用2度核心、32像元真实相邻采样边沿及离线Mip至1×1；无逐片高度归一化。原有MapRelief仍最多两份概览、四张细化和一个工作线程。法国有效材质优先；德国地理过渡从下方连续衔接。

水网为1份概览和14份有界补充。补充门槛250米/像素，当前视野涉及的全部补充一起请求；超过四份时用概览，不发布任意前四份。运行沿用StrategicSpatialLoader、LocalSpatialLod、LocalSpatialLayer和原GPU批次安装。新增地表不另建CanvasItem；水网增加现有类型的有界批次。

WORLD没有德国地表需求，近档不参与国家选择完成条件。离开范围后按原MapRelief和R39区域生命周期解绑、释放。原LOCAL高度与模型不扩展，缺少精细DEM处继续使用区域地貌参考。没有新企业、木材、军事通行或历史地态事实。
