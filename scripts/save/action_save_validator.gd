class_name ActionSaveValidator
extends RefCounted

const NUMERIC_CONTEXT_FIELDS: Array[String] = [
	"organization_support", "relationship_support", "funding", "preparation", "target_resistance",
]
const VALID_OUTCOMES: Array[String] = ["failure", "success", "guaranteed_success"]
const DOMAIN_CATEGORIES: Array[String] = [
	"build_relationship",
	"join_organization",
	"seek_position",
	"investigate_character",
	"promote_policy",
	"support_control",
]


func validate(
	record: Dictionary,
	society: SocietySimulationService,
	map_service: MapControlService,
	current_hour: int,
	action_id_state: Dictionary,
	require_player_actor: bool = true
) -> String:
	var actor_id: String = str(record.get("actor_character_id", ""))
	var definition_id: String = str(record.get("definition_id", ""))
	var actor: CharacterData = society.roster.get_active(actor_id)
	if actor_id.is_empty() or actor == null:
		return "当前行动人物引用无效"
	if require_player_actor and actor_id != society.roster.player_character_id:
		return "当前行动不属于存档中的玩家人物"
	if not require_player_actor and actor_id == society.roster.player_character_id:
		return "NPC 行动不能引用玩家人物"
	if not map_service.data_set.actions.has(definition_id):
		return "当前行动定义引用无效"
	if current_hour < 0:
		return "当前行动对应的存档时间无效"
	if not record.get("context") is Dictionary or not record.get("applied_effects") is Dictionary:
		return "当前行动上下文或结果结构无效"

	var action := ActionInstanceData.from_dict(record)
	var definition: ActionDefinitionData = map_service.data_set.actions[definition_id] as ActionDefinitionData
	if not id_state_covers(action_id_state, action.id, "action_instance"):
		return "行动 ID 计数器落后于当前行动"
	if action.status not in [
		ActionInstanceData.STATUS_ACTIVE,
		ActionInstanceData.STATUS_PAUSED,
		ActionInstanceData.STATUS_COMPLETED,
		ActionInstanceData.STATUS_CANCELLED,
		ActionInstanceData.STATUS_INTERRUPTED,
	]:
		return "当前行动状态无效"
	if action.total_work <= 0.0 or not is_equal_approx(action.total_work, definition.total_work):
		return "当前行动总工作量与定义不一致"
	if action.accumulated_work < 0.0 or action.accumulated_work > action.total_work:
		return "当前行动进度无效"
	if action.start_hour < 0 or action.last_update_hour < action.start_hour or action.last_update_hour > current_hour:
		return "当前行动时间字段无效"
	var error: String = _validate_context(record["context"] as Dictionary, action)
	if not error.is_empty():
		return error
	error = _validate_state(action)
	if not error.is_empty():
		return error
	error = _validate_target(action, definition, actor, society, map_service)
	if not error.is_empty():
		return error
	if action.status == ActionInstanceData.STATUS_COMPLETED and definition.category in DOMAIN_CATEGORIES and not action.domain_effect_applied:
		return "已完成领域行动尚未执行权威写回"
	if action.status in [ActionInstanceData.STATUS_ACTIVE, ActionInstanceData.STATUS_PAUSED]:
		error = _validate_authoritative_context(
			action, definition, actor, society, map_service
		)
		if not error.is_empty():
			return error
	return _validate_formula(action, definition, actor)


func _validate_context(context: Dictionary, action: ActionInstanceData) -> String:
	if typeof(context.get("target_id", "")) != TYPE_STRING or str(context.get("target_id", "")) != action.target_id:
		return "当前行动目标与上下文不一致"
	if context.has("study_skill_id") and typeof(context["study_skill_id"]) != TYPE_STRING:
		return "当前行动学习技能字段类型无效"
	if context.has("work_skill_id") and typeof(context["work_skill_id"]) != TYPE_STRING:
		return "当前行动本职工作技能字段类型无效"
	if context.has("occupation_match_bonus"):
		if typeof(context["occupation_match_bonus"]) not in [TYPE_INT, TYPE_FLOAT]:
			return "当前行动职业匹配加成字段类型无效"
		var occupation_bonus: float = float(context["occupation_match_bonus"])
		if occupation_bonus < 0.0 or occupation_bonus > 100.0:
			return "当前行动职业匹配加成超出范围"
	if context.has("social_match_bonus"):
		if typeof(context["social_match_bonus"]) not in [TYPE_INT, TYPE_FLOAT]:
			return "当前行动社会匹配加成字段类型无效"
		var social_bonus: float = float(context["social_match_bonus"])
		if social_bonus < 0.0 or social_bonus > 100.0:
			return "当前行动社会匹配加成超出范围"
	if context.has("organization_match_bonus"):
		if typeof(context["organization_match_bonus"]) not in [TYPE_INT, TYPE_FLOAT]:
			return "当前行动组织匹配加成字段类型无效"
		var organization_bonus: float = float(
			context["organization_match_bonus"]
		)
		if organization_bonus < 0.0 or organization_bonus > 100.0:
			return "当前行动组织匹配加成超出范围"
	if typeof(context.get("boundary_invalid_reason", "")) != TYPE_STRING:
		return "当前行动边界失效原因字段类型无效"
	if typeof(context.get("settle_previous_interval", false)) != TYPE_BOOL:
		return "当前行动旧区间结算字段类型无效"
	if bool(context.get("settle_previous_interval", false)) or not str(
		context.get("boundary_invalid_reason", "")
	).is_empty():
		return "存档不能包含日结算内部的临时行动边界状态"
	var raw_permissions: Variant = context.get("position_permissions", null)
	if not raw_permissions is Array:
		return "当前行动职位权限字段无效"
	var seen: Dictionary = {}
	for raw_permission: Variant in raw_permissions as Array:
		if typeof(raw_permission) != TYPE_STRING:
			return "当前行动职位权限必须为字符串"
		var permission: String = str(raw_permission)
		if permission.is_empty() or seen.has(permission):
			return "当前行动职位权限存在空值或重复值"
		seen[permission] = true
	for field: String in NUMERIC_CONTEXT_FIELDS:
		var raw_value: Variant = context.get(field, null)
		if typeof(raw_value) not in [TYPE_INT, TYPE_FLOAT]:
			return "当前行动上下文字段 %s 类型无效" % field
		var value: float = float(raw_value)
		if value < 0.0 or value > 100.0:
			return "当前行动上下文字段 %s 超出范围" % field
	var has_cost: bool = context.has("funding_cost")
	var has_committed: bool = context.has("funding_committed")
	var has_wealth: bool = context.has("wealth_before_funding")
	if not has_cost and not has_committed and not has_wealth:
		return ""
	if not has_cost or not has_committed or not has_wealth:
		return "当前行动资金审计字段不完整"
	var raw_cost: Variant = context["funding_cost"]
	var raw_wealth: Variant = context["wealth_before_funding"]
	if typeof(raw_cost) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw_wealth) not in [TYPE_INT, TYPE_FLOAT]:
		return "当前行动资金审计字段类型无效"
	var cost: float = float(raw_cost)
	var wealth_before: float = float(raw_wealth)
	if cost < 0.0 or cost != floor(cost) or wealth_before < 0.0 or wealth_before != floor(wealth_before):
		return "当前行动资金审计字段数值无效"
	if typeof(context["funding_committed"]) != TYPE_BOOL:
		return "当前行动资金承诺字段类型无效"
	var committed: bool = bool(context["funding_committed"])
	if committed and wealth_before < cost:
		return "当前行动开始前财富不足以覆盖费用"
	if not committed and (cost != 0.0 or wealth_before != 0.0):
		return "未承诺资金的通用行动不能携带支付审计数值"
	return ""


func _validate_state(action: ActionInstanceData) -> String:
	if action.status in [ActionInstanceData.STATUS_ACTIVE, ActionInstanceData.STATUS_PAUSED]:
		if action.accumulated_work >= action.total_work or action.completion_hour != -1:
			return "未完成行动具有完成状态数据"
		if not action.outcome_code.is_empty() or action.result_applied or action.domain_effect_applied:
			return "未完成行动具有已结算结果"
		if not action.result_description.is_empty() or not action.applied_effects.is_empty() or not action.interruption_reason.is_empty():
			return "未完成行动包含结果或中断载荷"
		if action.status == ActionInstanceData.STATUS_ACTIVE and action.estimated_completion_hour <= action.last_update_hour:
			return "进行中行动预计完成时间无效"
		if action.status == ActionInstanceData.STATUS_PAUSED and action.estimated_completion_hour != -1:
			return "暂停行动预计完成时间无效"
		return ""
	if action.status == ActionInstanceData.STATUS_COMPLETED:
		if not is_equal_approx(action.accumulated_work, action.total_work):
			return "已完成行动工作量未完成"
		if action.completion_hour < action.start_hour or action.completion_hour > action.last_update_hour:
			return "已完成行动完成时间无效"
		if action.estimated_completion_hour != action.completion_hour:
			return "已完成行动预计完成时间不一致"
		if action.outcome_code not in VALID_OUTCOMES or not action.result_applied:
			return "已完成行动结果状态无效"
		if action.result_description.is_empty() or action.applied_effects.is_empty() or not action.interruption_reason.is_empty():
			return "已完成行动结算载荷无效"
		return ""
	if action.completion_hour != -1 or action.estimated_completion_hour != -1:
		return "取消或中断行动具有完成时间"
	if not action.outcome_code.is_empty() or action.result_applied or action.domain_effect_applied:
		return "取消或中断行动具有已结算结果"
	if not action.result_description.is_empty() or not action.applied_effects.is_empty():
		return "取消或中断行动包含结果载荷"
	if action.status == ActionInstanceData.STATUS_INTERRUPTED and action.interruption_reason.is_empty():
		return "中断行动缺少中断原因"
	if action.status == ActionInstanceData.STATUS_CANCELLED and not action.interruption_reason.is_empty():
		return "取消行动不应包含中断原因"
	return ""


func _validate_target(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	actor: CharacterData,
	society: SocietySimulationService,
	map_service: MapControlService
) -> String:
	var study_skill_id: String = str(
		action.context.get(
			"study_skill_id",
			definition.primary_skill if definition.category == "study_skill" else ""
		)
	)
	if definition.category == "study_skill":
		if study_skill_id.is_empty() or not actor.skills.has(study_skill_id):
			return "当前学习行动的技能目标无效"
	elif not study_skill_id.is_empty():
		return "非学习行动包含异常技能目标"
	var work_skill_id: String = str(action.context.get("work_skill_id", ""))
	if definition.category == "perform_work":
		if not work_skill_id.is_empty() and not actor.skills.has(work_skill_id):
			return "当前本职工作能力映射无效"
	elif not work_skill_id.is_empty() or not is_zero_approx(
		float(action.context.get("occupation_match_bonus", 0.0))
	):
		return "非工作行动包含异常职业匹配上下文"
	if definition.category not in ["build_relationship", "investigate_character"] and not is_zero_approx(
		float(action.context.get("social_match_bonus", 0.0))
	):
		return "非人物接触行动包含异常社会匹配上下文"
	if definition.category not in ["join_organization", "seek_position"] and not is_zero_approx(
		float(action.context.get("organization_match_bonus", 0.0))
	):
		return "非组织目标行动包含异常组织匹配上下文"
	if definition.category in ["build_relationship", "investigate_character"]:
		if not society.roster.is_living(action.target_id) or action.target_id == action.actor_character_id:
			return "当前行动人物目标无效"
	elif definition.category in ["join_organization", "seek_position"]:
		if society.organizations.get_organization(action.target_id) == null:
			return "当前行动组织目标无效"
	elif definition.category in ["promote_policy", "support_control"]:
		if map_service.get_unit(action.target_id) == null:
			return "当前行动地图目标无效"
	elif not action.target_id.is_empty():
		return "无需目标的行动包含异常目标"
	return ""


func _validate_authoritative_context(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	actor: CharacterData,
	society: SocietySimulationService,
	map_service: MapControlService
) -> String:
	var rules := ActionRulesConfig.new()
	if rules.load_from_file() != OK:
		return "无法验证当前行动权威条件：%s" % rules.error_message
	var context_service := PlayerActionContextService.new(rules, society, map_service)
	var target_error: String = context_service.get_target_validation_error(
		definition, actor, action.target_id
	)
	if not target_error.is_empty():
		return "当前行动目标已不满足权威条件：%s" % target_error
	var expected: Dictionary = context_service.build_authoritative_context_for_action(
		definition, actor, action
	)
	if expected.is_empty():
		return "当前行动无法重建权威上下文"
	var stored_permissions: Array[String] = DataRecordUtils.to_string_array(
		action.context.get("position_permissions", [])
	)
	var expected_permissions: Array[String] = DataRecordUtils.to_string_array(
		expected.get("position_permissions", [])
	)
	stored_permissions.sort()
	expected_permissions.sort()
	if stored_permissions != expected_permissions:
		return "当前行动职位权限与权威组织状态不一致"
	var stored_study_skill: String = str(
		action.context.get(
			"study_skill_id",
			definition.primary_skill if definition.category == "study_skill" else ""
		)
	)
	if stored_study_skill != str(expected.get("study_skill_id", "")):
		return "当前行动学习技能与权威人物状态不一致"
	if action.context.has("work_skill_id") and str(
		action.context.get("work_skill_id", "")
	) != str(expected.get("work_skill_id", "")):
		return "当前行动本职工作技能与权威职业不一致"
	if action.context.has("occupation_match_bonus") and not is_equal_approx(
		float(action.context.get("occupation_match_bonus", -1.0)),
		float(expected.get("occupation_match_bonus", -2.0))
	):
		return "当前行动职业匹配加成与权威职业不一致"
	if action.context.has("social_match_bonus") and not is_equal_approx(
		float(action.context.get("social_match_bonus", -1.0)),
		float(expected.get("social_match_bonus", -2.0))
	):
		return "当前行动社会匹配加成与权威人物状态不一致"
	if action.context.has("organization_match_bonus") and not is_equal_approx(
		float(action.context.get("organization_match_bonus", -1.0)),
		float(expected.get("organization_match_bonus", -2.0))
	):
		return "当前行动组织匹配加成与权威人物状态不一致"
	for field: String in NUMERIC_CONTEXT_FIELDS:
		if not is_equal_approx(
			float(action.context.get(field, -1.0)),
			float(expected.get(field, -2.0))
		):
			return "当前行动字段 %s 与权威状态不一致" % field
	if action.context.has("funding_committed") and bool(
		action.context.get("funding_committed", false)
	) and int(action.context.get("funding_cost", -1)) != int(expected.get("funding_cost", -2)):
		return "当前行动费用与配置不一致"
	if not definition.position_permission_required.is_empty() and not expected_permissions.has(
		definition.position_permission_required
	):
		return "当前行动所需职位权限已失效"
	return ""


func _validate_formula(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	actor: CharacterData
) -> String:
	var rules := ActionRulesConfig.new()
	if rules.load_from_file() != OK:
		return "无法验证当前行动公式：%s" % rules.error_message
	var evaluator := ActionService.new(rules, StableIdService.new())
	if action.outlook != rules.get_outlook(
		action.effective_value,
		definition.guaranteed_success_threshold,
		definition.success_threshold
	):
		return "当前行动定性把握与有效值不一致"
	if not is_equal_approx(action.current_efficiency, evaluator.calculate_efficiency(definition, action.effective_value)):
		return "当前行动效率与有效值不一致"
	if action.status in [ActionInstanceData.STATUS_ACTIVE, ActionInstanceData.STATUS_PAUSED]:
		if not is_equal_approx(action.effective_value, evaluator.calculate_effective_value(definition, actor, action.context)):
			return "当前行动有效值与人物及上下文不一致"
		if action.status == ActionInstanceData.STATUS_ACTIVE:
			var estimate: int = action.last_update_hour + ceili(
				maxf(action.total_work - action.accumulated_work, 0.0) / action.current_efficiency
			)
			if action.estimated_completion_hour != estimate:
				return "当前行动预计完成时间与进度不一致"
	if action.status == ActionInstanceData.STATUS_COMPLETED:
		var expected: String = evaluator.calculate_outcome_code(definition, action.effective_value)
		var domain_failure: bool = (
			action.domain_effect_applied
			and action.outcome_code == "failure"
			and action.applied_effects.get("domain_applied", true) == false
			and definition.category in DOMAIN_CATEGORIES
		)
		if action.outcome_code != expected and not domain_failure:
			return "已完成行动结果与有效值阈值不一致"
	return ""


static func id_state_covers(state: Dictionary, id: String, expected_namespace: String) -> bool:
	if not StableIdService.is_valid_id(id) or StableIdService.get_namespace(id) != expected_namespace:
		return false
	var slug: String = id.get_slice(":", 1)
	return slug.is_valid_int() and int(slug) >= 1 and int(state.get(expected_namespace, 0)) >= int(slug)
