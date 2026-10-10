extends "res://experiments/war_resolver/gameplay/scenario.gd"
const LiveProvider = preload("res://experiments/war_resolver/interactive_observer/input_provider.gd")
var bound_actor: String = ""
var provider: LiveProvider = LiveProvider.new()
var selected_script_disabled: bool = false

func configure_bound(scene: String, seed_value: int, actor: String, options: Dictionary = {}) -> bool:
	var allowed: Dictionary = {"S1": ["squad", "company"], "S2": ["platoon"], "S3": ["soldier"]}
	if actor not in allowed.get(scene, []):
		return false
	bound_actor = actor
	var supplied: Dictionary = {"variant": "condition" if options.get("bridge_clear", false) else "autonomous", "sleeping_areas": options.get("sleeping_areas", 0)}
	if options.get("bridge_clear", false) and scene != "S2":
		return false
	if not configure(scene, seed_value, supplied) or not selected_script_disabled:
		return false
	env.gameplay.participants.debug_calculations = bool(options.get("diagnostic", false))
	if not options.get("diagnostic", false):
		env.lod.physical_event_sink = Callable()
	var cadence: float = float(F.F.Roles.INPUT_SECONDS[F.F.Roles.ROLES.find(str(env.people[actor].role))])
	return env.decisions.enroll(actor, {"cadence": cadence, "targets": ["node_unit_000", "node_unit_001", "blue_platoon", "blue_destination", "blue_company"],
		"urgent": false, "command_kind": "goal_intent", "standing_orders": {}}, provider)

func _enroll(actor: String, entries: Array) -> bool:
	if actor == bound_actor:
		selected_script_disabled = true
		return true
	return super._enroll(actor, entries)
