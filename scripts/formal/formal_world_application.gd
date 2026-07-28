class_name FormalWorldApplication
extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
## Formal product scene: historical hemisphere, country navigation and the
## authoritative country-level economy share one clock and one save state.

var formal_simulation := FormalWorldSimulation.new()
var economy_panel_open: bool = true
var _formal_status: String = ""
var _last_summary: Dictionary = {}


func _ready() -> void:
	super._ready()
	if not formal_simulation.initialize():
		_formal_status = "正式世界经济初始化失败：%s" % formal_simulation.initialization_error
		_data_errors.append(_formal_status)
	else:
		_last_summary = formal_simulation.world_summary()
		_formal_status = "50国历史经济已接入；E 打开经济账，F5保存，F9读取。"
	queue_redraw()


func _on_clock_timer_timeout() -> void:
	if sim_paused:
		return
	var minutes := 15 * sim_speed
	_advance_clock(minutes)
	if formal_simulation.initialized:
		_last_summary = formal_simulation.advance_minutes(minutes)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_E:
				economy_panel_open = not economy_panel_open
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_F5:
				_formal_status = "正式世界已保存。" if formal_simulation.save_to_user() else "正式世界保存失败。"
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_F9:
				_formal_status = "正式世界存档已恢复。" if formal_simulation.load_from_user() else "没有可恢复的正式世界存档。"
				_last_summary = formal_simulation.world_summary()
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
	super._unhandled_key_input(event)


func _draw() -> void:
	super._draw()
	_draw_formal_economy_status()
	if economy_panel_open:
		_draw_formal_economy_panel()


func _draw_formal_economy_status() -> void:
	var size := get_viewport_rect().size
	var rect := Rect2(330.0, size.y - 54.0, maxf(260.0, size.x - 660.0), 36.0)
	_panel(rect, Color(0.018, 0.038, 0.043, 0.94), Color(0.70, 0.62, 0.39, 0.34))
	var fulfillment := int(_last_summary.get("fulfillment_bp", 0))
	var text := "世界经济  国家 %d  商品 %d  航路 %d  在途 %d  需求满足 %.1f%%" % [
		int(_last_summary.get("country_count", 0)),
		int(_last_summary.get("commodity_count", 0)),
		int(_last_summary.get("route_count", 0)),
		int(_last_summary.get("active_shipments", 0)),
		float(fulfillment) / 100.0,
	]
	_draw_label(rect.position + Vector2(14.0, 23.0), text, 10, Color(0.88, 0.88, 0.77, 0.98))
	_draw_button(Rect2(rect.end.x - 82.0, rect.position.y + 5.0, 72.0, 26.0), "经济账 E", "formal_economy_toggle", true)


func _draw_formal_economy_panel() -> void:
	var size := get_viewport_rect().size
	var width := clampf(size.x * 0.30, 330.0, 430.0)
	var rect := Rect2(size.x - width - 18.0, 92.0, width, size.y - 170.0)
	_panel(rect, Color(0.014, 0.031, 0.037, 0.975), Color(0.78, 0.66, 0.38, 0.44))
	_draw_label(rect.position + Vector2(20.0, 31.0), "正式世界经济", 17, Color(0.95, 0.88, 0.67, 1.0))
	_draw_label(
		rect.position + Vector2(20.0, 54.0),
		"真实政治实体与有界历史估算；未验证维度不会被标成已验证。",
		9,
		Color(0.76, 0.81, 0.78, 0.95)
	)
	var selected_id := _selected_economy_entity_id()
	var country := formal_simulation.country_summary(selected_id)
	var y := 86.0
	if country.is_empty():
		_draw_label(rect.position + Vector2(20.0, y), "在半球上选择政治实体以查看国家经济。", 11)
		y += 30.0
	else:
		var entity := _history_entity_by_id.get(selected_id, {}) as Dictionary
		_draw_label(rect.position + Vector2(20.0, y), str(entity.get("name_zh", selected_id)), 14)
		y += 25.0
		var totals := country.get("daily_totals", {}) as Dictionary
		var lines: Array[String] = [
			"人口：%s" % _compact_integer(int(country.get("population", 0))),
			"人均产出锚：%d（2011国际元口径）" % int(country.get("income_per_capita", 0)),
			"城市化率：%.1f%%" % (float(country.get("urban_share_bp", 0)) / 100.0),
			"综合置信度：%.1f%% · %s" % [float(country.get("overall_confidence_bp", 0)) / 100.0, str(country.get("admission_status", "bounded_estimate"))],
			"当日满足率：%.1f%%" % (float(totals.get("fulfillment_bp", 0)) / 100.0),
			"关联在途运输：%d" % int(country.get("active_shipments", 0)),
		]
		for line: String in lines:
			_draw_label(rect.position + Vector2(20.0, y), line, 10, Color(0.86, 0.87, 0.80, 0.98))
			y += 20.0
		y += 6.0
		_draw_label(rect.position + Vector2(20.0, y), "主要短缺", 11, Color(0.95, 0.76, 0.43, 1.0))
		y += 21.0
		var shortages := country.get("top_shortages", []) as Array
		if shortages.is_empty():
			_draw_label(rect.position + Vector2(20.0, y), "当前没有显著未满足需求。", 9, Color(0.70, 0.78, 0.73, 0.95))
			y += 20.0
		else:
			for index: int in range(mini(6, shortages.size())):
				var shortage := shortages[index] as Dictionary
				_draw_label(
					rect.position + Vector2(20.0, y),
					"%s  缺口 %.1f" % [str(shortage.get("name_zh", shortage.get("commodity_id", ""))), float(shortage.get("unmet", 0.0))],
					9,
					Color(0.91, 0.67, 0.48, 0.98)
				)
				y += 18.0
	var button_y := rect.end.y - 38.0
	_draw_button(Rect2(rect.position.x + 18.0, button_y, 84.0, 26.0), "保存 F5", "formal_save", true)
	_draw_button(Rect2(rect.position.x + 110.0, button_y, 84.0, 26.0), "读取 F9", "formal_load", true)
	_draw_button(Rect2(rect.end.x - 88.0, button_y, 70.0, 26.0), "关闭", "formal_economy_toggle", true)
	if not _formal_status.is_empty():
		_draw_label(rect.position + Vector2(20.0, rect.size.y - 51.0), _formal_status, 8, Color(0.72, 0.78, 0.72, 0.92), rect.size.x - 40.0)


func _activate_button(action: String) -> void:
	if action == "formal_economy_toggle":
		economy_panel_open = not economy_panel_open
		queue_redraw()
		return
	if action == "formal_save":
		_formal_status = "正式世界已保存。" if formal_simulation.save_to_user() else "正式世界保存失败。"
		queue_redraw()
		return
	if action == "formal_load":
		_formal_status = "正式世界存档已恢复。" if formal_simulation.load_from_user() else "没有可恢复的正式世界存档。"
		_last_summary = formal_simulation.world_summary()
		queue_redraw()
		return
	super._activate_button(action)


func _selected_economy_entity_id() -> String:
	if not selected_country_id.is_empty() and formal_simulation.economy.country_states.has(selected_country_id):
		return selected_country_id
	var home_id := _home_historical_entity_id()
	if formal_simulation.economy.country_states.has(home_id):
		return home_id
	if formal_simulation.economy.country_states.has("country_fra"):
		return "country_fra"
	var ids: Array = formal_simulation.economy.country_states.keys()
	return str(ids[0]) if not ids.is_empty() else ""


func _compact_integer(value: int) -> String:
	if value >= 1000000000:
		return "%.2f十亿" % (float(value) / 1000000000.0)
	if value >= 1000000:
		return "%.2f百万" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1f千" % (float(value) / 1000.0)
	return str(value)
