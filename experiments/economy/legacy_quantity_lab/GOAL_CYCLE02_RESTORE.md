# Goal Cycle02 完整恢复说明

## 两个组件共同构成完整恢复集

1. WWO_Economy_Goal_Cycle02_Source_Restore.zip：全量已跟踪源码、原历史结果、Git对象/分支/显式 shallow 边界及本轮状态/报告。解压得到 source/，无需 GitHub 或阅读包生成源码。
2. WWO_Economy_Goal_Cycle02_Full_Raw_Evidence.zip：所有 .local/cycle02 原始完成/失败/中断/开发/诊断/复审档案，原 Cycle01 交接 ZIP、bundle/patch。解压到同一父目录，将 source/.local/cycle02 合并到上述 source/。RAW_FILES.json 逐文件提供尺寸和SHA-256。原始证据压缩前约17.9GB，请预留25GB以上。

旁置 handoff/export_manifest.json 记录最终 sealed HEAD、每个组件实际字节/哈希、恢复检查。小阅读ZIP只用于阅读，不能替代上述两组件。

源快照 .git 的浅边界是 BASE 334d3f546824415604b7645a91a61196fb2bad83；早于BASE的父历史未取回。该标记保留，不声称无限历史克隆。

## 最小恢复验证

在解压得到的 source/ 中运行：

- git status --short（应空）
- git rev-parse HEAD（须等于旁置export_manifest的final_sealed_HEAD）
- git fsck --full
- python verify_goal_cycle01.py --correctness-only
- python reaudit_cycle02.py（使用同目录恢复的118正式档案与10负例；耗时约12分钟，不会重跑经济）

读取 .local/cycle02/replay_a 和 replay_b 的 execution.json、hash_manifest.json，结合原档CRC/SHA验证；不要将中断目录当成完整成功重放。

## 新进程精确经济复现

原经济执行版本为710dac38d82a4d48609e88c9f974a927e9b6c686。最终源码含明确另列指纹的离线v4检查/分析修订。要复现原533文件字节，应从恢复仓库另建这个执行版本的独立检出，再用冻结 experiments_manifest_cycle02_final.json，输出到两个新目录。不要从fixtures.formal_manifest()再生成旧43配置或旧holdout资金。

实际命令接口见 run_cycle02.py --help；原命令、final59 config、执行前后10源码hash均在各replay根execution.json保存。两个案例集均完整独立初始化，不能拼接短前缀模拟3600日。

## Patch / bundle

增量patch和bundle均相对真实Cycle01封存提交93633b4321dc288bd14b064350cc7fb053529bae。bundle须先具备该commit和对象；它不是独立仓库。完整源快照已含所需依赖，恢复不依赖bundle。patch只应用一次。

## 状态

研究结论：SOURCE PASS / CAUSAL PASS / MODEL MIXED，M0—M5 DONE，GOAL_COMPLETE。未push、PR、merge、tag或正式集成。完整物资/资金与因果证据可重查；人工fixture、信息缓存增长、ID tie-break、异质限价下个别sink恶化等边界仍存在。推荐A，仅建议，不自动执行Cycle03。
