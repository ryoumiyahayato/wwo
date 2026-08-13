class_name VNextMacroPopulationRecord
extends RefCounted
## One bounded macro population state keyed by an existing place/region ID.
## This record deliberately contains no person, household, labor, economic,
## political, military, or AI state.

const SNAPSHOT_SCHEMA_ID: String = "vnext_macro_population_record_v3"
const LEGACY_SNAPSHOT_SCHEMA_ID: String = "vnext_macro_population_record_v2"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

const AGE_BUCKET_KEYS: PackedStringArray = [
	"under_18",
	"age_18_40",
	"age_41_64",
	"age_65_plus",
]
const SEX_KEYS: PackedStringArray = ["female", "male"]
const URBAN_RURAL_KEYS: PackedStringArray = ["urban", "rural"]
const AGEING_REMAINDER_KEYS: PackedStringArray = [
	"under_18_to_age_18_40",
	"age_18_40_to_age_41_64",
	"age_41_64_to_age_65_plus",
]
const AGEING_DENOMINATORS: Dictionary = {
	"under_18_to_age_18_40": 216,
	"age_18_40_to_age_41_64": 276,
	"age_41_64_to_age_65_plus": 288,
}

var _place_id: String = ""
var _total_population: int = 0
var _age_buckets: Dictionary = {}
var _sex_structure: Dictionary = {}
var _urban_rural: Dictionary = {}
var _ageing_remainders: Dictionary = {}
var _births: int = 0
var _deaths: int = 0
var _external_immigration: int = 0
var _external_emigration: int = 0
## Cursor for the first absolute month that has not been settled yet.
## Absolute month 0 is January 1900.
var _last_settled_period: int = 0


static func create_zero(place_id_value: String) -> VNextMacroPopulationRecord:
	return from_state(place_id_value, {
		"total_population": 0,
		"age_buckets": _zero_buckets(AGE_BUCKET_KEYS),
		"sex_structure": _zero_buckets(SEX_KEYS),
		"urban_rural": _zero_buckets(URBAN_RURAL_KEYS),
	})


static func from_state(
	place_id_value: String, state_value: Dictionary
) -> VNextMacroPopulationRecord:
	if not _is_spatial_key(place_id_value):
		return null
	var candidate_state: Dictionary = state_value.duplicate(true)
	if candidate_state.has("schema_id"):
		var schema_id: Variant = candidate_state.get("schema_id")
		if schema_id != SNAPSHOT_SCHEMA_ID and schema_id != LEGACY_SNAPSHOT_SCHEMA_ID:
			return null
	if candidate_state.has("place_id") and candidate_state.get("place_id") != place_id_value:
		return null
	var has_legacy_migration: bool = (
		candidate_state.has("migration") or candidate_state.has("net_migration")
	)
	var has_explicit_external: bool = (
		candidate_state.has("external_immigration")
		or candidate_state.has("external_emigration")
	)
	if candidate_state.has("migration") and candidate_state.has("net_migration"):
		return null
	if has_legacy_migration and has_explicit_external:
		return null
	if candidate_state.has("migration"):
		candidate_state["net_migration"] = candidate_state.get("migration")
		candidate_state.erase("migration")
	if candidate_state.has("net_migration"):
		var legacy_parts: Dictionary = _legacy_external_parts(
			candidate_state.get("net_migration")
		)
		if legacy_parts.is_empty():
			return null
		candidate_state["external_immigration"] = legacy_parts[
			"external_immigration"
		]
		candidate_state["external_emigration"] = legacy_parts[
			"external_emigration"
		]
		candidate_state.erase("net_migration")
	if (
		candidate_state.has("external_immigration")
		and not candidate_state.has("external_emigration")
	) or (
		candidate_state.has("external_emigration")
		and not candidate_state.has("external_immigration")
	):
		return null
	for optional_field: String in [
		"births",
		"deaths",
		"external_immigration",
		"external_emigration",
		"last_settled_period",
	]:
		if not candidate_state.has(optional_field):
			candidate_state[optional_field] = 0
	if not candidate_state.has("ageing_remainders"):
		candidate_state["ageing_remainders"] = _zero_buckets(AGEING_REMAINDER_KEYS)
	candidate_state["schema_id"] = SNAPSHOT_SCHEMA_ID
	candidate_state["place_id"] = place_id_value

	var record := VNextMacroPopulationRecord.new()
	if not record.restore(candidate_state):
		return null
	return record

func place_id() -> String:
	return _place_id


func total_population() -> int:
	return _total_population


func age_buckets() -> Dictionary:
	return _age_buckets.duplicate(true)


func sex_structure() -> Dictionary:
	return _sex_structure.duplicate(true)


func urban_rural_structure() -> Dictionary:
	return _urban_rural.duplicate(true)


func ageing_remainders() -> Dictionary:
	return _ageing_remainders.duplicate(true)


func working_age_population() -> int:
	return int(_age_buckets.get("age_18_40", 0)) + int(
		_age_buckets.get("age_41_64", 0)
	)


func births() -> int:
	return _births


func deaths() -> int:
	return _deaths


func external_immigration() -> int:
	return _external_immigration


func external_emigration() -> int:
	return _external_emigration


func external_net_migration() -> int:
	return _external_immigration - _external_emigration


## Compatibility alias for the former signed external input.
func net_migration() -> int:
	return external_net_migration()


## Compatibility alias for the former signed external input.
func migration() -> int:
	return external_net_migration()


func last_settled_period() -> int:
	return _last_settled_period


func last_settled_population_period() -> int:
	return _last_settled_period


func age_bucket_population(bucket_name: String) -> int:
	if not AGE_BUCKET_KEYS.has(bucket_name):
		return -1
	return int(_age_buckets.get(bucket_name, -1))


func can_transfer(amount: int) -> bool:
	return (
		is_valid()
		and _is_valid_nonnegative_int(amount)
		and amount <= _total_population
	)


func transfer_composition(amount: int) -> Dictionary:
	if not can_transfer(amount):
		return {}
	var age_parts: Dictionary = _proportional_parts(
		amount, _age_buckets, "age_18_40", true
	)
	var sex_parts: Dictionary = _proportional_parts(
		amount, _sex_structure, "female", true
	)
	var urban_rural_parts: Dictionary = _proportional_parts(
		amount, _urban_rural, "rural", true
	)
	if (
		age_parts.is_empty()
		or sex_parts.is_empty()
		or urban_rural_parts.is_empty()
	):
		return {}
	return {
		"amount": amount,
		"age_buckets": age_parts,
		"sex_structure": sex_parts,
		"urban_rural": urban_rural_parts,
	}


func apply_transfer(composition: Dictionary, removing: bool) -> bool:
	if not is_valid() or composition.size() != 4:
		return false
	for key: String in ["amount", "age_buckets", "sex_structure", "urban_rural"]:
		if not composition.has(key):
			return false
	var normalized_amount: Dictionary = _normalize_nonnegative_integer(
		composition.get("amount")
	)
	var age_parts: Dictionary = _normalize_bucket_dictionary(
		composition.get("age_buckets"), AGE_BUCKET_KEYS
	)
	var sex_parts: Dictionary = _normalize_bucket_dictionary(
		composition.get("sex_structure"), SEX_KEYS
	)
	var urban_rural_parts: Dictionary = _normalize_bucket_dictionary(
		composition.get("urban_rural"), URBAN_RURAL_KEYS
	)
	if (
		normalized_amount.is_empty()
		or age_parts.is_empty()
		or sex_parts.is_empty()
		or urban_rural_parts.is_empty()
	):
		return false
	var amount: int = int(normalized_amount["value"])
	if (
		_sum_buckets(age_parts, AGE_BUCKET_KEYS) != amount
		or _sum_buckets(sex_parts, SEX_KEYS) != amount
		or _sum_buckets(urban_rural_parts, URBAN_RURAL_KEYS) != amount
	):
		return false
	var next_age: Dictionary = (
		_subtract_parts(_age_buckets, age_parts)
		if removing else _add_parts(_age_buckets, age_parts)
	)
	var next_sex: Dictionary = (
		_subtract_parts(_sex_structure, sex_parts)
		if removing else _add_parts(_sex_structure, sex_parts)
	)
	var next_urban_rural: Dictionary = (
		_subtract_parts(_urban_rural, urban_rural_parts)
		if removing else _add_parts(_urban_rural, urban_rural_parts)
	)
	if (
		next_age.is_empty()
		or next_sex.is_empty()
		or next_urban_rural.is_empty()
	):
		return false
	var next_total: int = (
		_total_population - amount if removing else _total_population + amount
	)
	if (
		next_total < 0
		or next_total > MAX_JSON_SAFE_INTEGER
		or not _is_valid_state(
			_place_id,
			next_total,
			next_age,
			next_sex,
			next_urban_rural,
			_ageing_remainders,
			_births,
			_deaths,
			_external_immigration,
			_external_emigration,
			_last_settled_period
		)
	):
		return false
	_total_population = next_total
	_age_buckets = next_age
	_sex_structure = next_sex
	_urban_rural = next_urban_rural
	return true


func is_valid() -> bool:
	return _is_valid_state(
		_place_id,
		_total_population,
		_age_buckets,
		_sex_structure,
		_urban_rural,
		_ageing_remainders,
		_births,
		_deaths,
		_external_immigration,
		_external_emigration,
		_last_settled_period
	)


func structure() -> Dictionary:
	return {
		"place_id": _place_id,
		"total_population": _total_population,
		"age_buckets": age_buckets(),
		"sex_structure": sex_structure(),
		"urban_rural": urban_rural_structure(),
		"ageing_remainders": ageing_remainders(),
		"working_age_population": working_age_population(),
		"births": _births,
		"deaths": _deaths,
		"external_immigration": _external_immigration,
		"external_emigration": _external_emigration,
		"external_net_migration": external_net_migration(),
		# Compatibility projection for callers that only need a signed total.
		"net_migration": external_net_migration(),
		"last_settled_period": _last_settled_period,
	}


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"place_id": _place_id,
		"total_population": _total_population,
		"age_buckets": age_buckets(),
		"sex_structure": sex_structure(),
		"urban_rural": urban_rural_structure(),
		"ageing_remainders": ageing_remainders(),
		"births": _births,
		"deaths": _deaths,
		"external_immigration": _external_immigration,
		"external_emigration": _external_emigration,
		"last_settled_period": _last_settled_period,
	}


func restore(snapshot_value: Dictionary) -> bool:
	# v2 snapshots are accepted only through this explicit signed-external
	# migration conversion; all other schemas remain rejected.
	var candidate_snapshot: Dictionary = snapshot_value.duplicate(true)
	if (
		candidate_snapshot.size() == 11
		and candidate_snapshot.get("schema_id") == LEGACY_SNAPSHOT_SCHEMA_ID
	):
		for legacy_field: String in [
			"schema_id",
			"place_id",
			"total_population",
			"age_buckets",
			"sex_structure",
			"urban_rural",
			"ageing_remainders",
			"births",
			"deaths",
			"net_migration",
			"last_settled_period",
		]:
			if not candidate_snapshot.has(legacy_field):
				return false
		var legacy_parts: Dictionary = _legacy_external_parts(
			candidate_snapshot.get("net_migration")
		)
		if legacy_parts.is_empty():
			return false
		candidate_snapshot.erase("net_migration")
		candidate_snapshot["external_immigration"] = legacy_parts[
			"external_immigration"
		]
		candidate_snapshot["external_emigration"] = legacy_parts[
			"external_emigration"
		]
		candidate_snapshot["schema_id"] = SNAPSHOT_SCHEMA_ID
	if candidate_snapshot.size() != 12:
		return false
	for required_field: String in [
		"schema_id",
		"place_id",
		"total_population",
		"age_buckets",
		"sex_structure",
		"urban_rural",
		"ageing_remainders",
		"births",
		"deaths",
		"external_immigration",
		"external_emigration",
		"last_settled_period",
	]:
		if not candidate_snapshot.has(required_field):
			return false
	if candidate_snapshot.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if typeof(candidate_snapshot.get("place_id")) != TYPE_STRING:
		return false
	var candidate_place_id: String = str(candidate_snapshot.get("place_id"))
	if not _is_spatial_key(candidate_place_id):
		return false

	var normalized_total: Dictionary = _normalize_nonnegative_integer(
		candidate_snapshot.get("total_population")
	)
	var normalized_births: Dictionary = _normalize_nonnegative_integer(
		candidate_snapshot.get("births")
	)
	var normalized_deaths: Dictionary = _normalize_nonnegative_integer(
		candidate_snapshot.get("deaths")
	)
	var normalized_immigration: Dictionary = _normalize_nonnegative_integer(
		candidate_snapshot.get("external_immigration")
	)
	var normalized_emigration: Dictionary = _normalize_nonnegative_integer(
		candidate_snapshot.get("external_emigration")
	)
	var normalized_period: Dictionary = _normalize_nonnegative_integer(
		candidate_snapshot.get("last_settled_period")
	)
	if (
		normalized_total.is_empty()
		or normalized_births.is_empty()
		or normalized_deaths.is_empty()
		or normalized_immigration.is_empty()
		or normalized_emigration.is_empty()
		or normalized_period.is_empty()
	):
		return false

	var normalized_age_buckets: Dictionary = _normalize_bucket_dictionary(
		candidate_snapshot.get("age_buckets"), AGE_BUCKET_KEYS
	)
	var normalized_sex_structure: Dictionary = _normalize_bucket_dictionary(
		candidate_snapshot.get("sex_structure"), SEX_KEYS
	)
	var normalized_urban_rural: Dictionary = _normalize_bucket_dictionary(
		candidate_snapshot.get("urban_rural"), URBAN_RURAL_KEYS
	)
	var normalized_ageing_remainders: Dictionary = _normalize_remainder_dictionary(
		candidate_snapshot.get("ageing_remainders")
	)
	if (
		normalized_age_buckets.is_empty()
		or normalized_sex_structure.is_empty()
		or normalized_urban_rural.is_empty()
		or normalized_ageing_remainders.is_empty()
	):
		return false

	var candidate_total: int = int(normalized_total["value"])
	var candidate_births: int = int(normalized_births["value"])
	var candidate_deaths: int = int(normalized_deaths["value"])
	var candidate_immigration: int = int(normalized_immigration["value"])
	var candidate_emigration: int = int(normalized_emigration["value"])
	var candidate_period: int = int(normalized_period["value"])
	if not _is_valid_state(
		candidate_place_id,
		candidate_total,
		normalized_age_buckets,
		normalized_sex_structure,
		normalized_urban_rural,
		normalized_ageing_remainders,
		candidate_births,
		candidate_deaths,
		candidate_immigration,
		candidate_emigration,
		candidate_period
	):
		return false

	_place_id = candidate_place_id
	_total_population = candidate_total
	_age_buckets = normalized_age_buckets
	_sex_structure = normalized_sex_structure
	_urban_rural = normalized_urban_rural
	_ageing_remainders = normalized_ageing_remainders
	_births = candidate_births
	_deaths = candidate_deaths
	_external_immigration = candidate_immigration
	_external_emigration = candidate_emigration
	_last_settled_period = candidate_period
	return true

func apply_monthly_settlement(
	monthly_births: int,
	monthly_deaths: int,
	monthly_external_immigration: int,
	monthly_external_emigration: int = -1
) -> bool:
	if not is_valid():
		return false
	if not _is_valid_nonnegative_int(monthly_births):
		return false
	if not _is_valid_nonnegative_int(monthly_deaths):
		return false
	var resolved_immigration: int = monthly_external_immigration
	var resolved_emigration: int = monthly_external_emigration
	if monthly_external_emigration == -1:
		var legacy_parts: Dictionary = _legacy_external_parts(
			monthly_external_immigration
		)
		if legacy_parts.is_empty():
			return false
		resolved_immigration = int(legacy_parts["external_immigration"])
		resolved_emigration = int(legacy_parts["external_emigration"])
	if (
		not _is_valid_nonnegative_int(resolved_immigration)
		or not _is_valid_nonnegative_int(resolved_emigration)
	):
		return false
	return _apply_one_month(
		monthly_births,
		monthly_deaths,
		resolved_immigration,
		resolved_emigration
	)


func advance_empty_months(elapsed_months: int) -> bool:
	if not is_valid() or elapsed_months <= 0:
		return false
	if elapsed_months > MAX_JSON_SAFE_INTEGER - _last_settled_period:
		return false

	var next_age: Dictionary = _age_buckets.duplicate()
	var next_ageing_remainders: Dictionary = _ageing_remainders.duplicate()
	for _month_index: int in range(elapsed_months):
		var ageing_result: Dictionary = _age_one_month(
			next_age, next_ageing_remainders
		)
		if ageing_result.is_empty():
			return false
		next_age = ageing_result["age_buckets"] as Dictionary
		next_ageing_remainders = ageing_result["ageing_remainders"] as Dictionary

	if not _is_valid_state(
		_place_id,
		_total_population,
		next_age,
		_sex_structure,
		_urban_rural,
		next_ageing_remainders,
		_births,
		_deaths,
		_external_immigration,
		_external_emigration,
		_last_settled_period + elapsed_months
	):
		return false

	_age_buckets = next_age
	_ageing_remainders = next_ageing_remainders
	_last_settled_period += elapsed_months
	return true


static func normalize_monthly_flow(flow_value: Variant) -> Dictionary:
	if typeof(flow_value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = flow_value as Dictionary
	for raw_key: Variant in source.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		var key: String = str(raw_key)
		if not [
			"births",
			"deaths",
			"external_immigration",
			"external_emigration",
			"net_migration",
			"migration",
		].has(key):
			return {}

	var has_legacy_migration: bool = (
		source.has("net_migration") or source.has("migration")
	)
	if source.has("migration") and source.has("net_migration"):
		return {}
	var has_explicit_external: bool = (
		source.has("external_immigration")
		or source.has("external_emigration")
	)
	if has_legacy_migration and has_explicit_external:
		return {}

	var normalized_births: Dictionary = _normalize_nonnegative_integer(
		source.get("births", 0)
	)
	var normalized_deaths: Dictionary = _normalize_nonnegative_integer(
		source.get("deaths", 0)
	)
	if normalized_births.is_empty() or normalized_deaths.is_empty():
		return {}

	var immigration: int = 0
	var emigration: int = 0
	if has_legacy_migration:
		var legacy_parts: Dictionary = _legacy_external_parts(
			source.get("net_migration", source.get("migration"))
		)
		if legacy_parts.is_empty():
			return {}
		immigration = int(legacy_parts["external_immigration"])
		emigration = int(legacy_parts["external_emigration"])
	elif has_explicit_external:
		var normalized_immigration: Dictionary = (
			_normalize_nonnegative_integer(
				source.get("external_immigration", 0)
			)
		)
		var normalized_emigration: Dictionary = (
			_normalize_nonnegative_integer(
				source.get("external_emigration", 0)
			)
		)
		if (
			normalized_immigration.is_empty()
			or normalized_emigration.is_empty()
		):
			return {}
		immigration = int(normalized_immigration["value"])
		emigration = int(normalized_emigration["value"])

	return {
		"births": int(normalized_births["value"]),
		"deaths": int(normalized_deaths["value"]),
		"external_immigration": immigration,
		"external_emigration": emigration,
	}


static func _legacy_external_parts(value: Variant) -> Dictionary:
	var normalized: Dictionary = _normalize_signed_integer(value)
	if normalized.is_empty():
		return {}
	var signed_value: int = int(normalized["value"])
	if signed_value >= 0:
		return {
			"external_immigration": signed_value,
			"external_emigration": 0,
		}
	return {
		"external_immigration": 0,
		"external_emigration": -signed_value,
	}


func _apply_one_month(
	monthly_births: int,
	monthly_deaths: int,
	monthly_external_immigration: int,
	monthly_external_emigration: int
) -> bool:
	if monthly_births > MAX_JSON_SAFE_INTEGER - _total_population:
		return false
	var after_births_total: int = _total_population + monthly_births
	if monthly_deaths > after_births_total:
		return false
	var after_deaths_total: int = after_births_total - monthly_deaths
	if monthly_external_immigration > (
		MAX_JSON_SAFE_INTEGER - after_deaths_total
	):
		return false
	var after_immigration_total: int = (
		after_deaths_total + monthly_external_immigration
	)
	if monthly_external_emigration > after_immigration_total:
		return false
	if _last_settled_period >= MAX_JSON_SAFE_INTEGER:
		return false
	if monthly_births > MAX_JSON_SAFE_INTEGER - _births:
		return false
	if monthly_deaths > MAX_JSON_SAFE_INTEGER - _deaths:
		return false
	if monthly_external_immigration > (
		MAX_JSON_SAFE_INTEGER - _external_immigration
	):
		return false
	if monthly_external_emigration > (
		MAX_JSON_SAFE_INTEGER - _external_emigration
	):
		return false

	var ageing_result: Dictionary = _age_one_month(
		_age_buckets, _ageing_remainders
	)
	if ageing_result.is_empty():
		return false
	var next_age: Dictionary = ageing_result["age_buckets"] as Dictionary
	var next_ageing_remainders: Dictionary = (
		ageing_result["ageing_remainders"] as Dictionary
	)
	var next_sex: Dictionary = _sex_structure.duplicate()
	var next_urban_rural: Dictionary = _urban_rural.duplicate()
	var birth_age: Dictionary = _zero_buckets(AGE_BUCKET_KEYS)
	var birth_sex: Dictionary = _zero_buckets(SEX_KEYS)
	var birth_urban_rural: Dictionary = _zero_buckets(URBAN_RURAL_KEYS)
	birth_age["under_18"] = monthly_births
	var male_births: int = int(floor(float(monthly_births) / 2.0))
	birth_sex["male"] = male_births
	birth_sex["female"] = monthly_births - male_births
	birth_urban_rural = _proportional_parts(
		monthly_births, _urban_rural, "rural", false
	)
	next_age = _add_parts(next_age, birth_age)
	next_sex = _add_parts(next_sex, birth_sex)
	next_urban_rural = _add_parts(next_urban_rural, birth_urban_rural)
	if next_age.is_empty() or next_sex.is_empty() or next_urban_rural.is_empty():
		return false

	var death_age: Dictionary = _proportional_parts(
		monthly_deaths, next_age, "under_18", true
	)
	var death_sex: Dictionary = _proportional_parts(
		monthly_deaths, next_sex, "female", true
	)
	var death_urban_rural: Dictionary = _proportional_parts(
		monthly_deaths, next_urban_rural, "rural", true
	)
	if (
		death_age.is_empty()
		or death_sex.is_empty()
		or death_urban_rural.is_empty()
	):
		return false
	next_age = _subtract_parts(next_age, death_age)
	next_sex = _subtract_parts(next_sex, death_sex)
	next_urban_rural = _subtract_parts(next_urban_rural, death_urban_rural)
	if next_age.is_empty() or next_sex.is_empty() or next_urban_rural.is_empty():
		return false

	var immigration_age: Dictionary = _proportional_parts(
		monthly_external_immigration, next_age, "age_18_40", false
	)
	var immigration_sex: Dictionary = _proportional_parts(
		monthly_external_immigration, next_sex, "female", false
	)
	var immigration_urban_rural: Dictionary = _proportional_parts(
		monthly_external_immigration, next_urban_rural, "rural", false
	)
	if (
		immigration_age.is_empty()
		or immigration_sex.is_empty()
		or immigration_urban_rural.is_empty()
	):
		return false
	next_age = _add_parts(next_age, immigration_age)
	next_sex = _add_parts(next_sex, immigration_sex)
	next_urban_rural = _add_parts(next_urban_rural, immigration_urban_rural)
	if next_age.is_empty() or next_sex.is_empty() or next_urban_rural.is_empty():
		return false

	var emigration_age: Dictionary = _proportional_parts(
		monthly_external_emigration, next_age, "age_18_40", true
	)
	var emigration_sex: Dictionary = _proportional_parts(
		monthly_external_emigration, next_sex, "female", true
	)
	var emigration_urban_rural: Dictionary = _proportional_parts(
		monthly_external_emigration, next_urban_rural, "rural", true
	)
	if (
		emigration_age.is_empty()
		or emigration_sex.is_empty()
		or emigration_urban_rural.is_empty()
	):
		return false
	next_age = _subtract_parts(next_age, emigration_age)
	next_sex = _subtract_parts(next_sex, emigration_sex)
	next_urban_rural = _subtract_parts(next_urban_rural, emigration_urban_rural)
	if next_age.is_empty() or next_sex.is_empty() or next_urban_rural.is_empty():
		return false

	var next_total: int = after_immigration_total - monthly_external_emigration
	if not _is_valid_state(
		_place_id,
		next_total,
		next_age,
		next_sex,
		next_urban_rural,
		next_ageing_remainders,
		_births + monthly_births,
		_deaths + monthly_deaths,
		_external_immigration + monthly_external_immigration,
		_external_emigration + monthly_external_emigration,
		_last_settled_period + 1
	):
		return false

	_total_population = next_total
	_age_buckets = next_age
	_sex_structure = next_sex
	_urban_rural = next_urban_rural
	_ageing_remainders = next_ageing_remainders
	_births += monthly_births
	_deaths += monthly_deaths
	_external_immigration += monthly_external_immigration
	_external_emigration += monthly_external_emigration
	_last_settled_period += 1
	return true


static func _is_valid_state(
	place_id_value: String,
	total_population_value: int,
	age_buckets_value: Dictionary,
	sex_structure_value: Dictionary,
	urban_rural_value: Dictionary,
	ageing_remainders_value: Dictionary,
	births_value: int,
	deaths_value: int,
	external_immigration_value: int,
	external_emigration_value: int,
	last_settled_period_value: int
) -> bool:
	if not _is_spatial_key(place_id_value):
		return false
	if not _is_valid_nonnegative_int(total_population_value):
		return false
	if not _is_valid_nonnegative_int(births_value):
		return false
	if not _is_valid_nonnegative_int(deaths_value):
		return false
	if not _is_valid_nonnegative_int(external_immigration_value):
		return false
	if not _is_valid_nonnegative_int(external_emigration_value):
		return false
	if not _is_valid_nonnegative_int(last_settled_period_value):
		return false
	if not _has_valid_bucket_values(age_buckets_value, AGE_BUCKET_KEYS):
		return false
	if not _has_valid_bucket_values(sex_structure_value, SEX_KEYS):
		return false
	if not _has_valid_bucket_values(urban_rural_value, URBAN_RURAL_KEYS):
		return false
	if not _has_valid_remainder_values(ageing_remainders_value):
		return false
	return (
		_sum_buckets(age_buckets_value, AGE_BUCKET_KEYS) == total_population_value
		and _sum_buckets(sex_structure_value, SEX_KEYS) == total_population_value
		and _sum_buckets(urban_rural_value, URBAN_RURAL_KEYS) == total_population_value
	)

static func _has_valid_bucket_values(
	bucket_value: Dictionary, expected_keys: PackedStringArray
) -> bool:
	if not _has_exact_keys(bucket_value, expected_keys):
		return false
	for key: String in expected_keys:
		var value: Variant = bucket_value.get(key)
		if typeof(value) != TYPE_INT:
			return false
		if not _is_valid_nonnegative_int(int(value)):
			return false
	return true


static func _normalize_bucket_dictionary(
	bucket_value: Variant, expected_keys: PackedStringArray
) -> Dictionary:
	if typeof(bucket_value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = bucket_value as Dictionary
	if not _has_exact_keys(source, expected_keys):
		return {}
	var normalized: Dictionary = {}
	for key: String in expected_keys:
		var value: Dictionary = _normalize_nonnegative_integer(source.get(key))
		if value.is_empty():
			return {}
		normalized[key] = int(value["value"])
	return normalized


static func _has_exact_keys(value: Dictionary, expected_keys: PackedStringArray) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not value.has(key):
			return false
	return true


static func _sum_buckets(value: Dictionary, keys: PackedStringArray) -> int:
	var result: int = 0
	for key: String in keys:
		var bucket_value: int = int(value.get(key, 0))
		if bucket_value > MAX_JSON_SAFE_INTEGER - result:
			return -1
		result += bucket_value
	return result


static func _zero_buckets(keys: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for key: String in keys:
		result[key] = 0
	return result


static func _age_one_month(
	age_buckets_value: Dictionary, ageing_remainders_value: Dictionary
) -> Dictionary:
	if not _has_valid_bucket_values(age_buckets_value, AGE_BUCKET_KEYS):
		return {}
	if not _has_valid_remainder_values(ageing_remainders_value):
		return {}

	var under_step: Dictionary = _ageing_step(
		int(age_buckets_value["under_18"]),
		int(ageing_remainders_value["under_18_to_age_18_40"]),
		int(AGEING_DENOMINATORS["under_18_to_age_18_40"])
	)
	var age_18_step: Dictionary = _ageing_step(
		int(age_buckets_value["age_18_40"]),
		int(ageing_remainders_value["age_18_40_to_age_41_64"]),
		int(AGEING_DENOMINATORS["age_18_40_to_age_41_64"])
	)
	var age_41_step: Dictionary = _ageing_step(
		int(age_buckets_value["age_41_64"]),
		int(ageing_remainders_value["age_41_64_to_age_65_plus"]),
		int(AGEING_DENOMINATORS["age_41_64_to_age_65_plus"])
	)
	if under_step.is_empty() or age_18_step.is_empty() or age_41_step.is_empty():
		return {}

	var under_outflow: int = int(under_step["moved"])
	var age_18_outflow: int = int(age_18_step["moved"])
	var age_41_outflow: int = int(age_41_step["moved"])
	var next_age: Dictionary = age_buckets_value.duplicate()
	next_age["under_18"] = int(age_buckets_value["under_18"]) - under_outflow
	next_age["age_18_40"] = (
		int(age_buckets_value["age_18_40"])
		+ under_outflow
		- age_18_outflow
	)
	next_age["age_41_64"] = (
		int(age_buckets_value["age_41_64"])
		+ age_18_outflow
		- age_41_outflow
	)
	next_age["age_65_plus"] = (
		int(age_buckets_value["age_65_plus"]) + age_41_outflow
	)
	var next_remainders: Dictionary = ageing_remainders_value.duplicate()
	next_remainders["under_18_to_age_18_40"] = int(under_step["remainder"])
	next_remainders["age_18_40_to_age_41_64"] = int(age_18_step["remainder"])
	next_remainders["age_41_64_to_age_65_plus"] = int(age_41_step["remainder"])
	if not _has_valid_bucket_values(next_age, AGE_BUCKET_KEYS):
		return {}
	return {
		"age_buckets": next_age,
		"ageing_remainders": next_remainders,
	}


static func _ageing_step(
	bucket_count: int, remainder: int, denominator: int
) -> Dictionary:
	if (
		bucket_count < 0
		or remainder < 0
		or remainder >= denominator
		or denominator <= 0
	):
		return {}
	if bucket_count == 0:
		return {"moved": 0, "remainder": 0}
	var carry: int = bucket_count % denominator
	var moved: int = int((bucket_count - carry) / denominator)
	var combined_remainder: int = carry + remainder
	if combined_remainder >= denominator:
		moved += 1
		combined_remainder -= denominator
	if moved > bucket_count:
		return {}
	return {"moved": moved, "remainder": combined_remainder}


static func _has_valid_remainder_values(
	remainder_value: Dictionary
) -> bool:
	if not _has_exact_keys(remainder_value, AGEING_REMAINDER_KEYS):
		return false
	for key: String in AGEING_REMAINDER_KEYS:
		var value: Variant = remainder_value.get(key)
		if typeof(value) != TYPE_INT:
			return false
		var denominator: int = int(AGEING_DENOMINATORS[key])
		if int(value) < 0 or int(value) >= denominator:
			return false
	return true


static func _normalize_remainder_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = value as Dictionary
	if not _has_exact_keys(source, AGEING_REMAINDER_KEYS):
		return {}
	var result: Dictionary = {}
	for key: String in AGEING_REMAINDER_KEYS:
		var normalized: Dictionary = _normalize_nonnegative_integer(source.get(key))
		if normalized.is_empty():
			return {}
		var remainder: int = int(normalized["value"])
		if remainder >= int(AGEING_DENOMINATORS[key]):
			return {}
		result[key] = remainder
	return result


static func _add_parts(source: Dictionary, additions: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate()
	for raw_key: Variant in additions.keys():
		var key: String = str(raw_key)
		if not result.has(key):
			return {}
		var source_value: int = int(result[key])
		var addition: int = int(additions[key])
		if addition > MAX_JSON_SAFE_INTEGER - source_value:
			return {}
		result[key] = source_value + addition
	return result


static func _subtract_parts(source: Dictionary, removals: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate()
	for raw_key: Variant in removals.keys():
		var key: String = str(raw_key)
		if not result.has(key):
			return {}
		var remaining: int = int(result[key]) - int(removals[key])
		if remaining < 0:
			return {}
		result[key] = remaining
	return result


static func _proportional_parts(
	amount: int, basis: Dictionary, fallback_key: String, removing: bool
) -> Dictionary:
	if amount < 0 or amount > MAX_JSON_SAFE_INTEGER:
		return {}
	var keys: Array[String] = []
	for raw_key: Variant in basis.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		keys.append(str(raw_key))
	keys.sort()
	if not keys.has(fallback_key):
		return {}
	var result: Dictionary = _zero_buckets(PackedStringArray(keys))
	if amount == 0:
		return result
	var total: int = _sum_buckets(basis, PackedStringArray(keys))
	if total < 0 or (removing and amount > total):
		return {}
	if total == 0:
		if removing:
			return {}
		result[fallback_key] = amount
		return result

	var fractions: Dictionary = {}
	var allocated: int = 0
	for key: String in keys:
		var basis_value: int = int(basis.get(key, 0))
		var raw_share: float = float(amount) * float(basis_value) / float(total)
		var whole_share: int = int(floor(raw_share))
		if removing and whole_share > basis_value:
			whole_share = basis_value
		result[key] = whole_share
		allocated += whole_share
		fractions[key] = raw_share - floor(raw_share)
	var remainder: int = amount - allocated
	while remainder > 0:
		var selected_key: String = ""
		var selected_fraction: float = -1.0
		for key: String in keys:
			if removing and int(result[key]) >= int(basis[key]):
				continue
			var fraction: float = float(fractions[key])
			if (
				selected_key.is_empty()
				or fraction > selected_fraction
				or (is_equal_approx(fraction, selected_fraction) and key < selected_key)
			):
				selected_key = key
				selected_fraction = fraction
		if selected_key.is_empty():
			return {}
		result[selected_key] = int(result[selected_key]) + 1
		remainder -= 1
	return result


static func _normalize_nonnegative_integer(candidate_value: Variant) -> Dictionary:
	var candidate_type: int = typeof(candidate_value)
	var candidate_int: int = 0
	if candidate_type == TYPE_INT:
		candidate_int = int(candidate_value)
	elif candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float):
			return {}
		if candidate_float < 0.0 or candidate_float > float(MAX_JSON_SAFE_INTEGER):
			return {}
		if candidate_float != floor(candidate_float):
			return {}
		candidate_int = int(candidate_float)
	else:
		return {}
	if not _is_valid_nonnegative_int(candidate_int):
		return {}
	return {"value": candidate_int}


static func _normalize_signed_integer(candidate_value: Variant) -> Dictionary:
	var candidate_type: int = typeof(candidate_value)
	var candidate_int: int = 0
	if candidate_type == TYPE_INT:
		candidate_int = int(candidate_value)
	elif candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float):
			return {}
		if candidate_float < -float(MAX_JSON_SAFE_INTEGER):
			return {}
		if candidate_float > float(MAX_JSON_SAFE_INTEGER):
			return {}
		if candidate_float != floor(candidate_float):
			return {}
		candidate_int = int(candidate_float)
	else:
		return {}
	if not _is_valid_signed_int(candidate_int):
		return {}
	return {"value": candidate_int}


static func _is_valid_nonnegative_int(candidate_value: int) -> bool:
	return candidate_value >= 0 and candidate_value <= MAX_JSON_SAFE_INTEGER


static func _is_valid_signed_int(candidate_value: int) -> bool:
	return (
		candidate_value >= -MAX_JSON_SAFE_INTEGER
		and candidate_value <= MAX_JSON_SAFE_INTEGER
	)


static func _is_spatial_key(candidate_value: String) -> bool:
	if (
		VNextStableId.is_valid(candidate_value)
		and VNextStableId.kind_of(candidate_value) == "place"
	):
		return true
	if not candidate_value.begins_with("region:"):
		return false
	return _is_valid_local_id(candidate_value.substr("region:".length()))


static func _is_valid_local_id(candidate_local_id: String) -> bool:
	if candidate_local_id.is_empty():
		return false
	for character_index: int in candidate_local_id.length():
		var candidate_character: String = candidate_local_id.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(candidate_character):
			return false
	return true
