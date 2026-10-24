extends RefCounted
const CombatState=preload("res://scripts/vnext/military/military_combat_authority_state.gd")
const State=preload("res://scripts/vnext/military/military_delegation_state.gd")
var world: WorldState
var persistence: FormalPersistence
func bind(w: WorldState,p: FormalPersistence) -> String:
	world=w;persistence=p
	return State.references_error(w)
func state() -> Dictionary:return world.military_state.local_delegation
func fail(reason: String) -> Dictionary:return {"ok":false,"reason":reason}
func available() -> bool:return not persistence.is_save_in_progress()
func register_controlled_annex() -> Dictionary:
	if not available():return fail("SAVE_IN_PROGRESS")
	if not state().is_empty():return {"ok":true,"duplicate":true}
	var d: Dictionary=world.military_state.duty_operations
	if d.is_empty() or not State.Duty.references_error(world).is_empty():return fail("NO_VALID_DUTY_SOURCE")
	if not d.active.is_empty():return fail("DUTY_LEASE_ACTIVE")
	var bodies: Dictionary={}
	for person: String in [d.leader,d.executor]:
		bodies[person]={"person":person,"claim":world.person_overlay.person(person).claim_id,"identity_owner":"PersonOverlay+PopulationState","medical_status":"UNMAPPED"}
	world.military_state.local_delegation={"schema":State.SCHEMA,"source":State.SOURCE,"unit":d.unit,"region":{"id":d.area+":controlled","anchor":d.anchor,"source_area":d.area,"source_charter":d.source,"kind":"CONTROLLED_NONCOMBAT_ANNEX","metres_per_unit":1,"origin":Vector3.ZERO,"minimum":Vector3(-90,-0.2,-90),"maximum":Vector3(90,3,90),"historical_geography":false},"bodies":bodies,"leases":[],"requests":{}}
	return {"ok":true,"medical_status":"UNMAPPED","combat_authorized":false}
func attach_projection(person: String,node: Node3D,resume_id: String="") -> Dictionary:
	if not available():return fail("SAVE_IN_PROGRESS")
	var d:=state()
	if d.is_empty() or not d.bodies.has(person) or not is_instance_valid(node) or node.get_meta("formal_person_id","")!=person:return fail("BODY_IDENTITY_MISMATCH")
	if not State.contains(d.region,node.position):return fail("OUTSIDE_REGISTERED_REGION")
	if not world.person_overlay.is_alive(person) or world.person_overlay.current_place(person)!=d.region.anchor or world.person_travel.is_in_transit(person):return fail("PERSON_NOT_PRESENT")
	if not world.military_state.duty_operations.active.is_empty() or not world.military_state.local_operations.get("active",{}).is_empty():return fail("OTHER_LOCAL_LEASE_ACTIVE")
	for custody: Dictionary in world.military_state.material_registry.get("view",{}).get("leases",{}).values():
		if custody.status in ["reserved","issued"]:return fail("MATERIAL_CUSTODY_ACTIVE")
	var bindings: Dictionary=world.military_state.delegation_bindings
	for l: Dictionary in d.leases:
		if l.person!=person or l.status!="ACTIVE":continue
		if bindings.has(l.id) and bindings[l.id].get_ref()!=null:return fail("BODY_ALREADY_PROJECTED")
		if resume_id!=l.id or node.position!=l.position:return fail("EXPLICIT_SAVED_PROJECTION_REQUIRED")
		bindings[l.id]=weakref(node)
		return {"ok":true,"lease":l.id,"resumed":true}
	if not resume_id.is_empty():return fail("UNKNOWN_OR_RELEASED_PROJECTION")
	if d.leases.size()>=128:return fail("PROJECTION_HISTORY_LIMIT")
	var id: String="projection:"+str(d.leases.size()+1)
	d.leases.append({"id":id,"person":person,"claim":d.bodies[person].claim,"region":d.region.id,"position":node.position,"status":"ACTIVE","begin_minute":world.game_clock.total_minutes(),"end_minute":-1})
	bindings[id]=weakref(node)
	return {"ok":true,"lease":id,"resumed":false}
func release_projection(id: String,node: Node3D) -> Dictionary:
	if not available():return fail("SAVE_IN_PROGRESS")
	var bindings: Dictionary=world.military_state.delegation_bindings
	if not bindings.has(id) or bindings[id].get_ref()!=node:return fail("NOT_PROJECTION_OWNER")
	for l: Dictionary in state().leases:
		if l.id==id and l.status=="ACTIVE":
			if node.position!=l.position:return fail("UNACCOUNTED_PROJECTION_MOVEMENT")
			l.status="RELEASED";l.end_minute=world.game_clock.total_minutes();bindings.erase(id)
			return {"ok":true}
	return fail("UNKNOWN_OR_RELEASED_PROJECTION")
func request_combat(q: Dictionary,context: Dictionary) -> Dictionary:
	if not available():return fail("SAVE_IN_PROGRESS")
	var d:=state()
	if d.is_empty():return fail("NO_REGISTERED_ANNEX")
	var e:=State.request_error(d,q)
	if not e.is_empty():return fail(e)
	if d.requests.has(q.id):
		if d.requests[q.id].request!=q:return fail("CONFLICTING_DELEGATION_REQUEST")
		return {"ok":true,"duplicate":true,"decision":d.requests[q.id].duplicate(true)}
	var duty: Dictionary=world.military_state.duty_operations
	if q.issuer!=duty.leader or q.settlement_owner!=(CombatState.ORG if not world.military_state.combat_authority.is_empty() else duty.organization) or context.get("person_id")!=q.issuer:return fail("INVALID_SETTLEMENT_RESPONSIBILITY")
	if q.from_minute!=world.game_clock.total_minutes():return fail("REQUEST_TIME_MISMATCH")
	if not duty.active.is_empty() or not world.military_state.local_operations.get("active",{}).is_empty():return fail("OTHER_LOCAL_LEASE_ACTIVE")
	if d.requests.size()>=64:return fail("REQUEST_HISTORY_LIMIT")
	var resolution:=world.authorization_check.resolve_authority(context,"military.combat.delegate",AuthorizationCheck.STAGE_DELEGATION,d.unit,d.region.anchor,duty.executor,1.0,world.game_clock.current_hour())
	var blockers: Array=State.BLOCKERS.duplicate()
	var installed: bool=not world.military_state.combat_authority.is_empty()
	var qualified: bool=installed and CombatState.qualified(world)
	if qualified:blockers.erase("NAMED_UNIT_NONCOMBAT_ONLY")
	if resolution.status!=AuthorizationCheck.ALLOWED:blockers.append("NO_COMBAT_DELEGATION_AUTHORITY")
	# Recording a rejected request never issues an order, allocates ammo, or adopts time.
	var decision: Dictionary={"request":q.duplicate(true),"minute":world.game_clock.total_minutes(),"status":"FORMAL_COMBAT_NOT_READY","blockers":blockers,"authority":resolution.duplicate(true)}
	if installed:
		d.schema=State.AUTHORITY_SCHEMA
		decision.qualification_source=CombatState.SOURCE if qualified else ""
	d.requests[q.id]=decision
	return {"ok":true,"duplicate":false,"decision":decision.duplicate(true)}
func apply_injury(_lease: String,_receipt: Dictionary) -> Dictionary:
	return fail("NO_FORMAL_BODY_MEDICAL_AUTHORITY")
func adopt_combat_result(_request_id: String,_receipt: Dictionary) -> Dictionary:
	return fail("NO_AUTHORIZED_COMBAT_EXECUTION")
