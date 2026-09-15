extends RefCounted
## Test-only prototype for a persistence-owned exact JSON numeric codec.
##
## Numeric leaves are removed from the JSON payload and represented exactly in
## the root numeric manifest. Literal null leaves are listed separately so a
## decoder can distinguish a genuine null from a numeric placeholder whose
## manifest entry was accidentally omitted.

const FORMAT_ID: String = "wwo.formal.exact-json.v1"
const FORMAT_FIELD: String = "format"
const PAYLOAD_FIELD: String = "payload"
const NUMBERS_FIELD: String = "numbers"
const LITERAL_NULLS_FIELD: String = "literal_nulls"
const F64_TYPE: String = "f64"
const I64_TYPE: String = "i64"


func encode_variant_tree(value: Variant) -> Dictionary:
	var numbers: Array = []
	var literal_nulls: Array = []
	var encoded := _encode_node(value, [], numbers, literal_nulls)
	if not bool(encoded.get("ok", false)):
		return _fail(str(encoded.get("error", "encode failed")))
	return {
		"ok": true,
		"value": {
			FORMAT_FIELD: FORMAT_ID,
			PAYLOAD_FIELD: encoded.get("value", null),
			NUMBERS_FIELD: numbers,
			LITERAL_NULLS_FIELD: literal_nulls,
		},
		"error": "",
		"stats": _manifest_stats(numbers, literal_nulls),
	}


func decode_variant_tree(envelope_value: Variant) -> Dictionary:
	if not envelope_value is Dictionary:
		return _fail("exact JSON envelope must be a Dictionary")
	var envelope := envelope_value as Dictionary
	if not _has_exact_string_keys(
		envelope,
		[FORMAT_FIELD, PAYLOAD_FIELD, NUMBERS_FIELD, LITERAL_NULLS_FIELD]
	):
		return _fail("exact JSON envelope fields are invalid")
	if str(envelope.get(FORMAT_FIELD, "")) != FORMAT_ID:
		return _fail("unknown exact JSON format discriminator")
	if not envelope.get(NUMBERS_FIELD, null) is Array:
		return _fail("numeric manifest must be an Array")
	if not envelope.get(LITERAL_NULLS_FIELD, null) is Array:
		return _fail("literal-null manifest must be an Array")

	var payload: Variant = envelope.get(PAYLOAD_FIELD, null)
	var payload_scan := _scan_payload(payload, [])
	if not bool(payload_scan.get("ok", false)):
		return _fail(str(payload_scan.get("error", "payload validation failed")))
	if int(payload_scan.get("numeric_leaves", -1)) != 0:
		return _fail("payload contains an authoritative numeric leaf")

	var null_paths: Dictionary = payload_scan.get("null_paths", {}) as Dictionary
	var claimed_paths: Dictionary = {}
	var literal_paths: Array = envelope.get(LITERAL_NULLS_FIELD, []) as Array
	for raw_path: Variant in literal_paths:
		var path_validation := _validate_path(raw_path)
		if not bool(path_validation.get("ok", false)):
			return _fail("literal-null path is malformed: %s" % path_validation.get("error", ""))
		var path := raw_path as Array
		var path_id := _path_id(path)
		if claimed_paths.has(path_id):
			return _fail("duplicate manifest path: %s" % path_id)
		var resolved := _resolve_path(payload, path)
		if not bool(resolved.get("ok", false)):
			return _fail("literal-null path cannot be resolved: %s" % resolved.get("error", ""))
		if typeof(resolved.get("value", 0)) != TYPE_NIL:
			return _fail("literal-null manifest target is not null")
		claimed_paths[path_id] = "null"

	var numbers: Array = envelope.get(NUMBERS_FIELD, []) as Array
	var validated_numbers: Array = []
	for raw_entry: Variant in numbers:
		if not raw_entry is Dictionary:
			return _fail("numeric manifest entry must be a Dictionary")
		var entry := raw_entry as Dictionary
		if not _has_exact_string_keys(entry, ["path", "type", "bits"]):
			return _fail("numeric manifest entry fields are invalid")
		var path_validation := _validate_path(entry.get("path", null))
		if not bool(path_validation.get("ok", false)):
			return _fail("numeric path is malformed: %s" % path_validation.get("error", ""))
		var path := entry.get("path", []) as Array
		var path_id := _path_id(path)
		if claimed_paths.has(path_id):
			return _fail("duplicate manifest path: %s" % path_id)
		var numeric_type := str(entry.get("type", ""))
		if numeric_type not in [F64_TYPE, I64_TYPE]:
			return _fail("unknown numeric type: %s" % numeric_type)
		var bits := str(entry.get("bits", ""))
		if not _is_canonical_bits(bits):
			return _fail("numeric bits must be 16 lowercase hexadecimal digits")
		var resolved := _resolve_path(payload, path)
		if not bool(resolved.get("ok", false)):
			return _fail("numeric path cannot be resolved: %s" % resolved.get("error", ""))
		if typeof(resolved.get("value", 0)) != TYPE_NIL:
			return _fail("numeric manifest target is not a null placeholder")
		claimed_paths[path_id] = numeric_type
		validated_numbers.append({
			"path": path.duplicate(true),
			"type": numeric_type,
			"bits": bits,
		})

	if claimed_paths.size() != null_paths.size():
		return _fail("payload null placeholders are not completely classified")
	for path_id: Variant in null_paths.keys():
		if not claimed_paths.has(path_id):
			return _fail("payload null placeholder is missing a manifest entry")

	var reconstructed: Variant = payload
	if payload is Dictionary:
		reconstructed = (payload as Dictionary).duplicate(true)
	elif payload is Array:
		reconstructed = (payload as Array).duplicate(true)
	for raw_entry: Variant in validated_numbers:
		var entry := raw_entry as Dictionary
		var decoded := _decode_numeric(str(entry["type"]), str(entry["bits"]))
		if not bool(decoded.get("ok", false)):
			return _fail(str(decoded.get("error", "numeric decode failed")))
		var replacement := _replace_at_path(
			reconstructed,
			entry["path"] as Array,
			decoded.get("value", null)
		)
		if not bool(replacement.get("ok", false)):
			return _fail(str(replacement.get("error", "numeric replacement failed")))
		reconstructed = replacement.get("value", null)

	return {
		"ok": true,
		"value": reconstructed,
		"error": "",
		"stats": _manifest_stats(numbers, literal_paths),
	}


func f64_bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return _little_endian_bytes_to_canonical_hex(bytes)


func i64_bits(value: int) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, value)
	return _little_endian_bytes_to_canonical_hex(bytes)


func f64_from_bits(bits: String) -> Dictionary:
	if not _is_canonical_bits(bits):
		return _fail("f64 bits are malformed")
	var bytes_result := _canonical_hex_to_little_endian_bytes(bits)
	if not bool(bytes_result.get("ok", false)):
		return bytes_result
	var bytes: PackedByteArray = bytes_result.get("value", PackedByteArray())
	return {"ok": true, "value": bytes.decode_double(0), "error": ""}


func i64_from_bits(bits: String) -> Dictionary:
	if not _is_canonical_bits(bits):
		return _fail("i64 bits are malformed")
	var bytes_result := _canonical_hex_to_little_endian_bytes(bits)
	if not bool(bytes_result.get("ok", false)):
		return bytes_result
	var bytes: PackedByteArray = bytes_result.get("value", PackedByteArray())
	return {"ok": true, "value": bytes.decode_s64(0), "error": ""}


func strict_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_FLOAT:
			return f64_bits(float(left)) == f64_bits(float(right))
		TYPE_DICTIONARY:
			var left_dict := left as Dictionary
			var right_dict := right as Dictionary
			if left_dict.size() != right_dict.size():
				return false
			for raw_key: Variant in left_dict.keys():
				if not right_dict.has(raw_key):
					return false
				if not strict_equal(left_dict[raw_key], right_dict[raw_key]):
					return false
			return true
		TYPE_ARRAY:
			var left_array := left as Array
			var right_array := right as Array
			if left_array.size() != right_array.size():
				return false
			for index: int in range(left_array.size()):
				if not strict_equal(left_array[index], right_array[index]):
					return false
			return true
		_:
			return left == right


func count_numeric_leaves(value: Variant) -> Dictionary:
	var counts := {"total": 0, "f64": 0, "i64": 0, "non_string_keys": 0}
	_count_numeric_node(value, counts)
	return counts


func _encode_node(
	value: Variant,
	path: Array,
	numbers: Array,
	literal_nulls: Array
) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			literal_nulls.append(path.duplicate(true))
			return {"ok": true, "value": null, "error": ""}
		TYPE_BOOL, TYPE_STRING:
			return {"ok": true, "value": value, "error": ""}
		TYPE_INT:
			numbers.append({
				"path": path.duplicate(true),
				"type": I64_TYPE,
				"bits": i64_bits(int(value)),
			})
			return {"ok": true, "value": null, "error": ""}
		TYPE_FLOAT:
			var numeric := float(value)
			if is_nan(numeric) or is_inf(numeric):
				return _fail("non-finite f64 cannot be persisted")
			numbers.append({
				"path": path.duplicate(true),
				"type": F64_TYPE,
				"bits": f64_bits(numeric),
			})
			return {"ok": true, "value": null, "error": ""}
		TYPE_ARRAY:
			var source_array := value as Array
			var encoded_array: Array = []
			for index: int in range(source_array.size()):
				var child_path := path.duplicate(true)
				child_path.append({"index": str(index)})
				var child := _encode_node(source_array[index], child_path, numbers, literal_nulls)
				if not bool(child.get("ok", false)):
					return child
				encoded_array.append(child.get("value", null))
			return {"ok": true, "value": encoded_array, "error": ""}
		TYPE_DICTIONARY:
			var source_dict := value as Dictionary
			var keys: Array[String] = []
			for raw_key: Variant in source_dict.keys():
				if typeof(raw_key) != TYPE_STRING:
					return _fail("Dictionary keys must be strings")
				keys.append(str(raw_key))
			keys.sort()
			var encoded_dict: Dictionary = {}
			for key: String in keys:
				var child_path := path.duplicate(true)
				child_path.append({"key": key})
				var child := _encode_node(source_dict[key], child_path, numbers, literal_nulls)
				if not bool(child.get("ok", false)):
					return child
				encoded_dict[key] = child.get("value", null)
			return {"ok": true, "value": encoded_dict, "error": ""}
		_:
			return _fail("unsupported Variant type in JSON persistence tree: %s" % type_string(typeof(value)))


func _scan_payload(value: Variant, path: Array) -> Dictionary:
	var null_paths: Dictionary = {}
	var scan := _scan_payload_node(value, path, null_paths)
	if not bool(scan.get("ok", false)):
		return scan
	return {
		"ok": true,
		"error": "",
		"numeric_leaves": int(scan.get("numeric_leaves", 0)),
		"null_paths": null_paths,
	}


func _scan_payload_node(value: Variant, path: Array, null_paths: Dictionary) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			null_paths[_path_id(path)] = true
			return {"ok": true, "error": "", "numeric_leaves": 0}
		TYPE_BOOL, TYPE_STRING:
			return {"ok": true, "error": "", "numeric_leaves": 0}
		TYPE_INT, TYPE_FLOAT:
			return {"ok": true, "error": "", "numeric_leaves": 1}
		TYPE_ARRAY:
			var array_total := 0
			var array := value as Array
			for index: int in range(array.size()):
				var child_path := path.duplicate(true)
				child_path.append({"index": str(index)})
				var child := _scan_payload_node(array[index], child_path, null_paths)
				if not bool(child.get("ok", false)):
					return child
				array_total += int(child.get("numeric_leaves", 0))
			return {"ok": true, "error": "", "numeric_leaves": array_total}
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			var keys: Array[String] = []
			for raw_key: Variant in dict.keys():
				if typeof(raw_key) != TYPE_STRING:
					return _fail("payload Dictionary keys must be strings")
				keys.append(str(raw_key))
			keys.sort()
			var dict_total := 0
			for key: String in keys:
				var child_path := path.duplicate(true)
				child_path.append({"key": key})
				var child := _scan_payload_node(dict[key], child_path, null_paths)
				if not bool(child.get("ok", false)):
					return child
				dict_total += int(child.get("numeric_leaves", 0))
			return {"ok": true, "error": "", "numeric_leaves": dict_total}
		_:
			return _fail("payload contains unsupported Variant type")


func _validate_path(path_value: Variant) -> Dictionary:
	if not path_value is Array:
		return _fail("path must be an Array")
	var path := path_value as Array
	for raw_segment: Variant in path:
		if not raw_segment is Dictionary:
			return _fail("path segment must be a Dictionary")
		var segment := raw_segment as Dictionary
		if segment.size() != 1:
			return _fail("path segment must have exactly one discriminator")
		if segment.has("key"):
			if typeof(segment["key"]) != TYPE_STRING:
				return _fail("key path segment must contain a String")
			continue
		if segment.has("index"):
			if typeof(segment["index"]) != TYPE_STRING:
				return _fail("index path segment must contain a String")
			var index_text := str(segment["index"])
			if not _is_canonical_index(index_text):
				return _fail("array index must be canonical non-negative decimal text")
			continue
		return _fail("path segment discriminator must be key or index")
	return {"ok": true, "value": path, "error": ""}


func _resolve_path(root: Variant, path: Array) -> Dictionary:
	var current: Variant = root
	for raw_segment: Variant in path:
		var segment := raw_segment as Dictionary
		if segment.has("key"):
			if not current is Dictionary:
				return _fail("path traverses a non-Dictionary value")
			var key := str(segment["key"])
			var dict := current as Dictionary
			if not dict.has(key):
				return _fail("Dictionary path key does not exist")
			current = dict[key]
		else:
			if not current is Array:
				return _fail("path traverses a non-Array value")
			var index_result := _parse_index(str(segment["index"]))
			if not bool(index_result.get("ok", false)):
				return index_result
			var index := int(index_result.get("value", -1))
			var array := current as Array
			if index < 0 or index >= array.size():
				return _fail("array index is out of bounds")
			current = array[index]
	return {"ok": true, "value": current, "error": ""}


func _replace_at_path(root: Variant, path: Array, replacement: Variant) -> Dictionary:
	if path.is_empty():
		return {"ok": true, "value": replacement, "error": ""}
	var current: Variant = root
	for index: int in range(path.size() - 1):
		var segment := path[index] as Dictionary
		if segment.has("key"):
			if not current is Dictionary:
				return _fail("replacement path traverses a non-Dictionary value")
			current = (current as Dictionary)[str(segment["key"])]
		else:
			if not current is Array:
				return _fail("replacement path traverses a non-Array value")
			var index_result := _parse_index(str(segment["index"]))
			if not bool(index_result.get("ok", false)):
				return index_result
			current = (current as Array)[int(index_result["value"])]
	var final_segment := path[path.size() - 1] as Dictionary
	if final_segment.has("key"):
		if not current is Dictionary:
			return _fail("replacement target parent is not a Dictionary")
		(current as Dictionary)[str(final_segment["key"])] = replacement
	else:
		if not current is Array:
			return _fail("replacement target parent is not an Array")
		var final_index_result := _parse_index(str(final_segment["index"]))
		if not bool(final_index_result.get("ok", false)):
			return final_index_result
		var final_index := int(final_index_result["value"])
		var final_array := current as Array
		if final_index < 0 or final_index >= final_array.size():
			return _fail("replacement array index is out of bounds")
		final_array[final_index] = replacement
	return {"ok": true, "value": root, "error": ""}


func _decode_numeric(numeric_type: String, bits: String) -> Dictionary:
	if numeric_type == F64_TYPE:
		var decoded := f64_from_bits(bits)
		if not bool(decoded.get("ok", false)):
			return decoded
		var numeric := float(decoded.get("value", 0.0))
		if is_nan(numeric) or is_inf(numeric):
			return _fail("non-finite f64 cannot be loaded")
		return {"ok": true, "value": numeric, "error": ""}
	if numeric_type == I64_TYPE:
		return i64_from_bits(bits)
	return _fail("unknown numeric type")


func _little_endian_bytes_to_canonical_hex(bytes: PackedByteArray) -> String:
	var result := ""
	for index: int in range(bytes.size() - 1, -1, -1):
		result += "%02x" % int(bytes[index])
	return result


func _canonical_hex_to_little_endian_bytes(bits: String) -> Dictionary:
	if not _is_canonical_bits(bits):
		return _fail("canonical bits are malformed")
	var bytes := PackedByteArray()
	bytes.resize(8)
	for canonical_index: int in range(8):
		var byte_text := bits.substr(canonical_index * 2, 2)
		var byte_value := byte_text.hex_to_int()
		bytes[7 - canonical_index] = byte_value
	return {"ok": true, "value": bytes, "error": ""}


func _is_canonical_bits(bits: String) -> bool:
	if bits.length() != 16:
		return false
	for index: int in range(bits.length()):
		var character := bits.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _is_canonical_index(text: String) -> bool:
	if text.is_empty():
		return false
	if text.length() > 1 and text.begins_with("0"):
		return false
	for index: int in range(text.length()):
		var character := text.substr(index, 1)
		if not "0123456789".contains(character):
			return false
	return text.length() <= 18


func _parse_index(text: String) -> Dictionary:
	if not _is_canonical_index(text):
		return _fail("array index text is invalid")
	var value: int = 0
	for index: int in range(text.length()):
		value = value * 10 + int(text.substr(index, 1))
	return {"ok": true, "value": value, "error": ""}


func _path_id(path: Array) -> String:
	return JSON.stringify(path, "", true, true)


func _has_exact_string_keys(dict: Dictionary, expected_keys: Array) -> bool:
	if dict.size() != expected_keys.size():
		return false
	for raw_key: Variant in dict.keys():
		if typeof(raw_key) != TYPE_STRING:
			return false
		if str(raw_key) not in expected_keys:
			return false
	for raw_expected_key: Variant in expected_keys:
		if typeof(raw_expected_key) != TYPE_STRING:
			return false
		var key := str(raw_expected_key)
		if not dict.has(key):
			return false
	return true


func _manifest_stats(numbers: Array, literal_nulls: Array) -> Dictionary:
	var f64_count := 0
	var i64_count := 0
	for raw_entry: Variant in numbers:
		if not raw_entry is Dictionary:
			continue
		var numeric_type := str((raw_entry as Dictionary).get("type", ""))
		if numeric_type == F64_TYPE:
			f64_count += 1
		elif numeric_type == I64_TYPE:
			i64_count += 1
	return {
		"numeric_leaves": numbers.size(),
		"f64_leaves": f64_count,
		"i64_leaves": i64_count,
		"literal_null_leaves": literal_nulls.size(),
	}


func _count_numeric_node(value: Variant, counts: Dictionary) -> void:
	match typeof(value):
		TYPE_INT:
			counts["total"] = int(counts["total"]) + 1
			counts["i64"] = int(counts["i64"]) + 1
		TYPE_FLOAT:
			counts["total"] = int(counts["total"]) + 1
			counts["f64"] = int(counts["f64"]) + 1
		TYPE_ARRAY:
			for child: Variant in value as Array:
				_count_numeric_node(child, counts)
		TYPE_DICTIONARY:
			for raw_key: Variant in (value as Dictionary).keys():
				if typeof(raw_key) != TYPE_STRING:
					counts["non_string_keys"] = int(counts["non_string_keys"]) + 1
				_count_numeric_node((value as Dictionary)[raw_key], counts)


func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": null, "error": error}
