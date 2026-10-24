extends RefCounted
## Explicit factory for a fresh, fictional 1900 depot. Never called by load/migration.
const State = preload("res://scripts/vnext/military/military_material_state.gd")

static func create_new(native_config: Dictionary={}) -> WorldBuildResult:
	var built:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,native_config)
	if not built.success:return built
	var w:=built.world;var c:=State.config();var core:=w.organization_state
	var year:=int(w.game_clock.current_date().get("year",-1))
	if year<int(c.year_min) or year>int(c.year_max):built.success=false;built.error="SCENARIO_ERA_MISMATCH";return built
	var id:=w.player_state.player_id()
	for org: String in [c.owner_id,c.receiver_id]:
		if not (core.register_organization(org,"military_institution",c.place_id) and core.define_position(org,"quartermaster","Scenario quartermaster",1) and core.add_member(org,id) and core.create_appointment(org,"initial_quartermaster",id,"quartermaster")):
			built.success=false;built.error="SCENARIO_ROLE_INITIALIZATION_FAILED";return built
		for operation: String in State.OPERATIONS:
			var stages: Array[String]=[AuthorizationCheck.STAGE_DOMAIN_EXECUTION]
			var grant: Dictionary={"authority_id":authority_id(org,operation),"holder":OrganizationState.position_holder(org,"quartermaster"),"represented_entity":org,"operation":"military.material."+operation,"target_scope":[c.asset_id],"spatial_scope":[c.place_id],"subject_scope":[id],"amount_or_quantity_limit":20.0,"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":c.source_id},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":OrganizationState.constraints(stages),"accountability":OrganizationState.accountability(org),"revoked_at":-1}
			if not core.add_authority_grant(grant):built.success=false;built.error="SCENARIO_GRANT_INITIALIZATION_FAILED";return built
	var event: Dictionary={"event_id":c.source_id+":event:1","sequence":1,"kind":"register","minute":0,"actor_id":"scenario_initializer","context":{},"payload":c}
	var registered:=State.append(State.empty(),event)
	if not registered.ok:built.success=false;built.error=registered.reason;return built
	w.military_state.material_registry=registered.state
	built.persistence._save_metadata=FormalWorldPersistenceDocument.next_metadata(built.persistence._save_metadata)
	built.persistence._save_metadata["military_scenario"]={"scenario_id":c.scenario_id,"source_kind":c.source_kind,"new_world_only":true}
	return built

static func authority_id(org: String,operation: String) -> String:
	return "authority.%s.%s"%[org.replace(":","."),operation]

static func context(world: WorldState,operation: String,owner: String="") -> Dictionary:
	if owner.is_empty():owner=world.military_state.material_registry.get("view",{}).get("asset",{}).get("owner_id","")
	return OrganizationState.acting_context(world.player_state.player_id(),owner,owner,authority_id(owner,operation),"initial_quartermaster",true)
