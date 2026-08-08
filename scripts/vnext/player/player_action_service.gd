class_name VNextPlayerActionService
extends RefCounted


func wait(
	runtime: VNextWorldRuntime,
	player: VNextPlayerState,
	minutes: int
) -> VNextActionResult:
	if runtime == null:
		return VNextActionResult.fail(
			"invalid_runtime", "vNext runtime is required for WAIT."
		)
	if player == null:
		return VNextActionResult.fail(
			"invalid_player", "vNext player state is required for WAIT."
		)
	if not player.is_valid():
		return VNextActionResult.fail(
			"invalid_player_id", "WAIT requires a valid person player_id."
		)
	if minutes <= 0:
		return VNextActionResult.fail(
			"invalid_minutes", "WAIT minutes must be greater than zero."
		)
	if not runtime.advance_minutes(minutes):
		return VNextActionResult.fail(
			"runtime_rejected", "vNext runtime rejected WAIT advancement."
		)
	return VNextActionResult.ok(minutes)
