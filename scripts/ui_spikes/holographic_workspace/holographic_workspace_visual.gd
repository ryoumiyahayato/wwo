extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"

var _workspace_font: SystemFont


func _ready() -> void:
	_workspace_font = SystemFont.new()
	_workspace_font.font_names = PackedStringArray([
		"Noto Sans CJK SC",
		"Noto Sans CJK JP",
		"Microsoft YaHei",
		"Microsoft JhengHei",
		"PingFang SC",
		"SimSun",
	])
	super._ready()


func _set_layout(layout_id: int) -> void:
	super._set_layout(layout_id)
	if space_level == WORLD:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_label(
	position: Vector2,
	text: String,
	font_size: int = 12,
	color: Color = Color(0.90, 0.91, 0.84, 1.0)
) -> void:
	var font: Font = _workspace_font if _workspace_font != null else ThemeDB.fallback_font
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_global_world() -> void:
	for segment: PackedVector2Array in _global_screen_segments:
		draw_polyline(segment, Color(0.64, 0.84, 0.78, 0.23), 0.85, true)
	for selected_segment: PackedVector2Array in _selected_country_segments:
		draw_polyline(selected_segment, Color(0.92, 0.77, 0.42, 0.88), 2.0, true)

	for country_key_value: Variant in _country_screen_anchors.keys():
		var country_id: String = str(country_key_value)
		var country: Dictionary = _country_by_id.get(country_id, {}) as Dictionary
		var selected: bool = country_id == selected_country_id
		var hovered: bool = country_id == hover_country_id
		var label_rank: int = int(country.get("label_rank", 9))
		var visible_marker: bool = selected or hovered or country_id == FOCUS_COUNTRY_ID or label_rank <= 2
		if not visible_marker:
			continue
		var point: Vector2 = _country_screen_anchors.get(country_id, Vector2.ZERO) as Vector2
		var radius: float = 5.5 if selected or hovered else 2.7
		var marker_color: Color = Color(0.94, 0.76, 0.40, 0.94) if selected else Color(0.72, 0.88, 0.82, 0.64)
		if hovered:
			marker_color = Color(0.84, 0.96, 0.90, 0.98)
		draw_circle(point, radius, marker_color)
		if selected or hovered:
			_draw_label(point + Vector2(9.0, -8.0), str(country.get("name", country_id)), 12)

	for event_key_value: Variant in _event_screen_positions.keys():
		var event_id: String = str(event_key_value)
		var event_point: Vector2 = _event_screen_positions.get(event_id, Vector2.ZERO) as Vector2
		var event: Dictionary = _event_by_id.get(event_id, {}) as Dictionary
		var severity: int = int(event.get("severity", 1))
		var event_color: Color = Color(0.96, 0.59, 0.28, 0.94) if severity >= 2 else Color(0.91, 0.76, 0.40, 0.82)
		var event_radius: float = 5.5 if event_id == hover_event_id or event_id == selected_event_id else 4.0
		var halo: Color = event_color
		halo.a = 0.14
		draw_circle(event_point, event_radius + 3.0, halo, false, 1.2)
		draw_circle(event_point, event_radius, event_color)
		if event_id == hover_event_id:
			_draw_label(event_point + Vector2(10.0, 4.0), _ellipsize(str(event.get("title", "状态")), 28), 11)


func _draw_country_focus() -> void:
	for region_index: int in range(_regions.size()):
		var region: Dictionary = _regions[region_index]
		var region_id: String = str(region.get("id", ""))
		var selected: bool = region_id == selected_region_id
		var hovered: bool = region_id == hover_region_id
		var fill: Color = _focus_region_color(region_index)
		var border: Color = Color(0.0, 0.0, 0.0, 0.0)
		var border_width: float = 0.0
		if selected:
			fill = Color(0.84, 0.63, 0.28, 0.44)
			border = Color(0.96, 0.80, 0.42, 0.96)
			border_width = 1.8
		elif hovered:
			fill = Color(0.44, 0.70, 0.64, 0.40)
			border = Color(0.78, 0.94, 0.86, 0.90)
			border_width = 1.4
		var polygons: Array = _focus_region_screen_polygons.get(region_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			if border_width > 0.0:
				draw_polyline(polygon, border, border_width, true)
		var anchor: Vector2 = _focus_region_screen_anchors.get(region_id, Vector2.INF) as Vector2
		if anchor != Vector2.INF:
			var anchor_color: Color = border if border_width > 0.0 else Color(0.82, 0.78, 0.60, 0.82)
			draw_circle(anchor, 4.5 if selected or hovered else 2.8, anchor_color)
			_draw_label(anchor + Vector2(7.0, -5.0), _ellipsize(str(region.get("display_name_zh", region_id)), 14), 10)

	_draw_label(_hemisphere_rect.position + Vector2(18.0, 28.0), "国家聚焦 · 法兰西第三共和国", 15)
	_draw_button(
		Rect2(_hemisphere_rect.position + Vector2(18.0, 42.0), Vector2(96.0, 28.0)),
		"返回全球",
		"overview_world",
		true
	)


func _focus_region_color(index: int) -> Color:
	match index % 9:
		0:
			return Color(0.25, 0.37, 0.39, 0.32)
		1:
			return Color(0.31, 0.38, 0.34, 0.32)
		2:
			return Color(0.32, 0.34, 0.42, 0.32)
		3:
			return Color(0.37, 0.35, 0.30, 0.32)
		4:
			return Color(0.27, 0.40, 0.36, 0.32)
		5:
			return Color(0.35, 0.31, 0.39, 0.32)
		6:
			return Color(0.30, 0.39, 0.43, 0.32)
		7:
			return Color(0.39, 0.37, 0.29, 0.32)
		_:
			return Color(0.29, 0.34, 0.36, 0.32)


func _draw_region_map() -> void:
	var rect: Rect2 = _main_content_rect(120.0, 166.0, 104.0)
	_panel(rect, Color(0.025, 0.047, 0.052, 0.94), Color(0.70, 0.62, 0.36, 0.32))
	var region: Dictionary = _region_by_id.get(selected_region_id, {}) as Dictionary
	_draw_label(rect.position + Vector2(24.0, 34.0), "二维大区层 · " + str(region.get("display_name_zh", "选中大区")), 17)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		"行政边界、城市与机构来自现有数据；城市联系线按现有坐标派生",
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_region_flat_geometry(rect)
	_draw_region_cities_and_routes(rect)
	_draw_region_institutions(rect)


func _draw_city_map() -> void:
	var rect: Rect2 = _main_content_rect(120.0, 166.0, 104.0)
	_panel(rect, Color(0.03, 0.04, 0.04, 0.94), Color(0.72, 0.75, 0.66, 0.24))
	var city: Dictionary = _city_by_id.get(selected_city_id, {}) as Dictionary
	_draw_label(rect.position + Vector2(24.0, 34.0), "城市本地层 · " + str(city.get("name", "本地城市")), 17)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		"显示该城市已配置的正式机构与人物；未配置对象不会用虚构地点补齐",
		12,
		Color(0.73, 0.82, 0.78, 1.0)
	)
	_draw_city_institutions(rect)
	_draw_city_characters(rect)


func _enter_region() -> void:
	if selected_region_id.is_empty():
		return
	if _info_tween != null and _info_tween.is_valid():
		_info_tween.kill()
	info_open = false
	info_progress = 0.0
	space_level = REGION
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	_set_world_layer_visible(false)
	queue_redraw()
