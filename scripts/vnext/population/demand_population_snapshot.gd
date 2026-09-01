class_name VNextDemandPopulationSnapshot
extends RefCounted
## Immutable Population facts for a future household-demand calculation.
##
## Commodity quantities, preferences, prices, and elasticities deliberately do
## not appear here. The current Population authority has no household or
## income strata, so those projections remain empty until an authoritative
## source is added.

const SNAPSHOT_SCHEMA_ID: String = "vnext_population_demand_population_snapshot_v1"
const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991

var _initialized: bool = false
var _settlement_period: int = -1
var _source_population_period: int = -1
var _covered_population: int = 0
var _regions: Array[Dictionary] = []


static func create(
	settlement_period: int,
	source_population_period: int,
	region_records: Array[Dictionary],
	covered_population: int
) -> VNextDemandPopulationSnapshot:
	var snapshot := VNextDemandPopulationSnapshot.new()
	if not snapshot._configure(
		settlement_period,
		source_population_period,
		region_records,
		covered_population
	):
		return null
	return snapshot


func _configure(
	settlement_period: int,
	source_population_period: int,
	region_records: Array[Dictionary],
	covered_population: int
) -> bool:
	if (
		settlement_period < 0
		or source_population_period < 0
		or covered_population < 0
		or covered_population > MAX_JSON_SAFE_INTEGER
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
	for region_id: String in ordered_region_ids:
		var region: Dictionary = by_region[region_id] as Dictionary
		candidate_population = _checked_add(
			candidate_population, int(region["population"])
		)
		if candidate_population < 0:
			return false
		candidate_regions.append(region.duplicate(true))
	if candidate_population != covered_population:
		return false

	_regions = candidate_regions
	_settlement_period = settlement_period
	_source_population_period = source_population_period
	_covered_population = covered_population
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
	for region: Dictionary in _regions:
		if not _validate_region(region):
			return false
		candidate_population = _checked_add(candidate_population, int(region["population"]))
		if candidate_population < 0:
			return false
	return candidate_population == _covered_population


func settlement_period() -> int:
	return _settlement_period


func source_population_period() -> int:
	return _source_population_period


func covered_population() -> int:
	return _covered_population


func total_population() -> int:
	return _covered_population


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


func population_at(region_id: String) -> int:
	var region: Dictionary = region_snapshot(region_id)
	return int(region.get("population", -1))


func urban_rural_at(region_id: String) -> Dictionary:
	var region: Dictionary = region_snapshot(region_id)
	if region.is_empty():
		return {}
	return (region.get("urban_rural", {}) as Dictionary).duplicate(true)


func household_strata_at(region_id: String) -> Dictionary:
	var region: Dictionary = region_snapshot(region_id)
	if region.is_empty():
		return {}
	return (region.get("household_strata", {}) as Dictionary).duplicate(true)


func income_strata_at(region_id: String) -> Dictionary:
	var region: Dictionary = region_snapshot(region_id)
	if region.is_empty():
		return {}
	return (region.get("income_strata", {}) as Dictionary).duplicate(true)


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
		"regions": copied_regions,
	}


func _validate_region(region: Dictionary) -> bool:
	var region_id: String = str(region.get("region_id", ""))
	if not _is_region_id(region_id):
		return false
	var population_value: Variant = region.get("population")
	if typeof(population_value) != TYPE_INT:
		return false
	var population: int = int(population_value)
	if population < 0 or population > MAX_JSON_SAFE_INTEGER:
		return false

	var urban_rural_value: Variant = region.get("urban_rural")
	if typeof(urban_rural_value) != TYPE_DICTIONARY:
		return false
	var urban_rural: Dictionary = urban_rural_value as Dictionary
	if urban_rural.size() != 2 or not urban_rural.has("urban") or not urban_rural.has("rural"):
		return false
	var urban: Variant = urban_rural.get("urban")
	var rural: Variant = urban_rural.get("rural")
	if (
		typeof(urban) != TYPE_INT
		or typeof(rural) != TYPE_INT
		or int(urban) < 0
		or int(rural) < 0
		or _checked_add(int(urban), int(rural)) != population
	):
		return false

	var working_age_value: Variant = region.get("working_age_population")
	if typeof(working_age_value) != TYPE_INT:
		return false
	var working_age: int = int(working_age_value)
	if working_age < 0 or working_age > population:
		return false
	for field_name: String in ["household_strata", "income_strata"]:
		if typeof(region.get(field_name)) != TYPE_DICTIONARY:
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
