extends "res://scripts/ui_spikes/holographic_workspace/holographic_workspace_final.gd"

const WORLD_ZOOM_MIN: float = 0.74
const WORLD_ZOOM_MAX: float = 6.0
const WORLD_ZOOM_STEP: float = 0.10
const COUNTRY_LABEL_FADE_START: float = 1.18
const COUNTRY_LABEL_FADE_END: float = 2.40
const FLAG_TIMER_STEP: float = 0.12
const MAP_PROJECTED_AREA_EPSILON: float = 0.001
const MAP_SCREEN_DUPLICATE_DISTANCE: float = 0.0001
const MAP_TINY_SURFACE_SIZE: float = 3.0
const MAP_MINIMUM_SURFACE_MARKER_RADIUS: float = 1.15
const MAP_HORIZON_SURFACE_DEPTH_EPSILON: float = 0.02
const MAP_TRIANGLE_DEPTH_EPSILON: float = 0.0001
const MAP_TRIANGLE_AREA_EPSILON: float = 0.00001
# A CShapes ring can be area-correct in lon/lat while still producing a very
# large straight chord after it is projected onto the globe.  This rule is
# deliberately independent of country identity and latitude: a valid source
# triangle must be small enough everywhere that its projected edge cannot
# become a cross-ocean wedge at a polar or horizon view.
const MAP_MAX_SOURCE_TRIANGLE_EDGE_DEGREES: float = 18.0
const MAP_SOURCE_TRIANGLE_SUBDIVISION_MIN_AREA: float = 20.0
const MAP_MAX_SOURCE_TRIANGLE_SUBDIVISION_DEPTH: int = 3
const MAP_TRIANGULATION_EDGE_SAMPLE_COUNT: int = 7
const MAP_HORIZON_SUBPIXEL_AREA_EPSILON: float = 0.05
const MAP_PHYSICAL_SCREEN_AREA_EPSILON: float = 0.25
const MAP_SCREEN_TRIANGLE_AREA_EPSILON: float = 0.05
const MAP_SCREEN_FRAGMENT_AREA_EPSILON: float = 0.10
const MAP_INTERACTION_LOD_HOLD_USEC: int = 220000
const MAP_STATIC_SURFACE_BUILD_BUDGET_USEC: int = 12000
const MAP_INTERACTIVE_SURFACE_BUILD_BUDGET_USEC: int = 4000
const MAP_DETAIL_RESTORE_BUDGET_USEC: int = 8000
const MAP_USE_EXPLICIT_TRIANGLE_SUBMISSION: bool = true
const INTERACTIVE_SURFACE_RING_POINTS: int = 64
const INTERACTIVE_BOUNDARY_RING_POINTS: int = 96
const INTERACTIVE_PHYSICAL_RING_POINTS: int = 64
const MAP_PHASE_LAND_ONLY: String = "land"
const MAP_PHASE_POLITICAL_SOLID: String = "political"
const MAP_PHASE_SELECTION_BORDERS: String = "borders"
const MAP_PHASE_HISTORICAL_FLAGS: String = "flags"
const MAP_PLAYER_AUDIT_SAMPLE_STRIDE: int = 4
const INTERACTION_COLOR_PALETTE: Array[Color] = [
	Color("#5B7891"),
	Color("#9A6E72"),
	Color("#718F72"),
	Color("#9A875B"),
	Color("#7E7198"),
	Color("#5C8A87"),
	Color("#A47759"),
	Color("#837E68"),
	Color("#6E879F"),
	Color("#A27B87"),
	Color("#7B9C84"),
	Color("#B09662"),
	Color("#8A7FA8"),
	Color("#6A9694"),
	Color("#B07F5F"),
	Color("#938E78"),
]

var world_zoom: float = 0.86
var map_render_phase: String = MAP_PHASE_HISTORICAL_FLAGS
var map_topology_validation_enabled: bool = false
var map_screen_topology_diagnostics_enabled: bool = false
var map_debug_hide_physical_boundaries: bool = false
var map_debug_hide_physical_land: bool = false
var map_debug_disable_batched_political_fills: bool = false
var map_debug_hide_globe_grid: bool = false
var map_debug_opaque_political_fills: bool = false
var map_debug_build_timing: bool = false
var map_debug_source_triangle_max_edge_degrees: float = MAP_MAX_SOURCE_TRIANGLE_EDGE_DEGREES
var map_debug_source_triangle_max_depth: int = MAP_MAX_SOURCE_TRIANGLE_SUBDIVISION_DEPTH
# During active camera input the product may defer the expensive flag shading
# pass, but it must keep the same validated political surface underneath.
# This is deliberately a presentation/LOD switch; it never changes ownership
# or source geometry.
var map_interaction_flag_lod_enabled: bool = true
var _base_hemisphere_radius: float = 220.0
var _flag_time: float = 0.0
var _flag_palettes: Dictionary = {}
var _flag_screen_polygons: Dictionary = {}
var _flag_screen_triangle_records: Dictionary = {}
var _interactive_flag_screen_points: Dictionary = {}
var _interactive_flag_screen_components: Dictionary = {}
var _interactive_flag_screen_component_indices: Dictionary = {}
var _interactive_flag_screen_source_triangles: Dictionary = {}
var _interactive_flag_screen_clipped_children: Dictionary = {}
var _flag_screen_bounds: Dictionary = {}
var _country_screen_boundary_segments: Dictionary = {}
var _country_surface_triangle_polygons: Dictionary = {}
var _country_surface_triangle_records: Dictionary = {}
var _country_surface_triangle_statistics: Dictionary = {}
var _country_surface_triangle_buffers: Dictionary = {}
var _interactive_country_surface_triangle_buffers: Dictionary = {}
var _interactive_country_boundary_sources: Dictionary = {}
var _country_flag_uv_bounds: Dictionary = {}
var _country_flag_uv_reference_longitudes: Dictionary = {}
var _country_screen_meshes: Dictionary = {}
var _country_screen_triangle_counts: Dictionary = {}
var _map_render_stage_records: Dictionary = {}
var _map_render_submitted_parts: Dictionary = {}
var _map_render_drawn_parts: Dictionary = {}
var _map_render_submitted_triangles: Dictionary = {}
var _map_render_drawn_triangles: Dictionary = {}
var _map_render_submitted_areas: Dictionary = {}
var _map_render_drawn_areas: Dictionary = {}
var _map_render_rejections: Dictionary = {}
var _map_render_fallbacks: Dictionary = {}
var _flag_projection_cache_revision: int = -1
var _map_render_profile: Dictionary = {}
var _map_profile_static_triangulation_usec: int = 0
var _map_profile_static_triangulation_total_usec: int = 0
var _static_data_build_count: int = 0
var _static_uv_build_count: int = 0
var _static_provenance_build_count: int = 0
var _static_triangulation_build_count: int = 0
var _static_surface_build_cursor: int = 0
var _static_surface_build_complete: bool = false
var _interactive_surface_build_cursor: int = 0
var _interactive_surface_build_complete: bool = false
var _static_projection_cache_revision: int = -1
var _detail_restore_in_progress: bool = false
var _detail_restore_cursor: int = 0
var _detail_restore_revision: int = -1
var _interactive_source_triangles_processed: int = 0
var _interactive_front_triangles: int = 0
var _interactive_behind_triangles: int = 0
var _interactive_horizon_clipped_triangles: int = 0
var _interactive_projected_vertices: int = 0
var _interactive_screen_triangles: int = 0
var _interactive_clip_temp_array_count: int = 0
var _interactive_provenance_string_lookups: int = 0
var _interactive_clip_points_scratch := PackedVector3Array()
var _interactive_clip_screen_scratch := PackedVector2Array()
var _interactive_clip_output_scratch := PackedVector2Array()
var _physical_land_triangle_records: Array[PackedVector3Array] = []
var _interactive_physical_land_triangle_records: Array[PackedVector3Array] = []
var _interactive_physical_land_polygons: Array[PackedVector3Array] = []
var _interactive_physical_land_holes: Array = []
var _physical_land_screen_triangles: Array[PackedVector2Array] = []
var _physical_land_screen_boundary_segments: Array[PackedVector2Array] = []
var _physical_land_projection_cache_revision: int = -1
var _last_map_cache_lod: String = "full"
var _map_flag_resource_lookup_calls: int = 0
var _map_flag_texture_cache_hits: int = 0
var _map_flag_texture_cache_misses: int = 0
var _map_flag_draw_calls: int = 0
var _flag_draw_validation_failures: Array[Dictionary] = []
var _map_player_audit_path: String = ""
var _map_player_audit_samples: Array[Dictionary] = []
var _map_player_audit_frame_index: int = 0
var _map_player_audit_input_kind: String = "idle"
var _map_interaction_lod_until_usec: int = 0
var _map_interaction_lod_timer_active: bool = false
var _map_runtime_interaction_enabled: bool = false
var _interaction_adjacency_by_entity: Dictionary = {}
var _interaction_color_index_by_entity: Dictionary = {}
var _interaction_coloring_ready: bool = false

@onready var _world_camera: Camera3D = %Camera3D


func _ready() -> void:
	_map_render_phase_from_command_line()
	if not _map_player_audit_path.is_empty():
		_map_player_audit_samples.append({
			"kind": "start",
			"timestamp_usec": Time.get_ticks_usec(),
		})
	_load_flag_palettes()
	super._ready()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()
	queue_redraw()
	_map_runtime_interaction_enabled = true
	if not _map_player_audit_path.is_empty():
		_write_map_player_audit()


func _map_render_phase_from_command_line() -> void:
	for argument: String in OS.get_cmdline_args():
		if argument == "--map-topology-audit":
			map_topology_validation_enabled = true
			map_screen_topology_diagnostics_enabled = true
			continue
		if argument == "--map-hide-physical-boundaries":
			map_debug_hide_physical_boundaries = true
			continue
		if argument == "--map-hide-physical-land":
			map_debug_hide_physical_land = true
			continue
		if argument == "--map-disable-batched-political-fills":
			map_debug_disable_batched_political_fills = true
			continue
		if argument == "--map-hide-globe-grid":
			map_debug_hide_globe_grid = true
			continue
		if argument == "--map-opaque-political-fills":
			map_debug_opaque_political_fills = true
			continue
		if argument == "--map-debug-build-timing":
			map_debug_build_timing = true
			continue
		if argument.begins_with("--map-source-max-edge="):
			map_debug_source_triangle_max_edge_degrees = maxf(
				2.0,
				argument.trim_prefix("--map-source-max-edge=").to_float()
			)
			continue
		if argument.begins_with("--map-source-max-depth="):
			map_debug_source_triangle_max_depth = clampi(
				argument.trim_prefix("--map-source-max-depth=").to_int(),
				1,
				6
			)
			continue
		if argument.begins_with("--map-yaw-degrees="):
			yaw = deg_to_rad(argument.trim_prefix("--map-yaw-degrees=").to_float())
			continue
		if argument.begins_with("--map-tilt-degrees="):
			tilt = clampf(
				deg_to_rad(argument.trim_prefix("--map-tilt-degrees=").to_float()),
				-HEMISPHERE_TILT_LIMIT,
				HEMISPHERE_TILT_LIMIT
			)
			continue
		if argument.begins_with("--map-zoom="):
			world_zoom = clampf(argument.trim_prefix("--map-zoom=").to_float(), WORLD_ZOOM_MIN, WORLD_ZOOM_MAX)
			continue
		if argument.begins_with("--map-player-audit-path="):
			_map_player_audit_path = argument.trim_prefix("--map-player-audit-path=")
			continue
		if not argument.begins_with("--map-phase="):
			continue
		var requested := argument.trim_prefix("--map-phase=").to_lower()
		if requested in [
			MAP_PHASE_LAND_ONLY,
			MAP_PHASE_POLITICAL_SOLID,
			MAP_PHASE_SELECTION_BORDERS,
			MAP_PHASE_HISTORICAL_FLAGS,
		]:
			map_render_phase = requested


func _on_flag_timer_timeout() -> void:
	_flag_time += FLAG_TIMER_STEP
	if space_level == WORLD and world_mode == WORLD_COUNTRIES and viewport_container.visible:
		queue_redraw()


func _apply_layout() -> void:
	super._apply_layout()
	_base_hemisphere_radius = _hemisphere_radius
	_apply_world_zoom_geometry()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var wheel_event: InputEventMouseButton = event as InputEventMouseButton
		if (
			wheel_event.pressed
			and space_level == WORLD
			and world_mode == WORLD_COUNTRIES
			and not _position_hits_ui(wheel_event.position)
			and Rect2(viewport_container.position, viewport_container.size).has_point(wheel_event.position)
		):
			if wheel_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_map_player_audit_input_kind = "zoom"
				_set_world_zoom(world_zoom + WORLD_ZOOM_STEP, wheel_event.position)
				accept_event()
				return
			if wheel_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_map_player_audit_input_kind = "zoom"
				_set_world_zoom(world_zoom - WORLD_ZOOM_STEP, wheel_event.position)
				accept_event()
				return
	super._gui_input(event)
	if event is InputEventMouseMotion and dragging:
		_map_player_audit_input_kind = "drag"
	elif event is InputEventMouseButton and dragging:
		_map_player_audit_input_kind = "drag"


func _ensure_projection_cache() -> void:
	var rebuild_flags: bool = (
		_projection_dirty
		or _flag_projection_cache_revision != _projection_revision
	)
	var base_projection_start_usec: int = Time.get_ticks_usec()
	var defer_optional_camera_layers := (
		map_interaction_flag_lod_enabled and _camera_interaction_active()
		or not _static_surface_build_complete
	)
	if defer_optional_camera_layers:
		# The active map draw path uses the physical-land cache, the political
		# surface cache, and the globe grid.  Coastlines, anchors, event markers,
		# focus polygons, and selected polylines are hidden until input settles;
		# projecting them here would spend input-frame time on data that cannot be
		# submitted in this LOD.
		_projection_dirty = false
		_projection_cache_revision = _projection_revision
		_global_screen_segments.clear()
		_selected_country_segments.clear()
		_country_screen_anchors.clear()
		_event_screen_positions.clear()
		_focus_country_screen_polygons.clear()
		_focus_region_screen_polygons.clear()
		_focus_region_screen_anchors.clear()
	else:
		super._ensure_projection_cache()
	_map_render_profile["base_projection_usec"] = Time.get_ticks_usec() - base_projection_start_usec
	if rebuild_flags:
		# Static political buffers are built independently from camera projection.
		# Do not immediately project every partially-built country (or the full
		# fallback while the compact interaction buffers are warming); physical
		# land remains visible and the next queued frame continues this bounded
		# preparation.
		_ensure_country_surface_triangle_buffers()
		if (
			not _static_surface_build_complete
			or (map_interaction_flag_lod_enabled and not _interactive_surface_build_complete)
		):
			if viewport != null:
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			queue_redraw()
			return
		_rebuild_country_flag_cache_fast()


func physical_land_source_report() -> Dictionary:
	var report := super.physical_land_source_report()
	_ensure_physical_land_triangle_cache()
	_ensure_interactive_physical_land_triangle_cache()
	report["triangle_count"] = _physical_land_triangle_records.size()
	report["projected_triangle_count"] = _physical_land_screen_triangles.size()
	report["projection_cache_revision"] = _physical_land_projection_cache_revision
	report["interactive_triangle_count"] = _interactive_physical_land_triangle_records.size()
	return report


func camera_navigation_report() -> Dictionary:
	return {
		"yaw_radians": yaw,
		"tilt_radians": tilt,
		"world_zoom": world_zoom,
		"hemisphere_center": [_hemisphere_center.x, _hemisphere_center.y],
		"layout_center": [_layout_hemisphere_center.x, _layout_hemisphere_center.y],
		"center_offset": [_world_view_center_offset.x, _world_view_center_offset.y],
		"hemisphere_radius": _hemisphere_radius,
		"hemisphere_rect": [
			_hemisphere_rect.position.x,
			_hemisphere_rect.position.y,
			_hemisphere_rect.size.x,
			_hemisphere_rect.size.y,
		],
		"tilt_limits_radians": [-HEMISPHERE_TILT_LIMIT, HEMISPHERE_TILT_LIMIT],
		"projection_revision": _projection_revision,
		"projection_cache_revision": _projection_cache_revision,
		"flag_projection_cache_revision": _flag_projection_cache_revision,
		"physical_land_projection_cache_revision": _physical_land_projection_cache_revision,
		"cache_lod": _last_map_cache_lod,
		"cache_ready": (
			_projection_cache_revision == _projection_revision
			and _flag_projection_cache_revision == _projection_revision
			and _physical_land_projection_cache_revision == _projection_revision
		),
	}


## Public, read-only diagnostics for map correctness probes.  The renderer's
## authoritative dictionaries remain private so tests cannot mutate ownership
## or topology while still being able to audit the exact runtime data path.
func map_debug_historical_roster() -> Dictionary:
	var entity_ids: Array[String] = []
	for entity_key: Variant in _country_by_id.keys():
		entity_ids.append(str(entity_key))
	entity_ids.sort()
	return {
		"ready": not entity_ids.is_empty(),
		"entity_count": entity_ids.size(),
		"entity_ids": entity_ids,
	}


func map_debug_country_record(entity_id: String) -> Dictionary:
	return (_country_by_id.get(entity_id, {}) as Dictionary).duplicate(true)


func map_debug_country_source_polygons(entity_id: String) -> Array:
	return (_country_unit_polygons.get(entity_id, []) as Array).duplicate()


func map_debug_country_surface_records(entity_id: String, source_index: int) -> Array:
	var cache_key := "%s:%d" % [entity_id, source_index]
	return (_country_surface_triangle_records.get(cache_key, []) as Array).duplicate()


func map_debug_country_screen_triangle_records(entity_id: String) -> Array:
	return (_flag_screen_triangle_records.get(entity_id, []) as Array).duplicate()


func map_debug_static_surface_report() -> Dictionary:
	return {
		"complete": _static_surface_build_complete,
		"cursor": _static_surface_build_cursor,
		"country_count": _countries.size(),
		"buffer_count": _country_surface_triangle_buffers.size(),
		"record_count": _country_surface_triangle_records.size(),
		"profile": _map_render_profile.duplicate(true),
	}


func map_debug_country_reference_longitude(entity_id: String) -> float:
	return float(_country_flag_uv_reference_longitudes.get(entity_id, 0.0))


func map_debug_focus_camera_on_entity(entity_id: String, zoom: float = 2.4) -> Dictionary:
	var anchor := Vector3.ZERO
	var buffer := _country_surface_triangle_buffers.get(entity_id, {}) as Dictionary
	if not buffer.is_empty():
		anchor = buffer.get("country_visibility_center", Vector3.ZERO) as Vector3
	if anchor.length_squared() <= 0.000001:
		var source_polygons: Array = _country_unit_polygons.get(entity_id, []) as Array
		for source_value: Variant in source_polygons:
			var source := source_value as PackedVector3Array
			for point: Vector3 in source:
				anchor += point
		if anchor.length_squared() > 0.000001:
			anchor = anchor.normalized()
	return map_debug_focus_camera_on_unit_anchor(anchor, zoom)


func map_debug_focus_camera_on_lon_lat(longitude: float, latitude: float, zoom: float = 2.4) -> Dictionary:
	return map_debug_focus_camera_on_unit_anchor(_lon_lat_to_unit(Vector2(longitude, latitude)), zoom)


func map_debug_focus_camera_on_unit_anchor(anchor: Vector3, zoom: float = 2.4) -> Dictionary:
	if anchor.length_squared() <= 0.000001:
		return camera_navigation_report()
	var normalized_anchor := anchor.normalized()
	# The globe basis is Rx(tilt) * Ry(yaw).  Choose yaw first so the anchor's
	# horizontal component points at the camera, then choose tilt so its
	# transformed y coordinate is zero.  This changes orientation only; the
	# viewport center remains the layout center.
	var next_yaw := atan2(-normalized_anchor.x, normalized_anchor.z)
	var yawed_anchor := Basis(Vector3.UP, next_yaw) * normalized_anchor
	var next_tilt := atan2(yawed_anchor.y, yawed_anchor.z)
	yaw = next_yaw
	tilt = clampf(next_tilt, -HEMISPHERE_TILT_LIMIT, HEMISPHERE_TILT_LIMIT)
	world_zoom = clampf(zoom, WORLD_ZOOM_MIN, WORLD_ZOOM_MAX)
	_apply_world_zoom_geometry()
	_mark_projection_dirty()
	_ensure_projection_cache()
	queue_redraw()
	var report := camera_navigation_report()
	report["focused_anchor"] = [normalized_anchor.x, normalized_anchor.y, normalized_anchor.z]
	return report


func _ensure_physical_land_triangle_cache() -> void:
	if not _physical_land_triangle_records.is_empty() or _physical_land_polygons.is_empty():
		return
	var triangle_start_usec := Time.get_ticks_usec()
	for source_index: int in range(_physical_land_polygons.size()):
		var source: PackedVector3Array = _physical_land_polygons[source_index]
		if source.size() < 3:
			continue
		var reference_longitude := _map_unit_to_lon_lat(source[0]).x
		var planar_polygons: Array[PackedVector2Array] = [
			_unwrapped_planar_ring(source, reference_longitude)
		]
		var holes: Array = _physical_land_holes[source_index] as Array if source_index < _physical_land_holes.size() else []
		for hole_value: Variant in holes:
			var hole: PackedVector3Array = hole_value
			var planar_hole := _unwrapped_planar_ring(hole, reference_longitude)
			var difference: Array[PackedVector2Array] = []
			for polygon: PackedVector2Array in planar_polygons:
				for result_value: Variant in Geometry2D.clip_polygons(polygon, planar_hole):
					if result_value is PackedVector2Array:
						difference.append(result_value as PackedVector2Array)
			planar_polygons = difference
		for polygon: PackedVector2Array in planar_polygons:
			var triangle_indices := _triangulate_planar_polygon(polygon)
			for index: int in range(0, triangle_indices.size(), 3):
				if index + 2 >= triangle_indices.size():
					break
				var first_index := int(triangle_indices[index])
				var second_index := int(triangle_indices[index + 1])
				var third_index := int(triangle_indices[index + 2])
				if (
					first_index < 0
					or second_index < 0
					or third_index < 0
					or first_index >= polygon.size()
					or second_index >= polygon.size()
					or third_index >= polygon.size()
				):
					continue
				var planar_triangle := PackedVector2Array([
					polygon[first_index],
					polygon[second_index],
					polygon[third_index],
				])
				if _planar_polygon_area(planar_triangle) <= MAP_TRIANGLE_AREA_EPSILON:
					continue
				for child_planar: PackedVector2Array in _tessellate_planar_triangle(planar_triangle):
					if _planar_polygon_area(child_planar) <= MAP_TRIANGLE_AREA_EPSILON:
						continue
					_physical_land_triangle_records.append(PackedVector3Array([
						_lon_lat_to_unit(child_planar[0]),
						_lon_lat_to_unit(child_planar[1]),
						_lon_lat_to_unit(child_planar[2]),
					]))
	_map_render_profile["physical_land_static_triangulation_usec"] = Time.get_ticks_usec() - triangle_start_usec


func _ensure_interactive_physical_land_triangle_cache() -> void:
	if not _interactive_physical_land_triangle_records.is_empty() or _physical_land_polygons.is_empty():
		return
	for source_index: int in range(_physical_land_polygons.size()):
		var source: PackedVector3Array = _physical_land_polygons[source_index]
		var simplified_source := _simplify_unit_ring(source, INTERACTIVE_PHYSICAL_RING_POINTS)
		if simplified_source.size() < 3:
			continue
		_interactive_physical_land_polygons.append(simplified_source)
		var simplified_holes: Array[PackedVector3Array] = []
		var source_holes: Array = _physical_land_holes[source_index] as Array if source_index < _physical_land_holes.size() else []
		for hole_value: Variant in source_holes:
			var simplified_hole := _simplify_unit_ring(hole_value as PackedVector3Array, INTERACTIVE_PHYSICAL_RING_POINTS)
			if simplified_hole.size() >= 3:
				simplified_holes.append(simplified_hole)
		_interactive_physical_land_holes.append(simplified_holes)
		var reference_longitude := _map_unit_to_lon_lat(simplified_source[0]).x
		var planar_polygons: Array[PackedVector2Array] = [
			_unwrapped_planar_ring(simplified_source, reference_longitude)
		]
		for hole_value: Variant in simplified_holes:
			var planar_hole := _unwrapped_planar_ring(hole_value as PackedVector3Array, reference_longitude)
			var difference: Array[PackedVector2Array] = []
			for polygon: PackedVector2Array in planar_polygons:
				for result_value: Variant in Geometry2D.clip_polygons(polygon, planar_hole):
					if result_value is PackedVector2Array:
						difference.append(result_value as PackedVector2Array)
			planar_polygons = difference
		for polygon: PackedVector2Array in planar_polygons:
			var triangle_indices: PackedInt32Array = _triangulate_planar_polygon(polygon)
			for index: int in range(0, triangle_indices.size(), 3):
				if index + 2 >= triangle_indices.size():
					break
				var first_index := int(triangle_indices[index])
				var second_index := int(triangle_indices[index + 1])
				var third_index := int(triangle_indices[index + 2])
				if (
					first_index < 0
					or second_index < 0
					or third_index < 0
					or first_index >= polygon.size()
					or second_index >= polygon.size()
					or third_index >= polygon.size()
				):
					continue
				var planar_triangle := PackedVector2Array([
					polygon[first_index],
					polygon[second_index],
					polygon[third_index],
				])
				if _planar_polygon_area(planar_triangle) > MAP_TRIANGLE_AREA_EPSILON:
					for child_planar: PackedVector2Array in _tessellate_planar_triangle(planar_triangle):
						if _planar_polygon_area(child_planar) <= MAP_TRIANGLE_AREA_EPSILON:
							continue
						_interactive_physical_land_triangle_records.append(PackedVector3Array([
							_lon_lat_to_unit(child_planar[0]),
							_lon_lat_to_unit(child_planar[1]),
							_lon_lat_to_unit(child_planar[2]),
						]))


func _rebuild_physical_land_projection_cache(basis: Basis, interactive_lod: bool = false) -> void:
	var projection_start_usec := Time.get_ticks_usec()
	_ensure_physical_land_triangle_cache()
	if interactive_lod:
		_ensure_interactive_physical_land_triangle_cache()
	_physical_land_screen_triangles.clear()
	_physical_land_screen_boundary_segments.clear()
	var land_polygons: Array[PackedVector3Array] = _interactive_physical_land_polygons if interactive_lod else _physical_land_polygons
	var land_holes: Array = _interactive_physical_land_holes if interactive_lod else _physical_land_holes
	var land_triangles: Array[PackedVector3Array] = _interactive_physical_land_triangle_records if interactive_lod else _physical_land_triangle_records
	# Coastline polylines are presentation detail during active camera input.
	# Deferring them keeps the neutral physical land surface visible without
	# spending input-frame time projecting thousands of boundary points.
	if not interactive_lod:
		for source_index: int in range(land_polygons.size()):
			var source: PackedVector3Array = land_polygons[source_index]
			for boundary_segment: PackedVector2Array in _project_closed_unit_boundary_fast(source, basis):
				_physical_land_screen_boundary_segments.append(boundary_segment)
			var holes: Array = land_holes[source_index] as Array if source_index < land_holes.size() else []
			for hole_value: Variant in holes:
				for boundary_segment: PackedVector2Array in _project_closed_unit_boundary_fast(hole_value as PackedVector3Array, basis):
					_physical_land_screen_boundary_segments.append(boundary_segment)
	for triangle: PackedVector3Array in land_triangles:
		var transformed := PackedVector3Array()
		var maximum_depth := -INF
		var minimum_depth := INF
		for point: Vector3 in triangle:
			var rotated := basis * point
			transformed.append(rotated)
			maximum_depth = maxf(maximum_depth, rotated.z)
			minimum_depth = minf(minimum_depth, rotated.z)
		if maximum_depth <= MAP_TRIANGLE_DEPTH_EPSILON:
			continue
		var visible_points := transformed
		if minimum_depth < -MAP_TRIANGLE_DEPTH_EPSILON:
			visible_points = _clip_front_facing_triangle(transformed, Basis.IDENTITY)
		if visible_points.size() < 3:
			continue
		var screen := PackedVector2Array()
		for point: Vector3 in visible_points:
			var screen_point := _sphere_screen(point)
			if not is_finite(screen_point.x) or not is_finite(screen_point.y):
				screen = PackedVector2Array()
				break
			screen.append(screen_point)
		if screen.size() < 3:
			continue
		# Horizon clipping can turn a source triangle into a convex quad. Do not
		# fan that polygon: a fan is invalid for a concave/edge-touching result
		# and CanvasItem will reject it at draw time. Triangulate the clipped
		# screen polygon into independent, validated draw polygons instead.
		var screen_indices: PackedInt32Array = _triangulate_planar_polygon(screen)
		for index: int in range(0, screen_indices.size(), 3):
			if index + 2 >= screen_indices.size():
				break
			var first_index := int(screen_indices[index])
			var second_index := int(screen_indices[index + 1])
			var third_index := int(screen_indices[index + 2])
			if (
				first_index < 0
				or second_index < 0
				or third_index < 0
				or first_index >= screen.size()
				or second_index >= screen.size()
				or third_index >= screen.size()
			):
				continue
			var triangle_screen := PackedVector2Array([
				screen[first_index],
				screen[second_index],
				screen[third_index],
			])
			if _is_valid_physical_screen_triangle(triangle_screen):
				_physical_land_screen_triangles.append(triangle_screen)
	_physical_land_projection_cache_revision = _projection_revision
	_map_render_profile["physical_land_projection_usec"] = Time.get_ticks_usec() - projection_start_usec


func _draw_physical_land_base() -> void:
	# Explicit neutral land layer for physical surface without an admissible
	# 1900 political owner; it must remain distinct from ocean instead of
	# becoming an unexplained black hole beneath the political layer.
	var land_color := Color(0.13, 0.25, 0.27, 0.86)
	if not _physical_land_screen_triangles.is_empty():
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for triangle: PackedVector2Array in _physical_land_screen_triangles:
			if triangle.size() != 3:
				continue
			for point: Vector2 in triangle:
				points.append(point)
				colors.append(land_color)
		if points.size() >= 3:
			if MAP_USE_EXPLICIT_TRIANGLE_SUBMISSION:
				for point_index: int in range(0, points.size(), 3):
					if point_index + 2 >= points.size():
						break
					draw_colored_polygon(
						PackedVector2Array([points[point_index], points[point_index + 1], points[point_index + 2]]),
						land_color
					)
			else:
				var indices := _sequential_triangle_indices(points.size())
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
	else:
		for polygon: PackedVector2Array in _physical_land_screen_triangles:
			draw_colored_polygon(polygon, land_color)
	if map_debug_hide_physical_boundaries:
		return
	var close_mix := clampf(inverse_lerp(1.0, 3.0, world_zoom), 0.0, 1.0)
	var coastline_color := Color(0.20, 0.31, 0.32, lerpf(0.28, 0.48, close_mix))
	var coastline_width := lerpf(0.55, 0.90, close_mix)
	for segment: PackedVector2Array in _physical_land_screen_boundary_segments:
		draw_polyline(segment, coastline_color, coastline_width, true)


func _is_valid_physical_screen_triangle(triangle: PackedVector2Array) -> bool:
	if triangle.size() != 3:
		return false
	for point: Vector2 in triangle:
		if not is_finite(point.x) or not is_finite(point.y):
			return false
		# A finite but astronomically large point can still overflow the
		# renderer's canvas polygon validation after a camera transform.
		if absf(point.x) > 100000.0 or absf(point.y) > 100000.0:
			return false
	if triangle[0].distance_to(triangle[1]) <= 0.001:
		return false
	if triangle[1].distance_to(triangle[2]) <= 0.001:
		return false
	if triangle[2].distance_to(triangle[0]) <= 0.001:
		return false
	return _screen_polygon_area(triangle) > MAP_PHYSICAL_SCREEN_AREA_EPSILON


func _sequential_triangle_indices(vertex_count: int) -> PackedInt32Array:
	# RenderingServer's triangle-array submission is indexed.  An empty index
	# buffer is not a portable request for non-indexed triangles; on the
	# Compatibility renderer it can connect unrelated vertices into giant
	# surfaces.  Every caller supplies one explicit index per appended vertex.
	if vertex_count < 3 or vertex_count % 3 != 0:
		return PackedInt32Array()
	var indices := PackedInt32Array()
	indices.resize(vertex_count)
	for index: int in range(vertex_count):
		indices[index] = index
	return indices


func _draw_global_world() -> void:
	_draw_country_flag_skins()
	super._draw_global_world()
	_draw_zoom_country_labels()
	_draw_zoom_indicator()


func _focus_selected_country() -> void:
	super._focus_selected_country()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _show_event_from_hud(event_id: String) -> void:
	super._show_event_from_hud(event_id)
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _return_to_global_world() -> void:
	super._return_to_global_world()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _enter_region() -> void:
	super._enter_region()
	_apply_world_zoom_geometry()


func _enter_city(city_id: String) -> void:
	super._enter_city(city_id)
	_apply_world_zoom_geometry()


func _go_back() -> void:
	super._go_back()
	_apply_world_zoom_geometry()
	_mark_projection_dirty()


func _sync_moon_visibility() -> void:
	if _moon_node == null:
		return
	_moon_node.visible = (
		space_level == WORLD
		and world_mode == WORLD_COUNTRIES
		and viewport_container.visible
		and world_zoom <= 1.10
	)


func _set_world_zoom(value: float, anchor: Vector2 = Vector2(INF, INF)) -> void:
	var next_zoom: float = clampf(value, WORLD_ZOOM_MIN, WORLD_ZOOM_MAX)
	if is_equal_approx(next_zoom, world_zoom):
		return
	# Zoom is deliberately centered on the usable map viewport.  The old
	# cursor-anchor calculation translated the globe and made repeated wheel
	# input drift the world away from the stable viewport center.
	_reset_world_view_center()
	world_zoom = next_zoom
	_apply_world_zoom_geometry()
	_reset_world_view_center()
	_mark_projection_dirty()
	_sync_moon_visibility()
	hover_country_id = ""
	hover_event_id = ""
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _select_global_object_at(position: Vector2, click: bool) -> void:
	super._select_global_object_at(position, click)
	if not hover_event_id.is_empty():
		return
	var surface_country_id := _country_id_at_projected_surface(position)
	if surface_country_id.is_empty():
		if click:
			# A click on the globe background/ocean is an explicit deselection.
			# Optional country metadata and the nearest-anchor hover heuristic must
			# never keep a political selection alive after the surface miss.
			selected_country_id = ""
			selected_event_id = ""
			selected_region_id = ""
			selected_institution_id = ""
			hover_country_id = ""
			_mark_projection_dirty()
			_set_info_open(false)
			queue_redraw()
		return
	if hover_country_id != surface_country_id:
		hover_country_id = surface_country_id
		queue_redraw()
	if not click:
		return
	selected_country_id = surface_country_id
	selected_event_id = ""
	selected_region_id = ""
	selected_institution_id = ""
	_mark_projection_dirty()
	_set_info_open(true)


func _country_id_at_projected_surface(position: Vector2) -> String:
	for country_value: Variant in _countries:
		var country := country_value as Dictionary
		var country_id := str(country.get("id", ""))
		if _last_map_cache_lod == "interactive":
			var compact_points: PackedVector2Array = _interactive_flag_screen_points.get(country_id, PackedVector2Array()) as PackedVector2Array
			for point_index: int in range(0, compact_points.size(), 3):
				if _is_valid_screen_triangle_at(compact_points, point_index) and _point_in_screen_triangle_at(position, compact_points, point_index):
					return country_id
			continue
		for polygon_value: Variant in (_flag_screen_polygons.get(country_id, []) as Array):
			var polygon: PackedVector2Array = polygon_value
			if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(position, polygon):
				return country_id
	return ""


func _apply_world_zoom_geometry() -> void:
	if _base_hemisphere_radius <= 0.0:
		return
	var effective_zoom: float = _effective_world_zoom()
	_hemisphere_radius = _base_hemisphere_radius * effective_zoom
	_hemisphere_rect = Rect2(
		_hemisphere_center - Vector2(_hemisphere_radius, _hemisphere_radius),
		Vector2(_hemisphere_radius * 2.0, _hemisphere_radius * 2.0)
	)
	if _world_camera != null:
		_world_camera.size = CAMERA_ORTHO_SIZE / effective_zoom
		if viewport != null and viewport_container.visible:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _effective_world_zoom() -> float:
	if space_level == WORLD and world_mode == WORLD_COUNTRIES:
		return world_zoom
	return 1.0


func _load_flag_palettes() -> void:
	var document: Dictionary = _read_document("res://data/world_map/country_flag_palettes.json")
	var raw_palettes: Dictionary = document.get("palettes", {}) as Dictionary
	for iso_value: Variant in raw_palettes.keys():
		var iso: String = str(iso_value).to_upper()
		var raw_record: Dictionary = raw_palettes.get(iso, {}) as Dictionary
		var packed_colors: PackedColorArray = PackedColorArray()
		var color_values: Array = raw_record.get("colors", []) as Array
		for color_value: Variant in color_values:
			packed_colors.append(Color.from_string(str(color_value), Color(0.54, 0.60, 0.58, 1.0)))
		if packed_colors.is_empty():
			continue
		_flag_palettes[iso] = {
			"pattern": str(raw_record.get("pattern", "solid")),
			"colors": packed_colors,
		}


func _rebuild_country_flag_cache() -> void:
	var cache_start_usec: int = Time.get_ticks_usec()
	_map_profile_static_triangulation_usec = 0
	_interactive_source_triangles_processed = 0
	_interactive_front_triangles = 0
	_interactive_behind_triangles = 0
	_interactive_horizon_clipped_triangles = 0
	_interactive_projected_vertices = 0
	_interactive_screen_triangles = 0
	_interactive_clip_temp_array_count = 0
	_interactive_provenance_string_lookups = 0
	_flag_screen_polygons.clear()
	_flag_screen_triangle_records.clear()
	_interactive_flag_screen_components.clear()
	_flag_screen_bounds.clear()
	_country_screen_boundary_segments.clear()
	_country_screen_meshes.clear()
	_country_screen_triangle_counts.clear()
	_map_render_stage_records.clear()
	_ensure_country_flag_uv_bounds()
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	var boundary_projection_usec: int = 0
	var camera_projection_usec: int = 0
	var clipping_usec: int = 0
	var mesh_build_usec: int = 0
	for country_value: Variant in _countries:
		var country: Dictionary = country_value as Dictionary
		var country_id: String = str(country.get("id", ""))
		var source_polygons: Array = _country_unit_polygons.get(country_id, []) as Array
		var visible_polygons: Array[PackedVector2Array] = []
		var boundary_segments: Array[PackedVector2Array] = []
		var screen_triangles: Array[Dictionary] = []
		var has_bounds: bool = false
		var minimum: Vector2 = Vector2(100000.0, 100000.0)
		var maximum: Vector2 = Vector2(-100000.0, -100000.0)
		var source_triangle_count: int = 0
		var visible_source_triangle_count: int = 0
		var clipped_visible_triangle_count: int = 0
		var missing_visible_triangle_count: int = 0
		var invalid_projected_parts: int = 0
		var front_facing_geometry: bool = false
		var tiny_surface_fallback_parts: int = 0
		var source_planar_area: float = 0.0
		var triangulated_planar_area: float = 0.0
		var visible_projected_area: float = 0.0
		for source_index: int in range(source_polygons.size()):
			var source_value: Variant = source_polygons[source_index]
			var source: PackedVector3Array = source_value
			var boundary_start_usec: int = Time.get_ticks_usec()
			for boundary_segment: PackedVector2Array in _project_closed_unit_boundary_fast(source, basis):
				boundary_segments.append(boundary_segment)
			for hole_value: Variant in _holes_for_surface_source(country_id, source_index):
				var hole: PackedVector3Array = hole_value
				for boundary_segment: PackedVector2Array in _project_closed_unit_boundary_fast(hole, basis):
					boundary_segments.append(boundary_segment)
			boundary_projection_usec += Time.get_ticks_usec() - boundary_start_usec
			var static_records: Array = _surface_triangle_records(
				"%s:%d" % [country_id, source_index],
				country_id,
				source_index,
				source
			)
			var static_statistics: Dictionary = _country_surface_triangle_statistics.get(
				"%s:%d" % [country_id, source_index],
				{}
			) as Dictionary
			source_triangle_count += static_records.size()
			source_planar_area += float(static_statistics.get("source_area", 0.0))
			triangulated_planar_area += float(static_statistics.get("triangulated_area", 0.0))
			var source_visible_triangle_count: int = 0
			for record_value: Variant in static_records:
				var record: Dictionary = record_value as Dictionary
				var points: PackedVector3Array = record.get("points", PackedVector3Array()) as PackedVector3Array
				var uvs: PackedVector2Array = record.get("uvs", PackedVector2Array()) as PackedVector2Array
				var transformed := PackedVector3Array()
				var maximum_depth := -INF
				var minimum_depth := INF
				for point: Vector3 in points:
					var rotated: Vector3 = basis * point
					transformed.append(rotated)
					maximum_depth = maxf(maximum_depth, rotated.z)
					minimum_depth = minf(minimum_depth, rotated.z)
				if maximum_depth <= MAP_TRIANGLE_DEPTH_EPSILON:
					continue
				var projected_start_usec: int = Time.get_ticks_usec()
				var projected_triangles: Array[Dictionary]
				var candidate_points: PackedVector3Array = transformed
				if minimum_depth >= -MAP_TRIANGLE_DEPTH_EPSILON:
					projected_triangles = _screen_triangle_records(transformed, uvs)
				else:
					var clipping_start_usec: int = Time.get_ticks_usec()
					var clipped := _clip_front_facing_triangle_with_uv(transformed, uvs)
					clipping_usec += Time.get_ticks_usec() - clipping_start_usec
					candidate_points = clipped.get("points", PackedVector3Array()) as PackedVector3Array
					projected_triangles = _screen_triangle_records(
						candidate_points,
						clipped.get("uvs", PackedVector2Array()) as PackedVector2Array
					)
				camera_projection_usec += Time.get_ticks_usec() - projected_start_usec
				if _screen_area_for_unit_points(candidate_points) <= MAP_PROJECTED_AREA_EPSILON:
					continue
				source_visible_triangle_count += 1
				visible_source_triangle_count += 1
				front_facing_geometry = true
				if projected_triangles.is_empty():
					missing_visible_triangle_count += 1
					invalid_projected_parts += 1
					continue
				clipped_visible_triangle_count += projected_triangles.size()
				for triangle_record: Dictionary in projected_triangles:
					screen_triangles.append(triangle_record)
					var screen_triangle: PackedVector2Array = triangle_record.get("screen", PackedVector2Array()) as PackedVector2Array
					visible_polygons.append(screen_triangle)
					visible_projected_area += _screen_polygon_area(screen_triangle)
					for point: Vector2 in screen_triangle:
						has_bounds = true
						minimum.x = minf(minimum.x, point.x)
						minimum.y = minf(minimum.y, point.y)
						maximum.x = maxf(maximum.x, point.x)
						maximum.y = maxf(maximum.y, point.y)
			# A surface that only touches the horizon is not front-facing drawable
			# geometry.  Do not synthesize a marker: it would make the audit claim
			# that a polity was visible while the real surface had no draw mesh.
			if source_visible_triangle_count == 0 and not static_records.is_empty():
				var source_candidates := _source_screen_candidates(source, basis)
				var source_bounds := _bounds_for_points(source_candidates)
				if (
					(source_bounds.size.x <= MAP_TINY_SURFACE_SIZE and source_bounds.size.y <= MAP_TINY_SURFACE_SIZE)
					or _source_front_depth(source, basis) <= MAP_HORIZON_SURFACE_DEPTH_EPSILON
				):
					tiny_surface_fallback_parts += 1
		if not boundary_segments.is_empty():
			_country_screen_boundary_segments[country_id] = boundary_segments
		if screen_triangles.is_empty():
			_map_render_stage_records[country_id] = _make_map_render_stage_record(
				country_id,
				source_polygons.size(),
				clipped_visible_triangle_count,
				0,
				front_facing_geometry,
				invalid_projected_parts,
				false,
				0,
				source_triangle_count,
				visible_source_triangle_count,
				clipped_visible_triangle_count,
				tiny_surface_fallback_parts,
				missing_visible_triangle_count,
				source_planar_area,
				triangulated_planar_area,
				visible_projected_area
			)
			continue
		_flag_screen_polygons[country_id] = visible_polygons
		if has_bounds:
			_flag_screen_bounds[country_id] = Rect2(minimum, maximum - minimum)
		var mesh_start_usec: int = Time.get_ticks_usec()
		var screen_mesh := _mesh_from_screen_triangles(screen_triangles)
		if screen_mesh != null:
			_country_screen_meshes[country_id] = screen_mesh
			_country_screen_triangle_counts[country_id] = screen_triangles.size()
		mesh_build_usec += Time.get_ticks_usec() - mesh_start_usec
		_map_render_stage_records[country_id] = _make_map_render_stage_record(
			country_id,
			source_polygons.size(),
			clipped_visible_triangle_count,
			screen_triangles.size(),
			front_facing_geometry,
			invalid_projected_parts,
			_flag_screen_bounds[country_id].size.x <= MAP_PROJECTED_AREA_EPSILON
				or _flag_screen_bounds[country_id].size.y <= MAP_PROJECTED_AREA_EPSILON,
			tiny_surface_fallback_parts,
			source_triangle_count,
			visible_source_triangle_count,
			clipped_visible_triangle_count,
			screen_triangles.size(),
			missing_visible_triangle_count,
			source_planar_area,
			triangulated_planar_area,
			visible_projected_area
		)
	_flag_projection_cache_revision = _projection_revision
	_map_render_profile["flag_cache_build_usec"] = Time.get_ticks_usec() - cache_start_usec
	_map_render_profile["source_triangulation_usec"] = _map_profile_static_triangulation_usec
	_map_render_profile["boundary_projection_usec"] = boundary_projection_usec
	_map_render_profile["camera_projection_usec"] = camera_projection_usec
	_map_render_profile["hemisphere_clipping_usec"] = clipping_usec
	_map_render_profile["mesh_build_usec"] = mesh_build_usec
	_map_render_profile["static_triangulation_total_usec"] = _map_profile_static_triangulation_total_usec
	_map_render_profile["static_data_build_count"] = _static_data_build_count
	_map_render_profile["static_uv_build_count"] = _static_uv_build_count
	_map_render_profile["static_provenance_build_count"] = _static_provenance_build_count
	_map_render_profile["static_triangulation_build_count"] = _static_triangulation_build_count


func _ensure_country_surface_triangle_buffers() -> void:
	if (
		_static_surface_build_complete
		and _country_surface_triangle_buffers.size() == _countries.size()
		and _interactive_country_surface_triangle_buffers.size() == _countries.size()
		and not _countries.is_empty()
	):
		return
	if _static_surface_build_cursor == 0 and _country_surface_triangle_buffers.is_empty():
		_interactive_country_surface_triangle_buffers.clear()
		_interactive_country_boundary_sources.clear()
		_static_data_build_count += 1
		_static_provenance_build_count += 1
	var build_start_usec := Time.get_ticks_usec()
	while _static_surface_build_cursor < _countries.size():
		var country: Dictionary = _countries[_static_surface_build_cursor] as Dictionary
		var country_id := str(country.get("id", ""))
		_build_country_surface_triangle_buffer(country_id, _country_unit_polygons.get(country_id, []) as Array)
		_static_surface_build_cursor += 1
		if Time.get_ticks_usec() - build_start_usec >= MAP_STATIC_SURFACE_BUILD_BUDGET_USEC:
			break
	_static_surface_build_complete = _static_surface_build_cursor >= _countries.size()
	_map_render_profile["static_surface_build_cursor"] = _static_surface_build_cursor
	_map_render_profile["static_surface_build_complete"] = _static_surface_build_complete


func _reset_static_surface_build_progress() -> void:
	_static_surface_build_cursor = 0
	_static_surface_build_complete = false
	_interactive_surface_build_cursor = 0
	_interactive_surface_build_complete = false
	_static_projection_cache_revision = -1
	_detail_restore_in_progress = false
	_detail_restore_cursor = 0
	_detail_restore_revision = -1
	_country_surface_triangle_buffers.clear()
	_interactive_country_surface_triangle_buffers.clear()
	_interactive_country_boundary_sources.clear()


func _advance_interactive_surface_buffer_build() -> void:
	if (
		not _static_surface_build_complete
		or _interactive_surface_build_complete
		or _camera_interaction_active()
	):
		return
	var build_start_usec := Time.get_ticks_usec()
	while _interactive_surface_build_cursor < _countries.size():
		var country: Dictionary = _countries[_interactive_surface_build_cursor] as Dictionary
		var country_id := str(country.get("id", ""))
		var source_polygons := _country_unit_polygons.get(country_id, []) as Array
		var interactive_result := _build_interactive_surface_buffer(country_id, source_polygons)
		var interactive_buffer := interactive_result.get("buffer", {}) as Dictionary
		if interactive_buffer.is_empty():
			interactive_buffer = _country_surface_triangle_buffers.get(country_id, {}) as Dictionary
		_interactive_country_surface_triangle_buffers[country_id] = interactive_buffer
		_interactive_country_boundary_sources[country_id] = interactive_result.get(
			"boundaries",
			{"sources": source_polygons, "holes": []}
		) as Dictionary
		_interactive_surface_build_cursor += 1
		if Time.get_ticks_usec() - build_start_usec >= MAP_INTERACTIVE_SURFACE_BUILD_BUDGET_USEC:
			break
	_interactive_surface_build_complete = _interactive_surface_build_cursor >= _countries.size()
	if _interactive_surface_build_complete:
		if map_interaction_flag_lod_enabled:
			_detail_restore_in_progress = true
			_detail_restore_cursor = 0
			_detail_restore_revision = -1
			_last_map_cache_lod = "interactive"
		if viewport != null:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		queue_redraw()


func _build_country_surface_triangle_buffer(country_id: String, source_polygons: Array) -> void:
	var build_start_usec := Time.get_ticks_usec()
	if map_debug_build_timing:
		print("R43_SURFACE_BUILD_START id=%s parts=%d" % [country_id, source_polygons.size()])
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indexed_vertices := PackedVector3Array()
	var indexed_triangle_indices := PackedInt32Array()
	var indexed_vertex_lookup: Dictionary = {}
	var visibility_centers := PackedVector3Array()
	var visibility_margins := PackedFloat32Array()
	var source_components: Array[String] = []
	var source_component_indices := PackedInt32Array()
	var source_triangles := PackedInt32Array()
	var source_triangle_originals: Array[PackedVector2Array] = []
	var country_source_planar_area := 0.0
	var country_triangulated_planar_area := 0.0
	for source_index: int in range(source_polygons.size()):
		var source: PackedVector3Array = source_polygons[source_index]
		var records := _surface_triangle_records(
			"%s:%d" % [country_id, source_index],
			country_id,
			source_index,
			source
		)
		var source_statistics: Dictionary = _country_surface_triangle_statistics.get(
			"%s:%d" % [country_id, source_index],
			{}
		) as Dictionary
		country_source_planar_area += float(source_statistics.get("source_area", 0.0))
		country_triangulated_planar_area += float(source_statistics.get("triangulated_area", 0.0))
		for record_index: int in range(records.size()):
			var record: Dictionary = records[record_index] as Dictionary
			var triangle_points: PackedVector3Array = record.get("points", PackedVector3Array()) as PackedVector3Array
			var triangle_uvs: PackedVector2Array = record.get("uvs", PackedVector2Array()) as PackedVector2Array
			if triangle_points.size() != 3 or triangle_uvs.size() != 3:
				continue
			var center := (
				triangle_points[0] + triangle_points[1] + triangle_points[2]
			).normalized()
			var angular_margin := 0.0
			for point: Vector3 in triangle_points:
				angular_margin = maxf(angular_margin, 2.0 * sin(acos(clampf(center.dot(point), -1.0, 1.0)) * 0.5))
			visibility_centers.append(center)
			visibility_margins.append(angular_margin)
			for point: Vector3 in triangle_points:
				points.append(point)
				var vertex_index: int = int(indexed_vertex_lookup.get(point, -1))
				if vertex_index < 0:
					vertex_index = indexed_vertices.size()
					indexed_vertex_lookup[point] = vertex_index
					indexed_vertices.append(point)
				indexed_triangle_indices.append(vertex_index)
			for uv: Vector2 in triangle_uvs:
				uvs.append(uv)
			source_components.append("%s:%d" % [country_id, source_index])
			source_component_indices.append(source_index)
			source_triangles.append(record_index)
			source_triangle_originals.append(
			record.get("source_triangle_original_planar", PackedVector2Array()) as PackedVector2Array
		)
	var country_visibility_center := Vector3.FORWARD
	if not indexed_vertices.is_empty():
		var country_center_sum := Vector3.ZERO
		for point: Vector3 in indexed_vertices:
			country_center_sum += point
		if country_center_sum.length_squared() > 0.000001:
			country_visibility_center = country_center_sum.normalized()
	var country_visibility_margin := 0.0
	for point: Vector3 in indexed_vertices:
		country_visibility_margin = maxf(
			country_visibility_margin,
			2.0 * sin(acos(clampf(country_visibility_center.dot(point), -1.0, 1.0)) * 0.5)
		)
	_country_surface_triangle_buffers[country_id] = {
		"points": points,
		"uvs": uvs,
		"indexed_vertices": indexed_vertices,
		"indexed_triangle_indices": indexed_triangle_indices,
		"visibility_centers": visibility_centers,
		"visibility_margins": visibility_margins,
		"country_visibility_center": country_visibility_center,
		"country_visibility_margin": country_visibility_margin,
		"source_components": source_components,
		"source_component_indices": source_component_indices,
		"source_triangles": source_triangles,
		"source_triangle_originals": source_triangle_originals,
		"source_planar_area": country_source_planar_area,
		"triangulated_planar_area": country_triangulated_planar_area,
	}
	# Build the bounded per-component interaction representation alongside the
	# source buffer. Its input is capped before RDP, so this adds predictable
	# work without the old unbounded simplification stall. It never joins source
	# components or replaces the authoritative full buffer.
	var interactive_result := _build_interactive_surface_buffer(country_id, source_polygons)
	var interactive_buffer := interactive_result.get("buffer", {}) as Dictionary
	if interactive_buffer.is_empty():
		interactive_buffer = _country_surface_triangle_buffers[country_id]
	_interactive_country_surface_triangle_buffers[country_id] = interactive_buffer
	_interactive_country_boundary_sources[country_id] = interactive_result.get(
		"boundaries",
		{"sources": source_polygons, "holes": []}
	) as Dictionary
	if map_debug_build_timing:
		print("R43_SURFACE_BUILD_END id=%s ms=%.3f triangles=%d" % [
			country_id,
			float(Time.get_ticks_usec() - build_start_usec) / 1000.0,
			points.size() / 3,
		])


func _build_interactive_surface_buffer(country_id: String, source_polygons: Array) -> Dictionary:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	var visibility_centers := PackedVector3Array()
	var visibility_margins := PackedFloat32Array()
	var source_components: Array[String] = []
	var source_component_indices := PackedInt32Array()
	var source_triangles := PackedInt32Array()
	var source_triangle_originals: Array[PackedVector2Array] = []
	var boundary_sources: Array[PackedVector3Array] = []
	var boundary_holes: Array = []
	var source_planar_area := 0.0
	var triangulated_planar_area := 0.0
	for source_index: int in range(source_polygons.size()):
		var source: PackedVector3Array = source_polygons[source_index]
		var boundary_source := _simplify_unit_ring(source, INTERACTIVE_BOUNDARY_RING_POINTS)
		var simplified_source := _simplify_unit_ring(source, INTERACTIVE_SURFACE_RING_POINTS)
		if simplified_source.size() < 3:
			continue
		boundary_sources.append(boundary_source)
		var simplified_hole_list: Array[PackedVector3Array] = []
		var boundary_hole_list: Array[PackedVector3Array] = []
		for hole_value: Variant in _holes_for_surface_source(country_id, source_index):
			var hole: PackedVector3Array = hole_value
			var boundary_hole := _simplify_unit_ring(hole, INTERACTIVE_BOUNDARY_RING_POINTS)
			if boundary_hole.size() >= 3:
				boundary_hole_list.append(boundary_hole)
			var simplified_hole := _simplify_unit_ring(hole, INTERACTIVE_SURFACE_RING_POINTS)
			if simplified_hole.size() >= 3:
				simplified_hole_list.append(simplified_hole)
		boundary_holes.append(boundary_hole_list)
		var reference_longitude := _map_unit_to_lon_lat(simplified_source[0]).x
		var planar_polygons: Array[PackedVector2Array] = [
			_unwrapped_planar_ring(simplified_source, reference_longitude)
		]
		var simplified_outer_planar: PackedVector2Array = planar_polygons[0]
		source_planar_area += _planar_polygon_area(simplified_outer_planar)
		for hole_value: Variant in simplified_hole_list:
			var planar_hole := _unwrapped_planar_ring(hole_value as PackedVector3Array, reference_longitude)
			source_planar_area -= _planar_polygon_area(planar_hole)
			var difference: Array[PackedVector2Array] = []
			for polygon: PackedVector2Array in planar_polygons:
				for result_value: Variant in Geometry2D.clip_polygons(polygon, planar_hole):
					if result_value is PackedVector2Array:
						difference.append(result_value as PackedVector2Array)
			planar_polygons = difference
		for polygon: PackedVector2Array in planar_polygons:
			if polygon.size() < 3:
				continue
			var triangle_indices: PackedInt32Array = _triangulate_planar_polygon(polygon)
			for index: int in range(0, triangle_indices.size(), 3):
				if index + 2 >= triangle_indices.size():
					break
				var first_index := int(triangle_indices[index])
				var second_index := int(triangle_indices[index + 1])
				var third_index := int(triangle_indices[index + 2])
				if (
					first_index < 0
					or second_index < 0
					or third_index < 0
					or first_index >= polygon.size()
					or second_index >= polygon.size()
					or third_index >= polygon.size()
				):
					continue
				var planar_triangle := PackedVector2Array([
					polygon[first_index],
					polygon[second_index],
					polygon[third_index],
				])
				if _planar_polygon_area(planar_triangle) <= MAP_TRIANGLE_AREA_EPSILON:
					continue
				var triangle_points := PackedVector3Array([
					_lon_lat_to_unit(planar_triangle[0]),
					_lon_lat_to_unit(planar_triangle[1]),
					_lon_lat_to_unit(planar_triangle[2]),
				])
				var center := (triangle_points[0] + triangle_points[1] + triangle_points[2]).normalized()
				var angular_margin := 0.0
				for point: Vector3 in triangle_points:
					angular_margin = maxf(
						angular_margin,
						2.0 * sin(acos(clampf(center.dot(point), -1.0, 1.0)) * 0.5)
					)
				visibility_centers.append(center)
				visibility_margins.append(angular_margin)
				for point: Vector3 in triangle_points:
					points.append(point)
				for point: Vector2 in planar_triangle:
					uvs.append(_planar_to_flag_uv(country_id, point))
				source_components.append("%s:%d" % [country_id, source_index])
				source_component_indices.append(source_index)
				# This is a presentation LOD triangle, not a new political source
				# triangle.  Keep the distinction explicit instead of pretending its
				# local index addresses the full-resolution triangulation cache.
				source_triangles.append(-1)
				source_triangle_originals.append(planar_triangle)
				triangulated_planar_area += _planar_polygon_area(planar_triangle)
	var country_visibility_center := Vector3.FORWARD
	if not points.is_empty():
		var center_sum := Vector3.ZERO
		for point: Vector3 in points:
			center_sum += point
		if center_sum.length_squared() > 0.000001:
			country_visibility_center = center_sum.normalized()
	var country_visibility_margin := 0.0
	for point: Vector3 in points:
		country_visibility_margin = maxf(
			country_visibility_margin,
			2.0 * sin(acos(clampf(country_visibility_center.dot(point), -1.0, 1.0)) * 0.5)
		)
	return {
		"buffer": {
			"points": points,
			"uvs": uvs,
			"visibility_centers": visibility_centers,
			"visibility_margins": visibility_margins,
			"source_components": source_components,
			"source_component_indices": source_component_indices,
			"source_triangles": source_triangles,
			"source_triangle_originals": source_triangle_originals,
			"source_planar_area": maxf(source_planar_area, 0.0),
			"triangulated_planar_area": triangulated_planar_area,
			"country_visibility_center": country_visibility_center,
			"country_visibility_margin": country_visibility_margin,
			"provenance_mode": "INTERACTION_BOUNDARY_LOD",
		},
		"boundaries": {
			"sources": boundary_sources,
			"holes": boundary_holes,
		},
	}


func _simplify_unit_ring(source: PackedVector3Array, max_points: int) -> PackedVector3Array:
	if source.size() <= max_points:
		return source
	if source.size() < 3:
		return PackedVector3Array()
	var reference_longitude := _map_unit_to_lon_lat(source[0]).x
	# RDP is useful for coast fidelity but its recursive worst case is quadratic
	# on long historical rings. Bound its input first; the authoritative full
	# ring remains untouched and is still used by the idle geometry path/audits.
	var simplification_source := source
	if source.size() > 512:
		var sampled := PackedVector3Array()
		var stride := maxi(1, ceili(float(source.size()) / 512.0))
		for point_index: int in range(0, source.size(), stride):
			sampled.append(source[point_index])
		if sampled.size() >= 3:
			simplification_source = sampled
	var planar := _unwrapped_planar_ring(simplification_source, reference_longitude)
	var simplified := _simplify_line(planar, max_points)
	if simplified.size() < 3:
		return source
	var output := PackedVector3Array()
	for point: Vector2 in simplified:
		output.append(_lon_lat_to_unit(point))
	return output if output.size() >= 3 else source


func _camera_interaction_active() -> bool:
	if map_screen_topology_diagnostics_enabled:
		# The static topology audit must inspect the authoritative full surface
		# unless it explicitly marks the camera as actively dragging. This keeps
		# the diagnostic baseline independent from the presentation LOD hold.
		return dragging or absf(angular_velocity) > 0.0005
	return (
		dragging
		or absf(angular_velocity) > 0.0005
		or Time.get_ticks_usec() < _map_interaction_lod_until_usec
	)


func _mark_projection_dirty() -> void:
	if _detail_restore_in_progress:
		# New camera input invalidates the staged idle replacement. Keep the last
		# valid interaction surface and restart detail from the next quiet state.
		_detail_restore_in_progress = false
		_detail_restore_cursor = 0
		_detail_restore_revision = -1
	super._mark_projection_dirty()
	if not _map_runtime_interaction_enabled or not map_interaction_flag_lod_enabled or not is_inside_tree():
		return
	_map_interaction_lod_until_usec = maxi(
		_map_interaction_lod_until_usec,
		Time.get_ticks_usec() + MAP_INTERACTION_LOD_HOLD_USEC,
	)
	_schedule_camera_lod_refresh()


func _schedule_camera_lod_refresh(delay_seconds: float = 0.24) -> void:
	if _map_interaction_lod_timer_active or not is_inside_tree():
		return
	_map_interaction_lod_timer_active = true
	get_tree().create_timer(delay_seconds).timeout.connect(_on_camera_lod_refresh_timeout)


func _on_camera_lod_refresh_timeout() -> void:
	_map_interaction_lod_timer_active = false
	var remaining_usec := _map_interaction_lod_until_usec - Time.get_ticks_usec()
	if remaining_usec > 0:
		_schedule_camera_lod_refresh(float(remaining_usec) / 1000000.0)
		return
	_map_interaction_lod_until_usec = 0
	_detail_restore_in_progress = true
	_detail_restore_cursor = 0
	_detail_restore_revision = -1
	_last_map_cache_lod = "interactive"
	# Invalidate once after the input quiet period so the next idle frame
	# incrementally restores the complete flag/border presentation from the same
	# cached provenance records. Calling the base method avoids extending the hold.
	super._mark_projection_dirty()
	queue_redraw()


func _rebuild_country_flag_cache_fast() -> void:
	var cache_start_usec: int = Time.get_ticks_usec()
	var static_build_incremental := not _static_surface_build_complete
	var staged_detail_restore := _detail_restore_in_progress
	_map_profile_static_triangulation_usec = 0
	_interactive_source_triangles_processed = 0
	_interactive_front_triangles = 0
	_interactive_behind_triangles = 0
	_interactive_horizon_clipped_triangles = 0
	_interactive_projected_vertices = 0
	_interactive_screen_triangles = 0
	_interactive_clip_temp_array_count = 0
	_interactive_provenance_string_lookups = 0
	if staged_detail_restore:
		if _detail_restore_revision != _projection_revision:
			_flag_screen_polygons.clear()
			_flag_screen_triangle_records.clear()
			_flag_screen_bounds.clear()
			_country_screen_boundary_segments.clear()
			_country_screen_meshes.clear()
			_country_screen_triangle_counts.clear()
			_detail_restore_cursor = 0
			_detail_restore_revision = _projection_revision
	elif not static_build_incremental or _static_projection_cache_revision != _projection_revision:
		_flag_screen_polygons.clear()
		_flag_screen_triangle_records.clear()
		_interactive_flag_screen_points.clear()
		_interactive_flag_screen_components.clear()
		_interactive_flag_screen_component_indices.clear()
		_interactive_flag_screen_source_triangles.clear()
		_interactive_flag_screen_clipped_children.clear()
		_flag_screen_bounds.clear()
		_country_screen_boundary_segments.clear()
		_country_screen_meshes.clear()
		_country_screen_triangle_counts.clear()
		_map_render_stage_records.clear()
		_static_projection_cache_revision = _projection_revision
	_ensure_country_flag_uv_bounds()
	_ensure_country_surface_triangle_buffers()
	var basis: Basis = Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, yaw)
	var screen_center := _hemisphere_center
	var screen_radius := _hemisphere_radius
	var interaction_projection_active := _camera_interaction_active()
	# The post-input replacement first expands the already-warmed interaction
	# surface into flag records. This keeps geometry/UVs paired and avoids a
	# synchronous full-resolution rebuild before the neutral map is stable.
	var interactive_lod := interaction_projection_active or staged_detail_restore
	var collect_screen_topology := map_screen_topology_diagnostics_enabled
	# During active movement the flag/border layer is deferred.  Keep the same
	# authoritative source triangles, but avoid allocating one nested Dictionary
	# per screen triangle; the compact parallel buffers below retain provenance
	# through submission and are expanded only for diagnostic/full-flag frames.
	var compact_interactive_records := interactive_lod and not collect_screen_topology and not staged_detail_restore
	var previous_cache_lod := _last_map_cache_lod
	if staged_detail_restore:
		_last_map_cache_lod = "interactive"
	else:
		_last_map_cache_lod = "interactive" if interactive_lod else "full"
	if (
		_physical_land_projection_cache_revision != _projection_revision
		or previous_cache_lod != _last_map_cache_lod
	):
		_rebuild_physical_land_projection_cache(basis, interactive_lod)
	var camera_normal := Vector3(basis.x.z, basis.y.z, basis.z.z)
	var boundary_projection_usec: int = 0
	var camera_projection_usec: int = 0
	var clipping_usec: int = 0
	var mesh_build_usec: int = 0
	var projection_rejection_samples: Array[Dictionary] = []
	var horizon_subpixel_rejections: int = 0
	for country_index: int in range(_countries.size()):
		if staged_detail_restore and Time.get_ticks_usec() - cache_start_usec >= MAP_DETAIL_RESTORE_BUDGET_USEC:
			break
		if staged_detail_restore and country_index < _detail_restore_cursor:
			continue
		if staged_detail_restore:
			_detail_restore_cursor = country_index + 1
		var country: Dictionary = _countries[country_index] as Dictionary
		var country_id := str(country.get("id", ""))
		if static_build_incremental:
			var cache_has_country := (
				_interactive_flag_screen_component_indices.has(country_id)
				if interactive_lod
				else _flag_screen_triangle_records.has(country_id)
			)
			if cache_has_country:
				continue
		var source_polygons: Array = _country_unit_polygons.get(country_id, []) as Array
		# Interaction LOD uses a camera-independent, per-component boundary cache.
		# It never changes ownership or joins components; the full buffer remains
		# authoritative for idle/high-detail rendering and all source audits.
		var full_surface_buffer: Dictionary = _country_surface_triangle_buffers.get(country_id, {}) as Dictionary
		var surface_buffer: Dictionary = (
			_interactive_country_surface_triangle_buffers.get(country_id, full_surface_buffer) as Dictionary
			if interactive_lod
			else full_surface_buffer
		)
		var boundary_sources: Array = source_polygons
		var boundary_holes: Array = []
		var source_component_screen_bounds: Dictionary = {}
		if collect_screen_topology:
			for source_index: int in range(boundary_sources.size()):
				var source_candidates := _source_screen_candidates(boundary_sources[source_index] as PackedVector3Array, basis)
				var source_bounds := _bounds_for_points(source_candidates)
				if source_bounds.size.x > 0.0 and source_bounds.size.y > 0.0:
					source_component_screen_bounds["%s:%d" % [country_id, source_index]] = source_bounds
		var source_points: PackedVector3Array = surface_buffer.get("points", PackedVector3Array()) as PackedVector3Array
		var source_uvs: PackedVector2Array = surface_buffer.get("uvs", PackedVector2Array()) as PackedVector2Array
		var indexed_vertices: PackedVector3Array = surface_buffer.get("indexed_vertices", PackedVector3Array()) as PackedVector3Array
		var indexed_triangle_indices: PackedInt32Array = surface_buffer.get("indexed_triangle_indices", PackedInt32Array()) as PackedInt32Array
		var visibility_centers: PackedVector3Array = surface_buffer.get("visibility_centers", PackedVector3Array()) as PackedVector3Array
		var visibility_margins: PackedFloat32Array = surface_buffer.get("visibility_margins", PackedFloat32Array()) as PackedFloat32Array
		var source_components: Array = surface_buffer.get("source_components", []) as Array
		var source_component_indices: PackedInt32Array = surface_buffer.get("source_component_indices", PackedInt32Array()) as PackedInt32Array
		var source_triangles: PackedInt32Array = surface_buffer.get("source_triangles", PackedInt32Array()) as PackedInt32Array
		var source_triangle_originals: Array = surface_buffer.get("source_triangle_originals", []) as Array
		var visible_polygons: Array[PackedVector2Array] = []
		var visible_triangle_records: Array[Dictionary] = []
		var boundary_segments: Array[PackedVector2Array] = []
		var has_bounds := false
		var minimum := Vector2(100000.0, 100000.0)
		var maximum := Vector2(-100000.0, -100000.0)
		var source_triangle_count: int = source_points.size() / 3
		var visible_source_triangle_count := 0
		var clipped_visible_triangle_count := 0
		var missing_visible_triangle_count := 0
		var invalid_projected_parts := 0
		var front_facing_geometry := false
		var source_planar_area := float(surface_buffer.get("source_planar_area", 0.0))
		var triangulated_planar_area := float(surface_buffer.get("triangulated_planar_area", 0.0))
		var visible_projected_area := 0.0
		var expected_visible_projected_area := 0.0
		var tiny_surface_fallback_parts := 0
		var has_drawable_source_triangle := false
		var tiny_surface_candidate: Dictionary = {}
		var compact_component_indices := PackedInt32Array()
		var compact_source_triangles := PackedInt32Array()
		var compact_clipped_children := PackedInt32Array()
		var compact_screen_points := PackedVector2Array()
		var visible_triangle_count := 0
		var boundary_source_count := (
			boundary_sources.size()
			if not interactive_lod and _static_surface_build_complete
			else 0
		)
		for source_index: int in range(boundary_source_count):
			var source: PackedVector3Array = boundary_sources[source_index]
			var holes_to_project: Array = []
			if interactive_lod:
				if source_index < boundary_holes.size():
					holes_to_project = boundary_holes[source_index] as Array
			else:
				holes_to_project = _holes_for_surface_source(country_id, source_index)
			# Borders are deliberately deferred during active camera input.  The
			# validated political surface still projects below; retaining every
			# boundary segment here would spend 6-11ms per input frame on a layer
			# that is intentionally hidden/simplified while moving.
			if not interactive_lod:
				var boundary_start_usec: int = Time.get_ticks_usec()
				for boundary_segment: PackedVector2Array in _project_closed_unit_boundary_fast(source, basis):
					boundary_segments.append(boundary_segment)
				for hole_value: Variant in holes_to_project:
					var hole: PackedVector3Array = hole_value
					for boundary_segment: PackedVector2Array in _project_closed_unit_boundary_fast(hole, basis):
						boundary_segments.append(boundary_segment)
				boundary_projection_usec += Time.get_ticks_usec() - boundary_start_usec
		var country_visibility_center: Vector3 = surface_buffer.get("country_visibility_center", Vector3.FORWARD) as Vector3
		var country_visibility_margin := float(surface_buffer.get("country_visibility_margin", 2.0))
		if camera_normal.dot(country_visibility_center) + country_visibility_margin <= MAP_TRIANGLE_DEPTH_EPSILON:
			_map_render_stage_records[country_id] = _make_map_render_stage_record(
				country_id,
				source_polygons.size(),
				0,
				0,
				false,
				0,
				false,
				0,
				source_triangle_count,
				0,
				0,
				0,
				0,
				source_planar_area,
				triangulated_planar_area,
				0.0,
				0.0
			)
			continue
		var use_indexed_projection := indexed_vertices.size() > 0 and indexed_triangle_indices.size() >= source_triangle_count * 3
		var projected_vertices := PackedVector3Array()
		var projected_vertex_screens := PackedVector2Array()
		var projected_vertex_ready := PackedByteArray()
		if use_indexed_projection:
			projected_vertices.resize(indexed_vertices.size())
			projected_vertex_screens.resize(indexed_vertices.size())
			if interactive_lod:
				projected_vertex_ready.resize(indexed_vertices.size())
				# Back-facing source triangles are rejected from their static
				# visibility bounds below.  Do not transform every indexed vertex
				# before that rejection: during camera input this was the dominant
				# avoidable cost.  The first triangle that actually needs a vertex
				# fills the same camera-local arrays, preserving the authoritative
				# source triangle and provenance path.
			else:
				for vertex_index: int in range(indexed_vertices.size()):
					var projected_vertex := basis * indexed_vertices[vertex_index]
					projected_vertices[vertex_index] = projected_vertex
					projected_vertex_screens[vertex_index] = screen_center + Vector2(projected_vertex.x, -projected_vertex.y) * screen_radius
		var camera_projection_start_usec: int = Time.get_ticks_usec()
		for triangle_index: int in range(source_triangle_count):
			var triangle_offset: int = triangle_index * 3
			if interactive_lod:
				_interactive_source_triangles_processed += 1
			var center_depth: float = camera_normal.dot(visibility_centers[triangle_index]) if triangle_index < visibility_centers.size() else -INF
			var angular_margin: float = visibility_margins[triangle_index] if triangle_index < visibility_margins.size() else 2.0
			if center_depth + angular_margin <= MAP_TRIANGLE_DEPTH_EPSILON:
				if interactive_lod:
					_interactive_behind_triangles += 1
				continue
			var fully_front: bool = center_depth - angular_margin >= -MAP_TRIANGLE_DEPTH_EPSILON
			if interactive_lod:
				if fully_front:
					_interactive_front_triangles += 1
				else:
					_interactive_horizon_clipped_triangles += 1
			var projected_triangle_count := 0
			var first_point := Vector3.ZERO
			var second_point := Vector3.ZERO
			var third_point := Vector3.ZERO
			var first_screen := Vector2.ZERO
			var second_screen := Vector2.ZERO
			var third_screen := Vector2.ZERO
			if use_indexed_projection:
				var first_vertex_index := int(indexed_triangle_indices[triangle_offset])
				var second_vertex_index := int(indexed_triangle_indices[triangle_offset + 1])
				var third_vertex_index := int(indexed_triangle_indices[triangle_offset + 2])
				if (
					first_vertex_index < 0 or first_vertex_index >= projected_vertices.size()
					or second_vertex_index < 0 or second_vertex_index >= projected_vertices.size()
					or third_vertex_index < 0 or third_vertex_index >= projected_vertices.size()
				):
					continue
				if interactive_lod:
					if projected_vertex_ready[first_vertex_index] == 0:
						projected_vertices[first_vertex_index] = basis * indexed_vertices[first_vertex_index]
						projected_vertex_screens[first_vertex_index] = screen_center + Vector2(projected_vertices[first_vertex_index].x, -projected_vertices[first_vertex_index].y) * screen_radius
						projected_vertex_ready[first_vertex_index] = 1
						_interactive_projected_vertices += 1
					if projected_vertex_ready[second_vertex_index] == 0:
						projected_vertices[second_vertex_index] = basis * indexed_vertices[second_vertex_index]
						projected_vertex_screens[second_vertex_index] = screen_center + Vector2(projected_vertices[second_vertex_index].x, -projected_vertices[second_vertex_index].y) * screen_radius
						projected_vertex_ready[second_vertex_index] = 1
						_interactive_projected_vertices += 1
					if projected_vertex_ready[third_vertex_index] == 0:
						projected_vertices[third_vertex_index] = basis * indexed_vertices[third_vertex_index]
						projected_vertex_screens[third_vertex_index] = screen_center + Vector2(projected_vertices[third_vertex_index].x, -projected_vertices[third_vertex_index].y) * screen_radius
						projected_vertex_ready[third_vertex_index] = 1
						_interactive_projected_vertices += 1
				first_point = projected_vertices[first_vertex_index]
				second_point = projected_vertices[second_vertex_index]
				third_point = projected_vertices[third_vertex_index]
				first_screen = projected_vertex_screens[first_vertex_index]
				second_screen = projected_vertex_screens[second_vertex_index]
				third_screen = projected_vertex_screens[third_vertex_index]
			if fully_front:
				if not use_indexed_projection:
					first_point = basis * source_points[triangle_offset]
					second_point = basis * source_points[triangle_offset + 1]
					third_point = basis * source_points[triangle_offset + 2]
					first_screen = screen_center + Vector2(first_point.x, -first_point.y) * screen_radius
					second_screen = screen_center + Vector2(second_point.x, -second_point.y) * screen_radius
					third_screen = screen_center + Vector2(third_point.x, -third_point.y) * screen_radius
				var triangle_area := absf(
					first_screen.x * (second_screen.y - third_screen.y)
					+ second_screen.x * (third_screen.y - first_screen.y)
					+ third_screen.x * (first_screen.y - second_screen.y)
				) * 0.5
				var valid_screen_triangle := triangle_area > 0.0
				if not interactive_lod:
					valid_screen_triangle = (
						is_finite(first_screen.x) and is_finite(first_screen.y)
						and is_finite(second_screen.x) and is_finite(second_screen.y)
						and is_finite(third_screen.x) and is_finite(third_screen.y)
						and valid_screen_triangle
					)
				if valid_screen_triangle:
					var source_component_index: int = int(source_component_indices[triangle_index]) if triangle_index < source_component_indices.size() else -1
					var source_triangle_id: int = int(source_triangles[triangle_index]) if triangle_index < source_triangles.size() else triangle_index
					if triangle_area > MAP_SCREEN_TRIANGLE_AREA_EPSILON:
						if compact_interactive_records:
							compact_screen_points.append(first_screen)
							compact_screen_points.append(second_screen)
							compact_screen_points.append(third_screen)
							compact_component_indices.append(source_component_index)
							compact_source_triangles.append(source_triangle_id)
							compact_clipped_children.append(0)
						else:
							var source_component_id: String = str(source_components[triangle_index]) if triangle_index < source_components.size() else ""
							var component_bounds: Rect2 = source_component_screen_bounds.get(source_component_id, Rect2()) as Rect2
							var source_triangle_original_planar := (
								source_triangle_originals[triangle_index] as PackedVector2Array
								if triangle_index < source_triangle_originals.size()
								else PackedVector2Array()
							)
							var source_screen_triangle := PackedVector2Array([first_screen, second_screen, third_screen])
							var triangle_uvs := PackedVector2Array([
								source_uvs[triangle_offset],
								source_uvs[triangle_offset + 1],
								source_uvs[triangle_offset + 2],
							])
							var topology := (
								_screen_triangle_topology_diagnostic(
									source_screen_triangle,
									component_bounds,
									false,
									source_triangle_original_planar,
									basis
								)
								if collect_screen_topology
								else {}
							)
							visible_polygons.append(source_screen_triangle)
							visible_triangle_records.append({
								"screen": source_screen_triangle,
								"uvs": triangle_uvs,
								"source_component": source_component_id,
								"source_triangle": source_triangle_id,
								"clipped_child": 0,
								"representation": "SOURCE_TRIANGLE",
								"source_screen_area": triangle_area,
								"topology": topology,
						})
						visible_triangle_count += 1
						if compact_interactive_records:
							_interactive_screen_triangles += 1
						has_drawable_source_triangle = true
						visible_projected_area += triangle_area
						expected_visible_projected_area += triangle_area
						projected_triangle_count = 1
					if not interactive_lod:
						has_bounds = true
						minimum.x = minf(minimum.x, minf(first_screen.x, minf(second_screen.x, third_screen.x)))
						minimum.y = minf(minimum.y, minf(first_screen.y, minf(second_screen.y, third_screen.y)))
						maximum.x = maxf(maximum.x, maxf(first_screen.x, maxf(second_screen.x, third_screen.x)))
						maximum.y = maxf(maximum.y, maxf(first_screen.y, maxf(second_screen.y, third_screen.y)))
					elif tiny_surface_candidate.is_empty():
						var source_screen_triangle := PackedVector2Array([first_screen, second_screen, third_screen])
						tiny_surface_candidate = {
							"screen": source_screen_triangle,
							"uvs": PackedVector2Array([
								source_uvs[triangle_offset],
								source_uvs[triangle_offset + 1],
								source_uvs[triangle_offset + 2],
							]) if not interactive_lod else PackedVector2Array(),
							"source_triangle": source_triangle_id,
							"source_component_index": source_component_index,
							"source_component": str(source_components[triangle_index]) if not compact_interactive_records and triangle_index < source_components.size() else "",
						}
			else:
				var clipping_start_usec: int = Time.get_ticks_usec()
				if not use_indexed_projection:
					first_point = basis * source_points[triangle_offset]
					second_point = basis * source_points[triangle_offset + 1]
					third_point = basis * source_points[triangle_offset + 2]
				if interactive_lod:
					var screen_triangles := _interactive_clipped_screen_triangles(first_point, second_point, third_point)
					var screen_triangle_uvs: Array[PackedVector2Array] = []
					if staged_detail_restore:
						var clipped_with_uv := _clip_front_facing_triangle_with_uv(
							PackedVector3Array([first_point, second_point, third_point]),
							PackedVector2Array([
								source_uvs[triangle_offset],
								source_uvs[triangle_offset + 1],
								source_uvs[triangle_offset + 2],
							])
						)
						var uv_records := _screen_triangle_records(
							clipped_with_uv.get("points", PackedVector3Array()) as PackedVector3Array,
							clipped_with_uv.get("uvs", PackedVector2Array()) as PackedVector2Array,
							true
						)
						for uv_record_value: Variant in uv_records:
							screen_triangle_uvs.append((uv_record_value as Dictionary).get("uvs", PackedVector2Array()) as PackedVector2Array)
					clipping_usec += Time.get_ticks_usec() - clipping_start_usec
					var source_component_index: int = int(source_component_indices[triangle_index]) if triangle_index < source_component_indices.size() else -1
					var source_triangle_id: int = int(source_triangles[triangle_index]) if triangle_index < source_triangles.size() else triangle_index
					var candidate_area := 0.0
					for child_offset: int in range(0, screen_triangles.size(), 3):
						if child_offset + 2 >= screen_triangles.size():
							break
						var first_clipped_screen := screen_triangles[child_offset]
						var second_clipped_screen := screen_triangles[child_offset + 1]
						var third_clipped_screen := screen_triangles[child_offset + 2]
						var child_area := absf(
							first_clipped_screen.x * (second_clipped_screen.y - third_clipped_screen.y)
							+ second_clipped_screen.x * (third_clipped_screen.y - first_clipped_screen.y)
							+ third_clipped_screen.x * (first_clipped_screen.y - second_clipped_screen.y)
						) * 0.5
						candidate_area += child_area
						if child_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
							if tiny_surface_candidate.is_empty():
								tiny_surface_candidate = {
									"screen": PackedVector2Array([
										first_clipped_screen,
										second_clipped_screen,
										third_clipped_screen,
									]),
									"uvs": PackedVector2Array(),
									"source_triangle": source_triangle_id,
									"clipped_child": child_offset / 3,
									"source_component_index": source_component_index,
								}
							continue
						if compact_interactive_records:
							compact_screen_points.append(first_clipped_screen)
							compact_screen_points.append(second_clipped_screen)
							compact_screen_points.append(third_clipped_screen)
							compact_component_indices.append(source_component_index)
							compact_source_triangles.append(source_triangle_id)
							compact_clipped_children.append(child_offset / 3)
						else:
							var screen_triangle := PackedVector2Array([
								first_clipped_screen,
								second_clipped_screen,
								third_clipped_screen,
							])
							var source_component_id: String = str(source_components[triangle_index]) if triangle_index < source_components.size() else ""
							var component_bounds: Rect2 = source_component_screen_bounds.get(source_component_id, Rect2()) as Rect2
							var source_triangle_original_planar := (
								source_triangle_originals[triangle_index] as PackedVector2Array
								if triangle_index < source_triangle_originals.size()
								else PackedVector2Array()
							)
							var topology := (
								_screen_triangle_topology_diagnostic(
									screen_triangle,
									component_bounds,
									false,
									source_triangle_original_planar,
									basis
								)
								if collect_screen_topology
								else {}
							)
							visible_polygons.append(screen_triangle)
							visible_triangle_records.append({
								"screen": screen_triangle,
								"uvs": screen_triangle_uvs[child_offset / 3] if staged_detail_restore and child_offset / 3 < screen_triangle_uvs.size() else PackedVector2Array(),
								"source_component": source_component_id,
								"source_triangle": source_triangle_id,
								"clipped_child": child_offset / 3,
								"topology": topology,
							})
						visible_triangle_count += 1
						if compact_interactive_records:
							_interactive_screen_triangles += 1
						has_drawable_source_triangle = true
						visible_projected_area += child_area
						expected_visible_projected_area += child_area
						projected_triangle_count += 1
						has_bounds = true
						minimum.x = minf(minimum.x, minf(first_clipped_screen.x, minf(second_clipped_screen.x, third_clipped_screen.x)))
						minimum.y = minf(minimum.y, minf(first_clipped_screen.y, minf(second_clipped_screen.y, third_clipped_screen.y)))
						maximum.x = maxf(maximum.x, maxf(first_clipped_screen.x, maxf(second_clipped_screen.x, third_clipped_screen.x)))
						maximum.y = maxf(maximum.y, maxf(first_clipped_screen.y, maxf(second_clipped_screen.y, third_clipped_screen.y)))
					if projected_triangle_count == 0 and not screen_triangles.is_empty() and candidate_area > 0.0:
						if tiny_surface_candidate.is_empty():
							tiny_surface_candidate = {
								"screen": PackedVector2Array([
									screen_triangles[0], screen_triangles[1], screen_triangles[2],
								]),
								"uvs": PackedVector2Array(),
								"source_triangle": source_triangle_id,
								"clipped_child": 0,
								"source_component_index": source_component_index,
							}
				else:
					var transformed := PackedVector3Array([first_point, second_point, third_point])
					var triangle_uvs := PackedVector2Array([
						source_uvs[triangle_offset],
						source_uvs[triangle_offset + 1],
						source_uvs[triangle_offset + 2],
					])
					var clipped := _clip_front_facing_triangle_with_uv(transformed, triangle_uvs)
					clipping_usec += Time.get_ticks_usec() - clipping_start_usec
					var candidate_points: PackedVector3Array = clipped.get("points", PackedVector3Array()) as PackedVector3Array
					var candidate_uvs: PackedVector2Array = clipped.get("uvs", PackedVector2Array()) as PackedVector2Array
					var candidate_area := _screen_area_for_unit_points(candidate_points)
					var projected_triangles: Array[Dictionary] = []
					if candidate_area > MAP_SCREEN_TRIANGLE_AREA_EPSILON:
						projected_triangles = _screen_triangle_records(candidate_points, candidate_uvs, not interactive_lod)
					if not projected_triangles.is_empty():
						for clipped_child: int in range(projected_triangles.size()):
							var triangle_record: Dictionary = projected_triangles[clipped_child]
							var screen_triangle: PackedVector2Array = triangle_record.get("screen", PackedVector2Array()) as PackedVector2Array
							var clipped_uvs: PackedVector2Array = triangle_record.get("uvs", PackedVector2Array()) as PackedVector2Array
							var source_component_id: String = str(source_components[triangle_index]) if triangle_index < source_components.size() else ""
							var component_bounds: Rect2 = source_component_screen_bounds.get(source_component_id, Rect2()) as Rect2
							var source_triangle_original_planar := (
								source_triangle_originals[triangle_index] as PackedVector2Array
								if triangle_index < source_triangle_originals.size()
								else PackedVector2Array()
							)
							var topology := (
								_screen_triangle_topology_diagnostic(
									screen_triangle,
									component_bounds,
									false,
									source_triangle_original_planar,
									basis
								)
								if collect_screen_topology
								else {}
							)
							visible_polygons.append(screen_triangle)
							visible_triangle_records.append({
								"screen": screen_triangle,
								"uvs": clipped_uvs,
								"source_component": source_component_id,
								"source_triangle": int(source_triangles[triangle_index]) if triangle_index < source_triangles.size() else triangle_index,
								"clipped_child": clipped_child,
								"topology": topology,
							})
							visible_triangle_count += 1
							has_drawable_source_triangle = true
							var child_area := float(triangle_record.get("area", 0.0))
							visible_projected_area += child_area
							expected_visible_projected_area += child_area
							projected_triangle_count += 1
							for point: Vector2 in screen_triangle:
								if not interactive_lod:
									has_bounds = true
									minimum.x = minf(minimum.x, point.x)
									minimum.y = minf(minimum.y, point.y)
									maximum.x = maxf(maximum.x, point.x)
									maximum.y = maxf(maximum.y, point.y)
					if projected_triangle_count == 0 and candidate_area > 0.0 and candidate_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
						var candidate_screen := PackedVector2Array()
						for candidate_point: Vector3 in candidate_points:
							candidate_screen.append(screen_center + Vector2(candidate_point.x, -candidate_point.y) * screen_radius)
						var source_component_id: String = str(source_components[triangle_index]) if triangle_index < source_components.size() else ""
						var source_triangle_id: int = int(source_triangles[triangle_index]) if triangle_index < source_triangles.size() else triangle_index
						if tiny_surface_candidate.is_empty():
							tiny_surface_candidate = {
								"screen": candidate_screen,
								"uvs": candidate_uvs,
								"source_triangle": source_triangle_id,
								"clipped_child": -1,
								"source_component": source_component_id,
							}
					elif projected_triangle_count == 0 and candidate_area > MAP_SCREEN_TRIANGLE_AREA_EPSILON:
						var rejection_reason := "INVALID_SCREEN_CLIP"
						if candidate_area <= MAP_SCREEN_FRAGMENT_AREA_EPSILON:
							horizon_subpixel_rejections += 1
							rejection_reason = "SUBPIXEL_HORIZON_FRAGMENT"
						else:
							expected_visible_projected_area += candidate_area
							missing_visible_triangle_count += 1
							invalid_projected_parts += 1
						var candidate_screen := PackedVector2Array()
						for candidate_point: Vector3 in candidate_points:
							candidate_screen.append(screen_center + Vector2(candidate_point.x, -candidate_point.y) * screen_radius)
						if projection_rejection_samples.size() < 64:
							projection_rejection_samples.append({
								"entity_id": country_id,
								"source_component": source_components[triangle_index] if triangle_index < source_components.size() else "",
								"source_triangle": int(source_triangles[triangle_index]) if triangle_index < source_triangles.size() else triangle_index,
								"candidate_area": candidate_area,
								"candidate_screen": _packed_vector2_array_to_arrays(candidate_screen),
								"reason": rejection_reason,
							})
			if projected_triangle_count > 0:
				visible_source_triangle_count += 1
				front_facing_geometry = true
				clipped_visible_triangle_count += projected_triangle_count
		if not has_drawable_source_triangle and not tiny_surface_candidate.is_empty():
			var candidate := tiny_surface_candidate
			var candidate_component_index := int(candidate.get("source_component_index", -1))
			var source_component_id := str(candidate.get("source_component", ""))
			if source_component_id.is_empty() and candidate_component_index >= 0:
				source_component_id = "%s:%d" % [country_id, candidate_component_index]
			var candidate_screen: PackedVector2Array = candidate.get("screen", PackedVector2Array()) as PackedVector2Array
			if candidate_screen.size() < 3:
				continue
			var marker_triangle := _minimum_surface_marker(candidate_screen)
			var marker_area := _screen_polygon_area(marker_triangle)
			if marker_triangle.size() != 3 or marker_area <= 0.0:
				continue
			var component_bounds: Rect2 = source_component_screen_bounds.get(source_component_id, Rect2()) as Rect2
			var candidate_uvs: PackedVector2Array = candidate.get("uvs", PackedVector2Array()) as PackedVector2Array
			var marker_uvs := _minimum_surface_marker_uvs(candidate_uvs) if not interactive_lod else PackedVector2Array()
			var topology := (
				_screen_triangle_topology_diagnostic(marker_triangle, component_bounds, true)
				if collect_screen_topology
				else {}
			)
			if compact_interactive_records:
				compact_screen_points.append(marker_triangle[0])
				compact_screen_points.append(marker_triangle[1])
				compact_screen_points.append(marker_triangle[2])
				compact_component_indices.append(candidate_component_index)
				compact_source_triangles.append(int(candidate.get("source_triangle", -1)))
				compact_clipped_children.append(int(candidate.get("clipped_child", 0)))
				_interactive_screen_triangles += 1
			else:
				visible_polygons.append(marker_triangle)
				visible_triangle_records.append({
					"screen": marker_triangle,
					"uvs": marker_uvs,
					"source_component": source_component_id,
					"source_triangle": int(candidate.get("source_triangle", -1)),
					"clipped_child": int(candidate.get("clipped_child", 0)),
					"representation": "MINIMUM_DRAWABLE_SURFACE",
					"source_screen_area": _screen_polygon_area(candidate_screen),
					"topology": topology,
				})
			visible_triangle_count += 1
			visible_source_triangle_count += 1
			front_facing_geometry = true
			clipped_visible_triangle_count += 1
			visible_projected_area += marker_area
			expected_visible_projected_area += marker_area
			tiny_surface_fallback_parts += 1
			if not interactive_lod:
				for point: Vector2 in marker_triangle:
					has_bounds = true
					minimum.x = minf(minimum.x, point.x)
					minimum.y = minf(minimum.y, point.y)
					maximum.x = maxf(maximum.x, point.x)
					maximum.y = maxf(maximum.y, point.y)
		camera_projection_usec += Time.get_ticks_usec() - camera_projection_start_usec
		if not boundary_segments.is_empty():
			_country_screen_boundary_segments[country_id] = boundary_segments
		if visible_triangle_count <= 0:
			_map_render_stage_records[country_id] = _make_map_render_stage_record(
				country_id,
				source_polygons.size(),
				clipped_visible_triangle_count,
				0,
				front_facing_geometry,
				invalid_projected_parts,
				false,
				tiny_surface_fallback_parts,
				source_triangle_count,
				visible_source_triangle_count,
				clipped_visible_triangle_count,
				0,
				missing_visible_triangle_count,
				source_planar_area,
				triangulated_planar_area,
				visible_projected_area,
				expected_visible_projected_area
			)
			continue
		if compact_interactive_records:
			_interactive_flag_screen_points[country_id] = compact_screen_points
			_interactive_flag_screen_component_indices[country_id] = compact_component_indices
			_interactive_flag_screen_source_triangles[country_id] = compact_source_triangles
			_interactive_flag_screen_clipped_children[country_id] = compact_clipped_children
		else:
			_flag_screen_polygons[country_id] = visible_polygons
			_flag_screen_triangle_records[country_id] = visible_triangle_records
		if has_bounds:
			_flag_screen_bounds[country_id] = Rect2(minimum, maximum - minimum)
		_country_screen_triangle_counts[country_id] = visible_triangle_count
		var zero_size_bounds := false
		if not interactive_lod:
			var country_bounds: Rect2 = _flag_screen_bounds.get(country_id, Rect2()) as Rect2
			zero_size_bounds = country_bounds.size.x <= MAP_PROJECTED_AREA_EPSILON or country_bounds.size.y <= MAP_PROJECTED_AREA_EPSILON
		_map_render_stage_records[country_id] = _make_map_render_stage_record(
			country_id,
			source_polygons.size(),
			clipped_visible_triangle_count,
			visible_triangle_count,
			front_facing_geometry,
			invalid_projected_parts,
			zero_size_bounds,
			tiny_surface_fallback_parts,
			source_triangle_count,
			visible_source_triangle_count,
			clipped_visible_triangle_count,
			visible_triangle_count,
			missing_visible_triangle_count,
			source_planar_area,
			triangulated_planar_area,
			visible_projected_area,
			expected_visible_projected_area
		)
	if staged_detail_restore:
		if _detail_restore_cursor >= _countries.size():
			_detail_restore_in_progress = false
			_detail_restore_revision = _projection_revision
			_last_map_cache_lod = "full"
			_flag_projection_cache_revision = _projection_revision
		else:
			# Keep the interaction surface authoritative while the full flag layer
			# is replaced entity by entity on subsequent redraws.
			_flag_projection_cache_revision = -1
			queue_redraw()
	else:
		# Keep the flag revision invalid until every static source buffer has been
		# built. The next draw then continues the bounded build instead of blocking
		# Formal World entry on one monolithic all-polity triangulation pass.
		_flag_projection_cache_revision = _projection_revision if _static_surface_build_complete else -1
	_map_render_profile["flag_cache_build_usec"] = Time.get_ticks_usec() - cache_start_usec
	_map_render_profile["source_triangulation_usec"] = _map_profile_static_triangulation_usec
	_map_render_profile["boundary_projection_usec"] = boundary_projection_usec
	_map_render_profile["camera_projection_usec"] = camera_projection_usec
	_map_render_profile["hemisphere_clipping_usec"] = clipping_usec
	_map_render_profile["mesh_build_usec"] = 0
	_map_render_profile["static_triangulation_total_usec"] = _map_profile_static_triangulation_total_usec
	_map_render_profile["projection_rejection_samples"] = projection_rejection_samples
	_map_render_profile["horizon_subpixel_rejections"] = horizon_subpixel_rejections
	_map_render_profile["static_data_build_count"] = _static_data_build_count
	_map_render_profile["static_uv_build_count"] = _static_uv_build_count
	_map_render_profile["static_provenance_build_count"] = _static_provenance_build_count
	_map_render_profile["static_triangulation_build_count"] = _static_triangulation_build_count
	_map_render_profile["interactive_source_triangles_processed"] = _interactive_source_triangles_processed
	_map_render_profile["interactive_front_triangles"] = _interactive_front_triangles
	_map_render_profile["interactive_behind_triangles"] = _interactive_behind_triangles
	_map_render_profile["interactive_horizon_clipped_triangles"] = _interactive_horizon_clipped_triangles
	_map_render_profile["interactive_projected_vertices"] = _interactive_projected_vertices
	_map_render_profile["interactive_screen_triangles"] = _interactive_screen_triangles
	_map_render_profile["interactive_clip_temp_array_count"] = _interactive_clip_temp_array_count
	_map_render_profile["interactive_provenance_string_lookups"] = _interactive_provenance_string_lookups


func _project_surface_polygon(
	source: PackedVector3Array,
	country_id: String,
	source_index: int,
	basis: Basis
) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	if source.size() < 3:
		return output
	var cache_key := "%s:%d" % [country_id, source_index]
	var triangles := _surface_triangle_polygons(cache_key, country_id, source_index, source)
	for triangle: PackedVector3Array in triangles:
		var clipped := _clip_front_facing_triangle(triangle, basis)
		var screen := _screen_polygon_from_unit_points(clipped)
		if screen.size() >= 3:
			output.append(screen)
	return output


func _surface_triangle_polygons(
	cache_key: String,
	country_id: String,
	source_index: int,
	source: PackedVector3Array
) -> Array[PackedVector3Array]:
	if _country_surface_triangle_polygons.has(cache_key):
		return _country_surface_triangle_polygons.get(cache_key) as Array[PackedVector3Array]
	var records := _surface_triangle_records(cache_key, country_id, source_index, source)
	var triangles: Array[PackedVector3Array] = []
	for record_value: Variant in records:
		var record: Dictionary = record_value as Dictionary
		triangles.append(record.get("points", PackedVector3Array()) as PackedVector3Array)
	_country_surface_triangle_polygons[cache_key] = triangles
	return triangles


func _surface_triangle_records(
	cache_key: String,
	country_id: String,
	source_index: int,
	source: PackedVector3Array
) -> Array:
	if _country_surface_triangle_records.has(cache_key):
		return _country_surface_triangle_records.get(cache_key) as Array
	_static_triangulation_build_count += 1
	var static_start_usec: int = Time.get_ticks_usec()
	_ensure_country_flag_uv_bounds()
	var reference_longitude := float(_country_flag_uv_reference_longitudes.get(country_id, 0.0))
	var planar_outer := _unwrapped_planar_ring(source, reference_longitude)
	var planar_holes: Array[PackedVector2Array] = []
	var planar_polygons: Array[PackedVector2Array] = [planar_outer]
	for hole_value: Variant in _holes_for_surface_source(country_id, source_index):
		var hole: PackedVector3Array = hole_value
		var planar_hole := _unwrapped_planar_ring(hole, reference_longitude)
		if planar_hole.size() >= 3:
			planar_holes.append(planar_hole)
		var difference: Array[PackedVector2Array] = []
		for polygon: PackedVector2Array in planar_polygons:
			for result_value: Variant in Geometry2D.clip_polygons(polygon, planar_hole):
				if result_value is PackedVector2Array:
					var result_polygon := result_value as PackedVector2Array
					# Godot's difference operation can return the clip ring itself
					# when the CShapes hole winding matches the outer ring.  That
					# ring is not land and must never enter the triangulation cache.
					if _polygon_is_entirely_inside_ring(result_polygon, planar_hole):
						continue
					difference.append(result_polygon)
		planar_polygons = difference
	var source_area := _planar_polygon_area(planar_outer)
	for hole: PackedVector2Array in planar_holes:
		source_area -= _planar_polygon_area(hole)
	source_area = maxf(source_area, 0.0)
	var triangles_area := 0.0
	var records: Array[Dictionary] = []
	for polygon: PackedVector2Array in planar_polygons:
		var triangle_indices := _triangulate_planar_polygon(polygon)
		for index: int in range(0, triangle_indices.size(), 3):
			if index + 2 >= triangle_indices.size():
				break
			var first_index: int = int(triangle_indices[index])
			var second_index: int = int(triangle_indices[index + 1])
			var third_index: int = int(triangle_indices[index + 2])
			if (
				first_index < 0
				or second_index < 0
				or third_index < 0
				or first_index >= polygon.size()
				or second_index >= polygon.size()
				or third_index >= polygon.size()
			):
				continue
			var planar_triangle := PackedVector2Array([
				polygon[first_index],
				polygon[second_index],
				polygon[third_index],
			])
			var triangle_area := _planar_polygon_area(planar_triangle)
			if triangle_area <= MAP_TRIANGLE_AREA_EPSILON:
				continue
			if (
				(not planar_holes.is_empty() or map_topology_validation_enabled)
				and not _planar_triangle_respects_source(planar_triangle, planar_outer, planar_holes)
			):
				# Geometry2D.clip_polygons() can return a hole ring as an
				# additional result when the source and clip winding match the
				# CShapes convention.  Treat it as a rejected child, never as
				# political surface.
				continue
			var tessellated := _tessellate_planar_triangle(planar_triangle)
			for child_index: int in range(tessellated.size()):
				var child_planar: PackedVector2Array = tessellated[child_index]
				var child_area := _planar_polygon_area(child_planar)
				if child_area <= MAP_TRIANGLE_AREA_EPSILON:
					continue
				var triangle := PackedVector3Array([
					_lon_lat_to_unit(child_planar[0]),
					_lon_lat_to_unit(child_planar[1]),
					_lon_lat_to_unit(child_planar[2]),
				])
				var triangle_uvs := PackedVector2Array([
					_planar_to_flag_uv(country_id, child_planar[0]),
					_planar_to_flag_uv(country_id, child_planar[1]),
					_planar_to_flag_uv(country_id, child_planar[2]),
				])
				records.append({
					"points": triangle,
					"planar": child_planar,
					"uvs": triangle_uvs,
					"area": child_area,
					"source_triangle_parent": index / 3,
					"source_triangle_child": child_index,
					"source_triangle_original_planar": planar_triangle,
				})
				triangles_area += child_area
	_country_surface_triangle_records[cache_key] = records
	_country_surface_triangle_statistics[cache_key] = {
		"source_area": source_area,
		"triangulated_area": triangles_area,
		"triangle_count": records.size(),
		"triangulation_area_ratio": triangles_area / source_area if source_area > MAP_TRIANGLE_AREA_EPSILON else 1.0,
	}
	var elapsed_usec: int = Time.get_ticks_usec() - static_start_usec
	_map_profile_static_triangulation_usec += elapsed_usec
	_map_profile_static_triangulation_total_usec += elapsed_usec
	return records


func _planar_triangle_respects_source(
	triangle: PackedVector2Array,
	outer: PackedVector2Array,
	holes: Array[PackedVector2Array]
) -> bool:
	if triangle.size() != 3 or outer.size() < 3:
		return false
	var samples := PackedVector2Array([
		triangle[0] * 0.60 + triangle[1] * 0.20 + triangle[2] * 0.20,
		triangle[0] * 0.20 + triangle[1] * 0.60 + triangle[2] * 0.20,
		triangle[0] * 0.20 + triangle[1] * 0.20 + triangle[2] * 0.60,
		(triangle[0] + triangle[1] + triangle[2]) / 3.0,
		(triangle[0] + triangle[1]) * 0.5,
		(triangle[1] + triangle[2]) * 0.5,
		(triangle[2] + triangle[0]) * 0.5,
	])
	for sample: Vector2 in samples:
		if not _point_in_planar_ring(sample, outer):
			return false
		for hole: PackedVector2Array in holes:
			if _point_in_planar_ring(sample, hole):
				return false
	return true


func _tessellate_planar_triangle(triangle: PackedVector2Array, depth: int = 0) -> Array[PackedVector2Array]:
	if triangle.size() != 3:
		return []
	var maximum_edge := 0.0
	var triangle_area := _planar_polygon_area(triangle)
	for edge_index: int in range(3):
		maximum_edge = maxf(maximum_edge, triangle[edge_index].distance_to(triangle[(edge_index + 1) % 3]))
	if (
		depth >= map_debug_source_triangle_max_depth
		or (
			maximum_edge <= map_debug_source_triangle_max_edge_degrees
			and triangle_area <= MAP_SOURCE_TRIANGLE_SUBDIVISION_MIN_AREA
		)
	):
		return [triangle]
	var first_midpoint := triangle[0].lerp(triangle[1], 0.5)
	var second_midpoint := triangle[1].lerp(triangle[2], 0.5)
	var third_midpoint := triangle[2].lerp(triangle[0], 0.5)
	var children: Array[PackedVector2Array] = []
	for child: PackedVector2Array in [
		PackedVector2Array([triangle[0], first_midpoint, third_midpoint]),
		PackedVector2Array([first_midpoint, triangle[1], second_midpoint]),
		PackedVector2Array([third_midpoint, second_midpoint, triangle[2]]),
		PackedVector2Array([first_midpoint, second_midpoint, third_midpoint]),
	]:
		for grandchild: PackedVector2Array in _tessellate_planar_triangle(child, depth + 1):
			children.append(grandchild)
	return children


func _ensure_country_flag_uv_bounds() -> void:
	if _country_flag_uv_bounds.size() == _countries.size() and not _countries.is_empty():
		return
	_static_uv_build_count += 1
	_country_flag_uv_bounds.clear()
	_country_flag_uv_reference_longitudes.clear()
	for country_value: Variant in _countries:
		var country: Dictionary = country_value as Dictionary
		var country_id := str(country.get("id", ""))
		var source_polygons: Array = _country_unit_polygons.get(country_id, []) as Array
		if source_polygons.is_empty():
			continue
		var first_source: PackedVector3Array = source_polygons[0] as PackedVector3Array
		if first_source.is_empty():
			continue
		var reference_longitude := _map_unit_to_lon_lat(first_source[0]).x
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for source_index: int in range(source_polygons.size()):
			var source: PackedVector3Array = source_polygons[source_index]
			for point: Vector2 in _unwrapped_planar_ring(source, reference_longitude):
				minimum.x = minf(minimum.x, point.x)
				minimum.y = minf(minimum.y, point.y)
				maximum.x = maxf(maximum.x, point.x)
				maximum.y = maxf(maximum.y, point.y)
			for hole_value: Variant in _holes_for_surface_source(country_id, source_index):
				var hole: PackedVector3Array = hole_value
				for point: Vector2 in _unwrapped_planar_ring(hole, reference_longitude):
					minimum.x = minf(minimum.x, point.x)
					minimum.y = minf(minimum.y, point.y)
					maximum.x = maxf(maximum.x, point.x)
					maximum.y = maxf(maximum.y, point.y)
		if minimum.x != INF and maximum.x != -INF:
			_country_flag_uv_reference_longitudes[country_id] = reference_longitude
			_country_flag_uv_bounds[country_id] = Rect2(minimum, maximum - minimum)


func _planar_to_flag_uv(country_id: String, point: Vector2) -> Vector2:
	var bounds: Rect2 = _country_flag_uv_bounds.get(country_id, Rect2()) as Rect2
	var width := maxf(bounds.size.x, 0.000001)
	var height := maxf(bounds.size.y, 0.000001)
	return Vector2(
		clampf((point.x - bounds.position.x) / width, 0.0, 1.0),
		clampf(1.0 - (point.y - bounds.position.y) / height, 0.0, 1.0)
	)


func _planar_polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].x * polygon[next_index].y
		area -= polygon[next_index].x * polygon[index].y
	return absf(area) * 0.5


func _clip_front_facing_triangle_with_uv(
	triangle: PackedVector3Array,
	triangle_uvs: PackedVector2Array
) -> Dictionary:
	var output_points := PackedVector3Array()
	var output_uvs := PackedVector2Array()
	if triangle.size() < 3 or triangle_uvs.size() != triangle.size():
		return {"points": output_points, "uvs": output_uvs}
	var previous := triangle[triangle.size() - 1]
	var previous_uv := triangle_uvs[triangle_uvs.size() - 1]
	var previous_inside := previous.z >= -MAP_TRIANGLE_DEPTH_EPSILON
	for index: int in range(triangle.size()):
		var current: Vector3 = triangle[index]
		var current_uv: Vector2 = triangle_uvs[index]
		var current_inside := current.z >= -MAP_TRIANGLE_DEPTH_EPSILON
		if current_inside != previous_inside:
			var denominator := previous.z - current.z
			var ratio := 0.5
			if absf(denominator) > 0.000001:
				ratio = clampf(previous.z / denominator, 0.0, 1.0)
			var horizon := previous.lerp(current, ratio)
			horizon.z = 0.0
			output_points.append(horizon)
			output_uvs.append(previous_uv.lerp(current_uv, ratio))
		if current_inside:
			output_points.append(current)
			output_uvs.append(current_uv)
		previous = current
		previous_uv = current_uv
		previous_inside = current_inside
	return {"points": output_points, "uvs": output_uvs}


func _screen_triangle_records(
	points: PackedVector3Array,
	uvs: PackedVector2Array,
	include_uvs: bool = true
) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if points.size() < 3 or (include_uvs and points.size() != uvs.size()):
		return output
	var screen := PackedVector2Array()
	var clean_uvs := PackedVector2Array()
	for index: int in range(points.size()):
		var screen_point := _sphere_screen(points[index])
		if not is_finite(screen_point.x) or not is_finite(screen_point.y):
			return output
		if screen.is_empty() or screen[screen.size() - 1].distance_to(screen_point) > MAP_SCREEN_DUPLICATE_DISTANCE:
			screen.append(screen_point)
			if include_uvs:
				clean_uvs.append(uvs[index])
	if screen.size() > 1 and screen[0].distance_to(screen[screen.size() - 1]) < MAP_SCREEN_DUPLICATE_DISTANCE:
		screen.resize(screen.size() - 1)
		if not clean_uvs.is_empty():
			clean_uvs.resize(clean_uvs.size() - 1)
	if screen.size() < 3:
		return output
	# Sutherland-Hodgman clipping preserves the ordered convex boundary of a
	# source triangle (at most four vertices). A fan is sufficient here and
	# keeps every clipped vertex paired with its interpolated UV.
	for index: int in range(1, screen.size() - 1):
		var triangle_screen := PackedVector2Array([screen[0], screen[index], screen[index + 1]])
		# Use the same non-zero-area acceptance threshold as the draw layer. A
		# clipped child may be sub-pixel at the horizon but is still valid source
		# geometry and must not be discarded as a whole-country visibility loss.
		if _screen_polygon_area(triangle_screen) <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
			continue
		output.append({
			"screen": triangle_screen,
			"uvs": PackedVector2Array([clean_uvs[0], clean_uvs[index], clean_uvs[index + 1]]) if include_uvs else PackedVector2Array(),
			"area": _screen_polygon_area(triangle_screen),
		})
	return output


func _mesh_from_screen_buffers(vertices: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	if vertices.is_empty() or vertices.size() != uvs.size() or vertices.size() % 3 != 0:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mesh_from_screen_triangles(triangles: Array[Dictionary]) -> ArrayMesh:
	if triangles.is_empty():
		return null
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for triangle: Dictionary in triangles:
		var points: PackedVector2Array = triangle.get("screen", PackedVector2Array()) as PackedVector2Array
		var triangle_uvs: PackedVector2Array = triangle.get("uvs", PackedVector2Array()) as PackedVector2Array
		if points.size() != 3 or triangle_uvs.size() != 3:
			continue
		for index: int in range(3):
			vertices.append(Vector3(points[index].x, points[index].y, 0.0))
			uvs.append(triangle_uvs[index])
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _triangulate_planar_polygon(polygon: PackedVector2Array) -> PackedInt32Array:
	# GeoJSON rings are normally explicitly closed (the first point is repeated
	# as the last point).  That repeated coordinate is a boundary marker, not a
	# second vertex.  Passing it to Geometry2D can produce empty or area-
	# conserving but topologically invalid triangles after a ring has been
	# simplified.  Normalize once at the shared triangulation boundary and map
	# the resulting indices back to the caller's source ring.
	if polygon.size() < 3:
		return PackedInt32Array()
	var normalized := PackedVector2Array()
	var source_indices: Array[int] = []
	for source_index: int in range(polygon.size()):
		var point := polygon[source_index]
		if normalized.is_empty() or normalized[normalized.size() - 1].distance_to(point) > 0.000001:
			normalized.append(point)
			source_indices.append(source_index)
	if normalized.size() > 1 and normalized[0].distance_to(normalized[normalized.size() - 1]) <= 0.000001:
		normalized.resize(normalized.size() - 1)
		source_indices.resize(source_indices.size() - 1)
	if normalized.size() < 3:
		return PackedInt32Array()
	var normalized_indices := _triangulate_normalized_planar_polygon(normalized)
	var mapped := PackedInt32Array()
	for normalized_index: int in normalized_indices:
		if normalized_index < 0 or normalized_index >= source_indices.size():
			return PackedInt32Array()
		mapped.append(source_indices[normalized_index])
	return mapped


func _triangulate_normalized_planar_polygon(polygon: PackedVector2Array) -> PackedInt32Array:
	# Geometry2D.triangulate_polygon() can return an area-conserving but
	# topologically invalid result for some very large, highly concave CShapes
	# rings.  A triangle whose centroid is inside the ring is not sufficient:
	# the triangle must retain the complete source-component provenance.  Use a
	# deterministic ear clipper only as a bounded fallback so every emitted
	# triangle is derived from one ring and never bridges a concavity or another
	# component.  The engine triangulator is substantially faster for the normal
	# case; validating its result keeps the expensive fallback off the camera
	# and startup hot paths for the thousands of ordinary source rings.
	if polygon.size() < 3:
		return PackedInt32Array()
	var engine_indices := Geometry2D.triangulate_polygon(polygon)
	# Full ring containment and edge-crossing proof is intentionally an audit
	# operation. Running it for every large CShapes ring on the player's first
	# frame turns Canada's 268 components into an unbounded synchronous stall.
	# Normal rendering still receives the engine's indexed triangulation, then
	# applies the camera-independent long-edge subdivision and preserves the
	# source-component/source-triangle provenance. The independent topology
	# audit enables the slow proof explicitly and reports any bad source ring.
	var requires_topology_validation := map_topology_validation_enabled
	if engine_indices.size() >= 3 and not requires_topology_validation:
		return engine_indices
	if _triangulation_is_valid_for_ring(polygon, engine_indices):
		return engine_indices
	var reversed_polygon := PackedVector2Array()
	for reverse_index: int in range(polygon.size() - 1, -1, -1):
		reversed_polygon.append(polygon[reverse_index])
	var reversed_indices := Geometry2D.triangulate_polygon(reversed_polygon)
	var remapped_reversed := PackedInt32Array()
	for reverse_value: int in reversed_indices:
		remapped_reversed.append(polygon.size() - 1 - reverse_value)
	if _triangulation_is_valid_for_ring(polygon, remapped_reversed):
		return remapped_reversed
	var points := PackedVector2Array()
	var source_indices: Array[int] = []
	for index: int in range(polygon.size()):
		var point := polygon[index]
		if points.is_empty() or points[points.size() - 1].distance_to(point) > 0.000001:
			points.append(point)
			source_indices.append(index)
	if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) <= 0.000001:
		points.resize(points.size() - 1)
		source_indices.resize(source_indices.size() - 1)
	if points.size() < 3:
		return PackedInt32Array()
	var signed_area := _signed_planar_polygon_area(points)
	if absf(signed_area) <= MAP_TRIANGLE_AREA_EPSILON:
		return PackedInt32Array()
	var counter_clockwise := signed_area > 0.0
	var remaining: Array[int] = []
	for point_index: int in range(points.size()):
		remaining.append(point_index)
	var result := PackedInt32Array()
	var guard := 0
	var guard_limit := maxi(points.size() * points.size() * 2, 64)
	while remaining.size() > 3 and guard < guard_limit:
		guard += 1
		var clipped_ear := false
		for position: int in range(remaining.size()):
			var previous_position := (position - 1 + remaining.size()) % remaining.size()
			var next_position := (position + 1) % remaining.size()
			var previous_index: int = remaining[previous_position]
			var current_index: int = remaining[position]
			var next_index: int = remaining[next_position]
			var turn := _planar_cross(
				points[previous_index],
				points[current_index],
				points[next_index]
			)
			if counter_clockwise and turn <= MAP_TRIANGLE_AREA_EPSILON:
				continue
			if not counter_clockwise and turn >= -MAP_TRIANGLE_AREA_EPSILON:
				continue
			if not _planar_diagonal_is_inside(points, remaining, previous_index, next_index):
				continue
			var contains_vertex := false
			for candidate_index: int in remaining:
				if candidate_index == previous_index or candidate_index == current_index or candidate_index == next_index:
					continue
				if _point_in_or_on_planar_triangle(
					points[candidate_index],
					points[previous_index],
					points[current_index],
					points[next_index]
				):
					contains_vertex = true
					break
			if contains_vertex:
				continue
			result.append(source_indices[previous_index])
			result.append(source_indices[current_index])
			result.append(source_indices[next_index])
			remaining.remove_at(position)
			clipped_ear = true
			break
		if clipped_ear:
			continue
		# Collinear source points are harmless, but they can prevent an ear from
		# being found due to floating-point tolerances. Remove only a point that
		# is demonstrably on its two neighbours; never discard a real corner.
		var removed_collinear := false
		for position: int in range(remaining.size()):
			var previous_index: int = remaining[(position - 1 + remaining.size()) % remaining.size()]
			var current_index: int = remaining[position]
			var next_index: int = remaining[(position + 1) % remaining.size()]
			if absf(_planar_cross(points[previous_index], points[current_index], points[next_index])) <= MAP_TRIANGLE_AREA_EPSILON:
				remaining.remove_at(position)
				removed_collinear = true
				break
		if not removed_collinear:
			return PackedInt32Array()
	if remaining.size() != 3:
		return PackedInt32Array()
	var final_triangle := PackedVector2Array([
		points[remaining[0]],
		points[remaining[1]],
		points[remaining[2]],
	])
	if _planar_polygon_area(final_triangle) <= MAP_TRIANGLE_AREA_EPSILON:
		return PackedInt32Array()
	result.append(source_indices[remaining[0]])
	result.append(source_indices[remaining[1]])
	result.append(source_indices[remaining[2]])
	return result


func _triangulation_is_valid_for_ring(polygon: PackedVector2Array, indices: PackedInt32Array) -> bool:
	if polygon.size() < 3 or indices.size() < 3 or indices.size() % 3 != 0:
		return false
	var source_area := _planar_polygon_area(polygon)
	if source_area <= MAP_TRIANGLE_AREA_EPSILON:
		return false
	var ring_edge_bins := _build_planar_ring_edge_bins(polygon)
	var triangulated_area := 0.0
	for index: int in range(0, indices.size(), 3):
		var first_index := int(indices[index])
		var second_index := int(indices[index + 1])
		var third_index := int(indices[index + 2])
		if (
			first_index < 0 or second_index < 0 or third_index < 0
			or first_index >= polygon.size()
			or second_index >= polygon.size()
			or third_index >= polygon.size()
			or first_index == second_index
			or second_index == third_index
			or third_index == first_index
		):
			return false
		var triangle := PackedVector2Array([
			polygon[first_index],
			polygon[second_index],
			polygon[third_index],
		])
		var triangle_area := _planar_polygon_area(triangle)
		if triangle_area <= MAP_TRIANGLE_AREA_EPSILON:
			return false
		var samples := PackedVector2Array([
			triangle[0] * 0.60 + triangle[1] * 0.20 + triangle[2] * 0.20,
			triangle[0] * 0.20 + triangle[1] * 0.60 + triangle[2] * 0.20,
			triangle[0] * 0.20 + triangle[1] * 0.20 + triangle[2] * 0.60,
			(triangle[0] + triangle[1] + triangle[2]) / 3.0,
		])
		for sample: Vector2 in samples:
			if not _point_in_planar_ring(sample, polygon):
				return false
		for edge_index: int in range(3):
			var edge_start := triangle[edge_index]
			var edge_end := triangle[(edge_index + 1) % 3]
			# A diagonal can leave a concave ring and re-enter it without a
			# strict segment intersection being reported when it touches a source
			# vertex or follows a nearly collinear boundary run.  Test interior
			# points on every emitted edge as well as the triangle's barycentric
			# samples.  This rejects the non-adjacent boundary bridge that later
			# tessellation would otherwise multiply into a visually convincing but
			# invalid wedge.
			for edge_sample_index: int in range(1, MAP_TRIANGULATION_EDGE_SAMPLE_COUNT):
				var edge_sample := edge_start.lerp(
					edge_end,
					float(edge_sample_index) / float(MAP_TRIANGULATION_EDGE_SAMPLE_COUNT)
				)
				if not _point_in_planar_ring(edge_sample, polygon):
					return false
			if _triangle_edge_crosses_ring(edge_start, edge_end, polygon, ring_edge_bins):
				return false
		triangulated_area += triangle_area
	var area_tolerance := maxf(0.00001, source_area * 0.002)
	return absf(triangulated_area - source_area) <= area_tolerance


func _triangulation_has_large_edge(polygon: PackedVector2Array, indices: PackedInt32Array) -> bool:
	if polygon.size() < 3 or indices.size() < 3 or indices.size() % 3 != 0:
		return true
	for index: int in range(0, indices.size(), 3):
		var first_index := int(indices[index])
		var second_index := int(indices[index + 1])
		var third_index := int(indices[index + 2])
		if (
			first_index < 0 or second_index < 0 or third_index < 0
			or first_index >= polygon.size()
			or second_index >= polygon.size()
			or third_index >= polygon.size()
		):
			return true
		for edge_index: int in range(3):
			var start := polygon[[first_index, second_index, third_index][edge_index]]
			var end := polygon[[first_index, second_index, third_index][(edge_index + 1) % 3]]
			if start.distance_to(end) > MAP_MAX_SOURCE_TRIANGLE_EDGE_DEGREES:
				return true
	return false


func _triangulation_has_boundary_crossing(polygon: PackedVector2Array, indices: PackedInt32Array) -> bool:
	if polygon.size() < 3 or indices.size() < 3 or indices.size() % 3 != 0:
		return true
	var ring_edge_bins := _build_planar_ring_edge_bins(polygon)
	for index: int in range(0, indices.size(), 3):
		var first_index := int(indices[index])
		var second_index := int(indices[index + 1])
		var third_index := int(indices[index + 2])
		if (
			first_index < 0 or second_index < 0 or third_index < 0
			or first_index >= polygon.size()
			or second_index >= polygon.size()
			or third_index >= polygon.size()
		):
			return true
		var triangle_indices: Array[int] = [first_index, second_index, third_index]
		for edge_index: int in range(3):
			var start := polygon[triangle_indices[edge_index]]
			var end := polygon[triangle_indices[(edge_index + 1) % 3]]
			if _triangle_edge_crosses_ring(start, end, polygon, ring_edge_bins):
				return true
	return false


func _build_planar_ring_edge_bins(ring: PackedVector2Array) -> Dictionary:
	const CELL_SIZE := 5.0
	var bins: Dictionary = {}
	for edge_index: int in range(ring.size()):
		var start := ring[edge_index]
		var end := ring[(edge_index + 1) % ring.size()]
		var minimum := Vector2(minf(start.x, end.x), minf(start.y, end.y))
		var maximum := Vector2(maxf(start.x, end.x), maxf(start.y, end.y))
		var min_cell := Vector2i(floori(minimum.x / CELL_SIZE), floori(minimum.y / CELL_SIZE))
		var max_cell := Vector2i(floori(maximum.x / CELL_SIZE), floori(maximum.y / CELL_SIZE))
		for cell_x: int in range(min_cell.x - 1, max_cell.x + 2):
			for cell_y: int in range(min_cell.y - 1, max_cell.y + 2):
				var key := "%d:%d" % [cell_x, cell_y]
				var edge_list: Array = bins.get(key, []) as Array
				edge_list.append(edge_index)
				bins[key] = edge_list
	return bins


func _triangle_edge_crosses_ring(
	start: Vector2,
	end: Vector2,
	ring: PackedVector2Array,
	bins: Dictionary
) -> bool:
	const CELL_SIZE := 5.0
	var minimum := Vector2(minf(start.x, end.x), minf(start.y, end.y))
	var maximum := Vector2(maxf(start.x, end.x), maxf(start.y, end.y))
	var min_cell := Vector2i(floori(minimum.x / CELL_SIZE), floori(minimum.y / CELL_SIZE))
	var max_cell := Vector2i(floori(maximum.x / CELL_SIZE), floori(maximum.y / CELL_SIZE))
	var seen_edges: Dictionary = {}
	for cell_x: int in range(min_cell.x - 1, max_cell.x + 2):
		for cell_y: int in range(min_cell.y - 1, max_cell.y + 2):
			for edge_value: Variant in (bins.get("%d:%d" % [cell_x, cell_y], []) as Array):
				var ring_edge := int(edge_value)
				if seen_edges.has(ring_edge):
					continue
				seen_edges[ring_edge] = true
				var ring_start := ring[ring_edge]
				var ring_end := ring[(ring_edge + 1) % ring.size()]
				if _planar_segments_cross_interior_strict(start, end, ring_start, ring_end):
					return true
	return false


func _planar_segments_cross_interior_strict(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := (b - a).cross(c - a)
	var ab_d := (b - a).cross(d - a)
	var cd_a := (d - c).cross(a - c)
	var cd_b := (d - c).cross(b - c)
	const EPSILON := 0.0000001
	return (
		((ab_c > EPSILON and ab_d < -EPSILON) or (ab_c < -EPSILON and ab_d > EPSILON))
		and ((cd_a > EPSILON and cd_b < -EPSILON) or (cd_a < -EPSILON and cd_b > EPSILON))
	)


func _triangulation_indices_have_valid_shape(polygon: PackedVector2Array, indices: PackedInt32Array) -> bool:
	if polygon.size() < 3 or indices.size() < 3 or indices.size() % 3 != 0:
		return false
	for index: int in range(0, indices.size(), 3):
		var first_index := int(indices[index])
		var second_index := int(indices[index + 1])
		var third_index := int(indices[index + 2])
		if (
			first_index < 0 or second_index < 0 or third_index < 0
			or first_index >= polygon.size()
			or second_index >= polygon.size()
			or third_index >= polygon.size()
			or first_index == second_index
			or second_index == third_index
			or third_index == first_index
		):
			return false
	return true


func _signed_planar_polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].cross(polygon[next_index])
	return area * 0.5


func _planar_cross(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b - a).cross(c - b)


func _point_in_or_on_planar_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := _planar_cross(a, b, point)
	var second := _planar_cross(b, c, point)
	var third := _planar_cross(c, a, point)
	var has_negative := first < -MAP_TRIANGLE_AREA_EPSILON or second < -MAP_TRIANGLE_AREA_EPSILON or third < -MAP_TRIANGLE_AREA_EPSILON
	var has_positive := first > MAP_TRIANGLE_AREA_EPSILON or second > MAP_TRIANGLE_AREA_EPSILON or third > MAP_TRIANGLE_AREA_EPSILON
	return not (has_negative and has_positive)


func _planar_diagonal_is_inside(
	points: PackedVector2Array,
	remaining: Array[int],
	start_index: int,
	end_index: int
) -> bool:
	var start_position := remaining.find(start_index)
	var end_position := remaining.find(end_index)
	if start_position < 0 or end_position < 0:
		return false
	var start := points[start_index]
	var end := points[end_index]
	for edge_position: int in range(remaining.size()):
		var edge_start_index: int = remaining[edge_position]
		var edge_end_index: int = remaining[(edge_position + 1) % remaining.size()]
		if (
			edge_start_index == start_index or edge_start_index == end_index
			or edge_end_index == start_index or edge_end_index == end_index
		):
			continue
		if _planar_segments_intersect(start, end, points[edge_start_index], points[edge_end_index]):
			return false
	var midpoint := start.lerp(end, 0.5)
	var ring := PackedVector2Array()
	for index: int in remaining:
		ring.append(points[index])
	return _point_in_planar_ring(midpoint, ring)


func _planar_segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var first := _planar_cross(a, b, c)
	var second := _planar_cross(a, b, d)
	var third := _planar_cross(c, d, a)
	var fourth := _planar_cross(c, d, b)
	var epsilon := MAP_TRIANGLE_AREA_EPSILON
	if absf(first) <= epsilon and _point_on_planar_segment(c, a, b):
		return true
	if absf(second) <= epsilon and _point_on_planar_segment(d, a, b):
		return true
	if absf(third) <= epsilon and _point_on_planar_segment(a, c, d):
		return true
	if absf(fourth) <= epsilon and _point_on_planar_segment(b, c, d):
		return true
	return (first > 0.0) != (second > 0.0) and (third > 0.0) != (fourth > 0.0)


func _point_on_planar_segment(point: Vector2, start: Vector2, end: Vector2) -> bool:
	return (
		absf(_planar_cross(start, end, point)) <= MAP_TRIANGLE_AREA_EPSILON
		and
		point.x >= minf(start.x, end.x) - 0.000001
		and point.x <= maxf(start.x, end.x) + 0.000001
		and point.y >= minf(start.y, end.y) - 0.000001
		and point.y <= maxf(start.y, end.y) + 0.000001
	)


func _point_in_planar_ring(point: Vector2, ring: PackedVector2Array) -> bool:
	if ring.size() < 3:
		return false
	var inside := false
	for index: int in range(ring.size()):
		var start := ring[index]
		var end := ring[(index + 1) % ring.size()]
		if _point_on_planar_segment(point, start, end):
			return true
		if (start.y > point.y) == (end.y > point.y):
			continue
		var denominator := end.y - start.y
		if absf(denominator) <= 0.0000001:
			continue
		var intersection_x := start.x + (point.y - start.y) * (end.x - start.x) / denominator
		if intersection_x >= point.x:
			inside = not inside
	return inside


func _polygon_is_entirely_inside_ring(
	polygon: PackedVector2Array,
	ring: PackedVector2Array
) -> bool:
	if polygon.size() < 3 or ring.size() < 3:
		return false
	for point: Vector2 in polygon:
		if not _point_in_planar_ring(point, ring):
			return false
	return true


func _unwrapped_planar_ring(source: PackedVector3Array, reference_longitude: float = 0.0) -> PackedVector2Array:
	var planar := PackedVector2Array()
	if source.is_empty():
		return planar
	var previous_longitude := 0.0
	for index: int in range(source.size()):
		var lon_lat := _map_unit_to_lon_lat(source[index])
		var longitude := lon_lat.x
		if index == 0:
			previous_longitude = longitude
		else:
			while longitude - previous_longitude > 180.0:
				longitude -= 360.0
			while longitude - previous_longitude < -180.0:
				longitude += 360.0
			previous_longitude = longitude
		if index == 0 and absf(longitude - reference_longitude) > 180.0:
			while longitude - reference_longitude > 180.0:
				longitude -= 360.0
			while longitude - reference_longitude < -180.0:
				longitude += 360.0
			previous_longitude = longitude
		planar.append(Vector2(longitude, lon_lat.y))
	return planar


func _holes_for_surface_source(country_id: String, source_index: int) -> Array:
	var all_holes_value: Variant = get("_country_unit_holes")
	if not all_holes_value is Dictionary:
		return []
	var all_holes := all_holes_value as Dictionary
	var parts: Array = all_holes.get(country_id, []) as Array
	if source_index < 0 or source_index >= parts.size():
		return []
	var holes_value: Variant = parts[source_index]
	return holes_value as Array if holes_value is Array else []


func _append_interactive_clip_edge(
	output: PackedVector3Array,
	previous: Vector3,
	current: Vector3
) -> void:
	var previous_inside := previous.z >= -MAP_TRIANGLE_DEPTH_EPSILON
	var current_inside := current.z >= -MAP_TRIANGLE_DEPTH_EPSILON
	if current_inside != previous_inside:
		var denominator := previous.z - current.z
		var ratio := 0.5
		if absf(denominator) > 0.000001:
			ratio = clampf(previous.z / denominator, 0.0, 1.0)
		var horizon := previous.lerp(current, ratio)
		horizon.z = 0.0
		output.append(horizon)
	if current_inside:
		output.append(current)


func _interactive_clipped_screen_triangles(
	first: Vector3,
	second: Vector3,
	third: Vector3
) -> PackedVector2Array:
	# The interaction path does not need UVs or diagnostic Dictionaries.  It
	# still clips the authoritative source triangle, so every emitted child is
	# from one source triangle and can never connect separate components.
	_interactive_clip_temp_array_count += 1
	_interactive_clip_points_scratch.resize(0)
	_interactive_clip_screen_scratch.resize(0)
	_interactive_clip_output_scratch.resize(0)
	_append_interactive_clip_edge(_interactive_clip_points_scratch, third, first)
	_append_interactive_clip_edge(_interactive_clip_points_scratch, first, second)
	_append_interactive_clip_edge(_interactive_clip_points_scratch, second, third)
	if _interactive_clip_points_scratch.size() < 3:
		return _interactive_clip_output_scratch
	var screen_center := _hemisphere_center
	var screen_radius := _hemisphere_radius
	for point: Vector3 in _interactive_clip_points_scratch:
		var screen_point := screen_center + Vector2(point.x, -point.y) * screen_radius
		if not is_finite(screen_point.x) or not is_finite(screen_point.y):
			return _interactive_clip_output_scratch
		_interactive_clip_screen_scratch.append(screen_point)
	for index: int in range(1, _interactive_clip_screen_scratch.size() - 1):
		var area := absf(
			_interactive_clip_screen_scratch[0].x * (_interactive_clip_screen_scratch[index].y - _interactive_clip_screen_scratch[index + 1].y)
			+ _interactive_clip_screen_scratch[index].x * (_interactive_clip_screen_scratch[index + 1].y - _interactive_clip_screen_scratch[0].y)
			+ _interactive_clip_screen_scratch[index + 1].x * (_interactive_clip_screen_scratch[0].y - _interactive_clip_screen_scratch[index].y)
		) * 0.5
		if area <= 0.0:
			continue
		_interactive_clip_output_scratch.append(_interactive_clip_screen_scratch[0])
		_interactive_clip_output_scratch.append(_interactive_clip_screen_scratch[index])
		_interactive_clip_output_scratch.append(_interactive_clip_screen_scratch[index + 1])
	return _interactive_clip_output_scratch


func _clip_front_facing_triangle(triangle: PackedVector3Array, basis: Basis) -> PackedVector3Array:
	var output := PackedVector3Array()
	if triangle.size() < 3:
		return output
	var previous := basis * triangle[triangle.size() - 1]
	var previous_inside := previous.z >= 0.0
	for index: int in range(triangle.size()):
		var current := basis * triangle[index]
		var current_inside := current.z >= 0.0
		if current_inside != previous_inside:
			var denominator := previous.z - current.z
			var ratio := 0.5
			if absf(denominator) > 0.000001:
				ratio = clampf(previous.z / denominator, 0.0, 1.0)
			var horizon := previous.lerp(current, ratio)
			horizon.z = 0.0
			output.append(horizon)
		if current_inside:
			output.append(current)
		previous = current
		previous_inside = current_inside
	return output


func _screen_polygon_from_unit_points(points: PackedVector3Array) -> PackedVector2Array:
	var output := PackedVector2Array()
	for point: Vector3 in points:
		var screen_point := _sphere_screen(point)
		if not is_finite(screen_point.x) or not is_finite(screen_point.y):
			return PackedVector2Array()
		if output.is_empty() or output[output.size() - 1].distance_to(screen_point) > MAP_SCREEN_DUPLICATE_DISTANCE:
			output.append(screen_point)
	if output.size() > 1 and output[0].distance_to(output[output.size() - 1]) < MAP_SCREEN_DUPLICATE_DISTANCE:
		output.resize(output.size() - 1)
	if output.size() < 3 or _screen_polygon_area(output) <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
		return PackedVector2Array()
	if Geometry2D.triangulate_polygon(output).size() < 3:
		return PackedVector2Array()
	return output


func _project_closed_unit_boundary_fast(source: PackedVector3Array, basis: Basis) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	if source.size() < 2:
		return output
	for index: int in range(source.size()):
		var previous: Vector3 = basis * source[index]
		var current: Vector3 = basis * source[(index + 1) % source.size()]
		var segment := PackedVector2Array()
		var previous_visible := previous.z >= 0.0
		var current_visible := current.z >= 0.0
		if previous_visible:
			segment.append(_sphere_screen(previous))
		if previous_visible != current_visible:
			var denominator: float = previous.z - current.z
			var ratio: float = 0.5
			if absf(denominator) > 0.000001:
				ratio = clampf(previous.z / denominator, 0.0, 1.0)
			var horizon := previous.lerp(current, ratio)
			horizon.z = 0.0
			segment.append(_sphere_screen(horizon))
		if current_visible:
			segment.append(_sphere_screen(current))
		if segment.size() >= 2:
			output.append(segment)
	return output


func _project_closed_unit_boundary(source: PackedVector3Array, basis: Basis) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	if source.size() < 2:
		return output
	for index: int in range(source.size()):
		var edge := PackedVector3Array()
		edge.append(source[index])
		edge.append(source[(index + 1) % source.size()])
		for segment: PackedVector2Array in _project_unit_line(edge, basis):
			if segment.size() >= 2:
				output.append(segment)
	return output


func _source_screen_candidates(source: PackedVector3Array, basis: Basis) -> PackedVector2Array:
	var output := PackedVector2Array()
	if source.size() < 2:
		return output
	for index: int in range(source.size()):
		var previous := basis * source[index]
		var current := basis * source[(index + 1) % source.size()]
		if previous.z >= 0.0:
			output.append(_sphere_screen(previous))
		if (previous.z >= 0.0) != (current.z >= 0.0):
			var denominator := previous.z - current.z
			var ratio := 0.5
			if absf(denominator) > 0.000001:
				ratio = clampf(previous.z / denominator, 0.0, 1.0)
			var horizon := previous.lerp(current, ratio)
			horizon.z = 0.0
			output.append(_sphere_screen(horizon))
	return output


func _source_has_positive_front_geometry(source: PackedVector3Array, basis: Basis) -> bool:
	if source.size() < 2:
		return false
	for index: int in range(source.size()):
		var previous := basis * source[index]
		var current := basis * source[(index + 1) % source.size()]
		if previous.z > 0.0001 or current.z > 0.0001:
			return true
	return false


func _source_front_depth(source: PackedVector3Array, basis: Basis) -> float:
	var maximum_depth := 0.0
	for point: Vector3 in source:
		maximum_depth = maxf(maximum_depth, (basis * point).z)
	return maximum_depth


func _surface_buffer_has_drawable_projection(buffer: Dictionary, basis: Basis) -> bool:
	var points: PackedVector3Array = buffer.get("points", PackedVector3Array()) as PackedVector3Array
	var centers: PackedVector3Array = buffer.get("visibility_centers", PackedVector3Array()) as PackedVector3Array
	var margins: PackedFloat32Array = buffer.get("visibility_margins", PackedFloat32Array()) as PackedFloat32Array
	if points.size() < 3 or centers.is_empty():
		return false
	var camera_normal := Vector3(basis.x.z, basis.y.z, basis.z.z)
	for triangle_offset: int in range(0, points.size(), 3):
		var triangle_index := triangle_offset / 3
		if triangle_offset + 2 >= points.size() or triangle_index >= centers.size():
			break
		var center_depth := camera_normal.dot(centers[triangle_index])
		var angular_margin := margins[triangle_index] if triangle_index < margins.size() else 2.0
		if center_depth + angular_margin <= MAP_TRIANGLE_DEPTH_EPSILON:
			continue
		var first_point := basis * points[triangle_offset]
		var second_point := basis * points[triangle_offset + 1]
		var third_point := basis * points[triangle_offset + 2]
		var transformed := PackedVector3Array([first_point, second_point, third_point])
		var fully_front := center_depth - angular_margin >= -MAP_TRIANGLE_DEPTH_EPSILON
		if fully_front:
			var screen_triangle := PackedVector2Array([
				_sphere_screen(first_point),
				_sphere_screen(second_point),
				_sphere_screen(third_point),
			])
			var area := _screen_polygon_area(screen_triangle)
			if area > 0.0:
				return true
			continue
		var clipped := _clip_front_facing_triangle(transformed, Basis.IDENTITY)
		var candidate_area := _screen_area_for_unit_points(clipped)
		if candidate_area <= 0.0:
			continue
		if candidate_area <= MAP_SCREEN_TRIANGLE_AREA_EPSILON:
			return true
		if not _screen_triangle_records(clipped, PackedVector2Array(), false).is_empty():
			return true
	return false


func _bounds_for_points(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _packed_vector2_array_to_arrays(points: PackedVector2Array) -> Array:
	var output: Array = []
	for point: Vector2 in points:
		output.append([point.x, point.y])
	return output


func _screen_triangle_topology_diagnostic(
	triangle: PackedVector2Array,
	source_component_bounds: Rect2,
	minimum_surface_fallback: bool = false,
	source_triangle_planar: PackedVector2Array = PackedVector2Array(),
	basis: Basis = Basis.IDENTITY
) -> Dictionary:
	var finite := triangle.size() == 3
	for point: Vector2 in triangle:
		finite = finite and is_finite(point.x) and is_finite(point.y)
	var edge_lengths := PackedFloat32Array()
	if triangle.size() == 3:
		edge_lengths.append(triangle[0].distance_to(triangle[1]))
		edge_lengths.append(triangle[1].distance_to(triangle[2]))
		edge_lengths.append(triangle[2].distance_to(triangle[0]))
	var area := _screen_polygon_area(triangle) if finite else 0.0
	var screen_bounds := _bounds_for_points(triangle) if finite else Rect2()
	var source_triangle_screen_bounds := _source_planar_triangle_screen_bounds(source_triangle_planar, basis)
	var suspicious := false
	if finite and area > MAP_PROJECTED_AREA_EPSILON and source_component_bounds.size.x > 0.0 and source_component_bounds.size.y > 0.0:
		var span_ratio := maxf(
			screen_bounds.size.x / maxf(source_component_bounds.size.x, 1.0),
			screen_bounds.size.y / maxf(source_component_bounds.size.y, 1.0)
		)
		# The triangle is allowed to touch the component boundary because
		# clipping can interpolate a horizon vertex.  It may not escape the
		# component bounds or be wildly larger than the component it claims.
		if minimum_surface_fallback:
			var marker_center := (screen_bounds.position + screen_bounds.end) * 0.5
			suspicious = not source_component_bounds.grow(MAP_MINIMUM_SURFACE_MARKER_RADIUS + 2.0).has_point(marker_center)
		else:
			suspicious = (
				not source_component_bounds.grow(4.0).encloses(screen_bounds)
			or span_ratio > 1.75
			)
	if finite and area > MAP_PROJECTED_AREA_EPSILON and source_triangle_screen_bounds.size.x > 0.0 and source_triangle_screen_bounds.size.y > 0.0:
		var local_span_ratio := maxf(
			screen_bounds.size.x / maxf(source_triangle_screen_bounds.size.x, 1.0),
			screen_bounds.size.y / maxf(source_triangle_screen_bounds.size.y, 1.0)
		)
		# This is intentionally diagnostic-only.  A clipping child must stay
		# inside the projection of the exact source triangle that produced it;
		# comparing only with the whole country previously hid a bad local index
		# or cross-part bridge inside a very large component.
		if not source_triangle_screen_bounds.grow(4.0).encloses(screen_bounds) or local_span_ratio > 1.75:
			suspicious = true
	return {
		"finite": finite,
		"edge_lengths": Array(edge_lengths),
		"screen_bounds": [screen_bounds.position.x, screen_bounds.position.y, screen_bounds.size.x, screen_bounds.size.y],
		"source_component_bounds": [
			source_component_bounds.position.x,
			source_component_bounds.position.y,
			source_component_bounds.size.x,
			source_component_bounds.size.y,
		],
		"source_triangle_screen_bounds": [
			source_triangle_screen_bounds.position.x,
			source_triangle_screen_bounds.position.y,
			source_triangle_screen_bounds.size.x,
			source_triangle_screen_bounds.size.y,
		],
		"source_triangle_planar": _packed_vector2_array_to_arrays(source_triangle_planar),
		"screen_area": area,
		"suspicious": suspicious,
	}


func _source_planar_triangle_screen_bounds(
	source_triangle_planar: PackedVector2Array,
	basis: Basis
) -> Rect2:
	if source_triangle_planar.size() != 3:
		return Rect2()
	var source_points := PackedVector3Array()
	for point: Vector2 in source_triangle_planar:
		source_points.append(basis * _lon_lat_to_unit(point))
	var visible_points := _clip_front_facing_triangle(source_points, Basis.IDENTITY)
	if visible_points.size() < 3:
		return Rect2()
	var screen_points := PackedVector2Array()
	for point: Vector3 in visible_points:
		var screen_point := _sphere_screen(point)
		if not is_finite(screen_point.x) or not is_finite(screen_point.y):
			return Rect2()
		screen_points.append(screen_point)
	return _bounds_for_points(screen_points)


func _minimum_surface_marker(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(points.size())
	var radius := MAP_MINIMUM_SURFACE_MARKER_RADIUS
	return PackedVector2Array([
		center + Vector2(-radius, radius * 0.72),
		center + Vector2(radius, radius * 0.72),
		center + Vector2(0.0, -radius),
	])


func _minimum_surface_marker_uvs(uvs: PackedVector2Array) -> PackedVector2Array:
	if uvs.is_empty():
		return PackedVector2Array()
	var center := Vector2.ZERO
	for uv: Vector2 in uvs:
		center += uv
	center /= float(uvs.size())
	return PackedVector2Array([center, center, center])


func _screen_triangle_area_at(points: PackedVector2Array, point_index: int) -> float:
	if point_index < 0 or point_index + 2 >= points.size():
		return 0.0
	var first := points[point_index]
	var second := points[point_index + 1]
	var third := points[point_index + 2]
	return absf(
		first.x * (second.y - third.y)
		+ second.x * (third.y - first.y)
		+ third.x * (first.y - second.y)
	) * 0.5


func _is_valid_screen_triangle_at(points: PackedVector2Array, point_index: int) -> bool:
	if point_index < 0 or point_index + 2 >= points.size():
		return false
	for offset: int in range(3):
		var point := points[point_index + offset]
		if not is_finite(point.x) or not is_finite(point.y):
			return false
	return _screen_triangle_area_at(points, point_index) > MAP_SCREEN_TRIANGLE_AREA_EPSILON


func _point_in_screen_triangle_at(position: Vector2, points: PackedVector2Array, point_index: int) -> bool:
	if point_index < 0 or point_index + 2 >= points.size():
		return false
	var first := points[point_index]
	var second := points[point_index + 1]
	var third := points[point_index + 2]
	var first_cross := (second.x - first.x) * (position.y - first.y) - (second.y - first.y) * (position.x - first.x)
	var second_cross := (third.x - second.x) * (position.y - second.y) - (third.y - second.y) * (position.x - second.x)
	var third_cross := (first.x - third.x) * (position.y - third.y) - (first.y - third.y) * (position.x - third.x)
	var has_negative := first_cross < 0.0 or second_cross < 0.0 or third_cross < 0.0
	var has_positive := first_cross > 0.0 or second_cross > 0.0 or third_cross > 0.0
	return not (has_negative and has_positive)


func _is_valid_screen_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	for point: Vector2 in polygon:
		if not is_finite(point.x) or not is_finite(point.y):
			return false
	return true


func _screen_polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index: int in range(polygon.size()):
		var next_index := (index + 1) % polygon.size()
		area += polygon[index].x * polygon[next_index].y
		area -= polygon[next_index].x * polygon[index].y
	return absf(area) * 0.5


func _screen_area_for_unit_points(points: PackedVector3Array) -> float:
	var screen := PackedVector2Array()
	for point: Vector3 in points:
		var screen_point := _sphere_screen(point)
		if not is_finite(screen_point.x) or not is_finite(screen_point.y):
			return 0.0
		screen.append(screen_point)
	return _screen_polygon_area(screen) if screen.size() >= 3 else 0.0


func _map_unit_to_lon_lat(point: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(point.x, point.z)), rad_to_deg(asin(clampf(point.y, -1.0, 1.0))))


func _make_map_render_stage_record(
	country_id: String,
	geometry_parts: int,
	projected_parts: int,
	visible_parts: int,
	front_facing_geometry: bool,
	invalid_projected_parts: int,
	zero_size_projected_bounds: bool,
	tiny_surface_fallback_parts: int,
	source_triangles: int,
	visible_source_triangles: int,
	clipped_visible_triangles: int,
	submitted_triangles: int,
	missing_visible_triangles: int,
	source_planar_area: float,
	triangulated_planar_area: float,
	visible_projected_area: float,
	expected_visible_projected_area: float = 0.0
) -> Dictionary:
	var regions: Array = []
	var history_territories_value: Variant = get("_history_territories_by_entity")
	if history_territories_value is Dictionary:
		regions = (history_territories_value as Dictionary).get(country_id, []) as Array
	return {
		"id": country_id,
		"expected": true,
		"regions": regions.size(),
		"geometry_parts": geometry_parts,
		"projected_parts": projected_parts,
		"visible_parts": visible_parts,
		"should_be_visible": visible_parts > 0 or front_facing_geometry,
		"front_facing_geometry": front_facing_geometry,
		"invalid_projected_parts": invalid_projected_parts,
		"zero_size_projected_bounds": zero_size_projected_bounds,
		"tiny_surface_fallback_parts": tiny_surface_fallback_parts,
		"source_triangles": source_triangles,
		"visible_source_triangles": visible_source_triangles,
		"clipped_visible_triangles": clipped_visible_triangles,
		# Submission/draw counts are populated by the active render layer.  The
		# projected triangle count above is an expectation, not proof that the
		# CanvasItem actually accepted the geometry.
		"submitted_triangles": 0,
		"drawn_triangles": 0,
		"missing_visible_triangles": missing_visible_triangles,
		"source_planar_area": source_planar_area,
		"triangulated_planar_area": triangulated_planar_area,
		"triangulation_area_ratio": triangulated_planar_area / source_planar_area if source_planar_area > MAP_TRIANGLE_AREA_EPSILON else 1.0,
		"visible_projected_area": visible_projected_area,
		"expected_visible_projected_area": expected_visible_projected_area,
		"submitted_projected_area": 0.0,
		"drawn_projected_area": 0.0,
		"visible_surface_coverage_ratio": visible_projected_area / expected_visible_projected_area if expected_visible_projected_area > MAP_PROJECTED_AREA_EPSILON else 1.0,
	}


func _begin_map_render_audit() -> void:
	_map_render_submitted_parts.clear()
	_map_render_drawn_parts.clear()
	_map_render_submitted_triangles.clear()
	_map_render_drawn_triangles.clear()
	_map_render_submitted_areas.clear()
	_map_render_drawn_areas.clear()
	_map_render_rejections.clear()
	_map_render_fallbacks.clear()
	_map_flag_resource_lookup_calls = 0
	_map_flag_texture_cache_hits = 0
	_map_flag_texture_cache_misses = 0
	_map_flag_draw_calls = 0
	_map_render_profile["flag_resource_lookup_calls"] = 0
	_map_render_profile["flag_texture_cache_hits"] = 0
	_map_render_profile["flag_texture_cache_misses"] = 0
	_map_render_profile["flag_draw_calls"] = 0
	for profile_key: String in [
		"flags_draw_usec",
		"outlines_draw_usec",
		"labels_draw_usec",
		"flag_resource_lookup_usec",
		"cache_synchronization_usec",
	]:
		_map_render_profile[profile_key] = 0


func _exit_tree() -> void:
	if _map_player_audit_path.is_empty():
		return
	_write_map_player_audit()


func _write_map_player_audit() -> void:
	var output_path := _map_player_audit_path
	if not output_path.begins_with("res://") and not output_path.begins_with("user://"):
		output_path = ProjectSettings.globalize_path(output_path)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Map player audit could not open output path: " + output_path)
		return
	file.store_string(JSON.stringify({
		"sample_count": _map_player_audit_samples.size(),
		"samples": _map_player_audit_samples,
	}))


func _record_map_render_submission(country_id: String, triangle_count: int = 1, area: float = 0.0) -> void:
	_map_render_submitted_parts[country_id] = int(_map_render_submitted_parts.get(country_id, 0)) + 1
	_map_render_submitted_triangles[country_id] = int(_map_render_submitted_triangles.get(country_id, 0)) + triangle_count
	_map_render_submitted_areas[country_id] = float(_map_render_submitted_areas.get(country_id, 0.0)) + area


func _record_map_render_draw(country_id: String, triangle_count: int = 1, area: float = 0.0) -> void:
	_map_render_drawn_parts[country_id] = int(_map_render_drawn_parts.get(country_id, 0)) + 1
	_map_render_drawn_triangles[country_id] = int(_map_render_drawn_triangles.get(country_id, 0)) + triangle_count
	_map_render_drawn_areas[country_id] = float(_map_render_drawn_areas.get(country_id, 0.0)) + area


func _record_map_render_frame_profile(frame_usec: int) -> void:
	_map_render_profile["frame_usec"] = frame_usec
	_map_render_profile["flag_resource_lookup_calls"] = _map_flag_resource_lookup_calls
	_map_render_profile["flag_texture_cache_hits"] = _map_flag_texture_cache_hits
	_map_render_profile["flag_texture_cache_misses"] = _map_flag_texture_cache_misses
	_map_render_profile["flag_draw_calls"] = _map_flag_draw_calls
	_map_render_profile["invalid_flag_draw_count"] = _flag_draw_validation_failures.size()
	_map_render_profile["invalid_flag_draw_samples"] = _flag_draw_validation_failures.duplicate(true)
	if not _map_player_audit_path.is_empty():
		_map_player_audit_frame_index += 1
		if _map_player_audit_frame_index % MAP_PLAYER_AUDIT_SAMPLE_STRIDE != 0:
			return
		_map_player_audit_samples.append({
			"kind": "frame",
			"timestamp_usec": Time.get_ticks_usec(),
			"frame_usec": frame_usec,
			"dragging": dragging,
			"input_kind": _map_player_audit_input_kind,
			"processing": is_processing(),
			"yaw": yaw,
			"tilt": tilt,
			"world_zoom": world_zoom,
			"cache_lod": _last_map_cache_lod,
			"camera_projection_usec": int(_map_render_profile.get("camera_projection_usec", 0)),
			"flag_cache_build_usec": int(_map_render_profile.get("flag_cache_build_usec", 0)),
			"flags_draw_usec": int(_map_render_profile.get("flags_draw_usec", 0)),
			"outlines_draw_usec": int(_map_render_profile.get("outlines_draw_usec", 0)),
			"labels_draw_usec": int(_map_render_profile.get("labels_draw_usec", 0)),
			"physical_land_projection_usec": int(_map_render_profile.get("physical_land_projection_usec", 0)),
			"invalid_screen_triangles": int(_map_render_profile.get("invalid_screen_triangles", 0)),
			"static_data_build_count": int(_map_render_profile.get("static_data_build_count", 0)),
			"static_uv_build_count": int(_map_render_profile.get("static_uv_build_count", 0)),
			"static_provenance_build_count": int(_map_render_profile.get("static_provenance_build_count", 0)),
			"static_triangulation_build_count": int(_map_render_profile.get("static_triangulation_build_count", 0)),
			"interactive_source_triangles_processed": int(_map_render_profile.get("interactive_source_triangles_processed", 0)),
			"interactive_front_triangles": int(_map_render_profile.get("interactive_front_triangles", 0)),
			"interactive_behind_triangles": int(_map_render_profile.get("interactive_behind_triangles", 0)),
			"interactive_horizon_clipped_triangles": int(_map_render_profile.get("interactive_horizon_clipped_triangles", 0)),
			"interactive_projected_vertices": int(_map_render_profile.get("interactive_projected_vertices", 0)),
			"interactive_screen_triangles": int(_map_render_profile.get("interactive_screen_triangles", 0)),
			"interactive_clip_temp_array_count": int(_map_render_profile.get("interactive_clip_temp_array_count", 0)),
			"interactive_provenance_string_lookups": int(_map_render_profile.get("interactive_provenance_string_lookups", 0)),
		})


func _record_map_render_profile_stage(name: String, elapsed_usec: int) -> void:
	_map_render_profile[name] = elapsed_usec


func _record_map_render_rejection(country_id: String, reason: String) -> void:
	var reasons: Dictionary = _map_render_rejections.get(country_id, {}) as Dictionary
	reasons[reason] = int(reasons.get(reason, 0)) + 1
	_map_render_rejections[country_id] = reasons


func _record_map_render_fallback(country_id: String, reason: String) -> void:
	var reasons: Dictionary = _map_render_fallbacks.get(country_id, {}) as Dictionary
	reasons[reason] = int(reasons.get(reason, 0)) + 1
	_map_render_fallbacks[country_id] = reasons


func _interactive_source_component_id(entity_id: String, component_index: int) -> String:
	if component_index < 0:
		return ""
	return "%s:%d" % [entity_id, component_index]


func map_render_geometry_provenance_set() -> Array[String]:
	var result: Array[String] = []
	var entity_ids: Array[String] = []
	var compact_interactive_records := _last_map_cache_lod == "interactive"
	var entity_source: Dictionary = _interactive_flag_screen_component_indices if compact_interactive_records else _flag_screen_triangle_records
	for entity_key: Variant in entity_source.keys():
		entity_ids.append(str(entity_key))
	entity_ids.sort()
	for entity_id: String in entity_ids:
		if compact_interactive_records:
			var compact_component_indices: PackedInt32Array = _interactive_flag_screen_component_indices.get(entity_id, PackedInt32Array()) as PackedInt32Array
			var compact_source_triangles: PackedInt32Array = _interactive_flag_screen_source_triangles.get(entity_id, PackedInt32Array()) as PackedInt32Array
			var compact_clipped_children: PackedInt32Array = _interactive_flag_screen_clipped_children.get(entity_id, PackedInt32Array()) as PackedInt32Array
			for index: int in range(compact_component_indices.size()):
				result.append(
					"%s|%s|%d|%d" % [
						entity_id,
						_interactive_source_component_id(entity_id, int(compact_component_indices[index])),
						int(compact_source_triangles[index]) if index < compact_source_triangles.size() else -1,
						int(compact_clipped_children[index]) if index < compact_clipped_children.size() else -1,
					]
				)
			continue
		for record_value: Variant in (_flag_screen_triangle_records.get(entity_id, []) as Array):
			var record := record_value as Dictionary
			result.append(
				"%s|%s|%d|%d" % [
					entity_id,
					str(record.get("source_component", "")),
					int(record.get("source_triangle", -1)),
					int(record.get("clipped_child", -1)),
				]
			)
	result.sort()
	return result


func map_render_projected_fingerprint() -> String:
	var result: Array[String] = []
	var entity_ids: Array[String] = []
	var compact_interactive_records := _last_map_cache_lod == "interactive"
	var entity_source: Dictionary = _interactive_flag_screen_component_indices if compact_interactive_records else _flag_screen_triangle_records
	for entity_key: Variant in entity_source.keys():
		entity_ids.append(str(entity_key))
	entity_ids.sort()
	for entity_id: String in entity_ids:
		if compact_interactive_records:
			var compact_points: PackedVector2Array = _interactive_flag_screen_points.get(entity_id, PackedVector2Array()) as PackedVector2Array
			var compact_component_indices: PackedInt32Array = _interactive_flag_screen_component_indices.get(entity_id, PackedInt32Array()) as PackedInt32Array
			var compact_source_triangles: PackedInt32Array = _interactive_flag_screen_source_triangles.get(entity_id, PackedInt32Array()) as PackedInt32Array
			var compact_clipped_children: PackedInt32Array = _interactive_flag_screen_clipped_children.get(entity_id, PackedInt32Array()) as PackedInt32Array
			for index: int in range(0, compact_points.size(), 3):
				var compact_index: int = index / 3
				var values: Array[String] = [
					entity_id,
					_interactive_source_component_id(
						entity_id,
						int(compact_component_indices[compact_index]) if compact_index < compact_component_indices.size() else -1
					),
					str(int(compact_source_triangles[compact_index])) if compact_index < compact_source_triangles.size() else "-1",
					str(int(compact_clipped_children[compact_index])) if compact_index < compact_clipped_children.size() else "-1",
				]
				for point_offset: int in range(3):
					var point := compact_points[index + point_offset]
					values.append("%.5f,%.5f" % [point.x, point.y])
				result.append("|".join(values))
			continue
		for record_value: Variant in (_flag_screen_triangle_records.get(entity_id, []) as Array):
			var record := record_value as Dictionary
			var screen: PackedVector2Array = record.get("screen", PackedVector2Array()) as PackedVector2Array
			var uvs: PackedVector2Array = record.get("uvs", PackedVector2Array()) as PackedVector2Array
			var values: Array[String] = [
				entity_id,
				str(record.get("source_component", "")),
				str(int(record.get("source_triangle", -1))),
				str(int(record.get("clipped_child", -1))),
			]
			for point: Vector2 in screen:
				values.append("%.5f,%.5f" % [point.x, point.y])
			for uv: Vector2 in uvs:
				values.append("%.5f,%.5f" % [uv.x, uv.y])
			result.append("|".join(values))
	result.sort()
	return "\n".join(result)


func map_render_trace() -> Dictionary:
	var polities: Dictionary = {}
	var counts := {
		"expected": 0,
		"has_regions": 0,
		"has_geometry": 0,
		"projected": 0,
		"should_be_visible": 0,
		"submitted": 0,
		"drawn": 0,
		"invalid_projected_geometry": 0,
		"zero_size_projected_bounds": 0,
		"tiny_surface_fallback": 0,
		"source_triangles": 0,
		"visible_source_triangles": 0,
		"clipped_visible_triangles": 0,
		"submitted_triangles": 0,
		"drawn_triangles": 0,
		"missing_visible_triangles": 0,
		"source_planar_area": 0.0,
		"triangulated_planar_area": 0.0,
		"visible_projected_area": 0.0,
		"expected_visible_projected_area": 0.0,
		"submitted_projected_area": 0.0,
		"drawn_projected_area": 0.0,
		"screen_triangle_count": 0,
		"invalid_screen_triangles": 0,
		"suspicious_screen_triangles": 0,
		"invalid_screen_provenance": 0,
	}
	for country_value: Variant in _countries:
		var country := country_value as Dictionary
		var country_id := str(country.get("id", ""))
		var record := (_map_render_stage_records.get(country_id, {
			"id": country_id,
			"expected": true,
			"regions": 0,
			"geometry_parts": 0,
			"projected_parts": 0,
			"visible_parts": 0,
			"should_be_visible": false,
			"front_facing_geometry": false,
			"invalid_projected_parts": 0,
			"zero_size_projected_bounds": false,
			"tiny_surface_fallback_parts": 0,
			"source_triangles": 0,
			"visible_source_triangles": 0,
			"clipped_visible_triangles": 0,
			"submitted_triangles": 0,
			"drawn_triangles": 0,
			"missing_visible_triangles": 0,
			"source_planar_area": 0.0,
			"triangulated_planar_area": 0.0,
			"triangulation_area_ratio": 1.0,
			"visible_projected_area": 0.0,
			"submitted_projected_area": 0.0,
			"drawn_projected_area": 0.0,
			"visible_surface_coverage_ratio": 1.0,
		}) as Dictionary).duplicate(true)
		record["submitted_parts"] = int(_map_render_submitted_parts.get(country_id, 0))
		record["drawn_parts"] = int(_map_render_drawn_parts.get(country_id, 0))
		record["submitted_triangles"] = int(_map_render_submitted_triangles.get(country_id, 0))
		record["drawn_triangles"] = int(_map_render_drawn_triangles.get(country_id, 0))
		record["submitted_projected_area"] = float(_map_render_submitted_areas.get(country_id, 0.0))
		record["drawn_projected_area"] = float(_map_render_drawn_areas.get(country_id, 0.0))
		var visible_area: float = float(record.get("visible_projected_area", 0.0))
		var expected_visible_area: float = float(record.get("expected_visible_projected_area", 0.0))
		var drawn_area: float = float(record.get("drawn_projected_area", 0.0))
		record["visible_surface_coverage_ratio"] = drawn_area / expected_visible_area if expected_visible_area > MAP_PROJECTED_AREA_EPSILON else 1.0
		record["render_rejections"] = (_map_render_rejections.get(country_id, {}) as Dictionary).duplicate(true)
		record["render_fallbacks"] = (_map_render_fallbacks.get(country_id, {}) as Dictionary).duplicate(true)
		var screen_triangle_count := 0
		var invalid_screen_triangles := 0
		var suspicious_screen_triangles := 0
		var invalid_screen_provenance := 0
		var compact_interactive_records := _last_map_cache_lod == "interactive" and _interactive_flag_screen_component_indices.has(country_id)
		if compact_interactive_records:
			var compact_points: PackedVector2Array = _interactive_flag_screen_points.get(country_id, PackedVector2Array()) as PackedVector2Array
			var compact_component_indices: PackedInt32Array = _interactive_flag_screen_component_indices.get(country_id, PackedInt32Array()) as PackedInt32Array
			var compact_source_triangles: PackedInt32Array = _interactive_flag_screen_source_triangles.get(country_id, PackedInt32Array()) as PackedInt32Array
			for point_index: int in range(0, compact_points.size(), 3):
				var index := point_index / 3
				screen_triangle_count += 1
				if not _is_valid_screen_triangle_at(compact_points, point_index):
					invalid_screen_triangles += 1
				var source_component_index := int(compact_component_indices[index]) if index < compact_component_indices.size() else -1
				var source_component := _interactive_source_component_id(country_id, source_component_index)
				var source_triangle := int(compact_source_triangles[index]) if index < compact_source_triangles.size() else -1
				var component_records := _country_surface_triangle_records.get(source_component, []) as Array
				var interactive_surface_buffer := _interactive_country_surface_triangle_buffers.get(country_id, {}) as Dictionary
				var lod_provenance := str(interactive_surface_buffer.get("provenance_mode", "")) == "INTERACTION_BOUNDARY_LOD"
				if source_component.is_empty() or not source_component.begins_with(country_id + ":") or (
					(not lod_provenance and (source_triangle < 0 or source_triangle >= component_records.size()))
				):
					invalid_screen_provenance += 1
		else:
			var interactive_surface_buffer := _interactive_country_surface_triangle_buffers.get(country_id, {}) as Dictionary
			var lod_provenance := str(interactive_surface_buffer.get("provenance_mode", "")) == "INTERACTION_BOUNDARY_LOD"
			for screen_record_value: Variant in (_flag_screen_triangle_records.get(country_id, []) as Array):
				var screen_record := screen_record_value as Dictionary
				screen_triangle_count += 1
				var screen: PackedVector2Array = screen_record.get("screen", PackedVector2Array()) as PackedVector2Array
				var uvs: PackedVector2Array = screen_record.get("uvs", PackedVector2Array()) as PackedVector2Array
				var topology: Dictionary = screen_record.get("topology", {}) as Dictionary
				var finite_screen := screen.size() == 3
				for point: Vector2 in screen:
					finite_screen = finite_screen and is_finite(point.x) and is_finite(point.y)
				var valid_screen := screen.size() == 3 and uvs.size() == 3 and (
					bool(topology.get("finite", false)) if not topology.is_empty() else finite_screen
				)
				if valid_screen:
					valid_screen = _screen_polygon_area(screen) > MAP_TRIANGLE_AREA_EPSILON
				if not valid_screen:
					invalid_screen_triangles += 1
				if not topology.is_empty() and bool(topology.get("suspicious", false)):
					suspicious_screen_triangles += 1
				var source_component := str(screen_record.get("source_component", ""))
				var source_triangle := int(screen_record.get("source_triangle", -1))
				var component_records := _country_surface_triangle_records.get(source_component, []) as Array
				if source_component.is_empty() or not source_component.begins_with(country_id + ":") or (
					not lod_provenance and (source_triangle < 0 or source_triangle >= component_records.size())
				):
					invalid_screen_provenance += 1
		record["screen_triangle_count"] = screen_triangle_count
		record["invalid_screen_triangles"] = invalid_screen_triangles
		record["suspicious_screen_triangles"] = suspicious_screen_triangles
		record["invalid_screen_provenance"] = invalid_screen_provenance
		if has_method("historical_flag_material_trace"):
			var material_trace: Dictionary = call("historical_flag_material_trace", country_id) as Dictionary
			for trace_key: Variant in material_trace.keys():
				record[str(trace_key)] = material_trace[trace_key]
		record["pipeline"] = {
			"EXPECTED": bool(record.get("expected", false)),
			"HAS_REGIONS": int(record.get("regions", 0)) > 0,
			"LAND_GEOMETRY_PRESENT": not _physical_land_polygons.is_empty(),
			"POLITICAL_GEOMETRY_PRESENT": int(record.get("geometry_parts", 0)) > 0,
			"HISTORICAL_OWNER_RESOLVED": bool(record.get("HISTORICAL_OWNER_RESOLVED", false)),
			"DISPLAY_ENTITY_RESOLVED": bool(record.get("DISPLAY_ENTITY_RESOLVED", false)),
			"PROJECTED": int(record.get("projected_parts", 0)) > 0,
			"SHOULD_BE_VISIBLE": bool(record.get("should_be_visible", false)),
			"SUBMITTED": int(record.get("submitted_parts", 0)) > 0,
			"DRAWN": int(record.get("drawn_parts", 0)) > 0,
			"FILL_SUBMITTED": bool(record.get("fill_submitted", false)),
			"FILL_DRAWN": bool(record.get("fill_drawn", false)),
			"BORDER_DRAWN": bool(record.get("border_drawn", false)),
			"LABEL_DRAWN": bool(record.get("label_drawn", false)),
			"SCREEN_TOPOLOGY_VALID": int(record.get("invalid_screen_triangles", 0)) == 0
				and int(record.get("invalid_screen_provenance", 0)) == 0
				and int(record.get("suspicious_screen_triangles", 0)) == 0,
		}
		polities[country_id] = record
		counts["expected"] += 1
		if int(record.get("regions", 0)) > 0:
			counts["has_regions"] += 1
		if int(record.get("geometry_parts", 0)) > 0:
			counts["has_geometry"] += 1
		if int(record.get("projected_parts", 0)) > 0:
			counts["projected"] += 1
		if bool(record.get("should_be_visible", false)):
			counts["should_be_visible"] += 1
		if int(record.get("submitted_parts", 0)) > 0:
			counts["submitted"] += 1
		if int(record.get("drawn_parts", 0)) > 0:
			counts["drawn"] += 1
		counts["source_triangles"] += int(record.get("source_triangles", 0))
		counts["visible_source_triangles"] += int(record.get("visible_source_triangles", 0))
		counts["clipped_visible_triangles"] += int(record.get("clipped_visible_triangles", 0))
		counts["submitted_triangles"] += int(record.get("submitted_triangles", 0))
		counts["drawn_triangles"] += int(record.get("drawn_triangles", 0))
		counts["missing_visible_triangles"] += int(record.get("missing_visible_triangles", 0))
		counts["source_planar_area"] += float(record.get("source_planar_area", 0.0))
		counts["triangulated_planar_area"] += float(record.get("triangulated_planar_area", 0.0))
		counts["visible_projected_area"] += float(record.get("visible_projected_area", 0.0))
		counts["expected_visible_projected_area"] += float(record.get("expected_visible_projected_area", 0.0))
		counts["submitted_projected_area"] += float(record.get("submitted_projected_area", 0.0))
		counts["drawn_projected_area"] += float(record.get("drawn_projected_area", 0.0))
		counts["screen_triangle_count"] += int(record.get("screen_triangle_count", 0))
		counts["invalid_screen_triangles"] += int(record.get("invalid_screen_triangles", 0))
		counts["suspicious_screen_triangles"] += int(record.get("suspicious_screen_triangles", 0))
		counts["invalid_screen_provenance"] += int(record.get("invalid_screen_provenance", 0))
		counts["invalid_projected_geometry"] += int(record.get("invalid_projected_parts", 0))
		if bool(record.get("zero_size_projected_bounds", false)):
			counts["zero_size_projected_bounds"] += 1
		counts["tiny_surface_fallback"] += int(record.get("tiny_surface_fallback_parts", 0))
	return {
		"projection_revision": _projection_revision,
		"projection_cache_revision": _projection_cache_revision,
		"flag_projection_cache_revision": _flag_projection_cache_revision,
		"profile": _map_render_profile.duplicate(true),
		"flag_draw_validation_failures": _flag_draw_validation_failures.duplicate(true),
		"counts": counts,
		"polities": polities,
	}


func _draw_country_flag_skins() -> void:
	var zoom_mix: float = inverse_lerp(WORLD_ZOOM_MIN, WORLD_ZOOM_MAX, world_zoom)
	var base_alpha: float = lerpf(0.205, 0.105, zoom_mix)
	for country_key_value: Variant in _flag_screen_polygons.keys():
		var country_id: String = str(country_key_value)
		var country: Dictionary = _country_by_id.get(country_id, {}) as Dictionary
		var iso: String = str(country.get("iso_a3", "")).to_upper()
		var palette: Dictionary = _resolved_flag_palette(iso)
		var bounds: Rect2 = _flag_screen_bounds.get(country_id, Rect2()) as Rect2
		var selected: bool = country_id == selected_country_id
		var hovered: bool = country_id == hover_country_id
		var alpha: float = base_alpha
		if selected:
			alpha = maxf(alpha, 0.31)
		elif hovered:
			alpha = maxf(alpha, 0.255)
		var polygons: Array = _flag_screen_polygons.get(country_id, []) as Array
		for polygon_value: Variant in polygons:
			var polygon: PackedVector2Array = polygon_value
			_draw_flag_polygon(polygon, bounds, palette, country_id, alpha)


func _draw_flag_polygon(
	polygon: PackedVector2Array,
	bounds: Rect2,
	palette: Dictionary,
	country_id: String,
	alpha: float
) -> void:
	if polygon.size() < 3:
		return
	var colors: PackedColorArray = palette.get("colors", PackedColorArray()) as PackedColorArray
	if colors.is_empty():
		return
	var pattern: String = str(palette.get("pattern", "solid"))
	var vertex_colors: PackedColorArray = PackedColorArray()
	var safe_width: float = maxf(bounds.size.x, 1.0)
	var safe_height: float = maxf(bounds.size.y, 1.0)
	var phase: float = float(abs(country_id.hash()) % 997) / 997.0
	for point: Vector2 in polygon:
		var u: float = clampf((point.x - bounds.position.x) / safe_width, 0.0, 1.0)
		var v: float = clampf((point.y - bounds.position.y) / safe_height, 0.0, 1.0)
		var raw_color: Color = _flag_pattern_color(pattern, colors, u, v)
		var alternate: Color = colors[(int(floor((u + v) * float(colors.size()))) + 1) % colors.size()]
		var wave: float = sin(_flag_time * (0.60 + phase * 0.32) + u * 6.2 + v * 2.8 + phase * TAU)
		var secondary_wave: float = sin(_flag_time * 0.37 + v * 7.4 - phase * 4.0)
		var wave_mix: float = 0.025 + (wave + 1.0) * 0.016
		raw_color = raw_color.lerp(alternate, wave_mix)
		var subdued: Color = raw_color.lerp(Color(0.24, 0.34, 0.36, 1.0), 0.46)
		var brightness: float = 0.92 + wave * 0.055 + secondary_wave * 0.022
		vertex_colors.append(Color(
			clampf(subdued.r * brightness, 0.0, 1.0),
			clampf(subdued.g * brightness, 0.0, 1.0),
			clampf(subdued.b * brightness, 0.0, 1.0),
			alpha * (0.94 + wave * 0.045)
		))
	draw_polygon(polygon, vertex_colors)


func _flag_pattern_color(
	pattern: String,
	colors: PackedColorArray,
	u: float,
	v: float
) -> Color:
	var count: int = colors.size()
	if count == 1:
		return colors[0]
	if pattern == "vertical":
		return colors[clampi(int(floor(u * float(count))), 0, count - 1)]
	if pattern == "horizontal":
		return colors[clampi(int(floor(v * float(count))), 0, count - 1)]
	if pattern == "cross":
		var cross_color: Color = colors[1]
		if absf(u - 0.5) < 0.115 or absf(v - 0.5) < 0.115:
			if count > 2 and (absf(u - 0.5) < 0.042 or absf(v - 0.5) < 0.042):
				return colors[2]
			return cross_color
		return colors[0]
	if pattern == "canton":
		if count > 2 and u < 0.40 and v < 0.42:
			return colors[2]
		return colors[0] if v < 0.5 else colors[1]
	if pattern == "disc":
		var distance: float = Vector2(u, v).distance_to(Vector2(0.5, 0.5))
		if count > 2 and distance < 0.10:
			return colors[2]
		if distance < 0.24:
			return colors[1]
		return colors[0]
	if pattern == "quartered":
		var quadrant: int = (1 if u >= 0.5 else 0) + (2 if v >= 0.5 else 0)
		return colors[quadrant % count]
	return colors[0]


func _resolved_flag_palette(iso: String) -> Dictionary:
	if _flag_palettes.has(iso):
		return _flag_palettes.get(iso, {}) as Dictionary
	var fallback_sets: Array[PackedColorArray] = [
		PackedColorArray([Color("#315A82"), Color("#ECE9DF"), Color("#9A3038")]),
		PackedColorArray([Color("#3C6C57"), Color("#ECE9DF"), Color("#9A3038")]),
		PackedColorArray([Color("#C9A443"), Color("#3C6C57"), Color("#9A3038")]),
		PackedColorArray([Color("#315A82"), Color("#C9A443"), Color("#9A3038")]),
		PackedColorArray([Color("#9A3038"), Color("#ECE9DF")]),
		PackedColorArray([Color("#315A82"), Color("#ECE9DF")]),
	]
	var patterns: Array[String] = ["horizontal", "vertical", "horizontal", "vertical", "solid", "cross"]
	var index: int = abs(iso.hash()) % fallback_sets.size()
	return {"pattern": patterns[index], "colors": fallback_sets[index]}


func _draw_zoom_country_labels() -> void:
	var label_alpha: float = _country_label_alpha()
	if label_alpha <= 0.02:
		return
	var max_rank: int = 2 if world_zoom < 1.15 else 4
	var max_labels: int = int(round(lerpf(7.0, 20.0, label_alpha)))
	var candidates: Array[Dictionary] = []
	for country_key_value: Variant in _country_screen_anchors.keys():
		var country_id: String = str(country_key_value)
		if country_id == selected_country_id or country_id == hover_country_id:
			continue
		var country: Dictionary = _country_by_id.get(country_id, {}) as Dictionary
		var rank: int = int(country.get("label_rank", 9))
		if rank > max_rank:
			continue
		candidates.append({
			"id": country_id,
			"name": str(country.get("name", country_id)),
			"rank": rank,
			"point": _country_screen_anchors.get(country_id, Vector2.ZERO),
		})
	candidates.sort_custom(Callable(self, "_country_label_before"))
	var occupied: Array[Rect2] = []
	var viewport_rect: Rect2 = Rect2(viewport_container.position, viewport_container.size)
	var drawn: int = 0
	for candidate: Dictionary in candidates:
		if drawn >= max_labels:
			break
		var point: Vector2 = candidate.get("point", Vector2.ZERO) as Vector2
		var name: String = str(candidate.get("name", ""))
		var width: float = maxf(38.0, float(name.length()) * 10.5)
		var label_rect: Rect2 = Rect2(point + Vector2(7.0, -14.0), Vector2(width, 18.0))
		if not viewport_rect.encloses(label_rect):
			continue
		var overlaps: bool = false
		for existing: Rect2 in occupied:
			if existing.intersects(label_rect.grow(3.0)):
				overlaps = true
				break
		if overlaps:
			continue
		occupied.append(label_rect)
		_draw_label(label_rect.position + Vector2(0.0, 13.0), name, 11, Color(0.86, 0.89, 0.84, label_alpha * 0.92))
		var stage := _map_render_stage_records.get(str(candidate.get("id", "")), {}) as Dictionary
		stage["label_drawn"] = true
		_map_render_stage_records[str(candidate.get("id", ""))] = stage
		drawn += 1


func _country_label_before(a: Dictionary, b: Dictionary) -> bool:
	var a_rank: int = int(a.get("rank", 9))
	var b_rank: int = int(b.get("rank", 9))
	if a_rank == b_rank:
		var a_point: Vector2 = a.get("point", Vector2.ZERO) as Vector2
		var b_point: Vector2 = b.get("point", Vector2.ZERO) as Vector2
		return a_point.distance_squared_to(_hemisphere_center) < b_point.distance_squared_to(_hemisphere_center)
	return a_rank < b_rank


func _country_label_alpha() -> float:
	return smoothstep(COUNTRY_LABEL_FADE_START, COUNTRY_LABEL_FADE_END, world_zoom)


func _draw_zoom_indicator() -> void:
	var text: String = "滚轮缩放 %d%%" % int(round(world_zoom * 100.0))
	var mode_text: String = "旗色总览" if _country_label_alpha() < 0.25 else "国家名称"
	_draw_label(
		Vector2(_hemisphere_rect.position.x + 14.0, _hemisphere_rect.end.y - 14.0),
		text + " · " + mode_text,
		10,
		Color(0.66, 0.75, 0.72, 0.68)
	)
