# Structural Rebuild R1：本轮交付

正式场景：`scenes/formal/formal_world_main.tscn`。
`FormalWorldApplication extends Control`，仅初始化、连接信号和发出世界/保存读取请求。

```text
FormalWorldApplication
├─ 世界 / 运算 / 规则 / 保存：现有 FormalWorldSimulation 及当前事实 owner
├─ 历史资料：content/HistoricalLoader
│  ├─ GeographyLoader → CShapes 几何、既有 provenance admission
│  ├─ AdministrativeLoader → 历史行政区名称、国家档案、观察资料
│  └─ EvidenceLoader → flags metadata
├─ 输入 / 时间请求：actions/TimeControl + map/GlobeController
├─ 地图：presentation/map/GlobeRenderer
│  ├─ GlobeProjection：坐标投影、半球裁剪、历史三角细分
│  ├─ PoliticalLayer：当前政治实体、正式经济结果的显示颜色
│  ├─ GlobeLabels：标签
│  └─ GlobeSurface：球面底材、月球网格
└─ UI：presentation/ui/MainShell
   └─ PersonView / EconomyPage / OrganizationPage / WorldPage
```

## 唯一负责人

- 世界事实与当前时间：现有正式模拟及其组合的政治、人物、空间、经济、组织 owner。
- 地图绘制与投影缓存：GlobeRenderer；数学投影：GlobeProjection。
- yaw / tilt / zoom / 地图输入与观察选择：GlobeController。
- 页面、导航、HUD、界面命令：MainShell；页面组件只读真实记录。
- 新前端需要的历史资料读取：HistoricalLoader 及三个内容读取组件；当前政治身份仍由正式世界 registry 负责。
- 暂停与速度：TimeControl，仅提出推进分钟请求，不持有第二个游戏时钟。
- active generation：`scripts/system/active_components.gd`，普通整数。

## 迁移

- 原 runtime 的球面坐标、半球线段/多边形裁剪、实际旋转参数，分别进入 GlobeProjection / GlobeController。
- Player Experience R2 历史实现的三角细分进入 GlobeProjection；原 flags/history 中几何预处理只保留当前历史显示需要的部分。
- 原 hemisphere 的小型网格组件进入 GlobeSurface；三份必要 shader 移入 presentation。
- 原 history/admin/historical_evidence 宿主的数据读取移入 content；不保留旧 UI 宿主。
- 正确 Player Experience 的人物、经济、组织、世界导航意图进入 MainShell；四角 HUD 被删除。
- 当前地点读取通过正式模拟新增两个只读入口访问现有 SpatialWorld，不恢复旧 observation API。
- 应用入口不处理鼠标；UI 命中区域由 UI 提供，地图输入入口交给唯一控制器处理。地理坐标解析归 GeographyLoader，旗帜读取只保留一份记录索引。
- 与旧私有 UI 字段绑定的断言退出现有测试文件；其余现有世界/保存检查保留，本轮未执行。

## 实际删除

以下路径已物理删除；配对的旧脚本 UID 同时退出。

- `.github/workflows/holographic-workspace-spike.yml`
- `.github/workflows/release-ui-integration.yml`
- `scenes/formal/formal_world_ui_capture.tscn`
- `scenes/ui_spikes/holographic_workspace/holographic_workspace_admin1_probe.tscn`
- `scenes/ui_spikes/holographic_workspace/holographic_workspace_capture.tscn`
- `scenes/ui_spikes/holographic_workspace/holographic_workspace_interaction_probe.tscn`
- `scenes/ui_spikes/holographic_workspace/holographic_workspace_release_probe.tscn`
- `scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`
- `scripts/ui_spikes/holographic_workspace/holographic_hemisphere_3d.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1_probe.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_capture.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_flags_fixed.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_runtime.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_final.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_final_polish.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_flag_tuning.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_flags.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence_ui.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_history.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_hud_polish.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_interaction_probe.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_polish.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_release_probe.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_spike_runtime.gd`
- `scripts/ui_spikes/holographic_workspace/holographic_workspace_visual.gd`
- `shaders/ui_spikes/holographic_workspace/hemisphere_surface.gdshader`
- `shaders/ui_spikes/holographic_workspace/moon_surface.gdshader`
- `shaders/ui_spikes/holographic_workspace/workspace_background.gdshader`
- `tests/formal/formal_world_player_journey_smoke.gd`
- `tests/formal/formal_world_ui_capture.gd`
- `tests/formal/historical_evidence_bootstrap_regression_test.gd`
- `tests/v2_3/v2_3_city_detail_performance_test.gd`
- `tests/v2_3/v2_3_player_interface_test.gd`

## 本轮边界

没有新增兼容层、旧实现 fallback、分支、worktree、测试或 hash 基础设施。
未修改经济、政治、军事、人口运算。Market pulse 未恢复；军事页面与组织细节不补假数据。
行政区目前显示历史名称与层级，未用现代边界替代缺失的历史边界。
没有仍阻止旧前端继承链删除的问题；功能与布局由用户验收。

## 最小检查与截图

只运行 `git diff --check` 和指定 Godot `--headless --editor --quit` 解析。
按用户追加要求，另用临时截图脚本渲染正式场景的人物页与世界页；世界保持暂停，不读写用户存档。
截图脚本放在系统临时目录，截图在 `artifacts/structural_rebuild_r1/`，没有加入测试体系。
本轮停止，等待用户视觉确认。
