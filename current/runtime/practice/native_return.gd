extends RefCounted
## Pending native receipt boundary, never an inventory or an alternate world save.
const SCHEMA := "practice_native_return_v2"

static func valid_instance_id(instance_id: String) -> bool:
	if instance_id.is_empty() or instance_id.length()>80:return false
	for index: int in instance_id.length():
		var character:=instance_id.substr(index,1)
		if not "0123456789-".contains(character):return false
	return true

static func path(instance_id: String) -> String:
	return "user://practice_native_return_"+instance_id+".json"

static func write(instance_id: String, status: String, receipt: Dictionary, qualification: Dictionary={}, use_context: Dictionary={}, lease_anchor: Dictionary={}) -> String:
	if not valid_instance_id(instance_id):return "INVALID_PRACTICE_INSTANCE_ID"
	var document: Dictionary={"schema":SCHEMA,"instance_id":instance_id,"status":status,"receipt_base64":Marshalls.raw_to_base64(var_to_bytes(receipt)),"qualification_base64":Marshalls.raw_to_base64(var_to_bytes(qualification)),"use_context_base64":Marshalls.raw_to_base64(var_to_bytes(use_context)),"lease_anchor_base64":Marshalls.raw_to_base64(var_to_bytes(lease_anchor))}
	return AtomicJsonFileStore.write_verified(path(instance_id),document,Callable(load("res://practice/native_return.gd"),"verify"),true)

static func verify(file_path: String) -> String:
	var read:=read_file(file_path)
	return "" if read.get("ok",false) else str(read.get("reason","INVALID_NATIVE_RETURN"))

static func read_file(file_path: String) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(file_path))
	return decode(data)

static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary or not data.has_all(["schema","instance_id","status","receipt_base64"]) or data.get("schema") not in [SCHEMA,"practice_native_return_v1"] or not data.instance_id is String or not valid_instance_id(data.instance_id) or data.status not in ["idle","prepared_after_muzzle_ray","emitted_pending_formal_save","covered_by_formal_save"] or not data.receipt_base64 is String:return {"ok":false,"reason":"INVALID_NATIVE_RETURN_DOCUMENT"}
	if data.size()!=(7 if data.schema==SCHEMA else 4):return {"ok":false,"reason":"NATIVE_RETURN_FIELDS_MISMATCH"}
	var receipt: Variant=bytes_to_var(Marshalls.base64_to_raw(data.receipt_base64))
	if not receipt is Dictionary or (data.status!="idle" and not receipt.has_all(["receipt_id","physical","before","after"])):return {"ok":false,"reason":"INVALID_NATIVE_RETURN_RECEIPT"}
	var result: Dictionary={"ok":true,"instance_id":data.instance_id,"status":data.status,"receipt":receipt,"schema":data.schema}
	for key: String in ["qualification","use_context","lease_anchor"]:
		var payload: Variant=bytes_to_var(Marshalls.base64_to_raw(str(data.get(key+"_base64","")))) if data.schema==SCHEMA else {}
		if not payload is Dictionary:return {"ok":false,"reason":"NATIVE_RETURN_INVALID_"+key}
		result[key]=payload
	return result
