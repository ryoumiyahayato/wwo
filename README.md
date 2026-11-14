# WWO · GitHub main 开发入口

当前主工仍为 **R57代21 CANDIDATE，accepted=false，1,759,546,768字节**；R56为 **ROLLBACK，1,834,465,568字节**。唯一正式开发基线和默认分支为 **`main`**。本轮治理不生成EXE，不改变候选登记，不自动promote。

## Rust 人物系统

[rust/character-core](rust/character-core/README.md) 是面向 Rust 迁移的独立人物规则库，包含隐藏能力、经历、健康寿命、社会机会条件评估和版本化存档。可运行示例及宿主接口见模块说明；尚未接入正式游戏主循环、UI 或经济执行，不改变下面所述的现有 Godot 入口。

## 在线开发

一个新任务从最新 `main` 建立一个短期分支，提交一个面向 `main` 的PR。必要自动验证成功并完成审查后才合并；完成后退出短期分支，不建立永久主线副本。不要用 `[skip ci]` 跳过需要的检查。

普通PR运行 [Main validation](.github/workflows/main-validation.yml)：源码差异格式、修改过的Python/JSON语法与Actions配置检查；Godot 4.6.3无界面导入，以及既有个人账务、巴黎双雇主、有限原料交易局部回归。检查无路径过滤，便于设置稳定必需状态 `Source checks` 和 `Formal economy and person`。原料交易使用仓库归档的第30日检查点副本，保存写入隔离目录；不下载全量地貌BIN、不导出候选包。检查失败、资料缺失或超时均不是通过。

原有长跑、完整领域、研究流程保留为手动检查。Windows安装包只接受明确的手动构建确认，发布草稿另有默认关闭的输入；普通PR或合并不创建Release、不覆盖历史附件。正式发布与代码合并分离，仍须资源恢复和真实游戏验收。线上检查不能替代实际游戏验收，R57仍为CANDIDATE，R56继续保留。

军事、经济及独立研究线保持隔离。不能从分支名称推断已合入，不能将研究策略直接接入主WWO；独立PR分别审查，不自动合并或删除。历史候选使用固定归档提交、[构建登记](docs/archive/main-wwo-r57-g21-20261024/build-identity/preview_registry.json)和私有附件管理。

本轮核对、权限阻塞、旧PR处理及旧分支退出条件见 [主线治理记录](docs/maintenance/MAIN_GOVERNANCE_2026-10-25.md)。下一项主体任务只准备独立PR范围：[巴黎两家企业的自主经营约束](docs/maintenance/PARIS_AUTONOMOUS_ENTERPRISE_SCOPE_2026-10-25.md)。

## 已保存内容

主工当前源码、场景、Opening配置、UID、脚本、工具和说明在仓库实际路径。入口是 [project.godot](project.godot) → [正式菜单](scenes/formal/formal_world_menu.tscn)。引擎为Godot 4.6.3 Compatibility。

地貌运行BIN、R57现存制作输入、运行证据、隔离测试存档及来源材料在私有草稿附件。本次用户在得知LOCAL_ONLY清单后要求补传剩余原件；R57/R56 EXE、builds/windows历史发行、当前.godot冻结缓存、GIS Python库、模型/BLEND/图像和现存原始数据组件均已补存并逐包实际回下载。没有把大文件提交普通Git，没有发布正式Release。部分原件作者或再分发许可仍未明确，原说明保留；私人备份不将其改为可公开发布素材。

[统一清单](docs/archive/main-wwo-r57-g21-20261024/inventory.json)保存原路径、字节、附件对象ID、提供方返回的完整性元数据、分段偏移、回读状态和本地处置。相同文件逐字节确认后只存一份主体，`file_aliases`记录不同恢复位置。此前README中的“模型/二进制/缓存未上传”状态已由本次补存更新，原始历史报告不改写。

## 恢复与边界

先clone仓库的 `main`；恢复历史代21时检出固定归档提交 [`2be78dee796cda0e70478f6b4435ac9505a5a936`](https://github.com/ryoumiyahayato/wwo/commit/2be78dee796cda0e70478f6b4435ac9505a5a936)，不要依赖待退出的旧主线分支名。再用[恢复工具](tools/archive/restore_main_resources.py)读取统一清单，恢复到唯一的新目录。完整恢复需要 `--scope all`；只恢复运行依赖可用 `--scope runtime`。工具通过现有gh认证取得私有附件；不依赖原D盘资源链接，不覆盖已有文件。`--only-path`可选精确文件。检查点与真实玩家五槽分开，恢复测试用户目录不会自动写回AppData。

当前源码是接续快照；构建输入23,048项曾与代21登记的大小、mtime相符，没有构建时源码提交可证明EXE逐字节对应。驱动和报告有构建后的变化，未重导出。

已有能力与限制：普通人物生活、有限NPC自主生活、岗位流转、多雇主及30日连续运行/日24真实冷恢复已有记录。代21只证明玩家参与条件下有限原料交易，不证明持续自主补货。巴黎性能P1、菜单超时及其他未定位问题保留。见[代21报告](docs/map/R57_ORDINARY_MATERIAL_TRADE_2026-10-24.md)、[运行证据](docs/archive/main-wwo-r57-g21-20261024/evidence/)与[地图剩余问题](docs/map/R57_MAP_INTERACTION_CLOSEOUT_2026-10-22.md)。

本轮是现存文件的私人归档。已有输入不等于所有历史全球GIS/DEM来源齐全；原本缺失的输入未凭空补齐。外部Godot/Blender/Python安装和其他工作线不包含在主工文件包中。文件层回读与样本恢复不等于重新通过无缓存引擎导入、完整重建或游戏冷恢复；本轮没有运行这些验证。

## 本地处置

前轮已删除77个目录和45个独立文件，详情仍见清单resource_supplement.cleanup。本轮剩余原件上传后没有自动删除。按用户要求提供[PowerShell清理指令](tools/archive/cleanup_uploaded_remaining.ps1)：先预览，明确传入已核实提交和-Execute才删除。默认只处理remaining_originals_backup.manual_cleanup_files；额外传入-IncludeMainSource时加入同一清单的main_worktree_cleanup_files，包含已核对的主工源码和运行资源。归档后变化、链接或运行占用会停止操作，不改属性、不强制删除、不改回收站重试。

经济45项和主工此前被拒绝165份仍排除；共享/混合服务目录、真实玩家存档、凭据及其他工作线不进入这份清理指令。不能据此清空整个D:/programs/WWO。经济第23代另见[经济归档](https://github.com/ryoumiyahayato/wwo-economy-lab/releases/tag/economy-gen23-closeout-20261024)，军事另见[军事归档](https://github.com/ryoumiyahayato/wwo/tree/archive/military-full-20261024)。后续由用户直接安排，不启动新开发或旧协调。

私有附件：https://github.com/ryoumiyahayato/wwo/releases/tag/untagged-efeded1f78503dcbe026

本次补存：92包，3370832726字节有效包体；实际网络总流量未计量。

本次另从固定提交下载恢复工具和清单，实际恢复一份模型、一个空文件别名及其主体，并核对复用已存在的相同Git导入配置；内容与原件一致。工具不读取旧源目录。未启动引擎。
