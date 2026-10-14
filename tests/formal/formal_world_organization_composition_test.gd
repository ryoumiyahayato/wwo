extends SceneTree

const PERSON_IDS: Array[String] = ["person:alice", "person:bob"]
const PLACE_IDS: Array[String] = ["place:capital", "place:branch"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_unique_composition_and_empty_state()
	_test_reference_wiring_fail_closed()
	_test_detached_read_boundary()
	_test_nonempty_round_trip_and_fingerprints()
	_test_world_atomic_restore_rejections()
	_test_legacy_world_rejection()
	_test_v7_production_rejection()
	_test_reset_lifecycle()
	_test_scope_and_owner_boundaries()
	print("Formal organization composition: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_unique_composition_and_empty_state() -> void:
	var first := WorldBootstrap.new().build()
	var second := WorldBootstrap.new().build()
	_check(first.world.organization_state != null, "Formal composes one OrganizationState before initialization")
	var authority: OrganizationState = first.world.organization_state
	_check(first.success, "Formal initializes with its composed OrganizationState")
	_check(second.success, "second Formal world initializes independently")
	_check(first.world.organization_state == authority, "initialization retains exactly one authoritative OrganizationState instance")
	_check(first.world.organization_state.has_reference_catalog(), "Formal wires the Organization reference provider")
	var evidence := first.world.organization_evidence_view
	_check(evidence.organization_count() > 0, "formal product composes a non-empty production Organization baseline")
	_equal(
		FormalWorldOrganizationView.new(first.world.organization_state.snapshot()).organization_count(),
		evidence.organization_count(),
		"production Organization runtime roster matches immutable composition evidence"
	)
	_equal(
		FormalWorldOrganizationView.new(first.world.organization_state.snapshot()).snapshot(),
		FormalWorldOrganizationView.new(second.world.organization_state.snapshot()).snapshot(),
		"production Organization initialization is deterministic"
	)
	_equal(
		first.persistence.authoritative_fingerprint(),
		second.persistence.authoritative_fingerprint(),
		"fresh equivalent Formal worlds have the same world fingerprint"
	)
	_check(FormalWorldOrganizationView.new(first.world.organization_state.snapshot()) is FormalWorldOrganizationView, "Formal exposes an Organization query port")
	var production_saved := first.persistence.snapshot()
	var production_restored := WorldBootstrap.new().build()
	_check(production_restored.success, "production Organization round-trip target initializes")
	var candidate_1 := production_restored.persistence.restore_candidate(production_saved)
	if candidate_1.success:
		production_restored = candidate_1
	_check(candidate_1.success, "production Organization current-schema save loads")
	_equal(production_restored.persistence.snapshot(), production_saved, "production Organization current-schema round trip is identical")


func _test_reference_wiring_fail_closed() -> void:
	var catalog := VNextOrganizationReferenceCatalog.create(PERSON_IDS, PLACE_IDS)
	var core := _fixture_core()
	_check(core != null and catalog != null, "reference fixture creates valid detached catalogs")
	if core == null or catalog == null:
		return
	var world := WorldBootstrap.new().build(core, PERSON_IDS, PLACE_IDS)
	_check(world.success, "Formal accepts matching immutable Person and Place reference views")
	_equal(
		core.reference_catalog_fingerprint(),
		catalog.fingerprint(),
		"Formal wiring preserves the exact detached reference boundary"
	)
	var invalid_provider := WorldBootstrap.new().build(null, ["person:BadCase"], [])
	_check(not invalid_provider.success, "invalid reference provider fails Formal initialization closed")
	var missing_provider_core := OrganizationState.new()
	_check(
		missing_provider_core.register_organization("organization:ownerless", "association"),
		"missing-provider fixture can contain reference-free Organization state"
	)
	var missing_provider := WorldBootstrap.new().build(missing_provider_core, [], [])
	_check(not missing_provider.success, "missing Organization reference provider fails Formal initialization closed")


func _test_detached_read_boundary() -> void:
	var world := _fixture_world()
	if world == null:
		_check(false, "detached query fixture initializes")
		return
	var before := FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).snapshot()
	var query := FormalWorldOrganizationView.new(world.world.organization_state.snapshot())
	var organization := query.organization("organization:root")
	organization["organization_kind"] = "party"
	(query.member_ids("organization:root") as Array).append("person:intruder")
	var position := query.position("organization:root", "director")
	position["title"] = "Mutated"
	var appointment := query.appointment("organization:root", "director_alice")
	appointment["person_id"] = "person:bob"
	var detached_snapshot := query.snapshot()
	(detached_snapshot.get("organizations") as Array).clear()
	_equal(FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).snapshot(), before, "query result mutation cannot affect Organization authority")
	_equal(
		FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).organization_kind("organization:root"),
		"association",
		"Organization records returned by Formal are deeply detached"
	)
	_check(
		(AuthorizationCheck.new(world.world.organization_state).check(
			"person:alice", "organization:root", "organization.manage_appointments"
		)["status"] == AuthorizationCheck.ALLOWED),
		"detached query port preserves capability authorization semantics"
	)


func _test_nonempty_round_trip_and_fingerprints() -> void:
	var source := _fixture_world()
	var equivalent := _fixture_world()
	if source == null or equivalent == null:
		_check(false, "round-trip fixtures initialize")
		return
	var saved := source.persistence.snapshot()
	_equal(saved.get("schema_id"), FormalPersistence.SCHEMA_ID, "Formal save schema is explicitly current")
	_check(saved.get("organization") is Dictionary, "Formal authoritative save contains Organization snapshot")
	var organization_state: Dictionary = saved.get("organization") as Dictionary
	_equal(organization_state.get("revision"), 7, "Organization revision is persisted by its owner")
	_equal(
		organization_state.get("state_fingerprint"),
		FormalWorldOrganizationView.new(source.world.organization_state.snapshot()).state_fingerprint(),
		"Organization fingerprint is persisted by its owner"
	)
	_equal(
		FormalWorldOrganizationView.new(source.world.organization_state.snapshot()).snapshot(),
		FormalWorldOrganizationView.new(equivalent.world.organization_state.snapshot()).snapshot(),
		"same Organization fixture produces the same deterministic snapshot"
	)
	_equal(
		source.persistence.authoritative_fingerprint(),
		equivalent.persistence.authoritative_fingerprint(),
		"same complete world produces the same deterministic world fingerprint"
	)
	var production := WorldBootstrap.new().build()
	_check(production.success, "production comparison world initializes")
	_check(
		production.persistence.authoritative_fingerprint() != source.persistence.authoritative_fingerprint(),
		"Organization state contributes to the world fingerprint"
	)
	var restored := WorldBootstrap.new().build(null, PERSON_IDS, PLACE_IDS)
	_check(restored.success, "non-empty restore target initializes with matching references")
	var candidate_2 := restored.persistence.restore_candidate(saved)
	if candidate_2.success:
		restored = candidate_2
	_check(candidate_2.success, "non-empty Organization world restores through Formal candidate-first load")
	_equal(restored.persistence.snapshot(), saved, "current Formal schema round trip is identical")
	var view := FormalWorldOrganizationView.new(restored.world.organization_state.snapshot())
	_equal(view.organization_ids(), ["organization:child", "organization:root"], "organization identity survives save/load")
	_equal(view.organization_kind("organization:root"), "association", "organization kind survives save/load")
	_equal(view.parent_organization_id("organization:child"), "organization:root", "parent relation survives save/load")
	_equal(view.member_ids("organization:root"), ["person:alice"], "membership survives save/load")
	_equal(view.position_ids("organization:root"), ["director"], "position survives save/load")
	_equal(view.appointment_ids("organization:root"), ["director_alice"], "appointment survives save/load")
	_equal(
		view.capability_ids("organization:root"),
		["organization.manage_appointments"],
		"capability survives save/load"
	)
	_equal(view.revision(), FormalWorldOrganizationView.new(source.world.organization_state.snapshot()).revision(), "Organization revision restores exactly")
	_equal(view.state_fingerprint(), FormalWorldOrganizationView.new(source.world.organization_state.snapshot()).state_fingerprint(), "Organization fingerprint restores exactly")
	_equal(restored.persistence.authoritative_fingerprint(), source.persistence.authoritative_fingerprint(), "world fingerprint survives save/load")


func _test_world_atomic_restore_rejections() -> void:
	var world := _fixture_world()
	if world == null:
		_check(false, "atomic restore fixture initializes")
		return
	var valid := world.persistence.snapshot()

	var malformed_id := valid.duplicate(true)
	_first_organization(malformed_id)["organization_id"] = "organization:BadCase"
	_refresh_organization_fingerprint(malformed_id)
	_assert_failed_restore(world, malformed_id, "malformed organization ID")

	var unknown_kind := valid.duplicate(true)
	_first_organization(unknown_kind)["organization_kind"] = "unknown_kind"
	_refresh_organization_fingerprint(unknown_kind)
	_assert_failed_restore(world, unknown_kind, "unknown organization kind")

	var invalid_parent := valid.duplicate(true)
	_organization(invalid_parent, "organization:child")["parent_organization_id"] = "organization:missing"
	_refresh_organization_fingerprint(invalid_parent)
	_assert_failed_restore(world, invalid_parent, "invalid parent")

	var invalid_person := valid.duplicate(true)
	(_organization(invalid_person, "organization:root").get("member_ids") as Array)[0] = "person:unknown"
	_refresh_organization_fingerprint(invalid_person)
	_assert_failed_restore(world, invalid_person, "invalid Person reference")

	var invalid_place := valid.duplicate(true)
	_organization(invalid_place, "organization:root")["primary_place_id"] = "place:unknown"
	_refresh_organization_fingerprint(invalid_place)
	_assert_failed_restore(world, invalid_place, "invalid Place reference")

	var invalid_capability := valid.duplicate(true)
	(_organization(invalid_capability, "organization:root").get("capability_ids") as Array).append("unknown.capability")
	_refresh_organization_fingerprint(invalid_capability)
	_assert_failed_restore(world, invalid_capability, "invalid capability")

	var corrupted_fingerprint := valid.duplicate(true)
	(corrupted_fingerprint.get("organization") as Dictionary)["state_fingerprint"] = "0".repeat(64)
	_assert_failed_restore(world, corrupted_fingerprint, "corrupted Organization fingerprint")

	var malformed_snapshot := valid.duplicate(true)
	malformed_snapshot["organization"] = {"schema_id": OrganizationState.SNAPSHOT_SCHEMA_ID}
	_assert_failed_restore(world, malformed_snapshot, "malformed Organization snapshot")


func _test_legacy_world_rejection() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v4"
	var candidate_3 := world.persistence.restore_candidate(old)
	if candidate_3.success:
		world = candidate_3
	_check(not candidate_3.success, "v4 save format is rejected")
	_check(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_check(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _test_v7_production_rejection() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v7"
	var candidate_4 := world.persistence.restore_candidate(old)
	if candidate_4.success:
		world = candidate_4
	_check(not candidate_4.success, "v7 save format is rejected")
	_check(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_check(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _test_reset_lifecycle() -> void:
	var world := _fixture_world()
	if world == null:
		_check(false, "reset fixture initializes")
		return
	var old_authority: OrganizationState = world.world.organization_state
	_check(FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).organization_count() == 2, "world A contains synthetic Organization state")
	var candidate_5 := WorldBootstrap.new().build(null, world.organization_person_reference_ids, world.organization_place_reference_ids) if world.explicit_organization_reference_injection else WorldBootstrap.new().build()
	if candidate_5.success:
		world = candidate_5
	_check(candidate_5.success, "Formal reset/new world succeeds")
	_check(world.world.organization_state != old_authority, "reset replaces the previous OrganizationState lifecycle instance")
	_equal(FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).organization_count(), 0, "reset/new world clears prior Organization state")
	_equal(FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).revision(), 0, "reset/new world starts at Organization revision zero")


func _test_scope_and_owner_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/content/world_bootstrap.gd")
	_check(FileAccess.get_file_as_string("res://scripts/world/world_state.gd").count("var organization_state: OrganizationState") == 1 and not FileAccess.get_file_as_string("res://scripts/formal/formal_world_application.gd").contains("var _organization_state: OrganizationState"), "Installed WorldState declares the sole OrganizationState reference; Application owns no duplicate")
	_check(not source.contains("var _organizations"), "Formal owns no second organizations dictionary")
	_check(not source.contains("membership_table"), "Formal owns no second membership table")
	_check(not source.contains("appointment_table"), "Formal owns no second appointment table")
	_check(not source.contains("WorldTransactionCoordinator"), "Organization is not integrated with Transaction Coordinator")
	_check(not source.contains("VNextStatePolitics"), "Formal composition introduces no StatePolitics dual-write")
	_check(not source.contains("data/world_map/organizations.json"), "Formal composition does not ingest prototype organizations")
	_check(not source.contains("data/world_map/institutions.json"), "Formal composition does not ingest prototype institutions")
	_check(not source.contains("scripts/v2_2"), "Formal composition does not revive legacy Organization runtime")
	var organization_source := FileAccess.get_file_as_string("res://scripts/world/organization_state.gd")
	_check(not organization_source.contains("payroll"), "Organization gameplay payroll is not introduced")
	_check(not organization_source.contains("election"), "Organization gameplay elections are not introduced")


func _fixture_core() -> OrganizationState:
	var core := OrganizationState.create(PERSON_IDS, PLACE_IDS)
	if core == null:
		return null
	if not core.register_organization("organization:root", "association", "place:capital"):
		return null
	if not core.register_organization("organization:child", "company", "place:branch", "organization:root"):
		return null
	if not core.define_capability("organization:root", "organization.manage_appointments"):
		return null
	if not core.define_position(
		"organization:root",
		"director",
		"Director",
		1,
		["organization.manage_appointments"]
	):
		return null
	if not core.add_member("organization:root", "person:alice"):
		return null
	if not core.create_appointment(
		"organization:root", "director_alice", "person:alice", "director"
	):
		return null
	if not core.add_member("organization:child", "person:bob"):
		return null
	return core


func _fixture_world() -> WorldBuildResult:
	var core := _fixture_core()
	if core == null:
		return null
	var world := WorldBootstrap.new().build(core, PERSON_IDS, PLACE_IDS)
	if not world.success:
		return null
	return world


func _assert_failed_restore(
	world: WorldBuildResult, rejected: Dictionary, label: String
) -> void:
	var before := world.persistence.snapshot()
	var before_world_fingerprint := world.persistence.authoritative_fingerprint()
	var before_organization := FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).snapshot()
	var candidate_6 := world.persistence.restore_candidate(rejected)
	if candidate_6.success:
		world = candidate_6
	_check(not candidate_6.success, "%s fails Formal load closed" % label)
	_equal(world.persistence.authoritative_fingerprint(), before_world_fingerprint, "%s preserves whole-world hash" % label)
	_equal(FormalWorldOrganizationView.new(world.world.organization_state.snapshot()).snapshot(), before_organization, "%s preserves Organization authority" % label)
	_equal(world.persistence.snapshot(), before, "%s preserves every other authoritative domain" % label)


func _first_organization(world_snapshot: Dictionary) -> Dictionary:
	var organization_snapshot: Dictionary = world_snapshot.get("organization") as Dictionary
	return (organization_snapshot.get("organizations") as Array)[0] as Dictionary


func _organization(world_snapshot: Dictionary, organization_id: String) -> Dictionary:
	var organization_snapshot: Dictionary = world_snapshot.get("organization") as Dictionary
	for raw_record: Variant in organization_snapshot.get("organizations") as Array:
		var record: Dictionary = raw_record as Dictionary
		if str(record.get("organization_id", "")) == organization_id:
			return record
	return {}


func _refresh_organization_fingerprint(world_snapshot: Dictionary) -> void:
	var organization_snapshot: Dictionary = world_snapshot["organization"]
	var payload := organization_snapshot.duplicate(true)
	payload.erase("state_fingerprint")
	organization_snapshot["state_fingerprint"] = JSON.stringify(payload).sha256_text()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
