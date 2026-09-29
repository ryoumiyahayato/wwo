extends SceneTree
## O2 contracts: runtime political identity is authoritative, historical fields
## remain labelled evidence, and map observation never mutates the player.

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
	_check(simulation.initialized, "Formal world initializes for O2")
	if not simulation.initialized:
		_finish(application)
		return
	var player_before := simulation.player_person_id()
	var context_before := simulation.player_context_view()
	var place_before := str((context_before.get("current_place", {}) as Dictionary).get("id", ""))
	var local_context := context_before.get("political_observation", {}) as Dictionary
	var local_id := str(local_context.get("runtime_entity_id", ""))
	var local := simulation.political_observation(local_id)
	_check(bool(local.get("available", false)), "local polity narrow observation is available")
	_equal(local.get("owner"), "RuntimePoliticalEntityRegistry", "current political identity declares its Formal owner")
	_equal(local.get("runtime_id"), local_id, "local polity comes from player context mapping")
	_equal(local.get("source_historical_id"), simulation.political_registry_view().source_historical_id(local_id), "local source identity matches runtime registry")
	var local_evidence := local.get("historical_evidence", {}) as Dictionary
	var source_record := simulation.historical_record(str(local.get("source_historical_id", "")))
	_equal(local_evidence.get("status"), source_record.get("status"), "historical status matches admitted evidence")
	_equal(local_evidence.get("valid_from"), source_record.get("valid_from"), "historical validity start matches admitted evidence")
	_equal(local.get("authority_relations"), simulation.political_registry_view().authority_relations_for_target(local_id), "authority relations match runtime registry")
	_check(not local.has("controller_id") and not local.has("sovereign_id"), "narrow observation does not revive legacy controller aliases")

	var detached := simulation.political_observation(local_id)
	(detached.get("historical_evidence", {}) as Dictionary)["status"] = "tampered"
	(detached.get("authority_relations", []) as Array).clear()
	_equal((simulation.political_observation(local_id).get("historical_evidence", {}) as Dictionary).get("status"), source_record.get("status"), "political observation is detached")

	var observed_id := "state:german_empire"
	_check(simulation.has_polity(observed_id) and observed_id != local_id, "a different observed polity exists")
	application.selected_country_id = observed_id
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_POLITICS)
	var observed := application.observed_political_observation()
	_equal(observed.get("runtime_id"), observed_id, "observed polity follows map selection")
	_check(str(observed.get("runtime_id", "")) != str(application.local_political_observation().get("runtime_id", "")), "local and observed political contexts can differ")
	_equal(simulation.player_person_id(), player_before, "polity observation preserves player identity")
	_equal(str((simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", "")), place_before, "polity observation preserves player place")
	_equal((observed.get("historical_evidence", {}) as Dictionary).get("flag_id"), simulation.historical_record(str(observed.get("source_historical_id", ""))).get("flag_id"), "flag resource identity remains a separate evidence field")
	_check(str(observed.get("runtime_id", "")) != str((observed.get("historical_evidence", {}) as Dictionary).get("flag_id", "")), "flag resource ID is not political identity")

	_check(application._set_politics_tab(FormalWorldApplication.POLITICS_TAB_LOCAL), "Local politics tab is available")
	_check(application._set_politics_tab(FormalWorldApplication.POLITICS_TAB_OBSERVED), "Observed politics tab is available")
	_check(application._set_politics_tab(FormalWorldApplication.POLITICS_TAB_COMPARE), "Local-vs-observed politics tab is available")
	var player_after_tabs := simulation.player_person_id()
	var yaw_before := application.yaw
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640.0, 360.0)
	motion.relative = Vector2(120.0, 0.0)
	application._gui_input(motion)
	_equal(application.yaw, yaw_before, "politics workspace consumes drag without rotating the map")
	_equal(simulation.player_person_id(), player_after_tabs, "politics UI input cannot change player")

	var ui_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_application.gd")
	_check(not ui_source.contains("iso_a3") and not ui_source.contains("SOURCE_FLAG"), "politics UI does not present palette/resource adapters as political identity")
	_check(not ui_source.contains("data/alpha") and not ui_source.contains("prototype character"), "politics UI does not read retained Alpha or prototype identity data")
	_finish(application)


func _finish(application: FormalWorldApplication) -> void:
	print("Formal Observation Surface O2: %d checks, %d failures" % [checks, failures])
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
