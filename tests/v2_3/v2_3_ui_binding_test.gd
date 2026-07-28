extends SceneTree
## Compatibility-named UI binding guard. The former Lille flat-map binding has
## been retired; the formal hemisphere now binds political selection, detailed
## economy, time and save state directly to FormalWorldSimulation.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_simulation_binding()
	await _check_scene_binding()
	test.finish(self, "Formal hemisphere UI binding")


func _check_simulation_binding() -> void:
	var simulation := FormalWorldSimulation.new()
	test.expect(simulation.initialize(), "正式世界UI绑定环境初始化")
	if not simulation.initialized:
		return
	var summary := simulation.world_summary()
	test.equal(
		int(summary.get("world_political_unit_count", 0)),
		151,
		"UI状态源持有151个地图政治单元"
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
		96,
		"UI状态源区分96个纯背景地图单元"
	)
	var australia := simulation.polity_summary("cshapes_gw_901")
	test.expect(
		bool(australia.get("has_detailed_economy", false)),
		"澳大利亚殖民地地图单元可投影聚合经济"
	)
	test.equal(
		str(australia.get("economy_entity_id", "")),
		"australia_colonies_1900",
		"地图选择绑定到正确经济聚合体"
	)
	var background := simulation.polity_summary("cshapes_gw_31")
	test.expect(not background.is_empty(), "背景政治单元具有正式选择投影")
	test.expect(
		not bool(background.get("has_detailed_economy", true)),
		"背景政治单元不伪造高细节经济"
	)
	var before_hour := int(summary.get("total_hour", 0))
	simulation.advance_minutes(60)
	test.equal(
		int(simulation.world_summary().get("total_hour", 0)),
		before_hour + 1,
		"UI时间源与正式经济共用同一小时"
	)
	var state := simulation.get_persistent_state()
	test.equal(
		str(state.get("schema_id", "")),
		FormalWorldSimulation.SCHEMA_ID,
		"UI保存入口使用正式世界存档Schema"
	)


func _check_scene_binding() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(
		"res://scenes/formal/formal_world_main.tscn"
	) as PackedScene
	test.expect(packed != null, "正式半球UI场景可加载")
	if packed == null:
		return
	var view := packed.instantiate() as FormalWorldApplication
	test.expect(view != null, "正式半球UI场景可实例化")
	if view == null:
		return
	root.add_child(view)
	await process_frame
	await process_frame
	test.expect(view.formal_simulation.initialized, "场景绑定正式世界组合根")
	test.expect(
		view.get_node_or_null("PrototypeMap") == null,
		"场景绑定不再包含旧平面地图"
	)
	test.expect(
		view.get_node_or_null(
			"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D"
		) != null,
		"场景绑定真实三维半球"
	)
	view.selected_country_id = "cshapes_gw_901"
	var selected := view.formal_simulation.polity_summary(
		view._selected_polity_entity_id()
	)
	test.equal(
		str(selected.get("economy_entity_id", "")),
		"australia_colonies_1900",
		"半球选择传递到政经面板"
	)
	view.economy_panel_open = false
	view._activate_button("formal_economy_toggle")
	test.expect(view.economy_panel_open, "政经面板使用正式按钮动作")
	view.sim_paused = false
	var before_hour := view.formal_simulation.economy.total_hour
	for _index: int in range(4):
		view._on_clock_timer_timeout()
	test.expect(
		view.formal_simulation.economy.total_hour >= before_hour + 1,
		"场景计时器推进正式经济"
	)
	test.equal(
		root.content_scale_size,
		Vector2i(1280, 720),
		"正式UI使用1280×720内容缩放基准"
	)
	test.equal(
		Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
		),
		Vector2i(1280, 720),
		"项目视口配置保持1280×720"
	)
	view.queue_free()
	await process_frame
