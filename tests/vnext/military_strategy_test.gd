extends SceneTree

var checks := 0
var failures := 0
var map: VNextMilitaryMapAdapter
var service := VNextMilitaryService.new()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	map = VNextMilitaryMapAdapter.new()
	_check(map.load_existing_map(), "map adapter loads existing world map")
	if map != null and map.errors.is_empty():
		_test_shared_capacity_and_map()
		_test_supply_chronology_and_resume()
		_test_supply_completion_and_interruptions()
		_test_formation_movement_partition()
		_test_combat_position_and_defender_annihilation()
		_test_attacker_annihilation()
		_test_strict_restore_extensions()
		_test_control_boundary()
		_test_restore_readiness_concentrate_scope()
	print("VNext military strategic system: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)

func _test_shared_capacity_and_map() -> void:
	_check(map.get_city_ids().size() == 32, "reuses 32 existing cities")
	_check(map.get_all_links().size() == 15, "reuses existing road rail shipping links")
	var road := map.find_route("paris", "rouen", ["road"])
	var rail := map.find_route("paris", "rouen", ["rail"])
	var sea := map.find_route("paris", "london")
	_check(bool(road.get("reachable", false)) and bool(rail.get("reachable", false)), "road and rail are reachable")
	_check((sea.get("mode_sequence", []) as Array).has("shipping"), "shipping is reused")
	_check(int(rail.get("duration_hours", 0)) < int(road.get("duration_hours", 0)), "rail is faster than road")
	var link_id := str((rail.get("link_ids", []) as Array)[0])
	var original_capacity := int((map.links[link_id] as Dictionary).get("capacity_personnel", 0))
	(map.links[link_id] as Dictionary)["capacity_personnel"] = 0
	_check(map.get_link_transport_capacity_per_hour(link_id) == 0.0, "zero capacity stays impassable")
	_check(not bool(map.find_route("paris", "rouen", ["rail"]).get("reachable", false)), "zero-capacity route is unreachable")
	(map.links[link_id] as Dictionary)["capacity_personnel"] = original_capacity

	var state := _new_state()
	for id: String in ["formation:a", "formation:b", "formation:c"]:
		_add(state, id, "paris", 24000, 1.0)
	var a := service.move(state, map, "formation:a", "rouen", 0)
	var b := service.move(state, map, "formation:b", "rouen", 0)
	var c := service.move(state, map, "formation:c", "rouen", 0)
	_check(bool(a.get("success", false)) and bool(b.get("success", false)) and bool(c.get("success", false)), "three formations enter one contention window")
	_check(_advance(state, 1), "shared contention advances")
	var view := service.get_link_capacity_view(state, map, link_id)
	var queue: Array = view.get("queue", []) as Array
	_check(queue.size() >= 3, "three formations share one link queue")
	_check(str(queue[0]) == str(a.get("action_id", "")) and str(queue[1]) == str(b.get("action_id", "")) and str(queue[2]) == str(c.get("action_id", "")), "same-hour contention order is deterministic")
	_check(float(view.get("used_capacity", 0.0)) <= float(view.get("capacity_per_hour", 0.0)) + 0.001, "link use never exceeds authoritative capacity")
	var source := FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	_check(source.contains("equipment_load") and source.contains("CARGO_LOAD_WEIGHTS"), "personnel equipment and supply share transport load model")

func _test_supply_chronology_and_resume() -> void:
	var state := _remote_supply_state("formation:supply", "marseille", 5000)
	_check(_advance(state, 1), "remote supply first hour advances")
	var food := _find_supply(state, "formation:supply", "food")
	_check(not food.is_empty(), "remote cargo persists in active transport state")
	_check(VNextStableId.kind_of(str(food.get("action_id", ""))) == "military_action", "supply uses shared military action ID contract")
	var route: Dictionary = food.get("route", {}) as Dictionary
	var links: Array = route.get("link_ids", []) as Array
	_check(links.size() >= 2, "supply uses multi-edge route")
	_check(str(food.get("transport_state", "")) != "arrived", "multi-edge cargo does not arrive in one hour")
	_check(int(food.get("current_edge_index", -1)) == 0, "cargo starts on first edge")
	_check(str(food.get("current_city_id", "")) == str((route.get("city_ids", []) as Array)[0]), "cargo has authoritative current waypoint")
	_check(int(food.get("eta_hour", 0)) - int(food.get("start_hour", 0)) >= int(route.get("duration_hours", 0)), "route duration constrains supply ETA")
	_check(is_equal_approx(float(food.get("cargo_amount_total", 0.0)), float(food.get("cargo_amount_remaining", -1.0))), "in-transit cargo amount is conserved")

	var intermediate := _advance_supply_to_intermediate(state, "formation:supply", "food", 200)
	_check(not intermediate.is_empty(), "cargo reaches intermediate waypoint chronologically")
	if not intermediate.is_empty():
		var edge := int(intermediate.get("current_edge_index", -1))
		var cities: Array = (intermediate.get("route", {}) as Dictionary).get("city_ids", []) as Array
		_check(edge > 0 and str(intermediate.get("current_city_id", "")) == str(cities[edge]), "intermediate waypoint matches current edge")

	var snap := state.snapshot()
	var resumed := VNextMilitaryState.new()
	_check(resumed.restore(snap, map), "mid-route cargo snapshot restores")
	_check(resumed.snapshot() == snap, "mid-route cargo restore is exact")
	var target_hour := state.last_simulated_hour + 96
	_check(_advance(state, target_hour), "continuous cargo simulation advances")
	_check(_advance(resumed, target_hour), "restored cargo simulation advances")
	_check(state.snapshot() == resumed.snapshot(), "continuous and restored cargo simulation remain identical")

	var shared := _new_state()
	_add(shared, "formation:mover", "paris", 12000, 1.0)
	_add(shared, "formation:target", "rouen", 6000, 1.0)
	service.set_supply_input(shared, map, "paris_basin", _abundant_supply())
	var move := service.move(shared, map, "formation:mover", "rouen", 0)
	var shared_link := str(((move.get("route", {}) as Dictionary).get("link_ids", []) as Array)[0])
	_check(_advance(shared, 1), "movement and supply contention advances")
	var shared_view := service.get_link_capacity_view(shared, map, shared_link)
	var shared_queue: Array = shared_view.get("queue", []) as Array
	var saw_supply := false
	for request_id: Variant in shared_queue:
		if request_id != move.get("action_id", ""):
			saw_supply = true
	_check(shared_queue.has(move.get("action_id", "")) and saw_supply, "movement and supply use same current-link queue")
	_check(float(shared_view.get("used_capacity", 0.0)) <= float(shared_view.get("capacity_per_hour", 0.0)) + 0.001, "movement plus supply stays inside one budget")

	var replay_a := _two_supply_state()
	var replay_b := _two_supply_state()
	_check(_advance(replay_a, 72) and _advance(replay_b, 72), "two-shipment replay states advance")
	_check(replay_a.snapshot() == replay_b.snapshot(), "multiple supply shipments replay deterministically")
	_check(service.get_supply_shipments(replay_a).size() >= 2, "multiple supply shipments coexist and contend")

	var big := _remote_supply_state("formation:supply_partition", "marseille", 4500)
	var sliced := _remote_supply_state("formation:supply_partition", "marseille", 4500)
	_check(_advance(big, 120), "single supply 120h advance succeeds")
	var sliced_ok := true
	for hour: int in [24, 48, 72, 96, 120]:
		if not _advance(sliced, hour):
			sliced_ok = false
			break
	_check(sliced_ok, "sliced supply advancement succeeds")
	_check(big.snapshot() == sliced.snapshot(), "supply large jump equals sliced advancement")

func _test_supply_completion_and_interruptions() -> void:
	var completion := _remote_supply_state("formation:arrival", "marseille", 4000)
	_check(_advance(completion, 1), "arrival fixture starts")
	var shipment := _find_supply(completion, "formation:arrival", "food")
	var original_total := float(shipment.get("cargo_amount_total", 0.0))
	var arrived := false
	var arrival_hour := -1
	for _i: int in range(400):
		shipment = _find_supply(completion, "formation:arrival", "food")
		if shipment.is_empty():
			break
		if str(shipment.get("transport_state", "")) == "arrived":
			arrived = true
			arrival_hour = completion.last_simulated_hour
			break
		if not _advance(completion, completion.last_simulated_hour + 1):
			break
	_check(arrived, "cargo reaches arrived state only after final edge")
	if arrived:
		var arrival_route: Dictionary = shipment.get("route", {}) as Dictionary
		_check(int(shipment.get("current_edge_index", -1)) == (arrival_route.get("link_ids", []) as Array).size(), "arrived cargo completed every route edge")
		_check(str(shipment.get("current_city_id", "")) == str(shipment.get("destination_city_id", "")), "arrived cargo is at destination waypoint")
		_check(is_equal_approx(float(shipment.get("cargo_amount_remaining", -1.0)), original_total), "arrival itself neither duplicates nor loses cargo")
		_check(arrival_hour >= int(arrival_route.get("duration_hours", 0)), "arrival cannot precede route duration")
		var settled_action_id := str(shipment.get("action_id", ""))
		var settlement := service.advance_to_hour(completion, map, completion.last_simulated_hour + 1)
		_check(bool(settlement.get("success", false)), "arrived cargo settles on following supply hour")
		var delivered := (((settlement.get("supply", {}) as Dictionary).get("formation:arrival", {}) as Dictionary).get("delivered", {}) as Dictionary)
		_check(float(delivered.get("food", 0.0)) > 0.0, "only arrived cargo contributes delivered supply")
		_check(not completion.active_actions.has(settled_action_id), "fully delivered shipment is removed exactly once")

	var low := _remote_supply_state("formation:low_capacity", "rouen", 6000)
	var rail_route := map.find_route("paris", "rouen", ["rail"])
	var rail_link := str((rail_route.get("link_ids", []) as Array)[0])
	var original_capacity := int((map.links[rail_link] as Dictionary).get("capacity_personnel", 0))
	(map.links[rail_link] as Dictionary)["capacity_personnel"] = 10
	_check(_advance(low, 1), "small-capacity supply hour advances")
	var low_food := _find_supply(low, "formation:low_capacity", "food")
	_check(not low_food.is_empty() and float(low_food.get("edge_load_remaining", 0.0)) > 0.0, "small positive capacity creates finite multi-hour supply waves")
	(map.links[rail_link] as Dictionary)["capacity_personnel"] = original_capacity

	var zero_cut := _remote_supply_state("formation:zero_cut", "marseille", 5000)
	var zero_shipment := _advance_supply_to_intermediate(zero_cut, "formation:zero_cut", "food", 240)
	_check(not zero_shipment.is_empty(), "zero-capacity cut fixture reaches intermediate waypoint")
	if not zero_shipment.is_empty():
		var zero_route: Dictionary = zero_shipment.get("route", {}) as Dictionary
		var zero_edge := int(zero_shipment.get("current_edge_index", 0))
		var zero_link := str((zero_route.get("link_ids", []) as Array)[zero_edge])
		var saved_capacity := int((map.links[zero_link] as Dictionary).get("capacity_personnel", 0))
		var cargo_before := float(zero_shipment.get("cargo_amount_remaining", 0.0))
		(map.links[zero_link] as Dictionary)["capacity_personnel"] = 0
		_check(_advance(zero_cut, zero_cut.last_simulated_hour + 1), "zero-capacity interruption hour advances")
		zero_shipment = _find_supply(zero_cut, "formation:zero_cut", "food")
		_check(str(zero_shipment.get("transport_state", "")) == "interrupted", "mid-route zero capacity interrupts cargo")
		(map.links[zero_link] as Dictionary)["capacity_personnel"] = saved_capacity
		_check(_advance(zero_cut, zero_cut.last_simulated_hour + 1), "capacity recovery hour advances")
		zero_shipment = _find_supply(zero_cut, "formation:zero_cut", "food")
		_check(str(zero_shipment.get("transport_state", "")) in ["waiting_capacity", "moving"], "capacity recovery resumes cargo")
		_check(is_equal_approx(cargo_before, float(zero_shipment.get("cargo_amount_remaining", -1.0))), "capacity interruption preserves cargo")

	var control_cut := _remote_supply_state("formation:control_cut", "marseille", 5000)
	var control_shipment := _advance_supply_to_intermediate(control_cut, "formation:control_cut", "food", 240)
	_check(not control_shipment.is_empty(), "controller-cut fixture reaches intermediate waypoint")
	if not control_shipment.is_empty():
		var control_route: Dictionary = control_shipment.get("route", {}) as Dictionary
		var control_edge := int(control_shipment.get("current_edge_index", -1))
		var control_cities: Array = control_route.get("city_ids", []) as Array
		var next_city := str(control_cities[control_edge + 1])
		var next_region := map.get_region_id_for_city(next_city)
		var previous_controller := str(control_cut.region_controls.get(next_region, ""))
		var preserved_cargo := float(control_shipment.get("cargo_amount_remaining", 0.0))
		control_cut.region_controls[next_region] = "country_bel"
		_check(control_cut.is_valid(map), "future edge controller change preserves pending state validity")
		_check(_advance(control_cut, control_cut.last_simulated_hour + 1), "controller cut hour advances")
		control_shipment = _find_supply(control_cut, "formation:control_cut", "food")
		_check(str(control_shipment.get("transport_state", "")) in ["blocked", "interrupted"], "mid-route controller change blocks cargo")
		control_cut.region_controls[next_region] = previous_controller
		_check(_advance(control_cut, control_cut.last_simulated_hour + 1), "controller recovery hour advances")
		control_shipment = _find_supply(control_cut, "formation:control_cut", "food")
		_check(str(control_shipment.get("transport_state", "")) in ["waiting_capacity", "moving"], "controller access recovery resumes cargo")
		_check(is_equal_approx(preserved_cargo, float(control_shipment.get("cargo_amount_remaining", -1.0))), "controller interruption preserves cargo")

func _test_formation_movement_partition() -> void:
	var state := _new_state()
	_add(state, "formation:route", "paris", 8000, 1.0)
	var result := service.move(state, map, "formation:route", "marseille", 0)
	var action_id := str(result.get("action_id", ""))
	var intermediate_found := false
	for _i: int in range(240):
		if not _advance(state, state.last_simulated_hour + 1):
			break
		if state.active_actions.has(action_id) and state.get_formation("formation:route").current_city_id != "paris":
			intermediate_found = true
			break
	_check(intermediate_found, "formation exposes intermediate strategic waypoint")

	var big := _slicing_state()
	var sliced := _slicing_state()
	_check(_advance(big, 240), "single 240h movement advance succeeds")
	var sliced_ok := true
	for hour: int in [24,48,72,96,120,144,168,192,216,240]:
		if not _advance(sliced, hour):
			sliced_ok = false
			break
	_check(sliced_ok, "ten 24h movement advances succeed")
	_check(big.snapshot() == sliced.snapshot(), "240h once equals 10x24h")

func _test_combat_position_and_defender_annihilation() -> void:
	var win := _battle_state(50000, 1500)
	var win_order := service.attack(win, map, "formation:attacker", "lille", 0)
	_finish(win, str(win_order.get("action_id", "")), 500)
	_check(not win.battle_results.is_empty(), "winning battle resolves")
	if not win.battle_results.is_empty():
		var battle: Dictionary = win.battle_results.back() as Dictionary
		_check(battle.get("outcome", "") == "attacker_win", "extreme advantage produces attacker win")
		_check(win.get_formation("formation:attacker").current_city_id == "lille", "victory enters target")
		_check(win.region_controls.get("northern_industrial_belt", "") == "country_fra", "victory changes target control")
		var control: Dictionary = win.control_history.back() as Dictionary
		_check(control.get("cause", "") == "strategic_attack_victory" and control.get("context", "") == "battle", "battle victory records cause and context")
		_check(control.get("effective_hour", -1) == win.last_simulated_hour and control.get("source_action_id", "") == win_order.get("action_id", ""), "battle control records effective hour and source action")

	var hold := _battle_state(3000, 16000)
	var hold_order := service.attack(hold, map, "formation:attacker", "lille", 0)
	_finish(hold, str(hold_order.get("action_id", "")), 500)
	_check(hold.get_formation("formation:attacker").current_city_id != "lille", "hold or stalemate never teleports attacker into target")
	if hold.get_formation("formation:attacker").formation_status == VNextMilitaryFormation.STATUS_ACTIVE:
		_check(bool(service.move(hold, map, "formation:attacker", "rouen", hold.last_simulated_hour).get("success", false)), "failed attacker can receive recovery order")

	var annihilate := _battle_state(50000, 1)
	var defender_action := _formation_action_id(annihilate, "formation:defender")
	var attack := service.attack(annihilate, map, "formation:attacker", "lille", 0)
	_finish(annihilate, str(attack.get("action_id", "")), 500)
	var defender := annihilate.get_formation("formation:defender")
	_check(defender.personnel == 0 and defender.formation_status == VNextMilitaryFormation.STATUS_DESTROYED, "combat annihilates active defender")
	_check(not annihilate.active_actions.has(defender_action) and not _queue_contains(annihilate, defender_action), "annihilation cleans defender action and queue same boundary")
	_check(annihilate.is_valid(map), "post-annihilation state is immediately valid")
	var snap := annihilate.snapshot()
	var restored := VNextMilitaryState.new()
	_check(restored.restore(snap, map), "post-annihilation snapshot restores immediately")
	_check(_advance(restored, restored.last_simulated_hour + 1), "restored annihilation state can advance")
	_check(not bool(service.move(restored, map, "formation:defender", "rouen", restored.last_simulated_hour).get("success", false)), "destroyed defender rejects normal command")

func _test_attacker_annihilation() -> void:
	var old_loss := float(map.battle_rules.get("defender_win_loss_rate", 0.18))
	map.battle_rules["defender_win_loss_rate"] = 1.0
	var state := _battle_state(1, 50000)
	var order := service.attack(state, map, "formation:attacker", "lille", 0)
	var attack_id := str(order.get("action_id", ""))
	_finish(state, attack_id, 500)
	var attacker := state.get_formation("formation:attacker")
	_check(attacker.personnel == 0 and attacker.formation_status == VNextMilitaryFormation.STATUS_DESTROYED, "combat annihilates attacking formation")
	_check(attacker.action_state == VNextMilitaryFormation.ACTION_IDLE, "annihilated attacker is terminal idle")
	_check(not state.active_actions.has(attack_id) and not _queue_contains(state, attack_id), "annihilated attacker leaves no stale action or reservation")
	_check(state.is_valid(map), "attacker annihilation returns valid state immediately")
	var snap := state.snapshot()
	var restored := VNextMilitaryState.new()
	_check(restored.restore(snap, map), "attacker-annihilation snapshot restores")
	_check(_advance(restored, restored.last_simulated_hour + 1), "restored attacker-annihilation state advances")
	_check(not bool(service.move(restored, map, "formation:attacker", "rouen", restored.last_simulated_hour).get("success", false)), "destroyed attacker rejects ordinary order")
	map.battle_rules["defender_win_loss_rate"] = old_loss

func _test_strict_restore_extensions() -> void:
	var state := _new_state()
	_add(state, "formation:strict", "paris", 5000, 1.0)
	service.move(state, map, "formation:strict", "rouen", 0)
	_check(_advance(state, 1), "strict restore fixture enters current edge")
	var valid := state.snapshot()

	var mismatch := valid.duplicate(true)
	((mismatch.get("formations", []) as Array)[0] as Dictionary)["action_state"] = VNextMilitaryFormation.ACTION_IDLE
	_check(_transactionally_rejected(mismatch), "action-to-idle formation mismatch rejects transactionally")

	var reverse := valid.duplicate(true)
	(reverse.get("active_actions", []) as Array).clear()
	reverse["link_queues"] = {}
	reverse["link_capacity_used"] = {}
	_check(_transactionally_rejected(reverse), "non-idle formation without action rejects transactionally")

	var discontinuous := valid.duplicate(true)
	var discontinuous_action: Dictionary = (discontinuous.get("active_actions", []) as Array)[0] as Dictionary
	(discontinuous_action.get("route", {}) as Dictionary)["city_ids"] = ["paris", "berlin"]
	_check(_transactionally_rejected(discontinuous), "discontinuous route rejects transactionally")

	var zero_eta := valid.duplicate(true)
	var zero_eta_action: Dictionary = (zero_eta.get("active_actions", []) as Array)[0] as Dictionary
	zero_eta_action["eta_hour"] = zero_eta_action["start_hour"]
	_check(_transactionally_rejected(zero_eta), "zero action duration rejects transactionally")

	var negative_route := valid.duplicate(true)
	var negative_action: Dictionary = (negative_route.get("active_actions", []) as Array)[0] as Dictionary
	(negative_action.get("route", {}) as Dictionary)["duration_hours"] = -1
	_check(_transactionally_rejected(negative_route), "negative route duration rejects transactionally")

	var bad_edge := valid.duplicate(true)
	((bad_edge.get("active_actions", []) as Array)[0] as Dictionary)["current_edge_index"] = 999
	_check(_transactionally_rejected(bad_edge), "out-of-range current edge rejects transactionally")

	var bad_progress := valid.duplicate(true)
	((bad_progress.get("active_actions", []) as Array)[0] as Dictionary)["progress"] = 2.0
	_check(_transactionally_rejected(bad_progress), "invalid progress rejects transactionally")

	var future_request := valid.duplicate(true)
	((future_request.get("active_actions", []) as Array)[0] as Dictionary)["edge_request_hour"] = int(future_request.get("last_simulated_hour", 0)) + 1
	_check(_transactionally_rejected(future_request), "future current-edge request hour rejects transactionally")

	var negative_elapsed := valid.duplicate(true)
	((negative_elapsed.get("active_actions", []) as Array)[0] as Dictionary)["edge_elapsed_hours"] = -1
	_check(_transactionally_rejected(negative_elapsed), "negative edge elapsed time rejects transactionally")

	var load_overflow := valid.duplicate(true)
	var load_action: Dictionary = (load_overflow.get("active_actions", []) as Array)[0] as Dictionary
	load_action["edge_load_remaining"] = float(load_action.get("edge_load_total", 0.0)) + 1.0
	_check(_transactionally_rejected(load_overflow), "remaining load above total rejects transactionally")

	var bogus_queue := valid.duplicate(true)
	var queue_action: Dictionary = (bogus_queue.get("active_actions", []) as Array)[0] as Dictionary
	var queue_link := str(((queue_action.get("route", {}) as Dictionary).get("link_ids", []) as Array)[int(queue_action.get("current_edge_index", 0))])
	var queues: Dictionary = bogus_queue.get("link_queues", {}) as Dictionary
	if not queues.has(queue_link):
		queues[queue_link] = []
	(queues[queue_link] as Array).append("military_action:999999")
	_check(_transactionally_rejected(bogus_queue), "bogus queue request rejects transactionally")

	var wrong_queue := valid.duplicate(true)
	var wrong_action: Dictionary = (wrong_queue.get("active_actions", []) as Array)[0] as Dictionary
	var current_link := str(((wrong_action.get("route", {}) as Dictionary).get("link_ids", []) as Array)[int(wrong_action.get("current_edge_index", 0))])
	var wrong_queues: Dictionary = wrong_queue.get("link_queues", {}) as Dictionary
	for link: Dictionary in map.get_all_links():
		var candidate := str(link.get("id", ""))
		if candidate != current_link:
			wrong_queues.erase(current_link)
			wrong_queues[candidate] = [str(wrong_action.get("action_id", ""))]
			break
	_check(_transactionally_rejected(wrong_queue), "queue on wrong link rejects transactionally")

	var capacity_overflow := valid.duplicate(true)
	(capacity_overflow.get("link_capacity_used", {}) as Dictionary)[current_link] = map.get_link_transport_capacity_per_hour(current_link) + 1.0
	_check(_transactionally_rejected(capacity_overflow), "capacity ledger overflow rejects transactionally")

	var orphan_reservation := valid.duplicate(true)
	((orphan_reservation.get("active_actions", []) as Array)[0] as Dictionary)["reserved_link_id"] = "missing_link"
	_check(_transactionally_rejected(orphan_reservation), "orphan reservation rejects transactionally")

	var inaccessible := valid.duplicate(true)
	var access_action: Dictionary = (inaccessible.get("active_actions", []) as Array)[0] as Dictionary
	var access_route: Dictionary = access_action.get("route", {}) as Dictionary
	var access_edge := int(access_action.get("current_edge_index", 0))
	var next_city := str((access_route.get("city_ids", []) as Array)[access_edge + 1])
	var next_region := map.get_region_id_for_city(next_city)
	(inaccessible.get("region_controls", {}) as Dictionary)[next_region] = "country_bel"
	_check(_transactionally_rejected(inaccessible), "moving current edge with incompatible controller rejects transactionally")

	var prep_state := _battle_state(9000, 6000)
	var prep_order := service.attack(prep_state, map, "formation:attacker", "lille", 0)
	var prep_id := str(prep_order.get("action_id", ""))
	var reached_preparing := false
	for _i: int in range(400):
		if not prep_state.active_actions.has(prep_id):
			break
		var live: Dictionary = prep_state.active_actions[prep_id] as Dictionary
		if str(live.get("transport_state", "")) == "preparing":
			reached_preparing = true
			break
		if not _advance(prep_state, prep_state.last_simulated_hour + 1):
			break
	_check(reached_preparing, "attack reaches explicit preparation state")
	if reached_preparing:
		var prep_snap := prep_state.snapshot()
		var missing_end := prep_snap.duplicate(true)
		_find_snapshot_action(missing_end, prep_id).erase("preparation_end_hour")
		_check(_transactionally_rejected(missing_end), "missing preparation end rejects transactionally")
		var zero_prep := prep_snap.duplicate(true)
		_find_snapshot_action(zero_prep, prep_id)["attack_preparation_hours"] = 0
		_check(_transactionally_rejected(zero_prep), "zero preparation duration rejects transactionally")

func _test_control_boundary() -> void:
	var setup := _new_state()
	_check(service.setup_region_controller(setup, map, "northern_industrial_belt", "country_bel", "initial fixture"), "initial fixture setup succeeds")
	var record: Dictionary = setup.control_history.back() as Dictionary
	_check(record.get("effective_hour", -1) == 0 and record.get("context", "") == "setup_fixture", "setup control records hour and context")
	_add(setup, "formation:control", "paris", 1000, 1.0)
	service.move(setup, map, "formation:control", "rouen", 0)
	_check(not service.setup_region_controller(setup, map, "northern_industrial_belt", "country_fra", "late fixture"), "setup mutation rejects after action exists")
	_check(not setup.apply_region_control_change("northern_industrial_belt", "country_fra", "fixture", 0, "setup_fixture"), "direct setup bypass rejects after action exists")
	_check(_advance(setup, 1), "control boundary fixture advances")
	_check(not service.setup_region_controller(setup, map, "northern_industrial_belt", "country_fra", "late fixture"), "setup mutation rejects after simulation starts")
	_check(not setup.apply_region_control_change("northern_industrial_belt", "country_fra", "strategic_attack_victory", setup.last_simulated_hour, "battle", "military_action:999999"), "direct arbitrary battle-control bypass rejects")

func _test_restore_readiness_concentrate_scope() -> void:
	var restore_state := _new_state()
	_add(restore_state, "formation:restore", "paris", 5000, 1.0)
	service.move(restore_state, map, "formation:restore", "rouen", 0)
	_check(_advance(restore_state, 1), "restore fixture enters transport")
	var valid := restore_state.snapshot()
	var roundtrip := VNextMilitaryState.new()
	_check(roundtrip.restore(valid, map) and roundtrip.snapshot() == valid, "valid transport snapshot roundtrips")
	var missing := valid.duplicate(true)
	(missing.get("active_actions", []) as Array).clear()
	missing["link_queues"] = {}
	missing["link_capacity_used"] = {}
	_check(_transactionally_rejected(missing), "reverse formation/action mismatch rejects transactionally")
	var bogus := valid.duplicate(true)
	var action: Dictionary = (bogus.get("active_actions", []) as Array)[0] as Dictionary
	var link := str(((action.get("route", {}) as Dictionary).get("link_ids", []) as Array)[int(action.get("current_edge_index", 0))])
	var queues: Dictionary = bogus.get("link_queues", {}) as Dictionary
	if not queues.has(link):
		queues[link] = []
	(queues[link] as Array).append("military_action:999999")
	_check(_transactionally_rejected(bogus), "bogus queue request rejects transactionally")

	var healthy := _new_state()
	var low := _new_state()
	_add(healthy, "formation:healthy", "paris", 8000, 1.0)
	_add(low, "formation:low", "paris", 8000, 0.1, "country_fra", 0.8, 0.1, 0.1)
	low.get_formation("formation:low").update_supply({"food":0.1,"ammunition":0.1,"equipment":0.1,"transport_capacity":0.1}, 0.1, "cut")
	var healthy_move := service.move(healthy, map, "formation:healthy", "marseille", 0)
	var low_move := service.move(low, map, "formation:low", "marseille", 0)
	_check(float(service.get_action(low, str(low_move.get("action_id", ""))).get("edge_load_total", 0.0)) > float(service.get_action(healthy, str(healthy_move.get("action_id", ""))).get("edge_load_total", 0.0)), "low supply organization equipment morale penalize movement")

	var recovery := _new_state()
	_add(recovery, "formation:recovery", "paris", 2000, 0.2)
	var formation := recovery.get_formation("formation:recovery")
	formation.organization = 0.2
	formation.morale = 0.2
	formation.update_supply({"food":0.0,"ammunition":0.0,"equipment":0.0,"transport_capacity":0.0},0.0,"cut")
	var old_org := formation.organization
	var old_equipment := formation.equipment_factor()
	service.set_supply_input(recovery, map, "paris_basin", _abundant_supply())
	_check(_advance(recovery, 72), "recovery fixture advances")
	_check(formation.organization > old_org and formation.equipment_factor() > old_equipment and formation.formation_status == VNextMilitaryFormation.STATUS_ACTIVE, "local supply preserves bounded recovery path")

	var conc := _new_state()
	_add(conc, "formation:c1", "paris", 2000, 1.0)
	_add(conc, "formation:c2", "rouen", 2000, 1.0)
	var sequence := conc.next_action_sequence
	_check(not bool(service.concentrate(conc, map, ["formation:c1","formation:c1"], "lyon", 0).get("success", false)) and conc.active_actions.is_empty() and conc.next_action_sequence == sequence, "duplicate concentrate IDs reject atomically")
	_check(not bool(service.concentrate(conc, map, ["formation:c1","formation:missing"], "lyon", 0).get("success", false)) and conc.active_actions.is_empty() and conc.next_action_sequence == sequence, "invalid concentrate batch rejects atomically")
	_check(bool(service.concentrate(conc, map, ["formation:c2","formation:c1"], "lyon", 0).get("success", false)), "valid concentrate batch succeeds")

	var bounded := _new_state()
	for index: int in range(400):
		bounded.append_completed_action({"action_id":"military_action:%06d" % (index + 1),"kind":"move"})
		bounded.append_battle_result({"action_id":"military_action:%06d" % (index + 1)})
		bounded.append_control_history({"region_id":"paris_basin","previous_controller_id":"country_fra","controller_id":"country_bel","cause":"fixture","effective_hour":0,"context":"setup_fixture","source_action_id":""})
	_check(bounded.completed_actions.size() == 256 and bounded.battle_results.size() == 128 and bounded.control_history.size() == 256, "completed battle and control histories remain bounded")
	var runtime := FileAccess.get_file_as_string("res://scripts/vnext/world_runtime.gd")
	var service_source := FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	var adapter := FileAccess.get_file_as_string("res://scripts/vnext/map/military_map_adapter.gd")
	_check(not runtime.contains("VNextMilitary"), "world_runtime remains unchanged")
	_check(adapter.contains("PrototypeV2Data") and not service_source.contains("MilitaryManager") and not service_source.contains("GlobalManager") and not service_source.contains("GameContext"), "map reuse and architecture scope remain intact")

func _advance(state: VNextMilitaryState, target_hour: int) -> bool:
	var result := service.advance_to_hour(state, map, target_hour)
	return bool(result.get("success", false))

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
	return {"food":100000.0,"ammunition":100000.0,"equipment":100000.0,"transport_capacity":100000.0}

func _find_supply(state: VNextMilitaryState, formation_id: String, resource: String) -> Dictionary:
	for shipment: Dictionary in service.get_supply_shipments(state):
		if str(shipment.get("destination_formation_id", "")) == formation_id and str(shipment.get("resource_id", "")) == resource:
			return shipment
	return {}

func _advance_supply_to_intermediate(state: VNextMilitaryState, formation_id: String, resource: String, max_hours: int) -> Dictionary:
	var deadline := state.last_simulated_hour + max_hours
	while state.last_simulated_hour < deadline:
		if not _advance(state, state.last_simulated_hour + 1):
			return {}
		var shipment := _find_supply(state, formation_id, resource)
		if shipment.is_empty():
			return {}
		var route: Dictionary = shipment.get("route", {}) as Dictionary
		var edge := int(shipment.get("current_edge_index", -1))
		if edge > 0 and edge < (route.get("link_ids", []) as Array).size():
			return shipment
	return {}

func _slicing_state() -> VNextMilitaryState:
	var state := _new_state()
	_add(state, "formation:slice", "paris", 5000, 1.0)
	service.set_supply_input(state, map, "paris_basin", {"food":10000.0,"ammunition":3000.0,"equipment":1000.0,"transport_capacity":2000.0})
	service.move(state, map, "formation:slice", "marseille", 0)
	return state

func _battle_state(attacker: int, defender: int) -> VNextMilitaryState:
	var state := _new_state()
	service.setup_region_controller(state, map, "northern_industrial_belt", "country_bel", "battle fixture")
	_add(state, "formation:attacker", "paris", attacker, 1.0, "country_fra", 0.9, 0.9, 0.9)
	_add(state, "formation:defender", "lille", defender, 1.0, "country_bel", 0.8, 0.8, 0.8)
	service.defend(state, map, "formation:defender", 0, 500)
	return state

func _finish(state: VNextMilitaryState, action_id: String, max_hours: int) -> void:
	var deadline := state.last_simulated_hour + max_hours
	while state.active_actions.has(action_id) and state.last_simulated_hour < deadline:
		if not _advance(state, state.last_simulated_hour + 1):
			break
	_check(not state.active_actions.has(action_id), "action completes within bounded horizon")

func _formation_action_id(state: VNextMilitaryState, formation_id: String) -> String:
	for raw_id: Variant in state.active_actions.keys():
		var action_id := str(raw_id)
		var action: Dictionary = state.active_actions[action_id] as Dictionary
		if str(action.get("formation_id", "")) == formation_id:
			return action_id
	return ""

func _queue_contains(state: VNextMilitaryState, request_id: String) -> bool:
	for raw_queue: Variant in state.link_queues.values():
		if raw_queue is Array and (raw_queue as Array).has(request_id):
			return true
	return false

func _find_snapshot_action(data: Dictionary, action_id: String) -> Dictionary:
	for raw: Variant in data.get("active_actions", []) as Array:
		if raw is Dictionary and str((raw as Dictionary).get("action_id", "")) == action_id:
			return raw as Dictionary
	return {}

func _transactionally_rejected(data: Dictionary) -> bool:
	var candidate := _new_state()
	_add(candidate, "formation:sentinel", "paris", 1000, 1.0)
	var before := candidate.snapshot()
	return not candidate.restore(data, map) and candidate.snapshot() == before

func _new_state() -> VNextMilitaryState:
	var state := VNextMilitaryState.new()
	_check(state.initialize(map), "military state initializes")
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
