# V2.3 存档 Schema

## 版本

V2.3 Schema ID 为 `v2_3_space_cognition_1`，默认评审槽位为
`user://saves/v2_3_space_cognition_slot.json`。存档是可读 JSON，只保存权威可变状态和稳定
ID，不保存 Godot 节点、对象地址或重复静态地点/交通配置。

## 核心字段

存档包含唯一权威时间与随机状态，以及 V2.2 人物、日程、住户、账本、状态、合同、出勤、
组织和通知状态。V2.3 新增：

- `spatial_state`
- `travel_graph_state`
- `travel_state`
- `communication_state`
- `knowledge_state`
- `dynamic_relationship_state`
- `appointment_state`
- `introduction_state`
- `npc_spatial_state`
- `background_person_ids`
- `processed_hour_keys`

这些字段保存途中路段、待投递/未读消息、知识过期时间、六维关系、约见状态和各领域幂等键。

## 完整性与原子保存

快照先按键稳定排序、把等值整数浮点归一化，再对不含 `integrity` 的内容计算 SHA-256。
保存只允许 `user://` 下的 `.json`：

1. 写入并刷新 `.tmp`；
2. 重新读取、解析、验证 Schema 和摘要；
3. 将有效主文件更名为 `.bak`；
4. 将验证后的临时文件原子替换为主文件；
5. 替换失败则恢复备份。

加载先验证主文件；主文件损坏时可读取有效 `.bak`。主文件和备份均损坏时明确失败。

## 恢复安全

恢复先验证所有必需对象/数组/非空 ID 和摘要，再调用模拟组合根恢复。任何失败都不会修改当前
运行状态。恢复后继续验证人物位置、途中路线、消息队列、未读状态、知识时效、约见、关系和
幂等键。旅行扣费、消息投递和关系/约见结算的幂等键跨存档保持。

历史上限由 `v2_3_balance.json` 控制：旅行计划 128、消息 256、每人物知识 256、每关系互动
32、约见 128、幂等键 1024。
