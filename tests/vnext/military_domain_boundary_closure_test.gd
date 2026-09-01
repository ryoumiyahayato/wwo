extends SceneTree

const UNIT_ORGANIZATION_ID: String = "organization:test_military"

var checks: int = 0
var failures: int = 0
var service := VNextMilitaryService.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_authority_seams_and_control_claim()
	_test_snapshot_boundary_and_atomic_restore()
	_test_deterministic_battle_restore()
	print("VNext Military domain boundary closure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_authority_seams_and_control_claim() -> void:
	var fixture := _battle_fixture()
	var spatial: VNextSpatialWorld = fixture.get("spatial") as VNextSpatialWorld
	var map: VNextMilitaryMapAdapter = fixture.get("map") as VNextMilitaryMapAdapter
	var state: VNextMilitaryState = fixture.get("state") as VNextMilitaryState
	_check(spatial != null and map != null and state != null, "battle boundary fixture initializes")
	if spatial == null or map == null or state == null:
		return
	var formation := state.get_formation("formation:boundary_attacker")
	var order := _order_authorization(formation, 0, UNIT_ORGANIZATION_ID)
	var sequence_before := state.next_action_sequence
	_check(not bool(service.attack(state, map, formation.formation_id, "lille", 0, null, order).get("success", false)), "missing Political war authorization is rejected")
	var wrong_war := _war_authorization("country_fra", "german_empire", 0)
	_check(not bool(service.attack(state, map, formation.formation_id, "lille", 0, wrong_war, order).get("success", false)), "wrong-opponent Political authorization is rejected")
	var future_war := _war_authorization("country_fra", "country_bel", 1)
	_check(not bool(service.attack(state, map, formation.formation_id, "lille", 0, future_war, order).get("success", false)), "out-of-window Political authorization is rejected")
	var valid_war := _war_authorization("country_fra", "country_bel", 0)
	var wrong_order := _order_authorization(formation, 0, "organization:wrong_military")
	_check(not bool(service.attack(state, map, formation.formation_id, "lille", 0, valid_war, wrong_order).get("success", false)), "wrong Organization authorization is rejected")
	_check(state.next_action_sequence == sequence_before and formation.action_state == VNextMilitaryFormation.ACTION_IDLE, "rejected authority checks are atomic")

	var sovereign_before := str(spatial.get_territorial_facts("northern_industrial_belt").get("sovereign_owner_id", ""))
	var accepted := service.attack(state, map, formation.formation_id, "lille", 0, valid_war, order)
	_check(bool(accepted.get("success", false)), "valid Political and Organization authorizations permit the existing attack calculation")
	_finish(state, map, str(accepted.get("action_id", "")), 600)
	_check(not state.battle_results.is_empty(), "authorized battle resolves")
	if state.battle_results.is_empty():
		return
	var battle: Dictionary = state.battle_results.back() as Dictionary
	var claim: Dictionary = battle.get("control_claim", {}) as Dictionary
	_check(str(battle.get("outcome", "")) == "attacker_win" and not claim.is_empty(), "existing decisive battle produces a control claim")
	var facts_before_claim := spatial.get_territorial_facts("northern_industrial_belt")
	_check(str(facts_before_claim.get("military_controller_id", "")) == "country_bel", "Military battle cannot create territorial control")
	_check(str(facts_before_claim.get("sovereign_owner_id", "")) == sovereign_before, "Military battle cannot modify sovereignty")
	_check(spatial.apply_military_control_claim(claim), "Spatial validates and commits the candidate controller outcome")
	var facts_after_claim := spatial.get_territorial_facts("northern_industrial_belt")
	_check(str(facts_after_claim.get("military_controller_id", "")) == "country_fra", "Spatial is the sole controller owner")
	_check(str(facts_after_claim.get("sovereign_owner_id", "")) == sovereign_before, "Spatial claim application preserves sovereignty")
	_check(not spatial.apply_military_control_claim(claim), "a stale claim cannot create a duplicate controller transition")


func _test_snapshot_boundary_and_atomic_restore() -> void:
	var fixture := _fixture()
	var map: VNextMilitaryMapAdapter = fixture.get("map") as VNextMilitaryMapAdapter
	var state: VNextMilitaryState = fixture.get("state") as VNextMilitaryState
	_check(map != null and state != null, "snapshot boundary fixture initializes")
	if map == null or state == null:
		return
	_check(not service.create_formation(state, map, "formation:no_org", "country_fra", "paris", 1000), "formation creation requires an Organization identity seam")
	_check(service.create_formation(state, map, "formation:snapshot", "country_fra", "paris", 1000, {"equipment_factor": 1.0}, 0.8, 0.8, 0.8, {}, UNIT_ORGANIZATION_ID), "formation uses an external Organization stable ID")
	_check(service.set_external_supply_allocation(state, map, "paris_basin", {"food": 100.0, "ammunition": 100.0, "equipment": 100.0, "transport_capacity": 100.0}), "external supply allocation is accepted as runtime context")
	var snapshot_value := state.snapshot()
	for forbidden_field: String in [
		"region_controls",
		"control_history",
		"supply_inputs",
		"external_supply_allocations",
		"link_capacity_used",
		"link_queues",
		"regional_production",
		"economy_inventory",
		"population_pool",
		"transport_network_capacity",
	]:
		_check(not snapshot_value.has(forbidden_field), "Military snapshot excludes external truth: %s" % forbidden_field)
	var formation_snapshot: Dictionary = (snapshot_value.get("formations", []) as Array)[0] as Dictionary
	_check(str(formation_snapshot.get("unit_organization_id", "")) == UNIT_ORGANIZATION_ID, "formation persists only its Organization identity reference")
	_check(not formation_snapshot.has("parent_formation_id"), "formation does not model an Organization hierarchy")

	var restored := VNextMilitaryState.new()
	_check(restored.restore(snapshot_value, map, map.get_spatial_world()), "boundary-clean Military snapshot restores")
	_check(restored.snapshot() == snapshot_value, "boundary-clean restore is deterministic")
	_check(restored.external_supply_allocations().is_empty(), "external Economy allocation is not restored as Military truth")

	var sentinel_fixture := _fixture()
	var sentinel_map: VNextMilitaryMapAdapter = sentinel_fixture.get("map") as VNextMilitaryMapAdapter
	var sentinel: VNextMilitaryState = sentinel_fixture.get("state") as VNextMilitaryState
	_check(service.create_formation(sentinel, sentinel_map, "formation:sentinel", "country_fra", "paris", 500, {"equipment_factor": 1.0}, 0.8, 0.8, 0.8, {}, UNIT_ORGANIZATION_ID), "atomic restore sentinel initializes")
	var sentinel_before := sentinel.snapshot()
	var polluted := snapshot_value.duplicate(true)
	polluted["region_controls"] = {"northern_industrial_belt": "country_fra"}
	_check(not sentinel.restore(polluted, sentinel_map, sentinel_map.get_spatial_world()) and sentinel.snapshot() == sentinel_before, "polluted Military restore rejects atomically")


func _test_deterministic_battle_restore() -> void:
	var left := _battle_fixture()
	var right := _battle_fixture()
	var left_state: VNextMilitaryState = left.get("state") as VNextMilitaryState
	var right_state: VNextMilitaryState = right.get("state") as VNextMilitaryState
	var left_map: VNextMilitaryMapAdapter = left.get("map") as VNextMilitaryMapAdapter
	var right_map: VNextMilitaryMapAdapter = right.get("map") as VNextMilitaryMapAdapter
	_check(left_state != null and right_state != null and left_map != null and right_map != null, "deterministic battle fixtures initialize")
	if left_state == null or right_state == null or left_map == null or right_map == null:
		return
	var left_formation := left_state.get_formation("formation:boundary_attacker")
	var right_formation := right_state.get_formation("formation:boundary_attacker")
	var left_attack := service.attack(left_state, left_map, left_formation.formation_id, "lille", 0, _war_authorization("country_fra", "country_bel", 0), _order_authorization(left_formation, 0, UNIT_ORGANIZATION_ID))
	var right_attack := service.attack(right_state, right_map, right_formation.formation_id, "lille", 0, _war_authorization("country_fra", "country_bel", 0), _order_authorization(right_formation, 0, UNIT_ORGANIZATION_ID))
	_check(bool(left_attack.get("success", false)) and bool(right_attack.get("success", false)), "twin authorized battles start")
	_finish(left_state, left_map, str(left_attack.get("action_id", "")), 600)
	_finish(right_state, right_map, str(right_attack.get("action_id", "")), 600)
	_check(left_state.battle_results == right_state.battle_results, "existing battle power, losses, and outcome remain deterministic")
	_check(left_state.snapshot() == right_state.snapshot(), "Military battle snapshots are deterministic")
	var restored := VNextMilitaryState.new()
	var snapshot_value := left_state.snapshot()
	_check(restored.restore(snapshot_value, left_map, left_map.get_spatial_world()), "resolved battle snapshot restores")
	_check(restored.snapshot() == snapshot_value, "resolved battle restore is exact")


func _fixture() -> Dictionary:
	var spatial := VNextSpatialWorld.create_from_legacy_world_map()
	var map := VNextMilitaryMapAdapter.new()
	if spatial == null or not spatial.is_valid() or not map.load_existing_map(spatial):
		return {}
	var state := VNextMilitaryState.new()
	if not state.initialize(map):
		return {}
	return {"spatial": spatial, "map": map, "state": state}


func _battle_fixture() -> Dictionary:
	var fixture := _fixture()
	var spatial: VNextSpatialWorld = fixture.get("spatial") as VNextSpatialWorld
	var map: VNextMilitaryMapAdapter = fixture.get("map") as VNextMilitaryMapAdapter
	var state: VNextMilitaryState = fixture.get("state") as VNextMilitaryState
	if spatial == null or map == null or state == null:
		return {}
	if not spatial.set_military_controller("northern_industrial_belt", "country_bel"):
		return {}
	if not service.create_formation(state, map, "formation:boundary_attacker", "country_fra", "paris", 50000, {"equipment_factor": 1.0}, 0.9, 0.9, 0.9, {}, UNIT_ORGANIZATION_ID):
		return {}
	if not service.create_formation(state, map, "formation:boundary_defender", "country_bel", "lille", 1500, {"equipment_factor": 1.0}, 0.8, 0.8, 0.8, {}, UNIT_ORGANIZATION_ID):
		return {}
	service.defend(state, map, "formation:boundary_defender", 0, 600)
	return fixture


func _war_authorization(attacker_country_id: String, opponent_country_id: String, from_hour: int) -> VNextPoliticalWarAuthorization:
	var authorization := VNextPoliticalWarAuthorization.new()
	if not authorization.configure("event:test_war_boundary", "state:test_authority", attacker_country_id, [opponent_country_id], from_hour, from_hour + 1000):
		return null
	return authorization


func _order_authorization(formation: VNextMilitaryFormation, from_hour: int, organization_id: String) -> VNextMilitaryOrderAuthorization:
	var authorization := VNextMilitaryOrderAuthorization.new()
	if formation == null or not authorization.configure("event:test_order_boundary", organization_id, formation.formation_id, from_hour, from_hour + 1000):
		return null
	return authorization


func _finish(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, action_id: String, maximum_hours: int) -> void:
	var deadline := state.last_simulated_hour + maximum_hours
	while state.active_actions.has(action_id) and state.last_simulated_hour < deadline:
		if not bool(service.advance_to_hour(state, map, state.last_simulated_hour + 1).get("success", false)):
			break
	_check(not state.active_actions.has(action_id), "authorized battle completes within bounded horizon")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)
