class_name CommunicationService
extends RefCounted
## Delayed, indexed and idempotent message delivery separated from reading.

const MESSAGE_STATUSES: PackedStringArray = [
	"drafted", "queued", "in_transit", "delivered", "read", "replied",
	"failed", "cancelled",
]

var messages: Dictionary = {}
var inbox_index: Dictionary = {}
var outbox_index: Dictionary = {}
var delivery_queue: Array[String] = []
var public_notice_ids: Array[String] = []
var processed_idempotency_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _people: Dictionary = {}
var _channels: Dictionary = {}
var _next_sequence: int = 1
var _message_limit: int = 256
var _key_limit: int = 1024


func configure(
	people: Array,
	channel_records: Array,
	balance: Dictionary
) -> V2LifeLoopResult:
	messages.clear()
	inbox_index.clear()
	outbox_index.clear()
	delivery_queue.clear()
	public_notice_ids.clear()
	processed_idempotency_keys.clear()
	_processed_key_order.clear()
	_people.clear()
	_channels.clear()
	_next_sequence = 1
	var limits: Dictionary = balance.get("history_limits", {}) as Dictionary
	_message_limit = maxi(32, int(limits.get("messages", 256)))
	_key_limit = maxi(128, int(limits.get("idempotency_keys", 1024)))
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			continue
		var person: Dictionary = (raw_person as Dictionary).duplicate(true)
		var person_id: String = str(person.get("person_id", ""))
		_people[person_id] = person
		inbox_index[person_id] = []
		outbox_index[person_id] = []
	for raw_channel: Variant in channel_records:
		if not raw_channel is Dictionary:
			continue
		var channel: Dictionary = (raw_channel as Dictionary).duplicate(true)
		_channels[str(channel.get("channel", ""))] = channel
	for required: String in [
		"face_to_face", "local_letter", "organization_notice", "public_notice",
	]:
		if not _channels.has(required):
			return V2LifeLoopResult.fail(
				"missing_communication_channel", "缺少通信渠道", required
			)
	return V2LifeLoopResult.ok(
		"延迟通信服务已建立",
		{"person_count": _people.size(), "channel_count": _channels.size()}
	)


func send_message(
	sender_id: String,
	recipient_id: String,
	channel_id: String,
	content_type: String,
	payload: Dictionary,
	total_hour: int,
	locations: SpatialLocationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null,
	related_appointment_id: String = "",
	replied_message_id: String = "",
	caller_idempotency_key: String = ""
) -> V2LifeLoopResult:
	if not _people.has(sender_id) or not _people.has(recipient_id):
		return V2LifeLoopResult.fail(
			"unknown_contact", "发件人或收件人不存在",
			"%s -> %s" % [sender_id, recipient_id], [sender_id, recipient_id]
		)
	if not _channels.has(channel_id):
		return V2LifeLoopResult.fail(
			"channel_unavailable", "通信渠道不可用", channel_id, [sender_id, recipient_id]
		)
	var reply: bool = not replied_message_id.is_empty()
	var allowed: V2LifeLoopResult = relationships.can_contact(
		sender_id, recipient_id, channel_id, total_hour, knowledge, reply
	)
	if not allowed.success:
		return allowed
	var channel: Dictionary = _channels[channel_id] as Dictionary
	var source_id: String = str(
		(_people[sender_id] as Dictionary).get("postal_address_location_id", "")
	)
	var destination_id: String = str(
		(_people[recipient_id] as Dictionary).get("postal_address_location_id", "")
	)
	if bool(channel.get("requires_postal_address", false)):
		if (
			source_id.is_empty() or destination_id.is_empty()
			or not locations.locations.has(source_id)
			or not locations.locations.has(destination_id)
		):
			return V2LifeLoopResult.fail(
				"postal_address_unknown", "缺少有效邮寄地址", destination_id,
				[sender_id, recipient_id]
			)
	var message_id: String = "message:v2_3:%07d" % _next_sequence
	var send_key: String = caller_idempotency_key
	if send_key.is_empty():
		send_key = "message_send:%s" % message_id
	if processed_idempotency_keys.has(send_key):
		var existing_id: String = str(processed_idempotency_keys[send_key])
		return V2LifeLoopResult.ok(
			"该消息已经发送",
			{"message": get_message(existing_id), "already_sent": true},
			[sender_id, recipient_id, existing_id]
		)
	var postage: int = int(channel.get("postage_centimes", 0))
	if postage > 0 and households != null and ledger != null:
		var household_id: String = households.household_id_for_person(sender_id)
		if not household_id.is_empty():
			var postage_result: V2LifeLoopResult = ledger.post(
				households.households, household_id, sender_id, postage,
				"expense", "communication", total_hour, message_id, channel_id,
				"postage:%s" % message_id, "本地信件邮资"
			)
			if not postage_result.success:
				return postage_result
	var delivery_hours: int = _delivery_hours(
		channel, source_id, destination_id, locations
	)
	_next_sequence += 1
	var status: String = "read" if channel_id == "face_to_face" else "in_transit"
	var message: Dictionary = {
		"message_id": message_id,
		"sender_person_id": sender_id,
		"recipient_person_id": recipient_id,
		"channel": channel_id,
		"content_type": content_type,
		"payload": payload.duplicate(true),
		"created_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"sent_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"expected_delivery_datetime": V2DateTime.iso_from_total_hour(
			total_hour + delivery_hours
		),
		"delivered_datetime": (
			V2DateTime.iso_from_total_hour(total_hour) if delivery_hours == 0 else ""
		),
		"read_datetime": (
			V2DateTime.iso_from_total_hour(total_hour) if status == "read" else ""
		),
		"replied_message_id": replied_message_id,
		"related_appointment_id": related_appointment_id,
		"source_location_id": source_id,
		"destination_location_id": destination_id,
		"postage_centimes": postage,
		"status": status,
		"failure_reason": "",
		"idempotency_key": send_key,
	}
	messages[message_id] = message
	(outbox_index[sender_id] as Array).append(message_id)
	(inbox_index[recipient_id] as Array).append(message_id)
	if delivery_hours > 0:
		delivery_queue.append(message_id)
		_sort_delivery_queue()
	elif status == "read":
		_apply_message_knowledge(message, total_hour, knowledge)
	_remember_key(send_key, message_id)
	_trim_messages()
	return V2LifeLoopResult.ok(
		"消息已发送，投递与阅读分离",
		{"message": message.duplicate(true)}, [sender_id, recipient_id, message_id]
	)


func process_deliveries(total_hour: int) -> Array[V2LifeLoopResult]:
	var results: Array[V2LifeLoopResult] = []
	while not delivery_queue.is_empty():
		var message_id: String = delivery_queue[0]
		if not messages.has(message_id):
			delivery_queue.pop_front()
			continue
		var message: Dictionary = messages[message_id] as Dictionary
		var expected_hour: int = V2DateTime.total_hour_from_iso(
			str(message.get("expected_delivery_datetime", ""))
		)
		if expected_hour > total_hour:
			break
		delivery_queue.pop_front()
		var key: String = "message_delivery:%s" % message_id
		if processed_idempotency_keys.has(key):
			continue
		message["status"] = "delivered"
		message["delivered_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
		messages[message_id] = message
		_remember_key(key, message_id)
		results.append(V2LifeLoopResult.ok(
			"消息已经送达但仍未读", {"message": message.duplicate(true)},
			[str(message.get("recipient_person_id", "")), message_id]
		))
	return results


func read_message(
	person_id: String,
	message_id: String,
	total_hour: int,
	knowledge: KnowledgeService
) -> V2LifeLoopResult:
	if not messages.has(message_id):
		return V2LifeLoopResult.fail("unknown_message", "找不到消息", message_id, [message_id])
	var message: Dictionary = messages[message_id] as Dictionary
	if str(message.get("recipient_person_id", "")) != person_id:
		return V2LifeLoopResult.fail(
			"message_not_recipient", "当前人物不是消息收件人", message_id,
			[person_id, message_id]
		)
	var status: String = str(message.get("status", ""))
	if status in ["read", "replied"]:
		return V2LifeLoopResult.ok(
			"消息已经读过", {"message": message.duplicate(true), "already_read": true},
			[person_id, message_id]
		)
	if status != "delivered":
		return V2LifeLoopResult.fail(
			"message_not_delivered", "消息尚未送达", status, [person_id, message_id]
		)
	var key: String = "message_read:%s" % message_id
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.ok("消息已经读过", {"already_read": true})
	message["status"] = "read"
	message["read_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	messages[message_id] = message
	var knowledge_result: V2LifeLoopResult = _apply_message_knowledge(
		message, total_hour, knowledge
	)
	_remember_key(key, message_id)
	return V2LifeLoopResult.ok(
		"消息已读，相关事实进入人物认知",
		{
			"message": message.duplicate(true),
			"knowledge_result": knowledge_result.to_dict(),
		},
		[person_id, message_id]
	)


func reply_message(
	person_id: String,
	message_id: String,
	content_type: String,
	payload: Dictionary,
	total_hour: int,
	locations: SpatialLocationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null
) -> V2LifeLoopResult:
	if not messages.has(message_id):
		return V2LifeLoopResult.fail("unknown_message", "找不到原消息", message_id)
	var original: Dictionary = messages[message_id] as Dictionary
	if str(original.get("recipient_person_id", "")) != person_id:
		return V2LifeLoopResult.fail("message_not_recipient", "当前人物不能回复该消息")
	if str(original.get("status", "")) not in ["read", "replied"]:
		return V2LifeLoopResult.fail("message_not_read", "必须先阅读消息才能回复")
	var key: String = "message_reply:%s" % message_id
	if processed_idempotency_keys.has(key):
		var existing_id: String = str(processed_idempotency_keys[key])
		return V2LifeLoopResult.ok(
			"该消息已经回复",
			{"message": get_message(existing_id), "already_replied": true}
		)
	var result: V2LifeLoopResult = send_message(
		person_id,
		str(original.get("sender_person_id", "")),
		"local_letter",
		content_type,
		payload,
		total_hour,
		locations,
		knowledge,
		relationships,
		households,
		ledger,
		str(original.get("related_appointment_id", "")),
		message_id,
		key
	)
	if result.success:
		original["status"] = "replied"
		messages[message_id] = original
	return result


func post_public_notice(
	sender_id: String,
	source_location_id: String,
	content_type: String,
	payload: Dictionary,
	total_hour: int
) -> V2LifeLoopResult:
	if not _people.has(sender_id):
		return V2LifeLoopResult.fail("unknown_sender", "公告发布者不存在", sender_id)
	var message_id: String = "message:v2_3:%07d" % _next_sequence
	_next_sequence += 1
	var key: String = "message_send:%s" % message_id
	var message: Dictionary = {
		"message_id": message_id,
		"sender_person_id": sender_id,
		"recipient_person_id": "",
		"channel": "public_notice",
		"content_type": content_type,
		"payload": payload.duplicate(true),
		"created_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"sent_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"expected_delivery_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"delivered_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"read_datetime": "",
		"replied_message_id": "",
		"related_appointment_id": "",
		"source_location_id": source_location_id,
		"destination_location_id": source_location_id,
		"postage_centimes": 0,
		"status": "delivered",
		"failure_reason": "",
		"idempotency_key": key,
	}
	messages[message_id] = message
	public_notice_ids.append(message_id)
	_remember_key(key, message_id)
	return V2LifeLoopResult.ok(
		"公开公告已发布，但不会自动让全员知晓",
		{"message": message.duplicate(true)}, [sender_id, message_id]
	)


func read_public_notice(
	person_id: String,
	message_id: String,
	current_location_id: String,
	total_hour: int,
	knowledge: KnowledgeService
) -> V2LifeLoopResult:
	if message_id not in public_notice_ids or not messages.has(message_id):
		return V2LifeLoopResult.fail("unknown_public_notice", "找不到公开公告", message_id)
	var message: Dictionary = messages[message_id] as Dictionary
	if str(message.get("source_location_id", "")) != current_location_id:
		return V2LifeLoopResult.fail(
			"wrong_location", "必须到公告地点阅读", current_location_id,
			[person_id, message_id]
		)
	return _apply_message_knowledge(message, total_hour, knowledge, person_id)


func unread_count(person_id: String) -> int:
	var count: int = 0
	for raw_id: Variant in inbox_index.get(person_id, []) as Array:
		var message_id: String = str(raw_id)
		if messages.has(message_id) and str(
			(messages[message_id] as Dictionary).get("status", "")
		) == "delivered":
			count += 1
	return count


func inbox(person_id: String) -> Array[Dictionary]:
	return _messages_for_ids(inbox_index.get(person_id, []) as Array)


func outbox(person_id: String) -> Array[Dictionary]:
	return _messages_for_ids(outbox_index.get(person_id, []) as Array)


func get_message(message_id: String) -> Dictionary:
	var value: Variant = messages.get(message_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func get_persistent_state() -> Dictionary:
	return {
		"messages": messages.duplicate(true),
		"inbox_index": inbox_index.duplicate(true),
		"outbox_index": outbox_index.duplicate(true),
		"delivery_queue": delivery_queue.duplicate(),
		"public_notice_ids": public_notice_ids.duplicate(),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	for field: String in [
		"messages", "inbox_index", "outbox_index", "processed_idempotency_keys",
	]:
		if not state.get(field, {}) is Dictionary:
			return false
	for field: String in [
		"delivery_queue", "public_notice_ids", "processed_key_order",
	]:
		if not state.get(field, []) is Array:
			return false
	if int(state.get("next_sequence", 0)) < 1:
		return false
	var restored_messages: Dictionary = state["messages"] as Dictionary
	for raw_id: Variant in restored_messages.keys():
		var message_id: String = str(raw_id)
		if not restored_messages[message_id] is Dictionary:
			return false
		var message: Dictionary = restored_messages[message_id] as Dictionary
		if (
			message_id != str(message.get("message_id", ""))
			or str(message.get("status", "")) not in MESSAGE_STATUSES
		):
			return false
	messages = restored_messages.duplicate(true)
	inbox_index = (state["inbox_index"] as Dictionary).duplicate(true)
	outbox_index = (state["outbox_index"] as Dictionary).duplicate(true)
	delivery_queue.clear()
	for raw_id: Variant in state["delivery_queue"] as Array:
		var message_id: String = str(raw_id)
		if not messages.has(message_id):
			return false
		delivery_queue.append(message_id)
	public_notice_ids.clear()
	for raw_id: Variant in state["public_notice_ids"] as Array:
		public_notice_ids.append(str(raw_id))
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


func _apply_message_knowledge(
	message: Dictionary,
	total_hour: int,
	knowledge: KnowledgeService,
	reader_person_id: String = ""
) -> V2LifeLoopResult:
	var payload: Dictionary = message.get("payload", {}) as Dictionary
	var recipient_id: String = reader_person_id
	if recipient_id.is_empty():
		recipient_id = str(message.get("recipient_person_id", ""))
	if recipient_id.is_empty():
		recipient_id = str(payload.get("reader_person_id", ""))
	if recipient_id.is_empty():
		return V2LifeLoopResult.ok("公告尚未被具体人物阅读")
	var content_type: String = str(message.get("content_type", ""))
	var fact_id: String = str(payload.get("fact_id", ""))
	var subject_id: String = str(payload.get("subject_id", ""))
	var fact_type: String = str(payload.get("fact_type", content_type))
	var claim: Variant = payload.get("claim", payload)
	if content_type == "introduction":
		var target_id: String = str(payload.get("target_person_id", ""))
		fact_id = "person_identity:%s" % target_id
		subject_id = target_id
		fact_type = "person_identity"
		claim = {
			"display_name_zh": str(payload.get("target_display_name_zh", target_id)),
			"introduced_by": str(message.get("sender_person_id", "")),
		}
	if fact_id.is_empty() or subject_id.is_empty():
		return V2LifeLoopResult.ok("消息不包含可写入的正式事实")
	var channel_id: String = str(message.get("channel", "local_letter"))
	var channel: Dictionary = _channels.get(channel_id, {}) as Dictionary
	var confidence: int = int(channel.get("knowledge_confidence", 800))
	var expires_hour: int = int(payload.get("expires_hour", -1))
	return knowledge.record_fact(
		recipient_id, fact_id, subject_id, fact_type, claim,
		str(message.get("sender_person_id", "")), channel_id, total_hour,
		confidence, "reported" if confidence < 900 else "confirmed",
		expires_hour, str(message.get("message_id", "")),
		"knowledge:%s:%s:%s" % [
			recipient_id, fact_id, str(message.get("message_id", "")),
		]
	)


func _delivery_hours(
	channel: Dictionary,
	source_id: String,
	destination_id: String,
	locations: SpatialLocationService
) -> int:
	if source_id.is_empty() or destination_id.is_empty():
		return int(channel.get("delivery_hours_local", 0))
	var source: Dictionary = locations.get_location(source_id)
	var destination: Dictionary = locations.get_location(destination_id)
	var regional: bool = (
		str(source.get("parent_region_id", ""))
		!= str(destination.get("parent_region_id", ""))
	)
	return int(channel.get(
		"delivery_hours_regional" if regional else "delivery_hours_local", 0
	))


func _sort_delivery_queue() -> void:
	delivery_queue.sort_custom(func(left_id: String, right_id: String) -> bool:
		var left: Dictionary = messages.get(left_id, {}) as Dictionary
		var right: Dictionary = messages.get(right_id, {}) as Dictionary
		var left_hour: int = V2DateTime.total_hour_from_iso(
			str(left.get("expected_delivery_datetime", ""))
		)
		var right_hour: int = V2DateTime.total_hour_from_iso(
			str(right.get("expected_delivery_datetime", ""))
		)
		if left_hour != right_hour:
			return left_hour < right_hour
		return left_id < right_id
	)


func _messages_for_ids(ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id: Variant in ids:
		var message_id: String = str(raw_id)
		if messages.has(message_id):
			result.append((messages[message_id] as Dictionary).duplicate(true))
	return result


func _remember_key(key: String, entity_id: String) -> void:
	processed_idempotency_keys[key] = entity_id
	_processed_key_order.append(key)
	while _processed_key_order.size() > _key_limit:
		processed_idempotency_keys.erase(_processed_key_order.pop_front())


func _trim_messages() -> void:
	if messages.size() <= _message_limit:
		return
	var terminal_ids: Array[String] = []
	for raw_id: Variant in messages.keys():
		var message_id: String = str(raw_id)
		if str((messages[message_id] as Dictionary).get("status", "")) in [
			"read", "replied", "failed", "cancelled",
		]:
			terminal_ids.append(message_id)
	terminal_ids.sort()
	while messages.size() > _message_limit and not terminal_ids.is_empty():
		var removed_id: String = terminal_ids.pop_front()
		var removed: Dictionary = messages[removed_id] as Dictionary
		(inbox_index.get(str(removed.get("recipient_person_id", "")), []) as Array).erase(removed_id)
		(outbox_index.get(str(removed.get("sender_person_id", "")), []) as Array).erase(removed_id)
		messages.erase(removed_id)
