# 原生隔离训练嵌入

本模块适配初始化、显示、会话生命周期、部署/实体炮弹接线与地形所有权。默认保留单敌车；显式 `profile="field_170"` 为尚未达标的满规模场景配置。坦克/炮塔驾驶、GroundSupport、VehicleContacts、车组上下车、唯一有限弹药池、原炮口/炮手/装填、实体炮弹飞行碰撞与 Combat 伤损仍由原军事源码执行。不安装工程支援、独立诊断宿主、常驻性能采集器或全局渲染/模拟速率 helper。

## 嵌入 API

`controller.gd` 是 Node。主仓入口为 `res://military_runtime/native/modules/isolated_training/controller.gd`。

```gdscript
controller.prepared.connect(on_prepared) # status: Dictionary
controller.failed.connect(on_failed) # reason: String
controller.observer_requested.connect(show_observer)
controller.start({"viewport": observer_viewport, "world_root": optional_identity_root, "provider": layered_terrain})
```

- viewport 必须是现有、已入树且 own_world_3d=true 的观察 SubViewport。模块不替换 World3D，不新建环境/灯光，不接正式人物或 WorldState。
- world_root 可省略。提供时须在该视口内，global_transform 为单位变换；原生米制空间不能另行缩放/平移。
- provider 必须实现 `create_surface_material(options)` 与 `set_external_native_owner(bool)`。close/far 直接使用共享材质 factory。接已有 changed 信号唤醒纹理异步更新。
- `pause()`/`resume()` 保留同一 battle、车组字典、弹药池、弹丸、靶损、地形编辑和位置。pause 先清零全部 native collider 的 layer/mask，再交还观察地面；resume 先撤观察近景，再还原 native 碰撞。不会改 SceneTree.paused。
- `close()` 才明确结束会话。返回观察、地图切换或菜单不会创建新 battle。准备中的 pause 延后到原五人绑定及 install 完成，不重复安装。
- `set_input_exclusions(Array[Rect2])` 使用该 viewport 坐标。输入仍由原 mobile_battle 处理。
- `request_frame()` 只请求 UPDATE_ONCE。移动/转炮/视角变化、原装填、实体弹飞行、VFX、烟幕、地形流入/编辑期间逐帧请求，静止后停止。最后一帧负责清除已结束效果。
- `get_status()` 是事实副本：state/ready/paused、world_position、crew/registry、native_ammo（完整 canonical snapshot）、ammo（主炮状态）、target.modules/crew、shot_audit/incoming_audit、driving/ground_support 等。`formal_world_player=false`。
- `get_native_battle()` / `get_native_camera()` 仅供手动 driver/debug 读取原生对象、投影和原坐标；不属于正式世界控制接口。

## 不变边界

原 default_request 安装一次。五个稳定 person_id，车长 HP7/左臂 injured，AP6/HE2/smoke1 已消耗，原40主炮弹剩31。所有 garage/reset/select_unit/select_catalog/cycle_target/cycle_terrain/load_display/clear_stage 与弹药恢复入口被锁；不写正式存档或外部租约返回文件。

同一原Kestrel/Combat/三乘员在准备阶段一次放置于中央道路(0,110)m，接入原ai_armor观察、驾驶、炮塔及伤损。主炮采用原Shell实际飞行接触，MG保留hitscan；原大军部署不删减。外装layer1、内部乘员layer2、原LOS/天气/烟幕保留，没有强制命中或修改forced_roll。

近景唯一 owner 为原 Ridgevale + streamed_battle_terrain，包含 actor/固定靶流式 anchor、collision、support、形变及原事务。4m 原场双线性生成1m顶点，sample_height 与同1m碰撞三角使用相同对角重心插值；不抬平或改原高程。

## 主仓快照与资源

主仓 `military_runtime/native/` 是本次受控军事源码/配置快照。既有源码仅统一 res 前缀；Ridgevale terrain/world/heightfield 的运行时近景资源统一复用主仓 `assets/terrain/region_slice/`，不重装已有地形二进制。依赖闭包中的原小型 JSON 元数据保留为源码快照，不另建地形 owner。原目录的非嵌入可选宿主可能保留在依赖快照中，但本模块不安装或调用它们。

17个原资产从既有恢复 staging 复制到相同 native relative 路径；JSON 只变换 res 路径，不改原元数据/既有 source_sha 等字段。8个 GLB 由 .gitignore 排除，raw staging 不动。原 armor_collision 运行时 source 检查完整保留；导出须保持其原始 GLB 可由 FileAccess 读取，不可只留下 imported remap。

## 原模型附件安装

沿用 `tools/map/install_region_slice.py`。旧无参数及 `--from-zip` 用法仍只安装原地形附件；旧地形 README/元数据未改。

```text
python tools/map/install_region_slice.py --with-training
python tools/map/install_region_slice.py --training-from-zip PATH/wwo-native-training-models-v1.zip
python tools/map/install_region_slice.py --from-zip TERRAIN.zip --training-from-zip MODELS.zip
```

`--with-training` 沿用既有地形安装，并从同一 draft tag `untagged-75a9dbc800223cbf8a18` 获取 `wwo-native-training-models-v1.zip`。单独 `--training-from-zip` 只安装/复用八个原 GLB，不触发地形下载。训练附件及解压总量分别限4MiB，固定八路径白名单；所有目的文件先直接 byteequal 比较，缺失文件只用 xb 创建，不覆盖不同内容。九个 prefixed JSON 留在源码交付，不在 binary 附件中。

`military_runtime/TRAINING_ASSETS.json` 记录沿用的原 source/range provenance，并与附件内同名记录绑定，不新增摘要。上传后的新附件 asset ID 应另作发布说明，不修改这个版本已经打包的来源记录。授权的本地附件安装已执行一次：Installed 0，reused byte-for-byte 8，无覆盖。

## 2026-10-26 主宿主窗口有限事实

作者实现阶段未自行运行引擎、测试或 Git。以下来自 Lead 在主线宿主 `battle-main-final` 窗口的既有 driver 报告；没有独立启动军事工程引擎。

- 两发 AP，主炮余弹 31→30→29。第一发 blocked（左侧50未穿透）；第二发命中 rear35 并 penetrated，靶车 rear integrity 100→85，三名靶乘员 HP 10/10/10→7/6/8。
- 原车长 HP7、左臂 injured 未被治好。经原 UI 下车，实走位移3.446m，离原车达6.310m，再步行返回并占回原 seat0；上下车未补回弹药。
- sameActor、sameSession、同载具实例、暂停恢复状态保留及正式世界快照不变，均为既有 driver 比较报告，不是此文重新运行或独立重算；不能据此宣称全部军事能力通过或用户已验收。

## 2026-10-27 主宿主原规则对抗

下述单敌车历史运行源码为军事commit `01caf7907a8fe063e89ad16baf2e96f27f56abef`；当前快照来源见[NATIVE_SOURCE](../../../NATIVE_SOURCE.json)，不把后续commit当历史运行来源。规则在军事仓修改后用[同步命令](../../../../tools/map/sync_military_runtime.py)确定性更新，不手改两份规则。`get_player_status()`仅给本车横幅state/ready/on_foot/driving/ammo；完整`get_status().encounter`为driver-only，不作为隐藏敌情HUD。

主宿主完整实窗退出0：玩家驾驶20.263m、敌55.691m；原菜单标尺100m后两发AP实飞105.076m/0.657463s、51.731m/0.323464s，余弹31→29。敌front完整度100→78、三crew10/10/10→0/6/7；敌炮手/驾驶员仍活，不宣称全敌失能或胜利。敌两发真实来袭被我方装甲挡住。同车长实走3.286m、离车6.283m，原UI返同seat0/同Actor，HP7伤臂保留；暂停冻结、恢复、原菜单返回及正式世界比较均通过。首个独立会话冲近暴露侧面导致玩家车长阵亡，失败记录保留，未降低AI伤害或重生该会话。详见[主宿主说明](../../../../docs/maps/layered_military_region.md)。

这不是军事工程独立启动、全量回归或用户接受。原167.555ms尖峰仍未关闭；局部建块优化不能外推整体稳定。

该单敌车历史轮 NOT_RUN：HE、MG、smoke、拒绝负例、长时运行、正式部署、存读。正式保存、export、合并均未执行。

## 满规模20车＋150独立步兵：当前未通过

`field_170` 复用原Actor/Brain/person/有限弹药及19个原AI车辆，150人不含另计62名车组（玩家5＋AI57），分三路使用原5km高程、林地及村庄。准备分批创建并等待地形注册，活动后不按镜头冻结。军事源码只在canonical仓修改，再按固定commit同步。

| 真实同初始规模窗口 | 早期活动FPS / P95 | Armor平均每physics | 步兵事实 |
|---|---:|---:|---|
| `51e3d59` 未优化 | 1.822 / 591.333ms | 14.119ms | 150人0枪，24蓝有自己LOS，其余51蓝及全部红被贪心预算饿死 |
| `080003f` 同次查询消重 | 1.845 / 600.558ms | 13.144ms | 仍0枪；不能把微小收益或更差尾帧称修复 |

初20车/150独立ID/150活动Actor/62crew成立；19 AI车实际移动且部分按原弹药交火，不是假静态布置。慢render帧含8个physics，Actor最高405.925ms；motor/nav/sense/other均有成本，pose最高6.982ms，只有7次A*，不把性能归咎模型或共享规划缺失。初末完整流程仅推进约25秒模拟；所测活动阶段合计约60秒墙时，另有输入/上下车等待，不能直接当同区间倍率。明确不达30FPS。整卡GPU约1–4%含桌面，不能当进程GPU时间；CPU约满一核。

消重轮真实玩家AP1/HE1、SMK0；原车长上下车/伤弹、同会话暂停、25km上级图→5km重入和正式世界比较保留。没有烟弹就不记成功；自然伤亡/空弹、主动全会话暂停60FPS都不是完整负载通过。旧167.555ms来自历史观察步行，51.777ms为观察碰撞安装最大区间，缺旧同帧子段，不与native构建或51.447ms worker等待混为一谈。未合并、导出、发布Release。

后续实窗继续失败，未把改进包装成完成：

- `4822e46` 公平感知使150人全有自己的ray、全部实际位移>1m，身份未替换；蓝0枪/红3枪，仍1.733–1.991FPS。
- `d447d8d` 在本人fresh自见目标内优先接战范围，使39名射手74次实际射击、蓝红均开火；不拿最近敌真相代替LOS。结构命中约54k次，ownRID局部降低但capture/layout未提速，活动1.501–1.873FPS。
- `3ccfdbe` field-only原运动/nav20/60Hz，仍逐tick运行Brain/感知/fire/伤弹；原五人/玩家保留原路径。147人有低风险服务，但未知floor-snap支撑保守回60，实际平均45.49Hz；累计delta最大.05sim，未丢时或加速。开场2.079FPS/P95 509.004ms、持续2.261/P95 474.306，phase模拟/墙时仅.252–.314，明确未达30。49射手106枪、双方各53；150ID/实例不变，末50蓝/42红存活，不把自然减载当满载通过。玩家AP1/HE1、SMK0、驾驶2.972m，玩法整体仍失败；原车长伤弹/返同座、同会话/正式世界比较保留。
- `f1f5a09` 精确活读后的immutable snapshot试验：同开场capture99.47→112.58µs、layout61.39→70.76µs，没有净收益证据，`2baf779` 已回退。不继续叠缓存。后续`a48bc75`补真实native本体支撑：32255次实际命中原静态地形，实际平均28.17Hz；诊断轮1.304–1.526FPS、关闭诊断1.129–1.426FPS仍失败。两轮与外部3-worker地形采样重叠，OS亦见第二Godot与约237%单核等量Python负载，不作干净AB、不停止他线，也不拿此掩盖早先约2FPS失败。新risk段77.997ms/8tick，说明索引本身须优化；不降视觉预算、射击条件或接触精度。

## 本轮成本收敛与延长窗口：未达30FPS

- 核对宿主/军事计算/隔离运行/历史研究，没有可删的第二套crew/ammo/health owner。Armor think已有0.65s，导航为逐Actor局部scratch与原全Host最多一次plan/physics预算；共享小队全图不是这轮小改。原视觉LOD换共享Mesh/pose interval，不冻结physics/fire。不按入口未加载删研究码。
- 军事提交`a20df84`只作Actor/Host风险同call getter/几何去重；`0490c8e`只作Resolver每capture紧凑fresh Transform/整数路径，不跨capture比较/COW，不减形状/.045步长/query/callback，不改原插值或军规。主仓仅固定commit的确定性集成，无独立规则修改。
- 既有driver延长30s运动/30s玩家静止AI活动/30s接战/60sHE/30s烟/60s持续，补P99/每phase实际人数与弹药。默认关闭诊断约247.65s活动采样，仍20车/150独立兵/62双向座/212人；150全移动、19AI车全移动/16实射，双方69射手154枪。末57活兵不能当满载通过。原车长同Actor实走返原座，后来真实受伤HP7→3未治好，AP1/HE3/SMK1实耗；驾驶1.322m仍失败。
- 默认开场1.165FPS/P95 1034.489/P99 1073.738ms，静止玩家1.105/1061.497/1125.734，接战1.295/912.870/954.539，HE1.232/962.184/1035.569，持续1.421/845.245/896.630。CPU约满一核，整卡GPU1–4%非进程GPU时间，工作集1323–1351MiB。没有30FPS或完整操作验收。
- 风险µs/callback原始81.985→39.481→69.282，未改车辆控制组也约减半；不能归因或声明稳定净收益。风险轮44–60FPS时是原车长真实阵亡、battle_finished/physics-active=0，已判无效，不拿结束/自然减员/空弹过线。当前native terrain49.481ms主线程区间不等于旧观察51.777ms；旧167.555ms仍未关闭。日志无SCRIPT ERROR/ERROR，原warning保留。分阶段资源及四轮结果见[既有说明](../../../../docs/maps/layered_military_region.md)。未合并、导出、发布。

## 原热路径第二轮

- `f0ab400`单weight active world表只让shape段20.070→17.680µs，capture＋resolve父段却276.199→283.285µs、全军运动1.980→1.899FPS；未证实净收益，`e3b2bcc`已回退，不保留额外表。
- `a6b279c`仅在原时钟已保证本tick服务时省邻格分类，保留原入口、ensure/terrain/epoch、自身shape门及所有运动/支撑/Brain/感知/fire/伤弹。非mandatory仍完整live风险；`scheduled_unclassified_solves`单列，不当低风险/风险下降。不是降服务Hz，不改部署或用睡眠减载。详见[既有说明](../../../../docs/maps/layered_military_region.md)。
- RTX诊断首样本54450callbacks=22926solves+31524deferred，solves=0 classified-low+4973 classified-high+17953 scheduled；max.05sim/pending max.0333不变。仍1.446FPS开场/1.515持续，稳定净增益未证实。
- 同源码默认长窗实际切到Intel Iris Xe，不是RTX；NVIDIA0%/0MiB不是游戏GPU负载，不用于RTX对照/验收。245.827s活动采样1.091–1.405FPS，150人全移动、19AI车全移动/实射，63步兵射手159枪；驾驶1.321m、HE段2发及观察步行collision检查失败。身份、原车长同Actor伤弹和正式世界隔离比较保留；设备漂移/Intel与进程GPU缺口见既有说明。
- 10月28日固定`c5cab17`默认复核已由日志确认实际RTX/Compatibility；244.470s活动采样开场1.923FPS/P95 558.533/P99 562.804ms、静止1.944/555.633/588.301、HE2.393/475.742/503.101、持续2.752/417.446/445.165，模拟/墙时.256–.367。CPU约满一核，工作集1317–1347MiB；整卡GPU2.2–4.7%不是进程GPU时间。新标签只标明游戏PID/实际adapter/采样scope，不增测量。
- 150人全移动，19AI车全移动/18实射，75步兵射手159枪。AP1/HE5/SMK2、HE段4发过原密集门但FPS失败；驾驶2.973m仍失败。原车长同Actor伤弹/返原座保留、自然HP7→3；步行/同会话/正式世界比较通过。末31活兵不能验收满载，稳定净收益未证实。
