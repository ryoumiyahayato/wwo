class_name V23MinuteFormalInterface
extends V23FormalScheduleInterface
## Five-level minute clock controls, contextual travel leave and return-home decisions.


func _text(
	position: Vector2,
	value: String,
	font_size: int,
	color: Color,
	max_width: float = -1.0
) -> void:
	draw_string(
		_font,
		position,
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		max_width,
		font_size,
		color
	)


func _divider(position: Vector2, length: float, vertical: bool = false) -> void:
	var offset: Vector2 = Vector2(0.0, length) if vertical else Vector2(length, 0.0)
	draw_line(position, position + offset, LINE, 1.0)


func _draw() -> void:
	super._draw()
	var binding: V23ControlledUiBinding = _controlled_binding()
	if binding == null:
		return
	var prompt: Dictionary = binding.return_home_prompt_view()
	if not prompt.is_empty():
		_draw_return_home_prompt(prompt)


func close_top_layer() -> bool:
	var binding: V23ControlledUiBinding = _controlled_binding()
	if binding != null and not binding.return_home_prompt_view().is_empty():
		_show_toast("需要先决定返家或继续停留")
		return true
	return super.close_top_layer()


func get_panel_rect() -> Rect2:
	if open_panel == "time":
		return Rect2(1010.0, 88.0, 214.0, 236.0)
	return super.get_panel_rect()


func _draw_time_corner() -> void:
	_surface(TIME_CORNER, PANEL, Color(GOLD, 0.18), 10)
	_register(TIME_CORNER, "corner_time", null, "点击控制分钟权威时间")
	var date_label: String = "1900年3月12日 · 00:00"
	var state_label: String = "Ⅱ 暂停 · 1档"
	if life_binding != null:
		var time: Dictionary = life_binding.time_view()
		date_label = "%s · %s" % [
			str(time.get("date_display", "")),
			str(time.get("hour_display", "00:00")),
		]
		paused = bool(time.get("paused", true))
		speed = int(time.get("speed_level", time.get("speed", 1)))
		state_label = (
			"Ⅱ 暂停 · %s" % str(time.get("weekday_display", ""))
			if paused
			else "%s · %d档" % [
				str(time.get("weekday_display", "")), speed,
			]
		)
	_text(TIME_CORNER.position + Vector2(14.0, 24.0), date_label, 13, INK)
	_text(TIME_CORNER.position + Vector2(14.0, 47.0), state_label, 10, GOLD)
	_text(TIME_CORNER.end - Vector2(23.0, 20.0), "⌄", 14, INK_DIM)


func _draw_time_panel() -> void:
	var rect: Rect2 = _animated_rect(get_panel_rect(), Vector2(0.0, -24.0))
	_surface(rect, PANEL_SOLID, Color(GOLD, 0.28), 12)
	_register(rect, "consume")
	_text(rect.position + Vector2(14.0, 24.0), "分钟权威时间", 12, INK_MUTED)
	var pause_row := Rect2(
		rect.position.x + 8.0,
		rect.position.y + 34.0,
		rect.size.x - 16.0,
		27.0
	)
	_compact_action(
		pause_row,
		"Ⅱ  暂停",
		paused,
		"pause",
		null,
		"暂停分钟权威时间"
	)
	var descriptions: Dictionary = {
		1: "1分钟 / 0.1秒",
		2: "5分钟 / 0.1秒",
		3: "10分钟 / 0.1秒",
		4: "20分钟 / 0.1秒",
		5: "60分钟 / 0.1秒",
	}
	for index: int in range(5):
		var option: int = index + 1
		var row := Rect2(
			rect.position.x + 8.0,
			rect.position.y + 64.0 + float(index) * 31.0,
			rect.size.x - 16.0,
			28.0
		)
		_compact_action(
			row,
			"%d档  %s" % [option, str(descriptions[option])],
			not paused and speed == option,
			"speed",
			option,
			"每0.1现实秒推进指定游戏分钟；整点触发现有小时结算"
		)
	_text(
		rect.position + Vector2(14.0, rect.end.y - 15.0),
		"活动与交通分钟字段正在兼容迁移；旧结算仍在整点执行。",
		8,
		INK_DIM
	)


func _draw_return_home_prompt(prompt: Dictionary) -> void:
	_register(Rect2(Vector2.ZERO, size), "consume", null, "")
	var rect := Rect2(362.0, 184.0, 556.0, 336.0)
	_surface(rect, PANEL_SOLID, Color(AMBER, 0.68), 12)
	_register(rect, "consume")
	_text(rect.position + Vector2(24.0, 39.0), "人物准备返家", 22, INK)
	_text(
		rect.position + Vector2(24.0, 70.0),
		"%s目前位于%s。" % [
			str(prompt.get("person_name", "当前人物")),
			str(prompt.get("current_location_name", "当前位置")),
		],
		11,
		INK
	)
	_text(
		rect.position + Vector2(24.0, 96.0),
		"当前没有尚未完成的玩家活动，人物准备返回%s。" % str(
			prompt.get("home_location_name", "住所")
		),
		10,
		INK_MUTED
	)
	_divider(rect.position + Vector2(24.0, 122.0), rect.size.x - 48.0)
	_text(rect.position + Vector2(24.0, 151.0), "允许返家", 11, GREEN)
	_text(
		rect.position + Vector2(122.0, 151.0),
		"建立实际返家路线；到家后恢复正常自动日程。",
		9,
		INK_MUTED
	)
	_text(rect.position + Vector2(24.0, 184.0), "继续停留", 11, AMBER)
	_text(
		rect.position + Vector2(122.0, 184.0),
		"夜间每小时：疲劳 +%d，压力 +%d，健康 %d。" % [
			int(prompt.get("fatigue_per_hour", 0)),
			int(prompt.get("stress_per_hour", 0)),
			int(prompt.get("health_per_hour", 0)),
		],
		9,
		INK_MUTED
	)
	_text(
		rect.position + Vector2(24.0, 218.0),
		"时间已暂停。系统不会替玩家默认选择继续滞留。",
		9,
		BLUE
	)
	_primary_action(
		Rect2(rect.position.x + 24.0, rect.end.y - 66.0, 186.0, 38.0),
		"让人物回家",
		"return_home_accept",
		str(prompt.get("person_id", "")),
		"按实际路线返家，并解除临时停留指令"
	)
	_text_link(
		Rect2(rect.position.x + 244.0, rect.end.y - 64.0, 150.0, 34.0),
		"继续留在这里",
		"return_home_stay",
		str(prompt.get("person_id", "")),
		"明确阻止返家；夜间状态损耗将逐小时结算"
	)


func _activate(action: String, payload: Variant) -> void:
	var binding: V23ControlledUiBinding = _controlled_binding()
	match action:
		"return_home_accept":
			if binding == null:
				return
			var result: V2LifeLoopResult = binding.accept_return_home_prompt(
				str(payload)
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
			queue_redraw()
		"return_home_stay":
			if binding == null:
				return
			var result: V2LifeLoopResult = binding.continue_staying_prompt(
				str(payload)
			)
			_show_toast(("✓ " if result.success else "× ") + result.user_message)
			queue_redraw()
		"v2_3_travel_confirm":
			if binding == null:
				return
			var result: V2LifeLoopResult = binding.submit_travel()
			if (
				not result.success
				and result.error_code == "requires_leave_authorization"
			):
				leave_confirmation = result.data.duplicate(true)
				_show_toast("该行程与工作冲突，请确认是否请假")
			else:
				_show_toast(("✓ " if result.success else "× ") + result.user_message)
			queue_redraw()
		"leave_confirm_activity":
			if (
				binding != null
				and str(leave_confirmation.get("command_type", "")) == "travel"
			):
				var result: V2LifeLoopResult = binding.submit_travel_with_leave(
					leave_confirmation
				)
				_show_toast(("✓ " if result.success else "× ") + result.user_message)
				if result.success:
					leave_confirmation.clear()
				queue_redraw()
			else:
				super._activate(action, payload)
		_:
			super._activate(action, payload)
