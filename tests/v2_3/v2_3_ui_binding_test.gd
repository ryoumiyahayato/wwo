extends SceneTree
## V2.3 binding fields, limited cognition and 1280x720 panel bounds.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23LifeLoopSimulation.new()
	test.expect(simulation.initialize(), "V2.3 UI 绑定环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 UI binding")
		return
	var binding := V23LifeLoopUiBinding.new(simulation, true)
	var person: Dictionary = binding.person_view()
	test.equal(
		person.get("current_location_id"), "location_lille_pierre_home",
		"人物摘要显示权威当前位置"
	)
	test.equal(person.get("location_state"), "at_location", "人物摘要显示位置状态")
	test.expect(person.has("unread_message_count"), "人物摘要显示未读消息数")
	test.expect(person.has("knowledge_count"), "人物摘要显示认知记录数")
	var destinations: Array[Dictionary] = binding.travel_destination_options()
	var has_factory: bool = false
	var has_albert_home: bool = false
	for item: Dictionary in destinations:
		var location_id: String = str(item.get("location_id", ""))
		has_factory = has_factory or location_id == "location_lille_fives_factory"
		has_albert_home = has_albert_home or location_id == "location_lille_albert_home"
	test.expect(has_factory, "旅行列表包含人物已知工厂")
	test.expect(not has_albert_home, "旅行列表不泄露未知住所")
	test.expect(
		binding.preview_travel("location_lille_fives_factory").success,
		"界面预览生成正式路线而不直接移动人物"
	)
	test.equal(
		simulation.spatial_locations.position_for(
			V2LifeLoopSimulation.PIERRE_ID
		).get("current_location_id"),
		"location_lille_pierre_home",
		"路线预览不修改权威位置"
	)
	var limited_payload: Dictionary = binding.map_overlay_payload()
	var albert_home_visible: bool = false
	for location: Dictionary in limited_payload.get("locations", []) as Array:
		if str(location.get("location_id", "")) == "location_lille_albert_home":
			albert_home_visible = bool(location.get("visible", false))
	test.expect(not albert_home_visible, "普通地图载荷隐藏人物未知地点")
	test.expect(binding.set_truth_view(true).success, "评审模式可切换真相视图")
	var truth_payload: Dictionary = binding.map_overlay_payload()
	for location: Dictionary in truth_payload.get("locations", []) as Array:
		if str(location.get("location_id", "")) == "location_lille_albert_home":
			albert_home_visible = bool(location.get("visible", false))
	test.expect(albert_home_visible, "真相视图显式展示全量地点")

	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_main.tscn"
	) as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "V2.3 正式场景可实例化")
	if view == null:
		test.finish(self, "V2.3 UI binding")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	test.expect(
		view.life_simulation is V23LifeLoopSimulation
		and view.life_simulation.initialized,
		"正式场景建立 V2.3 组合根"
	)
	for panel_id: String in V23LifeLoopInterface.V2_3_PANEL_IDS:
		view.interface.open_panel_named(panel_id, false)
		var rect: Rect2 = view.interface.get_panel_rect()
		test.expect(
			rect.position.x >= 0.0 and rect.position.y >= 0.0
			and rect.end.x <= 1280.0 and rect.end.y <= 720.0,
			"1280×720 下 %s 面板无主要裁切" % panel_id
		)
	var state: Dictionary = view.debug_state()
	test.expect(bool(state.get("v2_3_scene", false)), "调试状态标记 V2.3 正式场景")
	view.queue_free()
	await process_frame
	test.finish(self, "V2.3 UI binding")
