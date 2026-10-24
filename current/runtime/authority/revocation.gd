extends SceneTree
const Service=preload("res://scripts/vnext/military/military_combat_authority_service.gd")
const Recovery=preload("res://practice/recovery.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var source:="";var report:="";var mode:="write"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
	var read:=Recovery.read_portable(source)
	if not read.get("ok",false):push_error(str(read));quit(1);return
	var b: WorldBuildResult=read.built;var native:=load("res://practice/native_return.gd")
	var marker: Dictionary=read.evidence
	var error:=AtomicJsonFileStore.write_verified(native.path(str(marker.instance_id)),marker,Callable(native,"verify"),true)
	var service:=Service.new();var bound:=service.bind(b.world,b.persistence)
	var m: Dictionary=service.state().mandates.annex_order_001
	var actor:=service.context("operator",m.delegation_id)
	var history: Dictionary=m.acceptance.duplicate(true)
	var revoked: Dictionary=service.revoke_mandate(m.id,service.command_context()) if mode=="write" else {"ok":true}
	var before:=b.persistence.snapshot()
	var denied:=service.authorize(m.id,actor)
	var refused:=service.accept(m.id,actor)
	var exact: bool=before==b.persistence.snapshot() and m.acceptance==history
	var saved:=b.persistence.save_to_user(3)
	var export_error:=Recovery.export_portable(report.trim_suffix(".json")+"_portable.json",b.persistence)
	var ok: bool=error.is_empty() and bound.is_empty() and revoked.ok and not denied.ok and not refused.ok and exact and saved.success and export_error.is_empty()
	var result: Dictionary={"pid":OS.get_process_id(),"mode":mode,"passed":ok,"current_permission":denied,"current_acceptance":refused,"history_and_world_exact_after_denial":exact,"delegation":b.world.organization_state.delegation(m.delegation_id),"minute":b.world.game_clock.total_minutes(),"pending_usec":b.world.military_state.duty_operations.pending_usec,"material":b.world.military_state.material_registry.view.lot,"save":ProjectSettings.globalize_path(FormalPersistence.slot_path(3))}
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("FORMAL_AUTHORITY_REVOKED_COLD "+str(ok)+" mode="+mode+" pid="+str(OS.get_process_id()));quit(0 if ok else 1)
