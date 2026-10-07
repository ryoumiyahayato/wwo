WWO — Political Map Macro Boundary Legibility Pass

状态：已实现并完成正式场景截图；等待用户人工视觉验收。

全部最终截图来自 `res://scenes/formal/formal_world_main.tscn`，1280×720，Compatibility / NVIDIA RTX 3050，模拟日期 1900-01-01 00:00，同一 Formal UI。没有推进模拟时间。

1. [Arabia 340% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/01_arabia_340_labels_off.png)
2. [Arabia 460% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/02_arabia_460_labels_off.png)
3. [Arabia 580% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/03_arabia_580_labels_off.png)
4. [Arabia 460% · Labels ON](D:/WWO/wwo/local-artifacts/political-boundary-legibility/04_arabia_460_labels_on.png)
5. [Gulf / Oman 600% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/05_gulf_oman.png)
6. [Yemen / Hadramaut 600% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/06_yemen_hadramaut.png)
7. [World 100% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/07_world_100_labels_off.png)

同视角对照：

![Before · 460% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/00_before_460_labels_off.png)

![After · 460% · Labels OFF](D:/WWO/wwo/local-artifacts/political-boundary-legibility/02_arabia_460_labels_off.png)

根因：旧政治边界只有一层低对比深青色描边，宽度为 0.55–0.85 屏幕像素；深色邻国容易融合。旧 Arabia 边界处理依据 source feature 是否进入 presentation scope 来抑制或裁剪源边缘，再追加 display 文件的边缘，不能完整表达边缘两侧的最终 owner。边界缓存还只在 source feature 列表改变时重建。

PoliticalLayer 现在拥有 Arabia 的最终边界提取。源 ring 和既有宏观 display frontier 仅提供候选线；候选在宏观 mask 交点处分段，然后沿法线查询两侧最终显示归属：两个非空 owner 不同，输出 macro；一侧为海洋，输出 coast；两侧相同，丢弃。相同几何边缘去重。查询消费当前显示分区和已有 geography，不读取 tribal / local authority 分区，也不改变归属。区域外维持原有整 feature 的最终宏观 owner 映射。

旧 Arabia source-feature 抑制 / partial source-polyline 裁剪路径已删除，旧单层政治边界绘制路径已删除。边界随 PoliticalLayer refresh 重建，不再用 geography feature 列表的变化代替最终显示状态变化。

GlobeRenderer 只消费 `macro` / `coast` 分类。先绘海岸线，再绘政治边界底线和内线：深炭蓝灰 2.1 px / alpha 0.88，石灰色 0.9 px / alpha 0.88；海岸线 0.65 px / alpha 0.62。宽度使用 Control 屏幕坐标，不乘地图 zoom。沒有 glow、白色高亮或黄色边框。

截图检查中发现中央南缘曾出现缺口：通用 point-in-polygon 的包含边缘容差让很近的两侧采样点同时属于首个区域。现在边界查询使用严格内部判断；Rashidi / Hadramaut 的三个连续南缘段均已进入最终输出。此修正仅用于边界查询。

运行代码修改：

- [political_layer.gd](D:/WWO/wwo/scripts/presentation/map/political_layer.gd)：最终边界查询、分类与去重。
- [globe_renderer.gd](D:/WWO/wwo/scripts/presentation/map/globe_renderer.gd)：边界 refresh、分类传递、固定像素双层描边。
- [capture_political_boundaries.gd](D:/WWO/wwo/tools/map/capture_political_boundaries.gd)：七张实际 Formal 截图及同次运行的 geometry accounting。

`arabia_political_map_regions_1900.json` 恢复为最近一次已渲染的冻结分区；未接入 runtime 的六实体替换草案及其 builder 已移除。本轮没有重新划分 Arabia、修改旗帜资产、UV、shader、tone 或 source geography。

最小验证：`git diff --check`、新增文件的 diff whitespace 检查、Godot 4.6.3 headless editor parse、实际 Formal GPU 截图均完成。没有运行新测试框架、benchmark、长模拟或 hash gate。

同次正式场景运行：[capture manifest](D:/WWO/wwo/local-artifacts/political-boundary-legibility/capture_manifest.json)。features=161，source exteriors=1634，loader=1634，projection retained=1634，render retained=1634，geometry_lost=0；不存在同 owner 的 macro 边界输出。计数是工程检查，不代替用户视觉验收。

本任务至此停止。
