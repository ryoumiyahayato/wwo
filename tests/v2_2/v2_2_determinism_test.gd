extends SceneTree
## Direct 30 days versus 10-day snapshot/restore plus 20 days.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var direct := V2LifeLoopSimulation.new()
	var split := V2LifeLoopSimulation.new()
	test.expect(direct.initialize() and split.initialize(), "确定性两条路径可初始化")
	direct.run_days(30)
	split.run_days(10)
	var snapshot: Dictionary = split.get_persistent_state()
	var resumed := V2LifeLoopSimulation.new()
	resumed.initialize()
	var restored: V2LifeLoopResult = resumed.restore_persistent_state(snapshot)
	test.expect(restored.success, "10日状态可恢复到新模拟")
	resumed.run_days(20)
	var direct_digest: Dictionary = direct.deterministic_digest()
	var resumed_digest: Dictionary = resumed.deterministic_digest()
	for field: String in [
		"current_datetime", "person_states", "households", "ledger", "conditions",
		"attendance", "contracts", "relationships", "organizations", "processed",
		"pay_processed", "household_processed",
	]:
		test.equal(resumed_digest.get(field), direct_digest.get(field), "30日确定性字段一致：%s" % field)
	test.expect(direct.ledger_consistency().success and resumed.ledger_consistency().success, "两条路径账本均一致")
	test.finish(self, "V2.2 determinism")
