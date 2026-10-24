extends "res://practice/application.gd"
const Command=preload("res://scripts/vnext/military/military_combat_authority_service.gd")
const AuthorityState=preload("res://scripts/vnext/military/military_combat_authority_state.gd")
var authority_tour:=""
var authority_output:="user://authority_native.json"
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--authority-tour="):authority_tour=arg.trim_prefix("--authority-tour=")
		if arg.begins_with("--authority-output="):authority_output=arg.trim_prefix("--authority-output=")
	super._ready()
func _process(delta: float) -> void:
	super._process(delta)
	if _world==null or opened or authority_tour.is_empty():return
	if DisplayServer.get_name()!="headless" and map_renderer.current_view_map_status().get("state")!="installed":return
	if Time.get_ticks_msec()-installed_tick<1200:return
	opened=true;run_authority.call_deferred()
func run_authority() -> void:
	time_control.paused=true
	var service:=Command.new();var binding:=service.bind(_world,_persistence)
	if not binding.is_empty():push_error(binding);get_tree().quit(1);return
	var original:=_persistence.snapshot();var results: Dictionary={}
	results.commission=service.commission()
	if not results.commission.ok:push_error(str(results));get_tree().quit(1);return
	results.delegate=service.delegate("annex_order_001",service.context("commander"),2,3)
	if not results.delegate.ok:push_error(str(results));get_tree().quit(1);return
	var m: Dictionary=service.state().mandates.annex_order_001
	var actor:=service.context("operator",m.delegation_id)
	results.accept=service.accept(m.id,actor)
	results.admission=service.execution_admission(m.id,actor)
	if not results.accept.ok or results.admission.ok:push_error(str(results));get_tree().quit(1);return
	var request_service: RefCounted=load("res://scripts/vnext/military/military_delegation_service.gd").new()
	request_service.bind(_world,_persistence)
	var d: Dictionary=service.state()
	var q: Dictionary={"id":"delegation_request:qualified_001","unit":d.unit,"region":_world.military_state.local_delegation.region.id,"issuer":d.commander,"participants":[d.commander,d.operator],"from_minute":2,"until_minute":3,"settlement_owner":AuthorityState.ORG,"objective":"CONTROLLED_LOCAL_DEFENCE"}
	results.decision=request_service.request_combat(q,service.command_context())
	main_shell.show_feedback("具名资格与委派链已生效；执行人已接令。正式combat仍缺身体医疗、区域、军备指派和执行契约。")
	var saved: SaveOperationResult=await _persistence.save_to_user_async(2)
	results.saved=saved.success
	var export_error: String=load("res://practice/recovery.gd").export_portable(authority_output.trim_suffix(".json")+"_portable.json",_persistence)
	for i: int in 30:await get_tree().process_frame
	if DisplayServer.get_name()!="headless":
		get_viewport().get_texture().get_image().save_png(authority_output.trim_suffix(".json")+".png")
	var before:=original.duplicate(true);var after:=_persistence.snapshot()
	for value: Dictionary in [before,after]:value.erase("military_state");value.erase("organization")
	var result: Dictionary={"pid":OS.get_process_id(),"tour":authority_tour,"results":results,"nonmilitary_world_exact":before==after,"minute":_world.game_clock.total_minutes(),"pending_usec":_world.military_state.duty_operations.pending_usec,"schema":_world.military_state.snapshot().schema_id,"world_id":_world.get_instance_id(),"step_id":_simulation_step.get_instance_id(),"organization_id":_world.organization_state.get_instance_id(),"persistence_id":_persistence.get_instance_id(),"save":ProjectSettings.globalize_path(FormalPersistence.slot_path(2)),"portable_error":export_error,"save_costs":_persistence.last_save_costs.duplicate(true),"engine_static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"snapshot_exact_on_cold":original==_persistence.snapshot() if authority_tour=="cold" else false}
	FileAccess.open(authority_output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("FORMAL_AUTHORITY_NATIVE_FINISHED "+JSON.stringify(result))
	get_tree().quit(0 if saved.success and export_error.is_empty() and before==after else 1)
