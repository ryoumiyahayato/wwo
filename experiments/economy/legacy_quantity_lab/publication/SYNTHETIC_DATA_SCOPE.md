# 人工实验数据范围

仓库内的经济余额、付款、库存与交易对手字段来自冻结的人工经济模拟配置，不是用户真实账户资产、真实企业账本或个人金融信息。

- network_round6/network_fixtures.py 用固定配方和参数生成 A、D、R#、B#、C# 企业与 T# sink。
- goal_cycle01/cycle_fixtures.py 按人工产能、天数、固定参考价计算整数初始资金。
- goal_cycle02/fixtures.py 只定义人工场景和受限对照。
- run_cycle02.py 仅读取本地冻结 manifest，再运行单一历史物资/支付 runtime；没有个人财务或真实银行连接器输入。
- final_metrics.csv 的 59 行来自已完成的 59 个冻结案例。全部 56 个账本 ID 均匹配 A/D/E/R#/B#/C#/external:T#，且全部属于 experiments_manifest_cycle02_final.json 的人工 balances ID 集合。
- 字段中的 real、actual、真实表示实际执行的模拟轨迹，与未执行预测/影子统计区分；不表示现实货币、现实库存或真实个人交易。

本次只发布已封存数据与恢复索引，没有重新运行经济、追加算法或改变实验结论。
