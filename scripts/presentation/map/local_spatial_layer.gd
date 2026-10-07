class_name LocalSpatialLayer
extends RefCounted
## Prepared line meshes and glyphs on the existing regional canvas.

const PREPARE_BUDGET_USEC: int = 2000
const DRAW_ORDER: int = 100000
const COLORS: Dictionary = {"rail": Color(0.78, 0.69, 0.48, 0.90), "river": Color(0.32, 0.65, 0.80, 0.94), "coast": Color(0.40, 0.74, 0.88, 0.96), "lake": Color(0.15, 0.36, 0.48, 1.0)}
const WIDTHS: Dictionary = {"rail": 2.4, "river": 2.1, "coast": 1.8}
const LODS: Array[String] = ["coarse", "medium", "local"]
var residency_policy: String = "active"
var rail_style: int = 2
var ready: bool = false
var preparing: bool = false
var metrics: Dictionary = {}
var visible_places: Dictionary = {}
var label_rects: Array[Rect2] = []
var available_lods: Dictionary = {}
var active_lod: String = ""
var prepare_count: int = 0
var _chunks: Array[Dictionary] = []
var _lod_thread: Thread
var _batches: Array[Dictionary] = []
var _places: Dictionary = {}
var _labels: Array[Dictionary] = []
var _content: LocalSpatialContent
var _cursor: int = 0
var _label_cursor: int = 0
var _shader: Shader
var _canvas: RID
var _frame := Basis()
var _started: int = 0
var _first_visible: bool = false
var _wanted: Array[String] = []
var _cpu_ready: Dictionary = {}
var _upload_chunks: Array[Dictionary] = []
var _resident: bool = false
var _target: String = "coarse"
var strategic: bool = false
var suppressed_places: Dictionary = {}
var paris_mask_weights: Dictionary = {}

func _lod(mpp: float) -> String:
	var value := MapScaleStyle.lod(mpp)
	return "medium" if strategic and value == "local" else value

func begin(content: LocalSpatialContent, canvas: RID) -> void:
	clear()
	_content = content
	strategic = str(content.metadata.get("content_level", "")) == "strategic"
	prepare_count += 1
	_canvas = canvas
	_shader = load("res://shaders/presentation/map/globe_boundary.gdshader") as Shader
	_started = Time.get_ticks_usec()
	metrics = content.metrics.duplicate()
	metrics.merge({"gpu_enqueue_usec": 0, "label_prepare_usec": 0, "max_prepare_step_usec": 0, "upload_bytes_estimate": 0, "lod_stats":{}, "lod_prepare_usec":0, "lod_upload_counts":{}, "release_count":0})
	for feature: Dictionary in content.features:
		if str(feature.kind) == "settlement":
			_places[str(feature.id)] = feature
			_labels.append({"feature": feature, "item": RID(), "km": Vector2.ZERO})
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.feature.rank) < int(b.feature.rank))
	_cursor = 0
	_label_cursor = 0
	request_lods(4500.0)

func request_lods(mpp: float) -> void:
	if _content == null:
		return
	var old_wanted := _wanted.duplicate()
	var was_resident := _resident
	_resident = true
	_target = _lod(mpp)
	_wanted.assign([_target])
	if residency_policy == "all":
		_wanted.assign(LODS)
	elif residency_policy == "adjacent":
		if _target == "coarse" and mpp <= 2600.0: _wanted.append("medium")
		elif _target == "medium": _wanted.append("coarse" if mpp > 400.0 else "local")
		elif _target == "local": _wanted.append("medium")
	if was_resident and old_wanted == _wanted:
		return
	_queue_preparation()
	_trim_gpu()

func _queue_preparation() -> void:
	if not _resident or _lod_thread != null or _cursor < _upload_chunks.size():
		return
	var missing: Array[String] = []
	for lod_name: String in _wanted:
		if not _cpu_ready.has(lod_name): missing.append(lod_name)
	if not missing.is_empty():
		_lod_thread = Thread.new()
		_lod_thread.start(LocalSpatialLod.prepare.bind(_content.line_chunks,missing))
		preparing = true
		return
	_upload_chunks.clear()
	_cursor = 0
	for chunk: Dictionary in _chunks:
		if str(chunk.lod) in _wanted and not available_lods.has(str(chunk.lod)):
			_upload_chunks.append(chunk)
	preparing = _cursor < _upload_chunks.size() or _label_cursor < _labels.size()
	ready = available_lods.has(_target)

func _trim_gpu() -> void:
	# Keep the old displayed batch until the requested replacement is complete.
	var fallback := active_lod
	if not available_lods.has(fallback) and not available_lods.is_empty():
		fallback = str(available_lods.keys()[0])
	var pending := str(_upload_chunks[_cursor].lod) if _cursor < _upload_chunks.size() else ""
	for index: int in range(_batches.size()-1,-1,-1):
		var batch := _batches[index]
		var protected := not available_lods.has(_target) and str(batch.lod)==fallback
		if str(batch.lod) not in _wanted and str(batch.lod)!=pending and not protected:
			RenderingServer.free_rid(batch.item as RID)
			available_lods.erase(str(batch.lod))
			_batches.remove_at(index)
	metrics["resident_lods"] = available_lods.keys()
	metrics["resident_gpu_buffer_bytes"] = resident_buffer_bytes()

func resident_buffer_bytes() -> int:
	var bytes: int = 0
	for batch: Dictionary in _batches:
		if bool(batch.get("water", false)):
			var geometry := batch.geometry as GlobeSurfaceBatch
			bytes += int(batch.faces) * (12*8+24*4) + geometry.data.get_width()*geometry.data.get_height()*16
		else:
			var geometry := batch.geometry as GlobeBoundaryBatch
			bytes += geometry.segment_count * (16*8+54*4) + geometry.data.get_width()*geometry.data.get_height()*16
	return bytes

func release_gpu() -> void:
	if not _resident: return
	_resident = false
	for batch: Dictionary in _batches: RenderingServer.free_rid(batch.item as RID)
	_batches.clear()
	for label: Dictionary in _labels:
		if (label.item as RID).is_valid(): RenderingServer.free_rid(label.item as RID)
		label.item = RID()
	_label_cursor = 0
	_upload_chunks.clear()
	_cursor = 0
	available_lods.clear()
	active_lod = ""
	visible_places.clear()
	label_rects.clear()
	ready = false
	preparing = _lod_thread != null
	metrics["release_count"] = int(metrics.get("release_count",0))+1
	metrics["resident_lods"] = []
	metrics["resident_gpu_buffer_bytes"] = 0

func prepare_step(font: Font) -> void:
	var step_started := Time.get_ticks_usec()
	if _lod_thread != null:
		if _lod_thread.is_alive():
			return
		var prepared := _lod_thread.wait_to_finish() as Dictionary
		_lod_thread = null
		_chunks.append_array(prepared.chunks as Array[Dictionary])
		(metrics.lod_stats as Dictionary).merge(prepared.lod_stats)
		metrics.lod_prepare_usec += prepared.lod_prepare_usec
		for name: String in prepared.lod_stats: _cpu_ready[name] = true
		_queue_preparation()
		if _lod_thread != null:
			return
	if not _resident:
		preparing = false
		return
	if not _prepare_labels(font, step_started):
		return
	while _cursor < _upload_chunks.size():
		var started := Time.get_ticks_usec()
		var line := _upload_chunks[_cursor]
		var geometry: RefCounted
		var water := line.has("faces")
		var geometry_bytes: int = 0
		var mesh: ArrayMesh
		var texture: ImageTexture
		if water:
			var surfaces := GlobeSurfaceBatch.new()
			surfaces.prepare(line.faces as Array)
			geometry = surfaces
			mesh = surfaces.mesh
			texture = surfaces.data
			geometry_bytes = (line.faces as Array).size() * (12*8+24*4)
		else:
			var boundaries: Array[Dictionary] = []
			boundaries.assign(line.boundaries as Array)
			var strokes := GlobeBoundaryBatch.new()
			strokes.prepare(boundaries, str(line.kind))
			geometry = strokes
			mesh = strokes.mesh
			texture = strokes.data
			geometry_bytes = strokes.segment_count * (16*8+54*4)
		if texture == null or mesh.get_surface_count() == 0:
			_cursor += 1
			continue
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/presentation/map/globe_water_surface.gdshader") as Shader if water else _shader
		material.set_shader_parameter("region_mode", true)
		material.set_shader_parameter("face_data" if water else "line_data", texture)
		if water:
			material.set_shader_parameter("water_color", COLORS.lake)
		else:
			material.set_shader_parameter("stroke_color", COLORS[str(line.kind)])
			material.set_shader_parameter("stroke_width", WIDTHS[str(line.kind)])
			material.set_shader_parameter("rail_style", rail_style if str(line.kind)=="rail" else 0)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, _canvas)
		RenderingServer.canvas_item_set_draw_index(item, DRAW_ORDER)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		RenderingServer.canvas_item_add_mesh(item, mesh.get_rid())
		RenderingServer.canvas_item_set_visible(item, false)
		var buffer_bytes := geometry_bytes + texture.get_width() * texture.get_height() * 16 if texture != null else 0
		_batches.append({"item": item, "material": material, "geometry": geometry, "lod":line.lod, "kind":line.kind, "visible":false, "water": water, "faces": (line.get("faces", []) as Array).size()})
		_cursor += 1
		metrics.gpu_enqueue_usec += Time.get_ticks_usec() - started
		metrics.upload_bytes_estimate += buffer_bytes
		var stats := (metrics.lod_stats as Dictionary)[str(line.lod)] as Dictionary
		stats["gpu_buffer_bytes"] = int(stats.get("gpu_buffer_bytes", 0)) + buffer_bytes
		if _cursor == _upload_chunks.size() or str(_upload_chunks[_cursor].lod) != str(line.lod):
			available_lods[str(line.lod)] = true
			metrics[str(line.lod) + "_ready_since_load_usec"] = Time.get_ticks_usec() - int(metrics.load_started_usec)
			var counts := metrics.lod_upload_counts as Dictionary
			counts[str(line.lod)] = int(counts.get(str(line.lod),0))+1
			ready = available_lods.has(_target)
			_trim_gpu()
		if _cursor < _upload_chunks.size() and Time.get_ticks_usec() - step_started >= PREPARE_BUDGET_USEC:
			metrics.max_prepare_step_usec = maxi(int(metrics.max_prepare_step_usec), Time.get_ticks_usec() - step_started)
			return
	metrics.max_prepare_step_usec = maxi(int(metrics.max_prepare_step_usec), Time.get_ticks_usec() - step_started)
	metrics.prepare_elapsed_usec = Time.get_ticks_usec() - _started
	if not metrics.has("ready_since_load_usec"):
		metrics.ready_since_load_usec = Time.get_ticks_usec() - int(metrics.load_started_usec)
	preparing = false
	_queue_preparation()
	_trim_gpu()

func _prepare_labels(font: Font, step_started: int) -> bool:
	while _label_cursor < _labels.size():
		var started := Time.get_ticks_usec()
		var label := _labels[_label_cursor]
		var feature := label.feature as Dictionary
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, _canvas)
		RenderingServer.canvas_item_set_draw_index(item, DRAW_ORDER + 1)
		font.draw_string(item, Vector2(7.0, -6.0), str(feature.display_name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.94, 0.93, 0.82))
		RenderingServer.canvas_item_set_visible(item, false)
		label["item"] = item
		label["text_size"] = font.get_string_size(str(feature.display_name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11)
		_label_cursor += 1
		metrics.label_prepare_usec += Time.get_ticks_usec() - started
		if Time.get_ticks_usec() - step_started >= PREPARE_BUDGET_USEC:
			metrics.max_prepare_step_usec = maxi(int(metrics.max_prepare_step_usec), Time.get_ticks_usec() - step_started)
			return false
	return true

func content_reference() -> LocalSpatialContent:
	return _content

func place(id: String) -> Dictionary:
	return _places.get(id, {}) as Dictionary

func update(camera: RegionCamera, controller: GlobeController, date: String, viewport_size: Vector2) -> void:
	var show := _resident and _content != null and not available_lods.is_empty() and camera.active and _content.active_on(date) and (not camera.local_active if strategic else LocalSpatialLoader.covers(RegionProjection.lon_lat(camera.unit_at(viewport_size * 0.5))))
	var mpp := camera.km_per_pixel * 1000.0
	active_lod = _lod(mpp) if show else ""
	if show and not available_lods.has(active_lod):
		active_lod = str(available_lods.keys()[0])
	visible_places.clear()
	label_rects.clear()
	var visible_line := false
	for batch: Dictionary in _batches:
		var weight := MapScaleStyle.strategic_weight(str(batch.kind), mpp) if strategic else MapScaleStyle.physical_weight(str(batch.kind), mpp)
		var visible := show and str(batch.lod) == active_lod and weight > 0.001
		if visible != bool(batch.visible):
			RenderingServer.canvas_item_set_visible(batch.item as RID, visible)
			batch.visible = visible
		if visible:
			visible_line = true
			var material := batch.material as ShaderMaterial
			var color := COLORS[str(batch.kind)] as Color
			color.a *= weight
			GlobeRenderer._parameter(batch, "water_color" if bool(batch.water) else "stroke_color", color)
			if not bool(batch.water): GlobeRenderer._parameter(batch, "rail_style", rail_style if str(batch.kind)=="rail" else 0)
			if strategic: GlobeRenderer._parameter(batch, "paris_mask_weight", float(paris_mask_weights.get(str(batch.kind), 0.0)))
			GlobeRenderer._parameter(batch, "globe_basis", camera.tangent_frame.transposed())
			GlobeRenderer._parameter(batch, "globe_center", camera.origin)
			GlobeRenderer._parameter(batch, "region_km_per_pixel", camera.km_per_pixel)
			GlobeRenderer._parameter(batch, "region_bearing", Vector2(cos(camera.bearing), sin(camera.bearing)))
			GlobeRenderer._bounds(batch,viewport_size)
	var changed_frame := _frame != camera.tangent_frame
	if show:
		_frame = camera.tangent_frame
	var occupied: Array[Rect2] = []
	var axes := RegionProjection.screen_axes(camera.bearing)
	for label: Dictionary in _labels:
		if not (label.item as RID).is_valid():
			continue
		RenderingServer.canvas_item_set_visible(label.item as RID, false)
		if not show:
			continue
		var feature := label.feature as Dictionary
		if suppressed_places.has(str(feature.id)):
			continue
		if date < str(feature.valid_from) or date >= str(feature.valid_to):
			continue
		if changed_frame:
			var coordinates := feature.geometry.coordinates as Array
			label.km = RegionProjection.forward(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]), float(coordinates[1]))), _frame)
		var selected := str(feature.id) == controller.selected_place_id
		var limit := float(feature.get("max_mpp", 0.0)) if strategic else MapScaleStyle.settlement_limit(int(feature.rank), str(feature.id))
		if mpp > limit and not selected:
			continue
		var point := camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel)
		if not Rect2(Vector2.ZERO, viewport_size).has_point(point):
			continue
		visible_places[str(feature.id)] = point
		if not controller.labels_enabled and not selected:
			continue
		var rect := Rect2(point + Vector2(7.0, -17.0), label.text_size as Vector2)
		var overlaps := false
		for other: Rect2 in occupied:
			overlaps = overlaps or other.intersects(rect.grow(3.0))
		if overlaps and not selected:
			continue
		occupied.append(rect)
		label_rects.append(rect)
		RenderingServer.canvas_item_set_transform(label.item as RID, Transform2D(0.0, point))
		RenderingServer.canvas_item_set_visible(label.item as RID, true)
	if visible_line and not _first_visible:
		_first_visible = true
		_mark_first_frame.call_deferred()

func _mark_first_frame() -> void:
	await RenderingServer.frame_post_draw
	metrics["first_visible_frame_since_prepare_usec"] = Time.get_ticks_usec() - _started
	metrics["first_visible_frame_since_load_usec"] = Time.get_ticks_usec() - int(metrics.load_started_usec)

func clear() -> void:
	if _lod_thread != null:
		_lod_thread.wait_to_finish()
		_lod_thread = null
	for batch: Dictionary in _batches:
		RenderingServer.free_rid(batch.item as RID)
	for label: Dictionary in _labels:
		if (label.item as RID).is_valid():
			RenderingServer.free_rid(label.item as RID)
	_batches.clear()
	_chunks.clear()
	_upload_chunks.clear()
	_cpu_ready.clear()
	_wanted.clear()
	_resident = false
	available_lods.clear()
	active_lod = ""
	_labels.clear()
	_places.clear()
	visible_places.clear()
	label_rects.clear()
	ready = false
	preparing = false
	_first_visible = false
	_frame = Basis()
	_content = null
