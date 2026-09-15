extends SceneTree
## Test-only exact numeric JSON persistence contract prototype.
##
## This script stops at the real 180-day authoritative snapshot. It does not
## modify product persistence, Economy, fingerprinting, world schema, or Formal
## baselines. The closed decimal-parser investigation is intentionally not
## repeated here.

const CODEC_SCRIPT := preload("res://tests/formal/exact_numeric_json_codec_prototype.gd")
const SAVE_RESTORE_DAY: int = 180
const MINUTES_PER_DAY: int = 24 * 60
const FORMAT_ID: String = "wwo.formal.exact-json.v1"
const COUNTEREXAMPLE_1_BITS: String = "3f43f634dfb491bb"
const COUNTEREXAMPLE_2_BITS: String = "40c3169901b276ea"
const JEWELRY_MARKET_ID := "market:legacy_aggregate:sultanate_of_zanzibar"
const JEWELRY_COMMODITY_ID := "jewelry_watches"
const JAPAN_MARKET_ID := "market:legacy_aggregate:empire_of_japan"

var _codec: RefCounted = CODEC_SCRIPT.new()
var _failures: int = 0
var _checks: int = 0
var _malformed_checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_contract_fixtures()
	_check_malformed_envelopes()
	var metrics := _check_real_180d_snapshot()

	print("EXACT_CODEC_MALFORMED_CASES=%d" % _malformed_checks)
	print("EXACT_CODEC_CHECKS=%d" % _checks)
	print("EXACT_CODEC_FAILURES=%d" % _failures)
	if not metrics.is_empty():
		print("EXACT_CODEC_RESULT=%s" % JSON.stringify(metrics, "", true, true))
	if _failures > 0:
		printerr("EXACT_JSON_CODEC_PROTOTYPE_FAILED=%d" % _failures)
		quit(1)
		return
	print("EXACT_JSON_CODEC_PROTOTYPE_COMPLETE=1")
	# Preserve the existing workflow completion marker while changing the
	# diagnostic's scope from parser investigation to exact-codec validation.
	print("FLOAT_PERSISTENCE_DIAGNOSTIC_COMPLETE=2")
	quit(0)


func _check_contract_fixtures() -> void:
	var counterexample_1 := _codec.f64_from_bits(COUNTEREXAMPLE_1_BITS)
	var counterexample_2 := _codec.f64_from_bits(COUNTEREXAMPLE_2_BITS)
	_check(bool(counterexample_1.get("ok", false)), "counterexample #1 fixture decodes from canonical bits")
	_check(bool(counterexample_2.get("ok", false)), "counterexample #2 fixture decodes from canonical bits")
	if bool(counterexample_1.get("ok", false)) and bool(counterexample_2.get("ok", false)):
		var fixture := {
			"f1": counterexample_1.get("value"),
			"f2": counterexample_2.get("value"),
			"int_value": 120,
			"float_value": 120.0,
			"bool_value": true,
			"literal_null": null,
			"nested": {
				"0": -0.0,
				"array": [0.0, 7, null, {"deep": counterexample_1.get("value")}],
			},
		}
		var fixture_encoded := _codec.encode_variant_tree(fixture)
		_check(bool(fixture_encoded.get("ok", false)), "nested fixture exact-codec encodes")
		if bool(fixture_encoded.get("ok", false)):
			var fixture_envelope := fixture_encoded.get("value") as Dictionary
			var path_text := JSON.stringify(fixture_envelope.get("numbers", []))
			_check(path_text.contains("\"key\":\"0\""), "typed path preserves Dictionary key \"0\"")
			_check(path_text.contains("\"index\":\"0\""), "typed path preserves Array index 0 separately")
		var roundtrip := _codec_roundtrip(fixture)
		_check(bool(roundtrip.get("ok", false)), "nested Array/Dictionary fixture exact-codec round-trips")
		if bool(roundtrip.get("ok", false)):
			var restored: Variant = roundtrip.get("value")
			_check(_codec.strict_equal(fixture, restored), "nested fixture preserves value plus Variant type")
			var restored_dict := restored as Dictionary
			_check(typeof(restored_dict["int_value"]) == TYPE_INT, "int remains TYPE_INT")
			_check(typeof(restored_dict["float_value"]) == TYPE_FLOAT, "120.0 remains TYPE_FLOAT")
			_check(typeof(restored_dict["bool_value"]) == TYPE_BOOL, "bool is not treated as integer")
			_check(typeof(restored_dict["literal_null"]) == TYPE_NIL, "literal null remains null")
			var nested := restored_dict["nested"] as Dictionary
			_check(_codec.f64_bits(float(nested["0"])) == "8000000000000000", "Dictionary key \"0\" signed zero is exact")
			var array := nested["array"] as Array
			_check(_codec.f64_bits(float(array[0])) == "0000000000000000", "Array index 0 positive zero is exact")

	var signed_zero := _codec_roundtrip({"positive": 0.0, "negative": -0.0})
	_check(bool(signed_zero.get("ok", false)), "+0.0/-0.0 fixture round-trips")
	if bool(signed_zero.get("ok", false)):
		var zeros := signed_zero.get("value") as Dictionary
		_check(_codec.f64_bits(float(zeros["positive"])) == "0000000000000000", "+0.0 sign bit is preserved")
		_check(_codec.f64_bits(float(zeros["negative"])) == "8000000000000000", "-0.0 sign bit is preserved")

	var max_finite := _codec.f64_from_bits("7fefffffffffffff")
	var min_subnormal := _codec.f64_from_bits("0000000000000001")
	var min_i64 := _codec.i64_from_bits("8000000000000000")
	var max_i64 := _codec.i64_from_bits("7fffffffffffffff")
	_check(bool(max_finite.get("ok", false)) and bool(min_subnormal.get("ok", false)), "finite f64 boundary fixtures decode")
	_check(bool(min_i64.get("ok", false)) and bool(max_i64.get("ok", false)), "signed i64 boundary fixtures decode")
	if (
		bool(max_finite.get("ok", false))
		and bool(min_subnormal.get("ok", false))
		and bool(min_i64.get("ok", false))
		and bool(max_i64.get("ok", false))
	):
		var boundaries := {
			"max_finite": max_finite.get("value"),
			"min_subnormal": min_subnormal.get("value"),
			"min_i64": min_i64.get("value"),
			"max_i64": max_i64.get("value"),
		}
		var boundaries_roundtrip := _codec_roundtrip(boundaries)
		_check(bool(boundaries_roundtrip.get("ok", false)), "finite f64 and i64 boundary fixture round-trips")
		if bool(boundaries_roundtrip.get("ok", false)):
			_check(_codec.strict_equal(boundaries, boundaries_roundtrip.get("value")), "finite f64 and i64 boundaries remain bit/type exact")

	var nan_value := _codec.f64_from_bits("7ff8000000000000")
	var positive_inf := _codec.f64_from_bits("7ff0000000000000")
	var negative_inf := _codec.f64_from_bits("fff0000000000000")
	_check(
		bool(nan_value.get("ok", false))
		and not bool(_codec.encode_variant_tree({"v": nan_value.get("value")}).get("ok", false)),
		"NaN save fails closed"
	)
	_check(
		bool(positive_inf.get("ok", false))
		and not bool(_codec.encode_variant_tree({"v": positive_inf.get("value")}).get("ok", false)),
		"+INF save fails closed"
	)
	_check(
		bool(negative_inf.get("ok", false))
		and not bool(_codec.encode_variant_tree({"v": negative_inf.get("value")}).get("ok", false)),
		"-INF save fails closed"
	)

	var non_string_key := {7: "not-json-object-safe"}
	_check(
		not bool(_codec.encode_variant_tree(non_string_key).get("ok", false)),
		"non-string Dictionary key is rejected rather than coerced"
	)


func _check_malformed_envelopes() -> void:
	var source_float := _codec.f64_from_bits(COUNTEREXAMPLE_1_BITS)
	if not bool(source_float.get("ok", false)):
		_check(false, "malformed-test source float is available")
		return
	var fixture := {
		"arr": [7, source_float.get("value")],
		"float": source_float.get("value"),
		"int": 120,
		"null": null,
	}
	var encoded := _codec.encode_variant_tree(fixture)
	_check(bool(encoded.get("ok", false)), "malformed-test base envelope encodes")
	if not bool(encoded.get("ok", false)):
		return
	var base := encoded.get("value") as Dictionary
	var f64_index := _first_numeric_index(base, "f64")
	var i64_index := _first_numeric_index(base, "i64")
	_check(f64_index >= 0 and i64_index >= 0, "malformed-test base has f64 and i64 entries")
	if f64_index < 0 or i64_index < 0:
		return

	var invalid_hex := base.duplicate(true)
	var invalid_hex_entry := (invalid_hex["numbers"] as Array)[f64_index] as Dictionary
	invalid_hex_entry["bits"] = "zzzzzzzzzzzzzzzz"
	_expect_decode_failure(invalid_hex, "invalid f64 hex")

	var wrong_length := base.duplicate(true)
	var wrong_length_entry := (wrong_length["numbers"] as Array)[f64_index] as Dictionary
	wrong_length_entry["bits"] = "3f43"
	_expect_decode_failure(wrong_length, "wrong f64 bit length")

	var duplicate_path := base.duplicate(true)
	var duplicate_entry := ((duplicate_path["numbers"] as Array)[f64_index] as Dictionary).duplicate(true)
	(duplicate_path["numbers"] as Array).append(duplicate_entry)
	_expect_decode_failure(duplicate_path, "duplicate numeric path")

	var missing_path := base.duplicate(true)
	var missing_path_entry := (missing_path["numbers"] as Array)[f64_index] as Dictionary
	missing_path_entry["path"] = [{"key": "does_not_exist"}]
	_expect_decode_failure(missing_path, "numeric path not found")

	var non_placeholder := base.duplicate(true)
	(non_placeholder["payload"] as Dictionary)["float"] = "tampered"
	_expect_decode_failure(non_placeholder, "numeric manifest target is not null placeholder")

	var missing_manifest := base.duplicate(true)
	(missing_manifest["numbers"] as Array).remove_at(f64_index)
	_expect_decode_failure(missing_manifest, "missing numeric manifest entry leaves unclassified null")

	var unknown_type := base.duplicate(true)
	var unknown_type_entry := (unknown_type["numbers"] as Array)[f64_index] as Dictionary
	unknown_type_entry["type"] = "f32"
	_expect_decode_failure(unknown_type, "unknown numeric type")

	var invalid_array_index := base.duplicate(true)
	var invalid_index_entry := (invalid_array_index["numbers"] as Array)[f64_index] as Dictionary
	invalid_index_entry["path"] = [
		{"key": "arr"}, {"index": "99"},
	]
	_expect_decode_failure(invalid_array_index, "array index out of bounds")

	var malformed_segment := base.duplicate(true)
	var malformed_segment_entry := (malformed_segment["numbers"] as Array)[f64_index] as Dictionary
	malformed_segment_entry["path"] = [
		{"key": "arr", "index": "0"},
	]
	_expect_decode_failure(malformed_segment, "path segment with both key and index")

	var missing_discriminator := base.duplicate(true)
	var missing_discriminator_entry := (missing_discriminator["numbers"] as Array)[f64_index] as Dictionary
	missing_discriminator_entry["path"] = [{}]
	_expect_decode_failure(missing_discriminator, "path segment with neither key nor index")

	var numeric_escape := base.duplicate(true)
	(numeric_escape["payload"] as Dictionary)["float"] = 1.5
	_expect_decode_failure(numeric_escape, "numeric leaf escaped into payload")

	var through_non_container := base.duplicate(true)
	var through_non_container_entry := (through_non_container["numbers"] as Array)[f64_index] as Dictionary
	through_non_container_entry["path"] = [{"key": "float"}, {"key": "child"}]
	_expect_decode_failure(through_non_container, "path traverses non-container placeholder")

	var unknown_format := base.duplicate(true)
	unknown_format["format"] = "wwo.formal.exact-json.v999"
	_expect_decode_failure(unknown_format, "unknown root format discriminator")

	var extra_envelope_field := base.duplicate(true)
	extra_envelope_field["codec_version"] = 1
	_expect_decode_failure(extra_envelope_field, "unexpected envelope field")

	var extra_entry_field := base.duplicate(true)
	var entry_with_extra := extra_entry_field["numbers"] as Array
	(entry_with_extra[f64_index] as Dictionary)["decimal"] = "0.0006091840909090909"
	_expect_decode_failure(extra_entry_field, "unexpected numeric entry field")

	var uppercase_hex := base.duplicate(true)
	var uppercase_hex_entry := (uppercase_hex["numbers"] as Array)[f64_index] as Dictionary
	uppercase_hex_entry["bits"] = COUNTEREXAMPLE_1_BITS.to_upper()
	_expect_decode_failure(uppercase_hex, "non-canonical uppercase bits")

	var malformed_index_text := base.duplicate(true)
	var malformed_index_entry := (malformed_index_text["numbers"] as Array)[f64_index] as Dictionary
	malformed_index_entry["path"] = [
		{"key": "arr"}, {"index": "01"},
	]
	_expect_decode_failure(malformed_index_text, "non-canonical array index text")

	var nonfinite_load := base.duplicate(true)
	var nonfinite_load_entry := (nonfinite_load["numbers"] as Array)[f64_index] as Dictionary
	nonfinite_load_entry["bits"] = "7ff0000000000000"
	_expect_decode_failure(nonfinite_load, "non-finite f64 manifest load")


func _check_real_180d_snapshot() -> Dictionary:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "real 180d Formal world initializes")
	if not simulation.initialized:
		return {}
	simulation.advance_minutes(SAVE_RESTORE_DAY * MINUTES_PER_DAY)
	var original_state := simulation.get_persistent_state()
	var original_fingerprint := simulation.authoritative_fingerprint()
	_check(not original_fingerprint.is_empty(), "real 180d authoritative fingerprint exists")

	var counts := _codec.count_numeric_leaves(original_state)
	_check(int(counts.get("non_string_keys", -1)) == 0, "real 180d snapshot contains only string Dictionary keys")

	var legacy_text := JSON.stringify(original_state, "\t", false, true)
	var legacy_bytes := legacy_text.to_utf8_buffer().size()

	var encode_start := Time.get_ticks_usec()
	var encoded := _codec.encode_variant_tree(original_state)
	_check(bool(encoded.get("ok", false)), "real 180d snapshot exact-codec encodes")
	if not bool(encoded.get("ok", false)):
		printerr("EXACT_CODEC_180D_ENCODE_ERROR=%s" % encoded.get("error", ""))
		return {}
	var envelope := encoded.get("value") as Dictionary
	var exact_text := JSON.stringify(envelope, "\t", false, true)
	var encode_usec := Time.get_ticks_usec() - encode_start
	var exact_bytes := exact_text.to_utf8_buffer().size()

	var second_encoded := _codec.encode_variant_tree(original_state)
	_check(bool(second_encoded.get("ok", false)), "real 180d snapshot second encode succeeds")
	var deterministic := false
	var manifest_deterministic := false
	if bool(second_encoded.get("ok", false)):
		var second_envelope := second_encoded.get("value") as Dictionary
		manifest_deterministic = JSON.stringify(envelope["numbers"]) == JSON.stringify(second_envelope["numbers"])
		deterministic = exact_text == JSON.stringify(second_envelope, "\t", false, true)
	_check(manifest_deterministic, "numeric manifest ordering/content is deterministic")
	_check(deterministic, "complete exact codec JSON output is deterministic for identical snapshot")

	var payload_numeric_counts := _codec.count_numeric_leaves(envelope["payload"])
	_check(int(payload_numeric_counts.get("total", -1)) == 0, "no numeric leaves escape into exact-codec payload")

	var decode_start := Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(exact_text)
	_check(parsed is Dictionary, "exact codec envelope survives Godot JSON parse")
	var decoded := _codec.decode_variant_tree(parsed)
	var decode_usec := Time.get_ticks_usec() - decode_start
	_check(bool(decoded.get("ok", false)), "parsed exact codec envelope decodes")
	if not bool(decoded.get("ok", false)):
		printerr("EXACT_CODEC_180D_DECODE_ERROR=%s" % decoded.get("error", ""))
		return {}
	var reconstructed := decoded.get("value")
	_check(reconstructed is Dictionary, "decoded exact codec value is normal Formal snapshot Dictionary")
	_check(_codec.strict_equal(original_state, reconstructed), "real 180d snapshot is recursively value/type/bit exact")

	var original_probe_1: Variant = _jewelry_probe_value(original_state)
	var decoded_probe_1: Variant = _jewelry_probe_value(reconstructed as Dictionary)
	var original_probe_2: Variant = _japan_produced_units_value(original_state)
	var decoded_probe_2: Variant = _japan_produced_units_value(reconstructed as Dictionary)
	var probe_1_source_bits := _float_bits_or_invalid(original_probe_1)
	var probe_1_decoded_bits := _float_bits_or_invalid(decoded_probe_1)
	var probe_2_source_bits := _float_bits_or_invalid(original_probe_2)
	var probe_2_decoded_bits := _float_bits_or_invalid(decoded_probe_2)
	_check(probe_1_source_bits == COUNTEREXAMPLE_1_BITS, "real counterexample #1 source bits match known observation")
	_check(probe_1_decoded_bits == COUNTEREXAMPLE_1_BITS, "real counterexample #1 exact codec round-trip is bit-exact")
	_check(probe_2_source_bits == COUNTEREXAMPLE_2_BITS, "real counterexample #2 source bits match known observation")
	_check(probe_2_decoded_bits == COUNTEREXAMPLE_2_BITS, "real counterexample #2 exact codec round-trip is bit-exact")

	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "exact-codec temporary-save verification target initializes")
	var restore_ok := false
	if restored.initialized and reconstructed is Dictionary:
		restore_ok = restored.restore_persistent_state(reconstructed as Dictionary)
	_check(restore_ok, "existing Formal restore accepts domain-normal decoded snapshot")
	var decoded_fingerprint := restored.authoritative_fingerprint() if restore_ok else ""
	_check(decoded_fingerprint == original_fingerprint, "180d original and exact-codec-decoded authoritative fingerprints are identical")

	var stats := encoded.get("stats", {}) as Dictionary
	var increase := exact_bytes - legacy_bytes
	var overhead_percent := (
		float(increase) * 100.0 / float(legacy_bytes)
		if legacy_bytes > 0
		else 0.0
	)
	print("EXACT_CODEC_FORMAT=%s" % str(envelope.get("format", "")))
	print("EXACT_CODEC_180D_ORIGINAL_FINGERPRINT=%s" % original_fingerprint)
	print("EXACT_CODEC_180D_DECODED_FINGERPRINT=%s" % decoded_fingerprint)
	print("EXACT_CODEC_COUNTEREXAMPLE_1_SOURCE_BITS=%s" % probe_1_source_bits)
	print("EXACT_CODEC_COUNTEREXAMPLE_1_DECODED_BITS=%s" % probe_1_decoded_bits)
	print("EXACT_CODEC_COUNTEREXAMPLE_2_SOURCE_BITS=%s" % probe_2_source_bits)
	print("EXACT_CODEC_COUNTEREXAMPLE_2_DECODED_BITS=%s" % probe_2_decoded_bits)
	print("EXACT_CODEC_NUMERIC_LEAVES=%d" % int(stats.get("numeric_leaves", -1)))
	print("EXACT_CODEC_F64_LEAVES=%d" % int(stats.get("f64_leaves", -1)))
	print("EXACT_CODEC_I64_LEAVES=%d" % int(stats.get("i64_leaves", -1)))
	print("EXACT_CODEC_LITERAL_NULL_LEAVES=%d" % int(stats.get("literal_null_leaves", -1)))
	print("EXACT_CODEC_LEGACY_JSON_BYTES=%d" % legacy_bytes)
	print("EXACT_CODEC_JSON_BYTES=%d" % exact_bytes)
	print("EXACT_CODEC_SIZE_INCREASE_BYTES=%d" % increase)
	print("EXACT_CODEC_SIZE_OVERHEAD_PERCENT=%.6f" % overhead_percent)
	print("EXACT_CODEC_ENCODE_USEC=%d" % encode_usec)
	print("EXACT_CODEC_DECODE_USEC=%d" % decode_usec)
	print("EXACT_CODEC_MANIFEST_DETERMINISTIC=%s" % manifest_deterministic)
	print("EXACT_CODEC_OUTPUT_DETERMINISTIC=%s" % deterministic)
	print("EXACT_CODEC_STRICT_EQUAL=%s" % _codec.strict_equal(original_state, reconstructed))

	return {
		"format": FORMAT_ID,
		"original_fingerprint": original_fingerprint,
		"decoded_fingerprint": decoded_fingerprint,
		"strict_equal": _codec.strict_equal(original_state, reconstructed),
		"numeric_leaves": int(stats.get("numeric_leaves", -1)),
		"f64_leaves": int(stats.get("f64_leaves", -1)),
		"i64_leaves": int(stats.get("i64_leaves", -1)),
		"literal_null_leaves": int(stats.get("literal_null_leaves", -1)),
		"legacy_json_bytes": legacy_bytes,
		"exact_json_bytes": exact_bytes,
		"size_increase_bytes": increase,
		"size_overhead_percent": overhead_percent,
		"encode_usec": encode_usec,
		"decode_usec": decode_usec,
		"manifest_deterministic": manifest_deterministic,
		"output_deterministic": deterministic,
	}


func _codec_roundtrip(value: Variant) -> Dictionary:
	var encoded := _codec.encode_variant_tree(value)
	if not bool(encoded.get("ok", false)):
		return encoded
	var text := JSON.stringify(encoded.get("value"), "", false, true)
	var parsed: Variant = JSON.parse_string(text)
	return _codec.decode_variant_tree(parsed)


func _expect_decode_failure(envelope: Dictionary, label: String) -> void:
	_malformed_checks += 1
	var result := _codec.decode_variant_tree(envelope)
	_check(not bool(result.get("ok", false)), "malformed envelope rejected: %s" % label)


func _first_numeric_index(envelope: Dictionary, numeric_type: String) -> int:
	var numbers := envelope.get("numbers", []) as Array
	for index: int in range(numbers.size()):
		if numbers[index] is Dictionary and str((numbers[index] as Dictionary).get("type", "")) == numeric_type:
			return index
	return -1


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


func _float_bits_or_invalid(value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT:
		return "<not-float>"
	return _codec.f64_bits(float(value))


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
		return
	_failures += 1
	printerr("[FAIL] %s" % label)
