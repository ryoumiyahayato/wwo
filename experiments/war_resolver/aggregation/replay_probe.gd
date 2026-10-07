extends SceneTree
const Fixtures = preload("res://experiments/war_resolver/aggregation/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const Authority = preload("res://experiments/war_resolver/aggregation/authority.gd")
const Resolver = preload("res://experiments/war_resolver/resolver.gd")

func _initialize() -> void:
	var records: Array[Dictionary] = []
	for seed_value: int in [1, 7, 17, 71, 733, 999]:
		for policy: String in [Resolver.DETAILED, Resolver.AGGREGATE]:
			var state: State = Fixtures.battle(40, seed_value, 0, "cell_037")
			var owner: Authority = Authority.new()
			owner.configure(state)
			Fixtures.coalesce_sides(owner, state, 40)
			owner.advance(1800.0, policy)
			owner.read_leaf("unit_000")
			owner.advance(3600.0, policy)
			records.append({"seed": seed_value, "policy": policy, "state": owner.snapshot(),
				"spatial": owner.spatial.nodes, "work": owner.counters()})
	print("TASK4_REPLAY_SHA256=" + JSON.stringify(records, "", true, true).sha256_text())
	quit(0)
