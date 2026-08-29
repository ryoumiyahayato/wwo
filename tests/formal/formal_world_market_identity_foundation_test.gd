extends SceneTree
## Permanent E1-D identity, persistence, observer and ownership guards.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "formal composition initializes with market registry")
	if simulation.initialized:
		_check_identity_contract(simulation)
		_check_invalid_identities()
		_check_registry_guards(simulation)
		_check_economy_scope_and_observer(simulation)
		_check_persistence_and_atomicity(simulation)
		_check_deterministic_state()
		_check_static_ownership_audit()
	print("Formal market identity foundation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_identity_contract(simulation: FormalWorldSimulation) -> void:
	var markets := simulation.market_registry_view()
	_check(markets.is_configured(), "market view is configured")
	_check(markets.market_count() == 50, "exactly 50 compatibility markets exist")
	_check(
		markets.revision() == FormalWorldMarketRegistry.REVISION,
		"market revision is explicit"
	)
	_check(not markets.mapping_fingerprint().is_empty(), "market mapping is fingerprinted")
	var market_ids := markets.market_ids()
	var unique_ids: Dictionary = {}
	var unique_aggregates: Dictionary = {}
	for market_id: String in market_ids:
		var record := markets.market(market_id)
		var aggregate_id := str(record.get("source_economic_aggregate_id", ""))
		_check(market_id.begins_with("market:legacy_aggregate:"), "market ID uses market namespace")
		_check(not market_id.begins_with("state:"), "market ID is not political ID")
		_check(not market_id.begins_with("economic_region:"), "market ID is not EconomicRegion ID")
		_check(not market_id.begins_with("site:"), "market ID is not Site ID")
		_check(not unique_ids.has(market_id), "market identity is unique")
		_check(not unique_aggregates.has(aggregate_id), "aggregate compatibility mapping is unique")
		unique_ids[market_id] = true
		unique_aggregates[aggregate_id] = true
		_check(
			markets.market_id_for_economic_aggregate(aggregate_id) == market_id,
			"aggregate resolves to explicit market"
		)
		_check(
			markets.economic_aggregate_id_for_market(market_id) == aggregate_id,
			"market resolves to source aggregate"
		)


func _check_invalid_identities() -> void:
	var valid := MarketIdentity.compatibility_snapshot(
		"identity_fixture", FormalWorldMarketRegistry.REVISION
	)
	var political_collision := valid.duplicate(true)
	political_collision["market_id"] = "state:identity_fixture"
	_check(
		not MarketIdentity.new(political_collision).is_valid(
			FormalWorldMarketRegistry.REVISION
		),
		"political ID cannot be a market ID"
	)
	var region_collision := valid.duplicate(true)
	region_collision["market_id"] = "economic_region:identity_fixture"
	_check(
		not MarketIdentity.new(region_collision).is_valid(
			FormalWorldMarketRegistry.REVISION
		),
		"EconomicRegion ID cannot be a market ID"
	)
	var site_collision := valid.duplicate(true)
	site_collision["market_id"] = "site:identity_fixture"
	_check(
		not MarketIdentity.new(site_collision).is_valid(
			FormalWorldMarketRegistry.REVISION
		),
		"Site ID cannot be a market ID"
	)
	var missing_revision := valid.duplicate(true)
	missing_revision.erase("revision")
	_check(not MarketIdentity.new(missing_revision).is_valid(), "identity without revision is rejected")


func _check_registry_guards(simulation: FormalWorldSimulation) -> void:
	var aggregate_ids: Array[String] = []
	for record: Dictionary in simulation.market_registry_view().markets():
		aggregate_ids.append(str(record.get("source_economic_aggregate_id", "")))
	var duplicate_ids := aggregate_ids.duplicate()
	duplicate_ids[duplicate_ids.size() - 1] = duplicate_ids[0]
	var duplicate_registry := FormalWorldMarketRegistry.new()
	_check(
		not duplicate_registry.configure(
			duplicate_ids, simulation.political_registry_view().entity_ids()
		),
		"duplicate market identity input fails closed"
	)
	var registry := FormalWorldMarketRegistry.new()
	_check(
		registry.configure(
			aggregate_ids, simulation.political_registry_view().entity_ids()
		),
		"registry fixture initializes once"
	)
	var before := registry.read_only_snapshot()
	_check(
		not registry.configure(
			aggregate_ids, simulation.political_registry_view().entity_ids()
		),
		"second market registry initialization fails"
	)
	_check(registry.read_only_snapshot() == before, "failed reconfiguration preserves registry")
	var copied_markets := simulation.market_registry_view().markets()
	copied_markets.clear()
	_check(
		simulation.market_registry_view().market_count() == 50,
		"consumer mutation cannot alter market registry"
	)


func _check_economy_scope_and_observer(simulation: FormalWorldSimulation) -> void:
	var economy := simulation.economy
	_check(economy.market_states.size() == 50, "Economy owns 50 market-scoped states")
	_check(
		economy.economic_aggregate_states.size() == 50,
		"observer exposes 50 distinct economic aggregates"
	)
	for market_id_value: Variant in economy.market_states:
		var market_id := str(market_id_value)
		var state := economy.market_states[market_id] as Dictionary
		var aggregate_id := str(state.get("source_economic_aggregate_id", ""))
		_check(str(state.get("market_id", "")) == market_id, "market state is keyed by market ID")
		_check(market_id != aggregate_id, "market state does not reuse aggregate ID")
		_check(state.get("inventory", {}) is Dictionary, "inventory is market-scoped")
		_check(state.get("prices", {}) is Dictionary, "prices are market-scoped")
	var summary := simulation.country_summary("united_states_1900")
	_check(str(summary.get("economic_aggregate_id", "")) == "united_states_1900", "summary names aggregate")
	_check(
		str(summary.get("market_id", ""))
		== economy.market_id_for_economic_aggregate("united_states_1900"),
		"summary names pricing market"
	)
	var observation := economy.observation()
	var economic_state := observation.get("economic_state", {}) as Dictionary
	_check(economic_state.has("economic_aggregates"), "observer separates aggregates")
	_check(economic_state.has("markets"), "observer separates markets")
	_check(not economic_state.has("country_states"), "observer does not equate country state with market")
	var facts := observation.get("fact_sources", {}) as Dictionary
	_check(not str(facts.get("market_revision", "")).is_empty(), "observer exposes market revision")
	_check(
		not str(facts.get("market_mapping_fingerprint", "")).is_empty(),
		"observer exposes market mapping fingerprint"
	)


func _check_persistence_and_atomicity(simulation: FormalWorldSimulation) -> void:
	simulation.advance_minutes(30 * 24 * 60)
	var state := simulation.get_persistent_state()
	_check(str(state.get("schema_id", "")) == "formal_world_simulation_v4", "world save is v4")
	var market_state := state.get("markets", {}) as Dictionary
	_check(
		str(market_state.get("schema_id", "")) == "formal_world_market_state_v1",
		"market persistence uses v1 identity state"
	)
	_check(market_state.keys().size() == 3, "market save contains references only")
	_check(not market_state.has("markets"), "market save excludes static identity catalog copy")
	_check(not market_state.has("projection"), "market save excludes observer cache")
	var economy_state := state.get("economy", {}) as Dictionary
	_check(
		str(economy_state.get("schema_id", "")) == "formal_world_economy_state_v6",
		"economy save uses market-scoped v6 state"
	)
	_check(economy_state.has("market_states"), "economy save persists market-scoped dynamics")
	_check(not economy_state.has("country_states"), "economy save excludes aggregate-as-market compatibility projection")
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "roundtrip candidate initializes")
	_check(restored.restore_persistent_state(state), "market save roundtrip succeeds")
	_check(restored.get_persistent_state() == state, "market save roundtrip is exact")

	var before := simulation.get_persistent_state()
	for field: String in ["revision", "mapping_fingerprint"]:
		var rejected := before.duplicate(true)
		var rejected_markets := rejected.get("markets", {}) as Dictionary
		if field == "revision":
			rejected_markets.erase(field)
		else:
			rejected_markets[field] = "invalid"
		rejected["markets"] = rejected_markets
		_check(not simulation.restore_persistent_state(rejected), "invalid market %s is rejected" % field)
		_check(simulation.get_persistent_state() == before, "market rejection is atomic")
	var copied_catalog := before.duplicate(true)
	var copied_market_state := copied_catalog.get("markets", {}) as Dictionary
	copied_market_state["projection_cache"] = []
	copied_catalog["markets"] = copied_market_state
	_check(not simulation.restore_persistent_state(copied_catalog), "market save rejects derived cache")
	_check(simulation.get_persistent_state() == before, "derived-cache rejection is atomic")


func _check_deterministic_state() -> void:
	var first := FormalWorldSimulation.new()
	var second := FormalWorldSimulation.new()
	_check(first.initialize() and second.initialize(), "determinism fixtures initialize")
	if not first.initialized or not second.initialized:
		return
	first.advance_minutes(30 * 24 * 60)
	second.advance_minutes(30 * 24 * 60)
	_check(
		first.market_registry_view().mapping_fingerprint()
		== second.market_registry_view().mapping_fingerprint(),
		"market mapping fingerprint is deterministic"
	)
	_check(first.get_persistent_state() == second.get_persistent_state(), "market-scoped state is deterministic")


func _check_static_ownership_audit() -> void:
	var economy_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_economy_service.gd"
	)
	_check(not economy_source.contains("MarketIdentity.new"), "Economy cannot create market identities")
	_check(
		not economy_source.contains("FormalWorldMarketRegistry.new"),
		"Economy cannot create a market registry"
	)
	_check(
		not economy_source.contains("compatibility_market_id("),
		"Economy cannot synthesize market IDs"
	)
	var registry_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_market_registry.gd"
	)
	_check(not registry_source.contains("FileAccess"), "market registry cannot load source files")
	_check(not registry_source.contains("data/alpha"), "market registry does not import Alpha market data")
	_check(not registry_source.contains("scripts/vnext"), "market registry does not import VNext market data")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
