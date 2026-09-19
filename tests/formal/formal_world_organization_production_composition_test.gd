extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_production_roster()
	_test_provenance_and_classification()
	_test_player_independence()
	_test_v7_empty_migration_and_conflict_rejection()
	_test_prototype_exclusion()
	print(
		"Formal Organization production composition: %d checks, %d failures"
		% [checks, failures]
	)
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_production_roster() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "fresh production Formal world initializes")
	if not world.initialized:
		return
	var evidence := world.organization_evidence_view()
	var organizations := world.organization_view()
	var coverage := evidence.coverage()
	_check(evidence.is_configured(), "Organization composition evidence is configured")
	_check(evidence.materialized_count() > 0, "production Organization roster is non-empty")
	_equal(
		organizations.organization_count(),
		evidence.materialized_count(),
		"OrganizationCore population exactly matches qualified composition evidence"
	)
	_equal(
		organizations.organization_ids(),
		evidence.organization_ids(),
		"Organization identities are deterministically derived from evidence"
	)
	_equal(
		int(coverage.get("political_unit_count", -1)),
		world.historical_evidence_view().record_count(),
		"coverage accounts for every historical political unit"
	)
	_equal(
		int(coverage.get("materialized_organization_count", -1))
		+ int(coverage.get("deferred_for_evidence_count", -1)),
		int(coverage.get("political_unit_count", -2)),
		"coverage has no silent political-unit gaps"
	)
	for organization_id: String in organizations.organization_ids():
		_equal(
			organizations.organization_kind(organization_id),
			"government_body",
			"production baseline materializes only governing institutional anchors"
		)
		_equal(
			organizations.primary_place_id(organization_id),
			"",
			"inference does not fabricate institutional location"
		)
		_equal(
			organizations.parent_organization_id(organization_id),
			"",
			"political control is not encoded as Organization hierarchy"
		)
		_equal(
			organizations.member_ids(organization_id),
			[],
			"inference does not fabricate membership"
		)
		_equal(
			organizations.position_ids(organization_id),
			[],
			"inference does not fabricate positions"
		)
		_equal(
			organizations.appointment_ids(organization_id),
			[],
			"inference does not fabricate appointments"
		)


func _test_provenance_and_classification() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "classification fixture initializes")
	if not world.initialized:
		return
	var evidence := world.organization_evidence_view()
	var coverage := evidence.coverage()
	_equal(int(coverage.get("historical_count", -1)), 0, "no historical Organization identity is fabricated")
	_check(int(coverage.get("inferred_count", 0)) > 0, "institutional inference cohort is present")
	_equal(int(coverage.get("generated_count", -1)), 0, "no generated Organization is added to production baseline")
	_equal(int(coverage.get("prototype_count", -1)), 0, "prototype Organization count remains zero")
	for organization_id: String in evidence.organization_ids():
		var record := evidence.record(organization_id)
		_equal(
			str(record.get("basis", "")),
			"institutional_inference",
			"every production baseline Organization declares inference basis"
		)
		var source_id := str(record.get("source_historical_id", ""))
		_check(
			world.historical_evidence_view().has_source(source_id),
			"inferred Organization references admitted historical political evidence"
		)
		var source := world.historical_evidence_view().record(source_id)
		_equal(
			str(source.get("relationship", "")),
			"independent_state",
			"inference source is an independent state"
		)
		_equal(
			str(source.get("status", "")),
			"sovereign",
			"inference source is sovereign"
		)


func _test_player_independence() -> void:
	var first := FormalWorldSimulation.new()
	var second := FormalWorldSimulation.new()
	_check(first.initialize() and second.initialize(), "player-independence worlds initialize")
	if not first.initialized or not second.initialized:
		return
	_equal(
		first.organization_view().snapshot(),
		second.organization_view().snapshot(),
		"fresh production Organization roster is independent of player interaction"
	)
	_equal(
		first.organization_evidence_view().fingerprint(),
		second.organization_evidence_view().fingerprint(),
		"Organization evidence fingerprint is deterministic across fresh worlds"
	)


func _test_v7_empty_migration_and_conflict_rejection() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "v7 migration source initializes")
	if not source.initialized:
		return
	var legacy := source.get_persistent_state()
	legacy["schema_id"] = FormalWorldSimulation.PREVIOUS_SCHEMA_ID
	legacy.erase("organization_evidence")
	var empty_core := VNextOrganizationCore.create(
		source.organization_person_reference_ids(),
		source._organization_place_reference_ids
	)
	_check(empty_core != null, "legacy empty Organization core can be reconstructed")
	if empty_core == null:
		return
	var empty_authority := VNextOrganizationAuthorityFoundation.create(
		empty_core,
		source.formal_person_ids(),
		source._organization_place_reference_ids
	)
	_check(empty_authority != null, "legacy empty Organization Authority can be reconstructed")
	if empty_authority == null:
		return
	legacy["organization"] = empty_core.snapshot()
	legacy["organization_authority"] = empty_authority.snapshot()

	var migrated := FormalWorldSimulation.new()
	_check(migrated.initialize(), "v7 empty migration target initializes")
	_check(
		migrated.restore_persistent_state(legacy),
		"canonical empty v7 Organization state migrates to production roster"
	)
	if migrated.initialized:
		_equal(
			migrated.organization_view().organization_ids(),
			migrated.organization_evidence_view().organization_ids(),
			"v7 empty migration materializes exactly the qualified current roster"
		)
		_equal(
			migrated.get_persistent_state().get("schema_id"),
			FormalWorldSimulation.SCHEMA_ID,
			"v7 migration emits current v8 schema"
		)

	var conflicting := source.get_persistent_state()
	conflicting["schema_id"] = FormalWorldSimulation.PREVIOUS_SCHEMA_ID
	conflicting.erase("organization_evidence")
	var rejected := FormalWorldSimulation.new()
	_check(rejected.initialize(), "v7 conflict target initializes")
	_check(
		not rejected.restore_persistent_state(conflicting),
		"non-empty v7 Organization state fails closed without explicit legacy references"
	)


func _test_prototype_exclusion() -> void:
	var catalog_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_organization_evidence_catalog.gd"
	)
	var simulation_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_simulation.gd"
	)
	var combined := catalog_source + "\n" + simulation_source
	for forbidden: String in [
		"data/world_map/organizations.json",
		"data/world_map/institutions.json",
		"data/vnext/politics/state_politics_1900.json",
		"scripts/v2_2/",
		"data/v2_2/",
	]:
		_check(
			not combined.contains(forbidden),
			"production Organization runtime code does not ingest forbidden source: %s" % forbidden
		)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
