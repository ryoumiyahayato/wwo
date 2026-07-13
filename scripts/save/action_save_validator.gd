class_name ActionSaveValidator
extends RefCounted

const NUMERIC_CONTEXT_FIELDS: Array[String] = [
	"organization_support", "relationship_support", "funding", "preparation", "target_resistance",
]
const VALID_OUTCOMES: Array[String] = ["failure", "success", "guaranteed_success"]


func validate(
	record: Dictionary,
	society: SocietySimulationService,
	map_service: MapControlService,
	current_hour: int,
	action_id_state: Dictionary
) -> String:
	var actor_id: String = str(record.get("actor_character_id", ""))
	var definition_id: String = str(record.get("definition_id", ""))
	var actor: CharacterData = society.roster.get_active(actor_id)
	if actor_id.is_empty() or actor == null:
		return "当前行动人物引用无效"
	if actor_id != society.roster.player_character_id:
		return "当前行动不属于存档中的玩家人物"
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
	error = _validate_target(action, definition, society, map_service)
	if not error.is_empty():
		return error
	return _validate_formula(action, definition, actor)


func _validate_context(context: Dictionary, action: ActionInstanceData) -> String:
	if typeof(context.get("target_id", "")) != TYPE_STRING or str(context.get("target_id", "")) != action.target_id:
		return "当前行动目标与上下文不一致"
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
	society: SocietySimulationService,
	map_service: MapControlService
) -> String:
	if definition.category in ["build_relationship", "investigate_character"]:
		if not society.roster.has_character(action.target_id) or action.target_id == action.actor_character_id:
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


func _validate_formula(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	actor: CharacterData
) -> String:
	var rules := ActionRulesConfig.new()
	if rules.load_from_file() != OK:
		return "无法验证当前行动公式：%s" % rules.error_message
	var evaluator := ActionService.new(rules, StableIdService.new())
	if action.outlook != rules.get_outlook(action.effective_value, definition.guaranteed_success_threshold):
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
			and definition.category in ["seek_position", "support_control", "investigate_character"]
		)
		if action.outcome_code != expected and not domain_failure:
			return "已完成行动结果与有效值阈值不一致"
	return ""


static func id_state_covers(state: Dictionary, id: String, expected_namespace: String) -> bool:
	if not StableIdService.is_valid_id(id) or StableIdService.get_namespace(id) != expected_namespace:
		return false
	var slug: String = id.get_slice(":", 1)
	return slug.is_valid_int() and int(slug) >= 1 and int(state.get(expected_namespace, 0)) >= int(slug)
