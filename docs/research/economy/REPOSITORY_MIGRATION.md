# 经济源码归属与研究迁移

2026-10-14。此次整理不修改经济算法，不切换正式默认旧经济入口，不修改真实玩家存档。

## WWO

私有仓库：[ryoumiyahayato/wwo](https://github.com/ryoumiyahayato/wwo)。继续已有 [integration/formal-economy-20261014](https://github.com/ryoumiyahayato/wwo/tree/integration/formal-economy-20261014)。此前阶段提交为 [e17db82f](https://github.com/ryoumiyahayato/wwo/commit/e17db82f1c2061266ef99f28741869af659165fa)。此次在该提交上加入已完成的企业资金压力、独立金融授权、劳动反馈、配置与页面接线，以及十五算法研究源码快照。没有合并或推送 canonical/current-world。

正式实现留在 `scripts/world/`，行动、时间、恢复和必要 UI 依赖留在原目录。资金压力组合继续显式使用 `--formal-stratified-economy --formal-liquidity-policy`。默认旧经济不变。已有 30 日、50 日开发运行结果仍是原场景结果，迁移不重新宣称这些行为通过，也不作全国或历史参数保证。

研究保存于 [research/economy/fifteen-algorithms](../../../research/economy/fifteen-algorithms/README.md)。来源目录、分支、基点及三个工作区修复见该 README。采用普通 Git 目录，不复制嵌套 `.git`，不用 submodule。`.gdignore` 隔离 Godot 导入。核心包括 ProgrammeWorld、Round6、原 economy.py、库存承诺及 goal_cycle01 现金和支付。保留必要配置、已有检查和方法来源说明；正式游戏不调用它。

十五算法目录原 origin 是本地研究副本，不能称为旧 Lab 云端已经包含十五算法。原本地研究仓库及两个集成研究工作树不修改。

## Economy Lab

私有仓库：[ryoumiyahayato/wwo-economy-lab](https://github.com/ryoumiyahayato/wwo-economy-lab)。旧 main 基点为 `48b280a37be8f5fd72f0c277f4ae435e675efa1f`。归档目标为 [archive/economy-lab-before-sandbox-20261014](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/archive/economy-lab-before-sandbox-20261014)。它保留旧 main 全树和祖先历史。原 main、Round3–Round6、goal-cycle-01、goal-cycle-02 和 controlled-workbench 分支不删除、不重写；独有内容仍可从各原分支访问。

新的日常入口为 [sandbox/main](https://github.com/ryoumiyahayato/wwo-economy-lab/tree/sandbox/main)。它以旧 main 为父提交，用正常提交移除当前树中的旧产品和历史验证入口，只保留沙盒说明与实验约定。历史仍在父提交和归档分支，不创建孤立历史。切换默认分支后，不改变旧分支名字、提交或显式 clone 引用；旧分支 PR 仍须单独选择目标。默认 clone 和未指定分支的浏览、Contents API 改指向沙盒。WWO 不依赖此默认入口。

## 未迁入内容

不迁入 raw、批量 CSV、重复实验日志、evidence、构建及缓存、临时脚本、真实存档、全量历史 verify/打包入口和未被本版本复用的 goal_cycle03。旧 Lab 云端内容保留原历史；十五算法本地完整历史及原结果留在原研究目录。军事、地图、政治等独立仓库不在本次迁移范围。没有创建跨仓库自动同步。
