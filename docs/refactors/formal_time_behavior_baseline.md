# D01 正式时间所有权行为基线

状态：行为基线阶段。本文不授权修改正式时间生产实现。

基础提交：`4697ec70dfbaadbb7b61350ad9d7a6e4aeb95858`。

## 1. 当前时间所有权结构

当前正式产品同时保留三套相关时间表示：

1. 半球展示时钟：`FormalWorldApplication`继承链中的`sim_year`、`sim_month`、`sim_day`、`sim_hour`、`sim_minute`、`sim_paused`和`sim_speed`。
2. 正式模拟时钟：`FormalWorldSimulation.total_minutes`和`_minute_remainder`。
3. 正式经济时钟：`FormalWorldEconomyService.total_hour`。

当前应用计时入口`FormalWorldApplication._on_clock_timer_timeout()`把同一批分钟分别传给半球`_advance_clock()`和`formal_simulation.advance_minutes()`。本PR只记录这一行为，不修复或重新定义所有权。

## 2. A类：长期稳定契约

`tests/variable_state/formal_time_stable_contract_test.gd`覆盖以下长期契约：

- 正式模拟初始化为1900-01-01 00:00，累计分钟、分钟余数和经济小时均为0。
- `advance_minutes()`只累计一次输入分钟，并维持经济小时与分钟余数的整数换算关系。
- `V2DateTime`独立执行有效公历换算，覆盖月末、非闰年、闰年、年末和小时往返。
- 当前真实应用tick在暂停时不推进任何相关时间；速度1、2、4分别使正式模拟净推进15、30、60分钟。
- 经济日结算只在24小时边界发生一次，大跨度推进不得重复结算同一日。
- `save_to_user()`和`load_from_user()`在隔离`user://`中进行真实磁盘往返，并恢复完整正式经济持久化状态。
- 被生产验证拒绝的恢复状态不得部分提交，失败前后完整相关状态必须一致。

这些断言在后续单一事实源实施PR中原则上保持字节不变。

## 3. B类：当前已知缺陷特征

`tests/variable_state/formal_time_known_defects_test.gd`文件头明确标注：

```text
KNOWN DEFECT CHARACTERIZATION
NOT A LONG-TERM CORRECTNESS CONTRACT
```

该文件证明当前存在以下缺陷：

- 半球初始显示为1900-03-12 08:00，而正式模拟为1900-01-01 00:00，差值为70天8小时，即1688小时。
- 真实tick分别推进两套表示，原有1688小时错位继续存在。
- 半球固定31日历可从1900-02-28 23:45生成无效日期1900-02-29 00:00，而`V2DateTime`拒绝该日期。
- 当前`formal_load`界面读取路径恢复正式模拟，但不恢复半球`sim_*`。
- 当前产品场景`launch_mode == "load"`继续游戏路径恢复正式模拟，但半球`sim_*`仍保持场景初始值。
- 当前`restore_persistent_state()`接受`total_minutes`、`minute_remainder`与`economy.total_hour`彼此不一致的状态。

后续实施PR修复上述问题时，必须明确把这些缺陷特征断言替换为一致性断言，不能把当前错误保留为长期契约。

## 4. user://隔离与清理

生产常量`FormalWorldSimulation.SAVE_PATH`保持不变。

永久CI把Windows runner的`APPDATA`重定向到`${RUNNER_TEMP}/formal-time-user-data`，使Godot的`user://formal_world_1900.json`位于一次性runner目录。两个测试仍在进程内执行以下保护：

1. 读取并备份测试启动前可能存在的正式存档字节；
2. 清理本测试产生的固定路径文件；
3. 使用生产`save_to_user()`和`load_from_user()`完成真实磁盘往返；
4. 测试结束后恢复原文件，或在原文件不存在时保持路径为空；
5. CI最后递归确认隔离APPDATA中不存在遗留`formal_world_1900.json`。

本PR不提交正式世界产品存档JSON，也不修改`SAVE_PATH`、schema或任何fallback。

## 5. 永久只读CI

`.github/workflows/formal-time-behavior-baseline.yml`：

- 仅响应目标分支为`agent/formal-world-economy-integration`的pull request及手动触发；
- `permissions: contents: read`；
- 使用Godot 4.6.3；
- 显式确认两个测试文件和辅助文件存在；
- 分别执行稳定契约和已知缺陷测试；
- 要求总结行存在、检查数大于0且失败数为0；
- 重新运行变量审计生成链，并用`git diff --exit-code`证明四份既有审计文档没有漂移；
- 执行`tools/run_validation.ps1`完整既有验证；
- 不使用push触发、不自动提交、不上传或修改仓库内容。

## 6. 严格边界

本PR只允许新增：

- 两个时间测试文件；
- 一个无状态测试辅助文件；
- 本说明文档；
- 一个永久只读workflow。

本PR没有修改`scripts/`、`scenes/`、`data/`、`resources/`、`project.godot`、现有fixture、现有测试、存档schema或任何生产时间字段。

D01仍按以下顺序推进：

```text
审计决定
→ 行为基线
→ 单一事实源实施
→ 原稳定契约不变通过
→ 明确替换缺陷特征断言
→ squash merge
```

本PR保持Draft，完成验证后停止，不进入正式时间生产重构。
