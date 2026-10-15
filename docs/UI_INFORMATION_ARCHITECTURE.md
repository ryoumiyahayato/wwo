# 当前正式 UI 与任务状态

更新：2026-10-12。正式入口仍为 `scenes/formal/formal_world_menu.tscn` → `scenes/formal/formal_world_main.tscn`。以下当前壳层为本轮保存的源码，未启动游戏、运行测试、审计、哈希核验、回归、性能探针或导出。后面的日期条目记录此前实现，不表示本轮继续经济工作。

## 当前菜单与选择层

主菜单为开始、加载、存档管理、设置、退出。加载在菜单中使用 WorldBootstrap 与 FormalPersistence 的现有路径准备和读取正式候选；成功后将同一 WorldBuildResult 交给 FormalWorldApplication，接收后移除场景临时引用。失败原因留在菜单中，没有第二套存档或运行容器。存档管理展示既有单槽、保存时间和路径，可以加载、打开目录；多槽、重命名与删除未实现。

开始进入国家与人物选择。背景与正式场景共用 `scenes/presentation/map/globe_renderer.tscn` 和现有 GlobeRenderer，只增加暗色投影遮罩。右侧选择面板展示现有历史国家/政治地域名称、同代旗帜和明确的人物区域。只有 WorldBootstrap 已有的法国巴黎生成身份可以进入新世界；其他地域显示没有可选人物。角色列表、职业和身份筛选未实现。控制者识别旗不称为本地国旗，缺失旗帜不补现代素材。进入世界与返回主菜单固定在面板底部。

预览只使用既有来源与政治身份种子的只读展示快照，不建立世界、个人或经济状态。选择国家、拖动背景和定位不改变正式人物。去掉了主菜单中的开发经济配置、生计试验选择和开局金额说明；其已有领域实现保持原状。

菜单和游戏内设置共用简单音频偏好，保存在 `user://interface_settings.cfg`。主音量控制已有 Master 音轨，BGM 开关只控制已有 BGM 音轨；没有该音轨时明确说明仅保存偏好。显示项仅说明当前跟随窗口尺寸，未提供虚假可点击功能。未添加音频素材或新的设置服务。

## 当前正式地图布局

左上为当前国家/观察视角与历史旗帜，附有资料入口。选择别国只改变观察，未选择政体时读取人物所在地政体。左下为当前人物、正式所在地、已有生计状态以及人物详情和定位入口，不再在摘要堆放现金数值。

右上为日期、继续/暂停、1×/2×/4×与系统菜单。系统菜单可以保存、加载、设置、返回主菜单或退出。返回主菜单和退出的按钮明确说明不自动保存。右下为已有操作反馈、相关记录与通知历史尚未实现的说明；不将世界组织事项自动包装成人物通知。

底部中央为政治、经济满足率、经济短缺模式和球形图层控件。球体是静态二维半透明线圈控件，点击打开既有显示选项；不是新的三维地图运行时。图层菜单保留地名、铁路、正式法国土地、1900 重建行政界、法国土地定位与行政资料，并增加回到现有球形视图的操作。金色土地线与蓝色历史省界继续使用原绘制实现。

地图对象卡仍在左侧，完整资料仍复用 WorldPage；人物、经济和组织页面保留原实现，收在资料导航中。未修改地形、海岸、字体资源、历史数据、世界政治或土地成员。面板、按钮和文字避让使用当前四角、底部中枢及展开区域的实际矩形；窗口最小尺寸仍为 960×640。

Esc 和右键共用返回顺序：设置、系统菜单、模式/图层菜单、导航、详情子层、页面历史、地图对象卡。菜单中的国家/身份弹出列表先关闭，菜单子页再返回主菜单。没有子界面时 Esc 呼出系统菜单，右键保留地图旋转。返回只改变 UI 和观察，不重建世界事实。

## 本轮地图显示修正及限制

源码存在两条能留下星空的路径：FormalWorldApplication 以 `_world != null` 决定地图可见性；GlobeRenderer 以 REGION 相机是否活动切换画布，没有同时等待区域内容完成。初始化又在正式场景 `_ready` 同步进行，错误或准备阶段不能展示完整地图。

本轮明确背景、地图和壳层顺序，共用全屏锚定地图场景并显式激活现有 Camera3D。世界准备从场景就绪回调中延后；菜单准备失败留在菜单内显示原因。正式地图不再因世界为空被隐藏。区域画布实际准备完成后才交接，并请求投影和视口重绘；缩放和恢复可见性继续沿原路径。SubViewport 尺寸由已有 stretch 容器随窗口确定，静止时仍使用 UPDATE_ONCE，没有新增动画或每帧刷新。

没有重现用户画面，不能将以上源码路径断定为该 EXE 黑屏的唯一原因。当前修改没有导出到旧 EXE，实际地球、地图、交接和布局仍未获得运行画面确认。

本轮修改文件：`scenes/formal/formal_world_menu.tscn`、`scenes/formal/formal_world_main.tscn`、`scenes/presentation/map/globe_renderer.tscn`、`scripts/formal/formal_world_menu.gd`、`scripts/formal/formal_world_application.gd`、`scripts/presentation/map/globe_renderer.gd`、`scripts/presentation/map/region_view.gd`、`scripts/presentation/ui/main_shell.gd`、`scripts/presentation/ui/ui_drawing.gd`、`scripts/presentation/ui/interface_settings.gd` 与本文件。没有删除正式土地、历史来源或领域算法。

此前个人/经济改动的调用、状态归属和可能冲突见 [已有移交报告](economy/personal_economy_implementation_handoff.md)。建议交由独立经济工作线决定保留或替换；本轮仅保留原行为和存档依赖，没有拆除耦合实现。

## 正式个人生活第一批

现有 `inventory` 是 FormalWorldEconomySimulation 生成并按日结增减的有限模拟存货；人口、收入锚及覆盖资料继续只读。原状态没有历史零售商、卖方账户或个人出售关系。本批在 FormalWorldEconomyState 中定义现有市场身份的库存保管与出售关系，标记为 `GENERATED_SIMULATION_ASSUMPTION`。它不创建零售公司、巴黎商店、第二份库存或额外商品供给。发生交易的市场才建立零余额收款账户；资金全部来自人物的现有 Ledger 账户。

访问按正式人物所在地的 Population place→statistical unit→market 映射判断。不按浏览国家、名称或距离猜市场。这里只支持所在地所属统计库存池的抽象交易；没有具体零售地址、包装和城市仓库，不能称为本市零售市场或实际配送。

沿用商品 `unit_name_zh` 与当前 `prices`。数量以原单位的千分之一记录，例如吨的 0.001 为一公斤；模型分币数值对应现有模拟货币最小单位，正额不足一最小单位向上取整。这是明确的模拟计价规则，不是历史货币兑换率或零售价格史料。没有第二套个人价格系统。local_service 不转为可持有商品；工业耐用品可持有，目前没有个人消费操作。

FormalLedgerState 保存并执行借贷双方的有限现金变化与付款收据。FormalWorldEconomyState 保存并扣减原市场库存，保留卖方保管关系和原价格。FormalPersonalEconomyState 保存人物持有批次、购入、消费、安排与失败记录；消费按购入来源扣除持有数量。食品、殖民消费品和家庭消耗品类别可消费，不增加饥饿、健康、幸福或生活质量数值。

每日安排使用 GameClock 和 SimulationStep 原时间推进，按到期边界处理。先使用持有量；不足时仅购买差额，按届时库存、价格、可访问市场和现金处理。条件不足记录该次失败并推进至下一日，保留未消费的原持有量，不赊账、不补货、不生成资金。工资仍由原结算执行。仅维护已有安排和实际参与人物，不在时间步扫描历史交易。

新增持有与安排沿 FormalPersistence 的原正式文件保存。personal_economy 嵌套 schema 为 v2，v1 直接读取为空财产、记录和安排。顶层 v15 与现有容器保持。恢复先取得 Ledger 与经济市场事实，再恢复个人财产及商品流转引用；不在页面刷新或读档安装时再购买、消费或发薪。未运行检查、试跑或测量。

## 地图显示路径

### 地图主界面与土地显示（2026-10-11）

正式场景 MainShell 增加 `HUDMargins/HUDLayout`，由既有 Godot MarginContainer 和全屏锚点确定边距。顶部单行、左上所在地与查看对象、左侧工具和资料卡、左下人物概况、右下实际反馈均使用当前窗口边界计算。模式菜单和显示菜单互斥，并替换上下文卡的位置；系统与页面导航不与地图工具同时展开。资料卡可收起、恢复、返回上一地图对象；返回不移动相机。地图对象历史只属于现有 GlobeController，不保存世界事实。

面板统一底色、边框和间距，按钮区分选中、悬停与展开。正文继续使用思源宋体与 EB Garamond；功能按钮保留现有功能字体。世界国名分为主次字号，区域国名上限调整为 24，描边降低不透明度。国名、城市名、土地名避让实际 HUD 和已占用文字区域。没有改变地形精度、阴影、UV、水面动画或常驻重绘。底部仅显示地图层级、尺度和一句来源性质，不再串接所有来源与内部 LOD 状态。

土地入口：左侧“显示选项”→“土地单元 · 巴黎周边”；“定位巴黎周边正式土地”开启叠加并依据现有 LandTopology 范围定位。当前初始数据为 30 块，包含原六块和外围新增 24 块。绘制遍历活动土地，后续分割不受固定数量限制。细边界、悬停和选择高亮读取现有几何；关闭开关停止土地线和拾取。

点击地块后，左侧卡显示生成试点性质、土地 ID、面积、法律主权、当前控制、未确定的行政归属及相邻单元入口。相邻按钮保持地图观察与选中高亮，定位保持选中的土地身份。已有城市标记仍可单独选择。完整资料保留 50 / 25 / 5 km 查询；更近尺度使用已有地点关系。

“Seine / Seine-et-Oise 行政资料”打开当前日期的历史名录，选择条目回到地图侧卡。两省已接入 TRF-GIS 1900 年度重建界线。卡显示层级、首府、资料年份和来源；完整资料分别显示重建图形面积、正式成员面积和未确定的相交土地。成员按钮定位土地，土地详情可返回所属行政区。没有边界的其他名录条目继续显示面积未知。

历史研究仍只取得目录和图集线索。[Apur 目录](https://www.apur.org/sites/default/files/documents/geo-apps/fichiers-attaches/catalogue_donnees_geo_2021.pdf?token=kEwl5G1b)分别列出 1895–1900 与 1933 年 Seine 图集；[Hauts-de-Seine 档案目录](https://applis.hauts-de-seine.fr/adOld/archives.hauts-de-seine.fr/archeologie-patrimoines/patrimoine-culturel/la-cartotheque-historique/principaux-plans-et-cartes-du-xxe-siecle-utiles-en-cartographie-historique/index.html)有 1900 年 Seine-et-Oise 市镇地图线索。未取得可直接导入且能对应当前土地的边界/成员数据，未将后修订图或现代行政面套入 1900 年。

水系请求继续由当前范围、日期和尺度触发。StrategicSpatialLoader 的请求返回是否存在当前范围数据；空范围和读取错误清除旧显示批次。跨日期线和极区的范围相交处理与已有海岸选择使用相同规则。更换分片时只保留实际完成并显示的 LOD 批次，准备完成后替换，过期结果仍由原 generation 取消。首次进入/直接定位无需切换标签。没有增加管理中心或永久轮询。

本轮未启动游戏、测试、采样或视觉验收。窗口实际效果、字体清晰度、FAR/MID 交接和土地点击效果仍由后续实际打开游戏确认。经济、人物、组织及军事算法未修改。

本轮修改的正式文件：

- 场景：[formal_world_main.tscn](../scenes/formal/formal_world_main.tscn)。
- 入口与只读展示：[formal_world_application.gd](../scripts/formal/formal_world_application.gd)、[formal_world_presenter.gd](../scripts/presentation/formal_world_presenter.gd)。
- 主界面与对象卡：[main_shell.gd](../scripts/presentation/ui/main_shell.gd)、[world_view.gd](../scripts/presentation/ui/world_view.gd)。
- 地图与文字：[globe_renderer.gd](../scripts/presentation/map/globe_renderer.gd)、[globe_controller.gd](../scripts/presentation/map/globe_controller.gd)、[region_view.gd](../scripts/presentation/map/region_view.gd)、[labels.gd](../scripts/presentation/map/labels.gd)。
- 加载与显示批次：[strategic_spatial_loader.gd](../scripts/content/strategic_spatial_loader.gd)、[local_spatial_layer.gd](../scripts/presentation/map/local_spatial_layer.gd)。
- 既有土地信息：[spatial_world.gd](../scripts/vnext/spatial/spatial_world.gd)，只读详情增加相邻土地引用。
- 说明：本文件与 [ARCHITECTURE.md](ARCHITECTURE.md)。

没有删除文件。实际替换了旧多行时间 HUD、横向展开导航、右侧固定对象卡、只绘制选中土地的旧函数，以及冗长底部来源串接。原经济页面、人物详情中的既有入口和经济动作保留。

水系直接按当前地理范围、日期与尺度请求。WORLD 接近可见尺度时也使用已有战略批次，不要求先进入 REGION。批次在当前缓存视口中显示，没有新增全局管理器或另一套加载状态机。

只复用活动分片，重复目标合并；更换目标或退出显示取消过期工作。准备期间保留已完成批次，新海陆裁切 LOD 整档完成后替换。真正的空 LOD 也完成交接，避免保留上一地区的河流。数据完成安装时自动请求重绘和所选地点资料刷新。历史地点保留当前所选展示记录，离开活动分片后仍可从详情定位；不创建正式世界地点。读取错误进入已有操作反馈。快速换档取消未完成批次，Local 请求不再用于当前视图时取消准备。

国名、城市名、地点卡和图例绑定已嵌入的思源宋体 / EB Garamond。城市字形及国名有限字号缓存随未变内容复用。移除了旧的逐次国名字形绘制副本和 WORLD 城市重叠绘制。战略裁切面从当前有效视口取得政体样式与纹理，换视口不重新准备未变几何。普通按钮保留功能字体。现有 Political / Economy 图层菜单、铁路开关、海洋静态边缘层次以及湖泊/内海配色保留。没有改地形数据、明暗或混合权重，没有新增动态水面或海底深度。

## 正式土地与行政关系续作（2026-10-11）

实际覆盖来自 `data/land/paris_land_pilot_r1.json`。本轮从巴黎—凡尔赛 454 km² 扩展到巴黎周边 7,264 km²，新增 6,810 km²。原六块几何及 ID 保留；两个连续外围带各新增 12 块，初始共 30 块。范围宽 116 km、高 84 km，外缘顶点约东经 1.36473–2.94548、北纬 48.45328–49.21709。外缘和内部线均为游戏范围及游戏单元分割，包含未分类的内陆水域。全球地理面、政治显示面、旧 Spatial 地点和军事地域聚合不自动成为正式土地。

既有生成器读取种子中的 `coverage_generation`，保存基础轮廓、稳定名称、外围带范围和来源窗口。后续有界扩展可以复用同一生成及存储过程；`--spec` / `--output` 支持显式输入和输出。只使用已有 Natural Earth 大陆源确认大陆内部包含关系。1900 年法国主权依据沿用同代巴黎及周边资料；法国开局控制仍是显式世界假定，不从物理岸线推出。

土地格式改为通用 `land_unit_seed_v1`；原文件路径、根 ID、源引用和谱系版本保留。当前 Spatial 和 Territory 存档结构保持。旧存档读取时，仅完整缺少的新增覆盖批次可以补入；已有土地、分割谱系和三类政治事实从存档恢复。新增土地取得原开局主权和控制，行政归属未知。邻接在原 LandTopology 中重建，仍只计算正长度共边。活动上限为 280，停用上限为 250；补入覆盖后仍可容纳原上限内的分割，不增加第二套索引。

地图定位整个覆盖时按扩展范围计算尺度，定位选中土地时只计算该土地范围。描边对原投影边作有限采样，以表示扩展土地在地图投影中的边形；采样不写入土地状态，不产生网格或新身份。既有 Political、城市、河湖、铁路、地形和旗帜表现保持。本轮未运行画面确认。

LandTopology 沿原索引增加 50 / 25 / 5 km 查询窗口，返回相交的现有土地 ID、相交面积及未覆盖面积。查询窗口以已有投影原点定位，不保存新网格或新土地身份。Spatial 分别汇总主权、Territory 当前控制和行政归属。地图尺度按约 100 像素的物理宽度选择查询档；5 km 以下读取该土地内已有正式地点及其显式道路、铁路、航运关系。历史展示点不因此成为正式地点。

在近景点击地点标记之外的试点土地，可选中真实土地 ID、显示轮廓并进入详情。世界资料明确说明覆盖范围；行政名录能进入单个行政对象详情，分页读取已关联土地，土地链接进入同一对象选择入口。没有编辑行政归属的玩家按钮，也没有增加军事或经济入口。

Spatial 使用既有 Seine、Seine-et-Oise 身份资料作为行政引用。`set_land_administration` 调整实际土地成员，清除时回到未确定；不修改主权或 Territory 控制。土地分割继承原政治事实。成员仍保存在现有 `spatial.land.politics` 的 `administrative_status/administrative_region_id`，原 v3 结构保持。两省成员现在依据 TRF-GIS 重建多边形确定，不按首府或质心分配。

历史资料线索：

- [Apur 历史地图入口](https://www.apur.org/dataviz/cassini-grand-paris/)可以访问历史底图。[Apur 数据目录](https://www.apur.org/sites/default/files/documents/geo-apps/fichiers-attaches/catalogue_donnees_geo_2021.pdf?token=kEwl5G1b)列有 1895–1900 年 Seine 图集地理配准资料；本轮未取得可以直接导入的边界矢量或成员对应表。
- [Seine-Saint-Denis 的图集条目](https://patrimoine.seinesaintdenis.fr/Atlas-du-departement-de-la-Seine)列出 37 幅图的配准拼接及 1895–1900 年时期。[Institut Paris Region 的历史制图资料](https://www.institutparisregion.fr/fileadmin/NewEtudes/Etude_679/3_siecles_de_cartographie_no_119_avec_signets_light.pdf)提到图集在 1930–1942 年修订。原版与后修订版必须区分，不能仅因图集名称标有 1900 就直接导入。
- [Hauts-de-Seine 档案地图目录](https://applis.hauts-de-seine.fr/adOld/archives.hauts-de-seine.fr/archeologie-patrimoines/patrimoine-culturel/la-cartotheque-historique/principaux-plans-et-cartes-du-xxe-siecle-utiles-en-cartographie-historique/index.html)列出 Andriveau-Goujon 1900 年 Seine-et-Oise 市镇地图。索引线索不等于取得地图、确认边界日期或建立土地成员。
- [巴黎档案地图分类](https://archives.paris.fr/archives-numerisees/plans/cartes-geographiques-et-plans-dedifices)覆盖多种时期和尺度；尚需取得具体原图、年代及市镇归属资料。未从档案网页名称生成几何，未用现代省界替代。

此前 Apur 图像请求失败，Seine-Saint-Denis 和 Hauts-de-Seine 仅取得图集及 Sèvres 图幅目录。这些原图缺口保留。本轮使用 TRF-GIS 省级历史重建数据接入，不再以失败的栅格请求为施工前提。

## TRF-GIS 1900 首批两省边界接入（2026-10-11）

实际下载 `DEPARTEMENTS_1900.zip`（Dataverse datafile 4083432）、`README_DEPARTEMENTS.txt`、`METADATA_DEPARTEMENTS.qmd`、1900 年省级名录及 codebook。只取得该年度省级材料，没有下载整个 1870–1940 GIS。原始材料保存在 `local-artifacts/trf-gis-1900`，由 `.gdignore` 排除出游戏资源。运行时只读取两省的派生 JSON。

作者为 Victor Gay，TSE / IAST；[Départements 数据集](https://doi.org/10.7910/DVN/ULQYM5)采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。论文：Gay (2021), Mapping the Third Republic, Historical Methods 54(4), 189–207，[文章 DOI](https://doi.org/10.1080/01615440.2021.1937421)。署名、许可、源文件和转换方法保存在派生数据中，界面显示作者、数据 DOI 和许可。

原 `.prj` 为 RGF93 / Lambert-93（EPSG:2154），`.cpg` 为 UTF-8。实际字段为 `fid, dep_id, dep_name, dep_encl, cl, cl_name, cl_act, cl_x, cl_y`。通过 `dep_name=SEINE / SEINE-ET-OISE` 与 `dep_id=75 / 78` 对应既有行政 ID，保留原首府和行政类型。年份来自年度文件，不是逐日测绘字段。`cl_x/cl_y` 是投影坐标；论文说明首府坐标为现代市政厅位置，本轮没有将其导入世界地点。

论文方法使用 HAC / COG 历史市镇归属，聚合 IGN GEOFLA 2011 市镇几何。论文给出底层 GEOFLA / BD CARTO 比例尺 1:1,000,000，并指出城市扩张等局部误差。本轮标为 `HISTORICAL_GIS_RECONSTRUCTION`，不称为 1900 年原始测绘或 1900-01-01 当日精确边界。地图使用范围限于 1900 年度，缺其他年度数据时不延用。

`tools/map/build_france_department_boundaries_1900.py` 离线提取两省，减去既有土地投影原点 `(648000, 6862000)`。保留完整外环和内环。土地交点沿原土地边作 0.25 m 二进制格点处理，并在省界中使用同一交点；本批最大位移约 3.24 m。这是转换数值处理，不是来源测绘精度。没有简化为任意直线、现代省界或质心分配。

原 30 块土地的对应结果：

- 直接确定 Seine 成员：`paris_pilot_east`、`paris_pilot_southeast`。
- 直接确定 Seine-et-Oise 成员：`paris_basin_inner_northwest_a/b`、`paris_basin_inner_south_a`、`paris_basin_inner_west_a/b`。
- 依据省界二分 14 块：核心 `north / northwest / south / west`；内环 `east_b / north_a / north_b`；外环 `east_b / north_b / northwest_a / northwest_b / southeast_b / west_a / west_b`。完整原 ID 和子代几何保存在派生 JSON 的 `land_correspondence.splits` 中。
- 保留未知的 9 个原单元：内环 `east_a / south_b / southeast_a / southeast_b`；外环 `east_a / north_a / south_a / south_b / southeast_a`。其中外环 `east_a` 位于本轮两省之外；其余交集涉及多部件或孔洞，不以不相连面冒充一个简单土地。

首批离线结果为 44 个活动单元：Seine 9 块，Seine-et-Oise 19 块，未知 16 块。未知包括上述 9 个原单元及 7 个切分后位于两省之外的子代。后续完整化结果见下节。覆盖仍为 7,264 km²。原 30 个 ID 保留为活动根或停用父项；新 ID 由原 ID 与 `trf1900` 后缀确定，不随相机变化。

LandTopology 在原简单 Polygon 支持中允许凹环，仍拒绝自交、孔洞和多部件土地，仍执行原面积、包含、重叠、邻接与身份约束。没有新土地运行时。新世界在原 Territory 控制安装后调用 `SpatialWorld.split_land` 和成员函数。读档先恢复原拓扑、主权、控制及行政事实，再处理尚未分割且几何保持原状的根；已有子代不替换，已有确定成员不重置。达到原分割限额或切分被原机制拒绝时保留未知。

左侧显示选项增加“历史行政界 · 1900 重建”。蓝色虚线表示重建省界，金色实线表示生成游戏土地。两项开关独立，不修改世界状态。开启土地层时，地点标记和土地选择优先；关闭土地层后可直接点击行政区域。行政详情可定位完整省界及成员土地；土地详情可返回所属行政区。关闭叠加后使用原 Political 底图。两省以外的行政范围和当前土地覆盖外区域不生成土地身份。

实际保存了原始数据、离线转换结果及实现。未启动游戏，未运行测试、试跑、性能探针、审计、哈希核验或 Git 操作。44 个活动单元及成员计数为离线对应结果，运行时会按实际成功切分和现有存档事实显示。

水系：进入巴黎支持范围且尺度适合时，现有资源同步函数直接请求 Local 数据，首次定位或平移不依赖后续滚轮事件。MID：区域缩放计算新姿态并拒绝超出有限投影域的操作，不再通过平移约束移动滚轮锚点。政治显示：战略参考陆地不覆盖已有部分政治显示区域，保留原有按日期解析的政治面和来源 ID；没有扩展记录日期或填造旗帜。海岸、地形、字体和菜单路径保留。

个人经济实现本轮只读，移交见 [personal_economy_implementation_handoff.md](economy/personal_economy_implementation_handoff.md)。经济实现没有修改或删除；是否保留由经济算法工作线决定。本轮未运行测试、试跑或测量。

## 巴黎周边省级行政归属完整化（2026-10-11）

仅读取本地 TRF-GIS `DEPARTEMENTS_1900.zip` 及同年的省级名录。按实际相交选出六省：Seine（75，Paris）、Seine-et-Oise（78，Versailles）、Seine-et-Marne（77，Melun）、Oise（60，Beauvais）、Eure（27，Evreux）、Eure-et-Loir（28，Chartres）。新行政 ID 由历史省名确定，原两省 ID 和首府引用保留。新增首府只记录来源名称，不创建正式地点。省级 CSV 按 CP1252 读取，Shapefile 仍为其 `.cpg` 指明的 UTF-8。

转换器保留首批十四次分割的 ID 和几何，继续处理其未知子项。完整参考省界用分组件的外环与孔洞保存，包含 Oise 飞地；正式土地仍只用连通、无孔洞的简单 Polygon。离线按历史省界裁切，再寻找逐个取出连通部分的有限顺序。每次父项均二分为两个简单多边形，余部保持连通并满足原限制。没有新增三角网、连接线或质心分配。很小的真实组件也保留；无法表示的部分不会并入邻省。

原九个未知根全部取得分割方案：

| 原土地简称 | 连通子项 | 二分次数 |
| --- | ---: | ---: |
| inner_east_a | 4 | 3 |
| inner_south_b | 3 | 2 |
| inner_southeast_a | 4 | 3 |
| inner_southeast_b | 4 | 3 |
| outer_east_a | 2 | 1 |
| outer_north_a | 4 | 3 |
| outer_south_a | 3 | 2 |
| outer_south_b | 3 | 2 |
| outer_southeast_a | 3 | 2 |

首批剩余七个未知 `_out` 子项：outer_north_b、outer_southeast_b、outer_west_b 完整归属；outer_east_b 二分为 2 项、outer_northwest_a 分成 5 项、outer_northwest_b 分成 4 项、outer_west_a 二分为 2 项。均通过原二分能力形成实际谱系。中间余部也有身份，后续分割后保留为停用父项。完整 ID、切分顺序和最终对应保存在 `france_department_boundaries_1900.json`。

最终离线历史开局为 74 个活动单元，74 个有明确成员，未知范围 0 km²；Seine 15、Seine-et-Oise 31、Seine-et-Marne 10、Oise 5、Eure 6、Eure-et-Loir 7。活动上限、停用上限、最小面积和坐标量化不变。总覆盖仍为 7,264 km²，首批两省边界和已归属土地不换几何。运行时根据实际成功的分割与存档状态显示，未运行游戏确认此计数。

Spatial 土地事实新增 `historical_initialization_eligible`，沿原 `spatial.land.politics` 持久化。只有资格仍在、几何对应离线方案、成员未知、主权及控制仍为开局事实的土地接受历史补充。正式游戏分割、行政调整（包括清除成员）、主权变更或控制变更会撤销资格；控制变更由原 TerritoryState 发出通知，控制事实仍只由它保存。历史初始化的分割继承原事实和资格。没有新存档容器或内容指纹要求。

旧四字段土地事实没有变更记录。读取时将其资格设为否，保留现有几何、谱系、成员、主权、控制和未知状态。不能证明玩家从未改过的旧土地不自动套用新初始参考；旧存档活动数和未知数可能与上述离线开局不同。

已有历史行政图层和名录包含六省，可选择完整重建范围、查看来源、首府和重建面积，定位当前成员土地。蓝虚线为 1900 历史参考，金线为当前游戏土地；当前成员始终从 Spatial 实际状态取得，资料卡明确两者可能不同。小于 0.01 km² 的土地面积用 m² 显示，避免显示为零。未重做 UI、地形、字体或 Political 底图。未启动游戏，实际玩家画面尚未确认。未运行测试、试跑、回归、审计、哈希、性能探针或 Git 操作。

## 法国本土历史省界与粗土地（2026-10-11）

本地 TRF-GIS 1900 Shapefile 与同年名录接入 87 个原始条目：86 省及 Territoire-de-Belfort，包含统一的 Corse，不加入当时属于德国的 Alsace-Lorraine。历史名称、dep_id、首府名称、Victor Gay 署名和 CC BY 4.0 保留。新首府只记录名称，不创建世界地点。资料是年度市镇归属与 GEOFLA 2011 几何的重建，不是 1900-01-01 实测边界。

统一转换器为 `tools/map/build_france_department_boundaries_1900.py`。旧巴黎外围生成器删除。原有巴黎 74 个活动身份、44 次二分方案、成员及微小子项保留；不将这些细分比例推广到全国。新增 285 个根土地：282 个使用固定 Lambert-93 50 km 单元，3 个因物理几何条件采用 25 km，没有新生成全国 5 km 网格。离线开局方案共 359 个活动土地，76 个有行政成员，283 个跨省或位于参考边缘，待按需要细化。旧存档的实际活动数仍由原分割谱系和玩家事实决定。

物理单元使用既有 Natural Earth 10m 资料，750 m 简化后与固定投影格裁切，保留连通简单多边形。有日期依据的 CShapes France 记录只参与范围选择和法律主权判定，不把其国界坐标复制为物理土地。完整落入该政治参考的新增单元记录法国主权，初始法国控制为明确开局假设；121 个国界或岸线来源边缘单元的主权和控制未知。行政成员只由完整历史省界包含确定，不按质心分配。主权、成员在 Spatial 保存，当前控制仍由 TerritoryState 保存；分割继承既有事实。

总物理单元面积约 591,556.41 km²，包含国界粗单元伸出的部分，不是法国行政面积或法国主权面积。与 TRF-GIS 1900 参考范围相交约 531,710.45 km²，完整参考约 533,627.66 km²。二者约 1,917.21 km² 的差值含岸线口径、概化与物理资料差异，不称为实测漏地面积。两个不足 1 km² 的新物理碎片暂不建立土地身份，合计约 0.75 km²；位置与原因保存在种子的 intentional_exclusions，未并入邻省。

沿原省界索引和 REGION 内容同步加载。174 个省界文件分为粗轮廓和原始参考细节；全国概览使用粗轮廓，近景只载入相交省份细节，选中省份可保留单个细节用于资料卡。原始 Shapefile 不在运行时读取。新增省界文件合计约 2.81 MB，粗文件约 0.45 MB、细节约 2.36 MB；这是文件大小，不是实际内存或性能测量。正式粗土地仍常驻原空间状态和索引，没有第二份网格。

现有菜单改为法国范围。蓝虚线显示 1900 年度历史参考，金线显示游戏土地；全国概览优先省界，细小土地线按屏幕范围隐藏。可从法国 REGION 选择历史省份、查看完整重建面积及实际覆盖比例、当前成员，再定位成员土地。关闭图层恢复原底图。1901 年后停止把年度参考显示为当年界线，但不删除当前成员和行政资料卡。未变更且具备初始化资格的土地才补充历史成员；玩家已有分割、成员、主权和控制不覆盖。没有新存档容器、内部指纹或兼容管理器。

本轮只执行离线数据生成，未启动游戏，实际玩家画面尚未确认。未运行测试、回归、审计、哈希、门禁、性能探针或 Git 操作。

本轮修改路径（项目根目录 `D:/programs/WWO/wwo`）：

- 转换：`tools/map/build_france_department_boundaries_1900.py`、`tools/provenance/generate_historical_provenance.py`；删除 `tools/map/build_paris_land_pilot.py`。
- 空间：`scripts/vnext/spatial/land_topology.gd`、`scripts/vnext/spatial/spatial_world.gd`、`scripts/world/territory_state.gd`。
- 加载：`scripts/content/land_pilot_loader.gd`、`scripts/content/administrative_loader.gd`、`scripts/content/world_bootstrap.gd`。
- 显示：`scripts/presentation/map/globe_renderer.gd`、`scripts/presentation/ui/main_shell.gd`、`scripts/presentation/ui/world_view.gd`、`scripts/presentation/formal_world_presenter.gd`、`scripts/formal/formal_world_application.gd`。
- 数据：`data/land/paris_land_pilot_r1.json`、`data/world_map/historical/france_administrative_identity_1900.json`、`data/world_map/historical/france_department_boundaries_1900.json`、`data/world_map/historical/france_departments_1900/dep_*_coarse.json` 与 `dep_*_detail.json`（174 个文件）、`data/world_map/territory_source_registry.json`、`data/provenance/historical_source_registry.json`、`data/provenance/historical_fact_evidence.json`。
- 说明：`docs/UI_INFORMATION_ARCHITECTURE.md`、`docs/map/paris_land_unit_pilot_r1.md`。

## 仍缺资料或尚未确认的部分

- 厄立特里亚与法属索马里海岸的既有政治记录从 1900-01-24 生效，1900-01-01 显示覆盖仍缺。保留对应地名与说明，不把记录日期改为建国日期，不以现代旗帜填空。
- 格陵兰仍缺当前历史政治显示关联。物理陆地与地理名称已有，中性说明不表示历史上无主。
- 汉志使用既有代表图案，其中灰白区域可为图案白色部分；不声称该代表图案是 1900 年国旗。
- 水系路径与 MID 交接已经修改调用，但未运行画面或性能测量，不能宣布路径问题或性能已通过。
- 全球正式土地覆盖尚未实现。法国本土已有历史参考与粗土地；283 个新粗土地的省级成员仍待细化或处于资料边缘。法国岸线细节、小于首层游戏面积的物理组件、逐市镇对应、其他年份、多层行政与其他国家土地仍缺。50 / 25 / 5 km 查询聚合当前正式身份；5 km 以下只表达已有正式地点及显式关系。旧存档缺少变更历史时保留当前未知。
- 当前人物基础身份没有姓名/头像资料，不能提供真人姓名或肖像。正式组织没有成员/职务/所在地引用时，对应入口无记录。
- 已接入个人购买、持有、消费和每日安排。历史零售商、城市仓库、配送、求职、迁居、加入组织、转售及物品转赠没有正式执行路径；未新增这些按钮。

2026-10-12 原生开发范围补充：人物页的岗位/订单区接入旅客线路、旅行阶段、异地申请和待领取批次。人物处境区显示在途与最早到达时间。按钮经 Application、LivelihoodAction 和实际宿主业务执行，页面没有移动或扣款公式。经营地点信息来自到达后的有限公告；地图选择不产生旅行。企业查询提供合同工作地点，原生区域观察显示生效范围和本人的扩容申请结果。有限开发组合提供一条显式cohort扩容选项；不会自动启用全国接管。完整迁居、跨人口统计单元旅行、重型个人搬运、拆分单批领取和退出清算仍缺。相关入口已解析，未运行画面或经济情景确认。

## 长期待办

| 范围 | 当前缺实现 | 缺资料 | 由其他工作线推进 |
| --- | --- | --- | --- |
| 地图 | 全球土地覆盖、多层行政关系、更多 Local 地区及地点关系、港口角色与船舶/航运显示 | 1900 行政边界与土地成员对应、城市空间依据、局部政治显示关系 | 不重复现有地图与土地基础 |
| 个人生活 | 职业/求职与个人需求、健康等生活后果、人物日程、旅行迁移及长期人生变化 | 姓名/头像/职业与关系资料按实际记录接入 | 现有正式人口、账务及工资保留；经济算法由经济线推进 |
| 企业与组织 | 组织事项从观察到处理、人物关系与承诺、信息获取和传播、政府与政治行动 | 明确的企业/机构地点、成员与职务引用 | 企业、库存、采购、运输的实际联动由经济/组织工作线推进；当前 UI 只读取已有结果 |
| 军事 | 当前正式人物 UI 尚无军事操作与持续推进接入 | 根据已有正式地理与编制继续接入 | 既有 MilitaryState、MilitaryService、MapAdapter、权限与 DefendAction 保留；军事算法由军事线推进 |

不为待办建立空类、空菜单、预留回调或兼容包装。其他工作线已提供的字段继续读取实际实现，不从实验目录搬回旧模拟。

## 此前被拒绝删除的编译缓存

这些路径保留未删状态，不是本批实施前置条件。本批没有再尝试删除、改路径或绕过审批。此前目录删除和指定文件删除均收到自动审批拒绝，工具只返回 `blocked by policy`，没有具体原因。

- `D:/programs/WWO/wwo/tools/map/__pycache__/audit_correctness_release.cpython-310.pyc`
- `D:/programs/WWO/wwo/tools/map/__pycache__/build_geographic_foundation.cpython-312.pyc`
- `D:/programs/WWO/wwo/tools/map/__pycache__/build_global_relief.cpython-312.pyc`
- `D:/programs/WWO/wwo/tools/map/__pycache__/build_global_strategic.cpython-310.pyc`
- `D:/programs/WWO/wwo/tools/map/__pycache__/build_global_strategic.cpython-312.pyc`
- `D:/programs/WWO/wwo/local-artifacts/physical-relief-r1/__pycache__/build_probe.cpython-312.pyc`

项目外上传附件不能在本地修改。旧附件中关于 FormalWorldSimulation、旧 EconomyService、组件注册表、启动阻断、版本互锁及额外核验流程的指导不适用于当前入口。


## 人物空间活动与区域接管续接（2026-10-12）

既有人物“岗位 / 个人订单”页显示旅行阶段、剩余分钟与到达估计。岗位和个人订单可以翻页；待领取批次仍提交原 collect 行动。工时按钮使用领域提供的 work_hours_available 和 can_work_now，不在页面计算或结算劳动。

“管理范围 / 企业经营”展开既有页面内的配置选择、接管结果及本人管理企业的暂停、恢复和退出请求。当前退出会显示延后原因并保留责任。区域开发配置中的选择引用真实宿主地点、人物和人口范围，新增资金与库存为零。

经济观察页显示本人管理地点的实际库存、可售数量、承诺、岗位、原料缺量与在途责任。其他企业仍只通过合法报价和配置公开的区域汇总表达。查询不会推进时间、提交接管或产生交易。原生与宏观统计继续分项显示。


## 跨区活动与个人物资操作

人物页分别显示常住统计归属与实际活动地点。岗位使用原已知信息，旅行仍显示已知可达路线、实际票款和时间。账务读取本人全部币种账户的真实交易，不因位置变化自动换汇。

原岗位 / 订单页复用数量输入提交部分 collect，可选择领取并寄存，并显示批次余量、已付货款、已付运费与仍预留金额。原财产 / 消费页显示所有权总量、当前可用量和本人各批次的随身、寄存、货运责任；store_goods、withdraw_goods、send_personal_goods 使用同一正式人物行动入口。页面不能远程消费寄存或货运占用物品。

货运候选来自领域查询的已知路线及已知保管地点，不暴露其他企业隐藏库存。区域开发菜单的承运路线公告是本人管理企业已有路线的明确扩容申请，到正式经济边界才取得信息；查询本身不学习路线。经济观察页区分常住消费责任、在场具名人数和旅行中人数；历史消费无活动地点时保留未定位信息，不随人物旅行重新归给当前地区。没有新增旅行、仓库或货运页面。


### 常住迁居与责任交接状态

人物现有岗位/订单页显示常住与活动统计单元、迁居申请及延后原因。只有领域查询提供有效目标许可与实际在场条件时显示申请迁居按钮。现有经营资料区提供本人退出申请，显示实际未来消费接收方。Application 使用 LivelihoodAction 提交；页面不写人口、库存和金额。

区域经济观察分开显示常住人口、在场具名人数、原生独立消费责任和旧宏观责任。商品映射显示来源、吨与开发单位数量比、未映射类别及无所有权的统计库存限制。只返回本人或其已授权接管请求涉及的个人物资交接。企业退出请求展示实际仍承担的库存、订单、工资、贷款、股份和经营责任。

### 企业现金、欠薪与信用

既有“生产与企业采购”区增加资金视图。只显示本人管理企业的实际资金、到期欠薪、贷款剩余本金、利息及到期日。借还款候选由领域按实际报价、现金、未清债务与独立金融许可提供；金额复用原数量输入，按钮提交 finance_firm，不在UI增加余额或清除债务。没有合法候选时保留具体原因。经营身份不授予分红或第三方赔付权限。

金融与物流组合须显式使用 --formal-stratified-economy --formal-liquidity-policy。旧经济默认入口不变。50日结果属于开发参数组合；经营恢复及金融根授权分支没有在该场景实跑，界面点击和布局未实机确认。金融增量随本次仓库整理纳入经济集成分支。

## 2026-10-14：时间刷新与 HUD 第二阶段

时间推进保留 SimulationStep 的原边界顺序。调度调用省略未使用的宏观世界摘要；生产、消费、工资、运输和日结算不变。Application 按已有结算日与状态修订读取经济摘要，组织观察只在相关页面需要时取得。Presenter 不再准备隐藏的人物账务、组织名录和市场页面。

普通时间更新只刷新钟表数值与时刻指示。静态钟表外框、刻度和星轨曲线使用 MainShell 内的 CanvasItem 绘制结果，布局变化才重画。行政与政治地图不因跨过每个小时重新解析或投影；已加载资料的有效期发生变化才重新准备相应显示。经济主题更新只替换观测数值，保留地理批次。

右上时钟为 160×160，圆心锚定右上屏幕角。左上国旗取消外框；18 个静态二维顶点由轻量 Shader 作约 1.15 像素波动，使用视觉 TIME。左下为镜面椭圆剪影饰盒，保留人物、账务和关系图标；姓名、地点与现金在现有人物详情读取。底部黄铜半球仪、事件星轨形制、主菜单、市场、五槽存档与退出逻辑不变。

REGION 可在海面使用有效投影，缺少 LOCAL 片段时仍可缩放至 2 米/像素。平移范围只约束平移，不再拒绝合法放大。LOCAL 交接不依赖距最初投影中心 500 千米的旧限制，也不会因资料准备较晚而跳回较远尺度。

局部地表的颜色和坡面明暗来自既有高程与法线，安装时计算并复用；没有新增海拔倍率、噪声、树木或水面。采尔马特资料为 swissALTI3D 2019 裸地参考，原生 2 米、显示约 19×28 米；缺少林地范围及真实河道水面几何，不能称为 1900 林地或精细城市地貌。

岛屿参考转换增补新几内亚三种殖民关系与俾斯麦群岛，并整理辽东和中美洲原日期几何。只在历史来源单独覆盖岛内且没有其他政体竞争时使用该岛完整物理轮廓；不以最近国家或旗帜延展归属。旅顺、大连租借外缘未核定，清方主权与俄方租借行政分别说明。CShapes 衍生几何保留原 CC BY-NC-SA 限制，原始下载材料不进入游戏包。

本阶段未运行游戏、性能测量或回归；源码与正常导出不代表玩家画面已确认。原生经济运输派发、资产完成与每日处理的计算成本仍需由经济工作线按其领域规则处理。

### 2026-10-14：企业直接成本观察

原 PersonView 企业资金区显示本人有权管理企业的履约收入、已售已知直接成本、可比较部分贡献及未知成本销售数量。不称净利润，不相加不同币种。已有企业来源批次查询增加其实际余量的成本状态；资本查询增加项目投入和设备来源成本。查询不记账、不形成工资、不推进时间。普通人物不能借公开区域统计读取其他企业成本账。

成本策略须显式使用 --formal-stratified-economy --formal-cost-accounting，可与已有资金压力组合同时启用。联合产出没有权重、旧来源成本未知及自身运输未明确分配时如实显示未知；只对可靠可比的实际经营结果使用有限NPC策略。正式经济价格、授权及默认入口不变。本轮成本增量仅保存在本地，未再次上传；界面解析通过，布局和点击未实机验证。

企业资金区增加单列物流费用、装卸已发生工资、已知物损成本、待付退款和待付赔偿。物损金额属于来源所有者观察，不指定最终合同责任。领域查询同时返回 transport_by_purpose、handling_allocations、loss_records、contract_dispositions、确认退款后的可比贡献和资本 cost_lifecycle；不将退款当成回库，也不将赔付当成销售。库存查询分开显示自有、站点可用、预留、在途及成本未知数量。普通人物的读取权限仍由原企业经营查询检查。本批经济解析和短业务恢复已运行；Application 的字体/纹理导入缓存缺失仍阻止完整界面解析，页面未实机查看。

### 企业商业服务入口

显式 `--formal-stratified-economy --formal-services` 下，PersonView 原企业经营区增加“商业仓储与设备维修”。仍使用当前已选的合法企业、经营地点和数量输入。有限候选包括已知报价委托、实际取回、未开始取消、维修暂停/恢复及本企业服务接单控制；动作统一通过 Application → LivelihoodAction → EconomyServiceMarket。查询复用真实接受预检，不预留资金、不移动货物、不推进时间。业务执行再次检查授权、预算、现金、来源和设施。

合同显示实际履行、已付/未付、保管余量、等待原因与币种；经营观察区分服务履约收入、客户费用、实际现金收付和完整已结合同的已知直接贡献。普通客户不读取提供者隐藏材料/工资成本；未送达仓储货损通知不直接暴露现场事实。页面不赋予客户商品产权、第三方赔偿权或组织贷款权。MainShell、地图和原个人寄存/货运入口未因服务开发重做。完整 Application 已通过 Godot 4.6.3 解析；本轮未进行界面人工点击或视觉验收。


### 居民服务入口

PersonView原生个人经济区增加“现场餐饮与个人服务”，只展示本人已知报价、实际地点、当前可预约容量、锁定费用、本人合同和目标窗口。可提交本人预约、未开始取消或同一未履行份额重新预约。Application经LivelihoodAction送到原ServiceMarket；Presenter只读取resident_services，不改需要、材料、资金或工时。原企业仓储维修区及个人寄存货运入口保留。企业经营者原有独立授权控制也适用于新服务报价的启停。

当前仅日界、同地、无劳动重叠份额。页面展示领域拒绝原因；预约不显示为已吃饭或已理发。不得由此读取其他企业成本或其他居民现金。已完成Application解析与领域行动运行，未进行完整界面实机点击验证。未改MainShell、地图或字体资源。

### 租赁使用权与租金责任

显式租赁组合在现有PersonView个人经济区提供“住房使用与租金责任”，企业经营区提供“经营场地租约与出租责任”。本人只看已知候选及本人合同；经理只看有权管理企业的合同和费用。显示地点、单位、有限余量、报价/期限、实际人份、期间已发生金额、实付、到期未付和等待原因。住房目标只覆盖显式配置人口，不推断初始无房，不自动办理常住迁居。

页面经Application和LivelihoodAction提交request_lease、handover_lease、end_lease、return_lease或pay_lease。可在交还后按当前条款重新承租；不提供原合同自动延期或强制腾退。领域重新检查当时权限、实际在场、日界、库存及未结业务，页面不能清账、移动人物、分配空间或修改Population。首次申请只锁首期现金；未来租金承诺、实际住房使用与已付款分别显示。出租收入、承租期间费用及欠款单列，不能读作净利润或商品成本。

企业租权只限制显式配置站点未来经营，已接受服务、库存和工资不会因页面显示租约结束而删除。仍有实际站点责任时交还会被领域拒绝。MainShell、地图、HUD及原服务入口未因租赁重做。Application解析及正式领域短场景已运行；页面布局和点击未实机验证。

### 建筑投资与出租经营观察

原PersonView“投资与设备”区域继续使用原invest、investment_status、capital_status和maintain_capital。建筑选项显示独立建设许可、空间单位、材料、实际工时、工期、预算及可取得的已知估算；建筑空间不显示为新增工业产能。建成资产显示可出租份额、实收/应收租金、原建设投入和未计折旧。估算与实际成本分别显示，不能将几日租金称为完整回报率。

原租约区域支持有独立出租授权的经营者暂停/恢复约定报价。人物只看已知住房及自己的租约；企业页面只返回当前合法管理范围。未完工、建筑不可用、未准备合法站点、资金不足和空间冲突由领域拒绝。建筑暂不可用时显示原合同、占用和欠款仍保留。新站点沿原范围扩容操作进入，不提供免费库存或设备。没有新增建筑编辑器、地图按钮、土地绘制或房地产主菜单。Application与经营查询已运行；完整界面点击及布局未实机验证。


### 门店经营与现场购物

PersonView原企业经营区显示有权管理门店的场地状态、营业余量、实际分配工时、可售库存、在途采购、近期销量及可比商品贡献。门店开停复用原站点暂停/恢复行动，进货复用原企业采购。租金与工资继续从原经营及租赁区域读取，不赋予额外采购、融资或出租权。

EconomyPage仍只展示人物已知卖方。选中具有现场交付条件的门店后，原购买行动按真实地点、营业工时、库存、资金和报价执行；界面注明现场取得后另按原消费安排使用。不可购买时显示领域原因。生产企业直接购买和实际运输渠道继续保留。没有新增商店菜单、MainShell或HUD布局。施工期间Application解析与领域查询已运行。末次Application复查被region_view.gd缺少五个表面生成函数阻塞；未处理地图工作线代码。完整界面布局和点击尚未实机检查。


### 商业公告与宣传操作

PersonView复用原企业服务操作分页，提供有权管理企业的商品/服务地点公告、付费本地公告、停止后续接触和自主宣传策略开停。显示渠道延迟、受众上限、拒绝原因、最近公告安排/送达数、真实宣传费用及已付款。服务提供者继续在原客户合同区看实际发布工作和收入。宣传费用单列为期间费用，未并入商品进价，也不称广告因果收益或净利润。

人物区域和本人EconomyPage只展示本人实际收到的有限公告，保留发布时观察与有效状态。原市场按钮打开本人已知的当前商品报价；餐饮/理发继续从原居民服务区取得实际知情候选。浏览页面不接收消息、不变更知识、不执行交易。公告中的历史数量不代表当前库存。普通人物不能读取其他企业成本或私人合同；Application仍经LivelihoodAction提交领域行动，没有新营销页面、MainShell或HUD结构。

公告后观察只返回原有限日期索引中的实际交付和每顾客最近请求样本，不声称全部历史询价次数或广告归因。服务现金合计包含原公告服务付款，宣传期间费用另列。当前Application解析通过，领域查询不改变正式快照；未进行完整界面点击与布局检查。


### 原生用工操作

PersonView原企业经营区的服务/经营分页加入招聘。合法用工经理可查看名额、实际聘用份额、现行未来报价及已接受合同，发布/续发招聘、调整未来空缺工资和名额、停止招聘、向原员工提出新条款。用工授权独立于生产开停、贷款和股息。页面只提交原LivelihoodAction，领域再次检查经理、授权、现金观察、名额和边界。

个人岗位列表使用收到的报价ID发出申请，点击不会静默改为新报价；过期或撤回条件可被拒。本人可在原岗位区域确认已经收到的未来条款，查看原合同、工作登记、付款与欠薪，并沿原行动离职。未收到招聘不提前显示新工资；不能由个人查询看到其他企业账户。

本轮Application及Presenter/PersonView解析通过。未做完整界面实机查看。地图、HUD、MainShell、字体及资源未因本轮修改。


## 自愿经营收尾操作

PersonView复用企业经营区和现有经营行动分页。独立授权者可申请收尾、恢复未来经营、选取原成熟工资或租金责任作部分付款；贷款及货损退赔继续走原入口。页面显示经营阶段、关闭阻塞、原债权引用及金额。派生经营查询另提供自由库存、合法报价、仍有效岗位及设备不可转让原因。查询不修改领域状态。

场地交还仍检查真实库存、设备、工资、服务与合同。员工使用原本人离职行动和已知招聘报价求职，经理不能删除其债权。停业不表示公司法律解散。界面没有债务编辑、免费转移资产或强制腾退入口。38日局部场景完成领域与候选恢复，Application解析通过；未进行完整UI实机查看。
