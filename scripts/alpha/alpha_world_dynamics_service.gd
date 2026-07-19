class_name AlphaWorldDynamicsService
extends RefCounted
## Daily/weekly/monthly Alpha batches. No world-wide work is performed each hour.

const EVENT_LIMIT: int = 512
const BACKGROUND_MATTER_LIMIT: int = 3

var background_states: Dictionary = {}
var national_issues: Dictionary = {}
var events: Array[Dictionary] = []
var counters: Dictionary = {}
var _world: AlphaWorldService
var _economy: AlphaEconomyService
var _enterprise: AlphaEnterpriseService
var _politics: AlphaPoliticsService
var _roster: CharacterRosterService
var _config: AlphaConfig
var _last_day_index: int = -1
var _last_week_index: int = -1
var _last_month_key: String = ""


func configure(
	world: AlphaWorldService,
	economy: AlphaEconomyService,
	enterprise: AlphaEnterpriseService,
	politics: AlphaPoliticsService,
	roster: CharacterRosterService,
	config: AlphaConfig
) -> bool:
	_world = world
	_economy = economy
	_enterprise = enterprise
	_politics = politics
	_roster = roster
	_config = config
	background_states.clear()
	national_issues.clear()
	events.clear()
	counters = {
		"daily_batches": 0,
		"weekly_batches": 0,
		"monthly_batches": 0,
		"background_job_changes": 0,
		"background_migrations": 0,
		"enterprise_bankruptcies": 0,
		"loan_defaults": 0,
		"policy_changes": 0,
	}
	_last_day_index = -1
	_last_week_index = -1
	_last_month_key = ""
	if (
		_world == null
		or _economy == null
		or _enterprise == null
		or _politics == null
		or _roster == null
		or _config == null
	):
		return false
	_initialize_background_states()
	_initialize_national_issues()
	return background_states.size() >= 100 and national_issues.size() >= 6


func process_boundaries(total_hour: int, active_characters: Dictionary) -> Dictionary:
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	var day_index: int = total_hour / 24
	if int(value.get("hour", -1)) == 23 and day_index > _last_day_index:
		_process_day(total_hour, active_characters)
		_last_day_index = day_index
	var week_index: int = day_index / 7
	if (
		int(value.get("hour", -1)) == 23
		and day_index % 7 == 6
		and week_index > _last_week_index
	):
		_process_week(total_hour)
		_last_week_index = week_index
	var month_key: String = "%04d-%02d" % [
		int(value.get("year", 1900)), int(value.get("month", 1)),
	]
	if (
		int(value.get("hour", -1)) == 23
		and int(value.get("day", -1)) == 1
		and month_key != _last_month_key
	):
		_process_month(total_hour, active_characters)
		_last_month_key = month_key
	return counters.duplicate(true)


func get_persistent_state() -> Dictionary:
	return {
		"background_states": background_states.duplicate(true),
		"national_issues": national_issues.duplicate(true),
		"events": events.duplicate(true),
		"counters": counters.duplicate(true),
		"last_day_index": _last_day_index,
		"last_week_index": _last_week_index,
		"last_month_key": _last_month_key,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("background_states", {}) is Dictionary
		or not state.get("national_issues", {}) is Dictionary
		or not state.get("events", []) is Array
		or not state.get("counters", {}) is Dictionary
	):
		return false
	var restored_background: Dictionary = (
		state["background_states"] as Dictionary
	).duplicate(true)
	if restored_background.size() != background_states.size():
		return false
	for raw_id: Variant in restored_background:
		var person_id: String = str(raw_id)
		var record: Dictionary = restored_background[person_id] as Dictionary
		if (
			not _roster.background_characters.has(person_id)
			or not _world.regions.has(str(record.get("region_id", "")))
		):
			return false
	background_states = restored_background
	national_issues = (state["national_issues"] as Dictionary).duplicate(true)
	events = DataRecordUtils.to_dictionary_array(state["events"])
	counters = (state["counters"] as Dictionary).duplicate(true)
	_last_day_index = int(state.get("last_day_index", -1))
	_last_week_index = int(state.get("last_week_index", -1))
	_last_month_key = str(state.get("last_month_key", ""))
	while events.size() > EVENT_LIMIT:
		events.pop_front()
	return true


func summary() -> Dictionary:
	var employed: int = 0
	var unemployed: int = 0
	var region_counts: Dictionary = {}
	for raw_state: Variant in background_states.values():
		var state: Dictionary = raw_state as Dictionary
		if bool(state.get("employed", false)):
			employed += 1
		else:
			unemployed += 1
		var region_id: String = str(state.get("region_id", ""))
		region_counts[region_id] = int(region_counts.get(region_id, 0)) + 1
	var enterprise_statuses: Dictionary = {}
	for raw_state: Variant in _enterprise.enterprises.values():
		var state: Dictionary = raw_state as Dictionary
		var status: String = str(state.get("status", "unknown"))
		enterprise_statuses[status] = int(enterprise_statuses.get(status, 0)) + 1
	return {
		"background_employed": employed,
		"background_unemployed": unemployed,
		"background_by_region": region_counts,
		"enterprise_statuses": enterprise_statuses,
		"national_issue_count": national_issues.size(),
		"event_count": events.size(),
		"counters": counters.duplicate(true),
	}


func _process_day(total_hour: int, active_characters: Dictionary) -> void:
	counters["daily_batches"] = int(counters.get("daily_batches", 0)) + 1
	var provider_id: String = AlphaEnterpriseService.AGGREGATE_MARKET_ID
	var active_ids: Array[String] = []
	for raw_id: Variant in active_characters:
		active_ids.append(str(raw_id))
	active_ids.sort()
	for person_id: String in active_ids:
		if not _economy.entity_profiles.has(person_id):
			continue
		var profile: Dictionary = _economy.entity_profiles[person_id] as Dictionary
		var region_id: String = str(profile.get("region_id", ""))
		var region: Dictionary = _world.regions.get(region_id, {}) as Dictionary
		var living_index: int = int(region.get("living_cost_index", 100))
		var daily_cost: int = maxi(12, living_index * 18 / 100)
		var cash: int = _economy.ledger.owner_cash(person_id)
		if cash >= daily_cost:
			_economy.pay_life_costs(
				"world:life:%s:%d" % [person_id, total_hour / 24],
				person_id,
				provider_id,
				total_hour,
				daily_cost * 45 / 100,
				daily_cost * 35 / 100,
				daily_cost * 10 / 100,
				0,
				daily_cost * 10 / 100
			)
		elif cash < daily_cost:
			_append_event({
				"event_id": "event:cash_shortage:%s:%d" % [person_id, total_hour],
				"total_hour": total_hour,
				"actor_id": person_id,
				"fact_type": "cash_shortage",
				"summary": "人物的稳定生活预算无法完整支付。",
				"requires_decision": person_id == _roster.player_character_id,
			})


func _process_week(total_hour: int) -> void:
	counters["weekly_batches"] = int(counters.get("weekly_batches", 0)) + 1
	var week_index: int = total_hour / 168
	_process_background_people(week_index, total_hour)
	_process_enterprises(week_index, total_hour)
	_process_loans(week_index, total_hour)
	_process_policies(week_index, total_hour)
	_process_markets(week_index, total_hour)
	_process_national_issues(week_index, total_hour)


func _process_month(total_hour: int, active_characters: Dictionary) -> void:
	counters["monthly_batches"] = int(counters.get("monthly_batches", 0)) + 1
	_politics.expire_terms(total_hour, active_characters)
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if int(value.get("month", 0)) == 1:
		_roster.increment_living_ages()


func _process_background_people(week_index: int, total_hour: int) -> void:
	var person_ids: Array[String] = []
	for raw_id: Variant in background_states:
		person_ids.append(str(raw_id))
	person_ids.sort()
	var region_ids: Array[String] = []
	for raw_id: Variant in _world.regions:
		region_ids.append(str(raw_id))
	region_ids.sort()
	for index: int in range(person_ids.size()):
		var person_id: String = person_ids[index]
		var state: Dictionary = background_states[person_id] as Dictionary
		var phase: int = posmod(week_index * 17 + index * 13, 100)
		if bool(state.get("employed", false)) and phase < 3:
			state["employed"] = false
			state["occupation_or_unemployed"] = "unemployed"
			state["income_band"] = "none"
			state["current_major_state"] = "job_search"
			counters["background_job_changes"] = (
				int(counters.get("background_job_changes", 0)) + 1
			)
		elif not bool(state.get("employed", false)) and phase < 24:
			state["employed"] = true
			state["occupation_or_unemployed"] = "regional_worker"
			state["income_band"] = "low" if phase < 12 else "middle"
			state["current_major_state"] = "stable"
			counters["background_job_changes"] = (
				int(counters.get("background_job_changes", 0)) + 1
			)
		if phase == 51 and int(state.get("migration_cooldown", 0)) <= 0:
			var current_index: int = region_ids.find(str(state.get("region_id", "")))
			var destination: String = region_ids[(current_index + 1) % region_ids.size()]
			state["region_id"] = destination
			state["migration_tendency"] = "settled_after_move"
			state["migration_cooldown"] = 26
			counters["background_migrations"] = (
				int(counters.get("background_migrations", 0)) + 1
			)
			_append_event({
				"event_id": "event:background_migration:%s:%d" % [person_id, total_hour],
				"total_hour": total_hour,
				"actor_id": person_id,
				"target_id": destination,
				"fact_type": "migration",
				"summary": "一名背景人物因就业与生活条件迁往相邻地区。",
				"requires_decision": false,
			})
		else:
			state["migration_cooldown"] = maxi(
				0, int(state.get("migration_cooldown", 0)) - 1
			)
		var matters: Array = state.get("important_matters", []) as Array
		if bool(state.get("employed", false)):
			matters = [{"type": "employment", "updated_week": week_index}]
		else:
			matters = [{"type": "job_search", "updated_week": week_index}]
		if str(state.get("debt_band", "")) == "high":
			matters.append({"type": "debt_pressure", "updated_week": week_index})
		if matters.size() > BACKGROUND_MATTER_LIMIT:
			matters.resize(BACKGROUND_MATTER_LIMIT)
		state["important_matters"] = matters
		background_states[person_id] = state


func _process_enterprises(week_index: int, total_hour: int) -> void:
	var enterprise_ids: Array[String] = []
	for raw_id: Variant in _enterprise.enterprises:
		enterprise_ids.append(str(raw_id))
	enterprise_ids.sort()
	for organization_id: String in enterprise_ids:
		var state: Dictionary = _enterprise.enterprises[organization_id] as Dictionary
		if str(state.get("status", "")) not in AlphaEnterpriseService.ACTIVE_ENTERPRISE_STATUSES:
			continue
		_enterprise.aggregate_day(
			"world:enterprise_week:%s:%d" % [organization_id, week_index],
			organization_id,
			total_hour
		)
		state = _enterprise.enterprises[organization_id] as Dictionary
		if int(state.get("distress", 0)) >= 98:
			var failed: Dictionary = _enterprise.bankrupt(
				"world:bankrupt:%s:%d" % [organization_id, week_index],
				organization_id,
				total_hour,
				"持续现金不足且无法履行到期义务"
			)
			if bool(failed.get("success", false)):
				counters["enterprise_bankruptcies"] = (
					int(counters.get("enterprise_bankruptcies", 0)) + 1
				)
				_append_event({
					"event_id": "event:bankruptcy:%s:%d" % [organization_id, total_hour],
					"total_hour": total_hour,
					"actor_id": organization_id,
					"fact_type": "enterprise_bankruptcy",
					"summary": "企业因持续亏损进入破产处置。",
					"requires_decision": false,
				})


func _process_loans(week_index: int, total_hour: int) -> void:
	var contract_ids: Array[String] = []
	for raw_id: Variant in _economy.contracts.contracts:
		contract_ids.append(str(raw_id))
	contract_ids.sort()
	for contract_id: String in contract_ids:
		var contract: Dictionary = _economy.contracts.contracts[contract_id] as Dictionary
		if str(contract.get("contract_type", "")) != "loan":
			continue
		var status: String = str(contract.get("status", ""))
		if status in ["fulfilled", "settled", "enforced", "terminated"]:
			continue
		if status in ["active", "partially_fulfilled", "renegotiated"]:
			_economy.accrue_loan_interest(
				"world:interest:%s:%d" % [contract_id, week_index],
				contract_id,
				total_hour,
				7
			)
		contract = _economy.contracts.contracts[contract_id] as Dictionary
		var due_hour: int = int(contract.get("end_hour", 0))
		if total_hour >= due_hour and str(contract.get("status", "")) != "overdue":
			_economy.mark_loan_overdue(
				"world:overdue:%s" % contract_id, contract_id, total_hour
			)
		elif total_hour >= due_hour + 30 * 24 and str(contract.get("status", "")) == "overdue":
			var defaulted: Dictionary = _economy.default_loan(
				"world:default:%s" % contract_id,
				contract_id,
				total_hour,
				"逾期三十日且未完成重组或偿还"
			)
			if bool(defaulted.get("success", false)):
				counters["loan_defaults"] = int(counters.get("loan_defaults", 0)) + 1


func _process_policies(week_index: int, total_hour: int) -> void:
	var implementation_ids: Array[String] = []
	for raw_id: Variant in _politics.policy_implementations:
		implementation_ids.append(str(raw_id))
	implementation_ids.sort()
	for implementation_id: String in implementation_ids:
		var implementation: Dictionary = (
			_politics.policy_implementations[implementation_id] as Dictionary
		)
		if str(implementation.get("status", "")) != "implementing":
			continue
		var before: int = int(implementation.get("progress", 0))
		var advanced: Dictionary = _politics.advance_policy(
			"world:policy:%s:%d" % [implementation_id, week_index],
			implementation_id,
			total_hour,
			1
		)
		if bool(advanced.get("success", false)):
			var after_state: Dictionary = (
				_politics.policy_implementations[implementation_id] as Dictionary
			)
			if before < 100 and int(after_state.get("progress", 0)) >= 100:
				counters["policy_changes"] = int(counters.get("policy_changes", 0)) + 1


func _process_markets(week_index: int, total_hour: int) -> void:
	var region_ids: Array[String] = []
	for raw_id: Variant in _economy.markets:
		region_ids.append(str(raw_id))
	region_ids.sort()
	var good_ids: Array[String] = []
	for raw_id: Variant in _economy.goods:
		good_ids.append(str(raw_id))
	good_ids.sort()
	var region_id: String = region_ids[week_index % region_ids.size()]
	var good_id: String = good_ids[(week_index * 3) % good_ids.size()]
	var delta_bp: int = 120 if week_index % 4 == 0 else -118 if week_index % 4 == 2 else 0
	if delta_bp != 0:
		_economy.apply_market_shock(
			"world:market:%d" % week_index,
			region_id,
			good_id,
			delta_bp,
			7,
			"地区供需、运输与国家问题的周期变化",
			total_hour
		)


func _process_national_issues(week_index: int, total_hour: int) -> void:
	var issue_ids: Array[String] = []
	for raw_id: Variant in national_issues:
		issue_ids.append(str(raw_id))
	issue_ids.sort()
	for index: int in range(issue_ids.size()):
		var issue_id: String = issue_ids[index]
		var issue: Dictionary = national_issues[issue_id] as Dictionary
		var delta: int = -1 if (week_index + index) % 3 == 0 else 1
		issue["pressure"] = clampi(int(issue.get("pressure", 50)) + delta, 10, 95)
		issue["last_changed_hour"] = total_hour
		national_issues[issue_id] = issue


func _initialize_background_states() -> void:
	var region_ids: Array[String] = []
	for raw_id: Variant in _world.regions:
		region_ids.append(str(raw_id))
	region_ids.sort()
	var person_ids: Array[String] = _roster.get_background_ids()
	for index: int in range(person_ids.size()):
		var person_id: String = person_ids[index]
		var record: BackgroundCharacterData = _roster.get_background(person_id)
		var region_id: String = (
			record.region_id if _world.regions.has(record.region_id)
			else region_ids[index % region_ids.size()]
		)
		record.region_id = region_id
		background_states[person_id] = {
			"person_id": person_id,
			"region_id": region_id,
			"employed": index % 9 != 0,
			"occupation_or_unemployed": (
				record.occupation_id if index % 9 != 0 else "unemployed"
			),
			"income_band": "middle" if index % 4 == 0 else "low",
			"wealth_band": "low" if index % 5 != 0 else "middle",
			"debt_band": "high" if index % 13 == 0 else "moderate" if index % 5 == 0 else "none",
			"organization_ids": record.organization_ids.duplicate(),
			"important_relationship_summary": record.relationship_ids.slice(0, 3),
			"current_major_state": "stable",
			"migration_tendency": "low" if index % 4 else "medium",
			"migration_cooldown": 0,
			"important_matters": [],
		}


func _initialize_national_issues() -> void:
	for raw_country: Variant in _config.country_profiles():
		var country: Dictionary = raw_country as Dictionary
		for raw_issue: Variant in country.get("national_issues", []) as Array:
			var issue: Dictionary = (raw_issue as Dictionary).duplicate(true)
			issue["country_id"] = str(country.get("country_id", ""))
			issue["last_changed_hour"] = 0
			national_issues[str(issue.get("issue_id", ""))] = issue


func _append_event(event: Dictionary) -> void:
	events.append(event.duplicate(true))
	while events.size() > EVENT_LIMIT:
		events.pop_front()
