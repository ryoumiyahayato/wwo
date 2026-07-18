class_name V2ScheduleService
extends RefCounted
## Incremental schedules with one authoritative primary activity per person-hour.

const SOURCE_PRIORITY: Dictionary = {
	"default_routine": 1,
	"npc_rule": 2,
	"contract": 3,
	"player": 4,
	"system": 5,
}
const PLAYER_TYPES: PackedStringArray = [
	"overtime", "authorized_leave", "rest", "sleep", "purchase_food",
	"purchase_essentials", "social_contact", "union_activity", "absence",
	"plan_route", "wait_for_transport", "travel_walk",
	"travel_urban_transit", "travel_regional_train", "arrive", "return_home",
	"meet_person", "social_visit", "workplace_conversation",
	"organization_conversation", "write_message", "read_message",
]
const TERMINAL_STATUSES: PackedStringArray = [
	"cancelled", "completed", "missed", "interrupted",
]
const ACTIVE_STATUSES: PackedStringArray = ["planned", "active"]

var schedules: Dictionary = {}
var recent_completed_activities: Array[Dictionary] = []
var generation_reasons: Dictionary = {}
var _people: Dictionary = {}
var _employment: V2EmploymentService
var _generated_days: Dictionary = {}
var _next_sequence: int = 1
var _minimum_horizon: int = 48
var _refill_threshold: int = 24
var _completed_limit: int = 256


func configure(
	people: Array,
	employment: V2EmploymentService,
	start_hour: int,
	balance: Dictionary
) -> void:
	schedules.clear()
	recent_completed_activities.clear()
	generation_reasons.clear()
	_people.clear()
	_generated_days.clear()
	_next_sequence = 1
	_employment = employment
	var time_rules: Dictionary = balance.get("time", {}) as Dictionary
	_minimum_horizon = int(time_rules.get("minimum_schedule_horizon_hours", 48))
	_refill_threshold = int(time_rules.get("schedule_refill_threshold_hours", 24))
	_completed_limit = int(
		(balance.get("history_limits", {}) as Dictionary).get("completed_activities", 256)
	)
	for raw_person: Variant in people:
		var person: Dictionary = (raw_person as Dictionary).duplicate(true)
		var person_id: String = str(person.get("person_id", ""))
		_people[person_id] = person
		schedules[person_id] = []
		generation_reasons[person_id] = "scenario_initialization"
		_generate_through(person_id, start_hour, start_hour + _minimum_horizon + 24)


func ensure_future(person_id: String, current_hour: int, reason: String) -> bool:
	if not schedules.has(person_id):
		return false
	var future_end: int = _future_end(person_id, current_hour)
	if future_end - current_hour >= _refill_threshold:
		return false
	generation_reasons[person_id] = reason
	_generate_through(person_id, current_hour, current_hour + _minimum_horizon + 24)
	return true


func get_future_horizon(person_id: String, current_hour: int) -> int:
	return maxi(0, _future_end(person_id, current_hour) - current_hour)


func activity_for_hour(person_id: String, total_hour: int) -> Dictionary:
	return _select_activity(person_id, total_hour, false)


func next_activity(person_id: String, current_hour: int) -> Dictionary:
	var current: Dictionary = activity_for_hour(person_id, current_hour)
	var search_start: int = current_hour + 1
	if not current.is_empty():
		search_start = int(current.get("end_hour", current_hour + 1))
	for hour: int in range(search_start, search_start + 72):
		var candidate: Dictionary = activity_for_hour(person_id, hour)
		if candidate.is_empty():
			continue
		if (
			current.is_empty()
			or str(candidate.get("activity_id", "")) != str(current.get("activity_id", ""))
		):
			return candidate
	return {}


func schedule_player_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int,
	current_hour: int,
	location_id: String,
	related_entity_id: String = "",
	required_cash_centimes: int = 0,
	expected_effects: Dictionary = {}
) -> V2LifeLoopResult:
	if not _people.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到当前人物", person_id, [person_id])
	if activity_type not in PLAYER_TYPES:
		return V2LifeLoopResult.fail(
			"unsupported_activity", "该活动不能由玩家安排", activity_type, [person_id]
		)
	if start_hour < current_hour:
		return V2LifeLoopResult.fail(
			"past_time", "不能修改过去的日程", V2DateTime.iso_from_total_hour(start_hour),
			[person_id]
		)
	if duration_hours < 1 or duration_hours > 12:
		return V2LifeLoopResult.fail(
			"invalid_duration", "活动持续时间无效", "duration=%d" % duration_hours,
			[person_id]
		)
	var conflict: V2LifeLoopResult = _validate_conflict(
		person_id, activity_type, start_hour, start_hour + duration_hours, "player"
	)
	if not conflict.success:
		return conflict
	var activity: Dictionary = _make_activity(
		person_id, activity_type, start_hour, start_hour + duration_hours,
		location_id, "player", related_entity_id, required_cash_centimes,
		expected_effects, current_hour
	)
	_append_activity(person_id, activity)
	generation_reasons[person_id] = "player_schedule_changed"
	return V2LifeLoopResult.ok(
		"活动已安排", {"activity": activity.duplicate(true)},
		[person_id, str(activity.get("activity_id", ""))]
	)


func schedule_rule_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int,
	location_id: String,
	source: String,
	related_entity_id: String = "",
	required_cash_centimes: int = 0
) -> V2LifeLoopResult:
	if not _people.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到当前人物", person_id, [person_id])
	if source not in ["npc_rule", "system"]:
		return V2LifeLoopResult.fail("invalid_source", "日程来源无效", source, [person_id])
	if duration_hours < 1 or start_hour < 0:
		return V2LifeLoopResult.fail("invalid_duration", "规则活动时间无效", activity_type)
	for raw_existing: Variant in schedules.get(person_id, []) as Array:
		var existing: Dictionary = raw_existing as Dictionary
		if (
			str(existing.get("activity_type", "")) == activity_type
			and int(existing.get("start_hour", -1)) == start_hour
			and int(existing.get("end_hour", -1)) == start_hour + duration_hours
			and str(existing.get("source", "")) == source
			and str(existing.get("status", "")) in ACTIVE_STATUSES
		):
			return V2LifeLoopResult.ok(
				"规则活动已经存在",
				{"activity": existing.duplicate(true), "already_scheduled": true},
				[person_id, str(existing.get("activity_id", ""))]
			)
	var conflict: V2LifeLoopResult = _validate_conflict(
		person_id, activity_type, start_hour, start_hour + duration_hours, source
	)
	if not conflict.success:
		return conflict
	var activity: Dictionary = _make_activity(
		person_id, activity_type, start_hour, start_hour + duration_hours,
		location_id, source, related_entity_id, required_cash_centimes, {}, start_hour
	)
	_append_activity(person_id, activity)
	generation_reasons[person_id] = "%s_need" % activity_type
	return V2LifeLoopResult.ok(
		"规则活动已安排", {"activity": activity.duplicate(true)}, [person_id]
	)


func can_schedule_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	duration_hours: int,
	source: String
) -> V2LifeLoopResult:
	if not _people.has(person_id):
		return V2LifeLoopResult.fail("unknown_person", "找不到当前人物", person_id, [person_id])
	if duration_hours < 1 or start_hour < 0:
		return V2LifeLoopResult.fail("invalid_duration", "活动时间无效", activity_type)
	if source not in SOURCE_PRIORITY:
		return V2LifeLoopResult.fail("invalid_source", "日程来源无效", source)
	return _validate_conflict(
		person_id, activity_type, start_hour, start_hour + duration_hours, source
	)


func merge_activity_metadata(
	person_id: String, activity_id: String, metadata: Dictionary
) -> bool:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if str(activity.get("activity_id", "")) != activity_id:
			continue
		for raw_key: Variant in metadata.keys():
			activity[str(raw_key)] = metadata[raw_key]
		person_schedule[index] = activity
		schedules[person_id] = person_schedule
		return true
	return false


func cancel_future_activity_types(
	person_id: String,
	activity_types: PackedStringArray,
	current_hour: int,
	reason: String
) -> int:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	var cancelled: int = 0
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if (
			str(activity.get("activity_type", "")) in activity_types
			and int(activity.get("start_hour", -1)) >= current_hour
			and str(activity.get("status", "")) == "planned"
		):
			activity["status"] = "cancelled"
			activity["cancellation_reason"] = reason
			person_schedule[index] = activity
			cancelled += 1
	schedules[person_id] = person_schedule
	return cancelled


func cancel_activity_by_id(
	person_id: String, activity_id: String, current_hour: int, reason: String
) -> V2LifeLoopResult:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if str(activity.get("activity_id", "")) != activity_id:
			continue
		if int(activity.get("start_hour", -1)) <= current_hour:
			return V2LifeLoopResult.fail(
				"activity_started", "活动已经开始，不能静默取消", activity_id,
				[person_id, activity_id]
			)
		if str(activity.get("status", "")) != "planned":
			return V2LifeLoopResult.fail(
				"activity_not_planned", "活动已经结束或取消", activity_id,
				[person_id, activity_id]
			)
		activity["status"] = "cancelled"
		activity["cancellation_reason"] = reason
		person_schedule[index] = activity
		schedules[person_id] = person_schedule
		return V2LifeLoopResult.ok("活动已取消", {"activity": activity}, [person_id, activity_id])
	return V2LifeLoopResult.fail(
		"activity_not_found", "找不到活动", activity_id, [person_id, activity_id]
	)


func find_available_hour(
	person_id: String,
	start_hour: int,
	end_hour: int,
	allowed_start_hour: int = 0,
	allowed_end_hour: int = 24,
	duration_hours: int = 1
) -> int:
	var duration: int = maxi(1, duration_hours)
	for candidate: int in range(start_hour, end_hour):
		var fits: bool = true
		for offset: int in range(duration):
			var hour_value: int = candidate + offset
			if hour_value >= end_hour:
				fits = false
				break
			var value: Dictionary = V2DateTime.from_total_hour(hour_value)
			var hour: int = int(value.get("hour", -1))
			if hour < allowed_start_hour or hour >= allowed_end_hour:
				fits = false
				break
			var activity: Dictionary = activity_for_hour(person_id, hour_value)
			if str(activity.get("source", "")) != "default_routine":
				fits = false
				break
		if fits:
			return candidate
	return -1


func has_pending_activity(
	person_id: String, activity_type: String, current_hour: int
) -> bool:
	for raw_activity: Variant in schedules.get(person_id, []) as Array:
		var activity: Dictionary = raw_activity as Dictionary
		if (
			str(activity.get("activity_type", "")) == activity_type
			and str(activity.get("status", "")) in ACTIVE_STATUSES
			and int(activity.get("end_hour", -1)) > current_hour
		):
			return true
	return false


func cancel_future_rule_activities(person_id: String, current_hour: int) -> int:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	var cancelled: int = 0
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if (
			str(activity.get("source", "")) == "npc_rule"
			and int(activity.get("start_hour", -1)) >= current_hour
			and str(activity.get("status", "")) == "planned"
		):
			activity["status"] = "cancelled"
			activity["cancellation_reason"] = "system_health_rest"
			person_schedule[index] = activity
			cancelled += 1
	schedules[person_id] = person_schedule
	return cancelled


func prune_before(cutoff_hour: int) -> void:
	for person_id_variant: Variant in schedules.keys():
		var person_id: String = str(person_id_variant)
		var retained: Array = []
		for raw_activity: Variant in schedules[person_id] as Array:
			var activity: Dictionary = raw_activity as Dictionary
			var terminal: bool = str(activity.get("status", "")) in TERMINAL_STATUSES
			if terminal and int(activity.get("end_hour", 0)) < cutoff_hour:
				continue
			retained.append(activity)
		schedules[person_id] = retained
	for generated_key_variant: Variant in _generated_days.keys():
		var generated_key: String = str(generated_key_variant)
		var generated_date: String = generated_key.right(10)
		var generated_hour: int = V2DateTime.total_hour_from_iso("%sT00:00:00" % generated_date)
		if generated_hour >= 0 and generated_hour + 24 < cutoff_hour:
			_generated_days.erase(generated_key_variant)


func cancel_player_activity(
	person_id: String, activity_id: String, current_hour: int
) -> V2LifeLoopResult:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if str(activity.get("activity_id", "")) != activity_id:
			continue
		if str(activity.get("source", "")) != "player":
			return V2LifeLoopResult.fail(
				"not_player_activity", "只能取消玩家安排的活动", activity_id, [person_id]
			)
		if int(activity.get("start_hour", -1)) <= current_hour:
			return V2LifeLoopResult.fail(
				"activity_started", "活动已经开始，不能取消", activity_id, [person_id]
			)
		if str(activity.get("status", "")) != "planned":
			return V2LifeLoopResult.fail(
				"activity_not_planned", "活动已经结束或取消", activity_id, [person_id]
			)
		activity["status"] = "cancelled"
		activity["cancellation_reason"] = "player_cancelled"
		person_schedule[index] = activity
		schedules[person_id] = person_schedule
		return V2LifeLoopResult.ok("活动已取消", {"activity": activity}, [person_id, activity_id])
	return V2LifeLoopResult.fail(
		"activity_not_found", "找不到活动", activity_id, [person_id, activity_id]
	)


func begin_hour(person_id: String, total_hour: int) -> Dictionary:
	var selected: Dictionary = activity_for_hour(person_id, total_hour)
	if selected.is_empty():
		return {}
	var person_schedule: Array = schedules[person_id] as Array
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if str(activity.get("activity_id", "")) != str(selected.get("activity_id", "")):
			continue
		activity["status"] = "active"
		var actual: Dictionary = activity.get("actual_effects", {}) as Dictionary
		actual["processed_hours"] = int(actual.get("processed_hours", 0)) + 1
		activity["actual_effects"] = actual
		person_schedule[index] = activity
		selected = activity.duplicate(true)
		break
	schedules[person_id] = person_schedule
	return selected


func finish_hour(person_id: String, total_hour: int, selected_activity_id: String) -> Dictionary:
	var person_schedule: Array = schedules[person_id] as Array
	var completed: Dictionary = {}
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if int(activity.get("end_hour", 0)) > total_hour + 1:
			continue
		if str(activity.get("status", "")) not in ACTIVE_STATUSES:
			continue
		var processed_hours: int = int(
			(activity.get("actual_effects", {}) as Dictionary).get("processed_hours", 0)
		)
		var duration: int = int(activity.get("end_hour", 0)) - int(activity.get("start_hour", 0))
		if processed_hours >= duration:
			activity["status"] = "completed"
			activity["completed_datetime"] = V2DateTime.iso_from_total_hour(total_hour + 1)
		else:
			activity["status"] = "missed"
			activity["interruption_reason"] = "higher_priority_activity"
		person_schedule[index] = activity
		if str(activity.get("activity_id", "")) == selected_activity_id:
			completed = activity.duplicate(true)
		recent_completed_activities.append(activity.duplicate(true))
	schedules[person_id] = person_schedule
	while recent_completed_activities.size() > _completed_limit:
		recent_completed_activities.pop_front()
	return completed


func timeline_for_day(person_id: String, day_hour: int, current_hour: int) -> Array[Dictionary]:
	var day_value: Dictionary = V2DateTime.from_total_hour(day_hour)
	if day_value.is_empty():
		return []
	var start: int = V2DateTime.to_total_hour({
		"year": int(day_value["year"]),
		"month": int(day_value["month"]),
		"day": int(day_value["day"]),
		"hour": 0,
	})
	var result: Array[Dictionary] = []
	for total_hour: int in range(start, start + 24):
		var activity: Dictionary = _select_activity(person_id, total_hour, true)
		if activity.is_empty():
			continue
		var stored_status: String = str(activity.get("status", "planned"))
		var segment_status: String = stored_status
		if stored_status in ACTIVE_STATUSES:
			segment_status = (
				"completed" if total_hour < current_hour
				else ("active" if total_hour == current_hour else "planned")
			)
		var can_merge: bool = (
			not result.is_empty()
			and str(result[-1].get("activity_id", "")) == str(activity.get("activity_id", ""))
			and int(result[-1].get("end_hour", -1)) == total_hour
			and str(result[-1].get("display_status", "")) == segment_status
		)
		if can_merge:
			result[-1]["end_hour"] = total_hour + 1
			result[-1]["end_datetime"] = V2DateTime.iso_from_total_hour(total_hour + 1)
		else:
			var segment: Dictionary = activity.duplicate(true)
			segment["start_hour"] = total_hour
			segment["end_hour"] = total_hour + 1
			segment["start_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
			segment["end_datetime"] = V2DateTime.iso_from_total_hour(total_hour + 1)
			segment["display_status"] = segment_status
			result.append(segment)
	return result


func set_activity_result(
	person_id: String,
	activity_id: String,
	success: bool,
	actual_effects: Dictionary,
	reason: String = ""
) -> void:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if str(activity.get("activity_id", "")) != activity_id:
			continue
		var merged_effects: Dictionary = activity.get("actual_effects", {}) as Dictionary
		merged_effects.merge(actual_effects, true)
		activity["actual_effects"] = merged_effects
		if not success:
			activity["status"] = "missed"
			activity["interruption_reason"] = reason
		person_schedule[index] = activity
		break
	schedules[person_id] = person_schedule


func clear_future_player_schedule(person_id: String, current_hour: int) -> int:
	var person_schedule: Array = schedules.get(person_id, []) as Array
	var cleared: int = 0
	for index: int in range(person_schedule.size()):
		var activity: Dictionary = person_schedule[index] as Dictionary
		if (
			str(activity.get("source", "")) == "player"
			and int(activity.get("start_hour", -1)) > current_hour
			and str(activity.get("status", "")) == "planned"
		):
			activity["status"] = "cancelled"
			activity["cancellation_reason"] = "developer_clear"
			person_schedule[index] = activity
			cleared += 1
	schedules[person_id] = person_schedule
	return cleared


func get_persistent_state() -> Dictionary:
	return {
		"schedules": schedules.duplicate(true),
		"recent_completed_activities": recent_completed_activities.duplicate(true),
		"generation_reasons": generation_reasons.duplicate(true),
		"generated_days": _generated_days.duplicate(true),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("schedules", {}) is Dictionary
		or not state.get("recent_completed_activities", []) is Array
		or not state.get("generation_reasons", {}) is Dictionary
		or not state.get("generated_days", {}) is Dictionary
		or int(state.get("next_sequence", 0)) < 1
	):
		return false
	var restored_schedules: Dictionary = state["schedules"] as Dictionary
	if restored_schedules.size() != _people.size():
		return false
	var seen_activity_ids: Dictionary = {}
	for person_id_variant: Variant in restored_schedules.keys():
		var person_id: String = str(person_id_variant)
		if not _people.has(person_id):
			return false
		var raw_schedule: Variant = restored_schedules[person_id]
		if not raw_schedule is Array:
			return false
		var previous_start: int = -1
		for raw_activity: Variant in raw_schedule as Array:
			if not raw_activity is Dictionary:
				return false
			var activity: Dictionary = raw_activity as Dictionary
			var activity_id: String = str(activity.get("activity_id", ""))
			var start_hour: int = int(activity.get("start_hour", -1))
			var end_hour: int = int(activity.get("end_hour", -1))
			if (
				activity_id.is_empty()
				or seen_activity_ids.has(activity_id)
				or str(activity.get("person_id", "")) != person_id
				or end_hour <= start_hour
				or start_hour < previous_start
				or str(activity.get("source", "")) not in SOURCE_PRIORITY
				or str(activity.get("status", "")) not in [
					"planned", "active", "cancelled", "completed", "missed", "interrupted",
				]
			):
				return false
			previous_start = start_hour
			seen_activity_ids[activity_id] = true
	var restored_completed: Array[Dictionary] = []
	for raw_completed: Variant in state["recent_completed_activities"] as Array:
		if not raw_completed is Dictionary:
			return false
		restored_completed.append((raw_completed as Dictionary).duplicate(true))
	if restored_completed.size() > _completed_limit:
		return false
	schedules = restored_schedules.duplicate(true)
	recent_completed_activities = restored_completed
	generation_reasons = (state["generation_reasons"] as Dictionary).duplicate(true)
	_generated_days = (state["generated_days"] as Dictionary).duplicate(true)
	_next_sequence = int(state["next_sequence"])
	return true


func _generate_through(person_id: String, current_hour: int, target_hour: int) -> void:
	var start_value: Dictionary = V2DateTime.from_total_hour(current_hour)
	if start_value.is_empty():
		return
	var day_start: int = V2DateTime.to_total_hour({
		"year": int(start_value["year"]),
		"month": int(start_value["month"]),
		"day": int(start_value["day"]),
		"hour": 0,
	})
	var day_hour: int = day_start
	while day_hour < target_hour:
		_generate_person_day(person_id, day_hour)
		day_hour += 24


func _generate_person_day(person_id: String, day_hour: int) -> void:
	var date: String = V2DateTime.date_from_total_hour(day_hour)
	var generated_key: String = "%s:%s" % [person_id, date]
	if _generated_days.has(generated_key):
		return
	var person: Dictionary = _people[person_id] as Dictionary
	var routine: Dictionary = person.get("default_schedule", {}) as Dictionary
	var blocks: Array[Dictionary] = []
	var block_type: String = ""
	var block_source: String = ""
	var block_location: String = ""
	var block_start: int = day_hour
	for offset: int in range(24):
		var total_hour: int = day_hour + offset
		var resolved: Dictionary = _default_hour(person_id, total_hour, person, routine)
		var next_type: String = str(resolved.get("type", "free_time"))
		var next_source: String = str(resolved.get("source", "default_routine"))
		var next_location: String = str(resolved.get(
			"location_id", person.get("home_location_id", "")
		))
		if offset == 0:
			block_type = next_type
			block_source = next_source
			block_location = next_location
			block_start = total_hour
		elif next_type != block_type or next_source != block_source or next_location != block_location:
			blocks.append({
				"type": block_type,
				"source": block_source,
				"location_id": block_location,
				"start_hour": block_start,
				"end_hour": total_hour,
			})
			block_type = next_type
			block_source = next_source
			block_location = next_location
			block_start = total_hour
	blocks.append({
		"type": block_type,
		"source": block_source,
		"location_id": block_location,
		"start_hour": block_start,
		"end_hour": day_hour + 24,
	})
	for block: Dictionary in blocks:
		_append_activity(person_id, _make_activity(
			person_id, str(block["type"]), int(block["start_hour"]), int(block["end_hour"]),
			str(block["location_id"]), str(block["source"]), "", 0, {}, day_hour
		))
	_generated_days[generated_key] = true


func _default_hour(
	person_id: String,
	total_hour: int,
	person: Dictionary,
	routine: Dictionary
) -> Dictionary:
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	var hour: int = int(value.get("hour", -1))
	var home: String = str(person.get("home_location_id", ""))
	var workplace: String = str(person.get("workplace_location_id", ""))
	if hour < int(routine.get("sleep_end_hour", 6)) or hour >= int(routine.get("sleep_start_hour", 22)):
		return {"type": "sleep", "source": "default_routine", "location_id": home}
	if _employment.is_required_work_hour(person_id, total_hour):
		return {"type": "work", "source": "contract", "location_id": workplace}
	var contract: Dictionary = _employment.contract_for_person(person_id)
	var workday: bool = (contract.get("work_days", []) as Array).has(int(value.get("weekday", -1)))
	if workday and hour == int(routine.get("commute_to_work_start_hour", 6)):
		return {"type": "commute_to_work", "source": "contract", "location_id": workplace}
	if workday and hour == int(routine.get("meal_break_start_hour", 12)):
		return {"type": "meal_break", "source": "contract", "location_id": workplace}
	if workday and hour == int(routine.get("commute_home_start_hour", 17)):
		return {"type": "commute_home", "source": "contract", "location_id": home}
	return {"type": "free_time", "source": "default_routine", "location_id": home}


func _validate_conflict(
	person_id: String,
	activity_type: String,
	start_hour: int,
	end_hour: int,
	new_source: String
) -> V2LifeLoopResult:
	for total_hour: int in range(start_hour, end_hour):
		var existing: Dictionary = activity_for_hour(person_id, total_hour)
		if existing.is_empty():
			continue
		var source: String = str(existing.get("source", ""))
		if source == "system":
			return _conflict_result(person_id, total_hour, existing, "强制健康安排")
		if new_source == "system":
			continue
		if source == "player":
			return _conflict_result(person_id, total_hour, existing, "已有玩家活动")
		if source == "contract":
			var existing_type: String = str(existing.get("activity_type", ""))
			var can_replace: bool = (
				activity_type in ["authorized_leave", "absence"]
				and existing_type in ["work", "meal_break"]
			)
			var overtime_after_shift: bool = (
				activity_type == "overtime" and existing_type == "commute_home"
			)
			if not can_replace and not overtime_after_shift:
				return _conflict_result(person_id, total_hour, existing, "工作义务冲突")
		if new_source == "npc_rule" and source not in ["default_routine", "npc_rule"]:
			return _conflict_result(person_id, total_hour, existing, "更高优先级日程")
	return V2LifeLoopResult.ok()


func _conflict_result(
	person_id: String,
	total_hour: int,
	existing: Dictionary,
	reason: String
) -> V2LifeLoopResult:
	return V2LifeLoopResult.fail(
		"time_conflict", "%s：%s" % [reason, V2DateTime.display_from_total_hour(total_hour)],
		"conflict_activity=%s" % str(existing.get("activity_id", "")),
		[person_id, str(existing.get("activity_id", ""))]
	)


func _make_activity(
	person_id: String,
	activity_type: String,
	start_hour: int,
	end_hour: int,
	location_id: String,
	source: String,
	related_entity_id: String,
	required_cash_centimes: int,
	expected_effects: Dictionary,
	created_hour: int = -1
) -> Dictionary:
	var activity_id: String = "activity:v2_2:%d" % _next_sequence
	_next_sequence += 1
	return {
		"activity_id": activity_id,
		"person_id": person_id,
		"activity_type": activity_type,
		"start_hour": start_hour,
		"end_hour": end_hour,
		"start_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"end_datetime": V2DateTime.iso_from_total_hour(end_hour),
		"location_id": location_id,
		"source": source,
		"status": "planned",
		"related_entity_id": related_entity_id,
		"required_cash_centimes": required_cash_centimes,
		"expected_effects": expected_effects.duplicate(true),
		"actual_effects": {},
		"cancellation_reason": "",
		"interruption_reason": "",
		"created_datetime": V2DateTime.iso_from_total_hour(
			start_hour if created_hour < 0 else created_hour
		),
		"completed_datetime": "",
	}


func _append_activity(person_id: String, activity: Dictionary) -> void:
	var person_schedule: Array = schedules[person_id] as Array
	person_schedule.append(activity)
	_sort_activities(person_schedule)
	schedules[person_id] = person_schedule


func _future_end(person_id: String, current_hour: int) -> int:
	var result: int = current_hour
	for raw_activity: Variant in schedules.get(person_id, []) as Array:
		var activity: Dictionary = raw_activity as Dictionary
		if str(activity.get("status", "")) not in ACTIVE_STATUSES:
			continue
		var start_hour: int = int(activity.get("start_hour", -1))
		var end_hour: int = int(activity.get("end_hour", -1))
		if end_hour <= result:
			continue
		if start_hour > result:
			break
		result = end_hour
	return result


func _select_activity(person_id: String, total_hour: int, include_terminal: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_priority: int = -1
	for raw_activity: Variant in schedules.get(person_id, []) as Array:
		var activity: Dictionary = raw_activity as Dictionary
		var status: String = str(activity.get("status", ""))
		if not include_terminal and status in TERMINAL_STATUSES:
			continue
		if total_hour < int(activity.get("start_hour", -1)) or total_hour >= int(activity.get("end_hour", -1)):
			continue
		var priority: int = int(SOURCE_PRIORITY.get(str(activity.get("source", "")), 0))
		if priority > best_priority:
			best = activity
			best_priority = priority
	return best.duplicate(true)


static func _sort_activities(activities: Array) -> void:
	activities.sort_custom(func(first: Variant, second: Variant) -> bool:
		var first_activity: Dictionary = first as Dictionary
		var second_activity: Dictionary = second as Dictionary
		var first_start: int = int(first_activity.get("start_hour", 0))
		var second_start: int = int(second_activity.get("start_hour", 0))
		if first_start != second_start:
			return first_start < second_start
		return str(first_activity.get("activity_id", "")) < str(
			second_activity.get("activity_id", "")
		)
	)
