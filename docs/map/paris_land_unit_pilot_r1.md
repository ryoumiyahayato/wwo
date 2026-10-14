# WWO PARIS LAND UNIT PILOT R1

> 历史记录。下文“当前”仅指记录时的阶段；旧实现、命令及同步要求不再是开发指令。不得据此恢复已删除的宿主、UI、探针或审计门禁。现行入口、WorldState 与 v15 存档见 [当前架构](../ARCHITECTURE.md) 和 [存档格式](../SAVE_FORMAT.md)。

本报告记录 `D:\WWO\wwo` 中的正式运行路径；开发测量项目与合成夹具均位于排除导出的目录。2026-10-08，Godot `4.6.3.stable.official.7d41c59c4` Standard / Compatibility / Windows x86-64。

## A. RESULT

`RESULT=COMPLETED_LAND_PILOT`

正式六块土地连续覆盖 454 km²；稳定身份、真实世界主权/控制、两次拆分、精确保存/恢复、地图不变和必要回归成立。最终统一验证 33 个 Godot suite / 30,827 checks / 0 failures，Python 62 tests 通过；十年 184.322189 s < 240 s。Windows Release 前后 16-stage 实机资源对照通过，没有新增常驻土地扫描或静止 GPU 工作。

行政成员仍为 `UNRESOLVED`，不宣称完成 Administrative Region。内部划分为游戏生成；物理来源只支持大陆内部覆盖，不能宣称精确 1900 水域、行政、地籍或所有权边界。

## B. EXISTING SPATIAL MODEL

既有 `VNextSpatialCatalog` 的 49 个地点继续是地点。`SpatialWorld._territories` 保存这些地点的既有四字段事实，`TerritoryState` 保存其当前控制者；旧地点控制仍接受既有不透明 controller ID。巴黎 Local 中的 `place:versailles` 是独立资料对象，没有被伪装成第 50 个正式城市。

新增土地由现有 SpatialWorld 拥有一份 `LandTopology` 和一份土地政治事实。LandTopology 只处理有界几何、身份、邻接、谱系和查询索引，复用 `VNextTerritoryUnit` 及冻结的初始 `VNextTerritoryUnitCatalog`。唯一当前控制存储仍是 TerritoryState，按 `territory_unit:*` namespace 保存土地控制，并核验当前正式政治 registry。没有第二套 SpatialWorld、TerritoryState、LandControlState 或 WorldRuntime。

## C. SOURCE REVIEW

| 来源 | 本轮审查结果 | 用途与准入 |
|---|---|---|
| Natural Earth 10m physical Land | 公共领域；官方 Land 5.1.1，固定上游仓库 tag v5.1.2；EPSG:4326 经纬度；全球概化大陆及大岛面 | 原始全球文件只作为 REFERENCE_ONLY 研究资料，经过裁切、投影、连续覆盖验证的巴黎有界派生资料为 ADMITTED / QUALIFIED |
| IGN BD TOPO | 法国官方现代地形资料、开放许可；现代资料不能证明 1900 年行政界或水域边界 | 作为更精细物理资料候选审查；本轮未下载、未用于生成、未准入 |
| 既有 Paris Local shard | 已有同代 Baedeker 地点与铁路等证据，完整历史行政 Polygon 缺失 | 复用地点身份和法国历史背景，展示几何未升级为通行能力或土地拓扑 |
| CShapes | 既有 REFERENCE_ONLY 与非商业条件不变 | 未作为新土地的 geometry、parent source 或准入依据 |
| Natural Earth Admin-1 prototype | 现代行政原型仍 REJECTED / prototype-only | 不参与土地或 1900 行政分配 |
| GeographyLoader 及既有政治显示几何 | 地图展示仍按原有证据与资料范围加载 | 不把显示面、country feature、河流或 railway corridor 转成土地身份 |

Natural Earth 官方说明其大陆面来自概化海岸线，并将大陆拆为相连片段。[Land 数据及版本](https://www.naturalearthdata.com/downloads/10m-physical-vectors/10m-land/)；[公共领域与商业使用条件](https://www.naturalearthdata.com/about/terms-of-use/)。本轮对这些片段求 union，再验证有限试点完全位于大陆内部；未使用 validity repair 补造缺口。原始文件 SHA-256 为 `1ac90796408bc6ad6911d69448485d3c4dbf2190370080368a09976e1c9f7416`，只用于研究完整性，不是存档兼容版本。

1:10,000,000 是大陆概化比例尺，不能理解为 10 米分辨率。来源未给出本试点的定量位置误差，只准入“位于大陆内部”的物理事实。现代来源不证明 1900 年政治或行政关系。IGN 后续候选入口：[官方 BD TOPO](https://geoservices.ign.fr/bdtopo)；[IGN 数据开放许可说明](https://www.ign.fr/institut/des-donnees-et-logiciels-ouverts-au-service-de-la-nation)。

## D. PILOT GEOGRAPHIC SCOPE

覆盖约 454 km²，投影范围宽 29 km、高 21 km；包括巴黎与凡尔赛，不覆盖整个 Paris Local 300 km 半径。外部六边形是明确标注的游戏试点范围，约东经 2.05963–2.45484、北纬 48.75573–48.94632。

固定 EPSG:2154 Lambert-93 / GRS80，局部原点 `(648000, 6862000)` 米。所有边界保存原点偏移后的米坐标，不依赖地图 AEQD anchor 或 camera。投影采用椭球 Lambert conformal conic 双标准纬线公式，并用开发期 PROJ 输出验证巴黎、凡尔赛正逆变换，显示转换预算 1.5 m。[PROJ 投影公式说明](https://proj.org/en/stable/operations/projections/lcc.html)。该预算和 1 cm 生成量化均不表示来源达到测绘精度。

## E. LAND UNIT DEFINITION

初始六块是具稳定命名 ID、明确 Polygon、正长度共享边邻接和独立政治状态的面对象：east、north、northwest、south、southeast、west。不是地点、行政省、军队、显示面或 5/25/50 km 网格。冻结 seed catalog 保留初始定义；当前活跃拓扑在 SpatialWorld 所属对象中保存，拆分只替换受影响的 immutable TerritoryUnit 记录。

## F. GEOMETRY COVERAGE

开发期 Shapely 审计：source mainland 与明确试点 extent 的交集等于 extent；六块 union 等于 extent；gap=0、overlap=0、面积=454,000,000 m²，无孔洞、孤岛、独立组件或人为修复。运行时 Godot 另行验证每个 convex simple Polygon、与外框包含关系、两两非重叠和总面积。非法自交、重复 ID、空隙、重叠和伪邻接负例均拒绝。

范围外是明确不覆盖的区域。大陆 mask 内的河流及内陆水域保留为 `INLAND_WATER_INCLUDED_UNCLASSIFIED`；本对象是领土表面，不声称每处都是干地，不推断水域通行或政治边界。没有依据水域资料挖洞，也没有为填满试点而填补 mask 缺口。原始大陆 mask 最近边界的近似距离约 144 km（经纬度平面选最近点后椭球测距），仅用于说明远离概化海岸，不是精确海岸测量。

## G. ADJACENCY / TOPOLOGY

初始每块有两个正长度共边邻居，中心点接触不算直接邻接。两向邻接必须一致，禁止 dangling/self/duplicate neighbor。共线分段重合允许拆分产生 T junction；拆分仅修订两个 successor 与原父块邻居，不在 camera 操作中全局重建。

有效性校验在 admission、相关几何 mutation 和 restore 边界发生。正常时间推进只有 O(1) 的 initialized 检查，不扫描土地。运行观察计数不写入存档。

## H. STABLE IDENTITY

初始 `territory_unit:paris_pilot_<named_sector>` 来自固定语义命名；不含数组下标、LOD、camera、行政名称或显示三角编号。反向排列输入仍得到相同快照与拓扑。seed 兼容版本为 `paris-land-seed-r1`，source reference 为 `territory_source:paris_mainland_pilot_r1`。

拆分操作接受显式且未使用的两个稳定 successor ID；原 ID 进入 retired archive，记录原 Polygon、parent、child IDs、split revision 和 source/geometry references。活跃与停用 ID 均禁止重复使用。最小谱系支持连续拆分，没有建立通用历史数据库。

## I. SOURCE GEOMETRY VS GENERATED PARTITION

`SOURCE_GEOMETRY` 表示来源支持的大陆内部空间覆盖；`GENERATED_PILOT_EXTENT` 是有界游戏范围；`GENERATED_PARTITION` 是游戏内部六块划分和后续拆分线。所有外框及内部线均不宣称为历史省界、所有权界或地籍界。`HISTORICAL_ADMIN_BOUNDARY` 本轮没有准入数据，不能从这些分割线产生。

## J. SOVEREIGNTY

新增土地的 `sovereign_polity_id` 位于 SpatialWorld 土地 facts，初始为当前正式身份 `state:country_fra`。历史背景复用同代 [Baedeker Paris and its environs，1900](https://archive.org/details/14thedbaedparis00karl)、既有 Versailles source leaf 427 与现有法国历史政治身份。并非使用现代省界或 CShapes face 推算。

`set_land_sovereign()` 只改变所选土地的主权，核验当前政治 ID；不修改 controller 或行政状态。真实试点测试建立德国主权、法国控制的不同值并验证保存与拆分继承；这个 mutation 是机制实验，不宣称真实 1900 巴黎曾如此。

## K. CONTROLLER

唯一权威位置是 TerritoryState 的 controller map。初始六块为 `state:country_fra`，依据明确的 `INITIAL_WORLD_ASSUMPTION`：1900-01-01 这一有限巴黎大陆试点按和平法国控制开局。没有 universal controller=sovereign 规则，后续修改不自动同步。

土地控制核验 active land 和正式 runtime polity；当前 controller 不留在 retired parent。restore 必须包含完整 active land scope，不能通过只传 49 place expected IDs 丢掉土地。既有 place controller opaque 语义保留。WorldState 中没有另一份土地 controller mirror。

## L. EXISTING PLACE COMPATIBILITY

正式地点数量仍为 49；初始 TerritoryState 共 55 个控制项，包含 49 place map ID 和 6 land ID。`place:paris` crosswalk、选择、政治资料卡和地点控制保持既有路径。改变巴黎附近土地控制，不改 `paris` 地点控制。凡尔赛继续通过 Paris Local 的 `place:versailles` 加载及 picking，不被伪造为 Formal Spatial 地点。Local、历史行政身份资料卡、Presentation boundary、Population、Economy 和时间金样回归分别验证。

## M. LAND SPLIT EXPERIMENT

真实 south 三角面沿外侧边中点到中心拆为 `south_a`、`south_b`。World Spatial 与 TerritoryState 双方先预检，随后在单模拟线程内无 await、信号或可失败步骤地提交：父面停用，active 6→7，两个 successor 继承父面主权、实际 controller 与 UNRESOLVED 行政状态，覆盖守恒，共边邻接正确，其他土地政治值不变。

自动回归再拆 `south_b` 为 `south_b1`、`south_b2`，active=8、retired=2，证明更深谱系及恢复。重叠/缺口拆分、未知身份、停用 ID 复用及损坏 ancestry 均拒绝。当前受控操作只支持一个凸单面拆成两个凸单面，不是 GIS 编辑器。

## N. ADMINISTRATIVE MEMBERSHIP READINESS

每块土地保存 `administrative_status="UNRESOLVED"` 和 `administrative_region_id=null`。意思是证据尚未解决，不是没有行政组织。Seine / Seine-et-Oise 身份与首府 dossier 保留；完整 1900 Polygon、正式 administrative owner、成员索引和动态行政边界仍未接入。此前 dossier 中 `BLOCKED_SPATIAL_MODEL` 是上一轮证据编译状态，不构成本轮土地状态；历史行政边界缺口仍是实际未解决条件。

没有以质心、最近首府、现代代码、market scope 或网格猜测成员。未来取得历史几何后，跨界土地须先准确拆分再明确分配成员。

## O. WORLDSTATE INTEGRATION

WorldState 继续只引用已有领域组件。WorldBootstrap 在历史 Evidence / runtime politics 建立后加载 LandPilotLoader；只有 Source Registry ADMITTED、完整 semantic seed 与已有 Provenance fact 相符、初始政治引用有效、几何拓扑有效时才安装。失败会中止正式世界构建。

LandPilotLoader 不拥有 runtime 世界；LandTopology 不保存主权或控制；SpatialWorld 不重复 controller；TerritoryState 不保存 geometry。没有新增 autoload、每帧事件系统、后台土地节点或 Population/Economy/Military 公式。

## P. PERSISTENCE VERSION

正式 root schema 为 `formal_world_simulation_v15`，仍为 18 个顶层字段；新增状态在 Spatial `vnext_spatial_world_v3.land` 中：topology（schema、semantic seed version、revision、active、retired）和 political facts。TerritoryState v1 map 结构自然扩展保存 land controller，没有第二个土地控制字段。无土地的独立 Spatial fixture 仍保持自身 v2 契约。

FormalPersistence isolated candidate 先恢复 runtime politics，再验证全部 land Polygon、active/retired ID、root cover、两子块面积与包含守恒、reciprocal parent/child、严格 split revision、邻接与主权 ID，重建静态 picking index；随后把 TerritoryState 绑定到该 candidate 的恢复拓扑并验证全部控制项。

Exact Variant payload 继续保留 float bits、PackedVector2Array 与 Variant 类型，通过既有 JSON wrapper / AtomicJsonFileStore 落盘。off-quantum 存档几何拒绝而非静默归一化。损坏候选不会改 live world。v14 和其他旧版本明确拒绝；不会猜测旧存档应生成的土地。外部 checksum 未参与运行 schema 或土地 ID 兼容判断。

## Q. PRESENTATION / PICKING

默认 WORLD / REGION / LOCAL 地图代码与地理表现不变，未绘制所有内部土地线。权威 picking 使用一次构建的 8 km 空间 bucket 和真实 Polygon，仅在明确查询时读取候选；bucket 是非持久索引，不是土地身份或全球计算网格。跨边 tie 按稳定 ID 排序；camera/LOD 不决定身份。

独立 native probe 在资源阶段结束后，一次性读取七块拆分后 geometry，在现有 RegionCamera 上画黄色轮廓和 `DEV: GENERATED_PARTITION` 标记，并从每块 screen center 回投影验证 picking。该场景位于 tools / isolated measurement project，被 product export 排除。默认产品不包含测试轮廓开关。

## R. PERFORMANCE / RESOURCE OCCUPANCY

NVIDIA GeForce RTX 3050 Laptop GPU；Windows Release，`debug=false`，1280×720，同一 16-stage probe、同 Godot 与 Compatibility。idle 20 s，pan/zoom 各 12 s；OS 样本排除各 stage 首 3 s、尾 1 s。before 是上轮保留的 production snapshot，after 是本轮 production resources；两次单独运行，没有同时跑十年测试。CPU 百分比按全部逻辑处理器归一，board W 为整张板卡读数；窗口隐藏仍使用真实 OpenGL，不能称为手工键鼠测试。

下表均为 **施工前 → 施工后**；资源列为窗口内中位数，frame 分位数来自该 stage 的实际 process-frame interval。

| Stage | CPU % | Process GPU % | Board W | WS MiB | Private MiB | Dedicated GPU MiB | Shared GPU MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| person_idle | 0.10 → 0.08 | 0.00 → 0.00 | 3.39 → 3.41 | 489.48 → 487.09 | 691.89 → 691.18 | 164.31 → 164.30 | 55.19 → 51.19 |
| world_idle | 0.05 → 0.05 | 0.00 → 0.00 | 3.39 → 3.39 | 501.09 → 500.21 | 710.79 → 711.66 | 178.43 → 178.42 | 64.23 → 60.23 |
| world_pan | 3.00 → 2.83 | 21.31 → 19.11 | 7.78 → 7.75 | 505.64 → 507.04 | 713.61 → 718.54 | 176.38 → 176.38 | 64.59 → 62.59 |
| world_zoom | 3.06 → 3.03 | 21.83 → 21.77 | 7.83 → 7.83 | 506.78 → 507.92 | 713.13 → 719.34 | 173.25 → 176.38 | 64.59 → 62.59 |
| region_far_idle | 0.05 → 0.18 | 0.00 → 0.00 | 3.41 → 3.41 | 554.17 → 559.94 | 777.06 → 785.19 | 189.23 → 189.23 | 52.59 → 54.59 |
| region_far_pan | 3.31 → 3.10 | 19.46 → 20.25 | 7.74 → 7.68 | 556.55 → 564.55 | 779.45 → 789.74 | 189.23 → 189.24 | 52.59 → 56.59 |
| region_far_zoom | 3.45 → 3.49 | 20.60 → 21.16 | 7.75 → 7.79 | 556.65 → 564.64 | 779.43 → 789.71 | 189.23 → 189.24 | 52.59 → 56.59 |
| region_mid_idle | 0.11 → 0.08 | 0.00 → 0.00 | 3.39 → 3.40 | 559.08 → 564.84 | 786.60 → 795.81 | 193.23 → 193.23 | 52.59 → 54.59 |
| region_mid_pan | 3.28 → 3.22 | 20.29 → 20.05 | 7.75 → 7.78 | 563.12 → 564.86 | 792.62 → 795.81 | 193.23 → 193.23 | 56.59 → 54.59 |
| region_mid_zoom | 3.37 → 3.60 | 20.84 → 20.98 | 7.83 → 7.81 | 563.16 → 564.91 | 792.62 → 795.81 | 193.23 → 193.23 | 56.59 → 54.59 |
| region_near_idle | 0.10 → 0.10 | 0.00 → 0.00 | 3.40 → 3.40 | 561.18 → 564.93 | 790.62 → 795.81 | 193.23 → 193.23 | 54.59 → 54.59 |
| region_near_pan | 2.86 → 2.99 | 20.13 → 20.05 | 7.73 → 7.76 | 561.20 → 560.12 | 790.62 → 795.81 | 193.23 → 193.23 | 54.59 → 54.46 |
| region_near_zoom | 3.44 → 3.43 | 21.59 → 21.77 | 7.80 → 7.76 | 561.25 → 560.17 | 790.62 → 795.81 | 193.23 → 193.23 | 54.59 → 54.46 |
| paris_local_idle | 0.18 → 0.09 | 0.00 → 0.00 | 3.40 → 3.40 | 565.77 → 564.53 | 803.14 → 809.04 | 201.23 → 201.23 | 54.46 → 54.46 |
| paris_local_pan | 2.66 → 2.97 | 22.47 → 25.46 | 7.83 → 7.86 | 568.41 → 566.62 | 805.77 → 811.12 | 201.23 → 201.23 | 54.46 → 54.46 |
| paris_local_zoom | 2.98 → 3.03 | 22.78 → 24.55 | 7.82 → 7.84 | 568.44 → 566.66 | 805.76 → 811.12 | 201.23 → 201.23 | 54.46 → 54.46 |

| Stage | Video MiB | Texture MiB | Buffer MiB | Draw calls | Redraw Δ | Frame p50/p95/p99/max ms |
|---|---:|---:|---:|---:|---:|---|
| person_idle | 125.66 → 125.66 | 104.66 → 104.66 | 21.00 → 21.00 | 64.00 → 64.00 | 0.00 → 0.00 | 16.66 / 17.71 / 18.08 / 22.92 → 16.68 / 17.71 / 18.13 / 23.41 |
| world_idle | 132.67 → 132.67 | 111.62 → 111.62 | 21.05 → 21.05 | 265.00 → 265.00 | 0.00 → 0.00 | 16.68 / 17.70 / 18.26 / 22.40 → 16.63 / 17.79 / 18.32 / 18.82 |
| world_pan | 132.79 → 134.82 | 111.74 → 111.74 | 21.05 → 23.08 | 309.00 → 309.00 | 420.00 → 420.00 | 16.62 / 17.57 / 18.09 / 19.79 → 16.64 / 17.67 / 18.04 / 18.18 |
| world_zoom | 132.79 → 134.82 | 111.74 → 111.74 | 21.05 → 23.08 | 318.50 → 318.50 | 420.00 → 420.00 | 16.66 / 17.63 / 18.05 / 18.30 → 16.64 / 17.64 / 18.16 / 18.61 |
| region_far_idle | 155.54 → 157.58 | 133.62 → 133.62 | 21.92 → 23.95 | 121.00 → 121.00 | 0.00 → 0.00 | 16.69 / 17.80 / 18.17 / 18.84 → 16.67 / 17.74 / 18.15 / 30.60 |
| region_far_pan | 155.02 → 157.05 | 133.48 → 133.48 | 21.55 → 23.58 | 405.50 → 402.50 | 433.00 → 432.00 | 16.65 / 17.72 / 19.23 / 32.72 → 16.63 / 17.63 / 18.20 / 21.75 |
| region_far_zoom | 155.54 → 157.58 | 133.62 → 133.62 | 21.92 → 23.95 | 438.50 → 433.50 | 420.00 → 420.00 | 16.62 / 17.68 / 18.16 / 18.68 → 16.67 / 17.66 / 18.13 / 23.37 |
| region_mid_idle | 157.32 → 159.35 | 134.12 → 134.12 | 23.20 → 25.23 | 105.00 → 105.00 | 0.00 → 0.00 | 16.68 / 17.77 / 18.14 / 32.02 → 16.68 / 17.75 / 18.25 / 23.45 |
| region_mid_pan | 159.35 → 159.35 | 134.12 → 134.12 | 25.23 → 25.23 | 424.00 → 424.00 | 420.00 → 420.00 | 16.65 / 17.68 / 18.09 / 21.07 → 16.67 / 17.57 / 18.05 / 20.92 |
| region_mid_zoom | 159.36 → 159.36 | 134.12 → 134.12 | 25.24 → 25.24 | 431.50 → 431.50 | 420.00 → 420.00 | 16.66 / 17.63 / 18.06 / 18.22 → 16.64 / 17.68 / 18.21 / 19.37 |
| region_near_idle | 159.33 → 159.33 | 134.12 → 134.12 | 25.21 → 25.21 | 86.00 → 86.00 | 0.00 → 0.00 | 16.65 / 17.82 / 18.16 / 18.75 → 16.68 / 17.76 / 18.12 / 41.98 |
| region_near_pan | 159.33 → 159.33 | 134.12 → 134.12 | 25.21 → 25.21 | 368.00 → 368.00 | 420.00 → 420.00 | 16.66 / 17.61 / 18.04 / 18.41 → 16.67 / 17.64 / 18.10 / 18.61 |
| region_near_zoom | 159.33 → 159.33 | 134.12 → 134.12 | 25.21 → 25.21 | 382.00 → 382.00 | 420.00 → 420.00 | 16.64 / 17.64 / 18.21 / 22.12 → 16.66 / 17.85 / 18.14 / 19.14 |
| paris_local_idle | 163.03 → 163.03 | 135.19 → 135.19 | 27.84 → 27.84 | 66.00 → 66.00 | 0.00 → 0.00 | 16.66 / 17.81 / 18.16 / 29.29 → 16.66 / 17.84 / 18.14 / 18.90 |
| paris_local_pan | 163.03 → 163.03 | 135.19 → 135.19 | 27.84 → 27.84 | 328.00 → 328.00 | 420.00 → 420.00 | 16.65 / 17.65 / 18.04 / 18.49 → 16.65 / 17.65 / 18.09 / 18.75 |
| paris_local_zoom | 163.03 → 163.03 | 135.19 → 135.19 | 27.84 → 27.84 | 331.50 → 331.50 | 420.00 → 420.00 | 16.66 / 17.63 / 18.08 / 20.09 → 16.71 / 17.80 / 18.28 / 19.22 |

所有 idle 阶段前后 process GPU=0%、map redraw Δ=0；after board 3.39–3.41 W。REGION pan/zoom after p95 17.57–17.85 ms，正常操作仍约 18 ms。LOCAL active process GPU 有约 1.8–3.0 个百分点的单次采样差异，功耗及 p95 接近；保留具体值，不据两次样本声称显著优化或所有指标完全相同。

WORLD/FAR 部分阶段 video memory 有 +2.03 MiB 的暂态差额，MID pan 之后基本一致；WS 差额约 −2.39 至 +8.01 MiB。现有异步 prewarm / LOD 的阶段驻留不同，不能将进程内存差额精确归给六块土地；新土地没有创建 GPU geometry 或后台 visible node。

每一阶段的 land start/end counters 逐值一致：active=6、retired=0、builds=1、coverage validations=1、adjacency validations=1、picking=0、neighbor queries=0、splits=0。正式初始拓扑本次 native build 969 μs。阶段完成后另测一次邻接查询 10 μs、控制修改 7 μs、一次真实拆分 334 μs；controller 不触发 topology work，不改变主权/行政值。拆分后 active=7、retired=1，精确 save candidate round trip 为 true，7/7 screen picks 匹配。

camera 阶段完整 snapshot 保持不变为 true；后续实际 control/split 会有意改变最终 snapshot，after `save_unchanged=false` 不是 camera mutation。默认地图截图检查通过；补拍开发轮廓时等待实际 draw submission，并明确标注 GENERATED_PARTITION。初次轮廓采集缺帧的原图与记录保留，未当成有轮廓的证据。

原始完整记录：[before summary](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/before-release/summary.json)、[after summary](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/after-release/summary.json)，各目录保留 `system.jsonl`、`results.json`、stdout/stderr 和截图。补拍：[开发轮廓及拆分 picking 证据](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/land-visual-proof/developer_generated_land_after_split.png)。

Windows product EXE 173,100,384 bytes，相较上轮产品 +47,440 bytes；PCK 776 entries。逐字节核对 pilot/source registry/provenance 的正式 JSON；tests、tools、docs、local-artifacts、global raw source 和合成 strip 均未打包。SHA-256 `bf016ac9752e7c535887717828f137e5fd3a3a4c2cd85bf71ef1df81b149a92b`。导出与两次 native probe 均退出 0，stderr 无脚本/解析/加载错误；既有项目版本 `0.001a` 的 Windows 数字版本 warning 保留，未修改无关产品元数据。

## S. SCALABILITY

正式试点限制 active≤256、retired≤250、单 ring≤64 vertices、最小面积 100 m²；本轮没有创建法国/全球土地库。静态 8 km bucket 在 admission/restore 建一次；split 只修改 parent/children/原邻居的记录与 index bucket。控制和主权 mutation 为单键操作；邻接查询复制已有邻接列表，不重算几何。

build/restore 的完整 coverage 与 adjacency 检查是 O(N²·P²)，限制在边界阶段，不适合作为未经改造的全球 GIS。picking 为 bucket 内候选检查和稳定排序，在窄条 fixture 中 bucket 候选可较多，不能声称恒定 O(1)。只有独立测试创建 256 条 synthetic strip；最终构建 342.751 ms、256 次 picking 5.798 ms（计时排除测试 PASS 输出），单独记录，不打包成法国事实。该模型证明小范围可变土地，不是全球扩展性能承诺。

## T. VALIDATION

最终命令：`powershell -ExecutionPolicy Bypass -File D:\WWO\wwo\tools\run_validation.ps1`，退出码 0。包含 headless 编辑器导入、解析/类型/加载日志扫描、历史经济静态审计、provenance deterministic check、62 项 Python regression、33 个 Godot suite / 30,827 checks / 0 failures，以及四组 fresh-process fingerprint 对照和正式 startup。

土地 A–G / I 和状态一致性回归 387 checks / 0 failures：正式 source admission、六块覆盖、输入顺序确定性、邻接、独立控制/主权、两次拆分、真实文件 Exact Variant 往返、损坏候选原子拒绝（包括 v14、unknown polity、gap、off-quantum、dangling neighbor、orphan lineage、retired control）。H 使用原有地图 camera suites 的整个保存值比较及 native 16-stage 完整快照比较；J 使用独立 Windows Release 前后资源测量。256-strip 规模 fixture 明确是 synthetic，未替代正式法国几何。

Formal Spatial / TerritoryState / catalog / source registry / WorldBootstrap / current-world convergence / political identity / rendering / scale transition / Paris Local / global strategic / physical relief / presentation boundary / Population / economy golden / personal economy / exact persistence / world integration / export resource contract 全部通过。30 日、一年及 180 日恢复后继续运行金样保持原值，没有修改 Population/Economy/Military 公式或放宽失败条件。

最终十年 184.322189 s < 240 s，42 checks / 0 failures；87,600 小时运行前后土地 counters 逐值相同：active 6、builds 1、coverage 1、adjacency 1、picking 0、neighbor queries 0、split 0。SimulationStep/Economy 不读取土地列表，Spatial internal validity 只增加 initialized 常数检查。此前完整复验也通过（185.829155 s）；上轮超时及本轮早期合成夹具失败日志保留，不将跨环境耗时差推断成算法优化。合成行政 fixture 改用既有隔离 control ledger，正式 TerritoryState 未弱化。

源几何 generator 在缓存的 pinned raw source 上执行 `--check`，结果 deterministic/current。product PCK 审计确认完整正式 seed/source/provenance 内容及开发资料排除。1280×720 native 截图检查了 REGION、LOCAL、旧行政身份 dossier 和一次性开发土地轮廓；这是脚本驱动的实机验证，未冒称人工键鼠或其他平台通过。

生产目录逐文件对照：本轮只修改 8 个既有 production files、新增 5 个文件（含 2 个 `.uid`）；after 测量项目与最终 production scripts/shaders/assets/data/scenes 逐字节一致。正式产品 EXE 已单独以 native OpenGL 启动（30 frames），退出 0，stderr 为空；该启动不冒称完整手工旅程。详见 [production source audit](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/production-source-audit.json) 与 `product-native-startup.out`。

完整最终记录：[统一验证日志](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/validation-source-final.log)、[source topology audit](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/source-topology-audit.json)、[package audit](D:/WWO/wwo/local-artifacts/paris-land-pilot-r1/package-audit.json)。

## U. MODIFIED / NEW FILES

正式数据：`data/land/paris_land_pilot_r1.json`；更新 `data/world_map/territory_source_registry.json` 和两份 `data/provenance` catalog。

正式脚本：新增 `scripts/content/land_pilot_loader.gd`、`scripts/vnext/spatial/land_topology.gd`；扩展 `scripts/content/world_bootstrap.gd`、`scripts/vnext/spatial/spatial_world.gd`、`scripts/world/territory_state.gd`、`scripts/persistence/formal_persistence.gd`、`scripts/formal/formal_world_persistence_document.gd`，以及 Godot 生成的对应 `.uid`。

原试点生成器已由 `tools/map/build_france_department_boundaries_1900.py` 的统一离线生成路线替换。原巴黎种子身份与谱系保留。此前测量与 probe 仅为历史记录，本轮未执行。

回归：新增 `tests/formal/formal_paris_land_pilot_test.gd`；更新 long-term balance 增加土地循环计数断言；更新 source registry / Population / administrative synthetic fixture 和当前 v15 schema assertions（Formal application、Spatial、map scale/local/paris/global geography/relief 等及 Python architecture contract）。未删除旧规则、降低门槛或修改模拟金样。

审计原始文件、研究下载、临时开发 Python 环境、测量项目、probe EXE 与资源日志在 `local-artifacts/paris-land-pilot-r1/`；正式导出为 `builds/windows/wwo-paris-land-pilot-r1.exe`。二者均为本地忽略目录。原有工作区其他变更未重置、提交、推送或清理。

## V. REAL DATA GAPS

仍缺精确 1900 内陆水域/干地几何、历史地籍与所有权界、Seine / Seine-et-Oise 可靠 Polygon 及配准、实际行政成员关系、terrain/river fordability/transport capacity 的来源与模型。非凸面、孔洞、multipart、合并和通用重划编辑尚未实现，输入拒绝而非修补。

地图未默认展示新土地控制；军事、经济、人口不按新土地重新分配。未来军事实体改变 land controller 仍须单独设计合法事件边界，不能把现有城市 control 直接传播到周围所有土地。

## W. NEXT RECOMMENDATION

先决定是否为这一已存在的小试点取得、配准和审查 Seine / Seine-et-Oise 的可靠历史行政几何，再验证跨界拆分与明确成员操作。精细水域/物理来源和非凸操作可按实际需要独立推进。未自动启动下一阶段，未扩建全球土地数据库。
