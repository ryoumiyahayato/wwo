class_name LocalSpatialLayer
extends RefCounted
signal display_changed
signal preparation_failed(message: String)
## Prepared line meshes and glyphs on the existing regional canvas.

const PREPARE_BUDGET_USEC: int = 2000
const FrameBudget = preload("res://scripts/presentation/map/map_frame_budget.gd")
const MapJobs = preload("res://scripts/presentation/map/map_jobs.gd")
const MAX_STAGED_BYTES: int = 224 * 1024 * 1024
const MAX_GEOMETRY_BYTES: int = 256 * 1024 * 1024
const MAX_RETIRED_BATCHES: int = 2048
var _retiring: Array[Dictionary] = []
var _geometry_bytes: int = 0
const DRAW_ORDER: int = 100000
var rail_style: int = 2
var ready: bool = false
var preparing: bool = false
var preparation_error: String = ""
# Last finite job descriptor only; no geometry, GPU reference or frame log.
var preparation_result: Dictionary = {}
var visible_places: Dictionary = {}
var label_rects: Array[Rect2] = []
var available_lods: Dictionary = {}
var active_lod: String = ""
var _chunks: Array[Dictionary] = []
var _lod_thread: MapJobs.Job
var _lod_generation: int = 0
var _generation: int = 0
var _generation_mutex := Mutex.new()
var _batches: Array[Dictionary] = []
var _fallback_batches: Array[Dictionary] = []
var _fallback_lod: String = ""
var _physical_reference: Dictionary = {}
var observation_hidden_kinds: Array[String] = []
var _places: Dictionary = {}
var _labels: Array[Dictionary] = []
var _content: LocalSpatialContent
var _cursor: int = 0
var _shader: Shader
var _canvas: RID
var _display_canvas := RID()
var _frame := Basis()
var _wanted: Array[String] = []
var _cpu_ready: Dictionary = {}
var _upload_chunks: Array[Dictionary] = []
var _resident: bool = false
var _target: String = "coarse"
var strategic: bool = false
var suppressed_places: Dictionary = {}
var reference_relief: Dictionary = {}
var _reference_window: Dictionary = {}
var _reference_revision: int = 0
var _ink_frames: Dictionary = {}
var _political_cells: Dictionary = {}
var _installed_political_cells: Dictionary = {}
var _pending_political_features: Array[String] = []
var _job_political_features: Array[String] = []
var _upload_political_features: Array[String] = []
var _job_cells: Dictionary = {}
var _step_active: bool = false
var _replace_noncoast: bool = false

var local_coverage: Dictionary = {}
var annotation_canvas := RID()
var local_projection: Callable
var symbol_limit: Callable

func set_local_coverage(coverage: Dictionary) -> void:
	if local_coverage==coverage: return
	local_coverage = coverage
	# Presentation readiness changes only these existing chart samplers. It
	# does not invalidate country fill, geographic requests or installed meshes.
	for group: Array[Dictionary] in [_batches,_fallback_batches]:
		for batch: Dictionary in group:
			var kind := str(batch.kind)
			if kind in ["river","lake","water_surface","coast","rail"]:
				GlobeRenderer.local_chart_uniforms(batch,coverage,kind in ["river","lake","water_surface"],kind=="river")

func set_reference_window(window: Dictionary) -> void:
	if _reference_window==window: return
	var textures_changed := _reference_texture_key(_reference_window)!=_reference_texture_key(window)
	_reference_window = window
	_reference_revision += 1
	# update() binds visible land before submitting the canvas. Weight changes
	# do not visit hidden materials. A changed sampler set releases only hidden
	# materials that actually still retain a sampler, preserving their empty cache.
	if not textures_changed: return
	for group: Array[Dictionary] in [_batches,_fallback_batches]:
		for batch: Dictionary in group:
			if str(batch.get("kind",""))!="land_reference" or bool(batch.get("visible",false)):continue
			if not (batch.get("surface_reference",{}) as Dictionary).is_empty() or (batch.get("parameters",{}) as Dictionary).get("relief_window")!=null:
				GlobeRenderer._relief_window_uniforms(batch,{})
			batch.erase("reference_revision")

static func _reference_texture_key(window: Dictionary) -> Array:
	var surface: Dictionary=window.get("surface",{})
	var result: Array=[window.get("texture"),surface.get("base",{}).get("texture"),surface.get("secondary",{}).get("texture")]
	for tile: Dictionary in surface.get("tiles",[]):result.append(tile.get("texture"))
	return result

func _lod(mpp: float) -> String:
	var value := MapScaleStyle.lod(mpp)
	return "medium" if strategic and value == "local" else value

func begin(content: LocalSpatialContent, canvas: RID, mpp: float = 4500.0, ink_frames: Dictionary = {}, political_cells: Dictionary = {}) -> void:
	# Reading a new shard and uploading it are two separate waits. Retain the
	# displayed geometry through both, then release it at the replacement boundary.
	var previous: Array[Dictionary] = []
	var previous_lod := _target if available_lods.has(_target) else active_lod
	var previous_physical := _physical_reference
	if strategic and not previous_physical.is_empty(): previous_lod = str(previous_physical.lod)
	var previous_cells := _installed_political_cells
	if strategic and not previous_lod.is_empty() and available_lods.has(previous_lod):
		for index: int in range(_batches.size()-1,-1,-1):
			if bool(_batches[index].get("complete",false)) and not bool(_batches[index].get("political_patch",false)) and str(_batches[index].lod)==previous_lod:
				previous.append(_batches[index])
				_batches.remove_at(index)
	if strategic and previous.is_empty() and not _fallback_batches.is_empty():
		previous = _fallback_batches
		previous_lod = _fallback_lod
		_fallback_batches = []
	var previous_coverage := local_coverage
	clear()
	# A shard handoff retires geometry, not the current LOCAL presentation.
	local_coverage = previous_coverage
	_fallback_batches = previous
	_fallback_lod = previous_lod
	if strategic and not previous_physical.is_empty(): _physical_reference = previous_physical
	_content = content
	_ink_frames = ink_frames
	_political_cells = political_cells
	if not previous.is_empty(): _installed_political_cells = previous_cells
	strategic = str(content.metadata.get("content_level", "")) == "strategic"
	_canvas = canvas
	_shader = load("res://shaders/presentation/map/globe_boundary.gdshader") as Shader
	for feature: Dictionary in content.features:
		if str(feature.kind) in ["settlement","landmark","geographic_region"]:
			_places[str(feature.id)] = feature
			_labels.append({"feature": feature, "km": Vector2.ZERO, "projected": false})
	if not strategic:
		for visual: Dictionary in content.landmark_visuals():
			if not _places.has(str(visual.anchor_place_id)): continue
			# The R41 model decorates this transport point; retain its existing
			# feature, symbol and query identity instead of replacing it by a model.
			if visual.has("local_anchor_id") and str(visual.id)==str(visual.anchor_place_id): continue
			var feature := visual.duplicate(true)
			for index: int in range(_labels.size()-1,-1,-1):
				if str(_labels[index].feature.id)==str(feature.id): _labels.remove_at(index)
			_places[str(feature.id)] = feature
			_labels.append({"feature":feature,"km":Vector2.ZERO,"projected":false})
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.feature.rank) < int(b.feature.rank))
	_cursor = 0
	request_lods(mpp)

func install_political_content(content: LocalSpatialContent, ink_frames: Dictionary, political_cells: Dictionary) -> bool:
	if not strategic or not _resident or preparing or _lod_thread!=null or not available_lods.has(_target): return false
	# A completed upload has not published its source/coverage yet. Replacing
	# that input here could certify a newer cap using an older staged patch.
	if not _cpu_ready.is_empty() or not _upload_political_features.is_empty(): return false
	var regions: Array[String] = []
	for id: String in content.metadata.get("regions",[]) as Array:
		if id.begins_with("physical_"): regions.append(id)
	regions.sort()
	var installed_regions := _physical_reference.get("regions",[]) as Array
	if regions!=installed_regions or str(_physical_reference.get("lod",""))!=_target: return false
	# Same physical package, enriched input. Keep every installed coast and
	# water reference; stage land ink and optional chart features once.
	_content = content
	_ink_frames = ink_frames
	_political_cells = political_cells
	preparation_error = ""
	_replace_noncoast = true
	_places.clear()
	_labels.clear()
	_pending_political_features.clear()
	for feature: Dictionary in content.features:
		if str(feature.kind) in ["settlement","landmark","geographic_region"]:
			_places[str(feature.id)] = feature
			_labels.append({"feature":feature,"km":Vector2.ZERO,"projected":false})
		elif str(feature.kind) not in ["coast","ocean_reference"]:
			if str(feature.kind)!="land_reference" or not bool(_physical_reference.get("ink_enabled",false)):
				_pending_political_features.append(str(feature.id))
	_labels.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.feature.rank)<int(b.feature.rank))
	_queue_preparation()
	if not preparing and _pending_political_features.is_empty():
		_replace_noncoast = false
		_physical_reference["ink_enabled"] = true
		display_changed.emit()
	return true

func set_political_cells(cells: Dictionary) -> void:
	if _political_cells==cells: return
	var previous := _sovereign_geometry(_political_cells)
	var next := _sovereign_geometry(cells)
	var changed: Array[Rect2] = []
	for id: String in previous:
		if not next.has(id) or next[id]!=previous[id]: changed.append((previous[id] as Dictionary).bounds as Rect2)
	for id: String in next:
		if not previous.has(id) or next[id]!=previous[id]: changed.append((next[id] as Dictionary).bounds as Rect2)
	if changed.is_empty():
		# New-world administrative/control metadata does not invalidate the
		# historical sovereign mesh transferred from country selection.
		_political_cells = cells
		if _sovereign_geometry(_installed_political_cells)==next: _installed_political_cells = cells
		if _sovereign_geometry(_job_cells)==next: _job_cells = cells
		return
	for id: String in _upload_political_features+(_job_political_features if _lod_thread!=null else []):
		if id not in _pending_political_features: _pending_political_features.append(id)
	_political_cells = cells
	preparation_error = ""
	if _content==null or _content.cancelled or not _resident: return
	if strategic and not bool(_content.metadata.get("ink_enabled",false)): return
	for feature: Dictionary in _content.features:
		if str(feature.kind)!="land_reference": continue
		var raw := feature.get("bounds_lon_lat",[]) as Array
		if raw.size()!=4: continue
		var bounds := Rect2(Vector2(float(raw[0]),float(raw[2])),Vector2(float(raw[1])-float(raw[0]),float(raw[3])-float(raw[2])))
		for area: Rect2 in changed:
			if bounds.intersects(area,true) and str(feature.id) not in _pending_political_features: _pending_political_features.append(str(feature.id))
	_cancel_preparation()
	# Discard only incomplete staging. The last complete fill and coast stay live.
	_discard_unpublished()
	_upload_chunks.clear()
	_upload_political_features = []
	_chunks.clear()
	_cpu_ready.clear()
	_cursor = 0
	_queue_preparation()
	if ready and not preparing:
		_installed_political_cells = cells
		display_changed.emit()

static func _sovereign_geometry(cells: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in cells:
		var cell := cells[id] as Dictionary
		if bool(cell.get("sovereignty_changed",true)):
			result[id] = {"bounds":cell.bounds,"ring":cell.ring}
	return result

func political_cells_installed() -> Dictionary:
	return _installed_political_cells

func _finish_political_patch() -> void:
	# Swap just the affected political tessellation, never coast/water/DEM.
	for index: int in range(_batches.size()-1,-1,-1):
		var batch := _batches[index]
		if str(batch.lod)!=_target: continue
		if bool(batch.get("political_patch",false)):
			batch.complete = true
			batch.political_patch = false
		elif (_replace_noncoast and str(batch.kind) not in ["coast","ocean_reference","land_reference"]) or (str(batch.kind)=="land_reference" and str(batch.get("source_feature_id","")) in _upload_political_features):
			_retire_batch(batch)
			_batches.remove_at(index)
	_installed_political_cells = _job_cells
	if _replace_noncoast: _physical_reference["ink_enabled"] = true
	_replace_noncoast = false
	_upload_political_features = []

func request_lods(mpp: float) -> void:
	if _content == null:
		return
	var target := _lod(mpp)
	if _resident and _target == target: return
	if _resident and _target != target:
		_replace_noncoast = false
		_cancel_preparation()
		_pending_political_features.clear()
		_upload_political_features = []
		_upload_chunks.clear()
		_cursor = 0
		_discard_unpublished()
		for index: int in range(_chunks.size()-1,-1,-1):
			if not available_lods.has(str(_chunks[index].lod)): _chunks.remove_at(index)
	_resident = true
	preparation_error = ""
	_target = target
	_wanted.assign([target])
	_queue_preparation()

func _queue_preparation() -> void:
	# An uploaded patch still owns its source list until the display commit.
	if not preparing and not _upload_political_features.is_empty(): return
	if not preparation_error.is_empty():
		preparing = false
		return
	if _content == null or _content.cancelled:
		preparing = false
		return
	if _lod_thread != null:
		preparing = true
		return
	if not _resident or _lod_thread != null or _cursor < _upload_chunks.size():
		return
	var missing: Array[String] = []
	for lod_name: String in _wanted:
		if not _cpu_ready.has(lod_name) and not available_lods.has(lod_name): missing.append(lod_name)
	if not missing.is_empty():
		_lod_generation = _generation
		_job_cells = _political_cells if not strategic or bool(_content.metadata.get("ink_enabled",false)) else {}
		_job_political_features = []
		_pending_political_features.clear()
		var priority := MapJobs.FOUNDATION if strategic and _target=="coarse" else MapJobs.VISIBLE
		_lod_thread = MapJobs.submit(_prepare_job.bind(_content,missing,_generation,_ink_frames,_job_cells,[]),"map geometry",priority,self)
		if _lod_thread==null:
			_fail_preparation("地图几何任务队列已满。")
			return
		preparing = true
		return
	if available_lods.has(_target) and not _pending_political_features.is_empty():
		_job_political_features = _pending_political_features.duplicate()
		_pending_political_features.clear()
		_job_cells = _political_cells
		_lod_generation = _generation
		var patch_lods: Array[String] = [_target]
		_lod_thread = MapJobs.submit(_prepare_job.bind(_content,patch_lods,_generation,_ink_frames,_job_cells,_job_political_features),"map ink geometry",MapJobs.VISIBLE,self)
		if _lod_thread==null:
			_fail_preparation("政治显示任务队列已满。")
			return
		preparing = true
		return
	_upload_chunks.clear()
	_cursor = 0
	for chunk: Dictionary in _chunks:
		if str(chunk.lod) in _wanted and not available_lods.has(str(chunk.lod)):
			_upload_chunks.append(chunk)
	# An empty completed LOD is also a result. Do not retain an old region's rivers.
	for lod_name: String in _wanted:
		if _cpu_ready.has(lod_name) and not available_lods.has(lod_name):
			var pending := false
			for chunk: Dictionary in _upload_chunks:
				if str(chunk.lod)==lod_name: pending = true; break
			if not pending: available_lods[lod_name] = true
	preparing = _cursor < _upload_chunks.size()
	ready = available_lods.has(_target)

func _prepare_job(source: LocalSpatialContent, lods: Array[String], generation: int, frames: Dictionary, cells: Dictionary, only: Array) -> Dictionary:
	var features: Array[String] = []
	features.assign(only)
	var result := LocalSpatialLod.prepare(source,lods,_preparation_current.bind(generation),frames,cells,features,MAX_STAGED_BYTES)
	result["request"] = {"generation":generation,"lods":lods.duplicate(),"regions":source.metadata.get("regions",[]),"source_groups":source.line_chunks.size(),"features":features}
	return result

func diagnostic_state() -> Dictionary:
	return {"target":_target,"wanted":_wanted.duplicate(),"active":active_lod,"available":available_lods.keys(),"preparing":preparing,"generation":_generation,"worker_generation":_lod_generation,"upload_cursor":_cursor,"upload_total":_upload_chunks.size(),"cpu_ready":_cpu_ready.keys(),"published":(_physical_reference.get("regions",[]) as Array).duplicate(),"published_lod":_physical_reference.get("lod",""),"content_regions":(_content.metadata.get("regions",[]) as Array).duplicate() if _content!=null else [],"error":preparation_error,"last_result":preparation_result.duplicate(true)}

func _trim_gpu() -> void:
	if available_lods.has(_target):
		if strategic and _content!=null:
			var physical_ids: Array[String] = []
			for feature: Dictionary in _content.features:
				if str(feature.kind) in ["coast","land_reference","ocean_reference"]: physical_ids.append(str(feature.id))
			physical_ids.sort()
			var key := _target+"|"+",".join(physical_ids)
			if str(_physical_reference.get("key",""))!=key:
				var water: Array[Dictionary] = []
				var land: Array[Dictionary] = []
				var coverage: Array = []
				for feature: Dictionary in _content.features:
					if str(feature.kind)=="land_reference" and _target in (feature.get("presentation_lods",[]) as Array): land.append_array(feature.get("land_query",[]) as Array)
					if str(feature.kind) in ["land_reference","ocean_reference"] and _target in (feature.get("presentation_lods",[]) as Array):
						var bounds := feature.get("bounds_lon_lat",[]) as Array
						if bounds.size()==4 and bounds not in coverage: coverage.append(bounds)
					if str(feature.kind)=="ocean_reference" and _target in (feature.get("presentation_lods",[]) as Array):
						water.append({"geometry":feature.geometry})
				# Publish the complete fill/stroke/water version only after upload.
				var regions: Array[String] = []
				for id: String in _content.metadata.get("regions",[]) as Array:
					if id.begins_with("physical_"): regions.append(id)
				regions.sort()
				_physical_reference = {"key":key,"land":land,"water":water,"coverage":coverage,"lod":_target,"regions":regions,"ink_enabled":bool(_content.metadata.get("ink_enabled",false))}
		_clear_fallback()
	# Keep the old displayed batch until the requested replacement is complete.
	var fallback := active_lod
	if not available_lods.has(fallback) and not available_lods.is_empty():
		fallback = str(available_lods.keys()[0])
	var pending := str(_upload_chunks[_cursor].lod) if _cursor < _upload_chunks.size() else ""
	for index: int in range(_batches.size()-1,-1,-1):
		var batch := _batches[index]
		var protected := not available_lods.has(_target) and str(batch.lod)==fallback
		if str(batch.lod) not in _wanted and str(batch.lod)!=pending and not protected:
			_retire_batch(batch)
			available_lods.erase(str(batch.lod))
			_batches.remove_at(index)

func release_gpu() -> void:
	if not _resident: return
	_replace_noncoast = false
	_cancel_preparation()
	_resident = false
	_physical_reference = {}
	_clear_fallback()
	for batch: Dictionary in _batches: _retire_batch(batch)
	_batches.clear()
	_upload_chunks.clear()
	_cursor = 0
	available_lods.clear()
	active_lod = ""
	visible_places.clear()
	label_rects.clear()
	_chunks.clear()
	_cpu_ready.clear()
	_wanted.clear()
	ready = false
	preparing = _lod_thread != null

func prepare_step(font: Font, budget: FrameBudget = null) -> bool:
	if _step_active:
		_step_active = false
		_fail_preparation("地图几何或绘制资源安装中断，请查看游戏错误日志。")
		return false
	_step_active = true
	var changed := _prepare_step(font,budget)
	_step_active = false
	return changed

func _prepare_step(font: Font, budget: FrameBudget) -> bool:
	if not preparing and _lod_thread==null: return false
	var step_started := Time.get_ticks_usec()
	if _lod_thread != null:
		if not _lod_thread.completed:
			return false
		var returned: Variant = _lod_thread.take()
		_lod_thread = null
		if returned is Dictionary:
			var r := returned as Dictionary
			preparation_result = {"request":r.get("request",{}),"returned_lods":r.get("lods",[]),"chunks":(r.get("chunks",[]) as Array).size(),"cancelled":r.get("cancelled",false),"stale":_lod_generation!=_generation,"error":r.get("error","")}
		if _lod_generation != _generation or _content == null or _content.cancelled or not _resident:
			_queue_preparation()
			return false
		if not returned is Dictionary:
			var regions: String = ",".join(_content.metadata.get("regions",[]) as Array).left(240)
			_fail_preparation("地图几何线程未返回有效结果。%s / LOD=%s / %d源分组 / 区域=%s" % ["战略" if strategic else "局部",",".join(_wanted),_content.line_chunks.size(),regions])
			return false
		var prepared := returned as Dictionary
		if bool(prepared.get("cancelled",false)):
			# Normal superseded jobs were discarded by the generation check above.
			# A current cancellation is not evidence of a missing physical shard.
			_fail_preparation("地图几何当前请求意外取消："+JSON.stringify(preparation_result))
			return false
		if prepared.has("error"):
			_fail_preparation(str(prepared.error)+" / "+JSON.stringify(preparation_result))
			return false
		if not prepared.get("chunks") is Array or not prepared.get("lods") is Array or prepared.lods!=_wanted:
			_fail_preparation("地图几何结果缺少当前完整LOD："+JSON.stringify(preparation_result)+" / wanted="+JSON.stringify(_wanted))
			return false
		for value: Variant in prepared.chunks as Array:
			if not value is Dictionary or not (value as Dictionary).get("payload") is Dictionary or str((value as Dictionary).get("lod","")) not in _wanted or not (value as Dictionary).has("kind"):
				_fail_preparation("地图几何返回不完整的绘制批次。")
				return false
		if not _job_political_features.is_empty():
			_upload_political_features = _job_political_features
			_upload_chunks.assign(prepared.chunks as Array)
			_cursor = 0
			preparing = true
		else:
			_chunks.append_array(prepared.chunks as Array[Dictionary])
			for name: String in prepared.lods: _cpu_ready[name] = true
			_queue_preparation()
			if _lod_thread != null: return false
	if _content == null or _content.cancelled:
		preparing = false
		return false
	if not _resident:
		preparing = false
		return false
	while _cursor < _upload_chunks.size():
		var line := _upload_chunks[_cursor]
		var bytes := int(line.get("upload_bytes",0))
		if _geometry_bytes + bytes > MAX_GEOMETRY_BYTES:
			if strategic and _target=="medium" and not _fallback_batches.is_empty():
				# The separate WORLD slot is already complete. Use it while the
				# two medium versions cannot coexist within the same budget.
				_clear_fallback()
				_physical_reference = {}
				display_changed.emit()
				return false
			if not _retiring.is_empty(): return false
			_fail_preparation("地图几何超过当前绘制驻留预算（%d 字节已驻留，%d 字节待提交）。"%[_geometry_bytes,bytes])
			return false
		if budget!=null and not budget.claim_upload(bytes): return false
		var upload_started := Time.get_ticks_usec()
		var geometry: RefCounted
		var surface := line.has("face_count")
		var mesh: ArrayMesh
		var texture: ImageTexture
		if surface:
			var surfaces := GlobeSurfaceBatch.new()
			# Surface geometry includes physical land and water. Its kind, not
			# this mesh representation, determines geographic meaning.
			surfaces.upload(line.payload as Dictionary,budget)
			geometry = surfaces
			mesh = surfaces.mesh
			texture = surfaces.data
		else:
			var strokes := GlobeBoundaryBatch.new()
			strokes.upload(line.payload as Dictionary,budget)
			geometry = strokes
			mesh = strokes.mesh
			texture = strokes.data
		if texture == null or mesh.get_surface_count() == 0:
			_fail_preparation("地图绘制资源安装失败："+str(line.kind)+" / "+str(line.get("source_feature_id","")))
			return false
		var material := ShaderMaterial.new()
		var land_reference := str(line.kind) == "land_reference"
		material.shader = load("res://shaders/presentation/map/political_surface.gdshader" if land_reference else "res://shaders/presentation/map/globe_water_surface.gdshader") as Shader if surface else _shader
		if land_reference:
			material.set_shader_parameter("flag_weight",0.0)
			material.set_shader_parameter("political_weight",0.0)
			if str(line.get("water_class","")) == "antarctic_land":
				material.set_shader_parameter("antarctic_land",true)
				var ice := HydrographyStyle.color("land_reference","antarctic_land")
				material.set_shader_parameter("physical_land_color",Vector3(ice.r,ice.g,ice.b))
		material.set_shader_parameter("region_mode", true)
		if str(line.kind)=="ocean_reference": GlobeRenderer.bind_ocean_material(material)
		material.set_shader_parameter("face_data" if surface else "line_data", texture)
		if surface and not land_reference:
			material.set_shader_parameter("water_color", HydrographyStyle.color(str(line.kind), str(line.get("water_class", "lake"))))
			material.set_shader_parameter("water_color_transition",line.get("water_transition",HydrographyStyle.surface_transition(str(line.get("source_feature_id",line.get("feature_id",""))))))
			material.set_shader_parameter("water_color_far",HydrographyStyle.OCEAN_COLOR)
		elif not surface:
			material.set_shader_parameter("stroke_color", HydrographyStyle.line_color(str(line.kind),str(line.get("water_line_style",""))))
			var dash := HydrographyStyle.line_dash(str(line.get("water_line_style","")))
			material.set_shader_parameter("dash_period",dash.x)
			material.set_shader_parameter("dash_on",dash.y)
			material.set_shader_parameter("stroke_width", HydrographyStyle.WIDTHS[str(line.kind)]*float(line.get("stroke_scale",1.0)))
			material.set_shader_parameter("miter_limit", HydrographyStyle.miter_limit(str(line.kind)))
			material.set_shader_parameter("stroke_feather", HydrographyStyle.feather(str(line.kind)))
			material.set_shader_parameter("rail_style", rail_style if str(line.kind)=="rail" else 0)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item,_display_canvas if _display_canvas.is_valid() else _canvas)
		RenderingServer.canvas_item_set_draw_index(item, DRAW_ORDER-2 if str(line.kind) in ["land_reference","ocean_reference"] else DRAW_ORDER-1 if str(line.kind)=="coast" else DRAW_ORDER)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		RenderingServer.canvas_item_add_mesh(item, mesh.get_rid())
		RenderingServer.canvas_item_set_visible(item, false)
		_batches.append({"item": item, "material": material, "geometry": geometry, "lod":line.lod, "kind":line.kind, "visible":false, "complete":false, "surface": surface, "ink_reference":line.get("ink_reference",""),"source_feature_id":line.get("source_feature_id",""),"original_ink_reference":line.get("original_ink_reference",""),"component_uv":line.get("component_uv",false),"political_patch":not _upload_political_features.is_empty(),"texture":RID(),"water_class": line.get("water_class", "lake"), "replacement_key":line.get("replacement_key",""),"water_line_style":line.get("water_line_style",""), "faces": int(line.get("face_count",0)), "cull_axis":line.get("cull_axis",Vector3.ZERO),"cull_angle":line.get("cull_angle",PI)})
		_batches.back()["upload_bytes"] = bytes
		_geometry_bytes += bytes
		if budget!=null: budget.finish_upload(upload_started,str(line.kind))
		# The installed geometry owns its mesh, texture and required picking data.
		# Encoded staging arrays are no longer needed by either content level.
		line.erase("payload")
		_cursor += 1
		# No staged face or stroke becomes eligible before the complete upload.
		if _cursor < _upload_chunks.size() and Time.get_ticks_usec() - step_started >= PREPARE_BUDGET_USEC:
			return true
	# Upload completion only makes staging eligible. Keep the old display
	# until update() submits the new projection, material and visibility.
	# A final empty mesh still completes its LOD; it must replace the old region.
	for lod_name: String in _wanted:
		if _cpu_ready.has(lod_name):
			available_lods[lod_name] = true
	# Batch.complete means published, not merely uploaded. A camera redraw
	# may keep using the old LOD while this successor waits for valid coverage.
	ready = available_lods.has(_target)
	preparing = false
	# Source geometry stays in Content. Another LOD is prepared on demand;
	# already installed LODs do not require a second CPU upload cache.
	_chunks.clear()
	_upload_chunks.clear()
	_cursor = 0
	# Upload completion requests a display commit through prepare_step's caller.
	# display_changed belongs to the installed version, not hidden staging.
	return true

func _fail_preparation(message: String) -> void:
	push_error(message)
	_replace_noncoast = false
	preparation_error = message
	preparing = false
	# Retain the last complete display, including its political installation.
	_discard_unpublished()
	_chunks.clear()
	_upload_chunks.clear()
	_upload_political_features.clear()
	_pending_political_features.clear()
	_cpu_ready.clear()
	_cursor = 0
	preparation_failed.emit(message)

func _discard_unpublished() -> void:
	for index: int in range(_batches.size()-1,-1,-1):
		if not bool(_batches[index].get("complete",false)) or bool(_batches[index].get("political_patch",false)):
			_retire_batch(_batches[index])
			_batches.remove_at(index)
	for lod_name: String in _cpu_ready: available_lods.erase(lod_name)
	_cpu_ready.clear()
	ready = available_lods.has(_target)

func display_installed() -> bool:
	return _resident and available_lods.has(_target) and _cpu_ready.is_empty() and _upload_political_features.is_empty() and _installed_political_cells==_political_cells and not preparing and not _step_active and preparation_error.is_empty()

func preparation_lod() -> String:
	return _target if strategic and _resident else ""

func discard_uncovered_preparation(required_regions: Array[String]) -> void:
	if not strategic or not preparing or _wanted.is_empty() or _content==null or required_regions.is_empty(): return
	var regions := _content.metadata.get("regions",[]) as Array
	if required_regions.all(func(id: String) -> bool: return id in regions): return
	# This pending package cannot become a complete frame for the new cap.
	# Cancel its CPU work and hidden uploads, never the installed physical map.
	_cancel_preparation()
	_discard_unpublished()
	_pending_political_features.clear()
	_upload_political_features = []
	_job_political_features = []
	_upload_chunks.clear()
	_chunks.clear()
	_cursor = 0
	_wanted.clear()
	_replace_noncoast = false
	preparing = _lod_thread!=null

func can_present_physical(required_regions: Array[String], mpp: float, lod_override: String = "") -> bool:
	if not strategic or not _resident or required_regions.is_empty(): return false
	var lod_name := _lod(mpp) if lod_override.is_empty() else lod_override
	# A successor can be published only as a whole current-view package. The
	# previous package is not coverage evidence for an unrelated staged result.
	if not preparing and (_cpu_ready.has(_target) or not _upload_political_features.is_empty()):
		if _content==null or _content.cancelled or _target!=lod_name or not available_lods.has(lod_name): return false
		var staged := _content.metadata.get("regions",[]) as Array
		return required_regions.all(func(id: String) -> bool: return id in staged)
	var installed := _physical_reference.get("regions",[]) as Array
	return str(_physical_reference.get("lod",""))==lod_name and required_regions.all(func(id: String) -> bool: return id in installed)

func can_reproject_physical(required_regions: Array[String]) -> bool:
	# The caller selects this same geographic cap at the INSTALLED LOD.
	# Cross-LOD tile IDs differ; equal geographic coverage does not require
	# matching the desired upgrade's IDs or having its files already loaded.
	if not strategic or not _resident or required_regions.is_empty() or _physical_reference.is_empty(): return false
	var installed := _physical_reference.get("regions",[]) as Array
	return required_regions.all(func(id: String) -> bool: return id in installed)

func _cancel_preparation() -> void:
	_generation_mutex.lock()
	_generation += 1
	_generation_mutex.unlock()
	MapJobs.cancel_queued(_lod_thread)

func _preparation_current(generation: int) -> bool:
	_generation_mutex.lock()
	var current := _generation == generation
	_generation_mutex.unlock()
	return current

func content_reference() -> LocalSpatialContent:
	return _content

func physical_reference() -> Dictionary:
	return _physical_reference

func place(id: String) -> Dictionary:
	return _places.get(id, {}) as Dictionary

func has_visible_kind(kind: String) -> bool:
	for batch: Dictionary in _batches+_fallback_batches:
		if str(batch.kind)==kind and bool(batch.get("visible",false)): return true
	return false

func physical_water_at(point: Vector2, camera: RegionCamera, world_view: Dictionary) -> bool:
	var unit := camera.unit_at(point) if camera.active else RegionProjection.world_unit(point,world_view.center as Vector2,float(world_view.radius),world_view.basis as Basis)
	if unit.is_zero_approx(): return false
	var position := RegionProjection.lon_lat(unit)
	for bounds: Array in _physical_reference.get("coverage",[]) as Array:
		if position.y<float(bounds[2]) or position.y>float(bounds[3]): continue
		for shift: float in [-360.0,0.0,360.0]:
			if position.x>=float(bounds[0])+shift and position.x<=float(bounds[1])+shift:
				return not physical_land_at(point,camera,world_view)
	return false

func physical_land_at(point: Vector2, camera: RegionCamera, world_view: Dictionary) -> bool:
	var unit := camera.unit_at(point) if camera.active else RegionProjection.world_unit(point,world_view.center as Vector2,float(world_view.radius),world_view.basis as Basis)
	if unit.is_zero_approx(): return false
	var position := RegionProjection.lon_lat(unit)
	# The complete installed physical version owns queries, including while
	# a successor is staging or political ink fails.
	for polygon: Dictionary in _physical_reference.get("land",[]) as Array:
		var coordinate := position
		coordinate.x += 360.0*roundf(((polygon.bounds as Rect2).get_center().x-coordinate.x)/360.0)
		if not (polygon.bounds as Rect2).has_point(coordinate): continue
		var rings := polygon.rings as Array
		if not Geometry2D.is_point_in_polygon(coordinate,rings[0] as PackedVector2Array): continue
		var hole := false
		for ring: PackedVector2Array in rings.slice(1):
			if Geometry2D.is_point_in_polygon(coordinate,ring): hole = true; break
		if not hole: return true
	return false

func update(camera: RegionCamera, controller: GlobeController, date: String, viewport_size: Vector2, commit_canvas: bool = true, world_view: Dictionary = {}, prepare_picking: bool = true) -> void:
	var costs: Dictionary=world_view.get("observation_costs",{})
	var observed: int=Time.get_ticks_usec() if not costs.is_empty() else 0
	var sampler_us: int=0
	var max_batch_us: int=0
	var max_batch_kind: String=""
	var regional := camera.active
	var geometry_ready := _resident and (not available_lods.is_empty() or not _fallback_batches.is_empty())
	var covered := strategic or _content!=null and _content.covers(RegionProjection.lon_lat(camera.valid_anchor(viewport_size).unit as Vector3))
	if not covered and regional and _content!=null:
		for visual: Dictionary in _content.landmark_visuals():
			var coordinate := (visual.geometry as Dictionary).coordinates as Array
			if Rect2(Vector2.ZERO,viewport_size).has_point(camera.project(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinate[0]),float(coordinate[1]))))): covered = true; break
	var show := _content!=null and (geometry_ready or not strategic and not _content.landmark_visuals().is_empty()) and (regional or strategic and not world_view.is_empty()) and _content.display_active_on(date) and covered
	var mpp := camera.km_per_pixel * 1000.0 if regional else float(world_view.get("mpp",8501.0))
	var publishing := commit_canvas and _resident and not preparing and (not _cpu_ready.is_empty() or not _upload_political_features.is_empty()) and (not strategic or bool(world_view.get("install_physical",false)))
	active_lod = str(world_view.get("display_lod","")) if strategic and show else _lod(mpp) if show else ""
	if show and not strategic and not available_lods.has(active_lod):
		active_lod = str(available_lods.keys()[0]) if not available_lods.is_empty() else _fallback_lod
	if not commit_canvas:
		_update_places(camera,controller,date,viewport_size,world_view,show,mpp)
		return
	var weights: Dictionary = {}
	var colors: Dictionary = {}
	if commit_canvas:
		for kind: String in ["coast","river","rail","land_reference","ocean_reference","lake","water_surface"]:
			var weight := MapScaleStyle.strategic_weight(kind,mpp) if strategic else MapScaleStyle.physical_weight(kind,mpp)
			# One completed physical LOD owns fill and stroke together. Cross-
			# fading different geometries exposes the old political coast below.
			if strategic and kind in ["land_reference","ocean_reference","coast"]: weight = 1.0
			if kind == "rail" and not controller.strategic_rails_enabled: weight = 0.0
			weights[kind] = weight
			var color := HydrographyStyle.color(kind)
			color.a *= weight
			colors[kind] = color
	var camera_values: Array = [camera.tangent_frame.transposed(),camera.origin,camera.km_per_pixel,Vector2(cos(camera.bearing),sin(camera.bearing))] if regional else [controller.orientation(),world_view.get("center",Vector2.ZERO),world_view.get("radius",1.0)]
	var camera_parameters: Array[StringName] = [&"globe_basis", &"globe_center"]
	if regional:
		camera_parameters.append(&"region_km_per_pixel")
		camera_parameters.append(&"region_bearing")
	else:
		camera_parameters.append(&"globe_radius")
	var canvas: RID = _canvas if regional else world_view.get("canvas",RID())
	if commit_canvas and _display_canvas != canvas:
		_display_canvas = canvas
	var anchor := camera.valid_anchor(viewport_size) if regional else {}
	var view_center := anchor.unit as Vector3 if regional else controller.orientation().transposed()*Vector3.BACK
	var view_angle := PI*0.5
	if regional:
		view_angle = 0.0
		for corner: Vector2 in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
			view_angle = maxf(view_angle,(corner.distance_to(anchor.pixel as Vector2)+8.0)*camera.km_per_pixel/6371.0088)
	var date_active := _content.active_on(date) if _content!=null else false
	var relief_world: Texture2D = reference_relief.get("world")
	var relief_region: Texture2D = reference_relief.get("region")
	var relief_weight := MapScaleStyle.relief_weight(mpp,controller.map_mode) if relief_world!=null else 0.0
	var relief_detail := MapScaleStyle.relief_detail_weight(mpp) if relief_region!=null else 0.0
	var grid := world_view.get("military_grid",{}) as Dictionary
	var ink_revision := int(world_view.get("ink_revision",-1))
	var land_style: Array = [ink_revision,world_view.get("ownership_revision",-1),controller.player_polity_id,grid,relief_world.get_instance_id() if relief_world!=null else 0,relief_region.get_instance_id() if relief_region!=null else 0,relief_weight,relief_detail]
	for batch: Dictionary in _batches + _fallback_batches:
		var batch_at: int=Time.get_ticks_usec() if observed>0 else 0
		var kind := str(batch.kind)
		var target_canvas := annotation_canvas if regional and annotation_canvas.is_valid() and kind not in ["land_reference","ocean_reference"] else canvas
		if batch.get("parent_canvas",RID())!=target_canvas:
			RenderingServer.canvas_item_set_parent(batch.item as RID,target_canvas)
			batch["parent_canvas"] = target_canvas
		if kind=="land_reference":
			var order := -50
			if int(batch.get("display_order",0))!=order:
				RenderingServer.canvas_item_set_draw_index(batch.item as RID,order)
				batch["display_order"] = order

		var weight := float(weights[str(batch.kind)])
		var dated := date_active or strategic and kind in ["land_reference","coast"]
		var published := bool(batch.get("complete",false)) or publishing and str(batch.lod)==_target
		var visible := show and dated and published and str(batch.lod) == active_lod and weight > 0.001 and kind not in observation_hidden_kinds
		# A load-time enclosing spherical cap rejects wholly offscreen batches.
		# This visits existing batches, never polygons, on controlled redraws.
		if visible and not view_center.is_zero_approx() and float(batch.cull_angle)<PI*0.5:
			var axis := batch.cull_axis as Vector3
			if not axis.is_zero_approx():
				visible = axis.dot(view_center) >= cos(minf(PI,float(batch.cull_angle)+view_angle))
		if visible:
			if kind=="land_reference": GlobeRenderer._parameter(batch,"city_overview",regional and bool(world_view.get("city_overview",false)))
			# Coverage changes already clear every hidden sampler in set_local_coverage.
			# New visible batches receive it here, without revisiting all hidden ink.
			if kind in ["river","lake","water_surface","coast","rail"]:
				GlobeRenderer.local_chart_uniforms(batch,local_coverage if regional else {},kind in ["river","lake","water_surface"],kind=="river")
			var material := batch.material as ShaderMaterial
			GlobeRenderer._parameter(batch,"region_mode",regional)
			if bool(batch.surface) and kind!="land_reference": GlobeRenderer._parameter(batch,"ocean_surface",kind=="ocean_reference")
			var color := colors[str(batch.kind)] as Color
			if bool(batch.surface) and kind!="land_reference":
				color = HydrographyStyle.color(str(batch.kind),str(batch.water_class))
				color.a *= weight
				GlobeRenderer._parameter(batch,"water_color",color)
			elif not bool(batch.surface):
				if kind=="river" and not str(batch.get("water_line_style","")).is_empty():
					color = HydrographyStyle.line_color(kind,str(batch.water_line_style))
					color.a *= weight
				GlobeRenderer._parameter(batch,"stroke_color",color)
			if kind=="land_reference" and (ink_revision<0 or batch.get("land_style",[])!=land_style):
				batch["land_style"]=land_style
				# Ink is an exact optional partition of physical land. It changes
				# material inputs, never shape, height, selection or ownership facts.
				var reference := str(batch.get("ink_reference",""))
				var styles := world_view.get("ink_styles",{}) as Dictionary
				var owners := world_view.get("ink_owners",{}) as Dictionary
				var current := world_view.get("current_land_owners",{}) as Dictionary
				var owner := str((current.get(reference,{}) as Dictionary).get("sovereign","")) if reference.begins_with("territory_unit:") else reference if reference.begins_with("political_map_region:") else str(owners.get(reference,""))
				var own_grid: bool=not grid.is_empty() and not owner.is_empty() and owner==controller.player_polity_id
				GlobeRenderer._parameter(batch,"military_grid_step",float(grid.get("step",0.0)) if own_grid else 0.0)
				if own_grid:
					GlobeRenderer._parameter(batch,"military_grid_projection",grid.projection)
					GlobeRenderer._parameter(batch,"military_grid_origin",grid.origin)
				var style := styles.get(owner,{}) as Dictionary if not owner.is_empty() else {}
				var parameters := style.get("parameters",{}) as Dictionary
				for parameter: String in ["surface_color","political_base_color","political_focus_style","political_emphasis","flag_weight","political_weight","flag_bounds","flag_uv_scale","flag_uv_offset","flag_uv_rotation"]:
					if parameter in ["flag_bounds","flag_uv_scale","flag_uv_offset","flag_uv_rotation"] and bool(batch.get("component_uv",false)): continue
					if parameters.has(parameter): GlobeRenderer._parameter(batch,parameter,parameters[parameter])
				if bool(batch.get("component_uv",false)):
					# Component UV is already the complete flag image. Old crops
					# expressed in the largest-territory frame would fit it twice.
					GlobeRenderer._parameter(batch,"flag_bounds",Vector4(0,0,1,1))
					GlobeRenderer._parameter(batch,"flag_uv_scale",Vector2.ONE)
					GlobeRenderer._parameter(batch,"flag_uv_offset",Vector2.ZERO)
					GlobeRenderer._parameter(batch,"flag_uv_rotation",Vector2(1,0))
				var original := str(batch.get("original_ink_reference",""))
				var original_owner := original if original.begins_with("political_map_region:") else str(owners.get(original,""))
				var new_sovereign := reference.begins_with("territory_unit:") and owner!=original_owner
				if new_sovereign: GlobeRenderer._parameter(batch,"flag_weight",0.0)
				if parameters.is_empty():
					GlobeRenderer._parameter(batch,"flag_weight",0.0)
					GlobeRenderer._parameter(batch,"political_weight",0.0)
				# A flag changes a sampler, never the mesh draw command or its
				# implicit canvas TEXTURE/UV state.
				GlobeRenderer._parameter(batch,"flag_texture",null if new_sovereign else style.get("flag_texture"))
				GlobeRenderer._parameter(batch,"reference_opacity",weight)
				GlobeRenderer._parameter(batch,"relief_world",relief_world)
				GlobeRenderer._parameter(batch,"relief_region",relief_region)
				GlobeRenderer._parameter(batch,"relief_weight",relief_weight)
				GlobeRenderer._parameter(batch,"relief_detail_weight",relief_detail)
			if kind=="land_reference":
				if int(batch.get("reference_revision",-1))!=_reference_revision or not batch.has("surface_reference"):
					var sampler_at: int=Time.get_ticks_usec() if observed>0 else 0
					GlobeRenderer._relief_window_uniforms(batch,_reference_window)
					if observed>0: sampler_us+=Time.get_ticks_usec()-sampler_at
					batch["reference_revision"]=_reference_revision
			if not bool(batch.surface):
				GlobeRenderer._parameter(batch, "rail_style", rail_style if str(batch.kind)=="rail" else 0)
				GlobeRenderer._parameter(batch,"river_replacement",world_view.get("local_river_replacements",{}).get(str(batch.get("replacement_key","")),Vector4.ZERO) if regional else Vector4.ZERO)
			if strategic and str(batch.kind)=="rail": GlobeRenderer._parameter(batch,"stroke_width",MapScaleStyle.strategic_rail_width(mpp))
			var previous := batch.get("camera_values",[]) as Array
			if previous != camera_values:
				for index: int in range(camera_values.size()):
					if previous.size()!=camera_values.size() or previous[index] != camera_values[index]: material.set_shader_parameter(camera_parameters[index],camera_values[index])
				batch["camera_values"] = camera_values
			if batch.get("bounds_size",Vector2.ZERO) != viewport_size: GlobeRenderer._bounds(batch,viewport_size)
		if visible != bool(batch.visible):
			RenderingServer.canvas_item_set_visible(batch.item as RID, visible)
			batch.visible = visible
		if observed>0 and Time.get_ticks_usec()-batch_at>max_batch_us:
			max_batch_us=Time.get_ticks_usec()-batch_at
			max_batch_kind=kind
	if observed>0: costs["surface_batches_us"]=Time.get_ticks_usec()-observed;costs["surface_samplers_us"]=sampler_us;observed=Time.get_ticks_usec()
	if observed>0: costs["surface_max_batch_us"]=max_batch_us;costs["surface_max_batch_kind"]=max_batch_kind
	if publishing:
		var previous_physical: Array = [_physical_reference.get("key",""),_physical_reference.get("ink_enabled",false)]
		var previous_cells := _installed_political_cells
		var patched := not _upload_political_features.is_empty()
		var completed_lod := _cpu_ready.has(_target)
		if completed_lod:
			for batch: Dictionary in _batches:
				if str(batch.lod)==_target: batch.complete = true
		if patched: _finish_political_patch()
		# New visible batches have current uniforms before predecessor RIDs go.
		_trim_gpu()
		if _cpu_ready.has(_target): _installed_political_cells = _job_cells
		_cpu_ready.clear()
		_queue_preparation()
		if completed_lod or patched or previous_physical!=[_physical_reference.get("key",""),_physical_reference.get("ink_enabled",false)] or previous_cells!=_installed_political_cells:
			display_changed.emit()
	# A same-input CPU query already prepared picking before this publication.
	# A changed target/appearance still takes the ordinary complete query path.
	if observed>0: costs["surface_publication_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
	if prepare_picking: _update_places(camera,controller,date,viewport_size,world_view,show,mpp)
	if observed>0: costs["surface_picking_us"]=Time.get_ticks_usec()-observed

func _update_places(camera: RegionCamera, controller: GlobeController, date: String, viewport_size: Vector2, world_view: Dictionary, show: bool, mpp: float) -> void:
	visible_places.clear()
	label_rects.clear()
	var regional := camera.active
	var changed_frame := _frame != camera.tangent_frame
	if show:
		_frame = camera.tangent_frame
	var axes := RegionProjection.screen_axes(camera.bearing)
	for label: Dictionary in _labels:
		if not show:
			continue
		var feature := label.feature as Dictionary
		if suppressed_places.has(str(feature.id)):
			continue
		var dated := LocalSpatialContent.landmark_visible_on(feature,date) if str(feature.kind)=="landmark" else date>=str(feature.valid_from) and date<str(feature.valid_to)
		if not dated:
			continue
		if regional and (changed_frame or not bool(label.projected)):
			var coordinates := feature.geometry.coordinates as Array
			label.km = RegionProjection.forward(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]), float(coordinates[1]))), _frame)
			label.projected = true
		var selected := str(feature.id) == controller.selected_place_id
		var limit := float(feature.get("max_mpp", 0.0)) if strategic else MapScaleStyle.settlement_limit(int(feature.rank), str(feature.id))
		if feature.has("display_kind"): limit = float(feature.get("max_mpp",650.0))
		if str(feature.kind)=="landmark": limit = float(feature.symbol_max_mpp)
		if symbol_limit.is_valid(): limit = symbol_limit.call(feature,str(feature.id)) as float
		if mpp > limit and not selected:
			continue
		var coordinates := feature.geometry.coordinates as Array
		var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
		var viewed := controller.orientation()*unit
		if not regional and viewed.z < 0.0: continue
		var point := camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel) if regional else GlobeProjection.sphere_screen(viewed,world_view.center as Vector2,float(world_view.radius))
		if regional and camera.local_active and local_projection.is_valid(): point = local_projection.call(unit) as Vector2
		if not Rect2(Vector2.ZERO, viewport_size).has_point(point):
			continue
		visible_places[str(feature.id)] = point

func clear() -> void:
	preparation_error = ""
	_replace_noncoast = false
	local_coverage = {}
	_ink_frames = {}
	_political_cells = {}
	_installed_political_cells = {}
	_pending_political_features.clear()
	_job_political_features = []
	_upload_political_features = []
	_job_cells = {}
	_physical_reference = {}
	_cancel_preparation()
	_clear_fallback()
	for batch: Dictionary in _batches:
		_retire_batch(batch)
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
	_frame = Basis()
	_display_canvas = RID()
	var retired := _detach_content_data()
	if not retired.is_empty() and _lod_thread == null:
		# Reuse the cancelled geometry slot. Only detached CPU containers move
		# here; meshes, materials and CanvasItems have already been released.
		_lod_generation = _generation-1
		_lod_thread = MapJobs.submit(LocalSpatialLayer._release_content_data.bind(retired),"retire map source",MapJobs.OPTIONAL)
		if _lod_thread==null:
			retired.clear()
	preparing = _lod_thread != null
	reference_relief = {}
	_reference_window = {}
	suppressed_places = {}

func _detach_content_data() -> Array:
	if _content == null: return []
	# Keep the containers alive while dropping the Content object. Do not
	# mutate them: another loader may still share an immutable shard.
	var data := [_content.metadata,_content.features,_content.shards,_content.errors,_content.line_chunks,_content.surface_reference,_content.surface_covers]
	_content = null
	return data

static func _release_content_data(data: Array) -> Dictionary:
	data.clear()
	return {"cancelled":true,"request":{"operation":"retire_cpu_data"}}

func hide_display() -> void:
	# Retain this precision's resources; the other complete precision owns the
	# visible surface. This is not clear()/release_gpu().
	var release_detail := reference_relief.has("region") or not _reference_window.is_empty()
	for batch: Dictionary in _batches+_fallback_batches:
		if bool(batch.get("visible",false)):
			RenderingServer.canvas_item_set_visible(batch.item as RID,false)
			batch["visible"] = false
		if release_detail and str(batch.kind)=="land_reference":
			GlobeRenderer._parameter(batch,"relief_region",null)
			GlobeRenderer._relief_window_uniforms(batch,{})
			batch.erase("reference_revision")
	if release_detail:
		reference_relief = {"world":reference_relief.get("world")}
		_reference_window = {}
	visible_places.clear()
	label_rects.clear()

func dispose() -> void:
	clear()
	drain_retirement()
	MapJobs.abandon(_lod_thread)
	_lod_thread = null

func _clear_fallback() -> void:
	for batch: Dictionary in _fallback_batches:
		_retire_batch(batch)
	_fallback_batches.clear()
	_fallback_lod = ""

func _retire_batch(batch: Dictionary) -> void:
	RenderingServer.canvas_item_set_visible(batch.item as RID,false)
	if _retiring.size() >= MAX_RETIRED_BATCHES:
		_free_batch(_retiring.pop_back())
	_retiring.append(batch)

func _free_batch(batch: Dictionary) -> void:
	RenderingServer.free_rid(batch.item as RID)
	_geometry_bytes -= int(batch.get("upload_bytes",0))

func retirement_pending() -> bool:
	return not _retiring.is_empty()

func drain_retirement(budget: FrameBudget = null) -> void:
	while not _retiring.is_empty() and (budget==null or budget.claim_retirement()):
		_free_batch(_retiring.pop_back())
