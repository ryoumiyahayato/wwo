extends SceneTree
## Verifies that the formal menu exposes the economy audit and the dashboard renders live data.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu_scene := load("res://scenes/v2_3/v2_3_life_loop_menu.tscn") as PackedScene
	test.expect(menu_scene != null, "正式菜单场景可载入")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	await process_frame
	await process_frame
	var audit_button := menu.find_child("EconomyAuditButton", true, false) as Button
	test.expect(audit_button != null, "正式菜单提供经济系统审计入口")
	test.expect(
		audit_button != null and not audit_button.disabled,
		"经济系统审计入口可正常点击"
	)
	menu.queue_free()
	await process_frame

	var dashboard_scene := load(
		"res://scenes/alpha/alpha_economy_dashboard_preview.tscn"
	) as PackedScene
	test.expect(dashboard_scene != null, "经济系统审计场景可载入")
	var dashboard := dashboard_scene.instantiate() as AlphaEconomyDashboardPreview
	root.add_child(dashboard)
	await process_frame
	await process_frame
	test.expect(dashboard.simulation.initialized, "经济审计界面完成模拟初始化")
	test.equal(
		dashboard.simulation.commodity_market.commodities.size(),
		67,
		"界面读取67种正式商品"
	)
	test.equal(
		dashboard.simulation.commodity_market.region_states.size(),
		8,
		"界面读取8个Alpha样本地区"
	)
	var tree_root: TreeItem = dashboard.market_tree.get_root()
	test.expect(
		tree_root != null and tree_root.get_child_count() > 0,
		"商品表格显示库存、价格、生产与消费行"
	)
	test.expect(dashboard.flow_list.item_count > 0, "界面显示调拨或国际贸易流")
	test.expect(dashboard.ai_list.item_count > 0, "界面显示人物AI经济决策")
	test.expect(
		"运行正常" in dashboard.status_label.text,
		"界面明确报告经济系统运行状态"
	)
	test.expect(
		dashboard.simulation.clock.total_hours >= 30 * 24,
		"审计预览至少推进30日并显示运行结果"
	)
	dashboard.queue_free()
	await process_frame
	test.finish(self, "Alpha economy UI audit")
