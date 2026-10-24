extends RefCounted
## Authorization, order transitions and unique time adoption over original owners.
const State = preload("res://scripts/vnext/military/military_duty_state.gd")
var world: WorldState
var step: SimulationStep
var persistence: FormalPersistence
var executor_ref: WeakRef
var adopting:=false

func bind(w: WorldState, s: SimulationStep, p: FormalPersistence, executor: Node3D) -> String:
	world=w;step=s;persistence=p;executor_ref=weakref(executor)
	step.local_operation_guard=Callable(self,"time_allowed")
	return State.references_error(world)
func time_allowed() -> bool:
	return not persistence.is_save_in_progress() and (adopting or persistence.world_time_available())
func state() -> Dictionary:return world.military_state.duty_operations
func current() -> Dictionary:
	var d:=state()
	return d.orders.get(d.active,{})
func authorize(op: String, context_value: Dictionary={}) -> Dictionary:
	var d:=state()
	if op not in State.OPS or d.is_empty():return fail("NO_FORMAL_DUTY_UNIT")
	var leader_op: bool=op in ["issue","receive"]
	var person: String=d.leader if leader_op else d.executor
	var role: String="duty_leader" if leader_op else "duty_observer"
	var a: Dictionary=context_value if not context_value.is_empty() else OrganizationState.acting_context(person,d.organization,d.organization,"authority."+d.unit.replace(":",".")+"."+op,role,true)
	if a.get("person_id")!=person or not world.person_overlay.is_alive(person) or world.person_overlay.current_place(person)!=d.anchor or (world.person_travel!=null and world.person_travel.is_in_transit(person)):return fail("DUTY_PERSON_ABSENT_OR_INCAPABLE")
	# A military assignment cannot erase or concurrently occupy civilian labor.
	if (world.economy_r1!=null and world.economy_r1._contracts.has(person)) or not world.personal_economy_state.employment(person).is_empty():return fail("CIVILIAN_EMPLOYMENT_CONFLICT")
	var r:=world.authorization_check.resolve_authority(a,"military.duty."+op,AuthorizationCheck.STAGE_DOMAIN_EXECUTION,d.unit,d.anchor,d.executor,1.0,world.game_clock.current_hour())
	return {"ok":r.status==AuthorizationCheck.ALLOWED,"reason":"DUTY_PERMISSION_DENIED" if r.status!=AuthorizationCheck.ALLOWED else "","proof":{"operation":"military.duty."+op,"resolution":r}}
func bound(node: Node3D) -> bool:
	return executor_ref!=null and executor_ref.get_ref()==node and not persistence.is_save_in_progress()
func issue(node: Node3D, plan_id: String) -> Dictionary:
	if not bound(node):return fail("UNBOUND_OR_SAVING_EXECUTOR")
	if world.military_state.has_projection_lease():return fail("BODY_PROJECTION_LEASE_ACTIVE")
	var d:=state()
	if not d.active.is_empty():return fail("DUTY_ALREADY_ACTIVE")
	if not d.mapping.plans.has(plan_id) or d.orders.size()>=64:return fail("DUTY_PLAN_OR_HISTORY_LIMIT")
	if not world.military_state.local_operations.get("active",{}).is_empty():return fail("OTHER_LOCAL_LEASE_ACTIVE")
	for c: Dictionary in world.military_state.material_registry.get("view",{}).get("leases",{}).values():
		if c.status in ["reserved","issued"]:return fail("MATERIAL_CUSTODY_ACTIVE")
	var a:=authorize("issue");var b:=authorize("execute")
	if not a.ok:return a
	if not b.ok:return b
	var distance: float=node.npc.position.distance_to(node.leader.position)
	if distance>5 or not node.face_clear():return fail("DUTY_ORDER_NOT_DELIVERED")
	var id: String=d.unit+":duty:"+str(d.next_order)
	d.next_order+=1;d.active=id
	d.orders[id]={"id":id,"plan":plan_id,"issuer":d.leader,"executor":d.executor,"phase":"OUTBOUND","issued_minute":world.game_clock.total_minutes(),"issue_authority":a.proof,"execute_authority":b.proof,"issued_distance":distance,"issued_clear":true,"waypoint":0,"physics_steps":0,"travelled":0.0,"elapsed_usec":0,"accounted_usec":0,"carry_in_usec":d.pending_usec,"pending_usec":d.pending_usec,"advanced_minutes":0,"receipts":[],"observation":{},"report":{},"failure":{}}
	d.pending_usec=0
	return {"ok":true,"order":id}
func observe(node: Node3D, hit: Dictionary, origin: Vector3) -> Dictionary:
	if not bound(node):return fail("UNBOUND_OR_SAVING_EXECUTOR")
	var d:=state();var o:=current();var a:=authorize("execute")
	if not a.ok:return a
	var plan: Dictionary=d.mapping.plans[o.plan]
	if o.phase!="OUTBOUND" or d.position.distance_to(plan.route.back())>0.4 or hit.is_empty() or not is_instance_valid(hit.get("collider")) or hit.collider.get_meta("duty_target_id","")!=plan.target_id or origin.distance_to(hit.position)>plan.max_observation_distance:return fail("DUTY_TARGET_NOT_OBSERVED")
	o.observation={"observer":d.executor,"target":plan.target_id,"origin":origin,"endpoint":hit.position,"normal":hit.normal,"distance":origin.distance_to(hit.position),"mask":9,"elapsed_usec":o.elapsed_usec,"physics_steps":o.physics_steps,"authority":a.proof,"visibility":"EXECUTOR_PRIVATE_UNTIL_DELIVERED"}
	o.phase="RETURNING";o.waypoint=plan.route.size()-2
	return {"ok":true}
func report(node: Node3D) -> Dictionary:
	if not bound(node):return fail("UNBOUND_OR_SAVING_EXECUTOR")
	var d:=state();var o:=current();var a:=authorize("report");var b:=authorize("receive")
	if not a.ok:return a
	if not b.ok:return b
	if o.is_empty() or o.phase!="RETURNING" or o.observation.is_empty():return fail("NO_DUTY_REPORT")
	var distance: float=node.npc.position.distance_to(node.leader.position)
	if distance>5 or not node.face_clear():return fail("DUTY_REPORT_UNDELIVERABLE")
	o.report={"id":str(o.id)+":report","sender":d.executor,"recipient":d.leader,"channel":"FACE_TO_FACE_LOS_5M","clear":true,"distance":distance,"sender_position":node.npc.position,"recipient_position":node.leader.position,"elapsed_usec":o.elapsed_usec,"minute":o.issued_minute+int((o.carry_in_usec+o.elapsed_usec)/60000000),"observation":o.observation.duplicate(true),"report_authority":a.proof,"receive_authority":b.proof}
	o.phase="REPORTED"
	return {"ok":true}
func block(reason: String) -> Dictionary:
	var o:=current()
	if o.is_empty():return fail("NO_ACTIVE_DUTY")
	o.phase="BLOCKED";o.failure={"reason":reason,"elapsed_usec":o.elapsed_usec,"position":state().position}
	return {"ok":true,"blocked":true,"reason":reason}

func checkpoint(node: Node3D, receipt: Dictionary={}) -> Dictionary:
	if not bound(node):return fail("UNBOUND_OR_SAVING_EXECUTOR")
	var d:=state()
	# Exact historical receipt is a no-op even after completion or in a new process.
	if not receipt.is_empty():
		for old: Dictionary in d.orders.values():
			for r: Dictionary in old.receipts:
				if r.id==receipt.get("id"):
					return {"ok":r==receipt,"duplicate":r==receipt,"reason":"CONFLICTING_DUTY_RECEIPT" if r!=receipt else "","advanced_minutes":0}
		return fail("UNKNOWN_DUTY_RECEIPT")
	var o:=current()
	if o.is_empty():return {"ok":true,"idle":true,"advanced_minutes":0}
	if world.game_clock.total_minutes()!=o.issued_minute+o.advanced_minutes:return fail("DUTY_WORLD_TIME_CONFLICT")
	var cumulative: int=o.carry_in_usec+o.elapsed_usec
	var minutes: int=int(cumulative/60000000)-o.advanced_minutes
	if minutes<0 or o.accounted_usec>o.elapsed_usec:return fail("DUTY_TIME_ROLLBACK")
	# One synchronous original boundary. No UI world-time action can interleave it.
	var started:=Time.get_ticks_usec()
	adopting=true
	var advanced:=step.advance_minutes(minutes)
	adopting=false
	if not advanced.get("success",true):return fail("DUTY_FORMAL_STEP_FAILED:"+str(advanced))
	var r: Dictionary={"id":str(o.id)+":checkpoint:"+str(o.receipts.size()+1),"order":o.id,"sequence":o.receipts.size()+1,"elapsed_usec":o.elapsed_usec,"from_minute":o.issued_minute+o.advanced_minutes,"to_minute":world.game_clock.total_minutes(),"advanced_minutes":minutes,"pending_usec":cumulative%60000000,"position":d.position,"physics_steps":o.physics_steps,"phase":o.phase}
	o.receipts.append(r);o.accounted_usec=o.elapsed_usec;o.advanced_minutes+=minutes;o.pending_usec=r.pending_usec
	if o.phase=="REPORTED":d.active="";d.pending_usec=o.pending_usec
	var e:=State.references_error(world)
	if not e.is_empty():return fail(e)
	return {"ok":true,"receipt":r.duplicate(true),"advanced_minutes":minutes,"step_result":advanced,"adoption_cpu_usec":Time.get_ticks_usec()-started}
func fail(reason: String) -> Dictionary:return {"ok":false,"reason":reason}
