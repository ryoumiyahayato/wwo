extends SceneTree
## Permanent E1-B ownership, mutation, persistence and observer boundary guards.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "formal composition initializes")
	if simulation.initialized:
		_check_source_loading_boundary()
		_check_mutation_isolation(simulation)
		_check_population_contract(simulation)
		_check_static_dynamic_save_boundary(simulation)
		_check_restore_references_and_atomicity(simulation)
		_check_v4_candidate_migration(simulation)
		_check_observer_contract(simulation)
		_check_second_initialization_fails(simulation)
	print("Formal economic boundary closure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_source_loading_boundary() -> void:
	var service_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_economy_service.gd"
	)
	_check(not service_source.contains("FileAccess"), "economy service cannot open source files")
	_check(
		not service_source.contains("political_units_1900.json"),
		"economy service cannot load political evidence"
	)
	_check(
		not service_source.contains("commodity_market_1900.json"),
		"commodity evidence is loaded only by composition-owned catalog"
	)
	_check(
		not service_source.contains("AlphaHistoricalWorldEconomyData.new"),
		"historical bootstrap loader is not economy-owned"
	)


func _check_mutation_isolation(simulation: FormalWorldSimulation) -> void:
	var before := simulation.get_persistent_state()
	var view := simulation.economy
	var copied_states := view.country_states
	var economy_ids: Array = copied_states.keys()
	economy_ids.sort()
	_check(not economy_ids.is_empty(), "observer exposes copied economy states")
	if not economy_ids.is_empty():
		var economy_id := str(economy_ids[0])
		var copied_country := copied_states[economy_id] as Dictionary
		var inventory := copied_country.get("inventory", {}) as Dictionary
		var commodity_ids: Array = inventory.keys()
		commodity_ids.sort()
		if not commodity_ids.is_empty():
			inventory[str(commodity_ids[0])] = -100.0
		copied_country["inventory"] = inventory
		copied_states[economy_id] = copied_country
	_check(
		simulation.get_persistent_state() == before,
		"mutating observer copies cannot mutate authoritative economy"
	)
	var shipments_copy := view.shipments
	shipments_copy.append({"shipment_id": "observer-only"})
	_check(
		simulation.get_persistent_state() == before,
		"mutating copied shipment list cannot mutate authoritative shipments"
	)


func _check_population_contract(simulation: FormalWorldSimulation) -> void:
	var observation := simulation.economy.observation()
	var facts := observation.get("fact_sources", {}) as Dictionary
	_check(not str(facts.get("population_revision", "")).is_empty(), "population revision exposed")
	_check(not str(facts.get("population_fingerprint", "")).is_empty(), "population fingerprint exposed")
	var dynamic_states := (
		observation.get("economic_state", {}) as Dictionary
	).get("markets", {}) as Dictionary
	for state_value: Variant in dynamic_states.values():
		var state := state_value as Dictionary
		_check(not state.has("population"), "economy dynamic state owns no population truth")
		_check(not state.has("population_bounds"), "economy dynamic state owns no demographic bounds")
		_check(not state.has("urban_share_bp"), "economy dynamic state owns no urban demographic fact")


func _check_static_dynamic_save_boundary(simulation: FormalWorldSimulation) -> void:
	var economy_state := simulation.get_persistent_state().get("economy", {}) as Dictionary
	_check(
		str(economy_state.get("schema_id", "")) == "formal_world_economy_state_v6",
		"production save uses market-scoped dynamic-only v6 schema"
	)
	_check(economy_state.has("static_evidence"), "save references static evidence revision")
	_check(economy_state.has("population_input"), "save references population input revision")
	_check(not economy_state.has("history"), "save excludes derived observer history")
	_check(not economy_state.has("routes"), "save excludes static route capability evidence")
	_check(not economy_state.has("projection"), "save excludes derived projections")
	_check(not economy_state.has("ui_history"), "save excludes UI history")
	_check(not economy_state.has("country_states"), "v6 save excludes legacy country-state projection")
	for state_value: Variant in (economy_state.get("market_states", {}) as Dictionary).values():
		var state := state_value as Dictionary
		for forbidden: String in [
			"population", "production", "infrastructure", "income_per_capita",
			"rank", "playability_tier", "polity_ids",
		]:
			_check(not state.has(forbidden), "dynamic save excludes static field %s" % forbidden)


func _check_restore_references_and_atomicity(simulation: FormalWorldSimulation) -> void:
	simulation.advance_minutes(25 * 60)
	var before := simulation.get_persistent_state()
	for field: String in ["static_evidence", "population_input"]:
		var rejected := before.duplicate(true)
		var economy_state := rejected.get("economy", {}) as Dictionary
		var reference := economy_state.get(field, {}) as Dictionary
		reference["revision"] = "invalid"
		economy_state[field] = reference
		rejected["economy"] = economy_state
		_check(not simulation.restore_persistent_state(rejected), "%s revision mismatch rejected" % field)
		_check(simulation.get_persistent_state() == before, "%s rejection is atomic" % field)
	var missing := before.duplicate(true)
	var missing_economy := missing.get("economy", {}) as Dictionary
	missing_economy.erase("static_evidence")
	missing["economy"] = missing_economy
	_check(not simulation.restore_persistent_state(missing), "missing static catalog reference rejected")
	_check(simulation.get_persistent_state() == before, "missing catalog rejection is atomic")


func _check_v4_candidate_migration(simulation: FormalWorldSimulation) -> void:
	var legacy_world := simulation.get_persistent_state()
	legacy_world["economy"] = simulation.economy_regression_snapshot()
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "v4 migration target initializes")
	_check(restored.restore_persistent_state(legacy_world), "v4 mixed-state save migrates through candidate")
	var migrated_economy := restored.get_persistent_state().get("economy", {}) as Dictionary
	_check(
		str(migrated_economy.get("schema_id", "")) == "formal_world_economy_state_v6",
		"v4 migration adopts market-scoped dynamic-only v6 state"
	)
	_check(not migrated_economy.has("history"), "v4 derived history is not adopted as authority")


func _check_observer_contract(simulation: FormalWorldSimulation) -> void:
	var observation := simulation.economy.observation()
	_check(str(observation.get("domain_owner", "")) == "FormalWorldEconomyService", "observer names domain owner")
	_check(observation.get("fact_sources", {}) is Dictionary, "observer separates fact sources")
	_check(observation.get("economic_state", {}) is Dictionary, "observer separates authoritative economic state")
	_check(observation.get("derived_view", {}) is Dictionary, "observer separates derived views")
	var before := simulation.get_persistent_state()
	(observation.get("economic_state", {}) as Dictionary).clear()
	(observation.get("derived_view", {}) as Dictionary).clear()
	_check(simulation.get_persistent_state() == before, "observer observation is detached from authority")


func _check_second_initialization_fails(simulation: FormalWorldSimulation) -> void:
	var catalog := FormalWorldEconomicEvidenceCatalog.new()
	_check(catalog.configure(), "economic evidence catalog initializes once")
	_check(not catalog.configure(), "economic evidence catalog second initialization fails closed")
	var static_view := FormalWorldEconomicStaticView.new(catalog.economic_snapshot())
	var population_view := FormalWorldPopulationInputView.new(catalog.population_snapshot())
	var service := FormalWorldEconomyService.new()
	service.bind_authoritative_hour_source(func() -> int: return 0)
	_check(
		service.configure(
			simulation.political_registry_view(),
			simulation.market_registry_view(),
			static_view,
			population_view
		),
		"economy owner initializes from immutable inputs"
	)
	_check(
		not service.configure(
			simulation.political_registry_view(),
			simulation.market_registry_view(),
			static_view,
			population_view
		),
		"second economy owner configuration fails closed"
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
