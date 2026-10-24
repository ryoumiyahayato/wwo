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

