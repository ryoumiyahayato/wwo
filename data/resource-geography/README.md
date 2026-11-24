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

史料点覆盖欧、亚、非、北美、南美和大洋洲。尚无可用于判断全球矿产空白的完整调查。南极目前无矿产记录。第一批选入的矿产以可核查的历史地点为主，MRDS 广域候选、具边界的矿区面、农业适宜性、渔场、河网水力和设施模型继续单独接入。
