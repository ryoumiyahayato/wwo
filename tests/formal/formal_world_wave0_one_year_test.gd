extends SceneTree
## Completion-scope duration checks without invoking the prohibited ten-year run.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_check(simulation.initialize(), "Formal simulation initializes")
	if simulation.initialized:
		var at_thirty_days := simulation.advance_minutes(30 * 24 * 60)
		_check(
			int(at_thirty_days.get("total_hour", -1)) == 30 * 24,
			"30-day Formal simulation completes"
		)
		var at_one_year := simulation.advance_minutes(335 * 24 * 60)
		_check(
			int(at_one_year.get("total_hour", -1)) == 365 * 24,
			"one-year Formal simulation completes"
		)
		_check(
			int(at_one_year.get("world_political_unit_count", 0)) == 151,
			"one-year run retains all dated political units"
		)
		_check(
			int(at_one_year.get("fulfillment_bp", -1)) >= 0,
			"one-year aggregate fulfillment remains valid"
		)
	print(
		"Wave 0 30-day and one-year simulation: %d checks, %d failures"
		% [_checks, _failures]
	)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("Wave 0 duration: " + message)
