# Rust 游戏候选

`wwo-map-lab` 是本地 `WWO-Mechanical-Preview.exe` 的源码。用 `cargo build --release --locked --bin wwo-map-lab` 构建。双击候选 EXE 或传入 `--play` 进入正式开局。EXE 旁需要原有的战略地图 `data/` 和本目录的两个 `tools/formal_*_bridge.gd`。通过 `WWO_R68_PROJECT` 指定带相同正式人物接口的 R68 项目，通过 `WWO_GODOT_EXE` 指定 Godot 4.6.3。

沿用现有地图数据目录。需要更新界面字形时，用 Pillow 执行 `python tools/build_hud.py <R68 项目> <候选数据目录>`。

人物依附正式世界的 `person:` ID。正式时钟到日界后，Rust 读取当天的食物需要结算与实际劳动记录。市场下单沿用正式账户与报价，R68 接单后才保存 Rust 人物的学习变化。人物状态随正式存档槽保存。带人物扩展的存档需要此候选，原版正式槽可直接载入。

当前健康和衰老参数属于开发假设。疾病与受伤事件来源、死亡后的正式人口与责任结算，以及学校教育还未接通。医疗、安全与休息资料留空。

候选由 Rust 按档位发出时间步进。R68 的正式游戏时钟仍持有唯一累计时间，负责执行步进和领域结算。每次步进绑定当前世界和分钟，读档后旧步进失效。
