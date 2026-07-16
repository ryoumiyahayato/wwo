# 《1900》V2 静态 UI 与地图视觉原型范围

## 目标

本原型只验证 1280×720 下的全屏地图、四角语义布局、对象入口、权限差异、信息层级、短动画和左键交互方向。它使用静态假数据帮助用户判断新版视觉与信息架构，不代表任何正式玩法系统已经接入。

## 不包含的正式功能

- 不接入现有社会模拟、人物行动、关系、组织、AI、市场、战争、技术或时间服务。
- 不读取或写入正式存档，不访问 `user://`，不修改正式玩家和世界状态。
- 不实现真实概率、资金流、区域市场、历史边界、战争结算或国家政治。
- 保存、设置、自动暂停和返回只展示视觉分组；时间速度只改变原型显示状态。

## 目录隔离

- 场景：`scenes/prototype_v2/`
- 脚本：`scripts/prototype_v2/`
- 静态数据：`data/prototype_v2/`
- 自制视觉说明：`assets/prototype_v2/`
- 原型测试：`tests/prototype_v2/`
- 说明与验收：`docs/prototype_v2/`
- 本地截图：`artifacts/prototype_v2_review/`，默认不提交

原型不修改 `project.godot` 的 `main_scene`，不加入正式战略地图节点，也不调用正式领域服务。所有原型 JSON 均包含 `prototype_only: true`。

## 静态数据范围

数据覆盖普通工人、地方官员、有限关系、已加入与可探索组织、地方机构、地区卡、四种静态地图模式、和平动态、战争视觉示例以及成功/风险/锁定行动状态。所有显示均为原型假数据。

## 启动方式

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --path 'D:\wwo' `
  'res://scenes/prototype_v2/prototype_v2_main.tscn'
```

关闭该独立场景不会改变正式游戏状态。
