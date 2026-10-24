# 法国与科西嘉地表参考 R42

本包只改变地图材质。不是1900年地貌、森林调查、政治边界或经济资源资料。物理海岸继续由原 Natural Earth 陆地几何决定。

## 高程

- Copernicus DEM GLO-90，公开COG渠道：<https://copernicus-dem-90m.s3.amazonaws.com/readme.html>。
- DSM，包含植被和建筑表面。TanDEM-X主体采集2011—2015；缺口可能使用更早资料。不是裸地DTM，不是1900年测绘。
- WGS84-G1150 / EPSG:4326，正高EGM2008 / EPSG:3855，单位米。原纬向3角秒；经向随纬度变化。采样间距不等于测量精度。
- 本轮提取600像素/度的平均高程，再配准到1/512度显示格网。高程原件与提取结果保存在制作资料目录。运行包只包含地势、阴影及覆盖的显示编码，不包含全国原始GeoTIFF。
- [产品手册](https://dataspace.copernicus.eu/sites/default/files/media/files/2024-06/geo1988-copernicusdem-spe-002_producthandbook_i5.0.pdf)；[GLO-90许可，第18—20页](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)。许可允许复制、分发、改编及组合，须保留来源与责任说明。

produced using Copernicus WorldDEM™-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM™-90.

本项目与这些机构没有认可或背书关系。下游使用者分发相应衍生资料时须保留上述来源、责任说明及原许可义务。

## 树木覆盖

- ESA WorldCover 2021 v200，EPSG:4326，原1/12000度网格，约10米赤道采样。
- 使用分类值10。该类包含树木主导覆盖、人工林及部分树木种植园，不等同法定森林、纯天然森林、树种或林冠密度。
- 读取公开COG的16倍分类概览，再把该类的二值存在采样平均到显示格网。这是现代分类参考，不能解释为精确林冠百分比或1900年林地。
- 未把其他分类转成农田、矿区、城镇或军事通行资料。没有按高程生成植被。
- 来源与[CC BY 4.0许可说明](https://esa-worldcover.org/en/data-access)；[产品手册](https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/docs/WorldCover_PUM_V2.0.pdf)。

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.

Zanaga et al., ESA WorldCover 10 m 2021 v200, 2022. <https://doi.org/10.5281/zenodo.7254221>。WWO进行了树木分类提取、重采样、显示混合及分片。

## 再生成与运行

运行 `tools/map/build_france_surface_r42.py`；需要重建配准缓存时加 `--rebuild`。离线依赖 numpy、scipy、Pillow、rasterio、requests。游戏不使用这些制作依赖。

制作资料：`local-artifacts/france-surface-r42/`。含逐文件URL、实际源格网与仿射变换、提取方法、提取日期、原始高程文件或有地理配准的研究提取文件，以及提供方手册和许可。没有新增哈希清单。

运行清单：`data/presentation/france_surface_r42.json`。RG​​BA四通道依次为对数高程、固定光照地貌阴影、2021树木类采样、地理支持权重。四通道都是线性数据，不是sRGB颜色贴图。材质由这些数据产生中性地势色阶和有来源的树木颜色。3倍只用于离线坡面阴影计算，不改变几何高度。

全国概览和当前至多四张细化瓦片共用原陆地Mesh、原投影及同一材质代码。细化瓦片有真实邻区采样边沿及离线Mipmap。离开需求后退出，不在WORLD或菜单预读。地方模型、地表高度、历史成员及正式世界快照不变。
