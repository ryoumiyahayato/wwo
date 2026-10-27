extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := WorldBootstrap.new().build()
	var second := WorldBootstrap.new().build()
	_check(first.success, "first production Formal world initializes")
	_check(second.success, "second production Formal world initializes")
	if not first.success or not second.success:
		_finish()
		return

	var expected_polity_ids: Array[String] = []
	for record: Dictionary in first.world.historical_evidence_view.records():
		if (
			str(record.get("status", "")) == "sovereign"
			and str(record.get("relationship", "")) == "independent_state"
		):
			expected_polity_ids.append(str(record.get("source_historical_id", "")))
	expected_polity_ids.sort()

	var evidence := first.world.organization_evidence_view
	var organizations := FormalWorldOrganizationView.new(first.world.organization_state.snapshot())
	var coverage := evidence.coverage_summary()

	_equal(evidence.organization_count(), expected_polity_ids.size(), "eligible polity set determines production Organization count")
	_equal(organizations.organization_count(), expected_polity_ids.size(), "OrganizationState materializes exactly the eligible production set")
	_check(evidence.organization_count() > 0, "production Organization roster is non-empty")
	_equal(int(coverage.get("political_unit_count", -1)), first.world.historical_evidence_view.record_count(), "coverage reports the full political evidence universe")
	_equal(int(coverage.get("eligible_governing_institution_count", -1)), expected_polity_ids.size(), "coverage reports eligible governing institutions")
	_equal(int(coverage.get("materialized_organization_count", -1)), expected_polity_ids.size(), "coverage reports every eligible institution materialized")
	_equal(int(coverage.get("historical_a_count", -1)), 0, "no unsupported historical-exact Organization claim is fabricated")
	_equal(int(coverage.get("inferred_b_count", -1)), expected_polity_ids.size(), "all initial production organizations are classified B institutional inference")
	_equal(int(coverage.get("generated_c_count", -1)), 0, "no generated C organizations are introduced")
	_equal(int(coverage.get("prototype_d_count", -1)), 0, "prototype D organizations are excluded")
	_equal(
		int(coverage.get("deferred_for_evidence_count", -1)),
		first.world.historical_evidence_view.record_count() - expected_polity_ids.size(),
		"non-eligible political units remain explicitly deferred for organization evidence"
	)

	for polity_id: String in expected_polity_ids:
		var organization_id := "organization:gov_" + polity_id
		_check(organizations.has_organization(organization_id), "eligible polity materializes deterministic Organization ID: %s" % polity_id)
		_equal(organizations.organization_kind(organization_id), "government_body", "governing anchor uses government_body kind: %s" % polity_id)
		_equal(organizations.primary_place_id(organization_id), "", "governing anchor does not fabricate institutional location: %s" % polity_id)
		_equal(organizations.parent_organization_id(organization_id), "", "political control is not encoded as Organization hierarchy: %s" % polity_id)
		_equal(organizations.member_ids(organization_id), [], "governing anchor does not fabricate members: %s" % polity_id)
		_equal(organizations.position_ids(organization_id), [], "governing anchor does not fabricate positions: %s" % polity_id)
		_equal(organizations.appointment_ids(organization_id), [], "governing anchor does not fabricate appointments: %s" % polity_id)
		var basis := evidence.organization_basis(organization_id)
		_equal(str(basis.get("represented_polity_id", "")), polity_id, "evidence preserves represented polity: %s" % polity_id)
		_equal(str(basis.get("basis_class", "")), "institutional_inference", "evidence labels inference explicitly: %s" % polity_id)
		_equal(bool(basis.get("historical_exact_name_claimed", true)), false, "inferred anchor never claims an exact historical agency name: %s" % polity_id)
		_equal(bool(basis.get("prototype_source", true)), false, "production anchor is not prototype-backed: %s" % polity_id)
		_equal(
			basis.get("source_fact_ids", []),
			["political_identity:" + polity_id],
			"production anchor records its political identity source fact: %s" % polity_id
		)

	_equal(FormalWorldOrganizationView.new(first.world.organization_state.snapshot()).snapshot(), FormalWorldOrganizationView.new(second.world.organization_state.snapshot()).snapshot(), "fresh production Organization composition is deterministic")
	_equal(first.world.organization_evidence_view.fingerprint(), second.world.organization_evidence_view.fingerprint(), "composition evidence fingerprint is deterministic")

	var saved := first.persistence.snapshot()
	_check(saved.get("organization_composition", {}) is Dictionary, "save pins Organization composition evidence")
	_equal(
		str((saved.get("organization_composition", {}) as Dictionary).get("fingerprint", "")),
		evidence.fingerprint(),
		"save pins the exact production Organization evidence fingerprint"
	)

	_test_evidence_view_detached_index()
	_finish()


func _test_evidence_view_detached_index() -> void:
	var source: Dictionary = {
		"organizations": [null, 3, [], {}, {"organization_id": ""},
			{"organization_id": " "}, {"organization_id": 17},
			{"organization_id": "z", "basis_class": "first"},
			{"organization_id": "z", "basis_class": "last", "nested": {"values": [2]}}],
		"coverage": {"nested": {"count": 2}},
	}
	var expected := source.duplicate(true)
	var view := FormalWorldOrganizationEvidenceView.new(source)
	_equal(source, expected, "evidence construction does not mutate its input")
	_equal(view.organization_ids(), [" ", "17", "z"], "index preserves string conversion, sorting and non-empty whitespace ID")
	_equal(view.organization_count(), 3, "index skips invalid rows and empty IDs, coalescing duplicate IDs")
	_equal(view.basis_class("z"), "last", "last duplicate ID remains the indexed record")
	_equal(view.organization_basis("missing"), {}, "unknown evidence ID remains empty")
	_equal(view.snapshot(), expected, "snapshot retains original rows, including rows omitted from the index")
	var expected_basis: Dictionary = expected["organizations"][-1]
	source["organizations"][-1]["nested"]["values"][0] = 50
	source["coverage"]["nested"]["count"] = 50
	_equal(view.organization_basis("z"), expected_basis, "nested input changes cannot reach indexed evidence")
	_equal(view.snapshot(), expected, "nested input changes cannot reach the owned snapshot")
	var basis := view.organization_basis("z")
	basis["nested"]["values"].append(60)
	_equal(view.organization_basis("z"), expected_basis, "nested basis result remains detached")
	var output := view.snapshot()
	output["organizations"][-1]["nested"]["values"].append(70)
	_equal(view.organization_basis("z"), expected_basis, "snapshot result cannot mutate the index")
	_equal(view.snapshot(), expected, "snapshot result remains detached")
	var coverage := view.coverage_summary()
	coverage["nested"]["count"] = 80
	_equal(view.coverage_summary(), expected["coverage"], "coverage result remains detached")
	var restored := FormalWorldOrganizationEvidenceView.new(view.snapshot())
	_equal(restored.snapshot(), expected, "view snapshot reconstructs without format changes")
	_equal(restored.organization_basis("z"), expected_basis, "reconstructed index retains the duplicate-ID rule")
	_equal(restored.organization_ids(), view.organization_ids(), "reconstructed index retains all IDs")
	_equal(FormalWorldOrganizationEvidenceView.new().organization_count(), 0, "missing organizations has an empty index")
	for raw: Variant in [null, 4, "not an array", {}]:
		var invalid_source: Dictionary = {"organizations": raw}
		var invalid_view := FormalWorldOrganizationEvidenceView.new(invalid_source)
		_equal(invalid_view.organization_count(), 0, "non-array organizations has an empty index")
		_equal(invalid_view.snapshot(), invalid_source, "non-array organizations remains unchanged in the snapshot")


func _finish() -> void:
	print("Formal production organization composition: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error(message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s | expected=%s actual=%s" % [message, str(expected), str(actual)])
