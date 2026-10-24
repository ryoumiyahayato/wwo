extends RefCounted
## Bounded training facts owned by MilitaryState. No inventory or world clock.
const SCHEMA := "formal_training_group_v1"
const SOURCE := "scenario:explicit_new_1900_range_group_v1"
const ORG := "organization:practice_1900_observation_unit"
const AREA := "practice_area:depot_1900_range_v1"
const NPC := "person:formal_generated_country_fra_0002"
const TARGET := Vector3(-4,0.05,-4)
const HOME := Vector3(-2,0.05,4)
const ORDER := "training_order:range_observe_0001"
const OPS := ["issue","execute","report","receive"]

static func keys(v: Variant, fields: Array) -> bool:
	return v is Dictionary and v.size()==fields.size() and v.has_all(fields)

static func point(v: Variant) -> bool:
	return vector(v) and absf(v.x)<=8 and v.y>=-0.1 and v.y<=3 and v.z>=-5 and v.z<=12

static func vector(v: Variant) -> bool:
	return v is Vector3 and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

static func error(d: Dictionary) -> String:
	if d.is_empty():return ""
	if not keys(d,["schema","source","area","organization","anchor","leader","observer","leader_claim","observer_claim","position","travelled","physics_steps","elapsed_usec","order"]):return "UNKNOWN_TRAINING_GROUP_FIELDS"
	if d.schema!=SCHEMA or d.source!=SOURCE or d.area!=AREA or d.organization!=ORG or d.anchor!="place:paris":return "UNKNOWN_TRAINING_GROUP_SOURCE"
	if d.leader!="person:formal_generated_country_fra_0001" or d.observer!=NPC or d.leader_claim!="formal_population_claim:country_fra:0001" or d.observer_claim!="formal_population_claim:country_fra:0002":return "INVALID_GROUP_IDENTITIES"
	if not point(d.position) or not d.travelled is float or not is_finite(d.travelled) or d.travelled<0 or not d.physics_steps is int or d.physics_steps<0 or not d.elapsed_usec is int or d.elapsed_usec<0:return "INVALID_GROUP_PHYSICAL_PROGRESS"
	if not d.order is Dictionary:return "INVALID_TRAINING_ORDER"
	var o: Dictionary=d.order
	if o.is_empty():return "" if d.physics_steps==0 and d.elapsed_usec==0 and d.travelled==0 and d.position==HOME else "UNORDERED_MOVEMENT"
	if not keys(o,["id","issuer","executor","issued_minute","status","issue_authority","execute_authority","issued_distance","issued_clear","observation","report"]):return "UNKNOWN_ORDER_FIELDS"
	if o.id!=ORDER or o.issuer!=d.leader or o.executor!=d.observer or not o.issued_minute is int or o.issued_minute<0 or o.status not in ["OUTBOUND","RETURNING","REPORTED"] or o.issued_clear!=true or not o.issued_distance is float or o.issued_distance>5 or o.issued_distance<0:return "INVALID_ORDER_OR_DELIVERY"
	if not is_finite(o.issued_distance) or not allowed(o.issue_authority,"issue") or not allowed(o.execute_authority,"execute"):return "INVALID_ORDER_AUTHORITY"
	if not o.observation is Dictionary or not o.report is Dictionary:return "INVALID_OBSERVATION_OR_REPORT"
	if o.status=="OUTBOUND":return "" if o.observation.is_empty() and o.report.is_empty() else "PREMATURE_KNOWLEDGE"
	var ob: Dictionary=o.observation
	if not keys(ob,["observer","target","origin","endpoint","normal","distance","mask","physics_steps","elapsed_usec","visibility","execute_authority"]):return "UNKNOWN_OBSERVATION_FIELDS"
	if ob.observer!=d.observer or ob.target!="practice_target:board_01" or ob.visibility!="OBSERVER_PRIVATE_UNTIL_FACE_TO_FACE_REPORT" or ob.mask!=169 or not vector(ob.origin) or not vector(ob.endpoint) or not vector(ob.normal):return "INVALID_OBSERVATION_SOURCE"
	if ob.origin.distance_to(TARGET+Vector3(0,1.5,0))>0.5 or not ob.distance is float or ob.distance<0 or ob.distance>20 or absf(ob.distance-ob.origin.distance_to(ob.endpoint))>0.01 or ob.endpoint.distance_to(Vector3(0,1.5,-22))>2:return "INVALID_OBSERVATION_GEOMETRY"
	if not is_finite(ob.distance) or absf(ob.normal.length()-1)>0.01:return "INVALID_OBSERVATION_GEOMETRY"
	if not allowed(ob.execute_authority,"execute") or not ob.physics_steps is int or ob.physics_steps<1 or ob.physics_steps>d.physics_steps or not ob.elapsed_usec is int or ob.elapsed_usec<1 or ob.elapsed_usec>d.elapsed_usec or d.travelled<7:return "UNBACKED_OBSERVATION"
	if o.status=="RETURNING":return "" if o.report.is_empty() else "PREMATURE_REPORT"
	var r: Dictionary=o.report
	if not keys(r,["id","sender","recipient","channel","distance","clear","delivered_minute","elapsed_usec","sender_position","recipient_position","report_authority","receive_authority","observation"]):return "UNKNOWN_REPORT_FIELDS"
	if r.id!=ORDER+":report:1" or r.sender!=d.observer or r.recipient!=d.leader or r.channel!="FACE_TO_FACE_LOS_5M" or r.clear!=true or not r.distance is float or r.distance>5 or r.distance<0 or not point(r.sender_position) or not point(r.recipient_position) or absf(r.distance-r.sender_position.distance_to(r.recipient_position))>0.01:return "INVALID_REPORT_DELIVERY"
	if not is_finite(r.distance) or r.sender_position!=d.position:return "REPORT_POSITION_MISMATCH"
	if not r.delivered_minute is int or r.delivered_minute<o.issued_minute or r.elapsed_usec!=d.elapsed_usec or r.elapsed_usec<ob.elapsed_usec or r.observation!=ob or d.travelled<12:return "INVALID_REPORT_CONTINUITY"
	if not allowed(r.report_authority,"report") or not allowed(r.receive_authority,"receive"):return "INVALID_REPORT_AUTHORITY"
	return ""

static func allowed(proof: Variant, op: String) -> bool:
	return keys(proof,["operation","resolution"]) and proof.operation=="military.training."+op and proof.resolution is Dictionary and proof.resolution.get("status")==AuthorizationCheck.ALLOWED

static func references_error(world: WorldState) -> String:
	var d: Dictionary=world.military_state.training_group
	var reason:=error(d)
	if not reason.is_empty() or d.is_empty():return reason
	for pair: Array in [[d.leader,d.leader_claim,"training_leader"],[d.observer,d.observer_claim,"training_observer"]]:
		var p:=world.person_overlay.person(pair[0])
		if p.get("claim_id")!=pair[1] or not p.get("alive",false) or p.get("current_place_id")!=d.anchor or world.population_state.unit_for_person(pair[0])!=p.get("population_territory_id"):return "TRAINING_PERSON_CLAIM_OR_PLACE_MISMATCH"
		var appointment:=world.organization_state.appointment(ORG,pair[2])
		if appointment.get("person_id")!=pair[0] or appointment.get("position_id")!=pair[2]:return "TRAINING_APPOINTMENT_MISMATCH"
	for op: String in OPS:
		var grant:=world.organization_state.authority_grant("authority.training_1900."+op)
		if grant.get("operation")!="military.training."+op or grant.get("represented_entity")!=ORG or grant.get("target_scope")!=[AREA] or grant.get("spatial_scope")!=[d.anchor] or grant.get("subject_scope")!=[d.observer] or grant.get("basis",{}).get("id")!=SOURCE:return "TRAINING_GRANT_MISMATCH"
	var relation:=world.organization_state.power_relation("relation:training_1900_supervision")
	if relation.get("source_entity")!=d.leader or relation.get("target_entity")!=d.observer or relation.get("represented_organization_id")!=ORG or relation.get("relation_type")!="supervision":return "TRAINING_SUPERVISION_MISMATCH"
	if not d.order.is_empty() and int(d.order.issued_minute)>world.game_clock.total_minutes():return "TRAINING_ORDER_FROM_FUTURE"
	return ""
