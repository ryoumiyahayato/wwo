class_name V23MinuteFormalInterfaceV2
extends V23MinuteFormalInterface
## Product-facing social planning panel. It exposes the choices that were
## previously hidden in the backend: goal, method, target, time and preparation.


func _draw_v2_3_sandbox_panel() -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	if binding == null:
		super._draw_v2_3_sandbox_panel()
		return
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(30.0, 0.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.36), 12)
	_register(rect, "consume")
	_close_control(rect)
	var view: Dictionary = binding.sandbox_view()
	_text(rect.position + Vector2(20.0, 32.0), "处境与行动计划", 21, INK)
	_text(
		rect.position + Vector2(20.0, 53.0),
		"先确定目标、方法、对象与时间；确认后才建立双方日程和实际行程。",
		8,
		GOLD
	)
	_draw_goal_choices(rect, view)
	_draw_method_choices(rect, view)
	_draw_target_choices(rect, view)
	_draw_time_and_preparation(rect, view)
	_draw_plan_preview(rect, view)
	_draw_recent_social_result(rect, view)


func _draw_goal_choices(rect: Rect2, view: Dictionary) -> void:
	_section_heading(rect.position + Vector2(20.0, 78.0), "1. 选择当前目标")
	var goals: Array = view.get("goals", []) as Array
	var selected: String = str(view.get("selected_goal_id", ""))
	if goals.is_empty():
		_text(rect.position + Vector2(20.0, 104.0), "当前没有有效目标。", 9, INK_DIM)
		return
	for index: int in range(mini(4, goals.size())):
		var goal: Dictionary = goals[index] as Dictionary
		var row := Rect2(
			rect.position.x + 20.0 + float(index % 2) * 278.0,
			rect.position.y + 98.0 + float(index / 2) * 31.0,
			266.0,
			27.0
		)
		var label: String = "%s · %s" % [
			_sandbox_kind_label(str(goal.get("kind", ""))),
			str(goal.get("title_zh", "")),
		]
		_compact_action(
			row,
			label,
			selected == str(goal.get("goal_id", "")),
			"sandbox_plan_goal",
			str(goal.get("goal_id", "")),
			"紧迫度 %d" % int(goal.get("urgency", 0))
		)


func _draw_method_choices(rect: Rect2, view: Dictionary) -> void:
	_section_heading(rect.position + Vector2(20.0, 166.0), "2. 选择行动方法")
	var methods: Array = view.get("methods", []) as Array
	var selected: String = str(view.get("selected_method_id", ""))
	if methods.is_empty():
		_text(rect.position + Vector2(20.0, 191.0), "当前目标没有可用方法。", 9, INK_DIM)
		return
	for index: int in range(mini(6, methods.size())):
		var method: Dictionary = methods[index] as Dictionary
		var row := Rect2(
			rect.position.x + 20.0 + float(index % 3) * 184.0,
			rect.position.y + 186.0 + float(index / 3) * 32.0,
			174.0,
			28.0
		)
		var label: String = str(method.get("label_zh", ""))
		if bool(method.get("illegal", false)):
			label += " · 违法"
		_compact_action(
			row,
			label,
			selected == str(method.get("method_id", "")),
			"sandbox_plan_method",
			str(method.get("method_id", "")),
			str(method.get("expected_consequence", ""))
		)


func _draw_target_choices(rect: Rect2, view: Dictionary) -> void:
	_section_heading(rect.position + Vector2(20.0, 258.0), "3. 选择人物对象")
	var targets: Array = view.get("targets", []) as Array
	var selected: String = str(view.get("selected_target_id", ""))
	if targets.is_empty():
		_text(
			rect.position + Vector2(20.0, 282.0),
			"当前方法不需要人物对象，或没有已知且可接触的人物。",
			8,
			INK_DIM
		)
		return
	for index: int in range(mini(4, targets.size())):
		var target: Dictionary = targets[index] as Dictionary
		_compact_action(
			Rect2(
				rect.position.x + 20.0 + float(index) * 137.0,
				rect.position.y + 276.0,
				129.0,
				28.0
			),
			str(target.get("display_name", "")),
			selected == str(target.get("person_id", "")),
			"sandbox_plan_target",
			str(target.get("person_id", "")),
			str(target.get("role", ""))
		)


func _draw_time_and_preparation(rect: Rect2, view: Dictionary) -> void:
	_section_heading(rect.position + Vector2(20.0, 322.0), "4. 时间与准备")
	_text(
		rect.position + Vector2(20.0, 348.0),
		"开始：%s" % str(view.get("selected_start_datetime", "")),
		9,
		INK
	)
	_compact_action(
		Rect2(rect.position.x + 188.0, rect.position.y + 332.0, 72.0, 27.0),
		"提前1时", false, "sandbox_plan_time", -1,
		"不能早于当前时间后一小时"
	)
	_compact_action(
		Rect2(rect.position.x + 266.0, rect.position.y + 332.0, 72.0, 27.0),
		"推后1时", false, "sandbox_plan_time", 1,
		"最多预排72小时"
	)
	var preparation: int = int(view.get("preparation", 400))
	for index: int in range(3):
		var value: int = [150, 400, 700][index]
		_compact_action(
			Rect2(
				rect.position.x + 356.0 + float(index) * 68.0,
				rect.position.y + 332.0,
				62.0,
				27.0
			),
			["仓促", "正常", "充分"][index],
			preparation == value,
			"sandbox_plan_preparation",
			value,
			"准备会影响结果，但不再提供必胜上限"
		)


func _draw_plan_preview(rect: Rect2, view: Dictionary) -> void:
	var preview: Dictionary = view.get("preview", {}) as Dictionary
	var preview_data: Dictionary = preview.get("data", {}) as Dictionary
	var line_y: float = rect.position.y + 378.0
	if preview.is_empty():
		_text(Vector2(rect.position.x + 20.0, line_y), "计划尚未完整。", 9, INK_DIM)
		return
	var success: bool = bool(preview.get("success", false))
	var summary: String = str(preview.get("message", ""))
	if success:
		summary = "%s · %s · %d小时 · 风险%d%s" % [
			str(preview_data.get("location_name", "未知地点")),
			str(preview_data.get("start_datetime", "")),
			int(preview_data.get("duration_hours", 0)),
			int(preview_data.get("risk", 0)),
			" · 违法" if bool(preview_data.get("illegal", false)) else "",
		]
	_text(
		Vector2(rect.position.x + 20.0, line_y),
		summary,
		9,
		GREEN if success else AMBER
	)
	var actor_route: Dictionary = preview_data.get("actor_route", {}) as Dictionary
	var target_route: Dictionary = preview_data.get("target_route", {}) as Dictionary
	var route_text: String = "到场：本人%s%s" % [
		"需要行程" if bool(actor_route.get("required", false)) else "已在地点",
		(
			"；对象需要行程" if bool(target_route.get("required", false))
			else ("；对象已在地点" if not target_route.is_empty() else "")
		),
	]
	_text(
		Vector2(rect.position.x + 20.0, line_y + 19.0),
		route_text,
		8,
		INK_MUTED
	)
	if success:
		_primary_action(
			Rect2(rect.end.x - 166.0, rect.position.y + 370.0, 142.0, 38.0),
			"确认并建立计划",
			"sandbox_plan_confirm",
			null,
			"建立实际旅行、双方日程和社会任务"
		)


func _draw_recent_social_result(rect: Rect2, view: Dictionary) -> void:
	_divider(Vector2(rect.position.x + 20.0, rect.position.y + 423.0), rect.size.x - 40.0)
	var tasks: Array = view.get("tasks", []) as Array
	var events: Array = view.get("events", []) as Array
	var task_text: String = "没有社会任务"
	if not tasks.is_empty():
		var task: Dictionary = tasks.back() as Dictionary
		task_text = "最近任务：%s · %s · %s" % [
			str(task.get("method_id", "")),
			str(task.get("status", "")),
			V2DateTime.iso_from_total_hour(int(task.get("start_hour", 0))),
		]
	_text(rect.position + Vector2(20.0, 448.0), task_text, 8, INK_MUTED)
	if not events.is_empty():
		var event: Dictionary = events.front() as Dictionary
		_text(
			rect.position + Vector2(20.0, 469.0),
			"最近已知事件：%s · %s · %s" % [
				str(event.get("datetime", "")),
				str(event.get("method_id", "")),
				"成功" if bool(event.get("success", false)) else "未成功",
			],
			8,
			INK_DIM
		)


func _activate(action: String, payload: Variant) -> void:
	var binding: V23ControlledUiBindingV2 = _planning_binding()
	var result: V2LifeLoopResult
	match action:
		"sandbox_plan_goal":
			result = binding.select_sandbox_goal(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_method":
			result = binding.select_sandbox_method(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_target":
			result = binding.select_sandbox_target(str(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_time":
			result = binding.shift_sandbox_start(int(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_preparation":
			result = binding.set_sandbox_preparation(int(payload))
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		"sandbox_plan_confirm":
			result = binding.submit_selected_sandbox_plan()
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
		_:
			super._activate(action, payload)
	queue_redraw()


func _planning_binding() -> V23ControlledUiBindingV2:
	return life_binding as V23ControlledUiBindingV2
