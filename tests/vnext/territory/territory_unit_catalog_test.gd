extends SceneTree

const STABLE_ID = preload("res://scripts/vnext/identity/stable_id.gd")
const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")
const TERRITORY_CATALOG = preload(
	"res://scripts/vnext/territory/territory_unit_catalog.gd"
)

const CATALOG_VERSION: String = "synthetic-territory-v1"
const SOURCE_SNAPSHOT_REF: String = "fixture://synthetic-territory-grid/v1"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_territory_identity_kind()
	_test_minimal_immutable_record()
	_test_malformed_wrong_kind_and_missing_geometry_rejected()
	_test_duplicate_id_and_version_mismatch_rejected()
	_test_deterministic_sealed_catalog()
	_test_deep_copy_isolation()
	_test_seal_is_immutable()
	_test_version_fingerprint_binding()
	_test_adjacency_validation()
	print("Territory unit catalog: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_territory_identity_kind() -> void:
	var territory_unit_id: String = STABLE_ID.compose("territory_unit", "grid_a1")
	_equal(territory_unit_id, "territory_unit:grid_a1", "territory unit ID composes")
	_check(STABLE_ID.is_valid(territory_unit_id), "territory unit ID is globally valid")
	_equal(STABLE_ID.kind_of(territory_unit_id), "territory_unit", "territory kind parses")
	_check(
		not TERRITORY_UNIT.is_valid_territory_unit_id("state:grid_a1"),
		"historical polity identity is not territory identity"
	)


func _test_minimal_immutable_record() -> void:
	var unit: VNextTerritoryUnit = _make_unit(
		"a1", ["territory_unit:b1", "territory_unit:a2"]
	)
	_check(unit != null and unit.is_configured(), "minimal territory record configures")
	_equal(
		unit.neighbor_ids(),
		["territory_unit:a2", "territory_unit:b1"],
		"neighbor IDs use canonical ordering"
	)
	_check(
		not unit.configure(
			"territory_unit:replacement",
			CATALOG_VERSION,
			"geometry://replacement",
			SOURCE_SNAPSHOT_REF
		),
		"configured territory record is immutable"
	)
	var record: Dictionary = unit.to_detached_dict()
	_equal(
		record.keys().size(),
		5,
		"record surface is limited to identity, catalog, geometry, source, and adjacency"
	)
	var forbidden_fields: Array[String] = [
		"polity", "polity_id", "controller", "controller_id", "sovereign",
		"sovereign_id", "population", "gdp", "inventory", "army", "occupation",
		"control", "runtime_control"
	]
	for forbidden_field: String in forbidden_fields:
		_check(not record.has(forbidden_field), "record excludes %s" % forbidden_field)


func _test_malformed_wrong_kind_and_missing_geometry_rejected() -> void:
	var malformed := VNextTerritoryUnit.new()
	_check(
		not malformed.configure(
			"territory_unit:Bad Unit", CATALOG_VERSION, "geometry://bad", SOURCE_SNAPSHOT_REF
		),
		"malformed territory unit ID is rejected"
	)
	var wrong_kind := VNextTerritoryUnit.new()
	_check(
		not wrong_kind.configure(
			"state:grid_a1", CATALOG_VERSION, "geometry://bad", SOURCE_SNAPSHOT_REF
		),
		"wrong-kind stable ID is rejected"
	)
	var missing_geometry := VNextTerritoryUnit.new()
	_check(
		not missing_geometry.configure(
			"territory_unit:grid_a1", CATALOG_VERSION, "", SOURCE_SNAPSHOT_REF
		),
		"missing geometry reference is rejected"
	)
	var missing_source := VNextTerritoryUnit.new()
	_check(
		not missing_source.configure(
			"territory_unit:grid_a1", CATALOG_VERSION, "geometry://grid/a1", ""
		),
		"missing source snapshot reference is rejected"
	)


func _test_duplicate_id_and_version_mismatch_rejected() -> void:
	var catalog := VNextTerritoryUnitCatalog.new()
	_check(catalog.configure(CATALOG_VERSION), "duplicate fixture catalog configures")
	_check(catalog.add_unit(_make_unit("a1")), "first globally unique ID is accepted")
	_check(not catalog.add_unit(_make_unit("a1")), "duplicate territory ID is rejected")
	var wrong_version: VNextTerritoryUnit = _make_unit("a2", [], "other-version")
	_check(not catalog.add_unit(wrong_version), "record/catalog version mismatch is rejected")


func _test_deterministic_sealed_catalog() -> void:
	var forward: VNextTerritoryUnitCatalog = _make_catalog(false)
	var reverse: VNextTerritoryUnitCatalog = _make_catalog(true)
	_check(forward != null and forward.is_sealed(), "forward catalog seals")
	_check(reverse != null and reverse.is_sealed(), "reverse-inserted catalog seals")
	_equal(forward.unit_count(), 8, "synthetic fixture contains eight territory units")
	_equal(forward.unit_ids(), reverse.unit_ids(), "catalog ordering ignores insertion order")
	_equal(
		forward.fingerprint(),
		reverse.fingerprint(),
		"catalog fingerprint ignores insertion order"
	)
	_equal(forward.fingerprint().length(), 64, "catalog fingerprint is SHA-256")
	var changed_geometry: VNextTerritoryUnitCatalog = _make_catalog_with_changed_geometry()
	_check(
		changed_geometry != null and changed_geometry.fingerprint() != forward.fingerprint(),
		"geometry reference participates in catalog fingerprint"
	)
	_check(
		forward.has_unit("territory_unit:b2")
		and not forward.has_unit("state:b2")
		and forward.unit_by_id("territory_unit:missing") == null,
		"queries require known territory-unit identities"
	)


func _test_deep_copy_isolation() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog(false)
	var detached: VNextTerritoryUnit = catalog.unit_by_id("territory_unit:a1")
	var detached_neighbors: Array[String] = detached.neighbor_ids()
	detached_neighbors.clear()
	var detached_dict: Dictionary = detached.to_detached_dict()
	detached_dict["geometry_ref"] = "geometry://tampered"
	(detached_dict["neighbor_ids"] as Array).clear()
	var detached_units: Array[VNextTerritoryUnit] = catalog.units()
	detached_units.clear()
	_equal(
		catalog.neighbor_ids("territory_unit:a1"),
		["territory_unit:a2", "territory_unit:b1"],
		"query array mutation cannot change sealed adjacency"
	)
	_equal(
		catalog.unit_by_id("territory_unit:a1").geometry_ref(),
		"geometry://synthetic-grid/v1/a1",
		"query dictionary mutation cannot change geometry reference"
	)
	_equal(catalog.unit_count(), 8, "query collection mutation cannot change catalog")


func _test_seal_is_immutable() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog(false)
	var original_fingerprint: String = catalog.fingerprint()
	_check(not catalog.add_unit(_make_unit("z9")), "sealed catalog rejects additions")
	_check(not catalog.configure("replacement-version"), "sealed catalog rejects reconfigure")
	_check(not catalog.seal(), "sealed catalog rejects a second seal")
	_equal(catalog.fingerprint(), original_fingerprint, "rejected mutations preserve fingerprint")


func _test_version_fingerprint_binding() -> void:
	var catalog: VNextTerritoryUnitCatalog = _make_catalog(false)
	var binding: Dictionary = catalog.binding()
	_check(catalog.validates_binding(binding), "exact version/fingerprint binding validates")
	var mutated_version: Dictionary = binding.duplicate(true)
	mutated_version["catalog_version"] = "synthetic-territory-v2"
	_check(not catalog.validates_binding(mutated_version), "wrong catalog version binding is rejected")
	var mutated_fingerprint: Dictionary = binding.duplicate(true)
	mutated_fingerprint["catalog_fingerprint"] = "0".repeat(64)
	_check(not catalog.validates_binding(mutated_fingerprint), "wrong fingerprint binding is rejected")
	var extended_binding: Dictionary = binding.duplicate(true)
	extended_binding["runtime_controller"] = "state:example"
	_check(not catalog.validates_binding(extended_binding), "binding rejects runtime ownership fields")
	var detached_binding: Dictionary = catalog.binding()
	detached_binding["catalog_fingerprint"] = "tampered"
	_check(catalog.validates_binding(binding), "binding queries are detached")


func _test_adjacency_validation() -> void:
	var self_neighbor := VNextTerritoryUnit.new()
	_check(
		not self_neighbor.configure(
			"territory_unit:a1",
			CATALOG_VERSION,
			"geometry://synthetic-grid/v1/a1",
			SOURCE_SNAPSHOT_REF,
			["territory_unit:a1"]
		),
		"self neighbor is rejected"
	)
	var duplicate_neighbor := VNextTerritoryUnit.new()
	_check(
		not duplicate_neighbor.configure(
			"territory_unit:a1",
			CATALOG_VERSION,
			"geometry://synthetic-grid/v1/a1",
			SOURCE_SNAPSHOT_REF,
			["territory_unit:a2", "territory_unit:a2"]
		),
		"duplicate neighbor is rejected"
	)
	var unknown_catalog := VNextTerritoryUnitCatalog.new()
	_check(unknown_catalog.configure(CATALOG_VERSION), "unknown-neighbor catalog configures")
	_check(
		unknown_catalog.add_unit(_make_unit("a1", ["territory_unit:missing"])),
		"unknown neighbor remains pending until full-catalog validation"
	)
	_check(not unknown_catalog.seal(), "unknown neighbor prevents seal")
	var asymmetric := VNextTerritoryUnitCatalog.new()
	_check(asymmetric.configure(CATALOG_VERSION), "asymmetric catalog configures")
	_check(asymmetric.add_unit(_make_unit("a1", ["territory_unit:a2"])), "edge source adds")
	_check(asymmetric.add_unit(_make_unit("a2")), "edge target adds")
	_check(not asymmetric.seal(), "asymmetric adjacency prevents seal")


func _make_catalog(reverse_insertion: bool) -> VNextTerritoryUnitCatalog:
	var definitions: Array[Dictionary] = [
		{"local_id": "a1", "neighbors": ["territory_unit:a2", "territory_unit:b1"]},
		{"local_id": "a2", "neighbors": ["territory_unit:a1", "territory_unit:b2"]},
		{"local_id": "b1", "neighbors": ["territory_unit:a1", "territory_unit:b2", "territory_unit:c1"]},
		{"local_id": "b2", "neighbors": ["territory_unit:a2", "territory_unit:b1", "territory_unit:c2"]},
		{"local_id": "c1", "neighbors": ["territory_unit:b1", "territory_unit:c2", "territory_unit:d1"]},
		{"local_id": "c2", "neighbors": ["territory_unit:b2", "territory_unit:c1", "territory_unit:d2"]},
		{"local_id": "d1", "neighbors": ["territory_unit:c1", "territory_unit:d2"]},
		{"local_id": "d2", "neighbors": ["territory_unit:c2", "territory_unit:d1"]},
	]
	if reverse_insertion:
		definitions.reverse()
	var catalog := VNextTerritoryUnitCatalog.new()
	if not catalog.configure(CATALOG_VERSION):
		return null
	for definition: Dictionary in definitions:
		var neighbors: Array = definition.get("neighbors", []) as Array
		if not catalog.add_unit(_make_unit(str(definition.get("local_id", "")), neighbors)):
			return null
	if not catalog.seal():
		return null
	return catalog


func _make_catalog_with_changed_geometry() -> VNextTerritoryUnitCatalog:
	var source: VNextTerritoryUnitCatalog = _make_catalog(false)
	if source == null:
		return null
	var catalog := VNextTerritoryUnitCatalog.new()
	if not catalog.configure(CATALOG_VERSION):
		return null
	for source_unit: VNextTerritoryUnit in source.units():
		var replacement := VNextTerritoryUnit.new()
		var geometry_ref: String = source_unit.geometry_ref()
		if source_unit.territory_unit_id() == "territory_unit:a1":
			geometry_ref += "-revised"
		if not replacement.configure(
			source_unit.territory_unit_id(),
			source_unit.catalog_version(),
			geometry_ref,
			source_unit.source_snapshot_ref(),
			source_unit.neighbor_ids()
		):
			return null
		if not catalog.add_unit(replacement):
			return null
	return catalog if catalog.seal() else null


func _make_unit(
	local_id: String,
	neighbors: Array = [],
	catalog_version: String = CATALOG_VERSION
) -> VNextTerritoryUnit:
	var unit := VNextTerritoryUnit.new()
	if not unit.configure(
		"territory_unit:" + local_id,
		catalog_version,
		"geometry://synthetic-grid/v1/" + local_id,
		SOURCE_SNAPSHOT_REF,
		neighbors
	):
		return null
	return unit


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
