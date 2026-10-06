extends SceneTree
## Machine observation, not rendered/human visual acceptance or a benchmark.
const Session = preload("res://experiments/war_resolver/sandbox/session.gd")
const Scenarios = preload("res://experiments/war_resolver/sandbox/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
var records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for seed: int in [7, 71, 733]:
		for name: String in Scenarios.NAMES:
			var session: Session = Session.new()
			session.reset(name, seed, "ordinary_soldier")
			for sample: int in range(60):
				session.advance_samples()
			for policy: String in Session.POLICIES:
				var state: State = session.states[policy]
				var units: Dictionary = {}
				for id: String in State.sorted_ids(state.units):
					var unit: Dictionary = state.units[id]
					var track: Dictionary = session.observations[policy].tracks[id]
					units[id] = {"position": unit.position, "distance_moved": unit.distance_moved,
						"casualties": unit.casualties, "suppression": unit.suppression,
						"action": unit.action, "mission": state.missions[unit.mission_id],
						"sampled_reversals": track.reversals, "action_changes": track.action_changes,
						"stationary_seconds": state.time - float(track.stationary_since)}
				var record: Dictionary = {"scenario": name, "seed": seed, "policy": policy,
					"time": state.time, "units": units, "totals": state.totals,
					"control": state.areas.field.control, "event_counts": session.observations[policy].event_counts,
					"trace": session.observations[policy].trace}
				records.append(record.duplicate(true))
	# Also exercise all roles through scope-based commands, with rejected early input.
	for role: String in Roles.ROLES:
		var session: Session = Session.new()
		session.reset("open_field_attack", 71, role)
		var scope: Dictionary = session.scope()
		var kind: String = str(scope.targets.keys()[0])
		var target: String = str(scope.targets[kind][0])
		var values: Dictionary = {"action": "take_cover"} if kind == "local_action" else {"posture": "support"}
		if kind == "mission":
			values = {"posture": "advance", "objective": 1.75, "direction": 1.0}
		session.submit(kind, target, values)
		session.submit(kind, target, values)
		for sample: int in range(30):
			session.advance_samples()
		for policy: String in Session.POLICIES:
			records.append({"role": role, "policy": policy, "view": session.view(policy)})
	var encoded: String = JSON.stringify(records, "", true, true)
	print("SANDBOX_OBSERVATIONS_JSON=" + encoded)
	print("SANDBOX_REPLAY_SHA256=" + encoded.sha256_text())
	quit(0)
