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
	_test_restore_rejections()
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
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": -1},
		"negative total_minutes"
	)
	_expect_restore_failure(
		runtime,
		{"schema_id": "vnext_world_runtime_v1", "total_minutes": 90.0},
		"float total_minutes"
	)


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
