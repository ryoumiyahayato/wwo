extends SceneTree
## Deterministic, cognition-limited fastest and cheapest route planning.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "路线测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 route planner")
		return
	var person_id: String = V2LifeLoopSimulation.PIERRE_ID
	var departure: int = simulation.clock.total_hours + 1
	var fastest: V2LifeLoopResult = simulation.preview_route(
		person_id, "location_lille_fives_factory", "fastest", departure
	)
	test.expect(fastest.success, "已知工厂可生成最快路线")
	test.equal(
		int(fastest.data.get("total_duration_hours", -1)), 1,
		"最快路线使用一小时市内交通"
	)
	test.equal(
		int(fastest.data.get("total_cost_centimes", -1)), 5,
		"最快路线包含五生丁票价"
	)
	var cheapest: V2LifeLoopResult = simulation.preview_route(
		person_id, "location_lille_fives_factory", "cheapest", departure
	)
	test.expect(cheapest.success, "已知工厂可生成最省路线")
	test.equal(
		int(cheapest.data.get("total_cost_centimes", -1)), 0,
		"最省路线优先选择零费用步行"
	)
	test.equal(
		str((cheapest.data.get("route_segments", []) as Array)[0].get("mode_id", "")),
		"walk",
		"最省路线明确记录步行方式"
	)
	var repeated: V2LifeLoopResult = simulation.preview_route(
		person_id, "location_lille_fives_factory", "fastest", departure
	)
	test.equal(
		repeated.data.get("path_key"), fastest.data.get("path_key"),
		"同输入路线稳定决胜"
	)
	test.expect(
		simulation.route_planner.cache_hits >= 1,
		"重复路线命中预计算缓存"
	)
	var unknown: V2LifeLoopResult = simulation.preview_route(
		person_id, "location_roubaix_centre", "fastest", departure
	)
	test.equal(unknown.error_code, "unknown_location", "未知目的地不能被全知规划")
	var invalid: V2LifeLoopResult = simulation.preview_route(
		person_id, "location_lille_fives_factory", "scenic", departure
	)
	test.equal(invalid.error_code, "invalid_preference", "非法路线偏好明确失败")
	var no_cash: V2LifeLoopResult = simulation.route_planner.plan_route(
		person_id,
		"location_lille_pierre_home",
		"location_lille_fives_factory",
		departure,
		"fastest",
		-1,
		950,
		false
	)
	test.equal(
		no_cash.error_code, "no_affordable_route",
		"不可用预算且过度疲劳时返回可解释的不可达失败"
	)
	test.expect(
		not no_cash.suggested_alternatives.is_empty(),
		"路线失败提供可执行替代建议"
	)
	test.finish(self, "V2.3 route planner")
