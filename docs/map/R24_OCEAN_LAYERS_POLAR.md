# WWO R24 — Ocean Layers and Polar Ice

日期：2026-10-16。基线：本机 R23 正式源码。Godot 4.6.3 Compatibility。仅施工海洋材质、球体明暗和极地显示。沿用 R23 内部预览配置，不扩展古迹。

## 1. 本机素材调查

实际目录是 `C:/Users/agcrf/Downloads/orbital_ocean_materials/`，不是 `C:/Downloads/`。没有移动或清理下载原件。该目录有 18 张独立纹理、6 张根目录图片、清单、生成代码、嵌入数据、HTML、GLSL、GLB、OBJ、MTL 和 ZIP。逐张查看了 18 张纹理，并阅读清单及相关生成/着色代码。

18 张 PNG 均为 512×512、RGB、无 Alpha。它们是方形程序合成平铺素材，不是 2:1 全球颜色图，也没有真实经纬度配准。清单中的“洋流”“水深”“SST”不使合成场成为实测资料。浮冰多边形由 Voronoi 生成，水华和涡旋来自程序噪声。没有据此创建地理事实。

| 文件（textures/ 下） | 本轮处理及原因 |
|---|---|
| `pelagic_eddies_albedo.png` | 采用。原件复制，203477 字节。只读蓝通道粗 MIP 的低频变化，不直接覆盖原颜色，也不展示为真实洋流。 |
| `pelagic_eddies_normal.png` | 不采用。交叉涌浪/微波网格在全球球体上会增加细碎高光；仍用球面法线。 |
| `pelagic_eddies_roughness.png` | 不采用。RGB 是粗糙度/镜面/涡度复合数据，不是独立灰度粗糙度；不增加旋涡亮带。 |
| `chlorophyll_bloom_albedo.png` | 不采用。翡翠色丝带和旋涡明显，没有实际水华位置依据。 |
| `chlorophyll_bloom_normal.png` | 不采用。锋面/微波扰动不服务本轮静态弱层次。 |
| `chlorophyll_bloom_roughness.png` | 不采用。生物油膜高光控制会强化花纹；通道也不是单张普通粗糙度。 |
| `coastal_shelf_albedo.png` | 不采用。明亮浅滩和泥沙没有配准，会假造海岸浅水区域。 |
| `coastal_shelf_normal.png` | 不采用。沙脊/浅滩起伏不能作为真实海底或全球波形。 |
| `coastal_shelf_depth_sss.png` | 不采用。粗糙度、透光率、浊度为合成通道，不能当实际水深或岸线遮罩。 |
| `internal_waves_albedo.png` | 不采用。弧形重复条带在全球尺度过强。 |
| `internal_waves_normal.png` | 不采用。规则内波和微波细节会打散太阳反射。 |
| `internal_waves_roughness.png` | 不采用。设计目标是高反差耀斑条纹，与本轮集中、静态高光不合。 |
| `polar_pack_ice_albedo.png` | 采用。原件复制，323991 字节。只读平滑后的蓝通道，弱调冰水层次，不满强度显示黑色裂纹。 |
| `polar_pack_ice_normal.png` | 不采用。浮冰边界/冰脊高差会夸大纹样，且新增一次法线采样。 |
| `polar_pack_ice_roughness.png` | 不采用。RGB 分别是粗糙度/光泽/覆盖率；本轮可从同一冰图取弱标量，不需第三张图。 |
| `hydro_sst_thermal.png` | 不采用。热力伪彩和合成温度不能进入基础海色。 |
| `hydro_flowmap_uv.png` | 不采用。合成流场用于动态平流；本轮不做动画。 |
| `hydro_bathymetry_relief.png` | 不采用。合成中脊/海沟/SSH 不能替代真实 DEM 或海深资料。 |

根目录六张 PNG 对应水华、浅滩、SST、内波粗糙度、深海和浮冰预览。同名资源已在 textures 中审阅，不再安装一份根目录副本。没有做哈希或内容指纹比对。

`materials_manifest.json` 有 18 项，给出名称、用途和通道，不提供全球配准或明确版权授权。`ocean_textures_data.js` 含 18 个 PNG data URL，供浏览器展示；不在 Godot 中运行或打包整份嵌入 JS。`generate_ocean_materials.js` 用本地程序场生成图片，尺寸常量为 512；只阅读，未运行、未生成第四套海洋素材。其内部 PNG 完整性与噪声函数未被拿来计算项目指纹。

`viewer.html` 使用 Three.js、预加载纹理、持续动画、双相流场平流、多次法线/粗糙度采样和边缘光晕。仅研究其材质思路，不将网页、持续绘制或多层光晕搬入游戏。`shaders/orbital_ocean.glsl` 也是这套动态路径；未接入。R24 保留现有一次半向量镜面公式，没有引入其完整 GGX/SSS/色调映射系统。

实际 GLB 为 117104 字节，一 Mesh、一材质、2665 顶点、5120 三角形，无嵌入图片。其材质仅为基础颜色、metallic 0.1、roughness 0.28。OBJ 为 324966 字节；MTL 为 305 字节，引用水华颜色/法线/粗糙度。球体 UV 经度乘二，会重复方形纹理。它们适合外观预览，不带 WWO 地理裁切和政治关系；均不导入，不增加第二个球体。ZIP 是素材包，不作运行时资源。

README 声明本地程序合成，但本目录未找到明确商业/公开再分发许可。本次依用户授权用于本机内部预览。来源记录写入新资产目录。没有宣称取得公开发行权；R23 古迹的内部权限边界继续保留。

## 2. 海洋层次与通透感

沿用原海洋半球和已准入的物理海面。没有新 Mesh、球壳、视口、缓存或 Shader 动画。R22/R23 三张原海洋 PNG 仍保留，本轮不再绑定它们。

新深海图只采样蓝通道。使用固定 MIP 4（约 32×32 层级）压低丝状涡旋。经度仅一周铺图，纬度采样约束在 0.03125—0.96875。变动为 `clamp((b−0.28)×2.2,−0.18,0.18)`，再随高纬平滑衰减。它是弱表面色阶，不代表水深、洋流或地图分区。没有按国家染色。

基础色从 R23 的 65% `(0.10,0.24,0.29)` 混合，改为原 water 与 `(0.055,0.20,0.29)` 混合 75%。低频标量轻微改变亮度与蓝绿色阶。没有满强度使用深海图的深黑/靛蓝原色。

通透感采用单层不透明材质内的明暗与球缘处理。视线掠射时，海色倍率从中心 0.94 平滑趋向边缘 1.06；窄边缘光使用 4.5 次方，色阶 `(0.035,0.080,0.110)`，强度仍随太阳入射变化。冰区抑制这个海水边缘项。

没有真实 Alpha、屏幕背景采样或透射。背面大陆、国旗和星空没有新增穿透通道。原政治面、物理补陆、海岸和前半球裁切顺序保留。没有重复海岸几何。此次是视觉通透感回归，不是物理折射模拟。

## 3. 固定太阳及明暗

`CHART_SUN_VIEW` 仍为 `(0.17956061,0.90777866,0.37907239)`，观察空间上方偏右。地球旋转只改变地理法线和纹理位置，不旋转光源。相机方向和光照继续使用同一观察空间。日期、GameClock 和星轨 UI 不参与照明计算。

| 参数 | R23 | R24 |
|---|---|---|
| 日夜平滑区间 | −0.16 到 0.24 | −0.11 到 0.17 |
| 夜面 RGB 补光 | 0.30 / 0.36 / 0.44 | 0.25 / 0.32 / 0.42 |
| 昼面倍率 | 1.02 | 1.06 |
| 太阳正向入射额外上限 | 24% | 32% |
| 镜面指数 | 256 | 384 |
| 镜面颜色系数 | 0.38 / 0.41 / 0.39 | 0.54 / 0.57 / 0.53 |

明暗过渡变窄，但仍是 smoothstep。昼面和高光峰值提高，范围收紧；没有统一提高整球曝光。镜面仍由外部太阳、真实球面法线和观察半向量计算。冰区按其混合量最多抑制 85% 海水镜面，不让冰盖反射成海洋亮斑。没有启用微法线或动态粗糙度。

国家选择和正式 WORLD 共享这些 Shader。REGION/LOCAL 仍走原制图照明，新增极地海面函数只在 WORLD 路径调用。银河、原菜单油画、HUD 和黄铜机械半球仪文件及交互未改。

## 4. 北极与南极

北极海面从约 72°N 到 84°N 平滑加入寒带冰水色，最大美术权重 0.82；南方海面从约 66°S 到 78°S 平滑过渡，最大 0.46。冰图以 `earth.xz×2.2+0.5` 做极区平面采样，固定 MIP 5（约 16×16 层级）。避免经纬映射在极点把裂纹拉成放射线。蓝通道只在 0.93—1.0 倍范围弱调混合量，映射到灰蓝冰色 `(0.61,0.73,0.78)`。

上述纬度和权重是静态构图规则，不是 1900 年、某季节或当前日期的海冰边界。没有补造海冰 GIS、海岸、海宽、冰厚或动画。两极不是满白纯色圆盘；现有陆地和政治表面照旧覆盖海洋。

项目原来已有 `antarctic_land` 分类，来自四组已安装物理陆地分片。R24 沿用此分类，只为该既有补陆材质安装一个布尔标记。WORLD 上将其颜色向 `(0.76,0.83,0.86)` 混合 80%，再施加真实地势和共享太阳明暗。不是新增南极大陆或主权。REGION 不使用这次颜色增强。

物理分片尚未安装时，原海洋半球中的 DEM 陆地回退也在南方高纬使用同一冰雪色倾向，仍受原陆地遮罩限制。海冰纹样不作为陆地轮廓。高程、地形强度与数据原件没有改动。

## 5. 成本与边界

两张原图合计 527468 字节。导入为无损纹理，生成 MIP，并关闭自动 3D 压缩切换。图像仍是原文件；没有离线重绘或修改 PNG 内容。若按 RGBA8 加完整 MIP 估算，两张纹理约 2.67 MiB；这只是格式估算，不是显存测量。

非极地海面只读一次深海图。极区最多再读一次冰图，R23 为一次宏观色图采样。新增代价是一张 512×512 冰图的驻留、局部第二次采样及少量标量运算。既有物理海面覆盖半球时仍有原路径的重叠绘制，未宣称该成本消失。

材质安装时绑定共享 Texture2D，沿用 ResourceLoader 和参数值缓存。没有每帧生成图片、重新创建材质、扫描下载目录或绑定 GameClock。没有反射探针、SSR、流场、双相平流、体积效果、额外光源或持续重绘。新增成本有界，但未实测，不能保证所有机器的风扇或缩放表现。

## 6. 实际文件

修改既有正式文件 7 个：

- `scripts/presentation/map/globe_renderer.gd`：两张静态纹理绑定替代旧宏观纹理绑定。
- `scripts/presentation/map/local_spatial_layer.gd`：只在原南极补陆材质安装时设置分类标记。
- `shaders/presentation/map/ocean_globe.gdshaderinc`：低频色阶及极区冰水混合。
- `shaders/presentation/map/solar_globe.gdshaderinc`：明暗、高光和单层边缘层次。
- `shaders/presentation/map/political_surface.gdshader`：原南极物理补陆的 WORLD 冰雪色。
- `shaders/presentation/map/hemisphere_surface.gdshader`：原 DEM 陆地回退的南方高纬冰雪色。
- `export_presets.cfg`：现有内部预览的默认输出指向 R24，避免再次手动导出时覆盖 R23 回退；未改变正式发布配置。

新增正式文件：

- `assets/maps/ocean/orbital_r24/pelagic_eddies_albedo.png` 及 `.png.import`。
- `assets/maps/ocean/orbital_r24/polar_pack_ice_albedo.png` 及 `.png.import`。
- `assets/maps/ocean/orbital_r24/SOURCE_AND_USAGE.txt`。
- `docs/map/R24_OCEAN_LAYERS_POLAR.md`（本文）。

没有删除正式源码或资源。没有修改经济、人口、人物、组织、军事、GameClock、SimulationStep、五槽存档、LandTopology、国家身份、GIS 或 DEM。没有 Git 操作。其他工作线的本地文件没有覆盖或还原。

## 7. 唯一预览、实际截图与构建清理

唯一导出目标：`D:/programs/WWO/wwo/builds/preview_2026-10-16_ocean_layers_polar_r24/WWO_1900_Ocean_Layers_Polar_R24_Preview.exe`。

使用原 `Windows Desktop Internal Landmark Preview`、x86-64、嵌入 PCK 的配置。R23 三件古迹仍限内部预览，不扩大接入。新素材的公开发行许可也未由本轮确认。

本轮没有进入正式世界，只在国家选择界面旋转取图。没有启动性能采样、自动测试、回归、哈希核验、安全审计或 CI。没有写正式存档。

R24 首次导出成功后，实际窗口中极地原图的多边形裂纹仍明显。因此将冰图固定 MIP 从 2.5 改为 5，标量调制幅度从 28% 压至最多 7%。更新同一路径的未交付 R24 文件，不生成另一套候选预览。下载原图保持原样。

已删除 `D:/programs/WWO/wwo/builds/preview_2026-10-16_external_sun_ocean_r22/`：13 个文件，长度合计 339541061 字节。删除前检查绝对路径位于 builds、不是目录链接，且当前窗口中没有 R22。使用原生 Remove-Item，没有强制删除；随后该目录不存在。字节为删除文件长度合计，不是磁盘簇占用测量。

保留 R23 回退、R24、`builds/windows/` 当前正式文件。R19 因此前删除返回 `blocked by policy` 而保留，本轮未重试、改权限或换工具删除。下载 ZIP、生成源、研究资料、正式资源、存档和其他工作线产物未清理。只查看 builds、packaging 及项目/local-artifacts 根目录的打包产物，没有全项目清扫。未发现其他已确认可删的安装包或临时 PCK。

最终导出正常完成，`savepack` 完成；EXE 为 339766248 字节。原 `0.001a` 版本号格式警告仍存在。没有将导出成功等同于画质验收，也没有声称缩放、风扇或卡顿已解决。

实际窗口截图位于 `D:/programs/WWO/wwo/local-artifacts/r24_screenshots/`。均来自最终 R24 EXE 的真实窗口，不是浏览器 viewer、生成图或渲染概念图。没有后期修饰游戏截图。鼠标蓝色光圈属于原界面指针，不是太阳高光。取图期间出现手动操作提示时，先停止输入并重新读取窗口，再继续。

| 实际画面 | 文件 |
|---|---|
| 原油画主菜单 | [00_oil_menu_unchanged.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/00_oil_menu_unchanged.jpg) |
| 国家选择完整 UI | [01_country_selection_ui.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/01_country_selection_ui.jpg) |
| 大西洋层次、昼夜交接 | [02_atlantic_day_night.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/02_atlantic_day_night.jpg) |
| 北大西洋高纬近景 | [03_north_atlantic_arctic_close.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/03_north_atlantic_arctic_close.jpg) |
| 北极冰水过渡 | [04_arctic_ice_transition.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/04_arctic_ice_transition.jpg) |
| 太平洋、集中高光、暗面 | [05_pacific_glint_and_layers.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/05_pacific_glint_and_layers.jpg) |
| 南极原陆地轮廓、南方海面 | [06_antarctica_and_southern_ocean.jpg](D:/programs/WWO/wwo/local-artifacts/r24_screenshots/06_antarctica_and_southern_ocean.jpg) |

`material_contact_sheet.jpg` 仅为下载素材的缩略审阅拼图，不列作游戏截图。未对截图做性能计数。窗口取图结束后关闭；没有点击“进入世界”。正式 HUD 和 LOCAL 古迹不在本轮实机取图范围内，保留的是源码及资产路径。

## 8. 尚未确认

已在国家选择窗口看到弱海色变化、收紧的太平洋太阳反射、北极冷色过渡和南极冰雪陆地。首次出现的多边形冰裂纹已通过粗 MIP 和低权重压低。南极内陆仍是现有地形/底色表达，没有精细冰川纹理；海冰没有显示真实浮冰位置。主观清澈感、亮暗力度及冰水过渡是否合意，仍由用户查看。

没有实测 GPU/CPU/FPS/内存或风扇负担。两张纹理和极区第二次采样的成本不为零；没有发现本轮新增的持续重绘、重型反射或多球体路径，但不能据此保证所有机器表现。正式 WORLD/REGION/LOCAL 本轮没有启动或做回归；保留共享路径不等于已逐层实机确认。

海冰没有逐年/季节配准资料。冰图只作美术提示；不能用于历史冰况、水文、航行或主权判断。原有海岸精度差异仍存在。没有新增任何高精度地貌或地标。
