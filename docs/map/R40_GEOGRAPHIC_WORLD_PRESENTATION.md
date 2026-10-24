# WWO R40 — Geographic World Presentation and Layer Separation

日期：2026-10-18。基线：本机 R39。引擎：Godot 4.6.3 Compatibility。

本轮交付进入现有正式地图路径的原创城市模块、林地参考实例、DSM等高线和地理模式。不是完整巴黎、伦敦、阿尔卑斯或吉萨复原。R39相机、全球coarse与区域medium的管理继续使用。没有启动游戏；最终画面与运行负担待用户查看。

## 1. 已经接入的内容

| 范围 | R40实际改变 | 位置与事实边界 |
|---|---|---|
| WORLD | 新地理模式关闭旗帜和政治/经济墨层，使用同一物理面；提高已有ETOPO双光源地貌明暗权重 | 不新增海岸、高程或地态；海洋、极地、太阳和银河原实现保留 |
| REGION | 同一地理模式显示已有地势、海岸、水系、湖泊和地点；7个已准入交通点改用可分辨的车站/桥梁符号 | 符号是屏幕图例，不是桥面、轨道或城市建成区；坐标仍是原现代代表定位，存在约100—250米不确定性 |
| 巴黎 | 原18件布局使用原创折线屋顶、老虎窗、檐口、窗框、门廊、仓储与锯齿屋顶厂房形制 | 16件民用模块含4件转角变体，加1公共建筑、1厂房。仍是Gros-Caillou概念街区，不是18个实测1900建筑 |
| 伦敦 | 原Westminster的16件布局使用联排砖屋、山墙屋顶、烟囱、门窗和公共建筑；Millbank原4件采用仓库与河岸平台新构件 | Westminster含15组联排模块和1公共建筑；Millbank为南部原3仓库、1平台。没有向Victoria Tower Gardens北部扩建 |
| 采尔马特 | 在原swissALTI3D坡面与R29现代OSM林地遮罩内加入原创树木MultiMesh，原遮罩着色继续保留 | 65米显示采样，最多96株；按当前源几何与同一栅格条件离线计算有45个候选。不是1900林地、树种或密度调查，不提供木材产量或军事隐蔽值 |
| 吉萨 | 原西侧Copernicus DSM加入10米高程等值线、暖色制图地表；原高度与坡面保留 | 等值线按原DEM三角形逐边线性求交，未制造沙丘、岩块、采石场或矿坑。金字塔原模型、坐标、比例及平面基座不变，基座仍在该DSM之外 |

这些内容的入口仍是 `GlobeRenderer._sync_landmark_display()` → `RegionView.update_landmarks()`。建筑包已改为当前布局的正式模型路径，不是仅放进assets。树木与等高线进入现有LOCAL地形准备及显示提交，没有独立展示场景。

## 2. 地理、政治、行政与领域输入

R39的物理形状已由Natural Earth独立决定。R40没有再造物理地球。此前缺少的是可直接选择的地理用途，以及“非政治模式都等于经济模式”的若干分支。

| 内容 | 本轮核对与修改 |
|---|---|
| 地理模式 | `GlobeController.map_mode`加入`geographic`；现有底部地图菜单新增地理入口。物理面沿用已安装的同一coarse/medium，`flag_weight`和`political_weight`为0，不换Mesh，不改变国家事实 |
| 真实地势 | `MapScaleStyle.relief_weight()`在地理模式使用0.70—0.92的已有高程明暗权重。只改变制图对比，不改ETOPO高度或局部高度，也不生成森林/雪线 |
| LOCAL地面 | `_local_ground_style()`在地理模式直接返回零墨层权重，提前退出国家/经济借色路径。吉萨调色板在独立的`surface_presentation`中声明为打印色，不从文件路径或海拔判定荒漠 |
| 经济观察 | `FormalWorldApplication._refresh_economic_map()`只在满足率、短缺模式工作；`PoliticalLayer.color()`对地理模式不读取经济记录。原两个经济指标、未知值处理和正式结算不改 |
| 政治 | 切回政治模式恢复同一物理分区上的国旗与当前政治输入。R37预制显示、R39组件UV与国家边界继续使用 |
| 行政 | 新增现有地图菜单内的历史行政线开关，默认开启；政治与地理用途均可显示和查询。保留原正式世界以本国及明确所选行政区为主的有界需求，不称全球完整行政覆盖。显示开关会立即使行政显示更新，不必再动一次相机。没有用默认隐藏掩盖错位 |
| 主权/控制 | 原动态显示继续读取既有正式状态。显示开关、建筑和树木不调用正式主权或控制修改方法；实际控制不变成法理主权 |
| 产出/军事 | 没有新增完成模式。产出仍缺统一的实际结算产品、数量、单位、时间段和有效空间ID；军事仍需正式地图消费者、对象位置/行动/权限及领域解释。已有MilitaryState/Service和空间适配不是完整地图已实现的证明 |

现有共享引用仍是经纬度、place/catalog ID、territory_unit、administrative_region、runtime polity、market/site与军事实体ID。模型不创建这些身份，地理显示不反向决定人口、企业、矿产、产量、通行或补给能力。

普通地图用途切换只更新材质、描边和对应行政需求；不重新解码Natural Earth、DEM或固定政治面。首次准入LOCAL仍允许读取相应内容，不把可选模型缺失当作全球底图失败。

## 3. 历史行政显示纠偏

### 确认的问题

法国87个一级行政区没有内部线衍生字段，旧Renderer会逐区画完整外环。共边可重复描画，行政总外缘又与国家线不同源。德国177件已接入几何已有部分父级外缘处理，但选中后改用`display_outline_lines`会恢复完整外环；不同层级的重合段也未全部去除。

德国SVG配准与CShapes的差异仍在。普鲁士莱茵省、威斯特法伦、阿尔萨斯—洛林及各邦不是同一份精确测绘。法国为TRF-GIS年度Lambert-93资料；德国总图和南部附图有不同年份、无原生地理CRS，依靠既有控制点配准。比利时没有本轮可用的完整历史行政GIS，不能宣称已修好其全国内部行政线。德比、法比接壤显示首先涉及德国/法国行政外缘与国家线的来源差异。

### 实际处理

新增离线工具 `tools/map/build_administrative_display_r40.py`：

1. 法国从现有detail多边形提取边界，精确扣除该行政目录总外缘，保留内部线。
2. 德国从现有已处理的`display_lines`继续制作，不把SVG原始外环重新放回来。部分原多边形经舍入并非有效面，本工具不修补原面，直接沿用已有合法显示线。
3. 两者均与现有R27 coarse政治墨层的实际国家显示区域求交。该区域已经包含R27绘制优先级、物理陆地与未知缝隙，与R37显示包和R39国家线使用相同依据。不是拿相互重叠的原国家外包框裁切。
4. 按层级及稳定ID处理精确重合段，保留一份描边。没有几公里吸附、90米新缓冲遮罩、顶点移动或跨空白补线。线段求交产生新端点，仅改变显示线。
5. 每个已有行政身份生成coarse/detail两份仅含线段的衍生JSON。法国coarse沿用1500米概化尺度，德国沿用1000米；detail不再额外简化现有detail。
6. 选中法国/德国行政区也使用同一内部线，不再恢复一套不同外缘。选中只改强调样式；原多边形仍可供拾取、查询和正式覆盖对应使用。

衍生文件位于 `data/presentation/admin_display_r40/`：87+177个单位，528份线文件与1份来源清单，总计1,171,509字节。不是第二份行政多边形数据库。

`AdministrativeLoader.department_geometry()`先读取、核对原资料，再按相同ID、LOD和源路径安装这些显示线。原`local_polygons`、原拾取组件、行政面积、成员和原始GIS均未改。R25的源投影线段采样与运行时物理水域裁线保留。Renderer对这些单位不再因选中/取消而切换outline变体，减少相同几何的再次准备。

### 仍不能宣称什么

本轮消除了可确认的重复外缘组合、精确重复段和位于相应政治显示之外的内部描线。不能把SVG配准变成精确1900测绘。内部行政交点仍保留其来源位置；历史图上的真实配准误差、资料年份差异和未知缝隙仍存在。没有重建缺失的比利时行政GIS，没有改变R39的国家边界文件，也没有重划历史政治成员。

当前算法不保证不同来源中彼此接近但不精确重合的行政线全部共边。这类线不能靠随意吸附处理，仍需更可靠史料。选中时不再显示完整行政外环，也意味着国家外侧的选中轮廓由同一国家线承担，不新增另一圈高亮外缘。

## 4. 原创模型、制作方法与安装

新增一个GLB：`assets/settlements/urban_landscape_r40.glb`，979,228字节，16节点、13个共享Mesh、1材质、0图片纹理。8种近档形制和8个远档节点；其中3个远档节点共享同一基础Mesh。

| 近档形制 | 三角面 | 实际使用 |
|---|---:|---|
| paris_mansard | 2,948 | 巴黎12件 |
| paris_corner | 3,044 | 巴黎4件 |
| london_terrace | 1,484 | Westminster10件 |
| london_gabled | 1,488 | Westminster5件 |
| civic_hall | 2,252 | 巴黎、伦敦各1件 |
| sawtooth_workshop | 126 | 巴黎原仓储/工业概念位置1件 |
| warehouse | 392 | Millbank原3件 |
| quay_platform | 276 | Millbank原1件 |

远档复用原R12生成代码的轮廓，44—128面。8米/像素处在两档之间选择；继续按原比例渐退及最大3倍等比放大。外扩的窗台与檐口位于原布局允许的最大地面边框内，沿用原水域和古迹避让范围。没有增加新建筑位置、街道、道路网、码头面积或园林范围。

制作：

```powershell
& 'D:/Tools/blender.exe' --background --factory-startup --python tools/map/build_landscape_modules_r40.py
& 'C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/map/install_landscape_r40.py
```

源文件：`tools/map/model_sources/r40/urban_landscape_r40.blend`；参数与面数：同目录README.json；生成参数在Python源中。该目录由`.gdignore`排除导入，且tools不进入Windows包。GLB导入关闭不需要的切线、自动LOD副本、影子Mesh和动画导入。没有安装云盘V6/V8导入脚本或复杂碰撞体。

`RegionView.SETTLEMENT_MODULE_PATH`和三组布局的model_path都指向新GLB。沿用现有ResourceLoader异步读取，实例化源场景一次后提取命名Mesh，按模块使用MultiMesh。不会每栋建筑复制一套场景或材质。实际参数仍使用米制和glTF Y-up，与原地形贴地函数一致。公共建筑是概念形制，未宣称新增真实议会宫、巴黎市政厅或有经济身份的厂房。

`LocalSpatialLoader._valid_miniature()`的包路径及模块白名单同步更新为R40包和8种形制；否则旧R12白名单会拒绝整个城市LOCAL内容。原96件上限、500米偏移、最大3倍显示、原锚点/日期/来源校验继续保留，没有放开任意模型路径。

## 5. 山地、林地与吉萨高原

`LocalSpatialLod.TerrainPreparation`在原地形工作线程完成已有水/林地遮罩与原高程网格，随后才准备有界树位和可选等高线。相机移动不重做这些几何。

树位的中心及半径3.5米周边九点必须位于R29遮罩中，并避开有效水面和DEM边缘过渡。树脚采用原DEM三角形插值高度，树体不修改坡面。原生树Mesh为31面、一个不透明顶点色材质；实际大小约13.6—16米，是美术参数，不是测绘树高。没有随机撒向林外、海拔分带、雪线或森林生长。只有在原LOCAL地形强度足够、且比例不大于12米/像素时显示；遮罩地表仍提供较远尺度的连续覆盖参考。

吉萨的等高线逐个原DSM三角形求10米高程平面交线。绝对高度仍来自30.37—104.26米的原57×57样本，未做高度放大。暖色只是显式制图调色板，不声明整片DSM为沙漠或裸岩。原模型的三座金字塔、Petrie相对布局、原锚点和尺寸不动。两者有空间间隔，未用伪造地形连接。今后要连接基座仍需覆盖基座的合法高程资料。

等高线复用现有LOCAL线Mesh和材质，不增加全屏后处理、阴影灯或大纹理。LOCAL“已有3D河线”标志排除只画等高线的情形，避免把吉萨等高线误当成已安装河流而隐藏原水文中心线。

## 6. 准入、复用与释放

| 尺度/状态 | 实际行为 |
|---|---|
| WORLD | 原R39完整全球coarse。只更新合法物理/政治材质与投影，不实例化城市或树木 |
| REGION | 原按需medium、ETOPO窗口、有限地点及交通图例。未把7个交通点扩为车站GLB或未经定位的桥梁几何 |
| LOCAL | 原资料准入、有限三维裁剪视口、真实DEM及模型异步路径；每个模块共享Mesh与材质，林地只有一个MultiMesh |
| 准备中 | 原区域地图、地点符号继续显示；模型完成后原prepare_landmarks返回更新，进入既有显示提交，不需新的鼠标事件 |
| 相机变化 | 更新既有变换与必要LOD选择，不在滚轮中同步读取GLB，不重新制作静态建筑Mesh或林地实例 |
| 离开范围 | 原建筑/地标清理释放；树木MultiMesh在原surface释放函数一并退出，CPU树位数组安装后清空。没有全世界城市常驻实例 |
| 静止 | 沿用R39按需视口帧和停止_process条件；没有永久运行的环境动画或新监控服务 |

新增CPU/GPU内容确有成本：城市包的近档比旧体块多面；当前林地增加一个MultiMesh和一个31面Mesh；吉萨增加真实等高线的线顶点。没有测量实际内存或帧耗时，不能声称“没有影响”。全球基础没有新增一份几何或SubViewport。没有常驻全库medium或LOCAL模型。

## 7. 做了、储备了、没有做

| 类别 | 内容 |
|---|---|
| 已接入现有游戏路径 | 地理模式；默认可开启的历史行政线；法德内部显示衍生线；7个交通图例；38件原城市布局的模型升级；有界现代林地树木；吉萨原DSM等高线及打印色 |
| 已制作但未安装 | 没有把未安装模型计为本轮成果。本轮8种城市模块都有实际消费者 |
| 仍未制作 | 完整历史巴黎/伦敦建成区、精确河岸、完整议会宫、基座外推地形、比利时历史行政GIS、全球历史土地覆盖、矿井/采石场/农庄位置及其经济设施、完整军事和实际产出地图 |
| 未引入 | 云盘沙盘、无定位地貌、未确认再分发许可模型、R30天气/木屋/码头、全新森林覆盖范围 |

已有三件内部预览古迹仍按原许可隔离；没有借本轮扩大公开商业分发范围。新城市、树木为原创代码几何，许可和来源说明在 `assets/settlements/R40_SOURCE_AND_USAGE.md`。行政显示线另继承TRF-GIS的CC BY 4.0、德国处理图形的CC BY-SA 3.0、CShapes 2.0的CC BY-NC-SA 4.0及Natural Earth公共领域来源；不混称为CC0模型。原Baedeker、Historic England及Millbank历史研究引用继续保留在各LOCAL事实中，现代资料与1900史实分别说明。

## 8. 修改、新增文件与预览

修改18个正式文件：

- `scripts/presentation/map/globe_controller.gd`：地图用途与行政显示开关；R39相机方法不改。
- `scripts/presentation/map/globe_renderer.gd`：地理墨层、行政需求、交通图例及稳定内部线变体。
- `scripts/presentation/map/map_scale_style.gd`：已有高程明暗的地理模式权重。
- `scripts/presentation/map/political_layer.gd`：地理用途不读经济颜色。
- `scripts/presentation/map/local_spatial_lod.gd`：遮罩内树位、真实DSM等高线。
- `scripts/presentation/map/region_view.gd`：新建筑包、两档选择、林地MultiMesh、显式调色板及释放。
- `scripts/content/administrative_loader.gd`：按源ID/LOD读取显示衍生线。
- `scripts/content/local_spatial_loader.gd`：独立传递显示参数，同步有限模型准入白名单。
- `scripts/presentation/ui/main_shell.gd`：沿用原地图菜单增加地理及行政显示入口，不改半球仪函数。
- `scripts/formal/formal_world_application.gd`：仅限制经济观察刷新用途，不改领域结算。
- `shaders/presentation/map/local_terrain.gdshader`：显式打印色参数，不按路径分类。
- `data/local/paris_northern_france_1900.json`、`london_westminster_1900.json`：原布局模型引用、形制变体、交通图例与来源提示。
- `data/local/zermatt_west_physical_reference.json`、`giza_pyramids_1900.json`：独立景观参数和来源提示。
- `docs/map/MAP_SEMANTIC_CONTRACT_R26.md`：更新现有用途状态。
- `project.godot`、`export_presets.cfg`：R40构建身份与独立内部预览路径。

新增：

- `tools/map/build_landscape_modules_r40.py`、`install_landscape_r40.py`、`build_administrative_display_r40.py`。
- `tools/map/model_sources/.gdignore`、`tools/map/model_sources/r40/urban_landscape_r40.blend`、同目录`README.json`。
- `assets/settlements/urban_landscape_r40.glb`、其正常`.import`和`R40_SOURCE_AND_USAGE.md`。
- `data/presentation/admin_display_r40/`中的528份显示线与README.json。具体单位列在README.json，路径由原单位ID和LOD确定。
- 本报告。

没有删除正式文件或清理构建。原始GIS、DEM/DSM、旧模型、行政身份与正式成员保留。正式经济/人口/人物/组织/军事、GameClock、SimulationStep、存档格式和用户真实五槽未改。半球仪、海洋极地、太阳、银河、油画、时钟、日志和人物HUD的美术不改。

构建身份：`wwo-r40-internal`，顺序40。

唯一预览：

`D:\programs\WWO\wwo\builds\preview_2026-10-18_geographic_world_r40\WWO_1900_Geographic_World_Presentation_R40_Preview.exe`

正常资源导入及Windows导出完成，退出码0。最终EXE为404,249,000字节，导出日志未出现脚本解析错误。原Windows数字版本字段`0.001a`仍产生格式警告；R40实际构建身份来自上述项目配置，不由EXE名称推定。目录只交付一份R40 EXE。R39、R38及正式发布保持原状。未处理R19/R30。

用户仍需查看：地理/政治/经济往返时物理位置是否一致；法德比接壤处内部线是否仍有来源错位；巴黎、伦敦在8米/像素内外的建筑形制；采尔马特树木贴坡；吉萨等高线与原平面基座；新模型完成后的刷新；LOCAL退出及球面旋转。没有运行证据证明所有旧矩形、行政误差或风扇负担均已消失。
