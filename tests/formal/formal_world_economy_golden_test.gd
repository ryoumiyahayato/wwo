extends SceneTree
## Exact economic-state guard against the trusted P1 baseline. Political IDs and
## political roster counts are excluded; all economic formulas and in-flight
## economic state remain covered.

const CHECKPOINT_DAYS: Array[int] = [30, 365]
const EXPECTED_DIGESTS: Dictionary = {
	30: "90408a5dbe3075b6f64b893e9314736be0116293f3e6196b9dd4f04029657133",
	365: "c73d9ca3fe8e8bb114e43354beb53a6ace1b4704832e58dacdbcc27eed9e1286",
}
const SIMULATION_SCRIPT := preload("res://scripts/formal/formal_world_simulation.gd")

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation: Variant = SIMULATION_SCRIPT.new()
	_check(simulation.initialize(), "golden economy world initializes")
	if simulation.initialized:
		var previous_day := 0
		for checkpoint_day: int in CHECKPOINT_DAYS:
			for _day: int in range(previous_day, checkpoint_day):
				simulation.advance_minutes(24 * 60)
			var digest := _economic_digest(simulation.economy)
			print("FORMAL_ECONOMY_GOLDEN_%d=%s" % [checkpoint_day, digest])
			if EXPECTED_DIGESTS.has(checkpoint_day):
				_check(
					digest == str(EXPECTED_DIGESTS[checkpoint_day]),
					"day %d economy matches trusted baseline" % checkpoint_day
				)
			previous_day = checkpoint_day
	print("Formal world economy golden: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _economic_digest(economy: Variant) -> String:
	var state: Dictionary = economy.get_persistent_state().duplicate(true)
	state.erase("schema_id")
	var country_states := state.get("country_states", {}) as Dictionary
	for economy_id_value: Variant in country_states:
		var economy_id := str(economy_id_value)
		var country := country_states[economy_id] as Dictionary
		country.erase("polity_ids")
		country_states[economy_id] = country
	state["country_states"] = country_states
	var history := state.get("history", []) as Array
	for index: int in range(history.size()):
		var row := history[index] as Dictionary
		row.erase("world_political_unit_count")
		row.erase("detailed_polity_unit_count")
		row.erase("background_polity_count")
		history[index] = row
	state["history"] = history
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(JSON.stringify(state).to_utf8_buffer())
	return hashing.finish().hex_encode()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
