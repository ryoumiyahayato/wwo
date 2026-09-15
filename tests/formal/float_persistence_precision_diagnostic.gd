extends SceneTree
## Diagnostic-only probe for Godot 4.6.3 float persistence behavior.
##
## This script deliberately stops at the 180-day persistence boundary. It does
## not modify product persistence behavior, Economy, fingerprinting, or Formal
## baseline artifacts.

const SAVE_RESTORE_DAY: int = 180
const MINUTES_PER_DAY: int = 24 * 60
const JEWELRY_MARKET_ID := "market:legacy_aggregate:sultanate_of_zanzibar"
const JEWELRY_COMMODITY_ID := "jewelry_watches"
const JAPAN_MARKET_ID := "market:legacy_aggregate:empire_of_japan"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	if not simulation.initialize():
		printerr("FLOAT_DIAG_SETUP_ERROR=%s" % simulation.initialization_error)
		quit(1)
		return

	simulation.advance_minutes(SAVE_RESTORE_DAY * MINUTES_PER_DAY)
	var state := simulation.get_persistent_state()
	var jewelry_value: Variant = _jewelry_probe_value(state)
	var japan_value: Variant = _japan_produced_units_value(state)

	_probe_authoritative_float("JEWELRY_WATCHES_PRODUCED", jewelry_value)
	_probe_authoritative_float("EMPIRE_OF_JAPAN_PRODUCED_UNITS", japan_value)

	if _failures > 0:
		printerr("FLOAT_PERSISTENCE_DIAGNOSTIC_FAILED=%d" % _failures)
		quit(1)
		return
	print("FLOAT_PERSISTENCE_DIAGNOSTIC_COMPLETE=2")
	quit(0)


func _probe_authoritative_float(label: String, raw_value: Variant) -> void:
	print("FLOAT_DIAG_BEGIN=%s" % label)
	print("FLOAT_DIAG_%s_VARIANT_TYPE=%s" % [label, type_string(typeof(raw_value))])
	if typeof(raw_value) != TYPE_FLOAT:
		printerr("FLOAT_DIAG_%s_ERROR=authoritative probe is not float" % label)
		_failures += 1
		return

	var source: float = float(raw_value)
	var source_hex := _ieee754_hex(source)
	var source_bytes_hex := _double_bytes_hex(source)
	var json_text := JSON.stringify(source, "", true, true)
	var scientific_text := String.num_scientific(source)
	var num_text := String.num(source)
	var direct: float = json_text.to_float()
	var direct_hex := _ieee754_hex(direct)
	var json_parsed: Variant = _json_number_from_text(json_text)
	var json_hex := _variant_float_hex(json_parsed)

	print("FLOAT_DIAG_%s_SOURCE_IEEE754_HEX=%s" % [label, source_hex])
	print("FLOAT_DIAG_%s_SOURCE_ENCODE_DOUBLE_BYTES=%s" % [label, source_bytes_hex])
	print("FLOAT_DIAG_%s_FULL_PRECISION_JSON_TEXT=%s" % [label, json_text])
	print("FLOAT_DIAG_%s_NUM_SCIENTIFIC_TEXT=%s" % [label, scientific_text])
	print("FLOAT_DIAG_%s_STRING_NUM_TEXT=%s" % [label, num_text])
	print("FLOAT_DIAG_%s_DIRECT_STRING_PARSE_IEEE754_HEX=%s" % [label, direct_hex])
	print(
		"FLOAT_DIAG_%s_DIRECT_STRING_PARSE_FULL_PRECISION=%s"
		% [label, JSON.stringify(direct, "", true, true)]
	)
	print("FLOAT_DIAG_%s_JSON_PARSE_VARIANT_TYPE=%s" % [label, type_string(typeof(json_parsed))])
	print("FLOAT_DIAG_%s_JSON_PARSE_IEEE754_HEX=%s" % [label, json_hex])
	if typeof(json_parsed) == TYPE_FLOAT:
		print(
			"FLOAT_DIAG_%s_JSON_PARSE_FULL_PRECISION=%s"
			% [label, JSON.stringify(float(json_parsed), "", true, true)]
		)

	if direct_hex == source_hex and json_hex == source_hex:
		print("FLOAT_DIAG_%s_FIRST_RUNTIME_DIVERGENCE=NONE" % label)
	elif direct_hex == source_hex and json_hex != source_hex:
		print("FLOAT_DIAG_%s_FIRST_RUNTIME_DIVERGENCE=JSON_PARSER_EXTRA" % label)
	elif direct_hex != source_hex and json_hex == direct_hex:
		print("FLOAT_DIAG_%s_FIRST_RUNTIME_DIVERGENCE=AT_OR_BEFORE_STRING_TO_FLOAT" % label)
	else:
		print("FLOAT_DIAG_%s_FIRST_RUNTIME_DIVERGENCE=MULTIPLE_OR_UNRESOLVED" % label)

	_probe_decimal_candidate(label, source, "JSON_FULL_PRECISION", json_text)
	_probe_decimal_candidate(label, source, "NUM_SCIENTIFIC", scientific_text)
	_probe_decimal_candidate(label, source, "STRING_NUM_DEFAULT", num_text)
	_probe_var_to_str(label, source)
	_probe_json_native(label, source)
	_probe_binary_variant(label, source)
	_probe_packed_double(label, source)
	print("FLOAT_DIAG_END=%s" % label)


func _probe_decimal_candidate(
	label: String,
	source: float,
	candidate_name: String,
	text: String
) -> void:
	var direct := text.to_float()
	var json_value: Variant = _json_number_from_text(text)
	print("FLOAT_DIAG_%s_CANDIDATE_%s_TEXT=%s" % [label, candidate_name, text])
	print(
		"FLOAT_DIAG_%s_CANDIDATE_%s_DIRECT_HEX=%s"
		% [label, candidate_name, _ieee754_hex(direct)]
	)
	print(
		"FLOAT_DIAG_%s_CANDIDATE_%s_DIRECT_EXACT=%s"
		% [label, candidate_name, _ieee754_hex(direct) == _ieee754_hex(source)]
	)
	print(
		"FLOAT_DIAG_%s_CANDIDATE_%s_JSON_HEX=%s"
		% [label, candidate_name, _variant_float_hex(json_value)]
	)
	print(
		"FLOAT_DIAG_%s_CANDIDATE_%s_JSON_EXACT=%s"
		% [
			label,
			candidate_name,
			typeof(json_value) == TYPE_FLOAT
			and _ieee754_hex(float(json_value)) == _ieee754_hex(source),
		]
	)


func _probe_var_to_str(label: String, source: float) -> void:
	var text := var_to_str(source)
	var restored: Variant = str_to_var(text)
	print("FLOAT_DIAG_%s_CODEC_VAR_TO_STR_TEXT=%s" % [label, text])
	print("FLOAT_DIAG_%s_CODEC_VAR_TO_STR_TYPE=%s" % [label, type_string(typeof(restored))])
	print("FLOAT_DIAG_%s_CODEC_VAR_TO_STR_HEX=%s" % [label, _variant_float_hex(restored)])
	print(
		"FLOAT_DIAG_%s_CODEC_VAR_TO_STR_EXACT=%s"
		% [
			label,
			typeof(restored) == TYPE_FLOAT
			and _ieee754_hex(float(restored)) == _ieee754_hex(source),
		]
	)
	var nested := {"f": source, "i": 7, "a": [source, 7]}
	var nested_text := var_to_str(nested)
	var nested_again := var_to_str(nested)
	var nested_restored: Variant = str_to_var(nested_text)
	_print_nested_codec_result(
		label,
		"VAR_TO_STR",
		source,
		nested_restored,
		nested_text == nested_again,
		true
	)


func _probe_json_native(label: String, source: float) -> void:
	var native_float: Variant = JSON.from_native(source)
	var native_float_text := JSON.stringify(native_float, "", true, true)
	var native_float_json: Variant = JSON.parse_string(native_float_text)
	var restored_float: Variant = JSON.to_native(native_float_json)
	print("FLOAT_DIAG_%s_CODEC_JSON_NATIVE_TEXT=%s" % [label, native_float_text])
	print("FLOAT_DIAG_%s_CODEC_JSON_NATIVE_TYPE=%s" % [label, type_string(typeof(restored_float))])
	print("FLOAT_DIAG_%s_CODEC_JSON_NATIVE_HEX=%s" % [label, _variant_float_hex(restored_float)])
	print(
		"FLOAT_DIAG_%s_CODEC_JSON_NATIVE_EXACT=%s"
		% [
			label,
			typeof(restored_float) == TYPE_FLOAT
			and _ieee754_hex(float(restored_float)) == _ieee754_hex(source),
		]
	)
	var nested := {"f": source, "i": 7, "a": [source, 7]}
	var native_nested: Variant = JSON.from_native(nested)
	var nested_text := JSON.stringify(native_nested, "", true, true)
	var nested_text_again := JSON.stringify(JSON.from_native(nested), "", true, true)
	var nested_json: Variant = JSON.parse_string(nested_text)
	var nested_restored: Variant = JSON.to_native(nested_json)
	_print_nested_codec_result(
		label,
		"JSON_NATIVE",
		source,
		nested_restored,
		nested_text == nested_text_again,
		true
	)


func _probe_binary_variant(label: String, source: float) -> void:
	var bytes := var_to_bytes(source)
	var restored: Variant = bytes_to_var(bytes)
	print("FLOAT_DIAG_%s_CODEC_VAR_TO_BYTES_SIZE=%d" % [label, bytes.size()])
	print("FLOAT_DIAG_%s_CODEC_VAR_TO_BYTES_TYPE=%s" % [label, type_string(typeof(restored))])
	print("FLOAT_DIAG_%s_CODEC_VAR_TO_BYTES_HEX=%s" % [label, _variant_float_hex(restored)])
	print(
		"FLOAT_DIAG_%s_CODEC_VAR_TO_BYTES_EXACT=%s"
		% [
			label,
			typeof(restored) == TYPE_FLOAT
			and _ieee754_hex(float(restored)) == _ieee754_hex(source),
		]
	)
	var nested := {"f": source, "i": 7, "a": [source, 7]}
	var nested_bytes := var_to_bytes(nested)
	var nested_again := var_to_bytes(nested)
	var nested_restored: Variant = bytes_to_var(nested_bytes)
	_print_nested_codec_result(
		label,
		"VAR_TO_BYTES",
		source,
		nested_restored,
		nested_bytes == nested_again,
		false
	)


func _probe_packed_double(label: String, source: float) -> void:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, source)
	var restored := bytes.decode_double(0)
	print("FLOAT_DIAG_%s_CODEC_PACKED_DOUBLE_BYTES=%s" % [label, _bytes_hex(bytes)])
	print("FLOAT_DIAG_%s_CODEC_PACKED_DOUBLE_HEX=%s" % [label, _ieee754_hex(restored)])
	print(
		"FLOAT_DIAG_%s_CODEC_PACKED_DOUBLE_EXACT=%s"
		% [label, _ieee754_hex(restored) == _ieee754_hex(source)]
	)


func _print_nested_codec_result(
	label: String,
	codec: String,
	source: float,
	restored: Variant,
	deterministic_same_input: bool,
	human_readable: bool
) -> void:
	var valid := restored is Dictionary
	var restored_dict := restored as Dictionary if valid else {}
	var f: Variant = restored_dict.get("f", null)
	var i: Variant = restored_dict.get("i", null)
	var a: Variant = restored_dict.get("a", null)
	var array_valid := a is Array and (a as Array).size() == 2
	var array_float: Variant = (a as Array)[0] if array_valid else null
	var array_int: Variant = (a as Array)[1] if array_valid else null
	print("FLOAT_DIAG_%s_CODEC_%s_NESTED_VALID=%s" % [label, codec, valid])
	print("FLOAT_DIAG_%s_CODEC_%s_NESTED_FLOAT_TYPE=%s" % [label, codec, type_string(typeof(f))])
	print("FLOAT_DIAG_%s_CODEC_%s_NESTED_INT_TYPE=%s" % [label, codec, type_string(typeof(i))])
	print("FLOAT_DIAG_%s_CODEC_%s_ARRAY_FLOAT_TYPE=%s" % [label, codec, type_string(typeof(array_float))])
	print("FLOAT_DIAG_%s_CODEC_%s_ARRAY_INT_TYPE=%s" % [label, codec, type_string(typeof(array_int))])
	print(
		"FLOAT_DIAG_%s_CODEC_%s_NESTED_FLOAT_EXACT=%s"
		% [
			label,
			codec,
			typeof(f) == TYPE_FLOAT and _ieee754_hex(float(f)) == _ieee754_hex(source),
		]
	)
	print(
		"FLOAT_DIAG_%s_CODEC_%s_ARRAY_FLOAT_EXACT=%s"
		% [
			label,
			codec,
			typeof(array_float) == TYPE_FLOAT
			and _ieee754_hex(float(array_float)) == _ieee754_hex(source),
		]
	)
	print(
		"FLOAT_DIAG_%s_CODEC_%s_INT_FLOAT_DISTINCTION=%s"
		% [label, codec, typeof(f) == TYPE_FLOAT and typeof(i) == TYPE_INT]
	)
	print(
		"FLOAT_DIAG_%s_CODEC_%s_DETERMINISTIC_SAME_INPUT=%s"
		% [label, codec, deterministic_same_input]
	)
	print("FLOAT_DIAG_%s_CODEC_%s_HUMAN_READABLE=%s" % [label, codec, human_readable])


func _json_number_from_text(text: String) -> Variant:
	var parsed: Variant = JSON.parse_string("{\"v\":%s}" % text)
	if not parsed is Dictionary:
		return null
	return (parsed as Dictionary).get("v", null)


func _jewelry_probe_value(snapshot: Dictionary) -> Variant:
	var economy := snapshot.get("economy", {}) as Dictionary
	var markets := economy.get("market_states", {}) as Dictionary
	var market := markets.get(JEWELRY_MARKET_ID, {}) as Dictionary
	var metrics := market.get("daily_metrics", {}) as Dictionary
	var commodity := metrics.get(JEWELRY_COMMODITY_ID, {}) as Dictionary
	return commodity.get("produced", null)


func _japan_produced_units_value(snapshot: Dictionary) -> Variant:
	var economy := snapshot.get("economy", {}) as Dictionary
	var markets := economy.get("market_states", {}) as Dictionary
	var market := markets.get(JAPAN_MARKET_ID, {}) as Dictionary
	var daily_totals := market.get("daily_totals", {}) as Dictionary
	return daily_totals.get("produced_units", null)


func _variant_float_hex(value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT:
		return "<not-float>"
	return _ieee754_hex(float(value))


func _ieee754_hex(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return "%016x" % bytes.decode_u64(0)


func _double_bytes_hex(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return _bytes_hex(bytes)


func _bytes_hex(bytes: PackedByteArray) -> String:
	var result := ""
	for byte: int in bytes:
		result += "%02x" % byte
	return result
