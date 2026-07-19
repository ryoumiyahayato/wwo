class_name V23ProductSimulation
extends V23MinuteControlledSimulation
## Final formal product composition: activity and travel conflicts share contextual leave.


func request_travel(
	person_id: String,
	destination_id: String,
	preference: String = "fastest",
	start_hour: int = -1
) -> V2LifeLoopResult:
	var actual_start: int = clock.total_hours + 1 if start_hour < 0 else start_hour
	var preview: V2LifeLoopResult = preview_route(
		person_id, destination_id, preference, actual_start
	)
	if not preview.success:
		return preview
	var arrival_hour: int = int(
		preview.data.get("arrival_hour", actual_start + 1)
	)
	var covered_hours: Array[int] = _unreleased_contract_hours(
		person_id, actual_start, maxi(1, arrival_hour - actual_start)
	)
	if not covered_hours.is_empty():
		var leave_required := V2LifeLoopResult.fail(
			"requires_leave_authorization",
			"该行程与合同工作义务冲突，需要先确认请假。",
			"covered_hours=%d" % covered_hours.size(),
			[person_id, destination_id]
		)
		leave_required.data = {
			"command_type": "travel",
			"person_id": person_id,
			"destination_id": destination_id,
			"destination_name": spatial_locations.location_name(
				destination_id, person_id, truth_view
			),
			"preference": preference,
			"start_hour": actual_start,
			"arrival_hour": arrival_hour,
			"duration_hours": maxi(1, arrival_hour - actual_start),
			"covered_contract_hours": covered_hours.duplicate(),
			"covered_hour_count": covered_hours.size(),
		}
		return leave_required
	return super.request_travel(
		person_id, destination_id, preference, actual_start
	)


func authorize_leave_and_request_travel(
	person_id: String,
	destination_id: String,
	preference: String,
	start_hour: int
) -> V2LifeLoopResult:
	var preview: V2LifeLoopResult = preview_route(
		person_id, destination_id, preference, start_hour
	)
	if not preview.success:
		return preview
	var arrival_hour: int = int(
		preview.data.get("arrival_hour", start_hour + 1)
	)
	var covered_hours: Array[int] = _unreleased_contract_hours(
		person_id, start_hour, maxi(1, arrival_hour - start_hour)
	)
	if covered_hours.is_empty():
		return super.request_travel(
			person_id, destination_id, preference, start_hour
		)
	var schedule_before: Dictionary = schedule.get_persistent_state()
	var travel_before: Dictionary = travel_execution.get_persistent_state()
	var leave_before: Dictionary = leave.get_persistent_state()
	var authorization: V2LifeLoopResult = leave.authorize(
		person_id,
		start_hour,
		arrival_hour,
		clock.total_hours,
		employment
	)
	if not authorization.success:
		return authorization
	var record: Dictionary = authorization.data.get(
		"leave_authorization", {}
	) as Dictionary
	leave.release_contract_schedule(record, schedule)
	_replan_commutes_for_leave_record(record)
	var result: V2LifeLoopResult = super.request_travel(
		person_id, destination_id, preference, start_hour
	)
	if not result.success:
		schedule.restore_persistent_state(schedule_before)
		travel_execution.restore_persistent_state(travel_before)
		leave.restore_persistent_state(leave_before)
		return result
	notifications.add(
		"personal",
		"event",
		"请假已批准并建立行程",
		"已解除与行程重叠的合同工时；人物将按玩家指定路线出发。",
		clock.total_hours,
		"leave_for_travel:%s:%d" % [person_id, start_hour],
		result.affected_entity_ids
	)
	state_changed.emit({
		"travel": person_id,
		"leave": true,
		"player_override": true,
	})
	return result
