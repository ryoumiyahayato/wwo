extends SceneTree
const F = preload("res://experiments/war_resolver/decision/fixtures.gd")
var results: Array[Dictionary] = []

func _initialize() -> void:
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		for policy: String in ["DETAILED", "AGGREGATE"]:
			var env: Dictionary = F.setup(40, 0, true, seed_value)
			assert(F.claim(env).ok and F.claim(env, "ambiguous", "platoon", "status", {"states": ["withdraw"]}, "instant", "external_division").ok)
			assert(F.opportunity(env).ok and F.opportunity(env, "company_later", "company", 300.0).ok)
			assert(env.commands.regiment.apply({"id": "attachment", "kind": "attach", "effective_time": 15.0, "values": {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0}}).ok)
			assert(env.lod.advance(90.0, policy).ok)
			assert(F.claim(env, "urgent", "company", "ammunition", {"level": "LOW"}, "delayed", "external_company", 90.0).ok)
			F.policy(env, "company", "ammo")
			assert(env.decisions.admit_urgent("company", "urgent").ok)
			assert(env.lod.advance(142.0, policy).ok)
			assert(env.supply_commands.company.submit({"id": "shipment", "kind": "allocate", "request_id": "input_urgent_company_urgent", "source_ref": "source", "delivery_time": 317.0}).ok)
			F.policy(env, "regiment", "attach")
			assert(F.opportunity(env, "structure", "regiment", 200.0).ok)
			assert(env.lod.advance(1800.0, policy).ok)
			results.append({"seed": seed_value, "policy": policy, "world": env.lod.snapshot(), "information": env.information.snapshot(),
				"decision": env.decisions.snapshot(), "structure": env.service.snapshot(), "logistics": env.logistics.snapshot()})
	print("TASK8_REPLAY_SHA256=" + JSON.stringify(results).sha256_text())
	quit(0)
