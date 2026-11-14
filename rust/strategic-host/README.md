# WWO Rust Windows 游戏

`wwo-map-lab` 是 `WWO-Mechanical-Preview.exe` 的源码。用 `cargo build --release --locked --bin wwo-map-lab` 构建。双击 EXE 或传入 `--play` 开始游戏。EXE 旁需要战略地图的 `data/`。用 Pillow 执行 `python tools/build_hud.py <R68 项目> <游戏数据目录>` 可更新界面字形。

正式入口只打开 `data/maps/regional-2026-11-14/`。该地图保留领土旗纹、区域地表和海洋效果。用 `python tools/package_map_release.py <保留的 2026-11-14 区域地图数据目录> <游戏数据目录>` 发布现有地图。原目录可保留用于 R68 对照。正式入口会检查目录、旗纹资料和地图分片版本，版本不符或缺失时会报告错误。

法国、英国、德国、俄罗斯、清帝国和日本共用一份 1900 年历史资料和模拟规则。选择国家会选定玩家及其开局地点。50 个统计市场共用 Rust 正式时钟。Rust 执行跨日市场结算、统计货运、当地统计市场现货交易、个人库存和消费。巴黎的原开局岗位、劳动合同、工作和有限企业余额下的工资由 Rust 执行。

人物模块沿用正式人物 ID。工作和购买会更新经历。健康与衰老参数属于开发假设。疾病、受伤、医疗、休息、死亡、继承和学校教育尚未接入。地区商户、个人配送、完整企业经营、行政组织、科技、战略军事和 3D 训练仍待迁移。

原生游戏支持手动槽位、保存并退出及重启读档。每个档位保存在 `%LOCALAPPDATA%/WWO-Rust-Candidate/profiles/<配置名>/formal-world`，默认配置名为 `Default`，可用 `WWO_RUST_PROFILE` 指定。存档包含时间、人口、人物、市场、在途货物、账本、库存、合同和工资权益。

传入 `--r68` 可进入原有 R68 对照模式。该模式使用原有存档目录和 EXE 旁的两个 `tools/formal_*_bridge.gd`。通过 `WWO_R68_PROJECT` 和 `WWO_GODOT_EXE` 指定对照项目和 Godot 4.6.3。原生大厅只读写原生槽。维护工具 `wwo-formal-state` 可读取原版法国 v15 存档的部分领域。
