class_name PlayerActionContextService
extends RefCounted
## Builds player action inputs from authoritative resources, relationships and positions.

var rules: ActionRulesConfig
var society: SocietySimulationService
var map_service: MapControlService


func _init(
	action_rules: ActionRulesConfig,
	society_service: SocietySimulationService,
	control_service: MapControlService
) -> void:
	rules = action_rules
	society = society_service
	map_service = control_service


func build_context(
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String,
	extra_funding: int = 0,
	study_skill_id: String = ""
) -> Dictionary:
	if definition == null or character == null:
		return {}
	var resolved_study_skill: String = _resolve_study_skill_id(
		definition, character, study_skill_id
	)
	if definition.category == "study_skill" and resolved_study_skill.is_empty():
		return {}
	var applied_extra: int = clampi(extra_funding, 0, get_max_extra_funding())
	var total_cost: int = get_funding_cost(definition, applied_extra)
	var running_npc: bool = _is_running_npc_action(character.id)
	return {
		"target_id": target_id,
		"study_skill_id": resolved_study_skill,
		"position_permissions": _get_permissions(character.id),
		"organization_support": _organization_support(
			definition, character, target_id
		),
		"relationship_support": _relationship_support(character.id, target_id),
		"funding": clampf(
			float(total_cost)
			* float(rules.player_context_rules.get("funding_value_per_wealth", 0.0)),
			0.0,
			100.0
		),
		"preparation": _preparation(
			definition, character, applied_extra, resolved_study_skill
		),
		"target_resistance": _target_resistance(target_id),
		"boundary_invalid_reason": _get_strict_target_validation_error(
			definition, character, target_id
		) if running_npc else "",
		"settle_previous_interval": running_npc,
	}


func build_authoritative_context_for_action(
	definition: ActionDefinitionData,
	character: CharacterData,
	action: ActionInstanceData
) -> Dictionary:
	if action == null:
		return {}
	var base_cost: int = get_base_funding_cost(definition)
	var committed_cost: int = int(action.context.get("funding_cost", base_cost))
	var extra_funding: int = clampi(
		committed_cost - base_cost,
		0,
		get_max_extra_funding()
	)
	var context: Dictionary = build_context(
		definition,
		character,
		action.target_id,
		extra_funding,
		str(action.context.get("study_skill_id", ""))
	)
	if context.is_empty():
		return context
	context["funding_cost"] = base_cost + extra_funding
	context["funding_committed"] = bool(
		action.context.get("funding_committed", true)
	)
	context["wealth_before_funding"] = int(
		action.context.get(
			"wealth_before_funding",
			int(character.current_status.get("wealth", 0))
			+ base_cost
			+ extra_funding
		)
	)
	return context


func start_player_action(
	action_service: ActionService,
	definition: ActionDefinitionData,
	character: CharacterData,
	current_hour: int,
	target_id: String,
	extra_funding: int = 0,
	study_skill_id: String = ""
) -> ActionStartResult:
	var result := ActionStartResult.new()
	if action_service == null or definition == null or character == null:
		result.add_error("行动服务、行动定义和人物必须就绪。")
		return result
	var target_error: String = _get_strict_target_validation_error(
		definition, character, target_id
	)
	if not target_error.is_empty():
		result.add_error(target_error)
		return result
	var resolved_study_skill: String = _resolve_study_skill_id(
		definition, character, study_skill_id
	)
	if definition.category == "study_skill" and resolved_study_skill.is_empty():
		result.add_error("必须选择人物拥有的有效技能作为学习目标。")
		return result
	if extra_funding < 0 or extra_funding > get_max_extra_funding():
		result.add_error("额外准备投入超出允许范围。")
		return result
	if not can_afford(definition, character, extra_funding):
		result.add_error("财富不足，无法支付本次行动投入。")
		return result
	var cost: int = get_funding_cost(definition, extra_funding)
	var wealth_before: int = int(character.current_status.get("wealth", 0))
	var context: Dictionary = build_context(
		definition,
		character,
		target_id,
		extra_funding,
		resolved_study_skill
	)
	context["boundary_invalid_reason"] = ""
	context["settle_previous_interval"] = false
	context["funding_cost"] = cost
	context["funding_committed"] = true
	context["wealth_before_funding"] = wealth_before
	character.current_status["wealth"] = wealth_before - cost
	result = action_service.start_action(definition, character, current_hour, context)
	if not result.is_success():
		character.current_status["wealth"] = wealth_before
	return result


func get_base_funding_cost(definition: ActionDefinitionData) -> int:
	if definition == null:
		return 0
	var costs: Dictionary = rules.player_context_rules.get(
		"funding_cost_by_category", {}
	) as Dictionary
	return maxi(int(costs.get(definition.category, 0)), 0)


func get_funding_cost(
	definition: ActionDefinitionData, extra_funding: int = 0
) -> int:
	return get_base_funding_cost(definition) + clampi(
		extra_funding, 0, get_max_extra_funding()
	)


func get_max_extra_funding() -> int:
	return maxi(
		int(rules.player_context_rules.get("maximum_extra_funding", 0)), 0
	)


func can_afford(
	definition: ActionDefinitionData,
	character: CharacterData,
	extra_funding: int = 0
) -> bool:
	return (
		character != null
		and int(character.current_status.get("wealth", 0))
		>= get_funding_cost(definition, extra_funding)
	)


func consume_funding(
	definition: ActionDefinitionData,
	character: CharacterData,
	extra_funding: int = 0
) -> bool:
	if not can_afford(definition, character, extra_funding):
		return false
	var cost: int = get_funding_cost(definition, extra_funding)
	character.current_status["wealth"] = (
		int(character.current_status.get("wealth", 0)) - cost
	)
	return true


func get_target_validation_error(
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String
) -> String:
	var error: String = _get_strict_target_validation_error(
		definition, character, target_id
	)
	if not error.is_empty() and character != null and _is_running_npc_action(
		character.id
	):
		# The elapsed NPC interval still belongs to the previously stored context.
		# Its new invalid state is marked in the rebuilt context and applied only
		# after that interval has been settled.
		return ""
	return error


func _get_strict_target_validation_error(
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String
) -> String:
	if definition == null or character == null:
		return "行动或人物尚未就绪。"
	if society == null or society.roster == null or society.organizations == null:
		return "社会模拟尚未就绪。"
	match definition.category:
		"study_skill", "perform_work":
			return "" if target_id.is_empty() else "此行动不应选择目标。"
		"build_relationship", "investigate_character":
			if target_id.is_empty() or not society.roster.has_character(target_id):
				return "必须选择存在的人物目标。"
			if society.roster.get_exited(target_id) != null:
				return "目标人物已经退出当前社会活动。"
			if target_id == character.id:
				return "不能把自己作为人物目标。"
			return ""
		"join_organization":
			var join_target: OrganizationData = society.organizations.get_organization(
				target_id
			)
			if join_target == null:
				return "必须选择存在的组织。"
			if join_target.country_id != character.country_id:
				return "不能加入其他国家的组织。"
			if join_target.member_ids.has(character.id):
				return "人物已经是该组织成员。"
			return ""
		"seek_position":
			var position_target: OrganizationData = society.organizations.get_organization(
				target_id
			)
			if position_target == null:
				return "必须选择存在的组织。"
			if not position_target.member_ids.has(character.id):
				return "必须先加入该组织。"
			if _get_next_available_position_id(
				character.id, position_target
			).is_empty():
				return "该组织目前没有更高的空缺职位。"
			return ""
		"promote_policy":
			if map_service == null or map_service.get_unit(target_id) == null:
				return "必须选择有效的地区控制单元。"
			var policy_unit: ControlUnitData = map_service.get_unit(target_id)
			var policy_region: RegionData = map_service.data_set.regions.get(
				policy_unit.region_id
			) as RegionData
			if policy_region == null or (
				policy_region.de_jure_country_id != character.country_id
				and policy_unit.controller_country_id != character.country_id
			):
				return "政策只能推动本国法理地区或本国实际控制地区。"
			if not _has_jurisdiction_permission(
				character, target_id, "regional_policy"
			):
				return "当前职位没有覆盖该地区的政策辖权。"
			return ""
		"support_control":
			if map_service == null or map_service.get_unit(target_id) == null:
				return "必须选择有效的地区控制单元。"
			if not map_service.is_valid_control_support_target(
				target_id, character.country_id
			):
				return "军事控制支援只能作用于本国前线相邻敌区，或需要巩固的本国前线。"
			if not _has_jurisdiction_permission(
				character, target_id, "regional_control_support"
			):
				return "只有本国政府或军队职位可以调动该前线支援。"
			return ""
		_:
			return "未知行动类别。"


func describe(
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String,
	extra_funding: int = 0,
	study_skill_id: String = ""
) -> String:
	var context: Dictionary = build_context(
		definition, character, target_id, extra_funding, study_skill_id
	)
	if context.is_empty():
		return "行动条件尚未就绪。"
	var cost: int = get_funding_cost(definition, extra_funding)
	var base_cost: int = get_base_funding_cost(definition)
	var wealth: int = int(character.current_status.get("wealth", 0))
	var affordability: String = "可支付" if wealth >= cost else "资金不足"
	var target_error: String = _get_strict_target_validation_error(
		definition, character, target_id
	)
	var target_line: String = (
		"目标有效" if target_error.is_empty() else "目标无效：%s" % target_error
	)
	var study_line: String = ""
	if definition.category == "study_skill":
		study_line = "\n学习目标：%s" % str(context["study_skill_id"])
	return "系统条件与主动投入共同计算：\n准备 %.0f · 组织支持 %.0f · 关系支持 %.0f · 目标阻力 %.0f\n基础费用 %d + 额外投入 %d = %d（当前财富 %d，%s）\n%s%s" % [
		float(context["preparation"]),
		float(context["organization_support"]),
		float(context["relationship_support"]),
		float(context["target_resistance"]),
		base_cost,
		clampi(extra_funding, 0, get_max_extra_funding()),
		cost,
		wealth,
		affordability,
		target_line,
		study_line,
	]


func _get_next_available_position_id(
	character_id: String,
	organization: OrganizationData
) -> String:
	var positions: Dictionary = organization.position_structure.get(
		"positions", {}
	) as Dictionary
	var current_id: String = society.organizations.get_position_id(
		character_id, organization.id
	)
	var current_level: int = int(
		(positions.get(current_id, {}) as Dictionary).get("level", 0)
	)
	var candidates: Array[String] = []
	for raw_position_id: Variant in positions:
		var position_id: String = str(raw_position_id)
		var position: Dictionary = positions[position_id] as Dictionary
		var holders: Array[String] = DataRecordUtils.to_string_array(
			position.get("holder_ids", [])
		)
		if (
			int(position.get("level", 0)) > current_level
			and holders.size() < int(position.get("slots", 0))
		):
			candidates.append(position_id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var a_level: int = int((positions[a] as Dictionary).get("level", 0))
		var b_level: int = int((positions[b] as Dictionary).get("level", 0))
		return a < b if a_level == b_level else a_level < b_level
	)
	return "" if candidates.is_empty() else candidates[0]


func _preparation(
	definition: ActionDefinitionData,
	character: CharacterData,
	extra_funding: int,
	study_skill_id: String = ""
) -> float:
	var config: Dictionary = rules.player_context_rules
	var preparation_skill_id: String = (
		study_skill_id
		if definition.category == "study_skill" and not study_skill_id.is_empty()
		else definition.primary_skill
	)
	return clampf(
		float(config.get("base_preparation", 0.0))
		+ float(character.skills.get(preparation_skill_id, 0))
		* float(config.get("primary_skill_preparation_scale", 0.0))
		+ float(character.current_status.get("intelligence_points", 0))
		* float(config.get("intelligence_preparation_scale", 0.0))
		+ float(extra_funding)
		* float(config.get("preparation_value_per_extra_wealth", 0.0)),
		0.0,
		100.0
	)


func _resolve_study_skill_id(
	definition: ActionDefinitionData,
	character: CharacterData,
	study_skill_id: String
) -> String:
	if definition.category != "study_skill":
		return ""
	var resolved: String = study_skill_id
	if resolved.is_empty():
		resolved = definition.primary_skill
	return resolved if character.skills.has(resolved) else ""


func _is_running_npc_action(character_id: String) -> bool:
	if society == null or society.ai == null or character_id == society.roster.player_character_id:
		return false
	var state: AiStateData = society.ai.get_state(character_id)
	return state != null and not state.current_action_record.is_empty()


func _get_permissions(character_id: String) -> Array[String]:
	if society == null or society.organizations == null:
		return []
	return society.organizations.get_character_permissions(character_id)


func _organization_support(
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String
) -> float:
	if society == null or society.organizations == null:
		return 0.0
	var config: Dictionary = rules.player_context_rules
	var best: float = 0.0
	for organization_id: String in character.organization_ids:
		var organization: OrganizationData = society.organizations.get_organization(
			organization_id
		)
		if organization == null:
			continue
		if definition.category in ["promote_policy", "support_control"] and not _organization_has_jurisdiction(
			organization,
			target_id,
			definition.position_permission_required
		):
			continue
		var position_id: String = society.organizations.get_position_id(
			character.id, organization_id
		)
		var positions: Dictionary = organization.position_structure.get(
			"positions", {}
		) as Dictionary
		var position: Dictionary = positions.get(position_id, {}) as Dictionary
		var value: float = organization.influence * float(
			config.get("organization_influence_scale", 0.0)
		) + float(position.get("level", 0)) * float(
			config.get("position_level_scale", 0.0)
		)
		if organization_id == target_id:
			value += float(config.get("position_level_scale", 0.0))
		best = maxf(best, value)
	return clampf(best, 0.0, 100.0)


func _has_jurisdiction_permission(
	character: CharacterData,
	target_id: String,
	permission_id: String
) -> bool:
	for organization_id: String in character.organization_ids:
		var organization: OrganizationData = society.organizations.get_organization(
			organization_id
		)
		if (
			organization != null
			and society.organizations.has_permission(
				character.id, organization_id, permission_id
			)
			and _organization_has_jurisdiction(
				organization, target_id, permission_id
			)
		):
			return true
	return false


func _organization_has_jurisdiction(
	organization: OrganizationData,
	target_id: String,
	permission_id: String
) -> bool:
	if organization == null or map_service == null:
		return false
	var unit: ControlUnitData = map_service.get_unit(target_id)
	if unit == null:
		return false
	if permission_id == "regional_control_support":
		return organization.type in ["government", "military"]
	if permission_id == "regional_policy":
		return (
			organization.type == "government"
			or organization.region_id == unit.region_id
		)
	return true


func _relationship_support(character_id: String, target_id: String) -> float:
	if society == null or society.relationships == null:
		return 0.0
	var relationship: RelationshipData
	if society.roster.is_living(target_id):
		relationship = society.relationships.get_between(character_id, target_id)
	else:
		var organization: OrganizationData = society.organizations.get_organization(
			target_id
		)
		if organization != null and not organization.leader_character_id.is_empty():
			relationship = society.relationships.get_between(
				character_id, organization.leader_character_id
			)
	if relationship == null:
		return 0.0
	var config: Dictionary = rules.player_context_rules
	return clampf(
		relationship.familiarity
		* float(config.get("relationship_familiarity_scale", 0.0))
		+ maxf(relationship.trust, 0.0)
		* float(config.get("relationship_trust_scale", 0.0))
		+ maxf(relationship.affinity, 0.0)
		* float(config.get("relationship_affinity_scale", 0.0)),
		0.0,
		100.0
	)


func _target_resistance(target_id: String) -> float:
	if target_id.is_empty() or society == null:
		return 0.0
	var config: Dictionary = rules.player_context_rules
	var target: Variant = society.roster.get_public_character(target_id)
	var status: Dictionary = {}
	if target is CharacterData:
		status = (target as CharacterData).current_status
	elif target is BackgroundCharacterData:
		status = (target as BackgroundCharacterData).current_status
	if not status.is_empty():
		return clampf(
			float(status.get("reputation", 0))
			* float(config.get("character_reputation_resistance_scale", 0.0)),
			0.0,
			100.0
		)
	var organization: OrganizationData = society.organizations.get_organization(
		target_id
	)
	if organization != null:
		return clampf(
			organization.influence
			* float(config.get("organization_influence_resistance_scale", 0.0)),
			0.0,
			100.0
		)
	if map_service != null:
		var unit: ControlUnitData = map_service.get_unit(target_id)
		if unit != null:
			return clampf(
				unit.contested_level
				* float(config.get("control_contested_resistance_scale", 0.0))
				+ unit.enemy_pressure
				* float(config.get("control_enemy_pressure_resistance_scale", 0.0)),
				0.0,
				100.0
			)
	return 0.0
