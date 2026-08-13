class_name FormalWorldApplication
extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
## Formal product scene: the complete dated political world is the map authority.
## Fifty ranked polities receive high-detail economy; all remaining political
## units stay visible as background/non-player world actors.

const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
const PACKAGED_PROBE_ARGUMENT: String = "--wwo-player-baseline-probe"
const PACKAGED_PROBE_ENTITY_ID: String = "country_fra"
const PACKAGED_PROBE_FLAG_ID: String = "france_tricolour_1794"

var formal_simulation := FormalWorldSimulation.new()
var economy_panel_open: bool = true
var _formal_status: String = ""
var _last_summary: Dictionary = {}
var _packaged_probe_failures: int = 0


func _ready() -> void:
	super._ready()
	if not formal_simulation.initialize():
		_formal_status = "正式世界初始化失败：%s" % formal_simulation.initialization_error
		_data_errors.append(_formal_status)
	else:
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
	if PACKAGED_PROBE_ARGUMENT in OS.get_cmdline_user_args():
		_run_packaged_player_baseline_probe.call_deferred()


func _run_packaged_player_baseline_probe() -> void:
	await get_tree().process_frame
	_packaged_probe_require(formal_simulation.initialized, "正式模拟未初始化")
	_packaged_probe_require(_data_errors.is_empty(), "正式模拟产生数据错误")
	_packaged_probe_require(_history_entity_by_id.size() == 151, "历史政治单元数量不正确")
	_packaged_probe_require(_missing_flag_record_ids.is_empty(), "历史旗帜资源存在缺失")
	var evidence := historical_evidence_report()
	_packaged_probe_require(
		int(evidence.get("unresolved_flag_count", -1)) == 0,
		"历史旗帜证据仍未完全解析"
	)

	_ensure_projection_cache()
	var france_point := _country_screen_anchors.get(PACKAGED_PROBE_ENTITY_ID, Vector2.INF) as Vector2
	_packaged_probe_require(
		france_point != Vector2.INF,
		"默认半球视角没有法兰西选择锚点"
	)
	if france_point != Vector2.INF:
		_packaged_probe_mouse_button(france_point, true)
		_packaged_probe_mouse_button(france_point, false)
	await get_tree().process_frame
	_packaged_probe_require(
		selected_country_id == PACKAGED_PROBE_ENTITY_ID,
		"打包产品地图点击未选择法兰西政治单元"
	)
	_packaged_probe_require(info_open, "打包产品实体选择没有打开详情反馈")
	_packaged_probe_require(
		not formal_simulation.polity_summary(PACKAGED_PROBE_ENTITY_ID).is_empty(),
		"打包产品选中实体没有政经详情"
	)
	var imported_flags := _historical_imported_flag_texture_by_id as Dictionary
	_packaged_probe_require(
		imported_flags.get(PACKAGED_PROBE_FLAG_ID) is Texture2D,
		"打包产品没有通过导入Texture2D解析法兰西历史旗帜"
	)

	var date_before := _format_sim_datetime()
	_packaged_probe_require(
		await _packaged_probe_click_action("toggle_time_panel"),
		"打包产品时间面板入口不可点击"
	)
	_packaged_probe_require(
		await _packaged_probe_click_action("speed:4"),
		"打包产品4倍速控件不可点击"
	)
	var clock := get_node("ClockTimer") as Timer
	for _index: int in range(24):
		clock.timeout.emit()
	await get_tree().process_frame
	_packaged_probe_require(
		_format_sim_datetime() != date_before,
		"打包产品时间推进没有改变可见日期"
	)
	_packaged_probe_require(
		await _packaged_probe_click_action("toggle_pause"),
		"打包产品暂停控件不可点击"
	)
	_packaged_probe_require(sim_paused, "打包产品暂停控件未暂停正式时间")

	if _packaged_probe_failures > 0:
		push_error(
			"Packaged player baseline probe: %d failures" % _packaged_probe_failures
		)
	else:
		print("Packaged player baseline probe: title, world, polity, resource, and time passed")
	get_tree().quit(1 if _packaged_probe_failures > 0 else 0)


func _packaged_probe_click_action(action: String) -> bool:
	queue_redraw()
	for _index: int in range(3):
		await get_tree().process_frame
	for index: int in range(_button_hits.size() - 1, -1, -1):
		var record: Dictionary = _button_hits[index]
		if str(record.get("action", "")) != action or not bool(record.get("enabled", false)):
			continue
		var rect: Rect2 = record.get("rect", Rect2()) as Rect2
		_packaged_probe_mouse_button(rect.get_center(), true)
		_packaged_probe_mouse_button(rect.get_center(), false)
		await get_tree().process_frame
		return true
	return false


func _packaged_probe_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	_gui_input(event)


func _packaged_probe_require(condition: bool, message: String) -> void:
	if condition:
		return
	_packaged_probe_failures += 1
	push_error("Packaged player baseline probe: " + message)


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
	if economy_panel_open:
		_draw_formal_polity_panel()


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
