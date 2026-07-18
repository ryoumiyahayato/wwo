extends SceneTree
## End-to-end travel, public information, delayed introduction and save restore.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "完整闭环环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 full loop smoke")
		return
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	simulation.spatial_locations.force_set_at_location(
		pierre, "location_lille_public_square", simulation.clock.total_hours
	)
	var notice: V2LifeLoopResult = simulation.observe_public_notice(pierre)
	test.expect(notice.success, "人物到达公告地点后可实际阅读公开信息")
	test.expect(
		simulation.knowledge.records_for_subject(
			pierre, "union_metalworkers_nord"
		).size() > 0,
		"公开信息只在观察后进入个人认知"
	)
	simulation.spatial_locations.force_set_at_location(
		pierre, "location_lille_pierre_home", simulation.clock.total_hours
	)
	var introduction: V2LifeLoopResult = simulation.request_introduction(
		pierre, "jeanne", V23LifeLoopSimulation.JULES_ID
	)
	test.expect(introduction.success, "皮埃尔可经让娜请求介绍儒勒")
	var request: Dictionary = introduction.data.get("request", {}) as Dictionary
	var request_message_id: String = str(request.get("request_message_id", ""))
	var request_message: Dictionary = simulation.communication.get_message(
		request_message_id
	)
	var first_delivery: int = V2DateTime.total_hour_from_iso(
		str(request_message.get("expected_delivery_datetime", ""))
	)
	simulation.communication.process_deliveries(first_delivery)
	test.expect(
		simulation.read_message_now("jeanne", request_message_id).success,
		"中间人实际阅读介绍请求"
	)
	var updated_request: Dictionary = simulation.introductions.requests[
		str(request.get("request_id", ""))
	] as Dictionary
	var introduction_message_id: String = str(
		updated_request.get("introduction_message_id", "")
	)
	test.expect(not introduction_message_id.is_empty(), "中间人决定后寄出正式介绍回信")
	var introduction_message: Dictionary = simulation.communication.get_message(
		introduction_message_id
	)
	var second_delivery: int = V2DateTime.total_hour_from_iso(
		str(introduction_message.get("expected_delivery_datetime", ""))
	)
	simulation.communication.process_deliveries(second_delivery)
	test.expect(
		not simulation.knowledge.knows_person(
			pierre, V23LifeLoopSimulation.JULES_ID
		),
		"正式介绍送达但未读时仍不解锁陌生人"
	)
	test.expect(
		simulation.read_message_now(pierre, introduction_message_id).success,
		"请求者实际阅读正式介绍"
	)
	test.expect(
		simulation.knowledge.knows_person(
			pierre, V23LifeLoopSimulation.JULES_ID
		),
		"阅读介绍后人物身份进入认知"
	)
	test.equal(
		int(simulation.dynamic_relationships.get_relationship(
			pierre, V23LifeLoopSimulation.JULES_ID
		).get("familiarity", 0)),
		40,
		"介绍完成建立最低熟悉度 40 的新关系"
	)
	var snapshot: Dictionary = simulation.get_persistent_state()
	var restored := V23LifeLoopSimulation.new()
	test.expect(restored.initialize(), "完整闭环恢复环境初始化")
	test.expect(restored.restore_v2_3_state(snapshot).success, "完整闭环状态可保存恢复")
	test.expect(
		restored.knowledge.knows_person(
			pierre, V23LifeLoopSimulation.JULES_ID
		),
		"恢复后介绍产生的有限认知保持"
	)
	test.equal(
		restored.introductions.requests, simulation.introductions.requests,
		"恢复后延迟介绍状态与稳定 ID 保持"
	)
	test.finish(self, "V2.3 full loop smoke")
