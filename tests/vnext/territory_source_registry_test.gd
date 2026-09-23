extends SceneTree

const FIXTURE_PATH: String = "res://tests/vnext/territory_source_registry_test.gd"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_status_fixtures_register()
	_test_identity_hash_and_date_rejections()
	_test_admission_fail_closed_gates()
	_test_derivation_parent_validation()
	_test_deterministic_order_and_fingerprint()
	_test_detached_reads()
	_test_live_registry_classification_and_audit()
	_test_admitted_query_and_zero_admitted_state()
	_test_formal_non_composition_boundaries()
	print("VNext territory source registry: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_status_fixtures_register() -> void:
	var reference_registry := VNextTerritorySourceRegistry.new()
	_check(
		reference_registry.configure([_base_record(
			"territory_source:reference_fixture",
			VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
		)]),
		"A. valid reference-only source registers"
	)
	var candidate := _base_record(
		"territory_source:candidate_fixture",
		VNextTerritorySourceRecord.STATUS_CANDIDATE
	)
	candidate["dataset_version"] = ""
	candidate["production_admission_reason"] = "DATASET_VERSION_UNRESOLVED"
	var candidate_registry := VNextTerritorySourceRegistry.new()
	_check(candidate_registry.configure([candidate]), "B. valid unresolved candidate source registers")
	var admitted_registry := VNextTerritorySourceRegistry.new()
	_check(
		admitted_registry.configure([_base_record(
			"territory_source:admitted_fixture",
			VNextTerritorySourceRecord.STATUS_ADMITTED
		)]),
		"C. valid admitted fixture registers"
	)
	_equal(admitted_registry.admitted_sources().size(), 1, "admitted fixture is visible through admitted-only query")


func _test_identity_hash_and_date_rejections() -> void:
	var duplicate := _base_record(
		"territory_source:duplicate_fixture",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var duplicate_registry := VNextTerritorySourceRegistry.new()
	_check(
		not duplicate_registry.configure([duplicate, duplicate.duplicate(true)]),
		"D. duplicate source identity fails"
	)

	var malformed_hash := _base_record(
		"territory_source:malformed_hash",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	malformed_hash["source_sha256"] = "abc"
	var malformed_hash_registry := VNextTerritorySourceRegistry.new()
	_check(not malformed_hash_registry.configure([malformed_hash]), "E. malformed hash fails")

	var hash_mismatch := _base_record(
		"territory_source:hash_mismatch",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	hash_mismatch["source_sha256"] = "0".repeat(64)
	var hash_mismatch_registry := VNextTerritorySourceRegistry.new()
	_check(not hash_mismatch_registry.configure([hash_mismatch]), "F. declared hash mismatch fails")

	var invalid_date := _base_record(
		"territory_source:invalid_date",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	invalid_date["snapshot_date"] = "1900-02-30"
	var invalid_date_registry := VNextTerritorySourceRegistry.new()
	_check(not invalid_date_registry.configure([invalid_date]), "G. invalid calendar date fails")

	var inverted_range := _base_record(
		"territory_source:inverted_date_range",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	inverted_range["valid_from"] = "1901-01-01"
	inverted_range["valid_to"] = "1900-01-01"
	var inverted_range_registry := VNextTerritorySourceRegistry.new()
	_check(not inverted_range_registry.configure([inverted_range]), "invalid temporal range fails closed")

	var malformed_id := _base_record(
		"territory_source:malformed_id",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	malformed_id["source_snapshot_id"] = "territory_source::bad"
	var malformed_id_registry := VNextTerritorySourceRegistry.new()
	_check(not malformed_id_registry.configure([malformed_id]), "malformed source snapshot identity fails")


func _test_admission_fail_closed_gates() -> void:
	var prototype := _base_record(
		"territory_source:prototype_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	prototype["prototype_only"] = true
	var prototype_registry := VNextTerritorySourceRegistry.new()
	_check(not prototype_registry.configure([prototype]), "H. prototype source cannot be admitted")

	var noncommercial := _base_record(
		"territory_source:noncommercial_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	noncommercial["commercial_use_allowed"] = false
	var noncommercial_registry := VNextTerritorySourceRegistry.new()
	_check(not noncommercial_registry.configure([noncommercial]), "I. non-commercial source cannot be admitted")

	var no_redistribution := _base_record(
		"territory_source:no_redistribution_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	no_redistribution["redistribution_allowed"] = false
	var no_redistribution_registry := VNextTerritorySourceRegistry.new()
	_check(not no_redistribution_registry.configure([no_redistribution]), "J. redistribution-forbidden source cannot be admitted")

	var unresolved_license := _base_record(
		"territory_source:unresolved_license_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	unresolved_license["license_id"] = ""
	unresolved_license["license_url"] = ""
	unresolved_license["redistribution_allowed"] = null
	unresolved_license["derivative_work_allowed"] = null
	unresolved_license["commercial_use_allowed"] = null
	var unresolved_license_registry := VNextTerritorySourceRegistry.new()
	_check(not unresolved_license_registry.configure([unresolved_license]), "K. unresolved license cannot be admitted")

	var no_derivatives := _base_record(
		"territory_source:no_derivatives_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	no_derivatives["derivative_work_allowed"] = false
	var no_derivatives_registry := VNextTerritorySourceRegistry.new()
	_check(not no_derivatives_registry.configure([no_derivatives]), "derivative-work-forbidden source cannot be admitted")

	var historical_fail := _base_record(
		"territory_source:historical_fail_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	historical_fail["historical_fit_status"] = VNextTerritorySourceRecord.HISTORICAL_FIT_FAIL
	var historical_fail_registry := VNextTerritorySourceRegistry.new()
	_check(not historical_fail_registry.configure([historical_fail]), "historical-fit failure cannot be admitted")

	var temporal_fail := _base_record(
		"territory_source:temporal_fail_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	temporal_fail["valid_from"] = "2000-01-01"
	temporal_fail["valid_to"] = "2000-12-31"
	var temporal_fail_registry := VNextTerritorySourceRegistry.new()
	_check(not temporal_fail_registry.configure([temporal_fail]), "temporal mismatch cannot be admitted")

	var geometry_unresolved := _base_record(
		"territory_source:geometry_unresolved_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	geometry_unresolved["feature_count"] = null
	var geometry_unresolved_registry := VNextTerritorySourceRegistry.new()
	_check(not geometry_unresolved_registry.configure([geometry_unresolved]), "unresolved geometry scope evidence cannot be admitted")

	var provenance_unresolved := _base_record(
		"territory_source:provenance_unresolved_admitted",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	provenance_unresolved["dataset_version"] = ""
	var provenance_unresolved_registry := VNextTerritorySourceRegistry.new()
	_check(not provenance_unresolved_registry.configure([provenance_unresolved]), "unresolved provenance cannot be admitted")


func _test_derivation_parent_validation() -> void:
	var missing_parent := _derived_record(
		"territory_source:missing_parent",
		[],
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var missing_parent_registry := VNextTerritorySourceRegistry.new()
	_check(not missing_parent_registry.configure([missing_parent]), "L. derived source with missing parent declaration fails")

	var unknown_parent := _derived_record(
		"territory_source:unknown_parent",
		["territory_source:not_registered"],
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var unknown_parent_registry := VNextTerritorySourceRegistry.new()
	_check(not unknown_parent_registry.configure([unknown_parent]), "M. unknown derivation parent fails")

	var duplicate_parent := _derived_record(
		"territory_source:duplicate_parent",
		["territory_source:parent", "territory_source:parent"],
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var parent := _base_record(
		"territory_source:parent",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var duplicate_parent_registry := VNextTerritorySourceRegistry.new()
	_check(not duplicate_parent_registry.configure([parent, duplicate_parent]), "duplicate parent IDs fail")

	var cycle_a := _derived_record(
		"territory_source:cycle_a",
		["territory_source:cycle_b"],
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var cycle_b := _derived_record(
		"territory_source:cycle_b",
		["territory_source:cycle_a"],
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var cycle_registry := VNextTerritorySourceRegistry.new()
	_check(not cycle_registry.configure([cycle_a, cycle_b]), "N. parent source cycle fails")


func _test_deterministic_order_and_fingerprint() -> void:
	var alpha := _base_record(
		"territory_source:alpha",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var zeta := _base_record(
		"territory_source:zeta",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var first := VNextTerritorySourceRegistry.new()
	var second := VNextTerritorySourceRegistry.new()
	_check(first.configure([zeta, alpha]), "determinism fixture A configures")
	_check(second.configure([alpha, zeta]), "determinism fixture B configures")
	_equal(
		first.source_snapshot_ids(),
		["territory_source:alpha", "territory_source:zeta"],
		"O. source ordering is deterministic"
	)
	_equal(first.source_snapshot_ids(), second.source_snapshot_ids(), "reversed insertion produces identical source ordering")
	_equal(first.fingerprint(), second.fingerprint(), "P. repeated registry construction produces identical fingerprint")
	_check(first.fingerprint().length() == 64, "registry fingerprint is a SHA-256 hex digest")


func _test_detached_reads() -> void:
	var source := _base_record(
		"territory_source:detached",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	var registry := VNextTerritorySourceRegistry.new()
	_check(registry.configure([source]), "detached-read fixture configures")
	var original_fingerprint := registry.fingerprint()
	var detached := registry.source_by_id("territory_source:detached")
	detached["dataset_name"] = "MUTATED"
	(detached["parent_source_snapshot_ids"] as Array).append("territory_source:fake")
	_equal(
		registry.source_by_id("territory_source:detached").get("dataset_name"),
		"Test Geography",
		"Q. detached source result cannot mutate registry authority"
	)
	var detached_admission := registry.admission_for("territory_source:detached")
	(detached_admission["gates"] as Dictionary)[VNextTerritorySourceAdmission.COMMERCIAL_USE_ALLOWED] = VNextTerritorySourceAdmission.FAIL
	_equal(registry.fingerprint(), original_fingerprint, "detached admission result cannot mutate registry fingerprint")
	_equal(
		registry.admission_for("territory_source:detached").get("production_geography_admitted"),
		true,
		"detached admission mutation cannot change authoritative admission"
	)
	_check(not registry.configure([source]), "configured registry is immutable")


func _test_live_registry_classification_and_audit() -> void:
	var live := VNextTerritorySourceRegistry.new()
	_check(live.configure_from_path(), "live production evidence registry configures")
	if not live.is_configured():
		return

	var cshapes := live.source_by_id("territory_source:cshapes_2_0_1900_03_12")
	_equal(
		cshapes.get("production_admission_status"),
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY,
		"R. CShapes live snapshot is REFERENCE_ONLY, not ADMITTED"
	)
	_equal(cshapes.get("commercial_use_allowed"), false, "CShapes live snapshot preserves non-commercial source fact")

	var natural_earth := live.source_by_id("territory_source:wwo_france_admin1_prototype")
	_equal(
		natural_earth.get("production_admission_status"),
		VNextTerritorySourceRecord.STATUS_REJECTED,
		"S. current Natural Earth Admin-1 prototype geometry is not ADMITTED"
	)
	_equal(natural_earth.get("prototype_only"), true, "Natural Earth France projection remains explicitly prototype-only")

	var report := live.audit_report()
	_equal(report.get("REGISTERED_SOURCE_COUNT"), 7, "live registry reports seven explicit evidence records")
	_equal(report.get("REFERENCE_ONLY_SOURCE_COUNT"), 3, "live registry reference-only count is exact")
	_equal(report.get("CANDIDATE_SOURCE_COUNT"), 2, "live registry candidate count is exact")
	_equal(report.get("ADMITTED_SOURCE_COUNT"), 0, "live registry admits no production geography")
	_equal(report.get("REJECTED_SOURCE_COUNT"), 2, "live registry rejected count is exact")
	_equal(report.get("PROTOTYPE_SOURCE_COUNT"), 2, "live registry prototype count is exact")
	_equal(report.get("LICENSE_RESTRICTED_SOURCE_COUNT"), 2, "live registry license-restricted count is exact")
	_equal(report.get("COMMERCIAL_INELIGIBLE_SOURCE_COUNT"), 2, "live registry commercial-ineligible count is exact")
	_equal(report.get("UNRESOLVED_LICENSE_SOURCE_COUNT"), 1, "live registry unresolved-license count is exact")
	_equal(report.get("UNRESOLVED_HISTORICAL_FIT_COUNT"), 2, "live registry unresolved-historical-fit count is exact")
	_equal(report.get("DERIVED_SOURCE_COUNT"), 4, "live registry derived-source count is exact")
	_equal(report.get("UNTRACEABLE_DERIVATION_COUNT"), 0, "all registered derived source lineage is traceable")
	_equal(report.get("PRODUCTION_GEOGRAPHY_AVAILABLE"), "NO", "live registry reports production geography unavailable")
	print("REGISTERED_SOURCE_COUNT=%d" % int(report.get("REGISTERED_SOURCE_COUNT", -1)))
	print("REFERENCE_ONLY_SOURCE_COUNT=%d" % int(report.get("REFERENCE_ONLY_SOURCE_COUNT", -1)))
	print("CANDIDATE_SOURCE_COUNT=%d" % int(report.get("CANDIDATE_SOURCE_COUNT", -1)))
	print("ADMITTED_SOURCE_COUNT=%d" % int(report.get("ADMITTED_SOURCE_COUNT", -1)))
	print("REJECTED_SOURCE_COUNT=%d" % int(report.get("REJECTED_SOURCE_COUNT", -1)))
	print("PROTOTYPE_SOURCE_COUNT=%d" % int(report.get("PROTOTYPE_SOURCE_COUNT", -1)))
	print("LICENSE_RESTRICTED_SOURCE_COUNT=%d" % int(report.get("LICENSE_RESTRICTED_SOURCE_COUNT", -1)))
	print("COMMERCIAL_INELIGIBLE_SOURCE_COUNT=%d" % int(report.get("COMMERCIAL_INELIGIBLE_SOURCE_COUNT", -1)))
	print("UNRESOLVED_LICENSE_SOURCE_COUNT=%d" % int(report.get("UNRESOLVED_LICENSE_SOURCE_COUNT", -1)))
	print("UNRESOLVED_HISTORICAL_FIT_COUNT=%d" % int(report.get("UNRESOLVED_HISTORICAL_FIT_COUNT", -1)))
	print("DERIVED_SOURCE_COUNT=%d" % int(report.get("DERIVED_SOURCE_COUNT", -1)))
	print("UNTRACEABLE_DERIVATION_COUNT=%d" % int(report.get("UNTRACEABLE_DERIVATION_COUNT", -1)))
	print("REGISTRY_FINGERPRINT=%s" % str(report.get("REGISTRY_FINGERPRINT", "")))
	print("PRODUCTION_GEOGRAPHY_AVAILABLE=%s" % str(report.get("PRODUCTION_GEOGRAPHY_AVAILABLE", "")))


func _test_admitted_query_and_zero_admitted_state() -> void:
	var admitted := _base_record(
		"territory_source:admitted_query",
		VNextTerritorySourceRecord.STATUS_ADMITTED
	)
	var reference := _base_record(
		"territory_source:reference_query",
		VNextTerritorySourceRecord.STATUS_REFERENCE_ONLY
	)
	var registry := VNextTerritorySourceRegistry.new()
	_check(registry.configure([reference, admitted]), "admitted-query fixture configures")
	var admitted_records := registry.admitted_sources()
	_equal(admitted_records.size(), 1, "T. production admitted-source query returns only ADMITTED records")
	if admitted_records.size() == 1:
		_equal(
			admitted_records[0].get("source_snapshot_id"),
			"territory_source:admitted_query",
			"reference-only source is excluded from production admitted-source query"
		)

	var zero_admitted := VNextTerritorySourceRegistry.new()
	_check(zero_admitted.configure([reference]), "U. zero admitted sources is a valid registry state")
	_equal(zero_admitted.admitted_sources().size(), 0, "zero-admission registry exposes no admitted source")
	_equal(zero_admitted.production_geography_available(), false, "zero-admission registry reports no production geography")


func _test_formal_non_composition_boundaries() -> void:
	_equal(FormalWorldSimulation.SCHEMA_ID, "formal_world_simulation_v10", "Formal schema remains v10")
	_equal(FormalWorldSimulation.TERRITORIAL_CONTROL_OWNER, "VNextSpatialWorld", "territorial controller ownership remains VNextSpatialWorld")
	_equal(
		FormalWorldSimulation.TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED,
		false,
		"X. VNextTerritorialControlLedger remains non-production / uncomposed"
	)
	var formal_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_simulation.gd")
	_check(
		not formal_source.contains("VNextTerritoryUnitCatalog"),
		"V. no VNextTerritoryUnitCatalog is composed in Formal"
	)
	_check(
		not formal_source.contains("VNextPopulationAuthority"),
		"W. no VNextPopulationAuthority is composed in Formal"
	)
	_check(
		not formal_source.contains("VNextTerritorialControlLedger"),
		"X. no VNextTerritorialControlLedger is instantiated in Formal"
	)


func _base_record(source_id: String, status: String) -> Dictionary:
	return {
		"source_snapshot_id": source_id,
		"dataset_name": "Test Geography",
		"dataset_version": "1.0",
		"provider": "Fixture Provider",
		"source_page": "https://example.invalid/source",
		"download_url": "https://example.invalid/download",
		"local_resource_path": FIXTURE_PATH,
		"source_sha256": FileAccess.get_sha256(FIXTURE_PATH),
		"snapshot_date": "1900-03-12",
		"valid_from": "1900-03-12",
		"valid_to": "1900-03-12",
		"geometry_scope": "fixture geometry",
		"geometry_granularity": "fixture_unit",
		"feature_count": 1,
		"coordinate_reference_system": "EPSG:4326",
		"derivation_kind": VNextTerritorySourceRecord.DERIVATION_RAW_EXTERNAL,
		"parent_source_snapshot_ids": [],
		"derivation_method": "",
		"derivation_parameters": {},
		"historical_target_date": "1900-03-12",
		"historical_fit_status": VNextTerritorySourceRecord.HISTORICAL_FIT_STRONG,
		"license_id": "TEST_PERMISSIVE",
		"license_url": "https://example.invalid/license",
		"redistribution_allowed": true,
		"derivative_work_allowed": true,
		"commercial_use_allowed": true,
		"share_alike_required": false,
		"attribution_required": false,
		"prototype_only": false,
		"production_admission_status": status,
		"production_admission_reason": (
			"ALL_GATES_PASSED"
			if status == VNextTerritorySourceRecord.STATUS_ADMITTED
			else "REFERENCE_POLICY_ONLY"
		),
	}


func _derived_record(source_id: String, parent_ids: Array, status: String) -> Dictionary:
	var record := _base_record(source_id, status)
	record["derivation_kind"] = VNextTerritorySourceRecord.DERIVATION_DERIVED_SNAPSHOT
	record["parent_source_snapshot_ids"] = parent_ids.duplicate()
	record["derivation_method"] = "Deterministic fixture derivation"
	record["derivation_parameters"] = {"mode": "fixture"}
	return record


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_check(true, label)
		return
	_check(false, "%s | actual=%s | expected=%s" % [
		label,
		var_to_str(actual),
		var_to_str(expected),
	])
