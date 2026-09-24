extends SceneTree

const CONTROL_LEDGER = preload("res://scripts/vnext/territory/territorial_control_ledger.gd")

const TERRITORY_VERSION: String = "current_world_convergence_territory_v1"
const SOURCE_REF: String = "fixture://current-world-convergence/v1"
const TERRITORY_A: String = "territory_unit:convergence_a"
const TERRITORY_B: String = "territory_unit:convergence_b"
const CONTROLLER_A: String = "state:convergence_a"
const CONTROLLER_B: String = "state:convergence_b"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run()
	print("Current world domain convergence: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _run() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog()
	var political_view: RuntimePoliticalEntityView = _make_political_view()
	_check(catalog != null and political_view != null, "shared reference fixtures configure")
	if catalog == null or political_view == null:
		return

	var control: VNextTerritorialControlLedger = VNextTerritorialControlLedger.create(
		catalog, political_view
	)
	_check(control != null and control.is_configured(), "Territorial Control authority configures")
	if control == null:
		return
	_check(
		control.initialize_assignments([
			CONTROL_LEDGER.controlled_assignment(TERRITORY_A, CONTROLLER_A),
			CONTROL_LEDGER.controlled_assignment(TERRITORY_B, CONTROLLER_A),
		], 0),
		"Territorial Control initializes independently"
	)

	var population: VNextPopulationAuthority = VNextPopulationAuthority.create(catalog)
	_check(population != null and population.is_configured(), "Population authority configures")
	if population == null:
		return
	_check(
		population.initialize_population(TERRITORY_A, 100)
		and population.initialize_population(TERRITORY_B, 200),
		"Population initializes independently"
	)

	var formal := FormalWorldSimulation.new()
	_check(formal.initialize(), "Formal Economy fixture initializes")
	if not formal.initialized:
		return
	var market_ids: Array[String] = formal.market_registry_view().market_ids()
	_check(market_ids.size() >= 2, "Formal Market registry exposes remap targets")
	if market_ids.size() < 2:
		return
	var geography := VNextEconomicGeographyService.new()
	_check(
		geography.configure(
			catalog,
			formal.market_registry_view(),
			[_assigned(TERRITORY_A, market_ids[0])]
		),
		"Economic Geography configures independently"
	)
	if not geography.is_configured():
		return

	var population_before_control: String = population.fingerprint()
	var geography_before_control: String = geography.state_fingerprint()
	var control_before: String = control.authoritative_fingerprint()
	var control_candidate: Dictionary = control.prepare_control_change(
		TERRITORY_A,
		CONTROL_LEDGER.CONTROLLED,
		CONTROLLER_B,
		control.revision()
	)
	_check(not control_candidate.is_empty(), "controller change candidate prepares")
	_equal(population.fingerprint(), population_before_control, "control prepare preserves Population fingerprint")
	_equal(geography.state_fingerprint(), geography_before_control, "control prepare preserves Economic Geography fingerprint")
	_check(control.adopt_candidate(control_candidate), "controller change candidate adopts")
	_check(control.authoritative_fingerprint() != control_before, "controller adopt changes Control fingerprint")
	_equal(population.fingerprint(), population_before_control, "controller adopt preserves Population fingerprint")
	_equal(geography.state_fingerprint(), geography_before_control, "controller adopt preserves Economic Geography fingerprint")

	var control_before_transfer: String = control.authoritative_fingerprint()
	var population_before_transfer: String = population.fingerprint()
	var transfer: VNextPopulationCandidate = population.prepare_transfer(
		TERRITORY_A, TERRITORY_B, 10, population.revision()
	)
	_check(transfer != null, "Population transfer candidate prepares")
	_equal(control.authoritative_fingerprint(), control_before_transfer, "Population prepare preserves Control fingerprint")
	_check(transfer != null and population.adopt_candidate(transfer), "Population transfer candidate adopts")
	_check(population.fingerprint() != population_before_transfer, "Population adopt changes Population fingerprint")
	_equal(control.authoritative_fingerprint(), control_before_transfer, "Population adopt preserves Control fingerprint")

	var economy_before_remap: Dictionary = (
		formal.get_persistent_state().get("economy", {}) as Dictionary
	).duplicate(true)
	var geography_before_remap: String = geography.state_fingerprint()
	var remap: VNextEconomicGeographyCandidate = geography.prepare_remap(
		TERRITORY_A, market_ids[1], geography.revision()
	)
	_check(remap != null, "Economic Geography remap candidate prepares")
	_equal(
		formal.get_persistent_state().get("economy", {}),
		economy_before_remap,
		"Economic Geography prepare preserves Economy state"
	)
	_check(remap != null and geography.adopt_candidate(remap), "Economic Geography remap candidate adopts")
	_check(geography.state_fingerprint() != geography_before_remap, "remap changes Economic Geography fingerprint")
	_equal(
		formal.get_persistent_state().get("economy", {}),
		economy_before_remap,
		"Economic Geography adopt preserves Economy state"
	)

	var formal_source: String = FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_simulation.gd"
	)
	for domain_type: String in [
		"VNextTerritorialControlLedger",
		"VNextPopulationAuthority",
		"VNextEconomicGeographyService",
	]:
		_check(not formal_source.contains(domain_type), "%s is not composed into Formal" % domain_type)
	for domain_path: String in [
		"res://scripts/vnext/territory/territorial_control_ledger.gd",
		"res://scripts/vnext/population/population_authority.gd",
		"res://scripts/vnext/economic_geography/economic_geography_service.gd",
		"res://scripts/vnext/organization/organization_core.gd",
	]:
		var source: String = FileAccess.get_file_as_string(domain_path)
		_check(
			not source.contains("WorldTransactionCoordinator"),
			"%s remains outside real Transaction integration" % domain_path
		)


func _make_catalog() -> VNextTerritoryUnitCatalog:
	var catalog := VNextTerritoryUnitCatalog.new()
	if not catalog.configure(TERRITORY_VERSION):
		return null
	for territory_unit_id: String in [TERRITORY_A, TERRITORY_B]:
		var unit := VNextTerritoryUnit.new()
		if not unit.configure(
			territory_unit_id,
			TERRITORY_VERSION,
			"geometry://current-world-convergence/%s" % territory_unit_id.get_slice(":", 1),
			SOURCE_REF
		):
			return null
		if not catalog.add_unit(unit):
			return null
	return catalog if catalog.seal() else null


func _make_political_view() -> RuntimePoliticalEntityView:
	return RuntimePoliticalEntityView.new({
		"schema_id": "runtime_political_registry_v2",
		"entities": [
			_entity(CONTROLLER_A, "historical_convergence_a"),
			_entity(CONTROLLER_B, "historical_convergence_b"),
		],
		"authority_relations": [],
	})


func _entity(runtime_id: String, source_id: String) -> Dictionary:
	return {
		"runtime_id": runtime_id,
		"source_historical_ids": [source_id],
		"lifecycle_status": "active",
		"lineage": {
			"origin_kind": "historical_seed",
			"origin_tick": 0,
			"predecessor_runtime_ids": [],
		},
	}


func _assigned(territory_unit_id: String, market_id: String) -> Dictionary:
	return {
		"territory_unit_id": territory_unit_id,
		"assignment_state": VNextEconomicGeographyService.ASSIGNED,
		"market_id": market_id,
	}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])
