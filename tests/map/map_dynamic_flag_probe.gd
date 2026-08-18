extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const TARGET_P90_USEC := 33000
const TARGET_MEDIAN_USEC := 25000
const WORLD_ZOOM_MIN := 0.74
const WORLD_ZOOM_MAX := 6.0
const HEMISPHERE_TILT_LIMIT := 1.45
const CAMERA_STATES: Array[Dictionary] = [
	{"id": "front", "yaw": 0.0, "tilt": 0.0, "zoom": 0.86},
	{"id": "rotated", "yaw": 90.0, "tilt": 18.0, "zoom": 0.96},
	{"id": "horizon", "yaw": 180.0, "tilt": 68.0, "zoom": 1.04},
	{"id": "opposite", "yaw": 270.0, "tilt": -24.0, "zoom": 0.78},
]
const RUSSIA_POLAR_STATES: Array[Dictionary] = [
	{"id": "polar_north_west", "yaw": 0.0, "tilt": 72.0, "zoom": 0.96},
	{"id": "polar_north_central", "yaw": 90.0, "tilt": 82.0, "zoom": 1.04},
	{"id": "polar_north_east", "yaw": 180.0, "tilt": 74.0, "zoom": 1.04},
	{"id": "polar_south_transition", "yaw": 240.0, "tilt": -70.0, "zoom": 0.96},
]
const REPRESENTATIVE_IDS: Array[Dictionary] = [
	{"id": "russian_empire", "label": "Russian Empire"},
	{"id": "united_states_1900", "label": "United States"},
	{"id": "brazil_1900", "label": "Brazil"},
	{"id": "cshapes_gw_750", "label": "British India"},
	{"id": "emirate_of_afghanistan", "label": "Afghanistan"},
	{"id": "cshapes_gw_625", "label": "Anglo-Egyptian Sudan"},
	{"id": "kingdom_of_belgium", "label": "small European polity"},
	{"id": "cshapes_gw_781", "label": "island polity"},
]

var _application: FormalWorldApplication
var _failures: Array[String] = []
var _report: Dictionary = {
	"frames_tested": 0,
	"geometry_set_mismatches": [],
	"triangle_count_mismatches": [],
	"intermediate_missing_surfaces": [],
	"intermediate_suspicious_triangles": [],
	"cache_round_trip": {},
	"polar": {},
	"lod_transition": {},
	"performance": {},
	"nejd": {},
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		_fail("formal scene could not load")
		print("MAP_DYNAMIC_FLAG_REPORT=%s" % JSON.stringify(_report_with_failures()))
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	_application.map_interaction_flag_lod_enabled = false
	_application.map_screen_topology_diagnostics_enabled = false
	get_root().add_child(_application)
	await _wait_frames(8)
	if _application == null or _application._countries.is_empty():
		_fail("formal scene did not build the historical roster")
		print("MAP_DYNAMIC_FLAG_REPORT=%s" % JSON.stringify(_report_with_failures()))
		quit(1)
		return

	var central_arabia := _find_repository_central_arabia_control()
	if _application.has_method("historical_central_arabia_source_audit"):
		central_arabia["source_audit"] = _application.call("historical_central_arabia_source_audit") as Dictionary
	_report["central_arabia"] = central_arabia
	if str(central_arabia.get("correct_historical_target", "")) != "emirate_of_jabal_shammar":
		_fail("CENTRAL_ARABIA_TARGET_WRONG: 1900 audit must target Jabal Shammar/Rashidi control")
	if bool(central_arabia.get("modern_saudi_substitution", true)):
		_fail("CENTRAL_ARABIA_MODERN_FALLBACK: modern Saudi identity was substituted")

	await _audit_dynamic_flag_pairs(central_arabia)
	await _audit_russia_polar_provenance()
	await _audit_cache_round_trip()
	await _audit_lod_transition()
	await _audit_performance()

	print("MAP_DYNAMIC_FLAG_REPORT=%s" % JSON.stringify(_report_with_failures()))
	_application.queue_free()
	quit(1 if not _failures.is_empty() else 0)


func _find_repository_central_arabia_control() -> Dictionary:
	var audit := _application.call("historical_central_arabia_source_audit") as Dictionary if _application.has_method("historical_central_arabia_source_audit") else {}
	return {
		"entity_id": str(audit.get("entity_id", "")),
		"correct_historical_target": str(audit.get("correct_historical_target", "emirate_of_jabal_shammar")),
		"formal_record_present": bool(audit.get("repository_record_present", false)),
		"control_record_present": bool(audit.get("repository_control_record_present", false)),
		"modern_saudi_substitution": bool(audit.get("modern_saudi_substitution", false)),
		"diagnostic": str(audit.get("status", "CONTROL_EVIDENCE_RECORDED")),
	}


func _audit_dynamic_flag_pairs(nejd: Dictionary) -> void:
	var targets: Array[Dictionary] = REPRESENTATIVE_IDS.duplicate(true)
	var nejd_id := str(nejd.get("entity_id", ""))
	if not nejd_id.is_empty():
		targets.append({"id": nejd_id, "label": "repository Nejd"})
	var pair_results: Array[Dictionary] = []
	for target: Dictionary in targets:
		var entity_id := str(target.get("id", ""))
		if not _application._country_by_id.has(entity_id):
			_fail("dynamic target missing from formal roster: %s" % entity_id)
			continue
		for camera: Dictionary in CAMERA_STATES:
			await _apply_camera(camera, false)
			var solid := await _render_phase(_application.MAP_PHASE_POLITICAL_SOLID)
			var flags := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
			var geometry_difference := _array_difference(
				solid.get("geometry_set", []) as Array,
				flags.get("geometry_set", []) as Array
			)
			var reverse_difference := _array_difference(
				flags.get("geometry_set", []) as Array,
				solid.get("geometry_set", []) as Array
			)
			var solid_fingerprint := str(solid.get("projected_fingerprint", ""))
			var flag_fingerprint := str(flags.get("projected_fingerprint", ""))
			var pair := {
				"entity_id": entity_id,
				"camera": camera,
				"solid_submitted_triangles": int((solid.get("entities", {}).get(entity_id, {}) as Dictionary).get("submitted_triangles", 0)),
				"flag_submitted_triangles": int((flags.get("entities", {}).get(entity_id, {}) as Dictionary).get("submitted_triangles", 0)),
				"solid_drawn_triangles": int((solid.get("entities", {}).get(entity_id, {}) as Dictionary).get("drawn_triangles", 0)),
				"flag_drawn_triangles": int((flags.get("entities", {}).get(entity_id, {}) as Dictionary).get("drawn_triangles", 0)),
				"geometry_set_difference": geometry_difference + reverse_difference,
				"solid_projected_fingerprint": _fingerprint_summary(solid_fingerprint),
				"flag_projected_fingerprint": _fingerprint_summary(flag_fingerprint),
				"target_material": _application.historical_flag_material_classification(entity_id),
				"flag_alpha": _application.historical_flag_texture_alpha_audit(entity_id),
			}
			pair_results.append(pair)
			_report["frames_tested"] = int(_report.get("frames_tested", 0)) + 1
			if not geometry_difference.is_empty() or not reverse_difference.is_empty():
				_report["geometry_set_mismatches"].append(pair)
				_fail("solid/flag geometry provenance differs at %s/%s" % [entity_id, str(camera.get("id", ""))])
			if solid_fingerprint != flag_fingerprint:
				_report["geometry_set_mismatches"].append(pair)
				_fail("solid/flag projected or UV fingerprint differs at %s/%s" % [entity_id, str(camera.get("id", ""))])
			var solid_entity := solid.get("entities", {}).get(entity_id, {}) as Dictionary
			var flag_entity := flags.get("entities", {}).get(entity_id, {}) as Dictionary
			if int(solid_entity.get("submitted_triangles", 0)) != int(flag_entity.get("submitted_triangles", 0)):
				_report["triangle_count_mismatches"].append(pair)
				_fail("solid/flag submitted triangle count differs at %s/%s" % [entity_id, str(camera.get("id", ""))])
			if bool(solid_entity.get("should_be_visible", false)) and int(flag_entity.get("drawn_triangles", 0)) <= 0:
				_report["intermediate_missing_surfaces"].append(pair)
				_fail("flag mode loses a visible target at %s/%s" % [entity_id, str(camera.get("id", ""))])
			if int(flag_entity.get("invalid_screen_triangles", 0)) > 0 or int(flag_entity.get("suspicious_screen_triangles", 0)) > 0:
				_report["intermediate_suspicious_triangles"].append(pair)
				_fail("flag mode has invalid/suspicious target triangles at %s/%s" % [entity_id, str(camera.get("id", ""))])
	_report["dynamic_pairs"] = pair_results


func _audit_russia_polar_provenance() -> void:
	_application.map_screen_topology_diagnostics_enabled = true
	_application.map_interaction_flag_lod_enabled = false
	var samples: Array[Dictionary] = []
	var polar_defect := false
	for camera: Dictionary in RUSSIA_POLAR_STATES:
		await _apply_camera(camera, false)
		var trace := _application.map_render_trace()
		var russia := trace.get("polities", {}).get("russian_empire", {}) as Dictionary
		var records: Array = _application._flag_screen_triangle_records.get("russian_empire", []) as Array
		var suspicious: Array[Dictionary] = []
		var invalid_provenance := 0
		for record_value: Variant in records:
			var record := record_value as Dictionary
			var component_id := str(record.get("source_component", ""))
			var source_triangle := int(record.get("source_triangle", -1))
			var component_records: Array = _application._country_surface_triangle_records.get(component_id, []) as Array
			var valid := component_id.begins_with("russian_empire:") and source_triangle >= 0 and source_triangle < component_records.size()
			if not valid:
				invalid_provenance += 1
				continue
			var source_record := component_records[source_triangle] as Dictionary
			var topology := record.get("topology", {}) as Dictionary
			if bool(topology.get("suspicious", false)) or not bool(topology.get("finite", true)):
				suspicious.append({
					"source_entity": "russian_empire",
					"source_component": component_id,
					"source_triangle": source_triangle,
					"clipped_child": int(record.get("clipped_child", -1)),
					"source_geographic_coordinates": _source_geographic_coordinates(source_record.get("points", PackedVector3Array()) as PackedVector3Array),
					"projected_coordinates": _vector2_array_to_arrays(record.get("screen", PackedVector2Array()) as PackedVector2Array),
					"clip_result": "clipped" if int(record.get("clipped_child", 0)) > 0 else "direct",
					"topology": topology,
				})
		var sample := {
			"camera": camera,
			"russia_visible_triangles": records.size(),
			"trace_invalid_projected_geometry": int(russia.get("invalid_projected_parts", 0)),
			"trace_suspicious_triangles": int(russia.get("suspicious_screen_triangles", 0)),
			"invalid_provenance": invalid_provenance,
			"suspicious_triangle_provenance": suspicious,
		}
		samples.append(sample)
		if invalid_provenance > 0 or not suspicious.is_empty() or int(russia.get("invalid_projected_parts", 0)) > 0:
			polar_defect = true
			_fail("Russia polar/horizon provenance audit found an invalid or suspicious triangle at %s" % str(camera.get("id", "")))
	_report["polar"] = {
		"entity_id": "russian_empire",
		"classification": "RENDERER_OR_SOURCE_DEFECT" if polar_defect else "LEGITIMATE_SOURCE_GEOMETRY",
		"samples": samples,
	}
	_application.map_screen_topology_diagnostics_enabled = false


func _audit_cache_round_trip() -> void:
	_application.map_interaction_flag_lod_enabled = false
	var state_a: Dictionary = {"id": "A", "yaw": 37.0, "tilt": 11.0, "zoom": 0.92}
	var states_bcd: Array[Dictionary] = [
		{"id": "B", "yaw": 121.0, "tilt": -31.0, "zoom": 1.08},
		{"id": "C", "yaw": 212.0, "tilt": 64.0, "zoom": 0.80},
		{"id": "D", "yaw": 301.0, "tilt": -58.0, "zoom": 1.02},
	]
	await _apply_camera(state_a, false)
	var initial := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	for state: Dictionary in states_bcd:
		await _apply_camera(state, false)
		await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	await _apply_camera(state_a, false)
	var returned := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	var geometry_equal: bool = initial.get("geometry_set", []) == returned.get("geometry_set", [])
	var projected_equal: bool = str(initial.get("projected_fingerprint", "")) == str(returned.get("projected_fingerprint", ""))
	var materials_equal: bool = initial.get("materials", {}) == returned.get("materials", {})
	_report["cache_round_trip"] = {
		"camera_sequence": ["A", "B", "C", "D", "A"],
		"geometry_equal": geometry_equal,
		"projected_equal": projected_equal,
		"uv_equal": projected_equal,
		"material_assignment_equal": materials_equal,
		"mismatch": [] if geometry_equal and projected_equal and materials_equal else ["A_RETURN_MISMATCH"],
	}
	if not geometry_equal or not projected_equal or not materials_equal:
		_fail("camera cache round-trip A→B→C→D→A is not deterministic")


func _audit_lod_transition() -> void:
	_application.map_interaction_flag_lod_enabled = true
	var camera: Dictionary = {"id": "lod_reference", "yaw": 41.0, "tilt": 13.0, "zoom": 0.94}
	_application.dragging = false
	await _apply_camera(camera, false)
	var before := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	_application.dragging = true
	await _apply_camera(camera, true)
	var during := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	_application.dragging = false
	_application.angular_velocity = 0.0
	await _apply_camera(camera, false)
	var first_after := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	await _wait_frames(3)
	var settled := await _render_phase(_application.MAP_PHASE_HISTORICAL_FLAGS)
	var before_ids := before.get("drawn_ids", []) as Array
	var during_ids := during.get("drawn_ids", []) as Array
	var settled_ids := settled.get("drawn_ids", []) as Array
	var transition_ok := before_ids == during_ids and before_ids == settled_ids
	var lod_probe_id := "cshapes_gw_580"
	var full_probe_buffer := _application._country_surface_triangle_buffers.get(lod_probe_id, {}) as Dictionary
	var interactive_probe_buffer := _application._interactive_country_surface_triangle_buffers.get(lod_probe_id, {}) as Dictionary
	_report["lod_transition"] = {
		"before_drag": {"lod": before.get("lod", ""), "drawn_ids": before_ids, "invalid": before.get("invalid", 0)},
		"during_drag": {"lod": during.get("lod", ""), "drawn_ids": during_ids, "invalid": during.get("invalid", 0)},
		"first_post_drag": {"lod": first_after.get("lod", ""), "drawn_ids": first_after.get("drawn_ids", []), "invalid": first_after.get("invalid", 0)},
		"settled": {"lod": settled.get("lod", ""), "drawn_ids": settled_ids, "invalid": settled.get("invalid", 0)},
		"visible_entity_set_equal": transition_ok,
		"probe_entity": lod_probe_id,
		"probe_full_source_points": (full_probe_buffer.get("points", PackedVector3Array()) as PackedVector3Array).size(),
		"probe_interactive_source_points": (interactive_probe_buffer.get("points", PackedVector3Array()) as PackedVector3Array).size(),
		"probe_during_trace": (during.get("entities", {}) as Dictionary).get(lod_probe_id, {}),
	}
	if not transition_ok:
		_fail("LOD transition changes the visible political entity set")
	_application.map_interaction_flag_lod_enabled = false


func _audit_performance() -> void:
	_application.map_interaction_flag_lod_enabled = true
	_application.map_render_phase = _application.MAP_PHASE_HISTORICAL_FLAGS
	var drag_samples: Array[int] = []
	var zoom_samples: Array[int] = []
	var category_samples: Dictionary = {}
	var interactive_counter_samples: Dictionary = {}
	var static_rebuilds_during_input: Array[Dictionary] = []
	var static_counter_baseline: Dictionary = {}
	_application.dragging = true
	for index: int in range(24):
		var camera: Dictionary = {
			"id": "drag_%d" % index,
			"yaw": float(index) * 15.0,
			"tilt": sin(float(index) * 0.37) * 54.0,
			"zoom": 0.86,
		}
		await _apply_camera(camera, true)
		var drag_profile := _record_profile_sample(drag_samples, category_samples)
		_record_interactive_profile_sample(
			drag_profile,
			interactive_counter_samples,
			static_counter_baseline,
			static_rebuilds_during_input,
			drag_samples.size() - 1
		)
	for index: int in range(16):
		var zoom_camera: Dictionary = {
			"id": "zoom_%d" % index,
			"yaw": 30.0 + float(index) * 7.0,
			"tilt": sin(float(index) * 0.29) * 32.0,
			"zoom": 0.76 + float(index % 8) * 0.06,
		}
		await _apply_camera(zoom_camera, true)
		var zoom_profile := _record_profile_sample(zoom_samples, category_samples)
		_record_interactive_profile_sample(
			zoom_profile,
			interactive_counter_samples,
			static_counter_baseline,
			static_rebuilds_during_input,
			24 + zoom_samples.size() - 1
		)
	_application.dragging = false
	var drag_stats := _statistics(drag_samples)
	var zoom_stats := _statistics(zoom_samples)
	_report["performance"] = {
		"drag": drag_stats,
		"zoom": zoom_stats,
		"categories": _category_statistics(category_samples),
		"interactive_counters": _counter_statistics(interactive_counter_samples),
		"static_counter_baseline": static_counter_baseline,
		"static_rebuilds_during_camera_input": static_rebuilds_during_input,
		"target_median_usec": TARGET_MEDIAN_USEC,
		"target_p90_usec": TARGET_P90_USEC,
	}
	if int(drag_stats.get("median_usec", 0)) > TARGET_MEDIAN_USEC or int(drag_stats.get("p90_usec", 0)) > TARGET_P90_USEC:
		_fail("drag interaction misses the stated median/P90 performance gate")
	if int(zoom_stats.get("median_usec", 0)) > TARGET_MEDIAN_USEC or int(zoom_stats.get("p90_usec", 0)) > TARGET_P90_USEC:
		_fail("zoom interaction misses the stated median/P90 performance gate")
	if not static_rebuilds_during_input.is_empty():
		_fail("camera input rebuilt static map data")


func _record_profile_sample(samples: Array[int], category_samples: Dictionary) -> Dictionary:
	var trace := _application.map_render_trace()
	var profile := trace.get("profile", {}) as Dictionary
	var value := int(profile.get("flag_cache_build_usec", profile.get("frame_usec", 0)))
	if value > 0:
		samples.append(value)
	for key_value: Variant in profile.keys():
		var key := str(key_value)
		if not key.ends_with("_usec"):
			continue
		var values: Array = category_samples.get(key, []) as Array
		values.append(int(profile.get(key, 0)))
		category_samples[key] = values
	return profile


func _record_interactive_profile_sample(
	profile: Dictionary,
	counter_samples: Dictionary,
	baseline: Dictionary,
	rebuilds: Array[Dictionary],
	sample_index: int
) -> void:
	for key: String in [
		"interactive_source_triangles_processed",
		"interactive_front_triangles",
		"interactive_behind_triangles",
		"interactive_horizon_clipped_triangles",
		"interactive_projected_vertices",
		"interactive_screen_triangles",
		"interactive_clip_temp_array_count",
		"interactive_provenance_string_lookups",
		"static_data_build_count",
		"static_uv_build_count",
		"static_provenance_build_count",
		"static_triangulation_build_count",
	]:
		var value := int(profile.get(key, 0))
		var values: Array = counter_samples.get(key, []) as Array
		values.append(value)
		counter_samples[key] = values
		if key.begins_with("static_"):
			if not baseline.has(key):
				baseline[key] = value
			elif int(baseline[key]) != value:
				rebuilds.append({
					"sample": sample_index,
					"counter": key,
					"before": int(baseline[key]),
					"after": value,
				})


func _counter_statistics(samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in samples.keys():
		var key := str(key_value)
		result[key] = _statistics(samples[key] as Array)
	return result


func _snapshot() -> Dictionary:
	var trace := _application.map_render_trace()
	var entities: Dictionary = {}
	for entity_key: Variant in (trace.get("polities", {}) as Dictionary).keys():
		var entity_id := str(entity_key)
		var source := (trace.get("polities", {}) as Dictionary).get(entity_id, {}) as Dictionary
		entities[entity_id] = {
			"should_be_visible": bool(source.get("should_be_visible", false)),
			"submitted_triangles": int(source.get("submitted_triangles", 0)),
			"drawn_triangles": int(source.get("drawn_triangles", 0)),
			"missing_visible_triangles": int(source.get("missing_visible_triangles", 0)),
			"invalid_screen_triangles": int(source.get("invalid_screen_triangles", 0)),
			"suspicious_screen_triangles": int(source.get("suspicious_screen_triangles", 0)),
			"visible_projected_area": float(source.get("visible_projected_area", 0.0)),
		}
	var drawn_ids: Array[String] = []
	for entity_id: String in entities.keys():
		if int((entities[entity_id] as Dictionary).get("drawn_triangles", 0)) > 0:
			drawn_ids.append(entity_id)
	drawn_ids.sort()
	var materials: Dictionary = {}
	for entity_id: String in _application._country_by_id.keys():
		materials[entity_id] = _application.historical_flag_material_classification(entity_id)
	return {
		"geometry_set": _application.map_render_geometry_provenance_set(),
		"projected_fingerprint": _application.map_render_projected_fingerprint(),
		"entities": entities,
		"drawn_ids": drawn_ids,
		"invalid": int((trace.get("counts", {}) as Dictionary).get("invalid_screen_triangles", 0))
			+ int((trace.get("counts", {}) as Dictionary).get("invalid_projected_geometry", 0)),
		"lod": str(_application._last_map_cache_lod),
		"materials": materials,
		"profile": trace.get("profile", {}),
	}


func _render_phase(phase: String) -> Dictionary:
	_application.map_render_phase = phase
	_application.queue_redraw()
	await _wait_frames(2)
	return _snapshot()


func _apply_camera(camera: Dictionary, interactive: bool) -> void:
	_application.yaw = deg_to_rad(float(camera.get("yaw", 0.0)))
	_application.tilt = clampf(
		deg_to_rad(float(camera.get("tilt", 0.0))),
		-HEMISPHERE_TILT_LIMIT,
		HEMISPHERE_TILT_LIMIT
	)
	_application.world_zoom = clampf(float(camera.get("zoom", 0.86)), WORLD_ZOOM_MIN, WORLD_ZOOM_MAX)
	_application.dragging = interactive
	_application.angular_velocity = 0.0
	_application._mark_projection_dirty()
	_application._ensure_projection_cache()
	_application.queue_redraw()
	await _wait_frames(2)


func _source_geographic_coordinates(points: PackedVector3Array) -> Array:
	var result: Array = []
	for point: Vector3 in points:
		var unit := point.normalized()
		result.append([
			rad_to_deg(atan2(unit.x, unit.z)),
			rad_to_deg(asin(clampf(unit.y, -1.0, 1.0))),
		])
	return result


func _vector2_array_to_arrays(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point: Vector2 in points:
		result.append([point.x, point.y])
	return result


func _array_difference(first: Array, second: Array) -> Array:
	var remaining: Dictionary = {}
	for item: Variant in second:
		remaining[str(item)] = int(remaining.get(str(item), 0)) + 1
	var result: Array = []
	for item: Variant in first:
		var key := str(item)
		var count := int(remaining.get(key, 0))
		if count > 0:
			remaining[key] = count - 1
		else:
			result.append(item)
	return result


func _fingerprint_summary(fingerprint: String) -> Dictionary:
	return {
		"hash": fingerprint.hash(),
		"bytes": fingerprint.to_utf8_buffer().size(),
		"records": fingerprint.count("\n") + 1 if not fingerprint.is_empty() else 0,
	}


func _statistics(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "median_usec": 0, "p90_usec": 0, "max_usec": 0}
	var sorted: Array = samples.duplicate()
	sorted.sort()
	return {
		"samples": sorted.size(),
		"median_usec": sorted[int(sorted.size() / 2)],
		"p90_usec": sorted[int(float(sorted.size() - 1) * 0.90)],
		"max_usec": sorted[sorted.size() - 1],
	}


func _category_statistics(category_samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in category_samples.keys():
		result[str(key_value)] = _statistics(category_samples[key_value] as Array)
	return result


func _report_with_failures() -> Dictionary:
	var output := _report.duplicate(true)
	output["failures"] = _failures.duplicate()
	return output


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("Dynamic map/flag regression: " + message)


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame
