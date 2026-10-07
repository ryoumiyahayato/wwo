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
	var source := WorldBootstrap.new().build()
	_check(source.success, "Spatial persistence source initializes")
	if not source.success:
		return
	_check(source.world.spatial_world.set_nominal_capacity(LINK_ID, 320.0), "Formal authority mutates nominal capacity")
	_check(source.world.spatial_world.set_infrastructure_condition(LINK_ID, 0.75), "Formal authority mutates infrastructure condition")
	_check(source.world.spatial_world.set_infrastructure_status(LINK_ID, "damaged"), "Formal authority mutates infrastructure status")
	var reservation := source.world.spatial_world.request_capacity("formal_spatial_save",  LINK_ID, source.world.game_clock.current_hour(),  50.0)
	_check(bool(reservation.get("accepted", false)), "Formal request boundary reserves current Spatial window")
	var before_spatial := source.world.spatial_world.snapshot()
	var before_world_fingerprint := source.persistence.authoritative_fingerprint()
	var before_spatial_fingerprint := JSON.stringify(source.world.spatial_world.snapshot()).sha256_text()
	var saved := source.persistence.snapshot()
	var restored := WorldBootstrap.new().build()
	_check(restored.success, "Spatial persistence target initializes")
	var candidate_1 := restored.persistence.restore_candidate(saved)
	if candidate_1.success:
		restored = candidate_1
	_check(candidate_1.success, "Formal v10 restores exact Spatial snapshot before dependents")
	if not restored.success:
		return
	_equal(restored.world.spatial_world.snapshot(), before_spatial, "infrastructure and capacity window restore exactly")
	_equal(
		JSON.stringify(restored.world.spatial_world.snapshot()).sha256_text(),
		before_spatial_fingerprint,
		"Spatial authoritative fingerprint restores exactly"
	)
	_equal(
		restored.persistence.authoritative_fingerprint(),
		before_world_fingerprint,
		"Formal authoritative fingerprint restores exactly with Spatial"
	)
	var summary := restored.world.spatial_world.capacity_summary(LINK_ID)
	_equal(
		(summary.get("reservations", []) as Array).size(),
		1,
		"current-hour capacity reservation survives exact Formal restore"
	)
	_equal(
		float(restored.world.spatial_world.infrastructure_state(LINK_ID).get("nominal_capacity", -1.0)),
		320.0,
		"nominal capacity survives Formal save/load"
	)
	_equal(
		float(restored.world.spatial_world.infrastructure_state(LINK_ID).get("condition", -1.0)),
		0.75,
		"infrastructure condition survives Formal save/load"
	)
	_equal(
		str(restored.world.spatial_world.infrastructure_state(LINK_ID).get("status", "")),
		"damaged",
		"infrastructure status survives Formal save/load"
	)
	source.simulation_step.advance_minutes(MINUTES_PER_HOUR)
	restored.simulation_step.advance_minutes(MINUTES_PER_HOUR)
	_equal(
		restored.persistence.snapshot(),
		source.persistence.snapshot(),
		"saved continuation equals uninterrupted continuation after Spatial window rollover"
	)
	_equal(
		restored.persistence.authoritative_fingerprint(),
		source.persistence.authoritative_fingerprint(),
		"saved and uninterrupted continuation fingerprints remain exact"
	)


func _test_corrupted_spatial_restore_is_atomic() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "atomic Spatial restore world initializes")
	if not world.success:
		return
	_check(world.world.spatial_world.set_nominal_capacity(LINK_ID, 444.0), "atomic fixture mutates Spatial")
	var before_state := world.persistence.snapshot()
	var before_fingerprint := world.persistence.authoritative_fingerprint()
	var malformed := before_state.duplicate(true)
	var spatial := malformed.get("spatial", {}) as Dictionary
	var infrastructure := spatial.get("infrastructure", []) as Array
	if infrastructure.is_empty():
		_check(false, "atomic fixture has infrastructure")
		return
	(infrastructure[0] as Dictionary)["status"] = "corrupted_status"
	var candidate_2 := world.persistence.restore_candidate(malformed)
	if candidate_2.success:
		world = candidate_2
	_check(
		not candidate_2.success,
		"corrupted Spatial snapshot is rejected by Formal restore"
	)
	_equal(
		world.persistence.snapshot(),
		before_state,
		"failed Spatial restore leaves whole Formal state unchanged"
	)
	_equal(
		world.persistence.authoritative_fingerprint(),
		before_fingerprint,
		"failed Spatial restore leaves whole Formal fingerprint unchanged"
	)


func _test_spatial_fingerprint_boundary() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "Spatial fingerprint world initializes")
	if not world.success:
		return
	var initial_spatial_fingerprint := JSON.stringify(world.world.spatial_world.snapshot()).sha256_text()
	var initial_world_fingerprint := world.persistence.authoritative_fingerprint()
	var detached := world.world.spatial_world.snapshot()
	detached["projection_cache"] = {"camera": "not-authoritative"}
	var detached_infrastructure := detached.get("infrastructure", []) as Array
	if not detached_infrastructure.is_empty():
		(detached_infrastructure[0] as Dictionary)["debug_counter"] = 999
	_equal(
		JSON.stringify(world.world.spatial_world.snapshot()).sha256_text(),
		initial_spatial_fingerprint,
		"detached UI/cache mutation cannot change Spatial authoritative fingerprint"
	)
	_equal(
		world.persistence.authoritative_fingerprint(),
		initial_world_fingerprint,
		"detached UI/cache mutation cannot change Formal authoritative fingerprint"
	)
	_check(
		world.world.spatial_world.set_infrastructure_condition(LINK_ID, 0.5),
		"authoritative Spatial mutation is accepted"
	)
	_check(
		JSON.stringify(world.world.spatial_world.snapshot()).sha256_text() != initial_spatial_fingerprint,
		"authoritative Spatial mutation changes Spatial fingerprint"
	)
	_check(
		world.persistence.authoritative_fingerprint() != initial_world_fingerprint,
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
