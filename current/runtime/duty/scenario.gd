extends RefCounted
## Explicit fictional scenario charter. Ordinary load/migration never calls this initializer.
const State = preload("res://scripts/vnext/military/military_duty_state.gd")
const SOURCE := "scenario:explicit_new_1900_paris_annex_duty_v1"
const UNIT := "formation:paris_annex_duty_section"
const ORG := "organization:paris_annex_duty_section"
const AREA := "duty_area:paris_fictional_annex"
static func create_new() -> WorldBuildResult:
	var built: WorldBuildResult=load("res://practice/scenario.gd").create_new()
	return commission(built)

static func commission(built: WorldBuildResult) -> WorldBuildResult:
	if not built.success:return built
	if not built.world.military_state.duty_operations.is_empty():built.success=false;built.error="DUTY_CHARTER_ALREADY_INSTALLED";return built
	var w:=built.world;var core:=w.organization_state
	var leader:=w.player_state.player_id()
	# Reuse the resident from the current native Opening rather than creating a person.
	var residents: Array=w.economy_r1._spec.get("opening_residents",[])
	var observer:=""
	for row: Dictionary in residents:
		if row.person_id!=leader and row.place_id=="place:paris":observer=row.person_id;break
	if observer.is_empty():built.success=false;built.error="NO_EXISTING_LOCAL_RESIDENT";return built
	var members: Dictionary={}
	if not core.register_organization(ORG,"military_institution","place:paris"):built.success=false;built.error="DUTY_ORGANIZATION_FAILED";return built
	for pair: Array in [[leader,"duty_leader"],[observer,"duty_observer"]]:
		if not core.define_position(ORG,pair[1],"Explicit new fictional 1900 noncombat duty charter",1) or not core.add_member(ORG,pair[0]) or not core.create_appointment(ORG,pair[1],pair[0],pair[1]):built.success=false;built.error="DUTY_APPOINTMENT_FAILED";return built
		members[pair[0]]={"claim_id":w.person_overlay.person(pair[0]).claim_id,"role":pair[1]}
	for op: String in State.OPS:
		var role: String="duty_leader" if op in ["issue","receive"] else "duty_observer"
		var stages: Array[String]=[AuthorizationCheck.STAGE_DOMAIN_EXECUTION]
		var grant: Dictionary={"authority_id":"authority."+UNIT.replace(":",".")+"."+op,"holder":OrganizationState.position_holder(ORG,role),"represented_entity":ORG,"operation":"military.duty."+op,"target_scope":[UNIT],"spatial_scope":["place:paris"],"subject_scope":[observer],"amount_or_quantity_limit":1.0,"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":SOURCE},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":OrganizationState.constraints(stages,"","Unarmed local inspection and face-to-face report. No combat or civilian labor override."),"accountability":OrganizationState.accountability(ORG),"revoked_at":-1}
		if not core.add_authority_grant(grant):built.success=false;built.error="DUTY_GRANT_FAILED";return built
	if not core.add_power_relation({"relation_id":"relation:paris_annex_duty_supervision","relation_type":"supervision","source_entity":leader,"target_entity":observer,"represented_organization_id":ORG,"scope":{"formation_id":UNIT,"operations":["military.duty.issue","military.duty.execute","military.duty.report"]},"valid_from":0,"valid_until":-1,"basis":{"kind":"charter","id":SOURCE}}):built.success=false;built.error="DUTY_RELATION_FAILED";return built
	var unit:=VNextMilitaryFormation.new()
	var provenance: Dictionary={"schema":"formal_named_noncombat_unit_v1","source":SOURCE,"organization":ORG,"anchor":"place:paris","members":members}
	if not unit.configure_named(UNIT,"country_fra","paris",provenance) or not w.military_state.add_formation(unit):built.success=false;built.error="NAMED_UNIT_FAILED";return built
	var plan: Dictionary={"id":"plan:annex_road_inspection","kind":"INSPECT_AND_REPORT","route":[Vector3(12,0.05,4),Vector3(12,0.05,-40),Vector3(0,0.05,-40)],"target_id":"duty_target:annex_road_marker","target_position":Vector3(0,1.5,-45),"max_observation_distance":8.0}
	w.military_state.duty_operations={"schema":State.SCHEMA,"source":SOURCE,"unit":UNIT,"organization":ORG,"anchor":"place:paris","area":AREA,"mapping":{"kind":"FICTIONAL_NONCOMBAT_AREA_NOT_HISTORICAL_DEM","anchor_place":"place:paris","metres_per_unit":1,"home":Vector3(0,0.05,4),"plans":{plan.id:plan}},"leader":leader,"executor":observer,"leader_position":Vector3(0,0.05,6),"position":Vector3(0,0.05,4),"orders":{},"active":"","next_order":1,"pending_usec":0}
	built.persistence._save_metadata.military_scenario["noncombat_duty_charter"]={"source":SOURCE,"formation":UNIT,"population_created":0,"combat_qualification":false,"mapping":"FICTIONAL_NONCOMBAT_AREA_NOT_HISTORICAL_DEM"}
	var reason:=State.references_error(w)
	if not reason.is_empty():built.success=false;built.error=reason
	return built
