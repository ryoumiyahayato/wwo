# WWO M2.6.3 — Macro Political Cartography

施工完成，等待人工视觉验收。未标记 MAP RECOVERY CLOSED，未进入 M3 或 Formal Legacy Severance。

正式场景：`scenes/formal/formal_world_main.tscn`。世界日期：1900-01-01 00:00。截图没有推进模拟时间。

## 显示结果

Arabia 改为 12 个互斥宏观显示区域、7 个完整旗面视觉组。中央 Rashidi 使用一个连续主区域，原来的 tribal / local influence polygon 不再决定地表显示边界。紫色与绿色仍是冻结 Rashidi livery 的完整旗面条带，资产未重新设计。

Hejaz、Al-Hasa、Yemen、Qatar 共享 `ottoman_arabia_1900` 的同一 geographic flag frame。该 frame 在西部 Hejaz / Yemen 连续主地块上计算一次，东部地块沿用相同坐标，不重新 fit 月星。Ottoman 主体保持原有纹理坐标。Kuwait / Trucial、Aden / Mahra 分别共享一个 British flag field。

宏观显示边界只来自独立 display partition。已隐藏区域内部的 source feature、exterior 和 local authority 边界。标签从宏观显示区域取名，保留现有 Labels ON/OFF、碰撞避让与缩放行为；没有修改 UI。

## 分区与视觉组

所有新 display masks 都标记 `APPROXIMATE_CARTOGRAPHIC_DISPLAY_BOUNDARY`、`approximate = true`，仅服务 Political Map，不是新的地理来源，也不是排他主权断言。小型 Kuwait / Bahrain / Qatar / Aden 显示边界为 medium confidence，其余宏观内陆简化边界为 low confidence。

| Display region | 现有 display authority | Map visual group | 现有完整资产 |
|---|---|---|---|
| Rashidi / Nejd-Hail | `map_authority:arabia_rashidi_1900` | `rashidi_1900` | `rashidi_authority_1900.svg` |
| Hejaz | `map_display:hejaz_1900` | `ottoman_arabia_1900` | `ottoman_1844.png` |
| Al-Hasa | `map_display:hasa_1900` | `ottoman_arabia_1900` | `ottoman_1844.png` |
| Yemen | `map_display:yemen_1900` | `ottoman_arabia_1900` | `ottoman_1844.png` |
| Qatar | `map_authority:arabia_qatar_1900` | `ottoman_arabia_1900` | `ottoman_1844.png` |
| Oman | `state:sultanate_of_muscat_oman` | `oman_1900` | `muscat_oman_plain_red.png` |
| Trucial / Gulf sheikhdoms | `state:trucial_states` | `british_gulf_1900` | `uk_union_1801.png` |
| Kuwait | `map_authority:arabia_kuwait_1900` | `british_gulf_1900` | `uk_union_1801.png` |
| Hadramaut | `map_display:hadramaut_1900` | `hadramaut_1900` | `quaiti_1880.svg` |
| Mahra | `map_authority:arabia_mahra_1900` | `british_south_arabia_1900` | `uk_union_1801.png` |
| Aden | `map_authority:arabia_aden_treaty_states_1900` | `british_south_arabia_1900` | `uk_union_1801.png` |
| Bahrain | `map_authority:arabia_bahrain_1900` | `bahrain_1900` | `bahrain_authority_1900.svg` |

这些 authority 和旗帜/livery 均为已有内容。本轮没有新增历史 authority、旗帜或研究来源。保护关系及地方管理身份继续由原 metadata 表达，不将上述对象统一解释为 sovereign nation-state。

## 职责与退出的旧路径

- Source geography：冻结的历史地理数据，负责土地与原始 components。
- Local authority：原有 15 个地方/部落记录、status、confidence、source、historical notes 全部保留，文件内容未变化。
- Map display partition：独立 JSON 给显示地表提供唯一宏观 region owner。少量共同边界节点定义连续大区，再沿现有 source land 裁切；不读取地方 influence polygons 作为边界。
- Map visual group：独立决定完整旗面构图和共享 UV；authority / region 仍决定宏观边界。

旧 `map_display_authority_at` 的 local influence polygon 路由及旧 presentation bindings 已物理移除。Renderer 不再按 source triangle 的中心点查 local authority 后分别 fit 旗面，也没有 disabled / legacy presentation 分支。内容层 `authority_at` 保留用于真实地方事实，Political Map 不调用它。

源投影 meshes 原样保留。新增 mask 裁切只生成 presentation draw pieces，并携带原 source component provenance；这些片段不进入 geography feature / exterior accounting。Arabia 范围外沿用原 source surface / UV，未调整 shader、tone、Quaternion、projection、horizon、边界绘制风格或模拟系统。

## 硬数据验收

| 项目 | 结果 |
|---|---:|
| Geography features | 161 |
| Source exteriors | 1634 |
| Loader components | 1634 |
| Projection retained | 1634 |
| Render retained | 1634 |
| Geometry lost | 0 |
| 新增 geography features / exteriors | 0 / 0 |
| Display regions / visual groups | 12 / 7 |
| Arabia 未分配显示片段 | 0 |
| Arabia COLOR_FALLBACK faces | 0 |
| 分区构造的 overlap planar area | 0 |
| 分区构造的 uncovered planar area | 2.972 × 10⁻¹⁵（浮点残差） |
| Rashidi 最大连续主区域占比 | 99.9999448% |
| 运行时显示裁切相对平面面积差 | 0.000260474% |

Render retained 直接从正式场景的实际 display surface 缓存按 source component provenance 统计，不是复制 loader 数值。全世界 presentation draw pieces 共 51740，包含原有 surfaces 与 Arabia 裁切产生的片段；该数量不代表新增 geography。运行时面积残差来自单精度显示裁切，不计为新的地理或 authority。

`git diff --check` 通过。Godot headless editor parse 退出码 0，正式场景截图运行退出码 0，日志错误扫描为空。只做本轮解析、截图与 component accounting；没有运行长期模拟、benchmark、M3 或架构拆除。

冻结校验的 17 个文件无变化，包括 geography、authority、visual catalog、相关旗帜与 livery、冻结 presentation 配置及 Formal / simulation 文件。Before 是旧 M2.6.2 截图的逐字节副本。相同 Arabia 视角的 Afghanistan、Persia、Sudan B、Ottoman 主体、Qing 抽样像素保持一致；这仅证明所选采样区域，没有宣称整张世界截图逐像素相同。

证据：[正式场景 manifest](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_manifest.json)、[冻结核验](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/freeze_verification.json)、[冻结基线](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/frozen_baseline.json)。

## 本轮修改文件

- `data/world_map/historical/map_display_partition_1900.json`（新增）
- `scripts/content/administrative_loader.gd`
- `scripts/presentation/map/political_layer.gd`
- `scripts/presentation/map/globe_renderer.gd`
- `tools/map/build_arabia_display_partition.py`（新增）
- `tools/map/capture_arabia_authority.gd`
- `docs/map/macro_political_cartography_closure_m2_6_3.md`（本报告）
- `local-artifacts/arabia-cartography-closure/`（正式截图、manifest、日志与冻结校验）

工作区原有 Formal 重建等其他变更不属于本轮施工。

## 正式场景截图

### 1. M2.6.2 failed Arabia — Before

![M2.6.2 failed Arabia](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/before_failed_m2_6_2.png)

### 2. Corrected Arabia — After

![Corrected Arabia](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_arabia.png)

### 3. Rashidi / central Arabia

![Rashidi central Arabia](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_nejd_rashidi.png)

### 4. Hejaz

![Hejaz](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_hejaz.png)

### 5. Gulf / Oman

![Gulf Oman](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_gulf_oman.png)

### 6. Yemen / Hadramaut / Aden

![Yemen Hadramaut Aden](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_yemen_hadramaut.png)

### 7. Labels ON — macro authority view

![Macro labels ON](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_labels_on.png)

### 8. World scale

![World scale](D:/WWO/wwo/local-artifacts/arabia-cartography-closure/after_world.png)

验收重点：中央区域连续、没有 micro-authority 拼图、Ottoman Arabia 旗面连续而不逐区重复月星、宏观边界清楚、标签无地方部落名称。是否通过由用户人工判断。
