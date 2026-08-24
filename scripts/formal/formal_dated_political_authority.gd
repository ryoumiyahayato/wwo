class_name FormalDatedPoliticalAuthority
extends RefCounted
## Authoritative dated view of the formal world's historical political catalog.
## Static evidence is retained in full; runtime queries expose only entities whose
## validity interval contains the simulation date.

const CATALOG_PATH: String = (
	"res://data/world_map/historical/political_units_1900.json"
)
const SNAPSHOT_SCHEMA_ID: String = "formal_dated_political_authority_v1"

var initialization_error: String = ""

var _authoritative_hour_source: Callable = Callable()
var _records_by_id: Dictionary = {}
var _all_ids: Array[String] = []
var _active_ids: Array[String] = []
var _active_lookup: Dictionary = {}
var _catalog_provenance: Dictionary = {}
var _catalog_sha256: String = ""
var _current_date: String = ""
var _active_set_revision: int = 0
var _configured: bool = false


func bind_authoritative_hour_source(source: Callable) -> void:
	_authoritative_hour_source = source


func configure() -> bool:
	initialization_error = ""
	_records_by_id.clear()
	_all_ids.clear()
	_active_ids.clear()
	_active_lookup.clear()
	_catalog_provenance.clear()
	_catalog_sha256 = ""
	_current_date = ""
	_active_set_revision = 0
	_configured = false
	if not _authoritative_hour_source.is_valid():
		return _fail("政治权威缺少正式模拟时间源")
	var document := _read_document(CATALOG_PATH)
	if document.is_empty():
		return false
	var units_value: Variant = document.get("units", [])
	if (
		int(document.get("schema_version", -1)) != 1
		or not units_value is Array
		or not _is_iso_date(str(document.get("snapshot_date", "")))
	):
		return _fail("历史政治单元目录 Schema 或快照日期无效")
	for raw_unit: Variant in units_value as Array:
		if not raw_unit is Dictionary:
			return _fail("历史政治单元记录必须是对象")
		var unit := (raw_unit as Dictionary).duplicate(true)
		var entity_id := str(unit.get("id", ""))
		if (
			entity_id.is_empty()
			or _records_by_id.has(entity_id)
			or not _valid_interval(unit)
		):
			return _fail("历史政治单元ID重复、为空或有效期无效：%s" % entity_id)
		_records_by_id[entity_id] = unit
		_all_ids.append(entity_id)
	var declared_count := int(document.get("unit_count", -1))
	if _records_by_id.is_empty() or declared_count != _records_by_id.size():
		return _fail(
			"历史政治单元目录计数不一致：声明%d，加载%d" % [
				declared_count, _records_by_id.size(),
			]
		)
	_all_ids.sort()
	for entity_id: String in _all_ids:
		var controller_id := str(
			(_records_by_id[entity_id] as Dictionary).get("controller_id", "")
		)
		if not controller_id.is_empty() and not _records_by_id.has(controller_id):
			return _fail(
				"历史政治单元引用未知控制方：%s -> %s" % [
					entity_id, controller_id,
				]
			)
		if not _controller_chain_is_acyclic(entity_id):
			return _fail("历史政治控制链存在循环：%s" % entity_id)
	_catalog_sha256 = FileAccess.get_sha256(CATALOG_PATH)
	if _catalog_sha256.is_empty():
		return _fail("无法计算历史政治目录指纹")
	_catalog_provenance = {
		"catalog_path": CATALOG_PATH,
		"catalog_sha256": _catalog_sha256,
		"schema_version": int(document.get("schema_version", -1)),
		"snapshot_date": str(document.get("snapshot_date", "")),
		"geometry_provider": str(document.get("geometry_provider", "")),
		"policy": (document.get("policy", {}) as Dictionary).duplicate(true),
	}
	_configured = true
	if not synchronize():
		_configured = false
		return false
	return true


func is_configured() -> bool:
	return _configured and not _records_by_id.is_empty()


func synchronize() -> bool:
	if not is_configured() or not _authoritative_hour_source.is_valid():
		return false
	var total_hour := int(_authoritative_hour_source.call())
	var query_date := V2DateTime.date_from_total_hour(total_hour)
	if total_hour < 0 or query_date.is_empty():
		return _fail("正式模拟时间无法转换为政治查询日期")
	if query_date == _current_date:
		return true
	var next_ids: Array[String] = []
	var next_lookup: Dictionary = {}
	for entity_id: String in _all_ids:
		var record := _records_by_id[entity_id] as Dictionary
		if _supports_date(record, query_date):
			next_ids.append(entity_id)
			next_lookup[entity_id] = true
	if next_ids != _active_ids:
		_active_set_revision += 1
	_active_ids = next_ids
	_active_lookup = next_lookup
	_current_date = query_date
	return true


func current_date() -> String:
	_ensure_synchronized()
	return _current_date


func active_set_revision() -> int:
	_ensure_synchronized()
	return _active_set_revision


func total_record_count() -> int:
	return _records_by_id.size()


func active_entity_count() -> int:
	_ensure_synchronized()
	return _active_ids.size()


func all_entity_ids() -> Array[String]:
	return _all_ids.duplicate()


func active_entity_ids() -> Array[String]:
	_ensure_synchronized()
	return _active_ids.duplicate()


func active_entity_ids_on(query_date: String) -> Array[String]:
	var result: Array[String] = []
	if not _is_iso_date(query_date):
		return result
	for entity_id: String in _all_ids:
		if _supports_date(_records_by_id[entity_id] as Dictionary, query_date):
			result.append(entity_id)
	return result


func has_catalog_entity(entity_id: String) -> bool:
	return _records_by_id.has(entity_id)


func entity_exists(entity_id: String) -> bool:
	_ensure_synchronized()
	return _active_lookup.has(entity_id)


func entity_exists_on(entity_id: String, query_date: String) -> bool:
	return (
		_is_iso_date(query_date)
		and _records_by_id.has(entity_id)
		and _supports_date(_records_by_id[entity_id] as Dictionary, query_date)
	)


func catalog_record(entity_id: String) -> Dictionary:
	var value: Variant = _records_by_id.get(entity_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func active_entity(entity_id: String) -> Dictionary:
	if not entity_exists(entity_id):
		return {}
	return _runtime_record(entity_id)


func active_entities() -> Array[Dictionary]:
	_ensure_synchronized()
	var result: Array[Dictionary] = []
	for entity_id: String in _active_ids:
		result.append(_runtime_record(entity_id))
	return result


func administrative_owner_id(entity_id: String) -> String:
	if not entity_exists(entity_id):
		return ""
	var record := _records_by_id[entity_id] as Dictionary
	var controller_id := str(record.get("controller_id", ""))
	return entity_id if controller_id.is_empty() else controller_id


func root_authority_id(entity_id: String) -> String:
	if not entity_exists(entity_id):
		return ""
	var current_id := entity_id
	var visited: Dictionary = {}
	while not current_id.is_empty() and not visited.has(current_id):
		visited[current_id] = true
		var record := _records_by_id[current_id] as Dictionary
		var controller_id := str(record.get("controller_id", ""))
		if controller_id.is_empty():
			return current_id
		if not entity_exists(controller_id):
			return ""
		current_id = controller_id
	return ""


func controlled_entity_ids(controller_id: String) -> Array[String]:
	_ensure_synchronized()
	if not _active_lookup.has(controller_id):
		return []
	var result: Array[String] = []
	for entity_id: String in _active_ids:
		var record := _records_by_id[entity_id] as Dictionary
		if str(record.get("controller_id", "")) == controller_id:
			result.append(entity_id)
	return result


func temporal_status(entity_id: String) -> String:
	if not has_catalog_entity(entity_id):
		return "unknown_entity"
	return "active" if entity_exists(entity_id) else "outside_validity_interval"


func provenance() -> Dictionary:
	return _catalog_provenance.duplicate(true)


func get_persistent_state() -> Dictionary:
	_ensure_synchronized()
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"total_hour": int(_authoritative_hour_source.call()),
		"current_date": _current_date,
		"catalog_sha256": _catalog_sha256,
		"active_entity_ids": _active_ids.duplicate(),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if not is_configured() or not synchronize():
		return false
	if (
		str(state.get("schema_id", "")) != SNAPSHOT_SCHEMA_ID
		or int(state.get("total_hour", -1))
		!= int(_authoritative_hour_source.call())
		or str(state.get("current_date", "")) != _current_date
		or str(state.get("catalog_sha256", "")) != _catalog_sha256
		or not state.get("active_entity_ids", []) is Array
	):
		return false
	return DataRecordUtils.to_string_array(
		state.get("active_entity_ids", [])
	) == _active_ids


func _runtime_record(entity_id: String) -> Dictionary:
	var result := (_records_by_id[entity_id] as Dictionary).duplicate(true)
	result["entity_id"] = entity_id
	result["exists"] = true
	result["simulation_date"] = _current_date
	result["administrative_owner_id"] = administrative_owner_id(entity_id)
	result["root_authority_id"] = root_authority_id(entity_id)
	result["political_provenance"] = _catalog_provenance.duplicate(true)
	return result


func _ensure_synchronized() -> void:
	assert(synchronize(), "Formal dated political authority could not synchronize")


func _controller_chain_is_acyclic(entity_id: String) -> bool:
	var current_id := entity_id
	var visited: Dictionary = {}
	while not current_id.is_empty():
		if visited.has(current_id):
			return false
		visited[current_id] = true
		var record := _records_by_id.get(current_id, {}) as Dictionary
		current_id = str(record.get("controller_id", ""))
	return true


static func _valid_interval(record: Dictionary) -> bool:
	var valid_from := str(record.get("valid_from", ""))
	var valid_to := str(record.get("valid_to", ""))
	return (
		_is_iso_date(valid_from)
		and _is_iso_date(valid_to)
		and valid_from <= valid_to
	)


static func _supports_date(record: Dictionary, query_date: String) -> bool:
	return (
		str(record.get("valid_from", "")) <= query_date
		and query_date <= str(record.get("valid_to", ""))
	)


static func _is_iso_date(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9]:
		var codepoint := value.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
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
	)


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取历史政治目录：%s" % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		_fail(
			"历史政治目录无效：%s:%d %s" % [
				path, parser.get_error_line(), parser.get_error_message(),
			]
		)
		return {}
	if not parser.data is Dictionary:
		_fail("历史政治目录根节点必须是对象：%s" % path)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
