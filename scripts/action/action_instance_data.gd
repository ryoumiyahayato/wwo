class_name ActionInstanceData
extends RefCounted

const STATUS_ACTIVE: String = "active"
const STATUS_PAUSED: String = "paused"
const STATUS_COMPLETED: String = "completed"
const STATUS_CANCELLED: String = "cancelled"
const STATUS_INTERRUPTED: String = "interrupted"

var id: String
var definition_id: String
var actor_character_id: String
var target_id: String
var status: String = STATUS_ACTIVE
var start_hour: int
var last_update_hour: int
var completion_hour: int = -1
var accumulated_work: float = 0.0
var total_work: float
var current_efficiency: float
var estimated_completion_hour: int
var context: Dictionary = {}
var effective_value: float
var outlook: String
var outcome_code: String = ""
var result_description: String = ""
var applied_effects: Dictionary = {}
var result_applied: bool = false
var domain_effect_applied: bool = false
var interruption_reason: String = ""


static func from_dict(data: Dictionary) -> ActionInstanceData:
	var model := ActionInstanceData.new()
	model.id = str(data.get("id", ""))
	model.definition_id = str(data.get("definition_id", ""))
	model.actor_character_id = str(data.get("actor_character_id", ""))
	model.target_id = str(data.get("target_id", ""))
	model.status = str(data.get("status", STATUS_ACTIVE))
	model.start_hour = int(data.get("start_hour", 0))
	model.last_update_hour = int(data.get("last_update_hour", 0))
	model.completion_hour = int(data.get("completion_hour", -1))
	model.accumulated_work = float(data.get("accumulated_work", 0.0))
	model.total_work = float(data.get("total_work", 0.0))
	model.current_efficiency = float(data.get("current_efficiency", 0.0))
	model.estimated_completion_hour = int(data.get("estimated_completion_hour", -1))
	model.context = (data.get("context", {}) as Dictionary).duplicate(true)
	model.effective_value = float(data.get("effective_value", 0.0))
	model.outlook = str(data.get("outlook", ""))
	model.outcome_code = str(data.get("outcome_code", ""))
	model.result_description = str(data.get("result_description", ""))
	model.applied_effects = (data.get("applied_effects", {}) as Dictionary).duplicate(true)
	model.result_applied = bool(data.get("result_applied", false))
	model.domain_effect_applied = bool(data.get("domain_effect_applied", false))
	model.interruption_reason = str(data.get("interruption_reason", ""))
	return model


func get_progress_ratio() -> float:
	return 0.0 if total_work <= 0.0 else clampf(accumulated_work / total_work, 0.0, 1.0)


func is_terminal() -> bool:
	return status in [STATUS_COMPLETED, STATUS_CANCELLED, STATUS_INTERRUPTED]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"definition_id": definition_id,
		"actor_character_id": actor_character_id,
		"target_id": target_id,
		"status": status,
		"start_hour": start_hour,
		"last_update_hour": last_update_hour,
		"completion_hour": completion_hour,
		"accumulated_work": accumulated_work,
		"total_work": total_work,
		"current_efficiency": current_efficiency,
		"estimated_completion_hour": estimated_completion_hour,
		"context": context.duplicate(true),
		"effective_value": effective_value,
		"outlook": outlook,
		"outcome_code": outcome_code,
		"result_description": result_description,
		"applied_effects": applied_effects.duplicate(true),
		"result_applied": result_applied,
		"domain_effect_applied": domain_effect_applied,
		"interruption_reason": interruption_reason,
	}
