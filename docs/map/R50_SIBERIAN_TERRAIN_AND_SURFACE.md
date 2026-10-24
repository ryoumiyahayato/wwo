# WWO R50 — Siberian Terrain, River Basins and Natural Surface Reconstruction

日期：2026-10-18。施工对象为西伯利亚REGION地貌、水文和现代覆盖。**R48奥匈/意大利、R49欧洲俄罗斯扩库实际未完成；本报告不补记为已完成。** 本轮先修正Debug定位确认的几何线程类型错误，再复用现有地图路径制作西伯利亚资源。没有运行R50游戏验收或性能基准。

## 1. 前置故障与真实基线

已承接R39、R41—R49及R46后专项报告，核对MapRelief、GeographyLoader、StrategicSpatialLoader、LocalSpatialLod/Layer、GlobeRenderer和Shader。实际继承：R39唯一相机、24份coarse、原有界medium；R42—R46真实地貌；R48共享欧洲概览/地理细片选择及行政、水文修正；R47图集；R49线段严格分组预算和错误上下文。R48欧洲概览仅12°W—24°E、34°N—62°N，不等于欧洲俄国已建。

用户本轮明确授权一次最多5分钟的隔离Debug定位，仅暂停巴黎缩放、取得首个几何失败栈后退出，不保存、不采样性能。实际运行R49 Debug预览：2026-10-18 22:13:21.2618405—22:17:30.1041451（UTC+08），进程28632，约4分9秒。通过正常菜单进入新法国世界。时钟保持1900-01-01 00:00暂停。期间检测到用户输入，故不把路线视为严格可重复的相机轨迹；未取得准确米/像素。

取得首个脚本栈：

```text
Trying to assign an array of type "Array" to a variable of type "Array[Dictionary]".
at: prepare (res://scripts/presentation/map/local_spatial_lod.gd:63)
```

预计算水面三角形分支使用了三元表达式。一侧返回`Array[Dictionary]`，水面侧为普通Array字面量，类型推断使工作线程在赋值处退出。现在显式建立`Array[Dictionary]`，分别赋值或append。它解释已观察的几何线程无效返回，不证明R47原生访问冲突或全部Windows无响应已消失。

Debug模式停在工作线程错误处。选择“不保存并退出”后进程仍等待该线程。为遵守5分钟上限，核对PID和EXE路径后仅终止此隔离进程；退出码-1，**不是正常退出**。临时user://为`WWO_R50_Paris_Debug_20261018`，隔离目录未发现存档JSON。真实五槽未读写。临时override已移出旧预览目录，旧EXE保留。日志在`local-artifacts/r50-paris-debug/`，不入包。修正后未第二次启动游戏。

R49分组上限继续保留：非预制线片最多128条边，组最多1024/256段，原邻接和取消保留。R50没有新增行政枚举、地图探针、监控服务或模拟结算修改。CanvasItem RID警告、旧访问冲突、约11秒首屏及首次上传长帧仍需独立运行证据。

## 2. 地理范围

统一EPSG:4326，经纬度不按国家或省份重置。地貌资源外框54°E—176°E、46°N—84°N。支持域由三个相接地理邻带组成：西部54—118°E/46—84°N，中东部110—156°E/48—82°N（南缘从外贝加尔向东逐步退至60°N，避免展开完整阿穆尔及太平洋沿岸），东北部148—176°E/59—82°N；边缘2—4度渐退。核心区域连续，不沿政治边界裁切。

包含西西伯利亚、乌拉尔东麓过渡、阿尔泰—萨彦、中西伯利亚高原、普托拉纳、贝加尔、勒拿及东北内陆山系/主要北流水系。南部必要高程和河流延伸至哈萨克斯坦、中国、蒙古邻带，不算这些国家全面施工。176°E外不新增细片；±180°本身继续由原全球基础显示。

滨海、完整阿穆尔、萨哈林、千岛、堪察加、完整楚科奇及太平洋沿岸未施工。东北邻带不等于远东全部完成。中亚、蒙古和中国全国未施工。欧洲俄罗斯缺口没有被西伯利亚概览填充；乌拉尔本轮只有邻带，不宣称R49已补齐。

1900年俄罗斯帝国身份继续读取现有历史系统。未创建现代萨哈等政治实体，未变更国界、行政成员、主权、实际控制或土地经济身份。

## 3. 实际来源与制作

| 数据 | 实际精度、年代和基准 | 许可与用途 |
|---|---|---|
| NOAA ETOPO2022 Ice Surface 60s | 原21600×10800，60角秒；WGS84经纬度，EGM2008正高米；1998—2022复合资料。不是1900测量或统一米级DTM | NOAA公开/CC0来源说明保留。全国连续概览及普通细片的高程、色阶、离线坡向阴影 |
| Copernicus DEM GLO-90 | 现代DSM，主要TanDEM-X 2011—2015，含填补；WGS84/G1150，EGM2008米。原纬向3角秒、经向随纬度变化；实际仿射参数逐文件保留 | Copernicus DEM公开许可，需署名。只取得23处细化窗口所需地理单元和实邻边 |
| ESA WorldCover2021 v200 | 2021分类；原1/12000度，COG分类概览近邻抽样；广域每3度225×225，细化区2250×2250 | CC BY4.0。独立树木、灌丛、草本、耕地、裸露/稀疏、源冰雪、湿地、苔藓地衣类参考 |
| Natural Earth v5.1.2所含10m河流/湖泊 | EPSG:4326二维；1:10,000,000制图比例尺，**不是10米精度**。现代复合来源，具体观测年份不明；原记录序号/rivernum/ne_id保留 | Public Domain。真实中心线、天然湖泊及原R27海岸；不能当1900河岸或河宽 |

ETOPO原件复用`local-artifacts/physical-relief-r1/source/ETOPO_2022_v1_60s_N90W180_surface.tif`，未重下载全球库。GLO-90原COG和600×600/度、6角秒平均提取保存在制作目录；显示细片217.2米南北采样不代表测量精度。高纬东西采样随cos纬度收敛，不声称其显示像素优于原始DSM。

概览3660×1140，120角秒显示采样，南北约3.71km。普通2度细片128×128，含真实邻边，采样仍为60角秒，南北约1.85km。23处细化采用1088×1088、1/512度和32像素实邻边。高程没有用于生成新山峰GLB、放大实际高度或推定水域。

固定双方向hillshade离线按公制坡度生成。3倍因子仅用于阴影法向，不修改DEM。绝对高程使用统一log色阶，不按流域拉伸。没有新增独立法线纹理或逐帧山体阴影计算。R50编码5把离线阴影烘入线性RGB，A只表示地理支持度，避免将边缘透明度误作阴影而产生暗框。旧编码未改变。

分类只来自WorldCover。10类不区分针叶/阔叶或原生林；90类不等于泥炭土普查；100类是苔藓地衣，不等于权威苔原边界。未取得独立冻土或1900覆盖。缺源边缘只渐退分类可信度至中性，不外推覆盖。未知、建筑及现代水体类保留中性地貌，不以分类水像素制造现代水库蓝面。冰雪仅来自2021分类，不按纬度或海拔生成永久雪。湿地、耕地不产生经济或军事事实。

来源链接及署名：

- [NOAA ETOPO产品与原始资料](https://www.ncei.noaa.gov/products/etopo-global-relief-model)，[采样和垂直基准说明](https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/docs/1.2%20ETOPO%202022%20User%20Guide.pdf)。
- [Copernicus公开COG说明](https://copernicus-dem-90m.s3.amazonaws.com/readme.html)，[Copernicus DEM许可](https://dataspace.copernicus.eu/sites/default/files/media/files/2025-06/copernicus_contributing_mission_data_access_v2_cop_dem_licenses.pdf)。
- [WorldCover数据与许可](https://esa-worldcover.org/en/data-access)，[2021 v200 DOI](https://doi.org/10.5281/zenodo.7254221)。署名：© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium。
- [Natural Earth公共领域条款](https://www.naturalearthdata.com/about/terms-of-use/)，[实际固定版本目录](https://github.com/nvkelso/natural-earth-vector/tree/v5.1.2/geojson)。HydroRIVERS/HydroLAKES已评估，未取得或接入；不将其许可冒称为本轮来源。

## 4. 三大水系、湖泊和年代

本轮新增93个河流源记录、177个源分类天然湖泊对象。一份概览含66个河流记录、39个湖泊；其余165个对象按4度核心分为101份细片。细片跨边使用源几何交集，不连接未测端点；一个对象跨片会有多个显示记录，不能将这些计为新河流。共102份JSON及102份geom，1,224,244字节。概览500,249字节。河流为共享类别材质的线组，不为每条河创建独立Shader。主河/支流/小河分别使用1.35/1.0/0.62制图倍率，不表示测量河宽。

| 水系 | 实际安装 | 缺口或限制 |
|---|---|---|
| 鄂毕—额尔齐斯 | Ob/Malaya Ob、Irtysh/Ertis/Ertix、Tobol、Ishim/Esil、Tom、Chulym、Biya/Katun、Vasyugan等源河段 | 凯特河未找到可确认记录；上游保留真实跨境延伸，不重建1900河岸 |
| 叶尼塞 | Yenisey及上下游记录、Angara、Lower/Podkamennaya Tunguska等 | 阿巴坎河缺可确认记录；库区保留有来源的现代轴线参考，不生成旧宽水面 |
| 贝加尔 | ne_id1159113127天然湖面，含源孔洞；Selenga入湖，Angara从西南端出湖后连接叶尼塞体系 | 不把勒拿当作出湖河。巴尔古津缺记录；现代调节水位不同于1900 |
| 勒拿 | Lena、Aldan、Vilyuy、Olëkma、Vitim；Trofimovskaya/Tumatskaya/Bykovskaya/Olenekskaya四个源三角洲水道 | 三角洲、岛屿仍是现代概化资料，没有1900精确泥沙/海岸复原 |
| 东北及北方 | Yana、Indigirka、Kolyma、Omolon、Kheta/Kotuy/Khatanga、Pyasina、Anabar、Olenëk等 | 没有补造小支流或完整古河道；高纬小岛精度受Natural Earth限制 |

贝加尔/安加拉关系参考[联合国开发计划署—GEF贝加尔流域报告](https://archive.iwlearn.net/bic.iwlearn.org/bic.iwlearn.org/bic.iwlearn.org/en/documents/state-of-the-environment-report-the-lake-baikal-basin-1/general-conditions-of-the-baikal-lake-basin.html)。其中说明安加拉出流及伊尔库茨克工程后的水位变化。源湖面仅标为现代天然湖泊轮廓，不宣称1900水位。

源分类为Reservoir的候选全部排除：Novosibirsk1159123075、Lake Zaysan1159123091、Bratsk1159125163、Vilyuy1159125251、Krasnoyarsk1159125261、Ust-Ilimsk1159125431、Khantayskoye1159126045。邻带中Votkinsk1159125351、Kama1159125365、Zeya1159125585也未准入。Zaysan原本存在天然湖，但源给的是调节后的Reservoir轮廓，不能把该轮廓当1900自然水面。

萨彦—舒申斯克、博古恰内、科雷马水库多边形不在本次选取原件中；没有据此重建其历史河面。[ILEC布拉茨克资料](https://wldb.ilec.or.jp/Display/html/3578)记录1961—1967形成，不能用于1900天然湖泊。Lake Centerline仅作为现代轴线，类别和年代限制写入元数据；贝加尔内部轴线已移除，避免横穿天然湖面的多余蓝线。

可选包完整准入后，新源记录使用已有`display_replaces`替换`river:ob`、`river:lena`、`lake:lakebaikal`旧显示对象。原始eurasia文件和源ID没有编辑，未改变世界事实。其他流域没有复制R49未存在的水文。原R27海岸仍是现代Natural Earth10m；本轮没有历史北冰洋岸线、水位或季节海冰重建。

## 5. 运行接入与有界资源

沿用`GeographyLoader.decode_relief`的证据准入、FRT42解码及MapRelief单线程读取。仅增加`siberian_catalog`，不建立新加载器。MapRelief按当前地理支持域和视野重叠面积选概览，保留最多两份概览、四张有效细片；一个读取任务，替换时允许一张短时后继细片。西伯利亚宽视野使用同一概览，不按三个流域增加常驻槽位。

高纬视野采用球面圆帽的经向跨度，达到极点时覆盖所有经度；重叠排序按纬度余弦加权，并测试±360°包裹副本。细片网格、Shader经纬采样和世界球面仍使用同一坐标。R50没有176°E以东精细瓦片，不把±180°全球显示写成已新增极东高精度覆盖。

区域材质在4500米/像素以内请求目录/概览，2500—4500渐入；750米/像素以内选2×2细化邻域，300—750渐入。目录中的全部瓦片描述不等于全部像素读取。离开支持域清除细片需求和材质引用，纹理从textures退休；过期读取在ImageTexture创建前丢弃。目录描述可留用，访问过的像素不永久缓存。四片槽位仍限制同屏精细范围，邻域外回到连续较粗概览；这不是全国相同精度保证。

水文使用现有StrategicSpatialLoader。必须先有物理基础，且mpp≤2500才请求可选概览；mpp≤500、当前全部相交细片不超过4份才一并请求，否则保留概览，不取任意前四片。水面离线约束三角化保留岛洞，运行不重新做GIS。旧完整基础在准备期间保留。新增目录仅有描述的静态解析成本，地形像素/水文几何不是初始国家选择的必要依赖。

R50不新增LOCAL DEM或实际高度Mesh。近景继续显示区域材质；已有巴黎、伦敦、采尔马特等有限DEM和模型按旧生命周期运行。未改R39相机、medium/coarse结构、黄铜半球仪、政治旗帜、行政GIS、地标、GameClock、SimulationStep、经济或军事。

## 6. 实际覆盖清单

表中E=原生60角秒ETOPO，G=选定GLO-90窗口，W=WorldCover2021现代类别。所有“接入”指资源与代码接入，不代表玩家视觉验收。没有新米级LOCAL资料。

| 区域 | 高程来源 | 地貌贴图 | 主要水文 | 自然覆盖 | REGION状态 | LOCAL状态 |
|---|---|---|---|---|---|---|
| 西西伯利亚平原 | E；乌拉尔/低地选定G | 连续概览+普通细片 | 鄂毕及支流 | W分类，非历史地态 | 已接入区域参考 | 区域级，无新精细DEM |
| 瓦休甘 | E+80°E/56°N窗口G | 低缓坡向、选定细化 | Vasyugan源线 | W湿地/树木等；不等于泥炭普查 | 已接入；无1900湿地界 | 同上 |
| 鄂毕—额尔齐斯 | E；68°E/60°N窗口G | 低地/河谷连续 | 主干、实际支流；Ket缺口 | W | 已接入；河宽未复原 | 同上 |
| 阿尔泰 | E+86/88°E/48°N G | 高山/盆地细化 | Katun、Biya等 | W，非历史雪线 | 已接入选定山地精度 | 同上 |
| 萨彦 | E+92/96°E/52°N G | 山脊/盆地 | 叶尼塞源段；Abakan缺口 | W | 已接入 | 同上 |
| 中西伯利亚高原 | E+96/100°E选定G | 高原、台地、谷地 | 两条Tunguska等 | W | 连续区域参考+有限细化 | 同上 |
| 普托拉纳 | E+90/92°E/68°N G | 高原/深谷细化 | Keta、Lama、Dyupkun等天然湖 | W | 已接入；非实测峡壁Mesh | 同上 |
| 叶尼塞流域 | E+有限G | 主谷地与支流高原 | 叶尼塞/通古斯卡 | W | 已接入现代概化水网 | 同上 |
| 贝加尔及周边 | E+104/106/108°E选定G | 湖岸山地细化 | 实际天然湖面、Selenga/Angara | W | 已接入；Barguzin缺口 | 同上 |
| 安加拉 | E+100°E/56°N G | 河谷区域参考 | 源轴线；现代库面排除 | W | 已接入；无1900库区河岸 | 同上 |
| 勒拿 | E+128°E/62°N等G | 河谷及北部低地 | 主河/Aldan/Vilyuy/Olëkma | W | 已接入 | 同上 |
| 上扬斯克 | E+130°E/66°N G | 实际山地细化 | Yana及支流 | W，不推定冻土 | 已接入选定窗口 | 同上 |
| 切尔斯基 | E+144°E/66°N G | 实际山系细化 | Indigirka相关源线 | W | 已接入选定窗口 | 同上 |
| 因迪吉尔卡 | E+148°E/70°N等G | 山谷向低地过渡 | Indigirka/Moma等 | W | 已接入区域参考 | 同上 |
| 科雷马 | E+158°E/68°N G | 山地/北部低地 | Kolyma/Omolon等 | W | 已接入；不是远东全覆盖 | 同上 |
| 泰梅尔/北极沿岸 | E+102°E/74°N及勒拿河口G | 北方低地与实山地 | Taymyr湖、Khatanga、源河口水道 | W实际可得范围，缺处中性 | 已接入；海岸仍现代概化 | 同上 |

## 7. 文件、制作与交付

制作命令（普通Python/GIS工具仅离线使用，不入游戏）：

```text
python tools/map/build_siberian_surface_r50.py
python tools/map/build_siberian_hydro_r50.py
```

地貌工具可用`--acquire-only`、`--build-only`分开取源与生成，`--retry-cover-low`仅为失败的细覆盖读取取得真实粗概览。本次取得328个GLO-90原始单元/提取和399份WorldCover提取：70份2250×2250、329份225×225。8处细读取失败后已恢复为粗读取，最终读取失败0；对应3度单元西南角为(87,48)、(96,51)、(66,57)、(81,57)、(69,60)、(129,63)、(144,63)、(87,69)。这些地方没有2250细覆盖，不写成10米土地调查。研究目录`local-artifacts/siberian-surface-r50/`保留原COG、配准提取、来源记录及水文对象清单。原始ETOPO、Natural Earth、制作脚本和许可证不删除。游戏只打入处理后bin、JSON/geom；tools、docs、local-artifacts和日志沿用排除规则。没有额外清理、哈希清单、Git提交或推送。

正式新增：`tools/map/build_siberian_surface_r50.py`、`tools/map/build_siberian_hydro_r50.py`、`data/presentation/siberian_surface_r50.json`、`assets/maps/relief/siberian_r50_*.bin`、`data/strategic/siberian_hydro_*_r50.json/.geom`及本报告。

正式修改：`scripts/content/geography_loader.gd`、`scripts/presentation/map/map_relief.gd`、`scripts/presentation/map/local_spatial_lod.gd`、`scripts/presentation/map/globe_renderer.gd`、`shaders/presentation/map/france_surface.gdshaderinc`、`data/strategic/index.json`、`project.godot`、`export_presets.cfg`。R49报告追加本轮定位链接。没有删除施工前已有正式文件；其他工作线本地修改保留。收紧本轮东部范围后，仅移除本次新生成、未发布且已退出清单的12个水文中间文件：siberian_hydro_48_+136、48_+140、52_+132、52_+136、52_+140、56_+136各自的_r50.json/.geom；未清理旧构建或既有资产。

唯一预览目标：

`D:\programs\WWO\wwo\builds\preview_2026-10-18_siberian_r50\WWO_1900_Siberian_Terrain_R50_Preview.exe`

版本标识更新R50，`config/version=0.001a`和存档格式保留。使用原Windows Desktop Internal Landmark Preview预设、x86-64、嵌入PCK；内部地标许可限制保持。R49/R48直接回退、其他保护版本和正式发布未覆盖。没有生成R51。

### 最终资源与导出记录

- 地貌987份bin：概览1、普通60角秒细片963、GLO-90选定细片23；共71,897,966字节。目录JSON为1,400,424字节。全部使用编码5。
- 概览3660×1140、12级Mip，完整解码22,250,456字节（21.22MiB）。普通128×128为8级；细化1088×1088为11级，最大完整像素6,313,256字节（6.02MiB）。一份Siberian概览加四份最大细片的像素长度约45.30MiB；这不是实测显存或进程内存，未包含驱动及其他图层副本。
- 水文102份JSON+102份geom：93个河流源记录（80个源名称）、177个源分类天然湖泊对象；共1,224,244字节。概览含105条显示记录，500,249字节；101份细片当前最多准入4份。
- 上述运行资源及地貌目录合计74,522,634字节；不是EXE增长或驻留内存测量。国家选择仅新增少量索引描述解析，没有这些全部纹理/几何的必要读取。
- 两个生产脚本完成语法解析。LocalSpatialLod、MapRelief、GeographyLoader、GlobeRenderer已做修改所需的Godot局部check-only解析，退出0。概览头部尺寸/完整解码长度与描述一致，检查过制作图；没有据此宣布运行视觉通过。
- 为避免打入本轮放宽候选域留下的中间件，仅删除本轮未发布的30份bin（lat48、lon124—154每2度；lat50、lon128—154每2度），753,648字节。它们均不在最终目录；旧版本和既有地形未清理。
- Godot4.6.3正常headless编辑器导入退出0。内部预设使用Release模板导出，退出0；唯一EXE为1,011,476,528字节，内嵌PCK。没有另做R50 Debug或其他候选EXE。导入/导出日志未见脚本解析错误；保留原config/version=0.001a造成的Windows数字版本格式警告。日志位于local-artifacts/r50-import.log和r50-export.log，不入运行包。导出后未启动游戏。

用户仍需实机确认：新地貌画面、低地/高原/山地差异、三大流域和贝加尔、极北海陆、瓦片/LOD交接、旧近景无响应是否仍出现。没有本轮FPS、内存、显存、加载秒数或风扇改善结论。旧RID警告和原生访问冲突没有完成归因。
