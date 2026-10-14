extends SceneTree
const Scenarios = preload("res://experiments/war_resolver/scenarios.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")


func _initialize() -> void:
	var outputs: Array[Dictionary] = []
	for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
		for name: String in Scenarios.NAMES:
			var state: RefCounted = Scenarios.create(name)
			outputs.append(Resolver.new().resolve_until(state, 3600.0, policy))
	print("REPLAY_SHA256=" + JSON.stringify(outputs).sha256_text())
	quit(0)
