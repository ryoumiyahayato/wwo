extends Control
## Lightweight, self-contained HUD vehicle picker. Call setup(main) after main.hud
## exists. setup() attaches this Control to that CanvasLayer, then refresh() can be
## called by main.refresh_hud(). No shaders, blur passes, or infantry selection.

signal open_changed(is_open: bool)
signal vehicle_selected(index: int)

const ENTRY_SIZE := Vector2(52, 52)
const PANEL_SIZE := Vector2(300, 300)
const ACCENT := Color("d9c391")
const TEXT := Color("edf3ed")
const MUTED := Color("a8bdc4")

class TankGlyph extends Control:
	var light_tank := false
	var tint := Color("c8d8d8")
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(64, 44))
		var hull := PackedVector2Array([Vector2(5, 26), Vector2(13, 20), Vector2(48, 20), Vector2(57, 27), Vector2(53, 32), Vector2(9, 32)])
		if light_tank:
			hull = PackedVector2Array([Vector2(11, 27), Vector2(17, 22), Vector2(44, 22), Vector2(52, 27), Vector2(48, 32), Vector2(14, 32)])
		draw_style_box(_track_style(), Rect2(8 if not light_tank else 13, 29, 47 if not light_tank else 37, 10))
		for x in ([15, 24, 33, 42, 49] if not light_tank else [19, 28, 37, 45]):
			draw_circle(Vector2(x, 34), 2.6, Color(tint, 0.55))
		draw_colored_polygon(hull, Color(tint, 0.9))
		var turret := PackedVector2Array([Vector2(23, 20), Vector2(24, 12), Vector2(38, 12), Vector2(43, 20)])
		if light_tank:
			turret = PackedVector2Array([Vector2(25, 22), Vector2(25, 15), Vector2(36, 14), Vector2(41, 22)])
		draw_colored_polygon(turret, tint)
		draw_line(Vector2(37, 16 if not light_tank else 18), Vector2(61, 16 if not light_tank else 18), tint, 3.0, true)
		draw_line(Vector2(27, 11 if not light_tank else 14), Vector2(27, 5), Color(tint, 0.7), 1.0, true)
		draw_line(Vector2(15, 24), Vector2(45, 24), Color(1, 1, 1, 0.32), 1.0, true)
	func _track_style() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(tint, 0.12)
		style.border_color = Color(tint, 0.75)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		return style

var page_buttons:Array[Button]=[]
var catalog_page:=0
var catalog:Array=[]
var row_titles:Array[Label]=[]
var row_specs:Array[Label]=[]
var page_label:Label
var main: Node
var entry_button: Button
var panel: Panel
var close_button: Button
var row_buttons: Array[Button] = []
var row_markers: Array[Label] = []
var row_icons: Array[TankGlyph] = []
var is_open := false
var _built := false
var _font: Font
var _touches: Dictionary = {}
var _consume_mouse_release := false
var _suppress_emulated_mouse_until := 0
var _last_selected_unit := -100
var _last_handled_touch_position := Vector2.INF

func setup(host: Node) -> void:
	main = host
	var entries=main.get("catalog_vehicles")
	if entries is Array:catalog=entries
	_font = main.get("font") as Font
	var host_hud := main.get("hud") as CanvasLayer
	assert(host_hud != null, "Vehicle selector requires main.hud before setup().")
	if get_parent() == null:
		host_hud.add_child(self)
	elif get_parent() != host_hud:
		reparent(host_hud)
	name = "VehicleSelector"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	if not _built:
		_build()
		_built = true
		get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()

func _build() -> void:
	entry_button = Button.new()
	entry_button.name = "VehicleEntry"
	entry_button.size = ENTRY_SIZE
	entry_button.tooltip_text = "选择战车"
	entry_button.mouse_filter = Control.MOUSE_FILTER_STOP
	entry_button.toggle_mode = true
	entry_button.pressed.connect(func(): set_open(not is_open))
	add_child(entry_button)
	entry_button.add_theme_stylebox_override("normal", _glass(Color(0.07, 0.12, 0.15, 0.78), Color(0.65, 0.78, 0.8, 0.46), 10))
	entry_button.add_theme_stylebox_override("hover", _glass(Color(0.16, 0.23, 0.25, 0.88), Color(ACCENT, 0.8), 10))
	entry_button.add_theme_stylebox_override("pressed", _glass(Color(0.22, 0.27, 0.25, 0.9), ACCENT, 10))
	entry_button.add_theme_stylebox_override("focus", _focus_style())
	var entry_icon := TankGlyph.new()
	entry_icon.position = Vector2(8, 4)
	entry_icon.size = Vector2(36, 28)
	entry_icon.tint = ACCENT
	entry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_button.add_child(entry_icon)
	_label(entry_button, "载具", Vector2(0, 32), Vector2(52, 16), 11, TEXT, HORIZONTAL_ALIGNMENT_CENTER)

	panel = Panel.new()
	panel.name = "GlassTankPanel"
	panel.size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _glass(Color(0.055, 0.10, 0.13, 0.82), Color(0.72, 0.85, 0.86, 0.36), 14, true))
	add_child(panel)
	# Thin white reflections imply glass without a costly screen-texture blur.
	_line(panel, Vector2(18, 1), Vector2(264, 1), Color(0.89, 0.97, 1.0, 0.24))
	_line(panel, Vector2(18, 63), Vector2(264, 1), Color(0.8, 0.91, 0.94, 0.12))
	_label(panel, "选择战车", Vector2(18, 14), Vector2(220, 28), 20, TEXT)
	_label(panel, "VEHICLE BAY / %02d" % (catalog.size() if not catalog.is_empty() else 2), Vector2(19, 42), Vector2(220, 16), 10, MUTED)
	close_button = Button.new()
	close_button.name = "CloseVehiclePanel"
	close_button.position = Vector2(246, 8)
	close_button.size = Vector2(44, 44)
	close_button.text = "×"
	close_button.tooltip_text = "关闭载具选择"
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.add_theme_color_override("font_color", MUTED)
	close_button.add_theme_stylebox_override("normal", _glass(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 7))
	close_button.add_theme_stylebox_override("hover", _glass(Color(0.6, 0.8, 0.85, 0.10), Color(0.6, 0.8, 0.85, 0.18), 7))
	close_button.add_theme_stylebox_override("pressed", _glass(Color(0.6, 0.8, 0.85, 0.17), Color(0.6, 0.8, 0.85, 0.3), 7))
	close_button.add_theme_stylebox_override("focus", _focus_style())
	close_button.pressed.connect(func(): set_open(false))
	panel.add_child(close_button)
	_build_row(0, "堡垒 · 重型", "5 人乘员   AP 110 / 5 秒", 76)
	_build_row(1, "红隼 · 轻型", "3 人乘员   AP 90 / 3 秒", 164)
	page_label=_label(panel, "步兵由 AI 控制", Vector2(69, 260), Vector2(165, 22), 12, MUTED)
	if catalog.size()>2:
		for direction in [-1,1]:
			var nav:=Button.new();page_buttons.append(nav);panel.add_child(nav);nav.text="‹" if direction<0 else "›";nav.position=Vector2(16 if direction<0 else 246,254);nav.size=Vector2(38,36)
			nav.pressed.connect(_turn_page.bind(direction))
	panel.hide()

func _build_row(index: int, title: String, specs: String, top: float) -> void:
	var row := Button.new()
	row.name = "HeavyTank" if index == 0 else "LightTank"
	row.position = Vector2(14, top)
	row.size = Vector2(272, 80)
	row.tooltip_text = title + " · " + specs
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.pressed.connect(_choose.bind(index))
	row.add_theme_stylebox_override("hover", _glass(Color(0.29, 0.40, 0.42, 0.49), Color(ACCENT, 0.64), 10))
	row.add_theme_stylebox_override("pressed", _glass(Color(0.40, 0.43, 0.32, 0.62), ACCENT, 10))
	row.add_theme_stylebox_override("focus", _focus_style())
	panel.add_child(row)
	row_buttons.append(row)
	var icon := TankGlyph.new()
	icon.position = Vector2(8, 17)
	icon.size = Vector2(64, 44)
	icon.light_tank = index == 1
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	row_icons.append(icon)
	row_titles.append(_label(row, title, Vector2(81, 12), Vector2(182, 26), 15, TEXT))
	row_specs.append(_label(row, specs, Vector2(81, 42), Vector2(185, 22), 11, MUTED))
	var marker := _label(row, "●", Vector2(244, 7), Vector2(16, 16), 10, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	row_markers.append(marker)

func refresh() -> void:
	if not _built or not is_instance_valid(main):
		return
	var current := int(main.get("unit"))
	if not catalog.is_empty():
		current=-1
		for i in range(catalog.size()):
			if str(catalog[i].id)==str(main.get("selected_catalog_id")):current=i-catalog_page*2
		for i in range(2):
			var entry_index:=catalog_page*2+i
			row_buttons[i].visible=entry_index<catalog.size()
			if entry_index<catalog.size():
				var entry:Dictionary=catalog[entry_index]
				row_titles[i].text=str(entry.display_name)
				row_specs[i].text=("固定重型 / 5人 / AP110" if entry.fictional_stats=="heavy" else "固定轻型 / 3人 / AP90") if entry.fictional_stats!="car" else "装甲车 / 3人 / "+{"mg":"机枪","short_rocket":"短火箭","cannon":"加农炮"}.get(str(entry.get("weapon_class","cannon")),"加农炮")
				row_icons[i].light_tank=entry.fictional_stats=="light"
		page_label.text="%d / %d · AI步兵" % [catalog_page+1,int(ceil(catalog.size()/2.0))]
	# The host refreshes its HUD frequently; rebuild styles only on unit changes.
	if current != _last_selected_unit:
		_last_selected_unit = current
		for index in range(row_buttons.size()):
			var selected := index == current
			row_buttons[index].add_theme_stylebox_override("normal", _glass(Color(0.29, 0.34, 0.30, 0.53) if selected else Color(0.22, 0.32, 0.36, 0.24), Color(ACCENT, 0.76) if selected else Color(0.7, 0.84, 0.86, 0.16), 10))
			row_markers[index].visible = selected
			row_icons[index].tint = ACCENT if selected else Color("b5cdd3")
			row_icons[index].queue_redraw()
	entry_button.set_pressed_no_signal(is_open)
	entry_button.tooltip_text = "选择战车 · " + (["堡垒重型", "红隼轻型"][current] if current in [0, 1] else "战车")

func set_open(value: bool) -> void:
	if not _built:
		return
	var changed := is_open != value
	is_open = value
	panel.visible = value
	entry_button.set_pressed_no_signal(value)
	if value:
		refresh()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and (focused == self or is_ancestor_of(focused)):
			focused.release_focus()
	if changed:
		open_changed.emit(value)

func _turn_page(direction:int):
	catalog_page=posmod(catalog_page+direction,int(ceil(catalog.size()/2.0)));_last_selected_unit=-100;refresh()

func _choose(index: int) -> void:
	if index not in [0, 1] or not is_instance_valid(main):
		return
	# Close first: host.select_unit() may rebuild the scene and refresh its HUD.
	set_open(false)
	if catalog.is_empty():main.call("select_unit", index)
	elif catalog_page*2+index<catalog.size():main.call("select_catalog",str(catalog[catalog_page*2+index].id))
	refresh()
	vehicle_selected.emit(index)

func _layout() -> void:
	if not _built:
		return
	var viewport_size := get_viewport_rect().size
	entry_button.position = Vector2(16, clampf(270, 16, maxf(16, viewport_size.y - ENTRY_SIZE.y - 16)))
	panel.position = Vector2(80, clampf(242, 16, maxf(16, viewport_size.y - PANEL_SIZE.y - 16)))

func _input(event: InputEvent) -> void:
	if not _built or not is_visible_in_tree():
		return
	# Touch is handled directly so the picker also works without mouse emulation.
	# Absorb its emulated mouse companion to avoid toggling the panel twice.
	if event is InputEventMouse and event.device == -1 and (not _touches.is_empty() or (Time.get_ticks_msec() <= _suppress_emulated_mouse_until and event.position.distance_to(_last_handled_touch_position) < 24)):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
		return
	if event is InputEventScreenDrag and _touches.has(event.index):
		var touch: Dictionary = _touches[event.index]
		if event.position.distance_to(touch.origin) > 18:
			touch.moved = true
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed and _consume_mouse_release:
				_consume_mouse_release = false
				get_viewport().set_input_as_handled()
				return
			if is_open and event.pressed and not panel.get_global_rect().has_point(event.position) and not entry_button.get_global_rect().has_point(event.position):
				_consume_mouse_release = true
				set_open(false)
				get_viewport().set_input_as_handled()
	if is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var target := _touch_target(event.position)
		if target == -99:
			return
		_touches[event.index] = {"target": target, "origin": event.position, "moved": false}
		if target == -4:
			set_open(false)
	elif _touches.has(event.index):
		var touch: Dictionary = _touches[event.index]
		_touches.erase(event.index)
		if not event.canceled and not touch.moved and touch.target == _touch_target(event.position):
			if touch.target == -1:
				set_open(not is_open)
			elif touch.target == -2:
				set_open(false)
			elif touch.target in [-5,-6]:
				_turn_page(-1 if touch.target==-5 else 1)
			elif touch.target in [0, 1]:
				_choose(touch.target)
	else:
		return
	_last_handled_touch_position = event.position
	_suppress_emulated_mouse_until = Time.get_ticks_msec() + 120
	get_viewport().set_input_as_handled()

func _touch_target(point: Vector2) -> int:
	if entry_button.get_global_rect().has_point(point):
		return -1
	if not is_open:
		return -99
	if close_button.get_global_rect().has_point(point):
		return -2
	for index in range(page_buttons.size()):
		if page_buttons[index].get_global_rect().has_point(point):return -5-index
	for index in range(row_buttons.size()):
		if row_buttons[index].visible and row_buttons[index].get_global_rect().has_point(point):
			return index
	return -3 if panel.get_global_rect().has_point(point) else -4

func _glass(fill: Color, border: Color, radius: int, shadow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	if shadow:
		style.shadow_color = Color(0.01, 0.025, 0.035, 0.28)
		style.shadow_size = 9
		style.shadow_offset = Vector2(0, 5)
	return style

func _focus_style() -> StyleBoxFlat:
	var style := _glass(Color(0, 0, 0, 0), Color(ACCENT, 0.95), 9)
	style.set_border_width_all(2)
	return style

func _label(parent: Control, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if _font != null:
		label.add_theme_font_override("font", _font)
	parent.add_child(label)
	return label

func _line(parent: Control, at: Vector2, dimensions: Vector2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = at
	line.size = dimensions
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
