extends SceneTree
## Event-driven background people, spatial routines and bounded planning.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "NPC 空间日常环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 NPC spatial routine")
		return
	test.equal(
		simulation.background_person_ids.size(),
		simulation.v2_3_config.social_people().size()
		- V23LifeLoopSimulation.FORMAL_PERSON_IDS.size(),
		"背景人物索引覆盖正式配置中的全部非玩家人物"
	)
	test.equal(
		simulation.npc_routines.npc_plans.size(),
		simulation.v2_3_config.social_people().size(),
		"正式与背景人物共用事件驱动规划索引"
	)
	for person_id: String in simulation.background_person_ids:
		test.expect(
			not simulation.spatial_locations.position_for(person_id).is_empty(),
			"背景人物 %s 具有正式空间状态" % person_id
		)
	test.expect(
		not simulation.npc_routines.should_plan(
			"jeanne", simulation.clock.total_hours, "unsupported"
		),
		"未知重规划原因不会触发 NPC 全量规划"
	)
	simulation.npc_routines.queue_message("jeanne", "message:test:npc")
	simulation.npc_routines.queue_message("jeanne", "message:test:npc")
	test.equal(
		simulation.npc_routines.take_next_message("jeanne"),
		"message:test:npc",
		"NPC 消息队列去重并按到达顺序消费"
	)
	test.equal(
		simulation.npc_routines.take_next_message("jeanne"), "",
		"同一消息不会被 NPC 重复读取"
	)
	var calls_before: int = simulation.npc_routines.planning_call_count
	simulation.advance_hours(48)
	test.equal(simulation.v2_3_hours_processed, 48, "背景空间日常随权威小时推进")
	test.expect(
		simulation.npc_routines.planning_call_count - calls_before < 40,
		"48 小时内 NPC 只按事件或日边界进行有界规划"
	)
	for person_id: String in simulation.background_person_ids:
		var state: String = str(
			simulation.spatial_locations.position_for(person_id).get(
				"location_state", ""
			)
		)
		test.expect(
			state in SpatialLocationService.LOCATION_STATES,
			"背景人物 %s 保持有效位置状态" % person_id
		)
	test.finish(self, "V2.3 NPC spatial routine")
