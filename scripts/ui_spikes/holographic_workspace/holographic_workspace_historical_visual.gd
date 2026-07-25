extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_history_runtime.gd"

var _historical_flag_pattern_pieces: Dictionary = {}
var _historical_flag_wave_pieces: Dictionary = {}


func _ensure_projection_cache() -> void:
	var rebuild_patterns: bool = _projection_dirty or _historical_flag_pattern_pieces.is_empty()
	super._ensure_projection_cache()
	if rebuild_patterns:
		_rebuild_historical_flag_pattern_cache()


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = clampf(inverse_lerp(HISTORY_ZOOM_MIN, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0)
	for entity_key_value: Variant in _historical_flag_pattern_pieces.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var alpha: float = _historical_entity_skin_alpha(entity, zoom_mix)
		var entity_phase: float = float(abs(entity_id.hash()) % 997) / 997.0
		var pieces: Array = _historical_flag_pattern_pieces.get(entity_id, []) as Array
		for piece_value: Variant in pieces:
			var piece: Dictionary = piece_value as Dictionary
			var polygon: PackedVector2Array = piece.get("polygon", PackedVector2Array()) as PackedVector2Array
			var base_color: Color = piece.get("color", Color(0.45, 0.55, 0.55, 1.0)) as Color
			var local_phase: float = float(piece.get("phase", 0.0))
			var wave: float = sin(_flag_time * (0.52 + entity_phase * 0.18) + local_phase + entity_phase * TAU)
			var brightness: float = 0.96 + wave * 0.055
			var color: Color = Color(
				clampf(base_color.r * brightness, 0.0, 1.0),
				clampf(base_color.g * brightness, 0.0, 1.0),
				clampf(base_color.b * brightness, 0.0, 1.0),
				alpha
			)
			if polygon.size() > 2:
				draw_colored_polygon(polygon, color)

		var wave_pieces: Array = _historical_flag_wave_pieces.get(entity_id, []) as Array
		for wave_piece_value: Variant in wave_pieces:
			var wave_piece: Dictionary = wave_piece_value as Dictionary
			var wave_polygon: PackedVector2Array = wave_piece.get("polygon", PackedVector2Array()) as PackedVector2Array
			var phase: float = float(wave_piece.get("phase", 0.0))
			var highlight: float = 0.5 + 0.5 * sin(_flag_time * 0.46 + phase + entity_phase * TAU)
			if wave_polygon.size() > 2:
				draw_colored_polygon(wave_polygon, Color(0.72, 0.84, 0.80, alpha * (0.012 + highlight * 0.026)))


func _select_global_object_at(position: Vector2, click: bool) -> void:
	_ensure_projection_cache()
	var nearest_event: String = ""
	var nearest_event_distance: float = 12.0
	for event_key_value: Variant in _event_screen_positions.keys():
		var event_id: String = str(event_key_value)
		var event_point: Vector2 = _event_screen_positions.get(event_id, Vector2.ZERO) as Vector2
		var event_distance: float = position.distance_to(event_point)
		if event_distance < nearest_event_distance:
			nearest_event = event_id
			nearest_event_distance = event_distance

	if not nearest_event.is_empty():
		if hover_event_id != nearest_event or not hover_country_id.is_empty():
			hover_event_id = nearest_event
			hover_country_id = ""
			queue_redraw()
		if click:
			selected_event_id = nearest_event
			selected_country_id = ""
			selected_region_id = ""
			selected_institution_id = ""
			_set_info_open(true)
		return

	var polygon_entity: String = _historical_entity_at(position)
	if polygon_entity.is_empty():
		polygon_entity = _nearest_history_anchor(position)
	if hover_country_id != polygon_entity or not hover_event_id.is_empty():
		hover_country_id = polygon_entity
		hover_event_id = ""
		queue_redraw()
	if click and not polygon_entity.is_empty():
		selected_country_id = polygon_entity
		selected_event_id = ""
		selected_region_id = ""
		selected_institution_id = ""
		_mark_projection_dirty()
		_set_info_open(true)


func _rebuild_historical_flag_pattern_cache() -> void:
	_historical_flag_pattern_pieces.clear()
	_historical_flag_wave_pieces.clear()
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var palette_key: String = str(entity.get("iso_a3", ""))
		var palette: Dictionary = _resolved_flag_palette(palette_key)
		var pattern: String = str(palette.get("pattern", "solid"))
		var colors: PackedColorArray = palette.get("colors", PackedColorArray()) as PackedColorArray
		if colors.is_empty():
			continue
		var bounds: Rect2 = _flag_screen_bounds.get(entity_id, Rect2()) as Rect2
		var entity_pieces: Array[Dictionary] = []
		var entity_waves: Array[Dictionary] = []
		for polygon_value: Variant in (_flag_screen_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			_append_flag_pattern_pieces(entity_pieces, polygon, bounds, pattern, colors)
			_append_flag_wave_pieces(entity_waves, polygon, bounds)
		_historical_flag_pattern_pieces[entity_id] = entity_pieces
		_historical_flag_wave_pieces[entity_id] = entity_waves


func _append_flag_pattern_pieces(
	output: Array[Dictionary],
	polygon: PackedVector2Array,
	bounds: Rect2,
	pattern: String,
	colors: PackedColorArray
) -> void:
	if polygon.size() < 3:
		return
	if pattern == "vertical":
		_append_bands(output, polygon, bounds, colors, true)
		return
	if pattern == "horizontal":
		_append_bands(output, polygon, bounds, colors, false)
		return
	if pattern == "cross":
		_append_solid_piece(output, polygon, colors[0], 0.0)
		var cross_color: Color = colors[mini(1, colors.size() - 1)]
		_append_rect_piece(output, polygon, Rect2(bounds.position.x + bounds.size.x * 0.43, bounds.position.y, bounds.size.x * 0.14, bounds.size.y), cross_color, 1.2)
		_append_rect_piece(output, polygon, Rect2(bounds.position.x, bounds.position.y + bounds.size.y * 0.43, bounds.size.x, bounds.size.y * 0.14), cross_color, 2.4)
		if colors.size() > 2:
			_append_rect_piece(output, polygon, Rect2(bounds.position.x + bounds.size.x * 0.475, bounds.position.y, bounds.size.x * 0.05, bounds.size.y), colors[2], 3.2)
			_append_rect_piece(output, polygon, Rect2(bounds.position.x, bounds.position.y + bounds.size.y * 0.475, bounds.size.x, bounds.size.y * 0.05), colors[2], 4.0)
		return
	if pattern == "canton":
		var stripe_colors: PackedColorArray = PackedColorArray([colors[0], colors[mini(1, colors.size() - 1)]])
		_append_bands(output, polygon, bounds, stripe_colors, false)
		if colors.size() > 2:
			_append_rect_piece(output, polygon, Rect2(bounds.position, Vector2(bounds.size.x * 0.42, bounds.size.y * 0.44)), colors[2], 4.5)
		return
	if pattern == "disc":
		_append_solid_piece(output, polygon, colors[0], 0.0)
		if colors.size() > 1:
			_append_shape_piece(output, polygon, _circle_polygon(bounds.get_center(), minf(bounds.size.x, bounds.size.y) * 0.24, 28), colors[1], 2.4)
		if colors.size() > 2:
			_append_shape_piece(output, polygon, _circle_polygon(bounds.get_center(), minf(bounds.size.x, bounds.size.y) * 0.095, 24), colors[2], 3.6)
		return
	if pattern == "quartered":
		var half: Vector2 = bounds.size * 0.5
		for quadrant: int in range(4):
			var offset: Vector2 = Vector2(float(quadrant % 2) * half.x, float(quadrant / 2) * half.y)
			_append_rect_piece(output, polygon, Rect2(bounds.position + offset, half), colors[quadrant % colors.size()], float(quadrant) * 1.4)
		return
	if pattern == "diagonal":
		var top_left: Vector2 = bounds.position
		var top_right: Vector2 = Vector2(bounds.end.x, bounds.position.y)
		var bottom_left: Vector2 = Vector2(bounds.position.x, bounds.end.y)
		var bottom_right: Vector2 = bounds.end
		_append_shape_piece(output, polygon, PackedVector2Array([top_left, top_right, bottom_left]), colors[0], 0.0)
		_append_shape_piece(output, polygon, PackedVector2Array([top_right, bottom_right, bottom_left]), colors[mini(1, colors.size() - 1)], 2.2)
		if colors.size() > 2:
			var width: float = minf(bounds.size.x, bounds.size.y) * 0.10
			var diagonal: PackedVector2Array = PackedVector2Array([
				top_right + Vector2(-width, 0.0),
				top_right,
				bottom_left + Vector2(width, 0.0),
				bottom_left,
			])
			_append_shape_piece(output, polygon, diagonal, colors[2], 3.5)
		return
	_append_solid_piece(output, polygon, colors[0], 0.0)
	if colors.size() > 1:
		_append_rect_piece(output, polygon, Rect2(bounds.position.x + bounds.size.x * 0.46, bounds.position.y + bounds.size.y * 0.35, bounds.size.x * 0.08, bounds.size.y * 0.30), colors[1], 2.0)


func _append_bands(
	output: Array[Dictionary],
	polygon: PackedVector2Array,
	bounds: Rect2,
	colors: PackedColorArray,
	vertical: bool
) -> void:
	var count: int = colors.size()
	for index: int in range(count):
		var rect: Rect2
		if vertical:
			var width: float = bounds.size.x / float(count)
			rect = Rect2(bounds.position + Vector2(width * float(index), 0.0), Vector2(width + 0.5, bounds.size.y))
		else:
			var height: float = bounds.size.y / float(count)
			rect = Rect2(bounds.position + Vector2(0.0, height * float(index)), Vector2(bounds.size.x, height + 0.5))
		_append_rect_piece(output, polygon, rect, colors[index], float(index) * 1.35)


func _append_flag_wave_pieces(output: Array[Dictionary], polygon: PackedVector2Array, bounds: Rect2) -> void:
	if bounds.size.x < 3.0 or bounds.size.y < 3.0:
		return
	var slice_count: int = 6
	var slice_width: float = bounds.size.x / float(slice_count)
	for index: int in range(slice_count):
		var rect: Rect2 = Rect2(
			bounds.position + Vector2(slice_width * float(index), 0.0),
			Vector2(slice_width * 0.72, bounds.size.y)
		)
		var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(polygon, _rect_polygon(rect))
		for intersection: PackedVector2Array in intersections:
			if intersection.size() > 2:
				output.append({"polygon": intersection, "phase": float(index) * 0.92})


func _append_solid_piece(output: Array[Dictionary], polygon: PackedVector2Array, color: Color, phase: float) -> void:
	output.append({"polygon": polygon, "color": color, "phase": phase})


func _append_rect_piece(
	output: Array[Dictionary],
	subject: PackedVector2Array,
	rect: Rect2,
	color: Color,
	phase: float
) -> void:
	_append_shape_piece(output, subject, _rect_polygon(rect), color, phase)


func _append_shape_piece(
	output: Array[Dictionary],
	subject: PackedVector2Array,
	shape: PackedVector2Array,
	color: Color,
	phase: float
) -> void:
	var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(subject, shape)
	for intersection: PackedVector2Array in intersections:
		if intersection.size() > 2:
			output.append({"polygon": intersection, "color": color, "phase": phase})


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func _circle_polygon(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var output: PackedVector2Array = PackedVector2Array()
	for index: int in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		output.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return output


func _historical_entity_skin_alpha(entity: Dictionary, zoom_mix: float) -> float:
	var alpha: float = lerpf(0.40, 0.17, zoom_mix)
	var status: String = str(entity.get("status", "sovereign"))
	if status == "dependency" or status == "autonomous":
		alpha *= 0.80
	if bool(entity.get("provisional", false)):
		alpha *= 0.40
	var entity_id: String = str(entity.get("id", ""))
	if entity_id == selected_country_id:
		alpha = maxf(alpha, 0.50)
	elif entity_id == hover_country_id:
		alpha = maxf(alpha, 0.42)
	return alpha


func _historical_entity_at(position: Vector2) -> String:
	var best: String = ""
	var best_priority: int = -999
	var best_area: float = 1e20
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var provisional: bool = bool(entity.get("provisional", false))
		var priority: int = 0 if provisional else 100
		priority += 12 - int(entity.get("label_rank", 9))
		for polygon_value: Variant in (_flag_screen_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			if not Geometry2D.is_point_in_polygon(position, polygon):
				continue
			var area: float = absf(_screen_polygon_area(polygon))
			if priority > best_priority or (priority == best_priority and area < best_area):
				best = entity_id
				best_priority = priority
				best_area = area
	return best


func _nearest_history_anchor(position: Vector2) -> String:
	var best: String = ""
	var best_distance: float = 18.0
	for entity_key_value: Variant in _country_screen_anchors.keys():
		var entity_id: String = str(entity_key_value)
		var point: Vector2 = _country_screen_anchors.get(entity_id, Vector2.ZERO) as Vector2
		var distance: float = position.distance_to(point)
		if distance < best_distance:
			best = entity_id
			best_distance = distance
	return best


func _screen_polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var area: float = 0.0
	for index: int in range(points.size()):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % points.size()]
		area += current.x * following.y - following.x * current.y
	return area * 0.5
