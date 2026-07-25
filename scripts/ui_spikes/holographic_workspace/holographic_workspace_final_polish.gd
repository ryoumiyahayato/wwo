extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_crisp_flags_fixed.gd"


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = clampf(inverse_lerp(HISTORY_ZOOM_MIN, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0)
	var base_alpha: float = lerpf(0.40, 0.18, zoom_mix)
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var palette: Dictionary = _resolved_flag_palette(str(entity.get("iso_a3", "")))
		var status: String = str(entity.get("status", "sovereign"))
		var provisional: bool = bool(entity.get("provisional", false))
		var alpha: float = base_alpha
		if status == "dependency" or status == "autonomous":
			alpha *= 0.78
		if provisional:
			alpha *= 0.27
		if entity_id == selected_country_id:
			alpha = maxf(alpha, 0.56)
		elif entity_id == hover_country_id:
			alpha = maxf(alpha, 0.48)
		for polygon_value: Variant in (_flag_screen_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			_draw_flag_polygon(polygon, _screen_polygon_bounds(polygon), palette, entity_id, alpha)


func _draw_world_admin1_layer() -> void:
	var rect: Rect2 = _main_content_rect(110.0, 166.0, 104.0)
	_panel(rect, Color(0.018, 0.039, 0.046, 0.96), Color(0.67, 0.62, 0.42, 0.34))
	var records: Array = _world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array
	_draw_label(rect.position + Vector2(24.0, 34.0), _history_territory_name(selected_historical_territory_iso) + " · 一级行政区", 17)
	_draw_label(
		rect.position + Vector2(24.0, 59.0),
		"现代行政区几何作为1900历史数据缺失时的近似回退；当前记录 %d。" % records.size(),
		11,
		Color(0.70, 0.78, 0.75, 1.0)
	)
	_rebuild_world_admin1_screen_cache(rect)

	for index: int in range(records.size()):
		var record: Dictionary = records[index] as Dictionary
		var record_id: String = str(record.get("id", ""))
		var selected: bool = record_id == selected_world_admin1_id
		var hovered: bool = record_id == hover_world_admin1_id
		var fill: Color = _history_territory_color(index, 0.30)
		var border: Color = Color(0.66, 0.76, 0.71, 0.48)
		var width: float = 0.85
		if selected:
			fill = Color(0.82, 0.60, 0.24, 0.56)
			border = Color(0.98, 0.82, 0.43, 0.98)
			width = 2.0
		elif hovered:
			fill = Color(0.34, 0.64, 0.59, 0.49)
			border = Color(0.82, 0.95, 0.88, 0.92)
			width = 1.6
		for polygon_value: Variant in (_world_admin1_screen_polygons.get(record_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, width, true)

	var candidates: Array[Dictionary] = []
	for record_value: Variant in records:
		var record: Dictionary = record_value as Dictionary
		var record_id: String = str(record.get("id", ""))
		var label_lon_lat: Variant = record.get("label_lon_lat", [])
		if not label_lon_lat is Array or (label_lon_lat as Array).size() < 2:
			continue
		var rank: int = int(record.get("label_rank", 6))
		var selected: bool = record_id == selected_world_admin1_id
		var hovered: bool = record_id == hover_world_admin1_id
		if rank > 5 and not selected and not hovered:
			continue
		var point: Vector2 = _lon_lat_to_history_rect(
			Vector2(float(label_lon_lat[0]), float(label_lon_lat[1])),
			_world_admin1_bounds,
			_world_admin1_map_rect(rect)
		)
		candidates.append({
			"record": record,
			"point": point,
			"rank": -2 if selected else (-1 if hovered else rank),
		})
	candidates.sort_custom(Callable(self, "_admin1_label_before"))

	var occupied: Array[Rect2] = []
	var label_limit: int = 24 if records.size() <= 40 else 16
	var labeled: int = 0
	for candidate: Dictionary in candidates:
		if labeled >= label_limit:
			break
		var record: Dictionary = candidate.get("record", {}) as Dictionary
		var point: Vector2 = candidate.get("point", Vector2.ZERO) as Vector2
		var name: String = _world_admin1_short_name(record)
		var label_rect: Rect2 = Rect2(
			point + Vector2(4.0, -11.0),
			Vector2(maxf(34.0, float(name.length()) * 8.2), 15.0)
		)
		if not _admin1_label_rect_available(label_rect, occupied):
			continue
		occupied.append(label_rect)
		var record_id: String = str(record.get("id", ""))
		var color: Color = Color(0.77, 0.83, 0.78, 0.88)
		if record_id == selected_world_admin1_id:
			color = Color(0.98, 0.82, 0.43, 1.0)
		elif record_id == hover_world_admin1_id:
			color = Color(0.84, 0.96, 0.90, 0.96)
		_draw_label(label_rect.position + Vector2(0.0, 11.0), name, 9, color)
		labeled += 1

	_draw_button(
		Rect2(rect.end.x - 156.0, rect.end.y - 40.0, 132.0, 28.0),
		"进入下一级",
		"history_enter_admin1",
		not selected_world_admin1_id.is_empty()
	)
	if not selected_world_admin1_id.is_empty():
		var selected_record: Dictionary = _world_admin1_by_id.get(selected_world_admin1_id, {}) as Dictionary
		_draw_label(
			rect.position + Vector2(24.0, rect.size.y - 22.0),
			"当前一级区：" + _world_admin1_name(selected_record),
			11,
			Color(0.94, 0.80, 0.50, 1.0)
		)


func _draw_selected_admin1_on_globe() -> void:
	if world_zoom < ADMIN1_GLOBAL_ZOOM_START or selected_country_id.is_empty():
		return
	var iso: String = _selected_global_territory_iso()
	if iso.is_empty():
		return
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	var alpha: float = lerpf(
		0.16,
		0.48,
		clampf(inverse_lerp(ADMIN1_GLOBAL_ZOOM_START, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0)
	)
	var label_candidates: Array[Dictionary] = []
	for entry_value: Variant in _admin1_unit_lines_for_iso(iso):
		var entry: Dictionary = entry_value as Dictionary
		var record: Dictionary = entry.get("record", {}) as Dictionary
		for unit_line_value: Variant in (entry.get("unit_lines", []) as Array):
			var unit_line: PackedVector3Array = unit_line_value
			for segment: PackedVector2Array in _project_unit_line(unit_line, basis):
				draw_polyline(segment, Color(0.90, 0.81, 0.53, alpha), 0.85, true)
		if world_zoom < ADMIN1_GLOBAL_LABEL_ZOOM or int(record.get("label_rank", 6)) > 4:
			continue
		var label_value: Variant = _lon_lat_from_record(record, "label_lon_lat")
		if label_value == null:
			continue
		var rotated: Vector3 = basis * _lon_lat_to_unit(label_value as Vector2)
		if rotated.z < 0.0:
			continue
		label_candidates.append({
			"record": record,
			"point": _sphere_screen(rotated),
			"rank": int(record.get("label_rank", 6)),
		})
	label_candidates.sort_custom(Callable(self, "_admin1_label_before"))
	var occupied: Array[Rect2] = []
	var labels_drawn: int = 0
	for candidate: Dictionary in label_candidates:
		if labels_drawn >= 18:
			break
		var record: Dictionary = candidate.get("record", {}) as Dictionary
		var point: Vector2 = candidate.get("point", Vector2.ZERO) as Vector2
		var name: String = _world_admin1_short_name(record)
		var label_rect: Rect2 = Rect2(point + Vector2(5.0, -10.0), Vector2(maxf(32.0, float(name.length()) * 7.8), 14.0))
		if not _admin1_label_rect_available(label_rect, occupied):
			continue
		occupied.append(label_rect)
		_draw_label(label_rect.position + Vector2(0.0, 10.0), name, 9, Color(0.85, 0.84, 0.68, 0.78))
		labels_drawn += 1


func _admin1_label_before(a: Dictionary, b: Dictionary) -> bool:
	var a_rank: int = int(a.get("rank", 6))
	var b_rank: int = int(b.get("rank", 6))
	if a_rank == b_rank:
		var a_point: Vector2 = a.get("point", Vector2.ZERO) as Vector2
		var b_point: Vector2 = b.get("point", Vector2.ZERO) as Vector2
		return a_point.distance_squared_to(_hemisphere_center) < b_point.distance_squared_to(_hemisphere_center)
	return a_rank < b_rank


func _admin1_label_rect_available(label_rect: Rect2, occupied: Array[Rect2]) -> bool:
	for existing: Rect2 in occupied:
		if existing.intersects(label_rect.grow(3.0)):
			return false
	return true
