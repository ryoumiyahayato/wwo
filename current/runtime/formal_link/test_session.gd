extends SceneTree
## Requested focused contract cases. Synthetic returns are not native combat evidence.
var rows: Array[Dictionary]=[]
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,name: String) -> void:
	rows.append({"case":name,"passed":value})
	if not value:failures.append(name);push_error("LOCAL_CONTRACT_FAILED "+name)

func make_return(request: Dictionary,seconds: float,fire: bool) -> Dictionary:
	var result:=request.duplicate(true)
	result.return_id=str(request.lease_id)+":return";result.solver_owner="host_pending_commit"
	result.local_elapsed=float(request.local_elapsed)+seconds
	result.absolute_seconds=float(request.absolute_seconds)+seconds
	result.position_local=[-6.0,0.0,5.0]
	result.crew[0].hp=7.0;result.crew[0].parts.left_arm="injured"
	for i: int in 5:result.crew[i].location={"kind":"vehicle","vehicle_id":FormalLocalSession.VEHICLE_ID,"seat_id":str(i)}
	if fire:
		var ammo:=FormalLocalSession.new_ammo()
		ammo.restore(result.native_ammo)
		var commit: Dictionary=ammo.commit_fire("player_vehicle","primary",ammo.request_id(),5.0,true,true)
		check(commit.get("ok",false),"native_ammo_commit_in_contract_fixture")
		ammo.advance(5.0);result.native_ammo=ammo.snapshot()
		result.shot_sequence=int(request.shot_sequence)+1
		result.shot_audit.append({"id":result.shot_sequence,"accepted":true,"weapon":"tank_cannon","flight_state":"impacted","ammo_commit":int(result.native_ammo.sequence)})
		result.native_settled["1:%d"%int(result.native_ammo.sequence)]=true
	return result

func run() -> void:
	var built:=WorldBootstrap.new().build()
	check(built.success,"original_WorldBootstrap_build")
	if not built.success:finish();return
	var session:=FormalLocalSession.new()
	check(session.bind(built.world,built.simulation_step),"bind_real_installed_owners")
	var person_id:=built.world.player_state.player_id()
	var person_before:=built.world.person_overlay.snapshot()
	var ledger_before:=built.world.ledger_state.snapshot()
	var military_before:=built.world.military_state.snapshot()
	check(not session.issue("person:missing").ok,"unknown_or_unauthorized_person_rejected")
	check(not session.issue(person_id,"combat").ok,"unregistered_geography_and_vehicle_rejected")
	check(built.world.military_state.snapshot()==military_before,"rejected_entry_does_not_mutate_military")
	var issued:=session.issue(person_id)
	check(issued.ok and issued.request.crew[0].person_id==person_id,"formal_identity_issued_without_sample_alias")
	check(not built.simulation_step.advance_minutes(10).get("success",true) and built.world.game_clock.total_minutes()==0,"world_acceleration_blocked_during_lease")
	var result:=make_return(issued.request,65.0,true)
	var adopted:=session.adopt(result)
	check(adopted.ok and built.world.game_clock.total_minutes()==1 and absf(float(adopted.pending_seconds)-5.0)<.0001,"one_adoption_advances_original_clock_and_keeps_fraction")
	check(built.world.person_overlay.snapshot()==person_before,"training_does_not_relocate_or_recreate_population")
	var local_body: Dictionary=session.state().participants[person_id].local.crew[0]
	check(local_body.hp==7.0 and local_body.parts.left_arm=="injured","synthetic_training_body_injury_adopted_without_formal_medical_claim")
	check(built.world.ledger_state.snapshot()==ledger_before,"training_never_mints_or_spends_formal_money")
	var once:=built.world.military_state.snapshot()
	var duplicate:=session.adopt(result)
	check(duplicate.ok and duplicate.duplicate and built.world.military_state.snapshot()==once,"identical_duplicate_ignored_without_second_settlement")
	var conflict:=result.duplicate(true);conflict.position_local[0]=100.0
	check(not session.adopt(conflict).ok and built.world.military_state.snapshot()==once,"conflicting_duplicate_rejected")
	var second:=session.issue(person_id)
	var stale:=make_return(second.request,1.0,false)
	check(session.interrupt(str(second.request.lease_id)).ok,"explicit_interruption_discards_only_uncommitted_interval")
	var third:=session.issue(person_id)
	check(not session.adopt(stale).ok,"interrupted_old_lease_cannot_overwrite_new_lease")
	var saved:=built.persistence.save_to_user(4)
	check(saved.success,"original_atomic_FormalPersistence_save_active_lease")
	var loaded:=FormalPersistence.new().load_from_user(4)
	check(loaded.success,"original_exact_FormalPersistence_load")
	if loaded.success:
		check(loaded.world!=built.world and loaded.world.military_state.snapshot()==built.world.military_state.snapshot(),"new_world_instances_restore_exact_local_state_and_lease")
		check(loaded.world.person_overlay.snapshot()==person_before and loaded.world.game_clock.total_minutes()==1,"real_person_and_game_clock_restored")
		var restored_body: Dictionary=loaded.world.military_state.local_operations.participants[person_id].local.crew[0]
		check(restored_body.hp==7.0 and restored_body.parts.left_arm=="injured","training_body_injury_restored_by_original_persistence")
		var restored:=FormalLocalSession.new();check(restored.bind(loaded.world,loaded.simulation_step),"restored_owner_guard_rebound")
		check(not restored.issue(person_id).ok,"restart_does_not_silently_release_unreturned_lease")
		var interrupted_result:=make_return(third.request,1.0,false)
		check(restored.interrupt(str(third.request.lease_id)).ok,"restart_requires_explicit_interruption_decision")
		var fourth:=restored.issue(person_id)
		check(fourth.ok and int(fourth.request.native_ammo.vehicles.player_vehicle.primary.spent)==1,"new_lease_uses_persisted_finite_resources")
		check(not restored.adopt(interrupted_result).ok,"late_process_result_rejected_after_restart_discard")
		var stale_time:=make_return(fourth.request,1.0,false)
		loaded.world.game_clock.advance_minutes(1)
		check(not restored.adopt(stale_time).ok,"changed_authoritative_time_rejects_return")
	var corrupt:=built.persistence.snapshot()
	corrupt.military_state.local_operations.participants[person_id].local.native_ammo.vehicles.player_vehicle.primary.capacity=400
	check(not built.persistence.restore_candidate(corrupt).success,"formal_candidate_rejects_changed_training_ammo_capacity")
	finish()

func finish() -> void:
	var file:=FileAccess.open("user://formal_local_contract_tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"REAL_WORLD_BOOTSTRAP_WITH_SYNTHETIC_CONTRACT_RETURNS","rows":rows,"failures":failures},"\t"))
	print("FORMAL_LOCAL_CONTRACT_FINISHED "+JSON.stringify({"cases":rows.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
