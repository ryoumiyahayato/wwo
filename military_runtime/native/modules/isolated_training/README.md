# 原生隔离训练嵌入

本模块只适配初始化、显示、会话生命周期与地形所有权。坦克/炮塔驾驶、GroundSupport、VehicleContacts、车组上下车、唯一有限弹药池、原炮口/炮手/装填、实体炮弹飞行碰撞与 Combat 伤损仍由原军事源码执行。不安装独立军队、工程支援、诊断宿主、性能采集器或全局渲染/模拟速率 helper。

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

保留原 Kestrel 固定靶的外装 layer1、内部乘员 layer2。仅撤销 skirmish 的 blanket hide，继续使用原 LOS/天气/烟幕。没有强制命中，不改 forced_roll。

近景唯一 owner 为原 Ridgevale + streamed_battle_terrain，包含 actor/固定靶流式 anchor、collision、support、形变及原事务。4m 原场双线性生成1m顶点，sample_height 与同1m碰撞三角使用相同对角重心插值；不抬平或改原高程。

## 主仓快照与资源

主仓 `military_runtime/native/` 是本次受控军事源码/配置快照。既有源码仅统一 res 前缀；Ridgevale terrain/world/heightfield 的运行时近景资源统一复用主仓 `assets/terrain/region_slice/`，不重装已有地形二进制。依赖闭包中的原小型 JSON 元数据保留为源码快照，不另建地形 owner。原目录的非嵌入可选宿主可能保留在依赖快照中，但本模块不安装或调用它们。

17个原资产从既有恢复 staging 复制到相同 native relative 路径；JSON 只变换 res 路径，不改原元数据/既有 source_sha 等字段。8个 GLB 由 .gitignore 排除，raw staging 不动。原 armor_collision 运行时 source 检查完整保留；导出须保持其原始 GLB 可由 FileAccess 读取，不可只留下 imported remap。

本模块实施阶段不运行引擎、不执行测试或 Git。解析、实机驾驶/原伤损/原弹药守恒与嵌入交还由 Lead 统一验证。未运行不表示通过。
