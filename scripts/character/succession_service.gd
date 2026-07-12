class_name SuccessionService
extends RefCounted
## Selects successors from real social links and transfers only configured portions.

var rules: ContinuityRulesConfig
var roster: CharacterRosterService
var organizations: OrganizationService
var relationships: RelationshipService
var ai: SimpleAiService


func _init(
	continuity_rules: ContinuityRulesConfig,
	character_roster: CharacterRosterService,
	organization_service: OrganizationService,
	relationship_service: RelationshipService,
	ai_service: SimpleAiService
) -> void:
	rules = continuity_rules
	roster = character_roster
	organizations = organization_service
	relationships = relationship_service
	ai = ai_service


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
		var organization: OrganizationData = organizations.get_organization(organization_id)
		if organization == null:
			continue
		for member_id: String in organization.member_ids:
			if member_id == character_id:
				continue
			if not evidence.has(member_id):
				evidence[member_id] = {"relationship": null, "shared": []}
			var item: Dictionary = evidence[member_id] as Dictionary
			var shared: Array[String] = DataRecordUtils.to_string_array(item["shared"])
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
		var score: float = _score_candidate(candidate_source, relationship, shared)
		if score < float(rules.candidate["minimum_score"]):
			continue
		var candidate := SuccessionCandidateData.new()
		candidate.character_id = candidate_id
		candidate.name = str(candidate_source.name)
		candidate.score = snappedf(score, 0.001)
		candidate.relationship_id = "" if relationship == null else relationship.id
		candidate.shared_organization_ids = shared.duplicate()
		candidate.role_label = _role_label(relationship, shared)
		output.append(candidate)
	output.sort_custom(func(a: SuccessionCandidateData, b: SuccessionCandidateData) -> bool:
		return a.character_id < b.character_id if is_equal_approx(a.score, b.score) else a.score > b.score
	)
	return output


func execute_succession(
	old_character_id: String,
	successor_character_id: String,
	exit_reason: String,
	current_hour: int
) -> SuccessionResult:
	var result := SuccessionResult.new()
	if not rules.exit_reasons.has(exit_reason):
		result.add_error("未知退出原因：%s" % exit_reason)
		return result
	var old_character: CharacterData = roster.get_active(old_character_id)
	if old_character == null or old_character_id != roster.player_character_id:
		result.add_error("只有当前玩家人物可以执行继承")
		return result
	var selected: SuccessionCandidateData
	for candidate: SuccessionCandidateData in get_candidates(old_character_id):
		if candidate.character_id == successor_character_id:
			selected = candidate
			break
	if selected == null:
		result.add_error("所选人物不是有效继承候选")
		return result
	var successor: CharacterData = roster.get_active(successor_character_id)
	if successor == null:
		successor = roster.promote(successor_character_id)
	if successor == null:
		result.add_error("无法将继承候选升级到活跃层")
		return result

	var reason_rules: Dictionary = rules.exit_reasons[exit_reason] as Dictionary
	var old_relationships: Array[RelationshipData] = relationships.get_for_character(old_character_id)
	var old_positions: Dictionary = {}
	for organization_id: String in old_character.organization_ids:
		old_positions[organization_id] = organizations.get_position_id(
			old_character_id, organization_id
		)
	_transfer_resources(old_character, successor, reason_rules, result)
	_transfer_relationships(
		old_character_id, successor, old_relationships, reason_rules, current_hour, result
	)
	_transfer_organizations(
		old_character, successor, old_positions, reason_rules, selected.score, result
	)
	ai.unregister(successor.id)
	var exited: ExitedCharacterRecord = roster.exit_active_character(
		old_character_id, exit_reason, current_hour
	)
	if exited == null or not roster.set_player_character(successor):
		result.add_error("无法完成玩家人物切换")
		return result
	exited.successor_character_id = successor.id
	result.successor = successor
	result.exited_record = exited
	GameSessionService.transfer_player(successor)
	return result


func _transfer_resources(
	old_character: CharacterData,
	successor: CharacterData,
	reason_rules: Dictionary,
	result: SuccessionResult
) -> void:
	var old_wealth: int = int(old_character.current_status.get("wealth", 0))
	var old_reputation: int = int(old_character.current_status.get("reputation", 0))
	var old_intelligence: int = int(old_character.current_status.get("intelligence_points", 0))
	result.inherited_wealth = floori(float(old_wealth) * float(reason_rules["wealth_ratio"]))
	result.inherited_reputation = floori(float(old_reputation) * float(reason_rules["reputation_ratio"]))
	result.inherited_intelligence = floori(float(old_intelligence) * float(reason_rules["intelligence_ratio"]))
	old_character.current_status["wealth"] = old_wealth - result.inherited_wealth
	successor.current_status["wealth"] = int(successor.current_status.get("wealth", 0)) + result.inherited_wealth
	successor.current_status["reputation"] = int(successor.current_status.get("reputation", 0)) + result.inherited_reputation
	successor.current_status["intelligence_points"] = int(successor.current_status.get("intelligence_points", 0)) + result.inherited_intelligence


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
		if other_id == successor.id or roster.get_public_character(other_id) == null:
			continue
		var is_enemy: bool = old_relationship.affinity <= rules.enemy_affinity_threshold
		var ratio: float = float(reason_rules[
			"enemy_relationship_ratio" if is_enemy else "ally_relationship_ratio"
		])
		var inherited: RelationshipData = relationships.create_or_update(
			successor.id, other_id, current_hour, {},
			"inherited_rival" if is_enemy else "inherited_ally"
		)
		if inherited == null:
			continue
		inherited.familiarity = clampf(old_relationship.familiarity * ratio, 0.0, 1.0)
		inherited.trust = clampf(old_relationship.trust * ratio, -1.0, 1.0)
		inherited.affinity = clampf(old_relationship.affinity * ratio, -1.0, 1.0)
		inherited.is_public = old_relationship.is_public
		result.inherited_relationship_count += 1
		if is_enemy:
			result.inherited_enemy_count += 1


func _transfer_organizations(
	old_character: CharacterData,
	successor: CharacterData,
	old_positions: Dictionary,
	reason_rules: Dictionary,
	candidate_score: float,
	result: SuccessionResult
) -> void:
	var organization_ids: Array[String] = old_character.organization_ids.duplicate()
	for organization_id: String in organization_ids:
		var old_position: String = str(old_positions.get(organization_id, ""))
		organizations.leave_organization(old_character, organization_id)
		if not organizations.join_organization(successor, organization_id):
			continue
		if bool(reason_rules.get("position_inheritance", false)) and candidate_score >= rules.position_inheritance_minimum_score and not old_position.is_empty() and organizations.assign_position(successor, organization_id, old_position):
			result.inherited_position_count += 1


func _score_candidate(
	candidate: Variant,
	relationship: RelationshipData,
	shared_organizations: Array[String]
) -> float:
	var score: float = float(shared_organizations.size()) * float(
		rules.candidate["shared_organization_bonus"]
	)
	if relationship != null:
		score += relationship.familiarity * float(rules.candidate["familiarity_weight"])
		score += maxf(relationship.trust, 0.0) * float(rules.candidate["trust_weight"])
		score += maxf(relationship.affinity, 0.0) * float(rules.candidate["affinity_weight"])
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
	relationship: RelationshipData, shared_organizations: Array[String]
) -> String:
	if not shared_organizations.is_empty():
		return "同组织继任者"
	if relationship != null and relationship.trust >= 0.5:
		return "可信盟友"
	return "社会关系候选"
