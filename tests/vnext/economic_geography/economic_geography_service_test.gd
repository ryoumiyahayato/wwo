extends SceneTree
## B3 owner, reference, candidate, persistence, and scope regressions.

const SERVICE = preload("res://scripts/vnext/economic_geography/economic_geography_service.gd")
const CANDIDATE = preload("res://scripts/vnext/economic_geography/economic_geography_candidate.gd")
const TERRITORY_CATALOG = preload("res://scripts/vnext/territory/territory_unit_catalog.gd")
const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")

const TERRITORY_VERSION: String = "economic-geography-fixture-v1"
const TERRITORIES: Array[String] = [
	"territory_unit:alpha",
	"territory_unit:beta",
	"territory_unit:gamma",
	"territory_unit:zeta",
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_reference_validation_and_initialization()
	_test_reads_determinism_and_isolation()
	_test_unassigned_and_candidate_atomicity()
	_test_candidate_reference_bindings_and_malformed_input()
	_test_fingerprint_properties()
	_test_snapshot_restore_and_rejections()
	_test_political_and_economy_decoupling()
	_test_static_owner_and_scope_boundaries()
	print("VNext economic geography foundation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_reference_validation_and_initialization() -> void:
	var catalog: VNextTerritoryUnitCatalog = _catalog()
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var service := VNextEconomicGeographyService.new()
	_check(
		service.configure(
			catalog,
			registry,
			[
				_assigned("territory_unit:alpha", markets[0]),
				_assigned("territory_unit:beta", markets[1]),
			]
		),
		"valid territory-to-Market initialization succeeds"
	)
	_equal(service.revision(), 0, "initial composition begins at revision zero")
	_equal(
		service.market_for_territory("territory_unit:alpha"),
		_assigned("territory_unit:alpha", markets[0]),
		"initialized primary Market is authoritative"
	)

	var missing_territory := VNextEconomicGeographyService.new()
	_check(
		not missing_territory.configure(null, registry),
		"missing Territory provider fails closed"
	)
	var missing_market := VNextEconomicGeographyService.new()
	_check(
		not missing_market.configure(catalog, null),
		"missing Market identity provider fails closed"
	)
	var unsealed_catalog := VNextTerritoryUnitCatalog.new()
	_check(unsealed_catalog.configure(TERRITORY_VERSION), "unsealed fixture configures")
	var unsealed_service := VNextEconomicGeographyService.new()
	_check(
		not unsealed_service.configure(unsealed_catalog, registry),
		"unsealed Territory provider fails closed"
	)

	_expect_configuration_failure(
		catalog,
		registry,
		[_assigned("territory_unit:", markets[0])],
		"malformed Territory ID"
	)
	_expect_configuration_failure(
		catalog,
		registry,
		[_assigned("state:alpha", markets[0])],
		"wrong-kind Territory ID"
	)
	_expect_configuration_failure(
		catalog,
		registry,
		[_assigned("territory_unit:unknown", markets[0])],
		"unknown Territory ID"
	)
	_expect_configuration_failure(
		catalog,
		registry,
		[_assigned("territory_unit:alpha", "market:")],
		"malformed Market ID"
	)
	_expect_configuration_failure(
		catalog,
		registry,
		[_assigned("territory_unit:alpha", "state:market_a")],
		"wrong-kind Market ID"
	)
	_expect_configuration_failure(
		catalog,
		registry,
		[_assigned("territory_unit:alpha", "market:legacy_aggregate:unknown")],
		"unknown Market ID"
	)
	_expect_configuration_failure(
		catalog,
		registry,
		[
			_assigned("territory_unit:alpha", markets[0]),
			_unassigned("territory_unit:alpha"),
		],
		"duplicate initialization"
	)
	_equal(
		service.market_for_territory("territory_unit:"),
		{},
		"malformed Territory query fails closed"
	)
	_equal(
		service.market_for_territory("state:alpha"),
		{},
		"wrong-kind Territory query fails closed"
	)
	_equal(
		service.market_for_territory("territory_unit:unknown"),
		{},
		"unknown Territory query fails closed"
	)


func _test_reads_determinism_and_isolation() -> void:
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var service: VNextEconomicGeographyService = _service(
		registry,
		[
			_assigned("territory_unit:zeta", markets[1]),
			_assigned("territory_unit:gamma", markets[0]),
			_assigned("territory_unit:alpha", markets[0]),
		]
	)
	_equal(
		service.territories_for_market(markets[0]),
		["territory_unit:alpha", "territory_unit:gamma"],
		"reverse query uses canonical Territory ordering"
	)
	_equal(
		service.territories_for_market("market:legacy_aggregate:unknown"),
		[],
		"unknown Market reverse query fails closed"
	)
	var expected_ids: Array[String] = TERRITORIES.duplicate()
	_equal(
		_assignment_ids(service.all_assignments()),
		expected_ids,
		"all assignments use deterministic Territory ordering"
	)
	_equal(
		service.market_for_territory("territory_unit:beta"),
		_unassigned("territory_unit:beta"),
		"known absent initialization has explicit unassigned semantics"
	)
	_check(service.validates_assignment_coverage(), "partial coverage is valid by default policy")
	_check(
		not service.validates_assignment_coverage(true),
		"complete assignment coverage is an explicit stricter policy"
	)

	var detached_assignment: Dictionary = service.market_for_territory("territory_unit:alpha")
	detached_assignment["market_id"] = markets[2]
	var detached_all: Array[Dictionary] = service.all_assignments()
	detached_all[0]["territory_unit_id"] = "territory_unit:mutated"
	detached_all.clear()
	var detached_reverse: Array[String] = service.territories_for_market(markets[0])
	detached_reverse.clear()
	_equal(
		service.market_for_territory("territory_unit:alpha"),
		_assigned("territory_unit:alpha", markets[0]),
		"caller mutation cannot change authoritative assignment"
	)
	_equal(
		service.territories_for_market(markets[0]).size(),
		2,
		"caller mutation cannot change reverse query authority"
	)


func _test_unassigned_and_candidate_atomicity() -> void:
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var service: VNextEconomicGeographyService = _service(registry)
	var initial_fingerprint: String = service.state_fingerprint()
	var initial_snapshot: Dictionary = service.snapshot()
	var candidate: VNextEconomicGeographyCandidate = service.prepare_remap(
		"territory_unit:alpha", markets[0], service.revision()
	)
	_check(candidate != null and candidate.is_well_formed(), "valid remap candidate prepares")
	_equal(service.snapshot(), initial_snapshot, "prepare performs no live mutation")
	var detached_target: Dictionary = candidate.target_assignment()
	detached_target["market_id"] = markets[1]
	var detached_candidate: Dictionary = candidate.to_detached_dict()
	(detached_candidate["target_assignment"] as Dictionary)["market_id"] = markets[2]
	_equal(service.snapshot(), initial_snapshot, "candidate values are detached from authority")
	_equal(candidate.target_assignment().get("market_id"), markets[0], "candidate getters are detached")

	var before_revision: int = service.revision()
	_check(service.adopt_candidate(candidate), "valid remap candidate adopts")
	_equal(service.revision(), before_revision + 1, "successful adopt increments revision exactly once")
	_equal(
		service.market_for_territory("territory_unit:alpha"),
		_assigned("territory_unit:alpha", markets[0]),
		"UNASSIGNED to Market remap adopts"
	)
	_check(service.state_fingerprint() != initial_fingerprint, "changed mapping changes fingerprint")

	var stale_before: Dictionary = service.snapshot()
	var stale_revision: int = service.revision()
	_check(not service.adopt_candidate(candidate), "stale candidate is rejected")
	_equal(service.revision(), stale_revision, "failed stale adopt leaves revision unchanged")
	_equal(service.snapshot(), stale_before, "failed stale adopt leaves authority hash unchanged")
	_check(
		service.prepare_remap("territory_unit:alpha", markets[1], stale_revision - 1) == null,
		"prepare rejects stale expected revision"
	)

	var unassign: VNextEconomicGeographyCandidate = service.prepare_unassign(
		"territory_unit:alpha", service.revision()
	)
	_check(unassign != null, "Market to UNASSIGNED candidate prepares")
	_check(service.adopt_candidate(unassign), "Market to UNASSIGNED candidate adopts")
	_equal(
		service.market_for_territory("territory_unit:alpha"),
		_unassigned("territory_unit:alpha"),
		"Market to UNASSIGNED semantics are explicit"
	)
	_equal(service.state_fingerprint(), initial_fingerprint, "same mapping restores same fingerprint")


func _test_candidate_reference_bindings_and_malformed_input() -> void:
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var service: VNextEconomicGeographyService = _service(registry)
	var valid: VNextEconomicGeographyCandidate = service.prepare_remap(
		"territory_unit:alpha", markets[0], service.revision()
	)
	var before: Dictionary = service.snapshot()
	var invalid_target := VNextEconomicGeographyCandidate.new()
	_check(
		invalid_target.configure(
			service.revision(),
			_unassigned("territory_unit:alpha"),
			_assigned("territory_unit:alpha", "market:legacy_aggregate:unknown"),
			service.territory_catalog_binding(),
			service.market_identity_binding()
		),
		"syntactically valid unknown-Market candidate can be detached"
	)
	_check(not service.adopt_candidate(invalid_target), "candidate revalidates unknown Market reference")
	_equal(service.snapshot(), before, "unknown-Market candidate rejection is atomic")

	var wrong_territory_binding: Dictionary = service.territory_catalog_binding()
	wrong_territory_binding["catalog_fingerprint"] = "0".repeat(64)
	var catalog_mismatch := VNextEconomicGeographyCandidate.new()
	_check(
		catalog_mismatch.configure(
			service.revision(),
			valid.before_assignment(),
			valid.target_assignment(),
			wrong_territory_binding,
			service.market_identity_binding()
		),
		"detached catalog-mismatch candidate configures"
	)
	_check(not service.adopt_candidate(catalog_mismatch), "Territory catalog binding mismatch rejects")

	var wrong_market_binding: Dictionary = service.market_identity_binding()
	wrong_market_binding["identity_fingerprint"] = "f".repeat(64)
	var market_mismatch := VNextEconomicGeographyCandidate.new()
	_check(
		market_mismatch.configure(
			service.revision(),
			valid.before_assignment(),
			valid.target_assignment(),
			service.territory_catalog_binding(),
			wrong_market_binding
		),
		"detached Market-mismatch candidate configures"
	)
	_check(not service.adopt_candidate(market_mismatch), "Market identity binding mismatch rejects")

	var malformed: Dictionary = valid.to_detached_dict()
	malformed["candidate_fingerprint"] = "0".repeat(64)
	_check(CANDIDATE.from_detached_dict(malformed) == null, "corrupted candidate fingerprint fails closed")
	var extended: Dictionary = valid.to_detached_dict()
	extended["controller_id"] = "state:external"
	_check(CANDIDATE.from_detached_dict(extended) == null, "candidate rejects foreign political fields")
	_equal(service.snapshot(), before, "all failed candidates preserve authority and revision")


func _test_fingerprint_properties() -> void:
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var forward_records: Array = [
		_assigned("territory_unit:alpha", markets[0]),
		_assigned("territory_unit:gamma", markets[1]),
	]
	var reverse_records: Array = forward_records.duplicate(true)
	reverse_records.reverse()
	var forward: VNextEconomicGeographyService = _service(registry, forward_records)
	var reverse: VNextEconomicGeographyService = _service(registry, reverse_records)
	_equal(
		forward.state_fingerprint(),
		reverse.state_fingerprint(),
		"fingerprint is independent of initialization insertion order"
	)
	_equal(
		forward.all_assignments(),
		reverse.all_assignments(),
		"canonical assignments are independent of insertion order"
	)
	_equal(forward.state_fingerprint().length(), 64, "state fingerprint is SHA-256")


func _test_snapshot_restore_and_rejections() -> void:
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var source: VNextEconomicGeographyService = _service(
		registry,
		[
			_assigned("territory_unit:alpha", markets[0]),
			_assigned("territory_unit:zeta", markets[1]),
		]
	)
	var remap: VNextEconomicGeographyCandidate = source.prepare_remap(
		"territory_unit:alpha", markets[2], source.revision()
	)
	_check(source.adopt_candidate(remap), "snapshot fixture advances revision")
	var saved: Dictionary = source.snapshot()
	_equal(saved.get("schema_id"), SERVICE.SNAPSHOT_SCHEMA_ID, "snapshot schema is versioned")
	_equal(saved.size(), 6, "snapshot has an exact deterministic field set")
	_equal(
		JSON.stringify(source.snapshot()),
		JSON.stringify(source.snapshot()),
		"snapshot serialization is deterministic"
	)
	var restored: VNextEconomicGeographyService = _service(registry)
	_check(restored.restore(JSON.stringify(saved)), "JSON snapshot parses and restores")
	_equal(restored.snapshot(), saved, "snapshot round-trip is exact")

	var duplicate: Dictionary = saved.duplicate(true)
	var duplicate_records: Array = duplicate.get("assignments") as Array
	duplicate_records.append((duplicate_records[0] as Dictionary).duplicate(true))
	_expect_restore_failure(restored, duplicate, "duplicate snapshot Territory assignment")
	var malformed_territory: Dictionary = saved.duplicate(true)
	(malformed_territory["assignments"] as Array)[0]["territory_unit_id"] = "territory_unit:"
	_expect_restore_failure(restored, malformed_territory, "malformed snapshot Territory")
	var unknown_territory: Dictionary = saved.duplicate(true)
	(unknown_territory["assignments"] as Array)[0]["territory_unit_id"] = "territory_unit:unknown"
	_expect_restore_failure(restored, unknown_territory, "unknown snapshot Territory")
	var malformed_market: Dictionary = saved.duplicate(true)
	var assigned_index: int = _first_assigned_index(malformed_market.get("assignments") as Array)
	(malformed_market["assignments"] as Array)[assigned_index]["market_id"] = "market:"
	_expect_restore_failure(restored, malformed_market, "malformed snapshot Market")
	var unknown_market: Dictionary = saved.duplicate(true)
	(unknown_market["assignments"] as Array)[assigned_index]["market_id"] = "market:legacy_aggregate:unknown"
	_expect_restore_failure(restored, unknown_market, "unknown snapshot Market")
	var corrupted: Dictionary = saved.duplicate(true)
	corrupted["state_fingerprint"] = "0".repeat(64)
	_expect_restore_failure(restored, corrupted, "corrupted snapshot fingerprint")
	var wrong_catalog: Dictionary = saved.duplicate(true)
	(wrong_catalog["territory_catalog_binding"] as Dictionary)["catalog_fingerprint"] = "0".repeat(64)
	_expect_restore_failure(restored, wrong_catalog, "incompatible Territory catalog binding")
	var wrong_market: Dictionary = saved.duplicate(true)
	(wrong_market["market_identity_binding"] as Dictionary)["identity_fingerprint"] = "0".repeat(64)
	_expect_restore_failure(restored, wrong_market, "incompatible Market identity binding")
	var invalid_revision: Dictionary = saved.duplicate(true)
	invalid_revision["revision"] = -1
	_expect_restore_failure(restored, invalid_revision, "invalid snapshot revision")
	var unsupported: Dictionary = saved.duplicate(true)
	unsupported["schema_id"] = "vnext_economic_geography_snapshot_v2"
	_expect_restore_failure(restored, unsupported, "unsupported snapshot schema")


func _test_political_and_economy_decoupling() -> void:
	var registry: FormalWorldMarketRegistry = _market_registry()
	var markets: Array[String] = _market_ids(registry)
	var service: VNextEconomicGeographyService = _service(
		registry, [_assigned("territory_unit:alpha", markets[0])]
	)
	var external_control: Dictionary = {
		"territory_unit_id": "territory_unit:alpha",
		"controller_id": "state:polity_a",
	}
	var before_fingerprint: String = service.state_fingerprint()
	var before_assignment: Dictionary = service.market_for_territory("territory_unit:alpha")
	external_control["controller_id"] = "state:polity_b"
	_equal(
		service.state_fingerprint(),
		before_fingerprint,
		"simulated political controller change leaves geography fingerprint unchanged"
	)
	_equal(
		service.market_for_territory("territory_unit:alpha"),
		before_assignment,
		"political controller change does not remap primary Market"
	)
	var authority_text: String = JSON.stringify(service.snapshot())
	_check(not authority_text.contains("controller_id"), "authority snapshot excludes controller identity")
	_check(not authority_text.contains("sovereign_id"), "authority snapshot excludes sovereign identity")
	_check(not authority_text.contains("polity"), "authority snapshot excludes polity membership")

	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "formal Economy decoupling fixture initializes")
	if not simulation.initialized:
		return
	var formal_markets: Array[String] = simulation.market_registry_view().market_ids()
	var formal_geography: VNextEconomicGeographyService = _service(
		simulation.market_registry_view(),
		[_assigned("territory_unit:alpha", formal_markets[0])]
	)
	var economy_before: Dictionary = (
		simulation.get_persistent_state().get("economy", {}) as Dictionary
	).duplicate(true)
	var geography_remap: VNextEconomicGeographyCandidate = formal_geography.prepare_remap(
		"territory_unit:alpha", formal_markets[1], formal_geography.revision()
	)
	_check(formal_geography.adopt_candidate(geography_remap), "geography-only remap succeeds")
	_equal(
		simulation.get_persistent_state().get("economy", {}),
		economy_before,
		"geography remap does not mutate Economy authoritative state"
	)


func _test_static_owner_and_scope_boundaries() -> void:
	var geography_source: String = FileAccess.get_file_as_string(
		"res://scripts/vnext/economic_geography/economic_geography_service.gd"
	)
	var registry_source: String = FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_market_registry.gd"
	)
	var economy_source: String = FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_economy_service.gd"
	)
	for forbidden_field: String in ["controller_id", "sovereign_id", "polity_membership"]:
		_check(
			not geography_source.contains(forbidden_field),
			"Economic Geography source excludes %s" % forbidden_field
		)
	_check(
		not registry_source.contains("territory_unit"),
		"MarketRegistry does not become Territory mapping owner"
	)
	_check(
		not economy_source.contains("territory_unit"),
		"EconomyService does not become Territory mapping owner"
	)
	_check(
		not economy_source.contains("country_states_by_territory"),
		"country_states compatibility projection is not geography authority"
	)
	for forbidden_gameplay: String in [
		"trade_route",
		"customs_union",
		"transport_capacity",
		"tariff_rate",
		"market_merge",
		"market_split",
	]:
		_check(
			not geography_source.contains(forbidden_gameplay),
			"Economic Geography introduces no %s gameplay" % forbidden_gameplay
		)
	_check(
		not geography_source.contains("WorldTransactionCoordinator"),
		"domain-local candidate does not integrate Transaction Coordinator"
	)


func _catalog() -> VNextTerritoryUnitCatalog:
	var catalog := VNextTerritoryUnitCatalog.new()
	if not catalog.configure(TERRITORY_VERSION):
		return null
	for territory_unit_id: String in TERRITORIES:
		var unit := VNextTerritoryUnit.new()
		if not unit.configure(
			territory_unit_id,
			TERRITORY_VERSION,
			"geometry://economic-geography/%s" % territory_unit_id.get_slice(":", 1),
			"fixture://economic-geography/v1"
		):
			return null
		if not catalog.add_unit(unit):
			return null
	return catalog if catalog.seal() else null


func _market_registry() -> FormalWorldMarketRegistry:
	var aggregate_ids: Array[String] = []
	for index: int in FormalWorldMarketRegistry.EXPECTED_COMPATIBILITY_MARKET_COUNT:
		aggregate_ids.append("economic_fixture_%02d" % index)
	var registry := FormalWorldMarketRegistry.new()
	return registry if registry.configure(aggregate_ids, []) else null


func _market_ids(provider: Variant) -> Array[String]:
	var ids: Array[String] = []
	if provider is FormalWorldMarketRegistry:
		var snapshot: Dictionary = (provider as FormalWorldMarketRegistry).read_only_snapshot()
		for record: Dictionary in DataRecordUtils.to_dictionary_array(snapshot.get("markets", [])):
			ids.append(str(record.get("market_id", "")))
	else:
		ids = provider.market_ids()
	ids.sort()
	return ids


func _service(provider: Variant, initial_assignments: Array = []) -> VNextEconomicGeographyService:
	var service := VNextEconomicGeographyService.new()
	if not service.configure(_catalog(), provider, initial_assignments):
		return null
	return service


func _assigned(territory_unit_id: String, market_id: String) -> Dictionary:
	return {
		"territory_unit_id": territory_unit_id,
		"assignment_state": SERVICE.ASSIGNED,
		"market_id": market_id,
	}


func _unassigned(territory_unit_id: String) -> Dictionary:
	return {
		"territory_unit_id": territory_unit_id,
		"assignment_state": SERVICE.UNASSIGNED,
	}


func _assignment_ids(assignments: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for assignment: Dictionary in assignments:
		ids.append(str(assignment.get("territory_unit_id", "")))
	return ids


func _first_assigned_index(assignments: Array) -> int:
	for index: int in assignments.size():
		if (assignments[index] as Dictionary).get("assignment_state") == SERVICE.ASSIGNED:
			return index
	return -1


func _expect_configuration_failure(
	catalog: VNextTerritoryUnitCatalog,
	registry: FormalWorldMarketRegistry,
	assignments: Array,
	label: String
) -> void:
	var service := VNextEconomicGeographyService.new()
	_check(not service.configure(catalog, registry, assignments), "%s fails closed" % label)
	_check(not service.is_configured(), "%s leaves no configured authority" % label)


func _expect_restore_failure(
	service: VNextEconomicGeographyService, rejected: Variant, label: String
) -> void:
	var before: Dictionary = service.snapshot()
	var before_revision: int = service.revision()
	_check(not service.restore(rejected), "%s is rejected" % label)
	_equal(service.snapshot(), before, "%s rejection is atomic" % label)
	_equal(service.revision(), before_revision, "%s rejection preserves revision" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
