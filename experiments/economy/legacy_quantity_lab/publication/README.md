# Economy Goal 02 已授权研究发布索引

[Cycle02 完整报告](../GOAL_CYCLE02_REPORT.md)、[完整恢复说明](../GOAL_CYCLE02_RESTORE.md)、[59 案例指标](../economy_quantity_lab/goal_cycle02/evidence/final_metrics.csv)

## 发布与封存身份

用户于 2026-10-08 明确授权同步已完成经济与军事算法研究及未来游戏接入直接相关材料。此分支只新增恢复/发布索引。原封存状态文件中“未 push / 未授权发布”等描述保留为历史记录，未被覆写。

- LOCAL_SEALED_HEAD：f8c2915894b9a99deb147414a1f7ee18486d200f
- REMOTE_PUBLICATION_COMMIT：[封存树等价快照](https://github.com/ryoumiyahayato/wwo-economy-lab/commit/a31bfed0570a04506158475d46bd3ed0a19f90c4)
- 原封存 tree：1ba98d135463f450197611a8cd94ae1a3588b463
- 508 个原文件的路径、mode 和 Git blob 字节完全相同；整棵 tree SHA 精确一致
- 本分支 HEAD 是随后增加 publication/ 目录的索引提交，其父提交为上述等价快照

正常 Git 传输没有可用认证；此次使用已连接 GitHub 的原生 Git 对象工具生成新 publication commit。新提交具有新元数据，不能把它称为原 local sealed HEAD 的上传。真实原提交身份与所需对象仍在 Library 完整恢复包中。完整原文件索引见 [SEALED_TREE_FILES.json](SEALED_TREE_FILES.json)，关系与发布范围见 [PUBLICATION_MANIFEST.json](PUBLICATION_MANIFEST.json)。

## 完整恢复

完整恢复集是 Source_Restore.zip 加由 15 卷合并的 Full_Raw_Evidence.zip。现有 Library 文件名、ordered library_file_id、每卷容器 ZIP 的 SHA/字节数见 archive_index/LIBRARY_DELIVERY.json；原始 chunk 的 offset、字节数和 SHA 见 archive_index/raw_parts_manifest.json。完整 canonical 交付身份（含最终 Delivery_Index.zip）见 archive_index/CANONICAL_LIBRARY_ARCHIVES.json。

1. 从自己的 Library 保存 Source_Restore.zip 及全部 15 个 Raw_Part_XX_of_15.zip，保持清单中的准确文件名。
2. 运行 python publication/archive_index/restore_raw_evidence.py /保存全部15卷的目录 /新目录/WWO_Economy_Goal_Cycle02_Full_Raw_Evidence.zip。脚本先逐卷提取 raw.partXXX，再验证每个 chunk 以及合并 ZIP 的总尺寸和 SHA。不要直接连接 15 个包装 ZIP。
3. 将 Source_Restore.zip 与合并原始证据 ZIP 解压到同一父目录，使 source/.local/cycle02 正确合并。保留全部分卷、合并 ZIP 和解压档案时请预留约 40GB。
4. 用 archive_index/export_manifest.json、source_archive_validation.json、raw_archive_validation.json、raw_file_manifest.json 和 source_file_manifest.json 核对实际成员与恢复验收。Source_Restore 的 Git 对象恢复原 sealed HEAD，早于 Round6 BASE 的父历史是显式 shallow 边界。
5. 原经济执行版本为 710dac38d82a4d48609e88c9f974a927e9b6c686；最终封存 HEAD 另含 post-execution v4 离线审计与分析修订。具体复现与复审命令见 ../GOAL_CYCLE02_RESTORE.md。

完整原档的 7.32GB 内容不存入 Git。Reading_Review.zip 只便于阅读，不能替代完整恢复集。所有原完成、失败、中断和开发证据均保留；本次发布没有复跑。

## 未来游戏接入的审查入口

继续审查单一经济/订单/物资结算权威、Cycle01 的支付/排序/局部价格反馈、Cycle02 的因果审计与唯一受限 N4 候选，以及报告记录的愿付振荡、sink 服务转移、缓存增长和模型限制。源代码、冻结配置、反例与原报告全部同树保留。

本次没有修改 main、创建 PR、merge、tag、生产部署、正式 WWO 接入或开启下一研究周期。数据均来自 [冻结人工模拟](SYNTHETIC_DATA_SCOPE.md)。远端 CI 未被此索引声称通过；最终交付另核对当前 commit 的 run/check/status。
