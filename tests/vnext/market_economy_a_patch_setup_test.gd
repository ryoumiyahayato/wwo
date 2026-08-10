extends SceneTree

const SOURCE_PATH: String = "res://scripts/vnext/economy/market_economy.gd"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: String = FileAccess.get_file_as_string(SOURCE_PATH)
	_check(not source.is_empty(), "market economy source is readable without diagnostic mutation")
	print("VNext market economy baseline setup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)
