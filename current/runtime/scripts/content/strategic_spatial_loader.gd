class_name StrategicSpatialLoader
extends RefCounted
signal content_changed
## Bounded Content slices on the existing evidence contracts, never Local support.
const INDEX_PATH: String = "res://data/strategic/index.json"
const MAX_ACTIVE_REGIONS: int = 2
const MEDIUM_LOD_MPP: float = 1500.0
var content: LocalSpatialContent
var errors: Array[String] = []
var failure: String = ""
var _index: Dictionary = {}
var _descriptors: Array[Dictionary] = []
var _thread: Thread
var _wanted: Array[String] = []
var _required_physical: Array[String] = []
var _physical_view: Array = []
var _physical_demands: Dictionary = {}
var _loading: Array[String] = []
var _request_mutex := Mutex.new()
var _request_generation: int = 0
var _loading_generation: int = 0
var _with_ink: bool = false
var _loading_with_ink: bool = false

func request(center: Vector2, radius_km: float, date: String, mpp: float = 4500.0, with_ink: bool = false, installed_physical: Dictionary = {}) -> bool:
	if _index.is_empty():
		_index = ContentDocument.read(INDEX_PATH, errors)
		for descriptor: Dictionary in _index.get("regions",[]) as Array: _descriptors.append(descriptor)
		for descriptor: Dictionary in _index.get("coast_regions",[]) as Array:
			_descriptors.append(descriptor)
			for child: Dictionary in descriptor.get("medium_regions",[]) as Array: _descriptors.append(child)
		for descriptor: Dictionary in _index.get("hydro_regions",[]) as Array: _descriptors.append(descriptor)
	if str(_index.get("schema_id", "")) != "global_strategic_index_r1" or _index.get("physical_foundation","")!="INDEPENDENT_NATURAL_EARTH_R27":
		release()
		return false
	var physical_view: Array = [center,radius_km]
	if physical_view!=_physical_view:
		_physical_view = physical_view
		_physical_demands.clear()
	var candidates: Array[Dictionary] = []
	var target_lod := "coarse" if mpp>MEDIUM_LOD_MPP else "medium"
	for descriptor: Dictionary in _index.get("regions", []) as Array:
		if date<str(_index.valid_from) or date>=str(_index.valid_to): continue
		# The immutable WORLD foundation already owns all physical shards. Its
		# sourced natural lakes must exist before a close camera can reuse it.
		# Regional enrichment remains capped below; no rivers/places preload.
		if target_lod=="coarse":
			candidates.append({"id":descriptor.id,"distance":0.0})
			continue
		var bounds := descriptor.bounds as Array
		var latitude_padding := minf(90.0, radius_km / 111.195)
		var longitude_padding := minf(180.0, latitude_padding / maxf(0.1, cos(deg_to_rad(center.y))))
		if absf(center.y)+latitude_padding>=90.0: longitude_padding = 180.0
		if not _intersects(bounds,center,latitude_padding,longitude_padding):
			continue
		var anchor := descriptor.anchor as Array
		var delta := Vector2(wrapf(float(anchor[0]) - center.x, -180.0, 180.0) * cos(deg_to_rad(center.y)), float(anchor[1]) - center.y)
		candidates.append({"id": descriptor.id, "distance": delta.length_squared()})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var wanted: Array[String] = []
	for candidate: Dictionary in (candidates if target_lod=="coarse" else candidates.slice(0, MAX_ACTIVE_REGIONS)):
		wanted.append(str(candidate.id))
	# Fixed display packing only. Wrapped copies select date-line neighbours;
	# no region, ownership or administrative identities are manufactured.
	var coast_wanted := physical_demand(target_lod)
	# Select the geographic cap, including polar and date-line neighbours.
	# Never truncate visible physical coverage by an arbitrary first-N list.
	_required_physical.assign(coast_wanted)
	_required_physical.sort()
	var installed_regions := installed_physical.get("regions",[]) as Array
	var prepared_ink := true
	for descriptor: Dictionary in _descriptors:
		if str(descriptor.id) in coast_wanted and not descriptor.has("compiled_asset"): prepared_ink = false; break
	if with_ink and not prepared_ink and (str(installed_physical.get("lod",""))!=target_lod or not coast_wanted.all(func(id: String) -> bool: return id in installed_regions)):
		# A previous hemisphere is not proof that this demand has a base map.
		# Finish physical coverage before enriching the same installed package.
		with_ink = false
	# Optional modern hydrography never participates in physical completeness.
	# A detail view requests every intersecting core together, or stays on its
	# complete overview. This bounds residency without exposing cut river ends.
	if with_ink and not installed_physical.is_empty() and mpp<=2500.0:
		var detail: Array[String] = []
		for descriptor: Dictionary in _index.get("hydro_regions",[]) as Array:
			if not _physical_intersects(descriptor.bounds as Array,center,radius_km): continue
			if bool(descriptor.get("detail",false)):
				if mpp<=float(descriptor.get("max_mpp",500.0)): detail.append(str(descriptor.id))
			else: wanted.append(str(descriptor.id))
		if detail.size()<=4: wanted.append_array(detail)
	wanted.append_array(coast_wanted)
	wanted.sort()
	if wanted.is_empty():
		release()
		return false
	if wanted == _wanted and with_ink==_with_ink and (content != null or _thread != null or not failure.is_empty()):
		return true
	# Keep a bounded completed/in-flight window while it still contains the
	# entire demand. A smaller view does not invalidate the same physical work.
	var hydro_ids: Array = (_index.get("hydro_regions",[]) as Array).map(func(descriptor: Dictionary) -> String: return str(descriptor.id))
	var same_hydro := wanted.filter(func(id: String) -> bool: return id in hydro_ids)==_wanted.filter(func(id: String) -> bool: return id in hydro_ids)
	if same_hydro and with_ink==_with_ink and failure.is_empty() and (content!=null or _thread!=null) and wanted.all(func(id: String) -> bool: return id in _wanted):
		return true
	_wanted = wanted
	_with_ink = with_ink
	failure = ""
	errors.clear()
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()
	_start()
	return true

static func _intersects(bounds: Array, center: Vector2, lat_padding: float, lon_padding: float) -> bool:
	if center.y+lat_padding < float(bounds[2]) or center.y-lat_padding > float(bounds[3]): return false
	for shift: float in [-360.0,0.0,360.0]:
		if center.x+lon_padding>=float(bounds[0])+shift and center.x-lon_padding<=float(bounds[1])+shift: return true
	return false

static func _physical_intersects(bounds: Array, center: Vector2, radius_km: float) -> bool:
	# Closest point on a lon/lat rectangle to the existing spherical demand cap.
	# A polar cap crosses every longitude, but not every latitude at every lon.
	var latitude := deg_to_rad(center.y)
	var best := -1.0
	for shift: float in [-360.0,0.0,360.0]:
		var longitude := clampf(center.x,float(bounds[0])+shift,float(bounds[1])+shift)
		var meridian := cos(deg_to_rad(longitude-center.x))
		var closest := clampf(atan2(sin(latitude),cos(latitude)*meridian),deg_to_rad(float(bounds[2])),deg_to_rad(float(bounds[3])))
		best = maxf(best,sin(latitude)*sin(closest)+cos(latitude)*cos(closest)*meridian)
	return acos(clampf(best,-1.0,1.0))<=radius_km/6371.0088+0.000001

func _start(retired: LocalSpatialContent = null) -> void:
	if _thread != null or _wanted.is_empty():
		return
	_loading = _wanted.duplicate()
	_loading_generation = _request_generation
	_loading_with_ink = _with_ink
	if retired == null: retired = content
	content = null
	_thread = Thread.new()
	var descriptors: Array[Dictionary] = []
	var lake_only := not _with_ink or not _loading.any(func(id: String) -> bool: return id.begins_with("physical_") and "_mid_" in id)
	for descriptor: Dictionary in _descriptors:
		if str(descriptor.id) in _loading:
			var selected := descriptor.duplicate()
			if lake_only and str(descriptor.id) in (_index.regions as Array).map(func(row: Dictionary) -> String: return str(row.id)): selected["natural_lakes_only"] = true
			descriptors.append(selected)
	var error := _thread.start(_load.bind(_index, descriptors, _request_current.bind(_request_generation), retired,_with_ink))
	if error!=OK:
		_thread = null
		failure = "无法启动物理地图读取线程："+error_string(error)
		errors.append(failure)
		content_changed.emit()

func _request_current(generation: int) -> bool:
	_request_mutex.lock()
	var current := generation == _request_generation
	_request_mutex.unlock()
	return current

func preparing() -> bool:
	return _thread != null

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var returned: Variant = _thread.wait_to_finish()
	_thread = null
	var stale := _loading != _wanted or _loading_generation != _request_generation or _loading_with_ink!=_with_ink
	if stale:
		_start(returned as LocalSpatialContent if returned is LocalSpatialContent else null)
		return false
	if not returned is LocalSpatialContent:
		failure = "物理地图线程未返回有效内容。"
		errors.append(failure)
		content_changed.emit()
		return true
	var result := returned as LocalSpatialContent
	if result.cancelled:
		failure = "当前物理地图请求意外结束，未安装不完整分片。"
	elif not result.errors.is_empty(): failure = "\n".join(result.errors)
	if not failure.is_empty():
		errors.append(failure)
		content_changed.emit()
		return true
	content = result
	content_changed.emit()
	return true

func release() -> void:
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()
	_wanted.clear()
	_required_physical.clear()
	_physical_view.clear()
	_physical_demands.clear()
	content = null
	failure = ""

func dispose() -> void:
	release()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

static func _load(index: Dictionary, descriptors: Array[Dictionary], current: Callable = Callable(), retired: LocalSpatialContent = null, with_ink: bool = false, features_only: bool = false) -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	# The installed layer may still read this content or prepare another LOD.
	# Borrow immutable shard references; its owner retires the old input.
	var previous_shards: Dictionary = {}
	var previous_ink: bool = false
	var previous_lake_shards: Array = []
	if retired != null:
		retired.geometry_mutex.lock()
		previous_shards = retired.shards
		previous_ink = bool(retired.metadata.get("ink_enabled",false))
		previous_lake_shards = retired.metadata.get("natural_lake_shards",[]) as Array
		if previous_ink and not with_ink: previous_shards = {}
		retired.geometry_mutex.unlock()
	result.metadata = {"content_level": "strategic", "valid_from": index.valid_from, "valid_to": index.valid_to, "physical_foundation":true,"ink_enabled":with_ink,"local_support": false, "presentation_lods": ["coarse", "medium"], "regions": descriptors.map(func(descriptor: Dictionary) -> String: return str(descriptor.id))}
	result.metadata["natural_lake_shards"] = descriptors.filter(func(row: Dictionary) -> bool: return bool(row.get("natural_lakes_only",false))).map(func(row: Dictionary) -> String: return str(row.id))
	var ids: Dictionary = {}
	var geometry_assets: Dictionary = {}
	for descriptor: Dictionary in descriptors:
		if current.is_valid() and not current.call():
			result.features.clear()
			result.cancelled = true
			return result
		var shard_id := str(descriptor.id)
		if previous_shards.has(shard_id) and (shard_id in previous_lake_shards)==bool(descriptor.get("natural_lakes_only",false)):
			var cached := previous_shards[shard_id] as Array
			if with_ink and not previous_ink and descriptor.has("compiled_asset"):
				cached = cached.map(func(feature: Dictionary) -> Dictionary:
					var copy := feature.duplicate()
					copy["compiled_descriptor"] = descriptor
					copy["lod_geometry"] = {}
					return copy)
			elif with_ink and not previous_ink and descriptor.has("ink_asset"):
				var partition := _read_ink(descriptor)
				if partition.has("error"):
					_note_optional_error(result,str(partition.error))
				else:
					cached = cached.map(func(feature: Dictionary) -> Dictionary:
						var copy := feature.duplicate()
						if str(copy.kind)=="land_reference": _bind_ink(copy,partition)
						return copy)
			result.shards[shard_id] = cached
			for feature: Dictionary in cached:
				if ids.has(str(feature.id)):
					result.errors.append("Duplicate strategic feature: "+str(feature.id))
					return result
				ids[str(feature.id)] = true
				result.features.append(feature)
			continue
		# The current physical/ink package is mandatory. Regional settlement,
		# railway and river supplements are optional; a broken supplement must
		# not be published partially or prevent the physical map from opening.
		if not features_only and not shard_id.begins_with("physical_"):
			var supplemental := _load(index,[descriptor],current,null,with_ink,true)
			if supplemental.cancelled:
				result.cancelled = true
				return result
			if not supplemental.errors.is_empty():
				if bool(descriptor.get("natural_lakes_only",false)):
					result.errors.append_array(supplemental.errors)
					return result
				if not result.metadata.has("optional_errors"): result.metadata["optional_errors"] = []
				(result.metadata.optional_errors as Array).append(shard_id+"："+"; ".join(supplemental.errors))
				continue
			for feature: Dictionary in supplemental.features:
				if ids.has(str(feature.id)):
					result.errors.append("Duplicate strategic feature: "+str(feature.id))
					return result
				ids[str(feature.id)] = true
				result.features.append(feature)
			result.shards[shard_id] = supplemental.features
			continue
		var shard_features: Array[Dictionary] = []
		var bytes := FileAccess.get_file_as_bytes(str(descriptor.path))
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
			result.errors.append("Invalid strategic JSON: " + str(descriptor.id))
			return result
		var document := parser.data as Dictionary
		if str((document.get("metadata", {}) as Dictionary).get("schema_id", "")) != "global_strategic_content_r1":
			result.errors.append("Unsupported strategic shard: " + str(descriptor.id))
			return result
		var sources := HistoricalSourceRegistry.new()
		var facts := HistoricalEvidenceCatalog.new()
		if not sources.load_document(document.get("source_registry", {}) as Dictionary) or not facts.load_document(document.get("evidence_catalog", {}) as Dictionary):
			result.errors.append_array(sources.errors())
			result.errors.append_array(facts.errors())
			return result
		var gate := HistoricalProvenanceGate.new(sources, facts)
		var ink: Dictionary = {}
		if with_ink and descriptor.has("ink_asset") and not descriptor.has("compiled_asset"):
			ink = _read_ink(descriptor)
			if ink.has("error"):
				_note_optional_error(result,str(ink.error))
				ink = {}
		for fact_id: String in facts.fact_ids():
			if current.is_valid() and not current.call():
				result.features.clear()
				result.cancelled = true
				return result
			var fact := facts.fact(fact_id)
			if not fact.value is Dictionary or not gate.admit_runtime_fact(fact_id, fact.domain, fact.output_material()):
				result.errors.append("Unadmitted strategic fact: " + fact_id)
				return result
			var feature := (fact.value as Dictionary).duplicate()
			if bool(descriptor.get("natural_lakes_only",false)) and str(feature.get("kind",""))!="lake": continue
			if not LocalSpatialContent.historical_rail_alignment(feature): continue
			if feature.has("geometry_asset"):
				var asset := feature.geometry_asset as Dictionary
				var path := str(asset.get("path", ""))
				if not path.begins_with("res://data/strategic/") or path.simplify_path() != path or str(asset.get("encoding", "")) != "ZLIB_JSON_UTF8":
					result.errors.append("Invalid strategic geometry descriptor: " + fact_id)
					return result
				if not geometry_assets.has(path):
					var packed := FileAccess.get_file_as_bytes(path)
					var decoded := packed.decompress_dynamic(33554432, FileAccess.COMPRESSION_DEFLATE)
					var geometry_parser := JSON.new()
					if decoded.is_empty() or geometry_parser.parse(decoded.get_string_from_utf8()) != OK or not geometry_parser.data is Dictionary:
						result.errors.append("Invalid strategic geometry payload: " + path)
						return result
					geometry_assets[path] = geometry_parser.data
				var bound := geometry_assets[path] as Dictionary
				if not bound.has(str(feature.id)):
					result.errors.append("Missing strategic feature geometry: " + fact_id)
					return result
				var geometry_value := bound[str(feature.id)] as Dictionary
				if geometry_value.size()!=2 or not geometry_value.get("geometry") is Dictionary or not geometry_value.get("lod_geometry") is Dictionary:
					result.errors.append("Invalid strategic geometry fields: " + fact_id)
					return result
				feature["geometry"] = geometry_value.geometry
				feature["lod_geometry"] = geometry_value.lod_geometry
				# Optional cross-source draw replacements are prepared offline in
				# this same bounded native pack. They never replace query geometry,
				# land, political ink, or an immutable cached source shard.
				var display_overrides: Dictionary = {}
				for old_id: String in feature.get("display_override_ids",[]) as Array:
					var replacement := bound.get(old_id,{}) as Dictionary
					if replacement.size()!=2 or not replacement.get("lod_geometry") is Dictionary:
						result.errors.append("Missing prepared water display override: "+old_id)
						return result
					display_overrides[old_id] = replacement.lod_geometry
				if not display_overrides.is_empty(): feature["display_overrides_data"] = display_overrides
			var native_display := with_ink and descriptor.has("compiled_asset")
			if ids.has(str(feature.get("id", ""))) or not valid_feature(feature,native_display) or fact.subject_id != str(feature.id) or fact.source_id != str(feature.source_id):
				result.errors.append("Invalid/duplicate strategic feature: " + fact_id)
				return result
			ids[str(feature.id)] = true
			if str(feature.kind)=="land_reference" and not ink.is_empty():
				# The physical polygon stays unchanged. Only its draw tessellation
				# is partitioned by an optional, separately sourced ink description.
				_bind_ink(feature,ink)
			if str(feature.kind)=="land_reference": feature["land_query"] = _land_query(feature.geometry as Dictionary)
			if with_ink and descriptor.has("compiled_asset"):
				feature["compiled_descriptor"] = descriptor
				# Queries retain the actual physical polygon; display triangles
				# live in the packed draw asset and are not held twice in Content.
				feature["lod_geometry"] = {}
				var source_path := str((feature.get("geometry_asset",{}) as Dictionary).get("path",""))
				if geometry_assets.has(source_path): (geometry_assets[source_path] as Dictionary).erase(str(feature.id))
			result.features.append(feature)
			shard_features.append(feature)
		result.shards[shard_id] = shard_features
	if features_only: return result
	# A validated optional display replacement owns its own outside-scope
	# remainders. Only then suppress the older coarse strokes/polygons. The
	# immutable source shards and all formal geographic identities stay intact.
	var replaced: Array[String] = []
	for feature: Dictionary in result.features:
		for id: String in feature.get("display_replaces",[]) as Array:
			if id not in replaced: replaced.append(id)
	if not replaced.is_empty():
		result.features = result.features.filter(func(feature: Dictionary) -> bool: return str(feature.id) not in replaced)
	var water_overrides: Dictionary = {}
	for feature: Dictionary in result.features:
		water_overrides.merge(feature.get("display_overrides_data",{}) as Dictionary,true)
	for feature_index: int in range(result.features.size()):
		var feature := result.features[feature_index] as Dictionary
		if str(feature.kind) not in ["river","lake"] or str(feature.get("source_type",""))!="PHYSICAL_REFERENCE" or not water_overrides.has(str(feature.id)): continue
		var replacement := water_overrides[str(feature.id)] as Dictionary
		for lod: String in feature.get("presentation_lods",["coarse","medium"]) as Array:
			if not replacement.get(lod) is Array:
				result.errors.append("Invalid water display override LOD: "+str(feature.id))
				return result
			var raw := replacement[lod] as Array
			if not raw.is_empty() and not _valid_geometry(str(feature.kind),{"type":(feature.geometry as Dictionary).type,"coordinates":raw},str(feature.get("geometry_role",""))):
				result.errors.append("Invalid water display override geometry: "+str(feature.id))
				return result
		var display := feature.duplicate()
		display["lod_geometry"] = replacement
		result.features[feature_index] = display
	var compiled_paths: Dictionary = {}
	for feature: Dictionary in result.features:
		if current.is_valid() and not current.call():
			result.features.clear()
			result.line_chunks.clear()
			result.cancelled = true
			return result
		if str(feature.kind) == "settlement":
			continue
		if str(feature.get("geometry_role",""))=="INDEPENDENT_PHYSICAL_WATER_MASK": continue
		if feature.has("compiled_descriptor"):
			var descriptor := feature.compiled_descriptor as Dictionary
			var id := str(descriptor.id)
			if not compiled_paths.has(id):
				compiled_paths[id] = true
				var raw_bounds := descriptor.bounds as Array
				result.line_chunks.append({"kind":"compiled_physical","lod":descriptor.lod,"shard_id":id,"compiled_asset":descriptor.compiled_asset,"ink_descriptor":descriptor,"land_feature_id":"land_reference:"+id,"bounds":Rect2(Vector2(float(raw_bounds[0]),float(raw_bounds[2])),Vector2(float(raw_bounds[1])-float(raw_bounds[0]),float(raw_bounds[3])-float(raw_bounds[2])))})
			continue
		for lod: String in feature.get("presentation_lods", ["coarse", "medium"]) as Array:
			var raw: Array = (feature.lod_geometry as Dictionary).get(lod, []) as Array
			var tolerance := float((feature.get("lod_tolerance_m", {}) as Dictionary).get(lod,5000.0 if lod=="coarse" else 1500.0))
			if str(feature.kind) == "rail":
				raw = [raw]
			elif str(feature.kind) in ["lake", "land_reference", "ocean_reference"]:
				result.line_chunks.append({"kind": feature.kind, "lod": lod, "tolerance_m": tolerance, "polygons": raw, "feature_id": feature.id, "source_geometry_file": feature.get("source_geometry_file", ""), "lod_geometry_role":feature.get("lod_geometry_role",""),"ink_references":feature.get("ink_references",[]),"ink_indices":feature.get("ink_indices",[]),"water_class":feature.get("water_class","")})
				continue
			var boundaries: Array[Dictionary] = []
			for line: Array in raw:
				var points := PackedVector3Array()
				var geographic := PackedVector2Array()
				for coordinate: Array in line:
					if str(feature.kind)=="coast": geographic.append(Vector2(float(coordinate[0]),float(coordinate[1])))
					var lon := deg_to_rad(float(coordinate[0]))
					var lat := deg_to_rad(float(coordinate[1]))
					points.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
				if str(feature.kind)=="coast": points = GlobeProjection.display_line(geographic)
				if points.size() >= 2:
					if str(feature.kind)=="coast":
						var loop := points.size()>2 and points[0]==points[-1]
						# Match the existing Local line packing: bound an individual
						# upload even when a source continental ring is very long.
						for first: int in range(0,points.size()-1,128):
							var end := mini(first+128,points.size()-1)
							var segment := {"kind":feature.kind,"points":points.slice(first,end+1),"feature_id":feature.id,"source_fact_id":"strategic_spatial:"+str(feature.id)}
							if first>0: segment["before"] = points[first-1]
							elif loop: segment["before"] = points[-2]
							if end<points.size()-1: segment["after"] = points[end+1]
							elif loop: segment["after"] = points[1]
							boundaries.append(segment)
					else:
						boundaries.append({"kind": feature.kind, "points": points, "feature_id": feature.id, "source_fact_id": "strategic_spatial:" + str(feature.id)})
			result.line_chunks.append({"kind": feature.kind, "lod": lod, "tolerance_m": tolerance, "boundaries": boundaries,"feature_id":feature.id,"stroke_scale":float(feature.get("stroke_scale",1.0)),"water_line_style":str(feature.get("water_line_style",""))})
	result.has_content = not result.features.is_empty()
	return result

static func _note_optional_error(result: LocalSpatialContent, message: String) -> void:
	if not result.metadata.has("optional_errors"): result.metadata["optional_errors"] = []
	(result.metadata.optional_errors as Array).append(message)

static func _land_query(geometry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for polygon: Array in geometry.coordinates:
		var rings: Array[PackedVector2Array] = []
		for raw: Array in polygon:
			var ring := PackedVector2Array()
			for point: Array in raw: ring.append(Vector2(float(point[0]),float(point[1])))
			rings.append(ring)
		result.append({"rings":rings,"bounds":GlobeProjection.lon_lat_bounds([rings[0]])})
	return result

static func _read_ink(descriptor: Dictionary) -> Dictionary:
	var id := str(descriptor.id)
	var bytes := FileAccess.get_file_as_bytes(str(descriptor.ink_asset.path)).decompress_dynamic(33554432,FileAccess.COMPRESSION_DEFLATE)
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK or not parser.data is Dictionary:
		return {"error":"Invalid political ink partition: "+id}
	var ink := parser.data as Dictionary
	if ink.get("schema_id")!="physical_political_ink_partition_r27" or ink.get("physical_shard_id")!=id or ink.get("lod")!=descriptor.get("lod") or ink.get("role")!="DISPLAY_INTERSECTION_ONLY_NOT_SOVEREIGNTY" or not ink.get("triangles") is Array or not ink.get("indices") is Array or not ink.get("references") is Array or (ink.triangles as Array).size()!=(ink.indices as Array).size():
		return {"error":"Unsupported political ink partition: "+id}
	for value: Variant in ink.indices:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or float(value)!=floorf(float(value)) or int(value)<0 or int(value)>=(ink.references as Array).size(): return {"error":"Invalid ink reference index: "+id}
	if not _valid_geometry("land_reference",{"type":"MultiPolygon","coordinates":ink.triangles},""):
		return {"error":"Invalid ink triangles: "+id}
	return ink

static func read_display(asset: Dictionary, id: String, lod: String) -> Dictionary:
	var path := str(asset.get("path",""))
	if not path.begins_with("res://data/strategic/") or path.simplify_path()!=path or asset.get("encoding")!="GODOT_COMPRESSED_VARIANT_R37": return {"error":"政治显示资源描述无效："+id}
	var file := FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_DEFLATE)
	if file==null: return {"error":"无法读取预制政治显示："+id+" / "+error_string(FileAccess.get_open_error())}
	var value: Variant = file.get_var(false)
	if not value is Dictionary: return {"error":"预制政治显示内容无效："+id}
	var display := value as Dictionary
	if display.get("schema_id")!="physical_political_display_r37" or display.get("physical_shard_id")!=id or display.get("lod")!=lod or not display.get("chunks") is Array: return {"error":"预制政治显示不属于当前物理分片："+id}
	var geometry_path := str(asset.get("source_geometry","res://data/strategic/"+id+".geom"))
	if not geometry_path.begins_with("res://data/strategic/") or geometry_path.simplify_path()!=geometry_path or display.get("source_geometry")!=geometry_path or display.get("role")!="DISPLAY_ONLY_NOT_SOVEREIGNTY" or display.get("component_uv")!=true: return {"error":"预制政治显示来源或用途不匹配："+id}
	for chunk: Dictionary in display.chunks as Array:
		if str(chunk.get("lod",""))!=lod or str(chunk.get("kind","")) not in ["land_reference","coast"] or not chunk.get("payload") is Dictionary: return {"error":"预制政治批次不完整："+id}
	return display

static func _bind_ink(feature: Dictionary, ink: Dictionary) -> void:
	feature["lod_geometry"] = {str(ink.lod):ink.triangles}
	feature["ink_references"] = ink.references
	feature["ink_indices"] = ink.indices

func physical_demand(lod: String = "") -> Array[String]:
	# Coarse is the finite global foundation. Medium remains a geographic cap.
	if lod.is_empty(): return _required_physical.duplicate()
	if lod=="coarse":
		var global_ids: Array[String] = []
		for descriptor: Dictionary in _index.get("coast_regions",[]) as Array: global_ids.append(str(descriptor.id))
		global_ids.sort()
		return global_ids
	if _physical_view.is_empty() or lod not in ["coarse","medium"]: return []
	if not _physical_demands.has(lod):
		var selected: Array[String] = []
		var center := _physical_view[0] as Vector2
		var radius := float(_physical_view[1])
		for descriptor: Dictionary in _index.get("coast_regions",[]) as Array:
			if not _physical_intersects(descriptor.bounds as Array,center,radius): continue
			if lod=="coarse": selected.append(str(descriptor.id))
			else:
				for child: Dictionary in descriptor.get("medium_regions",[]) as Array:
					if _physical_intersects(child.bounds as Array,center,radius): selected.append(str(child.id))
		selected.sort()
		_physical_demands[lod] = selected
	# These are IDs only. Testing an installed coarse LOD reads no geometry
	# and does not request a second set of map files or GPU objects.
	return (_physical_demands[lod] as Array[String]).duplicate()

static func valid_feature(feature: Dictionary, native_display: bool = false) -> bool:
	if str(feature.get("id", "")).is_empty() or feature.has("owner") or feature.has("controller_id") or feature.has("polity_id") or feature.has("administrative_region_id"):
		return false
	if str(feature.get("kind", "")) not in ["settlement", "rail", "river", "coast", "lake", "land_reference", "ocean_reference"] or not HistoricalFactEvidence.valid_date(str(feature.get("valid_from", ""))) or not HistoricalFactEvidence.valid_date(str(feature.get("valid_to", ""))) or str(feature.valid_from) >= str(feature.valid_to):
		return false
	var geometry := feature.get("geometry", {}) as Dictionary
	var kind := str(feature.kind)
	if kind=="land_reference" and (feature.get("geometry_role")!="INDEPENDENT_PHYSICAL_LAND" or feature.get("source_type")!="PHYSICAL_REFERENCE" or feature.get("lod_geometry_role")!="PRECOMPUTED_DISPLAY_TRIANGLES"): return false
	if kind=="ocean_reference" and (feature.get("geometry_role")!="INDEPENDENT_PHYSICAL_WATER_MASK" or feature.get("source_type")!="PHYSICAL_REFERENCE" or feature.get("lod_geometry_role")!="REFERENCE_MASK_ONLY"): return false
	if kind != "settlement":
		if not feature.get("lod_geometry") is Dictionary: return false
		var lods := feature.get("presentation_lods", ["coarse", "medium"]) as Array
		if lods.is_empty() or lods.size()>2 or lods.size()!=(feature.lod_geometry as Dictionary).size(): return false
		for lod: String in lods:
			if lod not in ["coarse","medium"]: return false
			if not (feature.lod_geometry as Dictionary).get(lod) is Array: return false
			var raw := (feature.lod_geometry as Dictionary).get(lod, []) as Array
			if kind=="ocean_reference":
				if not raw.is_empty(): return false
				continue
			# These legacy draw triangles are immediately discarded on the native
			# path. Validate the physical/query geometry below and the actual
			# native payload at read_display/upload, rather than walking both.
			if native_display and kind in ["land_reference","coast"]: continue
			if not _valid_geometry(kind,{"type":geometry.get("type", ""),"coordinates":raw},str(feature.get("geometry_role", ""))): return false

	return _valid_geometry(kind,geometry,str(feature.get("geometry_role", "")))

static func _valid_geometry(kind: String, geometry: Dictionary, role: String) -> bool:
	if not geometry.get("coordinates") is Array: return false
	var coordinates := geometry.coordinates as Array
	if coordinates.is_empty(): return false
	var lines: Array = []
	match kind:
		"settlement":
			if str(geometry.get("type","")) != "Point": return false
			lines = [[coordinates]]
		"rail":
			if str(geometry.get("type","")) != "LineString" or coordinates.size()<2 or role!="APPROXIMATE_STRATEGIC_CORRIDOR": return false
			lines = [coordinates]
		"river", "coast":
			if str(geometry.get("type","")) != "MultiLineString": return false
			lines = coordinates
		"lake", "land_reference", "ocean_reference":
			if str(geometry.get("type","")) != "MultiPolygon": return false
			for polygon: Variant in coordinates:
				if not polygon is Array or (polygon as Array).is_empty(): return false
				for ring: Variant in polygon:
					if not ring is Array or (ring as Array).size()<4 or ring[0]!=ring[-1]: return false
					lines.append(ring)
		_: return false
	# Known geometry depth permits one point pass, without recursive Variant
	# dispatch at every coordinate. Finite/range/type checks still run at admission.
	for raw_line: Variant in lines:
		if not raw_line is Array or (raw_line as Array).is_empty(): return false
		var line := raw_line as Array
		if kind in ["river","coast"] and line.size()<2: return false
		var distinct := false
		for raw_point: Variant in line:
			if not raw_point is Array: return false
			var point := raw_point as Array
			if point.size()!=2 or typeof(point[0]) not in [TYPE_INT,TYPE_FLOAT] or typeof(point[1]) not in [TYPE_INT,TYPE_FLOAT]: return false
			var lon := float(point[0])
			var lat := float(point[1])
			if not is_finite(lon) or not is_finite(lat) or absf(lon)>180.0 or absf(lat)>90.0: return false
			distinct = distinct or point!=line[0]
		if kind in ["river","coast"] and not distinct: return false
	return true
