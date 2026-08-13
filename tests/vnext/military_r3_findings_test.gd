extends SceneTree

var checks := 0
var failures := 0
var map: VNextMilitaryMapAdapter
var spatial: VNextSpatialWorld
var _state_contexts: Dictionary = {}
var service := VNextMilitaryService.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	spatial = VNextSpatialWorld.create_from_legacy_world_map()
	_check(spatial != null and spatial.is_valid(), "authoritative Spatial world loads")
	map = VNextMilitaryMapAdapter.new()
	_check(map.load_existing_map(spatial), "R3 map loads")
	if map != null and map.errors.is_empty():
		_test_rolling_pipeline()
		_test_capacity_and_source_limits()
		_test_long_latency_high_capacity()
		_test_pipeline_interrupt_restore_partition_determinism()
		_test_strict_restore_matrix()
	print("VNext military R3 findings: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)

func _test_rolling_pipeline() -> void:
	var state := _remote("formation:r3_abundant", "marseille", 2000, _abundant())
	var route := map.find_route("paris", "marseille", [], "country_fra", state.region_controls, false)
	var transit := maxi(1, int(route.get("duration_hours", 1)))
	var max_food_inflight := 0
	var delivered_food := 0.0
	var measured_demand := 0.0
	var horizon := mini(1000, transit * 4 + 48)
	for _hour: int in range(horizon):
		var result := _advance_result(state, state.last_simulated_hour + 1)
		_check(bool(result.get("success", false)), "abundant remote hour advances")
		max_food_inflight = maxi(max_food_inflight, _supply_count(state, "formation:r3_abundant", "food"))
		if state.last_simulated_hour > transit * 2:
			var row: Dictionary = (result.get("supply", {}) as Dictionary).get("formation:r3_abundant", {}) as Dictionary
			delivered_food += float((row.get("delivered", {}) as Dictionary).get("food", 0.0))
			measured_demand += float((row.get("demand", {}) as Dictionary).get("food", 0.0))
	_check(max_food_inflight >= 2, "rolling pipeline has simultaneous same-resource shipments")
	_check(measured_demand > 0.0 and delivered_food / measured_demand > 0.80, "abundant remote steady throughput follows demand after warm-up")
	var formation := state.get_formation("formation:r3_abundant")
	_check(formation != null and formation.formation_status == VNextMilitaryFormation.STATUS_ACTIVE, "remote formation survives warm-up")
	_check(formation.supply_status != "cut" and formation.supply_level >= 0.75, "abundant remote formation leaves chronic cut state")
	_check(state.completed_actions.size() <= VNextMilitaryState.MAX_COMPLETED_ACTIONS and state.battle_results.size() <= VNextMilitaryState.MAX_BATTLE_RESULTS and state.control_history.size() <= VNextMilitaryState.MAX_CONTROL_HISTORY, "long-run histories remain bounded")
	var saw_supply_completion := false
	for record: Dictionary in state.completed_actions:
		if str(record.get("kind", "")) == "supply" and bool(record.get("success", false)):
			saw_supply_completion = true
			var total := float(record.get("cargo_amount_total", -1.0))
			_check(is_equal_approx(total, float(record.get("cargo_delivered", -2.0)) + float(record.get("cargo_lost", -3.0))), "successful supply completion conserves cargo")
			break
	_check(saw_supply_completion, "successful supply settlement leaves bounded completion provenance")

func _test_capacity_and_source_limits() -> void:
	var capacity_state := _remote("formation:r3_capacity", "rouen", 6000, _abundant())
	var rail := map.find_route("paris", "rouen", ["rail"], "country_fra", capacity_state.region_controls, false)
	var link_id := str((rail.get("link_ids", []) as Array)[0])
	var saved_capacity := float(spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))
	_check(spatial.set_nominal_capacity(link_id, 40.0), "R3 Spatial capacity limit applies")
	var max_inflight := 0
	for _hour: int in range(96):
		_check(_advance_one(capacity_state), "capacity-limited pipeline advances")
		max_inflight = maxi(max_inflight, _supply_count(capacity_state, "formation:r3_capacity", "food"))
	_check(max_inflight >= 2, "capacity-limited route still builds multiple-shipment pipeline")
	_check(capacity_state.get_formation("formation:r3_capacity").supply_level < 0.95, "capacity scarcity produces shortage")
	_check(spatial.set_nominal_capacity(link_id, saved_capacity), "R3 Spatial capacity limit restores")

	var source := _abundant()
	source["food"] = 0.0
	var source_state := _remote("formation:r3_source", "rouen", 2000, source)
	for _hour: int in range(120):
		_check(_advance_one(source_state), "source-limited pipeline advances")
	var source_formation := source_state.get_formation("formation:r3_source")
	_check(float(source_formation.supply_fill.get("food", 1.0)) < 0.05, "source scarcity, not transport serialization, limits food")

func _test_long_latency_high_capacity() -> void:
	var state := _remote("formation:r3_latency", "marseille", 1000, _abundant())
	var context: Dictionary = _context_for_state(state)
	var state_map: VNextMilitaryMapAdapter = context.get("map") as VNextMilitaryMapAdapter
	var state_spatial: VNextSpatialWorld = context.get("spatial") as VNextSpatialWorld
	map = state_map
	spatial = state_spatial
	var saved: Dictionary = {}
	for link_id: String in state_map.links.keys():
		var link: Dictionary = state_map.links[link_id] as Dictionary
		var nominal := float(state_spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))
		saved[link_id] = {"movement_hours": int(link.get("movement_hours", 1)), "nominal_capacity": nominal}
		link["movement_hours"] = maxi(2, int(link.get("movement_hours", 1)) * 3)
		_check(state_spatial.set_nominal_capacity(link_id, maxf(1.0, nominal * 30.0)), "R3 high Spatial capacity applies")
	var route := state_map.find_route("paris", "marseille", [], "country_fra", state.region_controls, false)
	var transit := int(route.get("duration_hours", 0))
	var max_food := 0
	var delivered := 0.0
	var demand := 0.0
	var horizon := mini(1400, transit * 3 + 48)
	for _hour: int in range(horizon):
		var result := _advance_result(state, state.last_simulated_hour + 1)
		_check(bool(result.get("success", false)), "long-latency high-capacity hour advances")
		max_food = maxi(max_food, _supply_count(state, "formation:r3_latency", "food"))
		if state.last_simulated_hour > transit * 2:
			var row: Dictionary = (result.get("supply", {}) as Dictionary).get("formation:r3_latency", {}) as Dictionary
			delivered += float((row.get("delivered", {}) as Dictionary).get("food", 0.0))
			demand += float((row.get("demand", {}) as Dictionary).get("food", 0.0))
	_check(transit > 0 and max_food >= 3, "long latency increases in-transit inventory")
	_check(demand > 0.0 and delivered / demand > 0.75, "high capacity preserves steady throughput despite long latency")
	for link_id: String in saved.keys():
		(state_map.links[link_id] as Dictionary)["movement_hours"] = int((saved[link_id] as Dictionary)["movement_hours"])
		_check(state_spatial.set_nominal_capacity(link_id, float((saved[link_id] as Dictionary)["nominal_capacity"])), "R3 high Spatial capacity restores")


func _test_pipeline_interrupt_restore_partition_determinism() -> void:
	var interrupted := _remote("formation:r3_interrupt", "rouen", 2000, _abundant())
	for _hour: int in range(4):
		_check(_advance_one(interrupted), "pipeline warm-up before interruption")
	var shipments := service.get_supply_shipments(interrupted)
	_check(shipments.size() >= 4, "multiple shipments exist before interruption")
	var first: Dictionary = shipments[0]
	var edge := int(first.get("current_edge_index", 0))
	var link_id := str(((first.get("route", {}) as Dictionary).get("link_ids", []) as Array)[edge])
	var tracked: Dictionary = {}
	for shipment: Dictionary in shipments:
		var shipment_edge := int(shipment.get("current_edge_index", -1))
		var shipment_links: Array = (shipment.get("route", {}) as Dictionary).get("link_ids", []) as Array
		if shipment_edge >= 0 and shipment_edge < shipment_links.size() and str(shipment_links[shipment_edge]) == link_id:
			tracked[str(shipment.get("action_id", ""))] = float(shipment.get("cargo_amount_remaining", 0.0))
	_check(not tracked.is_empty(), "interruption fixture tracks current-link cargo")
	var saved_capacity := float(spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))
	_check(spatial.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "R3 authoritative Spatial interruption applies")
	_check(_advance_one(interrupted), "multi-shipment capacity interruption advances")
	var frozen := 0
	for action_id: String in tracked.keys():
		var live := _find_supply_by_id(interrupted, action_id)
		if (
			not live.is_empty()
			and str(live.get("reserved_link_id", "")).is_empty()
			and str(live.get("transport_state", "")) in ["interrupted", "blocked"]
			and is_equal_approx(float(live.get("cargo_amount_remaining", -1.0)), float(tracked[action_id]))
		):
			frozen += 1
	_check(frozen == tracked.size(), "pipeline shipments freeze without duplicate delivery")
	var duplicate_completion := false
	for record: Dictionary in interrupted.completed_actions:
		if tracked.has(str(record.get("action_id", ""))):
			duplicate_completion = true
			break
	_check(not duplicate_completion, "capacity interruption does not settle tracked cargo")
	var interrupted_snapshot := interrupted.snapshot()
	var interruption_restored := VNextMilitaryState.new()
	_check(interruption_restored.restore(interrupted_snapshot, map), "interrupted pipeline snapshot restores while capacity is zero")
	_check(interruption_restored.snapshot() == interrupted_snapshot, "interrupted pipeline restore is exact")
	_check(spatial.set_nominal_capacity(link_id, saved_capacity) and spatial.restore_infrastructure(link_id), "R3 authoritative Spatial interruption recovers")
	_check(_advance_one(interrupted), "pipeline resumes after capacity recovery")
	_check(_advance_one(interruption_restored), "restored pipeline resumes after capacity recovery")
	_check(interrupted.snapshot() == interruption_restored.snapshot(), "interruption snapshot recovery matches continuous state")

	var continuous := _remote("formation:r3_resume", "marseille", 1200, _abundant())
	for _hour: int in range(8):
		_check(_advance_one(continuous), "multi-flight snapshot warm-up")
	_check(_supply_count(continuous, "formation:r3_resume", "food") >= 2, "snapshot contains multiple same-resource shipments")
	var snap := continuous.snapshot()
	var restored := VNextMilitaryState.new()
	_check(restored.restore(snap, map), "multiple in-flight pipeline snapshot restores")
	_check(restored.snapshot() == snap, "restored pipeline snapshot is exact")
	var target := continuous.last_simulated_hour + 120
	_check(bool(_advance_result(continuous, target).get("success", false)), "continuous pipeline continuation advances")
	_check(bool(_advance_result(restored, target).get("success", false)), "restored pipeline continuation advances")
	_check(continuous.snapshot() == restored.snapshot(), "pipeline resume equals uninterrupted continuation")

	var big := _remote("formation:r3_partition", "marseille", 1200, _abundant())
	var sliced := _remote("formation:r3_partition", "marseille", 1200, _abundant())
	_check(bool(_advance_result(big, 160).get("success", false)), "pipeline large advance succeeds")
	for _hour: int in range(160):
		_check(_advance_one(sliced), "pipeline sliced hour succeeds")
	_check(big.snapshot() == sliced.snapshot(), "multi-shipment pipeline large vs sliced time is identical")

	var order_a := _remote("formation:r3_order", "rouen", 1000, _abundant())
	var order_b := _remote("formation:r3_order", "rouen", 1000, _abundant())
	for _hour: int in range(5):
		_check(_advance_one(order_a) and _advance_one(order_b), "determinism warm-up advances")
	var ids: Array[String] = []
	for raw_id: Variant in order_b.active_actions.keys(): ids.append(str(raw_id))
	ids.sort(); ids.reverse()
	var reordered: Dictionary = {}
	for action_id: String in ids: reordered[action_id] = order_b.active_actions[action_id]
	order_b.active_actions = reordered
	_check(_advance_one(order_a) and _advance_one(order_b), "permuted insertion states advance")
	_check(order_a.snapshot() == order_b.snapshot(), "capacity contention is insertion-order deterministic")

func _test_strict_restore_matrix() -> void:
	var state := _remote("formation:r3_strict", "rouen", 1000, _abundant())
	for _hour: int in range(5): _check(_advance_one(state), "strict fixture advances")
	var valid := state.snapshot()
	var first_action: Dictionary = (valid.get("active_actions", []) as Array)[0] as Dictionary
	var action_id := str(first_action.get("action_id", ""))
	var current_link := str(first_action.get("capacity_link_id", ""))
	if current_link.is_empty(): current_link = str(((first_action.get("route", {}) as Dictionary).get("link_ids", []) as Array)[int(first_action.get("current_edge_index", 0))])

	var phantom := valid.duplicate(true)
	for link: Dictionary in map.get_all_links():
		var candidate := str(link.get("id", ""))
		if candidate != current_link:
			(phantom.get("link_capacity_used", {}) as Dictionary)[candidate] = 1.0
			break
	_check(_rejected(phantom), "phantom link capacity is transactionally rejected")

	var wrong_aggregate := valid.duplicate(true)
	if not current_link.is_empty(): (wrong_aggregate.get("link_capacity_used", {}) as Dictionary)[current_link] = 0.0
	_check(_rejected(wrong_aggregate), "unexplained zero capacity aggregate is rejected")

	var chronology := valid.duplicate(true)
	var chronology_action: Dictionary = (chronology.get("active_actions", []) as Array)[0] as Dictionary
	chronology_action["edge_request_hour"] = maxi(1, int(chronology_action.get("edge_started_hour", 0)) + 1)
	chronology_action["edge_started_hour"] = int(chronology_action["edge_request_hour"]) - 1
	_check(_rejected(chronology), "edge start before request is rejected")

	var teleport_state := _new_state()
	_check(bool(_advance_result(teleport_state, 1).get("success", false)), "control teleport fixture advances")
	var teleport := teleport_state.snapshot()
	(teleport.get("region_controls", {}) as Dictionary)["northern_industrial_belt"] = "country_bel"
	_check(_rejected(teleport), "runtime controller change without provenance is rejected")

	var active_reuse := valid.duplicate(true)
	(active_reuse.get("battle_results", []) as Array).append({"action_id": action_id, "outcome":"attacker_win", "target_region_id":"northern_industrial_belt", "controller_country_id":"country_fra", "control_changed":false})
	_check(_rejected(active_reuse), "active action cannot reuse retained battle identity")

	var duplicate_lifecycle := valid.duplicate(true)
	(duplicate_lifecycle.get("battle_results", []) as Array).append({"action_id":"military_action:000400"})
	(duplicate_lifecycle.get("battle_results", []) as Array).append({"action_id":"military_action:000400"})
	duplicate_lifecycle["next_action_sequence"] = 401
	_check(_rejected(duplicate_lifecycle), "duplicate battle lifecycle identity is rejected")

	var battle_high := valid.duplicate(true)
	(battle_high.get("battle_results", []) as Array).append({"action_id":"military_action:000500"})
	battle_high["next_action_sequence"] = 500
	_check(_rejected(battle_high), "next sequence below battle high-water is rejected")

	var control_high := teleport_state.snapshot()
	(control_high.get("region_controls", {}) as Dictionary)["northern_industrial_belt"] = "country_bel"
	(control_high.get("control_history", []) as Array).append({"region_id":"northern_industrial_belt","previous_controller_id":"country_fra","controller_id":"country_bel","control_origin_controller_id":"country_fra","cause":"strategic_attack_victory","effective_hour":1,"context":"battle","source_action_id":"military_action:000500","source_action_kind":"attack","source_formation_id":"formation:provenance","source_target_region_id":"northern_industrial_belt","source_controller_id":"country_bel","source_preparation_end_hour":1})
	control_high["next_action_sequence"] = 500
	_check(_rejected(control_high), "next sequence below control source high-water is rejected")

	var orphan := valid.duplicate(true)
	((orphan.get("active_actions", []) as Array)[0] as Dictionary)["reserved_link_id"] = "missing_link"
	_check(_rejected(orphan), "orphan reservation is rejected")

	var link_mismatch := valid.duplicate(true)
	var mismatch_action: Dictionary = (link_mismatch.get("active_actions", []) as Array)[0] as Dictionary
	for link: Dictionary in map.get_all_links():
		var candidate := str(link.get("id", ""))
		if candidate != current_link:
			mismatch_action["capacity_link_id"] = candidate
			break
	_check(_rejected(link_mismatch), "allocation link mismatch is rejected")

	var current_window := int(valid.get("capacity_window_hour", -1))
	var current_used: Dictionary = valid.get("link_capacity_used", {}) as Dictionary
	var current_allocated_action: Dictionary = {}
	for raw_action: Variant in valid.get("active_actions", []) as Array:
		if not raw_action is Dictionary:
			continue
		var candidate_action := raw_action as Dictionary
		var candidate_link := str(candidate_action.get("capacity_link_id", ""))
		var candidate_used := float(candidate_action.get("capacity_used_this_window", 0.0))
		if (
			candidate_used > 0.0001
			and not candidate_link.is_empty()
			and int(candidate_action.get("capacity_window_hour", -2)) == current_window
			and float(current_used.get(candidate_link, 0.0)) >= candidate_used - 0.0001
		):
			current_allocated_action = candidate_action
			break
	_check(not current_allocated_action.is_empty(), "strict fixture contains a real current-window allocation")
	if not current_allocated_action.is_empty():
		var hour_mismatch := valid.duplicate(true)
		var mismatched_id := str(current_allocated_action.get("action_id", ""))
		var mismatch_snapshot_action: Dictionary = {}
		for raw_action: Variant in hour_mismatch.get("active_actions", []) as Array:
			if raw_action is Dictionary and str((raw_action as Dictionary).get("action_id", "")) == mismatched_id:
				mismatch_snapshot_action = raw_action as Dictionary
				break
		_check(not mismatch_snapshot_action.is_empty(), "current allocation action is found by stable ID")
		if not mismatch_snapshot_action.is_empty():
			mismatch_snapshot_action["capacity_window_hour"] = current_window - 1
			_check(_rejected(hour_mismatch), "real current allocation hour mismatch is rejected")

func _remote(id: String, city: String, personnel: int, supply: Dictionary) -> VNextMilitaryState:
	var state := _new_state()
	_check(service.create_formation(state, map, id, "country_fra", city, personnel, {"equipment_factor":1.0}, 0.8, 0.8, 0.8), "remote formation created")
	_check(service.set_supply_input(state, map, "paris_basin", supply), "remote source configured")
	return state

func _new_state() -> VNextMilitaryState:
	var state_spatial := VNextSpatialWorld.create_from_legacy_world_map()
	_check(state_spatial != null and state_spatial.is_valid(), "R3 fixture Spatial world initializes")
	var state_map := VNextMilitaryMapAdapter.new()
	_check(state_map.load_existing_map(state_spatial), "R3 fixture adapter attaches Spatial world")
	_configure_r4_spatial_capacity_baseline(state_spatial, state_map)
	spatial = state_spatial
	map = state_map
	var state := VNextMilitaryState.new()
	_check(state.initialize(state_map), "R3 military state initializes")
	_state_contexts[state.get_instance_id()] = {"spatial": state_spatial, "map": state_map}
	return state


func _abundant() -> Dictionary:
	return {"food":100000.0,"ammunition":100000.0,"equipment":100000.0,"transport_capacity":100000.0}

func _advance_one(state: VNextMilitaryState) -> bool:
	return bool(_advance_result(state, state.last_simulated_hour + 1).get("success", false))


func _advance_result(state: VNextMilitaryState, target_hour: int) -> Dictionary:
	var context: Dictionary = _context_for_state(state)
	if context.is_empty():
		return {"success": false}
	var state_spatial: VNextSpatialWorld = context.get("spatial") as VNextSpatialWorld
	var state_map: VNextMilitaryMapAdapter = context.get("map") as VNextMilitaryMapAdapter
	if state_spatial.current_hour() < state.last_simulated_hour:
		if not state_spatial.advance_to_hour(state.last_simulated_hour):
			return {"success": false}
	return service.advance_to_hour(state, state_map, target_hour)


func _context_for_state(state: VNextMilitaryState) -> Dictionary:
	var key: int = state.get_instance_id()
	if _state_contexts.has(key):
		return _state_contexts[key] as Dictionary
	var state_spatial := VNextSpatialWorld.create_from_legacy_world_map()
	if state_spatial == null or not state_spatial.is_valid():
		return {}
	if not state_spatial.advance_to_hour(state.last_simulated_hour):
		return {}
	var state_map := VNextMilitaryMapAdapter.new()
	if not state_map.load_existing_map(state_spatial):
		return {}
	var context := {"spatial": state_spatial, "map": state_map}
	_state_contexts[key] = context
	return context


func _supply_count(state: VNextMilitaryState, formation_id: String, resource_id: String) -> int:
	var count := 0
	for shipment: Dictionary in service.get_supply_shipments(state):
		if str(shipment.get("destination_formation_id", "")) == formation_id and str(shipment.get("resource_id", "")) == resource_id:
			count += 1
	return count

func _find_supply_by_id(state: VNextMilitaryState, action_id: String) -> Dictionary:
	for shipment: Dictionary in service.get_supply_shipments(state):
		if str(shipment.get("action_id", "")) == action_id:
			return shipment
	return {}

func _rejected(snapshot: Dictionary) -> bool:
	var sentinel := _new_state()
	_check(service.create_formation(sentinel, map, "formation:sentinel_r3", "country_fra", "paris", 100, {"equipment_factor":1.0}), "sentinel formation created")
	var before := sentinel.snapshot()
	return not sentinel.restore(snapshot, map) and sentinel.snapshot() == before

func _configure_r4_spatial_capacity_baseline(
	state_spatial: VNextSpatialWorld, state_map: VNextMilitaryMapAdapter
) -> void:
	# Preserve the exact pre-PR62 R4 physical-throughput fixture values while
	# routing them through Spatial authority. This is test data, not production
	# Military capacity authority.
	for link: Dictionary in state_map.get_all_links():
		var mode: String = str(link.get("mode", ""))
		var personnel_capacity: float = 0.0
		var reliability: float = 0.0
		match mode:
			"road":
				personnel_capacity = 8000.0
				reliability = 0.82
			"rail":
				personnel_capacity = 24000.0
				reliability = 0.96
			"shipping":
				personnel_capacity = 50000.0
				reliability = 0.78
		var movement_hours: float = maxf(1.0, float(link.get("movement_hours", 1.0)))
		var per_hour: float = personnel_capacity * reliability / movement_hours
		if per_hour > 0.0:
			_check(state_spatial.set_nominal_capacity(str(link.get("id", "")), per_hour), "R4 capacity fixture is owned by Spatial")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
