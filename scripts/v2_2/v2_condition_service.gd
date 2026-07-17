class_name V2ConditionService
extends RefCounted
## Applies configured condition deltas and keeps their bounded causal trace.

var person_states: Dictionary = {}
var causal_events: Array[Dictionary] = []
var sleep_hour_history: Dictionary = {}
var _effects: Dictionary = {}
var _rules: Dictionary = {}
var _next_sequence: int = 1
var _maximum_events: int = 512


func configure(balance: Dictionary, people: Array) -> void:
	_effects = (balance.get("activity_effects", {}) as Dictionary).duplicate(true)
	_rules = (balance.get("condition", {}) as Dictionary).duplicate(true)
	_maximum_events = int(
		(balance.get("history_limits", {}) as Dictionary).get("causal_events", 512)
	)
	person_states.clear()
	sleep_hour_history.clear()
	for record_variant: Variant in people:
		var person: Dictionary = record_variant as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		var initial: Dictionary = person.get("initial_condition", {}) as Dictionary
		person_states[person_id] = initial.duplicate(true)
		sleep_hour_history[person_id] = []


func seed_sleep_history(person_id: String, start_hour: int, sleep_hours: int) -> void:
	if not sleep_hour_history.has(person_id):
		return
	var history: Array = []
	for total_hour: int in range(start_hour - maxi(0, sleep_hours), start_hour):
		history.append(total_hour)
	sleep_hour_history[person_id] = history


func apply_activity(person_id: String, activity_type: String, total_hour: int) -> void:
	var effect: Dictionary = _effects.get(activity_type, {}) as Dictionary
	for stat: String in ["health", "fatigue", "stress"]:
		var delta: int = int(effect.get(stat, 0))
		if delta != 0:
			apply_delta(
				person_id, stat, delta, total_hour,
				_activity_reason(activity_type), "activity", activity_type
			)
	if activity_type == "sleep":
		var history: Array = sleep_hour_history.get(person_id, []) as Array
		history.append(total_hour)
		while history.size() > 72:
			history.pop_front()
		sleep_hour_history[person_id] = history


func apply_delta(
	person_id: String,
	stat: String,
	delta: int,
	total_hour: int,
	reason: String,
	source_type: String,
	source_id: String
) -> int:
	if not person_states.has(person_id) or stat not in ["health", "fatigue", "stress"]:
		return 0
	var state: Dictionary = person_states[person_id] as Dictionary
	var before: int = int(state.get(stat, 0))
	var after: int = clampi(
		before + delta,
		int(_rules.get("minimum", 0)),
		int(_rules.get("maximum", 1000))
	)
	var actual_delta: int = after - before
	if actual_delta == 0:
		return 0
	state[stat] = after
	person_states[person_id] = state
	causal_events.append({
		"causal_event_id": "causal:v2_2:%d" % _next_sequence,
		"datetime": V2DateTime.iso_from_total_hour(total_hour),
		"total_hour": total_hour,
		"person_id": person_id,
		"source_type": source_type,
		"source_id": source_id,
		"target_stat": stat,
		"delta": actual_delta,
		"before_value": before,
		"after_value": after,
		"human_readable_reason": reason,
	})
	_next_sequence += 1
	while causal_events.size() > _maximum_events:
		causal_events.pop_front()
	return actual_delta


func settle_daily_sleep(person_id: String, total_hour: int) -> int:
	var history: Array = sleep_hour_history.get(person_id, []) as Array
	var sleep_hours: int = 0
	for raw_hour: Variant in history:
		var sleep_hour: int = int(raw_hour)
		if sleep_hour >= total_hour - 24 and sleep_hour < total_hour:
			sleep_hours += 1
	var state: Dictionary = person_states.get(person_id, {}) as Dictionary
	state["sleep_hours_current_day"] = sleep_hours
	if sleep_hours < int(_rules.get("short_sleep_hours", 6)):
		apply_delta(person_id, "fatigue", int(_rules.get("short_sleep_fatigue_delta", 80)), total_hour, "过去24小时睡眠不足6小时", "daily_sleep", V2DateTime.date_from_total_hour(total_hour))
		apply_delta(person_id, "stress", int(_rules.get("short_sleep_stress_delta", 40)), total_hour, "睡眠不足增加压力", "daily_sleep", V2DateTime.date_from_total_hour(total_hour))
		apply_delta(person_id, "health", int(_rules.get("short_sleep_health_delta", -5)), total_hour, "连续睡眠不足影响健康", "daily_sleep", V2DateTime.date_from_total_hour(total_hour))
		state = person_states[person_id] as Dictionary
		state["consecutive_short_sleep_days"] = int(state.get("consecutive_short_sleep_days", 0)) + 1
	elif sleep_hours < int(_rules.get("healthy_sleep_hours", 8)):
		apply_delta(person_id, "fatigue", int(_rules.get("partial_sleep_fatigue_delta", 30)), total_hour, "过去24小时睡眠不足8小时", "daily_sleep", V2DateTime.date_from_total_hour(total_hour))
		apply_delta(person_id, "stress", int(_rules.get("partial_sleep_stress_delta", 10)), total_hour, "睡眠时间偏短", "daily_sleep", V2DateTime.date_from_total_hour(total_hour))
	else:
		apply_delta(person_id, "health", int(_rules.get("healthy_sleep_health_delta", 2)), total_hour, "过去24小时获得充分睡眠", "daily_sleep", V2DateTime.date_from_total_hour(total_hour))
		state = person_states[person_id] as Dictionary
		state["consecutive_short_sleep_days"] = 0
	state["sleep_hours_current_day"] = sleep_hours
	person_states[person_id] = state
	return sleep_hours


func settle_food_need(person_id: String, has_food_deficit: bool, total_hour: int) -> void:
	if not person_states.has(person_id):
		return
	var state: Dictionary = person_states[person_id] as Dictionary
	if has_food_deficit:
		var consecutive_days: int = int(state.get("consecutive_food_deficit_days", 0)) + 1
		state["consecutive_food_deficit_days"] = consecutive_days
		person_states[person_id] = state
		apply_delta(
			person_id,
			"stress",
			int(_rules.get("food_deficit_stress_delta", 50)),
			total_hour,
			"住户当天食品不足",
			"household_consumption",
			V2DateTime.date_from_total_hour(total_hour)
		)
		if consecutive_days >= int(_rules.get("food_deficit_health_threshold_days", 2)):
			apply_delta(
				person_id,
				"health",
				int(_rules.get("food_deficit_health_delta_after_days", -10)),
				total_hour,
				"连续食品不足影响健康",
				"household_consumption",
				V2DateTime.date_from_total_hour(total_hour)
			)
	else:
		state["consecutive_food_deficit_days"] = 0
		person_states[person_id] = state


func settle_essentials_need(person_id: String, has_deficit: bool, total_hour: int) -> void:
	if has_deficit:
		apply_delta(
			person_id,
			"stress",
			int(_rules.get("essentials_deficit_stress_delta", 15)),
			total_hour,
			"住户当天生活用品不足",
			"household_consumption",
			V2DateTime.date_from_total_hour(total_hour)
		)


func apply_rent_arrears(person_id: String, total_hour: int) -> void:
	apply_delta(
		person_id,
		"stress",
		int(_rules.get("rent_arrears_stress_delta", 60)),
		total_hour,
		"房租到期但现金不足",
		"rent",
		V2DateTime.iso_from_total_hour(total_hour)
	)


func get_state(person_id: String) -> Dictionary:
	var value: Variant = person_states.get(person_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func recent_causes(person_id: String, stat: String, current_hour: int, limit: int = 4) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(causal_events.size() - 1, -1, -1):
		var event: Dictionary = causal_events[index]
		if (
			str(event.get("person_id", "")) != person_id
			or str(event.get("target_stat", "")) != stat
			or int(event.get("total_hour", -9999)) < current_hour - 24
		):
			continue
		result.append(event.duplicate(true))
		if result.size() >= limit:
			break
	return result


func indicator(person_id: String, stat: String, current_hour: int) -> Dictionary:
	var value: int = int((person_states.get(person_id, {}) as Dictionary).get(stat, 0))
	var symbol: String = "✓"
	if stat == "health":
		symbol = "✓" if value >= 700 else ("!" if value >= 400 else "×")
	elif stat == "fatigue":
		symbol = "✓" if value < 600 else ("!" if value < 950 else "×")
	else:
		symbol = "✓" if value < 600 else "!"
	var causes: Array[Dictionary] = recent_causes(person_id, stat, current_hour)
	var reason: String = "最近24小时没有显著变化"
	var trend: String = "稳定"
	if not causes.is_empty():
		reason = str(causes[0].get("human_readable_reason", "近期活动影响"))
		var total_delta: int = 0
		for cause: Dictionary in causes:
			total_delta += int(cause.get("delta", 0))
		trend = "上升" if total_delta > 0 else ("下降" if total_delta < 0 else "稳定")
	var label_map: Dictionary = {"health": "健康", "fatigue": "疲劳", "stress": "压力"}
	var impact: String = "当前不限制常规活动"
	var suggestion: String = "维持当前生活节奏"
	if stat == "fatigue" and value >= 950:
		impact = "当前不能安排加班或工会活动"
		suggestion = "优先安排睡眠或休息"
	elif stat == "stress" and value >= 600:
		impact = "高压力会持续影响生活状态"
		suggestion = "安排休息或联系关系人物"
	elif stat == "health" and value < 700:
		impact = "健康状态需要持续观察"
		suggestion = "保证睡眠并避免物资短缺"
	return {
		"label": str(label_map.get(stat, stat)),
		"symbol": symbol,
		"state": "%s · %d/1000" % [str(label_map.get(stat, stat)), value],
		"reason": reason,
		"trend": trend,
		"impact": impact,
		"suggestion": suggestion,
		"value": value,
	}


func get_persistent_state() -> Dictionary:
	return {
		"person_states": person_states.duplicate(true),
		"causal_events": causal_events.duplicate(true),
		"sleep_hour_history": sleep_hour_history.duplicate(true),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("person_states", {}) is Dictionary
		or not state.get("causal_events", []) is Array
		or not state.get("sleep_hour_history", {}) is Dictionary
		or int(state.get("next_sequence", 0)) < 1
	):
		return false
	for raw_state: Variant in (state["person_states"] as Dictionary).values():
		if not raw_state is Dictionary:
			return false
		var person_state: Dictionary = raw_state as Dictionary
		for stat: String in ["health", "fatigue", "stress"]:
			var value: int = int(person_state.get(stat, -1))
			if value < 0 or value > 1000:
				return false
	person_states = (state["person_states"] as Dictionary).duplicate(true)
	causal_events.clear()
	for raw_event: Variant in state["causal_events"] as Array:
		if not raw_event is Dictionary:
			return false
		causal_events.append((raw_event as Dictionary).duplicate(true))
	sleep_hour_history = (state["sleep_hour_history"] as Dictionary).duplicate(true)
	_next_sequence = int(state["next_sequence"])
	return true


static func _activity_reason(activity_type: String) -> String:
	var labels: Dictionary = {
		"sleep": "睡眠带来恢复",
		"commute_to_work": "上班通勤增加疲劳与压力",
		"work": "正常工作增加疲劳与压力",
		"meal_break": "午间休息带来短暂恢复",
		"commute_home": "回家通勤增加疲劳与压力",
		"rest": "休息带来恢复",
		"free_time": "自由时间带来恢复",
		"household_chores": "家务增加少量疲劳",
		"purchase_food": "购买食品增加少量疲劳",
		"purchase_essentials": "购买生活用品增加少量疲劳",
		"social_contact": "联系关系人物缓解压力",
		"union_activity": "参加工会活动",
		"overtime": "加班比正常工作产生更多疲劳与压力",
		"authorized_leave": "无薪请假提供休息",
		"absence": "无故缺勤增加压力",
	}
	return str(labels.get(activity_type, "活动改变状态"))
