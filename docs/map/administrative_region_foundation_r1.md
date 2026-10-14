# WWO Administrative Region Foundation R1

2026-10-08；Godot 4.6.3.stable.official.7d41c59c4；Compatibility；Windows x86-64。

## RESULT

**BLOCKED_SPATIAL_MODEL**。有实际产品用途的部分：法国历史行政资料页显示两个经过现有 Evidence gate 准入的历史身份和首府；既有行政边界缓存支持停用墓碑与只读计数；独立合成夹具研究可变成员、局部边界更新和恢复。**正式世界行政成员关系、动态行政地图和行政持久化没有接入，不能判定 COMPLETED。**

另有边界资料缺口：找到历史馆藏目录，但没有获得经过许可、数字化与误差审查的完整行政几何。没有用现代省界、显示三角面、首府质心或 5/25/50 km 网格补齐。

## A. CURRENT SPATIAL MODEL

|对象|实际身份与用途|是否能承担试点行政成员|
|---|---|---|
|`VNextSpatialCatalog` / `VNextSpatialWorld`|9 个法国游戏宏观 region、32 个 city、8 个 port，共 49 个地点事实；`place:<map_id>` 是查询接口稳定 ID；国别目录 177 条|不能。地点不是无缝覆盖的土地分割，城市/港口是点；宏观 region 是游戏聚合|
|`SpatialWorld._territories`|地点 `entity_id` → sovereign_owner_id、administrative_parent_id；现有 parent 指地点层级，不是正式 Département|不能将其现有名字或 parent 改解释为历史行政成员|
|`TerritoryState`|49 个地点 ID → controller；当前唯一可变控制所有者|控制可变，但没有 département 精度的独立土地覆盖|
|`VNextTerritoryUnit` / sealed `VNextTerritoryUnitCatalog`|已有不可变 land ID / geometry_ref / source_snapshot_ref / adjacency 类型|Formal `WorldBootstrap` 未实例化此目录；不能把已存在类型误报为已有法国土地实例|
|`TerritorySourceRegistry`|8 个来源；0 个 ADMITTED；CShapes 非商业限制为 REFERENCE_ONLY；现代法国原型为 REJECTED|没有可由该准入机制生成正式法国细土地的来源|
|`regions.json`|96 个现代 département Polygon 加 2 个 Lille 手工占位 Polygon；9 个宏观 region；整个文件 `prototype_only=true`|不能。Seine-Maritime 等现代命名和占位几何不是 1900 年证据|
|`GeographyLoader` / CShapes|151 个日期筛选政治 feature，另有 Arabia/Gulf 展示补充；法国 `gw_220` 为国家尺度|不能拆出 Seine / Seine-et-Oise 的土地成员；Presentation 内容准入不等于 TerritorySource 生产土地准入|
|`GlobeSurfaceBatch`|51,788 个显示面属三角化、细分、纹理/拾取面；camera 只改 uniforms|没有 territory_unit_id、单独主权/控制存档；不得升级为土地事实|
|Paris Local / Global Strategic|日期证据、城市点、物理水系、铁路参考和按需 LOD|Paris shard 行政 Polygon 为 0；没有覆盖 département 的可编辑土地拓扑|
|50/25/5 km|候选查询/聚合粒度|不是法律土地身份或行政界|

缺少的具体能力：与行政名称无关的稳定土地 ID；在巴黎周边覆盖陆地、共享边一致且无重叠缺口的几何分割；跨历史界的土地可明确空间拆分；独立土地主权/控制与保存绑定。所需几何必须能沿历史界划分，不能用固定 5 km 边缘代替。

## B. ADMINISTRATIVE MODEL

只读证据身份为 `administrative_region:france_seine` / `administrative_region:france_seine_et_oise`；type=`departement`，level=1，parent=null，polity=`state:country_fra`。这些是稳定**证据引用**，尚未成为当前行政实体。有效范围 1900-01-01≤date<1901-01-01 是本次核实资料范围，不是虚构建制成立/撤销日期。

独立夹具才有 current_name、historical_name、active、capital_place_id、成员及 membership_revision。仅研究一个真实所需层级，不建立无限层级/权限系统。可以表达 State / Guberniya 等类型，但没有把合成实体声称为历史内容。

## C. SOVEREIGNTY / CONTROL / ADMINISTRATION

生产现状：地点主权仍由 SpatialWorld 保存，地点 controller 仍由 TerritoryState 保存；只读历史 dossier 不改变两者。实验中行政 membership 仅在合成夹具内，控制使用独立 TerritoryState，主权独立记录。测试证明 controller 变更不修改成员；成员变更不修改主权和控制；改名不改变归属。

## D. HISTORICAL SOURCES

复用 `HistoricalSourceRegistry`、`HistoricalEvidenceCatalog`、`HistoricalProvenanceGate` 与原生成器；新增 3 个外部身份来源记录、1 个项目编纂来源和 1 个内容绑定的 `administrative_identity` fact。以下记录没有引入第二套历史注册系统。

|来源|机构、年份/定位|使用限制、适用范围、误差和实际审查|
|---|---|---|
|[SGF Mouvement de la population T210](https://www.insee.fr/fr/statistiques/2659665?sommaire=2591397)|SGF / Insee；1900；DBF record 73 SEINE、76 SEINE-ET-OISE，V6 名称、V3 历史省代码|仅独立提取事实名称；没有重新发行整表，没有导入人口计算。CP850 解码 dBase 字段；无坐标/几何，因此几何误差不适用。原始 DBF 留在 local-artifacts research|
|[Archives de Paris institutional history](https://www.paris.fr/pages/historique-missions-fonds-et-collections-d-archives-2353)|Archives de Paris / Ville de Paris；回顾 1796、1878、1964；Historique 段落|核实 Paris 为 Seine chef-lieu 及建制连续性；仅事实提取，未打包页面/图片；复用 `place:paris`，不从首府推断边界|
|[Préfecture des Yvelines building history](https://www.yvelines.gouv.fr/Services-de-l-Etat/La-prefecture-des-Yvelines/Histoire-du-batiment)|法国国家机关；从 1800 的 Seine-et-Oise prefecture、1866 入驻、1867 开幕；I.1|核实 Versailles 首府；复用 Local 已准入 `place:versailles`，不是新创身份。现有 Local 城市代表点约 0.5–2 km 误差，不等于行政界|
|[Plan du département de la Seine](https://catalogue.bnf.fr/ark:/12148/cb40722120g)|BnF 馆藏，H. Barrère 1895；1:12,500，12 张；GE BB-52，FRBNF40722120|**候选目录，未准入几何**。目录确认时期/图幅，未取得扫描与明确复制许可；未配准、未数字化，几何误差未知|
|[Atlas du département de la Seine](https://patrimoine.seinesaintdenis.fr/Atlas-du-departement-de-la-Seine)|Seine-Saint-Denis 文化遗产服务；1895–1900，37 张拼接配准；单幅分别登记|**候选参考**。页面明确 reproduction soumise à autorisation；没有引入受限扫描。目录所列地名覆盖并不证明都在 Seine 行政辖域；未采用其配准结果，误差未知|
|[Seine-et-Oise 1900 map catalogue lead](https://applis.hauts-de-seine.fr/adOld/archives.hauts-de-seine.fr/archeologie-patrimoines/patrimoine-culturel/la-cartotheque-historique/principaux-plans-et-cartes-du-xxe-siecle-utiles-en-cartographie-historique/index.html)|AD92；Andriveau-Goujon 1900；目录提及 1/5,000，FRAD092_5FI_SEV_001|**线索，未准入几何**。实际图幅、比例尺及复制权限尚待核查；没有手工对齐或误差估计，更未声称测绘精度|

BnF 1898 `[Carte du] Département de la Seine` 的目录检索有记录 cb40722121t，但详情请求未成功；未将其未经复核的详细参数用于正式数据。没有取得可直接接入的历史 GIS。

## E. INITIAL CONFIGURATION

生产的当前行政初始化为 **0 个实体**。Content dossier 可用 **2 个历史身份**：Seine / Paris、Seine-et-Oise / Versailles；这不是全法国配置。已验证 SGF 1900 原始条目，拒绝将现代 Yvelines、Hauts-de-Seine、Seine-Saint-Denis 等当作这两个历史单位。

## F. TERRITORY MEMBERSHIP

生产成员关系 **0**；没有把首府点、法国国家 Polygon 或旧 96 个现代 Polygon 分配进去。合成夹具显式通过既有 sealed TerritoryUnitCatalog 提供四块 land，X/Y 初属 A、Z 属 B、W 属 C；通过单一 land→region 索引和派生反向索引验证修改。它不是法国土地。

## G. MUTABILITY

合成夹具验证 create、rename、capital、批量 transfer、empty deactivate、exact restore；全批预验后才写两向索引；重复 ID、未知 land、重复成员、跨 polity 转移、无效首府、非空停用失败时不改事实。不允许重用停用身份。没有正式玩家编辑按钮或政治改革动作。

## H. BOUNDARY GENERATION

生产动态边界 **尚未实现**。实验仅对具有精确共享顶点/边的合成拓扑消去内部边，产生轮廓线缓存；没有长期独立可改行政 Polygon。此方法不处理真实 GIS noding、容差、孔洞、国际日期变更线或曲面，不冒充正式 polygon union。

## I. CACHE / REVISION

复用 `AdministrativeBoundaryCache`；成员未变不失效，只通知 A/B；同 revision 重复通知无作用，旧结果 `store` 拒绝；C 缓存保持原值；停用清 geometry/dirty 并保留 revision tombstone。新增 O(1) 只读 metrics；camera、controller、rename、capital 不驱动成员版本。

合成 2,000 单位实验：单块转移触及 1 个 land 和 2 个 region，不扫描全球成员；只测试状态实验复杂度，不声称证明全球正式 GIS 性能。

## J. REGION VISUALIZATION

行政 FAR/MID/NEAR **未启用**，因为没有合法历史边界。现有 FAR 国家界/旗帜 fade/地形、MID 城市水系铁路、NEAR 地方结构和 Paris LOCAL 连续保留。没有添加行政标签碰撞、第四套地图或虚假线。身份页可显示两个历史名称及首府，标题明确部分样本，说明无土地/边界。

## K. HISTORICAL ACCURACY

身份、名称和首府有历史名录与官方机构证据；有效日期只限本次核实年。候选历史地图仅证明馆藏存在，未证明精确几何。未纳入 Alsace-Lorraine、现代省份或未审核的法国海外区划；没有声称构造完整法国范围。原历史源不因实验改名/转移改变。

## L. OCCUPATION COMPATIBILITY

合成 A 的 X 可以 controller=Germany，而 Y 仍 France；A 身份/成员保持。行政记录无整体 controller，也不复制人口、经济、军事事实。占领比例将来只能从各成员控制事实派生；本轮没有军事占领玩法。

## M. PERFORMANCE

同机先后测量施工前快照与修改版；Godot 4.6.3 / Compatibility，NVIDIA RTX 3050 Laptop GPU，Windows **Release**（debug=false），1280×720，隐藏窗口原生渲染。每包 16 个阶段，Person idle 20 s，其余 idle 20 s、pan/zoom 12 s；系统摘要排除首 3 s 和尾 1 s，约 2–3 s 采样。两个包均 save_unchanged=true / v14。测量没有与 Godot 模拟测试并行。

frame 指 process_frame 间隔，包含静止 low-processor 等待，不是 GPU 单帧绘制时间；CPU 为进程除以 20 逻辑核；process GPU 是最忙引擎而非各引擎求和；W 是整板、包含其他应用。短样本不能证明长期功耗或风扇转速。

|stage|version|frame median ms|p95 ms|p99 ms|max ms|CPU %|process GPU %|board W|WS MiB|private MiB|video MiB|GPU dedicated/shared MiB|last-frame calls|
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
|person_idle|before|16.66|17.68|18.10|18.73|0.13|0.00|3.38|505.86|710.04|125.66|164.31 / 55.19|64.00|
|person_idle|after|16.67|17.73|18.20|21.00|0.08|0.00|3.41|506.38|708.99|125.66|164.31 / 55.19|64.00|
|world_idle|before|16.67|17.66|18.11|24.17|0.10|0.00|3.38|516.65|728.29|132.67|178.43 / 64.23|265.00|
|world_idle|after|16.68|17.82|18.15|25.88|0.10|0.00|3.40|517.16|727.26|132.67|178.43 / 64.23|265.00|
|world_pan|before|16.65|17.73|18.18|34.87|2.84|18.98|7.76|525.09|738.66|136.85|176.39 / 68.59|308.50|
|world_pan|after|16.61|17.94|20.01|28.44|3.15|18.57|7.76|525.90|738.11|136.85|176.39 / 68.59|305.50|
|world_zoom|before|16.68|17.64|18.04|18.42|2.72|21.25|7.87|526.28|736.82|136.85|173.26 / 68.59|318.50|
|world_zoom|after|16.63|17.73|18.15|21.83|2.84|21.24|7.82|526.30|738.28|136.85|176.39 / 68.59|300.00|
|region_far_idle|before|16.65|17.81|18.37|19.52|0.10|0.00|3.41|573.10|801.14|159.61|189.23 / 56.59|121.00|
|region_far_idle|after|16.69|17.69|18.16|23.66|0.09|0.00|3.42|574.49|802.17|159.61|189.23 / 56.59|121.00|
|region_far_pan|before|16.68|17.76|20.86|32.07|3.21|19.24|7.71|577.74|805.86|159.09|189.24 / 58.59|403.00|
|region_far_pan|after|16.66|17.97|22.50|29.67|3.07|20.32|7.74|579.11|806.79|159.09|189.24 / 58.59|406.00|
|region_far_zoom|before|16.67|17.71|18.20|22.55|3.25|21.33|7.78|577.79|805.83|159.61|189.24 / 58.59|439.00|
|region_far_zoom|after|16.67|18.03|21.07|25.58|3.39|20.81|7.86|579.15|806.69|159.61|189.24 / 58.59|436.00|
|region_mid_idle|before|16.66|17.82|18.28|20.58|0.08|0.00|3.41|578.17|810.05|161.39|193.23 / 56.59|105.00|
|region_mid_idle|after|16.65|17.73|18.16|26.39|0.15|0.00|3.44|579.58|811.08|161.39|193.23 / 56.59|105.00|
|region_mid_pan|before|16.65|17.78|18.33|27.63|2.99|21.02|7.78|578.22|810.05|161.38|193.23 / 56.59|424.00|
|region_mid_pan|after|16.66|18.17|23.91|29.86|3.49|20.81|7.85|579.62|811.08|161.38|193.23 / 56.59|424.50|
|region_mid_zoom|before|16.67|17.87|20.39|23.65|3.45|20.46|7.79|578.27|810.05|161.39|193.23 / 56.59|431.50|
|region_mid_zoom|after|16.61|18.00|22.48|36.25|3.29|20.23|7.81|579.66|811.08|161.39|193.23 / 56.59|429.00|
|region_near_idle|before|16.65|17.78|18.34|18.98|0.14|0.00|3.42|578.29|810.05|161.36|193.23 / 56.59|86.00|
|region_near_idle|after|16.67|17.67|18.11|18.81|0.07|0.00|3.46|579.69|811.08|161.36|193.23 / 56.59|86.00|
|region_near_pan|before|16.70|17.62|18.18|21.41|2.28|19.83|7.82|578.39|810.05|161.36|193.23 / 56.59|371.00|
|region_near_pan|after|16.63|17.87|23.10|24.92|2.80|20.33|7.84|579.72|811.08|161.36|193.23 / 56.59|372.00|
|region_near_zoom|before|16.64|17.65|18.02|18.34|2.62|21.25|7.87|578.45|810.05|161.37|193.23 / 56.59|385.50|
|region_near_zoom|after|16.65|17.97|19.47|22.24|2.71|20.42|7.84|579.76|811.08|161.37|193.23 / 56.59|384.50|
|paris_local_idle|before|16.64|17.67|18.12|20.15|0.06|0.00|3.44|583.02|824.61|165.06|201.23 / 56.46|66.00|
|paris_local_idle|after|16.68|17.72|18.09|18.56|0.10|0.00|3.47|584.29|823.61|165.06|201.23 / 56.46|66.00|
|paris_local_pan|before|16.67|18.05|22.79|29.17|2.86|21.31|7.83|585.62|827.18|165.06|201.23 / 56.46|328.00|
|paris_local_pan|after|16.67|17.70|18.12|19.63|2.44|20.14|8.03|585.91|825.25|165.06|201.23 / 56.46|328.00|
|paris_local_zoom|before|16.67|18.17|24.03|37.29|3.34|18.34|7.86|585.66|827.18|165.06|201.23 / 56.46|331.50|
|paris_local_zoom|after|16.66|17.66|18.14|26.14|3.17|19.96|7.90|585.96|825.25|165.06|201.23 / 56.46|331.00|

全部六个 idle 阶段修改前后 process GPU 中位数均 **0.00%**，稳态 renderer 绘制增量为 **0**。修改版静止板卡中位数 **3.40–3.47 W**；REGION 操作 p95 **17.87–18.17 ms**，LOCAL pan/zoom **17.70 / 17.66 ms**。没有观察到持续地图重绘；短期 CPU/WS 波动不单独归因为行政内容。

修改版全部阶段行政缓存 invalidations / stores / retirements / dirty / cached 均 **0**，camera 不建立任何行政几何。正式行政边界准备及更新耗时 **N/A**（未接入，不能报成已完成或用 0 ms 冒充）。统一回归的独立合成共享边更新为 **250 µs**，2,000 个合成单位的一块成员转移为 **401 µs**；含测试断言输出，不是正式 GIS 性能。

原始 frame、OS、prepare transition、GPU/renderer memory、缓存计数均保留于 `local-artifacts/administrative-foundation-r1/{before,after}/{results.json,system.jsonl,summary.json}`。截图源于同一测量包。

## N. MEMORY / GPU

|项目|实际新增/变化|
|---|---:|
|新运行数据文件|1（France identity JSON）|
|新身份证据 / 正式行政实体|2 / 0|
|生产成员关系 / 行政几何坐标|0 / 0|
|新身份 JSON|4,782 bytes|
|既有来源 registry / fact catalog 增量|3,676 / 6,597 bytes|
|运行数据总增量|15,055 bytes|
|行政 GPU geometry / draw calls|0 / 0|
|Release 包前 / 后|173,036,224 / 173,052,944 bytes|
|Release 实际增量|16,720 bytes|
|PCK entries|771|

修改版全进程 idle WS **506.38–584.29 MiB**，完整 private/video/GPU dedicated/shared 与 before 对照见 M 表；不能把全进程差额视为精确行政对象大小。没有行政边界常驻 CPU/GPU；两个 identity 及来源由现有 Content/Evidence 一次读入，现有地图几何继续按需驻留。Release static tracked RAM=0 是构建监视器不可用，不是零内存。

包体实查确认 3 个更新的运行 JSON 与工作文件一致；**tests / tools / docs / local-artifacts / builds** 未打包，合成夹具、SGF 原始表、历史馆藏研究和测量场景均不进入产品。`package-audit.json` 保留 PCK 核查；SHA256 `dfa957f60a3bfe36768601a2024bd33690f3650f069f8030d686bcf112a8e3c7` 仅标识发行产物，不用于存档兼容判断。

## O. WORLD STATE

**新增正式状态 0**。WorldState、WorldBootstrap、SpatialWorld、TerritoryState、经济、人口、军事计算均未修改；历史资料仅由已有 Content loader 消费。夹具在 `tests/fixtures`，不能被生产启动或玩家 UI 调用。

## P. PERSISTENCE

保持 `formal_world_simulation_v14`。生产没有可变行政事实，因而不升级 schema，也没有猜测旧存档迁移。真实 formal save/load 用现有回归验证；合成 fixture binary roundtrip 单独报告，绝不称作正式行政存档完成。

## Q. MODIFIED / NEW FILES

|路径|本任务职责|
|---|---|
|`data/world_map/historical/france_administrative_identity_1900.json`|2 个身份/首府、范围与来源；无成员/几何|
|`tools/provenance/generate_historical_provenance.py`|沿原生成器验证并产生来源/fact；合法政治/地点引用、明确 identity-only|
|`data/provenance/historical_source_registry.json` / `historical_fact_evidence.json`|仅追加本任务的 4 来源/1 fact，保留已有语义记录|
|`scripts/content/administrative_loader.gd`|Evidence gate 接入历史 dossier，detached dated lookup|
|`scripts/content/historical_loader.gd`|资料页按 GameClock 日期取历史行政身份|
|`scripts/presentation/ui/world_view.gd`|已有资料页显示有证据的首府|
|`scripts/presentation/map/administrative_boundary_cache.gd`|停用墓碑和只读计数；无成员事实|
|`tests/fixtures/administration/synthetic_administrative_state.gd`|明确独立合成修改/恢复/共享边实验，不在产品内|
|`tests/formal/formal_administrative_foundation_test.gd`|真实 Content + 合成试验边界；空间缺口审计|
|`tests/formal/presentation_content_boundary_test.gd`|把旧“法国资料为空”断言更新为实际身份覆盖/边界仍缺失|
|`tests/world_data/test_administrative_identity_contract.py`|拒绝坏日期、引用、重复身份以及伪装几何/成员|
|`tools/run_validation.ps1`|将新回归纳入统一流程；未改阈值|
|`tools/map/administrative_foundation_release_probe.gd`|驱动现有产品的 16 个原生 Release 测量阶段及真实截图|
|`tools/map/build_administrative_measurement.py` / `summarize_administrative_measurement.py`|隔离测量包与 OS/frame/cache 观测摘要|
|`docs/map/administrative_membership_presentation_contract.md` / 本报告|更新可用范围、实际阻塞与验证证据|

新 GDScript 的 `.uid` 为 Godot 生成配套身份文件。没有 commit、reset、cleanup、push，保留工作树其他改动。

## R. VALIDATION

**统一验证 exit=1，不能宣称全部通过。** 十年测试 **40 checks / 1 failure**，实际 **326.098445 s**，超过原 **240 s**。唯一失败是耗时；十年数值、存档恢复、146 政治实体、50 主要经济目录、满足率 3194 bp 和 699,092-byte 存档检查通过。没有改公式或阈值。

|验证|实际结果|
|---|---|
|统一 runner 到十年前的 27 套件|30,126 checks / 0 failures|
|Administrative Foundation R1（包含在上项）|87 checks / 0 failures|
|世界十年|40 checks / 1 failure；exit 1|
|施工前快照同脚本十年控制|420 s 进程超时；runner exit 1；无完整指标|
|中断后补跑的最后历史经济套件|18 checks / 0 failures；exit 0|
|完整原统一套件合计（含补跑）|30,184 checks / 1 failure|
|TerritorySourceRegistry / TerritoryUnitCatalog / control ledger 补充回归|65 / 58 / 131 checks，合计 254 / 0 failures；各 exit 0|
|Python world-data（含新身份准入）|62 tests / 0 failures|
|额外 provenance EOL/content 回归|5 tests / 0 failures|
|政治 / market / economic / world 四组 fresh-process hash|各两进程一致；exit 0|
|补跑正式 headless startup|exit 0，无脚本/加载错误|
|Windows Release 产品导出 / 原生启动 / before & after native probes|各 exit 0|
|PCK 发行资源审查|771 entries，开发/原始资料排除，通过|

地图渲染、scale transition、Local foundation、Paris Local、visual scale、resource efficiency、physical relief、global strategic、Presentation、Spatial、political identity、Population、Personal Economy、30-day/year golden、Persistence、World integration 全部通过各自检查；统一及补跑日志扫描无未解决 parse/type/script/resource loading 错误。negative rejection 测试的预期 push_error 保留，不作为引擎错误。

初次开发 fixture 曾错误读取 flat snapshot 的 `state` 字段，已修正并经最终 87-check 回归通过；初次 Start-Process 导出未正确引用带空格的 preset 名，改用结构化 subprocess 参数后实际导出成功。初次失败日志保留。产品原有 version `0.001a` 的非数字导出警告仍在，没有进行无关版本修改。

`tests/codex_audit_regression.gd` 在当前树不存在；本次没有改人物成长、NPC 时间边界或正式权威模拟状态，未宣称运行这个不存在的旧入口。现有 strict save/load、状态冲突/原子恢复与 World integration 由上述生产回归验证。人工 1280×720 鼠标旅程没有执行；原生自动旅程和真实截图已执行，不能互相替代。

施工前快照（所有生产资源在本任务改动前复制）以**相同未改阈值的十年脚本**独立对照，也未在 **420 s 进程运行上限**内完成；runner exit=1 / TIMED_OUT，子进程已终止，未捕获完整模拟指标，不能将进程上限当作精确模拟耗时。它表明本次环境中的基线也未通过，不能证明具体根因、不能宣布不存在回退；本任务没有改模拟公式，性能 gate 仍未关闭。结果记录在 `before-ten-year-control.json` 与 runner 日志。未放宽 240 s 判定，也未将任一失败改报 PASS。

## S. VISUAL EVIDENCE

实际 Windows Release，1280×720。已检查下列图像：两个历史行政身份页、FAR / MID / NEAR / LOCAL。**地图没有有效行政边界**；这些截图证明当前产品及缺口，不能当作已完成行政地图。没有用示意图替代产品截图；隐藏窗口自动旅程不是人工鼠标测试。

|真实截图|含义|
|---|---|
|[France identity dossier](../../local-artifacts/administrative-foundation-r1/after/france_identity_dossier.png)|两项历史身份/首府，明确部分样本、无土地/边界|
|[France REGION FAR](../../local-artifacts/administrative-foundation-r1/after/region_far.png)|4500 m/px；现有国旗 fade、国界、地形和地理骨架|
|[France REGION MID](../../local-artifacts/administrative-foundation-r1/after/region_mid.png)|1200 m/px；现有水系、城市与铁路|
|[France REGION NEAR](../../local-artifacts/administrative-foundation-r1/after/region_near.png)|400 m/px；现有地方结构|
|[Paris LOCAL](../../local-artifacts/administrative-foundation-r1/after/paris_local.png)|75 m/px；既有 Paris / Versailles 稳定身份|

产品：[wwo-administrative-foundation-r1.exe](../../builds/windows/wwo-administrative-foundation-r1.exe)。日志、OS/frame 数据、package audit 和确定性结果在 `local-artifacts/administrative-foundation-r1/`。

## T. REMAINING DATA GAPS

1. 法国试点可准入、无缝细土地 catalog 和可拆分稳定身份，独立土地控制/主权绑定；这是首要阻塞。
2. 1895–1905 年完整历史界图幅的许可与扫描访问、精确配准和数字化、共享边拓扑及误差预算；Seine 与周围 Seine-et-Oise 的孔洞/接界不能凭质心猜测。
3. 1900 法国边界与行政名录完整性、跨现有 Paris shard 的覆盖、海外制度；本样本只两项。
4. 真实土地→历史行政成员的空间包含/切分证据、同级冲突/空隙验证。
5. 土地人口空间分布；行政单位尚不能作为地方人口/经济统计事实来源。
6. 各国各历史制度来源、类型、层级和生命周期证据；没有生成全球实例。
7. 正式模型通过准入后才可接入 WorldState/v15 或按届时版本升级存档，并实现真实边界 batch/标签/政治授权。

## U. NEXT RECOMMENDATION

**土地单元精度完善**：先为巴黎周边建立有许可与历史依据的稳定细土地拓扑，明确切分、来源准入及主权/控制/存档绑定，再研究历史界如何初始化成员。此项只建议，未自动开始；当前不适合启动 Administrative Editing R2。
