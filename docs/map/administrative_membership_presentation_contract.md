# Administrative membership / territory / control：Presentation 边界

本文件是后续接入约束。Administrative Region Foundation R1 已接入法国两个历史身份的只读资料页，以及独立合成成员实验；没有正式行政成员系统、占领算法、行政编辑器或持久化变更。详见 [R1 审查与验证报告](administrative_region_foundation_r1.md)。

## 身份和关系

`territory_unit_id` / spatial unit 表示土地身份，`geometry_ref` 表示当前有来源的空间形状。Province / State / Département / Oblast 是国家的 **mutable administrative grouping**：它拥有自己的稳定身份及可变名称、首府、层级和成员土地集合。历史行政 polygon 是初始成员配置的证据，不是永久 Province identity；改名不生成土地 ID，拆分/合并不改写原土地的身份。

未来的只读 Presentation 输入必须分别提供：

| 关系 | 输入职责 | 禁止推导 |
|---|---|---|
| sovereignty | 土地 → sovereign polity | 不能从 fill texture 或行政 polygon 推断 |
| controller | 土地 → current controller | 不能因为一块土地被占领而覆盖整个行政区 |
| administration | 土地 → 当前国家、层级下的 administrative membership | 不能从 controller 自动重写 |
| administrative grouping | administrative ID → 成员土地、名称、首府、membership revision | 不把一个 source polygon 的 ID 视为永恒身份 |

例如一块土地可以 sovereign=France、controller=Germany、administrative membership=French département Y。行政区未占领 / 部分占领 / 全占领只能从其成员土地的控制状态计算。本轮不存在此类占领计算，也未改现有 controller / sovereignty。

现有 `VNextTerritoryUnit` 是目录几何单元；现有 `AdministrativeLoader.runtime_units` 是资料卡中的历史名称列表，不能把其按顺序生成的 dossier ID 直接升级为未来行政实体 ID。两个类型均不是已完成的 Province gameplay。

## 边界显示缓存

Renderer 的 `administrative_boundaries` 是一个当前为空的 Presentation 缓存接口，与国界批次、physical coastline、铁路/河流分开。没有历史几何时不初始化行政区域，也没有 modern admin1 fallback。

未来接入步骤：

1. 权威行政服务提供 detached membership view 和单调递增 revision。
2. Create / split / merge / reassign 的变更事件明确列出受影响的新旧 administrative IDs。
3. `membership_changed(affected_ids, revision)` 只使这些缓存失效；其余行政区保留。
4. 后台/受控任务由成员土地计算边界，准备 static batch。当前没有实现 union。
5. 用 `store(region_id, revision, geometry)` 发布；旧 revision 的异步结果被拒绝。Renderer 只读取已准备的缓存。

Camera pan、zoom、map mode、label collision 不触发 membership revision，不调用 union，不失效行政边界。Rename / capital change 可更新标签资料；如果成员没有改变，不重建 polygon 边界。Controller change 更新独立控制层，不把行政 grouping 当作占领原子单位。

缓存不保存行政 membership、不执行编辑，也不写 WorldState / save。其回归覆盖受影响区域失效、未受影响区域保留、旧 revision 拒绝和 dissolved grouping 的空边界。

R1 增加 `retire(region_id, revision)`：停用单位只清除该单位 geometry/dirty，保留单调 revision 墓碑以拒绝尚未完成的旧结果；`metrics()` 只读返回失效、存入、停用及驻留计数。没有每帧调用或新增 GPU batch。独立合成夹具用精确共享边抵消研究边界更新，不是正式 GIS polygon union。

## 聚合尺度

50 km strategic、25 km operational、5 km detailed local 是未来计算/查询/LOD 的聚合尺度，与行政 identity 无关。行政区可跨任意数量聚合单元；任何网格都不能定义 Province 边界。当前地图不绘制网格，也没有新增或持久化聚合 cell。

## 当前资料缺口

Paris shard 的历史 admin polygons 仍为 0：`ADMIN_BOUNDARY_DATA_GAP`。无 terrain / DEM / hillshade 资料准入：`TERRAIN_DATA_GAP`。没有为了填图引入现代行政或道路数据。
