# R16：缩放、有限河面交接与地标层级

施工基线：本机R15。保留R13—R15正式源码、历史地理资料、R15资产目录及经济工作线本地修改。没有启动游戏、采集截图或性能数据，没有Git提交或推送。

本文记录首次R16施工与导出。其后按用户追加指令继续完成同一轮R16性能收敛，详见 `R16_LOCAL_RENDER_CONVERGENCE.md`。最终版使用独立路径，首次R16保留为回退；追加阶段将资源退出迟滞改为35%，并进一步缩小呈现通知、MultiMesh和拾取更新范围。

## 缩放调用链与实际修改

原路径：`GlobeRenderer._gui_input → _ensure_view → _sync_local_resources / _sync_strategic_resources → LocalSpatialLayer.update`；`unit_at()`、滚轮后再次 `_ensure_view()` 和 `_evaluate_scale()` 还会进入视野准备。多个输入事件可以在一次画面提交前重复执行这些工作。转换动画期间的输入原来直接被拦截，连续滚轮会丢失部分输入。

现在：

1. 输入和坐标查询只调用 `_ensure_camera()`，立即更新相机和锚点，不请求GIS、安装LOD或准备地表。完整内容请求仍在既有 `_draw / _ensure_view` 路径，同一帧使用最终相机状态。
2. 同一帧、同一鼠标位置的连续滚轮复用地理锚点。已开始拖动时不再先做一次地表射线命中。有效点击仍使用原正式拾取，不改变空白海洋取消选择。
3. `_evaluate_scale()` 只处理尺度交接，使用平面地理锚点决定显示层，不再重复请求LOCAL，也不为尺度判断重复射线扫描地表。
4. WORLD/REGION淡入淡出期间仍接收滚轮，沿当前相机继续缩放，交接完成后判断最终尺度；未加入数秒等待。
5. LOCAL异步完成后只走一次既有同步安装入口，删除先 `local_layer.begin()` 再同步可能重复开始的调用。LocalSpatialLoader只在需求真正改变时取消旧加载，不为同一后继请求反复增加取消代数。

这些是源码中可以确认的重复工作。没有实测，不能将其认定为全部卡顿来源。

## LOCAL地表准备与资源所有权

原 `RegionView._update_surface_demand()` 在主线程同步执行水面栅格遮罩、法线/坡面、逐三角形裁水、贴地覆盖、河流线和拾取分块。进入高精度范围时，这些工作会与输入和画面提交争用主线程。

现将原算法移入现有 `LocalSpatialLod.TerrainPreparation`，作为有限CPU任务。它不是地图运行时、资源管理器或世界状态。只生成数组和字节，不创建Node、ImageTexture、Mesh、Material或访问RenderingServer。

- `RegionView`至多持有一个地表准备线程。需求由实际地表路径及投影框架决定，不包含相机平移、朝向或缩放，因此相同地表不随滚轮重新裁水。
- 数据片或框架改变、退出范围或隐藏地图时取消旧任务。任务在阶段、网格行和三角形处理中检查现有请求代数；过期结果丢弃。
- 有效结果由主线程一次安装纹理和Mesh。之后只更新当前相机变换、必要材质参数和可见实例。准备期间保留原REGION底图；完成事件触发后续提交，不依赖玩家再滚一次鼠标。
- 工作线程不保存旧相机的屏幕位置。结果按最终相机姿态安装；没有新投影、屏幕偏移或高度夸张。
- 共享普通建筑Mesh、MultiMesh及有限GLB缓存保留。相同可见组合不重复提交静态实例颜色；随实际视图变化的变换仍需更新。
- 现有SubViewport只在内容或相机变化时请求一次渲染，尺寸只在窗口变化时更新。没有第二个三维视口或持续动画。
- 退出LOCAL时继续释放当前地形、水面、拾取数组、材质及实例；取消任务完成后排空。R10旧LOD退休、R15中尺度纹理最多一片的机制保留。

仍需在主线程上传Mesh和纹理。行政LOD转换、当前几何投影及透明地表/水面的实际GPU成本尚未测量。后台准备降低的是输入线程中的同步工作，不保证风扇、总CPU或内存下降。

## 泰晤士河截断

确认的制作路径：`build_local_natural_transport.py` 先将下载的伦敦现代水面与 `london_surface_ea_dtm.json` 的实际覆盖相交；有限多边形又被裁成贴地三角形。伦敦63×63采样窗口为：

- 西 −0.13545°，东 −0.11375°；
- 南 51.48985°，北 51.51155°。

当前伦敦水面实际触及东侧和南侧数据边缘。它们不是泰晤士河的自然终点。R13三维覆盖已在DEM边缘淡出，但二维水面仍保留同一条不透明的裁切边，因此淡出后仍能看到突然结束的宽水面。

修正：

- LocalSpatialLoader在读取时识别与已知DEM窗口边缘重合的实际多边形边，给显示批次携带数据裁切范围与方向。原多边形、经纬度、来源和历史记录不修改。
- LocalSpatialLod保持这些边缘描述与对应水面关联，不把不同数据片的裁切信息混在一批。
- 水面Shader仅在确认为采集裁切边的方向使用地理坐标过渡，范围为窗口宽/高的12%。自然河岸不因多边形外框而统一淡出。
- 与既有LOCAL接管共用同一投影，未增加第二个水层。裁切边过渡时保留外围合法河流中心线，不加长水面、不指定任意河宽。
- Shader共用已有图表的逆投影辅助函数，避免为新边缘逻辑再计算一次平面到球面的反变换。

巴黎沿用同一通用判断：只有实际与采集窗口重合的边才处理，不把完整塞纳河岸当成裁切边。吉萨已有尼罗河现代水面与概化中心线继续按原范围显示。

没有取得新的河岸。窗口外缺少适用水面范围的河段继续使用现有中心线。Natural Earth概化中心线和现代水面精度不同，仍可能存在小尺度位置差异；本轮未移动中心线或伪造河宽。伦敦无实测水位的问题保持原说明。

## 地标层级

旧埃菲尔铁塔、钟楼和金字塔都允许在110米/像素显示GLB；原放大上限分别为32、100、22倍。REGION还会按接近模型阈值增大建筑剪影。这解释了中景出现大体量建筑轮廓的源码路径。

- WORLD不实例化三维地标，保持原远景地理标记规则。
- REGION采用同一小型测绘地标符号，图形约10×15像素，点击范围16×22像素。取消三个随尺度变大的建筑剪影绘制分支。原有名称设置保留。
- LOCAL根据模型实际高度与宽度确定准入尺度：`min(原上限, clamp(max(模型高度,底宽×0.35)/20,4,24))` 米/像素。
- 现有埃菲尔铁塔约15.03米/像素、钟楼4.815米/像素、金字塔组约15.87米/像素开始准入。已安装实例有20%退出迟滞，减少阈值往返。
- 模型视觉放大最多3倍，目标屏幕高度22—42像素；金字塔组沿原整体足迹方式控制。实际高度、尺寸、坐标和来源字段不改。
- 保留GLB后台读取和真实贴地路径。正在等待适用地表的模型不抢先覆盖符号。三维模型完成实际渲染帧后，原符号才退出；离开视野或尺度后释放实例。

没有新增模型、建筑数量、港口、道路、森林或云盘素材。三件独立地标和六种普通模块保留。微缩建筑仍是抽象表现，不是1900年逐栋布局。

## 地形与世界系统

WORLD全球relief、REGION relief、R15四片中尺度地势和原LOCAL DEM/DSM均保留。未改变原始高程、海岸、国家主权、行政身份、LandTopology或历史日期。未新增随机颗粒或改用地貌GLB。

4×时间推进仍由 `FormalWorldApplication._advance_world → SimulationStep.advance_minutes` 执行。既有到期边界继续处理工资、原生经济时间/日结算、运输、旅行和消费。它们也运行在主线程，但本轮未测量其耗时，不认定为已证实瓶颈，不修改或跳过结算。经济工作线、存档、开局和HUD均未改动。

## 本地开发产物治理

`AGENTS.md` 已补充后续导出规则：新预览成功导出后保留当前版、前一必要回退及有效正式发布；再删除已确认被替代、未被其他工作线使用的旧预览。唯一原件、明确基线、研究材料、UID、导入配置及受保护文件不按日期或扩展名删除。没有新增清理服务或扫描框架。

本轮新导出完成后，检查旧目录内容及运行程序路径，再清理以下纯预览副本：

| 删除目录 | 文件数 | 文件字节合计 |
|---|---:|---:|
| builds/preview_2026-10-14_cabinet_log_memory_r10 | 1 | 336,455,976 |
| builds/preview_2026-10-14_local_natural_transport_r11 | 8 | 337,547,517 |
| builds/preview_2026-10-14_local_settlement_r12 | 9 | 337,633,715 |
| builds/preview_2026-10-15_local_composition_r13 | 9 | 337,666,251 |
| builds/preview_2026-10-15_terrain_material_r14 | 10 | 337,744,396 |

合计37个文件、6个目录、1,687,047,855字节（约1.57 GiB）。其中JSON和许可说明是旧构建内的副本，正式data/docs和R15/R16许可附属资料仍保留。没有删除任何正式地图或研究原件。

保留：R16新预览、R15回退、`builds/windows/` 原有两项有效发布文件。新预览沿用嵌入PCK，没有另留临时PCK。R16普通导入/导出诊断写入系统临时目录，不在项目再积累一套日志树。没有改动 `0.001a` 版本号警告。

尝试清理以下旧导出日志及其空父目录时，自动审批返回 `blocked by policy`，没有更细原因。整条删除操作未执行，不改用其他工具绕过：

- local-artifacts/local-composition-r13/resource-import.log
- local-artifacts/local-composition-r13/windows-export.log
- local-artifacts/terrain-material-r14/resource-import.log
- local-artifacts/terrain-material-r14/windows-export.log

这四份日志和目录继续保留。此前被拒绝的四个pyc及 `ui_cabinet_phase1_2026-10-14` 目录不触碰。经济工作线日志、快照和制作目录不清理。

## 云端分工建议，未实际迁移

以下适合在以后单独授权后归档：

- `local-artifacts/physical-relief-r1/source/`：大型ETOPO原件及来源说明，当前转换器仍依赖本地路径。
- `local-artifacts/local-landscape-r4/`：IGN/EA/swisstopo/Copernicus原始地形及必要说明，属于再生成输入；不能仅靠运行衍生结果恢复。
- `local-artifacts/trf-gis-1900/` 及已有历史GIS制作资料：保留独立原件、许可和重建依据，需要逐项决定归档内容。
- `local-artifacts/landmark-prototypes-r1/`、`settlement-miniatures-r12/` 中的唯一制作原件：需连同生成脚本及其路径依赖保留。

未创建云端归档目录、上传研究资料、移动Git或Godot缓存。120件Drive古迹继续作为外部储备，使用R15目录，不重复读取或导入。游戏必需资源仍随离线预览提供，不依赖Drive、Codex授权或网络。

## 正式文件及交付

修改：

- AGENTS.md
- scripts/presentation/map/globe_renderer.gd
- scripts/presentation/map/region_view.gd
- scripts/presentation/map/local_spatial_lod.gd
- scripts/presentation/map/local_spatial_layer.gd
- scripts/content/local_spatial_loader.gd
- shaders/presentation/map/globe_water_surface.gdshader
- shaders/presentation/map/local_chart.gdshaderinc

新增：本文。删除的正式源码/资源文件：无。地表CPU函数从RegionView移入现有LocalSpatialLod，没有保留主线程旧生成路径。三个旧建筑剪影分支直接移除。

预览：`D:/programs/WWO/wwo/builds/preview_2026-10-15_zoom_hydro_landmarks_r16/WWO_1900_Zoom_Hydro_Landmarks_R16_Preview.exe`。Windows Desktop x86-64，使用现有预设。许可和现代参考资料附属文件保留。普通导入和最终导出已完成，导出返回0；未运行游戏。

## 未确认与剩余风险

- 未运行，不能声称缩放实机、河流端部和模型交接已通过玩家确认，也不能声称风扇、帧率或内存改善幅度。
- 首次GPU上传、Shader首次编译、复杂行政/海岸显示、有效几何拾取仍可能造成瞬态负担，尚无实测归因。
- 后台裁水仍有真实计算成本；这里只把它从输入线程移出并避免重复准备，没有取消必要地形。
- 仍缺连续百米级地势、历史土地覆盖、完整精细河岸、水位及吉萨基座裸地；不以颜色、随机内容或模型填补。
- 仍有四份受策略阻止删除的旧日志。其余用途不明目录保留。
