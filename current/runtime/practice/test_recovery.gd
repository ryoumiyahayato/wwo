extends SceneTree
const Recovery = preload("res://practice/recovery.gd")
const Native = preload("res://practice/native_return.gd")
const Service = preload("res://scripts/vnext/military/military_material_service.gd")
const Custody = preload("res://custody/scenario.gd")
var rows: Array=[]
var failures: Array=[]
var task_root:=""

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	rows.append({"case":label,"passed":value})
	if not value:failures.append(label)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):task_root=arg.trim_prefix("--root=")
	var loaded:=Recovery.read_portable(task_root+"/private_state/emitted/portable.json")
	check(loaded.get("ok",false),"actual_emitted_bundle_read")
	if not loaded.get("ok",false):finish();return
	for name: String in ["missing_component","corrupt_receipt","future_bundle","wrong_instance","mismatched_pair","corrupt_world"]:
		check(not Recovery.read_portable(task_root+"/private_state/damaged/"+name+".json").get("ok",false),"portable_"+name+"_refused")
	var built: WorldBuildResult=loaded.built
	var world: WorldState=built.world
	var storage: FormalPersistence=built.persistence
	var native:=Native.decode(loaded.evidence)
	check(Recovery.assess(world,storage,native).get("state")=="EMITTED_UNADOPTED","actual_emitted_unadopted_classified")
	var service:=Service.new();check(service.bind(world,storage),"existing_material_owner_bound")
	check(not service.adopt_use(Custody.context(world,"use"),native.receipt).get("ok",false),"ordinary_use_cannot_replay_old_native_executor")
	var wrong_person:=Custody.context(world,"recover");wrong_person.person_id="person:unknown"
	check(not service.recover_emitted(wrong_person,native).get("ok",false),"wrong_recovery_person_refused")
	var wrong_source:=native.duplicate(true);wrong_source.receipt.physical.asset_id="material:unknown"
	check(not Recovery.assess(world,storage,wrong_source).get("ok",false),"wrong_physical_source_refused")
	var before:=storage.snapshot()
	var conflicting:=native.duplicate(true);conflicting.receipt.before={}
	check(not Recovery.assess(world,storage,conflicting).get("ok",false),"conflicting_native_budget_refused")
	conflicting=native.duplicate(true);conflicting.instance_id="1-2-3"
	check(not Recovery.assess(world,storage,conflicting).get("ok",false),"foreign_instance_refused")
	conflicting=native.duplicate(true);conflicting.qualification={}
	check(not Recovery.assess(world,storage,conflicting).get("ok",false),"action_authority_evidence_required")
	conflicting=native.duplicate(true);conflicting.receipt.physical.endpoint+=Vector3(2,0,0)
	check(not Recovery.assess(world,storage,conflicting).get("ok",false),"corrupt_ray_receipt_refused")
	check(not Recovery.assess(world,storage,{"ok":false,"reason":"MISSING_REQUIRED_EVIDENCE"}).get("ok",false),"missing_evidence_fails_closed")
	check(storage.snapshot()==before,"rejections_do_not_mutate_formal_world")
	check(world.organization_state.revoke_authority("authority.practice_1900.fire",world.game_clock.current_hour()),"actual_authority_revocation_after_event")
	var denied_context:=Custody.context(world,"recover");denied_context.authority_basis="authority.practice_1900.fire"
	check(not service.recover_emitted(denied_context,native).get("ok",false),"shooting_authority_cannot_replace_recovery_authority")
	var result: Dictionary=service.recover_emitted(Custody.context(world,"recover"),native)
	check(result.get("ok",false) and not result.get("replayed_native",true),"past_legal_event_recovers_after_fire_revocation_without_replay")
	check(service.view().lot.consumed==1 and service.view().lot.issued==5,"one_round_adopted_from_original_six")
	var after:=storage.snapshot();var duplicate: Dictionary=service.recover_emitted(Custody.context(world,"recover"),native)
	check(duplicate.get("duplicate",false) and storage.snapshot()==after,"repeat_recovery_no_second_debit")
	var conflict:=native.duplicate(true);conflict.receipt.physical.endpoint+=Vector3(1,0,0)
	check(not service.recover_emitted(Custody.context(world,"recover"),conflict).get("ok",false) and storage.snapshot()==after,"same_id_conflicting_receipt_refused_without_mutation")
	check(storage._save_metadata.get("practice_recovery_audit",[]).size()==1,"one_formal_recovery_audit")
	var prepared:=Recovery.read_portable(task_root+"/private_state/prepared/portable.json")
	check(prepared.get("ok",false) and prepared.assessment.state=="UNCERTAIN","actual_prepared_bundle_remains_uncertain")
	var covered:=Recovery.read_portable(task_root+"/private_state/covered/portable.json")
	check(covered.get("ok",false) and covered.assessment.state=="ALREADY_ADOPTED","actual_durable_formal_event_does_not_need_another_debit")
	check(not Native.decode({"schema":"practice_native_return_v999"}).get("ok",false),"future_evidence_schema_refused")
	storage._save_metadata.practice_recovery_protocol="future_v999"
	check(not Recovery.assess(world,storage,native).get("ok",false),"future_recovery_protocol_refused")
	finish()

func finish() -> void:
	FileAccess.open(task_root+"/run/recovery_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"source":"ACTUAL_TERMINATED_ENGINE_RECEIPTS_WITH_CONTROLLED_READ_ONLY_COPY_CHECKS","rows":rows,"failures":failures},"\t"))
	print("RECOVERY_CHECKS_FINISHED "+JSON.stringify({"cases":rows.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
