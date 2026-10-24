extends FormalWorldApplication
## Uses the current mainline scene, UI, economy, map and installed world owners.
const Scenario = preload("res://practice/scenario.gd")
var practice: Node3D
var entry_layer: CanvasLayer
var entry_button: Button
var previous_paused:=true
var practice_mode:=""
var duty_mode:=""
var duty_button: Button
var is_duty:=false
var duty_cycles:=0
var compatibility_mode:=""
var source_path:=""
var opened:=false
var origin:="CURRENT_MAINLINE_NEW_WORLD"
var installed_tick:=0
var application_start:=Time.get_ticks_msec()
var previous_background_visible:=true
var previous_map_process_mode:=Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--duty-tour="):duty_mode=arg.trim_prefix("--duty-tour=")
		if arg.begins_with("--practice-tour="):practice_mode=arg.trim_prefix("--practice-tour=")
		if arg.begins_with("--compat-tour="):compatibility_mode=arg.trim_prefix("--compat-tour=")
		if arg.begins_with("--compat-source="):source_path=arg.trim_prefix("--compat-source=")
		if arg.begins_with("--practice-source="):source_path=arg.trim_prefix("--practice-source=")
	var bundle_path:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--practice-bundle="):bundle_path=arg.trim_prefix("--practice-bundle=")
	var built: WorldBuildResult
	if not bundle_path.is_empty():
		var recovered: Dictionary=load("res://practice/recovery.gd").read_portable(bundle_path)
		if not recovered.get("ok",false):push_error("PORTABLE_IMPORT_REFUSED "+str(recovered.get("reason")));get_tree().quit(1);return
		built=recovered.built;origin="EXPLICIT_PORTABLE_IMPORT"
		var marker: Dictionary=recovered.evidence
		var error:=AtomicJsonFileStore.write_verified(load("res://practice/native_return.gd").path(str(marker.instance_id)),marker,Callable(load("res://practice/native_return.gd"),"verify"),true)
		if not error.is_empty():push_error(error);get_tree().quit(1);return
	elif "--duty-new" in OS.get_cmdline_user_args():built=load("res://duty/scenario.gd").create_new();origin="EXPLICIT_NEW_1900_NONCOMBAT_DUTY"
	elif "--duty-cold" in OS.get_cmdline_user_args():built=FormalPersistence.new().load_from_user(2);origin="DUTY_COLD_SLOT_2"
	elif "--practice-new" in OS.get_cmdline_user_args():built=Scenario.create_new();origin="EXPLICIT_NEW_1900_PRACTICE_WORLD"
	elif "--practice-cold" in OS.get_cmdline_user_args():built=FormalPersistence.new().load_from_user(3);origin="PRACTICE_COLD_SLOT_3"
	elif not source_path.is_empty():built=FormalPersistence.new()._restore_snapshot_file(source_path);origin="PRACTICE_EXPLICIT_SOURCE_COPY" if not practice_mode.is_empty() else "CURRENT_MAINLINE_READ_V6_COPY"
	elif compatibility_mode=="cold":built=FormalPersistence.new().load_from_user(4);origin="CURRENT_MAINLINE_COLD_SLOT_4"
	if built!=null:
		if not built.success:push_error("CURRENT_MAINLINE_PREPARED_WORLD_FAILED "+built.error);get_tree().quit(1);return
		if "--duty-commission" in OS.get_cmdline_user_args():
			built=load("res://duty/scenario.gd").commission(built)
			if not built.success:push_error("EXPLICIT_DUTY_CHARTER_REFUSED "+built.error);get_tree().quit(1);return
			origin="EXPLICIT_USER_DUTY_CHARTER_ON_RESTORED_WORLD"
		get_tree().set_meta(FormalWorldMenu.PREPARED_WORLD_META,built)
		get_tree().set_meta(LAUNCH_MODE_META,"prepared_new" if origin in ["EXPLICIT_NEW_1900_PRACTICE_WORLD","EXPLICIT_NEW_1900_NONCOMBAT_DUTY"] else "prepared_load")
	super._ready()

func _install_world(value: WorldBuildResult, focus_opening: bool=false) -> bool:
	if not super._install_world(value,focus_opening):return false
	installed_tick=Time.get_ticks_msec()
	entry_layer=CanvasLayer.new();entry_layer.layer=200;add_child(entry_layer)
	entry_button=Button.new();entry_button.position=Vector2(1005,151);entry_button.size=Vector2(255,37);entry_button.text="正式来源步枪 · 1900虚构试射场";entry_button.add_theme_font_override("font",load("res://cedar/system_font.tres"));entry_button.add_theme_font_size_override("font_size",16);entry_layer.add_child(entry_button);entry_button.pressed.connect(open_practice)
	entry_button.disabled=_persistence._save_metadata.get("military_scenario",{}).get("practice_area",{}).is_empty()
	if entry_button.disabled:entry_button.text="试射资格未配置（当前保存）"
	print("CURRENT_MAINLINE_INSTALLED "+JSON.stringify({"pid":OS.get_process_id(),"origin":origin,"world_instance":_world.get_instance_id(),"person_id":_world.player_state.player_id(),"military_schema":_world.military_state.snapshot().schema_id,"material_schema":_world.military_state.material_registry.get("schema","UNKNOWN_UNMODELED"),"install_ms":installed_tick-application_start,"entry_qualified":not entry_button.disabled}))
	duty_button=Button.new();duty_button.position=Vector2(1005,193);duty_button.size=Vector2(255,37);duty_button.text="具名非战斗分队 · 虚构勤务区";duty_button.add_theme_font_override("font",load("res://cedar/system_font.tres"));duty_button.add_theme_font_size_override("font_size",16);entry_layer.add_child(duty_button);duty_button.pressed.connect(open_duty);duty_button.disabled=_world.military_state.duty_operations.is_empty()
	return true

func _process(_delta: float) -> void:
	if _world==null or opened:return
	if DisplayServer.get_name()!="headless" and map_renderer.current_view_map_status().get("state")!="installed":
		if Time.get_ticks_msec()-installed_tick>60000:push_error("CURRENT_MAINLINE_MAP_INSTALL_TIMEOUT");get_tree().quit(1)
		return
	if Time.get_ticks_msec()-installed_tick<1200:return
	if not compatibility_mode.is_empty():opened=true;finish_compatibility.call_deferred()
	elif not duty_mode.is_empty():opened=true;open_duty()
	elif not practice_mode.is_empty():opened=true;open_practice()

func world_time_available_with_practice() -> bool:
	return practice==null and _persistence.world_time_available()

func open_practice() -> void:
	if practice!=null or _world==null or entry_button.disabled or _world.military_state.has_projection_lease() or not _world.military_state.duty_operations.get("active","").is_empty():return
	previous_paused=time_control.paused;time_control.paused=true
	previous_background_visible=($Background as CanvasItem).visible;($Background as CanvasItem).hide()
	previous_map_process_mode=map_controller.process_mode;map_controller.process_mode=Node.PROCESS_MODE_DISABLED
	map_controller.suspend_motion();main_shell.hide();main_shell.process_mode=Node.PROCESS_MODE_DISABLED;map_renderer.hide();entry_layer.hide()
	practice=load("res://practice/main.tscn").instantiate();practice.world=_world;practice.simulation=_simulation_step;practice.persistence=_persistence;practice.closed.connect(close_practice)
	practice.entry_performance={"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"render_total_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"render_texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
	_simulation_step.local_operation_guard=Callable(self,"world_time_available_with_practice")
	add_child(practice)
	print("PRACTICE_SAME_OWNERS "+JSON.stringify({"world_same":practice.world==_world,"step_same":practice.simulation==_simulation_step,"persistence_same":practice.persistence==_persistence,"person_id":_world.player_state.player_id()}))

func close_practice() -> void:
	if practice==null:return
	var duty_before: Dictionary=_persistence.snapshot() if is_duty else {}
	var old: Node3D=practice;practice=null;remove_child(old);old.queue_free()
	_simulation_step.local_operation_guard=Callable(_persistence,"world_time_available")
	main_shell.process_mode=Node.PROCESS_MODE_INHERIT;main_shell.show();map_renderer.show();entry_layer.show();time_control.paused=previous_paused
	($Background as CanvasItem).visible=previous_background_visible
	map_controller.process_mode=previous_map_process_mode
	_on_world_changed({"military":true});_save_dirty=false
	if is_duty:
		duty_cycles+=1
		print("DUTY_VIEW_HANDOFF "+JSON.stringify({"cycle":duty_cycles,"snapshot_exact":duty_before==_persistence.snapshot(),"world_id":_world.get_instance_id(),"step_id":_simulation_step.get_instance_id(),"persistence_id":_persistence.get_instance_id(),"minute":_world.game_clock.total_minutes()}))
		is_duty=false
	print("PRACTICE_RETURNED_TO_CURRENT_MAINLINE pid="+str(OS.get_process_id()))
	if not practice_mode.is_empty() or not duty_mode.is_empty():finish_practice_tour.call_deferred()

func finish_practice_tour() -> void:
	for i: int in 45:await get_tree().process_frame
	if DisplayServer.get_name()!="headless":
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--capture-dir="):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=")+"/returned_mainline.png")
	if duty_mode=="cycle" and duty_cycles<2:
		open_duty();return
	print("FORMAL_EQUIPMENT_PRACTICE_TOUR_FINISHED "+practice_mode+" pid="+str(OS.get_process_id()))
	get_tree().quit()

func finish_compatibility() -> void:
	var before:=_world.military_state.snapshot().duplicate(true)
	var saved: SaveOperationResult=await _persistence.save_to_user_async(4)
	var result: Dictionary={"pid":OS.get_process_id(),"origin":origin,"project":ProjectSettings.globalize_path("res://"),"mode":compatibility_mode,"actual_mainline_scene":scene_file_path,"actual_application_base":"FormalWorldApplication","world_schema":FormalPersistence.SCHEMA_ID,"military_schema":before.schema_id,"material_schema":before.get("material_registry",{}).get("schema","UNKNOWN_UNMODELED"),"person_id":_world.player_state.player_id(),"appointments":_world.organization_state.appointments_for_person(_world.player_state.player_id()),"material_unchanged_by_entry_and_save":before==_world.military_state.snapshot(),"saved":saved.success,"save_message":saved.message,"save_costs":_persistence.last_save_costs,"map_status":map_renderer.current_view_map_status(),"source":source_path,"source_not_modified":true,"minute":_world.game_clock.total_minutes(),"material_counts":before.get("material_registry",{}).get("view",{}).get("lot",{})}
	var path:="user://mainline_application_"+compatibility_mode+".json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--compat-output="):path=arg.trim_prefix("--compat-output=")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("CURRENT_MAINLINE_V6_APPLICATION_FINISHED "+JSON.stringify({"mode":compatibility_mode,"saved":saved.success,"material_unchanged":result.material_unchanged_by_entry_and_save,"map_state":result.map_status.get("state")}))
	get_tree().quit(0 if saved.success and result.material_unchanged_by_entry_and_save else 1)

func _request_departure(target: String) -> void:
	if practice!=null:
		if practice.busy or practice.unsaved:return
		if is_duty:practice.leave()
		else:practice.action("leave")
		return
	super._request_departure(target)


func open_duty() -> void:
	if practice!=null or _world==null or duty_button.disabled or _persistence.is_save_in_progress() or _world.military_state.has_projection_lease():return
	if not _world.military_state.local_operations.get("active",{}).is_empty():return
	for lease: Dictionary in _world.military_state.material_registry.get("view",{}).get("leases",{}).values():
		if lease.status in ["reserved","issued"]:return
	is_duty=true
	previous_paused=time_control.paused;time_control.paused=true
	previous_background_visible=($Background as CanvasItem).visible;($Background as CanvasItem).hide()
	previous_map_process_mode=map_controller.process_mode;map_controller.process_mode=Node.PROCESS_MODE_DISABLED
	map_controller.suspend_motion();main_shell.hide();main_shell.process_mode=Node.PROCESS_MODE_DISABLED;map_renderer.hide();entry_layer.hide()
	practice=load("res://duty/main.tscn").instantiate();practice.world=_world;practice.simulation=_simulation_step;practice.persistence=_persistence;practice.closed.connect(close_practice)
	add_child(practice)
	print("DUTY_SAME_OWNERS "+JSON.stringify({"world_same":practice.world==_world,"step_same":practice.simulation==_simulation_step,"persistence_same":practice.persistence==_persistence,"minute":_world.game_clock.total_minutes()}))
