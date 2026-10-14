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
