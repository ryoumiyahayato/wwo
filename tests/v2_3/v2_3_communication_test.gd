extends SceneTree
## Delayed delivery, reading, knowledge transfer, reply and postage.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "通信测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 communication")
		return
	var sender: String = V2LifeLoopSimulation.PIERRE_ID
	var recipient: String = "jeanne"
	var cash_before: int = int(
		simulation.households.household_for_person(sender).get("cash_centimes", 0)
	)
	var sent: V2LifeLoopResult = simulation.send_private_message(
		sender, recipient, "meeting_report",
		{
			"fact_id": "fact:test:meeting",
			"subject_id": "union_metalworkers_nord",
			"fact_type": "organization_activity",
			"claim": "星期三开会",
			"expires_hour": simulation.clock.total_hours + 96,
		}
	)
	test.expect(sent.success, "已知联系渠道可寄出本地信件")
	var message: Dictionary = sent.data.get("message", {}) as Dictionary
	var message_id: String = str(message.get("message_id", ""))
	test.equal(message.get("status"), "in_transit", "寄出后先进入运输状态")
	test.equal(
		int(simulation.households.household_for_person(sender).get(
			"cash_centimes", 0
		)),
		cash_before - int(message.get("postage_centimes", 0)),
		"邮资进入既有家庭与账本经济"
	)
	var expected_hour: int = V2DateTime.total_hour_from_iso(
		str(message.get("expected_delivery_datetime", ""))
	)
	test.equal(
		simulation.communication.process_deliveries(expected_hour - 1).size(), 0,
		"预计送达边界前不会提前投递"
	)
	test.equal(
		simulation.communication.process_deliveries(expected_hour).size(), 1,
		"预计送达边界投递一次"
	)
	test.equal(
		simulation.communication.get_message(message_id).get("status"),
		"delivered",
		"投递完成仍保持未读"
	)
	var known_before_read: bool = false
	for record: Dictionary in simulation.knowledge.records_for_subject(
		recipient, "union_metalworkers_nord"
	):
		if str(record.get("fact_id", "")) == "fact:test:meeting":
			known_before_read = true
	test.expect(not known_before_read, "未阅读前消息事实不会进入收件人认知")
	var read: V2LifeLoopResult = simulation.read_message_now(recipient, message_id)
	test.expect(read.success, "收件人可在投递后阅读")
	var known_after_read: bool = false
	for record: Dictionary in simulation.knowledge.records_for_subject(
		recipient, "union_metalworkers_nord"
	):
		if str(record.get("fact_id", "")) == "fact:test:meeting":
			known_after_read = true
	test.expect(known_after_read, "阅读后消息事实进入人物认知")
	var reply: V2LifeLoopResult = simulation.communication.reply_message(
		recipient, message_id, "greeting_reply", {"text": "收到"},
		expected_hour + 1, simulation.spatial_locations, simulation.knowledge,
		simulation.dynamic_relationships, simulation.households, simulation.ledger
	)
	test.expect(reply.success, "阅读后可正式回信")
	test.equal(
		simulation.communication.get_message(message_id).get("status"),
		"replied",
		"原信记录回信状态"
	)
	var repeated_delivery: Array[V2LifeLoopResult] = (
		simulation.communication.process_deliveries(expected_hour + 100)
	)
	test.expect(
		repeated_delivery.size() <= 1,
		"重复处理投递队列不会重复投递原信"
	)
	test.finish(self, "V2.3 communication")
