# 英国及爱尔兰地表、水网参考 R43

这是现代地理显示衍生，不是1900年地形测绘、土地利用、河岸、水位或政治事实。海岸仍使用R27 Natural Earth；本包不修改主权、行政成员、经济、军事或存档。

## 高程与地表

全区使用Copernicus DEM GLO-90公开COG，包含英格兰、威尔士、苏格兰、爱尔兰全岛及适用离岛。选用同一产品以避免英爱之间混用垂直基准。OS Terrain 50只覆盖大不列颠，本轮未混入。没有扩大伦敦EA DTM。

- [GLO-90来源及获取方式](https://copernicus-dem-90m.s3.amazonaws.com/readme.html)。DSM包含植被、建筑；TanDEM-X主体2011—2015，部分填补更早。不是裸地DTM。
- WGS84-G1150 / EPSG:4326；EGM2008正高 / EPSG:3855，米。原纬向3角秒，经向间距随纬度变化。保留源文件实际仿射变换，不把像元间距当测量误差。
- 96份一度高程源片提取为600×600平均格网，再配准到1/512度显示格网。显示间距约217米南北、约102—141米东西，不是全国百米精度测量。统一绝对高程解释；坡面阴影的3倍系数仅用于明暗，不修改真实高度。
- [产品手册](https://dataspace.copernicus.eu/sites/default/files/media/files/2024-06/geo1988-copernicusdem-spe-002_producthandbook_i5.0.pdf)；[GLO-90许可，第18—20页](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)。

produced using Copernicus WorldDEM™-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM™-90.

地表独立读取[ESA WorldCover 2021 v200](https://esa-worldcover.org/en/data-access)，[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，[产品手册](https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/docs/WorldCover_PUM_V2.0.pdf)。18份三度COG通过16倍分类概览提取；保留10树木、20灌丛、30草本、40耕地、60裸露/稀疏、90草本湿地的分类含义。先映射线性色调，再按面积重采样，不平均类别编号。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.

Zanaga et al., ESA WorldCover 10 m 2021 v200, 2022. <https://doi.org/10.5281/zenodo.7254221>。WWO进行了分类概览提取、重采样、地貌色调混合、分片及Mip制作。树木类包括人工林；草本不等于历史牧场；湿地不等于泥炭；灌丛不专指石楠。其他类别保持中性。本轮没有取得1900年覆盖、泥炭厚度、历史植被带或全国精细LOCAL高程。

现有Natural Earth物理岛屿组件只用于材质支持范围和细化优先级，外扩海侧采样边沿；不制造新的海岸。范围不按1900或现代国界切割。马恩岛等保留原政治身份；海峡群岛沿用原地图，未计入本轮新增地表。

## 河流与湖泊

| 来源 | 使用内容、范围 | 坐标、年代和限制 |
|---|---|---|
| [OS Open Rivers](https://docs.os.uk/os-downloads/products/water-portfolio/os-open-rivers/os-open-rivers-overview) | 大不列颠WatercourseLink中有名称的inlandRiver、tidalRiver | 原EPSG:27700，转换至统一制图米制坐标后转EPSG:4326；2026-10-18下载版本，概化中心线，名义使用比例1:25,000。不是1900年河道调查 |
| [EU-Hydro River Network v1](https://land.copernicus.eu/en/products/eu-hydro/eu-hydro-river-network-database) | 爱尔兰全岛River_Net_l的Strahler≥3线；英爱InlandWater中N类天然湖泊且≥0.25平方公里 | 产品参考2006—2012，个别要素更新记录更晚；服务EPSG:3857，下载时转4326；丢弃未核对垂直基准的Z。使用影像解译水网，不使用DEM推断的Drainage Network |

OS数据适用OGL 3.0。原下载ZIP及doc/licence.txt保留在制作目录。

Contains Ordnance Survey data © Crown copyright and database right 2026

EU-Hydro按[Copernicus数据政策](https://land.copernicus.eu/en/data-policy)使用。R43进行了地理筛选、简化、分片、湖面约束三角化和制图分级，不代表欧盟认可本项目。

Generated using European Union's Copernicus Land Monitoring Service information; https://doi.org/10.2909/393359a7-7ebd-4a52-80ac-1a18d5f3db9c

[EU-Hydro用户手册](https://land.copernicus.eu/en/technical-library/eu-hydro_user_guide/@@download/file)第36—37页定义LKE_TYPE：N天然、R水库、U未知。本轮只准入N，不准入R/U；天然湖受现代调节的可能性仍在。未重建1900年湖岸和水位。

OS运河、湖泊连接轴、fictitious和无名线不准入；工程名称含排水、运河、引水等且尚未历史核对的候选保守排除。这不构成其余所有河段的天然性或1900年线位证明。普通支流按源名称组累计长度≥7公里筛选；长河和代表性主要河流进入概览。OS双语name2同时参与识别，包括Afon Hafren / River Severn。

河流保留中心线。两档线宽只表示制图层级，不是河宽。仅合并源端点精确相连的线，不补接缺口，不生成通航、河道工程、运输能力或历史水文事实。湖区、洛蒙德湖、尼斯湖、内伊湖、科里布湖、德格湖等使用实际多边形；保留岛屿和孔洞。

## 制作与运行

```text
python tools/map/build_british_surface_r43.py
python tools/map/build_british_hydro_r43.py
```

离线依赖沿用R42的numpy、scipy、Pillow、rasterio、requests；另用shapely（含约束三角化）、pyproj、pyshp。游戏不加载Python或GIS制作环境。

制作资料：`local-artifacts/british-surface-r43/`，包含源URL、CRS、源仿射、提取方式、研究提取及原高程片；`hydro/`保留OS原包、EU-Hydro查询结果和手册。评估中取得但未准入的EPA数据也留在制作目录，不打入游戏。

运行地表清单：`data/presentation/british_surface_r43.json`。37份FRT42原生Mip包与R42使用同一解码器、MapRelief、四张细化上限及相同GPU绑定路径。R43编码1的RGB为线性地表色调，A为固定hillshade减0.4，支持域外为0。R42编码0的高程/阴影/树木/支持通道保持原文件和原调色解释。没有把颜色纹理当高度。

1份1024×896概览，36份1088×1088细化。每份细化为2度核心加32像元真实相邻采样边沿；离线Mip直到1×1。英国细化和法国细化共享至多四个槽位；跨海视野最多两份概览。近档未到达的部分保留完整概览。WORLD不发出英爱地表需求。

水网沿用`StrategicSpatialLoader → LocalSpatialLod → LocalSpatialLayer`。1份主要水网概览和11份四度补充片，每片JSON＋压缩geom。补充片不参与物理地球完整条件。近档对当前视野需要的全部补充片一起请求；超过四片时继续使用概览，不发布任意前四片的残缺水网。剪裁到相邻共享核心边，湖面约束三角化在离线完成。主河不在补充片重复描画。离开按R39现有区域资源生命周期退休。

地表纹理不另建CanvasItem或SubViewport。新增水网使用原有类型的有界Mesh、材质及CanvasItem批次，没有第二地球或相机。伦敦LOCAL消费相同经纬度地表材质，保留原EA DTM、真实范围和原模型。无LOCAL高精度资料的其他地区继续显示区域参考，不生成伪造近景地形。
