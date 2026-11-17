class_name CityMiniature
extends RefCounted
## Presentation only: source-derived city meshes and isolated settlement diagrams.
const MapJobs = preload("res://scripts/presentation/map/map_jobs.gd")
const CityStorage = preload("res://scripts/presentation/map/city_surface_storage.gd")
const GRADE_NAMES: Array[String] = ["未知", "村庄", "城镇", "中小城市", "中等城市", "中大型城市", "大型城市", "核心都市"]
const COUNTS: Array[int] = [0, 6, 18, 40, 85, 150, 240, 380]
static var _profiles: Dictionary = {}
static var _registered: Array[Dictionary] = []
static var _registered_ready: bool = false
const MAX_VISIBLE_CITIES: int = 2
const OVERVIEW_FULL_MPP: float = 160.0
const OVERVIEW_END_MPP: float = 240.0
const RASTER_DISTRICT_BUDGET_BYTES: int = 4*1024*1024
const CONTEXT_PRINT_BUDGET_BYTES: int = 6*1024*1024
const FrameBudget = preload("res://scripts/presentation/map/map_frame_budget.gd")
const MAX_READS: int = 4
const READ_BYTES: int = 12 * 1024 * 1024
var cache_budget_bytes: int = -1
var load_slots: Dictionary = {}
var frame_budget: FrameBudget
var _waiting_for_slot: bool = false
var _budget_rejected: Dictionary = {}
var _retiring_context: Array[Dictionary] = []
var nodes: Array[GeometryInstance3D] = []
var layout: Array[Dictionary] = []
var cached: Dictionary = {}
var profile: Dictionary = {}
var key: String = ""
var build_count: int = 0
var instances: int = 0
var bounds: Rect2
var render_bounds: Rect2
var _block_mesh: ArrayMesh
var _water_data: Dictionary = {}
var _water_polygons: Array[PackedVector2Array] = []
var _water_banks: Array[PackedVector2Array] = []
var _mesh_cache: Dictionary = {}
var _pending_meshes: Dictionary = {}
var _packed_mesh_jobs: Dictionary[String,MapJobs.Job] = {}
var _mesh_age: Dictionary = {}
var _mesh_bytes: Dictionary = {}
var _parts: Dictionary = {}
var _wanted_meshes: Dictionary = {}
var _presentation: Dictionary = {}
var _presentation_job: MapJobs.Job
var _presentation_ready: bool
var _context_tones_ready: bool
var _age: int = 0
var _water_mesh_paths: Dictionary = {} # Derived paths in the current presentation index.
var _water_active_path: String = ""
var _context_level: int = 8
var _context_print_level: int = 12
var _context_install_pending: bool = false
var _context_items: Dictionary = {}
var _context_view_key: Array = []
var _metropolitan_tones: Array[Vector4] = [] # Display windows, not settlement extent.
var _building_opacity: float = 0.0

func preparing() -> bool:
	return _presentation_job!=null or not _pending_meshes.is_empty() or _context_install_pending or _waiting_for_slot or not _retiring_context.is_empty()

func poll(budget_usec: int = 2000) -> bool:
	_drain_context(frame_budget)
	var changed := _waiting_for_slot
	_waiting_for_slot = false
	if _presentation_job!=null and _presentation_job.completed:
		var result := _presentation_job.take() as Dictionary
		_presentation = result.index
		if frame_budget!=null and not frame_budget.observations.is_empty() and result.has("read_us"):
			frame_budget.observations["city_index_read_us"] = int(frame_budget.observations.get("city_index_read_us",0)) + int(result.read_us)
			frame_budget.observations["city_index_decode_us"] = int(frame_budget.observations.get("city_index_decode_us",0)) + int(result.decode_us)
		_presentation_job = null
		_presentation_ready = true
		changed = true
	var began := Time.get_ticks_usec()
	for path: String in _pending_meshes.keys():
		var job: MapJobs.Job = _packed_mesh_jobs.get(path)
		if job!=null:
			if not job.completed: continue
		elif ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		var wanted := _wanted_meshes.has(path)
		if wanted and frame_budget!=null and not frame_budget.claim_upload(int(_pending_meshes[path])): break
		var started := Time.get_ticks_usec()
		var mesh: ArrayMesh
		if job!=null:
			var arrays := job.take() as Array
			_packed_mesh_jobs.erase(path)
			if wanted and not arrays.is_empty():
				mesh = ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			elif wanted: _budget_rejected[path] = true
		else:
			mesh = MapJobs.take_resource(path) as ArrayMesh
		if frame_budget!=null: frame_budget.observe("city_ground_upload_us" if job!=null else "native_get_us",started)
		if mesh!=null and wanted:
			var bytes := 0
			for surface: int in mesh.get_surface_count():
				bytes+=mesh.surface_get_array_len(surface)*16+mesh.surface_get_array_index_len(surface)*4
				if mesh.surface_get_format(surface)&Mesh.ARRAY_FORMAT_COLOR: bytes+=mesh.surface_get_array_len(surface)*4
				if mesh.surface_get_format(surface)&Mesh.ARRAY_FORMAT_TEX_UV: bytes+=mesh.surface_get_array_len(surface)*8
			if mesh.has_meta("resident_bytes"): bytes = int(mesh.get_meta("resident_bytes"))
			if _trim_meshes(bytes):
				_mesh_cache[path]=mesh
				_mesh_bytes[path]=bytes
			else: _budget_rejected[path] = true
		load_slots["count"] = int(load_slots.get("count",0))-1
		load_slots["bytes"] = int(load_slots.get("bytes",0))-int(_pending_meshes[path])
		_pending_meshes.erase(path)
		if not wanted: _mesh_age.erase(path)
		elif frame_budget!=null: frame_budget.finish_upload(started,"city loaded mesh")
		changed = changed or wanted
		if Time.get_ticks_usec()-began>budget_usec: break
		if wanted: break
	_trim_meshes()
	if changed or _context_install_pending: _context_view_key.clear()
	return changed or _context_install_pending

func _request_mesh(path: String) -> void:
	# poll() trims before scene installation. Keep every requested current
	# layer, including the blended overview and foundations, until then.
	_wanted_meshes[path]=true
	_age+=1
	if _mesh_cache.has(path) or _pending_meshes.has(path): _mesh_age[path]=_age
	if _budget_rejected.has(path): return
	if not _mesh_cache.has(path) and not _pending_meshes.has(path):
		var frame := Engine.get_process_frames()
		if _pending_meshes.size()>=2 or int(load_slots.get("count",0))>=MAX_READS or (frame_budget!=null and int(load_slots.get("frame",-1))==frame):
			_waiting_for_slot=true
			return
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null: return
		var bytes := file.get_length()
		var decoded_bytes := CityStorage.read_budget(file) if path.begins_with("res://assets/settlements/europe_context/context_") else 0
		file.close()
		bytes=maxi(bytes,decoded_bytes)
		if bytes>READ_BYTES: return
		if int(load_slots.get("bytes",0))+bytes>READ_BYTES:
			_waiting_for_slot=true
			return
		var error := OK
		if decoded_bytes>0:
			var job := MapJobs.submit(CityStorage.read.bind(path),"city ground decode",MapJobs.VISIBLE)
			if job==null: error=ERR_BUSY
			else: _packed_mesh_jobs[path]=job
		else: error=MapJobs.request_resource(path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE)
		if error==ERR_BUSY: _waiting_for_slot=true
		if error==OK:
			_mesh_age[path]=_age
			_pending_meshes[path]=bytes
			load_slots["count"] = int(load_slots.get("count",0))+1
			load_slots["bytes"] = int(load_slots.get("bytes",0))+bytes
			load_slots["frame"] = frame

func _trim_meshes(reserve: int = 0) -> bool:
	var total := 0
	for bytes: int in _mesh_bytes.values(): total+=bytes
	var budget: int=(48 if not profile.is_empty() else 24)*1024*1024
	# Keep the visible old and new context prints during the existing handoff.
	if cache_budget_bytes>=0: budget=maxi(cache_budget_bytes,24*1024*1024)
	for path: String in _budget_rejected.keys():
		if not _wanted_meshes.has(path): _budget_rejected.erase(path)
	while total+reserve>budget:
		var oldest: String=""
		for path: String in _mesh_cache:
			if _parts.has(path) or _context_items.has(path) or _wanted_meshes.has(path): continue
			if oldest.is_empty() or int(_mesh_age.get(path,0))<int(_mesh_age.get(oldest,0)): oldest=path
		if oldest.is_empty(): break
		total-=int(_mesh_bytes.get(oldest,0))
		_erase_mesh(oldest)
	return total+reserve<=budget

func _erase_mesh(path: String) -> void:
	_mesh_cache.erase(path)
	_mesh_age.erase(path)
	_mesh_bytes.erase(path)

static func for_content(content: LocalSpatialContent) -> Dictionary:
	if content == null: return {}
	var path: String = str(content.metadata.get("city_overview_path", ""))
	return _profile(path)

static func for_place(id: String) -> Dictionary:
	if id.is_empty(): return {}
	for data: Dictionary in registered_profiles():
		if str(data.place_id)==id: return data
	return {}

static func registered_profiles() -> Array[Dictionary]:
	if _registered_ready: return _registered
	for source: Dictionary in LocalSpatialLoader.SOURCES:
		var rows: Array = [{"place_id":source.anchor_id,"path":source.get("city_overview_path","")}]
		rows.append_array(source.get("city_overview_profiles",[]) as Array)
		for row: Dictionary in rows:
			var data := _profile(str(row.get("path","")))
			if data.is_empty(): continue
			data["place_id"]=str(row.place_id)
			_registered.append(data)
	for path: String in ["res://data/local/iberian_settlement_context.json", "res://data/local/germany_settlement_context.json", "res://data/local/europe_settlement_context.json"]:
		var data := _profile(path)
		if data.is_empty() or not FileAccess.file_exists(str(data.get("presentation_index",""))): continue
		data["place_id"]=""
		_registered.append(data)
	_registered_ready=true
	return _registered

static func at_position(ll: Vector2) -> Dictionary:
	for data: Dictionary in registered_profiles():
		if data.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT": continue
		var b: Array=data.get("content_bounds",data.get("overview_bounds",[]))
		if b.size()==4 and Rect2(Vector2(b[0],b[1]),Vector2(float(b[2])-float(b[0]),float(b[3])-float(b[1]))).has_point(ll): return data
	return {}

static func screen_bounds(data: Dictionary, camera: RegionCamera, include_water: bool = false) -> Rect2:
	var area := extent(data)
	if include_water and data.has("background_bounds"):
		var b: Array=data.background_bounds
		area=Rect2(Vector2(b[0],b[1]),Vector2(float(b[2])-float(b[0]),float(b[3])-float(b[1])))
	var bounds := Rect2()
	var first := true
	for ll: Vector2 in [area.position,area.end,Vector2(area.end.x,area.position.y),Vector2(area.position.x,area.end.y)]:
		var point := camera.project(GlobeProjection.lon_lat_to_unit(ll))
		bounds=Rect2(point,Vector2.ZERO) if first else bounds.expand(point)
		first=false
	return bounds

static func visible_profiles(camera: RegionCamera, viewport: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not camera.active: return result
	var candidates: Array[Dictionary]=[]
	var contexts: Array[Dictionary]=[]
	var geographic_view := Rect2()
	var first_corner := true
	for pixel: Vector2 in [Vector2.ZERO,Vector2(viewport.x,0),viewport,Vector2(0,viewport.y)]:
		var ll := RegionProjection.lon_lat(camera.unit_at(pixel))
		geographic_view=Rect2(ll,Vector2.ZERO) if first_corner else geographic_view.expand(ll);first_corner=false
	for data: Dictionary in registered_profiles():
		var context: bool=data.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT"
		if context and camera.km_per_pixel*1000.0>float(data.maximum_mpp): continue
		if context and not extent(data).intersects(geographic_view): continue
		var coverage: Array=data.get("coverage_windows",[])
		if context and not coverage.is_empty():
			# A continental envelope's projected corners can miss a local
			# window along the middle of its south or north edge.
			if coverage.any(func(b: Array) -> bool:
				return Rect2(Vector2(b[0],b[1]),Vector2(float(b[2])-float(b[0]),float(b[3])-float(b[1]))).intersects(geographic_view)
			): contexts.append(data)
			continue
		if not context and display_strength(camera.km_per_pixel*1000.0)<=0.001: continue
		var bounds := screen_bounds(data,camera,true)
		if bounds.grow(96.0).intersects(Rect2(Vector2.ZERO,viewport)):
			if context: contexts.append(data)
			else: candidates.append({"data":data,"distance":bounds.get_center().distance_squared_to(viewport*.5)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.distance)<float(b.distance))
	for row: Dictionary in candidates:
		result.append(row.data)
		if result.size()>=MAX_VISIBLE_CITIES: break
	result.append_array(contexts)
	return result

static func _profile(path: String) -> Dictionary:
	if path.is_empty(): return {}
	if not _profiles.has(path):
		_profiles[path] = _read_profile(path)
	return _profiles[path]

static func _read_profile(path: String, timing: Dictionary = {}) -> Dictionary:
	if path.is_empty(): return {}
	var started := Time.get_ticks_usec() if not timing.is_empty() else 0
	var text := FileAccess.get_file_as_string(path)
	var read_done := Time.get_ticks_usec() if started>0 else 0
	var data: Variant = JSON.parse_string(text)
	if started>0:
		timing["read_us"] = read_done-started
		timing["decode_us"] = Time.get_ticks_usec()-read_done
	return data if data is Dictionary else {}

func _ensure_presentation(path: String) -> bool:
	if _presentation_ready: return true
	if _presentation_job==null:
		_presentation_job = MapJobs.submit(CityMiniature._read_presentation.bind(path,MapJobs.measuring),"city presentation index",MapJobs.VISIBLE)
		if _presentation_job==null: _waiting_for_slot = true
	return false

static func _read_presentation(path: String, measured: bool) -> Dictionary:
	var timing: Dictionary = {"read_us":0,"decode_us":0} if measured else {}
	var data := _read_profile(path,timing)
	timing["index"] = data
	return timing

static func sample(source: Dictionary, grade: int) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result["id"] = "isolated_display_grade_" + str(grade)
	result["name"] = "隔离显示样例 · " + GRADE_NAMES[grade] + " · 不代表此处历史聚落"
	result["scale_grade"] = grade
	var radii: Array[float] = [0, 150, 330, 500, 750, 1000, 1400, 1700]
	result["districts"] = [{"name": GRADE_NAMES[grade] + "显示样例", "anchor": [-.13,51.513], "radius_m": [radii[grade], radii[grade] * .65], "count": COUNTS[grade], "heading": 0}]
	return result

static func extent(data: Dictionary) -> Rect2:
	if data.has("overview_bounds"):
		var b: Array=data.overview_bounds
		return Rect2(Vector2(float(b[0]),float(b[1])),Vector2(float(b[2])-float(b[0]),float(b[3])-float(b[1])))
	var result := Rect2()
	var first := true
	for d: Dictionary in data.get("districts", []):
		var ll := Vector2(float(d.anchor[0]), float(d.anchor[1]))
		var radius := Vector2(float(d.radius_m[0]) / (111195.0 * cos(deg_to_rad(ll.y))), float(d.radius_m[1]) / 111195.0)
		var area := Rect2(ll - radius, radius * 2)
		result = area if first else result.merge(area)
		first = false
	return result

static func pose_valid(data: Dictionary, camera: RegionCamera, origin: Vector2, scale: float, bearing: float, safe: Rect2, elevation: float, viewport_size: Vector2 = Vector2.ZERO) -> bool:
	if scale * 1000.0 < float(data.minimum_mpp) - .001: return false
	if scale*1000.0>float(data.get("maximum_mpp",96.0)): return false
	if data.has("background_bounds") and not data.has("presentation_index"):
		if scale*1000.0>float(data.get("maximum_mpp",96.0)): return false
		var b: Array=data.background_bounds
		var background := Rect2(Vector2(float(b[0]),float(b[1])),Vector2(float(b[2])-float(b[0]),float(b[3])-float(b[1])))
		var ground := Rect2(Vector2.ZERO,viewport_size).grow(24.0+80.0*cos(elevation)/maxf(1.0,scale*1000.0))
		var inverse := RegionProjection.screen_axes(bearing).inverse()
		for pixel: Vector2 in [ground.position,ground.end,Vector2(ground.end.x,ground.position.y),Vector2(ground.position.x,ground.end.y)]:
			var ll := RegionProjection.lon_lat(RegionProjection.inverse(inverse*(pixel-origin)*scale,camera.tangent_frame))
			if not background.has_point(ll): return false
	var area: Rect2 = extent(data)
	if data.has("content_bounds"):
		var box: Array=data.content_bounds
		area=Rect2(Vector2(float(box[0]),float(box[1])),Vector2(float(box[2])-float(box[0]),float(box[3])-float(box[1])))
	var polygon := PackedVector2Array()
	var axes := RegionProjection.screen_axes(bearing)
	for ll: Vector2 in [area.position, Vector2(area.end.x,area.position.y), area.end, Vector2(area.position.x,area.end.y)]:
		polygon.append(origin + axes * (RegionProjection.forward(GlobeProjection.lon_lat_to_unit(ll),camera.tangent_frame) / scale))
	var view := PackedVector2Array([safe.position,Vector2(safe.end.x,safe.position.y),safe.end,Vector2(safe.position.x,safe.end.y)])
	var original: float = absf(GlobeProjection.polygon_area(polygon))
	var visible: float = 0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(polygon,view): visible += absf(GlobeProjection.polygon_area(piece))
	# The content may be smaller than the screen. Preserve a visible part of
	# the city with a pitch-dependent safety band instead of confining all pixels.
	var collar: float = 24.0 + 32.0 * cos(elevation)
	var minimum := minf(original*.38,safe.get_area()*.30) if data.has("presentation_index") else original*.38
	return visible >= minimum and safe.grow(-collar).intersects(Rect2(polygon[0],Vector2.ONE).expand(polygon[1]).expand(polygon[2]).expand(polygon[3]))

static func display_strength(mpp: float) -> float:
	return 1.0-smoothstep(OVERVIEW_FULL_MPP,OVERVIEW_END_MPP,mpp)

func clear() -> void:
	_context_install_pending=false;_context_view_key.clear()
	_waiting_for_slot=false
	MapJobs.abandon(_presentation_job)
	_presentation_job = null
	_presentation_ready = false
	_context_tones_ready = false
	_budget_rejected.clear()
	for item: Dictionary in _context_items.values(): _retire_context_item(item)
	_context_items.clear()
	for node: GeometryInstance3D in nodes:
		node.visible = false
		if node is MultiMeshInstance3D: (node as MultiMeshInstance3D).multimesh = null
		elif node is MeshInstance3D: (node as MeshInstance3D).mesh = null
		node.queue_free()
	nodes.clear(); instances = 0; key = ""
	profile={};bounds=Rect2();render_bounds=Rect2()
	_parts.clear();_wanted_meshes.clear();_presentation={}
	_building_opacity=0.0
	_metropolitan_tones.clear()
	_water_active_path=""
	_mesh_cache.clear()
	_mesh_age.clear()
	_mesh_bytes.clear()

func _retire_context_item(item: Dictionary) -> void:
	if frame_budget==null:
		RenderingServer.free_rid(item.item as RID)
		return
	RenderingServer.canvas_item_set_visible(item.item as RID,false)
	if _retiring_context.size()>=512:
		RenderingServer.free_rid((_retiring_context.pop_back() as Dictionary).item as RID)
	_retiring_context.append(item)

func _drain_context(budget: FrameBudget) -> void:
	while not _retiring_context.is_empty() and (budget==null or budget.claim_retirement()):
		RenderingServer.free_rid((_retiring_context.pop_back() as Dictionary).item as RID)

func dispose() -> void:
	clear()
	_drain_context(null)
	for path: String in _pending_meshes:
		if _packed_mesh_jobs.has(path): MapJobs.abandon(_packed_mesh_jobs[path])
		else: MapJobs.abandon_resource(path)
		load_slots["count"] = int(load_slots.get("count",0))-1
		load_slots["bytes"] = int(load_slots.get("bytes",0))-int(_pending_meshes[path])
	_pending_meshes.clear()
	_packed_mesh_jobs.clear()

func _context_tile_rect(tile: Dictionary, view: RefCounted, camera: RegionCamera) -> Rect2:
	var b: Array=tile.bounds
	var rect := Rect2()
	var first := true
	for ll: Vector2 in [Vector2(b[0],b[1]),Vector2(b[2],b[1]),Vector2(b[2],b[3]),Vector2(b[0],b[3])]:
		var point: Vector2=view.chart_screen_point(GlobeProjection.lon_lat_to_unit(ll),camera)
		rect=Rect2(point,Vector2.ZERO) if first else rect.expand(point);first=false
	return rect

static func _context_view_extent(camera: RegionCamera, viewport_size: Vector2) -> Rect2:
	var extent := Rect2()
	var first := true
	for pixel: Vector2 in [Vector2(-48,-48),Vector2(viewport_size.x+48,-48),viewport_size+Vector2(48,48),Vector2(-48,viewport_size.y+48)]:
		var ll := RegionProjection.lon_lat(camera.unit_at(pixel))
		extent=Rect2(ll,Vector2.ZERO) if first else extent.expand(ll)
		first=false
	return extent

static func _context_grid(extent: Rect2, level: int) -> Rect2i:
	var n := 1<<level
	var x0 := clampi(int(floor((extent.position.x+180.0)/360.0*n)),0,n-1)
	var x1 := clampi(int(floor((extent.end.x+180.0)/360.0*n)),0,n-1)
	var y0 := clampi(int(floor((1.0-asinh(tan(deg_to_rad(clampf(extent.end.y,-85.0,85.0))))/PI)*.5*n)),0,n-1)
	var y1 := clampi(int(floor((1.0-asinh(tan(deg_to_rad(clampf(extent.position.y,-85.0,85.0))))/PI)*.5*n)),0,n-1)
	return Rect2i(x0,y0,x1-x0+1,y1-y0+1)

func _context_demand(level: int, grid: Rect2i) -> Dictionary:
	var wanted: Dictionary={}
	for x: int in range(grid.position.x,grid.end.x):
		for y: int in range(grid.position.y,grid.end.y):
			var tile: Dictionary=(_presentation.get("tiles",{}) as Dictionary).get("%d/%d/%d"%[level,x,y],{})
			if tile.is_empty(): continue
			wanted[str(tile.path)]=tile
	return wanted

static func _context_detail_tiles(overview: Dictionary, detail: Dictionary, grid: Rect2i) -> Dictionary:
	# z+2 divides each overview tile into a 4x4 group. Only replace a parent
	# when every on-screen child exists. No detail tiles are invented for gaps.
	var groups: Dictionary={}
	for path: String in detail:
		var row := detail[path] as Dictionary
		var key := Vector2i(int(row.x)>>2,int(row.y)>>2)
		if not groups.has(key): groups[key]=[]
		(groups[key] as Array).append(path)
	var result := detail.duplicate()
	for path: String in overview:
		var row := overview[path] as Dictionary
		var key := Vector2i(int(row.x),int(row.y))
		var children := groups.get(key,[]) as Array
		var expected := Rect2i(key*4,Vector2i(4,4)).intersection(grid).get_area()
		if expected>0 and children.size()==expected: continue
		for child: String in children: result.erase(child)
		result[path]=row
	return result

static func _ground_bytes(tiles: Dictionary) -> int:
	var bytes := 0
	for tile: Dictionary in tiles.values():
		bytes+=int(tile.get("resident_bytes",int(tile.vertices)*20+int(tile.triangles)*12))
	return bytes

func _update_context(view: RefCounted, data: Dictionary, camera: RegionCamera, viewport_size: Vector2) -> bool:
	if key!=str(data.id):
		clear();key=str(data.id);build_count+=1
	profile=data
	if not _ensure_presentation(str(data.presentation_index)): return false
	if not _context_tones_ready:
		_context_tones_ready = true
		for city: Dictionary in _presentation.get("building_print",{}).get("cities",[]):
			# Coarse ink hands over only where roof detail is actually present.
			# A larger, independent radius leaves an empty annulus around town.
			var radius := float(city.radius_km)
			_metropolitan_tones.append(Vector4(city.anchor[0],city.anchor[1],maxf(0.0,radius-clampf(radius*.3,1.0,3.0)),radius))
		if _metropolitan_tones.is_empty():
			var box: Array=data.content_bounds
			for city: Dictionary in registered_profiles():
				if city.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT": continue
				var a: Array=city.anchor
				if float(a[0])<box[0] or float(a[0])>box[2] or float(a[1])<box[1] or float(a[1])>box[3]: continue
				var b: Array=city.get("content_bounds",[])
				if b.size()!=4: continue
				var radius: float=maxf((float(b[2])-float(b[0]))*111.195*cos(deg_to_rad(a[1])),(float(b[3])-float(b[1]))*111.195)*.5
				_metropolitan_tones.append(Vector4(a[0],a[1],radius,radius*1.6))
	var detail_ready: Array=[]
	for layer: CityMiniature in view.city_views():
		if layer==self or layer.profile.is_empty() or layer.profile.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT": continue
		detail_ready.append([layer.key,layer._building_opacity])
	var input_key: Array=[camera.tangent_frame,camera.origin,camera.km_per_pixel,camera.bearing,viewport_size,view.city_profiles,detail_ready]
	if input_key==_context_view_key: return false
	_context_view_key=input_key
	_context_install_pending=false
	_wanted_meshes.clear()
	var mpp := camera.km_per_pixel*1000.0
	var london_overview: bool = _presentation.get("building_print",{}).has("historical_london") and mpp>160.0 and mpp<600.0
	var geographic_view := _context_view_extent(camera,viewport_size)
	var wanted := _context_demand(8,_context_grid(geographic_view,8))
	var ground_level := 8
	var print_level := 12
	var raster_overview := wanted.values().any(func(tile: Dictionary) -> bool: return bool(tile.get("woodland_mask",false)))
	var district_mpp := 175.0 if raster_overview else 110.0
	if mpp<district_mpp*(1.35 if _context_level==10 else 1.0):
		var grid := _context_grid(geographic_view,10)
		var fine := _context_detail_tiles(wanted,_context_demand(10,grid),grid)
		var bytes := _ground_bytes(fine)
		# Screen coverage, not only scale, bounds the district payload. Leave
		# headroom before re-entering it; retain valid old geometry during load.
		# Several large overview pages can cost more than the visible districts.
		var budget := cache_budget_bytes if cache_budget_bytes>=0 else int(data.cache_budget_bytes)
		var threshold := int(float(budget)*(1.0 if _context_level==10 else .8))
		# Prefer the existing polygons while the coarse mask spans several pixels.
		if raster_overview: threshold = maxi(threshold,RASTER_DISTRICT_BUDGET_BYTES)
		if not fine.is_empty() and (wanted.is_empty() or bytes<=threshold or bytes<_ground_bytes(wanted)):
			ground_level=10;wanted=fine
	_context_level=ground_level
	# Roof prints reuse the national canvas. Their byte budget includes the
	# mipmapped masks; no per-house nodes or new 3D viewport are required.
	if _presentation.has("building_print") and (mpp<240.0 or london_overview):
		print_level=14 if mpp<(24.0 if _context_print_level==14 else 18.0) else 12
		var overview := _context_demand(12,_context_grid(geographic_view,12))
		var prints := overview
		if print_level==14:
			var grid := _context_grid(geographic_view,14)
			prints = _context_detail_tiles(overview,_context_demand(14,grid),grid)
		var bytes := 0
		for tile: Dictionary in prints.values(): bytes+=int(tile.get("resident_bytes",0))
		if bytes>CONTEXT_PRINT_BUDGET_BYTES:
			print_level=12;prints=overview
		for path: String in prints.keys():
			var historical := str(prints[path].get("overview_only",""))=="london_historical"
			if (historical and not london_overview) or (not historical and mpp>=240.0): prints.erase(path)
		if _ground_bytes(prints)>CONTEXT_PRINT_BUDGET_BYTES:
			var centre := geographic_view.get_center()
			var nearest: Array=prints.values()
			nearest.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
				var pa := Vector2(float(a.anchor[0]),float(a.anchor[1]))
				var pb := Vector2(float(b.anchor[0]),float(b.anchor[1]))
				return pa.distance_squared_to(centre)<pb.distance_squared_to(centre)
			)
			var remaining := CONTEXT_PRINT_BUDGET_BYTES
			prints={}
			for row: Dictionary in nearest:
				var cost := int(row.get("resident_bytes",0))
				if cost>remaining: continue
				prints[str(row.path)]=row
				remaining-=cost
		_context_print_level=print_level
		wanted.merge(prints)
	var all_ready := true
	for path: String in wanted:
		_wanted_meshes[path]=true
		if _mesh_cache.has(path): _age+=1;_mesh_age[path]=_age
		elif _pending_meshes.size()<8: _request_mesh(path)
		if not _mesh_cache.has(path): all_ready=false
	var detail_boxes: Array[Vector4]=[]
	var detail_weights := Vector3.ZERO
	for layer: CityMiniature in view.city_views():
		if layer==self or layer.profile.is_empty() or layer.profile.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT": continue
		if layer._building_opacity<=0.0: continue
		var coverage: Array=layer.profile.get("building_coverage_bounds",[layer.profile.get("content_bounds",[])])
		for b: Array in coverage:
			if b.size()!=4 or detail_boxes.size()>=3: continue
			detail_weights[detail_boxes.size()]=layer._building_opacity
			detail_boxes.append(Vector4(b[0],b[1],b[2],b[3]))
	var wanted_cells: Dictionary={}
	for row: Dictionary in wanted.values():
		wanted_cells[Vector3i(int(row.x),int(row.y),int(row.z))]=true
	var changing := false
	for item: Dictionary in _context_items.values():
		var tile := item.tile as Dictionary
		if wanted.has(str(tile.path)) or bool(item.get("staged",false)): continue
		var cell := Vector3i(int(tile.x),int(tile.y),int(tile.z))
		if cell.z==10 or cell.z==14:
			changing=wanted_cells.has(Vector3i(cell.x>>2,cell.y>>2,cell.z-2))
		else:
			for y: int in range(4):
				for x: int in range(4):
					if wanted_cells.has(Vector3i(cell.x*4+x,cell.y*4+y,cell.z+2)): changing=true
				if changing: break
		if changing: break
	var keep: Dictionary={}
	var installed := 0
	if all_ready or not changing:
		for path: String in wanted:
			if not _mesh_cache.has(path): continue
			var tile: Dictionary=wanted[path]
			var roof_print := int(tile.z)>=12
			if not _context_items.has(path):
				if installed>=8 or frame_budget!=null and not frame_budget.claim_upload(0):
					_context_install_pending=true
					continue
				var started := Time.get_ticks_usec()
				var item := RenderingServer.canvas_item_create()
				RenderingServer.canvas_item_set_parent(item,view.map_canvas)
				RenderingServer.canvas_item_set_draw_index(item,-9 if roof_print else -10)
				RenderingServer.canvas_item_set_custom_rect(item,true,Rect2(Vector2.ZERO,viewport_size))
				var material := ShaderMaterial.new()
				material.shader=preload("res://shaders/presentation/map/settlement_context.gdshader")
				if not roof_print:
					var candidates: Array=_metropolitan_tones.duplicate()
					var center := Vector2(tile.anchor[0],tile.anchor[1])
					candidates.sort_custom(func(a: Vector4,b: Vector4)->bool:return Vector2(a.x,a.y).distance_squared_to(center)<Vector2(b.x,b.y).distance_squared_to(center))
					for index: int in range(3): material.set_shader_parameter("metropolitan%d"%index,candidates[index] if index<candidates.size() else Vector4.ZERO)
				var mesh := _mesh_cache[path] as ArrayMesh
				if mesh.has_meta("building_print"):
					material.set_shader_parameter("building_print",roof_print)
					material.set_shader_parameter("street_print",bool(tile.get("street_print",false)))
					material.set_shader_parameter("window_baked",bool(tile.get("window_baked",false)))
					material.set_shader_parameter("coverage_mask",not roof_print)
					material.set_shader_parameter("woodland_mask",bool(tile.get("woodland_mask",false)))
					material.set_shader_parameter("building_mask",mesh.get_meta("building_print"))
				if roof_print and not bool(tile.get("window_baked",false)):
					var windows: Array[Vector4]=[]
					for city: Dictionary in _presentation.get("building_print",{}).get("cities",[]):
						if not city.id in tile.get("cities",[]): continue
						var radius := float(city.radius_km)
						windows.append(Vector4(city.anchor[0],city.anchor[1],radius,clampf(radius*.3,1.0,3.0)))
					for index: int in range(3): material.set_shader_parameter("print_coverage%d"%index,windows[index] if index<windows.size() else Vector4.ZERO)
				RenderingServer.canvas_item_set_material(item,material.get_rid())
				RenderingServer.canvas_item_add_mesh(item,(_mesh_cache[path] as ArrayMesh).get_rid())
				_context_items[path]={"item":item,"material":material,"tile":tile,"staged":changing};installed+=1
				if frame_budget!=null: frame_budget.finish_upload(started,"city context item")
			keep[path]=true
	var switch_ready := all_ready and not _context_install_pending
	var continuity := 1.0-smoothstep(55.0,130.0,mpp) if data.get("building_ground_handoff",false) else 0.0
	if changing and not switch_ready:
		for path: String in _context_items:
			if _context_tile_rect(_context_items[path].tile,view,camera).intersects(Rect2(Vector2.ZERO,viewport_size).grow(48)): keep[path]=true
	instances=0
	for path: String in _context_items.keys():
		var item: Dictionary=_context_items[path]
		if not keep.has(path):
			_retire_context_item(item)
			_context_items.erase(path)
			if int(item.tile.z)>=12 and not _wanted_meshes.has(path): _erase_mesh(path)
			continue
		var tile: Dictionary=item.tile
		var roof_print := int(tile.z)>=12
		RenderingServer.canvas_item_set_custom_rect(item.item as RID,true,Rect2(Vector2.ZERO,viewport_size))
		if switch_ready or not changing: item["staged"]=false
		RenderingServer.canvas_item_set_visible(item.item as RID,not bool(item.get("staged",false)))
		var material := item.material as ShaderMaterial
		material.set_shader_parameter("generalisation_opacity",lerpf(.35,1.0,smoothstep(40.0,180.0,mpp)))
		material.set_shader_parameter("ground_continuity",continuity)
		material.set_shader_parameter("detailed_weight",display_strength(mpp) if _presentation.has("building_print") or not detail_boxes.is_empty() else 0.0)
		material.set_shader_parameter("globe_basis",camera.tangent_frame.transposed())
		material.set_shader_parameter("globe_center",camera.origin)
		material.set_shader_parameter("region_km_per_pixel",camera.km_per_pixel)
		material.set_shader_parameter("region_bearing",Vector2(cos(camera.bearing),sin(camera.bearing)))
		var maximum := float(data.maximum_mpp)
		material.set_shader_parameter("strength",1.0-smoothstep(maximum*5.0/6.0,maximum,mpp))
		if roof_print:
			var strength := 1.0-smoothstep(160.0,240.0,mpp)
			if tile.get("overview_only","")=="london_historical":
				strength = (1.0-strength)*(1.0-smoothstep(420.0,600.0,mpp))
			material.set_shader_parameter("strength",strength)
		material.set_shader_parameter("detail_weights",detail_weights)
		for index: int in range(3): material.set_shader_parameter("detail_bounds%d"%index,detail_boxes[index] if index<detail_boxes.size() else Vector4.ZERO)
		instances+=int(tile.get("source_features",{}).get("urban",0))
	bounds=Rect2(Vector2.ZERO,viewport_size);render_bounds=Rect2()
	_trim_meshes()
	return true

func _historical_part(view: RefCounted, path: String, tone: Color, water: bool = false, building: bool = false) -> MeshInstance3D:
	_request_mesh(path)
	if not _mesh_cache.has(path): return null
	if not _parts.has(path):
		if frame_budget!=null and not frame_budget.claim_upload(0):
			_waiting_for_slot = true
			return null
		var started := Time.get_ticks_usec()
		var node := MeshInstance3D.new()
		node.mesh=_mesh_cache[path] as ArrayMesh
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in node.mesh.get_surface_count():
			if building and profile.has("building_coverage_bounds"):
				var edge := ShaderMaterial.new()
				edge.shader=preload("res://shaders/presentation/map/city_reference_edge.gdshader")
				var coverage: Array=profile.building_coverage_bounds
				var a: Array=_presentation.anchor
				edge.set_shader_parameter("source_frame",RegionProjection.frame(Vector2(a[0],a[1])))
				edge.set_shader_parameter("tone",Vector3(tone.r,tone.g,tone.b) if surface==0 else Vector3(.36,.37,.33))
				for index: int in range(2):
					var b: Array=coverage[index] if index<coverage.size() else [0,0,0,0]
					edge.set_shader_parameter("coverage%d"%index,Vector4(b[0],b[1],b[2],b[3]))
				node.set_surface_override_material(surface,edge)
				continue
			var material := StandardMaterial3D.new()
			material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode=BaseMaterial3D.CULL_DISABLED
			material.albedo_color=tone if surface==0 or water else Color(.36,.37,.33)
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
			if water:
				material.vertex_color_use_as_albedo=true
				if surface==1:
					material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
					material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
			node.set_surface_override_material(surface,material)
		view._landmark_root.add_child(node);nodes.append(node);_parts[path]=node
		if frame_budget!=null: frame_budget.finish_upload(started,"city scene item")
	return _parts[path] as MeshInstance3D

func _opacity(node: MeshInstance3D, value: float) -> void:
	if node==null: return
	for surface: int in node.mesh.get_surface_count():
		var edge := node.get_surface_override_material(surface) as ShaderMaterial
		if edge!=null:
			edge.set_shader_parameter("strength",value)
			continue
		var material := node.get_surface_override_material(surface) as StandardMaterial3D
		# Fully visible roofs/walls use stable depth ordering. Water fringe and
		# actual LOD blends retain alpha; no dither is introduced into the map.
		var opaque := value>=.99999 and not material.vertex_color_use_as_albedo
		var mode := BaseMaterial3D.TRANSPARENCY_DISABLED if opaque else BaseMaterial3D.TRANSPARENCY_ALPHA
		if material.transparency!=mode:
			material.transparency=mode
			material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY if opaque else BaseMaterial3D.DEPTH_DRAW_DISABLED
		var color := material.albedo_color
		if not is_equal_approx(color.a,value):
			color.a=value
			material.albedo_color=color

func water_state() -> Dictionary:
	var resident: int = 0
	var bytes: int = 0
	var pending: int = 0
	for path: String in _water_mesh_paths:
		if _mesh_cache.has(path): resident+=1;bytes+=int(_mesh_bytes.get(path,0))
		if _pending_meshes.has(path): pending+=1
	var row: Dictionary = _water_mesh_paths.get(_water_active_path,{})
	return {"lod":row.get("id",""),"active_nodes":1 if _parts.has(_water_active_path) else 0,"resident_meshes":resident,"pending_meshes":pending,"geometry_bytes":bytes,"triangles":row.get("triangles",0),"simplification_m":row.get("simplification_m",0),"fringe_m":row.get("fringe_m",0),"basis":"MODERN_WATER_REFERENCE_NOT_HISTORICAL_SHORE"}

func _historical_water(view: RefCounted, camera: RegionCamera, desired: Dictionary) -> void:
	var levels: Array = _presentation.get("water_lods",{}).get("levels",[])
	if levels.is_empty(): return
	var mpp: float = camera.km_per_pixel*1000.0
	var grade: String = "near" if mpp<12.0 else "district" if mpp<24.0 else "overview"
	var current: String = str(_water_mesh_paths.get(_water_active_path,{}).get("id",""))
	# Hysteresis prevents repeated resource swaps around a scale boundary.
	if current=="near" and mpp<=13.0: grade=current
	elif current=="district" and mpp>=11.0 and mpp<=26.0: grade=current
	elif current=="overview" and mpp>=22.0: grade=current
	for row: Dictionary in levels:
		var path: String = row.path
		_water_mesh_paths[path]=row
		if row.id!=grade: continue
		_wanted_meshes[path]=true;_request_mesh(path)
		if _mesh_cache.has(path): _water_active_path=path
	# Retain the previous mesh until its asynchronous replacement is ready.
	if not _water_active_path.is_empty():
		desired[_water_active_path]=true
		_opacity(_historical_part(view,_water_active_path,Color(.34,.46,.45),true),display_strength(mpp))

func _update_historical(view: RefCounted, data: Dictionary, camera: RegionCamera, viewport_size: Vector2) -> void:
	if key!=str(data.id):
		clear();key=str(data.id);build_count+=1
		_water_data={"bounds":data.background_bounds}
	profile=data
	if not _ensure_presentation(str(data.presentation_index)): return
	var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(data.anchor[0]),float(data.anchor[1])))
	var placement: Transform3D=view._chart_transform(unit,camera,viewport_size)
	placement.basis*=view._geographic_basis(unit,camera,0.0)
	var desired: Dictionary={}
	_wanted_meshes.clear()
	var tones := {"water":Color(.34,.46,.45),"water_inner":Color(.32,.435,.43),"banks":Color(.47,.49,.39),"parks":Color(.40,.50,.33),"routes":Color(.75,.71,.59),"bridges":Color(.69,.65,.54)}
	_historical_water(view,camera,desired)
	for part: Dictionary in _presentation.get("foundation",[]):
		var path: String=part.path
		desired[path]=true
		# Green-space boundaries are a map tint over the physical reference,
		# not an opaque replacement for every terrain pixel inside the polygon.
		var opacity := .42 if part.id=="parks" else 1.0
		_opacity(_historical_part(view,path,tones.get(part.id,Color.WHITE)),display_strength(camera.km_per_pixel*1000.0)*opacity)
	var mpp := camera.km_per_pixel*1000.0
	var strength := display_strength(mpp)
	var inspection_mesh: bool = data.get("building_mesh_inspection_only",false)
	var building_strength := strength
	if inspection_mesh:
		# The default map uses one continuous set of roof prints. The separately
		# surveyed volumes remain available for explicitly oblique inspection.
		var tilt: float = view.inspection_elevation_degrees
		building_strength *= (1.0-smoothstep(18.0,32.0,mpp)) if tilt>=0.0 and tilt<45.0 else 0.0
	var near := building_strength>0.0 and mpp<28.0
	_building_opacity=0.0
	var detailed: Array[Dictionary]=[]
	var all_ready := true
	if near:
		for tile: Dictionary in _presentation.get("tiles",[]):
			if not tile.lods.has("district"): continue
			var a: Array=tile.bounds[0];var b: Array=tile.bounds[1]
			var screen := Rect2();var first := true
			for ll: Vector2 in [Vector2(a[0],a[1]),Vector2(b[0],a[1]),Vector2(b[0],b[1]),Vector2(a[0],b[1])]:
				var pixel: Vector2=view.chart_screen_point(GlobeProjection.lon_lat_to_unit(ll),camera)
				screen=Rect2(pixel,Vector2.ZERO) if first else screen.expand(pixel);first=false
			if not screen.intersects(Rect2(Vector2.ZERO,viewport_size).grow(160)): continue
			var row: Dictionary=tile.lods.district
			_wanted_meshes[str(row.path)]=true
			detailed.append(row);_request_mesh(str(row.path))
			if not _mesh_cache.has(str(row.path)): all_ready=false
	var district_nodes: Array[MeshInstance3D] = []
	if near and all_ready:
		for row: Dictionary in detailed:
			var path := str(row.path)
			desired[path]=true
			var tone := Color(.40,.39,.34) if inspection_mesh else Color(.49,.47,.41)
			var node := _historical_part(view,path,tone,false,true)
			if node!=null: district_nodes.append(node)
	var use_detail := near and not detailed.is_empty() and district_nodes.size()==detailed.size()
	var detail_weight := 1.0-smoothstep(16.0,24.0,mpp) if use_detail else 0.0
	if use_detail:
		instances=0
		_building_opacity=building_strength*detail_weight
		for row: Dictionary in detailed: instances+=int(row.blocks)
	for node: MeshInstance3D in district_nodes: _opacity(node,_building_opacity)
	if building_strength>0.0 and detail_weight<1.0:
		var overview: Dictionary=_presentation.get("overview",{})
		if overview.has("path"):
			desired[str(overview.path)]=true
			var tone := Color(.40,.39,.34) if inspection_mesh else Color(.45,.45,.39)
			var node := _historical_part(view,str(overview.path),tone,false,true)
			var opacity := building_strength*(1.0-detail_weight)
			_opacity(node,opacity)
			if node!=null: _building_opacity+=opacity
		if not use_detail:
			instances=0
			for tile: Dictionary in _presentation.get("tiles",[]): instances+=int(tile.lods.get("overview",{}).get("blocks",0))
	elif not use_detail:
		instances=0
	for path: String in _parts.keys():
		var node := _parts[path] as MeshInstance3D
		if not desired.has(path):
			nodes.erase(node);_parts.erase(path);node.visible=false;node.mesh=null;node.queue_free()
			if _water_mesh_paths.has(path) or path.get_file().begins_with("district_"): _erase_mesh(path)
		else: node.transform=placement
	profile=data
	var area := extent(data);bounds=Rect2();var first := true
	for ll: Vector2 in [area.position,area.end,Vector2(area.end.x,area.position.y),Vector2(area.position.x,area.end.y)]:
		var pixel: Vector2=view.chart_screen_point(GlobeProjection.lon_lat_to_unit(ll),camera)
		bounds=Rect2(pixel,Vector2.ZERO) if first else bounds.expand(pixel);first=false
	render_bounds=Rect2(Vector2.ZERO,viewport_size)
	_trim_meshes()

func _metres(ll: Vector2, anchor: Vector2) -> Vector2:
	return (ll - anchor) * Vector2(111195.0 * cos(deg_to_rad(anchor.y)),111195.0)

func _river(data: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var anchor := Vector2(float(data.anchor[0]),float(data.anchor[1]))
	for raw: Array in data.get("river_lines", []):
		var line := PackedVector2Array()
		for point: Array in raw: line.append(_metres(Vector2(float(point[0]),float(point[1])),anchor))
		result.append(line)
	return result

func _read_water(data: Dictionary) -> void:
	_water_data = _profile(str(data.get("water_path", "")))
	_water_polygons.clear(); _water_banks.clear()
	var anchor := Vector2(float(data.anchor[0]),float(data.anchor[1]))
	for polygon: Dictionary in _water_data.get("polygons", []):
		var points := PackedVector2Array()
		for ll: Array in polygon.outer: points.append(_metres(Vector2(float(ll[0]),float(ll[1])),anchor))
		_water_polygons.append(points)
	for raw: Array in _water_data.get("banks", []):
		var points := PackedVector2Array()
		for ll: Array in raw: points.append(_metres(Vector2(float(ll[0]),float(ll[1])),anchor))
		_water_banks.append(points)

func _on_water(p: Vector2, margin: float) -> bool:
	for polygon: PackedVector2Array in _water_polygons:
		if Geometry2D.is_point_in_polygon(p,polygon): return true
	for bank: PackedVector2Array in _water_banks:
		for i: int in range(bank.size()-1):
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,bank[i],bank[i+1])) < margin*margin: return true
	return false

func _water_mesh(data: Dictionary) -> ArrayMesh:
	var anchor := Vector2(float(data.anchor[0]),float(data.anchor[1]))
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: Array = _water_data.get("vertices", [])
	for index: int in _water_data.get("indices", []):
		var v: Array = vertices[index]
		var p := _metres(Vector2(float(v[0]),float(v[1])),anchor)
		st.set_color(Color(.32,.46,.45))
		st.add_vertex(Vector3(p.x,2.0,-p.y))
	return st.commit()

func _bank_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Original open banks only. No stroke across a clipped data window.
	for line: PackedVector2Array in _water_banks:
		for i: int in range(line.size()-1):
			var a := line[i]; var b := line[i+1]
			var n := (b-a).normalized().orthogonal()*4.0
			var points: Array[Vector2] = [a-n,a+n,b+n,a-n,b+n,b-n]
			for p: Vector2 in points:
				st.set_color(Color(.38,.43,.36,.55))
				st.add_vertex(Vector3(p.x,2.1,-p.y))
			for side: float in [-1.0,1.0]:
				var fringe: Array[Vector2] = [a+n*side,b+n*side,b+n*side*3.0,a+n*side,b+n*side*3.0,a+n*side*3.0]
				for j: int in fringe.size():
					st.set_color(Color(.38,.43,.36,0.0 if j in [2,4,5] else .55))
					st.add_vertex(Vector3(fringe[j].x,2.1,-fringe[j].y))
	return st.commit()

func _prepare(data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var anchor := Vector2(float(data.anchor[0]),float(data.anchor[1]))
	var rivers := _river(data)
	for group: int in data.districts.size():
		var d: Dictionary = data.districts[group]
		var center := _metres(Vector2(float(d.anchor[0]),float(d.anchor[1])),anchor)
		for index: int in int(d.count):
			var turn: float = float(index) * 2.39996323 + float(group) * .73 + .15*sin(float(index)*5.31)
			var r: float = sqrt((float(index)+.5)/float(d.count)) * (.92+.08*sin(float(index)*2.13))
			var p := center + Vector2(cos(turn)*float(d.radius_m[0]),sin(turn)*float(d.radius_m[1])) * r
			var water := _on_water(p,125.0 if int(data.scale_grade)>2 else 28.0)
			for line: PackedVector2Array in rivers if _water_polygons.is_empty() else []:
				for i: int in range(line.size()-1):
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p,line[i],line[i+1]))<205: water = true; break
				if water: break
			if water: continue
			var size_factor: float = .8 + .4 * sin(float(index)*1.7 + float(group))
			var small: bool = int(data.scale_grade) <= 2
			var protected := false
			for point: Array in data.get("protected_points", []):
				if p.distance_to(_metres(Vector2(float(point[0]),float(point[1])),anchor))<180: protected=true; break
			if protected: continue
			rows.append({"p": p, "heading": deg_to_rad(float(d.heading)) + .38*sin(turn), "size": Vector3(34 if small else 165+35*r, 12 if small else 32+24*(1-r), 22 if small else 110+26*size_factor), "tone": .88+.12*size_factor, "group": group})
	return rows

func _mesh() -> ArrayMesh:
	if _block_mesh != null: return _block_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-.5,0,-.5); var b := Vector3(.5,0,-.5);var c := Vector3(.5,0,.5);var d := Vector3(-.5,0,.5)
	var e := Vector3(-.5,.65,-.5);var f := Vector3(.5,.65,-.5);var g := Vector3(.5,.65,.5);var h := Vector3(-.5,.65,.5)
	var r := Vector3(0,1,-.5);var s := Vector3(0,1,.5)
	var faces: Array = [[a,b,f,e],[b,c,g,f],[c,d,h,g],[d,a,e,h],[e,r,s,h],[r,f,g,s]]
	for module: int in 3:
		var scale := Vector3(.34,1,1) if module<2 else Vector3(.28,.72,.6)
		var offset := Vector3(-.33 if module==0 else .33 if module==1 else 0,0,0)
		for i: int in faces.size():
			var q: Array = faces[i]
			st.set_color(Color(.72,.66,.54) if i<4 else Color(.42,.34,.29))
			for v: Vector3 in [q[0],q[2],q[1],q[0],q[3],q[2]]: st.add_vertex(v*scale+offset)
		for triangle: Array in [[e,f,r],[h,s,g]]:
			st.set_color(Color(.75,.68,.55))
			for v: Vector3 in triangle: st.add_vertex(v*scale+offset)
	st.generate_normals()
	_block_mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_block_mesh.surface_set_material(0,material)
	return _block_mesh

func update(view: RefCounted, data: Dictionary, camera: RegionCamera, viewport_size: Vector2) -> void:
	if data.is_empty() or not camera.active or (not camera.local_active and not data.has("presentation_index")):
		if not nodes.is_empty(): clear()
		return
	if data.get("role","")=="NATIONAL_CARTOGRAPHIC_CONTEXT":
		_update_context(view,data,camera,viewport_size)
		return
	if data.has("presentation_index"):
		_update_historical(view,data,camera,viewport_size)
		return
	var id: String = str(data.id)
	if key != id:
		clear(); key = id
		_read_water(data)
		if not cached.has(id):
			if cached.size()>=2: cached.erase(cached.keys()[0])
			cached[id] = _prepare(data); build_count += 1
		layout.assign(cached[id])
		var multi := MultiMeshInstance3D.new()
		multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		multi.multimesh = MultiMesh.new()
		multi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multi.multimesh.use_colors = true
		multi.multimesh.mesh = _mesh()
		multi.multimesh.instance_count = layout.size()
		view._landmark_root.add_child(multi); nodes.append(multi)
		var anchor := Vector2(float(data.anchor[0]),float(data.anchor[1]))
		for index: int in layout.size():
			var row: Dictionary = layout[index]
			var ll := anchor + (row.p as Vector2)/Vector2(111195.0*cos(deg_to_rad(anchor.y)),111195.0)
			var y: float = 0.0 if data.get("ground_mode","")=="cartographic_plane" else view._surface_ground_y(ll)
			multi.multimesh.set_instance_transform(index,Transform3D(Basis(Vector3.UP,float(row.heading)).scaled(row.size),Vector3(row.p.x,y+1.0,-row.p.y)))
			multi.multimesh.set_instance_color(index,Color(float(row.tone),float(row.tone),float(row.tone)))
		instances = layout.size()
		var paint := SurfaceTool.new();paint.begin(Mesh.PRIMITIVE_TRIANGLES)
		for d: Dictionary in data.districts:
			var center := _metres(Vector2(float(d.anchor[0]),float(d.anchor[1])),anchor)
			var urban := Color(.56,.545,.47)
			var background := Color(.63,.62,.52)
			for sector: int in 24:
				var a: float = TAU*float(sector)/24.0
				var b: float = TAU*float(sector+1)/24.0
				var ra: Vector2 = Vector2(cos(a)*float(d.radius_m[0]),sin(a)*float(d.radius_m[1]))*(1+.08*sin(a*3))
				var rb: Vector2 = Vector2(cos(b)*float(d.radius_m[0]),sin(b)*float(d.radius_m[1]))*(1+.08*sin(b*3))
				var points: Array[Vector2] = [center,center+ra*.72,center+rb*.72,center+ra*.72,center+ra*1.08,center+rb*1.08,center+ra*.72,center+rb*1.08,center+rb*.72]
				for j: int in points.size():
					var p: Vector2 = points[j]
					var ll := anchor+p/Vector2(111195.0*cos(deg_to_rad(anchor.y)),111195.0)
					paint.set_color(background if j in [4,5,7] else urban)
					paint.add_vertex(Vector3(p.x,.8 if data.get("ground_mode","")=="cartographic_plane" else view._surface_ground_y(ll)+.8,-p.y))
		var ground := MeshInstance3D.new();ground.mesh=paint.commit();ground.material_override=_block_mesh.surface_get_material(0)
		view._landmark_root.add_child(ground);nodes.append(ground)
		var river := MeshInstance3D.new()
		if not _mesh_cache.has(id):
			if _mesh_cache.size()>=2: _mesh_cache.erase(_mesh_cache.keys()[0])
			_mesh_cache[id] = [_water_mesh(data),_bank_mesh()]
		river.mesh = _mesh_cache[id][0]; river.material_override=_block_mesh.surface_get_material(0)
		view._landmark_root.add_child(river); nodes.append(river)
		var bank := MeshInstance3D.new(); bank.mesh=_mesh_cache[id][1]
		var ink := (_block_mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		bank.material_override=ink
		view._landmark_root.add_child(bank);nodes.append(bank)
	profile=data
	var unit := GlobeProjection.lon_lat_to_unit(Vector2(float(data.anchor[0]),float(data.anchor[1])))
	var transform: Transform3D = view._chart_transform(unit,camera,viewport_size)
	for node: GeometryInstance3D in nodes: node.transform = transform
	bounds = Rect2()
	var first := true
	var area := extent(data)
	for ll: Vector2 in [area.position,area.end,Vector2(area.end.x,area.position.y),Vector2(area.position.x,area.end.y)]:
		var pixel: Vector2 = view.chart_screen_point(GlobeProjection.lon_lat_to_unit(ll),camera)
		bounds = Rect2(pixel,Vector2.ZERO) if first else bounds.expand(pixel)
		first = false
	render_bounds=bounds
	if not _water_data.is_empty():
		var box: Array = _water_data.bounds
		for ll: Vector2 in [Vector2(float(box[0]),float(box[1])),Vector2(float(box[2]),float(box[3])),Vector2(float(box[0]),float(box[3])),Vector2(float(box[2]),float(box[1]))]:
			render_bounds=render_bounds.expand(view.chart_screen_point(GlobeProjection.lon_lat_to_unit(ll),camera))
	render_bounds=render_bounds.grow(160.0/(camera.km_per_pixel*1000.0))
