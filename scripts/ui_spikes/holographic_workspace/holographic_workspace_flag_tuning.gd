extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_flags.gd"


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = inverse_lerp(WORLD_ZOOM_MIN, WORLD_ZOOM_MAX, world_zoom)
	var base_alpha: float = lerpf(0.33, 0.16, zoom_mix)
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
			alpha = maxf(alpha, 0.44)
		elif hovered:
			alpha = maxf(alpha, 0.37)
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
		var wave_mix: float = 0.035 + (wave + 1.0) * 0.022
		raw_color = raw_color.lerp(alternate, wave_mix)
		var subdued: Color = raw_color.lerp(Color(0.23, 0.32, 0.34, 1.0), 0.28)
		var brightness: float = 0.98 + wave * 0.065 + secondary_wave * 0.026
		vertex_colors.append(Color(
			clampf(subdued.r * brightness, 0.0, 1.0),
			clampf(subdued.g * brightness, 0.0, 1.0),
			clampf(subdued.b * brightness, 0.0, 1.0),
			alpha * (0.96 + wave * 0.04)
		))
	draw_polygon(polygon, vertex_colors)
