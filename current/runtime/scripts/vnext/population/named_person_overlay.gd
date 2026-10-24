class_name VNextNamedPersonOverlay
extends RefCounted
## Stable named-person coverage over an existing authoritative Population total
## query. This overlay owns identity/claim/lifecycle references only. It never
## owns aggregate totals. Formal composition additionally binds a statistical
## Population state so materialization reserves one existing background person.

const SNAPSHOT_SCHEMA_ID: String = "vnext_named_person_overlay_v1"
## The retained population_territory_id wire field identifies the provider's
## population unit. In Formal it is a major-economy statistical scope, not a
## TerritoryUnitCatalog, current political entity or display geometry identity.
const _SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"population_source_fingerprint",
	"persons",
]
const _RECORD_FIELDS: Array[String] = [
	"person_id",
	"claim_id",
	"population_territory_id",
	"basic_demographic_identity",
	"current_place_id",
	"alive",
	"provenance",
]

var _population_total_query: Callable
var _place_exists_query: Callable
var _population_source_fingerprint: String = ""
var _persons_by_id: Dictionary = {}
var _person_id_by_claim_id: Dictionary = {}
var _last_error: String = ""
var _population_state: FormalWorldPopulationState = null
var _formal_world_ref: WeakRef


func bind_population_state(state: FormalWorldPopulationState) -> bool:
	if state == null or not state.is_configured() or _population_state != null or not _persons_by_id.is_empty():
		return false
	_population_state = state
	return true


static func create(
	population_total_query: Callable,
	place_exists_query: Callable,
	population_source_fingerprint: String
) -> VNextNamedPersonOverlay:
	var overlay := VNextNamedPersonOverlay.new()
	if not overlay.configure(
		population_total_query,
		place_exists_query,
		population_source_fingerprint
	):
		return null
	return overlay


func configure(
	population_total_query: Callable,
	place_exists_query: Callable,
	population_source_fingerprint: String
) -> bool:
	if (
		_population_total_query.is_valid()
		or not population_total_query.is_valid()
		or not place_exists_query.is_valid()
		or population_source_fingerprint.is_empty()
	):
		return false
	_population_total_query = population_total_query
	_place_exists_query = place_exists_query
	_population_source_fingerprint = population_source_fingerprint
	return true


func is_configured() -> bool:
	return (
		_population_total_query.is_valid()
		and _place_exists_query.is_valid()
		and not _population_source_fingerprint.is_empty()
	)


func rebind_population_total_query(population_total_query: Callable) -> bool:
	if (
		not population_total_query.is_valid()
		or not _place_exists_query.is_valid()
		or _population_source_fingerprint.is_empty()
	):
		return false
	_population_total_query = population_total_query
	return true


func last_error() -> String:
	return _last_error


func person_count() -> int:
	return _persons_by_id.size()


func person_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _persons_by_id.keys():
		if typeof(raw_id) == TYPE_STRING:
			result.append(str(raw_id))
	result.sort()
	return result


func has_person(person_id: String) -> bool:
	return _persons_by_id.has(person_id)


func is_alive(person_id: String) -> bool:
	return bool((_persons_by_id.get(person_id, {}) as Dictionary).get("alive", false))


func current_place(person_id: String) -> String:
	return str((_persons_by_id.get(person_id, {}) as Dictionary).get("current_place_id", ""))

## Travel changes physical presence without changing the person's statistical
## population claim. Cross-unit migration needs its own host responsibility rule.
func relocate(person_id: String, place_id: String) -> bool:
	if not is_alive(person_id) or not _place_exists(place_id): return false
	if _population_state != null and _population_state.place_support(place_id) == "UNKNOWN": return false
	_persons_by_id[person_id]["current_place_id"] = place_id
	return true


func population_claim(person_id: String) -> Dictionary:
	var record := _persons_by_id.get(person_id, {}) as Dictionary
	if record.is_empty():
		return {}
	return {
		"claim_id": str(record.get("claim_id", "")),
		"territory_id": str(record.get("population_territory_id", "")),
		"coverage": 1,
		"active": bool(record.get("alive", false)),
	}


func person(person_id: String) -> Dictionary:
	return (_persons_by_id.get(person_id, {}) as Dictionary).duplicate(true)


func materialize(
	person_id: String,
	claim_id: String,
	population_territory_id: String,
	basic_demographic_identity: Dictionary,
	current_place_id: String,
	provenance: Dictionary
) -> bool:
	_last_error = ""
	if not is_configured():
		return _fail("named person overlay is not configured")
	if (
		not VNextStableId.is_valid(person_id)
		or VNextStableId.kind_of(person_id) != "person"
	):
		return _fail("invalid person id")
	if _persons_by_id.has(person_id):
		return _fail("duplicate person id")
	if claim_id.is_empty() or _person_id_by_claim_id.has(claim_id):
		return _fail("duplicate or empty population claim")
	if population_territory_id.is_empty():
		return _fail("population territory claim is empty")
	if not _place_exists(current_place_id):
		return _fail("current place does not exist")
	if basic_demographic_identity.is_empty():
		return _fail("basic demographic identity is required")
	if provenance.is_empty():
		return _fail("provenance is required")
	var population_total := _population_total_for(population_territory_id)
	if population_total <= 0:
		return _fail("population territory has no authoritative population")
	if _active_claimed_count_for_territory(population_territory_id) >= population_total:
		return _fail("population claim exceeds authoritative population")
	var record := {
		"person_id": person_id,
		"claim_id": claim_id,
		"population_territory_id": population_territory_id,
		"basic_demographic_identity": basic_demographic_identity.duplicate(true),
		"current_place_id": current_place_id,
		"alive": true,
		"provenance": provenance.duplicate(true),
	}
	if _population_state != null and not _population_state.materialize_named_person(person_id, population_territory_id, current_place_id):
		return _fail(_population_state.error)
	_persons_by_id[person_id] = record
	_person_id_by_claim_id[claim_id] = person_id
	return true


func anonymous_population_for_territory(population_territory_id: String) -> int:
	if not is_configured():
		return -1
	var total := _population_total_for(population_territory_id)
	if total < 0:
		return -1
	return total - _active_claimed_count_for_territory(population_territory_id)


func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for person_id: String in person_ids():
		records.append(person(person_id))
	var result := {"schema_id": SNAPSHOT_SCHEMA_ID, "population_source_fingerprint": _population_source_fingerprint, "persons": records}
	return result


func restore(snapshot_value: Dictionary) -> bool:
	_last_error = ""
	if not is_configured():
		return _fail("named person overlay is not configured")
	var fields: Array[String] = _SNAPSHOT_FIELDS.duplicate()
	if not _has_exact_fields(snapshot_value, fields):
		return _fail("named person snapshot header is invalid")
	if (
		typeof(snapshot_value.get("schema_id")) != TYPE_STRING
		or snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID
		or typeof(snapshot_value.get("population_source_fingerprint")) != TYPE_STRING
		or snapshot_value.get("population_source_fingerprint")
		!= _population_source_fingerprint
		or typeof(snapshot_value.get("persons")) != TYPE_ARRAY
	):
		return _fail("named person snapshot header is invalid")

	var candidate_persons: Dictionary = {}
	var candidate_claims: Dictionary = {}
	var active_claim_counts: Dictionary = {}
	for raw_record: Variant in snapshot_value.get("persons") as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return _fail("named person snapshot record is invalid")
		var record := (raw_record as Dictionary).duplicate(true)
		if not _has_exact_fields(record, _RECORD_FIELDS):
			return _fail("named person snapshot record is invalid")
		if (
			typeof(record.get("person_id")) != TYPE_STRING
			or typeof(record.get("claim_id")) != TYPE_STRING
			or typeof(record.get("population_territory_id")) != TYPE_STRING
			or typeof(record.get("current_place_id")) != TYPE_STRING
			or typeof(record.get("basic_demographic_identity")) != TYPE_DICTIONARY
			or typeof(record.get("provenance")) != TYPE_DICTIONARY
			or typeof(record.get("alive")) != TYPE_BOOL
		):
			return _fail("named person snapshot record failed validation")

		var person_id: String = record.get("person_id") as String
		var claim_id: String = record.get("claim_id") as String
		var territory_id: String = record.get("population_territory_id") as String
		var place_id: String = record.get("current_place_id") as String
		var demographic_identity: Dictionary = (
			record.get("basic_demographic_identity") as Dictionary
		)
		var provenance: Dictionary = record.get("provenance") as Dictionary
		if (
			not VNextStableId.is_valid(person_id)
			or VNextStableId.kind_of(person_id) != "person"
			or candidate_persons.has(person_id)
			or claim_id.is_empty()
			or candidate_claims.has(claim_id)
			or territory_id.is_empty()
			or _population_total_for(territory_id) <= 0
			or not _place_exists(place_id)
			or demographic_identity.is_empty()
			or provenance.is_empty()
		):
			return _fail("named person snapshot record failed validation")
		candidate_persons[person_id] = record
		candidate_claims[claim_id] = person_id
		if bool(record.get("alive")):
			active_claim_counts[territory_id] = (
				int(active_claim_counts.get(territory_id, 0)) + 1
			)

	for raw_territory_id: Variant in active_claim_counts.keys():
		var territory_id: String = str(raw_territory_id)
		if int(active_claim_counts[territory_id]) > _population_total_for(territory_id):
			return _fail("named person claims violate population conservation")

	if _population_state != null and not _population_state.matches_person_records(candidate_persons):
		return _fail("named persons differ from current Population coverage or place mapping")
	_persons_by_id = candidate_persons
	_person_id_by_claim_id = candidate_claims
	return true


func state_fingerprint() -> String:
	return JSON.stringify(snapshot()).sha256_text()


func _active_claimed_count_for_territory(territory_id: String) -> int:
	var count: int = 0
	for raw_record: Variant in _persons_by_id.values():
		var record := raw_record as Dictionary
		if (
			str(record.get("population_territory_id", "")) == territory_id
			and bool(record.get("alive", false))
		):
			count += 1
	return count


func _population_total_for(population_territory_id: String) -> int:
	if population_territory_id.is_empty() or not _population_total_query.is_valid():
		return -1
	var raw_total: Variant = _population_total_query.call(population_territory_id)
	if typeof(raw_total) != TYPE_INT:
		return -1
	return int(raw_total)


func _place_exists(place_id: String) -> bool:
	if place_id.is_empty() or not _place_exists_query.is_valid():
		return false
	var raw_exists: Variant = _place_exists_query.call(place_id)
	return typeof(raw_exists) == TYPE_BOOL and bool(raw_exists)


static func _has_exact_fields(value: Dictionary, expected_fields: Array[String]) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field_name: String in expected_fields:
		if not value.has(field_name):
			return false
	return true


func _fail(message: String) -> bool:
	_last_error = message
	return false

## Formal space owns journeys and location. The economy only reads attendance.
func bind_formal_space(world: WorldState) -> void:
	_formal_world_ref = weakref(world)

func _formal_world() -> WorldState:
	return _formal_world_ref.get_ref() as WorldState if _formal_world_ref != null else null

static func valid_mobility_configuration(value: Variant) -> bool:
	if not value is Dictionary or not FormalLedgerState.exact_fields(value, ["passages", "carry_limits", "npc_policies", "arrival_notices"]): return false
	for key: String in ["passages", "npc_policies", "arrival_notices"]:
		if not value[key] is Array or value[key].size() > 256: return false
	if not value["carry_limits"] is Dictionary: return false
	for commodity: Variant in value["carry_limits"]:
		if not commodity is String or not FormalLedgerState.valid_amount(value["carry_limits"][commodity]): return false
	var ids: Dictionary = {}
	for row: Variant in value["passages"]:
		if not row is Dictionary or not EconomySliceConfig._fields(row, ["id", "source_link_id", "from_place_id", "to_place_id", "minutes", "fee", "payee_account_id", "known_to", "basis"], ["shared_capacity"]) or not row["id"] is String or ids.has(row["id"]) or not row["source_link_id"] is String or not row["from_place_id"] is String or not row["to_place_id"] is String or row["from_place_id"] == row["to_place_id"] or not FormalLedgerState.valid_amount(row["minutes"]) or int(row["minutes"]) < 1 or not FormalLedgerState.valid_amount(row["fee"]) or not row["payee_account_id"] is String or not row["known_to"] is Array or row["basis"] != "EXPLICIT_DEVELOPMENT_PERSON_PASSAGE": return false
		if row.has("shared_capacity"):
			var shared: Variant=row["shared_capacity"]
			if not shared is Dictionary or not FormalLedgerState.exact_fields(shared,["unit","numerator","denominator","basis"]) or not shared["unit"] is String or shared["unit"].is_empty() or not FormalLedgerState.valid_amount(shared["numerator"]) or shared["numerator"]<1 or not FormalLedgerState.valid_amount(shared["denominator"]) or shared["denominator"]<1 or shared["basis"]!="EXPLICIT_DEVELOPMENT_COMMON_PASSAGE": return false
		ids[row["id"]] = true
		var people: Dictionary = {}
		for person: Variant in row["known_to"]:
			if not person is String or people.has(person): return false
			people[person] = true
	var policies: Dictionary = {}
	for policy: Variant in value["npc_policies"]:
		if not policy is Dictionary or not FormalLedgerState.exact_fields(policy, ["person_id", "max_fee", "max_minutes", "cooldown_days", "max_trips"]) or not policy["person_id"] is String or policy["person_id"].is_empty() or policies.has(policy["person_id"]): return false
		policies[policy["person_id"]] = true
		for key: String in ["max_fee", "max_minutes", "cooldown_days", "max_trips"]:
			if not FormalLedgerState.valid_amount(policy[key]): return false
	for notice: Variant in value["arrival_notices"]:
		if not notice is Dictionary or not FormalLedgerState.exact_fields(notice, ["place_id", "kind", "candidate"]) or not notice["place_id"] is String or notice["kind"] not in ["job", "supplier"] or not notice["candidate"] is String: return false
	return true

func configure_formal_mobility(value: Dictionary) -> bool:
	var world := _formal_world()
	return value.is_empty() or (world != null and world.person_travel != null and world.person_travel.configure_mobility(value))

func is_travelling(person: String) -> bool:
	var world := _formal_world()
	return world != null and world.person_travel != null and world.person_travel.is_in_transit(person)

func is_at_place(person: String, place: String) -> bool:
	return is_alive(person) and not is_travelling(person) and current_place(person) == place

func has_travel_action(id: String) -> bool:
	var world := _formal_world()
	return world != null and world.person_travel != null and world.person_travel.has_action(id)

func travel_action_count() -> int:
	var world := _formal_world()
	return world.person_travel.action_count() if world != null and world.person_travel != null else 0

func travel_view(person: String) -> Dictionary:
	var world := _formal_world()
	return world.person_travel.view(person) if world != null and world.person_travel != null else {}

func arrival_notices(place: String) -> Array[Dictionary]:
	var world := _formal_world()
	return world.person_travel.arrival_notices(place) if world != null and world.person_travel != null else []


## Population owns the single residence commit. Physical location stays unchanged.
func commit_population_residence(owner: FormalWorldPopulationState, person_id: String, source: String, destination: String) -> bool:
	if owner == null or owner != _population_state or not is_alive(person_id) or owner.unit_for_person(person_id) != source or _persons_by_id[person_id]["population_territory_id"] != source or owner.unit_for_place(current_place(person_id)) != destination or is_travelling(person_id): return false
	_persons_by_id[person_id]["population_territory_id"] = destination
	return true
