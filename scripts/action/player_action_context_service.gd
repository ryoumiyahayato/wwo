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
	target_id: String
) -> Dictionary:
	if definition == null or character == null:
		return {}
	return {
		"target_id": target_id,
		"position_permissions": _get_permissions(character.id),
		"organization_support": _organization_support(character, target_id),
		"relationship_support": _relationship_support(character.id, target_id),
		"funding": float(get_funding_cost(definition)) * float(
			rules.player_context_rules.get("funding_value_per_wealth", 0.0)
		),
		"preparation": _preparation(definition, character),
		"target_resistance": _target_resistance(target_id),
	}


func get_funding_cost(definition: ActionDefinitionData) -> int:
	if definition == null:
		return 0
	var costs: Dictionary = rules.player_context_rules.get(
		"funding_cost_by_category", {}
	) as Dictionary
	return maxi(int(costs.get(definition.category, 0)), 0)


func can_afford(definition: ActionDefinitionData, character: CharacterData) -> bool:
	return character != null and int(character.current_status.get("wealth", 0)) >= get_funding_cost(definition)


func consume_funding(definition: ActionDefinitionData, character: CharacterData) -> bool:
	if not can_afford(definition, character):
		return false
	var cost: int = get_funding_cost(definition)
	character.current_status["wealth"] = int(character.current_status.get("wealth", 0)) - cost
	return true


func describe(
	definition: ActionDefinitionData,
	character: CharacterData,
	target_id: String
) -> String:
	var context: Dictionary = build_context(definition, character, target_id)
	if context.is_empty():
		return "行动条件尚未就绪。"
	var cost: int = get_funding_cost(definition)
	var wealth: int = int(character.current_status.get("wealth", 0))
	var affordability: String = "可支付" if wealth >= cost else "资金不足"
	return "系统根据人物状态自动计算：\n准备 %.0f · 组织支持 %.0f · 关系支持 %.0f · 目标阻力 %.0f\n行动费用 %d（当前财富 %d，%s）" % [
		float(context["preparation"]),
		float(context["organization_support"]),
		float(context["relationship_support"]),
		float(context["target_resistance"]),
		cost,
		wealth,
		affordability,
	]


func _preparation(definition: ActionDefinitionData, character: CharacterData) -> float:
	var config: Dictionary = rules.player_context_rules
	return clampf(
		float(config.get("base_preparation", 0.0))
		+ float(character.skills.get(definition.primary_skill, 0))
		* float(config.get("primary_skill_preparation_scale", 0.0))
		+ float(character.current_status.get("intelligence_points", 0))
		* float(config.get("intelligence_preparation_scale", 0.0)),
		0.0,
		100.0
	)


func _get_permissions(character_id: String) -> Array[String]:
	if society == null or society.organizations == null:
		return []
	return society.organizations.get_character_permissions(character_id)


func _organization_support(character: CharacterData, target_id: String) -> float:
	if society == null or society.organizations == null:
		return 0.0
	var config: Dictionary = rules.player_context_rules
	var best: float = 0.0
	for organization_id: String in character.organization_ids:
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		if organization == null:
			continue
		var position_id: String = society.organizations.get_position_id(character.id, organization_id)
		var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
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


func _relationship_support(character_id: String, target_id: String) -> float:
	if society == null or society.relationships == null:
		return 0.0
	var relationship: RelationshipData
	if society.roster.has_character(target_id):
		relationship = society.relationships.get_between(character_id, target_id)
	else:
		var organization: OrganizationData = society.organizations.get_organization(target_id)
		if organization != null and not organization.leader_character_id.is_empty():
			relationship = society.relationships.get_between(
				character_id, organization.leader_character_id
			)
	if relationship == null:
		return 0.0
	var config: Dictionary = rules.player_context_rules
	return clampf(
		relationship.familiarity * float(config.get("relationship_familiarity_scale", 0.0))
		+ maxf(relationship.trust, 0.0) * float(config.get("relationship_trust_scale", 0.0))
		+ maxf(relationship.affinity, 0.0) * float(config.get("relationship_affinity_scale", 0.0)),
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
	var organization: OrganizationData = society.organizations.get_organization(target_id)
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
