extends SceneTree
## Production gate for Formal Current World Population authority integration.

const FRANCE_TERRITORY: String = "territory_unit:gw_220"
const US_TERRITORY: String = "territory_unit:gw_2"
const AUSTRALIA_TERRITORIES: Array[String] = [
	"territory_unit:gw_901",
	"territory_unit:gw_902",
	"territory_unit:gw_903",
	"territory_unit:gw_904",
	"territory_unit:gw_905",
	"territory_unit:gw_906",
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_production_composition_and_evidence_mapping()
	_test_transfer_conservation_and_consumer_boundaries()
	_test_population_restore_atomicity_and_fingerprint()
	_test_v10_deterministic_population_baseline_migration()
	_test_owner_surface()
	print("Formal Population authority integration: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("FORMAL_POPULATION_AUTHORITY_INTEGRATION_COMPLETE=1")
	quit(0)


func _test_production_composition_and_evidence_mapping() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "Formal world initializes with Population authority: %s" % world.initialization_error)
	if not world.initialized:
		return
	_equal(str(world.get_persistent_state().get("schema_id", "")), "formal_world_simulation_v11", "Formal schema advances to v11")
	var population := world.population_snapshot()
	print("TERRITORY_CATALOG_FINGERPRINT=%s" % world.territory_unit_catalog_fingerprint())
	print("POPULATION_BASELINE_FINGERPRINT=%s" % world.population_authoritative_fingerprint())
	_check(not population.is_empty(), "Formal production contains a PopulationAuthority snapshot")
	_equal(
		population.get("territory_catalog_binding"),
		world.territory_unit_catalog_binding(),
		"PopulationAuthority binds the exact production TerritoryUnit catalog"
	)
	_equal(world.population_initialized_territory_count(), 49, "49 one-to-one historical population aggregates initialize exactly")
	_equal(world.population_uninitialized_territory_count(), 102, "remaining source-backed TerritoryUnits stay explicitly uninitialized")
	_equal(
		world.population_unmapped_evidence_ids(),
		["australia_colonies_1900"],
		"only the six-colony Australian aggregate is ambiguous at TerritoryUnit granularity"
	)
	_equal(world.population_total_for_territory(FRANCE_TERRITORY), 40_700_000, "France exact historical aggregate seeds its TerritoryUnit")
	_equal(world.population_total_for_territory(US_TERRITORY), 76_300_000, "United States exact historical aggregate seeds its TerritoryUnit")
	for territory_unit_id: String in AUSTRALIA_TERRITORIES:
		_equal(
			world.population_total_for_territory(territory_unit_id),
			-1,
			"ambiguous Australian aggregate is not fabricated into %s" % territory_unit_id
		)
	var detached := world.population_snapshot()
	var records := detached.get("records", []) as Array
	if not records.is_empty():
		(records[0] as Dictionary)["total_population"] = 0
	_equal(world.population_total_for_territory(FRANCE_TERRITORY), 40_700_000, "detached Population query cannot mutate authority")
	_check(
		not world._population_authority._authority.initialize_population(
			FRANCE_TERRITORY, 1
		),
		"duplicate population initialization fails closed"
	)
	var person_id := world.player_person_id()
	var claim := world.formal_person_population_claim(person_id)
	_equal(
		claim.get("territory_id"),
		FRANCE_TERRITORY,
		"new Formal Person claims authoritative TerritoryUnit identity"
	)
	_equal(
		world.formal_person_anonymous_population(FRANCE_TERRITORY),
		40_700_000,
		"named Person overlays do not subtract one unit from aggregate Population"
	)


func _test_transfer_conservation_and_consumer_boundaries() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "transfer fixture initializes")
	if not world.initialized:
		return
	var before_total := (
		world.population_total_for_territory(FRANCE_TERRITORY)
		+ world.population_total_for_territory(US_TERRITORY)
	)
	var before_world_fingerprint := world.authoritative_fingerprint()
	var before_population_fingerprint := world.population_authoritative_fingerprint()
	var before_economy := world.economy_regression_snapshot()
	var before_military := world._military_state.snapshot()
	var stale := world.prepare_population_transfer(
		FRANCE_TERRITORY, US_TERRITORY, 10, world.population_revision()
	)
	_check(stale != null, "valid Population transfer candidate prepares")
	if stale == null:
		return
	var intervening := world.prepare_population_transfer(
		US_TERRITORY, FRANCE_TERRITORY, 1, world.population_revision()
	)
	_check(intervening != null and world.adopt_population_candidate(intervening), "intervening Population candidate adopts")
	_check(not world.adopt_population_candidate(stale), "stale Population candidate is rejected")
	var candidate := world.prepare_population_transfer(
		FRANCE_TERRITORY, US_TERRITORY, 10, world.population_revision()
	)
	_check(candidate != null and world.adopt_population_candidate(candidate), "fresh Population transfer adopts")
	var after_total := (
		world.population_total_for_territory(FRANCE_TERRITORY)
		+ world.population_total_for_territory(US_TERRITORY)
	)
	_equal(after_total, before_total, "valid Population transfers conserve aggregate total")
	_check(
		world.population_authoritative_fingerprint() != before_population_fingerprint,
		"Population mutation changes Population authoritative fingerprint"
	)
	_check(
		world.authoritative_fingerprint() != before_world_fingerprint,
		"Population mutation changes Formal authoritative fingerprint"
	)
	_equal(
		world.formal_person_anonymous_population(FRANCE_TERRITORY),
		40_699_991,
		"Person overlay reads the live PopulationAuthority after transfers"
	)
	_equal(
		world.economy_regression_snapshot(),
		before_economy,
		"Population transfer does not silently change Economy formulas or settled state"
	)
	_equal(
		world._military_state.snapshot(),
		before_military,
		"Population transfer does not silently mutate Military state"
	)


func _test_population_restore_atomicity_and_fingerprint() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "Population persistence fixture initializes")
	if not world.initialized:
		return
	var transfer := world.prepare_population_transfer(
		FRANCE_TERRITORY, US_TERRITORY, 25, world.population_revision()
	)
	_check(transfer != null and world.adopt_population_candidate(transfer), "persistence fixture mutates Population authority")
	var saved := world.get_persistent_state()
	var saved_population := world.population_snapshot()
	var saved_population_fingerprint := world.population_authoritative_fingerprint()
	var saved_world_fingerprint := world.authoritative_fingerprint()
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "Population restore target initializes")
	_check(restored.restore_persistent_state(saved), "v11 restores exact Population snapshot before Person consumers")
	if restored.initialized:
		_equal(restored.population_snapshot(), saved_population, "Population snapshot restores exactly")
		_equal(restored.population_authoritative_fingerprint(), saved_population_fingerprint, "Population fingerprint restores exactly")
		_equal(restored.authoritative_fingerprint(), saved_world_fingerprint, "Formal fingerprint restores exactly with Population")
		_equal(restored.get_persistent_state(), saved, "v11 complete Formal state restores exactly")

	var before := world.get_persistent_state()
	var before_fingerprint := world.authoritative_fingerprint()
	var malformed := before.duplicate(true)
	var population := malformed.get("population", {}) as Dictionary
	var records := population.get("records", []) as Array
	if records.is_empty():
		_check(false, "corruption fixture contains Population records")
		return
	(records[0] as Dictionary)["total_population"] = -1
	_check(not world.restore_persistent_state(malformed), "corrupted Population snapshot is rejected atomically")
	_equal(world.get_persistent_state(), before, "failed Population restore leaves whole Formal state unchanged")
	_equal(world.authoritative_fingerprint(), before_fingerprint, "failed Population restore leaves whole Formal fingerprint unchanged")


func _test_v10_deterministic_population_baseline_migration() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "v10 migration source initializes")
	if not source.initialized:
		return
	source.advance_minutes(48 * 60)
	var legacy := source.get_persistent_state().duplicate(true)
	legacy["schema_id"] = FormalWorldSimulation.POPULATION_BASELINE_SCHEMA_ID
	legacy.erase("population")
	var persons := (legacy.get("persons", {}) as Dictionary).get("persons", []) as Array
	if not persons.is_empty():
		(persons[0] as Dictionary)["population_territory_id"] = "country_fra"
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "v10 migration target initializes")
	_check(
		restored.restore_persistent_state(legacy),
		"v10 save reconstructs PopulationAuthority only from immutable historical evidence"
	)
	if not restored.initialized:
		return
	var fresh := FormalWorldSimulation.new()
	_check(fresh.initialize(), "fresh Population baseline fixture initializes")
	_equal(
		restored.population_snapshot(),
		fresh.population_snapshot(),
		"v10 migration reconstructs deterministic Population baseline with no demographic history"
	)
	_equal(restored.total_minutes, 48 * 60, "v10 migration preserves authoritative Formal time")
	_equal(
		restored.formal_person_anonymous_population("country_fra"),
		40_700_000,
		"legacy Person population reference resolves through PopulationAuthority compatibility mapping"
	)


func _test_owner_surface() -> void:
	var formal_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_simulation.gd")
	_check(
		not formal_source.contains("VNextMacroPopulation"),
		"Formal production composes no second MacroPopulation total owner"
	)
	_check(
		not formal_source.contains("total_population ="),
		"Formal composition root stores no duplicate writable total_population field"
	)
	_equal(
		FormalWorldSimulation.TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED,
		false,
		"Population integration does not compose TerritorialControlLedger"
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s | actual=%s expected=%s" % [label, var_to_str(actual), var_to_str(expected)])
