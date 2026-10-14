class_name LocalSpatialLayer
extends RefCounted
signal display_changed
## Prepared line meshes and glyphs on the existing regional canvas.

const PREPARE_BUDGET_USEC: int = 2000
const DRAW_ORDER: int = 100000
var rail_style: int = 2
var ready: bool = false
var preparing: bool = false
var visible_places: Dictionary = {}
var label_rects: Array[Rect2] = []
var available_lods: Dictionary = {}
var active_lod: String = ""
var _chunks: Array[Dictionary] = []
var _lod_thread: Thread
var _lod_generation: int = 0
var _generation: int = 0
var _generation_mutex := Mutex.new()
var _batches: Array[Dictionary] = []
var _fallback_batches: Array[Dictionary] = []
var _fallback_lod: String = ""
var _places: Dictionary = {}
var _labels: Array[Dictionary] = []
var _content: LocalSpatialContent
var _cursor: int = 0
var _visible_labels: Array[Dictionary] = []
var label_font: Font
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
var paris_mask_weights: Dictionary = {}
var _reference_visuals: Dictionary = {}
var _reference_frames: Dictionary = {}
var reference_relief: Dictionary = {}
var reserved_label_rects: Array[Rect2] = []

func _lod(mpp: float) -> String:
	var value := MapScaleStyle.lod(mpp)
	return "medium" if strategic and value == "local" else value

func begin(content: LocalSpatialContent, canvas: RID, mpp: float = 4500.0, visual_context: Dictionary = {}) -> void:
	# Reading a new shard and uploading it are two separate waits. Retain the
	# displayed geometry through both, then release it at the replacement boundary.
	var previous: Array[Dictionary] = []
	var previous_lod := active_lod
	if strategic and not active_lod.is_empty() and available_lods.has(active_lod):
		for index: int in range(_batches.size()-1,-1,-1):
			if bool(_batches[index].get("complete",false)) and str(_batches[index].lod)==active_lod:
				previous.append(_batches[index])
				_batches.remove_at(index)
	elif strategic and not _fallback_batches.is_empty():
		previous = _fallback_batches
		previous_lod = _fallback_lod
		_fallback_batches = []
	clear()
	_fallback_batches = previous
	_fallback_lod = previous_lod
	_reference_visuals = visual_context.get("templates", {}) as Dictionary
	_reference_frames = visual_context.get("frames", {}) as Dictionary
	_content = content
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
			var feature := visual.duplicate(true)
			for index: int in range(_labels.size()-1,-1,-1):
				if str(_labels[index].feature.id)==str(feature.id): _labels.remove_at(index)
			_places[str(feature.id)] = feature
			_labels.append({"feature":feature,"km":Vector2.ZERO,"projected":false})
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.feature.rank) < int(b.feature.rank))
	_cursor = 0
	request_lods(mpp)

func request_lods(mpp: float) -> void:
	if _content == null:
		return
	var target := _lod(mpp)
	if _resident and _target == target: return
	if _resident and _target != target:
		_cancel_preparation()
		_upload_chunks.clear()
		_cursor = 0
		for index: int in range(_batches.size()-1,-1,-1):
			if not bool(_batches[index].get("complete",false)):
				RenderingServer.free_rid(_batches[index].item as RID)
				_batches.remove_at(index)
		for index: int in range(_chunks.size()-1,-1,-1):
			if not available_lods.has(str(_chunks[index].lod)): _chunks.remove_at(index)
		for lod_name: String in _cpu_ready.keys():
			if not available_lods.has(lod_name): _cpu_ready.erase(lod_name)
	_resident = true
	_target = target
	_wanted.assign([target])
	_queue_preparation()
	_trim_gpu()

func _queue_preparation() -> void:
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
		_lod_thread = Thread.new()
		_lod_generation = _generation
		_lod_thread.start(LocalSpatialLod.prepare.bind(_content,missing,_reference_frames,_preparation_current.bind(_generation)))
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

func _trim_gpu() -> void:
	if available_lods.has(_target):
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
			RenderingServer.free_rid(batch.item as RID)
			available_lods.erase(str(batch.lod))
			_batches.remove_at(index)

func release_gpu() -> void:
	if not _resident: return
	_cancel_preparation()
	_resident = false
	_clear_fallback()
	for batch: Dictionary in _batches: RenderingServer.free_rid(batch.item as RID)
	_batches.clear()
	_visible_labels.clear()
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

func prepare_step(font: Font) -> bool:
	var step_started := Time.get_ticks_usec()
	if _lod_thread != null:
		if _lod_thread.is_alive():
			return false
		var prepared := _lod_thread.wait_to_finish() as Dictionary
		_lod_thread = null
		if _lod_generation != _generation or _content == null or _content.cancelled or not _resident:
			_queue_preparation()
			return false
		_chunks.append_array(prepared.chunks as Array[Dictionary])
		for name: String in prepared.lods: _cpu_ready[name] = true
		_queue_preparation()
		if _lod_thread != null:
			return false
	if _content == null or _content.cancelled:
		preparing = false
		return false
	if not _resident:
		preparing = false
		return false
	label_font = font
	while _cursor < _upload_chunks.size():
		var line := _upload_chunks[_cursor]
		var geometry: RefCounted
		var water := line.has("face_count")
		var mesh: ArrayMesh
		var texture: ImageTexture
		if water:
			var surfaces := GlobeSurfaceBatch.new()
			# Land picking reports physical coverage only; texture continuation is
			# explicitly not an authority mapping.
			surfaces.upload(line.payload as Dictionary)
			geometry = surfaces
			mesh = surfaces.mesh
			texture = surfaces.data
		else:
			var strokes := GlobeBoundaryBatch.new()
			strokes.upload(line.payload as Dictionary)
			geometry = strokes
			mesh = strokes.mesh
			texture = strokes.data
		if texture == null or mesh.get_surface_count() == 0:
			_cursor += 1
			continue
		var reference := str(line.get("visual_reference_feature", ""))
		var template := _reference_visuals.get(reference, {}) as Dictionary
		var material := (template.material as ShaderMaterial).duplicate() as ShaderMaterial if not template.is_empty() else ShaderMaterial.new()
		var land_reference := str(line.kind) == "land_reference"
		if template.is_empty(): material.shader = load("res://shaders/presentation/map/political_surface.gdshader" if land_reference else "res://shaders/presentation/map/globe_water_surface.gdshader") as Shader if water else _shader
		if land_reference:
			material.set_shader_parameter("surface_expand_pixels", 0.0)
			if template.is_empty():
				material.set_shader_parameter("flag_weight", 0.0)
				material.set_shader_parameter("political_base_color", Vector3(107.0/255.0,128.0/255.0,117.0/255.0))
				if str(line.get("water_class","")) == "antarctic_land":
					var ice := HydrographyStyle.color("land_reference","antarctic_land")
					material.set_shader_parameter("political_base_color",Vector3(ice.r,ice.g,ice.b))
		material.set_shader_parameter("region_mode", true)
		if str(line.kind) == "ocean_reference": material.set_shader_parameter("surface_expand_pixels", 0.55)
		material.set_shader_parameter("face_data" if water else "line_data", texture)
		if water:
			material.set_shader_parameter("water_color", HydrographyStyle.color(str(line.kind), str(line.get("water_class", "lake"))))
		else:
			material.set_shader_parameter("stroke_color", HydrographyStyle.color(str(line.kind)))
			material.set_shader_parameter("stroke_width", HydrographyStyle.WIDTHS[str(line.kind)])
			material.set_shader_parameter("miter_limit", HydrographyStyle.miter_limit(str(line.kind)))
			material.set_shader_parameter("stroke_feather", HydrographyStyle.feather(str(line.kind)))
			material.set_shader_parameter("rail_style", rail_style if str(line.kind)=="rail" else 0)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item,_display_canvas if _display_canvas.is_valid() else _canvas)
		RenderingServer.canvas_item_set_draw_index(item, DRAW_ORDER-2 if str(line.kind) in ["land_reference", "ocean_reference"] else DRAW_ORDER-1 if str(line.kind)=="coast" else DRAW_ORDER)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		RenderingServer.canvas_item_add_mesh(item, mesh.get_rid(), Transform2D(), Color.WHITE, template.texture as RID if not template.is_empty() else RID())
		RenderingServer.canvas_item_set_visible(item, false)
		_batches.append({"item": item, "material": material, "geometry": geometry, "lod":line.lod, "kind":line.kind, "visible":false, "complete":false, "water": water, "water_class": line.get("water_class", "lake"), "faces": int(line.get("face_count",0)), "visual_template":template,"texture":template.get("texture",RID()),"visual_reference_feature":reference,"skin_values":{},"cull_axis":line.get("cull_axis",Vector3.ZERO),"cull_angle":line.get("cull_angle",PI)})
		# The installed geometry owns its mesh, texture and required picking data.
		# Encoded staging arrays are no longer needed by either content level.
		line.erase("payload")
		_cursor += 1
		if _cursor == _upload_chunks.size() or str(_upload_chunks[_cursor].lod) != str(line.lod):
			for batch: Dictionary in _batches:
				if str(batch.lod)==str(line.lod): batch["complete"] = true
			available_lods[str(line.lod)] = true
			ready = available_lods.has(_target)
			_trim_gpu()
		if _cursor < _upload_chunks.size() and Time.get_ticks_usec() - step_started >= PREPARE_BUDGET_USEC:
			return true
	# A final empty mesh still completes its LOD; it must replace the old region.
	for lod_name: String in _wanted:
		if _cpu_ready.has(lod_name):
			for batch: Dictionary in _batches:
				if str(batch.lod)==lod_name: batch["complete"] = true
			available_lods[lod_name] = true
	ready = available_lods.has(_target)
	preparing = false
	# Source geometry stays in Content. Another LOD is prepared on demand;
	# already installed LODs do not require a second CPU upload cache.
	_chunks.clear()
	_upload_chunks.clear()
	_cursor = 0
	_cpu_ready.clear()
	_queue_preparation()
	_trim_gpu()
	display_changed.emit()
	return true

func draw_labels(canvas: CanvasItem, font: Font) -> void:
	for label: Dictionary in _visible_labels:
		var name := str(label.feature.display_name)
		var current := label.get("font") as Font
		if current==null:
			current = GlobeLabels.font_for_name(font,name)
			label["font"] = current
		canvas.draw_string(current,(label.point as Vector2)+Vector2(7,-6),name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(0.94,0.93,0.82))

func _cancel_preparation() -> void:
	_generation_mutex.lock()
	_generation += 1
	_generation_mutex.unlock()

func _preparation_current(generation: int) -> bool:
	_generation_mutex.lock()
	var current := _generation == generation
	_generation_mutex.unlock()
	return current

func content_reference() -> LocalSpatialContent:
	return _content

func place(id: String) -> Dictionary:
	return _places.get(id, {}) as Dictionary

func has_visible_kind(kind: String) -> bool:
	for batch: Dictionary in _batches+_fallback_batches:
		if str(batch.kind)==kind and bool(batch.get("visible",false)): return true
	return false

func physical_land_at(point: Vector2, camera: RegionCamera, world_view: Dictionary) -> bool:
	var unit := camera.unit_at(point) if camera.active else Vector3.ZERO
	var basis := world_view.basis as Basis
	var center := world_view.center as Vector2
	var radius := float(world_view.radius)
	var normalized := (point-center)/maxf(radius,1.0)
	if not camera.active and normalized.length()>1.0: return false
	var inverse := basis.transposed()
	var origin := inverse*Vector3(normalized.x,-normalized.y,1.2)
	for batch: Dictionary in _batches+_fallback_batches:
		if str(batch.kind)!="land_reference" or not bool(batch.get("visible",false)): continue
		var geometry := batch.geometry as GlobeSurfaceBatch
		var distance := geometry.distance_region_point(unit,point,camera,0.55) if camera.active and not unit.is_zero_approx() else INF if camera.active else geometry.distance_screen_point(origin,inverse*Vector3.FORWARD,basis,point,center,radius,0.55)
		if distance<=0.55: return true
	return false

func update(camera: RegionCamera, controller: GlobeController, date: String, viewport_size: Vector2, commit_canvas: bool = true, world_view: Dictionary = {}) -> void:
	var regional := camera.active
	var geometry_ready := _resident and (not available_lods.is_empty() or not _fallback_batches.is_empty())
	var covered := strategic or _content!=null and _content.covers(RegionProjection.lon_lat(camera.valid_anchor(viewport_size).unit as Vector3))
	if not covered and regional and _content!=null:
		for visual: Dictionary in _content.landmark_visuals():
			var coordinate := (visual.geometry as Dictionary).coordinates as Array
			if Rect2(Vector2.ZERO,viewport_size).has_point(camera.project(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinate[0]),float(coordinate[1]))))): covered = true; break
	var show := _content!=null and (geometry_ready or not strategic and not _content.landmark_visuals().is_empty()) and (regional or strategic and not world_view.is_empty()) and _content.display_active_on(date) and covered
	var mpp := camera.km_per_pixel * 1000.0 if regional else float(world_view.get("mpp",8501.0))
	active_lod = _lod(mpp) if show else ""
	if show and not available_lods.has(active_lod):
		active_lod = str(available_lods.keys()[0]) if not available_lods.is_empty() else _fallback_lod
	visible_places.clear()
	label_rects.clear()
	var skins: Dictionary = {}
	var weights: Dictionary = {}
	var colors: Dictionary = {}
	if commit_canvas:
		for kind: String in ["coast","river","rail","land_reference","ocean_reference","lake","water_surface"]:
			var weight := MapScaleStyle.strategic_weight(kind,mpp) if strategic else MapScaleStyle.physical_weight(kind,mpp)
			if strategic and kind in ["land_reference","ocean_reference"]: weight = 1.0
			if kind == "rail" and not controller.strategic_rails_enabled: weight = 0.0
			if strategic and camera.local_active and kind!="river": weight = 0.0
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
		for batch: Dictionary in _batches + _fallback_batches: RenderingServer.canvas_item_set_parent(batch.item as RID,canvas)
	var view_center := camera.unit_at(viewport_size*0.5) if regional else controller.orientation().transposed()*Vector3.BACK
	var view_angle := (viewport_size.length()*0.5+8.0)*camera.km_per_pixel/6371.0088 if regional else PI*0.5
	for batch: Dictionary in _batches + _fallback_batches:
		if not commit_canvas: break
		var weight := float(weights[str(batch.kind)])
		# Generalized whole-feature land cannot overpaint dated partial politics.
		if strategic and str(batch.kind)=="land_reference" and str(batch.visual_reference_feature) in (world_view.get("scoped_features",[]) as Array): weight = 0.0
		var visible := show and _content.active_on(date) and bool(batch.get("complete",true)) and str(batch.lod) == active_lod and weight > 0.001
		# A load-time enclosing spherical cap rejects wholly offscreen batches.
		# This visits existing batches, never polygons, on controlled redraws.
		if visible and not view_center.is_zero_approx() and float(batch.cull_angle)<PI*0.5:
			visible = (batch.cull_axis as Vector3).angle_to(view_center) <= float(batch.cull_angle)+view_angle
		if visible != bool(batch.visible):
			RenderingServer.canvas_item_set_visible(batch.item as RID, visible)
			batch.visible = visible
		if visible:
			var material := batch.material as ShaderMaterial
			GlobeRenderer._parameter(batch,"region_mode",regional)
			var color := colors[str(batch.kind)] as Color
			if bool(batch.water):
				color = HydrographyStyle.color(str(batch.kind),str(batch.water_class))
				color.a *= weight
			GlobeRenderer._parameter(batch, "water_color" if bool(batch.water) else "stroke_color", color)
			var template := batch.get("visual_template", {}) as Dictionary
			if strategic and str(batch.kind)=="land_reference" and not str(batch.visual_reference_feature).is_empty():
				var owners := world_view.get("owners",{}) as Dictionary
				var surfaces := world_view.get("surfaces",{}) as Dictionary
				template = surfaces.get(str(owners.get(str(batch.visual_reference_feature),"")),template) as Dictionary
			var texture: RID = template.get("texture",RID())
			if bool(batch.water) and texture != batch.get("texture",RID()):
				RenderingServer.canvas_item_clear(batch.item as RID)
				RenderingServer.canvas_item_add_mesh(batch.item as RID,(batch.geometry as GlobeSurfaceBatch).mesh.get_rid(),Transform2D(),Color.WHITE,texture)
				batch["texture"] = texture
			if not template.is_empty():
				var reference := str(batch.visual_reference_feature)
				if not skins.has(reference):
					var values: Dictionary = {}
					var parameters := template.get("parameters", {}) as Dictionary
					for parameter: String in ["surface_color","political_base_color","political_focus_style","political_emphasis","flag_weight","political_weight","flag_bounds","flag_uv_scale","flag_uv_offset","flag_uv_rotation","relief_world","relief_region","relief_weight","relief_detail_weight"]:
						if parameters.has(parameter): values[parameter] = parameters[parameter]
					skins[reference] = values
				var skin := skins[reference] as Dictionary
				if (batch.skin_values as Dictionary) != skin:
					for parameter: String in skin: GlobeRenderer._parameter(batch,parameter,skin[parameter])
					batch.skin_values = skin
				GlobeRenderer._parameter(batch,"reference_opacity",weight)
			elif str(batch.kind)=="land_reference":
				GlobeRenderer._parameter(batch,"reference_opacity",weight)
				GlobeRenderer._parameter(batch,"political_weight",MapScaleStyle.political_weight(mpp) if controller.map_mode=="political" else 0.0)
				GlobeRenderer._parameter(batch,"relief_world",reference_relief.get("world"))
				GlobeRenderer._parameter(batch,"relief_region",reference_relief.get("region"))
				GlobeRenderer._parameter(batch,"relief_weight",MapScaleStyle.relief_weight(mpp,controller.map_mode) if reference_relief.has("world") else 0.0)
				GlobeRenderer._parameter(batch,"relief_detail_weight",MapScaleStyle.relief_detail_weight(mpp) if reference_relief.has("region") else 0.0)
			if not bool(batch.water): GlobeRenderer._parameter(batch, "rail_style", rail_style if str(batch.kind)=="rail" else 0)
			if strategic and str(batch.kind)=="rail": GlobeRenderer._parameter(batch,"stroke_width",MapScaleStyle.strategic_rail_width(mpp))
			if strategic: GlobeRenderer._parameter(batch, "paris_mask_weight", float(paris_mask_weights.get(str(batch.kind), 0.0)))
			var previous := batch.get("camera_values",[]) as Array
			if previous != camera_values:
				for index: int in range(camera_values.size()):
					if previous.size()!=camera_values.size() or previous[index] != camera_values[index]: material.set_shader_parameter(camera_parameters[index],camera_values[index])
				batch["camera_values"] = camera_values
			if batch.get("bounds_size",Vector2.ZERO) != viewport_size: GlobeRenderer._bounds(batch,viewport_size)
	var changed_frame := _frame != camera.tangent_frame
	if show:
		_frame = camera.tangent_frame
	if commit_canvas: _visible_labels.clear()
	var occupied: Array[Rect2] = reserved_label_rects.duplicate()
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
		if mpp > limit and not selected:
			continue
		var coordinates := feature.geometry.coordinates as Array
		var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
		var viewed := controller.orientation()*unit
		if not regional and viewed.z < 0.0: continue
		var point := camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel) if regional else GlobeProjection.sphere_screen(viewed,world_view.center as Vector2,float(world_view.radius))
		if not Rect2(Vector2.ZERO, viewport_size).has_point(point):
			continue
		visible_places[str(feature.id)] = point
		if not commit_canvas: continue
		if not controller.labels_enabled:
			continue
		if not label.has("text_size"):
			if label_font==null: continue
			var current := GlobeLabels.font_for_name(label_font,str(feature.display_name))
			label["font"] = current
			label["text_size"] = current.get_string_size(str(feature.display_name),HORIZONTAL_ALIGNMENT_LEFT,-1,13)
		var rect := Rect2(point + Vector2(7.0, -17.0), label.text_size as Vector2)
		var overlaps := false
		for other: Rect2 in occupied:
			if other.intersects(rect.grow(3.0)):
				overlaps = true
				break
		if overlaps and not selected:
			continue
		occupied.append(rect)
		label_rects.append(rect)
		label["point"] = point
		_visible_labels.append(label)

func clear() -> void:
	_cancel_preparation()
	_clear_fallback()
	for batch: Dictionary in _batches:
		RenderingServer.free_rid(batch.item as RID)
	_visible_labels.clear()
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
	preparing = _lod_thread != null
	_frame = Basis()
	_display_canvas = RID()
	_content = null
	_reference_visuals.clear()
	_reference_frames.clear()
	reference_relief = {}
	suppressed_places = {}
	reserved_label_rects.clear()

func dispose() -> void:
	clear()
	if _lod_thread != null:
		_lod_thread.wait_to_finish()
		_lod_thread = null

func _clear_fallback() -> void:
	for batch: Dictionary in _fallback_batches:
		RenderingServer.free_rid(batch.item as RID)
	_fallback_batches.clear()
	_fallback_lod = ""
