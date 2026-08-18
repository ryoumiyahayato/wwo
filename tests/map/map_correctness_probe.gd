extends SceneTree

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const ANGLE_STEP_DEGREES := 5.0
const TRIANGULATION_AREA_TOLERANCE := 0.005
const UV_EPSILON := 0.000001
const SCREEN_TRIANGLE_AREA_EPSILON := 0.00001
const MAX_ROTATION_FRAME_USEC := 50000
const PERFORMANCE_ANGLE_STEP_DEGREES := 15.0
const MAX_INTERACTIVE_CACHE_P90_USEC := 50000
const WORLD_ZOOM_TEST_STEP := 0.10

var _application: FormalWorldApplication
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		push_error("Map correctness probe: formal scene could not load")
		quit(1)
		return
	_application = scene.instantiate() as FormalWorldApplication
	_application.map_screen_topology_diagnostics_enabled = true
	get_root().add_child(_application)
	for _frame: int in range(8):
		await process_frame
	if _application == null or _application._countries.is_empty():
		push_error("Map correctness probe: formal scene did not build historical roster")
		quit(1)
		return

	var truth: Dictionary = _application.historical_map_truth_report()
	_expect(int(truth.get("expected_polities", 0)) == 151, "expected historical polity count is 151")
	_expect(int(truth.get("loaded_polities", 0)) == 151, "all historical polities load")
	_expect(int(truth.get("missing_geometry_count", 0)) == 0, "all historical polity geometry mappings resolve")
	_expect(int(truth.get("zero_geometry_count", 0)) == 0, "no historical polity has zero geometry")
	_expect(int(truth.get("geometry_without_valid_historical_owner_count", 0)) == 0, "all geometry has a historical owner")
	_expect(int(truth.get("duplicate_or_conflicting_geometry_mapping_count", 0)) == 0, "no duplicate geometry ownership mapping")
	_expect(int(truth.get("modern_identity_fallback_count", 0)) == 0, "no modern identity fallback enters formal world")
	_expect(not bool(truth.get("formal_world_uses_modern_crosswalk", true)), "formal world does not use modern crosswalk")
	_expect(int(truth.get("multipolygon_geometry_count", 0)) > 0, "multipolygon geometry is present in the audit")
	_expect(int(truth.get("dateline_geometry_count", 0)) > 0, "dateline geometry is present in the audit")
	_expect(int(truth.get("geometry_hole_ring_count", 0)) > 0, "hole geometry is present in the audit")
	var evidence: Dictionary = _application.historical_evidence_report()
	var physical_land: Dictionary = evidence.get("physical_land", {}) as Dictionary
	_expect(str(evidence.get("snapshot_date", "")) == "1900-03-12", "historical evidence uses the formal 1900 snapshot")
	_expect(int(evidence.get("valid_historical_flag_count", 0)) == 145, "all source-backed historical flag materials resolve")
	_expect(int(evidence.get("explicit_no_verified_flag_count", 0)) == 6, "documented flag absences remain explicit neutral fills")
	_expect(int(evidence.get("resource_error_count", 0)) == 0, "historical flag resource errors are zero")
	_expect(int(evidence.get("unresolved_flag_count", 0)) == 0, "historical flag identity resolution has no unresolved records")
	_expect(int(physical_land.get("triangle_count", 0)) > 0, "physical land has camera-independent geometry")
	_expect(not bool(physical_land.get("political_ownership_attached", true)), "physical land geometry is independent of political ownership")
	_expect(
		str(physical_land.get("antarctica_source_truth", "")) == ("present" if bool(physical_land.get("source_has_antarctica", false)) else "absent"),
		"physical land Antarctica coverage is reported from source data"
	)
	var identity_audit: Dictionary = _audit_historical_identity_targets()

	var baseline := await _scan_angle(0.0)
	var baseline_trace := baseline.get("trace", {}) as Dictionary
	var baseline_counts := baseline_trace.get("counts", {}) as Dictionary
	if OS.get_cmdline_args().has("--map-baseline-only"):
		print("MAP_BASELINE_DIAGNOSTIC=%s" % JSON.stringify(baseline_trace))
		_application.queue_free()
		quit(0)
		return
	for argument: String in OS.get_cmdline_args():
		if not argument.begins_with("--map-angle-only="):
			continue
		var requested_angle := argument.trim_prefix("--map-angle-only=").to_float()
		var angle_diagnostic := await _scan_angle(requested_angle)
		print("MAP_ANGLE_DIAGNOSTIC=%s" % JSON.stringify(angle_diagnostic))
		_application.queue_free()
		quit(0)
		return
	if OS.get_cmdline_args().has("--map-navigation-only"):
		_application.map_screen_topology_diagnostics_enabled = false
		var navigation_diagnostic := await _audit_navigation_and_hit_testing()
		print("MAP_NAVIGATION_DIAGNOSTIC=%s" % JSON.stringify(navigation_diagnostic))
		_application.queue_free()
		quit(0 if _failures.is_empty() else 1)
		return
	_expect(int(baseline_counts.get("expected", 0)) == 151, "baseline trace covers every expected polity")
	_expect(int(baseline_counts.get("has_regions", 0)) == 151, "baseline trace covers every mapped region")
	_expect(int(baseline_counts.get("has_geometry", 0)) == 151, "baseline trace covers every geometry-bearing polity")
	_expect(int(baseline_counts.get("invalid_projected_geometry", 0)) == 0, "baseline projection has no invalid geometry")
	_expect(int(baseline_counts.get("zero_size_projected_bounds", 0)) == 0, "baseline projection has no zero-size bounds")
	_validate_trace(baseline_trace, "baseline")
	var static_geometry_audit := _audit_static_geometry(baseline_trace)
	_expect(int(static_geometry_audit.get("invalid_source_vertices", 0)) == 0, "all static source vertices are finite")
	_expect(int(static_geometry_audit.get("invalid_uv_vertices", 0)) == 0, "all source-to-flag UV vertices are finite")
	_expect(int(static_geometry_audit.get("out_of_range_uv_vertices", 0)) == 0, "all source-to-flag UV vertices stay in the flag domain")
	_expect(int(static_geometry_audit.get("invalid_source_triangles", 0)) == 0, "all cached source triangles have three finite vertices")
	_expect(int(static_geometry_audit.get("invalid_mesh_surface_count", 0)) == 0, "legacy screen mesh path is not used")
	_expect(int(static_geometry_audit.get("invalid_screen_triangles", 0)) == 0, "all submitted screen triangles are finite and drawable")
	_expect(int(static_geometry_audit.get("invalid_screen_provenance", 0)) == 0, "all submitted screen triangles retain source provenance")
	_expect(int(static_geometry_audit.get("suspicious_screen_triangles", 0)) == 0, "no screen triangle exceeds its source component bounds")
	_expect(int(static_geometry_audit.get("area_ratio_failures", 0)) == 0, "static triangulation preserves source planar area")
	# The detailed screen topology audit is intentionally a baseline diagnostic.
	# Rotation/performance samples must measure the product cache without building
	# thousands of diagnostic dictionaries on every camera change.
	_application.map_screen_topology_diagnostics_enabled = false

	var coverage: Dictionary = {}
	var minimum_frame: Dictionary = {}
	var maximum_frame: Dictionary = {}
	for country_value: Variant in _application._countries:
		var country := country_value as Dictionary
		var country_id := str(country.get("id", ""))
		coverage[country_id] = 0
		minimum_frame[country_id] = 999999
		maximum_frame[country_id] = -1
	var front_facing_without_submission: Array[Dictionary] = []
	var front_facing_without_draw: Array[Dictionary] = []
	var frame_summaries: Array[Dictionary] = []
	var frame_times_usec: Array[int] = []
	# The 360-degree audit must exercise the same camera path as continuous
	# player rotation.  This selects the honest interactive LOD while retaining
	# all per-polity visibility/submission/draw invariants.
	var previous_dragging: bool = _application.dragging
	_application.dragging = true
	for angle_index: int in range(ceili(360.0 / ANGLE_STEP_DEGREES)):
		var angle := float(angle_index) * ANGLE_STEP_DEGREES
		var frame := await _scan_angle(angle)
		var trace: Dictionary = frame.get("trace", {}) as Dictionary
		var counts := trace.get("counts", {}) as Dictionary
		_validate_trace(trace, "rotation_%d" % angle_index)
		var profile := trace.get("profile", {}) as Dictionary
		var frame_usec := int(profile.get("frame_usec", 0))
		if frame_usec > 0:
			frame_times_usec.append(frame_usec)
		frame_summaries.append({
			"angle_degrees": angle,
			"expected": int(counts.get("expected", 0)),
			"should_be_visible": int(counts.get("should_be_visible", 0)),
			"submitted": int(counts.get("submitted", 0)),
			"drawn": int(counts.get("drawn", 0)),
			"projected": int(counts.get("projected", 0)),
			"invalid_projected_geometry": int(counts.get("invalid_projected_geometry", 0)),
			"tiny_surface_fallback": int(counts.get("tiny_surface_fallback", 0)),
			"source_triangles": int(counts.get("source_triangles", 0)),
			"visible_source_triangles": int(counts.get("visible_source_triangles", 0)),
			"clipped_visible_triangles": int(counts.get("clipped_visible_triangles", 0)),
			"submitted_triangles": int(counts.get("submitted_triangles", 0)),
			"drawn_triangles": int(counts.get("drawn_triangles", 0)),
			"screen_triangle_count": int(counts.get("screen_triangle_count", 0)),
			"missing_visible_triangles": int(counts.get("missing_visible_triangles", 0)),
			"visible_projected_area": float(counts.get("visible_projected_area", 0.0)),
			"expected_visible_projected_area": float(counts.get("expected_visible_projected_area", 0.0)),
			"submitted_projected_area": float(counts.get("submitted_projected_area", 0.0)),
			"drawn_projected_area": float(counts.get("drawn_projected_area", 0.0)),
			"profile": profile.duplicate(true),
		})
		for polity_value: Variant in (trace.get("polities", {}) as Dictionary).values():
			var polity := polity_value as Dictionary
			var country_id := str(polity.get("id", ""))
			if bool(polity.get("should_be_visible", false)) and int(polity.get("submitted_parts", 0)) == 0:
				front_facing_without_submission.append({"angle_degrees": angle, "id": country_id})
			if bool(polity.get("should_be_visible", false)) and int(polity.get("drawn_parts", 0)) == 0:
				front_facing_without_draw.append({"angle_degrees": angle, "id": country_id})
		for country_id: String in frame.get("drawn_ids", []) as Array:
			coverage[country_id] = int(coverage.get(country_id, 0)) + 1
			minimum_frame[country_id] = mini(int(minimum_frame.get(country_id, 999999)), angle_index)
			maximum_frame[country_id] = maxi(int(maximum_frame.get(country_id, -1)), angle_index)
	_application.dragging = previous_dragging

	var never_rendered: Array[String] = []
	for country_id: String in coverage.keys():
		if int(coverage[country_id]) == 0:
			never_rendered.append(country_id)
	never_rendered.sort()
	var sparse_coverage: Array[Dictionary] = []
	for country_id: String in coverage.keys():
		if int(coverage[country_id]) < 3:
			sparse_coverage.append({
				"id": country_id,
				"frames": coverage[country_id],
				"first": minimum_frame[country_id],
				"last": maximum_frame[country_id],
		})
	sparse_coverage.sort_custom(Callable(self, "_by_id"))
	_expect(never_rendered.is_empty(), "every valid historical polity is drawn at least once during 360 degrees")
	_expect(front_facing_without_submission.is_empty(), "front-facing geometry is never discarded before draw submission")
	_expect(front_facing_without_draw.is_empty(), "front-facing submitted geometry is drawn")
	_expect(sparse_coverage.is_empty(), "no valid polity has sparse rotation coverage")
	var frame_time_stats := _frame_time_statistics(frame_times_usec)
	_expect(int(frame_time_stats.get("max_usec", 0)) <= MAX_ROTATION_FRAME_USEC, "rotation frame work stays below 50 ms")
	var navigation_audit: Dictionary = await _audit_navigation_and_hit_testing()

	var revision_before := int(_application._projection_revision)
	_application.yaw = deg_to_rad(17.0)
	_application._mark_projection_dirty()
	_application._ensure_projection_cache()
	var revision_after := int(_application._projection_revision)
	var cache_revision_after := int(_application._flag_projection_cache_revision)
	_expect(revision_after > revision_before, "camera rotation increments projection revision")
	_expect(cache_revision_after == revision_after, "camera rotation rebuilds camera-dependent map cache")
	var static_records_before_historical_rebuild: int = _application._country_surface_triangle_records.size()
	_application._rebuild_historical_political_world()
	_expect(
		static_records_before_historical_rebuild > 0 and _application._country_surface_triangle_records.is_empty(),
		"historical world rebuild clears camera-independent surface ownership cache"
	)
	_application._ensure_projection_cache()
	_expect(not _application._country_surface_triangle_records.is_empty(), "historical world rebuild repopulates surface geometry cache")

	var report := {
		"expected_polities": _application._countries.size(),
		"historical_truth": truth,
		"historical_evidence": evidence,
		"physical_land": physical_land,
		"identity_audit": identity_audit,
		"static_geometry_audit": static_geometry_audit,
		"baseline": baseline,
		"rotation": {
			"angle_step_degrees": ANGLE_STEP_DEGREES,
			"frames": ceili(360.0 / ANGLE_STEP_DEGREES),
			"never_rendered": never_rendered,
			"sparse_coverage": sparse_coverage,
			"front_facing_without_submission": front_facing_without_submission,
			"front_facing_without_draw": front_facing_without_draw,
			"frame_summaries": frame_summaries,
			"frame_time_stats": frame_time_stats,
		},
		"cache": {
			"revision_before": revision_before,
			"revision_after": revision_after,
			"cache_revision_after": cache_revision_after,
		},
		"navigation": navigation_audit,
		"failures": _failures,
	}
	print("MAP_CORRECTNESS_REPORT=%s" % JSON.stringify(report))
	_application.queue_free()
	quit(1 if not _failures.is_empty() else 0)


func _audit_historical_identity_targets() -> Dictionary:
	var expected_materials: Dictionary = {
		"emirate_of_afghanistan": "VALID_HISTORICAL_FLAG",
		"cshapes_gw_625": "EXPLICIT_NO_VERIFIED_FLAG",
		"trucial_states": "EXPLICIT_NO_VERIFIED_FLAG",
		"russian_empire": "VALID_HISTORICAL_FLAG",
		"united_states_1900": "VALID_HISTORICAL_FLAG",
		"dominion_of_canada": "VALID_HISTORICAL_FLAG",
		"cshapes_gw_781": "EXPLICIT_NO_VERIFIED_FLAG",
	}
	var records: Dictionary = {}
	for entity_key: Variant in expected_materials.keys():
		var entity_id: String = str(entity_key)
		var entity: Dictionary = _application._country_by_id.get(entity_id, {}) as Dictionary
		var material_class: String = _application.historical_flag_material_classification(entity_id)
		var record: Dictionary = {
			"exists": not entity.is_empty(),
			"historical_id": str(entity.get("historical_identity_id", entity_id)),
			"display_entity_id": str(entity.get("display_entity_id", "")),
			"geometry_feature_id": str(entity.get("geometry_feature_id", "")),
			"material_classification": material_class,
			"modern_identity_fallback": bool(entity.get("modern_identity_fallback", true)),
		}
		records[entity_id] = record
		_expect(not entity.is_empty(), "historical target exists: %s" % entity_id)
		_expect(str(entity.get("historical_identity_id", "")) == entity_id, "historical identity is retained: %s" % entity_id)
		_expect(str(entity.get("display_entity_id", "")) == entity_id, "display identity is resolved from historical entity: %s" % entity_id)
		_expect(not bool(entity.get("modern_identity_fallback", true)), "modern identity fallback is disabled: %s" % entity_id)
		_expect(material_class == str(expected_materials[entity_id]), "historical material class is explicit: %s" % entity_id)
	return records


func _audit_navigation_and_hit_testing() -> Dictionary:
	var cache_build_times_usec: Array[int] = []
	var frame_times_usec: Array[int] = []
	var invalid_frames: Array[Dictionary] = []
	var front_facing_without_submission: Array[Dictionary] = []
	var profile_samples: Array[Dictionary] = []
	var tilt_samples: Array[Dictionary] = []
	var hit_tests: Dictionary = {}
	var hit_test_angles: Dictionary = {}
	var target_ids: Array[String] = [
		"dominion_of_canada",
		"russian_empire",
		"emirate_of_afghanistan",
		"cshapes_gw_625",
		"cshapes_gw_781",
	]
	for target_id: String in target_ids:
		hit_tests[target_id] = 0
		hit_test_angles[target_id] = []
	var zoom_before: float = _application.world_zoom
	var yaw_before: float = _application.yaw
	var tilt_before: float = _application.tilt
	var center_before: Vector2 = _application._hemisphere_center
	_application._set_world_zoom(zoom_before + WORLD_ZOOM_TEST_STEP, center_before + Vector2(48.0, -32.0))
	var center_after_zoom: Vector2 = _application._hemisphere_center
	var zoom_center_error: float = center_after_zoom.distance_to(center_before)
	_expect(zoom_center_error <= 0.5, "zoom preserves the stable map viewport center")
	_expect(is_equal_approx(_application.yaw, yaw_before), "zoom preserves longitude orientation")
	_expect(is_equal_approx(_application.tilt, tilt_before), "zoom preserves latitude orientation")
	_application.world_zoom = zoom_before
	_application._reset_world_view_center()
	_application._apply_world_zoom_geometry()
	_application._mark_projection_dirty()
	var center_after_round_trip: Vector2 = _application._hemisphere_center
	var zoom_round_trip_center_error: float = center_after_round_trip.distance_to(center_before)
	_expect(zoom_round_trip_center_error <= 0.5, "zoom in/out returns to the same map center")
	_expect(is_equal_approx(_application.yaw, yaw_before), "zoom round-trip preserves longitude orientation")
	_expect(is_equal_approx(_application.tilt, tilt_before), "zoom round-trip preserves latitude orientation")
	var zoom_round_trip_audit: Dictionary = {
		"zoom_before": zoom_before,
		"zoom_after": zoom_before + WORLD_ZOOM_TEST_STEP,
		"center_before": [center_before.x, center_before.y],
		"center_after_zoom": [center_after_zoom.x, center_after_zoom.y],
		"center_after_round_trip": [center_after_round_trip.x, center_after_round_trip.y],
		"zoom_center_error_pixels": zoom_center_error,
		"round_trip_center_error_pixels": zoom_round_trip_center_error,
		"yaw_preserved": is_equal_approx(_application.yaw, yaw_before),
		"tilt_preserved": is_equal_approx(_application.tilt, tilt_before),
	}
	_application.selected_country_id = "russian_empire"
	_application._select_global_object_at(Vector2(-100.0, -100.0), true)
	var background_deselected: bool = _application.selected_country_id.is_empty()
	_expect(background_deselected, "background click clears the selected country")
	_application.dragging = true
	_application.angular_velocity = 0.0
	for angle_index: int in range(ceili(360.0 / PERFORMANCE_ANGLE_STEP_DEGREES)):
		var angle: float = float(angle_index) * PERFORMANCE_ANGLE_STEP_DEGREES
		_application.yaw = deg_to_rad(angle)
		_application._mark_projection_dirty()
		var rebuild_start_usec: int = Time.get_ticks_usec()
		_application._ensure_projection_cache()
		var rebuild_elapsed_usec: int = Time.get_ticks_usec() - rebuild_start_usec
		cache_build_times_usec.append(int(_application._map_render_profile.get("flag_cache_build_usec", rebuild_elapsed_usec)))
		frame_times_usec.append(rebuild_elapsed_usec)
		profile_samples.append({
			"angle_degrees": angle,
			"lod": _application._last_map_cache_lod,
			"base_projection_usec": int(_application._map_render_profile.get("base_projection_usec", 0)),
			"outline_cache_usec": int(_application._map_render_profile.get("outline_cache_usec", 0)),
			"flag_cache_build_usec": int(_application._map_render_profile.get("flag_cache_build_usec", 0)),
			"physical_land_projection_usec": int(_application._map_render_profile.get("physical_land_projection_usec", 0)),
			"boundary_projection_usec": int(_application._map_render_profile.get("boundary_projection_usec", 0)),
			"camera_projection_usec": int(_application._map_render_profile.get("camera_projection_usec", 0)),
			"source_triangles": int(((_application.map_render_trace().get("counts", {}) as Dictionary).get("source_triangles", 0))),
		})
		_application.queue_redraw()
		await process_frame
		await process_frame
		var trace: Dictionary = _application.map_render_trace()
		var counts: Dictionary = trace.get("counts", {}) as Dictionary
		if int(counts.get("invalid_projected_geometry", 0)) != 0 or int(counts.get("missing_visible_triangles", 0)) != 0:
			invalid_frames.append({
				"angle_degrees": angle,
				"invalid_projected_geometry": int(counts.get("invalid_projected_geometry", 0)),
				"missing_visible_triangles": int(counts.get("missing_visible_triangles", 0)),
			})
		for polity_value: Variant in (trace.get("polities", {}) as Dictionary).values():
			var polity: Dictionary = polity_value as Dictionary
			if bool(polity.get("should_be_visible", false)) and int(polity.get("submitted_parts", 0)) == 0:
				front_facing_without_submission.append({"angle_degrees": angle, "id": str(polity.get("id", ""))})
		for target_id: String in target_ids:
			var hit: bool = false
			if _application._last_map_cache_lod == "interactive":
				var compact_points: PackedVector2Array = _application._interactive_flag_screen_points.get(target_id, PackedVector2Array()) as PackedVector2Array
				for point_index: int in range(0, compact_points.size(), 3):
					if point_index + 2 >= compact_points.size():
						continue
					var point := (compact_points[point_index] + compact_points[point_index + 1] + compact_points[point_index + 2]) / 3.0
					if _application._country_id_at_projected_surface(point) == target_id:
						hit = true
						break
			else:
				var polygons: Array = _application._flag_screen_polygons.get(target_id, []) as Array
				for polygon_value: Variant in polygons:
					var polygon: PackedVector2Array = polygon_value
					if polygon.size() < 3:
						continue
					var point := Vector2.ZERO
					for vertex: Vector2 in polygon:
						point += vertex
					point /= float(polygon.size())
					if _application._country_id_at_projected_surface(point) == target_id:
						hit = true
						break
			if hit:
				hit_tests[target_id] = int(hit_tests.get(target_id, 0)) + 1
				(hit_test_angles[target_id] as Array).append(angle)
	for requested_tilt: float in [-1.35, 1.35]:
		_application.tilt = requested_tilt
		_application.yaw = 0.0
		_application._mark_projection_dirty()
		_application._ensure_projection_cache()
		_application.queue_redraw()
		await process_frame
		await process_frame
		var tilt_trace: Dictionary = _application.map_render_trace()
		var tilt_counts: Dictionary = tilt_trace.get("counts", {}) as Dictionary
		tilt_samples.append({
			"tilt_radians": requested_tilt,
			"projected_polities": int(tilt_counts.get("projected", 0)),
			"submitted_polities": int(tilt_counts.get("submitted", 0)),
			"drawn_polities": int(tilt_counts.get("drawn", 0)),
			"invalid_projected_geometry": int(tilt_counts.get("invalid_projected_geometry", 0)),
		})
		_expect(int(tilt_counts.get("invalid_projected_geometry", 0)) == 0, "high/low latitude tilt has finite projected geometry")
		_expect(int(tilt_counts.get("drawn", 0)) > 0, "high/low latitude tilt retains drawable political geometry")
	_application.dragging = false
	_application.angular_velocity = 0.0
	_application.tilt = 0.0
	_application.yaw = 0.0
	_application._mark_projection_dirty()
	_application._ensure_projection_cache()
	for target_id: String in target_ids:
		_expect(int(hit_tests.get(target_id, 0)) > 0, "projected surface hit testing resolves %s" % target_id)
	var cache_stats: Dictionary = _frame_time_statistics(cache_build_times_usec)
	var frame_stats: Dictionary = _frame_time_statistics(frame_times_usec)
	var cache_p90_usec: int = _percentile_usec(cache_build_times_usec, 0.90)
	var frame_p90_usec: int = _percentile_usec(frame_times_usec, 0.90)
	_expect(invalid_frames.is_empty(), "interactive camera frames have valid projected geometry")
	_expect(front_facing_without_submission.is_empty(), "interactive camera frames submit every front-facing polity")
	_expect(cache_p90_usec <= MAX_INTERACTIVE_CACHE_P90_USEC, "interactive camera cache P90 stays below 50 ms")
	return {
		"camera": _application.camera_navigation_report(),
		"angle_step_degrees": PERFORMANCE_ANGLE_STEP_DEGREES,
		"cache_build_usec": cache_stats,
		"cache_build_p90_usec": cache_p90_usec,
		"continuous_rebuild_usec": frame_stats,
		"continuous_rebuild_p90_usec": frame_p90_usec,
		"cache_lod": _application._last_map_cache_lod,
		"profile_samples": profile_samples,
		"zoom_round_trip": zoom_round_trip_audit,
		"background_deselected": background_deselected,
		"tilt_samples": tilt_samples,
		"invalid_frames": invalid_frames,
		"front_facing_without_submission": front_facing_without_submission,
		"hit_tests": hit_tests,
		"hit_test_angles": hit_test_angles,
	}


func _percentile_usec(values: Array[int], fraction: float) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var index: int = clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _validate_trace(trace: Dictionary, label: String) -> void:
	var counts := trace.get("counts", {}) as Dictionary
	_expect(int(counts.get("invalid_projected_geometry", 0)) == 0, "%s projection has no invalid geometry" % label)
	_expect(int(counts.get("zero_size_projected_bounds", 0)) == 0, "%s projection has no zero-size bounds" % label)
	_expect(int(counts.get("missing_visible_triangles", 0)) == 0, "%s has no visible source triangles lost before submission" % label)
	_expect(int(counts.get("invalid_screen_triangles", 0)) == 0, "%s has only valid screen triangles" % label)
	_expect(int(counts.get("invalid_screen_provenance", 0)) == 0, "%s preserves screen triangle provenance" % label)
	_expect(int(counts.get("suspicious_screen_triangles", 0)) == 0, "%s has no suspicious screen-space topology" % label)
	_expect(
		int(counts.get("clipped_visible_triangles", 0)) == int(counts.get("submitted_triangles", 0)),
		"%s clipped triangles equal submitted triangles" % label
	)
	_expect(
		int(counts.get("submitted_triangles", 0)) == int(counts.get("drawn_triangles", 0)),
		"%s submitted triangles equal drawn triangles" % label
	)
	var visible_area := float(counts.get("visible_projected_area", 0.0))
	var expected_visible_area := float(counts.get("expected_visible_projected_area", 0.0))
	var submitted_area := float(counts.get("submitted_projected_area", 0.0))
	var drawn_area := float(counts.get("drawn_projected_area", 0.0))
	var area_tolerance := maxf(0.01, expected_visible_area * 0.00001)
	_expect(absf(expected_visible_area - visible_area) <= area_tolerance, "%s projected surface area is complete" % label)
	_expect(absf(visible_area - submitted_area) <= area_tolerance, "%s visible area equals submitted area" % label)
	_expect(absf(submitted_area - drawn_area) <= area_tolerance, "%s submitted area equals drawn area" % label)
	for polity_value: Variant in (trace.get("polities", {}) as Dictionary).values():
		var polity := polity_value as Dictionary
		var country_id := str(polity.get("id", ""))
		if int(polity.get("geometry_parts", 0)) <= 0:
			continue
		_expect(int(polity.get("source_triangles", 0)) > 0, "%s has source triangles: %s" % [label, country_id])
		var ratio := float(polity.get("triangulation_area_ratio", 0.0))
		_expect(
			is_finite(ratio) and absf(ratio - 1.0) <= TRIANGULATION_AREA_TOLERANCE,
			"%s preserves source area for %s" % [label, country_id]
		)
		if not bool(polity.get("should_be_visible", false)):
			continue
		_expect(int(polity.get("visible_source_triangles", 0)) > 0, "%s visible polity has source triangles: %s" % [label, country_id])
		_expect(int(polity.get("missing_visible_triangles", 0)) == 0, "%s visible polity has no missing triangles: %s" % [label, country_id])
		_expect(
			int(polity.get("clipped_visible_triangles", 0)) == int(polity.get("submitted_triangles", 0)),
			"%s polity clipped triangles equal submitted triangles: %s" % [label, country_id]
		)
		_expect(
			int(polity.get("submitted_triangles", 0)) == int(polity.get("drawn_triangles", 0)),
			"%s polity submitted triangles equal drawn triangles: %s" % [label, country_id]
		)
		var polity_visible_area := float(polity.get("visible_projected_area", 0.0))
		var polity_expected_area := float(polity.get("expected_visible_projected_area", 0.0))
		var polity_area_tolerance := maxf(0.001, polity_expected_area * 0.00001)
		_expect(
			absf(polity_expected_area - polity_visible_area) <= polity_area_tolerance
			and absf(polity_expected_area - float(polity.get("drawn_projected_area", 0.0))) <= polity_area_tolerance,
			"%s polity surface is complete: %s" % [label, country_id]
		)


func _audit_static_geometry(baseline_trace: Dictionary) -> Dictionary:
	var audit := {
		"source_triangles": 0,
		"invalid_source_triangles": 0,
		"invalid_source_vertices": 0,
		"uv_vertices": 0,
		"invalid_uv_vertices": 0,
		"out_of_range_uv_vertices": 0,
		"area_ratio_failures": 0,
		"mesh_surface_count": 0,
		"invalid_mesh_surface_count": 0,
		"screen_triangle_count": 0,
		"invalid_screen_triangles": 0,
		"invalid_screen_provenance": 0,
		"suspicious_screen_triangles": 0,
	}
	for statistics_value: Variant in _application._country_surface_triangle_statistics.values():
		var statistics := statistics_value as Dictionary
		audit["source_triangles"] += int(statistics.get("triangle_count", 0))
		var ratio := float(statistics.get("triangulation_area_ratio", 0.0))
		if not is_finite(ratio) or absf(ratio - 1.0) > TRIANGULATION_AREA_TOLERANCE:
			audit["area_ratio_failures"] += 1
	for records_value: Variant in _application._country_surface_triangle_records.values():
		var records := records_value as Array
		for record_value: Variant in records:
			var record := record_value as Dictionary
			var points: PackedVector3Array = record.get("points", PackedVector3Array()) as PackedVector3Array
			var uvs: PackedVector2Array = record.get("uvs", PackedVector2Array()) as PackedVector2Array
			if points.size() != 3 or uvs.size() != 3:
				audit["invalid_source_triangles"] += 1
			for point: Vector3 in points:
				if not is_finite(point.x) or not is_finite(point.y) or not is_finite(point.z):
					audit["invalid_source_vertices"] += 1
			for uv: Vector2 in uvs:
				audit["uv_vertices"] += 1
				if not is_finite(uv.x) or not is_finite(uv.y):
					audit["invalid_uv_vertices"] += 1
				if uv.x < -UV_EPSILON or uv.x > 1.0 + UV_EPSILON or uv.y < -UV_EPSILON or uv.y > 1.0 + UV_EPSILON:
					audit["out_of_range_uv_vertices"] += 1
	# The R4 path submits independent source-provenance triangles directly to
	# CanvasItem.draw_polygon.  A combined ArrayMesh is intentionally forbidden:
	# it can silently reconnect unrelated MultiPolygon components.
	audit["mesh_surface_count"] = _application._country_screen_meshes.size()
	audit["invalid_mesh_surface_count"] = audit["mesh_surface_count"]
	for entity_key_value: Variant in _application._flag_screen_triangle_records.keys():
		var entity_id := str(entity_key_value)
		var records := _application._flag_screen_triangle_records.get(entity_id, []) as Array
		for record_value: Variant in records:
			audit["screen_triangle_count"] += 1
			var record := record_value as Dictionary
			var screen: PackedVector2Array = record.get("screen", PackedVector2Array()) as PackedVector2Array
			var uvs: PackedVector2Array = record.get("uvs", PackedVector2Array()) as PackedVector2Array
			var component_id := str(record.get("source_component", ""))
			var source_triangle := int(record.get("source_triangle", -1))
			var screen_valid := screen.size() == 3
			for point: Vector2 in screen:
				if not is_finite(point.x) or not is_finite(point.y):
					screen_valid = false
			for uv: Vector2 in uvs:
				if (
					not is_finite(uv.x) or not is_finite(uv.y)
					or uv.x < -UV_EPSILON or uv.x > 1.0 + UV_EPSILON
					or uv.y < -UV_EPSILON or uv.y > 1.0 + UV_EPSILON
				):
					screen_valid = false
			if screen.size() != 3 or uvs.size() != 3:
				screen_valid = false
			if screen_valid:
				var triangle_area := _screen_polygon_area(screen)
				if triangle_area <= SCREEN_TRIANGLE_AREA_EPSILON:
					screen_valid = false
			if not screen_valid:
				audit["invalid_screen_triangles"] += 1
			if component_id.is_empty() or not component_id.begins_with(entity_id + ":"):
				audit["invalid_screen_provenance"] += 1
				continue
			var component_records := _application._country_surface_triangle_records.get(component_id, []) as Array
			if source_triangle < 0 or source_triangle >= component_records.size():
				audit["invalid_screen_provenance"] += 1
			var topology: Dictionary = record.get("topology", {}) as Dictionary
			if not bool(topology.get("finite", false)) or float(topology.get("screen_area", 0.0)) <= SCREEN_TRIANGLE_AREA_EPSILON:
				audit["invalid_screen_triangles"] += 1
			if bool(topology.get("suspicious", false)):
				audit["suspicious_screen_triangles"] += 1
	return audit


func _frame_time_statistics(frame_times_usec: Array[int]) -> Dictionary:
	if frame_times_usec.is_empty():
		return {"samples": 0, "min_usec": 0, "median_usec": 0, "max_usec": 0}
	var sorted := frame_times_usec.duplicate()
	sorted.sort()
	return {
		"samples": sorted.size(),
		"min_usec": sorted[0],
		"median_usec": sorted[int(sorted.size() / 2)],
		"max_usec": sorted[sorted.size() - 1],
	}


func _scan_angle(angle_degrees: float) -> Dictionary:
	_application.yaw = deg_to_rad(angle_degrees)
	_application.tilt = 0.0
	_application._mark_projection_dirty()
	_application._ensure_projection_cache()
	_application.queue_redraw()
	await process_frame
	await process_frame
	var trace: Dictionary = _application.map_render_trace()
	var submitted_ids: Array[String] = []
	var drawn_ids: Array[String] = []
	var submitted_parts: Dictionary = {}
	var drawn_parts: Dictionary = {}
	for polity_value: Variant in (trace.get("polities", {}) as Dictionary).values():
		var polity := polity_value as Dictionary
		var country_id := str(polity.get("id", ""))
		var submitted := int(polity.get("submitted_parts", 0))
		var drawn := int(polity.get("drawn_parts", 0))
		if submitted > 0:
			submitted_ids.append(country_id)
			submitted_parts[country_id] = submitted
		if drawn > 0:
			drawn_ids.append(country_id)
			drawn_parts[country_id] = drawn
	submitted_ids.sort()
	drawn_ids.sort()
	return {
		"angle_degrees": angle_degrees,
		"submitted_polities": submitted_ids.size(),
		"drawn_polities": drawn_ids.size(),
		"submitted_parts": _sum_parts(submitted_parts),
		"drawn_parts": _sum_parts(drawn_parts),
		"submitted_ids": submitted_ids,
		"drawn_ids": drawn_ids,
		"trace": trace,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("Map correctness regression: " + message)


func _sum_parts(parts: Dictionary) -> int:
	var total := 0
	for value: Variant in parts.values():
		total += int(value)
	return total


func _screen_polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	var area := 0.0
	for index: int in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].x * polygon[next_index].y
		area -= polygon[next_index].x * polygon[index].y
	return absf(area) * 0.5


func _by_id(first: Dictionary, second: Dictionary) -> bool:
	return str(first.get("id", "")) < str(second.get("id", ""))
