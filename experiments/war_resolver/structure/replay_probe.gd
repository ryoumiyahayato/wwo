extends SceneTree
const F = preload("res://experiments/war_resolver/structure/fixtures.gd")
var result: Array[Dictionary] = []

func _initialize() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		for mode: String in ["DETAILED", "AGGREGATE"]:
			var env: Dictionary = F.setup(40, 0, true, seed_value)
			assert(env.commands.regiment.apply(F.request("attach", "attach", 317.0,
				{"target": "node_unit_000", "parent": "blue_destination", "until": 733.0})).ok)
			assert(env.lod.advance(600.0, mode).ok)
			assert(env.lod.advance(733.0, mode).ok)
			assert(env.commands.regiment.apply(F.split_request(env)).ok)
			assert(env.lod.advance(733.0, mode).ok and env.service.history[-1].outcome.ok)
			assert(env.commands.regiment.apply(F.request("merge", "merge", 733.0,
				{"survivor": "unit_000", "donor": "detachment"})).ok)
			assert(env.lod.advance(733.0, mode).ok and env.service.history[-1].outcome.ok)
			assert(env.lod.advance(1800.0, mode).ok)
			result.append({"seed": seed_value, "mode": mode, "lod": env.lod.snapshot(),
				"structure": env.service.snapshot(), "spatial": env.lod.spatial.view("region_50"),
				"roles": env.roles.regiment.snapshot(), "work": env.service.work.duplicate()})
	print("TASK5_REPLAY_SHA256=" + JSON.stringify(result).sha256_text())
	quit(0)
