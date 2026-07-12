# 1900年二维社会与战争模拟 Demo

一个使用 Godot 制作的二维、离线、可暂停、实时推进的社会与战争模拟项目。玩家从架空国家的一名社会人物开始，通过技能、职业、组织和关系逐步获得影响力。

## 当前 Demo 范围

目标 Demo 包含两个架空国家、双层二维地图、人物随机开局、行动与组织、简化 AI、继承、存档和开发工具。P0 Demo 1.0 的 Windows 11 x86-64 可执行版本已经完成；Windows 10 为目标兼容平台，尚未实机验证。

地图支持拖动、滚轮缩放、法理边界、实际控制色、争夺斜纹、城市与铁路、自动前线和地区信息面板。信息面板可施加简化控制压力或模拟易手，以验证前线增删。

## 环境要求

- Windows 11 x86-64（本轮实际环境）
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

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --script res://tests/test_runner.gd
```

基础启动检查：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --quit-after 5
```

## 导出

`export_presets.cfg` 提供 Windows Desktop x86-64、Linux x86-64 和 macOS Universal 预设。只有 Windows 是本项目已验证目标；Linux 与 macOS 未导出、未测试。Windows Release 导出命令：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --export-release 'Windows Desktop' 'D:\wwo\builds\windows\wwo-p0-demo.exe'
```

## 当前完成度与限制

- M0 至 M8：已完成；M9 Windows 11 可执行 Demo 已完成，当前共 564 项自动检查通过。
- 新游戏先明确选择国家与随机模式并生成人物，再进入战略地图；存在手动档时主菜单可加载，设置仍禁用。
- 世界仍是程序绘制的架空正交地图；开发面板默认隐藏，手动档和单一周自动档写入 `user://`。
- 目标规模一年 8 倍自动模拟与 Windows 11 Release 冒烟已完成；Windows 10 产物真机测试仍未完成。
