extends SceneTree
## Phase E contracts: Pulse uses Formal current state and real global history,
## while unsupported local/regional/market/price histories remain unavailable.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "Formal world initializes for Market Pulse")
	if not simulation.initialized:
		_finish(null)
		return
	simulation.advance_minutes(30 * 24 * 60)
	var pulse := simulation.market_pulse_observation()
	_equal(pulse.get("domain_owner"), "FormalWorldEconomyService", "Pulse declares the authoritative Economy owner")
	_check(bool(pulse.get("derived", false)), "Pulse is labelled a deterministic derived view")
	_equal(pulse.get("current"), simulation.economy_view().world_summary(), "Pulse current state equals the Economy-owned world summary")
	_equal(int(pulse.get("market_count", -1)), simulation.market_registry_view().market_count(), "Pulse market count comes from the Formal registry")
	_equal(pulse.get("top_shortages"), simulation.world_summary().get("top_shortages"), "Pulse shortage alerts equal the Formal summary")
	var history := pulse.get("global_history", []) as Array
	_check(history.size() >= 2 and history.size() <= 30, "Pulse exposes a bounded real global history")
	var owned_history := simulation.economy_view().history
	_equal(history, _project_history(owned_history.slice(maxi(0, owned_history.size() - 30))), "Pulse history is an exact narrow projection of Formal history")
	var capabilities := pulse.get("history_capabilities", {}) as Dictionary
	_equal(capabilities.get("global_summary"), true, "global summary history is supported")
	_equal(capabilities.get("per_market"), false, "per-market history is honestly unavailable")
	_equal(capabilities.get("commodity_price"), false, "commodity price history is honestly unavailable")
	_check(bool((pulse.get("global_change", {}) as Dictionary).get("available", false)), "global yesterday change is derived only when two real daily rows exist")
	_check(_is_ranked(pulse.get("lowest_fulfillment_markets", []) as Array, false), "lowest-fulfillment markets are deterministically ranked")
	_check(_is_ranked(pulse.get("highest_fulfillment_markets", []) as Array, true), "highest-fulfillment markets are deterministically ranked")

	var detached := simulation.market_pulse_observation()
	(detached.get("global_history", []) as Array).clear()
	_equal((simulation.market_pulse_observation().get("global_history", []) as Array).size(), history.size(), "Pulse observation is detached")

	set_meta(FormalWorldApplication.LAUNCH_WORLD_META, simulation)
	set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in 32:
		await process_frame
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_ECONOMY)
	_equal(application.economy_tab_id(), FormalWorldApplication.ECONOMY_TAB_PULSE, "Economy opens on Pulse instead of the R1 table")
	_equal(application.economy_market_pulse_observation(), simulation.market_pulse_observation(), "UI Pulse cache equals the Formal narrow query")
	_equal(application._pulse_fulfillment_trend.point_count(), history.size(), "fulfillment sparkline uses every bounded Formal history point")
	_equal(application._pulse_unmet_trend.point_count(), history.size(), "unmet sparkline uses every bounded Formal history point")
	var context := application.economic_context_observation()
	_equal(str((context.get("place", {}) as Dictionary).get("id", "")), str((simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", "")), "economic context preserves the player's real place")
	_equal((context.get("local_market", {}) as Dictionary).get("available"), false, "place-scoped Local market is not fabricated")
	_equal((context.get("regional_market", {}) as Dictionary).get("available"), false, "Regional market is not fabricated")
	_equal(str((context.get("aggregate_market", {}) as Dictionary).get("market_id", "")), application.economy_my_market_id(), "current aggregate context uses the player's Formal market")
	_equal((context.get("employment", {}) as Dictionary).get("available"), false, "Employment remains unavailable")

	_check(application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_OVERVIEW), "Current Context remains reachable")
	_check(application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_MARKETS), "Detailed Markets remains reachable")
	_check(application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_COMMODITIES), "Commodity detail remains reachable")
	_check(application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_SHORTAGES), "Shortage detail remains reachable")
	_check(application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_TRANSPORT), "Transport detail remains reachable")
	_check(application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_PULSE), "Pulse can be restored")
	var refresh_count := application.economy_observation_refresh_count()
	for _index: int in 8:
		application.queue_redraw()
		await process_frame
	_equal(application.economy_observation_refresh_count(), refresh_count, "Pulse draw does not rescan markets")

	var ui_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_application.gd")
	_check(ui_source.contains("Market movers：unavailable"), "UI explicitly refuses unsupported market movers")
	_check(ui_source.contains("Local market：unavailable"), "UI explicitly refuses a fabricated Lille market")
	_check(not ui_source.contains("Economic Index"), "UI does not invent an economic index")
	_finish(application)


func _project_history(rows: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value: Variant in rows:
		var row := value as Dictionary
		output.append({
			"day_index": int(row.get("day_index", 0)),
			"total_hour": int(row.get("total_hour", 0)),
			"demand_units": float(row.get("demand_units", 0.0)),
			"consumed_units": float(row.get("consumed_units", 0.0)),
			"unmet_units": float(row.get("unmet_units", 0.0)),
			"fulfillment_bp": int(row.get("fulfillment_bp", 0)),
			"active_shipments": int(row.get("active_shipments", 0)),
		})
	return output


func _is_ranked(rows: Array, descending: bool) -> bool:
	for index: int in range(1, rows.size()):
		var previous := int((rows[index - 1] as Dictionary).get("fulfillment_bp", 0))
		var current := int((rows[index] as Dictionary).get("fulfillment_bp", 0))
		if (descending and previous < current) or (not descending and previous > current):
			return false
	return not rows.is_empty()


func _finish(application: FormalWorldApplication) -> void:
	print("Player Experience R2 E: %d checks, %d failures" % [checks, failures])
	if application != null:
		application.queue_free()
	quit(1 if failures > 0 or checks <= 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label if actual == expected else "%s | actual=%s expected=%s" % [label, var_to_str(actual), var_to_str(expected)])
