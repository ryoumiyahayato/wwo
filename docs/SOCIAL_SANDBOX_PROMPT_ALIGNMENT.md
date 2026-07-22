# 正式开发指令与仓库证据对应

本文件只负责把《1900》社会沙盒核心重构正式开发指令映射到当前仓库。详细结论见 `SOCIAL_SANDBOX_CONFORMANCE_AUDIT_2026-07-20.md`，操作步骤见 `SOCIAL_SANDBOX_TEST_PROTOCOL.md`。

| 指令核心要求 | 当前正式路径 | 状态 |
|---|---|---|
| 现实状态产生维持压力、威胁、机会和抱负 | `V23SocialSandboxService._derive_situations()`、V2职位扩展 | 当前范围满足 |
| 人物形成目标但不直接改世界 | `situations`、`goals`、稳定 `goal_id` | 满足 |
| 玩家与NPC使用同一行动入口 | `V23SocialSandboxServiceV2.submit_intent()` | 满足 |
| 意图成为占用时间、地点、人员和资源的任务 | `_reserve_schedule()`、正式日程和旅行服务 | 满足当前范围 |
| 到期重新读取现实条件 | `_prepare_proposal()` | 部分满足 |
| 同时行动统一准备和解决冲突 | `_resolve_batch()`、`_proposal_conflict_keys()` | 部分满足 |
| 状态与重要事件一致提交 | 逐行动权威快照、回滚、`event_ledger` | 满足逐行动原子性 |
| 客观事实、消息和人物认知分离 | `event_ledger`、`KnowledgeService`、`visible_events_for()` | 基础满足 |
| 事实继续形成反应 | `_queue_reaction()`、脏人物重新评估 | 部分满足，主要为延迟反应 |
| 工厂工作组不是固定关卡 | V2过滤固定代表信号；通用职位方法 | 满足当前数据范围 |
| 玩家零输入30日世界仍变化 | 正式社会沙盒与性能测试 | 满足 |
| 保存和恢复完整因果链 | `V23SaveService`、社会沙盒持久状态 | 满足当前Schema |
| 所有现实成立方法均可尝试 | 当前约32种数据驱动方法 | 未完全满足 |
| 完整多阶段即时反应与多原因因果网络 | 当前单小时批次、单一`cause_event_id` | 未满足 |
| 人工检查只判断可玩性而非证明技术路径 | `SOCIAL_SANDBOX_TEST_PROTOCOL.md` | 已明确 |
