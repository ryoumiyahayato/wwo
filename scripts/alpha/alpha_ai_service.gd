class_name AlphaAiService
extends RefCounted
## Bounded, explainable Alpha AI. Candidate selection only consumes person-known facts.

const MAX_CANDIDATES: int = 6
const HISTORY_LIMIT: int = 512

var decisions: Array[Dictionary] = []
var last_candidates: Dictionary = {}
var _labor: AlphaLaborService
var _economy: AlphaEconomyService
var _enterprise: AlphaEnterpriseService
var _politics: AlphaPoliticsService
var _organizations: OrganizationService
var _characters: AlphaCharacterService
var _processed_days: Dictionary = {}


func configure(
	labor: AlphaLaborService,
	economy: AlphaEconomyService,
	enterprise: AlphaEnterpriseService,
	politics: AlphaPoliticsService,
	organizations: OrganizationService,
	characters: AlphaCharacterService
) -> bool:
	_labor = labor
	_economy = economy
	_enterprise = enterprise
	_politics = politics
	_organizations = organizations
	_characters = characters
	decisions.clear()
	last_candidates.clear()
	_processed_days.clear()
	return (
		_labor != null
		and _economy != null
		and _enterprise != null
		and _politics != null
		and _organizations != null
		and _characters != null
	)


func build_candidates(
	character: CharacterData, known: Dictionary, total_hour: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if character == null:
		return candidates
	var employed: bool = bool(known.get("employed", false))
	var cash_low: bool = str(known.get("cash_band", "unknown")) in ["critical", "low"]
	var debt_band: String = str(known.get("debt_band", "unknown"))
	if employed:
		candidates.append(_candidate(
			"work", 80, "已有雇佣合同且今天可以履行工作", ["employment_status"]
		))
	else:
		candidates.append(_candidate(
			"seek_job", 90, "本人知道自己当前没有工作", ["employment_status", "known_jobs"]
		))
	if cash_low:
		candidates.append(_candidate(
			"seek_credit", 65, "本人估计现金缓冲偏低", ["cash_band", "known_lenders"]
		))
	if debt_band in ["moderate", "high"] and not cash_low:
		candidates.append(_candidate(
			"repay_debt", 72, "本人知道存在到期前可偿还债务", ["debt_band", "known_debts"]
		))
	if bool(known.get("can_migrate_for_work", false)) and not employed:
		candidates.append(_candidate(
			"migrate_for_work", 68, "已知的外地岗位高于本地机会", ["known_jobs", "known_routes"]
		))
	if (known.get("organization_ids", []) as Array).is_empty():
		candidates.append(_candidate(
			"join_organization", 42, "本人尚无组织身份且知道本地公开组织", ["known_organizations"]
		))
	if bool(known.get("known_business_opportunity", false)):
		candidates.append(_candidate(
			"found_enterprise", 38,
			"本人知道当前现金和本地市场足以尝试小规模经营",
			["cash_band", "known_business_opportunity"]
		))
	var controlled_enterprise_id: String = str(
		known.get("controlled_enterprise_id", "")
	)
	if not controlled_enterprise_id.is_empty():
		var business_risk: String = str(
			known.get("controlled_enterprise_risk", "stable")
		)
		candidates.append(_candidate(
			"sell_enterprise" if business_risk == "critical" else "manage_enterprise",
			76 if business_risk == "critical" else 36,
			"本人掌握其控制企业的经营摘要",
			["controlled_enterprise_id", "controlled_enterprise_risk"]
		))
		if (
			not bool(known.get("enterprise_has_partner", false))
			and not str(known.get("known_partner_id", "")).is_empty()
		):
			candidates.append(_candidate(
				"establish_partnership", 34,
				"企业尚无合伙人且本人知道一名可接触对象",
				["controlled_enterprise_id", "known_partner_id"]
			))
	if not str(known.get("contest_organization_id", "")).is_empty():
		candidates.append(_candidate(
			"contest_position", 35,
			"本人是组织成员并知道可争取的职位与支持者",
			["contest_organization_id", "known_supporter_id"]
		))
	if not str(known.get("policy_organization_id", "")).is_empty():
		candidates.append(_candidate(
			"advance_policy", 40,
			"本人知道现有职位具有一项公开政策权限",
			["policy_organization_id", "known_policy_id"]
		))
	if not bool(known.get("active_development_plan", false)):
		candidates.append(_candidate(
			"develop", 20,
			"本人当前没有发展计划且知道可用的独立训练方法",
			["development_skill_id", "known_development_method"]
		))
	candidates.append(_candidate(
		"wait", 10, "没有必须立即处理的已知事项", ["current_agendas"]
	))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a: int = int(a.get("priority", 0))
		var priority_b: int = int(b.get("priority", 0))
		return (
			str(a.get("action_id", "")) < str(b.get("action_id", ""))
			if priority_a == priority_b
			else priority_a > priority_b
		)
	)
	if candidates.size() > MAX_CANDIDATES:
		candidates.resize(MAX_CANDIDATES)
	last_candidates[character.id] = candidates.duplicate(true)
	return candidates


func process_person_day(
	character: CharacterData, known: Dictionary, total_hour: int
) -> Dictionary:
	if character == null:
		return _result(false, "invalid_character", {})
	var day_index: int = total_hour / 24
	var process_key: String = "%s:%d" % [character.id, day_index]
	if _processed_days.has(process_key):
		return _result(true, "already_processed", {
			"decision_id": str(_processed_days[process_key]),
			"duplicate": true,
		})
	var candidates: Array[Dictionary] = build_candidates(character, known, total_hour)
	if candidates.is_empty():
		return _result(false, "no_candidate", {})
	var selected: Dictionary = candidates[0]
	var secondary_day: bool = (
		posmod(day_index + absi(character.id.hash()), 7) == 0
	)
	if secondary_day:
		var secondary_candidates: Array[Dictionary] = []
		for candidate: Dictionary in candidates:
			if str(candidate.get("action_id", "")) not in [
				"work", "seek_job", "migrate_for_work", "seek_credit",
				"repay_debt", "join_organization", "wait",
			]:
				secondary_candidates.append(candidate)
		if not secondary_candidates.is_empty():
			selected = secondary_candidates[posmod(
				day_index / 7 + absi(character.id.hash()),
				secondary_candidates.size()
			)]
	var action_id: String = str(selected.get("action_id", "wait"))
	var execution: Dictionary = _execute(
		character, action_id, known, total_hour, process_key
	)
	var decision: Dictionary = {
		"decision_id": "ai_decision:%s:%d" % [character.id, day_index],
		"person_id": character.id,
		"total_hour": total_hour,
		"action_id": action_id,
		"reason": str(selected.get("reason", "")),
		"known_fields_used": (
			selected.get("known_fields_used", []) as Array
		).duplicate(),
		"candidate_count": candidates.size(),
		"execution_success": bool(execution.get("success", false)),
		"execution_code": str(execution.get("code", "")),
	}
	decisions.append(decision)
	while decisions.size() > HISTORY_LIMIT:
		decisions.pop_front()
	_processed_days[process_key] = decision["decision_id"]
	_trim_processed_days(day_index)
	return _result(true, "ok", {
		"decision": decision.duplicate(true),
		"execution": execution.duplicate(true),
	})


func get_persistent_state() -> Dictionary:
	return {
		"decisions": decisions.duplicate(true),
		"last_candidates": last_candidates.duplicate(true),
		"processed_days": _processed_days.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("decisions", []) is Array
		or not state.get("last_candidates", {}) is Dictionary
		or not state.get("processed_days", {}) is Dictionary
	):
		return false
	decisions = DataRecordUtils.to_dictionary_array(state["decisions"])
	last_candidates = (state["last_candidates"] as Dictionary).duplicate(true)
	_processed_days = (state["processed_days"] as Dictionary).duplicate(true)
	while decisions.size() > HISTORY_LIMIT:
		decisions.pop_front()
	return true


func _execute(
	character: CharacterData,
	action_id: String,
	known: Dictionary,
	total_hour: int,
	key: String
) -> Dictionary:
	match action_id:
		"work":
			var contract_id: String = str(known.get("employment_contract_id", ""))
			if contract_id.is_empty():
				return _result(false, "employment_unknown", {})
			var worked: Dictionary = _labor.work_shift(
				"ai:work:%s" % key, contract_id, total_hour, 8, 9000, false
			)
			if bool(worked.get("success", false)) and total_hour / 24 % 7 == 0:
				_labor.pay_wage(
					"ai:wage:%s" % key, contract_id, total_hour
				)
			return worked
		"seek_job", "migrate_for_work":
			return _seek_and_accept_job(character, known, total_hour, key, action_id)
		"seek_credit":
			return _seek_credit(character, known, total_hour, key)
		"repay_debt":
			var debt_id: String = str(known.get("repayable_contract_id", ""))
			var amount: int = mini(
				int(known.get("repayable_amount_centimes", 0)),
				maxi(0, _economy.ledger.owner_cash(character.id) / 3)
			)
			if debt_id.is_empty() or amount <= 0:
				return _result(false, "debt_not_actionable", {})
			return _economy.repay_loan(
				"ai:repay:%s" % key, debt_id, total_hour, amount
			)
		"join_organization":
			var organization_id: String = str(known.get("joinable_organization_id", ""))
			if organization_id.is_empty():
				return _result(false, "organization_unknown", {})
			return _politics.join_organization(
				"ai:join:%s" % key, character, organization_id, total_hour
			)
		"found_enterprise":
			return _found_enterprise(character, known, total_hour, key)
		"manage_enterprise":
			return _enterprise.aggregate_day(
				"ai:manage:%s" % key,
				str(known.get("controlled_enterprise_id", "")),
				total_hour
			)
		"establish_partnership":
			return _enterprise.establish_partnership(
				"ai:partner:%s" % key,
				str(known.get("controlled_enterprise_id", "")),
				character.id,
				str(known.get("known_partner_id", "")),
				300,
				2000,
				total_hour
			)
		"sell_enterprise":
			return _sell_enterprise(character, known, total_hour, key)
		"contest_position":
			return _contest_position(character, known, total_hour, key)
		"advance_policy":
			return _advance_policy(character, known, total_hour, key)
		"develop":
			return _characters.schedule_development(
				"ai:develop:%s" % key,
				character,
				str(known.get("development_skill_id", "finance")),
				"independent_study",
				total_hour + 1,
				8,
				0,
				str(known.get(
					"development_location_id",
					"location:dawnharbor:home"
				)),
				AlphaEnterpriseService.AGGREGATE_MARKET_ID,
				"",
				40,
				35
			)
		_:
			return _result(true, "waited", {})


func _found_enterprise(
	character: CharacterData,
	known: Dictionary,
	total_hour: int,
	key: String
) -> Dictionary:
	var available: int = _economy.ledger.owner_cash(character.id)
	if available < 800:
		return _result(false, "business_capital_unavailable", {})
	return _enterprise.create_enterprise(
		"ai:enterprise:%s" % key,
		character.id,
		"%s的地区经营社" % character.name,
		str(known.get("business_structure", "retail_trade")),
		character.region_id,
		str(character.current_status.get("city_id", "city:dawnharbor")),
		str(known.get("business_product_id", "household_goods")),
		str(known.get("business_input_id", "grain")),
		mini(1200, available / 2),
		total_hour
	)


func _sell_enterprise(
	character: CharacterData,
	known: Dictionary,
	total_hour: int,
	key: String
) -> Dictionary:
	var organization_id: String = str(
		known.get("controlled_enterprise_id", "")
	)
	var state: Dictionary = _enterprise.enterprises.get(
		organization_id, {}
	) as Dictionary
	var equity_id: String = str(state.get("equity_asset_id", ""))
	var share_bp: int = _economy.assets.owner_share(equity_id, character.id)
	if share_bp <= 0:
		return _result(false, "enterprise_equity_unavailable", {})
	return _enterprise.purchase_enterprise_share(
		"ai:sell:%s" % key,
		organization_id,
		character.id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		mini(share_bp, 5100),
		maxi(1, _economy.assets.value(equity_id) / 2),
		total_hour
	)


func _contest_position(
	character: CharacterData,
	known: Dictionary,
	total_hour: int,
	key: String
) -> Dictionary:
	var organization_id: String = str(
		known.get("contest_organization_id", "")
	)
	var supporter_id: String = str(known.get("known_supporter_id", ""))
	var supporter: CharacterData = known.get(
		"known_supporter_character"
	) as CharacterData
	if supporter != null and not supporter_id.is_empty():
		_politics.campaign_for_support(
			"ai:campaign:%s" % key,
			character,
			supporter,
			organization_id,
			str(known.get("known_issue_id", "")),
			80
		)
	return _politics.contest_position(
		"ai:contest:%s" % key,
		character,
		organization_id,
		str(known.get("contest_position_id", "")),
		total_hour
	)


func _advance_policy(
	character: CharacterData,
	known: Dictionary,
	total_hour: int,
	key: String
) -> Dictionary:
	var organization_id: String = str(
		known.get("policy_organization_id", "")
	)
	var proposed: Dictionary = _politics.propose_policy(
		"ai:policy_propose:%s" % key,
		character,
		organization_id,
		str(known.get("known_policy_id", "")),
		[known.get("policy_region_id", character.region_id)],
		total_hour
	)
	if not bool(proposed.get("success", false)):
		return proposed
	var implementation: Dictionary = (
		proposed.get("data", {}) as Dictionary
	).get("implementation", {}) as Dictionary
	return _politics.fund_and_start_policy(
		"ai:policy_fund:%s" % key,
		str(implementation.get("implementation_id", "")),
		total_hour
	)


func _seek_and_accept_job(
	character: CharacterData,
	known: Dictionary,
	total_hour: int,
	key: String,
	action_id: String
) -> Dictionary:
	var job_id: String = str(known.get("best_known_job_id", ""))
	if job_id.is_empty():
		return _result(false, "job_unknown", {})
	if action_id == "migrate_for_work":
		var job: Dictionary = _labor.jobs.get(job_id, {}) as Dictionary
		var target_city: String = str(job.get("city_id", ""))
		var target_region: String = str(known.get("target_region_id", ""))
		var migration: Dictionary = _labor.migrate(
			"ai:migrate:%s" % key,
			character.id,
			str(known.get("target_country_id", character.country_id)),
			target_region,
			target_city,
			AlphaEnterpriseService.AGGREGATE_MARKET_ID,
			int(known.get("migration_cost_centimes", 120)),
			total_hour
		)
		if not bool(migration.get("success", false)):
			return migration
		character.region_id = target_region
		character.current_status["city_id"] = target_city
	var applied: Dictionary = _labor.apply_for_job(
		"ai:apply:%s" % key, character.id, job_id, total_hour
	)
	if not bool(applied.get("success", false)):
		return applied
	var application: Dictionary = (
		applied.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	var application_id: String = str(application.get("application_id", ""))
	var decided: Dictionary = _labor.employer_decide(
		"ai:decide:%s" % key,
		application_id,
		total_hour,
		int(known.get("labor_demand_index", 50))
	)
	if not bool(decided.get("success", false)):
		return decided
	var decided_application: Dictionary = (
		decided.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	if str(decided_application.get("status", "")) == "rejected":
		return decided
	return _labor.accept_job_offer(
		"ai:accept:%s" % key, application_id, total_hour
	)


func _seek_credit(
	character: CharacterData,
	known: Dictionary,
	total_hour: int,
	key: String
) -> Dictionary:
	var lender_id: String = str(known.get("known_lender_id", ""))
	if lender_id.is_empty():
		return _result(false, "lender_unknown", {})
	var applied: Dictionary = _economy.apply_for_loan(
		"ai:loan_apply:%s" % key,
		character.id,
		lender_id,
		"credit:personal_unsecured",
		int(known.get("requested_credit_centimes", 1800)),
		total_hour,
		[],
		[],
		{"existing_debt_centimes": int(known.get("disclosed_debt_centimes", 0))}
	)
	if not bool(applied.get("success", false)):
		return applied
	var application_id: String = str(
		((applied.get("data", {}) as Dictionary).get(
			"application", {}
		) as Dictionary).get("application_id", "")
	)
	var reviewed: Dictionary = _economy.review_application(
		"ai:loan_review:%s" % key, application_id, total_hour
	)
	if not bool(reviewed.get("success", false)):
		return reviewed
	var reviewed_application: Dictionary = (
		reviewed.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	if str(reviewed_application.get("status", "")) != "offered":
		return reviewed
	return _economy.accept_loan_offer(
		"ai:loan_accept:%s" % key, application_id, total_hour
	)


func _trim_processed_days(current_day: int) -> void:
	var minimum_day: int = current_day - 62
	for raw_key: Variant in _processed_days.keys():
		var key: String = str(raw_key)
		var day_text: String = key.get_slice(":", key.get_slice_count(":") - 1)
		if day_text.is_valid_int() and int(day_text) < minimum_day:
			_processed_days.erase(key)


static func _candidate(
	action_id: String, priority: int, reason: String, known_fields: Array
) -> Dictionary:
	return {
		"action_id": action_id,
		"priority": priority,
		"reason": reason,
		"known_fields_used": known_fields.duplicate(),
	}


static func _result(success: bool, code: String, data: Dictionary) -> Dictionary:
	return {"success": success, "code": code, "message": "", "data": data}
