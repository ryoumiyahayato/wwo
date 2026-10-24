extends SceneTree
const State=preload("res://scripts/vnext/military/military_delegation_state.gd")
const Service=preload("res://scripts/vnext/military/military_delegation_service.gd")
var rows: Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	rows.append({"case":label,"passed":ok})
	if not ok:print("FAIL "+label)
func run() -> void:
	var source:="";var report:="";var mode:="prepare"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
	var b:=FormalPersistence.new()._restore_snapshot_file(source)
	check(b.success,"original_reader_loads_selected_success_branch")
	if not b.success:print(b.error);quit(1);return
	var original:=b.persistence.snapshot();var d: Dictionary=b.world.military_state.duty_operations
	check(d.orders.size()==2 and d.active.is_empty() and d.pending_usec==12402648 and b.world.game_clock.total_minutes()==2,"two_completed_duties_and_fraction_preserved")
	var service:=Service.new();check(service.bind(b.world,b.persistence).is_empty(),"bound_original_world_and_persistence")
	if mode=="prepare":
		check(b.world.military_state.local_delegation.is_empty() and b.world.military_state.snapshot().schema_id==VNextMilitaryState.DUTY_SCHEMA_ID,"v8_load_does_not_autocommission")
		check(service.register_controlled_annex().ok,"explicit_region_and_identity_registration")
		var before:=b.persistence.snapshot()
		check(service.register_controlled_annex().get("duplicate",false) and before==b.persistence.snapshot(),"duplicate_registration_exact_noop")
	var state:=service.state();var nodes: Array[Node3D]=[]
	for person: String in state.bodies:
		var node:=Node3D.new();node.set_meta("formal_person_id",person);get_root().add_child(node);node.position=d.leader_position if person==d.leader else d.position;nodes.append(node)
		var lease_id:=""
		if mode=="cold":
			for l: Dictionary in state.leases:
				if l.person==person and l.status=="ACTIVE":lease_id=l.id;node.position=l.position
			var before:=b.persistence.snapshot()
			check(not service.attach_projection(person,node).ok and before==b.persistence.snapshot(),"cold_requires_explicit_saved_lease_"+person)
		var linked:=service.attach_projection(person,node,lease_id)
		check(linked.ok,"projection_bound_"+person)
		var other:=Node3D.new();other.set_meta("formal_person_id",person);get_root().add_child(other);other.position=node.position
		var second:=Service.new();second.bind(b.world,b.persistence)
		check(not second.attach_projection(person,other,str(linked.get("lease",""))).ok,"second_service_cannot_project_same_person_"+person)
		check(not second.release_projection(str(linked.get("lease","")),other).ok,"other_node_cannot_release_projection_"+person)
		other.queue_free()
	check(not b.persistence.world_time_available() and not b.simulation_step.advance_minutes(1).get("success",true),"projection_lease_blocks_unowned_formal_time")
	var q: Dictionary={"id":"delegation_request:annex_001","unit":d.unit,"region":state.region.id,"issuer":d.leader,"participants":[d.leader,d.executor],"from_minute":2,"until_minute":3,"settlement_owner":d.organization,"objective":"CONTROLLED_LOCAL_DEFENCE"}
	var context:=OrganizationState.acting_context(d.leader,d.organization,d.organization,"authority."+str(d.unit).replace(":",".")+".issue","duty_leader",true)
	var decision:=service.request_combat(q,context)
	check(decision.ok and decision.decision.status=="FORMAL_COMBAT_NOT_READY" and decision.decision.blockers.has("NO_COMBAT_DELEGATION_AUTHORITY"),"noncombat_authority_does_not_authorize_combat")
	var before:=b.persistence.snapshot()
	check(service.request_combat(q,context).get("duplicate",false) and before==b.persistence.snapshot(),"repeated_request_exact_noop")
	var conflict:=q.duplicate(true);conflict.until_minute=4
	check(not service.request_combat(conflict,context).ok and before==b.persistence.snapshot(),"same_id_changed_request_refused")
	check(not service.apply_injury("projection:1",{"hp":0,"casualty":true}).ok and not service.adopt_combat_result(q.id,{"victory":true,"elapsed_usec":60000000}).ok and before==b.persistence.snapshot(),"invented_injury_and_combat_result_have_no_effect")
	for kind: String in ["unknown","medical","claim","ready","region","duplicate_body"]:
		var bad:=state.duplicate(true)
		match kind:
			"unknown":bad.extra=true
			"medical":bad.bodies[d.leader].medical_status="HEALTHY"
			"claim":bad.bodies[d.leader].claim=bad.bodies[d.executor].claim
			"ready":bad.requests[q.id].status="FORMAL_COMBAT_READY"
			"region":bad.region.historical_geography=true
			"duplicate_body":var l: Dictionary=bad.leases[0].duplicate(true);l.id="projection:"+str(bad.leases.size()+1);bad.leases.append(l)
		check(not State.error(bad).is_empty(),"reject_"+kind)
	var invalid:=before.duplicate(true);invalid.military_state.local_delegation.bodies[d.leader].claim="formal_population_claim:wrong"
	check(not b.persistence.restore_candidate(invalid).success,"restore_rejects_wrong_original_claim")
	check(State.references_error(b.world).is_empty(),"all_original_references_valid")
	if mode=="cold":
		for node: Node3D in nodes:
			for l: Dictionary in state.leases:
				if l.person==node.get_meta("formal_person_id") and l.status=="ACTIVE":check(service.release_projection(l.id,node).ok,"owner_releases_saved_projection_"+l.person)
		check(b.persistence.world_time_available(),"released_projection_restores_original_time_guard")
	var after:=b.persistence.snapshot();after.military_state.erase("local_delegation");after.military_state.schema_id=VNextMilitaryState.DUTY_SCHEMA_ID
	original.military_state.erase("local_delegation");original.military_state.schema_id=VNextMilitaryState.DUTY_SCHEMA_ID
	check(after==original,"entire_world_except_explicit_delegation_extension_unchanged")
	var saved:=b.persistence.save_to_user(2);check(saved.success,"original_atomic_formal_save")
	var result: Dictionary={"pid":OS.get_process_id(),"mode":mode,"source":source,"save":ProjectSettings.globalize_path(FormalPersistence.slot_path(2)),"minute":b.world.game_clock.total_minutes(),"pending_usec":d.pending_usec,"people":b.world.person_overlay.person_count(),"material":b.world.military_state.material_registry.view.lot,"decision":decision,"cases":rows,"passed":rows.all(func(x: Dictionary)->bool:return x.passed)}
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	for node: Node3D in nodes:node.queue_free()
	print("FORMAL_DELEGATION_CHECKS "+str(result.passed)+" "+str(rows.size())+" pid="+str(OS.get_process_id()));quit(0 if result.passed else 1)
