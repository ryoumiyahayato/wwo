class_name V23FormalSimulation
extends V23LifeLoopSimulation
## Formal V2.3 composition root with personal credit and non-blocking authorized leave.

var finance_config := V23FinanceConfig.new()
var finance := V23FinanceService.new()
var leave := V23LeaveService.new()


func initialize(simulation_clock: SimulationClock = null) -> bool:
	if not super.initialize(simulation_clock):
		return false
	leave.reset()
	var location_ids: Array[String] = []
	for raw_location: Variant in v2_3_config.location_records():
		location_ids.append(str((raw_location as Dictionary).get("location_id", "")))
	if finance_config.load_all(location_ids) != OK:
		return _fail_v2_3_initialization("; ".join(finance_config.errors))
	var finance_result: V2LifeLoopResult = finance.configure(
		finance_config, households, ledger
	)
	if not finance_result.success:
		return _fail_v2_3_initialization(finance_result.user_message)
	state_changed.emit({"formal_finance_initialized": true, "formal_leave_initialized": true})
	return true


func suggest_next_activity(
	person_id: String,
	activity_type: String
) -> V2LifeLoopResult:
	if activity_type != "authorized_leave":
		return super.suggest_next_activity(person_id, activity_type)
	var current_hour: int = clock.total_hours
	for day_offset: int in range(8):
		var candidate_day: int = _formal_day_start(current_hour + day_offset * 24)
		var covered: Array[int] = []
		for hour_offset: int in range(24):
			var total_hour: int = candidate_day + hour_offset
			if (
				total_hour >= current_hour
				and employment.is_required_work_hour(person_id, total_hour)
				and not leave.covers(person_id, total_hour)
			):
				covered.append(total_hour)
		if covered.is_empty():
			continue
		var start_hour: int = covered.front()
		var end_hour: int = covered.back() + 1
		return V2LifeLoopResult.ok(
			"已选择下一段合同工作义务",
			{
				"activity_type": "authorized_leave",
				"start_hour": start_hour,
				"duration_hours": end_hour - start_hour,
				"location_id": "",
				"required_cash_centimes": 0,
				"expected_effects": "解除所选时段内的合同工作义务；时间可自由安排",
			},
			[person_id]
		)
	return V2LifeLoopResult.fail("no_work_obligation", "未来七日没有可以申请解除的工作义务")


func request_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int
) -> V2LifeLoopResult:
	if activity_type != "authorized_leave":
		return super.request_activity(person_id, activity_type, start_hour, duration_hours)
	var result: V2LifeLoopResult = leave.authorize(
		person_id,
		start_hour,
		start_hour + duration_hours,
		clock.total_hours,
		employment
	)
	if not result.success:
		return result
	var record: Dictionary = result.data.get("leave_authorization", {}) as Dictionary
	leave.release_contract_schedule(record, schedule)
	_replan_commutes_for_leave_record(record)
	notifications.add(
		"personal",
		"event",
		"请假已批准",
		"对应合同工时已解除；这段时间不会被请假本身占用。",
		clock.total_hours,
		str(record.get("leave_id", "authorized_leave")),
		result.affected_entity_ids
	)
	state_changed.emit({"schedule": person_id, "employment": person_id, "leave": true})
	return result


func submit_loan_application(
	person_id: String,
	product_id: String,
	amount_centimes: int
) -> V2LifeLoopResult:
	var position: Dictionary = spatial_locations.position_for(person_id)
	if str(position.get("location_state", "")) != "at_location":
		return V2LifeLoopResult.fail("person_in_transit", "途中不能办理借款申请", person_id)
	var employment_contract: Dictionary = employment.contract_for_person(person_id)
	var result: V2LifeLoopResult = finance.submit_application(
		"v2_3:loan_application:%s:%s:%d:%d" % [
			person_id, product_id, amount_centimes, clock.total_hours,
		],
		person_id,
		product_id,
		amount_centimes,
		clock.total_hours,
		str(position.get("current_location_id", "")),
		_monthly_income_for(person_id),
		str(employment_contract.get("contract_status", "")) == "active"
	)
	if result.success:
		state_changed.emit({"finance": true, "loan_application": true})
	return result


func accept_loan_offer(application_id: String) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = finance.accept_offer(
		"v2_3:loan_accept:%s" % application_id,
		application_id,
		clock.total_hours
	)
	if result.success:
		notifications.add(
			"personal", "event", "借款已经放款", result.user_message,
			clock.total_hours, "loan_disbursed:%s" % application_id,
			result.affected_entity_ids
		)
		state_changed.emit({"finance": true, "households": true, "ledger": true})
	return result


func repay_personal_loan(contract_id: String, requested_centimes: int) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = finance.repay(
		"v2_3:loan_repay:%s:%d:%d" % [
			contract_id, requested_centimes, clock.total_hours,
		],
		contract_id,
		clock.total_hours,
		requested_centimes
	)
	if result.success:
		notifications.add(
			"personal", "event", "借款发生还款", result.user_message,
			clock.total_hours,
			"loan_repayment:%s:%d" % [contract_id, clock.total_hours],
			result.affected_entity_ids
		)
		state_changed.emit({"finance": true, "households": true, "ledger": true})
	return result


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["formal_finance_state"] = finance.get_persistent_state()
	state["formal_leave_state"] = leave.get_persistent_state()
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var base_result: V2LifeLoopResult = super.validate_v2_3_state(state)
	if not base_result.success:
		return base_result
	if state.has("formal_finance_state") and not finance.validate_persistent_state(
		state.get("formal_finance_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("corrupt_save", "正式金融存档字段损坏")
	if state.has("formal_leave_state") and not leave.validate_persistent_state(
		state.get("formal_leave_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("corrupt_save", "正式请假记录损坏")
	return V2LifeLoopResult.ok("V2.3 正式存档结构有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var validation: V2LifeLoopResult = validate_v2_3_state(state)
	if not validation.success:
		return validation
	var base_result: V2LifeLoopResult = super.restore_v2_3_state(state)
	if not base_result.success:
		return base_result
	var configured: V2LifeLoopResult = finance.configure(finance_config, households, ledger)
	if not configured.success:
		return configured
	if state.has("formal_finance_state") and not finance.restore_persistent_state(
		state.get("formal_finance_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("finance_restore_failed", "正式金融状态恢复失败")
	leave.reset()
	if state.has("formal_leave_state") and not leave.restore_persistent_state(
		state.get("formal_leave_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("leave_restore_failed", "正式请假状态恢复失败")
	var migrated_leave_count: int = _migrate_legacy_scheduled_leave()
	state_changed.emit({
		"loaded": true,
		"formal_finance": true,
		"formal_leave": true,
		"legacy_leave_migrated": migrated_leave_count,
	})
	return V2LifeLoopResult.ok("V2.3 正式存档已载入")


func determinism_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.determinism_snapshot()
	snapshot["formal_finance"] = finance.get_persistent_state()
	snapshot["formal_leave"] = leave.get_persistent_state()
	return snapshot


func _record_employment_hour(
	person_id: String,
	total_hour: int,
	activity_type: String,
	activity: Dictionary,
	condition_rules: Dictionary
) -> void:
	if leave.covers(person_id, total_hour):
		employment.record_hour(person_id, total_hour, "authorized_leave", condition_rules)
		return
	super._record_employment_hour(
		person_id, total_hour, activity_type, activity, condition_rules
	)


func _settle_hour(total_hour: int) -> void:
	super._settle_hour(total_hour)
	var condition_rules: Dictionary = (
		config.get_document("balance").get("condition", {}) as Dictionary
	)
	for person_id_variant: Variant in person_states.keys():
		var person_id: String = str(person_id_variant)
		if leave.covers(person_id, total_hour):
			employment.record_hour(
				person_id, total_hour, "authorized_leave", condition_rules
			)
	var finance_events: Array[Dictionary] = finance.process_hour(total_hour + 1)
	for event: Dictionary in finance_events:
		var event_type: String = str(event.get("event_type", ""))
		var title: String = str({
			"loan_offer": "借款方提出条件",
			"loan_rejected": "借款申请被拒绝",
			"loan_offer_expired": "借款条件已过期",
			"loan_overdue": "借款已经逾期",
			"loan_defaulted": "借款已经违约",
		}.get(event_type, "金融状态发生变化"))
		notifications.add(
			"personal",
			"notification" if event_type in ["loan_offer", "loan_overdue", "loan_defaulted"] else "event",
			title,
			str(event.get("summary", title)),
			int(event.get("total_hour", total_hour + 1)),
			str(event.get("event_id", "finance:%s:%d" % [event_type, total_hour + 1])),
			DataRecordUtils.to_string_array(event.get("entity_ids", []))
		)
	if not finance_events.is_empty():
		state_changed.emit({"finance": finance_events.size(), "households": true})


func _monthly_income_for(person_id: String) -> int:
	var contract: Dictionary = employment.contract_for_person(person_id)
	if contract.is_empty() or str(contract.get("contract_status", "")) != "active":
		return 0
	var base_wage: int = int(contract.get("base_wage_centimes", 0))
	var allowance: int = int(contract.get("allowance_centimes", 0))
	if str(contract.get("wage_period", "")) == "weekly":
		return int(base_wage * 52 / 12) + allowance
	return base_wage + allowance


func _replan_commutes_for_leave_record(record: Dictionary) -> void:
	var person_id: String = str(record.get("person_id", ""))
	var first_day: int = _formal_day_start(int(record.get("start_hour", clock.total_hours)))
	var last_day: int = _formal_day_start(int(record.get("end_hour", clock.total_hours + 1)) - 1)
	for day_start: int in range(first_day, last_day + 1, 24):
		if not _leave_covers_full_workday(person_id, day_start):
			continue
		leave.cancel_automatic_commutes_for_day(
			person_id, day_start, clock.total_hours, schedule, travel_execution
		)


func _leave_covers_full_workday(person_id: String, day_start: int) -> bool:
	var found_required_hour: bool = false
	for offset: int in range(24):
		var total_hour: int = day_start + offset
		if not employment.is_required_work_hour(person_id, total_hour):
			continue
		found_required_hour = true
		if not leave.covers(person_id, total_hour):
			return false
	return found_required_hour


func _migrate_legacy_scheduled_leave() -> int:
	var migrated_count: int = 0
	for person_id_variant: Variant in schedule.schedules.keys():
		var person_id: String = str(person_id_variant)
		var original: Array = schedule.schedules.get(person_id, []) as Array
		var retained: Array = []
		var migrated_records: Array[Dictionary] = []
		for raw_activity: Variant in original:
			var activity: Dictionary = raw_activity as Dictionary
			if str(activity.get("activity_type", "")) != "authorized_leave":
				retained.append(activity)
				continue
			if str(activity.get("status", "")) == "cancelled":
				continue
			var covered_hours: Array[int] = []
			for total_hour: int in range(
				int(activity.get("start_hour", 0)),
				int(activity.get("end_hour", 0))
			):
				if employment.is_required_work_hour(person_id, total_hour) and not leave.covers(person_id, total_hour):
					covered_hours.append(total_hour)
			if covered_hours.is_empty():
				continue
			var leave_id: String = "leave:legacy:%s" % str(activity.get("activity_id", migrated_count))
			var record: Dictionary = {
				"leave_id": leave_id,
				"person_id": person_id,
				"contract_id": str(employment.contract_for_person(person_id).get("contract_id", "")),
				"start_hour": int(activity.get("start_hour", 0)),
				"end_hour": int(activity.get("end_hour", 0)),
				"start_datetime": V2DateTime.iso_from_total_hour(int(activity.get("start_hour", 0))),
				"end_datetime": V2DateTime.iso_from_total_hour(int(activity.get("end_hour", 0))),
				"covered_contract_hours": covered_hours.duplicate(),
				"covered_hour_count": covered_hours.size(),
				"paid": false,
				"status": "approved",
				"approved_hour": clock.total_hours,
				"approved_datetime": V2DateTime.iso_from_total_hour(clock.total_hours),
				"migrated_from_activity_id": str(activity.get("activity_id", "")),
			}
			leave.authorizations[leave_id] = record
			migrated_records.append(record)
			migrated_count += 1
		schedule.schedules[person_id] = retained
		for record: Dictionary in migrated_records:
			leave.release_contract_schedule(record, schedule)
			_replan_commutes_for_leave_record(record)
	var retained_completed: Array[Dictionary] = []
	for activity: Dictionary in schedule.recent_completed_activities:
		if str(activity.get("activity_type", "")) != "authorized_leave":
			retained_completed.append(activity)
	schedule.recent_completed_activities = retained_completed
	return migrated_count


static func _formal_day_start(total_hour: int) -> int:
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if value.is_empty():
		return total_hour
	return V2DateTime.to_total_hour({
		"year": int(value.get("year", 1900)),
		"month": int(value.get("month", 1)),
		"day": int(value.get("day", 1)),
		"hour": 0,
	})
