class_name FormalDatedPoliticalAuthority
extends RefCounted
## Authoritative access to dated historical political identity and control
## evidence. This service never owns or mutates emergent political outcomes.

const SCHEMA_ID: String = "formal_dated_political_authority_v1"
const CATALOG_PATH: String = (
	"res://data/world_map/historical/political_units_1900.json"
)

var initialization_error: String = ""
var _records: Dictionary = {}
var _active_records: Dictionary = {}
var _introduced_records: Dictionary = {}
var _catalog_identity: Dictionary = {}
var _current_day_index: int = -1
var _last_boundary_change: Dictionary = {}


func configure(day_index: int = 0) -> bool:
	initialization_error = ""
	_records.clear()
	_active_records.clear()
	_introduced_records.clear()
	_catalog_identity.clear()
	_current_day_index = -1
	_last_boundary_change.clear()
	if day_index < 0:
		return _fail("正式历史政治权威收到无效日期")
	var document := _read_document()
	if document.is_empty():
		return false
	if int(document.get("schema_version", 0)) != 1:
		return _fail("历史政治单元目录 Schema 无效")
	var units := document.get("units", []) as Array
	var declared_count := int(document.get("unit_count", units.size()))
	for raw_unit: Variant in units:
		if not raw_unit is Dictionary:
			return _fail("历史政治单元目录包含非对象记录")
		var record := (raw_unit as Dictionary).duplicate(true)
		var entity_id := str(record.get("id", ""))
		if (
			entity_id.is_empty()
			or _records.has(entity_id)
			or not _valid_interval(record)
		):
			return _fail("历史政治单元身份或有效期无效：%s" % entity_id)
		var controller_id := str(record.get("controller_id", ""))
		if controller_id == entity_id:
			return _fail("历史政治单元不得控制自身：%s" % entity_id)
		record["entity_id"] = entity_id
		record["valid_from_day_index"] = _day_index_for_date(
			str(record.get("valid_from", ""))
		)
		record["expiration_day_index"] = _day_index_for_date(
			str(record.get("valid_to", ""))
		) + 1
		record["provenance"] = {
			"source_path": CATALOG_PATH,
			"schema_version": 1,
			"snapshot_date": str(document.get("snapshot_date", "")),
			"geometry_provider": str(document.get("geometry_provider", "")),
			"data_quality": str(
				record.get("data_quality", "dated_historical_gis")
			),
		}
		_records[entity_id] = record
	if _records.size() != declared_count:
		return _fail(
			"历史政治单元目录计数不一致：声明%d，加载%d" % [
				declared_count, _records.size(),
			]
		)
	for entity_id: String in _sorted_keys(_records):
		var controller_id := str(
			(_records[entity_id] as Dictionary).get("controller_id", "")
		)
		if not controller_id.is_empty() and not _records.has(controller_id):
			return _fail(
				"历史政治单元引用未知控制者：%s -> %s" % [
					entity_id, controller_id,
				]
			)
	_catalog_identity = {
		"source_path": CATALOG_PATH,
		"schema_version": 1,
		"snapshot_date": str(document.get("snapshot_date", "")),
		"geometry_provider": str(document.get("geometry_provider", "")),
		"record_count": _records.size(),
		"fingerprint": _catalog_fingerprint(),
	}
	return _set_day(day_index, false)


func advance_to_day(day_index: int) -> Dictionary:
	if day_index < 0 or _records.is_empty():
		return {}
	if day_index == _current_day_index:
		return _last_boundary_change.duplicate(true)
	if day_index < _current_day_index or not _set_day(day_index, true):
		return {}
	return _last_boundary_change.duplicate(true)


func snapshot(include_catalog: bool = false) -> Dictionary:
	var result := {
		"schema_id": SCHEMA_ID,
		"day_index": _current_day_index,
		"date": _date_for_day(_current_day_index),
		"catalog_identity": _catalog_identity.duplicate(true),
		"active_ids": _sorted_keys(_active_records),
		"introduced_ids": _sorted_keys(_introduced_records),
		"boundary_change": _last_boundary_change.duplicate(true),
	}
	if include_catalog:
		result["records"] = _records.duplicate(true)
		result["active_records"] = _active_records.duplicate(true)
	return result


func all_records() -> Dictionary:
	return _records.duplicate(true)


func active_records() -> Dictionary:
	return _active_records.duplicate(true)


func introduced_records() -> Dictionary:
	return _introduced_records.duplicate(true)


func record(entity_id: String) -> Dictionary:
	return (_records.get(entity_id, {}) as Dictionary).duplicate(true)


func has_record(entity_id: String) -> bool:
	return _records.has(entity_id)


func is_historically_valid(entity_id: String) -> bool:
	return _active_records.has(entity_id)


func catalog_identity() -> Dictionary:
	return _catalog_identity.duplicate(true)


func current_day_index() -> int:
	return _current_day_index


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"day_index": _current_day_index,
		"catalog_fingerprint": str(
			_catalog_identity.get("fingerprint", "")
		),
	}


func restore_persistent_state(state: Dictionary, expected_day_index: int) -> bool:
	if (
		str(state.get("schema_id", "")) != SCHEMA_ID
		or int(state.get("day_index", -1)) != expected_day_index
		or str(state.get("catalog_fingerprint", "")) != str(
			_catalog_identity.get("fingerprint", "")
		)
	):
		return false
	return _set_day(expected_day_index, false)


func _set_day(day_index: int, record_boundary: bool) -> bool:
	var date := _date_for_day(day_index)
	if date.is_empty():
		return false
	var next_active: Dictionary = {}
	var next_introduced: Dictionary = {}
	for entity_id: String in _sorted_keys(_records):
		var record := _records[entity_id] as Dictionary
		if str(record.get("valid_from", "")) <= date:
			next_introduced[entity_id] = record.duplicate(true)
		if _record_valid_on(record, date):
			next_active[entity_id] = record.duplicate(true)
	var activated: Array[String] = []
	var expired: Array[String] = []
	if record_boundary:
		for entity_id: String in _sorted_keys(next_active):
			if not _active_records.has(entity_id):
				activated.append(entity_id)
		for entity_id: String in _sorted_keys(_active_records):
			if not next_active.has(entity_id):
				expired.append(entity_id)
	_active_records = next_active
	_introduced_records = next_introduced
	_current_day_index = day_index
	_last_boundary_change = {
		"day_index": day_index,
		"date": date,
		"activated_ids": activated,
		"expired_ids": expired,
	}
	return true


func _record_valid_on(record: Dictionary, date: String) -> bool:
	return (
		str(record.get("valid_from", "")) <= date
		and date <= str(record.get("valid_to", ""))
	)


func _valid_interval(record: Dictionary) -> bool:
	var valid_from := str(record.get("valid_from", ""))
	var valid_to := str(record.get("valid_to", ""))
	return (
		_valid_date(valid_from)
		and _valid_date(valid_to)
		and valid_from <= valid_to
	)


func _valid_date(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	return (
		year > 0
		and month >= 1
		and month <= 12
		and day >= 1
		and day <= V2DateTime.days_in_month(year, month)
		and "%04d-%02d-%02d" % [year, month, day] == value
	)


func _date_for_day(day_index: int) -> String:
	if day_index < 0:
		return ""
	return V2DateTime.date_from_total_hour(day_index * 24)


func _day_index_for_date(date: String) -> int:
	var parts := date.split("-")
	if parts.size() != 3:
		return -1
	return (
		V2DateTime.absolute_day_index(
			int(parts[0]), int(parts[1]), int(parts[2])
		)
		- V2DateTime.absolute_day_index(1900, 1, 1)
	)


func _catalog_fingerprint() -> String:
	var canonical: Array[String] = []
	for entity_id: String in _sorted_keys(_records):
		var record := _records[entity_id] as Dictionary
		canonical.append("|".join([
			entity_id,
			str(record.get("valid_from", "")),
			str(record.get("valid_to", "")),
			str(record.get("status", "")),
			str(record.get("relationship", "")),
			str(record.get("controller_id", "")),
		]))
	return JSON.stringify(canonical).sha256_text()


func _read_document() -> Dictionary:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_fail("无法读取历史政治单元目录：%s" % CATALOG_PATH)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		_fail(
			"历史政治单元目录无效：%s:%d %s" % [
				CATALOG_PATH,
				parser.get_error_line(),
				parser.get_error_message(),
			]
		)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in dictionary:
		result.append(str(raw_key))
	result.sort()
	return result


func _fail(message: String) -> bool:
	initialization_error = message
	return false
