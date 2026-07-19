class_name AlphaCharacterService
extends RefCounted
## Reuses CharacterData/Generator/Roster while adding Alpha careers, development and delegation.

const CREATION_MODES: Array[String] = [
	"standard_random",
	"category_random",
	"full_random",
	"custom_background",
]
const DEVELOPMENT_METHODS: Array[String] = [
	"independent_study",
	"mentor_guidance",
	"formal_course",
	"work_practice",
	"organization_practice",
	"self_training",
	"exam",
]
const CATEGORY_MAP: Dictionary = {
	"industrial": "industrial",
	"commercial": "industrial",
	"administrative": "political",
	"military": "military",
	"professional": "knowledge",
	"organization": "civilian",
	"civilian": "civilian",
}

var development_plans: Dictionary = {}
var authorizations: Dictionary = {}
var assessments: Array[Dictionary] = []
var _data_set: CoreDataSet
var _generation_config: CharacterGenerationConfig
var _alpha_config: AlphaConfig
var _economy: AlphaEconomyService
var _labor: AlphaLaborService
var _processed_keys: Dictionary = {}
var _next_plan_sequence: int = 1
var _next_authorization_sequence: int = 1


func configure(
	data_set: CoreDataSet,
	generation_config: CharacterGenerationConfig,
	alpha_config: AlphaConfig,
	economy: AlphaEconomyService,
	labor: AlphaLaborService
) -> bool:
	_data_set = data_set
	_generation_config = generation_config
	_alpha_config = alpha_config
	_economy = economy
	_labor = labor
	development_plans.clear()
	authorizations.clear()
	assessments.clear()
	_processed_keys.clear()
	_next_plan_sequence = 1
	_next_authorization_sequence = 1
	return (
		_data_set != null
		and _generation_config != null
		and _generation_config.is_valid()
		and _alpha_config != null
		and _alpha_config.errors.is_empty()
	)


func create_character(
	country_id: String,
	region_id: String,
	city_id: String,
	mode: String,
	category: String,
	seed_value: int,
	custom_background: Dictionary = {},
	requested_id: String = ""
) -> Dictionary:
	if (
		mode not in CREATION_MODES
		or not _data_set.countries.has(country_id)
		or not _data_set.regions.has(region_id)
		or (
			_data_set.regions[region_id] as RegionData
		).de_jure_country_id != country_id
		or _alpha_config.city_record(city_id).is_empty()
		or str(_alpha_config.city_record(city_id).get("country_id", "")) != country_id
	):
		return _fail("invalid_character_creation", "人物创建模式、国家、地区或城市无效")
	if mode == "category_random" and not CATEGORY_MAP.has(category):
		return _fail("invalid_character_category", "分类随机必须选择七类背景之一")
	var generator_mode: String = CharacterGenerator.MODE_STANDARD
	var generator_category: String = ""
	if mode in ["category_random", "custom_background"]:
		generator_mode = CharacterGenerator.MODE_CATEGORY
		generator_category = str(CATEGORY_MAP.get(category, "civilian"))
	var generator := CharacterGenerator.new(
		_data_set,
		_generation_config,
		DeterministicRandomService.new(seed_value),
		StableIdService.new()
	)
	var generated: CharacterGenerationResult = generator.generate_character(
		country_id, generator_mode, generator_category
	)
	if not generated.is_success():
		return _fail("character_generation_failed", "; ".join(generated.errors))
	var character: CharacterData = generated.character
	character.id = (
		requested_id
		if not requested_id.is_empty()
		else "character:alpha:%d" % seed_value
	)
	character.region_id = region_id
	character.current_status["city_id"] = city_id
	character.current_status["home_location_id"] = _alpha_config.city_location_id(
		city_id, "home"
	)
	character.current_status["qualification_bypass_history"] = []
	character.current_status["development_plan_ids"] = []
	if mode == "full_random":
		character.random_mode = "full_random"
	elif mode == "standard_random":
		character.random_mode = "standard_random"
	else:
		character.random_mode = mode
		character.random_category = category
	_apply_category_history(character, category)
	if mode == "custom_background":
		_apply_custom_background(character, custom_background)
	_ensure_alpha_person_fields(character, seed_value)
	return _ok({"character": character})


func create_from_preset(preset_id: String) -> Dictionary:
	var preset: Dictionary = _alpha_config.get_preset(preset_id)
	if preset.is_empty():
		return _fail("preset_missing", "人物预设不存在")
	var created: Dictionary = create_character(
		str(preset.get("country_id", "")),
		str(preset.get("region_id", "")),
		str(preset.get("city_id", "")),
		"category_random",
		str(preset.get("category", "civilian")),
		int(preset.get("seed", 1)),
		{},
		str(preset.get("person_id", "character_pierre_lefevre"))
	)
	if not bool(created.get("success", false)):
		return created
	var character: CharacterData = (created.get("data", {}) as Dictionary).get(
		"character"
	) as CharacterData
	character.occupation_id = str(preset.get("occupation_id", character.occupation_id))
	character.domain_experience = (
		preset.get("experience", character.domain_experience) as Dictionary
	).duplicate(true)
	character.qualifications = DataRecordUtils.to_string_array(
		preset.get("qualifications", character.qualifications)
	)
	if not _economy.entity_profiles.has(character.id):
		var registered: Dictionary = _economy.register_entity(
			character.id,
			"person",
			int(preset.get("cash", 0)),
			{
				"income_monthly_centimes": 0,
				"reputation": int(character.current_status.get("reputation", 50)),
				"region_id": character.region_id,
				"qualifications": character.qualifications,
			}
		)
		if not bool(registered.get("success", false)):
			return registered
	if not _labor.person_profiles.has(character.id):
		if not _labor.register_person(character.id, {
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
			"opening_cash_centimes": int(preset.get("cash", 0)),
		}):
			return _fail("labor_registration_failed", "人物劳动档案登记失败")
	var debt: int = int(preset.get("debt", 0))
	if debt > 0:
		var lender_id: String = (
			"organization:loran_public_credit"
			if character.country_id == "country:loran_federation"
			else "organization:vesta_public_credit"
		)
		var opening_debt: Dictionary = _economy.create_opening_debt(
			"preset_debt:%s:%s" % [preset_id, character.id],
			character.id,
			lender_id,
			debt,
			"credit:personal_unsecured",
			0
		)
		if not bool(opening_debt.get("success", false)):
			return opening_debt
	return _ok({"character": character, "preset": preset.duplicate(true)})


func assess_action(
	character: CharacterData,
	action_id: String,
	skill_id: String,
	domain_id: String,
	complexity: int,
	base_duration_hours: int,
	base_cost_centimes: int,
	required_qualification: String = "",
	professional_helper: CharacterData = null
) -> Dictionary:
	if (
		character == null
		or action_id.is_empty()
		or complexity < 0
		or base_duration_hours <= 0
		or base_cost_centimes < 0
	):
		return _fail("invalid_assessment", "行动评估对象或参数无效")
	var skill: int = int(character.skills.get(skill_id, 0))
	var experience: int = int(character.domain_experience.get(domain_id, 0))
	var reasoning: int = int(character.hidden_aptitudes.get("reasoning", 50))
	var learning: int = int(character.hidden_aptitudes.get("learning", 50))
	var self_control: int = int(
		character.hidden_aptitudes.get(
			"willpower",
			character.hidden_aptitudes.get("self_control", 50)
		)
	)
	var helper_effect: int = 0
	var dependence: String = "independent"
	if professional_helper != null:
		helper_effect = (
			int(professional_helper.skills.get(skill_id, 0))
			+ int(professional_helper.hidden_aptitudes.get("reasoning", 50))
		) / 3
		dependence = "professional_support"
	var method_reliability: int = clampi(
		skill * 55 / 100
		+ mini(25, experience / 4)
		+ reasoning * 20 / 100
		+ helper_effect
		- complexity / 2,
		5,
		100
	)
	var error_risk: int = clampi(
		100 - method_reliability + complexity / 3 - self_control / 10, 0, 95
	)
	var duration_overrun_bp: int = maxi(
		0, (complexity - skill) * 90 + (60 - learning) * 25
	)
	var cost_overrun_bp: int = maxi(
		0, (complexity - skill) * 70 + (55 - reasoning) * 20
	)
	var institutional_blocked: bool = (
		not required_qualification.is_empty()
		and required_qualification not in character.qualifications
	)
	var result: Dictionary = {
		"success": true,
		"code": "ok",
		"action_id": action_id,
		"can_attempt": not institutional_blocked,
		"institutionally_blocked": institutional_blocked,
		"unavailable_reason": (
			"该行为依法要求资格：%s" % required_qualification
			if institutional_blocked
			else ""
		),
		"bypass_methods": (
			[
				"hire_qualified_person",
				"request_signature",
				"request_assistance",
				"forge_qualification",
				"bribe_official",
				"illegal_entry",
				"change_jurisdiction",
			]
			if institutional_blocked
			else []
		),
		"method_reliability": method_reliability,
		"error_risk": error_risk,
		"likely_error_type": _error_type(skill, reasoning, experience),
		"expected_duration_hours": (
			base_duration_hours * (10000 + duration_overrun_bp) / 10000
		),
		"expected_cost_centimes": (
			base_cost_centimes * (10000 + cost_overrun_bp) / 10000
		),
		"quality_band": _quality_band(method_reliability),
		"dependence": dependence if helper_effect > 0 else (
			"assistance_advised" if method_reliability < 45 else "independent"
		),
		"state_cost": maxi(1, complexity / 10 + (100 - self_control) / 20),
	}
	assessments.append({
		"person_id": character.id,
		"action_id": action_id,
		"skill_id": skill_id,
		"domain_id": domain_id,
		"result": result.duplicate(true),
	})
	while assessments.size() > 128:
		assessments.pop_front()
	return result


func estimate_unknown_value(
	character: CharacterData,
	fact_id: String,
	objective_value: int,
	skill_id: String,
	complexity: int
) -> Dictionary:
	if character == null or fact_id.is_empty() or objective_value < 0:
		return _fail("invalid_estimate", "估计事实或客观数值无效")
	var skill: int = int(character.skills.get(skill_id, 0))
	var reasoning: int = int(character.hidden_aptitudes.get("reasoning", 50))
	var uncertainty_bp: int = clampi(
		7000 - skill * 45 - reasoning * 25 + complexity * 30, 300, 9000
	)
	var stable_offset: int = (
		abs((fact_id + character.id).hash()) % (uncertainty_bp + 1)
		- uncertainty_bp / 2
	)
	var center: int = maxi(0, objective_value * (10000 + stable_offset) / 10000)
	var half_width: int = maxi(
		1, objective_value * uncertainty_bp / 10000 / 2
	)
	return _ok({
		"fact_id": fact_id,
		"estimate_lower": maxi(0, center - half_width),
		"estimate_upper": center + half_width,
		"confidence": clampi(100 - uncertainty_bp / 100, 5, 97),
		"source": "personal_estimate",
		"confirmed": false,
	})


func schedule_development(
	idempotency_key: String,
	character: CharacterData,
	skill_id: String,
	method: String,
	start_hour: int,
	hours: int,
	cost_centimes: int,
	location_id: String,
	provider_id: String,
	mentor_id: String,
	priority: int,
	acceptable_state_risk: int,
	target_qualification: String = ""
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"plan": (
				development_plans.get(existing_id, {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	if (
		character == null
		or skill_id.is_empty()
		or method not in DEVELOPMENT_METHODS
		or hours <= 0
		or cost_centimes < 0
		or location_id.is_empty()
		or provider_id.is_empty()
		or priority < 0
		or acceptable_state_risk < 0
		or acceptable_state_risk > 100
		or method == "mentor_guidance" and mentor_id.is_empty()
		or method == "exam" and target_qualification.is_empty()
	):
		return _fail("invalid_development_plan", "个人发展时间、方法、地点或指导者无效")
	if cost_centimes > 0:
		var paid: Dictionary = _economy.ledger.transfer(
			"ledger:%s" % idempotency_key,
			start_hour,
			character.id,
			provider_id,
			cost_centimes,
			"personal_development",
			"fact:development:%s:%d" % [character.id, start_hour],
			"个人发展支出"
		)
		if not bool(paid.get("success", false)):
			return paid
	var plan_id: String = "development_plan:alpha:%d" % _next_plan_sequence
	_next_plan_sequence += 1
	var plan: Dictionary = {
		"plan_id": plan_id,
		"person_id": character.id,
		"skill_id": skill_id,
		"method": method,
		"start_hour": start_hour,
		"end_hour": start_hour + hours,
		"planned_hours": hours,
		"completed_hours": 0,
		"cost_centimes": cost_centimes,
		"location_id": location_id,
		"provider_id": provider_id,
		"mentor_id": mentor_id,
		"priority": priority,
		"acceptable_state_risk": acceptable_state_risk,
		"target_qualification": target_qualification,
		"schedule_activity_id": "activity:development:%s" % plan_id,
		"status": "scheduled",
		"result": {},
	}
	development_plans[plan_id] = plan
	var ids: Array = character.current_status.get("development_plan_ids", []) as Array
	ids.append(plan_id)
	character.current_status["development_plan_ids"] = ids
	_processed_keys[idempotency_key] = plan_id
	return _ok({"plan": plan.duplicate(true), "duplicate": false})


func settle_development(
	idempotency_key: String,
	character: CharacterData,
	plan_id: String,
	total_hour: int,
	actual_hours: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({
			"plan": (development_plans.get(plan_id, {}) as Dictionary).duplicate(true),
			"duplicate": true,
		})
	var plan: Dictionary = development_plans.get(plan_id, {}) as Dictionary
	if (
		character == null
		or str(plan.get("person_id", "")) != character.id
		or str(plan.get("status", "")) not in ["scheduled", "in_progress"]
		or actual_hours <= 0
		or total_hour < int(plan.get("start_hour", 0))
	):
		return _fail("invalid_development_settlement", "个人发展计划或结算边界无效")
	var completed: int = mini(
		int(plan.get("planned_hours", 0)),
		int(plan.get("completed_hours", 0)) + actual_hours
	)
	plan["completed_hours"] = completed
	var skill_id: String = str(plan.get("skill_id", ""))
	var current_skill: int = int(character.skills.get(skill_id, 0))
	var learning: int = int(character.hidden_aptitudes.get("learning", 50))
	var method_multiplier: int = _development_method_multiplier(
		str(plan.get("method", ""))
	)
	var gained: int = maxi(
		1, actual_hours * (50 + learning) * method_multiplier / 10000
	)
	character.skills[skill_id] = mini(100, current_skill + gained)
	character.domain_experience[skill_id] = (
		int(character.domain_experience.get(skill_id, 0)) + actual_hours
	)
	character.current_status["fatigue"] = mini(
		100, int(character.current_status.get("fatigue", 0)) + maxi(1, actual_hours / 3)
	)
	var qualified: bool = false
	if completed >= int(plan.get("planned_hours", 0)):
		plan["status"] = "completed"
		if str(plan.get("method", "")) == "exam":
			var pass_score: int = (
				int(character.skills.get(skill_id, 0))
				+ int(character.hidden_aptitudes.get("reasoning", 50))
			) / 2
			qualified = pass_score >= 55
			if qualified:
				var qualification: String = str(plan.get("target_qualification", ""))
				if qualification not in character.qualifications:
					character.qualifications.append(qualification)
		plan["result"] = {
			"skill_gain": gained,
			"qualification_awarded": qualified,
			"completed_hour": total_hour,
		}
	else:
		plan["status"] = "in_progress"
	development_plans[plan_id] = plan
	_processed_keys[idempotency_key] = plan_id
	return _ok({
		"plan": plan.duplicate(true),
		"skill_gain": gained,
		"qualification_awarded": qualified,
	})


func create_authorization(
	idempotency_key: String,
	principal_id: String,
	agent_id: String,
	organization_id: String,
	scope: Array,
	budget_limit_centimes: int,
	maximum_open_items: int,
	start_hour: int,
	end_hour: int,
	delegation_depth: int = 1
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"authorization": (
				authorizations.get(existing_id, {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	if (
		principal_id.is_empty()
		or agent_id.is_empty()
		or principal_id == agent_id
		or scope.is_empty()
		or budget_limit_centimes < 0
		or maximum_open_items < 1
		or end_hour <= start_hour
		or delegation_depth != 1
	):
		return _fail("invalid_authorization", "代理授权范围、期限或层级无效")
	var authorization_id: String = "authorization:alpha:%d" % _next_authorization_sequence
	_next_authorization_sequence += 1
	var authorization: Dictionary = {
		"authorization_id": authorization_id,
		"principal_id": principal_id,
		"agent_id": agent_id,
		"organization_id": organization_id,
		"scope": DataRecordUtils.to_string_array(scope),
		"budget_limit_centimes": budget_limit_centimes,
		"budget_used_centimes": 0,
		"maximum_open_items": maximum_open_items,
		"open_item_ids": [],
		"start_hour": start_hour,
		"end_hour": end_hour,
		"delegation_depth": 1,
		"status": "active",
	}
	authorizations[authorization_id] = authorization
	_processed_keys[idempotency_key] = authorization_id
	return _ok({"authorization": authorization.duplicate(true), "duplicate": false})


func authorize_item(
	idempotency_key: String,
	authorization_id: String,
	action_kind: String,
	item_id: String,
	cost_centimes: int,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"authorization": (authorizations.get(authorization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var authorization: Dictionary = authorizations.get(authorization_id, {}) as Dictionary
	var scope: Array[String] = DataRecordUtils.to_string_array(
		authorization.get("scope", [])
	)
	var open_items: Array = authorization.get("open_item_ids", []) as Array
	if (
		str(authorization.get("status", "")) != "active"
		or total_hour < int(authorization.get("start_hour", 0))
		or total_hour > int(authorization.get("end_hour", 0))
		or action_kind not in scope
		or open_items.size() >= int(authorization.get("maximum_open_items", 0))
		or int(authorization.get("budget_used_centimes", 0)) + cost_centimes
		> int(authorization.get("budget_limit_centimes", 0))
	):
		return _fail("authorization_denied", "代理事项超出范围、期限、并发或预算")
	open_items.append(item_id)
	authorization["open_item_ids"] = open_items
	authorization["budget_used_centimes"] = (
		int(authorization.get("budget_used_centimes", 0)) + cost_centimes
	)
	authorizations[authorization_id] = authorization
	_processed_keys[idempotency_key] = authorization_id
	return _ok({"authorization": authorization.duplicate(true)})


func public_character_view(character: CharacterData, developer_mode: bool = false) -> Dictionary:
	if character == null:
		return {}
	var view: Dictionary = character.to_public_dict()
	view["domain_experience"] = character.domain_experience.duplicate(true)
	view["qualifications"] = character.qualifications.duplicate()
	view["drives"] = character.drives.duplicate(true)
	view["issue_positions"] = character.issue_positions.duplicate(true)
	view["current_agendas"] = character.current_agendas.duplicate(true)
	view["bottom_lines"] = character.bottom_lines.duplicate()
	if developer_mode:
		view["hidden_aptitudes"] = character.hidden_aptitudes.duplicate(true)
		view["temperament_weights"] = character.temperament_weights.duplicate(true)
	return view


func get_persistent_state() -> Dictionary:
	return {
		"development_plans": development_plans.duplicate(true),
		"authorizations": authorizations.duplicate(true),
		"assessments": assessments.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_plan_sequence": _next_plan_sequence,
		"next_authorization_sequence": _next_authorization_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("development_plans", {}) is Dictionary
		or not state.get("authorizations", {}) is Dictionary
		or not state.get("processed_keys", {}) is Dictionary
	):
		return false
	development_plans = (state["development_plans"] as Dictionary).duplicate(true)
	authorizations = (state["authorizations"] as Dictionary).duplicate(true)
	assessments = DataRecordUtils.to_dictionary_array(
		state.get("assessments", [])
	)
	_processed_keys = (state["processed_keys"] as Dictionary).duplicate(true)
	_next_plan_sequence = int(state.get("next_plan_sequence", 0))
	_next_authorization_sequence = int(state.get("next_authorization_sequence", 0))
	return _next_plan_sequence >= 1 and _next_authorization_sequence >= 1


func _apply_category_history(character: CharacterData, category: String) -> void:
	if category.is_empty():
		return
	character.background_history.append({
		"kind": "alpha_background_category",
		"category": category,
		"years": maxi(2, character.age - 20),
	})
	character.domain_experience[category] = maxi(
		20, int(character.domain_experience.get(category, 0))
	)


func _apply_custom_background(character: CharacterData, custom: Dictionary) -> void:
	if custom.has("name") and not str(custom["name"]).is_empty():
		character.name = str(custom["name"])
	if custom.has("occupation_id"):
		character.occupation_id = str(custom["occupation_id"])
	if custom.has("occupation"):
		character.occupation = str(custom["occupation"])
	if custom.get("skill_adjustments", {}) is Dictionary:
		for raw_skill_id: Variant in (custom["skill_adjustments"] as Dictionary):
			var skill_id: String = str(raw_skill_id)
			character.skills[skill_id] = clampi(
				int(character.skills.get(skill_id, 0))
				+ int((custom["skill_adjustments"] as Dictionary)[raw_skill_id]),
				0,
				100
			)
	character.qualifications = DataRecordUtils.to_string_array(
		custom.get("qualifications", [])
	)
	character.background_history.append({
		"kind": "custom_background",
		"summary": str(custom.get("summary", "自定义成年履历")),
	})


func _ensure_alpha_person_fields(character: CharacterData, seed_value: int) -> void:
	if character.drives.is_empty():
		var random := DeterministicRandomService.new(seed_value + 997)
		character.drives = {
			"security": random.next_int(20, 80),
			"wealth": random.next_int(20, 80),
			"status": random.next_int(20, 80),
			"belonging": random.next_int(20, 80),
			"ideals": random.next_int(20, 80),
		}
	if character.current_agendas.is_empty():
		character.current_agendas = [{
			"agenda_id": "agenda:stability",
			"priority": 50,
			"status": "active",
		}]
	if character.bottom_lines.is_empty():
		character.bottom_lines = ["survival"]


static func _development_method_multiplier(method: String) -> int:
	match method:
		"mentor_guidance":
			return 150
		"formal_course":
			return 135
		"work_practice":
			return 120
		"organization_practice":
			return 115
		"exam":
			return 70
		"self_training":
			return 105
		_:
			return 100


static func _error_type(skill: int, reasoning: int, experience: int) -> String:
	if skill < 30:
		return "method_selection"
	if experience < 25:
		return "context_misread"
	if reasoning < 45:
		return "cost_or_dependency_omission"
	return "execution_variance"


static func _quality_band(reliability: int) -> String:
	if reliability >= 80:
		return "reliable"
	if reliability >= 55:
		return "workable"
	if reliability >= 35:
		return "fragile"
	return "high_rework_risk"


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
