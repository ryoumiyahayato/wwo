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
	_test_v9_deterministic_baseline_rejection()
	_test_production_composition_and_ownership()
	_test_formal_clock_partition_invariance()
	print("Formal Spatial authority integration: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("FORMAL_SPATIAL_AUTHORITY_INTEGRATION_COMPLETE=1")
	quit(0)


func _test_v9_deterministic_baseline_rejection() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v9"
	var candidate_1 := world.persistence.restore_candidate(old)
	if candidate_1.success:
		world = candidate_1
	_check(not candidate_1.success, "v9 save format is rejected")
	_check(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_check(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _test_production_composition_and_ownership() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "Formal world initializes with production Spatial authority")
	if not world.success:
		return
	var state := world.persistence.snapshot()
	var spatial := world.world.spatial_world.snapshot()
	_equal(str(state.get("schema_id", "")), "formal_world_simulation_v15", "Formal schema is v15")
	_check(not spatial.is_empty(), "Formal initialization creates one valid Spatial authority")
	_equal(world.world.spatial_world.current_hour(), 0, "initial Spatial hour is Formal hour zero")
	_equal(
		world.world.spatial_world.current_hour(),
		int(world.world.game_clock.total_minutes() / MINUTES_PER_HOUR),
		"Spatial hour equals Formal authoritative total hour"
	)
	_equal(
		WorldBootstrap.TERRITORIAL_CONTROL_OWNER,
		"TerritoryState",
		"production territorial controller owner is explicit"
	)
	_check(
		world.world.territory_state != null,
		"TerritoryState is composed as the sole controller owner"
	)
	_check(
		WorldBootstrap.TERRITORY_AUTHORITY_PRODUCTION_STATUS.contains(
			"TERRITORY_STATE_SINGLE_AUTHORITY"
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
			(territory_records[0] as Dictionary).size() == 4 and state.has("territory"),
			"Spatial has only spatial fields; TerritoryState owns controller facts"
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
	var person := world.world.person_overlay.person(WorldBootstrap.DEFAULT_FORMAL_PERSON_ID)
	_equal(
		str(person.get("current_place_id", "")),
		WorldBootstrap.DEFAULT_FORMAL_PERSON_PLACE_ID,
		"existing Person place binding still consumes composed Spatial catalog"
	)


func _test_formal_clock_partition_invariance() -> void:
	var bulk := WorldBootstrap.new().build()
	var partitioned := WorldBootstrap.new().build()
	_check(bulk.success, "bulk Formal Spatial world initializes")
	_check(partitioned.success, "partitioned Formal Spatial world initializes")
	if not bulk.success or not partitioned.success:
		return
	bulk.simulation_step.advance_minutes(HOURS_PER_DAY * MINUTES_PER_HOUR)
	for _hour: int in range(HOURS_PER_DAY):
		partitioned.simulation_step.advance_minutes(MINUTES_PER_HOUR)
	_equal(bulk.world.spatial_world.current_hour(), HOURS_PER_DAY, "bulk clock reaches hour 24")
	_equal(partitioned.world.spatial_world.current_hour(), HOURS_PER_DAY, "partitioned clock reaches hour 24")
	_equal(
		bulk.world.spatial_world.snapshot(),
		partitioned.world.spatial_world.snapshot(),
		"Formal Spatial state is invariant between 1x24h and 24x1h"
	)
	_equal(
		JSON.stringify(bulk.world.spatial_world.snapshot()).sha256_text(),
		JSON.stringify(partitioned.world.spatial_world.snapshot()).sha256_text(),
		"Formal Spatial fingerprint is time-partition invariant"
	)
	_equal(
		bulk.world.spatial_world.current_hour(),
		int(bulk.world.game_clock.total_minutes() / MINUTES_PER_HOUR),
		"bulk Spatial clock remains synchronized"
	)
	_equal(
		partitioned.world.spatial_world.current_hour(),
		int(partitioned.world.game_clock.total_minutes() / MINUTES_PER_HOUR),
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
