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
	var found: String = str(document.get(SNAPSHOT_SCHEMA_FIELD, document.get("schema_id", "missing")))
	if str(document.get(FORMAT_FIELD, "missing")) != FORMAT_ID or found != FormalPersistence.SCHEMA_ID:
		var failure: Dictionary = _fail("SAVE FORMAT VERSION MISMATCH\nExpected: %s / %s\nFound: %s / %s\nReason: Formal land geometry, sovereignty, current control and split lineage require spatial land fields; old saves cannot infer fine land." % [FORMAT_ID, FormalPersistence.SCHEMA_ID, document.get(FORMAT_FIELD, "missing"), found])
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
		var failure: Dictionary = _fail("SAVE FORMAT VERSION MISMATCH\nExpected: %s\nFound: %s\nReason: Formal land geometry, sovereignty, current control and split lineage require spatial land fields; old saves cannot infer fine land." % [FormalPersistence.SCHEMA_ID, snapshot.get("schema_id", "missing")])
		failure["error_code"] = "save_format_version_mismatch"
		return failure
	return {
		"success": true,
		"snapshot": snapshot,
		"error": "",
	}


static func _fail(message: String) -> Dictionary:
	return {
		"success": false,
		"snapshot": {},
		"error": message,
	}
