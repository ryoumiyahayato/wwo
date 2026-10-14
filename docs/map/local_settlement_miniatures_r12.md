# R12 LOCAL城镇与河岸设施微缩表现

## 继承R11的实际内容

R11有四处有限高程片段：巴黎IGN RGE ALTI（63×63，约33×50米显示采样）、伦敦EA DTM（63×63，约24×39米）、吉萨西侧Copernicus DSM（57×57，约29×33米）、采尔马特swissALTI3D（33×63，约19×28米）。吉萨金字塔脚下尚无可用裸地DEM，继续使用局部平面。

水面包括巴黎IGN塞纳河多边形、伦敦OSM泰晤士河多边形、吉萨附近REGION尼罗河多边形。巴黎和伦敦有限水面已与已有DEM结合。伦敦没有实测水位；不能把地表贴覆当成水文模型。采尔马特有现代OSM林地覆盖，不代表1900年森林。R11没有生成树木。

历史交通有九处车站/桥梁代表点，以及Waterloo—City和柏林Stadtbahn的存在/连接资料。没有可靠历史精确线位，因此不绘制铁路或道路。本轮不补造线路。

本轮复用LocalSpatialLoader、LocalSpatialContent、RegionView的同一SubViewport、World3D、正交倾斜相机、原生高程三角插值、水面覆盖与地标交接。没有增加另一套城市场景或世界地点状态。

## 共享建筑资源

制作程序：`tools/map/build_settlement_modules.py`。

Blender：`D:/tools/blender.exe`，5.2.1 LTS。米制，底部原点，Blender Z-up导出为glTF Y-up。

运行资源：`assets/settlements/cabinet_building_modules.glb`。六个独立命名Mesh打包在一份GLB，39,104字节，436个三角面，一个共享顶点色材质，没有纹理、骨骼、动画、相机、灯光或碰撞。

|模块|三角面|用途|
|---|---:|---|
|paris_mansard|104|法国城市折线屋顶楼房体量|
|london_terrace|128|英国连排砖建筑体量|
|rural_house|32|坡顶乡村住宅模块；本轮未在城市中放置|
|civic_hall|68|通用公共建筑体块；不指代实际政府机关|
|warehouse|44|小型仓库/厂房外观；没有企业身份|
|quay_platform|60|简化岸边平台；不是实测码头岸墙|

模块没有各自重复的GLB副本。文件大小是上述共享包的实际总大小，不能将其分摊值称为六个独立文件大小。三个独特地标GLB没有修改，仍合计100,676字节，不计入普通建筑包。

材质为低饱和石材、砖、灰蓝屋顶、木色及少量深色开口的顶点色。省略逐窗、逐砖、室内、设备机械细节。没有现代集装箱起重机。

制作工程和导出统计在`local-artifacts/settlement-miniatures-r12/`，不进入游戏或Git。程序生成原件与GLB；源脚本保留生成方法。

## 地理事实与概念性排列

制作程序：`tools/map/build_settlement_placements.py`。只扩展既有巴黎、伦敦两份LocalSpatialContent的来源/事实集合。没有新建城市人口、土地、公司、房产、道路或行政身份。

|已有正式锚点|新增显示参考|代表经纬度|模块数|
|---|---|---|---:|
|place:paris|geographic_region:paris_gros_caillou_miniature|2.302000，48.858700|18|
|place:london|geographic_region:westminster_miniature|−0.131100，51.497200|16|
|place:london|geographic_region:millbank_wharves_1900|−0.124750，51.496350|4|

巴黎1900年Baedeker资料记录了Gros-Caillou、Champ-de-Mars及邻近工业和展览地域。参考原件已经保存在巴黎制作资料中。巴黎组合位于铁塔东侧的有限地理范围；不把整个Champ-de-Mars空地填成住宅。

伦敦资料核对了19世纪末Westminster/Millbank城市及河岸环境。1896年OS地图和Historic England记录显示Victoria Tower Gardens北部当时已是花园，南部仍有码头/工业设施。记录的后续公园扩建始于1909年方案，1914年开放。只在南部历史地域放置有限仓库和陆侧平台，不给北部花园制造港口。

**尚未取得可分发、已地理配准的1900年逐栋建筑或完整街区边界。** 按用户允许的有限概念性方案，本轮全部普通模块位置为`ABSTRACT_MINIATURE_COMPOSITION`。地域存在及大致位置有来源；内部排列、栋数、用途、尺寸与密度不是历史事实，不是随机生成的历史城市。三个参考对象的代表位置约100米精度，不冒称1900年实测。资料卡直接说明这个限制。

Millbank设施只表达历史河岸码头地域。现代河岸墙与1900年未筑堤岸线不同，因此平台保留在现代参考地表的陆侧。没有复原精确历史水陆接岸结构。没有码头企业、仓储账户、吞吐量、港口能力或运输规则。

## 空间衔接与尺度

- 模块的东/北米制偏移只属于显示。用现有RegionProjection的球面方位等距坐标转换，不写入SpatialWorld、LandTopology或TerritoryState。
- 底部取同一个原生DEM三角形高度，并应用与地表、河流和地标相同的RegionView变换。模块保留竖直轴，不另造坡度或改变高程。
- 离线生成时按最大3倍表现足迹排除已有现代水面，并限定在已经取得的DEM范围。邻近体块足迹不互相覆盖；独立地标周围保留位置余量。
- 在实际显示时再避免普通体块投影遮挡埃菲尔铁塔或钟楼的屏幕轮廓。没有改动地标GLB及其请求、安装、post-draw交接。
- 未恢复精确历史路线，所以不根据车站连接资料生成新的铁路线、道路或街道。普通排列不是1900年路网。
- WORLD不加载建筑包。REGION以城市群/码头轻量符号表达三个地理参考，最大约900米/像素；名称默认关闭。
- LOCAL在24米/像素以内显示真实GLB Mesh，18—24米/像素渐进交接，最多3倍表现放大。更近时持续显示，目标高度约12像素，但仍受3倍上限约束。不是精确屏幕物理比例。
- 第一次准备期间保留唯一可见符号。模型实际参与已完成的viewport绘制后，对应符号退出。静止视野不重算静态几何。仅模型实际投影的点击范围返回同一个地域资料，不为每个装饰体块建立资料卡。

## 加载与释放

建筑包沿用已有ResourceLoader后台请求和完成处理。只请求一份包含六种Mesh的GLB，不为每栋楼读取完整场景。提取共享Mesh后释放临时场景和PackedScene引用。

RegionView按模块建立MultiMeshInstance3D；只提交实际视野中的有限模块。无碰撞节点。视图改变时更新变换，时间推进不重建城镇。离开范围或LOCAL后，清除MultiMesh节点、Mesh引用、拾取矩形和过期后台结果。现有独特地标最近两份PackedScene缓存保持原规则。

窗口、地图拾取、历史行政、R10日志抽屉及其余HUD不改。水面/建筑没有独立政治或行政拾取算法。

Windows导出继续使用原有x86-64预设，只补充排除项目根目录的`_*_run.gd`及其UID临时运行脚本。这些其他工作线的本地文件没有删除或改动，也不纳入地图提交。

## 来源与许可

- [Karl Baedeker, Paris and its environs, 14th edition, 1900](https://archive.org/details/14thedbaedparis00karl)，同时代已进入公有领域的出版物。本轮使用原先已有文本和事实，不分发扫描图。
- [Historic England，NHLE 1000845](https://historicengland.org.uk/listing/the-list/list-entry/1000845)，历史记录撰写2002、修订2003，引用1894—1896年OS地图和档案。只整理历史事实，不复制网页描述、照片或现代OS地图。
- [Westminster / Atkins，2018 archaeological assessment，图5-12及相关历史讨论](https://www.westminster.gov.uk/sites/default/files/cd_6.13_es_volume_5_appendix_f_archaeological_desk_based_assessment.pdf)，仅用于核对晚维多利亚河岸和城市环境。PDF及含Groundsure来源的扫描片段只留本地研究目录，不进入游戏、Git或衍生逐栋几何。
- [NLS，London 1893—1896 Town Plans目录](https://maps.nls.uk/os/townplans-england/london-1056-1890s.html)，检索参考。本轮没有复制该整套地图或宣称已完成街区矢量化。
- WWO自行编写的事实摘要及概念性排列为CC0-1.0；外部文献保留各自权利。六个程序化Mesh为本项目原创，不含第三方模型/图片。
- 水面排除沿用R11：巴黎IGN Licence Ouverte 2.0；伦敦©OpenStreetMap contributors、ODbL-1.0。没有更改水面数据的年代或许可，预览继续附可读衍生JSON和署名说明。地表许可沿用R11来源记录。

## 尚未完成

没有实际启动游戏，未确认玩家画面、点击或性能。正常资产导入及Windows导出不等同于视觉验收。

巴黎和伦敦缺地理配准的1900年街区/建成区、精确历史河岸、可靠道路/铁路线位及逐栋用途。Millbank缺精确1900码头轮廓与适用设备图，故没有加入起重机或重建完整Port of London。巴黎未制造大型港口。吉萨和采尔马特不复制巴黎/伦敦建筑组合。

高程仍是现代物理参考；伦敦水位和近岸地表精度限制仍在。没有新增高程、林地、水系、交通网络或全国性GIS。本轮没有删除文件，没有运行游戏、测试、测量或哈希核验。
