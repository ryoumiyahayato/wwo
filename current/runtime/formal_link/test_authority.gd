extends "res://formal_link/test_session.gd"
## Requested local checks. All injected roles, combat results and faults are fixtures.
const Local = preload("res://scripts/vnext/military/military_local_state.gd")
const Authority = preload("res://formal_link/authority.gd")
var observations: Dictionary={"evidence_kind":"FOCUSED_SYNTHETIC_CONTRACT_AND_REAL_READER_CHECKS"}

func run() -> void:
	if "--interrupt-save" in OS.get_cmdline_user_args():await interrupt_fixture();return
	if "--resume-interrupt" in OS.get_cmdline_user_args():resume_interruption();return
	var built:=WorldBootstrap.new().build()
	check(built.success,"formal_bootstrap_current_content")
	if not built.success:finish();return
	var world:=built.world
	var id:=world.player_state.player_id()
	check(world.military_state.snapshot().schema_id=="vnext_military_state_v3" and not world.military_state.snapshot().has("local_operations"),"unused_local_feature_writes_exact_legacy_v3_shape")
	var assessment:=Authority.assess(world,id)
	observations.formal_default_resources=assessment
	check(assessment.status=="TRAINING_ONLY" and assessment.formal_player_known and not assessment.formal_combat_ready,"real_formal_identity_does_not_grant_combat")
	check(assessment.formation_count==0 and assessment.appointments.is_empty(),"production_composition_has_no_player_post_or_formation")
	var session:=FormalLocalSession.new();check(session.bind(world,built.simulation_step,built.persistence),"bind_same_formal_owners")
	var before:=world.military_state.snapshot()
	check(not session.issue("person:missing","combat").ok and before==world.military_state.snapshot(),"unknown_person_rejected_without_state_mutation")
	world.person_overlay._persons_by_id[id].alive=false
	check(not session.issue(id).ok and Authority.assess(world,id).status=="DENIED","dead_fixture_cannot_enter_training_or_combat")
	world.person_overlay._persons_by_id[id].alive=true
	world.person_travel._journeys[id]={"status":"TRAVELLING"}
	check(not session.issue(id).ok and Authority.assess(world,id).in_transit,"in_transit_fixture_cannot_enter")
	world.person_travel._journeys.erase(id)
	check(not session.issue(id,"combat").ok,"no_post_vehicle_ammo_or_geography_combat_stays_closed")
	var issued:=session.issue(id)
	check(issued.ok,"explicit_training_lease_still_works")
	var baseline:=world.military_state.snapshot()
	var returned:=make_return(issued.request,65.125,true)
	# Actual native shell generation is independent of the ammunition epoch.
	returned.native_settled={"2:1":true}
	check(session.adopt(returned).ok,"native_ammo_fixture_adopted_once")
	var good:=built.persistence.snapshot()
	var military:=world.military_state.snapshot()
	check(military.schema_id=="vnext_military_state_v5_local" and military.local_operations.schema==Local.SCHEMA,"used_local_feature_has_explicit_component_version")
	var record: Dictionary=military.local_operations.participants[id]
	check(record.local.native_ammo.epoch==1 and record.local.native_settled=={"2:1":true},"shell_generation_settlement_is_preserved_separately_from_ammo_epoch")
	check(record.pending_usec==5125000 and record.accounted_local_usec==65125000 and world.game_clock.total_minutes()==1,"whole_minute_and_integer_microsecond_remainder")
	var duplicate:=session.adopt(returned)
	check(duplicate.duplicate and military==world.military_state.snapshot(),"duplicate_return_preserves_inventory_history_and_clock")
	var corrupt:=good.duplicate(true)
	corrupt.military_state.local_operations.participants[id].local.native_ammo=baseline.local_operations.participants[id].local.native_ammo.duplicate(true)
	check(not built.persistence.restore_candidate(corrupt).success,"saved_inventory_rollback_rejected_against_adopted_result")
	corrupt=good.duplicate(true);corrupt.total_minutes=0;corrupt.minute_remainder=0
	check(not built.persistence.restore_candidate(corrupt).success,"formal_clock_rollback_before_committed_result_rejected")
	corrupt=good.duplicate(true);corrupt.military_state.schema_id="vnext_military_state_v999"
	check(not built.persistence.restore_candidate(corrupt).success,"unknown_component_version_rejected_without_drop")
	corrupt=good.duplicate(true);corrupt.military_state.local_operations.participants[id].local.crew[0].parts.left_arm="unknown"
	check(not built.persistence.restore_candidate(corrupt).success,"unknown_training_body_state_rejected")
	check(good==built.persistence.snapshot(),"failed_restore_candidates_leave_live_world_exact")
	var legacy:=good.duplicate(true)
	legacy.military_state.schema_id="vnext_military_state_v4_local"
	legacy.military_state.local_operations.schema="formal_local_operations_v1"
	legacy.military_state.local_operations.erase("time_policy")
	for p: Dictionary in legacy.military_state.local_operations.participants.values():p.erase("pending_usec");p.erase("accounted_local_usec")
	var upgraded:=built.persistence.restore_candidate(legacy)
	check(upgraded.success,"synthetic_legacy_v4_local_restores")
	if upgraded.success:
		var migrated: Dictionary=upgraded.world.military_state.local_operations
		check(migrated.adoptions==legacy.military_state.local_operations.adoptions and migrated.participants[id].local==legacy.military_state.local_operations.participants[id].local,"migration_preserves_native_results_events_and_injury_exactly")
		check(migrated.participants[id].pending_usec==5125000,"legacy_fraction_migrates_to_cumulative_usec")
		upgraded.simulation_step.local_operation_guard=Callable()
	var v3:=good.duplicate(true);v3.military_state=baseline.duplicate(true);v3.military_state.erase("local_operations");v3.military_state.schema_id="vnext_military_state_v3"
	var restored_v3:=built.persistence.restore_candidate(v3)
	check(restored_v3.success and restored_v3.world.military_state.snapshot().schema_id=="vnext_military_state_v3","legacy_v3_without_local_payload_stays_v3")
	if restored_v3.success:restored_v3.simulation_step.local_operation_guard=Callable()
	var task: Dictionary={"finished":false}
	_save_task.call_deferred(built.persistence,task,2)
	await process_frame
	var checked_busy:=false
	while not task.finished:
		if built.persistence.is_save_in_progress() and not checked_busy:
			checked_busy=true
			check(not built.simulation_step.advance_minutes(1).get("success",true),"parallel_formal_advance_blocked_while_save_snapshot_owned")
			check(not session.issue(id).ok,"new_lease_blocked_while_save_in_progress")
			check(not built.persistence.save_to_user(2).success,"second_save_cannot_replace_worker_temp_or_backup")
		await process_frame
	check(checked_busy and task.result.success and built.persistence.last_save_costs.responsive_frames>1,"async_save_uses_original_verified_atomic_path_and_yields_frames")
	observations.async_save_costs=built.persistence.last_save_costs.duplicate(true)
	var cold:=FormalPersistence.new().load_from_user(2)
	check(cold.success and cold.world!=world and cold.world.military_state.snapshot()==world.military_state.snapshot(),"async_saved_world_restores_as_new_owners")
	if cold.success:cold.simulation_step.local_operation_guard=Callable()
	var active:=session.issue(id)
	check(active.ok,"active_lease_can_be_saved")
	check((await built.persistence.save_to_user_async(3)).success,"async_active_lease_durable_before_native_start")
	var active_cold:=FormalPersistence.new().load_from_user(3)
	check(active_cold.success and not active_cold.simulation_step.advance_minutes(1).get("success",true),"restored_pending_lease_guards_clock_before_military_view_exists")
	if active_cold.success:
		var resumed:=FormalLocalSession.new();resumed.bind(active_cold.world,active_cold.simulation_step,active_cold.persistence)
		check(not resumed.adopt(make_return(active.request,1.0,false)).ok,"previous_process_unreturned_lease_cannot_be_adopted_after_cold_load")
		active_cold.simulation_step.local_operation_guard=Callable()
	session.interrupt(str(active.request.lease_id))
	var fork_a:=built.persistence.restore_candidate(good)
	var fork_b:=built.persistence.restore_candidate(good)
	if fork_a.success and fork_b.success:
		var a:=FormalLocalSession.new();var b:=FormalLocalSession.new()
		a.bind(fork_a.world,fork_a.simulation_step,fork_a.persistence);b.bind(fork_b.world,fork_b.simulation_step,fork_b.persistence)
		var ar:=a.issue(id);var br:=b.issue(id)
		check(ar.ok and br.ok and ar.request.lease_id==br.request.lease_id and ar.request.issuer_id!=br.request.issuer_id,"copied_save_forks_have_distinct_runtime_issuers")
		check(not b.adopt(make_return(ar.request,1.0,false)).ok,"receipt_from_another_runtime_fork_is_rejected")
		fork_a.simulation_step.local_operation_guard=Callable();fork_b.simulation_step.local_operation_guard=Callable()
	built.simulation_step.local_operation_guard=Callable()
	await time_equivalence()
	permission_fixture()
	finish()

func _save_task(storage: FormalPersistence,result: Dictionary,slot: int) -> void:
	result.result=await storage.save_to_user_async(slot);result.finished=true

func time_equivalence() -> void:
	var one:=WorldBootstrap.new().build()
	var split:=WorldBootstrap.new().build()
	check(one.success and split.success,"time_equivalence_real_formal_worlds")
	if not one.success or not split.success:return
	one.simulation_step.advance_minutes(59);split.simulation_step.advance_minutes(59)
	var states: Array[Dictionary]=[]
	for i: int in 2:
		var built: WorldBuildResult=one if i==0 else split
		var session:=FormalLocalSession.new();session.bind(built.world,built.simulation_step,built.persistence)
		var durations: Array=[120.25] if i==0 else [20.125,39.875,60.25]
		for duration: float in durations:
			var request:=session.issue(built.world.player_state.player_id())
			check(request.ok,"time_fixture_lease_%d"%i)
			if not request.ok:break
			check(session.adopt(make_return(request.request,duration,false)).ok,"time_fixture_adoption_%d"%i)
		var p: Dictionary=session.state().participants[built.world.player_state.player_id()]
		states.append({"minute":built.world.game_clock.total_minutes(),"pending_usec":p.pending_usec,"accounted_usec":p.accounted_local_usec,"economy":built.world.economy_state.get_persistent_state(),"spatial":built.world.spatial_world.snapshot(),"ledger":built.world.ledger_state.snapshot()})
		built.simulation_step.local_operation_guard=Callable()
	check(states[0]==states[1] and states[0].minute==61 and states[0].pending_usec==250000,"one_interval_equals_split_returns_across_minute_and_hour_boundary")
	observations.time_equivalence={"continuous_seconds":120.25,"split_seconds":[20.125,39.875,60.25],"start_minute":59,"end_minute":states[0].minute,"pending_usec":states[0].pending_usec,"formal_economy_spatial_ledger_equal":states[0]==states[1]}

func permission_fixture() -> void:
	# Synthetic organization/formation setup; this is not production military data.
	var built:=WorldBootstrap.new().build()
	var w:=built.world;var id:=w.player_state.player_id();var core:=w.organization_state
	var org:="organization:local_permission_fixture"
	check(core.register_organization(org,"military_institution","place:paris") and core.define_position(org,"commander","Fixture commander",1) and core.add_member(org,id) and core.create_appointment(org,"assigned",id,"commander"),"synthetic_permission_fixture_uses_existing_organization_apis")
	check(w.military_service.create_formation(w.military_state,w.military_map,"formation:local_permission_fixture","country_fra","paris",5,{"equipment_factor":1.0}),"synthetic_aggregate_formation_is_not_a_tank")
	var stages: Array[String]=[AuthorizationCheck.STAGE_DOMAIN_EXECUTION]
	var granted:=core.add_authority_grant({"authority_id":"authority.fixture.defend","holder":OrganizationState.position_holder(org,"commander"),"represented_entity":org,"operation":"military.defend","target_scope":["formation:local_permission_fixture"],"spatial_scope":[],"subject_scope":[],"amount_or_quantity_limit":-1.0,"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":"basis.fixture"},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":OrganizationState.constraints(stages),"accountability":OrganizationState.accountability(org),"revoked_at":-1})
	check(granted,"synthetic_scoped_defend_grant_accepted_by_existing_owner")
	var context:=OrganizationState.acting_context(id,org,org,"authority.fixture.defend","assigned")
	var allowed:=w.authorization_check.resolve_authority(context,"military.defend",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,"formation:local_permission_fixture","","",0.0,0)
	check(allowed.status==AuthorizationCheck.ALLOWED,"existing_scoped_military_authority_can_be_proven_in_fixture")
	var assessment:=Authority.assess(w,id)
	var existing_defend_allowed:=false
	for proof: Dictionary in assessment.existing_domain_authorizations:
		if proof.result.status==AuthorizationCheck.ALLOWED:existing_defend_allowed=true
	check(existing_defend_allowed,"fixture_assessment_reports_actual_scoped_defend_proof")
	check(not assessment.formal_combat_ready and not assessment.equipment_factor_is_vehicle_count,"defend_grant_and_equipment_factor_do_not_forge_local_vehicle_or_ammo")
	observations.synthetic_permission_fixture={"evidence_kind":"SYNTHETIC_PERMISSION_BOUNDARY_FIXTURE","defend_status":allowed.status,"combat_ready":assessment.formal_combat_ready,"formation_count":assessment.formation_count}
	built.simulation_step.local_operation_guard=Callable()

func interrupt_fixture() -> void:
	var built:=WorldBootstrap.new().build()
	var session:=FormalLocalSession.new();session.bind(built.world,built.simulation_step,built.persistence)
	var request:=session.issue(built.world.player_state.player_id())
	var saved:=built.persistence.save_to_user(3)
	if not saved.success:push_error(saved.message);quit(1);return
	session.adopt(make_return(request.request,65.0,true))
	var document:=FormalWorldPersistenceDocument.encode(built.persistence.snapshot(),built.persistence._save_metadata)
	var thread:=Thread.new()
	thread.start(func() -> String:return AtomicJsonFileStore.write_verified(FormalPersistence.slot_path(3),document,Callable(self,"hold_verifier"),true))
	while thread.is_alive():await process_frame
	thread.wait_to_finish();quit(2)

func hold_verifier(path: String) -> String:
	print("FAULT_INJECTION_TEMP_BEFORE_COMMIT pid=%d path=%s"%[OS.get_process_id(),path])
	OS.delay_msec(30000)
	return "FAULT_INJECTION_NOT_COMMITTED"

func resume_interruption() -> void:
	var loaded:=FormalPersistence.new().load_from_user(3)
	check(loaded.success,"killed_writer_kept_valid_prior_primary")
	if loaded.success:
		var s:=FormalLocalSession.new();s.bind(loaded.world,loaded.simulation_step,loaded.persistence)
		var id:=loaded.world.player_state.player_id();var p: Dictionary=s.state().participants[id]
		check(not s.state().active.is_empty() and not s.issue(id).ok,"interrupted_save_never_silently_releases_or_refills_lease")
		check(p.adoption_count==0 and p.local.native_ammo.vehicles.player_vehicle.primary.spent==0,"only_old_committed_baseline_is_claimed_not_unsaved_action")
		check(not loaded.simulation_step.advance_minutes(1).get("success",true),"pending_interval_stays_blocked_after_process_kill")
		loaded.simulation_step.local_operation_guard=Callable()
	finish()

func finish() -> void:
	FileAccess.open("user://formal_authority_contract_tests.json",FileAccess.WRITE).store_string(JSON.stringify({"source":"FOCUSED_SYNTHETIC_CONTRACT_RETURNS_NOT_NATIVE_COMBAT","rows":rows,"failures":failures,"observations":observations},"\t"))
	print("FORMAL_AUTHORITY_CONTRACT_FINISHED "+JSON.stringify({"cases":rows.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
