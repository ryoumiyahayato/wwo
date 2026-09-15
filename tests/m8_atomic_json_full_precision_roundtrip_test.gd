extends SceneTree
## Focused M8 persistence regression for the real low-order float counterexample.
##
## Keep strict equality here. This test is expected to remain red until the
## persistence representation contract can preserve the authoritative float
## bit-exactly through the real AtomicJsonFileStore boundary.

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var exact_float: float = 0.000609184090909091
	var default_roundtrip: Variant = JSON.parse_string(JSON.stringify(exact_float))
	_expect_true(
		typeof(default_roundtrip) == TYPE_FLOAT
		and float(default_roundtrip) != exact_float,
		"M8 precision fixture distinguishes default JSON stringify low-order loss"
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
	_expect_equal(loaded.get("float_value"), exact_float, "M8 shared serializer bit-exactly round-trips counterexample float")
	_expect_equal(int(loaded.get("integer_value", -1)), 7, "M8 serializer does not change integer value")
	_expect_equal(str(loaded.get("text_value", "")), "precision", "M8 serializer does not change string")
	var nested := loaded.get("nested", {}) as Dictionary
	_expect_true(bool(nested.get("flag", false)), "M8 serializer does not change nested Dictionary")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish()


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
