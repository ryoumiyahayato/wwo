extends "res://military_runtime/native/scripts/mobile_battle.gd"
## Embedded presentation only. All driving, aiming, crew and fire dispatch stay native.

func setup(host: Node3D) -> void:
	main = host
	name = "BattleControls"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	process_priority = 100
	process_mode = Node.PROCESS_MODE_INHERIT
	main.hud.add_child(self)
	_make_menu()
	# Do not install native diagnostics, performance collectors or preference writers.
	minimap = preload("res://military_runtime/native/scripts/battle_minimap.gd").new()
	minimap.setup(self)
	vehicle_hud = preload("res://military_runtime/native/scripts/bottom_vehicle_hud.gd").new()
	vehicle_hud.setup(self)

func _input(event: InputEvent) -> void:
	if active():
		main.request_training_frame()
	super._input(event)

func active() -> bool:
	return super.active() and bool(main.get("session_ready"))

func _draw() -> void:
	if not active(): return
	if not bool(main.get("battle_finished")):
		super._draw()
		return
	var center := size*0.5
	var caption := Rect2(center-Vector2(160,40),Vector2(320,36))
	var button := Rect2(center-Vector2(160,0),Vector2(320,60))
	var ink := Color("eee5cf")
	var panel := Color("142532")
	draw_rect(caption,panel)
	draw_rect(button,panel)
	draw_rect(button,Color("a98953"),false,1.0)
	draw_string(main.font,caption.position+Vector2(12,24),"训练结束 · "+str(main.get("battle_result")),HORIZONTAL_ALIGNMENT_CENTER,296,16,ink)
	draw_string(main.font,button.position+Vector2(12,38),"返回地图",HORIZONTAL_ALIGNMENT_CENTER,296,20,ink)

func _make_menu() -> void:
	menu = PanelContainer.new()
	add_child(menu)
	menu.hide()
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.06, 0.075, 0.96)
	background.set_corner_radius_all(12)
	background.content_margin_left = 18
	background.content_margin_right = 18
	background.content_margin_top = 14
	background.content_margin_bottom = 14
	menu.add_theme_stylebox_override("panel", background)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	menu.add_child(column)
	_add_menu_button(column, "原车组上下车", _toggle_crew_panel)
	_add_menu_button(column, "返回观察（保留本次训练）", _request_observer)
	sight_button = _add_menu_button(column, "", _cycle_sight)
	_update_sight_label()
	mode_button = _add_menu_button(column, "", _cycle_control_mode)
	_update_mode_label()

func _add_menu_button(parent: VBoxContainer, caption: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(250, 45)
	button.add_theme_font_override("font", main.font)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _toggle_crew_panel() -> void:
	main.crew_host.expanded = not main.crew_host.expanded

func _request_observer() -> void:
	set_menu(false)
	main.switch_mode()

func _cycle_sight() -> void:
	main.tank_sight.cycle(main)
	_update_sight_label()

func _cycle_control_mode() -> void:
	set_control_mode("buttons" if control_mode == "joystick" else "joystick", false)

func set_control_mode(value: String, _persist: bool = true) -> void:
	super.set_control_mode(value, false)

func set_menu(value: bool) -> void:
	menu_open = value
	menu.visible = value
	reset_pointers()
	# A local menu must never unpause the formal SceneTree.
	if is_instance_valid(main.crew_host):
		main.crew_host.panel.process_mode = Node.PROCESS_MODE_INHERIT
		if not value:
			main.crew_host.expanded = false
			main.crew_host.panel.hide()
