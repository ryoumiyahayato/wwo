extends SceneTree

var checks := 0
var failures := 0
var service := VNextMilitaryService.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_two_phase_movement_contention()
	_test_supply_shared_spatial_capacity()
	_test_interruption_history_recovery_snapshot()
	_test_corrupt_spatial_reference_rejected()
	_test_large_vs_hourly()
	_test_authority_boundary_source()
	print("VNext Military/Spatial capacity integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)

func _fixture() -> Dictionary:
	var spatial := VNextSpatialWorld.create_from_legacy_world_map()
	var map := VNextMilitaryMapAdapter.new()
	_check(spatial != null and spatial.is_valid(), "fixture Spatial world loads")
	_check(map.load_existing_map(spatial), "fixture Military adapter consumes Spatial")
	var state := VNextMilitaryState.new()
	_check(state.initialize(map), "fixture Military state initializes")
	return {"spatial": spatial, "map": map, "state": state}

func _add(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, id: String, city: String, personnel: int) -> void:
	_check(service.create_formation(
		state, map, id, "country_fra", city, personnel,
		{"equipment_factor": 0.0}, 0.9, 0.9, 0.9,
		{"food": 2400.0, "ammunition": 240.0, "equipment": 48.0, "transport_capacity": 24.0}
	), "formation created: %s" % id)

func _rail_link(map: VNextMilitaryMapAdapter, state: VNextMilitaryState) -> String:
	var route := map.find_route("paris", "rouen", ["rail"], "country_fra", state.region_controls, false)
	var ids: Array = route.get("link_ids", []) as Array
	return "" if ids.is_empty() else str(ids[0])

func _test_two_phase_movement_contention() -> void:
	var f := _fixture()
	var spatial: VNextSpatialWorld = f["spatial"]
	var map: VNextMilitaryMapAdapter = f["map"]
	var state: VNextMilitaryState = f["state"]
	var link_id := _rail_link(map, state)
	_check(not link_id.is_empty(), "contention rail link exists")
	_check(spatial.set_nominal_capacity(link_id, 100.0), "contention capacity set in Spatial")
	_add(state, map, "formation:spatial_a", "paris", 1000)
	_add(state, map, "formation:spatial_b", "paris", 1000)
	var first := service.move(state, map, "formation:spatial_a", "rouen", 0)
	var second := service.move(state, map, "formation:spatial_b", "rouen", 0)
	_check(bool(first.get("success", false)) and bool(second.get("success", false)), "two movement demands accepted by Military")
	_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "two-phase contention hour advances")
	var first_action: Dictionary = state.active_actions.get(str(first.get("action_id", "")), {}) as Dictionary
	var second_action: Dictionary = state.active_actions.get(str(second.get("action_id", "")), {}) as Dictionary
	var a := float(first_action.get("capacity_used_this_window", 0.0))
	var b := float(second_action.get("capacity_used_this_window", 0.0))
	_check(a > b and a + b <= 100.0001, "final canonical allocation, not provisional reverse submission, drives progress")
	_check(is_equal_approx(float(state.link_capacity_used.get(link_id, 0.0)), a + b), "Military ledger is derived attribution")
	_check(spatial.current_hour() == 1 and spatial.used_capacity(link_id) == 0.0, "Spatial rolled physical window and owns current usage")

func _test_supply_shared_spatial_capacity() -> void:
	var f := _fixture()
	var spatial: VNextSpatialWorld = f["spatial"]
	var map: VNextMilitaryMapAdapter = f["map"]
	var state: VNextMilitaryState = f["state"]
	var link_id := _rail_link(map, state)
	_check(spatial.set_nominal_capacity(link_id, 120.0), "shared supply capacity set in Spatial")
	_add(state, map, "formation:spatial_mover", "paris", 800)
	_add(state, map, "formation:spatial_supply", "rouen", 800)
	_check(service.set_supply_input(state, map, "paris_basin", {"food": 240000.0, "ammunition": 24000.0, "equipment": 4800.0, "transport_capacity": 2400.0}), "remote supply source configured")
	var move := service.move(state, map, "formation:spatial_mover", "rouen", 0)
	_check(bool(move.get("success", false)), "movement demand issued")
	_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "movement plus supply Spatial hour advances")
	var queue: Array = state.link_queues.get(link_id, []) as Array
	var saw_supply := false
	for action_id: Variant in queue:
		var action: Dictionary = state.active_actions.get(str(action_id), {}) as Dictionary
		if str(action.get("kind", "")) == "supply":
			saw_supply = true
	_check(queue.has(move.get("action_id", "")) and saw_supply, "movement and rolling supply submit into one Spatial-backed window")
	_check(float(state.link_capacity_used.get(link_id, 0.0)) <= 120.0001, "movement plus supply attribution is bounded by one Spatial capacity")

func _test_interruption_history_recovery_snapshot() -> void:
	var f := _fixture()
	var spatial: VNextSpatialWorld = f["spatial"]
	var map: VNextMilitaryMapAdapter = f["map"]
	var state: VNextMilitaryState = f["state"]
	var link_id := _rail_link(map, state)
	_check(spatial.set_nominal_capacity(link_id, 150.0), "interruption capacity configured")
	_add(state, map, "formation:spatial_interrupt", "paris", 1200)
	var move := service.move(state, map, "formation:spatial_interrupt", "rouen", 0)
	_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "warm movement hour advances")
	var action_id := str(move.get("action_id", ""))
	var before: Dictionary = state.active_actions[action_id] as Dictionary
	var historical_used := float(before.get("capacity_used_this_window", 0.0))
	var remaining_before := float(before.get("edge_load_remaining", 0.0))
	_check(historical_used > 0.0, "warm hour leaves historical Military attribution")
	_check(spatial.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "Spatial physical interruption applies")
	_check(VNextMilitaryStateInvariants.validate(state, map, spatial), "closed historical attribution survives later Spatial capacity change")
	_check(bool(service.advance_to_hour(state, map, 2).get("success", false)), "zero-capacity next hour advances normally")
	var interrupted: Dictionary = state.active_actions[action_id] as Dictionary
	_check(str(interrupted.get("transport_state", "")) == "interrupted", "zero Spatial capacity interrupts Military action")
	_check(is_equal_approx(float(interrupted.get("edge_load_remaining", -1.0)), remaining_before), "zero Spatial capacity makes no movement progress")
	_check(str(interrupted.get("spatial_request_id", "")).is_empty(), "closed/interrupted action retains no stale Spatial reservation")

	var military_snapshot := state.snapshot()
	var spatial_snapshot := spatial.snapshot()
	var restored_spatial := VNextSpatialWorld.create_from_legacy_world_map()
	_check(restored_spatial.restore(spatial_snapshot), "interrupted Spatial snapshot restores")
	var restored_map := VNextMilitaryMapAdapter.new()
	_check(restored_map.load_existing_map(restored_spatial), "restored Military adapter attaches restored Spatial")
	var restored_state := VNextMilitaryState.new()
	_check(restored_state.restore(military_snapshot, restored_map, restored_spatial), "interrupted Military snapshot restores transactionally")
	_check(spatial.restore_infrastructure(link_id) and restored_spatial.restore_infrastructure(link_id), "both Spatial worlds recover capacity")
	_check(bool(service.advance_to_hour(state, map, 3).get("success", false)), "continuous action resumes after recovery")
	_check(bool(service.advance_to_hour(restored_state, restored_map, 3).get("success", false)), "restored action resumes after recovery")
	_check(state.snapshot() == restored_state.snapshot(), "interrupted snapshot continuation is deterministic")
	_check(spatial.snapshot() == restored_spatial.snapshot(), "Spatial continuation is deterministic")

func _test_corrupt_spatial_reference_rejected() -> void:
	var f := _fixture()
	var spatial: VNextSpatialWorld = f["spatial"]
	var map: VNextMilitaryMapAdapter = f["map"]
	var state: VNextMilitaryState = f["state"]
	_add(state, map, "formation:spatial_corrupt", "paris", 800)
	var move := service.move(state, map, "formation:spatial_corrupt", "rouen", 0)
	_check(bool(move.get("success", false)) and bool(service.advance_to_hour(state, map, 1).get("success", false)), "corruption fixture advances")
	var corrupted := state.snapshot().duplicate(true)
	var actions: Array = corrupted.get("active_actions", []) as Array
	if not actions.is_empty():
		(actions[0] as Dictionary)["spatial_request_id"] = "not-a-real-spatial-request"
	var target := VNextMilitaryState.new()
	_check(not target.restore(corrupted, map, spatial), "stale/current Spatial reservation reference is rejected")

func _test_large_vs_hourly() -> void:
	var big := _fixture()
	var sliced := _fixture()
	var big_state: VNextMilitaryState = big["state"]
	var sliced_state: VNextMilitaryState = sliced["state"]
	_add(big_state, big["map"], "formation:spatial_partition", "paris", 600)
	_add(sliced_state, sliced["map"], "formation:spatial_partition", "paris", 600)
	_check(bool(service.move(big_state, big["map"], "formation:spatial_partition", "marseille", 0).get("success", false)), "large partition move issued")
	_check(bool(service.move(sliced_state, sliced["map"], "formation:spatial_partition", "marseille", 0).get("success", false)), "sliced partition move issued")
	_check(bool(service.advance_to_hour(big_state, big["map"], 48).get("success", false)), "large Spatial/Military advance succeeds")
	var sliced_ok := true
	for hour: int in range(1, 49):
		if not bool(service.advance_to_hour(sliced_state, sliced["map"], hour).get("success", false)):
			sliced_ok = false
			break
	_check(sliced_ok, "hourly Spatial/Military advance succeeds")
	_check(big_state.snapshot() == sliced_state.snapshot(), "large versus hourly Military state is identical")
	_check((big["spatial"] as VNextSpatialWorld).snapshot() == (sliced["spatial"] as VNextSpatialWorld).snapshot(), "large versus hourly Spatial state is identical")

func _test_authority_boundary_source() -> void:
	var adapter_source := FileAccess.get_file_as_string("res://scripts/vnext/map/military_map_adapter.gd")
	var service_source := FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	var overlay := FileAccess.get_file_as_string("res://data/world_map/strategic_military_overlay.json")
	_check(not overlay.contains("capacity_personnel") and not overlay.contains("supply_capacity_per_day") and not overlay.contains("\\\"reliability\\\""), "Military overlay no longer defines physical capacity")
	_check(adapter_source.contains("spatial_world.infrastructure_state") and service_source.contains("spatial.request_capacity_batch") and service_source.contains("spatial.reservation_results_batch"), "Military consumes Spatial physical authority")
	_check(not service_source.contains("var budgets: Dictionary"), "Military-local physical budget removed")
	_check(service_source.contains("_cancel_spatial_requests_for_formation") and service_source.contains("cancel_capacity_request"), "annihilation cleanup releases current Spatial requests")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: %s" % label)
