# WWO Global Physical Relief R1

RESULT: **NOT_PASS — Unified 十年模拟时间预算未通过**

本轮实现和数据已进入正式Windows Release；未将未全绿的验收标成PASS。地图资源与视觉结果见下表。

## A. SOURCE

采用 NOAA NCEI ETOPO 2022 v1 的60s ice-surface全球网格，WGS84 / EGM2008米；覆盖-180..180、-90..90。CC0-1.0，含商业派生和分发。source TIF 465,969,062 bytes，SHA256 `9d27d4b8ea8e76977e2988bca667d7c8fa68b927355feffcddd6b4875a7fd08e`。完整版本、检索时间、原PDF、许可、datum、极区、nodata、海洋处理见 [Content metadata](../../data/presentation/global_physical_relief.json) 和 [source review](../data/global-physical-relief-r1.md)。

## B. HISTORICAL / PHYSICAL STATUS

`PHYSICAL_REFERENCE`；大尺度山系、台地、平原可作百年游戏背景。不是1900精确地表、冰盖、岸线、城市、森林、耕地、道路、人口或政治归属证据。负高程压平；低于海平面的陆地凹陷也会丢失。现代大型湖泊与工程变化不作历史重建。

## C. PREPROCESSING

原始Float32 GeoTIFF→检查栅格定位→面积平均4096×2048→负值归零→经度周期Gaussian .65像元→按米间距求梯度→固定西北/东北双光照（视觉坡度6倍）+log-height→RG8派生图→同源面积平均1024×512。两档极点行经度一致。离线耗时9.000s，runtime无DEM读取、坡度计算或hillshade生成。工具 [build_global_relief.py](../../tools/map/build_global_relief.py)。

## D. RUNTIME REPRESENTATION

比较A低分辨率单图、B两档全球图、C有限地理分片，采用B。A仅1MiB但Region山系过糊；C可能减少同精度驻留，但本轮未实施或宣称其功耗已测。B低档1MiB，高档16MiB，当前需要时共享两个纹理，上限17MiB；没有科研级全球图、无限cache或GIS框架。纹理通过现有Content loader / provenance gate准入并在线程中验证字节hash、解码；Presentation只接准备结果。

## E. WORLD

现有政治面fragment按实际球面地理坐标采样；现有固定前半球底层补无政治面的粗正高程背景。固定球体geometry不变，仅修正其材质剔除方式并以模型位置避开背面法线翻转。国家owner不由背景决定。两条flag/no-flag材质路径在世界创建时一次性预热，不加载relief高档或DEM。

## F. REGION

现有AEQD逆投影在GPU按每个fragment采同一全球纹理；已有背景rect承载无政治面的物理背景。pan/zoom不重新投影CPU地理面、不parse、不生成地形、不建mesh。World接近8500m/px预备高档，11000m/px退出释放，camera变化不产生region tile cache。纹理只在residency/source准备变化时绑定；尺度权重每次draw计算一次，并在变化后批量更新，不随每个owner重复计算。

## G. LOCAL

巴黎使用相同粗physical reference。纬向约9.77km，不能宣称25–200m地形。Local越近连续减弱权重，保留线性过滤的模糊底图；无建筑、坡面、collision、terrain modifier。

## H. SCALE BLEND

Political权重：World远景约0.10，Far4500m/px约0.39，Mid1200约0.60，Near350约0.37，Local188约0.22，Close75约0.07。这是对有符号形态的乘法调制，非实际地形振幅。flag_weight和political_weight原映射不变。detail mix在10000→4000m/px连续增加；Economy仅保留Political relief权重的20%。

## I. PERFORMANCE

同机Windows Release，1280×720、Compatibility、VSync、60 FPS cap。before为本轮开始前R2快照，after复制同一正式app，测量用入口scene；模拟快照前后比较。每个正式idle至少60s，pan/zoom30s。OS读数经20逻辑核归一；GPU为该进程最高engine读数，board GPU/W是整卡，不是进程独占。其它用户应用未关闭，不声称全程无遮挡独占前台。记录原始system.jsonl；稳态丢弃最初5s和尾部边缘，完整frame max仍保留。loop FPS并非60个新静止地图frame。

| case | CPU % before → after | process GPU % | board GPU % | board W | p50 ms | p95 ms | p99 ms | max ms |
|---|---|---|---|---|---|---|---|---|
| person_idle | 0.08 → 0.09 | 0.00 → 0.00 | 0.00 → 0.00 | 3.38 → 3.38 | 16.66 → 16.67 | 17.75 → 17.69 | 18.17 → 18.16 | 19.22 → 22.00 |
| world_open_timeline | 0.07 → 0.12 | 0.00 → 0.00 | 0.00 → 0.00 | 3.40 → 3.38 | 16.66 → 16.64 | 17.79 → 17.75 | 18.17 → 18.23 | 160.10 → 41.27 |
| far_idle | 0.07 → 0.12 | 0.00 → 0.00 | 0.00 → 0.00 | 3.40 → 3.41 | 16.67 → 16.65 | 17.72 → 17.73 | 18.18 → 18.16 | 18.84 → 19.36 |
| far_pan | 2.79 → 3.36 | 19.65 → 20.31 | 37.00 → 37.50 | 7.62 → 7.83 | 16.65 → 16.65 | 17.81 → 18.77 | 18.28 → 24.25 | 30.84 → 30.58 |
| mid_idle | 0.14 → 0.11 | 0.00 → 0.00 | 0.00 → 0.00 | 3.44 → 3.41 | 16.68 → 16.66 | 17.82 → 17.73 | 18.20 → 18.23 | 42.38 → 19.26 |
| mid_pan | 3.70 → 2.66 | 20.47 → 21.05 | 39.00 → 39.00 | 7.79 → 7.83 | 16.68 → 16.63 | 18.13 → 17.94 | 19.73 → 21.24 | 22.67 → 30.15 |
| near_idle | 0.18 → 0.09 | 0.00 → 0.00 | 0.00 → 0.00 | 3.45 → 3.40 | 16.69 → 16.70 | 17.88 → 17.80 | 18.60 → 18.19 | 36.42 → 20.05 |
| local_idle | 0.16 → 0.11 | 0.00 → 0.00 | 0.00 → 0.00 | 3.43 → 3.40 | 16.71 → 16.67 | 17.75 → 17.79 | 18.20 → 18.25 | 18.75 → 37.84 |
| world_pan | 3.15 → 2.31 | 18.01 → 19.81 | 36.00 → 39.00 | 7.59 → 7.75 | 16.67 → 16.66 | 17.78 → 17.68 | 18.39 → 18.13 | 24.70 → 18.74 |
| world_zoom | 3.45 → 2.23 | 17.30 → 20.89 | 36.00 → 40.00 | 7.61 → 7.81 | 16.69 → 16.63 | 17.96 → 17.70 | 20.30 → 18.10 | 22.42 → 20.38 |
| world_right | 3.52 → 2.40 | 19.44 → 20.49 | 36.50 → 39.00 | 7.62 → 7.80 | 16.69 → 16.65 | 18.23 → 17.66 | 21.99 → 18.15 | 29.30 → 24.88 |
| region_pan | 3.96 → 3.30 | 19.91 → 21.08 | 38.50 → 39.00 | 7.77 → 7.75 | 16.70 → 16.65 | 19.34 → 17.68 | 22.50 → 18.06 | 30.62 → 19.02 |
| region_zoom | 4.23 → 3.30 | 19.95 → 21.16 | 37.00 → 39.00 | 7.72 → 7.75 | 16.70 → 16.64 | 19.65 → 17.95 | 22.09 → 21.44 | 32.25 → 29.43 |
| region_right | 4.21 → 3.11 | 19.63 → 20.92 | 39.00 → 38.00 | 7.76 → 7.79 | 16.71 → 16.67 | 19.74 → 17.66 | 22.15 → 18.17 | 27.68 → 22.27 |
| local_pan | 3.53 → 2.59 | 20.12 → 22.37 | 38.00 → 40.00 | 7.83 → 7.83 | 16.69 → 16.63 | 18.08 → 17.78 | 19.09 → 18.21 | 25.37 → 21.77 |
| local_zoom | 3.60 → 2.76 | 21.82 → 21.57 | 40.00 → 39.00 | 7.90 → 7.86 | 16.69 → 16.68 | 18.07 → 17.70 | 19.70 → 18.26 | 32.10 → 25.07 |

## J. IDLE

| idle | new rendered frames | map redraw | view update | CPU geography projection |
|---|---:|---:|---:|---:|
| person_idle | 0 | 0 | 0 | 0 |
| world_open_timeline | 0 | 0 | 0 | 0 |
| far_idle | 0 | 0 | 0 | 0 |
| mid_idle | 0 | 0 | 0 | 0 |
| near_idle | 0 | 0 | 0 | 0 |
| local_idle | 0 | 0 | 0 | 0 |

外部鼠标hover、focus和强制截图会合法刷新一次；需与view更新、几何投影及relief自身活动区分。静止判定同时依据实际GPU=0、源码无TIME/轮询、renderer停止_process和回归中的零重绘。最后一次draw-call值是已提交帧的历史值，不代表静止仍提交这些调用。

## K. MEMORY

| case | WS MiB before → after | private MiB | Godot video MiB | texture MiB | draw calls |
|---|---|---|---|---|---|
| person_idle | 514.31 → 486.03 | 725.00 → 698.11 | 125.66 → 125.66 | 104.66 → 104.66 | 64.00 → 64.00 |
| world_open_timeline | 532.82 → 500.52 | 735.99 → 718.94 | 131.33 → 132.67 | 110.29 → 111.62 | 265.00 → 265.00 |
| far_idle | 580.45 → 551.91 | 781.26 → 787.64 | 132.49 → 159.22 | 110.71 → 133.37 | 115.00 → 115.00 |
| far_pan | 582.93 → 553.93 | 783.63 → 789.57 | 131.97 → 158.70 | 110.56 → 133.22 | 292.50 → 292.50 |
| mid_idle | 584.55 → 556.49 | 789.16 → 797.16 | 134.37 → 161.10 | 111.26 → 133.93 | 106.00 → 106.00 |
| mid_pan | 585.92 → 556.63 | 789.29 → 797.27 | 134.37 → 161.10 | 111.26 → 133.93 | 379.00 → 378.00 |
| near_idle | 585.93 → 556.37 | 789.22 → 797.24 | 134.34 → 161.07 | 111.26 → 133.93 | 347.00 → 84.00 |
| local_idle | 591.90 → 561.68 | 803.55 → 810.99 | 138.05 → 164.78 | 112.33 → 135.00 | 66.00 → 66.00 |
| world_pan | 589.03 → 559.24 | 788.95 → 794.12 | 131.58 → 136.98 | 110.54 → 111.87 | 328.00 → 324.50 |
| world_zoom | 589.04 → 560.15 | 788.96 → 795.11 | 131.58 → 136.98 | 110.54 → 111.87 | 341.00 → 318.50 |
| world_right | 589.10 → 560.45 | 789.00 → 795.14 | 131.58 → 136.98 | 110.54 → 111.87 | 351.00 → 345.00 |
| region_pan | 591.06 → 565.78 | 795.13 → 801.46 | 134.50 → 161.23 | 111.39 → 134.05 | 379.00 → 378.00 |
| region_zoom | 590.97 → 565.72 | 795.10 → 801.46 | 134.50 → 161.23 | 111.39 → 134.05 | 378.00 → 382.00 |
| region_right | 590.99 → 566.62 | 795.10 → 802.46 | 134.50 → 161.23 | 111.39 → 134.05 | 385.00 → 384.50 |
| local_pan | 598.46 → 571.88 | 812.76 → 817.02 | 140.21 → 164.91 | 112.45 → 135.12 | 347.50 → 347.50 |
| local_zoom | 598.46 → 572.84 | 812.76 → 818.00 | 140.21 → 164.91 | 112.45 → 135.12 | 348.00 → 348.00 |

纹理payload World1MiB / Region和Local17MiB；CPU解码临时图在创建texture后释放，字节buffer与源catalog只在加载时使用，保留两项detached asset definitions。driver/engine实际video和进程WS/private以上表为准，不能把payload称作完整VRAM。Godot Release的tracked RAM monitor=0不可用。隐藏canvas和shader参数cache也清纹理引用；隐藏地图后纹理owner归零。

| case | process dedicated GPU MiB before → after | shared GPU MiB before → after |
|---|---:|---:|
| person_idle | 174.82 → 164.30 | 57.21 → 51.19 |
| world_open_timeline | 175.27 → 176.25 | 72.25 → 64.23 |
| far_idle | 172.11 → 189.23 | 59.77 → 56.59 |
| mid_idle | 176.11 → 193.23 | 59.64 → 56.46 |
| local_idle | 184.11 → 201.23 | 59.64 → 56.46 |
| world_pan | 172.24 → 188.11 | 63.64 → 60.46 |
| region_pan | 176.24 → 190.12 | 63.64 → 64.46 |
| local_pan | 184.25 → 198.12 | 65.64 → 64.46 |

Windows GPU Process Memory为驱动进程统计，包含共享与driver分配；与Godot video monitor口径不同，两者均保留。

## L. GLOBAL TRAVEL

欧洲→东亚→北美→南美→欧洲等13地点，重复三轮，含日期线和两极。用同一正式camera/renderer，不创建新World。以下是每轮实际资源：

```json
[
  {
    "lap": 0,
    "max_payload": 17825792,
    "median_video": 165951041.0,
    "median_ws": 584777728.0,
    "max_source_admissions": 1,
    "max_region_loads": 2
  },
  {
    "lap": 1,
    "max_payload": 17825792,
    "median_video": 165951041.0,
    "median_ws": 584773632,
    "max_source_admissions": 1,
    "max_region_loads": 2
  },
  {
    "lap": 2,
    "max_payload": 17825792,
    "median_video": 165951041.0,
    "median_ws": 586436608,
    "max_source_admissions": 1,
    "max_region_loads": 2
  }
]
```

细档没有按地区累计的geometry/texture；固定两个资源；load诊断history每级最多4项，不让统计本身无上限增长。三轮GPU/video中位数完全相同；WS中位数557.69、557.68、559.27MiB，约1.59MiB波动，无逐轮纹理或几何累计。

## M. RELEASE

正式产品 [wwo-global-physical-relief-r1.exe](../../builds/windows/wwo-global-physical-relief-r1.exe) 172,184,200 bytes；R2 169,585,456；delta **2,598,744 bytes**。PCK检查两份bin与metadata和原Paris JSON逐字节一致；raw DEM、PDF/archive、docs、tools、tests与本轮隔离工程排除。[Package audit](../../local-artifacts/physical-relief-r1/package-audit.json)。

## N. VISUAL

真实Windows Release render capture，1900-01-01，Labels ON，不是生成示意图。完整系列：

| 地区 / 尺度 | 截图 |
|---|---|
| Alps | [图](../../local-artifacts/physical-relief-r1/after/alps.png) |
| Pyrenees | [图](../../local-artifacts/physical-relief-r1/after/pyrenees.png) |
| Scandinavia | [图](../../local-artifacts/physical-relief-r1/after/scandinavia.png) |
| Caucasus | [图](../../local-artifacts/physical-relief-r1/after/caucasus.png) |
| Himalaya / Tibet | [图](../../local-artifacts/physical-relief-r1/after/himalaya.png) |
| Japan | [图](../../local-artifacts/physical-relief-r1/after/japan.png) |
| Rockies | [图](../../local-artifacts/physical-relief-r1/after/rockies.png) |
| Andes | [图](../../local-artifacts/physical-relief-r1/after/andes.png) |
| Great Plains | [图](../../local-artifacts/physical-relief-r1/after/great_plains.png) |
| Sahara | [图](../../local-artifacts/physical-relief-r1/after/sahara.png) |
| World / Far / Mid / Near / Local | [World](../../local-artifacts/physical-relief-r1/after/world.png)、[Far](../../local-artifacts/physical-relief-r1/after/far.png)、[Mid](../../local-artifacts/physical-relief-r1/after/mid.png)、[Near](../../local-artifacts/physical-relief-r1/after/near.png)、[Local](../../local-artifacts/physical-relief-r1/after/local.png) |

## O. DATE LINE / POLES

经度周期采样，纬度钳制每级最后有效行；pole经度显式置0避免atan(0,0)。Source下采样本身的两极行也经度一致。World用固定mesh位置，避免背面normal把南北翻转。[Date line](../../local-artifacts/physical-relief-r1/after/date_line.png)、[North](../../local-artifacts/physical-relief-r1/after/north_pole.png)、[South](../../local-artifacts/physical-relief-r1/after/south_pole.png)。已有CShapes在±180的细垂直outline存在于before截图，不来自relief；本轮不伪造更细政治边界。物理纹理无新增接缝。

## P. INTERACTION

Political边界、France/Germany/Austria色、蓝河、rail style2、settlements/labels继续在底图上清晰显示；Economy aggregate颜色主导，没有节点或数值映射变化。Native旅程与额外mode截图另列验收附件。

## Q. WORLD FACTS

无terrain state / simulation / 3D terrain；固定globe的材质变化不是height mesh。无Economy/Military效果，无sovereignty/controller/administrative membership改变，无第二World或第二Local shard。Province仍是未来可变行政分组，不由DEM、polygon或50/25/5km cell定义；admin gap不被现代资料填充。

## R. SAVE

`formal_world_simulation_v14`，全量before/after snapshot equality=True。Population、Personal Economy、Economy、Persistence及世界golden在统一验证中核对。

## S. VALIDATION / LOAD COST

导入、新relief检查、Rendering / Scale Transition / Local Foundation / Paris Content / Presentation Boundary / Unified / Windows Release与native validation以日志为准。第一轮被Presentation直接读来源的架构测试拦下，已改为Content callback，未削弱测试。

| level / load | read ms | admission ms | hash ms | decode ms | CPU format ms | texture creation / GPU enqueue ms | first visible ms |
|---|---|---|---|---|---|---|---|
| world | 0.34 | 1.42 | 0.91 | 6.66 | 0.64 | 0.42 | 54.48 |
| region | 1.84 | 0.01 | 8.64 | 79.47 | 8.88 | 3.13 | 121.92 |
| region | 1.22 | 0.01 | 8.54 | 82.66 | 9.77 | 3.37 | 128.52 |
| region | 1.24 | 0.01 | 9.09 | 85.44 | 10.68 | 3.18 | 128.08 |

首轮未预热诊断出现1155.914ms cold GL compile；后续中间版本785.64ms也保留。最终世界创建阶段只用2byte neutral texture与已有mesh预热World/Region及flag/no-flag程序；不是加载完整relief。GPU enqueue是CPU调用时长，不能等同GPU执行完成；first-visible来自post-draw callback。最终冷路径证据单独核对，不把预热之前长帧删除。



### 最终验证结果

| check | checks | failures | exit |
|---|---:|---:|---:|
| Formal personal economy and wages | 104 | 0 | 0 |
| Formal Person integration | 60 | 0 | 0 |
| Formal Spatial integration | 35 | 0 | 0 |
| Formal exact persistence | 32 | 0 | 0 |
| Formal Population production integration | 476 | 0 | 0 |
| Presentation content boundary | 60 | 0 | 0 |
| Formal map rendering regression | 745 | 0 | 0 |
| Formal map scale transition | 1280 | 0 | 0 |
| Formal map Local foundation | 68 | 0 | 0 |
| Paris Local Content R1 | 6537 | 0 | 0 |
| Map visual scale utilization R1 | 13577 | 0 | 0 |
| Map resource efficiency R2 | 47 | 0 | 0 |
| Global physical relief R1 | 1191 | 0 | 0 |
| Formal economy 30-day and one-year golden | 6 | 0 | 0 |
| Formal world integration | 67 | 0 | 0 |
| Historical world economy data (remaining test) | 18 | 0 | 0 |
| Unified ten-year balance | 40 | 1 (elapsed budget) | 1 |
| R2 paired ten-year balance | 40 | 1 (elapsed budget) | 1 |
| Remaining fresh-process probes / headless startup | 8 fresh processes + startup | 0 | 0 |
| Windows Release export / PCK source exclusion | verified | 0 | 0 |

最终 [Unified log](../../local-artifacts/physical-relief-r1/validation-cached-final.log) exit=1；十年模拟 276.809s，要求<240s。此前同轮曾记录195.037s通过，也记录244.164s、286.627s超时；最终耗时失败不能用早期通过覆盖。冻结R2快照使用完全相同的测试和240s要求：249.624s，exit=1。两版除elapsed以外的全部metrics精确等价=True，十年末save=699,092 bytes。未更改模拟代码、限制或跳过失败来声称Unified通过。

Unified中断后的历史世界资料测试、Political/Market/Economic/World四组各两次fresh-process hash及headless startup，按原runner检查逻辑单独补跑，[remaining log](../../local-artifacts/physical-relief-r1/validation-remaining.log) exit=0；这不豁免Unified的失败项。

本轮的 [scope audit](../../local-artifacts/physical-relief-r1/scope-audit.json) 确认原有data/assets/scenes逐字节不变，只有8个既有runtime/config文件变化，隔离测量工程runtime与产品相同。没有降低旧测试标准。导出仅保留既有Windows numeric version `0.001a`警告；正式Release/probe没有解析、脚本或资源错误。

### Native / mode 附件

正式产品菜单→创建1900世界→Person→World→Region FAR/MID/NEAR已经由Windows输入操作验证。[World](../../local-artifacts/physical-relief-r1/native/world.png)、[handoff](../../local-artifacts/physical-relief-r1/native/world-region.png)、[Far](../../local-artifacts/physical-relief-r1/native/region-far.png)、[Mid](../../local-artifacts/physical-relief-r1/native/region-mid.png)。途中外部手动输入使初次Region锚点位于Paris之外；有限chart限制没有被绕过。

同一正式app的隔离Release仅由测量入口准备Paris Region 238m/px；随后实际Windows鼠标完成238→195 Local、pan、238保持Local、290.36恢复Region。全程place:paris选择、Labels ON、Political、1900-01-01保持，完整save equality=True。[Before](../../local-artifacts/physical-relief-r1/native-local/region-238.png)、[Local](../../local-artifacts/physical-relief-r1/native-local/local-195.png)、[restored](../../local-artifacts/physical-relief-r1/native-local/region-restored.png)。部分系统截图被用户语音输入浮窗局部遮挡；主要产品render captures不含该浮窗。

额外正式mode handler截图：[Political](../../local-artifacts/physical-relief-r1/after/paris_mid_political.png)、[Fulfillment](../../local-artifacts/physical-relief-r1/after/paris_mid_fulfillment.png)、[Shortage](../../local-artifacts/physical-relief-r1/after/paris_mid_shortage.png)。World补充：[Alps](../../local-artifacts/physical-relief-r1/after/world_alps.png)、[Rockies](../../local-artifacts/physical-relief-r1/after/world_rockies.png)、[Andes](../../local-artifacts/physical-relief-r1/after/world_andes.png)、[North pole](../../local-artifacts/physical-relief-r1/after/world_north_pole.png)、[South pole](../../local-artifacts/physical-relief-r1/after/world_south_pole.png)、[date line](../../local-artifacts/physical-relief-r1/after/world_date_line.png)。

### 成本和测量限制

最终第一次World打开的最大frame=41.270ms，R2=160.103ms；包含完整首次准备，稳态另列。shader warmup=20.712ms，Region实际提交objects=3。此设备的GPU driver cache没有删除，不能宣称其它设备或完全冷driver-cache的相同成本。原中间版本的1.156s、0.786s cold-program帧以及precache完整测量中的World p95约24ms、首次最大607ms保留在开发证据中；最终加入有限预热和dirty-only共享uniform绑定后重新完整采样。

Person基准扣除后的进程WS差：World=-4.02MiB，Region MID=0.21MiB。单独进程WS受allocator/其它应用影响，绝不由负的未校正差值宣称零开销；GPU/video列为实际engine值，纹理payload是不同指标。OS dedicated/shared GPU逐样本保存在system.jsonl。完整基线和after使用相同分辨率、renderer、VSync/cap，不使用quick/no-cap或lower-fidelity结果作为验收。GUI输入隔离仅用于测量入口，未改变正式产品输入或任何权威规则。

## T. REMAINING LIMITS

约9.8km粗physical reference，不包含Local精细地形、1900 land use/ice/coast/工程。以下缺口未改变：admin geometry、全球细政治/岸线source、全球river/town密度、原Paris铁路微对齐及道路。低于海面的陆地凹陷与当前湖面/湖底不能精确显示；polar slope夸张被约束，非真实高程测量。

## U. NEXT RECOMMENDATION

停止本轮地图实现。先单独解决或确认十年模拟CI耗时门槛，恢复统一验证全绿；然后再单独决定全球river/major settlement扩展或Administrative Region。本轮不自动扩展地图或修改模拟。
