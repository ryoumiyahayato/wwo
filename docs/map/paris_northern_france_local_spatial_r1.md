# Paris / Northern France 1900 LOCAL spatial data R1

RESULT: **PARTIAL_DATA**。2026-10-06，Windows / Godot 4.6.3 standard / Compatibility 实测。

Paris Local 已接入正式 Content / Presentation，处理后的数据确实进入 Windows Release。历史依据充分的城镇、历史资料确认的主要铁路走廊、明确标注的现代物理河流和岸线已经可见。铁路线形仍是现代官方中心线的有界参考，尚未重建 1900 微观线位；因此不报告 COMPLETED，也不把这些线用于精确历史运输、军事或企业算法。

## A. PARIS LOCAL SCOPE

唯一锚点 `place:paris`，球面半径 300 km，不按现代行政区裁剪。涵盖 Paris / Île-de-France、法国北部、Normandy、Loire 附近落入范围的资料。实际矢量外包络约经度 −1.750146～6.451893、纬度 46.396024～51.092673；这是稀疏资料外包络，不表示整个矩形已有覆盖。点距锚点最大 299,994.56 m。

海峡法国一侧岸线已纳入。Belgium / Luxembourg / western Germany 及英国侧资料未正式准入；没有为了填图扩大研究。53 个城镇是依据同时代指南人工选择的城市、铁路节点及港口，不依据现代人口排名。

## B. SOURCES

| 类别 | 来源 / 机构 / 日期 | 许可与用途 | 可信度与限制 |
|---|---|---|---|
| settlements | [Baedeker Northern France 第三版 1899](https://archive.org/details/northernfrance00karl)，Karl Baedeker；University of Toronto / Internet Archive 馆藏 | 原著公共领域；每个点保存具体页/叶引用 | 存在及名称历史依据，confidence 0.9；坐标点不是历史建成区 |
| Paris 与近郊 | [Paris and environs 第十四修订版 1900](https://archive.org/details/14thedbaedparis00karl)，Karl Baedeker；University of California Libraries / Internet Archive | 原著公共领域；Banlieue 地图 n449，1:800,000，正文与索引引用按点保存 | 排除 1900 年稍后才开通的 Metro / Exposition 新线；有效期是 1900 资料快照 |
| settlements 定位辅助 | GeoNames，已有仓库 FR snapshot 2026-07-22，独立历史依据必需 | CC BY 4.0；只复用坐标 / record ID，5 个既有坐标保持 | REFERENCE_ONLY；不导入人口、现代行政归属或现代重要性 |
| rail 历史身份 / 公司 | Northern France 1899 路线正文及折图 France Nord et Est n7、France Ouest n578，1:1,500,000；Paris 1900 近郊图辅助 | 公共领域；证明走廊、站序与公司 | 有实际铁路历史依据，但扫描图没有矢量化配准 |
| rail 线形 | [SNCF Réseau：Formes des lignes du RFN](https://ressources.data.sncf.com/explore/dataset/formes-des-lignes-du-rfn/)，更新 2026-02-19 | ODbL 1.0；九个传统线路代码子集，经裁剪与 35 m 简化 | BOUNDED_ASSUMPTION，confidence 0.65；现代线位不是 1900 工程测绘 |
| rivers | [Sandre / OFB / IGN BD TOPAGE WFS](https://services.sandre.eaufrance.fr/geo/topage)，2026-10-06 获取当前服务快照 | Etalab Open Licence 2.0；命名自然主河流轴线，35 m 简化 | PHYSICAL_REFERENCE，confidence 0.65；不重建历史河岸、疏浚或港口改造 |
| coastline | 同服务 LimiteTerreEau_FXX，当前低潮岸线；[官方许可说明](https://www.sandre.eaufrance.fr/v2/news/diffusion-du-millesime-2026-de-la-bd-topage-metropole) | Etalab 2.0；300 km 范围内法国部分，45 m 简化 | 现代低潮物理参考，局部工程变化可能超过 1 km；不表示政治边界 |
| admin | 未取得可准入的 1900 几何 | ADMIN_BOUNDARY_DATA_GAP | 没有以现代 Natural Earth admin1 替代 |
| roads | 本轮未取得适当历史道路几何 | DEFER | 没有使用现代 OSM 路网 |

全部新增源的 title、publisher、date/version、license、retrieval、transformation、historical applicability、uncertainty 均在 shard 内沿用既有 `historical_source_registry_v2`。馆藏 metadata、OCR XML、实际扫描图、官方原始数据以及 SHA-256 存于排除发行的开发缓存。OCR 用来定位，原图与路线描述用来核对；没有将拒绝的 1909 版当作 1899 版。

源档案：`local-artifacts/paris-local-r1/source/`。获取日期统一为 2026-10-06；GeoNames 是已有 snapshot，并未伪称本轮下载。WFS 获取日期也不被当作每个对象的实际测绘年份，记录中保留 upstream modified date。

## C. DATA COUNTS

| Runtime 准入记录 | 数量 | 历史精度状态 |
|---|---:|---|
| places | 53 | 各自有独立同时代证据 |
| railway LineString parts | 11 | 9 条历史走廊的现代线形参考；精确重建的 1900 线形为 0 |
| river LineString parts | 1,387 | 9 条命名自然河流的现代物理参考 |
| coastline LineString parts | 657 | 现代低潮岸线参考 |
| historical admin polygons | 0 | 数据缺口 |
| roads | 0 | 暂缓 |

共 2,108 个 feature facts，23,049 个坐标。fragment 数量不能理解成独立河流/铁路数量。duplicate stable ID = 0，invalid geometry = 0。JSON 为 4,059,842 bytes，SHA-256 `ccbb2954cb57ea66e2f34c302581f726b30c2d9d6577ced10dc30bea6f5d803a`。

## D. HISTORICAL APPLICABILITY

**HISTORICAL_EVIDENCE**：城镇存在、历史名称、主要铁路走廊及公司。**PHYSICAL_REFERENCE**：现代自然主河流、现代法国侧低潮岸线。**BOUNDED_ASSUMPTION**：将已被 1899/1900 史料确认的传统铁路走廊映射到 SNCF 当前中心线；没有声称每一段现代线位在 1900 完全相同。**REFERENCE_ONLY**：现代 GeoNames 的定位辅助。

资料有效窗口为 `[1900-01-01, 1901-01-01)`；不是建城/拆除日期，也不表示城镇在 1901 消失。窗口外没有继续显示这一 1900 shard。城镇代表点不确定性约 0.5–2 km；铁路标示的 1,500 m 是未测定的历史位置估计，绝非经验证的误差上界。35/45 m 简化容差也不等于历史精度。

## E. PLACE IDENTITY

复用 `place:paris`、`place:lille`、`place:rouen`、`place:le_havre`、`place:calais`，没有 `local:paris` 等平行命名空间。已有 `place:port_le_havre` / `place:port_calais` 作为相关身份引用继续使用，未复制港口 ID。

新增 48 个 `place:*` 是 Content 内可选择、可显示的地点，不创建人口、企业、物理市场或正式模拟节点。已有 Content page DTO 承载新地点的资料卡，仍经既有 Presenter 显示。所有 53 个 ID 与逐点 citation 见文末地点表。

## F. POLITICAL REFERENCES

五个复用城市在本区域的 `country_fra` 引用本来就可解析，本轮未进行全球政治引用修补。新增法国城镇由同时代法国指南身份明确支持，引用现有 `country_fra`；没有根据现代 ISO、polygon overlap 或经济 scope 猜归属。

此前审查的 15 / 40 旧 political-parent 缺口未被批量处理，其他地区仍待独立历史依据。物理线没有 parent_country、owner、polity 或 controller。

## G. RAIL

| stable line ID | 本轮走廊 | 1900 公司 | geometry parts |
|---|---|---|---:|
| `rail:rfn_272000` | Paris-Nord – Lille | Nord | 1 |
| `rail:rfn_311000` | Longueau – Amiens – Boulogne | Nord | 1 |
| `rail:rfn_314000` | Boulogne – Calais | Nord | 1 |
| `rail:rfn_340000` | Paris-Saint-Lazare – Rouen – Le Havre | Ouest | 1 |
| `rail:rfn_420000` | Paris-Montparnasse – Chartres – Le Mans | Ouest | 1 |
| `rail:rfn_570000` | Paris – Orléans – Tours corridor | Paris-Orléans | 3 |
| `rail:rfn_070000` | Noisy-le-Sec – Meaux – Épernay – Châlons-sur-Marne (Paris-Est corridor) | Est | 1 |
| `rail:rfn_001000` | Paris-Est – Troyes | Est | 1 |
| `rail:rfn_830000` | Paris – Melun – Fontainebleau – Sens | Paris-Lyon-Méditerranée | 1 |

保持上游 line code、rank 和 fragment 组成的 stable segment ID，例如 `rail:rfn_272000:r1:p0`。geometry 从官方实际中心线裁剪，不是 prototype endpoints 的直线。每段只连接 shard 内有独立证据、距实际走廊不足 6.5 km 的代表地点；实际已记录距离约 108～2,960 m，Paris 的代表点与各终点车站天然不重合。

570000 保留三个断开的上游 parts；不自动填线。070000 起于 Noisy-le-Sec 的既有里程段，不虚构直接连到 Paris 中心；Paris-Est 共用起始段属于 001000。未生成末端车站支线，也没有合并近邻线为假 junction。测试覆盖 line/segment identity、引用解析、place-distance 与 geometry 相符及有限坐标；尚无完整可寻路的历史 junction/station graph。

配准方法记录为 **No scan-to-vector georeferencing**。历史图只核对走廊与站序；没有伪造控制点、RMSE 或 GPS 精度。因此这些线只能作为标明近似的 Local 空间参考，精确 1900 路由仍需后续历史图数字化。

## H. HYDROGRAPHY

Seine、Marne、Oise、Aisne、Somme、Eure、Loing、Yonne、Loire 在范围内的选定几何，共 1,387 parts。来源是命名自然河流轴线，未混入人工 canal 路网。法国北部与 Normandy / Channel 低潮岸线共 657 parts。

自然区域结构在 1900 有参考价值，但现代河道、潮位基准、港口、河岸工程可能改变局部形状。本轮没有填造 DEM、历史河宽、港口设施或水深。已有 WORLD / REGION 粗政治面的海陆填色继续保留；细岸线独立叠加，局部海陆填色与细物理岸线可能不一致，这是已知显示限制，不以岸线重新判国籍。

## I. ADMIN

**ADMIN_BOUNDARY_DATA_GAP**。1900 行政 polygon = 0；现代 admin1 未进入 Local 细边界。本项不阻止 Paris 的城镇、铁路参考和自然地理显示。

## J. LOCAL DISPLAY

在当前视觉测试确定的尺度：远端 Local（≤200 m/px）显示 major settlements、九条主要铁路参考走廊、命名河流与岸线；近端（≤115 m/px）再显示 secondary settlements。标签按既有 Labels 状态及碰撞抑制显示，选中项保留。25.2 m/px 已做性能测量，不据此宣称几何达到该级历史精度。

入口和出口、metric camera、bearing / screen anchor、mode、日期与 selection 的既有规则保留。底部注明“1900 城镇 · 铁路走廊近似 · 现代水系参考”。Political 保留原国家政治面，细物理线叠加。Economy Fulfillment / Shortage 保留 aggregate 着色；没有新增 market / factory / warehouse 节点。Military 未新增 units、fronts、supply 或 fortifications。

## K. REGION → LOCAL

游戏启动只构造惰性 loader，不读 Paris geometry。在 Paris 300 km 支持范围、Region 接近 420 m/px 时请求后台加载；数据和静态 batch ready 后，才允许原有 ≤200 m/px 入口进入 Local。未 ready 时继续 Region，轻提示准备中，未出现黑屏或弹窗。退出仍用原有 ≥280 m/px。

Paris：LOCAL_DATA_SUPPORTED（带明确 PARTIAL_DATA 精度限制）。Beijing / New York：LOCAL_DATA_NOT_AVAILABLE，原 camera fixture 保留，尝试放大后保持 Region，最细 150 m/px，没有额外 Paris 文件加载。纯摄像机夹具不再等于正式 Local 内容支持。

文件读取、JSON parse、source resolution、单位向量和 chunk 准备在后台线程；GPU资源与 glyph 分帧准备。相机移动只更新 shader uniform、label transform / collision，不再次解析、复验来源或重建全部静态几何。继续使用既有 evidence gate，未新增 registry / manager 框架。

## L. PERFORMANCE

同机 native Compatibility / RTX 3050 Laptop GPU，1280×720，VSync 下每项 180 帧。以下是帧间隔，不能代替 GPU kernel timing 或宣称其他平台性能。

| p95，ms | before | after |
|---|---:|---:|
| idle，180 m/px | 16.698 | 16.682 |
| pan，180 m/px | 16.687 | 16.683 |
| zoom，180 m/px | 16.693 | 16.684 |
| close pan，25.2 m/px | 未测同级 baseline | 16.693 |
| close zoom，25.2 m/px | 未测同级 baseline | 16.819 |

首次内容可见从请求开始约 2.208 s；旧版无细资料，不提供虚假的同内容 before 首次加载对比。预热窗口 120 帧 p95 16.717 ms，max 30.415 ms，≥100 ms 帧为 0。主线程单次准备最高 6.884 ms。该统计覆盖本次采样，不作所有硬件保证。

[before 原始测量](D:/WWO/wwo/local-artifacts/paris-local-r1/performance-before.json) · [after 原始测量](D:/WWO/wwo/local-artifacts/paris-local-r1/performance-after.json)

## M. LOAD COST

| 阶段 | 本次实测 ms | 执行位置 / 含义 |
|---|---:|---|
| file read | 6.078 | 后台 |
| JSON parse | 121.835 | 后台 |
| source / fact resolution | 739.493 | 后台，沿用既有 gate |
| geometry / chunks preparation | 19.432 | 后台 |
| worker elapsed | 886.846 | 包含上述及调度/其他小额工作 |
| GPU resource enqueue CPU 累计 | 262.157 | 分帧；不等于 GPU 实际传输时长 |
| label preparation CPU 累计 | 3.942 | 分帧 |
| 主线程分帧准备 wall elapsed | 1284.861 | 包含跨帧等待 |
| first visible frame since request | 2207.913 | `frame_post_draw` 标记 |

资源上传量估计 8,543,928 bytes；这是 batch buffer 估计，不是实际显存监测。**GPU 实际时钟/传输完成时间没有独立计时器，本轮未测得**。文件系统缓存没有主动清空，因此这是进程首次加载、非 OS 冷盘 benchmark。后台 parse / source resolution 超过 100 ms 不等于 UI 冻结。

## N. RELEASE

最终 Windows Release：[wwo-paris-local-r1-final.exe](D:/WWO/wwo/builds/windows/wwo-paris-local-r1-final.exe)。

Before 165,492,080 bytes；after 169,568,416 bytes；新增 **4,076,336 bytes**（约 3.887 MiB）。导出 exit 0。嵌入 PCK v3 的 745 项逐项核对：shard JSON 存在，解出的 payload 与工作区 JSON 完全一致；`local-artifacts/`、`tools/`、`tests/`、`docs/`、`builds/` 包内项均为零。原始扫描、OCR、完整 SNCF / WFS source archive 不进入包。

[发行包核查](D:/WWO/wwo/local-artifacts/paris-local-r1/package-audit.json)。保留现有 export version `0.001a` 非纯数字警告，未改项目版本；没有解析/类型/脚本加载错误。最终 Windows 程序已实际启动，通过菜单与鼠标完成 WORLD→REGION→Paris LOCAL，可见 Paris、Versailles、近郊城镇、铁路走廊和 Seine 水系。窗口随后有人工鼠标操作，因此代理停止发输入；没有宣称代理完成了 exported binary 的全部往返。完整 Paris 往返 / Beijing / New York 旅程使用 native Godot 的同一正式 scene/input handler 测试夹具执行，两类证据分别标明。

## O. VISUAL

Native 1280×720 正式 scene：Paris Region → wheel zoom → Paris Local（198.254 m/px）→ close / nearby settlements → aggregate Economy → northern network / Le Havre coast → pan 到 metric boundary → wheel zoom out → Region restored。Beijing / New York 的入口尝试均保持 Region。

最终 exported binary 的菜单与鼠标检查截图（1280×720 client，含 Windows 标题栏）：

![Exported Paris Local](D:/WWO/wwo/local-artifacts/paris-local-r1/release-visual/paris-local-manual.png)

以下是正式 scene 夹具的 native 旅程截图：

![Paris Local](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/paris-local-attempt.png)

![Paris nearby settlements](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/paris-close.png)

![Northern network](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/paris-network.png)

![Channel physical coast](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/channel-coast.png)

[Paris Region](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/paris-region.png) · [boundary](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/paris-boundary.png) · [Region restored](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/paris-region-restored.png) · [Beijing no Local](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/beijing-local-attempt.png) · [New York no Local](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/new-york-local-attempt.png) · [journey 原始状态](D:/WWO/wwo/local-artifacts/paris-local-r1/visual/journey.json)。

## P. WORLD FACTS

本轮没有 LocalWorld、第二套 World、全球 50×50 km grid、持久空间 cell 或新 WorldState。新增点均为 Content / Presentation 事实。Population / Economy / Personal Economy 不变；完整 persistence snapshot 在加载、选择新城镇、模式切换及旅程前后逐值相等。50 km 只读实验不是接入所需，因此未额外增加。

## Q. SAVE

`formal_world_simulation_v14` 不变，无 save schema 迁移。原精确 persistence / deterministic fresh-process world fingerprint 通过；新回归确认 Content 准备、Local round trip 与新地点资料卡显示不写模拟状态。地图跨尺度 selection / mode / Labels / date 连续；没有扩大存档 UI selection 的原有持久化承诺。

## R. VALIDATION

最终统一验证 exit **0**，24 个计数测试运行器合计 **12,665 checks / 0 failures**，另有 import、静态审计、provenance deterministic generation、fresh-process hashes 及正式启动。日志扫描通过。Persistence 的刻意坏存档拒绝诊断由验证脚本识别，不作真实回归故障。

| 检查 | checks | failures |
|---|---:|---:|
| Formal personal economy and wages | 104 | 0 |
| Formal livelihood player journeys | 39 | 0 |
| Formal application and main/menu | 33 | 0 |
| Formal Person integration | 60 | 0 |
| Formal Spatial integration | 35 | 0 |
| Formal exact persistence | 32 | 0 |
| Formal Population production integration | 476 | 0 |
| Presentation content boundary | 60 | 0 |
| Formal map rendering regression | 745 | 0 |
| Formal map scale transition | 1278 | 0 |
| Formal map Local foundation | 68 | 0 |
| Paris Local Content R1 | 6537 | 0 |
| Historical provenance foundation | 48 | 0 |
| Runtime political identity foundation | 1186 | 0 |
| Formal economy 30-day and one-year golden | 6 | 0 |
| Formal economic boundary closure | 542 | 0 |
| Formal market identity foundation | 649 | 0 |
| Organization state | 137 | 0 |
| Formal organization composition | 99 | 0 |
| Current world domain convergence | 32 | 0 |
| Formal Windows export resource contract | 374 | 0 |
| Formal world integration | 67 | 0 |
| Formal world ten-year balance | 40 | 0 |
| Historical world economy data | 18 | 0 |

Paris R1 6537 checks 包括逐源 metadata、逐事实历史/几何/ID、rail 引用与距离、NaN/owner/polygon 非法输入拒绝、快照日期、无数据地区保持 Region、异步 ready gate、anchor 连续、round trip、城镇可选且 Content copy 隔离、静止/移动无文件重读、全存档相等。原 scale / Local foundation 回归继续覆盖 bearing、pixel、selection、mode 和 hysteresis。30 日 / 一年经济 golden、90 日 World integration、十年 balance 均通过。

[统一验证日志](D:/WWO/wwo/local-artifacts/paris-local-r1/unified-final.log) · [结构数据审计](D:/WWO/wwo/local-artifacts/paris-local-r1/data-audit.json) · [validation-summary](D:/WWO/wwo/local-artifacts/paris-local-r1/validation-summary.json)。

## S. DATA GAPS

- 尚未配准/数字化历史铁路地图，未验证逐段 1900 microalignment、terminus 变化、station spurs 和完整 junction topology；精确历史线路仍为缺口。
- 九条主走廊以外的支线，以及部分城镇的铁路连接尚未准入；不补假线。
- 1900 行政几何缺失；历史主道路暂缓。
- 1900 河岸、港口工程、堤坝和潮位基准未重建；细物理岸线与既有粗政治海陆填色局部不一致。
- 半径内非法国侧内容尚未建立；其他地区没有正式 Local shard。
- GPU 实际上传时钟没有独立量测；首加载 benchmark 未控制 OS 冷缓存。

## T. NEXT RECOMMENDATION

先保留 Paris 作为有来源、明确精度限制的唯一 Local R1。建议下一步回到玩法主线；未来玩法若必须依赖精确铁路移动，再优先数字化 Paris 的历史铁路几何和站点/junction，而不是直接扩张第二地区。扩下一地区还是进入玩法由后续明确决定，本轮未自动启动任何下一阶段。

## Appendix：地点身份与独立历史依据

以下坐标只是定位点；全部有效期为 1900 快照，confidence 0.9；并非历史人口或行政数据。

| stable place ID | historical/display name | latitude, longitude | identity | 历史馆藏 citation |
|---|---|---|---|---|
| `place:paris` | Paris | 48.8566, 2.3522 | REUSED | [馆藏 n490](https://archive.org/details/14thedbaedparis00karl/page/n490/mode/1up) |
| `place:lille` | Lille | 50.6292, 3.0573 | REUSED | [馆藏 n151](https://archive.org/details/northernfrance00karl/page/n151/mode/1up) |
| `place:rouen` | Rouen | 49.4431, 1.0993 | REUSED | [馆藏 n285](https://archive.org/details/northernfrance00karl/page/n285/mode/1up) |
| `place:le_havre` | Le Havre | 49.4944, 0.1079 | REUSED | [馆藏 n139](https://archive.org/details/northernfrance00karl/page/n139/mode/1up) |
| `place:calais` | Calais | 50.9513, 1.8587 | REUSED | [馆藏 n151](https://archive.org/details/northernfrance00karl/page/n151/mode/1up) |
| `place:amiens` | Amiens | 49.9, 2.3 | NEW_CONTENT_PLACE | [馆藏 n63](https://archive.org/details/northernfrance00karl/page/n63/mode/1up) |
| `place:reims` | Rheims | 49.26526, 4.02853 | NEW_CONTENT_PLACE | [馆藏 n216](https://archive.org/details/northernfrance00karl/page/n216/mode/1up) |
| `place:orleans` | Orleans | 47.90248, 1.90407 | NEW_CONTENT_PLACE | [馆藏 n505](https://archive.org/details/northernfrance00karl/page/n505/mode/1up) |
| `place:tours` | Tours | 47.39484, 0.70398 | NEW_CONTENT_PLACE | [馆藏 n410](https://archive.org/details/northernfrance00karl/page/n410/mode/1up) |
| `place:caen` | Caen | 49.18585, -0.35912 | NEW_CONTENT_PLACE | [馆藏 n287](https://archive.org/details/northernfrance00karl/page/n287/mode/1up) |
| `place:le_mans` | Le Mans | 48.0021, 0.20251 | NEW_CONTENT_PLACE | [馆藏 n299](https://archive.org/details/northernfrance00karl/page/n299/mode/1up) |
| `place:saint_denis` | St. Denis | 48.93564, 2.35387 | NEW_CONTENT_PLACE | [馆藏 n492](https://archive.org/details/14thedbaedparis00karl/page/n492/mode/1up) |
| `place:versailles` | Versailles | 48.80359, 2.13424 | NEW_CONTENT_PLACE | [馆藏 n427](https://archive.org/details/14thedbaedparis00karl/page/n427/mode/1up) |
| `place:chantilly` | Chantilly | 49.19461, 2.47124 | NEW_CONTENT_PLACE | [馆藏 n491](https://archive.org/details/14thedbaedparis00karl/page/n491/mode/1up) |
| `place:creil` | Creil | 49.25672, 2.48477 | NEW_CONTENT_PLACE | [馆藏 n490](https://archive.org/details/14thedbaedparis00karl/page/n490/mode/1up) |
| `place:compiegne` | Compiegne | 49.41794, 2.82606 | NEW_CONTENT_PLACE | [馆藏 n140](https://archive.org/details/northernfrance00karl/page/n140/mode/1up) |
| `place:beauvais` | Beauvais | 49.43333, 2.08333 | NEW_CONTENT_PLACE | [馆藏 n103](https://archive.org/details/northernfrance00karl/page/n103/mode/1up) |
| `place:pontoise` | Pontoise | 49.05, 2.1 | NEW_CONTENT_PLACE | [馆藏 n451](https://archive.org/details/14thedbaedparis00karl/page/n451/mode/1up) |
| `place:mantes` | Mantes | 48.99048, 1.7167 | NEW_CONTENT_PLACE | [馆藏 n248](https://archive.org/details/northernfrance00karl/page/n248/mode/1up) |
| `place:rambouillet` | Rambouillet | 48.64374, 1.82992 | NEW_CONTENT_PLACE | [馆藏 n406](https://archive.org/details/14thedbaedparis00karl/page/n406/mode/1up) |
| `place:fontainebleau` | Fontainebleau | 48.40908, 2.70177 | NEW_CONTENT_PLACE | [馆藏 n469](https://archive.org/details/14thedbaedparis00karl/page/n469/mode/1up) |
| `place:melun` | Melun | 48.5457, 2.65356 | NEW_CONTENT_PLACE | [馆藏 n502](https://archive.org/details/northernfrance00karl/page/n502/mode/1up) |
| `place:meaux` | Meaux | 48.96014, 2.87885 | NEW_CONTENT_PLACE | [馆藏 n222](https://archive.org/details/northernfrance00karl/page/n222/mode/1up) |
| `place:etampes` | Etampes | 48.43507, 2.16233 | NEW_CONTENT_PLACE | [馆藏 n388](https://archive.org/details/northernfrance00karl/page/n388/mode/1up) |
| `place:vernon` | Vernon | 49.09292, 1.46332 | NEW_CONTENT_PLACE | [馆藏 n103](https://archive.org/details/northernfrance00karl/page/n103/mode/1up) |
| `place:evreux` | Evreux | 49.02414, 1.15082 | NEW_CONTENT_PLACE | [馆藏 n285](https://archive.org/details/northernfrance00karl/page/n285/mode/1up) |
| `place:chartres` | Chartres | 48.44685, 1.48925 | NEW_CONTENT_PLACE | [馆藏 n345](https://archive.org/details/northernfrance00karl/page/n345/mode/1up) |
| `place:dreux` | Dreux | 48.73649, 1.36566 | NEW_CONTENT_PLACE | [馆藏 n248](https://archive.org/details/northernfrance00karl/page/n248/mode/1up) |
| `place:arras` | Arras | 50.29301, 2.78186 | NEW_CONTENT_PLACE | [馆藏 n63](https://archive.org/details/northernfrance00karl/page/n63/mode/1up) |
| `place:douai` | Douai | 50.37069, 3.07922 | NEW_CONTENT_PLACE | [馆藏 n156](https://archive.org/details/northernfrance00karl/page/n156/mode/1up) |
| `place:longueau` | Longueau | 49.87226, 2.3588 | NEW_CONTENT_PLACE | [馆藏 n75](https://archive.org/details/northernfrance00karl/page/n75/mode/1up) |
| `place:abbeville` | Abbeville | 50.10521, 1.83547 | NEW_CONTENT_PLACE | [馆藏 n71](https://archive.org/details/northernfrance00karl/page/n71/mode/1up) |
| `place:boulogne_sur_mer` | Boulogne | 50.72485, 1.61373 | NEW_CONTENT_PLACE | [馆藏 n75](https://archive.org/details/northernfrance00karl/page/n75/mode/1up) |
| `place:dunkerque` | Dunkirk | 51.0344, 2.37681 | NEW_CONTENT_PLACE | [馆藏 n151](https://archive.org/details/northernfrance00karl/page/n151/mode/1up) |
| `place:dieppe` | Dieppe | 49.9216, 1.07772 | NEW_CONTENT_PLACE | [馆藏 n103](https://archive.org/details/northernfrance00karl/page/n103/mode/1up) |
| `place:fecamp` | Fecamp | 49.75787, 0.37457 | NEW_CONTENT_PLACE | [馆藏 n139](https://archive.org/details/northernfrance00karl/page/n139/mode/1up) |
| `place:saint_quentin` | St. Quentin | 49.84889, 3.28757 | NEW_CONTENT_PLACE | [馆藏 n183](https://archive.org/details/northernfrance00karl/page/n183/mode/1up) |
| `place:laon` | Laon | 49.5631, 3.62714 | NEW_CONTENT_PLACE | [馆藏 n185](https://archive.org/details/northernfrance00karl/page/n185/mode/1up) |
| `place:soissons` | Soissons | 49.38167, 3.32361 | NEW_CONTENT_PLACE | [馆藏 n221](https://archive.org/details/northernfrance00karl/page/n221/mode/1up) |
| `place:chateau_thierry` | Chateau-Thierry | 49.04636, 3.40304 | NEW_CONTENT_PLACE | [馆藏 n223](https://archive.org/details/northernfrance00karl/page/n223/mode/1up) |
| `place:epernay` | Epernay | 49.04, 3.95922 | NEW_CONTENT_PLACE | [馆藏 n428](https://archive.org/details/northernfrance00karl/page/n428/mode/1up) |
| `place:chalons_sur_marne` | Chalons-sur-Marne | 48.95393, 4.36724 | NEW_CONTENT_PLACE | [馆藏 n507](https://archive.org/details/northernfrance00karl/page/n507/mode/1up) |
| `place:troyes` | Troyes | 48.30073, 4.08524 | NEW_CONTENT_PLACE | [馆藏 n505](https://archive.org/details/northernfrance00karl/page/n505/mode/1up) |
| `place:sens` | Sens | 48.19738, 3.28328 | NEW_CONTENT_PLACE | [馆藏 n545](https://archive.org/details/northernfrance00karl/page/n545/mode/1up) |
| `place:auxerre` | Auxerre | 47.7996, 3.57033 | NEW_CONTENT_PLACE | [馆藏 n530](https://archive.org/details/northernfrance00karl/page/n530/mode/1up) |
| `place:montargis` | Montargis | 47.99696, 2.73261 | NEW_CONTENT_PLACE | [馆藏 n548](https://archive.org/details/northernfrance00karl/page/n548/mode/1up) |
| `place:blois` | Blois | 47.59432, 1.32912 | NEW_CONTENT_PLACE | [馆藏 n391](https://archive.org/details/northernfrance00karl/page/n391/mode/1up) |
| `place:bourges` | Bourges | 47.08333, 2.4 | NEW_CONTENT_PLACE | [馆藏 n546](https://archive.org/details/northernfrance00karl/page/n546/mode/1up) |
| `place:valenciennes` | Valenciennes | 50.35909, 3.52506 | NEW_CONTENT_PLACE | [馆藏 n171](https://archive.org/details/northernfrance00karl/page/n171/mode/1up) |
| `place:cambrai` | Cambrai | 50.17596, 3.23472 | NEW_CONTENT_PLACE | [馆藏 n142](https://archive.org/details/northernfrance00karl/page/n142/mode/1up) |
| `place:lisieux` | Lisieux | 49.1466, 0.22925 | NEW_CONTENT_PLACE | [馆藏 n250](https://archive.org/details/northernfrance00karl/page/n250/mode/1up) |
| `place:bernay` | Bernay | 49.08888, 0.59858 | NEW_CONTENT_PLACE | [馆藏 n286](https://archive.org/details/northernfrance00karl/page/n286/mode/1up) |
| `place:argentan` | Argentan | 48.74441, -0.02023 | NEW_CONTENT_PLACE | [馆藏 n291](https://archive.org/details/northernfrance00karl/page/n291/mode/1up) |
