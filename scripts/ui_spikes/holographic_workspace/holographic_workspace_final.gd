extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_polish.gd"

@onready var _moon_node: MeshInstance3D = %Moon


func _ready() -> void:
	super._ready()
	_sync_moon_visibility()


func _activate_button(action: String) -> void:
	super._activate_button(action)
	_sync_moon_visibility()


func _focus_selected_country() -> void:
	super._focus_selected_country()
	_sync_moon_visibility()


func _show_event_from_hud(event_id: String) -> void:
	super._show_event_from_hud(event_id)
	_sync_moon_visibility()


func _return_to_global_world() -> void:
	super._return_to_global_world()
	_sync_moon_visibility()


func _enter_region() -> void:
	super._enter_region()
	_sync_moon_visibility()


func _enter_city(city_id: String) -> void:
	super._enter_city(city_id)
	_sync_moon_visibility()


func _go_back() -> void:
	super._go_back()
	_sync_moon_visibility()


func _sync_moon_visibility() -> void:
	if _moon_node == null:
		return
	_moon_node.visible = (
		space_level == WORLD
		and world_mode == WORLD_COUNTRIES
		and viewport_container.visible
	)


func _draw_region_cities_and_routes(rect: Rect2) -> void:
	var city_ids: Array = _cities_by_region.get(selected_region_id, []) as Array
	if city_ids.is_empty():
		_draw_label(
			rect.position + Vector2(86.0, rect.size.y - 60.0),
			"当前大区没有配置城市入口",
			13,
			Color(0.95, 0.72, 0.43, 1.0)
		)
		return

	var polygons: Array = _region_polygons.get(selected_region_id, []) as Array
	var bounds: Rect2 = _lon_lat_bounds(polygons)
	var map_rect: Rect2 = _region_map_rect(rect)
	var city_records: Array[Dictionary] = []
	for city_id_value: Variant in city_ids:
		var city: Dictionary = _city_by_id.get(str(city_id_value), {}) as Dictionary
		if _lon_lat_from_record(city, "lon_lat") != null:
			city_records.append(city)
	city_records.sort_custom(Callable(self, "_city_priority_before"))

	var list_x: float = rect.end.x - 174.0
	var list_y: float = rect.position.y + 88.0
	var visible_count: int = mini(city_records.size(), 8)
	for index: int in range(visible_count):
		var city_record: Dictionary = city_records[index]
		var city_id: String = str(city_record.get("id", ""))
		var lon_lat_value: Variant = _lon_lat_from_record(city_record, "lon_lat")
		if lon_lat_value == null:
			continue
		var point: Vector2 = _lon_lat_to_rect(lon_lat_value as Vector2, bounds, map_rect)
		var is_major: bool = bool(city_record.get("major", false))
		var radius: float = 7.0 if is_major else 5.2
		var color: Color = Color(0.91, 0.75, 0.39, 0.94) if is_major else Color(0.72, 0.82, 0.68, 0.84)
		draw_circle(point, radius, color)
		draw_circle(point, radius + 3.0, Color(color.r, color.g, color.b, 0.16), false, 1.0)
		_draw_label(point + Vector2(10.0, 4.0), _ellipsize(str(city_record.get("name", "城市")), 16), 11)
		_register_hit(
			Rect2(point - Vector2(12.0, 12.0), Vector2(24.0, 24.0)),
			"enter_city:" + city_id,
			true
		)
		_draw_button(
			Rect2(list_x, list_y + float(index) * 34.0, 142.0, 27.0),
			"进入 " + _ellipsize(str(city_record.get("name", "城市")), 12),
			"enter_city:" + city_id,
			true
		)

	if city_records.size() > visible_count:
		_draw_label(
			Vector2(list_x, list_y + float(visible_count) * 34.0 + 14.0),
			"另有 %d 个城市节点" % (city_records.size() - visible_count),
			10,
			Color(0.66, 0.75, 0.72, 1.0)
		)


func _city_priority_before(a: Dictionary, b: Dictionary) -> bool:
	var a_priority: int = int(a.get("label_priority", 52))
	var b_priority: int = int(b.get("label_priority", 52))
	if a_priority == b_priority:
		return str(a.get("name", "")) < str(b.get("name", ""))
	return a_priority > b_priority


func _average_vector2(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() < 3:
		return super._average_vector2(points)
	var twice_area: float = 0.0
	var centroid_accumulator: Vector2 = Vector2.ZERO
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % points.size()]
		var cross_value: float = current.x * following.y - following.x * current.y
		twice_area += cross_value
		centroid_accumulator += (current + following) * cross_value
	if absf(twice_area) < 0.000001:
		return super._average_vector2(points)
	return centroid_accumulator / (3.0 * twice_area)
