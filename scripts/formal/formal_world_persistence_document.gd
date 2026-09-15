class_name FormalWorldPersistenceDocument
extends RefCounted
## Narrow persistence representation owned by Formal World.
##
## JSON remains the outer file container so the existing atomic file boundary,
## backup behavior, and legacy raw-JSON saves keep working. The authoritative
## snapshot itself is encoded with Godot's Variant binary representation so
## numeric Variant types and IEEE-754 float bits never pass through JSON's
## decimal-number parser.

const FORMAT_FIELD: String = "persistence_format"
const FORMAT_ID: String = "formal_world_exact_variant_v1"
const SNAPSHOT_SCHEMA_FIELD: String = "snapshot_schema_id"
const PAYLOAD_FIELD: String = "payload_base64"


static func encode(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {}
	var payload_bytes: PackedByteArray = var_to_bytes(snapshot)
	if payload_bytes.is_empty():
		return {}
	return {
		FORMAT_FIELD: FORMAT_ID,
		SNAPSHOT_SCHEMA_FIELD: str(snapshot.get("schema_id", "")),
		PAYLOAD_FIELD: Marshalls.raw_to_base64(payload_bytes),
	}


static func decode(document: Dictionary) -> Dictionary:
	# Legacy Formal saves are the authoritative snapshot at the JSON root.
	if not document.has(FORMAT_FIELD):
		return {
			"success": true,
			"legacy": true,
			"snapshot": document,
			"error": "",
		}
	if str(document.get(FORMAT_FIELD, "")) != FORMAT_ID:
		return _fail("不支持的正式世界持久化格式")
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
	var decoded: Variant = bytes_to_var(payload_bytes, false)
	if not decoded is Dictionary:
		return _fail("正式世界精确载荷不是快照对象")
	var snapshot := decoded as Dictionary
	if str(snapshot.get("schema_id", "")) != str(document[SNAPSHOT_SCHEMA_FIELD]):
		return _fail("正式世界精确载荷版本与外层文档不一致")
	return {
		"success": true,
		"legacy": false,
		"snapshot": snapshot,
		"error": "",
	}


static func _fail(message: String) -> Dictionary:
	return {
		"success": false,
		"legacy": false,
		"snapshot": {},
		"error": message,
	}
