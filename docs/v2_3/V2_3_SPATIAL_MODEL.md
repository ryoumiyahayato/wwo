# V2.3 正式空间模型

## 状态边界

地点、人物位置和途中状态属于世界真实状态。人物是否知道地点、路线或他人位置属于个人认知，
两者分别由 `SpatialLocationService` 和 `KnowledgeService` 保存。普通 UI 只能查询当前观察人物
已知的地点与事实；评审/开发者真相视角会明确标记，并且只读真实状态。

## 地点

`data/v2_3/lille_locations.json` 定义 12 个稳定地点。每项包含稳定 ID、类型、区域、世界与本地
坐标、默认知情人物、开放时间、组织/工作场所/居民、服务、通信能力、地图可见规则、发现规则
和 Demo 平衡标记。地点不是场景节点；服务加载后建立 ID、类型和服务索引。

当前类型覆盖：

- `residence`
- `workplace`
- `market`
- `organization_hall`
- `government_office`
- `post_office`
- `public_square`
- `railway_station`
- `city_centre`
- `regional_centre`

## 人物位置

每个人物保存：

- `current_location_id`
- `location_state`
- `current_route_id`
- `current_edge_id`
- `route_segment_index`
- `route_started_datetime`
- `expected_arrival_datetime`
- `travel_destination_id`
- `last_arrival_datetime`

`location_state` 为 `at_location`、`waiting`、`in_transit` 或 `interrupted`。开始路段时人物离开
起点但不会进入终点；只有路段结算完成时才改变 `current_location_id`。途中人物不能同时用于
起点或终点的工作、购买、工会活动和面对面交流。

## 地点条件

- 工作：必须位于合同工作地点，迟到按实际到场小时交给 V2.2 出勤服务结算。
- 购买：必须位于营业中且提供对应购买服务的地点；远程购买返回明确失败。
- 工会活动：必须位于活动指定的组织会所。
- 面对面交流和约见：双方在同一地点、同一小时可用，且均不在途中。
- 写信：需要可用邮政服务或可投递地址；阅读只处理已送达消息。

这些条件在模拟服务中重验，UI 只提交命令，不能直接修改位置或绕过地点规则。

## 性能约束

地点与人物为纯数据，不创建每人物/每地点常驻可见节点。位置只在权威小时边界更新，不在
`_process()` 或 `_physics_process()` 中扫描。地图投影目录按配置版本缓存，本地点查询使用
独立均匀网格索引，位置变化只标记本地覆盖层为脏。
