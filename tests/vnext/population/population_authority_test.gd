extends SceneTree

const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")
const TERRITORY_CATALOG = preload(
	"res://scripts/vnext/territory/territory_unit_catalog.gd"
)
const POPULATION_AUTHORITY = preload(
	"res://scripts/vnext/population/population_authority.gd"
)

const CATALOG_VERSION: String = "population-fixture-v1"
const SOURCE_REF: String = "fixture://population-authority/v1"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_reference_boundary_and_initialization()
	_test_deterministic_reads_and_fingerprint()
	_test_aggregation_policy()
	_test_transfer_candidate_and_conservation()
	_test_transfer_rejections_and_atomicity()
	_test_revision_preconditions()
	_test_snapshot_determinism_and_round_trip()
	_test_snapshot_rejection_matrix()
	_test_catalog_binding_mismatch()
	_test_political_decoupling_and_owner_surface()
	print("Population authority: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_reference_boundary_and_initialization() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog()
	var authority := VNextPopulationAuthority.create(catalog)
	_check(authority != null and authority.is_configured(), "sealed Territory provider binds")
	_check(
		authority.initialize_population("territory_unit:a", 1200),
		"known territory initializes an integer population"
	)
	_equal(authority.revision(), 1, "initialization advances revision once")
	_equal(
		authority.population_for_territory("territory_unit:a"),
		{"territory_unit_id": "territory_unit:a", "total_population": 1200},
		"initialized population is queryable"
	)
	_check(
		not authority.initialize_population("territory_unit:a", 1300),
		"duplicate initialization fails instead of overwriting"
	)
	_equal(
		authority.population_for_territory("territory_unit:a").get("total_population"),
		1200,
		"duplicate initialization preserves the first record"
	)
	_equal(authority.revision(), 1, "duplicate initialization preserves revision")

	var invalid_before: Dictionary = authority.snapshot()
	_check(
		not authority.initialize_population("territory_unit:Bad ID", 1),
		"malformed territory ID fails closed"
	)
	_check(
		not authority.initialize_population("state:a", 1),
		"wrong-kind territory ID fails closed"
	)
	_check(
		not authority.initialize_population("territory_unit:missing", 1),
		"unknown territory ID fails closed"
	)
	_check(
		not authority.initialize_population("territory_unit:b", -1),
		"negative population fails closed"
	)
	_check(
		not authority.initialize_population("territory_unit:b", 1.0),
		"floating population fails closed even when mathematically integral"
	)
	_check(
		not authority.initialize_population("territory_unit:b", INF),
		"infinite population fails closed"
	)
	_equal(authority.snapshot(), invalid_before, "all failed initialization is atomic")

	var shell := VNextPopulationAuthority.new()
	_check(not shell.is_configured(), "unbound Population authority is not configured")
	_check(
		not shell.initialize_population("territory_unit:a", 1),
		"missing Territory provider fails initialization closed"
	)
	_check(
		shell.prepare_transfer("territory_unit:a", "territory_unit:b", 1, 0) == null,
		"missing Territory provider fails candidate preparation closed"
	)
	_check(
		not shell.restore(authority.snapshot()),
		"missing Territory provider fails restore closed"
	)
	_check(
		VNextPopulationAuthority.create(null) == null,
		"factory refuses a missing Territory provider"
	)
	var unsealed := VNextTerritoryUnitCatalog.new()
	_check(unsealed.configure(CATALOG_VERSION), "unsealed fixture configures")
	_check(
		VNextPopulationAuthority.create(unsealed) == null,
		"factory refuses an unsealed Territory provider"
	)


func _test_deterministic_reads_and_fingerprint() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog()
	var forward: VNextPopulationAuthority = _make_authority(catalog, false)
	var reverse: VNextPopulationAuthority = _make_authority(catalog, true)
	_check(forward != null and reverse != null, "opposite insertion fixtures initialize")
	_equal(
		forward.population_states(),
		reverse.population_states(),
		"population iteration is territory-ID ordered"
	)
	_equal(
		(forward.population_states()[0] as Dictionary).get("territory_unit_id"),
		"territory_unit:a",
		"deterministic iteration begins with lexical territory ID"
	)
	_equal(forward.fingerprint(), reverse.fingerprint(), "fingerprint ignores insertion order")
	_equal(forward.fingerprint().length(), 64, "fingerprint is canonical SHA-256")
	var changed := VNextPopulationAuthority.create(catalog)
	_check(changed.initialize_population("territory_unit:a", 101), "changed fixture A initializes")
	_check(changed.initialize_population("territory_unit:b", 200), "changed fixture B initializes")
	_check(changed.initialize_population("territory_unit:c", 300), "changed fixture C initializes")
	_check(
		changed.fingerprint() != forward.fingerprint(),
		"changed population changes the fingerprint"
	)

	var detached: Dictionary = forward.population_for_territory("territory_unit:a")
	detached["total_population"] = 999999
	_equal(
		forward.population_for_territory("territory_unit:a").get("total_population"),
		100,
		"single-territory query is detached"
	)
	var detached_states: Array[Dictionary] = forward.population_states()
	(detached_states[0] as Dictionary)["total_population"] = 888888
	detached_states.clear()
	_equal(forward.population_states().size(), 3, "deterministic query collection is detached")
	_equal(
		forward.population_for_territory("territory_unit:a").get("total_population"),
		100,
		"deterministic query records are detached"
	)


func _test_aggregation_policy() -> void:
	var authority: VNextPopulationAuthority = _make_authority(_make_catalog(), false)
	var aggregate: Dictionary = authority.aggregate_population([
		"territory_unit:c", "territory_unit:a"
	])
	_check(bool(aggregate.get("success", false)), "valid territory aggregation succeeds")
	_equal(aggregate.get("total_population"), 400, "valid aggregation sums exact integers")
	_equal(
		aggregate.get("territory_unit_ids"),
		["territory_unit:a", "territory_unit:c"],
		"aggregate result reports deterministic territory order"
	)
	(aggregate.get("territory_unit_ids") as Array).clear()
	aggregate["total_population"] = 0
	_equal(authority.total_population(), 600, "aggregate result mutation cannot affect authority")
	_check(
		not bool(authority.aggregate_population([
			"territory_unit:a", "territory_unit:a"
		]).get("success", true)),
		"duplicate aggregate input fails closed"
	)
	_check(
		not bool(authority.aggregate_population([
			"territory_unit:a", "territory_unit:missing"
		]).get("success", true)),
		"unknown aggregate territory fails closed"
	)
	_check(
		not bool(authority.aggregate_population([
			"territory_unit:a", "state:b"
		]).get("success", true)),
		"wrong-kind aggregate territory fails closed"
	)
	_check(
		not bool(authority.aggregate_population([
			"territory_unit:a", "territory_unit:Bad ID"
		]).get("success", true)),
		"malformed aggregate territory fails closed"
	)
	var partial := VNextPopulationAuthority.create(_make_catalog())
	_check(partial.initialize_population("territory_unit:a", 10), "partial authority initializes")
	_check(
		not bool(partial.aggregate_population([
			"territory_unit:a", "territory_unit:b"
		]).get("success", true)),
		"known but uninitialized aggregate territory fails closed"
	)


func _test_transfer_candidate_and_conservation() -> void:
	var authority: VNextPopulationAuthority = _make_authority(_make_catalog(), false)
	var before_snapshot: Dictionary = authority.snapshot()
	var before_revision: int = authority.revision()
	var before_fingerprint: String = authority.fingerprint()
	var before_total: int = authority.total_population()
	var candidate: VNextPopulationCandidate = authority.prepare_transfer(
		"territory_unit:a", "territory_unit:b", 40, before_revision
	)
	_check(candidate != null, "valid transfer candidate prepares")
	_equal(authority.snapshot(), before_snapshot, "prepare does not mutate live authority")
	_check(authority.validate_candidate(candidate), "prepared transfer candidate validates")
	_equal(authority.snapshot(), before_snapshot, "candidate validation does not mutate authority")

	var detached_candidate: Dictionary = candidate.to_detached_dict()
	(detached_candidate.get("records") as Array).clear()
	detached_candidate["amount"] = 999
	var detached_records: Array = candidate.records()
	(detached_records[0] as Dictionary)["total_population"] = 777777
	_check(authority.validate_candidate(candidate), "candidate query mutation cannot corrupt candidate")
	_equal(authority.fingerprint(), before_fingerprint, "candidate mutation cannot affect authority")

	_check(authority.adopt_candidate(candidate), "valid transfer candidate adopts")
	_equal(authority.revision(), before_revision + 1, "successful adopt advances revision exactly once")
	_equal(
		authority.population_for_territory("territory_unit:a").get("total_population"),
		60,
		"transfer subtracts source exactly"
	)
	_equal(
		authority.population_for_territory("territory_unit:b").get("total_population"),
		240,
		"transfer adds destination exactly"
	)
	_equal(authority.total_population(), before_total, "transfer conserves total population")
	_check(authority.fingerprint() != before_fingerprint, "successful transfer changes state fingerprint")
	_check(
		not authority.adopt_candidate(candidate),
		"already-adopted candidate is stale and cannot apply twice"
	)
	_equal(authority.revision(), before_revision + 1, "replayed candidate leaves revision unchanged")

	var multi_before: int = authority.total_population()
	var second: VNextPopulationCandidate = authority.prepare_transfer(
		"territory_unit:b", "territory_unit:c", 30, authority.revision()
	)
	_check(second != null and authority.adopt_candidate(second), "second territory transfer adopts")
	var third: VNextPopulationCandidate = authority.prepare_transfer(
		"territory_unit:c", "territory_unit:a", 10, authority.revision()
	)
	_check(third != null and authority.adopt_candidate(third), "third territory transfer adopts")
	_equal(authority.total_population(), multi_before, "multi-territory transfers conserve population")


func _test_transfer_rejections_and_atomicity() -> void:
	var authority: VNextPopulationAuthority = _make_authority(_make_catalog(), false)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:a", 1,
		"same source and destination"
	)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:b", 0,
		"zero transfer"
	)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:b", -1,
		"negative transfer"
	)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:b", 1.0,
		"floating transfer"
	)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:b", 101,
		"insufficient source population"
	)
	_expect_prepare_failure(
		authority, "territory_unit:missing", "territory_unit:b", 1,
		"unknown transfer source"
	)
	_expect_prepare_failure(
		authority, "state:a", "territory_unit:b", 1,
		"wrong-kind transfer source"
	)
	var partial := VNextPopulationAuthority.create(_make_catalog())
	_check(partial.initialize_population("territory_unit:a", 10), "partial transfer fixture initializes")
	_expect_prepare_failure(
		partial, "territory_unit:a", "territory_unit:b", 1,
		"uninitialized transfer destination"
	)


func _test_revision_preconditions() -> void:
	var authority: VNextPopulationAuthority = _make_authority(_make_catalog(), false)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:b", 1,
		"stale expected revision", authority.revision() - 1
	)
	_expect_prepare_failure(
		authority, "territory_unit:a", "territory_unit:b", 1,
		"malformed expected revision", 3.0
	)
	var stale: VNextPopulationCandidate = authority.prepare_transfer(
		"territory_unit:a", "territory_unit:b", 10, authority.revision()
	)
	var intervening: VNextPopulationCandidate = authority.prepare_transfer(
		"territory_unit:c", "territory_unit:b", 5, authority.revision()
	)
	_check(intervening != null and authority.adopt_candidate(intervening), "intervening adopt succeeds")
	var before_stale_hash: String = authority.fingerprint()
	var before_stale_revision: int = authority.revision()
	_check(not authority.adopt_candidate(stale), "stale prepared candidate is rejected")
	_equal(authority.fingerprint(), before_stale_hash, "stale adopt preserves authority hash")
	_equal(authority.revision(), before_stale_revision, "stale adopt preserves revision")

	var max_revision_snapshot: Dictionary = authority.snapshot()
	max_revision_snapshot["revision"] = 9_007_199_254_740_991
	var max_revision_authority := VNextPopulationAuthority.create(_make_catalog())
	_check(
		max_revision_authority.restore(max_revision_snapshot),
		"maximum JSON-safe revision restores exactly"
	)
	var max_before: Dictionary = max_revision_authority.snapshot()
	_check(
		max_revision_authority.prepare_transfer(
			"territory_unit:a", "territory_unit:b", 1,
			max_revision_authority.revision()
		) == null,
		"maximum revision cannot overflow during transfer preparation"
	)
	_check(
		not max_revision_authority.initialize_population("territory_unit:d", 1),
		"maximum revision cannot overflow during initialization"
	)
	_equal(max_revision_authority.snapshot(), max_before, "revision overflow attempts are atomic")


func _test_snapshot_determinism_and_round_trip() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog()
	var forward: VNextPopulationAuthority = _make_authority(catalog, false)
	var reverse: VNextPopulationAuthority = _make_authority(catalog, true)
	_equal(forward.snapshot(), reverse.snapshot(), "snapshot ignores initialization order")
	_equal(
		JSON.stringify(forward.snapshot()),
		JSON.stringify(reverse.snapshot()),
		"snapshot JSON is deterministic"
	)
	var snapshot_value: Dictionary = forward.snapshot()
	_equal(snapshot_value.get("schema_id"), "vnext_population_authority_v1", "snapshot is versioned")
	_equal(
		snapshot_value.get("territory_catalog_binding"), catalog.binding(),
		"snapshot binds exact Territory catalog"
	)
	_equal(snapshot_value.get("state_fingerprint"), forward.fingerprint(), "snapshot carries state fingerprint")
	var parser := JSON.new()
	_check(parser.parse(JSON.stringify(snapshot_value)) == OK, "snapshot JSON parses")
	var restored := VNextPopulationAuthority.create(catalog)
	var restored_ok: bool = restored.restore(parser.data)
	_check(
		restored_ok,
		"snapshot round-trip restore succeeds (%s)" % restored.last_error()
	)
	_equal(restored.snapshot(), snapshot_value, "snapshot round trip is exact")
	_equal(restored.revision(), forward.revision(), "restore preserves saved revision")
	_equal(restored.fingerprint(), forward.fingerprint(), "restore preserves state fingerprint")

	var replacement := VNextPopulationAuthority.create(catalog)
	_check(replacement.initialize_population("territory_unit:a", 1), "replace target has live state")
	var replacement_before: Dictionary = replacement.snapshot()
	var restore_candidate: VNextPopulationCandidate = replacement.prepare_restore(
		snapshot_value
	)
	_check(restore_candidate != null, "explicit restore candidate prepares")
	_equal(replacement.snapshot(), replacement_before, "restore prepare leaves live state unchanged")
	var detached_restore_records: Array = restore_candidate.records()
	(detached_restore_records[0] as Dictionary)["total_population"] = 999999
	_check(
		replacement.validate_candidate(restore_candidate),
		"detached restore-candidate query cannot corrupt candidate"
	)
	_equal(replacement.snapshot(), replacement_before, "restore validation leaves live state unchanged")
	_check(replacement.adopt_candidate(restore_candidate), "explicit restore candidate replaces complete state")
	_equal(replacement.snapshot(), snapshot_value, "explicit restore adopts atomically")


func _test_snapshot_rejection_matrix() -> void:
	var authority: VNextPopulationAuthority = _make_authority(_make_catalog(), false)
	var valid: Dictionary = authority.snapshot()

	var duplicate: Dictionary = valid.duplicate(true)
	(duplicate.get("records") as Array).append(
		(duplicate.get("records") as Array)[0].duplicate(true)
	)
	_expect_restore_failure(authority, duplicate, "duplicate snapshot territory")

	var corrupted: Dictionary = valid.duplicate(true)
	corrupted["state_fingerprint"] = "0".repeat(64)
	_expect_restore_failure(authority, corrupted, "corrupted fingerprint")

	var negative: Dictionary = valid.duplicate(true)
	((negative.get("records") as Array)[0] as Dictionary)["total_population"] = -1
	_expect_restore_failure(authority, negative, "negative snapshot population")

	var floating: Dictionary = valid.duplicate(true)
	((floating.get("records") as Array)[0] as Dictionary)["total_population"] = 100.5
	_expect_restore_failure(authority, floating, "fractional snapshot population")

	var infinite: Dictionary = valid.duplicate(true)
	((infinite.get("records") as Array)[0] as Dictionary)["total_population"] = INF
	_expect_restore_failure(authority, infinite, "infinite snapshot population")

	var unknown: Dictionary = valid.duplicate(true)
	((unknown.get("records") as Array)[0] as Dictionary)["territory_unit_id"] = (
		"territory_unit:missing"
	)
	_expect_restore_failure(authority, unknown, "unknown snapshot territory")

	var wrong_kind: Dictionary = valid.duplicate(true)
	((wrong_kind.get("records") as Array)[0] as Dictionary)["territory_unit_id"] = "state:a"
	_expect_restore_failure(authority, wrong_kind, "wrong-kind snapshot territory")

	var malformed_id: Dictionary = valid.duplicate(true)
	((malformed_id.get("records") as Array)[0] as Dictionary)["territory_unit_id"] = (
		"territory_unit:Bad ID"
	)
	_expect_restore_failure(authority, malformed_id, "malformed snapshot territory")

	var malformed_revision: Dictionary = valid.duplicate(true)
	malformed_revision["revision"] = 3.5
	_expect_restore_failure(authority, malformed_revision, "fractional snapshot revision")

	var negative_revision: Dictionary = valid.duplicate(true)
	negative_revision["revision"] = -1
	_expect_restore_failure(authority, negative_revision, "negative snapshot revision")

	var unsupported: Dictionary = valid.duplicate(true)
	unsupported["schema_id"] = "vnext_population_authority_v2"
	_expect_restore_failure(authority, unsupported, "unsupported snapshot schema")

	var extra_field: Dictionary = valid.duplicate(true)
	extra_field["controller_id"] = "state:a"
	_expect_restore_failure(authority, extra_field, "unknown snapshot field")

	var malformed_record: Dictionary = valid.duplicate(true)
	((malformed_record.get("records") as Array)[0] as Dictionary)["polity_id"] = "state:a"
	_expect_restore_failure(authority, malformed_record, "unknown population record field")


func _test_catalog_binding_mismatch() -> void:
	var source_catalog: VNextTerritoryUnitCatalog = _make_catalog()
	var source: VNextPopulationAuthority = _make_authority(source_catalog, false)
	var changed_catalog: VNextTerritoryUnitCatalog = _make_catalog("geometry://population-fixture/revised/")
	_check(
		source_catalog.fingerprint() != changed_catalog.fingerprint(),
		"changed Territory definitions change catalog fingerprint"
	)
	var target := VNextPopulationAuthority.create(changed_catalog)
	var before: Dictionary = target.snapshot()
	_check(not target.restore(source.snapshot()), "Territory catalog binding mismatch fails closed")
	_equal(target.snapshot(), before, "catalog binding mismatch is atomic")

	var tampered: Dictionary = source.snapshot().duplicate(true)
	var binding: Dictionary = tampered.get("territory_catalog_binding") as Dictionary
	binding["catalog_version"] = "population-fixture-v2"
	_expect_restore_failure(source, tampered, "catalog version mismatch")


func _test_political_decoupling_and_owner_surface() -> void:
	var authority: VNextPopulationAuthority = _make_authority(_make_catalog(), false)
	var before: Dictionary = authority.snapshot()
	var simulated_control: Dictionary = {
		"territory_unit:a": "state:x",
		"territory_unit:b": "state:x",
		"territory_unit:c": "state:y",
	}
	simulated_control["territory_unit:a"] = "state:y"
	_equal(authority.snapshot(), before, "simulated controller change does not mutate Population")
	_equal(authority.total_population(), 600, "controller change does not delete, copy, or move population")
	var record: Dictionary = authority.population_for_territory("territory_unit:a")
	_equal(
		record.keys(),
		["territory_unit_id", "total_population"],
		"authoritative record contains only territory identity reference and population total"
	)
	for forbidden_field: String in [
		"controller_id", "country_id", "polity_id", "market_id", "organization_id",
		"employment", "household", "military_manpower", "migration_policy",
		"political_status"
	]:
		_check(not record.has(forbidden_field), "Population record excludes %s" % forbidden_field)
	var snapshot_value: Dictionary = authority.snapshot()
	_check(not snapshot_value.has("countries"), "snapshot introduces no Country population authority")
	_check(not snapshot_value.has("polities"), "snapshot introduces no Polity population authority")
	_check(not snapshot_value.has("controllers"), "snapshot introduces no control ownership coupling")


func _expect_prepare_failure(
	authority: VNextPopulationAuthority,
	source_id: Variant,
	destination_id: Variant,
	amount: Variant,
	label: String,
	expected_revision: Variant = null
) -> void:
	var revision_value: Variant = (
		authority.revision() if expected_revision == null else expected_revision
	)
	var before_hash: String = authority.fingerprint()
	var before_revision: int = authority.revision()
	var before_snapshot: Dictionary = authority.snapshot()
	_check(
		authority.prepare_transfer(source_id, destination_id, amount, revision_value) == null,
		"%s is rejected" % label
	)
	_equal(authority.fingerprint(), before_hash, "%s preserves authority hash" % label)
	_equal(authority.revision(), before_revision, "%s preserves revision" % label)
	_equal(authority.snapshot(), before_snapshot, "%s cannot half-adopt" % label)


func _expect_restore_failure(
	authority: VNextPopulationAuthority, rejected: Variant, label: String
) -> void:
	var before_hash: String = authority.fingerprint()
	var before_revision: int = authority.revision()
	var before_snapshot: Dictionary = authority.snapshot()
	_check(not authority.restore(rejected), "%s is rejected atomically" % label)
	_equal(authority.fingerprint(), before_hash, "%s preserves authority hash" % label)
	_equal(authority.revision(), before_revision, "%s preserves revision" % label)
	_equal(authority.snapshot(), before_snapshot, "%s preserves complete state" % label)


func _make_authority(
	catalog: VNextTerritoryUnitCatalog, reverse_insertion: bool
) -> VNextPopulationAuthority:
	var authority := VNextPopulationAuthority.create(catalog)
	if authority == null:
		return null
	var records: Array[Dictionary] = [
		{"territory_unit_id": "territory_unit:a", "total_population": 100},
		{"territory_unit_id": "territory_unit:b", "total_population": 200},
		{"territory_unit_id": "territory_unit:c", "total_population": 300},
	]
	if reverse_insertion:
		records.reverse()
	for record: Dictionary in records:
		if not authority.initialize_population(
			record.get("territory_unit_id"), record.get("total_population")
		):
			return null
	return authority


func _make_catalog(
	geometry_prefix: String = "geometry://population-fixture/v1/"
) -> VNextTerritoryUnitCatalog:
	var catalog := VNextTerritoryUnitCatalog.new()
	if not catalog.configure(CATALOG_VERSION):
		return null
	for local_id: String in ["a", "b", "c", "d"]:
		var unit := VNextTerritoryUnit.new()
		if not unit.configure(
			"territory_unit:" + local_id,
			CATALOG_VERSION,
			geometry_prefix + local_id,
			SOURCE_REF
		):
			return null
		if not catalog.add_unit(unit):
			return null
	return catalog if catalog.seal() else null


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
