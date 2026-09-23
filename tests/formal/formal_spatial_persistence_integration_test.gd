extends SceneTree
## Exact persistence/corruption/fingerprint gate for Formal Spatial authority.

const MINUTES_PER_HOUR: int = 60
const LINK_ID: String = "rail_paris_lille"

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_spatial_exact_restore()
	_test_corrupted_spatial_restore_is_atomic()
	_test_spatial_fingerprint_boundary()
	print("Formal Spatial persistence integration: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("FORMAL_SPATIAL_PERSISTENCE_INTEGRATION_COMPLETE=1")
	quit(0)


func _test_spatial_exact_restore() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "Spatial persistence source initializes")
	if not source.initialized:
		return
	_check(source.set_spatial_nominal_capacity(LINK_ID, 320.0), "Formal authority mutates nominal capacity")
	_check(source.set_spatial_infrastructure_condition(LINK_ID, 0.75), "Formal authority mutates infrastructure condition")
	_check(source.set_spatial_infrastructure_status(LINK_ID, "damaged"), "Formal authority mutates infrastructure status")
	var reservation := source.request_spatial_capacity("formal_spatial_save", LINK_ID, 50.0)
	_check(bool(reservation.get("accepted", false)), "Formal request boundary reserves current Spatial window")
	var before_spatial := source.spatial_snapshot()
	var before_world_fingerprint := source.authoritative_fingerprint()
	var before_spatial_fingerprint := source.spatial_authoritative_fingerprint()
	var saved := source.get_persistent_state()
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "Spatial persistence target initializes")
	_check(restored.restore_persistent_state(saved), "Formal v10 restores exact Spatial snapshot before dependents")
	if not restored.initialized:
		return
	_equal(restored.spatial_snapshot(), before_spatial, "infrastructure and capacity window restore exactly")
	_equal(
		restored.spatial_authoritative_fingerprint(),
		before_spatial_fingerprint,
		"Spatial authoritative fingerprint restores exactly"
	)
	_equal(
		restored.authoritative_fingerprint(),
		before_world_fingerprint,
		"Formal authoritative fingerprint restores exactly with Spatial"
	)
	var summary := restored.spatial_capacity_summary(LINK_ID)
	_equal(
		(summary.get("reservations", []) as Array).size(),
		1,
		"current-hour capacity reservation survives exact Formal restore"
	)
	_equal(
		float(restored.spatial_infrastructure_state(LINK_ID).get("nominal_capacity", -1.0)),
		320.0,
		"nominal capacity survives Formal save/load"
	)
	_equal(
		float(restored.spatial_infrastructure_state(LINK_ID).get("condition", -1.0)),
		0.75,
		"infrastructure condition survives Formal save/load"
	)
	_equal(
		str(restored.spatial_infrastructure_state(LINK_ID).get("status", "")),
		"damaged",
		"infrastructure status survives Formal save/load"
	)
	source.advance_minutes(MINUTES_PER_HOUR)
	restored.advance_minutes(MINUTES_PER_HOUR)
	_equal(
		restored.get_persistent_state(),
		source.get_persistent_state(),
		"saved continuation equals uninterrupted continuation after Spatial window rollover"
	)
	_equal(
		restored.authoritative_fingerprint(),
		source.authoritative_fingerprint(),
		"saved and uninterrupted continuation fingerprints remain exact"
	)


func _test_corrupted_spatial_restore_is_atomic() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "atomic Spatial restore world initializes")
	if not world.initialized:
		return
	_check(world.set_spatial_nominal_capacity(LINK_ID, 444.0), "atomic fixture mutates Spatial")
	var before_state := world.get_persistent_state()
	var before_fingerprint := world.authoritative_fingerprint()
	var malformed := before_state.duplicate(true)
	var spatial := malformed.get("spatial", {}) as Dictionary
	var infrastructure := spatial.get("infrastructure", []) as Array
	if infrastructure.is_empty():
		_check(false, "atomic fixture has infrastructure")
		return
	(infrastructure[0] as Dictionary)["status"] = "corrupted_status"
	_check(
		not world.restore_persistent_state(malformed),
		"corrupted Spatial snapshot is rejected by Formal restore"
	)
	_equal(
		world.get_persistent_state(),
		before_state,
		"failed Spatial restore leaves whole Formal state unchanged"
	)
	_equal(
		world.authoritative_fingerprint(),
		before_fingerprint,
		"failed Spatial restore leaves whole Formal fingerprint unchanged"
	)


func _test_spatial_fingerprint_boundary() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "Spatial fingerprint world initializes")
	if not world.initialized:
		return
	var initial_spatial_fingerprint := world.spatial_authoritative_fingerprint()
	var initial_world_fingerprint := world.authoritative_fingerprint()
	var detached := world.spatial_snapshot()
	detached["projection_cache"] = {"camera": "not-authoritative"}
	var detached_infrastructure := detached.get("infrastructure", []) as Array
	if not detached_infrastructure.is_empty():
		(detached_infrastructure[0] as Dictionary)["debug_counter"] = 999
	_equal(
		world.spatial_authoritative_fingerprint(),
		initial_spatial_fingerprint,
		"detached UI/cache mutation cannot change Spatial authoritative fingerprint"
	)
	_equal(
		world.authoritative_fingerprint(),
		initial_world_fingerprint,
		"detached UI/cache mutation cannot change Formal authoritative fingerprint"
	)
	_check(
		world.set_spatial_infrastructure_condition(LINK_ID, 0.5),
		"authoritative Spatial mutation is accepted"
	)
	_check(
		world.spatial_authoritative_fingerprint() != initial_spatial_fingerprint,
		"authoritative Spatial mutation changes Spatial fingerprint"
	)
	_check(
		world.authoritative_fingerprint() != initial_world_fingerprint,
		"authoritative Spatial mutation changes Formal fingerprint"
	)


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
