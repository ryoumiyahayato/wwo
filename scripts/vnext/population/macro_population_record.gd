class_name VNextMacroPopulationRecord
extends RefCounted
## One bounded macro population state keyed by an existing place/region ID.
## This record deliberately contains no person, household, labor, economic,
## political, military, or AI state.

const SNAPSHOT_SCHEMA_ID: String = "vnext_macro_population_record_v1"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

const AGE_BUCKET_KEYS: PackedStringArray = [
	"under_18",
	"age_18_40",
	"age_41_64",
	"age_65_plus",
]
const SEX_KEYS: PackedStringArray = ["female", "male"]
const URBAN_RURAL_KEYS: PackedStringArray = ["urban", "rural"]

var _place_id: String = ""
var _total_population: int = 0
var _age_buckets: Dictionary = {}
var _sex_structure: Dictionary = {}
var _urban_rural: Dictionary = {}
var _births: int = 0
var _deaths: int = 0
var _net_migration: int = 0
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
	if candidate_state.has("schema_id") and candidate_state.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return null
	if candidate_state.has("place_id") and candidate_state.get("place_id") != place_id_value:
		return null
	if candidate_state.has("migration"):
		if candidate_state.has("net_migration"):
			return null
		candidate_state["net_migration"] = candidate_state.get("migration")
		candidate_state.erase("migration")
	for optional_field: String in ["births", "deaths", "net_migration", "last_settled_period"]:
		if not candidate_state.has(optional_field):
			candidate_state[optional_field] = 0
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


func working_age_population() -> int:
	return int(_age_buckets.get("age_18_40", 0)) + int(
		_age_buckets.get("age_41_64", 0)
	)


func births() -> int:
	return _births


func deaths() -> int:
	return _deaths


func net_migration() -> int:
	return _net_migration


func migration() -> int:
	return _net_migration


func last_settled_period() -> int:
	return _last_settled_period


func last_settled_population_period() -> int:
	return _last_settled_period


func age_bucket_population(bucket_name: String) -> int:
	if not AGE_BUCKET_KEYS.has(bucket_name):
		return -1
	return int(_age_buckets.get(bucket_name, -1))


func is_valid() -> bool:
	return _is_valid_state(
		_place_id,
		_total_population,
		_age_buckets,
		_sex_structure,
		_urban_rural,
		_births,
		_deaths,
		_net_migration,
		_last_settled_period
	)


func structure() -> Dictionary:
	return {
		"place_id": _place_id,
		"total_population": _total_population,
		"age_buckets": age_buckets(),
		"sex_structure": sex_structure(),
		"urban_rural": urban_rural_structure(),
		"working_age_population": working_age_population(),
		"births": _births,
		"deaths": _deaths,
		"net_migration": _net_migration,
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
		"births": _births,
		"deaths": _deaths,
		"net_migration": _net_migration,
		"last_settled_period": _last_settled_period,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 10:
		return false
	for required_field: String in [
		"schema_id",
		"place_id",
		"total_population",
		"age_buckets",
		"sex_structure",
		"urban_rural",
		"births",
		"deaths",
		"net_migration",
		"last_settled_period",
	]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if typeof(snapshot_value.get("place_id")) != TYPE_STRING:
		return false
	var candidate_place_id: String = str(snapshot_value.get("place_id"))
	if not _is_spatial_key(candidate_place_id):
		return false

	var normalized_total: Dictionary = _normalize_nonnegative_integer(
		snapshot_value.get("total_population")
	)
	var normalized_births: Dictionary = _normalize_nonnegative_integer(
		snapshot_value.get("births")
	)
	var normalized_deaths: Dictionary = _normalize_nonnegative_integer(
		snapshot_value.get("deaths")
	)
	var normalized_migration: Dictionary = _normalize_signed_integer(
		snapshot_value.get("net_migration")
	)
	var normalized_period: Dictionary = _normalize_nonnegative_integer(
		snapshot_value.get("last_settled_period")
	)
	if (
		normalized_total.is_empty()
		or normalized_births.is_empty()
		or normalized_deaths.is_empty()
		or normalized_migration.is_empty()
		or normalized_period.is_empty()
	):
		return false

	var normalized_age_buckets: Dictionary = _normalize_bucket_dictionary(
		snapshot_value.get("age_buckets"), AGE_BUCKET_KEYS
	)
	var normalized_sex_structure: Dictionary = _normalize_bucket_dictionary(
		snapshot_value.get("sex_structure"), SEX_KEYS
	)
	var normalized_urban_rural: Dictionary = _normalize_bucket_dictionary(
		snapshot_value.get("urban_rural"), URBAN_RURAL_KEYS
	)
	if normalized_age_buckets.is_empty() or normalized_sex_structure.is_empty():
		return false
	if normalized_urban_rural.is_empty():
		return false

	var candidate_total: int = int(normalized_total["value"])
	var candidate_births: int = int(normalized_births["value"])
	var candidate_deaths: int = int(normalized_deaths["value"])
	var candidate_migration: int = int(normalized_migration["value"])
	var candidate_period: int = int(normalized_period["value"])
	if not _is_valid_state(
		candidate_place_id,
		candidate_total,
		normalized_age_buckets,
		normalized_sex_structure,
		normalized_urban_rural,
		candidate_births,
		candidate_deaths,
		candidate_migration,
		candidate_period
	):
		return false

	_place_id = candidate_place_id
	_total_population = candidate_total
	_age_buckets = normalized_age_buckets
	_sex_structure = normalized_sex_structure
	_urban_rural = normalized_urban_rural
	_births = candidate_births
	_deaths = candidate_deaths
	_net_migration = candidate_migration
	_last_settled_period = candidate_period
	return true


func apply_monthly_settlement(
	monthly_births: int, monthly_deaths: int, monthly_net_migration: int
) -> bool:
	if not is_valid():
		return false
	if not _is_valid_nonnegative_int(monthly_births):
		return false
	if not _is_valid_nonnegative_int(monthly_deaths):
		return false
	if not _is_valid_signed_int(monthly_net_migration):
		return false
	return _apply_one_month(monthly_births, monthly_deaths, monthly_net_migration)


func advance_empty_months(elapsed_months: int) -> bool:
	if not is_valid() or elapsed_months <= 0:
		return false
	if elapsed_months > MAX_JSON_SAFE_INTEGER - _last_settled_period:
		return false
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
		if not ["births", "deaths", "net_migration", "migration"].has(key):
			return {}
	if source.has("migration") and source.has("net_migration"):
		return {}

	var normalized_births: Dictionary = _normalize_nonnegative_integer(
		source.get("births", 0)
	)
	var normalized_deaths: Dictionary = _normalize_nonnegative_integer(
		source.get("deaths", 0)
	)
	var normalized_migration: Dictionary = _normalize_signed_integer(
		source.get("net_migration", source.get("migration", 0))
	)
	if normalized_births.is_empty() or normalized_deaths.is_empty():
		return {}
	if normalized_migration.is_empty():
		return {}
	return {
		"births": int(normalized_births["value"]),
		"deaths": int(normalized_deaths["value"]),
		"net_migration": int(normalized_migration["value"]),
	}


func _apply_one_month(
	monthly_births: int, monthly_deaths: int, monthly_net_migration: int
) -> bool:
	if monthly_births > MAX_JSON_SAFE_INTEGER - _total_population:
		return false
	var after_births_total: int = _total_population + monthly_births
	if monthly_deaths > after_births_total:
		return false
	var after_deaths_total: int = after_births_total - monthly_deaths
	if monthly_net_migration > 0:
		if monthly_net_migration > MAX_JSON_SAFE_INTEGER - after_deaths_total:
			return false
	else:
		var outbound_migration: int = -monthly_net_migration
		if outbound_migration > after_deaths_total:
			return false
	if _last_settled_period >= MAX_JSON_SAFE_INTEGER:
		return false
	if monthly_births > MAX_JSON_SAFE_INTEGER - _births:
		return false
	if monthly_deaths > MAX_JSON_SAFE_INTEGER - _deaths:
		return false
	if monthly_net_migration >= 0:
		if _net_migration > MAX_JSON_SAFE_INTEGER - monthly_net_migration:
			return false
	else:
		if _net_migration < -MAX_JSON_SAFE_INTEGER - monthly_net_migration:
			return false

	var next_age: Dictionary = _age_buckets.duplicate()
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

	var migration_amount: int = abs(monthly_net_migration)
	var migration_age: Dictionary = _proportional_parts(
		migration_amount, next_age, "age_18_40", monthly_net_migration < 0
	)
	var migration_sex: Dictionary = _proportional_parts(
		migration_amount, next_sex, "female", monthly_net_migration < 0
	)
	var migration_urban_rural: Dictionary = _proportional_parts(
		migration_amount, next_urban_rural, "rural", monthly_net_migration < 0
	)
	if (
		migration_age.is_empty()
		or migration_sex.is_empty()
		or migration_urban_rural.is_empty()
	):
		return false
	if monthly_net_migration > 0:
		next_age = _add_parts(next_age, migration_age)
		next_sex = _add_parts(next_sex, migration_sex)
		next_urban_rural = _add_parts(next_urban_rural, migration_urban_rural)
	else:
		next_age = _subtract_parts(next_age, migration_age)
		next_sex = _subtract_parts(next_sex, migration_sex)
		next_urban_rural = _subtract_parts(next_urban_rural, migration_urban_rural)
	if next_age.is_empty() or next_sex.is_empty() or next_urban_rural.is_empty():
		return false

	var next_total: int = after_deaths_total + monthly_net_migration
	if not _is_valid_state(
		_place_id,
		next_total,
		next_age,
		next_sex,
		next_urban_rural,
		_births + monthly_births,
		_deaths + monthly_deaths,
		_net_migration + monthly_net_migration,
		_last_settled_period + 1
	):
		return false

	_total_population = next_total
	_age_buckets = next_age
	_sex_structure = next_sex
	_urban_rural = next_urban_rural
	_births += monthly_births
	_deaths += monthly_deaths
	_net_migration += monthly_net_migration
	_last_settled_period += 1
	return true


static func _is_valid_state(
	place_id_value: String,
	total_population_value: int,
	age_buckets_value: Dictionary,
	sex_structure_value: Dictionary,
	urban_rural_value: Dictionary,
	births_value: int,
	deaths_value: int,
	net_migration_value: int,
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
	if not _is_valid_signed_int(net_migration_value):
		return false
	if not _is_valid_nonnegative_int(last_settled_period_value):
		return false
	if not _has_valid_bucket_values(age_buckets_value, AGE_BUCKET_KEYS):
		return false
	if not _has_valid_bucket_values(sex_structure_value, SEX_KEYS):
		return false
	if not _has_valid_bucket_values(urban_rural_value, URBAN_RURAL_KEYS):
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
