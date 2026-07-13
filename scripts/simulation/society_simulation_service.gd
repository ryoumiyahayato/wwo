class_name SocietySimulationService
extends RefCounted
## Composition root for roster, organizations, relationships, actions and bounded AI.

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
var _character_config: CharacterGenerationConfig
var _action_rules: ActionRulesConfig
var _action_service: ActionService


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
	_character_config = CharacterGenerationConfig.load_from_file()
	if not _character_config.is_valid():
		initialization_error = _character_config.error_message
		return false
	_action_rules = ActionRulesConfig.new()
	if _action_rules.load_from_file() != OK:
		initialization_error = _action_rules.error_message
		return false
	_action_service = ActionService.new(_action_rules, GameSessionService.action_id_service)
	roster = CharacterRosterService.new(data_set, _character_config, rules)
	if not roster.initialize_background_population() or not roster.register_player(player):
		initialization_error = "无法建立分层人物名册"
		return false
	organizations = OrganizationService.new(data_set.organizations)
	relationships = RelationshipService.new(roster, rules.relationship_defaults, StableIdService.new())
	ai = SimpleAiService.new(roster, rules)
	regional_influence = RegionalInfluenceService.new(continuity_rules)
	succession = SuccessionService.new(continuity_rules, roster, organizations, relationships, ai)
	_initialize_organization_leaders()
	ai.run_long_term_evaluations(0)
	ai.run_daily_decisions(0)
	return true


func attach_clock(simulation_clock: SimulationClock) -> void:
	attach_world(simulation_clock, _map_service)


func attach_world(simulation_clock: SimulationClock, control_service: MapControlService) -> void:
	if control_service != null:
		_map_service = control_service
	if simulation_clock == null:
		return
	if simulation_clock != _clock:
		_clock = simulation_clock
		if not _clock.hour_advanced.is_connected(_on_hour_advanced):
			_clock.hour_advanced.connect(_on_hour_advanced)
		if not _clock.day_advanced.is_connected(_on_day_advanced):
			_clock.day_advanced.connect(_on_day_advanced)
		if not _clock.month_advanced.is_connected(_on_month_advanced):
			_clock.month_advanced.connect(_on_month_advanced)
	_settle_current_action_domain_if_ready()


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


func create_player_relationship(other_character_id: String, current_hour: int) -> RelationshipData:
	return relationships.create_or_update(
		roster.player_character_id,
		other_character_id,
		current_hour,
		{"familiarity": 0.08, "trust": 0.02, "affinity": 0.01},
		"player_contact"
	)


func apply_action_domain_effect(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	map_service: MapControlService
) -> bool:
	if action == null or definition == null or action.status != ActionInstanceData.STATUS_COMPLETED or action.domain_effect_applied:
		return false
	var player: CharacterData = GameSessionService.player_character
	var applied: bool = false
	var requires_domain: bool = definition.category in [
		"build_relationship",
		"join_organization",
		"seek_position",
		"investigate_character",
		"promote_policy",
		"support_control",
	]
	if action.outcome_code != "failure" and player != null:
		match definition.category:
			"build_relationship":
				applied = create_player_relationship(action.target_id, action.completion_hour) != null
			"join_organization":
				applied = organizations.join_organization(player, action.target_id)
			"seek_position":
				applied = _award_next_position(player, action.target_id)
			"investigate_character":
				applied = _apply_investigation_dossier(player, action.target_id)
			_:
				applied = regional_influence.apply_action_domain_effect(
					action, definition, player, map_service
				)
	if requires_domain and action.outcome_code != "failure" and not applied and player != null:
		_action_service.replace_completed_result(action, definition, player, "failure")
		action.result_description = _domain_failure_description(definition.category)
	# Mark one-shot state only after a failed domain transaction has replaced the
	# generic success result, because replacement rebuilds applied_effects.
	action.domain_effect_applied = true
	action.applied_effects["domain_applied"] = applied
	if applied:
		GameSessionService.settlement_log.add(
			"action_domain",
			"行动领域结果已应用",
			action.completion_hour,
			{"action_id": action.id, "category": definition.category, "target_id": action.target_id}
		)
	return applied


func _apply_investigation_dossier(player: CharacterData, target_id: String) -> bool:
	var target: Variant = roster.get_public_character(target_id)
	if target == null:
		return false
	var tendencies: Dictionary = {}
	var name: String = ""
	var age: int = 0
	var occupation: String = ""
	var public_position: String = ""
	var region_id: String = ""
	var traits: Array[String] = []
	var organization_ids: Array[String] = []
	if target is CharacterData:
		var active: CharacterData = target as CharacterData
		name = active.name
		age = active.age
		occupation = active.occupation
		public_position = active.public_position
		region_id = active.region_id
		traits = active.manifested_traits.duplicate()
		organization_ids = active.organization_ids.duplicate()
		tendencies = active.tendencies.duplicate(true)
	elif target is BackgroundCharacterData:
		var background: BackgroundCharacterData = target as BackgroundCharacterData
		name = background.name
		age = background.age
		occupation = background.occupation
		public_position = background.public_position
		region_id = background.region_id
		traits = background.manifested_traits.duplicate()
		organization_ids = background.organization_ids.duplicate()
		var stored_tendencies: Variant = background.persistent_core.get("tendencies", {})
		if stored_tendencies is Dictionary and not (stored_tendencies as Dictionary).is_empty():
			tendencies = (stored_tendencies as Dictionary).duplicate(true)
		else:
			var generator := CharacterGenerator.new(
				_data_set,
				_character_config,
				DeterministicRandomService.new(background.activation_seed),
				StableIdService.new()
			)
			var generated: CharacterGenerationResult = generator.generate_character(
				background.country_id,
				CharacterGenerator.MODE_FULL_POPULATION
			)
			if generated.is_success():
				tendencies = generated.character.tendencies.duplicate(true)
	var raw_dossiers: Variant = player.current_status.get("investigation_dossiers", {})
	var dossiers: Dictionary = (
		(raw_dossiers as Dictionary).duplicate(true)
		if raw_dossiers is Dictionary
		else {}
	)
	dossiers[target_id] = {
		"name": name,
		"age": age,
		"occupation": occupation,
		"public_position": public_position,
		"region_id": region_id,
		"traits": traits,
		"organization_ids": organization_ids,
		"tendencies": tendencies,
		"investigated_hour": _current_hour(),
	}
	player.current_status["investigation_dossiers"] = dossiers
	return true


func _domain_failure_description(category: String) -> String:
	match category:
		"build_relationship":
			return "行动完成时目标已不可接触，未建立有效关系。"
		"join_organization":
			return "行动完成时组织入口职位不可用，未能加入组织。"
		"seek_position":
			return "行动过程完成，但结算时已无更高空缺职位。"
		"promote_policy":
			return "政策行动完成，但目标地区影响已达可调整边界。"
		"support_control":
			return "行动完成时目标已不再符合前线支援条件。"
		"investigate_character":
			return "调查目标已不可用，未形成有效档案。"
	return "行动完成，但权威领域状态未发生变化。"


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
	successor_character_id: String,
	exit_reason: String,
	current_hour: int
) -> SuccessionResult:
	var old_player_id: String = roster.player_character_id
	var previous_action: ActionInstanceData = GameSessionService.current_action
	var result: SuccessionResult = succession.execute_succession(
		old_player_id, successor_character_id, exit_reason, current_hour
	)
	if result.successor != null and previous_action != null and not previous_action.is_terminal():
		previous_action.status = ActionInstanceData.STATUS_CANCELLED
		previous_action.estimated_completion_hour = -1
	return result


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
		if not organizations.join_organization(character, organization_id):
			roster.demote(character.id)
			continue
		if not organizations.assign_position(
			character,
			organization_id,
			str(organization.position_structure.get("leader_position", ""))
		):
			organizations.leave_organization(character, organization_id)
			roster.demote(character.id)
			continue
		ai.register_active_npc(character.id)
		initialized += 1


func _on_hour_advanced(total_hour: int) -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	var player: CharacterData = GameSessionService.player_character
	if action == null or player == null or action.is_terminal():
		return
	var definition: ActionDefinitionData = _data_set.actions.get(action.definition_id) as ActionDefinitionData
	if definition == null or action.actor_character_id != player.id:
		_action_service.interrupt_action(action, total_hour, "invalid_actor_or_definition")
		return
	var context_service := PlayerActionContextService.new(
		_action_rules, self, _map_service
	)
	var target_error: String = context_service.get_target_validation_error(
		definition, player, action.target_id
	)
	if not target_error.is_empty():
		_action_service.interrupt_action(
			action, total_hour, "authoritative_target_invalid:%s" % target_error
		)
		return
	var authoritative_context: Dictionary = context_service.build_authoritative_context_for_action(
		definition, player, action
	)
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		authoritative_context.get("position_permissions", [])
	)
	if not definition.position_permission_required.is_empty() and not permissions.has(
		definition.position_permission_required
	):
		_action_service.interrupt_action(
			action, total_hour, "authoritative_permission_lost"
		)
		return
	if authoritative_context != action.context:
		if not _action_service.update_context(
			action,
			definition,
			player,
			action.last_update_hour,
			authoritative_context,
			_map_service
		):
			_action_service.interrupt_action(
				action, total_hour, "authoritative_context_invalid"
			)
			return
	_action_service.update_to_hour(action, definition, player, total_hour, _map_service)
	_settle_current_action_domain_if_ready()


func _settle_current_action_domain_if_ready() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null or action.status != ActionInstanceData.STATUS_COMPLETED or action.domain_effect_applied or _map_service == null:
		return
	var definition: ActionDefinitionData = _data_set.actions.get(action.definition_id) as ActionDefinitionData
	if definition == null:
		action.domain_effect_applied = true
		return
	apply_action_domain_effect(action, definition, _map_service)


func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	if paused_settlement_categories.has("daily_ai"):
		return
	var started: int = Time.get_ticks_usec()
	ai.run_daily_decisions(_current_hour())
	var applied: int = _execute_ai_daily_actions()
	GameSessionService.performance_stats.record("daily_ai", Time.get_ticks_usec() - started)
	if applied > 0:
		GameSessionService.settlement_log.add(
			"daily_ai",
			"活跃 NPC 执行了 %d 项日常行动" % applied,
			_current_hour()
		)


func _on_month_advanced(_year: int, _month: int) -> void:
	if paused_settlement_categories.has("monthly_ai"):
		return
	var started: int = Time.get_ticks_usec()
	ai.run_long_term_evaluations(_current_hour(), true)
	var world_changes: int = _execute_ai_monthly_world_actions()
	GameSessionService.performance_stats.record("monthly_ai", Time.get_ticks_usec() - started)
	GameSessionService.settlement_log.add(
		"monthly_ai",
		"月度长期计划结算完成",
		_current_hour(),
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
				character.current_status["fatigue"] = maxi(int(character.current_status.get("fatigue", 0)) - 8, 0)
				character.current_status["stress"] = maxi(int(character.current_status.get("stress", 0)) - 5, 0)
				applied += 1
			"action:perform_work":
				character.current_status["wealth"] = int(character.current_status.get("wealth", 0)) + 1
				character.current_status["fatigue"] = mini(int(character.current_status.get("fatigue", 0)) + 2, 100)
				applied += 1
			"action:study_skill":
				if state.daily_decision_count % 7 == 0:
					var skill_id: String = _lowest_skill_id(character)
					if not skill_id.is_empty():
						character.skills[skill_id] = mini(int(character.skills.get(skill_id, 0)) + 1, 100)
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
					organization,
					character.id,
					organization.region_id,
					0.12,
					organizations,
					_map_service
				):
					applied += 1
			if organizations.has_permission(character.id, organization.id, "regional_control_support"):
				var target_id: String = _first_enemy_frontier_unit(organization.country_id)
				if not target_id.is_empty() and regional_influence.apply_organization_control_support(
					organization,
					character.id,
					target_id,
					0.10,
					organizations,
					_map_service
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
	known.sort_custom(func(a: RelationshipData, b: RelationshipData) -> bool: return a.id < b.id)
	var relationship: RelationshipData = known[0]
	var other_id: String = relationship.character_b_id if relationship.character_a_id == character.id else relationship.character_a_id
	return relationships.create_or_update(
		character.id,
		other_id,
		_current_hour(),
		{"familiarity": 0.02, "trust": 0.01, "affinity": 0.005},
		"ai_contact"
	) != null


func _first_enemy_frontier_unit(country_id: String) -> String:
	if _map_service == null:
		return ""
	for unit_id: String in _map_service.get_sorted_unit_ids():
		var unit: ControlUnitData = _map_service.get_unit(unit_id)
		if unit.controller_country_id != country_id and _map_service.is_valid_control_support_target(unit.id, country_id):
			return unit.id
	return ""


func _current_hour() -> int:
	return 0 if _clock == null else _clock.total_hours
