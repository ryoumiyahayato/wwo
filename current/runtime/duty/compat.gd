extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var report:=""
 for a: String in OS.get_cmdline_user_args():
  if a.begins_with("--report="): report=a.trim_prefix("--report=")
 if "--cold-only" in OS.get_cmdline_user_args():
  var reader:=FormalPersistence.new()
  var decoded:=reader._read_snapshot_file(reader.slot_path(4))
  var restored:=reader.load_from_user(4)
  var cold: Dictionary={"pid":OS.get_process_id(),"mode":"independent_process_cold","accepted":restored.success,"error":restored.error}
  if restored.success:
   cold.snapshot_exact=restored.persistence.snapshot()==decoded.snapshot
   cold.firms=restored.world.economy_r1._spec.firms.size();cold.contracts=restored.world.economy_r1._contracts
   cold.people=restored.world.person_overlay.person_count();cold.military_schema=restored.world.military_state.snapshot().schema_id
  cold.ok=restored.success and cold.get("snapshot_exact",false) and cold.get("firms")==2 and cold.get("people")==2
  FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(cold,"\t"))
  print("LATEST_MAINLINE_INDEPENDENT_COLD "+str(cold.ok));quit(0 if cold.ok else 1);return
 var started:=Time.get_ticks_msec()
 var built: WorldBuildResult=load("res://practice/scenario.gd").create_new()
 if not built.success: push_error(built.error);quit(1);return
 var w: WorldState=built.world
 var military:=w.military_state.snapshot()
 var apply:=LivelihoodAction.execute_current(w,"apply",{"job_id":"job:opening_paris_workshop"})
 var advance: Dictionary=built.simulation_step.advance_minutes(1440)
 var state: Dictionary=built.persistence.snapshot()
 var saved: SaveOperationResult=await built.persistence.save_to_user_async(4)
 var result: Dictionary={"pid":OS.get_process_id(),"mode":"fresh","saved":saved.success,"save_message":saved.message,"apply":apply,"advance":advance,"minute":w.game_clock.total_minutes(),"firms":w.economy_r1._spec.firms,"contracts":w.economy_r1._contracts,"persons":state.persons,"population":state.population,"organization":state.organization,"military_preserved":military==w.military_state.snapshot(),"save_costs":built.persistence.last_save_costs,"total_ms":Time.get_ticks_msec()-started}
 if "--cold" in OS.get_cmdline_user_args():
  var restored:=FormalPersistence.new().load_from_user(4)
  result.cold_success=restored.success;result.cold_error=restored.error
  if restored.success:result.exact_restore=restored.persistence.snapshot()==state
 result.ok=saved.success and apply.accepted and result.military_preserved and w.economy_r1._spec.firms.size()==2 and w.economy_r1._contracts.size()==2 and result.get("exact_restore",true)
 FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print("LATEST_MAINLINE_COMPAT "+str(result.ok))
 quit(0 if result.ok else 1)

