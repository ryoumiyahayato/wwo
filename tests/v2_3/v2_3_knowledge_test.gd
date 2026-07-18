extends SceneTree
## Knowledge provenance, confidence, contradiction, expiry and idempotency.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "认知测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 knowledge")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var now: int = simulation.clock.total_hours
	var first: V2LifeLoopResult = simulation.knowledge.record_fact(
		person_id, "weather:lille", "location_lille_centre", "weather",
		"晴", "jeanne", "local_letter", now, 650, "reported", now + 2,
		"", "knowledge:test:weather:first"
	)
	test.expect(first.success, "带来源与置信度的知识可记录")
	var repeated: V2LifeLoopResult = simulation.knowledge.record_fact(
		person_id, "weather:lille", "location_lille_centre", "weather",
		"晴", "jeanne", "local_letter", now, 650, "reported", now + 2,
		"", "knowledge:test:weather:first"
	)
	test.expect(bool(repeated.data.get("already_recorded", false)), "同幂等键不会重复新增知识")
	var contradiction: V2LifeLoopResult = simulation.knowledge.record_fact(
		person_id, "weather:lille", "location_lille_centre", "weather",
		"雨", "character_jules_martin", "rumor", now + 1, 300, "rumor",
		now + 4, "", "knowledge:test:weather:second"
	)
	test.expect(contradiction.success, "相互矛盾的来源可并存")
	test.equal(
		str((contradiction.data.get("knowledge", {}) as Dictionary).get(
			"status", ""
		)),
		"contradicted",
		"矛盾事实被明确标记"
	)
	var first_record: Dictionary = first.data.get("knowledge", {}) as Dictionary
	test.equal(
		simulation.knowledge.get_record(
			str(first_record.get("knowledge_id", ""))
		).get("status"),
		"contradicted",
		"旧事实也建立双向矛盾状态"
	)
	var expiring: V2LifeLoopResult = simulation.knowledge.record_fact(
		person_id, "market:hours", "location_lille_wazemmes_market",
		"opening_hours", "今日营业", "direct_observation", "direct_observation",
		now, 1000, "confirmed", now + 1, "", "knowledge:test:expiry"
	)
	test.expect(expiring.success, "可建立带到期边界的确认知识")
	test.equal(simulation.knowledge.expire_due(now), 0, "到期前保持新鲜")
	test.expect(simulation.knowledge.expire_due(now + 1) >= 1, "到期边界转为过时")
	test.equal(
		simulation.knowledge.get_record(str(
			(expiring.data.get("knowledge", {}) as Dictionary).get("knowledge_id", "")
		)).get("freshness"),
		"expired",
		"过时知识保留但新鲜度变为 expired"
	)
	test.finish(self, "V2.3 knowledge")
