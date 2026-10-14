# 临时配属连续性 v0

起点为本地文档HEAD 2fb4f70199b98de4ed9173888a8f63e8ca6b244f，包含运行HEAD 12025f391ea16b1ed040399cc1beff7fec516d91。319份实验运行文件与运行Git blob逐字节相同。未计算自定义哈希。UTC 2026-10-10 16:10:42开始，360分钟；无暂停。最后90分钟不开机制。

G0源码事实：gameplay.blocks_structure只保护split/merge；attach/revoke已经支持人物或目标叶。Structure事件先预检，再物化因果子树、更新effective索引；永久_nodes.parent不变。Roles与Decision查询当前Structure。Information送达时复验当前Role。Logistics按稳定unit_id收件并重建局部路径。expiry已有原request ID复验。旧ObserverReader目标目录固定，不能表达新权限。旧延迟revoke没有绑定配属版本。

|组合/语义|分类|本轮口径|
|---|---|---|
|单班同阵营同级上级临时配属/撤销/到期|EXISTING|原Task5事件；无第二内核|
|人物仍属原班，任务与个人动作继续|EXISTING|稳定unit/person/mission/action ID不搬迁|
|在途命令送达复验、单位shipment单次收件|EXISTING|不改队列和时延|
|单叶连续性显式准入、复杂依赖预检拒绝|NEW_SUPPORTED_CONTRACT|启用时只开放单班局部任务；旧未启用行为保留|
|revoke绑定原attachment ID|NEW_SUPPORTED_CONTRACT|陈旧撤销不能取消后来配属|
|固定人物文本attach/revoke与当前权限目录|NEW_SUPPORTED_CONTRACT|同一8192字节协议与128个ID表；READY才写入|
|已经合法开始任务继续，后续命令才替换|PROTOTYPE_POLICY|历史issuer/deadline/progress不重置|
|请求delay最少1秒，duration正数；公司输入300秒|EXISTING|Task8已有attach政策；revoke沿同一决策路径|
|无来源关系通知|UNSUPPORTED|可看当前权限元数据；不补造人物已收到全局通知|
|跨单位协调、任务依赖、资源独占迁移|UNSUPPORTED|准入前拒绝；在途普通命令/报告/单位shipment不是拒绝理由|
|带人物/目标coalesce、任意split/merge|UNSUPPORTED|原guard不删除|

受影响索引：Structure._children/_leaves仅旧新祖先路径；Logistics._paths/_node_reps仅changed leaf；表示归属沿原Authority。人物_units、unit.gameplay_personnel、个人_actions、goal_v1及timers、Knowledge/消息/已发报告、库存所有权、session/去重表不重建。已详细叶实际物化0；无关proxy继续保留。空间摘要更新若原内核读局部live表示，计入成本。

时间顺序沿原phase：expiry 0、structure 1、物流收件2、决策5、通信6、spatial 9、gameplay 10。关系事件本身不改变物理事实；比较T处处理前后，完整轨迹用相同因果时间边界。PENDING只给旧提交视图和接收确认。拒绝可保留请求身份/回执；不留下物理、关系或目标半修改。运行异常BLOCKED，不声称崩溃回滚。

验证：最小旧行为反例；S1入掩体中配属及失能；S2旧/新上级和人物固定会话、在途旧命令/报告/补给；S3到期/撤销/新配属/陈旧事件与6—12轮。使用71/109/347/2027回归seed；normal/quota0/1/7/31；受控24h；原Windows47节和保留算法/玩法/observer门。冻结后逐字节核对运行源码。人物证据与DEBUG_TRUTH分开。
