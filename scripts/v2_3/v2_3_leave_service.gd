class_name V23LeaveService
extends RefCounted
## Authorized leave releases contract work obligations. It is not a time-occupying activity.

var authorizations: Dictionary = {}
var _next_sequence: int = 1


func reset() -> void:
	authorizations.clear()
	_next_sequence = 1


func authorize(
	person_id: String,
	start_hour: int,
	end_hour: int,
	current_hour: int,
	employment: V2EmploymentService
) -> V2LifeLoopResult:
	if person_id.is_empty() or employment == null:
		return V2LifeLoopResult.fail("leave_dependency_missing", "请假所需人物或劳动服务不可用")
	if start_hour < current_hour:
		return V2LifeLoopResult.fail("past_time", "不能为已经过去的时间请假")
	if end_hour <= start_hour:
		return V2LifeLoopResult.fail("invalid_leave_period", "请假结束时间必须晚于开始时间")
	if start_hour > current_hour + 7 * 24:
		return V2LifeLoopResult.fail("invalid_leave_date", "请假只能申请未来七日内的工作义务")
	var contract: Dictionary = employment.contract_for_person(person_id)
	if contract.is_empty() or str(contract.get("contract_status", "")) != "active":
		return V2LifeLoopResult.fail("employment_contract_missing", "人物当前没有可请假的有效劳动合同")
	var covered_hours: Array[int] = []
	for total_hour: int in range(start_hour, end_hour):
		if employment.is_required_work_hour(person_id, total_hour) and not covers(person_id, total_hour):
			covered_hours.append(total_hour)
	if covered_hours.is_empty():
		return V2LifeLoopResult.fail(
			"invalid_leave_period",
			"所选时段没有尚未豁免的合同工作义务"
		)
	var leave_id: String = "leave:v2_3:%06d" % _next_sequence
	_next_sequence += 1
	var record: Dictionary = {
		"leave_id": leave_id,
		"person_id": person_id,
		"contract_id": str(contract.get("contract_id", "")),
		"start_hour": start_hour,
		"end_hour": end_hour,
		"start_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"end_datetime": V2DateTime.iso_from_total_hour(end_hour),
		"covered_contract_hours": covered_hours.duplicate(),
		"covered_hour_count": covered_hours.size(),
		"paid": false,
		"status": "approved",
		"approved_hour": current_hour,
		"approved_datetime": V2DateTime.iso_from_total_hour(current_hour),
	}
	authorizations[leave_id] = record
	return V2LifeLoopResult.ok(
		"请假已批准：对应合同工时已解除，时间可自由安排",
		{"leave_authorization": record.duplicate(true)},
		[person_id, str(contract.get("contract_id", "")), leave_id]
	)


func covers(person_id: String, total_hour: int) -> bool:
	for raw_record: Variant in authorizations.values():
		var record: Dictionary = raw_record as Dictionary
		if (
			str(record.get("person_id", "")) == person_id
			and str(record.get("status", "")) == "approved"
			and total_hour in (record.get("covered_contract_hours", []) as Array)
		):
			return true
	return false


func records_for_person(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_record: Variant in authorizations.values():
		var record: Dictionary = raw_record as Dictionary
		if str(record.get("person_id", "")) == person_id:
			result.append(record.duplicate(true))
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get("start_hour", 0)) < int(second.get("start_hour", 0))
	)
	return result


func records_for_day(person_id: String, day_hour: int) -> Array[Dictionary]:
	var value: Dictionary = V2DateTime.from_total_hour(day_hour)
	if value.is_empty():
		return []
	var day_start: int = V2DateTime.to_total_hour({
		"year": int(value.get("year", 1900)),
		"month": int(value.get("month", 1)),
		"day": int(value.get("day", 1)),
		"hour": 0,
	})
	var result: Array[Dictionary] = []
	for record: Dictionary in records_for_person(person_id):
		if int(record.get("start_hour", 0)) < day_start + 24 and int(record.get("end_hour", 0)) > day_start:
			result.append(record)
	return result


func release_contract_schedule(record: Dictionary, schedule: V2ScheduleService) -> int:
	if schedule == null:
		return 0
	var person_id: String = str(record.get("person_id", ""))
	var leave_id: String = str(record.get("leave_id", ""))
	var leave_start: int = int(record.get("start_hour", -1))
	var leave_end: int = int(record.get("end_hour", -1))
	var original: Array = schedule.schedules.get(person_id, []) as Array
	var rebuilt: Array = []
	var changed: int = 0
	for raw_activity: Variant in original:
		var activity: Dictionary = raw_activity as Dictionary
		var activity_start: int = int(activity.get("start_hour", -1))
		var activity_end: int = int(activity.get("end_hour", -1))
		var overlaps: bool = activity_start < leave_end and activity_end > leave_start
		var releasable: bool = (
			str(activity.get("source", "")) == "contract"
			and str(activity.get("activity_type", "")) in ["work", "meal_break"]
			and str(activity.get("status", "")) in ["planned", "active"]
			and overlaps
		)
		if not releasable:
			rebuilt.append(activity)
			continue
		changed += 1
		if activity_start < leave_start:
			rebuilt.append(_activity_fragment(
				activity, activity_start, leave_start,
				"%s:before:%s" % [str(activity.get("activity_id", "")), leave_id]
			))
		if activity_end > leave_end:
			rebuilt.append(_activity_fragment(
				activity, leave_end, activity_end,
				"%s:after:%s" % [str(activity.get("activity_id", "")), leave_id]
			))
	rebuilt.sort_custom(func(first: Variant, second: Variant) -> bool:
		var first_activity: Dictionary = first as Dictionary
		var second_activity: Dictionary = second as Dictionary
		var first_start: int = int(first_activity.get("start_hour", 0))
		var second_start: int = int(second_activity.get("start_hour", 0))
		if first_start != second_start:
			return first_start < second_start
		return str(first_activity.get("activity_id", "")) < str(second_activity.get("activity_id", ""))
	)
	schedule.schedules[person_id] = rebuilt
	schedule.generation_reasons[person_id] = "authorized_leave_released_contract_time"
	return changed


func cancel_automatic_commutes_for_day(
	person_id: String,
	day_hour: int,
	current_hour: int,
	schedule: V2ScheduleService,
	travel: TravelExecutionService
) -> int:
	if schedule == null or travel == null:
		return 0
	var value: Dictionary = V2DateTime.from_total_hour(day_hour)
	if value.is_empty():
		return 0
	var day_start: int = V2DateTime.to_total_hour({
		"year": int(value.get("year", 1900)),
		"month": int(value.get("month", 1)),
		"day": int(value.get("day", 1)),
		"hour": 0,
	})
	var cancelled: int = 0
	var plan_ids: Array[String] = []
	for raw_plan_id: Variant in travel.travel_plans.keys():
		plan_ids.append(str(raw_plan_id))
	plan_ids.sort()
	for plan_id: String in plan_ids:
		var plan: Dictionary = travel.travel_plans[plan_id] as Dictionary
		var purpose: String = str(plan.get("purpose_activity_id", ""))
		var plan_start: int = int(plan.get("start_hour", -1))
		if (
			str(plan.get("person_id", "")) != person_id
			or str(plan.get("status", "")) != "planned"
			or plan_start < day_start
			or plan_start >= day_start + 24
			or not (purpose.begins_with("work:") or purpose.begins_with("return:"))
		):
			continue
		for raw_activity_id: Variant in plan.get("scheduled_activity_ids", []) as Array:
			schedule.cancel_activity_by_id(
				person_id, str(raw_activity_id), current_hour, "authorized_leave_replans_day"
			)
		plan["status"] = "cancelled"
		plan["interruption_reason"] = "authorized_leave_replans_day"
		travel._store_terminal_plan(plan_id, plan)
		cancelled += 1
	return cancelled


func get_persistent_state() -> Dictionary:
	return {
		"authorizations": authorizations.duplicate(true),
		"next_sequence": _next_sequence,
	}


func validate_persistent_state(state: Dictionary) -> bool:
	if not state.get("authorizations", {}) is Dictionary or int(state.get("next_sequence", 0)) < 1:
		return false
	for raw_record: Variant in (state.get("authorizations", {}) as Dictionary).values():
		if not raw_record is Dictionary:
			return false
		var record: Dictionary = raw_record as Dictionary
		if (
			str(record.get("leave_id", "")).is_empty()
			or str(record.get("person_id", "")).is_empty()
			or int(record.get("end_hour", 0)) <= int(record.get("start_hour", 0))
			or not record.get("covered_contract_hours", []) is Array
			or str(record.get("status", "")) != "approved"
		):
			return false
	return true


func restore_persistent_state(state: Dictionary) -> bool:
	if not validate_persistent_state(state):
		return false
	authorizations = (state.get("authorizations", {}) as Dictionary).duplicate(true)
	_next_sequence = int(state.get("next_sequence", 1))
	return true


static func _activity_fragment(
	activity: Dictionary,
	start_hour: int,
	end_hour: int,
	activity_id: String
) -> Dictionary:
	var fragment: Dictionary = activity.duplicate(true)
	fragment["activity_id"] = activity_id
	fragment["start_hour"] = start_hour
	fragment["end_hour"] = end_hour
	fragment["start_datetime"] = V2DateTime.iso_from_total_hour(start_hour)
	fragment["end_datetime"] = V2DateTime.iso_from_total_hour(end_hour)
	fragment["status"] = "planned"
	fragment["actual_effects"] = {}
	fragment["completed_datetime"] = ""
	fragment["cancellation_reason"] = ""
	fragment["interruption_reason"] = ""
	return fragment
