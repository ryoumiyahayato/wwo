class_name SocietySimulationService
extends RefCounted
## Composition root for roster, organizations, sparse relationships and bounded active AI.

var rules: SocietyRulesConfig
var roster: CharacterRosterService
var organizations: OrganizationService
var relationships: RelationshipService
var ai: SimpleAiService
var continuity_rules: ContinuityRulesConfig
var regional_influence: RegionalInfluenceService
var succession: SuccessionService
var initialization_error: String = ""
var paused_settlement_categories: Dictionary = {}
var _clock: SimulationClock
var _map_service: MapControlService
var _data_set: CoreDataSet


func initialize(player: CharacterData, data_set: CoreDataSet) -> bool:
	_data_set = data_set
	rules = SocietyRulesConfig.new()
	if rules.load_from_file() != OK:
		initialization_error = rules.error_message
		return false
	continuity_rules = ContinuityRulesConfig.new()
	if continuity_rules.load_from_file() != OK:
		initialization_error = continuity_rules.error_message
		return false
	var character_config := CharacterGenerationConfig.load_from_file()
	if not character_config.is_valid():
		initialization_error = character_config.error_message
		return false
	roster = CharacterRosterService.new(data_set, character_config, rules)
	if not roster.initialize_background_population() or not roster.register_player(player):
		initialization_error = "无法建立分层人物名册"
		return false
	organizations = OrganizationService.new(data_set.organizations)
	relationships = RelationshipService.new(
		roster, rules.relationship_defaults, StableIdService.new()
	)
	ai = SimpleAiService.new(roster, rules)
	regional_influence = RegionalInfluenceService.new(continuity_rules)
	succession = SuccessionService.new(
		continuity_rules, roster, organizations, relationships, ai
	)
	_initialize_organization_leaders()
	ai.run_long_term_evaluations(0)
	ai.run_daily_decisions(0)
	return true


func attach_clock(simulation_clock: SimulationClock) -> void:
	attach_world(simulation_clock, _map_service)


func attach_world(
	simulation_clock: SimulationClock,
	control_service: MapControlService
) -> void:
	if control_service != null:
		_map_service = control_service
	if simulation_clock == null or simulation_clock == _clock:
		return
	_clock = simulation_clock
	_clock.day_advanced.connect(_on_day_advanced)
	_clock.month_advanced.connect(_on_month_advanced)


func set_settlement_paused(category: String, paused: bool) -> void:
	if paused:
		paused_settlement_categories[category] = true
	else:
		paused_settlement_categories.erase(category)


func promote_background(character_id: String) -> CharacterData:
	var character: CharacterData = roster.promote(character_id)
	if character != null:
		ai.register_active_npc(character_id)
		ai.run_long_term_evaluations(_current_hour())
		ai.run_daily_decisions(_current_hour())
	return character


func demote_active(character_id: String) -> BackgroundCharacterData:
	if character_id == roster.player_character_id:
		return null
	for raw_organization: Variant in organizations.organizations.values():
		if (raw_organization as OrganizationData).leader_character_id == character_id:
			return null
	ai.unregister(character_id)
	return roster.demote(character_id)


func create_player_relationship(
	other_character_id: String, current_hour: int
) -> RelationshipData:
	return relationships.create_or_update(
		roster.player_character_id, other_character_id, current_hour,
		{"familiarity": 0.08, "trust": 0.02, "affinity": 0.01}, "player_contact"
	)


func apply_action_domain_effect(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	map_service: MapControlService
) -> bool:
	if action == null or definition == null or action.status != ActionInstanceData.STATUS_COMPLETED or action.domain_effect_applied:
		return false
	if action.outcome_code == "failure":
		action.domain_effect_applied = true
		return false
	var player: CharacterData = GameSessionService.player_character
	var applied: bool = false
	match definition.category:
		"build_relationship":
			applied = create_player_relationship(action.target_id, action.completion_hour) != null
		"join_organization":
			applied = organizations.join_organization(player, action.target_id)
		"seek_position":
			applied = _award_next_position(player, action.target_id)
		"investigate_character":
			var target: Variant = roster.get_public_character(action.target_id)
			if target != null:
				var known: Dictionary = {}
				if target is CharacterData:
					known = (target as CharacterData).known_tendencies.duplicate(true)
				player.current_status["known_character_%s" % str(target.id)] = known
				applied = true
		_:
			applied = regional_influence.apply_action_domain_effect(
				action, definition, player, map_service
			)
	if applied:
		action.domain_effect_applied = true
		GameSessionService.settlement_log.add(
			"action_domain", "行动领域结果已应用", action.completion_hour,
			{"action_id": action.id, "category": definition.category, "target_id": action.target_id}
		)
	return applied


func _award_next_position(character: CharacterData, organization_id: String) -> bool:
	var organization: OrganizationData = organizations.get_organization(organization_id)
	if organization == null or not organization.member_ids.has(character.id):
		return false
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	var current_id: String = organizations.get_position_id(character.id, organization_id)
	var current_level: int = int((positions.get(current_id, {}) as Dictionary).get("level", 0))
	var candidates: Array[String] = []
	for raw_position_id: Variant in positions:
		var position_id: String = str(raw_position_id)
		var position: Dictionary = positions[position_id] as Dictionary
		var holders: Array[String] = DataRecordUtils.to_string_array(position.get("holder_ids", []))
		if int(position.get("level", 0)) > current_level and holders.size() < int(position.get("slots", 0)):
			candidates.append(position_id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var a_level: int = int((positions[a] as Dictionary).get("level", 0))
		var b_level: int = int((positions[b] as Dictionary).get("level", 0))
		return a < b if a_level == b_level else a_level < b_level
	)
	return not candidates.is_empty() and organizations.assign_position(character, organization_id, candidates[0])


func execute_player_succession(
	successor_character_id: String, exit_reason: String, current_hour: int
) -> SuccessionResult:
	var old_player_id: String = roster.player_character_id
	if GameSessionService.current_action != null and not GameSessionService.current_action.is_terminal():
		GameSessionService.current_action.status = ActionInstanceData.STATUS_CANCELLED
		GameSessionService.current_action.estimated_completion_hour = -1
	return succession.execute_succession(
		old_player_id, successor_character_id, exit_reason, current_hour
	)


func _initialize_organization_leaders() -> void:
	var initialized: int = 0
	for organization_id: String in organizations.get_organization_ids():
		if initialized >= rules.initial_active_npc_count:
			break
		var organization: OrganizationData = organizations.get_organization(organization_id)
		var candidates: Array[String] = roster.get_background_ids(organization.country_id)
		if candidates.is_empty():
			continue
		var character: CharacterData = roster.promote(candidates[0])
		if character == null:
			break
		organizations.join_organization(character, organization_id)
		organizations.assign_position(
			character, organization_id,
			str(organization.position_structure.get("leader_position", ""))
		)
		ai.register_active_npc(character.id)
		initialized += 1


func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	if paused_settlement_categories.has("daily_ai"):
		return
	var started: int = Time.get_ticks_usec()
	ai.run_daily_decisions(_current_hour())
	var applied: int = _execute_ai_daily_actions()
	GameSessionService.performance_stats.record("daily_ai", Time.get_ticks_usec() - started)
	if applied > 0:
		GameSessionService.settlement_log.add(
			"daily_ai", "活跃 NPC 执行了 %d 项日常行动" % applied, _current_hour()
		)


func _on_month_advanced(_year: int, _month: int) -> void:
	if paused_settlement_categories.has("monthly_ai"):
		return
	var started: int = Time.get_ticks_usec()
	ai.run_long_term_evaluations(_current_hour(), true)
	var world_changes: int = _execute_ai_monthly_world_actions()
	GameSessionService.performance_stats.record("monthly_ai", Time.get_ticks_usec() - started)
	GameSessionService.settlement_log.add(
		"monthly_ai", "月度长期计划结算完成", _current_hour(),
		{"active_ai": ai.states.size(), "world_changes": world_changes}
	)


func _execute_ai_daily_actions() -> int:
	var applied: int = 0
	for character_id: String in ai.get_ai_character_ids():
		var character: CharacterData = roster.get_active(character_id)
		var state: AiStateData = ai.get_state(character_id)
		if character == null or state == null:
			continue
		match state.current_action_id:
			"rest":
				character.current_status["fatigue"] = maxi(
					int(character.current_status.get("fatigue", 0)) - 8, 0
				)
				character.current_status["stress"] = maxi(
					int(character.current_status.get("stress", 0)) - 5, 0
				)
				applied += 1
			"action:perform_work":
				character.current_status["wealth"] = int(
					character.current_status.get("wealth", 0)
				) + 1
				character.current_status["fatigue"] = mini(
					int(character.current_status.get("fatigue", 0)) + 2, 100
				)
				applied += 1
			"action:study_skill":
				if state.daily_decision_count % 7 == 0:
					var skill_id: String = _lowest_skill_id(character)
					if not skill_id.is_empty():
						character.skills[skill_id] = mini(
							int(character.skills.get(skill_id, 0)) + 1, 100
						)
						applied += 1
			"action:join_organization":
				if character.organization_ids.is_empty() and _join_first_home_organization(character):
					applied += 1
			"action:build_relationship":
				if _strengthen_existing_ai_relationship(character):
					applied += 1
	return applied


func _execute_ai_monthly_world_actions() -> int:
	if _map_service == null:
		return 0
	var applied: int = 0
	for character_id: String in ai.get_ai_character_ids():
		var character: CharacterData = roster.get_active(character_id)
		if character == null:
			continue
		for organization_id: String in character.organization_ids:
			var organization: OrganizationData = organizations.get_organization(organization_id)
			if organization == null:
				continue
			if organizations.has_permission(character.id, organization.id, "regional_policy"):
				if regional_influence.apply_organization_social_support(
					organization, character.id, organization.region_id, 0.12,
					organizations, _map_service
				):
					applied += 1
			if organizations.has_permission(character.id, organization.id, "regional_control_support"):
				var target_id: String = _first_enemy_frontier_unit(organization.country_id)
				if not target_id.is_empty() and regional_influence.apply_organization_control_support(
					organization, character.id, target_id, 0.10,
					organizations, _map_service
				):
					applied += 1
	return applied


func _lowest_skill_id(character: CharacterData) -> String:
	var ids: Array[String] = []
	for raw_id: Variant in character.skills:
		ids.append(str(raw_id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var a_value: int = int(character.skills.get(a, 0))
		var b_value: int = int(character.skills.get(b, 0))
		return a < b if a_value == b_value else a_value < b_value
	)
	return "" if ids.is_empty() else ids[0]


func _join_first_home_organization(character: CharacterData) -> bool:
	for organization_id: String in organizations.get_organization_ids():
		var organization: OrganizationData = organizations.get_organization(organization_id)
		if organization.country_id == character.country_id:
			return organizations.join_organization(character, organization_id)
	return false


func _strengthen_existing_ai_relationship(character: CharacterData) -> bool:
	var known: Array[RelationshipData] = relationships.get_for_character(character.id)
	if known.is_empty():
		return false
	known.sort_custom(func(a: RelationshipData, b: RelationshipData) -> bool:
		return a.id < b.id
	)
	var relationship: RelationshipData = known[0]
	var other_id: String = (
		relationship.character_b_id
		if relationship.character_a_id == character.id
		else relationship.character_a_id
	)
	return relationships.create_or_update(
		character.id, other_id, _current_hour(),
		{"familiarity": 0.02, "trust": 0.01, "affinity": 0.005}, "ai_contact"
	) != null


func _first_enemy_frontier_unit(country_id: String) -> String:
	if _map_service == null:
		return ""
	for unit_id: String in _map_service.get_sorted_unit_ids():
		var unit: ControlUnitData = _map_service.get_unit(unit_id)
		if unit.controller_country_id == country_id:
			continue
		for neighbor_id: String in unit.neighbor_ids:
			var neighbor: ControlUnitData = _map_service.get_unit(neighbor_id)
			if neighbor != null and neighbor.controller_country_id == country_id:
				return unit.id
	return ""


func _current_hour() -> int:
	return 0 if _clock == null else _clock.total_hours
