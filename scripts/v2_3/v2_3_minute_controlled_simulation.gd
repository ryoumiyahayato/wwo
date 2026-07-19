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
