extends RefCounted
## References and projection custody only. This is not a medical authority or combat solver.
const SCHEMA := "formal_local_delegation_prerequisites_v1"
const AUTHORITY_SCHEMA := "formal_local_delegation_prerequisites_v2"
const CombatState=preload("res://scripts/vnext/military/military_combat_authority_state.gd")
const SOURCE := "scenario:explicit_controlled_annex_registration_20261023"
const Duty = preload("res://scripts/vnext/military/military_duty_state.gd")
const BLOCKERS := ["NAMED_UNIT_NONCOMBAT_ONLY","NO_FORMAL_BODY_MEDICAL_AUTHORITY","CONTROLLED_AREA_NOT_COMBAT_REGISTERED","NO_COMBAT_MATERIAL_ASSIGNMENT","NO_LOCAL_COMBAT_EXECUTION_CONTRACT"]
static func keys(v: Variant, fields: Array) -> bool:return Duty.keys(v,fields)
static func error(d: Dictionary) -> String:
	if d.is_empty():return ""
	if not keys(d,["schema","source","unit","region","bodies","leases","requests"]) or d.schema not in [SCHEMA,AUTHORITY_SCHEMA] or d.source!=SOURCE or not d.unit is String:return "DELEGATION_SCHEMA_OR_FIELDS"
	var r: Variant=d.region
	if not keys(r,["id","anchor","source_area","source_charter","kind","metres_per_unit","origin","minimum","maximum","historical_geography"]) or not r.id is String or not r.anchor is String or not r.source_area is String or not r.source_charter is String or r.kind!="CONTROLLED_NONCOMBAT_ANNEX" or r.metres_per_unit!=1 or r.origin!=Vector3.ZERO or r.minimum!=Vector3(-90,-0.2,-90) or r.maximum!=Vector3(90,3,90) or r.historical_geography!=false:return "DELEGATION_REGION_INVALID"
	if not d.bodies is Dictionary or d.bodies.size()!=2 or not d.leases is Array or d.leases.size()>128 or not d.requests is Dictionary or d.requests.size()>64:return "DELEGATION_COLLECTIONS_INVALID"
	var claims: Dictionary={}
	for person: Variant in d.bodies:
		var b: Variant=d.bodies[person]
		if not person is String or not keys(b,["person","claim","identity_owner","medical_status"]) or b.person!=person or not b.claim is String or b.claim.is_empty() or b.identity_owner!="PersonOverlay+PopulationState" or b.medical_status!="UNMAPPED" or claims.has(b.claim):return "DELEGATION_BODY_REFERENCE_INVALID"
		claims[b.claim]=true
	var active: Dictionary={}
	for i: int in d.leases.size():
		var l: Variant=d.leases[i]
		if not keys(l,["id","person","claim","region","position","status","begin_minute","end_minute"]) or l.id!="projection:"+str(i+1) or not d.bodies.has(l.person) or l.claim!=d.bodies[l.person].claim or l.region!=r.id or not contains(r,l.position) or l.status not in ["ACTIVE","RELEASED"] or not Duty.nat(l.begin_minute) or not l.end_minute is int:return "DELEGATION_PROJECTION_INVALID"
		if l.status=="ACTIVE":
			if l.end_minute!= -1 or active.has(l.person):return "DUPLICATE_BODY_PROJECTION"
			active[l.person]=true
		elif l.end_minute<l.begin_minute:return "DELEGATION_RELEASE_TIME_INVALID"
	for id: Variant in d.requests:
		var q: Variant=d.requests[id]
		if not q is Dictionary:return "DELEGATION_DECISION_INVALID"
		if not id is String or not keys(q,["request","minute","status","blockers","authority"]+(["qualification_source"] if q.has("qualification_source") else [])) or q.status!="FORMAL_COMBAT_NOT_READY" or not Duty.nat(q.minute) or not q.blockers is Array or not q.authority is Dictionary or q.authority.get("status") not in [AuthorizationCheck.DENIED,AuthorizationCheck.ERROR,AuthorizationCheck.ALLOWED]:return "DELEGATION_DECISION_INVALID"
		if not request_error(d,q.request).is_empty() or q.request.id!=id or q.request.from_minute!=q.minute:return "DELEGATION_REQUEST_INVALID"
		var expected: Array=BLOCKERS.duplicate()
		if q.has("qualification_source"):
			if d.schema!=AUTHORITY_SCHEMA or q.qualification_source not in ["",CombatState.SOURCE]:return "INVALID_HISTORICAL_QUALIFICATION"
			if q.qualification_source==CombatState.SOURCE:expected.erase("NAMED_UNIT_NONCOMBAT_ONLY")
		if q.authority.status!=AuthorizationCheck.ALLOWED:expected.append("NO_COMBAT_DELEGATION_AUTHORITY")
		if q.blockers!=expected:return "DELEGATION_BLOCKERS_INVALID"
	return ""
static func contains(region: Dictionary, p: Variant) -> bool:
	return p is Vector3 and p.is_finite() and p.x>=region.minimum.x and p.y>=region.minimum.y and p.z>=region.minimum.z and p.x<=region.maximum.x and p.y<=region.maximum.y and p.z<=region.maximum.z
static func request_error(d: Dictionary, q: Variant) -> String:
	if not keys(q,["id","unit","region","issuer","participants","from_minute","until_minute","settlement_owner","objective"]):return "REQUEST_FIELDS_INVALID"
	if not q.id is String or not q.id.begins_with("delegation_request:") or q.unit!=d.unit or q.region!=d.region.id or not d.bodies.has(q.issuer) or not q.participants is Array or q.participants.size()!=d.bodies.size():return "REQUEST_IDENTITY_INVALID"
	var seen: Dictionary={}
	for person: Variant in q.participants:
		if not d.bodies.has(person) or seen.has(person):return "REQUEST_PARTICIPANTS_INVALID"
		seen[person]=true
	if not Duty.nat(q.from_minute) or not Duty.nat(q.until_minute) or q.until_minute<=q.from_minute or q.until_minute-q.from_minute>5 or not q.settlement_owner is String or not q.settlement_owner.begins_with("organization:") or q.objective!="CONTROLLED_LOCAL_DEFENCE":return "REQUEST_INTERVAL_OR_RESPONSIBILITY_INVALID"
	return ""
static func references_error(w: WorldState) -> String:
	var d: Dictionary=w.military_state.local_delegation
	var e:=error(d)
	if not e.is_empty() or d.is_empty():return e
	var duty: Dictionary=w.military_state.duty_operations
	if duty.is_empty() or not Duty.references_error(w).is_empty() or d.unit!=duty.unit or d.region.id!=duty.area+":controlled" or d.region.anchor!=duty.anchor or d.region.source_area!=duty.area or d.region.source_charter!=duty.source or not w.spatial_world.catalog().has_place(d.region.anchor):return "DELEGATION_REGION_SOURCE_MISMATCH"
	var members: Dictionary=w.military_state.get_formation(d.unit).named_personnel.members
	if d.bodies.size()!=members.size():return "DELEGATION_MEMBER_COUNT_MISMATCH"
	for person: String in d.bodies:
		if not members.has(person) or d.bodies[person].claim!=members[person].claim_id or w.person_overlay.person(person).get("claim_id")!=d.bodies[person].claim:return "DELEGATION_PERSON_CLAIM_MISMATCH"
	for l: Dictionary in d.leases:
		if l.begin_minute>w.game_clock.total_minutes() or l.end_minute>w.game_clock.total_minutes():return "DELEGATION_FUTURE_PROJECTION"
	for q: Dictionary in d.requests.values():
		if q.get("qualification_source","")==CombatState.SOURCE and w.military_state.combat_authority.is_empty():return "MISSING_HISTORICAL_QUALIFICATION_SOURCE"
		if q.minute>w.game_clock.total_minutes() or q.request.issuer!=duty.leader or q.request.settlement_owner!=(CombatState.ORG if q.has("qualification_source") else duty.organization):return "DELEGATION_RESPONSIBILITY_MISMATCH"
	return ""
