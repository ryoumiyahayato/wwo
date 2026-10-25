# GitHub main治理 · 2026-10-25

本轮只迁移线上开发流程、CI和当前说明，准备旧主线退出。没有游戏玩法、经济算法或地貌修改，没有新EXE、Release、候选promote，也没有合入研究代码。

## 核对基线与恢复

- GitHub默认分支为main。开工main是 `2be78dee796cda0e70478f6b4435ac9505a5a936`。
- `archive/main-wwo-r57-g21-20261024` 指向同一提交，完整Git树无差异。
- `canonical/current-world` 指向 `28cdc2dc37c68161dc7b3a3254692980cc75e972`；它是main的历史祖先，独有提交0，main领先22提交。结论来自提交图和差异，不依据名称。
- 工作分支 `chore/main-ci-governance-20261025` 从上述main新建，不建立永久主线副本。
- 构建登记在 `docs/archive/main-wwo-r57-g21-20261024/build-identity/preview_registry.json`：R57代21=CANDIDATE、accepted=false，R56=ROLLBACK。归档登记和私有附件保持不变。
- 历史代21用上述完整main提交恢复；旧R12用上述完整canonical提交恢复。README的恢复入口改为main及固定提交，`tools/archive/restore_main_resources.py` 继续按原清单恢复精确资源，不依赖旧分支名。归档清单中历史branch字段与历史记录不改写。

## CI迁移与边界

原13份工作流中12份引用canonical；既包括触发目标，也包括4份正式领域流程内的git fetch/diff基线。Windows流程原来对旧主线PR与push自动导出，push还会覆盖prototype-latest附件。

现在普通main PR与main push只自动运行 `Main validation`：

| 稳定检查名 | 范围 | 上限 |
|---|---|---|
| Source checks | 合并结果差异空白、修改的Python/JSON语法、actionlint 1.7.7检查Actions语法 | 5分钟 |
| Formal economy and person | Godot 4.6.3导入；既有个人账务、双雇主、有限原料交易入口 | job 15分钟；每个引擎进程240秒 |

PR验证GitHub生成的合并结果，没有路径过滤，避免文档PR缺少必需状态。新增PR、更新、重开、改目标及退出Draft都能触发。完整诊断保留在Actions任务日志，并写入任务摘要，不额外上传artifact；超时、缺资料、引擎错误、退出码失败、缺少有效测试完成行或非零失败数均不通过。负例按已有 `tools/run_validation.ps1` 的规则判断业务拒绝，不能因Godot退出0就忽略引擎错误。没有修改测试文件、断言或容差。

原有经济完整回归、自治长跑、精确持久化、组织/人物/空间/时间、vNext与历史资料检查保留原步骤，改为手动入口。军事实验只手动运行。原workflow中活动基线引用均改为main。独立分支上的历史workflow不在本轮修改范围。

Windows流程只在main上明确手动输入 `BUILD_WINDOWS_CANDIDATE` 才构建；`publish_draft` 默认false，另行请求时只创建独立draft prerelease，不覆盖旧Release或附件，不promote。普通工作流默认contents:read。手动城市分片生成器禁止在main上直接推送，结果必须经短期分支PR审查。

自动检查不恢复全量地图BIN，不生成GB级候选包，不安装导出模板。原料交易依赖的真实第30日存档已经在Git归档中，复制到隔离APPDATA使用，不接触玩家五槽。Windows完整安装包与完整游戏启动仍依赖归档运行资源；`tools/build_preview.ps1`、`tools/build/preview_policy.json` 也需从私有备份恢复。本轮没有把这些未运行路径写成通过。

本地实际检查：Godot版本 `4.6.3.stable.official.7d41c59c4`；隔离配置/数据/缓存目录导入成功；个人账务104项、双雇主1166项、有限原料交易136项，均0失败。actionlint与diff空白检查通过。首次导入因沙箱本地监听和配置目录不可写失败，设置隔离目录并允许正常本地监听后重试成功；未关闭错误检测。线上PR首次运行中源码检查与全部领域回归步骤实际通过，三个测试完成数同本地；最终job因Actions artifact配额已满而失败。普通CI改为保留完整任务日志及摘要，不依赖额外artifact上传，未删除任何旧附件，也未放宽检查。修正后的线上PR运行结果在本轮最终交付中另行列明，不以本地结果替代。

## main保护：实际阻塞

开工分支接口返回 `protected:false`，保护的required checks为空。保护详情读取返回403 `Resource not accessible by integration`；规则集接口返回403：`Upgrade to GitHub Pro or make this repository public to enable this feature.`。仓库是private。元数据的admin:true不能证明当前集成具有Administration权限。

因此本轮没有成功设置或验证服务端保护。没有通过改写别的分支、改变仓库可见性或伪造状态绕过。负责人需保留私有性并决定启用支持私有仓库保护的套餐/归属，再使用具Administration权限的身份设置：

- main禁止force push与删除；新源码必须经PR，管理员也受约束。
- 仅在本次PR已产生成功结果后，把 `Source checks`、`Formal economy and person` 设为必需检查；要求分支最新、讨论解决。不要把手动长跑或Windows构建设为每个源码PR必需条件。
- 当前为个人仓库，不擅自强制一个无法满足的外部批准人数；可先设required approvals=0，待具备独立审查者后单独提升。
- 正式Release仍走独立手动请求及实机验收，不能把保护通过当作promote。

## 优先旧PR的源码核对与处理范围

下表为迁移前真实差异，独有提交按main...head计算。保留不等于可直接合并；旧PR没有新的成功检查时不得标作通过。

| PR | 迁移前目标 | head独有提交/文件 | 当前用途及决定 |
|---|---|---|---|
| #96 | canonical | 6/5 | OHM固定获取记录、验证器、8项测试及旧验证器接线。main未包含；保留为面向main的独立资料审查，需重审当前tools接线，不下载1.3GB PBF |
| #97 | canonical | 15/58 | R2人物绑定、UI、地图及专用测试；触及已被R57替换的旧运行接口。保留Draft，面向main逐项摘取审查，不能整树回灌或宣称全已合入 |
| #112 | canonical | 1/18 | 删除17份Task1实验文件及实验CI的撤回提案；这些文件仍在main。保留Draft独立隔离审查，不自动执行军事删除 |
| #115 | canonical | 1/364 | 历史Python Economy Lab及迁移说明，main未包含。保留Draft，只迁移PR目标，不合入、不删除、不接入Godot |
| #116 | canonical | 4/6 | 当前实际是6份人物手册/存档恢复原型文档；PR原body只写4份。保留Draft，面向main重新核对R57接口，不将R12原型当作可直接接入实现 |

没有足够源码依据证明上述整个PR均可废弃，因此不关闭。治理PR合入后才将以上5个PR改为main目标；不修改head内容，不自动合并。其他开放PR #77、#105—#110、#113、#114保持原目标和Draft状态。

## 研究与其他分支

逐支查看了提交包含关系及实际差异路径。所有 `experiment/`、`backup/military-person-attachment-20261014-v1`、`evidence/war-step-cost-windows-20261009T191132` 的独有工作实际位于 `experiments/war_resolver/`，不是仅据名称分类。`archive/military-full-20261024` README明确军事接令/撤权归档且与main无共同祖先；绝不能推断已合入。`feature/military-capability-simulation` 含独立军事领域修改；军事review两支及organization review支含独立研究文档。

`docs/local-economy-review-20261013`、`integration/formal-economy-20261014`、`research/economy-lab-migration-20261014` 分别含经济研究资料、较大整合代码和历史Lab。`checkpoint/trusted-wave2b1-20260823` 仍有main未含提交。`local-sync/current-world` 无共同祖先，不能作重复主线清退。除前述5个PR目标迁移外，这些分支、研究PR与隔离边界均不变。

旧主线删除仅限精确两支：`archive/main-wwo-r57-g21-20261024`、`canonical/current-world`。执行前必须再次读取远端tip，确认main包含它们、治理PR已合入、5个旧PR已迁移且没有其他PR仍以它们为base；若tip改变先停止。恢复依靠main可达的固定提交和原附件。未确认权限或执行结果时保留分支，交付精确CLI，不声称已删除。本轮最终交付另列实际删除结果。

下一项只按 [巴黎自主经营独立PR范围](PARIS_AUTONOMOUS_ENTERPRISE_SCOPE_2026-10-25.md)开展。本轮到治理与范围制定为止。
