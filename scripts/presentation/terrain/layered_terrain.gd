extends Node3D
## Read-only fictional training scenery embedded in the existing formal-world host.
## No WorldState, clock, actors, military/economic commands or persistence live here.
## Coordinates are local metres, not geographic registration to the selected place.
## One worker job and at most one mesh installation per frame; caches have fixed caps.
signal prepared
signal changed
signal failed(message: String)

const HeightSource: GDScript = preload("res://scripts/presentation/terrain/terrain_height_source.gd")
const GroundShader: Shader = preload("res://shaders/presentation/terrain/layered_ground.gdshader")
const DEFAULT_BASE_PATH: String = "res://assets/terrain/region_slice/"
const REGION_MIN: float = -22500.0
const REGION_MAX: float = 27500.0
const REGION_TILE_SIZE: float = 5000.0
const REGION_TILE_COUNT: int = 10
const REGION_CELLS: int = 20
const NATIVE_HALF: float = 2500.0
const NATIVE_TILE_SIZE: float = 500.0
const NATIVE_TILE_COUNT: int = 10
const NATIVE_CELLS: int = 125
const NATIVE_VIEW_LIMIT: float = 8500.0
const DETAIL_VIEW_LIMIT: float = 1800.0
const MAX_DETAIL_TILES: int = 9
const NO_TILE: Vector2i = Vector2i(-999, -999)

var training_only: bool = true
var _base_path: String = DEFAULT_BASE_PATH
var _center: Vector2 = Vector2.ZERO
var _span: float = 50000.0
var _started: bool = false
var _prepared: bool = false
var _data_ready: bool = false
var _native_requested: bool = false
var _native_focus: Vector2i = NO_TILE
var _region_focus: Vector2i = NO_TILE
var _region_heights: PackedFloat32Array = PackedFloat32Array()
var _native_heights: PackedFloat32Array = PackedFloat32Array()
var _region_tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _detail_tiles: Dictionary[Vector2i, MeshInstance3D] = {}
var _detail_targets: Dictionary[Vector2i, bool] = {}
var _native_overview: MeshInstance3D
var _region_material: ShaderMaterial
var _overview_material: ShaderMaterial
var _detail_material: ShaderMaterial
var _coverage_image: Image
var _coverage_texture: ImageTexture
var _queue: Array[Dictionary] = []
var _worker: Thread
var _worker_kind: String = ""
var _worker_description: Dictionary = {}
var _texture_requests: Dictionary[String, String] = {}
var _resource_notes: PackedStringArray = PackedStringArray()
var _collision_enabled: bool = true
var _collision_layer: int = 1
# At most four 500m tiles cover the local +/-64m safety square.
const COLLISION_MARGIN: float = 64.0
var _collision_tiles: Dictionary[Vector2i, StaticBody3D] = {}


func begin(config: Dictionary) -> void:
	close()
	if config.get("training_only", true) != true:
		failed.emit("此组件只允许 training_only 观察，不能作为正式地理或军事世界")
		return
	_base_path = str(config.get("base_path", DEFAULT_BASE_PATH)).strip_edges()
	if not _base_path.begins_with("res://"):
		failed.emit("训练地形 base_path 必须是项目内 res:// 资源路径")
		return
	if not _base_path.ends_with("/"):
		_base_path += "/"
	training_only = true
	_center = Vector2.ZERO
	_span = 50000.0
	var configured_center: Variant = config.get("center", Vector2.ZERO)
	if configured_center is Vector2:
		var point: Vector2 = configured_center
		if point.is_finite():
			_center = _clamp_center(point)
	var configured_span: Variant = config.get("span_m", 50000.0)
	if configured_span is float or configured_span is int:
		var value: float = float(configured_span)
		if is_finite(value):
			_span = clampf(value, 50.0, 75000.0)
	_collision_enabled = bool(config.get("collision_enabled", true))
	_collision_layer = clampi(int(config.get("collision_layer", 1)), 1, 2147483647)
	_started = true
	set_meta("training_only", true)
	set_meta("geographically_registered", false)
	_create_materials()
	_request_textures()
	_worker = Thread.new()
	_worker_kind = "sources"
	var error: Error = _worker.start(HeightSource.read_sources.bind(_base_path))
	if error != OK:
		_worker = null
		_started = false
		failed.emit("无法启动训练高度源读取")
		return
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
	if _data_ready:
		_refresh_targets()


func sample_height(x: float, z: float) -> float:
	if not _data_ready or not is_finite(x) or not is_finite(z):
		return NAN
	if not _native_heights.is_empty() and absf(x) <= NATIVE_HALF and absf(z) <= NATIVE_HALF:
		return HeightSource.sample(_native_heights, 1251, -2500.0, 4.0, x, z)
	return HeightSource.sample(_region_heights, 1001, REGION_MIN, 50.0, x, z)


func is_ready() -> bool:
	# Ready means a real source-backed patch is installed, not all queued tiles.
	return _prepared


func is_collision_ready(position: Vector3) -> bool:
	# Local coordinates. The whole safety square must exist, not merely a visual.
	if not _data_ready or not _native_requested or not _collision_enabled or not position.is_finite():
		return false
	if absf(position.x) > NATIVE_HALF or absf(position.z) > NATIVE_HALF:
		return false
	var keys: Array[Vector2i] = _collision_keys(Vector2(position.x, position.z))
	for key: Vector2i in keys:
		if not _collision_tiles.has(key) or not is_instance_valid(_collision_tiles[key]):
			return false
	return not keys.is_empty()


func get_status() -> Dictionary:
	# Small local presentation state only; never a world snapshot.
	return {
		"training_only": true,
		"geographically_registered": false,
		"ready": _prepared,
		"native_available": not _native_heights.is_empty(),
		"native_visible": _native_requested and is_instance_valid(_native_overview),
		"region_tiles": _region_tiles.size(),
		"detail_tiles": _detail_tiles.size(),
		"detail_tile_limit": MAX_DETAIL_TILES,
		"queued_tiles": _queue.size(),
		"loading": _worker != null,
		"local_collision_ready": is_collision_ready(Vector3(_center.x, 0.0, _center.y)),
		"collision_tiles": _collision_tiles.size(),
		"resource_notes": _resource_notes.duplicate(),
	}


func close() -> void:
	set_process(false)
	_started = false
	_prepared = false
	_data_ready = false
	_native_requested = false
	_native_focus = NO_TILE
	_region_focus = NO_TILE
	_queue.clear()
	# The single bounded data job owns no nodes. Join before releasing its inputs.
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
	_worker_kind = ""
	_worker_description.clear()
	# Collect requests owned by this component before releasing its texture refs.
	for path: String in _texture_requests:
		var state: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_LOADED or state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(path)
	_texture_requests.clear()
	for tile: MeshInstance3D in _region_tiles.values():
		_release_node(tile)
	for tile: MeshInstance3D in _detail_tiles.values():
		_release_node(tile)
	_region_tiles.clear()
	_detail_tiles.clear()
	_detail_targets.clear()
	_release_node(_native_overview)
	_native_overview = null
	_clear_collision()
	_region_heights = PackedFloat32Array()
	_native_heights = PackedFloat32Array()
	_region_material = null
	_overview_material = null
	_detail_material = null
	_coverage_image = null
	_coverage_texture = null
	_resource_notes = PackedStringArray()


func _exit_tree() -> void:
	close()


func _process(_delta: float) -> void:
	if not _started:
		return
	_poll_one_texture()
	if _worker != null and not _worker.is_alive():
		var result: Variant = _worker.wait_to_finish()
		var kind: String = _worker_kind
		_worker = null
		_worker_kind = ""
		_worker_description.clear()
		if result is Dictionary:
			var document: Dictionary = result
			if kind == "sources":
				_accept_sources(document)
			else:
				_install_patch(document)
		else:
			failed.emit("训练地形工作线程未返回有效数据")
	if not _started:
		return
	_sync_local_collision()
	if _worker == null and _data_ready and not _queue.is_empty():
		_start_next_patch()


func _accept_sources(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_started = false
		set_process(false)
		failed.emit(str(result.get("error", "50km 训练高度源无法读取")))
		return
	_region_heights = result["region"]
	_native_heights = result["native"]
	_data_ready = true
	var native_error: String = str(result.get("native_error", ""))
	if not native_error.is_empty():
		# Missing native data does not block the independently valid 50km view.
		_resource_notes.append("5km 细图不可用：" + native_error)
	_refresh_targets()
	changed.emit()


func _refresh_targets() -> void:
	var wants_native: bool = not _native_heights.is_empty() and _span < NATIVE_VIEW_LIMIT and absf(_center.x) <= NATIVE_HALF + _span * 0.5 and absf(_center.y) <= NATIVE_HALF + _span * 0.5
	var wants_detail: bool = wants_native and _span < DETAIL_VIEW_LIMIT
	var next_native: Vector2i = _native_key(_center) if wants_detail else NO_TILE
	var next_region: Vector2i = Vector2i(floori((_center.x - REGION_MIN) / REGION_TILE_SIZE), floori((_center.y - REGION_MIN) / REGION_TILE_SIZE))
	# Walking camera motion inside a tile does not recopy/sort the render cache.
	# Its small collision safety square is checked independently each frame.
	if wants_native == _native_requested and next_native == _native_focus and next_region == _region_focus:
		return
	_native_requested = wants_native
	_native_focus = next_native
	_region_focus = next_region
	_detail_targets.clear()
	if wants_detail:
		for row: int in range(maxi(0, _native_focus.y - 1), mini(NATIVE_TILE_COUNT, _native_focus.y + 2)):
			for column: int in range(maxi(0, _native_focus.x - 1), mini(NATIVE_TILE_COUNT, _native_focus.x + 2)):
				_detail_targets[Vector2i(column, row)] = true
	for key: Vector2i in _collision_tiles.keys():
		if not _detail_targets.has(key):
			_release_node(_collision_tiles[key])
			_collision_tiles.erase(key)
	for key: Vector2i in _detail_tiles.keys():
		if not _detail_targets.has(key):
			_release_node(_detail_tiles[key])
			_detail_tiles.erase(key)
	_refresh_coverage()
	_refresh_visibility()
	_rebuild_queue()
	changed.emit()


func _rebuild_queue() -> void:
	_queue.clear()
	if _native_requested and not is_instance_valid(_native_overview):
		_queue.append({"kind": "overview", "key": Vector2i.ZERO})
	var detail_keys: Array[Vector2i] = []
	for key: Vector2i in _detail_targets:
		if not _detail_tiles.has(key):
			detail_keys.append(key)
	detail_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _detail_distance(a) < _detail_distance(b))
	for key: Vector2i in detail_keys:
		_queue.append({"kind": "detail", "key": key})
	var region_keys: Array[Vector2i] = []
	for row: int in REGION_TILE_COUNT:
		for column: int in REGION_TILE_COUNT:
			var key: Vector2i = Vector2i(column, row)
			if not _region_tiles.has(key):
				region_keys.append(key)
	region_keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _region_distance(a) < _region_distance(b))
	for key: Vector2i in region_keys:
		_queue.append({"kind": "region", "key": key})
	if not _worker_description.is_empty():
		for index: int in range(_queue.size() - 1, -1, -1):
			if _queue[index] == _worker_description:
				_queue.remove_at(index)


func _start_next_patch() -> void:
	var description: Dictionary = _queue.pop_front()
	var kind: String = str(description["kind"])
	var key: Vector2i = description["key"]
	var job: Dictionary = {"kind": kind, "key": key}
	if kind == "region":
		job.merge({
			"heights": _region_heights, "width": 1001,
			"source_origin": REGION_MIN, "source_step": 50.0,
			"origin": Vector2(REGION_MIN + key.x * REGION_TILE_SIZE, REGION_MIN + key.y * REGION_TILE_SIZE),
			"cells": REGION_CELLS, "step": 250.0,
		})
	else:
		job.merge({"heights": _native_heights, "width": 1251, "source_origin": -2500.0, "source_step": 4.0})
		if kind == "overview":
			job.merge({"origin": Vector2(-NATIVE_HALF, -NATIVE_HALF), "cells": 250, "step": 20.0, "skirt": 30.0})
		else:
			job.merge({
				"origin": Vector2(-NATIVE_HALF + key.x * NATIVE_TILE_SIZE, -NATIVE_HALF + key.y * NATIVE_TILE_SIZE),
				"cells": NATIVE_CELLS, "step": 4.0, "skirt": 12.0,
			})
	_worker = Thread.new()
	_worker_kind = "mesh"
	_worker_description = description
	var error: Error = _worker.start(HeightSource.build_patch.bind(job))
	if error != OK:
		_worker = null
		_worker_description.clear()
		_started = false
		set_process(false)
		failed.emit("无法启动训练地形分块构建")


func _install_patch(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		failed.emit(str(result.get("error", "训练地形分块构建失败")))
		return false
	var kind: String = str(result["kind"])
	var key: Vector2i = result["key"]
	if kind == "detail" and (not _detail_targets.has(key) or _detail_tiles.has(key)):
		return false
	if kind == "overview" and (not _native_requested or is_instance_valid(_native_overview)):
		return false
	if kind == "region" and _region_tiles.has(key):
		return false
	var arrays: Array = result["arrays"]
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tile: MeshInstance3D = MeshInstance3D.new()
	tile.name = "Training_%s_%d_%d" % [kind, key.x, key.y]
	tile.mesh = mesh
	tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == "region":
		tile.material_override = _region_material
		_region_tiles[key] = tile
	elif kind == "overview":
		tile.material_override = _overview_material
		_native_overview = tile
	else:
		tile.material_override = _detail_material
		_detail_tiles[key] = tile
	add_child(tile)
	_set_material_transforms()
	_refresh_coverage()
	_refresh_visibility()
	if not _prepared:
		_prepared = true
		prepared.emit()
	changed.emit()
	return true


func _create_materials() -> void:
	_coverage_image = Image.create(NATIVE_TILE_COUNT, NATIVE_TILE_COUNT, false, Image.FORMAT_R8)
	_coverage_image.fill(Color.BLACK)
	_coverage_texture = ImageTexture.create_from_image(_coverage_image)
	_region_material = ShaderMaterial.new()
	_region_material.shader = GroundShader
	_overview_material = ShaderMaterial.new()
	_overview_material.shader = GroundShader
	_overview_material.set_shader_parameter("native_surface", true)
	_overview_material.set_shader_parameter("native_overview", true)
	_overview_material.set_shader_parameter("detail_coverage", _coverage_texture)
	_detail_material = ShaderMaterial.new()
	_detail_material.shader = GroundShader
	_detail_material.set_shader_parameter("native_surface", true)
	for material: ShaderMaterial in [_region_material, _overview_material, _detail_material]:
		# Linear reflectance palette. Source control/low-frequency layout is retained.
		material.set_shader_parameter("grass_color", Vector3(0.085, 0.160, 0.035))
		material.set_shader_parameter("soil_color", Vector3(0.160, 0.090, 0.035))
		material.set_shader_parameter("rock_color", Vector3(0.220, 0.230, 0.215))
		material.set_shader_parameter("field_color", Vector3(0.190, 0.155, 0.050))
		material.set_shader_parameter("macro_contrast", 2.8)
		material.set_shader_parameter("normal_relief", 1.6)
		material.set_shader_parameter("detail_scale", 0.32)
		material.set_shader_parameter("detail_contrast", 2.2)
		material.set_shader_parameter("detail_bump_metres", 0.018)
	# Regional slopes are genuinely shallow. Emphasize their SOURCE normal only;
	# never exaggerate physical vertex height or change grounding/collision.
	_region_material.set_shader_parameter("normal_relief", 5.0)
	_region_material.set_shader_parameter("hillshade_strength", 0.38)
	_region_material.set_shader_parameter("macro_contrast", 3.4)
	_set_material_transforms()


func _set_material_transforms() -> void:
	for material: ShaderMaterial in [_region_material, _overview_material, _detail_material]:
		if material != null:
			material.set_shader_parameter("terrain_to_local", global_transform.affine_inverse())
			material.set_shader_parameter("terrain_to_world", global_transform)


func _request_textures() -> void:
	var files: Dictionary[String, String] = {
		"region_color": "continuous/assets/region_color.png",
		"region_normal": "continuous/assets/region_normal.png",
		"land_color": "ridgevale/assets/land_color.png",
		"land_control": "ridgevale/assets/land_control.png",
		"grass_detail": "cedar/assets/grass_detail.png",
		"soil_detail": "cedar/assets/soil_detail.png",
		"stone_detail": "cedar/assets/stone_detail.png",
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
				for material: ShaderMaterial in [_region_material, _overview_material, _detail_material]:
					material.set_shader_parameter(parameter, texture)
					material.set_shader_parameter("has_" + parameter, true)
			else:
				_resource_notes.append("表层纹理类型无效：" + path)
		else:
			_resource_notes.append("表层纹理读取失败：" + path)
		changed.emit()
		break


func _refresh_coverage() -> void:
	if _coverage_image == null:
		return
	_coverage_image.fill(Color.BLACK)
	if _native_requested:
		for key: Vector2i in _detail_tiles:
			_coverage_image.set_pixel(key.x, key.y, Color.WHITE)
	_coverage_texture.update(_coverage_image)


func _refresh_visibility() -> void:
	var native_visible: bool = _native_requested and is_instance_valid(_native_overview)
	if is_instance_valid(_native_overview):
		_native_overview.visible = native_visible
	for key: Vector2i in _region_tiles:
		_region_tiles[key].visible = not (native_visible and key == Vector2i(4, 4))
	for tile: MeshInstance3D in _detail_tiles.values():
		tile.visible = native_visible


func _sync_local_collision() -> void:
	if not _collision_enabled or _detail_targets.is_empty() or not is_instance_valid(_native_overview):
		_clear_collision()
		return
	if absf(_center.x) > NATIVE_HALF or absf(_center.y) > NATIVE_HALF:
		_clear_collision()
		return
	var required: Array[Vector2i] = _collision_keys(_center)
	for key: Vector2i in _collision_tiles.keys():
		if not required.has(key):
			_release_node(_collision_tiles[key])
			_collision_tiles.erase(key)
	for key: Vector2i in required:
		if _collision_tiles.has(key) or not _detail_tiles.has(key):
			continue
		var mesh: Mesh = _detail_tiles[key].mesh
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "TrainingLocalGround_%d_%d" % [key.x, key.y]
		body.collision_layer = _collision_layer
		body.collision_mask = 0
		body.set_meta("training_only", true)
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = mesh.create_trimesh_shape()
		body.add_child(collider)
		add_child(body)
		_collision_tiles[key] = body
		changed.emit()
		# One local collider per frame, never all 5km collision at once.
		break


func _collision_keys(point: Vector2) -> Array[Vector2i]:
	var first: Vector2i = _native_key(point - Vector2(COLLISION_MARGIN, COLLISION_MARGIN))
	var last: Vector2i = _native_key(point + Vector2(COLLISION_MARGIN, COLLISION_MARGIN))
	var keys: Array[Vector2i] = []
	for row: int in range(first.y, last.y + 1):
		for column: int in range(first.x, last.x + 1):
			keys.append(Vector2i(column, row))
	return keys


func _clear_collision() -> void:
	for body: StaticBody3D in _collision_tiles.values():
		_release_node(body)
	_collision_tiles.clear()


func _clamp_center(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, REGION_MIN, REGION_MAX), clampf(point.y, REGION_MIN, REGION_MAX))


func _native_key(point: Vector2) -> Vector2i:
	return Vector2i(
		clampi(floori((point.x + NATIVE_HALF) / NATIVE_TILE_SIZE), 0, NATIVE_TILE_COUNT - 1),
		clampi(floori((point.y + NATIVE_HALF) / NATIVE_TILE_SIZE), 0, NATIVE_TILE_COUNT - 1)
	)


func _detail_distance(key: Vector2i) -> float:
	var midpoint: Vector2 = Vector2(-NATIVE_HALF, -NATIVE_HALF) + (Vector2(key) + Vector2(0.5, 0.5)) * NATIVE_TILE_SIZE
	return midpoint.distance_squared_to(_center)


func _region_distance(key: Vector2i) -> float:
	var midpoint: Vector2 = Vector2(REGION_MIN, REGION_MIN) + (Vector2(key) + Vector2(0.5, 0.5)) * REGION_TILE_SIZE
	return midpoint.distance_squared_to(_center)


func _release_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() == self:
		remove_child(node)
	node.queue_free()
