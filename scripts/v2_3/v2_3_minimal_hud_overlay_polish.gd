extends "res://scripts/v2_3/v2_3_minimal_hud_overlay.gd"
## Final visual cover: compact symbolic corners and a legible field-book spine.


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and _system_cover_rect().has_point(button.position):
			_host_activate("toggle_system_menu", null)
			get_viewport().set_input_as_handled()
			return
	super._input(event)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.016, 0.030, 0.034, 1.0), true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)


func _draw_character_sigil() -> void:
	super._draw_character_sigil()
	var cover := _character_cover_rect()
	var badge := Rect2(cover.end.x, cover.end.y - 41.0, 54.0, 29.0)
	draw_rect(badge, Color(0.016, 0.030, 0.034, 1.0), true)
	draw_rect(badge, Color(0.72, 0.64, 0.38, 0.30), false, 1.0)
	_draw_text(badge.position + Vector2(10.0, 19.0), _role_label(), 11, Color(0.86, 0.82, 0.66, 1.0))


func _draw_clock_corner() -> void:
	super._draw_clock_corner()
	var system_rect := _system_cover_rect()
	draw_rect(system_rect, Color(0.04, 0.055, 0.052, 1.0), true)
	draw_rect(system_rect, Color(0.72, 0.64, 0.38, 0.42), false, 1.0)
	_draw_text(system_rect.position + Vector2(8.0, 20.0), "⚙", 13, Color(0.88, 0.84, 0.70, 1.0))


func _draw_newspaper_corner() -> void:
	var rect := _newspaper_rect()
	draw_rect(rect, Color(0.74, 0.73, 0.66, 1.0), true)
	draw_rect(rect, Color(0.25, 0.28, 0.25, 0.82), false, 1.0)
	draw_line(rect.position + Vector2(12.0, 26.0), rect.position + Vector2(rect.size.x - 12.0, 26.0), Color(0.24, 0.27, 0.24, 0.72), 2.0)
	draw_line(rect.position + Vector2(12.0, 30.0), rect.position + Vector2(rect.size.x - 12.0, 30.0), Color(0.24, 0.27, 0.24, 0.42), 1.0)
	_draw_text(rect.position + Vector2(13.0, 20.0), "已知信息", 13, INK)
	var messages := _message_headlines()
	for index: int in range(mini(3, messages.size())):
		_draw_text(rect.position + Vector2(15.0, 49.0 + float(index) * 18.0), "— " + str(messages[index]), 10, INK_MUTED)


func _draw_field_book() -> void:
	super._draw_field_book()
	if field_book_progress > 0.08:
		return
	var tab := _visible_book_tab_rect()
	var visible_x := maxf(5.0, tab.position.x + tab.size.x - 39.0)
	var top := tab.position.y + 17.0
	draw_line(Vector2(visible_x, top), Vector2(visible_x, tab.end.y - 17.0), Color(0.86, 0.73, 0.43, 0.62), 1.0)
	for offset: float in [0.0, 7.0, 14.0]:
		draw_line(Vector2(visible_x + 8.0, tab.end.y - 27.0 - offset), Vector2(tab.end.x - 8.0, tab.end.y - 27.0 - offset), Color(0.78, 0.68, 0.47, 0.44), 1.0)
	_draw_text(Vector2(visible_x + 8.0, top + 28.0), "事", 14, Color(0.91, 0.84, 0.67, 1.0))
	_draw_text(Vector2(visible_x + 8.0, top + 51.0), "务", 14, Color(0.91, 0.84, 0.67, 1.0))
	_draw_text(Vector2(visible_x + 8.0, top + 74.0), "簿", 14, Color(0.91, 0.84, 0.67, 1.0))


func _visible_book_tab_rect() -> Rect2:
	var rect := super._visible_book_tab_rect()
	rect.position.x -= field_book_progress * 112.0
	return rect


func _role_label() -> String:
	return {
		"farmer": "农民",
		"merchant": "商人",
		"intellectual": "学者",
		"official": "主官",
		"royal": "贵族",
	}.get(_role_category(), "工人")


func _country_cover_rect() -> Rect2:
	return Rect2(12.0, 12.0, 96.0, 82.0)


func _character_cover_rect() -> Rect2:
	return Rect2(12.0, size.y - 112.0, 96.0, 100.0)


func _time_cover_rect() -> Rect2:
	return Rect2(size.x - 248.0, 12.0, 236.0, 82.0)


func _system_cover_rect() -> Rect2:
	var time_rect := _time_cover_rect()
	return Rect2(time_rect.end.x - 39.0, time_rect.position.y + 7.0, 31.0, 28.0)


func _book_tab_rect() -> Rect2:
	return Rect2(-24.0, size.y * 0.5 - 74.0, 68.0, 148.0)
