extends SceneTree
## Wave 0 regression for the actual Formal product composition and presentation.

const MENU_SCENE := "res://scenes/formal/formal_world_menu.tscn"
const PRODUCT_SCENE := "res://scenes/formal/formal_world_main.tscn"
const FRANCE_ID := "country_fra"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_default_entry()
	var packed := load(PRODUCT_SCENE) as PackedScene
	_check(packed != null, "actual Formal product scene loads")
	if packed == null:
		_finish()
		return
	var application := packed.instantiate() as FormalWorldApplication
	_check(application != null, "actual root constructs FormalWorldApplication")
	if application == null:
		_finish()
		return
	get_root().add_child(application)
	current_scene = application
	await process_frame
	await process_frame
	_check_runtime_truth(application)
	await _check_country_navigation(application)
	_check_time_and_economy(application)
	_check_save_restore_contract(application)
	_check_unavailable_local_navigation(application)
	_check_runtime_provenance(application)
	application.queue_free()
	current_scene = null
	await process_frame
	_finish()


func _check_default_entry() -> void:
	_check(
		str(ProjectSettings.get_setting("application/run/main_scene", "")) == MENU_SCENE,
		"project.godot points to the actual Formal menu"
	)
	var menu_packed := load(MENU_SCENE) as PackedScene
	_check(menu_packed != null, "actual default menu loads")
	if menu_packed == null:
		return
	var menu := menu_packed.instantiate()
	_check(menu is FormalWorldMenu, "actual default menu uses FormalWorldMenu")
	_check(
		str((menu as FormalWorldMenu).WORLD_SCENE) == PRODUCT_SCENE,
		"default menu enters the single actual Formal product scene"
	)
	menu.free()


func _check_runtime_truth(application: FormalWorldApplication) -> void:
	_check(application.formal_simulation.initialized, "FormalWorldSimulation initializes")
	_check(
		application._history_entity_by_id.size() == 146
		and int(application.historical_evidence_report().get("catalog_unit_count", 0)) == 151,
		"151-unit dated catalog remains available while January 1 presentation fails closed"
	)
	_check(
		str(application.historical_evidence_report().get("snapshot_date", "")) == "1900-03-12",
		"political projection retains the dated snapshot"
	)
	_check(application._prototype_presentation_count() == 0, "prototype-only catalogs are absent from normal presentation")
	_check(application._spike_city_count() == 0, "normal runtime has no *_spike city augmentation")
	_check(application._character_profiles.is_empty(), "prototype characters are not loaded")
	_check(application.active_character_key == "product_session", "normal player identity is a neutral product session")
	_check(application._active_character_name() == application.NEUTRAL_SESSION_NAME, "neutral session identity is player-visible")
	_check(application._institutions.is_empty(), "prototype institutions are not live organizations")
	_check(application._world_events.is_empty(), "agenda-derived static events are absent")
	_check(application._history_conflicts.is_empty(), "legacy static conflicts are absent")
	_check(not application.history_war_layer_visible, "legacy military overlay is disabled")


func _check_country_navigation(application: FormalWorldApplication) -> void:
	application._ensure_projection_cache()
	var france_point := application._country_screen_anchors.get(FRANCE_ID, Vector2.INF) as Vector2
	_check(france_point != Vector2.INF, "France has a dated-world selection anchor")
	if france_point == Vector2.INF:
		return
	_send_mouse(application, france_point, true)
	_send_mouse(application, france_point, false)
	await process_frame
	_check(application.selected_country_id == FRANCE_ID, "country selection works on the actual dated globe")
	_check(application.info_open, "country selection opens current political-unit information")
	application._focus_selected_country()
	await process_frame
	_check(application.world_mode == application.WORLD_HISTORICAL_ENTITY_FOCUS, "selected country enters dated political focus")
	_check(application.selected_country_id == FRANCE_ID, "country focus preserves the selected polity")


func _check_time_and_economy(application: FormalWorldApplication) -> void:
	var simulation := application.formal_simulation
	var initial_minutes := simulation.total_minutes
	application.sim_paused = false
	application.sim_speed = 4
	application._on_clock_timer_timeout()
	_check(simulation.total_minutes == initial_minutes + 60, "normal time control advances the Formal clock")
	var boundary_start := simulation.economy.world_summary()
	var before_hour := int(boundary_start.get("total_hour", -1))
	simulation.advance_minutes(23 * 60)
	var boundary_end := simulation.economy.world_summary()
	_check(int(boundary_end.get("total_hour", -1)) == before_hour + 23, "Formal Economy reaches the normal daily settlement boundary")
	_check(int(boundary_end.get("fulfillment_bp", -1)) >= 0, "Formal Economy settlement summary remains valid")
	application.sim_paused = true


func _check_save_restore_contract(application: FormalWorldApplication) -> void:
	var before := application.formal_simulation.get_persistent_state().duplicate(true)
	application.formal_simulation.advance_minutes(7 * 60)
	_check(
		application.formal_simulation.restore_persistent_state(before),
		"narrow Formal state restores through the existing persistence contract"
	)
	_check(
		application.formal_simulation.get_persistent_state() == before,
		"restored Formal time/economy state matches the saved snapshot"
	)


func _check_unavailable_local_navigation(application: FormalWorldApplication) -> void:
	application._enter_region()
	_check(application.space_level == application.REGION, "country can inspect the local-availability layer")
	_check(application.selected_region_id.is_empty(), "no prototype France region is selected")
	_check(application.selected_city_id.is_empty(), "no unsupported city is selected")
	application._open_product_panel("city_status")
	_check(application.active_hud_panel == "city_status", "city navigation resolves to an explicit availability panel")
	application._open_product_panel("politics")
	_check(application.active_hud_panel == "politics", "politics resolves to an explicit unavailable state")
	application._open_product_panel("military")
	_check(application.active_hud_panel == "military", "military resolves to an explicit unavailable state")


func _check_runtime_provenance(application: FormalWorldApplication) -> void:
	var provenance := application.product_runtime_provenance()
	_check(str(provenance.get("product_entry", "")) == MENU_SCENE, "runtime provenance reports the actual default entry")
	_check(str(provenance.get("runtime_scene", "")) == PRODUCT_SCENE, "runtime provenance reports the constructed product scene")
	_check(not bool(provenance.get("e1_product_integration", true)), "runtime provenance reports E1 product integration NO")
	var owners := _owners_by_label(provenance.get("owners", []) as Array)
	_check(_owner_name(owners, "TIME OWNER") == "FormalWorldSimulation", "Formal clock owner is runtime-derived")
	_check(_owner_name(owners, "ECONOMY OWNER") == "FormalWorldEconomyService", "Formal economy owner is runtime-derived")
	for absent_label: String in [
		"POPULATION OWNER",
		"ORGANIZATION OWNER",
		"POLITICS OWNER",
		"MILITARY OWNER",
	]:
		_check(
			str((owners.get(absent_label, {}) as Dictionary).get("status", "")) == "NOT INTEGRATED",
			absent_label + " is honestly not integrated"
		)
	var gate := application.product_integration_gate_report()
	for gate_name: String in [
		"prototype_dependency",
		"fixture_dependency",
		"spike_cities",
		"false_domain_activation",
		"default_entry",
	]:
		_check(str(gate.get(gate_name, "")) == "PASS", "product integration gate passes: " + gate_name)


func _owners_by_label(owner_values: Array) -> Dictionary:
	var output := {}
	for owner_value: Variant in owner_values:
		if owner_value is Dictionary:
			var owner := owner_value as Dictionary
			output[str(owner.get("label", ""))] = owner
	return output


func _owner_name(owners: Dictionary, label: String) -> String:
	return str((owners.get(label, {}) as Dictionary).get("owner", ""))


func _send_mouse(
	application: FormalWorldApplication, position: Vector2, pressed: bool
) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	application._gui_input(event)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("Wave 0 product truth: " + message)


func _finish() -> void:
	print("Wave 0 product truth: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
