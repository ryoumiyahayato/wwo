extends SceneTree
const F = preload("res://experiments/war_resolver/logistics/fixtures.gd")
const Base = preload("res://experiments/war_resolver/structure/fixtures.gd")
var results: Array[Dictionary] = []

func _initialize() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		for mode: String in ["DETAILED", "AGGREGATE"]:
			var env: Dictionary = F.setup(40, 0, true, true, 0.25, 0.75, 400.0, seed_value)
			assert(F.delivery(env, "formation_ammo", "formation", "blue_company", "AMMUNITION", 500.0, 317.0).ok)
			assert(F.delivery(env, "leaf_fuel", "unit", "unit_000", "FUEL", 1.0, 317.0).ok)
			assert(F.repair(env, "repairs", "formation", "blue_company", 2.0, 317.0).ok)
			assert(env.commands.regiment.apply(Base.request("attach", "attach", 317.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 733.0})).ok)
			assert(env.lod.advance(600.0, mode).ok)
			assert(env.lod.advance(733.0, mode).ok)
			assert(env.commands.company.apply(F.split(env)).ok)
			assert(env.lod.advance(733.0, mode).ok and env.service.history[-1].outcome.ok)
			assert(F.delivery(env, "donor_delivery", "unit", "detachment", "SPARES", 1.0, 900.0).ok)
			assert(env.commands.company.apply(Base.request("merge", "merge", 733.0, {"survivor": "unit_000", "donor": "detachment"})).ok)
			assert(env.lod.advance(733.0, mode).ok and env.service.history[-1].outcome.ok)
			assert(env.lod.advance(1800.0, mode).ok)
			assert(env.logistics._deliveries.donor_delivery.status == "REJECTED_RETURNED")
			results.append({"seed": seed_value, "mode": mode, "lod": env.lod.snapshot(), "structure": env.service.snapshot(), "logistics": env.logistics.snapshot(), "audit": env.logistics.audit(), "spatial": env.lod.spatial.view("region_50")})
	print("TASK6_REPLAY_SHA256=" + JSON.stringify(results).sha256_text())
	quit(0)
