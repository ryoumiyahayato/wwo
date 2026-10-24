# R16追加：LOCAL渲染性能收敛

直接接续首次R16。保留其缩放输入、后台地表准备、泰晤士河数据边缘交接和小型地标符号。不创建R17，不增加资源库或世界系统。

没有启动游戏、截图、性能采样、基准、测试或Git推送。以下区分源码事实与未测量的风险，不分配CPU、内存或帧率百分比。

## 为什么一件轻量 GLB 仍可能导致 WWO 严重卡顿

### 1. 单个模型不等于单个渲染负担

`GlobeRenderer._sync_landmark_display → RegionView.update_landmarks` 同时处理独立地标、LOCAL地表、河流覆盖和普通建筑需求。`_enable_landmark_3d()` 既可能由模型实例调用，也可能由地表安装调用。地表甚至可以在GLB准入之前启用三维。

启用内容包括正交Camera3D、已有World3D的环境、无阴影方向光、局部地形、水面、当前有效建筑，以及二维背景和前景注记的合成。R15的110米/像素模型阈值与细地表进入尺度接近，显示模型与激活这些工作可能同时发生；这不证明GLB是唯一原因。R16已将三件地标限制到更近尺度。

### 2. 使用接近完整地图窗口的共享目标

`RegionView.initialize / resize` 建立一个现有REGION SubViewport，尺寸跟随地图Control。LOCAL直接在此视口启用3D，没有新建小模型专用视口。相机变化后，需要更新二维地图、深度/三维内容和前景注记的合成图像；工作范围不是模型文件的几何大小。

没有发现滚轮改变视口尺寸的实现。`resize`已有尺寸相同即返回的条件。本追加未降低地图/HUD分辨率、增加视口或反复重建渲染目标。驱动实际分配和每次呈现耗时未测量。

### 3. 首次进入与已有内容的更新不同

首次GLB：`load_threaded_request → 状态LOADED → load_threaded_get → PackedScene.instantiate → 节点/材质安装 → 首次呈现`。实例化和加入场景仍在主线程。首次驱动Shader编译或目标附件准备可能阻塞，但未测量，不能归为已证实主热点。

已经加载：使用当前实例或最多两件PackedScene的现有有限缓存。地表按路径和固定投影框架复用，缩放不重新解析JSON或裁水。主线程更新相机/模型变换，后台只处理实际新需求。`wait_to_finish`和资源获取在正常轮询中先检查完成状态，不是每帧等待未完成线程。

### 4. 呈现通知存在多余反馈，但没有证据表明无限循环

原 `RegionView._landmark_frame_ready()` 每个三维呈现帧都会发出 `landmark_display_changed`。`GlobeRenderer._on_local_frame_ready()` 无变化时仍要求父控件重画；首次有效地表覆盖还调用 `_invalidate_appearance()`。

原 `_landmark_view_key` 已能阻止同一姿态反复申请三维帧，因此不能把它描述为已证实的无限循环。本追加让完成通知仅在已呈现地标集合、建筑集合或地表身份改变时发出。相机姿态真的改变，仍正常更新图像。

### 5. 首次地表就绪不再扩大为整图外观失效

原首次覆盖通知可进入 `_draw → _sync_strategic_resources / _draw_surfaces / _draw_boundaries / _draw_administrative_boundaries`，枚举本来没变的国家、行政及资源需求。它不一定重建Mesh，但确实扩大CPU处理范围。

现在通过既有 `LocalSpatialLayer.set_local_coverage()` 直接更新当前/过渡批次的水面遮罩和地表位移参数，连同既有边界、行政注记参数更新。只请求必要的共享视口图像，不触发政治外观或GIS请求。首次覆盖仍可能需要一次后续合成帧；这是必要的遮罩接管，不是持续重绘。

### 6. 当前地形与河面没有按每次滚轮重建

首次R16已经把遮罩、法线、裁水、贴地水面及拾取数组移入 `LocalSpatialLod.TerrainPreparation`。`RegionView._update_surface_demand()` 以来源路径和固定投影框架作为需求；同一地表和框架直接复用。

本追加保留取消代数、单个有限地表准备任务及主线程GPU安装。没有重新制作DEM、修改高程或建立新地形缓存。完全淡出的地表、水面和中心线节点停止绘制；该过渡范围内的资源短暂保留以避免来回重建。不可见地表不再参与高度拾取和二维位移接管。

### 7. MultiMesh原来仍逐实例提交相机变换

原 `_update_settlement_batches()` 把每栋建筑换算成带相机平移、朝向和尺度的屏幕空间三维变换。即使只是平移，也会对每个可见实例调用 `set_instance_transform`；首次R16只缓存了颜色。

现在实例变换使用现有地表投影的局部米制坐标，公共的屏幕变换放在各模块的MultiMeshInstance3D父变换。平移/朝向改变时更新公共变换。当前实例保存上一份已提交变换，只在实例、LOD视觉比例或实际变换改变时提交；缓冲区数量改变后完整恢复必要数据。不改回逐栋Node3D。

视口裁切、地标避让和LOD比例仍需要计算。没有声称消除了所有建筑CPU工作。暂时退出当前LOD的最多六个模块节点只在当前LOCAL过渡带保留；离开实际需求后仍释放，避免在淡出临界点不断重建MultiMesh。

### 8. 拾取候选块原来不够贴近地理范围

原地表/水面按每192个索引或顶点分块。它们沿网格行排列，包围盒可能横跨较宽区域；鼠标经过时可能命中宽包围盒，测试较多无关三角形。

现在在已有后台准备中按8×8原生DEM单元重排现有三角索引，并据此建立原有AABB块。水面射线数据同样按实际源网格分组。渲染顶点、高程、三角形、河岸和最近命中规则保持；没有增加第二套全球拾取。分组临时数组在准备结束后释放，不在鼠标移动时重建。

### 9. 原资源退出迟滞小于一次滚轮步长

`GlobeController.ZOOM_FACTOR=1.22`。首次R16的模型退出余量20%、地表15%，不足以覆盖一次反向滚轮，可能出现“进入→退出→再进入”的重建。

模型和地表已安装资源的退出余量统一改为35%，进入尺度不变。大范围离开、换来源或退出LOCAL仍正常取消/释放。LOCAL整体200/280米/像素的原40%交接、有限PackedScene缓存和过期请求丢弃继续保留。没有无限扩大缓存。

### 10. 约1GB的归属目前不能从截图确定

源代码中有以下长期或当前有效持有者，不能将任务管理器进程内存全部归给一个GLB：

| 所有者 | 实际持有类别 | 本轮处理 |
|---|---|---|
| GlobeRenderer / PoliticalLayer | WORLD规范几何、CPU拾取源、政治及地理元数据、GPU面/边界数据 | 保留正式远景和拾取所需内容 |
| RegionView.surfaces / boundaries | 共享WORLD几何引用、自己的材质与画布命令 | Mesh共享，没有把引用当成又复制一套Mesh |
| StrategicSpatialLoader / AdministrativeLoader及显示层 | 当前海岸、水系、行政LOD、安装与过渡数据 | 保留既有有界请求和旧LOD退休 |
| 当前LOCAL | DEM、裁水Mesh、水面、两种遮罩/高度纹理、射线数据、普通建筑 | 静态复用，离场释放；只保留必要过渡 |
| 地标缓存 | 当前实例和至多两件最近PackedScene | 上限不增，过期加载结果不入库 |
| SubViewport / 引擎 | 当前二维图像、启用3D时的渲染附件、驱动/Shader缓存 | 保留当前地图；内部实际保留量未知 |
| 字体与世界对象 | 字体/字形及经济、空间、人口、组织等有效世界状态 | 不在地图工作线删除 |

任务管理器的进程内存不是GLB文件大小，也不能直接视作显存。没有按所有者测量，不能说上述某一项占主要比例。整机内存压力与换页也仅是可能因素。

### 11. 已确认的源码问题

确认了：无变化呈现通知、首次覆盖扩大整图失效、关闭地名仍组装地点字典、相机参数重复赋值、平移时逐实例提交变换、条带式拾取候选过宽、迟滞小于滚轮步长、全透明过渡Mesh仍被提交。

这些都已直接修改。它们的存在不等于已证明是玩家严重卡顿的唯一或主要原因。

### 12. 仍未确定的可能因素

未确定主线程瞬态峰值、驱动首次Shader编译、全窗口GPU合成的实际耗时、整机内存压力、引擎资源池保留量，以及领域结算与地图操作同时发生的开销。没有游戏运行或采样，不给出改善百分比。

`UPDATE_ALWAYS` 搜索结果中，`GlobeRenderer._warm_relief_shaders()` 仅在首次世界准备、受 `_relief_shader_warmed` 控制时临时使用，强制完成一次准备后改回禁用。没有发现它在LOCAL常态永久开启，不将其误报为持续三维刷新原因。

### 13. 实际修改的入口

- `RegionView._landmark_frame_ready`：仅有效呈现状态变化发通知。
- `GlobeRenderer._on_local_frame_ready / _sync_local_coverage` 与 `LocalSpatialLayer.set_local_coverage`：局部图表参数更新，代替整图外观失效。
- `GlobeRenderer._draw`：关闭地名或LOCAL不使用国家地名布局时，跳过无用地点字典合并。
- `RegionView._update_local_camera`：按视口尺寸/俯角缓存Camera3D参数，不因模型缩放变换重复赋值。
- `RegionView._update_settlement_batches`：公共父变换、按需实例提交及有限LOD保留。
- `LocalSpatialLod.TerrainPreparation._make_surface_mesh / _make_surface_cover`：原网格空间分组，不改变实际三角几何。
- `RegionView.update_landmarks / _update_surface_demand`：35%退出迟滞。
- `RegionView._update_surface_pose / coverage_description / chart_screen_point / surface_unit_at / surface_screen_point`：完全透明过渡的绘制、位移及拾取退出保持一致。

### 14. 必须继续保留的资源

当前视口图像、实际显示的三维资源、正式WORLD拾取源、当前REGION/行政LOD、当前LOCAL地形和必要水面射线数据、共享建筑Mesh以及有限GLB缓存仍有用途。清空它们会破坏显示、拾取或造成反复读取。

本追加仅给当前几十个建筑实例记录已提交变换，并保存一个Camera3D状态键。没有新增纹理、大型Mesh、全国缓存或第二个视口。隐藏过渡资源仅限当前LOCAL与既有迟滞范围，离场仍释放。

### 15. 最终判断

一件GLB可能是整套LOCAL渲染路径启用时最显眼的对象，但同时参与的工作包含全窗口合成、局部地表/水面、地图注记、拾取及实例更新。实际成本取决于这些工作和失效频率，不能用GLB的几百个三角面替代整条链的性能判断。

本轮确认并减少的是附带重复工作。没有足够数据判断当前严重卡顿到底以CPU、GPU、内存压力还是领域结算为主。

## 不同触发的现有行为

| 触发 | 内容准备/安装 | 图像更新 |
|---|---|---|
| 首次LOCAL | 当前有界地表任务，必要GLB后台读取，主线程安装 | 实际安装/呈现后更新；覆盖接管可再合成一次 |
| LOCAL平移 | 复用地表/模型，公共变换、可见范围及必要拾取更新 | 当前相机的新图像 |
| LOCAL缩放 | 同源地表复用，LOD或地理需求变化才准备；迟滞保留 | 当前相机、真实视觉比例的新图像 |
| 鼠标悬停 | 精确拾取及必要文字/高亮，不准备地表 | 无地图材质变化时不请求三维图像 |
| 普通时钟/HUD/日志文本 | 不准备地表或模型 | 不请求三维图像 |
| 选中对象 | 原选择状态、符号/政治外观按真实变化更新 | 地图外观真变时需更新共享图像 |
| GLB加载完成 | 仅当前仍需要的实例；过期结果丢弃 | 安装后呈现并完成符号交接 |
| 离开再进入 | 迟滞内复用；真正离场释放，有限PackedScene复用 | 恢复当前相机与有效资源，不使用旧姿态 |

## 四类负担与领域边界

**A：CPU主线程。** 已修正通知导致的无用枚举、地点合并、Camera3D重复参数、MultiMesh重复提交及过宽射线候选。首次R16已经移走同步地表裁水。仍有必要的视野裁切、少量投影、精确求交和GPU安装。

**B：GPU。** 减少无用完成通知后的父控件重画与整图更新请求；完全淡出的过渡Mesh停止绘制。共享目标仍需在实际相机、内容或地图外观变化时重绘，无法据源码量化耗时。

**C：驻留。** 没有发现一个地标会自动加载120件模型。已有几何共享、旧LOD退休、LOCAL释放和缓存上限保留。迟滞是有界复用，非永久保留所有地区；全透明的保留资源不提交绘制。引擎内部缓冲是否立即归还未知。

**D：正式模拟。** `FormalWorldApplication._advance_world → SimulationStep.advance_minutes` 仍执行到期工资、消费、经济、运输、旅行和组织处理。`_on_world_changed` 检查历史显示是否实际变化；政治地图还已有 `_refresh_economic_map` 的模式保护，不因普通经济观察就无差别刷新政治地图。没有改动这些算法或伪称它们是已证实瓶颈。

## 文件与交付

追加修改四项：

- scripts/presentation/map/region_view.gd
- scripts/presentation/map/globe_renderer.gd
- scripts/presentation/map/local_spatial_layer.gd
- scripts/presentation/map/local_spatial_lod.gd

新增本文，并给 `R16_ZOOM_HYDRO_LANDMARKS.md` 增加追加阶段链接。没有删除正式文件，没有新诊断脚本。此前泰晤士河裁切边过渡、原水系数据、地标符号、三件GLB、六种建筑模块、R15中尺度地势、HUD与世界事实保留。

最终独立预览已导出：`D:/programs/WWO/wwo/builds/preview_2026-10-15_local_render_convergence_r16/WWO_1900_Local_Render_Convergence_R16_Preview.exe`，337,402,120字节。使用现有Windows Desktop x86-64预设，普通导入及导出完成，最终导出返回0。原 `0.001a` Windows版本号警告保持，没有修改版本配置。没有启动游戏。

首次R16 `preview_2026-10-15_zoom_hydro_landmarks_r16` 作为回退，不覆盖。新版本成功导出后按既有保留规则清理更早R15预览副本：11个文件、1个目录、337,815,886字节。删除前确认绝对路径位于本项目builds内且没有运行该预览；正式源码及R15资产目录不删除。`builds/windows/` 不动。当前保留两个R16预览及正式windows构建。

R13/R14四份旧导出日志此前已被自动审批以 `blocked by policy` 拒绝删除，本追加不再尝试。受保护pyc和目录继续保留。经济工作线未完成内容、原始GIS/地形、Blender、存档和Git历史不触碰。
