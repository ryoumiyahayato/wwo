extends SceneTree
## Focused M8 persistence regression for the real 180d authoritative float.
##
## Keep strict bit equality here. The authoritative source value is constructed
## from its observed IEEE-754 bytes so the fixture itself does not pass through
## GDScript's decimal-literal parser before exercising AtomicJsonFileStore.

const EXPECTED_SOURCE_HEX := "3f43f634dfb491bb"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var exact_float := _authoritative_counterexample()
	_expect_equal(
		_ieee754_hex(exact_float),
		EXPECTED_SOURCE_HEX,
		"M8 fixture holds the real 180d authoritative IEEE-754 value"
	)

	var full_precision_text := JSON.stringify(exact_float, "", true, true)
	var direct_parse := full_precision_text.to_float()
	var json_parse: Variant = JSON.parse_string(full_precision_text)
	_expect_equal(
		full_precision_text,
		"0.0006091840909090909",
		"M8 fixture reproduces Godot full-precision decimal text"
	)
	_expect_true(
		_ieee754_hex(direct_parse) != EXPECTED_SOURCE_HEX,
		"M8 counterexample reproduces String.to_float bit loss"
	)
	_expect_true(
		typeof(json_parse) == TYPE_FLOAT
		and _ieee754_hex(float(json_parse)) == _ieee754_hex(direct_parse),
		"M8 counterexample reproduces JSON parser's same numeric conversion result"
	)

	var path: String = "user://tests/m8_atomic_json_precision.json"
	var snapshot: Dictionary = {
		"float_value": exact_float,
		"integer_value": 7,
		"text_value": "precision",
		"nested": {"flag": true},
	}
	var verifier := func(temporary_path: String) -> String:
		var temporary_file := FileAccess.open(temporary_path, FileAccess.READ)
		if temporary_file == null:
			return error_string(FileAccess.get_open_error())
		var temporary_parser := JSON.new()
		var temporary_parse_error := temporary_parser.parse(temporary_file.get_as_text())
		temporary_file.close()
		if temporary_parse_error != OK:
			return "precision fixture temporary JSON parse failed"
		if not temporary_parser.data is Dictionary:
			return "precision fixture temporary JSON root is not Dictionary"
		return ""
	var write_error := AtomicJsonFileStore.write_verified(
		path,
		snapshot,
		verifier,
		false
	)
	_expect_equal(write_error, "", "M8 AtomicJsonFileStore writes full-precision fixture")
	var file := FileAccess.open(path, FileAccess.READ)
	_expect_true(file != null, "M8 full-precision fixture reads back across real file boundary")
	if file == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_finish()
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	_expect_equal(parse_error, OK, "M8 full-precision fixture passes real JSON parser")
	if parse_error != OK or not parser.data is Dictionary:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_finish()
		return
	var loaded := parser.data as Dictionary
	_expect_true(typeof(loaded.get("float_value")) == TYPE_FLOAT, "M8 full-precision float remains float Variant")
	if typeof(loaded.get("float_value")) == TYPE_FLOAT:
		_expect_equal(
			_ieee754_hex(float(loaded.get("float_value"))),
			EXPECTED_SOURCE_HEX,
			"M8 shared serializer bit-exactly round-trips real counterexample float"
		)
	_expect_equal(int(loaded.get("integer_value", -1)), 7, "M8 serializer does not change integer value")
	_expect_equal(str(loaded.get("text_value", "")), "precision", "M8 serializer does not change string")
	var nested := loaded.get("nested", {}) as Dictionary
	_expect_true(bool(nested.get("flag", false)), "M8 serializer does not change nested Dictionary")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish()


func _authoritative_counterexample() -> float:
	# Little-endian bytes emitted by PackedByteArray.encode_double() for the real
	# 180d jewelry_watches.produced value. decode_double() preserves those bits.
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes[0] = 0xbb
	bytes[1] = 0x91
	bytes[2] = 0xb4
	bytes[3] = 0xdf
	bytes[4] = 0x34
	bytes[5] = 0xf6
	bytes[6] = 0x43
	bytes[7] = 0x3f
	return bytes.decode_double(0)


func _ieee754_hex(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return "%016x" % bytes.decode_u64(0)


func _expect_true(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % description)
		return
	_failures += 1
	printerr("[FAIL] %s" % description)


func _expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	_expect_true(actual == expected, "%s (actual=%s expected=%s)" % [description, actual, expected])


func _finish() -> void:
	if _failures > 0:
		printerr("M8 ATOMIC JSON PRECISION REGRESSION FAILED: %d/%d checks failed" % [_failures, _checks])
		quit(1)
		return
	print("M8 ATOMIC JSON PRECISION REGRESSION PASSED: %d checks" % _checks)
	quit(0)
