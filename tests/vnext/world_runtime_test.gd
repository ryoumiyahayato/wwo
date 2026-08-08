extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_initial_state()
	_test_advance_minutes()
	_test_deterministic_sequence()
	_test_snapshot_contract()
	_test_snapshot_round_trip()
	_test_json_snapshot_round_trip()
	_test_restore_numeric_contract()
	_test_restore_rejections()
	_test_fractional_json_rejection()
	print("VNext world runtime: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_initial_state() -> void:
	var runtime := VNextWorldRuntime.new()
	_equal(runtime.total_minutes(), 0, "new runtime starts at zero minutes")


func _test_advance_minutes() -> void:
	var runtime := VNextWorldRuntime.new()
	_check(runtime.advance_minutes(15), "positive minute advance succeeds")
	_equal(runtime.total_minutes(), 15, "positive minute advance accumulates")
	_check(runtime.advance_minutes(45), "second positive minute advance succeeds")
	_equal(runtime.total_minutes(), 60, "multiple advances accumulate deterministically")

	var before_zero: int = runtime.total_minutes()
	_check(not runtime.advance_minutes(0), "zero minute advance is rejected")
	_equal(runtime.total_minutes(), before_zero, "zero minute rejection leaves state unchanged")

	var before_negative: int = runtime.total_minutes()
	_check(not runtime.advance_minutes(-1), "negative minute advance is rejected")
	_equal(runtime.total_minutes(), before_negative, "negative minute rejection leaves state unchanged")


func _test_deterministic_sequence() -> void:
	var first := VNextWorldRuntime.new()
	var second := VNextWorldRuntime.new()
	for minutes: int in [1, 59, 60, 125, 1441]:
		_check(first.advance_minutes(minutes), "first deterministic sequence accepts %d minutes" % minutes)
		_check(second.advance_minutes(minutes), "second deterministic sequence accepts %d minutes" % minutes)
	_equal(first.snapshot(), second.snapshot(), "identical advance sequences produce identical snapshots")


func _test_snapshot_contract() -> void:
	var runtime := VNextWorldRuntime.new()
	_check(runtime.advance_minutes(75), "snapshot fixture can advance")
	var value: Dictionary = runtime.snapshot()
	_equal(value.size(), 2, "snapshot contains exactly two fields")
	_check(value.has("schema_id"), "snapshot contains schema_id")
	_check(value.has("total_minutes"), "snapshot contains total_minutes")
	_equal(value.get("schema_id"), "vnext_world_runtime_v1", "snapshot schema_id is correct")
	_equal(value.get("total_minutes"), 75, "snapshot contains current total_minutes")


func _test_snapshot_round_trip() -> void:
	var source := VNextWorldRuntime.new()
	_check(source.advance_minutes(137), "round-trip source can advance")
	var saved: Dictionary = source.snapshot()

	var restored := VNextWorldRuntime.new()
	_check(restored.advance_minutes(999), "round-trip target can differ before restore")
	_check(restored.restore(saved), "valid snapshot restore succeeds")
	_equal(restored.total_minutes(), 137, "restore recovers total_minutes")
	_equal(restored.snapshot(), saved, "snapshot round trip preserves complete state")


func _test_json_snapshot_round_trip() -> void:
	var source := VNextWorldRuntime.new()
	_check(source.advance_minutes(137), "JSON round-trip source can advance")
	var source_snapshot: Dictionary = source.snapshot()
	var serialized_snapshot: String = JSON.stringify(source_snapshot)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized_snapshot)
	_equal(parse_error, OK, "JSON.stringify snapshot parses with JSON.parse")
	if parse_error != OK:
		return

	var parsed_value: Variant = parser.data
	_check(typeof(parsed_value) == TYPE_DICTIONARY, "JSON.parse returns a snapshot Dictionary")
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return
	var parsed_snapshot: Dictionary = parsed_value
	_equal(
		typeof(parsed_snapshot.get("total_minutes")),
		TYPE_FLOAT,
		"JSON-parsed total_minutes crosses the serialization boundary as float"
	)

	var restored := VNextWorldRuntime.new()
	_check(restored.restore(parsed_snapshot), "JSON-parsed snapshot restore succeeds")
	_equal(restored.total_minutes(), 137, "JSON round trip recovers total_minutes")
	_equal(restored.snapshot(), source_snapshot, "JSON round trip preserves complete business state")


func _test_restore_numeric_contract() -> void:
	var int_runtime := VNextWorldRuntime.new()
	_check(
		int_runtime.restore({"schema_id": "vnext_world_runtime_v1", "total_minutes": 90}),
		"integer total_minutes restore succeeds"
	)
	_equal(int_runtime.total_minutes(), 90, "integer total_minutes restores exact state")

	var float_runtime := VNextWorldRuntime.new()
	_check(
		float_runtime.restore({"schema_id": "vnext_world_runtime_v1", "total_minutes": 90.0}),
		"integer-valued float total_minutes restore succeeds"
	)
	_equal(float_runtime.total_minutes(), 90, "integer-valued float normalizes to runtime int")
	_equal(
		typeof(float_runtime.snapshot().get("total_minutes")),
		TYPE_INT,
		"accepted float does not change runtime snapshot ownership from int"
	)


func _test_restore_rejections() -> void:
	var runtime := VNextWorldRuntime.new()
	_check(runtime.advance_minutes(90), "restore rejection fixture can advance")

	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v0", "total_minutes": 12},
		"wrong schema"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1"},
		"missing total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": "90"},
		"string total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": null},
		"null total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": -1},
		"negative integer total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": -1.0},
		"negative float total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": INF},
		"infinite float total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": NAN},
		"NaN total_minutes"
	)


func _test_fractional_json_rejection() -> void:
	var runtime := VNextWorldRuntime.new()
	_check(runtime.advance_minutes(45), "fractional JSON rejection fixture can advance")
	var parser := JSON.new()
	var parse_error: Error = parser.parse(
		'{"schema_id":"vnext_world_runtime_v1","total_minutes":90.5}'
	)
	_equal(parse_error, OK, "fractional JSON snapshot parses successfully")
	if parse_error != OK:
		return

	var parsed_value: Variant = parser.data
	_check(typeof(parsed_value) == TYPE_DICTIONARY, "fractional JSON parse returns a Dictionary")
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return
	var parsed_snapshot: Dictionary = parsed_value
	_equal(
		parsed_snapshot.get("total_minutes"),
		90.5,
		"fractional JSON number reaches restore as 90.5"
	)
	_expect_restore_failure(runtime, parsed_snapshot, "fractional JSON total_minutes")


func _expect_restore_failure(
	runtime: VNextWorldRuntime, rejected: Dictionary, label: String
) -> void:
	var before: Dictionary = runtime.snapshot()
	_check(not runtime.restore(rejected), "%s is rejected" % label)
	_equal(runtime.snapshot(), before, "%s rejection is transactional" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
