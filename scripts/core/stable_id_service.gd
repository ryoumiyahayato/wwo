class_name StableIdService
extends RefCounted
## Generates deterministic, serializable IDs without node or memory-address state.

const GENERATED_WIDTH: int = 8

var _counters: Dictionary = {}


func next_id(id_namespace: String) -> String:
	if not is_valid_namespace(id_namespace):
		return ""
	var next_value: int = int(_counters.get(id_namespace, 0)) + 1
	_counters[id_namespace] = next_value
	return "%s:%0*d" % [id_namespace, GENERATED_WIDTH, next_value]


func get_state() -> Dictionary:
	return _counters.duplicate(true)


func restore_state(state: Dictionary) -> bool:
	var validated: Dictionary = {}
	for raw_namespace: Variant in state:
		var id_namespace: String = str(raw_namespace)
		var value: Variant = state[raw_namespace]
		if not is_valid_namespace(id_namespace) or not _is_non_negative_integer(value):
			return false
		validated[id_namespace] = int(value)
	_counters = validated
	return true


static func is_valid_id(value: String) -> bool:
	var separator_index: int = value.find(":")
	if separator_index <= 0 or separator_index != value.rfind(":"):
		return false
	var id_namespace: String = value.left(separator_index)
	var slug: String = value.substr(separator_index + 1)
	return is_valid_namespace(id_namespace) and _is_valid_slug(slug)


static func get_namespace(value: String) -> String:
	if not is_valid_id(value):
		return ""
	return value.get_slice(":", 0)


static func is_valid_namespace(value: String) -> bool:
	if value.is_empty() or not _is_lowercase_letter(value.unicode_at(0)):
		return false
	for index: int in range(1, value.length()):
		var code: int = value.unicode_at(index)
		if not _is_lowercase_letter(code) and not _is_digit(code) and code != 95:
			return false
	return true


static func _is_valid_slug(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not _is_lowercase_letter(code) and not _is_digit(code) and code != 95 and code != 45:
			return false
	return true


static func _is_lowercase_letter(code: int) -> bool:
	return code >= 97 and code <= 122


static func _is_digit(code: int) -> bool:
	return code >= 48 and code <= 57


static func _is_non_negative_integer(value: Variant) -> bool:
	if not value is int and not value is float:
		return false
	var numeric: float = float(value)
	return numeric >= 0.0 and numeric == floor(numeric)
