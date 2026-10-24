# R20 — Solar Globe and Galactic Background

## 球体光照

全球地图原来由三维海洋半球与二维政治/物理面共同组成。仅修改三维材质不能让陆地同步受光。

`solar_globe.gdshaderinc`提供同一组Earth坐标光照。固定太阳方向为西经65°、北纬20°的单位向量。这是制图照明，不读取GameClock，不代表1900年某时刻的太阳位置。现有`globe_basis`把该方向转换到观察空间。转动地球时照明随实际地理法线变化，没有固定屏幕渐变。

海洋半球改为不透明表面，移除旧透明球壳的黄铜色宽边和无效surface_tint。政治面和物理补陆面在原有政治着色、选择调制及真实relief之后应用同一昼夜照明。夜面保留43%—56%的通道补光，国家、海岸和地势仍可读取。REGION/LOCAL不应用球体昼夜明暗，保留原制图照明。

海洋采用固定指数88的半向量镜面项，方向取决于太阳、球面法线和正交观察方向。强度受太阳入射限制，色阶为低饱和暖色。该项只用于海洋球壳及实际ocean_reference面；湖泊不使用海洋镜面，陆地和政治纹理没有镜面项。无反射探针、SSR、新灯光或TIME。原有装饰月球采用同一入射方向；位置和几何不变，不声称真实天文轨道。

## 银河背景

正式世界场景原逐像素背景Shader使用多组分形采样和星点函数。现在由一张2048×1152 RGB PNG替代，文件235,590字节。TextureRect等比覆盖窗口，处于原背景层级。无第二个三维场景、粒子或实时星云。预计未压缩纹理约6.75 MiB，实际上传格式由Godot导入决定，可能为RGBA8约9 MiB；不能将PNG体量当作显存占用。

背景固定在观察空间，不随地球自转。它是低成本固定天文插画，不是星表、真实银河朝向或天文事件。生成方法为`tools/map/generate_galactic_background.py`，使用Python、NumPy和Pillow离线绘制。原始WWO程序化美术，无外部图像/模型输入；该脚本与衍生PNG以CC0-1.0提供。普通星点、淡银河与尘带仅为背景表现。

油画主菜单仍使用原有场景和资源。底部黄铜半球仪的Shader、几何、尺度、位置和交互均未修改。其余HUD布局不变。

## R19后续源码复查

继续阅读物理海岸及政治面、已安装物理LOD、LOCAL TextureRect/透明合成、隐藏模型命中、过期后台结果所属检查、普通时间推进与Presenter的实际入口。

保留R19的同源岸线/面、双扇面地平线裁切、闭环细分、当前物理LOD裁水、海洋取消选择、模型呈现状态、后台代数与世界所属检查。没有修改原始GIS、DEM/DSM、政治身份或行政事实。

R19的LOCAL纹理仍由预乘Alpha TextureRect承载；静止视图键返回，不因普通时钟申请新三维图像。隐藏模型命中仍要求可见且已呈现。隐藏页面和普通日期的刷新隔离保留。本轮未发现足以重新改写这些路径的新证据，不重复申报R19成果。

本轮清理的是正式世界背景的旧逐像素Shader及UID、海洋球壳的旧透明/黄铜边参数。太阳方向为共享常量，观察矩阵沿用现有参数值缓存，不新增定时更新和材质复制。新增静态背景纹理需要驻留；其成本不声称为零。

正式时间链仍为0.25秒Timer→TimeControl→SimulationStep/GameClock→领域结算→实际可见页面更新。工资、消费、运输、人物、组织及经济计算不改。没有性能测量，不能排序GPU、主线程上传、合法结算及整机换页负担。

## 文件

修改：
- `scenes/formal/formal_world_main.tscn`
- `scripts/presentation/map/globe_renderer.gd`
- `scripts/presentation/map/local_spatial_layer.gd`
- `shaders/presentation/map/hemisphere_surface.gdshader`
- `shaders/presentation/map/political_surface.gdshader`
- `shaders/presentation/map/globe_water_surface.gdshader`
- `shaders/presentation/map/moon_surface.gdshader`

新增：
- `shaders/presentation/map/solar_globe.gdshaderinc`
- `shaders/presentation/map/solar_globe.gdshaderinc.uid`
- `assets/maps/background/galactic_chart.png`
- `assets/maps/background/galactic_chart.png.import`
- `tools/map/generate_galactic_background.py`
- `docs/map/R20_SOLAR_GLOBE_GALACTIC_BACKGROUND.md`

删除：`shaders/presentation/ui/workspace_background.gdshader`及其UID。它的唯一运行引用已由纹理替换；历史文档不改写。

## 交付和剩余问题

目标预览：`D:/programs/WWO/wwo/builds/preview_2026-10-15_solar_globe_galactic_r20/WWO_1900_Solar_Globe_Galactic_R20_Preview.exe`。

保留R19回退，不推送。正常导出完成后，仅为用户明确要求的返图打开当前预览；不安排性能基准、探针、回归或额外测试。实际导出、画面与截图情况另在文末补记。

有限河岸、现代与历史海岸精度差异、小岛/河口资料及LOCAL地形覆盖仍有限。没有新建城市、森林、地貌纹理或导入120件古迹。卡顿、风扇负担和最终视觉可接受性不能由源码修改或单次截图证明。

### 实际导出与返图

Windows Desktop x86-64内嵌PCK导出返回0。EXE为337,660,696字节。正常导出输出没有SCRIPT ERROR或ERROR；保留原`0.001a`版本字符串警告，未修改版本规则。

已使用computer-use技能的Windows窗口接口打开上述R20 EXE，经原有菜单新建法国开局。游戏日期保持1900-01-01 00:00暂停；没有推进4×、记录性能或执行自动化测试。仅为用户要求的画面获取进行缩放、旋转、打开日志，以及使用原行政名录定位巴黎。没有保存或覆盖正式存档。

原始窗口JPEG保存在`D:/programs/WWO/wwo/local-artifacts/r20_screenshots/`，均为1282×752窗口画面，保留标题栏及原画面，没有合成、改色或AI替代：

- `01_solar_globe.jpg`：完整地球、日夜明暗、大西洋高光。
- `02_galactic_background.jpg`：另一观察方向的地球及固定银河背景。
- `03_main_hud_archive.jpg`：地球、银河、时钟、顶部星轨、原日志抽屉和底部黄铜半球仪。
- `04_france_region.jpg`：法国及周边REGION当前画面。
- `05_britain_region.jpg`：英国REGION当前画面。
- `06_paris_local.jpg`：经已有塞纳省资料定位后的巴黎LOCAL，包含原地形、铁塔和18个建筑体块。

这些画面确认本轮新球体光照与背景已进入实际项目，不代表玩家已验收其质量。截图还表明：法国西部填充和岸线的视觉关系仍不一致；巴黎地表仍显单调，局部坡面和不同来源河线的衔接仍不充分。不能将这些旧问题写成已经解决。

源码中已继续核对原几何输入、分片和三角化、当前物理批次、显示层级及局部命中路径。上述现状不能仅凭截图确定为某一项投影/三角化故障，也不能一概归为历史年代差异；尚无足够依据安全修改其共同根因。本轮没有改动原始轮廓、补造水面、添加海岸遮罩或为单独城市写偏移。未声称LOCAL黑边、全部海岸及缩放负担已经通过画面验收。

R19完整保留。旧R18目录在本次开始时仍在用户资源管理器中打开，未将其当作已确认无用的产物删除；本轮不扩大目录清理。原始研究资料和经济工作线未动。没有Git提交或推送。
