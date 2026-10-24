# R57实机画面、缩放与UI整改

2026-10-20。R57继续为CANDIDATE，R56为ROLLBACK；未执行promote。

后续全球精度盘点、队列续接及REGION发布整改见[R57全球精度与稳定性](R57_GLOBAL_TERRAIN_QUALITY_AND_STABILITY.md)。本报告保留此前灰带、缩放和UI施工记录。

读取R54、R56、R57及构建治理报告。用户12张游戏截图和追加3张俄国游戏截图为失败基线；其余追加图片是设计说明。图片没有相机记录，未把推定坐标写成截图的精确位置。

## 根因与修改

| 故障 | 直接证据 | 修改 |
|---|---|---|
| 西班牙、维也纳、法国／瑞士的灰带 | 普通Godot窗口复现。维也纳16.4E/48N、400mpp，`repair_r57_mid8_r56_40_+16`与`repair_r57_mid8_r56_48_+16`已绑定、编码6、有效覆盖1，但两张贡献都为0；3707米共同概览贡献接管 | `MapRelief._detail_edges`不再因整页最差DEM精度不同，强制相邻已安装页同时退回基底。保留暴露边缘渐退；使用真实重叠邻边，不拉宽渐退 |
| 相邻贡献不足再次漏出概览 | Shader用四张权重的最大值作覆盖强度。两个互补权重各0.5仍会漏出一半基底 | `surface_detail`以`min(sum,1)`表示联合覆盖，颜色仍按权重归一；探针CPU重建同步修改。没有重复叠加阴影 |
| Benelux整个可选层被拒绝 | 索引ID仍为`benelux_hydro_overview_r46`，路径实际指向`benelux_hydro_overview_r48.json/.geom`。`lake:zuiderzee_near1900_reference_r46:benelux_hydro_overview_r46`的查询类型为Polygon；加载协议的lake必须为MultiPolygon，导致查询及coarse/medium均失败 | 将这一个查询外壳正规化为MultiPolygon；坐标、岛屿孔洞、762个显示三角形不变。制作器同步修复。未删河流、未放宽校验 |
| ARCHIVES滚轮、拖条及百科按钮失效 | 普通窗口注入同一路径GUI事件，修改前滚轮0、拖条0，命中GlobeRenderer，百科仍在map页 | `FormalWorldApplication._enter_tree`复用菜单Renderer后，将其移回MainShell之前。Godot GUI命中顺序由场景树决定，`z_index=20`只保证画面层级 |
| 状态刷屏、滚动位置重置 | 连续准备／安装状态形成多条map消息，重建列表固定回到0 | MainShell合并相邻非错误地图状态；错误及领域消息保留。列表更新保留滚动位置 |

灰带修正未重制任何地貌BIN。编码6的RGB、A、Mip未改变；共同概览仍在，无新采样器。基底A作为中性DEM明暗，不代表分类有效性。粗分类在近档减弱的既有设计仍保留；本次不能把所有灰色平原都视为错误。

## 普通窗口取证

复用`GlobeRenderer._dump_terrain_point`、`TerrainPixelSource.inspect`。外部有限驱动进入原油画菜单、国家选择、正式新世界并暂停；没有独立展示地图。输出在`local-artifacts/r57_visual_repair/`，不入EXE。

隔离目录：`C:/Users/agcrf/AppData/Roaming/WWO_R57_Visual_Repair`。没有读取、转换或保存真实五槽。诊断仍只覆盖原有两份`r57_terrain_point.json`、`r57_terrain_pixel.png`；选点结果汇总为每次覆盖的一份bindings.json，无持续逐帧日志。

Godot4.6.3 Compatibility，1280×720，NVIDIA GeForce RTX3050 Laptop GPU，驱动572.83。普通窗口，无GUI自动化；事件由现有Godot输入路径提交。未锁定前台，未执行FPS、GPU或显存基准，因此不作性能改善结论。

| 代表窗口（明确设置，非还原原截图相机） | mpp | 取证 |
|---|---:|---|
| 西班牙北部 -7.5E/42.5N | 400 | -8E两张8度页共享边；修改前两边均保留0.35度退回基底，修改后共享边为0 |
| 维也纳16.4E/48N | 400 | 40/48N、8/16E四页交界；修改后共同边不再使两侧贡献归零 |
| 法国／瑞士6.5E/46.6N | 300 | `repair_r57_mid8_r56_40_+0`与`...40_+8`，检查8E交接 |
| 莫斯科邻区36.5E/56N | 400 | 48/56N、32/40E四页；检查准备、完整medium发布及静止状态 |
| Benelux4.9E/51.7N | 400 | 检查正式对象准入、绘制批次及须德海显示 |

`before/*.png`为修改前普通Godot最终viewport；`after/*.png`为新候选实际窗口。同名bindings.json记录每窗口三个点的真实绑定、像素颜色、源精度和几何状态。CPU估计Mip单独标记，GPU隐式Mip仍为“无法直接取得”。不将CPU重建当作GPU测量。

最终EXE的五窗口均为完整medium、preparing=false、无几何错误。维也纳中心两张页贡献由0/0变为1/1，按归一权重混合；人工灰带在西班牙、维也纳、法国／瑞士窗口消失。俄国代表窗口静止后保持已安装，源分类与DEM精度差异仍可见，不称为均匀高清。Benelux实际内容含186项，须德海GPU水面批次可见；窗口中的河流与水面均保留，没有可选层错误。

一次候选取证因静态窗口没有主动发布下一帧，使外部驱动等待`frame_post_draw`超过210秒而停止。驱动随后只在指定捕获时调用`RenderingServer.force_draw(false)`，普通游戏代码不强制逐帧绘制；同一候选已完成五窗口、连续缩放和正常退出。这不是游戏加载耗时或FPS样本。没有因此再导出EXE。

最终候选的GUI输入检查：滚轮38像素，拖条到323像素，地图尺度不变；独立帮助检查实际进入`world/index_category=help`。准备→已安装→重复已安装三次反馈只新增1条地图记录。有限连续35次放大停在54.2944mpp，10次缩小至396.6008mpp，返回WORLD后地貌纹理只剩`world`。没有实测触控硬件或完整长期性能。

修改前四个静止窗口均已发布完整medium，未复现“缺少当前完整LOD”。俄国原截图提示本身不能证明死循环。本轮没有修改StrategicSpatialLoader、LocalSpatialLod或LocalSpatialLayer的准备／发布合同，不能宣称旧几何提示已根治。

## 缩放边界

原REGION硬下限2mpp，LOCAL入口200mpp、退出280mpp；LOCAL查询圆可达300km，这不表示圆内处处有街区或精细DEM。

现在滚轮下限按当前位置实际有效DEM／输出格网的较粗者确定：最多约4屏幕像素表达一个真实采样。GLO细片217米格网约54.29mpp；仅60角秒ETOPO约463.31mpp。判定读取当前目录及替代关系，不下载、不解压、不预加载。原先已处于更近尺度或平移到粗区时，不强制缩远。

有实际LOCAL原生DEM时，限于其真实坐标矩形，采用格网间距和原有local_min_mpp；已有模型周围有限2.5km观察邻域可继续按既有下限观察模型。这不是已建成城市边界，也不将整个300km分片认作LOCAL。LOCAL自动准入同时核对此条件。边界前减缓滚轮，达到上限给出说明；缩小、旋转、返回WORLD仍沿原相机路径。

局部相机检查：80次放大稳定在指定75mpp，中心锚点误差0；换成400mpp资料限制后不强行跳远。资料不同的屏幕外围仍可能较粗；没有声称全国均匀细节。缩放限制没有代替400/300mpp下的灰带修复。

## LOCAL城市与村庄：能力审查及设计

**本节是设计，未实现新的建设动作。**

现有`LocalSpatialContent.settlement_visuals`、`RegionView._settlement_demand/_update_settlement_batches`支持同一地理锚点、共享模块Mesh、MultiMesh及近远LOD；已有布局是显示参考。`CivilianFacilityLayer`使用旧economy_r1站点外观代理；它不能直接代表当前Formal逐栋权属或建筑坐标。VNext基础设施有construction状态，但不等于完整聚落建设链。

| 显示单元 | 可复用结构 | 正式接入条件 |
|---|---|---|
| 城市中心、街区、住宅、公共建筑 | 正式place_id下的局部米制坐标；共享住宅／公共模块，远档街区包络，近档实例 | 有来源的参考布局与正式建设结果分别标记；无坐标不猜造逐栋史实 |
| 工商业、车站、仓储、道路 | 设施／站点ID绑定既有经济与交通对象，复用模型、共享材质 | 由唯一正式对象给出位置、用途、状态和完成量；三个专题图消费同一对象 |
| 村庄、农舍、农业设施 | 村核、生产设施、道路连接、建成区包络；不随机填满田地 | 土地使用、资金、物料、人口／劳动力、组织及建设进度由Formal权威状态提供 |
| 扩建 | 现有place及地块下的建设项目引用；只更新受影响实例 | 先实现合法用地、支付／物料、劳动与运输、施工进度、完工资产的领域链，再显示阶段结果 |

“5×5”采用约5km×5km观察邻域或5×5可按需准备的小片组织参考；不是重切正式LandTopology，也不是新增军事世界。实际范围由聚落包络与可用DEM决定。LOCAL使用原相机、时间和领域事实；不生成重复全球地表。当前微缩模型和少量地标不等于可活动、可扩建的完整城市。

下一步应先选一个已有正式城市与一个村庄，在Formal内补齐建设命令、状态归属与完成事件，再给既有LOCAL批次提供只读投影。当前无此完整合同，不新增假按钮、演示场景或独立存档。

## 文件、资源及候选

正式修改：`scripts/presentation/map/{map_relief,terrain_pixel_source,region_camera,globe_controller,globe_renderer}.gd`、`shaders/presentation/map/france_surface.gdshaderinc`、`scripts/content/local_spatial_content.gd`、`scripts/formal/formal_world_application.gd`、`scripts/presentation/ui/main_shell.gd`、`data/strategic/{index.json,benelux_hydro_overview_r48.geom}`、`tools/map/build_zuiderzee_display_r48.py`。

新增有限外部工具：`tools/map/{r57_visual_driver.gd,run_r57_visual_repair.py}`及本报告。Godot产生的对应UID保留。没有删除正式文件。

新增DEM、分类源、地貌BIN：0；原有87份R57替代资源未重制。水文geom为258,796B，比原258,805B减少9B。最多2概览、4活动细片、1后台解码的上限不变。WORLD退出仍只保留world地貌纹理。349份旧制作依赖不删除。

新候选1,382,617,664B，较原R57增加2,336B；嵌入PCK为1,278,098,996B。一次正式导出写入约1.38GB，使用同卷替换，没有另复制完整包。诊断目录合计约14.2MB，普通运行日志均为KB级。构建入口自动清退结果0文件／0B：没有符合删除条件的其他旧普通候选。没有新地貌上传；Benelux恢复正常水文准备和上传，其开销不冒充为零。

唯一候选仍为`D:/programs/WWO/wwo/builds/preview_2026-10-19_raster_r57/WWO_1900_Terrain_Raster_LOD_Integrity_R57_Preview.exe`，通过`tools/build_preview.ps1 build --version R57`原路径更新；不新增R58。唯一必要回退为`D:/programs/WWO/wwo/builds/preview_2026-10-19_sampling_r56/WWO_1900_Terrain_Sampling_LOD_Coastline_R56_Preview.exe`。

R39相机与24份coarse、R54有界安装与释放、政治日期修正、正式领域及黄铜半球仪未改动。相机只增加资料能力约束，没有等待全部高清资源的门控。没有宣称启动仍精确8秒，也没有宣称不存在性能回退。

## 玩家仍需验收

在原失败地点对比灰带、普通比例接缝、连续缩放和跨区返回；检查真实存档环境的ARCHIVES输入、百科／帮助、启动等待及明显长帧。既有源级分辨率差异、未配准的原截图相机、未复现的几何错误、全局海岸近景精度仍未关闭。技术导出及本轮有限普通窗口取证不能替代玩家确认。
