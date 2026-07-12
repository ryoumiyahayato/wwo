# 1900年二维社会与战争模拟 Demo

一个使用 Godot 制作的二维、离线、可暂停、实时推进的社会与战争模拟项目。玩家从架空国家的一名社会人物开始，通过技能、职业、组织和关系逐步获得影响力。

## 当前范围

目标 P0 Demo 包含两个架空国家、双层二维地图、人物随机开局、行动与组织、简化 AI、继承、存档和开发工具。历史 Windows 11 x86-64 系统原型已经成功导出，但人工验收确认普通玩家闭环尚未完成，当前处于 `P0-R1` 可玩性修复和本机复验阶段。Windows 10 为目标兼容平台，尚未实机验证。

地图支持拖动、滚轮缩放、法理边界、实际控制色、争夺斜纹、城市与铁路、自动前线和地区信息面板。直接施加控制压力、模拟易手及其他权威状态修改只在开发模式中显示。

## 环境要求

- Windows 11 x86-64（当前开发与历史导出环境）
- Godot 标准版 `4.6.3.stable.official.7d41c59c4`
- Compatibility 渲染器
- 强类型 GDScript

项目目标包含 Windows 10 x86-64，但当前尚未完成真机验证。Linux 和 macOS 仅保持设计兼容，不宣称已测试。

## 安装和运行

Godot 已由用户安装，不需要本项目下载或升级。当前开发机运行：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --path 'D:\wwo'
```

## 测试

原有底层回归：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script res://tests/test_runner.gd
```

P0-R1 真实玩家旅程：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script res://tests/p0_r1_player_journey.gd
```

基础启动检查：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --quit-after 5
```

完整本机验收步骤见 `docs/P0_R1_VALIDATION.md`。

## 导出

`export_presets.cfg` 提供 Windows Desktop x86-64、Linux x86-64 和 macOS Universal 预设。P0-R1 通过本机测试后再重新导出：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --export-release 'Windows Desktop' 'D:\wwo\builds\windows\wwo-p0-r1.exe'
```

Linux 与 macOS 未导出、未测试。

## 当前状态与限制

- M0 至 M9 的底层实现历史和 564 项旧自动检查记录保留，但它们不能单独证明普通玩家可玩性。
- P0-R1 第一轮源码已补充真实行动条件、正式保存入口、跨页面世界会话、最小 NPC 执行层和真实玩家旅程测试。
- 网页端无法运行本机 Godot；当前源码尚需执行旧回归、新旅程测试、1280×720 人工交互、保存加载和重新导出验收。
- 世界仍是程序绘制的架空正交地图；设置界面尚未开放。
- 在上述验收完成前，不得将当前版本标记为完成的 P0 Demo。
