# WWO军事线唯一归档入口 · 2026-10-24

私有仓库 `ryoumiyahayato/wwo`，分支 `archive/military-full-20261024`。本分支只归档军事研发链，不是默认主线，不是正式游戏Release。默认分支、R57候选及R56回退均未修改。大型资料在本仓库私有草稿归档附件，Git分支保存可直接阅读的当前源码、恢复工具和一份机器清单。

## 当前是什么

当前基线为 `formal-combat-authority-20261024`：R57代19已验基底，加当时冻结接入的8份主线文件。之后6份经济/人物变化未接入、未验。不追赶本次主线代21。限定具名资格、组织授权、委派、接令和撤权恢复已实现；**FORMAL_COMBAT_NOT_READY**。正式身体/医疗、作战区域、combat军备指派、局部执行和结果采用仍缺。

原成功点应保持2人物/2 claim、1原具名单位/0聚合兵力、2次成功勤务、18发可用/2发已耗、正式2分钟、12,402,648微秒余量。成功与撤权分别保存，历史接令不删除；本轮不增加combat开火、战果或伤亡。

## 去哪里读

- [当前实际源码](current/runtime/)：1233个可阅读文件，10653905字节。完整运行资源和原始文件字节以附件及清单为准；不能只clone源码镜像就宣称完整恢复。
- [唯一机器清单](manifest.json.gz)：gzip压缩UTF-8 JSON。含全部原路径、大小、SHA256、硬链接身份、内容去重映射、分包、私有附件ID、专用用户目录、排除与保护范围。恢复工具只读云端包，不读取清单里的旧源路径。
- [独立恢复工具](tools/restore_military.py)：使用Python标准库，要求显式清单、下载目录、全新目标及专用用户目录。默认仅恢复当前runtime和当前private_state，可在首次验证时额外取回原枪口恢复样本。

历史文件可给同一工具增加 `--archive-prefix <清单中的某个旧目录>`，按原字节还原该目录，保留其历史缓存和报告；旧`.git`工作树指针以原字节放入`.archive_origin`，不自动重新连接主工程.git。该模式不启动引擎，也不宣称逐历史版本重新运行通过。混合工作台未归档的经济/共享内容不能用此模式冒称完整恢复。不要默认下载整个军事历史树。
- [私有归档附件](https://github.com/ryoumiyahayato/wwo/releases/tag/untagged-75a9dbc800223cbf8a18)：18个分包，7192143243字节；草稿附件要求有权账号登录，不开放持链接访问。清单保存稳定附件ID；脚本用GitHub认证下载，不保存临时签名URL。

首次大包请求超时后改为64MiB分段传输，没有重新压缩。附件中的`.part`必须按清单重组，分别检查段SHA256和完整ZIP的SHA256。失败的`starter`对象不是恢复依赖，不计入已完成归档；只使用清单中的成功附件ID。

## 覆盖与历史边界

本地军事树原盘点603,465个文件、63,402,879,747字节；硬链接逻辑大小不能当成释放空间。新增17个明确军事专用用户目录，265,081,616字节，未读取主WWO真实玩家五槽。本轮纳入597914个文件，去重后44407份内容、8767158190字节。当前依赖、历史材料、私人状态分包；同内容只保存一个主体，旧路径由清单映射。

历史成功、失败、未采用增量、原始报告、录像、恢复脚本和冻结依赖原样保留。原30文件增量ZIP不再是唯一恢复依据；旧日期目录与硬链接目标的真实内容已纳入。`.import`配置和UID保留。历史Godot缓存也保留在历史对象中，当前恢复明确跳过全部旧`.godot`，要求新导入验证。

`wwo-web-workbench-20261015`实际是经济/军事混合仓库，根仓库和经济内容不迁移删除，仅纳入明确军事适配源码。原库 `ryoumiyahayato/wwo-economy-lab` 的本地HEAD为 `b4795906250a6a765da5eb99b0ce7a87300374ac`，本轮不将其当成军事独占目录。主WWO、经济/CAD/地图等其他工作线、共享原素材、账户/签名凭据和通用工具链不清理。

本地未找到旧APK原件，2.3GB旧完整ZIP中也没有APK；旧交付记录不能代替原件。不重新导出APK，不宣称全历史从未缺失。旧Drive冻结/Cedar/Rivergate/Atlas入口仅作历史来源；未回下载核对的旧云端对象不作为本轮删除依据。旧报告的权限或调度安排只是历史，不恢复旧queue、协调聊天或后台监控。

## 如何恢复

先登录有权读取私有仓库的GitHub账号，将本分支 `manifest.json.gz` 与 `tools/restore_military.py` 实际下载到一个新目录。安装现有Python标准库运行环境、GitHub CLI及Godot4.6.3标准版Compatibility；不更换引擎。用有权账号的 `gh auth login` 状态下载附件。

```powershell
& <Python.exe> <下载目录>\restore_military.py `
  --manifest <下载目录>\manifest.json.gz --packages <新的附件下载目录> `
  --destination D:\programs\WWO\research\military\current `
  --user-dir WWO-FormalPractice-MilitaryCurrent-20261024 `
  --archive-commit <本分支已核实提交SHA> --download
```

该命令必须使用不存在的目标目录和新下载目录。它按清单下载所需附件、核对SHA256，逐文件物化普通文件，不创建指向旧D盘目录的链接。声明的迁移差异只有：project.godot中的专用用户目录；authority/recovery_checks.gd的报告输出由旧D盘绝对路径改为显式task_root下的文件。新普通文件不重设原共享只读/硬链接标记，不改变军事规则或保存字节。原始源码及原输出路径仍保留在冻结附件中，恢复工具应用上述两处迁移修改。然后用Godot4.6.3对新runtime执行无旧缓存导入，再由 `current/tools/Run-Military.ps1` 显式读取成功portable。撤权输入为 `current/private_state/authority_revoked_portable.json`，仅用于独立检查。

## 实际验证与清理结果

- `CLOUD_ARCHIVE_VERIFIED`: true
- `CLOUD_ONLY_RESTORE_PASSED`: true
- `OLD_LOCAL_CONTENT_REMOVED`: true
- `CLEAN_CURRENT_RESTORED`: true

[实际结果与唯一清理清单](archive-results.json) · [绝对路径删除清单](DELETE_PLAN.json)。全部18包已从GitHub回下载，SHA256、ZIP CRC及对象映射通过；首次新目录恢复不读取旧源码或旧AppData。Godot4.6.3无缓存导入、既有权限/勤务/枪口恢复证据检查、成功和撤权冷读均已实际执行。没有重新强杀、长期模拟或新增作战。

manifest.json.gz是冻结的文件与对象映射快照；实际恢复源码提交以archive-results.json的verified_source_commit为准，最新删除结果以DELETE_PLAN.json和archive-results.json为准。

已删除旧根目录 52 个；移除文件目录项 590561 个，逻辑字节 63137542807。实际空间变化见清单的磁盘前后观测，硬链接逻辑大小不作为释放量。

本地current已按用户后续清空要求删除，当前没有活动军事工作区；需要时从本归档恢复。再次从GitHub新下载所需6包并独立物化；第二次无缓存导入、原生成功冷读及撤权冷读通过。复现日志见 [验证日志](verification-logs.zip)。默认成功portable；撤权portable仅作对照。`RESTORE_RECEIPT.json`保留实际恢复所用固定源码提交，不改写成后来的收尾说明提交。

5个旧目录因混合经济工作台或仍有共享引用保留，外部403模型来源库和主WWO.git保持原样。经济16包原回下载记录及当前云端元数据已核对，但45项原清理曾遭策略拒绝，未重试。主工归档分支源码与精选证据可读；当前完整运行/重建仍有本地缺项和许可限制，未删除主工程、候选或回退。

本地清空补记：current及其专用测试user已删除；批准的旧52根及本轮暂存此前已清理。5个共享/混合旧根和外部模型来源库继续保护。本地仅留小恢复索引与清理记录，不保留完整军事工程或压缩包。
