class_name MapControlService
extends RefCounted
## Owns mutable military control and the incrementally maintained frontline edge set.

signal control_unit_changed(unit_id: String)
signal frontlines_changed()

const STAGE_STABLE: String = "stable"
const STAGE_WEAKENING: String = "weakening"
const STAGE_CONTESTED: String = "contested"
const STAGE_ENEMY_OCCUPATION: String = "enemy_occupation"
const STAGE_CONSOLIDATING: String = "consolidating"

var data_set: CoreDataSet
var rules: MapRulesConfig

var _frontline_edges: Dictionary = {}
var _units_by_grid_position: Dictionary = {}


func _init(source_data_set: CoreDataSet, source_rules: MapRulesConfig) -> void:
	data_set = source_data_set
	rules = source_rules
	_index_grid_positions()
	_rebuild_all_frontlines()


func get_unit(unit_id: String) -> ControlUnitData:
	return data_set.control_units.get(unit_id) as ControlUnitData


func get_unit_at(grid_x: int, grid_y: int) -> ControlUnitData:
	return _units_by_grid_position.get(_grid_key(grid_x, grid_y)) as ControlUnitData


func get_sorted_unit_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in data_set.control_units:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func get_country_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in data_set.countries:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func get_other_country_id(country_id: String) -> String:
	for candidate: String in get_country_ids():
		if candidate != country_id:
			return candidate
	return ""


func set_control_state(
	unit_id: String,
	controller_country_id: String,
	control_strength: float,
	contested_level: float
) -> bool:
	var unit: ControlUnitData = get_unit(unit_id)
	if unit == null or not data_set.countries.has(controller_country_id):
		return false
	var controller_changed: bool = unit.controller_country_id != controller_country_id
	unit.controller_country_id = controller_country_id
	unit.control_strength = clampf(control_strength, 0.0, 1.0)
	unit.contested_level = clampf(contested_level, 0.0, 1.0)
	if controller_changed:
		unit.enemy_pressure = 0.0
		_update_frontlines_for_unit(unit)
	control_unit_changed.emit(unit.id)
	return true


func is_valid_control_support_target(
	unit_id: String,
	supporting_country_id: String
) -> bool:
	var unit: ControlUnitData = get_unit(unit_id)
	if unit == null or not data_set.countries.has(supporting_country_id):
		return false
	var adjacent_to_supporter: bool = false
	var adjacent_to_enemy: bool = false
	for neighbor_id: String in unit.neighbor_ids:
		var neighbor: ControlUnitData = get_unit(neighbor_id)
		if neighbor == null:
			continue
		if neighbor.controller_country_id == supporting_country_id:
			adjacent_to_supporter = true
		else:
			adjacent_to_enemy = true
	if unit.controller_country_id != supporting_country_id:
		return adjacent_to_supporter
	return adjacent_to_enemy and (
		unit.control_strength < 1.0
		or unit.contested_level > 0.0
		or unit.enemy_pressure > 0.0
	)


func apply_frontline_control_pressure(
	unit_id: String,
	attacking_country_id: String,
	intensity: float = 1.0
) -> bool:
	if not is_valid_control_support_target(unit_id, attacking_country_id):
		return false
	return apply_control_pressure(unit_id, attacking_country_id, intensity)


func apply_control_pressure(
	unit_id: String,
	attacking_country_id: String,
	intensity: float = 1.0
) -> bool:
	var unit: ControlUnitData = get_unit(unit_id)
	if unit == null or not data_set.countries.has(attacking_country_id):
		return false
	var applied_intensity: float = clampf(intensity, 0.0, 1.0)
	if applied_intensity <= 0.0:
		return false
	if unit.controller_country_id == attacking_country_id:
		unit.control_strength = clampf(
			unit.control_strength + rules.pressure_strength_loss * applied_intensity,
			0.0,
			1.0
		)
		unit.contested_level = clampf(
			unit.contested_level - rules.pressure_contested_gain * applied_intensity,
			0.0,
			1.0
		)
		unit.enemy_pressure = clampf(
			unit.enemy_pressure - rules.pressure_enemy_gain * applied_intensity,
			0.0,
			1.0
		)
	else:
		unit.control_strength = clampf(
			unit.control_strength - rules.pressure_strength_loss * applied_intensity,
			0.0,
			1.0
		)
		unit.contested_level = clampf(
			unit.contested_level + rules.pressure_contested_gain * applied_intensity,
			0.0,
			1.0
		)
		unit.enemy_pressure = clampf(
			unit.enemy_pressure + rules.pressure_enemy_gain * applied_intensity,
			0.0,
			1.0
		)
		if (
			unit.control_strength <= rules.capture_strength_threshold
			and unit.contested_level >= rules.capture_contested_threshold
		):
			unit.controller_country_id = attacking_country_id
			unit.control_strength = rules.consolidation_strength
			unit.contested_level = minf(rules.contested_threshold * 0.5, 0.2)
			unit.enemy_pressure = 0.0
			_update_frontlines_for_unit(unit)
	control_unit_changed.emit(unit.id)
	return true


func get_control_stage(unit_id: String) -> String:
	var unit: ControlUnitData = get_unit(unit_id)
	if unit == null:
		return ""
	if unit.contested_level >= rules.contested_threshold:
		return STAGE_CONTESTED
	if unit.controller_country_id != unit.de_jure_country_id:
		return (
			STAGE_ENEMY_OCCUPATION
			if unit.control_strength < rules.weak_control_threshold
			else STAGE_CONSOLIDATING
		)
	if unit.control_strength < rules.weak_control_threshold:
		return STAGE_WEAKENING
	return STAGE_STABLE


func get_frontline_edges() -> Array[Dictionary]:
	var keys: Array[String] = []
	for raw_key: Variant in _frontline_edges:
		keys.append(str(raw_key))
	keys.sort()
	var edges: Array[Dictionary] = []
	for key: String in keys:
		edges.append((_frontline_edges[key] as Dictionary).duplicate(true))
	return edges


func get_frontline_edge_count_for_unit(unit_id: String) -> int:
	var count: int = 0
	for edge: Dictionary in get_frontline_edges():
		if edge["a"] == unit_id or edge["b"] == unit_id:
			count += 1
	return count


func is_surrounded(unit_id: String) -> bool:
	var unit: ControlUnitData = get_unit(unit_id)
	if unit == null or unit.neighbor_ids.is_empty() or unit.controller_country_id.is_empty():
		return false
	for neighbor_id: String in unit.neighbor_ids:
		var neighbor: ControlUnitData = get_unit(neighbor_id)
		if neighbor == null or neighbor.controller_country_id == unit.controller_country_id:
			return false
	return true


func get_region_summary(region_id: String) -> Dictionary:
	if not data_set.regions.has(region_id):
		return {}
	var region: RegionData = data_set.regions[region_id] as RegionData
	var unit_count: int = 0
	var controller_counts: Dictionary = {}
	var contested_total: float = 0.0
	var railroad_edge_keys: Dictionary = {}
	for unit_value: Variant in data_set.control_units.values():
		var unit: ControlUnitData = unit_value as ControlUnitData
		if unit.region_id != region_id:
			continue
		unit_count += 1
		controller_counts[unit.controller_country_id] = int(
			controller_counts.get(unit.controller_country_id, 0)
		) + 1
		contested_total += unit.contested_level
		for rail_neighbor_id: String in unit.railroad_neighbor_ids:
			railroad_edge_keys[_edge_key(unit.id, rail_neighbor_id)] = true
	var population_total: int = 0
	for population_id: String in region.population_group_ids:
		if data_set.population_groups.has(population_id):
			population_total += (
				data_set.population_groups[population_id] as PopulationGroupData
			).population_count
	var percentages: Dictionary = {}
	if unit_count > 0:
		for raw_country_id: Variant in controller_counts:
			percentages[str(raw_country_id)] = (
				float(controller_counts[raw_country_id]) / float(unit_count)
			)
	return {
		"region_id": region.id,
		"name": region.name,
		"de_jure_country_id": region.de_jure_country_id,
		"unit_count": unit_count,
		"control_percentages": percentages,
		"average_contested": contested_total / float(maxi(unit_count, 1)),
		"social_influence": region.social_influence.duplicate(true),
		"population_total": population_total,
		"railroad_connections": railroad_edge_keys.size(),
	}


func get_persistent_state() -> Dictionary:
	var regions: Dictionary = {}
	for raw_region: Variant in data_set.regions.values():
		var region: RegionData = raw_region as RegionData
		regions[region.id] = {"social_influence": region.social_influence.duplicate(true)}
	var units: Dictionary = {}
	for unit_id: String in get_sorted_unit_ids():
		var unit: ControlUnitData = get_unit(unit_id)
		units[unit_id] = {
			"controller_country_id": unit.controller_country_id,
			"control_strength": unit.control_strength,
			"contested_level": unit.contested_level,
			"enemy_pressure": unit.enemy_pressure,
		}
	return {"regions": regions, "control_units": units}


func restore_persistent_state(state: Dictionary) -> bool:
	var regions: Variant = state.get("regions", {})
	var units: Variant = state.get("control_units", {})
	if not regions is Dictionary or not units is Dictionary:
		return false
	if (regions as Dictionary).size() != data_set.regions.size() or (units as Dictionary).size() != data_set.control_units.size():
		return false
	var expected_country_ids: Array[String] = get_country_ids()
	for region_id: String in data_set.regions:
		if not (regions as Dictionary).has(region_id):
			return false
		var region_state: Variant = (regions as Dictionary)[region_id]
		if not region_state is Dictionary or not (region_state as Dictionary).get("social_influence", {}) is Dictionary:
			return false
		var influence: Dictionary = (region_state as Dictionary).get("social_influence", {}) as Dictionary
		if influence.size() != expected_country_ids.size():
			return false
		var influence_total: float = 0.0
		for country_id: String in expected_country_ids:
			if not influence.has(country_id):
				return false
			var value: float = float(influence[country_id])
			if value < 0.0 or value > 1.0:
				return false
			influence_total += value
		if not is_equal_approx(influence_total, 1.0):
			return false
	for unit_id: String in data_set.control_units:
		if not (units as Dictionary).has(unit_id):
			return false
		var unit_state: Variant = (units as Dictionary)[unit_id]
		if not unit_state is Dictionary:
			return false
		var controller_id: String = str((unit_state as Dictionary).get("controller_country_id", ""))
		var strength: float = float((unit_state as Dictionary).get("control_strength", -1.0))
		var contested: float = float((unit_state as Dictionary).get("contested_level", -1.0))
		var pressure: float = float((unit_state as Dictionary).get("enemy_pressure", -1.0))
		if not data_set.countries.has(controller_id) or strength < 0.0 or strength > 1.0 or contested < 0.0 or contested > 1.0 or pressure < 0.0 or pressure > 1.0:
			return false
	for region_id: String in data_set.regions:
		(data_set.regions[region_id] as RegionData).social_influence = (((regions as Dictionary)[region_id] as Dictionary)["social_influence"] as Dictionary).duplicate(true)
	for unit_id: String in data_set.control_units:
		var unit: ControlUnitData = get_unit(unit_id)
		var unit_state: Dictionary = (units as Dictionary)[unit_id] as Dictionary
		unit.controller_country_id = str(unit_state["controller_country_id"])
		unit.control_strength = float(unit_state["control_strength"])
		unit.contested_level = float(unit_state["contested_level"])
		unit.enemy_pressure = float(unit_state["enemy_pressure"])
	_rebuild_all_frontlines()
	frontlines_changed.emit()
	return true


func _index_grid_positions() -> void:
	_units_by_grid_position.clear()
	for unit_value: Variant in data_set.control_units.values():
		var unit: ControlUnitData = unit_value as ControlUnitData
		_units_by_grid_position[_grid_key(unit.grid_x, unit.grid_y)] = unit


func _rebuild_all_frontlines() -> void:
	_frontline_edges.clear()
	for unit_value: Variant in data_set.control_units.values():
		_update_frontlines_for_unit(unit_value as ControlUnitData, false)


func _update_frontlines_for_unit(unit: ControlUnitData, emit_signal: bool = true) -> void:
	var changed: bool = false
	for neighbor_id: String in unit.neighbor_ids:
		var neighbor: ControlUnitData = get_unit(neighbor_id)
		var key: String = _edge_key(unit.id, neighbor_id)
		var should_exist: bool = (
			neighbor != null
			and not unit.controller_country_id.is_empty()
			and not neighbor.controller_country_id.is_empty()
			and unit.controller_country_id != neighbor.controller_country_id
		)
		if should_exist and not _frontline_edges.has(key):
			var ordered_ids: PackedStringArray = _ordered_edge_ids(unit.id, neighbor_id)
			_frontline_edges[key] = {"a": ordered_ids[0], "b": ordered_ids[1]}
			changed = true
		elif not should_exist and _frontline_edges.erase(key):
			changed = true
	if changed and emit_signal:
		frontlines_changed.emit()


static func _edge_key(first_id: String, second_id: String) -> String:
	var ordered_ids: PackedStringArray = _ordered_edge_ids(first_id, second_id)
	return "%s|%s" % [ordered_ids[0], ordered_ids[1]]


static func _ordered_edge_ids(first_id: String, second_id: String) -> PackedStringArray:
	return (
		PackedStringArray([first_id, second_id])
		if first_id < second_id
		else PackedStringArray([second_id, first_id])
	)


static func _grid_key(grid_x: int, grid_y: int) -> String:
	return "%d,%d" % [grid_x, grid_y]
