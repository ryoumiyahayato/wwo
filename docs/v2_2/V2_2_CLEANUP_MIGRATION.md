# V2.2 世界地图与旧原型清理迁移

本轮将已经通过实机评审的世界地图从旧 `prototype_v2` 路径迁入正式 `world_map` 模块，并删除不合格旧原型的可执行入口。

## 保留并迁移

以下内容属于当前 V2.2 正式运行依赖，迁入新路径后继续保留：

- Robinson 世界地图与国家轮廓；
- 法国 96 个省级行政区与九个宏观地区；
- LOD、空间索引、批绘图层、标签缓存和 96 倍缩放；
- 当前世界地图数据、交通数据、机构与组织节点；
- V2.2 四角界面所需的地图基础控制器。

新路径：

```text
scripts/world_map/
data/world_map/
```

## 已删除

以下内容不再作为历史回归或备用入口保留：

- 旧 P0-R1 主菜单；
- 旧人物创建界面；
- 旧网格战略地图；
- 旧静态 V2 独立原型场景；
- 旧 `scripts/ui` 表现层；
- 旧 `scripts/prototype_v2`、`data/prototype_v2`、`tests/prototype_v2` 和 `tools/prototype_v2` 路径；
- P0-R1 与旧 M0—M9 专属回归入口。

## 兼容实现说明

迁移后的 `scripts/world_map/internal/` 中仍保留少量 `PrototypeV2*` 全局类名。这些名称只作为现有 GDScript 类型连接的内部兼容标识，不再对应旧场景、旧菜单、旧网格地图或旧数据路径。正式运行入口使用 `WorldMapMain` 与 `WorldMapCanvas`。

## 验证边界

统一验证现在只运行当前 V2.2 系统及世界地图守卫，不再把已删除旧原型纳入通过条件。性能守卫会检查旧菜单、旧人物创建、旧网格地图、旧静态原型场景和旧数据路径确实不存在。

线上提交阶段未运行本机 Godot。同步后必须执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\v2_2\run_local_acceptance.ps1 `
  -OpenManualReview
```
