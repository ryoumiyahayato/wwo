class_name PrototypeV2Interface
extends Control
## Draws the four-corner UI and its static card workspaces without formal services.

signal mode_requested(mode_id: String)
signal selection_clear_requested

const INK := Color("#efe6cf")
const INK_MUTED := Color("#bdb9a9")
const INK_DIM := Color("#8e938c")
const PANEL := Color(0.075, 0.105, 0.115, 0.96)
const PANEL_LIGHT := Color(0.115, 0.145, 0.145, 0.97)
const PANEL_SOFT := Color(0.13, 0.155, 0.15, 0.9)
const BORDER := Color(0.68, 0.61, 0.45, 0.5)
const GOLD := Color("#d9b968")
const GOLD_SOFT := Color("#a88b52")
const GREEN := Color("#78a67d")
const RED := Color("#b86a5b")
const AMBER := Color("#c8935d")
const BLUE := Color("#7392a1")
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)

const COUNTRY_CORNER := Rect2(16.0, 16.0, 304.0, 76.0)
const TIME_CORNER := Rect2(1000.0, 16.0, 264.0, 88.0)
const CHARACTER_CORNER := Rect2(16.0, 604.0, 360.0, 100.0)
const ACTIVITY_CORNER := Rect2(880.0, 558.0, 384.0, 146.0)
const IDENTITY_SWITCH := Rect2(502.0, 16.0, 276.0, 36.0)
const MODE_SWITCH := Rect2(410.0, 662.0, 456.0, 42.0)

var data: PrototypeV2Data
var identity: String = "worker"
var open_panel: String = ""
var character_section: String = "summary"
var relationship_category: String = "亲近关系"
var relationship_sort: String = "relationship"
var detail_person_id: String = ""
var action_detail_id: String = ""
var selected_object: Dictionary = {}
var paused: bool = true
var speed: int = 1
var current_mode: String = "legal"
var panel_progress: float = 0.0:
	set(value):
		panel_progress = value
		queue_redraw()

var _font: Font
var _click_targets: Array[Dictionary] = []
var _hover_tooltip: String = ""
var _hover_position: Vector2 = Vector2.ZERO
var _toast: String = ""
var _toast_until_msec: int = 0
var _panel_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	set_process(true)


func _process(_delta: float) -> void:
	if not _toast.is_empty() and Time.get_ticks_msec() >= _toast_until_msec:
		_toast = ""
		queue_redraw()


func setup(prototype_data: PrototypeV2Data) -> void:
	data = prototype_data
	queue_redraw()


func handle_pointer_motion(position: Vector2) -> bool:
	_hover_position = position
	var next_tooltip: String = ""
	for index: int in range(_click_targets.size() - 1, -1, -1):
		var target: Dictionary = _click_targets[index]
		if (target.get("rect", Rect2()) as Rect2).has_point(position):
			next_tooltip = str(target.get("tooltip", ""))
			break
	if next_tooltip != _hover_tooltip:
		_hover_tooltip = next_tooltip
		queue_redraw()
	return not next_tooltip.is_empty()


func handle_pointer_pressed(position: Vector2) -> bool:
	for index: int in range(_click_targets.size() - 1, -1, -1):
		var target: Dictionary = _click_targets[index]
		if (target.get("rect", Rect2()) as Rect2).has_point(position):
			_activate(str(target.get("action", "consume")), target.get("payload"))
			return true
	return false


func contains_point(position: Vector2) -> bool:
	for index: int in range(_click_targets.size() - 1, -1, -1):
		var target: Dictionary = _click_targets[index]
		if (target.get("rect", Rect2()) as Rect2).has_point(position):
			return true
	return false


func close_top_layer() -> bool:
	if not detail_person_id.is_empty():
		detail_person_id = ""
		queue_redraw()
		return true
	if not action_detail_id.is_empty():
		action_detail_id = ""
		queue_redraw()
		return true
	if not selected_object.is_empty():
		selected_object = {}
		selection_clear_requested.emit()
		queue_redraw()
		return true
	if not open_panel.is_empty():
		close_panel()
		return true
	return false


func open_panel_named(panel_id: String, animated: bool = true) -> void:
	if open_panel == panel_id and panel_progress >= 0.99 and animated:
		close_panel()
		return
	if _panel_tween != null:
		_panel_tween.kill()
	open_panel = panel_id
	detail_person_id = ""
	action_detail_id = ""
	selected_object = {}
	selection_clear_requested.emit()
	panel_progress = 0.0 if animated else 1.0
	if animated:
		_panel_tween = create_tween()
		_panel_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_panel_tween.tween_property(self, "panel_progress", 1.0, 0.22)
	queue_redraw()


func close_panel(animated: bool = true) -> void:
	if open_panel.is_empty():
		return
	if _panel_tween != null:
		_panel_tween.kill()
	if not animated:
		panel_progress = 0.0
		open_panel = ""
		queue_redraw()
		return
	_panel_tween = create_tween()
	_panel_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(self, "panel_progress", 0.0, 0.18)
	_panel_tween.tween_callback(func() -> void:
		open_panel = ""
		queue_redraw()
	)


func set_identity(identity_id: String) -> void:
	if identity_id != "worker" and identity_id != "official":
		return
	identity = identity_id
	detail_person_id = ""
	action_detail_id = ""
	queue_redraw()


func set_mode_display(mode_id: String) -> void:
	current_mode = mode_id
	queue_redraw()


func set_selected_object(value: Dictionary) -> void:
	selected_object = value.duplicate(true)
	open_panel = ""
	panel_progress = 0.0
	detail_person_id = ""
	action_detail_id = ""
	queue_redraw()


func apply_review_state(state_id: String) -> void:
	open_panel = ""
	panel_progress = 0.0
	detail_person_id = ""
	action_detail_id = ""
	selected_object = {}
	character_section = "summary"
	identity = "worker"
	match state_id:
		"worker_character":
			open_panel = "character"
			panel_progress = 1.0
		"official_character":
			identity = "official"
			open_panel = "character"
			panel_progress = 1.0
		"relationships":
			open_panel = "character"
			character_section = "relationships"
			panel_progress = 1.0
		"person_detail":
			open_panel = "character"
			character_section = "relationships"
			detail_person_id = "anna"
			panel_progress = 1.0
		"owned_organizations":
			open_panel = "character"
			character_section = "owned_orgs"
			panel_progress = 1.0
		"discover_organizations":
			open_panel = "character"
			character_section = "discover_orgs"
			panel_progress = 1.0
		"institutions", "official_permissions", "institution_official":
			identity = "official"
			open_panel = "country"
			panel_progress = 1.0
		"worker_permissions", "institution_worker":
			open_panel = "country"
			panel_progress = 1.0
		"world_activity":
			open_panel = "activity"
			panel_progress = 1.0
		"time_panel":
			open_panel = "time"
			panel_progress = 1.0
		"action_detail":
			open_panel = "character"
			character_section = "summary"
			action_detail_id = "学习"
			panel_progress = 1.0
		_:
			pass
	queue_redraw()


func debug_state() -> Dictionary:
	return {
		"identity": identity,
		"open_panel": open_panel,
		"character_section": character_section,
		"detail_person_id": detail_person_id,
		"selected_object": selected_object.duplicate(true),
		"paused": paused,
		"speed": speed,
	}


func get_panel_rect() -> Rect2:
	match open_panel:
		"country":
			return Rect2(16.0, 104.0, 520.0, 488.0)
		"time":
			return Rect2(992.0, 112.0, 272.0, 268.0)
		"character":
			return Rect2(16.0, 104.0, 500.0, 488.0)
		"activity":
			return Rect2(824.0, 112.0, 440.0, 434.0)
	return Rect2()


func _draw() -> void:
	_click_targets.clear()
	if data == null:
		_text(Vector2(32.0, 48.0), "原型静态数据尚未加载", 18, RED)
		return
	_draw_identity_switch()
	_draw_country_corner()
	_draw_time_corner()
	_draw_character_corner()
	_draw_activity_corner()
	_draw_mode_switch()
	if not open_panel.is_empty() and panel_progress > 0.01:
		match open_panel:
			"country":
				_draw_country_panel()
			"time":
				_draw_time_panel()
			"character":
				_draw_character_panel()
			"activity":
				_draw_activity_panel()
	if not selected_object.is_empty():
		_draw_object_card()
	if not detail_person_id.is_empty():
		_draw_person_detail()
	if not action_detail_id.is_empty():
		_draw_action_detail()
	if not _toast.is_empty():
		_draw_toast()
	if not _hover_tooltip.is_empty():
		_draw_tooltip()


func _draw_identity_switch() -> void:
	_panel(IDENTITY_SWITCH, Color(0.055, 0.08, 0.09, 0.88), Color(0.7, 0.62, 0.46, 0.32), 18)
	_text(Vector2(516.0, 39.0), "示例身份", 11, INK_MUTED)
	_pill(Rect2(590.0, 20.0, 82.0, 28.0), "普通工人", identity == "worker", "identity_worker", null, "切换为普通工人示例")
	_pill(Rect2(678.0, 20.0, 88.0, 28.0), "地方官员", identity == "official", "identity_official", null, "切换为地方官员示例")


func _draw_country_corner() -> void:
	_card(COUNTRY_CORNER, "corner_country", null, "打开国家与主要机构")
	draw_circle(Vector2(50.0, 54.0), 22.0, Color("#6f7f76"))
	draw_circle(Vector2(50.0, 54.0), 17.0, Color("#253b3c"))
	_text(Vector2(38.0, 60.0), "FR", 12, GOLD)
	_text(Vector2(82.0, 43.0), "法兰西共和国", 17, INK)
	_text(Vector2(82.0, 63.0), "议会共和制", 12, INK_MUTED)
	var institution: String = "河港机械工会 · 公开机构" if identity == "worker" else "北部工业区行政署 · 公共事务科"
	_text(Vector2(82.0, 82.0), institution, 11, GOLD)


func _draw_time_corner() -> void:
	_card(TIME_CORNER, "corner_time", null, "展开时间与自动暂停设置")
	draw_circle(Vector2(1028.0, 50.0), 22.0, Color("#263d3e"))
	draw_arc(Vector2(1028.0, 50.0), 15.0, 0.0, TAU, 32, GOLD_SOFT, 2.0)
	draw_line(Vector2(1028.0, 50.0), Vector2(1028.0, 39.0), GOLD, 2.0)
	draw_line(Vector2(1028.0, 50.0), Vector2(1036.0, 55.0), GOLD, 2.0)
	_text(Vector2(1058.0, 42.0), "1900年3月12日", 14, INK)
	_text(Vector2(1058.0, 61.0), "周一 · 14:00", 11, INK_MUTED)
	_text(Vector2(1014.0, 88.0), "Ⅱ" if paused else "▶", 14, GOLD)
	for index: int in range(4):
		var option: int = [1, 2, 4, 8][index]
		_pill(Rect2(1042.0 + float(index) * 42.0, 69.0, 36.0, 24.0), "%d×" % option, speed == option, "speed", option, "静态时间速度示意")
	_text(Vector2(1218.0, 88.0), "AⅡ", 10, INK_DIM)


func _draw_character_corner() -> void:
	_card(CHARACTER_CORNER, "corner_character", null, "打开人物中心")
	_draw_avatar(Vector2(58.0, 648.0), 29.0)
	var person: Dictionary = _identity_data()
	_text(Vector2(100.0, 632.0), str(person.get("name", "")), 18, INK)
	_text(Vector2(100.0, 652.0), str(person.get("role", "")), 12, GOLD)
	_text(Vector2(100.0, 672.0), str(person.get("life_summary", "")), 12, INK_MUTED)
	_text(Vector2(100.0, 691.0), "要紧：%s" % str(person.get("primary_concern", "")), 11, Color("#d0b77a"))


func _draw_activity_corner() -> void:
	_card(ACTIVITY_CORNER, "corner_activity", null, "展开世界动态历史")
	_text(Vector2(900.0, 584.0), "世界动态", 16, INK)
	_status_dot(Vector2(1238.0, 579.0), "important")
	_text(Vector2(900.0, 608.0), "河港食品价格异常上涨", 13, Color("#e1c788"))
	_text(Vector2(900.0, 628.0), "铁路货运中断推高本地成本", 11, INK_MUTED)
	draw_line(Vector2(900.0, 640.0), Vector2(1242.0, 640.0), Color(BORDER, 0.32), 1.0)
	_text(Vector2(900.0, 660.0), "本月地区组织活动", 12, INK)
	_text(Vector2(900.0, 680.0), "6 个组织在 5 个地区扩大影响", 11, INK_MUTED)


func _draw_mode_switch() -> void:
	_panel(MODE_SWITCH, Color(0.055, 0.08, 0.09, 0.9), Color(BORDER, 0.42), 10)
	var modes: Array = data.get_document("map_modes").get("modes", []) as Array
	for index: int in range(modes.size()):
		var mode: Dictionary = modes[index] as Dictionary
		var rect := Rect2(418.0 + float(index) * 110.0, 669.0, 102.0, 28.0)
		var mode_id: String = str(mode.get("id", ""))
		_pill(rect, str(mode.get("label", "")), current_mode == mode_id, "mode", mode_id, str(mode.get("description", "")))


func _draw_country_panel() -> void:
	var base: Rect2 = get_panel_rect()
	var rect: Rect2 = _animated_rect(base, Vector2(-42.0, 0.0))
	_panel(rect, PANEL, BORDER, 12)
	_register(rect, "consume", null, "")
	_text(rect.position + Vector2(22.0, 34.0), "国家与机构", 22, INK)
	_text(rect.position + Vector2(22.0, 57.0), "法兰西共和国 · 议会共和制", 13, GOLD)
	_icon_button(Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 28.0, 28.0), "×", "panel_close", null, "收起")
	var badge_text: String = "公开视角" if identity == "worker" else "地方行政视角"
	_pill(Rect2(rect.position.x + 360.0, rect.position.y + 47.0, 120.0, 26.0), badge_text, true, "consume", null, "权限决定信息与行动")
	_text(rect.position + Vector2(22.0, 91.0), "当前可见", 12, INK_MUTED)
	var institutions: Array = data.get_document("institutions").get("institutions", []) as Array
	var shown: int = 0
	for institution_variant: Variant in institutions:
		var institution: Dictionary = institution_variant as Dictionary
		var visibility: String = str(institution.get("worker_visibility" if identity == "worker" else "official_visibility", "hidden"))
		if visibility == "hidden":
			continue
		var card_rect := Rect2(rect.position.x + 18.0, rect.position.y + 104.0 + float(shown) * 122.0, rect.size.x - 36.0, 110.0)
		_draw_institution_card(card_rect, institution, visibility)
		shown += 1
		if shown >= 2:
			break
	if identity == "official":
		var permissions: Array = data.get_document("institutions").get("official_permissions", []) as Array
		_text(rect.position + Vector2(22.0, 364.0), "法定权限", 12, INK_MUTED)
		for index: int in range(mini(permissions.size(), 4)):
			_pill(Rect2(rect.position.x + 22.0 + float(index % 2) * 224.0, rect.position.y + 374.0 + float(index / 2) * 29.0, 214.0, 24.0), str(permissions[index]), false, "permission_info", permissions[index], "仅限当前辖区与职位")
		_text(rect.position + Vector2(22.0, 450.0), "🔒 中央财政委员会：需要中央财政职位", 11, AMBER)
	else:
		_text(rect.position + Vector2(22.0, 458.0), "完全无关的中央预算、外交与军事命令已隐藏", 11, INK_DIM)


func _draw_institution_card(rect: Rect2, institution: Dictionary, visibility: String) -> void:
	_panel(rect, PANEL_LIGHT, Color(BORDER, 0.32), 8)
	_text(rect.position + Vector2(14.0, 23.0), str(institution.get("name", "")), 16, INK)
	var state_color: Color = GREEN if visibility == "operable" else (AMBER if visibility == "known_locked" else BLUE)
	var state_label: String = "可参与" if visibility == "operable" else ("已知但受限" if visibility == "known_locked" else "公开信息")
	_status_badge(Rect2(rect.end.x - 106.0, rect.position.y + 10.0, 92.0, 23.0), state_label, state_color)
	_text(rect.position + Vector2(14.0, 45.0), "职责：%s" % str(institution.get("mandate", "")), 11, INK_MUTED)
	_text(rect.position + Vector2(14.0, 64.0), "议程：%s" % str(institution.get("agenda", "")), 11, INK_MUTED)
	if identity == "official" or visibility != "public":
		_text(rect.position + Vector2(14.0, 83.0), "预算：%s" % str(institution.get("budget", "")), 11, INK_MUTED)
	var access_key: String = "worker_access" if identity == "worker" else "official_access"
	_text(rect.position + Vector2(14.0, 101.0), str(institution.get(access_key, "")), 10, state_color)


func _draw_time_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(0.0, -32.0))
	_panel(rect, PANEL, BORDER, 12)
	_register(rect, "consume", null, "")
	_text(rect.position + Vector2(18.0, 31.0), "时间与自动暂停", 18, INK)
	_icon_button(Rect2(rect.end.x - 40.0, rect.position.y + 10.0, 28.0, 28.0), "×", "panel_close", null, "收起")
	_button(Rect2(rect.position.x + 18.0, rect.position.y + 49.0, 96.0, 32.0), "继续" if paused else "暂停", "toggle_pause", null, false, "原型中只切换视觉状态")
	for index: int in range(4):
		var option: int = [1, 2, 4, 8][index]
		_pill(Rect2(rect.position.x + 122.0 + float(index % 2) * 60.0, rect.position.y + 49.0 + float(index / 2) * 35.0, 54.0, 29.0), "%d×" % option, speed == option, "speed", option, "不推进正式世界时间")
	_text(rect.position + Vector2(18.0, 110.0), "自动暂停", 12, INK_MUTED)
	_check_row(rect.position + Vector2(18.0, 133.0), "玩家事件需要决定", true)
	_check_row(rect.position + Vector2(18.0, 157.0), "人物健康危险", true)
	_check_row(rect.position + Vector2(18.0, 181.0), "战争开始或结束", true)
	draw_line(rect.position + Vector2(18.0, 200.0), rect.position + Vector2(254.0, 200.0), Color(BORDER, 0.4), 1.0)
	_text(rect.position + Vector2(18.0, 222.0), "系统工具", 11, INK_DIM)
	_icon_button(Rect2(rect.position.x + 18.0, rect.position.y + 232.0, 70.0, 28.0), "保存", "system_save", null, "原型不写入任何存档")
	_icon_button(Rect2(rect.position.x + 96.0, rect.position.y + 232.0, 70.0, 28.0), "设置", "system_settings", null, "仅展示系统工具分组")
	_icon_button(Rect2(rect.position.x + 174.0, rect.position.y + 232.0, 80.0, 28.0), "返回", "system_return", null, "独立原型不连接正式菜单")


func _draw_character_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(-42.0, 24.0))
	_panel(rect, PANEL, BORDER, 12)
	_register(rect, "consume", null, "")
	_draw_avatar(rect.position + Vector2(48.0, 46.0), 28.0)
	var person: Dictionary = _identity_data()
	_text(rect.position + Vector2(88.0, 36.0), str(person.get("name", "")), 21, INK)
	_text(rect.position + Vector2(88.0, 58.0), str(person.get("role", "")), 12, GOLD)
	_text(rect.position + Vector2(88.0, 77.0), str(person.get("access_summary", "")), 10, INK_MUTED)
	_icon_button(Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 28.0, 28.0), "×", "panel_close", null, "收起")
	_draw_character_tabs(rect.position + Vector2(16.0, 92.0))
	var body := Rect2(rect.position.x + 16.0, rect.position.y + 160.0, rect.size.x - 32.0, rect.size.y - 176.0)
	match character_section:
		"summary":
			_draw_character_summary(body, person)
		"life_finance":
			_draw_life_finance(body, person)
		"work_ability":
			_draw_work_ability(body, person)
		"relationships":
			_draw_relationships(body)
		"plans":
			_draw_plans(body, person)
		"results":
			_draw_results(body, person)
		"owned_orgs":
			_draw_organizations(body, true)
		"discover_orgs":
			_draw_organizations(body, false)


func _draw_character_tabs(origin: Vector2) -> void:
	var tabs: Array = [
		["summary", "人物摘要"], ["life_finance", "生活与财务"], ["work_ability", "工作与能力"], ["relationships", "关系"],
		["plans", "个人计划"], ["results", "最近结果"], ["owned_orgs", "我的组织"], ["discover_orgs", "探索组织"],
	]
	for index: int in range(tabs.size()):
		var row: int = index / 4
		var column: int = index % 4
		_pill(Rect2(origin.x + float(column) * 116.0, origin.y + float(row) * 32.0, 108.0, 27.0), str(tabs[index][1]), character_section == str(tabs[index][0]), "character_section", str(tabs[index][0]), "在人物中心内切换，不叠加新面板")


func _draw_character_summary(rect: Rect2, person: Dictionary) -> void:
	_text(rect.position + Vector2(4.0, 20.0), "扫视状态", 12, INK_MUTED)
	_status_tile(Rect2(rect.position.x, rect.position.y + 30.0, 106.0, 58.0), "健康", str(person.get("health", "")), GREEN)
	_status_tile(Rect2(rect.position.x + 114.0, rect.position.y + 30.0, 106.0, 58.0), "疲劳", str(person.get("fatigue", "")), AMBER)
	_status_tile(Rect2(rect.position.x + 228.0, rect.position.y + 30.0, 106.0, 58.0), "压力", str(person.get("stress", "")), BLUE)
	_status_tile(Rect2(rect.position.x + 342.0, rect.position.y + 30.0, 110.0, 58.0), "本月结余", str(person.get("monthly_balance", "")), GOLD)
	_text(rect.position + Vector2(4.0, 111.0), "当前要紧", 12, INK_MUTED)
	_panel(Rect2(rect.position.x, rect.position.y + 121.0, rect.size.x, 48.0), PANEL_LIGHT, Color(BORDER, 0.3), 7)
	_text(rect.position + Vector2(14.0, 151.0), str(person.get("primary_concern", "")), 13, INK)
	_text(rect.position + Vector2(4.0, 194.0), "上下文行动", 12, INK_MUTED)
	var actions: Array = person.get("available_actions", []) as Array
	var states: Array = ["★", "✓", "!", "×", "!"] if identity == "worker" else ["✓", "✓", "★", "!", "×"]
	for index: int in range(mini(actions.size(), 5)):
		var action_name: String = str(actions[index])
		var state: String = states[index]
		var state_color: Color = GOLD if state == "★" else (GREEN if state == "✓" else (AMBER if state == "!" else RED))
		var tooltip: String = "当前有效值：72 · 成功线：45 · 保证线：65 · 主要限制：可支配时间"
		var action_rect := Rect2(rect.position.x + float(index % 3) * 151.0, rect.position.y + 205.0 + float(index / 3) * 39.0, 142.0, 32.0)
		_status_action(action_rect, "%s %s" % [state, action_name], state_color, "action_detail", action_name, tooltip)


func _draw_life_finance(rect: Rect2, person: Dictionary) -> void:
	_info_block(Rect2(rect.position.x, rect.position.y, rect.size.x, 84.0), "生活状态", [str(person.get("household", "")), str(person.get("housing", "")), "当前最紧迫：%s" % str(person.get("primary_concern", ""))])
	_info_block(Rect2(rect.position.x, rect.position.y + 94.0, rect.size.x, 92.0), "财务摘要", ["现金 %s · 本月净收入 %s" % [str(person.get("cash", "")), str(person.get("monthly_balance", ""))], str(person.get("income", "")), str(person.get("expenses", ""))])
	_text(rect.position + Vector2(4.0, 214.0), "悬停看主要支出；点击状态看完整来源", 11, INK_DIM)
	_status_action(Rect2(rect.position.x, rect.position.y + 228.0, 160.0, 32.0), "✓ 财务可控", GREEN, "action_detail", "财务摘要", "本月净收入：%s · 主要支出：住房、食品" % str(person.get("monthly_balance", "")))


func _draw_work_ability(rect: Rect2, person: Dictionary) -> void:
	_info_block(Rect2(rect.position.x, rect.position.y, rect.size.x, 84.0), "工作", [str(person.get("work", "")), "当前职位：%s" % str(person.get("position", "")), "最近评价：可靠，能够承担额外协调"])
	_info_block(Rect2(rect.position.x, rect.position.y + 94.0, rect.size.x, 82.0), "能力", [str(person.get("ability", "")), "主要成长来自工作实践与当前计划", "资格：与当前职位要求匹配"])
	_text(rect.position + Vector2(4.0, 205.0), "行动只保留与当前上下文有关的入口", 11, INK_DIM)
	_button(Rect2(rect.position.x, rect.position.y + 221.0, 132.0, 32.0), "工作投入", "action_detail", "工作投入", false, "提高表现，也增加疲劳")
	_button(Rect2(rect.position.x + 142.0, rect.position.y + 221.0, 112.0, 32.0), "休整", "action_detail", "休整", false, "牺牲计划进度以恢复")


func _draw_relationships(rect: Rect2) -> void:
	var categories: Array[String] = ["亲近关系", "经常接触", "普通熟人", "可经引荐接触", "公开人物"]
	for index: int in range(categories.size()):
		var width: float = 86.0 if index < 3 else 91.0
		var x: float = rect.position.x + float(index) * 91.0
		_pill(Rect2(x, rect.position.y, width, 24.0), categories[index].replace("关系", ""), relationship_category == categories[index], "relationship_category", categories[index], "未知人物不会出现在列表")
	_pill(Rect2(rect.position.x, rect.position.y + 31.0, 104.0, 23.0), "按关系排序", relationship_sort == "relationship", "relationship_sort", "relationship", "")
	_pill(Rect2(rect.position.x + 112.0, rect.position.y + 31.0, 118.0, 23.0), "按最近互动", relationship_sort == "recent", "relationship_sort", "recent", "")
	var visible: Array[Dictionary] = _filtered_relationships()
	for index: int in range(mini(visible.size(), 4)):
		var relation: Dictionary = visible[index]
		var column: int = index % 2
		var row: int = index / 2
		var card_rect := Rect2(rect.position.x + float(column) * 230.0, rect.position.y + 62.0 + float(row) * 117.0, 220.0, 106.0)
		_draw_relationship_card(card_rect, relation)
	if visible.is_empty():
		_text(rect.position + Vector2(10.0, 96.0), "该分类没有当前可见人物", 13, INK_MUTED)


func _draw_relationship_card(rect: Rect2, relation: Dictionary) -> void:
	_panel(rect, PANEL_LIGHT, Color(BORDER, 0.28), 8)
	_register(rect, "person_detail", str(relation.get("id", "")), "%s · %s · %s" % [str(relation.get("relation", "")), str(relation.get("status", "")), str(relation.get("common", ""))])
	_text(rect.position + Vector2(12.0, 22.0), str(relation.get("name", "")), 15, INK)
	_text(rect.position + Vector2(12.0, 41.0), "%s · %s" % [str(relation.get("occupation", "")), str(relation.get("region", ""))], 10, INK_MUTED)
	_text(rect.position + Vector2(12.0, 60.0), str(relation.get("relation", "")), 11, GOLD)
	_text(rect.position + Vector2(12.0, 78.0), str(relation.get("last_interaction", "")), 10, INK_DIM)
	_pill(Rect2(rect.position.x + 118.0, rect.position.y + 76.0, 88.0, 22.0), "直接联系" if str(relation.get("last_interaction", "")) != "从未直接互动" else "查看渠道", false, "person_contact", str(relation.get("id", "")), str(relation.get("contact", "")))


func _draw_plans(rect: Rect2, person: Dictionary) -> void:
	_info_block(Rect2(rect.position.x, rect.position.y, rect.size.x, 84.0), "主要计划", [str(person.get("plan", "")), "每周投入适中 · 不影响基本工作义务", "预计继续 6 周后复核"])
	_text(rect.position + Vector2(4.0, 112.0), "当前发展", 12, INK_MUTED)
	_text(rect.position + Vector2(12.0, 139.0), "• 疲劳偏高：可减少额外投入或休整", 12, INK)
	_text(rect.position + Vector2(12.0, 164.0), "• 最易接触：安娜·贝尔", 12, INK)
	_text(rect.position + Vector2(12.0, 189.0), "• 本月住房支出较上月增加", 12, INK)


func _draw_results(rect: Rect2, person: Dictionary) -> void:
	_info_block(Rect2(rect.position.x, rect.position.y, rect.size.x, 82.0), "最近结果", [str(person.get("recent_result", "")), "结果来源：当前职位与近期投入", "完整历史只在点击详情后出现"])
	_text(rect.position + Vector2(4.0, 113.0), "过去一个月", 12, INK_MUTED)
	_text(rect.position + Vector2(12.0, 141.0), "3 天前 · 完成一次同事联系", 12, INK)
	_text(rect.position + Vector2(12.0, 168.0), "2 周前 · 工资按合同支付", 12, INK)
	_text(rect.position + Vector2(12.0, 195.0), "本月 · 生活支出小幅增加", 12, INK)


func _draw_organizations(rect: Rect2, owned: bool) -> void:
	_pill(Rect2(rect.position.x, rect.position.y, 112.0, 26.0), "我的组织", owned, "character_section", "owned_orgs", "只显示已经加入的组织")
	_pill(Rect2(rect.position.x + 120.0, rect.position.y, 112.0, 26.0), "探索组织", not owned, "character_section", "discover_orgs", "只显示当前知道且可接触的未加入组织")
	var identity_records: Dictionary = _organization_identity_data()
	var organizations: Array = identity_records.get("owned" if owned else "discover", []) as Array
	if not owned:
		var filters: Array[String] = ["当前地区", "类型", "职业匹配", "关系引荐", "公开程度"]
		for index: int in range(filters.size()):
			_pill(Rect2(rect.position.x + float(index) * 91.0, rect.position.y + 34.0, 84.0, 22.0), filters[index], index == 0, "filter_info", filters[index], "静态筛选示意")
	for index: int in range(mini(organizations.size(), 3)):
		var organization: Dictionary = organizations[index] as Dictionary
		var y: float = rect.position.y + (36.0 if owned else 65.0) + float(index) * (133.0 if owned else 82.0)
		var card_rect := Rect2(rect.position.x, y, rect.size.x, 124.0 if owned else 74.0)
		if owned:
			_draw_owned_organization(card_rect, organization)
		else:
			_draw_discover_organization(card_rect, organization)


func _draw_owned_organization(rect: Rect2, organization: Dictionary) -> void:
	_panel(rect, PANEL_LIGHT, Color(BORDER, 0.3), 8)
	_text(rect.position + Vector2(12.0, 22.0), str(organization.get("name", "")), 15, INK)
	_text(rect.position + Vector2(12.0, 42.0), "职位：%s · %s" % [str(organization.get("position", "")), str(organization.get("department", ""))], 11, GOLD)
	_text(rect.position + Vector2(12.0, 61.0), "%s · 上级：%s · 下属：%s" % [str(organization.get("allowance", "")), str(organization.get("supervisor", "")), str(organization.get("subordinates", ""))], 10, INK_MUTED)
	_text(rect.position + Vector2(12.0, 80.0), "权限：%s" % str(organization.get("authority", "")), 10, INK_MUTED)
	_text(rect.position + Vector2(12.0, 99.0), "项目：%s" % str(organization.get("project", "")), 10, GREEN)
	_text(rect.position + Vector2(12.0, 117.0), "下一职位：%s" % str(organization.get("next_position", "")), 10, INK_DIM)
	_pill(Rect2(rect.end.x - 100.0, rect.position.y + 11.0, 86.0, 23.0), "参与项目", false, "organization_action", "参与项目", "仅显示已加入组织的上下文事务")


func _draw_discover_organization(rect: Rect2, organization: Dictionary) -> void:
	_panel(rect, PANEL_LIGHT, Color(BORDER, 0.28), 8)
	_text(rect.position + Vector2(12.0, 21.0), str(organization.get("name", "")), 14, INK)
	_text(rect.position + Vector2(12.0, 40.0), "%s · %s" % [str(organization.get("type", "")), str(organization.get("match", ""))], 10, INK_MUTED)
	_text(rect.position + Vector2(12.0, 59.0), str(organization.get("access", "")), 10, GOLD)
	var action: String = str(organization.get("action", ""))
	_pill(Rect2(rect.end.x - 104.0, rect.position.y + 24.0, 90.0, 26.0), action, false, "organization_action", action, "未加入组织的上下文入口")


func _draw_activity_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(44.0, 20.0))
	_panel(rect, PANEL, BORDER, 12)
	_register(rect, "consume", null, "")
	_text(rect.position + Vector2(20.0, 32.0), "世界动态", 21, INK)
	_text(rect.position + Vector2(20.0, 55.0), "只显示亲历、组织渠道或公开报道", 11, INK_MUTED)
	_icon_button(Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 28.0, 28.0), "×", "panel_close", null, "收起")
	var labels: Array[String] = ["与我相关", "本地", "国家", "世界"]
	for index: int in range(labels.size()):
		_pill(Rect2(rect.position.x + 18.0 + float(index) * 98.0, rect.position.y + 70.0, 90.0, 26.0), labels[index], index == 0, "activity_filter", labels[index], "静态消息筛选")
	var items: Array = data.get_document("activity").get("items", []) as Array
	for index: int in range(mini(items.size(), 5)):
		var item: Dictionary = items[index] as Dictionary
		var y: float = rect.position.y + 112.0 + float(index) * 61.0
		_status_dot(Vector2(rect.position.x + 27.0, y + 5.0), str(item.get("level", "normal")))
		_text(Vector2(rect.position.x + 44.0, y + 9.0), "%s · %s" % [str(item.get("time", "")), str(item.get("title", ""))], 12, INK)
		_text(Vector2(rect.position.x + 44.0, y + 28.0), str(item.get("detail", "")), 10, INK_MUTED)
		_text(Vector2(rect.position.x + 44.0, y + 45.0), str(item.get("source", "")), 9, INK_DIM)
		if index < 4:
			draw_line(Vector2(rect.position.x + 20.0, y + 53.0), Vector2(rect.end.x - 20.0, y + 53.0), Color(BORDER, 0.22), 1.0)


func _draw_object_card() -> void:
	var object_type: String = str(selected_object.get("type", ""))
	var object_data: Dictionary = selected_object.get("data", {}) as Dictionary
	var rect := Rect2(702.0, 146.0, 380.0, 360.0)
	_panel(rect, PANEL, BORDER, 12)
	_register(rect, "consume", null, "")
	_icon_button(Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 28.0, 28.0), "×", "object_close", null, "取消地图选择")
	if object_type == "region":
		_text(rect.position + Vector2(20.0, 34.0), str(object_data.get("name", "")), 21, INK)
		_text(rect.position + Vector2(20.0, 58.0), str(object_data.get("country", "")), 12, GOLD)
		_draw_region_fields(rect, object_data)
	elif object_type == "city":
		_text(rect.position + Vector2(20.0, 34.0), str(object_data.get("name", "")), 21, INK)
		_text(rect.position + Vector2(20.0, 58.0), "主要城市%s" % (" · 港口" if bool(object_data.get("port", false)) else ""), 12, GOLD)
		var region_id: String = str(object_data.get("region", ""))
		var region: Dictionary = _region_by_id(region_id)
		_draw_region_fields(rect, region)
	_pill(Rect2(rect.position.x + 20.0, rect.end.y - 48.0, 112.0, 28.0), "查看公开信息", true, "object_info", null, "地图选择只改变观察对象")
	_pill(Rect2(rect.position.x + 142.0, rect.end.y - 48.0, 112.0, 28.0), "行动需上下文", false, "object_info", null, "不会隐式改变人物计划")


func _draw_region_fields(rect: Rect2, region: Dictionary) -> void:
	var fields: Array = [
		["主要城市", str(region.get("capital", ""))],
		["人口", str(region.get("population", ""))],
		["区域市场", str(region.get("market", ""))],
		["交通", str(region.get("transport", ""))],
		["公开政治", str(region.get("politics", ""))],
	]
	for index: int in range(fields.size()):
		var y: float = rect.position.y + 94.0 + float(index) * 43.0
		_text(Vector2(rect.position.x + 20.0, y), str(fields[index][0]), 10, INK_DIM)
		_text(Vector2(rect.position.x + 112.0, y), str(fields[index][1]), 12, INK)
		draw_line(Vector2(rect.position.x + 20.0, y + 13.0), Vector2(rect.end.x - 20.0, y + 13.0), Color(BORDER, 0.2), 1.0)


func _draw_person_detail() -> void:
	var relation: Dictionary = _relationship_by_id(detail_person_id)
	if relation.is_empty():
		return
	var rect := Rect2(538.0, 148.0, 390.0, 410.0)
	_panel(rect, PANEL, BORDER, 12)
	_register(rect, "consume", null, "")
	_draw_avatar(rect.position + Vector2(48.0, 48.0), 26.0)
	_text(rect.position + Vector2(88.0, 37.0), str(relation.get("name", "")), 20, INK)
	_text(rect.position + Vector2(88.0, 58.0), "%s · %s" % [str(relation.get("occupation", "")), str(relation.get("region", ""))], 11, GOLD)
	_icon_button(Rect2(rect.end.x - 42.0, rect.position.y + 12.0, 28.0, 28.0), "×", "close_person_detail", null, "关闭人物卡")
	var rows: Array = [
		["关系", relation.get("relation", "")], ["最近互动", relation.get("last_interaction", "")],
		["公开状态", relation.get("status", "")], ["接触方式", relation.get("contact", "")],
		["共同关系", relation.get("common", "")],
	]
	for index: int in range(rows.size()):
		var y: float = rect.position.y + 98.0 + float(index) * 36.0
		_text(Vector2(rect.position.x + 20.0, y), str(rows[index][0]), 10, INK_DIM)
		_text(Vector2(rect.position.x + 112.0, y), str(rows[index][1]), 12, INK)
	_text(rect.position + Vector2(20.0, 298.0), "上下文行动", 11, INK_MUTED)
	var actions: Array[String] = ["联系", "加深关系", "请求帮助", "引荐", "调查", "查看共同关系"]
	for index: int in range(actions.size()):
		var action: String = actions[index]
		var locked: bool = action == "请求帮助" and detail_person_id != "anna"
		_button(Rect2(rect.position.x + 20.0 + float(index % 3) * 116.0, rect.position.y + 311.0 + float(index / 3) * 40.0, 106.0, 32.0), ("🔒 " if locked else "") + action, "person_action", action, locked, "需要更高信任" if locked else "从当前人物卡直接互动")


func _draw_action_detail() -> void:
	var rect := Rect2(548.0, 208.0, 364.0, 286.0)
	_panel(rect, Color(0.065, 0.095, 0.105, 0.985), Color(GOLD, 0.62), 12)
	_register(rect, "consume", null, "")
	_text(rect.position + Vector2(20.0, 33.0), action_detail_id, 20, INK)
	_status_badge(Rect2(rect.end.x - 124.0, rect.position.y + 13.0, 106.0, 24.0), "★ 保证成功", GOLD)
	_icon_button(Rect2(rect.end.x - 42.0, rect.position.y + 48.0, 28.0, 28.0), "×", "close_action_detail", null, "关闭详情")
	_text(rect.position + Vector2(20.0, 69.0), "当前有效值 72 · 成功线 45 · 保证线 65", 12, INK_MUTED)
	draw_line(rect.position + Vector2(20.0, 86.0), rect.position + Vector2(344.0, 86.0), Color(BORDER, 0.42), 1.0)
	var breakdown: Array = [["能力", "+17"], ["准备", "+21"], ["资金", "+20"], ["关系支持", "+8"], ["目标阻力", "−12"]]
	for index: int in range(breakdown.size()):
		var y: float = rect.position.y + 112.0 + float(index) * 28.0
		_text(Vector2(rect.position.x + 28.0, y), str(breakdown[index][0]), 12, INK)
		_text(Vector2(rect.position.x + 294.0, y), str(breakdown[index][1]), 12, GREEN if str(breakdown[index][1]).begins_with("+") else RED)
	_text(rect.position + Vector2(20.0, 267.0), "QA 内部字段和公式在普通原型界面中隐藏", 10, INK_DIM)


func _draw_toast() -> void:
	var width: float = minf(520.0, _font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x + 36.0)
	var rect := Rect2((size.x - width) * 0.5, 612.0, width, 34.0)
	_panel(rect, Color(0.06, 0.09, 0.095, 0.96), Color(GOLD, 0.45), 17)
	_text(rect.position + Vector2(18.0, 22.0), _toast, 12, INK)


func _draw_tooltip() -> void:
	var width: float = clampf(_font.get_string_size(_hover_tooltip, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x + 28.0, 180.0, 500.0)
	var position: Vector2 = _hover_position + Vector2(16.0, 18.0)
	position.x = minf(position.x, size.x - width - 12.0)
	position.y = minf(position.y, size.y - 56.0)
	var rect := Rect2(position, Vector2(width, 38.0))
	_panel(rect, Color(0.035, 0.055, 0.06, 0.985), Color(GOLD, 0.52), 7)
	_text(rect.position + Vector2(14.0, 24.0), _hover_tooltip, 11, INK)


func _activate(action: String, payload: Variant) -> void:
	match action:
		"corner_country":
			open_panel_named("country")
		"corner_time":
			open_panel_named("time")
		"corner_character":
			open_panel_named("character")
		"corner_activity":
			open_panel_named("activity")
		"identity_worker":
			set_identity("worker")
		"identity_official":
			set_identity("official")
		"mode":
			current_mode = str(payload)
			mode_requested.emit(str(payload))
		"panel_close":
			close_panel()
		"object_close":
			selected_object = {}
			selection_clear_requested.emit()
			queue_redraw()
		"character_section":
			character_section = str(payload)
			detail_person_id = ""
			action_detail_id = ""
			queue_redraw()
		"relationship_category":
			relationship_category = str(payload)
			queue_redraw()
		"relationship_sort":
			relationship_sort = str(payload)
			queue_redraw()
		"person_detail":
			detail_person_id = str(payload)
			queue_redraw()
		"close_person_detail":
			detail_person_id = ""
			queue_redraw()
		"action_detail":
			action_detail_id = str(payload)
			queue_redraw()
		"close_action_detail":
			action_detail_id = ""
			queue_redraw()
		"toggle_pause":
			paused = not paused
			_show_toast("原型时间已%s；未推进正式世界" % ("暂停" if paused else "继续"))
		"speed":
			speed = int(payload)
			queue_redraw()
		"system_save":
			_show_toast("保存仅为视觉占位；原型不会写入 user://")
		"system_settings":
			_show_toast("设置入口为静态占位")
		"system_return":
			_show_toast("独立原型不连接正式菜单")
		"person_contact", "person_action", "organization_action", "permission_info", "filter_info", "activity_filter", "object_info":
			_show_toast("%s · 静态交互示意" % str(payload if payload != null else "公开信息"))
		_:
			pass


func _identity_data() -> Dictionary:
	var identities: Dictionary = data.get_document("characters").get("identities", {}) as Dictionary
	var value: Variant = identities.get(identity, {})
	return value as Dictionary if value is Dictionary else {}


func _organization_identity_data() -> Dictionary:
	var identities: Dictionary = data.get_document("organizations").get("identities", {}) as Dictionary
	var value: Variant = identities.get(identity, {})
	return value as Dictionary if value is Dictionary else {}


func _filtered_relationships() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for relation_variant: Variant in data.get_document("relationships").get("relationships", []):
		if relation_variant is Dictionary:
			var relation: Dictionary = relation_variant as Dictionary
			if str(relation.get("category", "")) == relationship_category:
				result.append(relation)
	if relationship_sort == "recent":
		var order: Dictionary = {"今天": 0, "3 天前": 1, "2 个月前": 2, "一年多以前": 3, "从未直接互动": 4}
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(order.get(str(a.get("last_interaction", "")), 9)) < int(order.get(str(b.get("last_interaction", "")), 9))
		)
	return result


func _relationship_by_id(person_id: String) -> Dictionary:
	for relation_variant: Variant in data.get_document("relationships").get("relationships", []):
		if relation_variant is Dictionary and str((relation_variant as Dictionary).get("id", "")) == person_id:
			return relation_variant as Dictionary
	return {}


func _region_by_id(region_id: String) -> Dictionary:
	for region_variant: Variant in data.get_document("regions").get("regions", []):
		if region_variant is Dictionary and str((region_variant as Dictionary).get("id", "")) == region_id:
			return region_variant as Dictionary
	return {}


func _show_toast(message: String) -> void:
	_toast = message
	_toast_until_msec = Time.get_ticks_msec() + 2300
	queue_redraw()


func _animated_rect(target: Rect2, offset: Vector2) -> Rect2:
	return Rect2(target.position + offset * (1.0 - panel_progress), target.size)


func _register(rect: Rect2, action: String, payload: Variant = null, tooltip: String = "") -> void:
	_click_targets.append({"rect": rect, "action": action, "payload": payload, "tooltip": tooltip})


func _panel(rect: Rect2, color: Color, border_color: Color, radius: int) -> void:
	draw_rect(Rect2(rect.position + Vector2(0.0, 5.0), rect.size), SHADOW)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	draw_style_box(style, rect)


func _card(rect: Rect2, action: String, payload: Variant, tooltip: String) -> void:
	_panel(rect, Color(0.065, 0.095, 0.105, 0.92), Color(BORDER, 0.46), 10)
	_register(rect, action, payload, tooltip)


func _text(position: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _pill(rect: Rect2, label: String, active: bool, action: String, payload: Variant, tooltip: String) -> void:
	var fill: Color = Color(GOLD_SOFT, 0.34) if active else Color(0.16, 0.19, 0.18, 0.9)
	var border: Color = Color(GOLD, 0.62) if active else Color(BORDER, 0.26)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	draw_style_box(style, rect)
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
	_text(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + rect.size.y * 0.5 + 4.0), label, 10, INK if active else INK_MUTED)
	_register(rect, action, payload, tooltip)


func _button(rect: Rect2, label: String, action: String, payload: Variant, locked: bool, tooltip: String) -> void:
	var fill: Color = Color(0.18, 0.22, 0.2, 0.96) if not locked else Color(0.12, 0.13, 0.13, 0.8)
	var border: Color = Color(GOLD_SOFT, 0.5) if not locked else Color(RED, 0.35)
	_panel(rect, fill, border, 7)
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	_text(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + rect.size.y * 0.5 + 4.0), label, 11, INK if not locked else INK_DIM)
	_register(rect, "consume" if locked else action, payload, tooltip)


func _icon_button(rect: Rect2, label: String, action: String, payload: Variant, tooltip: String) -> void:
	_panel(rect, Color(0.12, 0.15, 0.14, 0.92), Color(BORDER, 0.3), 7)
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	_text(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + rect.size.y * 0.5 + 4.0), label, 11, INK_MUTED)
	_register(rect, action, payload, tooltip)


func _status_badge(rect: Rect2, label: String, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.18)
	style.border_color = Color(color, 0.48)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	draw_style_box(style, rect)
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
	_text(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + rect.size.y * 0.5 + 4.0), label, 10, color)


func _status_tile(rect: Rect2, label: String, value: String, color: Color) -> void:
	_panel(rect, PANEL_LIGHT, Color(color, 0.34), 7)
	_text(rect.position + Vector2(10.0, 21.0), label, 10, INK_DIM)
	_text(rect.position + Vector2(10.0, 45.0), value, 15, color)
	_register(rect, "consume", null, "%s：%s · 点击详情可查看来源" % [label, value])


func _status_action(rect: Rect2, label: String, color: Color, action: String, payload: Variant, tooltip: String) -> void:
	_panel(rect, Color(color, 0.13), Color(color, 0.48), 7)
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	_text(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + rect.size.y * 0.5 + 4.0), label, 11, color)
	_register(rect, action, payload, tooltip)


func _info_block(rect: Rect2, title: String, lines: Array) -> void:
	_panel(rect, PANEL_LIGHT, Color(BORDER, 0.3), 8)
	_text(rect.position + Vector2(14.0, 22.0), title, 14, GOLD)
	for index: int in range(lines.size()):
		_text(rect.position + Vector2(14.0, 43.0 + float(index) * 18.0), lines[index], 10, INK_MUTED)
	_register(rect, "consume", null, "点击详情查看完整已知来源")


func _check_row(position: Vector2, label: String, checked: bool) -> void:
	draw_rect(Rect2(position, Vector2(16.0, 16.0)), Color(0.12, 0.16, 0.15, 0.9))
	draw_rect(Rect2(position, Vector2(16.0, 16.0)), Color(BORDER, 0.5), false, 1.0)
	if checked:
		draw_line(position + Vector2(3.0, 8.0), position + Vector2(7.0, 12.0), GREEN, 2.0)
		draw_line(position + Vector2(7.0, 12.0), position + Vector2(14.0, 3.0), GREEN, 2.0)
	_text(position + Vector2(25.0, 13.0), label, 11, INK_MUTED)


func _status_dot(position: Vector2, level: String) -> void:
	var color: Color = INK_MUTED
	if level == "important":
		color = AMBER
	elif level == "world":
		color = BLUE
	draw_circle(position, 5.0, Color(color, 0.22))
	draw_circle(position, 2.5, color)


func _draw_avatar(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("#273b3b"))
	draw_circle(center, radius - 3.0, Color("#b7a87d"))
	draw_circle(center + Vector2(0.0, -7.0), radius * 0.29, Color("#334443"))
	draw_arc(center + Vector2(0.0, 14.0), radius * 0.5, PI, TAU, 20, Color("#334443"), 10.0)
	draw_arc(center, radius - 1.5, 0.0, TAU, 32, Color(GOLD, 0.48), 1.5)
