class_name AiStateData
extends RefCounted

var character_id: String
var current_goal: String = ""
var goal_priority: float = 0.0
var current_action_id: String = ""
var candidate_actions: Array[Dictionary] = []
var next_daily_decision_hour: int = 0
var next_long_term_hour: int = 0
var daily_decision_count: int = 0
var long_term_evaluation_count: int = 0


static func from_dict(data: Dictionary) -> AiStateData:
	var model := AiStateData.new()
	model.character_id = str(data.get("character_id", ""))
	model.current_goal = str(data.get("current_goal", ""))
	model.goal_priority = float(data.get("goal_priority", 0.0))
	model.current_action_id = str(data.get("current_action_id", ""))
	model.candidate_actions = []
	for raw_candidate: Variant in data.get("candidate_actions", []):
		if raw_candidate is Dictionary:
			model.candidate_actions.append((raw_candidate as Dictionary).duplicate(true))
	model.next_daily_decision_hour = int(data.get("next_daily_decision_hour", 0))
	model.next_long_term_hour = int(data.get("next_long_term_hour", 0))
	model.daily_decision_count = int(data.get("daily_decision_count", 0))
	model.long_term_evaluation_count = int(data.get("long_term_evaluation_count", 0))
	return model


func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"current_goal": current_goal,
		"goal_priority": goal_priority,
		"current_action_id": current_action_id,
		"candidate_actions": candidate_actions.duplicate(true),
		"next_daily_decision_hour": next_daily_decision_hour,
		"next_long_term_hour": next_long_term_hour,
		"daily_decision_count": daily_decision_count,
		"long_term_evaluation_count": long_term_evaluation_count,
	}
