class_name VNextPopulationConservationValidator
extends RefCounted
## Domain-local exact-integer conservation checks for population transfers.

const POPULATION_STATE = preload(
	"res://scripts/vnext/population/population_state.gd"
)


static func total_for_states(states_by_id: Dictionary) -> int:
	var total: int = 0
	for raw_state: Variant in states_by_id.values():
		if not raw_state is VNextPopulationState:
			return -1
		var state: VNextPopulationState = raw_state as VNextPopulationState
		if state == null or not state.is_configured():
			return -1
		var population: int = state.total_population()
		if population > POPULATION_STATE.MAX_JSON_SAFE_INTEGER - total:
			return -1
		total += population
	return total


static func conserves(before_states: Dictionary, after_states: Dictionary) -> bool:
	var before_total: int = total_for_states(before_states)
	var after_total: int = total_for_states(after_states)
	return before_total >= 0 and before_total == after_total
