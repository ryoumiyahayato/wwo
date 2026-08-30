class_name VNextObservationVisibilityResolver
extends RefCounted

## Authorization truth is injected from outside this contract. The default
## implementation rejects every decision, so absence of a resolver fails closed.


func is_known_observer(_observer_actor_id: String) -> bool:
	return false

func has_capability(_observer_actor_id: String, _capability: String) -> bool:
	return false


func can_observe(
	_observer_actor_id: String,
	_subject_id: String,
	_field_id: String,
	_required_capability: String
) -> bool:
	return false
