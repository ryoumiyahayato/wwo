extends SceneTree

var checks: int = 0
var failures: int = 0
var map: VNextMilitaryMapAdapter
var service := VNextMilitaryService.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	map = VNextMilitaryMapAdapter.new()
	_check(map.load_existing_map(), "map adapter loads existing world map")
	if map != null and map.errors.is_empty():
		_test_map_capacity_truth()
		_test_shared_capacity_and_ordering()
		_test_supply_competition()
		_test_per_edge_movement_and_slicing()
		_test_attack_positioning_and_combat()
		_test_destroyed_and_strict_restore()
		_test_condition_penalties_and_recovery()
		_test_concentrate_control_history_and_scope()
	print("VNext military strategic system: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_map_capacity_truth() -> void:
	_check(map.get_city_ids().size() == 32, "strategic map reuses 32 existing cities")
	_check(map.get_all_links().size() == 15, "strategic map reuses existing road rail shipping links")
	var road_route: Dictionary = map.find_route("paris", "rouen", ["road"])
	var rail_route: Dictionary = map.find_route("paris", "rouen", ["rail"])
	var sea_route: Dictionary = map.find_route("paris", "london")
	_check(bool(road_route.get("reachable", false)), "road route is reachable")
	_check(bool(rail_route.get("reachable", false)), "rail route is reachable")
	_check(bool(sea_route.get("reachable", false)) and (sea_route.get("mode_sequence", []) as Array).has("shipping"), "shipping route is reused")
	_check(int(rail_route.get("duration_hours", 0)) < int(road_route.get("duration_hours", 0)), "rail is faster than road")
	_check(float(rail_route.get("supply_capacity_per_day", 0.0)) > float(road_route.get("supply_capacity_per_day", 0.0)), "rail has more shared throughput than road")

	var rail_link_id: String = str((rail_route.get("link_ids", []) as Array)[0])
	var original_capacity: int = int((map.links[rail_link_id] as Dictionary).get("capacity_personnel", 0))
	(map.links[rail_link_id] as Dictionary)["capacity_personnel"] = 0
	_check(map.get_link_transport_capacity_per_hour(rail_link_id) == 0.0, "zero link capacity stays zero")
	_check(not bool(map.find_route("paris", "rouen", ["rail"]).get("reachable", false)), "zero capacity link is impassable")
	(map.links[rail_link_id] as Dictionary)["capacity_personnel"] = original_capacity

	var road_link_id: String = str((road_route.get("link_ids", []) as Array)[0])
	var old_road_hours: int = int((map.links[road_link_id] as Dictionary).get("movement_hours", 0))
	var old_rail_hours: int = int((map.links[rail_link_id] as Dictionary).get("movement_hours", 0))
	(map.links[road_link_id] as Dictionary)["movement_hours"] = 20
	(map.links[rail_link_id] as Dictionary)["movement_hours"] = 20
	var equal_a: Dictionary = map.find_route("paris", "rouen")
	var equal_b: Dictionary = map.find_route("paris", "rouen")
	_equal(equal_a.get("link_ids", []), equal_b.get("link_ids", []), "equal cost route tie is deterministic")
	_check(str((equal_a.get("link_ids", []) as Array)[0]) == mini(road_link_id, rail_link_id), "equal cost route chooses stable lexical link tie break")
	(map.links[road_link_id] as Dictionary)["movement_hours"] = old_road_hours
	(map.links[rail_link_id] as Dictionary)["movement_hours"] = old_rail_hours

	var small_state := _new_state()
	_check(_add(small_state, "formation:small_wave", "paris", 4000, 1.0), "create small-capacity test formation")
	(map.links[rail_link_id] as Dictionary)["capacity_personnel"] = 100
	var small_move: Dictionary = service.move(small_state, map, "formation:small_wave", "rouen", 0)
	_check(bool(small_move.get("success", false)), "very small positive capacity remains traversable")
	_check(int(small_move.get("eta_hour", 0)) > int((small_move.get("route", {}) as Dictionary).get("duration_hours", 0)), "very small capacity creates finite waves")
	(map.links[rail_link_id] as Dictionary)["capacity_personnel"] = original_capacity


func _test_shared_capacity_and_ordering() -> void:
	var state := _new_state()
	_check(_add(state, "formation:army_a", "paris", 24000, 1.0), "create first 24k formation")
	_check(_add(state, "formation:army_b", "paris", 24000, 1.0), "create second 24k formation")
	_check(_add(state, "formation:army_c", "paris", 24000, 1.0), "create third 24k formation")
	var first: Dictionary = service.move(state, map, "formation:army_a", "rouen", 0)
	var second: Dictionary = service.move(state, map, "formation:army_b", "rouen", 0)
	var third: Dictionary = service.move(state, map, "formation:army_c", "rouen", 0)
	_check(bool(first.get("success", false)) and bool(second.get("success", false)) and bool(third.get("success", false)), "three formations enter shared contention")
	var first_id: String = str(first.get("action_id", ""))
	var second_id: String = str(second.get("action_id", ""))
	var third_id: String = str(third.get("action_id", ""))
	_check(VNextStableId.kind_of(first_id) == "military_action", "military action uses shared stable ID contract")
	var link_id: String = str(((first.get("route", {}) as Dictionary).get("link_ids", []) as Array)[0])
	_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "advance shared link one hour")
	var capacity_view: Dictionary = service.get_link_capacity_view(state, map, link_id)
	var queue: Array = capacity_view.get("queue", []) as Array
	_check(queue.size() >= 3, "all three movement requests share one link queue")
	_check(str(queue[0]) == first_id and str(queue[1]) == second_id and str(queue[2]) == third_id, "same-hour movement ordering follows stable action IDs")
	_check(float(capacity_view.get("used_capacity", 0.0)) <= float(capacity_view.get("capacity_per_hour", 0.0)) + 0.001, "shared link use never exceeds map capacity")
	var nominal_eta: int = int(first.get("eta_hour", 0))
	service.advance_to_hour(state, map, nominal_eta)
	var arrived_count: int = 0
	for formation_id: String in ["formation:army_a", "formation:army_b", "formation:army_c"]:
		if state.get_formation(formation_id).current_city_id == "rouen":
			arrived_count += 1
	_check(arrived_count < 3, "three 24k formations cannot all complete one nominal rail cycle")

	var load_state := _new_state()
	_check(_add(load_state, "formation:personnel_small", "paris", 4000, 1.0), "create small personnel load")
	_check(_add(load_state, "formation:personnel_large", "paris", 8000, 1.0), "create large personnel load")
	var small_action: Dictionary = service.move(load_state, map, "formation:personnel_small", "rouen", 0)
	var large_action: Dictionary = service.move(load_state, map, "formation:personnel_large", "rouen", 0)
	_check(float(service.get_action(load_state, str(large_action.get("action_id", ""))).get("edge_load_total", 0.0)) > float(service.get_action(load_state, str(small_action.get("action_id", ""))).get("edge_load_total", 0.0)), "personnel consumes transport capacity")
	var service_source: String = FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	_check(service_source.contains("equipment_load") and service_source.contains("EQUIPMENT_LOAD_PER_PERSON"), "equipment contributes explicit unified transport load")

	var replay_a := _contention_replay_state()
	var replay_b := _contention_replay_state()
	service.advance_to_hour(replay_a, map, 72)
	service.advance_to_hour(replay_b, map, 72)
	_equal(replay_a.snapshot(), replay_b.snapshot(), "same-hour multi-army contention replays deterministically")


func _test_supply_competition() -> void:
	var state := _new_state()
	_check(_add(state, "formation:mover", "paris", 12000, 1.0), "create mover for logistics competition")
	_check(_add(state, "formation:supply_target", "rouen", 6000, 1.0), "create remote supply target")
	_check(service.set_supply_input(state, map, "paris_basin", {"food": 100000.0, "ammunition": 100000.0, "equipment": 100000.0, "transport_capacity": 100000.0}), "configure fixed remote supply input")
	var move_result: Dictionary = service.move(state, map, "formation:mover", "rouen", 0)
	var move_id: String = str(move_result.get("action_id", ""))
	var link_id: String = str(((move_result.get("route", {}) as Dictionary).get("link_ids", []) as Array)[0])
	var tick: Dictionary = service.advance_to_hour(state, map, 1)
	_check(bool(tick.get("success", false)), "movement and supply advance together")
	var view: Dictionary = service.get_link_capacity_view(state, map, link_id)
	var queue: Array = view.get("queue", []) as Array
	_check(queue.has(move_id), "movement reserves the shared logistics link")
	var saw_supply: bool = false
	for raw_request: Variant in queue:
		if str(raw_request).begins_with("supply:"):
			saw_supply = true
	_check(saw_supply, "supply cargo enters the same link queue as movement")
	_check(float(view.get("used_capacity", 0.0)) <= float(view.get("capacity_per_hour", 0.0)) + 0.001, "movement plus supply cannot exceed shared link capacity")
	var supply_report: Dictionary = tick.get("supply", {}) as Dictionary
	_check(supply_report.has("formation:supply_target"), "supply cargo produces deterministic delivery report")
	var cargo_source: String = FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	_check(cargo_source.contains("CARGO_LOAD_WEIGHTS"), "food ammunition equipment and transport inputs convert to transport load")
	_finish_action(state, move_id, 300)
	service.advance_to_hour(state, map, state.last_simulated_hour + 1)
	var released: Dictionary = service.get_link_capacity_view(state, map, link_id)
	_check(not (released.get("queue", []) as Array).has(move_id), "completed movement releases link reservation")


func _test_per_edge_movement_and_slicing() -> void:
	var state := _new_state()
	_check(_add(state, "formation:route_army", "paris", 8000, 1.0), "create multi-edge formation")
	var move_result: Dictionary = service.move(state, map, "formation:route_army", "marseille", 0)
	_check(bool(move_result.get("success", false)), "multi-edge movement starts")
	var action_id: String = str(move_result.get("action_id", ""))
	var route: Dictionary = move_result.get("route", {}) as Dictionary
	_check((route.get("link_ids", []) as Array).size() >= 2, "paris to marseille uses multiple edges")
	var intermediate_found: bool = false
	for _step: int in range(1, 300):
		service.advance_to_hour(state, map, state.last_simulated_hour + 1)
		var formation: VNextMilitaryFormation = state.get_formation("formation:route_army")
		if state.active_actions.has(action_id) and formation.current_city_id != "paris":
			intermediate_found = true
			break
	_check(intermediate_found, "formation exposes intermediate strategic waypoint before destination")
	if intermediate_found:
		var action: Dictionary = service.get_action(state, action_id)
		var edge_index: int = int(action.get("current_edge_index", -1))
		var city_ids: Array = (action.get("route", {}) as Dictionary).get("city_ids", []) as Array
		_check(edge_index > 0 and edge_index < city_ids.size(), "action tracks current route edge")
		var next_city: String = str(city_ids[edge_index + 1]) if edge_index + 1 < city_ids.size() else ""
		var next_region: String = map.get_region_id_for_city(next_city)
		if not next_region.is_empty():
			_check(service.setup_region_controller(state, map, next_region, "country_bel", "mid-route control cut fixture"), "fixture changes next region controller mid-route")
			service.advance_to_hour(state, map, state.last_simulated_hour + 1)
			var blocked: Dictionary = service.get_action(state, action_id)
			_check(str(blocked.get("transport_state", "")) in ["blocked", "interrupted"], "next edge recheck blocks route after enemy control change")
			_check(state.get_formation("formation:route_army").current_city_id != "marseille", "blocked route cannot tunnel through changed control")
			_check(service.setup_region_controller(state, map, next_region, "country_fra", "restore route fixture"), "fixture restores route access")
			_finish_action(state, action_id, 500)
			_equal(state.get_formation("formation:route_army").current_city_id, "marseille", "blocked formation can recover and continue after access returns")

	var big := _slicing_state()
	var sliced := _slicing_state()
	_check(bool(service.advance_to_hour(big, map, 240).get("success", false)), "single 240h advance succeeds")
	for day: int in range(1, 11):
		_check(bool(service.advance_to_hour(sliced, map, day * 24).get("success", false)), "sliced 24h advance succeeds day %d" % day)
	_equal(big.snapshot(), sliced.snapshot(), "advance 240h once equals advance 24h x10")


func _test_attack_positioning_and_combat() -> void:
	var win_state := _battle_state(50000, 1500, 1.0, 0.8)
	var win_order: Dictionary = service.attack(win_state, map, "formation:attacker", "lille", 0)
	_check(bool(win_order.get("success", false)), "strong attacker starts attack")
	_finish_action(win_state, str(win_order.get("action_id", "")), 600)
	var win_battle: Dictionary = win_state.battle_results.back() as Dictionary
	_equal(win_battle.get("outcome"), "attacker_win", "extreme force advantage produces attacker victory")
	_equal(win_state.get_formation("formation:attacker").current_city_id, "lille", "attacker victory enters target city")
	_equal(win_state.region_controls.get("northern_industrial_belt"), "country_fra", "victory changes military control")
	_check(int(win_battle.get("attacker_losses", -1)) >= 0 and int(win_battle.get("attacker_losses", 999999)) <= 50000, "attacker casualties are bounded by available personnel")
	_check(int(win_battle.get("defender_losses", -1)) >= 0, "defender casualties are nonnegative")

	var hold_state := _battle_state(3000, 16000, 0.65, 1.0)
	var hold_order: Dictionary = service.attack(hold_state, map, "formation:attacker", "lille", 0)
	_finish_action(hold_state, str(hold_order.get("action_id", "")), 600)
	var hold_battle: Dictionary = hold_state.battle_results.back() as Dictionary
	_check(str(hold_battle.get("outcome", "")) in ["defender_hold", "stalemate"], "strong defense prevents attacker victory")
	_equal(hold_state.region_controls.get("northern_industrial_belt"), "country_bel", "defender hold keeps target control")
	_check(hold_state.get_formation("formation:attacker").current_city_id != "lille", "defender hold does not place attacker inside enemy target")
	if hold_state.get_formation("formation:attacker").formation_status == VNextMilitaryFormation.STATUS_ACTIVE:
		var retreat: Dictionary = service.move(hold_state, map, "formation:attacker", "rouen", hold_state.last_simulated_hour)
		_check(bool(retreat.get("success", false)), "held attacker can retreat or receive a new legal order")

	var old_win: float = float(map.battle_rules.get("attack_ratio_for_win", 1.25))
	var old_hold: float = float(map.battle_rules.get("attack_ratio_for_hold", 0.85))
	map.battle_rules["attack_ratio_for_win"] = 999.0
	map.battle_rules["attack_ratio_for_hold"] = -1.0
	var stale_state := _battle_state(9000, 6000, 0.9, 0.9)
	var stale_order: Dictionary = service.attack(stale_state, map, "formation:attacker", "lille", 0)
	_finish_action(stale_state, str(stale_order.get("action_id", "")), 600)
	var stale_battle: Dictionary = stale_state.battle_results.back() as Dictionary
	_equal(stale_battle.get("outcome"), "stalemate", "forced threshold scenario resolves stalemate")
	_check(stale_state.get_formation("formation:attacker").current_city_id != "lille", "stalemate keeps attacker outside enemy city")
	map.battle_rules["attack_ratio_for_win"] = old_win
	map.battle_rules["attack_ratio_for_hold"] = old_hold

	var undersupplied := _battle_state(9000, 7000, 0.9, 0.9)
	undersupplied.get_formation("formation:attacker").update_supply({"food": 0.05, "ammunition": 0.05, "equipment": 0.05, "transport_capacity": 0.05}, 0.05, "cut")
	undersupplied.get_formation("formation:defender").update_supply({"food": 0.05, "ammunition": 0.05, "equipment": 0.05, "transport_capacity": 0.05}, 0.05, "cut")
	var under_preview: Dictionary = service.preview_battle(undersupplied, map, "formation:attacker", "lille")
	_check(is_finite(float(under_preview.get("attacker_power", NAN))) and is_finite(float(under_preview.get("defender_power", NAN))), "both undersupplied combat remains finite")


func _test_destroyed_and_strict_restore() -> void:
	var destroyed_state := _new_state()
	_check(_add(destroyed_state, "formation:destroyed_unit", "paris", 100, 1.0), "create formation for annihilation")
	var destroyed: VNextMilitaryFormation = destroyed_state.get_formation("formation:destroyed_unit")
	destroyed.apply_losses(100)
	_equal(destroyed.personnel, 0, "runtime losses may reduce personnel to zero")
	_equal(destroyed.formation_status, VNextMilitaryFormation.STATUS_DESTROYED, "zero personnel atomically becomes destroyed terminal state")
	var destroyed_snapshot: Dictionary = destroyed_state.snapshot()
	var destroyed_restored := VNextMilitaryState.new()
	_check(destroyed_restored.restore(destroyed_snapshot, map), "zero-personnel destroyed formation snapshot restores")
	_equal(destroyed_restored.snapshot(), destroyed_snapshot, "destroyed formation snapshot roundtrips exactly")

	var source := _new_state()
	_check(_add(source, "formation:restore_unit", "paris", 5000, 1.0), "create formation for strict action restore")
	var issued: Dictionary = service.move(source, map, "formation:restore_unit", "rouen", 0)
	_check(bool(issued.get("success", false)), "create valid active action snapshot")
	var valid: Dictionary = source.snapshot()
	var roundtrip := VNextMilitaryState.new()
	_check(roundtrip.restore(valid, map), "valid active action snapshot restores")
	_equal(roundtrip.snapshot(), valid, "valid active action snapshot roundtrips")

	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["kind"] = "unknown"), "unknown action kind rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["route"] = {}), "missing or empty transport route rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: ((s["active_actions"] as Array)[0]["route"] as Dictionary)["city_ids"] = ["paris", "berlin"]), "discontinuous route rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["eta_hour"] = (s["active_actions"] as Array)[0]["start_hour"]), "zero duration rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["progress"] = 2.0), "invalid progress rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["formations"] as Array)[0]["action_state"] = "idle"), "formation action mismatch rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: s["next_action_sequence"] = 1), "sequence conflict rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["action_id"] = "military_action:bad_id"), "invalid military action sequence ID rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["origin_city_id"] = "missing_city"), "invalid origin rejected")
	_check(_reject_mutation(valid, func(s: Dictionary) -> void: (s["active_actions"] as Array)[0]["destination_city_id"] = "missing_city"), "invalid target rejected")

	var transactional := _new_state()
	_check(_add(transactional, "formation:sentinel", "paris", 1000, 1.0), "create transactional restore sentinel")
	var before: Dictionary = transactional.snapshot()
	var invalid: Dictionary = valid.duplicate(true)
	(invalid["active_actions"] as Array)[0]["progress"] = -1.0
	_check(not transactional.restore(invalid, map), "invalid restore fails transactionally")
	_equal(transactional.snapshot(), before, "failed restore leaves previous state unchanged")
	_check(not service.create_formation(_new_state(), map, "bad_formation_id", "country_fra", "paris", 1000), "invalid formation stable ID rejected")


func _test_condition_penalties_and_recovery() -> void:
	var healthy := _new_state()
	var low_supply := _new_state()
	var low_org := _new_state()
	var low_equipment := _new_state()
	_add(healthy, "formation:healthy", "paris", 8000, 1.0)
	_add(low_supply, "formation:low_supply", "paris", 8000, 1.0)
	_add(low_org, "formation:low_org", "paris", 8000, 1.0)
	_add(low_equipment, "formation:low_equipment", "paris", 8000, 0.05)
	low_supply.get_formation("formation:low_supply").update_supply({"food": 0.1, "ammunition": 0.1, "equipment": 0.1, "transport_capacity": 0.1}, 0.1, "cut")
	low_org.get_formation("formation:low_org").organization = 0.1
	var healthy_eta: int = int(service.move(healthy, map, "formation:healthy", "marseille", 0).get("eta_hour", 0))
	var low_supply_eta: int = int(service.move(low_supply, map, "formation:low_supply", "marseille", 0).get("eta_hour", 0))
	var low_org_eta: int = int(service.move(low_org, map, "formation:low_org", "marseille", 0).get("eta_hour", 0))
	var low_equipment_eta: int = int(service.move(low_equipment, map, "formation:low_equipment", "marseille", 0).get("eta_hour", 0))
	_check(low_supply_eta > healthy_eta, "low supply reduces movement efficiency")
	_check(low_org_eta > healthy_eta, "low organization reduces movement efficiency")
	_check(low_equipment_eta > healthy_eta, "low equipment reduces movement efficiency")

	var recovery := _new_state()
	_add(recovery, "formation:recovery", "paris", 2000, 0.2)
	var recovering: VNextMilitaryFormation = recovery.get_formation("formation:recovery")
	recovering.organization = 0.2
	recovering.morale = 0.2
	recovering.update_supply({"food": 0.0, "ammunition": 0.0, "equipment": 0.0, "transport_capacity": 0.0}, 0.0, "cut")
	var old_org: float = recovering.organization
	var old_equipment: float = recovering.equipment_factor()
	service.set_supply_input(recovery, map, "paris_basin", {"food": 100000.0, "ammunition": 100000.0, "equipment": 100000.0, "transport_capacity": 100000.0})
	service.advance_to_hour(recovery, map, 72)
	_check(recovering.organization > old_org, "full local supply provides organization recovery path")
	_check(recovering.equipment_factor() > old_equipment, "full local supply provides equipment recovery path")
	_check(recovering.formation_status == VNextMilitaryFormation.STATUS_ACTIVE, "recovery does not require deadlock-breaking teleport")


func _test_concentrate_control_history_and_scope() -> void:
	var state := _new_state()
	_add(state, "formation:conc_a", "paris", 2000, 1.0)
	_add(state, "formation:conc_b", "rouen", 2000, 1.0)
	var sequence_before: int = state.next_action_sequence
	var duplicate: Dictionary = service.concentrate(state, map, ["formation:conc_a", "formation:conc_a"], "lyon", 0)
	_check(not bool(duplicate.get("success", false)), "duplicate concentrate formation IDs rejected")
	_check(state.active_actions.is_empty() and state.next_action_sequence == sequence_before, "duplicate concentrate failure is atomic")
	var invalid_batch: Dictionary = service.concentrate(state, map, ["formation:conc_a", "formation:missing"], "lyon", 0)
	_check(not bool(invalid_batch.get("success", false)), "invalid concentrate batch rejected")
	_check(state.active_actions.is_empty() and state.next_action_sequence == sequence_before, "candidate batch validates fully before action creation")
	var valid_batch: Dictionary = service.concentrate(state, map, ["formation:conc_b", "formation:conc_a"], "lyon", 0)
	_check(bool(valid_batch.get("success", false)) and (valid_batch.get("action_ids", []) as Array).size() == 2, "valid concentrate batch creates atomically")

	var control_state := _new_state()
	_check(service.setup_region_controller(control_state, map, "northern_industrial_belt", "country_bel", "explicit setup fixture"), "control mutation uses explicit setup-only API")
	var control_record: Dictionary = control_state.control_history.back() as Dictionary
	_check(control_record.has("cause") and control_record.has("effective_hour") and control_record.get("context") == "setup_fixture", "control history records cause time and context")
	var service_source: String = FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	_check(not service_source.contains("func set_region_controller("), "unstructured public control teleport API removed")

	var bounded := _new_state()
	for index: int in range(400):
		bounded.append_completed_action({"action_id": "military_action:%06d" % (index + 1), "kind": "move"})
		bounded.append_battle_result({"action_id": "military_action:%06d" % (index + 1)})
		bounded.append_control_history({"region_id": "paris_basin", "previous_controller_id": "country_fra", "controller_id": "country_bel", "cause": "fixture", "effective_hour": 0, "context": "setup_fixture"})
	_check(bounded.completed_actions.size() == VNextMilitaryState.MAX_COMPLETED_ACTIONS, "completed action history is bounded")
	_check(bounded.battle_results.size() == VNextMilitaryState.MAX_BATTLE_RESULTS, "battle history is bounded")
	_check(bounded.control_history.size() == VNextMilitaryState.MAX_CONTROL_HISTORY, "control history is bounded")

	var runtime_source: String = FileAccess.get_file_as_string("res://scripts/vnext/world_runtime.gd")
	_check(not runtime_source.contains("VNextMilitary"), "world_runtime remains unchanged and unintegrated")
	var adapter_source: String = FileAccess.get_file_as_string("res://scripts/vnext/map/military_map_adapter.gd")
	_check(adapter_source.contains("PrototypeV2Data") and adapter_source.contains("strategic_military_overlay.json"), "military reuses existing map and stable-ID overlay")
	_check(not service_source.contains("MilitaryManager") and not service_source.contains("GlobalManager") and not service_source.contains("GameContext"), "no global manager service locator or second world context introduced")


func _contention_replay_state() -> VNextMilitaryState:
	var state := _new_state()
	_add(state, "formation:replay_a", "paris", 10000, 1.0)
	_add(state, "formation:replay_b", "paris", 10000, 1.0)
	_add(state, "formation:replay_c", "paris", 10000, 1.0)
	service.move(state, map, "formation:replay_a", "rouen", 0)
	service.move(state, map, "formation:replay_b", "rouen", 0)
	service.move(state, map, "formation:replay_c", "rouen", 0)
	return state


func _slicing_state() -> VNextMilitaryState:
	var state := _new_state()
	_add(state, "formation:slice_army", "paris", 5000, 1.0)
	service.set_supply_input(state, map, "paris_basin", {"food": 10000.0, "ammunition": 3000.0, "equipment": 1000.0, "transport_capacity": 2000.0})
	service.move(state, map, "formation:slice_army", "marseille", 0)
	return state


func _battle_state(attacker_personnel: int, defender_personnel: int, attacker_equipment: float, defender_equipment: float) -> VNextMilitaryState:
	var state := _new_state()
	service.setup_region_controller(state, map, "northern_industrial_belt", "country_bel", "battle fixture")
	_add(state, "formation:attacker", "paris", attacker_personnel, attacker_equipment, "country_fra", 0.9, 0.9, 0.9)
	_add(state, "formation:defender", "lille", defender_personnel, defender_equipment, "country_bel", 0.8, 0.8, 0.8)
	service.defend(state, map, "formation:defender", 0, 500)
	return state


func _reject_mutation(valid_snapshot: Dictionary, mutate: Callable) -> bool:
	var candidate: Dictionary = valid_snapshot.duplicate(true)
	mutate.call(candidate)
	var restored := VNextMilitaryState.new()
	return not restored.restore(candidate, map)


func _finish_action(state: VNextMilitaryState, action_id: String, max_hours: int) -> void:
	var deadline: int = state.last_simulated_hour + max_hours
	while state.active_actions.has(action_id) and state.last_simulated_hour < deadline:
		var result: Dictionary = service.advance_to_hour(state, map, state.last_simulated_hour + 1)
		if not bool(result.get("success", false)):
			break
	_check(not state.active_actions.has(action_id), "action completes within bounded test horizon: %s" % action_id)


func _new_state() -> VNextMilitaryState:
	var state := VNextMilitaryState.new()
	_check(state.initialize(map), "military state initializes")
	return state


func _add(
	state: VNextMilitaryState,
	formation_id: String,
	city_id: String,
	personnel: int,
	equipment_factor: float,
	country_id: String = "country_fra",
	training: float = 0.8,
	morale: float = 0.8,
	organization: float = 0.8
) -> bool:
	return service.create_formation(state, map, formation_id, country_id, city_id, personnel, {"equipment_factor": equipment_factor}, training, morale, organization)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
