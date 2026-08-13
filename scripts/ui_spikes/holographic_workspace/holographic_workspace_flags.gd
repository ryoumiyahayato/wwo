extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_final.gd"

const WORLD_ZOOM_MIN: float = 0.74
const WORLD_ZOOM_MAX: float = 1.24
const WORLD_ZOOM_STEP: float = 0.10
const COUNTRY_LABEL_FADE_START: float = 1.02
const COUNTRY_LABEL_FADE_END: float = 1.18
const FLAG_TIMER_STEP: float = 0.12

var world_zoom: float = 0.86
var _base_hemisphere_radius: float = 220.0
var _flag_time: float = 0.0
var _flag_palettes: Dictionary = {}
var _flag_screen_polygons: Dictionary = {}
var _flag_screen_bounds: Dictionary = {}
var _performance_flag_timer_redraw_count: int = 0
var _performance_flag_cache_rebuild_count: int = 0
var _performance_flag_cache_rebuild_usec: int = 0

@onready var _world_camera: Camera3D = %Camera3D


func _ready() -> void:
	_load_flag_palettes()
	super._ready()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()
	queue_redraw()


func _on_flag_timer_timeout() -> void:
	_flag_time += FLAG_TIMER_STEP
	if space_level == WORLD and world_mode == WORLD_COUNTRIES and viewport_container.visible:
		_performance_flag_timer_redraw_count += 1
		queue_redraw()


func _apply_layout() -> void:
	super._apply_layout()
	_base_hemisphere_radius = _hemisphere_radius
	_apply_world_zoom_geometry()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var wheel_event: InputEventMouseButton = event as InputEventMouseButton
		if (
			wheel_event.pressed
			and space_level == WORLD
			and world_mode == WORLD_COUNTRIES
			and not _position_hits_ui(wheel_event.position)
			and Rect2(viewport_container.position, viewport_container.size).has_point(wheel_event.position)
		):
			if wheel_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_set_world_zoom(world_zoom + WORLD_ZOOM_STEP)
				accept_event()
				return
			if wheel_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_set_world_zoom(world_zoom - WORLD_ZOOM_STEP)
				accept_event()
				return
	super._gui_input(event)


func _ensure_projection_cache() -> void:
	var rebuild_flags: bool = _projection_dirty or _flag_screen_polygons.is_empty()
	super._ensure_projection_cache()
	if rebuild_flags:
		_rebuild_country_flag_cache()


func _draw_global_world() -> void:
	_draw_country_flag_skins()
	super._draw_global_world()
	_draw_zoom_country_labels()
	_draw_zoom_indicator()


func _focus_selected_country() -> void:
	super._focus_selected_country()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _show_event_from_hud(event_id: String) -> void:
	super._show_event_from_hud(event_id)
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _return_to_global_world() -> void:
	super._return_to_global_world()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _enter_region() -> void:
	super._enter_region()
	_apply_world_zoom_geometry()


func _enter_city(city_id: String) -> void:
	super._enter_city(city_id)
	_apply_world_zoom_geometry()


func _go_back() -> void:
	super._go_back()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _sync_moon_visibility() -> void:
	if _moon_node == null:
		return
	_moon_node.visible = (
		space_level == WORLD
		and world_mode == WORLD_COUNTRIES
		and viewport_container.visible
		and world_zoom <= 1.10
	)


func _set_world_zoom(value: float) -> void:
	var next_zoom: float = clampf(value, WORLD_ZOOM_MIN, WORLD_ZOOM_MAX)
	if is_equal_approx(next_zoom, world_zoom):
		return
	world_zoom = next_zoom
	_apply_world_zoom_geometry()
	_mark_projection_dirty()
	_sync_moon_visibility()
	hover_country_id = ""
	hover_event_id = ""
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _apply_world_zoom_geometry() -> void:
	if _base_hemisphere_radius <= 0.0:
		return
	var effective_zoom: float = _effective_world_zoom()
	_hemisphere_radius = _base_hemisphere_radius * effective_zoom
	_hemisphere_rect = Rect2(
		_hemisphere_center - Vector2(_hemisphere_radius, _hemisphere_radius),
		Vector2(_hemisphere_radius * 2.0, _hemisphere_radius * 2.0)
	)
	if _world_camera != null:
		_world_camera.size = CAMERA_ORTHO_SIZE / effective_zoom
		if viewport != null and viewport_container.visible:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _effective_world_zoom() -> float:
	if space_level == WORLD and world_mode == WORLD_COUNTRIES:
		return world_zoom
	return 1.0


func _load_flag_palettes() -> void:
	var document: Dictionary = _read_document("res://data/world_map/country_flag_palettes.json")
	var raw_palettes: Dictionary = document.get("palettes", {}) as Dictionary
	for iso_value: Variant in raw_palettes.keys():
		var iso: String = str(iso_value).to_upper()
		var raw_record: Dictionary = raw_palettes.get(iso, {}) as Dictionary
		var packed_colors: PackedColorArray = PackedColorArray()
		var color_values: Array = raw_record.get("colors", []) as Array
		for color_value: Variant in color_values:
			packed_colors.append(Color.from_string(str(color_value), Color(0.54, 0.60, 0.58, 1.0)))
		if packed_colors.is_empty():
			continue
		_flag_palettes[iso] = {
			"pattern": str(raw_record.get("pattern", "solid")),
			"colors": packed_colors,
		}


func _rebuild_country_flag_cache() -> void:
	var performance_started_usec := Time.get_ticks_usec()
	_performance_flag_cache_rebuild_count += 1
	_flag_screen_polygons.clear()
	_flag_screen_bounds.clear()
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	for country_value: Variant in _countries:
		var country: Dictionary = country_value as Dictionary
		var country_id: String = str(country.get("id", ""))
		var source_polygons: Array = _country_unit_polygons.get(country_id, []) as Array
		var visible_polygons: Array[PackedVector2Array] = []
		var has_bounds: bool = false
		var minimum: Vector2 = Vector2(100000.0, 100000.0)
		var maximum: Vector2 = Vector2(-100000.0, -100000.0)
		for source_value: Variant in source_polygons:
			var source: PackedVector3Array = source_value
			var visible: PackedVector2Array = _clip_visible_country_polygon(source, basis)
			if visible.size() < 3:
				continue
			if Geometry2D.triangulate_polygon(visible).size() < 3:
				continue
			visible_polygons.append(visible)
			for point: Vector2 in visible:
				has_bounds = true
				minimum.x = minf(minimum.x, point.x)
				minimum.y = minf(minimum.y, point.y)
				maximum.x = maxf(maximum.x, point.x)
				maximum.y = maxf(maximum.y, point.y)
		if visible_polygons.is_empty():
			continue
		_flag_screen_polygons[country_id] = visible_polygons
		if has_bounds:
			_flag_screen_bounds[country_id] = Rect2(minimum, maximum - minimum)
	_performance_flag_cache_rebuild_usec += Time.get_ticks_usec() - performance_started_usec


func _clip_visible_country_polygon(source: PackedVector3Array, basis: Basis) -> PackedVector2Array:
	var output: PackedVector2Array = PackedVector2Array()
	if source.size() < 3:
		return output
	var clipped: Array[Vector3] = []
	var previous: Vector3 = basis * source[source.size() - 1]
	var previous_inside: bool = previous.z >= 0.0
	for index: int in range(source.size()):
		var current: Vector3 = basis * source[index]
		var current_inside: bool = current.z >= 0.0
		if current_inside != previous_inside:
			var denominator: float = previous.z - current.z
			var ratio: float = 0.5
			if absf(denominator) > 0.000001:
				ratio = clampf(previous.z / denominator, 0.0, 1.0)
			var horizon: Vector3 = previous.lerp(current, ratio)
			horizon.z = 0.0
			clipped.append(horizon)
		if current_inside:
			clipped.append(current)
		previous = current
		previous_inside = current_inside
	for point: Vector3 in clipped:
		var screen_point: Vector2 = _sphere_screen(point)
		if output.is_empty() or output[output.size() - 1].distance_to(screen_point) > 0.35:
			output.append(screen_point)
	if output.size() > 3 and output[0].distance_to(output[output.size() - 1]) < 0.35:
		output.resize(output.size() - 1)
	return output


func debug_performance_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.debug_performance_snapshot()
	snapshot["flag_timer_redraw_count"] = _performance_flag_timer_redraw_count
	snapshot["flag_cache_rebuild_count"] = _performance_flag_cache_rebuild_count
	snapshot["flag_cache_rebuild_usec"] = _performance_flag_cache_rebuild_usec
	snapshot["visible_flag_entity_count"] = _flag_screen_polygons.size()
	return snapshot


func debug_reset_performance_metrics() -> void:
	super.debug_reset_performance_metrics()
	_performance_flag_timer_redraw_count = 0
	_performance_flag_cache_rebuild_count = 0
	_performance_flag_cache_rebuild_usec = 0


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = inverse_lerp(WORLD_ZOOM_MIN, WORLD_ZOOM_MAX, world_zoom)
	var base_alpha: float = lerpf(0.205, 0.105, zoom_mix)
	for country_key_value: Variant in _flag_screen_polygons.keys():
		var country_id: String = str(country_key_value)
		var country: Dictionary = _country_by_id.get(country_id, {}) as Dictionary
		var iso: String = str(country.get("iso_a3", "")).to_upper()
		var palette: Dictionary = _resolved_flag_palette(iso)
		var bounds: Rect2 = _flag_screen_bounds.get(country_id, Rect2()) as Rect2
		var selected: bool = country_id == selected_country_id
		var hovered: bool = country_id == hover_country_id
		var alpha: float = base_alpha
		if selected:
			alpha = maxf(alpha, 0.31)
		elif hovered:
			alpha = maxf(alpha, 0.255)
		var polygons: Array = _flag_screen_polygons.get(country_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			_draw_flag_polygon(polygon, bounds, palette, country_id, alpha)


func _draw_flag_polygon(
	polygon: PackedVector2Array,
	bounds: Rect2,
	palette: Dictionary,
	country_id: String,
	alpha: float
) -> void:
	if polygon.size() < 3:
		return
	var colors: PackedColorArray = palette.get("colors", PackedColorArray()) as PackedColorArray
	if colors.is_empty():
		return
	var pattern: String = str(palette.get("pattern", "solid"))
	var vertex_colors: PackedColorArray = PackedColorArray()
	var safe_width: float = maxf(bounds.size.x, 1.0)
	var safe_height: float = maxf(bounds.size.y, 1.0)
	var phase: float = float(abs(country_id.hash()) % 997) / 997.0
	for point: Vector2 in polygon:
		var u: float = clampf((point.x - bounds.position.x) / safe_width, 0.0, 1.0)
		var v: float = clampf((point.y - bounds.position.y) / safe_height, 0.0, 1.0)
		var raw_color: Color = _flag_pattern_color(pattern, colors, u, v)
		var alternate: Color = colors[(int(floor((u + v) * float(colors.size()))) + 1) % colors.size()]
		var wave: float = sin(_flag_time * (0.60 + phase * 0.32) + u * 6.2 + v * 2.8 + phase * TAU)
		var secondary_wave: float = sin(_flag_time * 0.37 + v * 7.4 - phase * 4.0)
		var wave_mix: float = 0.025 + (wave + 1.0) * 0.016
		raw_color = raw_color.lerp(alternate, wave_mix)
		var subdued: Color = raw_color.lerp(Color(0.24, 0.34, 0.36, 1.0), 0.46)
		var brightness: float = 0.92 + wave * 0.055 + secondary_wave * 0.022
		vertex_colors.append(Color(
			clampf(subdued.r * brightness, 0.0, 1.0),
			clampf(subdued.g * brightness, 0.0, 1.0),
			clampf(subdued.b * brightness, 0.0, 1.0),
			alpha * (0.94 + wave * 0.045)
		))
	draw_polygon(polygon, vertex_colors)


func _flag_pattern_color(
	pattern: String,
	colors: PackedColorArray,
	u: float,
	v: float
) -> Color:
	var count: int = colors.size()
	if count == 1:
		return colors[0]
	if pattern == "vertical":
		return colors[clampi(int(floor(u * float(count))), 0, count - 1)]
	if pattern == "horizontal":
		return colors[clampi(int(floor(v * float(count))), 0, count - 1)]
	if pattern == "cross":
		var cross_color: Color = colors[1]
		if absf(u - 0.5) < 0.115 or absf(v - 0.5) < 0.115:
			if count > 2 and (absf(u - 0.5) < 0.042 or absf(v - 0.5) < 0.042):
				return colors[2]
			return cross_color
		return colors[0]
	if pattern == "canton":
		if count > 2 and u < 0.40 and v < 0.42:
			return colors[2]
		return colors[0] if v < 0.5 else colors[1]
	if pattern == "disc":
		var distance: float = Vector2(u, v).distance_to(Vector2(0.5, 0.5))
		if count > 2 and distance < 0.10:
			return colors[2]
		if distance < 0.24:
			return colors[1]
		return colors[0]
	if pattern == "quartered":
		var quadrant: int = (1 if u >= 0.5 else 0) + (2 if v >= 0.5 else 0)
		return colors[quadrant % count]
	return colors[0]


func _resolved_flag_palette(iso: String) -> Dictionary:
	if _flag_palettes.has(iso):
		return _flag_palettes.get(iso, {}) as Dictionary
	var fallback_sets: Array[PackedColorArray] = [
		PackedColorArray([Color("#315A82"), Color("#ECE9DF"), Color("#9A3038")]),
		PackedColorArray([Color("#3C6C57"), Color("#ECE9DF"), Color("#9A3038")]),
		PackedColorArray([Color("#C9A443"), Color("#3C6C57"), Color("#9A3038")]),
		PackedColorArray([Color("#315A82"), Color("#C9A443"), Color("#9A3038")]),
		PackedColorArray([Color("#9A3038"), Color("#ECE9DF")]),
		PackedColorArray([Color("#315A82"), Color("#ECE9DF")]),
	]
	var patterns: Array[String] = ["horizontal", "vertical", "horizontal", "vertical", "solid", "cross"]
	var index: int = abs(iso.hash()) % fallback_sets.size()
	return {"pattern": patterns[index], "colors": fallback_sets[index]}


func _draw_zoom_country_labels() -> void:
	var label_alpha: float = _country_label_alpha()
	if label_alpha <= 0.02:
		return
	var max_rank: int = 2 if world_zoom < 1.15 else 4
	var max_labels: int = int(round(lerpf(7.0, 20.0, label_alpha)))
	var candidates: Array[Dictionary] = []
	for country_key_value: Variant in _country_screen_anchors.keys():
		var country_id: String = str(country_key_value)
		if country_id == selected_country_id or country_id == hover_country_id:
			continue
		var country: Dictionary = _country_by_id.get(country_id, {}) as Dictionary
		var rank: int = int(country.get("label_rank", 9))
		if rank > max_rank:
			continue
		candidates.append({
			"id": country_id,
			"name": str(country.get("name", country_id)),
			"rank": rank,
			"point": _country_screen_anchors.get(country_id, Vector2.ZERO),
		})
	candidates.sort_custom(Callable(self, "_country_label_before"))
	var occupied: Array[Rect2] = []
	var viewport_rect: Rect2 = Rect2(viewport_container.position, viewport_container.size)
	var drawn: int = 0
	for candidate: Dictionary in candidates:
		if drawn >= max_labels:
			break
		var point: Vector2 = candidate.get("point", Vector2.ZERO) as Vector2
		var name: String = str(candidate.get("name", ""))
		var width: float = maxf(38.0, float(name.length()) * 10.5)
		var label_rect: Rect2 = Rect2(point + Vector2(7.0, -14.0), Vector2(width, 18.0))
		if not viewport_rect.encloses(label_rect):
			continue
		var overlaps: bool = false
		for existing: Rect2 in occupied:
			if existing.intersects(label_rect.grow(3.0)):
				overlaps = true
				break
		if overlaps:
			continue
		occupied.append(label_rect)
		_draw_label(label_rect.position + Vector2(0.0, 13.0), name, 11, Color(0.86, 0.89, 0.84, label_alpha * 0.92))
		drawn += 1


func _country_label_before(a: Dictionary, b: Dictionary) -> bool:
	var a_rank: int = int(a.get("rank", 9))
	var b_rank: int = int(b.get("rank", 9))
	if a_rank == b_rank:
		var a_point: Vector2 = a.get("point", Vector2.ZERO) as Vector2
		var b_point: Vector2 = b.get("point", Vector2.ZERO) as Vector2
		return a_point.distance_squared_to(_hemisphere_center) < b_point.distance_squared_to(_hemisphere_center)
	return a_rank < b_rank


func _country_label_alpha() -> float:
	return smoothstep(COUNTRY_LABEL_FADE_START, COUNTRY_LABEL_FADE_END, world_zoom)


func _draw_zoom_indicator() -> void:
	var text: String = "滚轮缩放 %d%%" % int(round(world_zoom * 100.0))
	var mode_text: String = "旗色总览" if _country_label_alpha() < 0.25 else "国家名称"
	_draw_label(
		Vector2(_hemisphere_rect.position.x + 14.0, _hemisphere_rect.end.y - 14.0),
		text + " · " + mode_text,
		10,
		Color(0.66, 0.75, 0.72, 0.68)
	)
