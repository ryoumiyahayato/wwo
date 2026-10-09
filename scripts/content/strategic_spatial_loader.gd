class_name StrategicSpatialLoader
extends RefCounted
## Bounded Content slices on the existing evidence contracts, never Local support.
const INDEX_PATH: String = "res://data/strategic/index.json"
const MAX_ACTIVE_REGIONS: int = 2
var content: LocalSpatialContent
var metrics: Dictionary = {"file_reads": 0, "source_admissions": 0, "loads": 0, "active_regions": []}
var errors: Array[String] = []
var _index: Dictionary = {}
var _thread: Thread
var _wanted: Array[String] = []
var _loading: Array[String] = []
var _date: String = ""

func request(center: Vector2, radius_km: float, date: String) -> void:
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
	wanted.sort()
	if wanted.is_empty():
		release()
		return
	if wanted == _wanted and (content != null or _thread != null):
		return
	_wanted = wanted
	_start()

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
	metrics["active_regions"] = _loading.duplicate()
	metrics["active_features"] = result.features.size()
	return true

func release() -> void:
	_wanted.clear()
	content = null
	metrics["active_regions"] = []
	metrics["active_features"] = 0

func dispose() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	release()

static func _load(index: Dictionary, selected: Array[String]) -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	var started := Time.get_ticks_usec()
	result.metrics = {"load_started_usec": started, "file_read_usec": 0, "parse_usec": 0, "source_resolution_usec": 0, "geometry_prepare_usec": 0, "file_reads": 0, "source_admissions": 0}
	result.metadata = {"content_level": "strategic", "valid_from": index.valid_from, "valid_to": index.valid_to, "local_support": false, "presentation_lods": ["coarse", "medium"], "regions": selected}
	var ids: Dictionary = {}
	for descriptor: Dictionary in index.regions as Array:
		if str(descriptor.id) not in selected:
			continue
		var read_started := Time.get_ticks_usec()
		var bytes := FileAccess.get_file_as_bytes(str(descriptor.path))
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
			var feature := fact.value as Dictionary
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
		for lod: String in ["coarse", "medium"]:
			var raw: Array = (feature.lod_geometry as Dictionary).get(lod, []) as Array
			if str(feature.kind) == "rail":
				raw = [raw]
			elif str(feature.kind) == "lake":
				result.line_chunks.append({"kind": "lake", "lod": lod, "polygons": raw, "feature_id": feature.id, "source_geometry_file": feature.get("source_geometry_file", "")})
				continue
			var boundaries: Array[Dictionary] = []
			for line: Array in raw:
				var points := PackedVector3Array()
				for coordinate: Array in line:
					var lon := deg_to_rad(float(coordinate[0]))
					var lat := deg_to_rad(float(coordinate[1]))
					points.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
				if points.size() >= 2:
					boundaries.append({"kind": feature.kind, "points": points, "feature_id": feature.id, "source_fact_id": "strategic_spatial:" + str(feature.id)})
			result.line_chunks.append({"kind": feature.kind, "lod": lod, "boundaries": boundaries})
	result.metrics.geometry_prepare_usec = Time.get_ticks_usec() - prepare_started
	result.metrics.worker_elapsed_usec = Time.get_ticks_usec() - started
	return result

static func valid_feature(feature: Dictionary) -> bool:
	if str(feature.get("id", "")).is_empty() or feature.has("owner") or feature.has("controller_id") or feature.has("polity_id") or feature.has("administrative_region_id"):
		return false
	if str(feature.get("kind", "")) not in ["settlement", "rail", "river", "lake"] or not HistoricalFactEvidence.valid_date(str(feature.get("valid_from", ""))) or not HistoricalFactEvidence.valid_date(str(feature.get("valid_to", ""))) or str(feature.valid_from) >= str(feature.valid_to):
		return false
	var geometry := feature.get("geometry", {}) as Dictionary
	var coordinates := geometry.get("coordinates", []) as Array
	if not _valid_coordinates(coordinates): return false
	match str(feature.kind):
		"settlement": return str(geometry.get("type", "")) == "Point" and coordinates.size() == 2
		"rail": return str(geometry.get("type", "")) == "LineString" and coordinates.size() >= 2 and str(feature.get("geometry_role", "")) == "APPROXIMATE_STRATEGIC_CORRIDOR"
		"river":
			if str(geometry.get("type", "")) != "MultiLineString": return false
			for line: Array in coordinates:
				if line.size() < 2: return false
		"lake":
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
