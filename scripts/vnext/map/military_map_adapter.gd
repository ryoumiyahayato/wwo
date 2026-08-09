class_name VNextMilitaryMapAdapter
extends RefCounted
## Reads the existing world-map dataset and adds military-only semantics by stable ID.
## It never owns geometry, city records, or a second world map.

const OVERLAY_PATH: String = "res://data/world_map/strategic_military_overlay.json"
const MODE_ROAD: String = "road"
const MODE_RAIL: String = "rail"
const MODE_SHIPPING: String = "shipping"

var errors: Array[String] = []
var cities: Dictionary = {}
var countries: Dictionary = {}
var regions: Dictionary = {}
var ports: Dictionary = {}
var links: Dictionary = {}
var links_by_city: Dictionary = {}
var terrain_profiles: Dictionary = {}
var transport_profiles: Dictionary = {}
var supply_rules: Dictionary = {}
var battle_rules: Dictionary = {}
var region_overlays: Dictionary = {}
var country_overlays: Dictionary = {}
var city_overlays: Dictionary = {}


func load_existing_map() -> bool:
	errors.clear()
	_clear_runtime_indexes()
	var source := PrototypeV2Data.new()
	if not source.load_all():
		errors.append_array(source.errors)
		return false
	if not _load_base_documents(source):
		return false
	if not _load_overlay():
		return false
	_build_network()
	return errors.is_empty() and not cities.is_empty() and not links.is_empty()


func get_city_ids() -> Array[String]:
	return _sorted_string_keys(cities)


func get_region_ids() -> Array[String]:
	var ids: Array[String] = []
	for city_id: String in get_city_ids():
		var region_id: String = get_region_id_for_city(city_id)
		if not region_id.is_empty() and not ids.has(region_id):
			ids.append(region_id)
	ids.sort()
	return ids


func has_city(city_id: String) -> bool:
	return cities.has(city_id)


func has_country(country_id: String) -> bool:
	return countries.has(country_id)


func has_region(region_id: String) -> bool:
	return get_region_ids().has(region_id)


func get_city(city_id: String) -> Dictionary:
	return _duplicate_dictionary(cities.get(city_id, {}))


func get_region_id_for_city(city_id: String) -> String:
	var city: Dictionary = cities.get(city_id, {}) as Dictionary
	if city.is_empty():
		return ""
	var parent_region_id: String = str(city.get("parent_region_id", ""))
	if not parent_region_id.is_empty() and regions.has(parent_region_id):
		return parent_region_id
	var country_id: String = str(city.get("parent_country_id", ""))
	return country_id if countries.has(country_id) else ""


func get_city_ids_for_region(region_id: String) -> Array[String]:
	var ids: Array[String] = []
	for city_id: String in get_city_ids():
		if get_region_id_for_city(city_id) == region_id:
			ids.append(city_id)
	return ids


func get_port_ids_for_city(city_id: String) -> Array[String]:
	var result: Array[String] = []
	for port_id: String in _sorted_string_keys(ports):
		var port: Dictionary = ports[port_id] as Dictionary
		if str(port.get("city_id", "")) == city_id:
			result.append(port_id)
	return result


func get_initial_controller(region_id: String) -> String:
	var overlay: Dictionary = _overlay_for_region(region_id)
	var configured: String = str(overlay.get("initial_controller_id", ""))
	if not configured.is_empty() and has_country(configured):
		return configured
	if regions.has(region_id):
		return str((regions[region_id] as Dictionary).get("parent_country_id", ""))
	return region_id if has_country(region_id) else ""


func get_initial_garrison(region_id: String) -> int:
	var overlay: Dictionary = _overlay_for_region(region_id)
	return maxi(0, int(overlay.get("initial_garrison_personnel", 0)))


func get_region_report(region_id: String, controls: Dictionary = {}) -> Dictionary:
	if not has_region(region_id):
		return {}
	var overlay: Dictionary = _overlay_for_region(region_id)
	var terrain_id: String = str(overlay.get("terrain_id", "plains"))
	var terrain: Dictionary = _duplicate_dictionary(terrain_profiles.get(terrain_id, {}))
	var city_summaries: Array[Dictionary] = []
	for city_id: String in get_city_ids_for_region(region_id):
		city_summaries.append(_city_military_view(city_id))
	var transport_ids: Array[String] = []
	var road_ids: Array[String] = []
	var rail_ids: Array[String] = []
	var shipping_ids: Array[String] = []
	var port_ids: Array[String] = []
	for link_id: String in _sorted_string_keys(links):
		var link: Dictionary = links[link_id] as Dictionary
		if not get_city_ids_for_region(region_id).has(str(link.get("from_city_id", ""))) \
		and not get_city_ids_for_region(region_id).has(str(link.get("to_city_id", ""))):
			continue
		transport_ids.append(link_id)
		match str(link.get("mode", "")):
			MODE_ROAD:
				road_ids.append(link_id)
			MODE_RAIL:
				rail_ids.append(link_id)
			MODE_SHIPPING:
				shipping_ids.append(link_id)
	for port_id: String in _sorted_string_keys(ports):
		var port: Dictionary = ports[port_id] as Dictionary
		if get_region_id_for_city(str(port.get("city_id", ""))) == region_id:
			port_ids.append(port_id)
	var controller_id: String = str(controls.get(region_id, get_initial_controller(region_id)))
	var country_name: String = _country_name(controller_id)
	return {
		"region_id": region_id,
		"name": _region_name(region_id),
		"region_kind": "macro_region" if regions.has(region_id) else "country_fallback",
		"terrain_id": terrain_id,
		"terrain": terrain,
		"city_ids": get_city_ids_for_region(region_id),
		"cities": city_summaries,
		"transport_link_ids": transport_ids,
		"road_link_ids": road_ids,
		"rail_link_ids": rail_ids,
		"shipping_link_ids": shipping_ids,
		"port_ids": port_ids,
		"resources": DataRecordUtils.to_string_array(overlay.get("resources", [])),
		"strategic_value": clampf(float(overlay.get("strategic_value", 0.5)), 0.0, 1.0),
		"controller_country_id": controller_id,
		"controller_name": country_name,
		"initial_garrison_personnel": get_initial_garrison(region_id),
	}


func get_link(link_id: String) -> Dictionary:
	return _duplicate_dictionary(links.get(link_id, {}))


func get_all_links() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for link_id: String in _sorted_string_keys(links):
		result.append(get_link(link_id))
	return result


func find_route(
	origin_city_id: String,
	destination_city_id: String,
	allowed_modes: Array[String] = [],
	controller_country_id: String = "",
	controls: Dictionary = {},
	allow_enemy_destination: bool = false
) -> Dictionary:
	if not has_city(origin_city_id) or not has_city(destination_city_id):
		return _unreachable_route("未知的起点或终点城市。")
	if origin_city_id == destination_city_id:
		return {
			"reachable": true,
			"origin_city_id": origin_city_id,
			"destination_city_id": destination_city_id,
			"city_ids": [origin_city_id],
			"link_ids": [],
			"links": [],
			"region_ids": [get_region_id_for_city(origin_city_id)],
			"total_distance_km": 0.0,
			"duration_hours": 0,
			"supply_capacity_per_day": 0.0,
			"reliability": 1.0,
			"capacity_personnel": 0,
			"mode_sequence": [],
		}
	var distances: Dictionary = {origin_city_id: 0.0}
	var previous_city: Dictionary = {}
	var previous_link: Dictionary = {}
	var pending: Array[String] = [origin_city_id]
	while not pending.is_empty():
		var current_city_id: String = _take_lowest_cost_city(pending, distances)
		pending.erase(current_city_id)
		if current_city_id == destination_city_id:
			break
		var current_city_links: Dictionary = links_by_city.get(current_city_id, {}) as Dictionary
		for link_id: String in _sorted_string_keys(current_city_links):
			var link: Dictionary = links[link_id] as Dictionary
			var mode: String = str(link.get("mode", ""))
			if not allowed_modes.is_empty() and not allowed_modes.has(mode):
				continue
			var next_city_id: String = _other_city(link, current_city_id)
			if next_city_id.is_empty() or not _route_edge_allowed(
				current_city_id,
				next_city_id,
				destination_city_id,
				controller_country_id,
				controls,
				allow_enemy_destination
			):
				continue
			var movement_hours: float = float(link.get("movement_hours", 0.0))
			var candidate_cost: float = float(distances[current_city_id]) + movement_hours
			if not distances.has(next_city_id) or candidate_cost < float(distances[next_city_id]):
				distances[next_city_id] = candidate_cost
				previous_city[next_city_id] = current_city_id
				previous_link[next_city_id] = link_id
				if not pending.has(next_city_id):
					pending.append(next_city_id)
	if not distances.has(destination_city_id):
		return _unreachable_route("现有道路、铁路和港口航线无法连通该起终点。")
	return _build_route_result(
		origin_city_id,
		destination_city_id,
		previous_city,
		previous_link,
		distances
	)


func get_route_capacity_per_day(route: Dictionary) -> float:
	if not bool(route.get("reachable", false)):
		return 0.0
	var link_list: Array = route.get("links", []) as Array
	if link_list.is_empty():
		return 0.0
	var capacity: float = INF
	for raw_link: Variant in link_list:
		var link: Dictionary = raw_link as Dictionary
		var terrain: Dictionary = get_region_terrain(get_region_id_for_city(str(link.get("to_city_id", ""))))
		var terrain_factor: float = clampf(float(terrain.get("supply_factor", 1.0)), 0.05, 2.0)
		capacity = minf(
			capacity,
			float(link.get("supply_capacity_per_day", 0.0))
			* float(link.get("reliability", 0.0))
			* terrain_factor
		)
	return 0.0 if is_inf(capacity) else maxf(0.0, capacity)


func get_region_terrain(region_id: String) -> Dictionary:
	var overlay: Dictionary = _overlay_for_region(region_id)
	var terrain_id: String = str(overlay.get("terrain_id", "plains"))
	return _duplicate_dictionary(terrain_profiles.get(terrain_id, {}))


func get_city_defense_factor(city_id: String) -> float:
	var overlay: Dictionary = city_overlays.get(city_id, {}) as Dictionary
	return clampf(float(overlay.get("defense_factor", 1.0)), 0.5, 2.5)


func get_city_strategic_value(city_id: String) -> float:
	var overlay: Dictionary = city_overlays.get(city_id, {}) as Dictionary
	return clampf(float(overlay.get("strategic_value", 0.4)), 0.0, 1.0)


func get_overlay_rules() -> Dictionary:
	return {
		"supply": supply_rules.duplicate(true),
		"battle": battle_rules.duplicate(true),
	}


func _load_base_documents(source: PrototypeV2Data) -> bool:
	var country_document: Dictionary = source.get_document("countries")
	for raw_country: Variant in country_document.get("countries", []) as Array:
		if raw_country is Dictionary:
			var country: Dictionary = (raw_country as Dictionary).duplicate(true)
			var id: String = str(country.get("id", country.get("stable_id", "")))
			if not id.is_empty():
				countries[id] = country
	var region_document: Dictionary = source.get_document("regions")
	for raw_region: Variant in region_document.get("regions", []) as Array:
		if raw_region is Dictionary:
			var region: Dictionary = (raw_region as Dictionary).duplicate(true)
			var region_id: String = str(region.get("id", region.get("stable_id", "")))
			if not region_id.is_empty():
				regions[region_id] = region
	var city_document: Dictionary = source.get_document("cities")
	for raw_city: Variant in city_document.get("cities", []) as Array:
		if raw_city is Dictionary:
			var city: Dictionary = (raw_city as Dictionary).duplicate(true)
			var city_id: String = str(city.get("id", ""))
			if not city_id.is_empty():
				cities[city_id] = city
	var port_document: Dictionary = source.get_document("ports")
	for raw_port: Variant in port_document.get("ports", []) as Array:
		if raw_port is Dictionary:
			var port: Dictionary = (raw_port as Dictionary).duplicate(true)
			var port_id: String = str(port.get("id", ""))
			if not port_id.is_empty():
				ports[port_id] = port
	if cities.is_empty() or countries.is_empty():
		errors.append("existing world-map cities or countries are empty")
	return errors.is_empty()


func _load_overlay() -> bool:
	if not FileAccess.file_exists(OVERLAY_PATH):
		errors.append("missing military semantics overlay: %s" % OVERLAY_PATH)
		return false
	var file := FileAccess.open(OVERLAY_PATH, FileAccess.READ)
	if file == null:
		errors.append("cannot read military semantics overlay")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("military semantics overlay must be a JSON object")
		return false
	var document: Dictionary = parsed as Dictionary
	if int(document.get("schema_version", -1)) != 1:
		errors.append("unsupported military semantics overlay schema")
		return false
	for raw_profile: Variant in document.get("terrain_profiles", []) as Array:
		if raw_profile is Dictionary:
			var profile: Dictionary = raw_profile as Dictionary
			terrain_profiles[str(profile.get("id", ""))] = profile.duplicate(true)
	for raw_profile: Variant in document.get("transport_profiles", []) as Array:
		if raw_profile is Dictionary:
			var profile: Dictionary = raw_profile as Dictionary
			transport_profiles[str(profile.get("mode", ""))] = profile.duplicate(true)
	supply_rules = _dictionary_or_empty(document.get("supply_rules", {}))
	battle_rules = _dictionary_or_empty(document.get("battle_rules", {}))
	for raw_overlay: Variant in document.get("region_overlays", []) as Array:
		if raw_overlay is Dictionary:
			var overlay: Dictionary = raw_overlay as Dictionary
			region_overlays[str(overlay.get("region_id", ""))] = overlay.duplicate(true)
	for raw_overlay: Variant in document.get("country_overlays", []) as Array:
		if raw_overlay is Dictionary:
			var overlay: Dictionary = raw_overlay as Dictionary
			country_overlays[str(overlay.get("country_id", ""))] = overlay.duplicate(true)
	for raw_overlay: Variant in document.get("city_overlays", []) as Array:
		if raw_overlay is Dictionary:
			var overlay: Dictionary = raw_overlay as Dictionary
			city_overlays[str(overlay.get("city_id", ""))] = overlay.duplicate(true)
	return not terrain_profiles.is_empty() and not transport_profiles.is_empty()


func _build_network() -> void:
	var source := PrototypeV2Data.new()
	if not source.load_all():
		return
	for raw_segment: Variant in source.get_document("road_segments").get("segments", []) as Array:
		_add_transport_segment(raw_segment as Dictionary, MODE_ROAD)
	for raw_segment: Variant in source.get_document("rail_segments").get("segments", []) as Array:
		_add_transport_segment(raw_segment as Dictionary, MODE_RAIL)
	for raw_route: Variant in source.get_document("shipping_routes").get("routes", []) as Array:
		_add_shipping_route(raw_route as Dictionary)


func _add_transport_segment(segment: Dictionary, mode: String) -> void:
	var from_city_id: String = str(segment.get("from_city_id", ""))
	var to_city_id: String = str(segment.get("to_city_id", ""))
	if not has_city(from_city_id) or not has_city(to_city_id):
		errors.append("%s segment references an unknown city" % mode)
		return
	var profile: Dictionary = transport_profiles.get(mode, {}) as Dictionary
	var distance_km: float = _city_distance_km(from_city_id, to_city_id)
	_add_link(
		str(segment.get("id", "")),
		from_city_id,
		to_city_id,
		mode,
		distance_km,
		profile
	)


func _add_shipping_route(route: Dictionary) -> void:
	var from_port: Dictionary = ports.get(str(route.get("from_port_id", "")), {}) as Dictionary
	var to_port: Dictionary = ports.get(str(route.get("to_port_id", "")), {}) as Dictionary
	var from_city_id: String = str(from_port.get("city_id", ""))
	var to_city_id: String = str(to_port.get("city_id", ""))
	if not has_city(from_city_id) or not has_city(to_city_id):
		errors.append("shipping route references an unknown port city")
		return
	var waypoints: Array = route.get("waypoints_lon_lat", []) as Array
	var distance_km: float = _waypoint_distance_km(waypoints)
	_add_link(
		str(route.get("id", "")),
		from_city_id,
		to_city_id,
		MODE_SHIPPING,
		distance_km,
		transport_profiles.get(MODE_SHIPPING, {}) as Dictionary
	)


func _add_link(
	link_id: String,
	from_city_id: String,
	to_city_id: String,
	mode: String,
	distance_km: float,
	profile: Dictionary
) -> void:
	if link_id.is_empty() or links.has(link_id):
		errors.append("duplicate or empty transport link ID: %s" % link_id)
		return
	var terrain: Dictionary = get_region_terrain(get_region_id_for_city(to_city_id))
	var terrain_factor: float = clampf(float(terrain.get("movement_factor", 1.0)), 0.1, 2.0)
	var speed: float = maxf(float(profile.get("movement_speed_km_per_day", 1.0)), 1.0)
	var base_hours: float = distance_km / speed * 24.0 / terrain_factor
	var movement_hours: int = maxi(
		int(profile.get("minimum_movement_hours", 12)),
		ceili(base_hours)
	)
	var link: Dictionary = {
		"id": link_id,
		"from_city_id": from_city_id,
		"to_city_id": to_city_id,
		"mode": mode,
		"distance_km": maxf(0.1, distance_km),
		"movement_hours": movement_hours,
		"supply_capacity_per_day": maxf(0.0, float(profile.get("supply_capacity_per_day", 0.0))),
		"capacity_personnel": maxi(1, int(profile.get("capacity_personnel", 1))),
		"reliability": clampf(float(profile.get("reliability", 0.0)), 0.0, 1.0),
	}
	links[link_id] = link
	if not links_by_city.has(from_city_id):
		links_by_city[from_city_id] = {}
	if not links_by_city.has(to_city_id):
		links_by_city[to_city_id] = {}
	(links_by_city[from_city_id] as Dictionary)[link_id] = true
	(links_by_city[to_city_id] as Dictionary)[link_id] = true


func _route_edge_allowed(
	current_city_id: String,
	next_city_id: String,
	destination_city_id: String,
	controller_country_id: String,
	controls: Dictionary,
	allow_enemy_destination: bool
) -> bool:
	if controller_country_id.is_empty():
		return true
	var current_region_id: String = get_region_id_for_city(current_city_id)
	var next_region_id: String = get_region_id_for_city(next_city_id)
	var current_controller: String = str(
		controls.get(current_region_id, get_initial_controller(current_region_id))
	)
	var next_controller: String = str(
		controls.get(next_region_id, get_initial_controller(next_region_id))
	)
	if current_controller != controller_country_id:
		return false
	if next_controller == controller_country_id:
		return true
	return allow_enemy_destination and next_city_id == destination_city_id


func _build_route_result(
	origin_city_id: String,
	destination_city_id: String,
	previous_city: Dictionary,
	previous_link: Dictionary,
	distances: Dictionary
) -> Dictionary:
	var reversed_city_ids: Array[String] = []
	var reversed_link_ids: Array[String] = []
	var cursor: String = destination_city_id
	while true:
		reversed_city_ids.append(cursor)
		if cursor == origin_city_id:
			break
		if not previous_city.has(cursor) or not previous_link.has(cursor):
			return _unreachable_route("路径回溯失败。")
		reversed_link_ids.append(str(previous_link[cursor]))
		cursor = str(previous_city[cursor])
	reversed_city_ids.reverse()
	reversed_link_ids.reverse()
	var route_links: Array[Dictionary] = []
	var total_distance_km: float = 0.0
	var reliability: float = 1.0
	var capacity_personnel: int = 2147483647
	var modes: Array[String] = []
	for link_id: String in reversed_link_ids:
		var link: Dictionary = get_link(link_id)
		route_links.append(link)
		total_distance_km += float(link.get("distance_km", 0.0))
		reliability *= clampf(float(link.get("reliability", 1.0)), 0.0, 1.0)
		capacity_personnel = mini(capacity_personnel, maxi(1, int(link.get("capacity_personnel", 1))))
		var mode: String = str(link.get("mode", ""))
		if not modes.has(mode):
			modes.append(mode)
	var region_ids: Array[String] = []
	for city_id: String in reversed_city_ids:
		var region_id: String = get_region_id_for_city(city_id)
		if not region_ids.has(region_id):
			region_ids.append(region_id)
	return {
		"reachable": true,
		"origin_city_id": origin_city_id,
		"destination_city_id": destination_city_id,
		"city_ids": reversed_city_ids,
		"link_ids": reversed_link_ids,
		"links": route_links,
		"region_ids": region_ids,
		"total_distance_km": total_distance_km,
		"duration_hours": int(distances[destination_city_id]),
		"supply_capacity_per_day": get_route_capacity_per_day({"reachable": true, "links": route_links}),
		"reliability": reliability,
		"capacity_personnel": capacity_personnel if capacity_personnel < 2147483647 else 0,
		"mode_sequence": modes,
	}


func _take_lowest_cost_city(pending: Array[String], distances: Dictionary) -> String:
	var selected: String = pending[0]
	var selected_cost: float = float(distances.get(selected, INF))
	for city_id: String in pending:
		var candidate_cost: float = float(distances.get(city_id, INF))
		if candidate_cost < selected_cost or (is_equal_approx(candidate_cost, selected_cost) and city_id < selected):
			selected = city_id
			selected_cost = candidate_cost
	return selected


func _other_city(link: Dictionary, city_id: String) -> String:
	var from_city_id: String = str(link.get("from_city_id", ""))
	var to_city_id: String = str(link.get("to_city_id", ""))
	return to_city_id if from_city_id == city_id else from_city_id if to_city_id == city_id else ""


func _city_military_view(city_id: String) -> Dictionary:
	var city: Dictionary = get_city(city_id)
	var overlay: Dictionary = city_overlays.get(city_id, {}) as Dictionary
	return {
		"city_id": city_id,
		"name": str(city.get("name", city_id)),
		"role": str(overlay.get("role", "settlement")),
		"strategic_value": get_city_strategic_value(city_id),
		"defense_factor": get_city_defense_factor(city_id),
		"port_ids": get_port_ids_for_city(city_id),
	}


func _overlay_for_region(region_id: String) -> Dictionary:
	if region_overlays.has(region_id):
		return region_overlays[region_id] as Dictionary
	if country_overlays.has(region_id):
		return country_overlays[region_id] as Dictionary
	return {}


func _region_name(region_id: String) -> String:
	if regions.has(region_id):
		return str((regions[region_id] as Dictionary).get("name", region_id))
	if countries.has(region_id):
		var country: Dictionary = countries[region_id] as Dictionary
		return str(country.get("display_name_zh", country.get("name", region_id)))
	return region_id


func _country_name(country_id: String) -> String:
	var country: Dictionary = countries.get(country_id, {}) as Dictionary
	return str(country.get("display_name_zh", country.get("name", country_id)))


func _city_distance_km(first_city_id: String, second_city_id: String) -> float:
	var first: Dictionary = cities[first_city_id] as Dictionary
	var second: Dictionary = cities[second_city_id] as Dictionary
	return _great_circle_km(
		(first.get("lon_lat", [0.0, 0.0]) as Array),
		(second.get("lon_lat", [0.0, 0.0]) as Array)
	)


func _waypoint_distance_km(waypoints: Array) -> float:
	if waypoints.size() < 2:
		return 0.1
	var distance_km: float = 0.0
	for index: int in range(waypoints.size() - 1):
		distance_km += _great_circle_km(waypoints[index] as Array, waypoints[index + 1] as Array)
	return maxf(0.1, distance_km)


func _great_circle_km(first: Array, second: Array) -> float:
	if first.size() < 2 or second.size() < 2:
		return 0.1
	var latitude_a: float = deg_to_rad(float(first[1]))
	var latitude_b: float = deg_to_rad(float(second[1]))
	var delta_latitude: float = latitude_b - latitude_a
	var delta_longitude: float = deg_to_rad(float(second[0]) - float(first[0]))
	var haversine: float = sin(delta_latitude * 0.5) ** 2.0 + cos(latitude_a) * cos(latitude_b) * sin(delta_longitude * 0.5) ** 2.0
	return 6371.0 * 2.0 * asin(sqrt(clampf(haversine, 0.0, 1.0)))


func _clear_runtime_indexes() -> void:
	cities.clear()
	countries.clear()
	regions.clear()
	ports.clear()
	links.clear()
	links_by_city.clear()
	terrain_profiles.clear()
	transport_profiles.clear()
	supply_rules.clear()
	battle_rules.clear()
	region_overlays.clear()
	country_overlays.clear()
	city_overlays.clear()


func _unreachable_route(reason: String) -> Dictionary:
	return {
		"reachable": false,
		"reason": reason,
		"city_ids": [],
		"link_ids": [],
		"links": [],
		"region_ids": [],
		"total_distance_km": 0.0,
		"duration_hours": 0,
		"supply_capacity_per_day": 0.0,
		"reliability": 0.0,
		"mode_sequence": [],
	}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _duplicate_dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for raw_key: Variant in source.keys():
		keys.append(str(raw_key))
	keys.sort()
	return keys
