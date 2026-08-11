class_name VNextMacroPopulation
extends RefCounted
## Slow, place-keyed population aggregates. It is intentionally independent
## from the person roster and from the vNext runtime clock.

const SNAPSHOT_SCHEMA_ID: String = "vnext_macro_population_v1"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991
const MAX_SETTLEMENT_MONTHS_PER_CALL: int = 120_000
const BASE_YEAR: int = 1900

var _initialized: bool = false
## This is an external key contract, not a population-owned geography model.
var _known_place_ids: Dictionary = {}
var _records: Dictionary = {}


func _init(initial_place_ids: Array[String] = []) -> void:
	if not initial_place_ids.is_empty():
		initialize(initial_place_ids)


static func create(initial_place_ids: Array[String] = []) -> VNextMacroPopulation:
	var population := VNextMacroPopulation.new()
	if not population.initialize(initial_place_ids):
		return null
	return population


func initialize(place_ids: Array[String]) -> bool:
	var candidate_known_ids: Dictionary = {}
	var candidate_records: Dictionary = {}
	for raw_place_id: Variant in place_ids:
		if typeof(raw_place_id) != TYPE_STRING:
			return false
		var place_id: String = str(raw_place_id)
		if not VNextMacroPopulationRecord._is_spatial_key(place_id):
			return false
		if candidate_known_ids.has(place_id):
			return false
		var record: VNextMacroPopulationRecord = (
			VNextMacroPopulationRecord.create_zero(place_id)
		)
		if record == null or not record.is_valid():
			return false
		candidate_known_ids[place_id] = true
		candidate_records[place_id] = record
	if candidate_known_ids.is_empty():
		return false

	_initialized = true
	_known_place_ids = candidate_known_ids
	_records = candidate_records
	return true


func is_valid() -> bool:
	if not _initialized or _known_place_ids.is_empty():
		return false
	if _known_place_ids.size() != _records.size():
		return false
	for raw_place_id: Variant in _known_place_ids.keys():
		if typeof(raw_place_id) != TYPE_STRING:
			return false
		var place_id: String = str(raw_place_id)
		if not _records.has(place_id):
			return false
		var record_value: Variant = _records.get(place_id)
		if not record_value is VNextMacroPopulationRecord:
			return false
		var record: VNextMacroPopulationRecord = record_value as VNextMacroPopulationRecord
		if not record.is_valid() or record.place_id() != place_id:
			return false
	return true


func register_place(place_id: String, initial_state: Dictionary = {}) -> bool:
	if not VNextMacroPopulationRecord._is_spatial_key(place_id):
		return false
	if _known_place_ids.has(place_id):
		return false
	var record: VNextMacroPopulationRecord
	if initial_state.is_empty():
		record = VNextMacroPopulationRecord.create_zero(place_id)
	else:
		record = VNextMacroPopulationRecord.from_state(place_id, initial_state)
	if record == null or not record.is_valid():
		return false
	_known_place_ids[place_id] = true
	_records[place_id] = record
	_initialized = true
	return true


func set_initial_state(place_id: String, state_value: Dictionary) -> bool:
	if not is_valid() or not _known_place_ids.has(place_id):
		return false
	var candidate: VNextMacroPopulationRecord = (
		VNextMacroPopulationRecord.from_state(place_id, state_value)
	)
	if candidate == null or not candidate.is_valid():
		return false
	_records[place_id] = candidate
	return true


func known_place_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_place_id: Variant in _known_place_ids.keys():
		result.append(str(raw_place_id))
	result.sort()
	return result


func place_ids() -> Array[String]:
	return known_place_ids()


func has_place(place_id: String) -> bool:
	return is_valid() and _known_place_ids.has(place_id)


func record_count() -> int:
	return _records.size()


func population_at(place_id: String) -> int:
	var record: VNextMacroPopulationRecord = _record_at(place_id)
	if record == null:
		return -1
	return record.total_population()


func working_age_at(place_id: String) -> int:
	var record: VNextMacroPopulationRecord = _record_at(place_id)
	if record == null:
		return -1
	return record.working_age_population()


func age_bucket_at(place_id: String, bucket_name: String) -> int:
	var record: VNextMacroPopulationRecord = _record_at(place_id)
	if record == null:
		return -1
	return record.age_bucket_population(bucket_name)


func age_18_40_at(place_id: String) -> int:
	return age_bucket_at(place_id, "age_18_40")


func structure_at(place_id: String) -> Dictionary:
	var record: VNextMacroPopulationRecord = _record_at(place_id)
	if record == null:
		return {}
	return record.structure()


func record_snapshot_at(place_id: String) -> Dictionary:
	var record: VNextMacroPopulationRecord = _record_at(place_id)
	if record == null:
		return {}
	return record.snapshot()


func last_settled_period_at(place_id: String) -> int:
	var record: VNextMacroPopulationRecord = _record_at(place_id)
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
	var normalized_ids: Array[String] = _normalize_query_ids(place_ids)
	if normalized_ids.is_empty() and not place_ids.is_empty():
		return -1
	var result: int = 0
	for place_id: String in normalized_ids:
		var population_value: int = population_at(place_id)
		if population_value < 0 or population_value > MAX_JSON_SAFE_INTEGER - result:
			return -1
		result += population_value
	return result


func aggregate_structure(place_ids: Array[String]) -> Dictionary:
	var normalized_ids: Array[String] = _normalize_query_ids(place_ids)
	if normalized_ids.is_empty() and not place_ids.is_empty():
		return {}
	var result: Dictionary = _empty_aggregate_structure()
	var first_period: int = -1
	for place_id: String in normalized_ids:
		var record: VNextMacroPopulationRecord = _record_at(place_id)
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
	elapsed_months: int, monthly_flows_by_place: Dictionary = {}
) -> bool:
	return settle_elapsed_months(elapsed_months, monthly_flows_by_place)


func settle_elapsed_months(
	elapsed_months: int, monthly_flows_by_place: Dictionary = {}
) -> bool:
	return _settle_records(elapsed_months, -1, monthly_flows_by_place, false)


func settle_absolute_months(
	start_absolute_month: int,
	elapsed_months: int,
	monthly_flows_by_place: Dictionary = {}
) -> bool:
	if not _is_valid_absolute_month(start_absolute_month):
		return false
	return _settle_records(
		elapsed_months, start_absolute_month, monthly_flows_by_place, true
	)


func settle_year_month(
	start_year: int,
	start_month: int,
	elapsed_months: int,
	monthly_flows_by_place: Dictionary = {}
) -> bool:
	var start_absolute_month: int = absolute_month_from_year_month(
		start_year, start_month
	)
	if start_absolute_month < 0:
		return false
	return settle_absolute_months(
		start_absolute_month, elapsed_months, monthly_flows_by_place
	)


func settle_place(
	place_id: String,
	elapsed_months: int,
	monthly_births: int = 0,
	monthly_deaths: int = 0,
	monthly_net_migration: int = 0,
	start_absolute_month: int = -1
) -> bool:
	if not has_place(place_id):
		return false
	var flows: Dictionary = {
		place_id: {
			"births": monthly_births,
			"deaths": monthly_deaths,
			"net_migration": monthly_net_migration,
		}
	}
	if start_absolute_month < 0:
		return settle_elapsed_months(elapsed_months, flows)
	return settle_absolute_months(start_absolute_month, elapsed_months, flows)


func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for place_id: String in known_place_ids():
		var record: VNextMacroPopulationRecord = _record_at(place_id)
		if record == null:
			continue
		records.append(record.snapshot())
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"known_place_ids": known_place_ids(),
		"records": records,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 3:
		return false
	for required_field: String in ["schema_id", "known_place_ids", "records"]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	var candidate_known_ids: Dictionary = _normalize_place_id_array(
		snapshot_value.get("known_place_ids")
	)
	if candidate_known_ids.is_empty():
		return false
	if _initialized and candidate_known_ids != _known_place_ids:
		return false
	if typeof(snapshot_value.get("records")) != TYPE_ARRAY:
		return false
	var raw_records: Array = snapshot_value.get("records") as Array
	if raw_records.size() != candidate_known_ids.size():
		return false

	var candidate_records: Dictionary = {}
	for raw_record: Variant in raw_records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var candidate_record := VNextMacroPopulationRecord.new()
		if not candidate_record.restore(raw_record as Dictionary):
			return false
		var place_id: String = candidate_record.place_id()
		if not candidate_known_ids.has(place_id) or candidate_records.has(place_id):
			return false
		candidate_records[place_id] = candidate_record
	if candidate_records.size() != candidate_known_ids.size():
		return false
	for raw_place_id: Variant in candidate_known_ids.keys():
		if not candidate_records.has(str(raw_place_id)):
			return false

	_initialized = true
	_known_place_ids = candidate_known_ids
	_records = candidate_records
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
	enforce_start_period: bool
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

	var candidate_records: Dictionary = {}
	for place_id: String in known_place_ids():
		var source_record: VNextMacroPopulationRecord = _record_at(place_id)
		var candidate_record := VNextMacroPopulationRecord.new()
		if source_record == null or not candidate_record.restore(source_record.snapshot()):
			return false
		if enforce_start_period and candidate_record.last_settled_period() != start_absolute_month:
			return false
		var flow: Dictionary = normalized_flows.get(place_id, {
			"births": 0,
			"deaths": 0,
			"net_migration": 0,
		})
		var births: int = int(flow["births"])
		var deaths: int = int(flow["deaths"])
		var net_migration: int = int(flow["net_migration"])
		var has_nonzero_flow: bool = births != 0 or deaths != 0 or net_migration != 0
		var settled: bool
		if not has_nonzero_flow:
			settled = candidate_record.advance_empty_months(elapsed_months)
		else:
			settled = true
			for _month_index: int in range(elapsed_months):
				if not candidate_record.apply_monthly_settlement(
					births, deaths, net_migration
				):
					settled = false
					break
		if not settled:
			return false
		candidate_records[place_id] = candidate_record

	_records = candidate_records
	return true


func _normalize_flows(monthly_flows_by_place: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for raw_place_id: Variant in monthly_flows_by_place.keys():
		if typeof(raw_place_id) != TYPE_STRING:
			return {}
		var place_id: String = str(raw_place_id)
		if not _known_place_ids.has(place_id):
			return {}
		var flow: Dictionary = VNextMacroPopulationRecord.normalize_monthly_flow(
			monthly_flows_by_place.get(place_id)
		)
		if flow.is_empty():
			return {}
		normalized[place_id] = flow
	return normalized


func _record_at(place_id: String) -> VNextMacroPopulationRecord:
	if not is_valid() or not _records.has(place_id):
		return null
	var record_value: Variant = _records.get(place_id)
	if not record_value is VNextMacroPopulationRecord:
		return null
	return record_value as VNextMacroPopulationRecord


func _normalize_query_ids(place_ids: Array[String]) -> Array[String]:
	var normalized: Array[String] = []
	for raw_place_id: Variant in place_ids:
		if typeof(raw_place_id) != TYPE_STRING:
			return []
		var place_id: String = str(raw_place_id)
		if not _records.has(place_id) or normalized.has(place_id):
			return []
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
		if not VNextMacroPopulationRecord._is_spatial_key(place_id):
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
	var current_migration: int = int(result["net_migration"])
	var migration_addition: int = int(value["net_migration"])
	if migration_addition >= 0:
		if current_migration > MAX_JSON_SAFE_INTEGER - migration_addition:
			return false
	else:
		if current_migration < -MAX_JSON_SAFE_INTEGER - migration_addition:
			return false
	result["net_migration"] = current_migration + migration_addition
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
