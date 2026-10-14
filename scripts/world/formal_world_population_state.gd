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
var _base_places: Dictionary = {}
var _place_population_bindings: Array[Dictionary] = []
# Derived from the installed native cohorts; totals and named claims stay here.
var _native_background: Dictionary = {}
var _native_background_owner_ref: WeakRef
# Explicit residence operations, separate from physical travel and anonymous transfers.
var _residence_requests: Dictionary = {}


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
	_base_places = place_units.duplicate(true)
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


func unit_for_person(person_id: String) -> String:
	return str(_named.get(person_id, ""))


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
	if population(unit_id) <= int(_named_counts[unit_id]) + int(_native_background.get(unit_id, 0)):
		return _fail("Background population is exhausted")
	_named[person_id] = unit_id
	_named_counts[unit_id] = int(_named_counts[unit_id]) + 1
	error = ""
	return true


## Only anonymous population moves through this operation.
func transfer_population(source_id: String, destination_id: String, amount: int) -> bool:
	if source_id == destination_id or not _totals.has(source_id) or not _totals.has(destination_id) or amount <= 0:
		return _fail("Invalid population transfer")
	if amount > population(source_id) - int(_named_counts[source_id]) - int(_native_background.get(source_id, 0)) or amount > MAX_POPULATION - population(destination_id):
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
		if not bool(record.get("alive", false)) or not _totals.has(unit_id) or place_support(str(record.get("current_place_id", ""))) == "UNKNOWN":
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
	var result := {"schema_id": SCHEMA_ID, "binding": _binding, "records": records, "named_person_units": named}
	if not _residence_requests.is_empty(): result["residence_requests"] = _residence_requests.duplicate(true)
	if not _place_population_bindings.is_empty(): result["place_population_bindings"] = _place_population_bindings.duplicate(true)
	return result


## Parse and validate detached values before replacing any installed facts.
func restore(value: Dictionary) -> bool:
	var fields: Array[String] = ["schema_id", "binding", "records", "named_person_units"]
	if value.has("residence_requests"): fields.append("residence_requests")
	if value.has("place_population_bindings"): fields.append("place_population_bindings")
	if not is_configured() or not FormalLedgerState.exact_fields(value, fields) or value.get("schema_id") != SCHEMA_ID or value.get("binding") != _binding:
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
	var place_rows: Variant = value.get("place_population_bindings", [])
	var places := _prepared_place_population_units(place_rows)
	if places.is_empty(): return _fail("Invalid explicit place population binding")
	var requests: Variant = value.get("residence_requests", {})
	if not _valid_residence_requests(requests, named, places): return _fail("Invalid named residence history")
	_totals = totals
	_named = named
	_named_counts = counts
	_residence_requests = requests.duplicate(true)
	_places = places
	_place_population_bindings.assign(place_rows.duplicate(true))
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

func bind_native_background(responsibilities: Dictionary, owner: RefCounted = null, boundary_handover: bool = false) -> bool:
	var previous := _native_background_owner_ref.get_ref() as RefCounted if _native_background_owner_ref != null else null
	if previous != null and bool(previous.call("management_active")) and (owner != previous or (responsibilities != _native_background and not boundary_handover)):
		return _fail("Active native population ranges require an explicit responsibility handover")
	if not responsibilities.is_empty() and (owner == null or not owner.has_method("background_responsibilities") or owner.call("background_responsibilities") != responsibilities):
		return _fail("Native population reservation must reference its prepared economic owner")
	for unit_id: String in responsibilities:
		if not _totals.has(unit_id) or not _valid_count(responsibilities[unit_id]) or int(responsibilities[unit_id]) > population(unit_id) - int(_named_counts[unit_id]):
			return _fail("Native cohorts exceed current anonymous population: " + unit_id)
	_native_background = responsibilities.duplicate(true)
	_native_background_owner_ref = weakref(owner) if owner != null else null
	return true


func residence_unit_at(person: String, minute: int) -> String:
	var result := unit_for_person(person)
	var applied: Array[Dictionary] = []
	for row: Dictionary in _residence_requests.values():
		if row["person_id"] == person and row["status"] == "APPLIED" and int(row["effective_minute"]) > minute: applied.append(row)
	applied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) > int(b["effective_minute"]))
	for row: Dictionary in applied: result = row["source_unit_id"]
	return result

func _residence_permission(world: WorldState, person: String, source: String, destination: String, place: String) -> Dictionary:
	if world.economy_r1 == null: return {}
	for row: Dictionary in world.economy_r1.config.get("residence_permissions", []):
		if row["person_id"] == person and row["source_unit_id"] == source and row["destination_unit_id"] == destination and row["place_ids"].has(place): return row.duplicate(true)
	return {}

func residence_view(world: WorldState, person: String) -> Dictionary:
	var pending: Array[Dictionary] = []
	var history: Array[Dictionary] = []
	for row: Dictionary in _residence_requests.values():
		if row["person_id"] != person: continue
		history.append(row.duplicate(true))
		if row["status"] in ["QUEUED", "DEFERRED"]: pending.append(row.duplicate(true))
	var place := world.person_overlay.current_place(person)
	var target := unit_for_place(place)
	var permission := _residence_permission(world, person, unit_for_person(person), target, place)
	return {"resident_population_unit_id": unit_for_person(person), "current_place_id": place, "activity_population_unit_id": target, "pending": pending, "history": history, "can_request": _residence_requests.size() < 128 and world.person_overlay.is_at_place(person, place) and (world.person_travel == null or not world.person_travel.active(person)) and target != unit_for_person(person) and not permission.is_empty() and pending.is_empty(), "target_unit_id": target, "permission_basis": permission.get("basis", "")}

func request_residence(world: WorldState, person: String, payload: Dictionary, action_id: String, native_source: EconomyR1Slice = null) -> Dictionary:
	if world == null: return {"accepted": false, "reason": "NO_RESIDENCE_ACTION_AUTHORITY"}
	var authorized := (person == world.player_state.player_id()) if native_source == null else (native_source == world.economy_r1 and native_source.npc_residence_authorized(person, payload))
	if not authorized or not world.person_overlay.is_alive(person) or not FormalLedgerState.exact_fields(payload, ["destination_unit_id", "place_id"]) or not payload["destination_unit_id"] is String or not payload["place_id"] is String: return {"accepted": false, "reason": "NO_RESIDENCE_ACTION_AUTHORITY"}
	if _residence_requests.has(action_id): return {"accepted": false, "reason": "RESIDENCE_ACTION_ALREADY_EXISTS"}
	if _residence_requests.size() >= 128: return {"accepted": false, "reason": "RESIDENCE_REQUEST_LIMIT"}
	var source := unit_for_person(person)
	var destination := str(payload["destination_unit_id"])
	var place := str(payload["place_id"])
	if source.is_empty() or source == destination or not _totals.has(destination) or unit_for_place(place) != destination or not world.person_overlay.is_at_place(person, place) or (world.person_travel != null and world.person_travel.active(person)): return {"accepted": false, "reason": "RESIDENCE_REQUIRES_ACTUAL_TARGET_PRESENCE"}
	var permission := _residence_permission(world, person, source, destination, place)
	if permission.is_empty(): return {"accepted": false, "reason": "RESIDENCE_PERMISSION_UNCONFIGURED"}
	for row: Dictionary in _residence_requests.values():
		if row["person_id"] == person and row["status"] in ["QUEUED", "DEFERRED"]: return {"accepted": false, "reason": "RESIDENCE_REQUEST_PENDING"}
	var minute := world.game_clock.total_minutes()
	if minute > FormalLedgerState.MAX_AMOUNT-1440: return {"accepted": false, "reason": "RESIDENCE_TIME_LIMIT"}
	var boundary: int = (minute / 1440 + 1) * 1440
	_residence_requests[action_id] = {"action_id": action_id, "person_id": person, "source_unit_id": source, "destination_unit_id": destination, "place_id": place, "requested_minute": minute, "boundary_minute": boundary, "effective_minute": -1, "status": "QUEUED", "reason": "", "permission_id": permission["id"], "authorization_basis": permission["basis"]}
	return {"accepted": true, "reason": "RESIDENCE_QUEUED", "boundary_minute": boundary}

## Old day responsibilities finish first. This commits only future residence.
func apply_residence_boundary(world: WorldState) -> int:
	var now := world.game_clock.total_minutes()
	if now % 1440 != 0: return 0
	var applied: int = 0
	var ids := _residence_requests.keys()
	ids.sort()
	for id: String in ids:
		var row := _residence_requests[id] as Dictionary
		if row["status"] not in ["QUEUED", "DEFERRED"] or int(row["boundary_minute"]) > now: continue
		var person := str(row["person_id"])
		var source := str(row["source_unit_id"])
		var target := str(row["destination_unit_id"])
		var reason: String = ""
		if unit_for_person(person) != source: reason = "RESIDENCE_SOURCE_CHANGED"
		elif _residence_permission(world, person, source, target, row["place_id"]).is_empty(): reason = "RESIDENCE_PERMISSION_UNAVAILABLE"
		elif not world.person_overlay.is_at_place(person, row["place_id"]) or (world.person_travel != null and world.person_travel.active(person)): reason = "PERSON_NOT_AT_RESIDENCE_DESTINATION"
		elif population(source) < 1 or int(_named_counts[source]) < 1 or population(target) >= MAX_POPULATION: reason = "POPULATION_CANNOT_ACCEPT_RESIDENCE_TRANSFER"
		elif population(source)-1 < int(_named_counts[source])-1+int(_native_background.get(source, 0)): reason = "NATIVE_BACKGROUND_RESPONSIBILITY_WOULD_BE_LOST"
		if reason.is_empty() and not world.person_overlay.commit_population_residence(self, person, source, target): reason = "HOST_RESIDENCE_COMMIT_UNAVAILABLE"
		if not reason.is_empty():
			row["status"] = "DEFERRED"
			row["reason"] = reason
			row["boundary_minute"] = now+1440
			continue
		_totals[source] = population(source)-1
		_totals[target] = population(target)+1
		_named_counts[source] = int(_named_counts[source])-1
		_named_counts[target] = int(_named_counts[target])+1
		_named[person] = target
		row["status"] = "APPLIED"
		row["reason"] = ""
		row["effective_minute"] = now
		applied += 1
	return applied

func _valid_residence_requests(value: Variant, named: Dictionary, places: Dictionary) -> bool:
	if not value is Dictionary or value.size() > 128: return false
	var paths: Dictionary = {}
	var pending: Dictionary = {}
	for id: Variant in value:
		var row: Variant = value[id]
		if not id is String or not row is Dictionary or not FormalLedgerState.exact_fields(row, ["action_id", "person_id", "source_unit_id", "destination_unit_id", "place_id", "requested_minute", "boundary_minute", "effective_minute", "status", "reason", "permission_id", "authorization_basis"]) or row["action_id"] != id: return false
		for field: String in ["person_id", "source_unit_id", "destination_unit_id", "place_id", "reason", "permission_id"]:
			if not row[field] is String: return false
		if not named.has(row["person_id"]) or not _totals.has(row["source_unit_id"]) or not _totals.has(row["destination_unit_id"]) or row["source_unit_id"] == row["destination_unit_id"] or places.get(row["place_id"], "") != row["destination_unit_id"] or row["authorization_basis"] != "DEVELOPMENT_RESIDENCE_PERMISSION" or row["status"] not in ["QUEUED", "DEFERRED", "APPLIED"]: return false
		if not FormalLedgerState.valid_amount(row["requested_minute"]) or not FormalLedgerState.valid_amount(row["boundary_minute"]) or int(row["boundary_minute"])%1440 != 0 or int(row["boundary_minute"]) <= int(row["requested_minute"]) or typeof(row["effective_minute"]) != TYPE_INT: return false
		var person := str(row["person_id"])
		if row["status"] == "APPLIED":
			if int(row["effective_minute"]) != int(row["boundary_minute"]) or not row["reason"].is_empty(): return false
			if not paths.has(person): paths[person] = []
			paths[person].append(row)
		else:
			if row["effective_minute"] != -1 or pending.has(person) or row["source_unit_id"] != named[person]: return false
			pending[person] = true
	for person: String in paths:
		paths[person].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
		var previous: Dictionary = {}
		for row: Dictionary in paths[person]:
			if not previous.is_empty() and (row["source_unit_id"] != previous["destination_unit_id"] or int(row["requested_minute"]) < int(previous["effective_minute"])): return false
			previous = row
		if previous["destination_unit_id"] != named[person]: return false
	return true

func validate_residence_state(world: WorldState) -> bool:
	var now := world.game_clock.total_minutes()
	if not _place_population_bindings.is_empty() and (world.economy_r1 == null or world.economy_r1.config.get("place_population_bindings", []) != _place_population_bindings): return _fail("Place population binding lacks its explicit economic configuration")
	for row: Dictionary in _residence_requests.values():
		if int(row["requested_minute"]) > now or (row["status"] == "APPLIED" and int(row["effective_minute"]) > now) or (row["status"] != "APPLIED" and int(row["boundary_minute"]) <= now): return _fail("Residence state exceeds its saved clock boundary")
		var permit := _residence_permission(world, row["person_id"], row["source_unit_id"], row["destination_unit_id"], row["place_id"])
		if permit.get("id") != row["permission_id"] or world.economy_r1 == null or not world.economy_r1.valid_residence_request(row): return _fail("Residence operation lacks its configured permission and accepted action")
	return true

func residence_statistics() -> Dictionary:
	var moved: Dictionary = {}
	var pending: int = 0
	for row: Dictionary in _residence_requests.values():
		if row["status"] == "APPLIED": moved[row["person_id"]] = true
		else: pending += 1
	return {"migrated_named_people": moved.size(), "pending_residence_requests": pending, "population_basis": "CURRENT_RESIDENCE_SEPARATE_FROM_PHYSICAL_PRESENCE"}


func present_named_count(unit_id: String, persons: VNextNamedPersonOverlay) -> int:
	var count: int = 0
	for person: String in persons.person_ids():
		var place := persons.current_place(person)
		if persons.is_at_place(person, place) and unit_for_place(place) == unit_id: count += 1
	return count


## A finite explicit place crosswalk can resolve an otherwise unsupported host
## place. It never reassigns an admitted place or changes any population total.
func _prepared_place_population_units(rows: Variant) -> Dictionary:
	if not valid_place_population_bindings(rows): return {}
	var places := _base_places.duplicate(true)
	for row: Dictionary in rows:
		if not places.has(row["place_id"]) or not _totals.has(row["population_unit_id"]) or (not str(places[row["place_id"]]).is_empty() and places[row["place_id"]] != row["population_unit_id"]): return {}
		places[row["place_id"]] = row["population_unit_id"]
	return places

static func valid_place_population_bindings(rows: Variant) -> bool:
	if not rows is Array or rows.size() > 64: return false
	var seen: Dictionary = {}
	for row: Variant in rows:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row, ["place_id", "population_unit_id", "source", "basis", "scope_assumption"]) or row["basis"] != "DEVELOPMENT_PLACE_POPULATION_CROSSWALK": return false
		for key: String in ["place_id", "population_unit_id", "source", "scope_assumption"]:
			if not row[key] is String or row[key].is_empty(): return false
		if seen.has(row["place_id"]): return false
		seen[row["place_id"]] = true
	return true

func prepare_place_population_bindings(rows: Array) -> bool:
	if not _place_population_bindings.is_empty() or not _residence_requests.is_empty(): return _fail("Live population place bindings cannot be replaced")
	var places := _prepared_place_population_units(rows)
	if places.is_empty(): return _fail("Place population binding is unavailable or overlaps an existing unit")
	_places = places
	_place_population_bindings.assign(rows.duplicate(true))
	return true

func matches_place_population_bindings(rows: Array) -> bool:
	return rows == _place_population_bindings
