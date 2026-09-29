extends SceneTree
## O1 contracts: Formal economy ownership, narrow detached projections, market
## observation navigation, and map overlays that never mutate player or geometry.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in range(30):
		await process_frame
	var simulation := application.formal_simulation
	_check(simulation.initialized, "Formal world initializes for O1")
	if not simulation.initialized:
		_finish(application)
		return
	var player_id := simulation.player_person_id()
	var player := simulation.player_context_view()
	var economy := player.get("economic_observation", {}) as Dictionary
	var economy_id := str(economy.get("economy_entity_id", ""))
	var expected_market := simulation.market_registry_view().market_id_for_economic_aggregate(economy_id)
	_check(not expected_market.is_empty(), "current player economy resolves to a Formal market")

	var unsettled := simulation.market_observation(expected_market)
	_check(bool(unsettled.get("available", false)), "current player market narrow query is available")
	_check(not bool(unsettled.get("settled", true)), "pre-settlement market is explicitly unsettled")
	_equal(unsettled.get("daily_totals", {}), {}, "unsettled totals are unavailable instead of fabricated zero")

	var catalog := simulation.economy_observation_catalog()
	_equal(catalog.get("domain_owner"), "FormalWorldEconomyService", "market catalogue declares the Formal owner")
	_equal((catalog.get("markets", []) as Array).size(), simulation.market_registry_view().market_count(), "all Formal markets are browsable")
	var commodity_catalog := simulation.commodity_catalog_observation()
	_equal((commodity_catalog.get("commodities", []) as Array).size(), int(simulation.world_summary().get("commodity_count", -1)), "commodity browser count comes from the Formal runtime catalog")
	_equal(commodity_catalog.get("domain_owner"), "FormalWorldEconomyService", "commodity catalogue is a Formal projection")
	var detached_markets := catalog.get("markets", []) as Array
	(detached_markets[0] as Dictionary)["population"] = -99
	_check(int(((simulation.economy_observation_catalog().get("markets", []) as Array)[0] as Dictionary).get("population", -99)) >= 0, "market catalogue rows are detached")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_ECONOMY)
	_equal(application.economy_my_market_id(), expected_market, "Economy Overview resolves the player's market")
	_equal(application.economy_observed_market_id(), expected_market, "initial observed market is the player market")
	var geometry_revision := application.map_projection_revision()
	var refresh_count := application.economy_observation_refresh_count()
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_PERSON)
	for _index: int in range(5):
		application.queue_redraw()
		await process_frame
	_equal(application.economy_observation_refresh_count(), refresh_count, "closed Economy page performs no repeated catalogue refresh")
	_equal(application.map_projection_revision(), geometry_revision, "Economy page navigation does not dirty map geometry")

	simulation.advance_minutes(30 * 24 * 60)
	await process_frame
	var settled := simulation.market_observation(expected_market)
	_check(bool(settled.get("settled", false)), "current market becomes settled after the Formal daily boundary")
	_equal((settled.get("commodities", []) as Array).size(), int(commodity_catalog.get("commodity_count", -1)), "market commodity rows cover the Formal catalog")
	var first_commodity := (settled.get("commodities", []) as Array)[0] as Dictionary
	_check(first_commodity.has("inventory") and first_commodity.has("price_centimes"), "commodity stock and price come from owned Formal market state")

	var shortages := simulation.shortage_observation()
	var shortage_rows := shortages.get("rows", []) as Array
	var summary_shortages := simulation.world_summary().get("top_shortages", []) as Array
	if not summary_shortages.is_empty():
		var top := summary_shortages[0] as Dictionary
		_check(_contains_shortage(shortage_rows, str(top.get("market_id", "")), str(top.get("commodity_id", ""))), "Shortage view contains the Formal world-summary top shortage")
	var all_shortages_positive := true
	for row_value: Variant in shortage_rows:
		var row := row_value as Dictionary
		if float(row.get("unmet", 0.0)) <= 0.0:
			all_shortages_positive = false
			break
	_check(all_shortages_positive and not shortage_rows.is_empty(), "Shortage view contains only actual unmet rows")

	var transport := simulation.transport_observation()
	var economy_view := simulation.economy_view()
	_equal(transport.get("active_shipments", []), economy_view.shipments, "transport observation matches Formal active shipments")
	_equal(transport.get("routes", []), economy_view.routes, "transport observation matches Formal routes")

	var overlay := simulation.economy_overlay_observation("fulfillment")
	var overlay_values := overlay.get("values_by_polity_id", {}) as Dictionary
	_check(bool(overlay.get("derived", false)), "economy map overlay is labelled deterministic derived data")
	var shared_mapping_checked := false
	for market_row_value: Variant in simulation.economy_observation_catalog().get("markets", []) as Array:
		var market_row := market_row_value as Dictionary
		var polity_ids := market_row.get("polity_ids", []) as Array
		if polity_ids.size() < 2:
			continue
		var first_id := str(polity_ids[0])
		var second_id := str(polity_ids[1])
		if overlay_values.has(first_id) and overlay_values.has(second_id):
			_equal((overlay_values[first_id] as Dictionary).get("value"), (overlay_values[second_id] as Dictionary).get("value"), "polities sharing one economy receive the same overlay value")
			shared_mapping_checked = true
			break
	_check(shared_mapping_checked, "at least one multi-polity economy mapping is verified")
	var unmapped_id := ""
	for polity_id: String in simulation.political_registry_view().entity_ids():
		if simulation.market_id_for_polity(polity_id).is_empty():
			unmapped_id = polity_id
			break
	_check(not unmapped_id.is_empty() and not overlay_values.has(unmapped_id), "unmapped polity remains explicitly unavailable to the economy overlay")

	var observed_polity := ""
	for polity_id: String in simulation.political_registry_view().entity_ids():
		var market_id := simulation.market_id_for_polity(polity_id)
		if not market_id.is_empty() and market_id != expected_market:
			observed_polity = polity_id
			break
	_check(not observed_polity.is_empty(), "a different mapped polity is available for observation")
	if not observed_polity.is_empty():
		application.selected_country_id = observed_polity
		application._activate_button("formal_market_map_observed")
		_equal(application.economy_observed_market_id(), simulation.market_id_for_polity(observed_polity), "selected polity changes observed market")
		_equal(simulation.player_person_id(), player_id, "observed market selection preserves player identity")
		_equal(str((simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", "")), str((player.get("current_place", {}) as Dictionary).get("id", "")), "observed market selection preserves player place")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	var before_overlay_revision := application.map_projection_revision()
	_check(application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_FULFILLMENT), "fulfillment map mode is available")
	_equal(application.map_projection_revision(), before_overlay_revision, "fulfillment overlay does not rebuild geometry")
	_check(application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_SHORTAGE), "shortage map mode is available")
	_equal(application.map_projection_revision(), before_overlay_revision, "shortage overlay does not rebuild geometry")
	_equal(simulation.player_person_id(), player_id, "economy overlays preserve the player")

	var ui_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_application.gd")
	_check(not ui_source.contains("data/alpha") and not ui_source.contains("V2.3"), "Formal economy UI does not read retained Alpha or V2.3 sources")
	_finish(application)


func _contains_shortage(rows: Array, market_id: String, commodity_id: String) -> bool:
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if str(row.get("market_id", "")) == market_id and str(row.get("commodity_id", "")) == commodity_id:
			return true
	return false


func _finish(application: FormalWorldApplication) -> void:
	print("Formal Observation Surface O1: %d checks, %d failures" % [checks, failures])
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
