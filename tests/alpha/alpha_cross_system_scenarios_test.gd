extends SceneTree
## Ten named deterministic integration scenarios and seven required world loops.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var runner := AlphaScenarioRunner.new()
	test.equal(
		AlphaScenarioRunner.SCENARIO_IDS.size(),
		10,
		"维护十个命名确定性集成场景"
	)
	for scenario_id: String in AlphaScenarioRunner.SCENARIO_IDS:
		if scenario_id == "three_year_unattended_world":
			continue
		var first: Dictionary = runner.run(scenario_id)
		test.expect(
			bool(first.get("success", false)),
			"集成场景通过：%s · %s" % [
				scenario_id, str(first.get("summary", "")),
			]
		)
		if not bool(first.get("success", false)):
			push_error(JSON.stringify(first, "\t"))
			continue
		test.equal(
			int(first.get("fixed_seed", 0)),
			int(AlphaScenarioRunner.FIXED_SEEDS[scenario_id]),
			"场景使用固定种子：%s" % scenario_id
		)
		test.expect(
			(first.get("trace", []) as Array).size() > 0,
			"场景生成可读事实摘要：%s" % scenario_id
		)
		test.expect(
			bool((first.get("integrity", {}) as Dictionary).get(
				"success", false
			)),
			"场景引用闭合：%s" % scenario_id
		)
		test.equal(
			(first.get("snapshot_errors", []) as Array).size(),
			0,
			"场景中途恢复后的快照有效：%s" % scenario_id
		)
	test.finish(self, "Alpha cross-system scenarios")
