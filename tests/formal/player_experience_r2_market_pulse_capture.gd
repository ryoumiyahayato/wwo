extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var _output_dir: String = ""


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_output_dir = OS.get_environment("WWO_R2_EVIDENCE_DIR")
	if _output_dir.is_empty():
		_output_dir = ProjectSettings.globalize_path("res://artifacts/player_experience_r2/e")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var service := FormalNewGameService.new()
	var preview := service.preview_player_candidates({
		"population_origin_id": "country_fra",
		"start_place_id": "place:lille",
		"birth_year_min": 1860,
		"birth_year_max": 1882,
		"random_origin": false,
		"locked_fields": {},
		"seed": 19000101,
		"rules_version": FormalNewGameService.RULES_VERSION,
		"draft_index": 0,
	})
	if not bool(preview.get("success", false)):
		_fail("preview failed")
		return
	var candidate := (preview.get("candidates", []) as Array)[0] as Dictionary
	var created := service.create_new_game(str(candidate.get("candidate_token", "")), "capture:r2:market-pulse")
	if not bool(created.get("success", false)):
		_fail(str(created.get("message", "creation failed")))
		return
	var world := created.get("world") as FormalWorldSimulation
	world.advance_minutes(45 * 24 * 60)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(32)
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_ECONOMY)
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_PULSE)
	await _capture_frame("E01_market_pulse_global.png")
	await _capture_frame("E03_market_movers_unavailable.png")
	await _capture_frame("E04_global_trend_real.png")

	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_OVERVIEW)
	await _capture_frame("E02_current_economic_context.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_SHORTAGES)
	await _capture_frame("E05_shortage_alerts.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_MARKETS)
	await _capture_frame("E06_detailed_markets.png")
	application._set_economy_tab(FormalWorldApplication.ECONOMY_TAB_COMMODITIES)
	await _capture_frame("E07_commodity_detail.png")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_FULFILLMENT)
	await _settle_map(application)
	await _capture_frame("E08_global_map_fulfillment.png")
	application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_SHORTAGE)
	await _settle_map(application)
	await _capture_frame("E09_global_map_shortage.png")

	application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_POLITICAL)
	application._map_player_audit_input_kind = "zoom"
	application.map_debug_focus_camera_on_unit_anchor(
		application._lon_lat_to_unit(Vector2(3.0573, 50.6292)),
		application.WORLD_ZOOM_MAX
	)
	application._selected_place_id = "place:lille"
	application._selected_place_context_cache = world.place_context_view("place:lille")
	await _settle_map(application)
	await _capture_frame("E10_city_with_aggregate_market_notice.png")
	application.queue_free()
	get_tree().quit(0)


func _settle_map(application: FormalWorldApplication) -> void:
	application.angular_velocity = 0.0
	application.dragging = false
	application.set_process(true)
	await get_tree().create_timer(0.30).timeout
	var stable_hash := ""
	var stable_frames := 0
	for _index: int in 360:
		application.angular_velocity = 0.0
		application.set_process(true)
		application.queue_redraw()
		await get_tree().process_frame
		application._ensure_projection_cache()
		var report := application.formal_map_lod_report(true)
		if (
			bool(report.get("presentation_surface_complete", false))
			and int(report.get("flag_eligible_entity_count", 0)) > 0
			and (
				int(report.get("drawn_flag_entity_count", 0)) > 0
				if application.map_observation_mode() == FormalWorldApplication.MAP_MODE_POLITICAL
				else int(report.get("visible_political_entity_count", 0)) > 0
			)
			and int(report.get("flag_projection_cache_revision", -1))
				== int(report.get("projection_revision", -2))
		):
			var render_hash := str(report.get("render_state_hash", ""))
			stable_frames = stable_frames + 1 if render_hash == stable_hash else 1
			stable_hash = render_hash
			if stable_frames >= 2:
				return
		else:
			stable_frames = 0
			stable_hash = ""
	_fail("map cache did not reach a stable flag surface")


func _capture_frame(filename: String) -> void:
	await _settle_frames(6)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		_fail("capture smaller than 1280x720")
		return
	var error := image.save_png(_output_dir.path_join(filename))
	if error != OK:
		_fail(error_string(error))


func _fail(message: String) -> void:
	push_error("R2 Market Pulse capture: %s" % message)
	get_tree().quit(1)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame
