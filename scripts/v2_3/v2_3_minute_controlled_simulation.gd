class_name V23MinuteControlledSimulation
extends V23ControlledSimulation
## Product composition root: minute clock plus player-authoritative movement.

const MINUTE_CLOCK_PATH: String = "res://data/v2_3/minute_clock.json"


func initialize(simulation_clock: SimulationClock = null) -> bool:
	var resolved_clock: SimulationClock = simulation_clock
	if resolved_clock == null:
		var clock_config := SimulationClockConfig.new()
		var load_error: Error = clock_config.load_from_file(
			MINUTE_CLOCK_PATH
		)
		if load_error != OK:
			initialization_error = clock_config.error_message
			return false
		resolved_clock = V23MinuteClock.new(clock_config)
	return super.initialize(resolved_clock)


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	if clock is V23MinuteClock:
		state["formal_minute_clock_state"] = (
			(clock as V23MinuteClock).get_persistent_state()
		)
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var base_result: V2LifeLoopResult = super.validate_v2_3_state(state)
	if not base_result.success:
		return base_result
	if state.has("formal_minute_clock_state") and not state.get(
		"formal_minute_clock_state", {}
	) is Dictionary:
		return V2LifeLoopResult.fail(
			"corrupt_save", "分钟时钟存档字段损坏"
		)
	return V2LifeLoopResult.ok("V2.3 分钟时钟状态有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = super.restore_v2_3_state(state)
	if not result.success:
		return result
	if (
		state.has("formal_minute_clock_state")
		and clock is V23MinuteClock
		and not (clock as V23MinuteClock).restore_persistent_state(
			state.get("formal_minute_clock_state", {}) as Dictionary
		)
	):
		return V2LifeLoopResult.fail(
			"minute_clock_restore_failed",
			"分钟时钟状态恢复失败"
		)
	state_changed.emit({"minute_clock_restored": true})
	return result


func determinism_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.determinism_snapshot()
	if clock is V23MinuteClock:
		snapshot["formal_minute_clock"] = (
			(clock as V23MinuteClock).get_persistent_state()
		)
	return snapshot
