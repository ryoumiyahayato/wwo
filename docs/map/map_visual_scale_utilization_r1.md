# WWO MAP VISUAL SCALE UTILIZATION R1

RESULT：**COMPLETED（本轮 Presentation 尺度利用与行政边界接口）**。

Paris 的资料质量状态仍为 **PARTIAL_DATA**；本轮没有提升铁路历史精度、补建行政资料或新建地区。2026-10-06，Godot 4.6.3 standard / Compatibility，Windows 本机 1280×720 / NVIDIA RTX 3050 Laptop GPU 验证。

## A. SCALE BANDS

仍然只有 WORLD / REGION / LOCAL 三个 runtime。以下 FAR / MID / NEAR / CLOSE 是基于 actual meters/pixel 的视觉策略，非新 World、非新 camera、非行政区或空间网格。

| 视觉级别 | 策略 | 新增、隐藏与权重 |
|---|---|---|
| WORLD | 既有世界尺度 | 国家边界、国家/洲际关系、旗帜政治身份；远端 flag weight=1 |
| World→Region | 既有交接阈值与 0.22 s crossfade | 同一个 scale blend；在约 6000 m/px 且 Paris 范围内开始预热 |
| REGION FAR | >2400 m/px | Paris 优先、已有正式主要城市点；岸线 <5000 m/px 渐显，主河流 <3500 m/px 渐显；主要铁路尚未显示 |
| REGION MID | 650～2400 m/px | 历史 major settlements；主要铁路从 1800 向 700 m/px 渐显；主要河流与 coastline 权重上升；没有 admin fallback |
| REGION NEAR | ≤650 m/px 且未进入 Local | medium geometry；550 m/px 开始增加部分历史交通/近郊节点；国家文字标签通常退出，政治面与边界继续存在 |
| LOCAL FAR | 保留 ≤200 m/px 入口、≥280 m/px 出口 | 同一 shard 的 local geometry，沿用 Near 已准入的城市节点；flag 为零，没有交接时突然整层打开 |
| LOCAL CLOSE | ≤115 m/px | 其余 secondary settlements，受 Labels 和碰撞限制的更密标签；本轮不绘制 50/25/5 km grid |

Local 约 300 km 半径、chart、screen anchor、bearing、selection、mode、date 的既有约束未改。Runtime Region 最细 150 m/px 的无数据地区也仍然属于 Region。

## B. FLAG BLEND

`political_surface.gdshader` 新增 `flag_weight` uniform。按 log(mpp) 上的 smoothstep 插值连接以下权重锚点：16000→1、8000→0.95、5500→0.65、3000→0.30、1200→0.08、300→0。WORLD 和 REGION 使用同一曲线，去掉旧的 `region_mode ? 0.35 : 1.0` 阶跃。

每次受控 camera / appearance 更新只设置 uniform；不生成 geometry。新测试以 25 m/px 步进检查单调、范围及连续性，Local 权重为零。资料卡中的小旗帜继续显示政治身份，缩放不会消除 dossier 的国籍信息。

## C. POLITICAL / PHYSICAL VISUAL WEIGHT

政治基础色与旗帜 modulation 分离。`political_weight` 从远端 1 连续减至近端 0.42，与静态 physical land palette 混合；物理线与城镇逐步成为更可读的前景。没有修改政治颜色的来源记录、polity ID、territory owner 或 controller。

岸线在 5000～2400、河流在 3500～1200、铁路在 1800～700 m/px 内连续改变 alpha。它们仍是 physical / bounded historical reference，不获得政治 ownership。Economy 模式不衰减其 aggregate 色标（political_weight=1），继续保持原 fulfillment / shortage 数值映射；空间参考线可以叠加，未制造经济流量。

## D. PARIS REGION CONTENT

唯一来源仍为 `data/local/paris_northern_france_1900.json`：53 个有历史依据的城镇、9 条主要铁路走廊的 11 个现代中心线参考 parts、1387 river parts、657 coastline parts。没有第二份 Region 资料、第二个 Local shard 或新增历史事实。

Content JSON 的 bytes 与 SHA-256 和上一轮完全相同：`ccbb2954cb57ea66e2f34c302581f726b30c2d9d6577ced10dc30bea6f5d803a`。各类资料的同时代证据、modern physical reference、bounded rail accuracy、1900 有效窗口与许可保持原样，见 [Paris 数据报告](D:/WWO/wwo/docs/map/paris_northern_france_local_spatial_r1.md)。

Scope / date gate 同时约束 Region 和 Local。Beijing / New York 即使同一进程已加载 Paris，visible Paris places 为 0，active Paris LOD 为空，不进入 Local。通用 flag / political fill fade 仍然正常。未 ready 时保留粗显示，无黑屏、弹窗或等待冻结。

## E. GEOMETRY LOD

在 canonical Content 通过现有 provenance gate 后，Presentation worker 用 chord-space Douglas–Peucker 准备三个有限缓存。local 直接复用 canonical points；coarse / medium 是显示简化，不是新测绘或新历史证据。每条派生边界保持同一个 feature ID 与 `local_spatial:<feature ID>` source fact ID，断开的 source parts 不补线。

| LOD | load-time 简化容差 | segments | PackedVector3 payload | GPU buffer payload |
|---|---:|---:|---:|---:|
| coarse | 600 m | 3,186 | 61,032 bytes | 1,325,360 bytes |
| local | 0 m | 20,941 | 276,276 bytes | 8,731,512 bytes |
| medium | 120 m | 9,147 | 134,604 bytes | 3,818,312 bytes |

>650 m/px 选 coarse，220～650 选 medium，≤220 选 local。完整缓存未准备好时使用已经 ready 的较粗档；正式 Local 仍等待全部必要准备完成。可忽略的闭合小环在 coarse / medium 可能消失，canonical feature / evidence 保留。原 source chunk 分界保留，不声称历史 junction graph 完成。

Camera movement 不调用 simplify、不重跑 gate、不重读文件、不重建 mesh。批次只有在准备期间创建，之后只更新 visibility / shader uniforms。不可见批次避免重复发 visibility 指令。三个 LOD 均静态驻留，数量有明确上限。

## F. LABEL LOD

使用原有历史 rank 与少量在本 shard 史料中明确的铁路/近郊节点名单：rank 0≤6000，rank 1≤2400，指定节点≤550，其余 secondary≤115 m/px。节点名单只是显示优先级，不创建人口、站点能力或新 gameplay 属性。

字体与 53 条 glyph source 在首次准备时一次建立；相机只更新 transform、可见性与小集合碰撞。Paris labels 优先，并把实际占用 rect 传给既有 Region labels，避免重复 Paris 名称及国家标签重叠。选中项保留，Labels OFF 隐藏未选中标签；source label list 不随每帧或每次 zoom 重建。

视野随放大变小，所以画面中的绝对城市数不必单调增长；递增的是可准入的等级与每单位屏幕/地理面积的信息密度。回归区分 eligibility 与 viewport coverage，未为满足城市数量断言扩大地理范围。

## G. TERRAIN / RELIEF

**TERRAIN_DATA_GAP**。本轮未准入可靠 DEM / hillshade，未制作地形图、3D terrain 或 camera-triggered terrain calculation。近端的 physical land palette 是中性背景色，不声称有地貌、海拔或土地利用依据。

## H. ADMINISTRATIVE DESIGN CONSTRAINT

明确：**Province 未来是 mutable administrative grouping，不是 immutable map polygon**。土地 unit 保留稳定身份；它分别引用 sovereign polity、controller 和当前 administrative membership。France 主权 / Germany 控制 / French département membership 可以同时存在，不能从 controller 自动改行政 identity。

新增的 Presentation-only `AdministrativeBoundaryCache` 仅提供受影响 IDs + membership revision 的失效/发布接口。其他区域缓存保留，旧 revision 的后台结果被拒绝，dissolved grouping 可发布空边界；camera、controller 变化不自动改变 membership。当前没有成员数据库、union 算法、编辑器或占领模拟。

Renderer 持有空缓存，不把既有政治 boundary batch 当作 Province。未来由独立权威行政服务给出 detached membership view，才计算相关边界并建立 static batch。50 / 25 / 5 km 聚合尺度与行政区无关，不定义 Province 边界，不进入 WorldState。

详细契约：[administrative membership Presentation contract](D:/WWO/wwo/docs/map/administrative_membership_presentation_contract.md)。现有历史 dossier 的按序名称 ID 不可直接升级为未来行政实体 ID。

## I. ADMIN DATA GAP

Paris historical administrative polygons 仍为 **0 / ADMIN_BOUNDARY_DATA_GAP**。未使用现代 Natural Earth admin1、ISO、polygon overlap 或 50 km grid 补造 1900 行政配置。空行政缓存不阻止物理内容显示。

## J. PERFORMANCE

同机、同一 profiler，六档各 idle / pan / zoom 90 帧，before / after 分别 1620 个 steady frame 样本。表为 p95 ms，VSync 约 60 FPS；是帧间隔，不是 GPU kernel timing。统一验证完成后单独运行 after profiler。

| scale | idle before→after | pan before→after | zoom before→after |
|---|---:|---:|---:|
| world | 16.735 → 16.876 | 16.721 → 16.763 | 16.688 → 16.798 |
| region_far | 16.722 → 16.732 | 16.681 → 16.677 | 16.687 → 16.687 |
| region_mid | 16.685 → 16.732 | 16.682 → 16.675 | 16.684 → 16.687 |
| region_near | 16.693 → 16.715 | 16.682 → 16.686 | 16.680 → 16.681 |
| local_far | 16.687 → 16.688 | 16.686 → 16.679 | 16.685 → 16.683 |
| local_close | 16.826 → 16.689 | 16.683 → 16.680 | 16.715 → 16.675 |

After 所有 steady samples ≥50 ms 为 0，最高帧间隔约 17.157 ms。没有测到持续 50 / 100 / 500 ms spike。首次准备每次主线程 step 最高 4.802 ms；该数是分批准备函数的耗时，不把它误称为整个首加载期间的 frame p95。只报告这台 Windows 机器的观察，不声称其他平台通过。

[before 原始性能](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/performance-before.json) · [after 原始性能](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/performance-after.json)。

## K. RAM / VRAM

Godot tracked static RAM：准备后 before=271,065,896 bytes，after=278,471,277 bytes，增加 **7,405,381 bytes / 7.062 MiB**。这是 engine tracked allocation，非 Windows 进程 RSS 或整个物理 RAM。

Godot render video memory counter：准备后 before=144,748,481，after=148,858,397 bytes，增加 **4,109,916 bytes / 3.920 MiB**。它是 renderer 资源计数，不包含整个驱动/系统占用。

单独按准备的 vertex/index/texture payload 计算：coarse+medium 额外 GPU buffers 合计 5,143,672 bytes / 4.905 MiB；多余 PackedVector3 payload 合计 195,636 bytes。local points 共享 canonical packed data，未复制三份历史 JSON。表中 GPU payload 与 engine counter 统计口径不同；不把任一个说成精确硬件显存读数。

Release before=169,568,416，after=169,578,560 bytes，增加 **10,144 bytes**。LOD 在首次 load-time 生成，发行包没有三份线路副本。PCK 751 entries 验证通过；原始扫描、OCR、tools、tests、docs、local artifacts 均不打包。

## L. PREPARATION COST

预热从约 6000 m/px、Paris 支持范围开始，包含 World→Region handoff；停住也会准备，不再依赖下一次 wheel。该时机不等于提前进入 Local。

| 阶段 | after ms | 位置 / 解释 |
|---|---:|---|
| file read | 7.670 | Content worker |
| parse | 122.478 | Content worker |
| source resolution | 773.437 | Content worker |
| canonical geometry chunks | 21.757 | Content worker |
| three LOD preparation | 43.010 | Presentation worker |
| label prepare CPU | 3.366 | 分帧主线程 |
| GPU enqueue CPU 累计 | 378.651 | 跨帧，不等于 GPU 实际 transfer clock |
| coarse ready since request | 1227.465 | 可先显示 |
| medium ready since request | 1810.047 | 可先显示 |
| full/local ready since request | 3059.565 | 原 before full ready=2183.189 ms |
| first physical visible frame | 1235.959 | `frame_post_draw` 标记 |

完整准备由约 2.18 s 增至 3.06 s，是三档缓存的真实代价；首个 coarse 可见约 1.24 s，普通用户持续缩放到 Local 前已准备。未 ready 保留粗缓存和 Region。文件系统缓存未刻意清空，不声称是 OS cold disk benchmark；GPU 实际完成时钟未独立量测。

## M. VISUAL

完整 native production scene 七级序列如下；World→Region 使用现有 wheel handler，其他固定尺度用于可重复截图。截图为实渲染，非 mockup。约 300 km Local boundary 与 round trip 的旧回归保留，新旅程亦包含 Local pan、返回 Region、Economy reference、Beijing / New York 尝试。

| screenshot | runtime / visual band | m/px | flag weight | fill weight | LOD | visible shard places |
|---|---|---:|---:|---:|---|---:|
| 01-world | WORLD | 19692.2 | 1.0000 | 1.0000 | 未 ready / 不适用 | 0 |
| 02-world-region | REGION FAR | 3282.0 | 0.3208 | 0.9585 | 未 ready / 不适用 | 0 |
| 03-region-far | REGION FAR | 4000.0 | 0.4617 | 0.9805 | coarse | 1 |
| 04-region-mid | REGION MID | 1200.0 | 0.0800 | 0.7651 | coarse | 30 |
| 05-region-near | REGION NEAR | 360.0 | 0.0038 | 0.5025 | medium | 22 |
| 06-local-far | LOCAL FAR | 180.0 | 0.0000 | 0.4241 | local | 11 |
| 07-local-close | LOCAL CLOSE | 50.0 | 0.0000 | 0.4200 | local | 3 |

![WORLD](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/01-world.png)

![WORLD to REGION](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/02-world-region.png)

![REGION FAR](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/03-region-far.png)

![REGION MID](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/04-region-mid.png)

![REGION NEAR](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/05-region-near.png)

![LOCAL FAR](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/06-local-far.png)

![LOCAL CLOSE](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/07-local-close.png)

Windows Release 也实际启动，通过菜单、selection、Labels 与滚轮完成 World→Region Far→Mid→Near 的手工检查。约 1178 m/px 时已显示城镇、铁路、河流与岸线：

![Exported Region Mid manual](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/release-visual/region-mid-manual.png)

手工操作随后检测到人工输入，代理停止发鼠标指令，不宣称完成全部 exported-binary 手工 Local 往返；完整 Local 与无数据地区的旅程属于上面的 native scene 夹具，证据分开标明。

[native journey 原始状态](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/journey.json) · [Region restored](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/10-region-restored.png) · [Beijing no Local](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/beijing-no-local.png) · [New York no Local](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/visual/new-york-no-local.png)。

## N. WORLD FACTS

没有修改 sovereignty、controller、administrative membership、Population、Economy、Personal Economy 或 Military simulation。没有新 World、LocalWorld、global grid、Province editor、occupation、trade flow、factory、market location 或 shipment。Renderer 的 cache / style / label state 是非持久 Presentation 状态。

新测试加载、各级 zoom / pan、跨地区、LOD 选择之后整个 formal persistence snapshot 与前值相同。Fresh-process formal world fingerprint 仍为 `ff34bcd09ab7cdbfd248a90755abe781ff24d94210b25e810a24407186d63724`。

## O. SAVE

`formal_world_simulation_v14` 不变。未改 persistence、未新增 save 字段或 schema migration。Exact persistence round trip、全量 world facts 比较、economic / political / world fresh-process deterministic checks 通过。

## P. REGRESSIONS

最终统一验证 exit **0**，25 个计数 runner，**26,244 checks / 0 failures**，另有 clean import / parse/type/load log scan、数据静态审计、provenance generation、fresh-process hashes 和正式 startup。

| runner | checks | failures |
|---|---:|---:|
| Formal personal economy and wages | 104 | 0 |
| Formal livelihood player journeys | 39 | 0 |
| Formal application and main/menu | 33 | 0 |
| Formal Person integration | 60 | 0 |
| Formal Spatial integration | 35 | 0 |
| Formal exact persistence | 32 | 0 |
| Formal Population production integration | 476 | 0 |
| Presentation content boundary | 60 | 0 |
| Formal map rendering regression | 745 | 0 |
| Formal map scale transition | 1280 | 0 |
| Formal map Local foundation | 68 | 0 |
| Paris Local Content R1 | 6537 | 0 |
| Map visual scale utilization R1 | 13577 | 0 |
| Historical provenance foundation | 48 | 0 |
| Runtime political identity foundation | 1186 | 0 |
| Formal economy 30-day and one-year golden | 6 | 0 |
| Formal economic boundary closure | 542 | 0 |
| Formal market identity foundation | 649 | 0 |
| Organization state | 137 | 0 |
| Formal organization composition | 99 | 0 |
| Current world domain convergence | 32 | 0 |
| Formal Windows export resource contract | 374 | 0 |
| Formal world integration | 67 | 0 |
| Formal world ten-year balance | 40 | 0 |
| Historical world economy data | 18 | 0 |

新增 scale tests 覆盖 flag 连续性、物理权重、LOD source/feature 同一性、三级 segment 数量、城市 eligibility、缓存选择、相机不重建/重读、已加载 Paris 不跨区域泄漏、行政 dirty-only / stale revision、全 save 不变。保留原 Map Rendering、Scale Transition、Local Foundation、Paris Content、Presentation Boundary 回归。

修复了准备后 Paris 与国家标签的碰撞；更新旧 scale fixture 的前提：早期后台准备可以与 Region handoff 重叠，必须等有限准备任务完成后检查 idle 停止处理，仍保留全部 anchor / bearing / selection / mode / geometry identity 断言。没有削弱正式状态规则。

[统一验证日志](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/unified-final.log) · [发行包核查](D:/WWO/wwo/local-artifacts/map-scale-utilization-r1/package-audit.json) · [Windows Release](D:/WWO/wwo/builds/windows/wwo-map-scale-utilization-r1-final.exe)。最终导出 exit 0，Release headless startup exit 0；手工检查的导出程序与最终文件 SHA-256 完全相同（91c63680f7361f72bb1fa75019babe519bd3d54a1a9726c2b2511ff20e6187d4）。保留预先存在的 export version `0.001a` 格式 warning，未改版本。

## Q. REMAINING VISUAL GAPS

- 非 Paris 地区没有新的细物理/交通资料；只有通用 fade 与既有城市/政治资料，保持无 Local 的诚实行为。
- Paris 底层 coarse political 海陆填色未重建，可能与更细物理 coastline 不一致；低潮港湾资料在中尺度仍可显得密集。
- 铁路仍是历史走廊 + 现代官方中心线参考，geometry LOD 不提升历史精度。
- 行政边界和 terrain / relief 仍分别为 ADMIN_BOUNDARY_DATA_GAP / TERRAIN_DATA_GAP。
- 城市/几何有限阈值切换没有新增时间动画；线的可见权重与旗帜/fill 连续，简化档切换可能有小幅形状差异。完整准备与缓存的 RAM / VRAM 成本已量测。
- 实际 GPU upload clock、driver 总显存及 OS cold-cache first-load 未独立测量；手工完整 exported Local 往返未重复完成，native fixture 与既有 Local foundation 已覆盖。

## R. NEXT RECOMMENDATION

Paris 的中尺度信息断层已经填补，**停止继续基础地图施工**。下一步建议单独决定 **Economy Algorithm Research**，先研究正式 aggregate 数据与空间参考的可用边界；不要把近似铁路直接当作精确运输图。

如果选择 Administrative Region R1，则先取得可准入的历史初始行政资料、设计权威 mutable membership，再接这个 Presentation cache seam。两项均未自动开始。
