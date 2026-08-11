extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_identity_and_hierarchy()
	_test_membership_positions_and_appointments()
	_test_capability_authorization_and_inactive_semantics()
	_test_snapshot_determinism_and_round_trip()
	_test_restore_rejections_are_transactional()
	print("VNext organization core: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _new_core() -> VNextOrganizationCore:
	return VNextOrganizationCore.create(
		[
			"person:alice",
			"person:bob",
			"person:carol",
		],
		["place:capital", "place:branch"],
	)


func _test_identity_and_hierarchy() -> void:
	var core: VNextOrganizationCore = _new_core()
	_check(core != null, "reference catalogs create a vNext organization core")
	if core == null:
		return
	_check(core.is_valid(), "empty organization core is structurally valid")
	_check(
		core.register_organization(
			"organization:world_council", "institution", "place:capital"
		),
		"organization identity accepts an organization stable ID and place reference"
	)
	_check(
		core.register_organization(
			"organization:transport_union",
			"union",
			"place:branch",
			"organization:world_council"
		),
		"organization hierarchy accepts an existing parent"
	)
	_check(
		core.register_organization(
			"organization:branch_council",
			"institution",
			"",
			"organization:transport_union"
		),
		"nested subordinate organization is registered"
	)
	_check(
		not core.register_organization(
			"organization:orphan", "institution", "", "organization:missing"
		),
		"missing hierarchy parent is rejected"
	)
	_check(
		not core.register_organization(
			"organization:self_parent", "institution", "", "organization:self_parent"
		),
		"self parent is rejected"
	)
	_check(
		not core.register_organization(
			"organization:world_council", "institution", "place:capital"
		),
		"duplicate organization identity is rejected"
	)
	_equal(
		core.organization_ids(),
		[
			"organization:branch_council",
			"organization:transport_union",
			"organization:world_council",
		],
		"organization IDs are returned in deterministic order"
	)
	_equal(
		core.subordinate_organization_ids("organization:world_council"),
		["organization:transport_union"],
		"subordinate query returns only direct children"
	)
	_equal(
		core.parent_organization_id("organization:branch_council"),
		"organization:transport_union",
		"parent query returns the authoritative structural reference"
	)

	var before_cycle: Dictionary = core.snapshot()
	_check(
		not core.set_parent_organization(
			"organization:world_council", "organization:branch_council"
		),
		"hierarchy cycle is rejected"
	)
	_equal(core.snapshot(), before_cycle, "cycle rejection leaves hierarchy unchanged")
	_check(
		not core.register_organization(
			"organization:bad_place", "institution", "place:unknown"
		),
		"configured reference catalog rejects unknown place IDs"
	)
	_check(
		not core.register_organization(
			"organization:bad_id", "institution", "place:Capital"
		),
		"stable ID validation rejects malformed place IDs"
	)


func _test_membership_positions_and_appointments() -> void:
	var core: VNextOrganizationCore = _new_core()
	if core == null:
		_check(false, "membership fixture creates a core")
		return
	_check(
		core.register_organization("organization:party", "party", "place:capital"),
		"membership fixture organization registers"
	)
	_check(
		core.define_capability("organization:party", "party.manage_internal_appointments"),
		"organization declares a capability before it can be granted"
	)
	_check(
		core.define_position(
			"organization:party",
			"secretary",
			"Secretary",
			1,
			["party.manage_internal_appointments"]
		),
		"position definition accepts a local deterministic position ID"
	)
	_check(
		core.add_member("organization:party", "person:alice"),
		"membership is added independently from appointment"
	)
	_check(
		core.is_member("organization:party", "person:alice"),
		"member query recognizes the membership fact"
	)
	_equal(
		core.member_ids("organization:party"),
		["person:alice"],
		"member IDs are deterministic and do not include employment fields"
	)
	_check(
		not core.add_member("organization:party", "person:alice"),
		"duplicate membership is rejected"
	)
	_check(
		core.create_appointment(
			"organization:party",
			"secretary_alice",
			"person:alice",
			"secretary"
		),
		"membership-backed appointment is created"
	)
	_check(
		not core.create_appointment(
			"organization:party",
			"secretary_bob",
			"person:bob",
			"secretary"
		),
		"appointment requiring membership rejects a non-member"
	)
	_check(
		core.create_appointment(
			"organization:party",
			"advisor_bob",
			"person:bob",
			"secretary",
			false
		) == false,
		"single-slot position enforces appointment cardinality"
	)
	_check(
		not core.create_appointment(
			"organization:party",
			"position:bad", "person:bob", "secretary", false
		),
		"position IDs do not introduce a shared position stable-ID kind"
	)
	_check(
		core.define_position("organization:party", "advisor", "Advisor", 1),
		"second position is defined without any membership implication"
	)
	_check(
		core.appoint_person(
			"organization:party",
			"advisor_bob",
			"person:bob",
			"advisor",
			false
		),
		"explicit non-membership appointment is allowed"
	)
	_check(
		not core.is_member("organization:party", "person:bob"),
		"non-membership appointment does not create membership"
	)
	_check(
		core.remove_member("organization:party", "person:alice") == false,
		"required-membership appointment blocks implicit membership removal"
	)
	_check(
		core.remove_appointment("organization:party", "secretary_alice"),
		"appointment removal is explicit"
	)
	_check(
		core.remove_member("organization:party", "person:alice"),
		"membership can be removed after its required appointment ends"
	)
	_check(
		not core.create_appointment(
			"organization:party",
			"advisor_bob_duplicate",
			"person:bob",
			"advisor",
			false
		),
		"a person cannot hold contradictory simultaneous appointments in one organization"
	)
	_check(
		not core.create_appointment(
			"organization:party",
			"appointment:bad", "person:carol", "advisor", false
		),
		"appointment IDs remain organization-owned local IDs"
	)


func _test_capability_authorization_and_inactive_semantics() -> void:
	var core: VNextOrganizationCore = _new_core()
	if core == null:
		_check(false, "authorization fixture creates a core")
		return
	_check(
		core.register_organization("organization:military_office", "ministry", "place:capital"),
		"authorization fixture organization registers"
	)
	_check(
		core.define_capability(
			"organization:military_office", "military.issue_strategic_order"
		),
		"military capability is declared as authorization data"
	)
	_check(
		core.define_position(
			"organization:military_office",
			"war_minister",
			"War Minister",
			1
		),
		"war minister position exists without calling a military system"
	)
	_check(
		core.grant_capability(
			"organization:military_office",
			"war_minister",
			"military.issue_strategic_order"
		),
		"capability grant is attached to a position"
	)
	_check(
		core.appoint_person(
			"organization:military_office",
			"war_minister_alice",
			"person:alice",
			"war_minister",
			false
		),
		"appointment can explicitly use non-membership semantics"
	)
	_check(
		core.has_capability(
			"person:alice",
			"organization:military_office",
			"military.issue_strategic_order"
		),
		"authorization query grants capability from current appointment"
	)
	_equal(
		core.capabilities_for_person(
			"person:alice", "organization:military_office"
		),
		["military.issue_strategic_order"],
		"capability query returns deterministic declared grants"
	)
	_check(
		not core.has_capability(
			"person:bob",
			"organization:military_office",
			"military.issue_strategic_order"
		),
		"unappointed person has no authorization"
	)
	_check(
		not core.grant_capability(
			"organization:military_office",
			"war_minister",
			"military.unknown"
		),
		"position cannot grant an undeclared capability"
	)
	_check(
		core.set_organization_active("organization:military_office", false),
		"organization can become structurally inactive"
	)
	_check(
		not core.has_capability(
			"person:alice",
			"organization:military_office",
			"military.issue_strategic_order"
		),
		"inactive organization grants no authorization"
	)
	_check(
		not core.add_member("organization:military_office", "person:carol"),
		"inactive organization rejects new membership mutation"
	)
	_check(
		core.set_organization_active("organization:military_office", true),
		"organization can be reactivated without losing structural facts"
	)
	_check(
		core.has_capability(
			"person:alice",
			"organization:military_office",
			"military.issue_strategic_order"
		),
		"reactivated organization restores authorization from retained appointment"
	)
	_check(
		core.revoke_capability(
			"organization:military_office",
			"war_minister",
			"military.issue_strategic_order"
		),
		"capability grant can be revoked without executing military behavior"
	)
	_check(
		not core.has_capability(
			"person:alice",
			"organization:military_office",
			"military.issue_strategic_order"
		),
		"revoked capability is no longer authorized"
	)


func _test_snapshot_determinism_and_round_trip() -> void:
	var core: VNextOrganizationCore = _new_core()
	if core == null:
		_check(false, "persistence fixture creates a core")
		return
	_check(
		core.register_organization("organization:zeta", "union", "place:branch"),
		"persistence fixture registers zeta"
	)
	_check(
		core.register_organization("organization:alpha", "party", "place:capital"),
		"persistence fixture registers alpha"
	)
	_check(
		core.define_capability("organization:alpha", "party.vote_internal"),
		"persistence fixture defines capability"
	)
	_check(
		core.define_position(
			"organization:alpha", "chair", "Chair", 2, ["party.vote_internal"]
		),
		"persistence fixture defines position"
	)
	_check(core.add_member("organization:alpha", "person:bob"), "persistence fixture adds bob")
	_check(
		core.create_appointment(
			"organization:alpha", "chair_bob", "person:bob", "chair"
		),
		"persistence fixture creates appointment"
	)

	var saved: Dictionary = core.snapshot()
	_equal(saved.size(), 2, "organization snapshot has exactly two top-level fields")
	_equal(saved.get("schema_id"), "vnext_organization_core_v1", "organization snapshot schema is explicit")
	var saved_organizations: Array = saved.get("organizations") as Array
	_equal(
		_saved_organization_ids(saved_organizations),
		["organization:alpha", "organization:zeta"],
		"snapshot organizations are sorted independent of registration order"
	)
	var alpha: Dictionary = _find_organization(saved_organizations, "organization:alpha")
	_equal(
		_find_position_ids(alpha.get("positions") as Array),
		["chair"],
		"snapshot positions use organization-owned local IDs"
	)
	_equal(
		_find_appointment_ids(alpha.get("appointments") as Array),
		["chair_bob"],
		"snapshot appointments use organization-owned local IDs"
	)

	var serialized: String = JSON.stringify(saved)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(serialized)
	_equal(parse_error, OK, "organization snapshot survives JSON serialization")
	if parse_error != OK:
		return
	var parsed: Variant = parser.data
	_check(typeof(parsed) == TYPE_DICTIONARY, "JSON parser returns an organization dictionary")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var restored := _new_core()
	_check(restored != null and restored.restore(parsed as Dictionary), "valid organization snapshot restores")
	if restored == null:
		return
	_equal(restored.snapshot(), saved, "organization snapshot round trip preserves complete state")
	_check(restored.is_valid(), "restored organization core remains structurally valid")

	var unsorted: Dictionary = saved.duplicate(true)
	var unsorted_organizations: Array = unsorted.get("organizations") as Array
	unsorted_organizations.reverse()
	var unsorted_alpha: Dictionary = _find_organization(
		unsorted_organizations, "organization:alpha"
	)
	var unsorted_members: Array = unsorted_alpha.get("member_ids") as Array
	unsorted_members.reverse()
	var normalized := _new_core()
	_check(
		normalized != null and normalized.restore(unsorted),
		"restore accepts valid collection ordering from transport"
	)
	if normalized != null:
		_equal(normalized.snapshot(), saved, "restore canonicalizes ordering deterministically")


func _test_restore_rejections_are_transactional() -> void:
	var core: VNextOrganizationCore = _new_core()
	if core == null:
		_check(false, "restore fixture creates a core")
		return
	_check(
		core.register_organization("organization:root", "institution", "place:capital"),
		"restore fixture registers root"
	)
	_check(
		core.register_organization(
			"organization:child", "institution", "place:branch", "organization:root"
		),
		"restore fixture registers child"
	)
	_check(core.add_member("organization:root", "person:alice"), "restore fixture adds member")
	_check(
		core.define_capability("organization:root", "internal.appoint"),
		"restore fixture defines capability"
	)
	_check(
		core.define_position(
			"organization:root", "secretary", "Secretary", 1, ["internal.appoint"]
		),
		"restore fixture defines position"
	)
	_check(
		core.create_appointment(
			"organization:root", "secretary_alice", "person:alice", "secretary"
		),
		"restore fixture creates appointment"
	)
	var valid: Dictionary = core.snapshot()
	_expect_restore_failure(
		core,
		{
			"schema_id": "vnext_organization_core_v0",
			"organizations": valid.get("organizations"),
		},
		"wrong schema"
	)

	var duplicate_member: Dictionary = valid.duplicate(true)
	var duplicate_member_root: Dictionary = _find_organization(
		duplicate_member.get("organizations") as Array, "organization:root"
	)
	(duplicate_member_root.get("member_ids") as Array).append("person:alice")
	_expect_restore_failure(core, duplicate_member, "duplicate membership")

	var missing_position: Dictionary = valid.duplicate(true)
	var missing_position_root: Dictionary = _find_organization(
		missing_position.get("organizations") as Array, "organization:root"
	)
	var missing_position_appointment: Dictionary = _find_appointment(
		missing_position_root.get("appointments") as Array, "secretary_alice"
	)
	missing_position_appointment["position_id"] = "missing"
	_expect_restore_failure(core, missing_position, "appointment position existence")

	var unknown_capability: Dictionary = valid.duplicate(true)
	var unknown_capability_root: Dictionary = _find_organization(
		unknown_capability.get("organizations") as Array, "organization:root"
	)
	var unknown_capability_position: Dictionary = _find_position(
		unknown_capability_root.get("positions") as Array, "secretary"
	)
	(unknown_capability_position.get("capability_ids") as Array).append("unknown.capability")
	_expect_restore_failure(core, unknown_capability, "capability existence")

	var missing_parent: Dictionary = valid.duplicate(true)
	var missing_parent_child: Dictionary = _find_organization(
		missing_parent.get("organizations") as Array, "organization:child"
	)
	missing_parent_child["parent_organization_id"] = "organization:missing"
	_expect_restore_failure(core, missing_parent, "missing parent reference")

	var cycle: Dictionary = valid.duplicate(true)
	var cycle_root: Dictionary = _find_organization(
		cycle.get("organizations") as Array, "organization:root"
	)
	cycle_root["parent_organization_id"] = "organization:child"
	_expect_restore_failure(core, cycle, "hierarchy cycle")

	var malformed_collection: Dictionary = valid.duplicate(true)
	var malformed_root: Dictionary = _find_organization(
		malformed_collection.get("organizations") as Array, "organization:root"
	)
	malformed_root["positions"] = {}
	_expect_restore_failure(core, malformed_collection, "malformed positions collection")

	var extra_field: Dictionary = valid.duplicate(true)
	(extra_field.get("organizations") as Array)[0]["unexpected"] = true
	_expect_restore_failure(core, extra_field, "unexpected organization field")
	_equal(core.snapshot(), valid, "all invalid restores preserve live state transactionally")

	var inactive: Dictionary = valid.duplicate(true)
	var inactive_root: Dictionary = _find_organization(
		inactive.get("organizations") as Array, "organization:root"
	)
	inactive_root["active"] = false
	_check(core.restore(inactive), "inactive organization snapshot is structurally restorable")
	_check(
		not core.has_capability("person:alice", "organization:root", "internal.appoint"),
		"restored inactive organization is fail-closed for authorization"
	)
	_check(
		core.snapshot() == inactive,
		"inactive status is preserved as an owned structural fact"
	)
	_check(core.restore(valid), "active snapshot can be restored after inactive snapshot")


func _expect_restore_failure(
	core: VNextOrganizationCore, rejected: Dictionary, label: String
) -> void:
	var before: Dictionary = core.snapshot()
	_check(not core.restore(rejected), "%s restore is rejected" % label)
	_equal(core.snapshot(), before, "%s rejection is transactional" % label)


func _saved_organization_ids(records: Array) -> Array[String]:
	var output: Array[String] = []
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			output.append(str((raw_record as Dictionary).get("organization_id", "")))
	return output


func _find_organization(records: Array, organization_id: String) -> Dictionary:
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			var record: Dictionary = raw_record as Dictionary
			if str(record.get("organization_id", "")) == organization_id:
				return record
	return {}


func _find_position(records: Array, position_id: String) -> Dictionary:
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			var record: Dictionary = raw_record as Dictionary
			if str(record.get("position_id", "")) == position_id:
				return record
	return {}


func _find_appointment(records: Array, appointment_id: String) -> Dictionary:
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			var record: Dictionary = raw_record as Dictionary
			if str(record.get("appointment_id", "")) == appointment_id:
				return record
	return {}


func _find_position_ids(records: Array) -> Array[String]:
	var output: Array[String] = []
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			output.append(str((raw_record as Dictionary).get("position_id", "")))
	return output


func _find_appointment_ids(records: Array) -> Array[String]:
	var output: Array[String] = []
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			output.append(str((raw_record as Dictionary).get("appointment_id", "")))
	return output


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
