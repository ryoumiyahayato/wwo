extends SceneTree
## Same inputs, save boundaries and future continuation remain deterministic.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := V23LifeLoopSimulation.new()
	var second := V23LifeLoopSimulation.new()
	test.expect(first.initialize() and second.initialize(), "双确定性环境初始化")
	if not first.initialized or not second.initialized:
		test.finish(self, "V2.3 determinism")
		return
	first.send_private_message(
		V2LifeLoopSimulation.PIERRE_ID, "jeanne", "greeting",
		{"text": "determinism"}
	)
	second.send_private_message(
		V2LifeLoopSimulation.PIERRE_ID, "jeanne", "greeting",
		{"text": "determinism"}
	)
	first.advance_hours(96)
	second.advance_hours(96)
	test.equal(
		_canonical_text(first.determinism_snapshot()),
		_canonical_text(second.determinism_snapshot()),
		"同初始种子、命令与小时数产生完全一致快照"
	)
	var saved: Dictionary = first.get_persistent_state()
	var restored := V23LifeLoopSimulation.new()
	test.expect(restored.initialize(), "确定性恢复环境初始化")
	test.expect(restored.restore_v2_3_state(saved).success, "中途快照可恢复")
	first.advance_hours(72)
	restored.advance_hours(72)
	test.equal(
		_canonical_text(first.determinism_snapshot()),
		_canonical_text(restored.determinism_snapshot()),
		"保存恢复边界不改变后续确定性"
	)
	test.equal(first.clock.total_hours, restored.clock.total_hours, "恢复后的权威时间连续")
	test.equal(
		first.travel_execution.processed_idempotency_keys,
		restored.travel_execution.processed_idempotency_keys,
		"旅行扣费幂等键跨存档保持"
	)
	test.finish(self, "V2.3 determinism")


static func _canonical_text(value: Dictionary) -> String:
	return JSON.stringify(V23SaveService._canonical(value), "", true)
