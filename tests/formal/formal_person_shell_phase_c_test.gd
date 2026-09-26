extends SceneTree

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
	_check(application.formal_simulation.initialized, "Formal shell world initializes")
	if not application.formal_simulation.initialized:
		_finish(application)
		return

	var player_id := application.formal_simulation.player_person_id()
	_equal(application.formal_workspace_id(), FormalWorldApplication.WORKSPACE_PERSON, "person home is the default workspace")
	_check(application.sim_paused, "person home starts paused")
	_equal(application.shell_player_person_id(), player_id, "person home identity equals player_person_id")
	_equal(application.formal_prototype_character_count(), 0, "prototype character file does not drive Formal shell")

	var expected_workspaces: Array[String] = [
		FormalWorldApplication.WORKSPACE_PERSON,
		FormalWorldApplication.WORKSPACE_ECONOMY,
		FormalWorldApplication.WORKSPACE_RELATIONS,
		FormalWorldApplication.WORKSPACE_ORGANIZATION,
		FormalWorldApplication.WORKSPACE_POLITICS,
		FormalWorldApplication.WORKSPACE_MILITARY,
		FormalWorldApplication.WORKSPACE_MAP,
	]
	_equal(application.formal_workspace_ids(), expected_workspaces, "seven first-class navigation entries are exact")
	var revision_before := application.map_projection_revision()
	for workspace_id: String in expected_workspaces:
		_check(application.set_formal_workspace(workspace_id), "navigate to %s" % workspace_id)
		await process_frame
		_equal(application.formal_workspace_id(), workspace_id, "%s becomes current workspace" % workspace_id)
		_equal(application.shell_player_person_id(), player_id, "%s navigation preserves player identity" % workspace_id)
	_equal(application.map_projection_revision(), revision_before, "shell navigation does not dirty map geometry projection")

	for workspace_id: String in [
		FormalWorldApplication.WORKSPACE_ECONOMY,
		FormalWorldApplication.WORKSPACE_RELATIONS,
		FormalWorldApplication.WORKSPACE_ORGANIZATION,
		FormalWorldApplication.WORKSPACE_POLITICS,
	]:
		application.set_formal_workspace(workspace_id)
		_equal(application.formal_page_execution_actions(), [], "%s exposes no fabricated command" % workspace_id)

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MILITARY)
	var defend := application.formal_simulation.player_defend_options()
	_equal(defend.get("acting_person_id"), player_id, "DEFEND options bind the authoritative player")
	_check(not bool(defend.get("available", true)), "default production world has no authorized DEFEND")
	_check((defend.get("unavailable_reasons", []) as Array).has("no_formation"), "default DEFEND explains missing formation")
	_check((defend.get("unavailable_reasons", []) as Array).has("no_authority_context"), "default DEFEND explains missing authority context")
	_equal(application.formal_page_execution_actions(), [], "military empty state has no execution button")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_PERSON)
	application.queue_redraw()
	await process_frame
	_check(not _has_action(application, "toggle_pause"), "covered map time button is not clickable on person page")
	_check(not _has_action(application, "toggle_character_panel"), "covered prototype-style character button is not clickable")
	var yaw_before := application.yaw
	var revision_before_drag := application.map_projection_revision()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640.0, 360.0)
	motion.relative = Vector2(120.0, 40.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	application._gui_input(motion)
	_equal(application.yaw, yaw_before, "dragging person-page blank space cannot rotate map")
	_equal(application.map_projection_revision(), revision_before_drag, "person-page drag cannot dirty map projection")
	application._activate_button("formal_system_toggle")
	application.queue_redraw()
	await process_frame
	_check(application.formal_system_menu_open(), "system menu opens as a modal layer")
	_check(not _has_action(application, "formal_workspace:map"), "system modal removes covered navigation hit targets")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	application._unhandled_key_input(escape)
	_check(not application.formal_system_menu_open(), "Esc closes the topmost system modal")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	await process_frame
	application._ensure_projection_cache()
	var target_id := "state:german_empire"
	if not application._country_screen_anchors.has(target_id):
		for raw_id: Variant in application._country_screen_anchors.keys():
			if str(raw_id) != application.selected_country_id:
				target_id = str(raw_id)
				break
	var anchor := application._country_screen_anchors.get(target_id, Vector2.INF) as Vector2
	_check(anchor != Vector2.INF, "map workspace exposes a selectable polity anchor")
	if anchor != Vector2.INF:
		_send_mouse(application, anchor, true)
		_send_mouse(application, anchor, false)
		await process_frame
		_equal(application.selected_country_id, target_id, "map click changes selected polity")
		_equal(application.formal_simulation.player_person_id(), player_id, "map click does not change player")
	application.info_open = false
	application.info_progress = 0.0
	application.economy_panel_open = true
	var panel_yaw := application.yaw
	var panel_press := InputEventMouseButton.new()
	panel_press.button_index = MOUSE_BUTTON_LEFT
	panel_press.pressed = true
	panel_press.position = Vector2(500.0, 400.0)
	application._gui_input(panel_press)
	var panel_motion := InputEventMouseMotion.new()
	panel_motion.position = Vector2(620.0, 440.0)
	panel_motion.relative = Vector2(120.0, 40.0)
	panel_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	application._gui_input(panel_motion)
	_equal(application.yaw, panel_yaw, "open map panel consumes blank-space drag")
	application.economy_panel_open = false

	var saved := application.formal_simulation.get_persistent_state()
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_RELATIONS)
	_check(application.formal_simulation.restore_persistent_state(saved), "same Formal save restores while shell is open")
	await process_frame
	_equal(application.shell_player_person_id(), player_id, "restore keeps shell and authoritative player aligned")
	_equal(application.formal_simulation.player_person_id(), player_id, "restore keeps the same player ID")

	_finish(application)


func _has_action(application: FormalWorldApplication, action: String) -> bool:
	for record: Dictionary in application._button_hits:
		if str(record.get("action", "")) == action and bool(record.get("enabled", false)):
			return true
	return false


func _send_mouse(application: FormalWorldApplication, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	application._gui_input(event)


func _finish(application: FormalWorldApplication) -> void:
	print("Formal person shell Phase C: %d checks, %d failures" % [checks, failures])
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
