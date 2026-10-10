extends SceneTree
const Scenario = preload("res://experiments/war_resolver/gameplay/scenario.gd")
var checks: int = 0
var failures: int = 0
var rows: Array[Dictionary] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	for name: String in ["S1", "S2", "S3"]:
		for seed_value: int in [71, 109]:
			var reference: Dictionary = {}
			for quota: int in [0, 1, 7, 31]:
				var scenario: Scenario = Scenario.new()
				check(scenario.configure(name, seed_value, {"variant": "valid"}), "new long scenario admitted")
				check(scenario.advance(86400.0, quota).ok and scenario.env.state.time == 86400.0, "new slice continues on the same world clock for 24h")
				check(scenario.balanced(), "24h resources and member capacity stay conserved")
				var physical: Dictionary = scenario.physical()
				for key: String in ["world_counters", "gameplay_work", "personal_work"]:
					physical.erase(key)
				if quota == 0:
					reference = physical
				else:
					check(physical == reference, "new 24h normal/quota formal results exact")
				var metadata: Dictionary = {"scene": name, "seed": seed_value, "quota": quota, "time": physical.time,
					"pending": scenario.env.state.events.size(), "world_counters": scenario.env.state.counters.duplicate(),
					"goal_work": scenario.env.gameplay.work.duplicate(), "person_work": scenario.env.gameplay.participants.work.duplicate(),
					"trace_records": scenario.observation.debug_records.size(), "trace_dropped": scenario.observation.dropped,
					"mission_count": scenario.env.state.missions.size(), "message_count": scenario.env.information._messages.size(),
					"active_areas": scenario.env.state.active_areas.size(), "remote_groups": scenario.env.lod._groups.size()}
				rows.append(metadata)
				scenario.dispose()
	print("GAMEPLAY_LONG=" + JSON.stringify(rows))
	print("Gameplay 24h: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
