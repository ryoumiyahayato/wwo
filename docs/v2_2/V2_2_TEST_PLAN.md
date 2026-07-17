# V2.2 本地测试与实机验收计划

本文件用于在 Windows + Godot 4.6.3 Compatibility 环境中验收 V2.2。在线修改阶段不宣称这些步骤已经执行；只有本地真实运行返回成功并完成窗口检查后，才能把对应项目标记为通过。

## 环境

- 项目：`D:\wwo`
- Godot：`D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe`
- 版本：`4.6.3.stable.official.7d41c59c4`
- 主要窗口：1280×720
- 渲染器：Compatibility
- 场景：`res://scenes/v2_2/v2_2_life_loop_main.tscn`

## 一键入口

```powershell
cd D:\wwo
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\v2_2\run_local_acceptance.ps1
```

跳过可见窗口采集：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\v2_2\run_local_acceptance.ps1 `
  -SkipVisibleCapture `
  -SkipPerformanceCapture
```

自动步骤结束后打开人工评审窗口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\v2_2\run_local_acceptance.ps1 `
  -OpenManualReview
```

## 专项入口

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --headless --path 'D:\wwo' `
  --script 'res://tests/v2_2/v2_2_life_loop_smoke.gd'
```

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --headless --path 'D:\wwo' `
  --script 'res://tests/v2_2/v2_2_determinism_test.gd'
```

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --headless --path 'D:\wwo' `
  --script 'res://tests/v2_2/v2_2_save_load_test.gd'
```

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --headless --path 'D:\wwo' `
  --script 'res://tests/v2_2/v2_2_performance_guard_test.gd'
```

统一验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File D:\wwo\tools\run_validation.ps1
```

## 正常与评审启动

正常模式：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --path 'D:\wwo' `
  'res://scenes/v2_2/v2_2_life_loop_main.tscn'
```

评审与开发者模式：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --path 'D:\wwo' `
  'res://scenes/v2_2/v2_2_life_loop_main.tscn' `
  -- `
  --prototype-review `
  --developer-mode
```

## 自动测试范围

### 时间

- 暂停时不推进。
- 1×、2×、4×、8×正确。
- 累积多小时仍逐小时处理。
- 跨日、跨周、跨月只结算一次。
- 保存恢复后不重复当前小时。

### 日程

- 每人每小时只有一个主要活动。
- 跨午夜睡眠正确。
- 默认日程不覆盖玩家安排。
- 星期日不生成皮埃尔工作义务。
- 未来日程连续覆盖，不得被远期工会或联系事件掩盖中间空洞。
- 日程不在每帧重建。
- 长期运行后历史和未来日程保持有界。

### 就业与工资

- 完整周工资为 2400 生丁。
- 缺勤和请假扣款正确区分。
- 加班按实际完成小时支付。
- 同一工资周期只支付一次。
- 保存恢复不重复发薪。
- 无故缺勤增加就业风险，完整出勤降低风险。

### 住户与账本

- 购买扣款和库存同时成功或同时失败。
- 每日消费只执行一次。
- 房租正常支付或产生欠款。
- 同一房租周期只结算一次。
- 所有现金变化都有账本。
- 账本余额与住户现金一致。

### 状态与因果

- 工作、通勤、休息、睡眠和加班产生正确影响。
- 食品不足和短睡眠产生每日后果。
- 状态保持在 0—1000。
- 悬停说明来自真实因果事件。

### 关系与组织

- 联系让娜耗时 1 小时。
- 24 小时内不能重复联系。
- 熟悉度和信任更新。
- 工会活动只在正确时间执行。
- 工会参与度和活动历史更新。

### NPC

- 皮埃尔与阿尔贝在未被观察时继续生活。
- NPC 保持未来日程。
- 食品不足时优先采购。
- 疲劳过高时优先休息。
- 不覆盖玩家安排。
- 不在每帧规划。

### 存档与确定性

- 损坏和不兼容存档被拒绝。
- 载入失败不破坏当前状态。
- 直接 30 日与 10 日保存 + 20 日结果逐字段一致。
- 工资、房租、消费和账本无重复。

### 性能守卫

- 每小时结算不设置地图几何 Dirty Flag。
- 账本和通知不触发地图重建。
- 最大缩放仍为 96。
- 法国 96 个行政区保留。
- LOD、空间索引和批绘层继续有效。

## 人工窗口流程

1. 正常启动，确认标题为 V2.2 人物生活闭环原型。
2. 确认默认人物为皮埃尔，起点为 1900-03-12 05:00。
3. 测试暂停、1×、2×、4×、8×。
4. 观察睡眠、通勤、上午工作、午休、下午工作和回家。
5. 查看当前活动、下一活动和今日安排。
6. 推进至星期六 18:00，确认工资只到账一次。
7. 购买食品和生活用品，确认现金、库存和账本同步。
8. 制造现金不足，确认失败无半完成交易。
9. 安排加班，确认疲劳和压力变化。
10. 把疲劳设为 950，确认不能继续加班。
11. 安排请假并制造无故缺勤，比较工资和就业风险。
12. 联系让娜，确认关系变化和冷却。
13. 参加星期三工会活动，确认参与度变化。
14. 测试正常房租和房租欠款。
15. 切换阿尔贝，确认皮埃尔仍在后台运行。
16. 推进到 4 月 1 日，确认月薪和津贴只支付一次。
17. 保存、继续运行、载入，确认恢复且无重复结算。
18. 8×运行 30 日，确认不崩溃、日程无空洞、账本一致。
19. 暂停、1×、8×分别在 96 倍下拖动 20 秒。
20. 打开人物面板后拖动，快速缩放 100 次。
21. 检查 30 日后内存、拖动和标签恢复。

## 通过条件

只有以下全部满足才能判定 V2.2 通过：

- 所有专项入口退出码 0。
- 统一验证退出码 0。
- 30 日运行完成。
- 确定性逐字段一致。
- 账本一致。
- 无重复工资、房租和消费。
- 两个人物持续生活。
- 1280×720 无主要裁切。
- 地图性能没有明显回退。
- 人工操作中的按钮、悬停、Esc、保存和载入正常。

线上提交未执行这些步骤时，状态只能写为“代码待本地验收”，不能写为“V2.2 已通过”。
