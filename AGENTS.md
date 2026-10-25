# 工程代理指南

## 执行规则

开工前读取本节。用户本次指令优先。

- 只阅读相关代码、实现并保存修改，说明未解决的问题。
- 不主动计算或比对 SHA256、MD5，不生成指纹清单。
- 不添加或运行额外门禁、验收矩阵、证据包、探针或对应脚本。
- 不自行运行全量测试、全仓库回归、启动测量或审计。用户未要求时不运行检查。
- 不执行无关 Git 操作。没有执行的工作不得声称通过。
- 不绕过自动审批拒绝；此前被拒绝删除的缓存路径和原因保留在当前 UI 说明。
- 说明使用短句。单个资料缺口不阻止继续实施不依赖它的工作。
- 委派时把执行规则传给每个子代理。

## GitHub 开发基线

- 唯一正式开发基线为 `main`；一个任务一个短期分支或PR，经必要检查和审查后进入main。
- 普通PR使用 `Main validation` 的轻量检查和有界正式领域回归；旧完整流程保持手动。资料缺失、跳过或未运行不可写为通过。
- Windows构建与Release独立手动授权；不因普通PR导出，不自动promote。历史候选按固定提交与私有附件恢复。
- 军事、经济及独立研究保持隔离，不自动合并、删除或移植策略。不建立永久主线副本。

## 构建产物保留

- 内部预览统一使用`tools/build_preview.ps1 build --version R数字`。禁止另建手工导出候选目录；该入口完成技术校验、候选登记和自动清退。没有正式运行输入变化时不重导出。
- 用户明确通过实机验收后，使用同入口的`promote R数字 --acceptance "用户确认内容" --execute`提升版本并清退旧普通回退。不得把技术导出成功当作实机验收。
- `tools/build/preview_policy.json`与`builds/preview_registry.json`管理保护和候选状态。R57未验收前保留R56。正式Release、R19/R30、原始来源、许可证和未知资料不进入清理范围。
- 地貌制作通过带输入/输出元数据的增量recipe执行。R50—R57脚本默认复用现有目录；明确重制才传`--rebuild`或`--refresh`并声明临时预算。不得为普通预览重新下载原始资料。

- 独立Windows预览正常导出完成后，保留当前预览、前一个必要回退及 `builds/windows/` 有效正式发布内容。
- 再清理已明确被替代、没有独立保留要求且未被其他工作线使用的旧预览。不得在新构建完成前删除唯一回退，不得覆盖旧预览来伪装清理。
- 构建日志仅在需要处理导出问题时保留。已完成且没有独立用途的导出日志和临时PCK可以清理。不得据日期或扩展名批量删除研究资料、正式资源、UID、导入配置或经济工作线输出。
- 每次删除前确认绝对路径位于本项目已授权范围。此前审批拒绝的文件和目录保持原状。无法确认用途时保留并报告。

## 项目与当前入口

项目为 `D:/programs/WWO/wwo`，使用 Godot 4.6.3 标准版和 Compatibility。正式入口为 `scenes/formal/formal_world_menu.tscn` → `scenes/formal/formal_world_main.tscn`。

`FormalWorldApplication` 连接场景、WorldBootstrap、WorldState、SimulationStep、FormalPersistence、HistoricalLoader、FormalWorldPresenter、MainShell 和 GlobeRenderer。当前说明为 `docs/ARCHITECTURE.md` 与 `docs/UI_INFORMATION_ARCHITECTURE.md`。不恢复旧 FormalWorldSimulation、EconomyService、组件注册表、启动版本互锁或核验入口。

## 实现约束

- UTF-8 与强类型 GDScript。单个组件承担原有职责。
- 界面显示并发出请求，计算留在现有领域实现，世界事实保存在原有状态中。
- 地图选择不修改人物、国籍、所在地或控制对象。只有明确定位才移动视角。
- 人物账务读取现有 Ledger 与 PersonalEconomy，页面刷新不分配现金或结算工资。
- 历史展示地点不自动创建人口、市场、组织或正式世界地点。未知资料不补成零或现代事实。
- 保留正常格式解析、错误返回、存档读写和实际权限/游戏规则。沿用现有正式持久化路径；新增实际财产扩展所属组件快照，不另建存档服务。
- 不每帧复制全世界页面数据，不全世界预加载，不常驻多套 LOD。静态批次按需要加载，内容或视图变化时刷新。
- 相机与显示偏好属于 UI；正式世界累计时间只属于 GameClock。
- 不升级或替换引擎，不引入 C#、C++、GDExtension、联网、遥测、账户或来源不明素材。

## 权威状态约束

已经过的行动区间按该区间原有效率和上下文结算。正式权限继续在领域执行处判断。存档恢复保留格式、引用、层级与时间一致性约束。不得用 UI、编辑器或隐藏分支绕过世界规则。

当前布局、功能缺口和其他工作线进度集中记录在现有 UI 说明。待办不产生空接口或虚假可点击行为。

正式存档为 `user://formal_world_1900.json`，快照是 `formal_world_simulation_v15`，外层为 `formal_world_exact_variant_v1`。内部存档指纹绑定仍存在，字段与恢复依赖留待单独清理。`VNextWorldRuntime` 是隔离运行容器，旧嵌套存档分支仍保留。市场按实际身份集合处理，不要求恰好 50 个。Prototype、Alpha 旧读取宿主和 V2 旧 UI 已退出正式实现，不从历史指引恢复其入口。
