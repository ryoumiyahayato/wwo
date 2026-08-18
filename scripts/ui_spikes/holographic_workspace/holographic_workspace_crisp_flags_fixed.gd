extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1.gd"

const FLAG_TEXTURE_WIDTH: int = 144
const FLAG_TEXTURE_HEIGHT: int = 96
const ADMIN1_GLOBAL_ZOOM_START: float = 2.20
const ADMIN1_GLOBAL_LABEL_ZOOM: float = 4.10

var _flag_texture_by_entity: Dictionary = {}
var _historical_outline_polygons: Dictionary = {}
var _world_admin1_unit_cache: Dictionary = {}
var _world_admin1_country_count: int = 0

# Reused only by the interaction solid-fill submission.  These buffers are
# camera-dependent presentation data; keeping them alive avoids rebuilding a
# large PackedVector2Array/PackedColorArray on every drag/zoom draw without
# sharing any source geometry or provenance state between countries.
var _interactive_fill_points_scratch := PackedVector2Array()
var _interactive_fill_colors_scratch := PackedColorArray()
var _interactive_fill_stat_ids: Array[String] = []
var _interactive_fill_stat_counts := PackedInt32Array()
var _interactive_fill_stat_areas := PackedFloat32Array()
var _flag_draw_points_scratch := PackedVector2Array()
var _flag_draw_uvs_scratch := PackedVector2Array()
var _flag_draw_colors_scratch := PackedColorArray()
var _flag_triangle_colors_scratch := PackedColorArray()


func _ready() -> void:
	super._ready()
	var country_keys: Dictionary = {}
	for iso_value: Variant in _world_admin1_by_iso.keys():
		country_keys[str(iso_value)] = true
	_world_admin1_country_count = country_keys.size()
	_prewarm_distinctive_flag_textures()
	_mark_projection_dirty()
	queue_redraw()


func _ensure_projection_cache() -> void:
	var defer_optional_camera_layers := (
		map_interaction_flag_lod_enabled and (_camera_interaction_active() or _detail_restore_in_progress)
		or not _static_surface_build_complete
	)
	var rebuild_outlines: bool = _projection_dirty or _historical_outline_polygons.is_empty()
	super._ensure_projection_cache()
	if defer_optional_camera_layers:
		# The outline cache is a camera-dependent presentation layer. Clear the
		# stale screen polygons while moving so the next idle frame must rebuild
		# them instead of drawing an old orientation.
		_historical_outline_polygons.clear()
	elif rebuild_outlines:
		var outline_start_usec: int = Time.get_ticks_usec()
		_rebuild_merged_historical_outlines()
		_record_map_render_profile_stage("outline_cache_usec", Time.get_ticks_usec() - outline_start_usec)


func _draw_global_world() -> void:
	# Finish the optional interaction representation in small idle slices. The
	# authoritative full-resolution surface has already been built before this
	# pass; a user can therefore see a valid map while the LOD cache warms.
	_advance_interactive_surface_buffer_build()
	if not map_debug_hide_globe_grid:
		_draw_rotating_globe_grid()
	if not map_debug_hide_physical_land:
		_draw_physical_land_base()
	if map_render_phase == MAP_PHASE_LAND_ONLY:
		return
	# Static source buffers are built in bounded slices. Keep the already-valid
	# physical land visible during that warm-up instead of submitting a growing
	# partial political mesh every frame; the latter made startup spend more
	# time drawing provisional triangles than building the next source slice.
	if not _static_surface_build_complete:
		return
	_draw_solid_political_fills()
	if map_render_phase == MAP_PHASE_POLITICAL_SOLID:
		return
	if map_render_phase == MAP_PHASE_SELECTION_BORDERS:
		_draw_selected_admin1_on_globe()
		_draw_historical_entity_borders()
		return
	# During active camera input the solid political surface remains the
	# authoritative visible layer. Flag shading is optional presentation work
	# and is resumed after the camera settles; it must never remove the base
	# surface or alter its provenance.
	if map_interaction_flag_lod_enabled and _camera_interaction_active():
		# The selected fill itself is the interaction highlight.  Normal border
		# polylines are deferred until idle so stale boundary caches and thousands
		# of line draw calls cannot dominate camera input.
		return
	var flags_start_usec: int = Time.get_ticks_usec()
	_draw_country_flag_skins()
	_record_map_render_profile_stage("flags_draw_usec", Time.get_ticks_usec() - flags_start_usec)
	_draw_selected_admin1_on_globe()
	var outline_start_usec: int = Time.get_ticks_usec()
	_draw_historical_entity_borders()
	_record_map_render_profile_stage("outlines_draw_usec", Time.get_ticks_usec() - outline_start_usec)
	_draw_historical_conflicts()
	_draw_historical_entity_anchors()
	_draw_world_event_markers()
	var labels_start_usec: int = Time.get_ticks_usec()
	_draw_zoom_country_labels()
	_record_map_render_profile_stage("labels_draw_usec", Time.get_ticks_usec() - labels_start_usec)
	_draw_zoom_indicator()
	_draw_history_layer_controls()


func _draw_solid_political_fills() -> void:
	# This backing is intentionally opaque enough to remain visibly political
	# when a flag texture is dark, translucent, missing, or still transitioning
	# between LODs. A flag is a shade on this surface, never its replacement.
	var phase_alpha: float = (
		1.0
		if map_debug_opaque_political_fills
		else (0.82 if map_render_phase == MAP_PHASE_HISTORICAL_FLAGS else 0.72)
	)
	if _draw_solid_political_fills_batched(phase_alpha):
		return
	var entity_source: Dictionary = _interactive_flag_screen_points if _last_map_cache_lod == "interactive" else _flag_screen_triangle_records
	for entity_key_value: Variant in entity_source.keys():
		var entity_id := str(entity_key_value)
		var fill := _political_fill_color(entity_id, phase_alpha)
		if entity_id == selected_country_id:
			fill = Color(0.93, 0.68, 0.28, 0.94)
		var area := 0.0
		var drawn_count := 0
		if _last_map_cache_lod == "interactive":
			var compact_points: PackedVector2Array = _interactive_flag_screen_points.get(entity_id, PackedVector2Array()) as PackedVector2Array
			for point_index: int in range(0, compact_points.size(), 3):
				var triangle_area := _screen_triangle_area_at(compact_points, point_index)
				if not is_finite(triangle_area) or triangle_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
					_record_map_render_rejection(entity_id, "invalid_political_triangle")
					continue
				var polygon := PackedVector2Array([
					compact_points[point_index],
					compact_points[point_index + 1],
					compact_points[point_index + 2],
				])
				draw_colored_polygon(polygon, fill)
				area += triangle_area
				drawn_count += 1
		else:
			var records: Array = _flag_screen_triangle_records.get(entity_id, []) as Array
			for record_value: Variant in records:
				var record := record_value as Dictionary
				var polygon: PackedVector2Array = record.get("screen", PackedVector2Array()) as PackedVector2Array
				if polygon.size() != 3 or not _is_valid_screen_polygon(polygon):
					_record_map_render_rejection(entity_id, "invalid_political_triangle")
					continue
				var triangle_area := _screen_polygon_area(polygon)
				if triangle_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
					_record_map_render_rejection(entity_id, "zero_area_political_triangle")
					continue
				draw_colored_polygon(polygon, fill)
				area += triangle_area
				drawn_count += 1
		if drawn_count <= 0:
			continue
		var stage := _map_render_stage_records.get(entity_id, {}) as Dictionary
		stage["political_fill_submitted"] = true
		stage["political_fill_drawn"] = true
		_map_render_stage_records[entity_id] = stage
		# In the full flag phase the political fill is a backing layer.  Keep the
		# public submission/draw audit owned by the final flag/fallback layer so a
		# triangle is counted exactly once, while the separate fill fields still
		# document that the neutral backing exists.
		var final_flag_layer_owns_audit := (
			map_render_phase == MAP_PHASE_HISTORICAL_FLAGS
			and not (map_interaction_flag_lod_enabled and _camera_interaction_active())
		)
		if not final_flag_layer_owns_audit:
			_record_map_render_submission(entity_id, drawn_count, area)
			_record_map_render_draw(entity_id, drawn_count, area)


func _draw_solid_political_fills_batched(phase_alpha: float) -> bool:
	if map_debug_disable_batched_political_fills:
		return false
	var compact_interactive := _last_map_cache_lod == "interactive"
	var entity_source: Dictionary = _interactive_flag_screen_points if compact_interactive else _flag_screen_triangle_records
	if entity_source.is_empty():
		return false
	var points: PackedVector2Array = _interactive_fill_points_scratch
	var colors: PackedColorArray = _interactive_fill_colors_scratch
	points.resize(0)
	colors.resize(0)
	# Keep the batched draw audit in parallel primitive arrays. A Dictionary per
	# visible polity was being allocated on every interactive frame even though
	# the renderer only needs the three scalar values after submission.
	var render_stat_ids: Array[String] = _interactive_fill_stat_ids
	var render_stat_counts: PackedInt32Array = _interactive_fill_stat_counts
	var render_stat_areas: PackedFloat32Array = _interactive_fill_stat_areas
	render_stat_ids.clear()
	render_stat_counts.resize(0)
	render_stat_areas.resize(0)
	for entity_key_value: Variant in entity_source.keys():
		var entity_id := str(entity_key_value)
		var fill := _political_fill_color(entity_id, phase_alpha)
		if entity_id == selected_country_id:
			fill = Color(0.93, 0.68, 0.28, 0.94)
		var area := 0.0
		var drawn_count := 0
		if compact_interactive:
			var compact_points: PackedVector2Array = _interactive_flag_screen_points.get(entity_id, PackedVector2Array()) as PackedVector2Array
			for point_index: int in range(0, compact_points.size(), 3):
				var triangle_area := _screen_triangle_area_at(compact_points, point_index)
				if not is_finite(triangle_area) or triangle_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
					_record_map_render_rejection(entity_id, "invalid_political_triangle")
					continue
				points.append(compact_points[point_index])
				points.append(compact_points[point_index + 1])
				points.append(compact_points[point_index + 2])
				colors.append(fill)
				colors.append(fill)
				colors.append(fill)
				area += triangle_area
				drawn_count += 1
		else:
			for record_value: Variant in (_flag_screen_triangle_records.get(entity_id, []) as Array):
				var record := record_value as Dictionary
				var polygon: PackedVector2Array = record.get("screen", PackedVector2Array()) as PackedVector2Array
				if polygon.size() != 3 or not _is_valid_screen_polygon(polygon):
					_record_map_render_rejection(entity_id, "invalid_political_triangle")
					continue
				var triangle_area := _screen_polygon_area(polygon)
				if triangle_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
					_record_map_render_rejection(entity_id, "zero_area_political_triangle")
					continue
				for point: Vector2 in polygon:
					points.append(point)
					colors.append(fill)
				area += triangle_area
				drawn_count += 1
		if drawn_count > 0:
			render_stat_ids.append(entity_id)
			render_stat_counts.append(drawn_count)
		render_stat_areas.append(area)
	if points.size() < 3:
		return false
	var indices := _sequential_triangle_indices(points.size())
	if indices.is_empty():
		return false
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(),
		indices,
		points,
		colors,
		PackedVector2Array(),
		PackedInt32Array(),
		PackedFloat32Array(),
		RID(),
		-1
	)
	for stat_index: int in range(render_stat_ids.size()):
		var entity_id := render_stat_ids[stat_index]
		var drawn_count := int(render_stat_counts[stat_index])
		var area := float(render_stat_areas[stat_index])
		var stage := _map_render_stage_records.get(entity_id, {}) as Dictionary
		stage["political_fill_submitted"] = true
		stage["political_fill_drawn"] = true
		_map_render_stage_records[entity_id] = stage
		var final_flag_layer_owns_audit := (
			map_render_phase == MAP_PHASE_HISTORICAL_FLAGS
			and not (map_interaction_flag_lod_enabled and _camera_interaction_active())
		)
		if not final_flag_layer_owns_audit:
			_record_map_render_submission(entity_id, drawn_count, area)
			_record_map_render_draw(entity_id, drawn_count, area)
	return true


func _political_fill_color(entity_id: String, alpha: float) -> Color:
	if _interaction_coloring_ready and _interaction_color_index_by_entity.has(entity_id):
		var palette_index := int(_interaction_color_index_by_entity.get(entity_id, 0))
		var color: Color = INTERACTION_COLOR_PALETTE[palette_index % INTERACTION_COLOR_PALETTE.size()]
		color.a = alpha
		return color
	var hue := float(abs(entity_id.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.28, 0.64, alpha)


func _build_interaction_adjacency_coloring() -> void:
	if _interaction_coloring_ready or _countries.is_empty():
		return
	var adjacency: Dictionary = {}
	var boundary_cells: Dictionary = {}
	var entity_bounds: Dictionary = {}
	const cell_size := 1.0
	for country_value: Variant in _countries:
		var country := country_value as Dictionary
		var entity_id := str(country.get("id", ""))
		adjacency[entity_id] = {}
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for source_value: Variant in (_country_unit_polygons.get(entity_id, []) as Array):
			var source := source_value as PackedVector3Array
			# The interaction palette is a presentation cache.  Do not scan every
			# CShapes vertex during startup: high-resolution historical coastlines
			# can contain hundreds of thousands of points.  Uniform samples retain
			# a deterministic conservative neighborhood index without competing
			# with source triangulation or blocking the first usable frame.
			for point: Vector3 in _interaction_ring_samples(source, 32):
				var lon_lat := _map_unit_to_lon_lat(point)
				minimum.x = minf(minimum.x, lon_lat.x)
				minimum.y = minf(minimum.y, lon_lat.y)
				maximum.x = maxf(maximum.x, lon_lat.x)
				maximum.y = maxf(maximum.y, lon_lat.y)
				var cell := Vector2i(floori(lon_lat.x / cell_size), floori(lon_lat.y / cell_size))
				var key := "%d:%d" % [cell.x, cell.y]
				var occupants: Array = boundary_cells.get(key, []) as Array
				if not occupants.has(entity_id):
					occupants.append(entity_id)
					boundary_cells[key] = occupants
		if minimum.x != INF:
			entity_bounds[entity_id] = Rect2(minimum, maximum - minimum)
	var entity_ids: Array[String] = []
	for entity_key: Variant in adjacency.keys():
		entity_ids.append(str(entity_key))
	entity_ids.sort()
	for entity_id: String in entity_ids:
		for source_value: Variant in (_country_unit_polygons.get(entity_id, []) as Array):
			var source := source_value as PackedVector3Array
			for point: Vector3 in _interaction_ring_samples(source, 32):
				var lon_lat := _map_unit_to_lon_lat(point)
				var cell := Vector2i(floori(lon_lat.x / cell_size), floori(lon_lat.y / cell_size))
				for cell_x: int in range(cell.x - 1, cell.x + 2):
					for cell_y: int in range(cell.y - 1, cell.y + 2):
						for neighbor_value: Variant in boundary_cells.get("%d:%d" % [cell_x, cell_y], []) as Array:
							var neighbor_id := str(neighbor_value)
							if neighbor_id == entity_id:
								continue
							(adjacency[entity_id] as Dictionary)[neighbor_id] = true
							(adjacency[neighbor_id] as Dictionary)[entity_id] = true
	# A sampled boundary can miss a short shared border.  Add a cheap envelope
	# edge as a conservative adjacency hint; false positives only consume a
	# palette slot, while a known neighboring pair can never share a color.
	for first_index: int in range(entity_ids.size()):
		var first_id := entity_ids[first_index]
		var first_bounds := entity_bounds.get(first_id, Rect2()) as Rect2
		for second_index: int in range(first_index + 1, entity_ids.size()):
			var second_id := entity_ids[second_index]
			var second_bounds := entity_bounds.get(second_id, Rect2()) as Rect2
			if _interaction_bounds_are_near(first_bounds, second_bounds, 2.0):
				(adjacency[first_id] as Dictionary)[second_id] = true
				(adjacency[second_id] as Dictionary)[first_id] = true
	var remaining: Array[String] = entity_ids.duplicate()
	while not remaining.is_empty():
		var best_id := str(remaining[0])
		var best_saturation := -1
		var best_degree := -1
		for candidate_value: Variant in remaining:
			var candidate := str(candidate_value)
			var neighbor_colors: Dictionary = {}
			for neighbor_value: Variant in (adjacency[candidate] as Dictionary).keys():
				var neighbor := str(neighbor_value)
				if _interaction_color_index_by_entity.has(neighbor):
					neighbor_colors[int(_interaction_color_index_by_entity[neighbor])] = true
			var saturation := neighbor_colors.size()
			var degree := (adjacency[candidate] as Dictionary).size()
			if saturation > best_saturation or (
				saturation == best_saturation and (
					degree > best_degree or (degree == best_degree and candidate < best_id)
			)):
				best_id = candidate
				best_saturation = saturation
				best_degree = degree
		var forbidden: Dictionary = {}
		for neighbor_value: Variant in (adjacency[best_id] as Dictionary).keys():
			var neighbor := str(neighbor_value)
			if _interaction_color_index_by_entity.has(neighbor):
				forbidden[int(_interaction_color_index_by_entity[neighbor])] = true
		var selected_index := 0
		while selected_index < INTERACTION_COLOR_PALETTE.size() and forbidden.has(selected_index):
			selected_index += 1
		if selected_index >= INTERACTION_COLOR_PALETTE.size():
			# Keep the result deterministic even if the conservative spatial graph
			# contains a clique larger than the palette.
			selected_index = absi(best_id.hash()) % INTERACTION_COLOR_PALETTE.size()
			for color_index: int in range(INTERACTION_COLOR_PALETTE.size()):
				if not forbidden.has(color_index):
					selected_index = color_index
					break
		_interaction_color_index_by_entity[best_id] = selected_index
		remaining.erase(best_id)
	_interaction_adjacency_by_entity = adjacency
	_interaction_coloring_ready = true


func _interaction_ring_samples(source: PackedVector3Array, maximum_samples: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	if source.size() < 3:
		return result
	var step := maxi(1, ceili(float(source.size()) / float(maximum_samples)))
	for point_index: int in range(0, source.size(), step):
		result.append(source[point_index])
	if result.size() < 3:
		return source
	return result


func _interaction_bounds_are_near(first: Rect2, second: Rect2, tolerance: float) -> bool:
	if first.size.x <= 0.0 or first.size.y <= 0.0 or second.size.x <= 0.0 or second.size.y <= 0.0:
		return false
	return (
		first.position.x <= second.end.x + tolerance
		and second.position.x <= first.end.x + tolerance
		and first.position.y <= second.end.y + tolerance
		and second.position.y <= first.end.y + tolerance
	)


func map_debug_interaction_coloring_report() -> Dictionary:
	var same_color_edges := 0
	var edge_count := 0
	for entity_key: Variant in _interaction_adjacency_by_entity.keys():
		var entity_id := str(entity_key)
		for neighbor_key: Variant in (_interaction_adjacency_by_entity[entity_id] as Dictionary).keys():
			var neighbor_id := str(neighbor_key)
			if entity_id >= neighbor_id:
				continue
			edge_count += 1
			if int(_interaction_color_index_by_entity.get(entity_id, -1)) == int(_interaction_color_index_by_entity.get(neighbor_id, -2)):
				same_color_edges += 1
	return {
		"ready": _interaction_coloring_ready,
		"palette_size": INTERACTION_COLOR_PALETTE.size(),
		"entity_count": _interaction_color_index_by_entity.size(),
		"edge_count": edge_count,
		"adjacent_same_color_count": same_color_edges,
	}


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = clampf(inverse_lerp(HISTORY_ZOOM_MIN, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0)
	var base_alpha: float = lerpf(0.50, 0.23, zoom_mix)
	for entity_key_value: Variant in _flag_screen_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var palette: Dictionary = _resolved_flag_palette(str(entity.get("iso_a3", "")))
		var status: String = str(entity.get("status", "sovereign"))
		var provisional: bool = bool(entity.get("provisional", false))
		var alpha: float = base_alpha
		if status == "dependency" or status == "autonomous":
			alpha *= 0.82
		if provisional:
			alpha *= 0.30
		if entity_id == selected_country_id:
			alpha = maxf(alpha, 0.64)
		elif entity_id == hover_country_id:
			alpha = maxf(alpha, 0.55)
		_draw_country_flag_triangles(entity_id, palette, alpha)


func _draw_country_flag_triangles(
	entity_id: String,
	palette: Dictionary,
	alpha: float
) -> void:
	var records: Array = _flag_screen_triangle_records.get(entity_id, []) as Array
	if records.is_empty():
		_record_map_render_rejection(entity_id, "missing_screen_triangles")
		return
	var area: float = float((_map_render_stage_records.get(entity_id, {}) as Dictionary).get("visible_projected_area", 0.0))
	var material_classification := "VALID_HISTORICAL_FLAG"
	if has_method("historical_flag_material_classification"):
		material_classification = str(call("historical_flag_material_classification", entity_id))
	var texture_start_usec: int = Time.get_ticks_usec()
	var texture: ImageTexture = _flag_texture_for_entity(entity_id, palette)
	_record_map_render_profile_stage(
		"flag_resource_lookup_usec",
		int(_map_render_profile.get("flag_resource_lookup_usec", 0)) + Time.get_ticks_usec() - texture_start_usec
	)
	var stage := _map_render_stage_records.get(entity_id, {}) as Dictionary
	stage["flag_material_classification"] = material_classification
	stage["flag_submitted"] = true
	_map_render_stage_records[entity_id] = stage
	_record_map_render_submission(entity_id, records.size(), area)
	if texture == null:
		if material_classification == "EXPLICIT_NO_VERIFIED_FLAG":
			_record_map_render_fallback(entity_id, "NO_VERIFIED_FLAG_ASSET")
		else:
			_record_map_render_fallback(entity_id, "RESOURCE_ERROR")
		# Missing optional flag data must leave the valid political surface
		# drawable through the neutral solid backing layer.
		stage["flag_drawn"] = true
		_map_render_stage_records[entity_id] = stage
		_record_map_render_draw(entity_id, records.size(), area)
		return
	var points: PackedVector2Array = _flag_draw_points_scratch
	var uvs_buffer: PackedVector2Array = _flag_draw_uvs_scratch
	var colors: PackedColorArray = _flag_draw_colors_scratch
	points.resize(0)
	uvs_buffer.resize(0)
	colors.resize(0)
	for record_index: int in range(records.size()):
		var record_value: Variant = records[record_index]
		var record := record_value as Dictionary
		var polygon: PackedVector2Array = record.get("screen", PackedVector2Array()) as PackedVector2Array
		var uvs: PackedVector2Array = record.get("uvs", PackedVector2Array()) as PackedVector2Array
		if polygon.size() != 3 or uvs.size() != 3 or not _is_valid_screen_polygon(polygon):
			_record_map_render_rejection(entity_id, "invalid_flag_triangle")
			continue
		if _screen_polygon_area(polygon) <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
			_record_map_render_rejection(entity_id, "tiny_flag_triangle")
			continue
		var phase: float = float(abs(entity_id.hash()) % 997) / 997.0
		var record_colors: PackedColorArray = _flag_triangle_colors_scratch
		record_colors.resize(0)
		for uv: Vector2 in uvs:
			var cloth_wave := sin(_flag_time * (0.42 + phase * 0.18) + uv.y * TAU * 1.35 + phase * TAU)
			var secondary := sin(_flag_time * 0.24 + uv.x * TAU * 0.85 - phase * 3.0)
			var brightness := 0.96 + cloth_wave * 0.055 + secondary * 0.018
			record_colors.append(Color(brightness, brightness, brightness, alpha * (0.97 + cloth_wave * 0.025)))
		var draw_validation := _validate_flag_triangle_for_renderer(polygon, uvs, record_colors)
		if not bool(draw_validation.get("valid", false)):
			_record_map_render_rejection(entity_id, "renderer_polygon_validation")
			if _flag_draw_validation_failures.size() < 128:
				_flag_draw_validation_failures.append({
					"entity_id": entity_id,
					"record_index": record_index,
					"source_component": str(record.get("source_component", "")),
					"source_triangle": int(record.get("source_triangle", -1)),
					"clipped_child": int(record.get("clipped_child", -1)),
					"reason": str(draw_validation.get("reason", "")),
					"area": _screen_polygon_area(polygon),
					"screen": _packed_vector2_array_to_arrays(polygon),
					"uvs": _packed_vector2_array_to_arrays(uvs),
				})
			continue
		for vertex_index: int in range(3):
			points.append(polygon[vertex_index])
			uvs_buffer.append(uvs[vertex_index])
			colors.append(record_colors[vertex_index])
	var drawn_count := points.size() / 3
	if drawn_count > 0:
		if MAP_USE_EXPLICIT_TRIANGLE_SUBMISSION:
			for point_index: int in range(0, points.size(), 3):
				if point_index + 2 >= points.size():
					break
				draw_polygon(
					PackedVector2Array([points[point_index], points[point_index + 1], points[point_index + 2]]),
					PackedColorArray([colors[point_index], colors[point_index + 1], colors[point_index + 2]]),
					PackedVector2Array([uvs_buffer[point_index], uvs_buffer[point_index + 1], uvs_buffer[point_index + 2]]),
					texture
				)
		else:
			var indices := _sequential_triangle_indices(points.size())
			if indices.is_empty():
				return
			RenderingServer.canvas_item_add_triangle_array(
				get_canvas_item(),
				indices,
				points,
				colors,
				uvs_buffer,
				PackedInt32Array(),
				PackedFloat32Array(),
				texture.get_rid(),
				-1
			)
		_map_flag_draw_calls += 1
	stage["flag_drawn"] = drawn_count > 0
	_map_render_stage_records[entity_id] = stage
	_record_map_render_draw(entity_id, drawn_count, area if drawn_count > 0 else 0.0)


func _validate_flag_triangle_for_renderer(
	polygon: PackedVector2Array,
	uvs: PackedVector2Array,
	modulations: PackedColorArray
) -> Dictionary:
	if polygon.size() != 3:
		return {"valid": false, "reason": "screen_vertex_count"}
	for point: Vector2 in polygon:
		if not is_finite(point.x) or not is_finite(point.y):
			return {"valid": false, "reason": "non_finite_screen_vertex"}
	if _screen_polygon_area(polygon) <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
		return {"valid": false, "reason": "screen_area"}
	if uvs.size() != 3 or modulations.size() != 3:
		return {"valid": false, "reason": "attribute_vertex_count"}
	for uv: Vector2 in uvs:
		if not is_finite(uv.x) or not is_finite(uv.y):
			return {"valid": false, "reason": "non_finite_uv"}
	for color: Color in modulations:
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
			return {"valid": false, "reason": "non_finite_modulation"}
	# Every record reaching this method is already a source triangle (or a
	# clipped child triangle).  Re-triangulating three vertices with Geometry2D
	# on every frame was redundant and was the dominant post-input hitch.
	return {"valid": true}


func _draw_flag_polygon(
	polygon: PackedVector2Array,
	bounds: Rect2,
	palette: Dictionary,
	entity_id: String,
	alpha: float
) -> void:
	if polygon.size() < 3:
		_record_map_render_rejection(entity_id, "polygon_too_small")
		return
	if Geometry2D.triangulate_polygon(polygon).size() < 3:
		_record_map_render_rejection(entity_id, "draw_triangulation_rejected")
		return
	var texture: ImageTexture = _flag_texture_for_entity(entity_id, palette)
	if texture == null:
		# Political geometry remains drawable even when optional flag metadata is absent.
		# Use a neutral fill rather than allowing presentation data to discard the polity.
		_record_map_render_fallback(entity_id, "missing_flag_texture")
		_record_map_render_submission(entity_id)
		draw_colored_polygon(polygon, Color(0.36, 0.43, 0.50, alpha))
		_record_map_render_draw(entity_id)
		return
	var safe_width: float = maxf(bounds.size.x, 1.0)
	var safe_height: float = maxf(bounds.size.y, 1.0)
	var phase: float = float(abs(entity_id.hash()) % 997) / 997.0
	var uvs: PackedVector2Array = PackedVector2Array()
	var modulations: PackedColorArray = PackedColorArray()
	for point: Vector2 in polygon:
		var u: float = clampf((point.x - bounds.position.x) / safe_width, 0.0, 1.0)
		var v: float = clampf((point.y - bounds.position.y) / safe_height, 0.0, 1.0)
		var cloth_wave: float = sin(_flag_time * (0.42 + phase * 0.18) + v * TAU * 1.35 + phase * TAU)
		var secondary: float = sin(_flag_time * 0.24 + u * TAU * 0.85 - phase * 3.0)
		uvs.append(Vector2(clampf(u + cloth_wave * (0.010 + v * 0.010), 0.002, 0.998), v))
		var brightness: float = 0.96 + cloth_wave * 0.055 + secondary * 0.018
		modulations.append(Color(brightness, brightness, brightness, alpha * (0.97 + cloth_wave * 0.025)))
	_record_map_render_submission(entity_id)
	draw_polygon(polygon, modulations, uvs, texture)
	_record_map_render_draw(entity_id)


func _flag_texture_for_entity(entity_id: String, palette: Dictionary) -> ImageTexture:
	if _flag_texture_by_entity.has(entity_id):
		return _flag_texture_by_entity.get(entity_id) as ImageTexture
	var colors: PackedColorArray = palette.get("colors", PackedColorArray()) as PackedColorArray
	if colors.is_empty():
		return null
	var pattern: String = _distinctive_pattern_for_entity(entity_id, str(palette.get("pattern", "solid")))
	var image: Image = Image.create(FLAG_TEXTURE_WIDTH, FLAG_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for y: int in range(FLAG_TEXTURE_HEIGHT):
		var v: float = (float(y) + 0.5) / float(FLAG_TEXTURE_HEIGHT)
		for x: int in range(FLAG_TEXTURE_WIDTH):
			var u: float = (float(x) + 0.5) / float(FLAG_TEXTURE_WIDTH)
			var color: Color = _distinctive_flag_color(pattern, colors, u, v)
			var weave: float = 0.975 + 0.025 * sin(float(y) * 0.73) * sin(float(x) * 0.19)
			image.set_pixel(x, y, Color(color.r * weave, color.g * weave, color.b * weave, 1.0))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_flag_texture_by_entity[entity_id] = texture
	return texture


func _distinctive_pattern_for_entity(entity_id: String, fallback: String) -> String:
	match entity_id:
		"british_isles_1900", "british_empire_overseas":
			return "union"
		"united_states_1900", "united_states_overseas":
			return "stripes_canton"
		"qing_empire":
			return "dragon_disc"
		"empire_of_japan":
			return "sun_disc"
		"ottoman_empire":
			return "crescent"
		"austria_hungary":
			return "dual_monarchy"
		"kingdom_of_nepal":
			return "double_pennant"
		"kingdom_of_bhutan":
			return "dragon_diagonal"
		_:
			return fallback


func _distinctive_flag_color(pattern: String, colors: PackedColorArray, u: float, v: float) -> Color:
	var count: int = colors.size()
	var c0: Color = colors[0]
	var c1: Color = colors[mini(1, count - 1)]
	var c2: Color = colors[mini(2, count - 1)]
	var c3: Color = colors[mini(3, count - 1)]
	if pattern == "union":
		var color: Color = c0
		var diagonal_a: float = absf(v - u * 0.67 - 0.165)
		var diagonal_b: float = absf(v + u * 0.67 - 0.835)
		if diagonal_a < 0.105 or diagonal_b < 0.105:
			color = c1
		if diagonal_a < 0.035 or diagonal_b < 0.035:
			color = c2
		if absf(u - 0.5) < 0.115 or absf(v - 0.5) < 0.17:
			color = c1
		if absf(u - 0.5) < 0.050 or absf(v - 0.5) < 0.075:
			color = c2
		return color
	if pattern == "stripes_canton":
		var stripe: Color = c0 if int(floor(v * 13.0)) % 2 == 0 else c1
		if u < 0.42 and v < 0.54:
			var star_u: float = fposmod(u * 13.0, 1.0)
			var star_v: float = fposmod(v * 11.0, 1.0)
			var star_cell: Vector2 = Vector2(star_u, star_v) - Vector2(0.5, 0.5)
			return c1 if star_cell.length() < 0.075 else c2
		return stripe
	if pattern == "dragon_disc":
		var center_distance: float = Vector2(u, v).distance_to(Vector2(0.53, 0.50))
		if center_distance < 0.24:
			var angle: float = atan2(v - 0.5, u - 0.53)
			var spiral: float = absf(sin(angle * 2.5 + center_distance * 22.0))
			return c2 if center_distance < 0.07 else c1.lerp(c2, spiral * 0.34)
		return c0
	if pattern == "sun_disc":
		return c1 if Vector2(u, v).distance_to(Vector2(0.5, 0.5)) < 0.245 else c0
	if pattern == "crescent":
		var outer: bool = Vector2(u, v).distance_to(Vector2(0.48, 0.5)) < 0.25
		var inner: bool = Vector2(u, v).distance_to(Vector2(0.56, 0.47)) < 0.205
		var star: bool = Vector2(u, v).distance_to(Vector2(0.70, 0.50)) < 0.055
		return c1 if (outer and not inner) or star else c0
	if pattern == "dual_monarchy":
		if u < 0.5:
			return c2 if v < 0.30 or v > 0.70 else c1
		if v < 0.30:
			return c2
		if v > 0.70:
			return Color(0.22, 0.43, 0.30, 1.0)
		return c3
	if pattern == "double_pennant":
		var upper_triangle: bool = v < 0.49 and u < 0.78 - v * 0.45
		var lower_triangle: bool = v >= 0.43 and u < 0.88 - (v - 0.43) * 0.55
		var border_band: bool = (upper_triangle or lower_triangle) and (u < 0.045 or absf(v - 0.49) < 0.035)
		if border_band:
			return c1
		if upper_triangle or lower_triangle:
			var emblem_center: Vector2 = Vector2(0.28, 0.27 if v < 0.49 else 0.70)
			return c2 if Vector2(u, v).distance_to(emblem_center) < 0.075 else c0
		return Color(0.035, 0.055, 0.065, 1.0)
	if pattern == "dragon_diagonal":
		var base: Color = c0 if u + v < 1.0 else c1
		var body: float = absf(v - (0.76 - u * 0.52 + sin(u * 12.0) * 0.035))
		return c2 if body < 0.045 and u > 0.20 and u < 0.82 else base
	return _flag_pattern_color(pattern, colors, u, v)


func _prewarm_distinctive_flag_textures() -> void:
	var key_entities: Array[String] = [
		"country_fra", "german_empire", "british_isles_1900", "austria_hungary",
		"russian_empire", "ottoman_empire", "qing_empire", "empire_of_japan",
		"united_states_1900", "kingdom_of_nepal", "kingdom_of_bhutan"
	]
	for entity_id: String in key_entities:
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		if not entity.is_empty():
			_flag_texture_for_entity(entity_id, _resolved_flag_palette(str(entity.get("iso_a3", ""))))


func _flag_texture_signature(entity_id: String) -> String:
	var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
	if entity.is_empty():
		return ""
	var texture: ImageTexture = _flag_texture_for_entity(entity_id, _resolved_flag_palette(str(entity.get("iso_a3", ""))))
	if texture == null:
		return ""
	var image: Image = texture.get_image()
	var samples: Array[Vector2i] = [Vector2i(14, 16), Vector2i(72, 16), Vector2i(126, 16), Vector2i(24, 48), Vector2i(72, 48), Vector2i(120, 72)]
	var parts: PackedStringArray = PackedStringArray()
	for point: Vector2i in samples:
		parts.append(image.get_pixel(point.x, point.y).to_html(false))
	return "-".join(parts)


func _screen_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var minimum: Vector2 = polygon[0]
	var maximum: Vector2 = polygon[0]
	for point: Vector2 in polygon:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _rebuild_merged_historical_outlines() -> void:
	_historical_outline_polygons.clear()
	for entity_key_value: Variant in _country_screen_boundary_segments.keys():
		var entity_id: String = str(entity_key_value)
		var segments: Array[PackedVector2Array] = []
		for segment_value: Variant in (_country_screen_boundary_segments.get(entity_id, []) as Array):
			var segment: PackedVector2Array = segment_value
			if segment.size() >= 2:
				segments.append(segment)
		_historical_outline_polygons[entity_id] = segments


func _history_border_pulse_value(entity_id: String) -> float:
	var phase: float = float(abs(entity_id.hash()) % 997) / 997.0
	return 0.5 + 0.5 * sin(_flag_time * (0.43 + phase * 0.16) + phase * TAU)


func _historical_border_geometry_signature() -> String:
	var point_count: int = 0
	var checksum_x: int = 0
	var checksum_y: int = 0
	for entity_value: Variant in _historical_outline_polygons.keys():
		for polygon_value: Variant in (_historical_outline_polygons.get(str(entity_value), []) as Array):
			for point: Vector2 in (polygon_value as PackedVector2Array):
				point_count += 1
				checksum_x += int(round(point.x * 10.0))
				checksum_y += int(round(point.y * 10.0))
	return "%d:%d:%d" % [point_count, checksum_x, checksum_y]


func _draw_historical_entity_borders() -> void:
	var close_mix := clampf(inverse_lerp(1.0, 3.0, world_zoom), 0.0, 1.0)
	for entity_key_value: Variant in _historical_outline_polygons.keys():
		var entity_id: String = str(entity_key_value)
		var entity: Dictionary = _country_by_id.get(entity_id, {}) as Dictionary
		var status: String = str(entity.get("status", "sovereign"))
		var provisional: bool = bool(entity.get("provisional", false))
		var pulse: float = _history_border_pulse_value(entity_id)
		var color: Color = Color(0.18, 0.28, 0.29, lerpf(0.30, 0.52, close_mix) + pulse * 0.025)
		var width: float = lerpf(0.58, 1.14, close_mix)
		if status == "dependency" or status == "autonomous":
			color = Color(0.28, 0.32, 0.27, color.a * 0.80)
			width = lerpf(0.50, 0.90, close_mix)
		elif status == "contested" or status == "fragmented":
			color = Color(0.39, 0.28, 0.22, color.a * 0.92)
			width = lerpf(0.62, 1.20, close_mix)
		if provisional:
			color.a *= 0.45
		if entity_id == hover_country_id:
			color = Color(0.62, 0.80, 0.75, lerpf(0.58, 0.78, close_mix))
			width = lerpf(0.90, 1.45, close_mix)
		if entity_id == selected_country_id:
			color = Color(0.88, 0.66, 0.28, 0.92)
			width = lerpf(1.50, 1.90, close_mix)
		var stage := _map_render_stage_records.get(entity_id, {}) as Dictionary
		stage["border_drawn"] = true
		_map_render_stage_records[entity_id] = stage
		for polygon_value: Variant in (_historical_outline_polygons.get(entity_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			if status == "dependency" or status == "autonomous" or provisional:
				_draw_dashed_polyline(polygon, color, width, 6.0, 4.0)
			else:
				draw_polyline(polygon, color, width, false)


func _admin1_unit_lines_for_iso(iso: String) -> Array:
	if _world_admin1_unit_cache.has(iso):
		return _world_admin1_unit_cache.get(iso, []) as Array
	var output: Array = []
	for record_value: Variant in (_world_admin1_by_iso.get(iso, []) as Array):
		var record: Dictionary = record_value as Dictionary
		var unit_lines: Array = []
		for polygon_value: Variant in (record.get("runtime_polygons", []) as Array):
			unit_lines.append(_to_unit_line(polygon_value as PackedVector2Array))
		output.append({"record": record, "unit_lines": unit_lines})
	_world_admin1_unit_cache[iso] = output
	return output


func _selected_global_territory_iso() -> String:
	if not selected_historical_territory_iso.is_empty():
		return selected_historical_territory_iso
	var territories: Array = _history_territories_by_entity.get(selected_country_id, []) as Array
	if territories.is_empty():
		return ""
	var config: Dictionary = _history_entity_by_id.get(selected_country_id, {}) as Dictionary
	for core_value: Variant in (config.get("core_members", []) as Array):
		var core_iso: String = str(core_value).to_upper()
		for territory_value: Variant in territories:
			if str((territory_value as Dictionary).get("iso_a3", "")) == core_iso:
				return core_iso
	return str((territories[0] as Dictionary).get("iso_a3", ""))


func _draw_selected_admin1_on_globe() -> void:
	if world_zoom < ADMIN1_GLOBAL_ZOOM_START or selected_country_id.is_empty():
		return
	var iso: String = _selected_global_territory_iso()
	if iso.is_empty():
		return
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	var alpha: float = lerpf(0.16, 0.48, clampf(inverse_lerp(ADMIN1_GLOBAL_ZOOM_START, HISTORY_ZOOM_MAX, world_zoom), 0.0, 1.0))
	var labels_drawn: int = 0
	for entry_value: Variant in _admin1_unit_lines_for_iso(iso):
		var entry: Dictionary = entry_value as Dictionary
		var record: Dictionary = entry.get("record", {}) as Dictionary
		for unit_line_value: Variant in (entry.get("unit_lines", []) as Array):
			var unit_line: PackedVector3Array = unit_line_value
			for segment: PackedVector2Array in _project_unit_line(unit_line, basis):
				draw_polyline(segment, Color(0.90, 0.81, 0.53, alpha), 0.85, true)
		if world_zoom >= ADMIN1_GLOBAL_LABEL_ZOOM and labels_drawn < 26 and int(record.get("label_rank", 6)) <= 4:
			var label_value: Variant = _lon_lat_from_record(record, "label_lon_lat")
			if label_value != null:
				var rotated: Vector3 = basis * _lon_lat_to_unit(label_value as Vector2)
				if rotated.z >= 0.0:
					_draw_label(_sphere_screen(rotated) + Vector2(5.0, 3.0), _world_admin1_short_name(record), 9, Color(0.85, 0.84, 0.68, 0.78))
					labels_drawn += 1


func _go_back() -> void:
	if world_mode == WORLD_HISTORICAL_ENTITY_FOCUS and space_level == CITY:
		var count: int = (_world_admin1_by_iso.get(selected_historical_territory_iso, []) as Array).size()
		if count <= 1:
			space_level = WORLD
			selected_world_admin1_id = ""
			queue_redraw()
			return
	super._go_back()
