class_name PrototypeV2MapCanvas
extends Control
## Geographic V2.1 prototype map. Every object is projected from WGS84 lon/lat.

const WORLD_SIZE := Vector2(1080.0, 540.0)
const ROBINSON_X := [1.0, 0.9986, 0.9954, 0.99, 0.9822, 0.973, 0.96, 0.9427, 0.9216, 0.8962, 0.8679, 0.835, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322]
const ROBINSON_Y := [0.0, 0.062, 0.124, 0.186, 0.248, 0.31, 0.372, 0.434, 0.4958, 0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1.0]
const ROBINSON_X_EXTENT := 2.6662696851
const ROBINSON_Y_EXTENT := 1.3523

const OCEAN_TOP := Color("#1f4150")
const OCEAN_BOTTOM := Color("#0d2632")
const OCEAN_GRID := Color(0.46, 0.68, 0.72, 0.12)
const LAND_BASE := Color("#66776c")
const COAST := Color("#dfd4b8")
const COUNTRY_BORDER := Color(0.15, 0.22, 0.23, 0.82)
const REGION_BORDER := Color(0.91, 0.84, 0.65, 0.74)
const LABEL := Color("#f2ead7")
const LABEL_MUTED := Color("#b9c2b5")
const SELECT := Color("#f2c865")
const CITY := Color("#f6e7bd")
const PORT_COLOR := Color("#66b5c4")
const RAIL_DARK := Color("#172022")
const RAIL_LIGHT := Color("#e0bd6f")
const ROAD := Color("#ba9e79")
const SHIPPING := Color("#67b8c8")
const INSTITUTION := Color("#d2a65f")
const ORGANIZATION := Color("#83b88c")
const FRONT := Color("#d46355")
const FOCUS_COUNTRY_ID := "country_fra"
const PLAYER_CITY_ID := "lille"

var current_mode: String = "legal"
var selected_id: String = ""
var selected_type: String = ""
var zoom: float = 0.94
var pan: Vector2 = Vector2(132.0, 93.0)
var war_example_active: bool = false

var _data: PrototypeV2Data
var _font: Font
var _coastlines: Array = []
var _countries: Array = []
var _regions: Array = []
var _cities: Array = []
var _ports: Array = []
var _rail_segments: Array = []
var _road_segments: Array = []
var _shipping_routes: Array = []
var _institutions: Array = []
var _organizations: Array = []
var _modes: Dictionary = {}
var _country_by_id: Dictionary = {}
var _country_by_iso: Dictionary = {}
var _features_by_iso: Dictionary = {}
var _region_by_id: Dictionary = {}
var _city_by_id: Dictionary = {}
var _port_by_id: Dictionary = {}
var _institution_by_id: Dictionary = {}
var _organization_by_id: Dictionary = {}
var _label_rects: Array[Rect2] = []
var _label_counts: Dictionary = {}
var _last_draw_counts: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_font = ThemeDB.fallback_font


func setup(prototype_data: PrototypeV2Data) -> void:
	_data = prototype_data
	_coastlines = _document_array("world_coastlines", "features")
	_countries = _document_array("countries", "countries")
	_regions = _document_array("regions", "regions")
	_cities = _document_array("cities", "cities")
	_ports = _document_array("ports", "ports")
	_rail_segments = _document_array("rail_segments", "segments")
	_road_segments = _document_array("road_segments", "segments")
	_shipping_routes = _document_array("shipping_routes", "routes")
	_institutions = _document_array("institutions", "institutions")
	_modes = _data.get_document("map_modes")
	_build_indexes()
	reset_view()
	queue_redraw()


func set_mode(mode_id: String) -> void:
	current_mode = mode_id
	queue_redraw()


func set_war_example_active(active: bool) -> void:
	war_example_active = active
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
	var zoom_config: Dictionary = _modes.get("zoom", {}) as Dictionary
	var minimum: float = float(zoom_config.get("minimum", 0.82))
	var maximum: float = float(zoom_config.get("maximum", 5.8))
	var factor: float = float(zoom_config.get("factor", 1.24))
	var previous: float = zoom
	var next_zoom: float = clampf(zoom * (factor if direction > 0.0 else 1.0 / factor), minimum, maximum)
	if is_equal_approx(previous, next_zoom):
		return
	var world_anchor: Vector2 = (anchor - pan) / previous
	zoom = next_zoom
	pan = anchor - world_anchor * zoom
	_clamp_pan()
	queue_redraw()


func reset_view() -> void:
	_set_view(Vector2(4.0, 14.0), 0.94, Vector2(640.0, 356.0))


func focus_europe() -> void:
	_set_view(Vector2(9.0, 49.0), 3.25, Vector2(650.0, 354.0))


func focus_france() -> void:
	_set_view(Vector2(2.25, 47.1), 9.2, Vector2(650.0, 360.0))


func get_zoom_level() -> String:
	var zoom_config: Dictionary = _modes.get("zoom", {}) as Dictionary
	if zoom <= float(zoom_config.get("far_max", 1.5)):
		return "far"
	if zoom <= float(zoom_config.get("middle_max", 3.15)):
		return "middle"
	return "near"


func get_shared_basemap_id() -> String:
	return str(_modes.get("shared_basemap_id", ""))


func has_visible_front() -> bool:
	return current_mode == "war" and war_example_active


func project_lon_lat(value: Variant) -> Vector2:
	var lon_lat: Vector2 = _array_to_vector(value)
	var longitude_radians: float = deg_to_rad(clampf(lon_lat.x, -180.0, 180.0))
	var latitude: float = clampf(lon_lat.y, -90.0, 90.0)
	var coefficient_index: float = absf(latitude) / 5.0
	var lower: int = clampi(int(floor(coefficient_index)), 0, ROBINSON_X.size() - 1)
	var upper: int = mini(lower + 1, ROBINSON_X.size() - 1)
	var weight: float = coefficient_index - float(lower)
	var x_coefficient: float = lerpf(float(ROBINSON_X[lower]), float(ROBINSON_X[upper]), weight)
	var y_coefficient: float = lerpf(float(ROBINSON_Y[lower]), float(ROBINSON_Y[upper]), weight)
	var projected_x: float = 0.8487 * longitude_radians * x_coefficient
	var projected_y: float = 1.3523 * signf(latitude) * y_coefficient
	return Vector2(
		(projected_x / (ROBINSON_X_EXTENT * 2.0) + 0.5) * WORLD_SIZE.x,
		(0.5 - projected_y / (ROBINSON_Y_EXTENT * 2.0)) * WORLD_SIZE.y
	)


func lon_lat_to_screen(value: Variant) -> Vector2:
	return project_lon_lat(value) * zoom + pan


func region_contains_lon_lat(region_id: String, lon_lat: Variant) -> bool:
	var region: Dictionary = get_region(region_id)
	if region.is_empty():
		return false
	return Geometry2D.is_point_in_polygon(_array_to_vector(lon_lat), _lon_lat_polygon(region.get("polygon_lon_lat", [])))


func is_record_visible(record: Dictionary) -> bool:
	return zoom >= float(record.get("min_zoom", 0.0)) and zoom <= float(record.get("max_zoom", 99.0))


func get_object_at(screen_position: Vector2) -> Dictionary:
	var world_position: Vector2 = (screen_position - pan) / zoom
	if get_zoom_level() == "near" and should_draw_detail_nodes():
		var node_result: Dictionary = _node_at(world_position, _institutions, "institution", 11.0)
		if not node_result.is_empty():
			return node_result
		node_result = _node_at(world_position, _organizations, "organization", 10.0)
		if not node_result.is_empty():
			return node_result
		var port_result: Dictionary = _node_at(world_position, _ports, "port", 10.0)
		if not port_result.is_empty():
			return port_result
	var city_result: Dictionary = _node_at(world_position, _cities, "city", 11.0)
	if not city_result.is_empty():
		return city_result
	if get_zoom_level() == "near":
		for index: int in range(_regions.size() - 1, -1, -1):
			var region: Dictionary = _regions[index] as Dictionary
			for clipped_polygon: PackedVector2Array in _clipped_region_world_polygons(region):
				if Geometry2D.is_point_in_polygon(world_position, clipped_polygon):
					return {"type": "region", "id": str(region.get("id", "")), "data": region}
	for country_variant: Variant in _countries:
		var country: Dictionary = country_variant as Dictionary
		if _country_contains(country, world_position):
			return {"type": "country", "id": str(country.get("id", "")), "data": country}
	return {}


func get_region(region_id: String) -> Dictionary:
	return _dictionary_value(_region_by_id, region_id)


func get_city(city_id: String) -> Dictionary:
	return _dictionary_value(_city_by_id, city_id)


func get_country(country_id: String) -> Dictionary:
	return _dictionary_value(_country_by_id, country_id)


func get_institution(institution_id: String) -> Dictionary:
	return _dictionary_value(_institution_by_id, institution_id)


func get_organization(organization_id: String) -> Dictionary:
	return _dictionary_value(_organization_by_id, organization_id)


func get_label_budget(category: String, level: String = "") -> int:
	var target_level: String = get_zoom_level() if level.is_empty() else level
	var budgets: Dictionary = _modes.get("label_budgets", {}) as Dictionary
	var level_budget: Dictionary = budgets.get(target_level, {}) as Dictionary
	return int(level_budget.get(category, 0))


func get_visible_rail_ids(level: String = "") -> Array[String]:
	var target_level: String = get_zoom_level() if level.is_empty() else level
	var result: Array[String] = []
	for segment: Dictionary in _rail_segments_for_level(target_level):
		result.append(str(segment.get("id", "")))
	return result


func get_visible_city_node_ids(level: String = "") -> Array[String]:
	var target_level: String = get_zoom_level() if level.is_empty() else level
	var result: Array[String] = []
	for city_variant: Variant in _cities:
		var city: Dictionary = city_variant as Dictionary
		if _city_node_visible_for_level(city, target_level):
			result.append(str(city.get("id", "")))
	return result


func should_draw_detail_nodes() -> bool:
	return get_zoom_level() == "near" and selected_type in ["city", "region", "institution", "organization"]


func debug_resolve_label_candidates(candidates: Array, budget: int) -> Array[String]:
	var sorted_candidates: Array = candidates.duplicate(true)
	sorted_candidates.sort_custom(_candidate_higher_priority)
	var accepted_rects: Array[Rect2] = []
	var accepted_ids: Array[String] = []
	for candidate_variant: Variant in sorted_candidates:
		if accepted_ids.size() >= budget:
			break
		var candidate: Dictionary = candidate_variant as Dictionary
		var rect: Rect2 = candidate.get("rect", Rect2()) as Rect2
		var collides: bool = false
		for existing: Rect2 in accepted_rects:
			if existing.intersects(rect):
				collides = true
				break
		if collides:
			continue
		accepted_rects.append(rect)
		accepted_ids.append(str(candidate.get("id", "")))
	return accepted_ids


func _draw() -> void:
	_draw_ocean()
	if _data == null:
		return
	_label_rects.clear()
	_label_counts.clear()
	_last_draw_counts.clear()
	_draw_graticule()
	_draw_countries()
	_draw_selected_object_label()
	_draw_player_city_label()
	_draw_country_labels()
	if get_zoom_level() == "near":
		_draw_regions()
	_draw_shipping_routes()
	if get_zoom_level() != "far":
		_draw_railways()
	if get_zoom_level() == "near" and should_draw_detail_nodes():
		_draw_roads()
	if has_visible_front():
		_draw_war_overlay()
	_draw_cities()
	if get_zoom_level() != "far":
		_draw_transport_labels()
	if get_zoom_level() == "near":
		_draw_ports()
	if should_draw_detail_nodes():
		_draw_institutions()
		_draw_organizations()
	_draw_ocean_labels()
	_draw_transport_legend()


func _draw_ocean() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OCEAN_BOTTOM)
	for index: int in range(16):
		var ratio: float = float(index) / 15.0
		var color: Color = OCEAN_TOP.lerp(OCEAN_BOTTOM, ratio)
		draw_rect(Rect2(0.0, ratio * size.y, size.x, size.y / 15.0 + 1.0), Color(color, 0.58))
	for index: int in range(8):
		var center := Vector2(size.x * (0.18 + float(index % 4) * 0.23), 130.0 + float(index / 4) * 370.0)
		draw_circle(center, 210.0, Color(0.18, 0.4, 0.47, 0.035))


func _draw_graticule() -> void:
	for longitude: int in range(-150, 180, 30):
		var points := PackedVector2Array()
		for latitude: int in range(-80, 81, 5):
			points.append(lon_lat_to_screen([longitude, latitude]))
		draw_polyline(points, OCEAN_GRID, 1.0, true)
	for latitude: int in range(-60, 61, 30):
		var points := PackedVector2Array()
		for longitude: int in range(-180, 181, 5):
			points.append(lon_lat_to_screen([longitude, latitude]))
		draw_polyline(points, OCEAN_GRID, 1.0, true)


func _draw_countries() -> void:
	for feature_variant: Variant in _coastlines:
		var feature: Dictionary = feature_variant as Dictionary
		var iso_a3: String = str(feature.get("iso_a3", ""))
		var country: Dictionary = _dictionary_value(_country_by_iso, iso_a3)
		var fill: Color = _country_color(country, str(feature.get("continent", "")))
		for ring_variant: Variant in feature.get("rings", []):
			var polygon: PackedVector2Array = _screen_polygon(ring_variant)
			if polygon.size() < 3:
				continue
			# Dateline-touching rings can become non-simple after planar projection. Their
			# coastline still renders, but invalid rings are not sent to the triangulator.
			if not Geometry2D.triangulate_polygon(polygon).is_empty():
				draw_colored_polygon(polygon, fill)
			var border: Color = COAST if country.is_empty() else COUNTRY_BORDER
			draw_polyline(_closed_polygon(polygon), border, 0.75 if get_zoom_level() == "far" else 1.15, true)
			if selected_type == "country" and selected_id == str(country.get("id", "")):
				draw_polyline(_closed_polygon(polygon), SELECT, 3.2, true)


func _draw_selected_object_label() -> void:
	if selected_id.is_empty():
		return
	var record: Dictionary
	var coordinate_field: String = "lon_lat"
	match selected_type:
		"country":
			record = get_country(selected_id)
			coordinate_field = "label_lon_lat"
		"region":
			record = get_region(selected_id)
			coordinate_field = "label_lon_lat"
		"city":
			record = get_city(selected_id)
		"institution":
			record = get_institution(selected_id)
		"organization":
			record = get_organization(selected_id)
	if record.is_empty() or not record.has(coordinate_field):
		return
	var label: String = str(record.get("display_name_zh", record.get("name", "")))
	_try_label(lon_lat_to_screen(record.get(coordinate_field, [])), label, 14, SELECT, true)


func _draw_player_city_label() -> void:
	if selected_type == "city" and selected_id == PLAYER_CITY_ID:
		return
	var city: Dictionary = get_city(PLAYER_CITY_ID)
	if city.is_empty() or not is_record_visible(city):
		return
	_try_label(lon_lat_to_screen(city.get("lon_lat", [])) + Vector2(8.0, 3.0), str(city.get("name", "")), 12, SELECT, false, "city")


func _draw_country_labels() -> void:
	for country_variant: Variant in _records_by_priority(_countries):
		var country: Dictionary = country_variant as Dictionary
		if not is_record_visible(country):
			continue
		if selected_type == "country" and selected_id == str(country.get("id", "")):
			continue
		var color: Color = LABEL
		if get_zoom_level() == "near" and str(country.get("id", "")) != FOCUS_COUNTRY_ID:
			color = Color(LABEL_MUTED, 0.34)
		_try_label(lon_lat_to_screen(country.get("label_lon_lat", [])), str(country.get("name", "")), 15, color, true, "country")


func _draw_regions() -> void:
	for region_variant: Variant in _records_by_priority(_regions):
		var region: Dictionary = region_variant as Dictionary
		if not is_record_visible(region):
			continue
		var color_key: String = "legal_color"
		if current_mode == "market":
			color_key = "market_color"
		elif current_mode == "population":
			color_key = "population_color"
		var alpha: float = 0.22 if current_mode in ["legal", "war"] else 0.45
		for world_polygon: PackedVector2Array in _clipped_region_world_polygons(region):
			var polygon: PackedVector2Array = _world_to_screen_polygon(world_polygon)
			if not Geometry2D.triangulate_polygon(polygon).is_empty():
				draw_colored_polygon(polygon, Color(Color(str(region.get(color_key, "#718da0"))), alpha))
			draw_polyline(_closed_polygon(polygon), REGION_BORDER, 1.15, true)
			if selected_type == "region" and selected_id == str(region.get("id", "")):
				draw_polyline(_closed_polygon(polygon), SELECT, 3.4, true)
		if not (selected_type == "region" and selected_id == str(region.get("id", ""))):
			_try_label(lon_lat_to_screen(region.get("label_lon_lat", [])), str(region.get("name", "")), 13, LABEL, true, "region")


func _draw_shipping_routes() -> void:
	for route_variant: Variant in _shipping_routes:
		var route: Dictionary = route_variant as Dictionary
		if not is_record_visible(route):
			continue
		var points := PackedVector2Array()
		for point_variant: Variant in route.get("waypoints_lon_lat", []):
			points.append(lon_lat_to_screen(point_variant))
		for index: int in range(points.size() - 1):
			_draw_dashed_line(points[index], points[index + 1], Color(SHIPPING, 0.78), 10.0, 7.0, 1.6)


func _draw_railways() -> void:
	var drawn: int = 0
	for segment: Dictionary in _rail_segments_for_level(get_zoom_level()):
		var first: Dictionary = get_city(str(segment.get("from_city_id", "")))
		var second: Dictionary = get_city(str(segment.get("to_city_id", "")))
		if first.is_empty() or second.is_empty():
			continue
		var start: Vector2 = lon_lat_to_screen(first.get("lon_lat", []))
		var end: Vector2 = lon_lat_to_screen(second.get("lon_lat", []))
		var selected: bool = _rail_is_selected(segment)
		var alpha: float = 1.0 if selected else (0.62 if get_zoom_level() == "middle" else 0.4)
		var width: float = 3.8 if bool(segment.get("main", false)) else 2.6
		draw_line(start, end, Color(RAIL_DARK, alpha), width, true)
		draw_line(start, end, Color(RAIL_LIGHT, alpha), 1.05, true)
		_draw_rail_ties(start, end, alpha)
		drawn += 1
	_last_draw_counts["rail"] = drawn


func _draw_transport_labels() -> void:
	for segment: Dictionary in _rail_segments_for_level(get_zoom_level()):
		if not bool(segment.get("main", false)):
			continue
		var first: Dictionary = get_city(str(segment.get("from_city_id", "")))
		var second: Dictionary = get_city(str(segment.get("to_city_id", "")))
		if first.is_empty() or second.is_empty():
			continue
		var midpoint: Vector2 = (lon_lat_to_screen(first.get("lon_lat", [])) + lon_lat_to_screen(second.get("lon_lat", []))) * 0.5
		_try_label(midpoint + Vector2(0.0, -5.0), str(segment.get("name", "")), 9, Color(RAIL_LIGHT, 0.62), true, "transport")


func _draw_roads() -> void:
	for segment_variant: Variant in _road_segments:
		var segment: Dictionary = segment_variant as Dictionary
		if not is_record_visible(segment):
			continue
		var first: Dictionary = get_city(str(segment.get("from_city_id", "")))
		var second: Dictionary = get_city(str(segment.get("to_city_id", "")))
		if first.is_empty() or second.is_empty():
			continue
		_draw_dashed_line(lon_lat_to_screen(first.get("lon_lat", [])), lon_lat_to_screen(second.get("lon_lat", [])), Color(ROAD, 0.72), 4.0, 4.0, 1.0)


func _draw_war_overlay() -> void:
	var control_polygon: PackedVector2Array = _screen_polygon([[4.1, 49.1], [7.9, 48.0], [8.2, 50.8], [4.4, 51.0]])
	draw_colored_polygon(control_polygon, Color(FRONT, 0.2))
	var front_points := PackedVector2Array()
	for point: Array in [[5.8, 49.8], [5.95, 49.45], [5.75, 49.1], [6.0, 48.75], [5.82, 48.4]]:
		front_points.append(lon_lat_to_screen(point))
	draw_polyline(front_points, Color(FRONT, 0.22), 13.0, true)
	draw_polyline(front_points, FRONT, 4.0, true)
	_try_label(lon_lat_to_screen([6.75, 49.15]), "莱茵战区 · 静态示例", 12, Color("#ffd0b0"), true)


func _draw_cities() -> void:
	var level: String = get_zoom_level()
	for city_variant: Variant in _records_by_priority(_cities):
		var city: Dictionary = city_variant as Dictionary
		if not is_record_visible(city) or not _city_node_visible_for_level(city, level):
			continue
		var point: Vector2 = lon_lat_to_screen(city.get("lon_lat", []))
		var is_selected: bool = selected_type == "city" and selected_id == str(city.get("id", ""))
		if is_selected:
			draw_circle(point, 10.0, Color(SELECT, 0.24))
		draw_circle(point, 4.5 if bool(city.get("major", false)) else 3.2, SELECT if is_selected else CITY)
		draw_circle(point, 1.55, Color("#253537"))
		var allow_middle_french_label: bool = str(city.get("parent_country_id", "")) != FOCUS_COUNTRY_ID or str(city.get("id", "")) in ["paris", PLAYER_CITY_ID]
		if (level == "near" or (int(city.get("label_priority", 0)) >= 84 and allow_middle_french_label)) and not is_selected and str(city.get("id", "")) != PLAYER_CITY_ID:
			_try_label(point + Vector2(8.0, 3.0), str(city.get("name", "")), 11, LABEL, false, "city")


func _draw_ports() -> void:
	for port_variant: Variant in _ports:
		var port: Dictionary = port_variant as Dictionary
		if not is_record_visible(port):
			continue
		var point: Vector2 = lon_lat_to_screen(port.get("lon_lat", [])) + Vector2(0.0, 7.0)
		draw_arc(point, 5.5, 0.15, PI - 0.15, 12, PORT_COLOR, 1.5)
		draw_line(point + Vector2(0.0, -6.0), point + Vector2(0.0, 4.0), PORT_COLOR, 1.4)


func _draw_institutions() -> void:
	for institution_variant: Variant in _records_by_priority(_institutions):
		var institution: Dictionary = institution_variant as Dictionary
		if not is_record_visible(institution) or not _detail_record_relevant(institution):
			continue
		var point: Vector2 = lon_lat_to_screen(institution.get("lon_lat", []))
		var selected: bool = selected_type == "institution" and selected_id == str(institution.get("id", ""))
		_draw_diamond(point, 6.0, SELECT if selected else INSTITUTION)
		_try_label(point + Vector2(10.0, 4.0), str(institution.get("name", "")), 10, LABEL_MUTED, false)


func _draw_organizations() -> void:
	for organization_variant: Variant in _records_by_priority(_organizations):
		var organization: Dictionary = organization_variant as Dictionary
		if not is_record_visible(organization) or not _detail_record_relevant(organization):
			continue
		var point: Vector2 = lon_lat_to_screen(organization.get("lon_lat", []))
		var selected: bool = selected_type == "organization" and selected_id == str(organization.get("id", ""))
		draw_circle(point, 5.5, SELECT if selected else ORGANIZATION)
		draw_circle(point, 2.2, Color("#1c3430"))
		if selected:
			_try_label(point + Vector2(10.0, 4.0), str(organization.get("name", "")), 10, LABEL_MUTED, false)


func _draw_ocean_labels() -> void:
	if get_zoom_level() != "far":
		return
	_try_label(lon_lat_to_screen([-38.0, 6.0]), "大 西 洋", 14, Color(LABEL_MUTED, 0.56), true)
	_try_label(lon_lat_to_screen([79.0, -23.0]), "印 度 洋", 14, Color(LABEL_MUTED, 0.56), true)
	_try_label(lon_lat_to_screen([-151.0, 4.0]), "太 平 洋", 14, Color(LABEL_MUTED, 0.56), true)
	_try_label(lon_lat_to_screen([159.0, -4.0]), "太 平 洋", 14, Color(LABEL_MUTED, 0.56), true)


func _draw_transport_legend() -> void:
	if get_zoom_level() == "far":
		return
	var origin := Vector2(478.0, 672.0)
	draw_rect(Rect2(origin - Vector2(12.0, 18.0), Vector2(326.0, 34.0)), Color(0.025, 0.06, 0.07, 0.78))
	draw_line(origin, origin + Vector2(34.0, 0.0), RAIL_DARK, 3.4, true)
	draw_line(origin, origin + Vector2(34.0, 0.0), RAIL_LIGHT, 1.0, true)
	draw_string(_font, origin + Vector2(40.0, 4.0), "铁路", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, LABEL_MUTED)
	_draw_dashed_line(origin + Vector2(86.0, 0.0), origin + Vector2(120.0, 0.0), ROAD, 4.0, 4.0, 1.0)
	draw_string(_font, origin + Vector2(126.0, 4.0), "陆路", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, LABEL_MUTED)
	_draw_dashed_line(origin + Vector2(170.0, 0.0), origin + Vector2(206.0, 0.0), SHIPPING, 9.0, 6.0, 1.5)
	draw_string(_font, origin + Vector2(212.0, 4.0), "航运", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, LABEL_MUTED)
	if has_visible_front():
		draw_line(origin + Vector2(260.0, 0.0), origin + Vector2(286.0, 0.0), FRONT, 4.0, true)
		draw_string(_font, origin + Vector2(292.0, 4.0), "战线", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color("#ffc1a8"))


func _build_indexes() -> void:
	_country_by_id.clear()
	_country_by_iso.clear()
	_features_by_iso.clear()
	_region_by_id.clear()
	_city_by_id.clear()
	_port_by_id.clear()
	_institution_by_id.clear()
	_organization_by_id.clear()
	_organizations.clear()
	for feature_variant: Variant in _coastlines:
		var feature: Dictionary = feature_variant as Dictionary
		_features_by_iso[str(feature.get("iso_a3", ""))] = feature
	for country_variant: Variant in _countries:
		var country: Dictionary = country_variant as Dictionary
		_country_by_id[str(country.get("id", ""))] = country
		for iso_variant: Variant in country.get("geometry_iso_a3", []):
			_country_by_iso[str(iso_variant)] = country
	for region_variant: Variant in _regions:
		var region: Dictionary = region_variant as Dictionary
		_region_by_id[str(region.get("id", ""))] = region
	for city_variant: Variant in _cities:
		var city: Dictionary = city_variant as Dictionary
		_city_by_id[str(city.get("id", ""))] = city
	for port_variant: Variant in _ports:
		var port: Dictionary = port_variant as Dictionary
		_port_by_id[str(port.get("id", ""))] = port
	for institution_variant: Variant in _institutions:
		var institution: Dictionary = institution_variant as Dictionary
		_institution_by_id[str(institution.get("id", ""))] = institution
	for organization_variant: Variant in _data.get_document("organizations").get("catalog", []):
		var organization: Dictionary = organization_variant as Dictionary
		var organization_id: String = str(organization.get("id", ""))
		_organization_by_id[organization_id] = organization
		if organization.has("lon_lat"):
			_organizations.append(organization)


func _document_array(document_id: String, field: String) -> Array:
	return _data.get_document(document_id).get(field, []) as Array


func _records_by_priority(records: Array) -> Array:
	var result: Array = records.duplicate()
	result.sort_custom(_record_higher_priority)
	return result


func _record_higher_priority(first_variant: Variant, second_variant: Variant) -> bool:
	var first: Dictionary = first_variant as Dictionary
	var second: Dictionary = second_variant as Dictionary
	return _record_priority(first) > _record_priority(second)


func _record_priority(record: Dictionary) -> int:
	if record.has("label_priority"):
		return int(record.get("label_priority", 0))
	return 70 if bool(record.get("main", false)) else 30


func _candidate_higher_priority(first_variant: Variant, second_variant: Variant) -> bool:
	return int((first_variant as Dictionary).get("priority", 0)) > int((second_variant as Dictionary).get("priority", 0))


func _rail_segments_for_level(level: String) -> Array[Dictionary]:
	if level == "far":
		return []
	var candidates: Array = []
	for segment_variant: Variant in _rail_segments:
		var segment: Dictionary = segment_variant as Dictionary
		if level == get_zoom_level() and not is_record_visible(segment):
			continue
		if level == "middle" and not bool(segment.get("main", false)):
			continue
		candidates.append(segment)
	candidates = _records_by_priority(candidates)
	var result: Array[Dictionary] = []
	var limit: int = get_label_budget("transport", level)
	for index: int in range(mini(limit, candidates.size())):
		result.append(candidates[index] as Dictionary)
	return result


func _city_node_visible_for_level(city: Dictionary, level: String) -> bool:
	if level != "middle":
		return true
	var city_id: String = str(city.get("id", ""))
	if str(city.get("parent_country_id", "")) != FOCUS_COUNTRY_ID:
		return int(city.get("label_priority", 0)) >= 84
	if city_id in ["paris", PLAYER_CITY_ID]:
		return true
	for segment: Dictionary in _rail_segments_for_level("middle"):
		if city_id in [str(segment.get("from_city_id", "")), str(segment.get("to_city_id", ""))]:
			return true
	return false


func _rail_is_selected(segment: Dictionary) -> bool:
	if selected_type == "city":
		return selected_id in [str(segment.get("from_city_id", "")), str(segment.get("to_city_id", ""))]
	if selected_type == "region":
		var first: Dictionary = get_city(str(segment.get("from_city_id", "")))
		var second: Dictionary = get_city(str(segment.get("to_city_id", "")))
		return selected_id in [str(first.get("parent_region_id", "")), str(second.get("parent_region_id", ""))]
	return false


func _detail_record_relevant(record: Dictionary) -> bool:
	match selected_type:
		"city":
			return str(record.get("city_id", "")) == selected_id
		"region":
			return str(record.get("parent_region_id", "")) == selected_id
		"institution":
			return str(record.get("id", "")) == selected_id or str(record.get("institution_id", "")) == selected_id
		"organization":
			return str(record.get("id", "")) == selected_id
	return false


func _country_color(country: Dictionary, continent: String) -> Color:
	if country.is_empty():
		var generic: Dictionary = {
			"Africa": Color("#777d68"), "Asia": Color("#747a68"), "Europe": Color("#6e7d76"),
			"North America": Color("#6e7c71"), "South America": Color("#6f806e"), "Oceania": Color("#7b806d"),
		}
		return Color(generic.get(continent, LAND_BASE) as Color, 0.94)
	var key: String = "legal_color"
	if current_mode == "market":
		key = "market_color"
	elif current_mode == "population":
		key = "population_color"
	elif current_mode == "war":
		key = "war_color"
	return Color(Color(str(country.get(key, "#738077"))), 0.96)


func _node_at(world_position: Vector2, records: Array, object_type: String, radius_pixels: float) -> Dictionary:
	for index: int in range(records.size() - 1, -1, -1):
		var record: Dictionary = records[index] as Dictionary
		if not record.has("lon_lat") or not is_record_visible(record):
			continue
		if world_position.distance_to(project_lon_lat(record.get("lon_lat", []))) <= radius_pixels / zoom:
			return {"type": object_type, "id": str(record.get("id", "")), "data": record}
	return {}


func _country_contains(country: Dictionary, world_position: Vector2) -> bool:
	for iso_variant: Variant in country.get("geometry_iso_a3", []):
		var feature: Dictionary = _dictionary_value(_features_by_iso, str(iso_variant))
		for ring_variant: Variant in feature.get("rings", []):
			if Geometry2D.is_point_in_polygon(world_position, _projected_polygon(ring_variant)):
				return true
	return false


func _set_view(center_lon_lat: Vector2, next_zoom: float, screen_anchor: Vector2) -> void:
	zoom = next_zoom
	pan = screen_anchor - project_lon_lat(center_lon_lat) * zoom
	_clamp_pan()
	queue_redraw()


func _clamp_pan() -> void:
	var scaled: Vector2 = WORLD_SIZE * zoom
	var margin := Vector2(230.0, 170.0)
	pan.x = clampf(pan.x, size.x - scaled.x - margin.x, margin.x)
	pan.y = clampf(pan.y, size.y - scaled.y - margin.y, margin.y)


func _screen_polygon(source: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if source is Array:
		for point_variant: Variant in source as Array:
			result.append(lon_lat_to_screen(point_variant))
	return result


func _projected_polygon(source: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if source is Array:
		for point_variant: Variant in source as Array:
			result.append(project_lon_lat(point_variant))
	return result


func _world_to_screen_polygon(source: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in source:
		result.append(point * zoom + pan)
	return result


func _clipped_region_world_polygons(region: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var region_polygon: PackedVector2Array = _projected_polygon(region.get("polygon_lon_lat", []))
	var france_feature: Dictionary = _dictionary_value(_features_by_iso, "FRA")
	for ring_variant: Variant in france_feature.get("rings", []):
		var country_polygon: PackedVector2Array = _projected_polygon(ring_variant)
		for intersection_variant: Variant in Geometry2D.intersect_polygons(region_polygon, country_polygon):
			var intersection: PackedVector2Array = intersection_variant as PackedVector2Array
			if intersection.size() >= 3:
				result.append(intersection)
	return result


func _lon_lat_polygon(source: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if source is Array:
		for point_variant: Variant in source as Array:
			result.append(_array_to_vector(point_variant))
	return result


func _closed_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if not result.is_empty() and result[0] != result[-1]:
		result.append(result[0])
	return result


func _array_to_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _dictionary_value(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _try_label(position: Vector2, value: String, font_size: int, color: Color, centered: bool, category: String = "") -> bool:
	if value.is_empty():
		return false
	if not category.is_empty() and int(_label_counts.get(category, 0)) >= get_label_budget(category):
		return false
	var text_size: Vector2 = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var top_left := Vector2(position.x - text_size.x * 0.5 if centered else position.x, position.y - text_size.y * 0.72)
	# Labels keep readable air around their glyph bounds; low-priority candidates are
	# dropped instead of compressing dense Western European names together.
	var rect := Rect2(top_left - Vector2(7.0, 4.0), text_size + Vector2(14.0, 8.0))
	if rect.end.x < 0.0 or rect.position.x > size.x or rect.end.y < 0.0 or rect.position.y > size.y:
		return false
	for existing: Rect2 in _label_rects:
		if existing.intersects(rect):
			return false
	_label_rects.append(rect)
	if not category.is_empty():
		_label_counts[category] = int(_label_counts.get(category, 0)) + 1
	draw_string(_font, top_left + Vector2(0.0, text_size.y * 0.78), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
	return true


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


func _draw_rail_ties(start: Vector2, end: Vector2, alpha: float = 1.0) -> void:
	var distance: float = start.distance_to(end)
	if distance < 12.0:
		return
	var direction: Vector2 = (end - start).normalized()
	var normal := Vector2(-direction.y, direction.x) * 3.5
	var cursor: float = 8.0
	while cursor < distance:
		var center: Vector2 = start + direction * cursor
		draw_line(center - normal, center + normal, Color(RAIL_LIGHT, 0.78 * alpha), 0.85, true)
		cursor += 13.0


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(_closed_polygon(points), Color("#2a3331"), 1.0, true)
