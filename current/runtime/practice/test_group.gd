extends SceneTree
## Requested local checks of restored NPC/group references and strict version boundaries.
const State = preload("res://scripts/vnext/military/military_training_state.gd")
const Service = preload("res://scripts/vnext/military/military_training_service.gd")
var rows: Array=[]
var source_path:=""
var report_path:=""

func _initialize() -> void:run.call_deferred()

func check(value: bool, label: String) -> void:rows.append({"case":label,"passed":value})

func refused(snapshot: Dictionary, label: String) -> void:
	var built:=FormalPersistence.new().restore_candidate(snapshot)
	check(not built.success,label)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source_path=arg.trim_prefix("--source=")
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	var built:=FormalPersistence.new()._restore_snapshot_file(source_path)
	check(built.success,"actual_completed_group_save_read")
	if not built.success:finish();return
	var world:=built.world
	var snapshot:=built.persistence.snapshot()
	check(world.person_overlay.person_count()==2 and world.population_state.snapshot().named_person_units.size()==2,"two_formal_people_match_population_owner")
	check(world.person_overlay.person(State.NPC).claim_id=="formal_population_claim:country_fra:0002","ordinary_npc_claim_preserved")
	check(snapshot.economy_native.config.actors.filter(func(actor: Dictionary) -> bool:return actor.id==State.NPC).all(func(actor: Dictionary) -> bool:return actor.population_start==0),"named_npc_not_background_population")
	check(world.military_state.material_registry.schema=="military_material_registry_v3_recovery" and world.military_state.training_group.order.status=="REPORTED","material_v3_and_completed_group_share_world")
	check(world.military_state.material_registry.view.lot.available==18 and world.military_state.material_registry.view.lot.consumed==2,"finite_18_plus_2_after_legal_return")
	var candidate:=snapshot.duplicate(true)
	candidate.economy_native.config.opening_residents[0].claim_id="formal_population_claim:wrong"
	refused(candidate,"opening_claim_mismatch_refused")
	candidate=snapshot.duplicate(true);candidate.persons.persons[1].claim_id=candidate.persons.persons[0].claim_id
	refused(candidate,"duplicate_population_claim_refused")
	candidate=snapshot.duplicate(true)
	candidate.persons.persons[1].provenance.opening_place_id="place:london"
	refused(candidate,"opening_birth_place_mismatch_refused")
	candidate=snapshot.duplicate(true)
	candidate.persons.persons[1].basic_demographic_identity.opening_cash_policy="invented"
	refused(candidate,"opening_zero_cash_identity_mismatch_refused")
	candidate=snapshot.duplicate(true)
	candidate.economy_native.config.erase("opening_residents")
	refused(candidate,"missing_explicit_npc_reference_not_auto_repaired")
	candidate=snapshot.duplicate(true);candidate.military_state.schema_id="vnext_military_state_v999"
	refused(candidate,"future_military_schema_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.schema_id="vnext_military_state_v6_material"
	refused(candidate,"old_outer_schema_cannot_hide_group_field")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.schema="formal_training_group_v999"
	refused(candidate,"future_group_schema_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.observer=candidate.military_state.training_group.leader
	refused(candidate,"same_person_cannot_fill_two_claims")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.observer_claim="formal_population_claim:wrong"
	refused(candidate,"group_claim_mismatch_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.position=Vector3(INF,0,0)
	refused(candidate,"nonfinite_physical_position_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.order.observation.clear()
	refused(candidate,"report_without_physical_observation_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.order.report.clear()
	refused(candidate,"completed_order_without_delivery_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.order.report.distance=99.0
	refused(candidate,"distant_face_to_face_report_refused")
	candidate=snapshot.duplicate(true);candidate.military_state.training_group.order.observation.physics_steps=0
	refused(candidate,"animation_or_timer_without_physics_refused")
	var node:=Node3D.new();get_root().add_child(node)
	var service:=Service.new();check(service.bind(world,node).is_empty(),"original_world_authorization_owner_bound")
	var qm: Dictionary=load("res://custody/scenario.gd").context(world,"inspect")
	check(not service.authorize("issue",qm).ok,"quartermaster_authority_not_training_command")
	var fire: Dictionary=load("res://practice/scenario.gd").context(world,"fire")
	check(not service.authorize("issue",fire).ok,"shooting_authority_not_training_command")
	var before:=built.persistence.snapshot()
	var result:=service.issue(node)
	check(result.get("duplicate",false) and built.persistence.snapshot()==before,"repeat_order_preserves_report_population_resources_and_clock")
	check(not service.report(node).ok and built.persistence.snapshot()==before,"repeat_report_cannot_duplicate_observation")
	check(world.organization_state.revoke_authority("authority.training_1900.issue",world.game_clock.current_hour()),"training_command_authority_can_be_revoked")
	before=built.persistence.snapshot()
	check(not service.issue(node).ok and built.persistence.snapshot()==before,"revoked_command_cannot_repeat_order")
	node.free();finish()

func finish() -> void:
	var failed:=rows.filter(func(row: Dictionary) -> bool:return not row.passed)
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"pid":OS.get_process_id(),"source":source_path,"checks":rows,"failures":failed},"\t"))
	print("FORMAL_GROUP_LOCAL_CHECKS "+JSON.stringify({"checks":rows.size(),"failures":failed.size()}))
	quit(0 if failed.is_empty() else 1)
