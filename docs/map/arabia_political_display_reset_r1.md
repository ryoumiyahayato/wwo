# Arabia Political Map Display Reset R1 — 人工验收截图

全部截图为 1280×720、Formal 场景、1900-01-01 00:00、相同 UI。
BEFORE 为本轮重建前失败尝试的正式截图；AFTER 为重新设计的显示层。
尚未宣告 MAP RECOVERY CLOSED。施工到此停止，等待用户人工视觉验收。

1. Arabia BEFORE

![Arabia BEFORE](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/01_arabia_before.png)

2. Arabia AFTER — Labels OFF

![Arabia AFTER Labels OFF](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/02_arabia_after_labels_off.png)

3. Central Arabia / Rashidi

![Central Arabia Rashidi](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/03_central_rashidi.png)

4. Hejaz + Al-Hasa

![Hejaz Al-Hasa](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/04_hejaz_hasa.png)

5. Yemen + Aden + Hadramout

![Yemen Aden Hadramout](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/05_yemen_aden_hadramaut.png)

6. Gulf + Oman + Trucial + Qatar + Bahrain + Kuwait

![Gulf Oman](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/06_gulf_oman.png)

7. Labels ON

![Labels ON](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/07_labels_on.png)

8. World scale

![World scale](D:/WWO/wwo/local-artifacts/arabia-display-reset-r1/08_world_scale.png)

## 显示层施工说明

旧 `map_display_partition_1900.json`、旧分区生成器与专用截图脚本已删除。
绿紫 Rashidi livery 资产及其生成路径已删除。不存在 shared visual group、
micro rendering 或旧模式兼容分支。

新 `data/presentation/arabia_political_map_regions_1900.json` 由人工设计的
宏观共享边线构造，不读取旧 partition、local influence polygons 或 triangle
ownership。它仅表达世界地图显示，不设置历史主权、地方控制或模拟 controller。
PoliticalLayer 直接消费该文件，历史 AdministrativeLoader 不再加载显示分区。
每个 region 使用自身代表旗和一个固定 geographic UV frame；所有 components
沿用这个 frame。旗面在主区域的可读内部构图，边缘地块不重复 fit。

Rashidi 使用干净的红黄月星完整 SVG。
[Commons 文件、作者与许可](https://commons.wikimedia.org/wiki/File:Flag_of_the_Emirate_of_Ha%27il.svg)：
Guilherme Paula / NikNaks，CC BY-SA 3.0，原文件未修改。
这是现代重绘的关联代表视觉，`approximate=true`、`confidence=low`、
`historical_national_flag=NOT_ASSERTED`，并未宣称精确复原 1900 年国旗。
原绿紫旗的历史文字证据、历史插图、local/tribal records 和关系 metadata 保留。
其他地方旗的附近年代及近似范围见资产目录中的 ATTRIBUTION.md。

## 本轮允许的验证

- `git diff --check`：退出码 0。
- 指定 Godot 4.6.3 headless editor parse：退出码 0，错误日志为空。
- 正式场景 GPU 截图：退出码 0，错误日志为空；已逐张目视检查上述八张图。
- 实际 source component accounting：features 161，source exteriors 1634，
  loader 1634，projection retained 1634，render retained 1634，geometry lost 0。

本轮按 Reset R1 的验证限制执行，没有继续统一回归、长期模拟、benchmark 或导出。
用户发出 Reset R1 前启动的上一轮注册测试已停止，其日志不作为本轮通过依据。
截图检查属于施工自检，不能代替用户的人工视觉验收。

Source geography、历史 local/tribal authority、provenance、其他地区资产、
Quaternion、projection、horizon clipping、shader/tone、边界绘制样式、
UI、simulation、economy 与 save/load 未在本轮重建中修改。
