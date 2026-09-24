extends SceneTree
## Production composition/time/ownership gate for Formal Spatial authority.

const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const LINK_ID: String = "rail_paris_lille"

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_v9_deterministic_baseline_migration()
	_test_production_composition_and_ownership()
	_test_formal_clock_partition_invariance()
	print("Formal Spatial authority integration: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("FORMAL_SPATIAL_AUTHORITY_INTEGRATION_COMPLETE=1")
	quit(0)


func _test_v9_deterministic_baseline_migration() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "v9 migration source initializes")
	if not source.initialized:
		return
	source.advance_minutes(2 * HOURS_PER_DAY * MINUTES_PER_HOUR)
	var legacy := source.get_persistent_state().duplicate(true)
	legacy["schema_id"] = FormalWorldSimulation.SPATIAL_BASELINE_SCHEMA_ID
	legacy.erase("spatial")
	var migrated := FormalWorldSimulation.new()
	_check(migrated.initialize(), "v9 migration target initializes")
	_check(
		migrated.restore_persistent_state(legacy),
		"v9 save without Spatial snapshot restores deterministic baseline"
	)
	if not migrated.initialized:
		return
	_equal(
		migrated.spatial_current_hour(),
		int(migrated.total_minutes / MINUTES_PER_HOUR),
		"v9 migration advances baseline Spatial to saved Formal hour"
	)
	_equal(
		float(migrated.spatial_infrastructure_state(LINK_ID).get("nominal_capacity", -1.0)),
		1000.0,
		"v9 migration fabricates no infrastructure history"
	)
	_equal(
		(migrated.spatial_capacity_summary(LINK_ID).get("reservations", []) as Array).size(),
		0,
		"v9 migration fabricates no capacity reservations"
	)


func _test_production_composition_and_ownership() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "Formal world initializes with production Spatial authority")
	if not world.initialized:
		return
	var state := world.get_persistent_state()
	var spatial := world.spatial_snapshot()
	_equal(str(state.get("schema_id", "")), "formal_world_simulation_v10", "Formal schema advances to v10")
	_check(not spatial.is_empty(), "Formal initialization creates one valid Spatial authority")
	_equal(world.spatial_current_hour(), 0, "initial Spatial hour is Formal hour zero")
	_equal(
		world.spatial_current_hour(),
		int(world.total_minutes / MINUTES_PER_HOUR),
		"Spatial hour equals Formal authoritative total hour"
	)
	_equal(
		FormalWorldSimulation.TERRITORIAL_CONTROL_OWNER,
		"VNextSpatialWorld",
		"production territorial controller owner is explicit"
	)
	_check(
		not FormalWorldSimulation.TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED,
		"TerritorialControlLedger remains non-production and uncomposed"
	)
	_check(
		FormalWorldSimulation.TERRITORY_AUTHORITY_PRODUCTION_STATUS.contains(
			"TERRITORIAL_CONTROL_LEDGER_NON_PRODUCTION_UNCOMPOSED"
		),
		"territory authority production status is explicit"
	)
	_check(state.has("spatial"), "Formal persistence has one Spatial state")
	_check(
		not state.has("territorial_control_ledger"),
		"Formal persistence has no duplicate territorial control ledger"
	)
	var territory_records := spatial.get("territories", []) as Array
	_check(not territory_records.is_empty(), "Spatial snapshot carries territorial facts")
	if not territory_records.is_empty():
		_check(
			(territory_records[0] as Dictionary).has("military_controller_id"),
			"current controller fact remains on the sole composed Spatial owner"
		)
	var economy_state := state.get("economy", {}) as Dictionary
	var military_state := state.get("military_state", {}) as Dictionary
	for forbidden_key: String in [
		"capacity_window",
		"nominal_capacity",
		"effective_capacity",
		"used_capacity",
		"remaining_capacity",
	]:
		_check(
			not _contains_key_recursive(economy_state, forbidden_key),
			"Economy owns no duplicate Spatial capacity key: %s" % forbidden_key
		)
	for forbidden_key: String in [
		"nominal_capacity",
		"effective_capacity",
		"used_capacity",
		"remaining_capacity",
	]:
		_check(
			not _contains_key_recursive(military_state, forbidden_key),
			"Military owns no physical Spatial capacity key: %s" % forbidden_key
		)
	_check(
		military_state.has("capacity_window_hour"),
		"Military retains only its existing local transport-window attribution"
	)
	var person := world.formal_person(FormalWorldSimulation.DEFAULT_FORMAL_PERSON_ID)
	_equal(
		str(person.get("current_place_id", "")),
		FormalWorldSimulation.DEFAULT_FORMAL_PERSON_PLACE_ID,
		"existing Person place binding still consumes composed Spatial catalog"
	)


func _test_formal_clock_partition_invariance() -> void:
	var bulk := FormalWorldSimulation.new()
	var partitioned := FormalWorldSimulation.new()
	_check(bulk.initialize(), "bulk Formal Spatial world initializes")
	_check(partitioned.initialize(), "partitioned Formal Spatial world initializes")
	if not bulk.initialized or not partitioned.initialized:
		return
	bulk.advance_minutes(HOURS_PER_DAY * MINUTES_PER_HOUR)
	for _hour: int in range(HOURS_PER_DAY):
		partitioned.advance_minutes(MINUTES_PER_HOUR)
	_equal(bulk.spatial_current_hour(), HOURS_PER_DAY, "bulk clock reaches hour 24")
	_equal(partitioned.spatial_current_hour(), HOURS_PER_DAY, "partitioned clock reaches hour 24")
	_equal(
		bulk.spatial_snapshot(),
		partitioned.spatial_snapshot(),
		"Formal Spatial state is invariant between 1x24h and 24x1h"
	)
	_equal(
		bulk.spatial_authoritative_fingerprint(),
		partitioned.spatial_authoritative_fingerprint(),
		"Formal Spatial fingerprint is time-partition invariant"
	)
	_equal(
		bulk.spatial_current_hour(),
		int(bulk.total_minutes / MINUTES_PER_HOUR),
		"bulk Spatial clock remains synchronized"
	)
	_equal(
		partitioned.spatial_current_hour(),
		int(partitioned.total_minutes / MINUTES_PER_HOUR),
		"partitioned Spatial clock remains synchronized"
	)


func _contains_key_recursive(value: Variant, key: String) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary := value as Dictionary
		if dictionary.has(key):
			return true
		for child: Variant in dictionary.values():
			if _contains_key_recursive(child, key):
				return true
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value as Array:
			if _contains_key_recursive(child, key):
				return true
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: %s | expected=%s actual=%s" % [label, str(expected), str(actual)])
