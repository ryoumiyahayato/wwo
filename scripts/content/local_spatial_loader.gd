class_name LocalSpatialLoader
extends RefCounted
## Lazy preparation through the existing source/fact contracts, off the UI thread.

const PARIS_PATH: String = "res://data/local/paris_northern_france_1900.json"
const ANCHOR: Vector2 = Vector2(2.3522, 48.8566)
const GIZA_ANCHOR: Vector2 = Vector2(31.131557,29.976122)
const GIZA_PATH: String = "res://data/local/giza_pyramids_1900.json"
const SOURCES: Array[Dictionary] = [
	{"path":PARIS_PATH,"anchor":ANCHOR,"anchor_id":"place:paris","radius_km":300.0},
	{"path":GIZA_PATH,"anchor":GIZA_ANCHOR,"anchor_id":"landmark:giza_pyramids_1900","radius_km":20.0},
	{"path":"res://data/local/london_westminster_1900.json","anchor":Vector2(-0.1246,51.5007),"anchor_id":"place:london","radius_km":15.0},
	{"path":"res://data/local/zermatt_west_physical_reference.json","anchor":Vector2(7.703304,46.010743),"anchor_id":"geographic_region:zermatt_west_reference","radius_km":8.0}]
const PREWARM_KM_PER_PIXEL: float = 6.0
var content: LocalSpatialContent
var _thread: Thread
var _request_mutex := Mutex.new()
var _request_generation: int = 0
var _wanted: bool = false
var _wanted_path: String = PARIS_PATH
var _loading_path: String = ""
var _wanted_anchor := ANCHOR

static func covers(lon_lat: Vector2) -> bool:
	return not source_at(lon_lat).is_empty()

static func source_at(lon_lat: Vector2) -> Dictionary:
	var unit := GlobeProjection.lon_lat_to_unit(lon_lat)
	for source: Dictionary in SOURCES:
		if unit.angle_to(GlobeProjection.lon_lat_to_unit(source.anchor as Vector2))*6371.0088<=float(source.radius_km): return source
	return {}

static func anchors() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for source: Dictionary in SOURCES: result.append(source.anchor as Vector2)
	return result

func request(lon_lat: Vector2 = ANCHOR) -> void:
	var source := source_at(lon_lat)
	if source.is_empty(): return
	_wanted = true
	_wanted_path = str(source.path)
	_wanted_anchor = source.anchor as Vector2
	if _thread!=null:
		if _loading_path!=_wanted_path:
			_request_mutex.lock()
			_request_generation += 1
			_request_mutex.unlock()
		return
	if content!=null and str(content.metadata.get("content_path",""))==_wanted_path: return
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()
	_thread = Thread.new()
	_loading_path = _wanted_path
	_thread.start(_load.bind(_wanted_path,_request_current.bind(_request_generation)))

func cancel_pending() -> void:
	if not _wanted: return
	_wanted = false
	if _thread == null: return
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()

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
	if result.cancelled or not _wanted or _loading_path!=_wanted_path:
		if _wanted: request(_wanted_anchor)
		return false
	content = result
	return true

func dispose() -> void:
	cancel_pending()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

static func _load(path: String, current: Callable) -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	result.metadata["content_path"] = path
	if not current.call():
		result.cancelled = true
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.metadata["content_path"] = path
		result.errors.append("Local shard unavailable: "+path)
		return result
	var text := file.get_as_text()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid Local shard JSON")
		return result
	var document := parser.data as Dictionary
	result.metadata = document.get("metadata", {}) as Dictionary
	result.metadata["content_path"] = path
	var expected := ""
	for source: Dictionary in SOURCES:
		if str(source.path)==path: expected = str(source.anchor_id); break
	if str(result.metadata.get("schema_id", "")) != "local_spatial_content_r1" or str(result.metadata.get("anchor_place_id", "")) != expected:
		result.errors.append("Unsupported Local content shard")
		return result
	var sources := HistoricalSourceRegistry.new()
	var facts := HistoricalEvidenceCatalog.new()
	if not sources.load_document(document.get("source_registry", {}) as Dictionary) or not facts.load_document(document.get("evidence_catalog", {}) as Dictionary):
		result.errors.append_array(sources.errors())
		result.errors.append_array(facts.errors())
		return result
	var gate := HistoricalProvenanceGate.new(sources, facts)
	var ids: Dictionary = {}
	for fact_id: String in facts.fact_ids():
		if not current.call():
			result.cancelled = true
			return result
		var fact := facts.fact(fact_id)
		if not fact.value is Dictionary:
			result.errors.append("Local spatial fact requires a feature")
			return result
		if not gate.admit_runtime_fact(fact_id, fact.domain, fact.output_material()):
			result.errors.append_array(gate.errors())
			return result
		var feature := (fact.value as Dictionary).duplicate(true)
		var id := str(feature.get("id", ""))
		if ids.has(id) or not _valid_feature(feature) or fact.subject_id != id or str(feature.get("source_id", "")) != fact.source_id:
			result.errors.append("Invalid or duplicate Local feature: " + id)
			return result
		ids[id] = true
		if not LocalSpatialContent.historical_rail_alignment(feature): continue
		result.features.append(feature)
	for visual: Dictionary in result.landmark_visuals():
		if not ids.has(str(visual.get("anchor_place_id",""))) or not _valid_feature(visual) or str(visual.get("kind",""))!="landmark" or not str(visual.get("model_path","")).begins_with("res://assets/landmarks/") or str(visual.get("source_reference","")).is_empty():
			result.errors.append("Invalid landmark placement reference")
			return result
	var surface_path := str(result.metadata.get("surface_reference_path",""))
	if not surface_path.is_empty():
		var surface_errors: Array[String] = []
		var surface := ContentDocument.read(surface_path,surface_errors)
		if surface_errors.is_empty() and _valid_surface(surface):
			surface["content_path"] = surface_path
			result.surface_reference = surface
		else:
			result.metadata["terrain_note_zh"] = "局部高程资料不可用，地表保持平面。"
	for feature: Dictionary in result.features:
		if not current.call():
			result.cancelled = true
			return result
		if str(feature.kind) == "rail":
			for place_id: String in feature.get("places", []) as Array:
				if not ids.has(place_id):
					result.errors.append("Unresolved railway place: " + place_id)
	var groups: Dictionary = {}
	var segment_counts: Dictionary = {}
	for feature: Dictionary in result.features:
		if not current.call():
			result.cancelled = true
			return result
		if str(feature.kind) in ["settlement","landmark","geographic_region"]:
			continue
		var points := PackedVector3Array()
		for coordinate: Array in feature.geometry.coordinates as Array:
			var lon := deg_to_rad(float(coordinate[0]))
			var lat := deg_to_rad(float(coordinate[1]))
			points.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
		var kind := str(feature.kind)
		if not groups.has(kind):
			groups[kind] = []
			segment_counts[kind] = 0
		for offset: int in range(0, points.size() - 1, 128):
			var part := points.slice(offset, mini(offset + 129, points.size()))
			(groups[kind] as Array).append({"kind": kind, "points": part, "feature_id":str(feature.id)})
			segment_counts[kind] += part.size() - 1
			if int(segment_counts[kind]) >= 256:
				result.line_chunks.append({"kind": kind, "boundaries": groups[kind], "max_mpp": 200.0})
				groups[kind] = []
				segment_counts[kind] = 0
	for kind: String in groups:
		if not (groups[kind] as Array).is_empty():
			result.line_chunks.append({"kind": kind, "boundaries": groups[kind], "max_mpp": 200.0})
	result.has_content = not result.features.is_empty()
	if not current.call(): result.cancelled = true
	return result

static func _valid_surface(surface: Dictionary) -> bool:
	if surface.get("schema_id")!="local_native_height_reference_r1" or surface.get("horizontal_crs")!="EPSG:4326": return false
	var width := int(surface.get("width",0))
	var height := int(surface.get("height",0))
	var rows := surface.get("height_rows_m",[]) as Array
	if width<2 or height<2 or width>128 or height>128 or rows.size()!=height or float(surface.get("step_degrees",0.0))<=0.0 or (surface.get("anchor_lon_lat",[]) as Array).size()!=2: return false
	for row: Variant in rows:
		if not row is Array or (row as Array).size()!=width: return false
		for value: Variant in row:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)): return false
	return true

static func _valid_feature(feature: Dictionary) -> bool:
	if str(feature.get("id", "")).is_empty() or feature.has("owner") or feature.has("controller_id") or feature.has("polity_id"):
		return false
	if not HistoricalFactEvidence.valid_date(str(feature.get("valid_from", ""))) or not HistoricalFactEvidence.valid_date(str(feature.get("valid_to", ""))) or str(feature.valid_from) >= str(feature.valid_to):
		return false
	var kind := str(feature.get("kind", ""))
	if kind not in ["settlement", "landmark", "geographic_region", "rail", "river", "coast"]:
		return false
	var geometry := feature.get("geometry", {}) as Dictionary
	var points: Array = []
	if kind in ["settlement","landmark","geographic_region"] and str(geometry.get("type", "")) == "Point":
		points.append(geometry.get("coordinates", []))
	elif str(geometry.get("type", "")) == "LineString":
		points = geometry.get("coordinates", []) as Array
		if points.size() < 2:
			return false
	else:
		return false
	var previous: Array = []
	for raw: Variant in points:
		if not raw is Array or (raw as Array).size() != 2:
			return false
		var point := raw as Array
		if typeof(point[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(point[1]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(point[0])) or not is_finite(float(point[1])) or absf(float(point[0])) > 180.0 or absf(float(point[1])) > 90.0:
			return false
		if point == previous:
			return false
		previous = point
	return true
