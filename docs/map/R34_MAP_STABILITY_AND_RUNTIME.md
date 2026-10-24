# WWO R34 — Runtime Architecture and Map Stability

日期：2026-10-17。基线：本机最新 R33。引擎：Godot 4.6.3 Compatibility。

## 实际完成与结论边界

本轮修改地图批次显示交接和旧源数据生命周期，补齐中文运行说明。没有启动游戏，没有采集 FPS、CPU/GPU 或内存数据，没有测试或改写真实五槽，没有 Git 操作或构建清理。

**已确认旧显示退出与新显示提交不在同一步；现已修改。用户五张截图中的全部瞬时缺图、全部政治矩形是否因此消失，仍待用户运行 R34 确认。** 没有将源码修正或导出成功等同于画面验收。

完整运行图、每个主要模块的调用者、频率、线程、输入、写入、资源、停止条件和源码行号见：

[WWO_RUNTIME_EXECUTION_MAP_R34.md](D:/programs/WWO/wwo/docs/architecture/WWO_RUNTIME_EXECUTION_MAP_R34.md)

该文包含一页总览、八类流程图、经营日结子图、地图事件表、调用关系表和资源所有权表。既有实验/离线工具不被列为正式常驻系统。

## 1. 为什么可能出现只剩海洋或少数国旗的中间状态

当前地图实际经过：文件读取 → LocalSpatialLod CPU 准备 → 主线程按预算创建隐藏批次 → 下一次显示提交设置投影/样式 → SubViewport 按需绘制。

旧 `LocalSpatialLayer._prepare_step()` 在上传最后一个批次后立即调用 `_finish_political_patch()` 和 `_trim_gpu()`。前者释放旧政治/中性陆地的 CanvasItem RID；后者清掉旧 fallback LOD。此时刚上传的新批次还是 `visible=false`，相机、旗帜 sampler、比例和画布父节点要等后续 `update(..., commit_canvas=true)` 设置。

因此旧代码存在一个确定的资源命令空档：旧资源已销毁，新资源仍隐藏或未提交当前参数。若绘制请求在交接中消费此状态，就没有完整陆地可画；后续 `update()` 和着色完成后又会恢复。它与“文件最终都能读到”不是同一个正确性问题。

**这是能从源码确定的错误顺序，不是对每张截图已经完成实机复现。** 没有证据能精确说明用户某张图里仅剩的那片国旗属于哪个上传批次，也没有把一次普通日期变化直接认定为源头。

R34 改为：

1. 后台几何及主线程整批上传完成，只使该批次获得提交资格。旧物理/政治显示继续存在。
2. `update()` 先为需要显示的新批次提交父画布、当前 WORLD/REGION 投影、国旗/物理材质、裁剪矩形和可见状态。
3. 完成这些提交后，才调用 `_finish_political_patch()`、`_trim_gpu()` 释放旧政治面及旧 LOD。
4. 同一步发布配套物理引用和 `political_cells_installed()`。只有本次确有完整上传/政治补丁才执行这段收尾，不在每次无关重画时重新构造物理版本。
5. 取消或失败时，尚未提交的政治补丁即使已上传，也按暂存清掉；仍有效的旧政治面保留。

没有新建第二个地球、加载管理器、永久中性遮挡层或另一组完成标记。继续使用原 `_cpu_ready`、`_upload_political_features`、批次 complete/political_patch、available_lods 及请求代号。

## 2. 读取线程对旧显示输入的破坏

`StrategicSpatialLoader._load()` 原先接收 retired Content 后，在工作线程中设置 `retired.cancelled=true`，并把它的 shards、features、line_chunks 清空。这个对象仍被有效 `LocalSpatialLayer._content` 持有；另一个 LOD 准备线程也可能准备读取它。已有 GPU 不等于旧显示层不再需要其源内容。

这种提前退休会使旧 LOD 准备被取消、覆盖/显示查询失去原输入，后续又靠新 Content 重新安装恢复。源码能确认这一跨所有权修改，不能从截图确定它在玩家当时发生了几次。

现在读取线程只借用不变 shard 的引用，不改旧对象的 cancelled 或数组。新的输入完成后由显示层接管；旧输入在层和旧线程不再引用后自然释放。请求代号仍负责丢弃过期新结果。没有让过期线程安装地图，也没有无限保留所有视角。

**代价与限制**：旧源数组可能保留到后继接管，较提前清空的版本生命周期更长。不变分片共享引用；有变化的 ink 与有效旧显示在交接中暂时并存。这是正确交接的必要工作集，不宣称一定降低峰值内存。尚未测量实际峰值和释放延迟。

## 3. 请求、安装与日期入口核对

- 相机旋转、平移、缩放和尺度切换会使 `_resource_demand_dirty` 为真；需求仍按已有范围集合比较，相同或已覆盖请求继续复用。
- `_on_strategic_content_changed()` 使内容消费变脏，不制造相机变化。`poll()` 检查请求代号、内容类型、取消和读取错误。
- 政治升级继续复用对应物理覆盖；同范围只替换政治陆地及原可选内容，不重读 Natural Earth 原始数据或 DEM。
- `GlobeRenderer._on_current_land_changed()` 读取正式事实，R33 的 `sovereignty_changed` 继续决定真正主权切分。控制和行政变化不自动等于主权改变。
- `FormalWorldApplication._on_world_changed()` 普通跨日只更新观察日期；只有 `display_changes_between()` 确认跨有效期才刷新地图显示输入。经济变化只有当前经济主题需要时改其观察颜色，不触发物理三角化。
- 未从当前正式时间链查到“每小时主动卸载全球物理图”的调用。不能为解释截图虚构这个原因。
- 菜单地图和正式世界仍转交同一 Renderer/Controller；正式场景释放默认对象，不额外长期持有一套菜单地球。

R34 同时调整 `current_view_map_status()` 的检查次序：实际失败先返回；已有脏画布尚待提交时返回“准备提交”，不能在 CPU 已结束、尚未显示提交这一间隔报“无任务且安装失败”。没有等待 `frame_post_draw`，没有增加 15/30/60 秒的成功计时器，也没有改变失败提示、手动重试及返回流程。

## 4. 确定消除的重复工作

隐藏 Renderer 为排空其他任务，会调用两个 LocalSpatialLayer 的 `prepare_step()`。旧 `_prepare_step()` 即使没有工作线程、没有上传任务，也能走完整收尾并发出 `display_changed`，使画布、历史边界和行政需求再次变脏。

现在无准备工作且无 LOD 线程时立即返回。收尾只在完整上传之后执行，退休只在实际显示提交执行。提交中若原队列继续启动工作，原 Renderer 会保持必要 `_process`，完成后原停处理规则仍有效。没有新增忙等待、后台服务或每帧全局查询。

这些是源码冗余及错误调用修正，不是实测性能降幅。R16—R33 已有缓存、逐批上传、过期丢弃、失败保留和按需重画继续保留，未换名重复申报。

## 5. 剩余政治矩形与顶点核对

本轮沿现有输入读取了：原物理/ink 的职责、LocalSpatialLod 分组、GlobeSurfaceBatch 编码与上传、CanvasItem Mesh 命令、政治 Shader 及 WORLD/REGION 参数路径。

当前每面 6 个顶点；索引逐项为自身序号；面纹理每面 6 texel，前三个是球面顶点，后三个是 UV。Shader 以 VERTEX_ID 得到面和裁切扇。国旗由独立 sampler 提供。GPU 外接矩形没有在该函数中作为国家几何生成。已有画布 custom_rect 负责 Shader 位移后的裁剪范围，不能把原 [-1,1] 顶点包围盒直接认定为当前唯一缺图原因。

查阅了[Godot 4.6 GLES3 Canvas 的 Mesh 分支](https://github.com/godotengine/godot/blob/4.6-stable/drivers/gles3/rasterizer_canvas_gles3.cpp#L1064)及[逐 Mesh 索引绘制](https://github.com/godotengine/godot/blob/4.6-stable/drivers/gles3/rasterizer_canvas_gles3.cpp#L1313)。该路径不把这些 Mesh 拼进普通矩形顶点批次。不能因为普通 2D 合批存在，就推断它一定改坏当前 VERTEX_ID。

**尚未确认**：错误帧实际使用的批次/分片、材质引用、逐面纹理和最终投影输出。未复现驱动行为，未找到足以要求再次更改寻址的直接证据。本轮没有改 Shader、国旗 UV、美术或 geom/ink；没有以总面积或连续索引宣称 GPU 已正确。

历史国家线、历史行政线、现代物理海岸和当前控制线仍是独立来源。合法资料年代/精度差异保留；它们不能解释所有悬空矩形，也未用于掩盖程序交接错误。

## 6. 风扇负担：已知工作与未证明归因

| 情况 | 从当前代码能确认的工作 | 本轮处理 / 限制 |
|---|---|---|
| 油画首页 | 油画 Shader 使用 TIME 做 36 秒轻微运动；引擎仍需绘图 | 保留已认可美术；不能声称静态首页完全无 GPU 工作 |
| 地图静止 | 有任务才 Renderer._process；无任务关闭；地图 SubViewport 按需 UPDATE_ONCE | 移除空闲图层重复收尾；没有证据是无限帧率，已有 60 上限及 VSync |
| 窗口失焦 | 未实现自动暂停/失焦帧率分支；正式 Timer、合法后台任务不因此自动停止 | 未擅自冻结世界；实际引擎/驱动呈现需另行观察 |
| 地理需求变化 | 解压 geom/ink、政治分组、球面细分、编码、主线程 Mesh/Texture 创建 | 同需求继续复用；保留原上传预算。单批上传不是硬性 2ms 上限 |
| 政治升级 | 旧有效图与新隐藏暂存短暂共存；多批次材质及面数据 | 提交后释放旧 RID，不提前制造空图；不长期保留两套世界 |
| LOCAL 准入 | 真实地表准备、Camera3D、有限目标、建筑/地标、遮罩及拾取 | 沿用原有限缓存与离场释放；模型小不代表整套组合无成本 |
| 1× / 2× / 4× | 每次 Timer 请求 15/30/60 分钟；跨更多合法结算边界 | 不改工资、消费、企业、运输、组织或人口事实；未测量其耗时 |
| 读档 / 保存 | 快照、Variant/Base64、临时文件和完整恢复候选验证 | 保留必要保护；这不是暂停世界每帧的常驻工作 |
| 内存 | 源环、当前物理/ink、有效 GPU 批次、少量替换输入、relief、LOCAL 拾取数组 | 明确所有权与退出；未测量 MB 或显存，不把磁盘大小当内存 |

暂停只抑制 TimeControl 推进，不暂停输入、UI tween、仍在结束的读取/LOD/relief/行政任务、惯性及地图转换。Timer 每 0.25 秒仍回调，但 `paused` 时不发出推进请求。

只有正式世界才创建领域状态、Step、Persistence 和 Timer。普通首页不存在正在进行经济日结的正式世界。军事对象会初始化和保存，但未接入当前正式 Step 自动推进；具体经营切片需要现有配置或存档，不是所有研究案例都在运行。

宏观经济、个人工资/消费、旅行、住居交接及组织日评与 GPU 绘制独立。Step 在主线程按顺序执行；地图线程不改变这些领域。没有修改任何领域算法来降低负担。

不能从以上候选确认风扇的唯一原因。后续若用户另行授权，需要分别观察静止需求次数、提交边界是否缺图、主线程单批上传、合法日结和候选恢复耗时、离场后的资源回落。本轮没有实施这些采样。

## 7. 实际文件

修改：

1. `scripts/presentation/map/local_spatial_layer.gd`：延后政治替换及 LOD 退休；提交参数后才显示；保留暂存身份到提交；取消时清理未提交补丁；政治安装状态在提交后发布；空闲准备立即返回。
2. `scripts/content/strategic_spatial_loader.gd`：只读复用旧 shard，不在读取线程取消和清空仍有效的旧 Content。
3. `scripts/presentation/map/globe_renderer.gd`：队列继续准备时保持原处理入口；首屏状态先承认尚待显示提交，不误报已结束但失败。
4. `scripts/presentation/map/local_spatial_lod.gd`：仅修正文档注释，说明源输入可以由有效旧显示继续持有；算法不变。
5. `project.godot`：R34 构建标签、`wwo-r34-internal`、顺序 34；未改真实存档格式或应用版本号。
6. `export_presets.cfg`：现有内部预览预设的输出路径；正式 Release 预设不改。

新增：

- `docs/architecture/WWO_RUNTIME_EXECUTION_MAP_R34.md`
- 本报告 `docs/map/R34_MAP_STABILITY_AND_RUNTIME.md`

没有删除正式文件，没有重制地理数据，没有新增贴图、GLB、Shader、场景、相机或大型视口。地图源文件均读本机最新内容后做局部修改，没有用旧 Git 整份还原，未观察到本轮所改文件的外部并发写入。

## 8. 严格保留与交付

保留 R27 独立物理底图、R28 当前政治、R29 林地、R32 物理先行、R33 存档版本及五槽资料、海洋/极地/太阳/银河、旗帜、原史料、LandTopology、原 DEM/GIS、模型和内部许可限制。经济、人口、人物、组织、军事和 GameClock 不修改。

HUD 和底部黄铜半球仪未修改。R34 构建身份来自配置，新存档不会继续标 R33。没有读取、改写、删除或自动迁移真实五槽。没有重新启用 R30 内容或删除 R19/R30 构建。

唯一交付目标：

`D:/programs/WWO/wwo/builds/preview_2026-10-17_runtime_map_stability_r34/WWO_1900_Runtime_Map_Stability_R34_Preview.exe`

沿用 Windows Desktop Internal Landmark Preview、x86-64、嵌入 PCK。保留 R33 为主要回退，R32/R29/R28 及其他受保护对照、正式 `builds/windows` 不覆盖。正常导出结果在文末记录，不自动运行预览。

仍待实机确认：瞬时大陆缺失是否消失、政治完整替换、连续缩放/旋转和 WORLD/REGION 交接、剩余矩形、窗口失焦行为及实际资源负担。后续仅需用户先打开本预览观察，不要求本轮进行额外压力测试。


### 最终正常导出记录

Windows 内部预览预设导出退出码 0，savepack 完成。EXE 为 346,801,752 字节。导出日志没有 SCRIPT ERROR、Parse Error 或 ERROR；保留既有 `0.001a` 版本字符串警告。未运行游戏，因此没有以导出日志代替实际地图验收。

同一 R34 目标文件保存最终内容，没有生成另一候选预览。交付目录附两份 Markdown 运行说明及原来源、许可说明。没有采集截图、运行额外门禁或新增诊断脚本。完成后停止。
