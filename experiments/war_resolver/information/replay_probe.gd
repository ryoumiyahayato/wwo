extends SceneTree
const F = preload("res://experiments/war_resolver/information/fixtures.gd")
var results: Array[Dictionary] = []

func _initialize() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		for policy: String in ["DETAILED", "AGGREGATE"]:
			var env: Dictionary = F.setup(40, 0, true, seed_value)
			assert(F.observation(env).ok and F.report(env).ok)
			assert(F.external(env, "uncertain", "external_company", "status", {"states": ["hold"]}).ok)
			assert(F.report(env, "uncertain_message", "uncertain", "company", "platoon", "instant").ok)
			assert(F.command(env).ok)
			assert(F.Base.delivery(env, "ammo", "unit", "unit_000", "AMMUNITION", 10.0, 47.0).ok)
			assert(env.lod.advance(300.0, policy).ok)
			assert(F.observation(env, "current", "squad", "unit", "unit_000", "status").ok)
			assert(F.report(env, "current_message", "current", "squad", "division").ok)
			assert(env.commands.regiment.apply(F.Structure.request("attach", "attach", 317.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 733.0})).ok)
			assert(F.command(env, "invalidated").ok)
			assert(env.lod.advance(733.0, policy).ok)
			assert(env.information._messages.invalidated.status == "REJECTED")
			assert(F.external(env, "stale", "external_company", "ammunition", {"level": "AVAILABLE"}).ok)
			assert(F.report(env, "stale_message", "stale", "company", "company").ok)
			assert(env.lod.advance(1800.0, policy).ok)
			results.append({"seed": seed_value, "policy": policy, "world": env.lod.snapshot(), "information": env.information.snapshot(), "structure": env.service.snapshot(), "logistics": env.logistics.snapshot(), "role": env.roles.platoon.snapshot(), "aware_report": env.roles.division.report()})
	print("TASK7_REPLAY_SHA256=" + JSON.stringify(results).sha256_text())
	quit(0)
