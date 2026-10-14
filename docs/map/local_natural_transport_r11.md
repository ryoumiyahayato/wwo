# R11：LOCAL 地表、水面、现代覆盖与历史交通参考

基线为 R10。本轮不改 HUD、世界身份、存档或领域算法。不启动游戏，不做性能测量或回归。正常资源导入与 Windows 导出不等于玩家画面验收。

## 地表与相机

RegionView 保留同一个 SubViewport、World3D 和正交 Camera3D。二维战略图仍在 CanvasLayer -1，作为三维背景，不新建第二颗地球或地图运行时。

原地表变换以 `1/sin(观察角度)` 拉伸地面轴，抵消了倾斜相机的地面透视压缩。R11 取消这项补偿，地面与垂直方向使用相同的米到观察尺度关系。120 米/像素附近为约85度俯视，25米/像素及更近为35度倾斜，之间平滑过渡。没有放大海拔。

观察中心位于地表范围内时，用该点的实际采样高程调整显示基准，避免山坡因平移离开视口。地标原点使用地表相同变换与相同三角面高程；表现放大只用于 GLB。地表颜色保留坡度和相对高度层次，方向光使用真实法线，不再叠加第二次烘焙坡面光照。

| 地区 | 原始资料 | 当前显示采样 | 有限地表范围 | 原样保留的高程范围 |
|---|---|---|---|---|
| 巴黎铁塔附近 | IGN RGE ALTI，2026-10-13取得的现代裸地参考 | 63×63，约33×50米；接口未给出具体测量精度 | 约2.04×3.10千米 | 22.25—70.48米 |
| 伦敦威斯敏斯特 | EA 2022 DTM合成，原始1米，调查2000—2022 | 63×63，约24×39米 | 约1.50×2.41千米 | −6.09—24.58米 |
| 吉萨西侧 | COP-DEM-GLO-30 2021版，现代DSM | 57×57，约29×33米 | 约1.62×1.87千米 | 30.37—104.26米 |
| 采尔马特西侧 | swissALTI3D 2019版，原始2米裸地 | 33×63，约19×28米 | 约0.62×1.72千米 | 1968.29—2838.33米 |

地表在LOCAL且不超过120米/像素时按视野安装。近景最低尺度仍为2米/像素；放大不会增加源数据精度。吉萨DSM仍只用于已取得的西侧范围，不用于金字塔基座、现代开罗建筑或尼罗河谷。没有把粗土地单元当成山谷或山脊。

## 水面与林地

新增资料取得日期为2026-10-14，均是现代物理参考，不证明1900年河岸、潮位或林地分布。

| 对象 | 来源和许可 | 实际显示 |
|---|---|---|
| 塞纳河 | IGN BD TOPO V3 `surface_hydrographique`；Licence Ouverte 2.0，© IGN | 仅选自然流动水体；两段源多边形与巴黎高程网相交，951个显示三角面。源Z为27米，保留为水面参考高程，不称历史实测水位 |
| 泰晤士河 | OSM关系28934；ODbL 1.0，© OpenStreetMap contributors | 裁切至已取得的威斯敏斯特地表，2341个水面显示三角面。OSM没有水位，覆盖贴合当前DTM，不代表实测潮位或流动水面 |
| 尼罗河 | OSM关系2063663；ODbL 1.0 | 仅保留吉萨/开罗附近约东经31.158—31.226、北纬29.966—30.005范围。REGION显示真实来源水面多边形。没有河谷高程，因此不制造LOCAL河谷水面Mesh |
| 采尔马特林地 | OSM关系102130与已取得的两个forest方式；ODbL 1.0 | 先合并范围，避免重复覆盖；裁切至swissALTI3D地表，1793个贴地覆盖三角面。仅现代林地参考，没有逐棵树木Node3D、随机密度或1900森林断言 |

覆盖几何在离线制作时与原地表三角面相交，保留岸线、孔洞和岛屿。没有使用中心线推算固定河宽。一个共享覆盖Mesh承载水面或林地颜色；无水流Shader、碰撞体、植被模拟或树木纹理。河流中心线继续作为线状参考，在地表范围内沿同一高程采样。

OSM现代水库记录没有作为1900年历史水体接入。没有制作历史冰川、雪线、城市建筑群或新湖泊。

## 历史交通

新增九个有来源的地图展示地点，不创建正式企业、车站经营资产、运输能力或人口。

- 巴黎：北站、圣拉扎尔站、耶拿桥。SNCF和巴黎市资料确认1900年以前存在。圣拉扎尔代表19世纪末站址，不把1837年临时木站放在同一点；耶拿桥没有采用1937年拓宽后的桥面范围。
- 伦敦：Waterloo、当时名为City的Waterloo & City终点、Charing Cross、Westminster Bridge。TfL资料确认Waterloo—City于1898年连接；1940年才改名Bank。保存B类连接，不画未经定位的隧道。其余为C类存在及位置资料。
- 柏林：Friedrichstraße、Alexanderplatz。柏林官方遗产资料支持1882年Stadtbahn相关车站。B类引用表示同一历史线路，不断言两站为直接相邻站。不提前加入后来的地铁或重建站厅。

坐标是有标注的现代代表定位，按约100—250米不确定性处理，不是1900年站台或桥面实测。柏林片段只用于REGION交通参考点，没有DEM，因此不会启动空白LOCAL地表。

本轮没有取得完成地理配准、可分发且足以证明1900年精确线位的A类铁路/道路几何。未恢复现代SNCF线位或旧概略走廊。没有画连接两个车站的直线冒充铁路。一般道路、站场、道岔及港口布局仍缺资料。

## 资源与交互

沿用LocalSpatialLoader的后台读入、LocalSpatialLod的分级准备、LocalSpatialLayer的有界安装及RegionView的地表/地标生命周期。静止时不重建Mesh；时间推进不重建自然覆盖。WORLD不安装LOCAL地表。退出范围时清除覆盖节点、Mesh、地表引用及拾取数组，GLB仍仅保留最近两件PackedScene。

3D地表拾取继续相交同一Mesh，再转换到现有地理坐标。水面和林地没有碰撞拾取，不拦截政治、行政或地点选择。交通点沿用原地点选择和WorldPage资料卡；说明、来源和许可通过已有资料页显示。地图名称默认状态不改。

## 来源与分发

既有高程来源：

- IGN：[RGE ALTI](https://data.geopf.fr/altimetrie/resources/ign_rge_alti_wld)，Licence Ouverte 2.0。
- Environment Agency：[DTM 1m](https://www.data.gov.uk/dataset/01b3ee39-da3f-47b6-83da-dc98e73a461f/lidar-composite-digital-terrain-model-dtm-1m)，Open Government Licence v3.0。
- swisstopo：[swissALTI3D](https://www.swisstopo.admin.ch/en/height-model-swissalti3d)，swisstopo OGD，©swisstopo。
- Copernicus：[COP-DEM](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM)，WorldDEM-30公共许可。原始归属文字保留在已有地表JSON。

新增物理资料：

- [IGN BD TOPO](https://geoservices.ign.fr/bdtopo)，实际WFS类型 `BDTOPO_V3:surface_hydrographique`，经纬度范围记录在原始请求文件。只取有限水面子集。
- [OSM版权与许可](https://www.openstreetmap.org/copyright)，实际来源关系ID和适配多边形保留在数据里。衍生几何采用ODbL，不将其许可改为CC0。预览目录提供对应的可读JSON与许可说明。

新增历史事实来源：

- [SNCF北站历史](https://www.garesetconnexions.sncf/fr/histoire-gare-du-nord)。
- [SNCF圣拉扎尔历史](https://patrimoine.sncf.com/2025/04/25/la-gare-de-paris-saint-lazare-entre-histoire-art-et-modernite/)。
- [巴黎市耶拿桥资料](https://www.paris.fr/pages/lifting-reussi-pour-les-cavaliers-du-pont-d-iena-27479)。
- [TfL档案研究指南29](https://tfl.gov.uk/cdn/static/cms/documents/research-guide-no-29-brief-history-of-the-waterloo-and-city-line.pdf)。
- [Network Rail查令十字站历史](https://www.networkrail.co.uk/who-we-are/our-history/iconic-infrastructure/the-history-of-charing-cross-station/)。
- [London Museum威斯敏斯特桥](https://www.londonmuseum.org.uk/collections/london-stories/westminster-bridge/)。
- [柏林遗产对象09080415](https://denkmaldatenbank.berlin.de/daobj.php?obj_dok_nr=09080415)和[09066667](https://denkmaldatenbank.berlin.de/daobj.php?obj_dok_nr=09066667)。

只整理公开事实与来源链接，未复制上述机构的地图、照片或长篇文章。WWO自行编写的事实汇编采用CC0；原网页和扫描资料仍保留各自权利。

生成脚本为 `tools/map/build_local_natural_transport.py`，使用项目已保留的Shapely制作依赖。原始下载、请求与日志在 `local-artifacts/local-natural-transport-r11/`，不进入EXE。游戏只读取 `data/local/` 中的有限衍生资源。本轮没有删除文件，没有改动另一经济工作线文件，没有启动游戏或声称完成实际画面验收。
