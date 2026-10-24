class_name AuthorizationCheck
extends RefCounted

## Computes current permission from organization facts; no snapshots or permission cache.
const ALLOWED: String = "ALLOWED"
const DENIED: String = "DENIED"
const ERROR: String = "ERROR"
const REASON_NO_PROPOSAL_AUTHORITY: String = "NO_PROPOSAL_AUTHORITY"
const REASON_AWAITING_APPROVAL: String = "AWAITING_APPROVAL"
const REASON_APPROVED_NOT_REPRESENTABLE: String = "APPROVED_NOT_REPRESENTABLE"
const REASON_OUT_OF_SCOPE: String = "OUT_OF_SCOPE"
const REASON_EXPIRED: String = "EXPIRED"
const REASON_DELEGATION_INVALID: String = "DELEGATION_INVALID"
const REASON_INVALID_ACTING_CONTEXT: String = "INVALID_ACTING_CONTEXT"
const STAGE_PROPOSAL: String = "proposal"
const STAGE_REPRESENTATION: String = "representation"
const STAGE_DOMAIN_EXECUTION: String = "domain_execution"
const STAGE_DELEGATION: String = "delegation"
const _STAGES: Array[String] = [
	STAGE_PROPOSAL,
	STAGE_REPRESENTATION,
	STAGE_DOMAIN_EXECUTION,
	STAGE_DELEGATION,
]


var _state: OrganizationState


func _init(state: OrganizationState) -> void:
	_state = state


func authorize_domain_execution(
	proposal_id: String, context: Dictionary, at_time: int
) -> Dictionary:
	if _state == null:
		return data_error("Missing OrganizationState for authorize_domain_execution")
	if not _state._proposals.has(proposal_id):
		return data_error("Unknown proposal: " + proposal_id)
	var proposal_record: Dictionary = _state._proposals[proposal_id] as Dictionary
	var input_error := _input_error(context, str(proposal_record["operation"]), STAGE_DOMAIN_EXECUTION, str(proposal_record["spatial_place_id"]), at_time, float(proposal_record["amount_or_quantity"]))
	if not input_error.is_empty():
		return data_error(input_error)
	if str(proposal_record.get("status", "")) != "approved":
		return {"status": DENIED, "reason": REASON_AWAITING_APPROVAL}
	if not _acting_context_valid(context):
		return {"status": DENIED, "reason": REASON_INVALID_ACTING_CONTEXT}
	if str(context.get("represented_organization_id", "")) != str(proposal_record.get("organization_id", "")):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if (proposal_record.get("signatures", []) as Array).is_empty():
		return {"status": DENIED, "reason": REASON_APPROVED_NOT_REPRESENTABLE}
	var resolution := resolve_authority(
		context,
		str(proposal_record.get("operation", "")),
		STAGE_DOMAIN_EXECUTION,
		str(proposal_record.get("target_id", "")),
		str(proposal_record.get("spatial_place_id", "")),
		str(proposal_record.get("subject_id", "")),
		float(proposal_record.get("amount_or_quantity", 0.0)),
		at_time,
		proposal_id
	)
	if str(resolution.get("status", "")) == ALLOWED:
		resolution["status"] = ALLOWED
		resolution["proposal_id"] = proposal_id
		resolution["decision_id"] = str(proposal_record.get("decision_id", ""))
	return resolution


func resolve_authority(
	context: Dictionary,
	operation: String,
	stage: String,
	target_id: String = "",
	spatial_place_id: String = "",
	subject_id: String = "",
	amount_or_quantity: float = 0.0,
	at_time: int = 0,
	proposal_id: String = ""
) -> Dictionary:
	var error := _input_error(context, operation, stage, spatial_place_id, at_time, amount_or_quantity)
	if not error.is_empty():
		return data_error(error)
	if not proposal_id.is_empty() and not _state._proposals.has(proposal_id):
		return data_error("Unknown proposal: " + proposal_id)
	if not _acting_context_valid(context):
		return {"status": DENIED, "reason": "NOT_MEMBER" if bool(context["membership_basis"]) and not _state.is_member(str(context["acting_organization_id"]), str(context["person_id"])) else "POSITION_NOT_GRANTED"}
	var delegation_id: String = str(context.get("delegation_id", ""))
	if not delegation_id.is_empty():
		return _resolve_delegation(
			delegation_id,
			context,
			operation,
			stage,
			target_id,
			spatial_place_id,
			subject_id,
			amount_or_quantity,
			at_time,
			proposal_id
		)
	var authority_id: String = str(context.get("authority_basis", ""))
	if authority_id.is_empty():
		return _position_capability(context, operation, stage, at_time)
	if not _state._authority_grants.has(authority_id):
		return data_error("Unknown authority: %s; person: %s" % [authority_id, str(context["person_id"])])
	var grant: Dictionary = _state._authority_grants[authority_id] as Dictionary
	return _resolve_grant(
		grant,
		context,
		operation,
		stage,
		target_id,
		spatial_place_id,
		subject_id,
		amount_or_quantity,
		at_time,
		proposal_id
	)


func _resolve_grant(
	grant: Dictionary,
	context: Dictionary,
	operation: String,
	stage: String,
	target_id: String,
	spatial_place_id: String,
	subject_id: String,
	amount_or_quantity: float,
	at_time: int,
	proposal_id: String
) -> Dictionary:
	if str(grant.get("represented_entity", "")) != str(context.get("represented_organization_id", "")):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if str(grant.get("operation", "")) != operation:
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if not _holder_matches_context(grant.get("holder", {}) as Dictionary, context):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if not _grant_time_valid(grant, at_time):
		return {"status": DENIED, "reason": REASON_EXPIRED}
	if not _scope_matches(grant, target_id, spatial_place_id, subject_id, amount_or_quantity):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	var constraint_record: Dictionary = grant.get("additional_constraints", {}) as Dictionary
	if not _state._scope_string_array(constraint_record.get("allowed_stages", [])).has(stage):
		if stage == STAGE_PROPOSAL:
			return {"status": DENIED, "reason": REASON_NO_PROPOSAL_AUTHORITY}
		if stage == STAGE_REPRESENTATION and not proposal_id.is_empty() and _proposal_is_approved(proposal_id):
			return {"status": DENIED, "reason": REASON_APPROVED_NOT_REPRESENTABLE}
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	var required_procedure_id := str(constraint_record.get("required_procedure_id", ""))
	if stage in [STAGE_REPRESENTATION, STAGE_DOMAIN_EXECUTION] and not required_procedure_id.is_empty():
		if proposal_id.is_empty() or not _proposal_is_approved_by(proposal_id, required_procedure_id):
			return {"status": DENIED, "reason": REASON_AWAITING_APPROVAL}
	return {
		"status": ALLOWED,
		"authority_id": str(grant.get("authority_id", "")),
		"basis_chain": [str(grant.get("authority_id", ""))],
	}


func _resolve_delegation(
	delegation_id: String,
	context: Dictionary,
	operation: String,
	stage: String,
	target_id: String,
	spatial_place_id: String,
	subject_id: String,
	amount_or_quantity: float,
	at_time: int,
	proposal_id: String
) -> Dictionary:
	var effective := _effective_delegation(delegation_id, at_time, {})
	if effective.has("status"):
		return effective
	if str(effective.get("recipient_person_id", "")) != str(context.get("person_id", "")):
		return {"status": DENIED, "reason": REASON_DELEGATION_INVALID}
	if str(effective.get("represented_entity", "")) != str(context.get("represented_organization_id", "")):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if str(effective.get("operation", "")) != operation:
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if not _state._scope_string_array(effective.get("allowed_stages", [])).has(stage):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	if not _scope_matches(effective, target_id, spatial_place_id, subject_id, amount_or_quantity):
		return {"status": DENIED, "reason": REASON_OUT_OF_SCOPE}
	var required_procedure_id := str(effective.get("required_procedure_id", ""))
	if stage in [STAGE_REPRESENTATION, STAGE_DOMAIN_EXECUTION] and not required_procedure_id.is_empty():
		if proposal_id.is_empty() or not _proposal_is_approved_by(proposal_id, required_procedure_id):
			return {"status": DENIED, "reason": REASON_AWAITING_APPROVAL}
	return {
		"status": ALLOWED,
		"authority_id": str(effective.get("source_authority_id", "")),
		"delegation_id": delegation_id,
		"basis_chain": effective.get("basis_chain", []),
	}


func _effective_delegation(delegation_id: String, at_time: int, visited: Dictionary) -> Dictionary:
	if visited.has(delegation_id):
		return data_error("Delegation cycle: " + delegation_id)
	if not _state._delegations.has(delegation_id):
		return data_error("Unknown delegation: " + delegation_id)
	visited[delegation_id] = true
	var record: Dictionary = _state._delegations[delegation_id] as Dictionary
	if not _delegation_time_valid(record, at_time):
		return {"status": DENIED, "reason": REASON_DELEGATION_INVALID}
	var source_kind := str(record.get("source_kind", ""))
	var source_id := str(record.get("source_id", ""))
	if source_kind == "authority":
		if not _state._authority_grants.has(source_id):
			return data_error("Broken delegation source authority: " + source_id)
		var grant: Dictionary = _state._authority_grants[source_id] as Dictionary
		if not _grant_time_valid(grant, at_time):
			return {"status": DENIED, "reason": REASON_DELEGATION_INVALID}
		return {
			"source_authority_id": source_id,
			"recipient_person_id": str(record.get("recipient_person_id", "")),
			"represented_entity": str(grant.get("represented_entity", "")),
			"operation": str(grant.get("operation", "")),
			"target_scope": record.get("target_scope", []),
			"spatial_scope": record.get("spatial_scope", []),
			"subject_scope": record.get("subject_scope", []),
			"amount_or_quantity_limit": float(record.get("amount_or_quantity_limit", -1.0)),
			"allowed_stages": (grant.get("additional_constraints", {}) as Dictionary).get("allowed_stages", []),
			"required_procedure_id": str((grant.get("additional_constraints", {}) as Dictionary).get("required_procedure_id", "")),
			"basis_chain": [source_id, delegation_id],
		}
	if source_kind == "delegation":
		var parent := _effective_delegation(source_id, at_time, visited)
		if parent.has("status"):
			return parent
		var chain: Array = (parent.get("basis_chain", []) as Array).duplicate()
		chain.append(delegation_id)
		return {
			"source_authority_id": str(parent.get("source_authority_id", "")),
			"recipient_person_id": str(record.get("recipient_person_id", "")),
			"represented_entity": str(parent.get("represented_entity", "")),
			"operation": str(parent.get("operation", "")),
			"target_scope": record.get("target_scope", []),
			"spatial_scope": record.get("spatial_scope", []),
			"subject_scope": record.get("subject_scope", []),
			"amount_or_quantity_limit": float(record.get("amount_or_quantity_limit", -1.0)),
			"allowed_stages": parent.get("allowed_stages", []),
			"required_procedure_id": str(parent.get("required_procedure_id", "")),
			"basis_chain": chain,
		}
	return data_error("Impossible delegation source kind: %s; ID: %s" % [source_kind, delegation_id])


func _delegator_matches_source(
	context: Dictionary, source_kind: String, source_id: String, at_time: int
) -> bool:
	if not _acting_context_valid(context):
		return false
	if source_kind == "authority":
		if not _state._authority_grants.has(source_id):
			return false
		var grant: Dictionary = _state._authority_grants[source_id] as Dictionary
		if str(context.get("authority_basis", "")) != source_id:
			return false
		if not str(context.get("delegation_id", "")).is_empty():
			return false
		if str(grant.get("represented_entity", "")) != str(context.get("represented_organization_id", "")):
			return false
		if not _holder_matches_context(grant.get("holder", {}) as Dictionary, context):
			return false
		if not _grant_time_valid(grant, at_time):
			return false
		if not bool(grant.get("delegable", false)):
			return false
		var constraint_record: Dictionary = grant.get("additional_constraints", {}) as Dictionary
		return _state._scope_string_array(constraint_record.get("allowed_stages", [])).has(STAGE_DELEGATION)
	if source_kind == "delegation":
		if not _state._delegations.has(source_id):
			return false
		var source_record: Dictionary = _state._delegations[source_id] as Dictionary
		var effective := _effective_delegation(source_id, at_time, {})
		if effective.has("status"):
			return false
		return (
			bool(source_record.get("redelegable", false))
			and str(source_record.get("recipient_person_id", "")) == str(context.get("person_id", ""))
			and str(context.get("delegation_id", "")) == source_id
			and str(context.get("authority_basis", "")) == str(effective.get("source_authority_id", ""))
			and str(context.get("represented_organization_id", "")) == str(effective.get("represented_entity", ""))
			and _state._scope_string_array(effective.get("allowed_stages", [])).has(STAGE_DELEGATION)
		)
	return false


func _scope_matches(
	record: Dictionary,
	target_id: String,
	spatial_place_id: String,
	subject_id: String,
	amount_or_quantity: float
) -> bool:
	var targets := _state._scope_string_array(record.get("target_scope", []))
	var places := _state._scope_string_array(record.get("spatial_scope", []))
	var subjects := _state._scope_string_array(record.get("subject_scope", []))
	if not targets.is_empty() and not targets.has(target_id):
		return false
	if not places.is_empty() and not places.has(spatial_place_id):
		return false
	if not subjects.is_empty() and not subjects.has(subject_id):
		return false
	var limit := float(record.get("amount_or_quantity_limit", -1.0))
	return limit < 0.0 or amount_or_quantity <= limit


func _proposal_is_approved(proposal_id: String) -> bool:
	return (
		_state._proposals.has(proposal_id)
		and str((_state._proposals[proposal_id] as Dictionary).get("status", "")) == "approved"
	)


func _proposal_is_approved_by(proposal_id: String, procedure_id: String) -> bool:
	return (
		_proposal_is_approved(proposal_id)
		and str((_state._proposals[proposal_id] as Dictionary).get("procedure_id", "")) == procedure_id
	)


func check(person_id: String, organization_id: String, capability_id: String, current_hour: int = 0) -> Dictionary:
	return resolve_authority(
		OrganizationState.acting_context(person_id, organization_id, organization_id, ""),
		capability_id, STAGE_DOMAIN_EXECUTION, "", "", "", 0.0, current_hour
	)


func check_proposal(record: Dictionary) -> Dictionary:
	if _state == null:
		return data_error("Missing OrganizationState for check_proposal")
	var normalized := _state._scope_normalize_proposal(record)
	if normalized.is_empty():
		return data_error("Malformed proposal: %s" % str(record))
	var context: Dictionary = normalized["proposer_context"]
	if str(context["represented_organization_id"]) != str(normalized["organization_id"]):
		return {"status": DENIED, "reason": "OUTSIDE_SCOPE"}
	return resolve_authority(context, str(normalized["operation"]), STAGE_PROPOSAL,
		str(normalized["target_id"]), str(normalized["spatial_place_id"]), str(normalized["subject_id"]),
		float(normalized["amount_or_quantity"]), int(normalized["created_at"]))


func check_signature(proposal_id: String, context: Dictionary, at_time: int) -> Dictionary:
	if _state == null:
		return data_error("Missing OrganizationState for check_signature")
	if not _state._proposals.has(proposal_id):
		return data_error("Unknown proposal: " + proposal_id)
	var record := _state.proposal(proposal_id)
	var input_error := _input_error(context, str(record["operation"]), STAGE_REPRESENTATION, str(record["spatial_place_id"]), at_time, float(record["amount_or_quantity"]))
	if not input_error.is_empty():
		return data_error(input_error)
	if str(record["status"]) != "approved":
		return {"status": DENIED, "reason": "AWAITING_APPROVAL"}
	if str(context.get("represented_organization_id", "")) != str(record["organization_id"]):
		return {"status": DENIED, "reason": "OUTSIDE_SCOPE"}
	return resolve_authority(context, str(record["operation"]), STAGE_REPRESENTATION,
		str(record["target_id"]), str(record["spatial_place_id"]), str(record["subject_id"]),
		float(record["amount_or_quantity"]), at_time, proposal_id)


func check_delegation(record: Dictionary) -> Dictionary:
	if _state == null:
		return data_error("Missing OrganizationState for check_delegation")
	var normalized := _state._scope_normalize_delegation(record)
	if normalized.is_empty():
		return data_error("Malformed delegation: %s" % str(record))
	var context: Dictionary = normalized["delegator_context"]
	var source_kind: String = str(normalized["source_kind"])
	var source_id: String = str(normalized["source_id"])
	var at_time: int = int(normalized["valid_from"])
	if not _state.is_valid():
		return data_error("Broken delegation source facts: %s" % str(record))
	if source_kind == "authority" and not _state._authority_grants.has(source_id):
		return data_error("Unknown delegation source authority: " + source_id)
	if source_kind == "delegation" and not _state._delegations.has(source_id):
		return data_error("Unknown source delegation: " + source_id)
	var source_id_for_operation: String = source_id
	while _state._delegations.has(source_id_for_operation):
		source_id_for_operation = str(_state.delegation(source_id_for_operation)["source_id"])
	var operation: String = str(_state.authority_grant(source_id_for_operation)["operation"])
	var input_error := _input_error(context, operation, STAGE_DELEGATION, "", at_time, 0.0)
	if not input_error.is_empty():
		return data_error(input_error)
	var source_scope := _state._scope_effective_source_scope(source_kind, source_id)
	if not _state._scope_delegation_scope_is_subset(normalized, source_scope):
		return {"status": DENIED, "reason": "OUTSIDE_SCOPE"}
	if not _delegator_matches_source(context, source_kind, source_id, at_time):
		return {"status": DENIED, "reason": "DELEGATION_INVALID"}
	return {"status": ALLOWED, "authority_id": str(context["authority_basis"])}


func _position_capability(context: Dictionary, operation: String, stage: String, at_time: int) -> Dictionary:
	var organization_id: String = str(context["acting_organization_id"])
	if not _state.capability_ids(organization_id).has(operation):
		return {"status": DENIED, "reason": "CAPABILITY_NOT_GRANTED"}
	for appointment_id: String in _state.appointment_ids(organization_id):
		var appointment := _state.appointment(organization_id, appointment_id)
		if str(appointment["person_id"]) != str(context["person_id"]):
			continue
		if not str(context["appointment_id"]).is_empty() and str(context["appointment_id"]) != appointment_id:
			continue
		if bool(appointment["requires_membership"]) and not _state.is_member(organization_id, str(context["person_id"])):
			return {"status": DENIED, "reason": "NOT_MEMBER"}
		var position := _state.position(organization_id, str(appointment["position_id"]))
		if not (position["capability_ids"] as Array).has(operation):
			continue
		var position_context := context.duplicate(true)
		position_context["appointment_id"] = appointment_id
		# The position grant is a rule fact, evaluated by the same scoped algorithm.
		return _resolve_grant({
			"authority_id": "%s/%s/%s" % [organization_id, str(position["position_id"]), operation],
			"holder": OrganizationState.position_holder(organization_id, str(position["position_id"])),
			"represented_entity": organization_id, "operation": operation,
			"valid_from": 0, "valid_until": -1, "revoked_at": -1,
			"target_scope": [], "spatial_scope": [], "subject_scope": [], "amount_or_quantity_limit": -1.0,
			"additional_constraints": OrganizationState.constraints([STAGE_DOMAIN_EXECUTION]),
		}, position_context, operation, stage, "", "", "", 0.0, at_time, "")
	return {"status": DENIED, "reason": "POSITION_NOT_GRANTED"}


func _input_error(context: Dictionary, operation: String, stage: String, place_id: String, at_time: int, amount: float) -> String:
	if _state == null or not _state.is_valid():
		return "Invalid OrganizationState; context=%s; facts=%s" % [str(context), str(_state.snapshot())] if _state != null else "Missing OrganizationState; context=%s" % str(context)
	if not _state._has_exact_fields(context, ["person_id", "acting_organization_id", "appointment_id", "membership_basis", "represented_organization_id", "authority_basis", "decision_id", "delegation_id"]):
		return "Malformed acting context: %s" % str(context)
	for key: String in ["person_id", "acting_organization_id", "appointment_id", "represented_organization_id", "authority_basis", "decision_id", "delegation_id"]:
		if typeof(context[key]) != TYPE_STRING:
			return "Malformed context field: %s; value: %s" % [key, str(context[key])]
	if typeof(context["membership_basis"]) != TYPE_BOOL:
		return "Malformed membership reference: %s" % str(context["membership_basis"])
	var person_id: String = str(context.get("person_id", ""))
	if not _state._known_person_ids.has(person_id):
		return "Unknown person: " + person_id
	for key: String in ["acting_organization_id", "represented_organization_id"]:
		var organization_id: String = str(context[key])
		if not _state.has_organization(organization_id):
			return "Unknown organization: %s; person: %s" % [organization_id, person_id]
	var known_operation: bool = VNextOrganizationCapabilityCatalog.is_known_operation(operation)
	for authority_id: String in _state.authority_ids():
		if str(_state.authority_grant(authority_id)["operation"]) == operation:
			known_operation = true
	if not known_operation:
		return "Unknown capability: %s; person: %s; organization: %s" % [operation, person_id, str(context["acting_organization_id"])]
	if not _STAGES.has(stage) or at_time < 0 or amount < 0.0 or not is_finite(amount):
		return "Malformed authorization request: capability=%s stage=%s hour=%d amount=%s" % [operation, stage, at_time, str(amount)]
	if not place_id.is_empty() and not _state._known_place_ids.has(place_id):
		return "Impossible scope place: " + place_id
	var appointment_id: String = str(context["appointment_id"])
	if not appointment_id.is_empty():
		var appointment := _state.appointment(str(context["acting_organization_id"]), appointment_id)
		if appointment.is_empty():
			return "Unknown appointment: %s; person: %s" % [appointment_id, person_id]
		var position_id: String = str(appointment["position_id"])
		if _state.position(str(context["acting_organization_id"]), position_id).is_empty():
			return "Unknown position: " + position_id
	var delegation_id: String = str(context["delegation_id"])
	if not delegation_id.is_empty() and not _state._delegations.has(delegation_id):
		return "Unknown delegation: " + delegation_id
	var authority_id: String = str(context["authority_basis"])
	if not authority_id.is_empty() and not _state._authority_grants.has(authority_id):
		return "Unknown authority: %s; person: %s" % [authority_id, person_id]
	return ""


static func data_error(detail: String) -> Dictionary:
	var message: String = "AUTHORIZATION DATA ERROR: " + detail
	push_error(message)
	return {"status": ERROR, "reason": "AUTHORIZATION_DATA_ERROR", "message": message}


func _acting_context_valid(context: Dictionary) -> bool:
	if not _state._has_exact_fields(context, [
		"person_id",
		"acting_organization_id",
		"appointment_id",
		"membership_basis",
		"represented_organization_id",
		"authority_basis",
		"decision_id",
		"delegation_id",
	]):
		return false
	var person_id := str(context.get("person_id", ""))
	var acting_org := str(context.get("acting_organization_id", ""))
	var represented_org := str(context.get("represented_organization_id", ""))
	if (
		not _state._known_person_ids.has(person_id)
		or not _state.has_organization(acting_org)
		or not _state.is_organization_active(acting_org)
		or not _state.has_organization(represented_org)
		or not _state.is_organization_active(represented_org)
	):
		return false
	var appointment_id := str(context.get("appointment_id", ""))
	if not appointment_id.is_empty():
		var appointment_record := _state.appointment(acting_org, appointment_id)
		if appointment_record.is_empty() or str(appointment_record.get("person_id", "")) != person_id:
			return false
	if bool(context.get("membership_basis", false)) and not _state.is_member(acting_org, person_id):
		return false
	return true




func _holder_matches_context(holder: Dictionary, context: Dictionary) -> bool:
	var kind := str(holder.get("kind", ""))
	var acting_org := str(context.get("acting_organization_id", ""))
	var person_id := str(context.get("person_id", ""))
	if kind == "position":
		if str(holder.get("organization_id", "")) != acting_org:
			return false
		var appointment_id := str(context.get("appointment_id", ""))
		if appointment_id.is_empty():
			return false
		var appointment_record := _state.appointment(acting_org, appointment_id)
		return (
			str(appointment_record.get("person_id", "")) == person_id
			and str(appointment_record.get("position_id", "")) == str(holder.get("local_id", ""))
		)
	if kind == "membership":
		return (
			str(holder.get("organization_id", "")) == acting_org
			and bool(context.get("membership_basis", false))
			and _state.is_member(acting_org, person_id)
		)
	if kind == "person":
		return str(holder.get("person_id", "")) == person_id
	## A collective DecisionBody never collapses into one person's ActingContext.
	return false




func _grant_time_valid(grant: Dictionary, at_time: int) -> bool:
	if at_time < int(grant.get("valid_from", 0)):
		return false
	var valid_until := int(grant.get("valid_until", -1))
	if valid_until >= 0 and at_time > valid_until:
		return false
	var revoked_at := int(grant.get("revoked_at", -1))
	return revoked_at < 0 or at_time < revoked_at




func _delegation_time_valid(record: Dictionary, at_time: int) -> bool:
	if at_time < int(record.get("valid_from", 0)):
		return false
	var valid_until := int(record.get("valid_until", -1))
	if valid_until >= 0 and at_time > valid_until:
		return false
	var revoked_at := int(record.get("revoked_at", -1))
	return revoked_at < 0 or at_time < revoked_at
