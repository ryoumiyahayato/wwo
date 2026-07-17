extends SceneTree
## Real-time binding and 1280×720 scene integration.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/v2_2/v2_2_life_loop_main.tscn") as PackedScene
	test.expect(packed != null, "V2.2 场景资源可加载")
	var view: V2LifeLoopMain = packed.instantiate() as V2LifeLoopMain
	test.expect(view != null, "V2.2 场景可实例化为强类型根")
	if view == null:
		test.finish(self, "V2.2 UI binding")
		return
	root.add_child(view)
	current_scene = view
	await process_frame
	await process_frame
	test.expect(view.life_simulation != null and view.life_simulation.initialized, "场景建立正式生活模拟")
	if view.life_simulation == null or not view.life_simulation.initialized:
		view.queue_free()
		test.finish(self, "V2.2 UI binding")
		return
	test.expect(
		view.life_binding.save_service is V2ReviewSaveService,
		"正式 V2.2 场景使用保留安全备份的存档服务"
	)
	var state: Dictionary = view.debug_state()
	test.expect(not bool(state.get("time_is_static_prototype", true)), "旧静态时间提示已删除")
	test.equal(str(state.get("identity", "")), "worker", "正常启动默认显示皮埃尔")
	test.expect(not bool(state.get("identity_switch_visible", true)), "正常模式不显示评审身份条")
	test.expect(bool(state.get("schedule_panel_available", false)), "人物中心具有安排活动入口")
	test.expect(bool(state.get("save_load_available", false)), "右上系统菜单具有保存载入入口")
	var schedule_rect: Rect2
	view.interface.open_panel_named("schedule", false)
	schedule_rect = view.interface.get_panel_rect()
	test.expect(
		schedule_rect.position.x >= 0
		and schedule_rect.position.y >= 0
		and schedule_rect.end.x <= 1280
		and schedule_rect.end.y <= 720,
		"1280×720下安排活动面板无主要裁切"
	)
	test.expect(view.life_simulation.clock.is_paused, "打开安排活动面板自动暂停")
	var schedule_count_before: int = (
		view.life_simulation.schedule.schedules[
			V2LifeLoopSimulation.PIERRE_ID
		] as Array
	).size()
	view.interface._activate("schedule_activity", "rest")
	test.expect(
		not view.interface.schedule_form.is_empty(),
		"选择活动只加载日期、时间、地点、成本与效果表单"
	)
	test.equal(
		(
			view.life_simulation.schedule.schedules[
				V2LifeLoopSimulation.PIERRE_ID
			] as Array
		).size(),
		schedule_count_before,
		"确认前不修改权威日程"
	)
	view.interface._activate("schedule_confirm", null)
	test.expect(
		(
			view.life_simulation.schedule.schedules[
				V2LifeLoopSimulation.PIERRE_ID
			] as Array
		).size() == schedule_count_before + 1,
		"确认后活动进入权威日程"
	)
	test.expect(view.interface.close_top_layer(), "Esc语义逐层关闭安排活动面板")
	await create_timer(0.2).timeout
	var before_hour: int = view.life_simulation.clock.total_hours
	view.interface._activate("speed", 8)
	view.life_simulation.advance_real_seconds(1.0)
	test.equal(view.life_simulation.clock.total_hours, before_hour + 8, "时间菜单真实控制8×权威时钟")
	view.interface._activate("pause", null)
	var paused_hour: int = view.life_simulation.clock.total_hours
	view.life_simulation.advance_real_seconds(2.0)
	test.equal(view.life_simulation.clock.total_hours, paused_hour, "暂停后状态停止")

	view.life_simulation.notifications.add(
		"personal", "notification", "界面未读测试", "打开生活动态后应标记已读",
		view.life_simulation.clock.total_hours, "ui_unread_test",
		[V2LifeLoopSimulation.PIERRE_ID]
	)
	test.equal(view.life_simulation.notifications.unread_count(), 1, "新增生活通知进入未读状态")
	view.interface.open_panel_named("activity", false)
	await process_frame
	await process_frame
	test.equal(view.life_simulation.notifications.unread_count(), 0, "打开生活动态面板后未读状态清零")
	view.interface.close_panel(false)

	view.interface.set_review_mode(true)
	view.interface.set_identity("official")
	test.equal(view.life_simulation.selected_person_id, V2LifeLoopSimulation.ALBERT_ID, "评审身份切换只改变观察人物")
	test.equal(view.life_binding.person_view().get("cash_centimes"), 8600, "阿尔贝个人现金实时显示且不混入机构预算")
	var review_binding := V2LifeLoopUiBinding.new(view.life_simulation, true)
	test.expect(
		review_binding.developer_command("step_hour").success,
		"评审或开发者模式可使用权威开发命令"
	)
	view.queue_free()
	await process_frame
	test.finish(self, "V2.2 UI binding")
