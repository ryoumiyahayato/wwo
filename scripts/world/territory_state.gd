class_name TerritoryState
extends RefCounted
## The sole mutable owner of current place control. Controller IDs are opaque.

const SCHEMA_ID: String = "territory_state_v1"

var error: String = ""
var _controllers: Dictionary[String, String] = {}


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
	_controllers[territory_id] = controller_id
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


func restore(value: Dictionary, expected_ids: Array[String]) -> bool:
	error = ""
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
		if not controller is String or (controller as String).is_empty():
			error = "UNKNOWN CONTROLLER for territory: %s" % str(raw_id)
			push_error(error)
			return false
		candidate[raw_id] = controller
	for territory_id: String in expected_ids:
		if not candidate.has(territory_id):
			error = "MISSING TERRITORY ID: %s" % territory_id
			push_error(error)
			return false
	_controllers = candidate
	return true
