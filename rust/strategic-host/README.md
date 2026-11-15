# WWO Rust Windows 游戏

`wwo-map-lab` 是当前原生 Windows 游戏入口。在此目录用 `cargo build --release --locked --bin wwo-map-lab --bin wwo-formal-state` 构建。双击 EXE 或传入 `--play` 开始游戏。EXE 旁需要战略地图的 `data/`。`--data`、`--observe` 和 `--background` 均沿用正式入口。阶段归档包含 `WWO-Country-Records.exe`、Z7 候选 EXE 和运行数据，恢复步骤见 [仓库 README](../../README.md#构建与恢复)。旧地图的独立对照使用 `--map-comparison --data <旧地图目录>`。用 Pillow 执行 `python tools/build_hud.py <R68 项目> <游戏数据目录>` 可更新界面字形。

正式入口从 `data/maps/regional-2026-11-14/` 读取领土、旗纹和原有专题地图数据。用 `python tools/package_map_release.py <保留的 2026-11-14 区域地图数据目录> <游戏数据目录>` 发布这部分资源。正式入口会检查目录、旗纹资料和地图分片版本，版本不符或缺失时会报告错误。

四种地图模式共用候选资源 `data/worldcrs84quad-z4-v3/`。网格采用 WGS84 经纬度，原点为西经 180°、北纬 90°，X 向东，Y 向南。Z0 为 2×1，每升一级行列翻倍。每张分片的 256×256 个有效样点位于像元中心，四边附带 4 像素的相邻样点。经度在 180° 环绕，纬度在两极钳制。资源按 Z/X/Y 编号，分别保存 BC7 地表及有符号 16 位米制高程。地形、地表颜色、阴影和水系在全球母栅格计算，各级从母栅格降采样。[OGC WorldCRS84Quad](https://docs.ogc.org/is/17-083r4/17-083r4.html)

重建命令为 `python tools/build_natural_terrain.py <原始资料缓存> <Natural Earth 矢量目录> <输出目录>/worldcrs84quad-z4-v3`。复核现有资源用 `python tools/build_natural_terrain.py --verify <资源目录>`。逐级核验覆盖、坐标、编码、瓦片长度、同级共享样点、极区边缘和父子高程降采样误差。启动时按正式版本核对资源。运行时按视野加载，缺页从同库父级采样，相邻页共用边缘和角点的过渡权重。用 `--play --observe <观察请求路径>` 检查正式入口、帧间隔、瓦片加载和驻留状态。旧地图通过独立对照入口查看。

第一阶段覆盖全球 Z0–Z4。此后按全球 Z5、Z6、Z7 逐级生成、验收。逐级记录覆盖、体积、采样精度、资料缺口、跨级渲染和性能，并验证正式世界及专题图层。高于 Z7 先确认资料和性能预算。源数据达不到目标精度的范围回退至已验证层级，并登记缺口。验收前保留发布资源和历史对照。城市施工在全球地貌基础层后启动，人口档依次为 50 万及以上、20 万至不足 50 万、10 万至不足 20 万、5 万至不足 10 万。城市目录记录历史名称、位置、人口年份、统计口径、来源和可信度。具备历史几何的城市另记施工状态。

候选高程沿用 GMT 的 SRTM15+ V2.1 全球 60 角秒网格。海底数据包含估算区，网格间距与测量精度分别记录。海岸、湖泊及冰川使用 Natural Earth 1:10m。HydroRIVERS v1.0 的河段和下游编号保存在 `river-topology.u32`，构建输入为 `HydroRIVERS_v10_shp.zip`。地表覆盖来自 ESA WorldCover 2021 v200。现代覆盖、水文和湖库作为参照，缺口见 `index.json`。[GMT](https://docs.generic-mapping-tools.org/6.2/datasets/remote-data.html) · [SRTM15+](https://doi.org/10.1029/2019EA000658) · [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) · [HydroRIVERS](https://www.hydrosheds.org/products/hydrorivers) · [ESA WorldCover CC BY 4.0](https://doi.org/10.5281/zenodo.7254221)

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.

Z5–Z7 的预览使用同一网格和新的全球高程母栅格。原始输入为 GMT 的 SRTM15+ V2.5.5，15 角秒、像元中心配准，统一使用米。将下载文件保存为原始资料缓存中的 `gmt-15s-p-nju.grd`。较低层从同一母栅格降采样，独立的 Z4 预览可继续运行。地表采用 ESA WorldCover 缓存原有的每 3° 562 个样点。湖泊、海岸、冰川和河流沿用相同来源和统一规则。[GMT 高程文件](https://mirror.nju.edu.cn/gmtdata/earth_relief_15s_p.grd) · [SRTM15+ 方法](https://doi.org/10.1029/2019EA000658)

使用 `python tools/build_natural_terrain.py --through 5 <原始资料缓存> <Natural Earth 矢量目录> <输出目录>/worldcrs84quad-15s-v1` 生成到 Z5。通过构建核验并检查 Rust 实机后，以 `--through 6` 和 `--through 7` 续建。每级压成一个可定位瓦片的文件，构建核验解压后的共享高程、颜色、两极边界和父子高程。阶段间复用同一份临时母栅格，Z7 打包后清理临时栅格。运行候选时传入 `--play --data <原有游戏数据目录> --terrain-candidate <worldcrs84quad-15s-v1>`。Rust 只读取当前视野所需的地貌颜色，政治、经济和军事资源继续从原有数据目录加载。

使用 `python tools/build_natural_terrain.py --repack <worldcrs84quad-15s-v1> <worldcrs84quad-15s-v2>` 从完整 Z0–Z7 包生成压缩候选。重打包和复核 v2 需要 Python 的 `zstandard`。每级一个带索引的 `.qpk`，颜色和高程分别存成独立的 Zstandard 帧，压缩等级为 6。保留 BC7 原始块、Alpha 海陆覆盖和 4 像素边缘。16 位有符号米制高程以水平及垂直差分、ZigZag 及字节平面可逆存储。生成时逐瓦片对照原包，并复核全球共享边缘、两极、反经线、父子高程和原有河网。试运行时将 `--terrain-candidate` 指向 v2 目录。

LOD 使用视口中心的投影比例。将当前纬度的东西、南北采样轴换算为屏幕像素，以两轴均方根求目标层级。相邻等级以半个层级为切换中心，滞回范围为上下各 0.12 级。视野超过固定瓦片缓存时使用可完整覆盖视口的较粗层。目标瓦片就绪前显示父级，边缘跟随相邻瓦片就绪状态过渡。观察接口的 `terrain_decode_ms` 记录颜色帧解压，`tile_load_ms` 记录请求到工作线程结果送达的时间。

法国、英国、德国、俄罗斯、清帝国和日本共用一份 1900 年历史资料和模拟规则。选择国家会选定玩家及其开局地点。50 个统计市场共用 Rust 正式时钟。Rust 执行跨日市场结算、统计货运、当地统计市场现货交易、个人库存和消费。巴黎的原开局岗位、劳动合同、工作和有限企业余额下的工资由 Rust 执行。

人物模块沿用正式人物 ID。工作和购买会更新经历。健康与衰老参数属于开发假设。疾病、受伤、医疗、休息、死亡、继承和学校教育尚未接入。地区商户、个人配送、完整企业经营、行政组织、科技、战略军事和 3D 训练仍待迁移。

原生游戏支持手动槽位、保存并退出及重启读档。每个档位保存在 `%LOCALAPPDATA%/WWO-Rust-Candidate/profiles/<配置名>/formal-world`，默认配置名为 `Default`，可用 `WWO_RUST_PROFILE` 指定。存档包含时间、人口、人物、市场、在途货物、账本、库存、合同和工资权益。

## R68 地标和城市 3D

正式地图用 `/` 搜索埃菲尔铁塔、巴黎北站、耶拿桥、威斯敏斯特钟楼、威斯敏斯特桥、Friedrichstraße 车站或吉萨金字塔。定位后可点击模型查看地标 ID 和经纬度。滚轮缩放，右键拖动改变方位，`V` 切换倾斜与俯视。四种地图模式共用地标位置和模型。查询使用地图资料，人物所在地继续由正式世界管理。

GLB 与原有摆放资料随 Rust 源码从 Git 恢复，并编入 EXE。近景按视野解码和上传，桥梁、车站沿用原 GLB 两档网格。读取原件的材质底色、顶点色和法线。桥梁沿用 R68 的显示坐标和桥面基准。

巴黎 Gros-Caillou、威斯敏斯特和米尔班克沿用 [R40 原创城市模块](../../assets/settlements/R40_SOURCE_AND_USAGE.md) 的 18、16 和 4 个摆放点。相同的模块共享 GPU 网格，沿用 8 米/像素切换近远档，并保留资料注明的概念街区比例。搜索 `paris_gros_caillou_miniature`、`westminster_miniature` 或 `millbank_wharves_1900` 可定位。地标与街区沿用地图相对平面。当前原件没有图片贴图。局部地形接地、贴图和动画资源待接入。

## 全球地图验收

每轮验收从亚洲、欧洲、非洲、北美洲、南美洲、大洋洲和南极洲各随机抽取至少一个 WorldCRS84Quad 区块，共至少七个。全洲采用同一个预先确定的抽样 Z。用版本固定的洲界和陆地数据建立候选池，纳入含该洲陆地的瓦片，包括沿海和岛屿。各洲候选按 Z/X/Y 排序后等概率、不放回抽取，优先排除上轮区块。候选不足时记录重复及原因。国家、城市、画面质量和地貌加载结果均不作为筛选条件。

截图前冻结名单。记录抽样种子、随机算法及实现版本、抽样 Z、洲界和陆地数据版本，以及每个区块的 WGS84 经纬度、分片 ID 和两档取景参数。相机中心使用瓦片中心。中心落在该洲陆地之外时，取瓦片内距中心最近的该洲陆地位置，距离相同按经度、纬度排序。每块至少检查区域和近景，记录相机中心、投影、视口尺寸、缩放倍率或米／像素，以及目标 Z。画面异常或资源缺失时保留原样本和失败记录。

每档截图前核对运行时实际用于绘制的资源版本、样本中心分片 ID，以及边缘涉及的瓦片层级。记录加载过程中的短暂父级与稳定后的降级，记录混合过渡涉及的层级及原因。现有 `--observe` 的 `target_level`、`view_max_level` 和各级驻留计数用于辅助判断。需要区分具体分片或混合层级时，按坐标核对运行时页表及渲染采样状态。无法确认实际分片时标记未验证。

每块检查地貌精度、山脉和河流连续性、海岸、地表颜色、瓦片接缝及缩放跨层切换。无对应地物和资料缺口分别记录。报告按洲列出原抽样名单、两档取景参数、实际分片和层级、回退原因、截图及检查结果。异常登记坐标、分片和原因。按全球统一规则修复后，在原样本上复验。

每轮另列 180° 经线、南北两极、同级瓦片边界和不同精度交界的固定专项检查。专项结果单列，七大洲随机样本仍须齐全。

## 本地构建目录

以下目录相对于 `D:/programs/WWO`。

| 用途 | 目录 |
| --- | --- |
| Rust 主线源码 | `wwo-character-integration/rust/strategic-host` |
| Cargo 构建缓存 | `offline-map-sources/natural-terrain/target`，使用 `CARGO_TARGET_DIR` 指向该目录 |
| 当前 Windows 运行目录 | `wwo/local-artifacts/strategic-map-phase4`，随 EXE 保留所需 `data/` |
| 自然地理候选和回退 | 当前 Windows 运行目录下的 `natural-terrain-preview`，同机位交付截图在 `z7-review` |
| 地理输入和来源记录 | `offline-map-sources` |
| 单次临时观察输出 | `%TEMP%` 下的本次会话目录 |

正式构建交付后，用独立档案确认启动、世界推进、地图切换和重启读档。保留当前发布、必要回退及对应数据，清理本次已退出的观察会话、重复打包和可再生构建输出。地貌构建的临时母栅格用于续建，只有当前预定层级生成并核验后才清理。移除已合并的临时工作树前，核对 `main`、远程引用、未提交和未跟踪文件，再用 `git worktree remove`。R68 和未合并的独立工作线保留原工程与资产。

传入 `--r68` 可进入原有 R68 对照模式。该模式使用原有存档目录和 EXE 旁的两个 `tools/formal_*_bridge.gd`。通过 `WWO_R68_PROJECT` 和 `WWO_GODOT_EXE` 指定对照项目和 Godot 4.6.3。原生大厅只读写原生槽。维护工具 `wwo-formal-state` 可读取原版法国 v15 存档的部分领域。
