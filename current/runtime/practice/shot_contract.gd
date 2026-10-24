extends RefCounted
## Persisted facts from the existing infantry muzzle ray. No hit or inventory owner.
const SCHEMA := "formal_equipment_practice_shot_v1"
const AREA := "practice_area:depot_1900_range_v1"
const TIME_CONTRACT := "DISCRETE_PRACTICE_SAME_FORMAL_MINUTE"
const FIELDS := ["schema","shot_id","person_id","asset_id","lot_id","source_id","area_id","anchor_place_id","minute","input_id","physics_frame","actor_shot_sequence","body_position","origin","direction","endpoint","normal","hit_id","target_kind","collision_model","collision_mask","max_range","native_preparation_usec","time_contract","carry_context","fire_context"]

static func error(p: Dictionary, receipt: Dictionary, event: Dictionary, source: Dictionary) -> String:
	if p.size()!=FIELDS.size() or not p.has_all(FIELDS) or p.schema!=SCHEMA:return "UNKNOWN_PHYSICAL_SHOT_SCHEMA_OR_FIELDS"
	if p.shot_id!=str(receipt.receipt_id)+":shot" or p.person_id!=event.actor_id or p.asset_id!=source.asset_id or p.lot_id!=source.lot_id or p.source_id!=source.source_id:return "PHYSICAL_SHOT_SOURCE_OR_ACTOR_MISMATCH"
	if p.area_id!=AREA or p.anchor_place_id!=source.place_id or p.minute!=event.minute or p.time_contract!=TIME_CONTRACT:return "PHYSICAL_SHOT_SCOPE_OR_TIME_MISMATCH"
	if p.collision_model!="GODOT_PHYSICS_MUZZLE_RAY" or p.collision_mask!=169 or p.max_range!=125.0 or p.native_preparation_usec not in [0,1000]:return "UNSUPPORTED_PHYSICAL_SHOT_MODEL"
	if not p.input_id is String or p.input_id.is_empty() or not p.physics_frame is int or p.physics_frame<1 or not p.actor_shot_sequence is int or p.actor_shot_sequence<1:return "INVALID_PHYSICAL_INPUT_SEQUENCE"
	for key: String in ["body_position","origin","direction","endpoint","normal"]:
		if not p[key] is Vector3 or not (p[key] as Vector3).is_finite():return "INVALID_PHYSICAL_SHOT_GEOMETRY"
	if absf(p.direction.length()-1.0)>0.00001 or p.origin.distance_to(p.endpoint)>125.0001:return "INVALID_PHYSICAL_SHOT_RAY"
	if (p.endpoint-p.origin).length()>0.001 and (p.endpoint-p.origin).normalized().dot(p.direction)<0.99999:return "PHYSICAL_SHOT_NOT_ON_MUZZLE_AXIS"
	if absf(p.body_position.x)>8.0 or p.body_position.z>12.0 or p.body_position.z< -5.0:return "OUTSIDE_REGISTERED_PRACTICE_FOOTPRINT"
	if p.hit_id not in ["","practice_target:board_01","practice_target:backstop","practice_target:ground"] or p.target_kind!=("LEGAL_MISS_NO_POPULATION" if p.hit_id=="" else "SYNTHETIC_NON_POPULATION"):return "UNREGISTERED_PRACTICE_TARGET"
	for operation: String in ["carry","fire"]:
		var context: Variant=p[operation+"_context"]
		if not context is Dictionary or context.size()!=8 or not context.has_all(["person_id","acting_organization_id","appointment_id","membership_basis","represented_organization_id","authority_basis","decision_id","delegation_id"]) or context.get("person_id")!=p.person_id or context.get("represented_organization_id")!=source.owner_id or context.get("appointment_id")!="practice_qualification":return "INVALID_PRACTICE_AUTHORIZATION_CONTEXT"
	return ""

static func references_error(world: WorldState, physical: Dictionary) -> String:
	for operation: String in ["carry","fire"]:
		var context: Dictionary=physical[operation+"_context"]
		var grant:=world.organization_state.authority_grant(str(context.authority_basis))
		if grant.get("operation")!="military.practice."+operation or not grant.get("target_scope",[]).has(AREA) or not grant.get("spatial_scope",[]).has(physical.anchor_place_id) or not grant.get("subject_scope",[]).has(physical.person_id):return "UNKNOWN_PRACTICE_AUTHORITY_REFERENCE"
	return ""
