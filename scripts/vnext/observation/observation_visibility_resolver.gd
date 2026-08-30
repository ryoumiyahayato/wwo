class_name VNextObservationVisibilityResolver
extends RefCounted

## Authorization truth stays outside the observation contract. The default
## resolver rejects every decision, so an absent injection fails closed.


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
