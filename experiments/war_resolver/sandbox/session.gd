extends RefCounted
## Isolated orchestration/observation only. No combat formulas or display clock.
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Scenarios = preload("res://experiments/war_resolver/sandbox/fixtures.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const RoleScenarios = preload("res://experiments/war_resolver/role_scenarios.gd")
const POLICIES: Array[String] = [Resolver.DETAILED, Resolver.AGGREGATE]
const SAMPLE_SECONDS: float = 120.0
const TRACE_LIMIT: int = 160
const TRAIL_LIMIT: int = 48
const CLONE_FIELDS: Array[String] = ["time", "seed", "random_state", "units", "areas",
	"missions", "coordination", "tactical_intents", "command_coordination", "mission_dependents",
	"contacts", "area_units", "active_areas", "touched_units", "touched_areas", "totals",
	"counters", "events", "event_ids"]
var states: Dictionary = {}
var authorities: Dictionary = {}
var observations: Dictionary = {}
var command_results: Dictionary = {}
var scenario: String = "open_field_attack"
var seed: int = 71
var role: String = "ordinary_soldier"
var paused: bool = true
var _command_serial: int = 0
var _resolver: Resolver = Resolver.new()


func reset(name: String, battle_seed: int, player_role: String) -> bool:
	if name not in Scenarios.NAMES or player_role not in Roles.ROLES:
		return false
	scenario = name
	seed = battle_seed
	role = player_role
	paused = true
	_command_serial = 0
	states.clear()
	authorities.clear()
	observations.clear()
	command_results.clear()
	var initial: State = Scenarios.create(scenario, seed)
	for policy: String in POLICIES:
		var state: State = _clone(initial)
		var authority: Roles = Roles.new()
		assert(authority.configure(state, RoleScenarios.hierarchy(), RoleScenarios.people(), role))
		states[policy] = state
		authorities[policy] = authority
		var tracks: Dictionary = {}
		for id: String in State.sorted_ids(state.units):
			tracks[id] = {"trail": [float(state.units[id].position)], "last_direction": 0.0,
				"reversals": 0, "action_changes": 0, "stationary_since": 0.0}
		observations[policy] = {"trace": [], "dropped": 0, "event_counts": {}, "tracks": tracks}
	return true


static func _clone(initial: State) -> State:
	var clone: State = State.new()
	for field: String in CLONE_FIELDS:
		var value: Variant = initial.get(field)
		clone.set(field, value.duplicate(true) if value is Dictionary or value is Array else value)
	return clone


func advance_samples(count: int = 1) -> void:
	assert(count >= 1 and count <= 16)
	for sample: int in range(count):
		for policy: String in POLICIES:
			var state: State = states[policy]
			var output: Dictionary = _resolver.resolve_until(state, state.time + SAMPLE_SECONDS, policy)
			assert(output.ok)
			_record(policy, output)


func tick(count: int) -> void:
	if not paused:
		advance_samples(count)


func scope(policy: String = Resolver.DETAILED) -> Dictionary:
	return authorities[policy].command_scope()


func submit(kind: String, target: String, values: Dictionary) -> Dictionary:
	_command_serial += 1
	var command: Dictionary = RoleScenarios.command("sandbox_%04d" % _command_serial, kind, target, values)
	var results: Dictionary = {}
	for policy: String in POLICIES:
		var result: Dictionary = authorities[policy].apply(command.duplicate(true))
		results[policy] = result.duplicate(true)
		if result.ok:
			_trace(policy, result.event)
		else:
			_trace(policy, {"time": states[policy].time, "kind": "command_rejected",
				"id": command.id, "target": target, "error": result.error})
	command_results = results.duplicate(true)
	return results


func _record(policy: String, output: Dictionary) -> void:
	var observation: Dictionary = observations[policy]
	for event: Dictionary in output.events:
		var kind: String = str(event.kind)
		observation.event_counts[kind] = int(observation.event_counts.get(kind, 0)) + 1
		if kind == "action_changed":
			observation.tracks[event.unit_id].action_changes += 1
		# Loss totals are displayed separately; do not drown causal transitions in fire logs.
		if kind != "losses":
			_trace(policy, event)
	for id: String in State.sorted_ids(output.state_delta.units):
		var unit: Dictionary = output.state_delta.units[id]
		var track: Dictionary = observation.tracks[id]
		var trail: Array = track.trail
		var position: float = float(unit.position)
		var change: float = position - float(trail.back())
		if absf(change) > 0.000001:
			var direction: float = signf(change)
			if float(track.last_direction) != 0.0 and direction != float(track.last_direction):
				track.reversals += 1
			track.last_direction = direction
			track.stationary_since = float(output.state_delta.to_time)
		trail.append(position)
		if trail.size() > TRAIL_LIMIT:
			trail.pop_front()


func _trace(policy: String, event: Dictionary) -> void:
	var observation: Dictionary = observations[policy]
	observation.trace.append(event.duplicate(true))
	if observation.trace.size() > TRACE_LIMIT:
		observation.trace.pop_front()
		observation.dropped += 1


func view(policy: String) -> Dictionary:
	# Explicit bounded debug read, only on UI refresh. Rendering receives copies.
	var state: State = states[policy]
	return {"state": state.snapshot(), "observation": observations[policy].duplicate(true),
		"report": authorities[policy].report(), "scope": scope(policy),
		"command_result": command_results.get(policy, {}).duplicate(true)}
