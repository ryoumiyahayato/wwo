class_name PrototypeV2MapCanvas
extends Control
## Programmatic, original placeholder geography for the isolated visual prototype.

const OCEAN_TOP := Color("#233b49")
const OCEAN_BOTTOM := Color("#142c38")
const COAST := Color("#d8c9a4")
const REGION_LINE := Color("#263b3d")
const RAIL_DARK := Color("#242c2a")
const RAIL_LIGHT := Color("#d0b16f")
const PORT := Color("#d9c27e")
const CITY := Color("#f1e7c9")
const LABEL := Color("#e8dfc6")
const LABEL_MUTED := Color("#b9b59f")
const SELECT := Color("#f0c866")
const FRONT := Color("#c45e51")
const FRONT_GLOW := Color(0.88, 0.37, 0.29, 0.24)

var map_data: Dictionary = {}
var mode_data: Dictionary = {}
var current_mode: String = "legal"
var selected_id: String = ""
var selected_type: String = ""
var zoom: float = 1.0
var pan: Vector2 = Vector2(80.0, 78.0)

var _font: Font
var _city_by_id: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_font = ThemeDB.fallback_font


func setup(regions_document: Dictionary, modes_document: Dictionary) -> void:
	map_data = regions_document
	mode_data = modes_document
	_city_by_id.clear()
	for city_variant: Variant in map_data.get("cities", []):
		if city_variant is Dictionary:
			var city: Dictionary = city_variant as Dictionary
			_city_by_id[str(city.get("id", ""))] = city
	queue_redraw()


func set_mode(mode_id: String) -> void:
	current_mode = mode_id
	queue_redraw()


func set_selection(object_type: String, object_id: String) -> void:
	selected_type = object_type
	selected_id = object_id
	queue_redraw()


func clear_selection() -> void:
	selected_type = ""
	selected_id = ""
	queue_redraw()


func pan_by(delta: Vector2) -> void:
	pan += delta
	_clamp_pan()
	queue_redraw()


func zoom_at(direction: float, anchor: Vector2) -> void:
	var minimum: float = float(mode_data.get("zoom_min", 0.78))
	var maximum: float = float(mode_data.get("zoom_max", 1.85))
	var step: float = float(mode_data.get("zoom_step", 0.12))
	var previous: float = zoom
	var next_zoom: float = clampf(zoom + direction * step, minimum, maximum)
	if is_equal_approx(previous, next_zoom):
		return
	var world_anchor: Vector2 = (anchor - pan) / previous
	zoom = next_zoom
	pan = anchor - world_anchor * zoom
	_clamp_pan()
	queue_redraw()


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2(80.0, 78.0)
	queue_redraw()


func get_object_at(screen_position: Vector2) -> Dictionary:
	var world_position: Vector2 = _to_world(screen_position)
	var city_radius: float = 13.0 / zoom
	for city_variant: Variant in map_data.get("cities", []):
		if not city_variant is Dictionary:
			continue
		var city: Dictionary = city_variant as Dictionary
		if world_position.distance_to(_array_to_vector(city.get("position", []))) <= city_radius:
			return {"type": "city", "id": str(city.get("id", "")), "data": city}
	var regions: Array = map_data.get("regions", []) as Array
	for index: int in range(regions.size() - 1, -1, -1):
		var region_variant: Variant = regions[index]
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant as Dictionary
		var polygon: PackedVector2Array = _polygon_points(region.get("polygon", []))
		if Geometry2D.is_point_in_polygon(world_position, polygon):
			return {"type": "region", "id": str(region.get("id", "")), "data": region}
	return {}


func get_region(region_id: String) -> Dictionary:
	for region_variant: Variant in map_data.get("regions", []):
		if region_variant is Dictionary and str((region_variant as Dictionary).get("id", "")) == region_id:
			return region_variant as Dictionary
	return {}


func get_city(city_id: String) -> Dictionary:
	var value: Variant = _city_by_id.get(city_id, {})
	return value as Dictionary if value is Dictionary else {}


func _draw() -> void:
	_draw_ocean()
	if map_data.is_empty():
		return
	_draw_regions()
	_draw_transport()
	if current_mode == "war":
		_draw_static_front()
	_draw_cities()
	_draw_scale_hint()


func _draw_ocean() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OCEAN_BOTTOM)
	var bands: int = 14
	for index: int in range(bands):
		var ratio: float = float(index) / float(bands)
		var color: Color = OCEAN_TOP.lerp(OCEAN_BOTTOM, ratio)
		color.a = 0.24
		draw_rect(Rect2(0.0, ratio * size.y, size.x, size.y / float(bands) + 1.0), color)
	for index: int in range(7):
		var y: float = 112.0 + float(index) * 76.0
		draw_arc(Vector2(size.x * 0.52, y), 360.0 + float(index) * 28.0, 3.32, 6.08, 48, Color(0.54, 0.71, 0.72, 0.08), 1.0)


func _draw_regions() -> void:
	for region_variant: Variant in map_data.get("regions", []):
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant as Dictionary
		var world_polygon: PackedVector2Array = _polygon_points(region.get("polygon", []))
		var screen_polygon := PackedVector2Array()
		for point: Vector2 in world_polygon:
			screen_polygon.append(_to_screen(point))
		var fill: Color = _region_color(region)
		draw_colored_polygon(screen_polygon, fill)
		draw_polyline(_closed_polygon(screen_polygon), Color(COAST, 0.72), maxf(1.0, 1.4 * zoom), true)
		draw_polyline(_closed_polygon(screen_polygon), REGION_LINE, maxf(0.8, 0.8 * zoom), true)
		if selected_type == "region" and selected_id == str(region.get("id", "")):
			draw_polyline(_closed_polygon(screen_polygon), SELECT, 4.0, true)
		var center: Vector2 = _polygon_center(world_polygon)
		_draw_centered_text(_to_screen(center) + Vector2(0.0, -5.0), str(region.get("name", "")), 15, LABEL)
		if zoom >= 1.05:
			_draw_centered_text(_to_screen(center) + Vector2(0.0, 13.0), str(region.get("country", "")), 11, LABEL_MUTED)


func _draw_transport() -> void:
	for connection_variant: Variant in map_data.get("railways", []):
		if not connection_variant is Array:
			continue
		var connection: Array = connection_variant as Array
		if connection.size() != 2:
			continue
		var first: Dictionary = get_city(str(connection[0]))
		var second: Dictionary = get_city(str(connection[1]))
		if first.is_empty() or second.is_empty():
			continue
		var start: Vector2 = _to_screen(_array_to_vector(first.get("position", [])))
		var end: Vector2 = _to_screen(_array_to_vector(second.get("position", [])))
		var distance: float = start.distance_to(end)
		if distance > 205.0 * zoom:
			_draw_dashed_line(start, end, Color(PORT, 0.48), 7.0, 5.0, 1.2)
		else:
			draw_line(start, end, Color(RAIL_DARK, 0.82), maxf(2.4, 3.6 * zoom), true)
			draw_line(start, end, Color(RAIL_LIGHT, 0.72), maxf(0.9, 1.2 * zoom), true)


func _draw_static_front() -> void:
	var front_points := PackedVector2Array([
		_to_screen(Vector2(618.0, 118.0)),
		_to_screen(Vector2(633.0, 144.0)),
		_to_screen(Vector2(625.0, 171.0)),
		_to_screen(Vector2(642.0, 198.0)),
	])
	draw_polyline(front_points, FRONT_GLOW, 12.0, true)
	draw_polyline(front_points, FRONT, 4.0, true)
	for point: Vector2 in front_points:
		draw_circle(point, 4.5, Color("#e6b06b"))


func _draw_cities() -> void:
	for city_variant: Variant in map_data.get("cities", []):
		if not city_variant is Dictionary:
			continue
		var city: Dictionary = city_variant as Dictionary
		var position: Vector2 = _to_screen(_array_to_vector(city.get("position", [])))
		var is_selected: bool = selected_type == "city" and selected_id == str(city.get("id", ""))
		if is_selected:
			draw_circle(position, 11.0, Color(SELECT, 0.2))
		draw_circle(position, 5.2 if bool(city.get("port", false)) else 4.3, SELECT if is_selected else CITY)
		draw_circle(position, 2.1, Color("#263335"))
		if bool(city.get("port", false)):
			draw_arc(position + Vector2(0.0, 4.0), 7.0, 0.2, 2.94, 12, PORT, 1.4)
		var city_id: String = str(city.get("id", ""))
		var always_labeled: bool = city_id in ["new_york", "buenos_aires", "alexandria", "calcutta", "tokyo"]
		if zoom >= 1.14 or is_selected or always_labeled:
			draw_string(_font, position + Vector2(9.0, 5.0), str(city.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, LABEL)


func _draw_scale_hint() -> void:
	var label: String = "战争视觉示例 · 静态假数据" if current_mode == "war" else "和平 · 无前线"
	draw_string(_font, Vector2(22.0, 356.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(LABEL_MUTED, 0.78))


func _region_color(region: Dictionary) -> Color:
	var key: String = "legal"
	match current_mode:
		"market":
			key = "market_color"
		"population":
			key = "population_color"
		"war":
			key = "war_color"
		_:
			key = "legal"
	var color := Color(str(region.get(key, "#7f8874")))
	if current_mode == "population":
		color = color.lightened(0.04)
	return Color(color, 0.94)


func _polygon_points(source: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if source is Array:
		for point_variant: Variant in source as Array:
			result.append(_array_to_vector(point_variant))
	return result


func _closed_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _array_to_vector(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _polygon_center(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point: Vector2 in points:
		total += point
	return total / float(points.size())


func _to_screen(world_position: Vector2) -> Vector2:
	return world_position * zoom + pan


func _to_world(screen_position: Vector2) -> Vector2:
	return (screen_position - pan) / zoom


func _clamp_pan() -> void:
	var world_array: Array = map_data.get("world_size", [1120, 560]) as Array
	var world_size := Vector2(float(world_array[0]), float(world_array[1])) * zoom
	var horizontal_margin: float = 260.0
	var vertical_margin: float = 180.0
	pan.x = clampf(pan.x, size.x - world_size.x - horizontal_margin, horizontal_margin)
	pan.y = clampf(pan.y, size.y - world_size.y - vertical_margin, vertical_margin)


func _draw_centered_text(position: Vector2, value: String, font_size: int, color: Color) -> void:
	var width: float = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font, position - Vector2(width * 0.5, 0.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_dashed_line(start: Vector2, end: Vector2, color: Color, dash: float, gap: float, width: float) -> void:
	var distance: float = start.distance_to(end)
	if distance <= 0.01:
		return
	var direction: Vector2 = (end - start) / distance
	var cursor: float = 0.0
	while cursor < distance:
		var segment_end: float = minf(cursor + dash, distance)
		draw_line(start + direction * cursor, start + direction * segment_end, color, width, true)
		cursor += dash + gap
