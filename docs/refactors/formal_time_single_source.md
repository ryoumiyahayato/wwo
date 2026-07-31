# D01 正式时间唯一事实源

## 实施基线

- Base 分支：`agent/formal-world-economy-integration`
- 固定 Base SHA：`54abacf268e90d86e6fff3a2dc29f3162fd29089`
- 实施分支：`agent/formal-time-single-source`
- 隔离 worktree 初始状态：干净
- 稳定契约文件初始 Git blob：`871d312cd0d8fa4370aa201ad7ac5a863684ab4d`
- 正式初始时间：`1900-01-01 00:00`

## 改造前所有权图

|状态|所有者|写入者|读取者|结论|
|---|---|---|---|---|
|`FormalWorldSimulation.total_minutes`|正式模拟|初始化、分钟推进、恢复|日期、存档、测试|权威候选|
|`FormalWorldSimulation._minute_remainder`|正式模拟|初始化、分钟推进、恢复|日期、存档、测试|重复可写派生值|
|`FormalWorldEconomyService.total_hour`|经济层|配置、逐小时推进、恢复|日结、摘要、存档|第二套可写正式时间|
|`sim_year/month/day/hour/minute`|半球运行时|场景默认值、`_advance_clock()`、测试写入|HUD、半球、测试|第二套独立产品显示时间|

正式应用每个 tick 先调用半球 `_advance_clock()`，再调用正式模拟 `advance_minutes()`；保存和读取只恢复正式模拟，形成双写和恢复后错位。

## 改造后所有权图

|状态|性质|唯一写入者|读取者|
|---|---|---|---|
|`FormalWorldSimulation.total_minutes`|唯一可写正式时间|`initialize()`、`advance_minutes()`、验证成功后的 `restore_persistent_state()`|公历、经济、HUD、半球、保存、测试|
|`FormalWorldSimulation._minute_remainder`|只读 getter|无独立写入者；由 `total_minutes % 60` 即时派生|存档校验、稳定契约|
|`FormalWorldEconomyService.total_hour`|只读 getter|无独立写入者；通过绑定的正式小时源派生|日结、摘要、持久化校验|
|正式半球与 HUD 日期|即时显示结果|无写入者；调用 `formal_simulation.date_time()`|正式界面|

正式 tick 的唯一产品入口是半球运行时的 `_on_clock_timer_timeout()`，该入口只调用正式应用覆盖的 `_advance_simulation_minutes()`，最终只写 `FormalWorldSimulation.total_minutes`。地图、HUD 和经济层均不再额外推进时间。

## 删除和隔离

从正式产品继承链中删除：

- `sim_year`
- `sim_month`
- `sim_day`
- `sim_hour`
- `sim_minute`
- 固定 31 天月份的 `_advance_clock()`

UI 样机场景改为加载 `holographic_workspace_spike_runtime.gd`。该脚本只保留隔离样机本地累计分钟，不被正式产品场景加载，也不能写正式模拟时间。

## 公历和经济结算

日期统一由 `V2DateTime` 从权威累计小时派生。`V2DateTime` 使用完整格里高利规则，1900 年不是闰年，1900 年 2 月为 28 天。

正式模拟在写入本批分钟之前记录起始权威小时，在写入后计算结束权威小时，并把两者传给 `settle_hour_range(previous_total_hour, current_total_hour)`。经济服务只消费 `(previous_total_hour, current_total_hour]` 内跨越的完整小时，并验证结束小时等于当前权威小时；它不保存、递增或恢复第二个小时计数。因此 23/24、47/48 小时及大跨度跨日推进均只结算一次。

## 保存和读取

存档版本保持 `formal_world_simulation_v2`，没有修改版本号。`total_minutes` 是权威表示；`minute_remainder` 和经济状态中的 `total_hour` 是严格校验字段。V2 存档缺字段或任意三者矛盾时，恢复在提交前拒绝。经济状态恢复失败时，正式分钟和完整经济状态回滚到调用前快照。

`formal_world_simulation_v1` 继续读取：已有一致时间字段原样恢复；旧小时边界存档缺少分钟字段时，可从已保存经济小时推导。不会通过双写或读取后补丁同步兼容旧字段。

## 稳定契约保护

`tests/variable_state/formal_time_stable_contract_test.gd` 必须保持 Git blob `871d312cd0d8fa4370aa201ad7ac5a863684ab4d`，本轮不修改其字节。

## 范围边界

本轮不处理 V2.3 其他依赖、其他变量组、正式世界性能规则、十年平衡规则、Windows 发布、PR #19 收尾或 `master` 合并。
