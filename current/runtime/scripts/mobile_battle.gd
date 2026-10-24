extends Control
## Pointer IDs are independent: driving, looking and firing can run simultaneously.
var main: Node3D
var map_observing := false
var presentation_exclusions: Array[Rect2] = []
var drive := Vector2.ZERO
var drive_pointer := -99
var look_pointer := -99
var fire_pointer := -99
var mg_pointer := -99
# A vehicle fire-origin gesture keeps ownership after leaving its first button.
# The primary trigger is never rearmed until a fresh press.
var _fire_slide_pointer := -99
var _fire_slide_zone := ""
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var fire_held := false
var mg_held := false
var menu_open := false
var look_input_radians := 0.0
var _ads_drag_pointer := -99
var _ads_scope_seen := false
const ADS_FINE_GAIN := 0.25
var camera_yaw := PI
var camera_pitch := -0.035
var speed := 0.0
var steer := 0.0
var generation := -1
var travel := 0.0
var left_travel := 0.0
var right_travel := 0.0
var initialized := false
var drive_blocked := false
var camera_obstructed := false
var camera_snap_pending := true
var report_time := 0.0
var menu: PanelContainer
var battle_time := 0.0
var status := ""
var toast := ""
var toast_until := 0
var minimap:Control
var vehicle_hud:Control
var control_mode:="joystick"
var gear:=0
var turn_pointers:Dictionary={}
var stop_pointers:Dictionary={}
var gear_pointers:Dictionary={}
var sight_button:Button
var graphics_button:Button
var mode_button:Button
var fire_layout_rect:=Rect2()
var fire_layout_scale:=1.0
var fire_layout_clock:=0.0
var observed_shot_sequence:=0
var shot_feedback_time:=0.0
var hud_events = preload("res://scripts/battle_hud_events.gd").new()

func setup(host: Node3D) -> void:
	main=host
	main.get_tree().quit_on_go_back=false
	name="BattleControls"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=50
	process_priority=100
	process_mode=Node.PROCESS_MODE_ALWAYS
	main.hud.add_child(self)
	var preferences:=ConfigFile.new()
	if preferences.load("user://controls.cfg")==OK:control_mode=str(preferences.get_value("driving","mode","joystick"))
	if control_mode not in ["joystick","buttons"]:control_mode="joystick"
	_make_menu()
	load("res://scripts/battle_performance_status.gd").new().setup(self)
	load("res://modules/battle_diagnostics/battle_diagnostics.gd").new().setup(self)
	minimap=load("res://scripts/battle_minimap.gd").new();minimap.setup(self)
	vehicle_hud=load("res://scripts/bottom_vehicle_hud.gd").new();vehicle_hud.setup(self)

func active() -> bool:
	return is_instance_valid(main) and not main.garage and main.game_mode=="skirmish" and is_instance_valid(main.hero)

func _make_menu() -> void:
	menu=PanelContainer.new();add_child(menu);menu.hide()
	var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.06,.075,.96);style.set_corner_radius_all(16);style.content_margin_left=22;style.content_margin_right=22;style.content_margin_top=18;style.content_margin_bottom=18
	menu.add_theme_stylebox_override("panel",style)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",10);menu.add_child(col)
	for item in [["乘员",func():main.crew_host.expanded=not main.crew_host.expanded],["联络：请求掩护",func():main.construction_host.request_support("cover");set_menu(false)],["联络：工程支援",func():main.construction_host.request_support("engineering");set_menu(false)],["返回车库",func():set_menu(false);main.switch_mode()]]:
		var b:=Button.new();b.text=item[0];b.custom_minimum_size=Vector2(220,45);b.add_theme_font_override("font",main.font);b.pressed.connect(item[1]);col.add_child(b)

	sight_button=Button.new();sight_button.custom_minimum_size=Vector2(220,45);sight_button.add_theme_font_override("font",main.font);col.add_child(sight_button)
	sight_button.pressed.connect(func():main.tank_sight.cycle(main);_update_sight_label())
	_update_sight_label()
	mode_button=Button.new();mode_button.custom_minimum_size=Vector2(220,45);mode_button.add_theme_font_override("font",main.font);col.add_child(mode_button)
	mode_button.pressed.connect(func():set_control_mode("buttons" if control_mode=="joystick" else "joystick"))
	_update_mode_label()
	graphics_button=Button.new();graphics_button.custom_minimum_size=Vector2(220,45);graphics_button.add_theme_font_override("font",main.font);col.add_child(graphics_button)
	graphics_button.pressed.connect(func():
		var budget=main.get_node_or_null("MobileRenderBudget")
		if budget!=null:budget.set_low_pixel_mode(not budget.low_pixel_mode)
		_update_graphics_label())
	call_deferred("_update_graphics_label")

func _update_sight_label()->void:
	if not is_instance_valid(sight_button):return
	sight_button.visible=main.tank_sight.active(main)
	sight_button.text="标尺 %.0fm · 点击切换"%main.tank_sight.distance

func _update_graphics_label() -> void:
	var budget=main.get_node_or_null("MobileRenderBudget")
	if is_instance_valid(graphics_button):graphics_button.text="画面：低像素（3D 67%）" if budget!=null and budget.low_pixel_mode else "画面：标准（点击省像素）"

func _update_mode_label()->void:
	if is_instance_valid(mode_button):mode_button.text="驾驶设置："+("摇杆" if control_mode=="joystick" else "档位方向键")

func set_control_mode(value:String,persist:bool=true)->void:
	control_mode=value if value in ["joystick","buttons"] else "joystick"
	reset_pointers();speed=0;steer=0;_update_mode_label();queue_redraw()
	if persist:
		var preferences:=ConfigFile.new();preferences.set_value("driving","mode",control_mode);preferences.save("user://controls.cfg")

func direction_button(action:String)->Vector2:
	var center:=center_stick()
	return center+{"forward":Vector2(0,-85),"reverse":Vector2(0,85),"left":Vector2(-85,0),"right":Vector2(85,0),"stop":Vector2.ZERO}[action]

func _sync_button_drive()->void:
	var turn:=0.0
	for value in turn_pointers.values():turn+=float(value)
	drive=Vector2(clampf(turn,-1,1),-(float(gear)/3.0 if gear>0 else float(gear))) if stop_pointers.is_empty() else Vector2.ZERO

func set_menu(value:bool) -> void:
	menu_open=value;menu.visible=value
	get_tree().paused=false
	if is_instance_valid(main.crew_host):main.crew_host.panel.process_mode=Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(main.construction_host):main.construction_host.panel.process_mode=Node.PROCESS_MODE_ALWAYS
	reset_pointers()
	if not value:
		if is_instance_valid(main.crew_host):main.crew_host.expanded=false;main.crew_host.panel.hide()
		if is_instance_valid(main.construction_host):main.construction_host.panel.hide()

func reset_pointers() -> void:
	if is_instance_valid(vehicle_hud):vehicle_hud.pointers.clear()
	if is_instance_valid(main) and main.has_method("clear_vehicle_fire_input"):main.clear_vehicle_fire_input()
	if active() and main.scoped and not on_foot():_ads_stop_intent()
	_ads_drag_pointer=-99
	_fire_slide_pointer=-99;_fire_slide_zone=""
	if active() and on_foot():main.player_infantry_controller.clear_input()
	drive=Vector2.ZERO;drive_pointer=-99;look_pointer=-99;fire_pointer=-99;mg_pointer=-99;fire_held=false;mg_held=false
	gear=0;turn_pointers.clear();stop_pointers.clear();gear_pointers.clear();steer=0;speed=0

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST and active():
		if is_instance_valid(minimap) and minimap.expanded:minimap.cancel()
		else:set_menu(not menu_open)
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_pointers()
		if is_instance_valid(minimap):minimap.cancel()

# Fire/ADS circles share hit radii; the compact MG barrel has transparent touch padding.
# Screen safe area is converted
# through the actual canvas transform, never treated as 1280x720 UI pixels.
func refresh_fire_layout() -> void:
	var safe:=Rect2(Vector2.ZERO,size)
	var transform:=get_viewport().get_screen_transform()*get_global_transform_with_canvas()
	var pixel_scale:=maxf(.01,transform.x.length())
	if OS.has_feature("android") or OS.has_feature("ios"):
		var physical:=DisplayServer.get_display_safe_area()
		if physical.size.x>0 and physical.size.y>0:
			var inverse:=transform.affine_inverse()
			safe=safe.intersection(Rect2(inverse*Vector2(physical.position),Vector2(physical.size)/pixel_scale))
	var dpi:=float(DisplayServer.screen_get_dpi()) if OS.has_feature("android") or OS.has_feature("ios") else 160.0
	configure_fire_layout(safe,dpi,pixel_scale)

func configure_fire_layout(safe:Rect2,dpi:float,pixel_scale:float) -> void:
	fire_layout_rect=safe if safe.size.x>0 and safe.size.y>0 else Rect2(Vector2.ZERO,size)
	# Preserve the established device/safe-area scale while reducing the visual footprint.
	var density_scale:=76.0*maxf(160.0,dpi)/160.0/maxf(.01,pixel_scale)/128.0
	fire_layout_scale=minf(maxf(1.0,density_scale),minf(fire_layout_rect.size.y/620.0,fire_layout_rect.size.x/780.0))
	fire_layout_scale=maxf(.45,fire_layout_scale)

func action_radius(action:String) -> float:
	return (70.0 if action=="fire" else 44.0 if action in ["ads","mg"] else 64.0)*fire_layout_scale

func _fire_anchor(offset:Vector2) -> Vector2:
	var rect:=fire_layout_rect if fire_layout_rect.size.x>0 else Rect2(Vector2.ZERO,size)
	return rect.end-offset*fire_layout_scale

# Reference viewport proportions, not physical centimeters: 38 UI units ≈ requested 1 cm.
func center_fire() -> Vector2:return _fire_anchor(Vector2(112,129))
func center_ads() -> Vector2:return _fire_anchor(Vector2(112,281))
func center_mg() -> Vector2:return _fire_anchor(Vector2(262,125))
func board_exit_rect() -> Rect2:
	return Rect2(_fire_anchor(Vector2(36,34))-Vector2(28,28)*fire_layout_scale,Vector2(56,56)*fire_layout_scale)
func center_stance() -> Vector2:return _fire_anchor(Vector2(300,300))
func center_sprint() -> Vector2:return _fire_anchor(Vector2(300,475))
func center_stick() -> Vector2:return Vector2(maxf(160,fire_layout_rect.position.x+125),size.y-160)


func _input(event:InputEvent) -> void:
	if not active():return
	if map_observing:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:_pointer(-1,event.position,false)
		elif event is InputEventScreenTouch and (not event.pressed or event.canceled):_pointer(event.index,event.position,false)
		return
	# Godot emits mouse events for touch with device -1. Never let that
	# duplicate stream own a battle pointer; GUI buttons still receive it.
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION:return
	# Release/cancel is processed before any modal selection routing.
	if event is InputEventScreenTouch and event.canceled:
		_pointer(event.index,event.position,false);minimap.cancel();get_viewport().set_input_as_handled();return
	if event is InputEventScreenTouch and not event.pressed:
		_pointer(event.index,event.position,false);return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		_pointer(-1,event.position,false);return
	if event is InputEventMouseButton and event.pressed or event is InputEventScreenTouch and event.pressed:
		for rect: Rect2 in presentation_exclusions:
			if rect.has_point(event.position):return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if minimap.expanded:minimap.cancel()
			else:set_menu(not menu_open)
			get_viewport().set_input_as_handled()
		if event.keycode==KEY_SHIFT:main.toggle_scope();get_viewport().set_input_as_handled()
		if event.keycode==KEY_E and on_foot():main.player_infantry_controller.request_pickup();get_viewport().set_input_as_handled()
		if event.keycode==KEY_R and on_foot():main.player_infantry_controller.request_reload();get_viewport().set_input_as_handled()
		if event.keycode==KEY_C and on_foot() and not menu_open:main.player_infantry_controller.cycle_stance();get_viewport().set_input_as_handled()
		if event.keycode==KEY_V and on_foot() and not menu_open:main.player_infantry_controller.toggle_sprint();get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch and minimap.handle_pointer(event.index,event.position,event.pressed and not event.canceled):
		get_viewport().set_input_as_handled();return
	if event is InputEventScreenDrag and minimap.handle_motion(event.index):get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and minimap.handle_pointer(-1,event.position,event.pressed):get_viewport().set_input_as_handled();return
	if is_instance_valid(main.construction_host) and main.construction_host.selecting and not menu_open:
		return
	if event is InputEventScreenTouch:
		_pointer(event.index,event.position,event.pressed and not event.canceled)
	elif event is InputEventScreenDrag:
		_motion(event.index,event.position,event.relative)
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:_pointer(-1,event.position,event.pressed)
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			main.toggle_scope();get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_motion(-1,event.position,event.relative)

func _pointer(id:int,p:Vector2,pressed:bool) -> void:
	# Handle the original fire finger before any HUD/modal can consume its release.
	if id==_fire_slide_pointer:
		if not pressed:_end_fire_slide()
		get_viewport().set_input_as_handled();return
	if is_instance_valid(vehicle_hud) and vehicle_hud.pointer(id,p,pressed):get_viewport().set_input_as_handled();return
	if not pressed:
		if id==_ads_drag_pointer and main.scoped and not on_foot():
			_ads_stop_intent()
		var handled:=false
		if turn_pointers.has(id):turn_pointers.erase(id);_sync_button_drive();steer=0;handled=true
		if stop_pointers.has(id):stop_pointers.erase(id);_sync_button_drive();handled=true
		if gear_pointers.has(id):gear_pointers.erase(id);handled=true
		if id==drive_pointer:drive=Vector2.ZERO;drive_pointer=-99;steer=0;handled=true
		if id==look_pointer:look_pointer=-99;handled=true
		if id==fire_pointer:fire_held=false;fire_pointer=-99;main.clear_vehicle_fire_input();handled=true
		if id==mg_pointer:mg_held=false;mg_pointer=-99;handled=true
		if handled:get_viewport().set_input_as_handled()
		elif is_instance_valid(minimap):minimap.handle_pointer(id,p,false)
		return
	if is_instance_valid(minimap) and minimap.handle_pointer(id,p,true):get_viewport().set_input_as_handled();return
	if p.distance_to(Vector2(size.x-42,42))<32:
		set_menu(not menu_open);get_viewport().set_input_as_handled();return
	if menu_open:return
	if gear_pointers.has(id) or turn_pointers.has(id) or id in [drive_pointer,look_pointer,fire_pointer,mg_pointer]:return
	if main.battle_finished:
		if Rect2(Vector2(size.x*.5-160,size.y*.5),Vector2(320,60)).has_point(p):main.switch_mode()
		return
	# One descriptor supplies drawing, hit bounds, visibility and enabled state.
	for button in utility_actions():
		if not button.visible or not button.rect.has_point(p):continue
		get_viewport().set_input_as_handled()
		if button.enabled:_activate_utility(str(button.id))
		elif not str(button.get("reason","")).is_empty():show_notice(str(button.reason))
		return
	if control_mode=="buttons" and not on_foot():
		for action in ["forward","reverse","left","right"]:
			if p.distance_to(direction_button(action))>38:continue
			if action=="stop":
				gear=0;turn_pointers.clear();stop_pointers[id]=true;speed=0;steer=0
			elif action in ["forward","reverse"]:
				if action=="forward":gear=0 if gear<0 or gear>=3 else gear+1
				else:gear=0 if gear!=0 else -1
				gear_pointers[id]=1 if action=="forward" else -1
				if 1 in gear_pointers.values() and -1 in gear_pointers.values():gear=0
			else:turn_pointers[id]=-1 if action=="left" else 1
			_sync_button_drive();get_viewport().set_input_as_handled();return
	if on_foot() and p.distance_to(center_stance())<=action_radius("stance"):
		main.player_infantry_controller.cycle_stance();get_viewport().set_input_as_handled();return
	if on_foot() and p.distance_to(center_sprint())<=action_radius("sprint"):
		main.player_infantry_controller.toggle_sprint();get_viewport().set_input_as_handled();return
	if p.distance_to(center_fire())<=action_radius("fire"):
		if fire_pointer!=-99 or _fire_slide_pointer!=-99:return
		if main.player_can_fire():
			fire_pointer=id;fire_held=true
			if not on_foot():_fire_slide_pointer=id;_fire_slide_zone="fire"
		if not on_foot():
			main.fire_cannon()
			if not main.player_can_fire():show_notice("炮手失能或离车 · 检查车组状态，失能时可由车长接替")
	elif p.distance_to(center_ads())<=action_radius("ads"):main.toggle_scope()
	elif on_foot() and p.distance_to(center_mg())<=action_radius("mg"):main.player_infantry_controller.request_pickup()
	elif not on_foot() and p.distance_to(center_mg())<=action_radius("mg") and main.primary_weapon() not in ["mg","short_rocket"]:
		if mg_pointer!=-99:return
		mg_pointer=id;mg_held=true;main.fire_mg()
	elif (control_mode=="joystick" or on_foot()) and p.x<size.x*.38 and p.y>size.y*.4 and drive_pointer==-99:
		drive_pointer=id;origin=center_stick();knob=p;_update_drive(p)
	elif look_pointer==-99:
		look_pointer=id
	get_viewport().set_input_as_handled()

func _motion(id:int,p:Vector2,relative:Vector2) -> void:
	if id==_fire_slide_pointer:
		_fire_slide_motion(p);get_viewport().set_input_as_handled();return
	if is_instance_valid(vehicle_hud) and vehicle_hud.pointers.has(id):get_viewport().set_input_as_handled();return
	if is_instance_valid(minimap) and minimap.handle_motion(id):get_viewport().set_input_as_handled();return
	if turn_pointers.has(id) or stop_pointers.has(id) or gear_pointers.has(id):get_viewport().set_input_as_handled();return
	if id==drive_pointer:_update_drive(p);get_viewport().set_input_as_handled()
	elif id==look_pointer or id==mg_pointer or (id==fire_pointer and (on_foot() or main.primary_weapon()=="mg")):
		if main.fire_control.active():main.fire_control.cancel("手动拖镜接管")
		if main.scoped and main.indirect_fire_mode() and not main.artillery_aim.manual:main.artillery_aim.enter_manual(main)
		_sync_ads_mode()
		# Logical input coordinates already account for viewport stretch. No second DPI scale.
		# Match screen angular scale to optical zoom; no frame-delta factor.
		var sensitivity:=.0048*(tan(deg_to_rad(32.0)*.5)/tan(deg_to_rad(62.0)*.5)) if main.scoped else .0048
		if main.scoped and not on_foot():sensitivity*=ADS_FINE_GAIN
		look_input_radians+=relative.length()*sensitivity
		camera_yaw-=relative.x*sensitivity
		# Indirect scoped view follows high elevation; actual mount limits still clamp the bore.
		var high_angle_manual:bool=main.scoped and main.indirect_fire_mode() and main.artillery_aim.manual
		camera_pitch=clampf(camera_pitch-relative.y*sensitivity,-1.55 if high_angle_manual else -.5,1.55 if high_angle_manual else .28)
		if main.scoped and not on_foot():
			_ads_drag_pointer=id
			_ads_bound_lead()
		get_viewport().set_input_as_handled()

func _stop_slide_triggers() -> void:
	# Never clear another finger's direct MG trigger or movement/look ownership.
	if fire_pointer==_fire_slide_pointer:
		fire_pointer=-99;fire_held=false;main.clear_vehicle_fire_input()
	if mg_pointer==_fire_slide_pointer:mg_pointer=-99;mg_held=false

func _end_fire_slide() -> void:
	_stop_slide_triggers()
	_fire_slide_pointer=-99;_fire_slide_zone=""

func _fire_slide_motion(p:Vector2) -> void:
	if menu_open or main.battle_finished or on_foot():_end_fire_slide();return
	var zone:=""
	if p.distance_to(center_ads())<=action_radius("ads"):zone="ads"
	elif main.primary_weapon() not in ["mg","short_rocket"] and p.distance_to(center_mg())<=action_radius("mg"):zone="mg"
	elif p.distance_to(center_fire())<=action_radius("fire"):zone="fire"
	if zone==_fire_slide_zone:return
	_stop_slide_triggers()
	_fire_slide_zone=zone
	if zone=="ads":
		# Idempotent ON, never a toggle loop when re-entering or jittering on the edge.
		if not main.scoped:main.toggle_scope()
	elif zone=="mg" and mg_pointer==-99:
		var capable:bool=main.player_can_fire_any_mg() if main.has_method("player_can_fire_any_mg") else main.player_can_fire()
		if capable:mg_pointer=_fire_slide_pointer;mg_held=true;main.fire_mg()
	# A return to fire, a utility icon, or empty space cannot issue a new main shot.

func _ads_muzzle_angles() -> Vector2:
	var muzzle:Node3D=main.weapon_muzzle()
	if muzzle==null:return Vector2(camera_yaw,camera_pitch)
	var direction:Vector3=main.tank_sight.view_axis(main,-muzzle.global_basis.z.normalized())
	return Vector2(atan2(-direction.x,-direction.z),asin(clampf(direction.y,-1,1)))

func _ads_stop_intent() -> void:
	var angles:=_ads_muzzle_angles()
	camera_yaw=angles.x;camera_pitch=angles.y
	_ads_drag_pointer=-99
	main.aiming_pending=false

func _sync_ads_mode() -> void:
	var scoped_vehicle:bool=main.scoped and not on_foot()
	if scoped_vehicle and not _ads_scope_seen:_ads_stop_intent()
	_ads_scope_seen=scoped_vehicle

func _ads_bound_lead() -> void:
	var angles:=_ads_muzzle_angles()
	# One authoritative tick of each axis's original mechanical rate, in radians.
	var lead:float=main.weapon_aim_speed_radians()/maxf(1,Engine.physics_ticks_per_second)
	camera_yaw=angles.x+clampf(wrapf(camera_yaw-angles.x,-PI,PI),-lead,lead)
	camera_pitch=angles.y+clampf(camera_pitch-angles.y,-lead,lead)

func _update_drive(p:Vector2) -> void:
	drive=(p-origin)/80.0
	if drive.length()>1:drive=drive.normalized()
	if drive.length()<.12:drive=Vector2.ZERO
	knob=origin+drive*70

func _physics_process(delta:float) -> void:
	if not active():
		# Release on a real control transition, not on every inactive practice tick.
		# Repeated cancellation would revoke a legal non-mobile staggered salvo.
		if initialized or drive_pointer!=-99 or look_pointer!=-99 or fire_pointer!=-99 or mg_pointer!=-99 or _fire_slide_pointer!=-99:reset_pointers()
		initialized=false;speed=0;return
	if generation!=main.stage_generation:
		hud_events.clear();toast="";toast_until=0
		generation=main.stage_generation;initialized=false;battle_time=0;speed=0;travel=0;left_travel=0;right_travel=0;reset_pointers();set_menu(false)
	battle_time+=delta
	# Wait until collision terrain and the crew registry are bound.
	if main.ai_started_generation!=generation:return
	if not initialized:
		camera_yaw=main.hero.rotation.y;camera_pitch=-.035;camera_snap_pending=true;initialized=true
	var input:=Vector2.ZERO if map_observing else drive
	if not map_observing and not menu_open and not minimap.expanded:
		input.x+=float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		input.y+=float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	input=input.limit_length()
	if on_foot():
		_on_foot_tick(delta,input);return
	if main.battle_finished:reset_pointers();return
	if not main.player_can_fire() and fire_held:
		fire_held=false;fire_pointer=-99;main.clear_vehicle_fire_input()
	var can_mg:bool=main.player_can_fire_any_mg() if main.has_method("player_can_fire_any_mg") else main.player_can_fire()
	if not can_mg and mg_held:
		mg_held=false;mg_pointer=-99
	var can_drive:bool=not is_instance_valid(main.crew_host) or main.crew_host.can_drive()
	if not can_drive or menu_open:input=Vector2.ZERO
	var mobility:=1.0
	for key in ["track_left","track_right"]:
		if main.player_combat.modules.has(key) and main.player_combat.modules[key].integrity<=0:mobility*=.38
	var desired:float=-input.y*(7.2 if input.y<0 else 3.7)*mobility
	speed=move_toward(speed,desired,delta*(5.5 if absf(desired)>.1 else 8.0))
	steer=move_toward(steer,-input.x*1.0*mobility,delta*4)
	if not can_drive:steer=0
	var support:Dictionary=main.align_vehicle_ground(main.hero)
	var old:Transform3D=main.hero.transform
	# Steer is smoothed left/right intent. Reverse the applied yaw only while
	# travelling backward, so the travel arc follows the stick. Apply this after
	# smoothing to avoid a wrong-way arc when signed speed crosses zero.
	var turn_direction:float=-1.0 if speed<0.0 else 1.0
	var yaw:float=main.hero.rotation.y+steer*turn_direction*delta
	drive_blocked=not bool(support.get("driveable",true))
	# Ground support still updates every tick (including new craters). A motionless
	# rigid hull needs no duplicate fitting or zero-length contact sweep.
	if absf(speed)>0.000001 or absf(steer)>0.000001:
		var contact:Dictionary=main.vehicle_contacts.capture_pose(main.hero)
		main.hero.rotation=Vector3(0,yaw,0)
		var direction:=Vector3(-sin(yaw),0,-cos(yaw))
		main.hero.position+=direction*speed*delta
		var next_support:Dictionary=main.align_vehicle_ground(main.hero)
		var valid:bool=main.GroundSupport.transition_allowed(support,next_support,absf(speed)*delta,absf(steer)*delta)
		drive_blocked=not valid
		if not valid:
			main.hero.transform=old;main.hero.rotation.y=yaw
			var pivot:Dictionary=main.align_vehicle_ground(main.hero)
			if not main.GroundSupport.transition_allowed(support,pivot,0,absf(steer)*delta):main.hero.transform=old;steer=0
			speed=0
		var result:Dictionary=main.vehicle_contacts.resolve_pose(main.hero,contact,speed,delta)
		drive_blocked=drive_blocked or bool(result.get("blocked",false))
		travel+=main.hero.position.distance_to(old.origin)
		if result.get("blocked",false):
			speed=0
			var accepted:Transform3D=main.hero.transform
			var accepted_support:Dictionary=main.align_vehicle_ground(main.hero)
			var pivot_contact:Dictionary=main.vehicle_contacts.capture_pose(main.hero)
			main.hero.rotation.y=yaw
			var pivot_support:Dictionary=main.align_vehicle_ground(main.hero)
			if main.GroundSupport.transition_allowed(accepted_support,pivot_support,0,absf(steer)*delta):main.vehicle_contacts.resolve_pose(main.hero,pivot_contact,0,delta)
			else:main.hero.transform=accepted
	var left:float=speed-steer*turn_direction*1.35
	var right:float=speed+steer*turn_direction*1.35
	left_travel+=left*delta;right_travel+=right*delta
	main.hero.set_meta("track_left_speed",left);main.hero.set_meta("track_right_speed",right)
	main.hero.set_meta("track_left_travel",left_travel);main.hero.set_meta("track_right_travel",right_travel)
	main.hero.set_meta("steering_input",input.x);main.hero.set_meta("vehicle_speed",speed)
	_sync_ads_mode()
	if main.scoped:_ads_bound_lead()
	# The camera aim sets an intended point; turret slew and real muzzle remain authoritative.
	var view_direction:=Vector3(-sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),-cos(camera_yaw)*cos(camera_pitch))
	var aim_origin:Vector3=main.weapon_muzzle().global_position if main.scoped and main.weapon_muzzle()!=null else main.hero.global_position+Vector3(0,2.0,0)
	var goal:=aim_origin+view_direction*260
	if not main.scoped:
		var ray:=PhysicsRayQueryParameters3D.create(main.camera.global_position,main.camera.global_position+view_direction*260,1|8|128)
		var excludes:Array[RID]=[]
		for body in main.hero.find_children("*","CollisionObject3D",true,false):excludes.append(body.get_rid())
		ray.exclude=excludes
		var hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(ray)
		goal=main.camera_aim_point(goal,hit)
	if main.fire_control.active():main.fire_control.tick(delta)
	else:
		main.aim_weapon(goal,false,delta)
		main.advance_weapon_aim(delta)
	if fire_held and main.reload_remaining<=0 and main.mg_remaining<=0:main.fire_cannon()
	if mg_held and main.mg_remaining<=0:main.fire_mg()
	# Exterior camera consumes latest touch intent in render, independently of turret simulation.
	status="驾驶员"+_role_reason(2) if not can_drive else ("前方受阻" if drive_blocked else ("倒车" if speed<-.1 else "行驶" if speed>.1 else "就绪"))

func _ground_available(p:Vector3) -> bool:
	if is_instance_valid(main.terrain_damage) and main.terrain_damage.has_method("in_bounds"):
		if not main.terrain_damage.in_bounds(p.x,p.z):return false
		if not main.terrain_damage.is_position_loaded(p):return false
		return main.terrain_damage.sample_normal(p.x,p.z).y>.78
	var q:=PhysicsRayQueryParameters3D.create(p+Vector3(0,12,0),p-Vector3(0,12,0),8)
	var hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.normal.y>.78

func _camera_clip(focus:Vector3,desired:Vector3) -> Vector3:
	var q:=PhysicsRayQueryParameters3D.create(focus,desired,8|128)
	var hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():return desired
	camera_obstructed=true
	return hit.position+(focus-hit.position).normalized()*.45

func request_camera_snap() -> void:
	camera_snap_pending=true

func _place_exterior_camera(focus:Vector3,desired:Vector3,view:Vector3,delta:float,smoothing:float=9.0) -> void:
	camera_obstructed=false
	var safe:=_camera_clip(focus,desired)
	var candidate:Vector3=safe if camera_snap_pending else main.camera.global_position.lerp(safe,1-exp(-delta*smoothing))
	# Collision must constrain the actual interpolated position, not only its goal.
	main.camera.global_position=_camera_clip(focus,candidate)
	main.camera.look_at(main.camera.global_position+view,Vector3.UP)
	main.camera.fov=62
	camera_snap_pending=false

func _camera_update(delta:float,view_direction:Vector3) -> void:
	var focus:Vector3=(main.hero.get_global_transform_interpolated().origin if get_tree().is_physics_interpolation_enabled() else main.hero.global_position)+Vector3(0,2.15,0)
	_place_exterior_camera(focus,focus-view_direction*10.5+Vector3(0,1,0),view_direction,delta)

func _process(_delta:float) -> void:
	if active() and initialized and not main.battle_finished and not main.scoped and not on_foot():
		var view:=Vector3(-sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),-cos(camera_yaw)*cos(camera_pitch))
		_camera_update(_delta,view)
	shot_feedback_time=maxf(0,shot_feedback_time-_delta)
	if is_instance_valid(main) and is_instance_valid(main.combat_effects):
		var sequence:int=main.combat_effects.player_shot_sequence
		if sequence!=observed_shot_sequence:
			observed_shot_sequence=sequence;shot_feedback_time=.085
	fire_layout_clock-=_delta
	if fire_layout_clock<=0 or fire_layout_rect.size==Vector2.ZERO:
		refresh_fire_layout();fire_layout_clock=.5
	visible=active()
	if not visible:menu.hide();return
	size=get_viewport_rect().size
	menu.position=Vector2(size.x-275,90)
	_update_sight_label()
	# Keep advanced systems accessible behind Commands, never floating over play.
	if is_instance_valid(main.crew_host):
		main.crew_host.toggle.hide()
		main.crew_host.panel.visible=menu_open and main.crew_host.expanded
		main.crew_host.panel.position=Vector2(size.x-560,90)
	if is_instance_valid(main.construction_host):
		main.construction_host.toggle_button.hide()
		main.construction_host.panel.position=Vector2(28,130)
		if not menu_open and not main.construction_host.selecting:main.construction_host.panel.hide()
	if is_instance_valid(main.vehicle_selector):main.vehicle_selector.hide()
	queue_redraw()

func show_notice(text:String) -> void:
	toast=text
	toast_until=Time.get_ticks_msec()+6000

func _circle(p:Vector2,r:float,label:String,pressed:bool=false) -> void:
	draw_circle(p,r,Color(.06,.10,.12,.67 if pressed else .36))
	draw_arc(p,r,0,TAU,64,Color(.91,.89,.75,.9 if pressed else .53),2,true)
	var fs:=clampi(roundi(r*.30),18,30)
	var w:float=main.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	draw_string(main.font,p+Vector2(-w*.5,fs*.36),label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("eee9d9"))

func _draw_mg_barrel() -> void:
	# Small single barrel, no large label/circle. Hit target remains 88 scaled UI units.
	var p:=center_mg()
	var scale_ui:=fire_layout_scale
	var ink:=Color("f5d68b") if mg_held else Color("d6e3de")
	draw_set_transform(p,0,Vector2.ONE*scale_ui)
	# Slim receiver, perforated jacket and bare muzzle; no cannon-like shield.
	var edge:=Color(.06,.08,.07,.95)
	draw_line(Vector2(-27,2),Vector2(29,2),edge,6,true)
	draw_colored_polygon(PackedVector2Array([Vector2(-29,-2),Vector2(-21,-1),Vector2(-21,3),Vector2(-29,6)]),ink)
	draw_rect(Rect2(-21,-3,14,8),edge,true)
	draw_rect(Rect2(-20,-2,12,6),ink,true)
	draw_rect(Rect2(-8,-2,26,5),ink,true)
	for x in [-4,2,8,14]:draw_line(Vector2(x,-1),Vector2(x,2),edge,2,true)
	draw_line(Vector2(18,.5),Vector2(30,.5),ink,2,true)
	draw_line(Vector2(23,.5),Vector2(23,-4),ink,2,true)
	draw_line(Vector2(-15,4),Vector2(-18,10),ink,2,true)
	draw_line(Vector2(12,4),Vector2(8,10),ink,1.5,true)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if not active():return
	# Small peripheral reticle ticks acknowledge actual emitted shots, including
	# point-blank ADS where drawing a tracer would violate camera clearance.
	if shot_feedback_time>0 and main.scoped:
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			draw_line(size*.5+direction*28,size*.5+direction*37,Color(1,.78,.3,.9),3,true)
	if shot_feedback_time>0 and not main.scoped:
		var mg_button:bool=not on_foot() and main.combat_effects.last_player_kind=="mg" and main.primary_weapon() not in ["mg","short_rocket"]
		draw_arc(center_mg() if mg_button else center_fire(),action_radius("mg" if mg_button else "fire")+4,0,TAU,48,Color(1,.78,.3,.95),4,true)
	var base:=center_stick()
	if control_mode=="joystick" or on_foot():
		draw_circle(base,90,Color(.05,.09,.10,.25));draw_arc(base,90,0,TAU,64,Color(.8,.86,.86,.34),2,true)
		draw_circle(base+drive*70,34,Color(.84,.87,.81,.38))
		draw_arc(base+drive*70,34,0,TAU,40,Color(.94,.93,.85,.65),2,true)
	else:
		_circle(direction_button("forward"),36,"前进",gear>0)
		_circle(direction_button("reverse"),36,"倒车",gear==-1)
		_circle(direction_button("left"),36,"左",drive.x<0)
		_circle(direction_button("right"),36,"右",drive.x>0)
		draw_string(main.font,base+Vector2(-105,-137),"档位："+("F%d"%gear if gear>0 else "R" if gear<0 else "N"),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("f1ead7"))
	var foot_fire: String = ""
	if on_foot():
		var foot_actor = main.player_infantry_controller.actor()
		foot_fire = "徒手" if foot_actor.weapon.is_empty() else "换弹中" if foot_actor.brain.state=="reload" else "无弹药" if foot_actor.brain.ammo+foot_actor.brain.reserve_ammo<=0 else "射击"
	_circle(center_fire(),action_radius("fire"),foot_fire if on_foot() else "停火" if not main.player_can_fire() else "%.1f"%main.reload_remaining if main.reload_remaining>.05 else "开火",fire_held)
	if not main.player_can_fire():
		draw_circle(center_fire(),action_radius("fire"),Color(.07,.08,.09,.55))
	_circle(center_ads(),action_radius("ads"),"",main.scoped)
	var aim_center:=center_ads()
	draw_arc(aim_center,12,0,TAU,32,Color("d6e3de"),2,true)
	for axis in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:draw_line(aim_center+axis*8,aim_center+axis*20,Color("d6e3de"),2,true)
	if on_foot():
		_circle(center_mg(),action_radius("mg"),"拾取")
		_circle(center_stance(),action_radius("stance"),main.player_infantry_controller.next_stance_label())
		_circle(center_sprint(),action_radius("sprint"),"步行" if main.player_infantry_controller.actor().sprinting else "跑步",main.player_infantry_controller.actor().sprinting)
	elif main.primary_weapon() not in ["mg","short_rocket"]:_draw_mg_barrel()
	_circle(Vector2(size.x-42,42),25,"≡",menu_open)
	for button in utility_actions():
		if not button.visible:continue
		if button.id=="board_exit":
			var center:Vector2=button.rect.get_center()
			var color:=Color("dae5df") if button.enabled else Color(.6,.65,.63,.45)
			draw_set_transform(center,0,Vector2.ONE*fire_layout_scale)
			draw_circle(Vector2.ZERO,23,Color(.025,.045,.055,.45))
			draw_rect(Rect2(Vector2(-12,-14),Vector2(18,28)),color,false,2)
			var direction:float=-1.0 if on_foot() else 1.0
			draw_line(Vector2(-3,0),Vector2(16*direction,0),color,2)
			draw_line(Vector2(16*direction,0),Vector2(10*direction,-5),color,2)
			draw_line(Vector2(16*direction,0),Vector2(10*direction,5),color,2)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_style_box(_chip(),button.rect)
			draw_string(main.font,button.rect.position+Vector2(12,28),button.label,HORIZONTAL_ALIGNMENT_LEFT,button.rect.size.x-24,18,Color.WHITE if button.enabled else Color("929c9c"))
	var event_lines: Array[String] = hud_events.lines(Time.get_ticks_msec())
	if not event_lines.is_empty():
		var event_width := 0.0
		for line in event_lines:event_width=maxf(event_width,main.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x)
		var event_style := _chip()
		event_style.bg_color=Color(.025,.04,.05,.82)
		draw_style_box(event_style,Rect2(Vector2(18,426),Vector2(minf(620,event_width+24),12+24*event_lines.size())))
	var event_y := 447.0
	for line in event_lines:
		draw_string(main.font,Vector2(30,event_y),line,HORIZONTAL_ALIGNMENT_LEFT,596,17,Color("f5dfb8"))
		event_y += 24
	var limit := aim_status_text()
	if not limit.is_empty():draw_circle(size*.5+Vector2(0,24),3,Color("edab87"))
	if main.battle_finished:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,.6))
		draw_string(main.font,Vector2(size.x*.5-150,size.y*.5-30),"车长阵亡 · 战斗结束",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color.WHITE)
		draw_style_box(_chip(),Rect2(Vector2(size.x*.5-160,size.y*.5),Vector2(320,60)))
		draw_string(main.font,Vector2(size.x*.5-50,size.y*.5+38),"返回车库",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color.WHITE)

func _role_reason(index:int) -> String:
	if main.player_combat.crew.size()<=index:return "缺岗"
	if not main.crew_host.registry._role_capable(main.player_combat.crew[index],"gunner" if index==1 else "driver"):return "失能"
	if index not in main.player_onboard_indices():return "已离车"
	return "缺岗"

func _vehicle_disabled() -> bool:
	return main.player_combat.crew.size()>2 and not main.player_combat.crew[1].alive and not main.player_combat.crew[2].alive

func _chip() -> StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=Color(.04,.07,.09,.48);s.set_corner_radius_all(12);return s

func on_foot()->bool:
	return is_instance_valid(main.player_infantry_controller) and main.player_infantry_controller.active()

func _on_foot_tick(delta:float,input:Vector2)->void:
	var controller=main.player_infantry_controller
	var actor:Node3D=controller.actor()
	if not is_instance_valid(actor):return
	var forward:=Vector3(-sin(camera_yaw),0,-cos(camera_yaw))
	var right:=Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	var motion:Vector3=right*input.x-forward*input.y
	var view:=Vector3(-sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),-cos(camera_yaw)*cos(camera_pitch))
	var focus:Vector3=actor.global_position+Vector3.UP*(actor.view_height() if actor.has_method("view_height") else 1.55)
	var goal:Vector3=focus+view*260
	var query:=PhysicsRayQueryParameters3D.create(focus,goal,1|8|128)
	query.exclude=[actor.get_rid()]
	var hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
	goal=main.camera_aim_point(goal,hit)
	controller.set_input(Vector2(motion.x,motion.z),goal,fire_held and not menu_open)
	if not main.scoped:
		_place_exterior_camera(focus,focus-view*4.5+right*.55,view,delta,12.0)
	speed=actor.velocity.length();status="车长步战"

func record_shot(kind: String, visible_contact: bool) -> void:
	hud_events.push("shot",hud_events.shot_text(kind,visible_contact),Time.get_ticks_msec())
func record_incoming(text: String) -> void:
	hud_events.push("incoming",text,Time.get_ticks_msec())
func aim_status_text() -> String:
	if on_foot():return ""
	if main.aim_contact_blocked:return "炮管受阻 · 调整车位或瞄准方向"
	if main.aim_limited:return "瞄准限位 · "+str(main.aim_limit_reason)
	if camera_obstructed and not main.scoped:return "观察位贴近掩体 · 视距已收近"
	var muzzle:Node3D=main.weapon_muzzle()
	if muzzle!=null:
		var view:=Vector3(-sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),-cos(camera_yaw)*cos(camera_pitch))
		var gap:=rad_to_deg(view.angle_to(-muzzle.global_basis.z.normalized()))
		if gap>3.0:return "炮塔转动中 · 观察与炮口相差 %.0f°"%gap
	return ""

func utility_actions() -> Array[Dictionary]:
	var foot := on_foot()
	var safe := fire_layout_rect if fire_layout_rect.size.x>0 else Rect2(Vector2.ZERO,size)
	var origin_ui := safe.position
	var take: Dictionary = main.crew_host.takeover_status() if is_instance_valid(main.crew_host) else {}
	var needs: bool = is_instance_valid(main.crew_host) and main.crew_host.gunner_needs_takeover()
	var pending := bool(take.get("pending",false))
	var assigned := bool(take.get("active",false))
	var moving := not foot and absf(float(main.hero.get_meta("vehicle_speed",0.0)))>0.5
	var ammo_text: String = "火箭" if main.primary_weapon()=="short_rocket" else ["曳光","穿甲","燃烧"][main.mg_ammo] if main.primary_weapon()=="mg" else ["AP 穿甲","HE 高爆","SMK 烟幕"][main.ammo]
	var reload_enabled: bool = main.primary_weapon()!="short_rocket"
	var ammo_left:=safe.position.x+safe.size.x*.43
	var ammo_width:=minf(210,maxf(1,center_mg().x-action_radius("mg")-14-ammo_left))
	if foot:
		var actor = main.player_infantry_controller.actor()
		ammo_text="徒手 · 靠近武器拾取" if actor.weapon.is_empty() else "%s 换弹 %d/%d"%[main.player_infantry_controller.weapon_label(),actor.brain.ammo,actor.brain.reserve_ammo]
		reload_enabled=main.player_infantry_controller.can_reload()
	return [
		{"id":"designate","rect":Rect2(origin_ui+Vector2(196,270),Vector2(170,44)),"visible":false,"enabled":true,"label":"取消指示 / 手动" if main.fire_control.active() else "指示观察方向","reason":""},
		{"id":"board_exit","rect":board_exit_rect(),"visible":true,"enabled":not moving,"label":"原车 %.0fm · 返回"%main.player_infantry_controller.actor().global_position.distance_to(main.hero.global_position) if foot else "车长下车","reason":"车辆仍在移动，请先停车" if moving else ""},
		{"id":"takeover","rect":Rect2(origin_ui+Vector2(330,194),Vector2(200,44)),"visible":false,"enabled":needs and not pending and not assigned,"label":"车长兼任炮手" if assigned else "接替中 %.1f秒"%float(take.get("remaining",0)) if pending else "接替炮手","reason":""},
		{"id":"ammo","rect":Rect2(Vector2(ammo_left,safe.end.y-65),Vector2(ammo_width,43)),"visible":foot,"enabled":reload_enabled,"label":("下一发 " if not foot and main.primary_weapon()=="cannon" else "")+ammo_text+(" ›" if reload_enabled else ""),"reason":"当前无法换弹" if foot else ""}
	]

func _activate_utility(id: String) -> void:
	match id:
		"designate":
			if main.fire_control.active():main.fire_control.cancel("已取消，手动接管")
			else:
				var result:Dictionary=main.fire_control.designate_from_view()
				show_notice("炮手已接收；拖镜可接管，开火由你决定" if bool(result.ok) else str(result.reason))
		"board_exit":
			if on_foot():main.player_infantry_controller.request_board()
			else:main.crew_host.request_commander_exit()
		"takeover":main.crew_host.request_commander_takeover()
		"ammo":
			if on_foot():main.player_infantry_controller.request_reload()
			elif main.primary_weapon()=="mg":main.cycle_mg()
			elif main.primary_weapon()!="short_rocket":main.select_ammo((main.ammo+1)%3)

