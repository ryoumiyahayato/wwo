**2026-10-23｜PASS：有限巴黎自主生活闭环。** R57代数17 CANDIDATE；R56保留，未promote。施工AI完成170项局部检查及源码／实际EXE自动GUI；不是人类验收。

**自主劳动PASS｜工资收入PASS｜购买PASS｜交付PASS｜实际消费PASS｜需要反馈PASS。**

| 验收问题 | 实际结果 |
|---|---|
| 1. 独立居民 | 普通Opening增加具名居民person:formal_generated_country_fra_0002。其他人口仍是统计，不冒充逐人AI。代数16原有玩家0001保留。 |
| 2. 身份与来源 | 独立claim、巴黎所在地、个人账户、food需要和正式岗位／面包消息均有Opening记录。NPC初始现金0；玩家2500、工坊1200、粮食60、面包12、岗位1不变。雇佣由原申请形成，不预授企业管理权。 |
| 3. 无玩家操作A | 普通油画菜单新世界推进7日（10080分钟），玩家请求0。1440分钟自主应聘、登记次期工作；2880分钟完成首轮；4320分钟收工资6，购买2面包、消费1。最终工作12小时，工资责任36、已付30、未到期6。 |
| 4. 合法信息 | 只使用本人已收到的岗位／供货信息与当期报价，不知道未公开粮食报价。延迟供货通知测试中，有工资也不能提前发现卖方。未移植研究HouseholdTiming、household_choice或NPC经营策略。 |
| 5. 真实生活后果 | 5单共取得6面包、支出12；StockLots消费5、NPC持有1，来源可追溯至原Opening货批。food累计需要7、满足5、未满足2；当前日满足1/1，前两日缺食未被抹去。现场交付，无虚构运输。 |
| 6. 受限行为 | 无销售工时、资金不足、无货、失效报价、在途货物均不能绕过原规则。欠薪测试保留债权，并按原政策离岗。消费不重复扣货或记满足；不能控制NPC或冒用他人现金。 |
| 7. 玩家参与B | 与A的Opening和初始状态相同，用户目录独立。玩家先占唯一岗位，NPC仍自主申请，7次收到NO_VACANCY；无收入、购买或消费，food未满足7。玩家工作4小时、工资12、购买消费1面包，现金2510。 |
| 8. 守恒与权威 | A：NPC现金18、工坊1182、玩家2500，合计3700；耗粮6、生产面包12，工坊粮食54、面包18。每轮2小时按原规则分配1小时销售、1小时生产。复用同一WorldState、GameClock、Ledger、StockLots与v15持久化；日结驱动，无逐帧AI。 |
| 9. 恢复与旧路径 | A/B各5处正式槽4恢复一致，后续推进无重复工作、生产、支付或消费。真实离开巴黎的隔离旅途测试仍结算；旧代数16存档不补生NPC。原玩家生活闭环、肥皂1的预占／在途／交付、货款8＋运费1、撤权拒绝及恢复均通过。人物、两张地图同源，只公开已知当地岗位空额。 |
| 10. 性能及版本 | 同设备接电、720p、政治250mpp、160标记／792批次／每次平移26次布局。提示开P95 85.488→87.382ms，最大124.482→113.621ms，>100ms均4帧；提示关82.143→80.307ms。未见明显新增退化，P1保留。统一构建一次，EXE 1,759,497,136 B，增3,632 B。 |

[A组记录](D:/programs/WWO/wwo/local-artifacts/r57-autonomous-residents-2026-10-23/candidate-idle/economic-action.json) · [B组记录](D:/programs/WWO/wwo/local-artifacts/r57-autonomous-residents-2026-10-23/candidate-participating/economic-action.json) · [玩家回归](D:/programs/WWO/wwo/local-artifacts/r57-autonomous-residents-2026-10-23/candidate-player-regression/economic-action.json) · [肥皂回归](D:/programs/WWO/wwo/local-artifacts/r57-autonomous-residents-2026-10-23/candidate-soap-regression/economic-action.json) · [性能](D:/programs/WWO/wwo/local-artifacts/r57-autonomous-residents-2026-10-23/candidate-performance/performance.json)。国家／地点拾取、百科、帮助、Benelux水文、WORLD退出通过；湖区、色界和ARCHIVES未重测，资源及相关实现未改。实际EXE日志无脚本错误或警告；源码GUI出现一条既有锚点警告。菜单准备超时未复现。未重建地貌，已停止。

本轮诊断18份、2,083,937 B，无截图；4个隔离测试用户目录共81份、26,362,444 B，含正式存档和引擎日志，保留。构建暂存为空，实际自动清退0 B。此前自动审批拒删的83份24,523,633 B及82份23,628,718 B原样保留，未重试或绕过。
