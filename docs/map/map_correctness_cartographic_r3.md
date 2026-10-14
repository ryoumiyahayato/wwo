# WWO MAP CORRECTNESS & CARTOGRAPHIC PRESENTATION R3

RESULT=PERFORMANCE_NOT_PASS

## A. USER SCREENSHOT DEFECT REPRODUCTION

稳定复现：旧 LOD 被清空；克里米亚内部三角色块、丹麦与梅梅尔岸外细线、诺曼底重复岸边；宏观铁路与国界争夺注意力。用户报告的 Labels OFF 未主动显示问题按异步提交调用链修正；本次修正前的安静原生滚轮旅程也能借输入/惯性刷新呈现，未稳定复现持续灰面，不能声称该现象每次都复现。修改前后均为正常菜单进入的 Windows Release，1280×720，Political，固定经纬度、北向和米/像素。

## B. COLD REGION LOAD

无按钮切换的冷加载以独立安静运行的 cold-trace.jsonl 为依据；标签 OFF → ON → OFF 不要求重读或重建地理。截图取证运行与构建/模拟并行产生的加载时间不作为资源结论。 本次修改前后均可在不切换 Labels 的原生滚轮旅程呈现；修正验证保证等待异步准备本身会请求刷新，不依赖残留输入。冷启动默认视角/可见分片受本轮默认球体尺寸调整影响，时间是各自默认操作路径的测量，不能当作完全相同几何工作量的加速比。

## C. ASYNC / REDRAW FIX

GlobeRenderer._process 在 Content.poll 与 LocalSpatialLayer.prepare_step 后使视图失效并安排下一次提交；异步新建城市缓存首次投影不再误用上一帧坐标。LocalSpatialLayer.begin 保留已呈现的旧 LOD；目标 LOD 完整上传后替换并释放旧缓冲。停止处理后仍为按需重绘。

## D. COASTLINE / TRIANGLE DEFECT

共同根因分为六项：① canonical CShapes 的 0.08°简化与 1:10M 物理陆地不一致；②差集裁切后再次 DP 简化会移动共享边；③补片原先没有沿用国家 UV/遮罩，产生三角纹理色块；④政治三角面亚像素扩展和球面弦投影超出平面海水差集，留下岸外细线。修改 build_geographic_foundation.py，使同一全球简化陆地生成海岸与陆海裁切、裁切后不再简化；离线约束三角化保留孔洞；仅在物理海水中覆盖按现有 2°细分弦差计算的有限裁切范围；海水 shader 使用 0.55px 受控覆盖，包住原政治面 0.45px 扩展。补片从原始同日期 CShapes 查验有界纹理关联，沿用同一国家 UV、纹理和材质；不确定关联保留中性物理参考。⑤ Natural Earth land 数据包含 Syvash 内陆水域，未从物理陆地扣除 Syvash，政治几何中的旧水域孔洞被陆地差集三角化填满，现以已有 Syvash 自然水面裁切；⑥约 9.8km DEM 的正高度背景会在物理海水中再画一层岸线，现仅在精确物理覆盖未准备时保留背景，陆地地形照常显示。所有政治身份、主权、控制和拾取几何保持原值。

克里米亚—亚速海：主要为粗政治几何与物理补片差异及纹理断裂。丹麦海峡：岛屿与窄海峡放大了独立简化和裁切外溢。梅梅尔—波罗的海：潟湖/沙嘴显示了旧面扩展的细线。诺曼底—加莱：长边球面弦投影与独立物理岸线进一步放大错位；巴黎范围还有既有 Local 物理参考遮罩。剩余来源限制为现代 1:10M 概化、1500m/300m 显示 LOD，以及未经提供方量化的历史岸位准确度；这些均不能解释或豁免渲染尖刺。

|区域|直接修改位置|
|---|---|
|克里米亚—亚速海|[build_geographic_foundation.py](D:/WWO/wwo/tools/map/build_geographic_foundation.py)、[repair_syvash_display_r3.py](D:/WWO/wwo/tools/map/repair_syvash_display_r3.py)、[local_spatial_lod.gd](D:/WWO/wwo/scripts/presentation/map/local_spatial_lod.gd)|
|丹麦海峡|[build_geographic_foundation.py](D:/WWO/wwo/tools/map/build_geographic_foundation.py)、[local_spatial_layer.gd](D:/WWO/wwo/scripts/presentation/map/local_spatial_layer.gd)|
|梅梅尔—波罗的海|[build_geographic_foundation.py](D:/WWO/wwo/tools/map/build_geographic_foundation.py)、[globe_water_surface.gdshader](D:/WWO/wwo/shaders/presentation/map/globe_water_surface.gdshader)|
|诺曼底—加莱|[build_geographic_foundation.py](D:/WWO/wwo/tools/map/build_geographic_foundation.py)、[globe_renderer.gd](D:/WWO/wwo/scripts/presentation/map/globe_renderer.gd)、[local_spatial_layer.gd](D:/WWO/wwo/scripts/presentation/map/local_spatial_layer.gd)|


## E. POLITICAL BOUNDARIES

国界采用同一源中真实共享边联合简化，保留已有阿拉伯有据边界；不从两个独立简化多边形的偶合边推断国界。细单线提高连续性，并置于物理补片之上。国家填色/拾取仍沿用原权威几何。

## F. RAILWAY PRESENTATION

宏观虚线为约 1900 年铁路廊道示意，Political 默认抑制；既有巴黎近似铁路线与 Local 轨道仍按原数据范围呈现。未新增工程或军事通达事实。

## G. CITY MARKERS

城市点使用受控尺度、等级和选择状态，降低所有城市同样醒目的黄色点干扰；国家标签先安排，城市文字避让。

## H. COUNTRY LABELS

离线主连通陆地内部位置取代首都位置，视图移动使用有限缓存候选。Georgia/Cambria/Times New Roman/SimSun 系统字体后备，16–28px 字号桶与轮廓提高可读性。八个已核验名称为 République française、Deutsches Reich、United Kingdom、Österreich-Ungarn、Российская империя、Devlet-i Osmaniye、大清、España；来源与语言政策记录在 country_label_layout_r3.json。未核验国家仍用既有中文身份，奥匈/大清的代表文字不宣称唯一官方语言。

## I. TERRAIN VISIBILITY

沿用既有 ETOPO 2022 RG 参考纹理，通过静态高度与阴影组合改善比利牛斯、阿尔卑斯、喜马拉雅—青藏、落基山和安第斯的可见性；经济模式降低混合。参考像元约 9.8km，平原与 Local 不能因此获得虚构精细地形，未添加动画、额外 DEM 或模拟因素。

## J. DEFAULT GLOBE CAMERA

1280×720 首次 WORLD 直径由约 369px 调为 480px，即窗口高度约 2/3；首次有效尺寸执行一次，用户操作后不重复重置。世界/区域/Local 阈值、方向和手势保持原契约。

## K. MEMORY ROOT CAUSE

原 FAR 成本包含大范围文本 JSON、SourceFact 深复制/断言序列化、解析后的通用数组、有限 LOD 向量、面纹理与 GPU 批次，并非只能归因于海岸点数。SHA256 绑定的无损压缩几何侧车使 admission 使用紧凑描述；只解码请求分片，同一侧车每次请求只读一次。新指标区分 admission、解压、哈希、解析和几何准备；不能将进程 Private Bytes 的高水位全部称为仍驻留的地图对象。 最终 FAR 源分片 4,653,163 bytes，解码几何 15,949,308 bytes，紧凑向量 5,529,540 bytes，GPU 几何 39,796,120 bytes；这些指标分别属于编码/解析/几何/GPU，不能相加当作进程总 RAM。FAR 参考段数由旧版 45,593 增为 59,313，保留真实水域和同源边缘需要更多数据；不能通过吞掉细节使成本下降。

## L. RESOURCE RESIDENCY

静止后地图没有持续处理或重绘；新旧 LOD 仅在替换期间短暂共存。离开地图释放当前与 fallback 几何、细地形与 shader 引用；系统字体、基础场景、只读政治几何及进程分配器可保持驻留。重复跨区旅行的进程/GPU/对象样本另附，区分真实资源与分配器保留。

before 三轮跨区旅行：[进程 / GPU / 对象原始指标](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-travel-release/summary.json)；第 1 轮返回西欧 WS 628.4MiB，独占显存 208.4MiB，资源对象 163.0；第 2 轮返回西欧 WS 641.4MiB，独占显存 205.2MiB，资源对象 163.0；第 3 轮返回西欧 WS 657.1MiB，独占显存 205.2MiB，资源对象 163.0

after 三轮跨区旅行：[进程 / GPU / 对象原始指标](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-travel-release/summary.json)；第 1 轮返回西欧 WS 656.8MiB，独占显存 222.2MiB，资源对象 163.0；第 2 轮返回西欧 WS 663.8MiB，独占显存 222.2MiB，资源对象 163.0；第 3 轮返回西欧 WS 662.7MiB，独占显存 222.3MiB，资源对象 163.0

## M. INITIAL LOAD COST

见安静冷启动取证和各尺度准备指标。首次有用几何、完整目标 LOD、CPU worker、admission、解压/哈希/解析、GPU enqueue、首次可见帧分别记录；Labels 切换不能代替加载完成证据。

before：[原始冷启动指标](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-cold-quiet/cold-summary.json)；cold_far 首次有用 4968.078ms，完整目标 4968.078ms，Labels 未触碰=True；cold_mid 首次有用 3117.762ms，完整目标 3117.762ms，Labels 未触碰=True

after：[原始冷启动指标](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-cold-quiet/cold-summary.json)；cold_far 首次有用 4925.4ms，完整目标 4925.4ms，Labels 未触碰=True；cold_mid 首次有用 773.31ms，完整目标 773.31ms，Labels 未触碰=True 首次有用/完整时间按首次观察到可见批次且画布实际重绘的样本确定，分辨率受取样间隔限制；仅 ready/batches 不算画面证据，原始 PNG 同时保留。目录名称 quiet 表示本任务未同时构建或模拟；同机研究测试进程见各目录 background-processes.json，不能据此称整机空闲。

## N. FRAME / GPU / POWER

RTX 3050 Laptop GPU，同设备；Person 与五个地图尺度静止 20s、pan/zoom 12s。以下每格为修改前 → 修改后。CPU 为全逻辑处理器归一化，进程 GPU 来自 Windows 计数器，功耗为板卡 nvidia-smi，Godot VRAM 不等同整机显存。完整 CSV 还包含板卡 GPU、Shared、texture/buffer 和 draw calls。历史 REGION MID 最大帧 184.604ms 保留作为旧记录；本次未复现也不能删除。

|阶段|median ms|p95 ms|p99 ms|max ms|CPU %|进程 GPU %|板卡 W|WS MiB|Private MiB|独占显存 MiB|Godot VRAM MiB|重绘增量|
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|person_idle|16.65 → 16.69|17.81 → 17.73|18.26 → 18.18|19.92 → 24.73|0.13 → 0.09|0.00 → 0.00|3.38 → 3.40|544.36 → 521.60|744.68 → 725.60|170.07 → 171.93|129.21 → 132.07|0.00 → 0.00|
|world_idle|16.70 → 16.65|17.74 → 17.83|18.10 → 18.13|19.03 → 24.38|0.09 → 0.05|0.00 → 0.00|3.37 → 3.40|559.10 → 549.79|773.54 → 767.41|180.44 → 184.30|136.21 → 139.32|0.00 → 0.00|
|world_pan|16.66 → 16.95|17.72 → 20.07|19.08 → 25.06|29.41 → 31.70|3.38 → 4.88|20.03 → 21.15|7.78 → 7.79|559.31 → 549.63|773.91 → 767.41|180.39 → 184.24|136.34 → 139.57|420.00 → 409.00|
|world_zoom|16.66 → 16.87|18.05 → 18.95|21.70 → 23.01|27.69 → 33.66|3.42 → 4.92|20.36 → 19.59|7.78 → 7.78|559.32 → 550.03|773.91 → 767.84|180.39 → 184.24|136.34 → 139.57|419.00 → 407.00|
|region_far_idle|16.71 → 16.63|17.50 → 17.65|18.11 → 18.15|19.17 → 33.22|0.13 → 0.05|0.00 → 0.00|3.40 → 3.42|815.66 → 785.12|1088.67 → 1064.89|230.39 → 238.26|186.54 → 196.17|0.00 → 0.00|
|region_far_pan|16.81 → 16.67|19.16 → 24.64|25.25 → 39.60|32.59 → 47.46|4.01 → 4.53|25.45 → 20.68|8.89 → 11.18|813.97 → 785.30|1086.93 → 1060.94|230.39 → 235.12|186.47 → 195.65|432.00 → 420.00|
|region_far_zoom|16.79 → 17.27|20.93 → 20.94|22.01 → 25.67|23.94 → 30.68|4.27 → 4.97|23.13 → 20.38|8.87 → 10.89|814.57 → 783.40|1087.58 → 1058.94|230.39 → 235.12|186.55 → 196.17|412.00 → 390.00|
|region_mid_idle|16.69 → 16.67|17.60 → 17.75|18.10 → 18.28|18.26 → 18.76|0.11 → 0.09|0.00 → 0.00|3.39 → 3.45|677.18 → 689.94|943.29 → 978.13|224.39 → 247.12|168.37 → 172.83|0.00 → 0.00|
|region_mid_pan|16.63 → 16.66|18.02 → 17.96|18.77 → 20.88|23.82 → 26.60|3.81 → 3.66|21.72 → 21.74|7.93 → 8.02|677.29 → 689.98|944.02 → 962.16|224.39 → 231.12|168.37 → 172.83|420.00 → 419.00|
|region_mid_zoom|16.78 → 17.00|23.36 → 29.85|39.41 → 34.85|67.24 → 54.18|7.70 → 4.88|20.72 → 22.49|7.94 → 8.06|700.33 → 704.26|967.82 → 979.73|224.39 → 231.12|168.37 → 173.08|469.00 → 460.00|
|region_near_idle|16.68 → 16.65|17.80 → 17.92|18.20 → 18.35|22.47 → 18.84|0.10 → 0.05|0.00 → 0.00|3.41 → 3.44|692.09 → 705.05|950.94 → 976.61|219.26 → 231.12|168.34 → 173.05|0.00 → 0.00|
|region_near_pan|16.68 → 16.66|17.86 → 17.78|18.92 → 19.01|20.90 → 27.40|3.50 → 3.44|20.42 → 22.66|7.97 → 8.05|692.18 → 705.07|950.94 → 972.61|219.26 → 227.12|168.34 → 173.05|420.00 → 420.00|
|region_near_zoom|16.68 → 16.69|17.84 → 18.33|19.00 → 22.85|23.11 → 33.08|3.65 → 3.66|21.60 → 22.31|7.92 → 8.02|692.18 → 705.14|950.94 → 972.62|219.26 → 227.12|168.35 → 173.06|419.00 → 419.00|
|paris_local_idle|16.66 → 16.66|17.69 → 17.74|18.15 → 18.09|18.80 → 20.10|0.13 → 0.05|0.00 → 0.00|3.42 → 3.43|698.81 → 705.38|963.53 → 975.33|219.26 → 227.12|164.38 → 168.41|0.00 → 0.00|
|paris_local_pan|16.64 → 16.65|17.65 → 17.74|17.99 → 20.47|18.73 → 26.22|3.26 → 3.01|23.47 → 20.35|7.78 → 7.91|698.82 → 705.40|954.09 → 963.18|211.26 → 215.12|164.38 → 168.41|420.00 → 420.00|
|paris_local_zoom|16.66 → 16.68|17.64 → 17.98|18.06 → 22.16|18.58 → 28.65|3.30 → 2.95|22.81 → 21.38|7.81 → 7.91|698.82 → 705.45|954.09 → 963.18|211.26 → 215.12|164.39 → 168.41|420.00 → 419.00|
|person_return_idle|16.67 → 16.64|17.59 → 17.71|18.11 → 18.47|19.35 → 19.00|0.04 → 0.12|0.00 → 0.00|3.40 → 3.45|698.92 → 705.46|945.34 → 963.18|203.12 → 215.12|141.72 → 145.75|0.00 → 0.00|

[完整指标 CSV](D:/WWO/wwo/local-artifacts/map-correctness-r3/resources-comparison.csv)

紧邻 FAR 复测（相同 30s pan / 20s zoom）：

before-far-matched-recheck / region_far_pan：p95 19.666ms，max 33.013ms，板卡 8.675W，WS 780.9MiB。

before-far-matched-recheck / region_far_zoom：p95 19.367ms，max 34.787ms，板卡 8.510W，WS 781.1MiB。

capped-reference-far / region_far_pan：p95 21.933ms，max 33.960ms，板卡 11.090W，WS 817.9MiB。

capped-reference-far / region_far_zoom：p95 18.300ms，max 25.550ms，板卡 11.100W，WS 818.0MiB。

已拒绝的第一版修正包 FAR zoom 最大帧 197.739ms 留存于 [第一次完整资源取证](D:/WWO/wwo/local-artifacts/map-correctness-r3/rejected-first-resource-release/summary.json)，不能以最终版本未复现来删去。最终采样开始时同机另有研究 Headless 测试进程，见 [背景进程记录](D:/WWO/wwo/local-artifacts/map-correctness-r3/resource-start-background-processes.json)；板卡功耗为整卡读数，不能归为本游戏独占或严格因果估计。

本轮完整采样的高水位（before → after，bytes）：{"before": {"working_set": 886603776.0, "private_bytes": 1175826432.0, "dedicated_gpu_bytes": 243675136.0, "shared_gpu_bytes": 74563584.0}, "after": {"working_set": 887926784.0, "private_bytes": 1179656192.0, "dedicated_gpu_bytes": 259129344.0, "shared_gpu_bytes": 69820416.0}}。FAR p95 与功耗仍恶化，故不报告约 60 FPS 或地图联合质量 PASS。

## O. VISUAL EVIDENCE

下表链接为可直接打开的原始 PNG；未裁图、修图或重绘。对比页 [compare.html](D:/WWO/wwo/local-artifacts/map-correctness-r3/compare.html)。

|区域|尺度|修改前|修改后|
|---|---:|---|---|
|克里米亚—亚速海|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/crimea_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/crimea_4500.png)|
|克里米亚—亚速海|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/crimea_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/crimea_1200.png)|
|克里米亚—亚速海|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/crimea_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/crimea_400.png)|
|克里米亚—亚速海|200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/crimea_200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/crimea_200.png)|
|刻赤海峡|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/kerch_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/kerch_4500.png)|
|刻赤海峡|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/kerch_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/kerch_1200.png)|
|刻赤海峡|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/kerch_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/kerch_400.png)|
|刻赤海峡|200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/kerch_200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/kerch_200.png)|
|丹麦海峡|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/denmark_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/denmark_4500.png)|
|丹麦海峡|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/denmark_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/denmark_1200.png)|
|丹麦海峡|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/denmark_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/denmark_400.png)|
|丹麦海峡|200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/denmark_200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/denmark_200.png)|
|梅梅尔—波罗的海|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/memel_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/memel_4500.png)|
|梅梅尔—波罗的海|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/memel_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/memel_1200.png)|
|梅梅尔—波罗的海|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/memel_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/memel_400.png)|
|梅梅尔—波罗的海|200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/memel_200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/memel_200.png)|
|诺曼底|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/normandy_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/normandy_4500.png)|
|诺曼底|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/normandy_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/normandy_1200.png)|
|诺曼底|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/normandy_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/normandy_400.png)|
|诺曼底|200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/normandy_200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/normandy_200.png)|
|加莱|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/calais_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/calais_4500.png)|
|加莱|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/calais_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/calais_1200.png)|
|加莱|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/calais_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/calais_400.png)|
|加莱|200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/calais_200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/calais_200.png)|
|法国|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/france_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/france_4500.png)|
|法国|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/france_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/france_1200.png)|
|法国|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/france_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/france_400.png)|
|西班牙|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/spain_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/spain_4500.png)|
|西班牙|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/spain_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/spain_1200.png)|
|西班牙|400 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/spain_400.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/spain_400.png)|
|欧洲整体|4500 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/europe_4500.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/europe_4500.png)|
|欧洲整体|1200 m/px|[原始修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/europe_1200.png)|[原始修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/europe_1200.png)|

其他实际 Release 画面：[pyrenees](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/pyrenees_1200.png)、[alps](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/alps_1200.png)、[himalaya](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/himalaya_1200.png)、[rockies](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/rockies_1200.png)、[andes](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/andes_1200.png)、[plains](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/plains_1200.png)、[germany](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/germany_1200.png)、[britain](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/britain_1200.png)、[austria](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/austria_1200.png)、[russia](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/russia_1200.png)、[ottoman](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/ottoman_1200.png)、[qing](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/qing_1200.png)。慢速 / 快速缩放与准备期间拖动：[逐帧状态记录](D:/WWO/wwo/local-artifacts/map-correctness-r3/native-final-fast-slow-capped/cold-trace.jsonl)；[存档一致性](D:/WWO/wwo/local-artifacts/map-correctness-r3/native-final-fast-slow-capped/journey.json)。

|其他区域|修改前 MID|修改后 MID|
|---|---|---|
|pyrenees|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/pyrenees_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/pyrenees_1200.png)|
|alps|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/alps_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/alps_1200.png)|
|himalaya|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/himalaya_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/himalaya_1200.png)|
|rockies|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/rockies_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/rockies_1200.png)|
|andes|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/andes_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/andes_1200.png)|
|plains|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/plains_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/plains_1200.png)|
|germany|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/germany_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/germany_1200.png)|
|britain|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/britain_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/britain_1200.png)|
|austria|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/austria_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/austria_1200.png)|
|russia|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/russia_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/russia_1200.png)|
|ottoman|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/ottoman_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/ottoman_1200.png)|
|qing|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/qing_1200.png)|[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/qing_1200.png)|

默认 WORLD 大小：[修改前 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/before-matched-visual/default_world.png) / [修改后 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/default_world.png)；巴黎 Local：[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/paris_local.png)；返回 WORLD：[原始 PNG](D:/WWO/wwo/local-artifacts/map-correctness-r3/after-matched-visual/world_return.png)。80 组固定区域相机与 PNG SHA256 核对见 [原生对比审计](D:/WWO/wwo/local-artifacts/map-correctness-r3/native-png-camera-audit.json)。

## P. WORLD FACTS / SAVE

导出审计逐字节核验 213 个保护文件；正常 Source/WorldState/领土、行政、人口、行动与经济事实未改变。原生旅程保存快照一致，formal_world_simulation_v15 不变。新的展示资料只经内容层读取，渲染层只接收脱离加载器的数据副本。

## Q. VALIDATION

统一验证：Python 62 项；Godot 36 组，共 31679 checks，0 failures；退出码与日志扫描见 [完整统一验证日志](D:/WWO/wwo/local-artifacts/map-correctness-r3/validation-final.log)。十年内部 240 秒上界及既有外部超时不变。包含存档、30 日、一年和十年回归。实际 Release 截图为自动输入旅程，不能声称用户人工旅程已完成。 最终十年回归实测 168.911s。 统一验证进程退出码 0；Windows Release 导出与全部截图/资源取证进程均退出 0，stderr 为空。

## R. RELEASE SIZE

正式包 204,002,144 bytes；上一包 258,678,488 bytes；变化 -54,676,344 bytes。PCK 不包含 GIS 原始源、geo-env、测试、工具、报告、取证 PNG 或 probe autoload。正式包与取证包的全部运行数据、场景、shader、素材和编译产品脚本逐字节一致，见 [PCK 等价审计](D:/WWO/wwo/local-artifacts/map-correctness-r3/release-package-audit.json)。 清理 22 个旧安装/临时取证 EXE，共释放 4,953,550,816.0 bytes；仅保留本轮正式 Release，原始 PNG、日志、资源测量与可复现源快照保留。清理清单：[installation-cleanup.json](D:/WWO/wwo/local-artifacts/map-correctness-r3/installation-cleanup.json)。

## S. MODIFIED FILES

内容边界：geography_loader.gd、historical_loader.gd、map_geometry_content.gd；按需加载与无损编码：strategic_spatial_loader.gd；旧 LOD 保留、批次合并、UV 连续和城市缓存：local_spatial_layer.gd、local_spatial_lod.gd；显示顺序、标签、国界、默认视角：globe_renderer.gd、region_view.gd、globe_controller.gd、labels.gd；静态地形与海水裁切：map_scale_style.gd、political_surface.gdshader、globe_water_surface.gdshader。离线工具及新回归用于检验这些问题，导出侧车 filter 更新于 export_presets.cfg。全部生产变更文件见 [文件清单](D:/WWO/wwo/local-artifacts/map-correctness-r3/modified-production-files.json)。 性能修正位于 globe_surface_batch.gd 和 local_spatial_lod.gd：显示参考面不保留权威拾取缓存、采用 6 顶点/12 索引、上传后释放可再生 CPU 数组、缓存模板参数，并在已有批次循环中用离线计算的保守球面包围帽剔除屏外批次。原政治面的拾取和三角化契约保持不变。

## T. REMAINING GAPS

历史数据：未重建精确 1900 海岸、河岸、水位与现代填海差异；既有行政边界和巴黎土地缺口保持显式未知。来源精度：Natural Earth 1:10M、ETOPO 约 9.8km、CShapes 历史精度未量化；显示 LOD 不能作为测量精度。实际产品缺陷与人工验收结果必须单列，不能归入正常概化来获得 PASS。 实测 FAR pan 与板卡功耗仍退化，因此本轮联合验收为 PERFORMANCE_NOT_PASS；尚不能宣称低功耗成果全部保持。物理岸线细节增加及参考补片绘制带来成本，已撤回帧时间更差的空间分组试验。静止零重绘保留，不抵消交互成本。

## U. NEXT RECOMMENDATION

停止地图扩张和新系统施工，交回本版 Release、同视角 PNG 与资源证据供用户打开验收。若画面仍有错位或资源退化，仅继续修复对应实际问题。
