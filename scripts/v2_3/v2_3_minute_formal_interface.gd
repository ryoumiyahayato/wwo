class_name V23MinuteFormalInterface
extends V23FormalScheduleInterface
## Five-level minute clock controls for the formal product scene.


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
