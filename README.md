# WWO

`main` 是唯一正式开发线。当前 Windows 游戏由 WWO 的 [Rust 宿主](rust/strategic-host/README.md) 运行。入口是 [`rust/strategic-host/src/main.rs`](rust/strategic-host/src/main.rs)，原生会话和持久化在同一宿主内。winit 提供窗口和输入事件，wgpu 提供图形接口。人物规则复用 [character-core](rust/character-core/README.md)。

当前 Windows 预览可进入 1900 年正式世界，切换地理、政治、经济和军事地图，推进世界时钟，交易和结算工资，并保存及恢复原生档案。[Rust 宿主运行核实](docs/RUST_HOST_RUNTIME_REVIEW.md) 记录了实跑的 EXE、测试范围、模块归属和旧版对照入口。

Godot 4.6.3 工程、场景和旧回归保存在 [R68 源码归档](https://github.com/ryoumiyahayato/wwo/tree/archive/godot-r68-source-20261120)。正式主线使用 Rust。R68 对照、旧界面素材和地理编码工具从归档恢复。

## 经济和军事

- 经济以补齐和整合为主。Rust 已有统计市场、个人库存、工资责任和已完班次成本输入。沿用经济沙盒中已验证的企业生产与交付链，接入现有账本、货批和时钟。企业生产批次成本仍待分配。
- 军事优先接入 Rust 装甲陆战。正式游戏可从法国军事地图的 50／25 公里方格进入同一场交战。真实 QPK 粗高程、通用车辆、战果和原生存档的当前范围见 [军事地图方格与装甲战场](rust/strategic-host/README.md#军事地图方格与装甲战场)。

## 构建与恢复

Windows x64 使用 Rust MSVC 工具链、MSVC C++ Build Tools 和 Windows SDK。正式构建由 [Main validation](.github/workflows/main-validation.yml) 执行。本机在固定工作树运行 `./rust/strategic-host/tools/wwo-cargo.ps1 check --bin wwo-map-lab`，也可调用 `build`、`test` 或 `run`。入口复用同一个 Cargo target，串行构建。超限时回收对应配置的工程产物，保留共享依赖。dev/test 关闭调试信息、PDB 和增量编译。需要调试器时加 `-DebugSymbols`，使用独立的 `dev-debug` 配置目录。

需要重建 Windows 正式二进制时，在仓库根目录运行以下命令。

```powershell
cargo build --release --locked --manifest-path rust/strategic-host/Cargo.toml --bin wwo-map-lab --bin wwo-formal-state
```

将阶段资源恢复到新构建 EXE 旁的 `data/`。在仓库根目录用以下命令打包人口数据，指定 EXE 旁的 `data` 或游戏 `--data` 指定的运行目录。

```powershell
./rust/strategic-host/tools/package_population.ps1 -DataDirectory <运行目录>
```

运行 `wwo-map-lab.exe --play`。状态工具默认也读取 EXE 旁的 `data/`。地图另有 `--data` 目录时，可用 `WWO_DATA_DIR` 单独指定开局人口和 F7 资料所在目录。共享本地构建命令默认使用固定工作树的 `data/`。人口清单 `data/historical_population_1900/runtime-manifest.json` 声明新开局版本、市场校准版本和各版所需文件。生成新版人口资料时同步更新清单，旧存档按保存的版本读取对应文件。版本化开局数据和 F7 参考表均随人口包离线使用。

私有 [Rust Windows 阶段资源包](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115) 保存实跑的预览 EXE、运行数据、压缩地貌和训练高程。Release 标签固定阶段源码版本。附件说明登记来源、恢复目录及回读状态。

- 基础预览解开运行 TAR 到空目录，启动 `WWO-Country-Records.exe`。
- Z7 候选再解开 Z0–Z6 TAR 到同一目录，将 `7.qpk` 放入 `data/worldcrs84quad-15s-v2/`，运行随包 `Play-WWO-WorldCRS84Quad-Compact.cmd`。地图画面验收使用 [全球地貌验收规程](rust/strategic-host/README.md#全球地图验收)。
- 正式地图按 [水文资源恢复步骤](rust/strategic-host/README.md#正式水文资源) 装入同一 `data/`。
- 历史 Godot 资源按 [R57 归档与恢复清单](docs/archive/main-wwo-r57-g21-20261024/inventory.json) 及 [恢复工具](tools/archive/restore_main_resources.py) 处理。

## 恢复 R68 源码

在现有仓库旁恢复归档工作树。

```powershell
git fetch origin tag archive/godot-r68-source-20261120
git worktree add --detach ../wwo-r68-candidate archive/godot-r68-source-20261120
```

归档含旧场景、GDScript、着色器、候选导出入口及历史回归。旧 `.display` 编码用 `tools/map/build_geographic_foundation.py --compile-display --godot <Godot> --r68-project <归档目录>`。Rust 的 R68 对照与界面字形重建见 [宿主文档](rust/strategic-host/README.md#r68-对照)。

## 阶段提交

1. 每完成一个可验证阶段，先本地运行相关检查，在同一轮提交并推送源码、配置、测试和报告。施工中的改动留在开发分支。使用短期分支和 PR，按 [Main validation](.github/workflows/main-validation.yml) 完成检查后合入 `main`。
2. 大型运行资源、必要原件及发布包使用私有附件。记录版本、来源、对应提交和存储服务提供的完整性信息。玩家存档、凭据、私人资料及可重建缓存不得进入 Git 或附件。
3. 普通 PR 合并后核对远端 `main` 和必需 CI。正式发布、运行资源打包或存档格式改变、重建环境时，使用固定验证目录从云端冷恢复。优先使用能访问的既有 CI 构建和归档附件。报告提交 ID、资源状态、实际恢复结果和仅在本机的内容。

代码合并、资源归档和正式候选提升分别记录。长期开发规则见 [AGENTS.md](AGENTS.md)。
