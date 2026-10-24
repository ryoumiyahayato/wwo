extends RefCounted
const State=preload("res://scripts/vnext/military/military_combat_authority_state.gd")
const BASE_BLOCKERS := ["NO_FORMAL_BODY_MEDICAL_AUTHORITY","CONTROLLED_AREA_NOT_COMBAT_REGISTERED","NO_COMBAT_MATERIAL_ASSIGNMENT","NO_LOCAL_COMBAT_EXECUTION_CONTRACT"]
var world: WorldState
var persistence: FormalPersistence
func bind(w: WorldState,p: FormalPersistence) -> String:
	world=w;persistence=p;return State.references_error(w)
func fail(reason: String) -> Dictionary:return {"ok":false,"reason":reason}
func state() -> Dictionary:return world.military_state.combat_authority
func context(role: String,delegation_id: String="") -> Dictionary:
	var d:=state();var person: String=d.commander if role=="commander" else d.operator
	return OrganizationState.acting_context(person,State.ORG,State.ORG,State.EXECUTE,role,true,"",delegation_id)
func command_context() -> Dictionary:
	var c:=context("commander");c.authority_basis=State.DELEGATE;return c
func commission() -> Dictionary:
	if persistence.is_save_in_progress():return fail("SAVE_IN_PROGRESS")
	if not state().is_empty():return {"ok":true,"duplicate":true}
	var d: Dictionary=world.military_state.duty_operations
	if d.is_empty() or world.military_state.local_delegation.is_empty() or not State.Duty.references_error(world).is_empty() or not d.active.is_empty() or not world.military_state.local_operations.get("active",{}).is_empty() or world.military_state.has_projection_lease():return fail("INVALID_OR_OCCUPIED_DUTY_UNIT")
	for person: String in [d.leader,d.executor]:
		if not world.person_overlay.is_alive(person) or world.person_overlay.current_place(person)!=d.anchor or world.person_travel.is_in_transit(person):return fail("PERSON_NOT_PRESENT")
	# Build only an OrganizationState candidate; adopt into the original owner once valid.
	var core:=OrganizationState.new();core._reference_catalog=world.organization_state._reference_catalog;core._reference_catalog_configured=true
	if not core.restore(world.organization_state.snapshot()):return fail("ORGANIZATION_CANDIDATE_RESTORE_FAILED")
	if not core.register_organization(State.ORG,"military_institution",d.anchor):return fail("COMMAND_ORGANIZATION_EXISTS_OR_INVALID")
	for pair: Array in [[d.leader,"commander"],[d.executor,"operator"]]:
		if not core.define_position(State.ORG,pair[1],"Explicit fictional limited military command charter",1) or not core.add_member(State.ORG,pair[0]) or not core.create_appointment(State.ORG,pair[1],pair[0],pair[1]):return fail("COMMAND_APPOINTMENT_FAILED")
	for pair: Array in [[State.DELEGATE,"military.combat.delegate",false],[State.EXECUTE,"military.combat.execute",true]]:
		var grant: Dictionary={"authority_id":pair[0],"holder":OrganizationState.position_holder(State.ORG,"commander"),"represented_entity":State.ORG,"operation":pair[1],"target_scope":[d.unit],"spatial_scope":[d.anchor],"subject_scope":[d.executor],"amount_or_quantity_limit":1.0,"valid_from":world.game_clock.current_hour(),"valid_until":world.game_clock.current_hour()+1,"basis":{"kind":"charter","id":State.SOURCE},"revocable":true,"delegable":pair[2],"exclusive_or_concurrent":"concurrent","additional_constraints":OrganizationState.constraints([AuthorizationCheck.STAGE_DELEGATION,AuthorizationCheck.STAGE_DOMAIN_EXECUTION],"","Authority qualification only; medical, geography, assigned materials and execution contract remain required."),"accountability":OrganizationState.accountability(State.ORG),"revoked_at":-1}
		if not core.add_authority_grant(grant):return fail("COMMAND_GRANT_FAILED")
	if not core.add_power_relation({"relation_id":"relation:annex_limited_command","relation_type":"temporary_command_assignment","source_entity":State.ORG,"target_entity":d.unit,"represented_organization_id":State.ORG,"scope":{"formation_id":d.unit,"members":[d.leader,d.executor],"purpose":"LIMITED_COMBAT_QUALIFICATION_NO_EXECUTION_ADMISSION"},"valid_from":world.game_clock.current_hour(),"valid_until":world.game_clock.current_hour()+1,"basis":{"kind":"charter","id":State.SOURCE}}):return fail("COMMAND_RELATION_FAILED")
	var qualification: Dictionary={"schema":State.SCHEMA,"source":State.SOURCE,"unit":d.unit,"organization":State.ORG,"anchor":d.anchor,"commander":d.leader,"operator":d.executor,"claims":{d.leader:world.person_overlay.person(d.leader).claim_id,d.executor:world.person_overlay.person(d.executor).claim_id},"commissioned_minute":world.game_clock.total_minutes(),"mandates":{}}
	if not State.error(qualification).is_empty():return fail("QUALIFICATION_INVALID")
	if not world.organization_state.restore(core.snapshot()):return fail("COMMAND_ADOPTION_FAILED")
	world.military_state.combat_authority=qualification
	return {"ok":true,"qualified":State.qualified(world),"combat_ready":false}
func delegate(id: String,issuer: Dictionary,from_minute: int,until_minute: int) -> Dictionary:
	if persistence.is_save_in_progress():return fail("SAVE_IN_PROGRESS")
	if not State.qualified(world):return fail("NO_CURRENT_NAMED_COMBAT_QUALIFICATION")
	var d:=state()
	if world.person_overlay.current_place(d.commander)!=d.anchor or world.person_travel.is_in_transit(d.commander):return fail("COMMANDER_NOT_PRESENT")
	if (world.economy_r1!=null and world.economy_r1._contracts.has(d.commander)) or not world.personal_economy_state.employment(d.commander).is_empty():return fail("CIVILIAN_EMPLOYMENT_CONFLICT")
	if id.is_empty() or not id.is_valid_identifier():return fail("INVALID_MANDATE_ID")
	if d.mandates.has(id):
		var old: Dictionary=d.mandates[id]
		return {"ok":true,"duplicate":true,"mandate":old.duplicate(true)} if old.from_minute==from_minute and old.until_minute==until_minute and issuer==context("commander") else fail("CONFLICTING_COMBAT_MANDATE")
	if d.mandates.size()>=64 or from_minute!=world.game_clock.total_minutes() or until_minute<=from_minute or until_minute-from_minute>5:return fail("MANDATE_INTERVAL_INVALID")
	# Resolve at current time as well as check_delegation's historical valid_from.
	var current:=world.authorization_check.resolve_authority(issuer,"military.combat.execute",AuthorizationCheck.STAGE_DELEGATION,d.unit,d.anchor,d.operator,1.0,world.game_clock.current_hour())
	if current.status!=AuthorizationCheck.ALLOWED:return fail("CURRENT_DELEGATOR_PERMISSION_DENIED")
	var record: Dictionary={"delegation_id":"delegation.annex."+id,"source_kind":"authority","source_id":State.EXECUTE,"delegator_context":issuer.duplicate(true),"recipient_person_id":d.operator,"target_scope":[d.unit],"spatial_scope":[d.anchor],"subject_scope":[d.operator],"amount_or_quantity_limit":1.0,"valid_from":world.game_clock.current_hour(),"valid_until":world.game_clock.current_hour()+1,"redelegable":false,"revocable":true,"exclusive_or_concurrent":"concurrent","revoked_at":-1}
	var checked:=world.authorization_check.check_delegation(record)
	if checked.status!=AuthorizationCheck.ALLOWED:return fail("DELEGATION_AUTHORITY_DENIED")
	if not world.organization_state.record_delegation(record):return fail("DELEGATION_RECORD_REJECTED")
	d.mandates[id]={"id":id,"delegation_id":record.delegation_id,"issued_minute":from_minute,"from_minute":from_minute,"until_minute":until_minute,"accepted":false,"acceptance":{}}
	return {"ok":true,"duplicate":false,"mandate":d.mandates[id].duplicate(true)}
func authorize(id: String,actor: Dictionary) -> Dictionary:
	if not State.qualified(world):return fail("NO_CURRENT_NAMED_COMBAT_QUALIFICATION")
	var d:=state();var m: Dictionary=d.mandates.get(id,{})
	if m.is_empty() or actor.get("person_id")!=d.operator or actor.get("delegation_id")!=m.delegation_id:return fail("WRONG_MANDATE_RECIPIENT")
	if world.game_clock.total_minutes()<m.from_minute or world.game_clock.total_minutes()>=m.until_minute:return fail("MINUTE_WINDOW_CLOSED")
	if world.person_overlay.current_place(d.operator)!=d.anchor or world.person_travel.is_in_transit(d.operator):return fail("OPERATOR_NOT_PRESENT")
	if (world.economy_r1!=null and world.economy_r1._contracts.has(d.operator)) or not world.personal_economy_state.employment(d.operator).is_empty():return fail("CIVILIAN_EMPLOYMENT_CONFLICT")
	var resolution:=world.authorization_check.resolve_authority(actor,"military.combat.execute",AuthorizationCheck.STAGE_DOMAIN_EXECUTION,d.unit,d.anchor,d.operator,1.0,world.game_clock.current_hour())
	return {"ok":resolution.status==AuthorizationCheck.ALLOWED,"reason":"CURRENT_EXECUTION_AUTHORITY_DENIED" if resolution.status!=AuthorizationCheck.ALLOWED else "","authorization":resolution}
func accept(id: String,actor: Dictionary) -> Dictionary:
	if persistence.is_save_in_progress():return fail("SAVE_IN_PROGRESS")
	var allowed:=authorize(id,actor)
	if not allowed.ok:return allowed
	var m: Dictionary=state().mandates[id]
	if m.accepted:return {"ok":true,"duplicate":true}
	m.accepted=true;m.acceptance={"minute":world.game_clock.total_minutes(),"person":state().operator,"authorization":allowed.authorization.duplicate(true)}
	return {"ok":true,"duplicate":false,"qualified_order_accepted":true,"combat_ready":false}
func revoke_mandate(id: String,issuer: Dictionary) -> Dictionary:
	if persistence.is_save_in_progress():return fail("SAVE_IN_PROGRESS")
	if not State.qualified(world):return fail("NO_CURRENT_NAMED_COMBAT_QUALIFICATION")
	var d:=state();var m: Dictionary=d.mandates.get(id,{})
	if m.is_empty():return fail("UNKNOWN_COMBAT_MANDATE")
	var permission:=world.authorization_check.resolve_authority(issuer,"military.combat.delegate",AuthorizationCheck.STAGE_DELEGATION,d.unit,d.anchor,d.operator,1.0,world.game_clock.current_hour())
	if permission.status!=AuthorizationCheck.ALLOWED:return fail("REVOCATION_AUTHORITY_DENIED")
	var record:=world.organization_state.delegation(m.delegation_id)
	if record.revoked_at>=0:return {"ok":true,"duplicate":true}
	if not world.organization_state.revoke_delegation(m.delegation_id,world.game_clock.current_hour()):return fail("REVOCATION_RECORD_REJECTED")
	return {"ok":true,"duplicate":false}
func blockers(issuer: Dictionary) -> Array:
	var result: Array=BASE_BLOCKERS.duplicate()
	if not State.qualified(world):result.push_front("NAMED_UNIT_NONCOMBAT_ONLY")
	var duty: Dictionary=world.military_state.duty_operations
	var r:=world.authorization_check.resolve_authority(issuer,"military.combat.delegate",AuthorizationCheck.STAGE_DELEGATION,duty.unit,duty.anchor,duty.executor,1.0,world.game_clock.current_hour())
	if r.status!=AuthorizationCheck.ALLOWED:result.append("NO_COMBAT_DELEGATION_AUTHORITY")
	return result
func execution_admission(id: String,actor: Dictionary) -> Dictionary:
	var a:=authorize(id,actor)
	if not a.ok:return a
	return {"ok":false,"reason":"FORMAL_COMBAT_NOT_READY","blockers":BASE_BLOCKERS.duplicate()}
