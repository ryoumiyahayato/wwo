extends RefCounted
## Formal authorization and bounded order transitions. Physics supplied by one bound local executor.
const State = preload("res://scripts/vnext/military/military_training_state.gd")
var world: WorldState
var _executor: WeakRef

static func initialize(world_value: WorldState) -> String:
	var core:=world_value.organization_state
	var leader:=world_value.player_state.player_id()
	var observer:=world_value.person_overlay.person(State.NPC)
	if observer.get("claim_id")!="formal_population_claim:country_fra:0002":return "NO_LEGITIMATE_OPENING_NPC"
	if not core.register_organization(State.ORG,"military_institution","place:paris","organization:practice_1900_range"):return "TRAINING_UNIT_FAILED"
	for pair: Array in [[leader,"training_leader"],[State.NPC,"training_observer"]]:
		if not core.define_position(State.ORG,pair[1],"Explicit new 1900 range "+pair[1],1):return "TRAINING_POSITION_FAILED"
		if not core.add_member(State.ORG,pair[0]):return "TRAINING_MEMBERSHIP_FAILED"
		if not core.create_appointment(State.ORG,pair[1],pair[0],pair[1]):return "TRAINING_APPOINTMENT_FAILED"
	for op: String in State.OPS:
		var leader_operation: bool=op in ["issue","receive"]
		var role: String="training_leader" if leader_operation else "training_observer"
		var stages: Array[String]=[AuthorizationCheck.STAGE_DOMAIN_EXECUTION]
		var grant: Dictionary={"authority_id":"authority.training_1900."+op,"holder":OrganizationState.position_holder(State.ORG,role),"represented_entity":State.ORG,"operation":"military.training."+op,"target_scope":[State.AREA],"spatial_scope":["place:paris"],"subject_scope":[State.NPC],"amount_or_quantity_limit":1.0,"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":State.SOURCE},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":OrganizationState.constraints(stages,"","One unarmed observer. Local instruction and face to face report only."),"accountability":OrganizationState.accountability(State.ORG),"revoked_at":-1}
		if not core.add_authority_grant(grant):return "TRAINING_GRANT_FAILED"
	if not core.add_power_relation({"relation_id":"relation:training_1900_supervision","relation_type":"supervision","source_entity":leader,"target_entity":State.NPC,"represented_organization_id":State.ORG,"scope":{"area_id":State.AREA,"operations":["military.training.issue","military.training.execute","military.training.report"]},"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":State.SOURCE}}):return "TRAINING_SUPERVISION_FAILED"
	world_value.military_state.training_group={"schema":State.SCHEMA,"source":State.SOURCE,"area":State.AREA,"organization":State.ORG,"anchor":"place:paris","leader":leader,"observer":State.NPC,"leader_claim":world_value.person_overlay.person(leader).claim_id,"observer_claim":observer.claim_id,"position":State.HOME,"travelled":0.0,"physics_steps":0,"elapsed_usec":0,"order":{}}
	return State.references_error(world_value)

func bind(w: WorldState, executor: Node3D) -> String:
	world=w;_executor=weakref(executor)
	return State.references_error(world)

func authorize(op: String, supplied_context: Dictionary={}) -> Dictionary:
	var d: Dictionary=world.military_state.training_group
	if d.is_empty() or op not in State.OPS:return {"ok":false,"reason":"NO_EXPLICIT_TRAINING_GROUP"}
	var leader_op: bool=op in ["issue","receive"]
	var person: String=d.leader if leader_op else d.observer
	var role: String="training_leader" if leader_op else "training_observer"
	var context:=supplied_context if not supplied_context.is_empty() else OrganizationState.acting_context(person,State.ORG,State.ORG,"authority.training_1900."+op,role,true)
	if context.get("person_id")!=person or not world.person_overlay.is_alive(person) or world.person_overlay.current_place(person)!=d.anchor or (world.person_travel!=null and world.person_travel.is_in_transit(person)):return {"ok":false,"reason":"TRAINING_PERSON_NOT_PRESENT"}
	var resolution:=world.authorization_check.resolve_authority(context,"military.training."+op,AuthorizationCheck.STAGE_DOMAIN_EXECUTION,State.AREA,d.anchor,d.observer,1.0,world.game_clock.current_hour())
	return {"ok":resolution.status==AuthorizationCheck.ALLOWED,"reason":"TRAINING_PERMISSION_DENIED" if resolution.status!=AuthorizationCheck.ALLOWED else "","proof":{"operation":"military.training."+op,"resolution":resolution}}

func issue(executor: Node3D) -> Dictionary:
	if _executor.get_ref()!=executor:return {"ok":false,"reason":"UNBOUND_EXECUTOR"}
	var d: Dictionary=world.military_state.training_group
	var a:=authorize("issue");var e:=authorize("execute")
	if not a.ok:return a
	if not e.ok:return e
	if not d.order.is_empty():return {"ok":true,"duplicate":true}
	var distance: float=executor.npc.position.distance_to(executor.host.actor.position)
	if distance>5 or not executor.face_clear():return {"ok":false,"reason":"ORDER_NOT_DELIVERABLE_FACE_TO_FACE"}
	var candidate:=d.duplicate(true)
	candidate.order={"id":State.ORDER,"issuer":d.leader,"executor":d.observer,"issued_minute":world.game_clock.total_minutes(),"status":"OUTBOUND","issue_authority":a.proof,"execute_authority":e.proof,"issued_distance":distance,"issued_clear":true,"observation":{},"report":{}}
	return commit(candidate)

func observe(executor: Node3D, hit: Dictionary, origin: Vector3) -> Dictionary:
	if _executor.get_ref()!=executor:return {"ok":false,"reason":"UNBOUND_EXECUTOR"}
	var d: Dictionary=world.military_state.training_group
	var a:=authorize("execute")
	if not a.ok:return a
	if d.order.get("status")!="OUTBOUND" or d.position.distance_to(State.TARGET)>0.4 or hit.is_empty() or not is_instance_valid(hit.get("collider")) or hit.collider.get_meta("practice_target_id","")!="practice_target:board_01" or origin.distance_to(hit.position)>20:return {"ok":false,"reason":"OBSERVATION_NOT_PHYSICALLY_OBTAINED"}
	var candidate:=d.duplicate(true)
	candidate.order.observation={"observer":d.observer,"target":"practice_target:board_01","origin":origin,"endpoint":hit.position,"normal":hit.normal,"distance":origin.distance_to(hit.position),"mask":169,"physics_steps":d.physics_steps,"elapsed_usec":d.elapsed_usec,"visibility":"OBSERVER_PRIVATE_UNTIL_FACE_TO_FACE_REPORT","execute_authority":a.proof}
	candidate.order.status="RETURNING"
	return commit(candidate)

func report(executor: Node3D) -> Dictionary:
	if _executor.get_ref()!=executor:return {"ok":false,"reason":"UNBOUND_EXECUTOR"}
	var d: Dictionary=world.military_state.training_group
	var a:=authorize("report");var receive:=authorize("receive")
	if not a.ok:return a
	if not receive.ok:return receive
	if d.order.get("status")!="RETURNING":return {"ok":false,"reason":"NO_OBSERVATION_TO_REPORT"}
	var leader_position: Vector3=executor.host.actor.position
	var distance: float=d.position.distance_to(leader_position)
	if distance>5 or not executor.face_clear():return {"ok":false,"reason":"REPORT_NOT_DELIVERABLE_FACE_TO_FACE"}
	var candidate:=d.duplicate(true)
	candidate.order.report={"id":State.ORDER+":report:1","sender":d.observer,"recipient":d.leader,"channel":"FACE_TO_FACE_LOS_5M","distance":distance,"clear":true,"delivered_minute":world.game_clock.total_minutes(),"elapsed_usec":d.elapsed_usec,"sender_position":d.position,"recipient_position":leader_position,"report_authority":a.proof,"receive_authority":receive.proof,"observation":d.order.observation.duplicate(true)}
	candidate.order.status="REPORTED"
	return commit(candidate)

func commit(candidate: Dictionary) -> Dictionary:
	var reason:=State.error(candidate)
	if not reason.is_empty():return {"ok":false,"reason":reason}
	world.military_state.training_group=candidate
	return {"ok":true,"status":candidate.order.get("status","IDLE")}
