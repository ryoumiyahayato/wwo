class_name PrototypeV2Interface
extends Control
## V2.1.2 four-corner interface. The map remains the primary visual surface.

signal mode_requested(mode_id: String)
signal world_view_requested
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
const TIME_CORNER := Rect2(1014.0, 18.0, 190.0, 62.0)
const SYSTEM_CORNER := Rect2(1214.0, 18.0, 48.0, 48.0)
const CHARACTER_CORNER := Rect2(18.0, 630.0, 304.0, 72.0)
const ACTIVITY_CORNER := Rect2(944.0, 622.0, 318.0, 80.0)
const MODE_ENTRY := Rect2(548.0, 674.0, 184.0, 28.0)
const WORLD_VIEW_ENTRY := Rect2(738.0, 674.0, 34.0, 28.0)
const REVIEW_SWITCH := Rect2(502.0, 14.0, 276.0, 34.0)
const MAX_PRIMARY_PANEL_WIDTH := 396.0

var data: PrototypeV2Data
var life_binding: V2LifeLoopUiBinding
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
var system_menu_open: bool = false
var person_more_menu_open: bool = false
var review_mode: bool = false
var schedule_form: Dictionary = {}
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


func setup_life_loop(binding: V2LifeLoopUiBinding) -> void:
	life_binding = binding
	if life_binding != null:
		identity = life_binding.identity_id()
		paused = bool(life_binding.time_view().get("paused", true))
		speed = int(life_binding.time_view().get("speed", 1))
		if not life_binding.view_changed.is_connected(_on_life_view_changed):
			life_binding.view_changed.connect(_on_life_view_changed)
	queue_redraw()


func toggle_pause_command() -> void:
	if life_binding != null:
		life_binding.toggle_pause()
		paused = bool(life_binding.time_view().get("paused", true))
	else:
		paused = not paused
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
	if system_menu_open:
		system_menu_open = false
		queue_redraw()
		return true
	if mode_menu_open:
		mode_menu_open = false
		queue_redraw()
		return true
	if person_more_menu_open:
		person_more_menu_open = false
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
	if life_binding != null and open_panel in ["schedule", "developer"] and open_panel != panel_id:
		life_binding.end_blocking_panel()
	open_panel = panel_id
	if life_binding != null and panel_id in ["schedule", "developer"]:
		life_binding.begin_blocking_panel()
	mode_menu_open = false
	system_menu_open = false
	person_more_menu_open = false
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
	var was_blocking: bool = open_panel in ["schedule", "developer"]
	if _panel_tween != null:
		_panel_tween.kill()
	if not animated:
		panel_progress = 0.0
		open_panel = ""
		if life_binding != null and was_blocking:
			life_binding.end_blocking_panel()
		queue_redraw()
		return
	_panel_tween = create_tween()
	_panel_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(self, "panel_progress", 0.0, 0.16)
	_panel_tween.tween_callback(func() -> void:
		open_panel = ""
		if life_binding != null and was_blocking:
			life_binding.end_blocking_panel()
		queue_redraw()
	)


func set_identity(identity_id: String) -> void:
	if identity_id not in ["worker", "official"]:
		return
	identity = identity_id
	if life_binding != null:
		var result: V2LifeLoopResult = life_binding.select_identity(identity_id)
		if not result.success:
			_show_toast(result.user_message)
			return
	detail_person_id = ""
	person_detail_level = 0
	person_more_menu_open = false
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
	person_more_menu_open = false
	queue_redraw()


func show_activity_toast() -> void:
	_show_toast("! 里尔食品价格上涨 · 点击右下角查看")


func show_camera_focus_feedback(message: String) -> void:
	_show_toast(message)


func camera_focus_target_at(position: Vector2) -> String:
	if COUNTRY_CORNER.has_point(position):
		return "country"
	if CHARACTER_CORNER.has_point(position):
		return "person"
	return ""


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
	system_menu_open = false
	person_more_menu_open = false
	_hover_tooltip = ""
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
		"person_more_menu":
			detail_person_id = "jeanne"
			person_detail_level = 1
			person_more_menu_open = true
		"plan_detail":
			identity = "official"
			open_panel = "character"
			panel_progress = 1.0
			action_detail_id = str((_identity_data().get("plan_detail", {}) as Dictionary).get("title", ""))
		"status_symbols":
			open_panel = "character"
			panel_progress = 1.0
			_hover_position = Vector2(560.0, 170.0)
			_hover_tooltip = "当前状态：需要注意\n主要原因：本周轮班与夜校重叠\n近期趋势：缓慢上升\n可能影响：可能降低晚间学习效率\n建议处理：安排一次完整休整"
		"owned_organizations":
			open_panel = "character"
			character_section = "owned_orgs"
			panel_progress = 1.0
		"discover_organizations":
			open_panel = "character"
			character_section = "discover_orgs"
			panel_progress = 1.0
		"organization_name_tooltip":
			open_panel = "character"
			character_section = "discover_orgs"
			panel_progress = 1.0
			_hover_position = Vector2(550.0, 225.0)
			_hover_tooltip = "为何知道：玩家在里尔市政公告栏看到登记信息\n接触来源：同地区公开组织公告\n主要职能：集中采购食品与燃料\n加入方式：携住址证明到公开窗口登记\n基本条件：符合地区居民基本条件\n缺少条件：无"
		"official_discover_organizations":
			identity = "official"
			open_panel = "character"
			character_section = "discover_orgs"
			panel_progress = 1.0
		"position_salary_tooltip":
			identity = "official"
			open_panel = "character"
			character_section = "discover_orgs"
			panel_progress = 1.0
			_hover_position = Vector2(555.0, 270.0)
			_hover_tooltip = "薪资：月薪 96 法郎\n支付周期：每月支付\n津贴：会议日交通津贴 4 法郎/月\n权限：登记议程与会签文件\n工作内容：整理道路、建筑和市镇工程会议文书\n条件：行政文书资历；公开考试或部门借调\n上级：委员会秘书长\n部门：书记处"
		"official_economy":
			identity = "official"
			open_panel = "character"
			character_section = "life_work"
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
		"system_menu":
			system_menu_open = true
		"mode_menu":
			mode_menu_open = true
		_:
			pass
	queue_redraw()


func debug_state() -> Dictionary:
	var country: Dictionary = _focus_country_data()
	var identities: Dictionary = data.get_document("characters").get("identities", {}) as Dictionary
	var official: Dictionary = _dictionary_value(identities, "official")
	var state: Dictionary = {
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
		"system_menu_open": system_menu_open,
		"person_more_menu_open": person_more_menu_open,
		"hover_tooltip": _hover_tooltip,
		"world_view_entry": WORLD_VIEW_ENTRY,
		"object_card_primary_actions": 1,
		"object_card_secondary_actions": 2,
		"activity_summary_items": 1,
		"institution_structure": "public_portal" if identity == "worker" else "department_hierarchy",
		"country_emblem_type": str(country.get("emblem_type", "")),
		"country_detail_name": str(country.get("formal_name_zh", "")),
		"country_visible_text": "%s %s %s" % [str(country.get("display_name_zh", "")), str(country.get("formal_name_zh", "")), str(country.get("native_name", ""))],
		"identity_fields_separated": true,
		"status_symbols": ["✓", "!", "×", "🔒"],
		"status_tooltip_fields": ["当前状态", "主要原因", "近期趋势", "可能影响", "建议处理"],
		"plan_title": str((_identity_data().get("plan_detail", {}) as Dictionary).get("title", "")),
		"plan_primary_fields": ["目标", "负责对象", "当前阶段", "预计持续时间", "预计效果", "所需时间", "所需资源", "权限来源", "中止条件", "下一步骤"],
		"plan_formula_visible": false,
		"relationship_sections": ["关系类型", "熟悉度", "信任", "好感或敌意", "共同工作", "共同组织", "共同联系人", "最近互动", "互相帮助或义务", "当前可进行的关系行为"],
		"time_menu_items": ["暂停", "1×", "2×", "4×", "8×"],
		"system_menu_items": ["保存", "设置", "退出或返回主菜单"],
		"time_is_static_prototype": true,
		"time_menu_contains_system_tools": false,
		"visible_ellipsis_has_menu": true,
		"discover_card_fields": ["组织名称", "组织类型", "当前是否可接触", "可获得职位", "主要入口"],
		"organization_tooltip_fields": ["为何知道", "接触来源", "主要职能", "加入方式", "基本条件", "缺少条件"],
		"position_tooltip_fields": ["薪资", "支付周期", "津贴", "权限", "工作内容", "条件", "上级", "部门"],
		"official_personal_cash": str(official.get("cash", "")),
		"official_personal_salary": str(official.get("monthly_salary", "")),
		"official_personal_income": str(official.get("income", "")),
		"official_personal_expenses": str(official.get("expenses", "")),
		"official_institution_budget": str(official.get("institution_budget_source", "")),
		"personal_and_institution_budget_separated": not official.has("budget_source") and official.has("institution_budget_source"),
		"permission_copy": "需要中央部门批准",
	}
	if life_binding != null:
		state.merge(life_binding.debug_state(), true)
		state["paused"] = bool(life_binding.time_view().get("paused", true))
		state["speed"] = int(life_binding.time_view().get("speed", 1))
		state["identity_switch_visible"] = review_mode
		state["time_is_static_prototype"] = false
		state["schedule_panel_available"] = true
		state["save_load_available"] = true
	return state


func get_panel_rect() -> Rect2:
	match open_panel:
		"country":
			return Rect2(18.0, 98.0, MAX_PRIMARY_PANEL_WIDTH, 510.0)
		"time":
			return Rect2(1030.0, 88.0, 174.0, 194.0)
		"character":
			return Rect2(18.0, 98.0, MAX_PRIMARY_PANEL_WIDTH, 516.0)
		"activity":
			return Rect2(866.0, 104.0, MAX_PRIMARY_PANEL_WIDTH, 500.0)
		"schedule":
			return Rect2(706.0, 86.0, 556.0, 528.0)
		"developer":
			return Rect2(654.0, 86.0, 608.0, 528.0)
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
	_draw_time_corner()
	_draw_system_corner()
	if open_panel != "character":
		_draw_character_corner()
	if open_panel != "activity":
		_draw_activity_corner()
	_draw_mode_entry()
	_draw_world_view_entry()
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
			"schedule":
				_draw_schedule_panel()
			"developer":
				_draw_developer_panel()
	if system_menu_open:
		_draw_system_menu()
	if not selected_object.is_empty():
		_draw_object_card()
	if not detail_person_id.is_empty():
		_draw_person_card()
	if person_more_menu_open:
		_draw_person_more_menu()
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
	var tooltip: String = "点击控制权威时间" if life_binding != null else "静态原型：时间推进尚未接入。点击选择暂停或速度视觉状态。"
	_register(TIME_CORNER, "corner_time", null, tooltip)
	var date_label: String = "1900年3月12日"
	var state_label: String = "Ⅱ 暂停" if paused else "速度预览 · %d×" % speed
	if life_binding != null:
		var time: Dictionary = life_binding.time_view()
		date_label = "%s · %s" % [
			str(time.get("date_display", "")), str(time.get("hour_display", "")),
		]
		paused = bool(time.get("paused", true))
		speed = int(time.get("speed", 1))
		state_label = (
			"Ⅱ 暂停 · %s" % str(time.get("weekday_display", ""))
			if paused
			else "%s · %d×" % [str(time.get("weekday_display", "")), speed]
		)
	_text(TIME_CORNER.position + Vector2(14.0, 24.0), date_label, 13 if life_binding != null else 15, INK)
	_text(TIME_CORNER.position + Vector2(14.0, 47.0), state_label, 10, GOLD)
	_text(TIME_CORNER.end - Vector2(23.0, 20.0), "⌄", 14, INK_DIM)


func _draw_system_corner() -> void:
	_surface(SYSTEM_CORNER, PANEL, Color(GOLD, 0.22), 18)
	_text(SYSTEM_CORNER.position + Vector2(14.0, 31.0), "⚙", 18, INK)
	_register(SYSTEM_CORNER, "toggle_system_menu", null, "系统工具：保存、载入、设置与开发者工具")


func _draw_system_menu() -> void:
	var live: bool = life_binding != null
	var items: Array = [
		["保存", "system_save", "原型不会写入存档"],
		["设置", "system_settings", "静态设置入口占位"],
		["退出或返回主菜单", "system_return", "独立原型不连接正式菜单"],
	]
	if live:
		items = [
			["保存进度", "system_save", "保存到 V2.2 固定评审槽"],
			["载入最近存档", "system_load", "验证后事务式恢复最近评审存档"],
			["设置", "system_settings", "设置入口占位"],
			["退出或返回主菜单", "system_return", "独立评审场景保持当前行为"],
		]
		if review_mode or life_binding.developer_mode:
			items.insert(
				3,
				["开发者工具", "open_developer", "打开权威时间、账本与结算工具"]
			)
	var rect := Rect2(1034.0, 78.0, 228.0, 18.0 + float(items.size()) * 29.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.3), 10)
	_register(rect, "consume")
	_text(rect.position + Vector2(14.0, 23.0), "系统工具", 12, INK_MUTED)
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(rect.position.x + 9.0, rect.position.y + 34.0 + float(index) * 29.0, rect.size.x - 18.0, 26.0)
		_text(row.position + Vector2(10.0, 18.0), str(item[0]), 11, INK)
		_register(row, str(item[1]), null, str(item[2]))


func _draw_character_corner() -> void:
	_surface(CHARACTER_CORNER, PANEL, Color(GOLD, 0.18), 10)
	_register(CHARACTER_CORNER, "corner_character", null, "打开人物中心")
	_draw_avatar(CHARACTER_CORNER.position + Vector2(34.0, 36.0), 23.0)
	var person: Dictionary = _identity_data()
	_text(CHARACTER_CORNER.position + Vector2(70.0, 23.0), str(person.get("display_name_zh", "")), 16, INK)
	_text(CHARACTER_CORNER.position + Vector2(70.0, 41.0), str(person.get("native_name", "")), 9, INK_MUTED)
	_text(CHARACTER_CORNER.position + Vector2(70.0, 60.0), str(person.get("occupation", "")), 11, GOLD)
	if life_binding != null:
		var current: Dictionary = person.get("current_activity", {}) as Dictionary
		_text(
			CHARACTER_CORNER.position + Vector2(196.0, 60.0),
			str(current.get("label", "")), 9, GREEN
		)
	_text(CHARACTER_CORNER.end - Vector2(22.0, 30.0), "›", 20, INK_DIM)


func _draw_activity_corner() -> void:
	_surface(ACTIVITY_CORNER, PANEL, Color(AMBER, 0.2), 10)
	_register(ACTIVITY_CORNER, "corner_activity", null, "展开通知、事件与新闻历史")
	var latest: Dictionary = {}
	var unread_count: int = 0
	if life_binding != null:
		var live_items: Array[Dictionary] = life_binding.notifications_view(1)
		if not live_items.is_empty():
			latest = live_items[0]
		unread_count = life_binding.simulation.notifications.unread_count()
	else:
		var summary: Dictionary = data.get_document("activity").get("default_summary", {}) as Dictionary
		latest = _activity_by_id(str(summary.get("latest_id", "")))
		unread_count = int(summary.get("unread_count", 0))
	_text(ACTIVITY_CORNER.position + Vector2(14.0, 21.0), "! 生活通知" if life_binding != null else "! 重要通知", 11, AMBER)
	_text(ACTIVITY_CORNER.position + Vector2(14.0, 43.0), str(latest.get("title", "暂无新通知")), 13, INK)
	_text(ACTIVITY_CORNER.position + Vector2(14.0, 63.0), "%s · 未读 %d" % [str(latest.get("time", "")), unread_count], 10, INK_MUTED)
	_text(ACTIVITY_CORNER.end - Vector2(24.0, 29.0), "↑", 15, GOLD)


func _draw_mode_entry() -> void:
	_surface(MODE_ENTRY, Color(0.025, 0.055, 0.06, 0.9), Color(GOLD, 0.2), 14)
	var mode: Dictionary = _mode_by_id(current_mode)
	_text(MODE_ENTRY.position + Vector2(14.0, 19.0), "%s  %s" % [str(mode.get("icon", "◇")), str(mode.get("label", "地图模式"))], 11, INK)
	_text(MODE_ENTRY.end - Vector2(24.0, 9.0), "⌃" if mode_menu_open else "⌄", 12, INK_MUTED)
	_register(MODE_ENTRY, "toggle_mode_menu", null, str(mode.get("description", "")))


func _draw_world_view_entry() -> void:
	_surface(
		WORLD_VIEW_ENTRY,
		Color(0.025, 0.055, 0.06, 0.9),
		Color(GOLD, 0.2),
		14
	)
	_text(WORLD_VIEW_ENTRY.position + Vector2(10.0, 20.0), "⌂", 14, INK)
	_register(
		WORLD_VIEW_ENTRY,
		"world_view",
		null,
		"返回世界视角（Home）"
	)


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
	_text(rect.position + Vector2(20.0, 58.0), "République française · 第三共和国", 10, INK_MUTED)
	_text(rect.position + Vector2(20.0, 78.0), "公开入口 · 信息精度受公开渠道限制", 9, BLUE)
	_section_heading(rect.position + Vector2(20.0, 108.0), "与玩家有关的本地政策")
	_text(rect.position + Vector2(20.0, 136.0), "北部省劳动监察处发布安全检查公告", 12, INK)
	_text(rect.position + Vector2(20.0, 157.0), "✓ 可查看公开摘要与投诉渠道", 9, INK_MUTED)
	_divider(rect.position + Vector2(20.0, 178.0), rect.size.x - 40.0)
	_section_heading(rect.position + Vector2(20.0, 205.0), "公开新闻")
	_text(rect.position + Vector2(20.0, 233.0), "《里尔公报》：巴黎—里尔铁路出现延误", 11, INK)
	_text(rect.position + Vector2(20.0, 253.0), "公开报道 · 今日", 9, INK_DIM)
	_divider(rect.position + Vector2(20.0, 274.0), rect.size.x - 40.0)
	_section_heading(rect.position + Vector2(20.0, 301.0), "可接触的公共机构")
	_text(rect.position + Vector2(20.0, 329.0), "北部省劳动监察处", 12, INK)
	_text(rect.position + Vector2(20.0, 348.0), "公开公告与投诉窗口", 9, INK_MUTED)
	_text(rect.position + Vector2(20.0, 379.0), "里尔市政厅", 12, INK)
	_text(rect.position + Vector2(20.0, 398.0), "办事程序与地区公告", 9, INK_MUTED)
	_text(rect.position + Vector2(20.0, 429.0), "未公开预算、内部层级与无关议程不会显示", 8, INK_DIM)
	_text(rect.position + Vector2(20.0, 445.0), "现代 Natural Earth 边界 · 原型技术说明", 8, Color(INK_DIM, 0.68))
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 48.0, 140.0, 30.0), "查看本地政策", "context_action", "查看本地政策", "公开信息入口")
	_text_link(Rect2(rect.position.x + 176.0, rect.end.y - 46.0, 92.0, 28.0), "公开新闻", "context_action", "公开新闻", "打开公开新闻")


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
	_text(rect.position + Vector2(20.0, 415.0), "🔒 中央铁路投资排序 · 需要中央部门批准", 10, AMBER)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 48.0, 142.0, 30.0), "处理当前议程", "context_action", "处理当前议程", "仅限当前职位与辖区")
	_text_link(Rect2(rect.position.x + 178.0, rect.end.y - 46.0, 96.0, 28.0), "查看程序", "context_action", "查看程序", "查看法定程序")


func _draw_time_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(0.0, -24.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_text(rect.position + Vector2(14.0, 24.0), "权威时间速度" if life_binding != null else "速度视觉状态", 12, INK_MUTED)
	var pause_row := Rect2(rect.position.x + 8.0, rect.position.y + 34.0, rect.size.x - 16.0, 27.0)
	_compact_action(pause_row, "Ⅱ  暂停", paused, "pause", null, "暂停权威时间" if life_binding != null else "静态原型：时间推进尚未接入。")
	for index: int in range(4):
		var option: int = [1, 2, 4, 8][index]
		var row := Rect2(rect.position.x + 8.0, rect.position.y + 64.0 + float(index) * 29.0, rect.size.x - 16.0, 26.0)
		_compact_action(row, "%d×  运行" % option if life_binding != null else "%d×  速度预览" % option, not paused and speed == option, "speed", option, "按固定小时步进运行" if life_binding != null else "仅验证视觉选中状态；不推进正式世界时间。")


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
		"schedule":
			_draw_schedule_summary(body, person)
		"relationships":
			_draw_relationships(body)
		"owned_orgs":
			_draw_organizations(body, true)
		"discover_orgs":
			_draw_organizations(body, false)


func _draw_character_navigation(rect: Rect2) -> void:
	var items: Array = [
		["summary", "概览"], ["life_work", "生活与工作"],
		["relationships", "关系人物"],
		["owned_orgs", "我的组织"], ["discover_orgs", "探索组织"],
	]
	if life_binding != null:
		items.insert(2, ["schedule", "安排活动"])
	for index: int in range(items.size()):
		var item: Array = items[index] as Array
		var row := Rect2(rect.position.x, rect.position.y + float(index) * 45.0, rect.size.x, 34.0)
		if character_section == str(item[0]):
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), GOLD)
		_text(row.position + Vector2(12.0, 22.0), str(item[1]), 11, INK if character_section == str(item[0]) else INK_MUTED)
		_register(row, "character_section", str(item[0]), "人物中心内切换信息层，不叠加模块窗口")


func _draw_character_summary(rect: Rect2, person: Dictionary) -> void:
	_section_heading(rect.position + Vector2(0.0, 15.0), "当前状态")
	var indicators: Array = person.get("status_indicators", []) as Array
	for index: int in range(mini(3, indicators.size())):
		_draw_status_indicator(Rect2(rect.position.x + float(index) * 82.0, rect.position.y + 27.0, 74.0, 28.0), indicators[index] as Dictionary)
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
	_primary_action(
		Rect2(rect.position.x, rect.end.y - 38.0, 118.0, 30.0),
		"安排活动" if life_binding != null else "查看当前计划",
		"open_schedule" if life_binding != null else "action_detail",
		str(person.get("plan", "")),
		"打开日期、时间、成本、效果与冲突检查" if life_binding != null else "查看目标、效果、资源、权限与下一步骤"
	)


func _draw_life_work(rect: Rect2, person: Dictionary) -> void:
	if life_binding != null:
		_draw_live_life_work(rect, person)
		return
	if identity == "worker":
		_section_heading(rect.position + Vector2(0.0, 15.0), "个人经济")
		_text(rect.position + Vector2(0.0, 43.0), str(person.get("household", "")), 12, INK)
		_text(rect.position + Vector2(0.0, 66.0), "现金  %s" % str(person.get("cash", "")), 10, INK_MUTED)
		_text(rect.position + Vector2(0.0, 86.0), "%s · %s" % [str(person.get("weekly_wage", "")), str(person.get("pay_cycle", ""))], 10, GOLD)
		_text(rect.position + Vector2(0.0, 106.0), "%s · %s" % [str(person.get("income", "")), str(person.get("expenses", ""))], 9, INK_MUTED)
		_section_heading(rect.position + Vector2(0.0, 135.0), "工作与组织")
		_text(rect.position + Vector2(0.0, 163.0), "雇主", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 163.0), str(person.get("employer", "")), 11, INK)
		_text(rect.position + Vector2(0.0, 188.0), "工会", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 188.0), str(person.get("union", "")), 11, GOLD)
		_text(rect.position + Vector2(0.0, 213.0), "职位", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 213.0), str(person.get("union_position", "")), 11, GOLD)
		_text(rect.position + Vector2(0.0, 238.0), "夜校", 10, INK_DIM)
		_text(rect.position + Vector2(58.0, 238.0), str(person.get("school", "")), 11, INK)
		_text(rect.position + Vector2(0.0, 268.0), str(person.get("work_contract", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(0.0, 289.0), str(person.get("debt_burden", "")), 9, INK_DIM)
	else:
		_section_heading(rect.position + Vector2(0.0, 15.0), "个人经济")
		_text(rect.position + Vector2(0.0, 43.0), "现金  %s" % str(person.get("cash", "")), 11, INK)
		_text(rect.position + Vector2(0.0, 65.0), "%s · %s" % [str(person.get("income", "")), str(person.get("expenses", ""))], 9, INK_MUTED)
		_text(rect.position + Vector2(0.0, 87.0), "%s · %s" % [str(person.get("monthly_salary", "")), str(person.get("pay_cycle", ""))], 10, GOLD)
		_text(rect.position + Vector2(0.0, 108.0), str(person.get("allowance", "")), 10, GREEN)
		_text(rect.position + Vector2(0.0, 129.0), str(person.get("debt_burden", "")), 9, INK_DIM)
		_divider(rect.position + Vector2(0.0, 146.0), rect.size.x)
		_section_heading(rect.position + Vector2(0.0, 170.0), "任职信息")
		_text(rect.position + Vector2(0.0, 198.0), str(person.get("institution_position", "")), 11, GOLD)
		_text(rect.position + Vector2(0.0, 220.0), str(person.get("institution", "")), 10, INK)
		_text(rect.position + Vector2(0.0, 242.0), "管辖  %s" % str(person.get("jurisdiction", "")), 10, INK_MUTED)
		_text(rect.position + Vector2(0.0, 264.0), "权限来源  %s" % str(person.get("authority_source", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(0.0, 292.0), str(person.get("upstream_locked", "")), 9, AMBER)


func _draw_live_life_work(rect: Rect2, person: Dictionary) -> void:
	_section_heading(rect.position + Vector2(0.0, 15.0), "个人经济")
	_text(rect.position + Vector2(0.0, 42.0), "现金  %s" % str(person.get("cash", "")), 11, INK)
	_text(rect.position + Vector2(0.0, 63.0), "%s · %s" % [str(person.get("income", "")), str(person.get("expenses", ""))], 9, INK_MUTED)
	_text(rect.position + Vector2(0.0, 84.0), "%s" % str(person.get("weekly_wage", "")), 10, GOLD)
	_text(rect.position + Vector2(0.0, 104.0), str(person.get("pay_cycle", "")), 8, INK_MUTED)
	_divider(rect.position + Vector2(0.0, 120.0), rect.size.x)
	_section_heading(rect.position + Vector2(0.0, 145.0), "生活物资与住房")
	_text(rect.position + Vector2(0.0, 173.0), "食品  %d 人日 · 用品  %d 人日" % [
		int(person.get("food_stock", 0)), int(person.get("essentials_stock", 0)),
	], 10, INK)
	_text(rect.position + Vector2(0.0, 195.0), "下次房租  %s" % str(person.get("next_rent", "")), 8, INK_MUTED)
	_text(rect.position + Vector2(0.0, 217.0), "欠款  %d 生丁" % int(person.get("rent_arrears_centimes", 0)), 10, AMBER if int(person.get("rent_arrears_centimes", 0)) > 0 else GREEN)
	_divider(rect.position + Vector2(0.0, 234.0), rect.size.x)
	_section_heading(rect.position + Vector2(0.0, 259.0), "今日出勤")
	var attendance: Dictionary = person.get("today_attendance", {}) as Dictionary
	_text(rect.position + Vector2(0.0, 287.0), "义务 %d · 出勤 %d · 请假 %d" % [
		int(attendance.get("required", 0)),
		int(attendance.get("attended", 0)),
		int(attendance.get("authorized_leave", 0)),
	], 9, INK)
	_text(rect.position + Vector2(0.0, 307.0), "缺勤 %d · 加班 %d · 风险 %d" % [
		int(attendance.get("unauthorized_absence", 0)),
		int(attendance.get("overtime", 0)),
		int(person.get("employment_risk", 0)),
	], 9, AMBER)


func _draw_schedule_summary(rect: Rect2, person: Dictionary) -> void:
	_section_heading(rect.position + Vector2(0.0, 15.0), "当前与下一活动")
	var current: Dictionary = person.get("current_activity", {}) as Dictionary
	var next: Dictionary = person.get("next_activity", {}) as Dictionary
	_text(rect.position + Vector2(0.0, 45.0), "当前  %s" % str(current.get("label", "无")), 11, GREEN)
	_text(rect.position + Vector2(0.0, 67.0), str(current.get("location_name", "")), 9, INK_MUTED)
	_text(rect.position + Vector2(0.0, 91.0), "结束  %s" % str(current.get("end_display", "")), 8, INK_DIM)
	_text(rect.position + Vector2(0.0, 124.0), "下一  %s" % str(next.get("label", "无")), 11, GOLD)
	_text(rect.position + Vector2(0.0, 146.0), str(next.get("start_display", "")), 8, INK_MUTED)
	_divider(rect.position + Vector2(0.0, 168.0), rect.size.x)
	_text(rect.position + Vector2(0.0, 194.0), "Demo 简化规则：无薪请假自动批准", 9, BLUE)
	_text(rect.position + Vector2(0.0, 218.0), "所有活动先检查时间、现金、工作义务与疲劳。", 9, INK_MUTED)
	_primary_action(Rect2(rect.position.x, rect.position.y + 252.0, 138.0, 30.0), "打开安排面板", "open_schedule", null, "选择活动并查看实时后果")


func _draw_relationships(rect: Rect2) -> void:
	if life_binding != null:
		var person: Dictionary = _identity_data()
		var relationship: Dictionary = person.get("relationship", {}) as Dictionary
		_section_heading(rect.position + Vector2(0.0, 15.0), "让娜·勒鲁瓦")
		if relationship.is_empty():
			_text(rect.position + Vector2(0.0, 48.0), "当前人物没有可用关系行动", 10, INK_MUTED)
			return
		_text(rect.position + Vector2(0.0, 48.0), "熟悉度  %d" % int(relationship.get("familiarity", 0)), 11, INK)
		_text(rect.position + Vector2(0.0, 72.0), "信任  %d" % int(relationship.get("trust", 0)), 11, INK)
		_text(rect.position + Vector2(0.0, 102.0), "最近联系  %s" % str(relationship.get("last_contact_datetime", "尚未联系")), 9, INK_MUTED)
		var interactions: Array = relationship.get("recent_interactions", []) as Array
		_text(rect.position + Vector2(0.0, 130.0), "最近互动 %d 条 · 每24小时最多一次" % interactions.size(), 9, GOLD)
		_primary_action(Rect2(rect.position.x, rect.position.y + 165.0, 116.0, 30.0), "联系让娜", "schedule_activity", "social_contact", "耗时1小时；熟悉度+5、信任+2、压力-20")
		return
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
	_text(rect.position + Vector2(0.0, 43.0), "已加入的具体职位与项目" if owned else "只显示当前已知并可解释来源的组织", 9, INK_DIM)
	var identity_records: Dictionary = _organization_identity_data()
	var organizations: Array = identity_records.get("owned" if owned else "discover", []) as Array
	for index: int in range(mini(organizations.size(), 2 if owned else 3)):
		var organization: Dictionary = _organization_record(organizations[index] as Dictionary)
		var height: float = 158.0 if owned else 108.0
		var row := Rect2(rect.position.x, rect.position.y + 60.0 + float(index) * (height + 8.0), rect.size.x, height)
		_draw_organization_entry(row, organization, owned)


func _draw_organization_entry(rect: Rect2, organization: Dictionary, owned: bool) -> void:
	draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), GOLD if owned else BLUE)
	var name_rect := Rect2(rect.position.x + 8.0, rect.position.y + 2.0, rect.size.x - 16.0, 24.0)
	_text(rect.position + Vector2(12.0, 20.0), "%s  %s" % [str(organization.get("emblem", "○")), str(organization.get("name", ""))], 13, INK)
	if owned:
		_text(rect.position + Vector2(12.0, 41.0), "职位  %s" % str(organization.get("position", "")), 10, GOLD)
		_text(rect.position + Vector2(12.0, 59.0), "部门  %s" % str(organization.get("department", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(12.0, 77.0), "项目  %s" % str(organization.get("project", "")), 9, GREEN)
		_text(rect.position + Vector2(12.0, 95.0), "上级  %s" % str(organization.get("supervisor", "")), 9, INK_MUTED)
		_text(rect.position + Vector2(12.0, 113.0), "薪酬  %s" % str(organization.get("compensation", "")), 9, GOLD)
		_text_link(Rect2(rect.position.x + 12.0, rect.end.y - 27.0, 104.0, 23.0), "查看组织事务", "organization_action", "查看组织事务", "主要动作")
		_text_link(Rect2(rect.position.x + 128.0, rect.end.y - 27.0, 100.0, 23.0), "职位与权限", "organization_action", "职位与权限", "权限：%s" % str(organization.get("authority", "")))
	else:
		var organization_tooltip: String = "为何知道：%s\n接触来源：%s\n主要职能：%s\n加入方式：%s\n基本条件：%s\n缺少条件：%s" % [str(organization.get("known_reason", "")), str(organization.get("contact_source", "")), str(organization.get("function", "")), str(organization.get("entry_method", "")), str(organization.get("eligible", "")), str(organization.get("missing_conditions", ""))]
		_register(name_rect, "consume", null, organization_tooltip)
		_text(rect.position + Vector2(12.0, 40.0), "%s · %s" % [str(organization.get("type", "组织")), str(organization.get("access", ""))], 9, INK_MUTED)
		var position_rect := Rect2(rect.position.x + 8.0, rect.position.y + 45.0, rect.size.x - 16.0, 24.0)
		_text(rect.position + Vector2(12.0, 61.0), "可申请职位  %s" % str(organization.get("available_position", "")), 10, GOLD)
		var position_tooltip: String = "薪资：%s\n支付周期：%s\n津贴：%s\n权限：%s\n工作内容：%s\n条件：%s\n上级：%s\n部门：%s" % [str(organization.get("position_salary", "")), str(organization.get("pay_cycle", "")), str(organization.get("allowance", "")), str(organization.get("position_authority", "")), str(organization.get("position_work", "")), str(organization.get("position_requirements", "")), str(organization.get("supervisor", "")), str(organization.get("department", ""))]
		_register(position_rect, "consume", null, position_tooltip)
		_text_link(Rect2(rect.position.x + 12.0, rect.end.y - 28.0, 126.0, 23.0), str(organization.get("primary_action", "查看组织")), "organization_action", str(organization.get("primary_action", "")), "组织主要入口")


func _draw_activity_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 18.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_close_control(rect)
	_text(rect.position + Vector2(20.0, 35.0), "生活动态" if life_binding != null else "世界动态", 22, INK)
	_text(rect.position + Vector2(20.0, 58.0), "个人提醒 · 组织信息 · 公开背景新闻" if life_binding != null else "通知即时提醒 · 事件可操作 · 新闻来自公开渠道", 10, INK_MUTED)
	var items: Array = (
		life_binding.notifications_view(20)
		if life_binding != null
		else data.get_document("activity").get("items", []) as Array
	)
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


func _draw_schedule_panel() -> void:
	if life_binding == null:
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var person: Dictionary = _identity_data()
	_text(rect.position + Vector2(20.0, 34.0), "安排活动", 22, INK)
	_text(rect.position + Vector2(20.0, 57.0), "%s · 面板打开时自动暂停" % str(person.get("display_name_zh", "")), 10, INK_MUTED)
	_section_heading(rect.position + Vector2(20.0, 82.0), "今日连续日程")
	var timeline: Array[Dictionary] = life_binding.today_schedule()
	var y: float = rect.position.y + 112.0
	for index: int in range(mini(6, timeline.size())):
		var segment: Dictionary = timeline[index]
		var start_value: Dictionary = V2DateTime.from_total_hour(int(segment.get("start_hour", 0)))
		var end_value: Dictionary = V2DateTime.from_total_hour(int(segment.get("end_hour", 0)))
		var source: String = str(segment.get("source", "default_routine"))
		var status: String = str(segment.get("display_status", "planned"))
		_text(Vector2(rect.position.x + 20.0, y), "%02d:00—%02d:00" % [
			int(start_value["hour"]), int(end_value["hour"]),
		], 9, INK_DIM)
		_text(Vector2(rect.position.x + 105.0, y), "%s · %s · %s" % [
			V2LifeLoopUiBinding._activity_label(str(segment.get("activity_type", ""))),
			_source_label(source), _schedule_status_label(status),
		], 9, INK if status != "completed" else INK_MUTED)
		if source == "player" and status == "planned":
			_register(
				Rect2(rect.position.x + 16.0, y - 15.0, rect.size.x - 32.0, 19.0),
				"schedule_cancel_activity",
				str(segment.get("activity_id", "")),
				"点击取消尚未开始的玩家活动"
			)
		y += 20.0
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 238.0), rect.size.x - 40.0)
	_section_heading(Vector2(rect.position.x + 20.0, rect.position.y + 259.0), "选择活动")
	var actions: Array = [
		["购买食品", "purchase_food", "1小时 · 560生丁 · +7人日"],
		["购买用品", "purchase_essentials", "1小时 · 140生丁 · +7人日"],
		["休息", "rest", "1小时 · 恢复疲劳与压力"],
		["睡眠", "sleep", "8小时 · 优先恢复"],
		["加班", "overtime", "17:00后 · 最多2小时"],
		["上午请假", "authorized_leave", "Demo：无薪自动批准；时长10小时为全天"],
		["联系让娜", "social_contact", "18:00—21:00 · 24小时冷却"],
		["工会例会", "union_activity", "星期三19:00—21:00"],
	]
	for index: int in range(actions.size()):
		var item: Array = actions[index] as Array
		var column: int = index % 4
		var row_index: int = index / 4
		var row := Rect2(
			rect.position.x + 20.0 + float(column) * 128.0,
			rect.position.y + 277.0 + float(row_index) * 31.0,
			120.0, 25.0
		)
		_compact_action(
			row,
			str(item[0]),
			str(schedule_form.get("activity_type", "")) == str(item[1]),
			"schedule_activity",
			str(item[1]),
			str(item[2])
		)
	if not schedule_form.is_empty():
		var start_hour: int = int(schedule_form.get("start_hour", 0))
		var duration: int = int(schedule_form.get("duration_hours", 1))
		var activity_type: String = str(schedule_form.get("activity_type", ""))
		_divider(Vector2(rect.position.x + 20.0, rect.position.y + 342.0), rect.size.x - 40.0)
		_text(
			rect.position + Vector2(20.0, 365.0),
			"%s · %s—%s" % [
				V2LifeLoopUiBinding._activity_label(activity_type),
				V2DateTime.display_from_total_hour(start_hour),
				V2DateTime.display_from_total_hour(start_hour + duration),
			],
			10,
			INK
		)
		_text(
			rect.position + Vector2(20.0, 385.0),
			"地点：%s · 时间成本：%d 小时 · 现金成本：%d 生丁" % [
				life_binding.simulation.config.location_name(
					str(schedule_form.get("location_id", ""))
				),
				duration,
				int(schedule_form.get("required_cash_centimes", 0)),
			],
			8,
			INK_MUTED
		)
		_text(
			rect.position + Vector2(20.0, 403.0),
			"预期：%s · 工作影响：%s" % [
				str(schedule_form.get("expected_effects", "")),
				"替换合同义务" if activity_type in ["authorized_leave", "absence"]
				else "不替换正式工作",
			],
			8,
			INK_MUTED
		)
		_text(
			rect.position + Vector2(20.0, 421.0),
			"✓ 待权威冲突检查 · 可调整日期、时间和持续时长",
			8,
			GREEN
		)
		var adjustments: Array = [
			["日期 -1", -24], ["日期 +1", 24],
			["时间 -1", -1], ["时间 +1", 1],
			["时长 -1", -1001], ["时长 +1", 1001],
		]
		for index: int in range(adjustments.size()):
			var adjustment: Array = adjustments[index] as Array
			_compact_action(
				Rect2(
					rect.position.x + 20.0 + float(index) * 85.0,
					rect.position.y + 439.0,
					79.0,
					24.0
				),
				str(adjustment[0]),
				false,
				"schedule_adjust",
				int(adjustment[1]),
				"调整后仍由权威层检查营业时间、合同义务与冲突"
			)
		_primary_action(
			Rect2(rect.position.x + 20.0, rect.position.y + 474.0, 160.0, 30.0),
			"确认安排",
			"schedule_confirm",
			null,
			"提交到正式日程服务"
		)
		_text_link(
			Rect2(rect.position.x + 194.0, rect.position.y + 476.0, 82.0, 26.0),
			"取消编辑",
			"schedule_cancel_edit",
			null,
			"放弃尚未提交的编辑"
		)
	if not life_binding.last_command_result.success:
		_text(rect.position + Vector2(20.0, rect.end.y - 18.0), "× %s" % life_binding.last_command_result.user_message, 9, RED)
	elif schedule_form.is_empty() and not life_binding.last_command_result.user_message.is_empty():
		_text(rect.position + Vector2(20.0, rect.end.y - 18.0), "✓ %s" % life_binding.last_command_result.user_message, 9, GREEN)


func _draw_developer_panel() -> void:
	if life_binding == null:
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(BLUE, 0.42), 12)
	_register(rect, "consume")
	_close_control(rect)
	var debug: Dictionary = life_binding.simulation.get_debug_state()
	_text(rect.position + Vector2(20.0, 34.0), "V2.2 开发者工具", 21, INK)
	_text(rect.position + Vector2(20.0, 57.0), "权威时间与生活结算 · 打开时自动暂停", 10, INK_MUTED)
	var household: Dictionary = life_binding.simulation.households.household_for_person(
		life_binding.simulation.selected_person_id
	)
	var current_activity: Dictionary = debug.get("current_activity", {}) as Dictionary
	var next_activity: Dictionary = debug.get("next_activity", {}) as Dictionary
	var rows: Array = [
		["权威时间", debug.get("authoritative_datetime", "")],
		["下一小时", debug.get("next_hour", "")],
		["速度", "%s · %s" % [debug.get("speed", 1), "暂停" if debug.get("paused", true) else "运行"]],
		["当前活动", current_activity.get("activity_type", "无")],
		["下一活动", next_activity.get("activity_type", "无")],
		["未来日程", "%s 小时 · %s" % [debug.get("future_48_hours", 0), debug.get("generation_reason", "")]],
		["工资周期", debug.get("current_pay_period", "")],
		["工资幂等键", JSON.stringify(debug.get("processed_pay_keys", [])).left(54)],
		["房租到期", V2DateTime.iso_from_total_hour(int(debug.get("rent_due", -1)))],
		["日消费键", JSON.stringify(debug.get("daily_consumption_keys", [])).right(54)],
		["现金", "%s 生丁" % debug.get("cash", 0)],
		["库存", "食品 %s · 用品 %s" % [
			household.get("food_stock_person_days", 0),
			household.get("essentials_stock_person_days", 0),
		]],
		["账本校验", "一致" if debug.get("ledger_valid", false) else "失败"],
		["状态", JSON.stringify(debug.get("condition", {}))],
		["就业风险", life_binding.simulation.employment.employment_risk(
			life_binding.simulation.selected_person_id
		)],
		["存档版本", debug.get("schema_version", "")],
		["小时性能", "最近 %sµs · 最大 %sµs" % [debug.get("last_hour_processing_usec", 0), debug.get("maximum_hour_processing_usec", 0)]],
		["最近因果", JSON.stringify(debug.get("recent_causal_events", [])).left(54)],
	]
	for index: int in range(rows.size()):
		var row: Array = rows[index] as Array
		var column: int = index / 9
		var row_index: int = index % 9
		var x: float = rect.position.x + 20.0 + float(column) * 282.0
		var y: float = rect.position.y + 84.0 + float(row_index) * 25.0
		_text(Vector2(x, y), str(row[0]), 8, INK_DIM)
		_text(Vector2(x + 76.0, y), str(row[1]).left(34), 8, INK)
	_divider(rect.position + Vector2(20.0, 318.0), rect.size.x - 40.0)
	var commands: Array = [
		["推进1小时", "step_hour"], ["推进1天", "step_day"],
		["到4月1日", "set_date:1900-04-01T08:00:00"],
		["强制发薪", "force_pay"], ["强制房租", "force_rent"],
		["制造缺勤", "absence"], ["现金归零", "cash_zero"],
		["食品归零", "food_zero"], ["用品归零", "essentials_zero"],
		["健康400", "health_low"], ["疲劳950", "fatigue_max"],
		["压力700", "stress_high"], ["清除玩家日程", "clear_schedule"], ["保存", "save"],
		["载入", "load"], ["重置场景", "reset"],
	]
	for index: int in range(commands.size()):
		var command: Array = commands[index] as Array
		var column: int = index % 5
		var row_index: int = index / 5
		_compact_action(
			Rect2(
				rect.position.x + 20.0 + float(column) * 112.0,
				rect.position.y + 336.0 + float(row_index) * 36.0,
				104.0, 28.0
			),
			str(command[0]), false, "developer_command", str(command[1]),
			"开发者命令：%s" % str(command[0])
		)


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
	_text_link(Rect2(rect.end.x - 68.0, rect.end.y - 44.0, 52.0, 28.0), "详情", "person_full_detail", detail_person_id, "查看完整关系信息")


func _draw_person_third_layer(relation: Dictionary) -> void:
	var rect := Rect2(626.0, 105.0, 494.0, 510.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.38), 12)
	_register(rect, "consume")
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "close_person_detail", "关闭人物详情")
	_draw_avatar(rect.position + Vector2(45.0, 48.0), 25.0)
	_text(rect.position + Vector2(84.0, 35.0), str(relation.get("display_name_zh", "")), 21, INK)
	_text(rect.position + Vector2(84.0, 54.0), str(relation.get("native_name", "")), 9, INK_MUTED)
	_text(rect.position + Vector2(84.0, 72.0), "%s · %s" % [str(relation.get("occupation", "")), str(relation.get("region", ""))], 10, GOLD)
	_section_heading(rect.position + Vector2(20.0, 101.0), "完整关系信息")
	var rows: Array = [
		["关系类型", relation.get("relation_type", relation.get("relation", ""))],
		["熟悉度", relation.get("familiarity", "资料待补充")],
		["信任", relation.get("trust", "资料待补充")],
		["好感或敌意", relation.get("affinity", "资料待补充")],
		["共同工作", relation.get("common_work", "暂无共同工作记录")],
		["共同组织", relation.get("common_organizations", "暂无共同组织记录")],
		["共同联系人", relation.get("common_contacts", relation.get("common", ""))],
		["最近互动", relation.get("last_interaction", "")],
		["互相帮助或义务", relation.get("obligations", "暂无义务记录")],
	]
	for index: int in range(rows.size()):
		var row: Array = rows[index] as Array
		var y: float = rect.position.y + 130.0 + float(index) * 31.0
		_text(Vector2(rect.position.x + 20.0, y), str(row[0]), 10, INK_DIM)
		_text(Vector2(rect.position.x + 122.0, y), str(row[1]), 10, INK)
		_divider(Vector2(rect.position.x + 20.0, y + 9.0), rect.size.x - 40.0)
	_text(rect.position + Vector2(20.0, 424.0), "当前可进行：%s" % " · ".join(relation.get("available_relationship_actions", ["联系", "请求帮助", "引荐"]) as Array), 9, INK_MUTED)
	_primary_action(Rect2(rect.position.x + 20.0, rect.end.y - 46.0, 104.0, 30.0), "联系", "person_action", "联系", "主要动作")
	_text_link(Rect2(rect.position.x + 140.0, rect.end.y - 44.0, 92.0, 28.0), "请求帮助", "person_action", "请求帮助", "次要动作")
	_text_link(Rect2(rect.position.x + 246.0, rect.end.y - 44.0, 54.0, 28.0), "引荐", "person_action", "引荐", "关系行为")
	_text_link(Rect2(rect.position.x + 314.0, rect.end.y - 44.0, 54.0, 28.0), "调查", "person_action", "调查", "关系行为")
	_text_link(Rect2(rect.position.x + 382.0, rect.end.y - 44.0, 92.0, 28.0), "共同关系", "person_action", "查看共同关系", "关系行为")


func _draw_person_more_menu() -> void:
	if detail_person_id.is_empty() or person_detail_level != 1:
		return
	var rect := Rect2(932.0, 398.0, 176.0, 112.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.34), 9)
	_register(rect, "consume")
	_text(rect.position + Vector2(12.0, 21.0), "关系行为", 11, INK_MUTED)
	var actions: Array = ["引荐", "调查", "查看共同关系"]
	for index: int in range(actions.size()):
		var row := Rect2(rect.position.x + 8.0, rect.position.y + 29.0 + float(index) * 25.0, rect.size.x - 16.0, 23.0)
		_text(row.position + Vector2(9.0, 17.0), str(actions[index]), 10, INK)
		_register(row, "person_action", actions[index], "静态关系行为入口")


func _draw_action_detail() -> void:
	var plan: Dictionary = _identity_data().get("plan_detail", {}) as Dictionary
	var rect := Rect2(646.0, 98.0, 500.0, 524.0)
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.42), 12)
	_register(rect, "consume")
	_icon_close(Rect2(rect.end.x - 38.0, rect.position.y + 10.0, 26.0, 26.0), "close_action_detail", "关闭详情")
	_text(rect.position + Vector2(20.0, 34.0), str(plan.get("title", action_detail_id)), 20, INK)
	var success_rect := Rect2(rect.position.x + 20.0, rect.position.y + 47.0, 126.0, 26.0)
	_text(success_rect.position + Vector2(0.0, 18.0), "%s  %s" % [str(plan.get("success_symbol", "!")), str(plan.get("success_label", "存在风险"))], 11, GOLD if str(plan.get("success_symbol", "")) == "★" else AMBER)
	_register(success_rect, "consume", null, str(plan.get("success_detail", "")))
	_divider(rect.position + Vector2(20.0, 82.0), rect.size.x - 40.0)
	_text(rect.position + Vector2(20.0, 107.0), "目标", 10, INK_DIM)
	_text(rect.position + Vector2(100.0, 107.0), str(plan.get("goal", "")), 11, INK)
	_text(rect.position + Vector2(20.0, 134.0), "负责对象", 10, INK_DIM)
	_text(rect.position + Vector2(100.0, 134.0), str(plan.get("responsible", "")), 10, INK)
	_text(rect.position + Vector2(20.0, 161.0), "当前阶段", 10, INK_DIM)
	_text(rect.position + Vector2(100.0, 161.0), "%s · %s" % [str(plan.get("stage", "")), str(plan.get("duration", ""))], 10, GOLD)
	_section_heading(rect.position + Vector2(20.0, 190.0), "预计效果")
	var effects: Array = plan.get("effects", []) as Array
	for index: int in range(mini(4, effects.size())):
		_text(rect.position + Vector2(28.0, 219.0 + float(index) * 22.0), "• %s" % str(effects[index]), 10, INK)
	_divider(rect.position + Vector2(20.0, 304.0), rect.size.x - 40.0)
	var detail_rows: Array = [["所需时间", plan.get("time_cost", "")], ["所需资源", plan.get("resources", "")], ["权限来源", plan.get("authority", "")], ["中止条件", plan.get("stop_conditions", "")], ["下一步骤", plan.get("next_step", "")]]
	for index: int in range(detail_rows.size()):
		var row: Array = detail_rows[index] as Array
		var y: float = rect.position.y + 330.0 + float(index) * 35.0
		_text(Vector2(rect.position.x + 20.0, y), str(row[0]), 10, INK_DIM)
		_text(Vector2(rect.position.x + 100.0, y), str(row[1]), 9, INK if index < 4 else GOLD)


func _draw_toast() -> void:
	var width: float = minf(480.0, _font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x + 38.0)
	var modal_open: bool = not selected_object.is_empty() or not detail_person_id.is_empty() or not action_detail_id.is_empty()
	var rect := Rect2((size.x - width) * 0.5, 58.0 if modal_open else 618.0, width, 36.0)
	_surface(rect, Color(0.025, 0.055, 0.06, 0.97), Color(AMBER, 0.42), 18)
	_text(rect.position + Vector2(19.0, 23.0), _toast, 12, INK)


func _draw_tooltip() -> void:
	var lines: PackedStringArray = _hover_tooltip.split("\n")
	var widest: float = 0.0
	for line: String in lines:
		widest = maxf(widest, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x)
	var width: float = clampf(widest + 28.0, 180.0, 470.0)
	var height: float = maxf(34.0, 18.0 + float(lines.size()) * 18.0)
	var position: Vector2 = _hover_position + Vector2(16.0, 18.0)
	position.x = minf(position.x, size.x - width - 12.0)
	position.y = minf(position.y, size.y - height - 12.0)
	var rect := Rect2(position, Vector2(width, height))
	_surface(rect, Color(0.018, 0.04, 0.045, 0.99), Color(GOLD, 0.32), 7)
	for index: int in range(lines.size()):
		_text(rect.position + Vector2(14.0, 22.0 + float(index) * 18.0), lines[index], 11, INK)


func _activate(action: String, payload: Variant) -> void:
	match action:
		"corner_country":
			open_panel_named("country")
		"corner_time":
			open_panel_named("time")
		"toggle_system_menu":
			system_menu_open = not system_menu_open
			if system_menu_open and open_panel == "time":
				close_panel(false)
			mode_menu_open = false
			queue_redraw()
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
			system_menu_open = false
			queue_redraw()
		"world_view":
			mode_menu_open = false
			system_menu_open = false
			world_view_requested.emit()
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
			person_more_menu_open = false
			queue_redraw()
		"close_person_detail":
			detail_person_id = ""
			person_detail_level = 0
			person_more_menu_open = false
			queue_redraw()
		"toggle_person_more":
			person_more_menu_open = not person_more_menu_open
			queue_redraw()
		"action_detail":
			action_detail_id = str(payload)
			queue_redraw()
		"close_action_detail":
			action_detail_id = ""
			queue_redraw()
		"toggle_pause":
			toggle_pause_command()
			if life_binding == null:
				_show_toast("静态原型：仅切换时间视觉状态")
		"pause":
			if life_binding != null:
				life_binding.set_paused(true)
			paused = true
			queue_redraw()
		"speed":
			speed = int(payload)
			paused = false
			if life_binding != null:
				life_binding.set_speed(speed)
			queue_redraw()
		"system_save":
			if life_binding != null:
				var save_result: V2LifeLoopResult = life_binding.save_review()
				_show_toast(("✓ " if save_result.success else "× ") + save_result.user_message)
			else:
				_show_toast("保存仅为视觉占位 · 原型不写入 user://")
		"system_load":
			if life_binding != null:
				var load_result: V2LifeLoopResult = life_binding.load_review()
				_show_toast(("✓ " if load_result.success else "× ") + load_result.user_message)
		"system_settings":
			_show_toast("设置入口为静态占位")
		"system_return":
			_show_toast("独立原型不连接正式菜单")
		"open_schedule":
			open_panel_named("schedule")
		"schedule_activity":
			if life_binding != null:
				var proposal: V2LifeLoopResult = life_binding.activity_proposal(
					str(payload)
				)
				if proposal.success:
					schedule_form = proposal.data.duplicate(true)
					_show_toast("✓ 已载入建议时间，可调整后确认")
				else:
					schedule_form.clear()
					life_binding.last_command_result = proposal
					_show_toast("× " + proposal.user_message)
				queue_redraw()
		"schedule_adjust":
			if not schedule_form.is_empty():
				var adjustment: int = int(payload)
				if absi(adjustment) == 1001:
					var duration_delta: int = 1 if adjustment > 0 else -1
					schedule_form["duration_hours"] = clampi(
						int(schedule_form.get("duration_hours", 1))
						+ duration_delta,
						1,
						12
					)
				else:
					schedule_form["start_hour"] = maxi(
						life_binding.simulation.clock.total_hours,
						int(schedule_form.get("start_hour", 0)) + adjustment
					)
				queue_redraw()
		"schedule_confirm":
			if life_binding != null and not schedule_form.is_empty():
				var confirmed: V2LifeLoopResult = life_binding.submit_activity(
					str(schedule_form.get("activity_type", "")),
					int(schedule_form.get("start_hour", -1)),
					int(schedule_form.get("duration_hours", 1))
				)
				_show_toast(("✓ " if confirmed.success else "× ") + confirmed.user_message)
				if confirmed.success:
					schedule_form.clear()
				queue_redraw()
		"schedule_cancel_edit":
			schedule_form.clear()
			queue_redraw()
		"schedule_cancel_activity":
			if life_binding != null:
				var cancelled: V2LifeLoopResult = life_binding.cancel_activity(
					str(payload)
				)
				_show_toast(
					("✓ " if cancelled.success else "× ")
					+ cancelled.user_message
				)
		"open_developer":
			system_menu_open = false
			if life_binding != null and (review_mode or life_binding.developer_mode):
				open_panel_named("developer")
			else:
				_show_toast("开发者工具只在评审或开发者模式可用")
		"developer_command":
			if life_binding != null:
				var developer_result: V2LifeLoopResult = life_binding.developer_command(str(payload))
				_show_toast(("✓ " if developer_result.success else "× ") + developer_result.user_message)
		"person_action":
			person_more_menu_open = false
			if life_binding != null and str(payload) == "联系":
				var contact_result: V2LifeLoopResult = life_binding.schedule_next("social_contact")
				_show_toast(("✓ " if contact_result.success else "× ") + contact_result.user_message)
			else:
				_show_toast("%s · 静态关系行为入口" % str(payload))
		"organization_action", "context_action", "object_action", "activity_item":
			_show_toast("%s · 静态上下文入口" % str(payload if payload != null else "更多"))
		_:
			pass


func _identity_data() -> Dictionary:
	if life_binding != null:
		return life_binding.person_view()
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
	if life_binding != null and person_id == "jeanne":
		var static_record: Dictionary = {}
		for relation_variant: Variant in data.get_document("relationships").get("relationships", []):
			var candidate: Dictionary = relation_variant as Dictionary
			if str(candidate.get("id", "")) == person_id:
				static_record = candidate.duplicate(true)
				break
		var live: Dictionary = (
			life_binding.person_view().get("relationship", {}) as Dictionary
		)
		if not live.is_empty():
			static_record["familiarity"] = "%d/1000" % int(live.get("familiarity", 0))
			static_record["trust"] = "%d/1000" % int(live.get("trust", 0))
			static_record["last_interaction"] = str(
				live.get("last_contact_datetime", "尚未联系")
			)
		return static_record
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


func _draw_status_indicator(rect: Rect2, indicator: Dictionary) -> void:
	var symbol: String = str(indicator.get("symbol", "!"))
	var color: Color = GREEN if symbol == "✓" else (RED if symbol == "×" else AMBER)
	_surface(rect, Color(color, 0.08), Color(color, 0.32), 7)
	_text(rect.position + Vector2(8.0, 20.0), symbol, 16, color)
	_text(rect.position + Vector2(31.0, 19.0), str(indicator.get("label", "状态")), 10, INK)
	var tooltip: String = "当前状态：%s\n主要原因：%s\n近期趋势：%s\n可能影响：%s\n建议处理：%s" % [str(indicator.get("state", "")), str(indicator.get("reason", "")), str(indicator.get("trend", "")), str(indicator.get("impact", "")), str(indicator.get("suggestion", ""))]
	_register(rect, "consume", null, tooltip)


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
	_text(rect.position + Vector2(9.0, 19.0), "…", 16, INK_MUTED)
	_register(rect, "toggle_person_more", "更多", tooltip)


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


func _on_life_view_changed() -> void:
	if life_binding == null:
		return
	var time: Dictionary = life_binding.time_view()
	paused = bool(time.get("paused", true))
	speed = int(time.get("speed", 1))
	identity = life_binding.identity_id()
	queue_redraw()


static func _source_label(source: String) -> String:
	var labels: Dictionary = {
		"contract": "合同",
		"default_routine": "默认",
		"player": "玩家",
		"npc_rule": "NPC规则",
		"system": "系统",
	}
	return str(labels.get(source, source))


static func _schedule_status_label(status: String) -> String:
	var labels: Dictionary = {
		"completed": "已完成",
		"active": "正在进行",
		"planned": "计划",
		"missed": "缺勤",
		"cancelled": "取消",
	}
	return str(labels.get(status, status))
