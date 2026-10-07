# WWO Map Resource Efficiency / Region LOD R2

RESULT=PASS

2026-10-07；Godot 4.6.3 / Compatibility，Windows Release，1280×720，NVIDIA RTX 3050 Laptop GPU。产品 `D:\WWO\wwo\builds\windows\wwo-map-resource-efficiency-r2-final.exe`，SHA256 `2899752e0deffaeb85a173ec554183748898044758dbd46722ed491882946edc`。正式产品与测量包使用相同生产脚本、shaders、data、scenes；测量包只以独立启动场景驱动正常产品并读取计数。

测量条件：同机连续旧版/修改版；没有并行 Godot 测试或导出。窗口以 Normal 创建，部分时间被用户其他应用覆盖，不能称为持续不被遮挡的前台实验。CPU 是进程 CPU / 20 逻辑核心；GPU 是进程最忙引擎计数，不能相加；NVIDIA GPU%/W 是整块板卡，包含其他应用。系统采样约 2–3 s，产品内部 1 Hz；稳态中位数排除首 5 s 与结束边缘，原始完整 60/90/30 s 数据保留。时长为 2 s 的视觉停留只验图，不作功耗结论。Release tracked RAM=0 是构建不支持，不能当作零 RAM；另用同源 Debug 量 CPU 缓存。

## A. Fan / power root cause

原有 Region SubViewport 已按 UPDATE_ONCE 缓存；真正仍持续刷新的主要来源是 root viewport：旧全局背景 shader 引用 TIME，且 low-processor mode 未启用。静止地图仍每秒绘制约 60 次完整 root 画面。移除背景 TIME、保留静态星空相位，并启用 Godot 现有按变化刷新路径；没有新 rendering framework。三个 60 s 控制实验：

| experiment | CPU% | process GPU% | board W | draw frames / sampled steady span | last-frame calls |
| --- | --- | --- | --- | --- | --- |
| ablation_static_continuous | 1.29 | 21.47 | 5.78 | 3180 | 150 |
| ablation_time_on_demand | 0.95 | 21.33 | 5.79 | 3180 | 150 |
| ablation_static_on_demand | 0.13 | 0.00 | 3.43 | 0 | 150 |

首次接近 Paris 的额外工作是 worker 上的读取/parse/evidence resolution，加上有限批次的 GPU enqueue/标签准备。它是有终点的短时工作；稳态不重复。风扇 RPM 不可读取，未实测转速，不能证明此前肉眼观察的每次风扇升速对应哪一采样点；这里确认的是 workload 与板卡功耗的因果对照，未承诺风扇完全无声。昨天低电量且隐藏窗口的数据、28–30 ms 提交探针未混入本次基线；本次短测曾在可见前台重现约60FPS/2.5–5ms提交，不能把所有环境差异都归为代码。

## B. Person idle baseline

每次 Release 都先完整静止60 s；启动/焦点准备另留30 s。Person 的同次运行基线用于计算地图增量，整个产品没有运行世界时间。

## C. Map steady power

正文列出全部静止及操作场景；每项包含实际进程利用率与板卡功耗。旧版 right 是尚未支持的无操作，不能用其较低负载宣称新旋转回退。

| stage | version | CPU% | process GPU% | board GPU% | board W | WS MiB | Godot video MiB | last frame calls |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| person_idle | before | 1.09 | 13.45 | 27.00 | 4.86 | 485.85 | 125.66 | 64 |
| person_idle | after | 0.12 | 0.00 | 0.00 | 3.43 | 508.79 | 125.66 | 64 |
| world_open_timeline | before | 1.16 | 21.22 | 41.00 | 5.78 | 516.86 | 131.33 | 101 |
| world_open_timeline | after | 0.13 | 0.00 | 0.00 | 3.43 | 531.00 | 131.33 | 265 |
| far_idle | before | 1.10 | 21.72 | 41.00 | 5.79 | 584.01 | 142.00 | 90 |
| far_idle | after | 0.12 | 0.00 | 0.00 | 3.40 | 581.16 | 132.49 | 115 |
| mid_idle | before | 1.07 | 21.82 | 41.00 | 5.78 | 582.37 | 142.02 | 106 |
| mid_idle | after | 0.22 | 0.00 | 0.00 | 3.40 | 584.90 | 134.37 | 106 |
| near_idle | before | 1.10 | 21.70 | 41.00 | 5.73 | 582.52 | 141.99 | 84 |
| near_idle | after | 0.11 | 0.00 | 0.00 | 3.42 | 585.20 | 134.34 | 84 |
| local_idle | before | 1.07 | 21.65 | 40.00 | 5.75 | 582.43 | 141.97 | 66 |
| local_idle | after | 0.13 | 0.00 | 0.00 | 3.41 | 589.75 | 138.05 | 66 |
| world_pan | before | 3.43 | 18.61 | 36.00 | 7.72 | 578.33 | 142.13 | 330 |
| world_pan | after | 3.44 | 18.19 | 36.00 | 7.62 | 587.52 | 131.58 | 334 |
| world_zoom | before | 3.45 | 17.92 | 35.50 | 7.73 | 578.36 | 142.13 | 334 |
| world_zoom | after | 3.42 | 17.85 | 35.00 | 7.62 | 587.54 | 131.58 | 326 |
| world_right | before | 1.46 | 21.34 | 41.00 | 5.82 | 578.37 | 142.13 | 162 |
| world_right | after | 3.77 | 18.41 | 35.50 | 7.61 | 587.66 | 131.58 | 349 |
| region_pan | before | 3.64 | 19.22 | 37.50 | 7.77 | 578.42 | 142.14 | 357 |
| region_pan | after | 3.85 | 19.78 | 36.50 | 7.74 | 588.95 | 134.50 | 380 |
| region_zoom | before | 3.59 | 19.55 | 37.00 | 7.77 | 578.49 | 142.14 | 358 |
| region_zoom | after | 4.25 | 20.03 | 37.00 | 7.72 | 589.00 | 134.50 | 381 |
| region_right | before | 1.22 | 21.97 | 41.00 | 5.82 | 580.14 | 142.14 | 108 |
| region_right | after | 4.14 | 20.05 | 38.50 | 7.71 | 590.01 | 134.50 | 384 |
| local_pan | before | 3.38 | 20.59 | 40.00 | 7.87 | 580.13 | 142.10 | 347 |
| local_pan | after | 3.49 | 20.17 | 38.00 | 7.79 | 593.61 | 138.18 | 348 |
| local_zoom | before | 3.43 | 20.38 | 39.00 | 7.83 | 579.89 | 142.10 | 350 |
| local_zoom | after | 3.57 | 21.85 | 39.00 | 7.84 | 593.61 | 138.18 | 349 |

地图静止相对 Person 的增量：

| version | map | CPU pp | GPU pp | W | WS MiB | video MiB |
| --- | --- | --- | --- | --- | --- | --- |
| before | world_open_timeline | 0.07 | 7.77 | 0.92 | 31.00 | 5.67 |
| before | far_idle | 0.01 | 8.27 | 0.94 | 98.15 | 16.33 |
| before | mid_idle | -0.02 | 8.37 | 0.92 | 96.52 | 16.35 |
| before | near_idle | 0.02 | 8.25 | 0.88 | 96.67 | 16.33 |
| before | local_idle | -0.02 | 8.20 | 0.89 | 96.57 | 16.30 |
| after | world_open_timeline | 0.01 | 0.00 | 0.00 | 22.21 | 5.67 |
| after | far_idle | -0.00 | 0.00 | -0.03 | 72.38 | 6.83 |
| after | mid_idle | 0.10 | 0.00 | -0.03 | 76.11 | 8.71 |
| after | near_idle | -0.02 | 0.00 | -0.01 | 76.41 | 8.68 |
| after | local_idle | 0.01 | 0.00 | -0.02 | 80.96 | 12.39 |

## D. Initial preparation power / timeline

从打开地图开始连续记录超过90 s，并继续穿越所有尺度。WORLD 停留不无条件准备 Paris；首次实际接近 FAR 才 request。后续 medium/local 在需要的尺度分别准备，不在 FAR 全部完成。

| event | seconds since run origin | meaning |
| --- | --- | --- |
| map opened | 93.077 | WORLD; no Paris read/prepare at this scale |
| Paris request | 183.191 | first approach to FAR; one worker read/admission |
| coarse ready | 184.493 | only the requested finite LOD |
| medium ready | 257.345 | only the requested finite LOD |
| local ready | 395.927 | only the requested finite LOD |
| all three CPU LODs visited | 395.927 | GPU keeps active Local LOD, not all three |
| first steady FAR | 189.587 | 60 s interval after a separate 5 s settling period |

| first FAR request | file_read ms | parse ms | source_resolution ms | geometry_prepare ms | lod_prepare ms | gpu_enqueue ms | label_prepare ms | ready_since_load ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before all | 10.839 | 119.102 | 712.467 | 23.897 | 42.588 | 458.048 | 4.764 | 3048.807 |
| after coarse | 7.414 | 112.824 | 846.505 | 30.831 | 19.293 | 42.010 | 4.315 | 1302.193 |

| first prepare +/-3s window | OS samples | CPU median / observed max % | GPU median / observed max % | board W median / observed max | ready ms |
| --- | --- | --- | --- | --- | --- |
| before all | 3 | 2.43 / 3.89 | 19.92 / 21.43 | 5.81 / 7.33 | 3073.11 |
| after staged coarse | 3 | 0.77 / 2.40 | 0.00 / 1.80 | 4.02 / 11.72 | 1323.75 |

上表是同机完整修改组合的对照，包含停止TIME重绘的效果；不能声称单独staged机制已降低硬件瞬时峰值。coarse的后续medium/local没有在第一次窗口提前上传；GPU enqueue总工作随需求分散，不阻塞相机。

系统2–3s采样可能漏掉更短峰值，不把采样峰值称为毫秒级真实上界。GPU enqueue 是 RenderingServer 提交时间，不等同硬件 fence 完成时间；首次可见帧另由计数记录。

## E. Idle work

camera/world facts 不变时：不 parse、不 admission、不 simplify、不 mesh rebuild、不生成 label source、不做 collision/LOD/admin cache 操作、不重复 visibility assignment。小型控制器/暂停 UI/本地1Hz测量计数仍有进程开销；地图本身计数如下：

| stage | new rendered frames | map draw | view update | CPU geography projections | cumulative LOD uploads |
| --- | --- | --- | --- | --- | --- |
| person_idle | 0 | 0 | 0 | 0 | {} |
| world_open_timeline | 0 | 0 | 0 | 0 | {} |
| far_idle | 0 | 0 | 0 | 0 | {'coarse': 1} |
| mid_idle | 0 | 0 | 0 | 0 | {'coarse': 1, 'medium': 1} |
| near_idle | 0 | 0 | 0 | 0 | {'coarse': 1, 'medium': 1} |
| local_idle | 0 | 0 | 0 | 0 | {'coarse': 1, 'local': 1, 'medium': 1} |

## F. Viewport / redraw

WORLD、REGION 使用已有静态 mesh/cache；变化时 shader uniform 和必要 picking transform 更新，SubViewport UPDATE_ONCE。切换页时 renderer/controller suspended、两个 viewports UPDATE_DISABLED。准备和短 crossfade 完成后 _process 关闭。背景不再 TIME 驱动。Godot draw-call/primitives monitor 静止时保留最后一帧数值，不能将其乘60当作实际稳态绘制量；应同时看 frames_drawn delta。官方机制：[OS low_processor_usage_mode](https://docs.godotengine.org/en/4.6/classes/class_os.html#class-os-property-low-processor-usage-mode)。

## G. LOD residency / lifecycle

同一 stable feature/source fact 对应 coarse600m / medium120m / local0m 三个有限 Presentation LOD，canonical 未简化或删除。默认 active-only：旧可见 batch 保留到新 batch ready，允许短时 old+in-flight；ready 后回到一个LOD。分阶段 CPU worker 与预算2ms GPU enqueue，camera 不 reparses 或实时 simplify。离开支持范围待 transition 完成，释放详细 mesh/material/line textures/glyph canvas items；保留单个 canonical CPU owner 与已访问的有限LOD cache，返回只重传。

| policy | scale | resident | CPU% | GPU% | W | WS MiB | video MiB | LOD payload MiB | calls |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| all | far | coarse,local,medium | 0.11 | 0.00 | 3.42 | 595.79 | 142.15 | 13.23 | 319 |
| all | mid | coarse,local,medium | 0.10 | 0.00 | 3.40 | 595.96 | 142.14 | 13.23 | 379 |
| all | local | coarse,local,medium | 0.13 | 0.00 | 3.40 | 584.43 | 142.10 | 13.23 | 358 |
| adjacent | far | coarse | 0.12 | 0.00 | 3.41 | 579.45 | 132.61 | 1.26 | 319 |
| adjacent | mid | coarse,medium | 0.12 | 0.00 | 3.44 | 580.49 | 135.51 | 4.91 | 380 |
| adjacent | local | local,medium | 0.12 | 0.00 | 3.38 | 585.81 | 141.09 | 11.97 | 358 |
| active | far | coarse | 0.14 | 0.00 | 3.42 | 580.16 | 132.61 | 1.26 | 320 |
| active | mid | medium | 0.12 | 0.00 | 3.40 | 584.77 | 134.50 | 3.64 | 379 |
| active | local | local | 0.12 | 0.00 | 3.44 | 588.83 | 138.18 | 8.33 | 358 |

三种策略稳态GPU均为0、功耗差在噪声范围；不会宣称少驻留本身降低静止瓦数。选择active-only主要因为最低GPU/video payload与简单有界生命周期。Local GPU首次/重返上传约1.3s，期间保持旧LOD/REGION并接受camera input，准备帧没有持续50/100ms冻结；它不是零延迟。补测每个policy先释放GPU，再在350m/px等待准备，随后到188，公平展示adjacent预取收益：

| policy | scale | ready ms | p95 frame ms | max frame ms |
| --- | --- | --- | --- | --- |
| all | 350.0 | 3013.39 | 19.78 | 289.16 |
| all | 188.0 | 17.43 | 17.42 | 17.42 |
| adjacent | 350.0 | 1845.82 | 18.77 | 27.70 |
| adjacent | 188.0 | 23.49 | 23.47 | 23.47 |
| active | 350.0 | 598.59 | 18.92 | 28.68 |
| active | 188.0 | 1301.86 | 21.12 | 24.45 |

adjacent在Near提前约1.85s准备medium+local，Local入口约24ms；active Near约0.60s、Local另等约1.30s。它以约11.97MiB而非8.33MiB换取进入延迟。补测首个all冷启动直接350有一次289ms帧，原始证据保留；正常主序列从WORLD接近FAR的首次准备max23.59ms，其后准备≤29ms，不能把这次冷fixture跳跃称为正常旅程完全零spike。按本轮RESOURCE > POWER > FRAME > LATENCY顺序选择C，没有为所有未来shard建立常驻队列。

## H. Multi-shard scaling

Debug canonical 增量 20.68 MiB；三个 CPU LOD 增量 5.98 MiB；共 26.66 MiB。当前实现只有一个内容 owner；begin 更换 owner 清理旧缓存，未建立全球 loader。以下是同等 Paris 数据量的有界估计，不是已实现100地区测试；catalogue更多条目不要求 parse/prepare/GPU resident，后台只有当前 requested 的一个worker。

| shards in catalogue | CPU one retained owner MiB | active Local payload MiB | naive all parsed MiB | naive all LOD GPU MiB |
| --- | --- | --- | --- | --- |
| 10 | 26.66 | 8.33 | 266.63 | 132.32 |
| 50 | 26.66 | 8.33 | 1333.13 | 661.62 |
| 100 | 26.66 | 8.33 | 2666.26 | 1323.24 |

表内 GPU 是 mesh/index/float line-texture payload；不含共享World、字体、driver页池。切换允许两个有限LOD的瞬时峰值。保留CPU的依据是约27MiB/一个owner，以及首次 admission≈1s、返回不read/parse；如扩区，必须延续单owner/有界nearby原则，不能增加无上限dictionary。

## I. Region Far

4500m/px：旧版只有Paris的 shard label，旗帜/政治面占主导；新版本更早允许重要 settlements，coastline与主河流从可见权重开始。仍只覆盖实际Paris约300km，欧洲其余部分不伪造细图。

## J. Region Mid

2000m/px：rail约0.9可见权重、2.4px铁路条带，river/coast更强；重要城市标签已支持。1200m/px开始medium geometry，可读巴黎向北/东/西/南的历史走廊和Seine骨架。flag与政治色仍用现有连续uniform混合，无政治事实变化。

## K. Region Near

700m/px增加一组重要区域节点；350m/px保留medium细河流/铁路形状。188m/px切换local geometry；75m/px允许secondary labels，但只能展示现有53个有依据的 settlements 与当前viewport实际范围。有限数据密度不能声称整个法国细图已完成。

## L. Railway style

选择style2：dark base / light core，加7px轻微周期条纹；一个既有strip mesh与一个draw/batch，没有轨枕geometry、双重draw或route事实变化。对照0（金色，新同宽条带）/1（暗底亮芯）/2（轻周期）各30s pan：

| style | CPU% | GPU% | W | calls | primitives | p95 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 4.67 | 19.82 | 7.69 | 305 | 1021776 | 17.90 | 23.88 |
| 1 | 4.61 | 20.02 | 7.71 | 305 | 1021776 | 17.93 | 35.39 |
| 2 | 4.45 | 20.07 | 7.73 | 305 | 1021776 | 17.77 | 20.81 |

仍是历史走廊身份 + modern SNCF bounded reference，不能当精确1900 routing。底部精度提示保留。真正旧版1.4px黄色线见 before/near；三种新同几何候选另有截图。

## M. Right-button bearing

RMB有效pick后固定地理点与screen pixel；相对水平movement连续转动已有orientation/bearing（0.008rad/px）。单击无角度跳动、不snap、不自动居中；zoom/selection/mode/date不变。边缘超出既有有限域时拒绝旋转，不能通过夹紧位置破坏anchor。左键平移不变，无新north-up按钮。WORLD/REGION的30s right操作使用真实Release产品 _gui_input 的InputEvent序列；工具不能OS注入右键拖拽，因此不能称为物理鼠标右拖人工实测。回归跨WORLD↔REGION↔LOCAL：anchor误差0px（阈值0.02），无新全图CPU projection、mesh upload、label glyph source。性能见C/P，比较本尺度pan。

## N. Local handoff at ~200m/px

Paris中心、date1900、support=true、local LOD ready、chart offset0、viewport满足既有300km域，188m/px→LOCAL。等待细LOD时保持REGION，不把coarse-ready当local-ready。不能从用户旧截图还原当时camera。另一个实测反例：pointer在Paris、188、local_ready=true、supported=true，但原chart距Paris924.311km>既有500km上限，正确留REGION；不能称为已确认旧截图原因。selection/bearing连续。Beijing/NewYork仍REGION，无Paris线/点、细GPU资源0；返回Paris只重传，source load_count仍1。

## O. Memory / draw calls / release

| stage | version | WS MiB | private MiB | Windows dedicated MiB | Windows shared MiB | Godot buffers MiB | Godot textures MiB | last frame primitives |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| person_idle | before | 485.85 | 690.91 | 172.81 | 59.99 | 21.00 | 104.66 | 852 |
| person_idle | after | 508.79 | 727.07 | 174.82 | 53.21 | 21.00 | 104.66 | 852 |
| world_open_timeline | before | 516.86 | 730.18 | 182.18 | 64.91 | 21.05 | 110.29 | 3432 |
| world_open_timeline | after | 531.00 | 734.55 | 172.13 | 68.25 | 21.05 | 110.29 | 862292 |
| far_idle | before | 584.01 | 789.23 | 186.10 | 53.24 | 28.52 | 113.47 | 2458 |
| far_idle | after | 581.16 | 785.52 | 172.10 | 59.31 | 21.78 | 110.71 | 4058 |
| mid_idle | before | 582.37 | 791.52 | 186.10 | 53.12 | 28.54 | 113.47 | 3482 |
| mid_idle | after | 584.90 | 796.07 | 176.10 | 59.31 | 23.11 | 111.26 | 3482 |
| near_idle | before | 582.52 | 791.62 | 186.10 | 53.12 | 28.51 | 113.47 | 2074 |
| near_idle | after | 585.20 | 796.20 | 176.10 | 59.31 | 23.08 | 111.26 | 2074 |
| local_idle | before | 582.43 | 791.68 | 186.10 | 53.12 | 28.49 | 113.47 | 920 |
| local_idle | after | 589.75 | 812.17 | 184.10 | 58.79 | 25.72 | 112.33 | 920 |
| world_pan | before | 578.33 | 796.07 | 186.24 | 57.12 | 28.53 | 113.60 | 862316 |
| world_pan | after | 587.52 | 806.37 | 180.24 | 62.79 | 21.05 | 110.54 | 862310 |
| world_zoom | before | 578.36 | 796.07 | 186.24 | 57.12 | 28.53 | 113.60 | 862251 |
| world_zoom | after | 587.54 | 795.23 | 172.24 | 62.79 | 21.04 | 110.54 | 862251 |
| world_right | before | 578.37 | 796.07 | 186.24 | 57.12 | 28.53 | 113.60 | 3376 |
| world_right | after | 587.66 | 795.23 | 172.24 | 62.79 | 21.05 | 110.54 | 862361 |
| region_pan | before | 578.42 | 796.12 | 186.24 | 57.12 | 28.54 | 113.60 | 915972 |
| region_pan | after | 588.95 | 800.98 | 176.24 | 62.79 | 23.11 | 111.39 | 1023334 |
| region_zoom | before | 578.49 | 796.20 | 186.24 | 57.12 | 28.54 | 113.60 | 916040 |
| region_zoom | after | 589.00 | 801.01 | 176.24 | 62.79 | 23.11 | 111.39 | 1023402 |
| region_right | before | 580.14 | 797.84 | 186.24 | 57.12 | 28.54 | 113.60 | 3610 |
| region_right | after | 590.01 | 802.00 | 176.24 | 62.79 | 23.11 | 111.39 | 1023439 |
| local_pan | before | 580.13 | 797.81 | 186.24 | 57.12 | 28.50 | 113.60 | 1233006 |
| local_pan | after | 593.61 | 815.27 | 184.24 | 62.79 | 25.72 | 112.45 | 1233043 |
| local_zoom | before | 579.89 | 797.81 | 186.24 | 57.12 | 28.50 | 113.60 | 1233080 |
| local_zoom | after | 593.61 | 815.27 | 184.24 | 62.79 | 25.72 | 112.45 | 1233080 |

Release Godot tracked RAM所有场景返回0（不可用）；Debug缓存测量单独列于H。GPU driver可能保留页池，所以RID释放量与Windows dedicated下降不必一一相等；Godot及payload计数分别保留。Release增量 6896 bytes；包169585456 bytes，751条目，无tools/tests/docs/local-artifacts或raw scan，shard SHA256 `ccbb2954cb57ea66e2f34c302581f726b30c2d9d6577ced10dc30bea6f5d803a`。

## P. Frame performance / preparation and reupload

表内FPS是process-loop中位间隔换算；静态帧保持显示，并无每秒60次地图渲染。旧版RMB无操作。全部采样按要求60/90s idle与30s动作；不掩盖单次max：

| stage | version | median loop FPS | median ms | p95 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- |
| person_idle | before | 60.01 | 16.66 | 16.86 | 16.96 | 17.27 |
| person_idle | after | 59.90 | 16.69 | 17.71 | 18.17 | 21.91 |
| world_open_timeline | before | 60.01 | 16.66 | 16.84 | 16.96 | 165.98 |
| world_open_timeline | after | 59.91 | 16.69 | 17.70 | 18.19 | 188.20 |
| far_idle | before | 60.01 | 16.66 | 16.83 | 16.92 | 17.57 |
| far_idle | after | 59.97 | 16.68 | 17.66 | 18.21 | 19.94 |
| mid_idle | before | 60.01 | 16.66 | 16.85 | 16.96 | 17.33 |
| mid_idle | after | 59.88 | 16.70 | 17.67 | 18.15 | 19.09 |
| near_idle | before | 60.01 | 16.66 | 16.85 | 16.95 | 17.43 |
| near_idle | after | 59.97 | 16.68 | 17.76 | 18.19 | 19.20 |
| local_idle | before | 60.01 | 16.66 | 16.84 | 16.92 | 23.74 |
| local_idle | after | 59.92 | 16.69 | 17.71 | 18.21 | 23.16 |
| world_pan | before | 60.01 | 16.66 | 16.86 | 17.07 | 22.63 |
| world_pan | after | 60.06 | 16.65 | 20.55 | 27.31 | 33.94 |
| world_zoom | before | 60.00 | 16.67 | 17.65 | 22.67 | 30.99 |
| world_zoom | after | 60.01 | 16.66 | 18.18 | 21.59 | 32.05 |
| world_right | before | 60.00 | 16.67 | 16.79 | 16.88 | 17.37 |
| world_right | after | 60.02 | 16.66 | 18.04 | 19.64 | 30.24 |
| region_pan | before | 60.00 | 16.67 | 17.66 | 22.94 | 38.94 |
| region_pan | after | 59.94 | 16.68 | 19.05 | 23.69 | 41.22 |
| region_zoom | before | 60.00 | 16.67 | 17.02 | 20.95 | 26.50 |
| region_zoom | after | 59.94 | 16.68 | 19.33 | 23.51 | 29.52 |
| region_right | before | 60.00 | 16.67 | 16.87 | 16.96 | 17.49 |
| region_right | after | 59.91 | 16.69 | 18.30 | 19.85 | 27.87 |
| local_pan | before | 60.01 | 16.66 | 16.88 | 19.16 | 31.05 |
| local_pan | after | 60.02 | 16.66 | 18.02 | 20.70 | 29.25 |
| local_zoom | before | 60.01 | 16.66 | 16.88 | 17.59 | 22.36 |
| local_zoom | after | 59.96 | 16.68 | 20.46 | 26.88 | 34.72 |

| version | policy | m/px | ready latency ms | prepare p95 frame ms | prepare max frame ms | new GPU enqueue ms | resident | LOCAL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before | all (R1) | 4500.0 | 3073.11 | 18.87 | 24.86 | 458.05 | R1 all | False |
| before | all (R1) | 2000.0 | 13.14 | 13.12 | 13.12 | 0.00 | R1 all | False |
| before | all (R1) | 1200.0 | 10.12 | 10.10 | 10.10 | 0.00 | R1 all | False |
| before | all (R1) | 700.0 | 10.66 | 10.64 | 10.64 | 0.00 | R1 all | False |
| before | all (R1) | 350.0 | 9.07 | 9.06 | 9.06 | 0.00 | R1 all | False |
| before | all (R1) | 188.0 | 11.90 | 11.89 | 11.89 | 0.00 | R1 all | True |
| before | all (R1) | 75.0 | 10.68 | 10.67 | 10.67 | 0.00 | R1 all | True |
| before | all (R1) | 1200.0 | 8.90 | 8.89 | 8.89 | 0.00 | R1 all | False |
| before | all (R1) | 100.0 | 10.15 | 10.12 | 10.12 | 0.00 | R1 all | True |
| after | active | 4500.0 | 1323.75 | 18.09 | 23.59 | 42.01 | ['coarse'] | False |
| after | active | 2000.0 | 24.96 | 24.95 | 24.95 | 0.00 | ['coarse'] | False |
| after | active | 1200.0 | 607.53 | 17.81 | 24.40 | 103.98 | ['medium'] | False |
| after | active | 700.0 | 15.40 | 15.38 | 15.38 | 0.00 | ['medium'] | False |
| after | active | 350.0 | 13.84 | 13.83 | 13.83 | 0.00 | ['medium'] | False |
| after | active | 188.0 | 1254.82 | 18.11 | 20.81 | 256.19 | ['local'] | True |
| after | active | 75.0 | 12.49 | 12.48 | 12.48 | 0.00 | ['local'] | True |
| after | active | 1200.0 | 606.25 | 20.11 | 30.42 | 162.21 | ['medium'] | False |
| after | active | 100.0 | 1265.38 | 18.25 | 25.62 | 271.77 | ['local'] | True |
| after | all | 4500.0 | 2088.99 | 21.18 | 23.09 | 474.99 | ['coarse', 'medium', 'local'] | False |
| after | all | 1200.0 | 11.09 | 11.07 | 11.07 | 0.00 | ['coarse', 'medium', 'local'] | False |
| after | all | 188.0 | 14.01 | 13.99 | 13.99 | 0.00 | ['coarse', 'medium', 'local'] | True |
| after | all | 4500.0 | 12.20 | 12.19 | 12.19 | 0.00 | ['coarse', 'medium', 'local'] | False |
| after | adjacent | 4500.0 | 15.27 | 15.27 | 15.27 | 0.00 | ['coarse'] | False |
| after | adjacent | 1200.0 | 569.88 | 17.85 | 19.60 | 101.51 | ['coarse', 'medium'] | False |
| after | adjacent | 188.0 | 1306.00 | 24.45 | 26.38 | 294.88 | ['medium', 'local'] | True |
| after | adjacent | 4500.0 | 272.43 | 41.62 | 41.62 | 62.64 | ['coarse'] | False |
| after | active | 4500.0 | 9.24 | 9.23 | 9.23 | 0.00 | ['coarse'] | False |
| after | active | 1200.0 | 571.61 | 17.98 | 21.21 | 110.39 | ['medium'] | False |
| after | active | 188.0 | 1253.62 | 17.77 | 20.85 | 216.27 | ['local'] | True |
| after | active | 4500.0 | 210.50 | 25.21 | 25.21 | 37.01 | ['coarse'] | False |
| after | active | 350.0 | 570.29 | 18.64 | 20.39 | 102.12 | ['medium'] | False |
| after | active | 188.0 | 1272.65 | 19.19 | 22.48 | 305.57 | ['local'] | True |

## Q. Deferred geometry fidelity

近距离粗政治coastline/territory geometry仍DEFER。未tessellate/subdivide/smooth伪造历史精度。physical coastline独立，不能替换political owner。没有新增terrain/relief。

## R. Admin status

Province尚未实现：没有Province state、France1900 admin polygons、editor或occupation integration；现有AdministrativeBoundaryCache仅mutable membership revision/affected-region dirty seam。Province未来是mutable行政grouping，不是永久polygon；sovereignty/control/admin分离，occupation不能以Province为原子。无per-frame union、无50/25/5km实体grid。ADMIN_BOUNDARY_DATA_GAP继续，不用modern admin1填空。

## S. World facts / save

615项baseline manifest比较：生产变化仅8个Presentation/controller/shader脚本，加project低占用设置；data/scenes/assets/simulation/persistence/MainShell导航均未改。53 settlements、11 rail parts/9corridors、1387 river parts/9rivers、657 coast parts、0admin/0road未变。两次完整probe save_unchanged=True/True，schema=formal_world_simulation_v14，无第二World、经济/军事事实或持久grid。canonical bytes逐字节相等。

## T. Validation

最终统一验证exit0、错误日志扫描通过；十年原限制保持195.400417s<240s，40/0。昨天402.987s那次失败保留，不通过放宽门槛变绿。最终Godot import和Windows产品导出exit0；仅既有0.001a非数字版本警告。正式数据/模拟hash保持。checks：

| check | assertions | result |
| --- | --- | --- |
| Formal personal economy and wages | 104 | PASS |
| Formal livelihood player journeys | 39 | PASS |
| Formal application and main/menu | 33 | PASS |
| Formal Person integration | 60 | PASS |
| Formal Spatial integration | 35 | PASS |
| Formal exact persistence | 32 | PASS |
| Formal Population production integration | 476 | PASS |
| Presentation content boundary | 60 | PASS |
| Formal map rendering regression | 745 | PASS |
| Formal map scale transition | 1280 | PASS |
| Formal map Local foundation | 68 | PASS |
| Paris Local Content R1 | 6537 | PASS |
| Map visual scale utilization R1 | 13577 | PASS |
| Map resource efficiency R2 | 47 | PASS |
| Historical provenance foundation | 48 | PASS |
| Runtime political identity foundation | 1186 | PASS |
| Formal economy 30-day and one-year golden | 6 | PASS |
| Formal economic boundary closure | 542 | PASS |
| Formal market identity foundation | 649 | PASS |
| Organization state | 137 | PASS |
| Formal organization composition | 99 | PASS |
| Current world domain convergence | 32 | PASS |
| Formal Windows export resource contract | 374 | PASS |
| Formal world integration | 67 | PASS |
| Formal world ten-year balance | 40 | PASS |
| Historical world economy data | 18 | PASS |

## U. Visual evidence

以下为实际Windows Release render capture，1280×720，Labels ON，1900-01-01，Political；并非生成示意图。旧/新same camera centre与scale。全序列：

另外通过computer-use skill实际操作正式产品菜单：建立1900世界→Person→World→左拖/原生滚轮→Far3854→Mid2123/1169→Near644/355→Local195→Local左拖→RMB单击无跳角→缩至238仍Local→291恢复Region。日期、Political、Labels ON保持，native-product-errors.log为空；结束正常关闭本次测试实例，未按Save。原生右拖的OS按钮注入仍受工具限制，30s旋转用真实产品InputEvent handler测试，已在M明确。原生图含Windows标题栏、游戏client1280×720：[Far](../../local-artifacts/map-resource-r2/native-far.png)、[Mid](../../local-artifacts/map-resource-r2/native-mid.png)、[Local](../../local-artifacts/map-resource-r2/native-local.png)、[round trip](../../local-artifacts/map-resource-r2/native-roundtrip.png)。

| scale | before | after |
| --- | --- | --- |
| world | [before](../../local-artifacts/map-resource-r2/baseline-final/world.png) | [after](../../local-artifacts/map-resource-r2/after-final/world.png) |
| far | [before](../../local-artifacts/map-resource-r2/baseline-final/far.png) | [after](../../local-artifacts/map-resource-r2/after-final/far.png) |
| mid_early | [before](../../local-artifacts/map-resource-r2/baseline-final/mid_early.png) | [after](../../local-artifacts/map-resource-r2/after-final/mid_early.png) |
| mid | [before](../../local-artifacts/map-resource-r2/baseline-final/mid.png) | [after](../../local-artifacts/map-resource-r2/after-final/mid.png) |
| mid_near | [before](../../local-artifacts/map-resource-r2/baseline-final/mid_near.png) | [after](../../local-artifacts/map-resource-r2/after-final/mid_near.png) |
| near | [before](../../local-artifacts/map-resource-r2/baseline-final/near.png) | [after](../../local-artifacts/map-resource-r2/after-final/near.png) |
| handoff | [before](../../local-artifacts/map-resource-r2/baseline-final/handoff.png) | [after](../../local-artifacts/map-resource-r2/after-final/handoff.png) |
| local | [before](../../local-artifacts/map-resource-r2/baseline-final/local.png) | [after](../../local-artifacts/map-resource-r2/after-final/local.png) |

铁路同视角候选：[0](../../local-artifacts/map-resource-r2/comparisons/rail_style_0.png) / [1](../../local-artifacts/map-resource-r2/comparisons/rail_style_1.png) / [2](../../local-artifacts/map-resource-r2/comparisons/rail_style_2.png)。此前after-final样式截图由于pan末段未归零产生镜头偏移，保留诊断，正式对照使用补测reset后的三图与30s动作。[Beijing](../../local-artifacts/map-resource-r2/after-final/beijing.png)、[NewYork](../../local-artifacts/map-resource-r2/after-final/new_york.png)。原始[before](../../local-artifacts/map-resource-r2/baseline-final/results.json)、[after](../../local-artifacts/map-resource-r2/after-final/results.json)、[supplement](../../local-artifacts/map-resource-r2/comparisons/results.json)、system.jsonl、[CPU cache](../../local-artifacts/map-resource-r2/cpu-cache.json)、[package audit](../../local-artifacts/map-resource-r2/package-audit.json)、[validation log](../../local-artifacts/map-resource-r2/validation-resumed.log)均保留。

## V. Next recommendation

本轮停止继续renderer/LOD基础施工；下一步单独决定Administrative Region R1或Economy Algorithm Research。本轮不自动开始。保留单次冷fixture289ms作为性能限制，不承诺所有未来跳跃路径零spike。真数据缺口仍是近尺度political source fidelity、历史admin、现有有限town密度；不是靠错误省区或加runtime geometry填满。
