extends Control
## A presentation excursion in the original FormalWorldApplication, never a world owner.
signal closed
const REGION_PATH := "res://data/map_regions/ridgevale_training.json"
var context: Dictionary = {}
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

func _ready() -> void:
	name = "MilitaryTerrainObservation"
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
	resized.connect(_resize)
	_resize()
	var script := load("res://scripts/presentation/terrain/layered_terrain.gd") as GDScript
	if script == null:
		_status.text = "地形组件尚未安装。返回后可继续原正式世界。"
		return
	terrain = script.new() as Node3D
	viewport.add_child(terrain)
	terrain.connect("changed",_request_frame)
	terrain.connect("prepared",_on_prepared)
	terrain.connect("failed",func(message: String) -> void: _status.text = "资源不可用："+message; _request_frame())
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
	_title.text = "军事地貌 / Ridgevale · 50 × 50 km"
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
	_button(controls,"村庄 / 道路",func() -> void: _enter_native();center=Vector2(0,40);span_m=700;elevation=30;_request_frame())
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
	button.pressed.connect(callback)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

func _resize() -> void:
	if viewport == null: return
	# One native-size target, no second simultaneous view or supersampling.
	viewport.size = Vector2i(size).max(Vector2i(1,1))
	_request_frame()

func _on_prepared() -> void:
	if scenery == null:
		scenery = preload("res://scripts/presentation/ui/region_scenery.gd").new() as Node3D
		viewport.add_child(scenery)
		scenery.connect("changed",_request_frame)
		scenery.call("begin",terrain)
		_cartography = scenery.get("_region_document") as Dictionary
		scenery.call("update_view",center,span_m)
	_detail.disabled = false
	_walk_button.disabled = false
	_status.text = "50m外围 / 4m原生高度样本 · 仅显示精度逐级提高，不增加测绘精度。"
	_request_frame()

func _request_frame() -> void:
	_dirty = true
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
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

func _gui_input(event: InputEvent) -> void:
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

func _input(event: InputEvent) -> void:
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

func _process(delta: float) -> void:
	var movement := Vector2(float(bool(_held.get(KEY_D,false)))-float(bool(_held.get(KEY_A,false))),float(bool(_held.get(KEY_S,false)))-float(bool(_held.get(KEY_W,false))))
	if not _walking and movement.length_squared()>0:
		center += movement.normalized().rotated(bearing)*span_m*0.4*delta
		_clamp_center()
		_request_frame()
	if not _dirty or camera==null: return
	_dirty = false
	_environment.background_mode=Environment.BG_COLOR if span_m>=8500 and not _walking else Environment.BG_SKY
	_sun.shadow_enabled=_walking
	if not _walking:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# Fit the complete square region in the usable height, not only its width.
		var full_square := span_m>=8500 or is_equal_approx(span_m,5000)
		camera.size = span_m*sin(deg_to_rad(elevation))*1.6 if full_square else span_m*size.y/maxf(1,size.x)
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
	var scale_label := "%.2f km观察宽度" %[span_m/1000]
	if span_m>=8500 or is_equal_approx(span_m,5000): scale_label="%.0f × %.0f km 范围" %[span_m/1000,span_m/1000]
	_title.text = "军事地貌 / Ridgevale · %s" % ("隔离步行观察" if _walking else scale_label)
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
		file.store_string(JSON.stringify({"region_id":region_config.id,"native_map_id":region_config.native_map_id,"training_only":true,"georegistered":false,"context":context,"center_m":[center.x,center.y],"span_m":span_m,"selected_cell":[selected_cell.x,selected_cell.y],"walking":_walking,"camera":str(camera.transform)},"\t"))
	_status.text="已保存真实游戏截图："+ProjectSettings.globalize_path(path+".png")

func _exit_tree() -> void:
	if is_instance_valid(terrain): terrain.call("close")
