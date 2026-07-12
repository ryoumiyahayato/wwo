class_name AutosaveCoordinator
extends RefCounted
## Uses the authoritative weekly boundary; only one autosave slot is ever replaced.

var clock: SimulationClock
var map_service: MapControlService
var save_service := GameSaveService.new()
var autosave_path: String = GameSaveService.AUTOSAVE_PATH


func _init(output_path: String = GameSaveService.AUTOSAVE_PATH) -> void:
	autosave_path = output_path


func attach(simulation_clock: SimulationClock, control_service: MapControlService) -> bool:
	if simulation_clock == null or control_service == null:
		return false
	clock = simulation_clock
	map_service = control_service
	if not clock.week_advanced.is_connected(_on_week_advanced):
		clock.week_advanced.connect(_on_week_advanced)
	return true


func run_now() -> SaveOperationResult:
	return save_service.save_to_path(
		autosave_path, save_service.build_snapshot(clock, map_service)
	)


func _on_week_advanced(_week_index: int) -> void:
	if GameSessionService.has_player() and GameSessionService.society_service != null:
		var result: SaveOperationResult = run_now()
		if not result.success:
			LogService.warning("Autosave", result.message)
