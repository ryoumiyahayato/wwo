extends SceneTree
## Formal V2.3 configuration, location indexes and initial cognition.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := V23Config.new()
	test.equal(config.load_all(), OK, "V2.3 全部数据驱动配置通过引用校验")
	test.equal(config.errors.size(), 0, "V2.3 配置没有校验错误")
	test.expect(
		config.location_records().size() >= 17,
		"扩展后的正式地点至少包含 17 个稳定节点"
	)
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "V2.3 组合根使用唯一权威时钟初始化")
	if not simulation.initialized:
		push_error(simulation.initialization_error)
		test.finish(self, "V2.3 locations")
		return
	test.equal(
		simulation.spatial_locations.locations.size(),
		config.location_records().size(),
		"全部正式地点 ID 进入同一空间索引"
	)
	test.equal(
		simulation.travel_graph.adjacency.size(),
		config.location_records().size(),
		"交通图覆盖全部扩展地点节点"
	)
	test.expect(
		simulation.travel_graph.edges.size() >= 22,
		"扩展交通图至少包含 22 条稳定边"
	)
	test.expect(simulation.travel_graph.graph_is_connected(), "整个正式交通图连通")
	test.equal(simulation.travel_graph.modes.size(), 3, "步行、市内交通和短途铁路齐备")
	test.expect(
		simulation.spatial_locations.knows_location(
			V2LifeLoopSimulation.PIERRE_ID, "location_lille_fives_factory"
		),
		"皮埃尔初始知道工厂"
	)
	test.expect(
		not simulation.spatial_locations.knows_location(
			V2LifeLoopSimulation.PIERRE_ID, "location_lille_albert_home"
		),
		"皮埃尔不知道阿尔贝住所"
	)
	test.expect(
		simulation.knowledge.knows_person(V2LifeLoopSimulation.PIERRE_ID, "jeanne"),
		"皮埃尔初始只从正式身份知识认识让娜"
	)
	test.expect(
		not simulation.knowledge.knows_person(
			V2LifeLoopSimulation.ALBERT_ID, "jeanne"
		),
		"阿尔贝不会认识让娜"
	)
	test.expect(
		simulation.knowledge.knows_person(
			V2LifeLoopSimulation.ALBERT_ID, V23LifeLoopSimulation.LUCIEN_ID
		),
		"阿尔贝初始认识吕西安"
	)
	test.equal(
		str(simulation.spatial_locations.position_for(
			V2LifeLoopSimulation.PIERRE_ID
		).get("current_location_id", "")),
		"location_lille_pierre_home",
		"皮埃尔初始正式位置为本人住所"
	)
	test.equal(
		simulation.schedule.schedules.size(),
		config.social_people().size(),
		"同一现有日程服务覆盖全部正式与背景人物"
	)
	test.finish(self, "V2.3 locations")
