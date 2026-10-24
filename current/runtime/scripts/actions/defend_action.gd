class_name DefendAction
extends RefCounted

const OPERATION_DEFEND: String = "military.defend"
const RESULT_EXECUTED: String = "EXECUTED"
const RESULT_DENIED: String = "DENIED"
const RESULT_ERROR: String = "ERROR"
const RESULT_REJECTED: String = "DOMAIN_REJECTED"


static func execute(
	context: Dictionary,
	formation_id: String,
	duration_hours: int,
	current_hour: int,
	player: VNextPlayerState,
	persons: VNextNamedPersonOverlay,
	authorization: AuthorizationCheck,
	military: VNextMilitaryState,
	service: VNextMilitaryService,
	map: VNextMilitaryMapAdapter
) -> Dictionary:
	if player == null or persons == null or authorization == null or military == null or service == null or map == null:
		return _error("Missing defend dependencies; formation: " + formation_id)
	var person_id: String = str(context.get("person_id", ""))
	if not persons.has_person(person_id):
		return _error("Unknown person: " + person_id)
	if military.get_formation(formation_id) == null:
		return _error("Unknown formation: " + formation_id)
	if current_hour < 0 or duration_hours <= 0:
		return _error("Malformed defend timing: formation=%s hour=%d duration=%d" % [formation_id, current_hour, duration_hours])
	if person_id != player.player_id() or not persons.is_alive(person_id):
		return {"success": false, "status": RESULT_DENIED, "reason": "NOT_CURRENT_ACTIVE_PERSON"}
	var result := authorization.resolve_authority(
		context, OPERATION_DEFEND, AuthorizationCheck.STAGE_DOMAIN_EXECUTION,
		formation_id, "", "", 0.0, current_hour
	)
	if str(result["status"]) != AuthorizationCheck.ALLOWED:
		return {"success": false, "status": str(result["status"]), "reason": str(result["reason"]), "authorization": result}
	var executed := service.defend(military, map, formation_id, current_hour, duration_hours)
	return {
		"success": bool(executed.get("success", false)),
		"status": RESULT_EXECUTED if bool(executed.get("success", false)) else RESULT_REJECTED,
		"authorization": result, "domain_result": executed,
	}


static func _error(detail: String) -> Dictionary:
	var message: String = "DEFEND ACTION DATA ERROR: " + detail
	push_error(message)
	return {"success": false, "status": RESULT_ERROR, "reason": "DEFEND_ACTION_DATA_ERROR", "message": message}
