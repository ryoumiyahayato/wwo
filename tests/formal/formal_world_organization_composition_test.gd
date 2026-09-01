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
	_test_legacy_world_migration()
	_test_reset_lifecycle()
	_test_scope_and_owner_boundaries()
	print("Formal organization composition: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_unique_composition_and_empty_state() -> void:
	var first := FormalWorldSimulation.new()
	var second := FormalWorldSimulation.new()
	_check(first._organization != null, "Formal composes one OrganizationCore before initialization")
	var authority: VNextOrganizationCore = first._organization
	_check(first.initialize(), "Formal initializes with its composed OrganizationCore")
	_check(second.initialize(), "second Formal world initializes independently")
	_check(first._organization == authority, "initialization retains exactly one authoritative OrganizationCore instance")
	_check(first._organization.has_reference_catalog(), "Formal wires an explicit empty reference provider")
	_equal(first.organization_view().organization_count(), 0, "formal product starts with legal empty Organization state")
	_equal(
		first.organization_view().snapshot(),
		second.organization_view().snapshot(),
		"empty Organization initialization is deterministic"
	)
	_equal(
		first.authoritative_fingerprint(),
		second.authoritative_fingerprint(),
		"fresh equivalent Formal worlds have the same world fingerprint"
	)
	_check(first.organization_query_port() is FormalWorldOrganizationView, "Formal exposes an Organization query port")
	var empty_saved := first.get_persistent_state()
	var empty_restored := FormalWorldSimulation.new()
	_check(empty_restored.initialize(), "empty Organization round-trip target initializes")
	_check(empty_restored.restore_persistent_state(empty_saved), "empty Organization current-schema save loads")
	_equal(empty_restored.get_persistent_state(), empty_saved, "empty Organization current-schema round trip is identical")


func _test_reference_wiring_fail_closed() -> void:
	var catalog := VNextOrganizationReferenceCatalog.create(PERSON_IDS, PLACE_IDS)
	var core := _fixture_core()
	_check(core != null and catalog != null, "reference fixture creates valid detached catalogs")
	if core == null or catalog == null:
		return
	var world := FormalWorldSimulation.new(core, PERSON_IDS, PLACE_IDS)
	_check(world.initialize(), "Formal accepts matching immutable Person and Place reference views")
	_equal(
		core.reference_catalog_fingerprint(),
		catalog.fingerprint(),
		"Formal wiring preserves the exact detached reference boundary"
	)
	var invalid_provider := FormalWorldSimulation.new(null, ["person:BadCase"], [])
	_check(not invalid_provider.initialize(), "invalid reference provider fails Formal initialization closed")
	var missing_provider_core := VNextOrganizationCore.new()
	_check(
		missing_provider_core.register_organization("organization:ownerless", "association"),
		"missing-provider fixture can contain reference-free Organization state"
	)
	var missing_provider := FormalWorldSimulation.new(missing_provider_core, [], [])
	_check(not missing_provider.initialize(), "missing Organization reference provider fails Formal initialization closed")


func _test_detached_read_boundary() -> void:
	var world := _fixture_world()
	if world == null:
		_check(false, "detached query fixture initializes")
		return
	var before := world.organization_view().snapshot()
	var query := world.organization_view()
	var organization := query.organization("organization:root")
	organization["organization_kind"] = "party"
	(query.member_ids("organization:root") as Array).append("person:intruder")
	var position := query.position("organization:root", "director")
	position["title"] = "Mutated"
	var appointment := query.appointment("organization:root", "director_alice")
	appointment["person_id"] = "person:bob"
	var detached_snapshot := query.snapshot()
	(detached_snapshot.get("organizations") as Array).clear()
	_equal(world.organization_view().snapshot(), before, "query result mutation cannot affect Organization authority")
	_equal(
		world.organization_view().organization_kind("organization:root"),
		"association",
		"Organization records returned by Formal are deeply detached"
	)
	_check(
		world.organization_view().has_capability(
			"person:alice", "organization:root", "organization.manage_appointments"
		),
		"detached query port preserves capability authorization semantics"
	)


func _test_nonempty_round_trip_and_fingerprints() -> void:
	var source := _fixture_world()
	var equivalent := _fixture_world()
	if source == null or equivalent == null:
		_check(false, "round-trip fixtures initialize")
		return
	var saved := source.get_persistent_state()
	_equal(saved.get("schema_id"), FormalWorldSimulation.SCHEMA_ID, "Formal save schema is explicitly v5")
	_check(saved.get("organization") is Dictionary, "Formal authoritative save contains Organization snapshot")
	var organization_state: Dictionary = saved.get("organization") as Dictionary
	_equal(organization_state.get("revision"), 7, "Organization revision is persisted by its owner")
	_equal(
		organization_state.get("state_fingerprint"),
		source.organization_view().state_fingerprint(),
		"Organization fingerprint is persisted by its owner"
	)
	_equal(
		source.organization_view().snapshot(),
		equivalent.organization_view().snapshot(),
		"same Organization fixture produces the same deterministic snapshot"
	)
	_equal(
		source.authoritative_fingerprint(),
		equivalent.authoritative_fingerprint(),
		"same complete world produces the same deterministic world fingerprint"
	)
	var empty := FormalWorldSimulation.new()
	_check(empty.initialize(), "empty comparison world initializes")
	_check(
		empty.authoritative_fingerprint() != source.authoritative_fingerprint(),
		"Organization state contributes to the world fingerprint"
	)
	var restored := FormalWorldSimulation.new(null, PERSON_IDS, PLACE_IDS)
	_check(restored.initialize(), "non-empty restore target initializes with matching references")
	_check(restored.restore_persistent_state(saved), "non-empty Organization world restores through Formal candidate-first load")
	_equal(restored.get_persistent_state(), saved, "current Formal schema round trip is identical")
	var view := restored.organization_view()
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
	_equal(view.revision(), source.organization_view().revision(), "Organization revision restores exactly")
	_equal(view.state_fingerprint(), source.organization_view().state_fingerprint(), "Organization fingerprint restores exactly")
	_equal(restored.authoritative_fingerprint(), source.authoritative_fingerprint(), "world fingerprint survives save/load")


func _test_world_atomic_restore_rejections() -> void:
	var world := _fixture_world()
	if world == null:
		_check(false, "atomic restore fixture initializes")
		return
	var valid := world.get_persistent_state()

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
	malformed_snapshot["organization"] = {"schema_id": VNextOrganizationCore.SNAPSHOT_SCHEMA_ID}
	_assert_failed_restore(world, malformed_snapshot, "malformed Organization snapshot")


func _test_legacy_world_migration() -> void:
	var current := FormalWorldSimulation.new()
	_check(current.initialize(), "legacy migration source initializes")
	var legacy := current.get_persistent_state()
	legacy["schema_id"] = "formal_world_simulation_v4"
	legacy.erase("organization")
	var first := FormalWorldSimulation.new()
	var second := FormalWorldSimulation.new()
	_check(first.initialize() and second.initialize(), "legacy migration targets initialize")
	_check(first.restore_persistent_state(legacy), "legacy v4 save without Organization loads successfully")
	_check(second.restore_persistent_state(legacy), "legacy v4 migration replays successfully")
	_equal(first.organization_view().organization_count(), 0, "legacy migration produces legal empty Organization state")
	_equal(
		first.organization_view().snapshot(),
		second.organization_view().snapshot(),
		"legacy empty Organization migration is deterministic"
	)
	_equal(first.get_persistent_state().get("schema_id"), FormalWorldSimulation.SCHEMA_ID, "legacy load emits current v5 schema")


func _test_reset_lifecycle() -> void:
	var world := _fixture_world()
	if world == null:
		_check(false, "reset fixture initializes")
		return
	var old_authority: VNextOrganizationCore = world._organization
	_check(world.organization_view().organization_count() == 2, "world A contains synthetic Organization state")
	_check(world.reset_world(), "Formal reset/new world succeeds")
	_check(world._organization != old_authority, "reset replaces the previous OrganizationCore lifecycle instance")
	_equal(world.organization_view().organization_count(), 0, "reset/new world clears prior Organization state")
	_equal(world.organization_view().revision(), 0, "reset/new world starts at Organization revision zero")


func _test_scope_and_owner_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_simulation.gd")
	_equal(source.count("var _organization: VNextOrganizationCore"), 1, "Formal declares exactly one OrganizationCore authority reference")
	_check(not source.contains("var _organizations"), "Formal owns no second organizations dictionary")
	_check(not source.contains("membership_table"), "Formal owns no second membership table")
	_check(not source.contains("appointment_table"), "Formal owns no second appointment table")
	_check(not source.contains("WorldTransactionCoordinator"), "Organization is not integrated with Transaction Coordinator")
	_check(not source.contains("VNextStatePolitics"), "Formal composition introduces no StatePolitics dual-write")
	var organization_source := FileAccess.get_file_as_string("res://scripts/vnext/organization/organization_core.gd")
	_check(not organization_source.contains("payroll"), "Organization gameplay payroll is not introduced")
	_check(not organization_source.contains("election"), "Organization gameplay elections are not introduced")


func _fixture_core() -> VNextOrganizationCore:
	var core := VNextOrganizationCore.create(PERSON_IDS, PLACE_IDS)
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


func _fixture_world() -> FormalWorldSimulation:
	var core := _fixture_core()
	if core == null:
		return null
	var world := FormalWorldSimulation.new(core, PERSON_IDS, PLACE_IDS)
	if not world.initialize():
		return null
	return world


func _assert_failed_restore(
	world: FormalWorldSimulation, rejected: Dictionary, label: String
) -> void:
	var before := world.get_persistent_state()
	var before_world_fingerprint := world.authoritative_fingerprint()
	var before_organization := world.organization_view().snapshot()
	_check(not world.restore_persistent_state(rejected), "%s fails Formal load closed" % label)
	_equal(world.authoritative_fingerprint(), before_world_fingerprint, "%s preserves whole-world hash" % label)
	_equal(world.organization_view().snapshot(), before_organization, "%s preserves Organization authority" % label)
	_equal(world.get_persistent_state(), before, "%s preserves every other authoritative domain" % label)


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
	var organization_snapshot: Dictionary = world_snapshot.get("organization") as Dictionary
	organization_snapshot["state_fingerprint"] = JSON.stringify({
		"revision": int(organization_snapshot.get("revision", 0)),
		"organizations": organization_snapshot.get("organizations", []),
	}).sha256_text()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
