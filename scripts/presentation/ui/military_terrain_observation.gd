extends Control
## A presentation excursion in the original FormalWorldApplication, never a world owner.
signal closed
signal map_requested(message: String)
const REGION_PATH := "res://data/map_regions/ridgevale_training.json"
var context: Dictionary = {}
var initial_training_profile: String = ""
var _direct_training: bool = false
var _direct_training_requested: bool = false
var _terrain_ready: bool = false
var region_config: Dictionary = {}
var viewport: SubViewport
var camera: Camera3D
var _environment: Environment
var _sun: DirectionalLight3D
var terrain: Node3D
var scenery: Node3D
var _cartography: Dictionary = {}
var center := Vector2(2500,2500)
var span_m := 50000.0
var bearing := 0.0
var elevation := 60.0
var selected_cell := Vector2i(4,4)
var _previous_region_center := Vector2.ZERO
var _previous_region_span := 50000.0
var _previous_region_bearing := 0.0
var _previous_region_elevation := 60.0
var _drag := false
var _orbit := false
var _press := Vector2.ZERO
var _last := Vector2.ZERO
var _title: Label
var _status: Label
var _hint: Label
var _detail: Button
var _texture: TextureRect
var _grid: Control
var _dirty := true
var _camera_ready := false
var _held: Dictionary = {}
var _walker: CharacterBody3D
var _walking := false
var _walk_preparing := false
var _walk_generation := 0
var _walk_button: Button
var _last_center := Vector2(INF,INF)
var _last_span := -1.0
const TRAINING_SCRIPT: String = "res://military_runtime/native/modules/isolated_training/controller.gd"
var _training: Node
var _training_active: bool = false
var _training_preparing: bool = false
var _training_button: Button
var _battlefield_button: Button
var _training_profile: String = "single_opponent"
var _training_exit: Button
var _training_banner: Label
var _toolbar: Control
var _training_tick: float = 0.0

func _install_training_controls() -> void:
	_toolbar = _title.get_parent().get_parent().get_parent().get_parent() as Control
	_training_button = _button(_walk_button.get_parent(), "原生坦克训练（隔离）", _toggle_training)
	_training_button.get_parent().move_child(_training_button, _walk_button.get_index() + 1)
	_training_button.disabled = true
	_battlefield_button = _button(_walk_button.get_parent(), "20车 / 150步兵战场（隔离）", _toggle_battlefield)
	_battlefield_button.tooltip_text = "20车与150名独立步兵，62名车组另计。满规模持续接战与30FPS仍在验证，尚未达标。暂停/重入保留伤损与有限弹药，不写正式世界。"
	_battlefield_button.get_parent().move_child(_battlefield_button, _training_button.get_index() + 1)
	_battlefield_button.disabled = true
	_training_exit = Button.new()
	_training_exit.text = "暂停并返回地图 / Esc" if _direct_training else "隔离训练 · 暂停并观察 / Esc"
	_training_exit.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# Keep the original native menu centred at viewport_width - 42 accessible.
	_training_exit.offset_left = -360
	_training_exit.offset_right = -106
	_training_exit.offset_top = 8
	_training_exit.offset_bottom = 50
	_training_exit.focus_mode = Control.FOCUS_NONE
	_training_exit.pressed.connect(_pause_training)
	_training_exit.hide()
	add_child(_training_exit)
	_training_banner = Label.new()
	_training_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_training_banner.offset_left = 240
	_training_banner.offset_right = -390
	_training_banner.offset_top = 6
	_training_banner.offset_bottom = 60
	_training_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_training_banner.add_theme_font_size_override("font_size", 16)
	_training_banner.add_theme_color_override("font_color", Color(0.98, 0.96, 0.88))
	_training_banner.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_training_banner.add_theme_constant_override("outline_size", 3)
	_training_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	_training_banner.add_theme_constant_override("shadow_outline_size", 3)
	_training_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_training_banner.hide()
	add_child(_training_banner)

func _toggle_battlefield() -> void:
	_toggle_training("field_170")

func _toggle_training(profile: String = "") -> void:
	if is_instance_valid(_training) and not profile.is_empty() and profile != _training_profile:
		_status.text = "本次会话保留原车组与伤弹。返回正式世界明确结束后，再选择另一训练场景。"
		return
	if _training_active:
		_pause_training()
		return
	if is_instance_valid(_training):
		_set_training_view(true)
		_training.call("resume")
		_training_button.text = "恢复原训练（弹药 / 伤损保留）"
		_request_frame()
		return
	var script: GDScript = load(TRAINING_SCRIPT) as GDScript
	if script == null or not script.can_instantiate():
		_status.text = "原军事训练模块未就绪；观察与正式世界仍可正常使用。"
		if _direct_training: map_requested.emit("原军事训练模块未就绪")
		return
	_stop_walk()
	_training_profile = "single_opponent" if profile.is_empty() else profile
	_training_preparing = true
	_set_training_view(true)
	_training_banner.text = "准备20辆可战车辆 / 150独立步兵；62车组另计\n原规则分批部署，地面就绪后共同激活" if _training_profile == "field_170" else "准备原生坦克与五车组 · 独立训练身份 · 不写正式世界"
	_training = script.new() as Node
	_training.connect("prepared", _on_training_prepared)
	_training.connect("failed", _on_training_failed)
	_training.connect("observer_requested", _pause_training)
	add_child(_training)
	_training.call("set_input_exclusions", _host_input_exclusions())
	_training.call("start", {"viewport": viewport, "provider": terrain, "profile": _training_profile})

func _set_training_view(active: bool) -> void:
	_training_active = active
	if active: _stop_walk()
	_held.clear()
	_drag = false
	_orbit = false
	_toolbar.visible = not active and not _direct_training
	_hint.get_parent().visible = not active and not _direct_training
	_grid.visible = not active and not _direct_training
	_training_exit.visible = active
	_training_banner.visible = active
	if is_instance_valid(scenery):
		# Drop observer-only support before the original military owner is installed.
		if active: scenery.call("update_view", center, 5000.0)
		scenery.visible = not active and not _direct_training
	_environment.background_mode = Environment.BG_SKY if active else Environment.BG_COLOR
	_sun.shadow_enabled = active
	if not active:
		camera.make_current()
		_last_span = -1.0
		_request_frame()

func _on_training_prepared(_status_data: Dictionary) -> void:
	_training_preparing = false
	_training_button.text = "恢复原训练（弹药 / 伤损保留）"
	_training_banner.text = "隔离训练 · 原车组 / 有限弹药 / 实弹弹着 · Esc返回地图" if _direct_training else "隔离训练 · 原车组 / 有限弹药 / 实弹弹着 · Esc暂停观察"
	_request_frame()

func _on_training_failed(reason: String) -> void:
	_training_preparing = false
	if is_instance_valid(_training):
		_training.call("close")
		_training.queue_free()
	_training = null
	_set_training_view(false)
	_status.text = "训练未启动：" + reason + "；未修改正式人物、时间或存档。"
	if _direct_training: map_requested.emit("训练未启动："+reason)

func _pause_training(return_to_map: bool = true) -> void:
	_direct_training_requested=false
	if not _training_active:
		if _direct_training and return_to_map: map_requested.emit("")
		return
	if is_instance_valid(_training):
		if _training_preparing:
			_training.call("close")
			_training.queue_free()
			_training = null
		else:
			_training.call("pause")
	_training_preparing = false
	_set_training_view(false)
	_status.text = "观察模式 · 本次训练已暂停，原车组 / 弹药 / 伤损保留；返回正式世界会结束本次隔离训练。"
	if _direct_training and return_to_map: map_requested.emit("")

func resume_training() -> void:
	_direct_training_requested=true
	if _terrain_ready: _toggle_training(initial_training_profile)

func get_training_status() -> Dictionary:
	if not is_instance_valid(_training): return {"state": "not_started", "isolated": true}
	var status_data: Dictionary = _training.call("get_status") as Dictionary
	return status_data

func _process(delta: float) -> void:
	if _training_active:
		_training_tick += delta
		if _training_tick >= 0.5 and not _training_preparing:
			_training_tick = 0.0
			var status_data: Dictionary = _training.call("get_player_status") as Dictionary if _training.has_method("get_player_status") else get_training_status()
			var driving: Dictionary = status_data.get("driving", {}) as Dictionary
			var motion_text: String = "车长离车" if bool(status_data.get("on_foot", false)) else "车内 · %.1f m/s" % float(driving.get("speed_mps", 0.0))
			var ammo: Dictionary = status_data.get("ammo", {}) as Dictionary
			var round_name: String = str(ammo.get("loaded", ""))
			if round_name.is_empty(): round_name = str(ammo.get("loading", ""))
			if round_name.is_empty(): round_name = str(ammo.get("next", ""))
			var chamber_text: String = "弹仓空"
			if not str(ammo.get("loaded", "")).is_empty(): chamber_text = "已装弹"
			elif not str(ammo.get("loading", "")).is_empty(): chamber_text = "装填 %.1fs" % float(ammo.get("remaining", 0.0))
			var scenario_label: String = "部署20车 / 150步兵" if _training_profile == "field_170" else "隔离装甲交战"
			_training_banner.text = "%s · %s\n%s · %s · 总余弹%d · Esc暂停" % [scenario_label, motion_text, round_name.to_upper(), chamber_text, int(ammo.get("total", 0))]
		return
	if not _direct_training: _process_observation(delta)

func _gui_input(event: InputEvent) -> void:
	if not _training_active and not _direct_training: _observation_gui_input(event)

func _input(event: InputEvent) -> void:
	if not _training_active:
		if _direct_training:
			if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
				_pause_training()
				get_viewport().set_input_as_handled()
			return
		_observation_input(event)
		return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_pause_training()
			get_viewport().set_input_as_handled()
			return
		if key.pressed and not key.echo and key.keycode == KEY_F12:
			var dock := get_tree().root.get_node_or_null("DebugWorkspaces")
			if dock!=null: dock.call("_screenshot")
			else: _capture()
			get_viewport().set_input_as_handled()
			return
	var pointer_position: Vector2 = Vector2.INF
	var pointer_released: bool = false
	if event is InputEventMouse:
		pointer_position = (event as InputEventMouse).position
		pointer_released = event is InputEventMouseButton and not (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pointer_position = (event as InputEventScreenTouch).position
		pointer_released = not (event as InputEventScreenTouch).pressed or (event as InputEventScreenTouch).canceled
	elif event is InputEventScreenDrag:
		pointer_position = (event as InputEventScreenDrag).position
	var host_control := false
	for rect: Rect2 in _host_input_exclusions():
		if rect.has_point(pointer_position): host_control=true;break
	if host_control:
		# Always release the native fire/look pointer, even over the host button.
		# Leave this event unhandled here so the actual pause button also receives it.
		if pointer_released and not _training_preparing:
			viewport.push_input(event, true)
			if is_instance_valid(_training): _training.call("request_frame")
		return
	if not _training_preparing:
		viewport.push_input(event, true)
		if is_instance_valid(_training) and _training.has_method("request_frame"): _training.call("request_frame")
	get_viewport().set_input_as_handled()

func _host_input_exclusions() -> Array[Rect2]:
	var rectangles: Array[Rect2]=[_training_exit.get_rect()]
	var dock := get_tree().root.get_node_or_null("DebugWorkspaces")
	if dock!=null and dock.has_method("input_rect"): rectangles.append(dock.call("input_rect") as Rect2)
	return rectangles

func _ready() -> void:
	name = "MilitaryTerrainObservation"
	_direct_training=not initial_training_profile.is_empty()
	_direct_training_requested=_direct_training
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIDrawing.shell_theme()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGION_PATH))
	if not parsed is Dictionary:
		closed.emit()
		return
	region_config = parsed as Dictionary
	_texture = TextureRect.new()
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	_texture.texture = viewport.get_texture()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	_environment=env
	env.background_color=Color("1c282b")
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("537fa6")
	sky_material.sky_horizon_color = Color("c7d4d6")
	sky_material.ground_horizon_color = Color("b9c3ba")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d5df")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
	environment.environment = env
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	_sun=sun
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=180
	sun.rotation_degrees = Vector3(-43,-35,0)
	sun.light_color = Color("fff1d5")
	sun.light_energy = 1.35
	sun.shadow_enabled = false
	viewport.add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 100000.0
	viewport.add_child(camera)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.draw.connect(_draw_grid)
	add_child(_grid)
	_build_toolbar()
	_install_training_controls()
	if _direct_training:
		_toolbar.hide()
		_grid.hide()
		_hint.get_parent().hide()
		_training_banner.text="正在准备坦克训练 · Esc返回地图"
		_training_banner.show()
	resized.connect(_resize)
	_resize()
	var script := load("res://scripts/presentation/terrain/layered_terrain.gd") as GDScript
	if script == null:
		_status.text = "地形组件尚未安装。返回后可继续原正式世界。"
		if _direct_training: map_requested.emit(_status.text)
		return
	terrain = script.new() as Node3D
	viewport.add_child(terrain)
	terrain.connect("changed",_request_frame)
	terrain.connect("prepared",_on_prepared)
	terrain.connect("failed",func(message: String) -> void:
		_status.text = "资源不可用："+message
		if _direct_training: map_requested.emit(_status.text)
		_request_frame()
	)
	terrain.call("begin",region_config)
	_request_frame()

func _build_toolbar() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 111
	add_child(top)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",16)
	margin.add_theme_constant_override("margin_right",16)
	margin.add_theme_constant_override("margin_top",8)
	margin.add_theme_constant_override("margin_bottom",8)
	top.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_title = Label.new()
	_title.text = "隔离训练观察 · Ridgevale"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)
	_button(row,"返回正式世界",_close)
	var controls := HBoxContainer.new()
	column.add_child(controls)
	_button(controls,"50 km",func() -> void: _set_range(50000))
	_button(controls,"25 km",func() -> void: _set_range(25000))
	_detail = _button(controls,"进入选中 5 km",_enter_selected)
	_detail.disabled = true
	_button(controls,"定位原生区块",func() -> void: selected_cell=Vector2i(4,4);center=Vector2.ZERO;_request_frame())
	_button(controls,"村庄 / 道路",func() -> void: _enter_native();center=Vector2(0,40);span_m=492.1875;elevation=30;_request_frame())
	_walk_button = _button(controls,"步行观察（隔离）",_toggle_walk)
	_walk_button.disabled = true
	_button(controls,"上一级 / Esc",_back)
	_status = Label.new()
	_status.text = "正在按需准备地形；广域图不建立建筑或碰撞。"
	_status.add_theme_font_size_override("font_size",13)
	column.add_child(_status)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -66
	add_child(bottom)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size",13)
	_hint.text = "  虚构训练地区 · 非历史地理配准 · 未绑定正式军事实体\n  左键选格 / 拖动平移 · 滚轮缩放 · 右拖旋转 · WASD移动观察 · F12截图；地图操作不移动正式人物。"
	bottom.add_child(_hint)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void:
		if _training_active and callback != Callable(self, "_toggle_training"):
			_pause_training()
		callback.call()
	)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _resize() -> void:
	if viewport == null: return
	# One native-size target, no second simultaneous view or supersampling.
	viewport.size = Vector2i(size).max(Vector2i(1,1))
	_request_frame()

func _on_prepared() -> void:
	_terrain_ready=true
	if _direct_training:
		if _direct_training_requested:
			var profile := initial_training_profile
			initial_training_profile=""
			_toggle_training(profile)
		return
	if scenery == null:
		scenery = preload("res://scripts/presentation/ui/region_scenery.gd").new() as Node3D
		viewport.add_child(scenery)
		scenery.connect("changed",_request_frame)
		scenery.call("begin",terrain)
		_cartography = scenery.get("_region_document") as Dictionary
		scenery.call("update_view",center,span_m)
	_detail.disabled = false
	_walk_button.disabled = false
	_training_button.disabled = false
	_battlefield_button.disabled = false
	_status.text = "50m外围 / 4m原生高度样本 · 仅显示精度逐级提高，不增加测绘精度。"
	_request_frame()
	if not initial_training_profile.is_empty():
		var profile := initial_training_profile
		initial_training_profile=""
		_toggle_training(profile)

func _request_frame() -> void:
	_dirty = true
	if _training_active and is_instance_valid(_training) and _training.has_method("request_frame"):
		_training.call("request_frame")
	elif viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _grid != null: _grid.queue_redraw()

func _set_range(value: float) -> void:
	_stop_walk()
	if value <= 5000:
		_enter_selected()
		return
	span_m = value
	if value >= 50000: center=Vector2(2500,2500)
	elevation = 52.0
	_request_frame()

func _enter_selected() -> void:
	if selected_cell != Vector2i(4,4):
		_status.text = "选中格 %d / %d 只有50m概略地形；本轮只安装绿色原生5km区块。" %[selected_cell.x,selected_cell.y]
		return
	_enter_native()

func _enter_native() -> void:
	_stop_walk()
	if span_m > 8500:
		_previous_region_center = center
		_previous_region_span = span_m
		_previous_region_bearing = bearing
		_previous_region_elevation = elevation
	center = Vector2.ZERO
	span_m = 5000
	elevation = 52.0
	_status.text = "Ridgevale 5 × 5 km · 原村庄 / 鞍部道路；细节资产集中于中央800m。"
	_request_frame()

func _back() -> void:
	if _walking:
		_stop_walk()
		span_m = 1100
	elif span_m < 8500:
		center = _previous_region_center
		span_m = _previous_region_span
		bearing = _previous_region_bearing
		elevation = _previous_region_elevation
	else:
		_close()
	_request_frame()

func _close() -> void:
	_stop_walk()
	closed.emit()

func _observation_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and mouse.pressed:
			if not _walking:
				var target := clampf(span_m*(0.8 if mouse.button_index==MOUSE_BUTTON_WHEEL_UP else 1.25),75.0,50000.0)
				if span_m>=8500 and target<8500:
					if selected_cell==Vector2i(4,4): _enter_native()
					else: target=8500
				span_m = target
				_request_frame()
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			_drag = mouse.pressed
			if mouse.pressed: _press=mouse.position;_last=mouse.position
			elif _press.distance_to(mouse.position)<6 and not _walking: _select_at(mouse.position,mouse.double_click)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = mouse.pressed
			_last = mouse.position
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbit:
			bearing -= motion.relative.x*0.006
			elevation = clampf(elevation+motion.relative.y*0.15,12,85)
			_request_frame()
		elif _drag and not _walking:
			var step := Vector2(-motion.relative.x,-motion.relative.y)*camera.size/maxf(1,size.y)
			center += step.rotated(bearing)
			_clamp_center()
			_request_frame()

func _observation_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key := event as InputEventKey
	if key.echo: return
	if key.keycode in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT]:
		_held[key.keycode] = key.pressed
		get_viewport().set_input_as_handled()
	elif key.pressed and key.keycode==KEY_ESCAPE:
		_back()
		get_viewport().set_input_as_handled()
	elif key.pressed and key.keycode==KEY_F12:
		_capture()
		get_viewport().set_input_as_handled()

func _select_at(point: Vector2, double_click: bool) -> void:
	var ray := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	if absf(direction.y)<0.0001: return
	var hit := ray+direction*(-ray.y/direction.y)
	selected_cell = Vector2i(clampi(floori((hit.x+22500)/5000),0,9),clampi(floori((hit.z+22500)/5000),0,9))
	_status.text = "已选区块 %d / %d · %s" %[selected_cell.x,selected_cell.y,"原生5km已安装；再次点击进入或双击" if selected_cell==Vector2i(4,4) else "仅概略观察，未安装精细资产"]
	if double_click and selected_cell==Vector2i(4,4): _enter_native()
	_request_frame()

func _clamp_center() -> void:
	var half := 2400.0 if span_m<8500 else 25000.0
	center.x = clampf(center.x,-half,half)
	center.y = clampf(center.y,-half,half)

func _process_observation(delta: float) -> void:
	var movement := Vector2(float(bool(_held.get(KEY_D,false)))-float(bool(_held.get(KEY_A,false))),float(bool(_held.get(KEY_S,false)))-float(bool(_held.get(KEY_W,false))))
	if not _walking and movement.length_squared()>0:
		center += movement.normalized().rotated(bearing)*span_m*0.4*delta
		_clamp_center()
		_request_frame()
	if not _dirty or camera==null: return
	_dirty = false
	_environment.background_mode=Environment.BG_SKY if _walking else Environment.BG_COLOR
	_sun.shadow_enabled=_walking
	if not _walking:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# One square-framing rule: no size jump at 8500m or exactly 5000m.
		camera.size = span_m*sin(deg_to_rad(elevation))*1.6
		var ground := 0.0
		if terrain != null and bool(terrain.call("is_ready")):
			ground = float(terrain.call("sample_height",center.x,center.y))
			if not is_finite(ground): ground=0
		var target := Vector3(center.x,ground,center.y)
		var pitch := deg_to_rad(elevation)
		var distance := maxf(span_m,1000)
		camera.position = target+Vector3(sin(bearing)*cos(pitch),sin(pitch),cos(bearing)*cos(pitch))*distance
		camera.look_at(target)
	if terrain != null and (center.distance_to(_last_center)>(1.0 if _walking else 20.0) or absf(span_m-_last_span)>10):
		terrain.call("update_view",center,span_m)
		if scenery != null: scenery.call("update_view",center,span_m)
		_last_center = center
		_last_span = span_m
	_camera_ready = true
	_title.text = "隔离训练观察 · Ridgevale"+(" · 步行" if _walking else "")
	_grid.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_grid() -> void:
	if camera==null or not _camera_ready or span_m<8500: return
	for i: int in range(11):
		var coord := -22500+i*5000
		_grid.draw_line(camera.unproject_position(Vector3(coord,0,-22500)),camera.unproject_position(Vector3(coord,0,27500)),Color(0.82,0.9,0.78,0.3),1)
		_grid.draw_line(camera.unproject_position(Vector3(-22500,0,coord)),camera.unproject_position(Vector3(27500,0,coord)),Color(0.82,0.9,0.78,0.3),1)
	for cell: Vector2i in [Vector2i(4,4),selected_cell]:
		var points := PackedVector2Array()
		for corner: Vector2 in [Vector2.ZERO,Vector2(5000,0),Vector2(5000,5000),Vector2(0,5000),Vector2.ZERO]:
			points.append(camera.unproject_position(Vector3(-22500+cell.x*5000+corner.x,0,-22500+cell.y*5000+corner.y)))
		_grid.draw_polyline(points,Color("f5c97b") if cell==selected_cell else Color("80dba0"),3)
	# Cartographic ink uses the admitted synthetic layout, not new world facts.
	var river := PackedVector2Array()
	for p: Array in _cartography.get("river",[]): river.append(camera.unproject_position(Vector3(float(p[0]),float(p[1]),float(p[2]))))
	if river.size()>1: _grid.draw_polyline(river,Color("67bfd6"),2)
	for index: int in range((_cartography.get("towns",[]) as Array).size()):
		var town: Dictionary=_cartography.towns[index]
		var p: Array=town.position
		var town_point:=camera.unproject_position(Vector3(float(p[0]),float(p[1]),float(p[2])))
		_grid.draw_rect(Rect2(town_point-Vector2(3,3),Vector2(6,6)),Color("f3d69e"))
		_grid.draw_string(theme.default_font,town_point+Vector2(8,4),"训练聚落 %02d" %[index+1],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e8ecd5"))
	var marker := camera.unproject_position(Vector3(0,100,0))
	_grid.draw_circle(marker,5,Color("82f1b0"))
	_grid.draw_string(theme.default_font,marker+Vector2(12,-12),"Ridgevale 5 km · 已安装",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("e6ffdd"))

func _toggle_walk() -> void:
	if _walk_preparing: return
	if _walking:
		_stop_walk()
		span_m=1100
		_request_frame()
		return
	_enter_native()
	var spawn := Vector2(110,225)
	center=spawn
	span_m=150
	terrain.call("update_view",center,span_m)
	_status.text = "正在准备当前位置碰撞；隔离观察体不是正式人物，没有武器、车辆或弹药。"
	# Wait for the real installed local collision, never create a floor substitute.
	_walk_preparing=true
	_walk_generation+=1
	var generation := _walk_generation
	var ready_collision := false
	for attempt: int in range(900):
		if generation!=_walk_generation: return
		if bool(terrain.call("is_collision_ready",Vector3(spawn.x,0,spawn.y))):
			ready_collision=true
			break
		await get_tree().physics_frame
	_walk_preparing=false
	if not ready_collision:
		_status.text="局部碰撞尚未就绪，未生成观察体；仍可使用3D观察。"
		return
	var y := float(terrain.call("sample_height",spawn.x,spawn.y))
	if not is_finite(y): return
	_walker = CharacterBody3D.new()
	_walker.name = "IsolatedSurveyBody_NotFormalPerson"
	_walker.collision_layer=2
	_walker.collision_mask=1
	_walker.floor_snap_length=0.5
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.3
	capsule.height=1.7
	collider.shape=capsule
	collider.position.y=0.85
	_walker.add_child(collider)
	viewport.add_child(_walker)
	_walker.position=Vector3(spawn.x,y+0.5,spawn.y)
	_walking=true
	elevation=8
	bearing=-1.2
	_walk_button.text="结束隔离步行"
	_status.text="隔离步行 · WASD移动 / Shift快走 / 右拖看向 · 使用真实局部地形碰撞；不写入正式世界。"
	_request_frame()

func _physics_process(delta: float) -> void:
	if not _walking or not is_instance_valid(_walker): return
	var move := Vector2(float(bool(_held.get(KEY_D,false)))-float(bool(_held.get(KEY_A,false))),float(bool(_held.get(KEY_S,false)))-float(bool(_held.get(KEY_W,false))))
	var direction := Vector3(move.x,0,move.y).rotated(Vector3.UP,bearing).normalized()
	var speed := 5.0 if bool(_held.get(KEY_SHIFT,false)) else 2.2
	_walker.velocity.x=direction.x*speed
	_walker.velocity.z=direction.z*speed
	_walker.velocity.y = -1.0 if _walker.is_on_floor() else _walker.velocity.y-18*delta
	var anticipated := _walker.position+Vector3(_walker.velocity.x,0,_walker.velocity.z)*delta
	if not bool(terrain.call("is_collision_ready",anticipated)):
		# Ask for the next safety square before waiting: never strand the body at a stream boundary.
		terrain.call("update_view",Vector2(anticipated.x,anticipated.z),span_m)
		_walker.velocity.x=0
		_walker.velocity.z=0
	var before := _walker.position
	_walker.move_and_slide()
	# A missing collision never becomes permission to fall through an unloaded chunk.
	var expected := float(terrain.call("sample_height",_walker.position.x,_walker.position.z))
	if not is_finite(expected) or _walker.position.y<expected-0.5 or absf(_walker.position.x)>2400 or absf(_walker.position.z)>2400:
		_walker.position=before
		_walker.velocity=Vector3.ZERO
	center=Vector2(_walker.position.x,_walker.position.z)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.fov=72
	camera.position=_walker.position+Vector3(0,1.62,0)
	camera.rotation=Vector3(-deg_to_rad(elevation),bearing,0)
	if direction.length_squared()>0 or _walker.position.distance_to(before)>0.001 or _dirty: _request_frame()

func _stop_walk() -> void:
	_walk_generation+=1
	_walk_preparing=false
	_walking=false
	_held.clear()
	if is_instance_valid(_walker): _walker.queue_free()
	_walker=null
	if _walk_button!=null: _walk_button.text="步行观察（隔离）"

func _capture() -> void:
	_request_frame()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var folder := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var stamp := Time.get_datetime_string_from_system().replace(":","-")
	var path := folder+"/terrain_"+stamp
	var error := get_viewport().get_texture().get_image().save_png(path+".png")
	if error!=OK:
		_status.text="截图失败："+error_string(error)
		return
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file!=null:
		var active_camera: Camera3D = viewport.get_camera_3d()
		file.store_string(JSON.stringify({"region_id":region_config.id,"native_map_id":region_config.native_map_id,"training_only":true,"georegistered":false,"context":context,"center_m":[center.x,center.y],"span_m":span_m,"selected_cell":[selected_cell.x,selected_cell.y],"walking":_walking,"military_training_active":_training_active,"training":get_training_status(),"camera":str(active_camera.global_transform) if active_camera != null else "not_ready"},"\t"))
	_status.text="已保存真实游戏截图："+ProjectSettings.globalize_path(path+".png")

func _exit_tree() -> void:
	# End only this explicit isolated scenario; never persist it as a formal unit.
	if is_instance_valid(_training): _training.call("close")
	if is_instance_valid(terrain): terrain.call("close")
