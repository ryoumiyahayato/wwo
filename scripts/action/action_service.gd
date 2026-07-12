class_name ActionService
extends RefCounted
## Event-driven long action calculation. No frame callback and no character scan.

signal action_changed(action: ActionInstanceData)
signal action_completed(action: ActionInstanceData)

var rules: ActionRulesConfig
var id_service: StableIdService


func _init(action_rules: ActionRulesConfig, stable_id_service: StableIdService) -> void:
	rules = action_rules
	id_service = stable_id_service


func start_action(
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int,
	input_context: Dictionary = {}
) -> ActionStartResult:
	var result := ActionStartResult.new()
	if definition == null or character == null:
		result.add_error("行动定义和执行人物不能为空")
		return result
	if current_hour < 0:
		result.add_error("行动开始时间无效")
		return result
	var context: Dictionary = _normalized_context(input_context)
	var validation_error: String = _validate_context(context)
	if not validation_error.is_empty():
		result.add_error(validation_error)
		return result
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		context["position_permissions"]
	)
	if not definition.position_permission_required.is_empty() and not permissions.has(definition.position_permission_required):
		result.add_error("缺少行动所需职位权限：%s" % definition.position_permission_required)
		return result
	var interruption: String = _get_interruption_reason(definition, character)
	if not interruption.is_empty():
		result.add_error("人物当前状态阻止行动：%s" % interruption)
		return result

	var action := ActionInstanceData.new()
	action.id = id_service.next_id("action_instance")
	action.definition_id = definition.id
	action.actor_character_id = character.id
	action.target_id = str(context.get("target_id", ""))
	action.start_hour = current_hour
	action.last_update_hour = current_hour
	action.total_work = definition.total_work
	action.context = context
	_recalculate_metrics(action, definition, character)
	result.action = action
	return result


func update_to_hour(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int,
	map_service: MapControlService = null
) -> void:
	if action == null or action.is_terminal() or current_hour <= action.last_update_hour:
		return
	if action.status == ActionInstanceData.STATUS_PAUSED:
		action.last_update_hour = current_hour
		action.estimated_completion_hour = -1
		return
	var elapsed_hours: int = current_hour - action.last_update_hour
	var remaining_work: float = maxf(action.total_work - action.accumulated_work, 0.0)
	var required_hours: int = ceili(remaining_work / action.current_efficiency)
	action.accumulated_work = minf(
		action.total_work,
		action.accumulated_work + float(elapsed_hours) * action.current_efficiency
	)
	action.last_update_hour = current_hour
	if action.accumulated_work >= action.total_work:
		action.completion_hour = current_hour - maxi(elapsed_hours - required_hours, 0)
		_complete_action(action, definition, character, map_service)
		return
	var interruption: String = _get_interruption_reason(definition, character)
	if not interruption.is_empty():
		action.status = ActionInstanceData.STATUS_INTERRUPTED
		action.interruption_reason = interruption
		action.estimated_completion_hour = -1
		action_changed.emit(action)
		return
	_update_estimate(action, current_hour)
	action_changed.emit(action)


func update_context(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int,
	new_context: Dictionary,
	map_service: MapControlService = null
) -> bool:
	if action == null or action.is_terminal():
		return false
	update_to_hour(action, definition, character, current_hour, map_service)
	if action.is_terminal():
		return false
	var merged: Dictionary = action.context.duplicate(true)
	for raw_key: Variant in new_context:
		merged[str(raw_key)] = new_context[raw_key]
	merged = _normalized_context(merged)
	if not _validate_context(merged).is_empty():
		return false
	action.context = merged
	action.target_id = str(merged["target_id"])
	_recalculate_metrics(action, definition, character)
	action_changed.emit(action)
	return true


func pause_action(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int,
	map_service: MapControlService = null
) -> bool:
	if action == null or action.status != ActionInstanceData.STATUS_ACTIVE:
		return false
	update_to_hour(action, definition, character, current_hour, map_service)
	if action.is_terminal():
		return false
	action.status = ActionInstanceData.STATUS_PAUSED
	action.estimated_completion_hour = -1
	action_changed.emit(action)
	return true


func resume_action(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int
) -> bool:
	if action == null or action.status != ActionInstanceData.STATUS_PAUSED:
		return false
	action.status = ActionInstanceData.STATUS_ACTIVE
	action.last_update_hour = current_hour
	_recalculate_metrics(action, definition, character)
	action_changed.emit(action)
	return true


func cancel_action(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int,
	map_service: MapControlService = null
) -> bool:
	if action == null or action.is_terminal():
		return false
	update_to_hour(action, definition, character, current_hour, map_service)
	if action.is_terminal():
		return false
	action.status = ActionInstanceData.STATUS_CANCELLED
	action.estimated_completion_hour = -1
	action_changed.emit(action)
	return true


func calculate_effective_value(
	definition: ActionDefinitionData,
	character: CharacterData,
	context: Dictionary
) -> float:
	var primary_skill: float = float(character.skills.get(definition.primary_skill, 0))
	var secondary_average: float = 0.0
	for skill_id: String in definition.secondary_skills:
		secondary_average += float(character.skills.get(skill_id, 0))
	if not definition.secondary_skills.is_empty():
		secondary_average /= float(definition.secondary_skills.size())
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		context.get("position_permissions", [])
	)
	var position_bonus: float = 0.0
	if not definition.position_permission_required.is_empty() and permissions.has(definition.position_permission_required):
		position_bonus = rules.position_permission_bonus
	var aptitude_id: String = str(rules.aptitude_by_skill.get(definition.primary_skill, "learning"))
	var aptitude_adjustment: float = (
		float(character.hidden_aptitudes.get(aptitude_id, 50)) - 50.0
	) * definition.aptitude_modifier_weight
	var state_adjustment: float = _calculate_state_modifier(character) * definition.state_modifier_weight
	return (
		primary_skill * rules.primary_skill_weight
		+ secondary_average * rules.secondary_skill_weight
		+ position_bonus
		+ float(context.get("organization_support", 0.0)) * definition.organization_support_weight
		+ float(context.get("relationship_support", 0.0)) * definition.relationship_support_weight
		+ float(context.get("funding", 0.0)) * definition.funding_weight
		+ float(context.get("preparation", 0.0)) * definition.preparation_weight
		+ aptitude_adjustment
		+ state_adjustment
		- definition.base_target_resistance
		- float(context.get("target_resistance", 0.0))
	)


func _recalculate_metrics(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData
) -> void:
	action.effective_value = calculate_effective_value(definition, character, action.context)
	action.outlook = rules.get_outlook(
		action.effective_value, definition.guaranteed_success_threshold
	)
	var progress_multiplier: float = clampf(
		rules.progress_base_multiplier
		+ action.effective_value * rules.progress_effective_scale,
		rules.minimum_progress_multiplier,
		rules.maximum_progress_multiplier
	)
	action.current_efficiency = maxf(
		definition.base_progress_per_hour * progress_multiplier, 0.000001
	)
	_update_estimate(action, action.last_update_hour)


func _update_estimate(action: ActionInstanceData, current_hour: int) -> void:
	if action.status != ActionInstanceData.STATUS_ACTIVE:
		action.estimated_completion_hour = -1
		return
	var remaining: float = maxf(action.total_work - action.accumulated_work, 0.0)
	action.estimated_completion_hour = current_hour + ceili(
		remaining / action.current_efficiency
	)


func _complete_action(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	map_service: MapControlService
) -> void:
	action.status = ActionInstanceData.STATUS_COMPLETED
	action.estimated_completion_hour = action.completion_hour
	if action.effective_value >= definition.guaranteed_success_threshold:
		action.outcome_code = "guaranteed_success"
	elif action.effective_value >= definition.success_threshold:
		action.outcome_code = "success"
	else:
		action.outcome_code = "failure"
	var result_data: Dictionary = (
		definition.success_result
		if action.outcome_code != "failure"
		else definition.failure_result
	)
	_apply_result_once(action, definition, character, result_data, map_service)
	action_changed.emit(action)
	action_completed.emit(action)


func _apply_result_once(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	result_data: Dictionary,
	map_service: MapControlService
) -> void:
	if action.result_applied:
		return
	action.result_description = str(result_data.get("description", "行动已结算"))
	if result_data.has("skill_delta"):
		var old_skill: int = int(character.skills.get(definition.primary_skill, 0))
		character.skills[definition.primary_skill] = clampi(
			old_skill + int(result_data["skill_delta"]), 0, 100
		)
	if result_data.has("wealth_delta"):
		character.current_status["wealth"] = maxi(
			int(character.current_status.get("wealth", 0)) + int(result_data["wealth_delta"]), 0
		)
	if result_data.has("reputation_delta"):
		character.current_status["reputation"] = maxi(
			int(character.current_status.get("reputation", 0)) + int(result_data["reputation_delta"]), 0
		)
	if result_data.has("intelligence_delta"):
		character.current_status["intelligence_points"] = maxi(
			int(character.current_status.get("intelligence_points", 0)) + int(result_data["intelligence_delta"]), 0
		)
	for state_key: String in ["fatigue", "stress"]:
		var delta_key: String = state_key + "_delta"
		if result_data.has(delta_key):
			character.current_status[state_key] = clampi(
				int(character.current_status.get(state_key, 0)) + int(result_data[delta_key]), 0, 100
			)
	if result_data.has("control_pressure") and map_service != null and not action.target_id.is_empty():
		map_service.apply_control_pressure(
			action.target_id,
			character.country_id,
			float(result_data["control_pressure"])
		)
	action.applied_effects = result_data.duplicate(true)
	action.result_applied = true


func _calculate_state_modifier(character: CharacterData) -> float:
	var status: Dictionary = character.current_status
	var value: float = (
		(float(status.get("health", 80)) - float(rules.state_rules["health_baseline"]))
		* float(rules.state_rules["health_weight"])
		- float(status.get("fatigue", 0)) * float(rules.state_rules["fatigue_weight"])
		- float(status.get("stress", 0)) * float(rules.state_rules["stress_weight"])
	)
	return clampf(
		value,
		float(rules.state_rules["minimum"]),
		float(rules.state_rules["maximum"])
	)


func _get_interruption_reason(
	definition: ActionDefinitionData, character: CharacterData
) -> String:
	for condition: String in definition.interruption_conditions:
		match condition:
			"detained":
				if bool(character.current_status.get("detained", false)):
					return "detained"
			"incapacitated":
				if float(character.current_status.get("health", 100)) <= float(rules.state_rules["incapacitated_health"]):
					return "incapacitated"
			"unemployed":
				if str(character.current_status.get("employment_status", "")) == "unemployed":
					return "unemployed"
	return ""


static func _normalized_context(input_context: Dictionary) -> Dictionary:
	return {
		"target_id": str(input_context.get("target_id", "")),
		"position_permissions": DataRecordUtils.to_string_array(
			input_context.get("position_permissions", [])
		),
		"organization_support": float(input_context.get("organization_support", 0.0)),
		"relationship_support": float(input_context.get("relationship_support", 0.0)),
		"funding": float(input_context.get("funding", 0.0)),
		"preparation": float(input_context.get("preparation", 0.0)),
		"target_resistance": float(input_context.get("target_resistance", 0.0)),
	}


static func _validate_context(context: Dictionary) -> String:
	for key: String in ["organization_support", "relationship_support", "funding", "preparation", "target_resistance"]:
		var value: float = float(context[key])
		if value < 0.0 or value > 100.0:
			return "%s 必须位于 0 至 100" % key
	return ""
