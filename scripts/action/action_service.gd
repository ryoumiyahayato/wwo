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
	var study_skill_id: String = str(context.get("study_skill_id", ""))
	var work_skill_id: String = str(context.get("work_skill_id", ""))
	if definition.category == "study_skill":
		if study_skill_id.is_empty():
			study_skill_id = definition.primary_skill
			context["study_skill_id"] = study_skill_id
		if not character.skills.has(study_skill_id):
			result.add_error("学习行动必须选择人物已有的有效技能")
			return result
	elif not study_skill_id.is_empty():
		result.add_error("非学习行动不能携带学习技能目标")
		return result
	if definition.category == "perform_work":
		if work_skill_id.is_empty():
			work_skill_id = definition.primary_skill
			context["work_skill_id"] = work_skill_id
		if not character.skills.has(work_skill_id):
			result.add_error("本职工作能力映射无效")
			return result
	elif not work_skill_id.is_empty() or not is_zero_approx(
		float(context.get("occupation_match_bonus", 0.0))
	):
		result.add_error("非工作行动不能携带职业匹配上下文")
		return result
	if definition.category not in ["build_relationship", "investigate_character"] and not is_zero_approx(
		float(context.get("social_match_bonus", 0.0))
	):
		result.add_error("非人物接触行动不能携带社会匹配上下文")
		return result
	if definition.category != "join_organization" and not is_zero_approx(
		float(context.get("organization_match_bonus", 0.0))
	):
		result.add_error("非加入组织行动不能携带组织匹配上下文")
		return result
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		context["position_permissions"]
	)
	if not definition.position_permission_required.is_empty() and not permissions.has(definition.position_permission_required):
		result.add_error("缺少行动所需职位权限：%s" % definition.position_permission_required)
		return result
	var interruption: String = get_interruption_reason(definition, character)
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
	map_service: MapControlService = null,
	check_current_interruptions: bool = true
) -> void:
	if action == null or action.is_terminal() or current_hour <= action.last_update_hour:
		return
	if action.status == ActionInstanceData.STATUS_PAUSED:
		action.last_update_hour = current_hour
		action.estimated_completion_hour = -1
		return
	var settle_previous_interval: bool = bool(
		action.context.get("settle_previous_interval", false)
	)
	if check_current_interruptions and not settle_previous_interval:
		var immediate_interruption: String = get_interruption_reason(
			definition, character
		)
		if not immediate_interruption.is_empty():
			interrupt_action(action, current_hour, immediate_interruption)
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
	if settle_previous_interval:
		action.context["settle_previous_interval"] = false
		var boundary_invalid_reason: String = str(
			action.context.get("boundary_invalid_reason", "")
		)
		if not boundary_invalid_reason.is_empty():
			interrupt_action(
				action,
				current_hour,
				"authoritative_target_invalid:%s" % boundary_invalid_reason
			)
			return
		var boundary_interruption: String = get_interruption_reason(
			definition, character
		)
		if not boundary_interruption.is_empty():
			interrupt_action(action, current_hour, boundary_interruption)
			return
		var boundary_permissions: Array[String] = DataRecordUtils.to_string_array(
			action.context.get("position_permissions", [])
		)
		if not definition.position_permission_required.is_empty() and not boundary_permissions.has(
			definition.position_permission_required
		):
			interrupt_action(
				action, current_hour, "authoritative_permission_lost"
			)
			return
		action.context["boundary_invalid_reason"] = ""
	_recalculate_metrics(action, definition, character)
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
	var study_skill_id: String = str(merged.get("study_skill_id", ""))
	if definition.category == "study_skill":
		if study_skill_id.is_empty():
			study_skill_id = definition.primary_skill
			merged["study_skill_id"] = study_skill_id
		if not character.skills.has(study_skill_id):
			return false
	elif not study_skill_id.is_empty():
		return false
	var work_skill_id: String = str(merged.get("work_skill_id", ""))
	if definition.category == "perform_work":
		if work_skill_id.is_empty():
			work_skill_id = definition.primary_skill
			merged["work_skill_id"] = work_skill_id
		if not character.skills.has(work_skill_id):
			return false
	elif not work_skill_id.is_empty() or not is_zero_approx(
		float(merged.get("occupation_match_bonus", 0.0))
	):
		return false
	if definition.category not in ["build_relationship", "investigate_character"] and not is_zero_approx(
		float(merged.get("social_match_bonus", 0.0))
	):
		return false
	if definition.category != "join_organization" and not is_zero_approx(
		float(merged.get("organization_match_bonus", 0.0))
	):
		return false
	var settle_previous_interval: bool = (
		bool(merged.get("settle_previous_interval", false))
		and current_hour <= action.last_update_hour
	)
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		merged["position_permissions"]
	)
	if not settle_previous_interval and not definition.position_permission_required.is_empty() and not permissions.has(
		definition.position_permission_required
	):
		return false
	action.context = merged
	action.target_id = str(merged["target_id"])
	if settle_previous_interval:
		# Keep the old effective value and efficiency for the elapsed interval.
		_update_estimate(action, action.last_update_hour)
	else:
		_recalculate_metrics(action, definition, character)
	action_changed.emit(action)
	return true


func interrupt_action(
	action: ActionInstanceData,
	current_hour: int,
	reason: String
) -> bool:
	if action == null or action.is_terminal() or reason.is_empty():
		return false
	action.last_update_hour = maxi(current_hour, action.last_update_hour)
	action.status = ActionInstanceData.STATUS_INTERRUPTED
	action.interruption_reason = reason
	action.estimated_completion_hour = -1
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
	var interruption: String = get_interruption_reason(definition, character)
	if not interruption.is_empty():
		interrupt_action(action, current_hour, interruption)
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
	var primary_skill_id: String = _get_effective_primary_skill_id(definition, context)
	var primary_skill: float = float(character.skills.get(primary_skill_id, 0))
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
	var aptitude_id: String = str(
		rules.aptitude_by_skill.get(primary_skill_id, "learning")
	)
	var aptitude_adjustment: float = (
		float(character.hidden_aptitudes.get(aptitude_id, 50)) - 50.0
	) * definition.aptitude_modifier_weight
	var state_adjustment: float = _calculate_state_modifier(character) * definition.state_modifier_weight
	var mastery_bonus: float = 0.0
	if (
		primary_skill >= float(rules.mastery_guarantee.get("skill_threshold", 80.0))
		and float(context.get("preparation", 0.0)) >= float(
			rules.mastery_guarantee.get("preparation_threshold", 90.0)
		)
		and float(context.get("funding", 0.0)) >= float(
			rules.mastery_guarantee.get("funding_threshold", 80.0)
		)
	):
		mastery_bonus = float(
			rules.mastery_guarantee.get("effective_value_bonus", 0.0)
		)
	return (
		primary_skill * rules.primary_skill_weight
		+ secondary_average * rules.secondary_skill_weight
		+ position_bonus
		+ float(context.get("organization_support", 0.0)) * definition.organization_support_weight
		+ float(context.get("relationship_support", 0.0)) * definition.relationship_support_weight
		+ float(context.get("funding", 0.0)) * definition.funding_weight
		+ float(context.get("preparation", 0.0)) * definition.preparation_weight
		+ float(context.get("occupation_match_bonus", 0.0))
		+ float(context.get("social_match_bonus", 0.0))
		+ float(context.get("organization_match_bonus", 0.0))
		+ aptitude_adjustment
		+ state_adjustment
		+ mastery_bonus
		- definition.base_target_resistance
		- float(context.get("target_resistance", 0.0))
	)


func calculate_efficiency(
	definition: ActionDefinitionData,
	effective_value: float
) -> float:
	var progress_multiplier: float = clampf(
		rules.progress_base_multiplier
		+ effective_value * rules.progress_effective_scale,
		rules.minimum_progress_multiplier,
		rules.maximum_progress_multiplier
	)
	return maxf(definition.base_progress_per_hour * progress_multiplier, 0.000001)


func calculate_outcome_code(
	definition: ActionDefinitionData,
	effective_value: float
) -> String:
	if effective_value >= definition.guaranteed_success_threshold:
		return "guaranteed_success"
	if effective_value >= definition.success_threshold:
		return "success"
	return "failure"


func replace_completed_result(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	outcome_code: String
) -> bool:
	if action == null or definition == null or character == null:
		return false
	if action.status != ActionInstanceData.STATUS_COMPLETED or not action.result_applied:
		return false
	if outcome_code not in ["failure", "success", "guaranteed_success"]:
		return false
	var raw_before: Variant = action.applied_effects.get("_before", null)
	if not raw_before is Dictionary:
		return false
	_restore_result_before(definition, character, raw_before as Dictionary)
	action.result_applied = false
	action.applied_effects = {}
	action.outcome_code = outcome_code
	var result_data: Dictionary = (
		definition.success_result if outcome_code != "failure" else definition.failure_result
	)
	_apply_result_once(action, definition, character, result_data, null)
	action_changed.emit(action)
	return true


func get_interruption_reason(
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


func _recalculate_metrics(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData
) -> void:
	action.effective_value = calculate_effective_value(definition, character, action.context)
	action.outlook = rules.get_outlook(
		action.effective_value,
		definition.guaranteed_success_threshold,
		definition.success_threshold
	)
	action.current_efficiency = calculate_efficiency(definition, action.effective_value)
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
	action.outcome_code = calculate_outcome_code(definition, action.effective_value)
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
	_map_service: MapControlService
) -> void:
	if action.result_applied:
		return
	var before: Dictionary = {}
	action.result_description = str(result_data.get("description", "行动已结算"))
	var skill_delta: int = int(result_data.get("skill_delta", 0))
	if not result_data.has("skill_delta") and definition.category != "study_skill":
		skill_delta = int(
			rules.practice_growth.get(
				"failure_delta" if action.outcome_code == "failure" else "success_delta",
				0
			)
		)
	if skill_delta != 0:
		var skill_id: String = _get_growth_skill_id(definition, action.context)
		var old_skill: int = int(character.skills.get(skill_id, 0))
		before["skill_id"] = skill_id
		before["skill_value"] = old_skill
		character.skills[skill_id] = clampi(
			old_skill + skill_delta, 0, 100
		)
	if result_data.has("wealth_delta"):
		before["wealth"] = int(character.current_status.get("wealth", 0))
		character.current_status["wealth"] = maxi(
			int(before["wealth"]) + int(result_data["wealth_delta"]), 0
		)
	if result_data.has("reputation_delta"):
		before["reputation"] = int(character.current_status.get("reputation", 0))
		character.current_status["reputation"] = maxi(
			int(before["reputation"]) + int(result_data["reputation_delta"]), 0
		)
	if result_data.has("intelligence_delta"):
		before["intelligence_points"] = int(
			character.current_status.get("intelligence_points", 0)
		)
		character.current_status["intelligence_points"] = maxi(
			int(before["intelligence_points"]) + int(result_data["intelligence_delta"]), 0
		)
	for state_key: String in ["fatigue", "stress"]:
		var delta_key: String = state_key + "_delta"
		if result_data.has(delta_key):
			before[state_key] = int(character.current_status.get(state_key, 0))
			character.current_status[state_key] = clampi(
				int(before[state_key]) + int(result_data[delta_key]), 0, 100
			)
	action.applied_effects = result_data.duplicate(true)
	action.applied_effects["_before"] = before
	action.result_applied = true


func _restore_result_before(
	definition: ActionDefinitionData,
	character: CharacterData,
	before: Dictionary
) -> void:
	if before.has("skill_id") and before.has("skill_value"):
		character.skills[str(before["skill_id"])] = int(before["skill_value"])
	elif before.has("skill"):
		# Compatibility with results written before selectable study skills.
		character.skills[definition.primary_skill] = int(before["skill"])
	for state_key: String in [
		"wealth", "reputation", "intelligence_points", "fatigue", "stress"
	]:
		if before.has(state_key):
			character.current_status[state_key] = int(before[state_key])


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


func _get_effective_primary_skill_id(
	definition: ActionDefinitionData, context: Dictionary
) -> String:
	if definition.category == "study_skill":
		var selected: String = str(context.get("study_skill_id", ""))
		if not selected.is_empty():
			return selected
	if definition.category == "perform_work":
		var work_skill_id: String = str(context.get("work_skill_id", ""))
		if not work_skill_id.is_empty():
			return work_skill_id
	return definition.primary_skill


func _get_growth_skill_id(
	definition: ActionDefinitionData, context: Dictionary
) -> String:
	return _get_effective_primary_skill_id(definition, context)


static func _normalized_context(input_context: Dictionary) -> Dictionary:
	return {
		"target_id": str(input_context.get("target_id", "")),
		"study_skill_id": str(input_context.get("study_skill_id", "")),
		"work_skill_id": str(input_context.get("work_skill_id", "")),
		"occupation_match_bonus": float(
			input_context.get("occupation_match_bonus", 0.0)
		),
		"social_match_bonus": float(input_context.get("social_match_bonus", 0.0)),
		"organization_match_bonus": float(
			input_context.get("organization_match_bonus", 0.0)
		),
		"position_permissions": DataRecordUtils.to_string_array(
			input_context.get("position_permissions", [])
		),
		"organization_support": float(input_context.get("organization_support", 0.0)),
		"relationship_support": float(input_context.get("relationship_support", 0.0)),
		"funding": float(input_context.get("funding", 0.0)),
		"preparation": float(input_context.get("preparation", 0.0)),
		"target_resistance": float(input_context.get("target_resistance", 0.0)),
		"boundary_invalid_reason": str(input_context.get("boundary_invalid_reason", "")),
		"settle_previous_interval": bool(input_context.get("settle_previous_interval", false)),
		"funding_cost": int(input_context.get("funding_cost", 0)),
		"funding_committed": bool(input_context.get("funding_committed", false)),
		"wealth_before_funding": int(input_context.get("wealth_before_funding", 0)),
	}


static func _validate_context(context: Dictionary) -> String:
	for key: String in ["organization_support", "relationship_support", "funding", "preparation", "target_resistance"]:
		var value: float = float(context[key])
		if value < 0.0 or value > 100.0:
			return "%s 必须位于 0 至 100" % key
	var occupation_match_bonus: float = float(
		context.get("occupation_match_bonus", 0.0)
	)
	if occupation_match_bonus < 0.0 or occupation_match_bonus > 100.0:
		return "职业匹配加成必须位于 0 至 100"
	var social_match_bonus: float = float(context.get("social_match_bonus", 0.0))
	if social_match_bonus < 0.0 or social_match_bonus > 100.0:
		return "社会匹配加成必须位于 0 至 100"
	var organization_match_bonus: float = float(
		context.get("organization_match_bonus", 0.0)
	)
	if organization_match_bonus < 0.0 or organization_match_bonus > 100.0:
		return "组织匹配加成必须位于 0 至 100"
	if typeof(context.get("boundary_invalid_reason", "")) != TYPE_STRING:
		return "行动边界失效原因必须为字符串"
	if typeof(context.get("settle_previous_interval", false)) != TYPE_BOOL:
		return "行动旧区间结算标记必须为布尔值"
	var funding_cost: int = int(context["funding_cost"])
	var wealth_before: int = int(context["wealth_before_funding"])
	if funding_cost < 0 or wealth_before < 0:
		return "行动资金审计字段不得为负数"
	if bool(context["funding_committed"]) and wealth_before < funding_cost:
		return "行动开始前财富不足以覆盖已承诺费用"
	return ""
