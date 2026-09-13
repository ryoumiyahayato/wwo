class_name VNextSyntheticObservationVisibilityResolver
extends VNextObservationVisibilityResolver

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")

const OBSERVER_A_ID: String = "person:observer_a"
const OBSERVER_B_ID: String = "person:observer_b"
const QA_OBSERVER_ID: String = "person:qa_observer"
const SUBJECT_X_ID: String = "person:subject_x"

var _known_observers: Dictionary = {}
var _capabilities_by_observer: Dictionary = {}


func _init() -> void:
	_known_observers = {
		OBSERVER_A_ID: true,
		OBSERVER_B_ID: true,
		QA_OBSERVER_ID: true,
	}
	_capabilities_by_observer = {
		OBSERVER_A_ID: [CONTRACT.RESTRICTED_CAPABILITY],
		OBSERVER_B_ID: [],
		QA_OBSERVER_ID: [CONTRACT.TRUTH_CAPABILITY],
	}


func is_known_observer(observer_actor_id: String) -> bool:
	return _known_observers.has(observer_actor_id)


func has_capability(observer_actor_id: String, capability: String) -> bool:
	if not is_known_observer(observer_actor_id) or capability.is_empty():
		return false
	var capabilities: Array = _capabilities_by_observer.get(observer_actor_id, []) as Array
	return capabilities.has(capability)


func can_observe(
	observer_actor_id: String,
	subject_id: String,
	_field_id: String,
	required_capability: String
) -> bool:
	if not is_known_observer(observer_actor_id) or subject_id != SUBJECT_X_ID:
		return false
	if required_capability.is_empty():
		return true
	if has_capability(observer_actor_id, CONTRACT.TRUTH_CAPABILITY):
		return true
	return has_capability(observer_actor_id, required_capability)
