class_name VNextLaborSnapshot
extends RefCounted
## Immutable daily labor projection owned by Population's snapshot boundary.
##
## The source model has working-age and urban/rural marginals, but no
## authoritative occupation or skill axis. V1 therefore projects working-age
## people proportionally across rural and urban locations and keeps
## skilled_industrial at zero. Economy may apply later participation or job
## matching rules without changing Population truth.

const SNAPSHOT_SCHEMA_ID: String = "vnext_population_labor_snapshot_v1"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991
const LABOR_CATEGORIES: PackedStringArray = [
	"rural",
	"urban_unskilled",
	"skilled_industrial",
]

var _initialized: bool = false
var _settlement_period: int = -1
var _source_population_period: int = -1
var _covered_population: int = 0
var _economically_available_working_population: int = 0
var _regions: Array[Dictionary] = []


static func create(
	settlement_period: int,
	source_population_period: int,
	region_records: Array[Dictionary],
	covered_population: int,
	economically_available_working_population: int
) -> VNextLaborSnapshot:
	var snapshot := VNextLaborSnapshot.new()
	if not snapshot._configure(
		settlement_period,
		source_population_period,
		region_records,
		covered_population,
		economically_available_working_population
	):
		return null
	return snapshot


func _configure(
	settlement_period: int,
	source_population_period: int,
	region_records: Array[Dictionary],
	covered_population: int,
	economically_available_working_population: int
) -> bool:
	if (
		settlement_period < 0
		or source_population_period < 0
		or covered_population < 0
		or economically_available_working_population < 0
		or covered_population > MAX_JSON_SAFE_INTEGER
		or economically_available_working_population > MAX_JSON_SAFE_INTEGER
		or region_records.is_empty()
	):
		return false

	var by_region: Dictionary = {}
	for raw_region: Variant in region_records:
		if typeof(raw_region) != TYPE_DICTIONARY:
			return false
		var region: Dictionary = (raw_region as Dictionary).duplicate(true)
		if not _validate_region(region):
			return false
		var region_id: String = str(region.get("region_id", ""))
		if by_region.has(region_id):
			return false
		by_region[region_id] = region

	var ordered_region_ids: Array[String] = []
	for raw_region_id: Variant in by_region.keys():
		ordered_region_ids.append(str(raw_region_id))
	ordered_region_ids.sort()
	var candidate_regions: Array[Dictionary] = []
	var candidate_population: int = 0
	var candidate_available: int = 0
	for region_id: String in ordered_region_ids:
		var region: Dictionary = by_region[region_id] as Dictionary
		candidate_population = _checked_add(
			candidate_population, int(region["population"])
		)
		candidate_available = _checked_add(
			candidate_available,
			int(region["economically_available_working_population"])
		)
		if candidate_population < 0 or candidate_available < 0:
			return false
		candidate_regions.append(region.duplicate(true))

	if (
		candidate_population != covered_population
		or candidate_available != economically_available_working_population
	):
		return false
	_regions = candidate_regions
	_settlement_period = settlement_period
	_source_population_period = source_population_period
	_covered_population = covered_population
	_economically_available_working_population = (
		economically_available_working_population
	)
	_initialized = true
	return true


func is_valid() -> bool:
	if (
		not _initialized
		or _settlement_period < 0
		or _source_population_period < 0
		or _regions.is_empty()
	):
		return false
	var candidate_population: int = 0
	var candidate_available: int = 0
	for region: Dictionary in _regions:
		if not _validate_region(region):
			return false
		candidate_population = _checked_add(candidate_population, int(region["population"]))
		candidate_available = _checked_add(
			candidate_available,
			int(region["economically_available_working_population"])
		)
		if candidate_population < 0 or candidate_available < 0:
			return false
	return (
		candidate_population == _covered_population
		and candidate_available == _economically_available_working_population
	)


func settlement_period() -> int:
	return _settlement_period


func source_population_period() -> int:
	return _source_population_period


func covered_population() -> int:
	return _covered_population


func total_population() -> int:
	return _covered_population


func economically_available_working_population() -> int:
	return _economically_available_working_population


func available_workforce() -> int:
	return _economically_available_working_population


func region_ids() -> Array[String]:
	var output: Array[String] = []
	for region: Dictionary in _regions:
		output.append(str(region.get("region_id", "")))
	return output


func regions() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for region: Dictionary in _regions:
		output.append(region.duplicate(true))
	return output


func region_snapshot(region_id: String) -> Dictionary:
	for region: Dictionary in _regions:
		if str(region.get("region_id", "")) == region_id:
			return region.duplicate(true)
	return {}


func labor_pools_at(region_id: String) -> Dictionary:
	var region: Dictionary = region_snapshot(region_id)
	if region.is_empty():
		return {}
	return (region.get("labor_pools", {}) as Dictionary).duplicate(true)


func economically_available_working_population_at(region_id: String) -> int:
	var region: Dictionary = region_snapshot(region_id)
	return int(region.get("economically_available_working_population", -1))


func available_workforce_at(region_id: String) -> int:
	return economically_available_working_population_at(region_id)


func labor_pool_at(region_id: String, category: String) -> int:
	var pools: Dictionary = labor_pools_at(region_id)
	return int(pools.get(category, -1))


func pools_sum_at(region_id: String) -> int:
	var pools: Dictionary = labor_pools_at(region_id)
	if pools.is_empty():
		return -1
	var total: int = 0
	for category: String in LABOR_CATEGORIES:
		total = _checked_add(total, int(pools.get(category, -1)))
		if total < 0:
			return -1
	return total


func is_double_count_free() -> bool:
	if not is_valid():
		return false
	for region: Dictionary in _regions:
		var available: int = int(region["economically_available_working_population"])
		var pools: Dictionary = region["labor_pools"] as Dictionary
		var total_pools: int = 0
		for category: String in LABOR_CATEGORIES:
			var pool_value: int = int(pools.get(category, -1))
			if pool_value < 0:
				return false
			total_pools = _checked_add(total_pools, pool_value)
			if total_pools < 0:
				return false
		if total_pools > available:
			return false
	return true


func snapshot() -> Dictionary:
	if not is_valid():
		return {}
	var copied_regions: Array[Dictionary] = []
	for region: Dictionary in _regions:
		copied_regions.append(region.duplicate(true))
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"settlement_period": _settlement_period,
		"source_population_period": _source_population_period,
		"covered_population": _covered_population,
		"economically_available_working_population": _economically_available_working_population,
		"labor_categories": LABOR_CATEGORIES.duplicate(),
		"regions": copied_regions,
	}


func _validate_region(region: Dictionary) -> bool:
	var region_id: String = str(region.get("region_id", ""))
	if not _is_region_id(region_id):
		return false
	var population: int = int(region.get("population", -1))
	var available: int = int(
		region.get("economically_available_working_population", -1)
	)
	if (
		typeof(region.get("population")) != TYPE_INT
		or typeof(region.get("economically_available_working_population")) != TYPE_INT
		or population < 0
		or available < 0
		or population > MAX_JSON_SAFE_INTEGER
		or available > population
	):
		return false
	var pools_value: Variant = region.get("labor_pools")
	if typeof(pools_value) != TYPE_DICTIONARY:
		return false
	var pools: Dictionary = pools_value as Dictionary
	if pools.size() != LABOR_CATEGORIES.size():
		return false
	var pool_total: int = 0
	for raw_category: Variant in pools.keys():
		if typeof(raw_category) != TYPE_STRING or not LABOR_CATEGORIES.has(str(raw_category)):
			return false
	for category: String in LABOR_CATEGORIES:
		var pool_value: Variant = pools.get(category)
		if typeof(pool_value) != TYPE_INT or int(pool_value) < 0:
			return false
		pool_total = _checked_add(pool_total, int(pool_value))
		if pool_total < 0:
			return false
	if pool_total > available:
		return false
	return _validate_source_ids(region.get("source_population_ids", []))


static func _validate_source_ids(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var seen: Dictionary = {}
	for raw_source_id: Variant in value as Array:
		if typeof(raw_source_id) != TYPE_STRING or seen.has(str(raw_source_id)):
			return false
		seen[str(raw_source_id)] = true
	return true


static func _is_region_id(value: String) -> bool:
	if not value.begins_with("region:"):
		return false
	return _is_valid_local_id(value.substr("region:".length()))


static func _is_valid_local_id(value: String) -> bool:
	if value.is_empty():
		return false
	for character_index: int in value.length():
		var character: String = value.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true


static func _checked_add(left: int, right: int) -> int:
	if left < 0 or right < 0 or left > MAX_JSON_SAFE_INTEGER - right:
		return -1
	return left + right
