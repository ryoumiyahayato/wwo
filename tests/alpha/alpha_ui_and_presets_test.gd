extends SceneTree
## Quarantined grid-service presets and binding regression.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var configured_main: String = str(
		ProjectSettings.get_setting("application/run/main_scene", "")
	)
	test.equal(
		configured_main,
		"res://scenes/v2_3/v2_3_life_loop_menu.tscn",
		"普通启动保持正式V2.3世界地图入口"
	)
	var gated_scene: PackedScene = load(
		"res://scenes/alpha/alpha_main.tscn"
	) as PackedScene
	test.expect(gated_scene != null, "旧Alpha路径保留安全路由场景")
	if gated_scene != null:
		var gated_instance: Node = gated_scene.instantiate()
		test.expect(
			gated_instance is AlphaFixtureGate,
			"旧Alpha路径不再直接实例化架空网格界面"
		)
		gated_instance.free()
	var fixture_scene: PackedScene = load(
		"res://scenes/alpha/alpha_grid_fixture.tscn"
	) as PackedScene
	test.expect(fixture_scene != null, "内部网格夹具使用独立场景")
	if fixture_scene != null:
		var fixture_instance: Node = fixture_scene.instantiate()
		test.expect(
			fixture_instance is AlphaGridFixture,
			"内部夹具具有明确的诊断界面类型"
		)
		fixture_instance.free()

	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "网格服务回归配置可载入")
	var review_ids: Array[String] = config.review_state_ids()
	test.equal(review_ids.size(), 11, "保留十一种内部回归状态")
	var immediate_ids: Array[String] = review_ids.duplicate()
	immediate_ids.erase("world_after_three_years")
	for review_state_id: String in immediate_ids:
		var simulation := AlphaSimulationService.new()
		test.expect(
			simulation.set_launch_review_state(review_state_id),
			"可选择内部回归状态：%s" % review_state_id
		)
		test.expect(
			simulation.initialize(),
			"内部回归状态通过服务建立：%s" % review_state_id
		)
		if not simulation.initialized:
			push_error(
				"%s: %s" % [
					review_state_id, simulation.alpha_initialization_error,
				]
			)
			continue
		test.expect(
			bool(simulation.validate_alpha_integrity().get("success", false)),
			"夹具预设保持统一引用闭合：%s" % review_state_id
		)
		test.equal(
			str(simulation.current_intent.get("filter", "")),
			"all",
			"夹具筛选状态默认不限制对象：%s" % review_state_id
		)
	var ui_simulation := AlphaSimulationService.new()
	test.expect(ui_simulation.initialize(), "内部绑定测试世界可初始化")
	if ui_simulation.initialized:
		var binding := AlphaUiBinding.new(ui_simulation, true)
		for kind: String in [
			"person", "location", "enterprise", "organization", "job",
			"contract", "lender", "good", "asset",
		]:
			var objects: Array[Dictionary] = binding.object_list(kind)
			test.expect(
				not objects.is_empty(),
				"夹具服务可枚举对象：%s" % kind
			)
			var object_id: String = str(objects[0].get("id", ""))
			test.expect(
				not binding.object_detail(kind, object_id).is_empty(),
				"夹具服务可读取对象：%s" % kind
			)
		test.expect(
			bool(binding.developer_command("cash 50").get("success", false)),
			"内部工具可注入账本资金"
		)
		test.expect(
			bool(binding.developer_command("price grain 500").get(
				"success", false
			)),
			"内部工具可触发地区价格事件"
		)
		test.expect(
			bool(binding.developer_command("wage 2").get("success", false)),
			"内部工具可改变地区工资状态"
		)
		test.expect(
			bool(binding.developer_command("truth").get("success", false)),
			"内部工具可查看真实结算"
		)
		var intent_fields_present: bool = true
		for field: String in [
			"highlight_object_ids", "deadline_ids", "risk_ids", "filter",
		]:
			intent_fields_present = (
				intent_fields_present
				and ui_simulation.current_intent.has(field)
			)
		test.expect(
			intent_fields_present,
			"内部筛选只汇总高亮、期限、风险和对象类型"
		)
	test.finish(self, "Quarantined grid fixture binding")
