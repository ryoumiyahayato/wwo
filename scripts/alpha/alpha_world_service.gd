class_name AlphaWorldService
extends RefCounted
## Owns Alpha country, region, functional cell, city and route runtime state.

var countries: Dictionary = {}
var regions: Dictionary = {}
var cells: Dictionary = {}
var cities: Dictionary = {}
var locations: Dictionary = {}
var routes: Dictionary = {}
var topology_report: Dictionary = {}
var initialization_error: String = ""
var revision: int = 0


func configure(data_set: CoreDataSet, config: AlphaConfig) -> bool:
	countries.clear()
	regions.clear()
	cells.clear()
	cities.clear()
	locations.clear()
	routes.clear()
	initialization_error = ""
	if data_set == null or config == null or not config.errors.is_empty():
		initialization_error = "Alpha 世界依赖不可用"
		return false
	for raw_profile: Variant in config.country_profiles():
		var profile: Dictionary = (raw_profile as Dictionary).duplicate(true)
		var country_id: String = str(profile.get("country_id", ""))
		if not data_set.countries.has(country_id):
			initialization_error = "Alpha 国家引用未知核心 ID：%s" % country_id
			return false
		profile["region_ids"] = (
			data_set.countries[country_id] as CountryData
		).region_ids.duplicate()
		countries[country_id] = profile
	for raw_profile: Variant in config.region_profiles():
		var profile: Dictionary = (raw_profile as Dictionary).duplicate(true)
		var region_id: String = str(profile.get("region_id", ""))
		var core_region: RegionData = data_set.regions.get(region_id) as RegionData
		if core_region == null:
			initialization_error = "Alpha 地区引用未知核心 ID：%s" % region_id
			return false
		profile["country_id"] = core_region.de_jure_country_id
		profile["organization_ids"] = core_region.organization_ids.duplicate()
		profile["current_economic_state"] = "stable"
		profile["employment_index"] = 100
		profile["price_index"] = 100
		profile["policy_effects"] = {}
		regions[region_id] = profile
	for raw_unit: Variant in data_set.control_units.values():
		var unit: ControlUnitData = raw_unit as ControlUnitData
		var region: Dictionary = regions.get(unit.region_id, {}) as Dictionary
		if region.is_empty():
			initialization_error = "控制单元缺少 Alpha 地区：%s" % unit.id
			return false
		cells[unit.id] = _build_cell(unit, region)
	for raw_city: Variant in config.cities():
		var city: Dictionary = (raw_city as Dictionary).duplicate(true)
		var city_id: String = str(city.get("city_id", ""))
		city["location_ids"] = []
		cities[city_id] = city
	for raw_location: Variant in config.locations:
		var location: Dictionary = (raw_location as Dictionary).duplicate(true)
		var location_id: String = str(location.get("location_id", ""))
		locations[location_id] = location
		var city_id: String = str(location.get("city_id", ""))
		if cities.has(city_id):
			(cities[city_id]["location_ids"] as Array).append(location_id)
	for raw_route: Variant in config.transport_edges:
		var route: Dictionary = (raw_route as Dictionary).duplicate(true)
		routes[str(route.get("edge_id", ""))] = route
	topology_report = AlphaTopologyService.new().validate(
		cells, config.transport_edges
	)
	if not bool(topology_report.get("success", false)):
		initialization_error = "; ".join(
			topology_report.get("errors", []) as Array[String]
		)
		return false
	revision = 1
	return true


func country_view(country_id: String) -> Dictionary:
	var value: Variant = countries.get(country_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func region_view(region_id: String) -> Dictionary:
	var value: Variant = regions.get(region_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func city_view(city_id: String) -> Dictionary:
	var value: Variant = cities.get(city_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func cell_view(cell_id: String) -> Dictionary:
	var value: Variant = cells.get(cell_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func apply_region_effects(region_id: String, effects: Dictionary) -> bool:
	if not regions.has(region_id):
		return false
	var region: Dictionary = regions[region_id] as Dictionary
	var applied: Dictionary = region.get("policy_effects", {}) as Dictionary
	for raw_key: Variant in effects.keys():
		var key: String = str(raw_key)
		applied[key] = int(applied.get(key, 0)) + int(effects[raw_key])
		match key:
			"wage_index":
				region["wage_index"] = maxi(40, int(region["wage_index"]) + int(effects[raw_key]))
			"employment_index":
				region["employment_index"] = maxi(
					20, int(region["employment_index"]) + int(effects[raw_key])
				)
			"transport_cost_index":
				region["transport_cost_index"] = int(
					region.get("transport_cost_index", 100)
				) + int(effects[raw_key])
			_:
				pass
	region["policy_effects"] = applied
	regions[region_id] = region
	revision += 1
	return true


func get_persistent_state() -> Dictionary:
	return {
		"countries": countries.duplicate(true),
		"regions": regions.duplicate(true),
		"cells": cells.duplicate(true),
		"revision": revision,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("countries", {}) is Dictionary
		or not state.get("regions", {}) is Dictionary
		or not state.get("cells", {}) is Dictionary
	):
		return false
	var restored_countries: Dictionary = state["countries"] as Dictionary
	var restored_regions: Dictionary = state["regions"] as Dictionary
	var restored_cells: Dictionary = state["cells"] as Dictionary
	if (
		restored_countries.size() != countries.size()
		or restored_regions.size() != regions.size()
		or restored_cells.size() != cells.size()
	):
		return false
	for raw_cell_id: Variant in restored_cells.keys():
		var cell_id: String = str(raw_cell_id)
		if (
			not cells.has(cell_id)
			or not restored_cells[cell_id] is Dictionary
			or not restored_regions.has(
				str((restored_cells[cell_id] as Dictionary).get("region_id", ""))
			)
		):
			return false
	countries = restored_countries.duplicate(true)
	regions = restored_regions.duplicate(true)
	cells = restored_cells.duplicate(true)
	revision = maxi(1, int(state.get("revision", 1)))
	return true


func counts() -> Dictionary:
	return {
		"countries": countries.size(),
		"regions": regions.size(),
		"cells": cells.size(),
		"cities": cities.size(),
		"locations": locations.size(),
		"routes": routes.size(),
	}


func _build_cell(unit: ControlUnitData, region: Dictionary) -> Dictionary:
	var x: int = unit.grid_x
	var y: int = unit.grid_y
	var supply: Dictionary = region.get("supply", {}) as Dictionary
	var supply_keys: Array[String] = []
	for raw_key: Variant in supply.keys():
		supply_keys.append(str(raw_key))
	supply_keys.sort()
	var resource_id: String = supply_keys[(x + y) % supply_keys.size()]
	var land_use: String = "urban" if not unit.city_name.is_empty() else (
		"industrial" if (x + y) % 3 == 0
		else "agricultural" if (x + y) % 3 == 1
		else "mixed"
	)
	var industries: Array = region.get("industries", []) as Array
	var classes: Array = region.get("classes", []) as Array
	return {
		"cell_id": unit.id,
		"country_id": unit.de_jure_country_id,
		"region_id": unit.region_id,
		"grid_x": x,
		"grid_y": y,
		"polygon": [
			[float(x), float(y)],
			[float(x + 1), float(y)],
			[float(x + 1), float(y + 1)],
			[float(x), float(y + 1)],
			[float(x), float(y)],
		],
		"land_use_or_terrain": land_use,
		"population": maxi(1000, int(region.get("population", 0)) / 10),
		"major_class_or_occupation": str(classes[(x + y) % classes.size()]),
		"major_industry": str(industries[(x * 2 + y) % industries.size()]),
		"wage_index": int(region.get("wage_index", 100)) + (x % 3) - 1,
		"living_cost_index": int(region.get("living_cost_index", 100)) + (y % 3) - 1,
		"resource_condition": {
			"good_id": resource_id,
			"availability": int(supply.get(resource_id, 50)) + ((x + y) % 5) - 2,
		},
		"neighbor_ids": unit.neighbor_ids.duplicate(),
		"transport_connections": unit.neighbor_ids.duplicate(),
		"infrastructure": {
			"state": unit.infrastructure_state,
			"rail": bool(not unit.railroad_neighbor_ids.is_empty()),
			"index": int(50 + unit.control_strength * 45.0),
		},
		"security_or_political_environment": {
			"contested_level": unit.contested_level,
			"social_support": unit.social_support,
			"controller_country_id": unit.controller_country_id,
		},
		"major_organization_influence": (
			"organization:loran_government"
			if unit.de_jure_country_id == "country:loran_federation"
			else "organization:vesta_government"
		),
		"current_economic_state": "urban_demand" if land_use == "urban" else "stable",
		"formal_behavior_effect": (
			"employment" if land_use == "urban"
			else "goods_price" if land_use == "agricultural"
			else "business_location" if land_use == "industrial"
			else "transport"
		),
	}
