# 1900 年资源地理

第一批包含六种矿产的地点记录，以及农业土地、森林和牧场三张全球历史重建网格。

## 土地利用

原始数据取自 Hurtt、Chini 等人的 [LUH2 历史数据](https://doi.org/10.22033/ESGF/input4MIPs.10454)（UMD v2h 与 CMIP6 v2.1h 数据内容相同）。[数据发布许可为 CC BY-SA 4.0](https://www.wdc-climate.de/ui/cmip6?input=input4MIPs.CMIP6.CMIP.UofMD.UofMD-landState-2-1-h)。本目录的三个派生网格同样以 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 提供。处理包括选取 1900 年、按下表合并变量、量化并压缩。可复用 [源数据说明](https://luh.umd.edu/LUH2/LUH2_v2h_README.pdf) 和 [计算说明](https://luh.umd.edu/faq.shtml)。

| 图层 | 变量 | 含义 |
| --- | --- | --- |
| 农业土地 | `c3ann+c3per+c4ann+c4per+c3nfx` | 已耕作土地估计 |
| 森林 | `primf+secdf` | 原生及次生林地估计，包含次生潜在林地 |
| 牧场 | `pastr` | 管理型牧场估计 |

每层 1,440 列、720 行，原始分辨率 0.25°。网格由北向南、由西向东。数值是按原始网格面积归一的万分比，以小端 `u16` 存储。每层有 258,539 个有效网格，`0` 表示模型估计覆盖率为零，`65535` 表示无资料。远景采用有资料网格的面积加权聚合，点击返回原始网格。现代地表分类没有参与历史面积估算。

`tools/import_resource_land_use.py` 可用已有 `states.nc` 或 HTTP Range 提取这三层。土壤、灌溉条件、作物适宜性和林木品种暂缺。牧场层暂缺粗放放牧地。

## 矿产地点

`sites-1900.json` 逐条提供来源。经纬度是参考位置，`spatial_accuracy_m` 是保守位置误差，标为矿区的记录代表概略位置。适用期为 1900 年开局快照，`valid_to` 为排他年份。矿床、历史开采地点和矿区分别记录，已知归属可填 `deposit_id`。无记录表示尚未核实。未在史料中确认的储量、产量和品位留空。

史料点覆盖欧、亚、非、北美、南美和大洋洲。尚无可用于判断全球矿产空白的完整调查。南极目前无矿产记录。第二批还补入卡巴斯铝土矿区、维利奇卡盐矿、塔拉帕卡硝石矿区、波特兰角石灰岩采石区和亚当斯水电站。水电站记录的含义是历史开发地点，河段水力潜能和实际发电量暂缺。

### MRDS 发现与开采记录

`mrds-1900.json` 从 [USGS MRDS 地理服务](https://energy.usgs.gov/arcgis/rest/services/MRData/Mineral_Resource_Data_System/MapServer/3) 选取 A 至 C 级、带可解释的历史年份及主矿种的点。共 2,232 条矿种记录和 1,715 个地点，覆盖 12 种矿产。1,695 条矿种记录来自今美国境内。其他地区稀疏，地区空白按未核实处理。点位误差仅在 MRDS 提供可读米数时保留，坐标小数位与位置精度无关。

`tools/import_resource_mrds.py` 读取发现年、最早开采年和最后开采年，按资料标明的重复关联去重。1900 年及以前发现但未确认当时已经开采的地点按发现记录显示。此前已经开采而缺少 1900 年实际作业证据的矿点，状态为未知。最后一次开采早于 1900 年的状态为已停采。矿种相同的近邻记录也可能是不同矿井，保留各自源 ID。字段见 [MRDS 数据手册](https://pubs.usgs.gov/of/2014/1123/pdf/AppendixB_MRDS_Database_User_Manual_Explanation.pdf)。

具边界的矿区面、农业适宜性、历史渔场、淡水与河段水力资源、设施模型及第三批资源暂缺。
# HYDE 1900 agricultural grid

The economy map opens the 5 arc-minute agricultural grid under Renewables → Agricultural land or Pasture. Its bands are compressed separately and decoded on first use. The Rust API is `resource_geography::agriculture` and identifies a source cell by `agri:wgs84-5m:<row>:<column>`. Rows start at 90°N and columns at 180°W, both zero-based. Cell area comes from the WGS84 ellipsoid. Land area comes from the original HYDE land-availability grid.

[HYDE 3.2.1 baseline and supplementary grids](https://doi.org/10.17026/DANS-25G-GEZ3) by Kees Klein Goldewijk and colleagues supply the 1900 modeled physical area per cell. The distribution README states CC BY 3.0. Each band has 2,215,829 known cells. The original 5′ boundaries are preserved. `import_hyde_1900.py` converts km² to hectares, retaining source zero and treating `-9999` as missing. Each .zst contains 2160 × 4320 little-endian float32 values in row order, with `-1` for missing. The importer can read local archives or use bounded HTTP requests for the selected files.

Cropland includes irrigated and rainfed cropland. Rice is a subset of cropland, split into irrigated and rainfed rice. Grazing includes pasture, converted rangeland and unconverted rangeland. These are sources for physical land occupation. Harvested area accounting and modeled yield are separate. Overview shading divides summed hectares by the area of known source cells. Clicking the map always queries the original 5′ cell.

The existing LUH2 forest and land-use API remains available at its original 0.25° resolution for cross-reference. Historical crop area comes from HYDE for rice. GAEZ suitability, irrigated suitability scenarios and actual distributions for other crops are pending.
