extends "res://experiments/war_resolver/resolver.gd"
## Shares the predecessor's fire, movement, suppression and boundary kernel.
const Index = preload("res://experiments/war_resolver/aggregation/contact_index.gd")
var work: Dictionary = {"candidate_contacts_examined": 0, "index_records_examined": 0,
	"range_probes": 0, "formations_resolved": 0}
var _index: Index = Index.new()

func _prepare_area(state: State, area_id: String) -> Dictionary:
	var ids: Array[String] = State.sorted_ids(state.area_units[area_id])
	_index.build(state.units, ids, state)
	work.index_records_examined += ids.size()
	work.formations_resolved += ids.size()
	return super._prepare_area(state, area_id)

func _candidate_ids(_state: State, ids: Array[String], unit: Dictionary) -> Array[String]:
	var before: int = _index.probes
	var result: Array[String] = _index.candidates(float(unit.position), float(unit.weapon.range_km))
	work.range_probes += _index.probes - before
	work.candidate_contacts_examined += result.size()
	return result
