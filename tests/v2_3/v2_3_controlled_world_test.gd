extends SceneTree
## Product regression for minute time, contextual leave, temporary stays and identity.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	test.equal(BuildInfo.GAME_NAME, "1900", "游戏名称固定为1900")
	test.expect(
		BuildInfo.display_version().begins_with("v0.001a ("),
		"首页版本使用独立的基础版本与构建标识"
	)

	var simulation := V23ProductSimulation.new()
	test.expect(simulation.initialize(), "正式产品模拟可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 controlled world")
		return
	var minute_clock: V23MinuteClock = simulation.clock as V23MinuteClock
	test.expect(minute_clock != null, "正式产品使用分钟权威时钟")
	if minute_clock == null:
		test.finish(self, "V2.3 controlled world")
		return
	minute_clock.set_paused(false)
	minute_clock.set_speed(1)
	var initial_hour: int = minute_clock.total_hours
	simulation.advance_real_seconds(0.1)
	test.equal(minute_clock.minute, 1, "1档每0.1秒推进1游戏分钟")
	test.equal(minute_clock.total_hours, initial_hour, "未跨整点时不提前执行小时结算")
	minute_clock.set_speed(2)
	simulation.advance_real_seconds(0.1)
	test.equal(minute_clock.minute, 6, "2档每0.1秒推进5游戏分钟")
	minute_clock.set_speed(5)
	simulation.advance_real_seconds(0.1)
	test.equal(minute_clock.minute, 6, "5档推进60分钟后保留分钟余数")
	test.equal(minute_clock.total_hours, initial_hour + 1, "5档每0.1秒跨过1个整点")
	minute_clock.set_paused(true)

	var albert: String = V2LifeLoopSimulation.ALBERT_ID
	var belgium_route: V2LifeLoopResult = simulation.preview_route(
		albert,
		"location_brussels_centre",
		"fastest",
		simulation.clock.total_hours + 1
	)
	test.expect(belgium_route.success, "里尔人物可规划前往比利时的正式路线")
	if belgium_route.success:
		test.expect(
			"location_brussels_centre" in (
				belgium_route.data.get("path_nodes", []) as Array
			),
			"跨国路线实际到达布鲁塞尔地点"
		)
	var germany_route: V2LifeLoopResult = simulation.preview_route(
		albert,
		"location_cologne_centre",
		"fastest",
		simulation.clock.total_hours + 1
	)
	test.expect(germany_route.success, "里尔人物可经比利时规划前往德国的正式路线")
	if germany_route.success:
		var germany_nodes: Array = germany_route.data.get("path_nodes", []) as Array
		test.expect(
			"location_brussels_centre" in germany_nodes
			and "location_cologne_centre" in germany_nodes,
			"德国路线实际经过布鲁塞尔并到达科隆"
		)

	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var travel_start: int = simulation.clock.total_hours + 1
	var travel_request: V2LifeLoopResult = simulation.request_travel(
		pierre,
		"location_lille_centre",
		"fastest",
		travel_start
	)
	test.expect(
		not travel_request.success
		and travel_request.error_code == "requires_leave_authorization",
		"工作时段旅行先返回请假确认而不是要求手工预先请假"
	)
	var travel_confirmed: V2LifeLoopResult = (
		simulation.authorize_leave_and_request_travel(
			pierre,
			"location_lille_centre",
			"fastest",
			travel_start
		)
	)
	test.expect(travel_confirmed.success, "确认后原子完成请假与旅行安排")
	var active_plan: Dictionary = simulation.travel_execution.active_plan_for_person(
		pierre
	)
	test.expect(not active_plan.is_empty(), "玩家旅行形成正式旅行计划")
	var arrival_hour: int = int(
		active_plan.get("expected_arrival_hour", simulation.clock.total_hours + 1)
	)
	if simulation.clock.total_hours < arrival_hour:
		simulation.advance_hours(arrival_hour - simulation.clock.total_hours)
	var position: Dictionary = simulation.spatial_locations.position_for(pierre)
	test.equal(
		str(position.get("current_location_id", "")),
		"location_lille_centre",
		"旅行完成后人物实际位于里尔市中心"
	)
	test.equal(
		simulation.manual_hold_for(pierre),
		"location_lille_centre",
		"玩家指定地点形成临时停留意图"
	)
	var sleep_result: V2LifeLoopResult = simulation.request_activity(
		pierre,
		"sleep",
		simulation.clock.total_hours + 1,
		8
	)
	test.expect(
		not sleep_result.success and sleep_result.error_code == "requires_location",
		"人物不能在市中心远程执行住所睡眠"
	)

	minute_clock.set_paused(false)
	var first_prompt_hour: int = _next_hour_of_day(
		simulation.clock.total_hours, 21
	)
	simulation.advance_hours(first_prompt_hour - simulation.clock.total_hours)
	var return_prompt: Dictionary = simulation.next_return_home_prompt()
	test.expect(not return_prompt.is_empty(), "晚间空闲时形成返家提示")
	test.equal(
		str(return_prompt.get("person_id", "")),
		pierre,
		"返家提示关联被玩家留在市中心的人物"
	)
	test.expect(minute_clock.is_paused, "返家提示出现时权威时间暂停")
	var condition_before_stay: Dictionary = simulation.conditions.get_state(pierre)
	var stay_result: V2LifeLoopResult = simulation.continue_staying_outside_home(
		pierre
	)
	test.expect(stay_result.success, "玩家可以明确阻止人物返家")
	test.expect(not minute_clock.is_paused, "处理唯一返家提示后恢复原运行状态")
	simulation.advance_hours(2)
	var condition_after_stay: Dictionary = simulation.conditions.get_state(pierre)
	test.expect(
		int(condition_after_stay.get("fatigue", 0))
		> int(condition_before_stay.get("fatigue", 0)),
		"夜间强制滞留逐小时增加疲劳"
	)
	test.expect(
		int(condition_after_stay.get("stress", 0))
		> int(condition_before_stay.get("stress", 0)),
		"夜间强制滞留逐小时增加压力"
	)
	test.expect(
		int(condition_after_stay.get("health", 0))
		< int(condition_before_stay.get("health", 0)),
		"夜间强制滞留逐小时降低健康"
	)

	var second_prompt_hour: int = _next_hour_of_day(
		simulation.clock.total_hours, 21
	)
	simulation.advance_hours(second_prompt_hour - simulation.clock.total_hours)
	return_prompt = simulation.next_return_home_prompt()
	test.expect(not return_prompt.is_empty(), "下一晚仍在外时再次询问返家")
	var return_result: V2LifeLoopResult = simulation.accept_return_home(pierre)
	test.expect(return_result.success, "确认返家会建立实际返家路线")
	test.expect(simulation.next_return_home_prompt().is_empty(), "确认后返家提示被清除")
	active_plan = simulation.travel_execution.active_plan_for_person(pierre)
	test.expect(not active_plan.is_empty(), "返家不是瞬移而是正式旅行计划")
	arrival_hour = int(
		active_plan.get("expected_arrival_hour", simulation.clock.total_hours + 1)
	)
	if simulation.clock.total_hours < arrival_hour:
		simulation.advance_hours(arrival_hour - simulation.clock.total_hours)
	position = simulation.spatial_locations.position_for(pierre)
	var home_id: String = "location_lille_pierre_home"
	test.equal(
		str(position.get("current_location_id", "")),
		home_id,
		"返家行程完成后人物实际位于住所"
	)
	test.equal(
		simulation.manual_hold_for(pierre),
		"",
		"返家后解除临时停留并恢复正常自动日程"
	)

	simulation.spatial_locations.force_set_at_location(
		pierre, home_id, simulation.clock.total_hours
	)
	var work_hour: int = _next_unreleased_work_hour(simulation, pierre)
	test.expect(work_hour >= 0, "可找到下一小时合同工作义务")
	if work_hour >= 0:
		var rest_request: V2LifeLoopResult = simulation.request_activity(
			pierre, "rest", work_hour, 1
		)
		test.expect(
			not rest_request.success
			and rest_request.error_code == "requires_leave_authorization",
			"地点正确但与工作冲突时只要求确认请假"
		)
		var rest_confirmed: V2LifeLoopResult = (
			simulation.authorize_leave_and_request_activity(
				pierre, "rest", work_hour, 1
			)
		)
		test.expect(rest_confirmed.success, "确认后请假与休息活动原子写入")
		test.equal(
			str(simulation.schedule.activity_for_hour(
				pierre, work_hour
			).get("activity_type", "")),
			"rest",
			"玩家活动覆盖原合同日程"
		)

	var map_file := FileAccess.open(
		"res://data/world_map/map_modes.json", FileAccess.READ
	)
	var map_document: Dictionary = JSON.parse_string(
		map_file.get_as_text()
	) as Dictionary
	var zoom: Dictionary = map_document.get("zoom", {}) as Dictionary
	test.equal(float(zoom.get("maximum", 0.0)), 200.0, "地图最大倍率为200")
	test.equal(
		float(zoom.get("player_location_focus", 0.0)),
		180.0,
		"人物所在地默认聚焦倍率为180"
	)

	var menu_packed: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_menu.tscn"
	) as PackedScene
	var menu: V23LifeLoopMenu = menu_packed.instantiate() as V23LifeLoopMenu
	test.expect(menu != null, "正式首页可实例化")
	if menu != null:
		root.add_child(menu)
		await process_frame
		test.equal(
			str(menu.get_node("Center/Card/Margin/Content/TitleLabel").get("text")),
			"1900",
			"首页只显示固定游戏名称"
		)
		test.equal(
			str(menu.get_node("Center/Card/Margin/Content/PhaseLabel").get("text")),
			BuildInfo.display_version(),
			"首页单独显示可核对版本号"
		)
		menu.queue_free()
		await process_frame

	var packed: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_main.tscn"
	) as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "正式场景可实例化")
	if view != null:
		root.add_child(view)
		await process_frame
		await process_frame
		test.expect(
			view.interface is V23MinuteFormalInterface,
			"正式场景使用统一活动入口和分钟界面"
		)
		view.queue_free()
		await process_frame
	test.finish(self, "V2.3 controlled world")


func _next_hour_of_day(total_hour: int, target_hour_of_day: int) -> int:
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	var candidate: int = total_hour - int(value.get("hour", 0)) + target_hour_of_day
	if candidate <= total_hour:
		candidate += 24
	return candidate


func _next_unreleased_work_hour(
	simulation: V23ProductSimulation,
	person_id: String
) -> int:
	for candidate: int in range(
		simulation.clock.total_hours + 1,
		simulation.clock.total_hours + 8 * 24
	):
		if (
			simulation.employment.is_required_work_hour(person_id, candidate)
			and not simulation.leave.covers(person_id, candidate)
		):
			return candidate
	return -1
