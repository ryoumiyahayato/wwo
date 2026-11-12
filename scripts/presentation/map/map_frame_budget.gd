extends RefCounted

const UPLOAD_USEC: int = 2500
const UPLOAD_BYTES: int = 64 * 1024 * 1024
const UPLOAD_OPERATIONS: int = 12
const RETIRE_OPERATIONS: int = 48

var uploaded_bytes: int
var operations: int
var retired: int
var _used_usec: int
var observations: Dictionary

func reset(costs: Dictionary = {}) -> void:
	uploaded_bytes = 0
	operations = 0
	retired = 0
	_used_usec = 0
	observations = costs

func claim_upload(bytes: int) -> bool:
	if operations >= UPLOAD_OPERATIONS or _used_usec >= UPLOAD_USEC or bytes > UPLOAD_BYTES - uploaded_bytes:
		return false
	operations += 1
	uploaded_bytes += bytes
	return true

func finish_upload(started: int, kind: String = "") -> void:
	var elapsed := Time.get_ticks_usec() - started
	_used_usec += elapsed
	if not observations.is_empty() and elapsed > int(observations.get("atomic_us",0)):
		observations["atomic_us"] = elapsed
		observations["atomic_kind"] = kind

func observe(stage: String, started: int) -> void:
	if not observations.is_empty():
		observations[stage] = int(observations.get(stage,0)) + Time.get_ticks_usec()-started

func claim_retirement() -> bool:
	if retired >= RETIRE_OPERATIONS: return false
	retired += 1
	return true

static func packed_bytes(value: Variant) -> int:
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY: return value.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY: return value.size()*4
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY: return value.size()*8
		TYPE_PACKED_VECTOR3_ARRAY: return value.size()*12
		TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY: return value.size()*16
		TYPE_ARRAY, TYPE_DICTIONARY:
			var result := 0
			var entries: Array = value.values() if value is Dictionary else value
			for item: Variant in entries: result += packed_bytes(item)
			return result
	return 0
