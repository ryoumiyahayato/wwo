class_name LocalSpatialLoader
extends RefCounted
## Lazy preparation through the existing source/fact contracts, off the UI thread.

const PARIS_PATH: String = "res://data/local/paris_northern_france_1900.json"
const ANCHOR: Vector2 = Vector2(2.3522, 48.8566)
const PREWARM_KM_PER_PIXEL: float = 6.0
var content: LocalSpatialContent
var load_count: int = 0
var _thread: Thread

static func covers(lon_lat: Vector2) -> bool:
	var lat := deg_to_rad(lon_lat.y)
	var base := deg_to_rad(ANCHOR.y)
	var dot := sin(lat) * sin(base) + cos(lat) * cos(base) * cos(deg_to_rad(lon_lat.x - ANCHOR.x))
	return acos(clampf(dot, -1.0, 1.0)) * 6371.0088 <= 300.0

func request() -> void:
	if content != null or _thread != null:
		return
	load_count += 1
	_thread = Thread.new()
	_thread.start(_load)

func preparing() -> bool:
	return _thread != null

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	content = _thread.wait_to_finish() as LocalSpatialContent
	_thread = null
	return true

func dispose() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

static func _load() -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	var started := Time.get_ticks_usec()
	result.metrics["load_started_usec"] = started
	var file := FileAccess.open(PARIS_PATH, FileAccess.READ)
	if file == null:
		result.errors.append("Paris shard unavailable")
		return result
	var text := file.get_as_text()
	result.metrics["file_read_usec"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid Paris shard JSON")
		return result
	var document := parser.data as Dictionary
	result.metrics["parse_usec"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	result.metadata = document.get("metadata", {}) as Dictionary
	if str(result.metadata.get("schema_id", "")) != "local_spatial_content_r1" or str(result.metadata.get("anchor_place_id", "")) != "place:paris":
		result.errors.append("Unsupported Paris content shard")
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
		result.features.append(feature)
	for feature: Dictionary in result.features:
		if str(feature.kind) == "rail":
			for place_id: String in feature.get("places", []) as Array:
				if not ids.has(place_id):
					result.errors.append("Unresolved railway place: " + place_id)
	result.metrics["source_resolution_usec"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var groups: Dictionary = {}
	var segment_counts: Dictionary = {}
	for feature: Dictionary in result.features:
		if str(feature.kind) == "settlement":
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
	result.metrics["geometry_prepare_usec"] = Time.get_ticks_usec() - started
	result.metrics["worker_elapsed_usec"] = Time.get_ticks_usec() - int(result.metrics.load_started_usec)
	return result

static func _valid_feature(feature: Dictionary) -> bool:
	if str(feature.get("id", "")).is_empty() or feature.has("owner") or feature.has("controller_id") or feature.has("polity_id"):
		return false
	if not HistoricalFactEvidence.valid_date(str(feature.get("valid_from", ""))) or not HistoricalFactEvidence.valid_date(str(feature.get("valid_to", ""))) or str(feature.valid_from) >= str(feature.valid_to):
		return false
	var kind := str(feature.get("kind", ""))
	if kind not in ["settlement", "rail", "river", "coast"]:
		return false
	var geometry := feature.get("geometry", {}) as Dictionary
	var points: Array = []
	if kind == "settlement" and str(geometry.get("type", "")) == "Point":
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
