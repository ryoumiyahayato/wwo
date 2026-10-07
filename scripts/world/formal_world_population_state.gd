class_name FormalWorldPopulationState
extends RefCounted
## Mutable population over admitted major-economy statistical units. These IDs
## describe the fixed bootstrap scope, not sovereignty, control or polygons.

const SCHEMA_ID: String = "formal_world_population_state_v1"
const MAX_POPULATION: int = 9007199254740991

var error: String = ""
var _source_fingerprint: String = ""
var _binding: String = ""
var _initial_total: int = 0
var _totals: Dictionary = {}
var _named: Dictionary = {}
var _named_counts: Dictionary = {}
var _polities: Dictionary = {}
var _places: Dictionary = {}


func configure(input: Dictionary, polity_units: Dictionary, place_units: Dictionary) -> bool:
	if is_configured() or typeof(input.get("records")) != TYPE_ARRAY:
		return _fail("Population input is missing or already initialized")
	var totals: Dictionary = {}
	var total: int = 0
	for raw: Variant in input["records"]:
		if not raw is Dictionary:
			return _fail("Invalid population record")
		var record := raw as Dictionary
		var unit_id := str(record.get("economy_entity_id", ""))
		var population_record: Variant = record.get("population")
		if unit_id.is_empty() or totals.has(unit_id) or not population_record is Dictionary:
			return _fail("Invalid or duplicate statistical unit")
		var value: Variant = (population_record as Dictionary).get("value")
		if not _valid_count(value) or int(value) > MAX_POPULATION - total:
			return _fail("Invalid population total")
		totals[unit_id] = value
		total += int(value)
	if totals.is_empty() or str(input.get("fingerprint", "")).is_empty():
		return _fail("Population evidence is unavailable")
	for mapping: Dictionary in [polity_units, place_units]:
		for key: Variant in mapping:
			if not key is String or not mapping[key] is String:
				return _fail("Invalid statistical unit mapping")
			if not str(mapping[key]).is_empty() and not totals.has(mapping[key]):
				return _fail("Mapping references unavailable population")
	_totals = totals
	_initial_total = total
	_polities = polity_units.duplicate(true)
	_places = place_units.duplicate(true)
	_source_fingerprint = str(input["fingerprint"])
	_binding = JSON.stringify({"source": _source_fingerprint, "polities": _polities, "places": _places}).sha256_text()
	_named_counts = _counts({})
	error = ""
	return true


func is_configured() -> bool:
	return not _source_fingerprint.is_empty()


func unit_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_totals.keys())
	ids.sort()
	return ids


func population(unit_id: String) -> int:
	return int(_totals.get(unit_id, -1))


func unit_for_place(place_id: String) -> String:
	return str(_places.get(place_id, ""))


func unit_for_polity(source_polity_id: String) -> String:
	return str(_polities.get(source_polity_id, ""))


func place_support(place_id: String) -> String:
	if not _places.has(place_id):
		return "UNKNOWN"
	return "SUPPORTED" if not unit_for_place(place_id).is_empty() else "UNSUPPORTED"


func unit(unit_id: String) -> Dictionary:
	if not _totals.has(unit_id):
		return {}
	var named_count := int(_named_counts[unit_id])
	return {
		"population_unit_id": unit_id,
		"statistical_scope": "major_economy_aggregate",
		"economic_aggregate_id": unit_id,
		"population_total": population(unit_id),
		"named_person_count": named_count,
		"remaining_background_population": population(unit_id) - named_count,
	}


func materialize_named_person(person_id: String, unit_id: String, place_id: String) -> bool:
	if not VNextStableId.is_valid(person_id) or VNextStableId.kind_of(person_id) != "person" or _named.has(person_id):
		return _fail("Invalid or duplicate named person")
	if not _totals.has(unit_id) or unit_for_place(place_id) != unit_id:
		return _fail("Person place does not resolve to its population unit")
	if population(unit_id) <= int(_named_counts[unit_id]):
		return _fail("Background population is exhausted")
	_named[person_id] = unit_id
	_named_counts[unit_id] = int(_named_counts[unit_id]) + 1
	error = ""
	return true


## Only anonymous people move. Named-person relocation is outside R1.
func transfer_population(source_id: String, destination_id: String, amount: int) -> bool:
	if source_id == destination_id or not _totals.has(source_id) or not _totals.has(destination_id) or amount <= 0:
		return _fail("Invalid population transfer")
	if amount > population(source_id) - int(_named_counts[source_id]) or amount > MAX_POPULATION - population(destination_id):
		return _fail("Population transfer exceeds available background or numeric bounds")
	_totals[source_id] = population(source_id) - amount
	_totals[destination_id] = population(destination_id) + amount
	error = ""
	return true


func matches_person_records(persons: Dictionary) -> bool:
	var named: Dictionary = {}
	for person_id: String in persons:
		var record := persons[person_id] as Dictionary
		var unit_id := str(record.get("population_territory_id", ""))
		if not bool(record.get("alive", false)) or unit_for_place(str(record.get("current_place_id", ""))) != unit_id:
			return false
		named[person_id] = unit_id
	return named == _named


func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for unit_id: String in unit_ids():
		records.append(unit(unit_id))
	var named: Dictionary = {}
	var ids: Array = _named.keys()
	ids.sort()
	for person_id: String in ids:
		named[person_id] = _named[person_id]
	return {"schema_id": SCHEMA_ID, "binding": _binding, "records": records, "named_person_units": named}


## Parse and validate detached values before replacing any installed facts.
func restore(value: Dictionary) -> bool:
	if not is_configured() or value.size() != 4 or value.get("schema_id") != SCHEMA_ID or value.get("binding") != _binding:
		return _fail("Population snapshot binding or schema is invalid")
	if not value.get("records") is Array or not value.get("named_person_units") is Dictionary:
		return _fail("Population snapshot fields are invalid")
	var totals: Dictionary = {}
	var named := (value["named_person_units"] as Dictionary).duplicate(true)
	var total: int = 0
	for raw: Variant in value["records"]:
		if not raw is Dictionary:
			return _fail("Population snapshot record is invalid")
		var record := raw as Dictionary
		var unit_id := str(record.get("population_unit_id", ""))
		if record.size() != 6 or not _totals.has(unit_id) or totals.has(unit_id) or record.get("statistical_scope") != "major_economy_aggregate" or record.get("economic_aggregate_id") != unit_id:
			return _fail("Population snapshot statistical unit is invalid")
		for field: String in ["population_total", "named_person_count", "remaining_background_population"]:
			if not _valid_count(record.get(field)):
				return _fail("Population snapshot count is invalid")
		var count := int(record["population_total"])
		if count > MAX_POPULATION - total or int(record["named_person_count"]) > count or count - int(record["named_person_count"]) != int(record["remaining_background_population"]):
			return _fail("Population snapshot violates conservation")
		totals[unit_id] = count
		total += count
	if totals.size() != _totals.size() or total != _initial_total:
		return _fail("Population snapshot loses supported units or global conservation")
	for person_id: Variant in named:
		if not person_id is String or not VNextStableId.is_valid(person_id) or VNextStableId.kind_of(person_id) != "person" or not named[person_id] is String or not totals.has(named[person_id]):
			return _fail("Population snapshot named reference is invalid")
	var counts := _counts(named)
	for raw: Dictionary in value["records"]:
		var unit_id := str(raw["population_unit_id"])
		if int(raw["named_person_count"]) != int(counts[unit_id]):
			return _fail("Population snapshot named coverage is inconsistent")
	_totals = totals
	_named = named
	_named_counts = counts
	error = ""
	return true


func _counts(named: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for unit_id: String in unit_ids():
		counts[unit_id] = 0
	for unit_id: String in named.values():
		counts[unit_id] = int(counts[unit_id]) + 1
	return counts


func _valid_count(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_POPULATION


func _fail(message: String) -> bool:
	error = message
	return false
