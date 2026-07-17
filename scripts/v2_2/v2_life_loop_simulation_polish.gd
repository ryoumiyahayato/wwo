class_name V2LifeLoopSimulationPolish
extends V2LifeLoopSimulation
## V2.2.1 contact scheduling that resolves the target from the current person's
## configured relationship records instead of a global hard-coded person.


func suggest_contact_activity(
	person_id: String, target_id: String = ""
) -> V2LifeLoopResult:
	if not person_states.has(person_id):
		return V2LifeLoopResult.fail(
			"unknown_person", "找不到当前人物", person_id, [person_id]
		)
	var resolved_target: String = target_id
	if resolved_target.is_empty():
		resolved_target = relationships.first_contact_target(person_id)
	if resolved_target.is_empty():
		return V2LifeLoopResult.fail(
			"no_contact_candidates", "当前人物没有可联系的关系人物", person_id,
			[person_id]
		)
	var current_hour: int = clock.total_hours
	var start_hour: int = schedule.find_available_hour(
		person_id, current_hour + 1, current_hour + 7 * 24, 18, 21
	)
	if start_hour < 0:
		return V2LifeLoopResult.fail(
			"no_available_time", "未来 7 日没有可用于联系的时间", resolved_target,
			[person_id, resolved_target]
		)
	var allowed: V2LifeLoopResult = relationships.can_contact(
		person_id, resolved_target, start_hour
	)
	if not allowed.success:
		return allowed
	var person: Dictionary = config.person_record(person_id)
	return V2LifeLoopResult.ok(
		"已生成联系建议",
		{
			"activity_type": "social_contact",
			"start_hour": start_hour,
			"duration_hours": 1,
			"location_id": str(person.get("home_location_id", "")),
			"required_cash_centimes": 0,
			"expected_effects": "熟悉度 +5；信任 +2；压力 -20",
			"related_entity_id": resolved_target,
			"related_entity_name": relationships.target_display_name(
				person_id, resolved_target
			),
		},
		[person_id, resolved_target]
	)


func request_contact_activity(
	person_id: String,
	target_id: String,
	start_hour: int,
	duration_hours: int
) -> V2LifeLoopResult:
	if not person_states.has(person_id):
		return V2LifeLoopResult.fail(
			"unknown_person", "找不到当前人物", person_id, [person_id]
		)
	if target_id.is_empty():
		return V2LifeLoopResult.fail(
			"no_contact_target", "没有选择联系人", person_id, [person_id]
		)
	if duration_hours != 1:
		return V2LifeLoopResult.fail(
			"invalid_duration", "联系关系人物固定耗时 1 小时", "",
			[person_id, target_id]
		)
	if start_hour < clock.total_hours:
		return V2LifeLoopResult.fail(
			"past_time", "不能修改过去的日程",
			V2DateTime.iso_from_total_hour(start_hour), [person_id, target_id]
		)
	var contact_check: V2LifeLoopResult = relationships.can_contact(
		person_id, target_id, start_hour
	)
	if not contact_check.success:
		return contact_check
	var person: Dictionary = config.person_record(person_id)
	var result: V2LifeLoopResult = schedule.schedule_player_activity(
		person_id,
		"social_contact",
		start_hour,
		duration_hours,
		clock.total_hours,
		str(person.get("home_location_id", "")),
		target_id,
		0,
		{"familiarity": 5, "trust": 2, "stress": -20}
	)
	if result.success:
		state_changed.emit({"schedule": person_id, "contact_target": target_id})
	return result


func request_next_contact(
	person_id: String, target_id: String = ""
) -> V2LifeLoopResult:
	var suggestion: V2LifeLoopResult = suggest_contact_activity(
		person_id, target_id
	)
	if not suggestion.success:
		return suggestion
	return request_contact_activity(
		person_id,
		str(suggestion.data.get("related_entity_id", "")),
		int(suggestion.data.get("start_hour", -1)),
		int(suggestion.data.get("duration_hours", 1))
	)
