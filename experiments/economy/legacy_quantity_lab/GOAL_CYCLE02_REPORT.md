# Goal Cycle 02 日期采购与价格反馈因果研究

## 结论

SOURCE_CONTINUITY_GATE = PASS

CAUSAL_ATTRIBUTION_GATE = PASS

MODEL_VALUE_ASSESSMENT = MIXED

本轮恢复了真实 Cycle01 封存代码，并验证其原有 353 份冻结结果逐字节一致。完成两次独立、完整的最终正式配置集：每次 59 个案例、89,400 个模拟日，533 份确定性文件的完整集合与 SHA-256 全部相同。运行时间与内存数据独立保存。

价格排序确实改变采购来源、接受订单与物资到货，最终服务总量常被库存缓冲和充分供给掩盖。日期释放规则又限制了哪些报价真正能竞争。N3 在固定愿付上限附近出现可持续至 3600 日的停供振荡；一个事先冻结的局部 N4 候选减少了该损失，但异质限价 holdout 中仍出现明显的 sink 服务转移。因此正确性通过不能解释为模型已经足够真实或适合正式 WWO。

## 版本和预算

- 仓库：ryoumiyahayato/wwo-economy-lab
- BASE_SHA：334d3f546824415604b7645a91a61196fb2bad83
- Cycle01 recovered HEAD：93633b4321dc288bd14b064350cc7fb053529bae
- 工作分支：research/economy-goal-cycle-02
- 最终经济执行 checkpoint / LAST_VALIDATED_EXECUTION_COMMIT：710dac38d82a4d48609e88c9f974a927e9b6c686
- 封存 HEAD：由 handoff/export_manifest.json 记录，避免提交内自引用。
- UTC 开始：2026-10-08T02:39:06Z
- 原截止：2026-10-08T12:39:06Z，未因恢复而重置
- 机制扩展截止：2026-10-08T10:39:06Z；实际只选择一个 N4，无参数扫描、无 holdout 后修改
- 未 push、创建远端 PR、merge、tag 或接入正式 WWO。远端 CI、Windows 和全球 WWO 性能均 NOT_RUN。

32089 字节完整主提示词保存在 GOAL_CYCLE02_USER_PROMPT.txt，SHA-256 为 a8916c9e4f1b3ba0c21db767a47d6f654ee9f4b8f0f5647e02adfe4a1e2eab79。

## 来源与继承验证

原 ZIP 实测 30,775,867 字节，SHA-256 3f19b853ab4c7a2e14055382971d15e8c5c99a4af187083907591247f2834ecf。bundle 与 patch 的实测哈希分别为 9c08d896745b21d70e371e903163569fd258fe598b83985d5e486e230df64555、8f25800585b06dbbb4c50c1715a6c5cde1a78efab7732f93f9ca2d9fc21716b4。

bundle 的 BASE 依赖是真实存在的 334d3f5。通过授权仓库读取取回 374 个唯一 blob，逐一验证 Git SHA；重建的 tree 与 base commit 也精确匹配原 SHA，然后恢复原封存提交。没有用阅读摘取包重造源码。base 的更早父历史为明确的 shallow 边界；交付的源码快照含恢复所需对象与该标记。

先执行 verify_goal_cycle01.py --correctness-only，再运行完整入口。264 项历史检查、42 项 Cycle01 检查、原七类日志破坏、370 份 Round6 冻结经济文件及授权源码 delta 均通过。两个 50 案例、66,000 日的 Cycle01 复验完整进程匹配 353 文件；进一步与原包的 frozen manifest 对照也是 353/353 无差异。Cycle01 的所有原文件与状态未改。

原 Round6 strict verifier 的历史源码哈希差异仍被保留；没有刷新旧 manifest 或 golden 来伪造原严格校验通过。

## 冻结与实验范围

初始 43 配置 manifest：e34955c496b5c6a825a6112b2901adadd54f2cd868a96b0d0a7070e55bcf98f0。

最终 59 配置 manifest：6b2cc5f69b4d09cfec7c32aad16d81ecd1898f56aa774cd24ea5b90091edf8bf。

最终冻结时间为 2026-10-08T03:28:04.732215Z。范围包括：

- M2：8 个 P × R × T 对照，各 600 日
- M3：normal、coal scarcity、recovery 的 N2/N3 × 两类限价，12 个 600 日案例
- M4：相同三场景和限价组，12 个连续 3600 日案例
- 真实 cash 专项：3 个 600 日案例
- S5/S10：N2/N3 各 600 日，共 4 个案例
- 两个新 holdout 家族：N2/N3，共 4 个 600 日案例
- 同一输入的 N4：6 个主矩阵、6 个长矩阵、2 个规模、2 个 holdout，共 16 个案例

原 39 个非 holdout 配置未改变。两个 v1 holdout 家族曾被正确性测试运行 20 日前缀，该暴露明确列为开发记录；另建 v2 家族并在候选前冻结。随后只读检查发现其 T1 demand 增至 6 后仍按 5 配终端资金。在首次执行前，按 600 × 6 × 2000，仅把对应资金从 6,000,000 补到 7,200,000；需求、限价、报价及物理条件不变，原 hash 保留。最终六个 holdout 均没有 CASH 或 TERMINAL_CASH 拒绝。

M2 是独立 P/R/T 处理，不应把其中显式 R_LEGACY 覆盖称为历史 N2。其 mode 字段复用支付适配器；历史 N0/N1/N2/N3 的实现和定义保持不变。

## 主要实体结果

| 场景 | 日数 | N2 | N3 | N4 |
|---|---:|---:|---:|---:|
| normal / nonbinding | 600 | 6000 | 6000 | 6000 |
| coal scarcity / nonbinding | 600 | 6079 | 6079 | 6079 |
| coal scarcity / binding | 600 | 6079 | 4843 | 6019 |
| recovery / binding | 600 | 6000 | 6000 | 6000 |
| normal / nonbinding | 3600 | 36000 | 36000 | 36000 |
| coal scarcity / nonbinding | 3600 | 36079 | 36079 | 36079 |
| coal scarcity / binding | 3600 | 36079 | 28429 | 36019 |
| recovery / binding | 3600 | 36000 | 36000 | 36000 |
| S5 | 600 | 19709 | 19717 | 19717 |
| S10 | 600 | 31995 | 31995 | 31995 |
| mixed-date holdout | 600 | 6000 | 6000 | 6000 |
| asymmetric-limit/scarcity holdout | 600 | 10824 | 10776 | 10825 |

16 个 N2→N3 配对：1 个总量改善、3 个恶化、12 个总量不变。16 个 N3→N4 配对：3 个改善、0 个恶化、13 个总量不变。这里只按总交付分类。

分布没有被总量掩盖：S5 的 N3 总量多 8，但 T8 少 26、T10 少 16；S10 总量相同，却有 T8 少 1279、T18 少 1278，其他 sink 增加。非对称 holdout 的 N4 相对 N3 总量多 49，T4 却少 579、T9 少 670。N4 不应被称为普遍改善。

59 个案例的完整指标见 evidence/final_metrics.json 和 CSV。包括 backlog by sink、实际库存/在途、现金/预留/已付、firm 输入接受量、supplier 份额、生产连续性、报价路径、clamp/tick 与因果计数。

machine_days_inventory 是逐日末端企业 machine 库存的积分；模型没有已安装机器使用状态，installed machine service days 标记 NOT_MODELED，不能将库存积分写成机器服务或福利。

## 日期与价格机制

ReleaseBook 的 timely 与 release_due 同时成立时，在当前固定 lead 下要求 need_by_day 等于 conservative expected arrival。早到且尚未释放的报价并非当日可执行替代。

正常 N3 在 decision day 609 将 D 从 358 调到 360，effective day 610 生效。完成窗口 603—609 的直接本地输入：free stock 0、shipped 420、distinct received identities 14、active physical-unmet 112、PRICE/CASH 0；原 2% 整数步长 7，proposal 365，4x 边界把它限制到 360。

610 日 B2 向 A 以 49 请求 need614、接受 20；D 以 360 面对 need616，B1/B2 分别接受 28/32、各物理拒绝 8。A 对 need616 的 ETA614 虽及时，但 release612 尚未到；D 对 need614 则迟到。因此这对价差标为 NO_MATCHED_COMPETITIVE_OPPORTUNITY。D 后续高报价没有创造超过其 60/日瓶颈的新增销售。

完整真实链示例包括终端收到需求、own plan/material bucket、已查报价、need/date/release、真实请求/接受、dispatch/arrival/锁价付款，以及同一买方库存池随后发生的 consumed/produced/terminal 事件。没有编造某一煤或钢单位必然进入某一台机器的谱系。

## 正交对照与实际后果

P_UNIFORM 下，R_LEGACY 与 R_PRICE_FIRST 的全部实体轨迹相同。固定 R_LEGACY 时，报价异质性改变付款，但资金不约束时实体轨迹不变。异质报价加价格优先才改变实际采购来源。

同 ETA 异价的 price-first 案例有 2117 个严格匹配机会、2105 个第一轮价敏接受 dated-needs、2102 个相关实际 arrival events。混合 lead 对应 1200、1188、1186。匹配机会是按 day/boundary/buyer/good/need/date 去重并要求真实当前 ATP 正量；全价相同组的“异价匹配”定义为零。

两个异价 R 对照均在 day1 首次产生 matching/接受差异、day2 出现 shipment/production 差异、day3 出现 arrival 差异。terminal delivery 没有分叉。独立轨迹比较分别有 1191/1194 个买方实际到货日与数量 bucket 不同；若按 accepted-need 的供应商来源划分，则为 3027/3077。后者不能冒充买方服务量差。

supplier 构造、firm 插入与 request 列表反转在稳定 ID 下保持一致。稳定 ID 重标号回映射后，day2 真实库存/生产/现金已有差异，但最终 sink 服务相同。这是政策 tie-break 敏感性，不是容器不确定性。

## 愿付上限与现金

主 binding 组煤限价 110、钢限价 330，参考过 Cycle01 已知价格范围，不是对旧结果的盲测。

coal scarcity 的四格特别明确：N2 nonbinding、N3 nonbinding、N2 binding 都交付 6079；N3 binding 为 4843。49 日 A 从 110 升 112，50 生效；56 日出现 free400、shipped0、accepted0、PRICE798、CASH0，降回110。此后 110/112 双窗重复，3598 日仍然存在。3600 日损失扩大到 7650。此反例包含真实闲置库存和价格拒绝，无法只归为原煤产能不足。

现金专项中，低初始买方现金发生累计 CASH 拒绝量 239，但依靠原库存和后续真实付款，最终仍追平 6000。低终端资金只真实交付 2、backlog5998。TERMINAL_CASH 的 1,801,800 是重复尝试的拒绝数量累计，不是独立需求数。PRICE/CASH/PHYSICAL 其他累计也含重试；独立 need 身份另有去重计数。

## 一个受限 N4

NEW_PRICE_CANDIDATE_GATE = PASS，七项证据在运行新 holdout 前保存。正式版本为 local-zero-accept-refusal-bound-v1；早期 proposal 的 zero-sales 工作简称在最终命名时明确为 zero-accept，规则一直使用真实 accepted 数量。

仅在完成窗口有实际 PRICE 拒绝、accepted=0、自身 free stock>0、CASH=0，且有新信息时，卖方记住不高于 current−tick 的报价目标。先求原 v1，再受旧 floor/cap/tick/2% 单步边界限制。没有新信息先保持价格和记忆；若记忆目标低于 current-step，优先保持单次变化界限，逐步靠近目标。只用卖方本地事实，不读取买方私有限价或其他 firm 计划。

每 seller-good 一个整数记忆和当窗 acceptance 计数。该计数由 policy 的真实 request_result 维护，独立于 trace。关闭候选精确回到原 N3 权威轨迹；trace 开关、计价单位×10、无新信息、CASH/physical 拒绝、仍有高限价买方接受时不得学习等专项均通过。原 N3 未覆盖。

8 个确认零 PRICE 的 N3/N4 配对中，记忆从未学习，全部权威经济 hash 完全相同。binding 煤场景 N4 相对 N3 多交付 1176/7590；与固定 N2 的差距在 600 与3600 日均为60，表明主要剩余损失是本次初始过渡，而原 N3 振荡损失持续积累。

永久记忆可能错过以后更高愿付价的新买方；有富买方继续接受时不学习低价拒绝，低限价买方仍可能饥饿。这两点均保留，未按 holdout 回调规则。

N4 的 upper_hit/lower_hit/unclamped 是继承的 v1 proposal 标志。记忆挡价与原 floor/cap clamp 分开统计；不能把标志总数称为新的触顶次数。

## 审计和边界

经济执行源为 710dac3。两组正式原档的 533 文件保持原样，hash_manifest SHA-256 为 4b781ce29f023ad80453c7789156c49b847b4d93f3fddb814e87e5512d8db044。

原标准库账目审计重建 quantity/firm flow/order/locked price/cash/reservation/到货付款/terminal；新标准库因果审计重建窗口真实请求、身份最大值、accepted、发运、期末 free stock、整数报价公式及下一日实际报价。正式矩阵没有 cancelled 事件；取消行为通过继承的历史与专项检查覆盖，不假称新矩阵实测大量取消。

完成后发现并修补离线审计覆盖洞：幽灵 accepted-need 仍守恒总量、以及相同日期数量锁价订单跨买方换 ID，旧 checker 都会 PASS。v4 校验 exact keys、逐行上界、FIFO 接受分配、commodity/date/source bucket、request 与 accepted 的完整主体/route。旧 checker 和第9/10个 old-PASS/new-reject 反证保留。所有正式事实已独立扫描，无实际不一致；最终 Gate 以 v4 全118档复审为准：2026-10-08T04:59:53Z 实际 exit0，118次账目重审、118次因果重审及10份精确破坏副本全部获得预期结果。

事先现有八破坏加新两种共十种。日期提前、PRICE误作CASH、旧锁价替换真实新报价、重试冒充新身份、删除到货付款、未知报价、ghost need 和跨主体订单均已被最终 checker 精确拒绝。

decision cash/gap/current ATP 来自真实记录快照，不是对每一 decision 都独立重建的完整账簿。未来隔离是 N3 60/N4 80 日前缀等具体测试，不是形式证明。价格/日期审计与资金守恒是分别检查。离线检查不是第二套经济 runtime，也不是第三方经济模型认证。

长跑使用 compact/off 当前日尾和流式事件档案，不每日复制完整历史世界对象。诊断 gzip 固定 mtime0，两个进程文件字节一致。正常 N3 customer identity cache 从 day100 的560长到 day3600的18060；release identity cache 从1304长到43304，而 active buckets 一直54。这是有界时长验证，不是无限期常量内存。规模 performance 分列 planning/reconcile、known-edge报价分配、物资订单现金结算、档案和最小事件；不推断全球 WWO 性能。

## 失败分类与恢复

- IMPLEMENTATION_DEFECT：早期影子计数误含 legacy 后轮、空事件日审计遗漏、后处理 cache 覆盖、accepted-line/跨主体审计漏检。已单独修正和留版本；没有刷新经济 golden。
- MODEL_COUNTEREXAMPLE：D 触顶且服务完整、限价振荡减交付、总量改善但某些 sink 服务变坏、低终端资金无法付款。没有将它们当代码错误消除。
- EXPERIMENT_DESIGN_DEFECT：v1 holdout 前缀暴露、v2终端资金静态上界不足、早期 runner 预设候选Gate不能PASS。均保留原版本与修订理由。
- ENVIRONMENT_BLOCKER：最初 git 读路径认证失败，用授权原对象恢复；后来两个进程03:47:05中断，各52完成案例和553/599日半项保留，退出码未知，未称PASS。两次新的完整59进程最终 exit0，预算没有重置。

## 二十个问题的直接回答

1. **Cycle01 是否真实恢复？** 是，原封存SHA、bundle/patch与原树可追溯；原353冻结文件完全重现。
2. **触顶直接信号？** D窗口 free0/shipped420/14 identities/physical-unmet112，2%步长7，proposal365被限制360，609决定610生效。
3. **D高价可解释吗？** 可由本地信号和不同日期释放解释；这没有证明竞争市场价格合理或最优。
4. **同日期真实竞争存在吗？** 存在，equal-ETA异价组以及新mixed holdout均有同buyer/need/date及时可支付正量报价。
5. **价格排序改变多少决策？** M2 equal/mixed price-first 的严格第一轮价敏接受 dated-needs 为2105/1188。59配置总计107920个该单位的观测；含不同案例重复设置，不能当现实独立买方数。
6. **传导到真实物资多少？** 上述M2有2102/1186个相关实际arrival events；59组总107824。一个need可多shipment，不能把两种单位相除叫转化率。真正执行反事实的买方到货日数量差为1191/1194；来源分配差另列3027/3077。
7. **为何价格变而服务不变？** 日期门、资源可用性、缓冲库存、足够替代供给及末端生产/需求上界。内部库存/来源/付款仍可改变。
8. **异质性与排序分别作用？** 无价优排序时异价只改付款；同价时价优与legacy相同；二者结合才改变实际资源路径。
9. **lead交互明显吗？** 是，时间处理本身改变实体轨迹；跨日期报价不能直接比较。同日竞争机会由equal组2117降到mixed组1200。
10. **愿付上限约束N3怎样？** 真实PRICE拒绝与周期性停供，煤600/3600日少1236/7650，CASH0。
11. **cash与PRICE不同？** cash不足受真实余额/预留限制，低买方初始现金可通过后续到账恢复；PRICE超限在资金充足时仍拒绝。终端不足另造成2台交付。
12. **长期上限是何推动？** 真实卖方已收到请求的局部最大拒绝信号，受到日期释放及观察口径影响；不等于全市场持续短缺。涨到上限没有增加D产能。
13. **哪些只在人工fixture起作用？** 所有需求、初始资金/价格、known图、lead与愿付上限均为预设实验。尚未证明真实居民/企业行为或WWO综合经济。
14. **600与3600不同吗？** 原振荡不是初始暂态，损失继续累积；N4与N2的60差在两个周期不扩大。两者都只覆盖给定配置。
15. **规模服务分布差异仍在吗？** 是，S5多8而多sink下降；S10总量相同但某些sink差约1279。
16. **新候选证据？** 七项Gate全PASS，单卖方限价反例清楚区分物理稀缺和经济拒绝，形成一个纯局部可关闭N4。
17. **没有新增候选的理由？** 本轮已新增且只新增一个；不需要用不断改价公式来取得每项改善。
18. **defect与counterexample怎样分？** 前者为统计/审计/流程实现遗漏，已修；后者为正确规则产生的触顶、振荡、饥饿和服务转移，完整保留。
19. **增加了哪些可观察经济行为？** 有价格的采购排序、真实单位愿付拒绝、现金独立限制、锁价与付款转移、局部反馈后不同物资到货和sink分布。没有建立福利、GDP、利润或消费者剩余解释。
20. **最小下一方向？** 优先A Price Formation Revision：围绕记忆边界何时有理由释放以及异质限价下的服务损失做受限验证。家庭/消费、资金循环、共享物流和更大网络暂缓，现有最具体反证仍在价格反馈；本轮不自动开展下一周期。

## 复现与交付

经济结果精确复现使用执行 checkpoint710dac3和 experiments_manifest_cycle02_final.json，分别在新目录运行 run_cycle02.py 两次。最终离线 checker与分析器属于另列指纹的 post-execution v4；无需重跑经济来验证它们。

文中 evidence/ 路径统一指 economy_quantity_lab/goal_cycle02/evidence/。冻结候选Gate的旧 replay_a/39 档路径现对应 .local/cycle02/pre_candidate_39，原Gate与hash未改。

关键入口：verify_goal_cycle01.py、run_cycle02.py、run_controls.py、reaudit_cycle02.py、analyze.py、build_cycle02_evidence.py。原始案例必须完整独立初始化，不能用数段短跑冒充3600日。

全量恢复交付含源码/Git对象、原独立状态/manifest、patch和依赖声明bundle、全部已完成正式档案与完整hash、独立复审、十个负例、失败与中断记录。小阅读包仅便于审查，不能替代源码恢复。包的实际尺寸、SHA、恢复验收和Library交付身份在handoff清单中记录。

本轮停止于验收和封存，不自动开启 Goal Cycle03。

## 最终验收状态

Goal Cycle 02

- SOURCE_CONTINUITY_GATE = PASS
- CAUSAL_ATTRIBUTION_GATE = PASS
- MODEL_VALUE_ASSESSMENT = MIXED
- M0 — Source & Baseline：DONE
- M1 — Decision Attribution：DONE
- M2 — Price / Date Factorial：DONE
- M3 — Buyer Price Constraints：DONE
- M4 — Long-run Robustness：DONE
- M5 — Independent Audit & Handoff：DONE
- LAST_VALIDATED_COMMIT / LAST_VALIDATED_EXECUTION_COMMIT：710dac38d82a4d48609e88c9f974a927e9b6c686
- final sealed HEAD：见独立 handoff/export_manifest.json，与经济执行 checkpoint 区分
- 最终正式重放：2个独立进程，各59案例/89400日；合计118案例/178800日；533文件逐个hash与集合一致
- 新专项测试：14 + 11 = 25项；另继承264历史、42 Cycle01检查及原7破坏检查
- 新诊断controls：12配置/13200日，另列，不混入正式覆盖
- 最终v4复审：118账目 + 118因果，10精确破坏副本获预期拒绝；无经济runtime重跑
- N2→N3：16对中1改善/3恶化/12总量不变；N3→N4：16对中3改善/0恶化/13总量不变，个别sink仍下降
- remote CI / Windows / 全球WWO性能：NOT_RUN

最终退出：GOAL_COMPLETE。只推荐A Price Formation Revision，不自动执行Goal Cycle03。封存文件的实际恢复与完整字节校验记录见独立handoff清单；源码与全量原始证据两个组件共同构成恢复集。
