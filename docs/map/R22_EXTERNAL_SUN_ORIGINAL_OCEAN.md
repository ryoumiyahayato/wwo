# R22：外部太阳方向与原创静态海洋

日期：2026-10-16。基线：本机 R21。Godot 4.6.3 Compatibility。

本轮只修改 WORLD 显示。未运行测试、回归、性能采样、哈希检查或 Git 操作。只做资源导入、唯一一份 Windows 预览导出，以及用户要求的窗口截图。正式领域算法与另一经济工作线文件未改。

## 1. 原因与坐标修正

R20/R21 在 `solar_globe.gdshaderinc` 把 `CHART_SUN` 写成地球坐标中的西经 65°、北纬 20°向量。`solar_ground` 将地理法线直接与它点乘。`solar_ocean` 又以 `earth_to_view * CHART_SUN` 把光源转换到观察空间。月球也读取 `globe_basis * CHART_SUN`。

`GlobeController._orientation` 控制拖动、惯性转动、观察转向和定位。`GlobeRenderer` 把其矩阵作为 `globe_basis` 传给同一套表面 Shader。真实 Camera3D 保持 +Z 位置和原正交方向，只改变取景尺度；没有另一个绕球运行的相机。

因此旧太阳与地理数据共享同一旋转。大陆上的固定经纬度总保持同一受光关系，而观察到的明暗区及高光随地球转动。这是源码中的坐标绑定问题。R20 文档所说的 Earth 坐标固定方向，不能满足本轮要求的外部光源。

现在共享常量为 `CHART_SUN_VIEW = (0.17956061, 0.90777866, 0.37907239)`，即 `normalize(0.18, 0.91, 0.38)`。观察框架为 +X 向右、+Y 向上、+Z 朝正交相机。主光来自画面上方偏右，并朝向可见半球。向量不是从星轨 UI 坐标计算的，也不是 1900 年太阳历表。

陆地、政治面、物理补陆面、海洋与月球统一使用此观察空间方向：

- 政治面由原像素位置还原观察空间球面法线，不再转回地球坐标后与地球固定太阳点乘。
- 海洋半球沿原固定几何使用观察空间法线。物理水域修补面使用同一像素法线与同一海洋函数。
- 海洋镜面仍使用太阳、法线和正交观察方向构造半向量。只有反射法线接受极弱纹理扰动；昼夜入射仍由真实球面法线决定。
- 月球不再读取地球旋转矩阵。其位置、几何、表面程序纹理不改。

`globe_basis` 仍服务地理投影、DEM 定位和海洋纹理定位。它不再旋转太阳。材质中的纹理随地球转动；外部主光不随地理经纬度转动。玩家原旋转、惯性、定位和返回逻辑未改。将来若改变真实 Camera3D 姿态，需要将独立外部方向转换到新观察框架；本轮没有新增相机行为。

夜面沿用 R20 的通道补光 `(0.43,0.49,0.56)` 与原平滑昼夜分界。REGION / LOCAL 仍绕过 WORLD 昼夜光照。

## 2. 国家选择与正式世界

国家选择由 `FormalWorldMenu._install_preview` 实例化原 `globe_renderer.tscn`。进入正式世界时沿已有 PREPARED_MAP 交接复用 Renderer；重新创建地图时也使用相同脚本和 Shader。两处没有第二套太阳方向。

新方向为 Shader 共享常量，不需要每帧提交，也不读取 GameClock。删除月球失去消费者的 `globe_basis` uniform、`_moon_appearance` 字典及相机变化时的对应参数提交。太阳公式不增加日期依赖。

R18—R21 的 TextureRect 承载、按需视口更新、有限 LOD、旧批次交接与退休机制保留。银河、油画菜单、国家/人物选择功能、全部 HUD 与底部黄铜机械半球仪未修改。

## 3. 实际云盘素材与授权

使用已授权 Google Drive 的二工连接，读取目录 [WWO_原创全球海洋静态材质](https://drive.google.com/drive/folders/1jf-64OsRkrNy5j1jGFvPdz2AsoUi5dar)。目录还包含 V2—V5 变体与比较预览。本轮采用用户指定且被正式交付说明逐项列出的原三张图片。没有导入无对应说明的变体或预览图。

| 实际文件 | Drive ID | 本机读取的 PNG 规格 | 原文件字节 |
|---|---|---|---:|
| WWO_Ocean_Macro_Color_2048x1024.png | 15jg4qI45rZFvCplswu4psKtCtPGehgMz | 2048×1024，8 位 RGB，PNG color type 2，无 Alpha | 927585 |
| WWO_Ocean_Micro_Normal_512.png | 1LuiB_Xv5pK27wqcvvcjwSkKLccDD68Vo | 512×512，8 位 RGB，PNG color type 2 | 84211 |
| WWO_Ocean_Roughness_512.png | 1LJiQD529tMbOwz_567Of-JBNoZNjL5xS | 512×512，8 位单通道灰度，PNG color type 0 | 45281 |

已读取并保存 [制作方法与授权说明](https://docs.google.com/document/d/1wJM-5Rd7uFQhvx0qEyZ_8SQkwpE40lMip0uPeXunzdk/edit)。原文位于 `assets/maps/ocean/SOURCE_AND_LICENCE.txt`。说明声明三张图片由数学程序从零合成，无第三方图片输入；允许修改、商业使用和随工程/游戏包分发，无需署名。此处记录交付方声明，不另造许可证名称。

原说明将色图定义为 2:1 经纬度等距圆柱图，要求经度周期闭合、极区收敛；法线为 OpenGL Y+ 切线空间，R=X、G=Y、B=Z；粗糙度为独立灰度。说明声明没有烘焙太阳光斑、浪沫、焦散、阴影或真实水深/洋流表达。

本机已读取 PNG 头和查看实际三张图片。它们表现为低频蓝灰色、弱法线与窄范围灰度，没有可见的烘焙光斑。没有重跑交付方的数值核验、接缝统计或哈希脚本；说明中的数值结论不冒充本轮测量。

三张原 PNG 直接复制到 `assets/maps/ocean/`，未重新生成或改画。导入使用无损模式、Mipmaps，不反转法线 Y，不自动改成另一套有损三维压缩。

## 4. 海洋合成

新增 `ocean_globe.gdshaderinc` 只用于原海洋半球与原 `ocean_reference` 修补面。它复用 `solar_globe.gdshaderinc`，是海洋表面采样函数，不是另一套光照或场景。

色图以 22% 混入原蓝灰底色。以 `transpose(globe_basis) * view_normal` 取得地理法线，转换为与既有地球相同约定的经纬度 UV。纹理色差仅为表面表现，不作为海洋事实。

经度开启重复采样；纬度限制在首尾像素中心，避免北极与南极互相采样。经度导数在接缝处作周期修正后传给 `textureGrad`，避免经度跨 0/1 时选取错误 Mip 层。辅助图以 8×4 的静态经纬度重复坐标采样，在极区按球面水平分量渐退，避免切线方向在极点形成显著放射纹样。

法线只取原 R/G 弱斜率，消除 128 的中性量化偏置，再按原解码斜率的 10% 使用。东/北切线在地球坐标中构造，再通过地球旋转矩阵进入观察空间。这样水纹属于地表，太阳属于外部。宏观球面法线、地形、轮廓和政治边界均不移动。

粗糙度仅围绕 0.54 小幅调整原指数 88：`88 * (1 - clamp(r - 0.54, -0.12, 0.12) * 0.90)`。没有建立 PBR 海况系统。反射强度改为低饱和 `(0.24,0.25,0.23)`，保留太阳入射限制，减少高光与政治图的竞争。

法线与粗糙度不改变日夜分界。背光海洋只采颜色，不采两张反射辅助图。湖泊没有海洋镜面；REGION / LOCAL 不调用此 WORLD 水纹函数。水纹只进入已有合法水域显示，不覆盖国家或边界，也没有改海陆数据。

颜色纹理使用 `source_color`；法线/粗糙度作为数据纹理读取。依据为 [Godot 4.6 Shader uniform hints](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/shading_language.html)。未更换渲染器。

## 5. 新增成本及避免的负担

新增三张共享静态 Texture2D 及各自 Mip 链。PNG 总磁盘体积为 1,057,077 字节；这不是显存占用。实际 GPU 格式和驻留开销未测量。

每个实际调用 WORLD 海洋函数的像素新增一次色图采样；受光侧再有一次法线和一次粗糙度采样，最多三次。原三维海洋半球仍在二维政治面下；不宣称被陆地遮挡的底层海洋完全没有片元成本。海洋修补面也会调用相同函数。没有给政治面、陆地或月球增加这三张纹理采样。

原半球材质创建后绑定一次。海洋修补材质随原有批次安装绑定一次。`ResourceLoader` 共享相同路径的纹理；不新建纹理缓存，不按帧上传。普通时钟和 4× 推进不重建这些材质。

没有反射探针、SSR、动态海浪、TIME、海雾、体积光、新地球、额外灯光、额外视口或纹理生成任务。新增采样不是零成本；没有性能百分比或容量结论。

## 6. 实际文件

修改 7 个既有正式文件：

- `scripts/presentation/map/globe_renderer.gd`
- `scripts/presentation/map/local_spatial_layer.gd`
- `shaders/presentation/map/solar_globe.gdshaderinc`
- `shaders/presentation/map/hemisphere_surface.gdshader`
- `shaders/presentation/map/political_surface.gdshader`
- `shaders/presentation/map/globe_water_surface.gdshader`
- `shaders/presentation/map/moon_surface.gdshader`

新增：

- `shaders/presentation/map/ocean_globe.gdshaderinc` 及 Godot 生成 UID。
- `assets/maps/ocean/` 内上述三张 PNG、三个 `.import` 和原始 `SOURCE_AND_LICENCE.txt`。
- 本文 `docs/map/R22_EXTERNAL_SUN_ORIGINAL_OCEAN.md`。

未删除正式文件。未改 GlobeController 输入、正式世界应用、领域算法、GIS、DEM、历史政治、存档、菜单场景、银河或半球仪。Godot 自身导入缓存按正常导入机制更新，不作为新制作的地理资产。

## 7. 导出与截图

唯一预览目标：`D:/programs/WWO/wwo/builds/preview_2026-10-16_external_sun_ocean_r22/WWO_1900_External_Sun_Ocean_R22_Preview.exe`。

R21 目录保留为回退，正式 `builds/windows/` 保留。R19 的旧预览删除曾被自动审批拒绝，路径与原因见 R21 报告，本轮不重试。R18 有既有用途保留说明。R20 是否仍有独立用途未确认，本轮不扩大清理。

截图目标目录：`D:/programs/WWO/wwo/local-artifacts/r22_screenshots/`。只用 computer-use 的 Windows 实际窗口接口获取，不使用生成图或素材预览冒充游戏。

实际导出、截图路径和观察结果在完成后补记。Shader 修改不等于玩家验收。未测量性能；未确认所有显卡、缩放尺度、经度接缝与极区都没有视觉问题。

### 实际导出

正常资源导入返回 0。唯一 Windows Desktop x86-64 内嵌 PCK 导出返回 0。EXE 为 339,046,136 字节，完整路径即上列目标路径。导出仍显示原 `0.001a` 版本号格式警告，未改变版本规则。导出输出按进度过滤并保留 ERROR/WARNING 文本；未出现新的错误输出。这不作为测试或运行验收。

预览目录附带原来源侧文件、`R22_OCEAN_SOURCE_AND_LICENCE.txt` 和本文副本 `R22_BUILD_NOTES.txt`。保留 R21；没有导出中间候选版本。旧文件的保留说明不变，没有重试被拒绝的 R19 删除。

### 实际窗口返图

通过 computer-use 的 `@oai/sky` 启动上述 R22 EXE，经原菜单“开始”进入默认法国国家选择页。只拖动原球体及放大/还原一次以获取画面。没有进入正式世界、推进日期、存档或覆盖存档。截图保存为窗口接口返回的原 JPEG，包含标题栏，均为 1282×752；未裁剪、改色、合成或生成替代图。

1. `D:/programs/WWO/wwo/local-artifacts/r22_screenshots/01_default_country_selection.jpg`：默认国家选择，完整球体与原国家/人物选择面板。
2. `D:/programs/WWO/wwo/local-artifacts/r22_screenshots/02_rotated_americas.jpg`：旋转到美洲方向，光源构图仍在上方。
3. `D:/programs/WWO/wwo/local-artifacts/r22_screenshots/03_rotated_pacific.jpg`：再次旋转至太平洋，海洋高光仍在球体上方偏右。
4. `D:/programs/WWO/wwo/local-artifacts/r22_screenshots/04_ocean_material_and_solar_glint.jpg`：太平洋放大一级，显示低频海洋色差、克制高光与背光过渡；原选择面板仍在。
5. `D:/programs/WWO/wwo/local-artifacts/r22_screenshots/05_country_selection_full_ui.jpg`：恢复尺度后继续转到澳大利亚方向，展示完整国家选择 UI。

实际画面表明不同大陆方向进入同一上方受光区域，海洋高光包络没有跟随某块大陆移动。微法线/粗糙度细节属于地表，仍会随地理纹理改变。夜面保留轮廓和政治图可读性。该观察只对应这次窗口、这几个方向，不是玩家画质验收，也不能证明所有角度、极区及驱动都没有问题。

正式 WORLD 未在本轮截图流程中进入。其一致性来自相同 Renderer 交接和相同 Shader 的源码路径，不能写成正式世界已通过运行确认。REGION/LOCAL 的绕过规则也没有另做试跑。没有采样或记录性能。

本轮只保留这一份 R22 成果。截图完成后关闭预览，停止施工。
