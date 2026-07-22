class_name WorldMapCanvasDetail
extends "res://scripts/world_map/world_map_canvas.gd"
## Product map layer for modern city reference data. Core curated cities remain
## authoritative for theme labels; this layer is lazy, budgeted and selectable.

const DETAIL_CITY_COLOR := Color("#d9d0ad")
const DETAIL_MUNICIPALITY_COLOR := Color("#9fb9aa")
const DETAIL_SELECTED_COLOR := Color("#f2c865")

var _city_detail_catalog := WorldCityShardCatalog.new()


func setup(prototype_data: PrototypeV2Data) -> void:
	super.setup(prototype_data)
	_city_detail_catalog.configure(Callable(self, "project_lon_lat"))
	_refresh_city_detail()


func _refresh_visible_scene(redraw_geometry: bool, rebuild_labels: bool) -> void:
	super._refresh_visible_scene(redraw_geometry, rebuild_labels)
	if _refresh_city_detail():
		_request_layer_redraw(_node_layer)
		_request_layer_redraw(_label_layer)
		_request_layer_redraw(_hud_layer)


func _draw_node_layer(target: PrototypeV2MapLayer) -> void:
	super._draw_node_layer(target)
	if get_map_scope() == MAP_SCOPE_WORLD:
		return
	var records: Array[Dictionary] = _city_detail_catalog.visible_records
	_add_perf_traversal("city_detail_nodes", records.size())
	for record: Dictionary in records:
		var point: Vector2 = record.get("world_point", Vector2.INF) as Vector2
		if point == Vector2.INF:
			continue
		var record_id: String = str(record.get("id", ""))
		var selected: bool = selected_type == "city" and selected_id == record_id
		var municipality: bool = str(record.get("record_type", "")) == "municipality"
		var radius_pixels: float = 3.8 if bool(record.get("major", false)) else (2.5 if municipality else 3.0)
		if selected:
			target.draw_circle(point, 8.5 / zoom, Color(DETAIL_SELECTED_COLOR, 0.24))
		target.draw_circle(
			point,
			radius_pixels / zoom,
			DETAIL_SELECTED_COLOR if selected else (
				DETAIL_MUNICIPALITY_COLOR if municipality else DETAIL_CITY_COLOR
			)
		)
		if radius_pixels >= 3.0:
			target.draw_circle(point, 1.1 / zoom, Color("#263737"))


func _draw_label_layer(target: PrototypeV2MapLayer) -> void:
	super._draw_label_layer(target)
	if get_map_scope() == MAP_SCOPE_WORLD or _font == null:
		return
	var accepted: Array[Rect2] = []
	for base_rect: Rect2 in _label_rects:
		accepted.append(base_rect)
	var budget: int = _city_detail_catalog.get_label_budget()
	var drawn: int = 0
	var viewport := Rect2(Vector2.ZERO, size).grow(-8.0)
	for record: Dictionary in _city_detail_catalog.visible_records:
		if drawn >= budget:
			break
		var priority: int = int(record.get("label_priority", 0))
		if get_map_scope() == MAP_SCOPE_REGIONAL and priority < _regional_label_threshold():
			continue
		var label: String = str(record.get("name", record.get("native_name", "")))
		if label.is_empty():
			continue
		var world_point: Vector2 = record.get("world_point", Vector2.INF) as Vector2
		if world_point == Vector2.INF:
			continue
		var screen_point: Vector2 = world_point * zoom + pan
		if not viewport.has_point(screen_point):
			continue
		var font_size: int = 13 if get_map_scope() == MAP_SCOPE_CITY else 12
		var text_size: Vector2 = _font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		)
		var rect := Rect2(
			screen_point + Vector2(7.0, -float(font_size) - 2.0),
			text_size + Vector2(7.0, 5.0)
		)
		var collides: bool = false
		for existing: Rect2 in accepted:
			if existing.intersects(rect):
				collides = true
				break
		if collides:
			continue
		accepted.append(rect)
		target.draw_rect(rect, Color(0.025, 0.06, 0.065, 0.76))
		target.draw_string(
			_font,
			rect.position + Vector2(3.0, float(font_size) + 1.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			Color("#e6dfc5")
		)
		drawn += 1
	_add_perf_traversal("city_detail_labels", drawn)


func _draw_hud_layer(target: PrototypeV2MapLayer) -> void:
	super._draw_hud_layer(target)
	if not _city_detail_catalog.configured or get_map_scope() == MAP_SCOPE_WORLD:
		return
	var snapshot: Dictionary = _city_detail_catalog.debug_snapshot()
	var label: String = "现代城市参考 · 当前 %d · 缓存 %d/%d" % [
		int(snapshot.get("visible_records", 0)),
		int(snapshot.get("loaded_shards", 0)),
		int(snapshot.get("cache_limit", 0)),
	]
	var origin := Vector2(170.0, target.size.y - 34.0)
	target.draw_rect(
		Rect2(origin - Vector2(9.0, 18.0), Vector2(238.0, 28.0)),
		Color(0.025, 0.06, 0.07, 0.76)
	)
	target.draw_string(
		_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, LABEL_MUTED
	)


func get_object_at(screen_position: Vector2) -> Dictionary:
	var detail: Dictionary = _detail_city_at(screen_position)
	if not detail.is_empty():
		return {
			"type": "city",
			"id": str(detail.get("id", "")),
			"data": detail,
		}
	return super.get_object_at(screen_position)


func get_city(city_id: String) -> Dictionary:
	var detail: Dictionary = _city_detail_catalog.record(city_id)
	return detail if not detail.is_empty() else super.get_city(city_id)


func debug_performance_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.debug_performance_snapshot()
	snapshot["city_detail"] = _city_detail_catalog.debug_snapshot()
	return snapshot


func debug_architecture_state() -> Dictionary:
	var snapshot: Dictionary = super.debug_architecture_state()
	snapshot["city_detail_load_mode"] = "viewport_intersecting_shards"
	snapshot["city_detail_modern_reference"] = true
	snapshot["city_detail"] = _city_detail_catalog.debug_snapshot()
	return snapshot


func debug_city_detail_snapshot() -> Dictionary:
	return _city_detail_catalog.debug_snapshot()


func _refresh_city_detail() -> bool:
	if not _city_detail_catalog.configured:
		return false
	var world_rect: Rect2 = _world_view_rect()
	var prefetch: float = maxf(1.5, maxf(world_rect.size.x, world_rect.size.y) * 0.18)
	return _city_detail_catalog.query(world_rect.grow(prefetch), get_map_scope(), zoom)


func _detail_city_at(screen_position: Vector2) -> Dictionary:
	if get_map_scope() == MAP_SCOPE_WORLD:
		return {}
	var world_position: Vector2 = (screen_position - pan) / zoom
	var radius: float = 11.0 / maxf(zoom, 0.01)
	var maximum_distance: float = radius * radius
	var nearest: Dictionary = {}
	for record: Dictionary in _city_detail_catalog.visible_records:
		var point: Vector2 = record.get("world_point", Vector2.INF) as Vector2
		if point == Vector2.INF:
			continue
		var distance: float = point.distance_squared_to(world_position)
		if distance > maximum_distance:
			continue
		maximum_distance = distance
		nearest = record
	return nearest


func _regional_label_threshold() -> int:
	if zoom < 12.0:
		return 94
	if zoom < 24.0:
		return 76
	if zoom < 36.0:
		return 62
	return 48
