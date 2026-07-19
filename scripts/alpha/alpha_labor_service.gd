class_name AlphaLaborService
extends RefCounted
## Employment lifecycle shared by player-controlled and AI-controlled people.

const ACTIVE_EMPLOYMENT_STATUSES: Array[String] = [
	"active",
	"partially_fulfilled",
	"delayed",
	"renegotiated",
]

var jobs: Dictionary = {}
var applications: Dictionary = {}
var employment_states: Dictionary = {}
var person_profiles: Dictionary = {}
var unemployment: Dictionary = {}
var migrations: Array[Dictionary] = []
var _economy: AlphaEconomyService
var _processed_keys: Dictionary = {}
var _next_application_sequence: int = 1


func configure(config: AlphaConfig, economy: AlphaEconomyService) -> bool:
	jobs.clear()
	applications.clear()
	employment_states.clear()
	person_profiles.clear()
	unemployment.clear()
	migrations.clear()
	_processed_keys.clear()
	_next_application_sequence = 1
	_economy = economy
	for raw_job: Variant in config.job_records():
		var job: Dictionary = raw_job as Dictionary
		var job_id: String = str(job.get("job_id", ""))
		if job_id.is_empty() or jobs.has(job_id):
			return false
		jobs[job_id] = job.duplicate(true)
	return jobs.size() >= 12


func register_person(person_id: String, profile: Dictionary) -> bool:
	if person_id.is_empty():
		return false
	person_profiles[person_id] = {
		"person_id": person_id,
		"country_id": str(profile.get("country_id", "")),
		"region_id": str(profile.get("region_id", "")),
		"city_id": str(profile.get("city_id", "")),
		"skills": (profile.get("skills", {}) as Dictionary).duplicate(true),
		"qualifications": DataRecordUtils.to_string_array(profile.get("qualifications", [])),
		"experience": (profile.get("experience", {}) as Dictionary).duplicate(true),
		"health": int(profile.get("health", 80)),
		"fatigue": int(profile.get("fatigue", 10)),
		"stress": int(profile.get("stress", 10)),
		"occupation_id": str(profile.get("occupation_id", "")),
		"employment_contract_ids": [],
	}
	if not _economy.entity_profiles.has(person_id):
		var registered: Dictionary = _economy.register_entity(
			person_id,
			"person",
			int(profile.get("opening_cash_centimes", 0)),
			{
				"income_monthly_centimes": int(profile.get("income_monthly_centimes", 0)),
				"reputation": int(profile.get("reputation", 50)),
				"relationship_with_lender": int(profile.get("relationship_with_lender", 0)),
				"region_id": str(profile.get("region_id", "")),
				"qualifications": profile.get("qualifications", []),
			}
		)
		if not bool(registered.get("success", false)):
			return false
	unemployment[person_id] = {
		"since_hour": 0,
		"reason": "initial",
		"searching": false,
	}
	return true


func register_runtime_job(job: Dictionary) -> bool:
	var job_id: String = str(job.get("job_id", ""))
	if (
		job_id.is_empty()
		or jobs.has(job_id)
		or str(job.get("employer_id", "")).is_empty()
		or str(job.get("city_id", "")).is_empty()
		or int(job.get("wage", 0)) <= 0
		or int(job.get("hours_per_week", 0)) <= 0
	):
		return false
	jobs[job_id] = job.duplicate(true)
	return true


func discover_jobs(person_id: String, include_other_cities: bool = true) -> Array[Dictionary]:
	var profile: Dictionary = person_profiles.get(person_id, {}) as Dictionary
	var result: Array[Dictionary] = []
	if profile.is_empty():
		return result
	for raw_job: Variant in jobs.values():
		var job: Dictionary = raw_job as Dictionary
		if (
			include_other_cities
			or str(job.get("city_id", "")) == str(profile.get("city_id", ""))
		):
			var public_job: Dictionary = job.duplicate(true)
			public_job["requires_migration"] = (
				str(job.get("city_id", "")) != str(profile.get("city_id", ""))
			)
			result.append(public_job)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("job_id", "")) < str(b.get("job_id", ""))
	)
	return result


func apply_for_job(
	idempotency_key: String,
	person_id: String,
	job_id: String,
	total_hour: int,
	proposed_terms: Dictionary = {}
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _application_duplicate(idempotency_key)
	if not person_profiles.has(person_id) or not jobs.has(job_id):
		return _fail("invalid_job_application", "求职者或工作不存在")
	var application_id: String = "job_application:alpha:%d" % _next_application_sequence
	_next_application_sequence += 1
	var application: Dictionary = {
		"application_id": application_id,
		"person_id": person_id,
		"job_id": job_id,
		"employer_id": str((jobs[job_id] as Dictionary).get("employer_id", "")),
		"submitted_hour": total_hour,
		"proposed_terms": proposed_terms.duplicate(true),
		"status": "submitted",
		"decision_reason": "",
		"offered_terms": {},
	}
	applications[application_id] = application
	_processed_keys[idempotency_key] = application_id
	return _ok({"application": application.duplicate(true), "duplicate": false})


func employer_decide(
	idempotency_key: String,
	application_id: String,
	total_hour: int,
	labor_demand_index: int = 50
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _application_duplicate(idempotency_key)
	var application: Dictionary = applications.get(application_id, {}) as Dictionary
	if application.is_empty() or str(application.get("status", "")) != "submitted":
		return _fail("invalid_job_decision", "求职申请不处于待判断状态")
	var profile: Dictionary = person_profiles[
		str(application.get("person_id", ""))
	] as Dictionary
	var job: Dictionary = jobs[str(application.get("job_id", ""))] as Dictionary
	var skills: Dictionary = profile.get("skills", {}) as Dictionary
	var skill_id: String = str(job.get("skill", ""))
	var skill_level: int = int(skills.get(skill_id, 0))
	var qualification: String = str(job.get("qualification", ""))
	var qualifications: Array[String] = DataRecordUtils.to_string_array(
		profile.get("qualifications", [])
	)
	var score: int = skill_level + labor_demand_index / 2
	var status: String = "offered"
	var reason: String = "经验和地区用工需求达到雇主条件"
	if not qualification.is_empty() and qualification not in qualifications:
		status = "rejected"
		reason = "该岗位依法要求尚未具备的资格"
	elif score < 38:
		status = "rejected"
		reason = "雇主认为当前方法可靠性不足"
	elif score < 55:
		status = "countered"
		reason = "雇主提出试用和较低起薪"
	application["status"] = status
	application["decision_hour"] = total_hour
	application["decision_reason"] = reason
	var wage: int = int(job.get("wage", 0))
	if status == "countered":
		wage = wage * 85 / 100
	if status in ["offered", "countered"]:
		application["offered_terms"] = {
			"wage_centimes_per_week": wage,
			"hours_per_week": int(job.get("hours_per_week", 0)),
			"probation_days": 30 if status == "countered" else 0,
			"city_id": str(job.get("city_id", "")),
		}
	applications[application_id] = application
	_processed_keys[idempotency_key] = application_id
	return _ok({"application": application.duplicate(true)})


func accept_job_offer(
	idempotency_key: String, application_id: String, total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var contract_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"contract": (
				_economy.contracts.contracts.get(contract_id, {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	var application: Dictionary = applications.get(application_id, {}) as Dictionary
	if str(application.get("status", "")) not in ["offered", "countered"]:
		return _fail("job_offer_unavailable", "工作条件尚未提出或已经失效")
	var person_id: String = str(application.get("person_id", ""))
	var job: Dictionary = jobs[str(application.get("job_id", ""))] as Dictionary
	var offered: Dictionary = application.get("offered_terms", {}) as Dictionary
	var weekly_wage: int = int(offered.get("wage_centimes_per_week", 0))
	var term_days: int = 180
	var contract_result: Dictionary = _economy.contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:employment",
		[
			{"party_id": str(job.get("employer_id", "")), "role": "employer"},
			{"party_id": person_id, "role": "employee"},
		],
		{
			"job_id": job.get("job_id", ""),
			"position": job.get("name", ""),
			"location_city_id": job.get("city_id", ""),
		},
		weekly_wage * ceili(float(term_days) / 7.0),
		total_hour,
		total_hour + term_days * 24,
		{
			"payment_conditions": {"frequency_days": 7, "weekly_wage": weekly_wage},
			"hours_per_week": int(offered.get("hours_per_week", 0)),
			"promotion_condition": job.get("promotion", ""),
			"dismissal_condition": job.get("dismissal", ""),
			"probation_days": int(offered.get("probation_days", 0)),
			"document_ids": ["document:employment:%s" % application_id],
		}
	)
	if not bool(contract_result.get("success", false)):
		return contract_result
	var contract: Dictionary = (contract_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	var activated: Dictionary = _economy.contracts.activate(
		"activate:%s" % idempotency_key, contract_id, total_hour
	)
	if not bool(activated.get("success", false)):
		return activated
	employment_states[contract_id] = {
		"contract_id": contract_id,
		"person_id": person_id,
		"employer_id": str(job.get("employer_id", "")),
		"job_id": str(job.get("job_id", "")),
		"hours_worked_current_week": 0,
		"pending_wage_centimes": 0,
		"absence_hours": 0,
		"quality_total": 0,
		"shifts": 0,
		"promotion_level": 0,
		"status": "active",
	}
	var profile: Dictionary = person_profiles[person_id] as Dictionary
	var ids: Array = profile.get("employment_contract_ids", []) as Array
	ids.append(contract_id)
	profile["employment_contract_ids"] = ids
	profile["occupation_id"] = str(job.get("job_id", ""))
	profile["income_monthly_centimes"] = weekly_wage * 4
	person_profiles[person_id] = profile
	if _economy.entity_profiles.has(person_id):
		var economy_profile: Dictionary = _economy.entity_profiles[
			person_id
		] as Dictionary
		economy_profile["income_monthly_centimes"] = weekly_wage * 4
		_economy.entity_profiles[person_id] = economy_profile
	unemployment.erase(person_id)
	application["status"] = "accepted"
	application["contract_id"] = contract_id
	applications[application_id] = application
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": _economy.contracts.contracts[contract_id]})


func direct_hire(
	idempotency_key: String,
	person_id: String,
	job_id: String,
	total_hour: int
) -> Dictionary:
	var applied: Dictionary = apply_for_job(
		"apply:%s" % idempotency_key, person_id, job_id, total_hour
	)
	if not bool(applied.get("success", false)):
		return applied
	var application: Dictionary = (applied.get("data", {}) as Dictionary).get(
		"application", {}
	) as Dictionary
	var application_id: String = str(application.get("application_id", ""))
	var decided: Dictionary = employer_decide(
		"decide:%s" % idempotency_key, application_id, total_hour, 90
	)
	if not bool(decided.get("success", false)):
		return decided
	var status: String = str(
		((decided.get("data", {}) as Dictionary).get(
			"application", {}
		) as Dictionary).get("status", "")
	)
	if status == "rejected":
		return _fail("hire_rejected", "正式雇主判断未接受该求职者")
	return accept_job_offer(idempotency_key, application_id, total_hour)


func work_shift(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	hours: int,
	effort_bp: int = 10000,
	absent: bool = false
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"state": (employment_states.get(contract_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = employment_states.get(contract_id, {}) as Dictionary
	var contract: Dictionary = _economy.contracts.contracts.get(contract_id, {}) as Dictionary
	if (
		state.is_empty()
		or str(state.get("status", "")) != "active"
		or str(contract.get("status", "")) not in ACTIVE_EMPLOYMENT_STATUSES
		or hours <= 0
	):
		return _fail("invalid_work_shift", "工作班次或雇佣状态无效")
	var person_id: String = str(state.get("person_id", ""))
	var profile: Dictionary = person_profiles[person_id] as Dictionary
	if absent:
		state["absence_hours"] = int(state.get("absence_hours", 0)) + hours
		profile["stress"] = mini(100, int(profile.get("stress", 0)) + 2)
	else:
		var job: Dictionary = jobs[str(state.get("job_id", ""))] as Dictionary
		var skill_id: String = str(job.get("skill", ""))
		var skills: Dictionary = profile.get("skills", {}) as Dictionary
		var skill: int = int(skills.get(skill_id, 0))
		var quality: int = clampi(skill * 100 + effort_bp / 2, 1000, 10000)
		state["hours_worked_current_week"] = (
			int(state.get("hours_worked_current_week", 0)) + hours
		)
		state["quality_total"] = int(state.get("quality_total", 0)) + quality
		state["shifts"] = int(state.get("shifts", 0)) + 1
		var terms: Dictionary = contract.get("terms", {}) as Dictionary
		var scheduled_hours: int = maxi(1, int(terms.get("hours_per_week", 40)))
		var weekly_wage: int = int(
			(contract.get("payment_conditions", {}) as Dictionary).get(
				"weekly_wage", 0
			)
		)
		state["pending_wage_centimes"] = (
			int(state.get("pending_wage_centimes", 0))
			+ weekly_wage * hours / scheduled_hours
		)
		skills[skill_id] = mini(100, skill + 1)
		profile["skills"] = skills
		var experience: Dictionary = profile.get("experience", {}) as Dictionary
		experience[skill_id] = int(experience.get(skill_id, 0)) + hours
		profile["experience"] = experience
		profile["fatigue"] = mini(100, int(profile.get("fatigue", 0)) + maxi(1, hours / 2))
		var term_hours: int = maxi(
			1, int(contract.get("end_hour", total_hour)) - int(contract.get("start_hour", 0))
		)
		var delivery_bp: int = maxi(1, hours * 10000 / term_hours)
		_economy.contracts.record_delivery(
			"delivery:%s" % idempotency_key,
			contract_id,
			total_hour,
			delivery_bp,
			"evidence:work_shift:%s" % idempotency_key
		)
	person_profiles[person_id] = profile
	employment_states[contract_id] = state
	_processed_keys[idempotency_key] = contract_id
	return _ok({"state": state.duplicate(true), "profile": profile.duplicate(true)})


func pay_wage(
	idempotency_key: String, contract_id: String, total_hour: int
) -> Dictionary:
	var state: Dictionary = employment_states.get(contract_id, {}) as Dictionary
	var amount: int = int(state.get("pending_wage_centimes", 0))
	if amount <= 0:
		return _fail("no_wage_due", "当前没有已完成工作对应的工资")
	var payment: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		str(state.get("employer_id", "")),
		str(state.get("person_id", "")),
		amount,
		"employment_wage",
		"fact:wage:%s:%d" % [contract_id, total_hour],
		"雇佣合同工资"
	)
	if not bool(payment.get("success", false)):
		return payment
	var transaction: Dictionary = (payment.get("data", {}) as Dictionary).get(
		"transaction", {}
	) as Dictionary
	var recorded: Dictionary = _economy.contracts.record_payment(
		idempotency_key,
		contract_id,
		total_hour,
		str(transaction.get("transaction_id", "")),
		amount
	)
	if not bool(recorded.get("success", false)):
		return recorded
	state["pending_wage_centimes"] = 0
	state["hours_worked_current_week"] = 0
	employment_states[contract_id] = state
	var person_id: String = str(state.get("person_id", ""))
	var profile: Dictionary = _economy.entity_profiles.get(person_id, {}) as Dictionary
	profile["income_monthly_centimes"] = amount * 4
	_economy.entity_profiles[person_id] = profile
	return _ok({"contract": recorded.get("data", {}).get("contract", {}), "amount_centimes": amount})


func negotiate_terms(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	new_weekly_wage: int,
	new_hours_per_week: int
) -> Dictionary:
	var contract: Dictionary = _economy.contracts.contracts.get(contract_id, {}) as Dictionary
	if new_weekly_wage <= 0 or new_hours_per_week <= 0:
		return _fail("invalid_employment_terms", "协商工资或工时无效")
	var payment_conditions: Dictionary = contract.get("payment_conditions", {}) as Dictionary
	payment_conditions["weekly_wage"] = new_weekly_wage
	contract["payment_conditions"] = payment_conditions
	_economy.contracts.contracts[contract_id] = contract
	return _economy.contracts.renegotiate(
		idempotency_key,
		contract_id,
		total_hour,
		int(contract.get("end_hour", total_hour + 1)),
		{"hours_per_week": new_hours_per_week, "weekly_wage": new_weekly_wage}
	)


func promote(
	idempotency_key: String, contract_id: String, total_hour: int, new_position: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"state": (employment_states.get(contract_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = employment_states.get(contract_id, {}) as Dictionary
	if state.is_empty() or new_position.is_empty():
		return _fail("invalid_promotion", "晋升对象或职位无效")
	state["promotion_level"] = int(state.get("promotion_level", 0)) + 1
	var contract: Dictionary = _economy.contracts.contracts[contract_id] as Dictionary
	var subject: Dictionary = contract.get("subject", {}) as Dictionary
	subject["position"] = new_position
	contract["subject"] = subject
	_economy.contracts.contracts[contract_id] = contract
	employment_states[contract_id] = state
	_processed_keys[idempotency_key] = contract_id
	return _ok({"state": state.duplicate(true), "contract": contract.duplicate(true)})


func resign(
	idempotency_key: String, contract_id: String, total_hour: int
) -> Dictionary:
	return _end_employment(idempotency_key, contract_id, total_hour, "resigned", "主动辞职")


func dismiss(
	idempotency_key: String, contract_id: String, total_hour: int, reason: String
) -> Dictionary:
	return _end_employment(idempotency_key, contract_id, total_hour, "dismissed", reason)


func migrate(
	idempotency_key: String,
	person_id: String,
	new_country_id: String,
	new_region_id: String,
	new_city_id: String,
	transport_provider_id: String,
	cost_centimes: int,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"migration": migrations.back().duplicate(true), "duplicate": true})
	var profile: Dictionary = person_profiles.get(person_id, {}) as Dictionary
	if profile.is_empty() or new_region_id.is_empty() or new_city_id.is_empty():
		return _fail("invalid_migration", "迁移人物或目标无效")
	var payment: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		person_id,
		transport_provider_id,
		cost_centimes,
		"migration_transport",
		"fact:migration:%s:%d" % [person_id, total_hour],
		"跨地区迁移交通费"
	)
	if not bool(payment.get("success", false)):
		return payment
	var migration: Dictionary = {
		"migration_id": "migration:alpha:%d" % migrations.size(),
		"person_id": person_id,
		"from_country_id": profile.get("country_id", ""),
		"from_region_id": profile.get("region_id", ""),
		"from_city_id": profile.get("city_id", ""),
		"to_country_id": new_country_id,
		"to_region_id": new_region_id,
		"to_city_id": new_city_id,
		"total_hour": total_hour,
		"cost_centimes": cost_centimes,
	}
	profile["country_id"] = new_country_id
	profile["region_id"] = new_region_id
	profile["city_id"] = new_city_id
	person_profiles[person_id] = profile
	var economy_profile: Dictionary = _economy.entity_profiles[person_id] as Dictionary
	economy_profile["region_id"] = new_region_id
	_economy.entity_profiles[person_id] = economy_profile
	migrations.append(migration)
	_processed_keys[idempotency_key] = migration["migration_id"]
	return _ok({"migration": migration.duplicate(true)})


func get_persistent_state() -> Dictionary:
	return {
		"applications": applications.duplicate(true),
		"employment_states": employment_states.duplicate(true),
		"person_profiles": person_profiles.duplicate(true),
		"unemployment": unemployment.duplicate(true),
		"migrations": migrations.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_application_sequence": _next_application_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("applications", {}) is Dictionary
		or not state.get("employment_states", {}) is Dictionary
		or not state.get("person_profiles", {}) is Dictionary
	):
		return false
	applications = (state["applications"] as Dictionary).duplicate(true)
	employment_states = (state["employment_states"] as Dictionary).duplicate(true)
	person_profiles = (state["person_profiles"] as Dictionary).duplicate(true)
	unemployment = (state.get("unemployment", {}) as Dictionary).duplicate(true)
	migrations = DataRecordUtils.to_dictionary_array(
		state.get("migrations", [])
	)
	_processed_keys = (state.get("processed_keys", {}) as Dictionary).duplicate(true)
	_next_application_sequence = int(state.get("next_application_sequence", 0))
	for raw_contract_id: Variant in employment_states:
		if not _economy.contracts.contracts.has(str(raw_contract_id)):
			return false
	return _next_application_sequence >= 1


func _end_employment(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	status: String,
	reason: String
) -> Dictionary:
	var state: Dictionary = employment_states.get(contract_id, {}) as Dictionary
	if state.is_empty() or str(state.get("status", "")) != "active":
		return _fail("employment_not_active", "雇佣关系已经结束")
	var terminated: Dictionary = _economy.contracts.terminate(
		idempotency_key, contract_id, total_hour, reason
	)
	if not bool(terminated.get("success", false)):
		return terminated
	state["status"] = status
	state["ended_hour"] = total_hour
	state["end_reason"] = reason
	employment_states[contract_id] = state
	var person_id: String = str(state.get("person_id", ""))
	unemployment[person_id] = {
		"since_hour": total_hour,
		"reason": reason,
		"searching": true,
	}
	var profile: Dictionary = person_profiles[person_id] as Dictionary
	profile["occupation_id"] = "unemployed"
	person_profiles[person_id] = profile
	return _ok({"state": state.duplicate(true), "contract": terminated.get("data", {}).get("contract", {})})


func _application_duplicate(idempotency_key: String) -> Dictionary:
	var application_id: String = str(_processed_keys[idempotency_key])
	return _ok({
		"application": (
			applications.get(application_id, {}) as Dictionary
		).duplicate(true),
		"duplicate": true,
	})


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
