extends SceneTree
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Data = preload("res://experiments/war_resolver/data.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
var checks: int = 0
var failures: int = 0
var resolver: Resolver = Resolver.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_replay()
	_conservation()
	_idle_scaling()
	_partition_and_resolution()
	_terrain_ammunition_suppression()
	_order_symmetry()
	_boundaries_and_coordination()
	_frontage_and_sleep()
	_sleeping_reserves_and_observation()
	_simultaneous_arrivals()
	print("War resolver: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _replay() -> void:
	for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
		for name: String in Scenarios.NAMES:
			var a: State = Scenarios.create(name)
			var b: State = Scenarios.create(name)
			var left: Dictionary = resolver.resolve_until(a, 3600.0, policy)
			var right: Dictionary = resolver.resolve_until(b, 3600.0, policy)
			_check(left == right and a.snapshot() == b.snapshot(), name + " exact replay " + policy)
	var state: State = Scenarios.create()
	var snapshot: Dictionary = state.snapshot()
	_check(not resolver.resolve_until(state, -1.0).ok, "reject past horizon")
	_check(not resolver.resolve_until(state, 1.0, "unknown").ok, "reject unknown resolution")
	_check(snapshot == state.snapshot(), "rejected call leaves state unchanged")


func _resources(state: State, label: String) -> void:
	var personnel: float = 0.0
	var ammunition: float = 0.0
	var equipment: float = 0.0
	for id: String in State.sorted_ids(state.units):
		var unit: Dictionary = state.units[id]
		_check(float(unit.effective) >= 0.0 and float(unit.ammunition) >= 0.0 and float(unit.equipment) >= 0.0, label + " nonnegative " + id)
		_check(is_equal_approx(float(unit.effective) + float(unit.casualties), float(unit.personnel_total)), label + " personnel " + id)
		_check(float(unit.suppression) >= 0.0 and float(unit.suppression) <= 1.0 and float(unit.cohesion) >= 0.0 and float(unit.fatigue) <= 1.0, label + " bounded condition " + id)
		personnel += float(unit.effective) + float(unit.casualties)
		ammunition += float(unit.ammunition) + float(unit.ammo_spent)
		equipment += float(unit.equipment) + float(unit.equipment_lost)
	_check(is_equal_approx(personnel, float(state.totals.personnel)), label + " ledger personnel")
	_check(is_equal_approx(ammunition, float(state.totals.ammunition)), label + " ledger ammunition")
	_check(is_equal_approx(equipment, float(state.totals.equipment)), label + " ledger equipment")


func _conservation() -> void:
	for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
		for name: String in Scenarios.NAMES:
			var state: State = Scenarios.create(name)
			resolver.resolve_until(state, 7200.0, policy)
			_resources(state, name + policy)
	var state: State = Scenarios.create()
	state.units.attack_00.effective = 0.0
	state.units.attack_00.casualties = 12.0
	state.totals.casualties = 12.0
	state.units.attack_01.equipment = 0.0
	state.units.attack_01.equipment_lost = 12.0
	state.totals.equipment_lost = 12.0
	resolver.resolve_until(state, 7200.0)
	_check(state.units.attack_00.ammo_spent == 0.0 and state.units.attack_01.ammo_spent == 0.0, "disabled or unequipped cannot fire")
	_resources(state, "disabled equipment")


func _idle_scaling() -> void:
	var small: State = Scenarios.create()
	var large: State = Scenarios.create("open_field_attack", 71, 10000)
	var a: Dictionary = resolver.resolve_until(small, 3600.0)
	var b: Dictionary = resolver.resolve_until(large, 3600.0)
	_check(a.counters == b.counters, "10000 sleeping areas / 30000 idle units add zero resolver operations")
	_check(a.summary.units == b.summary.units and a.summary.control == b.summary.control, "idle population cannot affect active battle")
	_check(b.counters.units_examined <= b.counters.areas_examined * 400 and b.counters.units_examined >= b.counters.areas_examined * 10, "instrumented unit visits stay bounded by ten indexed active units")
	var idle: State = State.new()
	idle.add_area(Data.area("idle"))
	idle.add_mission(Data.mission("sleep", "idle"))
	idle.add_unit(Data.unit("idle_squad", "blue", "idle", "sleep"))
	var result: Dictionary = resolver.resolve_until(idle, 86400.0)
	_check(result.counters == {"areas_examined": 0, "units_examined": 0, "contacts_resolved": 0, "events_processed": 0, "segments": 0}, "idle day is a direct time jump")
	var previously_active: State = Scenarios.create("open_field_attack", 71, 1000)
	for area_id: String in State.sorted_ids(previously_active.areas):
		previously_active.wake(area_id)
	resolver.resolve_until(previously_active, 30.0)
	var resumed: Dictionary = resolver.resolve_until(previously_active, 60.0)
	_check(resumed.counters.areas_examined == 1 and resumed.summary.units.size() == 10 and resumed.summary.control.size() == 1, "previously active sleeping regions add no resolver or output scan")


func _compare(a: State, b: State, label: String, tolerance: float) -> void:
	_check(a.time == b.time, label + " single world clock")
	for id: String in State.sorted_ids(a.units):
		var left: Dictionary = a.units[id]
		var right: Dictionary = b.units[id]
		for key: String in ["casualties", "ammo_spent"]:
			var scale: float = maxf(1.0, float(left[key]))
			_check(absf(float(left[key]) - float(right[key])) <= scale * tolerance, label + " bounded " + key + " " + id)
		_check(absf(float(left.position) - float(right.position)) <= 0.20, label + " main movement " + id)
		_check(a.missions[left.mission_id].status == b.missions[right.mission_id].status, label + " mission " + id)
	_check(a.areas.field.control == b.areas.field.control, label + " control direction")
	_check(is_equal_approx(float(a.totals.personnel), float(b.totals.personnel)), label + " initial resources")


func _partition_and_resolution() -> void:
	for name: String in Scenarios.NAMES:
		for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
			var full: State = Scenarios.create(name)
			var chunks: State = Scenarios.create(name)
			resolver.resolve_until(full, 3600.0, policy)
			for target: int in [600, 1200, 1800, 2400, 3000, 3600]:
				resolver.resolve_until(chunks, float(target), policy)
			_compare(full, chunks, name + " partition " + policy, 0.01)
		var detailed: State = Scenarios.create(name)
		var aggregate: State = Scenarios.create(name)
		resolver.resolve_until(detailed, 3600.0, Resolver.DETAILED)
		resolver.resolve_until(aggregate, 3600.0, Resolver.AGGREGATE)
		_compare(detailed, aggregate, name + " resolution", 0.20)
		_check(float(detailed.totals.casualties) > 0.0 and float(aggregate.totals.casualties) > 0.0, name + " both modes resolve real contact")
		_check(int(aggregate.counters.segments) < int(detailed.counters.segments), name + " aggregate requires fewer segments")
	# Caller boundaries off the accuracy lattice must also preserve direction/ranges.
	var a: State = Scenarios.create()
	var b: State = Scenarios.create()
	resolver.resolve_until(a, 3600.0)
	for target: float in [317.0, 911.0, 1703.0, 2411.0, 3007.0, 3600.0]:
		resolver.resolve_until(b, target)
	_compare(a, b, "off-grid partition", 0.02)


func _terrain_ammunition_suppression() -> void:
	for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
		var open: State = Scenarios.create()
		var cover: State = Scenarios.create("covered_defense")
		var low: State = Scenarios.create("ammo_shortage")
		resolver.resolve_until(open, 3600.0, policy)
		resolver.resolve_until(cover, 3600.0, policy)
		resolver.resolve_until(low, 3600.0, policy)
		_check(float(cover.units.defend_00.casualties) < float(open.units.defend_00.casualties), policy + " cover reduces defensive casualties")
		_check(float(low.units.defend_00.casualties) < float(open.units.defend_00.casualties) * 0.1, policy + " scarce ammo limits inflicted casualties")
		_check(low.units.attack_00.ammunition == 0.0 and float(low.units.attack_00.ammo_spent) <= 3.0, policy + " cannot invent ammunition")
		var clear: State = Scenarios.create()
		var suppressed: State = Scenarios.create()
		for index: int in range(6):
			suppressed.units["attack_%02d" % index].suppression = 0.95
		resolver.resolve_until(clear, 30.0, policy)
		resolver.resolve_until(suppressed, 30.0, policy)
		_check(suppressed.units.attack_00.position == 0.5 and float(clear.units.attack_00.position) > 0.5, policy + " suppression stalls exposed advance")
		_check(suppressed.units.attack_00.action == "stalled", policy + " trace explains suppression stall")


func _order_symmetry() -> void:
	for seed_value: int in [1, 17, 71, 999]:
		for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
			var a: State = Scenarios.create("open_field_attack", seed_value)
			var b: State = Scenarios.create("open_field_attack", seed_value, 0, true)
			var left: Dictionary = resolver.resolve_until(a, 3600.0, policy)
			var right: Dictionary = resolver.resolve_until(b, 3600.0, policy)
			_check(left == right, "permuted insertion exact result " + policy)
			var mirrored: State = Scenarios.create("open_field_attack", seed_value)
			for id: String in State.sorted_ids(mirrored.units):
				var unit: Dictionary = mirrored.units[id]
				unit.side = "first_faction" if unit.side == "red" else "last_faction"
			resolver.resolve_until(mirrored, 3600.0, policy)
			for id: String in State.sorted_ids(a.units):
				for key: String in ["casualties", "ammunition", "position", "suppression"]:
					_check(a.units[id][key] == mirrored.units[id][key], "faction label permutation " + key)
	# Mirror geometry and attack direction, preserving entity IDs and capability.
	var a: State = Scenarios.create()
	var mirror: State = Scenarios.create()
	for id: String in State.sorted_ids(mirror.units):
		mirror.units[id].position = 5.0 - float(mirror.units[id].position)
		var mission: Dictionary = mirror.missions[mirror.units[id].mission_id]
		mission.objective = 5.0 - float(mission.objective)
		mission.direction = -float(mission.direction)
	resolver.resolve_until(a, 3600.0)
	resolver.resolve_until(mirror, 3600.0)
	for id: String in State.sorted_ids(a.units):
		_check(is_equal_approx(float(a.units[id].casualties), float(mirror.units[id].casualties)), "geometric mirror losses " + id)
		_check(is_equal_approx(float(a.units[id].position), 5.0 - float(mirror.units[id].position)), "geometric mirror movement " + id)


func _boundaries_and_coordination() -> void:
	var state: State = State.new()
	state.add_area(Data.area("origin"))
	state.add_area(Data.area("destination"))
	state.areas.origin.links.destination = true
	state.add_mission(Data.mission("idle", "idle"))
	var move: Dictionary = Data.mission("move", "advance", 1.0, 0.1)
	move.destination = "destination"
	state.add_mission(move)
	state.add_mission(Data.mission("following", "advance", 1.0, 1.0))
	state.add_unit(Data.unit("leader", "blue", "origin", "idle"))
	state.add_unit(Data.unit("reserve", "blue", "origin", "following"))
	state.set_coordination("reserve", {"after": ["move"], "role": "advance", "support": "leader"})
	_check(state.schedule_event("z_order", 17.0, "order", {"unit_id": "leader", "mission_id": "move"}), "schedule off-grid order")
	_check(not state.schedule_event("z_order", 18.0, "order", {"unit_id": "leader", "mission_id": "move"}), "reject duplicate event id")
	_check(state.schedule_event("a_reinforcement", 17.0, "reinforcement", {"unit": Data.unit("new_squad", "blue", "origin", "idle")}), "schedule reinforcement")
	_check(state.schedule_event("terrain", 21.0, "area_change", {"area_id": "origin", "movement_modifier": 0.5}), "schedule terrain boundary")
	var before: Dictionary = resolver.resolve_until(state, 16.0)
	_check(state.units.leader.position == 0.0 and state.units.reserve.position == 0.0, "pending order and dependency cannot act early")
	_check(before.counters.events_processed == 0, "future events not processed")
	var at_boundary: Dictionary = resolver.resolve_until(state, 17.0)
	var external_events: Array[String] = []
	for event: Dictionary in at_boundary.events:
		if event.kind in ["reinforcement", "order"]:
			external_events.append(str(event.id))
	_check(external_events == ["a_reinforcement", "z_order"], "same-time event ordering uses stable id")
	_check(state.units.leader.position == 0.0 and state.units.leader.mission_id == "move", "order applies exactly at boundary, no retroactive motion")
	var result: Dictionary = resolver.resolve_until(state, 600.0)
	_check(state.units.leader.area_id == "destination" and state.missions.move.status == "complete", "movement stops at objective and crosses explicit link")
	_check(float(state.units.reserve.position) > 0.0 and state.coordination.reserve.status == "assigned", "mission completion releases coordinated reserve")
	_check(result.state_delta.areas.has("destination") and result.state_delta.missions.has("move"), "delta includes authority-neutral area and mission changes")
	_check(state.counters.events_processed == 3, "exact external events processed")
	_resources(state, "reinforcement")
	var heap: State = State.new()
	heap.add_area(Data.area("a"))
	for index: int in range(100):
		_check(heap.schedule_event("e%03d" % index, float(100 - index), "area_change", {"area_id": "a"}), "heap schedule")
	var previous: float = -1.0
	for index: int in range(100):
		var event: Dictionary = heap.pop_event()
		_check(float(event.time) > previous, "heap ordered pop")
		previous = float(event.time)


func _frontage_and_sleep() -> void:
	var wide: State = Scenarios.create()
	var narrow: State = Scenarios.create("road_bottleneck")
	resolver.resolve_until(wide, 600.0)
	resolver.resolve_until(narrow, 600.0)
	_check(float(narrow.totals.ammo_spent) < float(wide.totals.ammo_spent), "frontage limits usable fire")
	_check(float(narrow.units.attack_00.position) < float(wide.units.attack_00.position), "bottleneck constrains movement")
	var lonely: State = State.new()
	lonely.add_area(Data.area("field"))
	lonely.add_mission(Data.mission("hold"))
	lonely.add_unit(Data.unit("squad", "blue", "field", "hold"))
	resolver.resolve_until(lonely, 30.0)
	var after: Dictionary = resolver.resolve_until(lonely, 86400.0)
	_check(after.counters.areas_examined == 0 and after.counters.units_examined == 0, "quiet hold area sleeps after evaluation")
	_check(lonely.areas.field.control == "blue" and after.summary.control.is_empty(), "unopposed control retained without an idle output scan")


func _sleeping_reserves_and_observation() -> void:
	var state: State = State.new()
	state.add_area(Data.area("field"))
	state.add_mission(Data.mission("reserve", "advance", 1.0, 1.0))
	state.add_unit(Data.unit("reserve_squad", "blue", "field", "reserve"))
	state.set_coordination("reserve_squad", {"release_time": 3600.0, "role": "advance"})
	resolver.resolve_until(state, 30.0)
	var idle: Dictionary = resolver.resolve_until(state, 3599.0)
	_check(idle.counters.areas_examined == 0 and idle.counters.units_examined == 0 and idle.counters.events_processed == 0, "reserve sleeps until scheduled release")
	var release: Dictionary = resolver.resolve_until(state, 3600.0)
	_check(release.counters.events_processed == 1 and state.units.reserve_squad.position == 0.0, "reserve release is exact-time event")
	resolver.resolve_until(state, 3660.0)
	_check(float(state.units.reserve_squad.position) > 0.0, "release wakes reserve area")
	var snapshot: Dictionary = state.snapshot()
	resolver.summary(state, Resolver.DETAILED)
	resolver.summary(state, Resolver.AGGREGATE)
	_check(snapshot == state.snapshot(), "observation summaries do not alter war rules/state/randomness")
	var no_visibility: State = Scenarios.create()
	no_visibility.areas.field.visibility = 0.0
	resolver.resolve_until(no_visibility, 600.0)
	_check(no_visibility.totals.casualties == 0.0 and no_visibility.totals.ammo_spent == 0.0, "detection constrains fire, no invented effective contacts")
	var withdrawal: State = State.new()
	withdrawal.add_area(Data.area("field"))
	withdrawal.add_mission(Data.mission("advance", "advance"))
	var unit: Dictionary = Data.unit("squad", "blue", "field", "advance", 0.1)
	unit.cohesion = 0.1
	withdrawal.add_unit(unit)
	resolver.resolve_until(withdrawal, 600.0)
	_check(withdrawal.missions.advance.status == "withdrawn" and withdrawal.units.squad.position == 0.0, "cohesion loss triggers bounded withdrawal")
	var after: Dictionary = resolver.resolve_until(withdrawal, 86400.0)
	_check(after.counters.areas_examined == 0, "completed withdrawal stops ongoing work")


func _simultaneous_arrivals() -> void:
	var state: State = State.new()
	state.add_area(Data.area("destination"))
	for source: String in ["a_source", "z_source"]:
		state.add_area(Data.area(source))
		state.areas[source].links.destination = true
		# Reach on the first accuracy boundary, before fatigue changes the speed.
		var mission: Dictionary = Data.mission("move_" + source, "advance", 1.0, 0.04)
		mission.destination = "destination"
		state.add_mission(mission)
		state.add_unit(Data.unit(source, "blue" if source == "a_source" else "red", source, mission.id))
	var result: Dictionary = resolver.resolve_until(state, 30.0)
	_check(state.units.a_source.area_id == "destination" and state.units.z_source.area_id == "destination", "simultaneous opposing arrivals at exact boundary")
	_check(state.areas.destination.control == "contested", "simultaneous arrival control uses both sides")
	var claims: int = 0
	for event: Dictionary in result.events:
		if event.kind == "control_changed" and event.area_id == "destination":
			claims += 1
			_check(event.control == "contested", "no transient faction-first claim on simultaneous arrival")
	_check(claims == 1, "single final control event per arrival boundary")
