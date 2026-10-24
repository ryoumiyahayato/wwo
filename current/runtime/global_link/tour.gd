extends Node
## Actual engine recording path. Uses the host actions and native local controls.
var host: Node
var phase := 0
var clock := 0.0
var marks: Dictionary = {}
var fired := false
var walking := false
var boarded := false
var drag_pixel := Vector2(470,295)
var dragging := false

func _ready() -> void:
	process_priority=2000
	Input.use_accumulated_input=false
	if not host.get_viewport().get_meta("replay_mouse_entered",false):
		host.get_viewport().notify_mouse_entered()
		host.get_viewport().set_meta("replay_mouse_entered",true)

func text(value: String) -> void:
	host.active_caption=value
	if host.local_shell!=null and host.local_shell.ready_battle:host.local_shell.navigation.caption=value

func mark(name: String) -> void:
	if marks.has(name):return
	marks[name]=true;host.record(name);host.capture(name)

func click_map(point: Vector2) -> void:
	await click_root(point+host.globe.position)
	host.input_observations["footprint_selected_by_pointer"]=host.globe.selected

func mouse_button(button: MouseButton,pressed: bool,point: Vector2) -> void:
	root_mouse(button,pressed,point+host.globe.position)

func wheel(button: MouseButton) -> void:
	mouse_button(button,true,host.globe.size*.5)
	await get_tree().process_frame
	mouse_button(button,false,host.globe.size*.5)

func root_mouse(button: MouseButton,pressed: bool,point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed;event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed and button==MOUSE_BUTTON_LEFT else 0
	host.get_viewport().push_input(event,true)

func click_root(point: Vector2) -> void:
	var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;host.get_viewport().push_input(move,true)
	await get_tree().process_frame
	root_mouse(MOUSE_BUTTON_LEFT,true,point)
	await get_tree().process_frame
	root_mouse(MOUSE_BUTTON_LEFT,false,point)

func send_key(key: Key) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=pressed;host.get_viewport().push_input(event,true)
		await get_tree().process_frame

func drive_input(battle: Node,begin: bool) -> void:
	var p: Vector2=battle.battle_controls.center_stick()
	if begin:
		root_mouse(MOUSE_BUTTON_LEFT,true,p)
		await get_tree().process_frame
		var event:=InputEventMouseMotion.new();event.relative=Vector2(0,-70);event.position=p+event.relative;event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT;host.get_viewport().push_input(event,true)
	else:root_mouse(MOUSE_BUTTON_LEFT,false,p+Vector2(0,-70))

func _process(delta: float) -> void:
	clock+=delta
	if phase==0:
		if clock<2:
			host.globe.set_military(false);text("WWO原全球地理 · 行政参考与军事观察共享底图")
			if clock>.5:mark("earth_admin")
		elif clock<5:
			host.globe.set_military(true)
			if not marks.has("drag_started"):
				marks["drag_started"]=true;dragging=true
				host.input_observations["drag_orientation_before"]=str(host.globe.controller.orientation())
				mouse_button(MOUSE_BUTTON_LEFT,true,drag_pixel)
			if clock<4.5:
				var relative:=Vector2(120*delta,0);drag_pixel+=relative
				var event:=InputEventMouseMotion.new();event.relative=relative;event.position=drag_pixel+host.globe.position;event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT
				host.get_viewport().push_input(event,true)
			elif dragging:
				mouse_button(MOUSE_BUTTON_LEFT,false,drag_pixel);dragging=false
				host.input_observations["drag_orientation_after"]=str(host.globe.controller.orientation());mark("earth_rotated")
			text("球面旋转观察。全球范围没有50公里上限。")
		elif clock<7:
			if not marks.has("earth_military"):
				host.globe.whole_earth();mark("earth_military")
			text("选用已有place:paris坐标；局部为明确标注的训练放置")
		elif clock<9:
			if not marks.has("country_reference"):
				host.globe.focus_training(false);mark("country_reference")
			if clock>7.5 and not marks.has("wheel_up"):
				marks["wheel_up"]=true
				host.input_observations["wheel_before_km_per_pixel"]=host.globe.controller.region_camera.km_per_pixel
				wheel(MOUSE_BUTTON_WHEEL_UP)
				host.input_observations["wheel_after_km_per_pixel"]=host.globe.controller.region_camera.km_per_pixel
			if clock>8.2 and not marks.has("wheel_down"):
				marks["wheel_down"]=true;wheel(MOUSE_BUTTON_WHEEL_DOWN)
				host.input_observations["wheel_return_km_per_pixel"]=host.globe.controller.region_camera.km_per_pixel
		elif clock<12:
			if not marks.has("selected_50km"):
				host.globe.focus_training(true)
				# Real pointer selection of the projected footprint.
				click_map(host.globe.project(host.globe.anchor_frame.z))
				host.input_observations["footprint_selected_by_pointer"]=host.globe.selected
				mark("selected_50km")
			text("50公里训练足迹有明确经纬度；地形尚未真实配准")
		else:
			click_root(host.enter_button.get_global_rect().get_center());phase=1;clock=0
	elif phase==1:
		if host.mode=="local":phase=2;clock=0
		elif clock>15 or clock>5 and not host.loading:
			mark("enter_input_unhandled");host.save_observations();push_error("点击进入未完成");get_tree().quit(1)
	elif phase==2:
		var nav: Control=host.local_shell.navigation
		var battle: Node=host.local_shell.battle
		if clock<3:
			text("进入既有50公里连续地形。原车、原车组继续模拟。")
			if clock>1:mark("local_50km")
		elif clock<7:
			nav.set_range(exp(lerpf(log(50000),log(25000),smoothstep(3,7,clock))))
		elif clock<9:
			nav.set_range(25000);text("同一局部视口 · 25公里")
			if clock>8:mark("local_25km")
		elif clock<13:
			nav.set_range(exp(lerpf(log(25000),log(5000),smoothstep(9,13,clock))))
		elif clock<15:
			nav.set_range(5000);text("同一局部视口 · 可驾驶的Ridgevale原5公里")
			if clock>14:mark("local_5km")
		elif clock<21:
			nav.set_range(exp(lerpf(log(5000),log(14),smoothstep(15,21,clock))))
		elif clock<24:
			nav.set_range(14)
			if not marks.has("drive_input_started"):
				marks["drive_input_started"]=true;drive_input(battle,true)
			if clock>23 and not marks.has("drive_input_released"):
				marks["drive_input_released"]=true;drive_input(battle,false)
			if clock>23.2 and not fired:
				var p: Vector2=battle.battle_controls.center_fire();click_root(p);fired=true
			text("原车长驾驶并真实开炮，弹药只由原模块扣除")
		elif clock<26.5:
			battle.battle_controls.drive=Vector2.ZERO;text("原人物、伤情和事件保留。准备返回球面。")
			if clock>25:mark("vehicle_after_action")
		else:
			send_key(KEY_TAB);phase=3;clock=0
	elif phase==3:
		if clock>.2 and host.mode!="global":
			mark("return_key_unhandled");host.save_observations();push_error("Tab返回未完成");get_tree().quit(1);return
		text("回到原球面锚点。局部模拟继续，装备与战果不刷新。")
		host.input_observations["return_via_tab_mode"]=host.mode
		if clock>.2:mark("globe_returned")
		if clock>3.5:mark("globe_waited")
		if clock>4:
			click_root(host.enter_button.get_global_rect().get_center());phase=4;clock=0
	elif phase==4:
		if clock>.2 and host.mode!="local":
			mark("reenter_input_unhandled");host.save_observations();push_error("再次进入未完成");get_tree().quit(1);return
		var battle: Node=host.local_shell.battle
		text("从同一球面区域再进入，继续原人物与原车")
		if clock>1:mark("same_vehicle_reentered")
		if clock>4 and not walking:
			print("GLOBE_TOUR_DISEMBARK "+JSON.stringify(battle.crew_host.disembark_person(battle.crew_host.commander_person_id())));walking=true
		if clock>5 and not marks.has("walk_input_started"):
			marks["walk_input_started"]=true;drive_input(battle,true)
		if clock>6.2 and not marks.has("walk_input_released"):
			marks["walk_input_released"]=true;drive_input(battle,false)
		if clock>7 and not boarded:
			print("GLOBE_TOUR_BOARD "+JSON.stringify(battle.player_infantry_controller.request_board()));boarded=true
		if clock>9:mark("crew_returned")
		if clock>11 and not marks.has("return_button_sent"):
			marks["return_button_sent"]=true
			click_root(host.local_shell.globe_button.get_global_rect().get_center());phase=5;clock=0
	elif phase==5:
		if clock>.2 and host.mode!="global":
			mark("return_button_unhandled");host.save_observations();push_error("按钮返回未完成");get_tree().quit(1);return
		text("同一球面、同一训练区域、同一局部状态")
		host.input_observations["return_via_button_mode"]=host.mode
		if clock>1:mark("globe_final_state")
		if clock>3:
			host.globe.whole_earth();mark("earth_final")
		if clock>5:
			host.record("finished");host.save_observations();print("GLOBE_LOCAL_TOUR_FINISHED");get_tree().quit()
