extends Node3D
## Fictional, unregistered training presentation. No actors, WorldState or actions.
## Native 4m render/support/collision vertices are never moved for LOD stitching.
## Only coarse-side boundary topology changes. A staged LOD batch commits atomically.
signal prepared
signal changed
signal failed(message: String)

const HeightSource: GDScript = preload("res://modules/region_observation/terrain_height_source.gd")
const GroundShader: Shader = preload("res://modules/region_observation/layered_ground.gdshader")
const DEFAULT_BASE_PATH: String = "res://"
const REGION_MIN: float = -22500.0
const REGION_MAX: float = 27500.0
const NATIVE_HALF: float = 2500.0
const NATIVE_VIEW_LIMIT: float = 8500.0
const DETAIL_VIEW_LIMIT: float = 1800.0
const MAX_DETAIL_TILES: int = 9
const COLLISION_MARGIN: float = 64.0
const COLLISION_SIZE: float = 100.0
const REGION_NATIVE_NEIGHBORS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(3, 4), Vector2i(5, 4), Vector2i(4, 3), Vector2i(4, 5)]

var training_only: bool = true
var _base_path: String = DEFAULT_BASE_PATH
var _center: Vector2 = Vector2.ZERO
var _span: float = 50000.0
var _started: bool = false
var _prepared: bool = false
var _data_ready: bool = false
var _native_requested: bool = false
var _native_active: bool = false
var _external_native_owner: bool = false
var _region_heights: PackedFloat32Array = PackedFloat32Array()
var _native_heights: PackedFloat32Array = PackedFloat32Array()
var _region_tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _native_tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _desired_fine: Dictionary = {}
var _active_fine: Dictionary = {}
var _region_material: ShaderMaterial
var _native_material: ShaderMaterial
var _surface_materials: Array[WeakRef] = []
var _loaded_textures: Dictionary[String, Texture2D] = {}
var _texture_requests: Dictionary[String, String] = {}
var _resource_notes: PackedStringArray = PackedStringArray()
var _worker: Thread
var _worker_kind: String = ""
var _stage_results: Array[Dictionary] = []
var _staged_nodes: Array[MeshInstance3D] = []
var _stage_fine: Dictionary = {}
var _stage_index: int = 0
var _collision_enabled: bool = true
var _collision_layer: int = 1
var _collision_tiles: Dictionary[Vector2i, StaticBody3D] = {}
var _last_mesh_install_usec: int = 0
var _last_shape_install_usec: int = 0
var _max_mesh_install_usec: int = 0
var _max_shape_install_usec: int = 0
# Explicit opt-in timing, bounded in memory/logs; original update policy is unchanged.
var _slow_timing_enabled: bool = OS.get_environment("WWO_TERRAIN_SLOW_TIMING") == "1"
var _slow_timing_threshold_usec: int = 16000
var _slow_timing_limit: int = 64
var _slow_timing_print: bool = true
var _slow_timing_events: Array[Dictionary] = []
var _slow_timing_overwritten: int = 0
var _slow_timing_printed: int = 0
var _slow_job_id: int = 0
var _slow_process_install_usec: int = 0


func set_slow_timing(enabled: bool, slow_usec: int = 16000, event_limit: int = 64, print_events: bool = true) -> void:
	_slow_timing_enabled = enabled
	_slow_timing_threshold_usec = maxi(1, slow_usec)
	_slow_timing_limit = clampi(event_limit, 1, 64)
	_slow_timing_print = print_events
	_slow_timing_events.clear()
	_slow_timing_overwritten = 0
	_slow_timing_printed = 0


func get_slow_timing() -> Dictionary:
	return {"enabled": _slow_timing_enabled, "threshold_usec": _slow_timing_threshold_usec,
		"event_limit": _slow_timing_limit, "overwritten": _slow_timing_overwritten,
		"printed": _slow_timing_printed, "events": _slow_timing_events.duplicate(true)}


func _record_slow_timing(operation: String, started_usec: int, ended_usec: int, segments: Dictionary, context: Dictionary = {}) -> void:
	if not _slow_timing_enabled or ended_usec - started_usec < _slow_timing_threshold_usec:
		return
	var event: Dictionary = {"source": "region_observation", "operation": operation,
		"thread": "main", "frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(),
		"start_usec": started_usec, "end_usec": ended_usec, "total_usec": ended_usec - started_usec,
		"segments_usec": segments}
	event.merge(context, true)
	if _slow_timing_events.size() >= _slow_timing_limit:
		_slow_timing_events.pop_front()
		_slow_timing_overwritten += 1
	_slow_timing_events.append(event)
	if _slow_timing_print and _slow_timing_printed < _slow_timing_limit:
		_slow_timing_printed += 1
		print("TERRAIN_SLOW ", JSON.stringify(event))


func _finish_slow_main_update(started_usec: int) -> void:
	if not _slow_timing_enabled:
		return
	var ended_usec: int = Time.get_ticks_usec()
	_record_slow_timing("main_update", started_usec, ended_usec,
		{"mesh_and_shape_install": _slow_process_install_usec,
		"other_main_update": maxi(0, ended_usec - started_usec - _slow_process_install_usec)})


func begin(config: Dictionary) -> void:
	close()
	if OS.get_environment("WWO_TERRAIN_SLOW_TIMING") == "1":
		_slow_timing_enabled = true
	if config.get("training_only", true) != true:
		failed.emit("仅允许 training_only 地形，不是正式地理或军事世界")
		return
	_base_path = str(config.get("base_path", DEFAULT_BASE_PATH)).strip_edges()
	if not _base_path.begins_with("res://"):
		failed.emit("地形 base_path 必须是项目内 res:// 路径")
		return
	if not _base_path.ends_with("/"):
		_base_path += "/"
	_center = Vector2.ZERO
	_span = 50000.0
	var configured_center: Variant = config.get("center", Vector2.ZERO)
	if configured_center is Vector2:
		var point: Vector2 = configured_center
		if point.is_finite():
			_center = _clamp_center(point)
	var configured_span: Variant = config.get("span_m", 50000.0)
	if configured_span is int or configured_span is float:
		var value: float = float(configured_span)
		if is_finite(value):
			_span = clampf(value, 50.0, 75000.0)
	_collision_enabled = bool(config.get("collision_enabled", true))
	_collision_layer = clampi(int(config.get("collision_layer", 1)), 1, 2147483647)
	training_only = true
	_started = true
	set_meta("training_only", true)
	set_meta("geographically_registered", false)
	_region_material = create_surface_material({"native_surface": false})
	_native_material = create_surface_material({"native_surface": true})
	_request_textures()
	_launch("sources", HeightSource.read_sources.bind(_base_path))
	set_process(true)


func update_view(center: Vector2, span_m: float) -> void:
	if not _started or not center.is_finite() or not is_finite(span_m):
		return
	var next_center: Vector2 = _clamp_center(center)
	var next_span: float = clampf(span_m, 50.0, 75000.0)
	if next_center.is_equal_approx(_center) and is_equal_approx(next_span, _span):
		return
	_center = next_center
	_span = next_span
	set_process(true)
	_refresh_targets()


func sample_height(x: float, z: float) -> float:
	# Passive authoritative support query; external training owner owns its edits.
	if not _data_ready or not is_finite(x) or not is_finite(z):
		return NAN
	if not _native_heights.is_empty() and absf(x) <= NATIVE_HALF and absf(z) <= NATIVE_HALF:
		return HeightSource.sample(_native_heights, 1251, -2500.0, 4.0, x, z)
	return HeightSource.sample(_region_heights, 1001, REGION_MIN, 50.0, x, z)


func is_ready() -> bool:
	return _prepared


func is_collision_ready(position: Vector3) -> bool:
	if not _data_ready or not _native_active or _external_native_owner or not _native_requested or not _collision_enabled or not position.is_finite():
		return false
	if absf(position.x) > NATIVE_HALF or absf(position.z) > NATIVE_HALF:
		return false
	if not _active_fine.has(_native_key(Vector2(position.x, position.z))):
		return false
	for key: Vector2i in _collision_keys(Vector2(position.x, position.z)):
		if not _collision_tiles.has(key):
			return false
	return true


func set_external_native_owner(active: bool) -> void:
	if active == _external_native_owner:
		return
	_external_native_owner = active
	if _started:
		set_process(true)
	_discard_stage()
	_clear_collision()
	_refresh_targets()
	_refresh_visibility()
	changed.emit()


func create_surface_material(options: Dictionary = {}) -> ShaderMaterial:
	# The original military owner may provide its own 100x100 / 50m coverage.
	# It retains collision, damage commands, support revision and simulation anchors.
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GroundShader
	material.set_shader_parameter("native_surface", bool(options.get("native_surface", true)))
	material.set_shader_parameter("coverage_enabled", bool(options.get("coverage_enabled", options.get("far_mesh", false))))
	material.set_shader_parameter("far_mesh", bool(options.get("far_mesh", false)))
	material.set_shader_parameter("coverage_cells", maxf(1.0, float(options.get("coverage_cells", 10.0))))
	material.set_shader_parameter("use_vertex_damage", bool(options.get("use_vertex_damage", false)))
	var coverage: Variant = options.get("detail_coverage")
	if coverage is Texture2D:
		material.set_shader_parameter("detail_coverage", coverage)
	material.set_shader_parameter("terrain_to_local", global_transform.affine_inverse())
	material.set_shader_parameter("terrain_to_world", global_transform)
	for parameter: String in _loaded_textures:
		material.set_shader_parameter(parameter, _loaded_textures[parameter])
		material.set_shader_parameter("has_" + parameter, true)
	_surface_materials.append(weakref(material))
	return material


func apply_command(_position: Vector3, _kind: String = "dig", _layer: String = "terrain") -> Dictionary:
	return {"ok": false, "error": "unsupported", "reason": "read_only_training_presentation"}


func apply_explosion(_position: Vector3, _mass: float) -> Dictionary:
	return {"ok": false, "error": "unsupported", "reason": "read_only_training_presentation"}


func get_status() -> Dictionary:
	var status: Dictionary = {
		"training_only": true, "geographically_registered": false,
		"ready": _prepared, "native_available": not _native_heights.is_empty(),
		"native_visible": _native_requested and _native_active and not _external_native_owner,
		"external_native_owner": _external_native_owner, "terrain_edit_supported": false,
		"region_tiles": _region_tiles.size(), "native_tiles": _native_tiles.size(),
		"detail_tiles": _active_fine.size(), "detail_tile_limit": MAX_DETAIL_TILES,
		"queued_tiles": maxi(0, _stage_results.size() - _stage_index),
		"loading": _worker != null or not _stage_results.is_empty(), "loading_kind": _worker_kind,
		"local_collision_ready": is_collision_ready(Vector3(_center.x, 0.0, _center.y)),
		"collision_tiles": _collision_tiles.size(), "collision_tile_limit": 9,
		"last_mesh_install_usec": _last_mesh_install_usec,
		"last_shape_install_usec": _last_shape_install_usec,
		"max_mesh_install_usec": _max_mesh_install_usec,
		"max_shape_install_usec": _max_shape_install_usec,
		"resource_notes": _resource_notes.duplicate(),
	}
	if _slow_timing_enabled:
		status["slow_timing"] = get_slow_timing()
	return status


func close() -> void:
	set_process(false)
	_started = false
	_prepared = false
	_data_ready = false
	_native_requested = false
	_native_active = false
	_external_native_owner = false
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
	_worker_kind = ""
	_discard_stage()
	for path: String in _texture_requests:
		var state: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_LOADED or state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(path)
	_texture_requests.clear()
	for tile: MeshInstance3D in _region_tiles.values():
		_release_node(tile)
	for tile: MeshInstance3D in _native_tiles.values():
		_release_node(tile)
	_region_tiles.clear()
	_native_tiles.clear()
	_desired_fine.clear()
	_active_fine.clear()
	_clear_collision()
	_region_heights = PackedFloat32Array()
	_native_heights = PackedFloat32Array()
	_region_material = null
	_native_material = null
	_surface_materials.clear()
	_loaded_textures.clear()
	_resource_notes = PackedStringArray()
	_last_mesh_install_usec = 0
	_last_shape_install_usec = 0
	_max_mesh_install_usec = 0
	_max_shape_install_usec = 0
	_slow_timing_events.clear()
	_slow_timing_overwritten = 0
	_slow_timing_printed = 0
	_slow_job_id = 0
	_slow_process_install_usec = 0


func _exit_tree() -> void:
	close()


func _process(_delta: float) -> void:
	if not _started:
		return
	var slow_started_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	if _slow_timing_enabled:
		_slow_process_install_usec = 0
	_poll_one_texture()
	if not _stage_results.is_empty():
		_stage_one_patch()
		if _stage_results.is_empty() and _worker == null and _data_ready:
			_start_next_work()
		if _slow_timing_enabled:
			_finish_slow_main_update(slow_started_usec)
		return
	if _worker != null and not _worker.is_alive():
		var result: Variant = _worker.wait_to_finish()
		_worker = null
		_worker_kind = ""
		if result is Dictionary:
			_accept_result(result)
		else:
			failed.emit("训练地形工作线程返回无效数据")
		# Start computation, not another upload, while this frame's patch is ready.
		if _started and _worker == null and _stage_results.is_empty() and _data_ready:
			_start_next_work()
		if _slow_timing_enabled:
			_finish_slow_main_update(slow_started_usec)
		return
	if _worker == null and _data_ready:
		_start_next_work()
	if _slow_timing_enabled:
		_finish_slow_main_update(slow_started_usec)


func _accept_result(result: Dictionary) -> void:
	if _slow_timing_enabled and result.has("_slow_worker"):
		var timing: Dictionary = result["_slow_worker"]
		var worker_start: int = int(timing["start_usec"])
		var worker_end: int = int(timing["end_usec"])
		_record_slow_timing("worker_data", worker_start, worker_end,
			{"worker_data": worker_end - worker_start}, {
			"thread": "worker", "frame": timing["dispatch_frame"],
			"physics_frame": timing["dispatch_physics_frame"], "frame_role": "dispatch",
			"received_frame": Engine.get_process_frames(), "job_id": timing["job_id"],
			"job_kind": timing["job_kind"], "dispatch_usec": timing["dispatch_usec"]})
	if not bool(result.get("ok", false)):
		_started = false
		set_process(false)
		failed.emit(str(result.get("error", "训练地形读取失败")))
		return
	var kind: String = str(result.get("kind", "sources"))
	if kind == "sources":
		_region_heights = result["region"]
		_native_heights = result["native"]
		_data_ready = true
		var note: String = str(result.get("native_error", ""))
		if not note.is_empty():
			_resource_notes.append("5km 细图不可用：" + note)
		_refresh_targets()
	elif kind == "transition":
		var fine: Dictionary = result["fine"]
		if _external_native_owner or fine != _desired_fine:
			return
		_stage_fine = fine
		_stage_results.assign(result["patches"])
		if _slow_timing_enabled and result.has("_slow_worker"):
			for patch: Dictionary in _stage_results:
				patch["_slow_worker"] = result["_slow_worker"]
		_stage_index = 0
		if _stage_results.is_empty():
			_active_fine = fine
	elif kind == "collision":
		if not _external_native_owner and _collision_keys(_center).has(result["key"]) and not _desired_fine.is_empty():
			_install_collision(result)
	else:
		if kind == "native" and _external_native_owner:
			return
		if kind == "region":
			var expected_fine: Dictionary = {} if _external_native_owner else _active_fine
			if str(result["signature"]) != _region_signature(result["key"], expected_fine):
				return
		var tile: MeshInstance3D = _upload_patch(result)
		_replace_tile(tile)
		if _native_tiles.size() == 100:
			_native_active = true
		_refresh_visibility()
		_mark_prepared()
	changed.emit()


func _refresh_targets() -> void:
	# Central 20m terrain persists at all observation levels once prepared.
	_native_requested = not _native_heights.is_empty()
	var near_native: bool = absf(_center.x) <= NATIVE_HALF + _span * 0.5 and absf(_center.y) <= NATIVE_HALF + _span * 0.5
	var desired: Dictionary = {}
	if _native_requested and near_native and _span < DETAIL_VIEW_LIMIT:
		var focus: Vector2i = _native_key(_center)
		for row: int in range(maxi(0, focus.y - 1), mini(10, focus.y + 2)):
			for column: int in range(maxi(0, focus.x - 1), mini(10, focus.x + 2)):
				desired[Vector2i(column, row)] = true
	_desired_fine = desired
	var required: Array[Vector2i] = _collision_keys(_center)
	for key: Vector2i in _collision_tiles.keys():
		if _external_native_owner or desired.is_empty() or not required.has(key):
			_release_node(_collision_tiles[key])
			_collision_tiles.erase(key)
	_refresh_visibility()


func _start_next_work() -> void:
	var regional_fine: Dictionary = {} if _external_native_owner else _active_fine
	# Keep a visible real coarse fallback; wide views finish their periphery first.
	if _region_tiles.is_empty() or (_span >= NATIVE_VIEW_LIMIT and _region_tiles.size() < 100):
		var first_region: Vector2i = _nearest_missing(_region_tiles, 10, 5000.0, REGION_MIN)
		_launch("region", HeightSource.build_patch.bind(_patch_job("region", first_region, regional_fine)))
		return
	if not _external_native_owner and _native_requested and not _native_active:
		var missing: Vector2i = _nearest_missing(_native_tiles, 10, 500.0, -2500.0)
		if missing.x >= 0:
			_launch("native", HeightSource.build_patch.bind(_patch_job("native", missing, {})))
			return
	if not _external_native_owner and _native_active and _active_fine != _desired_fine:
		var planned: Dictionary = _desired_fine.duplicate()
		var jobs: Array[Dictionary] = []
		for key: Vector2i in _native_tiles:
			var signature: String = _native_signature(key, planned)
			if str(_native_tiles[key].get_meta("signature", "")) != signature:
				jobs.append(_patch_job("native", key, planned))
		for key: Vector2i in REGION_NATIVE_NEIGHBORS:
			if not _region_tiles.has(key) or str(_region_tiles[key].get_meta("signature", "")) != _region_signature(key, planned):
				jobs.append(_patch_job("region", key, planned))
		_launch("transition", HeightSource.build_transition.bind(jobs, planned))
		return
	# Region's coarse side follows the actual native boundary, also on owner handoff.
	for key: Vector2i in REGION_NATIVE_NEIGHBORS:
		if _region_tiles.has(key) and str(_region_tiles[key].get_meta("signature", "")) != _region_signature(key, regional_fine):
			_launch("region", HeightSource.build_patch.bind(_patch_job("region", key, regional_fine)))
			return
	if not _external_native_owner and _collision_enabled and _native_active and not _desired_fine.is_empty() and absf(_center.x) <= NATIVE_HALF and absf(_center.y) <= NATIVE_HALF:
		for key: Vector2i in _collision_keys(_center):
			if not _collision_tiles.has(key):
				_launch("collision", HeightSource.build_collision.bind(key, _native_heights))
				return
	var region_key: Vector2i = _nearest_missing(_region_tiles, 10, 5000.0, REGION_MIN)
	if region_key.x >= 0:
		_launch("region", HeightSource.build_patch.bind(_patch_job("region", region_key, regional_fine)))
	elif _texture_requests.is_empty():
		# No repeated static-cache scan, upload or viewport wakeup while idle.
		set_process(false)


func _patch_job(kind: String, key: Vector2i, fine: Dictionary) -> Dictionary:
	if kind == "region":
		return {
			"kind": kind, "key": key, "lod": 250, "signature": _region_signature(key, fine),
			"heights": _region_heights, "width": 1001, "source_origin": REGION_MIN, "source_step": 50.0,
			"origin": Vector2(REGION_MIN, REGION_MIN) + Vector2(key) * 5000.0,
			"cells": 20, "step": 250.0, "native": _native_heights, "fine": fine,
		}
	var is_fine: bool = fine.has(key)
	return {
		"kind": "native", "key": key, "lod": 4 if is_fine else 20, "signature": _native_signature(key, fine),
		"heights": _native_heights, "width": 1251, "source_origin": -2500.0, "source_step": 4.0,
		"origin": Vector2(-2500.0, -2500.0) + Vector2(key) * 500.0,
		"cells": 125 if is_fine else 25, "step": 4.0 if is_fine else 20.0, "fine": fine,
	}


func _native_signature(key: Vector2i, fine: Dictionary) -> String:
	if fine.has(key):
		return "4"
	var bits: int = 0
	var offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
	for index: int in offsets.size():
		if fine.has(key + offsets[index]):
			bits |= 1 << index
	return "20:%d" % bits


func _region_signature(key: Vector2i, fine: Dictionary) -> String:
	var signature: String = "250"
	if not REGION_NATIVE_NEIGHBORS.has(key):
		return signature
	for index: int in 10:
		if key == Vector2i(4, 4) or key == Vector2i(3, 4):
			signature += "1" if fine.has(Vector2i(0, index)) else "0"
		if key == Vector2i(4, 4) or key == Vector2i(5, 4):
			signature += "1" if fine.has(Vector2i(9, index)) else "0"
		if key == Vector2i(4, 4) or key == Vector2i(4, 3):
			signature += "1" if fine.has(Vector2i(index, 0)) else "0"
		if key == Vector2i(4, 4) or key == Vector2i(4, 5):
			signature += "1" if fine.has(Vector2i(index, 9)) else "0"
	return signature


func _stage_one_patch() -> void:
	if _external_native_owner or _stage_fine != _desired_fine:
		_discard_stage()
		return
	var tile: MeshInstance3D = _upload_patch(_stage_results[_stage_index])
	tile.hide()
	_staged_nodes.append(tile)
	_stage_index += 1
	if _stage_index < _stage_results.size():
		return
	# All new boundary partners exist before any old matched surface disappears.
	for node: MeshInstance3D in _staged_nodes:
		_replace_tile(node)
	_active_fine = _stage_fine
	_staged_nodes = []
	_stage_results = []
	_stage_fine = {}
	_stage_index = 0
	_refresh_visibility()
	changed.emit()


func _slow_result_context(result: Dictionary) -> Dictionary:
	var key: Vector2i = result["key"]
	var context: Dictionary = {"key": [key.x, key.y], "kind": str(result["kind"])}
	if result.has("_slow_worker"):
		var timing: Dictionary = result["_slow_worker"]
		context["job_id"] = timing["job_id"]
		context["dispatch_frame"] = timing["dispatch_frame"]
		context["worker_start_usec"] = timing["start_usec"]
		context["worker_end_usec"] = timing["end_usec"]
	return context


func _upload_patch(result: Dictionary) -> MeshInstance3D:
	var start: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result["arrays"])
	var uploaded_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	var tile: MeshInstance3D = MeshInstance3D.new()
	var kind: String = str(result["kind"])
	var key: Vector2i = result["key"]
	tile.name = "Training_%s_%d_%d" % [kind, key.x, key.y]
	tile.mesh = mesh
	tile.material_override = _region_material if kind == "region" else _native_material
	tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.set_meta("kind", kind)
	tile.set_meta("key", key)
	tile.set_meta("signature", str(result["signature"]))
	tile.set_meta("lod", int(result["lod"]))
	var before_tree_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	add_child(tile)
	_last_mesh_install_usec = Time.get_ticks_usec() - start
	_max_mesh_install_usec = maxi(_max_mesh_install_usec, _last_mesh_install_usec)
	if _slow_timing_enabled:
		_slow_process_install_usec += _last_mesh_install_usec
		_record_slow_timing("mesh_install", start, start + _last_mesh_install_usec,
			{"mesh_upload": uploaded_usec - start, "node_setup": before_tree_usec - uploaded_usec,
			"tree_registration": start + _last_mesh_install_usec - before_tree_usec}, _slow_result_context(result))
	return tile


func _replace_tile(tile: MeshInstance3D) -> void:
	var key: Vector2i = tile.get_meta("key")
	if str(tile.get_meta("kind")) == "region":
		if _region_tiles.has(key):
			_release_node(_region_tiles[key])
		_region_tiles[key] = tile
	else:
		if _native_tiles.has(key):
			_release_node(_native_tiles[key])
		_native_tiles[key] = tile


func _discard_stage() -> void:
	for tile: MeshInstance3D in _staged_nodes:
		_release_node(tile)
	_staged_nodes = []
	_stage_results = []
	_stage_fine = {}
	_stage_index = 0


func _refresh_visibility() -> void:
	var show_native: bool = _native_requested and _native_active and not _external_native_owner
	for key: Vector2i in _region_tiles:
		_region_tiles[key].visible = not (key == Vector2i(4, 4) and (show_native or _external_native_owner))
	for tile: MeshInstance3D in _native_tiles.values():
		tile.visible = show_native


func _install_collision(result: Dictionary) -> void:
	var key: Vector2i = result["key"]
	if _collision_tiles.has(key):
		return
	var start: int = Time.get_ticks_usec()
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	var created_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	shape.set_faces(result["faces"])
	var faces_done_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TrainingLocalGround_%d_%d" % [key.x, key.y]
	body.collision_layer = _collision_layer
	body.collision_mask = 0
	body.set_meta("training_only", true)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var before_bind_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	collider.shape = shape
	body.add_child(collider)
	var before_space_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	add_child(body)
	var after_space_usec: int = Time.get_ticks_usec() if _slow_timing_enabled else 0
	_collision_tiles[key] = body
	_last_shape_install_usec = Time.get_ticks_usec() - start
	_max_shape_install_usec = maxi(_max_shape_install_usec, _last_shape_install_usec)
	if _slow_timing_enabled:
		_slow_process_install_usec += _last_shape_install_usec
		_record_slow_timing("shape_install", start, start + _last_shape_install_usec, {
			"shape_create": created_usec - start, "shape_set_faces": faces_done_usec - created_usec,
			"node_create": before_bind_usec - faces_done_usec, "shape_bind": before_space_usec - before_bind_usec,
			"space_registration": after_space_usec - before_space_usec,
			"other_main_update": start + _last_shape_install_usec - after_space_usec}, _slow_result_context(result))


func _collision_keys(point: Vector2) -> Array[Vector2i]:
	var first: Vector2i = _collision_key(point - Vector2(COLLISION_MARGIN, COLLISION_MARGIN))
	var last: Vector2i = _collision_key(point + Vector2(COLLISION_MARGIN, COLLISION_MARGIN))
	var keys: Array[Vector2i] = []
	for row: int in range(first.y, last.y + 1):
		for column: int in range(first.x, last.x + 1):
			keys.append(Vector2i(column, row))
	return keys


func _collision_key(point: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((point.x + 2500.0) / COLLISION_SIZE), 0, 49), clampi(floori((point.y + 2500.0) / COLLISION_SIZE), 0, 49))


func _clear_collision() -> void:
	for body: StaticBody3D in _collision_tiles.values():
		_release_node(body)
	_collision_tiles.clear()


func _launch(kind: String, callable: Callable) -> void:
	_worker = Thread.new()
	_worker_kind = kind
	var task: Callable = callable
	if _slow_timing_enabled:
		_slow_job_id += 1
		var context: Dictionary = {"job_id": _slow_job_id, "job_kind": kind,
			"dispatch_frame": Engine.get_process_frames(), "dispatch_physics_frame": Engine.get_physics_frames(),
			"dispatch_usec": Time.get_ticks_usec()}
		task = HeightSource.run_timed_job.bind(callable, context)
	var error: Error = _worker.start(task)
	if error != OK:
		_worker = null
		_started = false
		failed.emit("无法启动训练地形后台任务：" + kind)


func _nearest_missing(tiles: Dictionary, count: int, size_m: float, origin: float) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var distance: float = INF
	for row: int in count:
		for column: int in count:
			var key: Vector2i = Vector2i(column, row)
			if tiles.has(key):
				continue
			var midpoint: Vector2 = Vector2(origin, origin) + (Vector2(key) + Vector2(0.5, 0.5)) * size_m
			var candidate: float = midpoint.distance_squared_to(_center)
			if candidate < distance:
				distance = candidate
				best = key
	return best


func _mark_prepared() -> void:
	if not _prepared:
		_prepared = true
		prepared.emit()


func _request_textures() -> void:
	var files: Dictionary[String, String] = {
		"region_color": "continuous/assets/region_color.png", "region_normal": "continuous/assets/region_normal.png",
		"land_color": "ridgevale/assets/land_color.png", "land_control": "ridgevale/assets/land_control.png",
		"grass_detail": "cedar/assets/grass_detail.png", "soil_detail": "cedar/assets/soil_detail.png", "stone_detail": "cedar/assets/stone_detail.png",
	}
	for parameter: String in files:
		var path: String = _base_path + files[parameter]
		if not ResourceLoader.exists(path, "Texture2D"):
			_resource_notes.append("缺少可选表层纹理：" + files[parameter])
			continue
		var error: Error = ResourceLoader.load_threaded_request(path, "Texture2D")
		if error == OK:
			_texture_requests[path] = parameter
		else:
			_resource_notes.append("无法请求表层纹理：" + files[parameter])


func _poll_one_texture() -> void:
	for path: String in _texture_requests.keys():
		var state: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var parameter: String = _texture_requests[path]
		_texture_requests.erase(path)
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			var texture: Texture2D = ResourceLoader.load_threaded_get(path) as Texture2D
			if texture != null:
				_loaded_textures[parameter] = texture
				for index: int in range(_surface_materials.size() - 1, -1, -1):
					var material: ShaderMaterial = _surface_materials[index].get_ref() as ShaderMaterial
					if material == null:
						_surface_materials.remove_at(index)
					else:
						material.set_shader_parameter(parameter, texture)
						material.set_shader_parameter("has_" + parameter, true)
		else:
			_resource_notes.append("表层纹理读取失败：" + path)
		changed.emit()
		break


func _clamp_center(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, REGION_MIN, REGION_MAX), clampf(point.y, REGION_MIN, REGION_MAX))


func _native_key(point: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((point.x + 2500.0) / 500.0), 0, 9), clampi(floori((point.y + 2500.0) / 500.0), 0, 9))


func _release_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()
