extends SceneTree
## Production source/identity/determinism gate for the 1900 TerritoryUnit catalog.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_source_backed_catalog()
	_test_deterministic_reload()
	print("Production TerritoryUnit catalog: %d checks, %d failures" % [checks, failures])
	var exit_code: int = 1 if failures > 0 or checks <= 0 else 0
	print("PRODUCTION_TERRITORY_UNIT_CATALOG_EXIT_CODE=%d" % exit_code)
	quit(exit_code)


func _test_source_backed_catalog() -> void:
	var provider := VNextProductionTerritoryUnitCatalogProvider.new()
	_check(provider.load(), "production TerritoryUnit provider loads source-backed data")
	if not provider.is_loaded():
		return
	var catalog := provider.catalog()
	_check(catalog != null and catalog.is_sealed(), "production TerritoryUnit catalog is sealed")
	_equal(provider.territory_unit_count(), 151, "production catalog covers all 151 CShapes units")
	_equal(
		provider.territory_unit_id_for_political_unit("united_states_1900"),
		"territory_unit:gw_2",
		"political identity maps explicitly to geometry-owned TerritoryUnit identity"
	)
	_equal(
		provider.political_unit_id_for_territory_unit("territory_unit:gw_2"),
		"united_states_1900",
		"TerritoryUnit identity has a deterministic reverse political crosswalk"
	)
	_equal(provider.political_crosswalk().size(), 151, "political crosswalk is one-to-one")
	_check(catalog.has_unit("territory_unit:gw_2"), "known source geometry becomes a TerritoryUnit")
	var unit := catalog.unit_by_id("territory_unit:gw_2")
	_check(unit != null, "known production TerritoryUnit is queryable")
	if unit != null:
		_equal(
			unit.source_snapshot_ref(),
			VNextProductionTerritoryUnitCatalogProvider.GEOMETRY_SNAPSHOT_PATH,
			"TerritoryUnit provenance points at the committed CShapes snapshot"
		)
		_equal(
			unit.geometry_ref(),
			VNextProductionTerritoryUnitCatalogProvider.GEOMETRY_SNAPSHOT_PATH + "#feature=gw_2",
			"TerritoryUnit geometry_ref addresses a concrete source feature"
		)
	var neighbor_reference_count: int = 0
	for territory_id: String in catalog.unit_ids():
		var neighbors := catalog.neighbor_ids(territory_id)
		neighbor_reference_count += neighbors.size()
		for neighbor_id: String in neighbors:
			_check(catalog.has_unit(neighbor_id), "adjacency references only sealed catalog units")
			_check(
				catalog.neighbor_ids(neighbor_id).has(territory_id),
				"source-derived adjacency remains symmetric"
			)
	_check(neighbor_reference_count > 0, "production catalog contains mechanically derived land adjacency")
	_equal(neighbor_reference_count % 2, 0, "undirected adjacency has paired references")
	var record := catalog.unit_by_id("territory_unit:gw_2").to_detached_dict()
	for forbidden_field: String in [
		"controller_id", "sovereign_owner_id", "population", "gdp", "inventory",
		"army", "occupation", "runtime_control",
	]:
		_check(not record.has(forbidden_field), "TerritoryUnit identity excludes %s" % forbidden_field)


func _test_deterministic_reload() -> void:
	var first := VNextProductionTerritoryUnitCatalogProvider.new()
	var second := VNextProductionTerritoryUnitCatalogProvider.new()
	_check(first.load(), "first production provider load succeeds")
	_check(second.load(), "second production provider load succeeds")
	if not first.is_loaded() or not second.is_loaded():
		return
	_equal(first.catalog_binding(), second.catalog_binding(), "production catalog binding is deterministic")
	_equal(first.catalog_fingerprint(), second.catalog_fingerprint(), "production catalog fingerprint is deterministic")
	_equal(first.political_crosswalk(), second.political_crosswalk(), "political crosswalk ordering is deterministic")
	_check(not first.load(), "production provider refuses a second load")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
