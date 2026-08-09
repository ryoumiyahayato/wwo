class_name VNextPlayerActionService
extends RefCounted


func wait(
	runtime: VNextWorldRuntime,
	player_or_minutes: Variant,
	requested_minutes: int = -1
) -> VNextActionResult:
	if runtime == null:
		return VNextActionResult.fail(
			"invalid_runtime", "vNext runtime is required for WAIT."
		)
	if not runtime.is_valid():
		return VNextActionResult.fail(
			"invalid_runtime", "WAIT requires an initialized vNext runtime."
		)

	var player: VNextPlayerState = null
	var minutes: int = requested_minutes
	if requested_minutes == -1 and typeof(player_or_minutes) == TYPE_INT:
		player = runtime.player()
		minutes = int(player_or_minutes)
	else:
		if typeof(player_or_minutes) == TYPE_OBJECT:
			player = player_or_minutes as VNextPlayerState

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
	return wait(runtime, minutes)
