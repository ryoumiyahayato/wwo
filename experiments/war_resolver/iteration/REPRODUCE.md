# 获取与复现（本轮实际平台 Linux）

唯一分支 `experiment/war-spatial-continuity-goal-v0`，Draft PR111，base冻结Task8
`c4731a33177660b83c6490f41fe42dcbe7cfa7bb`。最终代码commit为
`69fa36d6202b2b0d8e9332406ff57d269749fa0c`；最终文档commit在交付HEADS.json
与PR最终head中给出。M1/M2/M3可独立检出的检查点见FINAL_ACCEPTANCE。

已有仓库建议新建detached worktree。先检查本地git状态，使用不存在的新目录；
下面fetch不覆盖当前工作树，worktree只检出指定实验commit。把FINAL_DOCS_SHA替换为
PR最终文档HEAD或交付HEADS.json值。本轮没有在用户Windows正式工作区执行这些命令。

```sh
git fetch origin experiment/war-spatial-continuity-goal-v0
git worktree add --detach ../wwo-task9-review FINAL_DOCS_SHA
cd ../wwo-task9-review
```

本轮Godot真实路径`/usr/local/bin/godot`，版本必须为
`4.6.3.stable.official.7d41c59c4`；Python实际3.12.14。其他环境使用自己的真实引擎
路径，给两个Python driver的`--godot`参数；不复制本轮云端路径当本机事实。
首次CLI运行前必须做headless editor import，不能假定已有全局类缓存。
当前Linux的可复现导入步骤如下（同本轮driver的可写XDG策略）：

```sh
mkdir -p builds/task9-review-xdg/data builds/task9-review-xdg/config builds/task9-review-xdg/cache
XDG_DATA_HOME="$PWD/builds/task9-review-xdg/data" XDG_CONFIG_HOME="$PWD/builds/task9-review-xdg/config" XDG_CACHE_HOME="$PWD/builds/task9-review-xdg/cache" /usr/local/bin/godot --headless --editor --path . --quit
```

快速实际因果链：

```sh
python3 -B experiments/war_resolver/continuity/run_scenario.py --scenario main --seed 71 --seconds 1800 --quota 7 --output builds/task9-review-quick
```

持续24游戏小时压力输入：

```sh
python3 -B experiments/war_resolver/continuity/run_scenario.py --scenario long --seed 109 --seconds 86400 --quota 31 --output builds/task9-review-stress
```

每个`--output`必须是不存在的新目录，避免覆盖旧证据。case还支持no-cut、
slow-reports、no-supply、keep、cycles-disabled；quota0是同kernel同步reference。
每份输出含result.json、provenance.json、Godot原日志、中文timeline.txt；trace不是UI。
long输入的循环在24h结束，不能把seconds604800下的空闲快进当7日持续压力。

完整验收命令见`../continuous/README.md`，采用`cloud_validate.py --mode final`、
全部9新增script与版本化M0 baseline，不加`--skip-unified`。driver先导入，执行原
Tasks1–8、五保留回归、官方统一脚本的等价步骤及audit，检查原fatal matcher与退出码。
它不在Python中计算战争。已知economy golden必须逐字等于M0失败，其他失败阻塞。

本轮M0是实际Linux冻结Task8结果：`evidence/m0-linux/evidence.json`。其他平台或
不同Godot构建应先在冻结Task8的独立worktree建立该平台基线，不能强制采用本轮
Linuxhash或旧Windows数字；任何新失败不能自动变成known failure。原PowerShell
本轮NOT RUN，Windows执行/导出NOT RUN；Linux薄driver使用selector读pipe，不
宣称能直接替代Windows官方runner。Windows应按原仓库固定引擎指引导入及运行
同GDScript/官方PowerShell，实际路径由本机决定，本轮未验证。

交付小bundle保留从Task8起的所有本轮commit，需已有冻结base对象；配套binary
patch是base到final的净改动。它们仅含实验tracked内容，不包含完整工作区、缓存、
引擎二进制或未跟踪生产UID。HEADS.json记录确切base/code/docs与文件SHA256。
