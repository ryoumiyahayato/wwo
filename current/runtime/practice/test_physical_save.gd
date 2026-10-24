extends SceneTree
## Focused checks of the actual practice save; no synthetic firing or full suite.
const MaterialLedger = preload("res://scripts/vnext/military/military_material_state.gd")
const Service = preload("res://scripts/vnext/military/military_material_service.gd")
const Custody = preload("res://custody/scenario.gd")
var rows: Array=[]
var failures: Array=[]
var loaded: WorldBuildResult

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, name_value: String) -> void:
	rows.append({"case":name_value,"passed":value})
	if not value:failures.append(name_value);push_error("PHYSICAL_SAVE_CHECK_FAILED "+name_value)

func rejected(candidate: Dictionary, good: Dictionary, name_value: String) -> void:
	var result:=loaded.persistence.restore_candidate(candidate)
	check(not result.success and loaded.persistence.snapshot()==good,name_value)

func run() -> void:
	var source:="";var report:="user://physical_save_results.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	if source.is_empty():push_error("Explicit practice save source is required");quit(2);return
	loaded=FormalPersistence.new()._restore_snapshot_file(source)
	check(loaded.success,"actual_saved_practice_world_restored")
	if not loaded.success:finish(report);return
	var world:=loaded.world
	var good:=loaded.persistence.snapshot()
	var registry: Dictionary=world.military_state.material_registry
	check(good.military_state.schema_id=="vnext_military_state_v6_material" and registry.schema==MaterialLedger.PHYSICAL_SCHEMA,"explicit_v6_with_v2_physical_registry")
	check(registry.view.lot.available==19 and registry.view.lot.issued==0 and registry.view.lot.consumed==1 and registry.view.lot.lost==0,"actual_twenty_round_source_conserved_after_return")
	check(registry.view.receipts.size()==1,"one_physical_receipt_not_a_second_controlled_consumption")
	var receipt: Dictionary=registry.view.receipts.values()[0]
	check(receipt.physical.hit_id=="practice_target:board_01" and receipt.physical.collision_model=="GODOT_PHYSICS_MUZZLE_RAY","saved_actual_native_target_and_muzzle_ray")
	check(receipt.physical.person_id==world.player_state.player_id() and receipt.physical.asset_id==registry.view.asset.asset_id,"same_formal_person_and_sourced_serial_weapon")
	var service:=Service.new();check(service.bind(world,loaded.persistence),"restored_service_binds_existing_owners")
	var duplicate: Dictionary=service.adopt_use(Custody.context(world,"use"),receipt)
	check(duplicate.get("ok",false) and duplicate.get("duplicate",false) and loaded.persistence.snapshot()==good,"old_receipt_duplicate_does_not_mutate_any_world_state")
	var stale:=receipt.duplicate(true);stale.receipt_id+="-late"
	check(not service.adopt_use(Custody.context(world,"use"),stale).get("ok",false) and loaded.persistence.snapshot()==good,"late_nonidentical_receipt_rejected_after_return_and_restart")
	var candidate:=good.duplicate(true);candidate.military_state.material_registry.view.lot.available+=1
	rejected(candidate,good,"material_projection_inventory_rollback_rejected_atomically")
	candidate=good.duplicate(true);candidate.military_state.erase("material_registry")
	rejected(candidate,good,"v6_cannot_drop_material_registry_field")
	candidate=good.duplicate(true);candidate.military_state.schema_id="vnext_military_state_v999"
	rejected(candidate,good,"unknown_future_military_version_rejected_atomically")
	candidate=good.duplicate(true);candidate.military_state.material_registry.schema="military_material_registry_v999"
	rejected(candidate,good,"unknown_future_material_version_rejected_atomically")
	candidate=good.duplicate(true);candidate.military_state.material_registry.schema=MaterialLedger.SCHEMA
	rejected(candidate,good,"physical_journal_cannot_masquerade_as_material_v1")
	var event_index:= -1
	for index: int in registry.events.size():
		if registry.events[index].payload.has("physical"):event_index=index;break
	check(event_index>=0,"actual_physical_event_present")
	if event_index>=0:
		candidate=good.duplicate(true);candidate.military_state.material_registry.events[event_index].payload.physical.schema="formal_equipment_practice_shot_v999"
		rejected(candidate,good,"unknown_future_physical_shot_contract_rejected")
		candidate=good.duplicate(true);candidate.military_state.material_registry.events[event_index].payload.physical.endpoint+=Vector3(3,0,0)
		rejected(candidate,good,"shot_endpoint_off_muzzle_axis_rejected")
		candidate=good.duplicate(true);candidate.military_state.material_registry.events[event_index].payload.physical.fire_context=Custody.context(world,"use")
		rejected(candidate,good,"custody_context_cannot_replace_shooter_qualification")
	check(loaded.persistence.snapshot()==good,"all_rejected_candidates_leave_installed_world_exact")
	finish(report)

func finish(report: String) -> void:
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"source":"ACTUAL_NATIVE_PRACTICE_SAVE_WITH_READ_ONLY_CORRUPTION_COPIES","pid":OS.get_process_id(),"rows":rows,"failures":failures},"\t"))
	print("PHYSICAL_SAVE_CHECK_FINISHED "+JSON.stringify({"cases":rows.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
