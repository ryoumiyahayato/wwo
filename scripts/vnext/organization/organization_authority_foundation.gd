class_name VNextOrganizationAuthorityFoundation
extends RefCounted

## Authoritative Organization-layer owner for scoped authority, collective decisions,
## representation, delegation and power-topology facts. It deliberately reads
## OrganizationCore structure but does not own Economy, Politics, Military,
## Population or Spatial domain facts.

const SNAPSHOT_SCHEMA_ID: String = "vnext_organization_authority_foundation_v1"

const STATUS_AUTHORIZED: String = "AUTHORIZED"
const STATUS_NO_PROPOSAL_AUTHORITY: String = "NO_PROPOSAL_AUTHORITY"
const STATUS_AWAITING_APPROVAL: String = "AWAITING_APPROVAL"
const STATUS_APPROVED_NOT_REPRESENTABLE: String = "APPROVED_NOT_REPRESENTABLE"
const STATUS_AUTHORIZED_FOR_DOMAIN_EXECUTION: String = "AUTHORIZED_FOR_DOMAIN_EXECUTION"
const STATUS_OUT_OF_SCOPE: String = "OUT_OF_SCOPE"
const STATUS_EXPIRED: String = "EXPIRED"
const STATUS_DELEGATION_INVALID: String = "DELEGATION_INVALID"
const STATUS_INVALID_ACTING_CONTEXT: String = "INVALID_ACTING_CONTEXT"
const STATUS_UNKNOWN_AUTHORITY: String = "UNKNOWN_AUTHORITY"

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

const _HOLDER_KINDS: Array[String] = ["position", "decision_body", "membership", "person"]
const _DECISION_PARTICIPANT_KINDS: Array[String] = ["person", "position", "membership"]
const _DENOMINATORS: Array[String] = [
	"eligible_weight",
	"cast_weight",
	"eligible_count",
	"cast_count",
]
const _TIE_HANDLING: Array[String] = ["reject", "approve"]
const _VOTE_CHOICES: Array[String] = ["yes", "no", "abstain"]
const _RELATION_TYPES: Array[String] = [
	"grant",
	"appointment",
	"approval",
	"confirmation",
	"veto",
	"supervision",
	"reservation",
	"delegation",
	"exclusive_authority",
	"concurrent_authority",
	"accountability",
	"succession",
	"temporary_command_assignment",
]
const _TRANSFER_TYPES: Array[String] = [
	"appointment_change",
	"delegation",
	"decision_authorization",
	"succession",
	"command_assignment",
	"rule_grant",
	"rule_revoke",
]

var _organization_core: VNextOrganizationCore = null
var _known_person_ids: Array[String] = []
var _known_place_ids: Array[String] = []
var _reference_fingerprint: String = ""

var _authority_grants: Dictionary = {}
var _decision_bodies: Dictionary = {}
var _procedures: Dictionary = {}
var _proposals: Dictionary = {}
var _delegations: Dictionary = {}
var _power_relations: Dictionary = {}
var _power_transfers: Dictionary = {}
var _revision: int = 0


static func create(
	organization_core: VNextOrganizationCore,
	known_person_ids: Array[String],
	known_place_ids: Array[String] = []
) -> VNextOrganizationAuthorityFoundation:
	if organization_core == null or not organization_core.is_valid():
		return null
	var authority := VNextOrganizationAuthorityFoundation.new()
	if not authority._configure_references(organization_core, known_person_ids, known_place_ids):
		return null
	return authority


func _configure_references(
	organization_core: VNextOrganizationCore,
	known_person_ids: Array[String],
	known_place_ids: Array[String]
) -> bool:
	var person_seen: Dictionary = {}
	for person_id: String in known_person_ids:
		if (
			not _is_valid_person_id(person_id)
			or person_seen.has(person_id)
		):
			return false
		person_seen[person_id] = true
	var place_seen: Dictionary = {}
	for place_id: String in known_place_ids:
		if (
			not _is_valid_place_id(place_id)
			or place_seen.has(place_id)
		):
			return false
		place_seen[place_id] = true
	_organization_core = organization_core
	_known_person_ids = known_person_ids.duplicate()
	_known_person_ids.sort()
	_known_place_ids = known_place_ids.duplicate()
	_known_place_ids.sort()
	_reference_fingerprint = JSON.stringify({
		"persons": _known_person_ids,
		"places": _known_place_ids,
	}).sha256_text()
	return true


func revision() -> int:
	return _revision


func state_fingerprint() -> String:
	return _state_fingerprint_for(
		_revision,
		_authority_grants,
		_decision_bodies,
		_procedures,
		_proposals,
		_delegations,
		_power_relations,
		_power_transfers
	)


func reference_fingerprint() -> String:
	return _reference_fingerprint


func structure_fingerprint() -> String:
	return _organization_core.state_fingerprint() if _organization_core != null else ""


static func position_holder(organization_id: String, position_id: String) -> Dictionary:
	return {
		"kind": "position",
		"organization_id": organization_id,
		"local_id": position_id,
		"person_id": "",
	}


static func decision_body_holder(organization_id: String, decision_body_id: String) -> Dictionary:
	return {
		"kind": "decision_body",
		"organization_id": organization_id,
		"local_id": decision_body_id,
		"person_id": "",
	}


static func membership_holder(organization_id: String, qualification: String = "member") -> Dictionary:
	return {
		"kind": "membership",
		"organization_id": organization_id,
		"local_id": qualification,
		"person_id": "",
	}


static func person_holder(person_id: String) -> Dictionary:
	return {
		"kind": "person",
		"organization_id": "",
		"local_id": "",
		"person_id": person_id,
	}


static func acting_context(
	person_id: String,
	acting_organization_id: String,
	represented_organization_id: String,
	authority_basis: String,
	appointment_id: String = "",
	membership_basis: bool = false,
	decision_id: String = "",
	delegation_id: String = ""
) -> Dictionary:
	return {
		"person_id": person_id,
		"acting_organization_id": acting_organization_id,
		"appointment_id": appointment_id,
		"membership_basis": membership_basis,
		"represented_organization_id": represented_organization_id,
		"authority_basis": authority_basis,
		"decision_id": decision_id,
		"delegation_id": delegation_id,
	}


static func constraints(
	allowed_stages: Array[String],
	required_procedure_id: String = "",
	compatibility_capability_id: String = "",
	notes: String = ""
) -> Dictionary:
	var sorted_stages := allowed_stages.duplicate()
	sorted_stages.sort()
	return {
		"allowed_stages": sorted_stages,
		"required_procedure_id": required_procedure_id,
		"compatibility_capability_id": compatibility_capability_id,
		"notes": notes,
	}


static func accountability(
	organization_id: String = "", relation_id: String = ""
) -> Dictionary:
	return {
		"organization_id": organization_id,
		"relation_id": relation_id,
	}


func authority_ids() -> Array[String]:
	return _sorted_keys(_authority_grants)


func authority_grant(authority_id: String) -> Dictionary:
	return (_authority_grants.get(authority_id, {}) as Dictionary).duplicate(true)


func add_authority_grant(record: Dictionary) -> bool:
	var normalized := _normalize_authority_grant(record)
	if normalized.is_empty():
		return false
	var authority_id: String = str(normalized.get("authority_id", ""))
	if _authority_grants.has(authority_id):
		return false
	if not _authority_references_valid(normalized, _decision_bodies):
		return false
	if _has_exclusive_authority_conflict(normalized, _authority_grants):
		return false
	var candidate := _authority_grants.duplicate(true)
	candidate[authority_id] = normalized
	_authority_grants = candidate
	_revision += 1
	return true


func revoke_authority(authority_id: String, revoked_at: int) -> bool:
	if not _authority_grants.has(authority_id) or revoked_at < 0:
		return false
	var record: Dictionary = _authority_grants[authority_id] as Dictionary
	if not bool(record.get("revocable", false)) or int(record.get("revoked_at", -1)) >= 0:
		return false
	if revoked_at < int(record.get("valid_from", 0)):
		return false
	var candidate := _authority_grants.duplicate(true)
	var updated: Dictionary = (candidate[authority_id] as Dictionary).duplicate(true)
	updated["revoked_at"] = revoked_at
	candidate[authority_id] = updated
	_authority_grants = candidate
	_revision += 1
	return true


func define_decision_body(record: Dictionary) -> bool:
	var normalized := _normalize_decision_body(record)
	if normalized.is_empty():
		return false
	var body_id: String = str(normalized.get("decision_body_id", ""))
	if _decision_bodies.has(body_id):
		return false
	if not _decision_body_references_valid(normalized):
		return false
	var candidate := _decision_bodies.duplicate(true)
	candidate[body_id] = normalized
	_decision_bodies = candidate
	_revision += 1
	return true


func decision_body(decision_body_id: String) -> Dictionary:
	return (_decision_bodies.get(decision_body_id, {}) as Dictionary).duplicate(true)


func define_procedure(record: Dictionary) -> bool:
	var normalized := _normalize_procedure(record)
	if normalized.is_empty():
		return false
	var procedure_id: String = str(normalized.get("procedure_id", ""))
	if _procedures.has(procedure_id) or not _procedure_references_valid(normalized, _decision_bodies):
		return false
	var candidate := _procedures.duplicate(true)
	candidate[procedure_id] = normalized
	_procedures = candidate
	_revision += 1
	return true


func procedure(procedure_id: String) -> Dictionary:
	return (_procedures.get(procedure_id, {}) as Dictionary).duplicate(true)


func create_proposal(record: Dictionary) -> bool:
	var normalized := _normalize_proposal(record)
	if normalized.is_empty():
		return false
	var proposal_id: String = str(normalized.get("proposal_id", ""))
	if _proposals.has(proposal_id):
		return false
	var organization_id: String = str(normalized.get("organization_id", ""))
	var procedure_id: String = str(normalized.get("procedure_id", ""))
	if (
		not _organization_core.has_organization(organization_id)
		or not _procedures.has(procedure_id)
		or str((_procedures[procedure_id] as Dictionary).get("organization_id", "")) != organization_id
	):
		return false
	var context: Dictionary = normalized.get("proposer_context", {}) as Dictionary
	var resolution := resolve_authority(
		context,
		str(normalized.get("operation", "")),
		STAGE_PROPOSAL,
		str(normalized.get("target_id", "")),
		str(normalized.get("spatial_place_id", "")),
		str(normalized.get("subject_id", "")),
		float(normalized.get("amount_or_quantity", 0.0)),
		int(normalized.get("created_at", 0))
	)
	if str(resolution.get("status", "")) != STATUS_AUTHORIZED:
		return false
	var candidate := _proposals.duplicate(true)
	candidate[proposal_id] = normalized
	_proposals = candidate
	_revision += 1
	return true


func proposal(proposal_id: String) -> Dictionary:
	return (_proposals.get(proposal_id, {}) as Dictionary).duplicate(true)


func revise_proposal(
	proposal_id: String, expected_version: int, new_content_fingerprint: String, at_time: int
) -> bool:
	if (
		not _proposals.has(proposal_id)
		or expected_version <= 0
		or new_content_fingerprint.length() != 64
		or at_time < 0
	):
		return false
	var current: Dictionary = _proposals[proposal_id] as Dictionary
	if (
		int(current.get("version", 0)) != expected_version
		or str(current.get("status", "")) != "proposed"
	):
		return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	updated["version"] = expected_version + 1
	updated["content_fingerprint"] = new_content_fingerprint
	updated["created_at"] = at_time
	updated["votes"] = []
	updated["step_results"] = {}
	updated["signatures"] = []
	updated["decision_id"] = ""
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func cast_vote(
	proposal_id: String,
	step_id: String,
	person_id: String,
	proposal_version: int,
	choice: String,
	recused: bool,
	at_time: int
) -> bool:
	if (
		not _proposals.has(proposal_id)
		or not _known_person_ids.has(person_id)
		or not _VOTE_CHOICES.has(choice)
		or at_time < 0
	):
		return false
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if (
		str(proposal_record.get("status", "")) != "proposed"
		or int(proposal_record.get("version", 0)) != proposal_version
	):
		return false
	var procedure_record: Dictionary = _procedures.get(
		str(proposal_record.get("procedure_id", "")), {}
	) as Dictionary
	var step := _procedure_step(procedure_record, step_id)
	if step.is_empty():
		return false
	var body: Dictionary = _decision_bodies.get(str(step.get("decision_body_id", "")), {}) as Dictionary
	var eligible := _eligible_participants(body)
	if not eligible.has(person_id):
		return false
	if recused and not bool(step.get("recusal_allowed", false)):
		return false
	if choice == "abstain" and not bool(step.get("abstention_allowed", false)):
		return false
	var votes: Array = proposal_record.get("votes", []) as Array
	for raw_vote: Variant in votes:
		var vote: Dictionary = raw_vote as Dictionary
		if str(vote.get("step_id", "")) == step_id and str(vote.get("person_id", "")) == person_id:
			return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	var updated_votes: Array = (updated.get("votes", []) as Array).duplicate(true)
	updated_votes.append({
		"step_id": step_id,
		"person_id": person_id,
		"proposal_version": proposal_version,
		"choice": choice,
		"recused": recused,
		"cast_at": at_time,
	})
	updated["votes"] = updated_votes
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func finalize_proposal_step(proposal_id: String, step_id: String, at_time: int) -> bool:
	if not _proposals.has(proposal_id) or at_time < 0:
		return false
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if str(proposal_record.get("status", "")) != "proposed":
		return false
	var procedure_record: Dictionary = _procedures.get(
		str(proposal_record.get("procedure_id", "")), {}
	) as Dictionary
	if procedure_record.is_empty() or _procedure_deadline_expired(procedure_record, proposal_record, at_time):
		return false
	var step := _procedure_step(procedure_record, step_id)
	if step.is_empty():
		return false
	var prior_results: Dictionary = proposal_record.get("step_results", {}) as Dictionary
	if prior_results.has(step_id):
		return false
	var result := _evaluate_step(step, proposal_record)
	if not bool(result.get("quorum_met", false)):
		return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	var results: Dictionary = (updated.get("step_results", {}) as Dictionary).duplicate(true)
	results[step_id] = result
	updated["step_results"] = results
	if not bool(result.get("approved", false)):
		updated["status"] = "rejected"
	elif results.size() == (procedure_record.get("steps", []) as Array).size():
		var all_approved := true
		for raw_step: Variant in procedure_record.get("steps", []) as Array:
			var procedure_step_record: Dictionary = raw_step as Dictionary
			var result_for_step: Dictionary = results.get(
				str(procedure_step_record.get("step_id", "")), {}
			) as Dictionary
			if not bool(result_for_step.get("approved", false)):
				all_approved = false
				break
		if all_approved:
			updated["status"] = "approved"
			updated["decision_id"] = "decision:%s:v%d" % [
				proposal_id,
				int(updated.get("version", 0)),
			]
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func sign_proposal(
	proposal_id: String,
	expected_version: int,
	signature_id: String,
	context: Dictionary,
	at_time: int
) -> bool:
	if (
		not _proposals.has(proposal_id)
		or not _is_valid_token(signature_id)
		or at_time < 0
	):
		return false
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if (
		str(proposal_record.get("status", "")) != "approved"
		or int(proposal_record.get("version", 0)) != expected_version
	):
		return false
	var resolution := resolve_authority(
		context,
		str(proposal_record.get("operation", "")),
		STAGE_REPRESENTATION,
		str(proposal_record.get("target_id", "")),
		str(proposal_record.get("spatial_place_id", "")),
		str(proposal_record.get("subject_id", "")),
		float(proposal_record.get("amount_or_quantity", 0.0)),
		at_time,
		proposal_id
	)
	if str(resolution.get("status", "")) != STATUS_AUTHORIZED:
		return false
	var signatures: Array = proposal_record.get("signatures", []) as Array
	for raw_signature: Variant in signatures:
		if str((raw_signature as Dictionary).get("signature_id", "")) == signature_id:
			return false
	var candidate := _proposals.duplicate(true)
	var updated: Dictionary = (candidate[proposal_id] as Dictionary).duplicate(true)
	var updated_signatures: Array = (updated.get("signatures", []) as Array).duplicate(true)
	updated_signatures.append({
		"signature_id": signature_id,
		"proposal_version": expected_version,
		"person_id": str(context.get("person_id", "")),
		"authority_id": str(resolution.get("authority_id", "")),
		"delegation_id": str(context.get("delegation_id", "")),
		"signed_at": at_time,
	})
	updated["signatures"] = updated_signatures
	candidate[proposal_id] = updated
	_proposals = candidate
	_revision += 1
	return true


func authorize_domain_execution(
	proposal_id: String, context: Dictionary, at_time: int
) -> Dictionary:
	if not _proposals.has(proposal_id):
		return {"status": STATUS_AWAITING_APPROVAL}
	var proposal_record: Dictionary = _proposals[proposal_id] as Dictionary
	if str(proposal_record.get("status", "")) != "approved":
		return {"status": STATUS_AWAITING_APPROVAL}
	if (proposal_record.get("signatures", []) as Array).is_empty():
		return {"status": STATUS_APPROVED_NOT_REPRESENTABLE}
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
	if str(resolution.get("status", "")) == STATUS_AUTHORIZED:
		resolution["status"] = STATUS_AUTHORIZED_FOR_DOMAIN_EXECUTION
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
	if not _STAGES.has(stage) or not _is_valid_operation(operation) or at_time < 0:
		return {"status": STATUS_OUT_OF_SCOPE}
	if not _acting_context_valid(context):
		return {"status": STATUS_INVALID_ACTING_CONTEXT}
	if not spatial_place_id.is_empty() and not _known_place_ids.has(spatial_place_id):
		return {"status": STATUS_OUT_OF_SCOPE}
	if amount_or_quantity < 0.0 or not is_finite(amount_or_quantity):
		return {"status": STATUS_OUT_OF_SCOPE}
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
	if not _authority_grants.has(authority_id):
		return {"status": STATUS_UNKNOWN_AUTHORITY}
	var grant: Dictionary = _authority_grants[authority_id] as Dictionary
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


func create_delegation(record: Dictionary) -> bool:
	var normalized := _normalize_delegation(record)
	if normalized.is_empty():
		return false
	var delegation_id: String = str(normalized.get("delegation_id", ""))
	if _delegations.has(delegation_id):
		return false
	var source_kind: String = str(normalized.get("source_kind", ""))
	var source_id: String = str(normalized.get("source_id", ""))
	var source_scope := _effective_source_scope(source_kind, source_id)
	if source_scope.is_empty():
		return false
	if not bool(source_scope.get("delegable", false)):
		return false
	if not _delegation_scope_is_subset(normalized, source_scope):
		return false
	var delegator_context: Dictionary = normalized.get("delegator_context", {}) as Dictionary
	if not _delegator_matches_source(delegator_context, source_kind, source_id, int(normalized.get("valid_from", 0))):
		return false
	if _delegation_person_cycle(source_kind, source_id, str(normalized.get("recipient_person_id", ""))):
		return false
	if _has_delegation_exclusive_conflict(normalized):
		return false
	var candidate := _delegations.duplicate(true)
	candidate[delegation_id] = normalized
	_delegations = candidate
	_revision += 1
	return true


func delegation(delegation_id: String) -> Dictionary:
	return (_delegations.get(delegation_id, {}) as Dictionary).duplicate(true)


func revoke_delegation(delegation_id: String, revoked_at: int) -> bool:
	if not _delegations.has(delegation_id) or revoked_at < 0:
		return false
	var record: Dictionary = _delegations[delegation_id] as Dictionary
	if not bool(record.get("revocable", false)) or int(record.get("revoked_at", -1)) >= 0:
		return false
	if revoked_at < int(record.get("valid_from", 0)):
		return false
	var candidate := _delegations.duplicate(true)
	var updated: Dictionary = (candidate[delegation_id] as Dictionary).duplicate(true)
	updated["revoked_at"] = revoked_at
	candidate[delegation_id] = updated
	_delegations = candidate
	_revision += 1
	return true


func add_power_relation(record: Dictionary) -> bool:
	var normalized := _normalize_power_relation(record)
	if normalized.is_empty():
		return false
	var relation_id: String = str(normalized.get("relation_id", ""))
	if _power_relations.has(relation_id):
		return false
	var organization_id: String = str(normalized.get("represented_organization_id", ""))
	if not _organization_core.has_organization(organization_id):
		return false
	var candidate := _power_relations.duplicate(true)
	candidate[relation_id] = normalized
	_power_relations = candidate
	_revision += 1
	return true


func power_relation(relation_id: String) -> Dictionary:
	return (_power_relations.get(relation_id, {}) as Dictionary).duplicate(true)


func record_power_transfer(record: Dictionary) -> bool:
	var normalized := _normalize_power_transfer(record)
	if normalized.is_empty():
		return false
	var transfer_id: String = str(normalized.get("transfer_id", ""))
	if _power_transfers.has(transfer_id):
		return false
	var candidate := _power_transfers.duplicate(true)
	candidate[transfer_id] = normalized
	_power_transfers = candidate
	_revision += 1
	return true


func power_transfer(transfer_id: String) -> Dictionary:
	return (_power_transfers.get(transfer_id, {}) as Dictionary).duplicate(true)


func migrate_legacy_position_capabilities(
	organization_id: String, valid_from: int = 0
) -> bool:
	if not _organization_core.has_organization(organization_id) or valid_from < 0:
		return false
	var created_any := false
	for position_id: String in _organization_core.position_ids(organization_id):
		var position_record := _organization_core.position(organization_id, position_id)
		for capability_id: String in _string_array(position_record.get("capability_ids", [])):
			if not VNextOrganizationCapabilityCatalog.is_known(capability_id):
				return false
			var authority_id := "legacy.%s.%s.%s" % [
				_sanitize_token(organization_id),
				_sanitize_token(position_id),
				_sanitize_token(capability_id),
			]
			if _authority_grants.has(authority_id):
				continue
			var record := {
				"authority_id": authority_id,
				"holder": position_holder(organization_id, position_id),
				"represented_entity": organization_id,
				"operation": capability_id,
				"target_scope": [],
				"spatial_scope": [],
				"subject_scope": [],
				"amount_or_quantity_limit": -1.0,
				"valid_from": valid_from,
				"valid_until": -1,
				"basis": {"kind": "legacy_capability", "id": capability_id},
				"revocable": true,
				"delegable": false,
				"exclusive_or_concurrent": "concurrent",
				"additional_constraints": constraints(
					[STAGE_DOMAIN_EXECUTION], "", capability_id, "compatibility projection"
				),
				"accountability": accountability(organization_id),
				"revoked_at": -1,
			}
			if not add_authority_grant(record):
				return false
			created_any = true
	return created_any


func legacy_capabilities_for_context(context: Dictionary, at_time: int = 0) -> Array[String]:
	var output: Array[String] = []
	for authority_id: String in authority_ids():
		var grant: Dictionary = _authority_grants[authority_id] as Dictionary
		var capability_id: String = str(
			(grant.get("additional_constraints", {}) as Dictionary).get(
				"compatibility_capability_id", ""
			)
		)
		if capability_id.is_empty() or output.has(capability_id):
			continue
		var resolution := _resolve_grant(
			grant,
			context,
			str(grant.get("operation", "")),
			STAGE_DOMAIN_EXECUTION,
			"",
			"",
			"",
			0.0,
			at_time,
			""
		)
		if str(resolution.get("status", "")) == STATUS_AUTHORIZED:
			output.append(capability_id)
	output.sort()
	return output


func snapshot() -> Dictionary:
	var core := _state_payload(
		_revision,
		_authority_grants,
		_decision_bodies,
		_procedures,
		_proposals,
		_delegations,
		_power_relations,
		_power_transfers
	)
	core["schema_id"] = SNAPSHOT_SCHEMA_ID
	core["structure_fingerprint"] = structure_fingerprint()
	core["reference_fingerprint"] = _reference_fingerprint
	core["state_fingerprint"] = state_fingerprint()
	return core


func restore(snapshot_value: Dictionary) -> bool:
	if not _has_exact_fields(snapshot_value, [
		"schema_id",
		"revision",
		"structure_fingerprint",
		"reference_fingerprint",
		"authority_grants",
		"decision_bodies",
		"procedures",
		"proposals",
		"delegations",
		"power_relations",
		"power_transfers",
		"state_fingerprint",
	]):
		return false
	if str(snapshot_value.get("schema_id", "")) != SNAPSHOT_SCHEMA_ID:
		return false
	if str(snapshot_value.get("structure_fingerprint", "")) != structure_fingerprint():
		return false
	if str(snapshot_value.get("reference_fingerprint", "")) != _reference_fingerprint:
		return false
	var candidate_revision := _nonnegative_int(snapshot_value.get("revision"))
	if candidate_revision < 0:
		return false
	var grants := _decode_record_array(snapshot_value.get("authority_grants"), Callable(self, "_normalize_authority_grant"), "authority_id")
	var bodies := _decode_record_array(snapshot_value.get("decision_bodies"), Callable(self, "_normalize_decision_body"), "decision_body_id")
	var procedures := _decode_record_array(snapshot_value.get("procedures"), Callable(self, "_normalize_procedure"), "procedure_id")
	var proposals := _decode_record_array(snapshot_value.get("proposals"), Callable(self, "_normalize_proposal"), "proposal_id")
	var delegations := _decode_record_array(snapshot_value.get("delegations"), Callable(self, "_normalize_delegation"), "delegation_id")
	var relations := _decode_record_array(snapshot_value.get("power_relations"), Callable(self, "_normalize_power_relation"), "relation_id")
	var transfers := _decode_record_array(snapshot_value.get("power_transfers"), Callable(self, "_normalize_power_transfer"), "transfer_id")
	if (
		grants.get("invalid", false)
		or bodies.get("invalid", false)
		or procedures.get("invalid", false)
		or proposals.get("invalid", false)
		or delegations.get("invalid", false)
		or relations.get("invalid", false)
		or transfers.get("invalid", false)
	):
		return false
	var candidate_grants: Dictionary = grants.get("records", {}) as Dictionary
	var candidate_bodies: Dictionary = bodies.get("records", {}) as Dictionary
	var candidate_procedures: Dictionary = procedures.get("records", {}) as Dictionary
	var candidate_proposals: Dictionary = proposals.get("records", {}) as Dictionary
	var candidate_delegations: Dictionary = delegations.get("records", {}) as Dictionary
	var candidate_relations: Dictionary = relations.get("records", {}) as Dictionary
	var candidate_transfers: Dictionary = transfers.get("records", {}) as Dictionary
	if not _validate_complete_state(
		candidate_grants,
		candidate_bodies,
		candidate_procedures,
		candidate_proposals,
		candidate_delegations,
		candidate_relations,
		candidate_transfers
	):
		return false
	var expected := _state_fingerprint_for(
		candidate_revision,
		candidate_grants,
		candidate_bodies,
		candidate_procedures,
		candidate_proposals,
		candidate_delegations,
		candidate_relations,
		candidate_transfers
	)
	if str(snapshot_value.get("state_fingerprint", "")) != expected:
		return false
	_authority_grants = candidate_grants
	_decision_bodies = candidate_bodies
	_procedures = candidate_procedures
	_proposals = candidate_proposals
	_delegations = candidate_delegations
	_power_relations = candidate_relations
	_power_transfers = candidate_transfers
	_revision = candidate_revision
	return true


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
		return {"status": STATUS_OUT_OF_SCOPE}
	if str(grant.get("operation", "")) != operation:
		return {"status": STATUS_OUT_OF_SCOPE}
	if not _holder_matches_context(grant.get("holder", {}) as Dictionary, context):
		return {"status": STATUS_OUT_OF_SCOPE}
	if not _grant_time_valid(grant, at_time):
		return {"status": STATUS_EXPIRED}
	if not _scope_matches(grant, target_id, spatial_place_id, subject_id, amount_or_quantity):
		return {"status": STATUS_OUT_OF_SCOPE}
	var constraint_record: Dictionary = grant.get("additional_constraints", {}) as Dictionary
	if not _string_array(constraint_record.get("allowed_stages", [])).has(stage):
		if stage == STAGE_PROPOSAL:
			return {"status": STATUS_NO_PROPOSAL_AUTHORITY}
		if stage == STAGE_REPRESENTATION and not proposal_id.is_empty() and _proposal_is_approved(proposal_id):
			return {"status": STATUS_APPROVED_NOT_REPRESENTABLE}
		return {"status": STATUS_OUT_OF_SCOPE}
	var required_procedure_id := str(constraint_record.get("required_procedure_id", ""))
	if stage in [STAGE_REPRESENTATION, STAGE_DOMAIN_EXECUTION] and not required_procedure_id.is_empty():
		if proposal_id.is_empty() or not _proposal_is_approved_by(proposal_id, required_procedure_id):
			return {"status": STATUS_AWAITING_APPROVAL}
	return {
		"status": STATUS_AUTHORIZED,
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
	if effective.is_empty():
		return {"status": STATUS_DELEGATION_INVALID}
	if str(effective.get("recipient_person_id", "")) != str(context.get("person_id", "")):
		return {"status": STATUS_DELEGATION_INVALID}
	if str(effective.get("represented_entity", "")) != str(context.get("represented_organization_id", "")):
		return {"status": STATUS_OUT_OF_SCOPE}
	if str(effective.get("operation", "")) != operation:
		return {"status": STATUS_OUT_OF_SCOPE}
	if not _string_array(effective.get("allowed_stages", [])).has(stage):
		return {"status": STATUS_OUT_OF_SCOPE}
	if not _scope_matches(effective, target_id, spatial_place_id, subject_id, amount_or_quantity):
		return {"status": STATUS_OUT_OF_SCOPE}
	var required_procedure_id := str(effective.get("required_procedure_id", ""))
	if stage in [STAGE_REPRESENTATION, STAGE_DOMAIN_EXECUTION] and not required_procedure_id.is_empty():
		if proposal_id.is_empty() or not _proposal_is_approved_by(proposal_id, required_procedure_id):
			return {"status": STATUS_AWAITING_APPROVAL}
	return {
		"status": STATUS_AUTHORIZED,
		"authority_id": str(effective.get("source_authority_id", "")),
		"delegation_id": delegation_id,
		"basis_chain": effective.get("basis_chain", []),
	}


func _effective_delegation(delegation_id: String, at_time: int, visited: Dictionary) -> Dictionary:
	if visited.has(delegation_id) or not _delegations.has(delegation_id):
		return {}
	visited[delegation_id] = true
	var record: Dictionary = _delegations[delegation_id] as Dictionary
	if not _delegation_time_valid(record, at_time):
		return {}
	var source_kind := str(record.get("source_kind", ""))
	var source_id := str(record.get("source_id", ""))
	if source_kind == "authority":
		if not _authority_grants.has(source_id):
			return {}
		var grant: Dictionary = _authority_grants[source_id] as Dictionary
		if not _grant_time_valid(grant, at_time):
			return {}
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
		if parent.is_empty():
			return {}
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
	return {}


func _effective_source_scope(source_kind: String, source_id: String) -> Dictionary:
	if source_kind == "authority":
		if not _authority_grants.has(source_id):
			return {}
		var grant: Dictionary = _authority_grants[source_id] as Dictionary
		return {
			"target_scope": grant.get("target_scope", []),
			"spatial_scope": grant.get("spatial_scope", []),
			"subject_scope": grant.get("subject_scope", []),
			"amount_or_quantity_limit": float(grant.get("amount_or_quantity_limit", -1.0)),
			"valid_from": int(grant.get("valid_from", 0)),
			"valid_until": int(grant.get("valid_until", -1)),
			"delegable": bool(grant.get("delegable", false)),
			"redelegable": bool(grant.get("delegable", false)),
		}
	if source_kind == "delegation" and _delegations.has(source_id):
		var delegation_record: Dictionary = _delegations[source_id] as Dictionary
		return {
			"target_scope": delegation_record.get("target_scope", []),
			"spatial_scope": delegation_record.get("spatial_scope", []),
			"subject_scope": delegation_record.get("subject_scope", []),
			"amount_or_quantity_limit": float(delegation_record.get("amount_or_quantity_limit", -1.0)),
			"valid_from": int(delegation_record.get("valid_from", 0)),
			"valid_until": int(delegation_record.get("valid_until", -1)),
			"delegable": bool(delegation_record.get("redelegable", false)),
			"redelegable": bool(delegation_record.get("redelegable", false)),
		}
	return {}


func _delegator_matches_source(
	context: Dictionary, source_kind: String, source_id: String, at_time: int
) -> bool:
	if source_kind == "authority":
		if not _authority_grants.has(source_id):
			return false
		var grant: Dictionary = _authority_grants[source_id] as Dictionary
		var resolution := _resolve_grant(
			grant,
			context,
			str(grant.get("operation", "")),
			STAGE_DELEGATION,
			"",
			"",
			"",
			0.0,
			at_time,
			""
		)
		return str(resolution.get("status", "")) == STATUS_AUTHORIZED
	if source_kind == "delegation":
		if not _delegations.has(source_id):
			return false
		var source_record: Dictionary = _delegations[source_id] as Dictionary
		return (
			bool(source_record.get("redelegable", false))
			and str(source_record.get("recipient_person_id", "")) == str(context.get("person_id", ""))
			and not _effective_delegation(source_id, at_time, {}).is_empty()
		)
	return false


func _delegation_scope_is_subset(record: Dictionary, source_scope: Dictionary) -> bool:
	if not _array_scope_subset(record.get("target_scope", []), source_scope.get("target_scope", [])):
		return false
	if not _array_scope_subset(record.get("spatial_scope", []), source_scope.get("spatial_scope", [])):
		return false
	if not _array_scope_subset(record.get("subject_scope", []), source_scope.get("subject_scope", [])):
		return false
	var source_limit := float(source_scope.get("amount_or_quantity_limit", -1.0))
	var delegated_limit := float(record.get("amount_or_quantity_limit", -1.0))
	if source_limit >= 0.0 and (delegated_limit < 0.0 or delegated_limit > source_limit):
		return false
	if int(record.get("valid_from", 0)) < int(source_scope.get("valid_from", 0)):
		return false
	var source_until := int(source_scope.get("valid_until", -1))
	var delegated_until := int(record.get("valid_until", -1))
	if source_until >= 0 and (delegated_until < 0 or delegated_until > source_until):
		return false
	return true


func _acting_context_valid(context: Dictionary) -> bool:
	if not _has_exact_fields(context, [
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
		not _known_person_ids.has(person_id)
		or not _organization_core.has_organization(acting_org)
		or not _organization_core.is_organization_active(acting_org)
		or not _organization_core.has_organization(represented_org)
		or not _organization_core.is_organization_active(represented_org)
	):
		return false
	var appointment_id := str(context.get("appointment_id", ""))
	if not appointment_id.is_empty():
		var appointment_record := _organization_core.appointment(acting_org, appointment_id)
		if appointment_record.is_empty() or str(appointment_record.get("person_id", "")) != person_id:
			return false
	if bool(context.get("membership_basis", false)) and not _organization_core.is_member(acting_org, person_id):
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
		var appointment_record := _organization_core.appointment(acting_org, appointment_id)
		return (
			str(appointment_record.get("person_id", "")) == person_id
			and str(appointment_record.get("position_id", "")) == str(holder.get("local_id", ""))
		)
	if kind == "membership":
		return (
			str(holder.get("organization_id", "")) == acting_org
			and bool(context.get("membership_basis", false))
			and _organization_core.is_member(acting_org, person_id)
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


func _scope_matches(
	record: Dictionary,
	target_id: String,
	spatial_place_id: String,
	subject_id: String,
	amount_or_quantity: float
) -> bool:
	var targets := _string_array(record.get("target_scope", []))
	var places := _string_array(record.get("spatial_scope", []))
	var subjects := _string_array(record.get("subject_scope", []))
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
		_proposals.has(proposal_id)
		and str((_proposals[proposal_id] as Dictionary).get("status", "")) == "approved"
	)


func _proposal_is_approved_by(proposal_id: String, procedure_id: String) -> bool:
	return (
		_proposal_is_approved(proposal_id)
		and str((_proposals[proposal_id] as Dictionary).get("procedure_id", "")) == procedure_id
	)


func _evaluate_step(step: Dictionary, proposal_record: Dictionary) -> Dictionary:
	var body: Dictionary = _decision_bodies.get(str(step.get("decision_body_id", "")), {}) as Dictionary
	var eligible := _eligible_participants(body)
	var recused: Dictionary = {}
	var yes_weight := 0
	var no_weight := 0
	var abstain_weight := 0
	var yes_count := 0
	var no_count := 0
	var abstain_count := 0
	for raw_vote: Variant in proposal_record.get("votes", []) as Array:
		var vote: Dictionary = raw_vote as Dictionary
		if str(vote.get("step_id", "")) != str(step.get("step_id", "")):
			continue
		var person_id := str(vote.get("person_id", ""))
		if not eligible.has(person_id):
			continue
		if bool(vote.get("recused", false)):
			recused[person_id] = true
			continue
		var weight := int(eligible.get(person_id, 0))
		match str(vote.get("choice", "")):
			"yes":
				yes_weight += weight
				yes_count += 1
			"no":
				no_weight += weight
				no_count += 1
			"abstain":
				abstain_weight += weight
				abstain_count += 1
	var eligible_weight := 0
	var eligible_count := 0
	for person_id: String in _sorted_keys(eligible):
		if recused.has(person_id):
			continue
		eligible_weight += int(eligible[person_id])
		eligible_count += 1
	var participating_weight := yes_weight + no_weight + abstain_weight
	var participating_count := yes_count + no_count + abstain_count
	var quorum_met := (
		participating_weight * int(step.get("quorum_denominator", 1))
		>= eligible_weight * int(step.get("quorum_numerator", 1))
	)
	var denominator_kind := str(step.get("denominator", "eligible_weight"))
	var denominator_value := 0
	var yes_value := 0
	match denominator_kind:
		"eligible_weight":
			denominator_value = eligible_weight
			yes_value = yes_weight
		"cast_weight":
			denominator_value = yes_weight + no_weight
			yes_value = yes_weight
		"eligible_count":
			denominator_value = eligible_count
			yes_value = yes_count
		"cast_count":
			denominator_value = yes_count + no_count
			yes_value = yes_count
	var lhs := yes_value * int(step.get("threshold_denominator", 1))
	var rhs := denominator_value * int(step.get("threshold_numerator", 1))
	var approved := denominator_value > 0 and lhs > rhs
	if denominator_value > 0 and lhs == rhs:
		approved = str(step.get("tie_handling", "reject")) == "approve"
	return {
		"approved": quorum_met and approved,
		"quorum_met": quorum_met,
		"eligible_weight": eligible_weight,
		"participating_weight": participating_weight,
		"yes_weight": yes_weight,
		"no_weight": no_weight,
		"abstain_weight": abstain_weight,
		"eligible_count": eligible_count,
		"participating_count": participating_count,
		"yes_count": yes_count,
		"no_count": no_count,
		"abstain_count": abstain_count,
	}


func _eligible_participants(body: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for raw_rule: Variant in body.get("eligible_participants", []) as Array:
		var rule: Dictionary = raw_rule as Dictionary
		var weight := int(rule.get("weight", 1))
		match str(rule.get("kind", "")):
			"person":
				var person_id := str(rule.get("person_id", ""))
				output[person_id] = int(output.get(person_id, 0)) + weight
			"position":
				var organization_id := str(body.get("organization_id", ""))
				var position_id := str(rule.get("position_id", ""))
				for appointment_id: String in _organization_core.appointment_ids(organization_id):
					var appointment_record := _organization_core.appointment(organization_id, appointment_id)
					if str(appointment_record.get("position_id", "")) == position_id:
						var person_id := str(appointment_record.get("person_id", ""))
						output[person_id] = int(output.get(person_id, 0)) + weight
			"membership":
				for person_id: String in _organization_core.member_ids(str(body.get("organization_id", ""))):
					output[person_id] = int(output.get(person_id, 0)) + weight
	return output


func _procedure_step(procedure_record: Dictionary, step_id: String) -> Dictionary:
	for raw_step: Variant in procedure_record.get("steps", []) as Array:
		var step: Dictionary = raw_step as Dictionary
		if str(step.get("step_id", "")) == step_id:
			return step
	return {}


func _procedure_deadline_expired(
	procedure_record: Dictionary, proposal_record: Dictionary, at_time: int
) -> bool:
	var deadline := int(procedure_record.get("deadline", -1))
	return deadline >= 0 and at_time > int(proposal_record.get("created_at", 0)) + deadline


func _normalize_authority_grant(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"authority_id", "holder", "represented_entity", "operation",
		"target_scope", "spatial_scope", "subject_scope", "amount_or_quantity_limit",
		"valid_from", "valid_until", "basis", "revocable", "delegable",
		"exclusive_or_concurrent", "additional_constraints", "accountability", "revoked_at",
	]):
		return {}
	var authority_id := str(record.get("authority_id", ""))
	var represented_entity := str(record.get("represented_entity", ""))
	var operation := str(record.get("operation", ""))
	var holder := _normalize_holder(record.get("holder", {}) as Dictionary)
	var target_scope := _normalized_unique_strings(record.get("target_scope"))
	var spatial_scope := _normalized_unique_strings(record.get("spatial_scope"))
	var subject_scope := _normalized_unique_strings(record.get("subject_scope"))
	var limit := _valid_limit(record.get("amount_or_quantity_limit"))
	var valid_from := _nonnegative_int(record.get("valid_from"))
	var valid_until := _optional_nonnegative_int(record.get("valid_until"))
	var revoked_at := _optional_nonnegative_int(record.get("revoked_at"))
	if (
		not _is_valid_token(authority_id)
		or holder.is_empty()
		or not _is_valid_organization_id(represented_entity)
		or not _is_valid_operation(operation)
		or target_scope.get("invalid", false)
		or spatial_scope.get("invalid", false)
		or subject_scope.get("invalid", false)
		or limit < -1.0
		or valid_from < 0
		or valid_until < -1
		or (valid_until >= 0 and valid_until < valid_from)
		or revoked_at < -1
		or (revoked_at >= 0 and revoked_at < valid_from)
		or typeof(record.get("revocable")) != TYPE_BOOL
		or typeof(record.get("delegable")) != TYPE_BOOL
		or str(record.get("exclusive_or_concurrent", "")) not in ["exclusive", "concurrent"]
	):
		return {}
	var basis := _normalize_basis(record.get("basis", {}) as Dictionary)
	var constraint_record := _normalize_constraints(record.get("additional_constraints", {}) as Dictionary)
	var accountability_record := _normalize_accountability(record.get("accountability", {}) as Dictionary)
	if basis.is_empty() or constraint_record.is_empty() or accountability_record.is_empty():
		return {}
	return {
		"authority_id": authority_id,
		"holder": holder,
		"represented_entity": represented_entity,
		"operation": operation,
		"target_scope": target_scope.get("values", []),
		"spatial_scope": spatial_scope.get("values", []),
		"subject_scope": subject_scope.get("values", []),
		"amount_or_quantity_limit": limit,
		"valid_from": valid_from,
		"valid_until": valid_until,
		"basis": basis,
		"revocable": bool(record.get("revocable")),
		"delegable": bool(record.get("delegable")),
		"exclusive_or_concurrent": str(record.get("exclusive_or_concurrent")),
		"additional_constraints": constraint_record,
		"accountability": accountability_record,
		"revoked_at": revoked_at,
	}


func _normalize_holder(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["kind", "organization_id", "local_id", "person_id"]):
		return {}
	var kind := str(record.get("kind", ""))
	var organization_id := str(record.get("organization_id", ""))
	var local_id := str(record.get("local_id", ""))
	var person_id := str(record.get("person_id", ""))
	if not _HOLDER_KINDS.has(kind):
		return {}
	match kind:
		"position", "decision_body", "membership":
			if not _is_valid_organization_id(organization_id) or not _is_valid_token(local_id) or not person_id.is_empty():
				return {}
		"person":
			if not organization_id.is_empty() or not local_id.is_empty() or not _known_person_ids.has(person_id):
				return {}
	return {
		"kind": kind,
		"organization_id": organization_id,
		"local_id": local_id,
		"person_id": person_id,
	}


func _normalize_constraints(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"allowed_stages", "required_procedure_id", "compatibility_capability_id", "notes"
	]):
		return {}
	var stages := _normalized_unique_strings(record.get("allowed_stages"))
	if stages.get("invalid", false):
		return {}
	for stage: String in stages.get("values", []) as Array:
		if not _STAGES.has(stage):
			return {}
	var required_procedure_id := str(record.get("required_procedure_id", ""))
	var compatibility_capability_id := str(record.get("compatibility_capability_id", ""))
	if (
		not required_procedure_id.is_empty() and not _is_valid_token(required_procedure_id)
	):
		return {}
	if (
		not compatibility_capability_id.is_empty()
		and not VNextOrganizationCapabilityCatalog.is_known(compatibility_capability_id)
	):
		return {}
	return {
		"allowed_stages": stages.get("values", []),
		"required_procedure_id": required_procedure_id,
		"compatibility_capability_id": compatibility_capability_id,
		"notes": str(record.get("notes", "")),
	}


func _normalize_accountability(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["organization_id", "relation_id"]):
		return {}
	var organization_id := str(record.get("organization_id", ""))
	var relation_id := str(record.get("relation_id", ""))
	if not organization_id.is_empty() and not _is_valid_organization_id(organization_id):
		return {}
	if not relation_id.is_empty() and not _is_valid_token(relation_id):
		return {}
	return {"organization_id": organization_id, "relation_id": relation_id}


func _normalize_basis(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["kind", "id"]):
		return {}
	var kind := str(record.get("kind", ""))
	var basis_id := str(record.get("id", ""))
	if not _is_valid_token(kind) or not _is_valid_token(basis_id):
		return {}
	return {"kind": kind, "id": basis_id}


func _normalize_decision_body(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["decision_body_id", "organization_id", "eligible_participants", "active"]):
		return {}
	var body_id := str(record.get("decision_body_id", ""))
	var organization_id := str(record.get("organization_id", ""))
	if not _is_valid_token(body_id) or not _is_valid_organization_id(organization_id) or typeof(record.get("active")) != TYPE_BOOL:
		return {}
	if typeof(record.get("eligible_participants")) != TYPE_ARRAY:
		return {}
	var participants: Array[Dictionary] = []
	for raw_rule: Variant in record.get("eligible_participants") as Array:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			return {}
		var rule := _normalize_participant_rule(raw_rule as Dictionary)
		if rule.is_empty():
			return {}
		participants.append(rule)
	if participants.is_empty():
		return {}
	return {
		"decision_body_id": body_id,
		"organization_id": organization_id,
		"eligible_participants": participants,
		"active": bool(record.get("active")),
	}


func _normalize_participant_rule(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["kind", "person_id", "position_id", "weight"]):
		return {}
	var kind := str(record.get("kind", ""))
	var person_id := str(record.get("person_id", ""))
	var position_id := str(record.get("position_id", ""))
	var weight := _positive_int(record.get("weight"))
	if not _DECISION_PARTICIPANT_KINDS.has(kind) or weight <= 0:
		return {}
	match kind:
		"person":
			if not _known_person_ids.has(person_id) or not position_id.is_empty():
				return {}
		"position":
			if not person_id.is_empty() or not _is_valid_token(position_id):
				return {}
		"membership":
			if not person_id.is_empty() or not position_id.is_empty():
				return {}
	return {"kind": kind, "person_id": person_id, "position_id": position_id, "weight": weight}


func _normalize_procedure(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, ["procedure_id", "organization_id", "steps", "deadline"]):
		return {}
	var procedure_id := str(record.get("procedure_id", ""))
	var organization_id := str(record.get("organization_id", ""))
	var deadline := _optional_nonnegative_int(record.get("deadline"))
	if not _is_valid_token(procedure_id) or not _is_valid_organization_id(organization_id) or deadline < -1:
		return {}
	if typeof(record.get("steps")) != TYPE_ARRAY:
		return {}
	var steps: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_step: Variant in record.get("steps") as Array:
		if typeof(raw_step) != TYPE_DICTIONARY:
			return {}
		var step := _normalize_procedure_step(raw_step as Dictionary)
		if step.is_empty() or seen.has(str(step.get("step_id", ""))):
			return {}
		seen[str(step.get("step_id", ""))] = true
		steps.append(step)
	if steps.is_empty():
		return {}
	return {"procedure_id": procedure_id, "organization_id": organization_id, "steps": steps, "deadline": deadline}


func _normalize_procedure_step(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"step_id", "decision_body_id", "quorum_numerator", "quorum_denominator",
		"threshold_numerator", "threshold_denominator", "denominator", "tie_handling",
		"abstention_allowed", "recusal_allowed",
	]):
		return {}
	var step_id := str(record.get("step_id", ""))
	var body_id := str(record.get("decision_body_id", ""))
	var qn := _positive_int(record.get("quorum_numerator"))
	var qd := _positive_int(record.get("quorum_denominator"))
	var tn := _positive_int(record.get("threshold_numerator"))
	var td := _positive_int(record.get("threshold_denominator"))
	if (
		not _is_valid_token(step_id)
		or not _is_valid_token(body_id)
		or qn <= 0 or qd <= 0 or qn > qd
		or tn <= 0 or td <= 0 or tn > td
		or str(record.get("denominator", "")) not in _DENOMINATORS
		or str(record.get("tie_handling", "")) not in _TIE_HANDLING
		or typeof(record.get("abstention_allowed")) != TYPE_BOOL
		or typeof(record.get("recusal_allowed")) != TYPE_BOOL
	):
		return {}
	return {
		"step_id": step_id,
		"decision_body_id": body_id,
		"quorum_numerator": qn,
		"quorum_denominator": qd,
		"threshold_numerator": tn,
		"threshold_denominator": td,
		"denominator": str(record.get("denominator")),
		"tie_handling": str(record.get("tie_handling")),
		"abstention_allowed": bool(record.get("abstention_allowed")),
		"recusal_allowed": bool(record.get("recusal_allowed")),
	}


func _normalize_proposal(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"proposal_id", "organization_id", "operation", "target_id", "spatial_place_id",
		"subject_id", "amount_or_quantity", "content_fingerprint", "version",
		"proposer_context", "procedure_id", "created_at", "status", "step_results",
		"votes", "signatures", "decision_id",
	]):
		return {}
	var proposal_id := str(record.get("proposal_id", ""))
	var organization_id := str(record.get("organization_id", ""))
	var operation := str(record.get("operation", ""))
	var place_id := str(record.get("spatial_place_id", ""))
	var amount := _nonnegative_float(record.get("amount_or_quantity"))
	var version := _positive_int(record.get("version"))
	var created_at := _nonnegative_int(record.get("created_at"))
	if (
		not _is_valid_token(proposal_id)
		or not _is_valid_organization_id(organization_id)
		or not _is_valid_operation(operation)
		or (not place_id.is_empty() and not _known_place_ids.has(place_id))
		or amount < 0.0
		or str(record.get("content_fingerprint", "")).length() != 64
		or version <= 0
		or not _acting_context_valid(record.get("proposer_context", {}) as Dictionary)
		or not _is_valid_token(str(record.get("procedure_id", "")))
		or created_at < 0
		or str(record.get("status", "")) not in ["proposed", "approved", "rejected"]
		or typeof(record.get("step_results")) != TYPE_DICTIONARY
		or typeof(record.get("votes")) != TYPE_ARRAY
		or typeof(record.get("signatures")) != TYPE_ARRAY
	):
		return {}
	return record.duplicate(true)


func _normalize_delegation(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"delegation_id", "source_kind", "source_id", "delegator_context", "recipient_person_id",
		"target_scope", "spatial_scope", "subject_scope", "amount_or_quantity_limit",
		"valid_from", "valid_until", "redelegable", "revocable", "exclusive_or_concurrent", "revoked_at",
	]):
		return {}
	var delegation_id := str(record.get("delegation_id", ""))
	var source_kind := str(record.get("source_kind", ""))
	var source_id := str(record.get("source_id", ""))
	var recipient_person_id := str(record.get("recipient_person_id", ""))
	var target_scope := _normalized_unique_strings(record.get("target_scope"))
	var spatial_scope := _normalized_unique_strings(record.get("spatial_scope"))
	var subject_scope := _normalized_unique_strings(record.get("subject_scope"))
	var limit := _valid_limit(record.get("amount_or_quantity_limit"))
	var valid_from := _nonnegative_int(record.get("valid_from"))
	var valid_until := _optional_nonnegative_int(record.get("valid_until"))
	var revoked_at := _optional_nonnegative_int(record.get("revoked_at"))
	if (
		not _is_valid_token(delegation_id)
		or source_kind not in ["authority", "delegation"]
		or not _is_valid_token(source_id)
		or not _acting_context_valid(record.get("delegator_context", {}) as Dictionary)
		or not _known_person_ids.has(recipient_person_id)
		or target_scope.get("invalid", false)
		or spatial_scope.get("invalid", false)
		or subject_scope.get("invalid", false)
		or limit < -1.0
		or valid_from < 0
		or valid_until < -1
		or (valid_until >= 0 and valid_until < valid_from)
		or revoked_at < -1
		or typeof(record.get("redelegable")) != TYPE_BOOL
		or typeof(record.get("revocable")) != TYPE_BOOL
		or str(record.get("exclusive_or_concurrent", "")) not in ["exclusive", "concurrent"]
	):
		return {}
	return {
		"delegation_id": delegation_id,
		"source_kind": source_kind,
		"source_id": source_id,
		"delegator_context": (record.get("delegator_context") as Dictionary).duplicate(true),
		"recipient_person_id": recipient_person_id,
		"target_scope": target_scope.get("values", []),
		"spatial_scope": spatial_scope.get("values", []),
		"subject_scope": subject_scope.get("values", []),
		"amount_or_quantity_limit": limit,
		"valid_from": valid_from,
		"valid_until": valid_until,
		"redelegable": bool(record.get("redelegable")),
		"revocable": bool(record.get("revocable")),
		"exclusive_or_concurrent": str(record.get("exclusive_or_concurrent")),
		"revoked_at": revoked_at,
	}


func _normalize_power_relation(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"relation_id", "relation_type", "source_entity", "target_entity",
		"represented_organization_id", "scope", "valid_from", "valid_until", "basis",
	]):
		return {}
	var relation_id := str(record.get("relation_id", ""))
	var relation_type := str(record.get("relation_type", ""))
	var organization_id := str(record.get("represented_organization_id", ""))
	var valid_from := _nonnegative_int(record.get("valid_from"))
	var valid_until := _optional_nonnegative_int(record.get("valid_until"))
	if (
		not _is_valid_token(relation_id)
		or relation_type not in _RELATION_TYPES
		or str(record.get("source_entity", "")).is_empty()
		or str(record.get("target_entity", "")).is_empty()
		or not _is_valid_organization_id(organization_id)
		or typeof(record.get("scope")) != TYPE_DICTIONARY
		or valid_from < 0 or valid_until < -1 or (valid_until >= 0 and valid_until < valid_from)
		or _normalize_basis(record.get("basis", {}) as Dictionary).is_empty()
	):
		return {}
	return {
		"relation_id": relation_id,
		"relation_type": relation_type,
		"source_entity": str(record.get("source_entity")),
		"target_entity": str(record.get("target_entity")),
		"represented_organization_id": organization_id,
		"scope": (record.get("scope") as Dictionary).duplicate(true),
		"valid_from": valid_from,
		"valid_until": valid_until,
		"basis": _normalize_basis(record.get("basis", {}) as Dictionary),
	}


func _normalize_power_transfer(record: Dictionary) -> Dictionary:
	if not _has_exact_fields(record, [
		"transfer_id", "transfer_type", "source_ref", "target_ref", "basis_ref", "effective_at",
		"authority_id", "relation_id", "delegation_id",
	]):
		return {}
	var transfer_id := str(record.get("transfer_id", ""))
	var transfer_type := str(record.get("transfer_type", ""))
	var effective_at := _nonnegative_int(record.get("effective_at"))
	if (
		not _is_valid_token(transfer_id)
		or transfer_type not in _TRANSFER_TYPES
		or str(record.get("source_ref", "")).is_empty()
		or str(record.get("target_ref", "")).is_empty()
		or str(record.get("basis_ref", "")).is_empty()
		or effective_at < 0
	):
		return {}
	return {
		"transfer_id": transfer_id,
		"transfer_type": transfer_type,
		"source_ref": str(record.get("source_ref")),
		"target_ref": str(record.get("target_ref")),
		"basis_ref": str(record.get("basis_ref")),
		"effective_at": effective_at,
		"authority_id": str(record.get("authority_id", "")),
		"relation_id": str(record.get("relation_id", "")),
		"delegation_id": str(record.get("delegation_id", "")),
	}


func _authority_references_valid(record: Dictionary, bodies: Dictionary) -> bool:
	var represented := str(record.get("represented_entity", ""))
	if not _organization_core.has_organization(represented):
		return false
	var holder: Dictionary = record.get("holder", {}) as Dictionary
	var holder_kind := str(holder.get("kind", ""))
	var holder_org := str(holder.get("organization_id", ""))
	match holder_kind:
		"position":
			if not _organization_core.has_organization(holder_org) or _organization_core.position(holder_org, str(holder.get("local_id", ""))).is_empty():
				return false
		"decision_body":
			if not bodies.has(str(holder.get("local_id", ""))):
				return false
		"membership":
			if not _organization_core.has_organization(holder_org):
				return false
		"person":
			if not _known_person_ids.has(str(holder.get("person_id", ""))):
				return false
	for place_id: String in _string_array(record.get("spatial_scope", [])):
		if not _known_place_ids.has(place_id):
			return false
	var required_procedure_id := str((record.get("additional_constraints", {}) as Dictionary).get("required_procedure_id", ""))
	if not required_procedure_id.is_empty() and not _procedures.has(required_procedure_id):
		return false
	return true


func _decision_body_references_valid(record: Dictionary) -> bool:
	var organization_id := str(record.get("organization_id", ""))
	if not _organization_core.has_organization(organization_id):
		return false
	for raw_rule: Variant in record.get("eligible_participants", []) as Array:
		var rule: Dictionary = raw_rule as Dictionary
		if str(rule.get("kind", "")) == "position" and _organization_core.position(organization_id, str(rule.get("position_id", ""))).is_empty():
			return false
	return true


func _procedure_references_valid(record: Dictionary, bodies: Dictionary) -> bool:
	var organization_id := str(record.get("organization_id", ""))
	if not _organization_core.has_organization(organization_id):
		return false
	for raw_step: Variant in record.get("steps", []) as Array:
		var step: Dictionary = raw_step as Dictionary
		var body_id := str(step.get("decision_body_id", ""))
		if not bodies.has(body_id):
			return false
		if str((bodies[body_id] as Dictionary).get("organization_id", "")) != organization_id:
			return false
	return true


func _validate_complete_state(
	grants: Dictionary,
	bodies: Dictionary,
	procedures: Dictionary,
	proposals: Dictionary,
	delegations: Dictionary,
	relations: Dictionary,
	transfers: Dictionary
) -> bool:
	for body_id: String in _sorted_keys(bodies):
		if not _decision_body_references_valid(bodies[body_id] as Dictionary):
			return false
	for procedure_id: String in _sorted_keys(procedures):
		if not _procedure_references_valid(procedures[procedure_id] as Dictionary, bodies):
			return false
	for authority_id: String in _sorted_keys(grants):
		if not _authority_references_valid(grants[authority_id] as Dictionary, bodies):
			return false
		if _has_exclusive_authority_conflict(grants[authority_id] as Dictionary, grants, authority_id):
			return false
	for proposal_id: String in _sorted_keys(proposals):
		var proposal_record: Dictionary = proposals[proposal_id] as Dictionary
		if not procedures.has(str(proposal_record.get("procedure_id", ""))):
			return false
		if not _organization_core.has_organization(str(proposal_record.get("organization_id", ""))):
			return false
	for delegation_id: String in _sorted_keys(delegations):
		var delegation_record: Dictionary = delegations[delegation_id] as Dictionary
		var source_kind := str(delegation_record.get("source_kind", ""))
		var source_id := str(delegation_record.get("source_id", ""))
		if source_kind == "authority" and not grants.has(source_id):
			return false
		if source_kind == "delegation" and not delegations.has(source_id):
			return false
		if source_id == delegation_id:
			return false
	for relation_id: String in _sorted_keys(relations):
		if not _organization_core.has_organization(str((relations[relation_id] as Dictionary).get("represented_organization_id", ""))):
			return false
	for transfer_id: String in _sorted_keys(transfers):
		var transfer: Dictionary = transfers[transfer_id] as Dictionary
		var authority_id := str(transfer.get("authority_id", ""))
		var relation_id := str(transfer.get("relation_id", ""))
		var delegation_id := str(transfer.get("delegation_id", ""))
		if not authority_id.is_empty() and not grants.has(authority_id):
			return false
		if not relation_id.is_empty() and not relations.has(relation_id):
			return false
		if not delegation_id.is_empty() and not delegations.has(delegation_id):
			return false
	return true


func _has_exclusive_authority_conflict(
	new_record: Dictionary, source: Dictionary, ignore_id: String = ""
) -> bool:
	for authority_id: String in _sorted_keys(source):
		if authority_id == ignore_id:
			continue
		var existing: Dictionary = source[authority_id] as Dictionary
		if str(existing.get("represented_entity", "")) != str(new_record.get("represented_entity", "")):
			continue
		if str(existing.get("operation", "")) != str(new_record.get("operation", "")):
			continue
		if str(existing.get("exclusive_or_concurrent", "")) != "exclusive" and str(new_record.get("exclusive_or_concurrent", "")) != "exclusive":
			continue
		if not _time_ranges_overlap(existing, new_record):
			continue
		if (
			_scope_arrays_overlap(existing.get("target_scope", []), new_record.get("target_scope", []))
			and _scope_arrays_overlap(existing.get("spatial_scope", []), new_record.get("spatial_scope", []))
			and _scope_arrays_overlap(existing.get("subject_scope", []), new_record.get("subject_scope", []))
		):
			return true
	return false


func _has_delegation_exclusive_conflict(new_record: Dictionary) -> bool:
	if str(new_record.get("exclusive_or_concurrent", "")) != "exclusive":
		return false
	for delegation_id: String in _sorted_keys(_delegations):
		var existing: Dictionary = _delegations[delegation_id] as Dictionary
		if str(existing.get("source_kind", "")) != str(new_record.get("source_kind", "")) or str(existing.get("source_id", "")) != str(new_record.get("source_id", "")):
			continue
		if not _time_ranges_overlap(existing, new_record):
			continue
		if (
			_scope_arrays_overlap(existing.get("target_scope", []), new_record.get("target_scope", []))
			and _scope_arrays_overlap(existing.get("spatial_scope", []), new_record.get("spatial_scope", []))
			and _scope_arrays_overlap(existing.get("subject_scope", []), new_record.get("subject_scope", []))
		):
			return true
	return false


func _delegation_person_cycle(source_kind: String, source_id: String, recipient_person_id: String) -> bool:
	var current_kind := source_kind
	var current_id := source_id
	var visited: Dictionary = {}
	while current_kind == "delegation":
		if visited.has(current_id) or not _delegations.has(current_id):
			return true
		visited[current_id] = true
		var record: Dictionary = _delegations[current_id] as Dictionary
		if str(record.get("recipient_person_id", "")) == recipient_person_id:
			return true
		current_kind = str(record.get("source_kind", ""))
		current_id = str(record.get("source_id", ""))
	return false


func _array_scope_subset(child_value: Variant, parent_value: Variant) -> bool:
	var child := _string_array(child_value)
	var parent := _string_array(parent_value)
	if parent.is_empty():
		return true
	if child.is_empty():
		return false
	for item: String in child:
		if not parent.has(item):
			return false
	return true


func _scope_arrays_overlap(first_value: Variant, second_value: Variant) -> bool:
	var first := _string_array(first_value)
	var second := _string_array(second_value)
	if first.is_empty() or second.is_empty():
		return true
	for item: String in first:
		if second.has(item):
			return true
	return false


func _time_ranges_overlap(first: Dictionary, second: Dictionary) -> bool:
	var first_start := int(first.get("valid_from", 0))
	var second_start := int(second.get("valid_from", 0))
	var first_end := int(first.get("valid_until", -1))
	var second_end := int(second.get("valid_until", -1))
	if first_end >= 0 and second_start > first_end:
		return false
	if second_end >= 0 and first_start > second_end:
		return false
	return true


func _state_payload(
	revision_value: int,
	grants: Dictionary,
	bodies: Dictionary,
	procedures: Dictionary,
	proposals: Dictionary,
	delegations: Dictionary,
	relations: Dictionary,
	transfers: Dictionary
) -> Dictionary:
	return {
		"revision": revision_value,
		"authority_grants": _records_as_sorted_array(grants),
		"decision_bodies": _records_as_sorted_array(bodies),
		"procedures": _records_as_sorted_array(procedures),
		"proposals": _records_as_sorted_array(proposals),
		"delegations": _records_as_sorted_array(delegations),
		"power_relations": _records_as_sorted_array(relations),
		"power_transfers": _records_as_sorted_array(transfers),
	}


func _state_fingerprint_for(
	revision_value: int,
	grants: Dictionary,
	bodies: Dictionary,
	procedures: Dictionary,
	proposals: Dictionary,
	delegations: Dictionary,
	relations: Dictionary,
	transfers: Dictionary
) -> String:
	return JSON.stringify({
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"structure_fingerprint": structure_fingerprint(),
		"reference_fingerprint": _reference_fingerprint,
		"state": _state_payload(
			revision_value, grants, bodies, procedures, proposals, delegations, relations, transfers
		),
	}).sha256_text()


func _decode_record_array(raw_value: Variant, normalizer: Callable, id_field: String) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return {"invalid": true, "records": {}}
	var records: Dictionary = {}
	for raw_record: Variant in raw_value as Array:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return {"invalid": true, "records": {}}
		var normalized: Dictionary = normalizer.call(raw_record as Dictionary)
		if normalized.is_empty():
			return {"invalid": true, "records": {}}
		var record_id := str(normalized.get(id_field, ""))
		if records.has(record_id):
			return {"invalid": true, "records": {}}
		records[record_id] = normalized
	return {"invalid": false, "records": records}


func _records_as_sorted_array(source: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for key: String in _sorted_keys(source):
		output.append((source[key] as Dictionary).duplicate(true))
	return output


func _normalized_unique_strings(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return {"invalid": true, "values": []}
	var output: Array[String] = []
	for raw_item: Variant in raw_value as Array:
		if typeof(raw_item) != TYPE_STRING:
			return {"invalid": true, "values": []}
		var item := str(raw_item)
		if item.is_empty() or output.has(item):
			return {"invalid": true, "values": []}
		output.append(item)
	output.sort()
	return {"invalid": false, "values": output}


func _string_array(raw_value: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(raw_value) != TYPE_ARRAY:
		return output
	for raw_item: Variant in raw_value as Array:
		if typeof(raw_item) == TYPE_STRING:
			output.append(str(raw_item))
	output.sort()
	return output


func _sorted_keys(source: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for raw_key: Variant in source.keys():
		if typeof(raw_key) == TYPE_STRING:
			output.append(str(raw_key))
	output.sort()
	return output


func _is_valid_person_id(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "person"


func _is_valid_place_id(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "place"


func _is_valid_organization_id(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == "organization"


func _is_valid_operation(value: String) -> bool:
	return _is_valid_token(value) and value.contains(".")


func _is_valid_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var character := value.substr(index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_.:-/".contains(character):
			return false
	return true


func _sanitize_token(value: String) -> String:
	var output := ""
	for index: int in value.length():
		var character := value.substr(index, 1).to_lower()
		output += character if "abcdefghijklmnopqrstuvwxyz0123456789_.".contains(character) else "_"
	return output


func _positive_int(value: Variant) -> int:
	if typeof(value) != TYPE_INT:
		return -1
	return int(value) if int(value) > 0 else -1


func _nonnegative_int(value: Variant) -> int:
	if typeof(value) != TYPE_INT:
		return -1
	return int(value) if int(value) >= 0 else -1


func _optional_nonnegative_int(value: Variant) -> int:
	if typeof(value) != TYPE_INT:
		return -2
	return int(value) if int(value) >= -1 else -2


func _nonnegative_float(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return -1.0
	var result := float(value)
	return result if is_finite(result) and result >= 0.0 else -1.0


func _valid_limit(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return -2.0
	var result := float(value)
	return result if is_finite(result) and result >= -1.0 else -2.0


func _has_exact_fields(record: Dictionary, fields: Array[String]) -> bool:
	if record.size() != fields.size():
		return false
	for field: String in fields:
		if not record.has(field):
			return false
	return true
