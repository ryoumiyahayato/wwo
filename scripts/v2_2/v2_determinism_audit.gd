class_name V2DeterminismAudit
extends RefCounted
## Canonical, UI-independent state used by save/restore and long-run regressions.


static func digest(simulation: V2LifeLoopSimulation) -> Dictionary:
	if simulation == null or not simulation.initialized:
		return {}
	return {
		"current_datetime": V2DateTime.iso_from_total_hour(simulation.clock.total_hours),
		"time_speed": simulation.clock.speed_multiplier,
		"paused": simulation.clock.is_paused,
		"random_seed": str(simulation.random.get_seed()),
		"random_state": str(simulation.random.get_state()),
		"selected_person_id": simulation.selected_person_id,
		"person_states": simulation.person_states.duplicate(true),
		"schedule_state": simulation.schedule.get_persistent_state(),
		"employment_state": simulation.employment.get_persistent_state(),
		"household_state": simulation.households.get_persistent_state(),
		"ledger_state": simulation.ledger.get_persistent_state(),
		"condition_state": simulation.conditions.get_persistent_state(),
		"relationship_state": simulation.relationships.get_persistent_state(),
		"organization_state": simulation.organizations.get_persistent_state(),
		"notification_state": simulation.notifications.get_persistent_state(),
		"processed_idempotency_keys": simulation.processed_idempotency_keys.duplicate(true),
		"hours_processed": simulation.hours_processed,
	}


static func comparison(
	first: V2LifeLoopSimulation, second: V2LifeLoopSimulation
) -> Dictionary:
	var first_digest: Dictionary = digest(first)
	var second_digest: Dictionary = digest(second)
	var fields: Dictionary = {}
	var all_equal: bool = true
	for field_variant: Variant in first_digest.keys():
		var field: String = str(field_variant)
		var equal: bool = first_digest.get(field) == second_digest.get(field)
		fields[field] = equal
		all_equal = all_equal and equal
	for field_variant: Variant in second_digest.keys():
		var field: String = str(field_variant)
		if fields.has(field):
			continue
		fields[field] = false
		all_equal = false
	return {
		"all_fields_equal": all_equal,
		"fields": fields,
		"first": first_digest,
		"second": second_digest,
	}
