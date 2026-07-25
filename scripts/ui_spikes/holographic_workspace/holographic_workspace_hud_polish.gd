extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_final_polish.gd"


func _draw_corners() -> void:
	var compact: bool = size.x < 940.0 or size.y < 620.0
	var left_width: float = minf(284.0, size.x * 0.42)
	var right_width: float = minf(282.0, size.x * 0.42)
	var top_height: float = 56.0 if compact else 66.0
	var bottom_height: float = 58.0 if compact else 70.0
	var country_rect: Rect2 = Rect2(18.0, 18.0, left_width, top_height)
	var time_rect: Rect2 = Rect2(size.x - right_width - 18.0, 18.0, right_width, top_height)
	var character_rect: Rect2 = Rect2(18.0, size.y - bottom_height - 18.0, left_width, bottom_height)
	var activity_rect: Rect2 = Rect2(size.x - right_width - 18.0, size.y - bottom_height - 18.0, right_width, bottom_height)
	_draw_corner(
		country_rect,
		_current_country_corner_title(),
		_current_country_corner_subtitle(),
		"toggle_country_panel",
		Color(0.72, 0.64, 0.38, 0.22),
		compact
	)
	_draw_corner(character_rect, _active_character_name(), _active_character_position(), "toggle_character_panel", Color(0.72, 0.64, 0.38, 0.22), compact)
	_draw_corner(activity_rect, "已知信息 · 未读 %d" % activity_unread, _activity_summary(), "toggle_activity_panel", Color(0.72, 0.50, 0.25, 0.22), compact)
	_panel(time_rect, Color(0.025, 0.055, 0.06, 0.88), Color(0.72, 0.64, 0.38, 0.22))
	_register_hit(time_rect, "toggle_time_panel", true)
	_draw_label(time_rect.position + Vector2(12.0, 22.0), _format_sim_datetime(), 13)
	var button_y: float = time_rect.end.y - 28.0
	_draw_button(Rect2(time_rect.position.x + 10.0, button_y, 44.0, 22.0), "Ⅱ" if sim_paused else "▶", "toggle_pause", true)
	_draw_button(Rect2(time_rect.position.x + 60.0, button_y, 38.0, 22.0), "1×", "speed:1", true)
	_draw_button(Rect2(time_rect.position.x + 102.0, button_y, 38.0, 22.0), "2×", "speed:2", true)
	_draw_button(Rect2(time_rect.position.x + 144.0, button_y, 38.0, 22.0), "4×", "speed:4", true)


func _draw_country_panel(rect: Rect2) -> void:
	var entity: Dictionary = _current_country_entity()
	if entity.is_empty() or selected_country_id == FOCUS_COUNTRY_ID:
		super._draw_country_panel(rect)
		return

	var title: String = str(entity.get("name_zh", entity.get("name", selected_country_id)))
	var status: String = _history_status_label(str(entity.get("status", "sovereign")))
	var territory_count: int = (_history_territories_by_entity.get(selected_country_id, []) as Array).size()
	_draw_label(rect.position + Vector2(24.0, 38.0), _ellipsize(title, 42), 20)
	_draw_label(rect.position + Vector2(24.0, 72.0), "地位：" + status, 13)
	_draw_label(rect.position + Vector2(24.0, 102.0), "辖区数量：%d" % territory_count, 12)
	if not selected_historical_territory_iso.is_empty():
		_draw_label(
			rect.position + Vector2(24.0, 130.0),
			"当前辖区：" + _history_territory_name(selected_historical_territory_iso),
			12,
			Color(0.92, 0.79, 0.49, 1.0)
		)
	var notice: String = "1900政治实体近似层；现代几何只用于缺失历史边界的视觉回退。"
	if bool(entity.get("provisional", false)):
		notice = "待校订领土：尚未作为已核实的1900主权实体。"
	_draw_label(rect.position + Vector2(24.0, 162.0), _ellipsize(notice, 66), 11, Color(0.73, 0.82, 0.78, 1.0))

	if world_mode == WORLD_COUNTRIES and space_level == WORLD:
		_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 122.0, 32.0), "放大定位", "history_zoom_selected", true)
		_draw_button(Rect2(rect.position.x + 158.0, rect.end.y - 50.0, 142.0, 32.0), "进入政治实体", "history_enter_selected", true)
	else:
		_draw_button(Rect2(rect.position.x + 24.0, rect.end.y - 50.0, 122.0, 32.0), "返回全球", "history_back_global", true)


func _current_country_entity() -> Dictionary:
	if selected_country_id.is_empty():
		return {}
	return _country_by_id.get(selected_country_id, {}) as Dictionary


func _current_country_corner_title() -> String:
	var entity: Dictionary = _current_country_entity()
	if not entity.is_empty():
		return str(entity.get("short_name_zh", entity.get("name_zh", entity.get("name", selected_country_id))))
	if world_mode == WORLD_COUNTRY_FOCUS or not selected_region_id.is_empty() or not selected_city_id.is_empty():
		return str(_country_profile.get("formal_name_zh", "法兰西第三共和国"))
	return "1900世界政治实体"


func _current_country_corner_subtitle() -> String:
	var entity: Dictionary = _current_country_entity()
	if entity.is_empty():
		return "政治实体 / 战争边界 / 国家入口"
	if selected_country_id == FOCUS_COUNTRY_ID:
		return "第三共和国 / 九大区 / 国家入口"
	var subtitle: String = _history_status_label(str(entity.get("status", "sovereign")))
	if not selected_historical_territory_iso.is_empty():
		subtitle += " / " + _history_territory_name(selected_historical_territory_iso)
	else:
		subtitle += " / %d个辖区" % ((_history_territories_by_entity.get(selected_country_id, []) as Array).size())
	return subtitle


func _history_status_label(status: String) -> String:
	match status:
		"empire":
			return "帝国"
		"dual_monarchy":
			return "二元君主国"
		"kingdom":
			return "王国"
		"republic":
			return "共和国"
		"dependency":
			return "属地"
		"autonomous":
			return "自治辖区"
		"colony":
			return "殖民地"
		"protectorate":
			return "保护国"
		"occupied":
			return "占领区"
		"contested":
			return "争议地区"
		"fragmented":
			return "多政权地区"
		"provisional":
			return "待校订领土"
		_:
			return "政治实体"
