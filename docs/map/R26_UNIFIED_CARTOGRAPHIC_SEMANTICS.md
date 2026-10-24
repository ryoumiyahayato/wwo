# WWO R26 — Unified Cartographic Semantics

日期：2026-10-16。基线：本机 R25。Godot 4.6.3 Compatibility。

## 1. 更正 R25

此前问题截图来自法国沿海、海峡、科西嘉及法国—瑞士邻接区域。R25 沿用了错误地点描述，并把后续简答当作截图定位依据，没有核对图像位置，随后转向俄国和圣彼得堡。这是任务判断错误。R25 报告已加更正；俄国专项不作为本轮证据，也不继续施工。跨180°修正不能解释法国截图。

本轮按用户纠正的范围检查公共路径。读取本机 R20 法国旧返图，只作为既有结构参考，没有将它冒充 R25 当前画面。未启动游戏或采集新截图。

## 2. 五类地图与实际入口

正式契约见 [MAP_SEMANTIC_CONTRACT_R26.md](MAP_SEMANTIC_CONTRACT_R26.md)，其中记录五类职责、共享ID、允许读取和禁止推断、时期、模式现状及资源边界。

当前正式切换只有 political、fulfillment、shortage。后两项是经济满足率与短缺观察，不能称为产出。没有完整地理地形、地态或军事独立切换；本轮未增加空白页面。WORLD/REGION/LOCAL仍是相机和呈现尺度。

物理来源是 Natural Earth、ETOPO 和各处现有现代高程；历史政治来源经 RuntimePoliticalEntityView / HistoricalPoliticalEvidenceView / ResolvedMapContent 解析；行政经 AdministrativeLoader。覆盖是现有现代 OSM/水文资料。经济读取 FormalWorldEconomyView 与既有正式查询。军事由原 MilitaryMapAdapter/State/Service 解释 Spatial 和 TerritoryState。没有新账本、地图管理器或地理数据库。

## 3. 法国问题涉及的共同路径

当前物理显示并非完全独立的物理底图。它使用 CShapes 历史政治面作底，叠加 Natural Earth 与其的补陆/裁水差集。补陆和水域差集离线约束三角化；运行时 `StrategicSpatialLoader → LocalSpatialLod.prepare → GlobeSurfaceBatch → LocalSpatialLayer` 安装。原政治面由 `GeographyLoader → MapGeometryContent → GlobeProjection.source_mesh → PoliticalLayer` 提供。历史行政来自另一条 GIS 显示路径。

没有发现把法国行政多边形作为物理补陆权威的当前入口；但物理差集确实依赖历史政治覆盖。不能把“未用行政面”写成“物理与政治已经完全解耦”。差集产生细长多边形是两来源差异的几何结果，不等于可以随意删除。球面/平面投影又以有限线段近似这些边缘；本轮没有对尖角强行缓冲或移位。

### 实际修改

1. **物理面不再按三角形借政治身份的画法。** 原补陆按9000米内的候选政治面分组，制作其 UV，持有并复制模板材质，在 WORLD还可取得国旗和经济色。分类会暴露三角形之间的颜色切换。R26 的补陆只按物理类别合批，使用相同地势和中性色，不持有国家纹理、颜色或经济参数。已有国家政治面和旗帜保持。物理补陆统一在政治填充下方；其存在不再暗示附近国家归属。
2. **国家线与行政线使用相同的当前水域显示裁切。** 原 `_prepare_overlay` 只为 administration 请求裁水，country 路径绕过。现在所有近景陆上边界墨线均使用已安装物理LOD的水域差集。原国家源线、行政 GIS、多边形拾取、成员与主权不变；不把此裁切当海上法理边界。
3. **预制三角形角色显式传递。** Loader 将已有 `lod_geometry_role` 传至准备端。只有声明为预制三角形的输入走原直接编码；普通含孔多边形仍走原完整环/孔路径。当前物理资料已声明并验证该角色，不能把这项接口澄清宣称为发现法国文件被错误截成三点。

R18/R19 已删除的独立海岸源重复绘制、双扇面问题、闭环端帽、已安装LOD交接没有重复施工。LocalSpatialLoader 已跳过与统一物理外缘不同的 LOCAL coast；GlobeRenderer 已在物理海岸可见时关闭政治来源 coast。保留这些行为。当前线、面 REGION 投影使用同一相机基底和 bearing，没有依据对法国单独偏移。

这些修改修正了颜色归属和近景线裁切路径，**没有证明全部三角缺口、深色窄带和几何接缝已消失**。完整物理底图与政治墨层的几何解耦仍未完成。没有用海色大面掩盖异常，也没有重制原海岸/GIS。

读取法国西侧、海峡及科西嘉所在的现有中尺度字段可见，`physical_1_4_mid_5_1` 的补陆索引包含552个借 `gw_220` 的三角面及94个无借色面；`physical_2_4_mid_0_1` 包含339个借 `gw_220` 的面及其他国家/无借色分组。它们均声明预制三角形。这证明相关准备分支实际作用于这些法国周边分片，不是只对俄国成立。但整片分片不等于截图中的具体位置，不能据索引计数认定缺口成因。

REGION 在 R21 已将补陆旗帜/政治权重归零，本轮保留，不重新申报这项画面改善。新增的是取消仍存在的 WORLD借色、准备端分组/UV/模板持有，以及跨尺度共同材质路径。对近景三角缺口的几何归因仍未确认。

## 4. 地形与地态

原 LOCAL 源包将 cover_meshes 与 height_rows_m 放在同一资料包。R26在加载后拆为 `LocalSpatialContent.surface_reference` 和 `surface_covers`，显式传给原 TerrainPreparation。原JSON未改，高程值不含地态类别。

覆盖只负责已有来源范围内的类型；DEM提供高度、贴地与真实法线。最终 Shader 的地图墨层改为明确的 `map_ink_tone/map_ink_weight`，可以合成政治或经济观察色，但它不是地态类型。`cover_kind` 仍仅来自经准入的覆盖。水面、林地和地表几何共用法线插值的合理实现保留。

删除 R25 通过吉萨 content_path 直接启用干旱色的分支及无其他消费者的 arid 参数/函数。它是表现选择，不是有空间范围的荒漠数据；本轮恢复中性地表。没有将“未知”改称“无森林”，没有生成森林、农田、湿地或冰川范围。

阿尔卑斯继续使用 R25 的方向残差和连续全球高度色阶；没有瑞士专用遮罩、模糊边框或新增贴片。跨来源垂直基准与采样尺度差异仍在，未声称拼接已得到实机确认。

R24 海洋/海冰、R22外部太阳、R20银河不改。原南极已分类陆地的冰雪基色转入物理色参数，不借政治墨层表达；沿用已有南极分类和冰雪色阶，不增加雪线或修改海冰。

## 5. 经济与军事接口

正式经济视图已提供聚合体/市场观察、total_hour、daily_totals、history、routes与shipments；当前地图只读 fulfillment_bp。原country summary存在 -1 未知哨兵，过去会被颜色计算 clamp成0。R26令缺键、负哨兵或不支持指标使用原中性色，真实0仍按零满足率显示。

正式 Presenter还可经已有权限查询有限 site_id、stock_place_id、activities、plan_day、库存和能力。这不足以直接绘制完整产出分布。后续经济线需要提供可解释的已完成产出数量、商品/单位、统计区间、有效空间引用和未知状态。没有把库存、计划、能力或地态颜色当成产出，没有修改经济领域文件。

MilitaryMapAdapter 已复用 Spatial.catalog 地点和交通，独立读取 strategic_military_overlay 的模型语义；军事控制/行动和 TerritoryState 不等同于主权或行政。军事实际通行、隐蔽、补给解释由军事线负责。正式地图仍无完整军事显示/命令入口，SimulationStep没有因本轮地图工作增加军事推进。个人玩家没有获得国家指挥权。

## 6. 冗余与保留

实际移除：补陆逐三角政治借色分组、UV计算、模板字典/原材质引用、WORLD/REGION切换时借色参数复制及相关重复纹理提交。面几何标记从误名 water 改为 surface，不再向陆地 Shader 提交 water_color。原6 texel通用面编码保留，避免另造格式和第二缓存。旧资产中的借色索引仍作已准入来源描述保留，运行时不再为它生成分组或绑定材质；本轮未批量重写地理资源。

同一地图模式再次设置时，不再发送 appearance_changed。真实切换仍更新显示。没有为五种用途复制地球、DEM、海岸Mesh或全局视口。原有限准备、失效任务丢弃、后继完整安装、旧LOD退休、LOCAL裁剪和GLB缓存不改。

没有实测性能。合批数量、阴影效果与整机负担不作比例承诺。近景country线加入裁水会增加有限后台裁切工作，使用原窗口缓存，不在每帧扫描原GIS。

## 7. 文件

修改正式源码10个：

- `scripts/content/local_spatial_content.gd`：独立覆盖输入。
- `scripts/content/local_spatial_loader.gd`：拆开高程与覆盖。
- `scripts/content/strategic_spatial_loader.gd`：传递预制几何角色，停止传入借色分组。
- `scripts/presentation/map/local_spatial_lod.gd`：物理类别合批、移除借色UV、显式覆盖准备。
- `scripts/presentation/map/local_spatial_layer.gd`：纯物理材质、排序和面/线语义，移除模板引用。
- `scripts/presentation/map/globe_renderer.gd`：取消政治模板上下文、共用边界裁水、独立覆盖输入。
- `scripts/presentation/map/region_view.gd`：独立覆盖输入及地图墨层参数，移除路径推定干旱色。
- `scripts/presentation/map/globe_controller.gd`：相同模式不重复刷新。
- `scripts/presentation/map/political_layer.gd`：未知经济指标不当作零。
- `shaders/presentation/map/local_terrain.gdshader`：覆盖、地形与最终墨层职责。

另修改：

- `shaders/presentation/map/terrain_palette.gdshaderinc`：删除无消费者的干旱色函数。
- `shaders/presentation/map/political_surface.gdshader`：原南极物理基色不借政治墨层。
- `export_presets.cfg`：内部预览默认输出指向唯一R26。
- `docs/MAP_DATA_AND_RENDERING.md`：标明早期Robinson设计不是当前运行架构。
- `docs/map/R25_GEOGRAPHIC_LAND_TERRAIN.md`：更正法国截图归因。

新增两份文档：`MAP_SEMANTIC_CONTRACT_R26.md` 与本文。没有删除正式文件，没有修改原始GIS、DEM/DSM、历史身份、行政成员、LandTopology、经济/军事/人物/人口/组织算法、GameClock或五槽存档。另一工作线本地文件未覆盖或还原，无Git操作。

## 8. 预览与未完成内容

唯一目标：`D:/programs/WWO/wwo/builds/preview_2026-10-16_unified_cartographic_semantics_r26/WWO_1900_Unified_Cartographic_Semantics_R26_Preview.exe`。

原 Windows Desktop Internal Landmark Preview、x86-64、嵌入PCK；古迹仍限原内部预览许可。R25保留回退，R24保留作已认可海洋表现对照，正式builds/windows保留。R19不重试删除。不生成多套候选版本。

Godot正常导出退出码0，savepack完成；唯一EXE长度339740552字节。导出日志没有ERROR，仍有原 `0.001a` 版本号格式警告。未改正式项目版本号。预览旁保留原可读地表/水文、许可和内部模型说明，附本报告及语义契约副本。正常完成的导出日志已清理，没有生成第二个EXE、独立PCK或安装包。

未启动游戏，未运行测试、回归、性能采样、FPS/内存测量、哈希核验、安全审计、CI或额外探针。没有本轮游戏截图，也未在图形驱动中确认全部Shader表现。正常导出不等于画质/运行验收。本轮未清理其他旧构建；R24用于保留海洋对照，R25用于回退，R19保持原状。

后续仍需：以实际法国异常画面定位差集几何与非线性边缘近似；在既有生命周期内完成独立物理底图与历史墨层的几何分离，而非地点补丁；取得明确历史地态、基准转换和完整河口资料；经济线提供产出观察契约；军事线负责战区显示、领域解释及个人权限。没有把这些未完成项写成已实现。
