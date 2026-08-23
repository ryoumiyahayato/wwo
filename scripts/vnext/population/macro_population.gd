class_name VNextMacroPopulation
extends RefCounted
## Slow, PopulationUnit-keyed population aggregates. It is intentionally independent
## from the person roster and from the vNext runtime clock.

const SNAPSHOT_SCHEMA_ID: String = "vnext_macro_population_v4"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991
const MAX_SETTLEMENT_MONTHS_PER_CALL: int = 120_000
const BASE_YEAR: int = 1900

var _initialized: bool = false
var _geography_authority: VNextPopulationUnitCatalog = null
## Population identity is independent of every geographic identifier space.
var _known_place_ids: Dictionary = {}
var _ordered_place_ids: Array[String] = []
var _records: Dictionary = {}
var _lineage_by_unit_id: Dictionary = {}
var _population_revision: int = 0
var _provider_revision: String = ""
var _validated_revision: int = -1
var _validated_result: bool = false


func _init(
	geography_authority: VNextPopulationUnitCatalog = null,
	initial_place_ids: Array[String] = [],
	provider_revision: String = ""
) -> void:
	if geography_authority != null and not initial_place_ids.is_empty():
		initialize(geography_authority, initial_place_ids, provider_revision)


static func create(
	geography_authority: VNextPopulationUnitCatalog = null,
	initial_place_ids: Array[String] = [],
	provider_revision: String = ""
) -> VNextMacroPopulation:
	var population := VNextMacroPopulation.new()
	if not population.initialize(geography_authority, initial_place_ids, provider_revision):
		return null
	return population


func initialize(
	geography_authority: VNextPopulationUnitCatalog,
	place_ids: Array[String],
	provider_revision: String = ""
) -> bool:
	if _initialized:
		return false
	if geography_authority == null or not geography_authority.is_loaded():
		return false
	var candidate_known_ids: Dictionary = {}
	var candidate_ordered_ids: Array[String] = []
	var candidate_records: Dictionary = {}
	for raw_place_id: Variant in place_ids:
		if typeof(raw_place_id) != TYPE_STRING:
			return false
		var place_id: String = str(raw_place_id)
		if not _authority_has_population_unit_id(geography_authority, place_id):
			return false
		if candidate_known_ids.has(place_id):
			return false
		var record: VNextMacroPopulationRecord = (
			VNextMacroPopulationRecord.create_zero(place_id)
		)
		if record == null or not record.is_valid():
			return false
		candidate_known_ids[place_id] = true
		candidate_ordered_ids.append(place_id)
		candidate_records[place_id] = record
	if candidate_known_ids.is_empty():
		return false
	candidate_ordered_ids.sort()

	_initialized = true
	_geography_authority = geography_authority
	_known_place_ids = candidate_known_ids
	_ordered_place_ids = candidate_ordered_ids
	_records = candidate_records
	_provider_revision = provider_revision if not provider_revision.is_empty() else geography_authority.revision()
	for unit_id: String in candidate_ordered_ids:
		_lineage_by_unit_id[unit_id] = VNextFactProvenance.unavailable(
			"uninitialized_population_state", _provider_revision
		)
	_population_revision = 1
	_validated_revision = -1
	return true


func is_valid() -> bool:
	if _validated_revision == _population_revision:
		return _validated_result
	_validated_result = _validate_full_state()
	_validated_revision = _population_revision
	return _validated_result


func _validate_full_state() -> bool:
	if (
		not _initialized
		or _geography_authority == null
		or not _geography_authority.is_loaded()
		or _known_place_ids.is_empty()
	):
		return false
	if (
		_known_place_ids.size() != _records.size()
		or _ordered_place_ids.size() != _known_place_ids.size()
	):
		return false
	var ordered_seen: Dictionary = {}
	for place_id: String in _ordered_place_ids:
		if ordered_seen.has(place_id) or not _known_place_ids.has(place_id):
			return false
		ordered_seen[place_id] = true
	for raw_place_id: Variant in _known_place_ids.keys():
		if typeof(raw_place_id) != TYPE_STRING:
			return false
		var place_id: String = str(raw_place_id)
		if (
			not _authority_has_population_unit_id(_geography_authority, place_id)
			or not _records.has(place_id)
		):
			return false
		var record_value: Variant = _records.get(place_id)
		if not record_value is VNextMacroPopulationRecord:
			return false
		var record: VNextMacroPopulationRecord = record_value as VNextMacroPopulationRecord
		if (
			not record.is_valid() or record.population_unit_id() != place_id
			or not _lineage_by_unit_id.has(place_id)
			or not VNextFactProvenance.is_valid(_lineage_by_unit_id[place_id] as Dictionary)
		):
			return false
	return (
		ordered_seen.size() == _known_place_ids.size()
		and _lineage_by_unit_id.size() == _known_place_ids.size()
		and _population_revision > 0
		and not _provider_revision.is_empty()
	)



func set_initial_state(
	place_id: String,
	state_value: Dictionary,
	lineage: Dictionary = {}
) -> bool:
	if (
		not is_valid()
		or not _known_place_ids.has(place_id)
		or not _authority_has_population_unit_id(_geography_authority, place_id)
		or _has_elapsed_settlement()
	):
		return false
	var candidate: VNextMacroPopulationRecord = (
		VNextMacroPopulationRecord.from_state(place_id, state_value)
	)
	if candidate == null or not candidate.is_valid():
		return false
	var candidate_lineage: Dictionary = (
		lineage.duplicate(true)
		if not lineage.is_empty()
		else VNextFactProvenance.unavailable("unspecified_population_initialization", _provider_revision)
	)
	if not VNextFactProvenance.is_valid(candidate_lineage):
		return false
	_records[place_id] = candidate
	_lineage_by_unit_id[place_id] = candidate_lineage
	_mark_mutated()
	return true


func known_place_ids() -> Array[String]:
	return _ordered_place_ids.duplicate()


func population_unit_ids() -> Array[String]:
	return _ordered_place_ids.duplicate()


func place_ids() -> Array[String]:
	return known_place_ids()


func has_place(place_id: String) -> bool:
	return is_valid() and _known_place_ids.has(place_id)


func has_population_unit(unit_id: String) -> bool:
	return is_valid() and _known_place_ids.has(unit_id)


func record_count() -> int:
	return _records.size()


func population_at(place_id: String) -> int:
	if not is_valid():
		return -1
	var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
	if record == null:
		return -1
	return record.total_population()


func working_age_at(place_id: String) -> int:
	if not is_valid():
		return -1
	var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
	if record == null:
		return -1
	return record.working_age_population()


func age_bucket_at(place_id: String, bucket_name: String) -> int:
	if not is_valid():
		return -1
	var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
	if record == null:
		return -1
	return record.age_bucket_population(bucket_name)


func age_18_40_at(place_id: String) -> int:
	return age_bucket_at(place_id, "age_18_40")


func structure_at(place_id: String) -> Dictionary:
	if not is_valid():
		return {}
	var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
	if record == null:
		return {}
	return record.structure()


func record_snapshot_at(place_id: String) -> Dictionary:
	if not is_valid():
		return {}
	var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
	if record == null:
		return {}
	return {
		"population_unit_id": place_id,
		"population_revision": _population_revision,
		"provider_revision": _provider_revision,
		"catalog_revision": _geography_authority.revision(),
		"lineage": (_lineage_by_unit_id[place_id] as Dictionary).duplicate(true),
		"state": record.snapshot(),
	}


func population_revision() -> int:
	return _population_revision


func provider_revision() -> String:
	return _provider_revision


func last_settled_period_at(place_id: String) -> int:
	if not is_valid():
		return -1
	var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
	if record == null:
		return -1
	return record.last_settled_period()


func last_settled_population_period_at(place_id: String) -> int:
	return last_settled_period_at(place_id)


func next_settlement_year_month_at(place_id: String) -> Dictionary:
	var period: int = last_settled_period_at(place_id)
	if period < 0:
		return {}
	return year_month_from_absolute_month(period)


func aggregate_population(place_ids: Array[String]) -> int:
	if not is_valid():
		return -1
	var normalized_ids: Array[String] = _normalize_query_ids(place_ids)
	if normalized_ids.is_empty() and not place_ids.is_empty():
		return -1
	var result: int = 0
	for place_id: String in normalized_ids:
		var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
		if record == null:
			return -1
		var population_value: int = record.total_population()
		if population_value < 0 or population_value > MAX_JSON_SAFE_INTEGER - result:
			return -1
		result += population_value
	return result


func aggregate_structure(place_ids: Array[String]) -> Dictionary:
	if not is_valid():
		return {}
	var normalized_ids: Array[String] = _normalize_query_ids(place_ids)
	if normalized_ids.is_empty() and not place_ids.is_empty():
		return {}
	var result: Dictionary = _empty_aggregate_structure()
	var first_period: int = -1
	for place_id: String in normalized_ids:
		var record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
		if record == null:
			return {}
		if first_period < 0:
			first_period = record.last_settled_period()
		elif first_period != record.last_settled_period():
			result["periods_aligned"] = false
		var structure_value: Dictionary = record.structure()
		if not _add_aggregate_structure(result, structure_value):
			return {}
	if result.get("periods_aligned", true):
		result["last_settled_period"] = 0 if first_period < 0 else first_period
	else:
		result["last_settled_period"] = -1
	return result


func settle(
	elapsed_months: int,
	monthly_flows_by_place: Dictionary = {},
	internal_migration_flows: Array = []
) -> bool:
	return settle_elapsed_months(
		elapsed_months, monthly_flows_by_place, internal_migration_flows
	)


func settle_elapsed_months(
	elapsed_months: int,
	monthly_flows_by_place: Dictionary = {},
	internal_migration_flows: Array = []
) -> bool:
	return _settle_records(
		elapsed_months,
		-1,
		monthly_flows_by_place,
		false,
		internal_migration_flows
	)


func settle_absolute_months(
	start_absolute_month: int,
	elapsed_months: int,
	monthly_flows_by_place: Dictionary = {},
	internal_migration_flows: Array = []
) -> bool:
	if not _is_valid_absolute_month(start_absolute_month):
		return false
	return _settle_records(
		elapsed_months,
		start_absolute_month,
		monthly_flows_by_place,
		true,
		internal_migration_flows
	)


func settle_year_month(
	start_year: int,
	start_month: int,
	elapsed_months: int,
	monthly_flows_by_place: Dictionary = {},
	internal_migration_flows: Array = []
) -> bool:
	var start_absolute_month: int = absolute_month_from_year_month(
		start_year, start_month
	)
	if start_absolute_month < 0:
		return false
	return settle_absolute_months(
		start_absolute_month,
		elapsed_months,
		monthly_flows_by_place,
		internal_migration_flows
	)



func settle_internal_migration(
	internal_migration_flows: Array
) -> bool:
	if (
		not is_valid()
		or not _has_elapsed_settlement()
		or not _records_are_period_aligned(_records, true)
	):
		return false
	var normalized_flows: Array = _normalize_internal_migration_flows(
		internal_migration_flows
	)
	if (
		normalized_flows.is_empty()
		and not internal_migration_flows.is_empty()
	):
		return false
	var candidate_records: Dictionary = _clone_records()
	if candidate_records.is_empty():
		return false
	if not _apply_internal_migration_batch(
		candidate_records, normalized_flows
	):
		return false
	_records = candidate_records
	_mark_mutated()
	return true



func snapshot() -> Dictionary:
	if not is_valid():
		return {}
	var records: Array[Dictionary] = []
	for place_id: String in known_place_ids():
		var record_view: Dictionary = record_snapshot_at(place_id)
		if record_view.is_empty():
			return {}
		records.append(record_view)
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"known_population_unit_ids": population_unit_ids(),
		"population_revision": _population_revision,
		"provider_revision": _provider_revision,
		"catalog_revision": _geography_authority.revision(),
		"records": records,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if not is_valid():
		return false
	var candidate_snapshot: Dictionary = snapshot_value.duplicate(true)
	if candidate_snapshot.size() != 6:
		return false
	for required_field: String in [
		"schema_id", "known_population_unit_ids", "population_revision",
		"provider_revision", "catalog_revision", "records",
	]:
		if not candidate_snapshot.has(required_field):
			return false
	if candidate_snapshot.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	var candidate_revision: int = int(candidate_snapshot.get("population_revision", -1))
	if (
		candidate_revision <= 0
		or str(candidate_snapshot.get("provider_revision", "")) != _provider_revision
		or str(candidate_snapshot.get("catalog_revision", "")) != _geography_authority.revision()
	):
		return false
	var candidate_known_ids: Dictionary = _normalize_place_id_array(
		candidate_snapshot.get("known_population_unit_ids")
	)
	if candidate_known_ids.is_empty():
		return false
	for raw_place_id: Variant in candidate_known_ids.keys():
		if not _authority_has_population_unit_id(
			_geography_authority, str(raw_place_id)
		):
			return false
	if candidate_known_ids != _known_place_ids:
		return false
	if typeof(candidate_snapshot.get("records")) != TYPE_ARRAY:
		return false
	var raw_records: Array = candidate_snapshot.get("records") as Array
	if raw_records.size() != candidate_known_ids.size():
		return false

	var candidate_records: Dictionary = {}
	var candidate_lineage: Dictionary = {}
	for raw_record: Variant in raw_records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record_view := raw_record as Dictionary
		for field_name: String in [
			"population_unit_id", "population_revision", "provider_revision",
			"catalog_revision", "lineage", "state",
		]:
			if not record_view.has(field_name):
				return false
		var view_unit_id: String = str(record_view.get("population_unit_id", ""))
		var lineage: Dictionary = record_view.get("lineage", {}) as Dictionary
		if (
			int(record_view.get("population_revision", -1)) != candidate_revision
			or str(record_view.get("provider_revision", "")) != _provider_revision
			or str(record_view.get("catalog_revision", "")) != _geography_authority.revision()
			or not VNextFactProvenance.is_valid(lineage)
			or not record_view.get("state", {}) is Dictionary
		):
			return false
		var candidate_record := VNextMacroPopulationRecord.new()
		if not candidate_record.restore(record_view.get("state", {}) as Dictionary):
			return false
		var place_id: String = candidate_record.population_unit_id()
		if place_id != view_unit_id or not candidate_known_ids.has(place_id) or candidate_records.has(place_id):
			return false
		candidate_records[place_id] = candidate_record
		candidate_lineage[place_id] = lineage.duplicate(true)
	if candidate_records.size() != candidate_known_ids.size():
		return false
	for raw_place_id: Variant in candidate_known_ids.keys():
		if not candidate_records.has(str(raw_place_id)):
			return false

	_records = candidate_records
	_lineage_by_unit_id = candidate_lineage
	_population_revision = candidate_revision
	_validated_revision = -1
	return true


static func absolute_month_from_year_month(year: int, month: int) -> int:
	if year < BASE_YEAR or month < 1 or month > 12:
		return -1
	var year_offset: int = year - BASE_YEAR
	if year_offset > int(MAX_JSON_SAFE_INTEGER / 12):
		return -1
	var result: int = year_offset * 12 + month - 1
	if not _is_valid_absolute_month(result):
		return -1
	return result


static func year_month_from_absolute_month(absolute_month: int) -> Dictionary:
	if not _is_valid_absolute_month(absolute_month):
		return {}
	var year_offset: int = int(floor(float(absolute_month) / 12.0))
	return {
		"year": BASE_YEAR + year_offset,
		"month": absolute_month % 12 + 1,
	}


func _settle_records(
	elapsed_months: int,
	start_absolute_month: int,
	monthly_flows_by_place: Dictionary,
	enforce_start_period: bool,
	internal_migration_flows: Array
) -> bool:
	if not is_valid():
		return false
	if elapsed_months <= 0 or elapsed_months > MAX_SETTLEMENT_MONTHS_PER_CALL:
		return false
	if enforce_start_period and not _is_valid_absolute_month(start_absolute_month):
		return false
	if enforce_start_period:
		if start_absolute_month > MAX_JSON_SAFE_INTEGER - elapsed_months:
			return false
	var normalized_flows: Dictionary = _normalize_flows(monthly_flows_by_place)
	if normalized_flows.is_empty() and not monthly_flows_by_place.is_empty():
		return false
	var normalized_internal_flows: Array = _normalize_internal_migration_flows(
		internal_migration_flows
	)
	if (
		normalized_internal_flows.is_empty()
		and not internal_migration_flows.is_empty()
	):
		return false

	var candidate_records: Dictionary = {}
	for place_id: String in known_place_ids():
		var source_record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
		var candidate_record := VNextMacroPopulationRecord.new()
		if source_record == null or not candidate_record.restore(source_record.snapshot()):
			return false
		if enforce_start_period and candidate_record.last_settled_period() != start_absolute_month:
			return false
		var flow: Dictionary = normalized_flows.get(place_id, {
			"births": 0,
			"deaths": 0,
			"external_immigration": 0,
			"external_emigration": 0,
		})
		var births: int = int(flow["births"])
		var deaths: int = int(flow["deaths"])
		var external_immigration: int = int(
			flow["external_immigration"]
		)
		var external_emigration: int = int(
			flow["external_emigration"]
		)
		var has_nonzero_flow: bool = (
			births != 0
			or deaths != 0
			or external_immigration != 0
			or external_emigration != 0
		)
		var settled: bool
		if not has_nonzero_flow:
			settled = candidate_record.advance_empty_months(elapsed_months)
		else:
			settled = true
			for _month_index: int in range(elapsed_months):
				if not candidate_record.apply_monthly_settlement(
					births,
					deaths,
					external_immigration,
					external_emigration
				):
					settled = false
					break
		if not settled:
			return false
		candidate_records[place_id] = candidate_record

	if not _apply_internal_migration_batch(
		candidate_records, normalized_internal_flows
	):
		return false
	_records = candidate_records
	_mark_mutated(elapsed_months)
	return true


func _normalize_flows(monthly_flows_by_place: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for raw_place_id: Variant in monthly_flows_by_place.keys():
		if typeof(raw_place_id) != TYPE_STRING:
			return {}
		var place_id: String = str(raw_place_id)
		if (
			not _known_place_ids.has(place_id)
			or not _authority_has_population_unit_id(_geography_authority, place_id)
		):
			return {}
		var flow: Dictionary = VNextMacroPopulationRecord.normalize_monthly_flow(
			monthly_flows_by_place.get(place_id)
		)
		if flow.is_empty():
			return {}
		normalized[place_id] = flow
	return normalized


func _trusted_record_at(place_id: String) -> VNextMacroPopulationRecord:
	if not _records.has(place_id):
		return null
	var record_value: Variant = _records.get(place_id)
	if not record_value is VNextMacroPopulationRecord:
		return null
	return record_value as VNextMacroPopulationRecord


func _authority_has_population_unit_id(
	authority: VNextPopulationUnitCatalog, candidate: String
) -> bool:
	if authority == null or not authority.is_loaded():
		return false
	return VNextPopulationUnitId.is_valid(candidate) and authority.has_population_unit(candidate)


func _clone_records() -> Dictionary:
	var candidate_records: Dictionary = {}
	for place_id: String in known_place_ids():
		var source_record: VNextMacroPopulationRecord = _trusted_record_at(place_id)
		var candidate_record := VNextMacroPopulationRecord.new()
		if (
			source_record == null
			or not candidate_record.restore(source_record.snapshot())
		):
			return {}
		candidate_records[place_id] = candidate_record
	return candidate_records


func _normalize_internal_migration_flows(flows: Array) -> Array:
	var by_pair: Dictionary = {}
	for raw_flow: Variant in flows:
		if typeof(raw_flow) != TYPE_DICTIONARY:
			return []
		var source: Dictionary = raw_flow as Dictionary
		if source.size() != 3:
			return []
		for required_key: String in [
			"origin_population_unit_id", "destination_population_unit_id", "amount"
		]:
			if not source.has(required_key):
				return []
		if (
			typeof(source.get("origin_population_unit_id")) != TYPE_STRING
			or typeof(source.get("destination_population_unit_id")) != TYPE_STRING
		):
			return []
		var origin: String = str(source.get("origin_population_unit_id"))
		var destination: String = str(source.get("destination_population_unit_id"))
		if (
			not _known_place_ids.has(origin)
			or not _known_place_ids.has(destination)
			or not _authority_has_population_unit_id(_geography_authority, origin)
			or not _authority_has_population_unit_id(_geography_authority, destination)
			or origin == destination
		):
			return []
		var amount: int = _normalize_flow_amount(source.get("amount"))
		if amount < 0:
			return []
		var pair_key: String = origin + "\n" + destination
		var previous: int = int(by_pair.get(pair_key, 0))
		if amount > MAX_JSON_SAFE_INTEGER - previous:
			return []
		by_pair[pair_key] = previous + amount
	var normalized: Array = []
	var pair_keys: Array[String] = []
	for raw_key: Variant in by_pair.keys():
		pair_keys.append(str(raw_key))
	pair_keys.sort()
	for pair_key: String in pair_keys:
		var separator: int = pair_key.find("\n")
		normalized.append({
			"origin_population_unit_id": pair_key.left(separator),
			"destination_population_unit_id": pair_key.substr(separator + 1),
			"amount": int(by_pair[pair_key]),
		})
	return normalized


func _normalize_flow_amount(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		var integer_value: int = int(value)
		return integer_value if (
			integer_value >= 0
			and integer_value <= MAX_JSON_SAFE_INTEGER
		) else -1
	if typeof(value) != TYPE_FLOAT:
		return -1
	var float_value: float = float(value)
	if (
		not is_finite(float_value)
		or float_value < 0.0
		or float_value > float(MAX_JSON_SAFE_INTEGER)
		or float_value != floor(float_value)
	):
		return -1
	return int(float_value)


func _apply_internal_migration_batch(
	candidate_records: Dictionary, normalized_flows: Array
) -> bool:
	if normalized_flows.is_empty():
		return true
	if not _records_are_period_aligned(candidate_records, true):
		return false
	var source_working: Dictionary = {}
	var compositions_by_origin: Dictionary = {}
	var incoming_by_destination: Dictionary = {}
	for flow: Dictionary in normalized_flows:
		var origin: String = str(flow["origin_population_unit_id"])
		var destination: String = str(flow["destination_population_unit_id"])
		var amount: int = int(flow["amount"])
		var working_value: Variant = source_working.get(origin)
		var working: VNextMacroPopulationRecord
		if working_value == null:
			var source_value: Variant = candidate_records.get(origin)
			if not source_value is VNextMacroPopulationRecord:
				return false
			working = VNextMacroPopulationRecord.new()
			if not working.restore(
				(source_value as VNextMacroPopulationRecord).snapshot()
			):
				return false
			source_working[origin] = working
		else:
			if not working_value is VNextMacroPopulationRecord:
				return false
			working = working_value as VNextMacroPopulationRecord
		var composition: Dictionary = working.transfer_composition(amount)
		if composition.is_empty() or not working.apply_transfer(composition, true):
			return false
		if not compositions_by_origin.has(origin):
			compositions_by_origin[origin] = []
		(compositions_by_origin[origin] as Array).append(composition)
		if not incoming_by_destination.has(destination):
			incoming_by_destination[destination] = []
		(incoming_by_destination[destination] as Array).append(composition)

	var origins: Array[String] = []
	for raw_origin: Variant in compositions_by_origin.keys():
		origins.append(str(raw_origin))
	origins.sort()
	for origin: String in origins:
		var target_value: Variant = candidate_records.get(origin)
		if not target_value is VNextMacroPopulationRecord:
			return false
		var target: VNextMacroPopulationRecord = target_value as VNextMacroPopulationRecord
		for composition: Dictionary in compositions_by_origin[origin]:
			if not target.apply_transfer(composition, true):
				return false

	var destinations: Array[String] = []
	for raw_destination: Variant in incoming_by_destination.keys():
		destinations.append(str(raw_destination))
	destinations.sort()
	for destination: String in destinations:
		var target_value: Variant = candidate_records.get(destination)
		if not target_value is VNextMacroPopulationRecord:
			return false
		var target: VNextMacroPopulationRecord = target_value as VNextMacroPopulationRecord
		var merged: Dictionary = {}
		for composition: Dictionary in incoming_by_destination[destination]:
			if merged.is_empty():
				merged = composition.duplicate(true)
			elif not _add_transfer_composition(merged, composition):
				return false
		if not target.apply_transfer(merged, false):
			return false
	return true


func _add_transfer_composition(target: Dictionary, addition: Dictionary) -> bool:
	var target_amount: int = int(target.get("amount", -1))
	var addition_amount: int = int(addition.get("amount", -1))
	if (
		target_amount < 0
		or addition_amount < 0
		or addition_amount > MAX_JSON_SAFE_INTEGER - target_amount
	):
		return false
	target["amount"] = target_amount + addition_amount
	for axis: String in ["age_buckets", "sex_structure", "urban_rural"]:
		var target_axis: Dictionary = target.get(axis, {}) as Dictionary
		var addition_axis: Dictionary = addition.get(axis, {}) as Dictionary
		if target_axis.is_empty() or addition_axis.is_empty():
			return false
		for raw_key: Variant in target_axis.keys():
			var key: String = str(raw_key)
			var current: int = int(target_axis[key])
			var amount: int = int(addition_axis.get(key, -1))
			if amount < 0 or amount > MAX_JSON_SAFE_INTEGER - current:
				return false
			target_axis[key] = current + amount
		target[axis] = target_axis
	return true


func _records_are_period_aligned(
	candidate_records: Dictionary, require_started: bool
) -> bool:
	var expected_period: int = -1
	for raw_record: Variant in candidate_records.values():
		if not raw_record is VNextMacroPopulationRecord:
			return false
		var record: VNextMacroPopulationRecord = raw_record as VNextMacroPopulationRecord
		var period: int = record.last_settled_period()
		if require_started and period <= 0:
			return false
		if expected_period < 0:
			expected_period = period
		elif expected_period != period:
			return false
	return expected_period >= 0


func _has_elapsed_settlement() -> bool:
	for raw_record: Variant in _records.values():
		if not raw_record is VNextMacroPopulationRecord:
			return true
		var record: VNextMacroPopulationRecord = raw_record as VNextMacroPopulationRecord
		if record.last_settled_period() > 0:
			return true
	return false


func _normalize_query_ids(place_ids: Array[String]) -> Array[String]:
	var normalized: Array[String] = []
	var seen: Dictionary = {}
	for raw_place_id: Variant in place_ids:
		if typeof(raw_place_id) != TYPE_STRING:
			return []
		var place_id: String = str(raw_place_id)
		if not _records.has(place_id) or seen.has(place_id):
			return []
		seen[place_id] = true
		normalized.append(place_id)
	return normalized


func _normalize_place_id_array(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	var result: Dictionary = {}
	for raw_place_id: Variant in value as Array:
		if typeof(raw_place_id) != TYPE_STRING:
			return {}
		var place_id: String = str(raw_place_id)
		if not VNextPopulationUnitId.is_valid(place_id):
			return {}
		if result.has(place_id):
			return {}
		result[place_id] = true
	return result


func _empty_aggregate_structure() -> Dictionary:
	return {
		"total_population": 0,
		"age_buckets": VNextMacroPopulationRecord._zero_buckets(
			VNextMacroPopulationRecord.AGE_BUCKET_KEYS
		),
		"sex_structure": VNextMacroPopulationRecord._zero_buckets(
			VNextMacroPopulationRecord.SEX_KEYS
		),
		"urban_rural": VNextMacroPopulationRecord._zero_buckets(
			VNextMacroPopulationRecord.URBAN_RURAL_KEYS
		),
		"working_age_population": 0,
		"births": 0,
		"deaths": 0,
		"external_immigration": 0,
		"external_emigration": 0,
		"external_net_migration": 0,
		"net_migration": 0,
		"last_settled_period": 0,
		"periods_aligned": true,
	}


func _add_aggregate_structure(result: Dictionary, value: Dictionary) -> bool:
	for field_name: String in ["total_population", "working_age_population", "births", "deaths"]:
		var current: int = int(result[field_name])
		var addition: int = int(value[field_name])
		if addition > MAX_JSON_SAFE_INTEGER - current:
			return false
		result[field_name] = current + addition
	for migration_field: String in [
		"external_immigration",
		"external_emigration",
	]:
		var current_migration: int = int(result[migration_field])
		var migration_addition: int = int(value[migration_field])
		if migration_addition > MAX_JSON_SAFE_INTEGER - current_migration:
			return false
		result[migration_field] = current_migration + migration_addition
	result["external_net_migration"] = (
		int(result["external_immigration"])
		- int(result["external_emigration"])
	)
	result["net_migration"] = result["external_net_migration"]
	for structure_name: String in ["age_buckets", "sex_structure", "urban_rural"]:
		var target: Dictionary = result[structure_name] as Dictionary
		var source: Dictionary = value[structure_name] as Dictionary
		for raw_key: Variant in target.keys():
			var key: String = str(raw_key)
			var current_bucket: int = int(target[key])
			var addition_bucket: int = int(source[key])
			if addition_bucket > MAX_JSON_SAFE_INTEGER - current_bucket:
				return false
			target[key] = current_bucket + addition_bucket
	return true


static func _is_valid_absolute_month(absolute_month: int) -> bool:
	return absolute_month >= 0 and absolute_month <= MAX_JSON_SAFE_INTEGER


func _mark_mutated(delta: int = 1) -> void:
	_population_revision += maxi(1, delta)
	_validated_revision = -1
