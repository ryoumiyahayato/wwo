class_name SocialAppointmentService
extends RefCounted
## Invitation delivery, shared reservation, attendance and missed consequences.

const STATUSES: PackedStringArray = [
	"invitation", "acceptance", "rejection", "reschedule", "appointment",
	"attended", "missed", "cancelled",
]

var appointments: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _next_sequence: int = 1
var _history_limit: int = 128
var _key_limit: int = 1024


func configure(balance: Dictionary) -> void:
	appointments.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_next_sequence = 1
	var limits: Dictionary = balance.get("history_limits", {}) as Dictionary
	_history_limit = maxi(32, int(limits.get("appointments", 128)))
	_key_limit = maxi(128, int(limits.get("idempotency_keys", 1024)))


func invite(
	initiator_id: String,
	participant_id: String,
	location_id: String,
	start_hour: int,
	end_hour: int,
	purpose: String,
	total_hour: int,
	locations: SpatialLocationService,
	communication: CommunicationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null
) -> V2LifeLoopResult:
	if end_hour <= start_hour or start_hour <= total_hour:
		return V2LifeLoopResult.fail("invalid_appointment_time", "约见时间无效")
	if (
		not locations.knows_location(initiator_id, location_id)
		or not locations.knows_location(participant_id, location_id)
	):
		return V2LifeLoopResult.fail(
			"appointment_location_unknown", "约见地点必须双方已知", location_id,
			[initiator_id, participant_id, location_id]
		)
	if not relationships.has_relationship(initiator_id, participant_id):
		return V2LifeLoopResult.fail(
			"unknown_relationship", "不能邀请陌生人约见", participant_id,
			[initiator_id, participant_id]
		)
	var appointment_id: String = "appointment:v2_3:%05d" % _next_sequence
	var sent: V2LifeLoopResult = communication.send_message(
		initiator_id, participant_id, "local_letter", "appointment_invitation",
		{
			"appointment_id": appointment_id,
			"fact_id": "appointment:%s" % appointment_id,
			"subject_id": appointment_id,
			"fact_type": "appointment",
			"claim": {
				"location_id": location_id,
				"start_datetime": V2DateTime.iso_from_total_hour(start_hour),
				"end_datetime": V2DateTime.iso_from_total_hour(end_hour),
				"purpose": purpose,
			},
			"expires_hour": end_hour,
		},
		total_hour, locations, knowledge, relationships, households, ledger,
		appointment_id
	)
	if not sent.success:
		return sent
	_next_sequence += 1
	var invitation_id: String = str(
		(sent.data.get("message", {}) as Dictionary).get("message_id", "")
	)
	var appointment: Dictionary = {
		"appointment_id": appointment_id,
		"initiator_id": initiator_id,
		"participant_ids": [participant_id],
		"location_id": location_id,
		"start_hour": start_hour,
		"end_hour": end_hour,
		"start_datetime": V2DateTime.iso_from_total_hour(start_hour),
		"end_datetime": V2DateTime.iso_from_total_hour(end_hour),
		"purpose": purpose,
		"status": "invitation",
		"invitation_message_ids": [invitation_id],
		"response_message_ids": [],
		"accepted_person_ids": [],
		"rejected_person_ids": [],
		"attendance": {},
		"scheduled_activity_ids": {},
		"failure_reason": "",
		"result_datetime": "",
	}
	appointments[appointment_id] = appointment
	_trim_history()
	return V2LifeLoopResult.ok(
		"约见邀请已寄出", {"appointment": appointment.duplicate(true)},
		[initiator_id, participant_id, appointment_id, invitation_id]
	)


func respond(
	appointment_id: String,
	person_id: String,
	accept: bool,
	total_hour: int,
	schedule: V2ScheduleService,
	communication: CommunicationService,
	locations: SpatialLocationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null
) -> V2LifeLoopResult:
	if not appointments.has(appointment_id):
		return V2LifeLoopResult.fail(
			"unknown_appointment", "找不到约见", appointment_id, [appointment_id]
		)
	var appointment: Dictionary = appointments[appointment_id] as Dictionary
	if person_id not in (appointment.get("participant_ids", []) as Array):
		return V2LifeLoopResult.fail("not_appointment_participant", "当前人物不是受邀者")
	var invitation_ids: Array = appointment.get("invitation_message_ids", []) as Array
	var invitation_id: String = str(invitation_ids[0]) if not invitation_ids.is_empty() else ""
	var invitation: Dictionary = communication.get_message(invitation_id)
	if str(invitation.get("status", "")) not in ["read", "replied"]:
		return V2LifeLoopResult.fail(
			"appointment_invitation_unread", "必须先阅读邀请", appointment_id
		)
	if str(appointment.get("status", "")) != "invitation":
		return V2LifeLoopResult.ok(
			"约见邀请已经响应",
			{"appointment": appointment.duplicate(true), "already_responded": true}
		)
	if not accept:
		appointment["status"] = "rejection"
		appointment["rejected_person_ids"] = [person_id]
		var rejection: V2LifeLoopResult = communication.reply_message(
			person_id, invitation_id, "appointment_rejection",
			{"appointment_id": appointment_id},
			total_hour, locations, knowledge, relationships, households, ledger
		)
		if rejection.success:
			(appointment["response_message_ids"] as Array).append(str(
				(rejection.data.get("message", {}) as Dictionary).get("message_id", "")
			))
		appointments[appointment_id] = appointment
		return V2LifeLoopResult.ok("约见邀请已拒绝", {"appointment": appointment})
	var participants: Array[String] = [
		str(appointment.get("initiator_id", "")), person_id,
	]
	for participant: String in participants:
		var preflight: V2LifeLoopResult = schedule.can_schedule_activity(
			participant, "meet_person",
			int(appointment.get("start_hour", -1)),
			int(appointment.get("end_hour", 0)) - int(appointment.get("start_hour", 0)),
			"npc_rule"
		)
		if not preflight.success:
			return V2LifeLoopResult.fail(
				"appointment_schedule_conflict", "一方日程无法预留",
				preflight.technical_message, participants
			)
	var scheduled: Dictionary = {}
	for participant: String in participants:
		var reserve: V2LifeLoopResult = schedule.schedule_rule_activity(
			participant, "meet_person",
			int(appointment.get("start_hour", -1)),
			int(appointment.get("end_hour", 0)) - int(appointment.get("start_hour", 0)),
			str(appointment.get("location_id", "")), "npc_rule", appointment_id
		)
		if not reserve.success:
			push_error("约见预检后预留失败：%s" % reserve.user_message)
			return reserve
		var activity_id: String = str(
			(reserve.data.get("activity", {}) as Dictionary).get("activity_id", "")
		)
		schedule.merge_activity_metadata(
			participant, activity_id, {"appointment_id": appointment_id}
		)
		scheduled[participant] = activity_id
	var response: V2LifeLoopResult = communication.reply_message(
		person_id, invitation_id, "appointment_acceptance",
		{"appointment_id": appointment_id},
		total_hour, locations, knowledge, relationships, households, ledger
	)
	appointment["status"] = "appointment"
	appointment["accepted_person_ids"] = [person_id]
	appointment["scheduled_activity_ids"] = scheduled
	if response.success:
		(appointment["response_message_ids"] as Array).append(str(
			(response.data.get("message", {}) as Dictionary).get("message_id", "")
		))
	appointments[appointment_id] = appointment
	return V2LifeLoopResult.ok(
		"约见已接受，双方日程均已预留",
		{"appointment": appointment.duplicate(true)}, participants
	)


func process_hour(
	total_hour: int,
	locations: SpatialLocationService,
	relationships: V23RelationshipService
) -> Array[V2LifeLoopResult]:
	var results: Array[V2LifeLoopResult] = []
	var appointment_ids: Array[String] = []
	for raw_id: Variant in appointments.keys():
		appointment_ids.append(str(raw_id))
	appointment_ids.sort()
	for appointment_id: String in appointment_ids:
		var appointment: Dictionary = appointments[appointment_id] as Dictionary
		if str(appointment.get("status", "")) != "appointment":
			continue
		var start_hour: int = int(appointment.get("start_hour", -1))
		var end_hour: int = int(appointment.get("end_hour", -1))
		if total_hour >= start_hour and total_hour < end_hour:
			_record_attendance(appointment_id, total_hour, locations)
		if total_hour + 1 >= end_hour:
			results.append(_settle_result(appointment_id, total_hour + 1, relationships))
	return results


func cancel(
	appointment_id: String,
	person_id: String,
	current_hour: int,
	schedule: V2ScheduleService
) -> V2LifeLoopResult:
	if not appointments.has(appointment_id):
		return V2LifeLoopResult.fail("unknown_appointment", "找不到约见", appointment_id)
	var appointment: Dictionary = appointments[appointment_id] as Dictionary
	if person_id != str(appointment.get("initiator_id", "")):
		return V2LifeLoopResult.fail("appointment_cancel_forbidden", "只有发起者可取消")
	if current_hour >= int(appointment.get("start_hour", -1)):
		return V2LifeLoopResult.fail(
			"appointment_started", "已经开始的约见不能静默取消", appointment_id
		)
	for raw_person_id: Variant in (
		appointment.get("scheduled_activity_ids", {}) as Dictionary
	).keys():
		schedule.cancel_activity_by_id(
			str(raw_person_id),
			str((appointment["scheduled_activity_ids"] as Dictionary)[raw_person_id]),
			current_hour,
			"appointment_cancelled"
		)
	appointment["status"] = "cancelled"
	appointments[appointment_id] = appointment
	return V2LifeLoopResult.ok("约见已取消并释放未来日程", {"appointment": appointment})


func get_persistent_state() -> Dictionary:
	return {
		"appointments": appointments.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("appointments", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
		or not state.get("processed_key_order", []) is Array
		or int(state.get("next_sequence", 0)) < 1
	):
		return false
	var restored: Dictionary = state["appointments"] as Dictionary
	for raw_id: Variant in restored.keys():
		if not restored[raw_id] is Dictionary:
			return false
		var appointment: Dictionary = restored[raw_id] as Dictionary
		if (
			str(raw_id) != str(appointment.get("appointment_id", ""))
			or str(appointment.get("status", "")) not in STATUSES
		):
			return false
	appointments = restored.duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_processed_key_order.clear()
	for raw_key: Variant in state["processed_key_order"] as Array:
		var key: String = str(raw_key)
		if not processed_idempotency_keys.has(key):
			return false
		_processed_key_order.append(key)
	_next_sequence = int(state["next_sequence"])
	return true


func _record_attendance(
	appointment_id: String,
	total_hour: int,
	locations: SpatialLocationService
) -> void:
	var appointment: Dictionary = appointments[appointment_id] as Dictionary
	var people: Array[String] = [str(appointment.get("initiator_id", ""))]
	for raw_person_id: Variant in appointment.get("participant_ids", []) as Array:
		people.append(str(raw_person_id))
	var attendance: Dictionary = appointment.get("attendance", {}) as Dictionary
	for person_id: String in people:
		var position: Dictionary = locations.position_for(person_id)
		var present: bool = (
			str(position.get("location_state", "")) == "at_location"
			and str(position.get("current_location_id", ""))
			== str(appointment.get("location_id", ""))
		)
		var record: Dictionary = attendance.get(person_id, {
			"arrived_datetime": "",
			"hours_present": 0,
			"status": "absent",
		}) as Dictionary
		if present:
			if str(record.get("arrived_datetime", "")).is_empty():
				record["arrived_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
			record["hours_present"] = int(record.get("hours_present", 0)) + 1
			record["status"] = "present"
		attendance[person_id] = record
	appointment["attendance"] = attendance
	appointments[appointment_id] = appointment


func _settle_result(
	appointment_id: String,
	total_hour: int,
	relationships: V23RelationshipService
) -> V2LifeLoopResult:
	var key: String = "appointment:%s:result" % appointment_id
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok("约见结果已经结算", {"already_settled": true})
	var appointment: Dictionary = appointments[appointment_id] as Dictionary
	var initiator_id: String = str(appointment.get("initiator_id", ""))
	var participant_id: String = str((appointment.get("participant_ids", []) as Array)[0])
	var attendance: Dictionary = appointment.get("attendance", {}) as Dictionary
	var initiator_present: bool = int(
		(attendance.get(initiator_id, {}) as Dictionary).get("hours_present", 0)
	) > 0
	var participant_present: bool = int(
		(attendance.get(participant_id, {}) as Dictionary).get("hours_present", 0)
	) > 0
	if initiator_present and participant_present:
		appointment["status"] = "attended"
		relationships.apply_interaction(
			initiator_id, participant_id, "appointment_attended",
			"%s:attended" % appointment_id, total_hour,
			"双方实际到达约见地点并共同在场"
		)
	else:
		appointment["status"] = "missed"
		var missing_id: String = participant_id if not participant_present else initiator_id
		appointment["failure_reason"] = "participant_absent:%s" % missing_id
		if relationships.has_relationship(initiator_id, participant_id):
			relationships.apply_interaction(
				initiator_id, participant_id, "appointment_missed",
				"%s:missed:%s" % [appointment_id, missing_id], total_hour,
				"已接受约见但一方未实际到场"
			)
	appointment["result_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	appointments[appointment_id] = appointment
	_remember_key(key)
	return V2LifeLoopResult.ok(
		"约见结果已按实际到场结算",
		{"appointment": appointment.duplicate(true)},
		[initiator_id, participant_id, appointment_id]
	)


func _remember_key(key: String) -> void:
	processed_idempotency_keys[key] = true
	_processed_key_order.append(key)
	while _processed_key_order.size() > _key_limit:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


func _trim_history() -> void:
	if appointments.size() <= _history_limit:
		return
	var terminal_ids: Array[String] = []
	for raw_id: Variant in appointments.keys():
		var appointment_id: String = str(raw_id)
		if str((appointments[appointment_id] as Dictionary).get("status", "")) in [
			"attended", "missed", "cancelled", "rejection",
		]:
			terminal_ids.append(appointment_id)
	terminal_ids.sort()
	while appointments.size() > _history_limit and not terminal_ids.is_empty():
		appointments.erase(terminal_ids.pop_front())
