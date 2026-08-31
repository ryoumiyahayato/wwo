extends SceneTree

const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")
const TERRITORY_CATALOG = preload(
	"res://scripts/vnext/territory/territory_unit_catalog.gd"
)
const CONTROL_LEDGER = preload(
	"res://scripts/vnext/territory/territorial_control_ledger.gd"
)
const POLITICAL_VIEW = preload(
	"res://scripts/formal/runtime_political_entity_view.gd"
)

const CATALOG_VERSION: String = "control-ledger-fixture-v1"
const SOURCE_SNAPSHOT_REF: String = "fixture://territorial-control/v1"
const TERRITORY_A: String = "territory_unit:a"
const TERRITORY_B: String = "territory_unit:b"
const TERRITORY_C: String = "territory_unit:c"
const TERRITORY_D: String = "territory_unit:d"
const CONTROLLER_A: String = "state:polity_a"
const CONTROLLER_B: String = "state:polity_b"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_reference_boundaries_fail_closed()
	_test_initial_assignment_and_explicit_uncontrolled()
	_test_invalid_ids_and_duplicates()
	_test_deterministic_queries_and_detached_projection()
	_test_candidate_isolation_revision_and_atomicity()
	_test_snapshot_round_trip_and_determinism()
	_test_corrupted_snapshot_rejection_is_atomic()
	_test_catalog_ownership_remains_immutable()
	print("Territorial control ledger: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_reference_boundaries_fail_closed() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog(false)
	var political_view: RuntimePoliticalEntityView = _make_political_view(false)
	_check(catalog != null and political_view != null, "reference fixtures configure")
	_check(
		VNextTerritorialControlLedger.create(null, political_view) == null,
		"missing territory catalog fails closed"
	)
	_check(
		VNextTerritorialControlLedger.create(catalog, null) == null,
		"missing political entity view fails closed"
	)
	var unsealed := VNextTerritoryUnitCatalog.new()
	_check(unsealed.configure(CATALOG_VERSION), "unsealed reference fixture configures")
	_check(
		VNextTerritorialControlLedger.create(unsealed, political_view) == null,
		"unsealed territory catalog fails closed"
	)
	var wrong_kind_view: RuntimePoliticalEntityView = _make_wrong_kind_political_view()
	_check(
		VNextTerritorialControlLedger.create(catalog, wrong_kind_view) == null,
		"wrong-kind identities invalidate the political reference view"
	)
	var inactive_view: RuntimePoliticalEntityView = _make_inactive_political_view()
	_check(
		VNextTerritorialControlLedger.create(catalog, inactive_view) == null,
		"inactive identities invalidate the current-world political reference view"
	)
	var raw := VNextTerritorialControlLedger.new()
	_check(
		raw.prepare_control_change(
			TERRITORY_A, CONTROL_LEDGER.CONTROLLED, CONTROLLER_A, 0
		).is_empty(),
		"unconfigured ledger refuses mutation"
	)
	_equal(raw.authoritative_fingerprint(), "", "unconfigured ledger has no authority hash")


func _test_initial_assignment_and_explicit_uncontrolled() -> void:
	var ledger: VNextTerritorialControlLedger = _make_ledger()
	_check(ledger != null and ledger.is_configured(), "ledger binds immutable references")
	var initial: Array[Dictionary] = [
		CONTROL_LEDGER.controlled_assignment(TERRITORY_C, CONTROLLER_A),
		CONTROL_LEDGER.uncontrolled_assignment(TERRITORY_B),
		CONTROL_LEDGER.controlled_assignment(TERRITORY_A, CONTROLLER_A),
	]
	_check(ledger.initialize_assignments(initial, 0), "valid initial assignments adopt")
	_equal(ledger.revision(), 1, "initial adoption advances revision exactly once")
	_equal(ledger.assignment_count(), 3, "initial assignments have one record per territory")
	var controlled: Dictionary = ledger.controller_for_territory(TERRITORY_A)
	_equal(controlled.get("control_state"), CONTROL_LEDGER.CONTROLLED, "controlled state is explicit")
	_equal(controlled.get("controller_id"), CONTROLLER_A, "controller query returns runtime political identity")
	var uncontrolled: Dictionary = ledger.controller_for_territory(TERRITORY_B)
	_equal(uncontrolled.get("control_state"), CONTROL_LEDGER.UNCONTROLLED, "uncontrolled state is explicit")
	_check(uncontrolled.has("controller_id"), "uncontrolled record retains explicit controller field")
	_check(
		typeof(uncontrolled.get("controller_id")) == TYPE_NIL,
		"uncontrolled state uses null rather than empty or missing identity"
	)
	_check(
		ledger.controller_for_territory(TERRITORY_D).is_empty()
		and not ledger.has_control_record(TERRITORY_D),
		"uninitialized and explicit uncontrolled states remain distinguishable"
	)
	_equal(ledger.uncontrolled_territory_ids(), [TERRITORY_B], "uncontrolled reverse query is deterministic")


func _test_invalid_ids_and_duplicates() -> void:
	var unknown_territory: VNextTerritorialControlLedger = _make_ledger()
	_assert_prepare_rejected_unchanged(
		unknown_territory,
		"territory_unit:missing",
		CONTROL_LEDGER.CONTROLLED,
		CONTROLLER_A,
		"unknown territory"
	)
	var wrong_kind_territory: VNextTerritorialControlLedger = _make_ledger()
	_assert_prepare_rejected_unchanged(
		wrong_kind_territory,
		"state:a",
		CONTROL_LEDGER.CONTROLLED,
		CONTROLLER_A,
		"wrong-kind territory"
	)
	var unknown_controller: VNextTerritorialControlLedger = _make_ledger()
	_assert_prepare_rejected_unchanged(
		unknown_controller,
		TERRITORY_A,
		CONTROL_LEDGER.CONTROLLED,
		"state:missing",
		"unknown controller"
	)
	var wrong_kind_controller: VNextTerritorialControlLedger = _make_ledger()
	_assert_prepare_rejected_unchanged(
		wrong_kind_controller,
		TERRITORY_A,
		CONTROL_LEDGER.CONTROLLED,
		"organization:polity_a",
		"wrong-kind controller"
	)
	var duplicate: VNextTerritorialControlLedger = _make_ledger()
	var duplicate_records: Array[Dictionary] = [
		CONTROL_LEDGER.controlled_assignment(TERRITORY_A, CONTROLLER_A),
		CONTROL_LEDGER.uncontrolled_assignment(TERRITORY_A),
	]
	var duplicate_hash: String = duplicate.authoritative_fingerprint()
	_check(
		duplicate.prepare_initial_assignments(duplicate_records, 0).is_empty(),
		"duplicate territory assignment is rejected"
	)
	_equal(duplicate.revision(), 0, "duplicate rejection preserves revision")
	_equal(duplicate.authoritative_fingerprint(), duplicate_hash, "duplicate rejection preserves hash")
	var ambiguous: VNextTerritorialControlLedger = _make_ledger()
	_check(
		ambiguous.prepare_control_change(
			TERRITORY_A, CONTROL_LEDGER.UNCONTROLLED, "", 0
		).is_empty(),
		"empty-string controller cannot represent uncontrolled state"
	)
	_check(
		ambiguous.prepare_control_change(
			TERRITORY_A, CONTROL_LEDGER.CONTROLLED, null, 0
		).is_empty(),
		"controlled state cannot omit a controller"
	)


func _test_deterministic_queries_and_detached_projection() -> void:
	var forward: VNextTerritorialControlLedger = _make_initialized_ledger(false)
	var reverse: VNextTerritorialControlLedger = _make_initialized_ledger(true)
	_check(forward != null and reverse != null, "insertion-order fixtures initialize")
	_equal(forward.assignments(), reverse.assignments(), "assignment ordering ignores insertion order")
	_equal(
		forward.authoritative_fingerprint(),
		reverse.authoritative_fingerprint(),
		"control fingerprint ignores insertion order"
	)
	_equal(forward.authoritative_fingerprint().length(), 64, "control fingerprint is SHA-256")
	var reverse_query: Array[String] = forward.territories_controlled_by(CONTROLLER_A)
	_equal(reverse_query, [TERRITORY_A, TERRITORY_C], "reverse controller query is sorted")
	reverse_query.clear()
	_equal(
		forward.territories_controlled_by(CONTROLLER_A),
		[TERRITORY_A, TERRITORY_C],
		"reverse query result is detached"
	)
	var detached_record: Dictionary = forward.controller_for_territory(TERRITORY_A)
	detached_record["controller_id"] = CONTROLLER_B
	_equal(
		forward.controller_for_territory(TERRITORY_A).get("controller_id"),
		CONTROLLER_A,
		"single-territory query is detached"
	)
	var detached_assignments: Array[Dictionary] = forward.assignments()
	(detached_assignments[0] as Dictionary)["controller_id"] = CONTROLLER_B
	detached_assignments.clear()
	_equal(forward.assignment_count(), 4, "detached assignment collection cannot mutate ledger")
	var polity_projection: Dictionary = {
		CONTROLLER_A: forward.territories_controlled_by(CONTROLLER_A),
		CONTROLLER_B: forward.territories_controlled_by(CONTROLLER_B),
	}
	(polity_projection[CONTROLLER_A] as Array).clear()
	polity_projection[CONTROLLER_B] = [TERRITORY_A, TERRITORY_B]
	_equal(
		forward.territories_controlled_by(CONTROLLER_A),
		[TERRITORY_A, TERRITORY_C],
		"derived polity territory projection cannot mutate authority"
	)


func _test_candidate_isolation_revision_and_atomicity() -> void:
	var ledger: VNextTerritorialControlLedger = _make_initialized_ledger(false)
	var before_snapshot: Dictionary = ledger.snapshot()
	var before_hash: String = ledger.authoritative_fingerprint()
	var before_revision: int = ledger.revision()
	var candidate: Dictionary = ledger.prepare_control_change(
		TERRITORY_A,
		CONTROL_LEDGER.CONTROLLED,
		CONTROLLER_B,
		before_revision
	)
	_check(not candidate.is_empty(), "valid control change candidate prepares")
	_equal(ledger.snapshot(), before_snapshot, "candidate preparation cannot mutate authority")
	_equal(ledger.authoritative_fingerprint(), before_hash, "candidate preparation preserves hash")
	_equal(ledger.revision(), before_revision, "candidate preparation preserves revision")
	var exposed_assignments: Array = candidate.get("assignments") as Array
	(exposed_assignments[0] as Dictionary)["controller_id"] = "state:tampered"
	candidate["assignments"] = exposed_assignments
	_equal(
		ledger.controller_for_territory(TERRITORY_A).get("controller_id"),
		CONTROLLER_A,
		"candidate mutation cannot mutate live controller"
	)
	_check(not ledger.adopt_candidate(candidate), "mutated candidate is rejected")
	_equal(ledger.authoritative_fingerprint(), before_hash, "failed candidate preserves hash")
	_equal(ledger.revision(), before_revision, "failed candidate preserves revision")
	_check(
		ledger.prepare_control_change(
			TERRITORY_A, CONTROL_LEDGER.CONTROLLED, CONTROLLER_B, before_revision - 1
		).is_empty(),
		"stale expected revision is rejected during prepare"
	)
	_equal(ledger.revision(), before_revision, "stale prepare preserves revision")
	var malformed: Dictionary = ledger.prepare_control_change(
		TERRITORY_A, CONTROL_LEDGER.CONTROLLED, CONTROLLER_B, before_revision
	)
	malformed.erase("candidate_fingerprint")
	_check(not ledger.validate_candidate(malformed), "malformed candidate fails validation")
	_check(not ledger.adopt_candidate(malformed), "malformed candidate fails adoption")
	_equal(ledger.snapshot(), before_snapshot, "malformed candidate rejection is atomic")
	var valid: Dictionary = ledger.prepare_control_change(
		TERRITORY_A, CONTROL_LEDGER.CONTROLLED, CONTROLLER_B, before_revision
	)
	_check(ledger.validate_candidate(valid), "valid candidate passes local validation")
	_check(ledger.adopt_candidate(valid), "valid candidate adopts atomically")
	_equal(ledger.revision(), before_revision + 1, "successful adopt advances revision exactly once")
	_equal(
		ledger.controller_for_territory(TERRITORY_A).get("controller_id"),
		CONTROLLER_B,
		"successful adopt replaces controller"
	)
	var after_success: Dictionary = ledger.snapshot()
	_check(not ledger.adopt_candidate(valid), "already-adopted candidate becomes stale")
	_equal(ledger.snapshot(), after_success, "failed stale adopt leaves authority unchanged")


func _test_snapshot_round_trip_and_determinism() -> void:
	var source: VNextTerritorialControlLedger = _make_initialized_ledger(false)
	_check(
		source.adopt_candidate(source.prepare_control_change(
			TERRITORY_A, CONTROL_LEDGER.CONTROLLED, CONTROLLER_B, source.revision()
		)),
		"snapshot source adopts a second revision"
	)
	var saved: Dictionary = source.snapshot()
	_equal(saved, source.snapshot(), "repeated snapshots are deterministic")
	_equal(saved.get("schema_id"), CONTROL_LEDGER.SNAPSHOT_SCHEMA_ID, "snapshot schema is explicit")
	_equal(saved.get("revision"), 2, "snapshot persists control revision")
	_equal(saved.get("fingerprint"), source.authoritative_fingerprint(), "snapshot persists authoritative fingerprint")
	var parser := JSON.new()
	_equal(parser.parse(JSON.stringify(saved)), OK, "snapshot is JSON round-trip safe")
	var restored: VNextTerritorialControlLedger = _make_ledger()
	_check(restored.restore(parser.data), "JSON-decoded snapshot restores")
	_equal(restored.snapshot(), saved, "snapshot round trip preserves complete authority")
	_equal(restored.revision(), source.revision(), "restore preserves saved revision")
	var detached: Dictionary = source.snapshot()
	(detached.get("assignments") as Array).clear()
	(detached.get("territory_catalog_binding") as Dictionary)["catalog_version"] = "tampered"
	_equal(source.snapshot(), saved, "snapshot result is deeply detached")


func _test_corrupted_snapshot_rejection_is_atomic() -> void:
	var ledger: VNextTerritorialControlLedger = _make_initialized_ledger(false)
	var saved: Dictionary = ledger.snapshot()
	var corruptions: Array[Dictionary] = []

	var corrupted_fingerprint: Dictionary = saved.duplicate(true)
	corrupted_fingerprint["fingerprint"] = "0".repeat(64)
	corruptions.append(corrupted_fingerprint)

	var invalid_revision: Dictionary = saved.duplicate(true)
	invalid_revision["revision"] = -1
	corruptions.append(invalid_revision)

	var wrong_binding: Dictionary = saved.duplicate(true)
	(wrong_binding["territory_catalog_binding"] as Dictionary)["catalog_version"] = "other"
	corruptions.append(wrong_binding)

	var duplicate_record: Dictionary = saved.duplicate(true)
	var duplicate_assignments: Array = duplicate_record["assignments"] as Array
	duplicate_assignments.append((duplicate_assignments[0] as Dictionary).duplicate(true))
	duplicate_record["assignments"] = duplicate_assignments
	corruptions.append(duplicate_record)

	var unknown_territory: Dictionary = saved.duplicate(true)
	(unknown_territory["assignments"] as Array)[0]["territory_unit_id"] = "territory_unit:missing"
	corruptions.append(unknown_territory)

	var wrong_kind_territory: Dictionary = saved.duplicate(true)
	(wrong_kind_territory["assignments"] as Array)[0]["territory_unit_id"] = "state:a"
	corruptions.append(wrong_kind_territory)

	var unknown_controller: Dictionary = saved.duplicate(true)
	var controlled_index: int = _first_controlled_index(unknown_controller["assignments"] as Array)
	(unknown_controller["assignments"] as Array)[controlled_index]["controller_id"] = "state:missing"
	corruptions.append(unknown_controller)

	var wrong_kind_controller: Dictionary = saved.duplicate(true)
	controlled_index = _first_controlled_index(wrong_kind_controller["assignments"] as Array)
	(wrong_kind_controller["assignments"] as Array)[controlled_index]["controller_id"] = "organization:polity_a"
	corruptions.append(wrong_kind_controller)

	var ambiguous_uncontrolled: Dictionary = saved.duplicate(true)
	var uncontrolled_index: int = _first_uncontrolled_index(ambiguous_uncontrolled["assignments"] as Array)
	(ambiguous_uncontrolled["assignments"] as Array)[uncontrolled_index]["controller_id"] = ""
	corruptions.append(ambiguous_uncontrolled)

	var malformed_fields: Dictionary = saved.duplicate(true)
	(malformed_fields["assignments"] as Array)[0]["sovereign_id"] = CONTROLLER_A
	corruptions.append(malformed_fields)

	for corruption_index: int in corruptions.size():
		var before: Dictionary = ledger.snapshot()
		var before_hash: String = ledger.authoritative_fingerprint()
		var before_revision: int = ledger.revision()
		_check(
			not ledger.restore(corruptions[corruption_index]),
			"corrupted snapshot %d is rejected" % corruption_index
		)
		_equal(ledger.snapshot(), before, "corrupted restore %d preserves state" % corruption_index)
		_equal(ledger.authoritative_fingerprint(), before_hash, "corrupted restore %d preserves hash" % corruption_index)
		_equal(ledger.revision(), before_revision, "corrupted restore %d preserves revision" % corruption_index)


func _test_catalog_ownership_remains_immutable() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog(false)
	var catalog_fingerprint: String = catalog.fingerprint()
	var catalog_records: Array[VNextTerritoryUnit] = catalog.units()
	var political_view: RuntimePoliticalEntityView = _make_political_view(false)
	var ledger: VNextTerritorialControlLedger = VNextTerritorialControlLedger.create(
		catalog, political_view
	)
	_check(
		ledger.initialize_assignments([
			CONTROL_LEDGER.controlled_assignment(TERRITORY_A, CONTROLLER_A),
			CONTROL_LEDGER.uncontrolled_assignment(TERRITORY_B),
		], 0),
		"ownership boundary fixture initializes"
	)
	_equal(catalog.fingerprint(), catalog_fingerprint, "control mutation cannot change territory catalog fingerprint")
	_equal(catalog.units().size(), catalog_records.size(), "control mutation cannot change territory catalog records")
	for unit: VNextTerritoryUnit in catalog.units():
		var record: Dictionary = unit.to_detached_dict()
		_check(not record.has("controller_id"), "immutable TerritoryUnit has no controller field")
		_check(not record.has("control_state"), "immutable TerritoryUnit has no control field")
	_check(
		not ledger.has_method("commit_transaction")
		and not ledger.has_method("prepare_transaction"),
		"ledger is not a WorldTransactionCoordinator participant"
	)


func _make_initialized_ledger(reverse_insertion: bool) -> VNextTerritorialControlLedger:
	var ledger: VNextTerritorialControlLedger = _make_ledger()
	if ledger == null:
		return null
	var records: Array[Dictionary] = [
		CONTROL_LEDGER.controlled_assignment(TERRITORY_A, CONTROLLER_A),
		CONTROL_LEDGER.uncontrolled_assignment(TERRITORY_B),
		CONTROL_LEDGER.controlled_assignment(TERRITORY_C, CONTROLLER_A),
		CONTROL_LEDGER.controlled_assignment(TERRITORY_D, CONTROLLER_B),
	]
	if reverse_insertion:
		records.reverse()
	return ledger if ledger.initialize_assignments(records, 0) else null


func _make_ledger() -> VNextTerritorialControlLedger:
	return VNextTerritorialControlLedger.create(
		_make_catalog(false), _make_political_view(false)
	)


func _make_catalog(reverse_insertion: bool) -> VNextTerritoryUnitCatalog:
	var local_ids: Array[String] = ["a", "b", "c", "d"]
	if reverse_insertion:
		local_ids.reverse()
	var catalog := VNextTerritoryUnitCatalog.new()
	if not catalog.configure(CATALOG_VERSION):
		return null
	for local_id: String in local_ids:
		var unit := VNextTerritoryUnit.new()
		if not unit.configure(
			"territory_unit:" + local_id,
			CATALOG_VERSION,
			"geometry://control-ledger/" + local_id,
			SOURCE_SNAPSHOT_REF
		):
			return null
		if not catalog.add_unit(unit):
			return null
	return catalog if catalog.seal() else null


func _make_political_view(reverse_insertion: bool) -> RuntimePoliticalEntityView:
	var entities: Array[Dictionary] = [
		_entity(CONTROLLER_A, "historical_polity_a"),
		_entity(CONTROLLER_B, "historical_polity_b"),
	]
	if reverse_insertion:
		entities.reverse()
	return RuntimePoliticalEntityView.new({
		"schema_id": "runtime_political_registry_v2",
		"entities": entities,
		"authority_relations": [],
	})


func _make_wrong_kind_political_view() -> RuntimePoliticalEntityView:
	return RuntimePoliticalEntityView.new({
		"schema_id": "runtime_political_registry_v2",
		"entities": [{"runtime_id": "organization:not_a_polity"}],
		"authority_relations": [],
	})


func _make_inactive_political_view() -> RuntimePoliticalEntityView:
	var inactive: Dictionary = _entity(CONTROLLER_A, "historical_polity_a")
	inactive["lifecycle_status"] = "retired"
	return RuntimePoliticalEntityView.new({
		"schema_id": "runtime_political_registry_v2",
		"entities": [inactive],
		"authority_relations": [],
	})


func _entity(runtime_id: String, source_id: String) -> Dictionary:
	return {
		"runtime_id": runtime_id,
		"source_historical_ids": [source_id],
		"lifecycle_status": "active",
		"lineage": {
			"origin_kind": "historical_seed",
			"origin_tick": 0,
			"predecessor_runtime_ids": [],
		},
	}


func _assert_prepare_rejected_unchanged(
	ledger: VNextTerritorialControlLedger,
	territory_unit_id: String,
	control_state: String,
	controller_id: Variant,
	label: String
) -> void:
	var before: Dictionary = ledger.snapshot()
	var before_hash: String = ledger.authoritative_fingerprint()
	var before_revision: int = ledger.revision()
	_check(
		ledger.prepare_control_change(
			territory_unit_id,
			control_state,
			controller_id,
			before_revision
		).is_empty(),
		"%s is rejected" % label
	)
	_equal(ledger.snapshot(), before, "%s preserves live state" % label)
	_equal(ledger.authoritative_fingerprint(), before_hash, "%s preserves live hash" % label)
	_equal(ledger.revision(), before_revision, "%s preserves revision" % label)


func _first_controlled_index(assignments: Array) -> int:
	for index: int in assignments.size():
		if (assignments[index] as Dictionary).get("control_state") == CONTROL_LEDGER.CONTROLLED:
			return index
	return -1


func _first_uncontrolled_index(assignments: Array) -> int:
	for index: int in assignments.size():
		if (assignments[index] as Dictionary).get("control_state") == CONTROL_LEDGER.UNCONTROLLED:
			return index
	return -1


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
