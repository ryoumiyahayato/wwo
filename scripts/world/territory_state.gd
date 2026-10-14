class_name TerritoryState
extends RefCounted
## Sole current control owner for places and active land. Place IDs retain legacy semantics.

const SCHEMA_ID: String = "territory_state_v1"

signal controller_changed(territory_id: String)

var error: String = ""
var _controllers: Dictionary[String, String] = {}
var _land: LandTopology
var _politics: RuntimePoliticalEntityRegistry

func bind_land_scope(land: LandTopology, politics: RuntimePoliticalEntityRegistry) -> void:
	_land = land
	_politics = politics

func is_bound_to_land(land: LandTopology) -> bool:
	return _land == land

func _valid_land_controller(id: String, controller: String) -> bool:
	if not id.begins_with("territory_unit:"):
		return true
	return _land != null and _land.has_land(id) and _politics != null and (controller.is_empty() or _politics.has_entity(controller))

func can_split_land(id: String, first: String, second: String) -> bool:
	return _land != null and _land.has_land(id) and _controllers.has(id) and _valid_land_controller(id,_controllers[id]) and not _controllers.has(first) and not _controllers.has(second)

func commit_land_split(id: String, first: String, second: String) -> void:
	var inherited := _controllers[id]
	_controllers.erase(id)
	_controllers[first] = inherited
	_controllers[second] = inherited


func has_territory(territory_id: String) -> bool:
	return _controllers.has(territory_id)


func get_controller(territory_id: String) -> String:
	assert(_controllers.has(territory_id), "UNKNOWN TERRITORY ID: %s" % territory_id)
	return _controllers[territory_id]


func set_controller(territory_id: String, controller_id: String) -> bool:
	if not _controllers.has(territory_id):
		error = "UNKNOWN TERRITORY ID: %s" % territory_id
		push_error(error)
		return false
	if controller_id.is_empty():
		error = "UNKNOWN CONTROLLER for territory: %s" % territory_id
		push_error(error)
		return false
	if not _valid_land_controller(territory_id,controller_id):
		error = "INVALID LAND CONTROLLER: " + controller_id
		return false
	var changed := _controllers[territory_id] != controller_id
	_controllers[territory_id] = controller_id
	if changed: controller_changed.emit(territory_id)
	error = ""
	return true


func territory_ids() -> Array[String]:
	var ids: Array[String] = _controllers.keys()
	ids.sort()
	return ids


func snapshot() -> Dictionary:
	var controllers: Dictionary = {}
	for territory_id: String in territory_ids():
		controllers[territory_id] = _controllers[territory_id]
	return {"schema_id": SCHEMA_ID, "controllers": controllers}


func restore(value: Dictionary, expected_ids: Array[String], opening_controllers: Dictionary = {}) -> bool:
	error = ""
	if _land != null:
		for id: String in _land.land_ids():
			if not expected_ids.has(id):
				error = "MISSING LAND CONTROL SCOPE: " + id
				return false
	if value.size() != 2 or value.get("schema_id") != SCHEMA_ID or not value.get("controllers") is Dictionary:
		error = "INVALID TERRITORY SNAPSHOT: expected %s" % SCHEMA_ID
		push_error(error)
		return false
	var records: Dictionary = value["controllers"]
	var candidate: Dictionary[String, String] = {}
	for raw_id: Variant in records:
		if not raw_id is String or not expected_ids.has(raw_id):
			error = "UNKNOWN TERRITORY ID: %s" % str(raw_id)
			push_error(error)
			return false
		var controller: Variant = records[raw_id]
		if not controller is String or ((controller as String).is_empty() and not str(raw_id).begins_with("territory_unit:")) or not _valid_land_controller(str(raw_id),str(controller)):
			error = "UNKNOWN CONTROLLER for territory: %s" % str(raw_id)
			push_error(error)
			return false
		candidate[raw_id] = controller
	if _land != null:
		for id: String in _land.restored_seed_ids():
			if candidate.has(id) or not expected_ids.has(id):
				error = "INVALID APPENDED LAND CONTROL: " + id
				return false
			var controller: Variant = opening_controllers.get(id)
			if not controller is String or not _valid_land_controller(id,str(controller)):
				error = "MISSING APPENDED LAND OPENING CONTROL: " + id
				return false
			candidate[id] = str(controller)
	for territory_id: String in expected_ids:
		if not candidate.has(territory_id):
			error = "MISSING TERRITORY ID: %s" % territory_id
			push_error(error)
			return false
	_controllers = candidate
	return true
