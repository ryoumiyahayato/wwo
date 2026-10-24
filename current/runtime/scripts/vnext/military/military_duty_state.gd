extends RefCounted
## Named personnel duties live in MilitaryState. Time remains in GameClock.
const SCHEMA := "formal_noncombat_duties_v1"
const OPS := ["issue","execute","report","receive"]
static func keys(v: Variant, fields: Array) -> bool:
	return v is Dictionary and v.size()==fields.size() and v.has_all(fields)
static func point(v: Variant) -> bool:
	return v is Vector3 and is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and absf(v.x)<=90 and absf(v.z)<=90 and v.y>=-0.2 and v.y<=3
static func allowed(v: Variant, op: String) -> bool:
	return keys(v,["operation","resolution"]) and v.operation=="military.duty."+op and v.resolution is Dictionary and v.resolution.get("status")==AuthorizationCheck.ALLOWED
static func num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))
static func nat(v: Variant) -> bool:
	return v is int and v>=0
static func error(d: Dictionary) -> String:
	if d.is_empty():return ""
	if not keys(d,["schema","source","unit","organization","anchor","area","mapping","leader","executor","leader_position","position","orders","active","next_order","pending_usec"]):return "UNKNOWN_DUTY_FIELDS"
	for k: String in ["source","unit","organization","anchor","area","leader","executor"]:
		if not d[k] is String or d[k].is_empty():return "INVALID_DUTY_ID_TYPE"
	if not d.organization.begins_with("organization:") or not d.anchor.begins_with("place:") or not d.leader.begins_with("person:") or not d.executor.begins_with("person:"):return "INVALID_DUTY_ID_KIND"
	if d.schema!=SCHEMA or not d.source is String or not d.source.begins_with("scenario:") or not d.unit is String or not d.unit.begins_with("formation:") or d.leader==d.executor or not point(d.position) or not point(d.leader_position):return "INVALID_DUTY_IDENTITY_OR_POSE"
	if not keys(d.mapping,["kind","anchor_place","metres_per_unit","home","plans"]) or d.mapping.kind!="FICTIONAL_NONCOMBAT_AREA_NOT_HISTORICAL_DEM" or d.mapping.anchor_place!=d.anchor or d.mapping.metres_per_unit!=1 or not point(d.mapping.home) or not d.mapping.plans is Dictionary or d.mapping.plans.is_empty():return "INVALID_DUTY_MAPPING"
	for id: Variant in d.mapping.plans:
		var p: Variant=d.mapping.plans[id]
		if not keys(p,["id","kind","route","target_id","target_position","max_observation_distance"]) or not id is String or not p.target_id is String or p.target_id.is_empty() or not num(p.max_observation_distance) or p.id!=id or p.kind!="INSPECT_AND_REPORT" or not p.route is Array or p.route.size()<1 or p.route.size()>16 or not point(p.target_position) or p.max_observation_distance<1 or p.max_observation_distance>20:return "INVALID_DUTY_PLAN"
		for q: Variant in p.route:
			if not point(q):return "INVALID_DUTY_WAYPOINT"
	if not d.pending_usec is int or d.pending_usec<0 or d.pending_usec>=60000000:return "INVALID_DUTY_CARRY"
	if not d.orders is Dictionary or d.orders.size()>64 or not d.next_order is int or d.next_order!=d.orders.size()+1 or not d.active is String or (not d.active.is_empty() and not d.orders.has(d.active)):return "INVALID_DUTY_ORDERS"
	var order_index:=0;var carried:=0;var previous_end:= -1
	for id: Variant in d.orders:
		order_index+=1
		if id!=d.unit+":duty:"+str(order_index):return "INVALID_DUTY_SEQUENCE"
		var o: Variant=d.orders[id]
		if not keys(o,["id","plan","issuer","executor","phase","issued_minute","issue_authority","execute_authority","issued_distance","issued_clear","waypoint","physics_steps","travelled","elapsed_usec","accounted_usec","carry_in_usec","pending_usec","advanced_minutes","receipts","observation","report","failure"]):return "UNKNOWN_DUTY_ORDER_FIELDS"
		if o.id!=id or not str(id).begins_with(d.unit+":duty:") or not d.mapping.plans.has(o.plan) or o.issuer!=d.leader or o.executor!=d.executor or o.phase not in ["OUTBOUND","RETURNING","REPORTED","BLOCKED"] or not o.issued_minute is int or o.issued_minute<0 or o.issued_clear!=true or not o.issued_distance is float or not is_finite(o.issued_distance) or o.issued_distance<0 or o.issued_distance>5 or not allowed(o.issue_authority,"issue") or not allowed(o.execute_authority,"execute"):return "INVALID_DUTY_ORDER"
		if not o.waypoint is int or o.waypoint< -1 or o.waypoint>d.mapping.plans[o.plan].route.size() or not o.physics_steps is int or o.physics_steps<0 or not o.travelled is float or not is_finite(o.travelled) or o.travelled<0:return "INVALID_DUTY_MOTION"
		for k: String in ["elapsed_usec","accounted_usec","carry_in_usec","pending_usec","advanced_minutes"]:
			if not o[k] is int or o[k]<0:return "INVALID_DUTY_TIME"
		if o.accounted_usec>o.elapsed_usec or o.pending_usec>=60000000 or o.accounted_usec+o.carry_in_usec!=o.advanced_minutes*60000000+o.pending_usec or o.carry_in_usec>=60000000 or o.elapsed_usec>1800000000 or not o.receipts is Array or o.receipts.size()>128:return "DUTY_TIME_CONSERVATION_FAILED"
		var prior_usec:=0;var minutes:=0
		for i: int in o.receipts.size():
			var r: Variant=o.receipts[i]
			if not keys(r,["id","order","sequence","elapsed_usec","from_minute","to_minute","advanced_minutes","pending_usec","position","physics_steps","phase"]) or r.id!=str(id)+":checkpoint:"+str(i+1) or r.order!=id or r.sequence!=i+1 or not r.elapsed_usec is int or r.elapsed_usec<prior_usec or r.elapsed_usec>o.elapsed_usec or not point(r.position) or not r.physics_steps is int or r.physics_steps<0 or r.physics_steps>o.physics_steps or r.phase not in ["OUTBOUND","RETURNING","REPORTED","BLOCKED"]:return "INVALID_DUTY_RECEIPT"
			for k: String in ["from_minute","to_minute","advanced_minutes","pending_usec"]:
				if not nat(r[k]):return "INVALID_DUTY_RECEIPT_TIME_TYPE"
			if r.from_minute!=o.issued_minute+minutes or r.to_minute!=o.issued_minute+int((o.carry_in_usec+r.elapsed_usec)/60000000) or r.advanced_minutes!=r.to_minute-r.from_minute or r.pending_usec!=(o.carry_in_usec+r.elapsed_usec)%60000000:return "DUPLICATE_OR_MISSING_DUTY_TIME"
			prior_usec=r.elapsed_usec;minutes+=r.advanced_minutes
		if o.carry_in_usec!=carried or o.issued_minute<previous_end:return "DUTY_INTERVAL_OVERLAP_OR_LOST_FRACTION"
		carried=o.pending_usec;previous_end=o.issued_minute+o.advanced_minutes
		if prior_usec!=o.accounted_usec or minutes!=o.advanced_minutes:return "DUTY_ADOPTION_CURSOR_MISMATCH"
		if not o.observation is Dictionary or not o.report is Dictionary or not o.failure is Dictionary:return "INVALID_DUTY_INFORMATION"
		if o.phase=="OUTBOUND" and (not o.observation.is_empty() or not o.report.is_empty()):return "PREMATURE_DUTY_INFORMATION"
		if not o.observation.is_empty():
			var b: Dictionary=o.observation;var p: Dictionary=d.mapping.plans[o.plan]
			if not keys(b,["observer","target","origin","endpoint","normal","distance","mask","elapsed_usec","physics_steps","authority","visibility"]) or b.observer!=d.executor or b.target!=p.target_id or b.mask!=9 or not point(b.origin) or not point(b.endpoint) or not b.normal is Vector3 or not b.normal.is_finite() or absf(b.normal.length()-1)>0.01 or b.endpoint.distance_to(p.target_position)>2 or b.origin.distance_to(p.route.back()+Vector3(0,1.5,0))>0.6 or not b.distance is float or not is_finite(b.distance) or b.distance>p.max_observation_distance or absf(b.origin.distance_to(b.endpoint)-b.distance)>0.01 or not nat(b.elapsed_usec) or not nat(b.physics_steps) or b.distance<0 or b.elapsed_usec<1 or b.elapsed_usec>o.elapsed_usec or b.physics_steps<1 or b.physics_steps>o.physics_steps or not allowed(b.authority,"execute") or b.visibility!="EXECUTOR_PRIVATE_UNTIL_DELIVERED":return "UNBACKED_DUTY_OBSERVATION"
		if o.phase in ["RETURNING","REPORTED"] and o.observation.is_empty():return "MISSING_DUTY_OBSERVATION"
		if o.phase!="REPORTED" and not o.report.is_empty():return "UNDELIVERED_DUTY_REPORT"
		if o.phase=="REPORTED":
			var r: Dictionary=o.report
			if not keys(r,["id","sender","recipient","channel","clear","distance","sender_position","recipient_position","elapsed_usec","minute","observation","report_authority","receive_authority"]) or r.id!=str(id)+":report" or r.sender!=d.executor or r.recipient!=d.leader or r.channel!="FACE_TO_FACE_LOS_5M" or r.clear!=true or not point(r.sender_position) or not point(r.recipient_position) or not r.distance is float or not is_finite(r.distance) or r.distance<0 or r.distance>5 or not nat(r.elapsed_usec) or not nat(r.minute) or absf(r.sender_position.distance_to(r.recipient_position)-r.distance)>0.01 or r.elapsed_usec!=o.elapsed_usec or r.minute!=o.issued_minute+int((o.carry_in_usec+o.elapsed_usec)/60000000) or r.observation!=o.observation or not allowed(r.report_authority,"report") or not allowed(r.receive_authority,"receive"):return "INVALID_DUTY_REPORT"
		if o.phase=="BLOCKED":
			if not keys(o.failure,["reason","elapsed_usec","position"]) or str(o.failure.reason).is_empty() or o.failure.elapsed_usec!=o.elapsed_usec or not point(o.failure.position):return "INVALID_DUTY_FAILURE"
		elif not o.failure.is_empty():return "UNBACKED_DUTY_FAILURE"
		if id!=d.active and o.phase not in ["REPORTED"]:return "UNOWNED_DUTY_INTERVAL"
	if d.pending_usec!=(carried if d.active.is_empty() else 0):return "DUTY_CARRY_OWNER_MISMATCH"
	return ""

static func references_error(w: WorldState) -> String:
	var d: Dictionary=w.military_state.duty_operations
	var e:=error(d)
	if not e.is_empty() or d.is_empty():return e
	if w.spatial_world.get_place(d.anchor).is_empty():return "DUTY_ANCHOR_MISSING"
	var unit:=w.military_state.get_formation(d.unit)
	if unit==null or unit.named_personnel.is_empty() or unit.named_personnel.source!=d.source or unit.named_personnel.organization!=d.organization or unit.named_personnel.anchor!=d.anchor or unit.named_personnel.members.size()!=2:return "DUTY_NAMED_UNIT_MISSING"
	var seen: Dictionary={}
	for f_id: String in w.military_state.get_sorted_formation_ids():
		var f:=w.military_state.get_formation(f_id)
		for id: Variant in f.named_personnel.get("members",{}):
			if seen.has(id):return "PERSON_IN_MULTIPLE_NAMED_UNITS"
			seen[id]=true
			var member: Dictionary=f.named_personnel.members[id];var p:=w.person_overlay.person(id)
			if p.get("claim_id")!=member.claim_id or w.population_state.unit_for_person(id)!=p.get("population_territory_id"):return "NAMED_UNIT_CLAIM_MISMATCH"
	if not unit.named_personnel.members.has_all([d.leader,d.executor]):return "DUTY_ROLE_IDENTITY_MISMATCH"
	for id: String in [d.leader,d.executor]:
		var role: String="duty_leader" if id==d.leader else "duty_observer"
		if unit.named_personnel.members[id].role!=role:return "DUTY_ROLE_MISMATCH"
		# Revoked authority and absent appointments remain loadable; execution rechecks them.
		if not w.organization_state.has_organization(d.organization):return "DUTY_ORGANIZATION_MISSING"
	if not d.active.is_empty():
		var o: Dictionary=d.orders[d.active]
		if w.game_clock.total_minutes()!=o.issued_minute+o.advanced_minutes:return "DUTY_WORLD_TIME_MISMATCH"
	return ""
