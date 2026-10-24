extends Control
## Read-only host for WWO's existing globe geometry, shaders and camera math.
## No polity, place, person, economy or combat state is created by this view.
signal loaded
signal region_selected(available: bool)
signal coordinate_selected(lon_lat: Vector2)
const SharedBoundary = preload("res://scripts/presentation/map/globe_boundary_batch.gd")
var controller := GlobeController.new()
var catalog := VNextSpatialCatalog.new()
var runtime_catalog: VNextSpatialCatalog
var anchor_place_id := "place:paris"
var anchor: Dictionary
var anchor_ll := Vector2.ZERO
var anchor_frame := Basis()
var viewport: SubViewport
var texture_view: TextureRect
var planet: Node3D
var camera: Camera3D
var background: ColorRect
var batches: Array[Dictionary] = []
var cities: Array[Dictionary] = []
var is_loaded := false
var selected := false
var military := true
var status := "准备WWO共享地图"
var load_ms := 0
var face_count := 0
var material_ms := 0.0
var vehicle_local := Vector3.ZERO
var person_local := Vector3.ZERO
var commander_dismounted := false
var commander_name := ""
var local_available := false
var font: Font = preload("res://cedar/system_font.tres")
var _base_radius := 230.0
var _radius := 230.0
var _center := Vector2.ZERO
var _ocean: ShaderMaterial
var _active_relief: Texture2D
var _active_regional := false
var relief_switch_max_ms := 0.0
var _last_size := Vector2.ZERO
var _tick := 0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	add_child(controller)
	controller.view_changed.connect(_view_changed)
	controller.appearance_changed.connect(_view_changed)
	if runtime_catalog!=null:catalog=runtime_catalog
	elif not catalog.load_legacy_world_map():push_error(str(catalog.errors()));return
	anchor=catalog.get_place(anchor_place_id)
	var ll: Array=anchor.lon_lat
	anchor_ll=Vector2(ll[0],ll[1]);anchor_frame=RegionProjection.frame(anchor_ll)
	cities=catalog.cities()
	cities.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return int(a.get("label_priority",0))>int(b.get("label_priority",0)))
	viewport=SubViewport.new();viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.size=Vector2i(940,600);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	texture_view=TextureRect.new();texture_view.mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_view.show_behind_parent=true;texture_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;texture_view.texture=viewport.get_texture();add_child(texture_view);texture_view.add_child(viewport)
	background=ColorRect.new();background.color=Color("163b49");background.mouse_filter=Control.MOUSE_FILTER_IGNORE;background.hide();viewport.add_child(background)
	planet=Node3D.new();planet.set_script(load("res://scripts/presentation/map/globe_surface.gd"))
	for name: String in ["Surface","Moon"]:
		var mesh:=MeshInstance3D.new();mesh.name=name;planet.add_child(mesh)
	camera=Camera3D.new();camera.name="Camera3D";camera.position=Vector3(0,0,2.35);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.55;camera.near=.05;camera.far=12;camera.current=true;planet.add_child(camera)
	viewport.add_child(planet)
	(planet.get_node("Moon") as Node3D).hide()
	_ocean=(planet.get_node("Surface") as MeshInstance3D).material_override
	_ocean.set_shader_parameter("ocean_detail",load("res://assets/maps/ocean/orbital_r24/pelagic_eddies_albedo.png"))
	_ocean.set_shader_parameter("ocean_ice",load("res://assets/maps/ocean/orbital_r24/polar_pack_ice_albedo.png"))
	controller.focus(anchor_frame.z);controller.set_world_zoom(1.05)
	_load_shared.call_deferred()

func _relief(path: String,width: int,height: int) -> Texture2D:
	var image:=Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))!=OK or image.get_size()!=Vector2i(width,height):
		push_error("WWO地貌资源读取失败："+path);return null
	image.convert(Image.FORMAT_RG8)
	return ImageTexture.create_from_image(image)

func _load_shared() -> void:
	var begin:=Time.get_ticks_msec()
	_active_relief=_relief("res://assets/maps/relief/world.bin",1024,512)
	var index: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://global_link/shared_map_index.json"))
	for row: Dictionary in index.physical_shards:
		var file:=FileAccess.open_compressed(row.compiled_asset.path,FileAccess.READ,FileAccess.COMPRESSION_DEFLATE)
		if file==null:push_error("无法读取WWO分片："+str(row.id));return
		var display: Dictionary=file.get_var(false);file.close()
		if display.get("schema_id")!="physical_political_display_r37" or display.get("physical_shard_id")!=row.id or display.get("role")!="DISPLAY_ONLY_NOT_SOVEREIGNTY":
			push_error("WWO分片身份不匹配");return
		for chunk: Dictionary in display.chunks:
			if chunk.kind!="land_reference" or not chunk.has("face_count"):continue
			var geometry:=GlobeSurfaceBatch.new();geometry.upload(chunk.payload)
			if geometry.data==null:continue
			var material:=ShaderMaterial.new();material.shader=load("res://shaders/presentation/map/political_surface.gdshader")
			material.set_shader_parameter("face_data",geometry.data)
			material.set_shader_parameter("flag_weight",0.0);material.set_shader_parameter("political_weight",0.0)
			material.set_shader_parameter("relief_world",_active_relief);material.set_shader_parameter("relief_region",_active_relief);material.set_shader_parameter("relief_weight",.92)
			material.set_shader_parameter("antarctic_land",str(chunk.get("water_class",""))=="antarctic_land")
			var mesh:=MeshInstance2D.new();mesh.mesh=geometry.mesh;mesh.material=material;viewport.add_child(mesh)
			batches.append({"node":mesh,"geometry":geometry,"material":material});face_count+=int(chunk.face_count)
		status="WWO共享地理分片 %d / 24"%int(index.physical_shards.find(row)+1)
		_view_changed()
		await get_tree().process_frame
	var border_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/political_border_display_r39.json"))
	if border_doc.get("schema_id")!="political_border_display_r39" or border_doc.get("geometry_role")!="DISPLAY_PARTITION_SHARED_EDGES_ONLY_NOT_SOVEREIGNTY":push_error("WWO边界格式不匹配");return
	var lines: Array[Dictionary]=[]
	for row: Dictionary in border_doc.boundaries:
		var ll:=PackedVector2Array()
		for p: Array in row.points:ll.append(Vector2(p[0],p[1]))
		lines.append({"kind":"admin","points":GlobeProjection.display_line(ll)})
	var boundary:=SharedBoundary.new();boundary.prepare(lines,"admin",true)
	var material:=ShaderMaterial.new();material.shader=load("res://shaders/presentation/map/globe_boundary.gdshader")
	material.set_shader_parameter("line_data",boundary.data);material.set_shader_parameter("stroke_color",Color(.80,.73,.56,.72));material.set_shader_parameter("stroke_width",.9);material.set_shader_parameter("stroke_feather",.65);material.set_shader_parameter("miter_limit",1.5)
	var mesh:=MeshInstance2D.new();mesh.mesh=boundary.mesh;mesh.material=material;mesh.z_index=1;viewport.add_child(mesh)
	batches.append({"node":mesh,"geometry":boundary,"material":material,"boundary":true})
	load_ms=Time.get_ticks_msec()-begin;is_loaded=true;status="WWO共享底图已就绪";_view_changed();loaded.emit()
	print("SHARED_WWO_GLOBE "+JSON.stringify({"shards":24,"faces":face_count,"batches":batches.size(),"load_ms":load_ms,"place":anchor.get("place_id","place:paris"),"lon_lat":[anchor_ll.x,anchor_ll.y]}))

func select_training() -> void:
	selected=true;region_selected.emit(true);queue_redraw()

func whole_earth() -> void:
	controller.focus(anchor_frame.z);controller.set_world_zoom(1.05)

func focus_training(close: bool=true) -> void:
	controller.suspend_motion()
	if close:controller.focus_region(anchor_frame.z,size*.5,.30,0,size)
	else:controller.focus_region(anchor_frame.z,size*.5,2.0,0,size)
	select_training()

func set_military(value: bool) -> void:
	if military==value:return
	military=value;_view_changed()

func project(unit: Vector3) -> Vector2:
	if controller.region_camera.active:return controller.region_camera.project(unit)
	return GlobeProjection.sphere_screen(controller.orientation()*unit,_center,_radius)

func visible_unit(unit: Vector3) -> bool:
	return (controller.observation_basis(size)*unit).z>0 and Rect2(Vector2.ZERO,size).has_point(project(unit))

func unit_at(pixel: Vector2) -> Vector3:
	if controller.region_camera.active:return controller.region_camera.unit_at(pixel)
	return RegionProjection.world_unit(pixel,_center,_radius,controller.orientation())

func unit_from_local(p: Vector3) -> Vector3:
	return RegionProjection.inverse(Vector2(p.x,-p.z)*.001,anchor_frame)

func footprint() -> PackedVector3Array:
	var line:=PackedVector3Array()
	var corners: Array[Vector2]=[Vector2(-22500,-22500),Vector2(27500,-22500),Vector2(27500,27500),Vector2(-22500,27500),Vector2(-22500,-22500)]
	for i: int in 4:
		for j: int in 8:
			var p:=corners[i].lerp(corners[i+1],float(j)/8)
			line.append(unit_from_local(Vector3(p.x,0,p.y)))
	line.append(line[0]);return line

func _gui_input(event: InputEvent) -> void:
	if not is_loaded:return
	var pixel: Vector2=event.position if event is InputEventMouse else get_local_mouse_position()
	var picked:=unit_at(pixel)
	var input_rect:=Rect2(Vector2.ZERO,size) if controller.region_camera.active else Rect2(_center-Vector2.ONE*_radius,Vector2.ONE*_radius*2)
	var clicked:=controller.handle_input(event,input_rect,picked,{"size":size,"base_radius":_base_radius,"center":_center,"minimum_mpp":250.0})
	controller.update_observation_mode(size,_center,_base_radius)
	if clicked and not picked.is_zero_approx():
		var km:=RegionProjection.forward(picked,anchor_frame)
		var hit:=Rect2(-22.5,-27.5,50,50).has_point(km)
		if not controller.region_camera.active:hit=hit or project(anchor_frame.z).distance_to(pixel)<15
		selected=hit;coordinate_selected.emit(RegionProjection.lon_lat(picked));region_selected.emit(hit);queue_redraw()
	accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if size!=_last_size:_last_size=size;_view_changed()
	_tick+=delta
	if _tick>.25:_tick=0;queue_redraw()

func _view_changed() -> void:
	if viewport==null:return
	var begin:=Time.get_ticks_usec()
	texture_view.size=size
	if viewport.size!=Vector2i(size):viewport.size=Vector2i(size)
	background.size=size
	_center=size*.5;_base_radius=minf(size.y/2.55,size.x*.49);_radius=_base_radius*controller.zoom
	var regional:=controller.region_camera.active
	if _active_relief!=null and regional!=_active_regional:
		var load_begin:=Time.get_ticks_usec()
		_active_relief=_relief("res://assets/maps/relief/region.bin" if regional else "res://assets/maps/relief/world.bin",4096 if regional else 1024,2048 if regional else 512)
		_active_regional=regional
		relief_switch_max_ms=maxf(relief_switch_max_ms,(Time.get_ticks_usec()-load_begin)/1000.0)
	planet.visible=not regional;background.visible=regional
	camera.size=2.55/controller.zoom
	var basis:=controller.region_camera.tangent_frame.transposed() if regional else controller.orientation()
	_ocean.set_shader_parameter("globe_basis",basis)
	for batch: Dictionary in batches:
		var material: ShaderMaterial=batch.material
		if not batch.get("boundary",false):
			material.set_shader_parameter("relief_world",_active_relief);material.set_shader_parameter("relief_region",_active_relief)
			material.set_shader_parameter("relief_detail_weight",1.0 if regional else 0.0)
		else:batch.node.visible=not military
		material.set_shader_parameter("globe_basis",basis)
		material.set_shader_parameter("globe_center",controller.region_camera.origin if regional else _center)
		material.set_shader_parameter("globe_radius",_radius)
		material.set_shader_parameter("region_mode",regional)
		material.set_shader_parameter("region_km_per_pixel",controller.region_camera.km_per_pixel)
		material.set_shader_parameter("region_bearing",Vector2(cos(controller.region_camera.bearing),sin(controller.region_camera.bearing)))
		RenderingServer.canvas_item_set_custom_rect(batch.node.get_canvas_item(),true,Rect2(Vector2.ZERO,size))
	material_ms=maxf(material_ms,(Time.get_ticks_usec()-begin)/1000.0);queue_redraw()

func _line(points: PackedVector3Array,color: Color,width: float) -> void:
	if controller.region_camera.active:
		var line:=PackedVector2Array()
		for p: Vector3 in points:
			if (controller.region_camera.tangent_frame.transposed()*p).z<0:
				if line.size()>1:draw_polyline(line,color,width,true)
				line=PackedVector2Array()
			else:line.append(project(p))
		if line.size()>1:draw_polyline(line,color,width,true)
	else:
		for line: PackedVector2Array in GlobeProjection.project_line(points,controller.orientation(),_center,_radius):draw_polyline(line,color,width,true)

func _draw() -> void:
	if not is_loaded:return
	var city_labels: Array[Rect2]=[]
	for city: Dictionary in cities:
		var raw: Array=city.lon_lat;var unit:=GlobeProjection.lon_lat_to_unit(Vector2(raw[0],raw[1]))
		if not visible_unit(unit):continue
		if not controller.region_camera.active and str(city.map_id) not in ["paris","london","berlin","cairo","new_york","tokyo"]:continue
		var point:=project(unit);draw_circle(point,2.5,Color("e0ca98"))
		var extent:=font.get_string_size(str(city.name),HORIZONTAL_ALIGNMENT_LEFT,-1,14)
		var box:=Rect2(point+Vector2(7,-20),extent+Vector2(2,6))
		if city_labels.any(func(other: Rect2) -> bool:return other.intersects(box.grow(4))):continue
		city_labels.append(box);draw_string(font,point+Vector2(7,-6),str(city.name),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f1e6ce"))
	_line(footprint(),Color("f2ca73") if selected else Color("a6c6a6"),2.5)
	if visible_unit(anchor_frame.z):
		var p:=project(anchor_frame.z)
		draw_arc(p,9,0,TAU,40,Color("f2ca73"),2)
		draw_string(font,p+Vector2(16,22),"50 km · 训练放置",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("ffe0a3"))
	if military and local_available:
		var unit:=unit_from_local(vehicle_local)
		if visible_unit(unit):
			var p:=project(unit);draw_circle(p,5,Color("7de5d0"));draw_string(font,p+Vector2(16,42),"原车" if commander_dismounted else "原车 / "+commander_name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("bbffef"))
		if commander_dismounted:
			var person:=unit_from_local(person_local)
			if visible_unit(person):
				var p:=project(person);draw_circle(p,3,Color("f2ca73"));draw_string(font,p+Vector2(16,62),commander_name+" · 步战",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffe0a3"))
	var scale: float=controller.region_camera.km_per_pixel if controller.region_camera.active else RegionProjection.EARTH_RADIUS_KM/_radius
	var km:=pow(10,floor(log(scale*100)/log(10)))
	var x:=Vector2(24,size.y-28);draw_line(x,x+Vector2(km/scale,0),Color("d6d8bb"),3)
	draw_string(font,x-Vector2(0,12),"%.0f km"%km,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("e4e5cc"))
	draw_string(font,Vector2(24,28),"行政参考 · 1900边界" if not military else "军事观察 · 共享WWO地理",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("eee4c6"))
