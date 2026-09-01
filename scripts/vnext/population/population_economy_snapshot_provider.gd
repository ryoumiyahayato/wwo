class_name VNextPopulationEconomySnapshotProvider
extends RefCounted
## Read-only adapter from authoritative Population state to Economy inputs.
##
## The provider has no live population fields. It reads a complete, aligned
## Population state once, applies an explicit region crosswalk, and constructs
## immutable value objects. Population changes after this call can only affect
## a later call.

const MAX_JSON_SAFE_INTEGER: int = 9_007_199_254_740_991
const LABOR_CATEGORIES: PackedStringArray = [
	"rural",
	"urban_unskilled",
	"skilled_industrial",
]


static func create_daily_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextPopulationEconomyDailySnapshot:
	var projected: Dictionary = _project_inputs(
		population, crosswalk, settlement_period
	)
	if projected.is_empty():
		return null
	var labor_snapshot := VNextLaborSnapshot.create(
		settlement_period,
		int(projected["source_population_period"]),
		projected["labor_regions"] as Array[Dictionary],
		int(projected["covered_population"]),
		int(projected["economically_available_working_population"])
	)
	var demand_snapshot := VNextDemandPopulationSnapshot.create(
		settlement_period,
		int(projected["source_population_period"]),
		projected["demand_regions"] as Array[Dictionary],
		int(projected["covered_population"])
	)
	return VNextPopulationEconomyDailySnapshot.create(
		labor_snapshot, demand_snapshot
	)


static func create_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextPopulationEconomyDailySnapshot:
	return create_daily_snapshot(population, crosswalk, settlement_period)


static func build_daily_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextPopulationEconomyDailySnapshot:
	return create_daily_snapshot(population, crosswalk, settlement_period)


func build(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextPopulationEconomyDailySnapshot:
	return create_daily_snapshot(population, crosswalk, settlement_period)


static func create_labor_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextLaborSnapshot:
	var projected: Dictionary = _project_inputs(
		population, crosswalk, settlement_period
	)
	if projected.is_empty():
		return null
	return VNextLaborSnapshot.create(
		settlement_period,
		int(projected["source_population_period"]),
		projected["labor_regions"] as Array[Dictionary],
		int(projected["covered_population"]),
		int(projected["economically_available_working_population"])
	)


static func create_demand_population_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextDemandPopulationSnapshot:
	var projected: Dictionary = _project_inputs(
		population, crosswalk, settlement_period
	)
	if projected.is_empty():
		return null
	return VNextDemandPopulationSnapshot.create(
		settlement_period,
		int(projected["source_population_period"]),
		projected["demand_regions"] as Array[Dictionary],
		int(projected["covered_population"])
	)


func build_labor_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextLaborSnapshot:
	return create_labor_snapshot(population, crosswalk, settlement_period)


func build_demand_population_snapshot(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> VNextDemandPopulationSnapshot:
	return create_demand_population_snapshot(population, crosswalk, settlement_period)


static func _project_inputs(
	population: VNextMacroPopulation,
	crosswalk: VNextPopulationEconomyRegionCrosswalk,
	settlement_period: int
) -> Dictionary:
	if (
		population == null
		or crosswalk == null
		or not population.is_valid()
		or not crosswalk.is_valid()
		or settlement_period < 0
	):
		return {}

	var source_ids: Array[String] = population.known_place_ids()
	if source_ids.is_empty() or source_ids != crosswalk.source_ids():
		return {}

	var source_population_period: int = -1
	var covered_population: int = 0
	var economically_available_working_population: int = 0
	var aggregate_by_region: Dictionary = {}

	for source_id: String in source_ids:
		var target_region_id: String = crosswalk.region_for_source(source_id)
		if target_region_id.is_empty():
			return {}
		var source_period: int = population.last_settled_period_at(source_id)
		if source_period < 0:
			return {}
		if source_population_period < 0:
			source_population_period = source_period
		elif source_period != source_population_period:
			return {}

		var structure: Dictionary = population.structure_at(source_id)
		if not _valid_source_structure(structure):
			return {}
		var total_population: int = int(structure["total_population"])
		var working_age_population: int = int(structure["working_age_population"])
		var urban_rural: Dictionary = structure["urban_rural"] as Dictionary
		var urban_population: int = int(urban_rural["urban"])
		var rural_population: int = int(urban_rural["rural"])
		var labor_pools: Dictionary = _project_labor_pools(
			working_age_population,
			total_population,
			urban_population,
			rural_population
		)
		if labor_pools.is_empty():
			return {}

		covered_population = _checked_add(covered_population, total_population)
		economically_available_working_population = _checked_add(
			economically_available_working_population,
			working_age_population
		)
		if covered_population < 0 or economically_available_working_population < 0:
			return {}

		if not aggregate_by_region.has(target_region_id):
			aggregate_by_region[target_region_id] = {
				"region_id": target_region_id,
				"population": 0,
				"working_age_population": 0,
				"urban_rural": {"urban": 0, "rural": 0},
				"labor_pools": _zero_labor_pools(),
				"source_population_ids": [],
			}
		var aggregate: Dictionary = aggregate_by_region[target_region_id] as Dictionary
		aggregate["population"] = _checked_add(
			int(aggregate["population"]), total_population
		)
		aggregate["working_age_population"] = _checked_add(
			int(aggregate["working_age_population"]), working_age_population
		)
		var aggregate_urban_rural: Dictionary = aggregate["urban_rural"] as Dictionary
		aggregate_urban_rural["urban"] = _checked_add(
			int(aggregate_urban_rural["urban"]), urban_population
		)
		aggregate_urban_rural["rural"] = _checked_add(
			int(aggregate_urban_rural["rural"]), rural_population
		)
		var aggregate_pools: Dictionary = aggregate["labor_pools"] as Dictionary
		for category: String in LABOR_CATEGORIES:
			aggregate_pools[category] = _checked_add(
				int(aggregate_pools[category]), int(labor_pools[category])
			)
		if (
			int(aggregate["population"]) < 0
			or int(aggregate["working_age_population"]) < 0
			or int(aggregate_urban_rural["urban"]) < 0
			or int(aggregate_urban_rural["rural"]) < 0
		):
			return {}
		for category: String in LABOR_CATEGORIES:
			if int(aggregate_pools[category]) < 0:
				return {}
		var aggregate_source_ids: Array = aggregate["source_population_ids"] as Array
		aggregate_source_ids.append(source_id)

	var ordered_region_ids: Array[String] = []
	for raw_region_id: Variant in aggregate_by_region.keys():
		ordered_region_ids.append(str(raw_region_id))
	ordered_region_ids.sort()
	var labor_regions: Array[Dictionary] = []
	var demand_regions: Array[Dictionary] = []
	for region_id: String in ordered_region_ids:
		var aggregate: Dictionary = aggregate_by_region[region_id] as Dictionary
		var aggregate_source_ids: Array = aggregate["source_population_ids"] as Array
		aggregate_source_ids.sort()
		var aggregate_urban_rural: Dictionary = aggregate["urban_rural"] as Dictionary
		var aggregate_pools: Dictionary = aggregate["labor_pools"] as Dictionary
		var aggregate_population: int = int(aggregate["population"])
		var aggregate_working_age: int = int(aggregate["working_age_population"])
		if (
			int(aggregate_urban_rural["urban"]) + int(aggregate_urban_rural["rural"])
			!= aggregate_population
			or _sum_labor_pools(aggregate_pools) > aggregate_working_age
		):
			return {}
		labor_regions.append({
			"region_id": region_id,
			"population": aggregate_population,
			"economically_available_working_population": aggregate_working_age,
			"labor_pools": aggregate_pools.duplicate(true),
			"source_population_ids": aggregate_source_ids.duplicate(true),
		})
		demand_regions.append({
			"region_id": region_id,
			"population": aggregate_population,
			"working_age_population": aggregate_working_age,
			"urban_rural": aggregate_urban_rural.duplicate(true),
			"household_strata": {},
			"income_strata": {},
			"source_population_ids": aggregate_source_ids.duplicate(true),
		})

	return {
		"source_population_period": source_population_period,
		"covered_population": covered_population,
		"economically_available_working_population": economically_available_working_population,
		"labor_regions": labor_regions,
		"demand_regions": demand_regions,
	}


static func _valid_source_structure(structure: Dictionary) -> bool:
	if structure.is_empty():
		return false
	for field_name: String in ["total_population", "working_age_population"]:
		if typeof(structure.get(field_name)) != TYPE_INT:
			return false
	var total_population: int = int(structure["total_population"])
	var working_age_population: int = int(structure["working_age_population"])
	if (
		total_population < 0
		or working_age_population < 0
		or working_age_population > total_population
	):
		return false
	var urban_rural_value: Variant = structure.get("urban_rural")
	if typeof(urban_rural_value) != TYPE_DICTIONARY:
		return false
	var urban_rural: Dictionary = urban_rural_value as Dictionary
	if urban_rural.size() != 2 or not urban_rural.has("urban") or not urban_rural.has("rural"):
		return false
	for category: String in ["urban", "rural"]:
		if typeof(urban_rural[category]) != TYPE_INT or int(urban_rural[category]) < 0:
			return false
	return (
		int(urban_rural["urban"]) + int(urban_rural["rural"])
		== total_population
	)


static func _project_labor_pools(
	working_age_population: int,
	total_population: int,
	urban_population: int,
	rural_population: int
) -> Dictionary:
	if (
		working_age_population < 0
		or total_population < 0
		or urban_population < 0
		or rural_population < 0
		or urban_population + rural_population != total_population
		or working_age_population > total_population
	):
		return {}
	var rural_working_population: int = 0
	if total_population > 0 and rural_population > 0 and working_age_population > 0:
		rural_working_population = int(
			floor(
				float(working_age_population)
				* float(rural_population)
				/ float(total_population)
			)
		)
	var urban_working_population: int = working_age_population - rural_working_population
	var result: Dictionary = _zero_labor_pools()
	result["rural"] = rural_working_population
	result["urban_unskilled"] = urban_working_population
	# Population has no authoritative skill/occupation axis in V1.
	result["skilled_industrial"] = 0
	return result


static func _zero_labor_pools() -> Dictionary:
	return {
		"rural": 0,
		"urban_unskilled": 0,
		"skilled_industrial": 0,
	}


static func _sum_labor_pools(pools: Dictionary) -> int:
	var total: int = 0
	for category: String in LABOR_CATEGORIES:
		var value: int = int(pools.get(category, -1))
		if value < 0:
			return -1
		total = _checked_add(total, value)
		if total < 0:
			return -1
	return total


static func _checked_add(left: int, right: int) -> int:
	if left < 0 or right < 0 or left > MAX_JSON_SAFE_INTEGER - right:
		return -1
	return left + right
