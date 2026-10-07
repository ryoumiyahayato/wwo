extends SceneTree
## Retained formal-world checks. Superseded private UI binding is retired.

var test := FormalTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_simulation_binding()
	test.finish(self, "Formal hemisphere UI binding")


func _check_simulation_binding() -> void:
	var simulation := WorldBootstrap.new().build()
	test.expect(simulation.success, "正式世界UI绑定环境初始化")
	if not simulation.success:
		return
	var summary := simulation.world.economy_state.world_summary().merged({"world_political_unit_count": simulation.world.political_registry.entity_count(), "historical_political_record_count": simulation.world.historical_evidence.record_count(), "formal_person_count": simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, simulation.world.political_registry.entity_count() - int(simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))})
	test.equal(
		int(summary.get("world_political_unit_count", 0)),
		146,
		"UI状态源持有146个运行时政治实体"
	)
	test.equal(
		int(summary.get("major_economy_count", 0)),
		50,
		"UI状态源持有50个高细节经济聚合体"
	)
	test.equal(
		int(summary.get("detailed_polity_unit_count", 0)),
		55,
		"UI状态源区分55个高细节地图单元"
	)
	test.equal(
		int(summary.get("background_polity_count", 0)),
		91,
		"UI状态源区分91个纯背景运行时实体"
	)
	var australia := CurrentWorldPoliticalProjection.polity_summary("state:cshapes_gw_901", RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view, FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()))
	test.expect(
		bool(australia.get("has_detailed_economy", false)),
		"澳大利亚殖民地地图单元可投影聚合经济"
	)
	test.equal(
		str(australia.get("economy_entity_id", "")),
		"australia_colonies_1900",
		"地图选择绑定到正确经济聚合体"
	)
	var background := CurrentWorldPoliticalProjection.polity_summary("state:cshapes_gw_31", RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view, FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()))
	test.expect(not background.is_empty(), "背景政治单元具有正式选择投影")
	test.expect(
		not bool(background.get("has_detailed_economy", true)),
		"背景政治单元不伪造高细节经济"
	)
	var before_hour := int(summary.get("total_hour", 0))
	simulation.simulation_step.advance_minutes(60)
	test.equal(
		int(simulation.world.economy_state.world_summary().merged({"world_political_unit_count": simulation.world.political_registry.entity_count(), "historical_political_record_count": simulation.world.historical_evidence.record_count(), "formal_person_count": simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, simulation.world.political_registry.entity_count() - int(simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))}).get("total_hour", 0)),
		before_hour + 1,
		"UI时间源与正式经济共用同一小时"
	)
	var state := simulation.persistence.snapshot()
	test.equal(
		str(state.get("schema_id", "")),
		FormalPersistence.SCHEMA_ID,
		"UI保存入口使用正式世界存档Schema"
	)
