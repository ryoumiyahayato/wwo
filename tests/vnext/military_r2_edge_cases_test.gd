extends SceneTree

var checks := 0
var failures := 0
var map: VNextMilitaryMapAdapter
var service := VNextMilitaryService.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	map = VNextMilitaryMapAdapter.new()
	_check(map.load_existing_map(), "map loads for R2 edge cases")
	if map != null and map.errors.is_empty():
		_test_supply_control_cut_and_determinism()
		_test_attacker_annihilation()
		_test_restore_adversarial_extensions()
	print("VNext military R2 edge cases: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)

func _test_supply_control_cut_and_determinism() -> void:
	var state := _remote_supply_state("formation:cut_access", "marseille", 5000)
	var shipment := _advance_supply_to_intermediate(state, "formation:cut_access", "food", 300)
	_check(not shipment.is_empty(), "supply reaches intermediate waypoint for control cut")
	if not shipment.is_empty():
		var route: Dictionary = shipment.get("route", {}) as Dictionary
		var edge := int(shipment.get("current_edge_index", -1))
		var city_ids: Array = route.get("city_ids", []) as Array
		var next_city := str(city_ids[edge + 1])
		var next_region := map.get_region_id_for_city(next_city)
		var old_controller := str(state.region_controls.get(next_region, ""))
		state.region_controls[next_region] = "country_bel"
		_check(state.is_valid(map), "future edge control change keeps pending waypoint snapshot valid")
		service.advance_to_hour(state, map, state.last_simulated_hour + 1)
		shipment = _find_supply(state, "formation:cut_access", "food")
		_check(str(shipment.get("transport_state", "")) in ["blocked", "interrupted"], "mid-route controller change blocks supply before next edge")
		var cargo_before := float(shipment.get("cargo_amount_remaining", 0.0))
		state.region_controls[next_region] = old_controller
		service.advance_to_hour(state, map, state.last_simulated_hour + 1)
		shipment = _find_supply(state, "formation:cut_access", "food")
		_check(str(shipment.get("transport_state", "")) in ["waiting_capacity", "moving"], "restored controller access resumes supply")
		_check(is_equal_approx(cargo_before, float(shipment.get("cargo_amount_remaining", -1.0))), "control interruption preserves cargo accounting")

	var replay_a := _two_supply_state()
	var replay_b := _two_supply_state()
	service.advance_to_hour(replay_a, map, 72)
	service.advance_to_hour(replay_b, map, 72)
	_check(replay_a.snapshot() == replay_b.snapshot(), "multiple supply shipments replay deterministically")
	var supply_count := 0
	for action: Dictionary in service.get_supply_shipments(replay_a):
		if str(action.get("kind", "")) == "supply":
			supply_count += 1
	_check(supply_count >= 2, "multiple supply shipments can coexist and contend")

func _test_attacker_annihilation() -> void:
	var old_loss := float(map.battle_rules.get("defender_win_loss_rate", 0.18))
	map.battle_rules["defender_win_loss_rate"] = 1.0
	var state := _battle_state(1, 50000)
	var order := service.attack(state, map, "formation:attacker", "lille", 0)
	var attack_id := str(order.get("action_id", ""))
	_finish(state, attack_id, 700)
	var attacker := state.get_formation("formation:attacker")
	_check(attacker.personnel == 0 and attacker.formation_status == VNextMilitaryFormation.STATUS_DESTROYED, "combat can annihilate attacking formation")
	_check(attacker.action_state == VNextMilitaryFormation.ACTION_IDLE, "annihilated attacker is terminal idle")
	_check(not state.active_actions.has(attack_id), "annihilated attacker leaves no stale attack/preparation action")
	_check(not _queue_contains(state, attack_id), "annihilated attacker leaves no stale capacity reservation")
	_check(state.is_valid(map), "attacker annihilation returns an immediately valid state")
	var snap := state.snapshot()
	var restored := VNextMilitaryState.new()
	_check(restored.restore(snap, map), "attacker annihilation snapshot restores")
	_check(bool(service.advance_to_hour(restored, map, restored.last_simulated_hour + 1).get("success", false)), "restored attacker-annihilation state advances")
	_check(not bool(service.move(restored, map, "formation:attacker", "rouen", restored.last_simulated_hour).get("success", false)), "destroyed attacker rejects normal command")
	map.battle_rules["defender_win_loss_rate"] = old_loss

func _test_restore_adversarial_extensions() -> void:
	var source := _new_state()
	_add(source, "formation:restore_edge", "paris", 5000, 1.0)
	service.move(source, map, "formation:restore_edge", "rouen", 0)
	service.advance_to_hour(source, map, 1)
	var valid := source.snapshot()

	var mismatch := valid.duplicate(true)
	var formation: Dictionary = (mismatch.get("formations", []) as Array)[0] as Dictionary
	formation["action_state"] = VNextMilitaryFormation.ACTION_IDLE
	_check(_transactionally_rejected(mismatch), "active action to idle formation mismatch rejects transactionally")

	var reverse := valid.duplicate(true)
	(reverse.get("active_actions", []) as Array).clear()
	reverse["link_queues"] = {}
	reverse["link_capacity_used"] = {}
	_check(_transactionally_rejected(reverse), "non-idle formation without active action rejects transactionally")

	var discontinuous := valid.duplicate(true)
	var dis_action: Dictionary = (discontinuous.get("active_actions", []) as Array)[0] as Dictionary
	(dis_action.get("route", {}) as Dictionary)["city_ids"] = ["paris", "berlin"]
	_check(_transactionally_rejected(discontinuous), "discontinuous route rejects transactionally")

	var zero_eta := valid.duplicate(true)
	var eta_action: Dictionary = (zero_eta.get("active_actions", []) as Array)[0] as Dictionary
	eta_action["eta_hour"] = eta_action["start_hour"]
	_check(_transactionally_rejected(zero_eta), "zero overall action duration rejects transactionally")

	var negative_route := valid.duplicate(true)
	var neg_action: Dictionary = (negative_route.get("active_actions", []) as Array)[0] as Dictionary
	(neg_action.get("route", {}) as Dictionary)["duration_hours"] = -1
	_check(_transactionally_rejected(negative_route), "negative route duration rejects transactionally")

	var inaccessible := valid.duplicate(true)
	var access_action: Dictionary = (inaccessible.get("active_actions", []) as Array)[0] as Dictionary
	var access_route: Dictionary = access_action.get("route", {}) as Dictionary
	var edge := int(access_action.get("current_edge_index", 0))
	var next_city := str((access_route.get("city_ids", []) as Array)[edge + 1])
	var next_region := map.get_region_id_for_city(next_city)
	(inaccessible.get("region_controls", {}) as Dictionary)[next_region] = "country_bel"
	_check(_transactionally_rejected(inaccessible), "moving current edge with incompatible controller rejects transactionally")

	var wrong_request_hour := valid.duplicate(true)
	var hour_action: Dictionary = (wrong_request_hour.get("active_actions", []) as Array)[0] as Dictionary
	hour_action["edge_request_hour"] = int(wrong_request_hour.get("last_simulated_hour", 0)) + 1
	_check(_transactionally_rejected(wrong_request_hour), "future current-edge request hour rejects transactionally")

func _remote_supply_state(id: String, city: String, personnel: int) -> VNextMilitaryState:
	var state := _new_state()
	_add(state, id, city, personnel, 1.0)
	service.set_supply_input(state, map, "paris_basin", _abundant_supply())
	return state

func _two_supply_state() -> VNextMilitaryState:
	var state := _new_state()
	_add(state, "formation:supply_a", "rouen", 5000, 1.0)
	_add(state, "formation:supply_b", "rouen", 5000, 1.0)
	service.set_supply_input(state, map, "paris_basin", _abundant_supply())
	return state

func _abundant_supply() -> Dictionary:
	return {"food": 100000.0, "ammunition": 100000.0, "equipment": 100000.0, "transport_capacity": 100000.0}

func _find_supply(state: VNextMilitaryState, formation_id: String, resource: String) -> Dictionary:
	for shipment: Dictionary in service.get_supply_shipments(state):
		if str(shipment.get("destination_formation_id", "")) == formation_id and str(shipment.get("resource_id", "")) == resource:
			return shipment
	return {}

func _advance_supply_to_intermediate(state: VNextMilitaryState, formation_id: String, resource: String, max_hours: int) -> Dictionary:
	var deadline := state.last_simulated_hour + max_hours
	while state.last_simulated_hour < deadline:
		if not bool(service.advance_to_hour(state, map, state.last_simulated_hour + 1).get("success", false)):
			return {}
		var shipment := _find_supply(state, formation_id, resource)
		if shipment.is_empty():
			return {}
		var route: Dictionary = shipment.get("route", {}) as Dictionary
		var edge := int(shipment.get("current_edge_index", -1))
		if edge > 0 and edge < (route.get("link_ids", []) as Array).size():
			return shipment
	return {}

func _battle_state(attacker_personnel: int, defender_personnel: int) -> VNextMilitaryState:
	var state := _new_state()
	service.setup_region_controller(state, map, "northern_industrial_belt", "country_bel", "battle fixture")
	_add(state, "formation:attacker", "paris", attacker_personnel, 1.0, "country_fra", 0.9, 0.9, 0.9)
	_add(state, "formation:defender", "lille", defender_personnel, 1.0, "country_bel", 0.8, 0.8, 0.8)
	service.defend(state, map, "formation:defender", 0, 500)
	return state

func _finish(state: VNextMilitaryState, action_id: String, max_hours: int) -> void:
	var deadline := state.last_simulated_hour + max_hours
	while state.active_actions.has(action_id) and state.last_simulated_hour < deadline:
		if not bool(service.advance_to_hour(state, map, state.last_simulated_hour + 1).get("success", false)):
			break
	_check(not state.active_actions.has(action_id), "edge-case action completes in bounded horizon")

func _transactionally_rejected(snapshot: Dictionary) -> bool:
	var state := _new_state()
	_add(state, "formation:sentinel_r2", "paris", 1000, 1.0)
	var before := state.snapshot()
	return not state.restore(snapshot, map) and state.snapshot() == before

func _queue_contains(state: VNextMilitaryState, request_id: String) -> bool:
	for raw_queue: Variant in state.link_queues.values():
		if raw_queue is Array and (raw_queue as Array).has(request_id):
			return true
	return false

func _new_state() -> VNextMilitaryState:
	var state := VNextMilitaryState.new()
	_check(state.initialize(map), "military state initializes for R2 edge case")
	return state

func _add(state: VNextMilitaryState, id: String, city: String, personnel: int, equipment: float, country: String = "country_fra", training: float = 0.8, morale: float = 0.8, organization: float = 0.8) -> bool:
	return service.create_formation(state, map, id, country, city, personnel, {"equipment_factor": equipment}, training, morale, organization)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)
