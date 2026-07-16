class_name PrototypeV2Interface
extends Control
## V2.1 four-corner interface. The map remains the primary visual surface.

signal mode_requested(mode_id: String)
signal selection_clear_requested

const INK := Color("#f1ead9")
const INK_MUTED := Color("#bcc2b8")
const INK_DIM := Color("#89958f")
const PANEL := Color(0.035, 0.068, 0.074, 0.94)
const PANEL_SOLID := Color(0.035, 0.066, 0.072, 0.985)
const PANEL_SOFT := Color(0.09, 0.125, 0.124, 0.9)
const LINE := Color(0.74, 0.68, 0.51, 0.25)
const GOLD := Color("#e0bd70")
const GREEN := Color("#83b68b")
const RED := Color("#c76f61")
const AMBER := Color("#d19a5f")
const BLUE := Color("#75a8b6")
const SHADOW := Color(0.0, 0.0, 0.0, 0.3)

const COUNTRY_CORNER := Rect2(18.0, 18.0, 272.0, 66.0)
const TIME_CORNER := Rect2(1028.0, 18.0, 234.0, 74.0)
const CHARACTER_CORNER := Rect2(18.0, 630.0, 304.0, 72.0)
const ACTIVITY_CORNER := Rect2(944.0, 622.0, 318.0, 80.0)
const MODE_ENTRY := Rect2(548.0, 674.0, 184.0, 28.0)
const REVIEW_SWITCH := Rect2(502.0, 14.0, 276.0, 34.0)
const MAX_PRIMARY_PANEL_WIDTH := 396.0

var data: PrototypeV2Data
var identity: String = "worker"
var open_panel: String = ""
var character_section: String = "summary"
var detail_person_id: String = ""
var person_detail_level: int = 0
var action_detail_id: String = ""
var selected_object: Dictionary = {}
var paused: bool = true
var speed: int = 1
var current_mode: String = "legal"
var mode_menu_open: bool = false
var review_mode: bool = false
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


func set_review_mode(enabled: bool) -> void:
	review_mode = enabled
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
		if ((_click_targets[index] as Dictionary).get("rect", Rect2()) as Rect2).has_point(position):
			return true
	return false


func close_top_layer() -> bool:
	if mode_menu_open:
		mode_menu_open = false
		queue_redraw()
		return true
	if not detail_person_id.is_empty():
		detail_person_id = ""
		person_detail_level = 0
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
	mode_menu_open = false
	detail_person_id = ""
	person_detail_level = 0
	action_detail_id = ""
	selected_object = {}
	selection_clear_requested.emit()
	panel_progress = 0.0 if animated else 1.0
	if animated:
		_panel_tween = create_tween()
		_panel_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_panel_tween.tween_property(self, "panel_progress", 1.0, 0.2)
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
	_panel_tween.tween_property(self, "panel_progress", 0.0, 0.16)
	_panel_tween.tween_callback(func() -> void:
		open_panel = ""
		queue_redraw()
	)


func set_identity(identity_id: String) -> void:
	if identity_id not in ["worker", "official"]:
		return
	identity = identity_id
	detail_person_id = ""
	person_detail_level = 0
	queue_redraw()


func set_mode_display(mode_id: String) -> void:
	current_mode = mode_id
	mode_menu_open = false
	queue_redraw()


func set_selected_object(value: Dictionary) -> void:
	selected_object = value.duplicate(true)
	open_panel = ""
	panel_progress = 0.0
	detail_person_id = ""
	person_detail_level = 0
	action_detail_id = ""
	queue_redraw()


func show_activity_toast() -> void:
	_show_toast("! 里尔食品价格上涨 · 点击右下角查看")


func apply_review_state(state_id: String) -> void:
	open_panel = ""
	panel_progress = 0.0
	detail_person_id = ""
	person_detail_level = 0
	action_detail_id = ""
	selected_object = {}
	character_section = "summary"
	identity = "worker"
	mode_menu_open = false
	match state_id:
		"worker_character", "sequence_06_character":
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
		"person_card", "sequence_05_person":
			detail_person_id = "jeanne"
			person_detail_level = 1
		"person_detail":
			detail_person_id = "jeanne"
			person_detail_level = 3
		"owned_organizations":
			open_panel = "character"
			character_section = "owned_orgs"
			panel_progress = 1.0
		"discover_organizations":
			open_panel = "character"
			character_section = "discover_orgs"
			panel_progress = 1.0
		"institution_official", "official_permissions", "sequence_07_official":
			identity = "official"
			open_panel = "country"
			panel_progress = 1.0
		"institution_worker", "worker_permissions":
			open_panel = "country"
			panel_progress = 1.0
		"world_activity", "sequence_08_activity":
			open_panel = "activity"
			panel_progress = 1.0
		"activity_toast":
			show_activity_toast()
		"time_panel":
			open_panel = "time"
			panel_progress = 1.0
		"mode_menu":
			mode_menu_open = true
		_:
			pass
	queue_redraw()


func debug_state() -> Dictionary:
	var country: Dictionary = _focus_country_data()
	return {
		"identity": identity,
		"open_panel": open_panel,
		"character_section": character_section,
		"detail_person_id": detail_person_id,
		"person_detail_level": person_detail_level,
		"selected_object": selected_object.duplicate(true),
		"paused": paused,
		"speed": speed,
		"character_corner_visible": open_panel != "character",
		"identity_switch_visible": review_mode,
		"mode_menu_open": mode_menu_open,
		"object_card_primary_actions": 1,
		"object_card_secondary_actions": 2,
		"activity_summary_items": 1,
		"institution_structure": "public_portal" if identity == "worker" else "department_hierarchy",
		"country_emblem_type": str(country.get("emblem_type", "")),
		"country_detail_name": str(country.get("formal_name_zh", "")),
		"country_visible_text": "%s %s %s" % [str(country.get("display_name_zh", "")), str(country.get("formal_name_zh", "")), str(country.get("native_name", ""))],
		"identity_fields_separated": true,
	}


func get_panel_rect() -> Rect2:
	match open_panel:
		"country":
			return Rect2(18.0, 98.0, MAX_PRIMARY_PANEL_WIDTH, 510.0)
		"time":
			return Rect2(970.0, 104.0, 292.0, 358.0)
		"character":
			return Rect2(18.0, 98.0, MAX_PRIMARY_PANEL_WIDTH, 516.0)
		"activity":
			return Rect2(866.0, 104.0, MAX_PRIMARY_PANEL_WIDTH, 500.0)
	return Rect2()


func _draw() -> void:
	_click_targets.clear()
	if data == null:
		_text(Vector2(28.0, 42.0), "原型静态数据尚未加载", 18, RED)
		return
	if review_mode:
		_draw_review_switch()
	if open_panel != "country":
		_draw_country_corner()
	if open_panel != "time":
		_draw_time_corner()
	if open_panel != "character":
		_draw_character_corner()
	if open_panel != "activity":
		_draw_activity_corner()
	_draw_mode_entry()
	if mode_menu_open:
		_draw_mode_menu()
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
		_draw_person_card()
	if not action_detail_id.is_empty():
		_draw_action_detail()
	if not _toast.is_empty():
		_draw_toast()
	if not _hover_tooltip.is_empty():
		_draw_tooltip()


func _draw_review_switch() -> void:
	_surface(REVIEW_SWITCH, Color(0.025, 0.055, 0.06, 0.9), Color(GOLD, 0.25), 17)
	_text(REVIEW_SWITCH.position + Vector2(14.0, 22.0), "评审身份", 10, INK_DIM)
	_compact_action(Rect2(574.0, 18.0, 82.0, 26.0), "普通工人", identity == "worker", "identity_worker", null, "仅在 --prototype-review 模式出现")
	_compact_action(Rect2(664.0, 18.0, 96.0, 26.0), "地方官员", identity == "official", "identity_official", null, "仅在 --prototype-review 模式出现")


func _draw_country_corner() -> void:
	_surface(COUNTRY_CORNER, PANEL, Color(GOLD, 0.18), 10)
	_register(COUNTRY_CORNER, "corner_country", null, "打开国家或所属机构")
	_draw_french_tricolor_emblem(Vector2(48.0, 51.0), 18.0)
	_text(Vector2(78.0, 42.0), "法兰西共和国", 17, INK)
	_text(Vector2(78.0, 63.0), "公开国家信息" if identity == "worker" else "北部省省政府", 11, GOLD if identity == "official" else INK_MUTED)
	_text(Vector2(264.0, 55.0), "›", 20, INK_DIM)


func _draw_french_tricolor_emblem(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("#f4f1e8"))
	_draw_vertical_circle_segment(center, radius, -radius, -radius / 3.0, Color("#244b8e"))
	_draw_vertical_circle_segment(center, radius, radius / 3.0, radius, Color("#c9424a"))
	draw_arc(center, radius, 0.0, TAU, 40, Color(GOLD, 0.72), 1.5, true)
	var rf_size: Vector2 = _font.get_string_size("RF", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8)
	draw_string(_font, center + Vector2(-rf_size.x * 0.5, rf_size.y * 0.35), "RF", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color("#243335"))


func _draw_vertical_circle_segment(center: Vector2, radius: float, left: float, right: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps: int = 8
	for index: int in range(steps + 1):
		var top_x: float = lerpf(left, right, float(index) / float(steps))
		points.append(center + Vector2(top_x, -sqrt(maxf(0.0, radius * radius - top_x * top_x))))
	for index: int in range(steps, -1, -1):
		var bottom_x: float = lerpf(left, right, float(index) / float(steps))
		points.append(center + Vector2(bottom_x, sqrt(maxf(0.0, radius * radius - bottom_x * bottom_x))))
	draw_colored_polygon(points, color)


func _draw_time_corner() -> void:
	_surface(TIME_CORNER, PANEL, Color(GOLD, 0.18), 10)
	_register(TIME_CORNER, "corner_time", null, "展开时间、自动暂停与系统工具")
	_text(TIME_CORNER.position + Vector2(16.0, 27.0), "1900年3月12日", 17, INK)
	_text(TIME_CORNER.position + Vector2(16.0, 49.0), "周一 · 14:00", 10, INK_MUTED)
	var state_label: String = "Ⅱ 暂停 · %d×" % speed if paused else "▶ 运行 · %d×" % speed
	_text(TIME_CORNER.position + Vector2(16.0, 66.0), state_label, 11, GOLD)
	_text(TIME_CORNER.end - Vector2(24.0, 22.0), "⌄", 16, INK_DIM)


func _draw_character_corner() -> void:
	_surface(CHARACTER_CORNER, PANEL, Color(GOLD, 0.18), 10)
	_register(CHARACTER_CORNER, "corner_character", null, "打开人物中心")
	_draw_avatar(CHARACTER_CORNER.position + Vector2(34.0, 36.0), 23.0)
	var person: Dictionary = _identity_data()
	_text(CHARACTER_CORNER.position + Vector2(70.0, 23.0), str(person.get("display_name_zh", "")), 16, INK)
	_text(CHARACTER_CORNER.position + Vector2(70.0, 41.0), str(person.get("native_name", "")), 9, INK_MUTED)
	_text(CHARACTER_CORNER.position + Vector2(70.0, 60.0), str(person.get("occupation", "")), 11, GOLD)
	_text(CHARACTER_CORNER.end - Vector2(22.0, 30.0), "›", 20, INK_DIM)


func _draw_activity_corner() -> void:
	_surface(ACTIVITY_CORNER, PANEL, Color(AMBER, 0.2), 10)
	_register(ACTIVITY_CORNER, "corner_activity", null, "展开通知、事件与新闻历史")
	var summary: Dictionary = data.get_document("activity").get("default_summary", {}) as Dictionary
	var latest: Dictionary = _activity_by_id(str(summary.get("latest_id", "")))
	_text(ACTIVITY_CORNER.position + Vector2(14.0, 21.0), "! 重要通知", 11, AMBER)
	_text(ACTIVITY_CORNER.position + Vector2(14.0, 43.0), str(latest.get("title", "")), 13, INK)
	_text(ACTIVITY_CORNER.position + Vector2(14.0, 63.0), "%s · 未读 %d" % [str(latest.get("time", "")), int(summary.get("unread_count", 0))], 10, INK_MUTED)
	_text(ACTIVITY_CORNER.end - Vector2(24.0, 29.0), "↑", 15, GOLD)


func _draw_mode_entry() -> void:
	_surface(MODE_ENTRY, Color(0.025, 0.055, 0.06, 0.9), Color(GOLD, 0.2), 14)
	var mode: Dictionary = _mode_by_id(current_mode)
	_text(MODE_ENTRY.position + Vector2(14.0, 19.0), "%s  %s" % [str(mode.get("icon", "◇")), str(mode.get("label", "地图模式"))], 11, INK)
	_text(MODE_ENTRY.end - Vector2(24.0, 9.0), "⌃" if mode_menu_open else "⌄", 12, INK_MUTED)
	_register(MODE_ENTRY, "toggle_mode_menu", null, str(mode.get("description", "")))


func _draw_mode_menu() -> void:
	var rect := Rect2(538.0, 512.0, 204.0, 154.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 10)
	_text(rect.position + Vector2(14.0, 22.0), "地图覆盖层", 12, INK_MUTED)
	var modes: Array = data.get_document("map_modes").get("modes", []) as Array
	for index: int in range(modes.size()):
		var mode: Dictionary = modes[index] as Dictionary
		var row := Rect2(rect.position.x + 8.0, rect.position.y + 32.0 + float(index) * 28.0, rect.size.x - 16.0, 25.0)
		if str(mode.get("id", "")) == current_mode:
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), GOLD)
		_text(row.position + Vector2(12.0, 17.0), "%s  %s" % [str(mode.get("icon", "")), str(mode.get("label", ""))], 11, INK if str(mode.get("id", "")) == current_mode else INK_MUTED)
		_register(row, "mode", str(mode.get("id", "")), str(mode.get("description", "")))


func _draw_country_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(-32.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_close_control(rect)
	if identity == "worker":
		_draw_worker_country_view(rect)
	else:
		_draw_official_institution_view(rect)


func _draw_worker_country_view(rect: Rect2) -> void:
	_text(rect.position + Vector2(20.0, 34.0), "法兰西第三共和国", 22, INK)
	_text(rect.position + Vector2(20.0, 56.0), "République française", 10, INK_MUTED)
	_text(rect.position + Vector2(20.0, 74.0), "公开入口 · 信息精度受公开渠道限制", 10, BLUE)
	_section_heading(rect.position + Vector2(20.0, 94.0), "本地政策")
	_text(rect.position + Vector2(20.0, 119.0), "北部省劳动监察处发布安全检查公告", 12, INK)
	_text(rect.position + Vector2(20.0, 138.0), "✓ 静态条目 · 可查看公开摘要与投诉渠道", 10, INK_MUTED)
	_divider(rect.position + Vector2(20.0, 160.0), rect.size.x - 40.0)
	_section_heading(rect.position + Vector2(20.0, 190.0), "公开新闻")
	_text(rect.position + Vector2(20.0, 215.0), "《里尔公报》：巴黎—里尔铁路出现延误", 11, INK)
	_text(rect.position + Vector2(20.0, 235.0), "来源：公开报道 · 今日", 10, INK_DIM)
	_divider(rect.position + Vector2(20.0, 258.0), rect.size.x - 40.0)
	_section_heading(rect.position + Vector2(20.0, 288.0), "可接触组织")
	_text(rect.position + Vector2(20.0, 314.0), "北部省劳动监察处", 13, INK)
	_text(rect.position + Vector2(20.0, 334.0), "公开公告与投诉窗口", 10, INK_MUTED)
	_text(rect.position + Vector2(20.0, 365.0), "里尔市政厅", 13, INK)
	_text(rect.position + Vector2(20.0, 385.0), "办事程序与地区公告", 10, INK_MUTED)
	_text(rect.position + Vector2(20.0, 414.0), "现代 Natural Earth 边界仅用于本原型的 UI 与缩放验证", 9, INK_DIM)
	_text(rect.position + Vector2(20.0, 430.0), "中央预算、内部层级与未公开议程不会显示", 9, INK_DIM)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 48.0, 140.0, 30.0), "查看本地政策", "context_action", "查看本地政策", "公开信息入口")
	_text_link(Rect2(rect.position.x + 176.0, rect.end.y - 46.0, 92.0, 28.0), "公开新闻", "context_action", "公开新闻", "打开公开新闻")
	_more_action(Rect2(rect.end.x - 54.0, rect.end.y - 46.0, 34.0, 28.0), "国家入口更多信息")


func _draw_official_institution_view(rect: Rect2) -> void:
	_text(rect.position + Vector2(20.0, 34.0), "北部省省政府", 22, INK)
	_text(rect.position + Vector2(20.0, 55.0), "Préfecture du Nord", 10, INK_MUTED)
	_text(rect.position + Vector2(20.0, 73.0), "公共工程处事务员 · 省级行政视角", 10, GOLD)
	_section_heading(rect.position + Vector2(20.0, 88.0), "机构结构")
	var center_x: float = rect.position.x + rect.size.x * 0.5
	_text(Vector2(center_x - 43.0, rect.position.y + 112.0), "北部省省长", 11, INK_MUTED)
	draw_line(Vector2(center_x, rect.position.y + 120.0), Vector2(center_x, rect.position.y + 145.0), LINE, 1.5)
	_surface(Rect2(center_x - 76.0, rect.position.y + 145.0, 152.0, 42.0), Color(GOLD, 0.12), Color(GOLD, 0.3), 7)
	_text(Vector2(center_x - 49.0, rect.position.y + 171.0), "公共工程处", 14, INK)
	draw_line(Vector2(center_x, rect.position.y + 187.0), Vector2(center_x, rect.position.y + 205.0), LINE, 1.5)
	draw_line(Vector2(center_x - 122.0, rect.position.y + 205.0), Vector2(center_x + 122.0, rect.position.y + 205.0), LINE, 1.0)
	_text(Vector2(center_x - 148.0, rect.position.y + 226.0), "里尔区公署", 10, INK_MUTED)
	_text(Vector2(center_x - 43.0, rect.position.y + 226.0), "里尔市政厅", 10, INK_MUTED)
	_text(Vector2(center_x + 64.0, rect.position.y + 226.0), "劳动监察处", 10, INK_MUTED)
	_divider(rect.position + Vector2(20.0, 246.0), rect.size.x - 40.0)
	_text(rect.position + Vector2(20.0, 270.0), "管辖", 10, INK_DIM)
	_text(rect.position + Vector2(86.0, 270.0), "北部省（département）", 12, INK)
	_text(rect.position + Vector2(20.0, 294.0), "预算来源", 10, INK_DIM)
	_text(rect.position + Vector2(86.0, 294.0), "北部省预算拨款 · 本处执行额 68%", 11, INK)
	_section_heading(rect.position + Vector2(20.0, 329.0), "当前议程")
	_text(rect.position + Vector2(20.0, 355.0), "! 协调巴黎—里尔铁路运输延误", 12, AMBER)
	_text(rect.position + Vector2(20.0, 381.0), "可执行程序", 10, INK_DIM)
	_text(rect.position + Vector2(88.0, 381.0), "处内提交 · 跨单位会签 · 执行复核", 11, INK)
	_text(rect.position + Vector2(20.0, 415.0), "🔒 中央铁路投资排序 · 已知但无权处理", 10, AMBER)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 48.0, 142.0, 30.0), "处理当前议程", "context_action", "处理当前议程", "仅限当前职位与辖区")
	_text_link(Rect2(rect.position.x + 178.0, rect.end.y - 46.0, 96.0, 28.0), "查看程序", "context_action", "查看程序", "查看法定程序")
	_more_action(Rect2(rect.end.x - 54.0, rect.end.y - 46.0, 34.0, 28.0), "机构更多信息")


func _draw_time_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(0.0, -24.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(18.0, 34.0), "1900年3月12日", 22, INK)
	_text(rect.position + Vector2(18.0, 58.0), "周一 · 14:00", 11, INK_MUTED)
	_primary_action(Rect2(rect.position.x + 18.0, rect.position.y + 78.0, 104.0, 32.0), "▶ 继续" if paused else "Ⅱ 暂停", "toggle_pause", null, "只切换原型视觉状态")
	_text(rect.position + Vector2(18.0, 139.0), "当前速度", 10, INK_DIM)
	for index: int in range(4):
		var option: int = [1, 2, 4, 8][index]
		_compact_action(Rect2(rect.position.x + 18.0 + float(index) * 56.0, rect.position.y + 151.0, 48.0, 25.0), "%d×" % option, speed == option, "speed", option, "不推进正式世界时间")
	_section_heading(rect.position + Vector2(18.0, 211.0), "自动暂停")
	_check_row(rect.position + Vector2(18.0, 226.0), "玩家事件需要决定")
	_check_row(rect.position + Vector2(18.0, 250.0), "人物健康出现危险")
	_check_row(rect.position + Vector2(18.0, 274.0), "战争开始或结束")
	_divider(rect.position + Vector2(18.0, 299.0), rect.size.x - 36.0)
	_text(rect.position + Vector2(18.0, 325.0), "系统工具", 10, INK_DIM)
	_text_link(Rect2(rect.position.x + 18.0, rect.position.y + 330.0, 55.0, 24.0), "保存", "system_save", null, "原型不会写入存档")
	_text_link(Rect2(rect.position.x + 86.0, rect.position.y + 330.0, 55.0, 24.0), "设置", "system_settings", null, "静态占位")
	_text_link(Rect2(rect.position.x + 154.0, rect.position.y + 330.0, 72.0, 24.0), "返回菜单", "system_return", null, "独立原型不连接正式菜单")


func _draw_character_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(-32.0, 18.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_close_control(rect)
	var person: Dictionary = _identity_data()
	_draw_avatar(rect.position + Vector2(42.0, 42.0), 25.0)
	_text(rect.position + Vector2(80.0, 31.0), str(person.get("display_name_zh", "")), 20, INK)
	_text(rect.position + Vector2(80.0, 50.0), str(person.get("native_name", "")), 10, INK_MUTED)
	_text(rect.position + Vector2(80.0, 70.0), "职业：%s" % str(person.get("occupation", "")), 10, GOLD)
	var nav_rect := Rect2(rect.position.x + 14.0, rect.position.y + 96.0, 92.0, rect.size.y - 114.0)
	_draw_character_navigation(nav_rect)
	var body := Rect2(rect.position.x + 118.0, rect.position.y + 96.0, rect.size.x - 136.0, rect.size.y - 114.0)
	match character_section:
		"summary":
			_draw_character_summary(body, person)
		"life_work":
			_draw_life_work(body, person)
		"relationships":
			_draw_relationships(body)
		"owned_orgs":
			_draw_organizations(body, true)
		"discover_orgs":
			_draw_organizations(body, false)


func _draw_character_navigation(rect: Rect2) -> void:
	var items: Array = [
		["summary", "概览"], ["life_work", "生活与工作"], ["relationships", "关系人物"],
		["owned_orgs", "我的组织"], ["discover_orgs", "探索组织"],
	]
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(rect.position.x, rect.position.y + float(index) * 45.0, rect.size.x, 34.0)
		if character_section == str(item[0]):
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), GOLD)
		_text(row.position + Vector2(12.0, 22.0), str(item[1]), 11, INK if character_section == str(item[0]) else INK_MUTED)
		_register(row, "character_section", str(item[0]), "人物中心内切换信息层，不叠加模块窗口")


func _draw_character_summary(rect: Rect2, person: Dictionary) -> void:
	_section_heading(rect.position + Vector2(0.0, 15.0), "当前状态")
	_text(rect.position + Vector2(0.0, 45.0), str(person.get("health", "")), 12, GREEN)
	_text(rect.position + Vector2(82.0, 45.0), str(person.get("fatigue", "")), 12, AMBER)
	_text(rect.position + Vector2(168.0, 45.0), str(person.get("stress", "")), 12, BLUE if identity == "worker" else AMBER)
	_divider(rect.position + Vector2(0.0, 62.0), rect.size.x)
	_text(rect.position + Vector2(0.0, 86.0), "职业", 10, INK_DIM)
	_text(rect.position + Vector2(62.0, 86.0), str(person.get("occupation", "")), 11, INK)
	_text(rect.position + Vector2(0.0, 112.0), "雇主" if identity == "worker" else "所属机构", 10, INK_DIM)
	_text(rect.position + Vector2(62.0, 112.0), str(person.get("employer", "")) if identity == "worker" else str(person.get("institution", "")), 11, INK)
	_text(rect.position + Vector2(0.0, 138.0), "工会职位" if identity == "worker" else "机构职位", 10, INK_DIM)
	_text(rect.position + Vector2(62.0, 138.0), str(person.get("union_position", "")) if identity == "worker" else str(person.get("institution_position", "")), 11, GOLD)
	_status_line(rect.position + Vector2(0.0, 169.0), "当前工作", str(person.get("current_work", "")), INK)
	_status_line(rect.position + Vector2(0.0, 211.0), "主要问题", str(person.get("primary_concern", "")), AMBER)
	_status_line(rect.position + Vector2(0.0, 253.0), "主要计划", str(person.get("plan", "")), GREEN)
	_primary_action(Rect2(rect.position.x, rect.end.y - 38.0, 118.0, 30.0), "查看当前计划", "action_detail", str(person.get("plan", "")), "进入第三层详情")
	_more_action(Rect2(rect.position.x + 130.0, rect.end.y - 38.0, 34.0, 30.0), "人物更多信息")


func _draw_life_work(rect: Rect2, person: Dictionary) -> void:
	if identity == "worker":
		_section_heading(rect.position + Vector2(0.0, 15.0), "生活")
		_text(rect.position + Vector2(0.0, 43.0), str(person.get("household", "")), 12, INK)
		_text(rect.position + Vector2(0.0, 65.0), "现金 %s · 本月 %s" % [str(person.get("cash", "")), str(person.get("monthly_balance", ""))], 10, INK_MUTED)
		_section_heading(rect.position + Vector2(0.0, 98.0), "工作与组织")
		_text(rect.position + Vector2(0.0, 126.0), "职业", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 126.0), str(person.get("occupation", "")), 11, INK)
		_text(rect.position + Vector2(0.0, 151.0), "雇主", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 151.0), str(person.get("employer", "")), 11, INK)
		_text(rect.position + Vector2(0.0, 176.0), "工会", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 176.0), str(person.get("union", "")), 11, GOLD)
		_text(rect.position + Vector2(0.0, 201.0), "工会职位", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 201.0), str(person.get("union_position", "")), 11, GOLD)
		_text(rect.position + Vector2(0.0, 226.0), "夜校", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 226.0), str(person.get("school", "")), 11, INK)
		_text(rect.position + Vector2(0.0, 259.0), str(person.get("work_contract", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(0.0, 282.0), "! 疲劳偏高可能影响夜校计划", 10, AMBER)
	else:
		_section_heading(rect.position + Vector2(0.0, 15.0), "个人与任职")
		_status_line(rect.position + Vector2(0.0, 42.0), "职业", str(person.get("occupation", "")), INK)
		_status_line(rect.position + Vector2(0.0, 80.0), "机构职位", str(person.get("institution_position", "")), GOLD)
		_status_line(rect.position + Vector2(0.0, 118.0), "所属机构", str(person.get("institution", "")), INK)
		_status_line(rect.position + Vector2(0.0, 156.0), "管辖范围", str(person.get("jurisdiction", "")), GOLD)
		_status_line(rect.position + Vector2(0.0, 194.0), "权限来源", str(person.get("authority_source", "")), INK_MUTED)
		_status_line(rect.position + Vector2(0.0, 232.0), "预算来源", str(person.get("budget_source", "")), INK_MUTED)
		_text(rect.position + Vector2(0.0, 285.0), str(person.get("upstream_locked", "")), 9, AMBER)


func _draw_relationships(rect: Rect2) -> void:
	_section_heading(rect.position + Vector2(0.0, 15.0), "有限关系人物")
	var relationships: Array = data.get_document("relationships").get("relationships", []) as Array
	for index: int in range(mini(relationships.size(), 4)):
		var relation: Dictionary = relationships[index] as Dictionary
		var row := Rect2(rect.position.x, rect.position.y + 29.0 + float(index) * 76.0, rect.size.x, 66.0)
		if index > 0:
			_divider(row.position - Vector2(0.0, 7.0), row.size.x)
		_text(row.position + Vector2(0.0, 18.0), str(relation.get("name", "")), 13, INK)
		_text(row.position + Vector2(0.0, 36.0), str(relation.get("occupation", "")), 10, INK_MUTED)
		_text(row.position + Vector2(0.0, 54.0), "%s · %s" % [str(relation.get("relation", "")), str(relation.get("last_interaction", ""))], 9, GOLD)
		_register(row, "person_card", str(relation.get("id", "")), "点击人物进入对象卡")


func _draw_organizations(rect: Rect2, owned: bool) -> void:
	_section_heading(rect.position + Vector2(0.0, 15.0), "我的组织" if owned else "探索组织")
	_text(rect.position + Vector2(0.0, 35.0), "已加入的具体职位与项目" if owned else "只显示当前已知并可解释来源的组织", 9, INK_DIM)
	var identity_records: Dictionary = _organization_identity_data()
	var organizations: Array = identity_records.get("owned" if owned else "discover", []) as Array
	for index: int in range(mini(organizations.size(), 2 if owned else 3)):
		var organization: Dictionary = _organization_record(organizations[index] as Dictionary)
		var height: float = 154.0 if owned else 100.0
		var row := Rect2(rect.position.x, rect.position.y + 52.0 + float(index) * (height + 8.0), rect.size.x, height)
		_draw_organization_entry(row, organization, owned)


func _draw_organization_entry(rect: Rect2, organization: Dictionary, owned: bool) -> void:
	draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), GOLD if owned else BLUE)
	_text(rect.position + Vector2(12.0, 20.0), "%s  %s" % [str(organization.get("emblem", "○")), str(organization.get("name", ""))], 13, INK)
	if owned:
		_text(rect.position + Vector2(12.0, 41.0), "职位  %s" % str(organization.get("position", "")), 10, GOLD)
		_text(rect.position + Vector2(12.0, 59.0), "部门  %s" % str(organization.get("department", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(12.0, 77.0), "项目  %s" % str(organization.get("project", "")), 10, GREEN)
		_text(rect.position + Vector2(12.0, 95.0), "上级  %s" % str(organization.get("supervisor", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(12.0, 113.0), "权限  %s" % str(organization.get("authority", "")), 9, INK_MUTED)
		_text_link(Rect2(rect.position.x + 12.0, rect.end.y - 27.0, 104.0, 23.0), "查看组织事务", "organization_action", "查看组织事务", "主要动作")
		_text_link(Rect2(rect.position.x + 128.0, rect.end.y - 27.0, 100.0, 23.0), "参与当前项目", "organization_action", "参与当前项目", "次要动作")
	else:
		_text(rect.position + Vector2(12.0, 41.0), "%s · %s" % [str(organization.get("type", "")), str(organization.get("match", ""))], 9, INK_MUTED)
		_text(rect.position + Vector2(12.0, 61.0), "得知来源：%s" % str(organization.get("contact_source", "")), 10, BLUE)
		_text(rect.position + Vector2(12.0, 81.0), str(organization.get("access", "")), 9, INK_MUTED)
		_register(rect, "organization_action", str(organization.get("primary_action", "")), "点击查看组织对象卡")


func _draw_activity_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 18.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 35.0), "世界动态", 22, INK)
	_text(rect.position + Vector2(20.0, 58.0), "通知即时提醒 · 事件可操作 · 新闻来自公开渠道", 10, INK_MUTED)
	var items: Array = data.get_document("activity").get("items", []) as Array
	var y: float = rect.position.y + 86.0
	var last_kind: String = ""
	for item_variant: Variant in items:
		var item: Dictionary = item_variant as Dictionary
		var kind: String = str(item.get("kind", "notification"))
		if kind != last_kind:
			_text(Vector2(rect.position.x + 20.0, y), _activity_kind_label(kind), 11, _activity_kind_color(kind))
			y += 22.0
			last_kind = kind
		var item_rect := Rect2(rect.position.x + 20.0, y, rect.size.x - 40.0, 54.0)
		_text(item_rect.position + Vector2(0.0, 17.0), str(item.get("title", "")), 12, INK)
		var group_count: int = int(item.get("group_count", 1))
		_text(item_rect.position + Vector2(0.0, 35.0), "%s%s" % [str(item.get("detail", "")), " · 聚合 %d 条" % group_count if group_count > 1 else ""], 9, INK_MUTED)
		_text(item_rect.position + Vector2(0.0, 50.0), "%s · %s" % [str(item.get("time", "")), str(item.get("source", ""))], 9, INK_DIM)
		_register(item_rect, "activity_item", item.get("object_id"), "点击定位关联对象")
		y += 58.0
		if y > rect.end.y - 32.0:
			break


func _draw_object_card() -> void:
	var object_type: String = str(selected_object.get("type", ""))
	var object_data: Dictionary = selected_object.get("data", {}) as Dictionary
	var rect := Rect2(756.0, 176.0, 366.0, 258.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.34), 12)
	_register(rect, "consume")
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "object_close", "关闭对象卡")
	var type_label: String = _object_type_label(object_type)
	_text(rect.position + Vector2(20.0, 28.0), type_label, 10, BLUE)
	_text(rect.position + Vector2(20.0, 57.0), _object_display_name(object_type, object_data), 21, INK)
	_text(rect.position + Vector2(20.0, 80.0), _object_hierarchy(object_type, object_data), 10, INK_MUTED)
	_divider(rect.position + Vector2(20.0, 96.0), rect.size.x - 40.0)
	_draw_object_summary(rect, object_type, object_data)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 47.0, 126.0, 30.0), _object_primary_action(object_type), "object_action", object_type, "对象上下文主要动作")
	_text_link(Rect2(rect.position.x + 162.0, rect.end.y - 45.0, 98.0, 28.0), _object_secondary_action(object_type), "object_action", object_type, "对象上下文次要动作")
	_more_action(Rect2(rect.end.x - 54.0, rect.end.y - 45.0, 34.0, 28.0), "更多对象操作")


func _draw_object_summary(rect: Rect2, object_type: String, object_data: Dictionary) -> void:
	match object_type:
		"country":
			_text(rect.position + Vector2(20.0, 121.0), str(object_data.get("native_name", "")), 11, INK)
			_text(rect.position + Vector2(20.0, 143.0), "%s · %s" % [str(object_data.get("government_name", "")), str(object_data.get("diplomacy", "和平"))], 10, GREEN)
			_text(rect.position + Vector2(20.0, 164.0), "现代 Natural Earth 边界 · 1900 年主题占位", 9, INK_DIM)
		"region":
			_text(rect.position + Vector2(20.0, 123.0), "人口  %s" % str(object_data.get("population", "")), 11, INK)
			_text(rect.position + Vector2(20.0, 146.0), "观察  %s · %s" % [str(object_data.get("market", "")), str(object_data.get("market_state", ""))], 10, AMBER)
			_text(rect.position + Vector2(20.0, 166.0), "游戏宏观地区，不等同于历史行政区划。", 9, INK_DIM)
		"city":
			_text(rect.position + Vector2(20.0, 123.0), "主要城市节点 · 地方交通入口", 11, INK)
			_text(rect.position + Vector2(20.0, 148.0), "缩放到近景可见机构与组织", 10, INK_MUTED)
		"port":
			_text(rect.position + Vector2(20.0, 123.0), "港口节点 · 航运路线使用蓝色长虚线", 11, BLUE)
		"institution":
			var view_key: String = "worker_view" if identity == "worker" else "official_view"
			var view: Dictionary = object_data.get(view_key, {}) as Dictionary
			_text(rect.position + Vector2(20.0, 123.0), str(view.get("summary", "")), 11, INK)
			_text(rect.position + Vector2(20.0, 146.0), "层级：%s · 管辖：%s" % [str(object_data.get("administrative_level", "")), str(object_data.get("jurisdiction", ""))], 10, GOLD)
			_text(rect.position + Vector2(20.0, 166.0), "信息精度：%s" % str(view.get("precision", "")), 9, INK_MUTED)
		"organization":
			_text(rect.position + Vector2(20.0, 123.0), "%s · %s" % [str(object_data.get("position", "")), str(object_data.get("department", ""))], 11, GOLD)
			_text(rect.position + Vector2(20.0, 148.0), "项目：%s" % str(object_data.get("project", "")), 10, GREEN)


func _draw_person_card() -> void:
	var relation: Dictionary = _relationship_by_id(detail_person_id)
	if relation.is_empty():
		return
	if person_detail_level == 1:
		_draw_person_first_layer(relation)
	else:
		_draw_person_third_layer(relation)


func _draw_person_first_layer(relation: Dictionary) -> void:
	var rect := Rect2(748.0, 198.0, 360.0, 238.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.34), 12)
	_register(rect, "consume")
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "close_person_detail", "关闭人物卡")
	_draw_avatar(rect.position + Vector2(43.0, 49.0), 24.0)
	_text(rect.position + Vector2(82.0, 38.0), str(relation.get("display_name_zh", "")), 20, INK)
	_text(rect.position + Vector2(82.0, 56.0), str(relation.get("native_name", "")), 9, INK_MUTED)
	_text(rect.position + Vector2(82.0, 74.0), "%s · %s" % [str(relation.get("occupation", "")), str(relation.get("region", ""))], 9, GOLD)
	_text(rect.position + Vector2(20.0, 110.0), str(relation.get("relation", "")), 13, INK)
	_text(rect.position + Vector2(20.0, 133.0), "最近互动  %s" % str(relation.get("last_interaction", "")), 10, INK_MUTED)
	_text(rect.position + Vector2(20.0, 155.0), str(relation.get("status", "")), 10, INK_MUTED)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 46.0, 104.0, 30.0), "联系", "person_action", "联系", "主要动作")
	_text_link(Rect2(rect.position.x + 140.0, rect.end.y - 44.0, 92.0, 28.0), "请求帮助", "person_action", "请求帮助", "次要动作；条件不足时会提示")
	_more_action(Rect2(rect.position.x + 248.0, rect.end.y - 44.0, 34.0, 28.0), "引荐、调查、共同关系")
	_text_link(Rect2(rect.end.x - 68.0, rect.end.y - 44.0, 52.0, 28.0), "详情", "person_full_detail", detail_person_id, "进入第三层完整结构")


func _draw_person_third_layer(relation: Dictionary) -> void:
	var rect := Rect2(700.0, 142.0, 396.0, 414.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.38), 12)
	_register(rect, "consume")
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "close_person_detail", "关闭人物详情")
	_draw_avatar(rect.position + Vector2(45.0, 48.0), 25.0)
	_text(rect.position + Vector2(84.0, 35.0), str(relation.get("display_name_zh", "")), 21, INK)
	_text(rect.position + Vector2(84.0, 54.0), str(relation.get("native_name", "")), 9, INK_MUTED)
	_text(rect.position + Vector2(84.0, 72.0), "%s · %s" % [str(relation.get("occupation", "")), str(relation.get("region", ""))], 10, GOLD)
	_section_heading(rect.position + Vector2(20.0, 101.0), "关系结构")
	var rows: Array = [
		["关系", relation.get("relation", "")], ["最近互动", relation.get("last_interaction", "")],
		["公开状态", relation.get("status", "")], ["接触方式", relation.get("contact", "")],
		["共同关系", relation.get("common", "")],
	]
	for index: int in range(rows.size()):
		var row: Array = rows[index] as Array
		var y: float = rect.position.y + 132.0 + float(index) * 38.0
		_text(Vector2(rect.position.x + 20.0, y), str(row[0]), 10, INK_DIM)
		_text(Vector2(rect.position.x + 108.0, y), str(row[1]), 11, INK)
		_divider(Vector2(rect.position.x + 20.0, y + 10.0), rect.size.x - 40.0)
	_text(rect.position + Vector2(20.0, 344.0), "更多入口：引荐 · 调查 · 查看共同关系", 10, INK_MUTED)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 46.0, 104.0, 30.0), "联系", "person_action", "联系", "主要动作")
	_text_link(Rect2(rect.position.x + 140.0, rect.end.y - 44.0, 92.0, 28.0), "请求帮助", "person_action", "请求帮助", "次要动作")
	_more_action(Rect2(rect.end.x - 54.0, rect.end.y - 44.0, 34.0, 28.0), "引荐、调查、共同关系")


func _draw_action_detail() -> void:
	var rect := Rect2(720.0, 216.0, 360.0, 260.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.42), 12)
	_register(rect, "consume")
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "close_action_detail", "关闭详情")
	_text(rect.position + Vector2(20.0, 34.0), action_detail_id, 20, INK)
	_text(rect.position + Vector2(20.0, 61.0), "★ 保证成功", 12, GOLD)
	_text(rect.position + Vector2(20.0, 86.0), "有效值 72 · 成功线 45 · 保证线 65", 11, INK_MUTED)
	_divider(rect.position + Vector2(20.0, 102.0), rect.size.x - 40.0)
	var rows: Array = [["能力", "+17"], ["准备", "+21"], ["资金", "+20"], ["关系支持", "+8"], ["目标阻力", "−12"]]
	for index: int in range(rows.size()):
		var row: Array = rows[index] as Array
		var y: float = rect.position.y + 130.0 + float(index) * 25.0
		_text(Vector2(rect.position.x + 28.0, y), str(row[0]), 11, INK)
		_text(Vector2(rect.end.x - 62.0, y), str(row[1]), 11, GREEN if str(row[1]).begins_with("+") else RED)


func _draw_toast() -> void:
	var width: float = minf(480.0, _font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x + 38.0)
	var rect := Rect2((size.x - width) * 0.5, 618.0, width, 36.0)
	_surface(rect, Color(0.025, 0.055, 0.06, 0.97), Color(AMBER, 0.42), 18)
	_text(rect.position + Vector2(19.0, 23.0), _toast, 12, INK)


func _draw_tooltip() -> void:
	var width: float = clampf(_font.get_string_size(_hover_tooltip, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x + 28.0, 180.0, 460.0)
	var position: Vector2 = _hover_position + Vector2(16.0, 18.0)
	position.x = minf(position.x, size.x - width - 12.0)
	position.y = minf(position.y, size.y - 50.0)
	var rect := Rect2(position, Vector2(width, 34.0))
	_surface(rect, Color(0.018, 0.04, 0.045, 0.99), Color(GOLD, 0.32), 7)
	_text(rect.position + Vector2(14.0, 22.0), _hover_tooltip, 11, INK)


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
		"toggle_mode_menu":
			mode_menu_open = not mode_menu_open
			queue_redraw()
		"mode":
			current_mode = str(payload)
			mode_menu_open = false
			mode_requested.emit(str(payload))
		"panel_close":
			close_panel()
		"object_close":
			selected_object = {}
			selection_clear_requested.emit()
			queue_redraw()
		"character_section":
			character_section = str(payload)
			queue_redraw()
		"person_card":
			detail_person_id = str(payload)
			person_detail_level = 1
			queue_redraw()
		"person_full_detail":
			detail_person_id = str(payload)
			person_detail_level = 3
			queue_redraw()
		"close_person_detail":
			detail_person_id = ""
			person_detail_level = 0
			queue_redraw()
		"action_detail":
			action_detail_id = str(payload)
			queue_redraw()
		"close_action_detail":
			action_detail_id = ""
			queue_redraw()
		"toggle_pause":
			paused = not paused
			_show_toast("原型时间已%s · 未推进正式世界" % ("暂停" if paused else "继续"))
		"speed":
			speed = int(payload)
			queue_redraw()
		"system_save":
			_show_toast("保存仅为视觉占位 · 原型不写入 user://")
		"system_settings":
			_show_toast("设置入口为静态占位")
		"system_return":
			_show_toast("独立原型不连接正式菜单")
		"person_action", "organization_action", "context_action", "object_action", "activity_item", "more":
			_show_toast("%s · 静态上下文入口" % str(payload if payload != null else "更多"))
		_:
			pass


func _identity_data() -> Dictionary:
	var identities: Dictionary = data.get_document("characters").get("identities", {}) as Dictionary
	return _dictionary_value(identities, identity)


func _focus_country_data() -> Dictionary:
	for country_variant: Variant in data.get_document("countries").get("countries", []):
		var country: Dictionary = country_variant as Dictionary
		if str(country.get("stable_id", "")) == "country_fra":
			return country
	return {}


func _organization_identity_data() -> Dictionary:
	var identities: Dictionary = data.get_document("organizations").get("identities", {}) as Dictionary
	return _dictionary_value(identities, identity)


func _organization_record(context: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var organization_id: String = str(context.get("organization_id", context.get("id", "")))
	for record_variant: Variant in data.get_document("organizations").get("catalog", []):
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("id", "")) == organization_id:
			result = record.duplicate(true)
			break
	result.merge(context, true)
	return result


func _relationship_by_id(person_id: String) -> Dictionary:
	for relation_variant: Variant in data.get_document("relationships").get("relationships", []):
		var relation: Dictionary = relation_variant as Dictionary
		if str(relation.get("id", "")) == person_id:
			return relation
	return {}


func _activity_by_id(activity_id: String) -> Dictionary:
	for item_variant: Variant in data.get_document("activity").get("items", []):
		var item: Dictionary = item_variant as Dictionary
		if str(item.get("id", "")) == activity_id:
			return item
	return {}


func _mode_by_id(mode_id: String) -> Dictionary:
	for mode_variant: Variant in data.get_document("map_modes").get("modes", []):
		var mode: Dictionary = mode_variant as Dictionary
		if str(mode.get("id", "")) == mode_id:
			return mode
	return {}


func _object_display_name(object_type: String, object_data: Dictionary) -> String:
	if object_type == "country":
		return str(object_data.get("formal_name_zh", object_data.get("display_name_zh", object_data.get("name", "未命名国家"))))
	return str(object_data.get("name", "未命名对象"))


func _object_hierarchy(object_type: String, object_data: Dictionary) -> String:
	match object_type:
		"country":
			return "世界 › 国家"
		"region":
			return "法兰西第三共和国 › 游戏宏观地区"
		"city":
			if str(object_data.get("id", "")) == "lille":
				return "法兰西第三共和国 › 北部省 › 里尔区 › 里尔市"
			return "法兰西第三共和国 › %s › 城市" % _region_name(str(object_data.get("parent_region_id", "")))
		"port":
			return "法兰西第三共和国 › %s › 港口" % _region_name(str(object_data.get("parent_region_id", "")))
		"institution":
			return "法兰西第三共和国 › %s › %s" % [str(object_data.get("jurisdiction", "地方辖区")), str(object_data.get("administrative_level", "机构"))]
		"organization":
			return "人物关系 › 已加入组织"
	return "地理对象"


func _region_name(region_id: String) -> String:
	for region_variant: Variant in data.get_document("regions").get("regions", []):
		var region: Dictionary = region_variant as Dictionary
		if str(region.get("id", "")) == region_id:
			return str(region.get("name", "地区"))
	return "地区"


func _object_type_label(object_type: String) -> String:
	var labels: Dictionary = {"country":"国家","region":"宏观地区","city":"城市","port":"港口","institution":"机构","organization":"组织"}
	return str(labels.get(object_type, "对象"))


func _object_primary_action(object_type: String) -> String:
	var labels: Dictionary = {"country":"查看国家","region":"查看地区","city":"查看城市","port":"查看船期","institution":"查看机构","organization":"组织事务"}
	return str(labels.get(object_type, "查看对象"))


func _object_secondary_action(object_type: String) -> String:
	return "查看交通" if object_type in ["region", "city", "port"] else "公开信息"


func _activity_kind_label(kind: String) -> String:
	var labels: Dictionary = {"notification":"通知","event":"事件","news":"新闻"}
	return str(labels.get(kind, "动态"))


func _activity_kind_color(kind: String) -> Color:
	if kind == "notification":
		return AMBER
	if kind == "event":
		return GREEN
	return BLUE


func _status_line(position: Vector2, label: String, value: String, color: Color) -> void:
	_text(position, label, 10, INK_DIM)
	_text(position + Vector2(0.0, 20.0), value, 11, color)


func _show_toast(message: String) -> void:
	_toast = message
	_toast_until_msec = Time.get_ticks_msec() + 2600
	queue_redraw()


func _animated_rect(target: Rect2, offset: Vector2) -> Rect2:
	return Rect2(target.position + offset * (1.0 - panel_progress), target.size)


func _register(rect: Rect2, action: String, payload: Variant = null, tooltip: String = "") -> void:
	_click_targets.append({"rect": rect, "action": action, "payload": payload, "tooltip": tooltip})


func _surface(rect: Rect2, color: Color, border_color: Color, radius: int) -> void:
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


func _text(position: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _section_heading(position: Vector2, label: String) -> void:
	draw_rect(Rect2(position, Vector2(3.0, 16.0)), GOLD)
	_text(position + Vector2(10.0, 13.0), label, 12, INK_MUTED)


func _divider(position: Vector2, width: float) -> void:
	draw_line(position, position + Vector2(width, 0.0), LINE, 1.0)


func _primary_action(rect: Rect2, label: String, action: String, payload: Variant, tooltip: String) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GOLD, 0.22)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	draw_style_box(style, rect)
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
	_text(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + 20.0), label, 11, INK)
	_register(rect, action, payload, tooltip)


func _text_link(rect: Rect2, label: String, action: String, payload: Variant, tooltip: String) -> void:
	_text(rect.position + Vector2(4.0, 19.0), label, 10, GOLD)
	draw_line(rect.position + Vector2(4.0, 23.0), rect.position + Vector2(minf(rect.size.x - 4.0, _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x + 4.0), 23.0), Color(GOLD, 0.45), 1.0)
	_register(rect, action, payload, tooltip)


func _more_action(rect: Rect2, tooltip: String) -> void:
	_text(rect.position + Vector2(8.0, 18.0), "•••", 12, INK_MUTED)
	_register(rect, "more", "更多", tooltip)


func _compact_action(rect: Rect2, label: String, active: bool, action: String, payload: Variant, tooltip: String) -> void:
	if active:
		draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), GOLD)
	_text(rect.position + Vector2(9.0, 18.0), label, 10, INK if active else INK_MUTED)
	_register(rect, action, payload, tooltip)


func _close_control(rect: Rect2) -> void:
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "panel_close", "收起")


func _icon_close(rect: Rect2, action: String, tooltip: String) -> void:
	_text(rect.position + Vector2(7.0, 18.0), "×", 14, INK_MUTED)
	_register(rect, action, null, tooltip)


func _check_row(position: Vector2, label: String) -> void:
	draw_circle(position + Vector2(7.0, 7.0), 7.0, Color(GREEN, 0.18))
	_text(position + Vector2(3.0, 12.0), "✓", 10, GREEN)
	_text(position + Vector2(24.0, 12.0), label, 10, INK_MUTED)


func _draw_avatar(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("#263f42"))
	draw_circle(center, radius - 3.0, Color("#b8aa82"))
	draw_circle(center + Vector2(0.0, -6.0), radius * 0.28, Color("#344746"))
	draw_arc(center + Vector2(0.0, 12.0), radius * 0.48, PI, TAU, 20, Color("#344746"), 9.0)
	draw_arc(center, radius - 1.5, 0.0, TAU, 28, Color(GOLD, 0.45), 1.3)


func _dictionary_value(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value as Dictionary if value is Dictionary else {}
