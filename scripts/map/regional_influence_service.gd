class_name RegionalInfluenceService
extends RefCounted
## Social influence is authoritative on RegionData and never mutates military fields.

signal social_influence_changed(region_id: String)

var rules: ContinuityRulesConfig


func _init(continuity_rules: ContinuityRulesConfig) -> void:
	rules = continuity_rules


func apply_social_influence(
	region: RegionData, country_id: String, delta: float
) -> bool:
	if region == null or country_id.is_empty() or not region.social_influence.has(country_id) or is_zero_approx(delta):
		return false
	var ids: Array[String] = []
	for raw_id: Variant in region.social_influence:
		ids.append(str(raw_id))
	ids.sort()
	var old_value: float = float(region.social_influence[country_id])
	var new_value: float = clampf(old_value + delta, 0.0, 1.0)
	var applied_delta: float = new_value - old_value
	if is_zero_approx(applied_delta):
		return false
	region.social_influence[country_id] = new_value
	var other_ids: Array[String] = []
	for id: String in ids:
		if id != country_id:
			other_ids.append(id)
	if not other_ids.is_empty():
		var per_other: float = applied_delta / float(other_ids.size())
		for other_id: String in other_ids:
			region.social_influence[other_id] = clampf(
				float(region.social_influence[other_id]) - per_other, 0.0, 1.0
			)
	_normalize_influence(region.social_influence)
	social_influence_changed.emit(region.id)
	return true


func apply_policy_action(
	control_unit_id: String,
	country_id: String,
	map_service: MapControlService
) -> bool:
	var unit: ControlUnitData = map_service.get_unit(control_unit_id)
	if unit == null:
		return false
	var region: RegionData = map_service.data_set.regions[unit.region_id] as RegionData
	return apply_social_influence(
		region, country_id, float(rules.social_influence["policy_delta"])
	)


func apply_organization_social_support(
	organization: OrganizationData,
	character_id: String,
	region_id: String,
	effort: float,
	organization_service: OrganizationService,
	map_service: MapControlService
) -> bool:
	if organization == null or not organization_service.has_permission(character_id, organization.id, "regional_policy"):
		return false
	var applied_effort: float = clampf(effort, 0.0, 1.0)
	var cost: float = applied_effort * float(rules.social_influence["organization_resource_cost"])
	if applied_effort <= 0.0 or organization.resources < maxf(cost, float(rules.social_influence["minimum_organization_resources"])) or not map_service.data_set.regions.has(region_id):
		return false
	var region: RegionData = map_service.data_set.regions[region_id] as RegionData
	var delta: float = applied_effort * organization.influence * float(
		rules.social_influence["organization_delta_scale"]
	)
	if not apply_social_influence(region, organization.country_id, delta):
		return false
	organization.resources -= cost
	return true


func apply_organization_control_support(
	organization: OrganizationData,
	character_id: String,
	control_unit_id: String,
	effort: float,
	organization_service: OrganizationService,
	map_service: MapControlService
) -> bool:
	if organization == null or not organization_service.has_permission(character_id, organization.id, "regional_control_support"):
		return false
	var applied_effort: float = clampf(effort, 0.0, 1.0)
	var cost: float = applied_effort * float(rules.social_influence["control_resource_cost"])
	if applied_effort <= 0.0 or organization.resources < maxf(cost, float(rules.social_influence["minimum_organization_resources"])):
		return false
	if not map_service.apply_control_pressure(
		control_unit_id, organization.country_id, applied_effort
	):
		return false
	organization.resources -= cost
	return true


func apply_action_domain_effect(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	map_service: MapControlService
) -> bool:
	if action == null or action.status != ActionInstanceData.STATUS_COMPLETED or action.outcome_code == "failure" or action.domain_effect_applied:
		return false
	var effect_id: String = str(action.applied_effects.get("domain_effect", ""))
	var applied: bool = false
	if effect_id == "regional_policy_support":
		applied = apply_policy_action(action.target_id, character.country_id, map_service)
	elif action.applied_effects.has("control_pressure"):
		# The military effect is already applied by ActionService; mark the domain hook consumed.
		applied = true
	if applied:
		action.domain_effect_applied = true
	return applied


static func _normalize_influence(influence: Dictionary) -> void:
	var total: float = 0.0
	for raw_value: Variant in influence.values():
		total += float(raw_value)
	if total <= 0.0:
		return
	for raw_id: Variant in influence:
		influence[raw_id] = float(influence[raw_id]) / total

