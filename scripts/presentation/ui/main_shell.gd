class_name MainShell
extends Control
## The one formal UI shell. Pages read detached records; commands go to composition.

signal action_requested(action: String)
signal refresh_requested
const PRIMARY_NAVIGATION: Array[Dictionary] = [
	{"id": "person", "label": "人物 / 当前处境"},
	{"id": "economy", "label": "经济 / 市场"},
	{"id": "organization", "label": "组织"},
	{"id": "map", "label": "世界"},
]
var current_page: String = "person"
var status_message: String = ""
var _system_open: bool = false
var _map_modes_open: bool = false
var _map_display_open: bool = false
var _hits: Array[Dictionary] = []
var _font := UIDrawing.create_font()
var _date: Dictionary = {}
var _content_errors: Array[String] = []
var _controller: GlobeController
var _time: TimeControl
var person_page := PersonView.new()
var economy_page := EconomyPage.new()
var organization_page := OrganizationPage.new()
var world_page := WorldPage.new()

func configure(content_errors: Array[String], controller: GlobeController, time: TimeControl) -> void:
	_content_errors = content_errors.duplicate()
	_controller = controller
	_time = time

func set_date(value: Dictionary) -> void:
	_date = value.duplicate(true)

func refresh() -> void:
	refresh_requested.emit()
	queue_redraw()

func set_page(page: String) -> void:
	_map_modes_open = false
	_map_display_open = false
	if page in ["person", "economy", "organization", "map", "politics", "military", "administration"]:
		current_page = page
		action_requested.emit("page_changed")
		refresh()

func _draw() -> void:
	_hits.clear()
	if _controller == null:
		return
	if current_page != "map":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.020, 0.024, 1.0))
		var rect := Rect2(24.0, 106.0, size.x - 48.0, size.y - 166.0)
		panel(rect, Color(0.016, 0.037, 0.042, 0.99), Color(0.70, 0.61, 0.36, 0.32))
		match current_page:
			"person": person_page.draw(self, rect)
			"economy": economy_page.draw(self, rect)
			"organization": organization_page.draw(self, rect)
			"politics": world_page.draw_politics(self, rect)
			"administration": world_page.draw_administration(self, rect)
			"military": heading(rect, "军事", "")
	else:
		_draw_map_controls()
		world_page.draw_card(self, Rect2(size.x - 318.0, 150.0, 294.0, 288.0))
	_draw_navigation()
	_draw_time_bar()
	if current_page == "map":
		_draw_map_menus()
	if _system_open:
		_draw_system_menu()
	if not _content_errors.is_empty():
		label(Vector2(28.0, size.y - 66.0), "数据错误：" + "; ".join(_content_errors), 11, Color(0.96, 0.58, 0.35), size.x - 56.0)

func _draw_navigation() -> void:
	panel(Rect2(0.0, 0.0, size.x, 88.0), Color(0.010, 0.025, 0.030, 0.985), Color(0.72, 0.62, 0.36, 0.38))
	label(Vector2(20.0, 25.0), "1900", 19, Color(0.96, 0.86, 0.61))
	label(Vector2(20.0, 46.0), "PLAYER SITUATION", 8, Color(0.60, 0.72, 0.68))
	var x: float = 154.0
	for item: Dictionary in PRIMARY_NAVIGATION:
		var page := str(item.id)
		var width: float = 154.0 if page in ["person", "economy"] else 112.0
		var rect := Rect2(x, 14.0, width, 34.0)
		button(rect, str(item.label), "page:" + page)
		if current_page == page or page == "map" and current_page in ["politics", "military", "administration"]:
			draw_rect(rect, Color(0.88, 0.72, 0.38, 0.72), false, 1.0)
		x += width + 8.0

func _draw_map_controls() -> void:
	var x: float = 24.0
	for item: Dictionary in [{"id": "map", "label": "地图"}, {"id": "politics", "label": "政治观察"}]:
		button(Rect2(x, 106.0, 104.0, 30.0), str(item.label), "page:" + str(item.id))
		x += 112.0
	var mode_names: Dictionary = {"political":"Political","fulfillment":"Economy / Fulfillment","shortage":"Economy / Shortage"}
	button(Rect2(x,106.0,190.0,30.0),str(mode_names[_controller.map_mode])+" ▾","map:mode_menu")
	button(Rect2(x+198.0,106.0,140.0,30.0),"显示选项 / 图例 ▾","map:display_menu")

func _draw_map_menus() -> void:
	if _map_modes_open:
		var rect := Rect2(248,142,264,178)
		panel(rect,Color(0.017,0.036,0.039,0.99),Color(0.70,0.61,0.36,0.7))
		_hits.append({"rect":rect,"action":"noop","enabled":true})
		button(Rect2(260,154,240,30),"Political","map_mode:political")
		label(Vector2(272,205),"Economy 地图图层",11)
		button(Rect2(260,212,240,30),"  Fulfillment","map_mode:fulfillment")
		button(Rect2(260,250,240,30),"  Shortage","map_mode:shortage")
		label(Vector2(272,303),"Military：正式图层尚未接入",10,Color(0.55,0.61,0.58))
	if _map_display_open:
		var rect := Rect2(446,142,350,250)
		panel(rect,Color(0.017,0.036,0.039,0.99),Color(0.70,0.61,0.36,0.7))
		_hits.append({"rect":rect,"action":"noop","enabled":true})
		button(Rect2(458,154,326,30),("☑ " if _controller.labels_enabled else "☐ ")+"地名 / 国家名称","map:labels")
		button(Rect2(458,192,326,30),("☑ " if _controller.strategic_rails_enabled else "☐ ")+"战略铁路连接（线位近似）","map:rails")
		label(Vector2(462,247),"虚线：有历史依据的近似战略连接",11)
		label(Vector2(462,270),"双轨：Paris Local 参考线，非运力网络",11)
		label(Vector2(462,293),"方块 / 圆环 / 小点：历史展示等级",11)
		label(Vector2(462,316),"等级不等于首都、港口或行政身份",10,Color(0.70,0.79,0.73))
		label(Vector2(462,339),"河湖岸线：现代物理参考，不复原水位",10,Color(0.70,0.79,0.73))
		label(Vector2(462,373),"滚轮缩放 · 左键平移 · 右键旋转",10,Color(0.70,0.79,0.73))

func _draw_time_bar() -> void:
	var rect := Rect2(0.0, size.y - 52.0, size.x, 52.0)
	panel(rect, Color(0.010, 0.025, 0.030, 0.99), Color(0.72, 0.62, 0.36, 0.28))
	var control_x := size.x - 486.0
	label(Vector2(control_x, 31.0), date_text(), 14, Color(0.95, 0.86, 0.61))
	button(Rect2(control_x, 46.0, 74.0, 28.0), "继续" if _time.paused else "暂停", "time:pause")
	for index: int in range(3):
		var speed: int = [1, 2, 4][index]
		button(Rect2(control_x + 84.0 + index * 62.0, 46.0, 54.0, 28.0), str(speed) + "×", "time:" + str(speed))
	button(Rect2(size.x - 102.0, 14.0, 82.0, 34.0), "系统", "system")
	label(Vector2(size.x - 480.0, rect.position.y + 31.0), status_message, 10, Color(0.70, 0.79, 0.73), 456.0)

func _draw_system_menu() -> void:
	var rect := Rect2(size.x - 246.0, 92.0, 222.0, 152.0)
	panel(rect, Color(0.017, 0.036, 0.039, 0.99), Color(0.78, 0.67, 0.42))
	_hits.append({"rect": rect, "action": "noop", "enabled": true})
	button(Rect2(rect.position + Vector2(16.0, 16.0), Vector2(190.0, 30.0)), "保存 F5", "save")
	button(Rect2(rect.position + Vector2(16.0, 58.0), Vector2(190.0, 30.0)), "读取 F9", "load")
	button(Rect2(rect.position + Vector2(16.0, 100.0), Vector2(190.0, 30.0)), "关闭", "system")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			for index: int in range(_hits.size() - 1, -1, -1):
				var hit := _hits[index]
				if (hit.rect as Rect2).has_point(mouse.position):
					if bool(hit.enabled):
						_activate(str(hit.action))
					get_viewport().set_input_as_handled()
					return
			if _map_modes_open or _map_display_open:
				_map_modes_open = false
				_map_display_open = false
				queue_redraw()
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_ESCAPE:
				if _map_modes_open or _map_display_open:
					_map_modes_open = false
					_map_display_open = false
				elif _system_open:
					_system_open = false
				elif current_page == "administration":
					set_page("map")
				else:
					_system_open = true
			KEY_F5: action_requested.emit("save")
			KEY_F9: action_requested.emit("load")
			KEY_SPACE: action_requested.emit("time:pause")
			_: return
		queue_redraw()
		get_viewport().set_input_as_handled()

func _activate(action: String) -> void:
	if action == "map:mode_menu":
		_map_modes_open = not _map_modes_open
		_map_display_open = false
	elif action == "map:display_menu":
		_map_display_open = not _map_display_open
		_map_modes_open = false
	elif action == "map:rails":
		_controller.toggle_strategic_rails()
	elif action.begins_with("map_mode:"):
		_map_modes_open = false
		action_requested.emit(action)
	elif action.begins_with("page:"):
		set_page(action.trim_prefix("page:"))
	elif action == "system":
		_system_open = not _system_open
	elif action == "organization:previous":
		organization_page.page = maxi(0, organization_page.page - 1)
	elif action == "organization:next":
		organization_page.page += 1
	elif action == "admin:previous":
		world_page.admin_page = maxi(0, world_page.admin_page - 1)
	elif action == "admin:next":
		world_page.admin_page += 1
	elif action != "noop":
		action_requested.emit(action)
	queue_redraw()

func blocks_map(point: Vector2) -> bool:
	if current_page != "map":
		return true
	for hit: Dictionary in _hits:
		if (hit.rect as Rect2).has_point(point):
			return true
	return not _controller.selected_polity_id.is_empty() and Rect2(size.x - 318.0, 150.0, 294.0, 288.0).has_point(point)

func date_text() -> String:
	var value := _date
	return "%04d年%02d月%02d日 %02d:%02d" % [int(value.get("year", 0)), int(value.get("month", 0)), int(value.get("day", 0)), int(value.get("hour", 0)), int(value.get("minute", 0))]

func panel(rect: Rect2, fill: Color, border: Color) -> void:
	UIDrawing.panel(self, rect, fill, border)

func label(point: Vector2, text: String, font_size: int = 12, color: Color = Color(0.90, 0.91, 0.84, 1.0), width: float = -1.0) -> void:
	UIDrawing.label(self, _font, point, text, font_size, color, width)

func button(rect: Rect2, text: String, action: String, enabled: bool = true) -> void:
	_hits.append({"rect": rect, "action": action, "enabled": enabled})
	panel(rect, Color(0.035, 0.06, 0.062, 0.94), Color(0.52, 0.54, 0.39, 0.28))
	label(rect.position + Vector2(12.0, 21.0), text, 11, Color(0.90, 0.91, 0.84) if enabled else Color(0.42, 0.48, 0.44))

func heading(rect: Rect2, title: String, subtitle: String) -> void:
	label(rect.position + Vector2(28.0, 42.0), title, 23, Color(0.96, 0.88, 0.67))
	label(rect.position + Vector2(28.0, 68.0), subtitle, 10, Color(0.67, 0.77, 0.73), rect.size.x - 56.0)
	draw_line(rect.position + Vector2(28.0, 84.0), Vector2(rect.end.x - 28.0, rect.position.y + 84.0), Color(0.64, 0.56, 0.33, 0.26), 1.0)

func card(rect: Rect2, title: String) -> void:
	panel(rect, Color(0.023, 0.046, 0.049, 0.95), Color(0.70, 0.61, 0.36, 0.38))
	label(rect.position + Vector2(18.0, 31.0), title, 13, Color(0.91, 0.82, 0.57), rect.size.x - 36.0)

func lines(point: Vector2, values: Array[String], width: float) -> void:
	var y := point.y
	for text: String in values:
		label(Vector2(point.x, y), text, 12, Color(0.82, 0.86, 0.79), width)
		y += 26.0
