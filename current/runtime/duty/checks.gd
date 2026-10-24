extends SceneTree
const State=preload("res://scripts/vnext/military/military_duty_state.gd")
const Service=preload("res://scripts/vnext/military/military_duty_service.gd")
var rows: Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:rows.append({"case":label,"passed":ok})
func run() -> void:
	var source:="";var output:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	var b:=FormalPersistence.new()._restore_snapshot_file(source)
	check(b.success,"actual_completed_v8_reader")
	if not b.success:push_error(b.error);quit(1);return
	var d: Dictionary=b.world.military_state.duty_operations
	check(State.references_error(b.world).is_empty() and b.world.person_overlay.person_count()==2,"original_claims_and_named_unit_references")
	check(d.orders.size()>=2 and d.orders.values().back().carry_in_usec==d.orders.values()[0].pending_usec,"second_mission_retains_first_fraction")
	for kind: String in ["unknown_schema","unknown_field","missing_report","impossible_pose","time_duplicated","duplicate_receipt","zero_observation_steps","lost_time_fraction"]:
		var x:=d.duplicate(true);var o: Dictionary=x.orders.values().back()
		match kind:
			"unknown_schema":x.schema="formal_noncombat_duties_v999"
			"unknown_field":x.extra=true
			"missing_report":o.report={}
			"impossible_pose":x.position=Vector3(1000,0,0)
			"time_duplicated":o.receipts.back().to_minute+=1
			"duplicate_receipt":o.receipts.append(o.receipts.back().duplicate(true))
			"zero_observation_steps":o.observation.physics_steps=0
			"lost_time_fraction":o.carry_in_usec=0
		check(not State.error(x).is_empty(),kind+"_refused")
	var f:=b.world.military_state.get_formation(d.unit)
	check(f.personnel==0 and f.apply_losses(2)==0 and not f.can_receive_orders(),"named_members_cannot_enter_aggregate_battle_or_losses")
	var clone:=VNextMilitaryFormation.new();var duplicate_data:=f.to_dict();duplicate_data.formation_id="formation:duplicate_named_unit"
	check(clone.restore(duplicate_data) and not b.world.military_state.add_formation(clone),"same_person_cannot_join_second_named_unit")
	var person: String=d.executor;var claim: String=f.named_personnel.members[person].claim_id
	f.named_personnel.members[person].claim_id="formal_population_claim:wrong"
	check(not State.references_error(b.world).is_empty(),"claim_substitution_refused")
	f.named_personnel.members[person].claim_id=claim
	var node:=Node3D.new();get_root().add_child(node)
	var service:=Service.new();check(service.bind(b.world,b.simulation_step,b.persistence,node).is_empty(),"existing_original_owners_bound")
	var before:=b.persistence.snapshot();var receipt: Dictionary=d.orders.values().back().receipts.back().duplicate(true)
	var adopted:=service.checkpoint(node,receipt)
	check(adopted.get("duplicate",false) and b.persistence.snapshot()==before,"cold_duplicate_is_exact_noop_for_economy_clock_and_people")
	receipt.to_minute+=1
	check(not service.checkpoint(node,receipt).ok and b.persistence.snapshot()==before,"conflicting_historical_receipt_has_no_effect")
	var context: Dictionary=load("res://practice/scenario.gd").context(b.world,"fire")
	check(not service.authorize("issue",context).ok,"shooting_qualification_is_not_duty_command")
	var applied:=LivelihoodAction.execute_current(b.world,"apply",{"job_id":"job:opening_paris_workshop"})
	check(applied.accepted,"original_civilian_contract_can_still_be_accepted")
	before=b.persistence.snapshot()
	check(service.authorize("issue").get("reason")=="CIVILIAN_EMPLOYMENT_CONFLICT" and before==b.persistence.snapshot(),"military_duty_refuses_to_erase_or_overlap_civilian_work")
	var snapshot:=b.persistence.snapshot();snapshot.military_state.schema_id="vnext_military_state_v999"
	check(not b.persistence.restore_candidate(snapshot).success,"unknown_outer_military_version_refused")
	var result: Dictionary={"pid":OS.get_process_id(),"cases":rows,"passed":rows.all(func(x:Dictionary)->bool:return x.passed)}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	node.queue_free();print("FORMAL_DUTY_LOCAL_CHECKS "+str(result.passed)+" "+str(rows.size()));quit(0 if result.passed else 1)
