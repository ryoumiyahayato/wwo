extends SceneTree
## R2 M gate: presentation LOD is reversible, imported flag eligibility survives
## camera round trips, and the city layer is sourced from Formal Spatial places.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks := 0
var failures := 0
var transition_flag_gap_frames := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in 48:
		await process_frame
	_check(application.formal_simulation.initialized, "Formal world initializes for R2 map LOD")
	_check(application.map_visual_lod() == application.MAP_VISUAL_LOD_WORLD, "default camera uses WORLD visual LOD")
	_check(not application.formal_country_labels_enabled(), "country labels default off")
	var catalog := application.formal_place_catalog_observation()
	_equal(int(catalog.get("place_count", -1)), 40, "Formal city layer contains 32 cities and 8 ports")
	var lille := application.formal_simulation.place_context_view("place:lille")
	_check(bool(lille.get("available", false)), "Lille resolves through Formal Spatial")
	_equal(lille.get("kind"), "city", "Lille place kind is authoritative")
	_equal(lille.get("economy_entity_id"), "country_fra", "Lille maps to the France aggregate")
	_check(str(lille.get("market_id", "")).begins_with("market:legacy_aggregate:"), "Lille exposes aggregate market identity without inventing a city market")
	_equal(lille.get("economic_statistics_level"), "economic_aggregate", "place card labels the aggregate statistics level")
	var detached := application.formal_simulation.place_context_view("place:lille")
	detached["display_label"] = "mutated"
	_check(str(application.formal_simulation.place_context_view("place:lille").get("display_label", "")) != "mutated", "place context is detached")

	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	application._set_world_zoom(4.81)
	_equal(application.map_visual_lod(), application.MAP_VISUAL_LOD_CITY, "CITY LOD enters at upper threshold")
	application._set_world_zoom(4.60)
	_equal(application.map_visual_lod(), application.MAP_VISUAL_LOD_CITY, "CITY LOD holds inside hysteresis band")
	application._set_world_zoom(4.34)
	_equal(application.map_visual_lod(), application.MAP_VISUAL_LOD_REGION, "CITY LOD exits below lower threshold")
	application._set_world_zoom(1.45)
	_equal(application.map_visual_lod(), application.MAP_VISUAL_LOD_REGION, "REGION LOD holds inside hysteresis band")
	application._set_world_zoom(1.34)
	_equal(application.map_visual_lod(), application.MAP_VISUAL_LOD_WORLD, "REGION LOD exits below lower threshold")
	# Retire the threshold probe's pending camera hold before the three measured
	# round trips so the first direct-state baseline is a normal full cache.
	await _visit_zoom(application, 1.0)

	var entity_ids: Array[String] = []
	for entity_value: Variant in application._country_by_id.keys():
		entity_ids.append(str(entity_value))
	entity_ids.sort()
	var camera_cases: Array[Dictionary] = [
		{"name": "normal", "yaw": -0.08, "pitch": -0.18, "selected": "country_fra", "hover": "german_empire"},
		{"name": "high_latitude", "yaw": 0.62, "pitch": 1.18, "selected": "russian_empire", "hover": "kingdom_of_sweden"},
		{"name": "oblique", "yaw": -1.04, "pitch": 0.52, "selected": "british_isles_1900", "hover": "kingdom_of_spain"},
	]
	for round_index: int in 3:
		for camera_case: Dictionary in camera_cases:
			var camera_name := str(camera_case.get("name", "camera"))
			var selected_id := _map_entity_id_for_source(application, str(camera_case.get("selected", "")))
			var hover_id := _map_entity_id_for_source(application, str(camera_case.get("hover", "")))
			if not application._country_by_id.has(selected_id):
				selected_id = entity_ids[0]
			if not application._country_by_id.has(hover_id):
				hover_id = entity_ids[1]
			application.yaw = float(camera_case.get("yaw", 0.0))
			application.tilt = float(camera_case.get("pitch", 0.0))
			application._map_player_audit_input_kind = "zoom"
			application._set_world_zoom(1.0)
			application._mark_projection_dirty()
			application.selected_country_id = selected_id
			application.hover_country_id = hover_id
			var before := await _settled_report(application)
			await _visit_zoom(application, 2.35)
			var city_report := await _visit_zoom(application, 6.0)
			_equal(city_report.get("visual_lod"), application.MAP_VISUAL_LOD_CITY, "%s round %d reaches CITY" % [camera_name, round_index + 1])
			_check(int(city_report.get("visible_political_entity_count", 0)) > 0, "%s round %d CITY keeps political context" % [camera_name, round_index + 1])
			await _visit_zoom(application, 2.35)
			await _visit_zoom(application, 1.0)
			# Compare the exact same camera + selection + hover state. Zoom changes
			# deliberately clear hover while the camera moves, so the final direct
			# state is restored before auditing the round trip.
			application.selected_country_id = selected_id
			application.hover_country_id = hover_id
			var after := await _settled_report(application)
			_equal(after.get("visual_lod"), before.get("visual_lod"), "%s round %d restores LOD" % [camera_name, round_index + 1])
			_equal(after.get("visible_political_entity_ids"), before.get("visible_political_entity_ids"), "%s round %d restores visible polity set" % [camera_name, round_index + 1])
			_equal(after.get("flag_resource_mapping_fingerprint"), before.get("flag_resource_mapping_fingerprint"), "%s round %d restores flag mapping" % [camera_name, round_index + 1])
			_equal(after.get("flag_eligible_entity_count"), before.get("flag_eligible_entity_count"), "%s round %d restores flag record coverage" % [camera_name, round_index + 1])
			_equal(after.get("camera_state_hash"), before.get("camera_state_hash"), "%s round %d restores camera-state hash" % [camera_name, round_index + 1])
			_equal(after.get("render_state_hash"), before.get("render_state_hash"), "%s round %d restores render-state hash" % [camera_name, round_index + 1])
			_equal(after.get("selected_country_id"), before.get("selected_country_id"), "%s round %d preserves selected polity" % [camera_name, round_index + 1])
			_equal(after.get("hover_country_id"), before.get("hover_country_id"), "%s round %d preserves hover polity" % [camera_name, round_index + 1])
			_check(int(after.get("drawn_flag_entity_count", 0)) > 0, "%s round %d restores drawn flags" % [camera_name, round_index + 1])
			_check(not bool(after.get("detail_restore_in_progress", true)), "%s round %d finishes detail restore" % [camera_name, round_index + 1])
			_check_edge_report(after, "%s round %d" % [camera_name, round_index + 1])

	var edge_cases: Array[Dictionary] = [
		{"name": "russia_limb", "yaw": -1.40, "pitch": 0.72, "selected": "russian_empire"},
		{"name": "east_asia_limb", "yaw": -2.12, "pitch": 0.38, "selected": "empire_of_japan"},
		{"name": "dateline_bering", "yaw": 3.08, "pitch": 0.42, "selected": "russian_empire"},
		{"name": "high_north", "yaw": 0.72, "pitch": 1.34, "selected": "russian_empire"},
		{"name": "high_south", "yaw": -0.62, "pitch": -1.24, "selected": "argentina_1900"},
	]
	for camera_case: Dictionary in edge_cases:
		var camera_name := str(camera_case.get("name", "edge"))
		application.yaw = float(camera_case.get("yaw", 0.0))
		application.tilt = float(camera_case.get("pitch", 0.0))
		var edge_entity_id := _map_entity_id_for_source(
			application, str(camera_case.get("selected", ""))
		)
		application.selected_country_id = edge_entity_id
		application.hover_country_id = ""
		application._mark_projection_dirty()
		var edge_before := await _settled_report(application)
		_check_edge_report(edge_before, camera_name + " direct")
		await _visit_zoom(application, 6.0)
		await _visit_zoom(application, 1.0)
		application.selected_country_id = edge_entity_id
		var edge_after := await _settled_report(application)
		_equal(edge_after.get("camera_state_hash"), edge_before.get("camera_state_hash"), camera_name + " restores camera-state hash")
		_equal(edge_after.get("render_state_hash"), edge_before.get("render_state_hash"), camera_name + " restores render-state hash")
		_check_edge_report(edge_after, camera_name + " round trip")

	application.map_debug_focus_camera_on_unit_anchor(
		application._lon_lat_to_unit(Vector2(3.0573, 50.6292)), 6.0
	)
	await _settled_report(application)
	_check(application.formal_place_screen_point("place:lille") != Vector2.INF, "CITY LOD projects Lille marker")
	var player_before := application.formal_simulation.player_person_id()
	var place_before := str((application.formal_simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", ""))
	application._selected_place_id = "place:lille"
	application._selected_place_context_cache = application.formal_simulation.place_context_view("place:lille")
	_equal(application.formal_simulation.player_person_id(), player_before, "place selection does not change player")
	_equal(str((application.formal_simulation.player_context_view().get("current_place", {}) as Dictionary).get("id", "")), place_before, "place observation does not move player")
	_equal(transition_flag_gap_frames, 0, "zoom round trips never expose a flagless political frame")

	print("Player Experience R2 M: %d checks, %d failures" % [checks, failures])
	application.queue_free()
	quit(1 if failures > 0 else 0)


func _map_entity_id_for_source(
	application: FormalWorldApplication,
	source_historical_id: String
) -> String:
	for entity_key: Variant in application._country_by_id.keys():
		var entity_id := str(entity_key)
		var entity := application._country_by_id.get(entity_id, {}) as Dictionary
		if str(entity.get("source_historical_id", entity_id)) == source_historical_id:
			return entity_id
	return source_historical_id


func _visit_zoom(application: FormalWorldApplication, zoom: float) -> Dictionary:
	application._map_player_audit_input_kind = "zoom"
	application._set_world_zoom(zoom)
	return await _settled_report(application)


func _settled_report(application: FormalWorldApplication) -> Dictionary:
	application.angular_velocity = 0.0
	application.dragging = false
	application.set_process(true)
	await create_timer(0.28).timeout
	var report: Dictionary = {}
	var stable_render_hash := ""
	var stable_frames := 0
	for _index: int in 180:
		application.queue_redraw()
		await process_frame
		application._ensure_projection_cache()
		# The headless display backend may coalesce CanvasItem draw notifications
		# after the compact projection is already valid. Exercise the production
		# flag submission method directly so this state audit still verifies the
		# exact screen+UV buffers and Texture2D renderer contract. The visible-window
		# watchdog independently verifies normal draw dispatch.
		application._draw_country_flag_skins()
		report = application.formal_map_lod_report()
		if (
			int(report.get("visible_political_entity_count", 0)) > 0
			and int(report.get("flag_eligible_entity_count", 0)) <= 0
		):
			transition_flag_gap_frames += 1
		if (
			str(report.get("cache_lod", "")) == "interactive"
			and bool(report.get("presentation_surface_complete", false))
			and not bool(report.get("detail_restore_in_progress", true))
			and int(report.get("flag_projection_cache_revision", -1)) == int(report.get("projection_revision", -2))
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
				return diagnostic
		else:
			stable_frames = 0
			stable_render_hash = ""
	var timeout_report := application.formal_map_lod_report(true)
	print("R2_M_SETTLE_TIMEOUT mode=%s phase=%s report=%s" % [
		application.map_observation_mode(),
		application.map_render_phase,
		var_to_str({
			"zoom": timeout_report.get("zoom"),
			"cache_lod": timeout_report.get("cache_lod"),
			"visible": timeout_report.get("visible_political_entity_count"),
			"interactive": timeout_report.get("interactive_flag_entity_count"),
			"eligible": timeout_report.get("flag_eligible_entity_count"),
			"drawn": timeout_report.get("drawn_flag_entity_count"),
			"fallback": timeout_report.get("fallback_count"),
			"detail": timeout_report.get("detail_restore_in_progress"),
		}),
	])
	return timeout_report


func _check_edge_report(report: Dictionary, label: String) -> void:
	var edge := report.get("edge_artifacts", {}) as Dictionary
	var artifact_count := int(edge.get("screen_space_edge_artifacts", -1))
	_check(
		artifact_count == 0,
		label + " has no renderer-created edge artifacts" if artifact_count == 0 else "%s edge artifacts=%d samples=%s" % [
			label,
			artifact_count,
			var_to_str(edge.get("artifact_samples", [])),
		]
	)
	_equal(int(edge.get("invalid_or_degenerate_count", -1)), 0, label + " has no invalid screen triangles")
	_equal(int(edge.get("uv_out_of_range_count", -1)), 0, label + " keeps clipped UVs in source range")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label if actual == expected else "%s | actual=%s expected=%s" % [label, var_to_str(actual), var_to_str(expected)])
