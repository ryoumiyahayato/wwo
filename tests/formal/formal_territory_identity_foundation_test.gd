extends SceneTree
## Formal production-composition gate for immutable TerritoryUnit identity.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_formal_territory_identity_composition()
	print("Formal Territory identity foundation: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("FORMAL_TERRITORY_IDENTITY_FOUNDATION_COMPLETE=1")
	quit(0)


func _test_formal_territory_identity_composition() -> void:
	var first := FormalWorldSimulation.new()
	var second := FormalWorldSimulation.new()
	_check(first.initialize(), "first Formal world initializes with production TerritoryUnit identity")
	_check(second.initialize(), "second Formal world initializes with production TerritoryUnit identity")
	if not first.initialized or not second.initialized:
		return
	_check(
		FormalWorldSimulation.TERRITORY_UNIT_CATALOG_PRODUCTION_COMPOSED,
		"Formal production explicitly composes the immutable TerritoryUnit catalog"
	)
	_check(
		not FormalWorldSimulation.TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED,
		"TerritorialControlLedger remains uncomposed and cannot duplicate controller ownership"
	)
	_equal(
		FormalWorldSimulation.TERRITORIAL_CONTROL_OWNER,
		"VNextSpatialWorld",
		"current writable territorial-control owner remains SpatialWorld"
	)
	_check(
		FormalWorldSimulation.TERRITORY_AUTHORITY_PRODUCTION_STATUS.contains(
			"TERRITORY_UNIT_CATALOG_PRODUCTION_IDENTITY_ONLY"
		),
		"production status distinguishes immutable identity from mutable territorial control"
	)
	_equal(first.territory_unit_count(), 151, "Formal world exposes all source-backed TerritoryUnits")
	_equal(
		first.territory_unit_id_for_political_unit("united_states_1900"),
		"territory_unit:gw_2",
		"Formal crosswalk resolves source political identity without aliasing it as Territory identity"
	)
	var binding := first.territory_unit_catalog_binding()
	_check(binding.size() == 2, "Formal production exposes exact catalog version/fingerprint binding")
	_check(not first.territory_unit_catalog_fingerprint().is_empty(), "Formal Territory catalog fingerprint exists")
	_equal(
		first.territory_unit_catalog_fingerprint(),
		second.territory_unit_catalog_fingerprint(),
		"Formal Territory catalog fingerprint is deterministic across worlds"
	)
	var state := first.get_persistent_state()
	_check(
		not state.has("territory_unit_catalog"),
		"immutable Territory identity is rebound from source rather than duplicated into mutable save state"
	)
	_check(
		not state.has("territorial_control_ledger"),
		"Formal save still contains no second territorial-control ledger"
	)
	_check(not first.authoritative_fingerprint().is_empty(), "Formal authoritative fingerprint remains valid")
	_equal(
		first.authoritative_fingerprint(),
		second.authoritative_fingerprint(),
		"identical production Territory identity yields deterministic Formal fingerprint"
	)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
