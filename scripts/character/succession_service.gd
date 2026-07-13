class_name SuccessionService
extends RefCounted
## Selects successors from real social links and transfers only configured portions.

var rules: ContinuityRulesConfig
var roster: CharacterRosterService
var organizations: OrganizationService
var relationships: RelationshipService
var ai: SimpleAiService
var society_rules: SocietyRulesConfig


func _init(
	continuity_rules: ContinuityRulesConfig,
	character_roster: CharacterRosterService,
	organization_service: OrganizationService,
	relationship_service: RelationshipService,
	ai_service: SimpleAiService,
	simulation_rules: SocietyRulesConfig
) -> void:
	rules = continuity_rules
	roster = character_roster
	organizations = organization_service
	relationships = relationship_service
	ai = ai_service
	society_rules = simulation_rules


func get_candidates(character_id: String) -> Array[SuccessionCandidateData]:
	var source: Variant = roster.get_public_character(character_id)
	if source == null:
		return []
	var evidence: Dictionary = {}
	for relationship: RelationshipData in relationships.get_for_character(character_id):
		var other_id: String = (
			relationship.character_b_id
			if relationship.character_a_id == character_id
			else relationship.character_a_id
		)
		evidence[other_id] = {"relationship": relationship, "shared": []}
	var source_orgs: Array[String] = _get_organization_ids(source)
	for organization_id: String in source_orgs:
		var organization: OrganizationData = organizations.get_organization(
			organization_id
		)
		if organization == null:
			continue
		for member_id: String in organization.member_ids:
			if member_id == character_id:
				continue
			if not evidence.has(member_id):
				evidence[member_id] = {"relationship": null, "shared": []}
			var item: Dictionary = evidence[member_id] as Dictionary
			var shared: Array[String] = DataRecordUtils.to_string_array(
				item["shared"]
			)
			if not shared.has(organization_id):
				shared.append(organization_id)
			item["shared"] = shared
			evidence[member_id] = item

	var output: Array[SuccessionCandidateData] = []
	for raw_candidate_id: Variant in evidence:
		var candidate_id: String = str(raw_candidate_id)
		var candidate_source: Variant = roster.get_public_character(candidate_id)
		if not _is_eligible(candidate_source, source):
			continue
		var item: Dictionary = evidence[candidate_id] as Dictionary
		var relationship: RelationshipData = item["relationship"] as RelationshipData
		var shared: Array[String] = DataRecordUtils.to_string_array(item["shared"])
		var score: float = _score_candidate(
			candidate_source, relationship, shared
		)
		if score < float(rules.candidate["minimum_score"]):
			continue
		var candidate := SuccessionCandidateData.new()
		candidate.character_id = candidate_id
		candidate.name = str(candidate_source.name)
		candidate.score = snappedf(score, 0.001)
		candidate.relationship_id = (
			"" if relationship == null else relationship.id
		)
		candidate.shared_organization_ids = shared.duplicate()
		candidate.role_label = _role_label(relationship, shared)
		output.append(candidate)
	output.sort_custom(func(a: SuccessionCandidateData, b: SuccessionCandidateData) -> bool:
		return a.character_id < b.character_id if is_equal_approx(a.score, b.score) else a.score > b.score
	)
	return output


func get_valid_exit_reason_ids(character: CharacterData) -> Array[String]:
	var output: Array[String] = []
	if character == null:
		return output
	for reason_id: String in rules.get_exit_reason_ids():
		if get_exit_reason_validation_error(character, reason_id).is_empty():
			output.append(reason_id)
	return output


func get_exit_reason_validation_error(
	character: CharacterData, exit_reason: String
) -> String:
	if character == null:
		return "继承退出人物不存在"
	if not rules.exit_reasons.has(exit_reason):
		return "未知退出原因：%s" % exit_reason
	if exit_reason == "voluntary":
		return ""
	if society_rules == null:
		return "社会生命周期规则尚未就绪"
	var lifecycle: Dictionary = society_rules.lifecycle_rules
	var required: bool = bool(
		character.current_status.get("succession_required", false)
	)
	var declared_reason: String = str(
		character.current_status.get("succession_reason", "")
	)
	match exit_reason:
		"retirement":
			var retirement_age: int = int(lifecycle.get("retirement_age", 65))
			if character.age < retirement_age and not (
				required and declared_reason == "retirement"
			):
				return "人物尚未达到退休年龄"
		"death":
			var maximum_age: int = int(lifecycle.get("maximum_age", 90))
			var health: int = int(character.current_status.get("health", 100))
			if health > 0 and character.age < maximum_age and not (
				required and declared_reason == "death"
			):
				return "人物当前并未死亡"
		"long_imprisonment":
			if not bool(character.current_status.get("detained", false)):
				return "人物当前没有被拘禁"
		"disgrace":
			var threshold: int = int(
				rules.exit_constraints.get("disgrace_reputation_threshold", 5)
			)
			var disgraced: bool = bool(
				character.current_status.get("disgraced", false)
			)
			if int(character.current_status.get("reputation", 0)) > threshold and not disgraced and not (
				required and declared_reason == "disgrace"
			):
				return "人物尚未达到严重失势条件"
	return ""


func execute_succession(
	old_character_id: String,
	successor_character_id: String,
	exit_reason: String,
	current_hour: int
) -> SuccessionResult:
	var result := SuccessionResult.new()
	if current_hour < 0:
		result.add_error("继承时间无效")
		return result
	if not rules.exit_reasons.has(exit_reason):
		result.add_error("未知退出原因：%s" % exit_reason)
		return result
	var old_character: CharacterData = roster.get_active(old_character_id)
	if old_character == null or old_character_id != roster.player_character_id:
		result.add_error("只有当前玩家人物可以执行继承")
		return result
	var exit_error: String = get_exit_reason_validation_error(
		old_character, exit_reason
	)
	if not exit_error.is_empty():
		result.add_error(exit_error)
		return result
	var selected: SuccessionCandidateData
	for candidate: SuccessionCandidateData in get_candidates(old_character_id):
		if candidate.character_id == successor_character_id:
			selected = candidate
			break
	if selected == null:
		result.add_error("所选人物不是有效继承候选")
		return result

	var roster_before: Dictionary = roster.get_persistent_state()
	var organizations_before: Array[Dictionary] = organizations.get_persistent_state()
	var relationships_before: Dictionary = relationships.get_persistent_state()
	var ai_before: Array[Dictionary] = ai.get_persistent_state()
	var old_relationships: Array[RelationshipData] = relationships.get_for_character(
		old_character_id
	)
	var old_positions: Dictionary = {}
	for organization_id: String in old_character.organization_ids:
		old_positions[organization_id] = organizations.get_position_id(
			old_character_id, organization_id
		)

	var exited: ExitedCharacterRecord = roster.exit_active_character(
		old_character_id, exit_reason, current_hour
	)
	if exited == null:
		result.add_error("无法记录当前人物退出")
		return result
	var successor: CharacterData = roster.get_active(successor_character_id)
	if successor == null:
		successor = roster.promote(successor_character_id)
	if successor == null:
		_rollback(
			roster_before,
			organizations_before,
			relationships_before,
			ai_before
		)
		result.add_error("无法将继承候选升级到活跃层")
		return result

	var reason_rules: Dictionary = rules.exit_reasons[exit_reason] as Dictionary
	_transfer_resources(old_character, successor, reason_rules, result)
	_transfer_relationships(
		old_character_id,
		successor,
		old_relationships,
		reason_rules,
		current_hour,
		result
	)
	_transfer_organizations(
		old_character,
		successor,
		old_positions,
		reason_rules,
		selected.score,
		selected.shared_organization_ids,
		result
	)
	ai.unregister(successor.id)
	if not roster.set_player_character(successor):
		_rollback(
			roster_before,
			organizations_before,
			relationships_before,
			ai_before
		)
		result.add_error("无法完成玩家人物切换")
		return result
	successor.current_status.erase("succession_required")
	successor.current_status.erase("succession_reason")
	exited.successor_character_id = successor.id
	result.successor = successor
	result.exited_record = exited
	GameSessionService.transfer_player(successor)
	return result


func _rollback(
	roster_state: Dictionary,
	organization_state: Array[Dictionary],
	relationship_state: Dictionary,
	ai_state: Array[Dictionary]
) -> bool:
	if not roster.restore_persistent_state(roster_state):
		return false
	if not organizations.restore_persistent_state(organization_state):
		return false
	if not relationships.restore_persistent_state(relationship_state):
		return false
	if not ai.restore_persistent_state(ai_state):
		return false
	var restored_player: CharacterData = roster.get_active(
		roster.player_character_id
	)
	if restored_player == null:
		return false
	GameSessionService.player_character = restored_player
	GameSessionService.selected_country_id = restored_player.country_id
	return true


func _transfer_resources(
	old_character: CharacterData,
	successor: CharacterData,
	reason_rules: Dictionary,
	result: SuccessionResult
) -> void:
	var old_wealth: int = int(old_character.current_status.get("wealth", 0))
	var old_reputation: int = int(
		old_character.current_status.get("reputation", 0)
	)
	var old_intelligence: int = int(
		old_character.current_status.get("intelligence_points", 0)
	)
	result.inherited_wealth = floori(
		float(old_wealth) * float(reason_rules["wealth_ratio"])
	)
	result.inherited_reputation = floori(
		float(old_reputation) * float(reason_rules["reputation_ratio"])
	)
	result.inherited_intelligence = floori(
		float(old_intelligence) * float(reason_rules["intelligence_ratio"])
	)
	old_character.current_status["wealth"] = old_wealth - result.inherited_wealth
	successor.current_status["wealth"] = int(
		successor.current_status.get("wealth", 0)
	) + result.inherited_wealth
	successor.current_status["reputation"] = int(
		successor.current_status.get("reputation", 0)
	) + result.inherited_reputation
	successor.current_status["intelligence_points"] = int(
		successor.current_status.get("intelligence_points", 0)
	) + result.inherited_intelligence


func _transfer_relationships(
	old_character_id: String,
	successor: CharacterData,
	old_relationships: Array[RelationshipData],
	reason_rules: Dictionary,
	current_hour: int,
	result: SuccessionResult
) -> void:
	for old_relationship: RelationshipData in old_relationships:
		var other_id: String = (
			old_relationship.character_b_id
			if old_relationship.character_a_id == old_character_id
			else old_relationship.character_a_id
		)
		if (
			other_id == successor.id
			or roster.get_public_character(other_id) == null
		):
			continue
		var is_enemy: bool = (
			old_relationship.affinity <= rules.enemy_affinity_threshold
		)
		var ratio: float = float(
			reason_rules[
				"enemy_relationship_ratio"
				if is_enemy
				else "ally_relationship_ratio"
			]
		)
		var inherited_familiarity: float = clampf(
			old_relationship.familiarity * ratio, 0.0, 1.0
		)
		var inherited_trust: float = clampf(
			old_relationship.trust * ratio, -1.0, 1.0
		)
		var inherited_affinity: float = clampf(
			old_relationship.affinity * ratio, -1.0, 1.0
		)
		var existing: RelationshipData = relationships.get_between(
			successor.id, other_id
		)
		var inherited: RelationshipData = relationships.create_or_update(
			successor.id,
			other_id,
			current_hour,
			{},
			(
				""
				if existing != null
				else "inherited_rival" if is_enemy else "inherited_ally"
			)
		)
		if inherited == null:
			continue
		if existing == null:
			inherited.familiarity = inherited_familiarity
			inherited.trust = inherited_trust
			inherited.affinity = inherited_affinity
			inherited.is_public = old_relationship.is_public
		else:
			inherited.familiarity = maxf(
				existing.familiarity, inherited_familiarity
			)
			inherited.trust = _merge_relationship_axis(
				existing.trust, inherited_trust
			)
			inherited.affinity = _merge_relationship_axis(
				existing.affinity, inherited_affinity
			)
			inherited.is_public = (
				existing.is_public or old_relationship.is_public
			)
		result.inherited_relationship_count += 1
		if is_enemy:
			result.inherited_enemy_count += 1


func _transfer_organizations(
	old_character: CharacterData,
	successor: CharacterData,
	old_positions: Dictionary,
	reason_rules: Dictionary,
	candidate_score: float,
	shared_organization_ids: Array[String],
	result: SuccessionResult
) -> void:
	var organization_ids: Array[String] = old_character.organization_ids.duplicate()
	var maximum_new_memberships: int = maxi(
		int(rules.candidate.get("maximum_inherited_organizations", 2)), 0
	)
	var inherited_memberships: int = 0
	var can_inherit_position: bool = (
		bool(reason_rules.get("position_inheritance", false))
		and candidate_score >= rules.position_inheritance_minimum_score
	)
	for organization_id: String in organization_ids:
		var old_position: String = str(
			old_positions.get(organization_id, "")
		)
		organizations.leave_organization(old_character, organization_id)
		var already_member: bool = successor.organization_ids.has(organization_id)
		var eligible_membership: bool = (
			shared_organization_ids.has(organization_id)
			or can_inherit_position
		)
		if not already_member:
			if (
				not eligible_membership
				or inherited_memberships >= maximum_new_memberships
				or not organizations.join_organization(
					successor, organization_id
				)
			):
				continue
			inherited_memberships += 1
		if (
			can_inherit_position
			and not old_position.is_empty()
			and _is_position_upgrade(
				successor.id, organization_id, old_position
			)
			and organizations.assign_position(
				successor, organization_id, old_position
			)
		):
			result.inherited_position_count += 1


func _is_position_upgrade(
	character_id: String,
	organization_id: String,
	candidate_position_id: String
) -> bool:
	var organization: OrganizationData = organizations.get_organization(
		organization_id
	)
	if organization == null:
		return false
	var positions: Dictionary = organization.position_structure.get(
		"positions", {}
	) as Dictionary
	if not positions.has(candidate_position_id):
		return false
	var current_position_id: String = organizations.get_position_id(
		character_id, organization_id
	)
	var current_level: int = int(
		(positions.get(current_position_id, {}) as Dictionary).get("level", 0)
	)
	var candidate_level: int = int(
		(positions[candidate_position_id] as Dictionary).get("level", 0)
	)
	return candidate_level > current_level


static func _merge_relationship_axis(
	existing_value: float, inherited_value: float
) -> float:
	var remaining_capacity: float = 1.0 - absf(existing_value)
	return clampf(
		existing_value + inherited_value * remaining_capacity * 0.5,
		-1.0,
		1.0
	)


func _score_candidate(
	candidate: Variant,
	relationship: RelationshipData,
	shared_organizations: Array[String]
) -> float:
	var score: float = float(shared_organizations.size()) * float(
		rules.candidate["shared_organization_bonus"]
	)
	if relationship != null:
		score += relationship.familiarity * float(
			rules.candidate["familiarity_weight"]
		)
		score += maxf(relationship.trust, 0.0) * float(
			rules.candidate["trust_weight"]
		)
		score += maxf(relationship.affinity, 0.0) * float(
			rules.candidate["affinity_weight"]
		)
	score += float(candidate.current_status.get("reputation", 0)) * float(
		rules.candidate["reputation_weight"]
	)
	return score


func _is_eligible(candidate: Variant, source: Variant) -> bool:
	if candidate == null or candidate.id == source.id or candidate.country_id != source.country_id:
		return false
	if roster.get_exited(str(candidate.id)) != null:
		return false
	return not bool(candidate.current_status.get("detained", false))


static func _get_organization_ids(character: Variant) -> Array[String]:
	return DataRecordUtils.to_string_array(character.organization_ids)


static func _role_label(
	relationship: RelationshipData,
	shared_organizations: Array[String]
) -> String:
	if not shared_organizations.is_empty():
		return "同组织继任者"
	if relationship != null and relationship.trust >= 0.5:
		return "可信盟友"
	return "社会关系候选"
