# WWO Formal Refactor B6 — Application boundaries

> 历史记录。下文“当前”仅指记录时的阶段；旧实现、命令及同步要求不再是开发指令。不得据此恢复已删除的宿主、UI、探针或审计门禁。现行入口、WorldState 与 v15 存档见 [当前架构](../ARCHITECTURE.md) 和 [存档格式](../SAVE_FORMAT.md)。

RESULT=PASS

以本轮补充指令为准：累计工作树不阻塞；本轮处理 Application / World Core，完整 Content/Presentation cleanup 留到后续。没有提交、push、merge、PR、reset、clean、stash，也没有启动/关闭用户 Godot GUI。所有验证均为独立 headless 进程。起始与最终 Git HEAD 均为 `622b260bc641036c23efbf6345a548485ac6c475`。

## A. CURRENT APPLICATION

| Metric | Before | After |
|---|---:|---:|
| Lines | 175 | 100 |
| Fields（含 onready） | 32 | 8 |
| Functions | 9 | 9 |
| Direct project class dependencies（去除自身与 Godot built-ins） | 39 | 12 |
| Explicit preload/load | 0 | 0 |
| Declared signals | 0 | 0 |

最终直接项目依赖：HistoricalLoader, WorldState, SimulationStep, FormalPersistence, GlobeRenderer, GlobeController, MainShell, TimeControl, WorldBootstrap, WorldBuildResult, FormalWorldPresenter, SaveOperationResult。

函数数量保持，是因为 `_refresh_ui` / `_refresh_map` 仍是应用刷新协调入口；其原显示实现已退出 Application，未保留任何领域查询返回 API。

## B. APPLICATION RESPONSIBILITY TABLE

| FUNCTION / FIELD | CURRENT PURPOSE（开始时） | TARGET AREA | KEEP IN APPLICATION? | MOVE? | DELETE? | REASON |
|---|---|---|---|---|---|---|
| `historical_content` | 现有显示内容引用（完整边界清理后续处理） | APPLICATION_COORDINATION | YES | NO | NO | 仅用于连接/调度；historical_content 的构造与加载实现已移到 Content |
| `_game_clock` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.game_clock | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_simulation_step` | 时间推进组件引用 | APPLICATION_COORDINATION | YES | NO | NO | 只连接现有组件，不保存另一份领域事实 |
| `_persistence` | 保存/候选恢复组件引用 | APPLICATION_COORDINATION | YES | NO | NO | 只连接现有组件，不保存另一份领域事实 |
| `_provenance` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.provenance | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_historical_evidence` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.historical_evidence | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_political_registry` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.political_registry | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_historical_evidence_view` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.historical_evidence_view | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_political_registry_view` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.political_registry_view | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_economic_evidence` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.economic_evidence | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_economic_static_view` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.economic_static_view | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_population_input_view` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.population_input_view | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_market_registry` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.market_registry | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_market_registry_view` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.market_registry_view | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_economy_service` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.economy_service | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_spatial_catalog` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.spatial_catalog | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_spatial_world` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.spatial_world | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_territory_state` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.territory_state | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_person_overlay` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.person_overlay | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_player_state` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.player_state | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_organization_state` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.organization_state | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_organization_evidence` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.organization_evidence | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_organization_evidence_view` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.organization_evidence_view | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_organization_responsibility` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.organization_responsibility | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_authorization_check` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.authorization_check | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_military_map` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.military_map | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_military_state` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.military_state | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `_military_service` | 当前世界组成引用（非数据副本） | WORLD | NO | WorldState.military_service | Application declaration | 稳定运行结构集中列出组件；真实数据仍由原 owner 保存 |
| `map_renderer` | 场景地图节点引用 | APPLICATION_COORDINATION | YES | NO | NO | 只连接现有组件，不保存另一份领域事实 |
| `map_controller` | 场景输入/相机/选择节点引用 | APPLICATION_COORDINATION | YES | NO | NO | 只连接现有组件，不保存另一份领域事实 |
| `main_shell` | 场景页面节点引用 | APPLICATION_COORDINATION | YES | NO | NO | 只连接现有组件，不保存另一份领域事实 |
| `time_control` | 场景真实时间速度/暂停控制引用 | APPLICATION_COORDINATION | YES | NO | NO | 只连接现有组件，不保存另一份领域事实 |
| `_ready` | 启动、launch meta、build、content setup、场景 signal 连接 | APPLICATION_COORDINATION | YES | 装载 → Content；提示 → Presentation | 内容加载/文本实现 | 启动只编排模块 |
| `_install_world` | 逐个组件安装与刷新 | APPLICATION_COORDINATION | YES | 组件结构 → WorldState | 25 个分散字段安装语句 | 一次安装稳定世界引用；不保存构建载体 |
| `_advance_world` | 调用 SimulationStep | APPLICATION_COORDINATION | YES | NO | NO | 无结算算法 |
| `_on_world_changed` | 读取变化标志，触发刷新/显示错误 | APPLICATION_COORDINATION | YES | 错误文本 → Presentation | 文本拼装 | 不计算日边界或经济结果 |
| `_refresh_ui` | 跨 owner 查询、detached views、页面 summary、refresh | PRESENTATION | 协调回调 YES | 显示实现 → FormalWorldPresenter.refresh_ui | 原数据组装函数体 | 展示投影属于 Presentation，Application 不再是查询集中点 |
| `_refresh_map` | 筛选 city/port records、views/date、renderer.refresh | PRESENTATION | 协调调用 YES | 显示实现 → FormalWorldPresenter.refresh_map | 原数据组装函数体 | 不改 renderer 算法 |
| `_on_action_requested` | 地图/页面/时间 UI request，save/load 调度 | APPLICATION_COORDINATION | YES | save 提示 → Presentation | 文本拼装 | 这里只存在 UI 操作与 persistence request，没有新游戏动作 |
| `_load_world` | 请求独立候选、成功安装、选择有效性处理 | APPLICATION_COORDINATION | YES | load 提示 → Presentation | 文本拼装 | 解码/restore/validation 仍由 FormalPersistence 执行 |
| `_update_map_visibility` | 地图显示和隐藏时 suspend_motion | APPLICATION_COORDINATION | YES | NO | NO | 场景生命周期协调；不改变 camera 算法 |

初始化：WorldBootstrap 创建 world/components；Content 准备当前显示内容；安装 world/step/persistence；连接场景和服务。没有新增 historical parsing 或领域规则。

Signal/wiring：MainShell.action_requested → `_on_action_requested`；MainShell.refresh_requested → `_refresh_ui`；TimeControl.advance_requested → `_advance_world`；TimeControl.controls_changed → MainShell.queue_redraw；GlobeController.selection_changed → MainShell.refresh；GlobeRenderer.input_blocked → MainShell.blocks_map。Application 不声明 signal；具体页面输入仍由 MainShell/Controller 负责。

原查询：person/player/place、political projection、economy summary、组织 view、city/port records，全部移到 Presenter。最终 Application 唯一直接领域查询是 load 后 `candidate.world.political_registry.has_entity(selected_id)`，用于验证 UI selection，不提供统一查询 API。

修改：Application 修改的仍是 UI speed/pause/map mode/labels/visibility/selection；正式世界推进由 SimulationStep，save/restore 由 FormalPersistence。当前 request 分支没有 move/purchase/join/defend 等游戏动作；无需在这里新增 Action Framework。

## C. WORLD CORE

`WorldState` 是安装后的稳定运行组件图：25 个 typed references，0 函数，0 Dictionary 数据副本，0 build metadata。`WorldBuildResult` 保留 world、成功/错误、operation、step/persistence、构建 reference options，只有字段；它不被 UI、Presenter 或 SimulationStep 长期持有。

| Area | Current actual owner |
|---|---|
| time | WorldState.game_clock → GameClock._total_minutes |
| person | person_overlay → VNextNamedPersonOverlay；player_state → 当前有效人物 ID |
| place/spatial | spatial_world → VNextSpatialWorld；spatial_catalog → 静态 topology；territory_state → 当前 controller |
| polity | political_registry → RuntimePoliticalEntityRegistry；控制事实仍由 TerritoryState 保存 |
| organization | organization_state → OrganizationState；organization_responsibility → 既有责任结算状态 |
| economy/market | market_registry → 市场身份/绑定；economy_service → 既有经济、市场运行值 |
| military | military_state → formations/actions/settlement cursor；military_service 执行规则 |
| relationship | 当前正式组织 membership/appointment 关系在 OrganizationState；未发现 Formal 的独立人物关系运行 store，本轮不虚构一个 |
| information | historical_evidence / organization_evidence / provenance 与 detached views 是已装载证据；未发现 Formal 的独立 mutable information store，本轮不新增 |

其他 references：economic_evidence / economic_static_view / population_input_view、historical_evidence_view / political_registry_view / organization_evidence_view / market_registry_view、authorization_check、military_map。它们仍引用既有组件，无复制运行字段。Persistence/Step 的 direct owner references 与 WorldState 指向同一实例；reference 不是第二份 mutable fact。

## D. MOVED RESPONSIBILITIES

- WORLD：Application 的 25 个组成 references 进入 WorldState；WorldBuildResult 改为携带 world，不再重复逐项声明这些组成。
- SIMULATION：无需搬算法；SimulationStep 原顺序和实现完全保留。Application 只调用 advance_minutes。
- RULES：未发现 Application/正式页面/renderer 中需要迁出的领域结算规则；UI spacing、camera、颜色和显示参数没有当成 rules 改动。
- ACTIONS：没有新动作。DefendAction / AuthorizationCheck / MilitaryService 保持；Application 当前其他输入是 UI 操作及 save/load request。
- PRESENTATION：页面 copied records/view 生成、显示统计 summary、city/port map inputs、状态提示进入 stateless FormalWorldPresenter。它有 7 个 static functions、0 fields、0 file IO，不持久保存 WorldState、不修改 domain owner；页面/renderer 仍只收到原 detached 输入。
- CONTENT：HistoricalLoader 的构造/load_current 从 Application 移入 WorldBootstrap.prepare_presentation_content。它只在应用需要显示内容时执行；headless world build 不强制加载显示内容。
- PERSISTENCE：FormalPersistence constructor 改为 WorldState + 明确 reference options；不再接收构建专用 carrier。内部 snapshot/codec/candidate validation/atomic write 保持。
- SYSTEM：增加现有 unittest / FormalTestCase 下的架构检查；没有新框架、bus、locator、cache 或 facade。

## E. APPLICATION REMAINS

1. launch mode / boot coordination。
2. 当前 world、step、persistence 和现有 content 的引用。
3. 四个 scene node references 与 signal wiring。
4. 时间推进请求与 changed metadata 的刷新调度。
5. UI 操作 dispatch、save/load request。
6. 安装成功 candidate 与选择有效性检查。
7. 调用 Presenter 刷新以及地图可见性/生命周期。

## F. NEW FILES

| File | Purpose | Lines |
|---|---|---:|
| scripts/world/world_state.gd | stable runtime component references | 30 |
| scripts/presentation/formal_world_presenter.gd | detached UI/map projections and display status | 52 |
| tests/formal/formal_application_architecture_test.gd | headless world/candidate/install/refresh regression | 82 |
| tests/world_data/test_formal_application_architecture.py | production architecture guard | 98 |

前三个 GDScript 对应 .gd.uid 均存在。此报告本身也是新增文档。验证 logs/manifest 位于 ignored builds/formal-refactor-b6，不是新的产品路径。

## G. MODIFIED FILES

- scripts/formal/formal_world_application.gd — stable-world installation + coordination only。
- scripts/content/world_bootstrap.gd — compose references inside result.world；Content owns optional display-content preparation。
- scripts/world/world_build_result.gd — fields-only build carrier → world + build outcome/options。
- scripts/persistence/formal_persistence.gd — explicit WorldState constructor；candidate references 使用 candidate.world；serialized payload 不变。
- tests/world_data/test_runtime_political_authority_closure.py — 检查 detached UI input 的生成位置从 Application 改到 Presenter，仍要求 bootstrap 后安装。
- `tests/formal/autonomous_formal_world_soak_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_exact_persistence_roundtrip_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_military_authorized_defend_integration_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_person_overlay_integration_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_spatial_authority_integration_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_spatial_persistence_integration_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_economic_boundary_closure_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_integration_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_long_term_balance_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_market_identity_foundation_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_market_snapshot_probe.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_organization_composition_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。 唯一 OrganizationState 断言同时迁到 WorldState 并禁止 Application 副本。
- `tests/formal/formal_world_organization_production_composition_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_organization_responsibility_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/formal_world_ui_binding_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/historical_provenance_foundation_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/formal/runtime_political_identity_foundation_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/variable_state/formal_time_known_defects_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/variable_state/formal_time_stable_contract_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/vnext/current_world_domain_convergence_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。
- `tests/vnext/economic_geography/economic_geography_service_test.gd` — 构建载体字段引用改为 `result.world.<owner>`；断言/测试行为保持。

## H. DELETED FILES

本轮无删除。此前已删除 formal_world_simulation.gd / UID，继续保持不存在。未建立 wrapper、alias、disabled implementation、backup 产品目录。

## I. RUNTIME PATHS

BOOT: formal_world_menu.tscn → formal_world_main.tscn → Application._ready → WorldBootstrap.build → WorldBuildResult.world → Application._install_world → world/step/persistence references；optional content preparation 在 Content。

TIME: TimeControl.advance_requested → Application._advance_world → SimulationStep.advance_minutes → Clock → Spatial → Economy → Organization responsibility review → changed metadata → Application refresh coordination。

SAVE: Application request → FormalPersistence.save_to_user → snapshot（15 fields, v12）→ exact Variant codec → temporary independent candidate validation → AtomicJsonFileStore。

LOAD: Application._load_world → FormalPersistence.load_from_user → WorldBootstrap candidate → restore / validation → successful WorldBuildResult → Application._install_world(candidate.world + services) → UI/map refresh。失败候选不安装。

DEFEND: 调用方传 current hour → DefendAction.execute → AuthorizationCheck → MilitaryService.defend；没有 Application/world forwarding facade；军事 settlement cursor 不作为 current time。

UI REFRESH: MainShell.refresh_requested / Application changed/load handling → FormalWorldPresenter.refresh_ui → copied date / person/place/polity / detached economy+organization inputs → pages；refresh_map → copied city/port + date + detached political/evidence/economy inputs → existing renderer。

## J. VALIDATION

Engine: Godot 4.6.3.stable.official.7d41c59c4。

- `git diff --check`：PASS。
- `<engine> --headless --editor --path D:/WWO/wwo --quit`：初次与最终 import 均 exit 0；无 parse/resource load errors。独立 APPDATA under builds/formal-refactor-b6/user-data。
- `<engine> --headless --path D:/WWO/wwo --check-only --script res://<affected.gd>`：28 个 GDScript PASS。
- `<engine> --headless --path D:/WWO/wwo --script res://<test.gd>`：既有 11 suite 2105 checks / 0 failures；新增 runtime suite 33 checks / 0 failures。
- `<python> -m unittest discover -s tests/world_data -p test_formal_application_architecture.py -v`：5 tests PASS。
- `<python> -m unittest discover -s tests/world_data -p test_runtime_political_authority_closure.py -v`：4 tests PASS。
- menu/main scene load、无 UI world 构造和分段跨小时/跨日推进、Economy/Spatial hour、Organization review、snapshot、candidate restore、失败隔离、成功磁盘 load 安装以及日期/人物页/政治地图 input 刷新均实际执行。

| GDScript suite | Checks | Failures |
|---|---:|---:|
| formal_time_stable_contract_test | 105 | 0 |
| formal_world_integration_test | 66 | 0 |
| formal_military_authorized_defend_integration_test | 115 | 0 |
| formal_person_overlay_integration_test | 60 | 0 |
| formal_spatial_persistence_integration_test | 27 | 0 |
| formal_world_organization_composition_test | 99 | 0 |
| formal_world_organization_production_composition_test | 653 | 0 |
| formal_world_organization_responsibility_test | 400 | 0 |
| formal_exact_persistence_roundtrip_test | 32 | 0 |
| formal_world_economic_boundary_closure_test | 537 | 0 |
| formal_world_ui_binding_test | 11 | 0 |
| formal_application_architecture_test | 33 | 0 |

日志中的 malformed candidate / old schema / unknown authority 等 ERROR 来自负例测试，结果明确拒绝；它们没有被改成 fallback。parse / type / script-load errors 为 0。

没有执行 GUI 人工画面旅程或 export，没有声称视觉/平台验收通过。没有改变地图实现。未提交，因此未执行“提交前全量验证/导出”流程；本轮采用补充指令要求的实际受影响验证。

## K. ARCHITECTURAL TESTS

| Question | Result | Evidence |
|---|---|---|
| Presentation removed → Simulation parses? | YES（静态依赖意义；没有实际删用户文件） | core closure 沿 global class + res:// script path 递归，无 presentation/scene dependency；headless parse |
| UI absent → World can initialize? | YES | runtime test 在加载 UI scene 之前 build/advance；释放 WorldBuildResult 后仍可推进 |
| Persistence independent of UI? | YES | snapshot/restore candidate 在加载 UI scene 前执行 |
| Simulation independent of renderer? | YES | transitive guard + headless runtime |
| Application contains domain algorithms? | NO | forbid settlement/restore/codec/raw parsing/domain query implementation |
| Application is a broad query facade? | NO | 0 public query functions；fields limited to world/services/scene wiring |
| FormalWorldSimulation executable refs? | 0 | scripts/scenes/tests/tools/workflows/project.godot search |

Guard 同时要求 WorldState 与 WorldBuildResult fields-only、UI不接收构建 carrier、Presenter 不保留 state/不写 domain。没有按 LOC 设硬阈值。

## L. REMAINING ARCHITECTURAL DEBT

1. 本轮按指令延期的 Content/Presentation 边界：MainShell / WorldPage / GlobeRenderer / PoliticalLayer 仍依赖 HistoricalLoader；PoliticalLayer.refresh 仍直接 ContentDocument.read(REGIONS_PATH)。Application 的 HistoricalLoader reference 是现有 wiring，本轮未伪装成另一种 service。
2. 当前经济数据与结算仍在既有 FormalWorldEconomyService 内；WorldState 引用这一实际 owner，没有声称本轮完成更深拆分。
3. 非 production 的部分 capture/旧 audit test 仍有 `formal_simulation` 字段绑定（如 tools/map/capture_territory_closure.gd 和 tests/alpha/alpha_economy_ui_audit_test.gd）；这些早于本轮存在，本轮核心 suite 没有调用它们。未恢复旧 facade。

没有发现需要决定新产品规则才能继续本轮的依赖；没有修改经济/组织/军事公式或修复玩法 bug。组织 test 的旧声明位置断言更新是架构目标改变，不是规则放宽。

## M. NEXT RECOMMENDATION

仅下一项：关闭正式 Presentation/Map 对 HistoricalLoader/raw Content 的直接依赖，通过 bounded detached inputs；同时更新相关正式 capture 验证输入。未开始。

## CORE LINE COUNTS

| File | Lines |
|---|---:|
| `scripts/formal/formal_world_application.gd` | 100 |
| `scripts/content/world_bootstrap.gd` | 324 |
| `scripts/world/world_state.gd` | 30 |
| `scripts/simulation/game_clock.gd` | 46 |
| `scripts/simulation/simulation_step.gd` | 93 |
| `scripts/persistence/formal_persistence.gd` | 315 |
| `scripts/world/world_build_result.gd` | 13 |
| `scripts/presentation/formal_world_presenter.gd` | 52 |

本轮新/修改核心脚本均低于 500 行。每个职责均可一句话说明；更关键的是 WorldState 没有业务函数、Application 没有领域查询/结算/持久化实现、Presenter 没有 retained state、Step/Persistence 不依赖 UI。这些边界由结构与运行测试验证。
