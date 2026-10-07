class_name GlobeRenderer
extends Control
## One map renderer: geographic surfaces, final display borders and controller input.
const POLITICAL_UNDER_COLOR: Color = Color(0.10, 0.13, 0.15, 0.88)
const POLITICAL_INNER_COLOR: Color = Color(0.66, 0.63, 0.56, 0.88)
const POLITICAL_UNDER_WIDTH: float = 2.1
const POLITICAL_INNER_WIDTH: float = 0.9
const COAST_COLOR: Color = Color(0.22, 0.29, 0.30, 0.62)
const COAST_WIDTH: float = 0.65

var controller: GlobeController
var content: MapGeometryContent
var local_content: LocalSpatialLoader
var local_layer := LocalSpatialLayer.new()
var strategic_content: StrategicSpatialLoader
var strategic_layer := LocalSpatialLayer.new()
var relief := MapRelief.new()
# Empty until a separately sourced administrative-membership view exists.
# Camera changes never invalidate this cache; controller changes are separate.
var administrative_boundaries := AdministrativeBoundaryCache.new()
var _political_view: RuntimePoliticalEntityView
var input_blocked: Callable
var political := PoliticalLayer.new()
var _source_meshes: Dictionary = {}
var _source_boundaries: Array[Dictionary] = []
var _projected_surfaces: Dictionary = {}
var _unassigned_surfaces: Array[Dictionary] = []
var _projected_boundaries: Array[Dictionary] = []
var _anchors: Dictionary = {}
var _place_points: Dictionary = {}
var _center := Vector2.ZERO
var _radius: float = 220.0
var _globe_rect := Rect2()
var _projection_dirty: bool = true
var _view_dirty: bool = true
var _source_dirty: bool = true
var _surface_batches: Dictionary = {}
var _boundary_batches: Array[Dictionary] = []
var _font := UIDrawing.create_font()
var _surface_shader: Shader
var _physical_background: Dictionary = {}
var _relief_shader_warmed: bool = false
const TRANSITION_SECONDS: float = 0.22
var region_view := RegionView.new()
var _last_pointer := Vector2(-1.0, -1.0)
var _transition_elapsed: float = -1.0
var _transition_to_region: bool = false
var transition_metrics: Dictionary = {}
var local_transition_metrics: Dictionary = {}
var _region_anchor_km: Dictionary = {}
var _region_place_km: Dictionary = {}
var _region_labels_dirty: bool = true
var _region_label_frame := Basis()
var render_draw_count: int = 0
var view_update_count: int = 0
var cpu_projection_count: int = 0
var last_submit_usec: int = 0
var last_submit_parts: Dictionary = {}

static func _parameter(batch: Dictionary, name: StringName, value: Variant) -> void:
	if not batch.has("parameters"): batch["parameters"] = {}
	var values := batch.parameters as Dictionary
	if not values.has(name) or values[name] != value:
		(batch.material as ShaderMaterial).set_shader_parameter(name,value)
		values[name] = value

static func _bounds(batch: Dictionary, viewport_size: Vector2) -> void:
	if batch.get("bounds_size",Vector2.ZERO) != viewport_size:
		RenderingServer.canvas_item_set_custom_rect(batch.item as RID,true,Rect2(Vector2.ZERO,viewport_size))
		batch["bounds_size"] = viewport_size
@onready var _container: SubViewportContainer = $HemisphereViewportContainer
@onready var _viewport: SubViewport = $HemisphereViewportContainer/HemisphereViewport
@onready var _camera: Camera3D = $HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Camera3D
@onready var _moon: MeshInstance3D = $HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Moon

func _ready() -> void:
	# The existing viewport also retains the prepared 2D map. Static camera and
	# appearance reuse its texture instead of projecting all faces on the GPU.
	_viewport.world_2d = World2D.new()
	_surface_shader = load("res://shaders/presentation/map/political_surface.gdshader") as Shader
	region_view.initialize(self)
	_physical_background = {"material": ($HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Surface as MeshInstance3D).material_override}
	region_view.resize(size)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)

func _exit_tree() -> void:
	relief.dispose()
	local_layer.clear()
	strategic_layer.clear()
	if strategic_content != null: strategic_content.dispose()
	if local_content != null:
		local_content.dispose()
	_clear_surface_batches()
	_clear_boundary_batches()
	region_view.dispose()

func configure(content_value: MapGeometryContent, controller_value: GlobeController) -> void:
	_source_meshes.clear()
	_source_dirty = true
	content = content_value
	controller = controller_value
	if not controller.view_changed.is_connected(_invalidate_projection):
		controller.view_changed.connect(_invalidate_projection)
		controller.selection_changed.connect(queue_redraw)
		controller.appearance_changed.connect(queue_redraw)

func refresh(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView, places: Array[Dictionary], date: Dictionary, display: ResolvedMapContent) -> void:
	_political_view = registry
	political.refresh(registry, evidence, economy, places, date, content, display)
	if controller.region_camera.local_active and (local_content == null or local_content.content == null or not local_content.content.active_on(display.date())):
		controller.region_camera.leave_local()
	_region_labels_dirty = true
	# Geometry is admitted geography, not the list of currently active polities.
	# A dated identity's absence must not turn its existing land into ocean.
	for feature_id: String in content.feature_ids():
		if not _source_meshes.has(feature_id):
			_source_meshes[feature_id] = GlobeProjection.source_mesh(content.parts(feature_id), feature_id)
			(_source_meshes[feature_id] as Dictionary)["flag_bounds"] = _territory_uv_bounds(_source_meshes[feature_id] as Dictionary)
	if political.bind_source_meshes(_source_meshes, _source_dirty):
		region_view.clear()
		_source_boundaries = political.display_boundary_sources(GlobeProjection.boundary_sources(_source_meshes, political.boundary_features), content)
		_prepare_surface_batches()
		_prepare_boundary_batches()
	_source_dirty = false
	if not _relief_shader_warmed and DisplayServer.get_name() != "headless":
		_relief_shader_warmed = true
		_warm_relief_shaders()
	# The layer has rebuilt final macro ownership, including dated display links.
	_invalidate_projection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_invalidate_projection()

func _invalidate_projection() -> void:
	_projection_dirty = true
	_view_dirty = true
	queue_redraw()

func _ensure_projection() -> void:
	if not _projection_dirty or controller == null:
		return
	_projection_dirty = false
	cpu_projection_count += 1
	_ensure_view()
	_projected_surfaces.clear()
	_unassigned_surfaces.clear()
	var basis := controller.orientation()
	# CPU projection remains a detached geometry inspection query. Rendering
	# and ray picking use the prepared source faces without this per-face copy.
	for feature_id: String in _source_meshes:
		for triangle: Dictionary in political.display_faces_by_feature.get(feature_id, []) as Array:
			var projected := GlobeProjection.project_surface(triangle, basis, _center, _radius)
			if (projected.points as PackedVector2Array).size() >= 3 and GlobeProjection.polygon_area(projected.points) > 0.0:
				var owner := str(triangle.owner)
				if not owner.is_empty():
					if not _projected_surfaces.has(owner):
						_projected_surfaces[owner] = []
					(_projected_surfaces[owner] as Array).append(projected)
				else:
					_unassigned_surfaces.append(projected)
	_projected_boundaries.clear()
	for boundary: Dictionary in _source_boundaries:
		for points: PackedVector2Array in GlobeProjection.project_line(boundary.points, basis, _center, _radius):
			_projected_boundaries.append({"points": points, "owners": boundary.owners, "kind": boundary.kind})

func _ensure_view() -> void:
	if not _view_dirty or controller == null:
		return
	_view_dirty = false
	view_update_count += 1
	_container.position = Vector2.ZERO
	_container.size = size
	_center = size * 0.5
	var base_radius := minf(size.y / 2.55, size.x * 0.49)
	_radius = base_radius * controller.zoom
	_camera.size = 2.55 / controller.zoom
	_moon.visible = controller.zoom <= 1.10
	_globe_rect = Rect2(_center - Vector2.ONE * _radius, Vector2.ONE * _radius * 2.0).intersection(Rect2(Vector2.ZERO, size))
	region_view.resize(size)
	var regional := controller.region_camera.active
	if not regional:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _transition_elapsed < 0.0:
		_container.visible = not regional
		region_view.container.visible = regional
	if regional:
		_globe_rect = Rect2(Vector2.ZERO, size)
		if not region_view.ready and not region_view.preparing:
			region_view.begin(_surface_batches)
			set_process(visible)
		if _region_label_frame != controller.region_camera.tangent_frame:
			_region_labels_dirty = true
		if _region_labels_dirty:
			_prepare_region_labels()
	_sync_local_resources()
	_sync_strategic_resources()
	local_layer.update(controller.region_camera, controller, political.display_date, size)
	_update_strategic_layer()
	_anchors.clear()
	_place_points.clear()
	var basis := controller.orientation()
	for entity_id: String in political.records:
		var rotated := basis * (political.anchors.get(entity_id, Vector3.ZERO) as Vector3)
		if regional:
			var point := _region_label_point(_region_anchor_km[entity_id] as Vector2)
			if Rect2(Vector2.ZERO, size).has_point(point):
				_anchors[entity_id] = point
		elif rotated.z >= 0.0:
			_anchors[entity_id] = GlobeProjection.sphere_screen(rotated, _center, _radius)
	if regional or controller.zoom >= 1.55:
		for place_id: String in political.places:
			if controller.region_camera.local_active or (regional and strategic_content != null):
				continue
			var place := political.places[place_id] as Dictionary
			var raw_point: Variant = place.get("lon_lat", [])
			if not raw_point is Array or (raw_point as Array).size() < 2:
				continue
			var rotated := basis * GlobeProjection.lon_lat_to_unit(Vector2(float(raw_point[0]), float(raw_point[1])))
			if regional:
				var point := _region_label_point(_region_place_km[place_id] as Vector2)
				if Rect2(Vector2.ZERO, size).has_point(point):
					_place_points[place_id] = point
			elif rotated.z >= 0.0:
				_place_points[place_id] = GlobeProjection.sphere_screen(rotated, _center, _radius)
	_place_points.merge(strategic_layer.visible_places, true)
	_place_points.merge(local_layer.visible_places, true)

func _clear_surface_batches() -> void:
	for batch: Dictionary in _surface_batches.values():
		RenderingServer.free_rid(batch.item as RID)
	_surface_batches.clear()

func _prepare_surface_batches() -> void:
	_clear_surface_batches()
	var faces_by_owner: Dictionary = {}
	for faces: Array in political.display_faces_by_feature.values():
		for face: Dictionary in faces:
			var owner := str(face.owner)
			if not faces_by_owner.has(owner):
				faces_by_owner[owner] = []
			(faces_by_owner[owner] as Array).append(face)
	var owners := faces_by_owner.keys()
	if owners.has(""):
		owners.erase("")
		owners.push_front("")
	for owner: String in owners:
		var geometry := GlobeSurfaceBatch.new()
		geometry.prepare(faces_by_owner[owner] as Array)
		var material := ShaderMaterial.new()
		material.shader = _surface_shader
		material.set_shader_parameter("face_data", geometry.data)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, _viewport.world_2d.canvas)
		RenderingServer.canvas_item_set_draw_behind_parent(item, true)
		RenderingServer.canvas_item_set_draw_index(item, _surface_batches.size() + 1)
		RenderingServer.canvas_item_set_material(item, material.get_rid())
		_surface_batches[owner] = {"geometry": geometry, "material": material, "item": item, "texture": RID()}
	for background: Dictionary in [_physical_background, region_view.background]: background.erase("surface_relief_style")
	_bind_relief()

func _draw_surfaces(regional: bool = false) -> void:
	var basis := controller.orientation()
	var batches := region_view.surfaces if regional else _surface_batches
	var mpp := controller.region_camera.km_per_pixel * 1000.0 if regional else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, basis), basis, _radius) * 1000.0
	var flag_blend := MapScaleStyle.flag_weight(mpp)
	var fill_weight := MapScaleStyle.political_weight(mpp) if controller.map_mode == "political" else 1.0
	_sync_relief()
	# Scale weights are shared by all countries. Texture bindings change only
	# on residency/source preparation; a pan must not repeat either per owner.
	var relief_style := Vector2(MapScaleStyle.relief_weight(mpp, controller.map_mode) if relief.textures.has("world") else 0.0,
		MapScaleStyle.relief_detail_weight(mpp) if relief.textures.has("region") else 0.0)
	var background := region_view.background if regional else _physical_background
	var style_key := Vector3(relief_style.x, relief_style.y, float(batches.size()))
	var relief_style_changed: bool = background.get("surface_relief_style", Vector3(-1.0, -1.0, -1.0)) != style_key
	_parameter(background, "relief_weight", relief_style.x)
	if regional:
		_parameter(background, "relief_detail_weight", relief_style.y)
		_set_region_uniforms(background)
	else:
		_parameter(background, "globe_basis", basis)
	for owner: String in batches:
		var batch := batches[owner] as Dictionary
		var material := batch.material as ShaderMaterial
		var color := Color("465451") if owner.is_empty() else political.color(owner, controller.map_mode)
		var base_color := Color(str((political.resolved_visuals.get(owner, {}) as Dictionary).get("color", "#6b8075"))) if controller.map_mode == "political" else color
		if not owner.is_empty() and owner == controller.selected_polity_id:
			color = color.lerp(Color(0.62, 0.51, 0.31), 0.22)
			base_color = base_color.lerp(Color(0.62, 0.51, 0.31), 0.22)
		elif not owner.is_empty() and owner == controller.hovered_polity_id:
			color = color.lightened(0.035)
		var texture: Texture2D = political.visual_textures.get(owner) if controller.map_mode == "political" else null
		var texture_rid := texture.get_rid() if texture != null else RID()
		var bounds := Rect2(Vector2.ZERO, Vector2.ONE)
		var uv_scale := Vector2.ONE
		var uv_offset := Vector2.ZERO
		var uv_rotation := 0.0
		if texture != null:
			var style := (political.resolved_visuals[owner] as Dictionary).map_visual as Dictionary
			var feature_id := str((political.records[owner] as Dictionary).get("geometry_feature_id", ""))
			bounds = (_source_meshes[feature_id] as Dictionary).flag_bounds as Rect2
			if political.region_frames.has(owner):
				bounds = Rect2(Vector2.ZERO, Vector2.ONE)
			uv_scale = Vector2(float(style.uv_scale[0]), float(style.uv_scale[1]))
			uv_offset = Vector2(float(style.uv_offset[0]), float(style.uv_offset[1]))
			uv_rotation = deg_to_rad(float(style.uv_rotation))
		color.a = 1.0 if texture != null else 0.0
		_parameter(batch, "surface_color", color)
		_parameter(batch, "political_base_color", Vector3(base_color.r, base_color.g, base_color.b))
		_parameter(batch, "flag_weight", flag_blend)
		_parameter(batch, "political_weight", fill_weight)
		if relief_style_changed:
			_parameter(batch, "relief_weight", relief_style.x)
			_parameter(batch, "relief_detail_weight", relief_style.y)
		if regional:
			_set_region_uniforms(batch)
		else:
			_parameter(batch, "globe_basis", basis)
			_parameter(batch, "globe_center", _center)
			_parameter(batch, "globe_radius", _radius)
		_parameter(batch, "flag_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
		_parameter(batch, "flag_uv_scale", uv_scale)
		_parameter(batch, "flag_uv_offset", uv_offset)
		_parameter(batch, "flag_uv_rotation", Vector2(cos(uv_rotation), sin(uv_rotation)))
		_bounds(batch,size)
		if not bool(batch.get("submitted", false)) or (batch.texture as RID) != texture_rid:
			RenderingServer.canvas_item_clear(batch.item as RID)
			RenderingServer.canvas_item_add_mesh(batch.item as RID, (batch.geometry as GlobeSurfaceBatch).mesh.get_rid(), Transform2D(), Color.WHITE, texture_rid)
			batch["texture"] = texture_rid
			batch["submitted"] = true
	background["surface_relief_style"] = style_key
	var detail_used := relief_style.y > 0.0
	if relief.needs_presented(detail_used): _relief_presented(detail_used)

func _sync_relief(mpp: float = -1.0) -> void:
	if mpp < 0.0:
		mpp = controller.region_camera.km_per_pixel * 1000.0 if controller.region_camera.active else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, controller.orientation()), controller.orientation(), _radius) * 1000.0
	if relief.request(visible, mpp):
		_bind_relief()
	if relief.preparing(): set_process(visible)

func _bind_relief() -> void:
	# Clear both cached canvases on release: hidden materials must not retain a
	# discarded high LOD through a shader parameter or its uniform-value cache.
	for batches: Dictionary in [_surface_batches, region_view.surfaces]:
		for batch: Dictionary in batches.values():
			_parameter(batch, "relief_world", relief.textures.get("world"))
			_parameter(batch, "relief_region", relief.textures.get("region", relief.textures.get("world")))
	for background: Dictionary in [_physical_background, region_view.background]:
		_parameter(background, "relief_world", relief.textures.get("world"))
	_parameter(region_view.background, "relief_region", relief.textures.get("region", relief.textures.get("world")))

func _warm_relief_shaders() -> void:
	# Compatibility compiles its GL programs on first use. Render one existing
	# source mesh in each cached viewport during world creation, before map
	# interaction. The 1-pixel neutral sample is not a terrain asset or fact.
	# No DEM/LOD is loaded, no source geometry is copied, no idle work remains.
	if _surface_batches.is_empty(): return
	var started := Time.get_ticks_usec()
	var neutral := ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_RG8, PackedByteArray([128, 0])))
	var owner := "state:country_fra" if _surface_batches.has("state:country_fra") else str(_surface_batches.keys()[0])
	var source := _surface_batches[owner] as Dictionary
	var flag := political.visual_textures.get(owner) as Texture2D
	var items: Array[RID] = []
	var materials: Array[ShaderMaterial] = []
	for regional: bool in [false, true]:
		for textured: bool in [false, true]:
			var material := (source.material as ShaderMaterial).duplicate() as ShaderMaterial
			material.set_shader_parameter("region_mode", regional)
			material.set_shader_parameter("relief_world", neutral)
			material.set_shader_parameter("relief_region", neutral)
			material.set_shader_parameter("relief_weight", 0.1)
			material.set_shader_parameter("relief_detail_weight", 0.5)
			material.set_shader_parameter("globe_center", size * 0.5)
			material.set_shader_parameter("globe_basis", RegionProjection.frame(LocalSpatialLoader.ANCHOR).transposed())
			var item := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(item, region_view.viewport.world_2d.canvas if regional else _viewport.world_2d.canvas)
			RenderingServer.canvas_item_set_material(item, material.get_rid())
			RenderingServer.canvas_item_set_custom_rect(item, true, Rect2(Vector2.ZERO, size))
			RenderingServer.canvas_item_add_mesh(item, (source.geometry as GlobeSurfaceBatch).mesh.get_rid(), Transform2D(), Color.WHITE, flag.get_rid() if textured and flag != null else RID())
			items.append(item)
			materials.append(material)
	for background: Dictionary in [_physical_background, region_view.background]:
		_parameter(background, "relief_world", neutral)
		_parameter(background, "relief_weight", 0.1)
	_parameter(region_view.background, "relief_region", neutral)
	_parameter(region_view.background, "relief_detail_weight", 0.5)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Flush this finite world-creation preparation, rather than relying on a
	# post-draw signal which can belong only to the visible Person viewport.
	RenderingServer.force_draw(false)
	relief.metrics["shader_warmup_region_objects"] = RenderingServer.viewport_get_render_info(region_view.viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for item: RID in items: RenderingServer.free_rid(item)
	if not is_inside_tree(): return
	_bind_relief()
	for background: Dictionary in [_physical_background, region_view.background]: _parameter(background, "relief_weight", 0.0)
	relief.metrics["shader_warmup_usec"] = Time.get_ticks_usec() - started
	if not visible:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _relief_presented(detail_used: bool) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	if is_inside_tree() and visible: relief.mark_presented(detail_used)

func _territory_uv_bounds(mesh: Dictionary) -> Rect2:
	# Fit one complete flag to the largest current connected surface. All other
	# components share this geographic mapping; it does not depend on the view.
	var components: Dictionary = {}
	for triangle: Dictionary in mesh.triangles:
		var component := int(triangle.component_index)
		var uv := triangle.uvs as PackedVector2Array
		var sphere := triangle.points as PackedVector3Array
		if not components.has(component):
			components[component] = {"area": 0.0, "bounds": Rect2(uv[0], Vector2.ZERO)}
		var record := components[component] as Dictionary
		record.area += (sphere[1] - sphere[0]).cross(sphere[2] - sphere[0]).length() * 0.5
		for point: Vector2 in uv:
			record.bounds = (record.bounds as Rect2).expand(point)
	var bounds := Rect2(Vector2.ZERO, Vector2.ONE)
	var largest := 0.0
	for record: Dictionary in components.values():
		if float(record.area) > largest:
			largest = float(record.area)
			bounds = record.bounds as Rect2
	bounds.size = bounds.size.max(Vector2.ONE * GlobeProjection.SOURCE_EPSILON)
	return bounds

func _clear_boundary_batches() -> void:
	for batch: Dictionary in _boundary_batches:
		RenderingServer.free_rid(batch.item as RID)
	_boundary_batches.clear()

func _prepare_boundary_batches() -> void:
	_clear_boundary_batches()
	var shader := load("res://shaders/presentation/map/globe_boundary.gdshader") as Shader
	for kind: String in ["coast", "macro"]:
		var geometry := GlobeBoundaryBatch.new()
		geometry.prepare(_source_boundaries, kind)
		if geometry.segment_count == 0:
			continue
		var strokes: Array[Dictionary] = []
		if kind == "coast":
			strokes.append({"width": COAST_WIDTH, "color": COAST_COLOR})
		else:
			strokes.append({"width": POLITICAL_UNDER_WIDTH, "color": POLITICAL_UNDER_COLOR})
			strokes.append({"width": POLITICAL_INNER_WIDTH, "color": POLITICAL_INNER_COLOR})
		for stroke: Dictionary in strokes:
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("line_data", geometry.data)
			material.set_shader_parameter("stroke_width", stroke.width)
			material.set_shader_parameter("stroke_color", stroke.color)
			var item := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(item, _viewport.world_2d.canvas)
			RenderingServer.canvas_item_set_draw_behind_parent(item, true)
			RenderingServer.canvas_item_set_draw_index(item, _surface_batches.size() + _boundary_batches.size() + 1)
			RenderingServer.canvas_item_set_material(item, material.get_rid())
			RenderingServer.canvas_item_add_mesh(item, geometry.mesh.get_rid())
			_boundary_batches.append({"geometry": geometry, "material": material, "item": item})

func _draw_boundaries(regional: bool = false) -> void:
	for batch: Dictionary in region_view.boundaries if regional else _boundary_batches:
		var material := batch.material as ShaderMaterial
		if regional:
			_set_region_uniforms(batch)
		else:
			_parameter(batch, "globe_basis", controller.orientation())
			_parameter(batch, "globe_center", _center)
			_parameter(batch, "globe_radius", _radius)
		_bounds(batch,size)

func _draw() -> void:
	render_draw_count += 1
	if controller == null:
		return
	var view_was_dirty := _view_dirty
	_ensure_view()
	var regional := controller.region_camera.active and region_view.ready
	var submission_started := Time.get_ticks_usec()
	_draw_surfaces(regional)
	last_submit_parts["surfaces"] = Time.get_ticks_usec()-submission_started
	var part_started := Time.get_ticks_usec()
	_draw_boundaries(regional)
	last_submit_parts["boundaries"] = Time.get_ticks_usec()-part_started
	part_started = Time.get_ticks_usec()
	if not view_was_dirty:
		local_layer.update(controller.region_camera, controller, political.display_date, size)
	if controller.region_camera.local_active:
		_place_points = local_layer.visible_places.duplicate()
	else:
		_place_points.merge(strategic_layer.visible_places, true)
		_place_points.merge(local_layer.visible_places, true)
	if regional:
		_update_strategic_layer()
		_place_points.merge(strategic_layer.visible_places, false)
		var covered := local_layer.visible_places.duplicate()
		covered.merge(strategic_layer.visible_places)
		if strategic_content != null: covered.merge(political.places)
		var reserved := local_layer.label_rects.duplicate()
		reserved.append_array(strategic_layer.label_rects)
		region_view.update_labels(controller.region_camera, controller, _font, size, covered, reserved)
	last_submit_parts["labels"] = Time.get_ticks_usec()-part_started
	part_started = Time.get_ticks_usec()
	if _transition_elapsed >= 0.0 and not transition_metrics.has("target_canvas_submit_usec"):
		transition_metrics["target_canvas_submit_usec"] = Time.get_ticks_usec() - submission_started
	if regional:
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not local_transition_metrics.is_empty() and not local_transition_metrics.has("first_canvas_submit_usec"):
			local_transition_metrics["first_canvas_submit_usec"] = Time.get_ticks_usec() - int(local_transition_metrics.started_usec)
			local_transition_metrics["canvas_submit_usec"] = Time.get_ticks_usec() - submission_started
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	last_submit_parts["viewport"] = Time.get_ticks_usec()-part_started
	part_started = Time.get_ticks_usec()
	if _transition_elapsed >= 0.0:
		return
	for entity_id: String in _anchors:
		if entity_id in [controller.selected_polity_id, controller.hovered_polity_id]:
			draw_circle(_anchors[entity_id], 3.0, Color(0.82, 0.68, 0.40, 0.85))
	for place_id: String in _place_points:
		var selected := place_id == controller.selected_place_id
		var point := _place_points[place_id] as Vector2
		draw_circle(point, 4.5 if selected else 2.7, Color(0.96, 0.84, 0.55, 0.96))
		if regional:
			continue
		if controller.zoom >= 4.8 or selected or place_id == controller.hovered_place_id:
			UIDrawing.label(self, _font, point + Vector2(7.0, -6.0), str((political.places[place_id] as Dictionary).get("name", place_id)), 10)
	if not regional:
		GlobeLabels.draw(self, _font, _anchors, political.records, Rect2(Vector2.ZERO, size), controller.zoom, controller.selected_polity_id, controller.hovered_polity_id, controller.labels_enabled)
	var metric := controller.region_camera.km_per_pixel if regional else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, controller.orientation()), controller.orientation(), _radius)
	var space := MapScaleStyle.band(metric * 1000.0, regional, controller.region_camera.local_active)
	if not local_layer.visible_places.is_empty():
		space += " · Paris 1900 · 铁路走廊近似 · 现代水系参考"
	if not strategic_layer.active_lod.is_empty():
		space += " · 约1900战略骨架 · 虚线铁路位置概略 · 现代水系参考"
	if relief.textures.has("world"):
		space += " · ETOPO 2022 粗地形参考"
	if regional and not controller.region_camera.local_active and metric <= RegionCamera.LOCAL_ENTER_KM_PER_PIXEL:
		space += " · 详细地图资料准备中" if (local_content != null and local_content.preparing()) or local_layer.preparing else " · 更详细地图资料尚不可用"
	UIDrawing.label(self, _font, Vector2(20.0, size.y - 18.0), "%s · CShapes 2.0 历史政治边界    %s · %.0f m/px" % [political.display_date, space, metric * 1000.0], 10, Color(0.70, 0.79, 0.73, 0.8))
	last_submit_parts["dots_footer"] = Time.get_ticks_usec()-part_started
	last_submit_usec = Time.get_ticks_usec()-submission_started

func _gui_input(event: InputEvent) -> void:
	if controller == null:
		return
	if _transition_elapsed >= 0.0:
		accept_event()
		return
	if input_blocked.is_valid() and event is InputEventMouse:
		if bool(input_blocked.call((event as InputEventMouse).position + position)):
			controller.suspend_motion()
			controller.hover("", "")
			return
	_ensure_view()
	if event is InputEventMouse:
		_last_pointer = (event as InputEventMouse).position
	var wheel := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	var was_regional := controller.region_camera.active
	var unit := unit_at(_last_pointer)
	var bearing := RegionProjection.world_bearing(unit, controller.orientation()) if not unit.is_zero_approx() and not was_regional else 0.0
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		controller.begin_bearing(unit,_last_pointer)
	var clicked := controller.handle_input(event, _globe_rect)
	if wheel:
		if not was_regional and not unit.is_zero_approx():
			_ensure_view()
			var xy := (_last_pointer - _center) / _radius
			if xy.length_squared() < 0.98:
				var scale := RegionProjection.EARTH_RADIUS_KM / (_radius * pow(1.0 - xy.length_squared(), 0.25))
				var restored := RegionProjection.restore_world(unit, _last_pointer, _center, scale, bearing)
				controller._orientation = (restored.orientation as Basis).get_rotation_quaternion()
				_invalidate_projection()
		_ensure_view()
		_evaluate_scale()
	if event is InputEventMouseMotion or clicked:
		var point: Vector2 = (event as InputEventMouseMotion).position if event is InputEventMouseMotion else (event as InputEventMouseButton).position
		var place_id := _place_at(point)
		var polity_id := _polity_at(point)
		if not place_id.is_empty():
			var place := local_layer.place(place_id) if local_layer.visible_places.has(place_id) else strategic_layer.place(place_id) if strategic_layer.visible_places.has(place_id) else political.places[place_id] as Dictionary
			polity_id = _political_view.runtime_id_for_source(str(place.get("parent_country_id", "")))
		controller.hover(polity_id, place_id)
		if clicked:
			# A real place remains selectable when its legacy country reference has
			# no current polity crosswalk. Do not infer that mapping from a polygon.
			controller.select(polity_id, place_id)
	accept_event()

func _polity_at(point: Vector2) -> String:
	if controller.region_camera.active:
		var unit := controller.region_camera.unit_at(point)
		if unit.is_zero_approx():
			return ""
		for owner: String in _surface_batches:
			if not owner.is_empty() and ((_surface_batches[owner] as Dictionary).geometry as GlobeSurfaceBatch).contains_region_point(unit, point, controller.region_camera):
				return str((political.records[owner] as Dictionary).get("runtime_entity_id", owner))
		return ""
	var normalized := (point - _center) / _radius
	if normalized.length_squared() > 1.0:
		return ""
	var basis := controller.orientation()
	var inverse := basis.inverse()
	var origin := inverse * Vector3(normalized.x, -normalized.y, 1.2)
	var direction := inverse * Vector3.FORWARD
	for owner: String in _surface_batches:
		if not owner.is_empty() and ((_surface_batches[owner] as Dictionary).geometry as GlobeSurfaceBatch).contains_screen_point(origin, direction, basis, point, _center, _radius):
			return str((political.records[owner] as Dictionary).get("runtime_entity_id", owner))
	return ""

func _place_at(point: Vector2) -> String:
	for place_id: String in _place_points:
		if point.distance_to(_place_points[place_id] as Vector2) <= 8.0:
			return place_id
	return ""

func focus_selection() -> void:
	controller.focus(political.anchors.get(controller.selected_polity_id, Vector3.ZERO) as Vector3)

func _on_mouse_exited() -> void:
	if controller != null:
		controller.suspend_motion()
		controller.hover("", "")
	_last_pointer = Vector2(-1.0, -1.0)

func unit_at(pixel: Vector2) -> Vector3:
	_ensure_view()
	return controller.region_camera.unit_at(pixel) if controller.region_camera.active else RegionProjection.world_unit(pixel, _center, _radius, controller.orientation())

func screen_point(unit: Vector3) -> Vector2:
	_ensure_view()
	return controller.region_camera.project(unit) if controller.region_camera.active else GlobeProjection.sphere_screen(controller.orientation() * unit, _center, _radius)

func _set_region_uniforms(batch: Dictionary) -> void:
	var camera := controller.region_camera
	_parameter(batch, "globe_basis", camera.tangent_frame.transposed())
	_parameter(batch, "globe_center", camera.origin)
	_parameter(batch, "region_km_per_pixel", camera.km_per_pixel)
	_parameter(batch, "region_bearing", Vector2(cos(camera.bearing), sin(camera.bearing)))

func _evaluate_scale() -> void:
	if _transition_elapsed >= 0.0:
		return
	var pixel := _last_pointer
	var unit := unit_at(pixel) if Rect2(Vector2.ZERO, size).has_point(pixel) else Vector3.ZERO
	if unit.is_zero_approx():
		pixel = size * 0.5
		unit = unit_at(pixel)
	if unit.is_zero_approx() and controller.region_camera.local_active:
		unit = RegionProjection.inverse(controller.region_camera.local_center_km, controller.region_camera.tangent_frame)
		pixel = controller.region_camera.project(unit)
	if unit.is_zero_approx():
		return
	var camera := controller.region_camera
	_sync_local_resources()
	if camera.active:
		var scale := camera.scale_at(unit)
		if local_content != null and scale <= LocalSpatialLoader.PREWARM_KM_PER_PIXEL and LocalSpatialLoader.covers(RegionProjection.lon_lat(unit)):
			local_content.request()
			if local_content.preparing() or local_layer.preparing:
				set_process(visible)
		if camera.local_active:
			if scale >= RegionCamera.LOCAL_EXIT_KM_PER_PIXEL:
				_record_local_handoff(false, unit, pixel)
			return
		if scale <= RegionCamera.LOCAL_ENTER_KM_PER_PIXEL and region_view.ready and LocalSpatialLoader.covers(RegionProjection.lon_lat(unit)):
			var resolve_started := Time.get_ticks_usec()
			if local_content == null or local_content.content == null or not local_layer.available_lods.has("local") or not local_content.content.active_on(political.display_date):
				return
			var paris := GlobeProjection.lon_lat_to_unit(LocalSpatialLoader.ANCHOR)
			var paris_pixel := camera.project(paris)
			if camera.enter_local(paris, paris_pixel, size, "place:paris"):
				_record_local_handoff(true, unit, pixel)
				local_transition_metrics["data_resolve_usec"] = Time.get_ticks_usec() - resolve_started
				local_transition_metrics.merge(local_layer.metrics, true)
			return
		if scale >= RegionCamera.EXIT_KM_PER_PIXEL:
			var frame := RegionProjection.frame(RegionProjection.lon_lat(unit))
			# Bearing at the exit anchor includes local meridian convergence.
			var north_step := camera.project((unit + frame.y * 0.0001).normalized()) - camera.project(unit)
			var angle := atan2(north_step.x, -north_step.y)
			var restored := RegionProjection.restore_world(unit, pixel, _center, scale, angle)
			controller._orientation = (restored.orientation as Basis).get_rotation_quaternion()
			controller.zoom = float(restored.radius) / minf(size.y / 2.55, size.x * 0.49)
			camera.active = false
			_begin_transition(false, unit, pixel)
		return
	var scale := RegionProjection.world_scale(unit, controller.orientation(), _radius)
	# Start while still in the World/Region handoff so a pause immediately
	# after entry does not require another wheel event to request the shard.
	if local_content != null and scale <= LocalSpatialLoader.PREWARM_KM_PER_PIXEL and LocalSpatialLoader.covers(RegionProjection.lon_lat(unit)):
		local_content.request()
		if local_content.preparing() or local_layer.preparing:
			set_process(visible)
	if scale <= RegionCamera.PREWARM_KM_PER_PIXEL and not region_view.ready and not region_view.preparing:
		region_view.begin(_surface_batches)
		set_process(visible)
	if scale <= RegionCamera.ENTER_KM_PER_PIXEL and region_view.ready:
		camera.enter(unit, pixel, scale, RegionProjection.world_bearing(unit, controller.orientation()), size)
		_region_labels_dirty = true
		_begin_transition(true, unit, pixel)

func _sync_local_resources() -> void:
	if local_content == null or local_content.content == null or _transition_elapsed >= 0.0:
		return
	var camera := controller.region_camera
	var center_unit := camera.unit_at(size*0.5) if camera.active else unit_at(size*0.5)
	var supported := not center_unit.is_zero_approx() and LocalSpatialLoader.covers(RegionProjection.lon_lat(center_unit))
	if camera.active and supported and local_content.content.active_on(political.display_date):
		local_layer.request_lods(camera.km_per_pixel*1000.0)
		if local_layer.preparing: set_process(visible)
	else:
		local_layer.release_gpu()

func _sync_strategic_resources() -> void:
	if strategic_content == null or controller == null: return
	var camera := controller.region_camera
	if not visible or not camera.active:
		strategic_layer.clear()
		strategic_content.release()
		return
	var center := RegionProjection.lon_lat(camera.unit_at(size*0.5))
	strategic_content.request(center, camera.km_per_pixel*size.length()*0.5, political.display_date)
	if strategic_content.content != null and strategic_content.content != strategic_layer.content_reference():
		strategic_layer.rail_style = 3
		strategic_layer.begin(strategic_content.content,region_view.viewport.world_2d.canvas)
	if strategic_content.content == null and not strategic_content.preparing(): strategic_layer.clear()
	strategic_layer.request_lods(camera.km_per_pixel*1000.0)
	if strategic_content.preparing() or strategic_layer.preparing: set_process(visible)

func _update_strategic_layer() -> void:
	strategic_layer.suppressed_places = local_layer.visible_places
	strategic_layer.paris_mask_weights = {}
	if not local_layer.active_lod.is_empty():
		strategic_layer.paris_mask_weights["river"] = MapScaleStyle.physical_weight("river",controller.region_camera.km_per_pixel*1000.0)
	strategic_layer.update(controller.region_camera,controller,political.display_date,size)

func _record_local_handoff(entering: bool, unit: Vector3, pixel: Vector2) -> void:
	var started := Time.get_ticks_usec()
	if not entering:
		controller.region_camera.leave_local()
	local_transition_metrics = {"direction": "REGION_TO_LOCAL" if entering else "LOCAL_TO_REGION",
		"anchor_lon_lat": RegionProjection.lon_lat(unit), "anchor_pixel": pixel,
		"anchor_delta": controller.region_camera.project(unit) - pixel,
		"meters_per_pixel": controller.region_camera.scale_at(unit) * 1000.0,
		"place_id": controller.region_camera.local_place_id, "data_resolve_usec": Time.get_ticks_usec() - started,
		"file_read_usec": 0, "parse_usec": 0, "geometry_usec": 0, "new_geometry_upload_bytes": 0,
		"label_prepare_usec": 0, "transition_usec": 0, "started_usec": started}
	# Both spaces use the same prepared canvas/projection. No fade or additional
	# viewport is needed; hidden and idle behaviour stays the REGION behaviour.
	_invalidate_projection()

func _begin_transition(to_region: bool, unit: Vector3, pixel: Vector2) -> void:
	controller.suspend_motion()
	# Refresh the departing cached texture at the final wheel position once.
	_draw_surfaces(not to_region)
	_draw_boundaries(not to_region)
	if to_region:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_transition_to_region = to_region
	_transition_elapsed = 0.0
	_container.visible = true
	region_view.container.visible = true
	_container.modulate.a = 1.0
	region_view.container.modulate.a = 0.0 if to_region else 1.0
	transition_metrics = {"anchor_lon_lat": RegionProjection.lon_lat(unit), "anchor_pixel": pixel,
		"prepare_items_usec": region_view.preparation_usec, "geometry_usec": 0, "geometry_shared": true,
		"new_geometry_upload_bytes": 0, "new_geometry_upload_usec": 0,
		"started_usec": Time.get_ticks_usec(), "direction": "WORLD_TO_REGION" if to_region else "REGION_TO_WORLD"}
	_invalidate_projection()
	set_process(visible)

func _process(_delta: float) -> void:
	if not visible:
		set_process(false)
		return
	if relief.poll():
		_bind_relief()
		queue_redraw()
	_sync_relief()
	if region_view.preparing:
		region_view.prepare_step(_surface_batches, _boundary_batches)
		if region_view.ready:
			_evaluate_scale()
			if controller.region_camera.active:
				queue_redraw()
	if strategic_content != null and strategic_content.poll():
		_sync_strategic_resources()
		_invalidate_projection()
	if strategic_layer.preparing:
		strategic_layer.prepare_step(_font)
		_invalidate_projection()
	if local_content != null and local_content.poll():
		if local_content.content.errors.is_empty():
			local_layer.begin(local_content.content, region_view.viewport.world_2d.canvas)
			_sync_local_resources()
	if local_layer.preparing:
		local_layer.prepare_step(_font)
		queue_redraw()
		if local_layer.ready:
			_evaluate_scale()
			_invalidate_projection()
	if _transition_elapsed >= 0.0:
		_transition_elapsed = float(Time.get_ticks_usec() - int(transition_metrics.started_usec)) / 1000000.0
		var weight := clampf(_transition_elapsed / TRANSITION_SECONDS, 0.0, 1.0)
		region_view.container.modulate.a = weight if _transition_to_region else 1.0 - weight
		# REGION is the upper cached canvas. Keep WORLD opaque underneath;
		# fading both layers would expose the background and darken the midpoint.
		_container.modulate.a = 1.0
		if weight >= 1.0:
			_transition_elapsed = -1.0
			transition_metrics["elapsed_usec"] = Time.get_ticks_usec() - int(transition_metrics.started_usec)
			_on_visibility_changed()
			_evaluate_scale()
			queue_redraw()
	if _transition_elapsed < 0.0:
		_sync_local_resources()
	if not relief.preparing() and not region_view.preparing and not strategic_layer.preparing and (strategic_content == null or not strategic_content.preparing()) and not local_layer.preparing and (local_content == null or not local_content.preparing()) and _transition_elapsed < 0.0:
		set_process(false)

func _on_visibility_changed() -> void:
	if controller == null:
		return
	_sync_relief()
	_sync_strategic_resources()
	if not visible:
		_transition_elapsed = -1.0
		set_process(false)
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_container.visible = not controller.region_camera.active
		region_view.container.visible = controller.region_camera.active
		_container.modulate.a = 1.0
		region_view.container.modulate.a = 1.0
		set_process(strategic_layer.preparing or (strategic_content != null and strategic_content.preparing()) or relief.preparing() or region_view.preparing or local_layer.preparing or (local_content != null and local_content.preparing()))
		queue_redraw()

func _prepare_region_labels() -> void:
	var started := Time.get_ticks_usec()
	_region_anchor_km.clear()
	_region_place_km.clear()
	var frame := controller.region_camera.tangent_frame
	_region_label_frame = frame
	var labels: Array[Dictionary] = []
	for entity_id: String in political.records:
		_region_anchor_km[entity_id] = RegionProjection.forward(political.anchors.get(entity_id, Vector3.ZERO) as Vector3, frame)
		var record := political.records[entity_id] as Dictionary
		labels.append({"id": entity_id, "km": _region_anchor_km[entity_id], "text": str(record.get("short_name_zh", record.get("name_zh", entity_id))), "rank": int(record.get("label_rank", 9)) + 10, "font_size": 11, "place": false})
	for place_id: String in political.places:
		var raw_point: Variant = (political.places[place_id] as Dictionary).get("lon_lat", [])
		if raw_point is Array and (raw_point as Array).size() >= 2:
			_region_place_km[place_id] = RegionProjection.forward(GlobeProjection.lon_lat_to_unit(Vector2(float(raw_point[0]), float(raw_point[1]))), frame)
			# Formal Region cities come from admitted spatial content. Keeping
			# prototype cities in the label source can resurrect them on redraw.
			if strategic_content == null:
				labels.append({"id": place_id, "km": _region_place_km[place_id], "text": str((political.places[place_id] as Dictionary).get("name", place_id)), "rank": 0, "font_size": 10, "place": true})
	region_view.prepare_labels(labels, _font)
	_region_labels_dirty = false
	transition_metrics["label_prepare_usec"] = Time.get_ticks_usec() - started

func _region_label_point(km: Vector2) -> Vector2:
	var camera := controller.region_camera
	return camera.origin + RegionProjection.screen_axes(camera.bearing) * (km / camera.km_per_pixel)
