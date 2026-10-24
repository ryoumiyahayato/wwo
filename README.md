# WWO 当前接续入口：R57 代21归档（2026-10-24）

此入口对应私有仓库 `ryoumiyahayato/wwo` 的 `archive/main-wwo-r57-g21-20261024`。默认分支仍为 `canonical/current-world`。本轮只整理和上传；未构建、未运行Godot、未promote、未合并、未删除历史内容。

当前为 **R57 代21 CANDIDATE，1,759,546,768字节，accepted=false**。R56继续 **ROLLBACK，1,834,465,568字节**。候选与回退EXE均本地保留，**LOCAL_ONLY**。未把EXE、PCK、Godot缓存或2GB地貌BIN提交普通Git。

## 当前能力与限制

主工程支持普通人物生活、有限NPC自主生活、岗位流转和多雇主选择。已有30日连续运行，以及日24中断后的真实冷恢复记录。代21证明：玩家参加两小时劳动后，工坊粮食经订单41交付面包房，随后进入生产。**没有证明持续自主补货**。NPC岗位/原料约束和巴黎性能P1继续保留；菜单超时等未定位问题没有关闭。详细适用范围见[代21原料交易](docs/map/R57_ORDINARY_MATERIAL_TRADE_2026-10-24.md)和原始失败记录。

## 工程、源码与构建身份

正确工程入口是本仓库的 [project.godot](project.godot)，菜单 [formal_world_menu.tscn](scenes/formal/formal_world_menu.tscn)，正式场景 [formal_world_main.tscn](scenes/formal/formal_world_main.tscn)。Godot **4.6.3 Compatibility**。使用同一正式WorldBootstrap/WorldState/SimulationStep/Persistence；独立经济研究代数和军事候选不属于本次主WWO版本。

主要源码：[正式应用](scripts/formal/formal_world_application.gd)、[人物经济](scripts/world/formal_personal_economy_state.gd)、[原料交付](scripts/world/economy_cargo_fulfilment.gd)、[Opening](data/formal/paris_employment_opening_r1.json)、[地图](scripts/presentation/map/region_view.gd)。保存了当前脚本、场景、UID、配置、工具及具有来源条件的显示数据。原有云端文件由基线提交 `28cdc2dc37c68161dc7b3a3254692980cc75e972` 继承，未重复打包。

当前运行输入23,048项与代21构建登记在大小和mtime上相符。没有构建时源码提交可证明逐字节对应，因此此分支是**当前源码接续快照**，不称为“代21精确源码提交”。驱动和报告有候选生成后的修改，未重新构建。[构建登记](docs/archive/main-wwo-r57-g21-20261024/build-identity/preview_registry.json)与[输入登记](docs/archive/main-wwo-r57-g21-20261024/build-identity/preview-inputs.json)保留原值。

启动：恢复下列本地依赖后，用Godot4.6.3打开工程并运行项目。构建仍按 [预览管理器说明](tools/build/README.md) 和 `tools/build_preview.ps1` 执行，并遵守既有资源锁；本轮未执行这些命令。归档分支push不匹配现有仅针对默认分支的构建触发器，未修改或停用工作流。

上传状态：**UPLOADED_VERIFIED**。首轮提交6,700项的远端Git对象身份一致；20项关键内容通过GitHub API实际回读，压缩/JSON样本可解析。此结论只覆盖文件层。

## 唯一清单与精选证据

[统一清单](docs/archive/main-wwo-r57-g21-20261024/inventory.json)记录路径、文件数、字节、工作线、用途、消费者、替代、云端状态与本地处置。`selected_files` 给出原路径和云端实际路径；`groups` 区分既有云端与本轮选入；`exclusions` 列出未上传依赖。上传成功不授予删除权限。

- [生活界面及30日运行](docs/map/R57_ORDINARY_LIVING_UI_2026-10-23.md)、[NPC自主生活](docs/map/R57_ORDINARY_AUTONOMOUS_RESIDENTS_2026-10-23.md)、[岗位流转](docs/map/R57_ORDINARY_EMPLOYMENT_CIRCULATION_2026-10-23.md)、[多雇主](docs/map/R57_ORDINARY_MULTI_EMPLOYER_CHOICE_2026-10-23.md)、[代21原料交易](docs/map/R57_ORDINARY_MATERIAL_TRADE_2026-10-24.md)。报告中的本机证据路径映射到清单的 `destination`；历史报告不改写。
- [精选证据目录](docs/archive/main-wwo-r57-g21-20261024/evidence/)保存既有压缩记录、实际GUI代表画面、日24中断、首次原料失败及中断日志；保留失败，不只保留PASS。截图数据为游戏模拟，版本和场景见清单。
- [连续运行主档与冷恢复备份](docs/archive/main-wwo-r57-g21-20261024/checkpoints/)分别是经过30日和24日的独立测试世界；UI日历分别1900-01-31和01-25。[原料采用后检查点](docs/archive/main-wwo-r57-g21-20261024/evidence/r57-living-ui-2026-10-23/material-candidate/material-slot4-adopted.json.gz)为经过44日，另有在途责任检查点。没有读取真实玩家五槽。本轮仅文件读取/解析，不是重新进行游戏恢复。
- [地图剩余问题](docs/map/R57_MAP_INTERACTION_CLOSEOUT_2026-10-22.md)、[来源与重建调查](docs/map/R57_TERRAIN_SOURCE_RECOVERY_AND_REBUILD_READINESS.md)。旧调查适用于2026-10-20；当前10月21日区域ETOPO缓存已存在，不能把旧“缺源”结论套到所有新缓存。它们仍不等于完整全球原始输入已恢复。

## 云端可继续开发与完整恢复缺口

云端可以查阅并继续编辑主线源码、Opening、工具及精选证据。**单独下载本分支不能完整重建或运行当前候选。** `assets/maps/relief/` 的3182个新BIN（1,992,581,569字节）仍仅本地；旧云端原有资产不因此补齐。当前候选、R56、旧受保护发行、Godot缓存保持本地。没有已配置的LFS对象或获准的新二进制渠道；旧 `prototype-latest` 是受保护历史预发行，本轮未改动、未发布Release。

再分发权未明确的内部预览模型、云盘适配BLEND、civilian交付模型、orbital_r24图像未新增上传，详见清单。原创R40/R41模型、图标及明确授权海洋材质连同制作源/许可已纳入。地理衍生资料保留原来源和许可，包括CShapes非商业条件、OSM、TRF等，不把不同许可统一改成CC0。

全球GIS/分类/DEM原件、区域缓存和制作依赖仍在清单列出的本地目录。已有制作脚本不等于已经证明可从原始输入完整重建。部分原始GLO/WC/ETOPO输入仍缺完整来源或版本恢复证明。未重新进行无缓存Godot导入、全世界地貌重建或游戏恢复验证。其他工作线仅登记入口，没有移动、上传或删除其内容。

## 本地取舍

本轮实际回收 **0字节**。当前候选、R56、正式历史发行、运行资产、来源和检查点为KEEP。未完整覆盖的历史实验、缓存与数据为ARCHIVE_THEN_REVIEW/HOLD，不能据目录日期删除。已核实重复截图两份570,690字节、重复成功日志一份100,447字节，共 **671,137字节** 列为DELETE_CANDIDATE，主体已归档并有别名；尚未删除。此前遭拒绝的165份、48,152,351字节继续HOLD，未重试删除。没有清理远端历史、分支或标签。

较早代20结论由本入口和代21原料报告界定更新；旧报告保留日期与适用版本。旧分支清理文档中的master表述是历史规则，当前默认分支以本入口核实的 `canonical/current-world` 为准。

完成整理后停止。后续由用户直接安排，不自动恢复研发、模拟、测试或历史资产删除。

本轮自有归档辅助脚本、备用Git索引及入口副本也列入清单的暂存取舍，归档完成后无运行消费者；未删除。清单中的占用数标注统计时点，首轮网络pack长度未留存，未用原文件长度冒充网络量。

## 后续补传与清理（2026-10-24）

阶段：`UPLOAD_IN_PROGRESS`。地貌BIN和R57制作资料使用[私有草稿附件](https://github.com/ryoumiyahayato/wwo/releases/tag/untagged-efeded1f78503dcbe026)，不会成为正式游戏Release。已实际上传并回读 40/64 包。文件路径、分段偏移、提供方对象ID、大小及校验元数据仍使用[统一清单](docs/archive/main-wwo-r57-g21-20261024/inventory.json)中的resource_supplement。全部大包在内存中串行处理，未新增磁盘ZIP；没有主动计算新哈希。

