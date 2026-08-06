#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "refactors" / "state_ownership_matrix.md"
TEXT = r'''# 状态所有权矩阵

## 0. 基线与规则

第一批实现基于基础提交`b4a9d637e294aa53b0c0e2525260421dce3b5182`，由PR #30实施。本矩阵描述第一批删除后的当前所有权及其余状态组的既有目标。

- 同一事实原则上只能有一个可写来源。
- selected、hovered、focused、active、pending、previous、requested、displayed、loaded、visible、enabled保持区分。
- UI只保存交互必需的瞬时状态；业务状态通过只读查询或命令访问。
- 不迁入 Autoload、万能 Context 或字符串键 Dictionary。

| 概念 | 当前可写所有者 | 写入者 | 只读者 | 生命周期 | 存档 | 可推导 | 副本 | 当前不一致处理 | 重构后唯一事实源 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| 当前玩家 | GameSessionService.player_character；roster player_character_id | set/transfer、继承、存档恢复 | 动作、存档、社会服务、HUD | 进程会话 | 是 | 否 | 与 selected_person_id/active_character_key 未对齐 | 靠调用顺序 | player_character 对象；roster ID 为持久标识 | 第一批只处理派生国家 |
| 当前国家（玩家所属） | player_character.country_id | set/transfer/succession/load只提交玩家对象 | 存档、国家入口 | 进程会话 | 旧JSON键保留 | 是 | 无运行期副本 | restore_snapshot要求旧键等于恢复玩家国家，否则拒绝 | player_character.country_id | 第一批已完成 |
| 当前地图选择政权 | 半球 selected_country_id | 鼠标、历史焦点、返回、测试 | 地图、政经面板、导航 | 场景 | 否 | 否 | 与玩家国家同名不同义 | 政经面板存在 home/France/首项 fallback | 正式导航控制器 selected_map_polity_id | 先补选择行为测试 |
| 当前角色/显示身份 | active_character_key、selected_person_id、player_character | HUD、模拟 select_person、继承 | 人物面板、行动服务 | 场景/模拟/进程 | 部分 | 部分 | displayed/selected/active 未区分 | 各系统独立 | 三个明确语义字段 | K：人工决定 |
| 当前日期 | sim_*、Formal minutes、Economy total_hour、SimulationClock | 计时器、advance、恢复 | HUD、经济、事件、存档 | 场景/模拟 | 是 | 年月日可由累计分钟推导 | 至少3套可写 | Application 同时推进两套 | 单一正式时钟 | P0 独立批次 |
| 游戏速度 | sim_speed、speed_multiplier、UI speed | 输入、binding、恢复 | 计时器、HUD | 场景/模拟 | 部分 | UI可推导 | 多份可写 | binding刷新/手工赋值 | 正式时钟 speed_multiplier | 与时间同批 |
| 暂停状态 | sim_paused、is_paused、UI paused | 输入、阻塞面板、恢复 | 计时器、HUD | 场景/模拟 | 部分 | UI可推导 | 多份可写 | 面板结束恢复 previous | 正式时钟 is_paused | previous临时状态保留 |
| 世界/大区/城市导航 | space_level + world_mode | runtime/history/admin/release | 绘制、输入、面包屑、viewport | 场景 | 否 | 否 | 多写入者并手工清理 | 分支同步 | 正式场景导航控制器 | P0，非第一批 |
| 当前大区 | selected_region_id | 点击、循环、转场 | 区域绘制、城市列表 | 场景 | 否 | 否 | 与 territory/admin 关系不清 | 转场清空 | selected_region_id | 先映射 ID |
| 当前城市 | selected_city_id | 点击、enter、返回 | 城市层、机构 | 场景 | 否 | 否 | 与 admin1 local 粒度可能不同 | 转场清空 | selected_city_id | 补导航冒烟测试 |
| 历史 territory | selected_historical_territory_iso | 历史地图点击/默认选择 | 历史焦点、admin1 | 场景 | 否 | 否 | 与政权/行政区不同 | fallback选择第一个 territory | 明确 historical_territory_id | K |
| 历史几何 admin1 | selected_world_admin1_id | 点击、唯一记录自动进入、返回 | admin1绘制、城市层 | 场景 | 否 | 否 | 与目录/近似 admin 字段重叠 | 按数据可用性分支 | historical_admin1_geometry_id | K |
| 历史目录 admin | selected_admin_unit_id | 目录按钮、翻页、返回 | 目录、面包屑 | 场景 | 否 | 否 | 不是几何 ID | 手工清空 | displayed_admin_catalog_entry_id | K |
| 区域近似行政分区 | selected_administrative_unit_id | 区域几何点击/换区 | 区域绘制 | 场景 | 否 | 否 | 现代近似与历史数据并存 | 视图 fallback | approximate_subdivision_id | K，需数据决定 |
| 悬停对象 | 多个 hover_* | 鼠标、缩放/转场清理 | 高亮、提示 | 指针/帧 | 否 | 否 | 按对象类型分字段合理，清理分散 | 各层直接清空 | 场景拥有，统一清理入口 | 不合并 selected |
| 聚焦对象 | 历史焦点、camera_focus_id、Control focus | 双击、按钮、UI系统 | 相机/绘制/键盘 | 场景 | 否 | 否 | 三种 focus 不同义 | 各自处理 | 明确 political/camera/keyboard focus | 不得合并 |
| 活动对象 | player_character、current_action、当前活动 | 行动开始/结算/选择 | 行动、HUD、存档 | 会话/行动 | 是 | 否 | active 跨业务域 | 各服务判断 | 各业务服务分别拥有 | 不建万能 active_object |
| 打开面板/窗口 | economy_panel_open、workspace_open、info_open、active_hud_panel、legacy open_panel | 键盘、按钮、导航 | 绘制、命中 | 场景 | 否 | 部分 | 开关与 Node.visible/viewport mode双写 | 手工同步 | 各场景一个明确面板选择 | 正式 HUD 批次 |
| UI展开动画 | info_open + info_progress + Tween | 按钮、动画 | 绘制、命中 | 场景动画 | 否 | progress不可瞬时推导 | 目标与动画不同，不是重复 | Tween推进 | 两者保留，progress不做业务事实 | 保留 |
| 地图倍率 | world_zoom、旧 zoom | 滚轮、预设、恢复 | 相机、投影、标签 | 场景 | 旧地图部分 | camera.size/半径可推导 | zoom与相机属性双写 | apply geometry | world_zoom为源 | 相机批次 |
| 相机状态 | yaw/tilt/angular_velocity/drag；旧 pan/focus | 鼠标、惯性、预设 | 投影、命中 | 场景 | 旧地图部分 | 屏幕几何可推导 | 缓存与相机分散 | dirty重建 | 半球拥有 yaw/tilt/zoom | 先做性能基线 |
| 当前事件 | selected_event_id + _world_events | HUD/地图、seed | 地图、信息面板 | 场景 | 否 | 事件应来自服务 | 展示层生成业务事件 | 无跨服务一致性 | 正式事件服务；UI只选ID | 事件批次 |
| 消息/未读 | activity_unread、通知服务、communication inbox | seed、mark read、通信 | 右下HUD、消息面板 | 场景/模拟 | 部分 | HUD计数可推导 | 多套未读事实 | 各自独立 | 正式消息服务 unread_count() | 事件消息批次 |
| 游戏模式 | world_mode、layout_mode、旧 current_mode、review/truth/developer | 输入、参数、测试、恢复 | 绘制、权限、数据可见性 | 场景/会话 | 部分 | 不同概念不可合并 | mode命名过宽 | 分支 | 具体命名的独立模式 | 分批 |
| 加载状态 | 各服务 initialized/error、SceneTree launch meta、menu _entering | initialize/load/menu | 菜单、错误UI | 初始化/跨场景一次性 | 部分 | 部分 | 同名 initialized 属不同服务；meta隐式全局 | bool/error/meta | 服务各自拥有；启动请求仅边界存在 | 去静默默认 |
| 存档状态 | Formal save/schema、GameSave snapshots、pending_load_path | 菜单、保存、恢复 | 继续游戏、测试 | 磁盘/跨场景 | 是 | save_exists可查询 | 多个存档体系 | 各自路径/schema | 产品组合根拥有存档服务 | 先建 fixture矩阵 |
| 缓存 | 投影、屏幕多边形、visible/label/text/spatial caches | 数据、相机、resize、dirty | 绘制、命中 | 场景/数据版本 | 否 | 可重算但成本不同 | 部分有dirty，部分每帧重建 | 混合 | 仅保留有证据缓存 | 最后处理 |

## 1. 第一批所有权决定

`GameSessionService.player_character`拥有当前玩家人物。玩家所属国家只由该对象的`country_id`属性取得；会话服务中的第二个可写国家ID已删除。无玩家时派生结果为空字符串。地图选择政权仍属于正式半球导航场景，并继续与玩家所属国家区分。

## 2. 仍需人工决定

1. 正式产品是否继续组合 V2/V2.3 人物与社会服务；这决定 `selected_person_id` 与 `player_character`关系。
2. 历史 admin1、现代近似 admin1、历史名称目录是否建立显式 crosswalk，或保持三个视图状态。
3. 事件、消息、情报最终由哪个正式服务提供；半球 seed 当前只能视为展示数据。
4. PR #19 合并后旧 PrototypeV2 地图脚本删除、归档或保留为隔离样机。
5. 支持哪些旧存档 schema，以及每个迁移分支的删除条件。'''


def main() -> None:
    OUTPUT.write_text(TEXT + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
