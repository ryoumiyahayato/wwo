# R41 历史交通地物与林地表现

本轮四件 GLB 均由 WWO 原创程序几何制作。沿用 R40 原创模型的 CC0-1.0 约定。没有复制第三方模型、照片、贴图或雕塑扫描。参考网页、历史图像及原地理资料保留各自权利，不随原创模型改许可。

## 已接入的模型

| 模型 | 历史依据 | 本轮形制与限制 |
|---|---|---|
| `pont_iena_r41.glb` | [巴黎市：桥梁及骑马雕像](https://www.paris.fr/pages/lifting-reussi-pour-les-cavaliers-du-pont-d-iena-27479)、[CONI：五孔结构参考](https://parigi2024.coni.it/it/gare/impianti/impianto/5:Pont_d%27Iena.html) | 五孔石拱、墩台、栏杆、四件骑马雕像的抽象轮廓。采用拓宽前14米主体，长度155米。不是1937年35米宽桥面。雕像不是原作复制。1900年临时步道的施工日期与细部未确认，未制作。 |
| `westminster_bridge_r41.glb` | [Historic England，1066172](https://historicengland.org.uk/listing/the-list/list-entry/1066172?section=official-listing)、原 London Museum 存在性记录 | 1862年七孔金属拱、花岗岩墩台、透空拱上构件、哥特式栏杆和多灯头灯柱。250×26米为建模参考包络；各分孔、涂色、灯柱布置不宣称为1900年精测复原。没有1906年后电车设施。 |
| `gare_du_nord_r41.glb` | [SNCF 站史](https://www.garesetconnexions.sncf/fr/histoire-gare-du-nord)、[巴黎市 Hittorff 建筑介绍](https://www.paris.fr/pages/sept-realisations-emblematiques-de-jacques-ignace-hittorff-l-architecte-de-la-gare-du-nord-22333) | 1860年代新古典站房的中央山花、拱窗、立面分区、寓意雕像轮廓和铁玻璃大厅。156×112米是模型包络，不是1900年测绘范围。大厅作概括表示，不据此声明实际厅跨、站台、轨道数。没有现代扩建、地铁或虚构站场。 |
| `friedrichstrasse_1882_r41.glb` | [柏林文保数据库09080415](https://denkmaldatenbank.berlin.de/daobj.php?obj_dok_nr=09080415)、[Heuer与Kirmse的1882年木刻](https://commons.wikimedia.org/wiki/File:Holzstich_G._Heuer,_%C3%9Cbergang_am_Bahnhof_Friedrichstra%C3%9Fe,_1882.jpg)、[1894年 Brockhaus 图](https://commons.wikimedia.org/wiki/File:Brockhaus_14_Berlin_Bahnhof_Friedrichstra%C3%9Fe.jpg) | 原站时期单厅拱顶与砖砌高架的示意，含入口、窗带和金属肋。排除1919—1925年双厅改建形制。114×60米为示意包络；高架孔数、入口平面和朝向不作为精测资料。没有轨道、列车或平台数量的主张。 |

四处原交通地点的 ID、坐标、有效期和历史连接关系保持原状。模型元数据另存建模依据和显示参数。资料卡继续选择原交通 ID；视觉对象不生成正式建筑资产、公司、运力或军事设施。

## 水文、地面与定位

桥梁的显示中心和横河方向由原有有限现代水域三角形推导。耶拿桥显示中心相对原代表点移约57.51米，威斯敏斯特桥约1.52米，都在原250米定位不确定性内。原地点坐标没有改写。该处理只是显示定位，不是历史坐标纠正，也不证明当前水域就是1900年河岸。

巴黎使用既有 IGN/SANDRE 水域参考；伦敦使用既有 OpenStreetMap contributors 水域参考，ODbL-1.0。原署名和资料仍在 LOCAL 文件中。生成的显示定位沿用相应来源条件。伦敦交线只取得36.28米的一个水域片段，不能当作完整泰晤士河宽；本轮未据此拉伸桥梁。桥梁未恢复已退役的有限宽河面。

桥面高程使用模型两端范围内现有现代 DEM 的较高采样值，减去模型12米桥面基准后安装整件模型。它不是1900年桥面或水位测量。桥墩与实际水底、两岸的精确接合仍待画面查看和更精细史料。没有修改 DEM 高度、外推河道或生成假河岸。

巴黎北站在已有巴黎 DEM 之外，柏林未取得 LOCAL DEM。两处使用原 R23 无 DEM 地标相对平面；不为站房创建城市地形。

## LOD、加载与维护

四件模型每件两个命名 Mesh：`Near`、`Far`，一份不透明顶点色材质；无图片纹理、骨骼、动画、碰撞体或内置灯光。桥梁在3米/像素、车站在5米/像素切换近档，另一档隐藏。模型在 LOCAL 12米/像素内准入，已有滞回仅用于离场；WORLD/REGION不读取这些 GLB，只使用原地点符号。最大显示比例为1，不为凑屏幕尺寸放大桥梁跨度。

沿用 RegionView 的异步 PackedScene 读取、既有3D视口、有限近期缓存和离场释放。实例持有自身 Mesh/材质；近期 PackedScene 缓存仍最多2件。R40普通城市包和38件布局不变。

可编辑源：`tools/map/model_sources/r41/*.blend`。生成器：`tools/map/build_historical_landmarks_r41.py`；安装器：`tools/map/install_historical_scenes_r41.py`。Blender 5.2.1，米制，Z-up导出glTF Y-up。使用生成器既有参数可重新制作；没有不可维护的单独导出件。

## 采尔马特

三种原创树冠轮廓由 `RegionView._reference_tree_mesh()` 生成。形制有分层宽冠、窄高冠和较宽冠，分别约16、15.2、14.3米高；不指定实测树种。共用一份不透明顶点色材质，按原树位索引分为3个 MultiMesh；追加施工将原65米候选采样间隔改为50米，实际67个候选，最多96个上限、原DEM及林地遮罩不变，最大冠幅半径仍不超过3.5米。树体只绕竖直轴旋转，不沿坡面倾斜。

现代 OSM 林地不是1900年林木、密度、木材产量或军事隐蔽资料。远处仍显示 R29 林地遮罩，不保留逐棵碰撞、骨骼、风动或持续更新任务。

已有内部预览古迹的作者与再分发限制继续适用。追加7件云盘古迹适配件，仅限内部预览，见[扩展来源说明](internal_preview_r41/SOURCE_AND_USAGE.md)。4种原创设施只供明确选择的测试负载使用，没有安装成未经定位的历史企业或矿区。
