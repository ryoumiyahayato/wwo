extends RefCounted
## Qualification over the existing named unit. OrganizationState owns all grants.
const SCHEMA := "formal_named_combat_authority_v1"
const SOURCE := "scenario:explicit_1900_annex_command_charter_20261024"
const ORG := "organization:annex_limited_command"
const EXECUTE := "authority.annex_limited_command.execute"
const DELEGATE := "authority.annex_limited_command.delegate"
const Duty=preload("res://scripts/vnext/military/military_duty_state.gd")
static func error(d: Dictionary) -> String:
	if d.is_empty():return ""
	if not Duty.keys(d,["schema","source","unit","organization","anchor","commander","operator","claims","commissioned_minute","mandates"]) or d.schema!=SCHEMA or d.source!=SOURCE or d.organization!=ORG:return "COMBAT_AUTHORITY_SCHEMA_INVALID"
	for key: String in ["unit","anchor","commander","operator"]:
		if not d[key] is String or d[key].is_empty():return "COMBAT_AUTHORITY_ID_INVALID"
	if d.commander==d.operator or not d.claims is Dictionary or d.claims.size()!=2 or not d.claims.has_all([d.commander,d.operator]) or d.claims[d.commander]==d.claims[d.operator] or not Duty.nat(d.commissioned_minute) or not d.mandates is Dictionary or d.mandates.size()>64:return "COMBAT_AUTHORITY_MEMBERS_INVALID"
	for claim: Variant in d.claims.values():
		if not claim is String or claim.is_empty():return "COMBAT_AUTHORITY_CLAIM_INVALID"
	for id: Variant in d.mandates:
		var m: Variant=d.mandates[id]
		if not id is String or not Duty.keys(m,["id","delegation_id","issued_minute","from_minute","until_minute","accepted","acceptance"]) or m.id!=id or m.delegation_id!="delegation.annex."+str(id) or not Duty.nat(m.issued_minute) or not Duty.nat(m.from_minute) or not Duty.nat(m.until_minute) or m.from_minute!=m.issued_minute or m.issued_minute<d.commissioned_minute or m.until_minute<=m.from_minute or m.until_minute-m.from_minute>5 or not m.accepted is bool or not m.acceptance is Dictionary:return "COMBAT_MANDATE_INVALID"
		if m.accepted:
			if not Duty.keys(m.acceptance,["minute","person","authorization"]) or not Duty.nat(m.acceptance.minute) or m.acceptance.minute<m.from_minute or m.acceptance.minute>=m.until_minute or m.acceptance.person!=d.operator or not m.acceptance.authorization is Dictionary or m.acceptance.authorization.get("status")!=AuthorizationCheck.ALLOWED:return "COMBAT_ACCEPTANCE_INVALID"
		elif not m.acceptance.is_empty():return "COMBAT_UNBACKED_ACCEPTANCE"
	return ""
static func references_error(w: WorldState) -> String:
	var d: Dictionary=w.military_state.combat_authority
	var e:=error(d)
	if not e.is_empty() or d.is_empty():return e
	var duty: Dictionary=w.military_state.duty_operations
	if duty.is_empty() or d.unit!=duty.unit or d.anchor!=duty.anchor or d.commander!=duty.leader or d.operator!=duty.executor or not w.organization_state.has_organization(ORG) or d.commissioned_minute>w.game_clock.total_minutes():return "COMBAT_AUTHORITY_SOURCE_MISMATCH"
	var f:=w.military_state.get_formation(d.unit)
	if f==null or f.personnel!=0 or f.named_personnel.members.size()!=d.claims.size():return "COMBAT_AGGREGATE_DUPLICATION"
	for person: String in d.claims:
		if not f.named_personnel.members.has(person) or f.named_personnel.members[person].claim_id!=d.claims[person] or w.person_overlay.person(person).get("claim_id")!=d.claims[person]:return "COMBAT_AUTHORITY_CLAIM_MISMATCH"
	var core:=w.organization_state
	for pair: Array in [[DELEGATE,"military.combat.delegate"],[EXECUTE,"military.combat.execute"]]:
		var grant:=core.authority_grant(pair[0])
		if grant.is_empty() or grant.operation!=pair[1] or grant.basis!={"kind":"charter","id":SOURCE} or grant.represented_entity!=ORG or grant.target_scope!=[d.unit] or grant.spatial_scope!=[d.anchor] or grant.subject_scope!=[d.operator]:return "COMBAT_AUTHORITY_GRANT_SOURCE_INVALID"
	for m: Dictionary in d.mandates.values():
		var delegation:=core.delegation(m.delegation_id)
		if delegation.is_empty() or delegation.source_kind!="authority" or delegation.source_id!=EXECUTE or delegation.recipient_person_id!=d.operator or delegation.target_scope!=[d.unit] or delegation.spatial_scope!=[d.anchor] or delegation.subject_scope!=[d.operator] or delegation.redelegable or delegation.valid_from!=int(m.issued_minute/60) or delegation.valid_until!=int(m.issued_minute/60)+1 or m.issued_minute>w.game_clock.total_minutes():return "COMBAT_MANDATE_REFERENCE_INVALID"
	return ""
static func qualified(w: WorldState) -> bool:
	var d: Dictionary=w.military_state.combat_authority
	if d.is_empty() or not references_error(w).is_empty():return false
	for pair: Array in [[d.commander,"commander"],[d.operator,"operator"]]:
		var a:=w.organization_state.appointment(ORG,pair[1])
		if a.get("person_id")!=pair[0] or a.get("position_id")!=pair[1] or not w.organization_state.is_member(ORG,pair[0]) or not w.person_overlay.is_alive(pair[0]):return false
	return true
