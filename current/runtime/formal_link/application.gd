extends FormalWorldApplication
## Isolated original product scene. Military receives the installed owners.
var military_host: Node
var entry_layer: CanvasLayer
var entry_button: Button
var previous_paused := true
var demo_mode := ""
var demo_clock := 0.0
var demo_opened := false
var demo_finished := false
var map_wait_seconds := 0.0
var application_rows: Array[Dictionary]=[]
var source_restore_ms := 0
var application_origin := "FORMAL_NEW_WORLD"
var capture_path := "user://formal_application_captures"

func _enter_tree() -> void:
	super._enter_tree()
	if "--background-record" in OS.get_cmdline_user_args():
		get_window().unfocusable=true;get_window().position=Vector2i(6000,6000)

func _ready() -> void:
	var source_save := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--formal-source-save="):source_save=arg.trim_prefix("--formal-source-save=")
		if arg.begins_with("--formal-tour="):demo_mode=arg.trim_prefix("--formal-tour=")
		if arg.begins_with("--capture-dir="):capture_path=arg.trim_prefix("--capture-dir=")
	var restored: WorldBuildResult
	var begin:=Time.get_ticks_msec()
	if not source_save.is_empty():
		restored=FormalPersistence.new()._restore_snapshot_file(source_save);application_origin="FORMAL_SAVE_COPY"
	elif not FormalPersistence.existing_slot_path(1).is_empty() and "--formal-new" not in OS.get_cmdline_user_args():
		restored=FormalPersistence.new().load_from_user(1);application_origin="FORMAL_ISOLATED_RESTART"
	if restored!=null:
		if not restored.success:push_error(restored.error);get_tree().quit(1);return
		get_tree().set_meta(FormalWorldMenu.PREPARED_WORLD_META,restored)
		get_tree().set_meta(LAUNCH_MODE_META,"prepared_load")
	source_restore_ms=Time.get_ticks_msec()-begin
	super._ready()
	if not demo_mode.is_empty():
		Input.use_accumulated_input=false;get_viewport().notify_mouse_entered()
		get_viewport().set_meta("replay_mouse_entered",true)

func _install_world(value: WorldBuildResult,focus_opening: bool=false) -> bool:
	if not super._install_world(value,focus_opening):return false
	if entry_layer==null:
		entry_layer=CanvasLayer.new();entry_layer.layer=200;add_child(entry_layer)
		entry_button=Button.new();entry_button.position=Vector2(1040,154);entry_button.size=Vector2(220,36);entry_button.text="军事训练地图（隔离接入）";entry_layer.add_child(entry_button)
		entry_button.add_theme_font_override("font",load("res://cedar/system_font.tres"));entry_button.add_theme_font_size_override("font_size",16)
		entry_button.pressed.connect(open_military)
	app_record("formal_application_installed")
	return true

func open_military() -> void:
	if _world==null or military_host!=null:return
	previous_paused=time_control.paused;time_control.paused=true
	map_controller.suspend_motion();main_shell.hide();main_shell.process_mode=Node.PROCESS_MODE_DISABLED
	map_renderer.hide();entry_layer.visible=false
	military_host=load("res://formal_link/main.tscn").instantiate()
	military_host.world=_world;military_host.simulation=_simulation_step;military_host.persistence=_persistence;military_host.formal_application=self
	military_host.formal_closed.connect(close_military)
	add_child(military_host)
	app_record("live_owners_passed_to_military")
	var row: Dictionary=application_rows.back()
	var info: Dictionary={}
	for key: String in ["pid","application_instance","world_instance","persistence_instance","world_person_id","place_id","world_minute","injected_same_world","injected_same_step","injected_same_persistence"]:info[key]=row[key]
	print("FORMAL_APPLICATION_MILITARY_OPEN "+JSON.stringify(info))

func close_military() -> void:
	if military_host==null:return
	app_record("same_application_world_returned")
	var already_saved: bool=military_host.current_world_saved
	var old: Node=military_host
	military_host=null;remove_child(old);old.queue_free()
	main_shell.process_mode=Node.PROCESS_MODE_INHERIT;main_shell.show();map_renderer.show();entry_layer.visible=true
	time_control.paused=previous_paused
	_on_world_changed({"time":true,"military":true})
	if already_saved:_save_dirty=false
	write_application_rows()
	if not demo_mode.is_empty():finish_demo.call_deferred()

func _process(delta: float) -> void:
	if demo_mode.is_empty() or demo_opened or _world==null:return
	if DisplayServer.get_name()!="headless" and map_renderer.current_view_map_status().get("state")!="installed":
		map_wait_seconds+=delta
		if map_wait_seconds>45:push_error("原正式地图未完成安装");get_tree().quit(1)
		return
	demo_clock+=delta
	if demo_clock>2 and not demo_finished:
		demo_finished=true;capture_application("original_formal_interface")
	if demo_clock>4:
		demo_opened=true;click_entry()

func click_entry() -> void:
	var at:=entry_button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;get_viewport().push_input(motion,true)
	await get_tree().process_frame
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=at;event.global_position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;get_viewport().push_input(event,true)
		await get_tree().process_frame

func finish_demo() -> void:
	if DisplayServer.get_name()!="headless":
		for i: int in 1350:
			if map_renderer.current_view_map_status().get("state")=="installed":break
			await get_tree().process_frame
		if map_renderer.current_view_map_status().get("state")!="installed":push_error("返回后的原正式地图未完成安装");get_tree().quit(1);return
	for i: int in 45:await get_tree().process_frame
	capture_application("returned_original_formal_interface")
	app_record("formal_application_demo_finished");write_application_rows()
	print("FORMAL_APPLICATION_TOUR_FINISHED "+demo_mode)
	for i: int in 35:await get_tree().process_frame
	get_tree().quit()

func capture_application(stage: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var directory:=ProjectSettings.globalize_path(capture_path);DirAccess.make_dir_recursive_absolute(directory)
	get_viewport().get_texture().get_image().save_png(directory+"/"+stage+".png")

func app_record(stage: String) -> void:
	if _world==null:return
	var person_id:=_world.player_state.player_id()
	application_rows.append({"stage":stage,"pid":OS.get_process_id(),"application_instance":get_instance_id(),"world_instance":str(_world.get_instance_id()),"persistence_instance":str(_persistence.get_instance_id()),"world_person_id":person_id,"place_id":_world.person_overlay.current_place(person_id),"world_minute":_world.game_clock.total_minutes(),"source_restore_ms":source_restore_ms,"military_state":_world.military_state.local_operations.duplicate(true),"injected_same_world":military_host.world==_world if military_host!=null else null,"injected_same_step":military_host.simulation==_simulation_step if military_host!=null else null,"injected_same_persistence":military_host.persistence==_persistence if military_host!=null else null})
	if application_rows.size()>32:application_rows.pop_front()

func write_application_rows() -> void:
	var file:=FileAccess.open("user://formal_application_%s.json"%demo_mode,FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"ORIGINAL_FORMAL_WORLD_APPLICATION_ISOLATED_SUBCLASS","application_origin":application_origin,"rows":application_rows},"\t"))



func _request_departure(target: String) -> void:
	if military_host!=null and military_host.saving:
		military_host.formal_status_text="请等待原正式保存完成后退出"
		while is_instance_valid(military_host) and military_host.saving:await get_tree().process_frame
	if military_host!=null and military_host.unsaved_commit:
		military_host.formal_status_text="已采用的结果尚未保存；请重试正式保存后退出";return
	if military_host!=null and (military_host.session.state().active as Dictionary).is_empty():close_military()
	super._request_departure(target)
