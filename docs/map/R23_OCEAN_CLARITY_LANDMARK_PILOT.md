# WWO R23 — Ocean Clarity and Landmark Pilot

日期：2026-10-16。基线：本机 R22。Godot 4.6.3 Compatibility。

本轮调整单层海洋与固定太阳，接入三件内部古迹示意，并整理过期构建。不运行自动测试、回归、跑分、CPU/GPU/FPS/内存采样、哈希核验、安全审计或 CI。不新增此类脚本，不操作 Git。正常资源导入与最终导出不作为性能验收。

## 1. 海洋为何显得厚重

R22 源码将低频宏观色图以 22% 混入蓝灰底色，受光侧还采样微法线及粗糙度。太阳反射指数约 88，夜面补光为 `(0.43,0.49,0.56)`，昼面额外增亮上限为 13%。这些参数使色图的宽尺度明暗更明显，镜面范围较宽，同时日夜对比较弱。它们与用户所见的浑浊、散光和灰暗表现一致；没有测量证明某一张图是唯一原因。

R20 说明记录了旧透明球壳和黄铜宽边的退出。可读的 R19—R22 报告没有提供可直接恢复的早期精确 Alpha 参数。本轮不从旧 EXE 推断旧材质，也不恢复旧持续渲染。透明背景参与球缘混合可以让边缘轻，但真正透明也会暴露星空或产生错误层次。因此选择原单层不透明表面内的颜色与边缘明暗调整。

## 2. 实际视觉修改

`CHART_SUN_VIEW` 保持 R22 的 `(0.17956061,0.90777866,0.37907239)`。仍是独立于地球转动的观察空间制图主光，方向在画面上方偏右。国家选择和正式 WORLD 继续共享 Renderer/Shader，不绑定时钟或星轨 UI。

| 项目 | R22 | R23 |
|---|---|---|
| 宏观色图混合 | 22% | 4% |
| 海洋基础色 | 原 `water` | 原色与 `(0.10,0.24,0.29)` 混合 65%，再叠加 4% 色图 |
| 微法线 | 原斜率的约 10% | 停用，不绑定、不采样 |
| 粗糙度图 | 小幅改变高光指数 | 停用，不绑定、不采样 |
| 镜面指数 | 约 88，随粗糙度变化 | 固定 256 |
| 反射颜色系数 | `(0.24,0.25,0.23)` | `(0.38,0.41,0.39)`，仍乘正向太阳入射 |
| 夜面补光 | `(0.43,0.49,0.56)` | `(0.30,0.36,0.44)` |
| 昼面 | 1.0，额外上限 13% | 1.02，按法线入射额外上限 24% |
| 日夜平滑区间 | −0.12 到 0.18 | −0.16 到 0.24 |
| 球缘 | 四次方冷色边缘项 | 五次方窄边，强度再受太阳入射控制 |

昼面增亮和夜面降低均取决于球面法线。不是全图统一曝光。过渡区间仍平滑；没有硬切黑夜。镜面采用原外部太阳、球面法线和正交观察半向量，但范围收窄，峰值稍提高。去掉法线/粗糙度变化，避免用纹理破坏集中反射。新效果仍待玩家查看。

未设置新的 ALPHA，没有透射、背景屏幕采样、透明球壳或重复几何。三维海洋保持不透明；政治面仍由原前半球裁切规则绘制，物理补陆/补水及边线保留原顺序。因此本轮没有新增背面大陆、背景星空透过海面的通道，也没有增加另一条海岸轮廓。原有海岸来源差异不因此自动解决。

三张原 PNG、导入配置及授权原文均保留。只有宏观色图继续绑定；WORLD 海洋函数每像素新增纹理采样由最多三次变为一次。PNG 仍在资源目录/内部包中不等于它们都驻留 GPU。没有实测资源下降比例。

## 3. 三件古迹：来源、位置与历史边界

只按 R15 已有 ID 下载三件，没有重扫 120 件。三件均为 `AncientRuinsLowPolyGenerator_v1` 生成的 glTF 2.0：各一场景、一节点、一 Mesh、六个原始材质、无纹理或外部图片、没有 copyright 字段。

| 古迹 | Drive 原文件 / ID | 经度、纬度 | 1900 国家与行政参考 |
|---|---|---|---|
| 加尔桥 Pont du Gard | 24_Pont_du_Gard_Aqueduct_France.glb / 1AIjHDRaZehIIeNfhOlUdWUzXL2NwE_IZ | 4.535278, 43.947222 | 法兰西第三共和国，Gard 加尔省；复用 `country_fra` |
| 巨石阵 Stonehenge | 03_Stonehenge_UK.glb / 1wF5r8AdHPa22TC1CVzIneRzlYidR4Apf | −1.826277, 51.178905 | 大不列颠及爱尔兰联合王国，英格兰 Wiltshire 历史郡；复用 `british_isles_1900` |
| 罗马斗兽场 Colosseum | 01_Colosseum_Rome.glb / 1o8J4o0i8HeWK5klPoMLT8x8bSnMalzSh | 12.4922, 41.8902 | 意大利王国，罗马省罗马；复用 `kingdom_of_italy` |

国家关联取项目现有 1900 身份，不以现代国名创建政体。行政地名为地点说明，没有给遗址新写正式行政成员、主权、控制或 LandTopology 单元。模型是显示引用，不创建正式世界城市、人口、市场或组织。

加尔桥的现代固定遗址坐标采用 [UNESCO 344](https://whc.unesco.org/en/list/344/) 的角度位置，转换后保留六位小数。[管理机构历史说明](https://pontdugard.fr/en/discover/history) 记载 1855—1859 年修复。这早于 1900；本模型的拱、桥长和附属构件仍未逐件对应 1900 状态。

巨石阵坐标采用 [Historic England 遗址记录](https://historicengland.org.uk/listing/heritage-gateway/results/record/5079bd59-b1b8-4237-b20f-3bc281dbc435/MWI12515)。[English Heritage 修复史](https://www.english-heritage.org.uk/visit/places/stonehenge/history-and-stories/history/conservation/) 及既有 R15 资料表明，1901 年和后来的修复改变了石块状态。模型没有按 1900 倒伏/倾斜状态复原，因此只作为抽象地标。约 7 米高度参考来自 [English Heritage 的石料说明](https://www.english-heritage.org.uk/about/search-news/research-reveals-origin-of-stonehenge-stones/)，不是本轮测量。

斗兽场存在年代与形制变化参考 [Parco archeologico del Colosseo](https://colosseo.it/en/area/the-colosseum/)；19 世纪支撑修复与现代地面/通道处理参考其[南侧回廊说明](https://colosseo.it/en/southern-ambulatories/)。近似中心坐标另取 [位置说明](https://www.thecolosseum.org/visit/)，与管理机构提供的入口位置区分，不用入口点冒充建筑中心。参考高约 48 米、长约 189 米，非 1900 复测。模型不是准确的 1900 残损复原。

坐标都是固定遗址的现代位置参考，不宣称米级历史测绘。三件模型的当代修复构件均未逐个核定；不把整齐的立石、拱券或完整墙段宣称为 1900 事实。朝向也没有测绘核定。

## 4. 权利及正式发布隔离

用户本次明确允许本机内部预览。Drive 读取成功，没有遇到禁止下载/处理的返回；这不等于取得商业或公开分发许可。三件作者、copyright 和再分发权仍待确认。数据和资料卡首先提示“仅本机内部预览；版权及再分发许可待确认，非1900精确复原”。

资源位于 `assets/landmarks/internal_preview_r23/`；显示资料位于 `data/local/internal_preview_r23/`。原 Windows Desktop、Linux、macOS 导出配置排除这两个目录。新增单一内部 Windows 预览配置，具有 `internal_landmark_preview` 特性。只有该内部预览和本地编辑器允许这些源与定位入口。没有导出、覆盖或验证正式 Release；排除配置不写成已完成正式 Release 运行验收。

没有 Git 提交、推送、公开上传或商业授权声明。三件原 GLB 不改写；来源声明保存在同目录 `INTERNAL_USE_ONLY.txt`。R15 原目录记录不改成“版权已确认”。

## 5. 实际接入与资源结构

入口：进入正式世界后，在右侧日志抽屉打开“百科 / 帮助 → 地图图层”，点击三件“内部示意”定位按钮。它们只定位地图并选择显示引用，不改变玩家所在地或身份。定位到约 3 米/像素，明确调用原 `RegionCamera.enter_local`，随后沿原内容完成与 LOCAL 交接处理。普通发布不显示这些按钮。

路径：`LocalSpatialLoader` 有界源 → 原 source/evidence 解析 → `LocalSpatialLayer` 地点和 REGION 符号 → `RegionView` 异步 PackedScene → 同一个 LOCAL 裁剪视口、相机、灯光与模型拾取边界。WORLD 不实例化 GLB；REGION 使用原测绘圆形符号。

原无 DEM 路径存在明确问题：模型仍在异步加载、实例尚为空且没有地表请求时，`update_landmarks` 会调用 `release_landmarks`，清掉想要的模型路径。稍后完成的 GLB 会被当成无需求丢弃。现在只有模型需求和地表需求都为空才释放；无效旧纹理仍按原规则隐藏。已有无 DEM 的地标能力因此能完成加载，不新建第二套运行时。

三件都没有本站精细 DEM。以原制图平面作为相对基座；周围仍是已有 ETOPO/行政/水系显示。没有造坡、河宽、岸线或土地覆盖。原模型附带的草地、岩壁、河水、铺装底座在实例安装时排除。只保留明确的古迹表面和其必要构件；不把演示底座当作真实地形。

原 GLB 单位是示意单位，并非米。本轮在已有地标实例下做一次明确的单位换算及基底平移：按参考高度统一缩放，最低保留顶点贴到制图平面，XZ 中心对准遗址锚点。不重新建模。横向压缩比例仍保留，属于示意，不能当成等比例历史测量模型。

| 模型 | 原 GLB 字节 | 原三角形 → 实际保留表面三角形 | Mesh / 原材质 → 保留材质 | 纹理 | 换算后的示意宽×深×高（米） |
|---|---:|---|---|---:|---|
| 加尔桥 | 60652 | 1080 → 1020 | 1 / 6 → 3 | 0 | 101.02 × 12.45 × 48.77 |
| 巨石阵 | 44792 | 876 → 636 | 1 / 6 → 4 | 0 | 17.79 × 17.34 × 7.00 |
| 斗兽场 | 75804 | 2004 → 1892 | 1 / 6 → 4 | 0 | 146.37 × 114.53 × 48.00 |

统计直接读取原 GLB 的 accessor/index 与材质结构；“保留”数量按实际安装所选 primitive 计算，不是性能测量。模型中没有动画、灯或碰撞。导入关闭无用的切线生成、额外 LOD、阴影 Mesh、烘焙和动画。原始场景仍可能暂留在原两件缓存中，因此不能把删除显示表面等同于全部原材质立即卸载。

三件的 REGION 符号上限为 1600 米/像素。按已有 `model_limit_mpp`，实际进入三维均为 4 米/像素，已有实例退出迟滞为 5.4 米/像素。最低 LOCAL 为 2 米/像素；沿用原最高 3 倍微缩显示放大和 150 像素宽度约束，不给巨石阵额外放大。巨石阵本身较小，细节可能仍有限。

每处只允许对应的一件模型实例：当前需求字典以 ID 去重；三个相距很远的 15 千米源不会在同一近景同时安装。当前视图不变不重算姿态/不重新实例化。离开有效尺度、地理源或视窗后隐藏并 queue_free；最多两件近期 PackedScene 缓存按原规则淘汰。待完成旧请求仍按当前想要路径决定接收或丢弃。

单位/底座适配只在实例首次安装时建立一个原子模型容器与保留表面的 ArrayMesh，原 PackedScene 不原地修改；不是每次 WORLD 绘制做几何转换。沿用原单一 LOCAL 光源、相机与按需目标。没有逐模型视口、实时灯光、碰撞生成、全世界 GLB 枚举或通用资产管理器。

## 6. 修改、新增与保护

修改 9 个既有文件：

- `shaders/presentation/map/solar_globe.gdshaderinc`
- `shaders/presentation/map/ocean_globe.gdshaderinc`
- `scripts/presentation/map/globe_renderer.gd`
- `scripts/presentation/map/region_view.gd`
- `scripts/content/local_spatial_loader.gd`
- `scripts/presentation/ui/world_view.gd`
- `scripts/presentation/ui/main_shell.gd`（仅为内部地图图层的三件定位按钮增加面板高度）
- `scripts/formal/formal_world_application.gd`（仅增加地图定位动作分支）
- `export_presets.cfg`

没有另改领域文件。新增本文、三个内部 GLB 及三个导入配置、内部来源 TXT、三个有来源的地标显示 JSON。没有删除正式源码、原始地理资产或三张海洋 PNG。

保留：R22 外部太阳坐标修复、R20 银河、R18—R21 按需视口与 LOD 退休、历史主权/行政身份、LandTopology、经济/人物/组织/军事模拟、GameClock/SimulationStep、五槽存档、原菜单和 HUD。黄铜机械半球仪的所有文件及联动/点击逻辑未改。未覆盖、还原或提交经济工作线的其他本地修改。

## 7. 唯一预览、清理与待确认

R23 内部预览目标：`D:/programs/WWO/wwo/builds/preview_2026-10-16_ocean_clarity_landmark_r23/WWO_1900_Ocean_Clarity_Landmark_R23_Preview.exe`。

保留 R22 和 `builds/windows/` 三件正式文件。R19 删除曾被自动审批拒绝，原因 `blocked by policy`，本轮不重试、不改权限、不换工具规避。R18 原先有文件夹打开记录；本轮当前窗口列表不再显示旧预览目录，且没有 WWO 运行进程。R18/R20/R21 当前目录只有预览 EXE、来源侧文件和报告副本，报告/原始资源仍在正式目录；在 R23 成功导出后才处理这些被替代的副本。

只检查 builds 内的这些小目录、项目根目录安装包类文件、packaging 及 artifacts/local-artifacts 根目录。没有全项目大扫除。packaging 中只有 `windows/1900.iss`，作为原安装脚本保留；这些有限范围未发现其他待删安装包或临时 PCK。研究目录、Blender 原件、唯一生成脚本、存档和其他工作线构建不动。

使用 Godot 4.6.3 Compatibility 与 `Windows Desktop Internal Landmark Preview` 配置导出。最终导出返回 0；目标是嵌入 PCK 的 Windows x86-64 EXE。仅交付上述一个 R23 文件。未生成安装包，也未覆盖正式 Release。原项目 `0.001a` 版本号格式警告仍存在。

成功导出后实际删除：

| 目录（均位于 builds） | 删除文件数 | 文件长度合计（字节） |
|---|---:|---:|
| `preview_2026-10-15_coast_terrain_simulation_r18` | 12 | 337961318 |
| `preview_2026-10-15_solar_globe_galactic_r20` | 12 | 338141128 |
| `preview_2026-10-15_map_performance_visual_r21` | 12 | 338213282 |
| 合计 | 36 | 1014315728 |

以上是实际删除文件的长度合计，不是磁盘簇占用测量。删除前确认绝对路径位于 builds，目录不是链接；使用原生 Remove-Item，未强制删除。三个目录随后均不存在。未删除任何正式源码或唯一来源资料。

当前保留 `preview_2026-10-15_coast_local_performance_r19`、`preview_2026-10-16_external_sun_ocean_r22`、本轮 R23 和 `builds/windows`。R19 的先前审批障碍仍保留，未再次删除。未发现另有待删安装包；原安装脚本保留。

新源码与模型安装不等于用户确认画质/性能。海洋清澈感、集中高光、暗面可读性、模型形制/比例/朝向、无 DEM 地表协调、缩放与风扇负担仍需查看。没有百分比改善、显存容量或三模型性能合格结论。

## 8. 实际窗口画面与交付状态

最终 EXE 为 339147960 字节。为截图打开过本轮游戏窗口；时间保持在 1900 年 1 月 1 日 00:00。结束时选择不保存并退出，窗口已关闭。没有写五槽存档，没有推进 4× 时间，没有性能采样或自动化测试。

首次有限查看发现内部定位只有 REGION 状态，画面停在圆形地标符号。定位入口补上已有 `enter_local` 调用；表面索引同时显式转换 JSON 数字为整数，避免依赖数组数字类型比较。三件按钮的内部面板增加 50 像素高度。修正后更新同一路径的 R23 EXE，没有保留第二份候选 EXE。

最终窗口已显示加尔桥和斗兽场的三维轮廓。巨石阵在既有微缩上限下仅有较小的石环细节；没有为返图单独放大几何。本站平面周边缺乏精细地表，画面仍显空。模型尺寸压缩、朝向及 1900 修复构件适用性仍未核定。这里只确认显示入口产生了实际画面，不确认真实性、画质验收或性能合格。

本次鼠标点击日志中的原“百科 / 帮助”按钮未打开页面；用 Tab 聚焦该按钮，再按 Enter 可进入。未定位这个既有鼠标输入问题的代码原因，也未扩展修改日志交互。可用上述键盘入口访问本轮三件定位按钮。

实际游戏截图目录：`D:/programs/WWO/wwo/local-artifacts/r23_screenshots/`。所有图片均为原游戏窗口截图，没有生成图或后期拼接。

- [国家选择地球](D:/programs/WWO/wwo/local-artifacts/r23_screenshots/01_country_selection_ocean.jpg)
- [正式 WORLD](D:/programs/WWO/wwo/local-artifacts/r23_screenshots/02_world_ocean.jpg)
- [地球另一角度（首次 R23 查看，光照 Shader 与最终相同）](D:/programs/WWO/wwo/local-artifacts/r23_screenshots/03_world_rotated_external_sun.jpg)
- [加尔桥 LOCAL](D:/programs/WWO/wwo/local-artifacts/r23_screenshots/04_pont_du_gard_local.jpg)
- [巨石阵 LOCAL](D:/programs/WWO/wwo/local-artifacts/r23_screenshots/05_stonehenge_local.jpg)
- [斗兽场 LOCAL](D:/programs/WWO/wwo/local-artifacts/r23_screenshots/06_colosseum_local.jpg)

海洋的最终主观清澈感、暗面可读性、持续缩放迟缓和风扇负担留待用户实机查看。三件 GLB 仍只具本机内部预览授权，作者和公开再分发许可待确认。不能用本 EXE 代替正式 Release。
