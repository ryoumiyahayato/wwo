class_name SimpleAiService
extends RefCounted
## Bounded rule AI for active NPCs only; background IDs are never registered.

var roster: CharacterRosterService
var rules: SocietyRulesConfig
var states: Dictionary = {}


func _init(character_roster: CharacterRosterService, society_rules: SocietyRulesConfig) -> void:
	roster = character_roster
	rules = society_rules


func register_active_npc(character_id: String) -> bool:
	if character_id == roster.player_character_id or roster.get_active(character_id) == null:
		return false
	if states.has(character_id):
		return true
	var state := AiStateData.new()
	state.character_id = character_id
	states[character_id] = state
	return true


func unregister(character_id: String) -> void:
	states.erase(character_id)


func run_daily_decisions(current_hour: int) -> int:
	var evaluated: int = 0
	for character_id: String in get_ai_character_ids():
		var character: CharacterData = roster.get_active(character_id)
		var state: AiStateData = states[character_id] as AiStateData
		if character == null:
			states.erase(character_id)
			continue
		if current_hour < state.next_daily_decision_hour:
			continue
		state.candidate_actions = _score_candidates(character, state)
		if state.current_action_record.is_empty():
			state.current_action_id = (
				""
				if state.candidate_actions.is_empty()
				else str(state.candidate_actions[0]["action_id"])
			)
		else:
			state.current_action_id = str(
				state.current_action_record.get(
					"definition_id", state.current_action_id
				)
			)
		state.daily_decision_count += 1
		state.next_daily_decision_hour = current_hour + int(
			rules.ai_rules.get("daily_interval_hours", 24)
		)
		evaluated += 1
	return evaluated


func run_long_term_evaluations(
	current_hour: int, force_period_boundary: bool = false
) -> int:
	var evaluated: int = 0
	var goals: Dictionary = rules.ai_rules.get("goal_by_occupation", {}) as Dictionary
	for character_id: String in get_ai_character_ids():
		var character: CharacterData = roster.get_active(character_id)
		var state: AiStateData = states[character_id] as AiStateData
		if character == null:
			states.erase(character_id)
			continue
		if not force_period_boundary and current_hour < state.next_long_term_hour:
			continue
		state.current_goal = str(
			goals.get(character.occupation_id, "career_growth")
		)
		state.goal_priority = clampf(
			40.0
			+ float(character.current_status.get("reputation", 0)) * 0.25
			+ float(character.temperament_weights.get("ambitious", 50)) * 0.2,
			0.0,
			100.0
		)
		state.long_term_evaluation_count += 1
		state.next_long_term_hour = current_hour + int(
			rules.ai_rules.get("long_term_interval_hours", 720)
		)
		evaluated += 1
	return evaluated


func get_state(character_id: String) -> AiStateData:
	return states.get(character_id) as AiStateData


func get_ai_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in states:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func get_persistent_state() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for character_id: String in get_ai_character_ids():
		output.append((states[character_id] as AiStateData).to_dict())
	return output


func restore_persistent_state(records: Array) -> bool:
	var restored: Dictionary = {}
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			return false
		var state := AiStateData.from_dict(raw_record as Dictionary)
		if state.character_id.is_empty() or state.character_id == roster.player_character_id or roster.get_active(state.character_id) == null or restored.has(state.character_id):
			return false
		if not state.current_action_record.is_empty():
			var action := ActionInstanceData.from_dict(state.current_action_record)
			if action.actor_character_id != state.character_id or action.is_terminal():
				return false
		restored[state.character_id] = state
	states = restored
	return true


func _score_candidates(
	character: CharacterData, state: AiStateData
) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var candidates: Array = rules.ai_rules.get("candidates", []) as Array
	var skill_weight: float = float(rules.ai_rules.get("skill_weight", 0.2))
	var fatigue: float = float(character.current_status.get("fatigue", 0))
	var stress: float = float(character.current_status.get("stress", 0))
	var wealth: float = float(character.current_status.get("wealth", 0))
	for raw_candidate: Variant in candidates:
		var candidate: Dictionary = raw_candidate as Dictionary
		var action_id: String = str(candidate["action_id"])
		var score: float = float(candidate["base_weight"])
		var skill_id: String = str(candidate.get("skill", ""))
		if not skill_id.is_empty():
			score += float(character.skills.get(skill_id, 0)) * skill_weight
		if str(candidate.get("goal", "")) == state.current_goal:
			score += float(rules.ai_rules.get("goal_bonus", 0.0))
		if action_id == "rest":
			score += fatigue * 0.5 + stress * 0.3
		else:
			score -= fatigue * float(
				rules.ai_rules.get("fatigue_penalty_weight", 0.0)
			)
			score -= stress * float(
				rules.ai_rules.get("stress_penalty_weight", 0.0)
			)
		if action_id == "action:perform_work" and wealth < 20.0:
			score += 16.0
		if action_id == "action:join_organization" and not character.organization_ids.is_empty():
			score -= 24.0
		if action_id == "action:seek_position" and character.organization_ids.is_empty():
			score -= 40.0
		output.append({"action_id": action_id, "weight": snappedf(score, 0.001)})
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_weight: float = float(a["weight"])
		var b_weight: float = float(b["weight"])
		return str(a["action_id"]) < str(b["action_id"]) if is_equal_approx(a_weight, b_weight) else a_weight > b_weight
	)
	return output
