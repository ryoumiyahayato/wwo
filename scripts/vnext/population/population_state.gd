class_name VNextPopulationState
extends RefCounted
## Minimal population record owned by VNextPopulationAuthority.
##
## Territory identity and every political, economic, household, employment,
## military, and demographic-classification fact remain outside this record.

const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

var _configured: bool = false
var _territory_unit_id: String = ""
var _total_population: int = 0


func configure(territory_unit_id_value: Variant, total_population_value: Variant) -> bool:
	if _configured:
		return false
	if (
		typeof(territory_unit_id_value) != TYPE_STRING
		or not TERRITORY_UNIT.is_valid_territory_unit_id(
			territory_unit_id_value as String
		)
		or not is_valid_population_value(total_population_value)
	):
		return false
	_territory_unit_id = territory_unit_id_value as String
	_total_population = int(total_population_value)
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func territory_unit_id() -> String:
	return _territory_unit_id


func total_population() -> int:
	return _total_population


func copy_detached() -> VNextPopulationState:
	if not _configured:
		return null
	var copied := VNextPopulationState.new()
	return copied if copied.configure(_territory_unit_id, _total_population) else null


func to_detached_dict() -> Dictionary:
	if not _configured:
		return {}
	return {
		"territory_unit_id": _territory_unit_id,
		"total_population": _total_population,
	}


static func is_valid_population_value(candidate_value: Variant) -> bool:
	return (
		typeof(candidate_value) == TYPE_INT
		and int(candidate_value) >= 0
		and int(candidate_value) <= MAX_JSON_SAFE_INTEGER
	)
