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
	if not runtime.is_valid():
		return VNextActionResult.fail(
			"invalid_runtime", "WAIT requires an initialized vNext runtime."
		)
	if player == null:
		return VNextActionResult.fail(
			"invalid_player", "vNext player state is required for WAIT."
		)
	var authoritative_player_id: String = player.player_id()
	if authoritative_player_id.is_empty() or not player.is_valid():
		return VNextActionResult.fail(
			"invalid_player_id", "WAIT requires a valid person player_id."
		)
	if authoritative_player_id != runtime.player_id():
		return VNextActionResult.fail(
			"invalid_player_id", "WAIT player identity does not match the runtime owner."
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


func wait_current_player(
	runtime: VNextWorldRuntime, minutes: int
) -> VNextActionResult:
	var player: VNextPlayerState = null
	if runtime != null:
		player = runtime.player()
	return wait(runtime, player, minutes)
