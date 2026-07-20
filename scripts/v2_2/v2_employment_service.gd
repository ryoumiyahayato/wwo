class_name V2EmploymentService
extends RefCounted
## Contract obligations, attendance and pay-period settlement.

var contracts: Dictionary = {}
var attendance_records: Array[Dictionary] = []
var processed_pay_period_ids: Dictionary = {}
var _attendance_keys: Dictionary = {}
var _maximum_records: int = 512


func configure(contract_records: Array, start_hour: int, balance: Dictionary) -> void:
	contracts.clear()
	attendance_records.clear()
	processed_pay_period_ids.clear()
	_attendance_keys.clear()
	_maximum_records = int(
		(balance.get("history_limits", {}) as Dictionary).get("attendance_records", 512)
	)
	for raw_contract: Variant in contract_records:
		var contract: Dictionary = (raw_contract as Dictionary).duplicate(true)
		var normalized_work_days: Array[int] = []
		for raw_day: Variant in contract.get("work_days", []) as Array:
			normalized_work_days.append(int(raw_day))
		contract["work_days"] = normalized_work_days
		var normalized_segments: Array[Dictionary] = []
		for raw_segment: Variant in contract.get("shift_segments", []) as Array:
			var segment: Dictionary = (raw_segment as Dictionary).duplicate(true)
			segment["start_hour"] = int(segment.get("start_hour", 0))
			segment["end_hour"] = int(segment.get("end_hour", 0))
			normalized_segments.append(segment)
		contract["shift_segments"] = normalized_segments
		contract["employment_risk"] = int(contract.get("employment_risk", 0))
		contract["processed_pay_period_ids"] = []
		contract["current_pay_period_id"] = _period_id(contract, start_hour)
		contract["next_pay_hour"] = _next_pay_hour(contract, start_hour)
		contract["next_pay_datetime"] = V2DateTime.iso_from_total_hour(
			int(contract["next_pay_hour"])
		)
		contracts[str(contract.get("contract_id", ""))] = contract


func contract_for_person(person_id: String) -> Dictionary:
	for raw_contract: Variant in contracts.values():
		var contract: Dictionary = raw_contract as Dictionary
		if str(contract.get("person_id", "")) == person_id:
			return contract.duplicate(true)
	return {}


func is_required_work_hour(person_id: String, total_hour: int) -> bool:
	var contract: Dictionary = contract_for_person(person_id)
	if contract.is_empty() or str(contract.get("contract_status", "")) != "active":
		return false
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if value.is_empty() or not (contract.get("work_days", []) as Array).has(int(value["weekday"])):
		return false
	var hour: int = int(value["hour"])
	for raw_segment: Variant in contract.get("shift_segments", []) as Array:
		var segment: Dictionary = raw_segment as Dictionary
		if hour >= int(segment.get("start_hour", 0)) and hour < int(segment.get("end_hour", 0)):
			return true
	return false


func record_hour(
	person_id: String,
	total_hour: int,
	activity_type: String,
	condition_rules: Dictionary
) -> void:
	var contract: Dictionary = contract_for_person(person_id)
	if contract.is_empty():
		return
	var required: bool = is_required_work_hour(person_id, total_hour)
	var is_overtime: bool = activity_type == "overtime"
	if not required and not is_overtime:
		return
	var contract_id: String = str(contract.get("contract_id", ""))
	var key: String = "attendance:%s:%d" % [contract_id, total_hour]
	if _attendance_keys.has(key):
		return
	var attended: bool = required and activity_type == "work"
	var authorized_leave: bool = required and activity_type == "authorized_leave"
	var health_interruption: bool = required and activity_type == "rest"
	var unauthorized_absence: bool = required and not attended and not authorized_leave and not health_interruption
	var status: String = (
		"overtime" if is_overtime
		else (
			"attended" if attended
			else (
				"authorized_leave" if authorized_leave
				else ("health_interruption" if health_interruption else "unauthorized_absence")
			)
		)
	)
	attendance_records.append({
		"attendance_id": key,
		"contract_id": contract_id,
		"person_id": person_id,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"date": V2DateTime.date_from_total_hour(total_hour),
		"total_hour": total_hour,
		"required": required,
		"attended": attended,
		"authorized_leave": authorized_leave,
		"unauthorized_absence": unauthorized_absence,
		"health_interruption": health_interruption,
		"overtime": is_overtime,
		"status": status,
	})
	_attendance_keys[key] = true
	if unauthorized_absence:
		contract["employment_risk"] = clampi(
			int(contract.get("employment_risk", 0))
			+ int(condition_rules.get("employment_risk_absence_hour_delta", 25)),
			0, 1000
		)
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if required and _is_last_shift_hour(contract, int(value.get("hour", -1))):
		var date: String = V2DateTime.date_from_total_hour(total_hour)
		var required_count: int = 0
		var attended_count: int = 0
		for record: Dictionary in attendance_records:
			if (
				str(record.get("contract_id", "")) == contract_id
				and str(record.get("date", "")) == date
				and bool(record.get("required", false))
			):
				required_count += 1
				if bool(record.get("attended", false)):
					attended_count += 1
		if required_count > 0 and required_count == attended_count:
			contract["employment_risk"] = maxi(
				0,
				int(contract.get("employment_risk", 0))
				+ int(condition_rules.get("employment_risk_full_day_delta", -10))
			)
	contracts[contract_id] = contract
	while attendance_records.size() > _maximum_records:
		var removed: Dictionary = attendance_records.pop_front()
		_attendance_keys.erase(str(removed.get("attendance_id", "")))


func settle_due_pay(
	total_hour: int,
	households: V2HouseholdService,
	ledger: V2LedgerService,
	notifications: V2NotificationService
) -> Array[V2LifeLoopResult]:
	var results: Array[V2LifeLoopResult] = []
	for contract_id_variant: Variant in contracts.keys():
		var contract_id: String = str(contract_id_variant)
		var contract: Dictionary = contracts[contract_id] as Dictionary
		if int(contract.get("next_pay_hour", -1)) != total_hour:
			continue
		var result: V2LifeLoopResult = (
			_settle_weekly(contract, total_hour, households, ledger, notifications)
			if str(contract.get("wage_period", "")) == "weekly"
			else _settle_monthly(contract, total_hour, households, ledger, notifications)
		)
		results.append(result)
		if not result.success:
			continue
		contract = contracts[contract_id] as Dictionary
		contract["next_pay_hour"] = (
			total_hour + 168
			if str(contract.get("wage_period", "")) == "weekly"
			else V2DateTime.next_month_hour(total_hour, 1, 9)
		)
		contract["next_pay_datetime"] = V2DateTime.iso_from_total_hour(
			int(contract["next_pay_hour"])
		)
		contract["current_pay_period_id"] = _period_id(
			contract, int(contract["next_pay_hour"])
		)
		contracts[contract_id] = contract
	return results


func force_settle(
	contract_id: String,
	total_hour: int,
	households: V2HouseholdService,
	ledger: V2LedgerService,
	notifications: V2NotificationService
) -> V2LifeLoopResult:
	if not contracts.has(contract_id):
		return V2LifeLoopResult.fail("unknown_contract", "找不到劳动合同", contract_id)
	var contract: Dictionary = contracts[contract_id] as Dictionary
	return (
		_settle_weekly(contract, total_hour, households, ledger, notifications)
		if str(contract.get("wage_period", "")) == "weekly"
		else _settle_monthly(contract, total_hour, households, ledger, notifications)
	)


func today_summary(person_id: String, total_hour: int) -> Dictionary:
	var date: String = V2DateTime.date_from_total_hour(total_hour)
	var summary: Dictionary = {
		"required": 0,
		"attended": 0,
		"authorized_leave": 0,
		"unauthorized_absence": 0,
		"overtime": 0,
	}
	for record: Dictionary in attendance_records:
		if str(record.get("person_id", "")) != person_id or str(record.get("date", "")) != date:
			continue
		for field: String in summary.keys():
			if bool(record.get(field, false)):
				summary[field] = int(summary[field]) + 1
	return summary


func employment_risk(person_id: String) -> int:
	return int(contract_for_person(person_id).get("employment_risk", 0))


func change_contract_status(
	person_id: String,
	status: String,
	total_hour: int,
	cause_event_id: String
) -> V2LifeLoopResult:
	if status not in ["active", "resigned", "dismissed", "retired"]:
		return V2LifeLoopResult.fail(
			"invalid_contract_status", "劳动合同状态无效", status
		)
	for contract_id_variant: Variant in contracts.keys():
		var contract_id: String = str(contract_id_variant)
		var contract: Dictionary = contracts[contract_id] as Dictionary
		if str(contract.get("person_id", "")) != person_id:
			continue
		if str(contract.get("contract_status", "")) == status:
			return V2LifeLoopResult.ok(
				"劳动合同已经是目标状态",
				{"contract": contract.duplicate(true), "already_changed": true}
			)
		contract["contract_status"] = status
		contract["status_changed_datetime"] = V2DateTime.iso_from_total_hour(
			total_hour
		)
		contract["status_cause_event_id"] = cause_event_id
		contracts[contract_id] = contract
		return V2LifeLoopResult.ok(
			"劳动合同状态已更新",
			{"contract": contract.duplicate(true)},
			[person_id, contract_id]
		)
	return V2LifeLoopResult.fail(
		"contract_not_found", "人物没有可变更的劳动合同", person_id
	)


func get_persistent_state() -> Dictionary:
	return {
		"contracts": contracts.duplicate(true),
		"attendance_records": attendance_records.duplicate(true),
		"processed_pay_period_ids": processed_pay_period_ids.duplicate(true),
		"attendance_keys": _attendance_keys.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("contracts", {}) is Dictionary
		or not state.get("attendance_records", []) is Array
		or not state.get("processed_pay_period_ids", {}) is Dictionary
		or not state.get("attendance_keys", {}) is Dictionary
	):
		return false
	var restored_contracts: Dictionary = state["contracts"] as Dictionary
	var person_ids: Dictionary = {}
	for contract_id_variant: Variant in restored_contracts.keys():
		var contract_id: String = str(contract_id_variant)
		var raw_contract: Variant = restored_contracts[contract_id]
		if not raw_contract is Dictionary:
			return false
		var contract: Dictionary = raw_contract as Dictionary
		if contract_id != str(contract.get("contract_id", "")):
			return false
		var person_id: String = str(contract.get("person_id", ""))
		if person_id.is_empty() or person_ids.has(person_id):
			return false
		person_ids[person_id] = true
		var risk: int = int(contract.get("employment_risk", -1))
		if risk < 0 or risk > 1000 or int(contract.get("next_pay_hour", -1)) < 0:
			return false
	var restored_attendance: Array[Dictionary] = []
	var restored_attendance_keys: Dictionary = state["attendance_keys"] as Dictionary
	var seen_attendance: Dictionary = {}
	for raw_record: Variant in state["attendance_records"] as Array:
		if not raw_record is Dictionary:
			return false
		var record: Dictionary = raw_record as Dictionary
		var attendance_id: String = str(record.get("attendance_id", ""))
		if (
			attendance_id.is_empty()
			or seen_attendance.has(attendance_id)
			or not restored_attendance_keys.has(attendance_id)
			or not restored_contracts.has(str(record.get("contract_id", "")))
		):
			return false
		seen_attendance[attendance_id] = true
		restored_attendance.append(record.duplicate(true))
	if seen_attendance.size() != restored_attendance_keys.size():
		return false
	contracts = restored_contracts.duplicate(true)
	attendance_records = restored_attendance
	processed_pay_period_ids = (
		state["processed_pay_period_ids"] as Dictionary
	).duplicate(true)
	_attendance_keys = restored_attendance_keys.duplicate(true)
	return true


func _settle_weekly(
	contract: Dictionary,
	total_hour: int,
	households: V2HouseholdService,
	ledger: V2LedgerService,
	notifications: V2NotificationService
) -> V2LifeLoopResult:
	var period_id: String = V2DateTime.week_id(total_hour)
	var contract_id: String = str(contract.get("contract_id", ""))
	var key: String = "%s:wage:%s" % [contract_id, period_id]
	if processed_pay_period_ids.has(key):
		return V2LifeLoopResult.fail("duplicate_wage", "该周工资已经支付", key, [contract_id])
	var leave_hours: int = 0
	var absence_hours: int = 0
	var overtime_hours: int = 0
	for record: Dictionary in attendance_records:
		if (
			str(record.get("contract_id", "")) != contract_id
			or V2DateTime.week_id(int(record.get("total_hour", 0))) != period_id
		):
			continue
		if bool(record.get("authorized_leave", false)):
			leave_hours += 1
		if bool(record.get("unauthorized_absence", false)):
			absence_hours += 1
		if bool(record.get("overtime", false)):
			overtime_hours += 1
	var deduction: int = (
		leave_hours * int(contract.get("authorized_leave_deduction_centimes_per_hour", 0))
		+ absence_hours * int(contract.get("absence_deduction_centimes_per_hour", 0))
	)
	var base_payment: int = maxi(0, int(contract.get("base_wage_centimes", 0)) - deduction)
	var overtime_payment: int = overtime_hours * int(contract.get("overtime_rate_centimes_per_hour", 0))
	var person_id: String = str(contract.get("person_id", ""))
	var household_id: String = households.household_id_for_person(person_id)
	var entries: Array[Dictionary] = [
		_payroll_entry(
			household_id, person_id, base_payment, "wage", total_hour,
			contract_id, key, "%s:base" % key, "周薪到账"
		),
	]
	if overtime_payment > 0:
		entries.append(_payroll_entry(
			household_id, person_id, overtime_payment, "overtime_wage", total_hour,
			contract_id, key, "%s:overtime" % key, "加班工资到账"
		))
	var batch_result: V2LifeLoopResult = ledger.post_batch(
		households.households, entries, "周薪与加班工资到账"
	)
	if not batch_result.success:
		return batch_result
	processed_pay_period_ids[key] = true
	var processed: Array = contract.get("processed_pay_period_ids", []) as Array
	processed.append(period_id)
	while processed.size() > 128:
		var removed_period: String = str(processed.pop_front())
		processed_pay_period_ids.erase("%s:wage:%s" % [contract_id, removed_period])
	contract["processed_pay_period_ids"] = processed
	contracts[contract_id] = contract
	notifications.add(
		"personal", "event", "工资到账",
		"周薪 %d 生丁%s" % [
			base_payment,
			"，加班工资 %d 生丁" % overtime_payment if overtime_payment > 0 else "",
		],
		total_hour, "wage:%s" % contract_id, [person_id, household_id, contract_id]
	)
	batch_result.data.merge({
		"base_payment_centimes": base_payment,
		"overtime_payment_centimes": overtime_payment,
		"authorized_leave_hours": leave_hours,
		"unauthorized_absence_hours": absence_hours,
		"overtime_hours": overtime_hours,
		"idempotency_key": key,
	}, true)
	return batch_result


func _settle_monthly(
	contract: Dictionary,
	total_hour: int,
	households: V2HouseholdService,
	ledger: V2LedgerService,
	notifications: V2NotificationService
) -> V2LifeLoopResult:
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	var period_id: String = "%04d-%02d" % [int(value["year"]), int(value["month"])]
	var contract_id: String = str(contract.get("contract_id", ""))
	var key: String = "%s:salary:%s" % [contract_id, period_id]
	if processed_pay_period_ids.has(key):
		return V2LifeLoopResult.fail("duplicate_salary", "该月薪资已经支付", key, [contract_id])
	var person_id: String = str(contract.get("person_id", ""))
	var household_id: String = households.household_id_for_person(person_id)
	var salary: int = int(contract.get("base_wage_centimes", 0))
	var allowance: int = int(contract.get("allowance_centimes", 0))
	var entries: Array[Dictionary] = [
		_payroll_entry(
			household_id, person_id, salary, "salary", total_hour,
			contract_id, key, "%s:salary" % key, "月薪到账"
		),
	]
	if allowance > 0:
		entries.append(_payroll_entry(
			household_id, person_id, allowance, "allowance", total_hour,
			contract_id, key, "%s:allowance" % key, "交通津贴到账"
		))
	var batch_result: V2LifeLoopResult = ledger.post_batch(
		households.households, entries, "月薪与津贴到账"
	)
	if not batch_result.success:
		return batch_result
	processed_pay_period_ids[key] = true
	var processed: Array = contract.get("processed_pay_period_ids", []) as Array
	processed.append(period_id)
	while processed.size() > 128:
		var removed_period: String = str(processed.pop_front())
		processed_pay_period_ids.erase("%s:salary:%s" % [contract_id, removed_period])
	contract["processed_pay_period_ids"] = processed
	contracts[contract_id] = contract
	notifications.add(
		"personal", "event", "月薪到账",
		"月薪 %d 生丁，交通津贴 %d 生丁" % [salary, allowance],
		total_hour, "salary:%s" % contract_id, [person_id, household_id, contract_id]
	)
	batch_result.data.merge({
		"salary_centimes": salary,
		"allowance_centimes": allowance,
		"idempotency_key": key,
	}, true)
	return batch_result


func _next_pay_hour(contract: Dictionary, start_hour: int) -> int:
	var rule: Dictionary = contract.get("pay_day_rule", {}) as Dictionary
	if str(contract.get("wage_period", "")) == "weekly":
		for offset: int in range(0, 8 * 24):
			var candidate: int = start_hour + offset
			var value: Dictionary = V2DateTime.from_total_hour(candidate)
			if (
				int(value.get("weekday", -1)) == int(rule.get("weekday_monday_zero", 5))
				and int(value.get("hour", -1)) == int(rule.get("hour", 18))
			):
				return candidate
	var start: Dictionary = V2DateTime.from_total_hour(start_hour)
	var candidate_monthly: int = V2DateTime.to_total_hour({
		"year": int(start.get("year", 0)),
		"month": int(start.get("month", 0)),
		"day": int(rule.get("day_of_month", 1)),
		"hour": int(rule.get("hour", 9)),
	})
	if candidate_monthly < start_hour:
		return V2DateTime.next_month_hour(
			start_hour, int(rule.get("day_of_month", 1)), int(rule.get("hour", 9))
		)
	return candidate_monthly


func _period_id(contract: Dictionary, total_hour: int) -> String:
	if str(contract.get("wage_period", "")) == "weekly":
		return V2DateTime.week_id(total_hour)
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	return "%04d-%02d" % [int(value.get("year", 0)), int(value.get("month", 0))]


static func _is_last_shift_hour(contract: Dictionary, hour: int) -> bool:
	var last_end: int = 0
	for raw_segment: Variant in contract.get("shift_segments", []) as Array:
		last_end = maxi(last_end, int((raw_segment as Dictionary).get("end_hour", 0)))
	return hour == last_end - 1


static func _payroll_entry(
	household_id: String,
	person_id: String,
	amount_centimes: int,
	category: String,
	total_hour: int,
	contract_id: String,
	source_event_id: String,
	idempotency_key: String,
	description: String
) -> Dictionary:
	return {
		"household_id": household_id,
		"person_id": person_id,
		"amount_centimes": amount_centimes,
		"direction": "income",
		"category": category,
		"total_hour": total_hour,
		"source_entity_id": contract_id,
		"source_event_id": source_event_id,
		"idempotency_key": idempotency_key,
		"description": description,
	}
