extends "res://practice/application.gd"
var delegation_tour:=""
var delegation_button: Button
var is_delegation:=false
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--delegation-tour="):delegation_tour=arg.trim_prefix("--delegation-tour=")
	super._ready()
func _install_world(value: WorldBuildResult,focus_opening: bool=false) -> bool:
	if not super._install_world(value,focus_opening):return false
	delegation_button=Button.new();delegation_button.position=Vector2(1005,235);delegation_button.size=Vector2(255,37);delegation_button.text="局部委派 · 资格与投影责任";delegation_button.add_theme_font_override("font",load("res://cedar/system_font.tres"));entry_layer.add_child(delegation_button);delegation_button.pressed.connect(open_delegation)
	delegation_button.disabled=_world.military_state.duty_operations.is_empty()
	return true
func _process(delta: float) -> void:
	super._process(delta)
	if _world==null or opened or delegation_tour.is_empty():return
	if DisplayServer.get_name()!="headless" and map_renderer.current_view_map_status().get("state")!="installed":return
	if Time.get_ticks_msec()-installed_tick<1200:return
	opened=true;open_delegation()
func open_delegation() -> void:
	if practice!=null or _world==null or delegation_button.disabled or _persistence.is_save_in_progress():return
	if not _world.military_state.duty_operations.active.is_empty() or not _world.military_state.local_operations.get("active",{}).is_empty():return
	is_delegation=true
	previous_paused=time_control.paused;time_control.paused=true
	previous_background_visible=($Background as CanvasItem).visible;($Background as CanvasItem).hide()
	previous_map_process_mode=map_controller.process_mode;map_controller.process_mode=Node.PROCESS_MODE_DISABLED
	map_controller.suspend_motion();main_shell.hide();main_shell.process_mode=Node.PROCESS_MODE_DISABLED;map_renderer.hide();entry_layer.hide()
	practice=load("res://delegation/view.gd").new();practice.world=_world;practice.persistence=_persistence;practice.simulation=_simulation_step;practice.tour=delegation_tour;practice.closed.connect(close_practice)
	_simulation_step.local_operation_guard=Callable(self,"world_time_available_with_practice")
	add_child(practice)
	print("DELEGATION_SAME_OWNERS "+JSON.stringify({"world":_world.get_instance_id(),"step":_simulation_step.get_instance_id(),"persistence":_persistence.get_instance_id(),"same":practice.world==_world and practice.persistence==_persistence and practice.simulation==_simulation_step}))
func close_practice() -> void:
	var closing:=is_delegation;var before: Dictionary=_persistence.snapshot() if closing else {}
	super.close_practice()
	if closing:
		is_delegation=false
		var exact:=before==_persistence.snapshot()
		print("DELEGATION_GLOBAL_HANDOFF exact="+str(exact)+" minute="+str(_world.game_clock.total_minutes()))
		if not delegation_tour.is_empty():get_tree().quit(0 if exact else 1)
func _request_departure(target: String) -> void:
	if is_delegation:
		if practice!=null:practice.leave()
		return
	super._request_departure(target)
