# WAR ALGORITHM STEP-COST ATTRIBUTION AND BOUNDED ADVANCEMENT VALIDATION

## 登记状态

这是环境封存时的研究计划与计量口径记录。G0未通过，未冻结可执行反例，未进入G1。
以下是待完成的预登记要求，不是事后追加的通过标准，也不是已执行验收。

固定base：3515734e5dfdf4bfa04fc0047764f53c380389ed。
分支：experiment/war-step-cost-bound-v1-20261008。
开始：2026-10-08T04:55:44Z。总授权360有效分钟，最后至少90分钟保留给最终冻结验证。
本轮因来源恢复失败提前停止，未将剩余预算自动延长或开启下一周期。

## G0实际状态

- 已完整读取用户二十节实施授权与精确base的AGENTS.md
- 已按SHA验证精确Git commit及完整tree对象
- 已读取精确base的FINAL_ACCEPTANCE、REPRODUCE、ACCEPTANCE、continuous/README与cloud_validate.py
- 已实测Linux x86_64、Godot4.6.3.stable.official.7d41c59c4、Python3.12.14、Git2.52.0
- 精确运行源/数据恢复未完成，无法导入完整项目或建立当前环境基线
- code69fa36d、历史checkout f609b75、docs3515734的关系仅来自精确冻结报告，Git祖先/运行源指纹对应未重新验证
- 公开状态、重放hash和允许失败边界仅保存了历史契约；当前环境尚未重验
- G0：BLOCKED。G1/G2/G3：NOT_RUN。G4完整回归：NOT_RUN

## 单次有界来源获取

使用已有对象优先：当前工作区、shared与独立经济实验repo均未找到精确base；未从经济代码替代。
选择已连接GitHub只读原生commit/tree/blob/contents接口，所有请求固定精确SHA/ref。
会话开始约04:56:38Z，原截止05:11:38Z，最多1500次读取、并发8、无无限循环。
contents对大于1MB文件的空content改用原生Git blob接口，属于同一会话；每对象替代一次。
在约05:01:00Z，world_admin1.json的Git blob读取返回Transport closed。
错误返回时立即停止缺失对象获取，不重试该blob，不延长窗口，不换基线。
保留368个唯一SHA验证blob、389条路径、51,783,874字节；这不是完整可运行checkout。
无push、PR、review、comment、merge、rebase、tag或生产接入。

## 待完成的计量范围

| 范围 | 预期边界 | 本轮状态 |
| --- | --- | --- |
| 外层advance_bounded | 同一call_id开始至结果返回 | NOT_RUN |
| 内部_step/primitive | 同一call_id、primitive_id和phase | NOT_RUN |
| 子阶段、provider/event | 关联scope/unit与前后时刻 | NOT_RUN |
| 整理、cleanup、最后引用释放 | 单列且包含在完整推进区间 | NOT_RUN |
| admission、输入构建、转换 | 推进之外单列 | NOT_RUN |
| 查询、快照、比对、JSON导出 | 同样边界单列，不混入任一侧advance | NOT_RUN |
| 操作计数 | 读取/比较/写入/复制元素/释放/接触 | NOT_RUN |
| 存储 | 序列化bytes、Godot static、RSS/harness分开 | NOT_RUN |

最小关联字段计划为run_id/sample_id/call_id/primitive_id/phase/scope_id/unit_id、
game_time_from/game_time_target/committed_time/quota/used_work/status。
诊断缓冲须有界、保留drop数量与极值关联；JSON快照移出核心计时。
开启/关闭诊断须相同负载对照，不能声称零扰动。

## 待完成反例A与B进入条件

候选怀疑路径来自历史报告的apply:apply_units及native容器/ID快照。
当前完整源码未恢复，因此没有选定具体子阶段，也没有静态确认容量相互关系。
A计划只扩大representation轴，固定unit形状/历史/地形/外部事件/任务/30游戏秒。
2/16/64/400/1024阶梯只有同时满足scope、cell、provider及其他实际契约才能运行。
优先稀疏合法布局；每档预热1次、样本5次，单配置最多10分钟墙钟。
normal和quota1使用完全相同推进边界；旧/候选输入及计时相同。五样本不称稳定p95。
H1（规模相关复制/排序/复合回调/释放）与H2（宿主/分配抖动）可共存。

B仅当A/关联计量直接证明路线历史、context/claim或其他权威历史进入同一P1关键路径时开展。
没有直接关联则跳过；不能因历史JSON大便归因37ms峰值。本轮B：NOT_RUN，未触发。

## 待完成判定

A成立要求合法输入、同call关联、可核对操作数量、同边界样本与诊断扰动对照。
孤立峰值、违法容量、无操作数量、不同边界、环境中断都不足以判定，不能盲目优化。
G1成立才选一条主修正路线；不改是合法结局，但需要所选路径的正面排除证据。
G3正确性与成本分门，不转移未计量工作、不改战斗/移动/权限/知识/提交时间契约。
G4须运行原完整final门和新增测试，不加skip-unified、不更golden/tolerance/exception。
本轮不能采用A/B/C/D的研究结论，因为固定基线环境未建立；采用E环境阻塞。
