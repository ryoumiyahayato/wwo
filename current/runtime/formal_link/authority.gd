extends RefCounted
## Read current domain facts. Existing defend authority never licenses a tank.
static func assess(world: WorldState,person_id: String) -> Dictionary:
	var known:=world.person_overlay.has_person(person_id)
	var controlled:=known and world.player_state.player_id()==person_id
	var alive:=known and world.person_overlay.is_alive(person_id)
	var in_transit:=known and world.person_travel!=null and world.person_travel.is_in_transit(person_id)
	var memberships:=world.organization_state.memberships_for_person(person_id) if known else []
	var appointments:=world.organization_state.appointments_for_person(person_id) if known else []
	var formations: Array[Dictionary]=[]
	for id: String in world.military_state.get_sorted_formation_ids():
		var f:=world.military_state.get_formation(id)
		formations.append({"formation_id":id,"affiliation_id":f.affiliation_id,"place_id":f.current_city_id,"personnel":f.personnel,"equipment_sets":f.equipment_sets.duplicate(true),"daily_requirements":f.daily_requirements.duplicate(true),"supply_fill":f.supply_fill.duplicate(true)})
	var authorizations: Array[Dictionary]=[]
	for appointment: Dictionary in appointments:
		var org:=str(appointment.organization_id)
		var context: Dictionary={"person_id":person_id,"acting_organization_id":org,"appointment_id":str(appointment.appointment_id),"membership_basis":bool(appointment.get("requires_membership",true)),"represented_organization_id":org,"authority_basis":"","decision_id":"","delegation_id":""}
		var bases: Array[String]=[""]
		for basis: String in world.organization_state.authority_ids():
			var grant:=world.organization_state.authority_grant(basis)
			if grant.get("represented_entity")==org and grant.get("operation")=="military.defend":bases.append(basis)
		for basis: String in bases:
			var scoped_context:=context.duplicate(true);scoped_context.authority_basis=basis
			for f: Dictionary in formations:
				var checked:=world.authorization_check.resolve_authority(scoped_context,"military.defend",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,str(f.formation_id),"","",0.0,world.game_clock.current_hour())
				authorizations.append({"operation":"military.defend","formation_id":f.formation_id,"context":scoped_context,"result":checked,"licenses_local_vehicle":false})
	var materials: Dictionary=world.military_state.material_registry
	var material_present:=not materials.is_empty()
	var reasons: Array[String]=[]
	if not controlled or not alive:reasons.append("NOT_CURRENT_ACTIVE_PERSON")
	if in_transit:reasons.append("PERSON_IN_TRANSIT")
	if appointments.is_empty():reasons.append("NO_MILITARY_APPOINTMENT")
	if formations.is_empty():reasons.append("NO_FORMAL_FORMATION")
	# The current registered vocabulary contains manage_appointments and defend.
	# Neither defines individual vehicle ownership, a loadout, or local combat scope.
	reasons.append("NO_FORMAL_COMBAT_VEHICLE_SOURCE" if material_present else "NO_COUNTED_VEHICLE_AND_AMMO_SOURCE")
	reasons.append("NO_FORMAL_CREW_OR_MEDICAL_MAPPING")
	reasons.append("NO_REGISTERED_LOCAL_COMBAT_OPERATION")
	reasons.append("NO_REGISTERED_BATTLEFIELD_GEOGRAPHY")
	return {"ok":false,"status":"TRAINING_ONLY" if controlled and alive and not in_transit else "DENIED","reason":reasons[0],"blockers":reasons,"person_id":person_id,"formal_player_known":known,"controlled":controlled,"alive":alive,"in_transit":in_transit,"place_id":world.person_overlay.current_place(person_id) if known else "","memberships":memberships,"appointments":appointments,"formation_count":formations.size(),"formations":formations,"aggregate_supply_inputs":world.military_state.supply_inputs.duplicate(true),"existing_domain_authorizations":authorizations,"counted_vehicle_registry_present":false,"material_registry_present":material_present,"material_source":materials.get("view",{}).get("source",{}).duplicate(true),"counted_ammunition_registry_present":material_present,"formal_individual_crew_present":false,"equipment_factor_is_vehicle_count":false,"formal_combat_ready":false,"source_contracts":["OrganizationState/AuthorizationCheck","VNextMilitaryState/VNextMilitaryFormation","strategic_military_overlay.json"],"world_minute":world.game_clock.total_minutes()}

static func explanation(assessment: Dictionary) -> String:
	var resource_text: String="已有场景步枪及弹药登记；没有正式载具与车组，不能委派现代坦克。" if assessment.get("material_registry_present",false) else "现有equipment_factor是效率系数。没有可追溯的逐车、车组和逐发库存。"
	return "TRAINING_ONLY\n人物：%s\n原世界地点：%s\n现有岗位%d / 编队%d\n\n%s\n\n%s\n现有military.defend权限不授权驾驶坦克。训练地图不代表巴黎实景。"%[assessment.person_id,assessment.place_id,assessment.appointments.size(),assessment.formation_count,"\n".join(assessment.blockers),resource_text]
