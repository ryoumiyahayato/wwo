class_name GlobeRenderer
extends Control
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
const CityOverview = preload("res://scripts/presentation/map/city_miniature.gd")
var _city_sample_grade: int = 0
var _city_entering: bool = false
var observation_profile: bool = false
var observation_costs: Dictionary = {}
var observation_return: Dictionary = {}
var observation_camera_rejection: Dictionary = {}


func _city_source_profile() -> Dictionary:
	if controller!=null and controller.region_camera.active:
		var camera := controller.region_camera
		if camera.local_active:
			var current := CityOverview.for_place(camera.local_place_id)
			if not current.is_empty(): return current
		var unit := camera.unit_at(size*.5)
		if not unit.is_zero_approx():
			var at := CityOverview.at_position(RegionProjection.lon_lat(unit))
			if not at.is_empty(): return at
	return CityOverview.for_content(local_content.content) if local_content!=null else {}

func _selected_city_profile() -> Dictionary:
	if controller==null: return {}
	if _city_display_active(): return _city_source_profile()
	if not controller.selected_place_id.is_empty(): return CityOverview.for_place(controller.selected_place_id)
	var unit := controller.region_camera.unit_at(size*.5) if controller.region_camera.active else Vector3.ZERO
	if unit.is_zero_approx(): return {}
	var source := LocalSpatialLoader.source_at(RegionProjection.lon_lat(unit))
	return CityOverview.for_place(str(source.get("anchor_id", "")))

func _city_display_active() -> bool:
	return controller!=null and controller.region_camera.local_active and _strategic_mpp()<100.0 and not _city_source_profile().is_empty()

func _city_plane_active() -> bool:
	return _city_display_active() and _city_source_profile().has("presentation_index")

func _city_safe_rect() -> Rect2:
	var result := Rect2(Vector2(18,130),Vector2(maxf(200,size.x-36),maxf(200,size.y-178)))
	for rect: Rect2 in _label_exclusions():
		if rect.position.x>size.x*.5 and rect.size.y>180: result.size.x=minf(result.end.x,rect.position.x-20)-result.position.x
	return result

func _focus_city_overview() -> void:
	if _city_entering: return
	var target := _selected_city_profile()
	if target.is_empty():
		map_notice.emit("当前选择没有城市整体资料。")
		return
	_city_entering=true
	var anchor := Vector2(float(target.anchor[0]),float(target.anchor[1]))
	if _city_source_profile().get("id", "")!=target.id or not controller.region_camera.active:
		await _locate_local_reference(anchor)
		var deadline := Time.get_ticks_msec()+15000
		while is_inside_tree() and _city_source_profile().get("id", "")!=target.id and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	_city_entering=false
	if _city_source_profile().get("id", "")!=target.id:
		map_notice.emit("城市资料尚未准备完成，请稍后重试。")
		return
	controller.region_camera.local_suppressed=false
	var camera := controller.region_camera
	var profile := _city_source_profile()
	if profile.has("presentation_index"):
		# Prebuilt meshes and all geographic anchors use this existing chart.
		# Rebase only on the player's explicit whole-city framing action.
		camera.leave_local()
		camera.tangent_frame=RegionProjection.frame(anchor)
	if profile.get("north_up_overview",false): camera.bearing=0.0
	var safe := _city_safe_rect()
	var area := CityOverview.extent(profile)
	var footprint := Rect2()
	var first := true
	for ll: Vector2 in [area.position,area.end,Vector2(area.end.x,area.position.y),Vector2(area.position.x,area.end.y)]:
		var point: Vector2=RegionProjection.screen_axes(camera.bearing)*(RegionProjection.forward(GlobeProjection.lon_lat_to_unit(ll),camera.tangent_frame)*1000.0)
		footprint=Rect2(point,Vector2.ZERO) if first else footprint.expand(point)
		first=false
	var mpp := maxf(float(profile.minimum_mpp),maxf(footprint.size.x/(safe.size.x*.65),footprint.size.y/(safe.size.y*.90)))
	var unit := GlobeProjection.lon_lat_to_unit(area.get_center())
	camera.local_min_km_per_pixel=float(profile.minimum_mpp)*.001
	camera.km_per_pixel=mpp*.001
	camera.origin=safe.get_center()-RegionProjection.screen_axes(camera.bearing)*(RegionProjection.forward(unit,camera.tangent_frame)/camera.km_per_pixel)
	camera.boundary_limited=false
	_evaluate_scale()
	controller.suspend_motion()
	controller.view_changed.emit()

func _draw_city_labels() -> void:
	var occupied: Array[Rect2]=[]
	for profile: Dictionary in region_view.city_profiles: _draw_city_profile_labels(profile,occupied)

func _draw_city_profile_labels(profile: Dictionary, occupied: Array[Rect2]) -> void:
	var national: bool=profile.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT"
	var districts: Array=profile.get("districts",[])
	if national:
		var layer := region_view.city_layers.get(str(profile.id)) as CityMiniature
		if layer==null: return
		districts=layer._presentation.get("building_print",{}).get("cities",[])
		if districts.is_empty(): return
	var strength := CityOverview.display_strength(_strategic_mpp())
	if strength<=.001: return
	var safe := _city_safe_rect()
	if _strategic_mpp()>=64.0: safe=Rect2(Vector2(16,70),size-Vector2(32,122))
	var bottom := safe.end.y
	safe.size.y=bottom-safe.position.y
	if not national and _strategic_mpp()>=64.0: districts=[{"name":profile.get("map_name",profile.name),"anchor":profile.anchor,"importance":2}]
	for district: Dictionary in districts:
		if national and str(district.get("name","")).is_empty(): continue
		if _strategic_mpp()>40.0 and int(district.get("importance",2))<2: continue
		var point := region_view.chart_screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(district.anchor[0]),float(district.anchor[1]))),controller.region_camera)
		if not safe.grow(-10).has_point(point): continue
		if national:
			var existing := false
			for symbol: Dictionary in _symbol_layout:
				if (symbol.rect as Rect2).get_center().distance_to(point)<26.0: existing=true;break
			if existing: continue
		var district_name := UILocale.name(district) if national else UILocale.text(str(district.name))
		var text_size := ThemeDB.fallback_font.get_string_size(district_name,HORIZONTAL_ALIGNMENT_LEFT,-1,15)
		var baseline := point+Vector2(5,-12)
		baseline.x=minf(baseline.x,safe.end.x-text_size.x-10)
		var label := Rect2(baseline+Vector2(-5,-18),text_size+Vector2(10,8))
		if not safe.encloses(label): continue
		var overlap := false
		for other: Rect2 in occupied:
			if label.grow(5).intersects(other): overlap=true;break
		if overlap: continue
		occupied.append(label)
		draw_string_outline(ThemeDB.fallback_font,baseline,district_name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,5,Color(.10,.13,.12,strength))
		draw_string(ThemeDB.fallback_font,baseline,district_name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color(.98,.94,.78,strength))
	for raw: Array in profile.get("water_reference_limits", []):
		var point := region_view.chart_screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(raw[0]),float(raw[1]))),controller.region_camera)
		if safe.grow(-48).has_point(point):
			draw_string_outline(ThemeDB.fallback_font,point+Vector2(10,-16),UILocale.text("河面参考范围"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,4,Color(.14,.18,.16))
			draw_string(ThemeDB.fallback_font,point+Vector2(10,-16),UILocale.text("河面参考范围"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(.94,.91,.76))


signal place_content_ready
signal current_politics_changed(state_changed: bool)
signal map_notice(message: String)
signal geographic_reference_selected(reference: Dictionary)
signal topic_selected(place_id: String, subject_id: String)
signal player_selected
var _player_unit := Vector3.ZERO
var _player_marker_rect := Rect2()
## One map renderer: geographic surfaces, final display borders and controller input.
const POLITICAL_UNDER_COLOR: Color = Color(0.60, 0.61, 0.54, 0.82)
const POLITICAL_UNDER_WIDTH: float = 1.05

var preserve_on_reparent: bool = false
var show_footer: bool = false
var inspection_preview: bool = false
var observation_suspended: bool = false
const FrameBudget = preload("res://scripts/presentation/map/map_frame_budget.gd")
var _map_budget := FrameBudget.new()

func suspend_for_observation(active: bool) -> void:
	# The unchanged camera can return immediately to the global foundation.
	if observation_suspended == active: return
	observation_suspended = active
	if controller != null: controller.suspend_motion()
	visible = not active
	if active:
		relief.retain_world()
		if not _world_layer.display_installed(): _world_layer.clear()
		_region_layer.clear()
		local_layer.clear()
		if strategic_content!=null: strategic_content.release()
		if local_content!=null: local_content.release()
		region_view.release_landmarks(false,true)
		_cancel_overlay_display()
		strategic_layer = _world_layer
		_bind_relief()
		_transition_elapsed = -1.0
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		set_process(_has_pending_preparation())
	else:
		_resource_demand_dirty = true
		_view_dirty = true
		set_process(true)
		queue_redraw()

var screenshot: Node
var controller: GlobeController
var spatial_world: VNextSpatialWorld
var content: MapGeometryContent
var local_content: LocalSpatialLoader
var local_layer := LocalSpatialLayer.new()
var strategic_content: StrategicSpatialLoader
var _world_layer := LocalSpatialLayer.new()
var _region_layer := LocalSpatialLayer.new()
# Active precision only; both slots use the existing layer/batch implementation.
var strategic_layer: LocalSpatialLayer = _world_layer
var relief := MapRelief.new()
var _political_view: RuntimePoliticalEntityView
var _territory_spatial: VNextSpatialWorld
var _territory_control: TerritoryState
var _current_land_rows: Dictionary = {}
var _military_grid_step_m: int = 50000
var _current_cells: Dictionary = {}
var _current_political_revision: int = 0
var _ink_style_revision: int = 0
var _ink_weight_key: Array = []
var _selected_land_context: String = ""
var _pointer_selection: bool = false
var _clipped_border_cells: Dictionary = {}
var _current_border_key: Array = []
var _current_border_demand: Array[Dictionary] = []
var _border_clip_revision: int = 0

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
var _symbol_hits: Dictionary = {}
var _symbol_atlas := MapSymbolAtlas.new()
var _symbol_layout: Array[Dictionary] = []
var _symbol_place_records: Dictionary = {}
var _symbol_text: Array[Dictionary] = []
var _symbol_layout_dirty: bool = true
var _symbol_selected: String = ""
var _symbol_exclusions: Array[Rect2] = []
var _topic_facts: Array[Dictionary] = []
var _topic_by_place: Dictionary = {}
var _topic_hits: Dictionary = {}
var _topic_links: Array[Dictionary] = []
var _topic_paths: Dictionary = {}
var _topic_projected: Dictionary = {}
var _topic_projection_key: Array = []
var _topic_flow: Node2D
var _topic_flow_enabled: bool = true
const EconomicFlowOverlay = preload("res://scripts/presentation/map/economy/formal_economic_flow_overlay.gd")
var _topic_places: Array[Dictionary] = []
var _logistics_observation: Dictionary = {}
var _logistics_by_place: Dictionary = {}
var _logistics_hits: Array[Dictionary] = []
var _unassigned_pick: bool = false
var _center := Vector2.ZERO
var _radius: float = 220.0
var _globe_rect := Rect2()
var _camera_dirty: bool = true
var _view_dirty: bool = true
var _resource_demand_dirty: bool = true
var _strategic_content_dirty: bool = false
var _strategic_failure: String = ""
var _strategic_waiting: bool = false
var _map_canvas_dirty: bool = true
var _physical_frames: Dictionary = {}
var _local_display_dirty: bool = true
var _controller_appearance_state: Array = []
var _local_coverage_signature: Array = []
var _source_dirty: bool = true
var _political_ink: Dictionary = {}
var _boundary_batches: Array[Dictionary] = []
var _font: Font = preload("res://assets/fonts/map/EBGaramond-Medium.ttf")
var _city_fonts: Dictionary = {}
var _admin_label_metrics: Dictionary = {}
var _country_font: Font = preload("res://assets/fonts/map/EBGaramond-Medium.ttf")
var _geographic_records: Dictionary = {}
var _geographic_cells: Dictionary = {}
var _country_label_layouts: Dictionary = {}
var _source_validity: Dictionary = {}
var _world_label_records: Dictionary = {}
var _world_labels := GlobeLabels.new()
var _label_setting: bool = false
var _physical_background: Dictionary = {}
const TRANSITION_SECONDS: float = 0.22
var region_view := RegionView.new()
var civilian_facilities: CivilianFacilityLayer
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
var _overlay_thread: MapJobs.Job
var _overlay_thread_owner: VNextSpatialWorld
var _overlay_upload_owner: VNextSpatialWorld
var _overlay_generation: int = 0
const MapJobs = preload("res://scripts/presentation/map/map_jobs.gd")
var _overlay_preparation := preload("res://scripts/presentation/map/map_overlay_preparation.gd").new()
var _overlay_uploads: Array[Dictionary] = []
var _overlay_installing: Dictionary = {}
var _overlay_retiring: Array[Dictionary] = []
var _overlay_query_id: String = ""
var _overlay_view := Rect2()
var _overlay_projection_key: Array = []
var _overlay_projection := Rect2()
var _overlay_revision: int = -1
var _overlay_owner: VNextSpatialWorld
var _overlay_request: Array = []
var _overlay_demand_key: Array = []
var _overlay_coast_key: String = ""
var _administrative_display_dirty: bool = false
var _terrain_probe_enabled: bool = "--r57-terrain-probe" in OS.get_cmdline_user_args()
var _terrain_probe_counts: Dictionary = {}
var _location_generation: int = 0


static func _parameter(batch: Dictionary, name: StringName, value: Variant) -> void:
	if not batch.has("parameters"): batch["parameters"] = {}
	var values := batch.parameters as Dictionary
	if not values.has(name) or values[name] != value:
		(batch.material as ShaderMaterial).set_shader_parameter(name,value)
		values[name] = value

static func bind_ocean_material(material: ShaderMaterial) -> void:
	# Bind once per existing material installation. ResourceLoader shares each
	# static Texture2D by path; no per-camera upload or separate texture cache.
	material.set_shader_parameter("ocean_detail",load("res://assets/maps/ocean/orbital_r24/pelagic_eddies_albedo.png"))
	material.set_shader_parameter("ocean_ice",load("res://assets/maps/ocean/orbital_r24/polar_pack_ice_albedo.png"))

static func local_chart_uniforms(batch: Dictionary, coverage: Dictionary, mask_water: bool = false, local_lines: bool = false) -> void:
	# A city's rectangular water request can contain gaps. Its painted water
	# overlays the chart; the rectangle alone is not proof of lake coverage.
	if str(batch.get("kind",""))=="lake" and bool(coverage.get("water_owner",false)) and coverage.get("water")==null:
		mask_water=false
	# Acquired city water also owns its bank outline. An old coast stroke
	# through the same sourced area is not a second authoritative shoreline.
	if str(batch.get("kind",""))=="coast" and bool(coverage.get("water_owner",false)):
		mask_water=true;local_lines=true
	# A camera pan changes projection uniforms, not source ownership. Hundreds
	# of installed boundary chunks otherwise repeat every chart-field lookup.
	if batch.has("chart_coverage") and batch.chart_coverage==coverage and batch.chart_mask==mask_water and batch.chart_lines==local_lines: return
	batch["chart_coverage"]=coverage.duplicate()
	batch["chart_mask"]=mask_water
	batch["chart_lines"]=local_lines
	_parameter(batch,"city_overview",bool(coverage.get("city_overview",false)))
	# This function owns all chart parameters. Empty coverage already wrote
	# every disabled value, including null samplers, on its first submission.
	if coverage.is_empty() and batch.has("parameters") and (batch.parameters as Dictionary).get(&"local_projection",-1.0)==0.0: return
	_parameter(batch,"local_bounds",coverage.get("bounds",Vector4.ZERO))
	_parameter(batch,"local_mask_bounds",coverage.get("mask_bounds",coverage.get("bounds",Vector4.ZERO)))
	_parameter(batch,"local_mask_edge",coverage.get("mask_edge",coverage.get("edge",Vector2.ONE*.12)))
	_parameter(batch,"local_edge",coverage.get("edge",Vector2.ONE*0.12))
	_parameter(batch,"local_height",coverage.get("height"))
	_parameter(batch,"local_height_layout",coverage.get("height_layout",Vector4.ZERO))
	_parameter(batch,"local_height_stride",coverage.get("height_stride",1.0))
	_parameter(batch,"local_height_bounds",coverage.get("height_bounds",Vector4.ZERO))
	_parameter(batch,"local_water",coverage.get("water") if mask_water else null)
	_parameter(batch,"local_projection",0.0 if coverage.is_empty() else 1.0)
	_parameter(batch,"local_vertical_pixels",coverage.get("vertical_pixels",0.0))
	_parameter(batch,"local_cover_strength",coverage.get("strength",0.0) if mask_water else 0.0)
	_parameter(batch,"local_line_owner",local_lines and bool(coverage.get("local_lines",false)))
	_parameter(batch,"local_water_owner",mask_water and bool(coverage.get("water_owner",false)))
	_parameter(batch,"local_line_bounds",coverage.get("line_bounds",Vector4.ZERO))
	_parameter(batch,"local_secondary_bounds",coverage.get("secondary_bounds",Vector4.ZERO))

static func _bounds(batch: Dictionary, viewport_size: Vector2) -> void:
	if batch.get("bounds_size",Vector2.ZERO) != viewport_size:
		RenderingServer.canvas_item_set_custom_rect(batch.item as RID,true,Rect2(Vector2.ZERO,viewport_size))
		batch["bounds_size"] = viewport_size
@onready var _container: TextureRect = $HemisphereViewportContainer
@onready var _viewport: SubViewport = $HemisphereViewportContainer/HemisphereViewport
@onready var _camera: Camera3D = $HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Camera3D
@onready var _moon: MeshInstance3D = $HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Moon

func _init() -> void:
	# The formal scene can discard this placeholder before _ready().
	# Parent the Control immediately so its CanvasItem has the same lifetime.
	civilian_facilities = CivilianFacilityLayer.new()
	add_child(civilian_facilities)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	region_view.landmark_display_changed.connect(_on_local_frame_ready)
	region_view.landmark_load_failed.connect(func(message: String) -> void: map_notice.emit(message))
	region_view.canvas_update_requested.connect(_invalidate_spatial_display)
	region_view.local_frame_ready.connect(_publish_local_frame)
	var chinese := preload("res://assets/fonts/map/SourceHanSerifCN-Regular.otf").duplicate() as FontFile
	_country_font = _country_font.duplicate() as FontFile
	_font = _country_font
	chinese.allow_system_fallback = false
	(_country_font as FontFile).allow_system_fallback = false
	_country_font.fallbacks = [chinese]
	# The existing viewport also retains the prepared 2D map. Static camera and
	# appearance reuse its texture instead of projecting all faces on the GPU.
	_viewport.world_2d = World2D.new()
	_container.texture = _viewport.get_texture()
	region_view.initialize(self)
	civilian_facilities.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	civilian_facilities.facility_selected.connect(func(row: Dictionary) -> void:
		controller.select(controller.selected_polity_id,str(row["place_id"]))
		map_notice.emit(str(row["id"])+" · "+str(row["model"][1])+" · "+str(row["source"])+"；显示假设，非建筑坐标。"))
	local_layer.annotation_canvas = region_view.annotation_canvas
	region_view.frame_budget = _map_budget
	for layer: LocalSpatialLayer in [_world_layer,_region_layer]: layer.annotation_canvas = region_view.annotation_canvas
	_physical_background = {"material": ($HemisphereViewportContainer/HemisphereViewport/GlobeSurface/Surface as MeshInstance3D).material_override}
	bind_ocean_material(_physical_background.material as ShaderMaterial)
	region_view.resize(size)
	visibility_changed.connect(_on_visibility_changed)
	for layer: LocalSpatialLayer in [_world_layer,_region_layer]:
		layer.preparation_failed.connect(func(message: String) -> void: map_notice.emit(message))
		layer.display_changed.connect(_on_spatial_display_changed.bind(layer))
	local_layer.display_changed.connect(_on_spatial_display_changed)
	screenshot = get_tree().root.get_node_or_null("NativeObservation")
	if screenshot==null:
		screenshot = preload("res://scripts/presentation/ui/native_screenshot.gd").new()
		screenshot.name = "NativeScreenshot"
		add_child(screenshot)
	screenshot.set("renderer",self)
	set_process(false)

func _exit_tree() -> void:
	if preserve_on_reparent: return
	_disconnect_current_politics()
	_overlay_generation = _overlay_preparation.invalidate()
	MapJobs.abandon(_overlay_thread)
	_overlay_thread = null
	_clear_overlay_installing()
	_clear_overlay_batches()
	_drain_overlay_retirement(false)
	_world_labels.clear()
	if _footer_prefix_item.is_valid(): RenderingServer.free_rid(_footer_prefix_item)
	if _footer_scale_item.is_valid(): RenderingServer.free_rid(_footer_scale_item)
	relief.dispose()
	_symbol_atlas.dispose()
	local_layer.dispose()
	_world_layer.dispose()
	_region_layer.dispose()
	if strategic_content != null: strategic_content.dispose()
	if local_content != null:
		local_content.dispose()
	_clear_political_ink()
	_clear_boundary_batches()
	region_view.dispose()

func configure(content_value: MapGeometryContent, controller_value: GlobeController) -> void:
	_source_meshes.clear()
	_physical_frames = {}
	_source_dirty = true
	content = content_value
	bind_controller(controller_value)
	_country_label_layouts = content.presentation_document("country_labels").get("layouts", {}) as Dictionary
	_source_validity = content.presentation_document("shared_borders").get("feature_validity",{}) as Dictionary
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
	# This is a fixed historical query/border derivative, not a live-world
	# sovereignty snapshot. Menu and formal world still share this renderer.
	var path := "res://data/strategic/historical_reference_1900.display"
	if FileAccess.file_exists(path):
		var file := FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_DEFLATE)
		if file!=null:
			var value: Variant = file.get_var(false)
			if value is Dictionary and (value as Dictionary).get("schema_id")=="historical_query_display_r37" and (value as Dictionary).get("meshes") is Dictionary:
				var prepared := (value as Dictionary).meshes as Dictionary
				for id: String in source.feature_ids():
					var reference := prepared.get(id,{}) as Dictionary
					if reference.get("parts") is Array and reference.get("uv_bounds") is Rect2 and reference.get("flag_bounds") is Rect2:
						# Reattach shared line arrays; do not deserialize a second
						# complete copy of every component's sampled borders.
						var borders: Array[PackedVector3Array] = []
						for part: Dictionary in reference.parts as Array: borders.append_array(part.borders as Array)
						reference["borders"] = borders
						meshes[id] = reference
	for id: String in source.feature_ids():
		if meshes.has(id): continue
		var mesh := GlobeProjection.source_reference(source.parts(id),id)
		meshes[id] = mesh
	return meshes

func install_source_geometry(meshes: Dictionary) -> void:
	_source_meshes = meshes
	_source_dirty = true
	_physical_frames = {}

func bind_controller(value: GlobeController) -> void:
	controller = value
	controller.region_camera.pose_valid=_camera_pose_valid
	local_layer.local_projection = region_view.chart_screen_point.bind(controller.region_camera)
	for layer: LocalSpatialLayer in [_world_layer,_region_layer]: layer.local_projection = region_view.chart_screen_point.bind(controller.region_camera)
	if not controller.view_changed.is_connected(_invalidate_projection): controller.view_changed.connect(_invalidate_projection)
	if not controller.selection_changed.is_connected(_on_map_selection): controller.selection_changed.connect(_on_map_selection)
	if not controller.appearance_changed.is_connected(_on_controller_appearance): controller.appearance_changed.connect(_on_controller_appearance)
	_controller_appearance_state = _appearance_state()
	if not controller.hover_changed.is_connected(queue_redraw): controller.hover_changed.connect(queue_redraw)
	if not controller.topic_preferences_changed.is_connected(queue_redraw): controller.topic_preferences_changed.connect(queue_redraw)
	_camera.current = true
	_view_dirty = true
	queue_redraw()

func refresh(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView, places: Array[Dictionary], date: Dictionary, display: ResolvedMapContent) -> void:
	_physical_frames = {}
	for background: Dictionary in [_physical_background,region_view.background]: background.erase("surface_appearance_style")
	_political_view = registry
	political.refresh(registry, evidence, economy, places, date, content, display)
	_symbol_atlas.configure(display.place_symbol_roles(),political.records,political.display_date)
	for layer: LocalSpatialLayer in [local_layer,_world_layer,_region_layer]: layer.symbol_limit = _symbol_atlas.limit_for
	_symbol_layout_dirty = true
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
		controller.leave_local()
	_region_labels_dirty = true
	# Historical geometry supplies political queries, flag frames and borders.
	# Independent physical land is loaded separately from Natural Earth.
	for feature_id: String in content.feature_ids():
		if not _source_meshes.has(feature_id):
			_source_meshes[feature_id] = GlobeProjection.source_reference(content.parts(feature_id), feature_id)
	if political.bind_source_queries(_source_meshes, _source_dirty):
		region_view.clear()
		var boundary_features := political.boundary_features
		if political.display_date>="1900-01-01" and political.display_date<"1901-01-01" and not content.presentation_document("shared_borders").is_empty():
			# The installed shared-border derivative already supplies the rest
			# of the world. Only the authored scoped frontier needs source edges.
			boundary_features = {}
			var scoped_area := Rect2(Vector2(33.9,11.9),Vector2(27.2,23.2))
			for owner: String in political.boundary_features:
				var feature := str(political.boundary_features[owner])
				if (_source_meshes[feature].uv_bounds as Rect2).intersects(scoped_area,true): boundary_features[owner] = feature
		_source_boundaries = political.display_boundary_sources(GlobeProjection.boundary_sources(_source_meshes,boundary_features), content)
		_source_boundaries = _shared_border_display(_source_boundaries)
		# Historical exterior edges are not the physical coastline.
		_source_boundaries = _source_boundaries.filter(func(border: Dictionary) -> bool: return str(border.kind)=="macro")
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
		_prepare_political_ink()
		_prepare_boundary_batches()
	_source_dirty = false
	# The layer has rebuilt final macro ownership, including dated display links.
	_invalidate_projection()

func _disconnect_current_politics() -> void:
	if _territory_spatial!=null and _territory_spatial.land_politics_changed.is_connected(_on_current_land_changed): _territory_spatial.land_politics_changed.disconnect(_on_current_land_changed)
	if _territory_control!=null and _territory_control.controller_changed.is_connected(_on_current_control_changed): _territory_control.controller_changed.disconnect(_on_current_control_changed)

func bind_current_politics(spatial: VNextSpatialWorld, control: TerritoryState) -> void:
	if _territory_spatial==spatial and _territory_control==control: return
	_disconnect_current_politics()
	_territory_spatial = spatial
	_territory_control = control
	_current_land_rows = {}
	_current_cells = {}
	_selected_land_context = ""
	if spatial!=null: spatial.land_politics_changed.connect(_on_current_land_changed)
	if control!=null: control.controller_changed.connect(_on_current_control_changed)
	_on_current_land_changed("",false)

func _controller_identity(raw: String) -> String:
	if _political_view==null: return ""
	return raw if _political_view.has_entity(raw) else _political_view.runtime_id_for_source(raw)

func _on_current_control_changed(id: String) -> void:
	if id.begins_with("territory_unit:"): _on_current_land_changed(id)
	else: current_politics_changed.emit(true) # Point control supplies no territorial area.

func _on_current_land_changed(changed_id: String, state_changed: bool = true) -> void:
	if _territory_spatial==null or _territory_control==null: return
	var topology := _territory_spatial.land_topology()
	if topology==null: return
	var ids: Array[String] = []
	if not changed_id.is_empty(): ids.append(changed_id)
	else: ids = topology.land_ids()
	var cells := _current_cells.duplicate()
	if changed_id.is_empty():
		for id: String in cells.keys():
			if not topology.has_land(id): cells.erase(id)
	for id: String in ids:
		if not topology.has_land(id): continue
		var facts := _territory_spatial.land_facts(id)
		if bool(facts.get("historical_initialization_eligible",true)): continue
		var ancestor := id
		var seed := topology._seed
		var initial := seed.get("initial_land_facts",{}) as Dictionary
		while not initial.has(ancestor) and not str(topology._parents.get(ancestor,"")).is_empty(): ancestor = str(topology._parents[ancestor])
		var opening := initial.get(ancestor,seed.initial_politics) as Dictionary
		var sovereignty_changed: bool = facts.sovereign_polity_id!=opening.get("sovereign_polity_id")
		var cell := cells.get(id,{}) as Dictionary
		if cell.is_empty() or cell.get("source_polygon",PackedVector2Array())!=topology.polygon(id):
			var ring := _current_land_ring(topology,id)
			cell = {"ring":ring,"bounds":GlobeProjection.lon_lat_bounds([ring]),"source_polygon":topology.polygon(id)}
		cell = cell.duplicate()
		cell["sovereignty_changed"] = sovereignty_changed
		cells[id] = cell
		_current_land_rows[id] = {"sovereign":str(facts.sovereign_polity_id) if facts.sovereign_polity_id!=null else "","controller":_controller_identity(_territory_control.get_controller(id)) if _territory_control.has_territory(id) else ""}
	_current_cells = cells
	_current_political_revision += 1
	_local_display_dirty = true
	for layer: LocalSpatialLayer in [_world_layer,_region_layer]: layer.set_political_cells(cells)
	_overlay_request.clear()
	_overlay_demand_key.clear()
	_administrative_display_dirty = true
	for background: Dictionary in [_physical_background,region_view.background]: background.erase("surface_appearance_style")
	_refresh_historical_border_geometry()
	_invalidate_appearance()
	if _world_layer.preparing or _region_layer.preparing: set_process(visible)
	current_politics_changed.emit(state_changed)

static func _current_land_ring(topology: LandTopology, id: String) -> PackedVector2Array:
	var local := topology.polygon(id)
	var ring := PackedVector2Array()
	for index: int in range(local.size()):
		var a := local[index]
		var b := local[(index+1)%local.size()]
		var steps := maxi(1,ceili(a.distance_to(b)/2000.0))
		for step: int in range(steps): ring.append(topology.to_geographic(a.lerp(b,float(step)/steps)))
	return ring

func _current_land_at(unit: Vector3) -> String:
	if _territory_spatial==null or unit.is_zero_approx(): return ""
	var topology := _territory_spatial.land_topology()
	if topology==null: return ""
	var id := topology.pick_geographic(RegionProjection.lon_lat(unit))
	if controller.map_mode=="military": return id
	return id if strategic_layer.political_cells_installed().has(id) and _current_land_rows.has(id) else ""

func _land_sovereign(id: String) -> String:
	if _current_land_rows.has(id): return str(_current_land_rows[id].sovereign)
	if _territory_spatial==null: return ""
	var sovereign: Variant=_territory_spatial.land_facts(id).get("sovereign_polity_id")
	return str(sovereign) if sovereign!=null else ""

func _on_map_selection() -> void:
	if not _pointer_selection: _selected_land_context = ""
	_invalidate_appearance()

func reconcile_current_selection() -> void:
	if _selected_land_context.is_empty() or _territory_spatial==null: return
	var details := selected_current_land()
	if details.is_empty():
		_selected_land_context = ""
		return
	_pointer_selection = true
	controller.select(str(details.sovereign_polity_id) if details.get("sovereign_polity_id")!=null else "",controller.selected_place_id)
	_pointer_selection = false

func selected_current_land() -> Dictionary:
	if _territory_spatial==null or _selected_land_context.is_empty(): return {}
	return _territory_spatial.land_details(_selected_land_context,_territory_control)

func _current_border_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _territory_spatial==null: return result
	var state_key: Array = [_current_political_revision,strategic_layer.political_cells_installed()]
	if state_key==_current_border_key: return _current_border_demand
	_current_border_key = state_key
	var topology := _territory_spatial.land_topology()
	if topology==null: return result
	var installed := strategic_layer.political_cells_installed()
	var seen: Dictionary = {}
	for id: String in installed:
		if not topology.has_land(id): continue
		for neighbor: String in topology.neighbors(id):
			var key := id+"|"+neighbor if id<neighbor else neighbor+"|"+id
			if seen.has(key): continue
			seen[key] = true
			var a := _territory_spatial.land_facts(id)
			var b := _territory_spatial.land_facts(neighbor)
			var changed_sovereignty := bool((installed.get(id,{}) as Dictionary).get("sovereignty_changed",false)) or bool((installed.get(neighbor,{}) as Dictionary).get("sovereignty_changed",false))
			var sovereign: bool = changed_sovereignty and a.sovereign_polity_id!=null and b.sovereign_polity_id!=null and a.sovereign_polity_id!=b.sovereign_polity_id
			var first := _controller_identity(_territory_control.get_controller(id)) if _territory_control.has_territory(id) else ""
			var second := _controller_identity(_territory_control.get_controller(neighbor)) if _territory_control.has_territory(neighbor) else ""
			var control := not first.is_empty() and not second.is_empty() and first!=second
			if not sovereign and not control: continue
			result.append({"id":"current_border:"+key,"kind":"sovereignty" if sovereign else "control","lod":str(topology.display_revision())+(":sovereignty" if sovereign else ":control"),"polygons":[topology.polygon(id),topology.polygon(neighbor)],"owners":[a.sovereign_polity_id,b.sovereign_polity_id]})
	_current_border_demand = result
	return result

func refresh_economic_observation(registry: RuntimePoliticalEntityView, evidence: HistoricalPoliticalEvidenceView, economy: FormalWorldEconomyView) -> void:
	if not political.refresh_economies(registry,evidence,economy,controller.economic_mode): return
	for background: Dictionary in [_physical_background,region_view.background]: background.erase("surface_appearance_style")
	_invalidate_appearance()

func set_economic_output(show_values: bool, values: Dictionary) -> void:
	if political.show_output_values==show_values and political.output_values==values: return
	political.show_output_values = show_values
	political.output_values = values
	political.output_maximum = 0.0
	for value: float in values.values(): political.output_maximum = maxf(political.output_maximum,value)
	for background: Dictionary in [_physical_background,region_view.background]: background.erase("surface_appearance_style")
	_invalidate_appearance()

func _shared_border_display(original: Array[Dictionary]) -> Array[Dictionary]:
	var document := content.presentation_document("shared_borders")
	if document.is_empty(): return original
	if political.display_date<str(document.valid_from) or political.display_date>=str(document.valid_to): return original
	var output: Array[Dictionary] = []
	var area := Rect2(Vector2(33.9,11.9),Vector2(27.2,23.2))
	for boundary: Dictionary in original:
		var points := PackedVector2Array()
		for point: Vector3 in boundary.points: points.append(RegionProjection.lon_lat(point))
		if str(boundary.kind) != "macro" or area.intersects(GlobeProjection.lon_lat_bounds([points]),true): output.append(boundary)
	var current_owners := political.get("_whole_owner_by_feature") as Dictionary
	var details: Dictionary = {}
	for detail: Dictionary in document.get("regional_frontiers",[]):
		var pair: Array = (detail.source_features as Array).duplicate()
		pair.sort()
		var key := "|".join(pair)
		if not details.has(key): details[key] = []
		(details[key] as Array).append_array(detail.lines)
	var replacements: Dictionary = {}
	for frontier: Dictionary in document.get("frontier_overrides",[]):
		var features := frontier.source_features as Array
		var owners := _frontier_owners(features,current_owners)
		if owners.size()!=features.size(): continue
		var valid_from := str(document.valid_from)
		var valid_to := str(document.valid_to)
		for feature: String in features:
			var validity: Dictionary = _source_validity.get(feature,{})
			var first := str(validity.get("valid_from",valid_from))
			var last := str(validity.get("valid_to",valid_to))
			if first>valid_from: valid_from=first
			if last<valid_to: valid_to=last
		if political.display_date<valid_from or political.display_date>=valid_to: continue
		if features.size()==2:
			var pair := features.duplicate()
			pair.sort()
			replacements["|".join(pair)] = true
		for line: Array in frontier.lines:
			output.append(_frontier_line(line,owners,valid_from,valid_to,"all"))
	var emitted_details: Dictionary = {}
	for boundary: Dictionary in document.get("boundaries",[]) as Array:
		var features := boundary.source_features as Array
		var pair := features.duplicate()
		pair.sort()
		var pair_key := "|".join(pair)
		if replacements.has(pair_key): continue
		var owners := _frontier_owners(features,current_owners)
		if owners.size()!=2: continue
		var coordinates := _frontier_coordinates(boundary.points)
		if area.intersects(GlobeProjection.lon_lat_bounds([coordinates]),true): continue
		var has_detail := details.has(pair_key)
		output.append({"points":GlobeProjection.display_line(coordinates),"owners":owners,"kind":"macro","valid_from":boundary.valid_from,"valid_to":boundary.valid_to,"frontier_lod":"strategic" if has_detail else "all"})
		var period_key := pair_key+"|"+str(boundary.valid_from)+"|"+str(boundary.valid_to)
		if has_detail and not emitted_details.has(period_key):
			for line: Array in details[pair_key]:
				output.append(_frontier_line(line,owners,str(boundary.valid_from),str(boundary.valid_to),"regional"))
			emitted_details[period_key] = true
	return output

static func _frontier_owners(features: Array, current_owners: Dictionary) -> PackedStringArray:
	var owners := PackedStringArray()
	for feature: String in features:
		var owner := str(current_owners.get(feature,""))
		if not owner.is_empty() and owner not in owners: owners.append(owner)
	return owners

static func _frontier_coordinates(line: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Array in line: points.append(Vector2(float(point[0]),float(point[1])))
	return points

static func _frontier_line(line: Array, owners: PackedStringArray, valid_from: String, valid_to: String, lod: String) -> Dictionary:
	return {"points":GlobeProjection.display_line(_frontier_coordinates(line)),"owners":owners,"kind":"macro","valid_from":valid_from,"valid_to":valid_to,"frontier_lod":lod}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_invalidate_spatial_display()
	if what == NOTIFICATION_RESIZED and is_node_ready():
		if controller!=null and controller.region_camera.active:
			controller.region_camera.fit_requested_scale(size,size*.5)
		_invalidate_projection()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and controller!=null:
		controller.suspend_motion()
		for target: SubViewport in [_viewport,region_view.viewport]:
			if target.render_target_update_mode==SubViewport.UPDATE_ALWAYS:
				target.render_target_update_mode = SubViewport.UPDATE_ONCE

func _invalidate_projection() -> void:
	_camera_dirty = true
	_resource_demand_dirty = true
	_invalidate_spatial_display()
	if visible: set_process(true)

func _invalidate_spatial_display() -> void:
	_symbol_layout_dirty = true
	# Installed batches change visible places and masks, not the camera or
	# geographic demand. Keep their completion out of the loader request path.
	_view_dirty = true
	_map_canvas_dirty = true
	if visible: set_process(true)
	queue_redraw()

func _publish_local_frame() -> void:
	# The scene and map batches are already installed. Only the cached parent
	# must consume the completed child's texture; do not rebuild labels/layers.
	if not visible or controller==null or not controller.region_camera.active: return
	_request_map_frame(true)
	queue_redraw()

func _invalidate_appearance() -> void:
	_symbol_layout_dirty = true
	_map_canvas_dirty = true
	if visible: set_process(true)
	queue_redraw()

func _appearance_state() -> Array:
	return [controller.map_mode,controller.economic_mode,controller.player_polity_id,controller.selected_polity_id,controller.selected_place_id,controller.labels_enabled,controller.strategic_rails_enabled]

func _on_controller_appearance() -> void:
	# Existing HUD popups also emit this signal. Their bounds can change labels,
	# but a clock, drawer or page change does not change the cached map image.
	var state := _appearance_state()
	if state!=_controller_appearance_state:
		_controller_appearance_state = state
		_administrative_display_dirty = true
		_invalidate_appearance()
	else: queue_redraw()

func _ensure_camera() -> void:
	if not _camera_dirty or controller==null: return
	_camera_dirty = false
	_container.position = Vector2.ZERO
	if _container.size!=size: _container.size = size
	if _viewport.size!=Vector2i(size): _viewport.size = Vector2i(size)
	_center = size * 0.5
	var base_radius := minf(size.y / 2.55, size.x * 0.49)
	if controller.initial_framing_pending and visible and size.x > 0.0 and size.y > 0.0:
		controller.initialize_framing(size,base_radius,float(get_window().size.y))
	_radius = base_radius * controller.zoom
	_camera.size = 2.55 / controller.zoom
	_moon.visible = controller.zoom <= 1.10
	_globe_rect = Rect2(_center - Vector2.ONE * _radius, Vector2.ONE * _radius * 2.0).intersection(Rect2(Vector2.ZERO, size))
	region_view.resize(size)
	if controller.region_camera.active: _globe_rect = Rect2(Vector2.ZERO,size)

func _ensure_view() -> LocalSpatialLayer:
	if not _view_dirty or controller==null: return null
	_ensure_camera()
	_view_dirty = false
	var regional := controller.region_camera.active
	# Container publication belongs to the completed draw below. REGION style
	# readiness alone does not prove that its physical window is installed.
	if regional:
		_globe_rect = Rect2(Vector2.ZERO, size)
		if _region_label_frame != controller.region_camera.tangent_frame:
			_region_labels_dirty = true
		if _region_labels_dirty:
			_prepare_region_labels()
	# Queries need current picking/settlement positions, but the final draw
	# commits GPU uniforms and collision-prioritized glyphs once below.
	local_layer.update(controller.region_camera, controller, political.display_date, size, false)
	var prepared_layer := _update_strategic_layer(false)
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
	return prepared_layer

func _clear_political_ink() -> void:
	_political_ink.clear()

func _prepare_political_ink() -> void:
	_clear_political_ink()
	for owner: String in political.records:
		_political_ink[owner] = {"parameters":{},"texture":RID()}
	for background: Dictionary in [_physical_background, region_view.background]:
		background.erase("surface_appearance_style")
	_bind_relief()

func _sync_political_focus() -> void:
	var key: Array = [controller.player_polity_id,_boundary_source_revision,_border_clip_revision]
	if key==_focus_border_key: return
	_focus_border_key = key
	_land_neighbors.clear()
	if controller.player_polity_id.is_empty(): return
	for border: Dictionary in _source_boundaries:
		if str(border.kind)!="macro" or controller.player_polity_id not in border.owners: continue
		for id: String in border.owners:
			if id!=controller.player_polity_id: _land_neighbors[id] = true

func _political_emphasis(owner: String) -> float:
	if controller.player_polity_id.is_empty(): return 0.70
	if owner==controller.player_polity_id: return 1.0
	if _related_polities.has(owner): return 0.88
	if _land_neighbors.has(owner): return 0.58
	return 0.18

func _update_political_ink(regional: bool = false) -> void:
	# CPU style records only. Camera and terrain uniforms belong to physical batches.
	var batches := _political_ink
	var mpp := _strategic_mpp()
	var flag_blend := 0.0
	var fill_weight := 0.0 if controller.map_mode in ["geographic","military"] else MapScaleStyle.economic_country_weight(mpp) if controller.map_mode=="economic" else MapScaleStyle.political_weight(mpp) if controller.map_mode == "political" else 1.0
	if controller.administrative_map_active():
		flag_blend = MapScaleStyle.flag_weight(mpp) if regional else 1.0
		if not regional: fill_weight = 0.86
	var relief_began: int=Time.get_ticks_usec() if observation_profile else 0
	_sync_relief()
	if observation_profile: observation_costs["relief_request_us"]=Time.get_ticks_usec()-relief_began
	var background := region_view.background if regional else _physical_background
	_parameter(background,"ocean_tone",HydrographyStyle.OCEAN_COLOR)
	if not regional: _parameter(background,"globe_basis",controller.orientation())
	var appearance_key: Array = [controller.map_mode,controller.player_polity_id,controller.selected_polity_id,_focus_border_key,regional and region_view.ready]
	var appearance_changed: bool = background.get("surface_appearance_style",[]) != appearance_key
	var weight_key: Array = [appearance_key,political.display_date,flag_blend,fill_weight]
	var thematic := controller.map_mode in ["economic","fulfillment","shortage"]
	if not appearance_changed and not thematic and _ink_weight_key==weight_key: return
	_ink_weight_key=weight_key
	_ink_style_revision+=1
	for owner: String in batches:
		var batch := batches[owner] as Dictionary
		if appearance_changed: _update_ink_appearance(batch,owner,flag_blend,fill_weight)
		var feature := str((political.records.get(owner,{}) as Dictionary).get("geometry_feature_id",""))
		var dated := political.display_active(owner,_source_validity.get(feature,{}) as Dictionary)
		(batch.parameters as Dictionary)["flag_weight"] = flag_blend if dated else 0.0
		# An unavailable country statistic contributes no thematic ink. Physical
		# triangles with/without an ownership partition retain the same terrain.
		var available := controller.map_mode not in ["fulfillment","shortage"] or political.economic_available(owner)
		if controller.map_mode=="economic" and political.show_output_values:
			available = political.output_value(owner)!=null
		(batch.parameters as Dictionary)["political_weight"] = fill_weight if dated and available else 0.0
	background["surface_appearance_style"] = appearance_key

static func _ink_parameter(batch: Dictionary, name: String, value: Variant) -> void:
	(batch.parameters as Dictionary)[name] = value

func _update_ink_appearance(batch: Dictionary, owner: String, flag_blend: float, fill_weight: float) -> void:
	# Content refresh invalidates appearance; camera updates only projection.
	_ink_parameter(batch,"political_focus_style",controller.administrative_map_active())
	_ink_parameter(batch,"political_emphasis",_political_emphasis(owner))
	var color := Color("465451") if owner.is_empty() else political.color(owner, controller.map_mode)
	var base_color := Color(str((political.resolved_visuals.get(owner, {}) as Dictionary).get("color", "#6b8075"))) if controller.map_mode == "political" else color
	if not owner.is_empty() and owner == controller.selected_polity_id:
		color = color.lerp(Color(0.62, 0.51, 0.31), 0.22)
		# Selection changes the flag/outline, not the ground ink shared by LOCAL.
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
	_ink_parameter(batch, "surface_color", color)
	_ink_parameter(batch, "political_base_color", Vector3(base_color.r, base_color.g, base_color.b))
	_ink_parameter(batch, "flag_weight", flag_blend)
	_ink_parameter(batch, "political_weight", fill_weight)
	_ink_parameter(batch, "flag_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	_ink_parameter(batch, "flag_uv_scale", uv_scale)
	_ink_parameter(batch, "flag_uv_offset", uv_offset)
	_ink_parameter(batch, "flag_uv_rotation", Vector2(cos(uv_rotation), sin(uv_rotation)))
	# Style only. The installed physical partition is the sole filled mesh.
	batch["texture"] = texture_rid
	batch["flag_texture"] = texture

func _sync_relief(mpp: float = -1.0) -> void:
	# CITY and REGION use the same physical reference and bounded demand.
	if mpp < 0.0:
		mpp = controller.region_camera.km_per_pixel * 1000.0 if controller.region_camera.active else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, controller.orientation()), controller.orientation(), _radius) * 1000.0
	var camera := controller.region_camera
	var center := RegionProjection.lon_lat(camera.valid_anchor(size).unit as Vector3) if camera.active else RegionProjection.lon_lat(RegionProjection.world_unit(_center,_center,_radius,controller.orientation()))
	var footprint := {"frame":camera.tangent_frame,"origin":camera.origin,"bearing":camera.bearing,"size":size,"step":camera.km_per_pixel,"extent":camera.extent_km} if camera.active else {}
	var selection_began: int=Time.get_ticks_usec() if observation_profile else 0
	var changed := relief.request(visible,mpp,center,size.length()*mpp*0.0005 if camera.active else 10000.0,camera.active,footprint,not _physical_demand_installed())
	if observation_profile: observation_costs["relief_selection_us"]=Time.get_ticks_usec()-selection_began
	var binding_began: int=Time.get_ticks_usec() if observation_profile else 0
	if changed:
		_bind_relief()
	if observation_profile: observation_costs["relief_binding_us"]=Time.get_ticks_usec()-binding_began
	if relief.preparing(): set_process(visible)

func _bind_relief() -> void:
	# Only installed physical land retains relief textures.
	var observed: int=Time.get_ticks_usec() if observation_profile else 0
	var window := _relief_description()
	if observation_profile: observation_costs["relief_description_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
	# The inactive precision is intentionally unbound by hide_display().
	# Rebinding it here only makes the same commit clear every sampler again.
	# A successor receives the current window in _update_strategic_layer()
	# before its complete physical version can become visible.
	strategic_layer.set_reference_window(window)
	if observation_profile: observation_costs["relief_layer_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
	region_view.set_surface_reference(window.surface as Dictionary)
	if observation_profile: observation_costs["relief_region_us"]=Time.get_ticks_usec()-observed

func _relief_description() -> Dictionary:
	var window := relief.window_description(_strategic_mpp())
	window["surface"] = relief.surface_description(_strategic_mpp())
	var city_weight := 1.0-smoothstep(40.0,140.0,_strategic_mpp()) if not region_view.city_profiles.is_empty() else 0.0
	window.surface["print_detail"]=lerpf(1.0,.60,city_weight)
	return window

static func _relief_window_uniforms(batch: Dictionary, window: Dictionary) -> void:
	if batch.is_empty(): return
	_parameter(batch,"relief_window",window.get("texture"))
	_parameter(batch,"relief_window_bounds",window.get("bounds",Vector4(0,0,1,1)))
	_parameter(batch,"relief_window_weight",window.get("weight",0.0))
	_parameter(batch,"relief_window_edge",window.get("edge",0.12))
	_surface_uniforms(batch,window.get("surface",{}) as Dictionary)

static func _surface_uniforms(batch: Dictionary, surface: Dictionary) -> void:
	if batch.get("surface_reference",null)==surface: return
	var previous: Dictionary=batch.get("surface_reference",{})
	batch["surface_reference"] = surface
	_parameter(batch,"surface_print_detail",surface.get("print_detail",1.0))
	var base := surface.get("base",{}) as Dictionary
	if not batch.has("parameters") or previous.get("base",null)!=base:
		_parameter(batch,"surface_base",base.get("texture"))
		_parameter(batch,"surface_base_ba",base.get("ba"))
		_parameter(batch,"surface_base_split",base.get("ba")!=null)
		_parameter(batch,"surface_base_bounds",base.get("bounds",Vector4.ZERO))
		_parameter(batch,"surface_base_encoding",base.get("encoding",0))
		_parameter(batch,"surface_base_feather",base.get("feather",Vector4.ZERO))
		_parameter(batch,"surface_base_opacity",base.get("opacity",1.0))
		_parameter(batch,"surface_cover_base",base.get("cover_weight",1.0))
	var secondary := surface.get("secondary",{}) as Dictionary
	if previous.get("secondary",null)!=secondary:
		_parameter(batch,"surface_secondary",secondary.get("texture"))
		_parameter(batch,"surface_secondary_ba",secondary.get("ba"))
		_parameter(batch,"surface_secondary_split",secondary.get("ba")!=null)
		_parameter(batch,"surface_secondary_bounds",secondary.get("bounds",Vector4.ZERO))
		_parameter(batch,"surface_secondary_encoding",secondary.get("encoding",0))
		_parameter(batch,"surface_secondary_feather",secondary.get("feather",Vector4.ZERO))
		_parameter(batch,"surface_secondary_opacity",secondary.get("opacity",1.0))
		_parameter(batch,"surface_cover_secondary",secondary.get("cover_weight",1.0))
	_parameter(batch,"surface_weight",surface.get("weight",0.0))
	_parameter(batch,"surface_detail_weight",surface.get("detail_weight",0.0))
	var tiles := surface.get("tiles",[]) as Array
	var previous_tiles: Array=previous.get("tiles",[])
	for index: int in range(MapRelief.SURFACE_SLOTS):
		var tile := tiles[index] as Dictionary if index<tiles.size() else {}
		if previous.has("tiles") and index<previous_tiles.size() and previous_tiles[index]==tile: continue
		if previous.has("tiles") and index>=previous_tiles.size() and tile.is_empty(): continue
		_parameter(batch,"surface_tile_%d"%index,tile.get("texture"))
		_parameter(batch,"surface_bounds_%d"%index,tile.get("bounds",Vector4.ZERO))
		_parameter(batch,"surface_inset_%d"%index,tile.get("inset",0.0))
		_parameter(batch,"surface_encoding_%d"%index,tile.get("encoding",0))
		_parameter(batch,"surface_cover_%d"%index,tile.get("cover_weight",1.0))
		_parameter(batch,"surface_core_%d"%index,tile.get("core",Vector4.ZERO))
		_parameter(batch,"surface_edges_%d"%index,tile.get("edges",Vector4.ZERO))

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
	var groups: Dictionary = {}
	for border: Dictionary in _source_boundaries:
		var owners: Array[String] = []
		for owner: String in border.owners: owners.append(owner)
		owners.sort()
		var valid_from := str(border.get("valid_from","0001-01-01"))
		var valid_to := str(border.get("valid_to","9999-12-31"))
		var frontier_lod := str(border.get("frontier_lod","all"))
		var key := "|".join(owners)+"|"+valid_from+"|"+valid_to+"|"+frontier_lod
		if not groups.has(key): groups[key] = {"owners":owners,"lines":[],"valid_from":valid_from,"valid_to":valid_to,"frontier_lod":frontier_lod}
		(groups[key].lines as Array).append(border)
	var shader := preload("res://shaders/presentation/map/globe_boundary.gdshader")
	for key: String in groups:
		var group := groups[key] as Dictionary
		var lines: Array[Dictionary] = []
		lines.assign(group.lines)
		var geometry := GlobeBoundaryBatch.new()
		geometry.prepare(_clip_historical_lines(lines,strategic_layer.political_cells_installed()),"macro")
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("line_data",geometry.data)
		material.set_shader_parameter("miter_limit",1.5)
		material.set_shader_parameter("stroke_feather",0.65)
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item,_viewport.world_2d.canvas)
		RenderingServer.canvas_item_set_draw_index(item,LocalSpatialLayer.DRAW_ORDER+2)
		RenderingServer.canvas_item_set_material(item,material.get_rid())
		RenderingServer.canvas_item_add_mesh(item,geometry.mesh.get_rid())
		var axis := Vector3.ZERO
		for line: Dictionary in lines:
			for point: Vector3 in line.points as PackedVector3Array: axis += point
		axis = axis.normalized()
		var angle := 0.0 if not axis.is_zero_approx() else PI
		for line: Dictionary in lines:
			var points := line.points as PackedVector3Array
			for index: int in range(points.size()):
				angle = maxf(angle,axis.angle_to(points[index]))
				if index>0: angle = maxf(angle,axis.angle_to(points[index-1])+points[index-1].angle_to(points[index]))
		_boundary_batches.append({"geometry":geometry,"material":material,"item":item,"kind":"macro","owners":group.owners,"source_lines":lines,"cull_axis":axis,"cull_angle":minf(angle,PI),"valid_from":group.valid_from,"valid_to":group.valid_to,"frontier_lod":group.frontier_lod})

func _refresh_historical_border_geometry() -> void:
	var cells: Dictionary = {}
	var installed := strategic_layer.political_cells_installed()
	for id: String in installed:
		if bool((installed[id] as Dictionary).get("sovereignty_changed",true)): cells[id] = installed[id]
	if cells==_clipped_border_cells: return
	var areas: Array[Rect2] = []
	for id: String in cells: areas.append(cells[id].bounds as Rect2)
	for id: String in _clipped_border_cells: areas.append(_clipped_border_cells[id].bounds as Rect2)
	_clipped_border_cells = cells
	_border_clip_revision += 1
	for batch: Dictionary in _boundary_batches:
		if not batch.has("source_lines"): continue
		var affected := false
		for line: Dictionary in batch.source_lines:
			var points := PackedVector2Array()
			for point: Vector3 in line.points: points.append(RegionProjection.lon_lat(point))
			var bounds := GlobeProjection.lon_lat_bounds([points])
			for area: Rect2 in areas:
				if bounds.intersects(area,true): affected = true; break
			if affected: break
		if not affected: continue
		var lines: Array[Dictionary] = []
		lines.assign(batch.source_lines as Array)
		var geometry := batch.geometry as GlobeBoundaryBatch
		geometry.prepare(_clip_historical_lines(lines,cells),"macro")
		_parameter(batch,"line_data",geometry.data)

static func _clip_historical_lines(lines: Array[Dictionary], cells: Dictionary) -> Array[Dictionary]:
	if cells.is_empty(): return lines
	var result: Array[Dictionary] = []
	for line: Dictionary in lines:
		var points := PackedVector2Array()
		for point: Vector3 in line.points: points.append(RegionProjection.lon_lat(point))
		var pieces: Array[PackedVector2Array] = [points]
		for id: String in cells:
			var cell := cells[id] as Dictionary
			if not bool(cell.get("sovereignty_changed",true)): continue
			var next: Array[PackedVector2Array] = []
			var shift := Transform2D(0.0,-(cell.bounds as Rect2).get_center())
			for piece: PackedVector2Array in pieces:
				if not (cell.bounds as Rect2).intersects(GlobeProjection.lon_lat_bounds([piece]),true): next.append(piece)
				else:
					for part: PackedVector2Array in Geometry2D.clip_polyline_with_polygon(shift*piece,shift*(cell.ring as PackedVector2Array)): next.append(shift.affine_inverse()*part)
			pieces = next
		for piece: PackedVector2Array in pieces:
			if piece.size()<2: continue
			var output := line.duplicate()
			output.points = GlobeProjection.display_line(piece)
			result.append(output)
	return result

func _draw_boundaries(regional: bool = false) -> void:
	# One national-line RID pool, moved to the active projection canvas.
	var physical_ready := _physical_demand_installed()
	var canvas := region_view.annotation_canvas if regional else _viewport.world_2d.canvas
	var camera := controller.region_camera
	# Select the sourced line before the difference spans a city-scale view.
	var regional_frontier := regional and camera.km_per_pixel<1.2
	var regional_width := 0.75*(1.0-smoothstep(0.4,2.4,camera.km_per_pixel)) if regional else 0.0
	var anchor := camera.valid_anchor(size) if regional else {}
	var center := anchor.unit as Vector3 if regional else controller.orientation().transposed()*Vector3.BACK
	var view_angle := PI*0.5+16.0/maxf(_radius,1.0)
	if regional:
		view_angle = 0.0
		for corner: Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
			view_angle = maxf(view_angle,(corner.distance_to(anchor.pixel as Vector2)+16.0)*camera.km_per_pixel/RegionProjection.EARTH_RADIUS_KM)
	for batch: Dictionary in _boundary_batches:
		if batch.get("parent_canvas",RID())!=canvas:
			RenderingServer.canvas_item_set_parent(batch.item as RID,canvas)
			batch["parent_canvas"] = canvas
		var shown := physical_ready and (controller.administrative_map_active() or controller.administrative_layer_active() or controller.map_mode=="economic") and political.display_date>=str(batch.valid_from) and political.display_date<str(batch.valid_to)
		if batch.frontier_lod!="all": shown=shown and (batch.frontier_lod=="regional")==regional_frontier
		if shown and float(batch.get("cull_angle",PI))<PI*0.5:
			shown = (batch.cull_axis as Vector3).angle_to(center)<=float(batch.cull_angle)+view_angle
		if shown!=bool(batch.get("visible",true)):
			RenderingServer.canvas_item_set_visible(batch.item as RID,shown)
			batch["visible"] = shown
		if not shown: continue
		_parameter(batch,"region_mode",regional)
		local_chart_uniforms(batch,local_layer.local_coverage if regional else {})
		var home := controller.administrative_map_active() and controller.player_polity_id in (batch.owners as Array)
		_parameter(batch,"stroke_color",HOME_BORDER_COLOR if home else POLITICAL_UNDER_COLOR)
		_parameter(batch,"stroke_width",(1.35 if home else POLITICAL_UNDER_WIDTH)+regional_width)
		if regional: _set_region_uniforms(batch)
		else:
			_parameter(batch,"globe_basis",controller.orientation())
			_parameter(batch,"globe_center",_center)
			_parameter(batch,"globe_radius",_radius)
		_bounds(batch,size)

func _commit_map_view(view_was_dirty: bool, prepared_layer: LocalSpatialLayer = null) -> void:
	if controller==null or not _can_submit_map_view(): return
	var commit_map := _map_canvas_dirty or view_was_dirty or _local_display_dirty
	_map_canvas_dirty = false # Later callbacks retain their new invalidation.
	var administrative_changed := _administrative_display_dirty
	_administrative_display_dirty = false
	var regional := controller.region_camera.active
	if commit_map:
		if regional: region_view.set_lighting_scale(controller.region_camera.km_per_pixel)
		var observed: int=Time.get_ticks_usec() if observation_profile else 0
		_sync_political_focus()
		_update_political_ink(regional)
		if observation_profile: observation_costs["politics_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
		local_layer.update(controller.region_camera,controller,political.display_date,size,true,{},prepared_layer==null or _view_dirty)
		if observation_profile: observation_costs["local_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
		_update_strategic_layer(true,prepared_layer)
		if observation_profile: observation_costs["strategic_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
		_sync_landmark_display()
		if observation_profile: observation_costs["landmarks_us"]=Time.get_ticks_usec()-observed
		_local_display_dirty = false
		_place_points.merge(strategic_layer.visible_places,true)
		_place_points.merge(local_layer.visible_places,true)
		observed=Time.get_ticks_usec() if observation_profile else 0
		_draw_boundaries(regional)
		if observation_profile: observation_costs["national_borders_us"]=Time.get_ticks_usec()-observed
	if commit_map or administrative_changed:
		# A completed line batch changes neither symbol identities nor their
		# positions. Demand/view changes already invalidate the existing layout.
		if commit_map: _symbol_layout_dirty = true
		var observed: int=Time.get_ticks_usec() if observation_profile else 0
		_update_overlay_batches(_overlay_local_view() if regional and spatial_world!=null else Rect2(),not commit_map and not _symbol_layout_dirty)
		if observation_profile: observation_costs["overlay_display_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
		_request_map_frame(regional)
		if observation_profile: observation_costs["map_submit_us"]=Time.get_ticks_usec()-observed
	if _transition_elapsed>=0.0:
		if _transition_started==0:
			_transition_started = Time.get_ticks_usec()
			_container.visible = true
			region_view.container.visible = true
			_container.modulate.a = 1.0
			region_view.container.modulate.a = 0.0 if _transition_to_region else 1.0
			set_process(visible)
	else: _show_submitted_canvas(regional)

func _draw() -> void:
	_player_marker_rect=Rect2()
	if region_view.internal_load_active():
		draw_string(ThemeDB.fallback_font,Vector2(28,92),UILocale.text("内部高负载 · 额外模型为测试实例 · 不写入存档"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.94,0.76,0.35))
	if controller==null: return
	var regional := controller.region_camera.active
	if controller.region_camera.local_active:
		_draw_local_data_boundary()
	_draw_city_labels()
	_world_labels.update(self,_country_font,_anchors,_world_label_records,Rect2(Vector2.ZERO,size),controller.zoom,controller.selected_polity_id,controller.hovered_polity_id,controller.labels_enabled,not regional and _transition_elapsed < 0.0,_label_exclusions())
	if _transition_elapsed >= 0.0:
		_draw_player_marker()
		return
	# CanvasItem drawing belongs to this callback. The commit prepares meshes
	# and materials; it cannot issue these country/geographic text commands.
	if regional and controller.labels_enabled and not controller.region_camera.local_active and _can_submit_map_view():
		var covered := local_layer.visible_places.duplicate()
		covered.merge(strategic_layer.visible_places)
		covered.merge(political.places)
		region_view.update_labels(self,controller.region_camera,controller,_font,size,covered,_label_exclusions())
	else: region_view.country_label_rects.clear()
	_prepare_symbol_layout()
	_draw_topic_information()
	_symbol_atlas.draw(self,_symbol_layout,controller.selected_place_id,controller.hovered_place_id)
	_draw_logistics_badges()
	_draw_symbol_labels()
	_draw_administrative_labels()
	for entity_id: String in _anchors:
		if entity_id in [controller.selected_polity_id,controller.hovered_polity_id]:
			draw_circle(_anchors[entity_id],3.0,Color(0.82,0.68,0.40,0.85))
	var metric := controller.region_camera.km_per_pixel if regional else RegionProjection.world_scale(RegionProjection.world_unit(_center, _center, _radius, controller.orientation()), controller.orientation(), _radius)
	var space := "地点关系" if controller.region_camera.local_active and metric<0.05 else "近景" if controller.region_camera.local_active else "区域 · 近" if regional and metric<0.65 else "区域 · 中" if regional and metric<2.4 else "区域 · 远" if regional else "世界"
	var source := "真实高程与现代物理参考" if controller.map_mode=="geographic" else "历史政治 · 物理地理参考"
	if controller.administrative_map_active():
		source = "1900 历史 GIS 重建省界"
		if political.display_date < "1900-01-01" or political.display_date >= "1901-01-01": source = "1900 省界参考超出适用年份"
	if regional and local_content!=null and local_content.content!=null and (controller.region_camera.local_active or local_layer.has_visible_kind("water_surface")):
		var attribution := str(local_content.content.metadata.get("map_attribution_zh",""))
		if not attribution.is_empty(): source = attribution
	if regional and not relief.surface_description(metric*1000.0).is_empty():
		source += " · 现代真实高程／WorldCover 2021 参考"
	if show_footer: _update_footer(UILocale.text(space+" · "+source+"   "),UILocale.text("%.0f 米/像素") % (metric * 1000.0))
	_present_civilian_facilities()
	_draw_player_marker()

func set_player_place(place: Dictionary) -> void:
	var coordinates := place.get("lon_lat",(place.get("geometry",{}) as Dictionary).get("coordinates",[])) as Array
	var unit := Vector3.ZERO
	if coordinates.size()==2:
		unit=GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
	if unit==_player_unit: return
	_player_unit=unit
	queue_redraw()

func _draw_player_marker() -> void:
	if _player_unit.is_zero_approx(): return
	if not controller.region_camera.active and (controller.orientation()*_player_unit).z<=0.0: return
	var ground := screen_point(_player_unit)
	if not ground.is_finite() or not Rect2(Vector2.ZERO,size).has_point(ground): return
	var center := ground-Vector2(0,17)
	var blue := Color("438fe3")
	draw_colored_polygon(PackedVector2Array([ground,center+Vector2(-8,4),center+Vector2(8,4)]),Color.WHITE)
	draw_colored_polygon(PackedVector2Array([ground-Vector2(0,3),center+Vector2(-6,3),center+Vector2(6,3)]),blue)
	draw_circle(center,11,Color.WHITE)
	draw_circle(center,9,blue)
	draw_circle(center+Vector2(0,-3),2.5,Color.WHITE)
	draw_arc(center+Vector2(0,5),4.5,PI,TAU,10,Color.WHITE,2,true)
	_player_marker_rect=Rect2(center-Vector2(12,12),Vector2(24,31))

## Value-only shared topic contract. Geography, authority and resource demand
## are untouched; badges reuse admitted place symbols and their picking order.
func set_topic_facts(rows: Array[Dictionary]) -> void:
	if _topic_facts==rows: return
	note_topic_query("topic_publications")
	_topic_facts = rows.slice(0,64)
	_topic_by_place.clear()
	for row: Dictionary in _topic_facts:
		if not row.has_all(["id","source_id","domain","kind","state","place_id","world_id","world_minute","observer","knowledge","maps"]): continue
		var place := str(row.place_id)
		if _topic_by_place.has(place):
			if row.kind=="country_statistics":(_topic_by_place[place] as Dictionary)["has_country_statistics"]=true
			continue
		var fact:=row.duplicate()
		_topic_by_place[place] = fact
		_topic_by_place[VNextSpatialCatalog.place_query_to_map_id(place)] = fact
	queue_redraw()

func set_topic_links(rows: Array[Dictionary]) -> void:
	var normalized:Array[Dictionary]=rows.slice(0,48)
	var layers:Dictionary={"transport":0,"offer":1,"receipt":2,"contract":3,"cargo":4}
	normalized.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		var first:=int(layers.get(str(a.get("kind","")),0));var second:=int(layers.get(str(b.get("kind","")),0))
		return first<second if first!=second else str(a.get("id",""))<str(b.get("id","")))
	if _topic_links==normalized:return
	_topic_links=normalized;_topic_paths.clear();_topic_projected.clear();_topic_projection_key.clear()
	if spatial_world!=null:
		for link:Dictionary in _topic_links:
			if str(link.get("kind","")) in ["rail_reference","shipping_reference"]:
				var rail_units := PackedVector3Array()
				for ll: Array in link.get("coordinates",[]):
					if ll.size()==2: rail_units.append(GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1]))))
				_topic_paths[str(link.id)]={"units":rail_units,"local":false}
				var levels: Dictionary={}
				for level: String in link.get("lod_coordinates",{}):
					var level_units := PackedVector3Array()
					for ll: Array in link.lod_coordinates[level]: level_units.append(GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1]))))
					levels[level]=level_units
				if not levels.is_empty(): _topic_paths[str(link.id)]["levels"]=levels
				continue
			var a:=spatial_world.get_place(str(link.get("from","")));var b:=spatial_world.get_place(str(link.get("to","")))
			if not a.get("lon_lat") is Array or not b.get("lon_lat") is Array:continue
			if a.lon_lat.size()!=2 or b.lon_lat.size()!=2:continue
			var u:=GlobeProjection.lon_lat_to_unit(Vector2(float(a.lon_lat[0]),float(a.lon_lat[1])))
			var v:=GlobeProjection.lon_lat_to_unit(Vector2(float(b.lon_lat[0]),float(b.lon_lat[1])))
			var units:=PackedVector3Array()
			for index:int in range(25):units.append(u.slerp(v,float(index)/24.0))
			_topic_paths[str(link.id)]={"units":units,"local":u.is_equal_approx(v)}
	_ensure_topic_flow()
	if _topic_links.is_empty():_topic_flow.call("update_paths",_topic_links)
	queue_redraw()

func _ensure_topic_flow() -> void:
	if is_instance_valid(_topic_flow):return
	_topic_flow=EconomicFlowOverlay.new();add_child(_topic_flow)
	_topic_flow.call("set_enabled",_topic_flow_enabled)

func set_topic_world_minute(minute: int) -> void:
	_ensure_topic_flow();_topic_flow.call("set_world_minute",minute)

func set_topic_flow_animation(enabled: bool) -> void:
	_topic_flow_enabled=enabled
	_ensure_topic_flow();_topic_flow.call("set_enabled",enabled)

func _topic_points(link:Dictionary) -> PackedVector2Array:
	var id:=str(link.get("id",""))
	if _topic_projected.has(id):return _topic_projected[id]
	var points:=PackedVector2Array();var source:Dictionary=_topic_paths.get(id,{})
	if str(link.get("kind",""))=="shipping_reference": _prepare_shipping_path(link,source)
	var units:PackedVector3Array=source.get("units",PackedVector3Array())
	if source.has("levels"):
		units=source.levels["overview" if _strategic_mpp()>250.0 else "district" if _strategic_mpp()>60.0 else "near"]
	if units.is_empty():return points
	if bool(source.get("local",false)):
		if id.begins_with("logistics:"): return points
		if str(link.get("kind",""))=="transport" or (not controller.region_camera.active and (controller.orientation()*units[0]).z<0):return points
		var point:=screen_point(units[0])
		if not point.is_finite():return points
		for index:int in range(25):points.append(point+Vector2(0,-12)+Vector2.from_angle(.35+float(index)*TAU/24.0)*9.0)
	else:
		for unit:Vector3 in units:
			points.append(screen_point(unit) if not unit.is_zero_approx() and (controller.region_camera.active or (controller.orientation()*unit).z>=0) else Vector2(INF,INF))
	_topic_projected[id]=points
	return points

func _prepare_shipping_path(link: Dictionary, source: Dictionary) -> void:
	var reference := strategic_layer.physical_reference()
	var key := str(reference.get("key",""))
	if source.get("water_key","unprepared")==key: return
	source["water_key"]=key
	var line := PackedVector2Array()
	for ll: Array in link.get("coordinates",[]): line.append(Vector2(float(ll[0]),float(ll[1])))
	var tracks: Array[PackedVector2Array]=[]
	# The legacy waypoints are a schematic corridor, not a surveyed sea lane.
	# Use only portions inside installed coverage and outside physical land.
	for bounds: Array in reference.get("coverage",[]):
		var cell := PackedVector2Array([Vector2(bounds[0],bounds[2]),Vector2(bounds[1],bounds[2]),Vector2(bounds[1],bounds[3]),Vector2(bounds[0],bounds[3])])
		tracks.append_array(Geometry2D.intersect_polyline_with_polygon(line,cell))
	for land: Dictionary in reference.get("land",[]):
		var remaining: Array[PackedVector2Array]=[]
		for track: PackedVector2Array in tracks:
			remaining.append_array(Geometry2D.clip_polyline_with_polygon(track,(land.rings as Array)[0] as PackedVector2Array))
		tracks=remaining
		if tracks.is_empty(): break
	var units := PackedVector3Array()
	for track: PackedVector2Array in tracks:
		if not units.is_empty(): units.append(Vector3.ZERO)
		for index: int in range(1,track.size()):
			var a := GlobeProjection.lon_lat_to_unit(track[index-1])
			var b := GlobeProjection.lon_lat_to_unit(track[index])
			var count := clampi(int(ceil(a.angle_to(b)*6371.0088/2.0)),1,256)
			if index==1: units.append(a)
			for step: int in range(1,count+1): units.append(a.slerp(b,float(step)/count))
	source["units"]=units

func set_topic_places(rows: Array[Dictionary]) -> void:
	if _topic_places==rows:return
	_topic_places=rows.slice(0,96)
	_symbol_layout_dirty=true
	queue_redraw()

func set_logistics_observation(value: Dictionary) -> void:
	if _logistics_observation==value: return
	_logistics_observation=value;_logistics_by_place.clear();_logistics_hits.clear()
	for row: Dictionary in value.get("nodes",[]): _logistics_by_place[str(row.place_id)]=row
	queue_redraw()

func _draw_logistics_badges() -> void:
	_logistics_hits.clear()
	if controller.map_mode!="economic": return
	# Public station coordinates, independent of private stock/warehouse sites.
	if controller.region_camera.active and _strategic_mpp()<350.0:
		for station: Dictionary in _logistics_observation.get("stations",[]):
			var ll: Array=station.coordinates
			var point := screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1]))))
			if point.is_finite() and Rect2(Vector2.ZERO,size).has_point(point):
				draw_circle(point,3.1,Color("4b5553"))
				draw_circle(point,1.7,Color("d7d5b9"))
				_logistics_hits.append({"rect":Rect2(point-Vector2(6,6),Vector2(12,12)),"station":station})
	var occupied: Dictionary = {}
	for rect: Rect2 in _symbol_exclusions: MapSymbolAtlas.occupy(rect,occupied)
	for rect: Rect2 in local_layer.label_rects: MapSymbolAtlas.occupy(rect,occupied)
	var candidates: Array[Dictionary] = []
	for row: Dictionary in _symbol_layout:
		MapSymbolAtlas.occupy(row.rect,occupied)
		var place := FormalEconomicMapObservation.canonical_place(str(row.id))
		if not _logistics_by_place.has(place): continue
		var data := _logistics_by_place[place] as Dictionary
		var warehouses := int(data.get("warehouses",0))
		var transit := int(data.get("transit_orders",0))
		var pending := int(data.get("pending_orders",0))
		if warehouses+transit+pending==0: continue
		var score := (4 if transit>0 else 0)+(2 if pending>0 else 0)+(1 if warehouses>0 else 0)
		candidates.append({"place":place,"rect":row.rect,"data":data,"score":score,"warehouses":warehouses,"transit":transit,"pending":pending})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return str(a.place)<str(b.place) if a.score==b.score else int(a.score)>int(b.score))
	var shown := 0
	var budget := 8 if controller.region_camera.active else 4
	var viewport := Rect2(Vector2.ZERO,size).grow(-5)
	for row: Dictionary in candidates:
		if shown>=budget: break
		var parts: Array[String] = []
		if row.warehouses>0: parts.append(UILocale.text("仓储 %d")%int(row.warehouses))
		if row.transit>0: parts.append(UILocale.text("在途 %d")%int(row.transit))
		if row.pending>0: parts.append(UILocale.text("待发 %d")%int(row.pending))
		var caption := " · ".join(parts)
		var font := GlobeLabels.font_for_name(_font,caption)
		var extent := Vector2(ceilf(font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x)+12,20)
		var base := row.rect as Rect2
		var place := str(row.place)
		for point: Vector2 in [Vector2(base.end.x+5,base.end.y+3),Vector2(base.position.x-extent.x-5,base.end.y+3),Vector2(base.end.x+5,base.position.y-extent.y-3)]:
			var box := Rect2(point,extent)
			if not viewport.encloses(box) or not MapSymbolAtlas.free_rect(box.grow(2),occupied): continue
			var edge := Color("82b1c0") if row.transit>0 else Color("d5b477")
			draw_rect(box,Color(0.045,0.085,0.105,0.94))
			draw_line(box.position,Vector2(box.position.x,box.end.y),edge,1.5)
			draw_string(font,box.position+Vector2(6,14),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("eee5cf"))
			MapSymbolAtlas.occupy(box.grow(2),occupied)
			_logistics_hits.append({"rect":box,"place_id":place,"data":row.data})
			shown += 1
			break
		if not _topic_hits.has(place): _topic_hits[place]={"subject_id":""}

func _get_tooltip(at_position: Vector2) -> String:
	if controller==null or controller.map_mode!="economic": return ""
	if is_instance_valid(_topic_flow) and _topic_flow.visible:
		for hit: Rect2 in _topic_flow.ship_hits:
			if hit.has_point(at_position): return UILocale.text("商船示意 · 航运联系，非实时船位")
	for hit: Dictionary in _logistics_hits:
		if not (hit.rect as Rect2).has_point(at_position): continue
		if hit.has("station"): return UILocale.text(str(hit.station.name))+"\n"+UILocale.text("铁路走廊：历史资料；线位：现代参考")
		var text := FormalEconomicText.logistics_brief(hit.data,_logistics_observation.get("units",{}))
		text+="\n"+UILocale.text("城市汇总；光点表示在途订单方向，非车船位置")
		if _logistics_observation.get("truncated",false): text+="\n"+UILocale.text("只列本次可见记录，更多见运输账目")
		return text
	if political.show_output_values:
		var owner := _polity_at(at_position)
		var value: Variant = political.output_value(owner)
		if value!=null: return UILocale.text("模拟日产值 · %.0f 生丁/日")%float(value)
	return ""

func topic_place_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in _symbol_layout:
		var id := FormalEconomicMapObservation.canonical_place(str(row.id))
		if not id.is_empty() and id not in ids: ids.append(id)
	return ids

func topic_capital(source_id: String) -> Dictionary:
	for row: Dictionary in _symbol_atlas.capital_places().values():
		if str(row.get("parent_country_id",""))==source_id: return row
	return {}

func _draw_topic_information() -> void:
	_topic_hits.clear()
	var mode := controller.map_mode
	if is_instance_valid(_topic_flow):_topic_flow.visible=mode=="economic"
	if mode!="economic": return
	var budget := 24 if mode=="economic" and controller.region_camera.local_active else 16 if mode=="economic" and controller.region_camera.active else 12 if mode=="economic" else 12 if controller.region_camera.local_active else 8 if controller.region_camera.active else 2
	for row: Dictionary in _symbol_layout:
		var fact := _topic_by_place.get(str(row.id),{}) as Dictionary
		if fact.is_empty() or mode not in (fact.maps as Array): continue
		if mode!="economic" and not controller.region_camera.active and str(fact.kind)!="country_statistics" and str(row.id)!=controller.selected_place_id:
			for candidate: Dictionary in _topic_facts:
				if candidate.kind=="country_statistics" and candidate.place_id==fact.place_id: fact=candidate;break
			if fact.kind!="country_statistics": continue
		var id := str(fact.place_id)
		if _topic_hits.has(id): continue
		# Economic facts share the city symbol and hit target at its true anchor.
		_topic_hits[id] = fact
		if _topic_hits.size()>=budget: break
	if is_instance_valid(_topic_flow):_topic_flow.visible=mode=="economic"
	if mode!="economic" or _topic_links.is_empty() or spatial_world==null:return
	var rc:=controller.region_camera
	var projection_key:Array=[controller.orientation(),controller.zoom,size,rc.active,rc.local_active,rc.tangent_frame,rc.origin,rc.km_per_pixel,rc.bearing]
	projection_key.append(strategic_layer.physical_reference().get("key",""))
	var changed:bool=projection_key!=_topic_projection_key
	if changed:_topic_projection_key=projection_key;_topic_projected.clear()
	var flows:Array[Dictionary]=[]
	for link:Dictionary in _topic_links:
		_draw_topic_link(link)
		if str(link.get("kind","")) in ["rail_reference","shipping_reference"] and (not controller.region_camera.active or _strategic_mpp()>2200.0): continue
		if changed and bool(link.get("animate",false)) and flows.size()<16:
			var points:=_topic_points(link);var contiguous:=PackedVector2Array();var pieces:Array[PackedVector2Array]=[]
			for point:Vector2 in points:
				if point.is_finite():contiguous.append(point)
				else:
					if contiguous.size()>1:pieces.append(contiguous)
					contiguous=PackedVector2Array()
			if contiguous.size()>1:pieces.append(contiguous)
			var viewport := PackedVector2Array([Vector2(-8,-8),Vector2(size.x+8,-8),size+Vector2(8,8),Vector2(-8,size.y+8)])
			# Clip every water-contiguous piece before choosing visible content.
			# The longest open-sea piece must not suppress a visible harbour piece.
			for piece:PackedVector2Array in pieces:
				for clipped: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(piece,viewport):
					if flows.size()>=16: break
					var length:float=0.0
					for index:int in range(1,clipped.size()):length+=clipped[index-1].distance_to(clipped[index])
					if length>0:flows.append({"points":clipped,"length":length,"rail":str(link.get("kind",""))=="rail_reference","ship":str(link.get("kind",""))=="shipping_reference","directions":link.get("flow_directions",[1]),"observed_minute":int(link.get("observed_minute",0))})
	if changed:_ensure_topic_flow();_topic_flow.call("update_paths",flows)

func _draw_topic_link(link:Dictionary) -> void:
	# Contract endpoints alone do not define a railway alignment.
	if str(link.get("id","")).begins_with("logistics:"): return
	var kind:=str(link.get("kind",""))
	if kind=="shipping_reference": return
	if kind=="rail_reference":
		_draw_rail_reference(link)
		return
	var status:=str(link.get("status",""))
	var color:=Color("caaa73")
	var width:=1.5
	var dashed:=true
	if kind=="transport":color=Color("5e8796");width=1.0
	elif kind=="offer":color=Color("7b9cc0") if bool(link.get("available",false)) else Color("b56868")
	elif kind=="receipt":color=Color(0.47,0.60,0.53,0.65);dashed=false
	elif kind=="cargo":
		color=Color("e5a36d");width=2.6
		dashed=status in ["WAITING","WAITING_TRANSFER"]
		if status in ["WAITING_UNLOAD","UNLOADING","AWAITING_RECIPIENT"]:color=Color("c2a0dd")
		elif status=="LOADING":color=Color("65cfca")
		elif status=="LOSS_RECORD":color=Color("c97a78")
	elif kind=="contract":
		if status in ["DELIVERED","CANCELLED"] or str(link.get("state","")).contains("历史"):color=Color(0.48,0.53,0.49,0.65)
		elif status=="TRANSIT":color=Color("dc986b")
		if str(link.get("id","")).begins_with("logistics:"): dashed=status!="TRANSIT"
	var viewport:=Rect2(Vector2.ZERO,size).grow(12)
	var points:=_topic_points(link)
	if points.size()<2:return
	if not dashed:
		var contiguous:=PackedVector2Array()
		for point:Vector2 in points:
			if point.is_finite():contiguous.append(point)
			else:
				if contiguous.size()>1:draw_polyline(contiguous,color,width,true)
				contiguous=PackedVector2Array()
		if contiguous.size()>1:draw_polyline(contiguous,color,width,true)
	else:
		for index:int in range(1,points.size(),2):
			if points[index-1].is_finite() and points[index].is_finite():draw_line(points[index-1],points[index],color,width,true)
	var index:=mini(14,points.size()-1)
	var tip:=points[index];var tail:=points[index-1]
	if bool(link.get("directed",false)) and tip.is_finite() and tail.is_finite() and viewport.has_point(tip) and tip.distance_squared_to(tail)>1:_draw_topic_arrow(tip,(tip-tail).normalized(),color,width)
	if kind=="cargo" and status in ["WAITING","WAITING_TRANSFER","LOADING","WAITING_UNLOAD","UNLOADING","AWAITING_RECIPIENT"]:
		var point:=points[points.size()-1] if status in ["WAITING_UNLOAD","UNLOADING","AWAITING_RECIPIENT"] else points[0]
		if point.is_finite() and viewport.has_point(point):draw_arc(point,6,0,TAU,16,color,2.0,true)

func _draw_rail_reference(link: Dictionary) -> void:
	if not controller.region_camera.active or _strategic_mpp()>2200.0: return
	var points := _topic_points(link)
	var strip := PackedVector2Array()
	for point: Vector2 in points:
		if point.is_finite(): strip.append(point)
		else:
			_draw_rail_strip(strip);strip=PackedVector2Array()
	_draw_rail_strip(strip)

func _draw_rail_strip(points: PackedVector2Array) -> void:
	if points.size()<2: return
	# Fine continuous cartographic track. No marching dashes or arrowheads.
	draw_polyline(points,Color(.83,.82,.70,.50),2.6,true)
	draw_polyline(points,Color(.27,.32,.30,.85),1.2,true)

func _draw_topic_arrow(tip:Vector2,direction:Vector2,color:Color,width:float) -> void:
	var normal:=Vector2(-direction.y,direction.x)
	draw_line(tip,tip-direction*7.0+normal*3.5,color,width,true)
	draw_line(tip,tip-direction*7.0-normal*3.5,color,width,true)

func _prepare_symbol_layout() -> void:
	note_topic_query("symbol_prepare_calls")
	var exclusions := _label_exclusions()
	exclusions.append_array(region_view.country_label_rects if controller.region_camera.active else _world_labels.label_rects)
	if not _symbol_layout_dirty and _symbol_selected==controller.selected_place_id and exclusions==_symbol_exclusions: return
	note_topic_query("symbol_layout_calls")
	_symbol_layout_dirty = false
	_symbol_selected = controller.selected_place_id
	_symbol_exclusions = exclusions
	var previous: Dictionary = {}
	for row: Dictionary in _symbol_layout: previous[str(row.id)] = true
	var records: Dictionary = {}
	var points := _place_points.duplicate()
	for id: String in points: records[id] = _display_place(id)
	for id: String in _symbol_atlas.capital_places():
		if records.has(id): continue
		var record := _symbol_atlas.capital_places()[id] as Dictionary
		var ll := record.lon_lat as Array
		var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1])))
		if not controller.region_camera.active and (controller.orientation()*unit).z<0.0: continue
		var point := screen_point(unit)
		if not Rect2(Vector2.ZERO,size).has_point(point): continue
		records[id] = record
		points[id] = point
	if controller.region_camera.active:
		var mpp := _strategic_mpp()
		var viewport := Rect2(Vector2.ZERO,size)
		for reference: Dictionary in _symbol_atlas.reference_places():
			if mpp>float(reference.max_mpp): continue
			var id := str(reference.id)
			var ll := reference.lon_lat as Array
			var point := screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1]))))
			if not viewport.has_point(point): continue
			records[id] = reference
			points[id] = point
	# These are existing observer-known Catalog anchors, not new settlements.
	# Admit them through the same atlas budget and occupied-rectangle rules.
	var topic_aliases:Dictionary={}
	for record:Dictionary in _topic_places:
		var id:=str(record.id)
		var local_id:=VNextSpatialCatalog.place_query_to_map_id(id)
		topic_aliases[id]=true;topic_aliases[local_id]=true
		if records.has(id) or records.has(local_id):continue
		var ll:Array=record.lon_lat
		var unit:=GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1])))
		if not controller.region_camera.active and (controller.orientation()*unit).z<0.0:continue
		var point:=screen_point(unit)
		if not Rect2(Vector2.ZERO,size).has_point(point):continue
		records[id]=record;points[id]=point
	# Reuse only the already requested administrative identities. Their known
	# chief-lieu coordinates are not new settlements, polygon centroids or facts.
	if controller.region_camera.active and spatial_world!=null and not _city_display_active():
		for row: Dictionary in _overlay_demand:
			if row.kind!="administration": continue
			var record := row.get("capital_symbol",{}) as Dictionary
			if record.is_empty(): continue
			var id := str(record.id)
			if records.has(id): continue
			var ll := record.capital_lon_lat as Array
			var point := screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(ll[0]),float(ll[1]))))
			if not Rect2(Vector2.ZERO,size).has_point(point): continue
			records[id] = record
			points[id] = point
	_symbol_place_records = records
	var candidates: Array[Dictionary] = []
	for id: String in points:
		var record := records.get(id,{}) as Dictionary
		if record.is_empty() or str(record.get("display_kind",""))=="physical_cover": continue
		if not UILocale.map_name_available(record): continue
		var model := region_view.landmark_visible(id) or region_view.settlement_visible(id)
		candidates.append({"id":id,"record":record,"point":points[id],"model":model,"topic_locator":topic_aliases.has(id)})
	var occupied: Dictionary = {}
	_symbol_layout = _symbol_atlas.layout(candidates,controller.region_camera.active,_strategic_mpp(),controller.selected_place_id,previous,exclusions,size,occupied)
	_symbol_hits.clear()
	_symbol_text.clear()
	local_layer.label_rects.clear()
	strategic_layer.label_rects.clear()
	for row: Dictionary in _symbol_layout:
		if bool((row.record as Dictionary).get("symbol_selectable",true)): _symbol_hits[str(row.id)] = (row.rect as Rect2).grow(4.0)
	for row: Dictionary in _symbol_layout:
		var id := str(row.id)
		var selected := id==controller.selected_place_id
		if bool(row.get("topic_locator_only",false)) and not selected: continue
		if not selected and _symbol_text.size()>=40: continue
		var record := row.record as Dictionary
		var name := UILocale.name(record.merged({"name":record.get("display_name",record.get("name",""))},true))
		if name.is_empty(): continue
		if not _city_fonts.has(name):
			if _city_fonts.size()>=256: _city_fonts.clear()
			var chosen_font := GlobeLabels.font_for_name(_font,name)
			_city_fonts[name] = {"font":chosen_font,"size":chosen_font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,13)+Vector2(0,3)}
		var metrics := _city_fonts[name] as Dictionary
		var font := metrics.font as Font
		var rect := row.rect as Rect2
		var baseline := Vector2(rect.end.x+4.0,rect.get_center().y+4.0)
		var text_box := Rect2(baseline-Vector2(0,13),metrics["size"] as Vector2)
		if not Rect2(Vector2.ZERO,size).encloses(text_box): continue
		if not selected and not MapSymbolAtlas.free_rect(text_box.grow(2.0),occupied): continue
		MapSymbolAtlas.occupy(text_box.grow(2.0),occupied)
		_symbol_text.append({"id":id,"name":name,"font":font,"baseline":baseline,"reference":id.begins_with("map_reference:")})
		local_layer.label_rects.append(text_box)
	if not _topic_places.is_empty():
		var current:Dictionary={}
		for row:Dictionary in _symbol_layout:current[str(row.id)]=true
		if current!=previous:place_content_ready.emit.call_deferred()

func _draw_symbol_labels() -> void:
	for label: Dictionary in _symbol_text:
		if not controller.labels_enabled and not bool(label.reference) and str(label.id) not in [controller.selected_place_id,controller.hovered_place_id]: continue
		var font := label.font as Font
		font.draw_string_outline(get_canvas_item(),label.baseline as Vector2,str(label.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13,2,Color(0.16,0.19,0.17,0.85))
		draw_string(font,label.baseline as Vector2,str(label.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(0.94,0.92,0.83))

func refresh_civilian_facilities(observation: Array[Dictionary]) -> void:
	civilian_facilities.rows = observation
	queue_redraw()

func _present_civilian_facilities() -> void:
	var points: Dictionary = {}
	for row: Dictionary in civilian_facilities.rows:
		var coordinates := row["lon_lat"] as Array
		var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(coordinates[0]),float(coordinates[1])))
		var rotated := controller.orientation()*unit
		if not controller.region_camera.active and rotated.z<=0.0: continue
		var point := controller.region_camera.project(unit) if controller.region_camera.active else GlobeProjection.sphere_screen(rotated,_center,_radius)
		if is_finite(point.x): points[row["id"]] = point
	civilian_facilities.present(points,controller.region_camera.active,controller.region_camera.active and controller.region_camera.km_per_pixel<0.1)

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
	if _terrain_probe_enabled and event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index==MOUSE_BUTTON_LEFT and click.ctrl_pressed and click.alt_pressed:
			_dump_terrain_point(click.position)
			accept_event()
			return
	var wheel := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]
	var camera_input := wheel or event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] or event is InputEventMouseMotion and (controller._dragging or controller._bearing_dragging)
	if camera_input:
		_location_generation+=1
	if input_blocked.is_valid() and event is InputEventMouse:
		if bool(input_blocked.call(get_global_transform()*(event as InputEventMouse).position)):
			controller.suspend_motion()
			controller.hover("", "")
			return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and _player_marker_rect.has_point(event.position):
		controller.suspend_motion()
		player_selected.emit()
		accept_event()
		return
	if camera_input and _transition_elapsed>=0.0:
		# New input supersedes a cosmetic fade; it does not wait for its timer
		# or a pending LOD. The next valid draw selects the current camera.
		_transition_elapsed = -1.0
		_transition_started = 0
		_invalidate_spatial_display()
	_ensure_camera()
	if event is InputEventMouse:
		_last_pointer = (event as InputEventMouse).position
	var was_regional := controller.region_camera.active

	var manipulating := event is InputEventMouseMotion and (controller._dragging or controller._bearing_dragging)
	var unit := Vector3.ZERO if manipulating else unit_at(_last_pointer)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		controller.begin_bearing(unit,_last_pointer)
	var minimum_mpp := 2.0 # Full proposed pose is checked by RegionCamera.
	var clicked := controller.handle_input(event,_globe_rect,unit,{"center":_center,"base_radius":minf(size.y/2.55,size.x*0.49),"size":size,"minimum_mpp":minimum_mpp})
	# A drag changes the camera, never the selected object. Picking every
	# intermediate pointer duplicates projection work along fragmented shores.
	if event is InputEventMouseMotion and (controller._dragging or controller._bearing_dragging):
		if controller._bearing_dragging: _stabilize_local_anchor(controller._bearing_anchor,controller._bearing_pixel)
		controller.hover("", "")
		accept_event()
		return
	if wheel:
		_ensure_camera()
		_evaluate_scale()
		if was_regional: _stabilize_local_anchor(unit,_last_pointer)
	if event is InputEventMouseMotion or clicked:
		_ensure_view()
		if not _can_submit_map_view():
			controller.hover("", "")
			accept_event()
			return
		var point: Vector2 = (event as InputEventMouseMotion).position if event is InputEventMouseMotion else (event as InputEventMouseButton).position
		_unassigned_pick = false
		var place_id := _place_at(point)
		var polity_id := ""
		var chart_point := controller.region_camera.project(unit_at(point)) if controller.region_camera.local_active else point
		var physical_water := place_id.is_empty() and strategic_layer.physical_water_at(chart_point,controller.region_camera,{"basis":controller.orientation(),"center":_center,"radius":_radius})
		if not physical_water and controller.administrative_layer_active() and place_id.is_empty() and spatial_world != null and controller.region_camera.active:
			var picked := unit_at(point)
			if not picked.is_zero_approx():
				var displayed: Array[String] = []
				for row: Dictionary in _overlay_demand:
					if row.kind=="administration" and _overlay_batches.has(str(row.id)): displayed.append(str(row.id))
				place_id = spatial_world.pick_administration(RegionProjection.lon_lat(picked),political.display_date,displayed)
				if not place_id.is_empty() and not UILocale.map_name_available(spatial_world.administrative_identity(place_id)):
					controller.hover("", "")
					accept_event()
					return
				if not place_id.is_empty() and place_id!=controller.selected_place_id and str(spatial_world.administrative_identity(place_id).get("polity_id",""))!=controller.player_polity_id: place_id = ""
		if place_id.is_empty() and not physical_water:
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
		if not place_id.is_empty():
			var named: Dictionary = spatial_world.administrative_identity(place_id) if spatial_world!=null and place_id.begins_with("administrative_region:") else _geographic_records.get(place_id,{}) if _geographic_records.has(place_id) else _display_place(place_id)
			if not UILocale.map_name_available(named):
				controller.hover("", "")
				accept_event()
				return
		var current_land := _current_land_at(unit_at(point)) if not physical_water else ""
		if not current_land.is_empty(): polity_id = _land_sovereign(current_land)
		controller.hover(polity_id, place_id)
		if clicked:
			_selected_land_context = current_land
			if _symbol_place_records.has(place_id) and not place_id.begins_with("administrative_region:"):
				var reference := (_symbol_place_records[place_id] as Dictionary).duplicate()
				var name := str(reference.get("display_name",reference.get("name","")))
				reference.merge({"place_id":place_id,"name":UILocale.name(reference) if name.is_empty() else name},true)
				if not reference.has("spatial_kind"): reference["spatial_kind"]="historical place reference"
				geographic_reference_selected.emit(reference)
			# A real place remains selectable when its legacy country reference has
			# no current polity crosswalk. Do not infer that mapping from a polygon.
			if polity_id.is_empty() and place_id.is_empty() and _unassigned_pick:
				var coordinate := RegionProjection.lon_lat(unit_at(point))
				place_id = "geographic_reference:physical_pick"
				geographic_reference_selected.emit({"place_id":place_id,"name":"海岸／岛屿地理参考","spatial_kind":"geographic_region","lon_lat":[coordinate.x,coordinate.y],"valid_from":"0001-01-01","valid_to":"9999-12-31","source_name_zh":"Natural Earth 物理陆地参考","source_reference":"https://www.naturalearthdata.com/","note_zh":"当前位置命中物理陆地，但当前正式土地记录未提供明确主权；历史参考与实际控制分别列示。" if not current_land.is_empty() else "当前位置命中已显示的物理陆地。现有历史政治几何未覆盖此处，政治归属未知；物理海岸不构成主权依据。"})
			_pointer_selection = true
			controller.select(polity_id, place_id)
			_pointer_selection = false
			current_politics_changed.emit(false)
			var canonical := FormalEconomicMapObservation.canonical_place(place_id)
			if _topic_hits.has(canonical):
				topic_selected.emit(canonical,str((_topic_hits[canonical] as Dictionary).get("subject_id","")))
	accept_event()

func _stabilize_local_anchor(unit: Vector3, pixel: Vector2) -> void:
	var camera := controller.region_camera
	if not camera.local_active or unit.is_zero_approx(): return
	var actual := region_view.chart_screen_point(unit,camera)
	var correction := pixel-actual
	if correction.length_squared()>0.0001:
		camera.pan(correction,size)
		controller.view_changed.emit()

func _return_to_region() -> void:
	if controller==null: return
	var camera := controller.region_camera
	if not camera.local_active: return
	var observed: int = Time.get_ticks_usec() if observation_profile else 0
	if observation_profile: observation_return = {"requested_us": observed, "first_valid_frame_us": 0}
	controller.suspend_motion()
	var anchor := unit_at(size*.5)
	if observation_profile: observation_return["anchor_us"] = Time.get_ticks_usec() - observed
	camera.leave_local()
	camera.local_suppressed=true
	if not anchor.is_zero_approx(): camera.origin+=size*.5-camera.project(anchor)
	# Preserve chart, centre, bearing, selection and world state. REGION can
	# subsequently zoom out or explicitly locate another source.
	camera.fit_requested_scale(size,size*.5)
	if observation_profile: observation_return["fit_finished_us"] = Time.get_ticks_usec()
	controller.view_changed.emit()
	if observation_profile: observation_return["callback_us"] = Time.get_ticks_usec() - observed

func _locate_local_reference(ll: Vector2) -> void:
	_location_generation+=1
	var generation := _location_generation
	var catalogue_size := relief._assets.size()
	var unit := GlobeProjection.lon_lat_to_unit(ll)
	controller.focus_region(unit,size*.5,.18,0.0,size)
	# WORLD initially knows only its foundation. Let the existing catalogue
	# request complete, then honour this explicit location's scale once.
	if controller.region_camera.km_per_pixel<=.181: return
	var deadline := Time.get_ticks_msec()+15000
	while is_inside_tree() and generation==_location_generation and relief._assets.size()==catalogue_size and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if is_inside_tree() and generation==_location_generation and relief._assets.size()!=catalogue_size:
		controller.focus_region(unit,size*.5,.18,0.0,size)

func _camera_pose_valid(at_origin: Vector2, scale: float, angle: float, viewport_size: Vector2) -> bool:
	if controller==null: return true
	var camera := controller.region_camera
	var city_data := _city_source_profile()
	# A flat vector chart keeps its own geographic extent. Raster sampling
	# quality controls the displayed relief, not whether the user may pan or
	# leave that raster's footprint. Fine 3D admission is checked below.
	if not camera.local_active: return true
	# The city is a map presentation, not fine 3D terrain. Its qualified pose
	# selects CITY in _evaluate_scale; moving out hands back to REGION.
	if city_data.has("presentation_index"): return true
	if camera.local_active and not city_data.is_empty() and scale<.1:
		var valid := CityOverview.pose_valid(city_data,camera,at_origin,scale,angle,_city_safe_rect(),region_view.elevation_for_scale(camera,scale*1000.0),viewport_size)
		if not valid: observation_camera_rejection={"reason":"CITY_FOOTPRINT","mpp":scale*1000.0}
		return valid
	var regions: Array[Dictionary]=[]
	var content_reference: LocalSpatialContent
	if local_content!=null: content_reference=local_content.content
	if content_reference!=null and content_reference.display_active_on(political.display_date): regions=content_reference.observation_regions()
	# An oblique terrain ray can meet any height in the displayed source.
	# REGION's flat chart is exactly the zero-height case. Orthographic ground
	# compensation is the same as RegionView._chart_transform, including yaw.
	var heights: Array[float]=[0.0]
	if camera.local_active and content_reference!=null and not content_reference.surface_reference.is_empty():
		var d := content_reference.surface_reference
		var base := float(d.height_rows_m[int(d.height)/2][int(d.width)/2])
		var low := float(d.height_min_m)-base;var high := float(d.height_max_m)-base
		if (d.get("presentation",{}) as Dictionary).has("context_height_asset"):
			low=minf(low,-base);high=maxf(high,5000.0-base) # documented log-height range
		if region_view._local_surface_key==str(d.content_path) and not region_view._surface_display_heights.is_empty():
			low=region_view._surface_ground_range.x;high=region_view._surface_ground_range.y
		var elevation := region_view.elevation_for_scale(camera,scale*1000.0)
		heights=[low*cos(elevation)*.001,high*cos(elevation)*.001]
	var axes := RegionProjection.screen_axes(angle)
	var ground := PackedVector2Array()
	for height: float in heights:
		for corner: Vector2 in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
			ground.append(axes.basis_xform_inv((corner-at_origin)*scale+Vector2(0,height)))
	var hull := Geometry2D.convex_hull(ground)
	var footprint := PackedVector2Array()
	var centre_ll := RegionProjection.lon_lat(RegionProjection.inverse(axes.basis_xform_inv((viewport_size*.5-at_origin)*scale),camera.tangent_frame))
	for index: int in range(hull.size()-1):
		for sample: int in range(5):
			var ll := RegionProjection.lon_lat(RegionProjection.inverse(hull[index].lerp(hull[index+1],float(sample)/5.0),camera.tangent_frame))
			ll.x+=360.0*roundf((centre_ll.x-ll.x)/360.0)
			footprint.append(ll)
	if not relief.supports_footprint(footprint,scale*1000.0,regions):
		observation_camera_rejection={"reason":"RELIEF_COVERAGE","mpp":scale*1000.0}
		return false
	if scale>=RegionCamera.LOCAL_EXIT_KM_PER_PIXEL: return true
	# A finer REGION colour page cannot qualify the coarser 3D height mesh
	# drawn over it. Qualify every visible context portion against that mesh's
	# own output spacing, except where an admitted fine survey replaces it.
	var shift := Transform2D(0.0,-centre_ll)
	for region: Dictionary in regions:
		if str(region.grade)!="generalized" or scale*1000.0+0.001>=float(region.minimum_mpp): continue
		var remaining: Array[PackedVector2Array]=Geometry2D.intersect_polygons(shift*footprint,shift*(region.polygon as PackedVector2Array))
		for fine: Dictionary in regions:
			if str(fine.grade)!="survey" or scale*1000.0<float(fine.minimum_mpp): continue
			var holes: Array[PackedVector2Array]=[shift*(fine.polygon as PackedVector2Array)]
			remaining=GlobeProjection.subtract_holes(remaining,holes)
		if remaining.any(func(piece: PackedVector2Array) -> bool: return absf(GlobeProjection.polygon_area(piece))>0.000000001): return false
	# The qualifying native patch must remain under the central ground rays.
	# Outer pixels may use REGION only when that same scale qualifies there.
	# In a narrow survey, this admits an honest overview, never fine 3D outside
	# its polygon. At deep scales the entire footprint must fit fine coverage.
	for height: float in heights:
		var centre := axes.basis_xform_inv((viewport_size*.5-at_origin)*scale+Vector2(0,height))
		var inside := false
		for region: Dictionary in regions:
			if scale*1000.0+0.001<float(region.minimum_mpp): continue
			var polygon := PackedVector2Array()
			for ll: Vector2 in region.polygon as PackedVector2Array: polygon.append(RegionProjection.forward(GlobeProjection.lon_lat_to_unit(ll),camera.tangent_frame))
			if not Geometry2D.is_point_in_polygon(centre,polygon): continue
			var clearance := INF
			for index: int in range(polygon.size()): clearance=minf(clearance,centre.distance_to(Geometry2D.get_closest_point_to_segment(centre,polygon[index],polygon[(index+1)%polygon.size()])))
			# Up to 32 pixels, bounded by two real output samples. Zooming out
			# must not inflate the safety collar until it traps the whole source.
			if clearance>=minf(scale*32.0,float(region.minimum_mpp)*LocalSpatialContent.OUTPUT_SAMPLE_PIXELS*.002): inside=true;break
		if not inside: return false
	return true

func _draw_local_data_boundary() -> void:
	var camera := controller.region_camera
	if not _city_source_profile().is_empty(): return
	if local_content==null or local_content.content==null: return
	for region: Dictionary in local_content.content.observation_regions():
		var ring := PackedVector2Array()
		var polygon := region.polygon as PackedVector2Array
		for index: int in range(polygon.size()):
			for sample: int in range(8):
				var ll := polygon[index].lerp(polygon[(index+1)%polygon.size()],float(sample)/8.0)
				ring.append(region_view.chart_screen_point(GlobeProjection.lon_lat_to_unit(ll),camera))
		if ring.is_empty(): continue
		ring.append(ring[0])
		draw_polyline(ring,Color(0.84,0.74,0.47,0.62 if str(region.grade)=="generalized" else 0.35),1.0,true)

func _polity_at(point: Vector2) -> String:
	_unassigned_pick = false
	var camera := controller.region_camera
	var unit := unit_at(point)
	if unit.is_zero_approx(): return ""
	var current_id := _current_land_at(unit)
	if not current_id.is_empty():
		var sovereign := _land_sovereign(current_id)
		_unassigned_pick = sovereign.is_empty()
		return sovereign
	var chart_point := camera.project(unit) if camera.local_active else point
	var basis := controller.orientation()
	var queried := political.query_at(unit)
	if bool(queried.found):
		_unassigned_pick = str(queried.owner).is_empty()
		return _picked_political_identity(str(queried.owner))
	# Physical land outside historical coverage has unknown political identity.
	var physical := strategic_layer.physical_land_at(chart_point,camera,{"basis":basis,"center":_center,"radius":_radius})
	if physical:
		_unassigned_pick = true
		return ""
	var nearest := political.query_edge(chart_point,camera,basis,_center,_radius,unit)
	if not nearest.is_empty(): return _picked_political_identity(nearest)
	_unassigned_pick = physical
	return ""

func _picked_political_identity(owner: String) -> String:
	var runtime_id := str((political.records.get(owner,{}) as Dictionary).get("runtime_entity_id",""))
	# Supplementary historical ranges deliberately have no simulation entity.
	# Their visible surface still selects its own sourced presentation record.
	return runtime_id if not runtime_id.is_empty() and _political_view.has_entity(runtime_id) else owner

func _place_at(point: Vector2) -> String:
	if controller.map_mode=="economic":
		for hit: Dictionary in _logistics_hits:
			if hit.has("place_id") and (hit.rect as Rect2).has_point(point): return str(hit.place_id)
	if controller.region_camera.active:
		for id: String in region_view.landmark_screen_bounds:
			if region_view.landmark_visible(id) and (region_view.landmark_screen_bounds[id] as Rect2).has_point(point): return id
		var settlement := region_view.settlement_at(point)
		if not settlement.is_empty(): return settlement
	for id: String in _symbol_hits:
		if (_symbol_hits[id] as Rect2).has_point(point): return id
	return ""

func _display_place(id: String) -> Dictionary:
	var place := local_layer.place(id)
	if place.is_empty(): place = strategic_layer.place(id)
	if place.is_empty(): place = political.places.get(id,{}) as Dictionary
	if place.is_empty(): place = _symbol_place_records.get(id,{}) as Dictionary
	return place

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

func focus_internal_landmark(id: String) -> bool:
	for source: Dictionary in LocalSpatialLoader.internal_landmark_sources():
		if str(source.anchor_id)!=id: continue
		var unit := GlobeProjection.lon_lat_to_unit(source.anchor as Vector2)
		_transition_elapsed = -1.0
		_container.modulate.a = 1.0
		region_view.container.modulate.a = 1.0
		controller.suspend_motion()
		controller.focus_region(unit,size*0.5,0.003,0.0,size)
		controller.enter_local(unit,size*0.5,size,id,2.0)
		controller.select(_political_view.runtime_id_for_source(str(source.parent_country_id)),id)
		controller.view_changed.emit()
		return true
	return false

func set_internal_load_test(active: bool) -> void:
	region_view.set_internal_load_test(active)
	_invalidate_spatial_display()

func country_observation(polity_id: String, available: Vector2) -> Dictionary:
	var anchor: Vector3=political.anchors.get(polity_id,Vector3.ZERO)
	var scale := .05
	var best := Rect2()
	var best_ring := PackedVector2Array()
	var best_area := -1.0
	var feature := str(political.boundary_features.get(polity_id,""))
	for part: Dictionary in content.parts(feature):
		var ring: PackedVector2Array=part.outer
		if ring.is_empty(): continue
		ring=GlobeProjection.unwrap_ring(ring,ring[0].x)
		var bounds := GlobeProjection.lon_lat_bounds([ring])
		var area := absf(GlobeProjection.polygon_area(ring))*maxf(.01,cos(deg_to_rad(bounds.get_center().y)))
		if area>best_area: best=bounds;best_ring=ring;best_area=area
	if best.has_area():
		anchor=GlobeProjection.lon_lat_to_unit(best.get_center())
		var frame := RegionProjection.frame(best.get_center())
		var projected := Rect2()
		var first := true
		for ll: Vector2 in best_ring:
			var km := RegionProjection.forward(GlobeProjection.lon_lat_to_unit(ll),frame)
			projected=Rect2(km,Vector2.ZERO) if first else projected.expand(km);first=false
		scale=maxf(projected.size.x/maxf(180,available.x),projected.size.y/maxf(240,available.y))*1.16
	return {"anchor":anchor,"scale":maxf(.008,scale)}

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
	var target := country_observation(controller.selected_polity_id,size-Vector2(80,180))
	controller.focus_market_view(target.anchor as Vector3,size*.5,float(target.scale),size,_evaluate_scale)

func _on_mouse_exited() -> void:
	if controller != null:
		controller.suspend_motion()
		controller.hover("", "")
	_last_pointer = Vector2(-1.0, -1.0)

func _dump_terrain_point(pixel: Vector2) -> void:
	# Read one completed frame only after an explicit diagnostic click. This
	# bridges bound inputs and the displayed colour without guessing GPU Mips.
	queue_redraw()
	await RenderingServer.frame_post_draw
	var unit := unit_at(pixel)
	if unit.is_zero_approx(): return
	var camera := controller.region_camera
	var mpp := _strategic_mpp()
	var batch := {}
	var unique_land: Array[Dictionary] = []
	var visible_land := 0
	var binding_mismatches := 0
	for layer: LocalSpatialLayer in [_world_layer,_region_layer]:
		for value: Dictionary in layer._batches+layer._fallback_batches:
			if str(value.kind)!="land_reference" or not bool(value.get("visible",false)): continue
			visible_land += 1
			if batch.is_empty(): batch=value
			elif batch.get("surface_reference")!=value.get("surface_reference"): binding_mismatches+=1
			if not unique_land.any(func(other: Dictionary) -> bool: return other.get("surface_reference")==value.get("surface_reference")):
				unique_land.append(value)
	var consumers: Array = []
	var context := {"capture":"explicit Ctrl+Alt+click; actual installed material parameters","screen_xy":TerrainPixelSource.serial(pixel),"viewport":TerrainPixelSource.serial(size),"camera_center":TerrainPixelSource.serial(RegionProjection.lon_lat(camera.tangent_frame.z)) if camera.active else [],"bearing":camera.bearing if camera.active else 0.0,"regional":camera.active,"local":camera.local_active,"map_mode":controller.map_mode,"visible_land_batches":visible_land,"different_land_bindings":binding_mismatches,"geometry":{"world":_world_layer.diagnostic_state(),"region":_region_layer.diagnostic_state(),"local":local_layer.diagnostic_state()},"relief_wanted":relief._surface_wanted,"relief_active":relief._surface_active,"relief_inflight":relief._level if relief.preparing() else "","relief_errors":relief.errors,"native_local":TerrainPixelSource.serial(region_view.coverage_description(camera)) if camera.active else {}}
	context["chart_center"] = context.camera_center
	context["chart_origin"] = TerrainPixelSource.serial(camera.origin) if camera.active else []
	var centre_unit := unit_at(size*.5)
	context["camera_center"] = TerrainPixelSource.serial(RegionProjection.lon_lat(centre_unit)) if not centre_unit.is_zero_approx() else []
	context["surface_view_bounds"] = [relief._surface_view.position.x,relief._surface_view.position.y,relief._surface_view.end.x,relief._surface_view.end.y]
	var frame := get_viewport().get_texture().get_image()
	if frame!=null and not frame.is_empty():
		var viewport_point := get_global_transform_with_canvas()*pixel
		var uv := viewport_point/get_viewport().get_visible_rect().size
		var xy := Vector2i((uv*Vector2(frame.get_size())).floor()).clamp(Vector2i.ZERO,frame.get_size()-Vector2i.ONE)
		context["framebuffer"] = {"frame":Engine.get_frames_drawn(),"viewport_point":TerrainPixelSource.serial(viewport_point),"image_size":TerrainPixelSource.serial(Vector2(frame.get_size())),"image_pixel":[xy.x,xy.y],"rgba":TerrainPixelSource.serial(frame.get_pixelv(xy)),"includes":"Actual completed viewport colour including political ink, map grading and native overlays; not a GPU Mip measurement"}
		var crop := Rect2i(xy-Vector2i(16,16),Vector2i(33,33)).intersection(Rect2i(Vector2i.ZERO,frame.get_size()))
		frame.get_region(crop).save_png("user://r57_terrain_pixel.png")
	if unique_land.is_empty(): consumers.append(TerrainPixelSource.inspect(relief,batch,RegionProjection.lon_lat(unit),mpp,context))
	for installed: Dictionary in unique_land:
		consumers.append(TerrainPixelSource.inspect(relief,installed,RegionProjection.lon_lat(unit),mpp,context.merged({"consumer":"visible physical land shared terrain binding","representative_source_feature":installed.get("source_feature_id",""),"political_note":"Terrain binding shared by this group; political ink varies by component. Final viewport pixel is recorded separately."},true)))
	if camera.local_active and region_view._surface_material!=null:
		consumers.append(TerrainPixelSource.inspect(relief,region_view._surface_texture_batch,RegionProjection.lon_lat(unit),mpp,context.merged({"consumer":"native LOCAL terrain material"},true)))
	var path := "user://r57_terrain_point.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		push_error("R57 point output unavailable: "+error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(TerrainPixelSource.serial(consumers),"\t")); file.close()
	print("R57 terrain point: ",ProjectSettings.globalize_path(path))

func unit_at(pixel: Vector2) -> Vector3:
	_ensure_camera()
	if controller.region_camera.local_active:
		var terrain := region_view.surface_unit_at(pixel,controller.region_camera,size)
		if not terrain.is_zero_approx(): return terrain
	return controller.region_camera.unit_at(pixel) if controller.region_camera.active else RegionProjection.world_unit(pixel, _center, _radius, controller.orientation())

func screen_point(unit: Vector3) -> Vector2:
	_ensure_camera()
	if controller.region_camera.local_active:
		var terrain := region_view.surface_screen_point(unit,controller.region_camera)
		if is_finite(terrain.x): return terrain
	return controller.region_camera.project(unit) if controller.region_camera.active else GlobeProjection.sphere_screen(controller.orientation() * unit, _center, _radius)

func _set_region_uniforms(batch: Dictionary) -> void:
	var camera := controller.region_camera
	_parameter(batch, "globe_basis", camera.tangent_frame.transposed())
	_parameter(batch, "globe_center", camera.origin)
	_parameter(batch, "region_km_per_pixel", camera.km_per_pixel)
	_parameter(batch, "region_bearing", Vector2(cos(camera.bearing), sin(camera.bearing)))
	if batch.has("kind"): local_chart_uniforms(batch,local_layer.local_coverage)

func _evaluate_scale() -> void:
	var changed := controller.update_observation_mode(size,_center,minf(size.y/2.55,size.x*0.49))
	if changed:
		_region_labels_dirty = true
		_begin_transition(controller.region_camera.active)
	var camera := controller.region_camera
	if not camera.active: return
	var city_data := _city_source_profile()
	if camera.local_active:
		if city_data.has("presentation_index"):
			if not CityOverview.pose_valid(city_data,camera,camera.origin,camera.km_per_pixel,camera.bearing,_city_safe_rect(),region_view.elevation_at(camera),size): controller.leave_local()
		elif camera.km_per_pixel>=RegionCamera.LOCAL_EXIT_KM_PER_PIXEL: controller.leave_local()
		return
	if camera.km_per_pixel>=RegionCamera.LOCAL_EXIT_KM_PER_PIXEL: camera.local_suppressed=false
	var unit := camera.valid_anchor(size).unit as Vector3
	if camera.scale_at(unit)>RegionCamera.LOCAL_ENTER_KM_PER_PIXEL or not region_view.ready: return
	if local_content==null or local_content.content==null or not local_content.content.covers(RegionProjection.lon_lat(unit)) or not local_content.content.display_active_on(political.display_date): return
	if not bool(local_content.content.metadata.get("local_enabled",true)): return
	if city_data.get("ground_mode","")=="cartographic_plane":
		# A flat sourced city display uses its own acquired coverage, not a
		# separate landmark DEM patch. This admits neither terrain nor entities.
		var b: Array=city_data.content_bounds
		var area := Rect2(Vector2(float(b[0]),float(b[1])),Vector2(float(b[2])-float(b[0]),float(b[3])-float(b[1])))
		camera.local_regions=[{"polygon":LocalSpatialContent._bounds_polygon(area),"minimum_mpp":float(city_data.minimum_mpp),"grade":"generalized"}]
	else:
		if not is_finite(local_content.content.minimum_observation_mpp(RegionProjection.lon_lat(unit),political.display_date)): return
		camera.local_regions=local_content.content.observation_regions()
	if camera.local_regions.is_empty(): return
	var anchor := city_data.get("anchor",local_content.content.metadata.get("anchor_lon_lat",[])) as Array
	var anchor_unit := GlobeProjection.lon_lat_to_unit(Vector2(float(anchor[0]),float(anchor[1])))
	if city_data.has("presentation_index") and not CityOverview.pose_valid(city_data,camera,camera.origin,camera.km_per_pixel,camera.bearing,_city_safe_rect(),region_view.elevation_at(camera),size): return
	controller.enter_local(anchor_unit,camera.project(anchor_unit),size,str(city_data.get("place_id",local_content.content.metadata.anchor_place_id)),float(city_data.get("minimum_mpp",local_content.content.metadata.get("local_min_mpp",25.0))))

func _sync_local_resources() -> void:
	if local_content == null:
		return
	var camera := controller.region_camera
	var center_unit := camera.unit_at(size*0.5) if camera.active else unit_at(size*0.5)
	var request_unit := center_unit
	var retained_city := _city_source_profile()
	if camera.local_active and retained_city.has("presentation_index"):
		var anchor: Array=retained_city.anchor
		request_unit=GlobeProjection.lon_lat_to_unit(Vector2(float(anchor[0]),float(anchor[1])))
	elif camera.active and (center_unit.is_zero_approx() or not LocalSpatialLoader.covers(RegionProjection.lon_lat(center_unit))):
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
	if local_content.content.errors.is_empty() and camera.local_active and camera.local_place_id!=str(local_content.content.metadata.anchor_place_id) and _city_source_profile().is_empty():
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

func _sync_landmark_display() -> bool:
	var observed: int = Time.get_ticks_usec() if observation_profile else 0
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
			var anchor := local_layer.place(str(visual.anchor_place_id))
			var transport_anchor := not anchor.is_empty() and str(anchor.get("display_kind",""))=="transport_node" and str(anchor.id)==id and str(visual.get("local_anchor_id",""))==str(local_content.content.metadata.anchor_place_id)
			# The menu may inspect a provenance-admitted display anchor without
			# constructing a formal world place or granting an actor visibility.
			var inspection_anchor := inspection_preview and spatial_world==null and not anchor.is_empty()
			if not geographic_anchor and not transport_anchor and not inspection_anchor and (spatial_world==null or spatial_world.get_place(str(visual.anchor_place_id)).is_empty()):
				_place_points.erase(id)
				continue
			_place_points[id] = point
			visuals.append(visual)
	var surface := local_content.content.surface_reference if visible and local_content!=null and local_content.content!=null and controller.region_camera.local_place_id==str(local_content.content.metadata.anchor_place_id) else {}
	var lines: Array[Dictionary] = []
	if not surface.is_empty() and local_content.content.active_on(political.display_date): lines.assign(local_content.content.features)
	var settlements: Array[Dictionary] = []
	if not surface.is_empty(): settlements = local_content.content.settlement_visuals(political.display_date)
	var covers: Array[Dictionary] = []
	if not surface.is_empty(): covers = local_content.content.surface_covers
	region_view.city_profile = _city_source_profile() if _city_display_active() else {}
	region_view.city_profiles = CityOverview.visible_profiles(controller.region_camera,size) if visible else []
	if _city_sample_grade>0 and not region_view.city_profile.is_empty(): region_view.city_profile=CityOverview.sample(region_view.city_profile,_city_sample_grade)
	if _city_sample_grade>0 and not region_view.city_profile.is_empty(): region_view.city_profiles=[region_view.city_profile]
	if observation_profile: observation_costs["landmark_demand_us"]=Time.get_ticks_usec()-observed; observed=Time.get_ticks_usec()
	region_view.update_landmarks(visuals,controller.region_camera,size,surface,lines,settlements,covers)
	if observation_profile: observation_costs["landmark_scene_us"]=Time.get_ticks_usec()-observed; observed=Time.get_ticks_usec()
	region_view.set_map_style(_local_ground_style())
	region_view.set_surface_reference(relief.surface_description(_strategic_mpp()))
	var coverage_changed := _sync_local_coverage()
	if observation_profile: observation_costs["landmark_coverage_us"]=Time.get_ticks_usec()-observed
	if controller.region_camera.local_active:
		for id: String in _place_points:
			var place := _display_place(id)
			var raw := (place.get("geometry",{}) as Dictionary).get("coordinates",place.get("lon_lat",[])) as Array
			if raw.size()!=2 or typeof(raw[0]) not in [TYPE_INT,TYPE_FLOAT]: continue
			var point := region_view.surface_screen_point(GlobeProjection.lon_lat_to_unit(Vector2(float(raw[0]),float(raw[1]))),controller.region_camera)
			if is_finite(point.x): _place_points[id] = point
	if region_view.landmark_preparing(): set_process(visible)
	return coverage_changed

func _sync_local_coverage() -> bool:
	var coverage := region_view.coverage_description(controller.region_camera) if visible else {}
	# Layer retirement may already have cleared its own description. Compare
	# resource IDs and values, not a layer's mutable dictionary, so old shader
	# sampler references are cleared even during asynchronous shard handoff.
	var signature: Array = []
	if not coverage.is_empty():
		signature = [coverage.bounds,coverage.edge,(coverage.water as Texture2D).get_instance_id() if coverage.water!=null else 0,(coverage.height as Texture2D).get_instance_id() if coverage.height!=null else 0,coverage.strength,coverage.vertical_pixels,coverage.local_lines,coverage.get("city_overview",false),coverage.get("water_owner",false),coverage.get("line_bounds",Vector4.ZERO),coverage.get("secondary_bounds",Vector4.ZERO)]
	var changed := _local_coverage_signature!=signature
	var held_textures := _local_coverage_signature.size()>3 and (int(_local_coverage_signature[2])!=0 or int(_local_coverage_signature[3])!=0)
	_local_coverage_signature = signature
	if changed:
		local_layer.set_local_coverage(coverage)
		# Keep physical land active; only the covered river symbols hand over.
		for layer: LocalSpatialLayer in [_world_layer,_region_layer]: layer.set_local_coverage(coverage)
		# Visible annotation batches receive the current chart in their normal
		# draw below. Visit hidden annotations only to release actual old samplers.
		if held_textures:
			for batch: Dictionary in _boundary_batches: local_chart_uniforms(batch,coverage)
			for batches: Array in _overlay_batches.values():
				for batch: Dictionary in batches: local_chart_uniforms(batch,coverage)
	return changed

func _on_local_frame_ready() -> void:
	# A newly presented terrain frame needs a chart-mask update, not another
	# political/administrative appearance pass or content request.
	if controller!=null: _sync_local_coverage()
	_invalidate_spatial_display()

func _local_ground_style() -> Dictionary:
	var shade := MapScaleStyle.relief_weight(_strategic_mpp(),controller.map_mode)
	var neutral := {"tone":Color(0.42,0.50,0.46),"weight":0.0,"relief":shade}
	if controller.map_mode in ["geographic","military"]: return neutral
	if local_content==null or local_content.content==null: return neutral
	var source := ""
	var anchor := str(local_content.content.metadata.anchor_place_id)
	for feature: Dictionary in local_content.content.features:
		if str(feature.id)==anchor:
			source = str(feature.get("parent_country_id",""))
			break
	if source.is_empty():
		for visual: Dictionary in local_content.content.landmark_visuals():
			if str(visual.anchor_place_id)==anchor:
				source = str(visual.get("parent_country_id",""))
				break
	var owner := _political_view.runtime_id_for_source(source) if _political_view!=null else ""
	# A single LOCAL material cannot portray two distinct current sovereignties.
	# Keep its physical terrain instead of covering the new map with old ink.
	var surface := local_content.content.surface_reference
	if not surface.is_empty():
		var step := float(surface.step_degrees)
		var bounds := Rect2(Vector2(float(surface.west_cell_centre),float(surface.north_cell_centre)-(int(surface.height)-1)*step),Vector2(int(surface.width)-1,int(surface.height)-1)*step)
		for id: String in strategic_layer.political_cells_installed():
			if _current_cells.has(id) and bounds.intersects(_current_cells[id].bounds as Rect2,true) and str((_current_land_rows.get(id,{}) as Dictionary).get("sovereign",""))!=owner:
				return {"tone":neutral.tone,"weight":0.0,"relief":shade}
	var batch := _political_ink.get(owner,{}) as Dictionary
	var values := batch.get("parameters",{}) as Dictionary
	if values.is_empty(): return neutral
	var base := values.get("political_base_color",Vector3(0.42,0.50,0.46)) as Vector3
	var tone := Color(base.x,base.y,base.z)
	if bool(values.get("political_focus_style",false)):
		var emphasis := float(values.get("political_emphasis",0.7))
		var luminance := tone.r*0.2126+tone.g*0.7152+tone.b*0.0722
		tone = Color(luminance,luminance,luminance).lerp(tone,lerpf(0.32,0.86,emphasis))*lerpf(0.86,1.04,emphasis)
	return {"tone":tone,"weight":float(values.get("political_weight",0.42)),"relief":shade}

func _sync_strategic_resources() -> void:
	if strategic_content==null or controller==null or not visible: return
	if not strategic_content.content_changed.is_connected(_on_strategic_content_changed): strategic_content.content_changed.connect(_on_strategic_content_changed)
	var camera := controller.region_camera
	var base_ready := _world_layer.can_present_physical(strategic_content.physical_demand("coarse"),4500.0,"coarse")
	var needs_medium := camera.active and _strategic_mpp()<=StrategicSpatialLoader.MEDIUM_LOD_MPP
	if base_ready and not needs_medium:
		# The global slot owns its immutable content after the single loader
		# moves on. Returning WORLD cancels only the regional reader.
		if strategic_content.preparing() or strategic_content.content!=null and strategic_content.content!=_world_layer.content_reference(): strategic_content.release()
		_strategic_waiting = false
		return
	var mpp := _strategic_mpp() if base_ready else 4500.0
	var unit := camera.valid_anchor(size).unit as Vector3 if camera.active else controller.orientation().transposed()*Vector3.BACK
	var target := _region_layer if base_ready else _world_layer
	if not strategic_content.request(RegionProjection.lon_lat(unit),_strategic_radius_km(),political.display_date,mpp,not _political_ink.is_empty(),target.physical_reference()):
		_strategic_failure = "\n".join(strategic_content.errors) if not strategic_content.errors.is_empty() else "缺少物理地图描述。"
		map_notice.emit(_strategic_failure)
		return
	if not strategic_content.failure.is_empty():
		if _strategic_failure!=strategic_content.failure: map_notice.emit(strategic_content.failure)
		_strategic_failure = strategic_content.failure
		return
	if target==_region_layer:
		var wanted := strategic_content.physical_demand("medium")
		var previous: Array = target.physical_reference().get("regions",[])
		if not previous.is_empty() and not wanted.any(func(id: String) -> bool: return id in previous):
			target.clear()
		else: target.discard_uncovered_preparation(wanted)
	_strategic_failure = ""
	if strategic_content.preparing() and not _strategic_waiting:
		_strategic_waiting = true
		map_notice.emit("正在准备区域细节；全球基础继续跟随相机。" if base_ready else "正在安装全球基础地图。")
	var prepared := strategic_content.content
	if prepared!=null and prepared!=target.content_reference() and prepared.errors.is_empty():
		for warning: String in prepared.metadata.get("optional_errors",[]) as Array: map_notice.emit("可选图层未加载："+warning)
		target.rail_style = 3
		if not target.install_political_content(prepared,_physical_ink_frames(),_current_cells): target.begin(prepared,region_view.map_canvas,mpp,_physical_ink_frames(),_current_cells)
	if prepared!=null and prepared.errors.is_empty(): target.request_lods(mpp)
	if strategic_content.preparing() or target.preparing: set_process(visible)

func _strategic_radius_km() -> float:
	var camera := controller.region_camera
	var anchor := camera.valid_anchor(size).pixel as Vector2 if camera.active else _center
	var farthest := 0.0
	for corner: Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
		farthest = maxf(farthest,anchor.distance_to(corner)+8.0)
	# WORLD is orthographic: screen distance is a chord, not an arc. A
	# complete visible hemisphere reaches pi/2, beyond the former 9000-km cap.
	return farthest*camera.km_per_pixel if camera.active else asin(clampf(farthest/maxf(_radius,1.0),0.0,1.0))*RegionProjection.EARTH_RADIUS_KM

func note_topic_query(kind: String) -> void:
	if _terrain_probe_enabled: _terrain_probe_counts[kind] = int(_terrain_probe_counts.get(kind,0))+1

func current_view_map_status() -> Dictionary:
	# Poll status only; resource scheduling belongs to _process().
	if not _world_layer.physical_reference().is_empty() and not _map_canvas_dirty and not _view_dirty:
		var warnings: Array = _world_layer.content_reference().metadata.get("optional_errors",[]) as Array
		return {"state":"installed","message":"全球基础地图已安装","political_pending":false,"warnings":warnings,"diagnostic_counters":_terrain_probe_counts.duplicate()}
	var failure := _strategic_failure if not _strategic_failure.is_empty() else _world_layer.preparation_error
	if not failure.is_empty(): return {"state":"failed","message":failure}
	return {"state":"preparing","message":"正在安装全球基础陆地、海岸与国家着色"}

func _physical_demand_installed() -> bool:
	return not _world_layer.physical_reference().is_empty()

func _installed_view_lod() -> String:
	if strategic_content==null: return ""
	if controller.region_camera.active and _strategic_mpp()<=StrategicSpatialLoader.MEDIUM_LOD_MPP and _region_layer.can_reproject_physical(strategic_content.physical_demand("medium")): return "medium"
	return "coarse" if _physical_demand_installed() else ""

func _prepared_view_lod() -> String:
	if strategic_content==null: return ""
	if controller.region_camera.active and _strategic_mpp()<=StrategicSpatialLoader.MEDIUM_LOD_MPP and _region_layer.can_present_physical(strategic_content.physical_demand("medium"),_strategic_mpp(),"medium"): return "medium"
	return "coarse" if _world_layer.can_present_physical(strategic_content.physical_demand("coarse"),4500.0,"coarse") else ""

func _can_submit_map_view() -> bool:
	# This guards first initialization only, never an optional medium request.
	return _physical_demand_installed() or strategic_content!=null and _world_layer.can_present_physical(strategic_content.physical_demand("coarse"),4500.0,"coarse")

func _show_submitted_canvas(regional: bool) -> void:
	_container.visible = not regional
	region_view.container.visible = regional
	_container.modulate.a = 1.0
	region_view.container.modulate.a = 1.0

func _physical_ink_frames() -> Dictionary:
	if not _physical_frames.is_empty(): return _physical_frames
	var frames := _physical_frames
	for feature_id: String in _source_meshes:
		var source := _source_meshes[feature_id] as Dictionary
		frames[feature_id] = {"frame":source.uv_bounds,"flag":source.flag_bounds,"components":source.parts}
	for owner: String in political.region_frames:
		var frame := political.region_frames[owner] as Array
		frames[owner] = Rect2(Vector2(float(frame[0]),float(frame[1])),Vector2(float(frame[2])-float(frame[0]),float(frame[3])-float(frame[1])))
	return frames

func _strategic_mpp() -> float:
	return controller.region_camera.km_per_pixel*1000.0 if controller.region_camera.active else RegionProjection.EARTH_RADIUS_KM/maxf(_radius,1.0)*1000.0

func _update_strategic_layer(commit_canvas: bool = true, prepared_layer: LocalSpatialLayer = null) -> LocalSpatialLayer:
	var lod_name := _prepared_view_lod()
	if lod_name.is_empty(): lod_name = _installed_view_lod()
	var target := _region_layer if lod_name=="medium" else _world_layer
	# Cities add sourced geometry over the same physical base at every scale.
	target.reference_relief = relief.textures
	target.set_reference_window(_relief_description())
	target.suppressed_places = local_layer.visible_places
	var observed: int=Time.get_ticks_usec() if observation_profile else 0
	target.update(controller.region_camera,controller,political.display_date,size,commit_canvas,{"mpp":_strategic_mpp(),"city_overview":_city_display_active(),"center":_center,"radius":_radius,"canvas":_viewport.world_2d.canvas,"display_lod":lod_name,"install_physical":true,"observation_costs":observation_costs if observation_profile else {},"military_grid":_military_grid_style(),"ink_styles":_political_ink,"ink_revision":_ink_style_revision,"ownership_revision":_current_political_revision,"ink_owners":political._whole_owner_by_feature,"current_land_owners":_current_land_rows,"local_river_replacements":_local_river_replacements()},target!=prepared_layer or _view_dirty)
	if observation_profile: observation_costs["strategic_update_us"]=Time.get_ticks_usec()-observed;observed=Time.get_ticks_usec()
	if commit_canvas:
		strategic_layer = target
		(_world_layer if target==_region_layer else _region_layer).hide_display()
		if target==_world_layer and (not controller.region_camera.active or _strategic_mpp()>StrategicSpatialLoader.MEDIUM_LOD_MPP) and _region_layer.content_reference()!=null:
			_region_layer.clear() # The global image is submitted before local retirement.
	if observation_profile: observation_costs["strategic_retire_us"]=Time.get_ticks_usec()-observed
	return target

func _local_river_replacements() -> Dictionary:
	# This exact source pair was traced in the post-R46 audit. A completed
	# BD TOPAGE layer owns its sourced 300 km disc, not other rivers or canals.
	var content := local_layer.content_reference()
	if content==null or str(content.metadata.get("content_path",""))!=LocalSpatialLoader.PARIS_PATH or not content.active_on(political.display_date) or not local_layer.has_visible_kind("river"): return {}
	var anchor := content.metadata.anchor_lon_lat as Array
	var center := GlobeProjection.lon_lat_to_unit(Vector2(float(anchor[0]),float(anchor[1])))
	return {"river:seine":Vector4(center.x,center.y,center.z,cos(float(content.metadata.radius_km)/6371.0088))}

func _military_grid_style() -> Dictionary:
	if controller.map_mode!="military" or spatial_world==null: return {}
	var topology := spatial_world.land_topology()
	if topology==null:return {}
	var projection: Dictionary=topology._seed.projection
	var origin: Array=projection.origin_m
	# Only two metric levels. The 25 km grid subdivides each 50 km cell;
	# zoom changes visibility, never the geographic origin or cell dimensions.
	var mpp := _strategic_mpp()
	if _military_grid_step_m==50000 and mpp<700.0: _military_grid_step_m=25000
	elif _military_grid_step_m==25000 and mpp>900.0: _military_grid_step_m=50000
	return {"step":float(_military_grid_step_m),"projection":Vector4(topology._n,topology._af,topology._rho0,topology._eccentricity),"origin":Vector3(float(projection.x_0)-float(origin[0]),float(projection.y_0)-float(origin[1]),deg_to_rad(float(projection.lon_0)))}

func _label_exclusions() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if label_exclusions.is_valid(): result.assign(label_exclusions.call())
	return result

func _overlay_local_view() -> Rect2:
	var camera := controller.region_camera
	var topology := spatial_world.land_topology()
	var key: Array = [topology.get_instance_id(),camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,size]
	if key==_overlay_projection_key: return _overlay_projection
	_overlay_projection_key = key
	var bounds := Rect2()
	var first := true
	for ratio: Vector2 in [Vector2.ZERO,Vector2(0.5,0),Vector2(1,0),Vector2(0,0.5),Vector2(0.5,0.5),Vector2(1,0.5),Vector2(0,1),Vector2(0.5,1),Vector2.ONE]:
		var unit := camera.unit_at(size*ratio)
		if unit.is_zero_approx(): continue
		var point := topology.from_geographic(RegionProjection.lon_lat(unit))
		if first: bounds = Rect2(point,Vector2.ZERO); first = false
		else: bounds = bounds.expand(point)
	_overlay_projection = bounds
	return _overlay_projection

func _sync_overlay_resources() -> void:
	# CITY owns district presentation. Regional administrative detail resumes on exit.
	if _city_display_active(): return
	if spatial_world==null or spatial_world.land_topology()==null: return
	if not spatial_world.administrative_display_changed.is_connected(_on_administrative_display_changed): spatial_world.administrative_display_changed.connect(_on_administrative_display_changed)
	var camera := controller.region_camera
	var show := visible and camera.active
	var mpp := _strategic_mpp()
	var topology := spatial_world.land_topology()
	var revision := topology.display_revision()
	var coast_key := str(strategic_layer.physical_reference().get("key",""))
	var signature: Array = [spatial_world,controller.map_mode,revision,spatial_world.administrative_display_revision(),_boundary_source_revision,coast_key,_current_political_revision,strategic_layer.political_cells_installed(),controller.player_polity_id,show,camera.active,camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,size,controller.administrative_layer_active(),controller.selected_place_id,political.display_date]
	if signature==_overlay_request: return
	_overlay_request = signature
	var current_borders: Array[Dictionary] = []
	var observed: int = Time.get_ticks_usec() if observation_profile else 0
	if visible and (controller.administrative_map_active() or controller.map_mode=="economic"): current_borders = _current_border_rows()
	if observation_profile: observation_costs["overlay_borders_us"]=Time.get_ticks_usec()-observed; observed=Time.get_ticks_usec()
	var view := _overlay_local_view() if show else topology.coverage_bounds() if not current_borders.is_empty() else Rect2()
	var padded_view := view.grow(maxf(mpp*60.0,maxf(view.size.x,view.size.y)*0.15)) if camera.active and view.has_area() else view
	var bounded_window := not camera.active or _overlay_view.size.x<=padded_view.size.x*2.0 and _overlay_view.size.y<=padded_view.size.y*2.0
	var same_window := bounded_window and _overlay_view.encloses(view) and revision==_overlay_revision and _overlay_owner==spatial_world and coast_key==_overlay_coast_key
	var preparation_view := _overlay_view if same_window else padded_view
	var demand: Array[Dictionary] = []
	demand.assign(current_borders)
	var selected := controller.selected_place_id
	var query_id := selected if show and spatial_world.administrative_identity(selected).has("reference_descriptor") and not spatial_world.administrative_coverage_ready(selected) else ""
	var demand_key: Array = [spatial_world,controller.map_mode,revision,spatial_world.administrative_display_revision(),_boundary_source_revision,coast_key,_current_political_revision,strategic_layer.political_cells_installed(),controller.player_polity_id,show,camera.tangent_frame,mpp,controller.administrative_layer_active(),selected,political.display_date]
	if same_window and demand_key==_overlay_demand_key and query_id==_overlay_query_id:
		# A pan inside the installed padded window changes uniforms, not the
		# country's entire administrative query or an in-flight worker's demand.
		return
	_overlay_demand_key = demand_key
	if observation_profile: observation_costs["overlay_window_us"]=Time.get_ticks_usec()-observed; observed=Time.get_ticks_usec()
	for row: Dictionary in spatial_world.request_administrative_boundaries(preparation_view,political.display_date,mpp,show and controller.administrative_layer_active(),selected,controller.player_polity_id):
		row["kind"] = "administration"
		var shared_strokes := str(row.id).begins_with("administrative_region:france_") or str(row.id).begins_with("administrative_region:germany_")
		row["variant"] = "interior" if shared_strokes else "outline" if str(row.id)==selected else "interior"
		var capital := spatial_world.administrative_capital_symbol(str(row.id),political.display_date)
		if not capital.is_empty(): row["capital_symbol"] = capital
		demand.append(row)
	if observation_profile: observation_costs["overlay_demand_us"]=Time.get_ticks_usec()-observed
	# Keep one padded display window, including hidden layer batches, for toggles.
	var reuse_window := same_window
	_overlay_owner = spatial_world
	_overlay_coast_key = coast_key
	if demand==_overlay_demand and query_id==_overlay_query_id and reuse_window:
		return
	_overlay_generation = _overlay_preparation.invalidate()
	MapJobs.cancel_queued(_overlay_thread)
	_overlay_demand = demand
	_symbol_layout_dirty = true
	_overlay_query_id = query_id
	if not reuse_window: _overlay_view = preparation_view
	_overlay_revision = revision
	var retire_at: int=Time.get_ticks_usec() if observation_profile else 0
	_clear_overlay_installing()
	# Evict geometry only on a changed geographic window or topology; switching
	# a layer off leaves the bounded current window available for reuse.
	if not reuse_window:
		_clear_overlay_batches()
		spatial_world.retain_administrative_boundaries([])
	_retire_overlay_demand()
	if observation_profile: observation_costs["overlay_retire_us"]=Time.get_ticks_usec()-retire_at;retire_at=Time.get_ticks_usec()
	_start_overlay_prepare()
	if observation_profile: observation_costs["overlay_start_us"]=Time.get_ticks_usec()-retire_at

func _start_overlay_prepare() -> void:
	if not _overlay_retiring.is_empty(): set_process(visible);return
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
	var physical_water: Array[Dictionary] = []
	physical_water.assign(strategic_layer.physical_reference().get("water",[]) as Array)
	var work := _overlay_preparation.prepare.bind(missing,query,spatial_world.land_topology(),_overlay_view,_overlay_revision,_overlay_generation,physical_water)
	_overlay_thread = MapJobs.submit(work,"administrative geometry and query",MapJobs.VISIBLE,_overlay_preparation)
	_overlay_thread_owner = spatial_world if _overlay_thread!=null else null
	set_process(visible)

func _poll_overlay_prepare() -> void:
	if not _overlay_retiring.is_empty():
		_drain_overlay_retirement()
		if not _overlay_retiring.is_empty(): return
		_start_overlay_prepare()
	if _overlay_thread!=null and _overlay_thread.completed:
		var result: Variant = _overlay_thread.take()
		_overlay_thread = null
		var same_world := _overlay_thread_owner==spatial_world
		_overlay_thread_owner = null
		if same_world and result is Dictionary and int(result.generation)==_overlay_generation:
			_overlay_uploads.assign(result.uploads)
			_overlay_upload_owner = spatial_world
			if not str(result.get("query","")).is_empty():
				spatial_world.install_administrative_coverage(str(result.query),result.overlaps,int(result.revision))
				_overlay_query_id = ""
				place_content_ready.emit()
		elif same_world:
			if result is Dictionary: _overlay_retiring.append_array(result.get("uploads",[]) as Array)
			_start_overlay_prepare()
		else:
			_clear_overlay_installing()
			_overlay_request.clear()
			_invalidate_projection()
	if _overlay_uploads.is_empty(): return
	if _overlay_upload_owner!=spatial_world:
		_clear_overlay_installing()
		_overlay_request.clear()
		_invalidate_projection()
		return
	var started := Time.get_ticks_usec()
	var changed := false
	while not _overlay_uploads.is_empty():
		var row := _overlay_uploads.front() as Dictionary
		var bytes := FrameBudget.packed_bytes(row.encoded)
		if not _map_budget.claim_upload(bytes): break
		var began := Time.get_ticks_usec()
		changed = _install_overlay_row(_overlay_uploads.pop_front() as Dictionary) or changed
		_map_budget.finish_upload(began,"administrative geometry")
		if Time.get_ticks_usec()-started>=2000: break
	if changed:
		# These are annotation/picking changes. Physical surfaces, relief and
		# models have not changed and must not be resubmitted for every unit.
		_administrative_display_dirty = true
		queue_redraw()
	if _overlay_uploads.is_empty(): _overlay_upload_owner = null

func _install_overlay_row(row: Dictionary) -> bool:
	var geometry := GlobeBoundaryBatch.new()
	geometry.upload(row.encoded)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/presentation/map/globe_boundary.gdshader")
	material.set_shader_parameter("line_data",geometry.data)
	material.set_shader_parameter("miter_limit",1.5)
	material.set_shader_parameter("stroke_feather",0.55)
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item,region_view.annotation_canvas)
	RenderingServer.canvas_item_set_draw_index(item,LocalSpatialLayer.DRAW_ORDER+3)
	RenderingServer.canvas_item_set_material(item,material.get_rid())
	RenderingServer.canvas_item_set_visible(item,false)
	if geometry.segment_count>0: RenderingServer.canvas_item_add_mesh(item,geometry.mesh.get_rid())
	var id := str(row.id)
	if not _overlay_installing.has(id): _overlay_installing[id] = []
	_overlay_installing[id].append({"id":id,"kind":row.kind,"level":row.get("level",1),"lod":row.lod,"variant":row.get("variant",""),"geometry":geometry,"material":material,"item":item,"owners":row.get("owners",[]),"cull_axis":row.encoded.get("cull_axis",Vector3.ZERO),"cull_angle":row.encoded.get("cull_angle",PI)})
	if bool(row.last):
		if _overlay_batches.has(id):
			for previous: Dictionary in _overlay_batches[id]: _retire_overlay_batch(previous)
		_overlay_batches[id] = _overlay_installing[id]
		_overlay_installing.erase(id)
		if row.kind=="administration" and row.get("basis","")!="current_members": spatial_world.install_administrative_boundary(id,row.components,str(row.lod))
		return true
	return false

func _cancel_overlay_display() -> void:
	_overlay_generation = _overlay_preparation.invalidate()
	MapJobs.cancel_queued(_overlay_thread)
	_overlay_demand.clear()
	_overlay_request.clear()
	_overlay_query_id = ""
	_clear_overlay_installing()
	_clear_overlay_batches()
	if spatial_world!=null: spatial_world.retain_administrative_boundaries([])

func _clear_overlay_batches() -> void:
	for group: Array in _overlay_batches.values():
		for batch: Dictionary in group: _retire_overlay_batch(batch)
	_overlay_batches.clear()

func _clear_overlay_installing() -> void:
	_overlay_retiring.append_array(_overlay_uploads)
	_overlay_uploads.clear()
	_overlay_upload_owner = null
	for group: Array in _overlay_installing.values():
		for batch: Dictionary in group: _retire_overlay_batch(batch)
	_overlay_installing.clear()

func _retire_overlay_batch(batch: Dictionary) -> void:
	RenderingServer.canvas_item_set_visible(batch.item,false)
	_overlay_retiring.append(batch)

func _drain_overlay_retirement(bounded: bool = true) -> void:
	var began := Time.get_ticks_usec()
	while not _overlay_retiring.is_empty() and (not bounded or _map_budget.claim_retirement()):
		var batch: Dictionary=_overlay_retiring.pop_back()
		if batch.has("item"): RenderingServer.free_rid(batch.item)
		batch.clear()
		if bounded and Time.get_ticks_usec()-began>=2000: break

func _retire_overlay_demand() -> void:
	var keep: Array[String] = []
	for row: Dictionary in _overlay_demand: keep.append(str(row.id))
	for id: String in _overlay_batches.keys():
		if id in keep: continue
		for batch: Dictionary in _overlay_batches[id]: _retire_overlay_batch(batch)
		_overlay_batches.erase(id)
	# This evicts display/picking components only, never administrative identity
	# or actual land membership. A replacement LOD keeps its previous components
	# until install_administrative_boundary swaps the same object's reference.
	if not _overlay_query_id.is_empty(): keep.append(_overlay_query_id)
	spatial_world.retain_administrative_boundaries(keep)

func _update_overlay_batches(view: Rect2, install_only: bool = false) -> void:
	var wanted: Dictionary = {}
	for row: Dictionary in _overlay_demand: wanted[str(row.id)] = row
	var colors := InterfaceSettings.theme_parameters()
	var physical_ready := _physical_demand_installed()
	var regional := controller.region_camera.active
	var padded_view := view.grow(_strategic_mpp()*8.0)
	var opacity := lerpf(1.0,0.72,smoothstep(650.0,2400.0,_strategic_mpp()))
	var anchor := controller.region_camera.valid_anchor(size) if regional else {}
	var center := anchor.unit as Vector3 if regional else controller.orientation().transposed()*Vector3.BACK
	var view_angle := PI*.5+16.0/maxf(_radius,1.0)
	if regional:
		view_angle=0.0
		for corner: Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
			view_angle=maxf(view_angle,(corner.distance_to(anchor.pixel as Vector2)+16.0)*controller.region_camera.km_per_pixel/RegionProjection.EARTH_RADIUS_KM)
	for id: String in _overlay_batches:
		for batch: Dictionary in _overlay_batches[id]:
			# Initialisation sets parent_canvas only after the batch becomes
			# visible. View, demand and style changes still update every batch.
			if install_only and batch.has("parent_canvas"): continue
			var show: bool = visible and physical_ready and (regional or str(batch.kind) in ["sovereignty","control"]) and wanted.has(id)
			if show and batch.kind in ["administration","military_grid"]:
				show = (not _city_display_active() or batch.kind=="military_grid") and (wanted[id].bounds as Rect2).intersects(padded_view,true)
			if show and float(batch.get("cull_angle",PI))<PI*.5:
				show=(batch.cull_axis as Vector3).angle_to(center)<=float(batch.cull_angle)+view_angle
			if show!=bool(batch.get("visible",false)):
				RenderingServer.canvas_item_set_visible(batch.item,show)
				batch["visible"] = show
			if not show: continue
			var canvas := region_view.annotation_canvas if regional else _viewport.world_2d.canvas
			if batch.get("parent_canvas",RID())!=canvas:
				RenderingServer.canvas_item_set_parent(batch.item,canvas)
				batch["parent_canvas"] = canvas
			_parameter(batch,"region_mode",regional)
			if regional: _set_region_uniforms(batch)
			else:
				_parameter(batch,"globe_basis",controller.orientation())
				_parameter(batch,"globe_center",_center)
				_parameter(batch,"globe_radius",_radius)
			_bounds(batch,size)
			var selected: bool = id==controller.selected_place_id
			var color := Color(0.80,0.57,0.29,0.82) if batch.kind=="control" else POLITICAL_UNDER_COLOR if batch.kind=="sovereignty" else colors.admin_line as Color
			if batch.kind=="military_grid": color=Color("a4b79a");color.a=0.70
			var level := int(batch.get("level",1))
			if batch.kind=="administration" and level>1:
				color = color.lerp(Color(0.55,0.57,0.53,color.a),0.18*minf(float(level-1),3.0))
				color.a *= maxf(0.45,1.0-0.18*float(level-1))
			color.a *= opacity
			if selected: color = Color(0.67,0.75,0.76,0.82)
			_parameter(batch,"stroke_color",color)
			var width := 1.35 if selected else 0.65 if batch.kind=="military_grid" else 1.05 if batch.kind in ["sovereignty","control"] else maxf(0.50,0.85-0.10*float(level))
			_parameter(batch,"stroke_width",width)



func _draw_administrative_labels() -> void:
	if _city_display_active(): return
	if not controller.administrative_layer_active() or spatial_world==null or not controller.region_camera.active: return
	if not controller.labels_enabled: return
	var occupied := _label_exclusions()
	occupied.append_array(region_view.country_label_rects)
	occupied.append_array(local_layer.label_rects)
	occupied.append_array(strategic_layer.label_rects)
	for row: Dictionary in _overlay_demand:
		if row.kind!="administration": continue
		var id := str(row.id)
		if _strategic_mpp()<180.0 and id!=controller.selected_place_id: continue
		# Reject known-ineligible labels before font fallback/shape allocation.
		# The padded geometry window is larger than the visible label window.
		if id!=controller.selected_place_id and (occupied.size()>28 or minf((row.bounds as Rect2).size.x,(row.bounds as Rect2).size.y)/_strategic_mpp()<38.0): continue
		var unit := GlobeProjection.lon_lat_to_unit(spatial_world.land_topology().to_geographic((row.bounds as Rect2).get_center()))
		var center := screen_point(unit)
		if not center.is_finite() or not Rect2(Vector2.ZERO,size).grow(32.0).has_point(center): continue
		var identity := spatial_world.administrative_identity(id)
		var text := UILocale.name(identity.merged({"id":id}))
		if not _admin_label_metrics.has(text):
			if _admin_label_metrics.size()>=128: _admin_label_metrics.erase(_admin_label_metrics.keys()[0])
			var face := GlobeLabels.font_for_name(_font,text)
			_admin_label_metrics[text] = {"font":face,"size":face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11)}
		var font := _admin_label_metrics[text].font as Font
		var text_size := _admin_label_metrics[text].size as Vector2
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
	controller.focus_region(unit,Vector2(size.x*0.5+minf(160.0,size.x*0.16),size.y*0.5),scale,0.0,size)
	controller.select(str(spatial_world.administrative_identity(id).get("polity_id","")),id)
	controller.view_changed.emit()
	return true

func _begin_transition(to_region: bool) -> void:
	# Cosmetic fade only. The authoritative mode already changed in Controller.
	# Freeze only the DEPARTING texture before its batches change canvas;
	# the active destination continues to redraw from the resident foundation.
	var departing := _viewport if to_region else region_view.viewport
	departing.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_transition_to_region = to_region
	_transition_elapsed = 0.0
	_transition_started = 0
	_invalidate_projection()
	set_process(visible)

func _request_map_frame(regional: bool) -> void:
	# Uniforms and canvas parents have already been committed. Update only
	# that target, and invalidate its TextureRect consumer in the main window.
	var target := region_view.viewport if regional else _viewport
	var consumer := region_view.container if regional else _container
	var moving := controller.camera_motion_active() or _transition_elapsed>=0.0
	if inspection_preview:
		target.render_target_update_mode = SubViewport.UPDATE_ONCE
		consumer.queue_redraw()
		if moving: set_process(visible)
		return
	var window := get_window()
	var foreground := window.has_focus() and window.mode!=Window.MODE_MINIMIZED
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS if moving and foreground else SubViewport.UPDATE_ONCE
	consumer.queue_redraw()
	if observation_profile and regional and not controller.region_camera.local_active and not observation_return.is_empty() and not observation_return.has("submitted_us"):
		observation_return["submitted_us"] = Time.get_ticks_usec()
		RenderingServer.frame_post_draw.connect(_observe_region_frame.bind(observation_return["requested_us"]), CONNECT_ONE_SHOT)
	if moving: set_process(visible)

func _observe_region_frame(requested: int) -> void:
	if not observation_return.is_empty() and int(observation_return["requested_us"]) == requested and controller.region_camera.active and not controller.region_camera.local_active:
		observation_return["first_valid_frame_us"] = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var observed_at: int=Time.get_ticks_usec() if observation_profile else 0
	if observation_profile: observation_costs={"frame":Engine.get_process_frames()}
	_map_budget.reset(observation_costs if observation_profile else {})
	for layer: LocalSpatialLayer in [_world_layer,_region_layer,local_layer]: layer.drain_retirement(_map_budget)
	if not visible:
		# Join cancelled workers and discard their results even while hidden.
		# This processing stops as soon as the existing requests have drained.
		_poll_overlay_prepare()
		if strategic_content!=null: strategic_content.poll()
		if local_content!=null: local_content.poll()
		local_layer.prepare_step(_font,_map_budget)
		_world_layer.prepare_step(_font,_map_budget)
		_region_layer.prepare_step(_font,_map_budget)
		region_view.prepare_landmarks()
		relief.poll(_map_budget)
		set_process(_has_pending_preparation())
		return
	# Reconcile a moved camera before collecting completed uploads.
	_ensure_camera()
	var camera_demand_changed := _resource_demand_dirty
	if camera_demand_changed:
		_resource_demand_dirty = false
		_sync_relief()
		_sync_local_resources()
		_sync_strategic_resources()
	var preparation_at: int=Time.get_ticks_usec() if observation_profile else 0
	if observation_profile: observation_costs["prepare_overlay_us"]=preparation_at-observed_at
	var previous_surface_base: Variant = relief.textures.get("europe_r48_base")
	var previous_canary_base: Variant = relief.textures.get("canary_r45_base")
	var previous_siberian_base: Variant = relief.textures.get("siberian_r50_base")
	var previous_asian_west: Variant = relief.textures.get("asia_west_r51_base")
	var previous_asian_east: Variant = relief.textures.get("asia_east_r51_base")
	var previous_shared_surface: Variant = relief.textures.get("euro_afro_arabia_r53_base")
	var previous_greenland: Variant = relief.textures.get("greenland_r52_base")
	if relief.poll(_map_budget):
		_bind_relief()
		var asian_west_ready: bool = relief.textures.get("asia_west_r51_base")!=previous_asian_west and relief.textures.has("asia_west_r51_base")
		var asian_east_ready: bool = relief.textures.get("asia_east_r51_base")!=previous_asian_east and relief.textures.has("asia_east_r51_base")
		var shared_surface_ready: bool = relief.textures.get("euro_afro_arabia_r53_base")!=previous_shared_surface and relief.textures.has("euro_afro_arabia_r53_base")
		var greenland_ready: bool = relief.textures.get("greenland_r52_base")!=previous_greenland and relief.textures.has("greenland_r52_base")
		if shared_surface_ready or greenland_ready:
			map_notice.emit("区域地貌：现代高程与WorldCover 2021；中性虚线表示水文季节属性未知，盐盆不表示永久湖面。")
		elif asian_west_ready:
			map_notice.emit("区域地貌：现代高程与WorldCover 2021；咸海水面采用1950年代后期参考，非1900精测。")
		elif asian_east_ready or relief.textures.get("europe_r48_base")!=previous_surface_base and relief.textures.has("europe_r48_base") or relief.textures.get("canary_r45_base")!=previous_canary_base and relief.textures.has("canary_r45_base") or relief.textures.get("siberian_r50_base")!=previous_siberian_base and relief.textures.has("siberian_r50_base"):
			map_notice.emit("区域地貌：现代真实高程与WorldCover 2021参考；共享地理瓦片，不代表1900年土地利用。")
		# Loading a texture must invalidate the cached viewport, not just glyphs.
		_invalidate_appearance()
	if observation_profile: observation_costs["prepare_relief_us"]=Time.get_ticks_usec()-preparation_at;preparation_at=Time.get_ticks_usec()
	if strategic_content != null: strategic_content.poll()
	if observation_profile: observation_costs["prepare_strategic_us"]=Time.get_ticks_usec()-preparation_at;preparation_at=Time.get_ticks_usec()
	for layer: LocalSpatialLayer in [_world_layer,_region_layer]:
		if layer.preparing:
			layer.prepare_step(_font,_map_budget)
			if layer.ready and not layer.preparing: _invalidate_spatial_display()
	if observation_profile: observation_costs["prepare_geometry_us"]=Time.get_ticks_usec()-preparation_at;preparation_at=Time.get_ticks_usec()
	if local_content != null and local_content.poll():
		if local_content.content.errors.is_empty():
			_sync_local_resources()
		_evaluate_scale()
		_invalidate_spatial_display()
		place_content_ready.emit()
	if local_layer.preparing:
		local_layer.prepare_step(_font,_map_budget)
		if local_layer.ready and not local_layer.preparing:
			_evaluate_scale()
			_invalidate_spatial_display()
	if observation_profile: observation_costs["preparation_us"]=Time.get_ticks_usec()-observed_at
	_ensure_camera()
	if _label_setting!=controller.labels_enabled:
		_label_setting = controller.labels_enabled
		_world_labels.clear()
		region_view.clear_labels()
		_region_labels_dirty = true
		_view_dirty = true
	if controller.region_camera.active and not region_view.ready: region_view.begin(_political_ink)
	var demand_changed := _resource_demand_dirty or _strategic_content_dirty
	var observed_demand: int=Time.get_ticks_usec() if observation_profile else 0
	if demand_changed:
		_resource_demand_dirty = false
		_strategic_content_dirty = false
		_sync_local_resources()
		if observation_profile: observation_costs["demand_local_us"]=Time.get_ticks_usec()-observed_demand;observed_demand=Time.get_ticks_usec()
		_sync_strategic_resources()
		if observation_profile: observation_costs["demand_strategic_us"]=Time.get_ticks_usec()-observed_demand;observed_demand=Time.get_ticks_usec()
	if camera_demand_changed or demand_changed or _administrative_display_dirty:
		_sync_overlay_resources()
		if observation_profile: observation_costs["demand_overlay_us"]=Time.get_ticks_usec()-observed_demand
	_poll_overlay_prepare()
	var view_was_dirty := _view_dirty
	var observed_view: int=Time.get_ticks_usec() if observation_profile else 0
	var prepared_layer := _ensure_view()
	if observation_profile: observation_costs["view_us"]=Time.get_ticks_usec()-observed_view
	var observed_commit: int=Time.get_ticks_usec() if observation_profile else 0
	if _map_canvas_dirty or view_was_dirty or _administrative_display_dirty or _local_display_dirty: _commit_map_view(view_was_dirty,prepared_layer)
	# Publish the current city/model demand before accepting finished loads.
	if region_view.prepare_landmarks():
		_local_display_dirty = true
		queue_redraw()
	if observation_profile:
		observation_costs["commit_us"]=Time.get_ticks_usec()-observed_commit
		observation_costs["map_us"]=Time.get_ticks_usec()-observed_at
		observation_costs["upload_bytes"]=_map_budget.uploaded_bytes
		observation_costs["upload_operations"]=_map_budget.operations
		observation_costs["retire_operations"]=_map_budget.retired
	if _transition_elapsed >= 0.0 and _transition_started>0:
		_transition_elapsed = float(Time.get_ticks_usec() - _transition_started) / 1000000.0
		var weight := clampf(_transition_elapsed / TRANSITION_SECONDS, 0.0, 1.0)
		region_view.container.modulate.a = weight if _transition_to_region else 1.0 - weight
		# REGION is the upper cached canvas. Keep WORLD opaque underneath;
		# fading both layers would expose the background and darken the midpoint.
		_container.modulate.a = 1.0
		if weight >= 1.0:
			_transition_elapsed = -1.0
			_show_submitted_canvas(_transition_to_region)
			_evaluate_scale()
			queue_redraw()
	var moving := controller!=null and controller.camera_motion_active()
	if not moving and _transition_elapsed<0.0:
		# Submit the final interaction frame, then Godot returns ONCE to disabled.
		for target: SubViewport in [_viewport,region_view.viewport]:
			if target.render_target_update_mode==SubViewport.UPDATE_ALWAYS:
				target.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _map_canvas_dirty or _view_dirty: queue_redraw()
	if not _physical_demand_installed() and (not _strategic_failure.is_empty() or not _world_layer.preparation_error.is_empty()) and not _has_pending_preparation():
		set_process(false)
		return
	if not moving and not _map_canvas_dirty and not _view_dirty and not _resource_demand_dirty and not _strategic_content_dirty and not _has_pending_preparation() and (_transition_elapsed < 0.0 or _transition_started==0):
		set_process(false)

func _has_pending_preparation() -> bool:
	return _overlay_thread!=null or not _overlay_uploads.is_empty() or not _overlay_retiring.is_empty() or relief.preparing() or region_view.landmark_preparing() or _world_layer.preparing or _region_layer.preparing or local_layer.preparing or _world_layer.retirement_pending() or _region_layer.retirement_pending() or local_layer.retirement_pending() or (strategic_content!=null and strategic_content.preparing()) or (local_content!=null and local_content.preparing())

func _on_strategic_content_changed() -> void:
	_strategic_content_dirty = true
	_invalidate_spatial_display()
	place_content_ready.emit()

func _on_spatial_display_changed(source: LocalSpatialLayer = null) -> void:
	_local_display_dirty = true
	if _strategic_waiting and source!=null and source.display_installed():
		map_notice.emit("全球基础地图已安装。" if source==_world_layer else "当前区域细节已安装。")
	_strategic_waiting = false
	# Both base publications can unlock the next bounded demand: WORLD
	# permits medium, and medium permits its optional ink/hydrography.
	# The loader's existing wanted/ink comparison makes this idempotent.
	if source in [_world_layer,_region_layer] and controller.region_camera.active: _strategic_content_dirty = true
	var installed := strategic_layer.political_cells_installed()
	for id: String in _current_land_rows.keys():
		if not _current_cells.has(id) and not installed.has(id): _current_land_rows.erase(id)
	_refresh_historical_border_geometry()
	_invalidate_spatial_display()
	_administrative_display_dirty = true

func _on_administrative_display_changed() -> void:
	# A completed admin display/picking batch is not a camera, terrain or
	# political surface revision. Update only its bounded demand and 2D image.
	_overlay_request.clear()
	_symbol_layout_dirty = true
	_administrative_display_dirty = true
	set_process(visible)
	queue_redraw()
	place_content_ready.emit()

func _on_visibility_changed() -> void:
	if observation_suspended:
		set_process(false)
		return
	if controller == null:
		return
	if not visible:
		civilian_facilities.present({},false,false)
		_cancel_overlay_display()
		_sync_relief()
		_world_layer.clear()
		_region_layer.clear()
		strategic_layer = _world_layer
		if strategic_content!=null: strategic_content.release()
		region_view.clear()
		_sync_local_coverage()
		local_layer.clear()
		if local_content != null: local_content.release()
		_transition_elapsed = -1.0
		set_process(_has_pending_preparation())
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		region_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		# Visibility changes do not publish an unprepared destination. The next
		# whole-view draw decides which cached canvas may be shown.
		_view_dirty = true
		_resource_demand_dirty = true
		set_process(true)
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
