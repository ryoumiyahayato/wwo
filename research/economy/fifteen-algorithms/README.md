# 十五算法研究源码

此目录保存十五类算法的 Python 研究版本。正式游戏实现位于 `scripts/world/`，不导入这里的 Python。目录内 `.gdignore` 阻止 Godot 导入研究文件。

来源为独立本地仓库 `D:/programs/WWO/research/economy/algorithm-completion/20261009-222452/repo`，分支 `research/fifteen-algorithms-v0`，源码基点 `030de3f69ddff1b050aff25cbbec8d4fa2e93ffb`。该仓库的 origin 是本地 `cycle03-m5-evidence/20261009-191155/repo`，并非 GitHub。原有三处未提交修复一并收入：Round6 计划和实际生产使用未被销售承诺占用的材料，以及对应 `test_programme.py` 短案例。原本地 Git 历史未改动。

`economy_quantity_lab/algorithm_completion/world.py` 的 `ProgrammeWorld` 继承 `network_round6`，继续使用原 `economy.py`、`StockCommitments` 和 `goal_cycle01` 现金、价格与支付机制。相对目录布局保留，bootstrap 的本地导入无需 Economy Lab、网络或 submodule。

保留研究核心、必要祖先模块、现有算法检查、人工研究 fixture 配置及方法笔记。配置不是 1900 年历史参数。研究 snapshot 是实验日志，不是正式游戏完整恢复状态。研究与 GDScript 不宣称全面等价。

## 最小运行

使用 Python 3.12 或更高版本和标准库，从此目录运行：

```sh
cd economy_quantity_lab/algorithm_completion
python -B -c "from world import ProgrammeWorld; from programme_fixtures import scenario; w=ProgrammeWorld(scenario('J1_normal',days=1)); w.step(); print('day',w.day,'orders',len(w.orders),'events',len(w.trace))"
```

这只推进一个研究日，不调用历史矩阵、归档、哈希或验收 runner。保留的旧 runner 和 observer 源码有原有输出及哈希行为，默认不执行。新输出放在忽略的 `.local/` 或 `artifacts/`，不能覆盖来源配置。现有测试可按具体改动选取，不默认运行整套历史验证。

原研究 raw、逐日结果、evidence、临时输出、打包器、全量 verify 入口及未被本版本复用的 `goal_cycle03` 不迁入。早期 Lab 研究留在原远端历史分支；十五算法的完整本地历史和输出继续留在原本地仓库。归属及远端链接见 [迁移说明](../../../docs/research/economy/REPOSITORY_MIGRATION.md)。

后续保留版本在本目录维护。新的独立沙盒在 `wwo-economy-lab`。沙盒结果须经明确选择再接入 WWO，不设置自动双向同步。
