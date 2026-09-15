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
const RESTORE_MARKET_ID := "market:legacy_aggregate:united_states_1900"
const RESTORE_COMMODITY_ID := "wheat"

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_price_restore_typing()
	_check_fulfillment_restore_typing()
	_check_trade_balance_restore_typing()
	var simulation: Variant = SIMULATION_SCRIPT.new()
	_check(simulation.initialize(), "golden economy world initializes")
	if simulation.initialized:
		var previous_day := 0
		for checkpoint_day: int in CHECKPOINT_DAYS:
			for _day: int in range(previous_day, checkpoint_day):
				simulation.advance_minutes(24 * 60)
			var digest := _economic_digest(simulation.economy_regression_snapshot())
			print("FORMAL_ECONOMY_GOLDEN_%d=%s" % [checkpoint_day, digest])
			if EXPECTED_DIGESTS.has(checkpoint_day):
				_check(
					digest == str(EXPECTED_DIGESTS[checkpoint_day]),
					"day %d economy matches trusted baseline" % checkpoint_day
				)
			previous_day = checkpoint_day
	print("Formal world economy golden: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_price_restore_typing() -> void:
	var source: Variant = SIMULATION_SCRIPT.new()
	_check(source.initialize(), "price restore source initializes")
	if not source.initialized:
		return
	var base_state: Dictionary = source.get_persistent_state()
	var opening_price: Variant = _price_value(base_state)
	_check(opening_price == 120 and typeof(opening_price) == TYPE_INT, "wheat price starts as int 120")

	var integral_candidate := base_state.duplicate(true)
	_set_price_value(integral_candidate, 120.0)
	var integral_target: Variant = SIMULATION_SCRIPT.new()
	_check(integral_target.initialize(), "integral-float price restore target initializes")
	if integral_target.initialized:
		_check(integral_target.restore_persistent_state(integral_candidate), "price restore accepts 120.0")
		var restored_price: Variant = _price_value(integral_target.get_persistent_state())
		_check(restored_price == 120 and typeof(restored_price) == TYPE_INT, "120.0 restores as int 120")

	var fractional_target: Variant = SIMULATION_SCRIPT.new()
	_check(fractional_target.initialize(), "fractional price restore target initializes")
	if not fractional_target.initialized:
		return
	var before_reject: Dictionary = fractional_target.get_persistent_state().duplicate(true)
	var fractional_candidate := base_state.duplicate(true)
	_set_price_value(fractional_candidate, 120.5)
	_check(not fractional_target.restore_persistent_state(fractional_candidate), "price restore rejects 120.5")
	_check(fractional_target.get_persistent_state() == before_reject, "fractional price rejection is atomic")


func _check_fulfillment_restore_typing() -> void:
	var source: Variant = SIMULATION_SCRIPT.new()
	_check(source.initialize(), "fulfillment restore source initializes")
	if not source.initialized:
		return
	source.advance_minutes(24 * 60)
	var base_state: Dictionary = source.get_persistent_state()
	var opening_value: Variant = _fulfillment_value(base_state)
	_check(typeof(opening_value) == TYPE_INT, "daily fulfillment starts as int")
	if typeof(opening_value) != TYPE_INT:
		return

	var integral_candidate := base_state.duplicate(true)
	_set_fulfillment_value(integral_candidate, float(opening_value))
	var integral_target: Variant = SIMULATION_SCRIPT.new()
	_check(integral_target.initialize(), "integral-float fulfillment restore target initializes")
	if integral_target.initialized:
		_check(integral_target.restore_persistent_state(integral_candidate), "fulfillment restore accepts integral float")
		var restored_value: Variant = _fulfillment_value(integral_target.get_persistent_state())
		_check(restored_value == opening_value and typeof(restored_value) == TYPE_INT, "integral fulfillment restores as int")

	var fractional_target: Variant = SIMULATION_SCRIPT.new()
	_check(fractional_target.initialize(), "fractional fulfillment restore target initializes")
	if not fractional_target.initialized:
		return
	var before_reject: Dictionary = fractional_target.get_persistent_state().duplicate(true)
	var fractional_candidate := base_state.duplicate(true)
	_set_fulfillment_value(fractional_candidate, float(opening_value) + 0.5)
	_check(not fractional_target.restore_persistent_state(fractional_candidate), "fulfillment restore rejects fractional float")
	_check(fractional_target.get_persistent_state() == before_reject, "fractional fulfillment rejection is atomic")


func _check_trade_balance_restore_typing() -> void:
	var source: Variant = SIMULATION_SCRIPT.new()
	_check(source.initialize(), "trade-balance restore source initializes")
	if not source.initialized:
		return
	var base_state: Dictionary = source.get_persistent_state()
	var integral_candidate := base_state.duplicate(true)
	_set_trade_balance_value(integral_candidate, 132892589.0)
	var integral_target: Variant = SIMULATION_SCRIPT.new()
	_check(integral_target.initialize(), "integral-float trade-balance target initializes")
	if integral_target.initialized:
		_check(integral_target.restore_persistent_state(integral_candidate), "trade balance restore accepts integral float")
		var restored_value: Variant = _trade_balance_value(integral_target.get_persistent_state())
		_check(restored_value == 132892589 and typeof(restored_value) == TYPE_INT, "integral trade balance restores as int")

	var fractional_target: Variant = SIMULATION_SCRIPT.new()
	_check(fractional_target.initialize(), "fractional trade-balance target initializes")
	if not fractional_target.initialized:
		return
	var before_reject: Dictionary = fractional_target.get_persistent_state().duplicate(true)
	var fractional_candidate := base_state.duplicate(true)
	_set_trade_balance_value(fractional_candidate, 132892589.5)
	_check(not fractional_target.restore_persistent_state(fractional_candidate), "trade balance restore rejects fractional float")
	_check(fractional_target.get_persistent_state() == before_reject, "fractional trade-balance rejection is atomic")


func _price_value(snapshot: Dictionary) -> Variant:
	var market := _restore_market(snapshot)
	return (market.get("prices", {}) as Dictionary).get(RESTORE_COMMODITY_ID, null)


func _set_price_value(snapshot: Dictionary, value: Variant) -> void:
	var market := _restore_market(snapshot)
	var prices := market.get("prices", {}) as Dictionary
	prices[RESTORE_COMMODITY_ID] = value
	market["prices"] = prices


func _fulfillment_value(snapshot: Dictionary) -> Variant:
	var market := _restore_market(snapshot)
	return (market.get("daily_totals", {}) as Dictionary).get("fulfillment_bp", null)


func _set_fulfillment_value(snapshot: Dictionary, value: Variant) -> void:
	var market := _restore_market(snapshot)
	var totals := market.get("daily_totals", {}) as Dictionary
	totals["fulfillment_bp"] = value
	market["daily_totals"] = totals


func _trade_balance_value(snapshot: Dictionary) -> Variant:
	return _restore_market(snapshot).get("trade_balance_centimes", null)


func _set_trade_balance_value(snapshot: Dictionary, value: Variant) -> void:
	_restore_market(snapshot)["trade_balance_centimes"] = value


func _restore_market(snapshot: Dictionary) -> Dictionary:
	var economy := snapshot.get("economy", {}) as Dictionary
	var markets := economy.get("market_states", {}) as Dictionary
	return markets.get(RESTORE_MARKET_ID, {}) as Dictionary


func _economic_digest(regression_state: Dictionary) -> String:
	var state: Dictionary = regression_state.duplicate(true)
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
