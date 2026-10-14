# 当前人物、调动与任务文本接口

根据代码接口给出，未试跑。使用现有Python客户端的A系列入口。同一session保留原世界实例，沿用原决策间隔、通信通道与世界时钟。临时配属不换人物；失能或死亡后的明确接续才改变控制焦点。读取不推进战争；PENDING读取旧提交状态，写入等待READY。

`transfer id person source_unit destination_unit delay`办理同地静止组之间已有身体账成员的换班。只搬当前能力和同一身体记录，共享库存留在原组。指挥资格按当前岗位判断；离开本班的原岗位会空缺。

结构命令格式为`命令词 id delay JSON对象`，delay至少1秒：

| 命令词 | JSON字段 |
| --- | --- |
| split_members | source、new_id、new_node、members（已有身体账人物ID数组）、anonymous、allocation、keep_goal、other_task |
| merge_members | survivor、donor、keep_goal、discard_other；涉及donor现有岗位时另给vacate_donor=true |
| detach_children | source、new_node、children（现有直属节点ID数组） |
| coarsen | source（编制节点）、leaves（稳定单位ID数组）、level（platoon／company／battalion） |
| propose_move | source、destination（稳定单位ID）、meeting（约定空间节点）、path、detachment、allocation |
| propose_transport | propose_move的六项字段，另给transport={patient_ref、carrier_ref} |
| approve_move / cancel_move / accept_move | movement（实际调动回执中的movement_ref） |
| redirect_move | movement、meeting、path、return_to_start |
| vacate_position | node（当前岗位节点） |
| appoint | node、person（已有候选）、acting（布尔）、vacate_previous（布尔） |

split_members的allocation明确给出equipment、ammunition、fuel、spares。keep_goal为source或new，另一组other_task为`"idle"`或原目标输入对象。原任务只有一个承接单位；目标ID、原发令人、进度与期限保留。新局部任务沿原直属排输入规则。合并keep_goal为survivor或donor，不同活动任务须discard_other=true明确取消。

propose_move的detachment为`{"new_id":"同行单位ID","new_node":"同行节点ID","members":["人物ID"],"anonymous":0.0}`，配合上述四项明确资源数量；或为`"whole_unit"`，allocation明确给`"existing_unit_stocks"`表示整组只带本组现有库存。也可逐项给出整组当前库存数量。提出安排不搬人，批准后候行；原身体动作先结束，选定成员再实际归队。首次出发须来源组在节点静止。

调动号在提出安排实际生效后返回，不能用输入id代替。状态区分PROPOSED、WAITING_DEPARTURE、DEPARTED、IN_TRANSIT、BLOCKED、ARRIVED、HANDED_OVER、CANCELLED。到达不自动接收：accept_move由当前有权目的指挥者提出，生效时双方仍须同在约定节点、静止、成员实际随组且能力及容量兼容。交接沿原库存合并和成员重绑路径一次完成，目的单位任务保留。

分遣途中保留原行政归属，身体和当前能力只在同行组结算。原阵地不保留同一份火力，目的单位接收前不增加能力。库存与历史消耗沿原账；没有个人背包系统。健康为0仍是失能。取消未出发安排不改身体或库存；已出发的取消在当前位置停止，不恢复位置、伤病或库存。之后可用普通合法路径命令实际返回；当前路段返回允许path=[]、return_to_start=true且目标为该路段原起点。

目的组移动不会自动改约。redirect_move是当前有权上级明确给出的新约定和已知路线；中途换路沿原返回／完成当前路段规则。候行超时或目标失败说明原因。调动未接收或取消以前，普通成员拆并及换班不能改其同行组名单。

appoint须空缺岗位、有权上级和已有合格候选。候选永久军职至少达到该岗位的前一级；本班代理候选须实际属于该班且可行动。在途人员暂不任命。vacate_previous=true才允许从旧岗位交接。acting不修改永久军职，任命不复制前任知识、身体或单位任务。A入口的已有班长使用原能力份额和同一伤亡账；失能、死亡、免职或离开本班岗位后撤下指挥资格。健康的离岗成员仍可局部行动。

propose_transport复用调动提出、批准、出发和接收。病员与具名搬运者须在同一实际组、附近可接走位置；detachment须包含两人，或明确使用整组。搬运者当前健康至少minimum_carrier_health（默认0.5）。搬运者先按个人动作票据接近身体，完成后实际携带、归队，再沿原路线出发。病员接走前位置不变；携带后位置随同一搬运者。搬运者不能同时发出其他新意图，且其能力不参与同期射击；携带移动速度按carry_speed_factor（默认0.5）结算，燃料沿原单位规则消耗。受伤导致条件不足、病员死亡或取消会在实际位置中断。接收仍须双方到达同一约定节点、明确accept_move；放下和换归属不治愈。放下后保留伤病。医疗另用下文 aid，不自动恢复；恢复后仍被携带者，须实际放下后才能独立输入。

life_state区分ABLE、WOUNDED、INCAPACITATED、DEAD。健康为0仍只表示失能。原火力剂量按同一人员账分配；新损失只扣剩余健康，超出剩余健康的实际伤害累积为trauma。失能且trauma达到fatal_trauma（默认1.0）才形成死亡事件和永久死亡记录。该阈值是可替换的实验伤情规则。失能身体在原接触范围仍可承受火力，死亡分类不再扣同一能力。死亡停止本人动作、新观察和新意图，身体位置及旧知识保留；旧消息按原送达规则处理，死亡之后到达的报告不写入死者知识。持续出血、救治、恢复及遗体处置使用下文入口。离组身体按原战斗区间起点确定 GROUP／BODY 排他归属，以实际坐标、地形、掩体、距离和射界进入同一批火力分配；随组者不再单独扣伤害。

`continue_as person_id`在当前控制人物失能或死亡后，选择continuity_candidates中的已有可行动人物。A入口给soldier、squad、scout登记实际已有的同班／同排联系，候选不包含全世界目录。选择在当前世界时间的事件边界生效，未完成计算时保持旧提交视图。只换控制焦点和本人输入、阅读绑定；不复制旧人物的知识、回执、职位、健康、库存或任务。新人物只读自己的知识和事件。没有候选时保持原世界和待选择状态，战争仍可继续推进。

任务命令格式为`task id target_formation JSON对象`，沿原军职命令通道送达。基本字段为intent（hold／advance／withdraw／cancel）、target_node、path、return_to_start；取消使用原四字段且目标为空、路径为空。

可选dependencies为至多4项的数组：

| kind | 其余字段与条件 |
| --- | --- |
| unit_arrived | unit_ref、node_ref；同方稳定单位与已知地点，单位须在当前范围或已有报告中；执行组以局部观察确认到达 |
| support_started | mission_ref；本人发出或报告已知的稳定目标；实际移动、开火或抵达后视为开始 |
| support_complete | mission_ref；等待该稳定目标正常完成 |
| route_open | edge_ref；已知路线，沿原真实通行事实处理 |
| new_route | 无其他字段；等待新的合法路径命令 |

前提满足一次后保留该事实。依赖退役、取消、失能或有限期限内不能满足时结束并说明原因。默认局部等待期限300秒，目标期限1200秒，沿原rules配置。新路径可给resume=true，沿用同一intent和target_node，不再给dependencies；保留原目标身份、发令人、进度和期限，并满足new_route条件。改变目的地则是新的合法目标或明确调动改约。

普通目标依赖随临时配属和已有下属划出继续；真实拆分明确承接方，合并明确任务选择。原after完成条件可迁移，未来释放票据、特殊同步和战术协调仍需专门政策，旧order迁移仍拒绝。在途行政来源的合并须先实际交接或归队。

`reserve id current_office JSON对象`由当前连级及以上岗位沿原命令通道使用。保留给`{"policy":"retain","units":["稳定单位ID"]}`；释放给`{"policy":"release","tasks":[{"unit_ref":"稳定单位ID","goal":原目标输入对象}]}`。一次至多4组，须为当前指挥范围内的真实单位。保留沿原Coordination置为reserve，既有任务和路线身份保留，不射击或前进；期限不会自动延长。释放须给实际任务，可为不同组给不同已知路线和普通依赖。使用原人员、装备和库存，没有战斗倍率或额外支援。已有特殊协调和正在执行的调动须先按各自明确政策处理。

移动目标粗化支持同阵营、相容能力与库存、同一路线阶段／方向和执行规则的advance／withdraw；原hold路径保留。目标身份、路径进度、里程、下一实际边界与期限不重置，燃料不恢复。桥梁变化、不同命令、局部接触或政策改变展开有关叶。非焦点具名成员若只随组、没有精确个人动作或搬运，可使用相同群体表示；已死者保留固定身体坐标。人物稳定引用指向同一身体事实，匿名余量与叶伤亡沿同一次群体火力分配。展开使用已结算健康和伤亡，不重算历史。焦点、掩体动作、接走、搬运及待救失能者仍详细；发生失能时只安排相关叶展开。没有全世界人物定时循环。

当前身体账最多6人（原4人加2名现有指挥所人物），每组最多4个具名成员，一次最多16个局部叶，调动记录最多64份。初次出发须在节点静止；分遣继续保留原拆分与库存条件。跨组或远处接走、车辆／担架能力、任意在途拆并、行政来源退役迁移、任意任务图、完整军职生活未实现；当前只给既有 platoon、company 增加身体账，recipient 尚缺明确份额。旧报告保持具体收件人；未来报告用已有直接来源送给当前岗位人物，无来源保持未知。旧测试与历史报告留在原处，本轮未运行。

`body id JSON对象`进入原 Task8 的本人局部行动。字段如下；实际伤情、位置、能力、库存和冲突决定是否可做，不构成演示步骤。

| action | 其他字段与过程 |
| --- | --- |
| aid | patient_ref、mode=stabilize或treat、supply_unit；现有合格 scout、活患者与实际医疗库存须在附近。扣一份 MEDICAL，占用30秒；treat 再等300秒，恢复最多0.25并受 trauma 限制。死亡不可恢复 |
| relocate | destination_node、path（已知地面边数组）；按健康、真实地形和速度逐段走，断路在实际位置停止，不更换人物或岗位 |
| collect_remains | person_ref、destination_node、path；附近同方遗体，实际接近与接走后搬运，速度减半。到达放下为 RECEIVED，搬运者能力不足时原地中断 |
| place_remains | person_ref；附近未被携带、未处置的遗体；占用30秒，留下 PLACED 和处置事实，不删除人物 |

MEDICAL 沿 Task6 原请求、分配及送达结构。A 入口明确配置 unit_001 两份医疗资源、原仓库八份，其他旧输入缺省为零。医疗能力不是所有角色的默认能力。单次新损失至少0.25或出现超额伤害才触发0.001/秒的出血，每30秒事件结算。新严重伤害中断救治，新伤害中断恢复；稳定时先结算尚未计入的出血。参数是研究用人工规则，可替换。原 injury、trauma、历史 casualties、库存消耗和报告保留；恢复只改当前能力和同一个身体。

personnel_recovered 为人员账中的恢复信用。单位 personnel_total 保留 effective＋历史 casualties 的账量关系；世界初始人数 totals.personnel 不增加，人员账减恢复信用才是初始人数份额。拆分、划转和合并迁移信用，不增加匿名成员。正在救治的原库存若随兼容合并转到存续单位，只重绑该次救治的库存引用，不再次消耗。

`person_report id nearby_person recipient`由当前人物观察附近可见身体，并沿原 report 通道（A 入口47秒）送给明确人物。只有送达后进入其知识。报告给发现时的生命状态、当前坐标和身体状态，不给世界内部死亡原因、精确死亡时刻或前任知识。遗体发现、收集和处置均保留稳定身份。

platoon、company 的身体在 C，各消耗 unit_001 原匿名账的一份；unit_ref 对这些人物表示能力份额持有单位，行政归属与当前岗位另列。实际个人 relocate 离岗时使旧岗位空缺；失能／死亡沿已有空缺处理。含指挥所份额的单位暂不进行成员合并或整组调动；前线成员可以明确拆出，指挥所人物用个人路线。继续使用每组4人的限制。

`continue_as`除原同班／同排联系，还可使用场景明确的指挥工作关系及实际医疗、救援、遗体收集、同行、送达命令形成的联系。A 入口未虚构亲属。关系不复制知识或扩大权限；候选仍须可行动。

`air id current_office JSON对象`进入原 Task8 和命令通道。出动字段为 asset_ref、operation=recon／strike／intercept、target_node、outbound（空间节点数组）、inbound（回基地节点数组）、target_ref。recon 的 target_ref 为空；strike 须引用本人已收到的 air_contact 或 sea_contact，并使用报告节点。intercept 只供具备空战武器的航空器，须有已收到的 air_track。撤回只给 asset_ref、operation=abort。保障给 asset_ref、operation=service、refuel、rearm、repair，后三项为明确布尔选择。

A 入口的 air_recon_01 位于 A，原仓库拨出的6份燃料、4份载荷继续保留。新增红方 air_interceptor_01 在 D，从明确新增的 red_source 拨出6份燃料、12份载荷。航空仍最多2架、64份任务，每程最多4个节点。起飞10秒、完好航速0.03km/s、高度0.3km、观察20秒、拦截区停留60秒、降落10秒，耗油0.01份/秒。航空直线航段与地面道路分开。燃料耗尽在实际位置进入有限无动力下降，不能瞬间回基地。

侦察按实际范围、地形可见性／隐蔽和云况产生最多8条坐标带，局部最多读16个地面表示。结果由航空器通过原报告队列送到原发令人，当前航空资料只列本人导航、状态和资源。收到报告后可沿原 task／reserve 改变地面任务。没有自动全知决策或展开整个战区。

对地 strike 在实际范围、高度和观察条件内消耗最多4份载荷，沿原陆地人员／装备损失路径结算。对舰 strike 使用舰体损伤路径，不套用地面班级暴露公式。已移动出范围的目标不被远程扣损失。

基地 A／D 绑定同一地理节点和原 Task6 仓库。每基地一处地勤槽位。降落不补满；service 排队，补油每份5秒、装弹每份5秒、维修每份 integrity 500秒，处理至少5秒。完好上限：燃料6份，侦察机载荷4份，拦截机12份；维修每份 integrity 消耗2份 SPARES。物资在处理完成时从当前仓库转移，库存变化或基地关闭可导致部分补给或中断。损毁装备不能维修复活。基地没有复制库存，飞机和舰艇共享该仓库的实际余量。

航空 integrity 影响航速、侦察、武器和任务。低于0.55迫使返航，低于或等于0.2进入有限下降；归零形成 DESTROYED 并停止旧路线。离基地的迫降进入 AWAITING_RECOVERY；本轮同节点回收见下文。unit_001／unit_002 的原武器输入明确包含防空能力，其他地面单位没有默认防空。防空依据可用装备、地形视野、射界、距离、高度、跟踪时间、压制及当前弹药，在航空接触事件中射击。默认发现范围0.25km、射程0.2km、高度0.02—0.6km，每次3份弹药，跟踪5秒、射击间隔15秒。局部跟踪不直接进入所有人的知识；air_track 经原47秒报告送到指定人物。

拦截沿真实起飞和航程进行，不追踪全世界真相。到达过时报告地点后，只有当前实际接近、可见、高度差和前向射界允许时才射击。默认空战射程0.18km、高度差0.15km，每次3份载荷、间隔15秒；航速和机动参数影响作用。没有具名飞行员死亡或跳伞模型。

`naval id current_office JSON对象`使用原 Task8 和15秒命令通道。普通士兵不能直接控制舰艇。实验授权为当前拥有该舰艇的连级及以上岗位。

| operation | 其余字段 |
| --- | --- |
| sail／patrol | vessel_ref、path（水域连接数组，最多8条）、target_node、target_ref="" |
| engage | 同上，target_ref 为本人已收到 sea_contact 的舰艇，target_node 为报告节点 |
| shore_support | 同上，target_node 为舰艇到达节点，target_ref 为已收到 air_contact／contact／position 的陆地单位 |
| stop／service | vessel_ref，无其他字段；service 必须实际位于本方原港口 |

合成区域声明岸线 y=-0.04，水域节点 PORT_B=[0,-0.06]、SEA_M=[0.1,-0.06]、PORT_R=[0.2,-0.06]。water_BM／water_MR 为外部明确的可航行水域连接，深度0.01km；陆地道路不能代替它们。节点和连接由现有 Space 持有，舰艇不另存地图。PORT_B／PORT_R 的陆地补给节点为 A／D。现有 schedule_waterway 改航道通行；schedule_site 可给 airfield_open、port_open、sea_visibility、sea_state 的定时外部事实。正式 Geography 接口仍未接入。

surface_blue_01／surface_red_01 各从所属仓库划出8份燃料、20份弹药，明确各纳入一件合成舰艇装备。最多2艘、64份任务。完好航速0.01km/s，航行耗油0.004份/秒，吃水0.003km；海况和舰体损伤降速。断航道、失去机动或燃料耗尽时停在实际位置，恢复航行须先承接当前水域连接。不会回退已走航程。

海上探测默认0.22km，受实际位置、海况视野和观察通道影响，sea_contact 经原报告延迟送给原发令人。水面射击默认0.18km、每次最多2份弹药、间隔15秒，有射界和实际发现条件；受到攻击者可沿实际局部发现反击。舰体损伤降速、使武器失效或失去机动；归零为 SUNK，不能继续旧任务。港口补给占用60秒，从同一有限仓库补油／补弹／补损管材料。本轮进水、损管和维修见下文。

航空可以在实际范围与可见性内形成 sea_contact，并沿原报告链送达。岸上人物取得情报后可请求 shore_support；舰炮必须实际到位并看见目标，每次消耗2份舰载弹药，陆地损失只调用一次原 direct_fire。未收到合法请求的舰艇不会自动读取全部陆地目标。

新增 red_commander 的身体在 D，消耗 unit_003 的原匿名份额，全局具名身体仍最多6人。可选择该人物使用 red_company 和 red_command；不复制蓝方知识。未由玩家控制时，红方沿已有有限决策周期作6次选择，间隔360秒；只读自己的导航及已送达报告，选择保障、拦截、水面巡逻或交战，不使用敌方 DEBUG_TRUTH。

这些为可替换的合成参数。没有完整雷达、防空指挥网、三维空战、机组、潜艇、航母、正式地理或游戏宿主接入。本轮未运行测试、试跑、编译检查或审计。

## 2026-10-11 上一轮：航空回收、舰艇损管与海运

以下为本轮代码及输入说明，未运行或验证。陆地火力、移动、人物、任务、Task6 普通补给及 Information 送达继续沿用。新增处理仍使用原世界事件队列。

航空落地读取 Space 的局部 surface_bounds_km，保存实际坐标及 LAND／WATER／UNKNOWN。未声明表面不猜测可回收。当前合成陆地界为 y≥-0.039999，水面界为 y≤-0.04，区域限于声明的矩形。回收不读取正式地图。

`air id current_office {"asset_ref":"air_recon_01","operation":"recover","unit_ref":"unit_001","base_ref":"A"}`：飞机须可回收、落在陆地，现有保障单位与本方开放基地在同一节点，距飞机不超过0.03km。unit_001／unit_003 只有局部搬运能力。至少2份匿名有效人员、1份可用装备及0.25份单位 SPARES；占用该单位，沿原 reserve 机制停止同期火力和移动。准备60秒，再以0.0005km/s搬到基地坐标。回收中人员、装备或地点条件失效会中断。`operation=cancel_recovery`只给 asset_ref，在当前坐标停止，不退材料。回收后为 GROUNDED，仍须原 service 才能维修和补给。跨节点重型拖运、水面回收、未知表面、损毁航空器均不支持。

舰艇命中增加进水、火灾及机动／武器损伤。持续损伤只由命中后的30秒事件结算，读取不增加损伤。命中剂量的0.25计入进水、0.15计入火灾，各0.5计入两项系统损伤。进水／火灾每单位强度每秒消耗0.003／0.004份 integrity。

`naval id current_office {"vessel_ref":"surface_blue_01","operation":"damage_control","active":true}`：使用舰上有限损管能力和同一 Task6 的舰上 SPARES。最多分配0.6份能力，受当前 integrity 和装备限制；每30秒消耗0.1份 SPARES。控制降低持续损伤，并以每秒0.002／0.004乘投入消减进水／火灾。同期射击可用份额为1减投入，航速乘1减0.3倍投入。材料不足、能力不足或已稳定后停止。active=false明确停止。损管不恢复 integrity 或系统能力。

`operation=repair`只给 vessel_ref。须实际到达已登记的本方开放港口，先控制进水和火灾。港口一个处理槽位，维修复用 Task6 capacity.remaining；不另建材料库存。每份修复量需要2份港口 SPARES和500秒，至少5秒；恢复舰体并减少相应系统损伤，受缺口、当前材料和维修余量限制。攻击或港口关闭中断作业。service可补至8份燃料、20份弹药和2份舰上 SPARES。沉没不能维修，保留身份、时间、坐标及损失。

新增本方目的港 PORT_F=[0.12,-0.10]，对应陆地 B 和原 Task6 新增空仓库 front_source。PORT_B 对应 A／source，PORT_R 对应 D／red_source。water_MF连接 SEA_M与PORT_F，长度0.05km；water_BF连接PORT_B与PORT_F，长度0.18km。前者与water_BM构成0.15km航线，后者是明确已知的备选航线。绕航仍受实际通行、敌舰接触、时间和燃料限制。

| naval operation | 字段及条件 |
| --- | --- |
| transport | vessel_ref、source_port、destination_port、path、cargo；可选 hold_departure、supply_request_ref、notify |
| resume_transport | vessel_ref、path、target_node；target_node只能为该货物原港或目的港 |
| cancel_transport | vessel_ref；未装船撤销预留，已装船则在实际位置停航并保留货物 |
| unload | vessel_ref；须实际位于对应开放港口且处理槽可用 |
| forward_supply | vessel_ref、transport_ref；须已收到该运输的目的港入库报告，当前有权，继续办理同节点陆地交接 |
| escort | 原航行五字段，另给 transport_ref；实际不同本方舰艇与承运舰距离不超过0.06km |
| intercept | 原 engage 五字段；target_ref与target_node来自本人已收到的sea_contact |
| blockade | 原 patrol 五字段，target_ref为空；只有实际发现、距离、射界和火力允许时截击 |

装船输入示例是格式说明，不是已执行过程：

```text
naval sea_load blue_company {"vessel_ref":"surface_blue_01","operation":"transport","source_port":"PORT_B","destination_port":"PORT_F","path":["water_BM","water_MF"],"cargo":{"AMMUNITION":30.0},"supply_request_ref":"finite_request","notify":["platoon","squad"]}
```

cargo只接受 Task6 的 AMMUNITION／FUEL／SPARES／MEDICAL，数量明确且有限；当前容量按合成货量相加，限40份。预留减少可用库存但不搬物资；装载完成才从源仓库扣除并进入 Task6 同一 SEA 交付记录，舰艇只保存其引用。装载和卸载各需要20秒加每份1秒，占用港口槽位。载货航速乘0.8。目的港卸完以前没有入库。沉没时已装货物只损失一次；未装货物只解除预留。停航、断路、失去机动、燃料耗尽都保留实际在途货物。取消已装货物不返库；须明确航行回原港并完成卸载。

中断后继续首先承接当前水域连接。当前不支持在连接内部直接反向转船；返回可先完成该连接，再使用给出的返航路径。hold_departure=true完成装载后等待新命令，不使用全知敌情自动挑选路线。

A系列原 finite_request 的30份弹药现在明确等待海运。原300秒预计时间不创建到达事件。绑定船运后，普通分配也只能使用已经实际卸货的目的港库存。可选 supply_request_ref引用现有未分配的同方单位请求；卸货后尝试原 Task6 港口局部交接，等待60秒，到期仍须单位实际位于港口对应陆地节点且不在道路上。单位离开则物资退回该港，不退回海运出发仓库。未达到本节点则停留港口，可待到达后明确 forward_supply。没有远处前线收货，也没有海运失败战斗倍率；陆军仍按真实 ammunition／fuel／spares／medical执行。

护航舰沿自己的实际航线移动，消耗自己的燃料、弹药和任务时间。装载、停航、失去机动或分离时护航等待；等待检查每10秒，任务限1200秒。实际靠近承运舰时，护航可探测和交战附近敌舰。没有护航加成。当前两艘舰艇上限保持；Python客户端新增 --second-vessel-role=escort将第二艘配置为surface_blue_02，使用本方原仓库。默认opponent保留surface_red_01。两舰护航配置没有第三艘敌舰。

运输、损管、航道中断及港口入库报告经原47秒 report 通道送到发令人和明确收件人。港口局部交接由港口资料源发送 supply_status，只有送达后才进入人物知识。舰艇视图使用初始已知资料和最后已送达 sea_status，标为 LAST_RECEIVED_OWN_NAVIGATION；其坐标、库存及状态可能过时。sea_transports也只列收到的运输报告。transport_ref／delivery_ref使用实际回执或报告中的稳定ID，不使用文本输入短ID代替。

有限NPC政策可配置 --supply-responses 的JSON对象：人物ID映射到 {transport_ref、on_interrupted、on_unit_received}。后两项是现有 Task8 意图对象，可选择原任务撤回或 reserve 等；只依据已送达 sea_status／supply_status触发。on_unit_received等待实际单位交接报告，不把目的港入库当作前线收货。只为未被玩家控制的既有人物安排6次有限决策，间隔600秒；没有默认运输决策或全知规划。红方原6次政策现在可根据收到的舰况选择损管、维修、截击或局部阻断。

主要限制：没有跨节点航空器运输、海上救援、船员个人生命周期、复杂舱室、打捞、造船、异节点陆地货运、新全局地理数据库或正式宿主接入。本轮没有开展测试、试跑、审计、编译、静态检查或最终验证。

## 2026-10-11 本轮：跨节点陆运和航空回收

本节补充上一轮能力。以下为代码及输入说明，没有执行这些示例，也没有运行验证。

沿用原陆战、道路、人物、Task6、Information、Task8、航空保障、海运和港口维修。新增物理陆运只作用于land transport输入。旧普通Task6交付不改成道路运输。

### 有限承运能力与库存

当前A系列在初始化时，把unit_001和unit_003明确设为MOTORIZED，各有8份初始FUEL。各从原12份可用装备中分配2份运输装备能力；没有任务开始后生成车辆。完整容量40份，随原可用装备比例下降；运输装备份额不足0.5或匿名有效人员不足2时失能。每队一次只承运一份任务。当前重型航空载重按30份计算。

陆运货量按Task6现有资源份额相加，支持AMMUNITION、FUEL、SPARES、MEDICAL。载货时道路速度乘0.65，继续使用原地形、路桥、压制、疲劳和实际燃料算法。承运队承担原陆战损失；运输占用期间不分配其普通地面火力。原人物身体与装备损失仍结算。

货物保存在同一Task6 LAND记录。RESERVED_AT_SOURCE仅预留，仍在仓库；承运队实际到达装载点并完成30秒加每份1秒装载后，才扣仓库并转为ONBOARD。货物不是运输队自己的射击弹药或维修零件。到达约定节点以后，卸载也需30秒加每份1秒；实际接收才变为RECEIVED。接收单位必须仍在该节点且不在道路上。不会自动追踪已移动的接收单位。

每次实际装备损失，对剩余货物应用损失量／损失前装备量，单次最多损失一半。损失进入原Task6 cargo_lost。运输能力丧失后，剩余货物记为STRANDED并保存坐标和道路进度。该规则为合成规则，不建立箱子实体。

### 陆运文本入口

`land id current_office JSON_parameters`使用原Task8及命令送达。当前需company或更高岗位，并拥有承运队、源仓库和接收对象的现有指挥范围。

| operation | 字段及行为 |
| --- | --- |
| transport | unit_ref、source_ref、recipient_kind、recipient_ref、target_node、approach_path、path、cargo；可选request_ref、notify |
| stop_transport | transport_ref；装载前解除预留，装载后在实际地点停留 |
| resume_transport | transport_ref、target_node、path；可选return_to_start；保留原接收对象 |
| redirect_transport | 上述继续字段，再给recipient_kind、recipient_ref；改变实际交接对象或交接点 |
| unload | transport_ref；在原约定位置再次安排卸载和会合 |
| recover_cargo | transport_ref、unit_ref；另一已配置承运队实际位于滞留货物的同一节点和坐标，并有容量，才转移承运引用 |

approach_path是承运队至源仓库的道路路径，path是装载以后至交接点的路径。两段分别使用本人已知道路。道路中段继续须先承接当前连接；return_to_start可以沿当前连接实际退回。路线中断、缺油、容量下降、压制或退却可产生BLOCKED、FUEL_EXHAUSTED、CAPACITY_LOST、TEMPORARILY_IMMOBILE或STRANDED。重新安排需要已经送达的对应报告。无人接收时为WAITING_RECIPIENT，仍保留在途物资。

以下格式表示已卸入front_source的弹药从B送回A的unit_000；前线在其他已知节点时，明确给出对应道路和交接点：

```text
land inland_supply blue_company {"operation":"transport","unit_ref":"unit_001","source_ref":"front_source","recipient_kind":"unit","recipient_ref":"unit_000","target_node":"A","approach_path":["AB"],"path":["AB"],"cargo":{"AMMUNITION":30.0},"request_ref":"finite_request","notify":["platoon"]}
```

接收仓库使用recipient_kind=depot。例如从front_source送SPARES至A的source，必须使用target_node=A和真实AB路线。物资进库以后，基地或港口仍通过原保障作业消耗它。FUEL交给单位时，单位必须具有原fuel_dependent能力。运MEDICAL不触发远处伤员治疗。

装载前stop_transport解除仓库预留；装载后停止不返库。返库使用redirect_transport，明确指定源仓库和返回道路，再完成卸载。任务和交付引用使用回执或报告里的稳定transport_ref，不把文本短ID当作交付ID。

### 海陆连续交接与军官决策

sea transport新增可选land_required=true。设置后，目的港卸货只入原港口仓库，不自动安排旧PORT_LOCAL交付。新land transport可以引用原supply_request_ref对应的request_ref，LAND记录保留SEA段引用。只接受实际已在该目的仓库完成卸货的海运请求。

默认未由玩家控制的company会使用原finite_request下达海运，在收到PORT_F入库报告以后下达陆运。A1交接点为B；A2／A3为A。运输队从A沿AB到B装载，A2／A3再沿AB返回A交接。若前线离开约定位置，运输队等待会合，不追踪隐藏位置。

原请求记录累计received_quantity。部分货物实际交付以后，仍缺的数量保持REQUESTED。company根据已送达的交付报告，可让原舰沿已声明的water_BF返PORT_B，再运剩余需求；仍需实际返源、装船、卸港和另一段陆运。源库存、承运能力或权限不足会阻止命令，不生成替代资源。

非玩家company／platoon的补给政策各最多12次机会，间隔600秒，结束于6600秒。company收到中断报告后可把unit_000保留为实际预备队；后续真实接收报告可释放为守位任务。platoon在当前权限内可暂缓推进、恢复既有任务条件或依据低弹药报告提出Task8请求。没有固定缺弹战斗倍率。已合法下达的移动、装卸及其他常驻任务继续推进，不等待玩家操作。

已有--supply-responses继续接受人物到政策对象的JSON映射。可按transport_ref或request_ref匹配，提供on_port_received、on_departed、on_interrupted、on_unit_received、on_low_ammunition。值仍是现有Task8意图，可使用goal、coordination、reserve、logistics_request或合法运输命令。政策读取已送达报告，并按状态阶段避免重复触发。替代路线必须明确给出，仍经原权限和已知道路约束。

land_supply_status包括运输段、原请求、SEA引用、承运队、实际报告地点、当前归属、剩余货物、损失及实际交付数量。沿原47秒报告通道送到发令人、请求人及明确收件人。land_transports只显示已收到报告。航空器视图也改用初始资料及已收到的air_status、air_service、回收和观察报告，标为LAST_RECEIVED_OWN_AIR_STATUS。位置和库存可能过时。水面迫降状态报告不自动给出精确坐标。

### 跨节点陆地航空回收

```text
air road_recovery blue_company {"asset_ref":"air_recon_01","operation":"recover_land","unit_ref":"unit_001","pickup_node":"B","base_ref":"A","approach_path":["AB"],"path":["AB"]}
```

需要已收到飞机在拾取节点的地点报告。飞机须为可回收LAND迫降资产，距声明的拾取道路节点不超过0.03km；该节点允许机动运输。不能解释局部接近关系时拒绝回收。

运输队先沿实际道路接近。装载占用90秒，再以0.0005km/s把飞机从实际迫降点拖到网络交接位置，消耗0.25份承运队SPARES。之后飞机为CARRIED_LAND，实际坐标随承运队变化。到本方基地后卸载90秒，成为GROUNDED；身份、库存和损伤保留。仍需原service维修、补油、装弹。

旧recover仍为同节点近距离搬运。cancel_recovery可以取消旧局部回收或新的陆地回收，保留已经移动的位置。损毁航空器不能回收复活。途中承运装备损失可使飞机受损或停止运输。

### 水面航空回收

只有surface_blue_01初始化配置一份航空器回收槽和设备。没有给全部舰艇添加打捞能力。实际人员与舰上装备能力、integrity至少0.4、舰上SPARES至少0.25以及任务空闲是装载条件。

现有舰艇传感事件可观察可回收水面飞机，生成water_recovery_contact。受实际位置、可见性和观察通道限制。远处只报告位置带，0.03km以内才可形成局部精确位置。DESTROYED、UNKNOWN或未发现资产不能作为水面回收对象。

```text
naval water_recovery blue_company {"vessel_ref":"surface_blue_01","operation":"recover_aircraft","asset_ref":"air_recon_01","pickup_node":"SEA_M","destination_port":"PORT_B","path":["water_BM"],"return_path":["water_BM"]}
```

必须先收到该水域节点的实际观察报告。舰艇沿原水域路径至拾取节点，在声明水面内、0.03km以内确实观察到飞机以后，再进行实际局部接近。装载90秒并消耗0.25份舰上SPARES。飞机为CARRIED_SEA，仍是原航空资产。舰艇先回到水域连接点，再走返港路线。

resume_recovery给vessel_ref、target_node和path；stop_recovery只给vessel_ref；unload_aircraft只给vessel_ref。继续或卸载需要已收到对应中断或港口报告。停止已装载任务会保留舰上飞机。失去能力可使飞机滞留舰上；沉没按实际位置结算，不能同时保留原海面副本。

PORT_B→A、PORT_F→B具有明确合成岸线搬运连接，占用原港口处理槽。准备90秒，再以0.0005km/s移动到对应陆地节点；不是从舰位直接送往远方基地。到A且基地可用时为GROUNDED；到B时仍为AWAITING_RECOVERY，可再用recover_land。港口关闭、能力失去或停止岸线作业时，保留当时实际位置。

没有具名飞行员和机组的水面生命事实。本轮只有航空资产回收，没有人员搜救、跳伞、生存、潜水或沉船打捞。

### 保障衔接和范围

航空基地已经提出的保障任务，在库存不足时保持WAITING_ACTUAL_BASE_STOCK。实际仓库入库事件才重新安排原保障作业。加油、装弹和维修仍分阶段耗时并消耗同一Task6库存。单位装备维修、医疗以及舰艇港口维修继续复用原入口，不能消费仍在LAND或SEA记录中的货物。

默认每方只有一队陆运力量；失能后可能没有可替代承运队。滞留货物再装限已声明节点的实际会合，不支持道路中段抢运。没有无路拖运、任意海面自由寻路、敌占货物处置、全球供应规划、正式地理或宿主接入。航空仍2架、舰艇仍2艘；新增陆运最多64份记录。平台报告源上限由6调整到8，供两份有限陆运报告源使用。

本轮未运行测试、试跑、编译、静态检查、审计、哈希或其他验证程序。以上参数和过程为代码说明，不表示运行正确性或性能已验证。

## 自主指挥与作战目的（本轮新增）

A系列默认使用--autonomy-mode=events。人物因实际报告送达、本人命令结果、岗位变化和低频期限获得机会。军职间隔仍有效；无新情况维持原常驻任务。自动输入不控制当前玩家人物。--autonomy-mode=prototype保留旧固定机会实验政策；--supply-responses仍用于该旧政策。

新增文本操作：

- operation id current_office JSON：begin、priority或cancel。
- forward id received_message_id subordinate_person：转发当前人物已经收到的报告。保留观察时间及来源，增加一次原报告通道延迟，不提高质量。
- look显示已收到的作战目的、任务状态与报告消息号。任务真相不直接进入视图。

begin参数：operation、purpose、target_node、priority、deadline_seconds、tasks。purpose允许hold、advance、route_security、supply、recon_support、withdraw。priority为0至5整数；期限60至86400秒。最多8项任务，至少一项required=true。after只能引用列表中较早的task_ref，避免递归计划。

GROUND任务包含task_ref、domain、unit_ref、goal、priority、required、after。goal沿用原intent／target_node／path／return_to_start。可选routes按收到的当前位置选已知路径；alternatives提供有限绕行候选。require_recon=true需要收到当前目的开始后的侦察覆盖。retain_before_execution=true由上级使用原预备队保留／释放路径；followup=false用于不应在结束后占用下一任务单位的阶段。

AIR、NAVAL、LAND、SUPPLY任务使用同名domain与原Task8 intent，仍经原领域检查和执行。LAND可配置approach_routes、handover_unit、handover_routes，以及按“当前位置:交接节点”索引的alternative_routes／redirect_routes。承运队已经出发时，改约仍须等相关报告，并沿真实道路移动。target_from_recon只从收到的近期air_contact选择支援目标。

示例参数结构（目标与路径须按当前知识填写）：

```json
{"operation":"begin","purpose":"hold","target_node":"A","priority":4,"deadline_seconds":3600,"tasks":[{"task_ref":"front","domain":"GROUND","unit_ref":"unit_000","goal":{"intent":"hold","target_node":"A","path":[],"return_to_start":false},"priority":4,"required":true,"after":[]}]}
```

修改优先级使用{"operation":"priority","operation_ref":"已收到的目的ID","priority":5}；取消使用{"operation":"cancel","operation_ref":"已收到的目的ID"}。取消后的具体动作仍通过原命令通道，不能瞬间返航、返港、返库或恢复资源。已提出的Task6请求不因目的取消而抹除。

默认双方初始目的、仓库和候选路线由合成输入配置。通用有限政策执行真实任务、报告、预备、补给和支援；它不自行创建全地图战役。physical_supply与delivery_plan仅给明确使用物理陆运的输入启用，普通旧Task6补给不重写。自动弹药警戒采用每件可用装备两份弹药；情报期限600秒。参数是可替换实验规则。

本轮内容仅依据代码修改描述，未运行验证程序。

## 2026-10-12 后续目的、接替与运输接管

原events入口继续默认启用。原初始目的、人物知识、Task8和领域执行入口保持同一套。campaign_options是当前职位的有限政策配置，不是新的玩家权限。双方使用相同选择函数；当前玩家人物仍只提交自己的明确输入。

campaign_options包含units（最多考虑8个实际下属）、objectives（最多考虑8项目标）、fallback_node、fallback_routes、deadline_seconds和可选air_support／naval_support。每项目标给出target_node、priority、require_recon及按出发节点索引的routes。政策只在已收到前一目的结束报告后选择后续目的。缺弹、缺油或失去机动时选择合法撤回或当前节点守位。阵地仍已满足且无已知接触时维持任务。缺少近期覆盖时先安排真实侦察。失败任务须有改变可选行动的信息才重新推进；重复报告时间和情报过期不表示战况改善。

后续目的使用普通begin，并带predecessor_ref。recon_not_before可保留此前已经收到的近期覆盖的观察时间；下属仍必须实际收到覆盖报告。naval_support包含vessel_ref、target_node及routes；它只声明已知支援位置与路线，目标仍来自收到的侦察。air_support继续使用配置中的recon_asset_ref。支援需要实际资源和可用资产，并接受原领域拒绝或失败结果。

原operation文本入口增加两项参数结构：

```json
{"operation":"reassign","operation_ref":"已收到的目的ID","task_ref":"已收到的子任务ID","unit_ref":"实际替代单位ID","goal":{"intent":"advance","target_node":"B","path":["AB"],"return_to_start":false}}
```

reassign限GROUND。目的未取消且未过期限，任务已失败、已取消或尚未发出，原依赖已完成，相关反馈已收到，旧命令已经结束，替代单位属于当前权限且未占用，才接受。任务ID保留，assignment_revision递增。旧库存、伤亡、人物知识和物理任务不复制。reserve_candidates给自主政策列出有限的现有候选；默认为空，运输队不会因此变成另一支预备队。

```json
{"operation":"transfer_observer","source_unit":"拥有现有报告能力的单位ID","unit_ref":"实际接收单位ID"}
```

报告能力转交要求两组属于当前指挥范围、均有实际人员，且在同一实际坐标并未在道路上。转交已有平台身份。合并的多份能力保留为所在组的备用能力；拆分不复制能力。转交后新组只发送自己的当前状态，旧消息仍是旧观察。

LAND任务可给recovery_carriers列出最多8个已经配置承运能力的本方单位。自主接管仅限已收到STRANDED报告、货物位于节点、候选承运单位已实际在该节点、容量足够且无其他任务占用。接管使用原recover_cargo，保留transport_ref、货物和原Task6请求；随后仍需合法路线恢复及真实卸货。没有候选承运队时继续滞留，不生成车辆。默认每方一个陆运队，未配置额外承运队。

字段报告增加fuel_level、spares_level、transport_capacity、field_report_capabilities和incoming_contact。physical_supply自动请求可用supply_quantities配置AMMUNITION、FUEL、SPARES的有限数量，默认10、10、2。未完成请求不会因当前库存短暂恢复而消失。请求分配按已收到的任务优先级和请求先后排序。MEDICAL沿用原请求、运输和实际医疗路径。

改交会合位置使用redirect_transport；保持原交接位置的绕行使用resume_transport。接收者返回约定位置时提出原unload。累计接收数量来自Task6的received_quantity，兼容的cumulative_received_quantity只是同一数值的报告字段。货物尚在途中或滞留时不能再次分配成已到货库存。

仍保留原记录容量和会话时间边界。候选目标、撤回方向、已知路线、支援资产和资源数量仍为明确的实验配置。没有全局规划、自动新海运链、道路中段抢运或正式宿主存档接入。本节仅说明已写入的代码与输入，未运行测试、编译或试跑。

## 2026-10-12 报告恢复、路线检查与新SEA批次

上述段落保留为此前记录。本节说明本轮新入口。

```json
{"operation":"request_report","subject_kind":"unit","subject_ref":"unit_000"}
```

使用原 `operation id current_office JSON` 提交。unit须在当前指挥范围内。vessel须满足原海军权限。请求经过命令延迟；现场已有来源有实际报告条件才回应。没有回应不代表单位毁灭。REPORT子任务的intent使用该operation_intent；恢复目的可给supports_operation_ref，引用已经收到的目的或下属任务。它只建立关联，不授予修改上级目的的权限。

contact_states只读取已送达Knowledge。默认600秒为过期，1200秒为失联期限。没有报告、过期、失联、通信失败、现场报告能力缺口、外部局部发现、确认失能和确认损失分别表达。观察、产生及送达时间保留。RECOVERED要求真正的新来源报告；旧报告转发不刷新覆盖。新编组的未报告任务从已知任务开始时刻等待。

GROUND子任务可给survey_unit和survey_edges（最多4段，须在其已知goal.path内）。它使用普通advance／hold等目标，继续承受原地面接触、燃料和人员限制。route_security目的未给survey_edges时采用声明路径的前4段；长路线需分成有限任务。实际走完路段报告PASSABLE／TRAVERSED_SEGMENT；实际入口受阻报告BLOCKED／LOCAL_ENTRY。观察到目标失能不再次结算损失。

GROUND和LAND子任务可给require_route_reports，最多4段。各段必须有可靠、近期、已经送达的PASSABLE报告，且观察时刻不早于route_not_before（默认目的开始时刻），才发出依赖它的动作。报告仍需到执行人物。已知替代路线和固定检查段的复杂替换须显式重新安排任务；不自动声明整片道路安全。

AIR的原recon参数可追加observe_unit或observe_vessel，以及survey_edges（最多4段）。对象须属于当前权限内的实际身份；目标点及往返航路仍须已知。只搜索实际飞到的传感器范围。friendly_contact／friendly_sea_contact保留局部发现；unit_condition表达现场失能。recon_result的subject_confirmed为false只表示此次没有确认。航空路线结果为ENTRY_OBSERVED／LOCAL_AERIAL_ENTRY，不作为地面PASSABLE证明。

recovery_scouts在Standing Order中给出最多考虑8个已有小组。每项包含unit_ref及routes，按目标节点、已知出发节点索引实际路径。小组须已有报告平台且未承担运输、战斗或预备占用。没有可用小组或航空器时保持等待。平台转交继续使用原transfer_observer和真实同地条件。

sea_supply_plans是职位的有限实验政策，不是新权限。每项包含：

- source_port、source_ref、destination_port、vessel_refs、resource_classes和recipient_nodes。
- path、approach_routes、resume_routes及可选resume_alternatives／return_alternatives。路线按舰艇已报告节点索引，水域移动仍使用原NAVAL。
- minimum_fuel及deadline_seconds。最低燃料是配置条件，实际消耗仍由航行计算。
- land：carrier_ref、source_ref、capacity、approach_routes、handover_routes；可追加redirect_routes、alternative_routes、recovery_carriers和require_route_reports。

港口和仓库必须是原注册对象。source_ref是出发港仓库；land.source_ref是目的港仓库。vessel_refs只是候选，实际选择还受当前所有权、位置、货物、燃料、损伤及任务限制。候选组合最多考虑8项。默认蓝方PORT_B／source至PORT_F／front_source配置四种原资源，并用原unit_001接续。红方只有一个本方港口，保持原LAND途径；不会生成新港口或借用敌舰。

新SEA装运使用原supply_request_ref和land_required=true。单批可小于未落实数量。Task6仍负责唯一库存。request_balance报告已收到、预留／在船、港口未转出、LAND占有、确认损失和未落实数量。forwarded_cargo是批次归属记录，在实际LAND装载时增加。它不代表另一份可用库存。一个请求按当前有限表示串行接续批次；货物尚在有效运输或滞留时不重新承诺它。

新任务依次实际装船、航行、卸港和陆运交接。空船按真实路径返源后再考虑下一批。港口收到货物不等于前线收到。原任务结束但船载货物仍存在时，可引用原transport_ref继续航行／卸载；不会重建需求或重复预留。PORT_LOCAL旧入口仅处理原来能够整批同地交接的情形，分批货物使用LAND。

已收到的港口库存、船舶状态、局部水域入口及运输报告影响重试。没有相关变化时不重复等价失败安排。水域入口可用不保证后续整条路线或战斗安全。缺油、无可用舰艇、未知路径、港口关闭、容量用尽或未完成货物责任仍可造成等待。不会抹除原请求。

原主作战目的可继续守位、暂缓、撤回或使用campaign_options。独立恢复／补给目的不停止整个世界。当前玩家人物仍不由后台政策代发新意图。原8目的、每目的8任务、资产、消息和交付容量保持原值。

边界：仍无完整通信网络、道路中段抢运、船间货物转装、全海面寻路或自动工程修复。已结束目的中的未完成LAND货物尚需显式再挂接。原库存、滞留责任及损失保留。本节描述代码与参数，未运行测试、编译或试跑。

## 2026-10-12：局部通信、转装和运输接续入口

前述边界是此前记录。本节对应本轮源码新增。旧陆海空、侦察、装卸、补给和维修继续使用原内核。

Session.configure的options可显式给local_communications:true。默认false。启用时，report、command和red_command中新产生的消息使用原communication世界事件，在实际发送、每段中继、重试及回执时刻读取物理位置。启用前已经入队的旧消息保持原契约。

参数field_radio_km默认0.12、naval_radio_km和air_radio_km默认0.3。它们只配置已经注册的平台，不创建设备。地面实际visibility和concealment折减作用距离。人物实际接触设备后才能使用它；无设备的人物仅有有限近距方式。contact_km为0.01，short_range_km为0.025。节点communication_open为false时阻断远距联系，同地接触仍可用。

relay_people可给已有指挥人物；relay_platforms可给已有平台ID。两者合计最多2项。给出relay_platforms时，默认不再加入人物中继。平台须有实际可用设备及当前组织中的合法转发关系。设备随单位的原移动／调动改变位置。平台转交和单位合并不改消息原来源；新拆分单位不自动取得设备。例：relay_platforms:["field_unit_001","field_unit_003"]只是选择当前既有平台，不保证链路可达。

communication_facts可声明最多8个初始世界事件，每项为{"id":"local_break","at":120.0,"node_ref":"C","open":false}。恢复事件给不同id和open:true。它接入Space.schedule_site的communication_open属性，不是人物修改世界的指令。

不可达消息保留原ID、claims及observed_at，每120秒尝试，等待边界为发送后3600秒。重连不重造观察。已经实际接收的中继人物才取得原claims；平台中继保留消息占有，不给远处人物写Knowledge。已超时消息不恢复为已送达，需要新合法报告。commands执行和回执分开；回执没有确认时为UNCONFIRMED，不重执行同一命令。communications只显示本人发送及等待回执状态。request_report本身须到达实际报告单位／舰艇；有实际条件时同时回应当前陆运状态。

原naval入口新增：

```json
{"operation":"transship_cargo","vessel_ref":"surface_blue_01","recipient_vessel_ref":"surface_blue_02","cargo":{"AMMUNITION":20.0}}
{"operation":"cancel_transshipment","vessel_ref":"surface_blue_01"}
{"operation":"continue_transport","vessel_ref":"surface_blue_02"}
```

转装示例需要second_vessel_role:"escort"提供的两艘既有本方船。货物须已经实际装船，舰艇须已经实际会合。省略cargo表示转移原舰当前全部份额。两舰距离须不超过0.005km，保持稳定状态，海况不超过0.5，火灾／进水及机动条件允许，扣除损管占用后的装卸能力至少0.5。准备20秒，随后每秒1单位，每次事件最多完成10单位。攻击、海况或能力变化会中断；完成部分留在接收舰，剩余部分留在原舰。接收舰原有兼容份额计入容量。

cargo_by_vessel属于原Task6 SEA交付，cargo仍为同一交付总量。原transport_ref、delivery_ref和request_ref不变。接收舰有独立实际航行任务，继续使用resume_transport及原已知水域路线到港卸货。货物不进入舰艇战斗弹药或燃料。每艘船只卸自己的份额；目的港实际入库部分可以继续LAND，原forwarded_cargo防止重复转出。无法保持稳定作业的失能舰不支持普通转装。

分载后的报告区分实际本舰货物与原manifest_cargo。数量投影依赖已收到报告及当前本地交接记录。未知的远处承运舰损失不直接释放已知余量。实际近距观察到沉没可产生friendly_sea_contact和确认货损报告。未确认余量可以保持等待。

原land入口新增：

```json
{"operation":"continue_transport","transport_ref":"<已有陆运身份>"}
{"operation":"redirect_transport","transport_ref":"<已有陆运身份>","recipient_kind":"unit","recipient_ref":"unit_000","request_ref":"<兼容的未落实请求>","target_node":"B","path":["AB"],"return_to_start":false}
```

continue_transport保留原位置、路径、装载及事件，仅变更当前有权负责人。redirect的实际路线须从当前位置合法出发；上述路径不是通用路线。新request_ref仅作用于已经装载的兼容货物。省略新请求时，保持同一接收单位的原请求；改往另一单位或仓库则解除旧请求的当前运输绑定，仍保留旧请求和初始请求来源。返回仓库要给recipient_kind:depot、实际source_ref对应的仓库、当前已知道路和实际卸货条件。

原operation begin的LAND／NAVAL子任务可给transport_ref，引用已有未完成运输。LAND示例：

```json
{"operation":"begin","purpose":"supply","target_node":"B","priority":4,"deadline_seconds":3600.0,"tasks":[{"task_ref":"continue_cargo","domain":"LAND","transport_ref":"<已有陆运身份>","request_ref":"<原请求>","priority":4,"required":true,"intent":{"kind":"command","command_kind":"land_intent","target":"blue_company","channel_ref":"command","values":{"operation":"continue_transport","transport_ref":"<已有陆运身份>"}}}]}
```

须替换为本人当前岗位、已经收到的运输与请求身份。LAND承运引用由实际job确定；可复用handover_unit、redirect_routes、alternative_routes、recovery_carriers及require_route_reports。NAVAL使用对应vessel_ref和continue_transport；completion:return表示以实际返源为任务完成条件。已有活动目的占用或未送达的前命令会阻止冲突承接。后续任务记录前任务及assignment_revision，原货物不重新预留。目的结束只结束军事安排，实际运输仍可继续。

原operation入口还可给{"operation":"reduce_supply_request","request_ref":"<已知原请求>","quantity":20.0}。quantity为调整后的总需求，只能减少未落实的部分。保护已接收、已预留、在途和港口剩余责任，不自动将已装货物返库。

自主政策复用原Task8、双方权限及有限候选。已结束目的中的未完运输可形成后续承接；陆运报告陈旧时先请求真实状态。受阻海运可在已经收到的真实近距、容量、燃料及作业信息允许时选择转装。没有新条件不重复等价尝试。玩家控制人物不被后台代发新意图。

仍未实现主动部署全图中继、移动信使网络、任意海面会合、任意SEA份额改绑不同请求／目的港、道路中段抢运、自动修桥或正式宿主存档。本节只说明源码与参数，未运行测试、编译、试跑或验证程序。

## 2026-10-12：主动部署、工程、会合与 SEA 改派

以下是新增输入。上节保留为历史；有限主动中继、明确设施工程、节点会合和每舰整份 SEA 改派现已写入源码。未运行验证。

初始 options 可显式声明有限能力与候选。下面是配置片段，须与实际存在的单位、设备、已知路线和当前人员／SPARES 相符；它不补发资源：

```json
{
  "local_communications": true,
  "relay_people": [],
  "relay_platforms": ["field_unit_001"],
  "engineers": {
    "unit_001": {
      "minimum_crew": 2.0, "minimum_equipment": 1.0,
      "clear_seconds": 120.0, "repair_seconds": 600.0,
      "clear_spares": 1.0, "repair_spares": 2.0
    }
  },
  "engineering_edges": {
    "AB": {"actions": ["clear"], "work_nodes": ["A", "B"]},
    "bridge_BD": {"actions": ["repair"], "work_nodes": ["B", "D"]}
  },
  "engineering_facts": [
    {"id": "bridge_damage", "edge_ref": "bridge_BD", "at": 600.0, "obstruction": "limited_damage"}
  ],
  "action_orders": {
    "company": {
      "relay_deployments": [
        {"unit_ref": "unit_001", "platform_ref": "field_unit_001", "node_ref": "B",
         "routes": {"A": ["AB"], "B": [], "C": ["AC", "AB"]}}
      ],
      "engineering_plans": [
        {"unit_ref": "unit_001", "edge_ref": "bridge_BD", "action": "repair", "node_ref": "B",
         "routes": {"A": ["AB"], "B": [], "C": ["AC", "AB"]}}
      ],
      "rendezvous_plans": [
        {"node_ref": "SEA_M", "routes": {"PORT_B": ["water_BM"], "PORT_F": ["water_MF"], "SEA_M": []}}
      ]
    }
  }
}
```

工程单位最多2个，声明设施最多4处，障碍事实最多8个；每类候选最多8项。debris 对应 clear，limited_damage 对应 repair。severe_damage 和 unclassified 保持不可处理。普通 open=false 不自动解释为有限损毁。SPARES 使用单位的原 Task6 库存；不足时保留受阻和真实补给需求。

中继必须是 physical 已登记的现有 relay_platforms，实际当前持有人须与任务 unit_ref 相同。GROUND 子任务可以使用下列字段，外围仍是原 operation begin：

```json
{
  "task_ref": "deploy_relay", "domain": "GROUND", "unit_ref": "unit_001",
  "priority": 4, "required": true, "followup": false,
  "goal": {"intent": "advance", "target_node": "B", "path": ["AB"], "return_to_start": false},
  "relay_deployment": {"platform_ref": "field_unit_001", "source_ref": "field_unit_000", "recipient_ref": "company", "channel_ref": "report"}
}
```

source_ref 必须来自本人已收到的报告，recipient_ref 为提出部署的人物。命令自身也受当前通信条件约束。到位结果是实际两段链路是否成立，不能解释为已经得到失联单位的新战况。

工程子任务使用相同 GROUND goal，改为 `"engineering":{"edge_ref":"bridge_BD","action":"repair"}`。目标必须是声明的工作端点，且已收到相应障碍报告。工程每段最多60秒，材料在该段开始时消耗；中断不退还。实际完成更新原空间事实，并发出局部设施报告。field_work 查询只显示已经收到的作业信息。

两舰分别通过原 naval 入口接受 rendezvous。使用相同 rendezvous_ref，partner_ref 互指，路径各自起于真实位置并终于同一个已知水域节点。例如在对应已知初始位置时：

```text
naval meet_a blue_company {"operation":"rendezvous","vessel_ref":"surface_blue_01","partner_ref":"surface_blue_02","rendezvous_ref":"meeting_1","target_node":"SEA_M","path":["water_BM"],"deadline_seconds":1200.0}
naval meet_b blue_company {"operation":"rendezvous","vessel_ref":"surface_blue_02","partner_ref":"surface_blue_01","rendezvous_ref":"meeting_1","target_node":"SEA_M","path":["water_MF"],"deadline_seconds":1200.0}
```

第二行只适用于第二舰实际从 PORT_F 出发；同在 PORT_B 时应使用其已知 water_BM 路线。两舰须已经存在且当前有权合作；只有一艘本方舰艇时不生成伙伴。可复用原双蓝方初始配置 second_vessel_role=escort，不在运行中增加舰艇。会合期限为60至3600秒。会合不卸货、不转装；实际接近后另用原 transship_cargo。可在同一目的中用两个 NAVAL 子任务及 after 依赖安排必要的转装任务。

SEA 改派使用原 naval 入口，当前舰艇的整份单种货物份额作为改派对象：

```text
naval redirect_cargo blue_company {"operation":"reassign_cargo","vessel_ref":"surface_blue_01","supply_request_ref":"<已收到的现有请求ID>","destination_port":"PORT_B","path":["water_BF"],"land_required":true}
```

示例路径只适用于从 PORT_F 航向 PORT_B 的已知路线。途中改派须先继续原水域连接，不能改变坐标。新请求须足以接收整份实际货物，不能已被其他运输占用。新请求或新港口至少改变一项；同一请求还有其他在途、港口或 LAND 份额时，不能把它拆成两个接收仓库。每次改派保留原 SEA 身份，最多8次修订。分载另一舰不随本次改变；不兼容份额不能混入同舰。当前首版强制 land_required=true，港口真实卸货以后经原 LAND 接收，尚未支持同舰内部任意小份分别去不同港口。

自主中继、工程、会合与已结束目的的 SEA 改派共用原有限决策政策。没有新条件不重复等价意图。工程失败后材料保留为已消耗；会合失败后船和货物留在实际位置；没有合法资源或路线继续等待。原人物权限、送达时权限、玩家控制排除、观察时间和 PENDING 查询边界保持原路径。

## 2026-10-13 步兵、班组、炮组与工事输入

以下是本轮源码接口，未试跑。仅 A 系列接入这些初始配置。现有客户端增加 `--battlefield-actions` JSON 参数，也可向原 Session.configure 的 options 给相同字段。参数只分配当前单位已有人员、装备及资源，不增加物资。原 S 系列和通信方式继续沿用。

初始字段：

| 字段 | 含义 |
| --- | --- |
| infantry_actions | A 系列默认 true。为已有 soldier、scout、squad 分配其原单位装备中的一个步枪操作份额。初始准备弹药为0。 |
| weapon_profiles | 最多6名已有身体人物的武器份额。role 为 rifle／automatic／precision。可给 magazine、reload_seconds、aim_seconds、rounds_per_minute、range_km、lethality、suppression_per_round、equipment_share；数值须正且有限。直接射界不超过原单位 weapon.range_km。 |
| gun_crews | 最多2组，结构为 gun_id → {unit_ref, profile}。profile 必须给 crew、equipment_share、range_km、deploy_seconds、reload_seconds、cycle_seconds、rounds_per_mission、lethality、radius_km。从已有匿名人员、装备和 AMMUNITION 取得份额。 |
| position_sites | 最多8个已有陆地节点 → [personal, squad, weapon 中的允许类型]。地形坡度须不大于0.3。最多16份实际工事，个人工事也占原16份附近掩体容量。 |
| engineers | 原最多2个实际工程单位。保留 minimum_crew、minimum_equipment、clear_seconds、repair_seconds、clear_spares、repair_spares；可增加 positions → 类型 → {seconds, spares}。 |
| action_orders | 原人物常驻有限候选，可增加 construction_plans。每项给 unit_ref、node_ref、position_ref、position_kind、routes（已知起点 → 路线）。沿用最多8个候选。 |

例如初始武器／炮组配置可采用以下对象；没有相应实际单位、人员和装备时配置不成立：

```json
{
  "weapon_profiles": {"soldier": {"role": "precision"}, "squad": {"role": "automatic"}},
  "gun_crews": {"field_gun_1": {"unit_ref": "unit_001", "profile": {
    "crew": 2.0, "equipment_share": 1.0, "range_km": 0.5,
    "deploy_seconds": 30.0, "reload_seconds": 20.0, "cycle_seconds": 15.0,
    "rounds_per_mission": 3.0, "lethality": 0.04, "radius_km": 0.025
  }}}
}
```

这些是可替换研究口径，不是现实枪械或炮兵参数。普通步枪默认准备容量4、装填10秒、瞄准5秒。自动武器默认容量12、装填18秒、瞄准6秒，较高射速／压力及较低每份弹药伤亡作用。精确武器默认容量2、装填12秒、瞄准20秒，较低射速及不同每份弹药作用。专门武器初始由 GROUP 模式继续执行本班火力；它仍排除原匿名份额，装填／瞄准耗时。个人动作接管同一份额。`release_weapon` 让普通武器回到匿名近似，让专门武器回到 GROUP，均不增加弹药或复制火力。

本人动作沿原 `body id JSON`：

```text
body look_direction {"action":"observe","node_ref":"D"}
body prepare_ammo {"action":"reload"}
body fire_visible {"action":"fire","target_ref":"<当前实际可见的单位ID>","seconds":60.0}
body stop_my_weapon {"action":"cease_fire"}
body guard_here {"action":"watch","node_ref":"B"}
body rejoin_fire {"action":"release_weapon"}
```

观察耗时5秒；只检查已知方向中实际可见的局部单位，也可发现实际所在节点的附近掩体。watch 在真实静止地点警戒，不生成全球自动观察。观察结果给本人 ground_contact／cover，带实际观察时间、坐标和射界信息。`combat_report id own_observation_id recipient` 使用原 Information 发送本人已产生的观察，接收者经过原时延和物理通信才取得知识。本人新观察的 message_id 同时是该 observation_id；可从原报告查询取得。

个人射击须在所属实际小组附近，单位须实际静止，装备和人物可用，目标处于当前射界。有效期正数且最多300秒；瞄准占该有效期。装填期间没有该份额的完整射击。准备弹药是单位库存中的占用，补给增加单位库存不会跳过个人装填。进入掩体、医护、搬运或其他身体动作会中断原精确操作；原 take_cover、wait、relocate 接口直接复用。射击或观察中的个人掩体暴露高于纯隐蔽；仍使用原伤病分配。

班长使用原军令通道的新文本别名 `tactics id owned_squad JSON`：

```text
tactics focus_fire node_unit_000 {"fire_mode":"concentrate","target_ref":"<已知目标单位>","seconds":60.0}
tactics suppress_direction node_unit_000 {"fire_mode":"suppress","node_ref":"D","seconds":60.0}
tactics local_cover node_unit_000 {"fire_mode":"cover_move","node_ref":"D","movers":["soldier"],"seconds":60.0}
tactics stop_squad node_unit_000 {"fire_mode":"cease"}
tactics resume_squad node_unit_000 {"fire_mode":"resume"}
```

还可给 fire_mode=watch。普通士兵没有该权限。目标／方向须来自本人知识，实际射界约束仍在执行端生效。集中火力只重新分配原份额；压制／掩护降低同批弹药的伤亡作用并提高压力作用。空方向可以消耗有限弹药，却不产生隐藏目标伤亡。cover_move 只支持本班最多4名实际人物进入他们已知的附近掩体，保留其他人员的掩护火力；移动仍耗时且可受伤。未实现道路上的交替跃进和任意编组机动。cease 同时停止该班当前个人／炮组射击；个人 cease_fire 只停自己的武器。有限火力期限结束后恢复原班组常驻行为。

已有炮组沿同一 `tactics` 入口，当前班长或在其实际指挥范围内的更高军官可发令：

```text
tactics deploy_gun blue_platoon {"gun_ref":"field_gun_1","gun_action":"deploy"}
tactics indirect_fire blue_platoon {"gun_ref":"field_gun_1","gun_action":"fire","claim_ref":"<本人已收到的 ground_contact 或 air_contact entry_id>","missions":1}
tactics direct_fire blue_platoon {"gun_ref":"field_gun_1","gun_action":"fire","direct":true,"target_ref":"<炮组当前可见的单位>","missions":1}
tactics reload_gun blue_platoon {"gun_ref":"field_gun_1","gun_action":"reload"}
tactics stop_gun blue_platoon {"gun_ref":"field_gun_1","gun_action":"stop"}
tactics pack_gun blue_platoon {"gun_ref":"field_gun_1","gun_action":"pack"}
```

部署耗 profile.deploy_seconds；收拢耗该时间的一半。每次火力任务最多8次有限作用，每次耗 cycle_seconds 和实际可用准备弹药；后续作用需 reload_seconds 及真实剩余弹药。部分弹药产生部分实际作用，报告保留 partial。间接火力保持原报告坐标／观察时间，不能追踪隐藏目标；直接火力要在实际射击时仍有射界。作用区内现有群体、离组身体和工事经原损失／空间路径处理，不指定击杀数字。不能越过现有作战任务的执行人取得同一炮组。展开炮组不能无时间代价随移动命令转移。

共同目的可用原 GROUND 任务的 fire_support；例如：

```json
{"operation":"begin","purpose":"recon_support","target_node":"A","priority":4,"deadline_seconds":1800.0,
 "tasks":[{"task_ref":"gun_support","domain":"GROUND","unit_ref":"unit_001","priority":4,"required":true,"followup":false,
 "goal":{"intent":"hold","target_node":"A","path":[],"return_to_start":false},
 "fire_support":{"gun_ref":"field_gun_1","target_node":"D","missions":2}}]}
```

上级只给目的和已知目标节点。实际执行人仍须收到该区域的位置报告；原自主转发可将上级已收到的相应报告沿通信交给他。实际到位、展开、装填、射击各经原命令与事件。fire_support 完成依据收到的实际炮组任务反馈，不依据单纯到达。其他任务的 after 可以依赖 gun_support。缺弹保留未完成次数，补给后仍需真实装填／续射。取消经原 Task8 停止。后续地面移动先收拢，再等待实际收拢报告。

构筑能力仍声明在原 engineers 中，例如 `"positions":{"personal":{"seconds":120.0,"spares":0.5},"squad":{"seconds":300.0,"spares":1.0},"weapon":{"seconds":360.0,"spares":1.5}}`。地点另给 `"position_sites":{"A":["personal","squad","weapon"]}`。GROUND 工程任务可给：

```json
{"task_ref":"dig","domain":"GROUND","unit_ref":"unit_001","priority":3,"required":true,"followup":false,
 "goal":{"intent":"advance","target_node":"A","path":[],"return_to_start":false},
 "engineering":{"action":"build","position_ref":"position_A_1","position_kind":"squad"}}
```

可给工程 xy，须在工作节点0.02km内；不改变道路和地图拓扑。工程沿原每段最多60秒的作业占用单位并消耗 SPARES。实际完成份额按稳定 position_ref 留在 Space；中断保留部分工程和已耗材料。个人工事接原附近掩体，班组／武器位置改变该位置的 terrain.cover；尚未完成的部分只有其实际进度效果。初始防护口径 personal 为0.65、半径0.005km；squad／weapon 为0.5、半径0.02km，再乘实际进度和完整性。它们不随单位移动，不赠送武器，不清除敌人。炮击可以损坏工事，尚未接入完整工事维修／维护。

人物查询新增本人 weapon 和仅从已收到 unit_state 构造的 tactical_reports。原有限自主政策可以依据收到的弹药、压制、目标与炮组状态停火、集中、压制、支援、收拢，或使用显式 construction_plans。普通步兵不运行完整个人 AI，当前玩家不被后台政策代发个人意图。原目的／任务容量不扩大。

尚不支持离组携枪及个人弹药物流、精确指定敌方具名人物、完整炮兵弹种／弹道、炮组具名操作员生命周期、任意地形阵地、大规模跃进、弃炮拖救和完整工事维护。没有正式宿主、GUI、地图或存档施工。本节只说明源码接口和规则，不声明运行正确性或性能。

## 2026-10-13 人员携行、未完动作与运行态

`transfer_person` 的原参数可以增加 `weapon_disposition`，取 `carry` 或 `leave`，默认 `carry`。仍通过原结构请求、当前权限和实际会合执行。携行转移原装备份额和当前准备份额一次；留置由原单位继续持有，不删除准备弹药。拆分的 `allocation` 必须覆盖随人武器和准备份额；合并和调动接收使用已经合并的库存，不重复转入。

```text
transfer transfer_1 5 {"person":"soldier","source":"unit_000","destination":"unit_001","weapon_disposition":"carry"}
body claim_1 {"action":"claim_weapon"}
```

`claim_weapon` 只接回本人原留置武器，须实际接触持有单位。`release_weapon` 也须在实际单位库存附近；它释放准备占用，库存总量不增加。`source_ref` 保留装备来源；`holder_ref` 和 `location_ref` 表达当前人物或单位持有。留置记录中的坐标是交接历史，不向人物公开远处持有单位的新位置。具体武器操作仍在原小组附近；离组携行不开放远程装填或精确射击。

身体移动、医护／搬运、失能及划转中断未来武器动作。原票据保留开始时间、持有关系和修订，陈旧事件只结束其旧责任。未完身体交接停止在当前插值位置。附近 `cover_move` 保留实际 movers 和原 action_ref 的完成／中断状态；掩护人员或弹药失效会中断局部移动。没有道路分批交替跃进。

原 A 文本入口增加：

```text
save_runtime D:/programs/WWO/research/military/wwo-person-attachment-20261011T0010/experiments/war_resolver/attachment_continuity/local_runtime.bin
load_runtime D:/programs/WWO/research/military/wwo-person-attachment-20261011T0010/experiments/war_resolver/attachment_continuity/local_runtime.bin
```

这是研究运行态文件，使用 Godot 二进制 Variant，关闭对象反序列化。只能在已完成结算边界使用；PENDING 拒绝保存和替换。加载先创建候选世界，失败保留当前世界，成功才安装。不会重跑开局配置、admit、初始库存或初始命令。人物焦点、权限、知识、动作去重和待决机会保持原状态。

代码接口：`F.runtime_state(env)`／`F.restore_runtime(image)`；A 场景 `runtime_checkpoint()`／`restore_candidate(image)`；Session `runtime_checkpoint()`／`restore_runtime(image)`／`save_runtime(path)`／`load_runtime(path)`。各原模块有相应权威字段及恢复绑定。`BattleState.snapshot()` 和原 Gameplay `snapshot()` 继续是诊断导出，不是可续接存档。

当前范围保存单位／身体与 LOD、原事件 ID 和时间、武器／炮组／fire_orders、医疗／占用／工程／阵地、现有陆海空模块、Task6 请求／交付／_assets／_reserved、Information 实际消息／知识／设备，以及 Task8 的绑定／等待／冷却和 auto、legacy、live 政策状态。库存和身体的别名在候选中重新绑定。自定义外部政策、外部报告生产者、旧诊断文件和 PENDING 内部游标不支持恢复。专业模块的所有变化组合没有在本轮逐一运行。

本轮授权的局部入口：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe' --headless --path 'D:\programs\WWO\research\military\wwo-person-attachment-20261011T0010' --script res://experiments/war_resolver/attachment_continuity/tests.gd -- --tactical-continuity
```

最终182项检查，0失败，输出无脚本错误。仅说明本轮相关短测结果，不代表全系统、性能或玩法验证。没有正式 SimulationStep／分钟 GameClock 接入，没有正式库存镜像，也没有经济商品批次或共同运力连接。

## 2026-10-13 道路两部分机动与携行火力

以下格式按代码接口编写，本轮未试跑。此前182项结果不覆盖这些新增行为。

当前班长沿原 tactics 入口提交一次意图：

```text
tactics <命令ID> <当前班节点> {"manoeuvre_action":"advance","movers":["<已有具名成员>"],"path":["<已知道路ID>"],"destination_node":"<已知端点>","target_ref":"<已观察或收到报告的敌单位>","require_cover":true,"seconds":600}
tactics <命令ID> <当前班节点> {"manoeuvre_action":"stop"}
tactics <命令ID> <当前班节点> {"manoeuvre_action":"resume"}
tactics <命令ID> <当前班节点> {"manoeuvre_action":"regroup"}
```

withdraw 使用相同参数，目的地和路线须明确且已知。先行部分只选已有成员，其余具名成员和匿名能力构成留守部分。最多四名先行成员、四段道路、3600秒原任务期限。起点须实际同地、FOOT、炮组已收拢，且没有医护、搬运、工程、运输等冲突。停步点仅支持现有道路／桥梁端点。

require_cover=true 需要实际可作用的明确目标及当前可用火力。先行人员到位、停止、瞄准以后，留守部分才移动；还须能够观察到实际到位信号。距离或声明射界不足会停止，接口不扩大射程。require_cover=false 可省略 target_ref，表示警戒机动，不产生压制或减伤保证。

stop 停在当前身体／道路进度，不退款、不退弹，不等同于停火。resume 接续剩余路段，保留原期限。regroup 从实际位置沿当前已经占用的路段返回该段起点，等待双方实际会合；不会搬走失能人员。新的整班路线／目标及永久成员划转、拆并须先会合。停火继续使用原 fire_mode=cease 或本人 cease_fire。

人物实际停住以后可使用原 body fire，射界从本人真实点计算。只有已携行的 ready 份额可在远处使用；reload／release_weapon 须接触原库存。原 fire_components 排除对应匿名份额，原库存支出和 GROUP／BODY 伤亡只采用一次。道路源位置仍使用当前锚点的声明可见性；不支持任意地形或边跑边精确射击。

非玩家政策可通过原 battlefield-actions 的 action_orders 为具体人物配置：

```json
{"action_orders":{"<已有班长>":{"tactics":{"enabled":true,"manoeuvre":{"manoeuvre_action":"advance","movers":["<已有成员>"],"path":["<已知道路>"],"destination_node":"<已知端点>","seconds":600,"require_cover":true,"regroup_on_stop":false,"resume_on_route_report":false}}}}}
```

政策只使用已收到的本班状态、敌接触和已知路线，选择有限意图，仍经原命令通道送达和当前权限检查。未默认开启全军机动。开启 regroup_on_stop 或 resume_on_route_report 只允许提出当前条件下的尝试，不保证会合或恢复。

本人 body 输出增加 road_action 和实际路段进度；原 tactical_reports 中的 manoeuvre 来自已送达报告，前方坐标只在报告来源可观察时给出，不公开远处准备弹药。查询不驱动移动、射击或装填。

原 save_runtime／load_runtime 保存新增阶段、成员和份额引用、路段动作、武器持有／火力所属、准备占用及原事件修订。环境版本为 war-environment-runtime-v2，旧环境v1明确不兼容。只支持完整结算边界；不恢复 PENDING 内部游标，不迁移正式宿主存档，不重跑开局或已完成动作。

## 2026-10-13 普通班组的两个匿名／混合行动部分

本节替代上节“先行部分必须具名”的范围限制。以下格式按源码接口编写，未试跑。旧 movers 输入仍可用，但会映射到同一 parts 表示，不运行另一套具名机动。

在原 tactics 入口的 manoeuvre_action=advance／withdraw 参数中，可以提供：

```text
tactics <命令ID> <当前班节点> {"manoeuvre_action":"advance","parts":{"front":{"members":[],"anonymous":4},"rear":{"members":[],"anonymous":4}},"path":["<已知道路>"],"destination_node":"<已知端点>","require_cover":false,"seconds":600}
```

4+4只示意当前匿名能力恰为8的合成量；不是现实人数、枪支或发数。提交前必须按实际当前能力分配。members 可省略或为空，也可列已有成员。两部分合计必须覆盖本班全部当前匿名能力及已有成员；具名健康不能再次计入 anonymous。两部分均需有剩余能力，同一成员不能重复。发令者仍须有当前班级权限，战斗成员不要求全部具名。

每部分可选 ammunition、equipment。ammunition 包含该部分所有具名 ready；两组总和必须等于当时原单位弹药。equipment 指尚未专门分配给具名武器的装备份额；两组共同划分这份现有装备。省略时按当前能力比例分配剩余份额，再计入已有武器和 ready，不增加资源。库存保管锚点是 rear，后续新到补给只增加该实际位置的可取得份额。

require_cover=true 仍须 target_ref 指向已观察或已收到报告的敌单位；实际几何、作用距离、人员、装备和本部分弹药不满足时会停止。false 表示警戒机动，没有隐含减伤。两部分使用原道路运动，先后到位并准备后改变职责；每段实际会合后可轮换先行部分。front／rear 是本次任务中的稳定身份，不随轮换重建。

stop、resume、regroup 继续使用上节格式。停止保留真实进度和支出；regroup 只沿当前路段返回本段起点，不搬走失能身体。新的个人动作不会被旧阶段清空。fire_mode=cease／watch 停止相应火力；fire_mode=resume 可恢复现有部分火力准备，不能代替 manoeuvre_action=resume 续行。实际会合不补弹；静止人员装填只取实际同位的本部分份额。

原 battlefield-actions 的 action_orders.<已有班长>.tactics.manoeuvre 可把 movers 换成相同 parts 对象。政策仍依赖已收到的本班状态、敌接触及已知路线，命令送达时再检查实际配额与权限。过时配额会拒绝，不补人补装备。没有开启该配置的单位继续原常驻算法。

范围限无炮组及非燃料依赖的 FOOT 班、同一已声明局部求解范围、最多四段道路、端点停步及当前路段返回。最多两个部分、四个班记录；起始已有身体须同地且无其他工作。未实现越野、车辆协同、任意路中停步规划、完整离组掩体操作、个人背包或单枪损毁模型。

原 save_runtime／load_runtime 使用环境 war-environment-runtime-v3，保存本轮分组位置、来源份额、弹药占用、身体关联、阶段和事件修订。环境v1、v2拒绝加载，避免猜测缺失事实。A／Session 外层保存入口保持；只支持完整结算边界，PENDING内部恢复、通用旧格式迁移、外部政策和正式宿主存档仍不支持。

## 2026-10-14 声明的局部非道路位置与机动

下列格式按代码接口编写，未试跑。原 battlefield-actions JSON 增加 local_sites、local_links、local_lanes、local_known 和可选 local_facts；默认都为空。不生成道路节点、人员、武器或库存。

- local_sites.<位置ID>：node_ref、xy（公里）、ground（原地形字段）、radius_km（正数，最多0.02）、enter_seconds（正数，最多120）。可选 position_ref 引用原 Space 工事；可选 cover_ref 引用当前真实个人掩体，两者不同时给。position_ref 可指向尚未施工的声明工事，但未实际可用时不能进入。天然位置只用声明 ground。位置距所属节点不超过0.25km。
- local_links.<段ID>：from、to、length_km、open、ground。端点使用局部位置ID或 node:<真实道路节点>；须同一cell，长度不短于坐标距离且不超过0.25km。它是局部 FOOT 通行段，不是战略道路。沿段直线插值；不支持任意道路中途接入。
- local_lanes：键为 <来源引用>><目标引用>，值为 {"observe":true,"fire":false} 等独立声明。来源／目标可以是 node:<节点>、局部位置ID或 segment:<局部段ID>。方向不自动反向，未声明即不可用；道路之间保留原 lanes。路段中使用 segment 引用及实际进度坐标。声明射界仍受原观察距离、武器射程和实际地形限制，不代表完整现实视线。
- local_known.<已有人物>.<目的位置引用>：已知路径数组的数组，例如 [["access_1"]]。进入原人物 known_routes 的 local:<目的引用>，只表示初始已知地图，不提供即时敌情、工事状态或免费报告平台。
- local_facts：可选列表，每项 {"id":"<稳定ID>","at":<秒>,"link_ref":"<已有局部段>","open":false}，最多8项，沿原 spatial 世界事件生效。恢复不会重发。

班长仍沿原 tactics 提交，parts 完整沿用上一节的匿名／混合份额：

```text
tactics <ID> <当前班节点> {"manoeuvre_action":"advance","parts":{"front":{"anonymous":<份额>,"members":["<已有成员>"]},"rear":{"anonymous":<余量>,"members":[]}},"local_path":["<已知局部段>"],"destination_ref":"<局部位置ID>","require_cover":false,"seconds":600}
tactics <ID> <当前班节点> {"manoeuvre_action":"stop"}
tactics <ID> <当前班节点> {"manoeuvre_action":"resume"}
tactics <ID> <当前班节点> {"manoeuvre_action":"regroup"}
```

withdraw 使用相同路径参数，目的必须通过已知道路／局部关系解释。不能同时给 path 和 local_path。regroup 仍只返回当前段起点；已经到另一端的部分须有可进入的原段，不能穿过关闭的新段。两部分可以均无 members；具名成员及匿名份额、装备和准备弹药不重新初始化。require_cover=true 还须给实际观察或收到报告的 target_ref。掩护火力从留守部分真实位置产生，失去条件会停在已经经过的位置。watch 不提供隐含减伤。

到位后再执行 enter_seconds；front 到位不代表 rear 到齐。两部分和必要身体实际会合且无实际敌方争夺，才结束本次局部机动。进入工事读当前完整性和施工进度，离开即解除地点效果。局部目的完成不直接完成城市／道路节点控制。原任务和期限继续存在。

个人动作沿原 body 入口，只控制本人；活动两部分期间保留互斥限制：

```text
body <ID> {"action":"relocate","local_path":["<本人已知局部段>"],"destination_ref":"<位置ID>"}
body <ID> {"action":"relocate","local_action":"stop"}
body <ID> {"action":"relocate","local_action":"return"}
body <ID> {"action":"relocate","local_action":"enter"}
```

个人路径结束在战术位置时尝试耗时进入。stop 只中断本人尚未完成的局部动作；return 只从本人已占用的中途段返回其起点。停在端点后的撤回需要本人已知的反向局部路径。受伤、失能、断路或严重压制保留实际位置，后来的医疗和旧到达票据不互相覆盖。新个人任意中途改道、局部搬运／遗体运输仍不支持。

静止后复用 observe／watch／fire／cease_fire／reload。射界来自本人或部分实际位置；移动／进入期间不能获得完整静止射击。离组准备份额可用，留在原库存的剩余量不能远程 reload。父班锚点无人员时不额外成为完整交战位置。工事空间效果和原个人掩体不重复叠加。物理陆运、港口同点交接只在实际声明交接点完成，尚无向任意非道路位置发货的车辆路径。

可选 action_orders.<班长>.tactics.manoeuvre 用同样 local_path／destination_ref／parts 替换原 path／destination_node。沿原政策和 Task8；不扫描最优掩体，不自动启用全军。resume_on_route_report 只在收到新的局部通行可用报告后恢复相应断路任务。局部通行报告须报告来源能够实际观察声明段及两端，旧报告不刷新观察时间。

本人输出增加 local_place_ref、entered_site_ref、known_local_places 及 road_action 的 travel_kind／local_edge／local_progress_km。known_local_places 是本人已有地图，不含隐藏实时库存或敌情。观察得到的 local_sites 进入原 Knowledge；上级看原已送达 tactical／unit_state 报告。查询不生成分组、移动或开火。

恢复格式改为 war-environment-runtime-v4，拒绝旧环境v1／v2／v3。原 save_runtime／load_runtime 和候选装配保存同一身体、parts、准备占用、局部进度、进入阶段、消息及原事件ID；不重开任务，不补资源。地点上的完整结算状态可以保存进行中动作，PENDING 内部和正式存档仍不支持。当前兼容规则不能把局部位置替换为道路节点，故该位置及未完动作保持必要详细表示。
## 2026-10-14 局部携弹与具名救援接口

以下按源码接口编写，未试跑。沿用秒和公里。位置、local_path、local_lanes、人物、武器和原库存必须实际存在；示例引用是占位符，不创建对象。

- 个人领取：`body id {"action":"ammunition","ammo_action":"take","source_ref":"unit","quantity":2.0}`。活动分组需先停止；可用来源也可写 `part:front` 或 `part:rear`。实际接触、健康、容量及操作占用在执行时判断。份额仍在原单位总弹药内。
- 本人携行：领取后使用原 `body id {"action":"relocate","local_path":["已有局部段"],"destination_ref":"已有局部位置"}`。中断保持实际位置和未交份额。`reload` 优先从本人真实备用份额装填；不从远处父班补弹。
- 个人交接：`body id {"action":"ammunition","ammo_action":"handover","target_ref":"part:front","quantity":2.0}`。可交给同班 `person:已有人物`，或同地 `unit` 库存位置。接收不立即填弹。
- 班级交接：`tactics id current_squad {"ammo_action":"handover","source_ref":"part:rear","target_ref":"part:front","quantity":2.0}`。两部分必须真实接近并停止。作业占用来源/接收部分的相应能力；不会创建第三个部分。
- 原部分携弹移动：`tactics id current_squad {"ammo_action":"move","part_ref":"rear","local_path":["已有局部段"],"destination_ref":"已有位置"}`。只支持已停止的现有两部分、两个明确端点、原期限内及承运部分实际份额/能力。复用原 manoeuvre；到位停下，仍需交接。其他部分保持原位置。
- 滞留接走：同班实际可接近的人员使用 `body id {"action":"ammunition","ammo_action":"recover","source_ref":"stranded:原携运人物","quantity":2.0}`。只作用于这一有来源的未毁损保管责任。无全世界物品搜索。
- 携带容量：每实际健康能力份额4个合成弹药单位。作业耗时5秒加本次可交数量。身体携行使用原 carry_speed_factor。不是现实弹药重量或装备标准。每班一个交接作业，最多两个原部分；具名保管记录最多6个。
- 救援接近：`body id {"action":"rescue","patient_ref":"已知具名患者","local_path":["已有局部段"],"destination_ref":"已知最后位置","pickup_on_arrival":false}`。true 为到达后尝试接走，默认 true；false 为先到场，可由合格人员使用原 aid/stabilize/treat，且医疗库存必须实际同地。搬运资格不等于医疗资格。
- 接走：`body id {"action":"rescue","rescue_action":"pickup","patient_ref":"已有患者"}`。实际接触 WOUNDED/INCAPACITATED 身体后按原个人动作计时，不改变伤情。
- 搬运：`body id {"action":"rescue","rescue_action":"carry","local_path":["已有局部段"],"destination_ref":"已有后方位置"}`。原 BODY 随搬运者的位置和进度移动。`rescue_action=stop` 中断并在真实位置放下，`return` 沿当前占用局部段返回，`put_down` 在当前位置耗时放下。
- 道路接续：到达实际 `node:道路节点` 后提交 `body id {"action":"rescue","rescue_action":"road","path":["已有道路"],"destination_node":"已知后送节点"}`。使用原道路搬运入口，不瞬移，不承诺医院治疗。
- 班长安排：`tactics id current_squad {"carrier_ref":"本班已有人员","rescue_order":{上述rescue输入}}`。命令送达仍重验当前权限，助手在执行时按本人身体、已知局部路线和原资源条件处理。当前不支持跨班患者交接、匿名担架组或带着未结弹药同时搬运患者。
- 可选 `action_orders.<人物>.local_support`：显式 `enabled:true`；`ammunition_orders`、`rescue_orders` 各最多4个候选。携弹候选用 `values` 存上述班级输入，可设置 `when_unit_low`、`when_part_low`、`threshold`；部分弹药只采用实际收到的同地库存信息。救援候选声明 `carrier_ref`、`patient_ref`、`approach_path`、`patient_place`、`carry_path`、`drop_place`，可声明 `road_path`/`road_node`。政策只使用新鲜已收报告和已知路线；没有报告、无路线、占用或同一尝试依据未改变时保持原状态。玩家控制排除沿用原决策机制。
- 本人输出提供 carried_ammunition、local_rescue 和原真实位置；上级经原 Information 获知，不因查询更新资源或推进动作。现场发现患者使用现有 observe/person_report 与合法报告链。
- 运行态为 `war-environment-runtime-v5`。保存原库存引用、保管份额、收交计数、患者双向搬运关系、局部职责、未完个人/部分动作与事件。v1/v2/v3/v4 明确不兼容；仍仅在完整结算边界保存/候选恢复，不支持 PENDING 内部游标、外部自定义政策和正式存档。