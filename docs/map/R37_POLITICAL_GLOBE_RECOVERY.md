# WWO R37 — Political Globe Rendering Recovery

日期：2026-10-18。基线：本机 R36。Godot 4.6.3 Compatibility。

本轮实际修改政治地图的制作和读取路径。没有启动游戏，没有测量启动时间、CPU、GPU、FPS或内存。R36未通过画面验收；本报告不把导出成功当作画面正确。

## 1. 为什么先出现自然地球，随后才出现旗帜

R36的正常路径确实包含两轮准备：

1. `GlobeRenderer._sync_strategic_resources()` 在已有物理底图后才请求 ink。
2. `StrategicSpatialLoader.request()` 又检查对应物理范围是否已经安装。
3. 第一轮读取物理 `.geom`，准备、上传并发布中性陆地和海岸。
4. 发布通知发起第二轮读取 `.ink.geom`。这些文件只预制了平面三角形和历史引用编号。
5. `LocalSpatialLod.prepare()` 仍逐面转换经纬度、按国家和源分片分组、球面细分、计算UV、制作面字典，然后调用 `GlobeSurfaceBatch.encode()` 制作RGBAF字节、顶点和索引。
6. 主线程再创建Mesh、ImageTexture、材质和CanvasItem。整批上传、提交后才出现国旗。

所以“有 ink 预制文件”不等于“启动时直接使用完成的显示数据”。后台执行仍然有实际计算成本。用户报告的约10秒是实机观察；源码不能拆出各步骤耗时，也不能证明其中某一步占满了这10秒。

## 2. 哪些工作现在提前完成

扩展现有 [build_geographic_foundation.py](D:/programs/WWO/wwo/tools/map/build_geographic_foundation.py)，新增 `--compile-display` 模式。它调用 [compile_political_display.gd](D:/programs/WWO/wwo/tools/map/compile_political_display.gd)，使用项目现有的 `StrategicSpatialLoader._load()`、`LocalSpatialLod.prepare()`、`GlobeSurfaceBatch.encode()` 和 `GlobeBoundaryBatch.encode()`。

这是一条离线资产制作入口。没有加载游戏主场景、创建正式世界、推进时间或访问五槽。它不导入GIS制作依赖，也不调用原始Natural Earth/CShapes布尔处理分支。

实际提前完成：

| 工作 | R36首次准备 | R37固定历史显示 |
|---|---|---|
| 历史查询环展开、组件包围范围、国界显示线采样 | 每次计算 | 从原始历史资料制作一次，原生读取 |
| 政治 ink JSON展开、引用编号解析 | 每次处理所需文件 | 制作时处理；正常初始显示不读取 ink JSON |
| 政治三角形按历史引用、源物理分片分组 | 每次计算 | 已存入分片显示包 |
| 原有球面细分 | 每次计算 | 已完成，未降低边缘精度 |
| 国旗UV、经度换周 | 每次计算 | 已按历史组件完成 |
| RGBAF面数据、顶点、索引、裁剪包围参数 | 每次编码 | 已存原生PackedArray |
| 物理海岸显示线及边界编码 | 每次制作 | 同分片预制 |
| GPU Mesh、纹理、材质、CanvasItem | 主线程创建 | 仍须主线程创建，保留预算 |
| 国家身份、当前主权、旗帜选择和资料查询 | 正式资料解析 | 继续读取正式资料，未跳过 |

制作命令：

```powershell
& 'C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/map/build_geographic_foundation.py --compile-display --apply --godot 'D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64_console.exe'
```

先读现有正式 `.geom` / `.ink.geom`，再保存原生压缩Variant。没有重新生成或改写原 `.geom`、`.ink.geom`、原始GIS及高程。

## 3. 初始政治地球如何读取

[StrategicSpatialLoader.request()](D:/programs/WWO/wwo/scripts/content/strategic_spatial_loader.gd:25) 识别当前必需分片是否具备预制显示描述。具备时，可以直接准备这一份包含完整物理陆地、未知中性区域、政治分区和海岸的包。无需先安装另一份中性GPU陆地，再从头生成相同范围的政治陆地。

`_load()` 保留物理多边形、海陆查询、来源准入及原分片ID。它用显示描述代替再次展开政治 ink。正常编译路径完成必要验证后，丢弃不会再使用的物理显示三角形数组和已消费的解码条目；物理查询多边形仍保留。

[LocalSpatialLod._prepared_display()](D:/programs/WWO/wwo/scripts/presentation/map/local_spatial_lod.gd) 在原工作线程中按需读取相应 `.display`，直接返回已编码批次。原生反序列化、解压和GPU创建仍有成本；没有宣称这些工作变为零。

首屏仍按当前视野、原LOD选择和完整范围发布。没有加载全部456份文件，也没有预载所有中档。区域铁路、河流等补充资料不成为首个地球的前提。R36的镜头响应、可用粗档重投影、隐藏上传、整批发布、旧资源最后退休保留。

预制显示读取失败会返回具体分片错误，进入既有失败、取消和重试路径，不能当作安装成功。历史查询预制文件缺失或条目不完整时，`prepare_source_geometry()` 对缺失项使用原资料计算。未知政治归属的已确认陆地继续保留中性色。

## 4. 巨大旗帜构图：确认了什么

旧 `GlobeProjection.source_reference()` 为一个历史feature准备统一 `uv_bounds`，另用其中面积最大的组件产生 `flag_bounds`。运行时先将所有三角形映射到统一框，Shader再按这个最大组件框换算。因此，最终相当于把**同一历史feature的所有分离组件都套进最大组件的构图坐标**。

远离主组件的区域可以得到远超0到1的UV，最终在片元采样时被clamp到旗图边缘。它可能呈现单条旗边颜色、过大的条纹或拉伸。现有 `flag_visuals.json` 还保留旧构图空间中的裁图参数；例如奥斯曼旗的scale为 `[3.0,6.5]`，offset为 `[0.33,2.45]`。把它们继续叠加到已经归一化的新组件UV，会再次将大部分采样推到图像之外。

原文件检查还表明：`gw_200`有28个多边形组件，`gw_220`有6个，`gw_365`有146个。`gw_365`原始坐标横跨-180到180度，但这个原始包围范围**不能直接当作展开后的实际UV宽度**。已有经度展开规则仍须参与处理。

一个明确例子是法国：主陆地组件东端约7.7076度，科西嘉组件约8.5758至9.5526度。用主陆地旗框计算科西嘉的UV，会超出旗图右缘并被截为边缘颜色。R37按科西嘉自己的原多边形组件构图；使用的是统一规则，没有法国专用分支。

不能概括为“每个殖民帝国都使用一张全球矩形”。CShapes也有分开的历史领土记录。本轮保持这些记录及其正式身份，没有把殖民地创建成独立主权国家。

## 5. 本轮实际修复的UV规则

[LocalSpatialLod._component_frame()](D:/programs/WWO/wwo/scripts/presentation/map/local_spatial_lod.gd) 按原历史多边形组件匹配政治源三角形：

- 使用展开后的原外环、内孔和包围范围，检查源三角形中心所在组件。
- 经度换周按该组件进行，同一三角形的角点使用共同换周偏移。
- 所有物理分片、粗中LOD、WORLD和REGION内属于这个组件的碎片，共用同一个地理构图框。不会每15×10度重启一面旗。
- 数值边缘无法匹配时保留原最大组件框，不猜邻国、不移动源顶点。
- 既有阿拉伯半岛显示地区继续使用其明确的 `flag_frame`。

新批次注明 `component_uv`。`LocalSpatialLayer.update()` 对这种批次使用单位flag_bounds和完整图片坐标，不再套用旧最大组件裁图参数。原PNG、历史旗帜选择、色调和光照未改。没有新增国家专用Shader或坐标偏移。

各组件UV可以写在同一国家批次的不同面上；没有因为岛屿增加而为每个岛单独创建材质或Mesh。

本轮没有更改 `VERTEX_ID`、六顶点/双裁切扇面、索引顺序、面纹理宽度、Shader投影和地平线裁切。编码仍调用原函数，WORLD/REGION仍消费同一套球面源点。

## 6. 矩形是否全部查明

**没有。** 本轮确认并修正的是上述构图空间复用和重复换算。UV只决定怎样采样旗图，不决定哪里存在陆地。不能把这项修复说成已经证明所有悬空矩形、弧形都是UV造成的。

没有新的直接证据证明原 `.ink.geom` 中某一份文件包含越过合法政治范围的错误三角形；本轮未据此重画或重制这些分区。离线显示包从其现有三角形生成，不把分片矩形或UV框变成政治多边形。

实际GPU输出是否仍有索引、投影、材质或交接异常，仍待用户查看R37画面。高纬和巨大连续领土仍有球面投影形变；并非所有长条图案都能靠分离组件规则消除。本轮没有游戏运行或GPU帧证据，不能宣布截图问题全部消失。

## 7. 菜单、正式世界与动态主权

菜单 `formal_world_menu.gd` 仍将原Renderer和Controller转交正式场景。`FormalWorldApplication._install_world()` 仍复用已有HistoricalLoader；已有对象不需要另造第二颗地球。

[LocalSpatialLayer.set_political_cells()](D:/programs/WWO/wwo/scripts/presentation/map/local_spatial_layer.gd) 现在比较真正改变主权的显示单元及其几何。只有行政/控制元信息变化、但有效主权几何不变时，不再取消线程、丢掉暂存、重切整组相交陆地。正在安装的主权补丁不会因此被提前标记为已经显示；已安装状态仍等待原提交。

真正发生主权变化时，受影响源分片仍读取原 `.ink.geom`，沿既有 `_political_pieces()` 做局部显示切分；其他预制分片和海岸复用。新主权的资料、控制关系、拾取和边界仍读取正式状态。预制1900年显示不覆盖世界事实，也没有冻结日期或主权更新。

`install_political_content()` 在物理范围已有政治显示时，只准备实际补充内容，不因后续铁路、河流资料又重上传所有政治陆地。替换这些补充内容时，不清空已有正确陆地。仅补充资料的请求也不再解压无关的政治显示包。

原CShapes拼接物理大陆方案继续退役。原始政治、行政身份和LandTopology未修改。

## 8. 数据大小、常驻与GPU成本

制作结果如下。这是**全部离线文件合计**，不是一次菜单实际加载量：

| 显示档 | 文件 | 面 | 批次 | 压缩字节 |
|---|---:|---:|---:|---:|
| coarse | 24 | 229,706 | 455 | 19,937,572 |
| medium | 432 | 406,230 | 1,381 | 37,962,883 |
| 合计 | 456 | 635,936 | 1,836 | 57,900,455 |

历史查询预制文件为569,174字节。上述二进制衍生文件共58,469,629字节；JSON清单和索引另计。实际最终制作结果以 [political_display_r37.json](D:/programs/WWO/wwo/data/strategic/political_display_r37.json) 为准。

显示包复用原456个物理分片ID，不复制历史资料库。文件带有来源路径、制作方式和许可证说明。Natural Earth是现代概化物理参考，不是1900年精确海岸；CShapes衍生许可沿原记录，仍用于本机内部预览。

没有新增全局几何缓存、相机、SubViewport或第二套图层管理器。只读当前需求的包。上传后，原暂存数组按已有流程释放；Content不额外保留一份已无用途的物理绘制三角形。历史查询预制的组件边界只存一次，读取时重接引用列表，避免序列化成两份完整边界数组。

GPU Mesh、ImageTexture和CanvasItem仍按当前有效包创建。批次仍有原面数上限、2000微秒批间预算和退出释放。单批GPU创建可能超出该预算，实际耗时没有测量。本轮没有宣称减少GPU总批次数。海岸按源分片预制会保留分片尾批次，可能比跨分片合批多一些CanvasItem；实际驱动负担待确认。

仍有成本未移走：原始历史身份和资料准入、所需物理 `.geom` 的读取解码和验证、旗图资源加载、当前边界/行政显示准备、原生包解压与GPU上传。不能承诺把约10秒缩短到某个数值。

## 9. 文件清单

修改：

- `scripts/content/strategic_spatial_loader.gd`：识别预制包；现有读取、借用和取消路径；不保留无用物理显示数组。
- `scripts/presentation/map/local_spatial_lod.gd`：原生显示包读取；历史组件UV；真实主权变化时局部回到原切分路径。
- `scripts/presentation/map/local_spatial_layer.gd`：组件坐标材质；排除未改变主权的重复准备；补充资料不重建陆地。
- `scripts/presentation/map/globe_renderer.gd`：读取预制历史查询；传组件框；允许已有编译包直接准备初始政治地球。
- `tools/map/build_geographic_foundation.py`：已有制作入口增加原生显示编译模式。
- `data/strategic/index.json`：分片显示资产描述和制作元信息。
- `project.godot`：R37标签、`wwo-r37-internal`、序号37。
- `export_presets.cfg`：Windows预设包含`.display`；仅内部预览输出路径改为R37。没有导出或覆盖正式Release。

新增：

- `tools/map/compile_political_display.gd`及引擎生成的`.gd.uid`：上述制作入口的原生编码辅助文件及脚本标识。
- `data/strategic/physical_*.display`：456份，逐项文件名、长度、LOD、面及批次数见正式清单。
- `data/strategic/historical_reference_1900.display`：一份固定历史查询/边界衍生文件。
- `data/strategic/political_display_r37.json`：来源、制作方法及逐项资产说明。
- 本报告。

没有删除正式文件或清理构建。R36、R35、R34、R33、R28、R24和正式Release保留。没有R19/R30删除尝试、Git操作或整体回退。没有发现需要覆盖其他工作线的同文件冲突；不据此声称其他任务已经停止。

海洋、极地、太阳、银河、R29林地/DEM、古迹和城市、HUD、主菜单美术和黄铜半球仪未改。经济、人口、人物、组织、军事及时间结算未改。存档格式未改，不读取或修改真实五槽；新存档构建来源由R37配置提供。

## 10. 唯一预览及尚待确认

目标：

`D:/programs/WWO/wwo/builds/preview_2026-10-18_political_globe_r37/WWO_1900_Political_Globe_Rendering_Recovery_R37_Preview.exe`

沿用 Windows Desktop Internal Landmark Preview，Windows x86-64、嵌入PCK。最终正常导出结果补记在下方。

仍需用户实机确认：初始政治地球出现时间；英国、法国、俄国及海外分离地区的旗帜构图；剩余矩形和弧形；WORLD/REGION/LOCAL交接；缩放、旋转、静止和普通日期推进时的完整性；实际主线程停顿与资源负担。

未启动预览，未运行回归、性能采样、哈希核验、CI、安全审计或新增诊断服务。完成后停止，不自动进入下一轮。

### 最终正常导出记录

唯一目标导出退出码为 **0**。EXE长度为 **405,455,400字节**。正常导出日志未出现SCRIPT ERROR、Parse Error或ERROR；保留原`0.001a`的Windows版本号警告。日志包含新物理分片显示包和历史查询预制文件的打包记录。

交付目录附原内部预览及来源、许可旁文件。没有覆盖R36、其他回退或正式Release。源码构建身份为`wwo-r37-internal`，存档格式未改。

以上确认制作和导出完成，不代表实机画面、加载速度或资源负担已验收。
