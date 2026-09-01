extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_d01_total_population()
	_test_d02_labor_bound()
	_test_d03_labor_classes_do_not_double_count()
	_test_d04_source_reorder_is_stable()
	_test_d05_unknown_region_fails_closed()
	_test_d06_missing_population_fails_closed()
	_test_d07_controller_change_does_not_move_population()
	_test_d08_snapshot_is_defensively_copied()
	_test_d09_unchanged_state_repeats_identically()
	_test_d10_later_population_mutation_is_next_period_only()
	print(
		"Population economy boundary: %d checks, %d failures" % [checks, failures]
	)
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_d01_total_population() -> void:
	var fixture: Dictionary = _fixture()
	var daily: VNextPopulationEconomyDailySnapshot = _daily(fixture, 10)
	_check(daily != null and daily.is_valid(), "D-01 daily snapshot is valid")
	if daily == null:
		return
	var population: VNextMacroPopulation = fixture["population"] as VNextMacroPopulation
	var source_total: int = population.aggregate_population(population.known_place_ids())
	var demand: VNextDemandPopulationSnapshot = daily.demand_population_snapshot()
	_equal(demand.total_population(), source_total, "D-01 snapshot total equals covered source population")
	var region_total: int = 0
	for region: Dictionary in demand.regions():
		region_total += int(region["population"])
	_equal(region_total, source_total, "D-01 region projections conserve source population")


func _test_d02_labor_bound() -> void:
	var daily: VNextPopulationEconomyDailySnapshot = _daily(_fixture(), 10)
	_check(daily != null, "D-02 labor fixture creates")
	if daily == null:
		return
	var labor: VNextLaborSnapshot = daily.labor_snapshot()
	_check(labor.is_double_count_free(), "D-02 labor snapshot reports bounded pools")
	for region_id: String in labor.region_ids():
		var available: int = labor.economically_available_working_population_at(region_id)
		_check(
			labor.pools_sum_at(region_id) <= available,
			"D-02 pools do not exceed available workforce for " + region_id
		)


func _test_d03_labor_classes_do_not_double_count() -> void:
	var daily: VNextPopulationEconomyDailySnapshot = _daily(_fixture(), 10)
	_check(daily != null, "D-03 labor fixture creates")
	if daily == null:
		return
	var labor: VNextLaborSnapshot = daily.labor_snapshot()
	_equal(
		labor.snapshot()["labor_categories"],
		PackedStringArray(["rural", "urban_unskilled", "skilled_industrial"]),
		"D-03 labor categories are the explicit V1 partition"
	)
	for region_id: String in labor.region_ids():
		var pools: Dictionary = labor.labor_pools_at(region_id)
		_equal(pools.size(), 3, "D-03 each region has exactly three labor classes")
		_equal(
			labor.pools_sum_at(region_id),
			labor.economically_available_working_population_at(region_id),
			"D-03 each working-age unit is assigned once for " + region_id
		)
		_equal(
			int(pools["skilled_industrial"]),
			0,
			"D-03 unsupported skill data does not invent a skilled population"
		)


func _test_d04_source_reorder_is_stable() -> void:
	var first: VNextPopulationEconomyDailySnapshot = _daily(
		_fixture(false, false), 10
	)
	var second: VNextPopulationEconomyDailySnapshot = _daily(
		_fixture(true, true), 10
	)
	_check(first != null and second != null, "D-04 reordered fixtures create")
	if first == null or second == null:
		return
	_equal(
		first.snapshot(),
		second.snapshot(),
		"D-04 stable source and crosswalk reorder produces identical snapshot"
	)


func _test_d05_unknown_region_fails_closed() -> void:
	var catalog: VNextSpatialCatalog = _catalog()
	var unknown_target := VNextPopulationEconomyRegionCrosswalk.create(
		catalog,
		{
			"place:paris": "region:not_a_spatial_region",
			"place:lille": "region:northern_industrial_belt",
		}
	)
	_check(unknown_target == null, "D-05 unknown region target is rejected")
	var fixture: Dictionary = _fixture()
	var incomplete := VNextPopulationEconomyRegionCrosswalk.create(
		catalog, {"place:paris": "region:paris_basin"}
	)
	_check(incomplete != null, "D-05 incomplete mapping remains explicit and inspectable")
	if incomplete != null:
		_check(
			_daily({"population": fixture["population"], "crosswalk": incomplete}, 10) == null,
			"D-05 missing source mapping fails closed"
		)


func _test_d06_missing_population_fails_closed() -> void:
	var fixture: Dictionary = _fixture()
	var daily: VNextPopulationEconomyDailySnapshot = (
		VNextPopulationEconomySnapshotProvider.create_daily_snapshot(
			null,
			fixture["crosswalk"] as VNextPopulationEconomyRegionCrosswalk,
			10
		)
	)
	_check(daily == null, "D-06 missing Population reference fails closed")


func _test_d07_controller_change_does_not_move_population() -> void:
	var fixture: Dictionary = _fixture()
	var before: VNextPopulationEconomyDailySnapshot = _daily(fixture, 10)
	var world: VNextSpatialWorld = VNextSpatialWorld.create(
		fixture["catalog"] as VNextSpatialCatalog
	)
	_check(before != null and world != null, "D-07 political-boundary fixture creates")
	if before == null or world == null:
		return
	_check(
		world.set_military_controller("paris_basin", "country_bel"),
		"D-07 controller change is applied only to Spatial political facts"
	)
	var after: VNextPopulationEconomyDailySnapshot = _daily(fixture, 10)
	_check(after != null, "D-07 post-controller snapshot creates")
	if after == null:
		return
	_equal(
		before.snapshot(),
		after.snapshot(),
		"D-07 political controller change does not change Population projection"
	)
	_check(
		not before.snapshot().has("military_controller_id"),
		"D-07 daily Population snapshot carries no political controller"
	)


func _test_d08_snapshot_is_defensively_copied() -> void:
	var daily: VNextPopulationEconomyDailySnapshot = _daily(_fixture(), 10)
	_check(daily != null, "D-08 snapshot fixture creates")
	if daily == null:
		return
	var before: Dictionary = daily.snapshot()
	var exposed: Dictionary = daily.snapshot()
	var exposed_labor: Dictionary = exposed["labor"] as Dictionary
	var exposed_labor_regions: Array = exposed_labor["regions"] as Array
	var exposed_labor_region: Dictionary = exposed_labor_regions[0] as Dictionary
	var exposed_pools: Dictionary = exposed_labor_region["labor_pools"] as Dictionary
	exposed_pools["rural"] = 999999
	var exposed_demand: Dictionary = exposed["demand_population"] as Dictionary
	var exposed_demand_regions: Array = exposed_demand["regions"] as Array
	var exposed_demand_region: Dictionary = exposed_demand_regions[0] as Dictionary
	exposed_demand_region["population"] = 999999
	_equal(
		daily.snapshot(),
		before,
		"D-08 mutating an exposed combined dictionary cannot mutate the snapshot"
	)

	var copied_regions: Array[Dictionary] = daily.demand_population_snapshot().regions()
	(copied_regions[0] as Dictionary)["population"] = 999999
	_equal(
		daily.demand_population_snapshot().population_at(
		str((copied_regions[0] as Dictionary)["region_id"])
	),
		int(((before["demand_population"] as Dictionary)["regions"] as Array)[0]["population"]),
		"D-08 region accessor returns a defensive deep copy"
	)


func _test_d09_unchanged_state_repeats_identically() -> void:
	var fixture: Dictionary = _fixture()
	var first: VNextPopulationEconomyDailySnapshot = _daily(fixture, 10)
	var second: VNextPopulationEconomyDailySnapshot = _daily(fixture, 10)
	_check(first != null and second != null, "D-09 unchanged-state fixtures create")
	if first == null or second == null:
		return
	_equal(
		first.snapshot(),
		second.snapshot(),
		"D-09 two snapshots from unchanged state are identical"
	)


func _test_d10_later_population_mutation_is_next_period_only() -> void:
	var fixture: Dictionary = _fixture()
	var population: VNextMacroPopulation = fixture["population"] as VNextMacroPopulation
	var crosswalk: VNextPopulationEconomyRegionCrosswalk = (
		fixture["crosswalk"] as VNextPopulationEconomyRegionCrosswalk
	)
	var before: VNextPopulationEconomyDailySnapshot = _daily(fixture, 10)
	_check(before != null, "D-10 initial snapshot creates")
	if before == null:
		return
	var before_dictionary: Dictionary = before.snapshot()
	var before_population: int = before.demand_population_snapshot().population_at(
		"region:paris_basin"
	)
	_check(
		population.settle_elapsed_months(
			1, {"place:paris": {"births": 10}}
		),
		"D-10 later Population mutation settles a later source period"
	)
	_equal(
		before.snapshot(),
		before_dictionary,
		"D-10 later Population mutation does not alter the existing snapshot"
	)
	var after: VNextPopulationEconomyDailySnapshot = (
		VNextPopulationEconomySnapshotProvider.create_daily_snapshot(
			population, crosswalk, 11
		)
	)
	_check(after != null, "D-10 next daily snapshot creates")
	if after == null:
		return
	_check(
		after.demand_population_snapshot().population_at("region:paris_basin")
		== before_population + 10,
		"D-10 later Population change appears only in the next snapshot"
	)


func _daily(
	fixture: Dictionary, settlement_period: int
) -> VNextPopulationEconomyDailySnapshot:
	var population: VNextMacroPopulation = fixture.get("population") as VNextMacroPopulation
	var crosswalk: VNextPopulationEconomyRegionCrosswalk = (
		fixture.get("crosswalk") as VNextPopulationEconomyRegionCrosswalk
	)
	return VNextPopulationEconomySnapshotProvider.create_daily_snapshot(
		population, crosswalk, settlement_period
	)


func _fixture(
	reverse_source_order: bool = false, reverse_mapping_order: bool = false
) -> Dictionary:
	var catalog: VNextSpatialCatalog = _catalog()
	var source_ids: Array[String] = ["place:paris", "place:lille"]
	if reverse_source_order:
		source_ids.reverse()
	var population: VNextMacroPopulation = VNextMacroPopulation.create(
		catalog, source_ids
	)
	if population == null:
		return {}
	if not population.set_initial_state(
		"place:paris",
		_state(1200, 120, 360, 480, 240, 600, 600, 900, 300)
	):
		return {}
	if not population.set_initial_state(
		"place:lille",
		_state(800, 80, 240, 320, 160, 400, 400, 300, 500)
	):
		return {}
	var mapping: Dictionary = {}
	if reverse_mapping_order:
		mapping["place:lille"] = "region:northern_industrial_belt"
		mapping["place:paris"] = "region:paris_basin"
	else:
		mapping["place:paris"] = "region:paris_basin"
		mapping["place:lille"] = "region:northern_industrial_belt"
	var crosswalk: VNextPopulationEconomyRegionCrosswalk = (
		VNextPopulationEconomyRegionCrosswalk.create(catalog, mapping)
	)
	if crosswalk == null:
		return {}
	return {"catalog": catalog, "population": population, "crosswalk": crosswalk}


func _catalog() -> VNextSpatialCatalog:
	var catalog := VNextSpatialCatalog.new()
	if not catalog.load_legacy_world_map():
		return null
	return catalog


func _state(
	total: int,
	under_18: int,
	age_18_40: int,
	age_41_64: int,
	age_65_plus: int,
	female: int,
	male: int,
	urban: int,
	rural: int
) -> Dictionary:
	return {
		"total_population": total,
		"age_buckets": {
			"under_18": under_18,
			"age_18_40": age_18_40,
			"age_41_64": age_41_64,
			"age_65_plus": age_65_plus,
		},
		"sex_structure": {"female": female, "male": male},
		"urban_rural": {"urban": urban, "rural": rural},
	}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
