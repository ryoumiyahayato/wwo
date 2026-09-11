extends SceneTree

const PEOPLE: Array[String] = [
	"person:alice",
	"person:bob",
	"person:carol",
	"person:dana",
	"person:erin",
	"person:frank",
]
const PLACES: Array[String] = [
	"place:capital",
	"place:branch",
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_position_authority_and_acting_identity()
	_test_scoped_authority_and_expiry()
	_test_company_decision_signature_execution_boundary()
	_test_delegation_subset_and_revocation()
	_test_structure_relations_do_not_imply_authority()
	_test_exclusive_and_concurrent_authority()
	_test_legacy_capability_projection()
	_test_government_party_military_union_semantics()
	_test_snapshot_round_trip_and_atomic_rejection()
	print("Organization authority foundation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_position_authority_and_acting_identity() -> void:
	var core := _new_core()
	_check(core != null, "position authority fixture creates OrganizationCore")
	if core == null:
		return
	_check(core.register_organization("organization:company", "company", "place:capital"), "company registers")
	_check(core.define_position("organization:company", "ceo", "CEO", 1), "CEO position registers")
	_check(core.add_member("organization:company", "person:alice"), "Alice joins company")
	_check(core.create_appointment("organization:company", "ceo_alice", "person:alice", "ceo"), "Alice appointment registers")
	var authority := _new_authority(core)
	_check(authority != null, "authority foundation binds existing core")
	if authority == null:
		return
	_check(
		authority.add_authority_grant(_grant(
			"authority.company.ceo.represent",
			VNextOrganizationAuthorityFoundation.position_holder("organization:company", "ceo"),
			"organization:company",
			"organization.represent",
			[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
		)),
		"position-scoped authority grant registers"
	)
	var no_appointment := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice",
		"organization:company",
		"organization:company",
		"authority.company.ceo.represent"
	)
	_equal(
		_status(authority.resolve_authority(no_appointment, "organization.represent", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"Position authority cannot be exercised without the matching Appointment"
	)
	var alice_ceo := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice",
		"organization:company",
		"organization:company",
		"authority.company.ceo.represent",
		"ceo_alice"
	)
	_equal(
		_status(authority.resolve_authority(alice_ceo, "organization.represent", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
		"matching Appointment activates Position authority only in the selected acting identity"
	)
	_check(core.remove_appointment("organization:company", "ceo_alice"), "old CEO appointment ends")
	_check(core.add_member("organization:company", "person:bob"), "Bob joins company")
	_check(core.create_appointment("organization:company", "ceo_bob", "person:bob", "ceo"), "Bob becomes CEO")
	_equal(
		_status(authority.resolve_authority(alice_ceo, "organization.represent", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_INVALID_ACTING_CONTEXT,
		"ended Appointment immediately invalidates former holder context"
	)
	var bob_ceo := VNextOrganizationAuthorityFoundation.acting_context(
		"person:bob",
		"organization:company",
		"organization:company",
		"authority.company.ceo.represent",
		"ceo_bob"
	)
	_equal(
		_status(authority.resolve_authority(bob_ceo, "organization.represent", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
		"replacement Appointment moves effective Position authority without copying power into a Person"
	)

	_check(core.register_organization("organization:party", "party", "place:capital"), "party registers")
	_check(core.define_position("organization:party", "chair", "Chair", 1), "party chair position registers")
	_check(core.add_member("organization:party", "person:bob"), "Bob joins party")
	_check(core.create_appointment("organization:party", "chair_bob", "person:bob", "chair"), "Bob becomes party chair")
	_check(
		authority.add_authority_grant(_grant(
			"authority.party.chair.represent",
			VNextOrganizationAuthorityFoundation.position_holder("organization:party", "chair"),
			"organization:party",
			"organization.represent",
			[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
		)),
		"separate party authority registers"
	)
	var bob_party := VNextOrganizationAuthorityFoundation.acting_context(
		"person:bob",
		"organization:party",
		"organization:party",
		"authority.party.chair.represent",
		"chair_bob"
	)
	_equal(
		_status(authority.resolve_authority(bob_party, "organization.represent", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
		"same Person can select a separate party acting identity"
	)
	var mixed_identity := VNextOrganizationAuthorityFoundation.acting_context(
		"person:bob",
		"organization:party",
		"organization:company",
		"authority.company.ceo.represent",
		"chair_bob"
	)
	_equal(
		_status(authority.resolve_authority(mixed_identity, "organization.represent", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"positions across organizations are not merged into a Person-wide power bag"
	)


func _test_scoped_authority_and_expiry() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "scope fixture creates OrganizationCore")
		return
	_check(core.register_organization("organization:agency", "government_body", "place:capital"), "agency registers")
	_check(core.define_position("organization:agency", "officer", "Officer", 1), "officer position registers")
	_check(core.add_member("organization:agency", "person:alice"), "officer is member")
	_check(core.create_appointment("organization:agency", "officer_alice", "person:alice", "officer"), "officer appointment registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "scope fixture creates authority foundation")
		return
	var grant := _grant(
		"authority.agency.issue",
		VNextOrganizationAuthorityFoundation.position_holder("organization:agency", "officer"),
		"organization:agency",
		"government.issue_document",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION],
		["target:licensed_entity"],
		["place:capital"],
		["subject:permit"],
		100.0,
		5,
		10
	)
	_check(authority.add_authority_grant(grant), "scoped authority registers")
	var context := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:agency", "organization:agency", "authority.agency.issue", "officer_alice"
	)
	_equal(
		_status(authority.resolve_authority(context, "government.issue_document", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "target:licensed_entity", "place:capital", "subject:permit", 100.0, 5)),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
		"exact target, spatial, subject and amount scope authorizes"
	)
	_equal(
		_status(authority.resolve_authority(context, "government.issue_document", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "target:other", "place:capital", "subject:permit", 10.0, 5)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"target scope overreach fails closed"
	)
	_equal(
		_status(authority.resolve_authority(context, "government.issue_document", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "target:licensed_entity", "place:branch", "subject:permit", 10.0, 5)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"spatial scope overreach fails closed"
	)
	_equal(
		_status(authority.resolve_authority(context, "government.issue_document", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "target:licensed_entity", "place:capital", "subject:other", 10.0, 5)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"subject scope overreach fails closed"
	)
	_equal(
		_status(authority.resolve_authority(context, "government.issue_document", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "target:licensed_entity", "place:capital", "subject:permit", 100.01, 5)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"amount or quantity limit overreach fails closed"
	)
	_equal(
		_status(authority.resolve_authority(context, "government.issue_document", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "target:licensed_entity", "place:capital", "subject:permit", 1.0, 11)),
		VNextOrganizationAuthorityFoundation.STATUS_EXPIRED,
		"expired authority cannot be exercised"
	)


func _test_company_decision_signature_execution_boundary() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "company decision fixture creates core")
		return
	_check(core.register_organization("organization:firm", "company", "place:capital"), "firm registers")
	for position_record: Dictionary in [
		{"id": "ceo", "title": "CEO", "person": "person:alice", "appointment": "ceo_alice"},
		{"id": "director_a", "title": "Director A", "person": "person:bob", "appointment": "director_bob"},
		{"id": "director_b", "title": "Director B", "person": "person:carol", "appointment": "director_carol"},
		{"id": "director_c", "title": "Director C", "person": "person:dana", "appointment": "director_dana"},
	]:
		_check(core.define_position("organization:firm", str(position_record.id), str(position_record.title), 1), "company position %s registers" % position_record.id)
		_check(core.add_member("organization:firm", str(position_record.person)), "company member %s registers" % position_record.person)
		_check(core.create_appointment("organization:firm", str(position_record.appointment), str(position_record.person), str(position_record.id)), "company appointment %s registers" % position_record.appointment)
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "company decision fixture creates authority")
		return
	_check(authority.define_decision_body({
		"decision_body_id": "board",
		"organization_id": "organization:firm",
		"eligible_participants": [
			_participant_position("director_a", 1),
			_participant_position("director_b", 1),
			_participant_position("director_c", 1),
		],
		"active": true,
	}), "board DecisionBody registers")
	_check(authority.define_procedure({
		"procedure_id": "board_majority",
		"organization_id": "organization:firm",
		"steps": [_step("board_vote", "board", 1, 2, 1, 2, "eligible_count", "reject")],
		"deadline": 100,
	}), "board majority Procedure registers")
	_check(authority.add_authority_grant(_grant(
		"authority.firm.ceo.propose",
		VNextOrganizationAuthorityFoundation.position_holder("organization:firm", "ceo"),
		"organization:firm",
		"organization.commitment",
		[VNextOrganizationAuthorityFoundation.STAGE_PROPOSAL]
	)), "CEO proposal authority registers")
	var represent_grant := _grant(
		"authority.firm.ceo.sign",
		VNextOrganizationAuthorityFoundation.position_holder("organization:firm", "ceo"),
		"organization:firm",
		"organization.commitment",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
	)
	represent_grant["additional_constraints"] = VNextOrganizationAuthorityFoundation.constraints(
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION],
		"board_majority"
	)
	_check(authority.add_authority_grant(represent_grant), "CEO signature authority is conditioned on board approval")
	var execute_grant := _grant(
		"authority.firm.ceo.execute_boundary",
		VNextOrganizationAuthorityFoundation.position_holder("organization:firm", "ceo"),
		"organization:firm",
		"organization.commitment",
		[VNextOrganizationAuthorityFoundation.STAGE_DOMAIN_EXECUTION]
	)
	execute_grant["additional_constraints"] = VNextOrganizationAuthorityFoundation.constraints(
		[VNextOrganizationAuthorityFoundation.STAGE_DOMAIN_EXECUTION],
		"board_majority"
	)
	_check(authority.add_authority_grant(execute_grant), "domain execution boundary authority registers without owning domain execution")
	_check(authority.add_authority_grant(_grant(
		"authority.firm.board.collective",
		VNextOrganizationAuthorityFoundation.decision_body_holder("organization:firm", "board"),
		"organization:firm",
		"organization.approve_commitment",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
	)), "collective DecisionBody authority can exist independently from chair or participants")

	var ceo_proposal := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:firm", "organization:firm", "authority.firm.ceo.propose", "ceo_alice"
	)
	var proposal := {
		"proposal_id": "project_alpha",
		"organization_id": "organization:firm",
		"operation": "organization.commitment",
		"target_id": "counterparty:alpha",
		"spatial_place_id": "place:capital",
		"subject_id": "subject:project_alpha",
		"amount_or_quantity": 50.0,
		"content_fingerprint": "a".repeat(64),
		"version": 1,
		"proposer_context": ceo_proposal,
		"procedure_id": "board_majority",
		"created_at": 1,
		"status": "proposed",
		"step_results": {},
		"votes": [],
		"signatures": [],
		"decision_id": "",
	}
	_check(authority.create_proposal(proposal), "authorized proposer creates versioned proposal")
	var ceo_sign := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:firm", "organization:firm", "authority.firm.ceo.sign", "ceo_alice"
	)
	_check(not authority.sign_proposal("project_alpha", 1, "signature.preapproval", ceo_sign, 2), "signature cannot precede collective approval")
	var ceo_execute := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:firm", "organization:firm", "authority.firm.ceo.execute_boundary", "ceo_alice"
	)
	_equal(
		_status(authority.authorize_domain_execution("project_alpha", ceo_execute, 2)),
		VNextOrganizationAuthorityFoundation.STATUS_AWAITING_APPROVAL,
		"proposal is not domain-executable before approval"
	)
	_check(authority.cast_vote("project_alpha", "board_vote", "person:bob", 1, "yes", false, 2), "director B votes yes")
	_check(authority.cast_vote("project_alpha", "board_vote", "person:carol", 1, "yes", false, 2), "director C votes yes")
	_check(authority.cast_vote("project_alpha", "board_vote", "person:dana", 1, "no", false, 2), "director D votes no")
	_check(not authority.cast_vote("project_alpha", "board_vote", "person:erin", 1, "yes", false, 2), "ineligible Person cannot vote as board")
	_check(not authority.cast_vote("project_alpha", "board_vote", "person:bob", 2, "yes", false, 2), "wrong proposal version is rejected")
	_check(authority.finalize_proposal_step("project_alpha", "board_vote", 3), "quorum and majority approve board step")
	_equal(str(authority.proposal("project_alpha").get("status", "")), "approved", "collective decision marks exact proposal version approved")
	_equal(
		_status(authority.authorize_domain_execution("project_alpha", ceo_execute, 3)),
		VNextOrganizationAuthorityFoundation.STATUS_APPROVED_NOT_REPRESENTABLE,
		"approval does not imply representation or signature"
	)
	var director_context := VNextOrganizationAuthorityFoundation.acting_context(
		"person:bob", "organization:firm", "organization:firm", "authority.firm.board.collective", "director_bob"
	)
	_equal(
		_status(authority.resolve_authority(director_context, "organization.approve_commitment", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"one board participant cannot impersonate the collective DecisionBody"
	)
	_check(authority.sign_proposal("project_alpha", 1, "signature.ceo", ceo_sign, 4), "authorized representative signs approved exact proposal version")
	_equal(
		_status(authority.authorize_domain_execution("project_alpha", ceo_execute, 4)),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED_FOR_DOMAIN_EXECUTION,
		"signed approved decision crosses only the Organization authorization boundary"
	)
	_check(
		not authority.proposal("project_alpha").has("paid")
		and not authority.proposal("project_alpha").has("inventory")
		and not authority.proposal("project_alpha").has("battle_result"),
		"Organization decision state owns no Economy or Military execution facts"
	)

	var quorum_core := _new_core()
	if quorum_core != null:
		_check(quorum_core.register_organization("organization:committee", "association", "place:capital"), "quorum committee registers")
		for index: int in 3:
			var pid := PEOPLE[index]
			var position_id := "seat_%d" % index
			var appointment_id := "seat_%d_holder" % index
			_check(quorum_core.define_position("organization:committee", position_id, position_id, 1), "quorum seat registers")
			_check(quorum_core.add_member("organization:committee", pid), "quorum member registers")
			_check(quorum_core.create_appointment("organization:committee", appointment_id, pid, position_id), "quorum appointment registers")
		var quorum_authority := _new_authority(quorum_core)
		if quorum_authority != null:
			_check(quorum_authority.define_decision_body({
				"decision_body_id": "committee_body",
				"organization_id": "organization:committee",
				"eligible_participants": [_participant_position("seat_0", 1), _participant_position("seat_1", 1), _participant_position("seat_2", 1)],
				"active": true,
			}), "quorum body registers")
			_check(quorum_authority.define_procedure({
				"procedure_id": "two_thirds_quorum",
				"organization_id": "organization:committee",
				"steps": [_step("vote", "committee_body", 2, 3, 1, 2, "eligible_count", "reject")],
				"deadline": 10,
			}), "quorum procedure registers")
			_check(quorum_authority.add_authority_grant(_grant(
				"authority.committee.propose",
				VNextOrganizationAuthorityFoundation.position_holder("organization:committee", "seat_0"),
				"organization:committee",
				"organization.motion",
				[VNextOrganizationAuthorityFoundation.STAGE_PROPOSAL]
			)), "quorum proposer grant registers")
			var qctx := VNextOrganizationAuthorityFoundation.acting_context("person:alice", "organization:committee", "organization:committee", "authority.committee.propose", "seat_0_holder")
			_check(quorum_authority.create_proposal(_proposal_record("quorum_case", "organization:committee", "organization.motion", qctx, "two_thirds_quorum", "b".repeat(64))), "quorum proposal registers")
			_check(quorum_authority.cast_vote("quorum_case", "vote", "person:alice", 1, "yes", false, 1), "single quorum vote is recorded")
			_check(not quorum_authority.finalize_proposal_step("quorum_case", "vote", 1), "insufficient quorum cannot finalize as approval")


func _test_delegation_subset_and_revocation() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "delegation fixture creates core")
		return
	_check(core.register_organization("organization:delegator", "company", "place:capital"), "delegation organization registers")
	_check(core.define_position("organization:delegator", "director", "Director", 1), "delegator position registers")
	_check(core.add_member("organization:delegator", "person:alice"), "delegator member registers")
	_check(core.create_appointment("organization:delegator", "director_alice", "person:alice", "director"), "delegator appointment registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "delegation authority fixture creates")
		return
	_check(authority.add_authority_grant(_grant(
		"authority.delegator.contract",
		VNextOrganizationAuthorityFoundation.position_holder("organization:delegator", "director"),
		"organization:delegator",
		"organization.sign_contract",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, VNextOrganizationAuthorityFoundation.STAGE_DELEGATION],
		["counterparty:a", "counterparty:b"],
		["place:capital", "place:branch"],
		["subject:supply", "subject:service"],
		1000.0,
		0,
		100,
		true
	)), "delegable source authority registers")
	var delegator := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:delegator", "organization:delegator", "authority.delegator.contract", "director_alice"
	)
	var delegation := _delegation_record(
		"delegation.bob.contract",
		"authority",
		"authority.delegator.contract",
		delegator,
		"person:bob",
		["counterparty:a"],
		["place:capital"],
		["subject:supply"],
		200.0,
		1,
		50,
		true
	)
	_check(authority.create_delegation(delegation), "delegated scope that is a strict subset of source scope is accepted")
	var expanded := _delegation_record(
		"delegation.invalid.expansion",
		"authority",
		"authority.delegator.contract",
		delegator,
		"person:carol",
		["counterparty:a", "counterparty:outside"],
		["place:capital"],
		["subject:supply"],
		200.0,
		1,
		50,
		false
	)
	_check(not authority.create_delegation(expanded), "delegation cannot expand target scope")
	var amount_expansion := _delegation_record(
		"delegation.invalid.amount",
		"authority",
		"authority.delegator.contract",
		delegator,
		"person:carol",
		["counterparty:a"],
		["place:capital"],
		["subject:supply"],
		1001.0,
		1,
		50,
		false
	)
	_check(not authority.create_delegation(amount_expansion), "delegation cannot expand amount limit")
	var bob := VNextOrganizationAuthorityFoundation.acting_context(
		"person:bob", "organization:delegator", "organization:delegator", "authority.delegator.contract", "", false, "", "delegation.bob.contract"
	)
	_equal(
		_status(authority.resolve_authority(bob, "organization.sign_contract", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "counterparty:a", "place:capital", "subject:supply", 199.0, 2)),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
		"delegation recipient can act only through explicit delegation identity"
	)
	_equal(
		_status(authority.resolve_authority(bob, "organization.sign_contract", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "counterparty:b", "place:capital", "subject:supply", 10.0, 2)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"delegation recipient cannot recover broader source target scope"
	)
	var redelegation := _delegation_record(
		"delegation.carol.contract",
		"delegation",
		"delegation.bob.contract",
		bob,
		"person:carol",
		["counterparty:a"],
		["place:capital"],
		["subject:supply"],
		100.0,
		2,
		40,
		false
	)
	_check(authority.create_delegation(redelegation), "explicitly redelegable delegation can create a narrower basis chain")
	var carol := VNextOrganizationAuthorityFoundation.acting_context(
		"person:carol", "organization:delegator", "organization:delegator", "authority.delegator.contract", "", false, "", "delegation.carol.contract"
	)
	var resolved_chain := authority.resolve_authority(carol, "organization.sign_contract", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "counterparty:a", "place:capital", "subject:supply", 99.0, 3)
	_equal(_status(resolved_chain), VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED, "redelegated recipient resolves through source chain")
	_equal((resolved_chain.get("basis_chain", []) as Array).size(), 3, "redelegation preserves full authority basis chain")
	_check(authority.revoke_delegation("delegation.bob.contract", 4), "source delegation revocation records")
	_equal(
		_status(authority.resolve_authority(bob, "organization.sign_contract", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "counterparty:a", "place:capital", "subject:supply", 10.0, 4)),
		VNextOrganizationAuthorityFoundation.STATUS_DELEGATION_INVALID,
		"revoked delegation stops recipient authority"
	)
	_equal(
		_status(authority.resolve_authority(carol, "organization.sign_contract", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "counterparty:a", "place:capital", "subject:supply", 10.0, 4)),
		VNextOrganizationAuthorityFoundation.STATUS_DELEGATION_INVALID,
		"source delegation revocation invalidates downstream redelegation"
	)


func _test_structure_relations_do_not_imply_authority() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "structural relation fixture creates core")
		return
	_check(core.register_organization("organization:parent", "government_body", "place:capital"), "parent organization registers")
	_check(core.register_organization("organization:child", "government_body", "place:branch", "organization:parent"), "child organization registers under structural parent")
	_check(core.define_position("organization:parent", "supervisor", "Supervisor", 1), "parent supervisor position registers")
	_check(core.define_position("organization:child", "director", "Director", 1), "child director position registers")
	_check(core.add_member("organization:parent", "person:alice"), "parent member registers")
	_check(core.add_member("organization:child", "person:bob"), "child member registers")
	_check(core.create_appointment("organization:parent", "supervisor_alice", "person:alice", "supervisor"), "parent appointment registers")
	_check(core.create_appointment("organization:child", "director_bob", "person:bob", "director"), "child appointment registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "structure relation authority fixture creates")
		return
	_check(authority.add_authority_grant(_grant(
		"authority.child.sign",
		VNextOrganizationAuthorityFoundation.position_holder("organization:child", "director"),
		"organization:child",
		"organization.sign_order",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
	)), "child director authority registers")
	var parent_context := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:parent", "organization:child", "authority.child.sign", "supervisor_alice"
	)
	_equal(
		_status(authority.resolve_authority(parent_context, "organization.sign_order", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE,
		"structural parent relationship does not inherit child authority"
	)
	_check(authority.add_power_relation({
		"relation_id": "relation.parent.supervises.child",
		"relation_type": "supervision",
		"source_entity": "organization:parent",
		"target_entity": "organization:child",
		"represented_organization_id": "organization:parent",
		"scope": {"subject": "audit"},
		"valid_from": 0,
		"valid_until": -1,
		"basis": {"kind": "charter", "id": "charter.parent_child"},
	}), "typed supervision relation registers")
	var supervision_as_power := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:parent", "organization:parent", "relation.parent.supervises.child", "supervisor_alice"
	)
	_equal(
		_status(authority.resolve_authority(supervision_as_power, "organization.sign_order", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_UNKNOWN_AUTHORITY,
		"supervision relation is not command or signature authority"
	)
	_check(authority.add_power_relation({
		"relation_id": "relation.parent.appoints.child",
		"relation_type": "appointment",
		"source_entity": "organization:parent",
		"target_entity": "position:child/director",
		"represented_organization_id": "organization:child",
		"scope": {"position": "director"},
		"valid_from": 0,
		"valid_until": -1,
		"basis": {"kind": "charter", "id": "charter.appointment"},
	}), "appointment power relation is represented separately")
	_equal(
		_status(authority.resolve_authority(supervision_as_power, "organization.sign_order", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)),
		VNextOrganizationAuthorityFoundation.STATUS_UNKNOWN_AUTHORITY,
		"appointment relation does not copy the appointee's business authority into appointing actor"
	)


func _test_exclusive_and_concurrent_authority() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "exclusive fixture creates core")
		return
	_check(core.register_organization("organization:exclusive", "association", "place:capital"), "exclusive fixture organization registers")
	_check(core.define_position("organization:exclusive", "a", "A", 1), "position A registers")
	_check(core.define_position("organization:exclusive", "b", "B", 1), "position B registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "exclusive fixture creates authority")
		return
	var concurrent_a := _grant(
		"authority.concurrent.a",
		VNextOrganizationAuthorityFoundation.position_holder("organization:exclusive", "a"),
		"organization:exclusive",
		"organization.review",
		[VNextOrganizationAuthorityFoundation.STAGE_PROPOSAL]
	)
	var concurrent_b := _grant(
		"authority.concurrent.b",
		VNextOrganizationAuthorityFoundation.position_holder("organization:exclusive", "b"),
		"organization:exclusive",
		"organization.review",
		[VNextOrganizationAuthorityFoundation.STAGE_PROPOSAL]
	)
	_check(authority.add_authority_grant(concurrent_a), "first concurrent authority registers")
	_check(authority.add_authority_grant(concurrent_b), "overlapping concurrent authority is explicitly allowed")
	var exclusive := _grant(
		"authority.exclusive",
		VNextOrganizationAuthorityFoundation.position_holder("organization:exclusive", "a"),
		"organization:exclusive",
		"organization.review",
		[VNextOrganizationAuthorityFoundation.STAGE_PROPOSAL]
	)
	exclusive["exclusive_or_concurrent"] = "exclusive"
	_check(not authority.add_authority_grant(exclusive), "overlapping exclusive authority conflict fails closed")


func _test_legacy_capability_projection() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "legacy capability fixture creates core")
		return
	_check(core.register_organization("organization:legacy", "association", "place:capital"), "legacy organization registers")
	_check(core.define_capability("organization:legacy", "organization.manage_appointments"), "legacy organization declares controlled capability")
	_check(core.define_position("organization:legacy", "secretary", "Secretary", 1, ["organization.manage_appointments"]), "legacy Position retains capability data")
	_check(core.add_member("organization:legacy", "person:alice"), "legacy member registers")
	_check(core.create_appointment("organization:legacy", "secretary_alice", "person:alice", "secretary"), "legacy appointment registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "legacy capability fixture creates authority")
		return
	_check(authority.migrate_legacy_position_capabilities("organization:legacy"), "legacy capability migrates into authoritative scoped grant")
	var context := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:legacy", "organization:legacy", "legacy.organization_legacy.secretary.organization.manage_appointments", "secretary_alice"
	)
	_equal(
		authority.legacy_capabilities_for_context(context),
		["organization.manage_appointments"],
		"capability_ids survive only as a derived compatibility projection from authority"
	)
	_check(core.has_capability("person:alice", "organization:legacy", "organization.manage_appointments"), "legacy OrganizationCore behavior remains intact during migration")


func _test_government_party_military_union_semantics() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "cross-institution fixture creates core")
		return
	for org_record: Dictionary in [
		{"id": "organization:ministry", "kind": "government_body", "place": "place:capital"},
		{"id": "organization:parliament", "kind": "government_body", "place": "place:capital"},
		{"id": "organization:party", "kind": "party", "place": "place:capital"},
		{"id": "organization:army", "kind": "military_institution", "place": "place:branch"},
		{"id": "organization:union", "kind": "union", "place": "place:branch"},
	]:
		_check(core.register_organization(str(org_record.id), str(org_record.kind), str(org_record.place)), "cross-institution organization %s registers" % org_record.id)
	_check(core.define_position("organization:ministry", "minister", "Minister", 1), "minister position registers")
	_check(core.add_member("organization:ministry", "person:alice"), "minister member registers")
	_check(core.create_appointment("organization:ministry", "minister_alice", "person:alice", "minister"), "minister appointment registers")
	_check(core.add_member("organization:parliament", "person:bob"), "parliament member B registers")
	_check(core.add_member("organization:parliament", "person:carol"), "parliament member C registers")
	_check(core.add_member("organization:parliament", "person:dana"), "parliament member D registers")
	_check(core.define_position("organization:party", "chair", "Chair", 1), "party chair registers")
	_check(core.add_member("organization:party", "person:alice"), "party Alice membership registers")
	_check(core.create_appointment("organization:party", "chair_alice", "person:alice", "chair"), "Alice party appointment registers")
	_check(core.define_position("organization:army", "commander", "Commander", 1), "military commander registers")
	_check(core.add_member("organization:army", "person:erin"), "military member registers")
	_check(core.create_appointment("organization:army", "commander_erin", "person:erin", "commander"), "administrative military appointment registers")
	_check(core.define_position("organization:union", "negotiator", "Negotiator", 1), "union negotiator registers")
	_check(core.add_member("organization:union", "person:bob"), "union Bob membership registers")
	_check(core.add_member("organization:union", "person:carol"), "union Carol membership registers")
	_check(core.add_member("organization:union", "person:dana"), "union Dana membership registers")
	_check(core.create_appointment("organization:union", "negotiator_bob", "person:bob", "negotiator"), "union negotiator appointment registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "cross-institution authority fixture creates")
		return
	_check(authority.add_authority_grant(_grant(
		"authority.ministry.minister",
		VNextOrganizationAuthorityFoundation.position_holder("organization:ministry", "minister"),
		"organization:ministry",
		"government.issue_department_order",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
	)), "minister has explicit department-scoped authority")
	var minister := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:ministry", "organization:ministry", "authority.ministry.minister", "minister_alice"
	)
	_equal(_status(authority.resolve_authority(minister, "government.issue_department_order", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)), VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED, "minister can exercise ministry authority")
	var party_as_ministry := VNextOrganizationAuthorityFoundation.acting_context(
		"person:alice", "organization:party", "organization:ministry", "authority.ministry.minister", "chair_alice"
	)
	_equal(_status(authority.resolve_authority(party_as_ministry, "government.issue_department_order", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION)), VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE, "party Position cannot become a public office decision")

	_check(authority.define_decision_body({
		"decision_body_id": "parliament_members",
		"organization_id": "organization:parliament",
		"eligible_participants": [{"kind": "membership", "person_id": "", "position_id": "", "weight": 1}],
		"active": true,
	}), "parliament collective membership body registers")
	_check(authority.define_procedure({
		"procedure_id": "parliament_budget_vote",
		"organization_id": "organization:parliament",
		"steps": [_step("budget_vote", "parliament_members", 1, 2, 1, 2, "eligible_count", "reject")],
		"deadline": 100,
	}), "parliament collective approval procedure registers")

	_check(authority.add_power_relation({
		"relation_id": "relation.army.temporary_command",
		"relation_type": "temporary_command_assignment",
		"source_entity": "person:erin",
		"target_entity": "unit:field_force",
		"represented_organization_id": "organization:army",
		"scope": {"operational": true, "administrative": false},
		"valid_from": 10,
		"valid_until": 20,
		"basis": {"kind": "order", "id": "order.temp_command"},
	}), "temporary operational command assignment coexists with administrative appointment")
	var command_relation_as_signature := VNextOrganizationAuthorityFoundation.acting_context(
		"person:erin", "organization:army", "organization:army", "relation.army.temporary_command", "commander_erin"
	)
	_equal(_status(authority.resolve_authority(command_relation_as_signature, "organization.sign_contract", VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION, "", "", "", 0.0, 12)), VNextOrganizationAuthorityFoundation.STATUS_UNKNOWN_AUTHORITY, "temporary command relation does not transfer administrative asset or signature power")

	_check(authority.define_decision_body({
		"decision_body_id": "union_members",
		"organization_id": "organization:union",
		"eligible_participants": [{"kind": "membership", "person_id": "", "position_id": "", "weight": 1}],
		"active": true,
	}), "union membership DecisionBody registers")
	_check(authority.define_procedure({
		"procedure_id": "union_member_vote",
		"organization_id": "organization:union",
		"steps": [_step("member_vote", "union_members", 1, 2, 1, 2, "eligible_count", "reject")],
		"deadline": 50,
	}), "union member-vote Procedure registers")
	_check(authority.add_authority_grant(_grant(
		"authority.union.negotiator.propose",
		VNextOrganizationAuthorityFoundation.position_holder("organization:union", "negotiator"),
		"organization:union",
		"union.collective_action",
		[VNextOrganizationAuthorityFoundation.STAGE_PROPOSAL]
	)), "union negotiator proposal authority registers")
	var union_rep := _grant(
		"authority.union.negotiator.represent",
		VNextOrganizationAuthorityFoundation.position_holder("organization:union", "negotiator"),
		"organization:union",
		"union.collective_action",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
	)
	union_rep["additional_constraints"] = VNextOrganizationAuthorityFoundation.constraints([VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION], "union_member_vote")
	_check(authority.add_authority_grant(union_rep), "union negotiator representation depends on member approval")
	var union_proposer := VNextOrganizationAuthorityFoundation.acting_context("person:bob", "organization:union", "organization:union", "authority.union.negotiator.propose", "negotiator_bob")
	_check(authority.create_proposal(_proposal_record("union_action", "organization:union", "union.collective_action", union_proposer, "union_member_vote", "c".repeat(64))), "union proposal registers")
	_check(authority.cast_vote("union_action", "member_vote", "person:bob", 1, "yes", false, 1), "union Bob votes")
	_check(authority.cast_vote("union_action", "member_vote", "person:carol", 1, "yes", false, 1), "union Carol votes")
	_check(authority.cast_vote("union_action", "member_vote", "person:dana", 1, "no", false, 1), "union Dana votes")
	_check(authority.finalize_proposal_step("union_action", "member_vote", 2), "union membership approval finalizes")
	var union_signer := VNextOrganizationAuthorityFoundation.acting_context("person:bob", "organization:union", "organization:union", "authority.union.negotiator.represent", "negotiator_bob")
	_check(authority.sign_proposal("union_action", 1, "signature.union_negotiator", union_signer, 3), "negotiator represents union only after member approval")
	_equal(_status(authority.authorize_domain_execution("union_action", union_signer, 3)), VNextOrganizationAuthorityFoundation.STATUS_OUT_OF_SCOPE, "approved and signed union action still does not mutate Economy employment without explicit domain-execution authority")


func _test_snapshot_round_trip_and_atomic_rejection() -> void:
	var core := _new_core()
	if core == null:
		_check(false, "snapshot fixture creates core")
		return
	_check(core.register_organization("organization:persist", "association", "place:capital"), "snapshot organization registers")
	_check(core.define_position("organization:persist", "director", "Director", 1), "snapshot position registers")
	_check(core.add_member("organization:persist", "person:alice"), "snapshot member registers")
	_check(core.create_appointment("organization:persist", "director_alice", "person:alice", "director"), "snapshot appointment registers")
	var authority := _new_authority(core)
	if authority == null:
		_check(false, "snapshot authority fixture creates")
		return
	_check(authority.add_authority_grant(_grant(
		"authority.persist",
		VNextOrganizationAuthorityFoundation.position_holder("organization:persist", "director"),
		"organization:persist",
		"organization.persist_action",
		[VNextOrganizationAuthorityFoundation.STAGE_REPRESENTATION]
	)), "snapshot authority registers")
	_check(authority.add_power_relation({
		"relation_id": "relation.persist.accountability",
		"relation_type": "accountability",
		"source_entity": "position:director",
		"target_entity": "organization:persist",
		"represented_organization_id": "organization:persist",
		"scope": {"reporting": true},
		"valid_from": 0,
		"valid_until": -1,
		"basis": {"kind": "charter", "id": "charter.persist"},
	}), "snapshot power relation registers")
	_check(authority.record_power_transfer({
		"transfer_id": "transfer.persist.appointment",
		"transfer_type": "appointment_change",
		"source_ref": "position:director",
		"target_ref": "person:alice",
		"basis_ref": "appointment:director_alice",
		"effective_at": 0,
		"authority_id": "authority.persist",
		"relation_id": "relation.persist.accountability",
		"delegation_id": "",
	}), "power transfer audit fact registers")
	var saved := authority.snapshot()
	var restored := _new_authority(core)
	_check(restored != null and restored.restore(saved), "authority snapshot restores against exact structural/reference identity")
	if restored != null:
		_equal(restored.snapshot(), saved, "authority snapshot round trip is deterministic")
		_equal(restored.state_fingerprint(), authority.state_fingerprint(), "authority fingerprint survives restore")
		var before := restored.snapshot()
		var corrupted := saved.duplicate(true)
		corrupted["state_fingerprint"] = "0".repeat(64)
		_check(not restored.restore(corrupted), "corrupted authority fingerprint fails closed")
		_equal(restored.snapshot(), before, "failed fingerprint restore does not partially mutate live state")
		var duplicate := saved.duplicate(true)
		var grants: Array = duplicate.get("authority_grants", []) as Array
		grants.append((grants[0] as Dictionary).duplicate(true))
		_check(not restored.restore(duplicate), "duplicate authority ID fails closed before adoption")
		_equal(restored.snapshot(), before, "duplicate-ID restore failure remains atomic")
	var changed_core := _new_core()
	if changed_core != null:
		_check(changed_core.register_organization("organization:persist", "association", "place:capital"), "changed structure fixture registers same organization")
		_check(changed_core.define_position("organization:persist", "director", "Director", 1), "changed structure fixture registers position")
		var incompatible := _new_authority(changed_core)
		if incompatible != null:
			_check(not incompatible.restore(saved), "snapshot pinned to exact Organization structure fingerprint fails closed after structure drift")


func _new_core() -> VNextOrganizationCore:
	return VNextOrganizationCore.create(PEOPLE, PLACES)


func _new_authority(core: VNextOrganizationCore) -> VNextOrganizationAuthorityFoundation:
	return VNextOrganizationAuthorityFoundation.create(core, PEOPLE, PLACES)


func _grant(
	authority_id: String,
	holder: Dictionary,
	represented_entity: String,
	operation: String,
	allowed_stages: Array[String],
	target_scope: Array[String] = [],
	spatial_scope: Array[String] = [],
	subject_scope: Array[String] = [],
	amount_limit: float = -1.0,
	valid_from: int = 0,
	valid_until: int = -1,
	delegable: bool = false
) -> Dictionary:
	return {
		"authority_id": authority_id,
		"holder": holder,
		"represented_entity": represented_entity,
		"operation": operation,
		"target_scope": target_scope,
		"spatial_scope": spatial_scope,
		"subject_scope": subject_scope,
		"amount_or_quantity_limit": amount_limit,
		"valid_from": valid_from,
		"valid_until": valid_until,
		"basis": {"kind": "charter", "id": "basis.%s" % authority_id},
		"revocable": true,
		"delegable": delegable,
		"exclusive_or_concurrent": "concurrent",
		"additional_constraints": VNextOrganizationAuthorityFoundation.constraints(allowed_stages),
		"accountability": VNextOrganizationAuthorityFoundation.accountability(represented_entity),
		"revoked_at": -1,
	}


func _delegation_record(
	delegation_id: String,
	source_kind: String,
	source_id: String,
	delegator_context: Dictionary,
	recipient_person_id: String,
	target_scope: Array[String],
	spatial_scope: Array[String],
	subject_scope: Array[String],
	amount_limit: float,
	valid_from: int,
	valid_until: int,
	redelegable: bool
) -> Dictionary:
	return {
		"delegation_id": delegation_id,
		"source_kind": source_kind,
		"source_id": source_id,
		"delegator_context": delegator_context,
		"recipient_person_id": recipient_person_id,
		"target_scope": target_scope,
		"spatial_scope": spatial_scope,
		"subject_scope": subject_scope,
		"amount_or_quantity_limit": amount_limit,
		"valid_from": valid_from,
		"valid_until": valid_until,
		"redelegable": redelegable,
		"revocable": true,
		"exclusive_or_concurrent": "concurrent",
		"revoked_at": -1,
	}


func _participant_position(position_id: String, weight: int) -> Dictionary:
	return {
		"kind": "position",
		"person_id": "",
		"position_id": position_id,
		"weight": weight,
	}


func _step(
	step_id: String,
	body_id: String,
	quorum_numerator: int,
	quorum_denominator: int,
	threshold_numerator: int,
	threshold_denominator: int,
	denominator: String,
	tie_handling: String
) -> Dictionary:
	return {
		"step_id": step_id,
		"decision_body_id": body_id,
		"quorum_numerator": quorum_numerator,
		"quorum_denominator": quorum_denominator,
		"threshold_numerator": threshold_numerator,
		"threshold_denominator": threshold_denominator,
		"denominator": denominator,
		"tie_handling": tie_handling,
		"abstention_allowed": true,
		"recusal_allowed": true,
	}


func _proposal_record(
	proposal_id: String,
	organization_id: String,
	operation: String,
	proposer_context: Dictionary,
	procedure_id: String,
	content_fingerprint: String
) -> Dictionary:
	return {
		"proposal_id": proposal_id,
		"organization_id": organization_id,
		"operation": operation,
		"target_id": "",
		"spatial_place_id": "",
		"subject_id": "",
		"amount_or_quantity": 0.0,
		"content_fingerprint": content_fingerprint,
		"version": 1,
		"proposer_context": proposer_context,
		"procedure_id": procedure_id,
		"created_at": 0,
		"status": "proposed",
		"step_results": {},
		"votes": [],
		"signatures": [],
		"decision_id": "",
	}


func _status(result: Dictionary) -> String:
	return str(result.get("status", ""))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
