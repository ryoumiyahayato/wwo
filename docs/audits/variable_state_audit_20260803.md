# WWO 全仓库变量与状态只读审计（2026-08-03）

## 结论摘要

本轮在固定 Base `277a6d801a6eae762e4f6963ceb995a909f80bd9` 上完成静态、只读、全仓库变量与状态盘点。扫描器覆盖 551 个纳入范围的文件、182 个生产 GDScript，并为 1,609 个生产成员声明（1,251 个变量、358 个常量，其中 15 个是 `static var`）逐项生成类型、初值、读写、生命周期、持久化、缓存、UI、近似变量、风险、建议和证据。

没有发现可在本轮直接删除、合并、改名或改型的字段。严格的 H（未使用候选）与 I（证据不足）阈值均为 0；这不等于仓库没有冗余，而是静态证据尚不足以安全删除。近名只保留为比较索引，没有按名称自动判定等价。唯一 G 项是人工确认需要产品边界决策的 `holographic_workspace_runtime.active_character_key`。

本轮确认的最高优先级不是“清理字段”，而是五个状态边界：正式经济 `_last_day_index` 的恢复一致性、正式产品与核心会话的玩家身份边界、历史政治数据中法理/控制语义、正式产品继承的 UI 播种事件、以及正式代码对 Alpha 命名空间数据类/目录的实际依赖。另有正式存档直接覆盖单文件的耐久性风险。没有 P0 结论。

## 基线与执行约束

开始前在 `D:\wwo-variable-audit` 重新执行并记录：

```text
git status --short
<无输出>

git rev-parse HEAD
277a6d801a6eae762e4f6963ceb995a909f80bd9

git branch --show-current
audit/formal-variable-state-inventory-20260803
```

远端只读预检记录：

- `integration`：`277a6d801a6eae762e4f6963ceb995a909f80bd9`。
- `master`：`92bbf22d05d8f1ba31fc2559f8b41d01a002e823`。
- `merge-base(integration, master)`：`92bbf22d05d8f1ba31fc2559f8b41d01a002e823`，`master` 是 `integration` 的祖先。
- PR #37 已关闭且已合并，合并提交即固定 Base；PR #36 已关闭且未合并。
- 与 formal-world 相关的开放项仅发现 Draft PR #19；它不在固定 Base 内，因此本报告不把其未合并内容作为证据。
- 预检时工作树干净，目标分支与授权一致。

本轮没有启动 Godot 编辑器、Headless 导入、统一验证或任何会生成 `.uid` 的动态验证；也没有创建临时验证 worktree。所有结论均明确标为静态证据或人工源码复核。

## 范围与方法

扫描范围：

- `scripts/**/*.gd`
- `scenes/**/*.tscn`
- `resources/**/*`
- `data/**/*.json`、`data/**/*.cfg`
- `project.godot`、`export_presets.cfg`
- `tests/**/*.gd`、`tests/**/*.json`
- `.github/workflows/**/*`
- `tools/**/*`

证据分层：

1. 声明和同文件引用：记录生产成员声明、类型、注解、初值，以及声明文件中的词法读写候选。
2. 跨文件引用：只有 `Owner.member` 或接收者显式类型可解析为 owner 时才进入生产读写者；无法解析接收者类型的 `.member` 单独列为“跨 owner 未解析候选”。
3. 测试、工具和配置：作为支持证据列出，不计为生产写入者。
4. 持久化：收集存档/恢复/迁移/快照语义函数中的字符串键，以及受版本控制 JSON 夹具键；同名键只证明候选关系，不证明某个成员必然持久化。
5. 动态边界：保留非字面 `get/set/call/call_deferred`、动态 `load/preload`、NodePath、信号、资源路径和重要事务/恢复局部变量，避免把静态未命中误写成“未使用”。
6. 人工复核：逐段核对正式时间、玩家、地图/政治、经济、存档、UI、事件/消息/AI 的权威状态和写入边界。

完整逐字段清单见 `docs/audits/variable_state_inventory_20260803.md`，机器可读结果见 `artifacts/variable-state-audit.json`。artifact 使用 `variable-state-audit/v2-normalized`：证据字段中的整数索引指向 38,961 项 `evidence_table`，去除重复字符串但不丢弃证据。

## 总量统计

| 指标 | 数量 |
|---|---:|
| 扫描文件 | 551 |
| 生产 GDScript | 182 |
| 生产成员声明总数 | 1,609 |
| 成员变量（含 static） | 1,251 |
| `static var` | 15 |
| 常量 | 358 |
| 持久化字段候选 | 974 |
| 重要局部状态 | 1,253 |
| 动态调用候选 | 8,261 |
| 动态资源路径候选 | 84 |
| 场景 NodePath 候选 | 63 |
| 信号候选 | 271 |
| 同名跨 owner 分组 | 135 |
| 去前缀近名分组 | 62 |

`dynamic_call_candidates` 是全范围词法候选，不是 8,261 个反射成员访问；它包含 `get/set/call/call_deferred` 形式，并用于提醒静态分析边界。

## A–I 主分类

每个生产成员声明恰有一个主分类。分类不授权删除。

| 分类 | 定义 | 数量 | 本轮处理 |
|---|---|---:|---|
| A | 正式状态、规则或不可变输入 | 1,067 | 保留，维护权威写入边界 |
| B | 可由其他正式状态计算 | 2 | 保留 getter，避免独立写入 |
| C | UI/交互/展示期临时状态 | 83 | 保留交互语义，需行为测试后才可重构 |
| D | 可重建索引或缓存 | 30 | 保留来源与失效语义 |
| E | 存档、迁移或兼容状态 | 124 | 保留兼容边界 |
| F | 测试/隔离产品线/夹具状态 | 302 | 保留隔离；继续验证产品可达性 |
| G | 重复或近似候选 | 1 | 仅人工比较，不主张等价 |
| H | 严格未使用候选 | 0 | 无可直接清理项 |
| I | 静态证据不足 | 0 | 动态不确定性在专门字段中表达 |

B 的两项均有明确来源：

- `FormalWorldSimulation._minute_remainder = total_minutes % 60`。
- `FormalWorldEconomyService.total_hour` 通过注入的 `Callable` 从 `FormalWorldSimulation.total_minutes / 60` 读取。

G 的唯一一项是 `holographic_workspace_runtime.active_character_key`。它是 UI 人物档案键，而核心会话使用 `GameSessionService.player_character`；二者是否应统一取决于正式产品人物规则，不能靠名称或类型自动合并。

## 风险分布

| 风险 | 数量 | 含义 |
|---|---:|---|
| P0 | 0 | 本轮没有确认会立即破坏权威状态的缺陷 |
| P1 | 243 | 优先复核；主要由兼容字段、跨生产文件持久状态写入和人工边界项构成 |
| P2 | 1,047 | 正常保留或需后续证据的状态 |
| P3 | 319 | 低风险不可变输入或低变更风险项 |

P1 是审计排序，不代表 243 个确认缺陷。尤其同名持久化键和多写入文件仍需领域测试确认。

## 优先域人工复核

### 1. 正式时间

确认结构：

- `FormalWorldSimulation.total_minutes` 是正式世界唯一可写累计时间。初始化、推进、恢复和失败回滚均在 `FormalWorldSimulation` 内完成（`scripts/formal/formal_world_simulation.gd:14,26-55,86-109`）。
- `_minute_remainder` 是只读 getter；`total_hour` 是经济服务向正式时间注入的只读视图（`scripts/formal/formal_world_simulation.gd:15-17,136-137`；`scripts/formal/formal_world_economy_service.gd:28-35`）。
- `date_time()` 通过 `V2DateTime.from_total_hour()` 生成日历显示，再加入分钟余数；没有发现第二个可写年月日时钟（`scripts/formal/formal_world_simulation.gd:71-74`）。
- UI 的 `sim_paused`、`sim_speed` 是推进控制，不是累计世界时间；正式应用覆写推进和日期显示入口（`scripts/formal/formal_world_application.gd:36-55`）。
- v2 存档同时保存 `total_minutes` 和派生 `minute_remainder`，恢复时验证余数和经济 `total_hour` 一致；v1 兼容路径可重建分钟（`scripts/formal/formal_world_simulation.gd:77-83,140-166`）。

结论：保留 `total_minutes`、`_minute_remainder` 和 `total_hour` 的当前权威/派生关系。不要把 `minute_remainder` 的持久化副本当成第二个权威时间。

P1 候选：`FormalWorldEconomyService._last_day_index` 随经济状态持久化并可独立恢复，但 `_validate_state()` 没有验证它与权威 `total_hour / 24` 的关系（`scripts/formal/formal_world_economy_service.gd:212-220,237-258,487-500,805-838`）。过大的 `last_day_index` 会使后续满足 `day_index <= _last_day_index` 的日结直接返回，因此可能跳过未来日结；过小值是否会造成重复日结，现有静态源码证据不能确认，需要后续行为测试。此项需要单独修复任务和跨日/存档回归，本轮不改行为。

### 2. 玩家与人物身份

确认结构：

- 核心会话的玩家对象是 `GameSessionService.player_character`；人物目录另持有稳定 ID `CharacterRosterService.player_character_id`。对象与 ID 是不同层次，不应按近名合并。
- `GameSessionService.player_character` 的生产写入位于 `set_player()`、`clear()`、`transfer_player()`，以及继承事务回滚和存档恢复的直接提交（`scripts/character/game_session_service.gd:24-42,75-77`；`scripts/character/succession_service.gd:257-280`；`scripts/save/game_save_service.gd:476-490`）。
- 核心存档键 `selected_country_id` 实际由 `GameSessionService.player_character.country_id` 生成，是 v1 存档兼容字段，不是半球 UI 的 `selected_country_id`（`scripts/save/game_save_service.gd:203-228`）。
- 正式应用继承 Holographic Workspace 的 `active_character_key` 和 `_character_profiles`，但没有接入 `GameSessionService.player_character`。这可能是“展示角色原型”与“权威玩家人物”尚未合流，也可能是产品刻意分层；当前证据不足以合并。

结论：保留对象、稳定 ID、UI 档案键和地图选择 ID。P1 后续任务应先定义正式产品的玩家权威来源，再考虑把存档恢复/继承回滚的直接赋值收口到一个经过重验的提交入口。

### 3. 地图、政治单元与经济体映射

确认结构：

- 正式地图加载 151 个历史政治单元，经济服务维护 50 个高细节经济体；一个经济体可覆盖多个政治单元（`scripts/formal/formal_world_economy_service.gd:3-17,46-80`）。
- `economy_polity_ids` 是经济体到政治单元的正向索引，`economy_by_polity_id` 是反向索引，`_crosswalk_records` 是加载期原始映射缓存；它们是 D，不是重复字段（`scripts/formal/formal_world_economy_service.gd:19-23,306-324,327-423`）。
- `country_states[*].polity_ids` 是随经济快照保存的自描述映射；旧 schema 缺失时从权威索引补齐（`scripts/formal/formal_world_economy_service.gd:212-258`）。它与内存索引近似，但有存档兼容语义，不能直接删除。
- `polity_summary()` 的 `economy_entity_id` 是 UI/查询投影，不是新的 owner（`scripts/formal/formal_world_economy_service.gd:190-205`）。

P1 产品语义候选：历史数据记录 `status`、`relationship` 和 `controller_id`，没有独立 `sovereign_id`；UI 历史投影把同一个 `controller_id` 同时写入 `sovereign_id` 与 `controller_id`（`scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd:111-120`）。因此当前实现不能证明“法理归属”和“实际控制”已分离。需要先定义 1900 数据规则和迁移策略，不能仅改变量名。

### 4. 经济所有权与记账

正式经济当前是国家/经济体聚合模型：

- `country_states[entity_id]` 持有人口、收入、产能、基础设施、库存、价格、日指标、黄金储备、贸易差额、关税收入和最近结算小时（`scripts/formal/formal_world_economy_service.gd:327-403`）。
- `shipments`、`routes` 和 `history` 由同一服务管理；库存转移在来源扣减、到达时计入目的地（`scripts/formal/formal_world_economy_service.gd:469-500,503-655`）。
- 没有在正式产品链中发现独立企业、家庭、政府或运输商账户余额；这些更细粒度 owner 主要存在于 Alpha/V2.x 产品线或数据夹具。不能把它们与正式聚合 `country_states` 当成重复账本。

边界事实：正式经济实例化 `AlphaHistoricalWorldEconomyData`，并读取 `res://data/alpha/commodity_market_1900.json`（`scripts/formal/formal_world_economy_service.gd:15,37,61-70`）。因此 Alpha 目录并非整体不可达：该数据类的 16 个成员按 A 保留，其余未发现正式入口的 Alpha 状态按 F 隔离。路径/类名仍带 Alpha 是架构命名风险，不是删除证据。

### 5. 存档与恢复

仓库存在多条相互独立的存档协议：

- 正式世界：`user://formal_world_1900.json`，模拟 schema v2，内嵌经济 schema v1–v3 兼容（`scripts/formal/formal_world_simulation.gd:8-9,77-133`；`scripts/formal/formal_world_economy_service.gd:212-258`）。
- 核心会话：`SAVE_VERSION = 1`，手动/自动槽，使用 `AtomicJsonFileStore.write_verified()`、备份和恢复校验（`scripts/save/game_save_service.gd:4-22,203-228,246,476-493`）。
- V2.2、V2.3 和 Alpha 各有版本、迁移或夹具边界；同名键不代表同一协议。

P1 耐久性候选：正式 `save_to_user()` 直接以 WRITE 打开目标文件并覆盖，没有临时文件、原子替换、备份或摘要；中断可能失去上一个可用存档（`scripts/formal/formal_world_simulation.gd:112-133`）。它与核心存档的原子写入能力不一致。应在单独任务中复用经验证的原子存储策略，并保持正式 schema 兼容。

### 6. UI 导航与展示状态

- `selected_*`、`hover_*`、`info_open`、旋转/拖拽和面板状态是 C；它们表达不同交互阶段，不是可按后缀合并的同义变量。
- `_last_summary` 是正式应用绘制用的最近摘要，推进/加载后刷新，绘制时读取；它是 C，不是独立模拟事实（`scripts/formal/formal_world_application.gd:9-12,32-38,58-60,102-117`）。是否每帧重算或继续缓存需性能证据。
- `_country_by_id`、`_region_by_id`、屏幕投影和几何边界等 D 项有查询/绘制性能语义；删除前必须验证建立与失效路径以及 1280×720 交互性能。

### 7. 事件、消息与 AI

- 核心会话有可持久化、有限长且验证顺序的 `WorldActivityService`（`scripts/simulation/world_activity_service.gd:1-18,21-104`）。
- Holographic Workspace 自己在 `_seed_world_events()` 中从机构议程生成 `_world_events`、`_event_by_id` 和 `activity_unread`（`scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd:68-70,475-499`）。正式应用继承这条展示链，但没有连接正式模拟事件服务。
- V2.2 因果事件、V2.3 消息/通知/账本、Alpha 事件和核心世界活动各属不同产品线/协议；没有证据支持按 `events/messages/notifications` 名称合并。
- 正式世界目前没有确认的权威 AI 状态入口；其他产品线的 AI 成员不能据此搬入或删除。

P1 产品边界候选：正式 UI 展示的“世界事件”目前由展示数据播种，而不是正式模拟产生。应先决定正式事件的真实性、可见性和存档规则，再选择复用 `WorldActivityService` 或建立正式专用服务。

## 高风险与高价值清单

| 优先级 | 项目 | 证据 | 结论 |
|---|---|---|---|
| P1 | `_last_day_index` 可独立恢复 | `formal_world_economy_service.gd:237-258,487-500,805-838` | 增加与权威小时一致性校验或在兼容迁移后派生 |
| P1 | 正式存档直接覆盖 | `formal_world_simulation.gd:112-133` | 单独任务采用原子写入并保持 schema |
| P1 | 玩家对象/ID/UI 档案三层边界 | `game_session_service.gd:8,24-77`；`holographic_workspace_runtime.gd:36` | 先定正式产品玩家权威来源 |
| P1 | `controller_id` 被投影为 `sovereign_id` | `holographic_workspace_historical_evidence.gd:111-120` | 先定法理/控制产品规则与数据迁移 |
| P1 | 正式事件由 UI 播种 | `holographic_workspace_runtime.gd:475-499`；`formal_world_application.gd:2` | 建立正式事件权威边界 |
| P2 | 正式代码依赖 Alpha 命名空间数据 | `formal_world_economy_service.gd:15,37,61-70` | 记录为共享历史数据或迁移命名，不删除 |

## 重复与未使用结论

- 135 个同名跨 owner 分组和 62 个去前缀近名分组仅是检索入口。`current/selected/active/player` 等前缀经常编码时间、生命周期或权限差异。
- G 仅 1 项，且是产品边界候选，不是删除候选。
- H 为 0：没有成员同时满足“无生产读写、无未解析跨 owner 引用、无动态/场景/信号、无持久化、无测试/工具/配置证据”的严格条件。
- I 为 0：无法静态解析的风险已在每行 `dynamic_access_unresolved`、`ambiguous_external_*` 和全局动态候选中显式保留；没有把这种不确定性误记成 H。
- 本轮不建议任何自动清理。分组和最小批次见 `docs/audits/variable_cleanup_candidates_20260803.md`。

## 静态验证与可复现性

最终验证不启动 Godot，包含：

- 扫描器同路径连续运行两次，JSON 与 Markdown 哈希逐字节一致。
- 生产声明覆盖校验：扫描器产出 1,609 个唯一声明位置，独立声明正则未发现遗漏。
- JSON 可解析、每个成员恰有 A–I 一个分类、A–I 计数之和等于 1,609。
- 所有生成差异只位于授权文档、artifact 和必要的只读 `tools/audit_*`。
- 扫描器不含网络调用，不写生产/测试/工作流文件。
- `git diff --check` 通过；没有 `.uid` 生成。

标准复跑命令如下。它从 PR 最新 Head 取得独立的检出门禁值，继续把原始审计 Base 写入报告，并把两次输出放在仓库外临时目录。实际检出 Head 只出现在扫描器的运行输出中，不写入提交产物，避免产物对其所在提交 SHA 形成自引用。

```powershell
$repoRoot = 'D:\wwo-variable-audit'
$expectedHead = git -C $repoRoot rev-parse HEAD
$reportBaseSha = '277a6d801a6eae762e4f6963ceb995a909f80bd9'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("wwo-variable-state-audit-" + [guid]::NewGuid().ToString('N'))
$run1 = Join-Path $tempRoot 'run1'
$run2 = Join-Path $tempRoot 'run2'
New-Item -ItemType Directory -Path $run1, $run2 | Out-Null

python -B (Join-Path $repoRoot 'tools\audit_formal_variable_state.py') `
  --root $repoRoot `
  --expected-head $expectedHead `
  --report-base-sha $reportBaseSha `
  --json-output (Join-Path $run1 'variable-state-audit.json') `
  --markdown-output (Join-Path $run1 'variable_state_inventory_20260803.md')

python -B (Join-Path $repoRoot 'tools\audit_formal_variable_state.py') `
  --root $repoRoot `
  --expected-head $expectedHead `
  --report-base-sha $reportBaseSha `
  --json-output (Join-Path $run2 'variable-state-audit.json') `
  --markdown-output (Join-Path $run2 'variable_state_inventory_20260803.md')

$hashes = [ordered]@{
  run1_json = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $run1 'variable-state-audit.json')).Hash
  run2_json = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $run2 'variable-state-audit.json')).Hash
  committed_json = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot 'artifacts\variable-state-audit.json')).Hash
  run1_markdown = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $run1 'variable_state_inventory_20260803.md')).Hash
  run2_markdown = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $run2 'variable_state_inventory_20260803.md')).Hash
  committed_markdown = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot 'docs\audits\variable_state_inventory_20260803.md')).Hash
}
$hashes
[ordered]@{
  json_runs_match = $hashes.run1_json -eq $hashes.run2_json
  json_matches_committed = $hashes.run1_json -eq $hashes.committed_json
  markdown_runs_match = $hashes.run1_markdown -eq $hashes.run2_markdown
  markdown_matches_committed = $hashes.run1_markdown -eq $hashes.committed_markdown
}
```

本次连续两次复跑及仓库产物的确定性哈希如下，三方逐字节一致：

- `artifacts/variable-state-audit.json`：run1 `4B3C0FCC734A304AD7BA7C4AE7987B5DB28663A33914162A0506645C55ECB75A`；run2 `4B3C0FCC734A304AD7BA7C4AE7987B5DB28663A33914162A0506645C55ECB75A`；仓库产物 `4B3C0FCC734A304AD7BA7C4AE7987B5DB28663A33914162A0506645C55ECB75A`。
- `docs/audits/variable_state_inventory_20260803.md`：run1 `0B7090A0944B3BD5F08B0D9D06086782713B6DD0C8694128AAB64BCFCC321BFE`；run2 `0B7090A0944B3BD5F08B0D9D06086782713B6DD0C8694128AAB64BCFCC321BFE`；仓库产物 `0B7090A0944B3BD5F08B0D9D06086782713B6DD0C8694128AAB64BCFCC321BFE`。

## 本轮不做

- 不删除、合并、改名、改型任何生产字段。
- 不修改生产脚本、测试、工作流、数据或资源。
- 不启动 Godot 或声称动态、真机、性能、导出验证通过。
- 不把静态未命中当成不可达证明。
- 不合并 PR，不把 Draft PR 标为 Ready。
