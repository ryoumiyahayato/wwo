class_name FormalWorldApplication
extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
## Formal product scene: the complete dated political world is the map authority.
## Fifty ranked polities receive high-detail economy; all remaining political
## units stay visible as background/non-player world actors.

const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"

var formal_simulation := FormalWorldSimulation.new()
var economy_panel_open: bool = true
var vertical_slice_panel_open: bool = true
var _formal_status: String = ""
var _last_summary: Dictionary = {}


func _ready() -> void:
	super._ready()
	if not formal_simulation.initialize():
		_formal_status = "正式世界初始化失败：%s" % formal_simulation.initialization_error
		_data_errors.append(_formal_status)
	else:
		_bind_formal_player_surface()
		var launch_mode := str(get_tree().get_meta(LAUNCH_MODE_META, "new"))
		if get_tree().has_meta(LAUNCH_MODE_META):
			get_tree().remove_meta(LAUNCH_MODE_META)
		if launch_mode == "load":
			var result := _load_formal_state()
			_formal_status = result.message
			if _formal_status.is_empty():
				_formal_status = (
					"正式世界存档已恢复。"
					if result.success
					else "正式世界存档恢复失败；当前状态保持1900-01-01 00:00。"
				)
		else:
			_formal_status = "新的1900正式世界已建立。"
		_last_summary = formal_simulation.world_summary()
	queue_redraw()


func _bind_formal_player_surface() -> void:
	var player := formal_simulation.player_summary()
	var employment := player.get("employment", {}) as Dictionary
	var profile := {
		"id": str(player.get("person_id", "")),
		"name": str(player.get("name_zh", "")),
		"display_name_zh": str(player.get("name_zh", "")),
		"nationality_id": str(player.get("country_id", "country_fra")),
		"occupation": str(player.get("position_title_zh", "")),
		"role": str(player.get("position_title_zh", "")),
		"organization_position": str(player.get("position_title_zh", "")),
		"position": str(player.get("position_title_zh", "")),
		"city_id": str(player.get("city_id", "")),
		"workplace_city_id": str(player.get("city_id", "")),
		"region_id": str(player.get("region_id", "")),
		"region": "%s · %s" % [
			str(player.get("region_name_zh", "")),
			str(player.get("city_name_zh", "")),
		],
		"current_work": str(employment.get("workplace_name_zh", "")),
		"plan": "缓解埃及面包缺口并协调马赛—亚历山大港运输",
		"primary_concern": "埃及粮食短缺与地中海航运时效",
		"access_summary": "组织成员、雇佣与岗位授权分别来自正式权威状态",
	}
	_character_profiles = {"formal_player": profile}
	active_character_key = "formal_player"


func _advance_simulation_minutes(minutes: int) -> void:
	if formal_simulation.initialized and minutes > 0:
		_last_summary = formal_simulation.advance_minutes(minutes)


func _format_sim_datetime() -> String:
	var value := formal_simulation.date_time()
	if value.is_empty():
		return "无效时间"
	return "%04d年%02d月%02d日 %02d:%02d" % [
		int(value.get("year", 0)),
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
	]


func _time_source_description() -> String:
	return "正式模拟权威时间；半球与HUD仅派生显示"


func _load_formal_state() -> SaveOperationResult:
	var result := formal_simulation.load_from_user()
	if result.success:
		_last_summary = formal_simulation.world_summary()
	return result


func _toggle_formal_economy_panel() -> void:
	economy_panel_open = not economy_panel_open
	queue_redraw()


func _save_formal_state_from_ui() -> void:
	var result := formal_simulation.save_to_user()
	_formal_status = result.message
	if _formal_status.is_empty():
		_formal_status = (
			"正式世界已保存。"
			if result.success
			else "正式世界保存失败。"
		)
	queue_redraw()


func _load_formal_state_from_ui() -> void:
	var result := formal_simulation.load_from_user()
	_formal_status = result.message
	if _formal_status.is_empty():
		_formal_status = (
			"正式世界存档已恢复。"
			if result.success
			else "没有可恢复的正式世界存档。"
		)
	if result.success:
		_last_summary = formal_simulation.world_summary()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		super._unhandled_key_input(event)
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		super._unhandled_key_input(event)
		return

	match key_event.keycode:
		KEY_E:
			_toggle_formal_economy_panel()
		KEY_F5:
			_save_formal_state_from_ui()
		KEY_F9:
			_load_formal_state_from_ui()
		_:
			super._unhandled_key_input(event)
			return

	get_viewport().set_input_as_handled()


func _draw() -> void:
	super._draw()
	_draw_formal_world_status()
	if vertical_slice_panel_open:
		_draw_vertical_slice_panel()
	if economy_panel_open:
		_draw_formal_polity_panel()


func _draw_vertical_slice_panel() -> void:
	var size := get_viewport_rect().size
	var rect := Rect2(18.0, 92.0, 365.0, size.y - 170.0)
	_panel(
		rect,
		Color(0.014, 0.031, 0.037, 0.975),
		Color(0.40, 0.73, 0.63, 0.52)
	)
	var summary := formal_simulation.vertical_slice_summary()
	var player := summary.get("player", {}) as Dictionary
	var destination := summary.get("destination", {}) as Dictionary
	var route := summary.get("route", {}) as Dictionary
	var shipment := summary.get("shipment", {}) as Dictionary
	var decision := summary.get("decision", {}) as Dictionary
	var last_action := decision.get("last_action", {}) as Dictionary
	_draw_label(
		rect.position + Vector2(18.0, 29.0),
		"地中海粮食供应任务",
		17,
		Color(0.83, 0.96, 0.82, 1.0)
	)
	_draw_label(
		rect.position + Vector2(18.0, 51.0),
		"法国 · 地中海沿岸 · 马赛港",
		9,
		Color(0.70, 0.83, 0.78, 0.96)
	)
	var y := 78.0
	_draw_label(rect.position + Vector2(18.0, y), "你的职位与授权", 12)
	y += 19.0
	y = _draw_panel_lines(rect, y, [
		"人物：%s" % str(player.get("name_zh", "")),
		"雇佣：%s" % str(
			(player.get("employment", {}) as Dictionary).get(
				"workplace_name_zh", ""
			)
		),
		"组织成员：%s" % str(player.get("organization_name_zh", "")),
		"岗位：%s" % str(player.get("position_title_zh", "")),
		"授权：%s · %s" % [
			"有效" if bool(player.get("authorized", false)) else "无效",
			str(player.get("capability_id", "")),
		],
	], Color(0.83, 0.88, 0.82, 0.98), 9)
	y += 4.0
	_draw_label(rect.position + Vector2(18.0, y), "观察到的供应问题", 12)
	y += 19.0
	var demand := float(destination.get("demand_units", 0.0))
	var unmet := float(destination.get("unmet_units", 0.0))
	var problem_text := (
		"尚未形成日结算；推进到运输计划出现。"
		if demand <= 0.0
		else "埃及面包：需求 %.1f · 缺口 %.1f" % [demand, unmet]
	)
	y = _draw_panel_lines(rect, y, [
		problem_text,
		"库存 %.1f · 生产 %.1f · 价格 %d 生丁" % [
			float(destination.get("inventory_units", 0.0)),
			float(destination.get("produced_units", 0.0)),
			int(destination.get("price_centimes", 0)),
		],
		"地区综合满足率：%.1f%%" % (
			float(destination.get("fulfillment_bp", 0)) / 100.0
		),
	], Color(0.96, 0.79, 0.55, 0.98), 9)
	y += 4.0
	_draw_label(rect.position + Vector2(18.0, y), "真实运输路线", 12)
	y += 19.0
	y = _draw_panel_lines(rect, y, [
		"%s → %s · %s" % [
			str(route.get("origin_port", "马赛")),
			str(route.get("destination_port", "亚历山大港")),
			_mode_name(str(route.get("mode", ""))),
		],
		"路线 %s · 容量 %.0f 单位/日 · 标准 %d 日" % [
			str(route.get("route_id", "")),
			float(route.get("capacity_units_per_day", 0.0)),
			int(route.get("duration_hours", 0)) / 24,
		],
	], Color(0.72, 0.87, 0.91, 0.98), 9)
	var shipment_status := str(summary.get("shipment_status", "not_scheduled"))
	var shipment_line := "运输：尚未排定"
	if shipment_status == "in_transit":
		shipment_line = "运输：%.1f 面包 · ETA %d 小时 · 进度 %.1f%%" % [
			float(shipment.get("units", 0.0)),
			int(summary.get("eta_hours", -1)),
			float(summary.get("progress_bp", 0)) / 100.0,
		]
	elif shipment_status == "delivered":
		shipment_line = "运输：已抵达 · 进度 100.0%"
	_draw_label(
		rect.position + Vector2(18.0, y + 4.0),
		shipment_line,
		9,
		Color(0.76, 0.92, 0.78, 1.0)
	)
	if not last_action.is_empty():
		_draw_label(
			rect.position + Vector2(18.0, y + 23.0),
			"已授权：ETA 提前 1 日；到货后对比缺口 %.1f。" % float(
				last_action.get("unmet_before", 0.0)
			),
			8,
			Color(0.87, 0.91, 0.66, 0.98)
		)
	var row_one_y := rect.end.y - 73.0
	_draw_button(
		Rect2(rect.position.x + 16.0, row_one_y, 126.0, 28.0),
		"定位地中海沿岸",
		"vertical_slice_locate",
		true
	)
	_draw_button(
		Rect2(rect.position.x + 150.0, row_one_y, 78.0, 28.0),
		"推进1日",
		"vertical_slice_day",
		true
	)
	_draw_button(
		Rect2(rect.position.x + 236.0, row_one_y, 78.0, 28.0),
		"推进7日",
		"vertical_slice_week",
		true
	)
	var action_used := not last_action.is_empty()
	var can_authorize := (
		bool(player.get("authorized", false))
		and space_level == REGION
		and selected_region_id == "mediterranean_coast"
		and shipment_status == "in_transit"
		and not action_used
	)
	_draw_button(
		Rect2(rect.position.x + 16.0, rect.end.y - 38.0, 208.0, 28.0),
		"已批准优先通关" if action_used else "批准面包运输优先通关",
		"vertical_slice_authorize",
		can_authorize
	)
	_draw_button(
		Rect2(rect.position.x + 232.0, rect.end.y - 38.0, 82.0, 28.0),
		"保存 F5",
		"formal_save",
		true
	)


func _mode_name(mode: String) -> String:
	match mode:
		"steamship": return "蒸汽船"
		"river": return "河运"
		_: return mode


func _locate_vertical_slice_region() -> void:
	selected_country_id = "country_fra"
	_focus_selected_country()
	selected_region_id = "mediterranean_coast"
	_enter_region()
	_formal_status = "已定位法国地中海沿岸与马赛港供应任务。"
	queue_redraw()


func _advance_vertical_slice_days(days: int) -> void:
	if days <= 0:
		return
	_last_summary = formal_simulation.advance_minutes(days * 24 * 60)
	_formal_status = "正式时间已推进 %d 日。" % days
	queue_redraw()


func _authorize_vertical_slice_transport() -> void:
	var result := formal_simulation.authorize_supply_transport_priority()
	_formal_status = str(result.get("message", "运输授权失败。"))
	_last_summary = formal_simulation.world_summary()
	queue_redraw()


func _draw_formal_world_status() -> void:
	var size := get_viewport_rect().size
	var rect := Rect2(330.0, size.y - 54.0, maxf(260.0, size.x - 660.0), 36.0)
	_panel(
		rect,
		Color(0.018, 0.038, 0.043, 0.94),
		Color(0.70, 0.62, 0.39, 0.34)
	)
	var fulfillment := int(_last_summary.get("fulfillment_bp", 0))
	var text := "1900世界  政治单元 %d  高细节经济 %d  核心可玩 %d  背景单元 %d  满足 %.1f%%" % [
		int(_last_summary.get("world_political_unit_count", 0)),
		int(_last_summary.get("major_economy_count", 0)),
		int(_last_summary.get("primary_playable_count", 0)),
		int(_last_summary.get("background_polity_count", 0)),
		float(fulfillment) / 100.0,
	]
	_draw_label(
		rect.position + Vector2(14.0, 23.0),
		text,
		10,
		Color(0.88, 0.88, 0.77, 0.98)
	)
	_draw_button(
		Rect2(rect.end.x - 82.0, rect.position.y + 5.0, 72.0, 26.0),
		"政经 E",
		"formal_economy_toggle",
		true
	)


func _draw_formal_polity_panel() -> void:
	var size := get_viewport_rect().size
	var width := clampf(size.x * 0.30, 330.0, 430.0)
	var rect := Rect2(size.x - width - 18.0, 92.0, width, size.y - 170.0)
	_panel(
		rect,
		Color(0.014, 0.031, 0.037, 0.975),
		Color(0.78, 0.66, 0.38, 0.44)
	)
	_draw_formal_panel_header(rect)
	var selected_id := _selected_polity_entity_id()
	var polity := formal_simulation.polity_summary(selected_id)
	_draw_polity_content(rect, selected_id, polity)
	_draw_formal_panel_buttons(rect)


func _draw_formal_panel_header(rect: Rect2) -> void:
	_draw_label(
		rect.position + Vector2(20.0, 31.0),
		"正式世界政经",
		17,
		Color(0.95, 0.88, 0.67, 1.0)
	)
	_draw_label(
		rect.position + Vector2(20.0, 54.0),
		"151个历史政治单元共同构成世界；50个主要政权使用高细节经济。",
		9,
		Color(0.76, 0.81, 0.78, 0.95)
	)


func _draw_polity_content(
	rect: Rect2, selected_id: String, polity: Dictionary
) -> void:
	var y := 86.0
	if polity.is_empty():
		_draw_label(
			rect.position + Vector2(20.0, y),
			"在半球上选择政治单元。",
			11
		)
		return
	_draw_label(
		rect.position + Vector2(20.0, y),
		str(polity.get("name_zh", polity.get("short_name_zh", selected_id))),
		14
	)
	y += 24.0
	var polity_lines: Array[String] = [
		"层级：%s" % str(polity.get("playability_tier_zh", "背景政治单元")),
		"地位：%s · %s" % [
			str(polity.get("status", "unknown")),
			str(polity.get("relationship", "")),
		],
	]
	var controller_id := str(polity.get("controller_id", ""))
	if not controller_id.is_empty():
		polity_lines.append("控制方：%s" % controller_id)
	y = _draw_panel_lines(
		rect,
		y,
		polity_lines,
		Color(0.82, 0.84, 0.78, 0.96),
		10
	)
	y += 5.0
	if bool(polity.get("has_detailed_economy", false)):
		_draw_detailed_economy(rect, y, polity.get("economy", {}) as Dictionary)
	else:
		_draw_background_polity_notice(rect, y)


func _draw_detailed_economy(
	rect: Rect2, y: float, country: Dictionary
) -> void:
	var totals := country.get("daily_totals", {}) as Dictionary
	var economy_lines: Array[String] = [
		"主要政权序位：%d" % int(country.get("rank", 0)),
		"人口：%s" % _compact_integer(int(country.get("population", 0))),
		"人均产出锚：%d（2011国际元口径）" % int(
			country.get("income_per_capita", 0)
		),
		"城市化率：%.1f%%" % (
			float(country.get("urban_share_bp", 0)) / 100.0
		),
		"数据状态：%.1f%% · %s" % [
			float(country.get("overall_confidence_bp", 0)) / 100.0,
			str(country.get("admission_status", "bounded_estimate")),
		],
		"当日满足率：%.1f%%" % (
			float(totals.get("fulfillment_bp", 0)) / 100.0
		),
		"关联在途运输：%d" % int(country.get("active_shipments", 0)),
	]
	_draw_panel_lines(
		rect,
		y,
		economy_lines,
		Color(0.86, 0.87, 0.80, 0.98),
		10
	)


func _draw_background_polity_notice(rect: Rect2, y: float) -> void:
	_draw_label(
		rect.position + Vector2(20.0, y),
		"该单元属于背景世界：保留边界、归属与外交存在，不运行高细节经济。",
		9,
		Color(0.91, 0.70, 0.45, 0.98)
	)


func _draw_panel_lines(
	rect: Rect2,
	y: float,
	lines: Array[String],
	color: Color,
	font_size: int
) -> float:
	for line: String in lines:
		_draw_label(
			rect.position + Vector2(20.0, y),
			line,
			font_size,
			color
		)
		y += 19.0
	return y


func _draw_formal_panel_buttons(rect: Rect2) -> void:
	var button_y := rect.end.y - 38.0
	_draw_button(
		Rect2(rect.position.x + 18.0, button_y, 84.0, 26.0),
		"保存 F5",
		"formal_save",
		true
	)
	_draw_button(
		Rect2(rect.position.x + 110.0, button_y, 84.0, 26.0),
		"读取 F9",
		"formal_load",
		true
	)
	_draw_button(
		Rect2(rect.end.x - 88.0, button_y, 70.0, 26.0),
		"关闭",
		"formal_economy_toggle",
		true
	)
	if not _formal_status.is_empty():
		_draw_label(
			rect.position + Vector2(20.0, rect.size.y - 51.0),
			_formal_status,
			8,
			Color(0.72, 0.78, 0.72, 0.92)
		)


func _activate_button(action: String) -> void:
	match action:
		"vertical_slice_locate":
			_locate_vertical_slice_region()
		"vertical_slice_day":
			_advance_vertical_slice_days(1)
		"vertical_slice_week":
			_advance_vertical_slice_days(7)
		"vertical_slice_authorize":
			_authorize_vertical_slice_transport()
		"formal_economy_toggle":
			_toggle_formal_economy_panel()
		"formal_save":
			_save_formal_state_from_ui()
		"formal_load":
			_load_formal_state_from_ui()
		_:
			super._activate_button(action)


func _selected_polity_entity_id() -> String:
	if formal_simulation.has_polity(selected_country_id):
		return selected_country_id

	var home_id := _home_historical_entity_id()
	if formal_simulation.has_polity(home_id):
		return home_id

	if formal_simulation.has_polity("country_fra"):
		return "country_fra"

	return formal_simulation.first_polity_id()


func _compact_integer(value: int) -> String:
	if value >= 1000000000:
		return "%.2f十亿" % (float(value) / 1000000000.0)
	if value >= 1000000:
		return "%.2f百万" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1f千" % (float(value) / 1000.0)
	return str(value)
