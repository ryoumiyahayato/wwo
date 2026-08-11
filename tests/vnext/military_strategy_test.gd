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
		_test_map_and_shared_capacity()
		_test_supply_chronology()
		_test_supply_interruptions()
		_test_movement_and_determinism()
		_test_combat_and_annihilation()
		_test_strict_restore()
		_test_readiness_recovery()
		_test_control_concentrate_history_scope()
	print("VNext military strategic system: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)

func _test_map_and_shared_capacity() -> void:
	_check(map.get_city_ids().size() == 32, "reuses existing 32-city map")
	_check(map.get_all_links().size() == 15, "reuses road rail shipping links")
	var road := map.find_route("paris", "rouen", ["road"])
	var rail := map.find_route("paris", "rouen", ["rail"])
	var sea := map.find_route("paris", "london")
	_check(bool(road.get("reachable", false)) and bool(rail.get("reachable", false)), "road and rail routes exist")
	_check((sea.get("mode_sequence", []) as Array).has("shipping"), "shipping route is reused")
	_check(int(rail.get("duration_hours", 0)) < int(road.get("duration_hours", 0)), "rail is faster than road")
	var rail_link := str((rail.get("link_ids", []) as Array)[0])
	var old_capacity := int((map.links[rail_link] as Dictionary).get("capacity_personnel", 0))
	(map.links[rail_link] as Dictionary)["capacity_personnel"] = 0
	_check(map.get_link_transport_capacity_per_hour(rail_link) == 0.0, "zero capacity stays zero")
	_check(not bool(map.find_route("paris", "rouen", ["rail"]).get("reachable", false)), "zero capacity is impassable")
	(map.links[rail_link] as Dictionary)["capacity_personnel"] = old_capacity

	var state := _new_state()
	for id: String in ["formation:a", "formation:b", "formation:c"]:
		_add(state, id, "paris", 24000, 1.0)
	var a := service.move(state, map, "formation:a", "rouen", 0)
	var b := service.move(state, map, "formation:b", "rouen", 0)
	var c := service.move(state, map, "formation:c", "rouen", 0)
	_check(bool(a.get("success", false)) and bool(b.get("success", false)) and bool(c.get("success", false)), "three formations enter contention")
	service.advance_to_hour(state, map, 1)
	var view := service.get_link_capacity_view(state, map, rail_link)
	var queue: Array = view.get("queue", []) as Array
	_check(queue.size() >= 3, "three formations share one link queue")
	_check(str(queue[0]) == str(a.get("action_id", "")) and str(queue[1]) == str(b.get("action_id", "")) and str(queue[2]) == str(c.get("action_id", "")), "contention order is stable by action ID")
	_check(float(view.get("used_capacity", 0.0)) <= float(view.get("capacity_per_hour", 0.0)) + 0.001, "shared use never exceeds map capacity")
	var nominal := int(a.get("eta_hour", 0))
	service.advance_to_hour(state, map, nominal)
	var arrived := 0
	for id: String in ["formation:a", "formation:b", "formation:c"]:
		if state.get_formation(id).current_city_id == "rouen":
			arrived += 1
	_check(arrived < 3, "formations do not each receive full independent link capacity")

	var loads := _new_state()
	_add(loads, "formation:small", "paris", 4000, 1.0)
	_add(loads, "formation:large", "paris", 8000, 1.0)
	var small := service.move(loads, map, "formation:small", "rouen", 0)
	var large := service.move(loads, map, "formation:large", "rouen", 0)
	_check(float(service.get_action(loads, str(large["action_id"])).get("edge_load_total", 0.0)) > float(service.get_action(loads, str(small["action_id"])).get("edge_load_total", 0.0)), "personnel consumes capacity")
	var source := FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	_check(source.contains("equipment_load") and source.contains("CARGO_LOAD_WEIGHTS"), "equipment and supply cargo consume shared capacity")

func _test_supply_chronology() -> void:
	var state := _remote_supply_state("formation:supply", "marseille", 6000)
	_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "remote supply starts")
	var food := _find_supply(state, "formation:supply", "food")
	_check(not food.is_empty(), "supply is persisted as in-transit action")
	_check(VNextStableId.kind_of(str(food.get("action_id", ""))) == "military_action", "supply reuses shared military action IDs")
	var route: Dictionary = food.get("route", {}) as Dictionary
	var links: Array = route.get("link_ids", []) as Array
	_check(links.size() >= 2, "supply fixture uses multi-edge route")
	_check(str(food.get("transport_state", "")) != "arrived", "multi-edge cargo cannot arrive in one hour")
	_check(int(food.get("current_edge_index", -1)) == 0, "supply starts on current edge only")
	_check(str(food.get("current_city_id", "")) == str((route.get("city_ids", []) as Array)[0]), "supply records current waypoint")
	_check(int(food.get("eta_hour", 0)) - int(food.get("start_hour", 0)) >= int(route.get("duration_hours", 0)), "route duration constrains arrival")
	_check(is_equal_approx(float(food.get("cargo_amount_total", 0.0)), float(food.get("cargo_amount_remaining", -1.0))), "in-transit cargo is conserved")

	var intermediate := false
	var arrival_hour := -1
	for _i: int in range(500):
		if not bool(service.advance_to_hour(state, map, state.last_simulated_hour + 1).get("success", false)):
			break
		food = _find_supply(state, "formation:supply", "food")
		if food.is_empty():
			break
		var edge := int(food.get("current_edge_index", -1))
		if edge > 0 and edge < links.size():
			intermediate = true
			_check(str(food.get("current_city_id", "")) == str((route.get("city_ids", []) as Array)[edge]), "supply reaches intermediate waypoint chronologically")
			break
	_check(intermediate, "supply exposes an intermediate waypoint")
	while state.last_simulated_hour < 500:
		food = _find_supply(state, "formation:supply", "food")
		if not food.is_empty() and str(food.get("transport_state", "")) == "arrived":
			arrival_hour = state.last_simulated_hour
			break
		service.advance_to_hour(state, map, state.last_simulated_hour + 1)
	_check(arrival_hour >= int(route.get("duration_hours", 0)), "cargo arrival respects route time")
	_check(not food.is_empty() and float(food.get("cargo_amount_remaining", 0.0)) > 0.0, "arrival is distinct from delivery settlement")
	service.advance_to_hour(state, map, state.last_simulated_hour + 1)
	_check(_find_supply(state, "formation:supply", "food").is_empty(), "arrived cargo is consumed without duplication")

	var continuous := _remote_supply_state("formation:resume", "marseille", 5000)
	service.advance_to_hour(continuous, map, 20)
	var snap := continuous.snapshot()
	var resumed := VNextMilitaryState.new()
	_check(resumed.restore(snap, map), "mid-route supply snapshot restores")
	_check(resumed.snapshot() == snap, "mid-route supply restore is exact")
	service.advance_to_hour(continuous, map, 160)
	service.advance_to_hour(resumed, map, 160)
	_check(continuous.snapshot() == resumed.snapshot(), "continuous and restored supply simulation converge exactly")
	var big := _remote_supply_state("formation:jump", "marseille", 4500)
	var sliced := _remote_supply_state("formation:jump", "marseille", 4500)
	service.advance_to_hour(big, map, 120)
	for h: int in [24, 48, 72, 96, 120]:
		service.advance_to_hour(sliced, map, h)
	_check(big.snapshot() == sliced.snapshot(), "supply large jump equals sliced advancement")

func _test_supply_interruptions() -> void:
	var state := _new_state()
	_add(state, "formation:mover", "paris", 12000, 1.0)
	_add(state, "formation:target", "rouen", 6000, 1.0)
	service.set_supply_input(state, map, "paris_basin", _abundant_supply())
	var move := service.move(state, map, "formation:mover", "rouen", 0)
	var link := str(((move.get("route", {}) as Dictionary).get("link_ids", []) as Array)[0])
	service.advance_to_hour(state, map, 1)
	var view := service.get_link_capacity_view(state, map, link)
	var queue: Array = view.get("queue", []) as Array
	var saw_supply := false
	for id: Variant in queue:
		if id != move.get("action_id", ""):
			saw_supply = true
	_check(queue.has(move.get("action_id", "")) and saw_supply, "movement and supply share the same link queue")
	_check(float(view.get("used_capacity", 0.0)) <= float(view.get("capacity_per_hour", 0.0)) + 0.001, "movement plus supply stays within one budget")

	var low := _remote_supply_state("formation:lowcap", "rouen", 6000)
	var route := map.find_route("paris", "rouen", ["rail"])
	var rail_link := str((route.get("link_ids", []) as Array)[0])
	var old := int((map.links[rail_link] as Dictionary).get("capacity_personnel", 0))
	(map.links[rail_link] as Dictionary)["capacity_personnel"] = 10
	service.advance_to_hour(low, map, 1)
	var cargo := _find_supply(low, "formation:lowcap", "food")
	_check(not cargo.is_empty() and float(cargo.get("edge_load_remaining", 0.0)) > 0.0, "small positive capacity creates multi-hour cargo waves")
	(map.links[rail_link] as Dictionary)["capacity_personnel"] = old

	var cut := _remote_supply_state("formation:cut", "marseille", 5000)
	var shipment := _advance_supply_to_intermediate(cut, "formation:cut", "food", 300)
	_check(not shipment.is_empty(), "supply reaches an intermediate edge before interruption test")
	if not shipment.is_empty():
		var current_link := str(((shipment.get("route", {}) as Dictionary).get("link_ids", []) as Array)[int(shipment.get("current_edge_index", 0))])
		var old_cap := int((map.links[current_link] as Dictionary).get("capacity_personnel", 0))
		(map.links[current_link] as Dictionary)["capacity_personnel"] = 0
		service.advance_to_hour(cut, map, cut.last_simulated_hour + 1)
		shipment = _find_supply(cut, "formation:cut", "food")
		_check(str(shipment.get("transport_state", "")) == "interrupted", "mid-route zero capacity interrupts cargo")
		var before := float(shipment.get("cargo_amount_remaining", 0.0))
		(map.links[current_link] as Dictionary)["capacity_personnel"] = old_cap
		service.advance_to_hour(cut, map, cut.last_simulated_hour + 1)
		shipment = _find_supply(cut, "formation:cut", "food")
		_check(str(shipment.get("transport_state", "")) in ["waiting_capacity", "moving"], "capacity recovery resumes cargo")
		_check(is_equal_approx(before, float(shipment.get("cargo_amount_remaining", -1.0))), "interruption does not lose cargo")

func _test_movement_and_determinism() -> void:
	var state := _new_state()
	_add(state, "formation:route", "paris", 8000, 1.0)
	var move := service.move(state, map, "formation:route", "marseille", 0)
	var action_id := str(move.get("action_id", ""))
	var intermediate := false
	for _i: int in range(400):
		service.advance_to_hour(state, map, state.last_simulated_hour + 1)
		if state.active_actions.has(action_id) and state.get_formation("formation:route").current_city_id != "paris":
			intermediate = true
			break
	_check(intermediate, "formation updates strategic position per waypoint")
	var big := _slicing_state()
	var sliced := _slicing_state()
	service.advance_to_hour(big, map, 240)
	for h: int in [24,48,72,96,120,144,168,192,216,240]:
		service.advance_to_hour(sliced, map, h)
	_check(big.snapshot() == sliced.snapshot(), "formation 240h once equals 10x24h")
	var replay_a := _contention_state()
	var replay_b := _contention_state()
	service.advance_to_hour(replay_a, map, 72)
	service.advance_to_hour(replay_b, map, 72)
	_check(replay_a.snapshot() == replay_b.snapshot(), "three-way contention replay is deterministic")

func _test_combat_and_annihilation() -> void:
	var win := _battle_state(50000, 1500)
	var win_order := service.attack(win, map, "formation:attacker", "lille", 0)
	_finish(win, str(win_order.get("action_id", "")), 700)
	var win_result: Dictionary = win.battle_results.back() as Dictionary
	_check(win_result.get("outcome", "") == "attacker_win", "strong attacker wins")
	_check(win.get_formation("formation:attacker").current_city_id == "lille", "victory enters target")
	_check(win.region_controls.get("northern_industrial_belt", "") == "country_fra", "victory changes control")
	var hold := _battle_state(3000, 16000)
	var hold_order := service.attack(hold, map, "formation:attacker", "lille", 0)
	_finish(hold, str(hold_order.get("action_id", "")), 700)
	_check(hold.get_formation("formation:attacker").current_city_id != "lille", "hold or stalemate keeps attacker outside target")
	if hold.get_formation("formation:attacker").formation_status == VNextMilitaryFormation.STATUS_ACTIVE:
		_check(bool(service.move(hold, map, "formation:attacker", "rouen", hold.last_simulated_hour).get("success", false)), "failed attacker remains recoverable")

	var annihilate := _battle_state(50000, 1)
	var defender_action := _formation_action_id(annihilate, "formation:defender")
	var order := service.attack(annihilate, map, "formation:attacker", "lille", 0)
	_finish(annihilate, str(order.get("action_id", "")), 700)
	var defender := annihilate.get_formation("formation:defender")
	_check(defender.formation_status == VNextMilitaryFormation.STATUS_DESTROYED and defender.personnel == 0, "combat can annihilate defending formation")
	_check(not annihilate.active_actions.has(defender_action), "annihilation removes stale defend action in same boundary")
	_check(not _queue_contains(annihilate, defender_action), "annihilation removes stale capacity queue entry")
	_check(annihilate.is_valid(map), "post-annihilation state is immediately valid")
	var snap := annihilate.snapshot()
	var restored := VNextMilitaryState.new()
	_check(restored.restore(snap, map), "immediate post-battle snapshot restores")
	_check(bool(service.advance_to_hour(restored, map, restored.last_simulated_hour + 1).get("success", false)), "restored post-battle state advances again")
	_check(not bool(service.move(restored, map, "formation:defender", "rouen", restored.last_simulated_hour).get("success", false)), "destroyed formation rejects ordinary order")

func _test_strict_restore() -> void:
	var source := _new_state()
	_add(source, "formation:restore", "paris", 5000, 1.0)
	service.move(source, map, "formation:restore", "rouen", 0)
	service.advance_to_hour(source, map, 1)
	var valid := source.snapshot()
	var roundtrip := VNextMilitaryState.new()
	_check(roundtrip.restore(valid, map) and roundtrip.snapshot() == valid, "valid active action snapshot roundtrips")
	for mutation: String in ["unknown_kind","empty_route","zero_duration","bad_edge","bad_progress","forward_missing","bogus_queue","wrong_queue","overflow","orphan_reservation","future_start","negative_elapsed","remaining_over_total","sequence","bad_origin","bad_target"]:
		_check(_transactionally_rejected(_mutate(valid, mutation)), "strict restore rejects %s" % mutation)
	var action: Dictionary = (valid.get("active_actions", []) as Array)[0] as Dictionary
	var current_link := str(((action.get("route", {}) as Dictionary).get("link_ids", []) as Array)[int(action.get("current_edge_index", 0))])
	var old_cap := int((map.links[current_link] as Dictionary).get("capacity_personnel", 0))
	(map.links[current_link] as Dictionary)["capacity_personnel"] = 0
	_check(_transactionally_rejected(valid), "moving current edge rejects authoritative zero capacity")
	(map.links[current_link] as Dictionary)["capacity_personnel"] = old_cap

	var prep := _battle_state(9000, 6000)
	var attack := service.attack(prep, map, "formation:attacker", "lille", 0)
	var attack_id := str(attack.get("action_id", ""))
	for _i: int in range(600):
		if not prep.active_actions.has(attack_id):
			break
		var live: Dictionary = prep.active_actions[attack_id] as Dictionary
		if str(live.get("transport_state", "")) == "preparing":
			break
		service.advance_to_hour(prep, map, prep.last_simulated_hour + 1)
	if prep.active_actions.has(attack_id):
		var prep_snap := prep.snapshot()
		var missing := prep_snap.duplicate(true)
		_find_snapshot_action(missing, attack_id).erase("preparation_end_hour")
		_check(_transactionally_rejected(missing), "restore rejects missing preparation end")
		var zero := prep_snap.duplicate(true)
		_find_snapshot_action(zero, attack_id)["attack_preparation_hours"] = 0
		_check(_transactionally_rejected(zero), "restore rejects zero preparation duration")

func _test_readiness_recovery() -> void:
	var healthy := _new_state()
	var low_supply := _new_state()
	var low_org := _new_state()
	var low_eq := _new_state()
	var low_morale := _new_state()
	_add(healthy,"formation:h","paris",8000,1.0)
	_add(low_supply,"formation:s","paris",8000,1.0)
	_add(low_org,"formation:o","paris",8000,1.0)
	_add(low_eq,"formation:e","paris",8000,0.05)
	_add(low_morale,"formation:m","paris",8000,1.0)
	low_supply.get_formation("formation:s").update_supply({"food":0.1,"ammunition":0.1,"equipment":0.1,"transport_capacity":0.1},0.1,"cut")
	low_org.get_formation("formation:o").organization = 0.1
	low_morale.get_formation("formation:m").morale = 0.1
	var h := service.move(healthy,map,"formation:h","marseille",0)
	var s := service.move(low_supply,map,"formation:s","marseille",0)
	var o := service.move(low_org,map,"formation:o","marseille",0)
	var e := service.move(low_eq,map,"formation:e","marseille",0)
	var m := service.move(low_morale,map,"formation:m","marseille",0)
	var base := float(service.get_action(healthy,str(h["action_id"])).get("edge_load_total",0.0))
	for pair: Array in [[low_supply,s],[low_org,o],[low_eq,e],[low_morale,m]]:
		_check(float(service.get_action(pair[0],str((pair[1] as Dictionary)["action_id"])).get("edge_load_total",0.0)) > base, "low readiness increases bounded movement burden")
	var recovery := _new_state()
	_add(recovery,"formation:r","paris",2000,0.2)
	var f := recovery.get_formation("formation:r")
	f.organization = 0.2
	f.morale = 0.2
	f.update_supply({"food":0.0,"ammunition":0.0,"equipment":0.0,"transport_capacity":0.0},0.0,"cut")
	var old_org := f.organization
	var old_eq := f.equipment_factor()
	service.set_supply_input(recovery,map,"paris_basin",_abundant_supply())
	service.advance_to_hour(recovery,map,72)
	_check(f.organization > old_org and f.equipment_factor() > old_eq and f.formation_status == VNextMilitaryFormation.STATUS_ACTIVE, "full local supply provides recovery path")

func _test_control_concentrate_history_scope() -> void:
	var setup := _new_state()
	_check(service.setup_region_controller(setup,map,"northern_industrial_belt","country_bel","fixture"), "initial setup control mutation succeeds")
	var rec: Dictionary = setup.control_history.back() as Dictionary
	_check(rec.get("effective_hour",-1) == 0 and rec.get("context","") == "setup_fixture", "setup records cause time context")
	_add(setup,"formation:x","paris",1000,1.0)
	service.move(setup,map,"formation:x","rouen",0)
	_check(not service.setup_region_controller(setup,map,"northern_industrial_belt","country_fra","late fixture"), "setup mutation rejected after action exists")
	_check(not setup.apply_region_control_change("northern_industrial_belt","country_fra","fixture",0,"setup_fixture"), "direct setup bypass rejected")
	service.advance_to_hour(setup,map,1)
	_check(not service.setup_region_controller(setup,map,"northern_industrial_belt","country_fra","late fixture"), "setup mutation rejected after simulation starts")
	_check(not setup.apply_region_control_change("northern_industrial_belt","country_fra","strategic_attack_victory",setup.last_simulated_hour,"battle","military_action:999999"), "arbitrary battle control bypass rejected")

	var battle := _battle_state(50000,1500)
	var attack := service.attack(battle,map,"formation:attacker","lille",0)
	_finish(battle,str(attack.get("action_id","")),700)
	var control: Dictionary = battle.control_history.back() as Dictionary
	_check(control.get("cause","") == "strategic_attack_victory" and control.get("context","") == "battle", "legitimate battle victory records controlled mutation")
	_check(control.get("effective_hour",-1) == battle.last_simulated_hour and control.get("source_action_id","") == attack.get("action_id",""), "battle control records effective hour and source action")

	var conc := _new_state()
	_add(conc,"formation:c1","paris",2000,1.0)
	_add(conc,"formation:c2","rouen",2000,1.0)
	var seq := conc.next_action_sequence
	_check(not bool(service.concentrate(conc,map,["formation:c1","formation:c1"],"lyon",0).get("success",false)) and conc.active_actions.is_empty() and conc.next_action_sequence == seq, "duplicate concentrate IDs reject atomically")
	_check(not bool(service.concentrate(conc,map,["formation:c1","formation:missing"],"lyon",0).get("success",false)) and conc.active_actions.is_empty() and conc.next_action_sequence == seq, "invalid concentrate batch rejects atomically")
	_check(bool(service.concentrate(conc,map,["formation:c2","formation:c1"],"lyon",0).get("success",false)), "valid concentrate batch succeeds")
	var bounded := _new_state()
	for i: int in range(400):
		bounded.append_completed_action({"action_id":"military_action:%06d" % (i+1),"kind":"move"})
		bounded.append_battle_result({"action_id":"military_action:%06d" % (i+1)})
		bounded.append_control_history({"region_id":"paris_basin","previous_controller_id":"country_fra","controller_id":"country_bel","cause":"fixture","effective_hour":0,"context":"setup_fixture","source_action_id":""})
	_check(bounded.completed_actions.size() == 256 and bounded.battle_results.size() == 128 and bounded.control_history.size() == 256, "all histories remain bounded")
	var runtime := FileAccess.get_file_as_string("res://scripts/vnext/world_runtime.gd")
	var svc := FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
	var adapter := FileAccess.get_file_as_string("res://scripts/vnext/map/military_map_adapter.gd")
	_check(not runtime.contains("VNextMilitary"), "world_runtime remains unchanged and unintegrated")
	_check(adapter.contains("PrototypeV2Data") and not svc.contains("MilitaryManager") and not svc.contains("GlobalManager") and not svc.contains("GameContext"), "existing map reused without forbidden global architecture")

func _mutate(valid: Dictionary, kind: String) -> Dictionary:
	var s := valid.duplicate(true)
	var actions: Array = s.get("active_actions",[]) as Array
	var a: Dictionary = actions[0] as Dictionary
	match kind:
		"unknown_kind": a["kind"]="unknown"
		"empty_route": a["route"]={}
		"zero_duration": (a["route"] as Dictionary)["duration_hours"]=0
		"bad_edge": a["current_edge_index"]=999
		"bad_progress": a["progress"]=2.0
		"forward_missing":
			actions.clear()
			s["link_queues"]={}
			s["link_capacity_used"]={}
		"bogus_queue":
			var link := str(((a["route"] as Dictionary)["link_ids"] as Array)[int(a["current_edge_index"])])
			var q: Dictionary=s["link_queues"]
			if not q.has(link):
				q[link]=[]
			(q[link] as Array).append("military_action:999999")
		"wrong_queue":
			var current := str(((a["route"] as Dictionary)["link_ids"] as Array)[int(a["current_edge_index"])])
			var q: Dictionary=s["link_queues"]
			for link: Dictionary in map.get_all_links():
				var candidate:=str(link.get("id",""))
				if candidate!=current:
					q.erase(current)
					q[candidate]=[str(a["action_id"])]
					break
		"overflow":
			var link := str(((a["route"] as Dictionary)["link_ids"] as Array)[int(a["current_edge_index"])])
			(s["link_capacity_used"] as Dictionary)[link]=map.get_link_transport_capacity_per_hour(link)+1.0
		"orphan_reservation": a["reserved_link_id"]="missing_link"
		"future_start": a["edge_started_hour"]=int(s["last_simulated_hour"])+10
		"negative_elapsed": a["edge_elapsed_hours"]=-1
		"remaining_over_total": a["edge_load_remaining"]=float(a["edge_load_total"])+1.0
		"sequence": s["next_action_sequence"]=1
		"bad_origin": a["origin_city_id"]="missing_city"
		"bad_target": a["destination_city_id"]="missing_city"
	return s

func _transactionally_rejected(snapshot: Dictionary) -> bool:
	var state := _new_state()
	_add(state,"formation:sentinel","paris",1000,1.0)
	var before:=state.snapshot()
	return not state.restore(snapshot,map) and state.snapshot()==before

func _find_snapshot_action(snapshot: Dictionary, id: String) -> Dictionary:
	for raw: Variant in snapshot.get("active_actions",[]) as Array:
		if raw is Dictionary and str((raw as Dictionary).get("action_id",""))==id:
			return raw as Dictionary
	return {}

func _remote_supply_state(id: String, city: String, personnel: int) -> VNextMilitaryState:
	var s:=_new_state()
	_add(s,id,city,personnel,1.0)
	service.set_supply_input(s,map,"paris_basin",_abundant_supply())
	return s

func _abundant_supply() -> Dictionary:
	return {"food":100000.0,"ammunition":100000.0,"equipment":100000.0,"transport_capacity":100000.0}

func _find_supply(state: VNextMilitaryState, formation_id: String, resource: String) -> Dictionary:
	for shipment: Dictionary in service.get_supply_shipments(state):
		if shipment.get("destination_formation_id","")==formation_id and shipment.get("resource_id","")==resource:
			return shipment
	return {}

func _advance_supply_to_intermediate(state: VNextMilitaryState, formation_id: String, resource: String, limit: int) -> Dictionary:
	var deadline:=state.last_simulated_hour+limit
	while state.last_simulated_hour<deadline:
		if not bool(service.advance_to_hour(state,map,state.last_simulated_hour+1).get("success",false)):
			return {}
		var shipment:=_find_supply(state,formation_id,resource)
		if shipment.is_empty():
			return {}
		var route: Dictionary=shipment.get("route",{}) as Dictionary
		var edge:=int(shipment.get("current_edge_index",-1))
		if edge>0 and edge<(route.get("link_ids",[]) as Array).size():
			return shipment
	return {}

func _formation_action_id(state: VNextMilitaryState, formation_id: String) -> String:
	for raw_id: Variant in state.active_actions.keys():
		var id: String = str(raw_id)
		var a: Dictionary=state.active_actions[id] as Dictionary
		if a.get("formation_id","")==formation_id:
			return id
	return ""

func _queue_contains(state: VNextMilitaryState, id: String) -> bool:
	for q: Variant in state.link_queues.values():
		if q is Array and (q as Array).has(id):
			return true
	return false

func _contention_state() -> VNextMilitaryState:
	var s:=_new_state()
	for id: String in ["formation:r1","formation:r2","formation:r3"]:
		_add(s,id,"paris",10000,1.0)
		service.move(s,map,id,"rouen",0)
	return s

func _slicing_state() -> VNextMilitaryState:
	var s:=_new_state()
	_add(s,"formation:slice","paris",5000,1.0)
	service.set_supply_input(s,map,"paris_basin",{"food":10000.0,"ammunition":3000.0,"equipment":1000.0,"transport_capacity":2000.0})
	service.move(s,map,"formation:slice","marseille",0)
	return s

func _battle_state(attacker: int, defender: int) -> VNextMilitaryState:
	var s:=_new_state()
	service.setup_region_controller(s,map,"northern_industrial_belt","country_bel","battle fixture")
	_add(s,"formation:attacker","paris",attacker,1.0,"country_fra",0.9,0.9,0.9)
	_add(s,"formation:defender","lille",defender,1.0,"country_bel",0.8,0.8,0.8)
	service.defend(s,map,"formation:defender",0,500)
	return s

func _finish(state: VNextMilitaryState, id: String, max_hours: int) -> void:
	var deadline:=state.last_simulated_hour+max_hours
	while state.active_actions.has(id) and state.last_simulated_hour<deadline:
		if not bool(service.advance_to_hour(state,map,state.last_simulated_hour+1).get("success",false)):
			break
	_check(not state.active_actions.has(id), "action completes within bounded horizon")

func _new_state() -> VNextMilitaryState:
	var s:=VNextMilitaryState.new()
	_check(s.initialize(map),"military state initializes")
	return s

func _add(state: VNextMilitaryState,id: String,city: String,personnel: int,equipment: float,country: String="country_fra",training: float=0.8,morale: float=0.8,organization: float=0.8) -> bool:
	return service.create_formation(state,map,id,country,city,personnel,{"equipment_factor":equipment},training,morale,organization)

func _check(condition: bool,label: String) -> void:
	checks+=1
	if condition:
		print("PASS: "+label)
		return
	failures+=1
	push_error("FAIL: "+label)
