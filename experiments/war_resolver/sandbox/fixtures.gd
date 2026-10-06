extends RefCounted
## Additional observation inputs only; all behavior comes from the existing resolver.
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const NAMES: Array[String] = ["open_field_attack", "covered_defense", "village_edge",
	"road_bottleneck", "ammo_shortage", "communication_delay", "suppression_recovery",
	"cohesion_withdrawal", "dependent_reserve"]


static func create(name: String, seed: int) -> State:
	assert(name in NAMES)
	var state: State = Scenarios.create(name if name in Scenarios.NAMES else "open_field_attack", seed)
	if name == "suppression_recovery":
		state.units.attack_00.suppression = 0.9
	elif name == "cohesion_withdrawal":
		state.units.attack_00.cohesion = 0.15
	elif name == "dependent_reserve":
		state.set_coordination("attack_00", {"role": "advance", "release_time": 600.0,
			"after": ["mission_attack_01"]})
	return state
