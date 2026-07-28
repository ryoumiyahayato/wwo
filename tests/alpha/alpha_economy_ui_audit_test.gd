extends SceneTree
## Compatibility-named economy UI audit. The former two-country/eight-region
## dashboard has been retired; this validates the formal hemisphere economy UI.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var menu_scene := load(
		"res://scenes/formal/formal_world_menu.tscn"
	) as PackedScene
	test.expect(menu_scene != null, "正式世界菜单场景可载入")
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		test.expect(menu is FormalWorldMenu, "正式菜单使用半球产品控制器")
		menu.free()

	var world_scene := load(
		"res://scenes/formal/formal_world_main.tscn"
	) as PackedScene
	test.expect(world_scene != null, "正式半球政经场景可载入")
	if world_scene == null:
		test.finish(self, "Formal hemisphere economy UI audit")
		return
	var view := world_scene.instantiate() as FormalWorldApplication
	test.expect(view != null, "正式半球政经场景可实例化")
	if view == null:
		test.finish(self, "Formal hemisphere economy UI audit")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	_check_world_summary(view)
	_check_polity_projection(view)
	_check_interaction(view)
	view.queue_free()
	await process_frame
	test.finish(self, "Formal hemisphere economy UI audit")


func _check_world_summary(view: FormalWorldApplication) -> void:
	test.expect(view.formal_simulation.initialized, "正式政经界面完成世界初始化")
	var summary := view.formal_simulation.world_summary()
	test.equal(int(summary.get("commodity_count", 0)), 67, "界面读取67种正式商品")
	test.equal(
		int(summary.get("world_political_unit_count", 0)),
		151,
		"界面显示完整151单元政治世界"
	)
	test.equal(
		int(summary.get("major_economy_count", 0)),
		50,
		"界面显示50个高细节经济聚合体"
	)
	test.equal(
		int(summary.get("detailed_polity_unit_count", 0)),
		55,
		"界面区分55个高细节地图单元"
	)
	test.equal(
		int(summary.get("background_polity_count", 0)),
		96,
		"界面区分96个纯背景单元"
	)


func _check_polity_projection(view: FormalWorldApplication) -> void:
	view.selected_country_id = "grand_duchy_of_luxembourg"
	var luxembourg := view.formal_simulation.polity_summary(
		view._selected_polity_entity_id()
	)
	test.expect(
		bool(luxembourg.get("has_detailed_economy", false)),
		"卢森堡地图单元显示高细节经济"
	)
	test.equal(
		str(luxembourg.get("economy_entity_id", "")),
		"kingdom_of_luxembourg",
		"卢森堡地图别名投影到正确经济记录"
	)
	view.selected_country_id = "cshapes_gw_31"
	var background := view.formal_simulation.polity_summary(
		view._selected_polity_entity_id()
	)
	test.expect(not background.is_empty(), "背景地图单元仍有政经选择投影")
	test.expect(
		not bool(background.get("has_detailed_economy", true)),
		"背景单元界面不伪造详细经济"
	)


func _check_interaction(view: FormalWorldApplication) -> void:
	test.expect(
		view.get_node_or_null("PrototypeMap") == null,
		"正式政经界面不包含旧平面地图"
	)
	test.expect(
		view.get_node_or_null(
			"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D"
		) != null,
		"正式政经界面以三维半球为地图"
	)
	view.economy_panel_open = false
	view._activate_button("formal_economy_toggle")
	test.expect(view.economy_panel_open, "正式政经面板可打开")
	view.sim_paused = false
	var before_hour := view.formal_simulation.economy.total_hour
	for _index: int in range(4):
		view._on_clock_timer_timeout()
	test.expect(
		view.formal_simulation.economy.total_hour >= before_hour + 1,
		"界面时钟推进正式经济"
	)
	test.expect(
		view.formal_simulation.save_to_user(),
		"正式政经界面可写入正式世界存档"
	)
