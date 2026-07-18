class_name SocialIntroductionService
extends RefCounted
## Delayed introduction requests; identity and relationship unlock only on reading.

const STATUSES: PackedStringArray = [
	"requested", "delivered", "read", "accepted", "rejected",
	"introduction_sent", "completed", "failed",
]

var requests: Dictionary = {}
var processed_idempotency_keys: Dictionary = {}
var _next_sequence: int = 1


func configure() -> void:
	requests.clear()
	processed_idempotency_keys.clear()
	_next_sequence = 1


func request_introduction(
	requester_id: String,
	intermediary_id: String,
	target_id: String,
	total_hour: int,
	communication: CommunicationService,
	locations: SpatialLocationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null
) -> V2LifeLoopResult:
	if not knowledge.knows_person(requester_id, intermediary_id):
		return V2LifeLoopResult.fail(
			"unknown_intermediary", "当前人物不认识介绍人", intermediary_id,
			[requester_id, intermediary_id]
		)
	if knowledge.knows_person(requester_id, target_id):
		return V2LifeLoopResult.fail(
			"target_already_known", "目标人物已经认识", target_id,
			[requester_id, target_id]
		)
	if not knowledge.knows_person(intermediary_id, target_id):
		return V2LifeLoopResult.fail(
			"intermediary_unknown_target", "介绍人不认识目标人物", target_id,
			[intermediary_id, target_id]
		)
	var request_id: String = "introduction_request:v2_3:%05d" % _next_sequence
	var key: String = "introduction:%s:%s" % [request_id, target_id]
	if processed_idempotency_keys.has(key):
		return V2LifeLoopResult.fail("duplicate_introduction", "介绍请求已经存在", key)
	var sent: V2LifeLoopResult = communication.send_message(
		requester_id, intermediary_id, "local_letter", "introduction_request",
		{
			"request_id": request_id,
			"target_person_id": target_id,
			"fact_type": "introduction_request",
		},
		total_hour, locations, knowledge, relationships, households, ledger,
		"", "", "message_send:introduction_request:%s" % request_id
	)
	if not sent.success:
		return sent
	_next_sequence += 1
	var message: Dictionary = sent.data.get("message", {}) as Dictionary
	var request: Dictionary = {
		"request_id": request_id,
		"requester_id": requester_id,
		"intermediary_id": intermediary_id,
		"target_id": target_id,
		"request_message_id": str(message.get("message_id", "")),
		"introduction_message_id": "",
		"created_datetime": V2DateTime.iso_from_total_hour(total_hour),
		"decided_datetime": "",
		"completed_datetime": "",
		"status": "requested",
		"failure_reason": "",
		"idempotency_key": key,
	}
	requests[request_id] = request
	return V2LifeLoopResult.ok(
		"介绍请求已寄出，目标人物不会立即解锁",
		{"request": request.duplicate(true), "message": message},
		[requester_id, intermediary_id, target_id, request_id]
	)


func decide_after_read(
	request_id: String,
	total_hour: int,
	accept: bool,
	communication: CommunicationService,
	locations: SpatialLocationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService,
	households: V2HouseholdService = null,
	ledger: V2LedgerService = null
) -> V2LifeLoopResult:
	if not requests.has(request_id):
		return V2LifeLoopResult.fail(
			"unknown_introduction_request", "找不到介绍请求", request_id
		)
	var request: Dictionary = requests[request_id] as Dictionary
	var request_message: Dictionary = communication.get_message(
		str(request.get("request_message_id", ""))
	)
	if str(request_message.get("status", "")) not in ["read", "replied"]:
		return V2LifeLoopResult.fail(
			"introduction_request_unread", "介绍人必须先读请求", request_id
		)
	if str(request.get("status", "")) not in ["requested", "delivered", "read"]:
		return V2LifeLoopResult.ok(
			"介绍请求已经决定", {"request": request.duplicate(true), "already_decided": true}
		)
	request["decided_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	if not accept:
		request["status"] = "rejected"
		requests[request_id] = request
		return V2LifeLoopResult.ok("介绍请求被拒绝", {"request": request})
	var target_id: String = str(request.get("target_id", ""))
	var target_records: Array[Dictionary] = knowledge.records_for_subject(
		str(request.get("intermediary_id", "")), target_id
	)
	var display_name: String = target_id
	for record: Dictionary in target_records:
		if str(record.get("fact_type", "")) == "person_identity":
			var claim: Dictionary = record.get("claim", {}) as Dictionary
			display_name = str(claim.get("display_name_zh", target_id))
			break
	var reply: V2LifeLoopResult = communication.reply_message(
		str(request.get("intermediary_id", "")),
		str(request.get("request_message_id", "")),
		"introduction",
		{
			"request_id": request_id,
			"target_person_id": target_id,
			"target_display_name_zh": display_name,
		},
		total_hour, locations, knowledge, relationships, households, ledger
	)
	if not reply.success:
		request["status"] = "failed"
		request["failure_reason"] = reply.error_code
		requests[request_id] = request
		return reply
	request["status"] = "introduction_sent"
	request["introduction_message_id"] = str(
		(reply.data.get("message", {}) as Dictionary).get("message_id", "")
	)
	requests[request_id] = request
	return V2LifeLoopResult.ok(
		"介绍人同意，介绍消息正在投递",
		{"request": request.duplicate(true), "message": reply.data.get("message", {})},
		[str(request.get("requester_id", "")), target_id, request_id]
	)


func complete_after_read(
	request_id: String,
	total_hour: int,
	communication: CommunicationService,
	knowledge: KnowledgeService,
	relationships: V23RelationshipService
) -> V2LifeLoopResult:
	if not requests.has(request_id):
		return V2LifeLoopResult.fail(
			"unknown_introduction_request", "找不到介绍请求", request_id
		)
	var request: Dictionary = requests[request_id] as Dictionary
	if str(request.get("status", "")) == "completed":
		return V2LifeLoopResult.ok(
			"介绍已经完成", {"request": request.duplicate(true), "already_completed": true}
		)
	var message: Dictionary = communication.get_message(
		str(request.get("introduction_message_id", ""))
	)
	if str(message.get("status", "")) not in ["read", "replied"]:
		return V2LifeLoopResult.fail(
			"introduction_unread", "请求人必须阅读介绍消息", request_id
		)
	var requester_id: String = str(request.get("requester_id", ""))
	var target_id: String = str(request.get("target_id", ""))
	if not knowledge.knows_person(requester_id, target_id):
		return V2LifeLoopResult.fail(
			"introduction_knowledge_missing", "介绍消息未建立身份知识", target_id
		)
	var interaction: V2LifeLoopResult = relationships.apply_interaction(
		requester_id, target_id, "introduction", request_id, total_hour,
		"阅读经介绍人同意后送达的正式介绍消息"
	)
	if not interaction.success:
		return interaction
	request["status"] = "completed"
	request["completed_datetime"] = V2DateTime.iso_from_total_hour(total_hour)
	requests[request_id] = request
	processed_idempotency_keys[str(request.get("idempotency_key", ""))] = true
	return V2LifeLoopResult.ok(
		"介绍完成，新人物进入已知人物和联系人列表",
		{"request": request.duplicate(true), "relationship": interaction.data.get("relationship", {})},
		[requester_id, target_id, request_id]
	)


func request_for_message(message_id: String) -> Dictionary:
	for raw_request_id: Variant in requests.keys():
		var request: Dictionary = requests[raw_request_id] as Dictionary
		if message_id in [
			str(request.get("request_message_id", "")),
			str(request.get("introduction_message_id", "")),
		]:
			return request.duplicate(true)
	return {}


func get_persistent_state() -> Dictionary:
	return {
		"requests": requests.duplicate(true),
		"processed_idempotency_keys": processed_idempotency_keys.duplicate(true),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("requests", {}) is Dictionary
		or not state.get("processed_idempotency_keys", {}) is Dictionary
		or int(state.get("next_sequence", 0)) < 1
	):
		return false
	var restored: Dictionary = state["requests"] as Dictionary
	for raw_id: Variant in restored.keys():
		if not restored[raw_id] is Dictionary:
			return false
		var request: Dictionary = restored[raw_id] as Dictionary
		if (
			str(raw_id) != str(request.get("request_id", ""))
			or str(request.get("status", "")) not in STATUSES
		):
			return false
	requests = restored.duplicate(true)
	processed_idempotency_keys = (
		state["processed_idempotency_keys"] as Dictionary
	).duplicate(true)
	_next_sequence = int(state["next_sequence"])
	return true
