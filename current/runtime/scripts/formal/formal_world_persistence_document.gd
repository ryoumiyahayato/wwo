class_name FormalWorldPersistenceDocument
extends RefCounted
## Narrow persistence representation owned by Formal World.
##
## JSON remains the outer container for atomic writes and file backups. The authoritative
## snapshot itself is encoded with Godot's Variant binary representation so
## numeric Variant types and IEEE-754 float bits never pass through JSON's
## decimal-number parser.

const FORMAT_FIELD: String = "persistence_format"
const FORMAT_ID: String = "formal_world_exact_variant_v1"
const SNAPSHOT_SCHEMA_FIELD: String = "snapshot_schema_id"
const PAYLOAD_FIELD: String = "payload_base64"
const METADATA_FIELD: String = "save_metadata"
const METADATA_SCHEMA: String = "formal_save_metadata_v1"


static func encode(snapshot: Dictionary, previous_metadata: Dictionary = {}) -> Dictionary:
	if snapshot.is_empty():
		return {}
	var payload_bytes: PackedByteArray = var_to_bytes(snapshot)
	if payload_bytes.is_empty():
		return {}
	return {
		FORMAT_FIELD: FORMAT_ID,
		SNAPSHOT_SCHEMA_FIELD: str(snapshot.get("schema_id", "")),
		PAYLOAD_FIELD: Marshalls.raw_to_base64(payload_bytes),
		METADATA_FIELD: next_metadata(previous_metadata),
	}

static func current_game_version() -> Dictionary:
	return {"build_id":str(ProjectSettings.get_setting("application/config/build_id","")),
		"build_label":str(ProjectSettings.get_setting("application/config/build_label","")),
		"application_version":str(ProjectSettings.get_setting("application/config/version","")),
		"build_sequence":int(ProjectSettings.get_setting("application/config/build_sequence",0))}

static func next_metadata(previous: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var result := previous.duplicate(true) if not previous.is_empty() else {
		"schema_id":METADATA_SCHEMA,"created_game_version":current_game_version(),"created_at_unix":now,
		"original_persistence_format":FORMAT_ID,"original_snapshot_schema_id":FormalPersistence.SCHEMA_ID,"migration_history":[]}
	result["last_saved_game_version"] = current_game_version()
	result["last_saved_at_unix"] = now
	return result

static func metadata(document: Dictionary) -> Dictionary:
	if document.get(METADATA_FIELD) is Dictionary: return (document[METADATA_FIELD] as Dictionary).duplicate(true)
	# The earlier UI summary describes its last writer. It is not evidence of
	# the creator, and filesystem timestamps are never used to infer one.
	var raw: Variant = document.get("ui_summary",{})
	var summary: Dictionary = raw if raw is Dictionary else {}
	var last_version: Variant = null
	var last_time: Variant = summary.get("saved_at_unix")
	if typeof(last_time) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(last_time)) or float(last_time)<=0.0 or float(last_time)!=floorf(float(last_time)): last_time = null
	if not str(summary.get("build_label","")).is_empty():
		last_version = {"build_label":str(summary.build_label),"application_version":str(summary.get("application_version","")),"build_id":"","build_sequence":0}
	return {"schema_id":METADATA_SCHEMA,"created_game_version":null,"created_at_unix":null,
		"last_saved_game_version":last_version,"last_saved_at_unix":last_time,
		"original_persistence_format":str(document.get(FORMAT_FIELD,"未记录")),
		"original_snapshot_schema_id":str(document.get(SNAPSHOT_SCHEMA_FIELD,document.get("schema_id","未记录"))),"migration_history":[]}

static func _metadata_error(document: Dictionary) -> String:
	if not document.has(METADATA_FIELD): return ""
	if not document[METADATA_FIELD] is Dictionary: return "存档版本资料不是对象。"
	var data := document[METADATA_FIELD] as Dictionary
	if data.get("schema_id")!=METADATA_SCHEMA: return "不支持的存档版本资料格式。"
	if not data.has_all(["created_game_version","created_at_unix","last_saved_game_version","last_saved_at_unix","original_persistence_format","original_snapshot_schema_id","migration_history"]): return "存档版本资料缺少字段。"
	for key: String in ["created_game_version","last_saved_game_version"]:
		if data[key]!=null and not data[key] is Dictionary: return "存档游戏版本资料无效。"
		if data[key] is Dictionary:
			var version := data[key] as Dictionary
			for field: String in ["build_id","build_label","application_version"]:
				if not version.get(field,"") is String: return "存档游戏版本字段无效。"
			var sequence: Variant = version.get("build_sequence",0)
			if typeof(sequence) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(sequence)) or float(sequence)<0.0 or float(sequence)!=floorf(float(sequence)): return "存档游戏版本次序无效。"
	for key: String in ["created_at_unix","last_saved_at_unix"]:
		if data[key]!=null and (typeof(data[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key])<=0.0 or float(data[key])!=floorf(float(data[key]))): return "存档时间资料无效。"
	if not data.original_persistence_format is String or not data.original_snapshot_schema_id is String or not data.migration_history is Array: return "存档原始格式或迁移记录无效。"
	return ""

static func migration_required(document: Dictionary) -> bool:
	var format := str(document.get(FORMAT_FIELD,""))
	var schema := str(document.get(SNAPSHOT_SCHEMA_FIELD,document.get("schema_id","")))
	var prefix := "formal_world_simulation_v"
	if format not in ["",FORMAT_ID] or not schema.begins_with(prefix): return false
	var number := schema.trim_prefix(prefix)
	return number.is_valid_int() and int(number)>=1 and int(number)<int(FormalPersistence.SCHEMA_ID.trim_prefix(prefix))

static func decode(document: Dictionary) -> Dictionary:
	var found: String = str(document.get(SNAPSHOT_SCHEMA_FIELD, document.get("schema_id", "missing")))
	if str(document.get(FORMAT_FIELD, "missing")) != FORMAT_ID or found != FormalPersistence.SCHEMA_ID:
		var requires_conversion := migration_required(document)
		var reason := "旧版存档，需要转换。本版没有此格式的转换器，不能直接读取；原文件未修改。" if requires_conversion else "版本不兼容：不支持此存档格式；原文件未修改。"
		var failure: Dictionary = _fail(reason+"\n当前支持：%s / %s\n文件格式：%s / %s" % [FORMAT_ID,FormalPersistence.SCHEMA_ID,document.get(FORMAT_FIELD,"未记录"),found])
		failure["error_code"] = "save_migration_required" if requires_conversion else "save_format_version_mismatch"
		return failure
	var metadata_error := _metadata_error(document)
	if not metadata_error.is_empty():
		var failure := _fail(metadata_error)
		if document.get(METADATA_FIELD) is Dictionary and (document[METADATA_FIELD] as Dictionary).get("schema_id")!=METADATA_SCHEMA:
			failure["error_code"] = "save_format_version_mismatch"
		return failure
	if typeof(document.get(SNAPSHOT_SCHEMA_FIELD, null)) != TYPE_STRING:
		return _fail("正式世界持久化文档缺少快照版本")
	if typeof(document.get(PAYLOAD_FIELD, null)) != TYPE_STRING:
		return _fail("正式世界持久化文档缺少精确载荷")
	var payload_text := str(document.get(PAYLOAD_FIELD, ""))
	if payload_text.is_empty():
		return _fail("正式世界精确载荷为空")
	var payload_bytes: PackedByteArray = Marshalls.base64_to_raw(payload_text)
	if payload_bytes.is_empty():
		return _fail("正式世界精确载荷无法解码")
	var decoded: Variant = bytes_to_var(payload_bytes)
	if not decoded is Dictionary:
		return _fail("正式世界精确载荷不是快照对象")
	var snapshot := decoded as Dictionary
	if str(snapshot.get("schema_id", "missing")) != FormalPersistence.SCHEMA_ID:
		var failure: Dictionary = _fail("存档载荷版本与文件声明不一致，不能读取；原文件未修改。\n声明：%s\n载荷：%s" % [FormalPersistence.SCHEMA_ID, snapshot.get("schema_id", "missing")])
		failure["error_code"] = "save_format_version_mismatch"
		return failure
	return {
		"success": true,
		"snapshot": snapshot,
		"error": "",
		"save_metadata":metadata(document),
	}


static func _fail(message: String) -> Dictionary:
	return {
		"success": false,
		"snapshot": {},
		"error": message,
	}
