# Ten-Year Timing Verification + Global Strategic Geography R1

RESULT: **COMPLETED**（Global Strategic Geography R1已进入正式Windows Release）。Phase A结论仍为 **INCONCLUSIVE_ENVIRONMENT_SENSITIVITY**；旧Relief NOT_PASS不被改写。本轮完整统一验证和原240秒十年检查通过。

## PHASE A — A–F

[完整十年报告](ten-year-timing-verification-r1.md)逐次列出14次完整运行、原调用路径、domain CPU/cycles、wall差异、环境限制和保存哈希。原240秒规则、测试计时区间与正式模拟算法保持不变。

- **A. TEN-YEAR CALL PATH**：WorldBootstrap.build → SimulationStep.advance_minutes；每日Clock / Spatial / Economy / Organization / wages，年度检查仍在原计时区间内。沿入口追踪的55个依赖类与冻结R2逐字节相同。
- **B. R2 / RELIEF PAIRED RUNS**：4个基础配对，首对主线程CPU测量失败的预实验保留但不采信；另3个完整domain配对。14次原测试均40项检查、0失败，原loop wall为173.191–209.986秒。逐次数据见上述报告，不混合两种harness。
- **C. DOMAIN CPU COST**：三个domain配对CPU中位数R2 / Relief：Economy132.219 /134.375秒，Organization review21.781 /24.109，Spatial6.484 /6.250，Personal wages0.109 /0.125。CPU tick量化为15.625ms，需同时阅读周期数和调用wall；Population独立读取成本不可单独量测。正式owner执行3650次每日domain、3660次wages，没有禁用domain。
- **D. WALL-CLOCK VARIANCE**：基础pair2–4 R2为183.804/184.495/203.828秒，Relief207.071/209.986/175.233，快慢关系反转。AC供电、Balanced scheme、聚合P-state/counter和后台CPU被动记录；没有可靠线程有效频率、温度/降频归因。
- **E. RELIEF INVOLVEMENT**：十年路径没有执行Relief/renderer/texture/GPU准备；只读缓存检查带positive control。HistoricalLoader / GeographyLoader类型依赖可能在解析时缓存，不等于执行加载/解码。完整save、恢复save、fingerprint、年度经济结果14次完全相同。
- **F. PHASE A DECISION**：**INCONCLUSIVE_ENVIRONMENT_SENSITIVITY**。满足用户规定的C→B条件，但不能把旧244/276/286秒失败归因于已确认的环境原因；旧Relief的NOT_PASS不改写。

14次完整十年原计时逐次记录（秒；全部原40项检查、exit0）：

|Run|loop wall|main CPU|process CPU|
|---|---:|---:|---:|
|canonical-01-r2|185.267|INVALID PILOT|185.234|
|canonical-01-relief|174.876|INVALID PILOT|174.438|
|canonical-02-r2|183.804|180.734|183.000|
|canonical-02-relief|207.071|202.969|205.188|
|canonical-03-r2|184.495|181.750|184.141|
|canonical-03-relief|209.986|205.156|207.766|
|canonical-04-r2|203.828|200.000|202.641|
|canonical-04-relief|175.233|173.688|175.969|
|diagnostic-01-r2|182.094|176.875|179.297|
|diagnostic-01-relief|180.415|175.375|177.688|
|diagnostic-02-r2|175.943|171.203|173.562|
|diagnostic-02-relief|181.315|175.594|177.672|
|diagnostic-03-r2|173.191|168.781|171.000|
|diagnostic-03-relief|174.586|169.031|171.109|

## PHASE B

### G. GLOBAL DATA SOURCES

[数据说明](../data/global-strategic-geography-r1.md)和[逐项来源审查](../data/global-strategic-source-review.json)包含出版机构、版本/日期、许可、catalog/页码、检索、变换、历史适用性和不确定度。运行数据使用既有HistoricalSourceRegistry / HistoricalEvidenceCatalog / HistoricalProvenanceGate。

|来源|日期、机构、使用状态|用途|
|---|---|---|
|[Philadelphia Public Ledger's Unrivaled Atlas](https://archive.org/details/philadelphiapubl00rand)|1899，Rand McNally；Allen County Public Library馆藏；公有领域，部分版图1894/95|城市/chief-city表、港口和已绘铁路连通证据|
|[China and adjoining regions](https://www.loc.gov/item/2006458350/)|1898，Weller / Royal Geographical Society；LOC G7820 1898 .W4；公有领域/自由复用|Hankow身份、既有Pekin–Tientsin；审查现有/施工/许可/建议线图例|
|[Pocket Atlas … Through Asia](https://www.loc.gov/item/2018694173/)|1900，Russian State Library / LOC WDL；公有领域/自由复用|目录明确铁路到Irkutsk、东部未完成；只纳入Omsk–Irkutsk宏观联系|
|[Natural Earth v5.1.2](https://github.com/nvkelso/natural-earth-vector/tree/v5.1.2)|2022-05-13 tag commit f1890d9；[公有领域](https://www.naturalearthdata.com/about/terms-of-use/)|50m River类、天然湖泊、Caspian物理水域；PHYSICAL_REFERENCE|
|Natural Earth10m populated places|同一固定版本，公有领域|仅坐标辅助REFERENCE_ONLY；未使用现代人口/排名/行政归属证明1900身份|
|既有Paris GeoNames locator|原2026检索，CC-BY-4.0，保留原来源记录及署名|五个共享Paris城市定位；保留原Local精确坐标和稳定ID|

检索2026-10-07。原扫描、OCR、目录和GIS归档136,815,892 bytes，仅开发证据，不进入发行包。历史扫描用于身份/拓扑，未声称从扫描测绘出真实轨道。

### H. STRATEGIC SETTLEMENTS

124个战略城市/重要城镇，依据同期地图、chief-city表、港口和铁路节点身份筛选。31个复用既有place ID，93个新ID；无local:*平行空间，无重复stable ID。Paris五个共享点优先复用Local定位；其余独立历史身份与现代坐标辅助分开记录。代表性定位误差通常0.5–5km、都会别名可达15km；显示rank是Presentation选择，不是人口事实。不存在从现代城市人口排名推出1900重要性的路径。

### I. RIVERS / LAKES

30个命名河流feature、19个天然湖泊/水域feature，若干feature包含多个source record/line/ring。Seine/Rhine/Danube/Volga、Yangtze/Yellow、Ganges/Indus、Nile、Amazon、Mississippi等用于战略骨架。只采用Natural Earth River类别，不把Lake Centerline作为1900河道；现代水库、Aral残片、Salton Sea、IJsselmeer排除。Caspian来自50m ocean的对应物理多边形。

均为**PHYSICAL_REFERENCE**：可用于大尺度排水轴与天然水域空间参照，不能作为1900精确河岸、水位、航运能力或行政归属。下游Dnieper以及部分Volga调控河段存在资料断裂，保留缺口。

### J. RAILWAY CORRIDORS

32条全球宏观连接：30条atlas依据、1条Pekin–Tientsin、1条Omsk–Irkutsk。所有点列与声明的places/定位一致；虚线标为**APPROXIMATE_STRATEGIC_CORRIDOR**。历史存在/拓扑与几何**BOUNDED_ASSUMPTION**明确分开；误差可为几十至几百公里，不能供实际寻路、运输成本或军事移动算法使用。没有运营商、车站、容量的虚构字段。

美国1869主干经Ogden至Oakland；不把Salt Lake作为原主线站、不把San Francisco渡轮画成铁路。New York–Chicago宏观连接经Philadelphia，避免跨Lake Erie。中国建议/施工干线不纳入；没有虚构贯通1900年Baikal/东部的Trans-Siberian。法国Local九条走廊/十一部分仍引用唯一原稳定身份，没有另造global法国铁路。

### K. COASTLINE

全球中尺度独立物理岸线本轮**DEFER**。已有ETOPO relief物理参考和Paris Local岸线继续使用；既有CShapes粗政治几何仍可在别处看到粗岸缘，但不声称成为细physical coastline，不决定水域所有权。

### L. HISTORICAL APPLICABILITY

城市身份/铁路连通是**HISTORICAL_EVIDENCE**；城市代表坐标是**REFERENCE_ONLY**；虚线宏观铁路形状是**BOUNDED_ASSUMPTION**；现代天然河湖为**PHYSICAL_REFERENCE**。全套circa1900显示snapshot的validity为1900-01-01≤date<1901-01-01，不声称该范围是城市创立/消失时间。跨出有效日期停止显示；不会把该1900层永久外推。

### M. DATA COUNTS

|正式新增global数据|数量|
|---|---:|
|settlements|124|
|rail corridors|32|
|river features|30|
|lake / major water features|19|
|总feature|205|
|geographic Content slices|9|
|原几何坐标数|10480|
|两个离线LOD坐标合计|9018|
|runtime index+shards bytes|831440|
|duplicate stable IDs|0|
|admin polygons / roads /新Local shard|0 /0 /0|

Paris原53城镇、9rail corridor/11parts不计为新增全球重复事实。

### N. RUNTIME ORGANIZATION

Content index+九片地域分片，不是第二套World或行政区域。loader只绑定证据、日期、ID和几何；Presentation复用现有LocalSpatialLayer/LocalSpatialLod及static batch。coarse5000m /medium1500m在生产时离线简化，引用相同feature/source fact；runtime不做camera-triggered simplification。湖泊三角化在一次性准备worker，静态water batch没有political owner。

WORLD不显示新增全球骨架；REGION FAR先出较少城市/河湖，MID渐入虚线rail和更多城市。major/secondary城市rank对应8000/6000/2600mpp可见上界；river8500→4000、lake8500→5500、rail4200→2200mpp连续权重。flag/political/relief已有曲线保持；LOCAL仅由原Paris支撑。

### O. RESOURCE LIFECYCLE

人物启动0 strategic文件读取。进入Region按当前camera范围选择当前及邻近片，最多2片；CPU保留此有限Content及两份小LOD点列，GPU仅当前LOD。切换LOD释放旧GPU；离开地域丢弃旧Content；隐藏地图/回World释放该层CPU/GPU。worker过时结果被丢弃，idle结束_process和地图redraw。每次旅行加载的累计admission计数会增长，不能误认累计计数是当前驻留资源。

行政资料仍缺；不引入immutable Province、占领原子单位或每帧polygon union。未来Province为mutable administrative grouping，与sovereignty/controller/spatial aggregation分开，本轮不实现membership gameplay、grid或编辑器。

### P. GLOBAL TRAVEL

实际Release测量副本完成3轮Europe→East Asia→North America→South America→Africa→India→Japan→Europe。回到Europe三次：

|回程|working set bytes|private bytes|video monitor bytes|strategic GPU geometry estimate bytes|
|---|---:|---:|---:|---:|
|0|543154176|780619776|166526441|621264|
|1|543248384|780619776|166526441|621264|
|2|543227904|780587008|166526441|621264|

三次均active Europe+Eurasia，82feature、1个GPU LOD；allocator/字体缓存的高水位没有随每次旅行继续累计。全程完整World/save不变。正式测试也执行三轮并检查≤2片、≤1 GPU LOD、隐藏释放。

### Q. PERFORMANCE

Windows原生Release，Godot4.6.3 Compatibility/OpenGL3.3，NVIDIA RTX3050 Laptop /572.83，1280×720。idle60秒、pan/zoom各30秒；CPU是20逻辑核整机百分比，GPU为Windows进程engine利用率。

|范围|pan p95 ms|zoom p95 ms|pan CPU %|zoom CPU %|
|---|---:|---:|---:|---:|
|Europe|18.029|18.388|3.618|3.873|
|East Asia|17.672|17.983|3.173|3.119|
|North America|17.694|17.718|2.682|2.918|
|Paris Local|17.847|17.738|2.829|3.176|
|修复water/遮罩后Great Lakes|17.687|17.676|3.414|3.320|
|修复后WORLD|18.212|17.781|3.028|3.109|
|修复后Paris Local|17.688|17.743|2.907|3.047|
|最终逐字节相同的显示代码/数据，Great Lakes|17.809|17.794|3.329|3.659|

完整主测pan/zoom max≤29.759ms；后续WORLD/GreatLakes/Local补测max≤37.604ms，没有持续50/100/500ms卡顿。一次WORLD idle样本max41.511ms，未隐藏此离群值。

冻结Relief与新增层同位置(-85,43)、1200mpp短配对（各8秒）：pan p95 **17.764→17.821ms**、GPU14.68→16.84%，video165557825→166327973 bytes。短样本不是60秒idle验收，也不能用不同整机功耗/进程RAM高水位推断确定改善。此前Relief的30秒Region/Local基线约17.68–17.95ms，与本轮Europe中心不同，非严格同场景对照。

主测后做过城市定位归因/少量定位修正、water-only来源caption和Region标签来源缓存修复；最终版本另做60秒idle、30秒pan、30秒zoom原生Release补测（caption/），完整主测数字不冒称来自最后逐字节相同的构建。最终补测snapshot完全相同、exit0、无运行错误。

### R. IDLE POWER

|60秒idle|CPU %中位数|process GPU %中位数|整块NVIDIA板功耗W|地图draw增量|
|---|---:|---:|---:|---:|
|Europe|0.114|0|3.405|0|
|East Asia|0.172|0|3.420|0|
|North America|0.133|0|3.430|0|
|Paris Local|0.116|0|3.420|0|
|补测Great Lakes|0.133|0|3.400|0|
|补测WORLD|0.131|0|3.400|0|
|最终代码/数据Great Lakes|0.185|0|3.380|0|

回人物30秒CPU0.121%、processGPU0%、板功耗3.44W，地图draw0且GPU数据释放。板功耗不是进程功耗；没有证明独占GPU功耗改善。没有idle持续map redraw、provenance、文件parse或geometry rebuild。

### S. MEMORY / GPU / PREPARATION

Europe两片：coarse PackedVector3点列26640 bytes，363线段、GPU静态geometry估计280392 bytes；medium点列54828 bytes，942线段、GPU估计621264 bytes。两份有限CPU点列合计81468 bytes；GPU不会把两级叠加驻留。geometry数字来自buffer/texture容量估计，不冒充单独驱动分配量。decoded JSON、label/font、mesh/material开销另计，不能把点列数冒充全部RAM。

主测Europe至NA working set约545–552MB、private782–789MB；Paris Local约607MB /860MB。补测全地域/字体及Local高水位达669MB /900MB，OS/allocator高水位不等同净新增数据成本。短配对WS约564→594MB，包含非隔离字体/allocator差异；video净差770148 bytes仅是该同位置短样本。

最终Great Lakes idle：OS working set617111552、private859602944 bytes；Windows GPU Process Memory dedicated202633216 /shared63528960 bytes；Godot video monitor164198017 bytes。这些是整进程/驱动口径，不能与上述只计算新增几何的估计混用或把shared memory当纯VRAM。

首次Europe coarse实际：read0.994ms、parse8.177ms、source admission71.566ms(worker)、Content几何准备1.107ms(worker)，worker83.512ms；LOD worker5.855ms；label准备7.254ms合计、GPU命令提交12.215ms合计均分帧。首次可见234.279ms，首次最大主线程准备片4.813ms；全主测最大准备片8.742ms。GPU enqueue不是可单独证明的硬件upload完成时间。后续medium elapsed包含观察coarse的0.5秒等待，不作为首次加载耗时。

### T. RELEASE SIZE

正式产品：`builds/windows/wwo-global-strategic-geography-r1.exe`，173036160 bytes；Relief基线172184200 bytes；**delta851960 bytes**（约0.813MiB）。export exit0。SHA256：`200339e5a97384b0b9422a1db91d9b08700680960eed467f1a2514786fa9add3`。

PCK770条，10份战略JSON、原Paris shard及两份Relief payload逐字节核对一致。无tests/tools/docs/local-artifacts/builds条目，原始扫描/GIS未打包；main_scene仍为正式菜单。package-audit.json记录所有核对哈希。导出仍有既有config/version=0.001a格式警告，未改版本/存档规则；无导出错误。

### U. VISUAL EVIDENCE

`local-artifacts/global-strategic-r1/after/`：九地区各WORLD、FAR4500mpp、MID1200mpp，共27图；另Paris Region/Local far/close、Beijing/New York保持Region。`delivery/`为十个更有代表性的城市/河湖MID补图及最终Local。最终caption/正式菜单旅程另存。

[完整原生截图序列](global-strategic-geography-r1-visuals.html)按地区并列WORLD/FAR/MID，附河湖/城市补图、最终三个map mode和正式菜单截图。caption/中的Caspian即使无城市也显示physical reference提示。native-menu/person/world/region-far/region-mid.png是正式产品入口及真实滚轮/拖动旅程，非测量入口替代产品菜单。额外手动Economy点击被系统截图浮层拦截，未把该点击记为通过；三个mode另由最终原生caption旅程成功验证。

|地区|MID可见信息 / 限制|
|---|---|
|西欧|历史城市、Rhine/Danube/Seine骨架、dated虚线走廊；Paris使用原Local精度|
|东欧/俄罗斯|Moscow等城市、Volga、有限macro rail；Dnieper下游缺口|
|中国|Pekin/Tientsin和已存在单条rail；大河参照；未画建议trunk|
|日本|Tokyo/Osaka/Kobe等节点、日期审查走廊；战略选择集|
|印度|Agra/Allahabad/Benares/Calcutta、Ganges及宏观rail|
|北美|Chicago/Toronto、Great Lakes、Mississippi与虚线rail|
|南美|Amazon物理参照；Argentina补图Buenos Aires/Rosario等、宏观rail|
|北非|Cairo/Alexandria/Port Said、Nile参照、有限rail|
|南非|Pretoria/Johannesburg/Bloemfontein/Kimberley/Durban节点与走廊|

城市/河流不是填满所有视窗的纹理：某些1200mpp乡野中心仍较空。WORLD不因新增124点信息爆炸；同一数据在FAR/MID增加信息、标签碰撞沿既有机制。Caspian/湖泊内部三角缝已通过不透明water fill修正。

### V. PARIS COMPATIBILITY

原53towns、9rail corridor/11parts、河流/岸线和稳定place:paris仍为唯一Local。共享city ID/locator、唯一French rail引用；Presentation压低Paris300km范围内全球河流与共享城市重复，Local使用原细线。此范围mask会一并隐藏同范围其他global水系，属于显示简化限制，不更改事实。Paris Local pan/zoom保持约60FPS；Beijing/New York不授予Local。

### W. WORLD FACTS

新增只进入Content→Presentation。没有sovereignty/controller/admin membership、工厂/市场/贸易流/军事unit/grid或其他新authoritative事实。55个模拟依赖文件和所有既有canonical data与冻结R2/Relief复核无变化，证据simulation-boundary-audit.json。行政边界缺失仍为**ADMIN_BOUNDARY_DATA_GAP**，没有Natural Earth admin1替代。

### X. SAVE

formal_world_simulation_v14不变。14次十年完整save SHA256一致：49b506ba3c671e76db6c10c29a673fc7248efe4aee015d0ac2a1d47e5870e288；fingerprint f8ddb8968d598efdc9811b4a761750f3596540f666d9fefa0f6eae523c77bd4a。所有原生测量副本完整snapshot前后相同；正式内容测试检查全save equality。没有持久化LOD/加载状态。

### Y. VALIDATION

首次统一验证发现Region重复redraw新增两条旧prototype城市glyph（23而非21）。正式Region现在从admitted spatial content提供城市label source，旧prototype仍可供独立fixture；修复后原尺度切换测试1280检查、0失败，未修改原断言。

最终统一验证 **exit0**，28个正式suite、30096 checks、0 failures，编辑器import及engine/log scan通过。另含Python静态审计、deterministic provenance generation、world-data regressions、四类跨进程hash/fingerprint与正式headless启动检查。

|检查|checks / failures|
|---|---:|
|Map rendering|745 /0|
|Map scale transition|1280 /0|
|Map Local foundation|68 /0|
|Paris Local Content|6537 /0|
|Scale utilization|13577 /0|
|Resource efficiency R2|47 /0|
|Global Relief|1191 /0|
|Global Strategic Geography|2614 /0|
|Presentation boundary|60 /0|
|Population|476 /0|
|Spatial|35 /0|
|Exact Persistence|32 /0|
|Personal Economy|104 /0|
|Economy30-day /one-year golden|6 /0|
|World integration|67 /0|
|原十年balance|40 /0|

十年原区间 **221.575280秒≤240秒**，仍87600小时、699092 save bytes、年度fulfillment3194bp。原测试源码哈希未变；55个authoritative依赖和所有旧data哈希再次复核相同。原生after、delivery、before、caption四个正式Release测量过程exit0，完整snapshot equality通过；Windows最终产品菜单/新世界/人物/世界/真实Region进入及pan已观察，产品stderr无运行错误。

### Z. REMAINING DATA GAPS

- ADMIN_BOUNDARY_DATA_GAP：无正式1900行政多边形/成员配置。
- 全球独立medium coastline DEFER；别处仍受粗政治岸缘限制。
- 河流/天然湖水位和岸线为现代physical reference；Dnieper/Volga部分断裂、工程变化未重建。
- Rail仅dated macro topology，缺实际track geometry/companies/stations/容量；禁止用它进行真实空间寻路。
- 中国仅Pekin–Tientsin；Trans-Siberian东部/绕Baikal未贯通部分未纳入。
- 精选战略网络不覆盖全部城市/铁路；没有第二Local shard，较近乡野可空。
- 不按polygon/ISO/经济scope补猜新增城市的政治归属；既有本区域以外未解析的旧place political parent仍待独立证据审查。

## NEXT RECOMMENDATION

下一步建议单独立项 **Administrative Region Foundation R1**，先设计mutable administrative grouping与territory/control分离的初始配置。**不自动开始。**
