# WWO Map Presentation Continuation · 第一批

RESULT=PERFORMANCE_NOT_PASS / PARTIAL_CORRECTION

延续 R3，没有重新生成海岸、政治几何、行政或土地数据。原 R3 的 PERFORMANCE_NOT_PASS 记录保留在 [上一轮 A–U 报告](D:/WWO/wwo/docs/map/map_correctness_cartographic_r3.md)。本批先修复其交互成本，再完成铁路与城市显示语义及必要的地图控件。完整清单中的海洋色阶、正式港口角色、船舶、历史行政界和城市建成区没有计入完成。

## 实际修改与 R3 后续结果

REGION 水系线保留全部源端点、相邻点和真实端帽，只省略内部面积为零的端帽几何；WORLD 保留动态地平线端帽。零扩展的陆地参考面和湖面保留原来有效的三角形，政治面与海水扩展保持原契约。GPU 数据纹理、UV、主权、控制和拾取均保持原值。

一次画面只提交一次地方图层；国旗样式只在内容、模式、选择状态变化时绑定，缩放仍更新原有连续权重。WORLD 国名字形及底部出处文字保留绘制命令，camera 只改位置和可见性。曾试验的三角面空间排序没有改善性能，已撤回。没有 TIME shader、常驻 process、模拟变化或新地图系统。

## 第一批产品行为

战略铁路默认关闭，可在“显示选项 / 图例”开启；FAR 可读主要连接，MID 使用受控线宽与虚线。Paris Local 双轨参考线保持原样。该开关不重读数据、不生成几何，也不提供正式轨道位置、车站、运力、列车或运输算法。

城市使用方块、圆环与小点区分已有历史展示等级，选择对象另有外圈。展示等级来自既有 atlas 证据，没有用现代人口推断首都、港口或行政身份，没有新增城区范围、建筑群或世界实体。

地图模式收进 Political / Economy 图层菜单；“经济 / 市场”一级页面不变。Military 正式地图内容尚未接入，菜单仅说明其缺口。时间、速度和系统区域保持原位；此次仅修改地图控件，不重做 MainShell。

## 原生 Windows Release 画面

截图来自正常菜单进入的独立 Release 取证包；产品数据、场景、shader、素材及 155 个编译产品脚本与正式包逐字节一致。输入旅程自动执行，不声称用户人工旅程已完成。14 组 REGION / LOCAL 相机、缩放、bearing 和 Political 图层对比见 [PNG / 相机审计](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch-png-audit.json)。

|区域 / 场景|修改前原始 PNG|修改后原始 PNG|
|---|---|---|
|world|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/world.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/world.png)|
|europe_far|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/europe_far.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/europe_far.png)|
|europe_mid|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/europe_mid.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/europe_mid.png)|
|east_asia|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/east_asia.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/east_asia.png)|
|north_america|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/north_america.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/north_america.png)|
|paris_region|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/paris_region.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/paris_region.png)|
|paris_local|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/paris_local.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/paris_local.png)|
|great_lakes|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/great_lakes.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/great_lakes.png)|
|pyrenees|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/pyrenees.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/pyrenees.png)|
|himalaya|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/himalaya.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/himalaya.png)|
|crimea|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/crimea.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/crimea.png)|
|denmark|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/denmark.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/denmark.png)|
|memel|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/memel.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/memel.png)|
|normandy|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/normandy.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/normandy.png)|
|calais|[前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-visual/calais.png)|[后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/calais.png)|

额外画面：[display_legend](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/display_legend.png)、[mode_menu](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/mode_menu.png)、[europe_mid_rails_on](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/europe_mid_rails_on.png)、[europe_far_rails_on](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/europe_far_rails_on.png)、[europe_mid_1920](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/europe_mid_1920.png)、[high_latitude_1920](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-delivery-visual/high_latitude_1920.png)。

[第一批原生前后对比页](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-compare.html)。上一轮海岸修复的四个重点区域、法国、西班牙及连续尺度的详细成因与原始对比继续保留在上述 R3 报告；本批新增近景回归没有重新施工该几何。

## 资源占用

RTX 3050 Laptop GPU，同设备，默认 Political、Labels ON；六类页面/尺度 idle 20s、pan/zoom 12s、返回人物页 idle 20s。以下为上一版 R3 → 本批；CSV 同时保留 R1 原始参考、median/p99、Private、Shared、纹理/几何与 draw calls。板卡 W 为整卡读数，不是本游戏独占功耗。静止零重绘和约 3.4W 用实际样本核验，不能以平均 60 FPS 替代。

|阶段|p95 ms 前→后|max ms 前→后|CPU % 后|进程 GPU % 后|板卡 W 前→后|WS MiB 前→后|独占显存 MiB 后|重绘增量 后|
|---|---:|---:|---:|---:|---:|---:|---:|---:|
|person_idle|17.73 → 17.77|24.73 → 19.84|0.11|0.00|3.40 → 3.40|521.60 → 521.01|171.93|0|
|world_idle|17.83 → 17.74|24.38 → 20.92|0.18|0.00|3.40 → 3.37|549.79 → 546.80|184.29|0|
|world_pan|20.07 → 17.90|31.70 → 28.24|2.89|19.63|7.79 → 7.78|549.63 → 547.22|184.23|419|
|world_zoom|18.95 → 17.66|33.66 → 18.76|3.03|21.22|7.78 → 7.80|550.03 → 547.21|184.23|420|
|region_far_idle|17.65 → 17.80|33.22 → 18.73|0.18|0.00|3.42 → 3.38|785.12 → 776.40|228.26|0|
|region_far_pan|24.64 → 25.43|47.46 → 36.82|4.48|21.13|11.18 → 9.09|785.30 → 778.61|228.25|406|
|region_far_zoom|20.94 → 26.39|30.68 → 37.60|4.80|20.69|10.89 → 8.55|783.40 → 774.68|228.25|371|
|region_mid_idle|17.75 → 17.71|18.76 → 18.50|0.13|0.00|3.45 → 3.40|689.94 → 681.26|236.25|0|
|region_mid_pan|17.96 → 18.19|26.60 → 31.86|3.86|20.96|8.02 → 7.83|689.98 → 681.40|224.25|419|
|region_mid_zoom|29.85 → 26.34|54.18 → 55.70|6.10|20.87|8.06 → 7.83|704.26 → 704.23|224.25|484|
|region_near_idle|17.92 → 17.84|18.84 → 24.44|0.05|0.00|3.44 → 3.40|705.05 → 727.80|221.12|0|
|region_near_pan|17.78 → 17.64|27.40 → 18.31|3.44|21.41|8.05 → 7.85|705.07 → 727.83|221.12|420|
|region_near_zoom|18.33 → 18.08|33.08 → 23.61|3.93|21.41|8.02 → 7.84|705.14 → 727.87|221.12|416|
|paris_local_idle|17.74 → 17.85|20.10 → 30.28|0.12|0.00|3.43 → 3.38|705.38 → 691.72|221.12|0|
|paris_local_pan|17.74 → 17.66|26.22 → 22.80|2.43|17.44|7.91 → 7.78|705.40 → 691.75|209.12|420|
|paris_local_zoom|17.98 → 17.69|28.65 → 18.55|2.48|25.60|7.91 → 7.77|705.45 → 691.92|209.12|420|
|person_return_idle|17.71 → 17.66|19.00 → 24.47|0.09|0.00|3.45 → 3.45|705.46 → 691.75|205.06|0|

[完整资源 CSV](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-resources-comparison.csv)。历史 REGION MID 最大帧 184.604ms、已拒绝的早期 R3 FAR zoom 197.739ms 保留，不因最终未复现而删除。原始取证目录保留。

最终完整 17 阶段的 FAR pan/zoom p95 为 25.435/26.393ms；此前优化短测曾出现约 18–20ms，但没有在这次完整旅程稳定维持。此结果仍未达到此前 R1 约 19ms 的标准，不能报告性能 PASS 或稳定 60FPS。WORLD、NEAR 和 LOCAL 的改善与 idle 零重绘不抵消 FAR 问题；不删除较差样本，也不继续扩大本批功能。

铁路开关同条件复测（idle 20s、pan 30s、zoom 20s）：

|Labels ON，同包、同视角 FAR 复测|p95 ms 关闭→开启|max ms 关闭→开启|板卡 W 关闭→开启|
|---|---:|---:|---:|
|region_far_idle|17.828 → 17.700|18.782 → 18.882|3.44 → 3.44|
|region_far_pan|20.185 → 20.795|36.345 → 30.705|9.02 → 9.23|
|region_far_zoom|20.719 → 20.356|31.099 → 26.370|8.97 → 8.56|

此复测只解释样本变化及可选图层成本，不能覆盖上面的完整旅程失败。原始数据：[关闭](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-rails-off-resources/summary.json)、[开启](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-rails-on-resources/summary.json)。

冷启动为正常菜单下真实滚轮与拖动、当前进程未访问过的区域；不是清空 OS 磁盘缓存。里程碑同时要求可见几何与实际后续 canvas 提交，不能拿 ready 标记冒充画面：

|首次实用画面 / 完整目标（Labels 未触碰）|前 秒|后 秒|
|---|---:|---:|
|cold_far|5.364|5.467|
|cold_mid|0.728|0.818|

FAR 首次等待没有实质缩短。GPU 入队与驻留字节减少，源解析、工作线程与分步调度仍占时间。Labels ON/OFF 不重读数据、不重建几何，两次独立取证均没有加载错误。[冷启动前](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-before-cold/cold-summary.json)、[冷启动后](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-after-cold/cold-summary.json)。

同一进程三轮跨区后返回人物页，原始时序和驻留见 [跨区旅行](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-travel/summary.json)；上一版 R3 → 本批峰值：working_set 700.0 → 692.4 MiB；private_bytes 972.1 → 958.4 MiB；dedicated_gpu_bytes 228.2 → 220.3 MiB。三轮有限观察不等于无限运行无泄漏证明。

## 数据边界与仍缺内容

没有新增外部数据。铁路及城市沿用既有约 1900 atlas 与经核验的历史来源；位置含现代 locator 参考，不能宣称历史城区、站址或人口精度。河湖岸线仍是 Natural Earth 1:10M 现代物理参考，显示 LOD 为 1500m/300m；ETOPO 约 9.8km。没有改水位、军事移动或经济条件。

港口旧文件明确为 prototype_only；即使兼容目录存在地点 ID，也不能据此宣布正式历史港口角色已核验。船舶缺少正式空间状态，Seine / Seine-et-Oise 等历史行政界仍缺可靠资料。既有六块巴黎土地保持不变，不用其分割线充当行政界。更细城市空间及 5×5km 以下关系视图另列后续，不在本批实现。

河流/湖泊现有分类与静态批次沿用；没有凭 rank=0 生成支流等级。海洋静态色阶尚未加入。国旗尺度衰减、国家名称和地形 R3 成果只做回归，不重新实现。

## 验证、包体与修改位置

统一验证：Python 62 项，Godot 36 组、31694 checks、0 failures；十年 193.203s，内部 240s 与原外部超时不变。退出码及日志扫描见 [完整日志](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-batch1-validation.log)。原生旅程 v15 与存档快照一致。

213 个受保护文件保持原样，全部 980 个运行 data 条目逐字节不变。正式包 204,008,528 bytes，上一版 R3 204,002,144 bytes，增量 6,384 bytes。开发 GIS、环境、测试、工具、截图、报告和 probe autoload 排除，见 [包体审计](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-release-audit.json)。

globe_boundary_batch / globe_surface_batch / local_spatial_layer：重复几何与重复提交成本；globe_renderer / labels / region_view：材质、出处与字形缓存；map_scale_style / globe_controller：既有内容的尺度和显示选择；main_shell：仅地图菜单与图例。数据和正式应用/模拟脚本保持原样。没有空 Service、船舶 Renderer 或未来接口。

修改文件：[globe_boundary_batch](D:/WWO/wwo/scripts/presentation/map/globe_boundary_batch.gd)、[globe_surface_batch](D:/WWO/wwo/scripts/presentation/map/globe_surface_batch.gd)、[local_spatial_layer](D:/WWO/wwo/scripts/presentation/map/local_spatial_layer.gd)、[globe_renderer](D:/WWO/wwo/scripts/presentation/map/globe_renderer.gd)、[labels](D:/WWO/wwo/scripts/presentation/map/labels.gd)、[region_view](D:/WWO/wwo/scripts/presentation/map/region_view.gd)、[map_scale_style](D:/WWO/wwo/scripts/presentation/map/map_scale_style.gd)、[globe_controller](D:/WWO/wwo/scripts/presentation/map/globe_controller.gd)、[main_shell](D:/WWO/wwo/scripts/presentation/ui/main_shell.gd)。测试与取证工具的变化不进入正式 Release。

## 本批结束边界

交回 [最新 Windows Release](D:/WWO/wwo/builds/windows/wwo-map-correctness-r3.exe) 和原始证据供实际打开检查，停止继续扩张。后续仅针对明确画面/资源问题修正；港口、船舶、行政区与城市模型待正式资料和世界事实具备后独立施工。

完成包体和证据审计后，删除本轮 14 个临时/旧取证 EXE，共 2,856,311,256 bytes；仅保留最新正式安装产物，PNG、日志、冻结源码和审计保留。清理记录：[原始清单](D:/WWO/wwo/local-artifacts/map-correctness-r3/continuation-installation-cleanup.json)。
