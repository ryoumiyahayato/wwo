class_name AlphaSimulationService
extends V23LifeLoopSimulation
## Alpha composition root retaining the V2.3 clock, schedule, space and cognition.

const ALPHA_SCHEMA_VERSION: String = "prototype_0_001_alpha_1"
const DEFAULT_PRESET_ID: String = "preset:employed_worker"
const DEFAULT_REVIEW_STATE_ID: String = "employed_worker"
const CORE_WORLD_PATH: String = "res://data/world/demo_world.json"
const HIGH_DETAIL_LIMIT: int = 20
const REVIEW_STATE_PRESETS: Dictionary = {
	"employed_worker": "preset:employed_worker",
	"indebted_low_income": "preset:indebted_laborer",
	"leveraged_enterprise": "preset:leveraged_owner",
	"enterprise_near_bankruptcy": "preset:distressed_owner",
	"isolated_professional": "preset:isolated_professional",
	"weak_owner_strong_partner": "preset:partner_supported",
	"local_official": "preset:local_official",
	"business_owner_in_politics": "preset:leveraged_owner",
	"policy_changed_region": "preset:local_official",
	"interregional_trade_and_migration": "preset:employed_worker",
	"world_after_three_years": "preset:employed_worker",
}

var alpha_config := AlphaConfig.new()
var core_data: CoreDataSet
var world := AlphaWorldService.new()
var organization_service: OrganizationService
var economy := AlphaEconomyService.new()
var labor := AlphaLaborService.new()
var enterprise := AlphaEnterpriseService.new()
var character_service := AlphaCharacterService.new()
var politics := AlphaPoliticsService.new()
var alpha_ai := AlphaAiService.new()
var world_dynamics := AlphaWorldDynamicsService.new()
var roster: CharacterRosterService
var generation_config: CharacterGenerationConfig
var society_rules: SocietyRulesConfig

var launch_preset_id: String = DEFAULT_PRESET_ID
var launch_review_state_id: String = DEFAULT_REVIEW_STATE_ID
var alpha_events: Array[Dictionary] = []
var current_intent: Dictionary = {}
var detailed_enterprise_ids: Array[String] = []
var alpha_initialization_error: String = ""
var alpha_last_hour_usec: int = 0
var alpha_maximum_hour_usec: int = 0
var alpha_hours_processed: int = 0
var _last_legacy_cash: Dictionary = {}


func initialize(simulation_clock: SimulationClock = null) -> bool:
	v2_3_config = AlphaV23Config.new()
	if not super.initialize(simulation_clock):
		return false
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		CORE_WORLD_PATH
	)
	if not loaded.is_success():
		return _fail_alpha("核心世界数据无法加载：%s" % "; ".join(loaded.errors))
	core_data = loaded.data_set
	if alpha_config.load_all() != OK:
		return _fail_alpha("Alpha 配置无法加载：%s" % "; ".join(alpha_config.errors))
	if not world.configure(core_data, alpha_config):
		return _fail_alpha(world.initialization_error)
	generation_config = CharacterGenerationConfig.load_from_file()
	if not generation_config.is_valid():
		return _fail_alpha(generation_config.error_message)
	society_rules = SocietyRulesConfig.new()
	if society_rules.load_from_file() != OK:
		return _fail_alpha(society_rules.error_message)
	organization_service = OrganizationService.new(core_data.organizations)
	if not economy.configure(alpha_config):
		return _fail_alpha("统一经济服务初始化失败")
	if not labor.configure(alpha_config, economy):
		return _fail_alpha("劳动服务初始化失败")
	if not enterprise.configure(
		alpha_config, economy, labor, organization_service, clock.total_hours
	):
		return _fail_alpha("企业服务初始化失败")
	if not character_service.configure(
		core_data, generation_config, alpha_config, economy, labor
	):
		return _fail_alpha("人物服务初始化失败")
	if not politics.configure(
		alpha_config, organization_service, economy, world
	):
		return _fail_alpha("组织政治服务初始化失败")
	roster = CharacterRosterService.new(
		core_data, generation_config, society_rules
	)
	if not roster.initialize_background_population():
		return _fail_alpha("背景人物初始化失败")
	if not _initialize_high_detail_people():
		return false
	if not alpha_ai.configure(
		labor, economy, enterprise, politics, organization_service,
		character_service
	):
		return _fail_alpha("AI 服务初始化失败")
	if not world_dynamics.configure(
		world, economy, enterprise, politics, roster, alpha_config
	):
		return _fail_alpha("世界动态服务初始化失败")
	alpha_events.clear()
	current_intent = {
		"intent_id": "intent:observe_world",
		"label": "观察当前处境",
		"highlight_object_ids": [roster.player_character_id],
		"deadline_ids": [],
		"risk_ids": [],
		"filter": "all",
	}
	detailed_enterprise_ids.clear()
	alpha_initialization_error = ""
	alpha_last_hour_usec = 0
	alpha_maximum_hour_usec = 0
	alpha_hours_processed = 0
	_capture_legacy_cash()
	selected_person_id = roster.player_character_id
	var review_result: Dictionary = apply_review_state(
		launch_review_state_id
	)
	if not bool(review_result.get("success", false)):
		return _fail_alpha(
			"人工检查预设无法建立：%s" % str(
				review_result.get(
					"message", review_result.get("code", "unknown")
				)
			)
		)
	state_changed.emit({"alpha_initialized": true, "schema": ALPHA_SCHEMA_VERSION})
	return true


func set_launch_preset(preset_id: String) -> bool:
	if initialized:
		return false
	if alpha_config.documents.is_empty() and alpha_config.load_all() != OK:
		return false
	if alpha_config.get_preset(preset_id).is_empty():
		return false
	launch_preset_id = preset_id
	return true


func set_launch_review_state(review_state_id: String) -> bool:
	if initialized or not REVIEW_STATE_PRESETS.has(review_state_id):
		return false
	launch_review_state_id = review_state_id
	launch_preset_id = str(REVIEW_STATE_PRESETS[review_state_id])
	return true


func apply_review_state(review_state_id: String) -> Dictionary:
	if not initialized or not REVIEW_STATE_PRESETS.has(review_state_id):
		return _result(
			false, "review_state_missing",
			{"review_state_id": review_state_id}
		)
	var result: Dictionary
	match review_state_id:
		"employed_worker", "isolated_professional":
			result = _result(true, "ok", {})
		"indebted_low_income":
			result = _result(
				economy.total_debt(roster.player_character_id) > 0,
				"indebted_state_missing",
				{}
			)
		"leveraged_enterprise":
			result = _prepare_leveraged_enterprise(false)
		"enterprise_near_bankruptcy":
			result = _prepare_distressed_takeover()
		"weak_owner_strong_partner":
			result = _prepare_partner_enterprise()
		"local_official":
			result = _prepare_local_official()
		"business_owner_in_politics":
			result = _prepare_business_owner_in_politics()
		"policy_changed_region":
			result = _prepare_completed_policy()
		"interregional_trade_and_migration":
			result = _prepare_interregional_trade_and_migration()
		"world_after_three_years":
			advance_hours(3 * 365 * 24)
			result = _result(true, "ok", {
				"elapsed_hours": 3 * 365 * 24,
			})
		_:
			result = _result(false, "review_state_missing", {})
	if bool(result.get("success", false)):
		launch_review_state_id = review_state_id
		set_current_intent(
			"intent:review:%s" % review_state_id,
			"检查预设：%s" % review_state_id,
			_review_highlights(review_state_id),
			"all"
		)
		_append_alpha_event({
			"event_id": "event:review_state:%s:%d" % [
				review_state_id, clock.total_hours,
			],
			"total_hour": clock.total_hours,
			"actor_id": roster.player_character_id,
			"fact_type": "review_state_loaded",
			"summary": "人工检查预设已通过正式服务建立：%s" % review_state_id,
			"requires_decision": false,
		})
	return result


func player_character() -> CharacterData:
	return null if roster == null else roster.get_active(roster.player_character_id)


func set_current_intent(
	intent_id: String,
	label: String,
	highlight_object_ids: Array = [],
	filter: String = "all"
) -> bool:
	if intent_id.is_empty() or label.is_empty():
		return false
	current_intent = {
		"intent_id": intent_id,
		"label": label,
		"highlight_object_ids": DataRecordUtils.to_string_array(
			highlight_object_ids
		),
		"deadline_ids": _current_deadline_ids(),
		"risk_ids": _current_risk_ids(),
		"filter": filter,
	}
	state_changed.emit({"current_intent": true})
	return true


func promote_for_contact(character_id: String, reason: String) -> bool:
	if roster == null or roster.active_characters.size() >= HIGH_DETAIL_LIMIT:
		return false
	var promoted: CharacterData = roster.promote(character_id)
	if promoted == null:
		return false
	_register_formal_character(promoted, 2500)
	_append_alpha_event({
		"event_id": "event:precision_up:%s:%d" % [character_id, clock.total_hours],
		"total_hour": clock.total_hours,
		"actor_id": character_id,
		"fact_type": "precision_upgrade",
		"summary": "人物因%s进入高精度模拟，聚合历史保持不变。" % reason,
		"requires_decision": false,
	})
	return true


func demote_if_unrelated(character_id: String) -> bool:
	if (
		roster == null
		or character_id == roster.player_character_id
		or _is_character_protected_from_demotion(character_id)
	):
		return false
	var background: BackgroundCharacterData = roster.demote(character_id)
	if background == null:
		return false
	if not world_dynamics.background_states.has(character_id):
		world_dynamics.background_states[character_id] = {
			"person_id": character_id,
			"region_id": background.region_id,
			"employed": not background.occupation_id.is_empty(),
			"occupation_or_unemployed": background.occupation_id,
			"income_band": "middle",
			"wealth_band": "middle",
			"debt_band": "none",
			"organization_ids": background.organization_ids.duplicate(),
			"important_relationship_summary": background.relationship_ids.slice(0, 3),
			"current_major_state": "stable",
			"migration_tendency": "low",
			"migration_cooldown": 0,
			"important_matters": [],
		}
	return true


func mark_enterprise_detailed(organization_id: String, detailed: bool) -> bool:
	if not enterprise.enterprises.has(organization_id):
		return false
	if detailed and organization_id not in detailed_enterprise_ids:
		detailed_enterprise_ids.append(organization_id)
		detailed_enterprise_ids.sort()
	elif not detailed:
		detailed_enterprise_ids.erase(organization_id)
	return true


func alpha_counts() -> Dictionary:
	var counts: Dictionary = world.counts()
	counts["active_people"] = (
		roster.active_characters.size() if roster != null else 0
	)
	counts["background_people"] = (
		roster.background_characters.size() if roster != null else 0
	)
	counts["enterprises"] = enterprise.enterprises.size()
	counts["organizations"] = (
		organization_service.organizations.size()
		if organization_service != null else 0
	)
	counts["contracts"] = economy.contracts.contracts.size()
	counts["debts"] = _loan_count()
	counts["unfinished_matters"] = _unfinished_matter_count()
	counts["event_history"] = (
		alpha_events.size() + world_dynamics.events.size()
	)
	return counts


func validate_alpha_integrity() -> Dictionary:
	if roster == null or roster.active_characters.size() > HIGH_DETAIL_LIMIT:
		return _result(false, "active_character_limit", {})
	for result: Dictionary in [
		economy.validate_integrity(),
		enterprise.validate_integrity(),
		politics.validate_integrity(),
	]:
		if not bool(result.get("success", false)):
			return result
	if world_dynamics.background_states.size() != roster.background_characters.size():
		return _result(false, "background_index_mismatch", {})
	var action_ids: Dictionary = {}
	for plan: Dictionary in character_service.development_plans.values():
		var activity_id: String = str(plan.get("schedule_activity_id", ""))
		if not activity_id.is_empty():
			if action_ids.has(activity_id):
				return _result(false, "duplicate_action_id", {})
			action_ids[activity_id] = true
	return _result(true, "ok", alpha_counts())


func get_alpha_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["schema_version"] = ALPHA_SCHEMA_VERSION
	state["alpha_world_id"] = str(alpha_config.world().get("world_id", ""))
	state["alpha_preset_id"] = launch_preset_id
	state["alpha_review_state_id"] = launch_review_state_id
	state["alpha_world_state"] = world.get_persistent_state()
	state["alpha_roster_state"] = roster.get_persistent_state()
	state["alpha_organization_state"] = organization_service.get_persistent_state()
	state["alpha_economy_state"] = economy.get_persistent_state()
	state["alpha_labor_state"] = labor.get_persistent_state()
	state["alpha_enterprise_state"] = enterprise.get_persistent_state()
	state["alpha_character_state"] = character_service.get_persistent_state()
	state["alpha_politics_state"] = politics.get_persistent_state()
	state["alpha_ai_state"] = alpha_ai.get_persistent_state()
	state["alpha_world_dynamics_state"] = world_dynamics.get_persistent_state()
	state["alpha_events"] = alpha_events.duplicate(true)
	state["current_intent"] = current_intent.duplicate(true)
	state["detailed_enterprise_ids"] = detailed_enterprise_ids.duplicate()
	state["alpha_hours_processed"] = alpha_hours_processed
	state["alpha_maximum_hour_usec"] = alpha_maximum_hour_usec
	state["legacy_cash_projection"] = _last_legacy_cash.duplicate(true)
	return state


func restore_alpha_state(state: Dictionary) -> V2LifeLoopResult:
	var validation: Dictionary = validate_alpha_snapshot_structure(state)
	if not bool(validation.get("success", false)):
		return V2LifeLoopResult.fail(
			str(validation.get("code", "invalid_alpha_save")),
			"Alpha 存档结构或引用无效"
		)
	var previous: Dictionary = get_alpha_persistent_state()
	if not _apply_alpha_state(state):
		if not _apply_alpha_state(previous):
			push_error("Alpha restore rollback failed")
		return V2LifeLoopResult.fail(
			"restore_failed", "Alpha 存档载入失败，当前运行状态已回滚"
		)
	state_changed.emit({"loaded": true, "alpha": true})
	return V2LifeLoopResult.ok("Alpha 存档已载入")


func validate_alpha_snapshot_structure(state: Dictionary) -> Dictionary:
	if str(state.get("schema_version", "")) != ALPHA_SCHEMA_VERSION:
		return _result(false, "incompatible_version", {})
	for field: String in [
		"alpha_world_state",
		"alpha_roster_state",
		"alpha_economy_state",
		"alpha_labor_state",
		"alpha_enterprise_state",
		"alpha_character_state",
		"alpha_politics_state",
		"alpha_ai_state",
		"alpha_world_dynamics_state",
		"current_intent",
	]:
		if not state.get(field, {}) is Dictionary:
			return _result(false, "invalid_field:%s" % field, {})
	for field: String in [
		"alpha_organization_state", "alpha_events", "detailed_enterprise_ids",
	]:
		if not state.get(field, []) is Array:
			return _result(false, "invalid_field:%s" % field, {})
	return _result(true, "ok", {})


func _settle_hour(total_hour: int) -> void:
	var started_usec: int = Time.get_ticks_usec()
	var legacy_before: Dictionary = _legacy_cash_snapshot()
	super._settle_hour(total_hour)
	_reconcile_legacy_cash(legacy_before, total_hour)
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if int(value.get("hour", -1)) == 23:
		_process_active_ai(total_hour)
		world_dynamics.process_boundaries(
			total_hour, roster.active_characters
		)
		_settle_due_development(total_hour)
	alpha_hours_processed += 1
	alpha_last_hour_usec = Time.get_ticks_usec() - started_usec
	alpha_maximum_hour_usec = maxi(
		alpha_maximum_hour_usec, alpha_last_hour_usec
	)


func _initialize_high_detail_people() -> bool:
	var preset_result: Dictionary = character_service.create_from_preset(
		launch_preset_id
	)
	if not bool(preset_result.get("success", false)):
		return _fail_alpha("玩家预设初始化失败：%s" % str(
			preset_result.get("message", "")
		))
	var player: CharacterData = (
		preset_result.get("data", {}) as Dictionary
	).get("character") as CharacterData
	if player == null or not roster.register_active_character(player, true):
		return _fail_alpha("玩家人物无法进入高精度层")
	var person_index: int = 0
	for person: Dictionary in alpha_config.people:
		var person_id: String = str(person.get("person_id", ""))
		if person_id == player.id:
			continue
		var category: String = _category_for_role(str(person.get("role", "")))
		var created: Dictionary = character_service.create_character(
			str(person.get("country_id", "")),
			str(person.get("region_id", "")),
			str(person.get("city_id", "")),
			"category_random",
			category,
			1000 + person_index,
			{},
			person_id
		)
		if not bool(created.get("success", false)):
			return _fail_alpha("高精度人物生成失败：%s" % person_id)
		var character: CharacterData = (
			created.get("data", {}) as Dictionary
		).get("character") as CharacterData
		character.name = str(person.get("display_name_zh", character.name))
		character.age = int(person.get("age", character.age))
		character.organization_ids.clear()
		if not _register_formal_character(character, 3600 + person_index * 240):
			return _fail_alpha("高精度人物登记失败：%s" % person_id)
		if not roster.register_active_character(character, false):
			return _fail_alpha("高精度人物超过上限：%s" % person_id)
		for organization_id: String in DataRecordUtils.to_string_array(
			person.get("organization_ids", [])
		):
			politics.join_organization(
				"initial:join:%s:%s" % [person_id, organization_id],
				character,
				organization_id,
				clock.total_hours
			)
		person_index += 1
	_register_initial_employment(player)
	return roster.active_characters.size() == alpha_config.people.size()


func _register_formal_character(
	character: CharacterData, opening_cash: int
) -> bool:
	if not economy.entity_profiles.has(character.id):
		var registered: Dictionary = economy.register_entity(
			character.id,
			"person",
			opening_cash,
			{
				"income_monthly_centimes": 2200,
				"reputation": int(character.current_status.get("reputation", 50)),
				"region_id": character.region_id,
				"qualifications": character.qualifications,
			}
		)
		if not bool(registered.get("success", false)):
			return false
	if not labor.person_profiles.has(character.id):
		if not labor.register_person(character.id, {
			"country_id": character.country_id,
			"region_id": character.region_id,
			"city_id": character.current_status.get("city_id", ""),
			"skills": character.skills,
			"qualifications": character.qualifications,
			"experience": character.domain_experience,
			"health": character.current_status.get("health", 80),
			"fatigue": character.current_status.get("fatigue", 0),
			"stress": character.current_status.get("stress", 0),
			"occupation_id": character.occupation_id,
			"opening_cash_centimes": opening_cash,
			"income_monthly_centimes": 2200,
		}):
			return false
	return true


func _register_initial_employment(player: CharacterData) -> void:
	if launch_preset_id != "preset:employed_worker":
		return
	var hired: Dictionary = labor.direct_hire(
		"initial:employment:%s" % player.id,
		player.id,
		"job:market_clerk",
		clock.total_hours
	)
	if not bool(hired.get("success", false)):
		_append_alpha_event({
			"event_id": "event:initial_job_rejected",
			"total_hour": clock.total_hours,
			"actor_id": player.id,
			"fact_type": "employment_decision",
			"summary": "预设人物的既有工作未能通过正式雇佣判断。",
			"requires_decision": true,
		})


func _prepare_leveraged_enterprise(
	distressed: bool, key_suffix: String = "leveraged"
) -> Dictionary:
	var player: CharacterData = player_character()
	var key: String = "review:%s" % key_suffix
	var created: Dictionary = enterprise.create_enterprise(
		"%s:create" % key,
		player.id,
		"远程商路经营社",
		"retail_trade",
		player.region_id,
		str(player.current_status.get("city_id", "city:dawnharbor")),
		"household_goods",
		"grain",
		mini(3000, economy.ledger.owner_cash(player.id)),
		clock.total_hours
	)
	if not bool(created.get("success", false)):
		return created
	var state: Dictionary = (
		created.get("data", {}) as Dictionary
	).get("enterprise", {}) as Dictionary
	var organization_id: String = str(state.get("organization_id", ""))
	var borrowed: Dictionary = enterprise.borrow_for_operations(
		"%s:borrow" % key,
		organization_id,
		_lender_for_country(player.country_id),
		6500,
		clock.total_hours,
		state.get("asset_ids", []) as Array
	)
	if not bool(borrowed.get("success", false)):
		return borrowed
	if distressed:
		var current: Dictionary = enterprise.enterprises[
			organization_id
		] as Dictionary
		current["distress"] = 86
		current["status"] = "distressed"
		current["current_risks"] = ["cash_shortage", "debt_due"]
		enterprise.enterprises[organization_id] = current
	mark_enterprise_detailed(organization_id, true)
	return _result(true, "ok", {"enterprise_id": organization_id})


func _prepare_distressed_takeover() -> Dictionary:
	var organization_id: String = "organization:vesta_redhill_industry"
	var state: Dictionary = enterprise.enterprises.get(
		organization_id, {}
	) as Dictionary
	var equity_id: String = str(state.get("equity_asset_id", ""))
	var seller_id: String = str(state.get("controller_id", ""))
	var value: int = economy.assets.value(equity_id)
	var purchased: Dictionary = enterprise.purchase_enterprise_share(
		"review:distressed:purchase",
		organization_id,
		seller_id,
		roster.player_character_id,
		5100,
		maxi(1, value * 51 / 100),
		clock.total_hours
	)
	if not bool(purchased.get("success", false)):
		return purchased
	mark_enterprise_detailed(organization_id, true)
	return _result(true, "ok", {"enterprise_id": organization_id})


func _prepare_partner_enterprise() -> Dictionary:
	var player: CharacterData = player_character()
	var created: Dictionary = enterprise.create_enterprise(
		"review:partner:create",
		player.id,
		"河脊共同商社",
		"information_service",
		player.region_id,
		str(player.current_status.get("city_id", "city:ironford")),
		"investigation_service",
		"household_goods",
		mini(1800, economy.ledger.owner_cash(player.id)),
		clock.total_hours
	)
	if not bool(created.get("success", false)):
		return created
	var state: Dictionary = (
		created.get("data", {}) as Dictionary
	).get("enterprise", {}) as Dictionary
	var organization_id: String = str(state.get("organization_id", ""))
	var partnered: Dictionary = enterprise.establish_partnership(
		"review:partner:contract",
		organization_id,
		player.id,
		"character_lucien_moreau",
		1000,
		3000,
		clock.total_hours
	)
	if not bool(partnered.get("success", false)):
		return partnered
	mark_enterprise_detailed(organization_id, true)
	return _result(true, "ok", {"enterprise_id": organization_id})


func _prepare_local_official() -> Dictionary:
	var actor: CharacterData = player_character()
	var supporter: CharacterData = roster.get_active("character_albert_dumont")
	var organization_id: String = "organization:loran_commerce_registry"
	if organization_service.get_position_id(
		actor.id, organization_id
	) == "registrar":
		return _result(true, "ok", {"organization_id": organization_id})
	for pair: Array in [
		[actor, "actor"],
		[supporter, "supporter"],
	]:
		var character: CharacterData = pair[0] as CharacterData
		if character == null:
			return _result(false, "review_supporter_missing", {})
		var organization: OrganizationData = organization_service.get_organization(
			organization_id
		)
		if character.id not in organization.member_ids:
			var joined: Dictionary = politics.join_organization(
				"review:official:join:%s" % str(pair[1]),
				character,
				organization_id,
				clock.total_hours
			)
			if not bool(joined.get("success", false)):
				return joined
	actor.skills["political_activity"] = maxi(
		80, int(actor.skills.get("political_activity", 0))
	)
	actor.skills["public_speaking"] = maxi(
		78, int(actor.skills.get("public_speaking", 0))
	)
	var support: Dictionary = politics.campaign_for_support(
		"review:official:support",
		actor,
		supporter,
		organization_id,
		"issue:loran_license_reform",
		100
	)
	if not bool(support.get("success", false)):
		return support
	var contest: Dictionary = politics.contest_position(
		"review:official:contest",
		actor,
		organization_id,
		"registrar",
		clock.total_hours
	)
	if not bool(contest.get("success", false)):
		return contest
	if str((contest.get("data", {}) as Dictionary).get("result", "")) != "won":
		return _result(false, "review_position_not_won", {})
	return _result(true, "ok", {"organization_id": organization_id})


func _prepare_business_owner_in_politics() -> Dictionary:
	var enterprise_result: Dictionary = _prepare_leveraged_enterprise(
		false, "business_owner"
	)
	if not bool(enterprise_result.get("success", false)):
		return enterprise_result
	var player: CharacterData = player_character()
	var organization_id: String = (
		"organization:loran_civic_league"
		if player.country_id == "country:loran_federation"
		else "organization:vesta_industry_bloc"
	)
	var joined: Dictionary = politics.join_organization(
		"review:owner_politics:join",
		player,
		organization_id,
		clock.total_hours
	)
	if not bool(joined.get("success", false)):
		return joined
	return _result(true, "ok", {
		"enterprise_id": (
			enterprise_result.get("data", {}) as Dictionary
		).get("enterprise_id", ""),
		"organization_id": organization_id,
	})


func _prepare_completed_policy() -> Dictionary:
	var official: Dictionary = _prepare_local_official()
	if not bool(official.get("success", false)):
		return official
	var actor: CharacterData = player_character()
	var organization_id: String = str(
		(official.get("data", {}) as Dictionary).get("organization_id", "")
	)
	var proposed: Dictionary = politics.propose_policy(
		"review:policy:propose",
		actor,
		organization_id,
		"policy:loran_wage_floor",
		["region:loran_dawnbay", "region:loran_riverback"],
		clock.total_hours
	)
	if not bool(proposed.get("success", false)):
		return proposed
	var implementation_id: String = str(
		((proposed.get("data", {}) as Dictionary).get(
			"implementation", {}
		) as Dictionary).get("implementation_id", "")
	)
	var funded: Dictionary = politics.fund_and_start_policy(
		"review:policy:fund",
		implementation_id,
		clock.total_hours
	)
	if not bool(funded.get("success", false)):
		return funded
	var advanced: Dictionary = politics.advance_policy(
		"review:policy:advance",
		implementation_id,
		clock.total_hours,
		12
	)
	if not bool(advanced.get("success", false)):
		return advanced
	return _result(true, "ok", {"implementation_id": implementation_id})


func _prepare_interregional_trade_and_migration() -> Dictionary:
	var player: CharacterData = player_character()
	var trade: Dictionary = economy.create_trade(
		"review:migration:trade",
		player.id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		"grain",
		1,
		"region:loran_southridge",
		"region:vesta_silverfield",
		clock.total_hours,
		3
	)
	if not bool(trade.get("success", false)):
		return trade
	var contract_id: String = str(
		((trade.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	var settled: Dictionary = economy.settle_trade(
		"review:migration:settle",
		contract_id,
		clock.total_hours + 3 * 24
	)
	if not bool(settled.get("success", false)):
		return settled
	var migrated: Dictionary = labor.migrate(
		"review:migration:move",
		player.id,
		"country:vesta_union",
		"region:vesta_silverfield",
		"city:starhold",
		"organization:vesta_enterprise",
		160,
		clock.total_hours
	)
	if not bool(migrated.get("success", false)):
		return migrated
	var profile: Dictionary = labor.person_profiles[player.id] as Dictionary
	for raw_contract_id: Variant in (
		profile.get("employment_contract_ids", []) as Array
	).duplicate():
		var employment_id: String = str(raw_contract_id)
		var employment: Dictionary = labor.employment_states.get(
			employment_id, {}
		) as Dictionary
		if str(employment.get("status", "")) in (
			AlphaLaborService.ACTIVE_EMPLOYMENT_STATUSES
		):
			var resigned: Dictionary = labor.resign(
				"review:migration:resign:%s" % employment_id,
				employment_id,
				clock.total_hours
			)
			if not bool(resigned.get("success", false)):
				return resigned
	var hired: Dictionary = labor.direct_hire(
		"review:migration:hire",
		player.id,
		"job:trade_agent",
		clock.total_hours
	)
	if not bool(hired.get("success", false)):
		return hired
	player.country_id = "country:vesta_union"
	player.region_id = "region:vesta_silverfield"
	player.current_status["city_id"] = "city:starhold"
	var migration: Dictionary = (
		migrated.get("data", {}) as Dictionary
	).get("migration", {}) as Dictionary
	return _result(true, "ok", {
		"contract_id": contract_id,
		"migration_id": migration.get("migration_id", ""),
	})


func _review_highlights(review_state_id: String) -> Array[String]:
	var highlights: Array[String] = [roster.player_character_id]
	match review_state_id:
		"enterprise_near_bankruptcy":
			highlights.append("organization:vesta_redhill_industry")
		"local_official", "policy_changed_region":
			highlights.append("organization:loran_commerce_registry")
		"interregional_trade_and_migration":
			highlights.append("region:vesta_silverfield")
	return highlights


static func _lender_for_country(country_id: String) -> String:
	return (
		"organization:loran_public_credit"
		if country_id == "country:loran_federation"
		else "organization:vesta_public_credit"
	)


func _process_active_ai(total_hour: int) -> void:
	for character_id: String in roster.get_active_ids(false):
		var character: CharacterData = roster.get_active(character_id)
		if character == null:
			continue
		var known: Dictionary = _known_ai_snapshot(character)
		var decision: Dictionary = alpha_ai.process_person_day(
			character, known, total_hour
		)
		if bool(decision.get("success", false)):
			var data: Dictionary = decision.get("data", {}) as Dictionary
			var record: Dictionary = data.get("decision", {}) as Dictionary
			if not record.is_empty() and not bool(
				data.get("duplicate", false)
			):
				_append_alpha_event({
					"event_id": "event:%s" % str(record.get("decision_id", "")),
					"total_hour": total_hour,
					"actor_id": character.id,
					"fact_type": "ai_action",
					"summary": "%s采取了%s；依据：%s" % [
						character.name,
						str(record.get("action_id", "")),
						str(record.get("reason", "")),
					],
					"requires_decision": false,
				})


func _settle_due_development(total_hour: int) -> void:
	var plan_ids: Array[String] = []
	for raw_plan_id: Variant in character_service.development_plans:
		plan_ids.append(str(raw_plan_id))
	plan_ids.sort()
	for plan_id: String in plan_ids:
		var plan: Dictionary = character_service.development_plans[
			plan_id
		] as Dictionary
		if (
			str(plan.get("status", "")) not in ["scheduled", "in_progress"]
			or int(plan.get("end_hour", total_hour + 1)) > total_hour
		):
			continue
		var character: CharacterData = roster.get_active(
			str(plan.get("person_id", ""))
		)
		if character == null:
			continue
		var remaining: int = (
			int(plan.get("planned_hours", 0))
			- int(plan.get("completed_hours", 0))
		)
		if remaining > 0:
			character_service.settle_development(
				"world:development:%s" % plan_id,
				character,
				plan_id,
				total_hour,
				remaining
			)


func _known_ai_snapshot(character: CharacterData) -> Dictionary:
	var profile: Dictionary = labor.person_profiles.get(
		character.id, {}
	) as Dictionary
	var employment_id: String = ""
	for raw_id: Variant in profile.get("employment_contract_ids", []) as Array:
		var contract_id: String = str(raw_id)
		var state: Dictionary = labor.employment_states.get(
			contract_id, {}
		) as Dictionary
		if str(state.get("status", "")) in AlphaLaborService.ACTIVE_EMPLOYMENT_STATUSES:
			employment_id = contract_id
			break
	var cash: int = economy.ledger.owner_cash(character.id)
	var debt: int = economy.total_debt(character.id)
	var best_job: Dictionary = {}
	for job: Dictionary in labor.discover_jobs(character.id, true):
		var qualification: String = str(job.get("qualification", ""))
		if not qualification.is_empty() and qualification not in character.qualifications:
			continue
		if (
			best_job.is_empty()
			or int(job.get("wage", 0)) > int(best_job.get("wage", 0))
		):
			best_job = job
	var repayable_id: String = ""
	for contract: Dictionary in economy.contracts.contracts_for_party(
		character.id, false
	):
		if str(contract.get("contract_type", "")) == "loan":
			repayable_id = str(contract.get("contract_id", ""))
			break
	var joinable_id: String = ""
	for organization_id: String in organization_service.get_organization_ids():
		var organization: OrganizationData = organization_service.get_organization(
			organization_id
		)
		if (
			organization.country_id == character.country_id
			and organization.type in ["union", "political", "professional"]
			and character.id not in organization.member_ids
		):
			joinable_id = organization_id
			break
	var controlled_enterprise_id: String = ""
	var controlled_enterprise_risk: String = "stable"
	var enterprise_has_partner: bool = false
	for raw_enterprise_id: Variant in enterprise.enterprises:
		var enterprise_id: String = str(raw_enterprise_id)
		var enterprise_state: Dictionary = enterprise.enterprises[
			enterprise_id
		] as Dictionary
		if str(enterprise_state.get("controller_id", "")) != character.id:
			continue
		controlled_enterprise_id = enterprise_id
		var distress: int = int(enterprise_state.get("distress", 0))
		controlled_enterprise_risk = (
			"critical" if distress >= 90
			else "elevated" if distress >= 65
			else "stable"
		)
		for contract_id: String in DataRecordUtils.to_string_array(
			enterprise_state.get("contract_ids", [])
		):
			var contract: Dictionary = economy.contracts.contracts.get(
				contract_id, {}
			) as Dictionary
			if (
				str(contract.get("contract_type", "")) == "partnership"
				and str(contract.get("status", "")) not in [
					"terminated", "defaulted", "fulfilled",
				]
			):
				enterprise_has_partner = true
				break
		break
	var known_partner: CharacterData
	for other_id: String in roster.get_active_ids(false):
		if other_id != character.id:
			known_partner = roster.get_active(other_id)
			break
	var contest_organization_id: String = ""
	var contest_position_id: String = ""
	var known_supporter: CharacterData
	var policy_organization_id: String = ""
	for organization_id: String in character.organization_ids:
		var member_organization: OrganizationData = (
			organization_service.get_organization(organization_id)
		)
		if member_organization == null:
			continue
		var position_id: String = organization_service.get_position_id(
			character.id, organization_id
		)
		var entry_id: String = str(
			member_organization.position_structure.get("entry_position", "")
		)
		var leader_id: String = str(
			member_organization.position_structure.get("leader_position", "")
		)
		if (
			contest_organization_id.is_empty()
			and member_organization.type in ["political", "government"]
			and position_id != leader_id
		):
			for member_id: String in member_organization.member_ids:
				var candidate: CharacterData = roster.get_active(member_id)
				if member_id != character.id and candidate != null:
					known_supporter = candidate
					break
			if known_supporter != null:
				contest_organization_id = organization_id
				contest_position_id = leader_id
		if (
			policy_organization_id.is_empty()
			and member_organization.type == "government"
			and position_id != entry_id
		):
			policy_organization_id = organization_id
	var known_issue_id: String = ""
	for issue: Dictionary in politics.issues.values():
		if str(issue.get("country_id", "")) == character.country_id:
			known_issue_id = str(issue.get("issue_id", ""))
			break
	var known_policy_id: String = ""
	for policy: Dictionary in politics.policies.values():
		if str(policy.get("country_id", "")) == character.country_id:
			known_policy_id = str(policy.get("policy_id", ""))
			break
	var active_development_plan: bool = false
	for plan_id: String in DataRecordUtils.to_string_array(
		character.current_status.get("development_plan_ids", [])
	):
		var plan: Dictionary = character_service.development_plans.get(
			plan_id, {}
		) as Dictionary
		if str(plan.get("status", "")) in ["scheduled", "in_progress"]:
			active_development_plan = true
			break
	var target_city: String = str(best_job.get("city_id", ""))
	var target_city_record: Dictionary = _city_for_id(target_city)
	return {
		"employed": not employment_id.is_empty(),
		"employment_status": "employed" if not employment_id.is_empty() else "unemployed",
		"employment_contract_id": employment_id,
		"cash_band": "critical" if cash < 400 else "low" if cash < 1400 else "stable",
		"debt_band": "high" if debt > 7000 else "moderate" if debt > 0 else "none",
		"known_jobs": [best_job] if not best_job.is_empty() else [],
		"best_known_job_id": str(best_job.get("job_id", "")),
		"labor_demand_index": 58,
		"can_migrate_for_work": (
			not best_job.is_empty()
			and target_city != str(profile.get("city_id", ""))
		),
		"known_routes": ["public_intercity_timetable"],
		"target_city_id": target_city,
		"target_region_id": str(target_city_record.get("region_id", "")),
		"target_country_id": str(target_city_record.get("country_id", "")),
		"migration_cost_centimes": 120,
		"known_lenders": [
			"organization:loran_public_credit",
			"organization:vesta_public_credit",
		],
		"known_lender_id": (
			"organization:loran_public_credit"
			if character.country_id == "country:loran_federation"
			else "organization:vesta_public_credit"
		),
		"requested_credit_centimes": 1800,
		"disclosed_debt_centimes": debt,
		"known_debts": [repayable_id] if not repayable_id.is_empty() else [],
		"repayable_contract_id": repayable_id,
		"repayable_amount_centimes": debt,
		"organization_ids": character.organization_ids.duplicate(),
		"known_organizations": [joinable_id] if not joinable_id.is_empty() else [],
		"joinable_organization_id": joinable_id,
		"current_agendas": character.current_agendas.duplicate(true),
		"known_business_opportunity": (
			controlled_enterprise_id.is_empty()
			and cash >= 1800
			and enterprise.enterprises.size() < 20
		),
		"business_structure": "retail_trade",
		"business_product_id": "household_goods",
		"business_input_id": "grain",
		"controlled_enterprise_id": controlled_enterprise_id,
		"controlled_enterprise_risk": controlled_enterprise_risk,
		"enterprise_has_partner": enterprise_has_partner,
		"known_partner_id": "" if known_partner == null else known_partner.id,
		"contest_organization_id": contest_organization_id,
		"contest_position_id": contest_position_id,
		"known_supporter_id": (
			"" if known_supporter == null else known_supporter.id
		),
		"known_supporter_character": known_supporter,
		"known_issue_id": known_issue_id,
		"policy_organization_id": policy_organization_id,
		"known_policy_id": known_policy_id,
		"policy_region_id": character.region_id,
		"active_development_plan": active_development_plan,
		"development_skill_id": (
			"finance"
			if int(character.skills.get("finance", 0)) < 60
			else "public_speaking"
		),
		"known_development_method": "independent_study",
		"development_location_id": str(character.current_status.get(
			"home_location_id", "location:dawnharbor:home"
		)),
	}


func _city_for_id(city_id: String) -> Dictionary:
	for raw_city: Variant in alpha_config.cities():
		var city: Dictionary = raw_city as Dictionary
		if str(city.get("city_id", "")) == city_id:
			return city
	return {}


func _reconcile_legacy_cash(before: Dictionary, total_hour: int) -> void:
	for person_id: String in [PIERRE_ID, ALBERT_ID]:
		if not economy.entity_profiles.has(person_id):
			continue
		var previous: int = int(before.get(person_id, 0))
		var current: int = int(_legacy_cash_snapshot().get(person_id, previous))
		var delta: int = current - previous
		if delta == 0:
			continue
		var person_account: String = economy.ledger.cash_account_id(person_id)
		var entries: Array = []
		if delta > 0:
			entries = [
				{
					"account_id": AlphaLedgerService.SYSTEM_OPENING_ACCOUNT,
					"delta_centimes": -delta,
				},
				{"account_id": person_account, "delta_centimes": delta},
			]
		else:
			entries = [
				{"account_id": person_account, "delta_centimes": delta},
				{
					"account_id": AlphaLedgerService.SYSTEM_OPENING_ACCOUNT,
					"delta_centimes": -delta,
				},
			]
		var posted: Dictionary = economy.ledger.post(
			"legacy_projection:%s:%d" % [person_id, total_hour],
			total_hour,
			"legacy_life_projection",
			"fact:legacy_life:%s:%d" % [person_id, total_hour],
			entries,
			"旧生活服务产生的正式现金变化接入 Alpha 账本"
		)
		if not bool(posted.get("success", false)):
			_append_alpha_event({
				"event_id": "event:legacy_cash_unfunded:%s:%d" % [
					person_id, total_hour,
				],
				"total_hour": total_hour,
				"actor_id": person_id,
				"fact_type": "cash_shortage",
				"summary": "既有生活安排产生支出，但 Alpha 正式现金不足。",
				"requires_decision": person_id == roster.player_character_id,
			})
	_capture_legacy_cash()


func _legacy_cash_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for person_id: String in [PIERRE_ID, ALBERT_ID]:
		snapshot[person_id] = int(
			households.household_for_person(person_id).get("cash_centimes", 0)
		)
	return snapshot


func _capture_legacy_cash() -> void:
	_last_legacy_cash = _legacy_cash_snapshot()


func _apply_alpha_state(state: Dictionary) -> bool:
	var base_state: Dictionary = state.duplicate(true)
	base_state["schema_version"] = V2_3_SCHEMA_VERSION
	var base_result: V2LifeLoopResult = super.restore_v2_3_state(base_state)
	if not base_result.success:
		return false
	if not world.restore_persistent_state(
		state["alpha_world_state"] as Dictionary
	):
		return _restore_domain_failed("world")
	if not roster.restore_persistent_state(
		state["alpha_roster_state"] as Dictionary
	):
		return _restore_domain_failed("roster")
	if not organization_service.restore_persistent_state(
		state["alpha_organization_state"] as Array
	):
		return _restore_domain_failed("organizations")
	if not economy.restore_persistent_state(
		state["alpha_economy_state"] as Dictionary
	):
		return _restore_domain_failed("economy")
	if not labor.restore_persistent_state(
		state["alpha_labor_state"] as Dictionary
	):
		return _restore_domain_failed("labor")
	if not enterprise.restore_persistent_state(
		state["alpha_enterprise_state"] as Dictionary
	):
		return _restore_domain_failed("enterprise")
	if not character_service.restore_persistent_state(
		state["alpha_character_state"] as Dictionary
	):
		return _restore_domain_failed("characters")
	if not politics.restore_persistent_state(
		state["alpha_politics_state"] as Dictionary
	):
		return _restore_domain_failed("politics")
	if not alpha_ai.restore_persistent_state(
		state["alpha_ai_state"] as Dictionary
	):
		return _restore_domain_failed("ai")
	if not world_dynamics.restore_persistent_state(
		state["alpha_world_dynamics_state"] as Dictionary
	):
		return _restore_domain_failed("world_dynamics")
	alpha_events = DataRecordUtils.to_dictionary_array(state["alpha_events"])
	current_intent = (state["current_intent"] as Dictionary).duplicate(true)
	detailed_enterprise_ids = DataRecordUtils.to_string_array(
		state["detailed_enterprise_ids"]
	)
	launch_preset_id = str(state.get("alpha_preset_id", DEFAULT_PRESET_ID))
	launch_review_state_id = str(
		state.get("alpha_review_state_id", DEFAULT_REVIEW_STATE_ID)
	)
	alpha_hours_processed = int(state.get("alpha_hours_processed", 0))
	alpha_maximum_hour_usec = int(state.get("alpha_maximum_hour_usec", 0))
	_last_legacy_cash = (
		state.get("legacy_cash_projection", {}) as Dictionary
	).duplicate(true)
	return bool(validate_alpha_integrity().get("success", false))


func _restore_domain_failed(domain: String) -> bool:
	push_error("Alpha restore domain failed: %s" % domain)
	return false


func _append_alpha_event(event: Dictionary) -> void:
	alpha_events.append(event.duplicate(true))
	while alpha_events.size() > 512:
		alpha_events.pop_front()


func _is_character_protected_from_demotion(character_id: String) -> bool:
	if labor.person_profiles.has(character_id):
		var profile: Dictionary = labor.person_profiles[character_id] as Dictionary
		if not (profile.get("employment_contract_ids", []) as Array).is_empty():
			return true
	if not organization_service.get_character_permissions(character_id).is_empty():
		return true
	for state: Dictionary in enterprise.enterprises.values():
		if str(state.get("controller_id", "")) == character_id:
			return true
	return false


func _current_deadline_ids() -> Array[String]:
	var result: Array[String] = []
	for contract: Dictionary in economy.contracts.contracts.values():
		if str(contract.get("status", "")) not in [
			"fulfilled", "settled", "enforced", "terminated",
		]:
			result.append(str(contract.get("contract_id", "")))
			if result.size() >= 8:
				break
	return result


func _current_risk_ids() -> Array[String]:
	var result: Array[String] = []
	for state: Dictionary in enterprise.enterprises.values():
		if int(state.get("distress", 0)) >= 70:
			result.append(str(state.get("organization_id", "")))
	return result


func _loan_count() -> int:
	var count: int = 0
	for contract: Dictionary in economy.contracts.contracts.values():
		if str(contract.get("contract_type", "")) == "loan":
			count += 1
	return count


func _unfinished_matter_count() -> int:
	var count: int = 0
	for implementation: Dictionary in politics.policy_implementations.values():
		if str(implementation.get("status", "")) in ["authorized", "implementing"]:
			count += 1
	for contract: Dictionary in economy.contracts.contracts.values():
		if str(contract.get("status", "")) not in [
			"fulfilled", "settled", "enforced", "terminated",
		]:
			count += 1
	return count


func _category_for_role(role: String) -> String:
	if "官" in role or "行政" in role or "政治" in role:
		return "administrative"
	if "军" in role:
		return "military"
	if "工" in role or "装配" in role:
		return "industrial"
	if "顾问" in role or "记者" in role or "信贷" in role:
		return "professional"
	if "组织" in role:
		return "organization"
	return "commercial"


func _fail_alpha(message: String) -> bool:
	alpha_initialization_error = message
	initialization_error = message
	initialized = false
	return false


static func _result(success: bool, code: String, data: Dictionary) -> Dictionary:
	return {"success": success, "code": code, "message": "", "data": data}
