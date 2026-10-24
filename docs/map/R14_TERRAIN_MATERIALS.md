# R14 地形材质与地图刷新

基线为本机 R13。没有新增地理来源、模型、城镇或正式世界事实。没有启动游戏、安排运行测试、截图、性能采样或 Git 操作。资源导入与 Windows 导出不代表实际画面或性能已确认。

## 刷新依赖

- R13 `_draw()` 在普通悬停和 HUD 重画时仍重复收集 LOCAL 地标、建筑需求、地表覆盖及地理标记。R14 在实际地图失效或 GLB 准备完成时才调用该准备路径，其余时候复用既有位置与实例。标签仍可根据弹层范围重新排布，不提交地图 GPU 几何。
- MainShell 的页面、弹层等操作仍使用原信号。GlobeRenderer 只在地图模式、玩家国家、选择、名称或铁路偏好改变时失效缓存地图；纯 HUD 变化只重画轻量界面，不改变 HUD 自身行为。
- 后台等待期间不再每帧调用 `_sync_relief()`、`_sync_strategic_resources()` 和 `_sync_local_resources()`。加载需求由相机、真实内容、图层或已有有效修订触发。既有后台工作仍按原预算推进并收尾。
- 尚未完成整批的 LOD 上传不再每步触发完整投影刷新。完整显示结果继续沿原 `display_changed` 安装与退休路径交接。
- 修复 relief 纹理加载完成后只重画文字而未必更新缓存视口的路径。现在明确失效地图图像，再呈现已安装纹理。
- REGION 物理陆地不再先写入国家旗帜/政治参数、随即又将其覆盖为零。政治表面在旗帜权重为零时跳过纹理采样；完成粗细 LOD 交接后只读取实际使用的一层 relief。水面 shader 清除未使用的国旗 UV 运算和政治材质字段。
- LOCAL 淡入强度、材质细节权重只在值改变时提交。离开需求后才完成的地标加载结果不再挤入近期缓存；已使用的最近两件 PackedScene 仍可复用。

## 自然底材与政治着色

`terrain_palette.gdshaderinc` 是几个现有地图 shader 共用的纯显示函数，不持有资源或世界状态。

- 低地、较高地势和高海拔使用渐变的橄榄灰、土褐和中性浅石色。这是测绘印刷色阶，不断言岩性、土地利用、植被或雪线。
- 既有全球 relief 的 R 通道为双光向派生明暗加高度亮度项，G 为对数正高程。先分离这两个量，再将形态明暗叠到现有政治着色上；不把国旗颜色写入自然底材。
- WORLD 保留低细节资料。REGION 按原 LOD 使用较细 relief；近景保留宽尺度地势参考，不通过放大取样冒充精细地形。
- 共享函数同时用于正式政治表面、物理陆地填充与地图背景。没有改变主权、旗帜来源、行政几何或海陆判断。
- 大地图的 `hemisphere_surface.gdshader` 仅是 GlobeRenderer 的物理背景。底部黄铜导航半球仪的绘制、尺寸和交互没有改动。

## LOCAL 三层材质

1. 基础高程色阶：按实际绝对高程编码，与区域底图采用相同的对数高度约定，不按单个数据片的极值拉伸颜色。
2. 坡面和谷地：原生 DEM 法线提供固定双光向明暗；同一原生网格的邻域高差提供有限谷地明暗。原始高度、网格位置和 R13 的显示边缘过渡不变。没有放大垂直高度。
3. 表面颗粒：新增原创 `assets/maps/materials/survey_grain.png`，128×128 灰度可平铺纹理，15,069 字节，CC0-1.0。生成方法为 `tools/map/build_terrain_material.py`。纹理按固定源地理米制坐标取样，不使用屏幕坐标或 TIME。4—24 米/像素之间逐步退出，24 米/像素以外关闭细节。启用 mipmaps 抑制远处颗粒混叠。

第三层不包含任何高程或用地信息，不能作为 1900 年森林、农田、沙丘或街区的证据。纹理仅由当前 LOCAL 地表材质加载和持有，不新增全局纹理缓存。

政治色以独立参数叠加到自然底材。R13 的共同地理投影、固定垂直基准、55 度近景观察、地表插值、注记高度采样及地理边缘过渡保留。没有移动建筑锚点，也没有在 DEM 覆盖外生成高度。

## 现有四处资料

| 地区 | 保留资料及当前显示采样 | R14 实际使用 |
|---|---|---|
| 巴黎 | IGN RGE ALTI，63×63，约33×50米，约2.04×3.10千米；22.25—70.48米 | 平缓地表的原生法线、有限河谷高差、绝对高度底色与近景颗粒；未制造山地 |
| 伦敦 | EA 2022 DTM合成，63×63，约24×39米，约1.50×2.41千米；−6.09—24.58米 | 同一坡面/低地材质，泰晤士水面沿原参考贴合；未视为1900年地表或实测潮位 |
| 吉萨西侧 | COP-DEM-GLO-30 2021 DSM，57×57，约29×33米，约1.62×1.87千米 | 仅既有西侧范围使用中性地势材质；金字塔脚下仍无可靠裸地DEM，不补基座地形或沙丘 |
| 采尔马特西侧 | swissALTI3D 2019，33×63，约19×28米，约0.62×1.72千米；1968.29—2838.33米 | 原生坡向、山脊谷地明暗与绝对高度层次；既有OSM林地仍只代表现代参考 |

全球资料继续使用 NOAA ETOPO 2022 60角秒衍生的现有两级纹理：WORLD 1024×512（赤道约39.1千米），REGION 4096×2048（约9.8千米）。它们不是运行时精细高程。原制作中的双光向及6倍视觉坡度派生约定保留，不重新生成数据，不用于地形测量、路径或模拟计算。

## 水陆和建筑

- 使用既有低饱和灰青水色，并统一海洋、湖泊、河面和中心线的色彩关系。没有增加水体动画、反射、粒子或水深。
- LOCAL 水面顶点在安装时根据已有水面遮罩的邻域取有限岸边色阶。不使用三角形边缘作为河岸，不修改水面范围；数据片边界不当作岸线。该色阶不是实测水深。
- R13 的地表裁水、LOCAL/REGION 水系接管和高程采样保留。巴黎水面继续保留原27米参考；伦敦仍缺实测水位。
- 六种共享模块、巴黎18处、伦敦16处与Millbank4处的声明位置及布局数据保留。仍是概念性微缩组合。三件独特地标和共享 MultiMesh 的贴地与显示尺度路径保留。
- 没有新增接触阴影几何、实时阴影灯光或建筑材质副本。现有采样不足以证明逐栋基座与1900年街道的精确关系。

## 资源与未处理部分

- 保留 WORLD 原始几何所有权、REGION 有界显示批次、按视野行政几何、旧 LOD 退休、LOCAL Mesh/纹理释放、有限 GLB 缓存和共享 MultiMesh。
- 新增的两组顶点 UV 随当前 LOCAL Mesh 生灭，分别承载固定颗粒坐标和高程/谷地显示属性。没有全球精细网格或常驻新增地理数据。
- 必须继续持有的内容包括 WORLD 正式拾取几何、当前 REGION 批次、当前 LOCAL 原生采样及边缘/水面遮罩。引擎自身分配器和 shader 程序缓存的实际释放不能由引用变化推算。
- 没有改动 FormalWorldApplication、SimulationStep、GameClock 或经济工作线文件。既有 `SimulationStep.advance_minutes` 仍按到期边界执行工资、消费、经济、运输和组织处理；经济显示仍会在实际修订后读取正式快照。这些开销没有实测，不能据此认定为卡顿主因。
- 仍缺1900年精细地表、完整历史用地、精确河岸与水位、连续城市建成区和吉萨金字塔基座裸地资料。本轮没有以现代分类或随机内容填补。
- 未运行游戏，不能宣称帧率、内存或最终视觉改善幅度。仍需玩家打开独立R14预览观察地形、颜色、接缝和操作。

## 来源与许可

没有新增外部地理资料。原来源记录保持原样：NOAA ETOPO CC0-1.0；IGN RGE ALTI/BD TOPO Licence Ouverte 2.0；EA DTM Open Government Licence v3.0；swissALTI3D swisstopo OGD；Copernicus WorldDEM-30公共许可；已有OSM水面与林地 ODbL-1.0。具体年代、署名、几何范围和不确定性仍见 `data/local/` 原记录及 R11/R12 说明。

新增颗粒为原创视觉材质，无第三方输入；共享色阶和 shader 仅改变地图表现，不修改地理来源或事实许可。

## 本轮文件

修改：

- `scripts/presentation/map/globe_renderer.gd`
- `scripts/presentation/map/region_view.gd`
- `scripts/presentation/map/local_spatial_layer.gd`
- `scripts/presentation/map/map_scale_style.gd`
- `scripts/presentation/map/hydrography_style.gd`
- `shaders/presentation/map/political_surface.gdshader`
- `shaders/presentation/map/relief_background.gdshader`
- `shaders/presentation/map/hemisphere_surface.gdshader`
- `shaders/presentation/map/local_terrain.gdshader`
- `shaders/presentation/map/globe_water_surface.gdshader`

新增：

- `shaders/presentation/map/terrain_palette.gdshaderinc` 及 Godot `.uid`
- `assets/maps/materials/survey_grain.png` 及 Godot `.import`
- `assets/maps/materials/README.md`
- `tools/map/build_terrain_material.py`
- 本文。

没有删除文件。独立预览及其继承的许可附属资料位于 `builds/preview_2026-10-15_terrain_material_r14/`。普通导入/导出日志位于本地制作目录，不是运行测量结果。
