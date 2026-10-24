# R41 扩展古迹与内部负载资产

本目录中的7件古迹来自用户授权读取的R15云盘目录。作者、原始作品许可和公开再分发权仍未确认。只用于本机处理和内部预览；普通Windows/Linux/macOS发行预设排除本目录及对应元数据。网页只用于历史存在性和形制核对，不替模型授予许可。

原件保留在`local-artifacts/r41_extension/originals/`。原R15目录、模型原件和历史GIS没有改写。仅下载8件候选，没有重取120件全库。

| 已安装对象 | 原文件 | Drive ID | 历史与定位来源 | 适配限制 |
|---|---|---|---|---|
| 奥朗日古剧场 | `65_Theatre_of_Orange_Roman_Stage_Wall_France.glb` | `1o4l1BGAYXh6pP_j9Jy157Z3OxCdt6wlg` | [UNESCO163](https://whc.unesco.org/en/list/163/)、[现代定位](https://en.wikipedia.org/wiki/Roman_Theatre_of_Orange) | 保留舞台墙、看台、开口；去掉演示山丘、未核定年代的侧翼屋顶和雕像。不是1900残损状态逐段复原。 |
| 比萨斜塔 | `10_Leaning_Tower_of_Pisa_Italy.glb` | `1RRsi3JjnXVxlmlTdp6qll5neSh1Hro_l` | [比萨市](https://www.comune.pisa.it/Vivere-il-Comune/Luoghi/Torre-di-Pisa)、[UNESCO395](https://whc.unesco.org/en/list/395/) | 去掉草坪；塔体倾角为原模型示意，不能称为1900实测倾角。 |
| 帕特农神庙遗址 | `02_Parthenon_Athens.glb` | `1AAXEB6qOJjPAFsvNvlXSr4rwCt0OIai0` | [UNESCO404](https://whc.unesco.org/en/list/404/) | 去掉无测绘依据的岩台；柱列、残墙不证明1900修复接缝和逐块状态。 |
| 佩特拉宝库立面 | `08_Petra_Treasury_Jordan.glb` | `1D66mrQ98lpY_d1HG-8f4d7WlGlIDzq40` | [佩特拉主管机关](https://pdtra.gov.jo/EN/ListDetails/Historical_Location/1234/2)、[现代定位](https://en.wikipedia.org/wiki/Al-Khazneh) | 只保留建筑立面；剔除假设峡谷、沙地和岩壁，不冒充地形测绘。 |
| 泰姬陵主体 | `06_Taj_Mahal_India.glb` | `1GhO-s6RkUCBfIDwc8M0oLucG1gfFG1U2` | [UNESCO252](https://whc.unesco.org/en/list/252/)、[官方建筑介绍](https://www.tajmahal.gov.in/architecture.aspx) | 保留白色主体、塔、顶饰；去掉演示园林、池水及红色场地。 |
| 天坛祈年殿 | `05_Temple_of_Heaven_China.glb` | `13GdDMjWRpD2BVh0dTTZgYYrScCoOR7m7` | [北京文旅：1896重建](https://www.visitbeijing.com.cn/article/47QllJ8IU2a)、[园林局](https://gygl.beijing.gov.cn/whgy/whgy_wsgc/201912/t20191206_885633.html)、[UNESCO881](https://whc.unesco.org/en/list/881/) | 保留三重檐、坛台；去掉整块演示庭院。无现代游客设施，未复原内部陈设和1900年周边用地。 |
| 圣索菲亚主体 | `18_Hagia_Sophia_Istanbul.glb` | `1nQPeKyZgJCk0tXV14EtnVVFVOWR9ToDE` | [土耳其文化部](https://www.ktb.gov.tr/EN-113776/ayasofya-hagia-sophia.html)、[UNESCO356](https://whc.unesco.org/en/list/356/)、[现代定位](https://en.wikipedia.org/wiki/Hagia_Sophia) | 保留穹顶、支墩和奥斯曼宣礼塔；去掉广场底座。壁面色及细部为概括表现。 |

7处均早于1900存在。现代坐标只作有250米不确定性的地标定位；不作为1900测量点。模型底部归零，统一缩放成米制示意包络，旋转轴转换为Godot坐标；没有制造周边DEM。高度、占地包络显示为“模型包络”，不改写为建筑实测尺寸。各地点通过`landmark:<key>_reference`稳定ID关联现有LOCAL路径和资料卡；不创建经济、人口、土地或军事事实。

第8件候选`64_Segovia_Roman_Aqueduct_Spain.glb`（`1aXuccBajkZQz4QVE1bSCNthHRt7zha5T`）没有安装。原模型双层开孔为矩形梁柱，不能表达[UNESCO311](https://whc.unesco.org/en/list/311/)对应的古罗马拱券；原件及淘汰原因保留。其试制适配件移至排除打包的`local-artifacts/r41_extension/rejected/`，不计成果。

## 制作与资源

`tools/map/r41_landmark_expansion.json`记录准入、保留的原材质组、锚点与来源。Blender脚本`tools/map/adapt_drive_landmarks_r41.py`只处理指定原件。清除不用的底座和未使用顶点，保留原材质，无外部图片依赖；近档与约55%面数的远档各一件Mesh。可编辑源在`tools/map/model_sources/r41/cloud_adaptations/`，结构统计在同目录`model_counts.json`。安装器为`tools/map/install_landmark_expansion_r41.py`。LOCAL按需加载，已有近期场景缓存上限仍为2。

`shared_facilities.glb`为4种WWO原创共享设施：历史货栈、机车维修厂房、农庄粮仓、采石吊装设施。每种近远两档，共8个Mesh、一份顶点色材质，没有贴图、骨骼、碰撞体、光源或动画。原创几何沿用CC0-1.0约定。生成器`tools/map/build_shared_facilities_r41.py`，可编辑源`tools/map/model_sources/r41/shared_facilities.blend`。源文件另保留隐藏的`SOURCE_ONLY_DerrickAssembly`，分离固定支架、臂架、吊索、石料与绞盘，保留对应支点；这些编辑部件不在GLB选集中，不增加运行负载。它们没有核定历史地点，只供显式启用的内部高负载配置使用，普通历史地图不放置。

内部高负载的复制建筑、树木及4件设施均标为测试实例。它们不进入WorldState、地点注册或五槽快照。只有先进入已有城市/林地LOCAL并明确选择高负载时才读取设施包；离开LOCAL清空测试节点与模板，默认启动不启用。原始7件古迹不被复制成伪造历史对象。
