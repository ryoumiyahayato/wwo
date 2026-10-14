class_name RegionView
extends RefCounted
## Cached regional canvas sharing the Globe's immutable GPU geometry.
signal landmark_display_changed
signal landmark_load_failed(message: String)

const PREPARE_BUDGET_USEC: int = 2000
var container: SubViewportContainer
var viewport: SubViewport
var map_canvas: RID
var _map_background_layer: CanvasLayer
var surfaces: Dictionary = {}
var boundaries: Array[Dictionary] = []
var ready: bool = false
var preparing: bool = false
var _owners: Array = []
var _cursor: int = 0
var _background: RID
var background: Dictionary = {}
var _labels: Array[Dictionary] = []
var country_label_rects: Array[Rect2] = []
const MINIATURE_ELEVATION: float = 0.6108652382 # 35 degrees; presentation only.
var landmark_screen_bounds: Dictionary = {}
var _landmark_scenes: Dictionary = {}
var _landmark_pending: Dictionary = {}
var _landmark_failed: Dictionary = {}
var _landmark_instances: Dictionary = {}
var _landmark_root: Node3D
var _landmark_camera: Camera3D
var _landmark_view_key: Array = []
var _landmark_presented: Dictionary = {}
var _landmark_render_pending: bool = false
var _local_surface: MeshInstance3D
var _local_surface_mesh: ArrayMesh
var _local_surface_key: String = ""
var _local_surface_anchor := Vector2.ZERO
var _surface_base_height: float = 0.0
var _surface_reference: Dictionary = {}
var _surface_vertices := PackedVector3Array()
var _surface_indices := PackedInt32Array()
var _surface_lines: MeshInstance3D
var _surface_line_mesh: ArrayMesh
var _surface_pick_chunks: Array[Dictionary] = []
var _surface_pick_pixel := Vector2(INF,INF)
var _surface_pick_unit := Vector3.ZERO

func initialize(parent: Control) -> void:
	container = SubViewportContainer.new()
	container.name = "RegionViewportContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.show_behind_parent = true
	container.stretch = true
	container.visible = false
	parent.add_child(container)
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	# Explicit World3D: own_world_3d creates a private world which world_3d
	# does not return. R3 assigned environment through that null base property.
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	_map_background_layer = CanvasLayer.new()
	_map_background_layer.layer = -1
	viewport.add_child(_map_background_layer)
	map_canvas = _map_background_layer.get_canvas()
	_background = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_background, map_canvas)
	RenderingServer.canvas_item_set_draw_index(_background, 0)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/presentation/map/relief_background.gdshader") as Shader
	RenderingServer.canvas_item_set_material(_background, material.get_rid())
	background = {"material": material, "item": _background}

func resize(viewport_size: Vector2) -> void:
	if container.size == viewport_size:
		return
	container.size = viewport_size
	viewport.size = Vector2i(viewport_size)
	if ready: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.canvas_item_clear(_background)
	RenderingServer.canvas_item_add_rect(_background, Rect2(Vector2.ZERO, viewport_size), Color(0.10, 0.14, 0.16))

func begin(source: Dictionary) -> void:
	clear()
	_owners = source.keys()
	_cursor = 0
	preparing = true

func prepare_step(source: Dictionary, lines: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	while _cursor < _owners.size():
		var owner := str(_owners[_cursor])
		var original := source[owner] as Dictionary
		var material := (original.material as ShaderMaterial).duplicate() as ShaderMaterial
		material.set_shader_parameter("region_mode", true)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, map_canvas)
		RenderingServer.canvas_item_set_draw_index(item, _cursor + 1)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		surfaces[owner] = {"geometry": original.geometry, "material": material, "item": item, "texture": RID()}
		_cursor += 1
		if Time.get_ticks_usec() - started >= PREPARE_BUDGET_USEC:
			return
	for original: Dictionary in lines:
		var material := (original.material as ShaderMaterial).duplicate() as ShaderMaterial
		material.set_shader_parameter("region_mode", true)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, map_canvas)
		RenderingServer.canvas_item_set_draw_index(item, LocalSpatialLayer.DRAW_ORDER + 2 if str(original.get("kind", "")) == "macro" else surfaces.size() + boundaries.size() + 1)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		RenderingServer.canvas_item_add_mesh(item, (original.geometry as GlobeBoundaryBatch).mesh.get_rid())
		boundaries.append({"geometry": original.geometry, "material": material, "item": item, "kind": original.get("kind", ""),"home_border":original.get("home_border",false)})
	preparing = false
	ready = true

func clear() -> void:
	release_landmarks()
	clear_labels()
	background.erase("surface_relief_style")
	background.erase("surface_appearance_style")
	for batch: Dictionary in surfaces.values():
		RenderingServer.free_rid(batch.item as RID)
	for batch: Dictionary in boundaries:
		RenderingServer.free_rid(batch.item as RID)
	surfaces.clear()
	boundaries.clear()
	ready = false
	preparing = false

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
	_landmark_scenes.clear()
	_landmark_pending.clear()
	_local_surface_mesh = null
	_surface_reference.clear()
	if _background.is_valid():
		RenderingServer.free_rid(_background)

func landmark_preparing() -> bool:
	return not _landmark_pending.is_empty()

func landmark_visible(id: String) -> bool:
	return _landmark_presented.has(id) and _landmark_instances.has(id) and landmark_screen_bounds.has(id)

func _landmark_failed_load(path: String) -> void:
	_landmark_failed[path] = true
	landmark_load_failed.emit("地标模型读取失败，暂保留地图剪影。")

func prepare_landmarks() -> bool:
	var completed := false
	for path: String in _landmark_pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(path) as PackedScene
			if scene!=null: _landmark_scenes[path] = scene
			else: _landmark_failed_load(path)
		else: _landmark_failed_load(path)
		_landmark_pending.erase(path)
		completed = true
	if completed: _landmark_view_key.clear()
	return completed

func update_landmarks(visuals: Array[Dictionary], camera: RegionCamera, viewport_size: Vector2, surface: Dictionary = {}, reference_lines: Array[Dictionary] = []) -> void:
	var wanted: Dictionary = {}
	if ready and camera.active and camera.local_active:
		for visual: Dictionary in visuals:
			var limit := float(visual.model_max_mpp)*(1.2 if _landmark_instances.has(str(visual.id)) else 1.0)
			if camera.local_place_id!=str(visual.anchor_place_id) or camera.km_per_pixel*1000.0>limit: continue
			wanted[str(visual.id)] = visual
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
		if not _landmark_scenes.has(path):
			if not _landmark_pending.has(path) and not _landmark_failed.has(path):
				if ResourceLoader.load_threaded_request(path,"PackedScene")==OK:
					_landmark_pending[path] = true
				else: _landmark_failed_load(path)
			continue
		if _landmark_instances.has(id): continue
		var node := (_landmark_scenes[path] as PackedScene).instantiate()
		var instance := node as Node3D
		if instance==null:
			node.free()
			_landmark_failed_load(path)
			continue
		_enable_landmark_3d()
		_landmark_root.add_child(instance)
		_landmark_instances[id] = instance
		_landmark_view_key.clear()
	_update_surface_demand(surface,camera,viewport_size,reference_lines)
	if _landmark_instances.is_empty() and _local_surface==null:
		release_landmarks()
		return
	var key: Array = [camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,viewport_size,_landmark_instances.keys(),_local_surface!=null]
	if key==_landmark_view_key: return
	_landmark_view_key = key
	# A single orthographic miniature camera uses this existing map viewport.
	# Ground positions are obtained from RegionCamera.project, not a new chart.
	_landmark_camera.size = viewport_size.y
	var distance := maxf(2048.0,viewport_size.length()*2.0)
	_landmark_camera.position = Vector3(0,sin(MINIATURE_ELEVATION),cos(MINIATURE_ELEVATION))*distance
	_landmark_camera.rotation = Vector3(-MINIATURE_ELEVATION,0,0)
	_landmark_camera.far = distance*4.0
	if _local_surface!=null: _update_surface_pose(camera,viewport_size)
	for id: String in _landmark_instances:
		var visual := wanted[id] as Dictionary
		_update_landmark_pose(_landmark_instances[id] as Node3D,visual,camera,viewport_size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not _landmark_render_pending:
		_landmark_render_pending = true
		RenderingServer.frame_post_draw.connect(_landmark_frame_ready,CONNECT_ONE_SHOT)

func _landmark_frame_ready() -> void:
	_landmark_render_pending = false
	if _landmark_root==null or _landmark_camera==null or not _landmark_camera.is_current() or not container.visible or viewport.disable_3d: return
	_landmark_presented.clear()
	for id: String in _landmark_instances:
		if landmark_screen_bounds.has(id) and (landmark_screen_bounds[id] as Rect2).intersects(Rect2(Vector2.ZERO,Vector2(viewport.size))): _landmark_presented[id] = true
	landmark_display_changed.emit()

func _enable_landmark_3d() -> void:
	if _landmark_root!=null: return
	viewport.disable_3d = false
	_landmark_root = Node3D.new()
	_landmark_root.name = "LocalMiniatures"
	viewport.add_child(_landmark_root)
	_landmark_camera = Camera3D.new()
	_landmark_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_landmark_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_landmark_camera.near = 0.1
	var environment := Environment.new()
	# Keep all existing 2D map batches as the background of the same viewport.
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = -1
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.76,0.78,0.72)
	environment.ambient_light_energy = 0.65
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Viewport composition checks the scenario's environment, not the camera
	# override. Otherwise the opaque 2D chart is drawn after the GLB and hides it.
	viewport.find_world_3d().environment = environment
	_landmark_root.add_child(_landmark_camera)
	_landmark_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48,-32,0)
	light.light_color = Color(1.0,0.95,0.85)
	light.light_energy = 0.9
	light.shadow_enabled = false
	_landmark_root.add_child(light)

func _update_landmark_pose(instance: Node3D, visual: Dictionary, camera: RegionCamera, viewport_size: Vector2) -> void:
	var coordinates := (visual.geometry as Dictionary).coordinates as Array
	var location := Vector2(float(coordinates[0]),float(coordinates[1]))
	var unit := GlobeProjection.lon_lat_to_unit(location)
	var geographic := RegionProjection.frame(location)
	var point := camera.project(unit)
	# Project short true east/north steps to include chart distortion/convergence.
	var step := 0.00001
	var metres := RegionProjection.EARTH_RADIUS_KM*1000.0*step
	var east := (camera.project((unit+geographic.x*step).normalized())-point)/metres
	var north := (camera.project((unit+geographic.y*step).normalized())-point)/metres
	var mpp := camera.scale_at(unit)*1000.0
	var height := float(visual.model_height_m)
	var width := float(visual.model_base_width_m)
	var near_weight := 1.0-smoothstep(RegionCamera.LOCAL_MIN_KM_PER_PIXEL*1000.0,float(visual.model_max_mpp),mpp)
	var desired := lerpf(float(visual.display_height_min_px),float(visual.display_height_max_px),near_weight)
	var exaggeration := minf(float(visual.display_scale_max),desired*mpp/(height*cos(MINIATURE_ELEVATION)))
	var heading := deg_to_rad(float(visual.model_heading_degrees))
	var screen_width := width*(absf(east.x*cos(heading)+north.x*sin(heading))+absf(east.x*sin(heading)-north.x*cos(heading)))
	exaggeration = minf(exaggeration,float(visual.display_width_max_px)/maxf(screen_width,0.000001))
	var sine := sin(MINIATURE_ELEVATION)
	# A rigid miniature preserves the GLB silhouette, unlike stretching its
	# horizontal axes to cancel the oblique camera's ground foreshortening.
	var e := Vector3(east.x,0,east.y).normalized()
	var n := Vector3.UP.cross(e)
	var orientation := Basis(e*cos(heading)+n*sin(heading),Vector3.UP,e*sin(heading)-n*cos(heading))
	var footprint := visual.get("model_footprint_m",[width,width]) as Array
	var span := 0.0
	for x: float in [-float(footprint[0])*0.5,float(footprint[0])*0.5]:
		for z: float in [-float(footprint[1])*0.5,float(footprint[1])*0.5]:
			var ground := orientation*Vector3(x,0,z)
			span = maxf(span,Vector2(ground.x,ground.z*sine).length()*2.0)
	if visual.has("display_footprint_min_px"):
		exaggeration = minf(float(visual.display_scale_max),lerpf(float(visual.display_footprint_min_px),float(visual.display_footprint_max_px),near_weight)*mpp/maxf(span,1.0))
	exaggeration = minf(exaggeration,float(visual.display_width_max_px)*mpp/maxf(span,1.0))
	var basis := orientation.scaled(Vector3.ONE*(exaggeration/mpp))
	var offset := point-viewport_size*0.5
	instance.transform = Transform3D(basis,Vector3(offset.x,0,offset.y/sine))
	if _local_surface!=null and _surface_contains(location):
		# The anchor is sampled on the same native triangle as the terrain mesh.
		var altitude := (_surface_height(location)-_surface_base_height)/mpp
		instance.position += Vector3(0,altitude,0)
	# Godot GLB is Y-up; its bottom origin is exactly on the existing chart plane.
	var bounds := Rect2(_landmark_camera.unproject_position(instance.position),Vector2.ZERO)
	for x: float in [-float(footprint[0])*0.5,float(footprint[0])*0.5]:
		for y: float in [0.0,height]:
			for z: float in [-float(footprint[1])*0.5,float(footprint[1])*0.5]:
				var corner := instance.transform*Vector3(x,y,z)
				bounds = bounds.expand(_landmark_camera.unproject_position(corner))
	landmark_screen_bounds[str(visual.id)] = bounds.grow(3.0)

func _update_surface_demand(surface: Dictionary, camera: RegionCamera, viewport_size: Vector2, reference_lines: Array[Dictionary]) -> void:
	var show := ready and camera.local_active and not surface.is_empty()
	var mpp := camera.km_per_pixel*1000.0
	if show:
		show = mpp>float(surface.display_min_mpp) and mpp<=float(surface.display_max_mpp)
	if show:
		var rectangle := Rect2()
		var first := true
		for column: int in [0,int(surface.width)-1]:
			for row: int in [0,int(surface.height)-1]:
				var coordinate := Vector2(float(surface.west_cell_centre)+column*float(surface.step_degrees),float(surface.north_cell_centre)-row*float(surface.step_degrees))
				var point := camera.project(GlobeProjection.lon_lat_to_unit(coordinate))
				rectangle = Rect2(point,Vector2.ZERO) if first else rectangle.expand(point)
				first = false
		show = rectangle.intersects(Rect2(Vector2.ZERO,viewport_size),true)
	if not show:
		if _surface_lines!=null:
			_surface_lines.queue_free()
			_surface_lines = null
		if _local_surface!=null:
			_local_surface.visible = false
			_local_surface.queue_free()
			_local_surface = null
			_landmark_view_key.clear()
		return
	var source_key := str(surface.content_path)
	if _local_surface!=null and source_key==_local_surface_key: return
	if _local_surface_mesh==null or source_key!=_local_surface_key:
		_surface_reference = surface
		_local_surface_key = source_key
		var anchor := surface.anchor_lon_lat as Array
		_local_surface_anchor = Vector2(float(anchor[0]),float(anchor[1]))
		_surface_base_height = _surface_height(_local_surface_anchor)
		_make_surface_mesh()
		_make_surface_lines(reference_lines)
	_enable_landmark_3d()
	if _local_surface==null:
		_local_surface = MeshInstance3D.new()
		_local_surface.name = "NativeLocalHeightReference"
		_local_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.metallic_specular = 0.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_local_surface.material_override = material
		_landmark_root.add_child(_local_surface)
	_local_surface.mesh = _local_surface_mesh
	if _surface_line_mesh!=null:
		if _surface_lines==null:
			_surface_lines = MeshInstance3D.new()
			_surface_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ink := StandardMaterial3D.new()
			ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ink.albedo_color = Color(0.16,0.32,0.37)
			_surface_lines.material_override = ink
			_landmark_root.add_child(_surface_lines)
		_surface_lines.mesh = _surface_line_mesh
	_landmark_view_key.clear()

func _surface_height(coordinate: Vector2) -> float:
	var d := _surface_reference
	var x := clampf((coordinate.x-float(d.west_cell_centre))/float(d.step_degrees),0.0,float(d.width)-1.0)
	var y := clampf((float(d.north_cell_centre)-coordinate.y)/float(d.step_degrees),0.0,float(d.height)-1.0)
	var column := mini(int(x),int(d.width)-2)
	var row := mini(int(y),int(d.height)-2)
	var dx := x-column
	var dy := y-row
	var rows := d.height_rows_m as Array
	var top_left := float(rows[row][column])
	var top_right := float(rows[row][column+1])
	var bottom_left := float(rows[row+1][column])
	var bottom_right := float(rows[row+1][column+1])
	return top_left+(top_right-top_left)*dx+(bottom_left-top_left)*dy if dx+dy<=1.0 else bottom_right+(bottom_left-bottom_right)*(1.0-dx)+(top_right-bottom_right)*(1.0-dy)

func _surface_contains(coordinate: Vector2) -> bool:
	if _surface_reference.is_empty(): return false
	var west := float(_surface_reference.west_cell_centre)
	var north := float(_surface_reference.north_cell_centre)
	var step := float(_surface_reference.step_degrees)
	return coordinate.x>=west and coordinate.x<=west+(int(_surface_reference.width)-1)*step and coordinate.y<=north and coordinate.y>=north-(int(_surface_reference.height)-1)*step

func _make_surface_mesh() -> void:
	var d := _surface_reference
	var frame := RegionProjection.frame(_local_surface_anchor)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for row: int in range(int(d.height)):
		for column: int in range(int(d.width)):
			var coordinate := Vector2(float(d.west_cell_centre)+column*float(d.step_degrees),float(d.north_cell_centre)-row*float(d.step_degrees))
			var metric := RegionProjection.forward(GlobeProjection.lon_lat_to_unit(coordinate),frame)*1000.0
			vertices.append(Vector3(metric.x,float(d.height_rows_m[row][column])-_surface_base_height,-metric.y))
			normals.append(Vector3.ZERO)
	for row: int in range(int(d.height)-1):
		for column: int in range(int(d.width)-1):
			var a := row*int(d.width)+column
			var b := a+1
			var c := a+int(d.width)
			var e := c+1
			indices.append_array(PackedInt32Array([a,c,b,b,c,e]))
	for index: int in range(0,indices.size(),3):
		var a := indices[index]
		var b := indices[index+1]
		var c := indices[index+2]
		var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		normals[a] += normal; normals[b] += normal; normals[c] += normal
	for index: int in range(normals.size()): normals[index] = normals[index].normalized()
	var low := Color(str(d.get("low_color","#62634f")))
	var rock := Color(str(d.get("high_color","#929080")))
	var lowest := INF
	var highest := -INF
	for vertex: Vector3 in vertices:
		lowest = minf(lowest,vertex.y)
		highest = maxf(highest,vertex.y)
	var light_direction := Vector3(-0.55,0.80,0.32).normalized()
	for index: int in range(vertices.size()):
		# Derived once from acquired elevations: no noise, height exaggeration,
		# vegetation classes or historical land-use claims.
		var slope := smoothstep(0.04,0.55,1.0-normals[index].y)
		var relief := (vertices[index].y-lowest)/maxf(highest-lowest,1.0)
		var shade := 0.72+0.28*maxf(0.0,normals[index].dot(light_direction))
		var tint := low.lerp(rock,clampf(slope*0.75+relief*0.25,0.0,1.0))
		colors.append(Color(tint.r*shade,tint.g*shade,tint.b*shade,1.0))
	_surface_vertices = vertices
	_surface_indices = indices
	_surface_pick_chunks.clear()
	for start: int in range(0,indices.size(),192):
		var end := mini(start+192,indices.size())
		var bounds := AABB(vertices[indices[start]],Vector3.ZERO)
		for index: int in range(start,end): bounds = bounds.expand(vertices[indices[index]])
		_surface_pick_chunks.append({"start":start,"end":end,"bounds":bounds.grow(0.01)})
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_local_surface_mesh = ArrayMesh.new()
	_local_surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func _update_surface_pose(camera: RegionCamera, viewport_size: Vector2) -> void:
	var unit := GlobeProjection.lon_lat_to_unit(_local_surface_anchor)
	var geographic := RegionProjection.frame(_local_surface_anchor)
	var point := camera.project(unit)
	var step := 0.00001
	var metres := RegionProjection.EARTH_RADIUS_KM*1000.0*step
	var east := (camera.project((unit+geographic.x*step).normalized())-point)/metres
	var north := (camera.project((unit+geographic.y*step).normalized())-point)/metres
	var mpp := camera.scale_at(unit)*1000.0
	var sine := sin(MINIATURE_ELEVATION)
	# Preserve actual height displacement. Picking intersects this same mesh.
	var height_axis := Vector3.UP/mpp
	var basis := Basis(Vector3(east.x,0,east.y/sine),height_axis,-Vector3(north.x,0,north.y/sine))
	var offset := point-viewport_size*0.5
	_local_surface.transform = Transform3D(basis,Vector3(offset.x,0,offset.y/sine))
	_surface_pick_pixel = Vector2(INF,INF)
	if _surface_lines!=null: _surface_lines.transform = _local_surface.transform

func _make_surface_lines(features: Array[Dictionary]) -> void:
	_surface_line_mesh = null
	var vertices := PackedVector3Array()
	var d := _surface_reference
	var west := float(d.west_cell_centre)
	var north := float(d.north_cell_centre)
	var east := west+(int(d.width)-1)*float(d.step_degrees)
	var south := north-(int(d.height)-1)*float(d.step_degrees)
	var frame := RegionProjection.frame(_local_surface_anchor)
	for feature: Dictionary in features:
		if str(feature.kind)!="river" or str(feature.geometry.type)!="LineString": continue
		var coordinates := feature.geometry.coordinates as Array
		for index: int in range(coordinates.size()-1):
			var a := Vector2(float(coordinates[index][0]),float(coordinates[index][1]))
			var b := Vector2(float(coordinates[index+1][0]),float(coordinates[index+1][1]))
			var delta := b-a
			var enter := 0.0
			var leave := 1.0
			for edge: Vector2 in [Vector2(-delta.x,a.x-west),Vector2(delta.x,east-a.x),Vector2(-delta.y,a.y-south),Vector2(delta.y,north-a.y)]:
				if is_zero_approx(edge.x):
					if edge.y<0.0: leave = -1.0
				elif edge.x<0.0: enter = maxf(enter,edge.y/edge.x)
				else: leave = minf(leave,edge.y/edge.x)
			if enter>=leave: continue
			var start := a+delta*enter
			var end := a+delta*leave
			var steps := clampi(ceili(start.distance_to(end)/float(d.step_degrees)),1,128)
			for part: int in range(steps):
				for fraction: float in [float(part)/steps,float(part+1)/steps]:
					var coordinate := start.lerp(end,fraction)
					var metric := RegionProjection.forward(GlobeProjection.lon_lat_to_unit(coordinate),frame)*1000.0
					vertices.append(Vector3(metric.x,_surface_height(coordinate)-_surface_base_height+0.6,-metric.y))
	if vertices.is_empty(): return
	# A thin centreline symbol follows the DEM; it is not a water polygon/width.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_surface_line_mesh = ArrayMesh.new()
	_surface_line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)

func surface_unit_at(pixel: Vector2) -> Vector3:
	if _local_surface==null or _landmark_camera==null: return Vector3.ZERO
	if pixel==_surface_pick_pixel: return _surface_pick_unit
	var inverse := _local_surface.global_transform.affine_inverse()
	var origin := inverse*_landmark_camera.project_ray_origin(pixel)
	var direction := inverse.basis*_landmark_camera.project_ray_normal(pixel)
	var end := origin+direction*_landmark_camera.far
	var nearest := INF
	var hit := Vector3.ZERO
	for chunk: Dictionary in _surface_pick_chunks:
		if (chunk.bounds as AABB).intersects_segment(origin,end)==null: continue
		for index: int in range(int(chunk.start),int(chunk.end),3):
			var intersection: Variant = Geometry3D.ray_intersects_triangle(origin,direction,_surface_vertices[_surface_indices[index]],_surface_vertices[_surface_indices[index+1]],_surface_vertices[_surface_indices[index+2]])
			if intersection==null: continue
			var distance := origin.distance_squared_to(intersection as Vector3)
			if distance<nearest:
				nearest = distance
				hit = intersection as Vector3
	_surface_pick_pixel = pixel
	_surface_pick_unit = RegionProjection.inverse(Vector2(hit.x,-hit.z)/1000.0,RegionProjection.frame(_local_surface_anchor)) if nearest<INF else Vector3.ZERO
	return _surface_pick_unit

func surface_screen_point(unit: Vector3) -> Vector2:
	var coordinate := RegionProjection.lon_lat(unit)
	if _local_surface==null or _landmark_camera==null or not _surface_contains(coordinate): return Vector2(INF,INF)
	var metric := RegionProjection.forward(unit,RegionProjection.frame(_local_surface_anchor))*1000.0
	return _landmark_camera.unproject_position(_local_surface.global_transform*Vector3(metric.x,_surface_height(coordinate)-_surface_base_height,-metric.y))

func release_landmarks() -> void:
	landmark_screen_bounds.clear()
	_landmark_presented.clear()
	_landmark_instances.clear()
	_landmark_view_key.clear()
	_local_surface = null
	_surface_lines = null
	if _landmark_root!=null:
		_landmark_root.visible = false
		_landmark_root.queue_free()
		_landmark_root = null
		_landmark_camera = null
		viewport.find_world_3d().environment = null
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
