extends SceneTree
## Direct 30 days versus 10-day snapshot/restore plus 20 days.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var direct := V2LifeLoopSimulation.new()
	var split := V2LifeLoopSimulation.new()
	test.expect(direct.initialize() and split.initialize(), "确定性两条路径可初始化")
	if not direct.initialized or not split.initialized:
		test.finish(self, "V2.2 determinism")
		return
	direct.run_days(30)
	split.run_days(10)
	var snapshot: Dictionary = split.get_persistent_state()
	var resumed := V2LifeLoopSimulation.new()
	resumed.initialize()
	var restored: V2LifeLoopResult = resumed.restore_persistent_state(snapshot)
	test.expect(restored.success, "10日状态可恢复到新模拟")
	if not restored.success:
		test.finish(self, "V2.2 determinism")
		return
	resumed.run_days(20)
	var comparison: Dictionary = V2DeterminismAudit.comparison(direct, resumed)
	var fields: Dictionary = comparison.get("fields", {}) as Dictionary
	for field_variant: Variant in fields.keys():
		var field: String = str(field_variant)
		test.expect(bool(fields[field]), "30日确定性字段一致：%s" % field)
	test.expect(bool(comparison.get("all_fields_equal", false)), "完整 V2.2 权威状态逐字段一致")
	test.expect(
		direct.ledger_consistency().success and resumed.ledger_consistency().success,
		"两条路径账本均一致"
	)
	test.finish(self, "V2.2 determinism")
