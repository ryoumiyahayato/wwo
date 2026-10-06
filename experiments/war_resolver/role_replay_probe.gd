extends SceneTree
const Resolver = preload("res://experiments/war_resolver/resolver.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const Fixtures = preload("res://experiments/war_resolver/role_scenarios.gd")
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")


func _initialize() -> void:
	var outputs: Array[Dictionary] = []
	for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
		for role: String in Roles.ROLES:
			var fixture: Dictionary = Fixtures.scripted(role, policy)
			assert(fixture.command.ok)
			outputs.append({"command": fixture.command, "result": Resolver.new().resolve_until(fixture.state, 3600.0, policy),
				"adapter": fixture.service.snapshot(), "report": fixture.service.report()})
		for role: String in Roles.ROLES.slice(2):
			var state: RefCounted = Scenarios.create()
			var service: RefCounted = Roles.new()
			assert(service.configure(state, Fixtures.hierarchy(), Fixtures.people(), role))
			var targets: Dictionary = {"platoon_leader": "squad_attack_00", "company_commander": "platoon_blue00",
				"battalion_commander": "company_blue0", "regiment_commander": "battalion_blue", "division_commander": "regiment_blue"}
			var command: Dictionary = service.apply(Fixtures.command("reserve", "coordination", targets[role], {"posture": "advance", "release_after": 317.0}))
			assert(command.ok)
			var invalid: Dictionary = service.apply(Fixtures.command("micro", "local_action", role, {"action": "step_forward"}))
			assert(not invalid.ok)
			outputs.append({"command": command, "rejected": invalid, "result": Resolver.new().resolve_until(state, 3600.0, policy),
				"adapter": service.snapshot(), "report": service.report()})
	print("ROLE_REPLAY_SHA256=" + JSON.stringify(outputs).sha256_text())
	quit(0)
