extends SceneTree
## Player-optional autonomous-world acceptance guard.
##
## This intentionally exercises the already-owned Formal economic loop without
## selecting a country, issuing a player action, or injecting a scripted outcome.
## The selected loop is deterministic by construction; it currently consumes no RNG.

const TOTAL_DAYS: int = 365
const SAVE_RESTORE_DAY: int = 180
const MINUTES_PER_DAY: int = 24 * 60
const AUTHORITATIVE_DOMAIN_ORDER: Array[String] = [
	"total_minutes",
	"historical_evidence",
	"runtime_politics",
	"markets",
	"economy",
	"persons",
	"player",
	"organization",
	"organization_authority",
	"military_state",
]

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
	print("AUTONOMOUS_180D_PRE_SAVE_FINGERPRINT=%s" % midpoint_fingerprint)
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
	var post_restore_fingerprint := ""
	if restore_ok:
		var post_restore_state := restored.get_persistent_state()
		post_restore_fingerprint = restored.authoritative_fingerprint()
		print("AUTONOMOUS_180D_POST_RESTORE_FINGERPRINT=%s" % post_restore_fingerprint)
		if post_restore_fingerprint != midpoint_fingerprint:
			_report_first_authoritative_difference(midpoint_state, post_restore_state)
		_check(
			post_restore_fingerprint == midpoint_fingerprint,
			"restore preserves the authoritative midpoint fingerprint"
		)
		_check(
			(post_restore_state.get("player", {}) as Dictionary) == initial_player,
			"restore does not invent player activity"
		)

	if not restore_ok:
		_finish({})
		return

	restored.advance_minutes((TOTAL_DAYS - SAVE_RESTORE_DAY) * MINUTES_PER_DAY)
	var final_state := restored.get_persistent_state()
	var final_fingerprint := restored.authoritative_fingerprint()
	print("AUTONOMOUS_365D_RESTORED_FINGERPRINT=%s" % final_fingerprint)
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
	var reference_fingerprint := ""
	if reference.initialized:
		reference.advance_minutes(TOTAL_DAYS * MINUTES_PER_DAY)
		reference_fingerprint = reference.authoritative_fingerprint()
		print("AUTONOMOUS_365D_UNINTERRUPTED_FINGERPRINT=%s" % reference_fingerprint)
		_check(
			reference_fingerprint == final_fingerprint,
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
		"pre_save_180d_authoritative_fingerprint": midpoint_fingerprint,
		"post_restore_180d_authoritative_fingerprint": post_restore_fingerprint,
		"final_authoritative_fingerprint": final_fingerprint,
		"uninterrupted_final_authoritative_fingerprint": reference_fingerprint,
	}
	_finish(diagnostic)


func _report_first_authoritative_difference(
	before_state: Dictionary,
	after_state: Dictionary
) -> void:
	for domain: String in AUTHORITATIVE_DOMAIN_ORDER:
		var before_has := before_state.has(domain)
		var after_has := after_state.has(domain)
		var before_value: Variant = before_state.get(domain, null)
		var after_value: Variant = after_state.get(domain, null)
		var before_fingerprint := _diagnostic_fingerprint(before_value) if before_has else "<missing>"
		var after_fingerprint := _diagnostic_fingerprint(after_value) if after_has else "<missing>"
		print(
			"AUTONOMOUS_180D_DOMAIN_FINGERPRINT domain=%s pre=%s post=%s"
			% [domain, before_fingerprint, after_fingerprint]
		)
		if not before_has:
			_print_first_difference(domain, {
				"path": domain,
				"before": null,
				"after": after_value,
				"before_type": "NIL",
				"after_type": type_string(typeof(after_value)),
				"category": "EXTRA",
			})
			return
		if not after_has:
			_print_first_difference(domain, {
				"path": domain,
				"before": before_value,
				"after": null,
				"before_type": type_string(typeof(before_value)),
				"after_type": "NIL",
				"category": "MISSING",
			})
			return
		if before_fingerprint == after_fingerprint:
			continue
		var difference := _first_difference(before_value, after_value, domain)
		if difference.is_empty():
			difference = {
				"path": domain,
				"before": before_value,
				"after": after_value,
				"before_type": type_string(typeof(before_value)),
				"after_type": type_string(typeof(after_value)),
				"category": "VALUE",
			}
		_print_first_difference(domain, difference)
		return
	print("AUTONOMOUS_180D_FIRST_MISMATCH_DOMAIN=<unresolved>")


func _first_difference(before: Variant, after: Variant, path: String) -> Dictionary:
	var before_type := typeof(before)
	var after_type := typeof(after)
	var representation_changed := (
		_diagnostic_fingerprint(before) != _diagnostic_fingerprint(after)
	)
	if before_type != after_type:
		if not representation_changed:
			return {}
		return {
			"path": path,
			"before": before,
			"after": after,
			"before_type": type_string(before_type),
			"after_type": type_string(after_type),
			"category": "TYPE",
		}
	match before_type:
		TYPE_DICTIONARY:
			return _first_dictionary_difference(
				before as Dictionary,
				after as Dictionary,
				path
			)
		TYPE_ARRAY:
			return _first_array_difference(before as Array, after as Array, path)
		_:
			if representation_changed:
				return {
					"path": path,
					"before": before,
					"after": after,
					"before_type": type_string(before_type),
					"after_type": type_string(after_type),
					"category": "VALUE",
				}
	return {}


func _first_dictionary_difference(
	before: Dictionary,
	after: Dictionary,
	path: String
) -> Dictionary:
	for raw_key: Variant in before.keys():
		if not after.has(raw_key):
			return {
				"path": _dictionary_path(path, raw_key),
				"before": before[raw_key],
				"after": null,
				"before_type": type_string(typeof(before[raw_key])),
				"after_type": "NIL",
				"category": "MISSING",
			}
	for raw_key: Variant in after.keys():
		if not before.has(raw_key):
			return {
				"path": _dictionary_path(path, raw_key),
				"before": null,
				"after": after[raw_key],
				"before_type": "NIL",
				"after_type": type_string(typeof(after[raw_key])),
				"category": "EXTRA",
			}
	for raw_key: Variant in before.keys():
		var difference := _first_difference(
			before[raw_key],
			after[raw_key],
			_dictionary_path(path, raw_key)
		)
		if not difference.is_empty():
			return difference
	var before_keys := before.keys()
	var after_keys := after.keys()
	if before_keys != after_keys:
		return {
			"path": path,
			"before": before_keys,
			"after": after_keys,
			"before_type": "Dictionary key order",
			"after_type": "Dictionary key order",
			"category": "ORDERING",
		}
	return {}


func _first_array_difference(before: Array, after: Array, path: String) -> Dictionary:
	var shared_size := mini(before.size(), after.size())
	var first_content_difference: Dictionary = {}
	for index: int in range(shared_size):
		var difference := _first_difference(
			before[index], after[index], "%s[%d]" % [path, index]
		)
		if not difference.is_empty():
			first_content_difference = difference
			break
	if before.size() == after.size() and not first_content_difference.is_empty():
		if _arrays_are_strict_permutations(before, after):
			return {
				"path": path,
				"before": before,
				"after": after,
				"before_type": "Array order",
				"after_type": "Array order",
				"category": "ORDERING",
			}
	if not first_content_difference.is_empty():
		return first_content_difference
	if before.size() > after.size():
		return {
			"path": "%s[%d]" % [path, shared_size],
			"before": before[shared_size],
			"after": null,
			"before_type": type_string(typeof(before[shared_size])),
			"after_type": "NIL",
			"category": "MISSING",
		}
	if after.size() > before.size():
		return {
			"path": "%s[%d]" % [path, shared_size],
			"before": null,
			"after": after[shared_size],
			"before_type": "NIL",
			"after_type": type_string(typeof(after[shared_size])),
			"category": "EXTRA",
		}
	return {}


func _arrays_are_strict_permutations(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return false
	var before_counts: Dictionary = {}
	var after_counts: Dictionary = {}
	for value: Variant in before:
		var signature := _typed_signature(value)
		before_counts[signature] = int(before_counts.get(signature, 0)) + 1
	for value: Variant in after:
		var signature := _typed_signature(value)
		after_counts[signature] = int(after_counts.get(signature, 0)) + 1
	return before_counts == after_counts


func _typed_signature(value: Variant) -> String:
	return "%s:%s" % [type_string(typeof(value)), JSON.stringify(value)]


func _dictionary_path(path: String, key: Variant) -> String:
	return "%s[%s]" % [path, JSON.stringify(key)]


func _diagnostic_fingerprint(value: Variant) -> String:
	return JSON.stringify(value).sha256_text()


func _print_first_difference(domain: String, difference: Dictionary) -> void:
	print("AUTONOMOUS_180D_FIRST_MISMATCH_DOMAIN=%s" % domain)
	print("AUTONOMOUS_180D_FIRST_MISMATCH_PATH=%s" % str(difference.get("path", domain)))
	print(
		"AUTONOMOUS_180D_BEFORE_VALUE=%s"
		% _diagnostic_value_text(difference.get("before", null))
	)
	print(
		"AUTONOMOUS_180D_BEFORE_TYPE=%s"
		% str(difference.get("before_type", "NIL"))
	)
	print(
		"AUTONOMOUS_180D_AFTER_VALUE=%s"
		% _diagnostic_value_text(difference.get("after", null))
	)
	print(
		"AUTONOMOUS_180D_AFTER_TYPE=%s"
		% str(difference.get("after_type", "NIL"))
	)
	print("AUTONOMOUS_180D_MISMATCH_CATEGORY=%s" % str(difference.get("category", "VALUE")))


func _diagnostic_value_text(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return "%.17f" % float(value)
	var rendered := JSON.stringify(value)
	if rendered.length() <= 512:
		return rendered
	return rendered.substr(0, 509) + "..."


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
		for raw_inventory_commodity_id: Variant in initial_inventory:
			var inventory_commodity_id := str(raw_inventory_commodity_id)
			var opening_units := float(
				initial_inventory.get(inventory_commodity_id, 0.0)
			)
			var closing_units := float(
				final_inventory.get(inventory_commodity_id, opening_units)
			)
			if absf(closing_units - opening_units) > 0.0001:
				inventory_changed = true
		for raw_price_commodity_id: Variant in initial_prices:
			var price_commodity_id := str(raw_price_commodity_id)
			var opening_price := maxi(
				1, int(initial_prices.get(price_commodity_id, 1))
			)
			var closing_price := maxi(
				1, int(final_prices.get(price_commodity_id, opening_price))
			)
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
