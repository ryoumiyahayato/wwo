# R3 地图性能修复交付记录

2026-10-10。本轮直接修改现有加载器、LOD、图层和批次。存档保持 `formal_world_simulation_v15`。未修改世界推进、经济、人口、军事、组织或土地规则。

正式包：[wwo-map-performance-r3.exe](D:/programs/WWO/wwo/builds/windows/wwo-map-performance-r3.exe)。已完成原生启动检查。完整统一验证有十年时限失败，见本文末尾。旧正式包 `wwo-map-correctness-r3.exe` 保留用于回退。

## 对照口径

直接基线是本轮开工时冻结的 `local-artifacts/map-correctness-r3/perf-continuation-before-project`。它包含 R3 和 continuation batch1。历史 CSV 的 25–26 ms 不作为本轮复测值。

同机 RTX 3050 Laptop GPU、Godot 4.6.3 Compatibility、1280×720、Balanced 电源方案、60 FPS、VSync、暂停、Political、Labels ON、战略铁路 OFF。两版均运行三轮：首次进入 FAR → 拖动/缩放 → MID 滚轮跨 LOD/分片 → NEAR → Paris Local → WORLD → FAR。每轮 FAR 拖动、缩放各 12 秒，MID 滚轮 12 秒。FAR 段没有新加载或准备。

拖动和缩放按墙钟时间生成相同轨迹。滚轮每 350 ms 一次，四次缩小、四次放大。实际帧采样时刻和端点有小幅差异；CSV 保留各轮 m/px 范围。正式前后采样分别为 20:08:53–20:12:10、20:12:51–20:15:45（台北时间）。全部 7,119 / 7,214 个记录帧均有窗口焦点。自己的导出、数据生成和统一验证均未与采样并行。

铁路开启补充采样及截图阶段发现其他军事、经济研究 Godot 进程；未终止。开工时也曾有其他 Python 进程。主对照没有连续保存其他进程占用，不能宣称系统全程无干扰。板卡功耗包含其他任务与桌面。原生自动输入和 PNG 属于自动检查，不称为人工验收。

最终前后使用同一修正后的测量器。早期诊断发现 MID 滚轮助手与外循环各等待一次帧，且无输入时仍发视图变化；已修正，并重新导出、重测两版。正式结果只用 `perf-paired-before` 和 `perf-paired-after`，不混入早期诊断成绩。测量器、测试和诊断开关均不进入正式包。

## 逐轮性能

单位 ms。单元格为 p50 / p95 / p99 / max。轮次从 1 开始。

| 操作 | 轮次 | 修复前 | 修复后 |
|---|---:|---|---|
| FAR 拖动 | 1 | 16.673 / 19.683 / 23.668 / 39.674 | 16.626 / 18.037 / 20.016 / 22.253 |
| FAR 拖动 | 2 | 16.630 / 18.179 / 20.526 / 25.250 | 16.626 / 18.031 / 20.344 / 27.777 |
| FAR 拖动 | 3 | 16.881 / 21.689 / 29.014 / 34.192 | 16.636 / 17.837 / 18.689 / 22.118 |
| FAR 缩放 | 1 | 16.602 / 19.232 / 22.168 / 26.068 | 16.647 / 17.793 / 18.586 / 24.285 |
| FAR 缩放 | 2 | 16.607 / 18.094 / 20.548 / 30.127 | 16.697 / 18.601 / 22.088 / 26.083 |
| FAR 缩放 | 3 | 16.605 / 21.842 / 24.171 / 27.864 | 16.666 / 18.296 / 21.067 / 25.336 |
| MID 缩放 | 1 | 16.580 / 27.270 / 37.536 / 73.858 | 16.754 / 18.563 / 22.632 / 26.718 |
| MID 缩放 | 2 | 16.574 / 26.528 / 38.122 / 96.357 | 16.699 / 19.542 / 22.729 / 24.239 |
| MID 缩放 | 3 | 16.541 / 27.471 / 47.088 / 120.416 | 16.704 / 19.683 / 23.363 / 28.275 |

新版本三个操作的三轮 p95 均低于 20 ms。已记录操作帧中未出现 50 ms 以上帧。FAR 第二轮拖动 max 从 25.250 增至 27.777 ms，保留原值。未对所有切换、所有地区的长帧作消失声明。

静止 FAR 三轮地图重绘增量均为 0；退出地图后的重绘增量为 0。静止的 `draw_calls` 是最近一次绘制的缓存统计，不能当作持续 GPU 工作。

铁路开启一轮：FAR 拖动 p95/max 18.056/23.350，FAR 缩放 18.471/31.870，MID 缩放 18.119/23.447 ms。它有上述外部任务干扰，仅作功能和补充性能检查。固定欧洲 MID 的铁路 UI 开关未增加读取次数或驻留缓冲；原有探针断言通过。

## 热点及替换

* `GlobeBoundaryBatch.prepare` 原来为每个线段建立 Dictionary，并反复追加数组。现在 `encode` 计数、预分配并直接写 packed 数组，工作在线程中完成；主线程 `upload` 只创建渲染资源。接头、端点和 shader 数据槽保持原有语义。
* `GlobeSurfaceBatch` 同样拆分 CPU 编码与主线程上传。LOD 结果消费后移除临时上传数组与显示面 Dictionary。世界面的拾取数据保留。
* `LocalSpatialLod.prepare` 按已有种类、水面类别和国家纹理关联合并兼容组。战略线组目标 1,024 段、面组最多 2,048 面；不改变三角形顺序，不合成全球批次。首个 FAR 上传批次 224 → 184，可见批次 189 → 149，海岸可见批次仍为 56。
* `StrategicSpatialLoader._load` 用已知几何深度的点遍历替换递归 Variant 验证。格式、有限数值、范围、几何形状、标识与原有完整性校验保留。索引只读共享，删除线程绑定时的深复制。已有 worker 在边界检查请求代次，过时结果不能回写。
* 分片交接曾在主线程释放旧 JSON/通用数组。诊断中的 `begin` 约 104 ms、`poll` 约 75 ms。现在既有来源 worker 替换旧数组，旧显示仍由 GPU 批次持有。LOD worker 内部取得来源数组，删除把大 Array 绑定到 Thread 回调后在主线程销毁的路径。中间版本该路径仍有约 37 ms 准备停顿，最终版本已替换。
* `LocalSpatialLayer.prepare_step` 等待线程时返回无进展，不触发重绘；退出时使结果失效，最终销毁才 join。没有新增全局队列或第二套加载状态机。
* `GlobeRenderer` 对区域国家面使用保守球面范围剔除。只更新可见面的连续外观参数；外观切换仍绑定所有国家。区域锚点只计算选中、悬停标记。`LocalSpatialLayer.update` 复用种类样式、减少相机参数写入和重复字典处理；标签碰撞遇到首个交叉即停止。
* `RegionView` 复用 16/20/24/28 四档国名字形节点，删除跨字号反向缩放时销毁重建节点的路径。文字仍移动和避让。

第一轮 FAR 拖动的视图更新 p50 1.395 → 0.651 ms，标签/图层更新 3.956 → 3.179 ms；FAR 缩放对应为 1.438 → 0.695、5.082 → 3.993 ms。`last_submit_usec` 从 `_draw_surfaces` 起算，不包含前面的 view；不能把总值与 view 再重复相加。第一轮 MID 视图更新次数 280 → 118，地图重绘 369 → 122；等待准备的帧不再持续提交。

最终 MID 逐帧分类区分来源启动、内容 begin、上传入队、等待准备和无准备。第三轮 28.275 ms 帧的主线程 poll/prepare 为 2/5 μs，标签/图层更新 6.881 ms。没有证据把全部帧间隔归因到某个地图函数。上传量和 CPU 入队计时有记录；GPU 执行时间、驱动材质切换次数未直接测量。

完成后的 FAR 只驻留 coarse LOD；交接期间沿用一档 fallback，替换完成即释放。未发现稳定画面同时提交多代 LOD 的记录。陆海差分修正面与政治底面仍按原裁切语义覆盖，未取得像素级 overdraw 计时，不能宣称已消除全部重复像素工作。

历史 draw_calls 增量也不是海岸已确认根因。R3 紧凑化改变顶点/索引数，未减少旧 LOD 分组数量。历史 WORLD 静止整帧提交已有 310 → 354；batch1 城市圆弧抗锯齿、国名字形节点和出处 CanvasItem 会拆分整帧命令。未取得驱动级逐层归因，不能把 FAR 的 +57/+81 全算给海岸。本轮三轮 FAR 拖动提交中位数 534/529/529 → 414/408/406；FAR 缩放 617/620/620 → 491/494/494。国界、城市、文字和菜单仍显示。

## 首次 FAR

从进程首次请求该地区计时；没有清空操作系统文件缓存，不称为 OS 冷加载。第 2、3 轮是同进程重新加载。新裁切面完整后原子交接，因此首次有效新内容与完整显示是同一帧，旧底图不计入。

| 轮次 | 修复前：请求后新内容完整显示 | 修复后 | 修复后：第一次缩放输入后 |
|---:|---:|---:|---:|
| 1 | 4.714 s | 2.774 s | 3.339 s |
| 2 | 4.575 s | 2.985 s | 3.036 s |
| 3 | 4.599 s | 2.369 s | 2.406 s |

表中请求后时间由 worker 开始计时；新版本请求到 worker 开始为 0.306/0.424/0.407 ms。第一次缩放输入包括 WORLD → FAR 的输入路径，单独保留。完整内容的 3 秒目标在请求口径达到；第一次输入口径第 1、2 轮仍超过 3 秒。1.5 秒开始显示目标未达到，未在菜单预载地图。

固定欧洲 MID（1200 m/px）的补充截图旅程中，新分片完整显示 1.642 → 0.971 秒，CPU 资源创建及入队 189.169 → 14.766 ms。该旅程单独进行且有外部任务干扰，不混入三轮性能分位数。

第一轮耗时（ms）：

| 阶段 | 修复前 | 修复后 |
|---|---:|---:|
| 来源 worker 总时间 | 1,112.265 | 1,048.012 |
| 描述分片读取 / JSON 解析 | 6.160 / 7.874 | 6.293 / 7.723 |
| 来源解析与验证（含下三项） | 693.950 | 632.702 |
| 压缩几何解码 | 76.479 | 76.205 |
| 既有完整性校验 | 72.698 | 73.814 |
| 几何 JSON 解析 | 213.747 | 211.390 |
| 来源几何整理 | 39.836 | 38.350 |
| LOD worker 准备 | 1,039.561 | 1,094.462 |
| 其中：几何 / 上传数组编码 | 未拆分 | 751.627 / 342.834 |
| 来源 worker 完成到主线程 poll | 未拆分 | 5.779 |
| LOD worker 完成到主线程 poll | 未拆分 | 5.156 |
| CPU GPU 资源创建及入队累计 | 587.615 | 87.289 |
| 图层准备墙钟时间（含 LOD 和上传） | 3,531.922 | 1,702.345 |
| 减去 LOD、入队、标签 CPU 后的调度残差 | 1,902.773 | 518.798 |

嵌套项目不相加。来源验证还包含资产读取及未单独拆分的校验，不能把描述分片读取当成所有文件读取。调度残差包含跨帧处理及其他准备，不是纯队列等待。CPU 入队不是 GPU 执行计时。剩余来源处理约 1 秒、LOD 处理约 1 秒，仍限制首次显示；保留完整面交接以避免半套裁切与旧面混合。

## 资源

三轮操作窗口内的系统样本合并中位数。CPU 为 20 个逻辑处理器归一化。GPU 为该进程 Windows GPU Engine 的最高引擎占用。板卡 W 为 nvidia-smi，非游戏独占值。系统采样实际中位间隔约 2.2 秒，不能作为瞬时峰值。

| 操作 | CPU % 前→后 | 进程 GPU % 前→后 | 板卡 W 前→后 |
|---|---|---|---|
| FAR 拖动 | 3.979 → 3.363 | 22.876 → 23.824 | 9.77 → 8.35 |
| FAR 缩放 | 4.339 → 4.151 | 24.124 → 23.599 | 8.70 → 8.24 |
| MID 缩放 | 9.068 → 6.539 | 11.456 → 4.076 | 7.87 → 4.34 |

FAR 拖动 GPU 未下降。第一轮 19.594 → 23.850%，后两轮 23.894/22.870 → 23.741/24.175%。不能仅凭本次粗采样证明 GPU 成本全面降低。静止 FAR 重绘为 0；新版本静止样本进程 GPU 为 0，前版部分样本覆盖入场后的 GPU 收尾。

| FAR 拖动工作集 MiB | 第 1 轮 | 第 2 轮 | 第 3 轮 |
|---|---:|---:|---:|
| 前 | 772.449 | 860.863 | 874.691 |
| 后 | 783.293 | 875.988 | 896.426 |

FAR 常驻工作集未达到下降目标；增加约 1.4–2.5%。私有提交也有约 16–18 MiB 增加。没有增加全球常驻资料或多代 LOD，不能据此把 OS 工作集增长解释成已证明的某个原因。MID 三轮工作集 870.027/819.400/920.586 → 732.371/838.676/847.668 MiB；第二轮仍增加。

启动至首次 FAR 静止的采样峰值：工作集 832.527 → 796.867 MiB，私有提交 1,081.852 → 1,084.488 MiB；专用 GPU 225.109 → 225.105 MiB，共享 GPU 67.242 → 67.238 MiB。仅 6/5 个系统样本，包含启动和 WORLD，不作为精确瞬时加载峰值。操作阶段专用/共享 GPU 逐轮值保存在 CSV。

活跃 FAR 几何缓冲 25,112,736 → 25,104,544 bytes；来源编码字节 4,653,163、解码 JSON 字节 15,949,308、packed 向量字节 5,529,540 保持相同。这些表示同一份数据在不同阶段的体积，不能相加为 RAM。8192 bytes 的缓冲差是分组填充差，未减少几何细节。旧来源数组在线程中退休；上传数组消费后释放，未增加永久副本。

## PNG、记录与修改文件

原始 PNG 对照位于 `local-artifacts/map-correctness-r3/`：

* `perf-paired-before/`、`perf-paired-after/`：`crimea_400/200.png`、`denmark_400/200.png`、`memel_400/200.png`、`normandy_400/200.png`、`calais_400/200.png`，以及三轮 WORLD/FAR/MID/NEAR/Local 截图。
* `perf-paired-before-visual/`、`perf-paired-after-visual/`：相同中心的 `europe_far.png`（4500 m/px）、`europe_mid.png`（1200 m/px）、`paris_local.png`（75 m/px）、铁路和显示菜单。它们用于画面对照，不混入 1280×720 性能结果。


| 视角 | 前 | 后 |
|---|---|---|
| 克里米亚 m/px | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/crimea_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/crimea_200.png) | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/crimea_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/crimea_200.png) |
| 丹麦 m/px | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/denmark_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/denmark_200.png) | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/denmark_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/denmark_200.png) |
| 梅梅尔 m/px | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/memel_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/memel_200.png) | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/memel_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/memel_200.png) |
| 诺曼底 m/px | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/normandy_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/normandy_200.png) | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/normandy_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/normandy_200.png) |
| 加莱 m/px | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/calais_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before/calais_200.png) | [400](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/calais_400.png) / [200](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after/calais_200.png) |
| 欧洲 FAR | [PNG](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before-visual/europe_far.png) | [PNG](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after-visual/europe_far.png) |
| 欧洲 MID | [PNG](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before-visual/europe_mid.png) | [PNG](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after-visual/europe_mid.png) |
| Paris Local | [PNG](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-before-visual/paris_local.png) | [PNG](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/perf-paired-after-visual/paris_local.png) |

逐张检查上述海岸及欧洲/Paris 前后 PNG。孔洞、岛屿、岸线填色关系、政治纹理和国界未见回退。海岸 200 m/px 使用原有资料精度，既有“更详细地图资料尚不可用”提示仍保留。欧洲国名、城市名、地形与 Paris 水系/铁路仍显示。截图不能证明操作过程每一帧均无错误；局部回归另有行为检查。

五张表均在同一目录：

* [performance-continuation-comparison.csv](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/performance-continuation-comparison.csv)：每轮帧分位、提交、焦点、尺度、加载/准备次数与静止重绘。
* [performance-continuation-load-stages.csv](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/performance-continuation-load-stages.csv)：每轮来源、LOD、上传和可见时间。
* [performance-continuation-resources.csv](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/performance-continuation-resources.csv)：每轮 CPU、GPU、功耗、工作集、私有提交、专用/共享 GPU。
* [performance-continuation-submit-parts.csv](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/performance-continuation-submit-parts.csv)：视图、面、边界、文字/图层、城市/出处 CPU 时间。连续相同的旧快照仅记一次；实际更新次数另列。各部分分位数不能相加。
* [performance-continuation-mid-frames.csv](D:/programs/WWO/wwo/local-artifacts/map-correctness-r3/performance-continuation-mid-frames.csv)：MID 的帧分类。分类按记录到的加载/准备计数和累计入队变化推断，含采样边界，不等于线程完整执行跟踪。

产品修改：`scripts/content/local_spatial_content.gd`、`strategic_spatial_loader.gd`；`scripts/presentation/map/globe_boundary_batch.gd`、`globe_surface_batch.gd`、`local_spatial_lod.gd`、`local_spatial_layer.gd`、`globe_renderer.gd`、`region_view.gd`。相关测试 `formal_global_strategic_geography_test.gd`、`formal_hydrography_presentation_test.gd`、`formal_map_scale_utilization_test.gd` 适配新的 prepare 参数、face_count 和编码后的几何表示，保留原有来源和行为断言。现有 `tools/map/map_correctness_release_probe.gd` 增加流式测量模式；`build_map_correctness_probe.py` 删除额外导出文件指纹计算。未新增性能平台、调度服务、架构门禁或资产格式。

## 验证与包

局部检查：R3 correctness 81、resource efficiency 47、hydrography 159、global strategic geography 2647 checks，均 0 failures。主要修正后启动一次现有 `tools/run_validation.ps1`。Map visual scale utilization 测试仍访问已删除的临时 boundaries 表示，发生脚本错误并达到原 240 秒超时。适配该测试：检查编码后的每段及其邻点属于同一原始稳定 feature，并检查原来源 fact ID；未增加产品元数据或跳过检查。随后使用原脚本的函数、剩余测试表及收尾步骤，从失败项续跑；未重复前面已通过的经济、存档、土地和人口检查。十年测试的内部 240 秒限制保留。首次适配还误读了原数组没有保存的 source_fact_id，修正为查询来源事实目录；该失败进程停止后再次从失败项续跑。三份日志：`perf-continuation-validation.log`、`perf-continuation-validation-resumed.log`、`perf-continuation-validation-resumed-final.log`，位于原 artifact 目录。产品源码和正式采样未因测试适配改变。

统一验证结果：35 个原测试组最终通过；十年组 42 checks、1 failure。十年模拟完成 87,600 小时，耗时 249.337 秒，超过原内部 240 秒；其余 41 项检查通过。没有修改模拟、测试时限或数据来绕过失败。不能称统一验证全绿。十年失败后仅接续未执行的最后测试和原收尾步骤，日志 `perf-continuation-validation-tail.log`；该日志的原脚本结尾 passed 文本只适用于所执行的收尾，不覆盖十年失败。未重跑十年。

正式 Windows Release 导出退出 0，204,014,496 bytes。产品 EXE 原生 Compatibility 启动 120 帧后退出 0，stderr 为空；这项是菜单启动检查，不是完整人工旅程。日志 `performance-product-export.log`、`performance-product-startup.log`。既有 0.001a Windows 数字版本警告仍存在。两版原生探针三轮、铁路一轮、固定视角旅程均退出 0，无 stderr；快照未变化，schema 为 v15。正式包与最终探针使用相同产品源码；探针额外带测量脚本，正式包不带。

本轮五个临时探针 EXE 已删除。保留新正式包、旧正式回退包、冻结来源及测量记录。

本轮剩余目标：1.5 秒首显、FAR 工作集下降、驱动级材质/GPU 执行归因，以及统一验证的十年 240 秒时限。完成本次包交付后停止，不继续其他地图功能。
