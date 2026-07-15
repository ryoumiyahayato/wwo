class_name SocietySimulationService
extends RefCounted
## Composition root for roster, organizations, relationships, actions and bounded AI.

const DOMAIN_ACTION_CATEGORIES: Array[String] = [
	"build_relationship",
	"join_organization",
	"seek_position",
	"investigate_character",
	"promote_policy",
	"support_control",
]
const STARTER_LEADER_ORGANIZATION_IDS: Array[String] = [
	"organization:loran_government",
	"organization:vesta_government",
	"organization:loran_military",
	"organization:vesta_military",
	"organization:loran_enterprise",
	"organization:vesta_enterprise",
	"organization:loran_union",
	"organization:vesta_union",
]

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
	_action_service = ActionService.new(
		_action_rules, GameSessionService.action_id_service
	)
	roster = CharacterRosterService.new(data_set, _character_config, rules)
	if not roster.initialize_background_population() or not roster.register_player(player):
		initialization_error = "无法建立分层人物名册"
		return false
	organizations = OrganizationService.new(data_set.organizations)
	relationships = RelationshipService.new(
		roster, rules.relationship_defaults, StableIdService.new()
	)
	_initialize_player_social_anchors(player)
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
	simulation_clock: SimulationClock, control_service: MapControlService
) -> void:
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


func create_player_relationship(
	other_character_id: String, current_hour: int
) -> RelationshipData:
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
	return apply_character_action_domain_effect(
		action,
		definition,
		GameSessionService.player_character,
		map_service,
		"player_contact"
	)


func apply_character_action_domain_effect(
	action: ActionInstanceData,
	definition: ActionDefinitionData,
	character: CharacterData,
	map_service: MapControlService,
	relationship_link: String = "ai_contact"
) -> bool:
	if (
		action == null
		or definition == null
		or character == null
		or action.status != ActionInstanceData.STATUS_COMPLETED
		or action.domain_effect_applied
	):
		return false
	var applied: bool = false
	var requires_domain: bool = definition.category in DOMAIN_ACTION_CATEGORIES
	if action.outcome_code != "failure":
		match definition.category:
			"perform_work":
				applied = _apply_work_relationship_opportunity(
					character, action.completion_hour
				)
			"build_relationship":
				applied = relationships.create_or_update(
					character.id,
					action.target_id,
					action.completion_hour,
					{"familiarity": 0.08, "trust": 0.02, "affinity": 0.01},
					relationship_link
				) != null
			"join_organization":
				applied = organizations.join_organization(
					character, action.target_id
				)
			"seek_position":
				applied = _award_next_position(character, action.target_id)
			"investigate_character":
				applied = _apply_investigation_dossier(
					character, action.target_id
				)
			_:
				applied = regional_influence.apply_action_domain_effect(
					action, definition, character, map_service
				)
	if requires_domain and action.outcome_code != "failure" and not applied:
		_action_service.replace_completed_result(
			action, definition, character, "failure"
		)
		action.result_description = _domain_failure_description(
			definition.category
		)
	action.domain_effect_applied = true
	action.applied_effects["domain_applied"] = applied
	if applied:
		GameSessionService.settlement_log.add(
			"action_domain",
			"行动领域结果已应用",
			action.completion_hour,
			{
				"action_id": action.id,
				"actor_id": character.id,
				"category": definition.category,
				"target_id": action.target_id,
			}
		)
	return applied


func _initialize_player_social_anchors(player: CharacterData) -> void:
	if player == null:
		return
	var candidates: Array[Dictionary] = []
	for character_id: String in roster.get_background_ids(player.country_id):
		var target: BackgroundCharacterData = roster.get_background(character_id)
		if target == null:
			continue
		var score: int = 0
		if target.region_id == player.region_id:
			score += 100
		if target.occupation_id == player.occupation_id:
			score += 80
		candidates.append({"id": character_id, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (
			str(a["id"]) < str(b["id"])
			if int(a["score"]) == int(b["score"])
			else int(a["score"]) > int(b["score"])
		)
	)
	for index: int in range(mini(candidates.size(), 2)):
		var target_id: String = str(candidates[index]["id"])
		var target: BackgroundCharacterData = roster.get_background(target_id)
		var link: String = (
			"coworker"
			if target.occupation_id == player.occupation_id
			else "neighbor"
		)
		relationships.create_or_update(
			player.id,
			target_id,
			0,
			{"familiarity": 0.04, "trust": 0.01, "affinity": 0.01},
			link
		)


func _apply_work_relationship_opportunity(
	character: CharacterData, current_hour: int
) -> bool:
	var candidates: Array[Dictionary] = []
	for character_id: String in roster.get_living_ids(character.country_id):
		if character_id == character.id:
			continue
		var target: Variant = roster.get_public_character(character_id)
		if not (target is CharacterData or target is BackgroundCharacterData):
			continue
		var score: int = 0
		if str(target.occupation_id) == character.occupation_id:
			score += 100
		if str(target.region_id) == character.region_id:
			score += 60
		if relationships.get_between(character.id, character_id) != null:
			score += 20
		candidates.append({"id": character_id, "score": score})
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (
			str(a["id"]) < str(b["id"])
			if int(a["score"]) == int(b["score"])
			else int(a["score"]) > int(b["score"])
		)
	)
	return relationships.create_or_update(
		character.id,
		str(candidates[0]["id"]),
		current_hour,
		{"familiarity": 0.03, "trust": 0.01, "affinity": 0.0},
		"coworker"
	) != null


func _apply_investigation_dossier(
	investigator: CharacterData, target_id: String
) -> bool:
	var target: Variant = roster.get_public_character(target_id)
	if target == null or roster.get_exited(target_id) != null:
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
		var stored_tendencies: Variant = background.persistent_core.get(
			"tendencies", {}
		)
		if stored_tendencies is Dictionary and not (
			stored_tendencies as Dictionary
		).is_empty():
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
	var raw_dossiers: Variant = investigator.current_status.get(
		"investigation_dossiers", {}
	)
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
	investigator.current_status["investigation_dossiers"] = dossiers
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


func _award_next_position(
	character: CharacterData, organization_id: String
) -> bool:
	var next_position_id: String = _get_next_position_id(
		character.id, organization_id
	)
	return (
		not next_position_id.is_empty()
		and organizations.assign_position(
			character, organization_id, next_position_id
		)
	)


func _get_next_position_id(
	character_id: String, organization_id: String
) -> String:
	var organization: OrganizationData = organizations.get_organization(
		organization_id
	)
	if organization == null or not organization.member_ids.has(character_id):
		return ""
	var positions: Dictionary = organization.position_structure.get(
		"positions", {}
	) as Dictionary
	var current_id: String = organizations.get_position_id(
		character_id, organization_id
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


func execute_player_succession(
	successor_character_id: String,
	exit_reason: String,
	current_hour: int
) -> SuccessionResult:
	var old_player_id: String = roster.player_character_id
	var old_player: CharacterData = roster.get_active(old_player_id)
	var previous_action: ActionInstanceData = GameSessionService.current_action
	var result: SuccessionResult = succession.execute_succession(
		old_player_id, successor_character_id, exit_reason, current_hour
	)
	if (
		result.successor != null
		and previous_action != null
		and not previous_action.is_terminal()
	):
		previous_action.status = ActionInstanceData.STATUS_CANCELLED
		previous_action.estimated_completion_hour = -1
		previous_action.last_update_hour = maxi(
			previous_action.last_update_hour, current_hour
		)
		GameSessionService.archive_action(previous_action, old_player)
	return result


func _initialize_organization_leaders() -> void:
	var initialized: int = 0
	var ordered_ids: Array[String] = []
	for organization_id: String in STARTER_LEADER_ORGANIZATION_IDS:
		if organizations.get_organization(organization_id) != null:
			ordered_ids.append(organization_id)
	for organization_id: String in organizations.get_organization_ids():
		if not ordered_ids.has(organization_id):
			ordered_ids.append(organization_id)
	for organization_id: String in ordered_ids:
		if initialized >= rules.initial_active_npc_count:
			break
		var organization: OrganizationData = organizations.get_organization(
			organization_id
		)
		var character: CharacterData = _promote_organization_candidate(
			organization
		)
		if character == null:
			continue
		if not organization.member_ids.has(character.id) and not organizations.join_organization(
			character, organization_id
		):
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
	if action == null or player == null:
		return
	if action.is_terminal():
		_settle_current_action_domain_if_ready()
		return
	var definition: ActionDefinitionData = _data_set.actions.get(
		action.definition_id
	) as ActionDefinitionData
	if definition == null or action.actor_character_id != player.id:
		_action_service.interrupt_action(
			action, total_hour, "invalid_actor_or_definition"
		)
		GameSessionService.archive_current_action(player)
		return
	var context_service := PlayerActionContextService.new(
		_action_rules, self, _map_service
	)
	var target_error: String = context_service.get_target_validation_error(
		definition, player, action.target_id
	)
	if not target_error.is_empty():
		_action_service.interrupt_action(
			action,
			total_hour,
			"authoritative_target_invalid:%s" % target_error
		)
		GameSessionService.archive_current_action(player)
		return
	var authoritative_context: Dictionary = (
		context_service.build_authoritative_context_for_action(
			definition, player, action
		)
	)
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		authoritative_context.get("position_permissions", [])
	)
	if (
		not definition.position_permission_required.is_empty()
		and not permissions.has(definition.position_permission_required)
	):
		_action_service.interrupt_action(
			action, total_hour, "authoritative_permission_lost"
		)
		GameSessionService.archive_current_action(player)
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
			GameSessionService.archive_current_action(player)
			return
	_action_service.update_to_hour(
		action, definition, player, total_hour, _map_service
	)
	_settle_current_action_domain_if_ready()


func _settle_current_action_domain_if_ready() -> void:
	var action: ActionInstanceData = GameSessionService.current_action
	if action == null:
		return
	if action.status != ActionInstanceData.STATUS_COMPLETED:
		if action.is_terminal():
			GameSessionService.archive_current_action(
				GameSessionService.player_character
			)
		return
	if _map_service == null:
		return
	var definition: ActionDefinitionData = _data_set.actions.get(
		action.definition_id
	) as ActionDefinitionData
	if definition == null:
		action.domain_effect_applied = true
	elif not action.domain_effect_applied:
		apply_action_domain_effect(action, definition, _map_service)
	GameSessionService.archive_current_action(GameSessionService.player_character)


func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	if paused_settlement_categories.has("daily_ai"):
		return
	var started: int = Time.get_ticks_usec()
	ai.run_daily_decisions(_current_hour())
	var applied: int = _execute_ai_daily_actions()
	GameSessionService.performance_stats.record(
		"daily_ai", Time.get_ticks_usec() - started
	)
	if applied > 0:
		GameSessionService.settlement_log.add(
			"daily_ai",
			"活跃 NPC 推进或开始了 %d 项行动" % applied,
			_current_hour()
		)


func _on_month_advanced(_year: int, month: int) -> void:
	if paused_settlement_categories.has("monthly_ai"):
		return
	var started: int = Time.get_ticks_usec()
	var organization_income: int = _apply_monthly_organization_income()
	var lifecycle_exits: int = 0
	if month == 1:
		lifecycle_exits = _run_annual_lifecycle()
	_fill_vacant_leadership()
	ai.run_long_term_evaluations(_current_hour(), true)
	var world_changes: int = _execute_ai_monthly_world_actions()
	GameSessionService.performance_stats.record(
		"monthly_ai", Time.get_ticks_usec() - started
	)
	GameSessionService.settlement_log.add(
		"monthly_ai",
		"月度组织经济与长期计划结算完成",
		_current_hour(),
		{
			"active_ai": ai.states.size(),
			"organization_income": organization_income,
			"lifecycle_exits": lifecycle_exits,
			"world_changes": world_changes,
		}
	)


func _execute_ai_daily_actions() -> int:
	var changed: int = 0
	var current_hour: int = _current_hour()
	var context_service := PlayerActionContextService.new(
		_action_rules, self, _map_service
	)
	for character_id: String in ai.get_ai_character_ids():
		var character: CharacterData = roster.get_active(character_id)
		var state: AiStateData = ai.get_state(character_id)
		if character == null or state == null:
			continue
		if not state.current_action_record.is_empty():
			if _advance_ai_action(
				character, state, context_service, current_hour
			):
				changed += 1
		if not state.current_action_record.is_empty():
			continue
		if _start_ai_action_from_candidates(
			character, state, context_service, current_hour
		):
			changed += 1
	return changed


func _advance_ai_action(
	character: CharacterData,
	state: AiStateData,
	context_service: PlayerActionContextService,
	current_hour: int
) -> bool:
	var action := ActionInstanceData.from_dict(state.current_action_record)
	var definition: ActionDefinitionData = _data_set.actions.get(
		action.definition_id
	) as ActionDefinitionData
	if definition == null or action.actor_character_id != character.id:
		state.current_action_record = {}
		state.current_action_id = ""
		state.last_action_result = "invalid_action_record"
		return true
	var target_error: String = context_service.get_target_validation_error(
		definition, character, action.target_id
	)
	if not target_error.is_empty():
		_action_service.interrupt_action(
			action,
			current_hour,
			"authoritative_target_invalid:%s" % target_error
		)
	else:
		var authoritative_context: Dictionary = (
			context_service.build_authoritative_context_for_action(
				definition, character, action
			)
		)
		if authoritative_context != action.context:
			if not _action_service.update_context(
				action,
				definition,
				character,
				action.last_update_hour,
				authoritative_context,
				_map_service
			):
				_action_service.interrupt_action(
					action, current_hour, "authoritative_context_invalid"
				)
		if not action.is_terminal():
			_action_service.update_to_hour(
				action,
				definition,
				character,
				current_hour,
				_map_service
			)
	if action.status == ActionInstanceData.STATUS_COMPLETED:
		apply_character_action_domain_effect(
			action, definition, character, _map_service, "ai_contact"
		)
		state.last_action_result = "%s:%s" % [
			action.definition_id, action.outcome_code
		]
		state.current_action_record = {}
		state.current_action_id = ""
		return true
	if action.is_terminal():
		state.last_action_result = "%s:%s" % [
			action.definition_id, action.status
		]
		state.current_action_record = {}
		state.current_action_id = ""
		return true
	state.current_action_record = action.to_dict()
	state.current_action_id = action.definition_id
	return true


func _start_ai_action_from_candidates(
	character: CharacterData,
	state: AiStateData,
	context_service: PlayerActionContextService,
	current_hour: int
) -> bool:
	for candidate: Dictionary in state.candidate_actions:
		var action_id: String = str(candidate.get("action_id", ""))
		if action_id == "rest":
			_apply_ai_rest(character, state)
			return true
		var definition: ActionDefinitionData = _data_set.actions.get(
			action_id
		) as ActionDefinitionData
		if definition == null:
			continue
		var target_id: String = _pick_ai_action_target(
			definition, character
		)
		if _action_requires_target(definition.category) and target_id.is_empty():
			continue
		var result: ActionStartResult = context_service.start_player_action(
			_action_service,
			definition,
			character,
			current_hour,
			target_id,
			0
		)
		if not result.is_success():
			continue
		state.current_action_id = definition.id
		state.current_action_record = result.action.to_dict()
		state.last_action_result = "started:%s" % definition.id
		return true
	_apply_ai_rest(character, state)
	return true


func _apply_ai_rest(character: CharacterData, state: AiStateData) -> void:
	character.current_status["fatigue"] = maxi(
		int(character.current_status.get("fatigue", 0))
		- int(rules.ai_rules.get("rest_fatigue_recovery", 12)),
		0
	)
	character.current_status["stress"] = maxi(
		int(character.current_status.get("stress", 0))
		- int(rules.ai_rules.get("rest_stress_recovery", 8)),
		0
	)
	state.current_action_id = "rest"
	state.last_action_result = "rested"


func _pick_ai_action_target(
	definition: ActionDefinitionData, character: CharacterData
) -> String:
	match definition.category:
		"build_relationship", "investigate_character":
			return _pick_relationship_target(character)
		"join_organization":
			return _pick_organization_target(character)
		"seek_position":
			return _pick_position_target(character)
		_:
			return ""


func _pick_relationship_target(character: CharacterData) -> String:
	var candidates: Array[Dictionary] = []
	var scan_limit: int = maxi(
		int(rules.ai_rules.get("relationship_target_scan_limit", 24)), 1
	)
	var scanned: int = 0
	for target_id: String in roster.get_living_ids(character.country_id):
		if target_id == character.id:
			continue
		scanned += 1
		if scanned > scan_limit:
			break
		var target: Variant = roster.get_public_character(target_id)
		if target == null:
			continue
		var score: float = 0.0
		if str(target.region_id) == character.region_id:
			score += 30.0
		if _characters_share_organization(character.id, target_id):
			score += 20.0
		var existing: RelationshipData = relationships.get_between(
			character.id, target_id
		)
		if existing == null:
			score += 25.0
		else:
			score += (1.0 - existing.familiarity) * 10.0
		score += float(target.current_status.get("reputation", 0)) * 0.05
		candidates.append({"id": target_id, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score: float = float(a["score"])
		var b_score: float = float(b["score"])
		return str(a["id"]) < str(b["id"]) if is_equal_approx(a_score, b_score) else a_score > b_score
	)
	return "" if candidates.is_empty() else str(candidates[0]["id"])


func _pick_organization_target(character: CharacterData) -> String:
	var candidates: Array[Dictionary] = []
	for organization_id: String in organizations.get_organization_ids():
		var organization: OrganizationData = organizations.get_organization(
			organization_id
		)
		if (
			organization == null
			or organization.country_id != character.country_id
			or organization.member_ids.has(character.id)
			or not _organization_entry_available(organization)
		):
			continue
		var score: float = organization.influence * 20.0
		if organization.region_id == character.region_id:
			score += 18.0
		score += _occupation_organization_bonus(
			character.occupation_id, organization.type
		)
		candidates.append({"id": organization_id, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score: float = float(a["score"])
		var b_score: float = float(b["score"])
		return str(a["id"]) < str(b["id"]) if is_equal_approx(a_score, b_score) else a_score > b_score
	)
	return "" if candidates.is_empty() else str(candidates[0]["id"])


func _pick_position_target(character: CharacterData) -> String:
	var candidates: Array[String] = []
	for organization_id: String in character.organization_ids:
		if not _get_next_position_id(character.id, organization_id).is_empty():
			candidates.append(organization_id)
	candidates.sort()
	return "" if candidates.is_empty() else candidates[0]


func _execute_ai_monthly_world_actions() -> int:
	if _map_service == null:
		return 0
	var applied: int = 0
	for character_id: String in ai.get_ai_character_ids():
		var character: CharacterData = roster.get_active(character_id)
		if character == null:
			continue
		for organization_id: String in character.organization_ids:
			var organization: OrganizationData = organizations.get_organization(
				organization_id
			)
			if organization == null:
				continue
			if organizations.has_permission(
				character.id, organization.id, "regional_policy"
			):
				if regional_influence.apply_organization_social_support(
					organization,
					character.id,
					organization.region_id,
					0.12,
					organizations,
					_map_service
				):
					applied += 1
			if organizations.has_permission(
				character.id,
				organization.id,
				"regional_control_support"
			):
				var target_id: String = _first_enemy_frontier_unit(
					organization.country_id
				)
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


func _apply_monthly_organization_income() -> int:
	var changed: int = 0
	var economy: Dictionary = rules.organization_economy
	var resource_cap: float = float(economy.get("resource_cap", 160.0))
	for organization_id: String in organizations.get_organization_ids():
		var organization: OrganizationData = organizations.get_organization(
			organization_id
		)
		var income: float = (
			float(economy.get("monthly_base_income", 0.0))
			+ organization.size
			* float(economy.get("size_income_scale", 0.0))
			+ organization.influence
			* float(economy.get("influence_income_scale", 0.0))
		)
		var old_resources: float = organization.resources
		organization.resources = minf(
			organization.resources + maxf(income, 0.0), resource_cap
		)
		if not is_equal_approx(old_resources, organization.resources):
			changed += 1
	return changed


func _run_annual_lifecycle() -> int:
	roster.increment_living_ages()
	var exited_count: int = 0
	var lifecycle: Dictionary = rules.lifecycle_rules
	var maximum_age: int = int(lifecycle.get("maximum_age", 90))
	var retirement_age: int = int(lifecycle.get("retirement_age", 65))
	var background_exit_age: int = int(
		lifecycle.get("background_exit_age", 85)
	)
	for character_id: String in roster.get_active_ids():
		var character: CharacterData = roster.get_active(character_id)
		_apply_annual_health_decline(character.current_status, character.age)
		if character_id == roster.player_character_id:
			if (
				character.age >= retirement_age
				or int(character.current_status.get("health", 0)) <= 0
			):
				character.current_status["succession_required"] = true
				character.current_status["succession_reason"] = (
					"death"
					if character.age >= maximum_age or int(character.current_status.get("health", 0)) <= 0
					else "retirement"
				)
			continue
		var reason: String = ""
		if character.age >= maximum_age or int(
			character.current_status.get("health", 0)
		) <= 0:
			reason = "death"
		elif character.age >= retirement_age:
			reason = "retirement"
		if not reason.is_empty() and _exit_active_npc(
			character, reason
		):
			exited_count += 1
	for character_id: String in roster.get_background_ids():
		var background: BackgroundCharacterData = roster.get_background(
			character_id
		)
		_apply_annual_health_decline(
			background.current_status, background.age
		)
		var reason: String = ""
		if background.age >= maximum_age or int(
			background.current_status.get("health", 0)
		) <= 0:
			reason = "death"
		elif background.age >= background_exit_age:
			reason = "retirement"
		if reason.is_empty():
			continue
		var exited: ExitedCharacterRecord = roster.exit_background_character(
			character_id, reason, _current_hour()
		)
		if exited == null:
			continue
		for organization_id: String in exited.character.organization_ids.duplicate():
			organizations.leave_organization(
				exited.character, organization_id
			)
		exited_count += 1
	return exited_count


func _apply_annual_health_decline(status: Dictionary, age: int) -> void:
	var lifecycle: Dictionary = rules.lifecycle_rules
	var start_age: int = int(
		lifecycle.get("health_decline_start_age", 55)
	)
	if age < start_age:
		return
	var decline: int = int(lifecycle.get("annual_health_decline", 1))
	if age >= int(lifecycle.get("old_age_start", 70)):
		decline += int(lifecycle.get("old_age_additional_decline", 3))
	status["health"] = maxi(
		int(status.get("health", 80)) - maxi(decline, 0), 0
	)


func _exit_active_npc(character: CharacterData, reason: String) -> bool:
	if character == null or character.id == roster.player_character_id:
		return false
	for organization_id: String in character.organization_ids.duplicate():
		organizations.leave_organization(character, organization_id)
	ai.unregister(character.id)
	return roster.exit_active_character(
		character.id, reason, _current_hour()
	) != null


func _fill_vacant_leadership() -> int:
	var filled: int = 0
	for organization_id: String in organizations.get_organization_ids():
		var organization: OrganizationData = organizations.get_organization(
			organization_id
		)
		if organization == null or not organization.leader_character_id.is_empty():
			continue
		var candidate: CharacterData = _best_active_leader_candidate(
			organization
		)
		if candidate == null:
			candidate = _promote_organization_candidate(organization)
		if candidate == null:
			continue
		if not organization.member_ids.has(candidate.id) and not organizations.join_organization(
			candidate, organization.id
		):
			continue
		var leader_position: String = str(
			organization.position_structure.get("leader_position", "")
		)
		if organizations.assign_position(
			candidate, organization.id, leader_position
		):
			ai.register_active_npc(candidate.id)
			filled += 1
	return filled


func _best_active_leader_candidate(
	organization: OrganizationData
) -> CharacterData:
	var candidates: Array[Dictionary] = []
	for member_id: String in organization.member_ids:
		if member_id == roster.player_character_id:
			continue
		var character: CharacterData = roster.get_active(member_id)
		if character == null:
			continue
		var score: float = float(
			character.current_status.get("reputation", 0)
		)
		score += float(character.skills.get("administration", 0)) * 0.3
		score += float(character.skills.get("political_activity", 0)) * 0.2
		if organization.type == "military":
			score += float(character.skills.get("military_command", 0)) * 0.5
		candidates.append({"character": character, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score: float = float(a["score"])
		var b_score: float = float(b["score"])
		var a_character: CharacterData = a["character"] as CharacterData
		var b_character: CharacterData = b["character"] as CharacterData
		return a_character.id < b_character.id if is_equal_approx(a_score, b_score) else a_score > b_score
	)
	return null if candidates.is_empty() else candidates[0]["character"] as CharacterData


func _promote_organization_candidate(
	organization: OrganizationData
) -> CharacterData:
	var preferred_ids: Array[String] = []
	var fallback_ids: Array[String] = []
	for character_id: String in roster.get_background_ids(
		organization.country_id
	):
		var background: BackgroundCharacterData = roster.get_background(
			character_id
		)
		if background.region_id == organization.region_id:
			preferred_ids.append(character_id)
		else:
			fallback_ids.append(character_id)
	var candidate_ids: Array[String] = preferred_ids
	candidate_ids.append_array(fallback_ids)
	for character_id: String in candidate_ids:
		var character: CharacterData = roster.promote(character_id)
		if character != null:
			return character
	return null


func _organization_entry_available(
	organization: OrganizationData
) -> bool:
	return (
		organization != null
		and organizations.has_entry_vacancy(organization.id)
	)


func _occupation_organization_bonus(
	occupation_id: String, organization_type: String
) -> float:
	var organization_match: Dictionary = _action_rules.player_context_rules.get(
		"organization_match_bonus", {}
	) as Dictionary
	var preferred_by_occupation: Dictionary = organization_match.get(
		"preferred_types_by_occupation", {}
	) as Dictionary
	var preferred_types: Array[String] = DataRecordUtils.to_string_array(
		preferred_by_occupation.get(occupation_id, [])
	)
	return (
		30.0
		if preferred_types.has(organization_type)
		else 0.0
	)


func _characters_share_organization(
	first_id: String, second_id: String
) -> bool:
	var first: Variant = roster.get_public_character(first_id)
	var second: Variant = roster.get_public_character(second_id)
	if first == null or second == null:
		return false
	var first_ids: Array[String] = DataRecordUtils.to_string_array(
		first.organization_ids
	)
	for organization_id: String in DataRecordUtils.to_string_array(
		second.organization_ids
	):
		if first_ids.has(organization_id):
			return true
	return false


func _action_requires_target(category: String) -> bool:
	return category in DOMAIN_ACTION_CATEGORIES


func _first_enemy_frontier_unit(country_id: String) -> String:
	if _map_service == null:
		return ""
	for unit_id: String in _map_service.get_sorted_unit_ids():
		var unit: ControlUnitData = _map_service.get_unit(unit_id)
		if (
			unit.controller_country_id != country_id
			and _map_service.is_valid_control_support_target(
				unit.id, country_id
			)
		):
			return unit.id
	return ""


func _current_hour() -> int:
	return 0 if _clock == null else _clock.total_hours
