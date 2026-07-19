extends SceneTree
## Alpha review presets and neutral object-driven UI binding regression.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "Alpha 人工检查配置可载入")
	var review_ids: Array[String] = config.review_state_ids()
	test.equal(review_ids.size(), 11, "提供十一种可直接载入的人工检查状态")
	var immediate_ids: Array[String] = review_ids.duplicate()
	immediate_ids.erase("world_after_three_years")
	for review_state_id: String in immediate_ids:
		var simulation := AlphaSimulationService.new()
		test.expect(
			simulation.set_launch_review_state(review_state_id),
			"可选择人工检查状态：%s" % review_state_id
		)
		test.expect(
			simulation.initialize(),
			"人工检查状态通过正式服务建立：%s" % review_state_id
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
			"预设保持统一引用闭合：%s" % review_state_id
		)
		test.equal(
			str(simulation.current_intent.get("filter", "")),
			"all",
			"当前打算只保存筛选条件：%s" % review_state_id
		)
	var ui_simulation := AlphaSimulationService.new()
	test.expect(ui_simulation.initialize(), "中立 UI 测试世界可初始化")
	if ui_simulation.initialized:
		var binding := AlphaUiBinding.new(ui_simulation, true)
		for kind: String in [
			"person", "location", "enterprise", "organization", "job",
			"contract", "lender", "good", "asset",
		]:
			var objects: Array[Dictionary] = binding.object_list(kind)
			test.expect(
				not objects.is_empty(),
				"正式对象具有可发现入口：%s" % kind
			)
			var object_id: String = str(objects[0].get("id", ""))
			test.expect(
				not binding.object_detail(kind, object_id).is_empty(),
				"正式对象具有只读详情：%s" % kind
			)
		test.expect(
			bool(binding.developer_command("cash 50").get("success", false)),
			"开发工具可注入正式账本资金"
		)
		test.expect(
			bool(binding.developer_command("price grain 500").get(
				"success", false
			)),
			"开发工具可触发地区价格外部事件"
		)
		test.expect(
			bool(binding.developer_command("wage 2").get("success", false)),
			"开发工具可改变地区工资状态"
		)
		test.expect(
			bool(binding.developer_command("truth").get("success", false)),
			"开发工具可查看真实结算"
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
			"当前打算只汇总高亮、期限、风险和筛选"
		)
	test.finish(self, "Alpha UI and presets")
