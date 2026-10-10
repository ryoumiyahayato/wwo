extends SceneTree
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")
var checks: int = 0
var failures: int = 0
var evidence: Array[Dictionary] = []

func _initialize() -> void:
	_remote_enemy()
	_arrival_is_not_control()
	_withdrawal()
	_dependency_failure()
	_cancel_and_permission()
	_quota()
	print("GAMEPLAY_G1_RESULTS=" + JSON.stringify(evidence))
	print("Gameplay G1: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _remote_enemy() -> void:
	var env: Dictionary = F.setup(71, {"range_km": 0.0})
	var records: Array[Dictionary] = []
	env.gameplay.transition.connect(func(record: Dictionary) -> void: records.append(record))
	check(env.gameplay.admit_standing("unit_000", "guard", "squad", F.intent("hold", "A")).ok, "standing guard admitted")
	check(F.advance(env, 60.0).ok, "autonomous guard runs")
	var mission: Dictionary = F.current(env)
	check(mission.status == "complete" and mission.goal_v1.local_condition, "local objective holds despite distant enemy")
	check(env.state.areas.field.control == "contested" and float(env.state.units.unit_002.effective) == 12.0, "whole cell remains contested with actual distant enemy")
	check(mission.goal_v1.route_complete, "arrival is a separate fact")
	check(F.advance(env, 1800.0).ok and float(env.state.units.unit_000.distance_moved) == 0.0, "completed guard does not repeat movement")
	var completed: int = 0
	for record: Dictionary in records:
		completed += int(record.kind == "goal_complete")
	check(completed == 1, "completion occurs once")
	evidence.append({"case": "local_goal_remote_enemy", "mission": mission.duplicate(true), "area_control": env.state.areas.field.control})

func _arrival_is_not_control() -> void:
	var env: Dictionary = F.setup(109, {"range_km": 0.0, "red_point": "B"})
	check(env.gameplay.admit_standing("unit_000", "advance", "squad", F.intent("advance", "B", ["AB"])).ok, "known route admitted")
	check(F.advance(env, 500.0).ok, "route executes autonomously")
	var mission: Dictionary = F.current(env)
	check(mission.status == "complete" and mission.goal_v1.route_complete, "advance task completes on arrival")
	check(not mission.goal_v1.local_condition, "arrival at occupied point is not local control")
	var distance: float = float(env.state.units.unit_000.distance_moved)
	check(F.advance(env, 1800.0).ok and float(env.state.units.unit_000.distance_moved) == distance, "arrival cannot restart the same path")
	evidence.append({"case": "arrival_not_control", "mission": mission.duplicate(true), "distance_km": distance})

func _withdrawal() -> void:
	var near: Dictionary = F.setup(71, {"blue_point": "B", "red_ammunition": 2000.0})
	check(near.gameplay.admit_standing("unit_000", "short_withdraw", "squad", F.intent("withdraw", "A", ["AB"])).ok, "short withdrawal admitted")
	check(F.advance(near, 180.0).ok and F.current(near).status == "complete", "withdrawal route can finish under enemy fire")
	var before: float = float(near.state.units.unit_000.casualties)
	check(before > 0.0 and F.current(near).goal_v1.effective_incoming_contact, "arrived withdrawal remains in effective contact")
	check(F.advance(near, 300.0).ok and float(near.state.units.unit_000.casualties) > before, "finished withdrawal grants no immunity")
	check(float(near.state.units.unit_000.ammo_spent) > 0.0, "standing hold after withdrawal can fire")
	var far: Dictionary = F.setup(71, {"blue_point": "B", "red_ammunition": 2000.0})
	check(far.gameplay.admit_standing("unit_000", "far_withdraw", "squad", F.intent("withdraw", "C", ["AB", "AC"])).ok, "far withdrawal admitted")
	check(F.advance(far, 900.0).ok and F.current(far).status == "complete", "far withdrawal reaches known safe node")
	var lost: float = float(far.state.units.unit_000.casualties)
	check(not F.current(far).goal_v1.effective_incoming_contact, "true physical disengagement differs from route completion")
	check(F.advance(far, 1800.0).ok and float(far.state.units.unit_000.casualties) == lost, "stale contact causes no later loss while other units remain active")
	evidence.append({"case": "withdraw_contact", "near_loss": near.state.units.unit_000.casualties, "far_loss": lost, "far_goal": F.current(far).duplicate(true)})

func _dependency_failure() -> void:
	var env: Dictionary = F.setup(109, {"range_km": 0.0, "rules": {"deadline_seconds": 60.0}})
	check(env.gameplay.admit_standing("unit_000", "unreachable_in_time", "squad", F.intent("advance", "D", ["AB", "bridge_BD"])).ok, "finite deadline goal admitted")
	var prerequisite: String = str(env.state.units.unit_000.mission_id)
	env.state.set_coordination("unit_001", {"after": [prerequisite], "release_time": 0.0, "role": "advance"})
	check(env.gameplay.admit_standing("unit_001", "dependent", "platoon", F.intent("advance", "D", ["AB", "bridge_BD"])).ok, "dependent admitted with explicit clock")
	check(F.advance(env, 1800.0).ok, "failed dependency world continues")
	check(F.current(env).status == "failed" and F.current(env).goal_v1.terminal_reason == "deadline_exceeded", "task fails for actual unmet deadline")
	check(F.current(env, "unit_001").status == "failed" and F.current(env, "unit_001").goal_v1.terminal_reason == "dependency_failed", "failed prerequisite does not leave permanent reserve")
	check(env.state.units.unit_001.action == "hold" and float(env.state.units.unit_001.distance_moved) == 0.0, "dependent failure has explicit standing fallback")
	evidence.append({"case": "failed_dependency", "prerequisite": F.current(env).duplicate(true), "dependent": F.current(env, "unit_001").duplicate(true)})

func _cancel_and_permission() -> void:
	var env: Dictionary = F.setup(71, {"range_km": 0.0})
	check(env.gameplay.admit_standing("unit_000", "initial", "squad", F.intent("advance", "D", ["AB", "bridge_BD"])).ok, "standing move admitted")
	var denied: Dictionary = env.information.issue_command("soldier", {"id": "bad_goal", "channel_ref": "command", "command": {"id": "bad_goal", "kind": "goal_intent", "target": "node_unit_000", "values": F.intent("withdraw", "A")}})
	check(not denied.ok and not env.state.event_ids.has("communication_bad_goal"), "ordinary person cannot command the squad")
	check(env.information.issue_command("squad", {"id": "cancel", "channel_ref": "command", "command": {"id": "cancel", "kind": "goal_intent", "target": "node_unit_000", "values": F.intent("cancel", "")}}).ok, "legal cancellation issued through real communication")
	check(F.advance(env, 15.0).ok and F.current(env).status == "cancelled", "cancel only takes effect on delivery")
	var stopped: float = float(env.state.units.unit_000.distance_moved)
	check(stopped > 0.0 and stopped < 0.12, "cancellation preserves actual partial travel")
	check(F.advance(env, 1800.0).ok and float(env.state.units.unit_000.distance_moved) == stopped, "cancelled task does not auto-restart")
	evidence.append({"case": "cancel", "distance_km": stopped, "status": F.current(env).status})

func _quota() -> void:
	var reference: Dictionary = {}
	for quota: int in [0, 1, 7, 31]:
		var env: Dictionary = F.setup(71)
		check(env.gameplay.admit_standing("unit_000", "same", "squad", F.intent("withdraw", "C", ["AC"])).ok, "quota goal admitted")
		check(F.advance(env, 1800.0, quota).ok, "quota completes")
		var result: Dictionary = {"units": env.state.units.duplicate(true), "missions": env.state.missions.duplicate(true), "totals": env.state.totals.duplicate(), "knowledge": env.information._knowledge.duplicate(true), "messages": env.information._messages.duplicate(true)}
		if quota == 0:
			reference = result
		else:
			check(result == reference, "same behavior normal/quota exact public results")
		check(env.state.time == 1800.0 and not env.state.settlement_pending, "one committed clock")
