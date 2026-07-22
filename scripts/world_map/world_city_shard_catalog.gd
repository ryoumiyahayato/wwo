class_name WorldCityShardCatalog
extends RefCounted
## Lazy modern-city projection. The catalog loads only shards whose projected
## bounds intersect the current world-space viewport and keeps a bounded LRU.

const INDEX_PATH: String = "res://data/world_map/city_detail/index.json"
const SHARD_ROOT: String = "res://data/world_map/city_detail/"

var configured: bool = false
var index_document: Dictionary = {}
var shard_metadata: Array[Dictionary] = []
var visible_records: Array[Dictionary] = []
var visible_by_id: Dictionary = {}

var _projector: Callable
var _loaded_shards: Dictionary = {}
var _lru_shard_ids: Array[String] = []
var _visible_signature: String = ""
var _cache_limit: int = 12
var _node_budget: int = 1600
var _label_budget: int = 180
var _metrics: Dictionary = {
	"index_loaded": false,
	"index_shards": 0,
	"index_records": 0,
	"query_count": 0,
	"cache_hits": 0,
	"cache_misses": 0,
	"shard_parses": 0,
	"evictions": 0,
	"candidate_records": 0,
	"visible_records": 0,
	"last_query_ms": 0.0,
	"maximum_query_ms": 0.0,
	"last_intersecting_shards": 0,
	"missing_shards": 0,
}


func configure(projector: Callable) -> bool:
	_projector = projector
	configured = false
	index_document = _read_json(INDEX_PATH)
	shard_metadata.clear()
	_loaded_shards.clear()
	_lru_shard_ids.clear()
	visible_records.clear()
	visible_by_id.clear()
	_visible_signature = ""
	if index_document.is_empty() or not _projector.is_valid():
		_metrics["index_loaded"] = false
		return false
	if str(index_document.get("historical_status", "")) != "modern_reference_only":
		push_error("城市细化索引缺少现代地理边界声明")
		return false
	var policy: Dictionary = index_document.get("runtime_policy", {}) as Dictionary
	_cache_limit = maxi(2, int(policy.get("country_cache_limit", 12)))
	_node_budget = maxi(100, int(policy.get("visible_node_budget", 1600)))
	_label_budget = maxi(20, int(policy.get("visible_label_budget", 180)))
	for raw_country: Variant in index_document.get("countries", []) as Array:
		if not raw_country is Dictionary:
			continue
		var country: Dictionary = raw_country as Dictionary
		for raw_shard: Variant in country.get("shards", []) as Array:
			if not raw_shard is Dictionary:
				continue
			var shard: Dictionary = (raw_shard as Dictionary).duplicate(true)
			shard["country_code"] = str(country.get("country_code", ""))
			shard["continent"] = str(country.get("continent", ""))
			shard["municipality_detail"] = bool(country.get("municipality_detail", false))
			shard["world_rect"] = _project_bounds(shard.get("bounds", []) as Array)
			if not str(shard.get("id", "")).is_empty() and not (shard["world_rect"] as Rect2).has_area():
				continue
			shard_metadata.append(shard)
	shard_metadata.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	var totals: Dictionary = index_document.get("totals", {}) as Dictionary
	_metrics["index_loaded"] = true
	_metrics["index_shards"] = shard_metadata.size()
	_metrics["index_records"] = int(totals.get("records", 0))
	_metrics["france_municipalities"] = int(totals.get("france_municipalities", 0))
	configured = true
	return true


func query(world_rect: Rect2, scope: String, zoom: float) -> bool:
	var started_usec: int = Time.get_ticks_usec()
	_metrics["query_count"] = int(_metrics.get("query_count", 0)) + 1
	if not configured or scope == "world":
		var had_visible: bool = not visible_records.is_empty()
		visible_records.clear()
		visible_by_id.clear()
		_visible_signature = ""
		_finish_query(started_usec, 0, 0)
		return had_visible
	var intersecting: Array[Dictionary] = []
	var exempt: Dictionary = {}
	for shard: Dictionary in shard_metadata:
		var shard_rect: Rect2 = shard.get("world_rect", Rect2()) as Rect2
		if not shard_rect.intersects(world_rect):
			continue
		intersecting.append(shard)
		exempt[str(shard.get("id", ""))] = true
	var candidates: Array[Dictionary] = []
	for shard: Dictionary in intersecting:
		for record: Dictionary in _load_shard(shard):
			var point: Vector2 = record.get("world_point", Vector2.INF) as Vector2
			if point == Vector2.INF or not world_rect.has_point(point):
				continue
			if not _record_visible(record, scope, zoom):
				continue
			if not str(record.get("curated_city_id", "")).is_empty():
				continue
			candidates.append(record)
	_evict_to_limit(exempt)
	candidates.sort_custom(_record_higher_priority)
	if candidates.size() > _node_budget:
		candidates.resize(_node_budget)
	var next_signature_parts := PackedStringArray()
	for record: Dictionary in candidates:
		next_signature_parts.append(str(record.get("id", "")))
	var next_signature: String = "|".join(next_signature_parts)
	var changed: bool = next_signature != _visible_signature
	if changed:
		_visible_signature = next_signature
		visible_records = candidates
		visible_by_id.clear()
		for record: Dictionary in visible_records:
			visible_by_id[str(record.get("id", ""))] = record
	_finish_query(started_usec, intersecting.size(), candidates.size())
	return changed


func record(record_id: String) -> Dictionary:
	var value: Variant = visible_by_id.get(record_id, {})
	return value as Dictionary if value is Dictionary else {}


func get_label_budget() -> int:
	return _label_budget


func clear_cache() -> void:
	_loaded_shards.clear()
	_lru_shard_ids.clear()
	visible_records.clear()
	visible_by_id.clear()
	_visible_signature = ""


func debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = _metrics.duplicate(true)
	snapshot["configured"] = configured
	snapshot["cache_limit"] = _cache_limit
	snapshot["node_budget"] = _node_budget
	snapshot["label_budget"] = _label_budget
	snapshot["loaded_shards"] = _loaded_shards.size()
	snapshot["loaded_shard_ids"] = _lru_shard_ids.duplicate()
	snapshot["visible_records"] = visible_records.size()
	return snapshot


func _load_shard(metadata: Dictionary) -> Array[Dictionary]:
	var shard_id: String = str(metadata.get("id", ""))
	if _loaded_shards.has(shard_id):
		_metrics["cache_hits"] = int(_metrics.get("cache_hits", 0)) + 1
		_touch_shard(shard_id)
		return _loaded_shards[shard_id] as Array[Dictionary]
	_metrics["cache_misses"] = int(_metrics.get("cache_misses", 0)) + 1
	var relative_path: String = str(metadata.get("path", ""))
	var document: Dictionary = _read_json(SHARD_ROOT + relative_path)
	var records: Array[Dictionary] = []
	if document.is_empty():
		_metrics["missing_shards"] = int(_metrics.get("missing_shards", 0)) + 1
		_loaded_shards[shard_id] = records
		_touch_shard(shard_id)
		return records
	for raw_record: Variant in document.get("cities", []) as Array:
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		record["world_point"] = _projector.call(record.get("lon_lat", [])) as Vector2
		records.append(record)
	_loaded_shards[shard_id] = records
	_touch_shard(shard_id)
	_metrics["shard_parses"] = int(_metrics.get("shard_parses", 0)) + 1
	return records


func _touch_shard(shard_id: String) -> void:
	_lru_shard_ids.erase(shard_id)
	_lru_shard_ids.append(shard_id)


func _evict_to_limit(exempt: Dictionary) -> void:
	var guard: int = _lru_shard_ids.size() * 2 + 4
	while _loaded_shards.size() > _cache_limit and guard > 0:
		guard -= 1
		if _lru_shard_ids.is_empty():
			break
		var candidate: String = _lru_shard_ids.front()
		_lru_shard_ids.pop_front()
		if exempt.has(candidate):
			_lru_shard_ids.append(candidate)
			continue
		_loaded_shards.erase(candidate)
		_metrics["evictions"] = int(_metrics.get("evictions", 0)) + 1


func _project_bounds(bounds: Array) -> Rect2:
	if bounds.size() != 4:
		return Rect2()
	var minimum_longitude: float = float(bounds[0])
	var minimum_latitude: float = float(bounds[1])
	var maximum_longitude: float = float(bounds[2])
	var maximum_latitude: float = float(bounds[3])
	var middle_longitude: float = (minimum_longitude + maximum_longitude) * 0.5
	var middle_latitude: float = (minimum_latitude + maximum_latitude) * 0.5
	var samples: Array = [
		[minimum_longitude, minimum_latitude],
		[minimum_longitude, maximum_latitude],
		[maximum_longitude, minimum_latitude],
		[maximum_longitude, maximum_latitude],
		[middle_longitude, minimum_latitude],
		[middle_longitude, maximum_latitude],
		[minimum_longitude, middle_latitude],
		[maximum_longitude, middle_latitude],
	]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for sample: Array in samples:
		var point: Vector2 = _projector.call(sample) as Vector2
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum).grow(0.25)


func _record_visible(record: Dictionary, scope: String, zoom: float) -> bool:
	if scope == "city":
		return true
	var priority: int = int(record.get("label_priority", 0))
	if zoom < 12.0:
		return priority >= 84
	if zoom < 24.0:
		return priority >= 62
	if zoom < 48.0:
		return priority >= 48
	return priority >= 38


func _record_higher_priority(left: Dictionary, right: Dictionary) -> bool:
	var left_priority: int = int(left.get("label_priority", 0))
	var right_priority: int = int(right.get("label_priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	var left_population: int = int(left.get("population", 0))
	var right_population: int = int(right.get("population", 0))
	if left_population != right_population:
		return left_population > right_population
	return str(left.get("id", "")) < str(right.get("id", ""))


func _finish_query(started_usec: int, intersecting_shards: int, candidate_count: int) -> void:
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_metrics["last_query_ms"] = elapsed_ms
	_metrics["maximum_query_ms"] = maxf(float(_metrics.get("maximum_query_ms", 0.0)), elapsed_ms)
	_metrics["last_intersecting_shards"] = intersecting_shards
	_metrics["candidate_records"] = candidate_count
	_metrics["visible_records"] = visible_records.size()


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
