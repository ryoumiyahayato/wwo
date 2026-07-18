extends SceneTree
## Six-dimensional dynamic relationships and causal idempotent history.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "关系测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 relationships")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var target_id: String = "jeanne"
	var initial: Dictionary = simulation.dynamic_relationships.get_relationship(
		person_id, target_id
	)
	for dimension: String in V23RelationshipService.DIMENSIONS:
		test.expect(initial.has(dimension), "关系包含维度 %s" % dimension)
	var interaction: V2LifeLoopResult = (
		simulation.dynamic_relationships.apply_interaction(
			person_id, target_id, "face_to_face", "interaction:test:one",
			simulation.clock.total_hours, "双方实际同地交谈"
		)
	)
	test.expect(interaction.success, "实际互动可改变动态关系")
	var updated: Dictionary = simulation.dynamic_relationships.get_relationship(
		person_id, target_id
	)
	test.equal(
		int(updated.get("familiarity", 0)),
		int(initial.get("familiarity", 0)) + 8,
		"面对面互动应用数据驱动熟悉度变化"
	)
	test.equal(
		(updated.get("interaction_history", []) as Array).size(), 1,
		"关系历史保存因果事件"
	)
	var repeated: V2LifeLoopResult = (
		simulation.dynamic_relationships.apply_interaction(
			person_id, target_id, "face_to_face", "interaction:test:one",
			simulation.clock.total_hours, "重复调用"
		)
	)
	test.expect(bool(repeated.data.get("already_settled", false)), "重复互动结算幂等")
	test.equal(
		int(simulation.dynamic_relationships.get_relationship(
			person_id, target_id
		).get("familiarity", 0)),
		int(updated.get("familiarity", 0)),
		"重复结算不会二次改变关系"
	)
	var cooldown: V2LifeLoopResult = simulation.dynamic_relationships.can_contact(
		person_id, target_id, "local_letter", simulation.clock.total_hours + 1,
		simulation.knowledge
	)
	test.equal(cooldown.error_code, "contact_cooldown", "互动后联系冷却由权威关系时间约束")
	test.equal(
		simulation.dynamic_relationships.contact_candidates(
			V2LifeLoopSimulation.ALBERT_ID, simulation.knowledge
		).size(),
		1,
		"联系人列表只来自人物已知且有渠道的动态关系"
	)
	test.finish(self, "V2.3 relationships")
