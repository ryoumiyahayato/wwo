extends SceneTree
## Player-optional autonomous-world acceptance guard.
##
## This intentionally exercises the already-owned Formal economic loop without
## selecting a country, issuing a player action, or injecting a scripted outcome.
## The selected loop is deterministic by construction; it currently consumes no RNG.

const TOTAL_DAYS: int = 365
const SAVE_RESTORE_DAY: int = 180
const MINUTES_PER_DAY: int = 24 * 60

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(
		simulation.initialize(),
		"autonomous Formal world initializes: %s" % simulation.initialization_error
	)
	if failures > 0:
		_finish({})
		return

	var initial_state := simulation.get_persistent_state()
	var initial_player := (initial_state.get("player", {}) as Dictionary).duplicate(true)
	var initial_runtime_politics := (
		initial_state.get("runtime_politics", {}) as Dictionary
	).duplicate(true)
	var initial_organization := (
		initial_state.get("organization", {}) as Dictionary
	).duplicate(true)
	var initial_organization_authority := (
		initial_state.get("organization_authority", {}) as Dictionary
	).duplicate(true)
	var initial_military := (
		initial_state.get("military_state", {}) as Dictionary
	).duplicate(true)
	var initial_economy := simulation.economy
	var initial_markets := initial_economy.market_states
	var initial_fingerprint := simulation.authoritative_fingerprint()
	_check(not initial_fingerprint.is_empty(), "initial authoritative fingerprint exists")

	# No PlayerState mutation and no player-facing domain entry point is invoked.
	simulation.advance_minutes(SAVE_RESTORE_DAY * MINUTES_PER_DAY)
	var midpoint_fingerprint := simulation.authoritative_fingerprint()
	_check(
		midpoint_fingerprint != initial_fingerprint,
		"world truth changes after 180 autonomous days without player input"
	)
	var midpoint_state := simulation.get_persistent_state()
	_check(
		(midpoint_state.get("player", {}) as Dictionary) == initial_player,
		"player state remains untouched during autonomous advancement"
	)

	# Exercise the persisted JSON boundary rather than handing the in-memory
	# Dictionary directly to restore.
	var encoded_midpoint := JSON.stringify(midpoint_state)
	var decoded_midpoint_variant: Variant = JSON.parse_string(encoded_midpoint)
	_check(decoded_midpoint_variant is Dictionary, "midpoint save payload JSON round-trips")
	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "restore target initializes")
	var restore_ok := false
	if decoded_midpoint_variant is Dictionary:
		restore_ok = restored.restore_persistent_state(
			decoded_midpoint_variant as Dictionary
		)
	_check(restore_ok, "midpoint autonomous world restores")
	if restore_ok:
		_check(
			restored.authoritative_fingerprint() == midpoint_fingerprint,
			"restore preserves the authoritative midpoint fingerprint"
		)
		_check(
			(restored.get_persistent_state().get("player", {}) as Dictionary)
			== initial_player,
			"restore does not invent player activity"
		)

	if not restore_ok:
		_finish({})
		return

	restored.advance_minutes((TOTAL_DAYS - SAVE_RESTORE_DAY) * MINUTES_PER_DAY)
	var final_state := restored.get_persistent_state()
	var final_fingerprint := restored.authoritative_fingerprint()
	var final_economy := restored.economy
	var final_markets := final_economy.market_states
	var change_metrics := _economic_change_metrics(initial_markets, final_markets)
	var activity_metrics := _economic_activity_metrics(final_state, final_economy)

	_check(
		int(restored.world_summary().get("total_hour", -1)) == TOTAL_DAYS * 24,
		"autonomous world reaches one full simulation year"
	)
	_check(
		final_fingerprint != midpoint_fingerprint,
		"world continues changing after restore without player input"
	)
	_check(
		(final_state.get("player", {}) as Dictionary) == initial_player,
		"one-year autonomous run never mutates PlayerState"
	)
	_check(
		int(change_metrics.get("inventory_changed_markets", 0)) > 0,
		"one-year run changes real inventories"
	)
	_check(
		int(change_metrics.get("price_changed_markets", 0)) > 0,
		"one-year run changes real market prices"
	)
	_check(
		int(activity_metrics.get("shortage_days_after_restore", 0)) > 0,
		"post-restore autonomous settlement produces observable shortages"
	)
	_check(
		_state_is_numerically_sound(final_economy),
		"one-year autonomous state has no NaN, infinity, negative inventory, or invalid price"
	)

	# A second uninterrupted run from the same initial world must converge to the
	# exact same authoritative state. The selected loop currently uses no RNG, so
	# there is no seed to hide or global random source to control.
	var reference := FormalWorldSimulation.new()
	_check(reference.initialize(), "determinism reference world initializes")
	if reference.initialized:
		reference.advance_minutes(TOTAL_DAYS * MINUTES_PER_DAY)
		_check(
			reference.authoritative_fingerprint() == final_fingerprint,
			"uninterrupted and save-restored autonomous runs are deterministic-equivalent"
		)

	var diagnostic := {
		"elapsed_simulation_days": TOTAL_DAYS,
		"selected_loop": "formal_economy_daily_settlement",
		"randomness": "none",
		"production_cycles": int(activity_metrics.get("production_cycles", 0)),
		"shipments_dispatched": int(activity_metrics.get("shipments_dispatched", 0)),
		"shipments_delivered": int(activity_metrics.get("shipments_delivered", 0)),
		"active_shipments": int(activity_metrics.get("active_shipments", 0)),
		"inventory_changed_markets": int(
			change_metrics.get("inventory_changed_markets", 0)
		),
		"price_changed_markets": int(change_metrics.get("price_changed_markets", 0)),
		"max_price_change_bp": int(change_metrics.get("max_price_change_bp", 0)),
		"shortage_days_after_restore": int(
			activity_metrics.get("shortage_days_after_restore", 0)
		),
		"save_restore_status": "pass" if restore_ok else "fail",
		"player_state_changed": (
			(final_state.get("player", {}) as Dictionary) != initial_player
		),
		"runtime_politics_changed": (
			(final_state.get("runtime_politics", {}) as Dictionary)
			!= initial_runtime_politics
		),
		"organization_state_changed": (
			(final_state.get("organization", {}) as Dictionary) != initial_organization
		),
		"organization_authority_changed": (
			(final_state.get("organization_authority", {}) as Dictionary)
			!= initial_organization_authority
		),
		"military_state_changed": (
			(final_state.get("military_state", {}) as Dictionary) != initial_military
		),
		"final_fulfillment_bp": int(
			restored.world_summary().get("fulfillment_bp", -1)
		),
		"final_authoritative_fingerprint": final_fingerprint,
	}
	_finish(diagnostic)


func _economic_activity_metrics(
	persistent_state: Dictionary,
	economy: FormalWorldEconomyView
) -> Dictionary:
	var economy_state := persistent_state.get("economy", {}) as Dictionary
	var last_day_index := int(economy_state.get("last_day_index", -1))
	var market_count := economy.market_states.size()
	var dispatched := maxi(0, int(economy_state.get("next_shipment_sequence", 1)) - 1)
	var active := economy.shipments.size()
	var shortage_days := 0
	for row: Dictionary in economy.history:
		if float(row.get("unmet_units", 0.0)) > 0.0001:
			shortage_days += 1
	return {
		"production_cycles": maxi(0, last_day_index) * market_count,
		"shipments_dispatched": dispatched,
		"shipments_delivered": maxi(0, dispatched - active),
		"active_shipments": active,
		"shortage_days_after_restore": shortage_days,
	}


func _economic_change_metrics(
	initial_markets: Dictionary,
	final_markets: Dictionary
) -> Dictionary:
	var inventory_changed_markets := 0
	var price_changed_markets := 0
	var max_price_change_bp := 0
	for raw_market_id: Variant in initial_markets:
		var market_id := str(raw_market_id)
		if not final_markets.has(market_id):
			continue
		var initial_market := initial_markets[market_id] as Dictionary
		var final_market := final_markets[market_id] as Dictionary
		var initial_inventory := initial_market.get("inventory", {}) as Dictionary
		var final_inventory := final_market.get("inventory", {}) as Dictionary
		var initial_prices := initial_market.get("prices", {}) as Dictionary
		var final_prices := final_market.get("prices", {}) as Dictionary
		var inventory_changed := false
		var price_changed := false
		for raw_commodity_id: Variant in initial_inventory:
			var commodity_id := str(raw_commodity_id)
			var opening_units := float(initial_inventory.get(commodity_id, 0.0))
			var closing_units := float(final_inventory.get(commodity_id, opening_units))
			if absf(closing_units - opening_units) > 0.0001:
				inventory_changed = true
		for raw_commodity_id: Variant in initial_prices:
			var commodity_id := str(raw_commodity_id)
			var opening_price := maxi(1, int(initial_prices.get(commodity_id, 1)))
			var closing_price := maxi(1, int(final_prices.get(commodity_id, opening_price)))
			if closing_price != opening_price:
				price_changed = true
				max_price_change_bp = maxi(
					max_price_change_bp,
					int(round(
						absf(float(closing_price - opening_price))
						/ float(opening_price)
						* 10000.0
					))
				)
		if inventory_changed:
			inventory_changed_markets += 1
		if price_changed:
			price_changed_markets += 1
	return {
		"inventory_changed_markets": inventory_changed_markets,
		"price_changed_markets": price_changed_markets,
		"max_price_change_bp": max_price_change_bp,
	}


func _state_is_numerically_sound(economy: FormalWorldEconomyView) -> bool:
	for raw_state: Variant in economy.market_states.values():
		var state := raw_state as Dictionary
		if not state.get("inventory", {}) is Dictionary:
			return false
		if not state.get("prices", {}) is Dictionary:
			return false
		for raw_units: Variant in (state.get("inventory", {}) as Dictionary).values():
			var units := float(raw_units)
			if is_nan(units) or is_inf(units) or units < 0.0:
				return false
		for raw_price: Variant in (state.get("prices", {}) as Dictionary).values():
			var price := int(raw_price)
			if price <= 0 or price >= 2_000_000_000:
				return false
	return true


func _finish(diagnostic: Dictionary) -> void:
	print("AUTONOMOUS_FORMAL_WORLD_SOAK=%s" % JSON.stringify(diagnostic))
	print("Autonomous Formal World Soak: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
