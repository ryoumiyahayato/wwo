# Global Physical Relief R1 — Content / Presentation

本轮只提供静态 `PHYSICAL_REFERENCE`。山系、台地与平原的大尺度形态可作为百年游戏时间的背景；现代 DEM 不能证明 1900 年的精确地表、冰盖、岸线、城市、森林、耕地、道路、人口或政治归属。运行时不保留可查询高程，不向 WorldState、Economy、Military 或 v14 存档加入地形状态。

## 来源审查

| 候选 | 机构与版本 | 覆盖、分辨率与基准 | 使用状态与判断 |
|---|---|---|---|
| ETOPO 2022 | NOAA NCEI，v1；选择 60s surface 全球文件 | 全球含两极；60 角秒，NOAA 从 15s 降采样；WGS84 / EGM2008 米；格陵兰、南极采用冰面 | CC0-1.0；指南明确私人、学术与商业用途。完整全球文件和可追溯 datum 适合本轮离线派生。**采用** |
| GMTED2010 | USGS / NGA，2010 | 全球陆地；30 / 15 / 7.5 角秒；主要 EGM96，综合多源；官方指出部分高纬资料较弱 | 官方公开全球高程方案；本轮未下载或分发。分块、多产品与数据处理负担高于需要 |
| Natural Earth Shaded Relief | Natural Earth，1:10m raster 系列 | 全球预制灰度 relief；21600×10800 或 16200×8100；来自下采样 SRTM Plus，并裁至现代 NE 岸线 | Public domain；适合视觉参考，但本轮需要可自行控制的 DEM→relief 步骤，避免把现代岸线裁剪带入历史政治面。未下载或分发 |

主来源：[NOAA 数据与许可元数据](https://www.ncei.noaa.gov/access/metadata/landing-page/bin/iso?id=gov.noaa.ngdc.mgg.dem:etopo_2022)、[ETOPO 2022 用户指南 1.2](https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/docs/1.2%20ETOPO%202022%20User%20Guide.pdf)、[60s 官方下载目录](https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/data/60s/60s_surface_elev_gtif/)。比较资料：[USGS GMTED2010](https://www.usgs.gov/coastal-changes-and-impacts/gmted2010)、[Natural Earth raster](https://www.naturalearthdata.com/downloads/10m-raster-data/)、[NE 使用条款](https://www.naturalearthdata.com/about/terms-of-use/)。

实际检索时间、原始 bytes / SHA256、原始 PDF 与目录元数据保存在 `local-artifacts/physical-relief-r1/source/`。发行包只包含必要派生纹理及 `data/presentation/global_physical_relief.json` 的完整 citation；使用现有 HistoricalSourceRegistry / HistoricalEvidenceCatalog / HistoricalProvenanceGate，不新增来源体系。

## 可复现处理

`tools/map/build_global_relief.py --source <ETOPO_2022_v1_60s_N90W180_surface.tif>`：

1. 检查 21600×10800 Float32 栅格、左上角 (-180,90)、60s 像元。
2. 面积平均到 4096×2048，检查有限值与无效高程；负高程归零。
3. 周期经度 Gaussian .65 像元；纬向采用边缘延拓。按米间距计算梯度。
4. 固定西北 / 东北双光照，视觉坡度夸张 6 倍，叠加低权重 log-positive-height；不是可供算法使用的真实坡度。
5. Region 极点最后三行平均经度，两档最终首末行再次平均，消除极点方向差异。输出 R 通道为有符号形态，G 通道为量化 log-height，仅用于无政治面的背景。
6. Region 为 4096×2048 RG8；World 从同一派生结果面积平均到 1024×512。PNG 编码以 `.bin` 保存，运行时验证原始字节 hash，线程内解码并转换 RG8，主线程创建静态 ImageTexture。

负高程也包含低于海平面的陆地凹陷，本轮会压平这些区域；大型湖泊的复合高程、现代岸线工程和冰盖不能代表 1900。背景中的 positive-height 渐变既不是独立 shoreline fact，也不决定 polity/controller。

## 表示方案与资源边界

| 方案 | RG8 纹理 payload | 优点 | 代价 |
|---|---:|---|---|
| A 单张 1024×512 | 1 MiB | 最小驻留、没有细档读取 | 赤道约39.1km，Region 山脊模糊 |
| B 两档 1024×512、4096×2048 | World 1 MiB；Region / Local 17 MiB 上限 | 固定两档共享源；全球移动无需解码、地理 cache 或 tile seam | 近尺度约9.8km纬向分辨率；额外16MiB是全球 Region 档，不是细地表 |
| C geographic tiles | 取决于可见跨度与 gutter；未实施、未测运行功耗 | 同等细度可能减少驻留，适合以后真正高精数据 | 极区 / 远 Region 可见区域跨度大；邻片、重叠、上传切换与 seam 维护增加实现负担 |

本轮采用 B，前提是 Release 实测静止、动作和内存通过。4096×2048 属于有限且适度的背景纹理，不加载科研 DEM 或超高精全球图。World 接近 8500m/px 时预备 Region 档；退出细档到11000m/px后释放；隐藏地图释放全部 relief 纹理。所有 cached shader materials 同时清引用，不能让隐藏 Region 或 uniform cache 钉住已释放 texture。

按 camera dirty 更新 uniform；线程工作未完成时保留已有政治画面。完成后 `_process` 关闭，无 TIME、DEM 计算、geometry rebuild、shader 数据重建或文件轮询。全球旅行只能持有这两个有限资源，不建立按地区增长的 cache。

Compatibility 首次 GL program 编译另做一次 world-creation 预热：使用已有法国 mesh、两条投影与 flag/no-flag路径，2byte中性sample；已有两个viewport只在这次准备期间强制绘制一次，立即恢复disabled。没有读取DEM或提前加载高档地形。原始诊断出现约1.16s cold帧，保留证据；native准入必须确认最终预热确实提交了viewport对象，再审查首次地图显示。

近尺度通过连续降低 relief 权重保留模糊背景，Local 不能由插值获得25–200m地形。Political 色与 flag fade 保留原映射；Economy relief 仅为 Political 权重的20%。既有蓝色河流、rail style2、城市和标签在静态地形之上。

行政边界缺口仍为 `ADMIN_BOUNDARY_DATA_GAP`。Province 仍是以后可变的行政分组；本轮不使用地形、DEM 或 spatial aggregation cell 建立行政身份。
