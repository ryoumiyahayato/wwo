# 源码移入稳定分支的状态记录（2026-10-25）

此目录是从本仓库未关闭PR [#11](https://github.com/ryoumiyahayato/wwo-economy/pull/11) 的原分支 `sandbox/algorithm-workbench-20261014`，固定Git提交 `b4795906250a6a765da5eb99b0ce7a87300374ac`，**原样复制86个文件**到已有固定默认 `sandbox/main`，避免仅保留在临时PR分支。原分支、PR和历史未改写。

## 功能与依赖真实边界

- 包含本地网页算法沙盒、具名人物/个人经济操作与可视化、原世界观察桥接、军事显示代码、场景样例、测试和启动器。军事代码是工作台已有交叉依赖，**不是由本经济库主导军事开发，也没有更改主WWO**。
- 依赖 `Node.js >=22.12`、`npm ci` 安装 `package-lock.json` 锁定的npm依赖（不存储 `node_modules`）、Python 3.12+，真实Formal适配器还需Godot 4.6.3以及原项目源码和地图资源。WebGL2用于可视化。这些不是源码提交就能消失的外部环境依赖。
- 原 `external/formal_economy.py` **锁定旧正式经济源** `ryoumiyahayato/wwo@b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`（`integration/formal-economy-20261014`）。它并未验证兼容2026-10-24经济第23代。原 `external/wwo_current.py` 及军事适配器也锁定特定旧源码；不得自动改成新主分支或强制跳过版本检查。
- 单独运行 **原创Demo/UI** 和接通真实外部Godot Formal经济是不同验收事项。缺少正确外部源码或引擎时，PRIVATE模式应保持未就绪，而不是回退成假数据成功。
- 经济默认源码 `project.godot`、`scripts/`、`merchant/` 属于第23代 Formal候选；其地图/资源/导入缓存及slot7存档仍只在[独立Release归档](https://github.com/ryoumiyahayato/wwo-economy/releases/tag/economy-gen23-closeout-20261024)。这一工作台不能替代这些资源。
- `experiments/individual-person-sandbox/` 另外保存了来自主WWO的旧个人钱包、具名人口测试和历史V2.3样本，**只供来源对照，不自动注入正式世界**。

此次操作只复制已有Git仓库Blob，并核对源码路径，没有启动Godot、npm、Python测试、GUI或GPU。不得记为Windows启动、旧个人适配器到Gen23升级通过；经济开发仍为STOP。原PR #11继续存在，另行判定其关闭/归档，当前操作不创建分支、不改默认分支、不触碰主WWO。
