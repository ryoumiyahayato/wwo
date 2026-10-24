# WWO R51 — Central Asia and Russian Far East Terrain Reconstruction

日期：2026-10-19。Godot 4.6.3 Compatibility。先中亚、后远东，资源已进入原MapRelief和StrategicSpatialLoader。未启动R51游戏或运行性能基准。导出记录见文末。

## 继承、来源与范围

R48实际修正了概览选择、不同编码细片采样、荷兰1905水面显示框和法国下级行政共享边；奥匈、意大利没有扩库。R49欧洲俄罗斯、芬兰和北高加索没有施工。R50已建西伯利亚，并在一次获授权Debug定位后修正`LocalSpatialLod.prepare`水面分支的`Array[Dictionary]`赋值错误。它解释已观察到的工作线程无效返回；没有证据证明R47原生访问冲突、旧RID警告及全部巴黎无响应已经消失。R51静态核对未发现需要先解除的新增无限循环或无界上传路径，不追加运行授权。

复用R39唯一相机、24份coarse、有界medium，R42—R48欧洲地貌和R47图集。R50的ETOPO、GLO-90、WorldCover缓存、材质函数、原生Mip格式及水文生成器继续使用。885张R50细片通过原路径引用，没有复制或重新上传同一地理单元。R50原清单、原资产及预览保留。

中亚是有衰减邻带的地理支持域，外框44—92°E、30—56°N；实际南缘约34—40°N，并未按现代五国裁切。远东主域覆盖黑龙江、乌苏里江、滨海、鄂霍次克、萨哈林、堪察加及楚科奇；东北延伸到192°E（等于168°W）。为流域和山脊保留邻区资料，不表示完成中国、蒙古、朝鲜、日本或整个亚洲。

现有`political_units_1900.json`中布哈拉、希瓦仍为`protectorate / protected_state`，控制关系指向俄罗斯；不是普通俄国行省。清朝、朝鲜帝国、日本、阿富汗和波斯等原身份不变。萨哈林1900年与1905年以后不同；1875年条约、1895年声明及1905年条约的时间关系见[日俄外交文献汇编](https://www.mofa.go.jp/region/europe/russia/territory/edition92/period2.html)。本轮不套用现代千岛归属、不纳入阿拉斯加，也不把铁路、租借和军事影响变成主权。

| 实际资料 | 年代、坐标和采样 | 许可与用途 |
|---|---|---|
| [NOAA ETOPO 2022](https://www.ncei.noaa.gov/products/etopo-global-relief-model)已有60角秒surface GeoTIFF | 1998—2022等来源合成；WGS84经纬度、EGM2008正高米；60角秒约1853米南北间距，非近景测绘 | NOAA公开资料；作为全域连续高程和较粗概览，不从负高程判水 |
| [Copernicus GLO-90](https://registry.opendata.aws/copernicus-dem/) | 现代DSM，主要TanDEM-X 2011—2015并有填补；WGS84/G1150、EGM2008米；原纬向3角秒、经向随纬度变化。选定单元提取600×600/度（6角秒），显示重采样1/512度 | [GLO许可](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)；只分发衍生bin，保留署名；不是1900地形或米级DTM |
| [ESA WorldCover 2021 v200](https://esa-worldcover.org/en/data-access) | 原10米分类；新单元多数采用450×450/3度分类概览，失败重取225；R50缓存保留实际225或2250采样。最近邻，不插造类别 | CC BY 4.0，[DOI](https://doi.org/10.5281/zenodo.7254221)；仅现代自然覆盖参考 |
| Natural Earth rivers/lakes v5.1.2 | WGS84二维，1:10M概化；不是10米精度或单一年度测绘 | [公有领域](https://www.naturalearthdata.com/about/terms-of-use/)；实际河流轴线、天然分类湖面，保留源ID、孔洞和类别 |
| [Natural Earth historic Aral](https://github.com/nvkelso/natural-earth-vector/blob/v5.1.2/geojson/ne_10m_lakes_historic.geojson) | `ne_id=1159110427`，源日期原文`late 1950s`；WGS84，概化多边形 | 公有领域；萎缩前历史显示参考，**不是1900年岸线** |

中亚取源349项、远东450项，均含原缓存复用，最终失败0；这不是799份互不重复原始数据。原COG、坐标仿射、实际提取尺寸及来源记录留在`local-artifacts/asian-surface-r51/`与原R50制作目录，不进入PCK。没有取得或假称采用HydroRIVERS/HydroLAKES。

## 中亚地貌、水网与历史水面

哈萨克低缓地势、萨雷阿尔卡丘陵、乌斯秋尔特高原及边坡、里海低地、两大荒漠、费尔干纳盆地、天山和帕米尔均由同一绝对高程和坡面计算表达。选定GLO-90窗口包括乌斯秋尔特、萨雷阿尔卡、费尔干纳、伊塞克、天山和帕米尔；其他地区仍是ETOPO区域参考。山峰不单独拉伸，没有沙丘/山峰GLB。

中亚新增15个河流源记录、9个天然分类湖泊及1个历史咸海。61个既有R50对象复用。锡尔河等跨域记录仅复用R50实际裁入西伯利亚的部分；其余有来源线段进入R51，不能因原ID存在而漏掉整个下游。阿姆河、锡尔河的原始线位与历史咸海实际相交；水面内轴线退出，不合成入湖连接线。河宽仍是制图线宽。

**历史咸海限制：**源年代约比1900晚55—59年，源多边形没有岛屿孔洞，不能宣称恢复了1900年精确岸线、岛屿或水位。保留原资料；没有猜画岛屿。曾检索[1909年突厥斯坦地图目录](https://www.loc.gov/item/2021668612/)，未取得可配准原图，不作为运行几何。REGION显示明确标注1950年代后期参考，WORLD仍沿用现代概化物理基础，存在尺度参考年代差异。里海没有取得1900精确岸线。

源`Reservoir`全部不准入新天然湖面。另排除现代南/北咸海残水域、Barsakelmes残水域、Sarygamysh和Aydar-Arnasay后期扩张水面。FAO记载[Sarygamysh的灌溉回水形成](https://www.fao.org/4/T0446E/T0446E09.htm)，[Ramsar资料](https://rsis.ramsar.org/RISapp/files/RISrep/UZ1841RIS.pdf)记录1969年Chardara泄水与Aydar形成。托克托古尔、恰尔达拉、卡普恰盖、布赫塔尔马/现代斋桑库面等不作为1900天然湖面；原天然斋桑的历史岸线未恢复。努列克等未被本次源选择录入，不等于已取得其1900河岸。

| 地区 | 高程来源 | 地貌贴图 | 水网/湖泊 | 自然覆盖 | REGION状态 | LOCAL状态 |
|---|---|---|---|---|---|---|
| 哈萨克草原 | ETOPO+R50邻区 | 连续区域图 | 乌拉尔及R50流域 | WC2021 | 已接入；非历史草原普查 | 无新增精细DEM |
| 萨雷阿尔卡 | ETOPO+选定GLO90 | 丘陵/高地细化 | 有源天然湖 | WC2021 | 已接入有限细化 | 同上 |
| 乌斯秋尔特 | ETOPO+选定GLO90 | 高原边坡 | 里海/咸海邻区参考 | WC2021 | 已接入 | 同上 |
| 里海东岸 | ETOPO+选定GLO90 | 低地/台地 | 原现代里海 | WC2021 | 已接入；缺1900岸线 | 同上 |
| 咸海 | ETOPO | 湖床周边地貌 | late1950s多边形 | WC2021不判水 | 历史参考已接入；缺1900精确岛岸 | 同上 |
| 卡拉库姆 | ETOPO+科佩特邻窗 | 低地/山前 | Atrek、Harirud源线 | WC2021实际类别 | 已接入，非精确沙丘分布 | 同上 |
| 克孜勒库姆 | ETOPO | 区域地貌 | 两主河邻区 | WC2021实际类别 | 已接入 | 同上 |
| 阿姆河流域 | ETOPO+帕米尔GLO90 | 源区/下游 | Amu、Panj、Pamir等 | WC2021 | 已接入；历史改道未重建 | 同上 |
| 锡尔河流域 | ETOPO+有限GLO90 | 盆地/山地 | R50部分+R51剩余Syr、Naryn | WC2021 | 已接入；无1900河岸测绘 | 同上 |
| 费尔干纳盆地 | ETOPO+GLO90 | 山地/低盆地细化 | 源河网 | WC2021 | 已接入 | 同上 |
| 天山 | ETOPO+GLO90选窗 | 山脊/谷地 | Naryn、湖区等 | WC2021 | 已接入；新疆仅必要邻带 | 同上 |
| 帕米尔 | ETOPO+GLO90选窗 | 高地/深谷 | Panj等 | WC2021 | 已接入；不推定主权 | 同上 |
| 巴尔喀什及伊塞克 | ETOPO+选窗 | 湖盆/周山 | 实际天然湖多边形与Ile | WC2021 | 已接入；水位现代参考 | 同上 |

## 远东地貌与跨经线

黑龙江—乌苏里江、锡霍特、斯塔诺夫/布列亚高地、滨海、萨哈林、鄂霍次克、堪察加与楚科奇使用实际高程。新GLO90窗口覆盖符拉迪沃斯托克邻区、乌苏里、萨哈林山地、朱格朱尔、堪察加及跨180°经线山地；没有批量火山模型或喷发效果。克柳切夫56.056°N、160.642°E和科里亚克/阿瓦恰所在158°E窗口由各自DSM细化；坐标参考[Smithsonian GVP](https://volcano.si.edu/volcano.cfm?vn=300260)，不用于推定1900活动状态。

新增37个河流记录、14个天然分类湖泊，复用27个R50对象。Amur、Ussuri、Shilka、Argun、Zeya、Songhua、Amgun、Anadyr、Kamchatka等来自实际中心线，兴凯湖和Kronotskoye来自实际水面。**布列亚河在保留的NE源中没有被识别，未补造主轴。**Zeya等源Reservoir排除；Songhua Hu虽被源标为Lake，依据[吉林官方资料中的丰满水库沿革](https://dfz.jl.gov.cn/ybjl/201711/t20171120_5217150.html)另行排除。不声称恢复结雅、布列亚等工程前的精确宽河面。

楚科奇概览使用120—192°展开经度，文件ID和源读取归一到[-180,180)。180°两侧在同一像素网格分别采样后接合。MapRelief的2度格号按180格取模；材质边界、四片合并范围和Shader采样移到当前视图最近的一圈，避免358度的错误邻域。水文先在经纬度剪入东西两个真实半域，再做离线等积简化及受约束三角化，不在±180°间补横穿世界的线。

| 地区 | 高程来源 | 地貌贴图 | 水网/湖泊 | 自然覆盖 | REGION状态 | LOCAL状态 |
|---|---|---|---|---|---|---|
| 黑龙江流域 | ETOPO+选定GLO90 | 低地/山地 | Amur、Argun、Shilka等 | WC2021 | 已接入概化河网 | 无新增精细DEM |
| 乌苏里江流域 | ETOPO+选窗 | 山前/河谷 | Ussuri、Khanka等 | WC2021 | 已接入 | 同上 |
| 滨海地区 | ETOPO+选窗 | 丘陵/海岸地势 | 原NE海岸、源河流 | WC2021 | 已接入；港区1900岸线未重建 | 同上 |
| 锡霍特山脉 | ETOPO+选窗 | 真实山脊/坡面 | 有源河道 | WC2021 | 已接入 | 同上 |
| 斯塔诺夫山系 | ETOPO+R50及R51邻窗 | 连续高地 | 源支流；Bureya缺口 | WC2021 | 已接入有限细化 | 同上 |
| 鄂霍次克海沿岸 | ETOPO+朱格朱尔选窗 | 高地/近岸 | Uda、Kukhtuy等 | WC2021可得范围 | 已接入；海岸现代概化 | 同上 |
| 萨哈林岛 | ETOPO+GLO90选窗 | 全岛地势/山脊 | Poronay等、原物理海岸 | WC2021 | 已接入；不套1905身份 | 同上 |
| 堪察加半岛 | ETOPO+GLO90选窗 | 实际火山/河谷 | Kamchatka、Kronotskoye | WC2021 | 已接入；非历史冰雪测绘 | 同上 |
| 楚科奇 | ETOPO+GLO90选窗 | 跨180度山地 | Anadyr、Palyavaam等 | WC2021可得范围 | 已接入；高纬显示待实机 | 同上 |

WorldCover分类独立于DEM：树木、灌丛、草本、耕地、裸地、湿地、苔藓等只用实际分类像元；水类保持中性，不由遥感水类重建1900海陆。树木不细分针阔叶，苔藓不等于完整苔原生态区，湿地不等于泥炭普查。未知保持中性。没有从纬度、高程、地名推定地态；不产生人口、企业、产量、通行或军事隐蔽。

## 资源、接入与交付

新增481个地形bin：2个共享概览、479张地理细片，其中32张GLO90细化，其余为ETOPO原生区域格。新增bin共83,282,691字节；清单1,920,365字节。中亚11个、远东31个水文JSON/geom分片，分别188,207和303,915字节。文件尺寸是磁盘长度，不能当作运行驻留或实测内存。

亚洲西概览2520×1620、东概览2160×1320，120角秒；普通细片128×128（60角秒真实邻带），精细片1088×1088（32像素实源邻带）。固定hillshade和高程材质离线生成，RGB编码5含明暗，A独立表示地理覆盖。Mip离线生成。两概览解码含Mip分别21,771,236与15,205,752字节；一张1088细片含Mip约6.31MB。不是全部细片同时驻留。

运行仍为**最多两份概览、四张有效细片、一个解码线程**，替换时可短时多一张后继。元数据仅在REGION视域命中时准入；WORLD不等待本轮精细图。细片mpp≤750准入，300以下权重完整；区域层4500→2500渐入。原StrategicSpatialLoader保持物理完整包优先，可选水网不阻塞全球完整性；细水文仅在全部相交分片≤4时整体准入，超预算保留概览。不逐河创建材质，水面三角形按原水类合批。过期图像在GPU创建前丢弃，离开需求解除材质引用并按原路径释放；未增加无限旅行缓存。

正式新增：两份`tools/map/build_asian_*_r51.py`、`data/presentation/asian_surface_r51.json`、本轮481个bin、42组`asian_hydro_*_r51.json/.geom`及本报告。正式修改：`tools/map/build_siberian_surface_r50.py`（可选复用参数，默认保持原制作）、`geography_loader.gd`、`map_relief.gd`、`globe_renderer.gd`、`hydrography_style.gd`、`france_surface.gdshaderinc`、`data/strategic/index.json`、版本和内部导出路径。R50水文概览需求框改为其实际已存几何外包范围，避免复用湖泊南缘被名义46°N范围排除；原几何、ID不改。

制作顺序：`build_asian_surface_r51.py central`、`build_asian_hydro_r51.py central`、对应`far_east`、最后surface工具`finish`。研究缓存、许可与原始源保留。仅移除本轮缩小支持域后退出最终清单的73个未发布`asian_r51_*.bin`中间产物，共2,832,339字节；没有清理施工前资产或旧构建，没有删除R19/R30或其他工作线文件。

必要局部检查：三份Python源码解析；1366个最终引用地貌包的格式头、尺寸和解码长度相符；4份修改GDScript局部解析返回0。首次Renderer解析发现两个布尔量缺显式类型，已修正后重查返回0。未运行全仓库测试、哈希、CI、正式模拟或真实存档读写。历史身份、主权、LandTopology、经济与军事算法、GameClock、五槽、R39相机及黄铜半球仪均未修改。

唯一预览：`D:\programs\WWO\wwo\builds\preview_2026-10-19_asian_r51\WWO_1900_Central_Asia_Far_East_R51_Preview.exe`。采用原Windows Desktop Internal Landmark Preview预设，不覆盖Release或R50回退。正常Godot资源导入和唯一Windows导出均返回0；EXE实际文件长度1,097,234,144字节。没有运行导出的游戏。

用户仍需实机检查：天山/帕米尔和R50邻区交接、咸海年代参考及缺岛限制、黑龙江河网、萨哈林与堪察加、楚科奇跨经线、纹理安装长帧和资源释放。没有R51的FPS、显存、内存、加载秒数或风扇改善结论；旧约11秒首屏、原生访问冲突和RID问题不因本次导出自动结案。西伯利亚以外未施工的其他亚洲国家、R48/R49未完成区域均未冒充完成。
