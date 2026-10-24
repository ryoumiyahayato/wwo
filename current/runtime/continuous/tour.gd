extends Node
## Continuous engine-recorded walkthrough. It drives the real camera/controller;
## movie-writer frames are not a measurement of real-time FPS.
var shell: Node
var clock := 0.0
var fired := false
var dismounted := false
var boarded := false
var recorded: Dictionary = {}
var board_result: Dictionary = {}
var input_mode := false
var input_results: Dictionary = {}
var pause_time := 0.0
var pan_before := Vector2.ZERO

func _ready() -> void:
	process_priority=2000
	input_mode="--input-tour" in OS.get_cmdline_user_args()
	shell.navigation.caption="原人物、原车。先驾驶，再连续拉远。"

func range_between(t: float,start: float,end: float) -> float:
	return exp(lerpf(log(start),log(end),smoothstep(0,1,t)))

func mark(name: String) -> void:
	if recorded.has(name):return
	recorded[name]=true;shell.record_stage(name)
	shell.capture()

func _process(delta: float) -> void:
	clock+=delta
	if input_mode:
		_input_walkthrough()
		return
	var nav: Control=shell.navigation
	var battle: Node=shell.battle
	if clock<3:
		battle.battle_controls.drive=Vector2(0,-.65) if clock<2.2 else Vector2.ZERO
		if clock<.2:mark("vehicle_start")
	elif clock<5:
		if not fired:
			battle.battle_controls.drive=Vector2.ZERO
			battle.fire_cannon();fired=true
		nav.caption="主炮真实扣弹。缩放期间装填与模拟继续。"
	elif clock<13:
		nav.set_range(range_between((clock-5)/8,14,5000))
		nav.caption="连续拉远至5公里：原地形、道路与村落。"
	elif clock<17:
		nav.set_range(5000)
		if clock>14.5:mark("range_5km")
	elif clock<25:
		nav.set_range(range_between((clock-17)/8,5000,25000))
		nav.caption="同一位置拉远至25公里。外围采用连续概略地形。"
	elif clock<29:
		nav.set_range(25000)
		if clock>26.5:mark("range_25km")
	elif clock<36:
		nav.set_range(range_between((clock-29)/7,25000,50000))
		nav.caption="50公里区域：河谷、山岭、交通与聚落。"
	elif clock<40:
		nav.set_range(50000)
		if clock>37.5:mark("range_50km")
	elif clock<45:
		nav.pan_offset=Vector2(6000,2600)*sin((clock-40)/5*PI)
		nav.caption="同一视口平移。相对地理位置不变。"
	elif clock<56:
		nav.pan_offset=Vector2.ZERO
		nav.set_range(range_between((clock-45)/11,50000,14))
		nav.caption="沿同一空间返回原车。没有重新开局。"
	elif clock<60:
		nav.set_range(14)
		if clock>57.5:mark("returned_vehicle")
		nav.caption="原车长、原车、伤情、弹药与事件保留。"
	elif clock<64:
		if not dismounted:
			var result: Dictionary=battle.crew_host.disembark_person(battle.crew_host.commander_person_id())
			print("TOUR_DISEMBARK "+JSON.stringify(result))
			dismounted=true
		if clock>61 and clock<62.2:battle.battle_controls.drive=Vector2(0,-.4)
		else:battle.battle_controls.drive=Vector2.ZERO
		nav.caption="同一人物下车，接续原生步战移动。"
	elif clock<68:
		if not boarded:
			board_result=battle.player_infantry_controller.request_board()
			print("TOUR_BOARD "+JSON.stringify(board_result));boarded=true
		nav.caption="返回原车。相机尺度没有控制模拟时间。"
		mark("crew_returned")
	else:
		shell.record_stage("tour_finished")
		shell.save_observations("user://tour_observation.json")
		print("CONTINUOUS_TOUR_FINISHED "+JSON.stringify({"seconds":clock,"board_result":board_result,"same_hero":shell.initial.hero_instance==shell.port.snapshot(battle).hero_instance,"shots":battle.shot_audit.size()}))
		get_tree().quit()

func _send_key(key: Key) -> void:
	var event:=InputEventKey.new();event.keycode=key;event.pressed=true
	shell.get_viewport().push_input(event,true)
	var release:=InputEventKey.new();release.keycode=key;release.pressed=false
	shell.get_viewport().push_input(release,true)

func _wheel() -> void:
	var event:=InputEventMouseButton.new();event.position=Vector2(650,360);event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true
	shell.get_viewport().push_input(event,true)

func _input_walkthrough() -> void:
	var nav: Control=shell.navigation
	if clock>1 and not recorded.has("preset_input"):
		_send_key(KEY_1)
		input_results["preset_key_sets_5km"]=is_equal_approx(nav.target_span,5000)
		mark("preset_input")
	if clock>4 and not recorded.has("wheel_input"):
		_wheel();_wheel();_wheel()
		input_results["wheel_changes_continuous_target"]=nav.target_span>10000 and nav.target_span<25000
		mark("wheel_input")
	if clock>6 and not recorded.has("pan_input"):
		pan_before=nav.pan_offset
		var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=Vector2(650,380);shell.get_viewport().push_input(down,true)
		var move:=InputEventMouseMotion.new();move.position=Vector2(530,460);move.relative=Vector2(-120,80);shell.get_viewport().push_input(move,true)
		var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=move.position;shell.get_viewport().push_input(up,true)
		input_results["drag_pans_without_teleport"]=nav.pan_offset.distance_to(pan_before)>100 and shell.initial.position_local[0]==shell.battle.hero.position.x and shell.initial.position_local[2]==shell.battle.hero.position.z
		mark("pan_input")
	if clock>8 and not recorded.has("home_input"):
		_send_key(KEY_HOME)
		input_results["home_returns_view_to_person"]=nav.target_span==14 and nav.pan_offset==Vector2.ZERO
		mark("home_input")
	if clock>10 and not recorded.has("explicit_pause"):
		_send_key(KEY_P);pause_time=shell.battle.elapsed
		input_results["explicit_pause_enabled"]=shell.get_tree().paused
		mark("explicit_pause")
	if clock>11 and not recorded.has("zoom_while_paused"):
		for i: int in 12:_wheel()
		input_results["zoom_does_not_resume_explicit_pause"]=shell.get_tree().paused and is_equal_approx(shell.battle.elapsed,pause_time)
		mark("zoom_while_paused")
	if clock>12 and not recorded.has("resume_input"):
		input_results["explicit_pause_holds_native_time"]=is_equal_approx(shell.battle.elapsed,pause_time)
		_send_key(KEY_P)
		mark("resume_input")
	if clock>15:
		input_results["time_resumes_only_by_request"]=not shell.get_tree().paused and shell.battle.elapsed>pause_time+1
		shell.record_stage("input_finished")
		shell.save_observations("user://input_observation.json")
		print("NAVIGATION_INPUT_RESULT "+JSON.stringify(input_results))
		var ok:=true
		for value: bool in input_results.values():ok=ok and value
		shell.get_tree().quit(0 if ok else 1)
