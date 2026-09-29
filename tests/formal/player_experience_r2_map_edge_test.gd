extends SceneTree
## R2 M supplemental gate: exact historical map IDs exercise Russia, East Asia,
## Bering/dateline, and both high-latitude limbs with paired screen/UV clipping.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	application.map_full_detail_idle_restore_enabled = true
	for _index: int in 48:
		await process_frame
	application.set_formal_workspace(FormalWorldApplication.WORKSPACE_MAP)
	var cases: Array[Dictionary] = [
		{"name": "russia_normal", "yaw": -0.72, "pitch": 0.42, "entity": "russian_empire"},
		{"name": "russia_limb", "yaw": -1.40, "pitch": 0.72, "entity": "russian_empire"},
		{"name": "east_asia_limb", "yaw": -2.12, "pitch": 0.38, "entity": "empire_of_japan"},
		{"name": "dateline_bering", "yaw": 3.08, "pitch": 0.42, "entity": "russian_empire"},
		{"name": "high_north", "yaw": 0.72, "pitch": 1.34, "entity": "russian_empire"},
		{"name": "high_south", "yaw": -0.62, "pitch": -1.24, "entity": "argentina_1900"},
	]
	for camera_case: Dictionary in cases:
		var label := str(camera_case.get("name", "edge"))
		var entity_id := _map_entity_id_for_source(
			application, str(camera_case.get("entity", ""))
		)
		_check(application._country_by_id.has(entity_id), label + " uses an actual historical map entity")
		application.yaw = float(camera_case.get("yaw", 0.0))
		application.tilt = float(camera_case.get("pitch", 0.0))
		application.selected_country_id = entity_id
		application.hover_country_id = ""
		application._set_world_zoom(1.0)
		application._mark_projection_dirty()
		var direct := await _settled_report(application)
		_check_edge_report(direct, label + " direct")
		application._set_world_zoom(6.0)
		await _settled_report(application)
		application._set_world_zoom(1.0)
		application.selected_country_id = entity_id
		var roundtrip := await _settled_report(application)
		_equal(roundtrip.get("camera_state_hash"), direct.get("camera_state_hash"), label + " restores camera-state hash")
		_equal(roundtrip.get("render_state_hash"), direct.get("render_state_hash"), label + " restores render-state hash")
		_check_edge_report(roundtrip, label + " round trip")
	print("Player Experience R2 map edge: %d checks, %d failures" % [checks, failures])
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


func _settled_report(application: FormalWorldApplication) -> Dictionary:
	application.angular_velocity = 0.0
	application.dragging = false
	application.set_process(false)
	await create_timer(0.28).timeout
	var stable_render_hash := ""
	var stable_frames := 0
	for _index: int in 300:
		application.queue_redraw()
		await process_frame
		var report := application.formal_map_lod_report()
		if (
			str(report.get("cache_lod", "")) == "full"
			and bool(report.get("static_surface_complete", false))
			and not bool(report.get("detail_restore_in_progress", true))
			and int(report.get("flag_projection_cache_revision", -1))
				== int(report.get("projection_revision", -2))
			and int(report.get("flag_record_entity_count", 0)) > 0
			and int(report.get("flag_eligible_entity_count", 0)) > 0
			and int(report.get("drawn_flag_entity_count", 0)) > 0
			and int(report.get("presentation_lod_entity_count", -1)) == 0
			and int(report.get("interactive_flag_entity_count", -1)) == 0
			and int(report.get("static_surface_buffer_count", -1))
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
	return application.formal_map_lod_report(true)


func _check_edge_report(report: Dictionary, label: String) -> void:
	var edge := report.get("edge_artifacts", {}) as Dictionary
	var artifact_count := int(edge.get("screen_space_edge_artifacts", -1))
	_check(
		artifact_count == 0,
		label + " has no renderer-created edge artifacts" if artifact_count == 0 else "%s artifacts=%d report=%s" % [
			label,
			artifact_count,
			var_to_str(edge),
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
