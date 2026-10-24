extends RefCounted
## Only explicit new-world construction installs practice qualifications.
const CustodyScenario = preload("res://custody/scenario.gd")
const MaterialLedger = preload("res://scripts/vnext/military/military_material_state.gd")
const Shot = preload("res://practice/shot_contract.gd")
const PRACTICE_ORGANIZATION := "organization:practice_1900_range"

static func create_new() -> WorldBuildResult:
	var built:=CustodyScenario.create_new(FormalEconomicOpening.for_source("country_fra"))
	if not built.success:return built
	var world:=built.world
	var core:=world.organization_state
	var source:=MaterialLedger.config()
	var person_id:=world.player_state.player_id()
	if not core.register_organization(PRACTICE_ORGANIZATION,"military_institution",source.place_id) or not core.define_position(PRACTICE_ORGANIZATION,"practice_shooter","Explicit 1900 range qualification",1) or not core.add_member(PRACTICE_ORGANIZATION,person_id) or not core.create_appointment(PRACTICE_ORGANIZATION,"practice_qualification",person_id,"practice_shooter"):
		built.success=false;built.error="PRACTICE_QUALIFICATION_INITIALIZATION_FAILED";return built
	for operation: String in ["carry","fire"]:
		var stages: Array[String]=[AuthorizationCheck.STAGE_DOMAIN_EXECUTION]
		var grant: Dictionary={"authority_id":authority_id(operation),"holder":OrganizationState.position_holder(PRACTICE_ORGANIZATION,"practice_shooter"),"represented_entity":source.owner_id,"operation":"military.practice."+operation,"target_scope":[Shot.AREA],"spatial_scope":[source.place_id],"subject_scope":[person_id],"amount_or_quantity_limit":1.0,"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":"charter:explicit_new_1900_practice_v1"},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":OrganizationState.constraints(stages,"","Fictional range only. No war/combat delegation."),"accountability":OrganizationState.accountability(source.owner_id),"revoked_at":-1}
		if not core.add_authority_grant(grant):built.success=false;built.error="PRACTICE_AUTHORITY_INITIALIZATION_FAILED";return built
	built.persistence._save_metadata.military_scenario["practice_area"]={"area_id":Shot.AREA,"anchor_place_id":source.place_id,"geometry":"FICTIONAL_FLAT_RANGE_NOT_FRANCE_DEM","time_contract":Shot.TIME_CONTRACT,"bounds_xz":[-8.0,-5.0,8.0,12.0],"prototype_parameters":true}
	built.persistence._save_metadata.military_scenario["practice_instance_id"]="%d-%d-%d"%[OS.get_process_id(),int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	var training_error: String=load("res://scripts/vnext/military/military_training_service.gd").initialize(world)
	if not training_error.is_empty():built.success=false;built.error=training_error
	return built

static func authority_id(operation: String) -> String:
	return "authority.practice_1900."+operation

static func context(world: WorldState, operation: String) -> Dictionary:
	var owner:=str(MaterialLedger.config().owner_id)
	return OrganizationState.acting_context(world.player_state.player_id(),PRACTICE_ORGANIZATION,owner,authority_id(operation),"practice_qualification",true)

static func authorize(world: WorldState, persistence: FormalPersistence, operation: String, context_value: Dictionary) -> Dictionary:
	var area: Dictionary=persistence._save_metadata.get("military_scenario",{}).get("practice_area",{})
	if area.get("area_id")!=Shot.AREA or area.get("anchor_place_id")!=MaterialLedger.config().place_id or area.get("geometry")!="FICTIONAL_FLAT_RANGE_NOT_FRANCE_DEM" or area.get("time_contract")!=Shot.TIME_CONTRACT:return {"ok":false,"reason":"NO_EXPLICIT_PRACTICE_SCENARIO"}
	var id:=world.player_state.player_id()
	if context_value.get("person_id")!=id or not world.person_overlay.is_alive(id) or world.person_overlay.current_place(id)!=area.anchor_place_id:return {"ok":false,"reason":"PRACTICE_PERSON_OR_PLACE_INVALID"}
	if world.person_travel!=null and world.person_travel.is_in_transit(id):return {"ok":false,"reason":"PRACTICE_PERSON_IN_TRANSIT"}
	var proof:=world.authorization_check.resolve_authority(context_value,"military.practice."+operation,AuthorizationCheck.STAGE_DOMAIN_EXECUTION,Shot.AREA,area.anchor_place_id,id,1.0,world.game_clock.current_hour())
	return {"ok":proof.status==AuthorizationCheck.ALLOWED,"reason":"PRACTICE_"+operation.to_upper()+"_PERMISSION_DENIED" if proof.status!=AuthorizationCheck.ALLOWED else "","authorization":proof}
