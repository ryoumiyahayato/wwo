class_name GlobeRenderer
extends Control
signal place_content_ready
signal map_notice(message: String)
signal geographic_reference_selected(reference: Dictionary)
## One map renderer: geographic surfaces, final display borders and controller input.
const POLITICAL_UNDER_COLOR: Color = Color(0.60, 0.61, 0.54, 0.82)
const POLITICAL_INNER_COLOR: Color = Color(0.66, 0.63, 0.56, 0.88)
const POLITICAL_UNDER_WIDTH: float = 1.05
const POLITICAL_INNER_WIDTH: float = 0.9
const COAST_COLOR: Color = Color(0.22, 0.29, 0.30, 0.62)
const COAST_WIDTH: float = 0.65

var preserve_on_reparent: bool = false
var show_footer: bool = false
var controller: GlobeController
var spatial_world: VNextSpatialWorld
var content: MapGeometryContent
var local_content: LocalSpatialLoader
var local_layer := LocalSpatialLayer.new()
var strategic_content: StrategicSpatialLoader
var strategic_layer := LocalSpatialLayer.new()
var relief := MapRelief.new()
var _political_view: RuntimePoliticalEntityView
var input_blocked: Callable
var label_exclusions: Callable
var political := PoliticalLayer.new()
var _source_meshes: Dictionary = {}
var _source_boundaries: Array[Dictionary] = []
var _boundary_source_revision: int = 0
const HOME_BORDER_COLOR: Color = Color(0.80,0.73,0.53,0.90)
var _focus_border_key: Array = []
var _land_neighbors: Dictionary = {}
var _related_polities: Dictionary = {}
var _anchors: Dictionary = {}
var _place_points: Dictionary = {}
var _landmark_symbols: Dictionary = {}
var _unassigned_pick: bool = false
var _center := Vector2.ZERO
var _radius: float = 220.0
var _globe_rect := Rect2()
var _view_dirty: bool = true
var _source_dirty: bool = true
var _surface_batches: Dictionary = {}
var _boundary_batches: Array[Dictionary] = []
var _font: Font = preload("res://assets/fonts/map/EBGaramond-Medium.ttf")
var _city_fonts: Dictionary = {}
var _country_font: Font = preload("res://assets/fonts/map/EBGaramond-Medium.ttf")
var _geographic_records: Dictionary = {}
var _geographic_cells: Dictionary = {}
var _country_label_layouts: Dictionary = {}
var _world_label_records: Dictionary = {}
var _world_labels := GlobeLabels.new()
var _label_setting: bool = false
var _surface_shader: Shader
var _physical_background: Dictionary = {}
var _relief_shader_warmed: bool = false
const TRANSITION_SECONDS: float = 0.22
var region_view := RegionView.new()
var _last_pointer := Vector2(-1.0, -1.0)
var _transition_elapsed: float = -1.0
var _transition_to_region: bool = false
var _transition_started: int = 0
var _region_anchor_km: Dictionary = {}
var _region_place_km: Dictionary = {}
var _region_labels_dirty: bool = true
var _region_label_frame := Basis()
var _footer_prefix_item := RID()
var _footer_scale_item := RID()
var _footer_prefix: String = ""
var _footer_scale: String = ""
var _footer_prefix_width: float = 0.0
var _overlay_batches: Dictionary = {}
var _overlay_demand: Array[Dictionary] = []
var _overlay_thread: Thread
var _overlay_generation: int = 0
var _overlay_mutex := Mutex.new()
var _overlay_uploads: Array[Dictionary] = []
var _overlay_installing: Dictionary = {}
var _overlay_query_id: String = ""
var _overlay_view := Rect2()
var _overlay_revision: int = -1
var _overlay_owner: VNextSpatialWorld
var _overlay_request: Array = []


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
	region_view.landmark_display_changed.connect(queue_redraw)
	region_view.landmark_load_failed.connect(func(message: String) -> void: map_notice.emit(message))
	var chinese := preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf").duplicate() as FontFile
	_country_font = _country_font.duplicate() as FontFile
	_font = _country_font
	chinese.allow_system_fallback = false
	(_country_font as FontFile).allow_system_fallback = false
	_country_font.fallbacks = [chinese]
	local_layer.label_font = _font
	strategic_layer.label_font = _font
	# The existing viewport also retains the prepared 2D map. Static camera and
	# appearance reuse its texture instead of projecting all faces on the GPU.
	_viewport.world_2d = World2D.new()
	_surface_shader = load("res://shaders/presentation/map/political_surface.gdshader") as Shader
	region_view.initialize(self)
	_physical_background = {"material": ($HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Surface as MeshInstance3D).material_override}
	region_view.resize(size)
	visibility_changed.connect(_on_visibility_changed)
	strategic_layer.display_changed.connect(_on_spatial_display_changed)
	local_layer.display_changed.connect(_on_spatial_display_changed)
	set_process(false)

func _exit_tree() -> void:
	if preserve_on_reparent: return
	_overlay_mutex.lock()
	_overlay_generation += 1
	_overlay_mutex.unlock()
	if _overlay_thread != null: _overlay_thread.wait_to_finish()
	_clear_overlay_installing()
	_clear_overlay_batches()
	_world_labels.clear()
	if _footer_prefix_item.is_valid(): RenderingServer.free_rid(_footer_prefix_item)
	if _footer_scale_item.is_valid(): RenderingServer.free_rid(_footer_scale_item)
	relief.dispose()
	local_layer.dispose()
	strategic_layer.dispose()
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
	bind_controller(controller_value)
	_country_label_layouts = content.presentation_document("country_labels").get("layouts", {}) as Dictionary
	_geographic_records.clear()
	_geographic_cells.clear()
	for annotation: Dictionary in content.presentation_document("geographic_annotations").get("annotations", []) as Array:
		var id := str(annotation.id)
		_geographic_records[id] = annotation
		var parts := content.parts(str(annotation.get("geometry_feature_id", "")))
		if annotation.has("geometry"):
			var coordinates := (annotation.geometry as Dictionary).coordinates as Array
			var components: Array = coordinates if str(annotation.geometry.type)=="MultiPolygon" else [coordinates]
			parts = []
			for component: Array in components:
				var holes: Array[PackedVector2Array] = []
				for ring: Array in component.slice(1): holes.append(political._ring(ring))
				parts.append({"outer":political._ring(component[0]),"holes":holes})
		var cells: Array[Dictionary] = []
		for part: Dictionary in parts:
			var bounds := GlobeProjection.lon_lat_bounds([part.outer])
			var axis := GlobeProjection.lon_lat_to_unit(bounds.get_center())
			var angle := 0.0
			for ll: Vector2 in part.outer as PackedVector2Array: angle = maxf(angle,axis.angle_to(GlobeProjection.lon_lat_to_unit(ll)))
			cells.append({"outer":part.outer,"holes":part.holes,"bounds":bounds,"cull_axis":axis,"cull_angle":angle})
		_geographic_cells[id] = cells
		annotation.erase("geometry")

static func prepare_source_geometry(source: MapGeometryContent) -> Dictionary:
	var meshes: Dictionary = {}
	for id: String in source.feature_ids():
		var mesh := GlobeProjection.source_mesh(source.parts(id),id)
		mesh["flag_bounds"] = _territory_uv_bounds(mesh)
		meshes[id] = mesh
	return meshes

func install_source_geometry(meshes: Dictionary) -> void:
	_source_meshes = meshes
	_source_dirty = true

func bind_controller(value: GlobeController) -> void:
	controller = value
	if not controller.view_changed.is_connected(_invalidate_projection): controller.view_changed.connect(_invalidate_projection)
	if not controller.selection_changed.is_connected(queue_redraw): controller.selection_changed.connect(queue_redraw)
	if not controller.appearance_changed.is_connected(queue_redraw): controller.appearance_changed.connect(queue_redraw)
	_camera.current = true
	_view_dirty = true
	queue_redraw()

func refresh(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView, places: Array[Dictionary], date: Dictionary, display: ResolvedMapContent) -> void:
	for background: Dictionary in [_physical_background,region_view.background]: background.erase("surface_appearance_style")
	_political_view = registry
	political.refresh(registry, evidence, economy, places, date, content, display)
	_related_polities.clear()
	for relation: Dictionary in registry.authority_relations():
		if str(relation.get("source_runtime_id",""))==controller.player_polity_id and str(relation.get("relation_type","")) in ["administration","protection","legacy_controller"]:
			_related_polities[str(relation.get("target_runtime_id",""))] = true
	_world_label_records = political.records.duplicate()
	for id: String in _geographic_records:
		if _geographic_active(id):
			_world_label_records[id] = _geographic_records[id].duplicate()
			(_world_label_records[id] as Dictionary)["geography"] = true
	for id: String in _world_label_records:
		var layout := _country_label_layouts.get(str((_world_label_records[id] as Dictionary).get("geometry_feature_id", "")), {}) as Dictionary
		if layout.has("name"):
			_world_label_records[id] = (_world_label_records[id] as Dictionary).duplicate()
			_world_label_records[id]["short_name_zh"] = layout.name
	if controller.region_camera.local_active and (local_content == null or local_content.content == null or not local_content.content.display_active_on(display.date())):
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
		_source_boundaries = _shared_border_display(_source_boundaries)
		_boundary_source_revision += 1
		for border: Dictionary in _source_boundaries:
			if str(border.kind)!="macro": continue
			var points := border.points as PackedVector3Array
			var axis := Vector3.ZERO
			for point: Vector3 in points: axis += point
			axis = axis.normalized()
			var angle := 0.0
			for point: Vector3 in points: angle = maxf(angle,axis.angle_to(point))
			border["cull_axis"] = axis
			border["cull_angle"] = angle
		_prepare_surface_batches()
		_prepare_boundary_batches()
	_source_dirty = false
	if not _relief_shader_warmed and DisplayServer.get_name() != "headless":
		_relief_shader_warmed = true
		_warm_relief_shaders()
	# The layer has rebuilt final macro ownership, including dated display links.
	_invalidate_projection()

func refresh_economic_observation(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView) -> void:
	political.refresh_economies(registry,evidence,economy)
	for background: Dictionary in [_physical_background,region_view.background]: background.erase("surface_appearance_style")
	queue_redraw()

func _shared_border_display(original: Array[Dictionary]) -> Array[Dictionary]:
	if political.display_date < "1900-01-01" or political.display_date >= "1901-01-01": return original
	var document := content.presentation_document("shared_borders")
	if document.is_empty(): return original
	var output: Array[Dictionary] = []
	var area := Rect2(Vector2(33.9,11.9),Vector2(27.2,23.2))
	for boundary: Dictionary in original:
		var points := PackedVector2Array()
		for point: Vector3 in boundary.points: points.append(RegionProjection.lon_lat(point))
		if str(boundary.kind) != "macro" or area.intersects(GlobeProjection.lon_lat_bounds([points]),true): output.append(boundary)
	var current_owners := political.get("_whole_owner_by_feature") as Dictionary
	for boundary: Dictionary in document.get("boundaries",[]) as Array:
		var features := boundary.source_features as Array
		var owners := PackedStringArray()
		for feature: String in features:
			var owner := str(current_owners.get(feature,""))
			if not owner.is_empty() and owner not in owners: owners.append(owner)
		if owners.size()!=2: continue
		var coordinates := PackedVector2Array()
		for point: Array in boundary.points: coordinates.append(Vector2(float(point[0]),float(point[1])))
		if area.intersects(GlobeProjection.lon_lat_bounds([coordinates]),true): continue
		output.append({"points":GlobeProjection.to_unit_line(coordinates),"owners":owners,"kind":"macro","detail_path":boundary.get("detail_path","")})
	return output

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_invalidate_projection()

func _invalidate_projection() -> void:
	_view_dirty = true
	queue_redraw()

func _ensure_view() -> void:
	if not _view_dirty or controller == null:
		return
	_view_dirty = false
	_container.position = Vector2.ZERO
	_container.size = size
	_center = size * 0.5
	var base_radius := minf(size.y / 2.55, size.x * 0.49)
	if controller.initial_framing_pending and visible and size.x > 0.0 and size.y > 0.0:
		controller.initial_framing_pending = false
		if not controller.region_camera.active and is_equal_approx(controller.zoom, 0.86):
			var target_radius := minf(float(get_window().size.y) / 3.0, minf(size.x, size.y) * 0.48)
			controller.zoom = clampf(target_radius / base_radius, GlobeController.MIN_ZOOM, GlobeController.MAX_ZOOM)
	_radius = base_radius * controller.zoom
	_camera.size = 2.55 / controller.zoom
	_moon.visible = controller.zoom <= 1.10
	_globe_rect = Rect2(_center - Vector2.ONE * _radius, Vector2.ONE * _radius * 2.0).intersection(Rect2(Vector2.ZERO, size))
	region_view.resize(size)
	var regional := controller.region_camera.active
	if not regional:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _transition_elapsed < 0.0:
		# Keep the existing WORLD canvas until REGION has actual prepared content.
		_container.visible = not (regional and region_view.ready)
		region_view.container.visible = regional and region_view.ready
		_container.modulate.a = 1.0
		region_view.container.modulate.a = 1.0
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
	# Queries need current picking/settlement positions, but the final draw
	# commits GPU uniforms and collision-prioritized glyphs once below.
	local_layer.update(controller.region_camera, controller, political.display_date, size, false)
	_update_strategic_layer(false)
	_anchors.clear()
	_place_points.clear()
	var basis := controller.orientation()
	for entity_id: String in political.records:
		if regional:
			if entity_id not in [controller.selected_polity_id,controller.hovered_polity_id]: continue
			var point := _region_label_point(_region_anchor_km[entity_id] as Vector2)
			if Rect2(Vector2.ZERO,size).has_point(point): _anchors[entity_id] = point
			continue
		var unit := political.anchors.get(entity_id, Vector3.ZERO) as Vector3
		var layout := _country_label_layouts.get(str((political.records[entity_id] as Dictionary).get("geometry_feature_id","")),{}) as Dictionary
		if not bool((political.records[entity_id] as Dictionary).get("display_only",false)) and not (layout.get("positions",[]) as Array).is_empty():
			var coordinates := (layout.positions[0] as Dictionary).lon_lat as Array
			unit = GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
		var rotated := basis * unit
		if rotated.z >= 0.0:
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
	if not regional:
		for id: String in _geographic_records:
			if not _geographic_active(id): continue
			var coordinates := (_geographic_records[id] as Dictionary).lon_lat as Array
			var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
			var rotated := basis * unit
			if rotated.z >= 0.0: _anchors[id] = GlobeProjection.sphere_screen(rotated,_center,_radius)

func _clear_surface_batches() -> void:
	for batch: Dictionary in _surface_batches.values():
		RenderingServer.free_rid(batch.item as RID)
	_surface_batches.clear()

func _prepare_surface_batches() -> void:
	_clear_surface_batches()
	var faces_by_owner: Dictionary = {}
	for feature_id: String in political.display_faces_by_feature:
		var faces := political.display_faces_by_feature[feature_id] as Array
		for face: Dictionary in faces:
			face["pick_component_key"] = feature_id+":"+str(face.component_index)+":"+str(face.get("political_map_region_id",""))
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
	for background: Dictionary in [_physical_background, region_view.background]:
		background.erase("surface_relief_style")
		background.erase("surface_appearance_style")
	_bind_relief()

func _sync_political_focus() -> void:
	var key: Array = [controller.player_polity_id,_boundary_source_revision]
	if key==_focus_border_key: return
	_focus_border_key = key
	_land_neighbors.clear()
	var home_lines: Array[Dictionary] = []
	if not controller.player_polity_id.is_empty():
		for border: Dictionary in _source_boundaries:
			if str(border.kind)!="macro" or controller.player_polity_id not in border.owners: continue
			home_lines.append(border)
			for id: String in border.owners:
				if id!=controller.player_polity_id: _land_neighbors[id] = true
	for group: Array[Dictionary] in [_boundary_batches,region_view.boundaries]:
		for index: int in range(group.size()-1,-1,-1):
			if not bool(group[index].get("home_border",false)): continue
			RenderingServer.free_rid(group[index].item)
			group.remove_at(index)
	if home_lines.is_empty(): return
	var geometry := GlobeBoundaryBatch.new()
	geometry.prepare(home_lines,"macro",true)
	for regional: bool in [false,true]:
		if regional and not region_view.ready: continue
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/presentation/map/globe_boundary.gdshader")
		material.set_shader_parameter("line_data",geometry.data)
		material.set_shader_parameter("region_mode",regional)
		material.set_shader_parameter("stroke_color",HOME_BORDER_COLOR)
		material.set_shader_parameter("stroke_width",1.35)
		material.set_shader_parameter("stroke_feather",0.65)
		material.set_shader_parameter("miter_limit",1.5)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item,region_view.map_canvas if regional else _viewport.world_2d.canvas)
		RenderingServer.canvas_item_set_draw_index(item,LocalSpatialLayer.DRAW_ORDER+2)
		RenderingServer.canvas_item_add_mesh(item,geometry.mesh.get_rid())
		RenderingServer.canvas_item_set_material(item,material.get_rid())
		var batch := {"geometry":geometry,"material":material,"item":item,"kind":"macro","home_border":true}
		if regional: region_view.boundaries.append(batch)
		else: _boundary_batches.append(batch)

func _political_emphasis(owner: String) -> float:
	if controller.player_polity_id.is_empty(): return 0.70
	if owner==controller.player_polity_id: return 1.0
	if _related_polities.has(owner): return 0.88
	if _land_neighbors.has(owner): return 0.58
	return 0.18

func _draw_surfaces(regional: bool = false) -> void:
	var basis := controller.orientation()
	var batches := region_view.surfaces if regional else _surface_batches
	var mpp := controller.region_camera.km_per_pixel * 1000.0 if regional else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, basis), basis, _radius) * 1000.0
	var flag_blend := MapScaleStyle.flag_weight(mpp) if controller.administrative_map_active() else 0.0
	var fill_weight := MapScaleStyle.political_weight(mpp) if controller.map_mode == "political" else 1.0
	_sync_relief()
	# Scale weights are shared by all countries. Texture bindings change only
	# on residency/source preparation; a pan must not repeat either per owner.
	var relief_style := Vector2(MapScaleStyle.relief_weight(mpp, controller.map_mode) if relief.textures.has("world") else 0.0,
		MapScaleStyle.relief_detail_weight(mpp) if relief.textures.has("region") else 0.0)
	var background := region_view.background if regional else _physical_background
	var appearance_key: Array = [controller.map_mode,controller.player_polity_id,controller.selected_polity_id,controller.hovered_polity_id,_focus_border_key]
	var appearance_changed: bool = background.get("surface_appearance_style",[]) != appearance_key
	# Once admitted physical land/sea coverage is ready, coarse DEM height
	# interpolation must not paint a second shoreline over its actual sea.
	var physical_coverage := regional and not strategic_layer.active_lod.is_empty()
	_parameter(background, "relief_weight", 0.0 if physical_coverage else relief_style.x)
	if regional:
		_parameter(background, "relief_detail_weight", relief_style.y)
		_set_region_uniforms(background)
	else:
		_parameter(background, "globe_basis", basis)
	var view_center := controller.region_camera.unit_at(size * 0.5) if regional else Vector3.ZERO
	var view_angle := (size.length() * 0.5 + 2.0) * controller.region_camera.km_per_pixel / 6371.0088
	for owner: String in batches:
		var batch := batches[owner] as Dictionary
		if appearance_changed:
			_apply_surface_appearance(batch,owner,flag_blend,fill_weight)
		if regional:
			var geometry := batch.geometry as GlobeSurfaceBatch
			var shown := view_center.is_zero_approx() or geometry.cull_angle >= PI * 0.5 or geometry.cull_axis.angle_to(view_center) <= geometry.cull_angle + view_angle
			if shown != bool(batch.get("visible", true)):
				RenderingServer.canvas_item_set_visible(batch.item as RID, shown)
				batch["visible"] = shown
			if not shown: continue
		_parameter(batch,"flag_weight",flag_blend)
		_parameter(batch,"political_weight",fill_weight)
		if batch.get("relief_style",Vector2(-1.0,-1.0)) != relief_style:
			_parameter(batch,"relief_weight",relief_style.x)
			_parameter(batch,"relief_detail_weight",relief_style.y)
			batch["relief_style"] = relief_style
		if regional:
			_set_region_uniforms(batch)
		else:
			_parameter(batch, "globe_basis", basis)
			_parameter(batch, "globe_center", _center)
			_parameter(batch, "globe_radius", _radius)
		_bounds(batch,size)
	background["surface_appearance_style"] = appearance_key

func _apply_surface_appearance(batch: Dictionary, owner: String, flag_blend: float, fill_weight: float) -> void:
	# Content refresh invalidates appearance; camera updates only projection.
	_parameter(batch,"political_focus_style",controller.administrative_map_active())
	_parameter(batch,"political_emphasis",_political_emphasis(owner))
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
	_parameter(batch, "flag_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	_parameter(batch, "flag_uv_scale", uv_scale)
	_parameter(batch, "flag_uv_offset", uv_offset)
	_parameter(batch, "flag_uv_rotation", Vector2(cos(uv_rotation), sin(uv_rotation)))
	if not bool(batch.get("submitted", false)) or (batch.texture as RID) != texture_rid:
		RenderingServer.canvas_item_clear(batch.item as RID)
		RenderingServer.canvas_item_add_mesh(batch.item as RID, (batch.geometry as GlobeSurfaceBatch).mesh.get_rid(), Transform2D(), Color.WHITE, texture_rid)
		batch["texture"] = texture_rid
		batch["submitted"] = true

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
			RenderingServer.canvas_item_set_parent(item, region_view.map_canvas if regional else _viewport.world_2d.canvas)
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
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for item: RID in items: RenderingServer.free_rid(item)
	if not is_inside_tree(): return
	_bind_relief()
	for background: Dictionary in [_physical_background, region_view.background]: _parameter(background, "relief_weight", 0.0)
	if not visible:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

static func _territory_uv_bounds(mesh: Dictionary) -> Rect2:
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
		for stroke: Dictionary in strokes:
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("line_data", geometry.data)
			material.set_shader_parameter("stroke_width", stroke.width)
			material.set_shader_parameter("stroke_color", stroke.color)
			material.set_shader_parameter("miter_limit", 1.5)
			material.set_shader_parameter("stroke_feather", 0.65)
			var item := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(item, _viewport.world_2d.canvas)
			RenderingServer.canvas_item_set_draw_behind_parent(item, true)
			RenderingServer.canvas_item_set_draw_index(item,LocalSpatialLayer.DRAW_ORDER+2 if kind=="macro" else _surface_batches.size()+_boundary_batches.size()+1)
			RenderingServer.canvas_item_set_material(item, material.get_rid())
			RenderingServer.canvas_item_add_mesh(item, geometry.mesh.get_rid())
			_boundary_batches.append({"geometry": geometry, "material": material, "item": item, "kind": kind})

func _draw_boundaries(regional: bool = false) -> void:
	var replacement := _country_overlay_ready() if regional else false
	for batch: Dictionary in region_view.boundaries if regional else _boundary_batches:
		var shown := not bool(batch.get("home_border",false)) or controller.administrative_map_active()
		var coast_weight := 1.0
		if regional:
			shown = shown and (not replacement or str(batch.get("kind",""))!="macro")
			if str(batch.get("kind", "")) == "coast" and not strategic_layer.active_lod.is_empty():
				coast_weight = 1.0-MapScaleStyle.strategic_weight("coast",controller.region_camera.km_per_pixel*1000.0)
				shown = shown and coast_weight>0.001
		if shown!=bool(batch.get("visible",true)):
			RenderingServer.canvas_item_set_visible(batch.item,shown)
			batch["visible"] = shown
		if not shown: continue
		if regional:
			_set_region_uniforms(batch)
			if str(batch.get("kind", "")) == "coast":
				var color := COAST_COLOR
				color.a *= coast_weight
				_parameter(batch,"stroke_color",color)
		else:
			_parameter(batch, "globe_basis", controller.orientation())
			_parameter(batch, "globe_center", _center)
			_parameter(batch, "globe_radius", _radius)
		_bounds(batch,size)

func _draw() -> void:
	if controller == null:
		return
	if _label_setting!=controller.labels_enabled:
		_label_setting = controller.labels_enabled
		_world_labels.clear()
		region_view.clear_labels()
		_region_labels_dirty = true
		_view_dirty = true
	var view_was_dirty := _view_dirty
	_ensure_view()
	if not view_was_dirty: _sync_strategic_resources()
	var regional := controller.region_camera.active and region_view.ready
	_sync_political_focus()
	_draw_surfaces(regional)
	_draw_boundaries(regional)
	if not regional:
		local_layer.update(controller.region_camera, controller, political.display_date, size)
	elif not view_was_dirty:
		local_layer.update(controller.region_camera, controller, political.display_date, size, false)
		_update_strategic_layer(false)
	if controller.region_camera.local_active:
		_place_points = local_layer.visible_places.duplicate()
	elif regional and strategic_content != null:
		_place_points = strategic_layer.visible_places.duplicate()
		_place_points.merge(local_layer.visible_places, true)
	else:
		_place_points.merge(strategic_layer.visible_places, true)
		_place_points.merge(local_layer.visible_places, true)
	if regional:
		_place_points.merge(strategic_layer.visible_places, false)
		var covered := local_layer.visible_places.duplicate()
		covered.merge(strategic_layer.visible_places)
		if strategic_content != null: covered.merge(political.places)
		region_view.update_labels(self,controller.region_camera, controller, _font, size, covered,_label_exclusions())
		var reserved := region_view.country_label_rects.duplicate()
		reserved.append_array(_label_exclusions())
		local_layer.reserved_label_rects = reserved
		local_layer.update(controller.region_camera, controller, political.display_date, size)
		strategic_layer.reserved_label_rects = reserved
		_update_strategic_layer()
	else:
		_update_strategic_layer()
	_sync_landmark_display()
	if regional:
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_world_labels.update(self,_country_font,_anchors,_world_label_records,Rect2(Vector2.ZERO,size),controller.zoom,controller.selected_polity_id,controller.hovered_polity_id,controller.labels_enabled,not regional and _transition_elapsed < 0.0,_label_exclusions())
	if _transition_elapsed >= 0.0:
		return
	if controller.labels_enabled:
		local_layer.draw_labels(self,_font)
		strategic_layer.draw_labels(self,_font)
	_draw_administrative_boundaries()
	_landmark_symbols.clear()
	for entity_id: String in _anchors:
		if entity_id in [controller.selected_polity_id, controller.hovered_polity_id]:
			draw_circle(_anchors[entity_id], 3.0, Color(0.82, 0.68, 0.40, 0.85))
	for place_id: String in _place_points:
		var selected := place_id == controller.selected_place_id
		var point := _place_points[place_id] as Vector2
		var place := _display_place(place_id)
		if str(place.get("kind",""))=="landmark":
			if not region_view.landmark_visible(place_id):
				_draw_landmark_symbol(place_id,place,point)
			if selected or place_id==controller.hovered_place_id: draw_arc(point,7.0,0,TAU,20,Color(0.84,0.77,0.55,0.8),1.0,true)
			continue
		if str(place.get("display_kind",""))=="transport_node":
			var ink := Color(0.77,0.71,0.55,0.95)
			draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),ink,false,1.0)
			draw_line(point+Vector2(-4,4),point+Vector2(4,4),ink,1.0,true)
			if selected or place_id==controller.hovered_place_id: draw_arc(point,7.0,0.0,TAU,16,ink,1.0,true)
			continue
		if str(place.get("display_kind","")) in ["settlement_miniature","historic_wharf"]:
			var ink := Color(0.76,0.72,0.59,0.92)
			if not region_view.settlement_visible(place_id):
				# Locality symbol, never a per-building ownership or parcel marker.
				for offset: Vector2 in [Vector2(-6,-2),Vector2(-1,-5),Vector2(4,-1)]:
					draw_rect(Rect2(point+offset,Vector2(3,5-offset.y)),ink,false,1.0)
				draw_line(point+Vector2(-8,5),point+Vector2(9,5),ink,1.0,true)
				if str(place.display_kind)=="historic_wharf": draw_line(point+Vector2(-7,8),point+Vector2(7,8),Color(0.39,0.59,0.61),1.0,true)
			if selected or place_id==controller.hovered_place_id: draw_arc(point,10.0,0.0,TAU,20,ink,1.0,true)
			continue
		var rank := int(place.get("rank", 1))
		var radius := float(MapScaleStyle.SETTLEMENT_RADII[clampi(rank,0,2)])
		var marker_color := Color(0.68,0.70,0.64,0.78)
		if selected:
			draw_arc(point,4.0,0.0,TAU,16,Color(0.84,0.80,0.67,0.92),1.0,true)
			draw_circle(point,1.2,marker_color)
		elif rank == 0:
			draw_rect(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2.0),marker_color)
		elif rank == 1:
			draw_arc(point,radius,0.0,TAU,12,marker_color,1.0,true)
		else:
			draw_circle(point,radius,Color(0.61,0.65,0.61,0.70))
		if regional:
			continue
		if strategic_layer.visible_places.has(place_id) or local_layer.visible_places.has(place_id): continue
		if controller.labels_enabled and (controller.zoom >= 4.8 or selected or place_id == controller.hovered_place_id):
			var name := str(place.get("name",place.get("display_name",place_id)))
			if not _city_fonts.has(name):
				if _city_fonts.size() >= 256: _city_fonts.clear()
				_city_fonts[name] = GlobeLabels.font_for_name(_font,name)
			var font := _city_fonts[name] as Font
			var label_rect := Rect2(point+Vector2(7,-19),font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,13))
			var hidden := false
			for occupied: Rect2 in _label_exclusions()+_world_labels.label_rects:
				if occupied.intersects(label_rect.grow(3.0)): hidden = true; break
			if not hidden: UIDrawing.label(self,font,point+Vector2(7,-6),name,13)
	var metric := controller.region_camera.km_per_pixel if regional else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, controller.orientation()), controller.orientation(), _radius)
	var space := "地点关系" if controller.region_camera.local_active and metric<0.05 else "近景" if controller.region_camera.local_active else "区域 · 近" if regional and metric<0.65 else "区域 · 中" if regional and metric<2.4 else "区域 · 远" if regional else "世界"
	var source := "历史政治 · 物理地理参考"
	if controller.administrative_map_active():
		source = "1900 历史 GIS 重建省界"
		if political.display_date < "1900-01-01" or political.display_date >= "1901-01-01": source = "1900 省界参考超出适用年份"
	if regional and local_content!=null and local_content.content!=null and (controller.region_camera.local_active or local_layer.has_visible_kind("water_surface")):
		var attribution := str(local_content.content.metadata.get("map_attribution_zh",""))
		if not attribution.is_empty(): source = attribution
	if show_footer: _update_footer(space+" · "+source+"   ","%.0f 米/像素" % (metric * 1000.0))

func _draw_landmark_symbol(id: String, visual: Dictionary, point: Vector2) -> void:
	var brass := Color(0.78,0.71,0.52,0.96)
	var shade := Color(0.37,0.36,0.29,0.98)
	var limit := float(visual.model_max_mpp)
	var close_weight := 1.0-smoothstep(limit,limit*4.0,_strategic_mpp())
	var scale := lerpf(1.0,float(visual.get("display_footprint_min_px",110.0))/45.0,close_weight) if str(visual.get("symbol_kind","eiffel"))=="pyramids" else lerpf(1.0,float(visual.display_height_min_px)/30.0,close_weight)
	if str(visual.get("symbol_kind","eiffel"))=="pyramids":
		for item: Vector3 in [Vector3(-11,-2,12),Vector3(2,1,14),Vector3(14,3,8)]:
			var foot := point+Vector2(item.x,item.y)*scale
			var top := foot+Vector2(-2,-item.z)*scale
			var left := foot+Vector2(-item.z*0.65,0)*scale
			var right := foot+Vector2(item.z*0.65,0)*scale
			draw_colored_polygon(PackedVector2Array([left,top,foot]),brass)
			draw_colored_polygon(PackedVector2Array([foot,top,right]),shade)
			draw_polyline(PackedVector2Array([left,top,right,left]),Color(0.87,0.79,0.61,0.9),0.8,true)
		_landmark_symbols[id] = Rect2(point+Vector2(-23,-17)*scale,Vector2(45,23)*scale)
	elif str(visual.get("symbol_kind",""))=="clock_tower":
		var body := PackedVector2Array([Vector2(-5,0),Vector2(-5,-22),Vector2(-7,-22),Vector2(-5,-26),Vector2(0,-35),Vector2(5,-26),Vector2(7,-22),Vector2(5,-22),Vector2(5,0)])
		for index: int in range(body.size()): body[index] = point+body[index]*scale
		draw_colored_polygon(body,brass)
		draw_circle(point+Vector2(0,-19)*scale,3.6*scale,Color(0.84,0.82,0.70))
		draw_line(point+Vector2(0,-19)*scale,point+Vector2(0,-21.5)*scale,shade,1.0,true)
		draw_line(point+Vector2(0,-19)*scale,point+Vector2(2,-18)*scale,shade,1.0,true)
		_landmark_symbols[id] = Rect2(point+Vector2(-9,-37)*scale,Vector2(18,40)*scale)
	else:
		# Open arch, tapering piers and two platforms: a tower, not a letter.
		for side: float in [-1.0,1.0]:
			var pier := PackedVector2Array([Vector2(side*10,0),Vector2(side*6,-11),Vector2(side*3,-19),Vector2(side*1,-30),Vector2(side*0.2,-30),Vector2(side*1,-17),Vector2(side*3,-10),Vector2(side*6,0)])
			for i: int in range(pier.size()): pier[i] = point+pier[i]*scale
			draw_colored_polygon(pier,brass)
		draw_line(point+Vector2(-7,-11)*scale,point+Vector2(7,-11)*scale,brass,2.4,true)
		draw_line(point+Vector2(-4,-19)*scale,point+Vector2(4,-19)*scale,brass,2.0,true)
		draw_arc(point+Vector2(0,1)*scale,6.0*scale,PI,TAU,12,shade,1.0,true)
		draw_line(point+Vector2(-11,1)*scale,point+Vector2(11,1)*scale,brass,1.1,true)
		_landmark_symbols[id] = Rect2(point+Vector2(-14,-33)*scale,Vector2(28,37)*scale)

func _update_footer(prefix: String, scale_text: String) -> void:
	# The long provenance label is static during pan/zoom. Keep its shaped
	# glyph commands separate from the short, exact meters-per-pixel number.
	if not _footer_prefix_item.is_valid():
		_footer_prefix_item = RenderingServer.canvas_item_create()
		_footer_scale_item = RenderingServer.canvas_item_create()
		for item: RID in [_footer_prefix_item,_footer_scale_item]:
			RenderingServer.canvas_item_set_parent(item,get_canvas_item())
			RenderingServer.canvas_item_set_draw_index(item,1000000)
	if _footer_prefix != prefix:
		_footer_prefix = prefix
		RenderingServer.canvas_item_clear(_footer_prefix_item)
		var footer_font := GlobeLabels.font_for_name(_font,prefix)
		footer_font.draw_string(_footer_prefix_item,Vector2.ZERO,prefix,HORIZONTAL_ALIGNMENT_LEFT,-1.0,10,Color(0.70,0.79,0.73,0.8))
		_footer_prefix_width = footer_font.get_string_size(prefix,HORIZONTAL_ALIGNMENT_LEFT,-1.0,10).x
	if _footer_scale != scale_text:
		_footer_scale = scale_text
		RenderingServer.canvas_item_clear(_footer_scale_item)
		GlobeLabels.font_for_name(_font,scale_text).draw_string(_footer_scale_item,Vector2.ZERO,scale_text,HORIZONTAL_ALIGNMENT_LEFT,-1.0,10,Color(0.76,0.77,0.66,0.8))
	RenderingServer.canvas_item_set_transform(_footer_prefix_item,Transform2D(0.0,Vector2(16.0,size.y-12.0)))
	RenderingServer.canvas_item_set_transform(_footer_scale_item,Transform2D(0.0,Vector2(16.0+_footer_prefix_width,size.y-12.0)))

func _gui_input(event: InputEvent) -> void:
	if controller == null:
		return
	if _transition_elapsed >= 0.0:
		accept_event()
		return
	if input_blocked.is_valid() and event is InputEventMouse:
		if bool(input_blocked.call(get_global_transform()*(event as InputEventMouse).position)):
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
	# A drag changes the camera, never the selected object. Picking every
	# intermediate pointer duplicates projection work along fragmented shores.
	if event is InputEventMouseMotion and (controller._dragging or controller._bearing_dragging):
		controller.hover("", "")
		accept_event()
		return
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
		var polity_id := ""
		if controller.administrative_map_active() and place_id.is_empty() and spatial_world != null and controller.region_camera.active:
			var picked := unit_at(point)
			if not picked.is_zero_approx():
				var displayed: Array[String] = []
				for row: Dictionary in _overlay_demand:
					if row.kind=="administration" and _overlay_batches.has(str(row.id)): displayed.append(str(row.id))
				place_id = spatial_world.pick_administration(RegionProjection.lon_lat(picked),political.display_date,displayed)
				if not place_id.is_empty() and place_id!=controller.selected_place_id and str(spatial_world.administrative_identity(place_id).get("polity_id",""))!=controller.player_polity_id: place_id = ""
		if place_id.is_empty():
			var geographic := _geographic_at(point)
			if not geographic.is_empty() and (_geographic_records[geographic] as Dictionary).has("political_source_id"): place_id = geographic
			else:
				polity_id = _polity_at(point)
				if polity_id.is_empty(): place_id = geographic
		if place_id.begins_with("administrative_region:") and spatial_world != null:
			polity_id = str(spatial_world.administrative_identity(place_id).get("polity_id",""))
		elif _geographic_records.has(place_id):
			var source_id := str((_geographic_records[place_id] as Dictionary).get("political_source_id",""))
			polity_id = _political_view.runtime_id_for_source(source_id)
			if polity_id.is_empty() and not source_id.is_empty():
				for owner: String in political.records:
					var record := political.records[owner] as Dictionary
					if str(record.get("source_historical_id",""))==source_id:
						polity_id = _picked_political_identity(owner)
						break
		elif not place_id.is_empty():
			var place := _display_place(place_id)
			polity_id = _political_view.runtime_id_for_source(str(place.get("parent_country_id", "")))
		controller.hover(polity_id, place_id)
		if clicked:
			# A real place remains selectable when its legacy country reference has
			# no current polity crosswalk. Do not infer that mapping from a polygon.
			if polity_id.is_empty() and place_id.is_empty() and _unassigned_pick:
				var coordinate := RegionProjection.lon_lat(unit_at(point))
				place_id = "geographic_reference:physical_pick"
				geographic_reference_selected.emit({"place_id":place_id,"name":"海岸／岛屿地理参考","spatial_kind":"geographic_region","lon_lat":[coordinate.x,coordinate.y],"valid_from":"0001-01-01","valid_to":"9999-12-31","source_name_zh":"Natural Earth 物理陆地参考","source_reference":"https://www.naturalearthdata.com/","note_zh":"当前位置命中已显示的物理陆地。现有历史政治几何未覆盖此处，政治归属未知；海岸与旗帜延展不构成主权依据。"})
			controller.select(polity_id, place_id)
	accept_event()

func _polity_at(point: Vector2) -> String:
	_unassigned_pick = false
	var owners := _surface_batches.keys()
	owners.reverse() # Exact overlap follows the actual political surface order.
	var camera := controller.region_camera
	var unit := unit_at(point)
	if unit.is_zero_approx(): return ""
	var chart_point := camera.project(unit) if camera.local_active else point
	var basis := controller.orientation()
	var inverse := basis.transposed()
	var normalized := (point-_center)/_radius
	var origin := inverse*Vector3(normalized.x,-normalized.y,1.2)
	var distances: Dictionary = {}
	for owner: String in owners:
		var geometry := (_surface_batches[owner] as Dictionary).geometry as GlobeSurfaceBatch
		var margin := 4.0*camera.km_per_pixel/RegionProjection.EARTH_RADIUS_KM if camera.active else 4.0/maxf(_radius,1.0)
		if geometry.cull_axis.angle_to(unit)>geometry.cull_angle+margin:
			distances[owner] = INF
			continue
		var distance := geometry.distance_region_point(unit,chart_point,camera) if camera.active else geometry.distance_screen_point(origin,inverse*Vector3.FORWARD,basis,point,_center,_radius)
		distances[owner] = distance
		if distance==0.0:
			_unassigned_pick = owner.is_empty()
			return _picked_political_identity(owner)
	# A physical texture continuation is never a sovereignty assignment.
	var physical := strategic_layer.physical_land_at(chart_point,camera,{"basis":basis,"center":_center,"radius":_radius})
	var best := 4.0
	var nearest := ""
	var found := false
	for owner: String in owners:
		var distance := float(distances[owner])
		if physical and distance>0.75: continue
		if distance>best or (found and distance==best): continue
		best = distance
		nearest = owner
		found = true
	if found:
		_unassigned_pick = nearest.is_empty()
		return _picked_political_identity(nearest)
	_unassigned_pick = physical
	return ""

func _picked_political_identity(owner: String) -> String:
	var runtime_id := str((political.records.get(owner,{}) as Dictionary).get("runtime_entity_id",""))
	# Supplementary historical ranges deliberately have no simulation entity.
	# Their visible surface still selects its own sourced presentation record.
	return runtime_id if not runtime_id.is_empty() and _political_view.has_entity(runtime_id) else owner

func _place_at(point: Vector2) -> String:
	if controller.region_camera.local_active:
		for id: String in region_view.landmark_screen_bounds:
			if (region_view.landmark_screen_bounds[id] as Rect2).has_point(point): return id
		var settlement := region_view.settlement_at(point)
		if not settlement.is_empty(): return settlement
	for id: String in _landmark_symbols:
		if (_landmark_symbols[id] as Rect2).has_point(point): return id
	for place_id: String in _place_points:
		if point.distance_to(_place_points[place_id] as Vector2) <= 8.0:
			return place_id
	return ""

func _display_place(id: String) -> Dictionary:
	var place := local_layer.place(id)
	if place.is_empty(): place = strategic_layer.place(id)
	return political.places.get(id,{}) as Dictionary if place.is_empty() else place

func _geographic_at(point: Vector2) -> String:
	var unit := unit_at(point)
	if unit.is_zero_approx(): return ""
	var coordinates := RegionProjection.lon_lat(unit)
	coordinates.x = wrapf(coordinates.x,-180.0,180.0)
	var exact := ""
	var priority := -1000
	var extent := INF
	for id: String in _geographic_cells:
		if not _geographic_active(id): continue
		var record := _geographic_records[id] as Dictionary
		var rank := int(record.get("pick_priority",20 if record.has("political_source_id") else -10))
		for cell: Dictionary in _geographic_cells[id] as Array[Dictionary]:
			if not political._contains_cell(coordinates,cell): continue
			var angle := float(cell.cull_angle)
			if rank>priority or (rank==priority and angle<extent):
				exact = id; priority = rank; extent = angle
	if not exact.is_empty(): return exact
	# The same known physical components support a small screen tolerance.
	# Exact geographic hits above always win; no nearest-country assignment.
	var best := 3.0
	var nearest := ""
	var camera := controller.region_camera
	var basis := controller.orientation()
	var angular_margin := best*camera.km_per_pixel/6371.0088 if camera.active else best/maxf(_radius,1.0)
	for id: String in _geographic_cells:
		if not _geographic_active(id) or not (_geographic_records[id] as Dictionary).has("political_source_id"): continue
		for cell: Dictionary in _geographic_cells[id] as Array[Dictionary]:
			if (cell.cull_axis as Vector3).angle_to(unit)>float(cell.cull_angle)+angular_margin: continue
			if camera.local_active: continue # Local ray hits are geographic; no flat-screen tolerance.
			var projected := PackedVector2Array()
			var bounds := Rect2()
			for ll: Vector2 in cell.outer as PackedVector2Array:
				var vertex := GlobeProjection.lon_lat_to_unit(ll)
				if not camera.active and (basis*vertex).z<0.0: projected.clear(); break
				var screen := camera.project(vertex) if camera.active else _center+Vector2((basis*vertex).x,-(basis*vertex).y)*_radius
				if projected.is_empty(): bounds = Rect2(screen,Vector2.ZERO)
				else: bounds = bounds.expand(screen)
				projected.append(screen)
			if projected.size()<3 or maxf(bounds.size.x,bounds.size.y)>18.0 or not bounds.grow(best).has_point(point): continue
			for index: int in range(projected.size()):
				var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,projected[index],projected[(index+1)%projected.size()]))
				if distance<best: best = distance; nearest = id
	if not nearest.is_empty(): return nearest
	return ""

func _geographic_active(id: String) -> bool:
	var annotation := _geographic_records[id] as Dictionary
	if political.display_date < str(annotation.get("valid_from","")) or political.display_date >= str(annotation.get("valid_to","9999-12-31")): return false
	var feature := str(annotation.get("geometry_feature_id", ""))
	return feature.is_empty() or not political._whole_owner_by_feature.has(feature)

func focus_place(place: Dictionary) -> bool:
	var raw: Variant = place.get("lon_lat",[])
	if not raw is Array or (raw as Array).size()!=2: return false
	var point := raw as Array
	_transition_elapsed = -1.0
	_container.modulate.a = 1.0
	region_view.container.modulate.a = 1.0
	controller.focus(GlobeProjection.lon_lat_to_unit(Vector2(float(point[0]),float(point[1]))))
	return true

func focus_selection() -> void:
	_transition_elapsed = -1.0
	_container.modulate.a = 1.0
	region_view.container.modulate.a = 1.0
	var place_id := controller.selected_place_id
	if not place_id.is_empty() and not _geographic_records.has(place_id):
		var place := local_layer.place(place_id)
		if place.is_empty(): place = strategic_layer.place(place_id)
		if place.is_empty(): place = political.places.get(place_id,{}) as Dictionary
		if place.has("geometry") and str((place.geometry as Dictionary).get("type",""))=="Point":
			place = {"lon_lat":(place.geometry as Dictionary).coordinates}
		if focus_place(place): return
	if _geographic_records.has(controller.selected_place_id):
		var coordinates := (_geographic_records[controller.selected_place_id] as Dictionary).lon_lat as Array
		controller.focus(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1]))))
		return
	controller.focus(political.anchors.get(controller.selected_polity_id, Vector3.ZERO) as Vector3)

func _on_mouse_exited() -> void:
	if controller != null:
		controller.suspend_motion()
		controller.hover("", "")
	_last_pointer = Vector2(-1.0, -1.0)

func unit_at(pixel: Vector2) -> Vector3:
	_ensure_view()
	if controller.region_camera.local_active:
		var terrain := region_view.surface_unit_at(pixel)
		if not terrain.is_zero_approx(): return terrain
	return controller.region_camera.unit_at(pixel) if controller.region_camera.active else RegionProjection.world_unit(pixel, _center, _radius, controller.orientation())

func screen_point(unit: Vector3) -> Vector2:
	_ensure_view()
	if controller.region_camera.local_active:
		var terrain := region_view.surface_screen_point(unit)
		if is_finite(terrain.x): return terrain
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
	var pixel := size*0.5 if controller.region_camera.active else _last_pointer
	var unit := unit_at(pixel) if Rect2(Vector2.ZERO, size).has_point(pixel) else Vector3.ZERO
	if unit.is_zero_approx():
		pixel = size * 0.5
		unit = unit_at(pixel)
	if controller.region_camera.active and unit.is_zero_approx():
		var anchor := controller.region_camera.valid_anchor(size)
		unit = anchor.unit
		pixel = anchor.pixel
	if unit.is_zero_approx():
		return
	var camera := controller.region_camera
	_sync_local_resources()
	if camera.active:
		var scale := camera.scale_at(unit)
		if local_content != null and scale <= LocalSpatialLoader.PREWARM_KM_PER_PIXEL and LocalSpatialLoader.covers(RegionProjection.lon_lat(unit)):
			local_content.request(RegionProjection.lon_lat(unit))
			if local_content.preparing() or local_layer.preparing:
				set_process(visible)
		if camera.local_active:
			if camera.km_per_pixel >= RegionCamera.LOCAL_EXIT_KM_PER_PIXEL:
				camera.leave_local()
				_invalidate_projection()
			return
		if scale <= RegionCamera.LOCAL_ENTER_KM_PER_PIXEL and region_view.ready and LocalSpatialLoader.covers(RegionProjection.lon_lat(unit)):
			if local_content == null or local_content.content == null or not local_content.content.covers(RegionProjection.lon_lat(unit)) or not local_content.content.display_active_on(political.display_date):
				return
			# A transport-only regional shard does not claim a LOCAL terrain.
			if not bool(local_content.content.metadata.get("local_enabled",true)): return
			var anchor := (local_content.content.metadata.get("anchor_lon_lat",[]) as Array)
			var anchor_unit := GlobeProjection.lon_lat_to_unit(Vector2(float(anchor[0]),float(anchor[1])))
			if camera.enter_local(anchor_unit,camera.project(anchor_unit),size,str(local_content.content.metadata.anchor_place_id),float(local_content.content.metadata.get("local_min_mpp",25.0))):
				_invalidate_projection()
			return
		if camera.km_per_pixel >= RegionCamera.EXIT_KM_PER_PIXEL:
			var frame := RegionProjection.frame(RegionProjection.lon_lat(unit))
			# Bearing at the exit anchor includes local meridian convergence.
			var north_step := camera.project((unit + frame.y * 0.0001).normalized()) - camera.project(unit)
			var angle := atan2(north_step.x, -north_step.y)
			var restored := RegionProjection.restore_world(unit, pixel, _center, scale, angle)
			controller._orientation = (restored.orientation as Basis).get_rotation_quaternion()
			controller.zoom = float(restored.radius) / minf(size.y / 2.55, size.x * 0.49)
			camera.active = false
			_begin_transition(false)
		return
	var scale := RegionProjection.world_scale(unit, controller.orientation(), _radius)
	# A finite geographic chart is valid over water as well as political land.
	# Missing local content does not prevent REGION observation or zooming.
	# Start while still in the World/Region handoff so a pause immediately
	# after entry does not require another wheel event to request the shard.
	if local_content != null and scale <= LocalSpatialLoader.PREWARM_KM_PER_PIXEL and LocalSpatialLoader.covers(RegionProjection.lon_lat(unit)):
		local_content.request(RegionProjection.lon_lat(unit))
		if local_content.preparing() or local_layer.preparing:
			set_process(visible)
	if scale <= RegionCamera.PREWARM_KM_PER_PIXEL and not region_view.ready and not region_view.preparing:
		region_view.begin(_surface_batches)
		set_process(visible)
	if scale <= RegionCamera.ENTER_KM_PER_PIXEL and region_view.ready:
		camera.enter(unit, pixel, scale, RegionProjection.world_bearing(unit, controller.orientation()), size)
		_region_labels_dirty = true
		_begin_transition(true)

func _sync_local_resources() -> void:
	if local_content == null or _transition_elapsed >= 0.0:
		return
	var camera := controller.region_camera
	var center_unit := camera.unit_at(size*0.5) if camera.active else unit_at(size*0.5)
	var request_unit := center_unit
	if camera.active and (center_unit.is_zero_approx() or not LocalSpatialLoader.covers(RegionProjection.lon_lat(center_unit))):
		for anchor: Vector2 in LocalSpatialLoader.anchors():
			var candidate := GlobeProjection.lon_lat_to_unit(anchor)
			if Rect2(Vector2.ZERO,size).has_point(camera.project(candidate)):
				request_unit = candidate
				break
	var supported := not request_unit.is_zero_approx() and LocalSpatialLoader.covers(RegionProjection.lon_lat(request_unit))
	if not visible or not supported or _strategic_mpp() > LocalSpatialLoader.PREWARM_KM_PER_PIXEL*1000.0:
		local_content.release()
		if local_layer.content_reference()!=null: local_layer.clear()
		if local_layer.preparing or local_content.preparing(): set_process(visible)
		return
	# First focus or pan into supported coverage needs no wheel event.
	local_content.request(RegionProjection.lon_lat(request_unit))
	if local_content.preparing(): set_process(visible)
	if local_content.content == null: return
	if local_content.content.errors.is_empty() and camera.local_active and camera.local_place_id!=str(local_content.content.metadata.anchor_place_id):
		# Both synchronous reuse and asynchronous completion retain the chart,
		# bearing and scale while admitting the new LOCAL anchor.
		camera.leave_local()
	if local_content.content!=local_layer.content_reference() and local_content.content.errors.is_empty():
		local_layer.begin(local_content.content,region_view.map_canvas,camera.km_per_pixel*1000.0)
	if camera.active and supported and local_content.content.covers(RegionProjection.lon_lat(request_unit)) and local_content.content.display_active_on(political.display_date):
		if local_content.content.active_on(political.display_date): local_layer.request_lods(camera.km_per_pixel*1000.0)
		else: local_layer.release_gpu()
		if local_layer.preparing: set_process(visible)
	else:
		local_layer.release_gpu()

func _sync_landmark_display() -> void:
	var visuals: Array[Dictionary] = []
	if visible and controller.region_camera.active and region_view.ready and local_content!=null and local_content.content!=null and local_content.content.errors.is_empty():
		for visual: Dictionary in local_content.content.landmark_visuals():
			if not LocalSpatialContent.landmark_visible_on(visual,political.display_date) or _strategic_mpp()>float(visual.symbol_max_mpp): continue
			var id := str(visual.id)
			var coordinates := (visual.geometry as Dictionary).coordinates as Array
			var point := controller.region_camera.project(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1]))))
			if not Rect2(Vector2.ZERO,size).grow(160.0).has_point(point): continue
			# Parent identity must already exist; a decoration never creates it.
			var geographic_anchor := str(visual.anchor_place_id)==str(visual.id) and local_content!=null and local_content.content!=null and str(local_content.content.metadata.anchor_place_id)==str(visual.id) and not _political_view.runtime_id_for_source(str(visual.get("parent_country_id",""))).is_empty()
			if not geographic_anchor and (spatial_world==null or spatial_world.get_place(str(visual.anchor_place_id)).is_empty()):
				_place_points.erase(id)
				continue
			_place_points[id] = point
			visuals.append(visual)
	var surface := local_content.content.surface_reference if visible and local_content!=null and local_content.content!=null and controller.region_camera.local_place_id==str(local_content.content.metadata.anchor_place_id) else {}
	var lines: Array[Dictionary] = []
	if not surface.is_empty() and local_content.content.active_on(political.display_date): lines.assign(local_content.content.features)
	var settlements: Array[Dictionary] = []
	if not surface.is_empty(): settlements = local_content.content.settlement_visuals(political.display_date)
	region_view.update_landmarks(visuals,controller.region_camera,size,surface,lines,settlements)
	if controller.region_camera.local_active:
		for id: String in _place_points:
			var place := _display_place(id)
			var raw := (place.get("geometry",{}) as Dictionary).get("coordinates",place.get("lon_lat",[])) as Array
			if raw.size()!=2 or typeof(raw[0]) not in [TYPE_INT,TYPE_FLOAT]: continue
			var point := region_view.surface_screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(raw[0]),float(raw[1]))))
			if is_finite(point.x): _place_points[id] = point
	if region_view.landmark_preparing(): set_process(visible)

func _sync_strategic_resources() -> void:
	if strategic_content == null or controller == null: return
	if not strategic_content.content_changed.is_connected(_on_strategic_content_changed):
		strategic_content.content_changed.connect(_on_strategic_content_changed)
	var camera := controller.region_camera
	var mpp := _strategic_mpp()
	var unit := (camera.valid_anchor(size).unit as Vector3) if camera.active else controller.orientation().transposed()*Vector3.BACK
	var center := RegionProjection.lon_lat(unit)
	_sync_overlay_resources()
	# The shared WORLD meshes remain owned by the WORLD batches. Only the
	# departing regional RIDs/material copies are retired beyond the prewarm band.
	if not camera.active and _transition_elapsed<0.0 and mpp>MapRelief.RELEASE_MPP and (region_view.ready or region_view.preparing):
		region_view.clear()
		_region_labels_dirty = true
	if not visible or mpp > RegionCamera.PREWARM_KM_PER_PIXEL*1000.0:
		strategic_layer.clear()
		strategic_content.release()
		return
	if not strategic_content.request(center,minf(9000,mpp*size.length()*0.0005),political.display_date,mpp):
		strategic_layer.clear()
		if strategic_content.preparing(): set_process(visible)
		return
	if strategic_content.content != null and not strategic_content.content.errors.is_empty():
		strategic_layer.clear()
		return
	if strategic_content.content != null and strategic_content.content != strategic_layer.content_reference() and strategic_content.content.errors.is_empty():
		strategic_layer.rail_style = 3
		var frames: Dictionary = {}
		var templates: Dictionary = {}
		var owners := political.get("_whole_owner_by_feature") as Dictionary
		var surfaces := region_view.surfaces if camera.active and region_view.ready else _surface_batches
		for feature: Dictionary in strategic_content.content.features:
			for reference: String in feature.get("visual_reference_features",[]) as Array:
				var owner := str(owners.get(reference,""))
				if not reference.is_empty() and _source_meshes.has(reference) and surfaces.has(owner):
					frames[reference] = (_source_meshes[reference] as Dictionary).uv_bounds
					templates[reference] = surfaces[owner]
		strategic_layer.begin(strategic_content.content,region_view.map_canvas,mpp,{"frames":frames,"templates":templates})
	if strategic_content.content != null and strategic_content.content.errors.is_empty(): strategic_layer.request_lods(mpp)
	if strategic_content.preparing() or strategic_layer.preparing: set_process(visible)

func _strategic_mpp() -> float:
	return controller.region_camera.km_per_pixel*1000.0 if controller.region_camera.active else RegionProjection.EARTH_RADIUS_KM/maxf(_radius,1.0)*1000.0

func _update_strategic_layer(commit_canvas: bool = true) -> void:
	strategic_layer.reference_relief = relief.textures
	strategic_layer.suppressed_places = local_layer.visible_places
	strategic_layer.paris_mask_weights = {}
	# Local river records are partial; they cannot erase every strategic river
	# within a 300 km circle. Both admitted batches remain geographically culled.
	if local_layer.has_visible_kind("coast"):
		strategic_layer.paris_mask_weights["coast"] = MapScaleStyle.physical_weight("coast",controller.region_camera.km_per_pixel*1000.0)
	var surfaces := region_view.surfaces if controller.region_camera.active and region_view.ready else _surface_batches
	strategic_layer.update(controller.region_camera,controller,political.display_date,size,commit_canvas,{"mpp":_strategic_mpp(),"center":_center,"radius":_radius,"canvas":_viewport.world_2d.canvas,"surfaces":surfaces,"owners":political.get("_whole_owner_by_feature"),"scoped_features":political.get("_scope_features")})

func _label_exclusions() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if label_exclusions.is_valid(): result.assign(label_exclusions.call())
	return result

func _overlay_local_view() -> Rect2:
	var bounds := Rect2()
	var first := true
	var topology := spatial_world.land_topology()
	for ratio: Vector2 in [Vector2.ZERO,Vector2(0.5,0),Vector2(1,0),Vector2(0,0.5),Vector2(0.5,0.5),Vector2(1,0.5),Vector2(0,1),Vector2(0.5,1),Vector2.ONE]:
		var unit := controller.region_camera.unit_at(size*ratio)
		if unit.is_zero_approx(): continue
		var point := topology.from_geographic(RegionProjection.lon_lat(unit))
		if first: bounds = Rect2(point,Vector2.ZERO); first = false
		else: bounds = bounds.expand(point)
	return bounds

func _sync_overlay_resources() -> void:
	if spatial_world==null or spatial_world.land_topology()==null: return
	if not spatial_world.administrative_display_changed.is_connected(_on_spatial_display_changed): spatial_world.administrative_display_changed.connect(_on_spatial_display_changed)
	var camera := controller.region_camera
	var show := visible and camera.active
	var mpp := _strategic_mpp()
	var topology := spatial_world.land_topology()
	var revision := topology.display_revision()
	var signature: Array = [spatial_world,revision,spatial_world.administrative_display_revision(),_boundary_source_revision,controller.player_polity_id,show,camera.active,camera.tangent_frame,camera.origin,camera.km_per_pixel,size,controller.administrative_map_active(),controller.selected_place_id,political.display_date.substr(0,4)]
	if signature==_overlay_request: return
	_overlay_request = signature
	var view := _overlay_local_view() if show else Rect2()
	var same_window := camera.active and _overlay_view.encloses(view) and revision==_overlay_revision and _overlay_owner==spatial_world
	var preparation_view := _overlay_view if same_window else view.grow(maxf(mpp*60.0,maxf(view.size.x,view.size.y)*0.15)) if view.has_area() else Rect2()
	var demand: Array[Dictionary] = []
	var selected := controller.selected_place_id
	for row: Dictionary in spatial_world.request_administrative_boundaries(preparation_view,political.display_date,mpp,show and controller.administrative_map_active(),selected,controller.player_polity_id):
		row["kind"] = "administration"
		row["variant"] = "outline" if str(row.id)==selected else "interior"
		demand.append(row)
	if show and mpp<=2200.0:
		var anchor := camera.valid_anchor(size).unit as Vector3
		var angle := size.length()*camera.km_per_pixel*0.65/6371.0088+0.02
		for index: int in range(_source_boundaries.size()):
			var border := _source_boundaries[index]
			if str(border.kind)!="macro" or (border.cull_axis as Vector3).angle_to(anchor)>float(border.cull_angle)+angle: continue
			var id := "display_border:"+str(index)
			var old_lod := str((_overlay_batches.get(id,[{"lod":""}]) as Array)[0].lod)
			var detail := mpp<450.0 or (old_lod.begins_with("country_detail") and mpp<650.0)
			demand.append({"id":id,"kind":"country","lod":("country_detail:" if detail else "country_coarse:")+str(_boundary_source_revision),"points":border.points,"detail_path":border.get("detail_path","") if detail else "","owners":border.owners,"anchor":anchor,"angle":angle,"step":0.025 if detail else 0.12})
	var query_id := selected if show and spatial_world.administrative_identity(selected).has("reference_descriptor") and not spatial_world.administrative_coverage_ready(selected) else ""
	# Keep one padded display window, including hidden layer batches, for toggles.
	var reuse_window := same_window
	_overlay_owner = spatial_world
	if demand==_overlay_demand and query_id==_overlay_query_id and reuse_window:
		_update_overlay_batches(view)
		return
	_overlay_mutex.lock()
	_overlay_generation += 1
	_overlay_mutex.unlock()
	_overlay_demand = demand
	_overlay_query_id = query_id
	if not reuse_window: _overlay_view = preparation_view
	_overlay_revision = revision
	_clear_overlay_installing()
	# Evict geometry only on a changed geographic window or topology; switching
	# a layer off leaves the bounded current window available for reuse.
	if not reuse_window:
		_clear_overlay_batches()
		spatial_world.retain_administrative_boundaries([])
	_retire_overlay_demand()
	_update_overlay_batches(view)
	_start_overlay_prepare()

func _overlay_current(generation: int) -> bool:
	_overlay_mutex.lock()
	var current := generation==_overlay_generation
	_overlay_mutex.unlock()
	return current

func _start_overlay_prepare() -> void:
	if _overlay_thread!=null: set_process(visible); return
	var missing: Array[Dictionary] = []
	for row: Dictionary in _overlay_demand:
		if not _overlay_batches.has(str(row.id)) or str(_overlay_batches[row.id][0].lod)!=str(row.lod) or str(_overlay_batches[row.id][0].get("variant",""))!=str(row.get("variant","")): missing.append(row)
	var query: Dictionary = {}
	if not _overlay_query_id.is_empty() and not spatial_world.administrative_coverage_ready(_overlay_query_id):
		query = {"id":_overlay_query_id,"descriptor":spatial_world.administrative_identity(_overlay_query_id).reference_descriptor,"polygons":{}}
		var topology := spatial_world.land_topology()
		for id: String in topology.land_ids_in_bounds(spatial_world.administrative_reference_bounds(_overlay_query_id)):
			query.polygons[id] = topology.polygon(id)
	if missing.is_empty() and query.is_empty(): return
	_overlay_thread = Thread.new()
	_overlay_thread.start(_prepare_overlay.bind(missing,query,spatial_world.land_topology(),_overlay_view,_overlay_revision,_overlay_generation))
	set_process(visible)

func _prepare_overlay(rows: Array[Dictionary], query: Dictionary, topology: LandTopology, view: Rect2, revision: int, generation: int) -> Dictionary:
	var uploads: Array[Dictionary] = []
	var query_components: Array = []
	for row: Dictionary in rows:
		if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
		var components: Array = []
		var paths: Array[Dictionary] = []
		if row.kind=="country":
			paths = _country_overlay_paths(row,generation)
		elif str(row.get("basis",""))=="current_members":
			paths = _member_overlay_paths(row,topology,view,generation)
		else:
			var document := AdministrativeLoader.department_geometry(row.descriptor,str(row.lod))
			for part: Array in document.get("display_pick_polygons",document.get("local_polygons",[])) as Array:
				var rings: Array[PackedVector2Array] = []
				for raw: Variant in part: rings.append(topology._polygon_from_value(raw))
				components.append(rings)
			if str(row.id)==str(query.get("id","")) and row.lod=="detail":
				for part: Array in document.get("local_polygons",[]) as Array:
					var rings: Array[PackedVector2Array] = []
					for raw: Variant in part: rings.append(topology._polygon_from_value(raw))
					query_components.append(rings)
			var display_rings: Array[Dictionary] = []
			if document.has("display_lines"):
				var field := "display_outline_lines" if row.get("variant","")=="outline" else "display_lines"
				for raw: Array in document.get(field,[]) as Array: display_rings.append({"points":topology._polygon_from_value(raw),"closed":false})
			else:
				for part: Array in components:
					for ring: PackedVector2Array in part: display_rings.append({"points":ring,"closed":true})
			for display_ring: Dictionary in display_rings:
				var ring := display_ring.points as PackedVector2Array
				if ring.size()<2: continue
				var edges := ring.size() if bool(display_ring.closed) else ring.size()-1
				var points := PackedVector3Array()
				for index: int in range(edges):
					var a := ring[index]
					var b := ring[(index+1)%ring.size()]
					if view.intersects(Rect2(a,Vector2.ZERO).expand(b),true):
						if points.is_empty(): points.append(GlobeProjection.lon_lat_to_unit(topology.to_geographic(a)))
						points.append(GlobeProjection.lon_lat_to_unit(topology.to_geographic(b)))
					elif points.size()>1:
						paths.append({"points":points}); points = PackedVector3Array()
					if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
				if points.size()>1: paths.append({"points":points})
		var lines: Array[Dictionary] = []
		var segments := 0
		var chunks: Array[Dictionary] = []
		for path: Dictionary in paths:
			var points := path.points as PackedVector3Array
			var loop := points.size()>2 and points[0].is_equal_approx(points[-1])
			var start := 0
			while start<points.size()-1:
				var end := mini(start+256,points.size()-1)
				var line := {"kind":"overlay","points":points.slice(start,end+1)}
				if start>0: line["before"] = points[start-1]
				elif loop: line["before"] = points[-2]
				elif path.has("before"): line["before"] = path.before
				if end<points.size()-1: line["after"] = points[end+1]
				elif loop: line["after"] = points[1]
				elif path.has("after"): line["after"] = path.after
				lines.append(line)
				segments += end-start
				start = end
				if segments>=2048:
					chunks.append(GlobeBoundaryBatch.encode(lines,"overlay",true))
					lines = []; segments = 0
				if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
		if not lines.is_empty(): chunks.append(GlobeBoundaryBatch.encode(lines,"overlay",true))
		if chunks.is_empty(): chunks.append({})
		for index: int in range(chunks.size()):
			uploads.append({"id":row.id,"kind":row.kind,"level":row.get("level",1),"lod":row.lod,"variant":row.get("variant",""),"encoded":chunks[index],"last":index==chunks.size()-1,"basis":row.get("basis",""),"owners":row.get("owners",[]),"components":components if index==chunks.size()-1 and row.kind=="administration" else []})
	var overlaps: Dictionary = {}
	if not query.is_empty() and _overlay_current(generation):
		if query_components.is_empty():
			for part: Array in AdministrativeLoader.department_geometry(query.descriptor,"detail").get("local_polygons",[]) as Array:
				var rings: Array[PackedVector2Array] = []
				for raw: Variant in part: rings.append(topology._polygon_from_value(raw))
				query_components.append(rings)
		for id: String in query.polygons:
			if not _overlay_current(generation): return {"generation":generation,"uploads":[]}
			var points := query.polygons[id] as PackedVector2Array
			var overlap := 0.0
			var bounds := LandTopology._polygon_bounds(points)
			for part: Array in query_components:
				if not bounds.intersects(LandTopology._polygon_bounds(part[0]),true): continue
				overlap += topology._intersection_area(points,part[0])
				for index: int in range(1,part.size()): overlap -= topology._intersection_area(points,part[index])
			if overlap>0.0: overlaps[id] = overlap
	return {"generation":generation,"uploads":uploads,"query":str(query.get("id","")),"overlaps":overlaps,"revision":revision}

func _country_overlay_paths(row: Dictionary, generation: int) -> Array[Dictionary]:
	# Sample the original lon/lat segment for projection, without smoothing or moving it.
	var result: Array[Dictionary] = []
	var original := row.points as PackedVector3Array
	var path := str(row.get("detail_path",""))
	if not path.is_empty():
		var errors: Array[String] = []
		var document := ContentDocument.read(path,errors)
		if errors.is_empty() and document.get("schema_id")=="historical_political_display_line_v1" and document.get("points") is Array:
			var coordinates := PackedVector2Array()
			for raw: Array in document.points as Array: coordinates.append(Vector2(float(raw[0]),float(raw[1])))
			if coordinates.size()>1: original = GlobeProjection.to_unit_line(coordinates)
	var points := PackedVector3Array()
	for index: int in range(original.size()-1):
		if not _overlay_current(generation): return []
		var a := original[index]
		var b := original[index+1]
		var angle := a.angle_to(b)
		if (a+b).normalized().angle_to(row.anchor)>float(row.angle)+angle*0.5:
			if points.size()>1: result.append({"points":points})
			points = PackedVector3Array()
			continue
		var start := RegionProjection.lon_lat(a)
		var finish := RegionProjection.lon_lat(b)
		finish.x = start.x+wrapf(finish.x-start.x,-180.0,180.0)
		var steps := maxi(1,ceili(maxf(absf(finish.x-start.x),absf(finish.y-start.y))/float(row.step)))
		if points.is_empty(): points.append(a)
		for step: int in range(1,steps): points.append(GlobeProjection.lon_lat_to_unit(start.lerp(finish,float(step)/steps)))
		points.append(b)
	if points.size()>1: result.append({"points":points})
	return result

func _member_overlay_paths(row: Dictionary, topology: LandTopology, view: Rect2, generation: int) -> Array[Dictionary]:
	# Remove only shared edges of actual members. Unknown land remains outside the outline.
	var result: Array[Dictionary] = []
	for id: String in row.polygons:
		var ring := row.polygons[id] as PackedVector2Array
		for index: int in range(ring.size()):
			if not _overlay_current(generation): return []
			var a := ring[index]
			var b := ring[(index+1)%ring.size()]
			if not view.intersects(Rect2(a,Vector2.ZERO).expand(b),true): continue
			var direction := b-a
			var length_squared := direction.length_squared()
			if length_squared<=0.0: continue
			var covered: Array[Vector2] = []
			var cuts: Array[float] = [0.0,1.0]
			for neighbor: PackedVector2Array in row.neighbors.get(id,[]):
				for edge: int in range(neighbor.size()):
					var c := neighbor[edge]
					var d := neighbor[(edge+1)%neighbor.size()]
					if absf(direction.cross(c-a))/sqrt(length_squared)>0.01 or absf(direction.cross(d-a))/sqrt(length_squared)>0.01: continue
					var low := clampf(minf((c-a).dot(direction),(d-a).dot(direction))/length_squared,0.0,1.0)
					var high := clampf(maxf((c-a).dot(direction),(d-a).dot(direction))/length_squared,0.0,1.0)
					if high<=low: continue
					covered.append(Vector2(low,high)); cuts.append(low); cuts.append(high)
			cuts.sort()
			for interval: int in range(cuts.size()-1):
				if cuts[interval+1]<=cuts[interval]: continue
				var midpoint := (cuts[interval]+cuts[interval+1])*0.5
				var shared := false
				for span: Vector2 in covered:
					if midpoint>=span.x and midpoint<=span.y: shared = true; break
				if shared: continue
				result.append({"points":PackedVector3Array([GlobeProjection.lon_lat_to_unit(topology.to_geographic(a.lerp(b,cuts[interval]))),GlobeProjection.lon_lat_to_unit(topology.to_geographic(a.lerp(b,cuts[interval+1])))])})
	return result

func _poll_overlay_prepare() -> void:
	if _overlay_thread!=null and not _overlay_thread.is_alive():
		var result := _overlay_thread.wait_to_finish() as Dictionary
		_overlay_thread = null
		if int(result.generation)==_overlay_generation:
			_overlay_uploads.assign(result.uploads)
			if not str(result.get("query","")).is_empty():
				spatial_world.install_administrative_coverage(str(result.query),result.overlaps,int(result.revision))
				_overlay_query_id = ""
				place_content_ready.emit()
		else: _start_overlay_prepare()
	if _overlay_uploads.is_empty(): return
	var row := _overlay_uploads.pop_front() as Dictionary
	var geometry := GlobeBoundaryBatch.new()
	geometry.upload(row.encoded)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/presentation/map/globe_boundary.gdshader")
	material.set_shader_parameter("line_data",geometry.data)
	material.set_shader_parameter("miter_limit",1.5)
	material.set_shader_parameter("stroke_feather",0.55)
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item,region_view.map_canvas)
	RenderingServer.canvas_item_set_draw_index(item,LocalSpatialLayer.DRAW_ORDER+3)
	RenderingServer.canvas_item_set_material(item,material.get_rid())
	RenderingServer.canvas_item_set_visible(item,false)
	if geometry.segment_count>0: RenderingServer.canvas_item_add_mesh(item,geometry.mesh.get_rid())
	var id := str(row.id)
	if not _overlay_installing.has(id): _overlay_installing[id] = []
	_overlay_installing[id].append({"id":id,"kind":row.kind,"level":row.get("level",1),"lod":row.lod,"variant":row.get("variant",""),"geometry":geometry,"material":material,"item":item,"owners":row.get("owners",[])})
	if bool(row.last):
		if _overlay_batches.has(id):
			for previous: Dictionary in _overlay_batches[id]: RenderingServer.free_rid(previous.item)
		_overlay_batches[id] = _overlay_installing[id]
		_overlay_installing.erase(id)
		if row.kind=="administration" and row.get("basis","")!="current_members": spatial_world.install_administrative_boundary(id,row.components,str(row.lod))
		_update_overlay_batches(_overlay_local_view())
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		queue_redraw()

func _clear_overlay_batches() -> void:
	for group: Array in _overlay_batches.values():
		for batch: Dictionary in group: RenderingServer.free_rid(batch.item)
	_overlay_batches.clear()

func _clear_overlay_installing() -> void:
	_overlay_uploads.clear()
	for group: Array in _overlay_installing.values():
		for batch: Dictionary in group: RenderingServer.free_rid(batch.item)
	_overlay_installing.clear()

func _retire_overlay_demand() -> void:
	var keep: Array[String] = []
	for row: Dictionary in _overlay_demand: keep.append(str(row.id))
	for id: String in _overlay_batches.keys():
		if id in keep: continue
		for batch: Dictionary in _overlay_batches[id]: RenderingServer.free_rid(batch.item)
		_overlay_batches.erase(id)
	# This evicts display/picking components only, never administrative identity
	# or actual land membership. A replacement LOD keeps its previous components
	# until install_administrative_boundary swaps the same object's reference.
	if not _overlay_query_id.is_empty(): keep.append(_overlay_query_id)
	spatial_world.retain_administrative_boundaries(keep)

func _update_overlay_batches(view: Rect2) -> void:
	var wanted: Dictionary = {}
	for row: Dictionary in _overlay_demand: wanted[str(row.id)] = row
	var colors := InterfaceSettings.theme_parameters()
	var country_ready := _country_overlay_ready()
	for id: String in _overlay_batches:
		for batch: Dictionary in _overlay_batches[id]:
			var show: bool = visible and controller.region_camera.active and wanted.has(id) and (str(batch.kind)!="country" or country_ready)
			if show and batch.kind=="administration":
				show = (wanted[id].bounds as Rect2).intersects(view.grow(_strategic_mpp()*8.0),true)
			if show!=bool(batch.get("visible",false)):
				RenderingServer.canvas_item_set_visible(batch.item,show)
				batch["visible"] = show
			if not show: continue
			_parameter(batch,"region_mode",true)
			_set_region_uniforms(batch)
			_bounds(batch,size)
			var selected: bool = str(batch.kind)!="country" and id==controller.selected_place_id
			var hovered: bool = str(batch.kind)!="country" and id==controller.hovered_place_id
			var home_border: bool = controller.administrative_map_active() and batch.kind=="country" and controller.player_polity_id in batch.get("owners",[])
			var color := (HOME_BORDER_COLOR if home_border else POLITICAL_UNDER_COLOR) if batch.kind=="country" else colors.admin_line as Color
			var level := int(batch.get("level",1))
			if batch.kind=="administration" and level>1:
				color = color.lerp(Color(0.55,0.57,0.53,color.a),0.18*minf(float(level-1),3.0))
				color.a *= maxf(0.45,1.0-0.18*float(level-1))
			if selected: color = Color(0.67,0.75,0.76,0.82)
			elif hovered: color.a = 0.60
			if batch.kind=="country" and controller.region_camera.local_active: color.a *= 0.72
			_parameter(batch,"stroke_color",color)
			var width := 1.35 if home_border else 1.05 if batch.kind=="country" else 1.35 if selected else 1.1 if hovered else maxf(0.50,0.85-0.10*float(level))
			if batch.kind=="country" and controller.region_camera.local_active: width *= 0.72
			_parameter(batch,"stroke_width",width)

func _country_overlay_ready() -> bool:
	var present := false
	for row: Dictionary in _overlay_demand:
		if row.kind!="country": continue
		present = true
		if not _overlay_batches.has(str(row.id)) or str(_overlay_batches[row.id][0].lod)!=str(row.lod): return false
	return present

func _draw_administrative_boundaries() -> void:
	if not controller.administrative_map_active() or spatial_world==null or not controller.region_camera.active: return
	_update_overlay_batches(_overlay_local_view())
	if not controller.labels_enabled: return
	var occupied := _label_exclusions()
	occupied.append_array(region_view.country_label_rects)
	occupied.append_array(local_layer.label_rects)
	occupied.append_array(strategic_layer.label_rects)
	for row: Dictionary in _overlay_demand:
		if row.kind!="administration": continue
		var id := str(row.id)
		if _strategic_mpp()<180.0 and id!=controller.selected_place_id: continue
		var text := str(spatial_world.administrative_identity(id).get("historical_name",""))
		var font := GlobeLabels.font_for_name(_font,text)
		var unit := GlobeProjection.lon_lat_to_unit(spatial_world.land_topology().to_geographic((row.bounds as Rect2).get_center()))
		var center := screen_point(unit)
		var text_size := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11)
		if id!=controller.selected_place_id and (minf((row.bounds as Rect2).size.x,(row.bounds as Rect2).size.y)/_strategic_mpp()<maxf(38.0,text_size.x*0.8) or occupied.size()>28): continue
		var rect := Rect2(center-text_size*0.5,text_size)
		var blocked := not Rect2(Vector2.ZERO,size).encloses(rect)
		for previous: Rect2 in occupied:
			if previous.intersects(rect.grow(3.0)): blocked = true; break
		if not blocked:
			occupied.append(rect)
			draw_string(font,rect.position+Vector2(0,11),text,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.67,0.72,0.74,0.85))

func focus_administration(id: String) -> bool:
	if spatial_world == null or spatial_world.administrative_identity(id).is_empty(): return false
	var bounds := spatial_world.administrative_display_bounds(id,political.display_date)
	if not bounds.has_area(): return false
	var unit := GlobeProjection.lon_lat_to_unit(spatial_world.land_topology().to_geographic(bounds.get_center()))
	controller.focus(unit)
	controller.set_map_mode("political")
	_transition_elapsed = -1.0
	_container.modulate.a = 1.0
	region_view.container.modulate.a = 1.0
	var scale := clampf(maxf(bounds.size.x/maxf(200.0,size.x-380.0),bounds.size.y/maxf(200.0,size.y-150.0))*0.001*1.6,RegionCamera.LOCAL_MIN_KM_PER_PIXEL,RegionCamera.ENTER_KM_PER_PIXEL)
	controller.region_camera.enter(unit,Vector2(size.x*0.5+minf(160.0,size.x*0.16),size.y*0.5),scale,0.0,size)
	controller.select(str(spatial_world.administrative_identity(id).get("polity_id","")),id)
	controller.view_changed.emit()
	return true

func _begin_transition(to_region: bool) -> void:
	controller.suspend_motion()
	# Hold the last complete departing texture while existing batches change canvas.
	_draw_surfaces(not to_region)
	_draw_boundaries(not to_region)
	if to_region:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_transition_to_region = to_region
	_transition_elapsed = 0.0
	_container.visible = true
	region_view.container.visible = true
	_container.modulate.a = 1.0
	region_view.container.modulate.a = 0.0 if to_region else 1.0
	_transition_started = Time.get_ticks_usec()
	_invalidate_projection()
	set_process(visible)

func _process(_delta: float) -> void:
	if not visible:
		# Join cancelled workers and discard their results even while hidden.
		# This processing stops as soon as the existing requests have drained.
		_poll_overlay_prepare()
		if strategic_content!=null: strategic_content.poll()
		if local_content!=null: local_content.poll()
		local_layer.prepare_step(_font)
		strategic_layer.prepare_step(_font)
		region_view.prepare_landmarks()
		relief.poll()
		set_process(_has_pending_preparation())
		return
	_poll_overlay_prepare()
	if relief.poll():
		_bind_relief()
		queue_redraw()
	_sync_relief()
	_sync_strategic_resources()
	if region_view.preparing:
		region_view.prepare_step(_surface_batches, _boundary_batches)
		if region_view.ready:
			_invalidate_projection()
			_evaluate_scale()
			if controller.region_camera.active:
				queue_redraw()
	if strategic_content != null: strategic_content.poll()
	if strategic_layer.preparing and strategic_layer.prepare_step(_font):
		_invalidate_projection()
	if local_content != null and local_content.poll():
		if local_content.content.errors.is_empty():
			local_layer.begin(local_content.content, region_view.map_canvas)
			_sync_local_resources()
		place_content_ready.emit()
	if local_layer.preparing:
		local_layer.prepare_step(_font)
		queue_redraw()
		if local_layer.ready:
			_evaluate_scale()
			_invalidate_projection()
	if region_view.prepare_landmarks(): queue_redraw()
	if _transition_elapsed >= 0.0:
		_transition_elapsed = float(Time.get_ticks_usec() - _transition_started) / 1000000.0
		var weight := clampf(_transition_elapsed / TRANSITION_SECONDS, 0.0, 1.0)
		region_view.container.modulate.a = weight if _transition_to_region else 1.0 - weight
		# REGION is the upper cached canvas. Keep WORLD opaque underneath;
		# fading both layers would expose the background and darken the midpoint.
		_container.modulate.a = 1.0
		if weight >= 1.0:
			_transition_elapsed = -1.0
			_on_visibility_changed()
			_evaluate_scale()
			queue_redraw()
	if _transition_elapsed < 0.0:
		_sync_local_resources()
	if not _has_pending_preparation() and _transition_elapsed < 0.0:
		set_process(false)

func _has_pending_preparation() -> bool:
	return _overlay_thread!=null or not _overlay_uploads.is_empty() or relief.preparing() or region_view.preparing or region_view.landmark_preparing() or strategic_layer.preparing or local_layer.preparing or (strategic_content!=null and strategic_content.preparing()) or (local_content!=null and local_content.preparing())

func _on_strategic_content_changed() -> void:
	_sync_strategic_resources()
	_invalidate_projection()
	place_content_ready.emit()

func _on_spatial_display_changed() -> void:
	_invalidate_projection()
	if controller.region_camera.active and region_view.ready:
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else: _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	place_content_ready.emit()

func _on_visibility_changed() -> void:
	if controller == null:
		return
	_sync_relief()
	_sync_strategic_resources()
	if not visible:
		region_view.clear()
		local_layer.clear()
		if local_content != null: local_content.release()
		_transition_elapsed = -1.0
		set_process(_has_pending_preparation())
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_container.visible = not (controller.region_camera.active and region_view.ready)
		region_view.container.visible = controller.region_camera.active and region_view.ready
		_container.modulate.a = 1.0
		region_view.container.modulate.a = 1.0
		_view_dirty = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if region_view.ready: region_view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(_has_pending_preparation())
		queue_redraw()

func _prepare_region_labels() -> void:
	_region_anchor_km.clear()
	_region_place_km.clear()
	var frame := controller.region_camera.tangent_frame
	_region_label_frame = frame
	var labels: Array[Dictionary] = []
	for entity_id: String in political.records:
		_region_anchor_km[entity_id] = RegionProjection.forward(political.anchors.get(entity_id, Vector3.ZERO) as Vector3, frame)
		if not controller.labels_enabled: continue
		var record := political.records[entity_id] as Dictionary
		var layout := _country_label_layouts.get(str(record.get("geometry_feature_id", "")), {}) as Dictionary
		var candidates: Array[Dictionary] = []
		if not bool(record.get("display_only", false)):
			for position: Dictionary in layout.get("positions", []) as Array:
				var coordinates := position.lon_lat as Array
				candidates.append({"km":RegionProjection.forward(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1]))),frame),"clearance_km":position.clearance_km})
		if candidates.is_empty(): candidates.append({"km":_region_anchor_km[entity_id],"clearance_km":100.0})
		labels.append({"id": entity_id, "km": candidates[0].km, "candidates":candidates,"candidate_index":0,"text": str(layout.get("name",record.get("short_name_zh", record.get("name_zh", entity_id)))), "rank": int(record.get("label_rank", 9)) + 10, "font_size": 24, "place": false})
	for id: String in _geographic_records:
		if not controller.labels_enabled or not _geographic_active(id): continue
		var annotation := _geographic_records[id] as Dictionary
		var coordinates := annotation.lon_lat as Array
		labels.append({"id":id,"km":RegionProjection.forward(GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1]))),frame),"text":str(annotation.name),"rank":int(annotation.get("label_rank",9))+10,"font_size":20,"place":false,"geography":true})
	for place_id: String in political.places:
		var raw_point: Variant = (political.places[place_id] as Dictionary).get("lon_lat", [])
		if raw_point is Array and (raw_point as Array).size() >= 2:
			_region_place_km[place_id] = RegionProjection.forward(GlobeProjection.lon_lat_to_unit(Vector2(float(raw_point[0]), float(raw_point[1]))), frame)
			if not controller.labels_enabled: continue
			# Formal Region cities come from admitted spatial content. Keeping
			# prototype cities in the label source can resurrect them on redraw.
			if strategic_content == null:
				labels.append({"id": place_id, "km": _region_place_km[place_id], "text": str((political.places[place_id] as Dictionary).get("name", place_id)), "rank": 0, "font_size": 13, "place": true})
	region_view.prepare_labels(labels, _font, _country_font)
	_region_labels_dirty = false

func _region_label_point(km: Vector2) -> Vector2:
	var camera := controller.region_camera
	return camera.origin + RegionProjection.screen_axes(camera.bearing) * (km / camera.km_per_pixel)
