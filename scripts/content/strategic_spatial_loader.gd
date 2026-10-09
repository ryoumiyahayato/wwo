class_name StrategicSpatialLoader
extends RefCounted
## Bounded Content slices on the existing evidence contracts, never Local support.
const INDEX_PATH: String = "res://data/strategic/index.json"
const MAX_ACTIVE_REGIONS: int = 2
const MAX_ACTIVE_COAST_REGIONS: int = 64
const MEDIUM_LOD_MPP: float = 1500.0
var content: LocalSpatialContent
var metrics: Dictionary = {"file_reads": 0, "source_admissions": 0, "loads": 0, "active_regions": []}
var errors: Array[String] = []
var _index: Dictionary = {}
var _thread: Thread
var _wanted: Array[String] = []
var _loading: Array[String] = []
var _date: String = ""

func request(center: Vector2, radius_km: float, date: String, mpp: float = 4500.0) -> void:
	_date = date
	if _index.is_empty():
		_index = ContentDocument.read(INDEX_PATH, errors)
		metrics.file_reads += 1
	if str(_index.get("schema_id", "")) != "global_strategic_index_r1" or date < str(_index.get("valid_from", "")) or date >= str(_index.get("valid_to", "")):
		release()
		return
	var candidates: Array[Dictionary] = []
	for descriptor: Dictionary in _index.get("regions", []) as Array:
		var bounds := descriptor.bounds as Array
		var latitude_padding := minf(45.0, radius_km / 111.195)
		var longitude_padding := minf(90.0, latitude_padding / maxf(0.2, cos(deg_to_rad(center.y))))
		if center.y + latitude_padding < float(bounds[2]) or center.y - latitude_padding > float(bounds[3]) or center.x + longitude_padding < float(bounds[0]) or center.x - longitude_padding > float(bounds[1]):
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
		return
	if wanted == _wanted and (content != null or _thread != null):
		return
	_wanted = wanted
	_start()

static func _intersects(bounds: Array, center: Vector2, lat_padding: float, lon_padding: float) -> bool:
	if center.y+lat_padding < float(bounds[2]) or center.y-lat_padding > float(bounds[3]): return false
	for shift: float in [-360.0,0.0,360.0]:
		if center.x+lon_padding>=float(bounds[0])+shift and center.x-lon_padding<=float(bounds[1])+shift: return true
	return false

func _start() -> void:
	if _thread != null or _wanted.is_empty():
		return
	_loading = _wanted.duplicate()
	content = null
	metrics.loads += 1
	_thread = Thread.new()
	_thread.start(_load.bind(_index.duplicate(true), _loading.duplicate()))

func preparing() -> bool:
	return _thread != null

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var result := _thread.wait_to_finish() as LocalSpatialContent
	_thread = null
	metrics.file_reads += int(result.metrics.get("file_reads", 0))
	metrics.source_admissions += int(result.metrics.get("source_admissions", 0))
	if _loading != _wanted:
		_start()
		return false
	content = result
	errors.append_array(result.errors)
	var strategic_regions: Array[String] = []
	var coast_regions: Array[String] = []
	for id: String in _loading:
		if id.begins_with("physical_"): coast_regions.append(id)
		else: strategic_regions.append(id)
	metrics["active_regions"] = strategic_regions
	metrics["active_coast_regions"] = coast_regions
	metrics["active_features"] = result.features.size()
	metrics["active_source_bytes"] = int(result.metrics.get("source_bytes",0))
	return true

func release() -> void:
	_wanted.clear()
	content = null
	metrics["active_regions"] = []
	metrics["active_features"] = 0
	metrics["active_coast_regions"] = []
	metrics["active_source_bytes"] = 0

func dispose() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	release()

static func _load(index: Dictionary, selected: Array[String]) -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	var started := Time.get_ticks_usec()
	result.metrics = {"load_started_usec": started, "file_read_usec": 0, "parse_usec": 0, "source_resolution_usec": 0, "geometry_prepare_usec": 0, "file_reads": 0, "source_admissions": 0, "source_bytes": 0}
	result.metadata = {"content_level": "strategic", "valid_from": index.valid_from, "valid_to": index.valid_to, "local_support": false, "presentation_lods": ["coarse", "medium"], "regions": selected}
	var ids: Dictionary = {}
	var geometry_assets: Dictionary = {}
	var descriptors: Array = (index.regions as Array).duplicate()
	descriptors.append_array(index.get("coast_regions", []) as Array)
	for parent: Dictionary in index.get("coast_regions", []) as Array:
		descriptors.append_array(parent.get("medium_regions", []) as Array)
	for descriptor: Dictionary in descriptors:
		if str(descriptor.id) not in selected:
			continue
		var read_started := Time.get_ticks_usec()
		var bytes := FileAccess.get_file_as_bytes(str(descriptor.path))
		result.metrics.source_bytes += bytes.size()
		result.metrics.file_read_usec += Time.get_ticks_usec() - read_started
		result.metrics.file_reads += 1
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if bytes.size() != int(descriptor.bytes) or hash.finish().hex_encode() != str(descriptor.sha256):
			result.errors.append("Strategic shard byte binding rejected: " + str(descriptor.id))
			return result
		var parse_started := Time.get_ticks_usec()
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
			result.errors.append("Invalid strategic JSON: " + str(descriptor.id))
			return result
		var document := parser.data as Dictionary
		result.metrics.parse_usec += Time.get_ticks_usec() - parse_started
		if str((document.get("metadata", {}) as Dictionary).get("schema_id", "")) != "global_strategic_content_r1":
			result.errors.append("Unsupported strategic shard: " + str(descriptor.id))
			return result
		var sources := HistoricalSourceRegistry.new()
		var facts := HistoricalEvidenceCatalog.new()
		var admitted_at := Time.get_ticks_usec()
		if not sources.load_document(document.get("source_registry", {}) as Dictionary) or not facts.load_document(document.get("evidence_catalog", {}) as Dictionary):
			result.errors.append_array(sources.errors())
			result.errors.append_array(facts.errors())
			return result
		var gate := HistoricalProvenanceGate.new(sources, facts)
		for fact_id: String in facts.fact_ids():
			var fact := facts.fact(fact_id)
			if not fact.value is Dictionary or not gate.admit_runtime_fact(fact_id, fact.domain, fact.output_material()):
				result.errors.append("Unadmitted strategic fact: " + fact_id)
				return result
			var feature := (fact.value as Dictionary).duplicate()
			if feature.has("geometry_asset"):
				var asset := feature.geometry_asset as Dictionary
				var path := str(asset.get("path", ""))
				if not path.begins_with("res://data/strategic/") or path.simplify_path() != path or int(asset.get("decoded_bytes", 0)) <= 0 or int(asset.get("decoded_bytes", 0)) > 33554432:
					result.errors.append("Invalid strategic geometry descriptor: " + fact_id)
					return result
				if not geometry_assets.has(path):
					var packed := FileAccess.get_file_as_bytes(path)
					var packed_hash := HashingContext.new()
					packed_hash.start(HashingContext.HASH_SHA256)
					packed_hash.update(packed)
					if not path.begins_with("res://data/strategic/") or str(asset.get("encoding", "")) != "ZLIB_JSON_UTF8" or packed.size() != int(asset.get("bytes", -1)) or packed_hash.finish().hex_encode() != str(asset.get("sha256", "")):
						result.errors.append("Strategic geometry payload binding rejected: " + path)
						return result
					var decoded := packed.decompress_dynamic(int(asset.decoded_bytes), FileAccess.COMPRESSION_DEFLATE)
					var decoded_hash := HashingContext.new()
					decoded_hash.start(HashingContext.HASH_SHA256)
					decoded_hash.update(decoded)
					var geometry_parser := JSON.new()
					if decoded.size() != int(asset.decoded_bytes) or decoded_hash.finish().hex_encode() != str(asset.decoded_sha256) or geometry_parser.parse(decoded.get_string_from_utf8()) != OK or not geometry_parser.data is Dictionary:
						result.errors.append("Invalid strategic geometry payload: " + path)
						return result
					geometry_assets[path] = {"descriptor":asset,"geometries":geometry_parser.data}
					result.metrics.source_bytes += packed.size()
					result.metrics.file_reads += 1
				var bound := geometry_assets[path] as Dictionary
				if bound.descriptor != asset or not (bound.geometries as Dictionary).has(str(feature.id)):
					result.errors.append("Strategic geometry identity binding rejected: " + fact_id)
					return result
				var geometry_value := (bound.geometries as Dictionary)[str(feature.id)] as Dictionary
				if geometry_value.size() != 2 or not geometry_value.get("geometry") is Dictionary or not geometry_value.get("lod_geometry") is Dictionary:
					result.errors.append("Invalid strategic geometry fields: " + fact_id)
					return result
				feature["geometry"] = geometry_value.geometry
				feature["lod_geometry"] = geometry_value.lod_geometry
			if ids.has(str(feature.get("id", ""))) or not valid_feature(feature) or fact.subject_id != str(feature.id) or fact.source_id != str(feature.source_id):
				result.errors.append("Invalid/duplicate strategic feature: " + fact_id)
				return result
			ids[str(feature.id)] = true
			result.features.append(feature)
		result.metrics.source_admissions += facts.fact_ids().size()
		result.metrics.source_resolution_usec += Time.get_ticks_usec() - admitted_at
	var prepare_started := Time.get_ticks_usec()
	for feature: Dictionary in result.features:
		if str(feature.kind) == "settlement":
			continue
		for lod: String in feature.get("presentation_lods", ["coarse", "medium"]) as Array:
			var raw: Array = (feature.lod_geometry as Dictionary).get(lod, []) as Array
			var tolerance := float((feature.get("lod_tolerance_m", {}) as Dictionary).get(lod,5000.0 if lod=="coarse" else 1500.0))
			if str(feature.kind) == "rail":
				raw = [raw]
			elif str(feature.kind) in ["lake", "land_reference", "ocean_reference"]:
				result.line_chunks.append({"kind": feature.kind, "lod": lod, "tolerance_m": tolerance, "polygons": raw, "feature_id": feature.id, "source_geometry_file": feature.get("source_geometry_file", "")})
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
	result.metrics.geometry_prepare_usec = Time.get_ticks_usec() - prepare_started
	result.metrics.worker_elapsed_usec = Time.get_ticks_usec() - started
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
	return _valid_geometry(kind,geometry,str(feature.get("geometry_role", "")))

static func _valid_geometry(kind: String, geometry: Dictionary, role: String) -> bool:
	var coordinates := geometry.get("coordinates", []) as Array
	if not _valid_coordinates(coordinates): return false
	match kind:
		"settlement": return str(geometry.get("type", "")) == "Point" and coordinates.size() == 2
		"rail": return str(geometry.get("type", "")) == "LineString" and coordinates.size() >= 2 and role == "APPROXIMATE_STRATEGIC_CORRIDOR"
		"river", "coast":
			if str(geometry.get("type", "")) != "MultiLineString": return false
			for line: Array in coordinates:
				if line.size() < 2: return false
				var distinct: bool = false
				for point: Array in line:
					distinct = distinct or point!=line[0]
				if not distinct: return false
		"lake", "land_reference", "ocean_reference":
			if str(geometry.get("type", "")) != "MultiPolygon": return false
			for polygon: Array in coordinates:
				for ring: Array in polygon:
					if ring.size() < 4 or ring[0] != ring[-1]: return false
	return true

static func _valid_coordinates(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty():
		return false
	var array := value as Array
	if array.size() == 2 and typeof(array[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(array[1]) in [TYPE_INT, TYPE_FLOAT]:
		return is_finite(float(array[0])) and is_finite(float(array[1])) and absf(float(array[0])) <= 180.0 and absf(float(array[1])) <= 90.0
	for child: Variant in array:
		if not _valid_coordinates(child): return false
	return true
