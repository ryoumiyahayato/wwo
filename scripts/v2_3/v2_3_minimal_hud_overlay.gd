class_name V23MinimalHudOverlay
extends Control

const PAPER := Color("#d3cfbd")
const PAPER_DARK := Color("#b9b39e")
const INK := Color("#252925")
const INK_MUTED := Color("#535b54")
const GOLD := Color("#b7a35f")
const PANEL := Color(0.016, 0.030, 0.034, 0.96)
const PANEL_BORDER := Color(0.72, 0.64, 0.38, 0.30)

var host: Control
var field_book_open: bool = false
var field_book_progress: float = 0.0
var _refresh_timer: Timer


func configure(target: Control) -> void:
	host = target


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.5
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(queue_redraw)
	add_child(_refresh_timer)
	set_process(false)
	queue_redraw()


func set_field_book_open(open: bool) -> void:
	field_book_open = open
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var target: float = 1.0 if field_book_open else 0.0
	field_book_progress = move_toward(field_book_progress, target, delta * 4.6)
	queue_redraw()
	if is_equal_approx(field_book_progress, target):
		set_process(false)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	var position := button.position
	if _visible_book_tab_rect().has_point(position) or (field_book_open and _book_close_rect().has_point(position)):
		set_field_book_open(not field_book_open)
		get_viewport().set_input_as_handled()
		return
	if _country_cover_rect().has_point(position):
		_host_activate("corner_country", null)
		get_viewport().set_input_as_handled()
		return
	if _character_cover_rect().has_point(position):
		_host_activate("corner_character", null)
		get_viewport().set_input_as_handled()
		return
	if _time_cover_rect().has_point(position):
		_host_activate("corner_time", null)
		get_viewport().set_input_as_handled()
		return
	if _newspaper_rect().has_point(position):
		_host_activate("v2_3_open", "v2_3_messages")
		get_viewport().set_input_as_handled()


func _draw() -> void:
	_draw_country_sigil()
	_draw_character_sigil()
	_draw_clock_corner()
	_draw_newspaper_corner()
	_draw_field_book()


func _draw_country_sigil() -> void:
	var cover := _country_cover_rect()
	_draw_panel(cover)
	var icon_rect := Rect2(cover.position + Vector2(15.0, 9.0), Vector2(62.0, 62.0))
	var colors := _country_colors(_home_country_key())
	var center := icon_rect.get_center()
	var radius := icon_rect.size.x * 0.45
	draw_circle(center, radius, colors[0])
	for index: int in range(1, colors.size()):
		var angle := TAU * float(index) / float(colors.size())
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center - direction * radius * 0.78, center + direction * radius * 0.78, colors[index], 5.0, true)
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.92, 0.90, 0.80, 0.88), 1.5, true)
	draw_arc(center, radius * 0.62, -PI * 0.5, PI * 0.5, 24, Color(0.86, 0.84, 0.74, 0.54), 1.0, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), Color(0.90, 0.87, 0.74, 0.52), 1.0, true)


func _draw_character_sigil() -> void:
	var cover := _character_cover_rect()
	_draw_panel(cover)
	var icon_rect := Rect2(cover.position + Vector2(15.0, 8.0), Vector2(64.0, 64.0))
	match _role_category():
		"farmer":
			_draw_farmer_icon(icon_rect)
		"merchant":
			_draw_merchant_icon(icon_rect)
		"intellectual":
			_draw_intellectual_icon(icon_rect)
		"official":
			_draw_official_icon(icon_rect)
		"royal":
			_draw_royal_icon(icon_rect)
		_:
			_draw_worker_icon(icon_rect)


func _draw_clock_corner() -> void:
	var cover := _time_cover_rect()
	_draw_panel(cover)
	var time := _time_view()
	var hour_text := str(time.get("hour_display", "08:00"))
	var parts := hour_text.split(":")
	var hour := int(parts[0]) if parts.size() > 0 else 8
	var minute := int(parts[1]) if parts.size() > 1 else 0
	var center := cover.position + Vector2(43.0, cover.size.y * 0.5)
	var radius := 25.0
	draw_circle(center, radius, Color(0.07, 0.09, 0.085, 0.98))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.87, 0.82, 0.61, 0.92), 1.5, true)
	for index: int in range(12):
		var angle := -PI * 0.5 + TAU * float(index) / 12.0
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 3.0)
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - (7.0 if index % 3 == 0 else 5.0))
		draw_line(inner, outer, Color(0.84, 0.80, 0.65, 0.78), 1.0, true)
	var minute_angle := -PI * 0.5 + TAU * float(minute) / 60.0
	var hour_angle := -PI * 0.5 + TAU * (float(hour % 12) + float(minute) / 60.0) / 12.0
	draw_line(center, center + Vector2(cos(hour_angle), sin(hour_angle)) * 13.5, Color(0.95, 0.91, 0.78, 1.0), 2.2, true)
	draw_line(center, center + Vector2(cos(minute_angle), sin(minute_angle)) * 19.0, Color(0.74, 0.86, 0.79, 1.0), 1.4, true)
	draw_circle(center, 2.0, GOLD)
	var date_label := str(time.get("date_display", "1900年3月12日"))
	var state_label := "暂停" if bool(time.get("paused", true)) else "%d档" % int(time.get("speed_level", time.get("speed", 1)))
	_draw_text(cover.position + Vector2(82.0, 29.0), date_label, 13, Color(0.90, 0.90, 0.82, 1.0))
	_draw_text(cover.position + Vector2(82.0, 53.0), "%s · %s" % [hour_text, state_label], 11, GOLD)


func _draw_newspaper_corner() -> void:
	var rect := _newspaper_rect()
	draw_rect(rect, Color(0.74, 0.73, 0.66, 0.94), true)
	draw_rect(rect, Color(0.25, 0.28, 0.25, 0.70), false, 1.0)
	draw_line(rect.position + Vector2(12.0, 26.0), rect.position + Vector2(rect.size.x - 12.0, 26.0), Color(0.24, 0.27, 0.24, 0.62), 2.0)
	draw_line(rect.position + Vector2(12.0, 30.0), rect.position + Vector2(rect.size.x - 12.0, 30.0), Color(0.24, 0.27, 0.24, 0.38), 1.0)
	_draw_text(rect.position + Vector2(13.0, 20.0), "已知信息", 13, INK)
	var messages := _message_headlines()
	for index: int in range(mini(3, messages.size())):
		_draw_text(rect.position + Vector2(15.0, 49.0 + float(index) * 18.0), "— " + str(messages[index]), 10, INK_MUTED)


func _draw_field_book() -> void:
	var shifted_tab := _visible_book_tab_rect()
	draw_rect(shifted_tab, Color(0.22, 0.19, 0.14, 0.98), true)
	draw_rect(shifted_tab, Color(0.75, 0.64, 0.36, 0.48), false, 1.2)
	draw_line(shifted_tab.position + Vector2(shifted_tab.size.x - 12.0, 14.0), shifted_tab.end - Vector2(12.0, 14.0), Color(0.78, 0.67, 0.40, 0.48), 2.0)
	if field_book_progress <= 0.01:
		return
	var final_rect := _book_open_rect()
	var start_rect := Rect2(Vector2(-final_rect.size.x * 0.72, final_rect.position.y + final_rect.size.y * 0.18), final_rect.size * Vector2(0.72, 0.68))
	var rect := Rect2(start_rect.position.lerp(final_rect.position, field_book_progress), start_rect.size.lerp(final_rect.size, field_book_progress))
	var alpha := smoothstep(0.12, 1.0, field_book_progress)
	draw_rect(rect, Color(0.12, 0.10, 0.075, 0.72 * alpha), true)
	var page_gap := 14.0
	var left_page := Rect2(rect.position + Vector2(18.0, 16.0), Vector2(rect.size.x * 0.5 - 18.0 - page_gap * 0.5, rect.size.y - 32.0))
	var right_page := Rect2(Vector2(rect.position.x + rect.size.x * 0.5 + page_gap * 0.5, rect.position.y + 16.0), Vector2(rect.size.x * 0.5 - 18.0 - page_gap * 0.5, rect.size.y - 32.0))
	draw_rect(left_page, Color(PAPER, alpha), true)
	draw_rect(right_page, Color(PAPER, alpha), true)
	draw_rect(left_page, Color(0.24, 0.22, 0.17, 0.54 * alpha), false, 1.0)
	draw_rect(right_page, Color(0.24, 0.22, 0.17, 0.54 * alpha), false, 1.0)
	draw_rect(Rect2(Vector2(rect.get_center().x - 7.0, rect.position.y + 12.0), Vector2(14.0, rect.size.y - 24.0)), Color(0.20, 0.16, 0.11, 0.84 * alpha), true)
	if field_book_progress < 0.72:
		return
	_draw_page_heading(left_page, "今日事项")
	_draw_page_heading(right_page, "愿景与野心")
	_draw_page_lines(left_page, _left_page_lines())
	_draw_page_lines(right_page, _right_page_lines())
	var close_rect := _book_close_rect()
	draw_rect(close_rect, Color(0.26, 0.21, 0.15, 0.96), true)
	_draw_text(close_rect.position + Vector2(10.0, 18.0), "收起", 10, Color(0.88, 0.81, 0.65, 1.0))


func _draw_page_heading(page: Rect2, title: String) -> void:
	_draw_text(page.position + Vector2(24.0, 34.0), title, 18, INK)
	draw_line(page.position + Vector2(22.0, 45.0), page.position + Vector2(page.size.x - 22.0, 45.0), Color(0.28, 0.29, 0.25, 0.62), 2.0)
	draw_line(page.position + Vector2(22.0, 49.0), page.position + Vector2(page.size.x - 22.0, 49.0), Color(0.28, 0.29, 0.25, 0.34), 1.0)


func _draw_page_lines(page: Rect2, lines: Array[String]) -> void:
	var y := page.position.y + 76.0
	for line: String in lines:
		for piece: String in _wrap_text(line, 22):
			if y > page.end.y - 28.0:
				return
			_draw_text(Vector2(page.position.x + 26.0, y), piece, 12, INK_MUTED)
			y += 19.0
		y += 8.0


func _left_page_lines() -> Array[String]:
	var person := _profile_view()
	var lines: Array[String] = []
	var actions: Array = person.get("available_actions", []) as Array
	if not actions.is_empty():
		lines.append("可做事项：" + "、".join(actions))
	var schedule := _today_schedule()
	if not schedule.is_empty():
		lines.append("今日安排：")
		for index: int in range(mini(3, schedule.size())):
			var item: Dictionary = schedule[index] as Dictionary
			lines.append("%s  %s" % [str(item.get("start_display", item.get("display_start", ""))), str(item.get("display_name", item.get("activity_name", item.get("type", "事项"))))])
	var situations := _sandbox_view().get("situations", []) as Array
	if not situations.is_empty():
		lines.append("需要注意：" + str((situations[0] as Dictionary).get("title_zh", "当前处境")))
	lines.append("提示：先确认人物所在地、时间与权限，再安排需要到场的行动。")
	return lines


func _right_page_lines() -> Array[String]:
	var person := _profile_view()
	var lines: Array[String] = []
	var plan_detail: Dictionary = person.get("plan_detail", {}) as Dictionary
	var plan := str(person.get("plan", plan_detail.get("title", "尚未形成明确愿景")))
	lines.append("当前愿景：" + plan)
	var goal := str(plan_detail.get("goal", ""))
	if not goal.is_empty():
		lines.append("目标：" + goal)
	var next_step := str(plan_detail.get("next_step", ""))
	if not next_step.is_empty():
		lines.append("下一步：" + next_step)
	var concern := str(person.get("primary_concern", ""))
	if not concern.is_empty():
		lines.append("主要顾虑：" + concern)
	var goals := _sandbox_view().get("goals", []) as Array
	if not goals.is_empty():
		lines.append("现实目标：" + str((goals[0] as Dictionary).get("title_zh", "改善当前处境")))
	return lines


func _draw_worker_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, 25.0, Color(0.17, 0.22, 0.21, 0.98))
	draw_line(c + Vector2(-17.0, 17.0), c + Vector2(15.0, -15.0), GOLD, 5.0, true)
	draw_line(c + Vector2(-8.0, -17.0), c + Vector2(19.0, 10.0), Color(0.83, 0.84, 0.76, 1.0), 4.0, true)
	draw_arc(c, 25.0, 0.0, TAU, 40, Color(0.84, 0.79, 0.59, 0.78), 1.2, true)


func _draw_farmer_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, 25.0, Color(0.16, 0.23, 0.17, 0.98))
	draw_line(c + Vector2(0.0, 20.0), c + Vector2(0.0, -18.0), GOLD, 2.5, true)
	for offset: float in [-12.0, -4.0, 4.0, 12.0]:
		draw_arc(c + Vector2(0.0, offset), 8.0, -0.2, 2.7, 16, Color(0.73, 0.82, 0.55, 0.96), 2.2, true)


func _draw_merchant_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, 25.0, Color(0.20, 0.20, 0.15, 0.98))
	draw_line(c + Vector2(0.0, -17.0), c + Vector2(0.0, 18.0), GOLD, 2.0, true)
	draw_line(c + Vector2(-18.0, -8.0), c + Vector2(18.0, -8.0), GOLD, 2.0, true)
	draw_arc(c + Vector2(-13.0, 2.0), 8.0, 0.0, PI, 20, Color(0.86, 0.84, 0.70, 1.0), 2.0, true)
	draw_arc(c + Vector2(13.0, 2.0), 8.0, 0.0, PI, 20, Color(0.86, 0.84, 0.70, 1.0), 2.0, true)


func _draw_intellectual_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, 25.0, Color(0.15, 0.19, 0.22, 0.98))
	var left := Rect2(c + Vector2(-20.0, -12.0), Vector2(18.0, 25.0))
	var right := Rect2(c + Vector2(2.0, -12.0), Vector2(18.0, 25.0))
	draw_rect(left, Color(0.84, 0.82, 0.70, 0.94), true)
	draw_rect(right, Color(0.84, 0.82, 0.70, 0.94), true)
	draw_line(c + Vector2(0.0, -12.0), c + Vector2(0.0, 13.0), GOLD, 2.0)


func _draw_official_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, 25.0, Color(0.18, 0.19, 0.20, 0.98))
	draw_rect(Rect2(c + Vector2(-17.0, -14.0), Vector2(34.0, 27.0)), Color(0.80, 0.77, 0.63, 0.94), false, 2.0)
	draw_line(c + Vector2(-10.0, -7.0), c + Vector2(10.0, -7.0), GOLD, 2.0)
	draw_line(c + Vector2(-10.0, 0.0), c + Vector2(10.0, 0.0), GOLD, 2.0)
	draw_line(c + Vector2(-10.0, 7.0), c + Vector2(4.0, 7.0), GOLD, 2.0)


func _draw_royal_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_circle(c, 25.0, Color(0.21, 0.15, 0.17, 0.98))
	var crown := PackedVector2Array([
		c + Vector2(-20.0, 12.0), c + Vector2(-16.0, -11.0), c + Vector2(-6.0, 0.0),
		c + Vector2(0.0, -17.0), c + Vector2(7.0, 0.0), c + Vector2(17.0, -11.0),
		c + Vector2(20.0, 12.0),
	])
	draw_colored_polygon(crown, GOLD)
	draw_line(c + Vector2(-20.0, 13.0), c + Vector2(20.0, 13.0), Color(0.94, 0.88, 0.67, 1.0), 3.0)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL, true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)


func _draw_text(position: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _wrap_text(value: String, max_chars: int) -> Array[String]:
	var output: Array[String] = []
	var remaining := value.strip_edges()
	while remaining.length() > max_chars:
		output.append(remaining.substr(0, max_chars))
		remaining = remaining.substr(max_chars)
	if not remaining.is_empty():
		output.append(remaining)
	return output


func _host_activate(action: String, payload: Variant) -> void:
	if host != null and host.has_method("_activate"):
		host.call("_activate", action, payload)
		host.queue_redraw()


func _binding() -> Object:
	if host == null:
		return null
	return host.get("life_binding") as Object


func _person_view() -> Dictionary:
	var binding := _binding()
	if binding != null and binding.has_method("person_view"):
		var value: Variant = binding.call("person_view")
		if value is Dictionary:
			return value as Dictionary
	return {}


func _identity_view() -> Dictionary:
	if host != null and host.has_method("_identity_data"):
		var value: Variant = host.call("_identity_data")
		if value is Dictionary:
			return value as Dictionary
	return {}


func _profile_view() -> Dictionary:
	var output := _identity_view().duplicate(true)
	output.merge(_person_view(), true)
	return output


func _time_view() -> Dictionary:
	var binding := _binding()
	if binding != null and binding.has_method("time_view"):
		var value: Variant = binding.call("time_view")
		if value is Dictionary:
			return value as Dictionary
	return {}


func _sandbox_view() -> Dictionary:
	var binding := _binding()
	if binding != null and binding.has_method("sandbox_view"):
		var value: Variant = binding.call("sandbox_view")
		if value is Dictionary:
			return value as Dictionary
	return {}


func _today_schedule() -> Array:
	var binding := _binding()
	if binding != null and binding.has_method("today_schedule"):
		var value: Variant = binding.call("today_schedule")
		if value is Array:
			return value as Array
	return []


func _message_headlines() -> Array[String]:
	var binding := _binding()
	var output: Array[String] = []
	if binding != null and binding.has_method("messages_view"):
		var mailbox: Variant = binding.call("messages_view")
		if mailbox is Dictionary:
			for message_value: Variant in ((mailbox as Dictionary).get("inbox", []) as Array):
				if message_value is Dictionary:
					output.append(str((message_value as Dictionary).get("display_title", "消息")))
					if output.size() >= 3:
						break
	if output.is_empty():
		output.append("目前没有新的公开消息")
	return output


func _home_country_key() -> String:
	var person := _profile_view()
	return str(person.get("nationality_id", person.get("culture_id", "country_fra"))).to_lower()


func _country_colors(country_key: String) -> PackedColorArray:
	if "deu" in country_key or "german" in country_key:
		return PackedColorArray([Color("#191919"), Color("#d7d2c6"), Color("#8e343d")])
	if "gbr" in country_key or "brit" in country_key:
		return PackedColorArray([Color("#263d69"), Color("#d5d0c4"), Color("#8a333c")])
	if "rus" in country_key:
		return PackedColorArray([Color("#d9d5cb"), Color("#3d5983"), Color("#8e343d")])
	if "jpn" in country_key:
		return PackedColorArray([Color("#d9d5cb"), Color("#8e343d")])
	if "chn" in country_key or "qing" in country_key:
		return PackedColorArray([Color("#c3a247"), Color("#2f5277"), Color("#8b343c")])
	return PackedColorArray([Color("#264b78"), Color("#ddd8cb"), Color("#8f343d")])


func _role_category() -> String:
	var person := _profile_view()
	var source := (str(person.get("occupation", "")) + " " + str(person.get("role", "")) + " " + str(person.get("position", ""))).to_lower()
	if "农" in source or "farmer" in source or "peasant" in source:
		return "farmer"
	if "商" in source or "merchant" in source or "bank" in source:
		return "merchant"
	if "教师" in source or "学者" in source or "知识" in source or "writer" in source or "professor" in source:
		return "intellectual"
	if "行政" in source or "公务" in source or "官" in source or "minister" in source or "official" in source:
		return "official"
	if "国王" in source or "王后" in source or "贵族" in source or "公爵" in source or "king" in source or "noble" in source:
		return "royal"
	return "worker"


func _country_cover_rect() -> Rect2:
	return Rect2(12.0, 12.0, minf(300.0, size.x * 0.35), 82.0)


func _character_cover_rect() -> Rect2:
	return Rect2(12.0, size.y - 94.0, minf(300.0, size.x * 0.35), 82.0)


func _time_cover_rect() -> Rect2:
	return Rect2(size.x - minf(300.0, size.x * 0.35) - 12.0, 12.0, minf(300.0, size.x * 0.35), 82.0)


func _newspaper_rect() -> Rect2:
	return Rect2(size.x - minf(356.0, size.x * 0.42) - 12.0, size.y - 112.0, minf(356.0, size.x * 0.42), 100.0)


func _book_tab_rect() -> Rect2:
	return Rect2(-54.0, size.y * 0.5 - 86.0, 104.0, 172.0)


func _visible_book_tab_rect() -> Rect2:
	var rect := _book_tab_rect()
	rect.position.x += lerpf(0.0, 60.0, field_book_progress)
	return rect


func _book_open_rect() -> Rect2:
	var width := minf(820.0, size.x - 120.0)
	var height := minf(520.0, size.y - 116.0)
	return Rect2(Vector2((size.x - width) * 0.5, (size.y - height) * 0.5), Vector2(width, height))


func _book_close_rect() -> Rect2:
	var rect := _book_open_rect()
	return Rect2(rect.end - Vector2(78.0, 42.0), Vector2(64.0, 28.0))
