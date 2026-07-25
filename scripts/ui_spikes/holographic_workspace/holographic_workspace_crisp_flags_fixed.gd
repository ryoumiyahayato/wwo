extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1.gd"

const FLAG_TEXTURE_WIDTH: int = 144
const FLAG_TEXTURE_HEIGHT: int = 96
const ADMIN1_GLOBAL_ZOOM_START: float = 2.20
const ADMIN1_GLOBAL_LABEL_ZOOM: float = 4.10

var _flag_texture_by_entity: Dictionary = {}
var _historical_outline_polygons: Dictionary = {}
var _world_admin1_unit_cache: Dictionary = {}
var _world_admin1_country_count: int = 0


func _ready() -> void:
	super._ready()
	var country_keys: Dictionary = {}
	for iso_value: Variant in _world_admin1_by_iso.keys():
		country_keys[str(iso_value)] = true
	_world_admin1_country_count = country_keys.size()
	_prewarm_distinctive_flag_textures()
	_mark_projection_dirty()
	queue_redraw()


func _ensure_projection_cache() -> void:
	var rebuild_outlines: bool = _projection_dirty or _historical_outline_polygons.is_empty()
	super._ensure_projection_cache()
	if rebuild_outlines:
		_rebuild_merged_historical_outlines()


func _draw_global_world() -> void:
	_draw_rotating_globe_grid()
	_draw_country_flag_skins()
	_draw_selected_admin1_on_globe()
	_draw_historical_entity_borders()
	_draw_historical_conflicts()
	_draw_historical_entity_anchors()
	_draw_world_event_markers()
	_draw_zoom_country_labels()
	_draw_zoom_indicator()
	_draw_history_layer_controls()


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = clampf(inverse_lerp(HISTORY_ZOOM_MIN, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0)
	var base_alpha: float = lerpf(0.50, 0.23, zoom_mix)
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var palette: Dictionary = _resolved_flag_palette(str(entity.get("iso_a3", "")))
		var status: String = str(entity.get("status", "sovereign"))
		var provisional: bool = bool(entity.get("provisional", false))
		var alpha: float = base_alpha
		if status == "dependency" or status == "autonomous":
			alpha *= 0.82
		if provisional:
			alpha *= 0.30
		if entity_id == selected_country_id:
			alpha = maxf(alpha, 0.64)
		elif entity_id == hover_country_id:
			alpha = maxf(alpha, 0.55)
		for polygon_value: Variant in (_flag_screen_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			_draw_flag_polygon(polygon, _screen_polygon_bounds(polygon), palette, entity_id, alpha)


func _draw_flag_polygon(
	polygon: PackedVector2Array,
	bounds: Rect2,
	palette: Dictionary,
	entity_id: String,
	alpha: float
) -> void:
	if polygon.size() < 3:
		return
	var texture: ImageTexture = _flag_texture_for_entity(entity_id, palette)
	if texture == null:
		return
	var safe_width: float = maxf(bounds.size.x, 1.0)
	var safe_height: float = maxf(bounds.size.y, 1.0)
	var phase: float = float(abs(entity_id.hash()) % 997) / 997.0
	var uvs: PackedVector2Array = PackedVector2Array()
	var modulations: PackedColorArray = PackedColorArray()
	for point: Vector2 in polygon:
		var u: float = clampf((point.x - bounds.position.x) / safe_width, 0.0, 1.0)
		var v: float = clampf((point.y - bounds.position.y) / safe_height, 0.0, 1.0)
		var cloth_wave: float = sin(_flag_time * (0.42 + phase * 0.18) + v * TAU * 1.35 + phase * TAU)
		var secondary: float = sin(_flag_time * 0.24 + u * TAU * 0.85 - phase * 3.0)
		uvs.append(Vector2(clampf(u + cloth_wave * (0.010 + v * 0.010), 0.002, 0.998), v))
		var brightness: float = 0.96 + cloth_wave * 0.055 + secondary * 0.018
		modulations.append(Color(brightness, brightness, brightness, alpha * (0.97 + cloth_wave * 0.025)))
	draw_polygon(polygon, modulations, uvs, texture)


func _flag_texture_for_entity(entity_id: String, palette: Dictionary) -> ImageTexture:
	if _flag_texture_by_entity.has(entity_id):
		return _flag_texture_by_entity.get(entity_id) as ImageTexture
	var colors: PackedColorArray = palette.get("colors", PackedColorArray()) as PackedColorArray
	if colors.is_empty():
		return null
	var pattern: String = _distinctive_pattern_for_entity(entity_id, str(palette.get("pattern", "solid")))
	var image: Image = Image.create(FLAG_TEXTURE_WIDTH, FLAG_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(FLAG_TEXTURE_HEIGHT):
		var v: float = (float(y) + 0.5) / float(FLAG_TEXTURE_HEIGHT)
		for x: int in range(FLAG_TEXTURE_WIDTH):
			var u: float = (float(x) + 0.5) / float(FLAG_TEXTURE_WIDTH)
			var color: Color = _distinctive_flag_color(pattern, colors, u, v)
			var weave: float = 0.975 + 0.025 * sin(float(y) * 0.73) * sin(float(x) * 0.19)
			image.set_pixel(x, y, Color(color.r * weave, color.g * weave, color.b * weave, 1.0))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_flag_texture_by_entity[entity_id] = texture
	return texture


func _distinctive_pattern_for_entity(entity_id: String, fallback: String) -> String:
	match entity_id:
		"british_isles_1900", "british_empire_overseas":
			return "union"
		"united_states_1900", "united_states_overseas":
			return "stripes_canton"
		"qing_empire":
			return "dragon_disc"
		"empire_of_japan":
			return "sun_disc"
		"ottoman_empire":
			return "crescent"
		"austria_hungary":
			return "dual_monarchy"
		"kingdom_of_nepal":
			return "double_pennant"
		"kingdom_of_bhutan":
			return "dragon_diagonal"
		_:
			return fallback


func _distinctive_flag_color(pattern: String, colors: PackedColorArray, u: float, v: float) -> Color:
	var count: int = colors.size()
	var c0: Color = colors[0]
	var c1: Color = colors[mini(1, count - 1)]
	var c2: Color = colors[mini(2, count - 1)]
	var c3: Color = colors[mini(3, count - 1)]
	if pattern == "union":
		var color: Color = c0
		var diagonal_a: float = absf(v - u * 0.67 - 0.165)
		var diagonal_b: float = absf(v + u * 0.67 - 0.835)
		if diagonal_a < 0.105 or diagonal_b < 0.105:
			color = c1
		if diagonal_a < 0.035 or diagonal_b < 0.035:
			color = c2
		if absf(u - 0.5) < 0.115 or absf(v - 0.5) < 0.17:
			color = c1
		if absf(u - 0.5) < 0.050 or absf(v - 0.5) < 0.075:
			color = c2
		return color
	if pattern == "stripes_canton":
		var stripe: Color = c0 if int(floor(v * 13.0)) % 2 == 0 else c1
		if u < 0.42 and v < 0.54:
			var star_u: float = fposmod(u * 13.0, 1.0)
			var star_v: float = fposmod(v * 11.0, 1.0)
			var star_cell: Vector2 = Vector2(star_u, star_v) - Vector2(0.5, 0.5)
			return c1 if star_cell.length() < 0.075 else c2
		return stripe
	if pattern == "dragon_disc":
		var center_distance: float = Vector2(u, v).distance_to(Vector2(0.53, 0.50))
		if center_distance < 0.24:
			var angle: float = atan2(v - 0.5, u - 0.53)
			var spiral: float = absf(sin(angle * 2.5 + center_distance * 22.0))
			return c2 if center_distance < 0.07 else c1.lerp(c2, spiral * 0.34)
		return c0
	if pattern == "sun_disc":
		return c1 if Vector2(u, v).distance_to(Vector2(0.5, 0.5)) < 0.245 else c0
	if pattern == "crescent":
		var outer: bool = Vector2(u, v).distance_to(Vector2(0.48, 0.5)) < 0.25
		var inner: bool = Vector2(u, v).distance_to(Vector2(0.56, 0.47)) < 0.205
		var star: bool = Vector2(u, v).distance_to(Vector2(0.70, 0.50)) < 0.055
		return c1 if (outer and not inner) or star else c0
	if pattern == "dual_monarchy":
		if u < 0.5:
			return c2 if v < 0.30 or v > 0.70 else c1
		if v < 0.30:
			return c2
		if v > 0.70:
			return Color(0.22, 0.43, 0.30, 1.0)
		return c3
	if pattern == "double_pennant":
		var upper_triangle: bool = v < 0.49 and u < 0.78 - v * 0.45
		var lower_triangle: bool = v >= 0.43 and u < 0.88 - (v - 0.43) * 0.55
		var border_band: bool = (upper_triangle or lower_triangle) and (u < 0.045 or absf(v - 0.49) < 0.035)
		if border_band:
			return c1
		if upper_triangle or lower_triangle:
			var emblem_center: Vector2 = Vector2(0.28, 0.27 if v < 0.49 else 0.70)
			return c2 if Vector2(u, v).distance_to(emblem_center) < 0.075 else c0
		return Color(0.035, 0.055, 0.065, 1.0)
	if pattern == "dragon_diagonal":
		var base: Color = c0 if u + v < 1.0 else c1
		var body: float = absf(v - (0.76 - u * 0.52 + sin(u * 12.0) * 0.035))
		return c2 if body < 0.045 and u > 0.20 and u < 0.82 else base
	return _flag_pattern_color(pattern, colors, u, v)


func _prewarm_distinctive_flag_textures() -> void:
	var key_entities: Array[String] = [
		"country_fra", "german_empire", "british_isles_1900", "austria_hungary",
		"russian_empire", "ottoman_empire", "qing_empire", "empire_of_japan",
		"united_states_1900", "kingdom_of_nepal", "kingdom_of_bhutan"
	]
	for entity_id: String in key_entities:
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		if not entity.is_empty():
			_flag_texture_for_entity(entity_id, _resolved_flag_palette(str(entity.get("iso_a3", ""))))


func _flag_texture_signature(entity_id: String) -> String:
	var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
	if entity.is_empty():
		return ""
	var texture: ImageTexture = _flag_texture_for_entity(entity_id, _resolved_flag_palette(str(entity.get("iso_a3", ""))))
	if texture == null:
		return ""
	var image: Image = texture.get_image()
	var samples: Array[Vector2i] = [Vector2i(14, 16), Vector2i(72, 16), Vector2i(126, 16), Vector2i(24, 48), Vector2i(72, 48), Vector2i(120, 72)]
	var parts: PackedStringArray = PackedStringArray()
	for point: Vector2i in samples:
		parts.append(image.get_pixel(point.x, point.y).to_html(false))
	return "-".join(parts)


func _screen_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var minimum: Vector2 = polygon[0]
	var maximum: Vector2 = polygon[0]
	for point: Vector2 in polygon:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _rebuild_merged_historical_outlines() -> void:
	_historical_outline_polygons.clear()
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var merged: Array[PackedVector2Array] = []
		for polygon_value: Variant in (_flag_screen_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			var absorbed: bool = false
			var polygon_bounds: Rect2 = _screen_polygon_bounds(polygon).grow(1.2)
			for index: int in range(merged.size()):
				if not _screen_polygon_bounds(merged[index]).grow(1.2).intersects(polygon_bounds):
					continue
				var union_result: Array = Geometry2D.merge_polygons(merged[index], polygon)
				if union_result.size() == 1:
					merged[index] = union_result[0] as PackedVector2Array
					absorbed = true
					break
			if not absorbed:
				merged.append(polygon)
		_historical_outline_polygons[entity_id] = merged


func _history_border_pulse_value(entity_id: String) -> float:
	var phase: float = float(abs(entity_id.hash()) % 997) / 997.0
	return 0.5 + 0.5 * sin(_flag_time * (0.43 + phase * 0.16) + phase * TAU)


func _historical_border_geometry_signature() -> String:
	var point_count: int = 0
	var checksum_x: int = 0
	var checksum_y: int = 0
	for entity_value: Variant in _historical_outline_polygons.keys():
		for polygon_value: Variant in (_historical_outline_polygons.get(str(entity_value), []) as Array):
			for point: Vector2 in (polygon_value as PackedVector2Array):
				point_count += 1
				checksum_x += int(round(point.x * 10.0))
				checksum_y += int(round(point.y * 10.0))
	return "%d:%d:%d" % [point_count, checksum_x, checksum_y]


func _draw_historical_entity_borders() -> void:
	for entity_key_value: Variant in _historical_outline_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var status: String = str(entity.get("status", "sovereign"))
		var provisional: bool = bool(entity.get("provisional", false))
		var pulse: float = _history_border_pulse_value(entity_id)
		var color: Color = Color(0.73, 0.83, 0.77, 0.43 + pulse * 0.12)
		var width: float = 1.30 + pulse * 0.20
		if status == "dependency" or status == "autonomous":
			color = Color(0.75, 0.69, 0.49, color.a * 0.86)
			width = 1.05
		elif status == "contested" or status == "fragmented":
			color = Color(0.93, 0.54, 0.29, color.a + 0.12)
			width = 1.65
		if provisional:
			color.a *= 0.30
		if entity_id == hover_country_id:
			color = Color(0.84, 0.96, 0.90, 0.92)
			width = 2.0
		if entity_id == selected_country_id:
			color = Color(0.98, 0.82, 0.43, 0.99)
			width = 2.45
		for polygon_value: Variant in (_historical_outline_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			if status == "dependency" or status == "autonomous" or provisional:
				_draw_dashed_polyline(polygon, color, width, 6.0, 4.0)
			else:
				draw_polyline(polygon, color, width, true)


func _admin1_unit_lines_for_iso(iso: String) -> Array:
	if _world_admin1_unit_cache.has(iso):
		return _world_admin1_unit_cache.get(iso, []) as Array
	var output: Array = []
	for record_value: Variant in (_world_admin1_by_iso.get(iso, []) as Array):
		var record: Dictionary = record_value as Dictionary
		var unit_lines: Array = []
		for polygon_value: Variant in (record.get("runtime_polygons", []) as Array):
			unit_lines.append(_to_unit_line(polygon_value as PackedVector2Array))
		output.append({"record": record, "unit_lines": unit_lines})
	_world_admin1_unit_cache[iso] = output
	return output


func _selected_global_territory_iso() -> String:
	if not selected_historical_territory_iso.is_empty():
		return selected_historical_territory_iso
	var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
	if territories.is_empty():
		return ""
	var config: Dictionary = _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	for core_value: Variant in (config.get("core_members", []) as Array):
		var core_iso: String = str(core_value).to_upper()
		for territory_value: Variant in territories:
			if str((territory_value as Dictionary).get("iso_a3", "")) == core_iso:
				return core_iso
	return str((territories[0] as Dictionary).get("iso_a3", ""))


func _draw_selected_admin1_on_globe() -> void:
	if world_zoom < ADMIN1_GLOBAL_ZOOM_START or selected_country_id.is_empty():
		return
	var iso: String = _selected_global_territory_iso()
	if iso.is_empty():
		return
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	var alpha: float = lerpf(0.16, 0.48, clampf(inverse_lerp(ADMIN1_GLOBAL_ZOOM_START, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0))
	var labels_drawn: int = 0
	for entry_value: Variant in _admin1_unit_lines_for_iso(iso):
		var entry: Dictionary = entry_value as Dictionary
		var record: Dictionary = entry.get("record", {}) as Dictionary
		for unit_line_value: Variant in (entry.get("unit_lines", []) as Array):
			var unit_line: PackedVector3Array = unit_line_value
			for segment: PackedVector2Array in _project_unit_line(unit_line, basis):
				draw_polyline(segment, Color(0.90, 0.81, 0.53, alpha), 0.85, true)
		if world_zoom >= ADMIN1_GLOBAL_LABEL_ZOOM and labels_drawn < 26 and int(record.get("label_rank", 6)) <= 4:
			var label_value: Variant = _lon_lat_from_record(record, "label_lon_lat")
			if label_value != null:
				var rotated: Vector3 = basis * _lon_lat_to_unit(label_value as Vector2)
				if rotated.z >= 0.0:
					_draw_label(_sphere_screen(rotated) + Vector2(5.0, 3.0), _world_admin1_short_name(record), 9, Color(0.85, 0.84, 0.68, 0.78))
					labels_drawn += 1


func _go_back() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and space_level == CITY:
		var count: int = (_world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array).size()
		if count <= 1:
			space_level = WORLD
			selected_world_admin1_id = ""
			queue_redraw()
			return
	super._go_back()
