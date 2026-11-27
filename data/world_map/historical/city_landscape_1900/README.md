# 1900 年城市景观名录

[Issue #296](https://github.com/ryoumiyahayato/wwo/issues/296) 的第五批工作记录。状态为 IN_PROGRESS，分母尚未冻结。运行基线为 Build 144、提交 `3dce67233c0acaf4d2b3e7c1466d9282e26288bc`。本批尚无运行代码或正式资源变更。[第四批主线 CI](https://github.com/ryoumiyahayato/wwo/actions/runs/45856908832) [施工草稿 #303](https://github.com/ryoumiyahayato/wwo/pull/303)

## 名录读取

```powershell
python rust/strategic-host/tools/city_landscape_roster.py
python rust/strategic-host/tools/city_landscape_roster.py --city landscape:hankou
python rust/strategic-host/tools/city_landscape_roster.py --unit cshapes_gw_433
python rust/strategic-host/tools/city_landscape_roster.py --generate
```

普通查询只用 Python 标准库。重算需要本地 Shapely 2。输入为现有 `historical_population_1900` 的 cities、population、geography 和中文地名，按 `city_key` 关联。政治目录来自 `political_units_1900.json`，空间回退来自 CShapes。名录另存于景观目录，人口真值未改。

| 文件 | 用途 |
|---|---|
| roster.json | 情景时点、区域缺口和各生成文件入口 |
| candidates.jsonl | 候选身份、原统计和决定、采用值、档位及施工配置 |
| coverage.jsonl | 按政治单位记录城市统计、仅有行政合计或仍未找到城市统计 |
| political-screening.csv | 缺口单位分组、历史地名及别名、已查参照和口径限制 |
| supplement-sources.csv / supplement-population.csv | 补查资料、原统计年、适用口径与来源 |
| decisions.csv | 别名归并、跨档依据、历史辖区差异和排除理由 |
| site-plans.json | 可复用资产、每层覆盖、历史范围、运行时分片和各等级的建造方法 |
| b4-timing.tsv | 七条实际路线各三次的引擎、GPU 和阻塞等待摘要 |

开局为 1900-01-01。政治底图元数据为 1900-03-12，两日期均保留。采用 1895–1905 的可比参照，保留原年与开局年的差。窄口径近年普查优先，异口径读数列在比较字段。单次编纂估计保留为 P。暂无可比的跨年边界，未插值。只有明列的区间上限或调度依据可提前排期。X 包括低于门槛、同城重复、无近年城市级依据及同名统计范围冲突。只有含 D 或 P 的施工卡计入预审分母。

原检查点有 1,724 条候选，预审 297 城。按原始政治单位目录补核后，加入布哈拉为 P，暂列第九批。Hamilton 1906 年出版的资料估计其城区有 100,000 人，实际观察年未注明。Rickmers 的独立街区与住户估计为 80,000–100,000。1909 年另有 78,650 人的估计。原数与口径均保留。现行数字由上面的离线命令生成。分档和逐城边界继续核对。[Hamilton 第 29 页](https://www.gutenberg.org/cache/epub/73258/pg73258.txt) [Rickmers 第十二章](https://upload.wikimedia.org/wikipedia/commons/c/c2/The_Duab_of_Turkestan%3B_%28IA_duabofturkestan00rick%29.pdf)

台北、基隆、台南、嘉义、宜兰归入台湾政治单位。台北的 69,672 人为城内、艋舺和大稻埕三处现住人口之和。英国帝国普查补录 Newfoundland、Belize、Bathurst、Freetown、Kingston、Perth、Hobart、Bloemfontein 的城镇读数。Kingston 保留与 Port Royal 的联合估计作为上界。波斯尼亚、黑塞哥维那、尼泊尔、利比里亚、卢森堡及希瓦另有城市读数或越窗比较。覆盖记录列出找到的候选 ID 和处置。未知政治单位仍需核查。[英帝国普查表 3](https://www.tradeshouselibrary.org/uploads/4/7/7/2/47723681/census_of_the_british_empire._1901.pdf) [波黑普查汇编](https://prilozi.iis.unsa.ba/wp-content/uploads/2023/05/32-Prilozi-Naucnerasprave-RobertJ.Donia_.pdf)

原始 67 个未找到城市统计的单位均登记历史地名筛查。重算按同单位候选、其他辖区及地点目录分别列出匹配。检查英帝国普查、Hammond 城市索引、法属与德属殖民档案入口、马来亚普查目录及部分地方表。档案目录和无年份的汇编只作参照。没有匹配的城市仍保留未知记录。波多黎各和苏里南补录八个地方读数，最大分别为圣胡安 32,048 人和帕拉马里博 31,817 人。两者均保留原统计覆盖。[波多黎各 1899 普查](https://www2.census.gov/library/publications/decennial/island-areas/1899/1899-census-porto-rico.pdf) [苏里南殖民报告](https://repository.overheid.nl/frbr/sgd/19011902/0000365065/1/pdf/SGD_19011902_0001296.pdf)

河内和阿贝奥库塔增加为 P。河内 1900 年序列值 103,000，Chandler 估计 72,000，分别保存。阿贝奥库塔的近时出版估计为 100,000 至 150,000，Chandler 为 60,000。保留 Egba 的历史归属；1900 年外缘用旧聚落、奥卢莫岩、奥贡河和地形约束。河内按老商业街区、升龙城址、还剑湖和红河区分施工单元，龙编桥当时尚未开通。塔那那利佛继续 X，采用 1905 年列为 61,068 人的首都范围，保留口径未明的高估比较。[河内人口表](https://www.ier.hit-u.ac.jp/COE/Japanese/discussionpapers/DP98.7/6.htm) [河内 1900 年档案图](https://luutruquocgia1.org.vn/wp-content/uploads/2016/11/Kien-truc-cac-cong-trinh-xay-dung-tai-Ha-Noi.pdf) [Hammond 城市表](https://www.columbia.edu/cu/lweb/digital/collections/cul/texts/ldpd_8527324_000/pages/ldpd_8527324_000_00000076.html) [马达加斯加行政统计摘要](https://www.persee.fr/doc/geo_0003-4010_1906_num_15_84_3531?pageId=T1_475)

意大利 1901 年普查表 XI 以主城人口替换 11 个入选城市的旧选用值。七城改为 D。那不勒斯、热那亚、佛罗伦萨和墨西拿的市辖区人口跨过施工门槛，继续以 P 排在第七、第八、第八、第九批，连续建成范围仍待核。利沃诺主城 85,102 人，全市辖区 93,321 人，继续排除。保留原编纂值和原城市 ID。

四座跨档城市的施工卡补录历史地图入口和待查单元。那不勒斯使用 1901 年城市图，热那亚和佛罗伦萨保留馆藏索引，墨西拿使用 1908 年测绘节选对照港口和西侧空地。四城仍待核实有效覆盖和外缘，墨西拿须剔除震后重建。[那不勒斯 1901 年地图](https://www.davidrumsey.com/luna/servlet/detail/RUMSEY~8~1~273903~90047256) [墨西拿 1908 年图幅](https://www.agenziademanio.it/export/sites/demanio/download/documentigare_2021_3/S0_INQ.CART.STORICO-1.pdf)

意大利 1901 年普查表 XI 列锡拉库萨（`reba:chandler:1362`）主城 23,247 人，全市辖区 32,030 人。该条由 P 改 X，原 108,000 人编纂值保留为比较。纽约州锡拉丘兹（`us_city_new_york_syracuse`）1900 年普查 108,374 人，保留第九批及独立 ID。第九批预审减少一城，正式分母待冻结。[意大利普查表 XI](https://ebiblio.istat.it/digibib/Censimenti%20popolazione/censpop1901/ist7957cp1901_v5_Relazione_sul_metodo_di_esecuzione_e_sui_risultati_del_censimento%2BOCR_ottimizzato.pdf) [美国普查公告 65 表 2](https://www2.census.gov/library/publications/decennial/1900/bulletins/demographic/65-population-incorporated-places.pdf)

帕特森、斯克兰顿、福尔里弗、罗切斯特及纽约州锡拉丘兹已登记近年图源与施工单元。分别核对引水渠、铁路货场、纺织厂带、河谷与运河。历史外缘和道路有效覆盖待核。[帕特森 1899 年图](https://www.loc.gov/item/sanborn05590_003/) [罗切斯特 1900 年地图服务](https://gis.cityofrochester.gov/arcgis/rest/services/HistoricPlatMaps/ROC_HistoricPlatMaps_1900/MapServer)

荷兰 1899 年 12 月 31 日普查记录阿姆斯特丹 510,853 人、鹿特丹 318,507 人、海牙 206,022 人、乌得勒支 102,086 人。四地改为 D，沿用第七、八、八、九批。原编纂值保留为比较。阿姆斯特丹卡已登记两幅近年图及四个施工单元，仍需核实外缘和道路有效覆盖。普查采用当时市辖范围，已并入的空地仍需按地物证据保留。[荷兰统计局普查表](https://www.cbs.nl/nl-nl/cijfers/detail/7377vt?dl=AFBAF) [阿姆斯特丹市档案馆](https://www.amsterdam.nl/stadsarchief/stukken/kaarten/amsterdam-1894/)

柏林、北京、上海、汉堡和阿尔托纳的卡已登记近年图源、资料适用范围和施工单元。柏林内城综合图跨 1899–1913 年，需要逐项核实年代。北京内城图和上海租界图分别只有部分有效范围。汉堡和阿尔托纳可对照同一张图，保留各自的历史城市 ID。图源核对尚未生成有效覆盖面，也未更改数据等级。

匹兹堡与阿勒格尼采用各自的 Sanborn 图，与 1899 年两城总图对照。阿勒格尼于 1907 年并入匹兹堡，1900 年仍使用独立城市 ID。纽瓦克与泽西市分别核对街区，再核对湿地、铁路与渡轮。纽瓦克港 1915 年开始的工程排除。四城仅新增史料入口与近似锚点，有效覆盖和实际外缘待核。[1899 年两城总图](https://www.davidrumsey.com/luna/servlet/detail/RUMSEY~8~1~353200~90120494) [新泽西历史地图索引](https://dep.nj.gov/njgws/technical/historical-maps/)

巴黎和伦敦的 B4 城市资产在现有目录。柏林、北京已有原创建筑模块和局部景观，已有首都/地标名单及现场范围另见 [CAPITAL_LANDSCAPE_1900.md](../../../../rust/strategic-host/CAPITAL_LANDSCAPE_1900.md)。泰晤士河对岸独立自治市、Brooklyn 1898 年并入、鲁尔跨城聚合、Elberfeld/Barmen 1929 年并入及汉口/武昌/汉阳分别保留身份关系。汉阳仍缺 1900 前后可分拆的人口。加尔各答与孟买复用了现有地点 ID。

法国和西班牙本机参考瓦片有明确采集窗，属近现代参照。只用于定位经历史依据证实的地物，不用于确认其历史建成区或道路存在。英国道路与建筑资料的缺口分开记录。湖面、公园、海湾和有证据的空地可作为有效空白。资料裁边和历史郊缘分别标注。区域缺口保留在名录头；没有可比城市统计的地区继续补资料，不能推导为没有可施工城市。现有目录的行政几何只用于匹配政治和统计单位。

北美预审 40 城均登记具名施工单元。本次补 29 城，15 城已登记有测绘年代的地方图源，14 城已有具名空间约束并保留图幅核对待办。具体将港岸、铁路堆场、台地住宅与空地分开。未量出的道路有效覆盖仍为未知，Sanborn 图幅拼接线不作历史郊缘。

不列颠群岛及大洋洲预审城市均登记具名核心、普通街区和两个边缘样区。本次补 36 张不列颠群岛卡及 4 张澳大利亚卡。不列颠群岛按六英寸图定位路网和地物，用二十五英寸图核实小路、房屋及实际覆盖。每幅图单独核对测绘与修订时间。澳大利亚分别登记悉尼、阿德莱德、布里斯班、墨尔本的城市测绘档案，明确水岸、港口、开敞公园和独立近郊边界。图源已登记，未数字化其有效覆盖。

南亚 28 城、东南亚 10 城和中亚 2 城均已有具名施工单元。本次补 28 张南亚卡及 7 张东南亚卡。印度图册按城图区分道路、街廓及外缘，省图只作主干和地形约束。南亚城镇与兵营各用独立建设范围，保留其间空地。曼谷、新加坡、巴达维亚、泗水、梭罗和仰光分别登记近年图源与水系约束。道路矢量及各图层边界待逐幅核实。

东亚预审 35 城均已有具名施工单元。本次补了 25 张卡。东京采用 1895–1897 年分区测图，天津采用 1899 年城厢图，首尔用晚 19 世纪城图与城墙档案。清末城市缺详细实测图时，以城墙、现存可追溯地物、水系和历史城史约束施工单元。晚期地形图只用于定位或对照。编制器优先用卡内具名核心作施工定位，保留原统计坐标。例如无锡的原坐标与旧城核心相差约 9 公里。

西亚与北非 13 城、撒哈拉以南非洲 4 城、拉美 14 城均有具名施工卡。本次补 26 城。从市区测绘资料登记历史海岸、河道、旧城交通线及开放土地。里约热内卢采用 1900 年军用测绘图，修正旧卡纬度符号。[里约热内卢 1900 年图](https://www.loc.gov/item/2012593122/)

欧洲大陆新增 102 张具名施工卡。新增德国原测地形图、奥匈第三及第四次军事测图、瑞士 Siegfried 图册、俄罗斯城市图、布加勒斯特实测图及伊斯坦布尔 Huber 图。全部施工城都登记了核心、普通街区和两个边缘。具名点作为施工与取景的定位，外围建成区依据同年或邻年可核实街廓、道路、墙体、水岸与地形逐单元识别。扫描页覆盖、测绘源内部缺口和历史边界各自记录。罗斯托夫原统计定位距历史核心约 23 公里，程序使用施工定位计算相邻目标。[德国地图索引](https://leibniz-ifl.de/forschung/infrastrukturen/bibliothek/kartensammlung/tk-125000-des-deutschen-reichs) [奥匈历史测图](https://www.bev.gv.at/Services/Produkte/Landkarten/Historische-Landkarten.html) [伊斯坦布尔市档案](https://sehirplanlama.ibb.istanbul/beyoglu-arsivi-haritalar/)

## B4 实测

- 正式 EXE 为 Build 144，路径为 `D:/programs/WWO/wwo/local-artifacts/strategic-map-phase4/wwo-map-lab.exe`。实际启动的窗口标题和 GitHub Windows CI 一致。数据来自 `D:/programs/WWO/wwo-cold-restore/runtime-97ebaf1003/data`。
- i7-13700H，RTX 3050 Laptop GPU，专用显存 4 GiB，Vulkan，NVIDIA 572.83。物理内存 16,886,784,000 字节，Phison E21 PCIe 4.0 SSD，接交流电，平衡电源计划。显示器为 1920×1080、144 Hz，后台可见游戏窗口为 1280×720，FIFO。使用正式存档，1900-01-01 地理模式、地图北向俯视、暂停、速度档 1。
- 复用 `capture_z7_pages.py` 的观察接口。每条路线连续至少 60 秒，重新启动进程重复三次。计时期间未按帧截图。固定位置为巴黎 (2.326, 48.864)、伦敦 (−0.1339, 51.5031)、巴黎北缘 (2.412, 48.920)、索洛涅 (1.958, 47.543)、威尔德 (0.682, 51.066)。稳态用 1.760573 米/像素。运动从 77 米/像素逐级至 1.760573 米/像素，左右各拖动 228 像素再反向缩放。原始日志保存在本机 `D:/programs/WWO/WWO-landscape-review/batch5-b4`。
- 下表的帧间隔是应用成功提交帧之间的计时。GPU 数字来自时间戳。绘制墙钟减 swapchain acquire 后仍含驱动和提交接口开销，独立记录于 TSV。PresentMon 2.6.0 的 ETW 会话返回 access denied，缺少管理员或 Performance Log Users 权限。实际显示间隔、城市专属 CPU/GPU 工作集字节数均未实测。不能用进程内存、GPU 时间或引擎提交间隔替代这些量。
- 进程峰值工作集 1,489,186,816 字节，采样私有字节最大 3,018,772,480。均含完整游戏与地貌。巴黎近景观察到 QPK 63 页约 116 MB，伦敦 34 页约 60 MB。QPK 页不计作 WCB 页。
- 每次从已启动进程中的正式世界定位，巴黎地表/水体概览就绪 0.593–0.625 秒，随后的 19 次缩放与地表/水体近景探针 2.719–2.735 秒。伦敦相应为 0.406–0.703 秒和 2.562–2.703 秒。探针的读取时刻有建筑实例数，初测未以应加载的 WCB 资源全集判定就绪。系统文件缓存未清空。
- 另做三轮强制重新加载后折返。先从城市近景前往索洛涅，再用 F11 重载资源。回到巴黎后概览 0.219–0.250 秒，地表、水体与该相机预期的近景建筑实例 2.828–2.875 秒。伦敦相应为 0.219–0.250 秒和 2.890–2.922 秒。均从定位请求计时。该探针没有验证自然驱逐和逐页 CPU/GPU 驻留字节。
- 正式资源目录列出巴黎 94 个、伦敦 507 个外置 WCB 页。目录页数用于选路线。`Catalogue::visible` 在允许城市模型的视距和日期内，缓存超过 192 页才清理视域外 CPU 页。渲染模型缓存另有 2 秒离场保留条件。自然驱逐折返须确认两个驻留集均已卸载。F11 会替换城市目录，已有 F11 计时单列。

| 路线 | 引擎 P95 ms | 引擎 P99 ms | GPU P95 ms | 最大间隔 ms | >50 / >100 ms |
|---|---:|---:|---:|---:|---:|
| 巴黎稳态 | 33.39 | 34.01 | 31.76 | 43.02 | 0 / 0 |
| 巴黎缩放平移 | 36.30 | 68.49 | 35.76 | 94.35 | 437 / 0 |
| 伦敦稳态 | 16.99 | 17.63 | 15.75 | 29.71 | 0 / 0 |
| 伦敦缩放平移 | 20.67 | 33.33 | 19.69 | 80.76 | 5 / 0 |
| 巴黎北缘 | 7.95 | 10.81 | 6.20 | 38.38 | 0 / 0 |
| 索洛涅 | 7.38 | 7.72 | 4.10 | 14.91 | 0 / 0 |
| 威尔德 | 7.36 | 7.60 | 2.67 | 20.45 | 0 / 0 |

百分位为三次路线的中位数。最大值取三次最高值，长帧数取三次合计。巴黎稳态 GPU 时间已超过第六批的显示帧间隔目标。运动中有长帧与地表切换同时出现，观察接口没有逐帧 WCB 调度归因，不能据此把每个长帧归给读盘。不得按 GPU 的倒数报告实测帧率。

## B4 测量交接

以下三项交给 [第六批 #297](https://github.com/ryoumiyahayato/wwo/issues/297)。原始文件仅在本机 `D:/programs/WWO/WWO-landscape-review/batch5-b4`。固定路线见 `routes.json`、`run-1.json` 至 `run-3.json` 及 21 个路线采样归档。现有引擎和 GPU 汇总见 `b4-timing.tsv`。

| 专项 | 状态与原始记录 | 第六批执行条件 |
|---|---|---|
| 实际显示间隔 | NOT_MEASURED。PresentMon 2.6.0 的 ETW 会话返回 access denied，见 `presentmon-etw-access.txt`。 | 在同设备用获授权的会话记录实际显示事件。沿用固定路线、分辨率、刷新率和 FIFO，分别保留 B4 引擎计时和显示事件。 |
| 自然驱逐后折返 | NOT_MEASURED。`return-probes.json` 的 6 次样本使用 F11 强制重载。 | 从可触发常规驱逐的路线离城。观测目标城市页退出 CPU 目录缓存和 GPU 模型缓存。定位返城请求后分别计量概览和视域应有细节就绪。 |
| 城市独立 CPU/GPU 工作集 | NOT_MEASURED。现有 `run-1.json` 至 `run-3.json` 有进程计数及 GPU 耗时。 | 在城市目录、页加载和渲染模型缓存按城归集驻留与临时字节。共享资源去重，区分读入、解压、待上传及待释放。 |

## 第六批需要的接口

| 现状 | 最小修改 |
|---|---|
| `city_models.rs` 每帧线性筛页、排序后最多 192 页，后台最多 6 个页任务。到达 155 米/像素及情景日期窗时切换。内容替换仍依赖已驻留 WCB 的矩形。 | 按稳定城市 ID 和视域查询页索引。用实际有效覆盖决定接替，按距离、LOD、字节与准备耗时排序。保持 192 页、6 任务的起始上限，主线程每帧 2 ms。 |
| F11 执行 `Catalogue::reload`，在主线程读取并解压视域内 WCB。普通页加载启动每页线程。 | 复用现有后台加载，旧请求过期即作废。新目录就绪后原子切换。统计队列、解压、CPU/GPU 同步高水位及释放。 |
| `build_city_models.py` 使用 1,024 米网格与每页最多 12,000 建筑记录。现有巴黎、伦敦需保持行为。 | 继续使用同一坐标底座和原 WCB/地表入口。片内共享建筑模块、屋顶和材质。将每页城市 ID、年代、资料等级和开敞空间引用写进现有目录的扩展字段。 |
| `globe.wgsl` 道路固定三源迭代。巴黎和伦敦各有经纬度裁剪框，栅格退让由矩形覆盖并集触发，样式在着色器按城市选择。 | 用道路资料记录驱动 tile、年代、等级、有效覆盖面、内部空洞和跨河依据。保留可靠老栅格，在同地点同类道路矢量就绪且资料可替代时交接。材质由页/道路携带地域和底材 ID。 |
| QSC 既有地表目录约 200 区域页，GPU 80 页。QWG/QHW 单独流式加载。 | 不扩大既有地表驻留。城市工作集单列，CPU 1 GiB、GPU 512 MiB 整体目标。视域查询 P95 ≤1 ms。保留现有地形、地物色彩、地图模式和郊外接替。 |

风险机位预选以原尺度条件复用。纽约为最高采用人口的北美目标，巴黎和伦敦为 B4 大型既有对照。英国工业带和 Essen/Dortmund、Elberfeld/Barmen 为相邻身份压力。上海、Hankou/Wuchang、Hong Kong 和 Valparaíso 覆盖河岸、港口和陡坡。Chongqing 覆盖双河夹山。以上为索引，未宣称各城已进入实机。

## 共享传输

共用上限 5,000,000,000 字节。唯一累计入口为 Issue #296。计量使用开工时 WLAN 的累计收发计数。暂不能分辨本机后台流，按接口读数差的上界计入。网页与 GitHub 连接器的远端源站流量留在服务端。两次连接器工单读取早于本地计量。地图、历史图页和工具链未下载到构建机，境内外站点只做索引和相关表页的浏览。未从 CI 下载 EXE。

B4 两城 WCB 含目录 5,685,672 字节，城市地表叠加层 2,884,596 字节。两城主要增量合计约 8.6 MB。按现阶段约 300 城、每城与 B4 平均相近估算，最终资源约 1.29 GB。若全部走单次归档再正式回传，两次传输约 2.57 GB。资料等级、城市大小和共用模块比例会改变实际值。为必要页、CI 交付与返工留约 1 GB 规划余量。各批优先用本机瓦片、史料索引、原创建筑和地形。同一变更包只传所需最小增量。当前无已安排尚未完成的必要二进制传输。

## 恢复位置

名录分支为 `codex/global-city-roster-1900`，基于 `3dce67233`，使用草稿 #303。核查其余政治单位、历史独立城市及逐城外缘、资料空洞和施工单元。名录核对完毕后冻结分母，经必需 CI 与审阅后合入。Build 144 继续作为正式运行对照。
