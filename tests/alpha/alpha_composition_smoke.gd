extends SceneTree
## Alpha composition root: retained clock/space plus bounded world batches.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := AlphaSimulationService.new()
	test.expect(simulation.initialize(), "Alpha 组合根可初始化")
	if not simulation.initialized:
		push_error(simulation.initialization_error)
		test.finish(self, "Alpha composition smoke")
		return
	var counts: Dictionary = simulation.alpha_counts()
	test.equal(int(counts.get("countries", 0)), 2, "组合根使用两国正式世界")
	test.equal(int(counts.get("regions", 0)), 8, "组合根使用八地区正式世界")
	test.equal(int(counts.get("active_people", 0)), 8, "八名预制人物进入高精度层")
	test.equal(int(counts.get("background_people", 0)), 120, "一百二十名人物留在背景层")
	test.expect(
		int(counts.get("active_people", 0)) <= 20,
		"高精度人物遵守二十人上限"
	)
	test.equal(int(counts.get("enterprises", 0)), 12, "十二家企业进入持续世界")
	test.expect(
		bool(simulation.validate_alpha_integrity().get("success", false)),
		"初始化后的统一引用和账本闭合"
	)
	simulation.advance_hours(48)
	test.equal(simulation.alpha_hours_processed, 48, "Alpha 继续使用唯一小时钟")
	test.equal(
		int(simulation.world_dynamics.counters.get("daily_batches", 0)),
		2,
		"日边界运行两次，不在每帧扫描世界"
	)
	test.expect(
		simulation.alpha_ai.decisions.size() > 0,
		"非玩家活跃人物通过正式系统执行有限候选"
	)
	for decision: Dictionary in simulation.alpha_ai.decisions:
		test.expect(
			not (decision.get("known_fields_used", []) as Array).is_empty(),
			"AI 决定记录其读取的已知信息"
		)
	test.expect(
		bool(simulation.validate_alpha_integrity().get("success", false)),
		"运行四十八小时后统一引用和账本仍闭合"
	)
	var save_service := AlphaSaveService.new()
	var snapshot: Dictionary = save_service.build_snapshot(simulation)
	test.equal(
		save_service.validate_snapshot(snapshot).size(),
		0,
		"Alpha 快照通过结构、完整性和跨对象引用校验"
	)
	var restored := AlphaSimulationService.new()
	test.expect(restored.initialize(), "可建立独立 Alpha 恢复目标")
	test.expect(
		save_service.restore(snapshot, restored).success,
		"Alpha 快照可事务恢复"
	)
	test.equal(
		restored.clock.total_hours,
		simulation.clock.total_hours,
		"恢复保持唯一权威时间"
	)
	test.equal(
		restored.economy.ledger.owner_cash(restored.roster.player_character_id),
		simulation.economy.ledger.owner_cash(simulation.roster.player_character_id),
		"恢复保持正式现金账本"
	)
	test.finish(self, "Alpha composition smoke")
