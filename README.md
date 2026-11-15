# WWO

`main` 是唯一正式开发线。当前 Windows 游戏由 WWO 的 [Rust 宿主](rust/strategic-host/README.md) 运行。入口是 [`rust/strategic-host/src/main.rs`](rust/strategic-host/src/main.rs)，原生会话和持久化在同一宿主内。winit 提供窗口和输入事件，wgpu 提供图形接口。人物规则复用 [character-core](rust/character-core/README.md)。

当前版本可进入 1900 年正式世界，操作地理、政治、经济和军事地图，推进同一套世界时钟，交易和结算工资，并保存及恢复原生档案。[运行核实与模块归属](docs/RUST_HOST_RUNTIME_REVIEW.md) 记录了隔离 Windows 实跑的范围、第三方库、原 Godot/R68 对照入口和待迁移功能。

Godot 4.6.3 工程及 R68 继续用于旧版对照、资产复用和迁移验证。旧工程入口见 [project.godot](project.godot)。经济和军事沙盒各自保留测试入口，接入正式游戏时共用 Rust 世界、人物和时间。[全球地貌验收规程](rust/strategic-host/README.md#全球地图验收) 适用于每次全球地图验收。

## 构建与恢复

Windows x64 使用 Rust MSVC 工具链、MSVC C++ Build Tools 和 Windows SDK。在仓库根目录运行：

```powershell
cargo build --release --locked --manifest-path rust/strategic-host/Cargo.toml --bin wwo-map-lab
```

运行时需同阶段的 `data/`，也可传 `--play --data <目录>`。私有 [Rust Windows 阶段资源包](https://github.com/ryoumiyahayato/wwo/releases/tag/rust-native-windows-20261115) 保存已经实跑的 EXE、共同运行数据和独立的压缩 Z7 资源。按附件说明恢复到空目录。Z7 资源为候选，使用随包 `Play-WWO-WorldCRS84Quad-Compact.cmd`。历史 Godot 资源另见 [R57 归档与恢复清单](docs/archive/main-wwo-r57-g21-20261024/inventory.json) 及 [恢复工具](tools/archive/restore_main_resources.py)。

## 阶段提交

1. 每完成一个可验证阶段，先本地运行相关检查，再提交源码、配置、测试和报告。使用短期分支和 PR，按 [Main validation](.github/workflows/main-validation.yml) 完成检查后合入 `main`。
2. 大型运行资源、必要原件及发布包使用私有附件。记录版本、来源、对应提交和存储服务提供的完整性信息。玩家存档、凭据、私人资料及可重建缓存不得进入 Git 或附件。
3. 从远端重新读取 `main`、代码、构建文件、报告和对应附件。在独立目录回下载和验证本阶段所需的恢复范围。报告提交 ID、附件、实际恢复结果和仅在本机的内容。云端同步和已要求的恢复检查完成后才标记完整交付。

代码合并、资源归档和正式候选提升分别记录。长期开发规则见 [AGENTS.md](AGENTS.md)。
