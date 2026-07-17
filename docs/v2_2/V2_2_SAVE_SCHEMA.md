# V2.2 存档结构

V2.2 评审存档版本：

```text
v2_2_life_loop_1
```

默认评审槽：

```text
user://saves/v2_2_review_slot.json
```

V2.2 复用现有 `GameSaveService` 的原子写入流程，不建立第二套平行存档系统。

## 时间语义

`current_datetime` 表示下一个尚未结算的游戏小时起点。

例如：

```text
1900-03-12T07:00:00
```

表示 07:00—08:00 尚未执行。保存和恢复后不得重新结算前一个小时，也不得跳过当前小时。

## 顶层字段

存档至少包含：

- `schema_version`
- `scenario_id`
- `current_datetime`
- `time_speed`
- `paused`
- `random_seed`
- `random_state`
- `selected_person_id`
- `person_states`
- `person_locations`
- `current_activities`
- `future_schedules`
- `recent_completed_activities`
- `employment_contracts`
- `attendance_records`
- `pay_period_states`
- `processed_pay_period_ids`
- `households`
- `cash`
- `inventories`
- `rent_due_dates`
- `rent_arrears`
- `ledgers`
- `health`
- `fatigue`
- `stress`
- `employment_risk`
- `short_sleep_counters`
- `food_deficit_counters`
- `condition_state`
- `relationships`
- `union_participation`
- `schedule_state`
- `household_state`
- `processed_idempotency_keys`
- `processed_hour_keys`
- `notifications`
- `causal_events`
- `hours_processed`

领域服务保存的内部状态必须可以在无 UI 环境下恢复。

## 幂等键

周期结算不得依赖“是否已经显示通知”来判断是否处理。当前使用的键形态包括：

```text
hour:<ISO_DATETIME>
household:<HOUSEHOLD_ID>:consumption:<YYYY-MM-DD>
household:<HOUSEHOLD_ID>:rent:<DUE_DATETIME>
contract:<CONTRACT_ID>:wage:<YEAR>-W<WEEK>
contract:<CONTRACT_ID>:salary:<YYYY-MM>
person:<PERSON_ID>:union:<EVENT_ID>:<DATE>
person:<PERSON_ID>:contact:<TARGET_ID>:<DATETIME>
```

恢复后，已处理键必须继续存在；同一键再次出现时必须拒绝重复发薪、重复扣租、重复消费或重复关系结果。

## 原子保存

保存流程：

1. 生成完整快照。
2. 写入临时文件。
3. 校验必要字段和完整性摘要。
4. 写入成功后替换正式存档。
5. 保留可恢复的旧文件或备份。
6. 任一步骤失败时不得损坏此前可用存档。

## 载入事务

载入流程：

1. 读取文件。
2. 验证 JSON 与完整性摘要。
3. 验证 `schema_version` 和 `scenario_id`。
4. 验证人物、日程、合同、住户、账本和幂等引用。
5. 在内存中准备恢复。
6. 所有领域服务恢复成功后提交新状态。
7. 任一领域恢复失败时回滚到载入前状态。

损坏或不兼容存档不得：

- 静默加载；
- 删除旧文件；
- 修改当前运行状态；
- 只恢复部分领域；
- 让现金与账本失配。

## 数值规范化

Godot JSON 读回后，数字可能以浮点表示。配置和存档读取边界必须把以下字段规范为整数：

- 小时；
- 生丁金额；
- 库存人日；
- 健康、疲劳、压力；
- 熟悉度、信任、参与度；
- 风险；
- 序列号和计数器。

确定性比较应在规范化后进行，避免把 `1200` 与 `1200.0` 错判为语义差异。

## 确定性验收

相同种子和相同玩家安排下，以下两条路径必须得到一致核心状态：

```text
直接运行 30 日
```

与：

```text
运行 10 日
→ 保存
→ 载入
→ 再运行 20 日
```

至少比较：

- 权威时间；
- 人物状态；
- 日程；
- 出勤；
- 工资；
- 房租；
- 现金；
- 账本；
- 库存；
- 健康、疲劳、压力；
- 就业风险；
- 关系；
- 工会参与度；
- 已处理幂等键。

## 兼容策略

V2.2 当前不承诺加载旧原型或旧 P0-R1 存档。版本不兼容时必须显示明确错误，但不得删除旧存档。

未来修改结构时应：

- 新增 schema 版本；
- 明确是否可迁移；
- 在现有迁移框架中实现迁移；
- 不通过悄悄补默认字段伪装兼容。
