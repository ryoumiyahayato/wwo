extends SceneTree
## Phase S contracts: the primary shell is situation-centered, while politics,
## military, evidence, and retained R1 tables remain reachable as context views.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in 32:
		await process_frame
	var simulation := application.formal_simulation
	_check(simulation.initialized, "Formal world initializes for the Situation surface")
	if not simulation.initialized:
		_finish(application)
		return

	_equal(application.formal_primary_navigation_ids(), [
		FormalWorldApplication.WORKSPACE_PERSON,
		FormalWorldApplication.WORKSPACE_ECONOMY,
		FormalWorldApplication.WORKSPACE_ORGANIZATION,
		FormalWorldApplication.WORKSPACE_MAP,
	], "primary navigation contains Situation, Economy, Organization, and World")
	_check(
		not application.formal_primary_navigation_ids().has(FormalWorldApplication.WORKSPACE_RELATIONS),
		"relationship/information is no longer a primary empty shell"
	)
	_check(
		not application.formal_primary_navigation_ids().has(FormalWorldApplication.WORKSPACE_POLITICS),
		"politics is no longer an equal-weight primary tab"
	)
	_check(
		not application.formal_primary_navigation_ids().has(FormalWorldApplication.WORKSPACE_MILITARY),
		"military is no longer an equal-weight primary tab"
	)
	_equal(application.world_context_navigation_ids(), [
		FormalWorldApplication.WORKSPACE_MAP,
		FormalWorldApplication.WORKSPACE_POLITICS,
		FormalWorldApplication.WORKSPACE_MILITARY,
	], "World contains map, political observation, and military context")

	var player_id := simulation.player_person_id()
	var player_context := simulation.player_context_view()
	var player_place := str((player_context.get("current_place", {}) as Dictionary).get("id", ""))
	var situation := application.situation_observation()
	_equal((situation.get("person", {}) as Dictionary).get("person_id"), player_id, "Situation is bound to the authoritative player")
	_equal(
		str(((situation.get("person", {}) as Dictionary).get("current_place", {}) as Dictionary).get("id", "")),
		player_place,
		"Situation place matches the Formal player context"
	)
	var my_market_id := application.economy_my_market_id()
	var situation_market := situation.get("market", {}) as Dictionary
	_equal(situation_market.get("market_id"), my_market_id, "Situation economy uses the player's mapped Formal market")
	_equal(situation_market, simulation.market_observation(my_market_id), "Situation market data equals the narrow authoritative query")
	var situation_org := situation.get("organization", {}) as Dictionary
	_equal(situation_org, simulation.player_organization_observation(), "Situation organization data equals the player-scoped Formal query")
	_equal(
		(situation.get("local_politics", {}) as Dictionary).get("runtime_id"),
		str((player_context.get("political_observation", {}) as Dictionary).get("runtime_entity_id", "")),
		"Situation political environment follows the player context"
	)
	_check(bool(situation.get("derived", false)), "Situation explicitly labels itself a deterministic derived view")

	_equal(application.person_tab_id(), FormalWorldApplication.PERSON_TAB_SITUATION, "Situation is the default person tab")
	_check(application._set_person_tab(FormalWorldApplication.PERSON_TAB_DETAILS), "Details/Evidence remains reachable")
	_equal(application.person_tab_id(), FormalWorldApplication.PERSON_TAB_DETAILS, "Details/Evidence is selected without changing identity")
	_equal(simulation.player_person_id(), player_id, "opening evidence does not change player")
	_check(application._set_person_tab(FormalWorldApplication.PERSON_TAB_SITUATION), "Situation tab is restorable")

	var geometry_revision := application.map_projection_revision()
	var economy_refresh_count := application.economy_observation_refresh_count()
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	application._activate_button("formal_world_context:%s" % FormalWorldApplication.WORKSPACE_POLITICS)
	_equal(application.formal_workspace_id(), FormalWorldApplication.WORKSPACE_POLITICS, "World navigation opens political observation")
	_equal(simulation.player_person_id(), player_id, "political observation preserves player")
	_equal(str((simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", "")), player_place, "political observation preserves place")
	application._activate_button("formal_world_context:%s" % FormalWorldApplication.WORKSPACE_MILITARY)
	_equal(application.formal_workspace_id(), FormalWorldApplication.WORKSPACE_MILITARY, "World navigation opens military context")
	_equal(simulation.player_person_id(), player_id, "military context preserves player")
	_equal(application.formal_page_execution_actions(), [], "default military context has no fabricated command")
	application._activate_button("formal_world_context:%s" % FormalWorldApplication.WORKSPACE_MAP)
	_equal(application.formal_workspace_id(), FormalWorldApplication.WORKSPACE_MAP, "World navigation returns to the map")
	_equal(application.map_projection_revision(), geometry_revision, "context navigation does not dirty map geometry")
	_equal(application.economy_observation_refresh_count(), economy_refresh_count, "Situation and World context do not trigger the full Economy catalogue scan")

	application._selected_place_id = player_place
	application._selected_place_context_cache = simulation.place_context_view(player_place)
	_check(not application._selected_place_context_cache.is_empty(), "player place has a detached Place Card context")
	application._activate_button("formal_place_to_situation")
	_equal(application.formal_workspace_id(), FormalWorldApplication.WORKSPACE_PERSON, "Place Card can return to player Situation")
	_equal(application.person_tab_id(), FormalWorldApplication.PERSON_TAB_SITUATION, "Place Card returns to the Situation layer")
	_equal(simulation.player_person_id(), player_id, "place-to-situation navigation never changes player")
	_equal(str((simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", "")), player_place, "place-to-situation navigation never moves player")

	var ui_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_application.gd")
	_check(ui_source.contains("当前版本尚无个人执行命令"), "Situation honestly states the absent personal-command contract")
	_check(ui_source.contains("关系 / 通信尚未 Formal 化"), "relationship and communication remain an explicit unavailable capability")
	_check(not ui_source.contains("0 friends") and not ui_source.contains("0 unread"), "Situation does not invent empty social or inbox facts")
	_finish(application)


func _finish(application: FormalWorldApplication) -> void:
	print("Player Experience R2 S: %d checks, %d failures" % [checks, failures])
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
