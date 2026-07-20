extends SceneTree
## End-to-end guard for the eight unfinished social-sandbox paths.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "完成版社会沙盒可初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 social sandbox completion")
		return
	var sandbox: V23SocialSandboxServiceV2 = (
		simulation.social_sandbox as V23SocialSandboxServiceV2
	)
	var binding := V23ControlledUiBindingV2.new(simulation, true)
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var goal: Dictionary = _goal(sandbox.goals_for(pierre), "maintenance")
	test.expect(not goal.is_empty(), "玩家有可持续的稳定目标")
	var stable_goal_id: String = str(goal.get("goal_id", ""))
	sandbox.mark_dirty([pierre])
	sandbox.reevaluate_dirty(simulation.clock.total_hours)
	goal = _goal(sandbox.goals_for(pierre), "maintenance")
	test.equal(
		str(goal.get("goal_id", "")), stable_goal_id,
		"同一人物与处境键重新评估后保持同一目标ID"
	)
	var missing_target: V2LifeLoopResult = sandbox.submit_intent(
		pierre,
		stable_goal_id,
		"contact_person",
		"",
		"player",
		{"current_hour": simulation.clock.total_hours}
	)
	test.expect(
		not missing_target.success and missing_target.error_code == "target_required",
		"玩家方法不再由后台随机补齐人物对象"
	)
	var view: Dictionary = binding.sandbox_view()
	test.expect(
		view.has("selected_goal_id")
		and view.has("selected_method_id")
		and view.has("selected_target_id")
		and view.has("selected_start_hour")
		and view.has("preparation")
		and view.has("preview"),
		"正式绑定公开目标、方法、对象、时间、准备和预览"
	)
	var goal_selection: V2LifeLoopResult = binding.select_sandbox_goal(stable_goal_id)
	test.expect(goal_selection.success, "玩家可明确选择目标")
	var contact_method: V2LifeLoopResult = binding.select_sandbox_method(
		"contact_person"
	)
	test.expect(contact_method.success, "玩家可明确选择联系方法")
	var target_result: V2LifeLoopResult = binding.select_sandbox_target("jeanne")
	test.expect(target_result.success, "玩家可明确选择让娜作为对象")
	for _step: int in range(14):
		binding.shift_sandbox_start(1)
	binding.set_sandbox_preparation(700)
	view = binding.sandbox_view()
	var preview: Dictionary = view.get("preview", {}) as Dictionary
	test.expect(bool(preview.get("success", false)), "计划预览验证双方路线与时间")
	var submit: V2LifeLoopResult = binding.submit_selected_sandbox_plan()
	test.expect(submit.success, "确认后建立社会行动计划")
	if submit.success:
		var task: Dictionary = submit.data.get("task", {}) as Dictionary
		test.expect(
			not str(task.get("schedule_activity_id", "")).is_empty(),
			"行动人物绑定权威日程"
		)
		test.expect(
			not str(task.get("target_schedule_activity_id", "")).is_empty(),
			"行动对象也具有同一时段的到场日程"
		)
		test.expect(
			bool(task.get("travel_required", false)),
			"非同地行动通过正式旅行服务建立到场过程"
		)
		var end_hour: int = int(task.get("end_hour", simulation.clock.total_hours + 1))
		simulation.advance_hours(maxi(0, end_hour - simulation.clock.total_hours))
		var event: Dictionary = _event_for_task(
			sandbox.event_ledger, str(task.get("task_id", ""))
		)
		test.expect(not event.is_empty(), "实际旅行和双方日程完成后形成事件")
		test.expect(
			not bool(event.get("guaranteed_success", true)),
			"充分准备不再形成必胜结果"
		)
	var repay_goal: Dictionary = _goal(sandbox.goals_for(pierre), "maintenance")
	var repay: V2LifeLoopResult = sandbox.submit_intent(
		pierre,
		str(repay_goal.get("goal_id", "")),
		"repay_favor",
		"jeanne",
		"player",
		{
			"current_hour": simulation.clock.total_hours,
			"start_hour": simulation.clock.total_hours + 12,
			"preparation": 700,
			"location_id": "location_lille_public_square",
		}
	)
	if repay.success:
		var repay_task: Dictionary = repay.data.get("task", {}) as Dictionary
		simulation.advance_hours(maxi(
			0,
			int(repay_task.get("end_hour", simulation.clock.total_hours + 1))
			- simulation.clock.total_hours
		))
		var repay_event: Dictionary = _event_for_task(
			sandbox.event_ledger, str(repay_task.get("task_id", ""))
		)
		test.expect(
			not bool(repay_event.get("success", true))
			or str(repay_event.get("failure_reason", "")).contains("承诺"),
			"没有既有承诺时偿还人情不会反向制造新承诺"
		)
	var snapshot: Dictionary = V23SaveService.new().build_snapshot(simulation)
	test.expect(
		V23SaveService.new().validate_snapshot(snapshot).is_empty(),
		"新增计划字段和稳定目标保持存档有效"
	)
	test.finish(self, "V2.3 social sandbox completion")


static func _goal(source: Array[Dictionary], kind: String) -> Dictionary:
	for goal: Dictionary in source:
		if str(goal.get("kind", "")) == kind:
			return goal
	return {}


static func _event_for_task(
	events: Array[Dictionary], task_id: String
) -> Dictionary:
	for event: Dictionary in events:
		if str(event.get("task_id", "")) == task_id:
			return event
	return {}
