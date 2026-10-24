# WWO R35 — Stable Map Display and Build Cleanup

日期：2026-10-17。基线：本机 R34。引擎：Godot 4.6.3 Compatibility。

本轮修改当前视野的发布条件、WORLD/REGION 画布提交和完成通知。没有运行游戏。没有将导出成功视作画面验收。截图中的大弧形尚未锁定到具体绘制对象。

## 1. 截图4→5→6：没有操作，为什么画面仍会变化

按用户确认，这三张截图期间没有相机操作。后台文件读取、LOD 准备、分预算上传和政治升级仍可继续。它们分别由 `StrategicSpatialLoader.poll()`、`LocalSpatialLayer.prepare_step()` 和 Renderer 的提交处理推进，不需要新的鼠标输入。

R34 已把新建批次设为隐藏，整次上传结束才标记完成。本轮没有发现“每上传一个新分片，就直接将其设为可见”的代码，不能把截图4直接说成第一个新分片的上传结果。

但确认了另一条能暴露不完整范围的公共路径：

1. `RegionView.prepare_step()` 完成的是样式记录和历史边界，随后 `ready=true`。它没有准备战略物理分片。
2. `GlobeRenderer._ensure_view()` 原来仅凭 `camera.active && region_view.ready`，就显示 REGION 容器。
3. `LocalSpatialLayer.update()` 可以选择前一个完整 LOD 或 `_fallback_batches`，立即将它们重新投影到新区域。
4. 这些旧批次对旧请求完整，不代表覆盖新 REGION 的全部范围。旧覆盖之外会露出海色；原物理分片边缘会表现为直线缺口。
5. 后继物理包完整上传并提交后，范围才补齐；同一加载器的政治升级随后再替换成国旗。

这是从源码确认的提前发布条件，能够产生上述阶段变化。没有错误帧的批次记录，不能逐片认定截图4中每块陆地的资源 ID。

## 2. 实际修复：先确认整组范围，再公开 REGION

`StrategicSpatialLoader.request()` 现在单独保存本次相机所需的物理分片集合。原 `_wanted` 仍负责有界读取和复用；它可能是较大的已完成或在途窗口，不再被直接等同于当前画面必需范围。没有扩大请求到全球全部456片。

`LocalSpatialLayer.can_present_physical()` 复用已有状态判断：

- 当前已安装的物理版本是否覆盖全部必需分片，且 LOD 相同。
- 或者，后继包是否已结束整次 GPU 资源创建、目标 LOD 可用，并包含全部必需分片。
- 已结束但属于其他范围的暂存结果，不借用旧物理引用冒充当前范围完整。

`GlobeRenderer._draw()` 在移动批次、提交投影、改变容器显示和请求视口更新之前检查这一条件。区域样式未完成时也不提交。覆盖不足的旧 fallback 不再被重新投影后公开为完整新区域。

旧完整范围仍适用于当前视野时，可以正常重画；不适用时保留上一张已提交纹理作为过渡，并使用已有准备提示。此时暂不按新坐标进行悬停或选取，滚轮仍可提出新需求。新范围完整后再提交。没有新遮罩、第二个 REGION 或按地名偏移。

没有以等待秒数判定成功。若既没有完整可提交范围，也没有正在进行的必要准备，并且没有已有具体错误，原 `map_notice` 会报告“当前视野没有可完整提交的物理地图”，保留旧画面。首屏沿用原失败、取消和重试入口，不自动无限重试。

## 3. WORLD 与 REGION 曾存在的投影不一致

R34 的 `_draw()` 用 `camera.active && region_view.ready` 决定重画哪个视口，但地理图层 `update()` 直接用 `camera.active` 决定投影和父画布。

所以在相机已进入 REGION、区域样式尚未完成时，前者仍可重画 WORLD，后者却已将陆地移到 REGION。这不是正常海岸精度差异，也不需要新的玩家输入才能在后台完成时恢复。

现在未满足同一完整范围条件就不移动批次，不重画目标。允许提交时，区域样式、物理包、相机投影、材质和目标视口使用同一观察状态。R34 已有“先设置参数，再显示，最后退休旧资源”的顺序保留。

## 4. 截图7→8的大弧形：已查到什么，没查到什么

**未查清实际产生截图7弧形的对象。** 本轮没有原错误帧的对象/RID、材质和最终顶点输出，也未运行游戏。不能凭描述将它认定为海冰、太阳高光、某个 Shader 或驱动错误。

读到的对象关系是：WORLD 使用既有3D海洋前半球和2D陆地/边界；REGION 使用既有2D背景、陆地、注记和有限 LOCAL 目标。海洋半球、政治/水面双扇裁切、海冰、太阳和 MapRelief 均已阅读。本轮没有在这些 Shader 中找到足以锁定该大弧形的直接证据，因此没有随机增加 Shader 判断。

确认了会影响这类瞬时画面的交接问题：

- `_begin_transition()` 原来在目的物理范围未完整时就启动0.22秒渐变，并改动离场样式/边界。
- RegionView 有6处可直接要求父区域视口 `UPDATE_ONCE`。LOCAL 安装、释放、调整或尺寸变化可绕过主地图的完整提交。
- `_on_local_frame_ready()` 也可独立要求区域视口更新。这可能重画本应保留的离场缓存。

本轮改为：先保持既有目标纹理；目的范围完整提交后才启动原渐变。准备期间不推进渐变时钟。RegionView 的父画布更新全部改为向原 Renderer 发出 `canvas_update_requested`，由同一个提交入口判断投影和范围。LOCAL 小型3D视口自己的更新规则保留。

`_on_local_frame_ready()` 仍同步现有地表遮罩，但由 Renderer 统一重画。行政准备及上传回调也不再独立提交边界相机参数。以上修复了明确的越过提交入口和投影混用路径；**尚不能据此认定截图7的弧形已经全部消失**。

## 5. 政治着色如何替换完整物理图

沿用现有同范围政治升级：物理源和海岸先完整安装，原加载器再读取对应 ink。未知或可选 ink 失败的陆地继续使用中性物理面。

CPU 全部准备结束后，主线程仍按原预算创建隐藏的 Mesh、面数据纹理和材质。整次上传结束只请求 Renderer 提交，不再提前发出“已显示”信号。

真正提交时才同步投影、国旗样式及可见性，沿用 R34 的旧资源退休顺序。`display_changed` 在提交后发送一次，包括 LOCAL 的完整 LOD；政治已安装通知不再被上传结束提前触发。

```mermaid
flowchart LR
    A[确定当前范围和LOD] --> B[后台读取全部必需分片]
    B --> C[后台准备整包几何]
    C --> D[分预算上传；保持隐藏]
    D --> E{完整覆盖当前范围？}
    E -->|否| F[保留已提交纹理；准备或明确报错]
    E -->|是| G[一次提交投影、样式、可见性和目标重画]
    G --> H[退休旧资源；发送安装通知]
    H --> I[同一路径后台升级完整政治着色]
```

没有关闭国旗，没有以中性面永久遮住政治错误，没有改变政治归属，也没有重制 geom/ink。剩余矩形和逐面 GPU 输出仍待实机确认。

## 6. 静止时哪些任务仍会改变显示

| 已有任务或回调 | 为什么没有新输入仍会执行 | 本轮处理 |
|---|---|---|
| 战略读取线程完成 | 完成先前发出的物理或政治请求 | 仍可准备，整组范围可用才公开 |
| LOD线程、分预算 GPU 创建 | 一次请求分多个主线程处理回合完成 | 保留预算，暂存继续隐藏 |
| 中性底图提交后的政治升级 | R32 原设计；不用新输入 | 保留，完成通知移到实际提交后 |
| RegionView 样式准备完成 | 可调用 `_evaluate_scale()`，在阈值满足时自动进入 REGION | 这是可能的内部相机变化；不能无记录就认定截图时确已发生。现在不凭样式 ready 提前显示区域 |
| relief 或 LOCAL 安装/释放 | 先前请求的结果到达 | 父地图重画交回 Renderer |
| 行政后台结果 | 原请求完成，安装相应线条 | 绘制投影在统一提交更新 |
| 惯性与尺度渐变 | 先前输入可能留下有限运动 | 原惯性规则保留；渐变在完整目的图提交后开始 |

未发现“普通日期推进必须重制静态 Natural Earth”的新证据。没有再次全面修改经济、军事或时间调度。相机不变、事实不变时，可以结束在途任务，但没有新增轮询服务或全局刷新。

## 7. 确认并删除的重复显示工作

- 上传结束和显示提交原来都能发出同一 `display_changed`，使行政及地图需求收到两阶段混杂通知。现在只有提交发出安装通知；原 `prepare_step()` 调用者负责上传结束后的提交请求。
- `_sync_overlay_resources()` 和行政上传回调不再直接更新整批边界投影。Renderer 统一提交。
- REGION 政治图一次 `_draw()` 原来可更新两次行政批次：统一地图提交一次，末尾 `_draw_administrative_boundaries()` 再一次。现在末尾只绘制行政文字，改名为 `_draw_administrative_labels()`。
- 尺度渐变结束不再调用通用 `_on_visibility_changed()`，避免无条件再把地理需求标记为需要重发；只显示已经提交的目标，再沿原规则检查尺度。

增加的是当前需求 ID 列表和范围判断，没有新 Mesh、纹理、第二套缓存、相机或视口。没有每帧遍历全球多边形。暂存和旧有效资源仍只在替换期间共存；原失败保留、过期丢弃和退出释放保留。

没有测量耗时、CPU/GPU、内存或风扇。上述重复调用是源码事实，不是性能下降百分比，也不是风扇唯一原因。

## 8. 实际文件和保护范围

修改：

1. `scripts/content/strategic_spatial_loader.gd`：区分实际视野需求与复用读取窗口。
2. `scripts/presentation/map/local_spatial_layer.gd`：范围发布判断；上传完成与实际安装通知分开。
3. `scripts/presentation/map/globe_renderer.gd`：完整范围提交、投影/目标一致、渐变开始条件、失败提示、统一区域重画、移除重复边界提交。
4. `scripts/presentation/map/region_view.gd`：父视口更新改为请求 Renderer 提交。
5. `project.godot`：构建标签、ID和顺序改为 R35 / `wwo-r35-internal` / 35。
6. `export_presets.cfg`：仅现有内部预览预设的输出路径。

新增：本报告。没有删除正式源码或重制地理衍生资源。删除的旧 EXE 在下节单列。

未修改任何地图 Shader、原 GIS/DEM/DSM、LandTopology、历史身份或正式领域算法。林地、海洋、极地、外部太阳、银河、模型、菜单美术和 HUD 保留。底部黄铜半球仪没有修改。没有读写用户真实存档，快照仍为 v15；新保存来源从 R35 构建配置读取。

施工使用最新文件做局部修改，没有 Git 覆盖、提交或推送；施工读取中未观察到所改文件有来源不明的外部写入。不将此表述为其他工作线已经停止。

## 9. 唯一预览与本轮清理

目标：`D:/programs/WWO/wwo/builds/preview_2026-10-17_stable_map_display_r35/WWO_1900_Stable_Map_Display_R35_Preview.exe`。

沿用 Windows Desktop Internal Landmark Preview，x86-64、嵌入PCK。最终正常导出结果与删除结果在下方补记。先导出，再删除已获授权淘汰的旧 EXE。

已读取 R29、R31、R32 候选目录实际内容及其说明。它们包含旧预览 EXE、历史报告、许可证和地理来源旁文件。只清理明确淘汰的 EXE，旁文件保留，不整目录删除。

保留 R34、R33、R28、R24 及正式 `builds/windows/`。旧菜单加载修复构建暂保留为独立故障对照。本轮不处理 R19、R30，不重试其历史策略拒绝；不计入此前 R25—R27 的释放空间。

## 10. 仍待用户确认

需实机观察：同一 REGION 静止时是否仍露出直线缺口、完整中性图是否一次替换国旗、WORLD 异常弧形、尺度交接以及剩余政治矩形。未运行游戏，不能宣布上述画面全部通过。

若弧形仍出现，尚缺错误帧对应的实际可见对象、投影和面输出证据。用户可先按原方式提供连续截图及当时观察尺度；没有在本轮预装性能探针或安排采样。保留现有错误日志入口。

## 11. 代码入口

| 实际入口 | 对应修改 |
|---|---|
| [StrategicSpatialLoader](D:/programs/WWO/wwo/scripts/content/strategic_spatial_loader.gd)：`request()`、`physical_demand()` | 当前视野必需集合与复用窗口分开 |
| [LocalSpatialLayer](D:/programs/WWO/wwo/scripts/presentation/map/local_spatial_layer.gd)：`can_present_physical()`、`_prepare_step()`、`update()` | 整包可发布判断；上传与安装通知分开 |
| [GlobeRenderer](D:/programs/WWO/wwo/scripts/presentation/map/globe_renderer.gd)：`_draw()`、`_can_submit_map_view()`、`_begin_transition()`、`_process()` | 确认范围后才转画布、重画和渐变 |
| [GlobeRenderer](D:/programs/WWO/wwo/scripts/presentation/map/globe_renderer.gd)：`_on_local_frame_ready()`、`_sync_overlay_resources()`、`_poll_overlay_prepare()` | 回调请求原提交入口，不独立改父视口画面 |
| [RegionView](D:/programs/WWO/wwo/scripts/presentation/map/region_view.gd)：`canvas_update_requested` | 6处父画布重画交给 Renderer；LOCAL 小视口保留 |

## 12. 最终正常导出结果

唯一 EXE 已生成：

`D:/programs/WWO/wwo/builds/preview_2026-10-17_stable_map_display_r35/WWO_1900_Stable_Map_Display_R35_Preview.exe`

文件长度 **346,803,192 字节**。正常导出退出码 **0**。导出日志未出现 SCRIPT ERROR、Parse Error 或 ERROR；保留既有 `0.001a` 非纯数字版本字符串警告。没有为此改变应用版本或存档格式。目录沿用原内部预览的许可和来源旁文件。

只执行一次正常导出，没有启动游戏、自动回归、性能或内存采样、哈希核验、CI、额外检查脚本或诊断服务。因此这里仅确认导出结果，不确认错误帧已消失。

## 13. 实际清理结果

在新 R35 正常导出后，使用普通系统文件删除操作，成功删除下列3份旧预览。删除前读取了候选目录、说明及文件属性，确认是 builds 内的普通 EXE 文件，没有删除整个目录。

| 已删除完整路径 | 文件长度（字节） |
|---|---:|
| `D:/programs/WWO/wwo/builds/preview_2026-10-16_earth_surface_assets_r29/WWO_1900_Earth_Surface_Terrain_Assets_R29_Preview.exe` | 346,676,216 |
| `D:/programs/WWO/wwo/builds/preview_2026-10-16_map_rendering_consistency_r31/WWO_1900_Map_Rendering_Loading_Consistency_R31_Preview.exe` | 346,723,600 |
| `D:/programs/WWO/wwo/builds/preview_2026-10-17_world_map_rendering_recovery_r32/WWO_1900_World_Map_Rendering_Recovery_R32_Preview.exe` | 346,747,376 |

**成功删除3个文件，长度合计1,040,147,192字节，约1.04 GB。** 只按本轮成功删除文件计数；不是扣除新 R35 导出后的净空间差，也没有计入此前 R25—R27。

上述目录中的报告、许可证、地理来源及 JSON 旁文件全部保留。未发现这3个候选目录内还有需要清理的临时 PCK；没有扩大删除范围。

实际保留的预览：R35、R34、R33、R28、R24；旧菜单加载修复预览也保留作独立故障对照。`builds/windows/` 的 `wwo-map-correctness-r3.exe`、`wwo-map-performance-r3.exe` 均保留。未触碰其他工作线构建、源码、素材、研究数据和用户存档。

本轮3次文件删除没有遇到新的权限或策略拒绝。R19和R30按既有拒绝要求保留，没有尝试删除、改权限或换方法。没有删除目录。完成后停止施工，等待用户实机查看。
