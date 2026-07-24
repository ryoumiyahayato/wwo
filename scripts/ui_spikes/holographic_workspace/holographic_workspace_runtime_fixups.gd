extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_spike.gd"


func _focus_selected_country() -> void:
	if selected_country_id != FOCUS_COUNTRY_ID:
		return
	space_level = WORLD
	world_mode = WORLD_COUNTRY_FOCUS
	selected_event_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	hover_country_id = ""
	hover_event_id = ""
	hover_region_id = ""
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	_set_world_layer_visible(true)
	_set_info_open(false)
	_mark_projection_dirty()
	queue_redraw()


func _show_event_from_hud(event_id: String) -> void:
	if not _event_by_id.has(event_id):
		return
	active_hud_panel = ""
	space_level = WORLD
	world_mode = WORLD_COUNTRIES
	selected_event_id = event_id
	selected_country_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	hover_country_id = ""
	hover_event_id = ""
	hover_region_id = ""
	_set_world_layer_visible(true)
	_mark_projection_dirty()
	_set_info_open(true)
	queue_redraw()


func _draw_city_institutions(rect: Rect2) -> void:
	var institution_ids: Array = _institutions_by_city.get(selected_city_id, [])
	if institution_ids.is_empty():
		_draw_label(
			rect.position + Vector2(40.0, 126.0),
			"当前城市没有配置正式机构节点。",
			14,
			Color(0.95, 0.72, 0.43, 1.0)
		)
		return

	var node_positions: Dictionary = {}
	var columns := mini(3, maxi(1, institution_ids.size()))
	var row_count := int(ceil(float(institution_ids.size()) / float(columns)))
	var inner_left := rect.position.x + 96.0
	var inner_right := maxf(inner_left, rect.end.x - 96.0)
	var available_top := rect.position.y + 145.0
	var available_bottom := maxf(available_top, rect.end.y - 104.0)
	var row_step := 0.0
	if row_count > 1:
		row_step = (available_bottom - available_top) / float(row_count - 1)

	for index in range(institution_ids.size()):
		var column := index % columns
		var row := int(index / columns)
		var column_ratio := 0.5 if columns <= 1 else float(column) / float(columns - 1)
		node_positions[str(institution_ids[index])] = Vector2(
			lerpf(inner_left, inner_right, column_ratio),
			available_top + float(row) * row_step
		)

	for institution_id in institution_ids:
		var institution: Dictionary = _institution_by_id.get(str(institution_id), {})
		var parent_id := str(institution.get("parent_institution_id", ""))
		if node_positions.has(parent_id):
			draw_line(
				node_positions[parent_id],
				node_positions[str(institution_id)],
				Color(0.58, 0.70, 0.64, 0.34),
				1.8
			)

	for institution_id in institution_ids:
		var institution: Dictionary = _institution_by_id.get(str(institution_id), {})
		var point: Vector2 = node_positions[str(institution_id)]
		var node_rect := Rect2(point - Vector2(72.0, 28.0), Vector2(144.0, 56.0))
		_panel(node_rect, Color(0.08, 0.12, 0.115, 0.90), Color(0.74, 0.68, 0.44, 0.42))
		_draw_label(
			node_rect.position + Vector2(10.0, 23.0),
			_ellipsize(str(institution.get("name", "机构")), 18),
			12
		)
		_draw_label(
			node_rect.position + Vector2(10.0, 43.0),
			_ellipsize(str(institution.get("department", institution.get("institution_kind", ""))), 20),
			10,
			Color(0.72, 0.82, 0.76, 1.0)
		)
		_register_hit(node_rect, "inspect_institution:" + str(institution_id), true)


func _draw_city_characters(rect: Rect2) -> void:
	var x := rect.position.x + 34.0
	var y := rect.end.y - 54.0
	for key in _character_profiles.keys():
		var profile: Dictionary = _character_profiles[key]
		if str(profile.get("city_id", "")) != selected_city_id:
			continue
		if x + 210.0 > rect.end.x - 24.0:
			x = rect.position.x + 34.0
			y -= 38.0
		var badge := Rect2(x, y, 210.0, 30.0)
		_panel(badge, Color(0.07, 0.10, 0.095, 0.88), Color(0.54, 0.70, 0.63, 0.34))
		_draw_label(
			badge.position + Vector2(10.0, 20.0),
			_ellipsize(
				str(profile.get("display_name_zh", profile.get("name", "人物")))
				+ " · " + str(profile.get("position", "")),
				30
			),
			11
		)
		x += 222.0


func _main_content_rect(preferred_margin: float, top: float, bottom: float) -> Rect2:
	var margin := minf(preferred_margin, maxf(18.0, (size.x - 520.0) * 0.5))
	return Rect2(
		margin,
		top,
		maxf(240.0, size.x - margin * 2.0),
		maxf(220.0, size.y - top - bottom)
	)


func _draw_corner(rect: Rect2, title: String, subtitle: String, action: String, border: Color, compact: bool) -> void:
	_panel(rect, Color(0.025, 0.055, 0.06, 0.88), border)
	_register_hit(rect, action, true)
	_draw_label(rect.position + Vector2(14.0, 25.0), _ellipsize(title, 24), 14 if compact else 15)
	if not compact:
		_draw_label(
			rect.position + Vector2(14.0, 48.0),
			_ellipsize(subtitle, 30),
			10,
			Color(0.76, 0.67, 0.39, 1.0)
		)


func _draw_top_info() -> void:
	if info_progress <= 0.001:
		return
	var compact := size.x < 940.0
	var height := minf(size.y * 0.34, 218.0)
	var rect: Rect2
	if compact:
		rect = Rect2(18.0, 86.0, size.x - 36.0, height)
	else:
		rect = Rect2(318.0, 8.0, maxf(360.0, size.x - 636.0), height)
	var shown_y := rect.position.y
	rect.position.y = lerpf(-height - 12.0, shown_y, info_progress)
	_panel(rect, Color(0.018, 0.035, 0.038, 0.96), Color(0.78, 0.70, 0.46, 0.40))
	_register_hit(rect, "noop", true)

	var title := "空间对象"
	var path := _breadcrumb_text()
	var summary := ""
	var action_label := ""
	var action := ""
	var action_enabled := false

	if not selected_institution_id.is_empty():
		var institution: Dictionary = _institution_by_id.get(selected_institution_id, {})
		title = str(institution.get("name", "机构"))
		summary = str(institution.get("mandate", institution.get("agenda", "未配置摘要")))
	elif not selected_event_id.is_empty():
		var event: Dictionary = _event_by_id.get(selected_event_id, {})
		title = str(event.get("title", "状态"))
		path = "世界 / 状态 / " + str(event.get("source", "机构"))
		summary = "来源：" + str(event.get("source", "机构"))
		action_label = "定位地区"
		action = "locate_event"
		action_enabled = not str(event.get("region_id", "")).is_empty()
	elif world_mode == WORLD_COUNTRIES and not selected_country_id.is_empty():
		var country: Dictionary = _country_by_id.get(selected_country_id, {})
		title = str(country.get("name", "国家"))
		path = "世界 / " + title
		summary = "国家级空间对象 · ISO " + str(country.get("iso_a3", ""))
		action_label = "进入国家"
		action = "focus_country"
		action_enabled = selected_country_id == FOCUS_COUNTRY_ID
	elif not selected_region_id.is_empty():
		var region: Dictionary = _region_by_id.get(selected_region_id, {})
		title = str(region.get("display_name_zh", "大区"))
		path = "世界 / 法兰西第三共和国 / " + title
		summary = "人口：%s · %s" % [
			str(region.get("population", "未配置")),
			str(region.get("market", "未配置")),
		]
		action_label = "进入大区"
		action = "enter_region"
		action_enabled = true

	_draw_label(rect.position + Vector2(24.0, 34.0), _ellipsize(title, 36), 19)
	_draw_label(
		rect.position + Vector2(24.0, 60.0),
		_ellipsize(path, 54),
		11,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_label(rect.position + Vector2(24.0, 94.0), _ellipsize(summary, 68), 12)
	if not action.is_empty():
		_draw_button(
			Rect2(rect.end.x - 176.0, rect.end.y - 48.0, 128.0, 32.0),
			action_label,
			action,
			action_enabled
		)
	_draw_button(Rect2(rect.end.x - 42.0, rect.position.y + 10.0, 30.0, 26.0), "×", "close_info", true)


func _draw_country_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), str(_country_profile.get("formal_name_zh", "法兰西第三共和国")), 20)
	_draw_label(rect.position + Vector2(24.0, 72.0), "政体：" + str(_country_profile.get("government_name", "第三共和国")), 13)
	_draw_label(
		rect.position + Vector2(24.0, 104.0),
		_ellipsize("公开议程：" + str(_country_profile.get("public_policy", "未配置")), 62),
		12
	)
	_draw_label(
		rect.position + Vector2(24.0, 134.0),
		_ellipsize("新闻：" + str(_country_profile.get("news", "未配置")), 62),
		12
	)
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 138.0, 32.0), "定位法兰西", "focus_france", true)


func _draw_character_panel(rect: Rect2) -> void:
	var profile: Dictionary = _character_profiles.get(active_character_key, {})
	_draw_label(rect.position + Vector2(24.0, 38.0), str(profile.get("display_name_zh", profile.get("name", "人物"))), 20)
	_draw_label(rect.position + Vector2(24.0, 70.0), str(profile.get("position", profile.get("occupation", ""))), 13)
	_draw_label(rect.position + Vector2(24.0, 102.0), _ellipsize("所在地：" + str(profile.get("region", "未配置")), 62), 12)
	_draw_label(rect.position + Vector2(24.0, 130.0), _ellipsize("当前事项：" + str(profile.get("plan", "未配置")), 62), 12)
	_draw_label(rect.position + Vector2(24.0, 158.0), _ellipsize("关注：" + str(profile.get("primary_concern", "未配置")), 62), 12)
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 150.0, 32.0), "切换角色视角", "switch_character", _character_profiles.size() > 1)


func _draw_activity_panel(rect: Rect2) -> void:
	_draw_label(rect.position + Vector2(24.0, 38.0), "已知信息与机构议程", 19)
	var y := rect.position.y + 66.0
	for index in range(mini(_world_events.size(), 6)):
		var event: Dictionary = _world_events[index]
		var event_id := str(event.get("id", ""))
		var row := Rect2(rect.position.x + 24.0, y, rect.size.x - 48.0, 27.0)
		_panel(row, Color(0.055, 0.075, 0.072, 0.82), Color(0.48, 0.62, 0.56, 0.22))
		_register_hit(row, "inspect_event:" + event_id, true)
		_draw_label(row.position + Vector2(8.0, 18.0), _ellipsize("• " + str(event.get("title", "状态")), 58), 10)
		y += 31.0
	_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 42.0, 118.0, 28.0), "标记已读", "mark_read", activity_unread > 0)


func _activity_summary() -> String:
	if _world_events.is_empty():
		return "暂无已知信息"
	return _ellipsize(str(_world_events[0].get("title", "机构议程")), 22)


func _ellipsize(value: String, maximum_characters: int) -> String:
	if maximum_characters <= 1 or value.length() <= maximum_characters:
		return value
	return value.left(maximum_characters - 1) + "…"


func _handle_button_click(position: Vector2) -> bool:
	for index in range(_button_hits.size() - 1, -1, -1):
		var record: Dictionary = _button_hits[index]
		var rect: Rect2 = record.get("rect", Rect2())
		if not rect.has_point(position):
			continue
		if bool(record.get("enabled", false)):
			_activate_button(str(record.get("action", "")))
		return true
	return false
