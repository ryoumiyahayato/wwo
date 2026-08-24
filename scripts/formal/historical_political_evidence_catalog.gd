class_name HistoricalPoliticalEvidenceCatalog
extends RefCounted
## Immutable access boundary for dated political evidence. Catalog membership is
## never a statement that an entity exists in the current simulated world.

const DEFAULT_PATH: String = "res://data/world_map/historical/political_units_1900.json"
const EXPECTED_RECORD_COUNT: int = 151

var initialization_error: String = ""
var _configured: bool = false
var _fingerprint: String = ""
var _snapshot_date: String = ""
var _records_by_source_id: Dictionary = {}
var _sorted_source_ids: Array[String] = []


func configure(path: String = DEFAULT_PATH) -> bool:
	initialization_error = ""
	_configured = false
	_fingerprint = ""
	_snapshot_date = ""
	_records_by_source_id.clear()
	_sorted_source_ids.clear()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("无法读取历史政治证据：%s" % path)
	var source_text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(source_text)
	if parse_error != OK or not parser.data is Dictionary:
		return _fail("历史政治证据 JSON 无效：%s" % path)
	var document := parser.data as Dictionary
	var units_value: Variant = document.get("units", [])
	if not units_value is Array:
		return _fail("历史政治证据缺少 units 数组")
	var units := units_value as Array
	if (
		int(document.get("unit_count", -1)) != units.size()
		or units.size() != EXPECTED_RECORD_COUNT
	):
		return _fail("历史政治证据必须包含 %d 条记录" % EXPECTED_RECORD_COUNT)

	for unit_value: Variant in units:
		if not unit_value is Dictionary:
			return _fail("历史政治证据记录必须是对象")
		var record := (unit_value as Dictionary).duplicate(true)
		var source_id := str(record.get("id", ""))
		var valid_from := str(record.get("valid_from", ""))
		var valid_to := str(record.get("valid_to", ""))
		if (
			source_id.is_empty()
			or _records_by_source_id.has(source_id)
			or not _is_valid_date(valid_from)
			or not _is_valid_date(valid_to)
			or valid_from > valid_to
		):
			return _fail("历史政治证据记录无效或重复：%s" % source_id)
		record["source_historical_id"] = source_id
		record["provenance"] = {
			"dataset": path,
			"geometry_provider": str(record.get("geometry_provider", "")),
			"data_quality": str(record.get("data_quality", "")),
		}
		_records_by_source_id[source_id] = record
		_sorted_source_ids.append(source_id)

	_sorted_source_ids.sort()
	_snapshot_date = str(document.get("snapshot_date", ""))
	if not _is_valid_date(_snapshot_date):
		return _fail("历史政治证据 snapshot_date 无效")
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return _fail("无法初始化历史政治证据指纹")
	if hashing.update(source_text.to_utf8_buffer()) != OK:
		return _fail("无法计算历史政治证据指纹")
	_fingerprint = hashing.finish().hex_encode()
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func record_count() -> int:
	return _records_by_source_id.size()


func fingerprint() -> String:
	return _fingerprint


func snapshot_date() -> String:
	return _snapshot_date


func has_source(source_historical_id: String) -> bool:
	return _records_by_source_id.has(source_historical_id)


func record(source_historical_id: String) -> Dictionary:
	return (
		(_records_by_source_id.get(source_historical_id, {}) as Dictionary)
		.duplicate(true)
	)


func source_ids() -> Array[String]:
	return _sorted_source_ids.duplicate()


func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source_id: String in _sorted_source_ids:
		result.append(record(source_id))
	return result


func records_active_on(date: String) -> Array[Dictionary]:
	if not _is_valid_date(date):
		return []
	var result: Array[Dictionary] = []
	for source_id: String in _sorted_source_ids:
		var candidate := _records_by_source_id[source_id] as Dictionary
		if (
			str(candidate.get("valid_from", "")) <= date
			and date <= str(candidate.get("valid_to", ""))
		):
			result.append(candidate.duplicate(true))
	return result


func source_ids_active_on(date: String) -> Array[String]:
	var result: Array[String] = []
	for candidate: Dictionary in records_active_on(date):
		result.append(str(candidate.get("source_historical_id", "")))
	return result


func _is_valid_date(value: String) -> bool:
	if (
		value.length() != 10
		or value.substr(4, 1) != "-"
		or value.substr(7, 1) != "-"
	):
		return false
	var year_text := value.substr(0, 4)
	var month_text := value.substr(5, 2)
	var day_text := value.substr(8, 2)
	if (
		not year_text.is_valid_int()
		or not month_text.is_valid_int()
		or not day_text.is_valid_int()
	):
		return false
	var year := int(year_text)
	var month := int(month_text)
	var day := int(day_text)
	return (
		year > 0
		and month >= 1
		and month <= 12
		and day >= 1
		and day <= V2DateTime.days_in_month(year, month)
	)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
