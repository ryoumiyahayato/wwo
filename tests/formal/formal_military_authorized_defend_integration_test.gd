extends SceneTree

const PERSON_COMMANDER: String = "person:commander"
const PERSON_DELEGATE: String = "person:delegate"
const PERSON_OTHER: String = "person:other"
const PERSON_IDS: Array[String] = [PERSON_COMMANDER, PERSON_DELEGATE, PERSON_OTHER]
const PLACE_IDS: Array[String] = ["place:paris"]
const ARMY_ORG: String = "organization:army_test"
const OTHER_ORG: String = "organization:other_test"
const AUTHORITY_ID: String = "authority.army.commander.defend"
const FORMATION_A: String = "formation:authorized_a"
const FORMATION_B: String = "formation:authorized_b"
const DURATION_HOURS: int = 24

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_authorized_defend_and_owner_boundaries()
	_test_authority_denials_and_acting_context_isolation()
	_test_stale_appointment()
	_test_target_and_operation_isolation()
	_test_invalid_formation_domain_rejection()
	_test_delegation_and_revocation_domain_effect()
	_test_formal_round_trip_and_atomic_corruption()
	_test_previous_schema_empty_migration()
	print("Formal Military authorized DEFEND integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_authorized_defend_and_owner_boundaries() -> void:
	var world := _new_world()
	_check(world != null, "authorized fixture composes Formal world")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "exact DEFEND authority grant registers")
	_check(world.select_player_person(PERSON_COMMANDER), "Formal Player selects commander Person")
	var context := _commander_context()
	var before_world := world.get_persistent_state()
	var before_fingerprint := world.authoritative_fingerprint()
	var before_spatial := world._spatial_world.snapshot()
	var before_formation := world._military_state.get_formation(FORMATION_A).to_dict()
	var before_capacity_window := world._military_state.capacity_window_hour
	var before_link_capacity := world._military_state.link_capacity_used.duplicate(true)
	var before_link_queues := world._military_state.link_queues.duplicate(true)
	var before_battles := world._military_state.battle_results.duplicate(true)
	var result := world.player_defend_formation(context, FORMATION_A, DURATION_HOURS)
	_equal(
		str(result.get("status", "")),
		VNextMilitaryAuthorityBridge.RESULT_AUTHORIZED_AND_EXECUTED,
		"authorized exact DEFEND crosses Authority boundary and executes"
	)
	_equal(
		str(result.get("authority_status", "")),
		VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
		"direct domain-execution grant resolves through existing Authority semantics"
	)
	var domain_result: Dictionary = result.get("domain_result", {}) as Dictionary
	_check(bool(domain_result.get("success", false)), "existing MilitaryService.defend returns success")
	var action_id := str(domain_result.get("action_id", ""))
	_check(world._military_state.active_actions.has(action_id), "MilitaryState owns created DEFEND action")
	if world._military_state.active_actions.has(action_id):
		var action: Dictionary = world._military_state.active_actions[action_id] as Dictionary
		_equal(str(action.get("kind", "")), "defend", "exact Military action kind is DEFEND")
		_equal(str(action.get("formation_id", "")), FORMATION_A, "Military action targets exact authorized formation")
	var after_formation := world._military_state.get_formation(FORMATION_A).to_dict()
	_equal(str(after_formation.get("action_state", "")), VNextMilitaryFormation.ACTION_DEFENDING, "Military owns defensive action state")
	_check(float(after_formation.get("defense_posture", 1.0)) > 1.0, "Military owns defensive posture mutation")
	_equal(after_formation.get("current_city_id"), before_formation.get("current_city_id"), "DEFEND does not move formation")
	_equal(after_formation.get("personnel"), before_formation.get("personnel"), "DEFEND does not alter personnel")
	_equal(after_formation.get("equipment_sets"), before_formation.get("equipment_sets"), "DEFEND does not alter equipment")
	_equal(world._military_state.battle_results, before_battles, "DEFEND does not resolve battle")
	_equal(world._military_state.capacity_window_hour, before_capacity_window, "DEFEND does not open Military capacity window")
	_equal(world._military_state.link_capacity_used, before_link_capacity, "DEFEND does not reserve transport capacity")
	_equal(world._military_state.link_queues, before_link_queues, "DEFEND does not create transport queue entries")
	_equal(world._spatial_world.snapshot(), before_spatial, "authorized DEFEND makes zero Spatial mutation")
	var after_world := world.get_persistent_state()
	for key: String in [
		"historical_evidence",
		"runtime_politics",
		"markets",
		"economy",
		"persons",
		"player",
		"organization",
		"organization_authority",
	]:
		_equal(after_world.get(key), before_world.get(key), "authorized DEFEND leaves %s unchanged" % key)
	_check(after_world.get("military_state") != before_world.get("military_state"), "authorized DEFEND changes only Military-owned persistent state")
	_check(world.authoritative_fingerprint() != before_fingerprint, "authorized DEFEND changes Formal fingerprint deterministically")


func _test_authority_denials_and_acting_context_isolation() -> void:
	var no_authority := _new_world()
	_check(no_authority != null, "no-authority fixture composes")
	if no_authority == null:
		return
	_check(no_authority.select_player_person(PERSON_COMMANDER), "no-authority fixture selects commander")
	_assert_denied_without_military_mutation(no_authority, _commander_context(), FORMATION_A, "missing authority")

	var world := _new_world()
	_check(world != null, "ActingContext isolation fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "ActingContext isolation grant registers")

	_check(world.select_player_person(PERSON_OTHER), "wrong-Person fixture selects explicit other Formal Person")
	var wrong_person := VNextOrganizationAuthorityFoundation.acting_context(
		PERSON_OTHER, ARMY_ORG, ARMY_ORG, AUTHORITY_ID, "commander_primary"
	)
	_assert_denied_without_military_mutation(world, wrong_person, FORMATION_A, "wrong Person without appointment")

	_check(world.select_player_person(PERSON_COMMANDER), "wrong-organization fixture reselects commander")
	var wrong_acting_org := VNextOrganizationAuthorityFoundation.acting_context(
		PERSON_COMMANDER, OTHER_ORG, ARMY_ORG, AUTHORITY_ID, "alternate_commander"
	)
	_assert_denied_without_military_mutation(world, wrong_acting_org, FORMATION_A, "wrong acting organization")

	var wrong_represented_org := VNextOrganizationAuthorityFoundation.acting_context(
		PERSON_COMMANDER, ARMY_ORG, OTHER_ORG, AUTHORITY_ID, "commander_primary"
	)
	_assert_denied_without_military_mutation(world, wrong_represented_org, FORMATION_A, "wrong represented organization")


func _test_stale_appointment() -> void:
	var world := _new_world()
	_check(world != null, "stale Appointment fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "stale Appointment grant registers")
	_check(world._organization.remove_appointment(ARMY_ORG, "commander_primary"), "old commander Appointment ends")
	_check(
		world._organization.create_appointment(ARMY_ORG, "commander_delegate", PERSON_DELEGATE, "commander"),
		"replacement commander Appointment starts"
	)
	_check(world.select_player_person(PERSON_COMMANDER), "old holder remains selectable Formal Person")
	_assert_denied_without_military_mutation(world, _commander_context(), FORMATION_A, "stale commander Appointment")
	_check(world.select_player_person(PERSON_DELEGATE), "replacement holder selected as Formal Player")
	var new_holder := VNextOrganizationAuthorityFoundation.acting_context(
		PERSON_DELEGATE, ARMY_ORG, ARMY_ORG, AUTHORITY_ID, "commander_delegate"
	)
	var result := world.player_defend_formation(new_holder, FORMATION_A, DURATION_HOURS)
	_equal(str(result.get("status", "")), VNextMilitaryAuthorityBridge.RESULT_AUTHORIZED_AND_EXECUTED, "replacement Position holder exercises authority without Person-level power copy")


func _test_target_and_operation_isolation() -> void:
	var world := _new_world()
	_check(world != null, "target/operation isolation fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "target-isolated grant registers")
	_check(world.select_player_person(PERSON_COMMANDER), "target-isolation fixture selects commander")
	var formation_a := world._military_state.get_formation(FORMATION_A)
	var formation_b := world._military_state.get_formation(FORMATION_B)
	_equal(formation_a.country_id, formation_b.country_id, "target isolation fixture uses same country_id for A and B")
	_assert_denied_without_military_mutation(world, _commander_context(), FORMATION_B, "same-country unauthorized formation B")
	var before := world._military_state.snapshot()
	for operation: String in ["military.move", "military.deploy", "military.concentrate", "military.attack"]:
		var resolution := world._organization_authority.resolve_authority(
			_commander_context(),
			operation,
			VNextOrganizationAuthorityFoundation.STAGE_DOMAIN_EXECUTION,
			FORMATION_A
		)
		_check(
			str(resolution.get("status", "")) != VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED,
			"DEFEND grant does not authorize %s" % operation
		)
	_equal(world._military_state.snapshot(), before, "operation-isolation resolution performs zero Military mutation")
	_check(not world._military_authority_bridge.has_method("move"), "narrow bridge exposes no MOVE command")
	_check(not world._military_authority_bridge.has_method("attack"), "narrow bridge exposes no ATTACK command")


func _test_invalid_formation_domain_rejection() -> void:
	var world := _new_world()
	_check(world != null, "missing formation fixture composes")
	if world == null:
		return
	var missing_id := "formation:missing"
	_check(_add_defend_grant(world, [missing_id]), "authority may scope an exact structurally valid missing formation ID")
	_check(world.select_player_person(PERSON_COMMANDER), "missing formation fixture selects commander")
	var before := world._military_state.snapshot()
	var result := world.player_defend_formation(_commander_context(), missing_id, DURATION_HOURS)
	_equal(str(result.get("status", "")), VNextMilitaryAuthorityBridge.RESULT_DOMAIN_REJECTED, "authorized but nonexistent formation fails in Military domain")
	_equal(str(result.get("authority_status", "")), VNextOrganizationAuthorityFoundation.STATUS_AUTHORIZED, "missing Military fact does not retroactively change institutional authorization")
	_equal(world._military_state.snapshot(), before, "missing formation failure creates no placeholder and no Military mutation")


func _test_delegation_and_revocation_domain_effect() -> void:
	var world := _new_world()
	_check(world != null, "delegation domain-effect fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A], true), "delegable exact DEFEND authority registers")
	var delegation := {
		"delegation_id": "delegation.defend.delegate",
		"source_kind": "authority",
		"source_id": AUTHORITY_ID,
		"delegator_context": _commander_context(),
		"recipient_person_id": PERSON_DELEGATE,
		"target_scope": [FORMATION_A],
		"spatial_scope": [],
		"subject_scope": [],
		"amount_or_quantity_limit": -1.0,
		"valid_from": 0,
		"valid_until": 100,
		"redelegable": false,
		"revocable": true,
		"exclusive_or_concurrent": "concurrent",
		"revoked_at": -1,
	}
	_check(world._organization_authority.create_delegation(delegation), "scoped DEFEND delegation is created by source commander authority")
	var delegate_context := VNextOrganizationAuthorityFoundation.acting_context(
		PERSON_DELEGATE,
		ARMY_ORG,
		ARMY_ORG,
		AUTHORITY_ID,
		"",
		false,
		"",
		"delegation.defend.delegate"
	)
	_check(world.select_player_person(PERSON_DELEGATE), "delegation recipient selected as Formal Player")
	_assert_denied_without_military_mutation(world, delegate_context, FORMATION_B, "delegated target scope excludes formation B")
	var first := world.player_defend_formation(delegate_context, FORMATION_A, DURATION_HOURS)
	_equal(str(first.get("status", "")), VNextMilitaryAuthorityBridge.RESULT_AUTHORIZED_AND_EXECUTED, "active scoped delegation produces real DEFEND domain effect")
	var after_first := world._military_state.snapshot()
	_check(world._organization_authority.revoke_delegation("delegation.defend.delegate", 0), "DEFEND delegation revokes")
	var second := world.player_defend_formation(delegate_context, FORMATION_A, DURATION_HOURS)
	_equal(str(second.get("status", "")), VNextMilitaryAuthorityBridge.RESULT_AUTHORITY_DENIED, "revoked delegation blocks later DEFEND before Military domain")
	_equal(str(second.get("authority_status", "")), VNextOrganizationAuthorityFoundation.STATUS_DELEGATION_INVALID, "revocation uses existing Authority delegation semantics")
	_equal(world._military_state.snapshot(), after_first, "revoked second attempt causes zero additional Military mutation")


func _test_formal_round_trip_and_atomic_corruption() -> void:
	var source := _new_world()
	_check(source != null, "Formal round-trip fixture composes")
	if source == null:
		return
	_check(_composition_is_unique(source), "Formal composes one Authority and one Military command path over unique owners")
	_check(_add_defend_grant(source, [FORMATION_A]), "round-trip DEFEND grant registers")
	_check(source.select_player_person(PERSON_COMMANDER), "round-trip fixture selects commander")
	var executed := source.player_defend_formation(_commander_context(), FORMATION_A, DURATION_HOURS)
	_equal(str(executed.get("status", "")), VNextMilitaryAuthorityBridge.RESULT_AUTHORIZED_AND_EXECUTED, "round-trip fixture records authorized DEFEND")
	var saved := source.get_persistent_state()
	_check(saved.get("organization_authority") is Dictionary, "Formal snapshot contains Organization Authority owner snapshot")
	_check(saved.get("military_state") is Dictionary, "Formal snapshot contains MilitaryState owner snapshot")
	var source_fingerprint := source.authoritative_fingerprint()

	var restored := FormalWorldSimulation.new(null, PERSON_IDS, PLACE_IDS)
	_check(restored.initialize(), "fresh Formal restore target initializes")
	_check(restored.restore_persistent_state(saved), "Formal candidate-first restore accepts valid Authority + Military state")
	_equal(restored.authoritative_fingerprint(), source_fingerprint, "Formal fingerprint survives Authority + Military round trip")
	_equal(restored._organization_authority.state_fingerprint(), source._organization_authority.state_fingerprint(), "Authority owner fingerprint survives round trip")
	_equal(restored._military_state.state_fingerprint(), source._military_state.state_fingerprint(), "Military owner fingerprint survives round trip")
	_equal(restored.formal_person_ids(), source.formal_person_ids(), "same Formal Person identities survive round trip")
	_equal(restored.organization_view().organization_ids(), source.organization_view().organization_ids(), "same Organization identities survive round trip")
	var restored_formation := restored._military_state.get_formation(FORMATION_A)
	_check(restored_formation != null, "same formation identity survives round trip")
	if restored_formation != null:
		_equal(restored_formation.action_state, VNextMilitaryFormation.ACTION_DEFENDING, "restored formation retains DEFEND Military state")
	_equal(restored.get_persistent_state(), saved, "current Formal schema round trip is exact")

	var authority_corrupted := saved.duplicate(true)
	var authority_snapshot: Dictionary = authority_corrupted.get("organization_authority") as Dictionary
	var grants: Array = authority_snapshot.get("authority_grants", []) as Array
	if not grants.is_empty():
		grants.append((grants[0] as Dictionary).duplicate(true))
		_refresh_authority_fingerprint(authority_snapshot)
	_assert_formal_restore_rejected_atomic(restored, authority_corrupted, "semantically duplicate Authority grant")

	var military_corrupted := saved.duplicate(true)
	var military_snapshot: Dictionary = military_corrupted.get("military_state") as Dictionary
	var formations: Array = military_snapshot.get("formations", []) as Array
	if not formations.is_empty():
		formations.append((formations[0] as Dictionary).duplicate(true))
	_assert_formal_restore_rejected_atomic(restored, military_corrupted, "duplicate Military formation")


func _test_previous_schema_empty_migration() -> void:
	var source := _new_world()
	_check(source != null, "v6 migration source composes")
	if source == null:
		return
	var legacy := source.get_persistent_state()
	legacy["schema_id"] = FormalWorldSimulation.PREVIOUS_SCHEMA_ID
	legacy.erase("organization_authority")
	legacy.erase("military_state")
	var first := FormalWorldSimulation.new(null, PERSON_IDS, PLACE_IDS)
	var second := FormalWorldSimulation.new(null, PERSON_IDS, PLACE_IDS)
	_check(first.initialize() and second.initialize(), "v6 migration targets initialize")
	_check(first.restore_persistent_state(legacy), "v6 snapshot missing new domains migrates deterministically")
	_check(second.restore_persistent_state(legacy), "v6 empty-domain migration replays deterministically")
	_equal((first._organization_authority.snapshot().get("authority_grants", []) as Array).size(), 0, "v6 migration creates legal empty Authority state")
	_equal(first._military_state.get_sorted_formation_ids(), [], "v6 migration creates legal empty Military formation state")
	_equal(first._organization_authority.snapshot(), second._organization_authority.snapshot(), "migrated empty Authority state is deterministic")
	_equal(first._military_state.snapshot(), second._military_state.snapshot(), "migrated empty Military state is deterministic")


func _new_world() -> FormalWorldSimulation:
	var core := VNextOrganizationCore.create(PERSON_IDS, PLACE_IDS)
	if core == null:
		return null
	if not core.register_organization(ARMY_ORG, "military_institution", "place:paris"):
		return null
	if not core.register_organization(OTHER_ORG, "association", "place:paris"):
		return null
	if not core.define_position(ARMY_ORG, "commander", "Commander", 1):
		return null
	if not core.define_position(OTHER_ORG, "alternate", "Alternate", 1):
		return null
	for person_id: String in [PERSON_COMMANDER, PERSON_DELEGATE]:
		if not core.add_member(ARMY_ORG, person_id):
			return null
	if not core.add_member(OTHER_ORG, PERSON_COMMANDER):
		return null
	if not core.create_appointment(ARMY_ORG, "commander_primary", PERSON_COMMANDER, "commander"):
		return null
	if not core.create_appointment(OTHER_ORG, "alternate_commander", PERSON_COMMANDER, "alternate"):
		return null
	var world := FormalWorldSimulation.new(core, PERSON_IDS, PLACE_IDS)
	if not world.initialize():
		return null
	if not world._military_service.create_formation(
		world._military_state,
		world._military_map,
		FORMATION_A,
		"country_fra",
		"paris",
		5000,
		{"equipment_factor": 1.0},
		0.8,
		0.8,
		0.8
	):
		return null
	if not world._military_service.create_formation(
		world._military_state,
		world._military_map,
		FORMATION_B,
		"country_fra",
		"rouen",
		4500,
		{"equipment_factor": 1.0},
		0.8,
		0.8,
		0.8
	):
		return null
	return world


func _add_defend_grant(
	world: FormalWorldSimulation,
	target_scope: Array[String],
	delegable: bool = false
) -> bool:
	var stages: Array[String] = [VNextOrganizationAuthorityFoundation.STAGE_DOMAIN_EXECUTION]
	if delegable:
		stages.append(VNextOrganizationAuthorityFoundation.STAGE_DELEGATION)
	return world._organization_authority.add_authority_grant({
		"authority_id": AUTHORITY_ID,
		"holder": VNextOrganizationAuthorityFoundation.position_holder(ARMY_ORG, "commander"),
		"represented_entity": ARMY_ORG,
		"operation": VNextMilitaryAuthorityBridge.OPERATION_DEFEND,
		"target_scope": target_scope,
		"spatial_scope": [],
		"subject_scope": [],
		"amount_or_quantity_limit": -1.0,
		"valid_from": 0,
		"valid_until": -1,
		"basis": {"kind": "charter", "id": "basis.%s" % AUTHORITY_ID},
		"revocable": true,
		"delegable": delegable,
		"exclusive_or_concurrent": "concurrent",
		"additional_constraints": VNextOrganizationAuthorityFoundation.constraints(stages),
		"accountability": VNextOrganizationAuthorityFoundation.accountability(ARMY_ORG),
		"revoked_at": -1,
	})


func _commander_context() -> Dictionary:
	return VNextOrganizationAuthorityFoundation.acting_context(
		PERSON_COMMANDER,
		ARMY_ORG,
		ARMY_ORG,
		AUTHORITY_ID,
		"commander_primary"
	)


func _assert_denied_without_military_mutation(
	world: FormalWorldSimulation,
	context: Dictionary,
	formation_id: String,
	label: String
) -> void:
	var before := world._military_state.snapshot()
	var before_fingerprint := world._military_state.state_fingerprint()
	var result := world.player_defend_formation(context, formation_id, DURATION_HOURS)
	_equal(str(result.get("status", "")), VNextMilitaryAuthorityBridge.RESULT_AUTHORITY_DENIED, "%s is rejected by Authority" % label)
	_equal(world._military_state.snapshot(), before, "%s leaves Military snapshot unchanged" % label)
	_equal(world._military_state.state_fingerprint(), before_fingerprint, "%s leaves Military fingerprint unchanged" % label)


func _composition_is_unique(world: FormalWorldSimulation) -> bool:
	return (
		world._organization != null
		and world._organization_authority != null
		and world._military_state != null
		and world._military_service != null
		and world._military_authority_bridge != null
		and world._military_authority_bridge._authority == world._organization_authority
		and world._military_authority_bridge._military_state == world._military_state
		and world._military_authority_bridge._military_service == world._military_service
		and world._military_authority_bridge._military_map == world._military_map
	)


func _refresh_authority_fingerprint(snapshot_value: Dictionary) -> void:
	snapshot_value["state_fingerprint"] = JSON.stringify({
		"schema_id": str(snapshot_value.get("schema_id", "")),
		"structure_fingerprint": str(snapshot_value.get("structure_fingerprint", "")),
		"reference_fingerprint": str(snapshot_value.get("reference_fingerprint", "")),
		"state": {
			"revision": int(snapshot_value.get("revision", 0)),
			"authority_grants": snapshot_value.get("authority_grants", []),
			"decision_bodies": snapshot_value.get("decision_bodies", []),
			"procedures": snapshot_value.get("procedures", []),
			"proposals": snapshot_value.get("proposals", []),
			"delegations": snapshot_value.get("delegations", []),
			"power_relations": snapshot_value.get("power_relations", []),
			"power_transfers": snapshot_value.get("power_transfers", []),
		},
	}).sha256_text()


func _assert_formal_restore_rejected_atomic(
	world: FormalWorldSimulation,
	rejected: Dictionary,
	label: String
) -> void:
	var before := world.get_persistent_state()
	var before_fingerprint := world.authoritative_fingerprint()
	_check(not world.restore_persistent_state(rejected), "%s fails Formal restore closed" % label)
	_equal(world.get_persistent_state(), before, "%s preserves all live Formal state" % label)
	_equal(world.authoritative_fingerprint(), before_fingerprint, "%s preserves whole-world fingerprint" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
