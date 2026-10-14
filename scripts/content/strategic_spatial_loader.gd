class_name StrategicSpatialLoader
extends RefCounted
signal content_changed
## Bounded Content slices on the existing evidence contracts, never Local support.
const INDEX_PATH: String = "res://data/strategic/index.json"
const MAX_ACTIVE_REGIONS: int = 2
const MAX_ACTIVE_COAST_REGIONS: int = 64
const MEDIUM_LOD_MPP: float = 1500.0
var content: LocalSpatialContent
var errors: Array[String] = []
var _index: Dictionary = {}
var _descriptors: Array[Dictionary] = []
var _thread: Thread
var _wanted: Array[String] = []
var _loading: Array[String] = []
var _request_mutex := Mutex.new()
var _request_generation: int = 0
var _loading_generation: int = 0

func request(center: Vector2, radius_km: float, date: String, mpp: float = 4500.0) -> bool:
	if _index.is_empty():
		_index = ContentDocument.read(INDEX_PATH, errors)
		for descriptor: Dictionary in _index.get("regions",[]) as Array: _descriptors.append(descriptor)
		for descriptor: Dictionary in _index.get("coast_regions",[]) as Array:
			_descriptors.append(descriptor)
			for child: Dictionary in descriptor.get("medium_regions",[]) as Array: _descriptors.append(child)
	if str(_index.get("schema_id", "")) != "global_strategic_index_r1" or date < str(_index.get("valid_from", "")) or date >= str(_index.get("valid_to", "")):
		release()
		return false
	var candidates: Array[Dictionary] = []
	for descriptor: Dictionary in _index.get("regions", []) as Array:
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
	for candidate: Dictionary in candidates.slice(0, MAX_ACTIVE_REGIONS):
		wanted.append(str(candidate.id))
	# Fixed display packing only. Wrapped copies select date-line neighbours;
	# no region, ownership or administrative identities are manufactured.
	var coast_wanted: Array[String] = []
	var lat_padding := minf(90.0, radius_km / 111.195)
	var lon_padding := minf(180.0, lat_padding / maxf(0.1, cos(deg_to_rad(center.y))))
	if absf(center.y)+lat_padding>=90.0: lon_padding = 180.0
	for descriptor: Dictionary in _index.get("coast_regions", []) as Array:
		if mpp>8500.0 or not _intersects(descriptor.bounds as Array,center,lat_padding,lon_padding): continue
		if mpp>MEDIUM_LOD_MPP:
			coast_wanted.append(str(descriptor.id))
		else:
			for child: Dictionary in descriptor.get("medium_regions", []) as Array:
				if _intersects(child.bounds as Array,center,lat_padding,lon_padding): coast_wanted.append(str(child.id))
	# Conservative polar coverage spans all longitudes; never truncate an
	# ordinary viewport by nearest city, and never load hidden coarse detail.
	coast_wanted = coast_wanted.slice(0, MAX_ACTIVE_COAST_REGIONS)
	wanted.append_array(coast_wanted)
	wanted.sort()
	if wanted.is_empty():
		release()
		return false
	if wanted == _wanted and (content != null or _thread != null):
		return true
	_wanted = wanted
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

func _start(retired: LocalSpatialContent = null) -> void:
	if _thread != null or _wanted.is_empty():
		return
	_loading = _wanted.duplicate()
	_loading_generation = _request_generation
	if retired == null: retired = content
	content = null
	_thread = Thread.new()
	var descriptors: Array[Dictionary] = []
	for descriptor: Dictionary in _descriptors:
		if str(descriptor.id) in _loading: descriptors.append(descriptor)
	_thread.start(_load.bind(_index, descriptors, _request_current.bind(_request_generation), retired))

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
	var result := _thread.wait_to_finish() as LocalSpatialContent
	_thread = null
	if _loading != _wanted or _loading_generation != _request_generation or result.cancelled:
		_start(result)
		return false
	content = result
	errors.append_array(result.errors)
	content_changed.emit()
	return true

func release() -> void:
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()
	_wanted.clear()
	content = null

func dispose() -> void:
	release()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

static func _load(index: Dictionary, descriptors: Array[Dictionary], current: Callable = Callable(), retired: LocalSpatialContent = null) -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	# The previous display has its own GPU batches and settlement dictionaries.
	# Drop its generic source arrays on this existing Content worker. Replace
	# the arrays; an in-flight LOD worker can finish reading its held references.
	var previous_shards: Dictionary = {}
	if retired != null:
		retired.geometry_mutex.lock()
		retired.cancelled = true
		previous_shards = retired.shards
		retired.shards = {}
		retired.features = []
		retired.line_chunks = []
		retired.geometry_mutex.unlock()
	result.metadata = {"content_level": "strategic", "valid_from": index.valid_from, "valid_to": index.valid_to, "local_support": false, "presentation_lods": ["coarse", "medium"], "regions": descriptors.map(func(descriptor: Dictionary) -> String: return str(descriptor.id))}
	var ids: Dictionary = {}
	var geometry_assets: Dictionary = {}
	for descriptor: Dictionary in descriptors:
		if current.is_valid() and not current.call():
			result.features.clear()
			result.cancelled = true
			return result
		var shard_id := str(descriptor.id)
		if previous_shards.has(shard_id):
			var cached := previous_shards[shard_id] as Array
			result.shards[shard_id] = cached
			for feature: Dictionary in cached:
				if ids.has(str(feature.id)):
					result.errors.append("Duplicate strategic feature: "+str(feature.id))
					return result
				ids[str(feature.id)] = true
				result.features.append(feature)
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
				if geometry_value.size() not in [2,3] or not geometry_value.get("geometry") is Dictionary or not geometry_value.get("lod_geometry") is Dictionary or (geometry_value.size()==3 and not geometry_value.get("lod_visual_reference_indices") is Dictionary):
					result.errors.append("Invalid strategic geometry fields: " + fact_id)
					return result
				feature["geometry"] = geometry_value.geometry
				feature["lod_geometry"] = geometry_value.lod_geometry
				if geometry_value.has("lod_visual_reference_indices"): feature["lod_visual_reference_indices"] = geometry_value.lod_visual_reference_indices
			if ids.has(str(feature.get("id", ""))) or not valid_feature(feature) or fact.subject_id != str(feature.id) or fact.source_id != str(feature.source_id):
				result.errors.append("Invalid/duplicate strategic feature: " + fact_id)
				return result
			ids[str(feature.id)] = true
			result.features.append(feature)
			shard_features.append(feature)
		result.shards[shard_id] = shard_features
	for feature: Dictionary in result.features:
		if current.is_valid() and not current.call():
			result.features.clear()
			result.line_chunks.clear()
			result.cancelled = true
			return result
		if str(feature.kind) == "settlement":
			continue
		for lod: String in feature.get("presentation_lods", ["coarse", "medium"]) as Array:
			var raw: Array = (feature.lod_geometry as Dictionary).get(lod, []) as Array
			var tolerance := float((feature.get("lod_tolerance_m", {}) as Dictionary).get(lod,5000.0 if lod=="coarse" else 1500.0))
			if str(feature.kind) == "rail":
				raw = [raw]
			elif str(feature.kind) in ["lake", "land_reference", "ocean_reference"]:
				result.line_chunks.append({"kind": feature.kind, "lod": lod, "tolerance_m": tolerance, "polygons": raw, "feature_id": feature.id, "source_geometry_file": feature.get("source_geometry_file", ""), "visual_reference_features":feature.get("visual_reference_features",[]), "visual_reference_indices":(feature.get("lod_visual_reference_indices",{}) as Dictionary).get(lod,[])})
				continue
			var boundaries: Array[Dictionary] = []
			for line: Array in raw:
				var points := PackedVector3Array()
				for coordinate: Array in line:
					var lon := deg_to_rad(float(coordinate[0]))
					var lat := deg_to_rad(float(coordinate[1]))
					points.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
				if points.size() >= 2:
					if str(feature.kind)=="coast":
						# Match the existing Local line packing: bound an individual
						# upload even when a source continental ring is very long.
						for first: int in range(0,points.size()-1,128):
							boundaries.append({"kind":feature.kind,"points":points.slice(first,mini(first+129,points.size())),"feature_id":feature.id,"source_fact_id":"strategic_spatial:"+str(feature.id)})
					else:
						boundaries.append({"kind": feature.kind, "points": points, "feature_id": feature.id, "source_fact_id": "strategic_spatial:" + str(feature.id)})
			result.line_chunks.append({"kind": feature.kind, "lod": lod, "tolerance_m": tolerance, "boundaries": boundaries})
	result.has_content = not result.features.is_empty()
	return result

static func valid_feature(feature: Dictionary) -> bool:
	if str(feature.get("id", "")).is_empty() or feature.has("owner") or feature.has("controller_id") or feature.has("polity_id") or feature.has("administrative_region_id"):
		return false
	if str(feature.get("kind", "")) not in ["settlement", "rail", "river", "coast", "lake", "land_reference", "ocean_reference"] or not HistoricalFactEvidence.valid_date(str(feature.get("valid_from", ""))) or not HistoricalFactEvidence.valid_date(str(feature.get("valid_to", ""))) or str(feature.valid_from) >= str(feature.valid_to):
		return false
	var geometry := feature.get("geometry", {}) as Dictionary
	var kind := str(feature.kind)
	if kind in ["land_reference", "ocean_reference"] and (str(feature.get("geometry_role", "")) != "PRESENTATION_DIFFERENCE_ONLY" or str(feature.get("source_type", "")) != "REFERENCE_ONLY" or str(feature.get("lod_geometry_role", "")) != "PRECOMPUTED_DISPLAY_TRIANGLES"): return false
	if kind != "settlement":
		if not feature.get("lod_geometry") is Dictionary: return false
		var lods := feature.get("presentation_lods", ["coarse", "medium"]) as Array
		if lods.is_empty() or lods.size()>2 or lods.size()!=(feature.lod_geometry as Dictionary).size(): return false
		for lod: String in lods:
			if lod not in ["coarse","medium"]: return false
			var raw := (feature.lod_geometry as Dictionary).get(lod, []) as Array
			if not _valid_geometry(kind,{"type":geometry.get("type", ""),"coordinates":raw},str(feature.get("geometry_role", ""))): return false
			if feature.has("visual_reference_features"):
				if kind != "land_reference" or str(feature.get("visual_reference_role", "")) != "BOUNDED_TEXTURE_CONTINUATION_ONLY" or feature.get("visual_reference_authority", true) != false or float(feature.get("visual_reference_max_distance_m",0)) != 9000.0: return false
				var references := feature.visual_reference_features as Array
				var indices := (feature.get("lod_visual_reference_indices",{}) as Dictionary).get(lod,[]) as Array
				if references.is_empty() or indices.size()!=raw.size(): return false
				for index: Variant in indices:
					if typeof(index) not in [TYPE_FLOAT,TYPE_INT] or float(index)!=floorf(float(index)) or int(index)<0 or int(index)>=references.size(): return false
				for reference: String in references:
					if not reference.is_empty() and (not reference.begins_with("gw_") or not reference.substr(3).is_valid_int()): return false
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
