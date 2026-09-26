extends Node

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const OUTPUT_DIR := "C:/Users/agcrf/wwo-formal-person-entry-r1/evidence/player_experience_r2/m"

var _reports: Array[Dictionary] = []


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
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
		_fail("candidate preview failed")
		return
	var candidate := (preview.get("candidates", []) as Array)[0] as Dictionary
	var created := service.create_new_game(
		str(candidate.get("candidate_token", "")), "capture:player-experience-r2:m"
	)
	if not bool(created.get("success", false)):
		_fail(str(created.get("message", "new game failed")))
		return
	var world := created.get("world") as FormalWorldSimulation
	get_tree().set_meta(FormalWorldApplication.LAUNCH_WORLD_META, world)
	get_tree().set_meta(FormalWorldApplication.LAUNCH_MODE_META, "new")
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	add_child(application)
	await _settle_frames(48)
	if application.formal_simulation.player_person_id() != world.player_person_id():
		_fail("delivered Formal world changed player")
		return
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	application._set_map_observation_mode(FormalWorldApplication.MAP_MODE_POLITICAL)
	application.selected_country_id = "state:country_fra"
	application.hover_country_id = ""
	application.yaw = -0.08
	application.tilt = -0.18
	await _zoom_and_settle(application, 1.0)
	await _save_state(application, "M01_global_flag_labels_off.png")

	application.hover_country_id = "state:german_empire"
	application.queue_redraw()
	await _settle_frames(4)
	await _save_state(application, "M02_global_hover_name.png")
	application.hover_country_id = ""

	await _zoom_and_settle(application, 2.35)
	await _save_state(application, "M03_region.png")

	application._map_player_audit_input_kind = "zoom"
	application.map_debug_focus_camera_on_unit_anchor(
		application._lon_lat_to_unit(Vector2(3.0573, 50.6292)), 6.0
	)
	await _settle_map(application)
	await _save_state(application, "M04_city_mode.png")
	var lille_point := application.formal_place_screen_point("place:lille")
	if lille_point == Vector2.INF:
		_fail("Lille marker was not projected in CITY LOD")
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = lille_point
	click.pressed = false
	application.drag_moved = false
	if not application._handle_formal_place_input(click):
		_fail("Lille marker click was not consumed by the Formal place layer")
		return
	await _settle_frames(5)
	if application.formal_selected_place_id() != "place:lille":
		_fail("Lille marker did not open the Formal place card")
		return
	await _save_state(application, "M05_city_selected.png")

	application._selected_place_id = ""
	application._selected_place_context_cache = {}
	application.yaw = -0.08
	application.tilt = -0.18
	await _zoom_and_settle(application, 1.0)
	var before := application.formal_map_lod_report()
	await _save_state(application, "M06_zoom_roundtrip_before.png")
	await _zoom_and_settle(application, 6.0)
	await _save_state(application, "M07_zoom_max.png")
	await _zoom_and_settle(application, 1.0)
	var after := application.formal_map_lod_report()
	_assert_roundtrip(before, after, "normal")
	await _save_state(application, "M08_zoom_roundtrip_after.png")

	application._map_player_audit_input_kind = "zoom"
	application.yaw = 0.62
	application.tilt = 1.18
	application._mark_projection_dirty()
	await _settle_map(application)
	var high_before := application.formal_map_lod_report()
	await _zoom_and_settle(application, 6.0)
	await _zoom_and_settle(application, 1.0)
	var high_after := application.formal_map_lod_report()
	_assert_roundtrip(high_before, high_after, "high_latitude")
	await _save_state(application, "M09_high_latitude_roundtrip.png")

	application._map_player_audit_input_kind = "zoom"
	application.yaw = -0.08
	application.tilt = -0.18
	application.selected_country_id = "state:country_fra"
	application._mark_projection_dirty()
	await _settle_map(application)
	var selected_before := application.formal_map_lod_report()
	await _zoom_and_settle(application, 6.0)
	await _zoom_and_settle(application, 1.0)
	var selected_after := application.formal_map_lod_report()
	_assert_roundtrip(selected_before, selected_after, "selected")
	await _save_state(application, "M10_selected_roundtrip.png")

	# Source-data gaps remain visible by contract. Capture them separately from
	# renderer regressions and persist their evidence classification beside the
	# images instead of filling them with invented modern geometry.
	var coverage_classifications: Array[Dictionary] = [
		{
			"capture": "M11_africa_east_gap_classified.png",
			"region": "Southeast Africa / Rhodesia",
			"classification": "DATE_FILTERED",
			"world_date": "1900-01-01",
			"source_valid_from": "1900-01-29",
		},
		{
			"capture": "M12_arabia_gap_classified.png",
			"region": "Arabia / Ottoman vicinity",
			"classification": "SOURCE_GAP",
			"reason": "NO_SOURCE_GEOMETRY",
		},
	]
	application.map_debug_focus_camera_on_unit_anchor(
		application._lon_lat_to_unit(Vector2(30.0, -20.0)), 2.35
	)
	await _settle_map(application)
	await _save_state(application, "M11_africa_east_gap_classified.png")
	application.map_debug_focus_camera_on_unit_anchor(
		application._lon_lat_to_unit(Vector2(45.0, 24.0)), 2.35
	)
	await _settle_map(application)
	await _save_state(application, "M12_arabia_gap_classified.png")

	await _camera_capture(application, -0.72, 0.42, 1.0, "M13_russia_normal_view.png")
	await _camera_capture(application, -1.40, 0.72, 1.0, "M14_russia_limb_view.png")
	await _camera_capture(application, -2.12, 0.38, 1.0, "M15_east_asia_limb.png")
	await _camera_capture(application, 3.08, 0.42, 1.0, "M16_dateline.png")
	await _camera_capture(application, 0.72, 1.34, 1.0, "M17_high_north.png")
	await _camera_capture(application, -0.62, -1.24, 1.0, "M18_high_south.png")

	application.yaw = -0.72
	application.tilt = 0.42
	application._set_world_zoom(1.0)
	application._mark_projection_dirty()
	await _settle_map(application)
	var exact_before := application.formal_map_lod_report(true)
	await _save_state(application, "M19_zoom_roundtrip_global_before.png")
	await _zoom_and_settle(application, 6.0)
	await _save_state(application, "M20_zoom_roundtrip_city.png")
	application.yaw = -0.72
	application.tilt = 0.42
	await _zoom_and_settle(application, 1.0)
	var exact_after := application.formal_map_lod_report(true)
	_assert_roundtrip(exact_before, exact_after, "exact_camera")
	if exact_before.get("camera_state_hash") != exact_after.get("camera_state_hash"):
		_fail("exact camera round trip changed camera-state hash")
		return
	if exact_before.get("render_state_hash") != exact_after.get("render_state_hash"):
		_fail("exact camera round trip changed render-state hash")
		return
	await _save_state(application, "M21_zoom_roundtrip_global_after.png")

	await _capture_continuous_sequence(application)
	var classification_file := FileAccess.open(
		OUTPUT_DIR.path_join("coverage_gap_classification.json"), FileAccess.WRITE
	)
	if classification_file == null:
		_fail("could not write coverage classification")
		return
	classification_file.store_string(JSON.stringify(coverage_classifications, "  "))

	var file := FileAccess.open(OUTPUT_DIR.path_join("map_lod_roundtrip_reports.json"), FileAccess.WRITE)
	if file == null:
		_fail("could not write round-trip report")
		return
	file.store_string(JSON.stringify(_reports, "  "))
	application.queue_free()
	get_tree().quit(0)


func _zoom_and_settle(application: FormalWorldApplication, zoom: float) -> void:
	application._map_player_audit_input_kind = "zoom"
	application._set_world_zoom(zoom)
	await _settle_map(application)


func _camera_capture(
	application: FormalWorldApplication,
	yaw_value: float,
	pitch_value: float,
	zoom_value: float,
	filename: String
) -> void:
	application.yaw = yaw_value
	application.tilt = pitch_value
	application._set_world_zoom(zoom_value)
	application._mark_projection_dirty()
	await _settle_map(application)
	await _save_state(application, filename)


func _settle_map(application: FormalWorldApplication) -> void:
	# Interaction LOD uses a real 220ms hold, so frame counts alone are not a
	# valid readiness signal on an uncapped capture run.
	application.angular_velocity = 0.0
	application.dragging = false
	application.set_process(true)
	await get_tree().create_timer(0.30).timeout
	var stable_render_hash := ""
	var stable_frames := 0
	for _index: int in 360:
		application.angular_velocity = 0.0
		application.set_process(true)
		application.queue_redraw()
		await get_tree().process_frame
		application._ensure_projection_cache()
		var report := application.formal_map_lod_report()
		if (
			str(report.get("cache_lod", "")) == "interactive"
			and bool(report.get("presentation_surface_complete", false))
			and not bool(report.get("detail_restore_in_progress", true))
			and int(report.get("flag_projection_cache_revision", -1))
				== int(report.get("projection_revision", -2))
			and int(report.get("flag_eligible_entity_count", 0)) > 0
			and int(report.get("drawn_flag_entity_count", 0)) > 0
			and int(report.get("interactive_flag_entity_count", 0)) > 0
			and int(report.get("interactive_surface_buffer_count", -1))
				== int(report.get("country_count", -2))
		):
			var diagnostic := application.formal_map_lod_report(true)
			var render_hash := str(diagnostic.get("render_state_hash", ""))
			stable_frames = stable_frames + 1 if render_hash == stable_render_hash else 1
			stable_render_hash = render_hash
			if stable_frames >= 2:
				return
		else:
			stable_frames = 0
			stable_render_hash = ""
	_fail("map cache did not reach a stable full state")


func _save_state(application: FormalWorldApplication, filename: String) -> void:
	application.queue_redraw()
	await _settle_frames(3)
	var report := application.formal_map_lod_report(true)
	report["capture"] = filename
	_reports.append(report)
	var image := get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		_fail("capture smaller than 1280x720: %s" % filename)
		return
	var error := image.save_png(OUTPUT_DIR.path_join(filename))
	if error != OK:
		_fail("%s: %s" % [filename, error_string(error)])


func _capture_continuous_sequence(application: FormalWorldApplication) -> void:
	var sequence_dir := OUTPUT_DIR.path_join("continuous")
	DirAccess.make_dir_recursive_absolute(sequence_dir)
	var manifest: Array[Dictionary] = []
	application.set_process(false)
	application.dragging = true
	for frame_index: int in 30:
		var phase := float(frame_index) / 29.0
		application.yaw = lerpf(-0.72, 2.95, phase)
		application.tilt = sin(phase * TAU) * 0.92
		var zoom_value := (
			lerpf(1.0, 6.0, phase / 0.5)
			if phase <= 0.5
			else lerpf(6.0, 1.0, (phase - 0.5) / 0.5)
		)
		application._set_world_zoom(zoom_value)
		application._mark_projection_dirty()
		application.queue_redraw()
		await get_tree().create_timer(0.5).timeout
		await get_tree().process_frame
		var report := application.formal_map_lod_report()
		var image := get_viewport().get_texture().get_image()
		var filename := "frame_%02d.png" % frame_index
		var error := image.save_png(sequence_dir.path_join(filename))
		if error != OK:
			_fail("continuous capture failed: %s" % error_string(error))
			return
		manifest.append({
			"frame": frame_index,
			"elapsed_seconds": frame_index * 0.5,
			"yaw": application.yaw,
			"pitch": application.tilt,
			"zoom": application.world_zoom,
			"lod": report.get("visual_lod", ""),
			"flag_batches": report.get("drawn_flag_entity_count", 0),
			"fallback_count": report.get("fallback_count", 0),
			"frame_time_usec": (
				(application.map_performance_diagnostic_report().get("last_profile", {}) as Dictionary).get(
					"frame_usec", 0
				)
			),
		})
	application.dragging = false
	application.angular_velocity = 0.0
	application._map_interaction_lod_until_usec = 0
	application._mark_projection_dirty()
	await _settle_map(application)
	var manifest_file := FileAccess.open(sequence_dir.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_fail("could not write continuous capture manifest")
		return
	manifest_file.store_string(JSON.stringify(manifest, "  "))


func _assert_roundtrip(before: Dictionary, after: Dictionary, label: String) -> void:
	var keys: Array[String] = [
		"visual_lod",
		"yaw",
		"pitch",
		"visible_political_entity_ids",
		"flag_resource_mapping_fingerprint",
		"flag_record_entity_count",
		"selected_country_id",
	]
	for key: String in keys:
		if before.get(key) != after.get(key):
			var detail := ""
			if key == "visible_political_entity_ids":
				var before_ids := before.get(key, []) as Array
				var after_ids := after.get(key, []) as Array
				var missing: Array[String] = []
				var extra: Array[String] = []
				for value: Variant in before_ids:
					if value not in after_ids:
						missing.append(str(value))
				for value: Variant in after_ids:
					if value not in before_ids:
						extra.append(str(value))
				detail = " missing=%s extra=%s" % [missing, extra]
			_fail("%s round trip changed %s before=%s after=%s%s" % [
				label, key, before.get(key), after.get(key), detail,
			])
			return
	if int(after.get("drawn_flag_entity_count", 0)) <= 0:
		_fail("%s round trip restored no drawn flags" % label)


func _settle_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame


func _fail(message: String) -> void:
	push_error("R2 M capture: %s" % message)
	get_tree().quit(1)
