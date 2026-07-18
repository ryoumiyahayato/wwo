class_name V2LifeLoopSimulation
extends RefCounted
## Authoritative V2.2 composition root. It consumes the one SimulationClock hour signal.

signal state_changed(change_set: Dictionary)

const SCHEMA_VERSION: String = "v2_2_life_loop_1"
const DEFAULT_REVIEW_SAVE_PATH: String = "user://saves/v2_2_review_slot.json"
const PIERRE_ID: String = "character_pierre_lefevre"
const ALBERT_ID: String = "character_albert_dumont"
const JEANNE_ID: String = "jeanne"
const UNION_ID: String = "union_metalworkers_nord"

var clock: SimulationClock
var config := V2LifeLoopConfig.new()
var random: DeterministicRandomService
var schedule := V2ScheduleService.new()
var employment := V2EmploymentService.new()
var ledger := V2LedgerService.new()
var households := V2HouseholdService.new()
var conditions := V2ConditionService.new()
var relationships := V2RelationshipProgressService.new()
var organizations := V2OrganizationActivityService.new()
var notifications := V2NotificationService.new()

var scenario_id: String = ""
var selected_person_id: String = PIERRE_ID
var person_states: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _processed_hour_keys: Array[String] = []
var initialization_error: String = ""
var initialized: bool = false
var last_hour_processing_usec: int = 0
var maximum_hour_processing_usec: int = 0
var hours_processed: int = 0


func initialize(simulation_clock: SimulationClock = null) -> bool:
	initialization_error = ""
	if config.load_all() != OK:
		initialization_error = "; ".join(config.errors)
		return false
	if simulation_clock == null:
		var clock_config := SimulationClockConfig.new()
		if clock_config.load_from_file() != OK:
			initialization_error = clock_config.error_message
			return false
		clock = SimulationClock.new(clock_config)
	else:
		clock = simulation_clock
	var scenario: Dictionary = config.get_document("scenario")
	var start_hour: int = V2DateTime.total_hour_from_iso(
		str(scenario.get("start_datetime", ""))
	)
	if start_hour < 0:
		initialization_error = "V2.2 评审起始时间无效"
		return false
	var start_value: Dictionary = V2DateTime.from_total_hour(start_hour)
	if not clock.set_datetime_for_debug(
		int(start_value["year"]), int(start_value["month"]),
		int(start_value["day"]), int(start_value["hour"])
	):
		initialization_error = "无法把权威时钟定位到评审起点"
		return false
	if int(start_value.get("weekday", -1)) != 0:
		initialization_error = "1900-03-12 必须为星期一"
		return false
	scenario_id = str(scenario.get("scenario_id", ""))
	selected_person_id = str(scenario.get("default_selected_person_id", PIERRE_ID))
	random = DeterministicRandomService.new(int(scenario.get("random_seed", 2201900)))
	_initialize_state(start_hour)
	if not clock.hour_advanced.is_connected(_on_hour_advanced):
		clock.hour_advanced.connect(_on_hour_advanced)
	initialized = true
	return true


func reset_scenario() -> V2LifeLoopResult:
	if not initialized:
		return V2LifeLoopResult.fail("not_initialized", "生活模拟尚未初始化")
	var scenario: Dictionary = config.get_document("scenario")
	var start_hour: int = V2DateTime.total_hour_from_iso(str(scenario.get("start_datetime", "")))
	var value: Dictionary = V2DateTime.from_total_hour(start_hour)
	if not clock.set_datetime_for_debug(
		int(value["year"]), int(value["month"]), int(value["day"]), int(value["hour"])
	):
		return V2LifeLoopResult.fail("clock_reset_failed", "无法重置权威时间")
	random.set_seed(int(scenario.get("random_seed", 2201900)))
	selected_person_id = str(scenario.get("default_selected_person_id", PIERRE_ID))
	_initialize_state(start_hour)
	state_changed.emit({"reset": true})
	return V2LifeLoopResult.ok("V2.2 评审场景已重置")


func advance_real_seconds(delta_seconds: float) -> int:
	return 0 if clock == null else clock.advance_real_seconds(delta_seconds)


func advance_hours(hour_count: int) -> void:
	if clock != null:
		clock.advance_hours(hour_count)


func run_days(day_count: int) -> void:
	advance_hours(maxi(0, day_count) * 24)


func select_person(person_id: String) -> V2LifeLoopResult:
	if not person_states.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到观察人物", person_id, [person_id])
	selected_person_id = person_id
	state_changed.emit({"selected_person_id": person_id})
	return V2LifeLoopResult.ok("已切换观察人物", {}, [person_id])


func request_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int
) -> V2LifeLoopResult:
	if not person_states.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到当前人物", person_id, [person_id])
	var current_hour: int = clock.total_hours
	if start_hour < current_hour:
		return V2LifeLoopResult.fail(
			"past_time", "不能修改过去的日程",
			V2DateTime.iso_from_total_hour(start_hour), [person_id]
		)
	var person: Dictionary = config.person_record(person_id)
	var home: String = str(person.get("home_location_id", ""))
	var location_id: String = home
	var related_entity_id: String = ""
	var required_cash: int = 0
	var expected_effects: Dictionary = {}
	var value: Dictionary = V2DateTime.from_total_hour(start_hour)
	var hour: int = int(value["hour"])
	var fatigue: int = int(conditions.get_state(person_id).get("fatigue", 0))
	match activity_type:
		"overtime":
			var contract: Dictionary = employment.contract_for_person(person_id)
			if (
				str(contract.get("wage_period", "")) != "weekly"
				or hour != 17
				or duration_hours < 1
				or duration_hours > int(contract.get("overtime_max_hours_per_day", 0))
				or not (contract.get("work_days", []) as Array).has(int(value["weekday"]))
			):
				return V2LifeLoopResult.fail(
					"invalid_overtime_time",
					"加班必须紧接工作日 17:00，且不超过每日上限",
					V2DateTime.iso_from_total_hour(start_hour), [person_id]
				)
			if fatigue >= 950:
				return V2LifeLoopResult.fail(
					"fatigue_too_high", "疲劳达到 950，不能安排加班",
					"fatigue=%d" % fatigue, [person_id]
				)
			location_id = str(contract.get("workplace_location_id", ""))
			related_entity_id = str(contract.get("contract_id", ""))
			expected_effects = {
				"overtime_wage_centimes": (
					duration_hours * int(contract.get("overtime_rate_centimes_per_hour", 0))
				)
			}
		"authorized_leave":
			if start_hour > current_hour + 7 * 24:
				return V2LifeLoopResult.fail(
					"invalid_leave_date", "无薪请假只能安排未来 7 日内",
					V2DateTime.iso_from_total_hour(start_hour), [person_id]
				)
			var required_hours: int = 0
			for target_hour: int in range(start_hour, start_hour + duration_hours):
				if employment.is_required_work_hour(person_id, target_hour):
					required_hours += 1
			if required_hours == 0:
				return V2LifeLoopResult.fail(
					"invalid_leave_period", "请假必须覆盖上午、下午或全天工作段",
					V2DateTime.iso_from_total_hour(start_hour), [person_id]
				)
			location_id = home
			related_entity_id = str(
				employment.contract_for_person(person_id).get("contract_id", "")
			)
			expected_effects = {
				"unpaid_hours": required_hours,
				"demo_rule": "无薪请假自动批准",
			}
		"absence":
			var absence_hours: int = 0
			for target_hour: int in range(start_hour, start_hour + duration_hours):
				if employment.is_required_work_hour(person_id, target_hour):
					absence_hours += 1
			if absence_hours == 0:
				return V2LifeLoopResult.fail(
					"invalid_absence_period", "无故缺勤必须覆盖正式工作义务",
					V2DateTime.iso_from_total_hour(start_hour), [person_id]
				)
			location_id = home
			related_entity_id = str(
				employment.contract_for_person(person_id).get("contract_id", "")
			)
			expected_effects = {
				"unauthorized_absence_hours": absence_hours,
				"employment_risk_delta": absence_hours * int(
					(config.get_document("balance").get("condition", {}) as Dictionary)
					.get("employment_risk_absence_hour_delta", 25)
				),
			}
		"purchase_food", "purchase_essentials":
			var costs: Dictionary = config.get_document("living_costs")
			if (
				duration_hours != int(costs.get("purchase_duration_hours", 1))
				or hour < int(costs.get("business_open_hour", 6))
				or hour >= int(costs.get("business_close_hour", 21))
			):
				return V2LifeLoopResult.fail(
					"business_closed", "购买活动必须在 06:00—21:00 且耗时 1 小时",
					V2DateTime.iso_from_total_hour(start_hour), [person_id]
				)
			var package_key: String = (
				"food_package" if activity_type == "purchase_food"
				else "essentials_package"
			)
			required_cash = int((costs.get(package_key, {}) as Dictionary).get(
				"price_centimes", 0
			))
			var household: Dictionary = households.household_for_person(person_id)
			var cash: int = int(household.get("cash_centimes", 0))
			if cash < required_cash:
				return V2LifeLoopResult.fail(
					"insufficient_cash",
					"现金不足，还缺 %d 生丁" % (required_cash - cash),
					"purchase rejected before schedule", [person_id]
				)
			location_id = str(costs.get("purchase_location_id", ""))
			expected_effects = {
				"cash_cost_centimes": required_cash,
				"stock_person_days": 7,
			}
		"social_contact":
			var contact_check: V2LifeLoopResult = relationships.can_contact(
				person_id, JEANNE_ID, start_hour
			)
			if not contact_check.success:
				return contact_check
			if duration_hours != 1:
				return V2LifeLoopResult.fail(
					"invalid_duration", "联系关系人物固定耗时 1 小时", "", [person_id]
				)
			related_entity_id = JEANNE_ID
			expected_effects = {"familiarity": 5, "trust": 2, "stress": -20}
		"union_activity":
			var union_check: V2LifeLoopResult = organizations.can_attend(
				person_id, UNION_ID, start_hour, fatigue
			)
			if not union_check.success:
				return union_check
			if duration_hours != 2:
				return V2LifeLoopResult.fail(
					"invalid_duration", "工会例会固定持续 2 小时", "", [person_id]
				)
			location_id = "location:metalworkers_nord_hall"
			related_entity_id = UNION_ID
			expected_effects = {"union_participation": 5}
		"rest", "sleep":
			location_id = home
		_:
			return V2LifeLoopResult.fail(
				"unsupported_activity", "该活动暂不支持玩家安排", activity_type,
				[person_id]
			)
	var result: V2LifeLoopResult = schedule.schedule_player_activity(
		person_id, activity_type, start_hour, duration_hours, current_hour,
		location_id, related_entity_id, required_cash, expected_effects
	)
	if result.success:
		state_changed.emit({"schedule": person_id})
	return result


func request_next_activity(person_id: String, activity_type: String) -> V2LifeLoopResult:
	var suggestion: V2LifeLoopResult = suggest_next_activity(
		person_id, activity_type
	)
	if not suggestion.success:
		return suggestion
	return request_activity(
		person_id,
		activity_type,
		int(suggestion.data.get("start_hour", -1)),
		int(suggestion.data.get("duration_hours", 1))
	)


func suggest_next_activity(
	person_id: String, activity_type: String
) -> V2LifeLoopResult:
	if not person_states.has(person_id):
		return V2LifeLoopResult.fail(
			"unknown_person", "找不到当前人物", person_id, [person_id]
		)
	var current_hour: int = clock.total_hours
	var start_hour: int = -1
	var duration: int = 1
	match activity_type:
		"purchase_food", "purchase_essentials":
			start_hour = schedule.find_available_hour(
				person_id, current_hour + 1, current_hour + 7 * 24, 6, 21
			)
		"rest":
			start_hour = schedule.find_available_hour(
				person_id, current_hour + 1, current_hour + 48
			)
		"sleep":
			start_hour = _next_matching_hour(current_hour + 1, 22)
			duration = 8
		"social_contact":
			start_hour = schedule.find_available_hour(
				person_id, current_hour + 1, current_hour + 7 * 24, 18, 21
			)
		"overtime":
			start_hour = _next_workday_hour(person_id, current_hour + 1, 17)
			duration = 2
		"authorized_leave":
			start_hour = _next_workday_hour(person_id, current_hour + 1, 7)
			duration = 5
		"union_activity":
			start_hour = _next_weekday_hour(current_hour + 1, 2, 19)
			duration = 2
		"absence":
			start_hour = _next_workday_hour(person_id, current_hour + 1, 7)
			duration = 5
		_:
			return V2LifeLoopResult.fail(
				"unsupported_activity", "找不到该活动的快捷安排规则", activity_type,
				[person_id]
			)
	if start_hour < 0:
		return V2LifeLoopResult.fail(
			"no_available_time", "未来 7 日没有可用时间", activity_type, [person_id]
		)
	var person: Dictionary = config.person_record(person_id)
	var costs: Dictionary = config.get_document("living_costs")
	var required_cash: int = 0
	var location_id: String = str(person.get("home_location_id", ""))
	var expected_effects: String = "按活动配置逐小时结算"
	match activity_type:
		"purchase_food":
			required_cash = int(
				(costs.get("food_package", {}) as Dictionary).get(
					"price_centimes", 0
				)
			)
			location_id = str(costs.get("purchase_location_id", ""))
			expected_effects = "食品 +7 人日"
		"purchase_essentials":
			required_cash = int(
				(costs.get("essentials_package", {}) as Dictionary).get(
					"price_centimes", 0
				)
			)
			location_id = str(costs.get("purchase_location_id", ""))
			expected_effects = "生活用品 +7 人日"
		"overtime":
			var contract: Dictionary = employment.contract_for_person(person_id)
			location_id = str(contract.get("workplace_location_id", ""))
			expected_effects = "加班工资 +%d 生丁" % (
				duration * int(contract.get("overtime_rate_centimes_per_hour", 0))
			)
		"authorized_leave":
			expected_effects = "无薪请假；不记无故缺勤"
		"social_contact":
			expected_effects = "熟悉度 +5；信任 +2；压力 -20"
		"union_activity":
			location_id = "location:metalworkers_nord_hall"
			expected_effects = "工会参与度 +5"
		"rest":
			expected_effects = "疲劳 -25；压力 -10/小时"
		"sleep":
			expected_effects = "疲劳 -90；压力 -20/小时"
		"absence":
			expected_effects = "无故缺勤并增加就业风险"
	return V2LifeLoopResult.ok(
		"已生成活动建议",
		{
			"activity_type": activity_type,
			"start_hour": start_hour,
			"duration_hours": duration,
			"location_id": location_id,
			"required_cash_centimes": required_cash,
			"expected_effects": expected_effects,
		},
		[person_id]
	)


func cancel_activity(person_id: String, activity_id: String) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = schedule.cancel_player_activity(
		person_id, activity_id, clock.total_hours
	)
	if result.success:
		state_changed.emit({"schedule": person_id})
	return result


func get_person_state(person_id: String) -> Dictionary:
	var value: Variant = person_states.get(person_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func get_persistent_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"scenario_id": scenario_id,
		"current_datetime": V2DateTime.iso_from_total_hour(clock.total_hours),
		"time_speed": clock.speed_multiplier,
		"paused": clock.is_paused,
		"random_seed": str(random.get_seed()),
		"random_state": str(random.get_state()),
		"selected_person_id": selected_person_id,
		"person_states": person_states.duplicate(true),
		"person_locations": _person_locations(),
		"current_activities": _current_activities(),
		"future_schedules": schedule.schedules.duplicate(true),
		"recent_completed_activities": schedule.recent_completed_activities.duplicate(true),
		"employment_contracts": employment.contracts.duplicate(true),
		"attendance_records": employment.attendance_records.duplicate(true),
		"pay_period_states": employment.get_persistent_state(),
		"processed_pay_period_ids": employment.processed_pay_period_ids.duplicate(true),
		"households": households.households.duplicate(true),
		"cash": _household_field("cash_centimes"),
		"inventories": _inventory_snapshot(),
		"rent_due_dates": _household_field("next_rent_due_hour"),
		"rent_arrears": _household_field("rent_arrears_centimes"),
		"ledgers": ledger.get_persistent_state(),
		"health": _condition_field("health"),
		"fatigue": _condition_field("fatigue"),
		"stress": _condition_field("stress"),
		"employment_risk": _employment_risks(),
		"short_sleep_counters": _condition_field("consecutive_short_sleep_days"),
		"food_deficit_counters": _condition_field("consecutive_food_deficit_days"),
		"condition_state": conditions.get_persistent_state(),
		"relationships": relationships.get_persistent_state(),
		"union_participation": organizations.get_persistent_state(),
		"schedule_state": schedule.get_persistent_state(),
		"household_state": households.get_persistent_state(),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_hour_keys": _processed_hour_keys.duplicate(),
		"notifications": notifications.get_persistent_state(),
		"causal_events": conditions.causal_events.duplicate(true),
		"hours_processed": hours_processed,
	}


func validate_persistent_state(state: Dictionary) -> V2LifeLoopResult:
	if str(state.get("schema_version", "")) != SCHEMA_VERSION:
		return V2LifeLoopResult.fail(
			"incompatible_version", "存档版本不兼容",
			str(state.get("schema_version", "")), []
		)
	if str(state.get("scenario_id", "")) != scenario_id:
		return V2LifeLoopResult.fail(
			"incompatible_scenario", "存档不属于当前评审场景",
			str(state.get("scenario_id", "")), []
		)
	for field: String in [
		"person_states", "future_schedules", "employment_contracts",
		"pay_period_states", "households", "ledgers", "condition_state",
		"relationships", "union_participation", "schedule_state",
		"household_state", "processed_idempotency_keys", "notifications",
	]:
		if not state.get(field) is Dictionary:
			return V2LifeLoopResult.fail(
				"corrupt_save", "存档字段损坏：%s" % field, field
			)
	for field: String in [
		"attendance_records", "recent_completed_activities", "causal_events",
		"processed_hour_keys",
	]:
		if not state.get(field) is Array:
			return V2LifeLoopResult.fail(
				"corrupt_save", "存档字段损坏：%s" % field, field
			)
	var expected_people: Dictionary = {PIERRE_ID: true, ALBERT_ID: true}
	var restored_people: Dictionary = state["person_states"] as Dictionary
	if restored_people.size() != 2:
		return V2LifeLoopResult.fail("corrupt_save", "存档人物数量无效")
	for person_id: String in expected_people.keys():
		if not restored_people.has(person_id):
			return V2LifeLoopResult.fail(
				"broken_reference", "存档缺少评审人物：%s" % person_id, person_id
			)
	if not expected_people.has(str(state.get("selected_person_id", ""))):
		return V2LifeLoopResult.fail("broken_reference", "当前观察人物引用无效")
	var saved_hour: int = V2DateTime.total_hour_from_iso(str(state.get("current_datetime", "")))
	if saved_hour < 0:
		return V2LifeLoopResult.fail("corrupt_save", "存档权威时间无效")
	return V2LifeLoopResult.ok("存档结构有效", {"total_hour": saved_hour})


func restore_persistent_state(state: Dictionary) -> V2LifeLoopResult:
	var validation: V2LifeLoopResult = validate_persistent_state(state)
	if not validation.success:
		return validation
	var previous: Dictionary = get_persistent_state()
	var target_hour: int = int(validation.data.get("total_hour", -1))
	var target_value: Dictionary = V2DateTime.from_total_hour(target_hour)
	if not clock.set_datetime_for_debug(
		int(target_value["year"]), int(target_value["month"]),
		int(target_value["day"]), int(target_value["hour"])
	):
		return V2LifeLoopResult.fail("restore_error", "无法恢复权威时间")
	clock.set_speed(int(state.get("time_speed", 1)))
	clock.set_paused(bool(state.get("paused", true)))
	var restored: bool = (
		schedule.restore_persistent_state(state["schedule_state"] as Dictionary)
		and employment.restore_persistent_state(state["pay_period_states"] as Dictionary)
		and households.restore_persistent_state(state["household_state"] as Dictionary)
		and ledger.restore_persistent_state(state["ledgers"] as Dictionary)
		and conditions.restore_persistent_state(state["condition_state"] as Dictionary)
		and relationships.restore_persistent_state(state["relationships"] as Dictionary)
		and organizations.restore_persistent_state(state["union_participation"] as Dictionary)
		and notifications.restore_persistent_state(state["notifications"] as Dictionary)
	)
	if not restored:
		_restore_without_validation(previous)
		return V2LifeLoopResult.fail(
			"restore_error", "存档领域状态无效，当前运行状态未改变"
		)
	person_states = (state["person_states"] as Dictionary).duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_hour_keys.clear()
	for raw_key: Variant in state["processed_hour_keys"] as Array:
		var key: String = str(raw_key)
		if not processed_idempotency_keys.has(key):
			_restore_without_validation(previous)
			return V2LifeLoopResult.fail(
				"restore_error", "存档小时幂等索引不一致，当前运行状态未改变", key
			)
		_processed_hour_keys.append(key)
	selected_person_id = str(state.get("selected_person_id", PIERRE_ID))
	random.set_seed(int(state.get("random_seed", 2201900)))
	random.restore_state(int(state.get("random_state", random.get_state())))
	hours_processed = int(state.get("hours_processed", 0))
	var ledger_check: V2LifeLoopResult = ledger.validate_balances(households.households)
	if not ledger_check.success:
		_restore_without_validation(previous)
		return V2LifeLoopResult.fail(
			"ledger_restore_error", "存档账本与现金不一致，当前运行状态未改变",
			ledger_check.technical_message
		)
	state_changed.emit({"loaded": true})
	return V2LifeLoopResult.ok("载入完成")


func deterministic_digest() -> Dictionary:
	return {
		"current_datetime": V2DateTime.iso_from_total_hour(clock.total_hours),
		"person_states": person_states.duplicate(true),
		"households": households.households.duplicate(true),
		"ledger": ledger.transactions.duplicate(true),
		"conditions": conditions.person_states.duplicate(true),
		"attendance": employment.attendance_records.duplicate(true),
		"contracts": employment.contracts.duplicate(true),
		"relationships": relationships.relationships.duplicate(true),
		"organizations": organizations.memberships.duplicate(true),
		"processed": processed_idempotency_keys.duplicate(true),
		"pay_processed": employment.processed_pay_period_ids.duplicate(true),
		"household_processed": households.processed_idempotency_keys.duplicate(true),
	}


func ledger_consistency() -> V2LifeLoopResult:
	return ledger.validate_balances(households.households)


func get_debug_state() -> Dictionary:
	return {
		"authoritative_datetime": V2DateTime.iso_from_total_hour(clock.total_hours),
		"next_hour": V2DateTime.iso_from_total_hour(clock.total_hours + 1),
		"speed": clock.speed_multiplier,
		"paused": clock.is_paused,
		"selected_person_id": selected_person_id,
		"current_activity": schedule.activity_for_hour(selected_person_id, clock.total_hours),
		"next_activity": schedule.next_activity(selected_person_id, clock.total_hours),
		"future_48_hours": schedule.get_future_horizon(selected_person_id, clock.total_hours),
		"current_pay_period": employment.contract_for_person(selected_person_id).get("current_pay_period_id", ""),
		"processed_pay_keys": employment.processed_pay_period_ids.keys(),
		"rent_due": households.household_for_person(selected_person_id).get("next_rent_due_hour", -1),
		"daily_consumption_keys": households.processed_idempotency_keys.keys(),
		"cash": households.household_for_person(selected_person_id).get("cash_centimes", 0),
		"ledger_valid": ledger_consistency().success,
		"condition": conditions.get_state(selected_person_id),
		"generation_reason": schedule.generation_reasons.get(selected_person_id, ""),
		"schema_version": SCHEMA_VERSION,
		"recent_causal_events": conditions.recent_causes(
			selected_person_id, "fatigue", clock.total_hours, 6
		),
		"hours_processed": hours_processed,
		"last_hour_processing_usec": last_hour_processing_usec,
		"maximum_hour_processing_usec": maximum_hour_processing_usec,
	}


func set_household_cash(person_id: String, cash_centimes: int) -> V2LifeLoopResult:
	if cash_centimes < 0:
		return V2LifeLoopResult.fail("invalid_cash", "现金不能小于 0")
	var household_id: String = households.household_id_for_person(person_id)
	if household_id.is_empty():
		return V2LifeLoopResult.fail("unknown_household", "找不到人物住户", person_id)
	var household: Dictionary = households.households[household_id] as Dictionary
	# Developer adjustment remains ledger-visible and never mutates cash silently.
	var before: int = int(household.get("cash_centimes", 0))
	var amount: int = absi(cash_centimes - before)
	if amount == 0:
		return V2LifeLoopResult.ok("现金无需调整")
	var result: V2LifeLoopResult = ledger.post(
		households.households, household_id, person_id, amount,
		"income" if cash_centimes > before else "expense", "other_income"
		if cash_centimes > before else "other_expense",
		clock.total_hours, "developer", "developer_cash",
		"developer:cash:%s:%d:%d" % [person_id, clock.total_hours, ledger.transactions.size()],
		"开发者调整现金"
	)
	if result.success:
		state_changed.emit({"cash": person_id})
	return result


func set_inventory(person_id: String, item_type: String, value: int) -> V2LifeLoopResult:
	if item_type not in ["food", "essentials"] or value < 0:
		return V2LifeLoopResult.fail("invalid_inventory", "库存设置无效")
	var household_id: String = households.household_id_for_person(person_id)
	var household: Dictionary = households.households.get(household_id, {}) as Dictionary
	if household.is_empty():
		return V2LifeLoopResult.fail("unknown_household", "找不到人物住户")
	household["%s_stock_person_days" % item_type] = value
	households.households[household_id] = household
	state_changed.emit({"inventory": person_id})
	return V2LifeLoopResult.ok("库存已设置")


func set_condition(person_id: String, stat: String, value: int) -> V2LifeLoopResult:
	var current: Dictionary = conditions.get_state(person_id)
	if current.is_empty() or stat not in ["health", "fatigue", "stress"] or value < 0 or value > 1000:
		return V2LifeLoopResult.fail("invalid_condition", "状态设置无效")
	conditions.apply_delta(
		person_id, stat, value - int(current.get(stat, 0)), clock.total_hours,
		"开发者调整状态", "developer", stat
	)
	if stat == "fatigue" and value >= 950:
		_plan_life_needs(clock.total_hours, "major_health_state")
	state_changed.emit({"condition": person_id})
	return V2LifeLoopResult.ok("状态已设置")


func advance_to_datetime(iso_datetime: String) -> V2LifeLoopResult:
	var target_hour: int = V2DateTime.total_hour_from_iso(iso_datetime)
	if target_hour < clock.total_hours:
		return V2LifeLoopResult.fail(
			"past_time", "开发者日期不能跳回已经结算的过去", iso_datetime
		)
	if target_hour == clock.total_hours:
		return V2LifeLoopResult.ok("权威时间已经位于目标日期")
	advance_hours(target_hour - clock.total_hours)
	return V2LifeLoopResult.ok(
		"已逐小时推进到 %s" % V2DateTime.iso_from_total_hour(target_hour)
	)


func _initialize_state(start_hour: int) -> void:
	var balance: Dictionary = config.get_document("balance")
	var people: Array = config.person_records()
	ledger = V2LedgerService.new()
	ledger.configure(int(
		(balance.get("history_limits", {}) as Dictionary)
		.get("transactions_per_household", 256)
	))
	notifications = V2NotificationService.new()
	notifications.configure(int(
		(balance.get("history_limits", {}) as Dictionary).get("notifications", 160)
	))
	conditions = V2ConditionService.new()
	conditions.configure(balance, people)
	for raw_person: Variant in people:
		conditions.seed_sleep_history(
			str((raw_person as Dictionary).get("person_id", "")), start_hour, 7
		)
	employment = V2EmploymentService.new()
	employment.configure(config.contract_records(), start_hour, balance)
	households = V2HouseholdService.new()
	households.configure(
		config.household_records(), config.get_document("living_costs"), ledger
	)
	relationships = V2RelationshipProgressService.new()
	relationships.configure(
		config.get_document("people").get("relationships", []) as Array,
		balance.get("relationship", {}) as Dictionary
	)
	organizations = V2OrganizationActivityService.new()
	organizations.configure(
		config.get_document("people").get("organization_memberships", []) as Array,
		balance.get("union", {}) as Dictionary
	)
	schedule = V2ScheduleService.new()
	schedule.configure(people, employment, start_hour, balance)
	person_states.clear()
	for raw_person: Variant in people:
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		person_states[person_id] = {
			"person_id": person_id,
			"current_location_id": str(person.get("initial_location_id", "")),
			"current_activity_id": "",
			"last_completed_activity_id": "",
		}
	processed_idempotency_keys.clear()
	_processed_hour_keys.clear()
	last_hour_processing_usec = 0
	maximum_hour_processing_usec = 0
	hours_processed = 0
	_plan_life_needs(start_hour, "scenario_initialization")


func _on_hour_advanced(next_unsettled_hour: int) -> void:
	_settle_hour(next_unsettled_hour - 1)


func _settle_hour(total_hour: int) -> void:
	var started_usec: int = Time.get_ticks_usec()
	var hour_key: String = "hour:%s" % V2DateTime.iso_from_total_hour(total_hour)
	if processed_idempotency_keys.has(hour_key):
		return
	var balance: Dictionary = config.get_document("balance")
	var condition_rules: Dictionary = balance.get("condition", {}) as Dictionary
	var needs_health_replan: bool = false
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		schedule.ensure_future(person_id, total_hour, "future_horizon_below_24_hours")
		var activity: Dictionary = schedule.begin_hour(person_id, total_hour)
		if activity.is_empty():
			continue
		var activity_type: String = str(activity.get("activity_type", "free_time"))
		var activity_id: String = str(activity.get("activity_id", ""))
		var person_state: Dictionary = person_states[person_id] as Dictionary
		person_state["current_activity_id"] = activity_id
		_apply_activity_location(person_id, activity, total_hour)
		person_state = person_states[person_id] as Dictionary
		person_states[person_id] = person_state
		_record_employment_hour(
			person_id, total_hour, activity_type, activity, condition_rules
		)
		var fatigue_before: int = int(conditions.get_state(person_id).get("fatigue", 0))
		_apply_activity_condition(person_id, activity_type, activity, total_hour)
		if (
			fatigue_before < int(condition_rules.get("forced_rest_fatigue", 950))
			and int(conditions.get_state(person_id).get("fatigue", 0))
			>= int(condition_rules.get("forced_rest_fatigue", 950))
		):
			needs_health_replan = true
		var completed: Dictionary = schedule.finish_hour(person_id, total_hour, activity_id)
		if not completed.is_empty():
			_complete_activity(person_id, completed, total_hour)
			person_state = person_states[person_id] as Dictionary
			person_state["last_completed_activity_id"] = activity_id
			person_states[person_id] = person_state
	if needs_health_replan:
		_plan_life_needs(total_hour + 1, "major_health_state")
	var time_value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if int(time_value["hour"]) == int(
		config.get_document("living_costs").get("daily_consumption_hour", 6)
	):
		for person_id_variant: Variant in person_states.keys():
			var person_id: String = str(person_id_variant)
			var sleep_hours: int = conditions.settle_daily_sleep(person_id, total_hour)
			if sleep_hours < 6:
				notifications.add(
					"personal", "notification", "睡眠不足",
					"过去24小时仅睡眠 %d 小时" % sleep_hours, total_hour,
					"short_sleep:%s" % person_id, [person_id]
				)
		households.settle_daily_consumption(total_hour, conditions, notifications)
		_plan_life_needs(total_hour + 1, "daily_needs_changed")
	households.settle_due_rent(total_hour, ledger, conditions, notifications)
	employment.settle_due_pay(total_hour, households, ledger, notifications)
	processed_idempotency_keys[hour_key] = true
	_processed_hour_keys.append(hour_key)
	while _processed_hour_keys.size() > 168:
		processed_idempotency_keys.erase(_processed_hour_keys.pop_front())
	hours_processed += 1
	if int(time_value["hour"]) == 23:
		for person_id_variant: Variant in person_states.keys():
			schedule.ensure_future(str(person_id_variant), total_hour + 1, "new_day")
		_plan_life_needs(total_hour + 1, "new_day")
		schedule.prune_before(total_hour + 1 - 72)
	last_hour_processing_usec = Time.get_ticks_usec() - started_usec
	maximum_hour_processing_usec = maxi(
		maximum_hour_processing_usec, last_hour_processing_usec
	)
	state_changed.emit({
		"hour": total_hour,
		"current_datetime": V2DateTime.iso_from_total_hour(total_hour + 1),
	})


func _apply_activity_location(
	person_id: String, activity: Dictionary, _total_hour: int
) -> void:
	var person_state: Dictionary = person_states[person_id] as Dictionary
	person_state["current_location_id"] = str(activity.get(
		"location_id", person_state.get("current_location_id", "")
	))
	person_states[person_id] = person_state


func _record_employment_hour(
	person_id: String,
	total_hour: int,
	activity_type: String,
	_activity: Dictionary,
	condition_rules: Dictionary
) -> void:
	employment.record_hour(person_id, total_hour, activity_type, condition_rules)


func _apply_activity_condition(
	person_id: String,
	activity_type: String,
	_activity: Dictionary,
	total_hour: int
) -> void:
	conditions.apply_activity(person_id, activity_type, total_hour)


func _complete_activity(
	person_id: String, activity: Dictionary, total_hour: int
) -> void:
	var activity_type: String = str(activity.get("activity_type", ""))
	var activity_id: String = str(activity.get("activity_id", ""))
	var result := V2LifeLoopResult.ok()
	match activity_type:
		"purchase_food":
			result = households.purchase(
				person_id, "food", total_hour, activity_id, ledger, notifications
			)
		"purchase_essentials":
			result = households.purchase(
				person_id, "essentials", total_hour, activity_id, ledger, notifications
			)
		"social_contact":
			result = relationships.complete_contact(
				person_id, str(activity.get("related_entity_id", JEANNE_ID)),
				int(activity.get("start_hour", total_hour)), activity_id, notifications
			)
		"union_activity":
			result = organizations.complete_activity(
				person_id, str(activity.get("related_entity_id", UNION_ID)),
				total_hour, activity_id, notifications
			)
		"overtime":
			notifications.add(
				"personal", "event", "加班完成",
				"已完成 %d 小时加班" % (
					int(activity.get("end_hour", 0)) - int(activity.get("start_hour", 0))
				),
				total_hour, "overtime:%s" % person_id, [person_id]
			)
	if not result.success:
		schedule.set_activity_result(
			person_id, activity_id, false, result.to_dict(), result.error_code
		)
	elif not result.data.is_empty():
		schedule.set_activity_result(person_id, activity_id, true, result.data)


func _plan_life_needs(start_hour: int, reason: String) -> void:
	var costs: Dictionary = config.get_document("living_costs")
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		schedule.ensure_future(person_id, start_hour, reason)
		var person: Dictionary = config.person_record(person_id)
		var household: Dictionary = households.household_for_person(person_id)
		var condition: Dictionary = conditions.get_state(person_id)
		if int(condition.get("fatigue", 0)) >= 950:
			schedule.cancel_future_rule_activities(person_id, start_hour)
			var rest_hour: int = start_hour
			var rest_result: V2LifeLoopResult = schedule.schedule_rule_activity(
				person_id, "rest", rest_hour, 2,
				str(person.get("home_location_id", "")), "system"
			)
			if not rest_result.success:
				rest_hour = schedule.find_available_hour(
					person_id, start_hour, start_hour + 48
				)
				if rest_hour >= 0:
					rest_result = schedule.schedule_rule_activity(
						person_id, "rest", rest_hour, 2,
						str(person.get("home_location_id", "")), "system"
					)
			if rest_result.success:
				schedule.generation_reasons[person_id] = "major_health_state"
			continue
		if (
			int(household.get("food_stock_person_days", 0)) <= 1
			and not schedule.has_pending_activity(person_id, "purchase_food", start_hour)
			and int(household.get("cash_centimes", 0))
			>= int((costs.get("food_package", {}) as Dictionary).get("price_centimes", 0))
		):
			var food_hour: int = schedule.find_available_hour(
				person_id, start_hour, start_hour + 48, 6, 21
			)
			if food_hour >= 0:
				schedule.schedule_rule_activity(
					person_id, "purchase_food", food_hour, 1,
					str(costs.get("purchase_location_id", "")), "npc_rule", "",
					int((costs.get("food_package", {}) as Dictionary).get("price_centimes", 0))
				)
		if (
			int(household.get("essentials_stock_person_days", 0)) == 0
			and not schedule.has_pending_activity(
				person_id, "purchase_essentials", start_hour
			)
			and int(household.get("cash_centimes", 0))
			>= int((costs.get("essentials_package", {}) as Dictionary).get("price_centimes", 0))
		):
			var essentials_hour: int = schedule.find_available_hour(
				person_id, start_hour, start_hour + 48, 6, 21
			)
			if essentials_hour >= 0:
				schedule.schedule_rule_activity(
					person_id, "purchase_essentials", essentials_hour, 1,
					str(costs.get("purchase_location_id", "")), "npc_rule", "",
					int((costs.get("essentials_package", {}) as Dictionary).get("price_centimes", 0))
				)
		if person_id == PIERRE_ID:
			var union_hour: int = _next_weekday_hour(start_hour, 2, 19)
			if union_hour < start_hour + 7 * 24:
				schedule.schedule_rule_activity(
					person_id, "union_activity", union_hour, 2,
					"location:metalworkers_nord_hall", "npc_rule", UNION_ID
				)
			var relationship: Dictionary = relationships.get_relationship(person_id, JEANNE_ID)
			var last_contact: String = str(relationship.get("last_contact_datetime", ""))
			var contact_due: bool = (
				last_contact.is_empty()
				or start_hour - V2DateTime.total_hour_from_iso(last_contact) >= 168
			)
			if (
				contact_due
				and not schedule.has_pending_activity(person_id, "social_contact", start_hour)
			):
				var contact_hour: int = schedule.find_available_hour(
					person_id, start_hour, start_hour + 7 * 24, 18, 21
				)
				if contact_hour >= 0:
					schedule.schedule_rule_activity(
						person_id, "social_contact", contact_hour, 1,
						str(person.get("home_location_id", "")), "npc_rule", JEANNE_ID
					)


func _restore_without_validation(state: Dictionary) -> void:
	var target_hour: int = V2DateTime.total_hour_from_iso(str(state.get("current_datetime", "")))
	var target_value: Dictionary = V2DateTime.from_total_hour(target_hour)
	clock.set_datetime_for_debug(
		int(target_value["year"]), int(target_value["month"]),
		int(target_value["day"]), int(target_value["hour"])
	)
	clock.set_speed(int(state.get("time_speed", 1)))
	clock.set_paused(bool(state.get("paused", true)))
	schedule.restore_persistent_state(state["schedule_state"] as Dictionary)
	employment.restore_persistent_state(state["pay_period_states"] as Dictionary)
	households.restore_persistent_state(state["household_state"] as Dictionary)
	ledger.restore_persistent_state(state["ledgers"] as Dictionary)
	conditions.restore_persistent_state(state["condition_state"] as Dictionary)
	relationships.restore_persistent_state(state["relationships"] as Dictionary)
	organizations.restore_persistent_state(state["union_participation"] as Dictionary)
	notifications.restore_persistent_state(state["notifications"] as Dictionary)
	person_states = (state["person_states"] as Dictionary).duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_hour_keys.clear()
	for raw_key: Variant in state.get("processed_hour_keys", []) as Array:
		_processed_hour_keys.append(str(raw_key))
	selected_person_id = str(state.get("selected_person_id", PIERRE_ID))
	random.set_seed(int(state.get("random_seed", 2201900)))
	random.restore_state(int(state.get("random_state", random.get_state())))
	hours_processed = int(state.get("hours_processed", 0))


func _person_locations() -> Dictionary:
	var result: Dictionary = {}
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		result[person_id] = (
			person_states[person_id] as Dictionary
		).get("current_location_id", "")
	return result


func _current_activities() -> Dictionary:
	var result: Dictionary = {}
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		result[person_id] = schedule.activity_for_hour(person_id, clock.total_hours)
	return result


func _household_field(field: String) -> Dictionary:
	var result: Dictionary = {}
	for household_id_variant: Variant in households.households.keys():
		var household_id: String = str(household_id_variant)
		result[household_id] = (
			households.households[household_id] as Dictionary
		).get(field)
	return result


func _inventory_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for household_id_variant: Variant in households.households.keys():
		var household_id: String = str(household_id_variant)
		var household: Dictionary = households.households[household_id] as Dictionary
		result[household_id] = {
			"food_stock_person_days": household.get("food_stock_person_days", 0),
			"essentials_stock_person_days": household.get("essentials_stock_person_days", 0),
		}
	return result


func _condition_field(field: String) -> Dictionary:
	var result: Dictionary = {}
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		result[person_id] = conditions.get_state(person_id).get(field)
	return result


func _employment_risks() -> Dictionary:
	var result: Dictionary = {}
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		result[person_id] = employment.employment_risk(person_id)
	return result


func _next_matching_hour(start_hour: int, target_hour: int) -> int:
	for candidate: int in range(start_hour, start_hour + 8 * 24):
		if int(V2DateTime.from_total_hour(candidate)["hour"]) == target_hour:
			return candidate
	return -1


func _next_weekday_hour(start_hour: int, weekday: int, target_hour: int) -> int:
	for candidate: int in range(start_hour, start_hour + 8 * 24):
		var value: Dictionary = V2DateTime.from_total_hour(candidate)
		if int(value["weekday"]) == weekday and int(value["hour"]) == target_hour:
			return candidate
	return -1


func _next_workday_hour(person_id: String, start_hour: int, target_hour: int) -> int:
	var contract: Dictionary = employment.contract_for_person(person_id)
	for candidate: int in range(start_hour, start_hour + 8 * 24):
		var value: Dictionary = V2DateTime.from_total_hour(candidate)
		if (
			int(value["hour"]) == target_hour
			and (contract.get("work_days", []) as Array).has(int(value["weekday"]))
		):
			return candidate
	return -1
