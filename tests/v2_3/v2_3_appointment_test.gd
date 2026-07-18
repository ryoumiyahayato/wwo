extends SceneTree
## Delayed appointment invitation, shared reservation, attendance and missed effects.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "约见测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 appointments")
		return
	var initiator: String = V2LifeLoopSimulation.PIERRE_ID
	var participant: String = "jeanne"
	var start_hour: int = simulation.clock.total_hours + 72
	var invited: V2LifeLoopResult = simulation.invite_appointment(
		initiator, participant, "location_lille_public_square",
		start_hour, start_hour + 1, "讨论工会会议"
	)
	test.expect(invited.success, "可向已知联系人发送正式约见邀请")
	var appointment: Dictionary = invited.data.get("appointment", {}) as Dictionary
	var appointment_id: String = str(appointment.get("appointment_id", ""))
	var message_id: String = str(
		(appointment.get("invitation_message_ids", []) as Array)[0]
	)
	var invitation: Dictionary = simulation.communication.get_message(message_id)
	var delivery_hour: int = V2DateTime.total_hour_from_iso(
		str(invitation.get("expected_delivery_datetime", ""))
	)
	simulation.communication.process_deliveries(delivery_hour)
	test.expect(
		simulation.read_message_now(participant, message_id).success,
		"受邀者必须先实际阅读邀请"
	)
	var accepted: V2LifeLoopResult = simulation.appointments.respond(
		appointment_id, participant, true, delivery_hour + 1,
		simulation.schedule, simulation.communication,
		simulation.spatial_locations, simulation.knowledge,
		simulation.dynamic_relationships, simulation.households, simulation.ledger
	)
	test.expect(accepted.success, "接受邀请后双方日程原子预留")
	var accepted_record: Dictionary = (
		simulation.appointments.appointments[appointment_id] as Dictionary
	)
	test.equal(accepted_record.get("status"), "appointment", "邀请转换为正式约见")
	test.equal(
		(accepted_record.get("scheduled_activity_ids", {}) as Dictionary).size(),
		2,
		"双方各有一个稳定约见活动 ID"
	)
	simulation.spatial_locations.force_set_at_location(
		initiator, "location_lille_public_square", start_hour
	)
	simulation.spatial_locations.force_set_at_location(
		participant, "location_lille_public_square", start_hour
	)
	simulation.appointments.process_hour(
		start_hour, simulation.spatial_locations, simulation.dynamic_relationships
	)
	test.equal(
		(simulation.appointments.appointments[appointment_id] as Dictionary).get(
			"status"
		),
		"attended",
		"双方实际同地到场后约见结算为 attended"
	)
	var relation: Dictionary = simulation.dynamic_relationships.get_relationship(
		initiator, participant
	)
	var attended_history: bool = false
	for item: Dictionary in relation.get("interaction_history", []) as Array:
		if str(item.get("interaction_type", "")) == "appointment_attended":
			attended_history = true
	test.expect(attended_history, "到场结果因果性地进入关系历史")
	var missed_simulation := V23LifeLoopSimulation.new()
	test.expect(missed_simulation.initialize(), "爽约测试使用独立确定性环境")
	var missed_start: int = missed_simulation.clock.total_hours + 72
	var missed_invite: V2LifeLoopResult = missed_simulation.invite_appointment(
		initiator, participant, "location_lille_public_square",
		missed_start, missed_start + 1, "爽约回归"
	)
	var missed_appointment: Dictionary = missed_invite.data.get(
		"appointment", {}
	) as Dictionary
	var missed_id: String = str(missed_appointment.get("appointment_id", ""))
	var missed_message_id: String = str(
		(missed_appointment.get("invitation_message_ids", []) as Array)[0]
	)
	var missed_message: Dictionary = missed_simulation.communication.get_message(
		missed_message_id
	)
	var missed_delivery: int = V2DateTime.total_hour_from_iso(
		str(missed_message.get("expected_delivery_datetime", ""))
	)
	missed_simulation.communication.process_deliveries(missed_delivery)
	missed_simulation.read_message_now(participant, missed_message_id)
	test.expect(
		missed_simulation.appointments.respond(
			missed_id, participant, true, missed_delivery + 1,
			missed_simulation.schedule, missed_simulation.communication,
			missed_simulation.spatial_locations, missed_simulation.knowledge,
			missed_simulation.dynamic_relationships,
			missed_simulation.households, missed_simulation.ledger
		).success,
		"爽约场景先完成双方日程预留"
	)
	var trust_before_missed: int = int(
		missed_simulation.dynamic_relationships.get_relationship(
			initiator, participant
		).get("trust", 0)
	)
	missed_simulation.spatial_locations.force_set_at_location(
		initiator, "location_lille_public_square", missed_start
	)
	missed_simulation.spatial_locations.force_set_at_location(
		participant, "location_lille_centre", missed_start
	)
	missed_simulation.appointments.process_hour(
		missed_start, missed_simulation.spatial_locations,
		missed_simulation.dynamic_relationships
	)
	test.equal(
		(missed_simulation.appointments.appointments[missed_id] as Dictionary).get(
			"status"
		),
		"missed",
		"一方未到实际地点时约见结算为 missed"
	)
	test.expect(
		int(missed_simulation.dynamic_relationships.get_relationship(
			initiator, participant
		).get("trust", 0)) < trust_before_missed,
		"爽约因果性地降低信任并增加关系代价"
	)
	test.finish(self, "V2.3 appointments")
