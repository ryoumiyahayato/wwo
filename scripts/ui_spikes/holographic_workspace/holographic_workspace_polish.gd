extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_visual.gd"

const REGION_CITY_SUPPLEMENTS: Array = [
	{"id":"amiens_spike","name":"亚眠","parent_region_id":"northern_industrial_belt","lon_lat":[2.2950,49.8941]},
	{"id":"douai_spike","name":"杜埃","parent_region_id":"northern_industrial_belt","lon_lat":[3.0800,50.3679]},
	{"id":"reims_spike","name":"兰斯","parent_region_id":"paris_basin","lon_lat":[4.0317,49.2583]},
	{"id":"nancy_spike","name":"南锡","parent_region_id":"paris_basin","lon_lat":[6.1844,48.6921]},
	{"id":"troyes_spike","name":"特鲁瓦","parent_region_id":"paris_basin","lon_lat":[4.0744,48.2973]},
	{"id":"caen_spike","name":"卡昂","parent_region_id":"normandy","lon_lat":[-0.3707,49.1829]},
	{"id":"cherbourg_spike","name":"瑟堡","parent_region_id":"normandy","lon_lat":[-1.6222,49.6337]},
	{"id":"rennes_spike","name":"雷恩","parent_region_id":"brittany","lon_lat":[-1.6778,48.1173]},
	{"id":"lorient_spike","name":"洛里昂","parent_region_id":"brittany","lon_lat":[-3.3702,47.7483]},
	{"id":"tours_spike","name":"图尔","parent_region_id":"loire_valley","lon_lat":[0.6848,47.3941]},
	{"id":"orleans_spike","name":"奥尔良","parent_region_id":"loire_valley","lon_lat":[1.9093,47.9029]},
	{"id":"angers_spike","name":"昂热","parent_region_id":"loire_valley","lon_lat":[-0.5560,47.4784]},
	{"id":"la_rochelle_spike","name":"拉罗谢尔","parent_region_id":"aquitaine","lon_lat":[-1.1511,46.1603]},
	{"id":"limoges_spike","name":"利摩日","parent_region_id":"aquitaine","lon_lat":[1.2611,45.8336]},
	{"id":"clermont_ferrand_spike","name":"克莱蒙费朗","parent_region_id":"massif_central","lon_lat":[3.0870,45.7772]},
	{"id":"dijon_spike","name":"第戎","parent_region_id":"massif_central","lon_lat":[5.0415,47.3220]},
	{"id":"besancon_spike","name":"贝桑松","parent_region_id":"massif_central","lon_lat":[6.0241,47.2378]},
	{"id":"grenoble_spike","name":"格勒诺布尔","parent_region_id":"rhone_valley","lon_lat":[5.7245,45.1885]},
	{"id":"saint_etienne_spike","name":"圣艾蒂安","parent_region_id":"rhone_valley","lon_lat":[4.3872,45.4397]},
	{"id":"chambery_spike","name":"尚贝里","parent_region_id":"rhone_valley","lon_lat":[5.9178,45.5646]},
	{"id":"nice_spike","name":"尼斯","parent_region_id":"mediterranean_coast","lon_lat":[7.2620,43.7102]},
	{"id":"montpellier_spike","name":"蒙彼利埃","parent_region_id":"mediterranean_coast","lon_lat":[3.8767,43.6119]},
	{"id":"perpignan_spike","name":"佩皮尼昂","parent_region_id":"mediterranean_coast","lon_lat":[2.8954,42.6887]}
]

var selected_administrative_unit_id: String = ""
var hover_administrative_unit_id: String = ""
var _administrative_notice: String = ""
var _administrative_unit_by_id: Dictionary = {}
var _administrative_polygons_by_id: Dictionary = {}
var _administrative_anchor_by_id: Dictionary = {}
var _administrative_units_by_region: Dictionary = {}
var _administrative_screen_polygons: Dictionary = {}
var _globe_grid_unit_lines: Array[PackedVector3Array] = []


func _ready() -> void:
	super._ready()
	_load_administrative_visual_data()
	_install_spike_city_coverage()
	_build_globe_grid()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if space_level == REGION:
		if event is InputEventMouseMotion:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			if _position_hits_ui(motion.position):
				super._gui_input(event)
				return
			_select_administrative_unit_at(motion.position, false)
			return
		if event is InputEventMouseButton:
			var button: InputEventMouseButton = event as InputEventMouseButton
			if _position_hits_ui(button.position):
				super._gui_input(event)
				return
			if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
				_select_administrative_unit_at(button.position, true)
				accept_event()
				return
	super._gui_input(event)


func _activate_button(action: String) -> void:
	if action == "previous_region":
		_cycle_region(-1)
		return
	if action == "next_region":
		_cycle_region(1)
		return
	super._activate_button(action)


func _draw_global_world() -> void:
	_draw_rotating_globe_grid()
	super._draw_global_world()


func _draw_region_map() -> void:
	var rect: Rect2 = _main_content_rect(120.0, 166.0, 104.0)
	_panel(rect, Color(0.018, 0.039, 0.047, 0.94), Color(0.70, 0.62, 0.36, 0.34))
	var region: Dictionary = _region_by_id.get(selected_region_id, {}) as Dictionary
	var unit_ids: Array = _administrative_units_by_region.get(selected_region_id, []) as Array
	var region_index: int = _region_index(selected_region_id)
	_draw_label(
		rect.position + Vector2(24.0, 34.0),
		"大区层 · %s · 行政分区 %d" % [str(region.get("display_name_zh", "选中大区")), unit_ids.size()],
		17
	)
	_draw_label(
		rect.position + Vector2(24.0, 58.0),
		_ellipsize(_administrative_notice, 82),
		11,
		Color(0.68, 0.77, 0.75, 1.0)
	)
	_draw_label(
		rect.position + Vector2(24.0, 80.0),
		"统一地理比例投影；分区可悬停和点击；轻微阴影仅用于表现层次。",
		11,
		Color(0.72, 0.69, 0.52, 1.0)
	)
	_draw_button(Rect2(rect.end.x - 284.0, rect.position.y + 18.0, 112.0, 28.0), "上一个大区", "previous_region", _regions.size() > 1)
	_draw_button(Rect2(rect.end.x - 160.0, rect.position.y + 18.0, 112.0, 28.0), "下一个大区", "next_region", _regions.size() > 1)
	_draw_label(rect.end - Vector2(156.0, 60.0), "%d / %d" % [region_index + 1, _regions.size()], 11, Color(0.68, 0.77, 0.75, 1.0))
	_draw_region_flat_geometry(rect)
	_draw_region_cities_and_routes(rect)
	_draw_region_institutions(rect)
	if not selected_administrative_unit_id.is_empty():
		var selected_unit: Dictionary = _administrative_unit_by_id.get(selected_administrative_unit_id, {}) as Dictionary
		_draw_label(
			rect.position + Vector2(24.0, rect.size.y - 22.0),
			"当前行政分区：" + _administrative_display_name(selected_unit, selected_administrative_unit_id),
			12,
			Color(0.94, 0.80, 0.50, 1.0)
		)


func _draw_region_flat_geometry(rect: Rect2) -> void:
	_administrative_screen_polygons.clear()
	var region_polygons: Array = _region_polygons.get(selected_region_id, []) as Array
	var bounds: Rect2 = _lon_lat_bounds(region_polygons)
	var map_rect: Rect2 = _region_map_rect(rect)
	var unit_ids: Array = _administrative_units_by_region.get(selected_region_id, []) as Array
	if unit_ids.is_empty():
		super._draw_region_flat_geometry(rect)
		return

	for unit_id_value: Variant in unit_ids:
		var unit_id: String = str(unit_id_value)
		var source_polygons: Array = _administrative_polygons_by_id.get(unit_id, []) as Array
		var screen_polygons: Array[PackedVector2Array] = []
		for polygon_value: Variant in source_polygons:
			var source: PackedVector2Array = polygon_value
			var screen: PackedVector2Array = PackedVector2Array()
			for lon_lat: Vector2 in source:
				screen.append(_lon_lat_to_rect(lon_lat, bounds, map_rect))
			if screen.size() > 2:
				screen_polygons.append(screen)
		_administrative_screen_polygons[unit_id] = screen_polygons

	for unit_id_value: Variant in unit_ids:
		var unit_id: String = str(unit_id_value)
		var polygons: Array = _administrative_screen_polygons.get(unit_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			var shadow: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in polygon:
				shadow.append(point + Vector2(5.0, 7.0))
			draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.26))

	for unit_index: int in range(unit_ids.size()):
		var unit_id: String = str(unit_ids[unit_index])
		var selected: bool = unit_id == selected_administrative_unit_id
		var hovered: bool = unit_id == hover_administrative_unit_id
		var fill: Color = _administrative_fill_color(unit_index)
		var border: Color = Color(0.66, 0.75, 0.70, 0.52)
		var width: float = 1.0
		if selected:
			fill = Color(0.78, 0.56, 0.22, 0.58)
			border = Color(0.98, 0.82, 0.43, 0.98)
			width = 2.2
		elif hovered:
			fill = Color(0.34, 0.64, 0.59, 0.55)
			border = Color(0.80, 0.95, 0.88, 0.92)
			width = 1.8
		var polygons: Array = _administrative_screen_polygons.get(unit_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			draw_colored_polygon(polygon, fill)
			draw_polyline(polygon, border, width, true)
		var anchor_value: Variant = _administrative_anchor_by_id.get(unit_id, null)
		if anchor_value is Vector2:
			var anchor: Vector2 = _lon_lat_to_rect(anchor_value as Vector2, bounds, map_rect)
			var unit: Dictionary = _administrative_unit_by_id.get(unit_id, {}) as Dictionary
			var label: String = _administrative_short_label(unit, unit_id)
			_draw_label(anchor + Vector2(5.0, 3.0), label, 9, Color(0.78, 0.83, 0.78, 0.90))


func _lon_lat_to_rect(lon_lat: Vector2, bounds: Rect2, rect: Rect2) -> Vector2:
	var center_lon: float = bounds.position.x + bounds.size.x * 0.5
	var center_lat: float = bounds.position.y + bounds.size.y * 0.5
	var longitude_factor: float = maxf(0.18, cos(deg_to_rad(center_lat)))
	var geographic_width: float = maxf(0.001, bounds.size.x * longitude_factor)
	var geographic_height: float = maxf(0.001, bounds.size.y)
	var scale: float = minf(rect.size.x / geographic_width, rect.size.y / geographic_height)
	var projected_x: float = (lon_lat.x - center_lon) * longitude_factor * scale
	var projected_y: float = -(lon_lat.y - center_lat) * scale
	return rect.get_center() + Vector2(projected_x, projected_y)


func _select_administrative_unit_at(position: Vector2, click: bool) -> void:
	var found: String = ""
	for unit_key_value: Variant in _administrative_screen_polygons.keys():
		var unit_id: String = str(unit_key_value)
		var polygons: Array = _administrative_screen_polygons.get(unit_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			if Geometry2D.is_point_in_polygon(position, polygon):
				found = unit_id
				break
		if not found.is_empty():
			break
	if hover_administrative_unit_id != found:
		hover_administrative_unit_id = found
		queue_redraw()
	if click and not found.is_empty():
		selected_administrative_unit_id = found
		queue_redraw()


func _cycle_region(direction: int) -> void:
	if _regions.is_empty():
		return
	var current_index: int = _region_index(selected_region_id)
	var next_index: int = posmod(current_index + direction, _regions.size())
	var next_region: Dictionary = _regions[next_index]
	selected_region_id = str(next_region.get("id", ""))
	selected_city_id = ""
	selected_institution_id = ""
	selected_administrative_unit_id = ""
	hover_administrative_unit_id = ""
	queue_redraw()


func _region_index(region_id: String) -> int:
	for index: int in range(_regions.size()):
		if str(_regions[index].get("id", "")) == region_id:
			return index
	return 0


func _load_administrative_visual_data() -> void:
	var document: Dictionary = _read_document("res://data/world_map/regions.json")
	_administrative_notice = str(document.get(
		"administrative_geometry_notice",
		"行政分区几何来自现有省级边界数据；不额外伪造历史边界。"
	))
	var unit_values: Array = document.get("administrative_units", []) as Array
	for unit_value: Variant in unit_values:
		if not unit_value is Dictionary:
			continue
		var unit: Dictionary = unit_value as Dictionary
		var unit_id: String = str(unit.get("id", ""))
		if unit_id.is_empty():
			continue
		_administrative_unit_by_id[unit_id] = unit
		var polygons: Array[PackedVector2Array] = []
		var largest_polygon: PackedVector2Array = PackedVector2Array()
		var largest_area: float = -1.0
		var geometries: Array = unit.get("geometry", []) as Array
		for geometry_value: Variant in geometries:
			if not geometry_value is Dictionary:
				continue
			var geometry: Dictionary = geometry_value as Dictionary
			var outer: PackedVector2Array = _points_from_raw(geometry.get("outer", []))
			if outer.size() < 3:
				continue
			var simplified: PackedVector2Array = _simplify_line(outer, 110)
			polygons.append(simplified)
			var area: float = absf(_polygon_area_score(simplified))
			if area > largest_area:
				largest_area = area
				largest_polygon = simplified
		_administrative_polygons_by_id[unit_id] = polygons
		if not largest_polygon.is_empty():
			_administrative_anchor_by_id[unit_id] = _average_vector2(largest_polygon)

	for region: Dictionary in _regions:
		var region_id: String = str(region.get("id", ""))
		var unit_ids: Array = []
		var source_ids: Array = region.get("administrative_unit_ids", []) as Array
		for unit_id_value: Variant in source_ids:
			var unit_id: String = str(unit_id_value)
			if _administrative_unit_by_id.has(unit_id):
				unit_ids.append(unit_id)
		_administrative_units_by_region[region_id] = unit_ids


func _install_spike_city_coverage() -> void:
	for supplement_value: Variant in REGION_CITY_SUPPLEMENTS:
		var supplement: Dictionary = supplement_value as Dictionary
		var city_id: String = str(supplement.get("id", ""))
		if city_id.is_empty() or _city_by_id.has(city_id):
			continue
		var record: Dictionary = {
			"id": city_id,
			"name": str(supplement.get("name", city_id)),
			"object_level": "city",
			"parent_country_id": FOCUS_COUNTRY_ID,
			"parent_region_id": str(supplement.get("parent_region_id", "")),
			"lon_lat": supplement.get("lon_lat", []),
			"major": false,
			"spike_supplement": true,
		}
		_cities.append(record)
		_city_by_id[city_id] = record
		var region_id: String = str(record.get("parent_region_id", ""))
		var city_ids: Array = _cities_by_region.get(region_id, []) as Array
		city_ids.append(city_id)
		_cities_by_region[region_id] = city_ids


func _build_globe_grid() -> void:
	_globe_grid_unit_lines.clear()
	for latitude: int in [-60, -30, 0, 30, 60]:
		var latitude_line: PackedVector3Array = PackedVector3Array()
		for longitude: int in range(-180, 181, 6):
			latitude_line.append(_lon_lat_to_unit(Vector2(float(longitude), float(latitude))))
		_globe_grid_unit_lines.append(latitude_line)
	for longitude: int in range(-150, 181, 30):
		var longitude_line: PackedVector3Array = PackedVector3Array()
		for latitude: int in range(-84, 85, 4):
			longitude_line.append(_lon_lat_to_unit(Vector2(float(longitude), float(latitude))))
		_globe_grid_unit_lines.append(longitude_line)


func _draw_rotating_globe_grid() -> void:
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	for grid_line: PackedVector3Array in _globe_grid_unit_lines:
		var segments: Array[PackedVector2Array] = _project_unit_line(grid_line, basis)
		for segment: PackedVector2Array in segments:
			draw_polyline(segment, Color(0.45, 0.67, 0.64, 0.10), 0.65, true)


func _average_vector2(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for point: Vector2 in points:
		total += point
	return total / float(points.size())


func _administrative_fill_color(index: int) -> Color:
	match index % 6:
		0:
			return Color(0.18, 0.31, 0.33, 0.52)
		1:
			return Color(0.22, 0.34, 0.30, 0.52)
		2:
			return Color(0.24, 0.29, 0.37, 0.52)
		3:
			return Color(0.31, 0.29, 0.24, 0.52)
		4:
			return Color(0.21, 0.35, 0.34, 0.52)
		_:
			return Color(0.29, 0.26, 0.33, 0.52)


func _administrative_short_label(unit: Dictionary, fallback_id: String) -> String:
	var source_code: String = str(unit.get("source_code", ""))
	if not source_code.is_empty():
		return source_code
	return _ellipsize(_administrative_display_name(unit, fallback_id), 10)


func _administrative_display_name(unit: Dictionary, fallback_id: String) -> String:
	var candidates: Array = [
		unit.get("display_name_zh", ""),
		unit.get("name_zh", ""),
		unit.get("name", ""),
		unit.get("native_name", ""),
		unit.get("source_code", ""),
	]
	for candidate_value: Variant in candidates:
		var candidate: String = str(candidate_value)
		if not candidate.is_empty():
			return candidate
	return fallback_id
