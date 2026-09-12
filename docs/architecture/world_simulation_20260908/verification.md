# 本次验证记录

日期：2026-09-08。源码基线与远端master：`85c073649e1ed17594f2a41d4f2081feceeabe8b`。

## 已实际执行

1. 读取三份用户附件，核对正式普通入口与vNext领域的调用、写入、推进和快照路径；静态解析实际加载的数据数量。结果见audit.md。
2. 本机执行Godot版本检查，结果：`4.6.3.stable.official.7d41c59c4`。
3. 执行现有vNext focused验证通道：**导入/脚本扫描通过，23个测试脚本通过，进程退出0**。逐步骤耗时、状态见[结构化结果](verification-results.json)。这些耗时是测试运行耗时，不是全世界一年仿真的性能指标。
4. 用独立Python整数/Fraction计算复核验收文件中22个用例的数值字段，包括分配、积分、工资税、消费、生产、价格、人口覆盖、在途守恒、火力、媒体、席位和银行账务。具体被复核字段见verification-results.json；未把对应集成行为标为已实现。
5. 检查45个验收ID唯一且连续、W00..W21共22个任务、算法/运行规则引用、文档链接、JSON可解析。

测试命令：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --version
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  'D:\wwo\wwo\tools\run_vnext_validation.py' `
  --root 'D:\wwo\wwo' `
  --godot 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --suite focused
```

本机原始日志：[vnext-focused.log](../../../local-artifacts/architecture-review-20260908/vnext-focused.log)。日志被.gitignore忽略；文档包内保留了结果摘要与日志内容hash。Python启动器原先登记的3.14路径不存在，第一次尝试未启动测试；随后改用桌面bundled Python完成上述验证，没有修改系统Python配置。

## 尚未执行，也不宣称通过

- 本方案T01..T45对应的**新世界实现测试**；acceptance.json是待落实的测试规格。
- 整个仓库的run_validation.ps1、现有vNext的long-run通道。
- 新算法在151政治单元完整经济/社会/战争世界上的一年性能、长期平衡和参数敏感性。
- 新入口的人工玩家旅程、Windows发布导出及用户验收。

本次仅新增本目录的设计文档、验收数据与验证摘要。没有修改游戏源代码、资料初值、项目入口、现行架构决策或用户存档。测试导入产生的未跟踪.gd.uid已清理；普通Godot缓存保留。

## 如何解读结果

原有focused通过说明当前独立领域有可复用的回归基础。数值复核说明方案所列部分算例前后一致。**两者都不证明新的全世界体系已实现，也不证明这些社会经济参数符合历史。** 后续工作必须按execution.md逐项把模型落实到生产链和真实验收。
