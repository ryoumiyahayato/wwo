# R18 Coastline / Terrain / Simulation Render Convergence

基线：本机R17正式源码。施工日期：2026-10-15。

本说明区分源码确认的问题和仍需实机确认的结果。未启动游戏，未采样、截图、运行测试或计算哈希，未操作Git。正常资源导入和Windows导出不属于游戏试跑。没有修改经济工作线的领域实现。

## 1. 海岸、政治填充和行政线的实际来源

- 物理海岸来自现有Natural Earth v5.1.2固定来源中的land 5.1.1。原件为`local-artifacts/paris-land-pilot-r1/research/ne_10m_land_v512.geojson`。这里的10m表示1:10,000,000比例尺，不是10米分辨率。现代物理参考，公有领域。
- 现有`build_geographic_foundation.py`从全局统一简化后的物理陆地外缘生成岸线；coarse和medium分别采用约1500米和300米保守简化容差，再分片。分片裁切边不作为海岸描边。现有Syvash湖孔继续保留。
- 政治底网仍来自现有1900历史国家几何及现有有界政治修订。`PoliticalLayer`负责归属、政治颜色和旗帜引用，`GlobeSurfaceBatch`负责GPU显示。WORLD和REGION共享既有不可变Mesh，各自持有必要材质和CanvasItem。
- 物理显示采用已有差量面：`land_reference`补充物理陆地减历史显示陆地的部分；`ocean_reference`扣除历史显示陆地中已知属于物理水域的部分。没有把现代岸线写入主权或LandTopology。既有差量衍生资源和许可记录未改。
- 行政线来自现有历史GIS的display_lines/display_outline_lines或原多边形外环；国家间政治边界仍走原macro路径。行政显示线与独立的拾取组件不混为一份事实。
- 巴黎局部资料另有Sandre/OFB/IGN现代水文岸线。该岸线与Natural Earth陆地并非同一测绘来源，不能替代其外缘后仍声称线面一致。

## 2. 确认的显示错误及修正

### 2.1 多来源海岸的替换不一致

旧路径同时保留历史国家外缘、战略物理海岸和巴黎局部水文岸线。巴黎局部岸线通过一个圆形区域权重压低Natural Earth描边，但填充仍是Natural Earth差量面。圆形范围也不能证明局部岸线资料完整覆盖。

R18删除这条圆形海岸替换分支及`paris_mask_weight`。局部coast事实和来源仍保留，但不再作为物理陆地的另一条外缘提交。当前完成的物理LOD同时负责填充和海岸描边。真正可见的物理岸线就绪后，历史国家外缘退出“物理海岸”显示；国家间macro边界继续显示。没有隐藏全部海岸。

战略物理fill/coast不再分别淡入不同权重。岸线替换判定在当帧批次可见状态更新后执行，不再只看active_lod或上一帧状态。原有新LOD完成后退休旧LOD的机制保留。

### 2.2 三角形扩张与细长缺口

政治面原先把每个三角形向外扩张0.45像素，海洋修补面另扩张0.55像素，补充陆地则用精确边。这三种轮廓不是同一组位置。细长修补三角形还会把扩张带进真实陆地。

R18移除政治面和水域面Shader中的逐三角形扩张及对应材质参数。陆地、补充面和水域修补面均使用原共享边。不是加粗描边或加背景色遮盖异常。

`GlobeProjection.display_line()`让物理岸线和历史源环采用与面网一致的2度球面边长/8度经差二分规则。原点保留，不简化、不平滑、不移动源坐标。128段岸线打包保留before/after邻点，避免把每个打包边界画成独立端帽。

`GlobeSurfaceBatch.encode()`排除编码为单位球float32后已经重合、共线或非有限的三角形。只排除无法形成显示面积的面，不设任意面积阈值，不修改原GIS。

物理批次可见后，粗高程背景不再以高度插值另画一层海陆轮廓。高程明暗仍在合法陆地面上显示。WORLD和REGION沿用同一规则。

### 2.3 行政线与物理水域

现有行政后台准备线程读取当前战略分片已有的ocean_reference多边形。只对与当前有界显示窗口相交的部分，在中心化地理坐标中执行线段差集；孔保留。资料、窗口或物理LOD改变时才重做，普通悬停和时钟不执行此裁切。

被裁的是显示墨线。原行政多边形、行政身份、成员、面积计算和拾取组件不变。国家间政治线不自动改成现代海岸。

限制：现有ocean_reference是有限的物理差量，不是另一份全球海洋权威。没有对应物理水域资料的部分不能据此裁去。真实1900与现代岸线的年代差异、河道工程和测绘误差仍可能可见，不能把所有不重合都宣布修复。

## 3. LOCAL黑色矩形的实际合成路径

R17：透明LOCAL SubViewport → SubViewportContainer普通透明混合 → REGION二维缓存。地形边缘的ALPHA小于1，项目默认清除色RGB为深色。Compatibility三维透明层写入目标时，RGB已经按覆盖Alpha累积；普通二维混合再次乘Alpha，会压暗边缘。透明像素若残留深色RGB，也会作为整块裁剪目标的底色进入合成。线性过滤还可能在透明边缘采到该颜色。

R18直接修正这一合成规则：

1. LOCAL环境改为显式黑色透明清除，RGB和Alpha均为0。
2. 以TextureRect显示现有ViewportTexture，使用CanvasItemMaterial的PREMULT_ALPHA及UNSHADED。
3. 保留原像素密度、整数裁剪原点和128像素尺寸档位，采用一对一最近采样。裁剪改变时明确更新同一个SubViewport的尺寸。
4. 保留原真实地理裁剪、正交相机偏移、完整地图像素和拾取原点换算。没有增加模糊、屏幕蒙版或另一层地形覆盖。

这是可由代码确认的混合错误。没有运行截图定位，不能断言截图中每个黑像素都只有这一成因，也不能宣称黑框已获玩家验收。

引擎依据：[Godot 4.6 GLES3三维透明混合及清除](https://raw.githubusercontent.com/godotengine/godot/4.6/drivers/gles3/rasterizer_scene_gles3.cpp)、[CanvasItemMaterial混合模式](https://docs.godotengine.org/en/4.6/classes/class_canvasitemmaterial.html)。

## 4. 各级地形与明暗交接

| 层级 | 保留的来源与精度 | R18显示规则 |
|---|---|---|
| WORLD | ETOPO 2022 v1 60s既有1024×512衍生，赤道约39.1千米 | 保留大尺度地势；海陆位置由合法物理面决定 |
| REGION | 同源4096×2048衍生，赤道约9.8千米 | 保留连续低频基底和原地理锚定 |
| 四处中尺度 | 原四个97×97原生60s窗口，东西约1.15—1.61千米、南北约1.85千米，EGM2008 | 保留R17固定幅度差量，不独立拉伸色阶；增加按原生间距计算的近景退出带 |
| 巴黎 | IGN现代RGE ALTI，63×63，约33×50米，2.04×3.10千米，IGN69 | 原约21.26米/像素进入、28.70退出；原真实坡面、法线和边缘几何保留 |
| 伦敦 | EA 2022 DTM，调查2000—2022，63×63，约24×39米，1.50×2.41千米，OS Newlyn | 原约15.65进入、21.12退出；不是1900精确城市地表 |
| 采尔马特 | swissALTI3D 2019，33×63，约19×28米，0.618×1.724千米，LN02 | 原约6.44进入、8.69退出和窄幅大高差俯角保留 |
| 吉萨西侧 | Copernicus DSM，2021发布、TanDEM-X 2011—2015等来源，57×57，约29×33米，EGM2008 | 原约16.86进入、22.76退出；不当成裸地DEM，金字塔基座不外推 |

中尺度差量先前在550米/像素以下一直保持完整权重，直到极近景。公里级短波段因此会被放大到城市地表尺度。现在以南北原生间距的0.05—0.20倍米/像素为近景权重带：约93米/像素以下不贡献，约371以上保留原中尺度权重；更远仍沿原1600/2200准入退出规则。原生分辨率没有提高。纹理在约60米/像素以下按现有迟滞机制退休，材质引用同步清除。

LOCAL删除R14的颗粒纹理采样及对应逐尺度uniform。保留基础高程配色、原真实法线双方向明暗和有限坡度印刷色。没有增加纹理、噪声、森林或岩石分类；坡度色仍只是制图约定。

R17已经删除的边缘高度压平、假坡和第二层谷地暗化没有恢复。没有逐片最低/最高海拔归一化。也没有声称不同垂直基准已完成测量级转换。既有覆盖边缘材质权重保留，但没有再增加模糊范围。

## 5. 河流、河口与海岸

R17的保守中心线规则保留。巴黎、伦敦、吉萨的有限现代开放河面仍保存在资料中，不恢复断头宽河面、裁水孔或任意河宽。地方河流不替代物理外海岸。海岸源统一后，不再因巴黎圆形替换生成两份不同来源的外缘。

仍缺：泰晤士河近景连续河岸与水位、塞纳河更完整的适用河岸、1900工程岸线、不同水文来源的可靠对象对应。Natural Earth概化中心线与Sandre现代精细中心线的局部精度差异仍可能存在；本轮没有按名称、固定圆形或猜测距离强行拼接，也不能保证每个河口的重复线都已消除。

## 6. 4×时间推进的实际调用关系

`0.25秒Timer → TimeControl.tick → advance_requested(15×speed分钟) → FormalWorldApplication._advance_world → SimulationStep.advance_minutes → GameClock及各正式领域 → _on_world_changed → 可见页面/真实地图修订`。

暂停不发推进请求。1×每次推进15分钟，4×每次推进60分钟；两者都由同一Timer驱动。4×不是每个渲染帧执行四次世界加载，但单位现实时间内跨过更多合法结算边界。

SimulationStep按日期、消费、生活安排、运输和旅行边界依序推进。工资、原生经营时间与日结、共享运输窗口、到达通知、消费、宏观区间、生活安排、迁居、经营范围和组织日审全部保留。GameClock、SimulationStep和经济领域文件未改。

地图日期改变不等于历史显示资料改变。只有`HistoricalLoader.display_changes_between`确认有效修订时才执行`_refresh_map`。原政治模式中的普通时钟推进没有被证实会重建DEM、GLB或行政GIS。本轮不重复宣称修复一个并不存在的每小时全地图重建。

### R18确认并删除的展示工作

- 跨日且有地图地点选中时，旧`_on_world_changed`无条件`MainShell.refresh()`。现在普通跨日只更新WorldPage观察日期；真实历史修订仍完整解析资料。
- 旧`_refresh_ui`只要有国家选中，或打开world/administration，就请求更新全世界经济展示快照。现在静态地图资料页复用已有身份到市场映射；人物、经济页面和实际经济地图仍按原revision读取最新总量。
- 同一动作中的选择、页面和资料完成信号原来同步进入Presenter多次。现有refresh入口现在合并为一次延后调用，读取最终当前页面；领域时间步骤没有合并或跳过。
- 国旗加载判定从“日期不同”改为“玩家国家/旗帜引用不同”。真实历史资料修订清除此键，不遗漏合法旗帜更换。
- 经济地图仍更新观察数据；只有实际显示色改变才失效地图缓存。余额等不影响地图颜色的变化不重画政治面、地形或LOCAL图像。
- 行政显示/拾取数据完成信号不再被当作相机投影失效。只更新其有界需求和二维缓存，不传播到LOCAL地形、战略需求或Camera3D。

人物页和经济页打开时，仍会读取其实际最新状态。它们的正式查询和日结本身可能有同步开销，属于对应工作线，未擅自改写。

## 7. 视口更新与资源持有

Godot原生SubViewportContainer在进入场景或可见性通知中，会将可见子视口改成UPDATE_ALWAYS。这与项目手动设置UPDATE_ONCE的意图冲突；不是一个模型的三角面预算问题。

R18将WORLD地图缓存、REGION缓存和裁剪LOCAL目标的显示宿主统一为TextureRect。仍读取同一ViewportTexture，没有新增视口。项目显式控制size、UPDATE_ONCE和UPDATE_DISABLED，不再被容器可见性通知改回持续渲染。具体依据：[Godot 4.6 SubViewportContainer实现](https://raw.githubusercontent.com/godotengine/godot/4.6/scene/gui/subviewport_container.cpp)。底部黄铜半球仪的绘制和交互未修改。

普通钟表数字、日志和悬停不申请新的三维图像。相机移动、真实材质变化、内容安装仍请求一次正确图像。原frame_post_draw完成代数、模型通知去重、MultiMesh公共变换、地形候选块拾取、缩放迟滞及异步请求退休继续使用。

必须继续保留：WORLD规范显示/拾取几何、当前REGION政治和行政批次、当前物理海岸/水系LOD、连续全球地势纹理、当前有用中尺度窗口、有效LOCAL地形/高度纹理、共享建筑Mesh/MultiMesh、当前地标及最多两件PackedScene、必要后继任务。离开范围仍释放不再需要的资源。没有新全球缓存、常驻监控器或额外地形目标。

## 8. 保留及不确定性

原始历史GIS、Natural Earth物理资料、全部DEM/DSM和衍生bin没有修改。政治主权、控制、历史行政成员、LandTopology、人物/经济/军事/组织、GameClock、存档不变。模型、建筑数量、Drive资产目录及未入库120件古迹不变。

HUD、旗帜、人物饰盒、机械时钟、星轨、日志抽屉、即时通知、对象资料卡、主菜单和五槽存档不重做。只补充WorldPage的日期赋值入口。海洋取消选择、拖动、缩放、旋转和页面返回沿原逻辑。

不能从源码确定的主要成本：驱动Shader首次准备、GPU目标和透明图层耗时、主线程Mesh上传、复杂行政后台准备、正式日结及可见经营页面查询、整机内存压力和换页。没有运行数据，不能排序为唯一瓶颈，不能声称风扇或卡顿消失，也没有CPU/GPU/内存下降百分比。

待补资料：更连续的原生精细高程、垂直基准转换、适用年代的连续河岸和水位、历史土地覆盖。现代NE本身概化的海湾和小岛精度上限仍存在。

## 9. 文件

修改：

- `scenes/presentation/map/globe_renderer.tscn`
- `scripts/formal/formal_world_application.gd`
- `scripts/presentation/ui/world_view.gd`
- `scripts/presentation/map/political_layer.gd`
- `scripts/presentation/map/globe_renderer.gd`
- `scripts/presentation/map/globe_projection.gd`
- `scripts/presentation/map/globe_surface_batch.gd`
- `scripts/presentation/map/region_view.gd`
- `scripts/presentation/map/local_spatial_lod.gd`
- `scripts/presentation/map/local_spatial_layer.gd`
- `scripts/presentation/map/map_relief.gd`
- `scripts/content/local_spatial_loader.gd`
- `scripts/content/strategic_spatial_loader.gd`
- `shaders/presentation/map/political_surface.gdshader`
- `shaders/presentation/map/globe_boundary.gdshader`
- `shaders/presentation/map/globe_water_surface.gdshader`
- `shaders/presentation/map/local_terrain.gdshader`

新增本文。未删除正式文件。实际移除的是旧海岸圆形替换、逐三角扩张、LOCAL颗粒采样和重复的展示失效分支。原研究资料、模型、许可、经济工作线和受保护缓存未清理。

## 10. 交付

独立预览目标：`D:/programs/WWO/wwo/builds/preview_2026-10-15_coast_terrain_simulation_r18/WWO_1900_Coast_Terrain_Simulation_R18_Preview.exe`。

正常导出后保留R18、R17回退和`builds/windows/`正式内容。导出结果在本节末尾补记。未运行预览，不自动推送GitHub。画面及操作结果等待玩家反馈。

实际资源导入返回0，Windows Desktop x86-64内嵌PCK导出返回0。EXE大小337,472,040字节。正常导出日志未报告SCRIPT ERROR或ERROR，仍有原`0.001a`版本号格式警告，未修改。没有将导出成功表述为运行验证。

预览附带原有水文/地形许可JSON和R12/R14/R15来源说明，以及本轮施工说明。R14说明中的颗粒素材不再由LOCAL地表采样，未因此删除历史制作来源。

成功导出后，清理了已被R17/R18替代且没有运行进程的`builds/preview_2026-10-15_local_render_convergence_r16/`：13个文件，337,890,714字节。保留R17与R18，以及`builds/windows/`。没有清理原始研究资料、正式文件、经济工作线或此前拒绝删除的路径。
