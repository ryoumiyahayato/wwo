class_name StrategicMapCanvas
extends Control
## Draws and hit-tests the complete strategic map without per-unit scene nodes.

signal unit_selected(unit_id: String)

const MAP_BACKGROUND: Color = Color("101823")
const GRID_COLOR: Color = Color(0.08, 0.11, 0.15, 0.75)
const REGION_BORDER_COLOR: Color = Color(0.86, 0.9, 0.93, 0.88)
const RAIL_DARK_COLOR: Color = Color(0.1, 0.12, 0.14, 0.9)
const RAIL_LIGHT_COLOR: Color = Color(0.72, 0.7, 0.58, 0.95)
const FRONTLINE_DARK_COLOR: Color = Color(0.08, 0.04, 0.03, 1.0)
const FRONTLINE_COLOR: Color = Color(1.0, 0.57, 0.3, 1.0)
const CONTESTED_COLOR: Color = Color(1.0, 0.86, 0.56, 0.42)
const SELECTION_COLOR: Color = Color(0.98, 0.88, 0.42, 1.0)
const CITY_COLOR: Color = Color(0.96, 0.96, 0.91, 1.0)
const DRAG_THRESHOLD: float = 5.0

var control_service: MapControlService
var rules: MapRulesConfig
var selected_unit_id: String = ""

var _zoom: float = 1.0
var _pan_offset: Vector2 = Vector2(34.0, 28.0)
var _left_button_down: bool = false
var _dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _country_colors: Dictionary = {}
var _fallback_font: Font


func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	_fallback_font = ThemeDB.fallback_font


func setup(service: MapControlService) -> void:
	control_service = service
	rules = service.rules
	_cache_country_colors()
	control_service.control_unit_changed.connect(_on_control_unit_changed)
	control_service.frontlines_changed.connect(_on_frontlines_changed)
	_center_map.call_deferred()
	queue_redraw()


func select_unit(unit_id: String) -> bool:
	if control_service == null or control_service.get_unit(unit_id) == null:
		return false
	selected_unit_id = unit_id
	unit_selected.emit(unit_id)
	queue_redraw()
	return true


func get_zoom() -> float:
	return _zoom


func get_pan_offset() -> Vector2:
	return _pan_offset


func set_zoom(value: float) -> void:
	zoom_at(value, size * 0.5)


func zoom_at(value: float, screen_anchor: Vector2) -> void:
	if rules == null:
		return
	var previous_zoom: float = _zoom
	var clamped_zoom: float = clampf(value, rules.min_zoom, rules.max_zoom)
	if is_equal_approx(previous_zoom, clamped_zoom):
		return
	var world_anchor: Vector2 = (screen_anchor - _pan_offset) / previous_zoom
	_zoom = clamped_zoom
	_pan_offset = screen_anchor - world_anchor * _zoom
	_clamp_pan()
	queue_redraw()


func pan_by(delta: Vector2) -> void:
	_pan_offset += delta
	_clamp_pan()
	queue_redraw()


func get_world_size() -> Vector2:
	if control_service == null or rules == null:
		return Vector2.ZERO
	var max_x: int = -1
	var max_y: int = -1
	for unit_id: String in control_service.get_sorted_unit_ids():
		var unit: ControlUnitData = control_service.get_unit(unit_id)
		max_x = maxi(max_x, unit.grid_x)
		max_y = maxi(max_y, unit.grid_y)
	return Vector2(
		float(max_x + 1) * rules.tile_width,
		float(max_y + 1) * rules.tile_height
	)


func _gui_input(event: InputEvent) -> void:
	if control_service == null:
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(_zoom + rules.zoom_step, mouse_button.position)
			accept_event()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(_zoom - rules.zoom_step, mouse_button.position)
			accept_event()
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_left_button_down = mouse_button.pressed
			if mouse_button.pressed:
				_dragging = false
				_press_position = mouse_button.position
			else:
				if not _dragging:
					_select_at_screen_position(mouse_button.position)
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _left_button_down:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if not _dragging and motion.position.distance_to(_press_position) >= DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			pan_by(motion.relative)
			accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MAP_BACKGROUND)
	if control_service == null or rules == null:
		return
	draw_set_transform(_pan_offset, 0.0, Vector2(_zoom, _zoom))
	_draw_unit_fills()
	_draw_contested_hatching()
	_draw_railroads()
	_draw_unit_and_region_borders()
	_draw_frontlines()
	_draw_cities_and_region_labels()
	_draw_selection()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_unit_fills() -> void:
	for unit_id: String in control_service.get_sorted_unit_ids():
		var unit: ControlUnitData = control_service.get_unit(unit_id)
		var rect: Rect2 = _unit_rect(unit).grow(-1.0)
		var fill: Color = _country_color(unit.controller_country_id)
		if unit.grid_y % 2 == 1:
			fill = fill.darkened(0.045)
		draw_rect(rect, fill, true)
		draw_rect(rect, GRID_COLOR, false, 1.0)


func _draw_contested_hatching() -> void:
	for unit_id: String in control_service.get_sorted_unit_ids():
		var unit: ControlUnitData = control_service.get_unit(unit_id)
		if unit.contested_level < rules.contested_threshold:
			continue
		var rect: Rect2 = _unit_rect(unit).grow(-4.0)
		var offset: float = -rect.size.y
		while offset < rect.size.x:
			var start_x: float = rect.position.x + offset
			var clipped_start_x: float = maxf(start_x, rect.position.x)
			var clipped_end_x: float = minf(start_x + rect.size.y, rect.end.x)
			var start_y: float = rect.end.y - (clipped_start_x - start_x)
			var end_y: float = rect.end.y - (clipped_end_x - start_x)
			draw_line(
				Vector2(clipped_start_x, start_y),
				Vector2(clipped_end_x, end_y),
				CONTESTED_COLOR,
				2.0
			)
			offset += 13.0


func _draw_railroads() -> void:
	for unit_id: String in control_service.get_sorted_unit_ids():
		var unit: ControlUnitData = control_service.get_unit(unit_id)
		for neighbor_id: String in unit.railroad_neighbor_ids:
			if unit.id >= neighbor_id:
				continue
			var neighbor: ControlUnitData = control_service.get_unit(neighbor_id)
			if neighbor == null:
				continue
			var start: Vector2 = _unit_rect(unit).get_center()
			var finish: Vector2 = _unit_rect(neighbor).get_center()
			draw_line(start, finish, RAIL_DARK_COLOR, 6.0, true)
			draw_line(start, finish, RAIL_LIGHT_COLOR, 2.2, true)


func _draw_unit_and_region_borders() -> void:
	for unit_id: String in control_service.get_sorted_unit_ids():
		var unit: ControlUnitData = control_service.get_unit(unit_id)
		var rect: Rect2 = _unit_rect(unit)
		var legal_color: Color = _country_color(unit.de_jure_country_id).lightened(0.28)
		draw_rect(rect.grow(-1.0), legal_color, false, 1.25)
		var directions: Array[Vector2i] = [
			Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
		]
		for direction: Vector2i in directions:
			var neighbor: ControlUnitData = control_service.get_unit_at(
				unit.grid_x + direction.x,
				unit.grid_y + direction.y
			)
			if neighbor == null or neighbor.region_id != unit.region_id:
				_draw_rect_side(rect, direction, REGION_BORDER_COLOR, 2.5)


func _draw_frontlines() -> void:
	for edge: Dictionary in control_service.get_frontline_edges():
		var first: ControlUnitData = control_service.get_unit(str(edge["a"]))
		var second: ControlUnitData = control_service.get_unit(str(edge["b"]))
		if first == null or second == null:
			continue
		var segment: PackedVector2Array = _shared_boundary(first, second)
		if segment.size() != 2:
			continue
		draw_line(segment[0], segment[1], FRONTLINE_DARK_COLOR, 8.0, true)
		draw_line(segment[0], segment[1], FRONTLINE_COLOR, 3.5, true)


func _draw_cities_and_region_labels() -> void:
	for unit_id: String in control_service.get_sorted_unit_ids():
		var unit: ControlUnitData = control_service.get_unit(unit_id)
		if not unit.city_name.is_empty():
			var center: Vector2 = _unit_rect(unit).get_center()
			draw_circle(center, 6.0, Color(0.08, 0.1, 0.13, 1.0))
			draw_circle(center, 3.5, CITY_COLOR)
			draw_string(
				_fallback_font,
				center + Vector2(8.0, -7.0),
				unit.city_name,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				13,
				CITY_COLOR
			)
		if unit.grid_x in [0, 5] and unit.grid_y % 2 == 0:
			var region: RegionData = control_service.data_set.regions[unit.region_id] as RegionData
			draw_string(
				_fallback_font,
				_unit_rect(unit).position + Vector2(7.0, 17.0),
				region.name,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				12,
				Color(1.0, 1.0, 1.0, 0.72)
			)


func _draw_selection() -> void:
	if selected_unit_id.is_empty():
		return
	var unit: ControlUnitData = control_service.get_unit(selected_unit_id)
	if unit != null:
		draw_rect(_unit_rect(unit).grow(-2.5), SELECTION_COLOR, false, 3.0)


func _draw_rect_side(rect: Rect2, direction: Vector2i, color: Color, width: float) -> void:
	var start: Vector2
	var finish: Vector2
	if direction == Vector2i(-1, 0):
		start = rect.position
		finish = rect.position + Vector2(0.0, rect.size.y)
	elif direction == Vector2i(1, 0):
		start = rect.position + Vector2(rect.size.x, 0.0)
		finish = rect.end
	elif direction == Vector2i(0, -1):
		start = rect.position
		finish = rect.position + Vector2(rect.size.x, 0.0)
	else:
		start = rect.position + Vector2(0.0, rect.size.y)
		finish = rect.end
	draw_line(start, finish, color, width, true)


func _shared_boundary(first: ControlUnitData, second: ControlUnitData) -> PackedVector2Array:
	var first_rect: Rect2 = _unit_rect(first)
	if first.grid_x != second.grid_x:
		var boundary_x: float = float(maxi(first.grid_x, second.grid_x)) * rules.tile_width
		return PackedVector2Array([
			Vector2(boundary_x, first_rect.position.y),
			Vector2(boundary_x, first_rect.end.y),
		])
	if first.grid_y != second.grid_y:
		var boundary_y: float = float(maxi(first.grid_y, second.grid_y)) * rules.tile_height
		return PackedVector2Array([
			Vector2(first_rect.position.x, boundary_y),
			Vector2(first_rect.end.x, boundary_y),
		])
	return PackedVector2Array()


func _select_at_screen_position(screen_position: Vector2) -> void:
	var world_position: Vector2 = (screen_position - _pan_offset) / _zoom
	var grid_x: int = int(floor(world_position.x / rules.tile_width))
	var grid_y: int = int(floor(world_position.y / rules.tile_height))
	var unit: ControlUnitData = control_service.get_unit_at(grid_x, grid_y)
	if unit != null:
		select_unit(unit.id)


func _unit_rect(unit: ControlUnitData) -> Rect2:
	return Rect2(
		Vector2(float(unit.grid_x) * rules.tile_width, float(unit.grid_y) * rules.tile_height),
		Vector2(rules.tile_width, rules.tile_height)
	)


func _country_color(country_id: String) -> Color:
	return _country_colors.get(country_id, Color(0.38, 0.42, 0.46, 1.0)) as Color


func _cache_country_colors() -> void:
	_country_colors.clear()
	for country_value: Variant in control_service.data_set.countries.values():
		var country: CountryData = country_value as CountryData
		_country_colors[country.id] = Color.from_string(
			str(country.public_status.get("map_color", "#68717a")),
			Color(0.4, 0.44, 0.48, 1.0)
		)


func _center_map() -> void:
	var world_size: Vector2 = get_world_size()
	if world_size == Vector2.ZERO:
		return
	_zoom = clampf(
		minf((size.x - 28.0) / world_size.x, (size.y - 28.0) / world_size.y),
		rules.min_zoom,
		minf(rules.max_zoom, 1.0)
	)
	_pan_offset = (size - world_size * _zoom) * 0.5
	_clamp_pan()
	queue_redraw()


func _clamp_pan() -> void:
	if rules == null:
		return
	var scaled_world: Vector2 = get_world_size() * _zoom
	_pan_offset.x = _clamp_axis(
		_pan_offset.x,
		scaled_world.x,
		size.x,
		rules.pan_visible_margin
	)
	_pan_offset.y = _clamp_axis(
		_pan_offset.y,
		scaled_world.y,
		size.y,
		rules.pan_visible_margin
	)


static func _clamp_axis(
	value: float,
	scaled_extent: float,
	viewport_extent: float,
	margin: float
) -> float:
	if scaled_extent + margin * 2.0 <= viewport_extent:
		return (viewport_extent - scaled_extent) * 0.5
	return clampf(value, margin - scaled_extent, viewport_extent - margin)


func _on_control_unit_changed(_unit_id: String) -> void:
	queue_redraw()


func _on_frontlines_changed() -> void:
	queue_redraw()
