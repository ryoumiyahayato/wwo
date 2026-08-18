extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_flag_tuning.gd"

const WORLD_HISTORICAL_ENTITY_FOCUS: String = "historical_entity_focus"
const HISTORY_ZOOM_MIN: float = 0.74
const HISTORY_ZOOM_MAX: float = 6.0
const HISTORY_ZOOM_FACTOR: float = 1.22
const HISTORY_LABEL_FADE_START: float = 1.35
const HISTORY_LABEL_FADE_END: float = 2.45

var history_war_layer_visible: bool = true
var selected_historical_territory_iso: String = ""
var hover_historical_territory_iso: String = ""

var _history_document: Dictionary = {}
var _history_entity_by_id: Dictionary = {}
var _history_territories_by_entity: Dictionary = {}
var _history_modern_record_by_iso: Dictionary = {}
var _history_modern_polygons_by_iso: Dictionary = {}
var _history_modern_anchor_by_iso: Dictionary = {}
var _history_explicit_mapped_isos: Dictionary = {}
var _history_provisional_entity_ids: Array[String] = []
var _history_focus_screen_polygons: Dictionary = {}
var _history_focus_screen_bounds: Rect2 = Rect2()
var _history_focus_dirty: bool = true
var _history_conflicts: Array[Dictionary] = []


func _ready() -> void:
	_history_document = _read_document("res://data/world_map/historical_political_entities_1900.json")
	super._ready()
	_rebuild_historical_political_world()
	_load_historical_conflicts()
	_mark_projection_dirty()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if space_level == WORLD and world_mode == WORLD_HISTORICAL_ENTITY_FOCUS:
		if event is InputEventMouseButton:
			var focus_button: InputEventMouseButton = event as InputEventMouseButton
			if focus_button.button_index == MOUSE_BUTTON_LEFT and focus_button.pressed:
				if _handle_button_click(focus_button.position):
					accept_event()
					return
				_select_historical_territory_at(focus_button.position, true)
				accept_event()
				return
		if event is InputEventMouseMotion:
			var focus_motion: InputEventMouseMotion = event as InputEventMouseMotion
			if not _position_hits_ui(focus_motion.position):
				_select_historical_territory_at(focus_motion.position, false)
			return

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
				_set_world_zoom(world_zoom * HISTORY_ZOOM_FACTOR, wheel_event.position)
				accept_event()
				return
			if wheel_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_set_world_zoom(world_zoom / HISTORY_ZOOM_FACTOR, wheel_event.position)
				accept_event()
				return
	super._gui_input(event)


func _set_world_zoom(value: float, anchor: Vector2 = Vector2(INF, INF)) -> void:
	var next_zoom: float = clampf(value, HISTORY_ZOOM_MIN, HISTORY_ZOOM_MAX)
	if is_equal_approx(next_zoom, world_zoom):
		return
	# History navigation obeys the same center invariant as the formal globe:
	# zoom changes radius only and never translates the viewport center.
	_reset_world_view_center()
	world_zoom = next_zoom
	_apply_world_zoom_geometry()
	_reset_world_view_center()
	_mark_projection_dirty()
	_sync_moon_visibility()
	hover_country_id = ""
	hover_event_id = ""
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _country_label_alpha() -> float:
	return smoothstep(HISTORY_LABEL_FADE_START, HISTORY_LABEL_FADE_END, world_zoom)


func _draw_world_overlay() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS:
		_rebuild_history_focus_cache_if_needed()
		_draw_historical_entity_focus()
		return
	super._draw_world_overlay()


func _draw_global_world() -> void:
	_draw_rotating_globe_grid()
	_draw_country_flag_skins()

	var internal_alpha: float = lerpf(0.035, 0.17, clampf(inverse_lerp(1.25, 4.5, world_zoom), 0.0, 1.0))
	for segment: PackedVector2Array in _global_screen_segments:
		draw_polyline(segment, Color(0.61, 0.77, 0.73, internal_alpha), 0.65, true)

	_draw_historical_entity_borders()
	_draw_historical_conflicts()
	_draw_historical_entity_anchors()
	_draw_world_event_markers()
	_draw_zoom_country_labels()
	_draw_zoom_indicator()
	_draw_history_layer_controls()


func _draw_zoom_country_labels() -> void:
	var label_alpha: float = _country_label_alpha()
	if label_alpha <= 0.02:
		return
	var max_rank: int = 2
	if world_zoom >= 2.2:
		max_rank = 4
	if world_zoom >= 3.5:
		max_rank = 9
	var max_labels: int = int(round(lerpf(8.0, 42.0, clampf(world_zoom / HISTORY_ZOOM_MAX, 0.0, 1.0))))
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
			"name": str(country.get("short_name_zh", country.get("name", country_id))),
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
		var width: float = maxf(42.0, float(name.length()) * 10.5)
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
		var provisional: bool = bool((_country_by_id.get(str(candidate.get("id", "")), {}) as Dictionary).get("provisional", false))
		var color: Color = Color(0.84, 0.88, 0.83, label_alpha * (0.54 if provisional else 0.92))
		_draw_label(label_rect.position + Vector2(0.0, 13.0), name, 11, color)
		drawn += 1


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = clampf(inverse_lerp(HISTORY_ZOOM_MIN, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0)
	var base_alpha: float = lerpf(0.36, 0.16, zoom_mix)
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var palette_key: String = str(entity.get("iso_a3", ""))
		var palette: Dictionary = _resolved_flag_palette(palette_key)
		var bounds: Rect2 = _flag_screen_bounds.get(entity_id, Rect2()) as Rect2
		var selected: bool = entity_id == selected_country_id
		var hovered: bool = entity_id == hover_country_id
		var provisional: bool = bool(entity.get("provisional", false))
		var status: String = str(entity.get("status", "sovereign"))
		var alpha: float = base_alpha
		if status == "dependency" or status == "autonomous":
			alpha *= 0.78
		if provisional:
			alpha *= 0.42
		if selected:
			alpha = maxf(alpha, 0.48)
		elif hovered:
			alpha = maxf(alpha, 0.40)
		var polygons: Array = _flag_screen_polygons.get(entity_id, []) as Array
		for polygon_value: Variant in polygons:
			_draw_flag_polygon(polygon_value as PackedVector2Array, bounds, palette, entity_id, alpha)


func _flag_pattern_color(pattern: String, colors: PackedColorArray, u: float, v: float) -> Color:
	if pattern == "diagonal" and colors.size() >= 2:
		var diagonal_value: float = u + (1.0 - v)
		if colors.size() >= 3 and absf(diagonal_value - 1.0) < 0.13:
			return colors[2]
		return colors[0] if diagonal_value < 1.0 else colors[1]
	return super._flag_pattern_color(pattern, colors, u, v)


func _draw_top_info() -> void:
	super._draw_top_info()
	if (
		info_progress <= 0.001
		or space_level != WORLD
		or world_mode != WORLD_COUNTRIES
		or selected_country_id.is_empty()
	):
		return
	var compact: bool = size.x < 940.0
	var height: float = minf(size.y * 0.34, 218.0)
	var rect: Rect2
	if compact:
		rect = Rect2(18.0, 86.0, size.x - 36.0, height)
	else:
		rect = Rect2(318.0, 8.0, maxf(360.0, size.x - 636.0), height)
	var shown_y: float = rect.position.y
	rect.position.y = lerpf(-height - 12.0, shown_y, info_progress)
	_draw_button(Rect2(rect.end.x - 310.0, rect.end.y - 48.0, 124.0, 32.0), "放大定位", "history_zoom_selected", true)
	_draw_button(Rect2(rect.end.x - 176.0, rect.end.y - 48.0, 128.0, 32.0), "进入政治实体", "history_enter_selected", true)


func _activate_button(action: String) -> void:
	if action == "history_zoom_selected":
		_zoom_to_selected_historical_entity()
		return
	if action == "history_enter_selected":
		_focus_selected_country()
		return
	if action.begins_with("history_enter_territory:"):
		_enter_historical_territory(action.get_slice(":", 1))
		return
	if action == "history_back_global":
		_return_to_global_world()
		return
	if action == "toggle_history_war_layer":
		history_war_layer_visible = not history_war_layer_visible
		queue_redraw()
		return
	super._activate_button(action)


func _focus_selected_country() -> void:
	if selected_country_id == FOCUS_COUNTRY_ID:
		super._focus_selected_country()
		return
	if selected_country_id.is_empty() or not _history_entity_by_id.has(selected_country_id):
		return
	space_level = WORLD
	world_mode = WORLD_HISTORICAL_ENTITY_FOCUS
	selected_historical_territory_iso = ""
	hover_historical_territory_iso = ""
	selected_event_id = ""
	selected_region_id = ""
	selected_city_id = ""
	selected_institution_id = ""
	dragging = false
	angular_velocity = 0.0
	set_process(false)
	viewport_container.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_info_open(false)
	_history_focus_dirty = true
	queue_redraw()


func _enter_region() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS:
		var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
		if selected_historical_territory_iso.is_empty() and territories.size() == 1:
			selected_historical_territory_iso = str((territories[0] as Dictionary).get("iso_a3", ""))
		if selected_historical_territory_iso.is_empty():
			return
		space_level = REGION
		_set_info_open(false)
		viewport_container.visible = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()
		return
	super._enter_region()


func _draw_region_map() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS:
		_draw_historical_territory_layer()
		return
	super._draw_region_map()


func _go_back() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS:
		if not active_hud_panel.is_empty():
			active_hud_panel = ""
			queue_redraw()
			return
		if info_open or info_progress > 0.01:
			_set_info_open(false)
			return
		if space_level == REGION:
			space_level = WORLD
			queue_redraw()
			return
		_return_to_global_world()
		return
	super._go_back()


func _breadcrumb_text() -> String:
	if world_mode != WORLD_HISTORICAL_ENTITY_FOCUS:
		return super._breadcrumb_text()
	var entity: Dictionary = _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	var text: String = "世界 / 1900政治实体 / " + str(entity.get("short_name_zh", entity.get("name_zh", "政治实体")))
	if not selected_historical_territory_iso.is_empty():
		text += " / " + _history_territory_name(selected_historical_territory_iso)
	return text


func _rebuild_historical_political_world() -> void:
	_history_modern_record_by_iso.clear()
	_history_modern_polygons_by_iso.clear()
	_history_modern_anchor_by_iso.clear()
	_history_explicit_mapped_isos.clear()
	_history_provisional_entity_ids.clear()

	for modern_value: Variant in _countries:
		var modern: Dictionary = modern_value as Dictionary
		var iso: String = str(modern.get("iso_a3", "")).to_upper()
		var modern_id: String = str(modern.get("id", ""))
		if iso.is_empty():
			continue
		_history_modern_record_by_iso[iso] = modern.duplicate(true)
		_history_modern_polygons_by_iso[iso] = (_country_unit_polygons.get(modern_id, []) as Array).duplicate()
		_history_modern_anchor_by_iso[iso] = _country_anchor_units.get(modern_id, Vector3.ZERO)

	_countries.clear()
	_country_by_id.clear()
	_country_unit_polygons.clear()
	_country_anchor_units.clear()
	_history_entity_by_id.clear()
	_history_territories_by_entity.clear()
	_interaction_adjacency_by_entity.clear()
	_interaction_color_index_by_entity.clear()
	_interaction_coloring_ready = false
	_reset_static_surface_build_progress()

	var entity_values: Array = _history_document.get("entities", []) as Array
	for entity_value: Variant in entity_values:
		if entity_value is Dictionary:
			_build_historical_entity(entity_value as Dictionary, false)

	for iso_value: Variant in _history_modern_record_by_iso.keys():
		var iso: String = str(iso_value)
		if _history_explicit_mapped_isos.has(iso):
			continue
		var modern: Dictionary = _history_modern_record_by_iso.get(iso, {}) as Dictionary
		var provisional: Dictionary = {
			"id": "history_unresolved_" + iso.to_lower(),
			"name_zh": "待校订领土·" + str(modern.get("display_name_zh", modern.get("name", iso))),
			"short_name_zh": str(modern.get("display_name_zh", modern.get("name", iso))),
			"status": "provisional",
			"label_rank": 9,
			"detail_mode": "single",
			"members": [iso],
			"pattern": "solid",
			"colors": [_provisional_color_hex(iso)],
			"provisional": true,
		}
		_build_historical_entity(provisional, true)

	_mark_projection_dirty()
	_history_focus_dirty = true
	if has_method("_build_interaction_adjacency_coloring"):
		call("_build_interaction_adjacency_coloring")


func _build_historical_entity(config: Dictionary, provisional: bool) -> void:
	var entity_id: String = str(config.get("id", ""))
	if entity_id.is_empty():
		return
	var members: Array = config.get("members", []) as Array
	var core_members: Array = config.get("core_members", []) as Array
	var all_polygons: Array = []
	var territories: Array[Dictionary] = []
	var anchor_sum: Vector3 = Vector3.ZERO
	var anchor_count: int = 0
	var preferred_anchor: Vector3 = Vector3.ZERO

	for member_value: Variant in members:
		var iso: String = str(member_value).to_upper()
		if not _history_modern_record_by_iso.has(iso):
			continue
		_history_explicit_mapped_isos[iso] = true
		var modern: Dictionary = _history_modern_record_by_iso.get(iso, {}) as Dictionary
		var polygons: Array = (_history_modern_polygons_by_iso.get(iso, []) as Array).duplicate()
		var anchor: Vector3 = _history_modern_anchor_by_iso.get(iso, Vector3.ZERO) as Vector3
		for polygon_value: Variant in polygons:
			all_polygons.append(polygon_value)
		if not anchor.is_zero_approx():
			anchor_sum += anchor
			anchor_count += 1
		if core_members.has(iso) and preferred_anchor.is_zero_approx():
			preferred_anchor = anchor
		territories.append({
			"iso_a3": iso,
			"name": str(modern.get("display_name_zh", modern.get("name", iso))),
			"polygons": polygons,
			"anchor": anchor,
		})

	if all_polygons.is_empty():
		return
	var entity_anchor: Vector3 = preferred_anchor
	if entity_anchor.is_zero_approx() and anchor_count > 0:
		entity_anchor = (anchor_sum / float(anchor_count)).normalized()
	if entity_anchor.is_zero_approx():
		entity_anchor = Vector3.FORWARD

	var palette_key: String = "HISTORY_" + entity_id.to_upper()
	var colors: PackedColorArray = PackedColorArray()
	for color_value: Variant in (config.get("colors", []) as Array):
		colors.append(Color.from_string(str(color_value), Color(0.45, 0.55, 0.55, 1.0)))
	if colors.is_empty():
		colors.append(Color.from_string(_provisional_color_hex(entity_id), Color(0.45, 0.55, 0.55, 1.0)))
	_flag_palettes[palette_key] = {
		"pattern": str(config.get("pattern", "solid")),
		"colors": colors,
	}

	var record: Dictionary = {
		"id": entity_id,
		"iso_a3": palette_key,
		"name": str(config.get("name_zh", entity_id)),
		"name_zh": str(config.get("name_zh", entity_id)),
		"short_name_zh": str(config.get("short_name_zh", config.get("name_zh", entity_id))),
		"label_rank": int(config.get("label_rank", 9)),
		"status": str(config.get("status", "sovereign")),
		"sovereign_id": str(config.get("sovereign_id", "")),
		"detail_mode": str(config.get("detail_mode", "single")),
		"provisional": provisional or bool(config.get("provisional", false)),
		"member_count": territories.size(),
	}
	_countries.append(record)
	_country_by_id[entity_id] = record
	_country_unit_polygons[entity_id] = all_polygons
	_country_anchor_units[entity_id] = entity_anchor
	_history_entity_by_id[entity_id] = config.duplicate(true)
	_history_territories_by_entity[entity_id] = territories
	if provisional:
		_history_provisional_entity_ids.append(entity_id)


func _load_historical_conflicts() -> void:
	_history_conflicts.clear()
	for conflict_value: Variant in (_history_document.get("conflicts", []) as Array):
		if not conflict_value is Dictionary:
			continue
		var conflict: Dictionary = (conflict_value as Dictionary).duplicate(true)
		var unit_lines: Array[PackedVector3Array] = []
		var center_sum: Vector3 = Vector3.ZERO
		var center_count: int = 0
		for path_value: Variant in (conflict.get("paths", []) as Array):
			var lon_lat_line: PackedVector2Array = _points_from_raw(path_value)
			if lon_lat_line.size() < 2:
				continue
			var unit_line: PackedVector3Array = _to_unit_line(lon_lat_line)
			unit_lines.append(unit_line)
			for point: Vector3 in unit_line:
				center_sum += point
				center_count += 1
		conflict["unit_lines"] = unit_lines
		conflict["anchor"] = (center_sum / float(maxi(1, center_count))).normalized()
		_history_conflicts.append(conflict)


func _draw_historical_entity_borders() -> void:
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var status: String = str(entity.get("status", "sovereign"))
		var provisional: bool = bool(entity.get("provisional", false))
		var selected: bool = entity_id == selected_country_id
		var hovered: bool = entity_id == hover_country_id
		var phase: float = float(abs(entity_id.hash()) % 997) / 997.0
		var pulse: float = 0.5 + 0.5 * sin(_flag_time * (0.43 + phase * 0.16) + phase * TAU)
		var alpha: float = 0.34 + pulse * 0.10
		var width: float = 1.15 + pulse * 0.18
		var color: Color = Color(0.70, 0.80, 0.74, alpha)
		if status == "dependency" or status == "autonomous":
			color = Color(0.67, 0.64, 0.49, alpha * 0.82)
			width = 0.95
		elif status == "contested" or status == "fragmented":
			color = Color(0.91, 0.53, 0.31, alpha + 0.10)
			width = 1.55
		if provisional:
			color.a *= 0.38
		if hovered:
			color = Color(0.82, 0.95, 0.87, 0.90)
			width = 1.9
		if selected:
			color = Color(0.97, 0.81, 0.43, 0.98)
			width = 2.35
		for polygon_value: Variant in (_flag_screen_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			if status == "dependency" or status == "autonomous" or provisional:
				_draw_dashed_polyline(polygon, color, width, 6.0, 4.0)
			else:
				draw_polyline(polygon, color, width, true)


func _draw_historical_conflicts() -> void:
	if not history_war_layer_visible:
		return
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	for conflict: Dictionary in _history_conflicts:
		var severity: int = int(conflict.get("severity", 1))
		var phase: float = float(abs(str(conflict.get("id", "")).hash()) % 997) / 997.0
		var pulse: float = 0.5 + 0.5 * sin(_flag_time * (0.72 + phase * 0.20) + phase * TAU)
		var main_color: Color = Color(0.95, 0.40, 0.23, 0.58 + pulse * 0.25)
		if str(conflict.get("type", "")) == "contested_front":
			main_color = Color(0.94, 0.67, 0.28, 0.55 + pulse * 0.23)
		for unit_line: PackedVector3Array in (conflict.get("unit_lines", []) as Array):
			for segment: PackedVector2Array in _project_unit_line(unit_line, basis):
				draw_polyline(segment, Color(main_color.r, main_color.g, main_color.b, 0.11), 5.0 + float(severity), true)
				_draw_dashed_polyline(segment, main_color, 1.3 + float(severity) * 0.35, 7.0, 4.0)
		if world_zoom >= 1.35:
			var anchor: Vector3 = conflict.get("anchor", Vector3.ZERO) as Vector3
			var rotated: Vector3 = basis * anchor
			if rotated.z >= 0.0:
				_draw_label(_sphere_screen(rotated) + Vector2(8.0, -6.0), str(conflict.get("name_zh", "战争区域")), 10, main_color)


func _draw_historical_entity_anchors() -> void:
	for entity_key_value: Variant in _country_screen_anchors.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var point: Vector2 = _country_screen_anchors.get(entity_id, Vector2.ZERO) as Vector2
		var selected: bool = entity_id == selected_country_id
		var hovered: bool = entity_id == hover_country_id
		var provisional: bool = bool(entity.get("provisional", false))
		var rank: int = int(entity.get("label_rank", 9))
		if not selected and not hovered and rank > 3 and world_zoom < 2.2:
			continue
		var radius: float = 5.8 if selected or hovered else 2.7
		var color: Color = Color(0.94, 0.77, 0.40, 0.96) if selected else Color(0.72, 0.87, 0.81, 0.66)
		if provisional:
			color.a *= 0.35
		if hovered:
			color = Color(0.84, 0.96, 0.90, 0.98)
		draw_circle(point, radius, color)
		if selected or hovered:
			_draw_label(point + Vector2(9.0, -8.0), str(entity.get("short_name_zh", entity.get("name", entity_id))), 12)


func _draw_world_event_markers() -> void:
	for event_key_value: Variant in _event_screen_positions.keys():
		var event_id: String = str(event_key_value)
		var event_point: Vector2 = _event_screen_positions.get(event_id, Vector2.ZERO) as Vector2
		var event: Dictionary = _event_by_id.get(event_id, {}) as Dictionary
		var severity: int = int(event.get("severity", 1))
		var event_color: Color = Color(0.96, 0.59, 0.28, 0.94) if severity >= 2 else Color(0.91, 0.76, 0.40, 0.82)
		var event_radius: float = 5.5 if event_id == hover_event_id or event_id == selected_event_id else 4.0
		draw_circle(event_point, event_radius + 3.0, Color(event_color.r, event_color.g, event_color.b, 0.14), false, 1.2)
		draw_circle(event_point, event_radius, event_color)


func _draw_history_layer_controls() -> void:
	var label: String = "战争边界：开" if history_war_layer_visible else "战争边界：关"
	_draw_button(Rect2(_hemisphere_rect.end.x - 118.0, _hemisphere_rect.position.y + 12.0, 106.0, 26.0), label, "toggle_history_war_layer", true)


func _zoom_to_selected_historical_entity() -> void:
	if selected_country_id.is_empty():
		return
	var anchor: Vector3 = _country_anchor_units.get(selected_country_id, Vector3.ZERO) as Vector3
	if anchor.is_zero_approx():
		return
	var yaw_target: float = -atan2(anchor.x, anchor.z)
	var yaw_basis: Basis = Basis(Vector3.UP, yaw_target)
	var yawed: Vector3 = yaw_basis * anchor
	var tilt_target: float = atan2(yawed.y, maxf(0.0001, yawed.z))
	yaw = yaw_target
	tilt = clampf(tilt_target, -1.15, 1.15)

	var maximum_angle: float = 0.02
	for polygon_value: Variant in (_country_unit_polygons.get(selected_country_id, []) as Array):
		var polygon: PackedVector3Array = polygon_value
		for point: Vector3 in polygon:
			maximum_angle = maxf(maximum_angle, anchor.angle_to(point))
	var fit_zoom: float = 0.72 / maxf(0.025, sin(maximum_angle))
	_set_world_zoom(clampf(fit_zoom, 1.05, HISTORY_ZOOM_MAX))
	_mark_projection_dirty()
	queue_redraw()


func _rebuild_history_focus_cache_if_needed() -> void:
	if not _history_focus_dirty:
		return
	_history_focus_dirty = false
	_history_focus_screen_polygons.clear()
	var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
	var lon_lat_polygons: Array = []
	for territory_value: Variant in territories:
		var territory: Dictionary = territory_value as Dictionary
		for polygon_value: Variant in (territory.get("polygons", []) as Array):
			var polygon: PackedVector3Array = polygon_value
			var lon_lat_polygon: PackedVector2Array = PackedVector2Array()
			for point: Vector3 in polygon:
				lon_lat_polygon.append(_unit_to_lon_lat(point))
			lon_lat_polygons.append(lon_lat_polygon)
	var bounds: Rect2 = _lon_lat_bounds(lon_lat_polygons)
	_history_focus_screen_bounds = bounds
	var rect: Rect2 = _history_focus_rect()
	for territory_value: Variant in territories:
		var territory: Dictionary = territory_value as Dictionary
		var iso: String = str(territory.get("iso_a3", ""))
		var screen_polygons: Array[PackedVector2Array] = []
		for polygon_value: Variant in (territory.get("polygons", []) as Array):
			var polygon: PackedVector3Array = polygon_value
			var screen: PackedVector2Array = PackedVector2Array()
			for point: Vector3 in polygon:
				screen.append(_lon_lat_to_history_rect(_unit_to_lon_lat(point), bounds, rect))
			if screen.size() > 2:
				screen_polygons.append(screen)
		_history_focus_screen_polygons[iso] = screen_polygons


func _draw_historical_entity_focus() -> void:
	var entity: Dictionary = _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	var rect: Rect2 = _history_focus_rect()
	_panel(rect.grow(14.0), Color(0.018, 0.038, 0.045, 0.94), Color(0.67, 0.62, 0.42, 0.32))
	var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
	for index: int in range(territories.size()):
		var territory: Dictionary = territories[index] as Dictionary
		var iso: String = str(territory.get("iso_a3", ""))
		var selected: bool = iso == selected_historical_territory_iso
		var hovered: bool = iso == hover_historical_territory_iso
		var fill: Color = _history_territory_color(index, 0.36)
		var border: Color = Color(0.70, 0.79, 0.73, 0.55)
		var width: float = 1.0
		if selected:
			fill = Color(0.82, 0.60, 0.24, 0.54)
			border = Color(0.98, 0.82, 0.43, 0.98)
			width = 2.1
		elif hovered:
			fill = Color(0.34, 0.64, 0.59, 0.48)
			border = Color(0.82, 0.95, 0.88, 0.92)
			width = 1.7
		for polygon_value: Variant in (_history_focus_screen_polygons.get(iso, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, width, true)
		var anchor: Vector3 = territory.get("anchor", Vector3.ZERO) as Vector3
		if not anchor.is_zero_approx():
			var label_point: Vector2 = _lon_lat_to_history_rect(_unit_to_lon_lat(anchor), _history_focus_screen_bounds, rect)
			_draw_label(label_point + Vector2(5.0, 3.0), str(territory.get("name", iso)), 10)

	_draw_label(rect.position + Vector2(12.0, 24.0), "1900政治实体 · " + str(entity.get("name_zh", selected_country_id)), 16)
	_draw_label(rect.position + Vector2(12.0, 47.0), "辖区数量：%d · 现代多边形聚合的历史近似" % territories.size(), 11, Color(0.70, 0.78, 0.75, 1.0))
	_draw_button(Rect2(rect.position.x + 12.0, rect.end.y - 38.0, 98.0, 28.0), "返回全球", "history_back_global", true)
	_draw_button(Rect2(rect.end.x - 136.0, rect.end.y - 38.0, 124.0, 28.0), "进入辖区", "enter_region", not selected_historical_territory_iso.is_empty() or territories.size() == 1)


func _select_historical_territory_at(position: Vector2, click: bool) -> void:
	_rebuild_history_focus_cache_if_needed()
	var found: String = ""
	for iso_value: Variant in _history_focus_screen_polygons.keys():
		var iso: String = str(iso_value)
		for polygon_value: Variant in (_history_focus_screen_polygons.get(iso, []) as Array):
			if Geometry2D.is_point_in_polygon(position, polygon_value as PackedVector2Array):
				found = iso
				break
		if not found.is_empty():
			break
	if hover_historical_territory_iso != found:
		hover_historical_territory_iso = found
		queue_redraw()
	if click and not found.is_empty():
		selected_historical_territory_iso = found
		queue_redraw()


func _enter_historical_territory(iso: String) -> void:
	selected_historical_territory_iso = iso
	_enter_region()


func _draw_historical_territory_layer() -> void:
	var entity: Dictionary = _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	var rect: Rect2 = _main_content_rect(110.0, 166.0, 104.0)
	_panel(rect, Color(0.020, 0.040, 0.046, 0.95), Color(0.68, 0.62, 0.42, 0.34))
	var territory: Dictionary = _history_territory_record(selected_historical_territory_iso)
	_draw_label(rect.position + Vector2(24.0, 34.0), str(entity.get("short_name_zh", "政治实体")) + " · " + str(territory.get("name", selected_historical_territory_iso)), 17)
	_draw_label(rect.position + Vector2(24.0, 60.0), "该层显示完整辖区轮廓；尚未配置更细历史行政数据时不伪造区县。", 11, Color(0.70, 0.78, 0.75, 1.0))
	var polygons: Array = territory.get("polygons", []) as Array
	var lon_lat_polygons: Array = []
	for polygon_value: Variant in polygons:
		var polygon: PackedVector3Array = polygon_value
		var lon_lat_polygon: PackedVector2Array = PackedVector2Array()
		for point: Vector3 in polygon:
			lon_lat_polygon.append(_unit_to_lon_lat(point))
		lon_lat_polygons.append(lon_lat_polygon)
	var bounds: Rect2 = _lon_lat_bounds(lon_lat_polygons)
	var map_rect: Rect2 = rect.grow(-76.0)
	map_rect.position.y += 42.0
	map_rect.size.y -= 42.0
	for polygon_value: Variant in lon_lat_polygons:
		var polygon: PackedVector2Array = polygon_value
		var screen: PackedVector2Array = PackedVector2Array()
		for lon_lat: Vector2 in polygon:
			screen.append(_lon_lat_to_history_rect(lon_lat, bounds, map_rect))
		if screen.size() > 2:
			draw_colored_polygon(screen, Color(0.25, 0.42, 0.41, 0.38))
			draw_polyline(screen, Color(0.88, 0.77, 0.46, 0.82), 1.5, true)
	_draw_label(rect.position + Vector2(24.0, rect.size.y - 22.0), "下一级：待历史GIS或国家行政数据补充", 11, Color(0.91, 0.66, 0.39, 1.0))


func _history_focus_rect() -> Rect2:
	return Rect2(viewport_container.position + Vector2(28.0, 72.0), viewport_container.size - Vector2(56.0, 118.0))


func _history_territory_record(iso: String) -> Dictionary:
	for territory_value: Variant in (_history_territories_by_entity.get(selected_country_id, []) as Array):
		var territory: Dictionary = territory_value as Dictionary
		if str(territory.get("iso_a3", "")) == iso:
			return territory
	return {}


func _history_territory_name(iso: String) -> String:
	return str(_history_territory_record(iso).get("name", iso))


func _unit_to_lon_lat(point: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(point.x, point.z)), rad_to_deg(asin(clampf(point.y, -1.0, 1.0))))


func _lon_lat_to_history_rect(lon_lat: Vector2, bounds: Rect2, rect: Rect2) -> Vector2:
	var center_lon: float = bounds.position.x + bounds.size.x * 0.5
	var center_lat: float = bounds.position.y + bounds.size.y * 0.5
	var longitude_factor: float = maxf(0.12, cos(deg_to_rad(center_lat)))
	var geographic_width: float = maxf(0.001, bounds.size.x * longitude_factor)
	var geographic_height: float = maxf(0.001, bounds.size.y)
	var scale: float = minf(rect.size.x / geographic_width, rect.size.y / geographic_height)
	return rect.get_center() + Vector2((lon_lat.x - center_lon) * longitude_factor * scale, -(lon_lat.y - center_lat) * scale)


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	if points.size() < 2:
		return
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[index + 1]
		var length: float = start.distance_to(finish)
		if length <= 0.001:
			continue
		var direction: Vector2 = (finish - start) / length
		var cursor: float = 0.0
		while cursor < length:
			var segment_end: float = minf(length, cursor + dash)
			draw_line(start + direction * cursor, start + direction * segment_end, color, width, true)
			cursor += dash + gap


func _history_territory_color(index: int, alpha: float) -> Color:
	var colors: Array[Color] = [
		Color(0.22, 0.37, 0.39, alpha),
		Color(0.30, 0.39, 0.34, alpha),
		Color(0.31, 0.34, 0.43, alpha),
		Color(0.40, 0.35, 0.28, alpha),
		Color(0.26, 0.42, 0.37, alpha),
		Color(0.38, 0.30, 0.40, alpha),
	]
	return colors[index % colors.size()]


func _provisional_color_hex(seed: String) -> String:
	var colors: Array[String] = ["#546C70", "#6A6658", "#536477", "#5D6D5D", "#6F5C64", "#66715A"]
	return colors[abs(seed.hash()) % colors.size()]
