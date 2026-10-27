# 原生隔离训练嵌入

本模块只适配初始化、显示、会话生命周期、单敌车部署/实体炮弹接线与地形所有权。坦克/炮塔驾驶、GroundSupport、VehicleContacts、车组上下车、唯一有限弹药池、原炮口/炮手/装填、实体炮弹飞行碰撞与 Combat 伤损仍由原军事源码执行。不安装独立军队、工程支援、诊断宿主、性能采集器或全局渲染/模拟速率 helper。

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

运行源码固定在[NATIVE_SOURCE](../../../NATIVE_SOURCE.json)所记军事commit `01caf7907a8fe063e89ad16baf2e96f27f56abef`；规则在军事仓修改后用[同步命令](../../../../tools/map/sync_military_runtime.py)确定性更新，不手改两份规则。`get_player_status()`仅给本车横幅state/ready/on_foot/driving/ammo；完整`get_status().encounter`为driver-only，不作为隐藏敌情HUD。

主宿主完整实窗退出0：玩家驾驶20.263m、敌55.691m；原菜单标尺100m后两发AP实飞105.076m/0.657463s、51.731m/0.323464s，余弹31→29。敌front完整度100→78、三crew10/10/10→0/6/7；敌炮手/驾驶员仍活，不宣称全敌失能或胜利。敌两发真实来袭被我方装甲挡住。同车长实走3.286m、离车6.283m，原UI返同seat0/同Actor，HP7伤臂保留；暂停冻结、恢复、原菜单返回及正式世界比较均通过。首个独立会话冲近暴露侧面导致玩家车长阵亡，失败记录保留，未降低AI伤害或重生该会话。详见[主宿主说明](../../../../docs/maps/layered_military_region.md)。

这不是军事工程独立启动、全量回归或用户接受。原167.555ms尖峰仍未关闭；局部建块优化不能外推整体稳定。

NOT_RUN：HE、MG、smoke、拒绝负例、长时运行、正式部署、存读。正式保存、export、合并均未执行。
