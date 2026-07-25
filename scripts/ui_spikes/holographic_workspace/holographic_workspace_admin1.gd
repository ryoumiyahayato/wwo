extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_history.gd"

var selected_world_admin1_id: String = ""
var hover_world_admin1_id: String = ""
var _world_admin1_by_iso: Dictionary = {}
var _world_admin1_by_id: Dictionary = {}
var _world_admin1_screen_polygons: Dictionary = {}
var _world_admin1_bounds: Rect2 = Rect2()


func _ready() -> void:
	super._ready()
	_load_world_admin1_data()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if space_level == REGION and world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and _has_world_admin1_for_selected_territory():
		if event is InputEventMouseButton:
			var button: InputEventMouseButton = event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
				if _handle_button_click(button.position):
					accept_event()
					return
				_select_world_admin1_at(button.position, true)
				accept_event()
				return
		if event is InputEventMouseMotion:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			if not _position_hits_ui(motion.position):
				_select_world_admin1_at(motion.position, false)
			return
	super._gui_input(event)


func _activate_button(action: String) -> void:
	if action == "history_enter_admin1":
		_enter_selected_world_admin1()
		return
	super._activate_button(action)


func _enter_region() -> void:
	super._enter_region()
	if space_level != REGION or world_mode != WORLD_HISTORICAL_ENTITY_FOCUS:
		return
	selected_world_admin1_id = ""
	hover_world_admin1_id = ""
	var records: Array = _world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array
	if records.size() == 1:
		selected_world_admin1_id = str((records[0] as Dictionary).get("id", ""))
		space_level = CITY
	queue_redraw()


func _draw_region_map() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and _has_world_admin1_for_selected_territory():
		_draw_world_admin1_layer()
		return
	super._draw_region_map()


func _draw_city_map() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and not selected_world_admin1_id.is_empty():
		_draw_world_admin1_local_layer()
		return
	super._draw_city_map()


func _go_back() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and space_level == CITY:
		space_level = REGION
		selected_world_admin1_id = ""
		queue_redraw()
		return
	super._go_back()


func _breadcrumb_text() -> String:
	var text: String = super._breadcrumb_text()
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and not selected_world_admin1_id.is_empty():
		var record: Dictionary = _world_admin1_by_id.get(selected_world_admin1_id, {}) as Dictionary
		text += " / " + _world_admin1_name(record)
	return text


func _load_world_admin1_data() -> void:
	_world_admin1_by_iso.clear()
	_world_admin1_by_id.clear()
	var document: Dictionary = _read_document("res://data/world_map/world_admin1.json")
	for record_value: Variant in (document.get("regions", []) as Array):
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value as Dictionary
		var iso: String = str(record.get("country_iso_a3", "")).to_upper()
		var record_id: String = str(record.get("id", ""))
		if iso.is_empty() or record_id.is_empty():
			continue
		var polygons: Array[PackedVector2Array] = []
		for polygon_value: Variant in (record.get("polygons", []) as Array):
			var polygon: PackedVector2Array = _points_from_raw(polygon_value)
			if polygon.size() > 2:
				polygons.append(polygon)
		if polygons.is_empty():
			continue
		var runtime_record: Dictionary = record.duplicate(true)
		runtime_record["runtime_polygons"] = polygons
		_world_admin1_by_id[record_id] = runtime_record
		var country_records: Array = _world_admin1_by_iso.get(iso, []) as Array
		country_records.append(runtime_record)
		_world_admin1_by_iso[iso] = country_records


func _has_world_admin1_for_selected_territory() -> bool:
	return not (_world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array).is_empty()


func _draw_world_admin1_layer() -> void:
	var rect: Rect2 = _main_content_rect(110.0, 166.0, 104.0)
	_panel(rect, Color(0.018, 0.039, 0.046, 0.96), Color(0.67, 0.62, 0.42, 0.34))
	var records: Array = _world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array
	_draw_label(rect.position + Vector2(24.0, 34.0), _history_territory_name(selected_historical_territory_iso) + " · 一级行政区", 17)
	_draw_label(rect.position + Vector2(24.0, 59.0), "现代行政区几何作为1900历史数据缺失时的近似回退；当前记录 %d。" % records.size(), 11, Color(0.70, 0.78, 0.75, 1.0))
	_rebuild_world_admin1_screen_cache(rect)
	var label_limit: int = 28 if records.size() <= 40 else 18
	var labeled: int = 0
	for index: int in range(records.size()):
		var record: Dictionary = records[index] as Dictionary
		var record_id: String = str(record.get("id", ""))
		var selected: bool = record_id == selected_world_admin1_id
		var hovered: bool = record_id == hover_world_admin1_id
		var fill: Color = _history_territory_color(index, 0.34)
		var border: Color = Color(0.66, 0.76, 0.71, 0.48)
		var width: float = 0.85
		if selected:
			fill = Color(0.82, 0.60, 0.24, 0.56)
			border = Color(0.98, 0.82, 0.43, 0.98)
			width = 2.0
		elif hovered:
			fill = Color(0.34, 0.64, 0.59, 0.49)
			border = Color(0.82, 0.95, 0.88, 0.92)
			width = 1.6
		for polygon_value: Variant in (_world_admin1_screen_polygons.get(record_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, width, true)
		if labeled < label_limit and (int(record.get("label_rank", 6)) <= 4 or selected or hovered):
			var label_lon_lat: Variant = record.get("label_lon_lat", [])
			if label_lon_lat is Array and (label_lon_lat as Array).size() >= 2:
				var point: Vector2 = _lon_lat_to_history_rect(Vector2(float(label_lon_lat[0]), float(label_lon_lat[1])), _world_admin1_bounds, _world_admin1_map_rect(rect))
				_draw_label(point + Vector2(4.0, 3.0), _world_admin1_short_name(record), 9, Color(0.77, 0.83, 0.78, 0.88))
				labeled += 1
	_draw_button(Rect2(rect.end.x - 156.0, rect.end.y - 40.0, 132.0, 28.0), "进入下一级", "history_enter_admin1", not selected_world_admin1_id.is_empty())
	if not selected_world_admin1_id.is_empty():
		var selected_record: Dictionary = _world_admin1_by_id.get(selected_world_admin1_id, {}) as Dictionary
		_draw_label(rect.position + Vector2(24.0, rect.size.y - 22.0), "当前一级区：" + _world_admin1_name(selected_record), 11, Color(0.94, 0.80, 0.50, 1.0))


func _rebuild_world_admin1_screen_cache(rect: Rect2) -> void:
	_world_admin1_screen_polygons.clear()
	var records: Array = _world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array
	var all_polygons: Array = []
	for record_value: Variant in records:
		var record: Dictionary = record_value as Dictionary
		for polygon_value: Variant in (record.get("runtime_polygons", []) as Array):
			all_polygons.append(polygon_value)
	_world_admin1_bounds = _lon_lat_bounds(all_polygons)
	var map_rect: Rect2 = _world_admin1_map_rect(rect)
	for record_value: Variant in records:
		var record: Dictionary = record_value as Dictionary
		var record_id: String = str(record.get("id", ""))
		var screen_polygons: Array[PackedVector2Array] = []
		for polygon_value: Variant in (record.get("runtime_polygons", []) as Array):
			var polygon: PackedVector2Array = polygon_value
			var screen: PackedVector2Array = PackedVector2Array()
			for lon_lat: Vector2 in polygon:
				screen.append(_lon_lat_to_history_rect(lon_lat, _world_admin1_bounds, map_rect))
			if screen.size() > 2:
				screen_polygons.append(screen)
		_world_admin1_screen_polygons[record_id] = screen_polygons


func _world_admin1_map_rect(rect: Rect2) -> Rect2:
	var map_rect: Rect2 = rect.grow(-70.0)
	map_rect.position.y += 28.0
	map_rect.size.y -= 42.0
	return map_rect


func _select_world_admin1_at(position: Vector2, click: bool) -> void:
	var found: String = ""
	for record_id_value: Variant in _world_admin1_screen_polygons.keys():
		var record_id: String = str(record_id_value)
		for polygon_value: Variant in (_world_admin1_screen_polygons.get(record_id, []) as Array):
			if Geometry2D.is_point_in_polygon(position, polygon_value as PackedVector2Array):
				found = record_id
				break
		if not found.is_empty():
			break
	if hover_world_admin1_id != found:
		hover_world_admin1_id = found
		queue_redraw()
	if click and not found.is_empty():
		selected_world_admin1_id = found
		queue_redraw()


func _enter_selected_world_admin1() -> void:
	if selected_world_admin1_id.is_empty():
		return
	space_level = CITY
	queue_redraw()


func _draw_world_admin1_local_layer() -> void:
	var record: Dictionary = _world_admin1_by_id.get(selected_world_admin1_id, {}) as Dictionary
	var rect: Rect2 = _main_content_rect(110.0, 166.0, 104.0)
	_panel(rect, Color(0.019, 0.037, 0.043, 0.97), Color(0.67, 0.62, 0.42, 0.34))
	_draw_label(rect.position + Vector2(24.0, 34.0), _history_territory_name(selected_historical_territory_iso) + " / " + _world_admin1_name(record), 17)
	_draw_label(rect.position + Vector2(24.0, 59.0), "已进入一级行政区本地层；更低层级需历史县市、城市与机构数据。", 11, Color(0.70, 0.78, 0.75, 1.0))
	var polygons: Array = record.get("runtime_polygons", []) as Array
	var bounds: Rect2 = _lon_lat_bounds(polygons)
	var map_rect: Rect2 = rect.grow(-82.0)
	map_rect.position.y += 24.0
	map_rect.size.y -= 36.0
	for polygon_value: Variant in polygons:
		var polygon: PackedVector2Array = polygon_value
		var screen: PackedVector2Array = PackedVector2Array()
		for lon_lat: Vector2 in polygon:
			screen.append(_lon_lat_to_history_rect(lon_lat, bounds, map_rect))
		if screen.size() > 2:
			draw_colored_polygon(screen, Color(0.27, 0.45, 0.43, 0.42))
			draw_polyline(screen, Color(0.90, 0.78, 0.46, 0.86), 1.6, true)
	_draw_label(rect.position + Vector2(24.0, rect.size.y - 22.0), "行政类型：" + str(record.get("type", "Region")) + " · 代码：" + str(record.get("code", "未配置")), 11, Color(0.91, 0.67, 0.40, 1.0))


func _world_admin1_name(record: Dictionary) -> String:
	var chinese: String = str(record.get("name_zh", ""))
	if not chinese.is_empty():
		return chinese
	return str(record.get("name", record.get("id", "一级行政区")))


func _world_admin1_short_name(record: Dictionary) -> String:
	return _ellipsize(_world_admin1_name(record), 12)
