class_name RegionView
extends RefCounted
## Cached regional canvas; political ink records share CPU identity geometry.
signal landmark_display_changed
signal landmark_load_failed(message: String)
signal canvas_update_requested

var container: TextureRect
var viewport: SubViewport
var map_canvas: RID
var annotation_canvas: RID
var _map_background_layer: CanvasLayer
var _map_annotation_layer: CanvasLayer
var _local_overlay_layer: CanvasLayer
var _local_container: TextureRect
var _local_viewport: SubViewport
var _local_render_rect := Rect2()
var _local_render_generation: int = 0
var ready: bool = false
var _background: RID
var background: Dictionary = {}
var _labels: Array[Dictionary] = []
var country_label_rects: Array[Rect2] = []
const MINIATURE_ELEVATION: float = 0.9599310886 # 55 degrees; shared chart ground.
const MAX_CACHED_LANDMARK_SCENES: int = 2
const SETTLEMENT_MODULE_PATH: String = "res://assets/settlements/urban_landscape_r40.glb"
var landmark_screen_bounds: Dictionary = {}
var _landmark_scenes: Dictionary = {}
var _landmark_scene_order: Array[String] = []
var _landmark_pending: Dictionary = {}
var _landmark_wanted_paths: Dictionary = {}
var _landmark_failed: Dictionary = {}
var _landmark_instances: Dictionary = {}
var _landmark_root: Node3D
var _landmark_camera: Camera3D
var _landmark_light: DirectionalLight3D
var _local_camera_key: Array = []
var _local_camera_inverse := Transform3D.IDENTITY
var _landmark_view_key: Array = []
var _landmark_presented: Dictionary = {}
var _landmark_render_pending: bool = false
var _local_surface: MeshInstance3D
var _local_surface_mesh: ArrayMesh
var _local_surface_key: String = ""
var _local_surface_anchor := Vector2.ZERO
var _surface_reference: Dictionary = {}
var _surface_thread: Thread
var _surface_build_key: Array = []
var _surface_wanted_key: Array = []
var _surface_cpu_ready: Dictionary = {}
var _surface_generation: int = 0
var _surface_mutex := Mutex.new()
var _surface_vertices := PackedVector3Array()
var _surface_ray_vertices := PackedVector3Array()
var _surface_indices := PackedInt32Array()
var _surface_lines: MeshInstance3D
var _surface_line_mesh: ArrayMesh
var _surface_pick_chunks: Array[Dictionary] = []
var _surface_pick_pixel := Vector2(INF,INF)
var _surface_pick_unit := Vector3.ZERO
var _surface_pick_view: Array = []
var _local_elevation: float = MINIATURE_ELEVATION
var _surface_chart_frame := Basis()
var _surface_chart_anchor_km := Vector2.ZERO
var _surface_presented_key: String = ""
var _surface_water_vertices := PackedVector3Array()
var _surface_water_chunks: Array[Dictionary] = []
var _surface_water_mask: ImageTexture
var _surface_woodland_mask: ImageTexture
var _surface_height_texture: ImageTexture
const COVER_MASK_SIZE: int = 256
var _surface_material: ShaderMaterial
var _surface_style_key: Array = []
var _surface_texture_batch: Dictionary = {}
var _surface_strength_value: float = -1.0
var _surface_cover_mesh: ArrayMesh
var _surface_cover: MeshInstance3D
var _settlement_meshes: Dictionary = {}
var _settlement_nodes: Dictionary = {}
var _settlement_drawn: Dictionary = {}
var _settlement_presented: Dictionary = {}
var _settlement_pick_rects: Dictionary = {}
var _settlement_render_bounds := Rect2()
var _settlement_demanded: bool = false
var _woodland_positions: Array[Vector3] = []
var _woodland_nodes: Array[MultiMeshInstance3D] = []
var _internal_scene_load: RefCounted

func set_internal_load_test(active: bool) -> void:
	if not OS.has_feature("internal_landmark_preview") and not OS.has_feature("editor"): return
	if active and _internal_scene_load==null:
		var script := load("res://scripts/presentation/map/internal_preview_r41/scene_load.gd") as GDScript
		if script==null: return
		_internal_scene_load = script.new() as RefCounted
	if _internal_scene_load!=null:
		_internal_scene_load.set("enabled",active)
		if not active: _internal_scene_load.call("clear")
	_landmark_view_key.clear()
	canvas_update_requested.emit()

func internal_load_active() -> bool:
	return _internal_scene_load!=null and bool(_internal_scene_load.get("enabled"))

func initialize(parent: Control) -> void:
	# TextureRect does not override a child's UPDATE_ONCE on visibility changes.
	container = TextureRect.new()
	container.name = "RegionViewportContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.show_behind_parent = true
	container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.stretch_mode = TextureRect.STRETCH_SCALE
	container.visible = false
	parent.add_child(container)
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	# This full-sized target is permanently 2D. LOCAL has one bounded 3D
	# target inside the same chart, between background and annotation layers.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	container.texture = viewport.get_texture()
	_map_background_layer = CanvasLayer.new()
	_map_background_layer.layer = -1
	viewport.add_child(_map_background_layer)
	map_canvas = _map_background_layer.get_canvas()
	_local_overlay_layer = CanvasLayer.new()
	_local_overlay_layer.layer = 0
	viewport.add_child(_local_overlay_layer)
	_map_annotation_layer = CanvasLayer.new()
	_map_annotation_layer.layer = 1
	viewport.add_child(_map_annotation_layer)
	annotation_canvas = _map_annotation_layer.get_canvas()
	_background = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_background, map_canvas)
	RenderingServer.canvas_item_set_draw_index(_background, -100)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/presentation/map/relief_background.gdshader") as Shader
	RenderingServer.canvas_item_set_material(_background, material.get_rid())
	background = {"material": material, "item": _background}

func resize(viewport_size: Vector2) -> void:
	if container.size == viewport_size:
		return
	container.size = viewport_size
	viewport.size = Vector2i(viewport_size)
	if ready and container.visible: canvas_update_requested.emit()
	RenderingServer.canvas_item_clear(_background)
	RenderingServer.canvas_item_add_rect(_background, Rect2(Vector2.ZERO, viewport_size), Color(0.10, 0.14, 0.16))

func begin(_source: Dictionary) -> void:
	# Styles and national-line RIDs have one owner in GlobeRenderer.
	ready = true

func clear() -> void:
	release_landmarks()
	clear_labels()
	background.erase("surface_appearance_style")
	ready = false

func clear_labels() -> void:
	_labels.clear()
	country_label_rects.clear()

func prepare_labels(candidates: Array[Dictionary], font: Font, country_font: Font = null) -> void:
	_labels = candidates
	_labels.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.rank)<int(b.rank))
	for label: Dictionary in _labels:
		var primary := country_font if not bool(label.place) and country_font != null else font
		label["font"] = GlobeLabels.font_for_name(primary,str(label.text))
		label["sizes"] = {}
		var font_size := int(label.font_size)
		label["text_size"] = (label.font as Font).get_string_size(str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		label.sizes[font_size] = label.text_size

func update_labels(canvas: CanvasItem, camera: RegionCamera, controller: GlobeController, font: Font, viewport_size: Vector2, shard_places: Dictionary = {}, reserved_labels: Array[Rect2] = []) -> void:
	country_label_rects.clear()
	var occupied: Array[Rect2] = reserved_labels.duplicate()
	var axes := RegionProjection.screen_axes(camera.bearing)
	var bounds := Rect2(Vector2.ZERO, viewport_size)
	if not controller.labels_enabled or camera.local_active: return
	var priorities: Array[int] = []
	if not controller.selected_polity_id.is_empty() or not controller.selected_place_id.is_empty(): priorities.append(0)
	if not controller.hovered_polity_id.is_empty() or not controller.hovered_place_id.is_empty(): priorities.append(1)
	priorities.append(2)
	for priority: int in priorities:
		for label: Dictionary in _labels:
			var place := bool(label.place)
			if place and shard_places.has(str(label.id)):
				continue
			var selected := str(label.id) == (controller.selected_place_id if place else controller.selected_polity_id)
			var hovered := str(label.id) == (controller.hovered_place_id if place else controller.hovered_polity_id)
			var order := 0 if selected else 1 if hovered else 2
			if priority != order:
				continue
			var detailed := controller.labels_enabled and (camera.km_per_pixel <= RegionCamera.PLACE_LABEL_KM_PER_PIXEL if place else true)
			if not place and str(label.id)==controller.player_polity_id and camera.km_per_pixel<0.7: continue
			if not selected and not hovered and not place:
				if bool(label.get("geography",false)) and int(label.rank)>12 and camera.km_per_pixel>3.0: continue
			if not detailed and not selected and not hovered:
				continue
			var point := camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel)
			if not place and label.has("candidates"):
				var candidates := label.candidates as Array[Dictionary]
				var index := int(label.candidate_index)
				if candidates.size()>1:
					var distance := INF
					for candidate_index: int in range(candidates.size()):
						var candidate_point := camera.origin + axes * ((candidates[candidate_index].km as Vector2) / camera.km_per_pixel)
						if bounds.grow(-40.0).has_point(candidate_point) and candidate_point.distance_squared_to(bounds.get_center()) < distance:
							distance = candidate_point.distance_squared_to(bounds.get_center())
							index = candidate_index
					label.candidate_index = index
				label.km = candidates[index].km
				point = camera.origin + axes * ((label.km as Vector2) / camera.km_per_pixel)
				var room := minf(float(candidates[index].clearance_km) / camera.km_per_pixel, viewport_size.y * 0.35)
				if room<34.0 and not selected and not hovered: continue
				var font_size := clampi(int(room * 0.14 / 4.0) * 4, 16, 24)
				if font_size != int(label.font_size):
					label.font_size = font_size
					if not (label.sizes as Dictionary).has(font_size): (label.sizes as Dictionary)[font_size] = (label.font as Font).get_string_size(str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1.0,font_size)
					label.text_size = (label.sizes as Dictionary)[font_size]
			var offset := Vector2(7.0, -6.0) if place else Vector2(-(label.text_size as Vector2).x * 0.5, float(label.font_size)*0.35)
			var rect := Rect2(point + offset - Vector2(0.0, float(label.font_size)), (label.text_size as Vector2) + Vector2(0.0, 3.0))
			if not bounds.encloses(rect) or occupied.size() >= 42:
				continue
			var overlaps := false
			for existing: Rect2 in occupied:
				if existing.intersects(rect.grow(3.0)):
					overlaps = true
					break
			if overlaps:
				continue
			occupied.append(rect)
			if not place: country_label_rects.append(rect)
			var label_font := label.font as Font
			label_font.draw_string_outline(canvas.get_canvas_item(),point+offset,str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(label.font_size),1,Color(0.08,0.12,0.13,0.45))
			canvas.draw_string(label_font,point+offset,str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(label.font_size),Color(0.92,0.88,0.77))

func dispose() -> void:
	clear()
	if _surface_thread!=null:
		_surface_thread.wait_to_finish()
		_surface_thread = null
	_landmark_scenes.clear()
	_landmark_scene_order.clear()
	_landmark_pending.clear()
	_local_surface_mesh = null
	_surface_reference.clear()
	if _background.is_valid():
		RenderingServer.free_rid(_background)

func landmark_preparing() -> bool:
	return _surface_thread!=null or not _landmark_pending.is_empty() or (_internal_scene_load!=null and bool(_internal_scene_load.call("preparing")))

func landmark_visible(id: String) -> bool:
	return _local_container!=null and _local_container.visible and _landmark_presented.has(id) and _landmark_instances.has(id) and (_landmark_instances[id] as Node3D).visible and landmark_screen_bounds.has(id)

func settlement_visible(id: String) -> bool:
	return _local_container!=null and _local_container.visible and _settlement_presented.has(id) and _settlement_drawn.has(id)

func settlement_at(pixel: Vector2) -> String:
	for id: String in _settlement_pick_rects:
		if not settlement_visible(id): continue
		for rectangle: Rect2 in _settlement_pick_rects[id] as Array:
			if rectangle.has_point(pixel): return id
	return ""

func _landmark_failed_load(path: String) -> void:
	_landmark_failed[path] = true
	landmark_load_failed.emit("地标模型读取失败，暂保留地图剪影。")

func prepare_landmarks() -> bool:
	var completed := _poll_surface_preparation()
	if _internal_scene_load!=null: completed = bool(_internal_scene_load.call("poll")) or completed
	for path: String in _landmark_pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(path) as PackedScene
			if scene!=null:
				# A retired LOCAL composition does not retain a late bundle result.
				if (_settlement_demanded if path==SETTLEMENT_MODULE_PATH else _landmark_wanted_paths.has(path)):
					_landmark_scenes[path] = scene
					_touch_landmark_scene(path)
			else: _landmark_failed_load(path)
		else: _landmark_failed_load(path)
		_landmark_pending.erase(path)
		completed = true
	_trim_landmark_scenes()
	if completed: _landmark_view_key.clear()
	return completed

func update_landmarks(visuals: Array[Dictionary], camera: RegionCamera, viewport_size: Vector2, surface: Dictionary = {}, reference_lines: Array[Dictionary] = [], settlements: Array[Dictionary] = [], covers: Array[Dictionary] = []) -> void:
	var wanted: Dictionary = {}
	if ready and camera.active and camera.local_active:
		for visual: Dictionary in visuals:
			var limit := model_limit_mpp(visual)*(1.35 if _landmark_instances.has(str(visual.id)) else 1.0)
			if camera.local_place_id!=str(visual.get("local_anchor_id",visual.anchor_place_id)) or camera.km_per_pixel*1000.0>limit: continue
			wanted[str(visual.id)] = visual
	_landmark_wanted_paths.clear()
	for visual: Dictionary in wanted.values(): _landmark_wanted_paths[str(visual.model_path)] = true
	for id: String in _landmark_instances.keys():
		if wanted.has(id): continue
		var instance := _landmark_instances[id] as Node3D
		instance.visible = false
		instance.queue_free()
		_landmark_instances.erase(id)
		_landmark_presented.erase(id)
		landmark_screen_bounds.erase(id)
	for id: String in wanted:
		var visual := wanted[id] as Dictionary
		var path := str(visual.model_path)
		if _landmark_failed.has(path): continue
		if _landmark_instances.has(id):
			if _landmark_scenes.has(path): _touch_landmark_scene(path)
			continue
		if not _landmark_scenes.has(path):
			if not _landmark_pending.has(path) and not _landmark_failed.has(path):
				if ResourceLoader.load_threaded_request(path,"PackedScene")==OK:
					_landmark_pending[path] = true
				else: _landmark_failed_load(path)
			continue
		_touch_landmark_scene(path)
		var node := (_landmark_scenes[path] as PackedScene).instantiate()
		var instance := node as Node3D
		if instance==null:
			node.free()
			_landmark_failed_load(path)
			continue
		if visual.has("model_metric_scale"):
			instance = _metric_landmark(instance,visual)
		_enable_landmark_3d()
		_landmark_root.add_child(instance)
		_landmark_instances[id] = instance
		_landmark_view_key.clear()
	_local_elevation = elevation_at(camera)
	_update_surface_demand(surface,camera,viewport_size,reference_lines,covers)
	var settlement_wanted := _settlement_demand(settlements,camera,viewport_size)
	_trim_landmark_scenes()
	if _landmark_instances.is_empty() and _local_surface==null:
		if _internal_scene_load!=null: _internal_scene_load.call("clear")
		if _surface_wanted_key.is_empty() and wanted.is_empty(): release_landmarks()
		elif _local_container!=null and _local_container.visible:
			# The old projection's geometry has retired while its successor waits.
			# A cached image of that old scene is not valid transition content.
			_local_container.visible = false
			_local_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_landmark_presented.clear()
			_settlement_presented.clear()
			_surface_presented_key = ""
			canvas_update_requested.emit()
		return
	var key: Array = [camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,viewport_size,_landmark_instances.keys(),_local_surface!=null,settlement_wanted.keys(),_settlement_meshes.size()]
	if key==_landmark_view_key: return
	_landmark_view_key = key
	_update_local_camera(camera,viewport_size)
	if _local_surface!=null: _update_surface_pose(camera,viewport_size)
	# Match the native terrain's geographic two-light mean with the existing
	# single model light. Rotating the chart must not rotate its lit slope.
	var light_unit := GlobeProjection.lon_lat_to_unit(_local_surface_anchor) if _local_surface!=null else camera.tangent_frame.z
	var light_frame := _chart_transform(light_unit,camera,viewport_size).basis*_geographic_basis(light_unit,camera,0.0)
	var light_direction := (light_frame*Vector3(0.05,0.70710678,-0.5)).normalized()
	_landmark_light.quaternion = Quaternion(Vector3.FORWARD,-light_direction)
	for id: String in _landmark_instances:
		var visual := wanted[id] as Dictionary
		_update_landmark_pose(_landmark_instances[id] as Node3D,visual,camera,viewport_size)
	_update_settlement_batches(settlement_wanted,camera,viewport_size)
	if _internal_scene_load!=null: _internal_scene_load.call("update",self,camera,viewport_size)
	_update_local_render_rect(camera,viewport_size)
	if _local_viewport==null or not _local_container.visible: return
	_local_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas_update_requested.emit()
	if not _landmark_render_pending:
		_landmark_render_pending = true
		RenderingServer.frame_post_draw.connect(_landmark_frame_ready.bind(_local_render_generation),CONNECT_ONE_SHOT)

func _metric_landmark(source: Node3D, visual: Dictionary) -> Node3D:
	# Internal pilot GLBs use schematic units and include decorative ground.
	# Adapt only these declared instances, once on installation. Keep their
	# PackedScene immutable and omit invented terrain/water from the map.
	var allowed := visual.model_surface_indices as Array
	var pending: Array[Node] = [source]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		for child: Node in node.get_children(): pending.append(child)
		if not node is MeshInstance3D: continue
		var geometry := node as MeshInstance3D
		var original := geometry.mesh as ArrayMesh
		if original==null: continue
		var mesh := ArrayMesh.new()
		for raw_index: Variant in allowed:
			var index := int(raw_index)
			if index<0 or index>=original.get_surface_count(): continue
			mesh.add_surface_from_arrays(original.surface_get_primitive_type(index),original.surface_get_arrays(index))
			mesh.surface_set_material(mesh.get_surface_count()-1,original.surface_get_material(index))
		geometry.mesh = mesh
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var scale := float(visual.model_metric_scale)
	var origin := visual.model_origin_units as Array
	source.transform = Transform3D(Basis.from_scale(Vector3.ONE*scale),-Vector3(float(origin[0]),float(origin[1]),float(origin[2]))*scale)*source.transform
	var metric := Node3D.new()
	metric.name = "MetricLandmarkReference"
	metric.add_child(source)
	return metric

func _update_local_camera(camera: RegionCamera, viewport_size: Vector2) -> void:
	# A single orthographic miniature camera uses this existing map viewport.
	# Ground positions are obtained from RegionCamera.project, not a new chart.
	_local_elevation = elevation_at(camera)
	if not _local_render_rect.has_area(): _local_render_rect = Rect2(Vector2.ZERO,viewport_size)
	var key: Array = [viewport_size,_local_elevation,_local_render_rect]
	if _local_camera_key==key: return
	_local_camera_key = key
	_landmark_camera.size = _local_render_rect.size.y
	_landmark_camera.h_offset = _local_render_rect.get_center().x-viewport_size.x*0.5
	_landmark_camera.v_offset = viewport_size.y*0.5-_local_render_rect.get_center().y
	# The existing chart's ground scale stays fixed while true vertical height
	# gains an oblique view. All ground layers use _chart_transform together.
	var distance := maxf(2048.0,viewport_size.length()*2.0)
	_landmark_camera.position = Vector3(0,sin(_local_elevation),cos(_local_elevation))*distance
	_landmark_camera.rotation = Vector3(-_local_elevation,0,0)
	_landmark_camera.far = distance*4.0
	_landmark_camera.force_update_transform()
	_local_camera_inverse = _landmark_camera.get_camera_transform().affine_inverse()

func _landmark_frame_ready(generation: int) -> void:
	if generation!=_local_render_generation: return
	_landmark_render_pending = false
	if _landmark_root==null or _landmark_camera==null or not _landmark_camera.is_current() or not container.visible or _local_viewport==null or not _local_container.visible: return
	var presented: Dictionary = {}
	for id: String in _landmark_instances:
		if (_landmark_instances[id] as Node3D).visible and landmark_screen_bounds.has(id) and (landmark_screen_bounds[id] as Rect2).intersects(Rect2(Vector2.ZERO,container.size)): presented[id] = true
	var changed := presented!=_landmark_presented or _settlement_presented!=_settlement_drawn or _surface_presented_key!=_local_surface_key
	_landmark_presented = presented
	_settlement_presented = _settlement_drawn.duplicate()
	_surface_presented_key = _local_surface_key
	if changed: landmark_display_changed.emit()

func _chart_pixel(position: Vector3) -> Vector2:
	# Same orthographic camera basis, in chart pixels. It is independent of
	# target allocation, so the first crop needs no full-window 3D allocation.
	var view := _local_camera_inverse*position
	return Vector2(view.x,-view.y)+_local_render_rect.get_center()

func _update_local_render_rect(camera: RegionCamera, viewport_size: Vector2) -> void:
	var bounds := Rect2()
	var initialized := false
	var nodes: Array[GeometryInstance3D] = []
	for node: MeshInstance3D in [_local_surface,_surface_cover,_surface_lines]:
		if node!=null and node.visible: nodes.append(node)
	for node: GeometryInstance3D in nodes:
		var box := node.get_aabb()
		for corner: int in range(8):
			var pixel := _chart_pixel(node.transform*box.get_endpoint(corner))
			bounds = bounds.expand(pixel) if initialized else Rect2(pixel,Vector2.ZERO)
			initialized = true
	for node: MultiMeshInstance3D in _woodland_nodes:
		if not node.visible: continue
		var tree_bounds := node.get_aabb()
		for corner: int in range(8):
			var pixel := _chart_pixel(node.transform*tree_bounds.get_endpoint(corner))
			bounds = bounds.expand(pixel) if initialized else Rect2(pixel,Vector2.ZERO)
			initialized = true
	if _settlement_render_bounds.has_area():
		bounds = bounds.merge(_settlement_render_bounds) if initialized else _settlement_render_bounds
		initialized = true
	if _internal_scene_load!=null:
		var extra := _internal_scene_load.call("render_bounds",self) as Rect2
		if extra.has_area():
			bounds = bounds.merge(extra) if initialized else extra
			initialized = true
	for id: String in landmark_screen_bounds:
		if not _landmark_instances.has(id) or not (_landmark_instances[id] as Node3D).visible: continue
		bounds = bounds.merge(landmark_screen_bounds[id] as Rect2) if initialized else landmark_screen_bounds[id] as Rect2
		initialized = true
	var visible_bounds := bounds.grow(8.0).intersection(Rect2(Vector2.ZERO,viewport_size)) if initialized else Rect2()
	_local_container.visible = visible_bounds.has_area()
	if not _local_container.visible:
		_local_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		canvas_update_requested.emit()
		return
	# Pixel-for-pixel crop, not resolution scaling. Quantized dimensions and
	# a small guard keep ordinary pan from reallocating the target each frame.
	var target_size := (visible_bounds.size/128.0).ceil()*128.0
	target_size = target_size.min(viewport_size).max(Vector2(2,2))
	var origin := (visible_bounds.get_center()-target_size*0.5).floor().clamp(Vector2.ZERO,(viewport_size-target_size).max(Vector2.ZERO))
	var next := Rect2(origin,target_size)
	if _local_render_rect==next and _local_container.size==next.size: return
	_local_render_rect = next
	_local_container.position = next.position
	if _local_container.size!=next.size: _local_container.size = next.size
	if _local_viewport.size!=Vector2i(next.size): _local_viewport.size = Vector2i(next.size)
	_update_local_camera(camera,viewport_size)

func elevation_at(camera: RegionCamera) -> float:
	var elevation := MINIATURE_ELEVATION
	if not _surface_reference.is_empty():
		var d := _surface_reference
		var step := float(d.step_degrees)*111195.0
		var span := minf((int(d.width)-1)*step*cos(deg_to_rad(float((d.anchor_lon_lat as Array)[1]))),(int(d.height)-1)*step)
		var relief := float(d.get("height_max_m",0.0))-float(d.get("height_min_m",0.0))
		# A narrow mountain survey is not a complete oblique landscape. Keep
		# its true heights, but limit the camera's screen-space vertical reach.
		if relief>span*0.25: elevation = maxf(elevation,acos(clampf(span*0.25/relief,0.0,1.0)))
	return lerpf(elevation,PI*0.5,smoothstep(110.0,RegionCamera.LOCAL_ENTER_KM_PER_PIXEL*1000.0,camera.km_per_pixel*1000.0))

func _chart_transform(unit: Vector3, camera: RegionCamera, viewport_size: Vector2) -> Transform3D:
	var axes := RegionProjection.screen_axes(camera.bearing)
	var mpp := camera.km_per_pixel*1000.0
	var sine := sin(elevation_at(camera))
	var offset := camera.project(unit)-viewport_size*0.5
	# The oblique camera's ground foreshortening is compensated for every
	# layer. Zero height maps to the same REGION pixel; true height remains Y.
	var basis := Basis(Vector3(axes.x.x,0,axes.x.y/sine)/mpp,Vector3.UP/mpp,Vector3(-axes.y.x,0,-axes.y.y/sine)/mpp)
	return Transform3D(basis,Vector3(offset.x,0,offset.y/sine))

func _geographic_basis(unit: Vector3, camera: RegionCamera, heading: float) -> Basis:
	var axes := RegionProjection.tangent_axes(unit,camera.tangent_frame)
	return Basis(Vector3(axes.x.x,0,-axes.x.y),Vector3.UP,Vector3(-axes.y.x,0,axes.y.y))*Basis(Vector3.UP,heading)

func _surface_strength(camera: RegionCamera) -> float:
	if _surface_reference.is_empty(): return 0.0
	var limit := _terrain_limit_mpp(_surface_reference)
	return 1.0-smoothstep(limit*0.75,limit*1.35,camera.km_per_pixel*1000.0)

static func _terrain_limit_mpp(surface: Dictionary) -> float:
	# A native window must have a useful map footprint before it enables 3D.
	# Coarse ETOPO remains the continuous chart outside this close band.
	var step := float(surface.step_degrees)*111195.0
	var latitude := float((surface.anchor_lon_lat as Array)[1])
	var span := minf((int(surface.width)-1)*step*cos(deg_to_rad(latitude)),(int(surface.height)-1)*step)
	return minf(float(surface.display_max_mpp),clampf(span/96.0,4.0,24.0))

func coverage_description(camera: RegionCamera) -> Dictionary:
	if _local_surface==null or not camera.local_active or _surface_presented_key!=_local_surface_key: return {}
	if _surface_strength(camera)<=0.001: return {}
	var d := _surface_reference
	var extent := Vector2(int(d.width)-1,int(d.height)-1)
	var west := float(d.west_cell_centre)
	var north := float(d.north_cell_centre)
	return {"bounds":Vector4(west,north-extent.y*float(d.step_degrees),west+extent.x*float(d.step_degrees),north),"edge":Vector2(maxf(2.0,extent.x*0.12)/extent.x,maxf(2.0,extent.y*0.12)/extent.y),"water":_surface_water_mask,"height":_surface_height_texture,"strength":_surface_strength(camera),"vertical_pixels":cos(elevation_at(camera))/(camera.km_per_pixel*1000.0),"local_lines":_surface_line_mesh!=null and not bool(d.get("river_chart_only",false))}

func set_map_style(style: Dictionary) -> void:
	var key: Array = [style.tone,style.weight,style.relief]
	if _surface_material==null or _surface_style_key==key: return
	_surface_style_key = key
	# Political/economic display ink is a final composition, not surface state.
	_surface_material.set_shader_parameter("map_ink_tone",style.tone)
	_surface_material.set_shader_parameter("map_ink_weight",style.weight)
	_surface_material.set_shader_parameter("cartographic_relief_weight",style.relief)
	if _local_viewport!=null: _local_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas_update_requested.emit()

func set_surface_reference(surface: Dictionary) -> void:
	if _surface_material==null: return
	if _surface_texture_batch.get("material")!=_surface_material:
		_surface_texture_batch = {"material":_surface_material}
	if _surface_texture_batch.get("surface_reference",null)==surface: return
	GlobeRenderer._surface_uniforms(_surface_texture_batch,surface)
	if _local_viewport!=null: _local_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	canvas_update_requested.emit()

func chart_screen_point(unit: Vector3, camera: RegionCamera) -> Vector2:
	var point := camera.project(unit)
	var coordinate := RegionProjection.lon_lat(unit)
	if camera.local_active and _local_surface!=null and _surface_strength(camera)>0.001 and _surface_contains(coordinate):
		point.y -= _surface_ground_y(coordinate)*cos(elevation_at(camera))/(camera.km_per_pixel*1000.0)
	return point

func _settlement_demand(features: Array[Dictionary], camera: RegionCamera, viewport_size: Vector2) -> Dictionary:
	var wanted: Dictionary = {}
	if ready and camera.local_active and _local_surface!=null:
		for feature: Dictionary in features:
			var layout := feature.miniature_layout as Dictionary
			if str(layout.anchor_place_id)!=camera.local_place_id or camera.km_per_pixel*1000.0>float(layout.max_mpp)*1.4: continue
			var raw := feature.geometry.coordinates as Array
			var coordinate := Vector2(float(raw[0]),float(raw[1]))
			if not _surface_contains(coordinate): continue
			var point := camera.project(GlobeProjection.lon_lat_to_unit(coordinate))
			if Rect2(Vector2.ZERO,viewport_size).grow(500.0/(camera.km_per_pixel*1000.0)+128.0).has_point(point): wanted[str(feature.id)] = feature
	_settlement_demanded = not wanted.is_empty()
	if not _settlement_demanded:
		_release_settlements()
		return wanted
	if not _settlement_meshes.is_empty(): return wanted
	if _landmark_failed.has(SETTLEMENT_MODULE_PATH): return wanted
	if not _landmark_scenes.has(SETTLEMENT_MODULE_PATH):
		if not _landmark_pending.has(SETTLEMENT_MODULE_PATH):
			if ResourceLoader.load_threaded_request(SETTLEMENT_MODULE_PATH,"PackedScene")==OK: _landmark_pending[SETTLEMENT_MODULE_PATH] = true
			else: _landmark_failed_load(SETTLEMENT_MODULE_PATH)
		return wanted
	var source := (_landmark_scenes[SETTLEMENT_MODULE_PATH] as PackedScene).instantiate()
	var nodes: Array[Node] = [source]
	while not nodes.is_empty():
		var node := nodes.pop_back() as Node
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh!=null: _settlement_meshes[str(node.name)] = mesh
		for child: Node in node.get_children(): nodes.append(child)
	# Only the six shared meshes/material remain. No per-building scene copies.
	source.free()
	_landmark_scenes.erase(SETTLEMENT_MODULE_PATH)
	_landmark_scene_order.erase(SETTLEMENT_MODULE_PATH)
	_landmark_view_key.clear()
	return wanted

func _update_settlement_batches(features: Dictionary, camera: RegionCamera, viewport_size: Vector2) -> void:
	var transforms: Dictionary = {}
	var tints: Dictionary = {}
	var common := _local_surface.transform if _local_surface!=null else Transform3D.IDENTITY
	var retaining_lod := false
	_settlement_drawn.clear()
	_settlement_pick_rects.clear()
	_settlement_render_bounds = Rect2()
	if _local_surface!=null and _landmark_camera!=null:
		for feature: Dictionary in features.values():
			var layout := feature.miniature_layout as Dictionary
			var mpp := camera.km_per_pixel*1000.0
			var lod_weight := 1.0-smoothstep(float(layout.max_mpp)*0.75,float(layout.max_mpp),mpp)
			if lod_weight<=0.02:
				retaining_lod = true
				continue
			var raw := feature.geometry.coordinates as Array
			var geographic := RegionProjection.frame(Vector2(float(raw[0]),float(raw[1])))
			var placement_index := 0
			for placement: Dictionary in layout.placements as Array:
				placement_index += 1
				var module := str(placement.module)
				if mpp>=float(layout.get("lod_switch_mpp",8.0)) and _settlement_meshes.has(module+"_far"): module += "_far"
				if not _settlement_meshes.has(module): continue
				var offset := placement.offset_m as Array
				var unit := RegionProjection.inverse(Vector2(float(offset[0]),float(offset[1]))/1000.0,geographic)
				var coordinate := RegionProjection.lon_lat(unit)
				if not _surface_contains(coordinate): continue
				var metric := (RegionProjection.forward(unit,_surface_chart_frame)-_surface_chart_anchor_km)*1000.0
				var local_pose := Transform3D(Basis.IDENTITY,Vector3(metric.x,_surface_ground_y(coordinate),-metric.y))
				var pose := common*local_pose
				var position := pose.origin
				var pixel := _chart_pixel(position)
				if not Rect2(Vector2.ZERO,viewport_size).grow(48.0).has_point(pixel): continue
				var mesh := _settlement_meshes[module] as Mesh
				var scale := placement.scale as Array
				var dimensions := Vector3(float(scale[0]),float(scale[1]),float(scale[2]))
				# Small deterministic size/ink differences, within the declared
				# maximum footprints. No coordinate randomisation or new buildings.
				dimensions *= Vector3(0.90+0.03*(placement_index%3),0.88+0.04*(placement_index%4),0.92+0.025*(placement_index%3))
				var height := (mesh.get_aabb() as AABB).size.y*dimensions.y
				var local_mpp := camera.km_per_pixel*1000.0
				var enlargement := clampf(float(layout.target_height_px)*local_mpp/maxf(height*cos(_local_elevation),1.0),1.0,float(layout.scale_max))*lod_weight
				# Rigid module: same east/north chart and true vertical as landmarks.
				local_pose.basis = _geographic_basis(unit,camera,deg_to_rad(float(placement.heading_degrees)))*Basis.from_scale(dimensions*enlargement)
				pose = common*local_pose
				var box := mesh.get_aabb()
				var rectangle := Rect2(pixel,Vector2.ZERO)
				for corner: int in range(8): rectangle = rectangle.expand(_chart_pixel(pose*box.get_endpoint(corner)))
				var obscures_landmark := false
				for bounds: Rect2 in landmark_screen_bounds.values():
					if rectangle.intersects(bounds.grow(3.0)):
						obscures_landmark = true
						break
				if obscures_landmark: continue
				_settlement_render_bounds = _settlement_render_bounds.merge(rectangle) if _settlement_render_bounds.has_area() else rectangle
				if not transforms.has(module):
					transforms[module] = []
					tints[module] = []
				(transforms[module] as Array).append(local_pose)
				(tints[module] as Array).append(Color(0.93+0.02*(placement_index%3),0.95+0.015*(placement_index%3),0.94+0.02*(placement_index%3)))
				if lod_weight>0.15:
					var id := str(feature.id)
					_settlement_drawn[id] = true
					if not _settlement_pick_rects.has(id): _settlement_pick_rects[id] = []
					(_settlement_pick_rects[id] as Array).append(rectangle.grow(2.0))
	for module: String in _settlement_nodes.keys():
		if transforms.has(module): continue
		var retired := _settlement_nodes[module] as MultiMeshInstance3D
		retired.visible = false
		if retaining_lod: continue # bounded current-LOCAL LOD handoff
		retired.multimesh = null
		retired.queue_free()
		_settlement_nodes.erase(module)
	for module: String in transforms:
		if not _settlement_nodes.has(module):
			var node := MultiMeshInstance3D.new()
			node.name = "Shared_"+module
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.use_colors = true
			node.multimesh.mesh = _settlement_meshes[module] as Mesh
			_landmark_root.add_child(node)
			_settlement_nodes[module] = node
		var node := _settlement_nodes[module] as MultiMeshInstance3D
		var poses := transforms[module] as Array
		node.visible = true
		if node.transform!=common: node.transform = common
		var resized: bool = node.multimesh.instance_count!=poses.size()
		if resized: node.multimesh.instance_count = poses.size()
		var previous_poses := node.get_meta("poses",[]) as Array
		var inks := tints[module] as Array
		var colors_changed: bool = resized or node.get_meta("inks",[])!=inks
		if colors_changed: node.set_meta("inks",inks)
		for index: int in range(poses.size()):
			if resized or index>=previous_poses.size() or previous_poses[index]!=poses[index]: node.multimesh.set_instance_transform(index,poses[index] as Transform3D)
			if colors_changed: node.multimesh.set_instance_color(index,inks[index] as Color)

		node.set_meta("poses",poses)

func _release_settlements() -> void:
	_settlement_demanded = false
	for node: MultiMeshInstance3D in _settlement_nodes.values():
		node.visible = false
		node.multimesh = null
		node.queue_free()
	_settlement_nodes.clear()
	_settlement_meshes.clear()
	_settlement_drawn.clear()
	_settlement_presented.clear()
	_settlement_pick_rects.clear()
	_settlement_render_bounds = Rect2()
	_landmark_scenes.erase(SETTLEMENT_MODULE_PATH)
	_landmark_scene_order.erase(SETTLEMENT_MODULE_PATH)

func _enable_landmark_3d() -> void:
	if _landmark_root!=null: return
	_local_container = TextureRect.new()
	_local_container.name = "LocalRenderCrop"
	_local_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_local_container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_local_container.stretch_mode = TextureRect.STRETCH_SCALE
	_local_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var composite := CanvasItemMaterial.new()
	composite.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	composite.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_local_container.material = composite
	_local_container.size = Vector2(2,2)
	_local_overlay_layer.add_child(_local_container)
	_local_viewport = SubViewport.new()
	_local_viewport.name = "LocalGeometryTarget"
	_local_viewport.size = Vector2i(2,2)
	_local_viewport.transparent_bg = true
	_local_viewport.world_2d = World2D.new()
	_local_viewport.world_3d = World3D.new()
	_local_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_local_container.add_child(_local_viewport)
	_local_container.texture = _local_viewport.get_texture()
	_local_render_rect = Rect2(Vector2.ZERO,container.size)
	_landmark_root = Node3D.new()
	_landmark_root.name = "LocalMiniatures"
	_local_viewport.add_child(_landmark_root)
	_landmark_camera = Camera3D.new()
	_landmark_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_landmark_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_landmark_camera.near = 0.1
	var environment := Environment.new()
	# No chart meshes, labels or political canvases in the 3D target.
	# The existing full-size 2D cache composites this bounded texture once.
	# A transparent target must clear RGB as well as Alpha. Project's dark
	# clear RGB is not a valid premultiplied transparent background.
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.76,0.78,0.72)
	environment.ambient_light_energy = 0.45
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_local_viewport.find_world_3d().environment = environment
	_landmark_root.add_child(_landmark_camera)
	_landmark_camera.current = true
	_landmark_light = DirectionalLight3D.new()
	_landmark_light.light_color = Color(1.0,0.95,0.85)
	_landmark_light.light_energy = 0.9
	_landmark_light.shadow_enabled = false
	_landmark_root.add_child(_landmark_light)

func _update_landmark_pose(instance: Node3D, visual: Dictionary, camera: RegionCamera, viewport_size: Vector2) -> void:
	# Keep the chart symbol until the requested terrain has an installed frame.
	instance.visible = _surface_wanted_key.is_empty() or (_local_surface!=null and _local_surface_key==str(_surface_wanted_key[0]))
	var coordinates := visual.get("display_lon_lat",(visual.geometry as Dictionary).coordinates) as Array
	var location := Vector2(float(coordinates[0]),float(coordinates[1]))
	var unit := GlobeProjection.lon_lat_to_unit(location)
	var pose := _chart_transform(unit,camera,viewport_size)
	var ground_y := _surface_ground_y(location) if _surface_contains(location) else 0.0
	# A bridge deck uses the higher sampled approach ground as its datum.
	# These are existing modern DEM samples, never inferred historical water levels.
	var approaches := visual.get("ground_samples_lon_lat",[]) as Array
	if approaches.size()==2:
		var a := Vector2(float(approaches[0][0]),float(approaches[0][1]))
		var b := Vector2(float(approaches[1][0]),float(approaches[1][1]))
		if _surface_contains(a) and _surface_contains(b):
			ground_y = maxf(_surface_ground_y(a),_surface_ground_y(b))-float(visual.get("model_ground_datum_m",0.0))
	pose.origin += pose.basis*Vector3(0,ground_y,0)
	var mpp := camera.km_per_pixel*1000.0
	if visual.has("model_lod_switch_mpp"):
		# Both LODs are in one admitted PackedScene; only one draws at a time.
		var near := instance.get_node_or_null("Near") as Node3D
		var far := instance.get_node_or_null("Far") as Node3D
		if near!=null and far!=null:
			near.visible = mpp<=float(visual.model_lod_switch_mpp)
			far.visible = not near.visible
	var height := float(visual.model_height_m)
	var width := float(visual.model_base_width_m)
	var near_weight := 1.0-smoothstep(2.0,model_limit_mpp(visual),mpp)
	var desired := lerpf(22.0,42.0,near_weight)
	var scale_cap := minf(3.0,float(visual.display_scale_max))
	var exaggeration := minf(scale_cap,desired*mpp/maxf(height*cos(_local_elevation),0.0001))
	var heading := deg_to_rad(float(visual.model_heading_degrees))
	var basis := pose.basis*_geographic_basis(unit,camera,heading)
	var footprint := visual.get("model_footprint_m",[width,width]) as Array
	var pixel := _chart_pixel(pose.origin)
	var span := 0.0
	for x: float in [-float(footprint[0])*0.5,float(footprint[0])*0.5]:
		for z: float in [-float(footprint[1])*0.5,float(footprint[1])*0.5]:
			span = maxf(span,_chart_pixel(pose.origin+basis*Vector3(x,0,z)).distance_to(pixel)*2.0)
	if visual.has("display_footprint_min_px"):
		exaggeration = minf(scale_cap,lerpf(64.0,112.0,near_weight)/maxf(span,0.0001))
	exaggeration = minf(exaggeration,float(visual.display_width_max_px)/maxf(span,0.0001))
	instance.transform = Transform3D(basis.scaled(Vector3.ONE*exaggeration),pose.origin)
	# Godot GLB is Y-up. Grounded models use the chart/DEM; bridge origins sit
	# below their deck datum. Bounds use the same installed model transform.
	var bounds := Rect2(_chart_pixel(instance.position),Vector2.ZERO)
	for x: float in [-float(footprint[0])*0.5,float(footprint[0])*0.5]:
		for y: float in [0.0,height]:
			for z: float in [-float(footprint[1])*0.5,float(footprint[1])*0.5]:
				var corner := instance.transform*Vector3(x,y,z)
				bounds = bounds.expand(_chart_pixel(corner))
	landmark_screen_bounds[str(visual.id)] = bounds.grow(3.0)

static func model_limit_mpp(visual: Dictionary) -> float:
	# Presentation admission only. Retain the sourced real/model dimensions.
	var size := maxf(float(visual.model_height_m),float(visual.model_base_width_m)*0.35)
	return minf(float(visual.model_max_mpp),clampf(float(visual.get("model_admission_mpp",size/20.0)),4.0,24.0))

func _update_surface_demand(surface: Dictionary, camera: RegionCamera, viewport_size: Vector2, reference_lines: Array[Dictionary], covers: Array[Dictionary]) -> void:
	var show := ready and camera.local_active and not surface.is_empty() and not _landmark_failed.has(str(surface.get("content_path","")))
	var mpp := camera.km_per_pixel*1000.0
	if show:
		show = mpp>float(surface.display_min_mpp) and mpp<=_terrain_limit_mpp(surface)*(1.35 if _local_surface!=null or not _surface_wanted_key.is_empty() else 1.0)
	if show:
		var rectangle := Rect2()
		var first := true
		for column: int in [0,int(surface.width)-1]:
			for row: int in [0,int(surface.height)-1]:
				var coordinate := Vector2(float(surface.west_cell_centre)+column*float(surface.step_degrees),float(surface.north_cell_centre)-row*float(surface.step_degrees))
				var point := camera.project(GlobeProjection.lon_lat_to_unit(coordinate))
				rectangle = Rect2(point,Vector2.ZERO) if first else rectangle.expand(point)
				first = false
		var relief_margin := (float(surface.get("height_max_m",0.0))-float(surface.get("height_min_m",0.0)))/maxf(mpp,1.0)
		show = rectangle.grow(maxf(0.0,relief_margin)).intersects(Rect2(Vector2.ZERO,viewport_size),true)
	if not show:
		_cancel_surface_preparation()
		if _surface_cover!=null:
			_surface_cover.visible = false
			_surface_cover.queue_free()
			_surface_cover = null
		if _surface_lines!=null:
			_surface_lines.queue_free()
			_surface_lines = null
		if _local_surface!=null:
			_local_surface.visible = false
			_local_surface.queue_free()
			_local_surface = null
			_landmark_view_key.clear()
		_release_surface_geometry()
		return
	var source_key := str(surface.content_path)
	if _local_surface!=null and source_key==_local_surface_key and _surface_chart_frame==camera.tangent_frame: return
	# A replacement is prepared before retiring the current valid geometry.
	# A different projection frame cannot be displayed using the old vertices.
	if _local_surface!=null and _surface_chart_frame!=camera.tangent_frame:
		for node: MeshInstance3D in [_local_surface,_surface_cover,_surface_lines]:
			if node!=null:
				node.visible = false
				node.queue_free()
		_local_surface = null
		_surface_cover = null
		_surface_lines = null
		_release_surface_geometry()

	var demand_key: Array = [source_key,camera.tangent_frame]
	if demand_key!=_surface_wanted_key:
		_cancel_surface_preparation()
		_surface_wanted_key = demand_key
	if _surface_cpu_ready.is_empty():
		if _surface_thread==null:
			_surface_build_key = demand_key+[_surface_generation]
			_surface_thread = Thread.new()
			_surface_thread.start(LocalSpatialLod.prepare_terrain.bind(surface,camera.tangent_frame,reference_lines,covers,_surface_preparation_current.bind(_surface_generation)))
		return
	if _local_surface!=null:
		for node: MeshInstance3D in [_local_surface,_surface_cover,_surface_lines]:
			if node!=null:
				node.visible = false
				node.queue_free()
		_local_surface = null
		_surface_cover = null
		_surface_lines = null
		_release_surface_geometry()
	_surface_reference = surface
	_local_surface_key = source_key
	_surface_chart_frame = camera.tangent_frame
	_install_surface_geometry(_surface_cpu_ready)
	_surface_cpu_ready = {}
	_surface_presented_key = ""
	_enable_landmark_3d()
	if _local_surface==null:
		_local_surface = MeshInstance3D.new()
		_local_surface.name = "NativeLocalHeightReference"
		_local_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_surface_material = ShaderMaterial.new()
		_surface_material.shader = preload("res://shaders/presentation/map/local_terrain.gdshader")
		var native_extent := Vector2(int(surface.width)-1,int(surface.height)-1)*float(surface.step_degrees)
		_surface_material.set_shader_parameter("survey_bounds",Vector4(float(surface.west_cell_centre),float(surface.north_cell_centre)-native_extent.y,float(surface.west_cell_centre)+native_extent.x,float(surface.north_cell_centre)))
		_surface_material.set_shader_parameter("woodland_enabled",_surface_woodland_mask!=null)
		if _surface_woodland_mask!=null: _surface_material.set_shader_parameter("woodland_mask",_surface_woodland_mask)
		var palette := (surface.get("presentation",{}) as Dictionary).get("palette",{}) as Dictionary
		_surface_material.set_shader_parameter("local_palette_enabled",not palette.is_empty())
		if not palette.is_empty():
			_surface_material.set_shader_parameter("ground_low_tone",Color(str(palette.low)))
			_surface_material.set_shader_parameter("ground_high_tone",Color(str(palette.high)))
		# Native mesh normals use the fixed REGION frame. Lighting uses actual
		# east/up/south at this survey, independent of where REGION was entered.
		_surface_material.set_shader_parameter("normal_to_geographic",_geographic_basis(GlobeProjection.lon_lat_to_unit(_local_surface_anchor),camera,0.0).transposed())
		_local_surface.material_override = _surface_material
		_landmark_root.add_child(_local_surface)
	_local_surface.mesh = _local_surface_mesh
	if _surface_line_mesh!=null:
		if _surface_lines==null:
			_surface_lines = MeshInstance3D.new()
			_surface_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ink := StandardMaterial3D.new()
			ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ink.vertex_color_use_as_albedo = true
			ink.albedo_color = Color.WHITE # Per-vertex river and height-contour inks.
			ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_surface_lines.material_override = ink
			_landmark_root.add_child(_surface_lines)
		_surface_lines.mesh = _surface_line_mesh
	if _surface_cover_mesh!=null:
		if _surface_cover==null:
			_surface_cover = MeshInstance3D.new()
			_surface_cover.name = "BoundedPhysicalCover"
			_surface_cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_surface_cover.material_override = _surface_material
			_landmark_root.add_child(_surface_cover)
		_surface_cover.mesh = _surface_cover_mesh
	_install_woodland_instances()
	_landmark_view_key.clear()

func _install_woodland_instances() -> void:
	if _woodland_positions.is_empty(): return
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	for variant: int in range(3):
		var count := ceili(float(_woodland_positions.size()-variant)/3.0)
		if count<=0: continue
		var node := MultiMeshInstance3D.new()
		node.name = "ModernWoodlandReference"+str(variant)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = _reference_tree_mesh(variant,material)
		node.multimesh.instance_count = count
		for local_index: int in range(count):
			var index := variant+local_index*3
			var scale := 0.85+0.05*float(index%4)
			# Rotate about gravity only. The existing masked DEM foot is unchanged.
			var basis := Basis(Vector3.UP,float(index)*2.39996323).scaled(Vector3.ONE*scale)
			node.multimesh.set_instance_transform(local_index,Transform3D(basis,_woodland_positions[index]))
		_landmark_root.add_child(node)
		_woodland_nodes.append(node)
	_woodland_positions.clear() # The installed MultiMesh owns the transforms.

static func _reference_tree_mesh(variant: int, material: StandardMaterial3D) -> ArrayMesh:
	# Three original branched silhouettes inside the existing 3.5-m footprint.
	# Ring shapes are art conventions, not species, density or 1900 forest facts.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var crowns: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(2,0.4),Vector2(3.5,3.5),Vector2(5.3,1.65),Vector2(6,3.1),Vector2(8.1,1.2),Vector2(8.8,2.5),Vector2(11.2,0.8),Vector2(11.6,1.6),Vector2(14.5,0.15),Vector2(16,0)]),
		PackedVector2Array([Vector2(4,0.3),Vector2(5,2.4),Vector2(6.4,2),Vector2(8,2.7),Vector2(10.5,1.4),Vector2(12,0.9),Vector2(15.2,0)]),
		PackedVector2Array([Vector2(3.5,0.3),Vector2(4.4,2.6),Vector2(6.7,3.2),Vector2(8.4,2.45),Vector2(10.8,2.2),Vector2(12.7,0.95),Vector2(14.3,0)])]
	var trunk := PackedVector2Array([Vector2(0,0.24),Vector2(6,0.13)])
	for rings: PackedVector2Array in [trunk,crowns[variant]]:
		for level: int in range(rings.size()-1):
			for side: int in range(8):
				var corners := PackedVector3Array()
				for ring: int in [level,level+1]:
					for sector: int in [side,side+1]:
						var angle := TAU*float(sector)/8.0
						var radius := rings[ring].y*(0.88+0.12*sin(sector*2.1+variant+ring*0.6))
						corners.append(Vector3(cos(angle)*radius,rings[ring].x,sin(angle)*radius))
				for face: PackedInt32Array in [PackedInt32Array([0,2,1]),PackedInt32Array([1,2,3])]:
					var normal := (corners[face[1]]-corners[face[0]]).cross(corners[face[2]]-corners[face[0]])
					if normal.length_squared()<0.000001: continue
					normal = normal.normalized()
					var ink := (Color(0.35,0.27,0.19) if rings==trunk else Color(0.22+0.02*variant,0.32+0.017*level,0.23+0.018*variant)).srgb_to_linear()
					for index: int in face:
						vertices.append(corners[index]); normals.append(normal); colours.append(ink)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material)
	return mesh

func _surface_grid(coordinate: Vector2) -> Vector2:
	return Vector2((coordinate.x-float(_surface_reference.west_cell_centre))/float(_surface_reference.step_degrees),(float(_surface_reference.north_cell_centre)-coordinate.y)/float(_surface_reference.step_degrees))

func _edge_weight(grid: Vector2) -> float:
	var extent := Vector2(int(_surface_reference.width)-1,int(_surface_reference.height)-1)
	var margin := grid.min(extent-grid)
	# A geographic edge transition, never a screen-fixed opacity rectangle.
	return smoothstep(0.0,maxf(2.0,extent.x*0.12),margin.x)*smoothstep(0.0,maxf(2.0,extent.y*0.12),margin.y)

func _surface_ground_y(coordinate: Vector2) -> float:
	if _surface_vertices.is_empty(): return 0.0
	var grid := _surface_grid(coordinate)
	var width := int(_surface_reference.width)
	var column := clampi(int(grid.x),0,width-2)
	var row := clampi(int(grid.y),0,int(_surface_reference.height)-2)
	var dx := clampf(grid.x-column,0.0,1.0)
	var dy := clampf(grid.y-row,0.0,1.0)
	var a := _surface_vertices[row*width+column].y
	var b := _surface_vertices[row*width+column+1].y
	var c := _surface_vertices[(row+1)*width+column].y
	var d := _surface_vertices[(row+1)*width+column+1].y
	return a+(b-a)*dx+(c-a)*dy if dx+dy<=1.0 else d+(c-d)*(1.0-dx)+(b-d)*(1.0-dy)

func _surface_contains(coordinate: Vector2) -> bool:
	if _surface_reference.is_empty(): return false
	var west := float(_surface_reference.west_cell_centre)
	var north := float(_surface_reference.north_cell_centre)
	var step := float(_surface_reference.step_degrees)
	return coordinate.x>=west and coordinate.x<=west+(int(_surface_reference.width)-1)*step and coordinate.y<=north and coordinate.y>=north-(int(_surface_reference.height)-1)*step

func _update_surface_pose(camera: RegionCamera, viewport_size: Vector2) -> void:
	_surface_pick_view = [camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,viewport_size,_local_surface_key]
	var unit := GlobeProjection.lon_lat_to_unit(_local_surface_anchor)
	_local_surface.transform = _chart_transform(unit,camera,viewport_size)
	_local_surface.force_update_transform()
	var strength := _surface_strength(camera)
	_local_surface.visible = strength>0.001
	if _surface_material!=null:
		if strength!=_surface_strength_value: _surface_material.set_shader_parameter("local_strength",strength)
	_surface_strength_value = strength
	_surface_pick_pixel = Vector2(INF,INF)
	if _surface_lines!=null: _surface_lines.transform = _local_surface.transform
	for node: MultiMeshInstance3D in _woodland_nodes:
		node.transform = _local_surface.transform
		var detail := (_surface_reference.get("presentation",{}) as Dictionary).get("woodland_instances",{}) as Dictionary
		node.visible = strength>0.95 and camera.km_per_pixel*1000.0<=float(detail.get("max_mpp",12.0))
	if _surface_cover!=null:
		_surface_cover.transform = _local_surface.transform
		_surface_cover.visible = strength>0.001
	for instance: MeshInstance3D in [_surface_lines]:
		if instance==null: continue
		instance.visible = strength>0.001
		var material := instance.material_override as StandardMaterial3D
		var color := material.albedo_color
		color.a = strength
		if material.albedo_color!=color: material.albedo_color = color

func surface_unit_at(pixel: Vector2, camera: RegionCamera, viewport_size: Vector2) -> Vector3:
	if _local_surface==null or _landmark_camera==null or _surface_chart_frame!=camera.tangent_frame: return Vector3.ZERO
	var view: Array = [camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,viewport_size,_local_surface_key]
	# A current crop contains every rendered terrain pixel. Outside it the
	# existing flat chart owns input; do not traverse native DEM triangles.
	# A pending camera move must first update its pose, so never reject against
	# the previous camera's crop while anchoring a zoom or bearing change.
	if _surface_pick_view==view and (_local_container==null or not _local_container.visible or not _local_render_rect.has_point(pixel)): return Vector3.ZERO
	# Input can arrive more than once before the next draw. Ray picking must
	# use this camera pose, not a previous frame's cached LOCAL transform.
	if _surface_pick_view!=view:
		_update_local_camera(camera,viewport_size)
		_update_surface_pose(camera,viewport_size)
	if not _local_surface.visible: return Vector3.ZERO
	if pixel==_surface_pick_pixel: return _surface_pick_unit
	var inverse := _local_surface.global_transform.affine_inverse()
	var local_pixel := pixel-_local_render_rect.position
	var origin := inverse*_landmark_camera.project_ray_origin(local_pixel)
	var direction := inverse.basis*_landmark_camera.project_ray_normal(local_pixel)
	var end := origin+direction*_landmark_camera.far
	var nearest := INF
	var hit := Vector3.ZERO
	for chunk: Dictionary in _surface_pick_chunks:
		if (chunk.bounds as AABB).intersects_segment(origin,end)==null: continue
		for index: int in range(int(chunk.start),int(chunk.end),3):
			var intersection: Variant = Geometry3D.ray_intersects_triangle(origin,direction,_surface_ray_vertices[_surface_indices[index]],_surface_ray_vertices[_surface_indices[index+1]],_surface_ray_vertices[_surface_indices[index+2]])
			if intersection==null: continue
			var distance := origin.distance_squared_to(intersection as Vector3)
			if distance<nearest:
				nearest = distance
				hit = intersection as Vector3
	# Water is not a selectable polity. Its displayed level nevertheless owns
	# the geographical ray hit, instead of the different-height bed below it.
	for chunk: Dictionary in _surface_water_chunks:
		if (chunk.bounds as AABB).intersects_segment(origin,end)==null: continue
		for index: int in range(int(chunk.start),int(chunk.end),3):
			var intersection: Variant = Geometry3D.ray_intersects_triangle(origin,direction,_surface_water_vertices[index],_surface_water_vertices[index+1],_surface_water_vertices[index+2])
			if intersection==null: continue
			var distance := origin.distance_squared_to(intersection as Vector3)
			if distance<nearest:
				nearest = distance
				hit = intersection as Vector3
	_surface_pick_pixel = pixel
	_surface_pick_unit = RegionProjection.inverse(Vector2(hit.x,-hit.z)/1000.0+_surface_chart_anchor_km,_surface_chart_frame) if nearest<INF else Vector3.ZERO
	if not _surface_pick_unit.is_zero_approx() and _edge_weight(_surface_grid(RegionProjection.lon_lat(_surface_pick_unit)))<0.02: _surface_pick_unit = Vector3.ZERO
	return _surface_pick_unit

func surface_screen_point(unit: Vector3, camera: RegionCamera) -> Vector2:
	var coordinate := RegionProjection.lon_lat(unit)
	if _local_surface==null or not _local_surface.visible or _landmark_camera==null or not _surface_contains(coordinate): return Vector2(INF,INF)
	return chart_screen_point(unit,camera)

func release_landmarks() -> void:
	if _internal_scene_load!=null: _internal_scene_load.call("clear")
	_cancel_surface_preparation()
	_release_settlements()
	_landmark_wanted_paths.clear()
	landmark_screen_bounds.clear()
	_landmark_presented.clear()
	_landmark_instances.clear()
	_landmark_view_key.clear()
	_local_surface = null
	_surface_lines = null
	_surface_cover = null
	_release_surface_geometry()
	if _landmark_root!=null:
		_landmark_root.visible = false
		_landmark_root = null
		_landmark_camera = null
		_landmark_light = null
		_local_camera_key.clear()
		_local_render_generation += 1
		_landmark_render_pending = false
		_local_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_local_viewport.find_world_3d().environment = null
		_local_container.visible = false
		_local_container.queue_free()
		_local_container = null
		_local_viewport = null
		_local_render_rect = Rect2()
		canvas_update_requested.emit()
	_trim_landmark_scenes()

func _release_surface_geometry() -> void:
	for node: MultiMeshInstance3D in _woodland_nodes:
		node.visible = false
		node.multimesh = null
		node.queue_free()
	_woodland_nodes.clear()
	_woodland_positions.clear()
	_local_surface_mesh = null
	_surface_line_mesh = null
	_surface_cover_mesh = null
	_local_surface_key = ""
	_surface_reference = {}
	_surface_presented_key = ""
	_surface_material = null
	_surface_texture_batch.clear()
	_surface_style_key.clear()
	_surface_strength_value = -1.0
	_surface_water_vertices = PackedVector3Array()
	_surface_water_chunks.clear()
	_surface_water_mask = null
	_surface_woodland_mask = null
	_surface_height_texture = null
	_surface_vertices = PackedVector3Array()
	_surface_ray_vertices = PackedVector3Array()
	_surface_indices = PackedInt32Array()
	_surface_pick_chunks.clear()
	_surface_pick_pixel = Vector2(INF,INF)
	_surface_pick_unit = Vector3.ZERO
	_surface_pick_view.clear()

func _touch_landmark_scene(path: String) -> void:
	_landmark_scene_order.erase(path)
	_landmark_scene_order.append(path)

func _trim_landmark_scenes() -> void:
	# Instances hold their own mesh/material references. Only the small recent
	# PackedScene working set remains here after LOCAL has been left.
	while _landmark_scene_order.size()>MAX_CACHED_LANDMARK_SCENES:
		_landmark_scenes.erase(_landmark_scene_order.pop_front())

func _cancel_surface_preparation() -> void:
	if _surface_wanted_key.is_empty() and _surface_cpu_ready.is_empty(): return
	_surface_mutex.lock()
	_surface_generation += 1
	_surface_mutex.unlock()
	_surface_wanted_key.clear()
	_surface_cpu_ready = {}

func _surface_preparation_current(generation: int) -> bool:
	_surface_mutex.lock()
	var current := generation==_surface_generation
	_surface_mutex.unlock()
	return current

func _poll_surface_preparation() -> bool:
	if _surface_thread==null or _surface_thread.is_alive(): return false
	var returned: Variant = _surface_thread.wait_to_finish()
	_surface_thread = null
	if not _surface_wanted_key.is_empty() and _surface_build_key==_surface_wanted_key+[_surface_generation]:
		var valid := returned is Dictionary
		if valid:
			for field: String in ["anchor","anchor_km","vertices","ray_vertices","indices","pick_chunks","water_vertices","water_chunks","water_bytes","woodland_bytes","height_bytes","terrain_arrays","cover_arrays","line_arrays"]:
				if not (returned as Dictionary).has(field): valid = false; break
		if not valid:
			# A failed current worker is not a cancellation or an empty valid terrain.
			# Keep the regional fallback; do not start the same failed job every frame.
			_landmark_failed[str(_surface_wanted_key[0])] = true
			_surface_wanted_key.clear()
			_surface_cpu_ready = {}
			landmark_load_failed.emit("LOCAL地形准备未返回完整结果，暂保留区域地貌和地点标识。")
		else: _surface_cpu_ready = returned as Dictionary
	return true

func _install_surface_geometry(data: Dictionary) -> void:
	_local_surface_anchor = data.anchor
	_surface_chart_anchor_km = data.anchor_km
	_surface_vertices = data.vertices
	_surface_ray_vertices = data.ray_vertices
	_surface_indices = data.indices
	_surface_pick_chunks.assign(data.pick_chunks)
	_surface_water_vertices = data.water_vertices
	_surface_water_chunks.assign(data.water_chunks)
	var water_bytes := data.water_bytes as PackedByteArray
	var woodland_bytes := data.woodland_bytes as PackedByteArray
	_woodland_positions.assign(data.get("woodland_positions",[]) as Array)
	_surface_woodland_mask = null if woodland_bytes.is_empty() else ImageTexture.create_from_image(Image.create_from_data(COVER_MASK_SIZE,COVER_MASK_SIZE,false,Image.FORMAT_R8,woodland_bytes))
	_surface_water_mask = ImageTexture.create_from_image(Image.create_from_data(1,1,false,Image.FORMAT_L8,PackedByteArray([0])) if water_bytes.is_empty() else Image.create_from_data(COVER_MASK_SIZE,COVER_MASK_SIZE,false,Image.FORMAT_L8,water_bytes))
	_surface_height_texture = ImageTexture.create_from_image(Image.create_from_data(int(_surface_reference.width),int(_surface_reference.height),false,Image.FORMAT_RF,data.height_bytes))
	_local_surface_mesh = ArrayMesh.new()
	var arrays := data.terrain_arrays as Array
	if not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): _local_surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_surface_cover_mesh = null
	arrays = data.cover_arrays as Array
	if not arrays.is_empty():
		_surface_cover_mesh = ArrayMesh.new()
		_surface_cover_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_surface_line_mesh = null
	arrays = data.line_arrays as Array
	if not arrays.is_empty():
		_surface_line_mesh = ArrayMesh.new()
		_surface_line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
