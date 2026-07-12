class_name SimulationRunner
extends Node
## Frame adapter for SimulationClock. It submits elapsed real seconds but never owns
## calendar rules or performs world simulation in _process().

signal clock_ready(clock: SimulationClock)

@export_file("*.json") var config_path: String = SimulationClockConfig.DEFAULT_PATH

var clock: SimulationClock
var initialization_error: String = ""


func _ready() -> void:
	var config := SimulationClockConfig.new()
	var load_error: Error = config.load_from_file(config_path)
	if load_error != OK:
		initialization_error = config.error_message
		LogService.error("SimulationRunner", initialization_error)
		set_process(false)
		return
	clock = SimulationClock.new(config)
	clock_ready.emit(clock)
	LogService.info("SimulationRunner", "权威游戏时钟已就绪")


func _process(delta: float) -> void:
	if clock != null:
		clock.advance_real_seconds(delta)

