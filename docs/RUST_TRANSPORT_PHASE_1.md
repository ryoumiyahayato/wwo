# Rust 交通基础第一阶段

`wwo_map_lab::transport` 提供按需查询和单线路通行状态。正式宿主已经有 `WorldSources`。调用方用它构建一次索引，发起查询时传入正式 `place:*` ID、允许的运输方式和统一载荷单位。

```rust
use wwo_map_lab::{
    formal_bootstrap::WorldBootstrap,
    transport::{map_data::load_prototype_map_network, ModeSet, TransportMode, TransportRequest},
};

let world = WorldBootstrap::load()?;
let mut transport = load_prototype_map_network(world.sources(), 64)?;
let route = transport.route(&TransportRequest {
    from: "place:paris".into(),
    to: "place:le_havre".into(),
    allowed_modes: ModeSet::only(TransportMode::Rail),
    capacity_units: 1,
});
```

## 路网和参数来源

- 道路、铁路和海运沿用 `WorldSources::routes()` 的原线路 ID。城市和港口沿用 `WorldSources::places()` 的 ID 与坐标。国境通行规则、运营班次和站点级位置待核实后接入。
- `data/world_map` 的全部五个输入标有 `prototype_only`。适配器明确启用这组资料，每一段查询结果保留该标记。道路和铁路距离取端点大圆距离，海运取显示用折线的各段距离。几何精度限于这些输入。源线路按双向通行建模，方向限制由后续资料提供。
- 港口使用 `ports.json` 的 `city_id` 建立独立双向换装边。海运只能通过港口和海运节点，港口以换装边接入所属城市。陆路在城市节点可换乘道路和铁路，城市内的车站位置与换乘用时待列入更细的网络。
- `transport_compact.json` 的铁路是实体级里程估计。海运是 `sea:*` 跨统计单位的走廊，有天数、容量指数和置信度。`formal_macro.rs` 用走廊关联统计市场，并转换容量指数用于聚合货运。地图 `shipping_*` 是港口间样例折线。两类 ID、端点和规模各自保留。巴黎和鲁昂沿用既有市场口径。

下表全部为开发假设，来自 `transport/map_data.rs`。费用为每段的抽象费用。运力为一次查询可占用的共享载荷。风险点可相加。实际运价、班次、吨位、客座换算和事故概率尚无本阶段数据。

| 方式 | 速度（km/h） | 固定换装（分钟） | 基础费用 + 每公里费用 | 名义载荷 | 风险点 |
| --- | ---: | ---: | --- | ---: | ---: |
| 道路 | 8 | 0 | 1 + 0.6/km | 16 | 3 |
| 铁路 | 40 | 0 | 2 + 0.4/km | 120 | 2 |
| 海运 | 20 | 0 | 3 + 0.2/km | 300 | 5 |
| 港口换装 | 6 | 45 | 4 + 0.3/km | 80 | 1 |

## 查询与世界时间

`route` 按总分钟最短择路，返回有方向的分段、费用、风险和最小剩余载荷。它区分未知端点、无效载荷、不可达、中断和运力不足。`set_availability` 更新同一分段的开闭与剩余运力，双向共用。客货读同一容量。查询只提供当前快照，未来由正式事件统一预留和释放运力。

邻接表在建图时生成。缓存上限由调用方传入，满时逐出最早插入项。更新线路时只丢弃依赖该段的查询。依赖包含已选线路和可能改善或改变结果的相关阻断边，连通性失败结果可跨运力变更复用。`Route::arrival_clock` 在传入的 `GameClock` 副本上推进预计行程分钟。没有渲染帧入口和后台线程。

## 原创模型和接入

`steam_1900.glb` 有 10 型、每型两档，使用几何和纯色材质。同目录的 `build_models.py` 可用 Python 标准库重新生成。模型尺寸为渲染设计值。 [GLB](../assets/civilian/transport/steam_1900/steam_1900.glb)

模型几何和材质由本项目生成。造型参考美国国会图书馆的同期影像。 [机车](https://www.loc.gov/item/2017658614/) [客轮](https://www.loc.gov/item/97505963/) [货船](https://www.loc.gov/item/2016807156/) [明轮船](https://www.loc.gov/item/2006683675/)

| 模型 | 近景三角面 | 远景三角面 |
| --- | ---: | ---: |
| 蒸汽机车 | 2,088 | 360 |
| 煤水车 | 1,068 | 184 |
| 客车厢 | 1,696 | 312 |
| 棚车 | 960 | 168 |
| 直轨 | 288 | 144 |
| 站房 | 568 | 232 |
| 带棚站台 | 304 | 136 |
| 双烟囱客轮 | 988 | 292 |
| 蒸汽货轮 | 496 | 264 |
| 近岸明轮船 | 804 | 332 |

GLB 大小 647,568 字节。使用米制，`+Y` 向上，`+Z` 朝车头、船首或轨道前方。直轨长 12 米，轨距 1.435 米，轨顶在 `Y=0.24 m`。车辆原点在轮轨接触面，固定设施原点在地面，船舶原点在水线。

未来地图接入时先做视野裁剪，再以最长投影边调用 `ModelLod::for_screen_extent`。小于 12 px 走现有地图符号或线路，12 至小于 48 px 用远景，48 px 起用近景。`models::decode(model, lod)` 复用宿主已有 `gltf` 依赖，只生成请求网格的顶点和索引。地图可用 `(model, lod)` 共用可见实例的 GPU 缓冲，并释放离开视野后闲置的网格。本阶段提供 CPU 解码，Windows 游戏渲染 `NOT_RUN`。

## 后续接入点

| 领域 | 接入位置和权威 |
| --- | --- |
| Person | 从正式人物地点发起预计路线和费用查询。玩家确认并取得运力后开始活动。在 `formal_step` 的现有 `TravelArrivals` 边界落地，使用 `GameClock`。Person 持有人物活动和到达地点。详细活动先覆盖玩家。 |
| Population | 在 `formal_step` 的居住或迁移结算处用路线筛选群体流量。Population 持有数量、结构和迁移统计。群体按批次占用运力。 |
| Economy | 保留 `MacroEconomy` 的统计在途记录及恢复逻辑。实物订单确定货权和货批后，先在正式出发事件提交共享运力与发货，保留唯一在途保管状态。到达以原货批身份和交割 ID 入库一次。中断继续保留保管归属。Ledger 和 Economy 持有现金、价格、订单和库存。 |
| 交通和存档 | 后续将已确认的预约按实际线路区间存入正式域状态。出发前核对客货统一载荷，事件结束后释放。已有时钟边界派发和到达，正式存档保存有状态的事件，索引和缓存可以重建。 |
| 地图 | 地图仍提供地点和线路。路由输出可用于选中路线，车辆模型消费正式事件产生的位置和方向。地图不可见时保留事件推进。 |

城市交通可以增加城市内节点和服务连接，航空可以在正式年份与设施资料具备后扩展方式和端点。此阶段运行的服务只包含道路、铁路、海运和港口换装。

## 局部验证

使用 `CARGO_BUILD_JOBS=2`，在 `rust/strategic-host` 执行 `cargo test --locked --offline --lib transport:: -- --test-threads=1`，9 项通过。覆盖法国实际目录、路由及缓存、GLB 解码。

本机 Windows Debug 测试进程重跑通过，进程 CPU 时间约 109 ms，采样观察到峰值工作集约 14.4 MiB。读数包含测试框架、正式数据引导和模型解码。游戏运行中的交通增量内存、帧耗时和显存 `NOT_RUN`。Windows 游戏实测、完整地图巡视和全仓回归 `NOT_RUN`。
