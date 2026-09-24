class_name VNextMilitaryAuthorityBridge
extends RefCounted
## Narrow Organization Authority -> Military integration seam for one exact command.
## Authority owns institutional permission; Military owns every domain fact and mutation.

const OPERATION_DEFEND: String = "military.defend"
const RESULT_AUTHORIZED_AND_EXECUTED: String = "AUTHORIZED_AND_EXECUTED"
const RESULT_AUTHORITY_DENIED: String = "AUTHORITY_DENIED"
const RESULT_DOMAIN_REJECTED: String = "DOMAIN_REJECTED"

var _authority: VNextOrganizationAuthorityFoundation = null
var _military_state: VNextMilitaryState = null
var _military_service: VNextMilitaryService = null
var _military_map: VNextMilitaryMapAdapter = null


static func create(
	authority: VNextOrganizationAuthorityFoundation,
	military_state: VNextMilitaryState,
	military_service: VNextMilitaryService,
	military_map: VNextMilitaryMapAdapter
) -> VNextMilitaryAuthorityBridge:
	if authority == null or military_state == null or military_service == null or military_map == null:
		return null
	var bridge := VNextMilitaryAuthorityBridge.new()
	bridge._authority = authority
	bridge._military_state = military_state
	bridge._military_service = military_service
	bridge._military_map = military_map
	return bridge


func defend(
	acting_context: Dictionary,
	formation_id: String,
	duration_hours: int,
	authority_time: int
) -> Dictionary:
	if (
		VNextStableId.kind_of(formation_id) != "formation"
		or duration_hours <= 0
		or authority_time < 0
	):
		return _domain_rejected({
			"success": false,
			"message": "Invalid DEFEND command precondition.",
		})

	var authorization := _authority.resolve_authority(
		acting_context,
		OPERATION_DEFEND,
		VNextOrganizationAuthorityFoundation.STAGE_DOMAIN_EXECUTION,
		formation_id,
		"",
		"",
		0.0,
		authority_time
	)
	var authority_status := str(authorization.get("status", ""))
	if authority_status != VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED:
		return {
			"success": false,
			"status": RESULT_AUTHORITY_DENIED,
			"authority_status": authority_status,
			"authorization": authorization.duplicate(true),
			"domain_result": {},
		}

	var domain_result := _military_service.defend(
		_military_state,
		_military_map,
		formation_id,
		_military_state.last_simulated_hour,
		duration_hours
	)
	if not bool(domain_result.get("success", false)):
		return _domain_rejected(domain_result, authorization)
	return {
		"success": true,
		"status": RESULT_AUTHORIZED_AND_EXECUTED,
		"authority_status": authority_status,
		"authorization": authorization.duplicate(true),
		"domain_result": domain_result.duplicate(true),
	}


func _domain_rejected(
	domain_result: Dictionary,
	authorization: Dictionary = {}
) -> Dictionary:
	return {
		"success": false,
		"status": RESULT_DOMAIN_REJECTED,
		"authority_status": str(authorization.get("status", "")),
		"authorization": authorization.duplicate(true),
		"domain_result": domain_result.duplicate(true),
	}
