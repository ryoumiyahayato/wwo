class_name WorldMapCanvas
extends "res://scripts/world_map/internal/world_map_canvas_impl.gd"
## Formal map with three explicit spatial layers. The shared basemap remains
## fixed; only the relevant local overlay is expanded for the active layer.

const MAP_SCOPE_WORLD: String = "world"
const MAP_SCOPE_REGIONAL: String = "regional"
const MAP_SCOPE_CITY: String = "city"
const REGIONAL_ZOOM: float = 36.0
const CITY_ZOOM: float = 180.0
const CITY_LOCAL_SCALE := Vector2(0.62, 0.52)

var _scope_cache: String = MAP_SCOPE_CITY
var _current_city_parent_id: String = "lille"


func set_map_scope(scope: String) -> void:
	if scope not in [MAP_SCOPE_WORLD, MAP_SCOPE_REGIONAL, MAP_SCOPE_CITY]:
		return
	_scope_cache = scope
	match scope:
		MAP_SCOPE_WORLD:
			reset_view()
		MAP_SCOPE_REGIONAL:
			_set_view(_player_world_point(), REGIONAL_ZOOM, _map_anchor())
		MAP_SCOPE_CITY:
			_set_view(_player_city_anchor(), minf(get_maximum_zoom(), CITY_ZOOM), _map_anchor())
	_rebuild_scope_catalog()


func get_map_scope() -> String:
	if zoom < 10.0:
		return MAP_SCOPE_WORLD
	if zoom < 80.0:
		return MAP_SCOPE_REGIONAL
	return MAP_SCOPE_CITY


func get_map_scope_label() -> String:
	return {
		MAP_SCOPE_WORLD: "世界",
		MAP_SCOPE_REGIONAL: "区域交通",
		MAP_SCOPE_CITY: "城市",
	}.get(get_map_scope(), "地图")


func zoom_at(direction: float, anchor: Vector2) -> void:
	var previous_scope: String = get_map_scope()
	super.zoom_at(direction, anchor)
	var next_scope: String = get_map_scope()
	if previous_scope != next_scope:
		_scope_cache = next_scope
		_rebuild_scope_catalog()


func focus_player_location() -> void:
	_update_current_city_parent()
	_scope_cache = MAP_SCOPE_CITY
	var focus_location_id: String = _observer_location_id()
	var focus_point: Vector2 = _player_city_anchor()
	if not focus_location_id.is_empty():
		focus_point = _scope_point_for_location_id(focus_location_id, MAP_SCOPE_CITY)
	camera_focus_id = focus_location_id if not focus_location_id.is_empty() else PLAYER_CITY_ID
	_set_view(focus_point, minf(get_maximum_zoom(), CITY_ZOOM), _map_anchor())
	_rebuild_scope_catalog()


func _rebuild_v2_3_local_catalog(catalog_revision: int) -> void:
	_update_current_city_parent()
	_v2_3_local_location_points.clear()
	_v2_3_local_spatial_index.configure(WORLD_BOUNDS, 24.0, _v2_3_local_locations.size())
	var scope: String = get_map_scope()
	for index: int in range(_v2_3_local_locations.size()):
		var location: Dictionary = _v2_3_local_locations[index] as Dictionary
		var location_id: String = str(location.get("location_id", ""))
		if location_id.is_empty():
			continue
		var point: Vector2 = _scope_point(location, scope)
		_v2_3_local_location_points[location_id] = point
		if _location_visible_in_scope(location, scope):
			_v2_3_local_spatial_index.insert(
				index,
				Rect2(point - Vector2.ONE * 0.08, Vector2.ONE * 0.16)
			)
	_v2_3_local_catalog_revision = catalog_revision
	_perf_v2_3_catalog_rebuilds += 1


func _rebuild_scope_catalog() -> void:
	if _v2_3_local_overlay.is_empty() or _v2_3_local_locations.is_empty():
		return
	_rebuild_v2_3_local_catalog(maxi(1, _v2_3_local_catalog_revision))
	_query_v2_3_local_locations(_world_view_rect().grow(4.0))
	for layer: PrototypeV2MapLayer in [
		_transport_layer, _node_layer, _selection_layer, _label_layer, _hud_layer,
	]:
		_request_layer_redraw(layer)


func _v2_3_local_overlay_visible() -> bool:
	return not _v2_3_local_overlay.is_empty() and get_map_scope() != MAP_SCOPE_WORLD


func _draw_v2_3_local_transport(target: PrototypeV2MapLayer) -> void:
	if not _v2_3_local_overlay_visible():
		return
	var scope: String = get_map_scope()
	var edges: Array = _v2_3_local_overlay.get("edges", []) as Array
	_add_perf_traversal("v2_3_local_edges", edges.size())
	for raw_edge: Variant in edges:
		if not raw_edge is Dictionary:
			continue
		var edge: Dictionary = raw_edge as Dictionary
		if not bool(edge.get("visible", false)) or not _edge_visible_in_scope(edge, scope):
			continue
		_draw_scope_route_segment(target, edge, Color(0.54, 0.58, 0.53, 0.44), 1.1)
	for raw_segment: Variant in _v2_3_local_overlay.get("preview_route_segments", []) as Array:
		if raw_segment is Dictionary:
			_draw_scope_route_segment(target, raw_segment as Dictionary, Color("#63a9d8"), 2.5)
	for raw_segment: Variant in _v2_3_local_overlay.get("active_route_segments", []) as Array:
		if raw_segment is Dictionary:
			_draw_scope_route_segment(target, raw_segment as Dictionary, Color("#d9b85c"), 3.2)


func _draw_scope_route_segment(
	target: PrototypeV2MapLayer,
	segment: Dictionary,
	color: Color,
	width_pixels: float
) -> void:
	var from_id: String = str(segment.get("from_location_id", ""))
	var to_id: String = str(segment.get("to_location_id", ""))
	if (from_id.is_empty() or to_id.is_empty()) and segment.has("edge_id"):
		var edge: Dictionary = _v2_3_local_edge_lookup.get(str(segment.get("edge_id", "")), {}) as Dictionary
		from_id = str(edge.get("from_location_id", ""))
		to_id = str(edge.get("to_location_id", ""))
	if not _v2_3_local_location_points.has(from_id) or not _v2_3_local_location_points.has(to_id):
		return
	var from_location: Dictionary = _v2_3_local_location_lookup.get(from_id, {}) as Dictionary
	var to_location: Dictionary = _v2_3_local_location_lookup.get(to_id, {}) as Dictionary
	var scope: String = get_map_scope()
	if not _location_visible_in_scope(from_location, scope) or not _location_visible_in_scope(to_location, scope):
		return
	target.draw_line(
		_v2_3_local_location_points[from_id] as Vector2,
		_v2_3_local_location_points[to_id] as Vector2,
		color,
		width_pixels / zoom,
		true
	)


func _draw_v2_3_local_nodes(target: PrototypeV2MapLayer) -> void:
	if not _v2_3_local_overlay_visible():
		return
	var scope: String = get_map_scope()
	_add_perf_traversal("v2_3_local_locations", _visible_v2_3_local_indices.size())
	for index: int in _visible_v2_3_local_indices:
		if index < 0 or index >= _v2_3_local_locations.size():
			continue
		var location: Dictionary = _v2_3_local_locations[index] as Dictionary
		if not bool(location.get("visible", false)) or not _location_visible_in_scope(location, scope):
			continue
		var point: Vector2 = _v2_3_local_location_points.get(str(location.get("location_id", "")), Vector2.ZERO) as Vector2
		var radius: float = 6.0 if scope == MAP_SCOPE_CITY else 4.8
		target.draw_circle(point, radius / zoom, Color("#d9c77a"))
		target.draw_circle(point, 2.1 / zoom, Color("#273c38"))
	var observer_id: String = str(_v2_3_local_overlay.get("observer_id", ""))
	for raw_position: Variant in _v2_3_local_overlay.get("person_positions", []) as Array:
		if not raw_position is Dictionary:
			continue
		var position: Dictionary = raw_position as Dictionary
		if not bool(position.get("visible", false)):
			continue
		var point: Vector2 = _v2_3_person_world_point(position)
		if point == Vector2.INF:
			continue
		var selected: bool = str(position.get("person_id", "")) == observer_id
		target.draw_circle(point, (7.2 if selected else 4.4) / zoom, Color("#e8c55e") if selected else Color("#82a7a0"))
		target.draw_circle(point, 1.8 / zoom, Color("#172b2b"))


func _v2_3_person_world_point(position: Dictionary) -> Vector2:
	var location_id: String = str(position.get("current_location_id", ""))
	var point: Vector2 = _scope_point_for_location_id(location_id, get_map_scope())
	if str(position.get("location_state", "")) != "in_transit":
		return point
	var edge: Dictionary = _v2_3_local_edge_lookup.get(str(position.get("current_edge_id", "")), {}) as Dictionary
	if edge.is_empty():
		return point
	var from_point: Vector2 = _scope_point_for_location_id(str(edge.get("from_location_id", "")), get_map_scope())
	var to_point: Vector2 = _scope_point_for_location_id(str(edge.get("to_location_id", "")), get_map_scope())
	return from_point.lerp(to_point, float(position.get("segment_progress", 0.5)))


func _draw_v2_3_local_labels(target: PrototypeV2MapLayer) -> void:
	if not _v2_3_local_overlay_visible() or _font == null:
		return
	var scope: String = get_map_scope()
	var accepted: Array[Rect2] = []
	for index: int in _visible_v2_3_local_indices:
		if index < 0 or index >= _v2_3_local_locations.size():
			continue
		var location: Dictionary = _v2_3_local_locations[index] as Dictionary
		if not bool(location.get("visible", false)) or not _location_visible_in_scope(location, scope):
			continue
		var label: String = str(location.get("display_name", ""))
		if label.is_empty():
			continue
		var point: Vector2 = (_v2_3_local_location_points.get(str(location.get("location_id", "")), Vector2.ZERO) as Vector2) * zoom + pan
		if not Rect2(Vector2.ZERO, size).grow(-8.0).has_point(point):
			continue
		var font_size: int = 12 if scope == MAP_SCOPE_CITY else 11
		var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var rect := Rect2(point + Vector2(8.0, -14.0), text_size + Vector2(7.0, 5.0))
		var collides: bool = false
		for existing: Rect2 in accepted:
			if existing.intersects(rect):
				collides = true
				break
		if collides:
			continue
		accepted.append(rect)
		target.draw_rect(rect, Color(0.025, 0.06, 0.065, 0.84))
		target.draw_string(_font, rect.position + Vector2(3.0, float(font_size) + 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color("#e6dfc5"))


func _draw_hud_layer(target: PrototypeV2MapLayer) -> void:
	super._draw_hud_layer(target)
	var label: String = "地图层：%s" % get_map_scope_label()
	var origin := Vector2(24.0, target.size.y - 34.0)
	target.draw_rect(Rect2(origin - Vector2(10.0, 19.0), Vector2(138.0, 29.0)), Color(0.025, 0.06, 0.07, 0.82))
	target.draw_string(_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, LABEL)


func _location_visible_in_scope(location: Dictionary, scope: String) -> bool:
	if location.is_empty():
		return false
	var location_type: String = str(location.get("location_type", ""))
	var parent_id: String = str(location.get("parent_region_id", ""))
	if scope == MAP_SCOPE_WORLD:
		return false
	if scope == MAP_SCOPE_REGIONAL:
		return location_type in ["city_centre", "regional_centre", "railway_station"]
	return parent_id == _current_city_parent_id and location_type not in ["regional_centre"]


func _edge_visible_in_scope(edge: Dictionary, scope: String) -> bool:
	var from_location: Dictionary = _v2_3_local_location_lookup.get(str(edge.get("from_location_id", "")), {}) as Dictionary
	var to_location: Dictionary = _v2_3_local_location_lookup.get(str(edge.get("to_location_id", "")), {}) as Dictionary
	return _location_visible_in_scope(from_location, scope) and _location_visible_in_scope(to_location, scope)


func _scope_point(location: Dictionary, scope: String) -> Vector2:
	var world_point: Vector2 = project_lon_lat(location.get("world_position", []))
	if scope != MAP_SCOPE_CITY:
		return world_point
	if str(location.get("parent_region_id", "")) != _current_city_parent_id:
		return world_point
	var city_anchor: Vector2 = _city_anchor_for_parent(_current_city_parent_id)
	var local: Array = location.get("local_position", []) as Array
	if local.size() != 2:
		return world_point
	return city_anchor + Vector2(float(local[0]), float(local[1])) * CITY_LOCAL_SCALE


func _scope_point_for_location_id(location_id: String, scope: String) -> Vector2:
	var location: Dictionary = _v2_3_local_location_lookup.get(location_id, {}) as Dictionary
	if location.is_empty():
		return Vector2.INF
	return _scope_point(location, scope)


func _observer_location_id() -> String:
	var observer_id: String = str(_v2_3_local_overlay.get("observer_id", ""))
	for raw_position: Variant in _v2_3_local_overlay.get("person_positions", []) as Array:
		if not raw_position is Dictionary:
			continue
		var position: Dictionary = raw_position as Dictionary
		if str(position.get("person_id", "")) == observer_id:
			return str(position.get("current_location_id", position.get("travel_destination_id", "")))
	return ""


func _update_current_city_parent() -> void:
	var location: Dictionary = _v2_3_local_location_lookup.get(_observer_location_id(), {}) as Dictionary
	var parent_id: String = str(location.get("parent_region_id", ""))
	if not parent_id.is_empty():
		_current_city_parent_id = parent_id


func _player_world_point() -> Vector2:
	var location: Dictionary = _v2_3_local_location_lookup.get(_observer_location_id(), {}) as Dictionary
	if location.is_empty():
		return _camera_focus_point("lille")
	return project_lon_lat(location.get("world_position", []))


func _player_city_anchor() -> Vector2:
	_update_current_city_parent()
	return _city_anchor_for_parent(_current_city_parent_id)


func _city_anchor_for_parent(parent_id: String) -> Vector2:
	var centre_candidate: Dictionary = {}
	for raw_location: Variant in _v2_3_local_locations:
		if not raw_location is Dictionary:
			continue
		var location: Dictionary = raw_location as Dictionary
		if str(location.get("parent_region_id", "")) != parent_id:
			continue
		if str(location.get("location_type", "")) == "city_centre":
			centre_candidate = location
			break
		if centre_candidate.is_empty():
			centre_candidate = location
	if centre_candidate.is_empty():
		return _player_world_point()
	return project_lon_lat(centre_candidate.get("world_position", []))
