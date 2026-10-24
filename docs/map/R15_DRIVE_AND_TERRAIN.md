# R15：云端素材目录与中尺度地势

基线为本机 R14。未使用远端源码覆盖。没有启动游戏、采集截图、运行性能测量或自动推送。

## Drive 接入与范围

- 使用 Codex 已授权 Google Drive 插件，读取“二工”账号。未使用 ChatGPT 授权假定、本地盘符、匿名下载代理或新安装工具。
- 先读取文件元数据，再通过接口返回的授权文件引用读取 GLB。未移动、覆盖、删除或重命名云端文件。
- 根目录只处理01—120。实际120件，5,143,656字节（约4.905 MiB）。编号之外的新素材未扩大接入。
- 120件 GLB 均已读取二进制头和 glTF JSON，记录场景、节点、Mesh、Primitive、索引三角面、顶点属性计数、材质和纹理引用。三角面范围288—2476；没有内嵌图片。静态结构不能证明外观、比例和历史形制正确。
- 数据在内存中解析。没有把120件 GLB 复制到正式 assets、创建120个场景或运行时注册对象。目录只在 docs，导出预设排除 docs。
- `drive_landmark_catalog_r15.json` 逐件保留文件名、Drive ID和原链接、文件大小、名称和地区的文件名声明、结构、历史分类、锚点、许可和接入状态。文件名中的现代国家/地区标签不是1900年政治资料。
- A类0件，B类2件（巨石阵、加尔桥：已有遗址存在依据，模型1900年形制未核定），C类118件，D类0件。未知不等于已可用或已被否决。其余没有逐件开展历史考证。未创建未核定的坐标或正式地点引用。
- 120件古迹均未附 `asset.copyright`。读取权限不能证明作者及再分发许可。目录记录为权利待确认，未进入游戏发布资源。

## 古迹历史依据与未安装原因

- [English Heritage：巨石阵修复史](https://www.english-heritage.org.uk/visit/places/stonehenge/history-and-stories/history/conservation/)记载1901年和20世纪后续修复。模型尚未与1900-01-01石块状态对应；当前伦敦 LOCAL 不覆盖该地点。
- [Pont du Gard 官方历史](https://pontdugard.fr/en/discover/history)记载1855—1859年修复。模型尺寸和1900形制未核定；当前巴黎 LOCAL 不覆盖加尔桥。
- 两处遗址都需要独立的地理锚点、适用地表和模型许可记录。本轮没有为摆放模型虚构 LOCAL 地形。历史网页只作事实引用，没有将其图片作为游戏资产。
- 其他目录中发掘遗址、迁移建筑和复建形制仍待逐件确认。没有仅按名字认定适合1900年。

## 地貌库

用户给定 Godot 优化目录当前实际名称为 `Godot与游戏引擎优化版_v8_全60款四季与性能极限套件`，ID保持不变。目录71项：67件GLB（60款、总览沙盘、6款季节变体）及4份原生文档脚本。

`drive_landform_catalog_r15.json` 保留71项元数据，实际读取山地、林地、平原、河滩四件GLB结构；其余仅有目录记录。另读取V8及V6导入说明内容，未运行或复制其脚本。

| 样本 | 文件字节 | 三角面 | Mesh数 | 内嵌许可字段 |
|---|---:|---:|---:|---|
| 山地 | 58,116 | 2,043 | 3 | CC0 / Game & Godot Engine Ready (8x8m Modular Grid) |
| 林地 | 70,456 | 2,310 | 3 | 同上 |
| 平原 | 49,172 | 1,755 | 3 | 同上 |
| 河滩 | 62,868 | 2,136 | 5 | 同上 |

可参考少材质、Surface/Plinth/Obstacles分组、静态低模轮廓。它们是带地质底座和人工障碍物的8米艺术模块，不能替代真实DEM、森林范围、河岸或LandTopology。季节变体和六边形沙盘没有接入。四件的内嵌CC0声明不代替其余文件的来源和作者记录。没有新增正式模型、材质或碰撞体。

## 中尺度地形

复用 `local-artifacts/physical-relief-r1/source/ETOPO_2022_v1_60s_N90W180_surface.tif`。没有下载新的全球资料，也没有重新生成 world.bin/region.bin。

现有 `tools/map/build_global_relief.py --regional-windows` 仅读取四处所需的TIFF块。每片97×97个原生60角秒样本，额外一圈仅用于差分。使用与原全球层一致的非负高程、双方向照明、六倍视觉法线和对数高度编码；没有改变高程或建立新高度Mesh。六倍是已有明暗约定，不是六倍真实山高。

| 范围 | 西/南/东/北（度，约） | 原生间距东×北 | 文件字节 |
|---|---|---|---:|
| 巴黎外围 | 1.4833 / 48.05 / 3.10 / 49.6667 | 1,219×1,853米 | 10,148 |
| 伦敦外围 | −0.9333 / 50.70 / 0.6833 / 52.3167 | 1,154×1,853米 | 10,185 |
| 采尔马特外围 | 6.9333 / 45.2167 / 8.55 / 46.8333 | 1,287×1,853米 | 17,667 |
| 吉萨外围 | 30.3333 / 29.1667 / 31.95 / 30.7833 | 1,605×1,853米 | 7,876 |

四片合计45,876字节。PNG编码仍用既有 `.bin` 形式，由现有 `GeographyLoader.decode_relief` 在工作线程解码为RG8。每片理论像素数据18,818字节；不是实测显存或内存占用。

- WORLD仍使用原全球远景。REGION原全球9.8千米层之外，仅在当前视野与片区相交、尺度合适时请求一片中尺度数据。
- 2,200米/像素以内准备，已加载片可保留到3,000米/像素；1,100—3,000米/像素之间渐变。一次最多一片，不预加载四片。
- Shader以同一逆投影经纬度采样，边缘在地理范围内羽化12%，不使用固定屏幕蒙版。它只细化现有陆地的地势表达，不提供海岸、主权、水宽或土地分类。
- LOCAL继续使用原IGN、EA、swissALTI3D和Copernicus资料与R13投影。中尺度地势在有限高精度范围之外提供外围地貌，不把高精度小片扩大到整个窗口。
- 该成果填入约1—2千米地势层，仍未补齐全部百米级过渡。ETOPO不能表达巴黎/伦敦街道、精细河岸或吉萨基座。

## 地表颜色、水陆与现有模型

- 发现国家选择会修改 `political_base_color`，随后 `_local_ground_style()` 将该颜色送入LOCAL地表。现已停止选择对基础地表墨色的修改，保留已有旗帜/边界反馈。不能据此认定截图中所有青绿变化均出于选择。
- 近景政治底色权重由0.42降至0.22，远景仍按已有曲线回到国家着色。增强真实地势读取，不改变政治事实或旗帜。
- 没有新增地表分类、森林、农田、沙丘、水宽和水面。保留R13裁水、R14低饱和水色及已有岸边色阶。没有动态水纹或新增水体采样。
- 巴黎、伦敦既有抽象微缩组合、Millbank设施、三件地标、共享Mesh和MultiMesh数量与位置均保持。地表底色变化仅影响环境观感，不把抽象组合升格为逐栋史实。
- 未改相机、地理锚点、DEM顶点、HUD、经济工作线、时间算法或存档。

## 调度与释放

- 扩展原 `MapRelief`，没有第二套缓存或资源服务。相同可见性、尺度、视野、资产描述不再重算需求列表。
- 一个解码线程沿用既有队列。过期请求完成后丢弃；失败请求在相同视野不循环重试，离开并重新进入后允许重试。
- 离开片区、退出REGION或隐藏地图时移除中尺度纹理。政治面、背景及战略陆地的有效/退休批次同步清空对应sampler和参数缓存，避免隐藏材质继续引用旧纹理。
- 当前政治与物理陆地共享同一张有效中尺度纹理。没有新几何副本。普通相机变化只调整必要权重和投影；参数缓存避免重复向渲染端提交。
- 保留R10旧LOD退休、LOCAL离场释放、R12共享建筑、有限PackedScene缓存和R13水面交接。没有因普通时钟或鼠标悬停新增地形准备。
- 仍有引擎分配器、Shader程序和有效WORLD拾取/几何的必要驻留。未运行，不能推算实际内存下降或卡顿改善。

## 来源与许可

- 新四片衍生数据：NOAA NCEI ETOPO 2022 v1 60s surface，WGS84 / EGM2008，CC0-1.0，现代复合物理参考。原 `global_physical_relief.json` 来源和历史限制保留，新增 bounded_derivation 与四片描述。
- 既有LOCAL来源未改：IGN RGE ALTI（Licence Ouverte 2.0）、EA DTM（OGL v3.0）、swissALTI3D（swisstopo OGD）、Copernicus DSM（WorldDEM-30公共许可）；水面/林地继续使用既有现代参考和ODbL说明。
- 没有新卫星图或云端模型进入发布资源。R14原创颗粒材质保留。

## 文件与交付

修改7项：`scripts/presentation/map/map_relief.gd`、`globe_renderer.gd`、`local_spatial_layer.gd`、`map_scale_style.gd`；`shaders/presentation/map/political_surface.gdshader`、`relief_background.gdshader`；`tools/map/build_global_relief.py`。另更新 `data/presentation/global_physical_relief.json`。

新增：`assets/maps/relief/native_paris.bin`、`native_london.bin`、`native_zermatt.bin`、`native_giza.bin`；`shaders/presentation/map/regional_relief.gdshaderinc`及Godot UID；`docs/map/drive_landmark_catalog_r15.json`、`drive_landform_catalog_r15.json`和本文。没有删除文件。

Windows预览已导出：`D:/programs/WWO/wwo/builds/preview_2026-10-15_drive_terrain_r15/WWO_1900_Drive_Terrain_R15_Preview.exe`。沿用Windows Desktop x86-64预设，保留R14。构建不等于运行验收。普通导入和导出完成，导出返回0；沿用项目原有 `0.001a` Windows版本号警告，未改动版本配置。没有启动游戏或额外检查。

仍缺：120件古迹作者及再分发依据、逐件1900形制/尺寸/坐标；候选所在地可靠LOCAL地表；四片范围之外中尺度数据及百米级连续地形；历史土地覆盖、精确河岸与水位；吉萨基座裸地。实际颜色接缝、细地形观感、卡顿和引擎驻留仍待玩家观察，未宣称已确认。
