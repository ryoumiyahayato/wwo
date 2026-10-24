extends SceneTree
const Service=preload("res://scripts/vnext/military/military_combat_authority_service.gd")
const State=preload("res://scripts/vnext/military/military_combat_authority_state.gd")
const Delegation=preload("res://scripts/vnext/military/military_delegation_service.gd")
const Recovery=preload("res://practice/recovery.gd")
var rows: Array=[]
var source:=""
var output:=""
var mode:="prepare"
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	rows.append({"case":label,"passed":ok});print(("OK " if ok else "FAIL ")+label)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
	var loaded:=Recovery.read_portable(source)
	check(loaded.get("ok",false),"explicit_portable_input_restored")
	if not loaded.get("ok",false):finish({});return
	var b: WorldBuildResult=loaded.built
	var marker: Dictionary=loaded.evidence
	var native:=load("res://practice/native_return.gd")
	var error:=AtomicJsonFileStore.write_verified(native.path(str(marker.instance_id)),marker,Callable(native,"verify"),true)
	check(error.is_empty(),"original_native_evidence_preserved")
	var w:=b.world;var p:=b.persistence;var original:=p.snapshot();var duty: Dictionary=w.military_state.duty_operations
	check(w.game_clock.total_minutes()==2 and duty.pending_usec==12402648 and duty.orders.size()==2 and duty.active.is_empty(),"two_successful_duties_and_formal_time_preserved")
	var service:=Service.new();check(service.bind(w,p).is_empty(),"original_owners_bound")
	var old_unit:=w.military_state.get_formation(duty.unit).to_dict()
	var old_org:=w.organization_state.snapshot()
	if mode=="prepare":
		check(w.military_state.combat_authority.is_empty(),"v9_does_not_autocommission")
		check(service.commission().get("qualified",false),"explicit_named_qualification_commissioned")
		check(State.qualified(w),"same_existing_unit_has_current_qualification")
		var before:=p.snapshot()
		check(service.commission().get("duplicate",false) and before==p.snapshot(),"repeat_commission_exact_noop")
		check(w.organization_state.appointment(duty.organization,"duty_leader").person_id==duty.leader and w.organization_state.appointment(duty.organization,"duty_observer").person_id==duty.executor,"original_duty_appointments_retained")
		var wrong:=service.context("operator")
		before=p.snapshot()
		check(not service.delegate("wrong_issuer",wrong,2,3).ok and before==p.snapshot(),"operator_cannot_self_issue_delegation")
		check(not service.delegate("future",service.context("commander"),1,3).ok and before==p.snapshot(),"backdated_minute_request_refused")
		check(service.delegate("annex_order_001",service.context("commander"),2,3).ok,"actual_organization_delegation_recorded")
	else:
		check(State.qualified(w) and w.military_state.combat_authority.mandates.has("annex_order_001"),"independent_process_qualified_chain_restored")
	var d:=service.state();var m: Dictionary=d.mandates.get("annex_order_001",{})
	if m.is_empty():finish({});return
	var actor:=service.context("operator",m.delegation_id)
	check(service.authorize(m.id,actor).ok,"current_operator_execution_permission_resolves")
	check(service.accept(m.id,actor).ok,"qualified_order_actually_accepted")
	var before:=p.snapshot()
	check(service.accept(m.id,actor).get("duplicate",false) and before==p.snapshot(),"repeat_acceptance_exact_noop")
	check(service.delegate(m.id,service.context("commander"),2,3).get("duplicate",false) and before==p.snapshot(),"repeat_delegation_exact_noop")
	check(not service.delegate(m.id,service.context("commander"),2,4).ok and before==p.snapshot(),"conflicting_mandate_no_effect")
	var wrong_actor:=actor.duplicate(true);wrong_actor.person_id=d.commander
	check(not service.authorize(m.id,wrong_actor).ok,"wrong_recipient_refused")
	var resolution:=w.authorization_check.resolve_authority(actor,"military.combat.execute",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,"formation:outside",d.anchor,d.operator,1.0,w.game_clock.current_hour())
	check(resolution.status==AuthorizationCheck.DENIED,"delegation_cannot_expand_unit_scope")
	resolution=w.authorization_check.resolve_authority(actor,"military.combat.execute",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,d.unit,d.anchor,d.operator,2.0,w.game_clock.current_hour())
	check(resolution.status==AuthorizationCheck.DENIED,"delegation_quantity_limit_enforced")
	var sub: Dictionary=w.organization_state.delegation(m.delegation_id).duplicate(true);sub.delegation_id="delegation.forbidden_redelegation";sub.source_kind="delegation";sub.source_id=m.delegation_id;sub.delegator_context=actor;sub.recipient_person_id=d.commander
	check(w.authorization_check.check_delegation(sub).status!=AuthorizationCheck.ALLOWED and not w.organization_state.record_delegation(sub),"operator_cannot_redelegate")
	var admission:=service.execution_admission(m.id,actor)
	check(not admission.ok and admission.reason=="FORMAL_COMBAT_NOT_READY" and admission.blockers.size()==4,"qualification_does_not_bypass_other_combat_requirements")
	var request_service:=Delegation.new();request_service.bind(w,p)
	var q: Dictionary={"id":"delegation_request:qualified_001","unit":d.unit,"region":w.military_state.local_delegation.region.id,"issuer":d.commander,"participants":[d.commander,d.operator],"from_minute":2,"until_minute":3,"settlement_owner":State.ORG,"objective":"CONTROLLED_LOCAL_DEFENCE"}
	var decision:=request_service.request_combat(q,service.command_context())
	check(decision.ok and decision.decision.blockers.size()==4 and not decision.decision.blockers.has("NAMED_UNIT_NONCOMBAT_ONLY") and not decision.decision.blockers.has("NO_COMBAT_DELEGATION_AUTHORITY"),"two_actual_authority_blockers_removed")
	check(w.military_state.local_delegation.requests["delegation_request:annex_gui_001"]==original.military_state.local_delegation.requests["delegation_request:annex_gui_001"],"historical_rejection_not_rewritten")
	check(w.military_state.get_formation(d.unit).to_dict()==old_unit and w.person_overlay.person_count()==2,"same_unit_zero_aggregate_and_same_people")
	for component: String in ["persons","population","ledger","personal_economy","economy_native","total_minutes","minute_remainder","person_travel","spatial","territory"]:
		if original.has(component):check(p.snapshot()[component]==original[component],"unchanged_"+component)
	check(w.military_state.material_registry==original.military_state.material_registry and w.military_state.duty_operations==original.military_state.duty_operations and w.military_state.training_group==original.military_state.training_group,"ammo_duty_training_entire_state_unchanged")
	var conserved:=p.snapshot();var prior:=original.duplicate(true)
	for value: Dictionary in [conserved,prior]:
		value.erase("organization");value.erase("military_state")
	check(conserved==prior,"all_nonmilitary_nonorganization_world_state_exact")
	check(State.references_error(w).is_empty(),"qualification_source_references_valid")
	var good:=p.snapshot()
	# Separate candidate worlds use the existing reader; tests never mutate the successful branch.
	var fork:=p.restore_candidate(good);check(fork.success,"v10_reader_accepts_actual_qualified_state")
	if fork.success:
		var fs:=Service.new();fs.bind(fork.world,fork.persistence)
		var revoke_before:=fork.persistence.snapshot()
		check(not fs.revoke_mandate(m.id,actor).ok and revoke_before==fork.persistence.snapshot(),"operator_cannot_revoke_commander_mandate")
		check(fs.revoke_mandate(m.id,fs.command_context()).ok and not fs.authorize(m.id,actor).ok,"revoked_delegation_stops_current_permission")
		revoke_before=fork.persistence.snapshot()
		check(fs.revoke_mandate(m.id,fs.command_context()).get("duplicate",false) and revoke_before==fork.persistence.snapshot(),"repeat_revocation_exact_noop")
		check(fork.persistence.restore_candidate(fork.persistence.snapshot()).success,"revoked_delegation_stays_loadable")
	fork=p.restore_candidate(good)
	if fork.success:
		var fs:=Service.new();fs.bind(fork.world,fork.persistence)
		check(fork.world.organization_state.revoke_authority(State.EXECUTE,0) and not fs.authorize(m.id,actor).ok,"source_revocation_stops_existing_delegation")
		var old_record:=w.organization_state.delegation(m.delegation_id)
		check(fork.world.authorization_check.check_delegation(old_record).status!=AuthorizationCheck.ALLOWED,"revoked_source_cannot_validate_historical_chain")
		check(not fs.delegate("after_revocation",fs.context("commander"),2,3).ok,"revoked_commander_cannot_issue_new_mandate")
	fork=p.restore_candidate(good)
	if fork.success:
		var fs:=Service.new();fs.bind(fork.world,fork.persistence)
		check(fork.world.organization_state.remove_appointment(State.ORG,"operator") and not State.qualified(fork.world) and not fs.authorize(m.id,actor).ok,"removed_appointment_disables_qualification")
		check(fork.persistence.restore_candidate(fork.persistence.snapshot()).success,"withdrawn_qualification_history_stays_loadable")
	fork=p.restore_candidate(good)
	if fork.success:
		var fs:=Service.new();fs.bind(fork.world,fork.persistence)
		var advanced:=fork.simulation_step.advance_minutes(1)
		check(advanced.get("success",true) and fork.world.game_clock.total_minutes()==3 and fs.authorize(m.id,actor).get("reason")=="MINUTE_WINDOW_CLOSED","minute_end_is_exclusive_using_original_clock")
		resolution=fork.world.authorization_check.resolve_authority(actor,"military.combat.execute",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,d.unit,d.anchor,d.operator,1.0,2)
		check(resolution.status==AuthorizationCheck.DENIED,"hour_authority_expiry_separate_from_minute_window")
	fork=p.restore_candidate(good)
	if fork.success:
		var fs:=Service.new();fs.bind(fork.world,fork.persistence)
		var expired:=fork.simulation_step.advance_minutes(119)
		check(expired.get("success",true) and fork.world.game_clock.current_hour()==2,"original_clock_advances_expiry_fork")
		check(fork.world.authorization_check.check_delegation(w.organization_state.delegation(m.delegation_id)).status==AuthorizationCheck.ALLOWED,"historical_signature_can_remain_valid_after_current_expiry")
		check(not fs.delegate("expired_current",fs.context("commander"),121,122).ok,"current_expiry_prevents_backdated_authority_reuse")
	fork=p.restore_candidate(good)
	if fork.success:
		fork.world.military_state.combat_authority.clear()
		var fs:=Service.new();fs.bind(fork.world,fork.persistence)
		var collision_before:=fork.persistence.snapshot()
		check(not fs.commission().ok and collision_before==fork.persistence.snapshot(),"failed_commission_has_no_partial_organization_mutation")
	var broken:=good.duplicate(true);broken.military_state.combat_authority.claims[d.operator]="formal_population_claim:wrong"
	check(not p.restore_candidate(broken).success,"wrong_qualification_claim_rejected_on_restore")
	broken=good.duplicate(true);broken.military_state.combat_authority.extra=true
	check(not p.restore_candidate(broken).success,"unknown_qualification_fields_rejected")
	check(p.snapshot()==good,"negative_cases_leave_original_world_exact")
	var saved:=p.save_to_user(2);check(saved.success,"original_atomic_formal_save")
	var export_error:=Recovery.export_portable(output.trim_suffix(".json")+"_portable.json",p)
	check(export_error.is_empty(),"portable_formal_and_native_evidence_exported")
	finish({"save":ProjectSettings.globalize_path(FormalPersistence.slot_path(2)),"qualification":d,"decision":decision,"material":w.military_state.material_registry.view.lot,"minute":w.game_clock.total_minutes(),"pending_usec":duty.pending_usec,"world_id":w.get_instance_id(),"organization_id":w.organization_state.get_instance_id(),"step_id":b.simulation_step.get_instance_id(),"persistence_id":p.get_instance_id()})
func finish(detail: Dictionary) -> void:
	var passed: bool=not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.passed)
	var result: Dictionary={"pid":OS.get_process_id(),"mode":mode,"source":source,"cases":rows,"passed":passed,"detail":detail}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("FORMAL_COMBAT_AUTHORITY_CHECKS "+str(passed)+" count="+str(rows.size())+" pid="+str(OS.get_process_id()));quit(0 if passed else 1)
