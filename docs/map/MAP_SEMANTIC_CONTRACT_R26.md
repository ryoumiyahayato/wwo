# WWO 地图语义契约 R26

日期：2026-10-16。R26 建立语义，R27 按独立物理底图实现更新。本文说明已存在的输入和边界，不表示五种完整地图模式均已实现。

## 1. 用途与尺度是两条轴

同一空间由不同用途组合显示。用途不创建第二个世界，观察尺度不决定领域事实。

| 轴 | 当前代码 | 含义 |
|---|---|---|
| WORLD | GlobeController、GlobeRenderer、GlobeProjection | 球体观察，独立物理 LOD 及其可选历史墨层 |
| REGION | RegionCamera、RegionProjection、RegionView | 等距方位投影、完整二维缓存、历史行政与物理参考 |
| LOCAL | 原 RegionView 裁剪三维目标、LocalSpatialLod | 在有限资料范围显示真实高程、覆盖和已有模型；不创造精度 |
| 用途 | GlobeController.map_mode | R40准入 geographic、political、fulfillment、shortage；后两种是经济观察，不是产出地图 |

R40的地理模式直接复用已安装的独立物理地表与合法景观，关闭政治/经济墨层。没有新建地态、产出或军事占位页面。原黄铜半球仪及其入口不改。军事战区网格若由军事线实现，只是空间组织方式，不替换真实地理坐标。

## 2. 五类事实与实际消费者

| 用途 | 真实输入／所有者 | 当前消费者与允许表现 | 不能承担的职责 |
|---|---|---|---|
| 地理地形 | GeographyLoader 的已准入定位；StrategicSpatialLoader 的 Natural Earth 物理海岸/水文；MapRelief 的 ETOPO；LocalSpatialLoader 的 IGN、EA、swissALTI3D、COP-DEM | GlobeProjection/RegionProjection 投影；LocalSpatialLod 准备几何；LocalSpatialLayer、RegionView 与 Shader 绘制地形 | 不决定主权、行政成员、土地利用、企业、产量或军事控制 |
| 政治行政 | HistoricalPoliticalEvidenceView、RuntimePoliticalEntityView、ResolvedMapContent、AdministrativeLoader；正式领土控制另由 TerritoryState 保存 | CurrentWorldPoliticalProjection 组装只读记录；PoliticalLayer 解析显示身份；GlobeRenderer 合成政治墨层、行政线及交互 | 不把政治面、现代海岸或 display owner 当作同一权威。行政显示裁切不重写原 GIS 或成员 |
| 产出 | 正式 EconomyState/EconomySimulation/EconomyR1 的已结算结果及只读查询 | 目前没有完整产出地图。FormalWorldEconomyView 提供市场/聚合体/历史观察；Presenter 已能按人物权限查询有限场所活动 | 不从森林、农田颜色或矿产图标生成产量。满足率、短缺、库存、能力、价格和运输不是实际产出 |
| 地态 | 已准入 cover 的 kind、范围、source_reference 和来源年代 | LocalSpatialContent.surface_covers → TerrainPreparation。R29 将现代采尔马特 OSM 林地栅格化为有限 LOCAL 显示遮罩，在原 DEM 材质上合成；有效水面仍使用原水文 Mesh。原覆盖事实和年代不变 | 不写高程，不按坡度、纬度、路径或政治色推定森林/荒漠/雪线。未知不是无覆盖 |
| 军事 | VNextMilitaryMapAdapter、MilitaryState、MilitaryService；控制读取 TerritoryState，交通能力读取 Spatial | Adapter 复用 Spatial.catalog 的地点/链接，附加 strategic_military_overlay 的军事语义；正式 GlobeRenderer 尚无完整军事模式 | 不由战区、军队或占领颜色修改自然地理、法理主权、行政成员和经济事实。不自动赋予玩家指挥权 |

MilitaryMapAdapter 的 terrain_profiles/resource_labels 是现有军事模型输入，不是由本轮 DEM/地态测绘生成的全球实测分类。军事线未来消费现代覆盖或坡度，需要明确适用年代、范围和军事解释；本轮没有接入新通行、隐蔽、寻路或补给规则。

## 3. 共享空间引用

- 经纬度／球面单位向量：GlobeProjection；REGION 公里坐标：RegionProjection。Shader 使用同一球面轴、相机基底和 bearing。
- place_id、catalog city/map ID：VNextSpatialCatalog 解析和映射；显示地标不自动成为正式地点、人口或企业。
- territory_unit ID：LandTopology 的正式空间单元；不从屏幕多边形或军事网格制造。
- runtime polity ID 与 source_historical_id：RuntimePoliticalEntityView 显式解析。1900年身份、当前主权、控制和管理关系各自保留。
- administrative_region ID：行政目录身份。显示轮廓、参考 GIS 与正式成员并非同一数据。
- market_id、economic aggregate ID、site_id：由经济接口提供；不能仅据国家颜色或最近地点猜测归属。
- military formation/action/scope ID：由军事组件保存，经 Spatial 身份解析位置；不是玩家权限。

这些引用允许数据相遇，不让五种事实互相推导。显示用 `_whole_owner_by_feature` 只用于政治绘图关系；不能充当所有领域通用 owner。

## 4. 日期与来源

| 输入 | 时间性质 | 当前限制 |
|---|---|---|
| 历史政治、行政 | Content 的 valid_from/valid_to、display_date、observation_year | 1897等重建用于已注明的1900参考，不等于逐日精确实测。真实显示修订仍由 Content 解析 |
| Natural Earth | 固定版本的现代概化物理参考，1:10,000,000 | 不是1900河岸、填海和工程重建，也不是10米数据 |
| ETOPO 2022 | 现代合成，EGM2008，含南极冰面 | 高程色阶不是土地覆盖分类；WORLD/REGION衍生并非运行时精细 DEM |
| IGN、EA、swissALTI3D、COP-DEM | 各自现代测绘时期和不同高程基准 | 本轮不统一垂直基准，不提高源精度；DSM不等于裸地 |
| OSM 林地／现代水文 | 现有资料注明2026取得日期或对应现代版本 | 不称1900森林、湿地、水位或完整河道；缺失范围保持未知 |
| R24 海洋/海冰图片 | 视觉装饰 | 不是实测洋流、水深、冰况；不用于航行、主权、土地覆盖或军事规则 |
| 经济 | FormalWorldEconomyView.total_hour、状态修订、daily_totals及正式活动记录时期 | 地图不能把不同统计期或单位相加；负满足率哨兵表示未知，0表示真实零满足率 |
| 军事 | 现有军事行动小时、控制历史及 action ETA | 当前 SimulationStep 未自动推进完整 Military；不能以屏幕动画代替军事结算 |

现代自然资料可以作明确标注的参考。没有历史覆盖资料时，不静默将其升级为1900事实。静态视觉装饰与真实地态分开。

## 5. 实际图层与合成边界

| 图层 | 当前实现 | R26 规则 |
|---|---|---|
| 物理填充 | StrategicSpatialLoader 的独立 Natural Earth 陆地、同源岸线与水域补集 | R27 取消 CShapes基础填充、补陆/裁水差集和DEM推断陆地。物理生成可不读取政治资料；未知历史归属保持中性 |
| relief | 共享 ETOPO纹理、一个中尺度窗口及有限 LOCAL DEM | 只提供几何/高度/法线；R25方向残差不重写全球高度色阶 |
| 地态覆盖 | 独立 surface_covers 输入与原覆盖 Mesh | 覆盖种类来自源；只共享 DEM 几何和光照，不从 DEM 分类 |
| 政治填充 | PoliticalLayer 身份/颜色、原历史查询面、可选 *.ink.geom 精确显示分区 | R27 用历史范围与已确定物理陆地的交集分区，在同一次物理填充中合成国旗/墨层。源政治面不再提交完整GPU填充；交集不是主权重写或最近国家推断 |
| 行政／国家边界 | 历史源线、原后台准备和裁水 | 近景陆上国家线与行政线使用同一已安装的完整物理水域补集做显示裁切；不表示海上法理界。原源线和拾取身份不改 |
| 经济着色 | fulfillment/shortage 使用正式 daily_totals.fulfillment_bp | 观察色独立于地态；缺键或负哨兵用原中性色，不涂成零满足率 |
| 军事叠加 | 领域 Adapter/State 已有，GlobeRenderer 完整显示未有 | 不新增虚构军队、控制区或战区页面 |
| 地点／建筑／古迹 | 现有地点与展示身份、LOCAL 有限模型 | 与地态、企业和军事单位分开；模型许可和准入保留 |
| 交互 | 原 selection/hover、行政/政治/物理拾取 | 只改变视图；未赋予国家主权、经营或军事指挥权限 |

LOCAL 的 `map_ink_tone/map_ink_weight` 只表示最终地图墨层。`cover_kind` 来自独立覆盖输入，UV2.x 表示派生高度，UV2.y 是本次准备的显示标记；原 height_rows_m 不含覆盖类别。零标记表示未叠加已知覆盖，不宣称“该处无森林”。

## 6. 产出接口的现状与缺口

已可读取：

- FormalWorldEconomyView 的 total_hour、country_summary、market_state、economic_aggregate_states、routes、shipments、history 及显式 polity/economy/market 交叉引用。
- FormalWorldPresenter 的现有有限查询：read_only_native_observation、population responsibility，以及经已有权限路径取得的 site_id、stock_place_id、activities、plan_day、库存、投入和共享能力。

上述字段不能直接全部画成产出。完整产出显示仍需要由经济线明确：已完成活动记录、商品与计量单位、实际产出数量、统计时间区间、有效空间引用及未知状态。库存/计划/能力不能顶替这些字段。当前地图没有将经济数值写回世界或从地态创建经济对象。

## 7. R26 已改与未改

已改：物理面逐三角政治借色和 UV/材质持有；面几何误名为 water 的分支；近景国家线绕过裁水；DEM与覆盖输入耦合；按吉萨文件路径选干旱色；经济负哨兵被夹成零；相同地图模式重复触发 appearance_changed。

保留并明确：原始地理和所有领域事实；原相机、地平线双扇面、孔洞处理、源投影和 LOD 退休；政治与地态作为最终合成输入；军事交通/控制所有权；真实历史修订更新。

R27 已替换上述物理几何债务，见 [独立物理底图施工报告](R27_INDEPENDENT_PHYSICAL_FOUNDATION.md)。旧差集不再是有效基础或并行回退。仍有：非线性投影的有限边缘近似、行政静态显示外缘与当前物理LOD的来源差异、垂直基准转换资料缺口、完整历史土地覆盖缺口。没有实机画面证明法国全部异常已经消失。

## 8. 资源与更新

仍只有原 WORLD/REGION 缓存目标和 LOCAL 裁剪目标。不为五种用途复制全球 DEM/海岸或创建常驻视口。共享历史CPU查询几何、已安装的一套物理LOD和有限地表，模式变化只更新需要的墨层和语义观察。

相机变化更新投影和可见需求；hover/selection更新交互；普通日期推进不重新准备静态地形、海岸或模型；Content有效修订才刷新对应历史显示；覆盖/地表完成安装只提交必要显示。军事和经济领域各自结算，地图不能跳过结算。

本轮不宣称性能改善比例。移除借色分组可以减少不必要的几何分组、模板持有和材质参数复制，但实际整机负担仍未测量。

## 9. R27 独立物理空间约束

`tools/map/build_geographic_foundation.py --independent` 只读取现有 Natural Earth land 与已采用的自然水域来源，生成完整陆地、同源海岸及分片水域补集。`--political-ink` 才读取原历史政治/阿拉伯显示资料，另制可选的完整交集分区。两类文件来源和许可分别记录；不从政治面补齐陆地。

`data/strategic/index.json → StrategicSpatialLoader → LocalSpatialLod → LocalSpatialLayer` 只在当前尺度安装一份有效填充。没有墨层时使用独立物理三角形；有墨层时用同一物理范围的完整分区取代其绘制细分，不同时提交两套完整面。无历史交集的陆地使用中性色。国旗UV保留原历史几何框，不随现代物理外缘重排。

海洋仍是原 WORLD 半球海面和 REGION 水色背景，不再上传旧政治裁水面；DEM只在已确定陆地上提供 relief，不作为海陆分类。内陆水面仍保留原独立水文显示，Natural Earth land 并非完整湖泊调查。当前物理水域是所选陆地的补集，不表示精确历史海水、水位或航行条件。近景边界直接按水域外环及陆地孔裁线，不为裁线再拆解完整水域面。

同一完整物理LOD上传完毕后，陆地/海岸和CPU水域裁切版本一起发布；旧有效批次在此之前保留。R39把24个全球粗档保留在基础层，区域medium由另一现有Layer实例按需持有与退休，不销毁全球基础。近景按需求球冠筛选极区相交片，不按前64片截断有效覆盖。WORLD和REGION使用同一套地理来源及投影关系，同一时刻只公开正确的一套表面。

`GlobeRenderer._political_ink` 是CPU样式记录，不是独立陆地或渲染目标。R39已删除RegionView重复样式和国界副本。原历史查询几何继续服务选择和国旗框；不再创建第二套完整政治GPU填充。真实政治颜色/身份修订更新墨层输入，普通时间不重制物理几何。未来历史几何来源变化需重制对应显示分区，不能让旧快照自动外推新历史版图。

共享的空间基础只管坐标、几何、有效来源和显示生命周期。行政、地态、产出、军事仍按第2—4节读取各自事实。R40新增geographic并保留political / fulfillment / shortage；后两者不称完整产出模式。地理模式不推定全球历史地态，原创建筑和现代林地参考树木不创建经济或军事事实。法德内部显示线仅在显示层去重、求交，原行政多边形与成员保留。见[R40施工报告](R40_GEOGRAPHIC_WORLD_PRESENTATION.md)。

## 10. R28 当前政治状态的实际显示

正式主权读取 `VNextSpatialWorld.land_facts(id).sovereign_polity_id`；实际控制读取 `TerritoryState.get_controller(id)`。原历史资料不随控制变化改写。前者已有 `set_land_sovereign`，后者已有 `set_controller`；R28只补显示通知和消费者，没有创建变更事件。

开局初始化资格已撤销的正式土地单元可覆盖原政治墨层。该标记只用于找到应读取当前值的记录，不代表主权一定已变化。形状来自当前LandTopology；首次或真实形状变化时，只在相交物理片中切分政治显示面。范围相同的再次归属变化只更新材质颜色。水陆、岸线、DEM和历史行政不因此重制。主权未知不借附近国家。

国家边界只从两个已知正式单元的真实共享边、且当前主权不同的部分生成。仅控制不同用独立控制线；不将占领变主权。不具备外侧空间状态的边界不续画。历史国家线在当前正式显示范围内退出；行政源线及身份保留。

WORLD/REGION使用同一当前状态、分区和有限边界准备路径。LOCAL仍只有单一地表墨层；若当前范围跨入其他主权，停用旧统一政治染色，保留真实地形，不伪称已完成LOCAL逐土地政治材质。当前状态与历史参考在原资料卡中分别标识。

当前身份注册表仍是开局实体集合，没有正式建国、解体、合并、改名或颜色编辑接口。无可靠面积几何的地点控制只显示在资料卡，不扩张为领土面。R28不增加经济、外交或军事算法，也不更改存档格式。详见 [R28施工报告](R28_PHYSICAL_AND_POLITICAL_UPDATES.md)。
