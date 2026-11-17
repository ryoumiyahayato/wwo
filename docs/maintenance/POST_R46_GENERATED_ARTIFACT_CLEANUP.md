# R46后生成物清理记录

日期：2026-10-18。工程：`D:/programs/WWO/wwo`。用户本次授权清理已确认过期的生成产物。先确认R46完成并完成法国制图/加载取证，再分类。未启动游戏、未修改正式实现、未重新导出。

## 扫描与决定

只读盘点了`builds/`、`local-artifacts/`的构建、日志、地形制作缓存；针对`assets/maps/relief/`、`data/strategic/`、`data/presentation/`核对运行清单、制作工具和导出配置。没有把全部非原始GIS视为垃圾，也未按版本号或old/tmp名称批量删除。未读取真实存档及旧清理目录中的存档快照。

清理前候选共11文件，长度合计1,159,574,950字节。表内消费者按正式运行、导出及离线制作区分，不把历史报告提到某EXE路径当作运行依赖。

| 完整路径 | 类型 | 字节数 | 生成/修改时间（UTC+8） | 替代与消费者 | 决定 |
|---|---|---:|---|---|---|
| `D:/programs/WWO/wwo/builds/preview_2026-10-18_german_empire_terrain_r44/WWO_1900_German_Empire_Terrain_Surface_Reconstruction_R44_Preview.exe` | .exe | 754,774,704 | 2026-10-18 18:54:09 | R45直接回退、R46当前预览；仅历史R44报告提及原路径，无运行/导出消费者 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/benelux-surface-r46/benelux_r46/cover_colour.npy` | .npy | 150,995,072 | 2026-10-18 19:24:14 | 最终`.bin`已存在；仅离线制作缓存可选读取，缺失可从保留源TIF再生成 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/benelux-surface-r46/benelux_r46/dem_aligned.npy` | .npy | 50,331,776 | 2026-10-18 19:24:12 | 最终`.bin`已存在；仅离线制作缓存可选读取，缺失可从保留源TIF再生成 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/benelux-surface-r46/benelux_r46/field.npy` | .npy | 201,326,720 | 2026-10-18 19:24:18 | 最终`.bin`已存在；仅离线制作缓存可选读取，缺失可从保留源TIF再生成 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/r38_export.log` | .log | 2,145,466 | 2026-10-18 11:05:38 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/british-surface-r43/export.log` | .log | 404 | 2026-10-18 18:23:52 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/british-surface-r43/import.log` | .log | 0 | 2026-10-18 18:15:45 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/german-surface-r44/export.log` | .log | 404 | 2026-10-18 18:53:34 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/german-surface-r44/import.log` | .log | 0 | 2026-10-18 18:46:28 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/r45-export.log` | .log | 404 | 2026-10-18 19:13:08 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |
| `D:/programs/WWO/wwo/local-artifacts/r45-resource-import.log` | .log | 0 | 2026-10-18 19:10:27 | R46现有导出记录及各轮报告保留；非运行输入 | 已删除 |

## 分类依据

- R44 EXE已由R45及R46替代。当前内部导出预设指向R46，R41性能入口不使用R44；代码、场景、工具和导出配置没有该EXE读取者。R44报告仍记载历史交付路径，清理后该链接不再可执行。目录内全部来源、许可证和说明保留。
- 三个R46 `.npy`是已完成制作的中间数组，不是原始测绘或正式运行瓦片。`build_benelux_surface_r46.build`重建field；共享`build_france_surface_r42.mosaic`与`build_british_surface_r43.colour_mosaic`在缓存缺失时从保留TIF重建。33份DEM提取、7份覆盖提取、来源JSON、生成脚本及最终地表包保留。下次离线再生成会花时间重建缓存，不影响游戏读包。
- 旧导出日志只含过期打包文件列表、重复数字版本警告或为空；不含R41原始计时。保留R46当前导出日志、各国源数据取得/生成日志、R39/R40/R41记录以及法国调查资料。未把删除零字节文件计作节省长度。
- 未发现WWO游戏、Godot、Blender或WWO制作/导出进程；不终止其他项目Python。删除前再次核对明确目标与路径。

## 明确保留和不确定项

| 完整路径/范围 | 决定及原因 |
|---|---|
| `D:/programs/WWO/wwo/builds/preview_2026-10-18_benelux_terrain_r46/` | 保留最新唯一R46预览及全部来源侧件；EXE 855,233,536字节 |
| `D:/programs/WWO/wwo/builds/preview_2026-10-18_spain_terrain_r45/` | 保留直接回退；EXE 837,634,144字节；不因删除其旧日志而改动构建 |
| `D:/programs/WWO/wwo/builds/windows/` | 正式发布及其历史发布全部保留 |
| `D:/programs/WWO/wwo/builds/preview_2026-10-18_map_runtime_r39/` | 保留目录/说明及R39报告、导出记录。开始盘点时原路径已无EXE |
| `D:/programs/WWO/wwo/builds/preview_2026-10-18_geographic_world_r40/`、`.../preview_2026-10-18_historical_scenes_r41/` | 原R41 A/B性能对照价值保留；开始盘点时两目录已无EXE。没有再次删除、补导出或重建 |
| `D:/programs/WWO/wwo/local-artifacts/r41_performance/` | 全部原事件、CSV、进程/GPU、截图、日志和隔离配置保留；不得把已缺失的A/B EXE称为仍可完整重跑 |
| `D:/programs/WWO/wwo/builds/preview_2026-10-18_france_terrain_r42/`、`local-artifacts/france-surface-r42/` | 法国初始对照、来源和制作资料保留；原预览目录在任务开始已无EXE |
| `D:/programs/WWO/wwo/builds/preview_2026-10-15_coast_local_performance_r19/` | 本次直接排除：此前策略拒绝/保护，不尝试删除、改权限或移动绕过 |
| `D:/programs/WWO/wwo/builds/preview_2026-10-16_surface_environment_landmarks_r30/`、`local-artifacts/revoked-r30/` | 同上，直接排除；不恢复R30内容 |
| `D:/programs/WWO/wwo/assets/`、`data/` | 本次不删除任何文件。R27/R37/R39/R40及R42—R46的正式衍生有运行消费者；目录、瓦片、模型和必要import都保留 |
| `D:/programs/WWO/wwo/data/presentation/political_border_display_r3.json` | 正式加载已用R39，但制作工具仍引用R3；216,147字节原件保留，不能只凭运行入口未读就删 |
| `D:/programs/WWO/wwo/local-artifacts/geographic-foundation-r1/before-project/`等 | 部分制作脚本仍读历史基线；不是无消费者缓存，保留 |
| `D:/programs/WWO/wwo/local-artifacts/paris-local-r1/source/`、`trf-gis-1900/`、`historical-islands-admin-r5/` | 本次河流及行政取证来源、原GIS、投影和重建资料保留 |
| `D:/programs/WWO/wwo/local-artifacts/r41_extension/rejected/` | 模型准入拒绝的来源/比较价值未失去，保留；未作为垃圾清理 |
| `D:/programs/WWO/wwo/tools/`及所有Blender制作源 | 唯一生成方法和编辑源保留 |
| 其他旧预览目录中的许可/来源侧件 | 保留；没有因EXE淘汰就清空目录。R36/R37/R38/R43等原目录也已无EXE，不计入本次删除量 |

对`builds/`、`local-artifacts/`的EXE/PCK文件名检查没有找到R39、R40、R41、R42原预览的其他副本；不推断整个磁盘没有备份。上述缺失在首次完整构建文件盘点时已经存在，本次未造成。不会为了补齐回退而另行导出。

## 导出冗余

内部预设的`all_resources`及`*.json`会保留当前不读、但制作工具仍用的R3国界JSON。建议未来在导出包含规则中排除已确认不再用于发行的展示旧版；本次不改预设或删除原件。PCK体积不等于启动内存，清理外部旧EXE也不会直接缩短点击开始后的加载。

## 实际执行结果

表中11项均成功删除，逐项删除后确认路径已不存在。实际成功11文件，文件长度合计1,159,574,950字节，约1.080 GiB。失败0项。该值是实际被删文件的逻辑长度，不是NTFS分配空间或系统可用磁盘变化测量。

删除前先对全部目标解析绝对路径，确认均为本工程builds或local-artifacts内的具体文件，排除R19/R30、正式windows目录及运行中的目标EXE，再用PowerShell原生Remove-Item -LiteralPath逐项操作。没有递归删目录、通配符清理、权限更改或git清理/回滚。

没有修改正式源码、导出预设、项目版本、当前R46或R45构建。此次正式新增仅两份报告。原始地理、模型、制作脚本、历史测量、其他领域工作线及用户存档未触碰。未打开或转换用户五槽。

R46当前预览与R45直接回退仍在原路径；R44目录保留全部来源和许可证。三个制作缓存今后可重建；正式游戏仍使用已交付地形包。R39/R40/R41/R42原预览EXE此前缺失的问题仍存在，本次未重建。清理不会修复地图绘制或证明加载时间下降。



## 2026-10-30用户授权的旧安装包清理

通过原 `tools/build_preview.ps1 cleanup --execute` 删除已登记且文件长度/修改时间仍匹配的R58、R60、R61 EXE，共3文件、4,564,387,272字节（约4.25GiB）。本轮用户明确要求清理旧构建和安装包，因此解除这三个旧安装包的历史保留配置；没有将候选视为已验收。R63保持CANDIDATE，R62保留为直接ROLLBACK。

R59改为PROTECTED：`local-artifacts/terrain-lossless-20261027/baseline-directory.json`仍引用其EXE，`terrain_a0_sample.batch_webp`读取该包。R61压缩资源、manifest、原始地理资料、经济运行输出、军事工作线、存档和`.godot`导入缓存均未删除。

后续删除R58残留`override.cfg`、`local-artifacts/terrain-ab-20261026/optional-sample.pck`及旧空目录的命令在启动前被自动审批拒绝，只返回`blocked by policy`，未执行。未换工具或路径重试；残留配置加入原保护清单。此前拒绝的缓存和r57-person-participation目录继续保留。

## 2026-11-13 Rust 第五阶段交付后盘点

盘点范围为 `D:/programs/WWO`、C 盘用户临时目录内的 WWO 项、D 盘 `C-Drive-Archive-2026-11-13/Temp` 内的 WWO 项，以及候选和 Godot 的 WWO 用户目录。目录合计按文件长度计算。跳过目录连接点，跨目录总计对硬链接只计一次。操作前后约 36.61 GB。自动审批以 `blocked by policy` 拒绝删除命令，未给出具体原因。命令未启动，实际回收 0 B。

| 项目 | 占用 GB | 核对结果 |
|---|---:|---|
| `wwo` | 15.94 | `.git` 4.56、`builds` 3.83、`local-artifacts` 3.52、`assets` 3.31。R65 EXE 1.45 仍受预览保护清单保护 |
| `wwo-r68-candidate` | 8.29 | `builds` 4.63、`assets` 2.88、`local-artifacts` 0.21。两处 R67 EXE 是同一个 2.35 GB 硬链接文件，两条路径用于回退和离线恢复。R68 EXE 2.28，游戏在运行 |
| `offline-map-sources` | 5.61 | 主要为欧洲聚落 1.73、历史伦敦 0.81、Python 离线依赖 0.36、巴黎北部 0.33、里昂 0.30。保留来源、依赖与许可证 |
| 其他工作树 | 1.10 | 训练验证 1.04。军事和经济分支合计 0.06。独立工作线保留 |
| C 盘 WWO 临时目录 | 2.44 | 扣除目录内硬链接。约 0.51 GB 巴黎原始道路数据仍是重建输入。使用中的 R68 路线和兼容会话保留 |
| D 盘 WWO 归档临时目录 | 5.51 | 六个 C 盘连接点指向此处。最大为 `WWO-map-task-c` 2.61 和 `WWO-map-lab-toolchain` 2.44 |
| 候选与 Godot 用户目录 | 0.07 | 包含正式档位与候选测试档位，保留 |

Rust 项目 `wwo/local-artifacts/strategic-map-phase4` 为 123.15 MB，其中源码目录 0.25 MB、运行数据 41.09 MB。阶段 V ZIP 为 109.32 MB，阶段 IV 回退 ZIP 为 94.92 MB。阶段 V 的 118 个运行数据文件中没有额外的旧 PCK 或阶段 IV 可执行文件。

### 本次自动审批拒绝的目标

下列文件仍在原处。容量按文件长度并扣除组内硬链接，合计约 5.87 GB。未换工具、路径或命令重试。

| 原目标 | GB | 可恢复性 |
|---|---:|---|
| D 盘归档 `WWO-map-task-c/r68-embedded.pck` | 2.178 | 对照正式 R68 内嵌 PCK 的 50,698 个条目。50,697 个相同。旧 `ridgevale/heightfield.gdc` 的 1,484 字节已保存为同目录 `r68-embedded-ridgevale-heightfield.gdc` |
| D 盘归档 `WWO-map-task-c/town-rechecked` | 0.190 | 2,088 个文件逐字节与同目录 `town` 相同 |
| C 盘临时 `WWO-IV-host-build`、D 盘归档 `WWO-map-lab-toolchain/target` | 1.071 | Cargo 构建输出。保留交付程序、源码、编译工具及离线依赖 |
| D 盘归档 `WWO-map-lab-toolchain` 的 `rustup/toolchains/stable-x86_64-pc-windows-msvc`、`component-parts`、`rustup-complete.exe` | 0.743 | `mirror-rustup` 保有同版工具链。镜像中的完整压缩包覆盖分块。安装器与 `rustup-init.exe` 相同 |
| `wwo/local-artifacts/preview-manager/r68-relief` 内 `fra0`、`wwocm2`、`metadata-current` | 1.236 | 预览工具可用版本化配方、R67 和原资源重建。配方 2,525 个源路径均存在 |
| `wwo/local-artifacts` 中阶段 I、II、II Reference、II Land-Use、III 共五份交付 ZIP，以及阶段 IV 散放 EXE | 0.165 | 前五份逐项与工作区保留文件相同。散放 EXE 与阶段 IV 回退 ZIP 相同 |
| C 盘临时 `wwo-stage-v-package-veytnci4`、`WWO-IV-market-package-txhk22jt`、`WWO-strategic-map-II-delivery`、`WWO-Phase3-delivery-20261113` | 0.254 | 解包副本逐项相同，额外文件为本地启动记录 |
| C 盘临时 `WWO-V-formal-*` 八个已退出会话、`WWO-V-route-*` 四个已结束操作目录 | 0.033 | 正式截图和结算记录已保存。候选档位在独立用户目录 |
| `wwo/builds/.preview-staging/border-292172137b694c8fa2fe5fbff07e97c2/WWO_Unified_Debug/shader_cache` 和阶段 V `tools/__pycache__` | 0.004 | 可再生成的着色器和 Python 缓存。同一暂存目录的档位与窗口资料保留 |

后续每轮交付后处理该轮已退出会话、解包副本和可重建编译中间件。交付包保留当前候选和所需回退。正式资源目录、独立研究、当前运行依赖和已拒绝路径沿用原保护。新 Rust 包按当前运行数据清单打包，旧展示资料保留在需要它们的原工程或研究目录。

### 同日追加清理与 10 GB 目标

Git 使用 `prune-packed` 清除 13,040 个在现有 pack 中已有副本的松散对象。逻辑长度减少 1,247,653,540 B。执行前后 D 盘可用空间从 115,462,918,144 B 增至 116,740,001,792 B，增加 1,277,083,648 B。清理后 `prune-packable` 为 0。三份 pack、引用和工作树均保留。Git 仍报告一个约 3.15 MB 的旧临时 pack 文件。

三处先前未列为拒绝目标的阶段 IV 临时解包目录中，457 个逐字节相同的地图数据和截图副本送入 Windows 回收站，共 207,867,367 B。各快照独有的文件保留。回收站未清空，该批字节不计作磁盘释放。之前被拒绝的目标未重试。

主工作树由 15,941,301,476 B 降至 14,693,652,582 B。全盘点范围扣除硬链接后约 35.16 GB，回收站单列。主工作树内 `.git`、`assets`、R65 与 R67 两份受保护的构建路径合计约 10.42 GB。10 GB 目标未达到。R67 在 R68 工作树的硬链接及配方仍在使用。正式候选、研究与存档保留。

### 主工作树以外的追加清理

已退出的 WWO 临时测试和归档删除着色器缓存 1,524 个。C 盘临时目录另删除 48 个与交付截图逐字节相同的副本。六个隔离候选档位目录在取得独占会话锁后删除 89 个着色器缓存，保留全部档位。各次操作前后实测可用空间合计增加 484,900,864 B，其中 C 盘 336,105,472 B、D 盘 148,795,392 B。未清空回收站。

清理后 C 盘 WWO 临时目录约 1.97 GB，D 盘 WWO 临时归档约 5.36 GB，候选隔离档位目录约 8.44 MB。上述容量按文件长度计。R68 工作树约 8.29 GB，正式程序与兼容会话仍在运行。离线地图来源逻辑长度 5.61 GB，Windows `compact` 查询报告存储数据 2.40 GB。针对部分已压缩或难压缩资源的压缩操作实测未增加可用空间，未计作释放。

上次审批拒绝的主工作树外目标合计约 4.47 GB，仍保留。原始地理资料、独立工作树、用户存档与现役候选保留。
