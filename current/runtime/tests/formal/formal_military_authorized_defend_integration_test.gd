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
	_test_previous_schema_empty_rejection()
	print("Formal Military authorized DEFEND integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_authorized_defend_and_owner_boundaries() -> void:
	var world := _new_world()
	_check(world != null, "authorized fixture composes Formal world")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "exact DEFEND authority grant registers")
	_check(world.world.player_state.set_player_id(PERSON_COMMANDER), "Formal Player selects commander Person")
	var context := _commander_context()
	var before_world := world.persistence.snapshot()
	var before_fingerprint := world.persistence.authoritative_fingerprint()
	var before_spatial := world.world.spatial_world.snapshot()
	var before_formation := world.world.military_state.get_formation(FORMATION_A).to_dict()
	var before_capacity_window := world.world.military_state.capacity_window_hour
	var before_link_capacity := world.world.military_state.link_capacity_used.duplicate(true)
	var before_link_queues := world.world.military_state.link_queues.duplicate(true)
	var before_battles := world.world.military_state.battle_results.duplicate(true)
	var result := DefendAction.execute(context, FORMATION_A, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(
		str(result.get("status", "")),
		DefendAction.RESULT_EXECUTED,
		"authorized exact DEFEND crosses Authority boundary and executes"
	)
	_equal(
		str((result.get("authorization", {}) as Dictionary).get("status", "")),
		AuthorizationCheck.ALLOWED,
		"direct domain-execution grant resolves through existing Authority semantics"
	)
	var domain_result: Dictionary = result.get("domain_result", {}) as Dictionary
	_check(bool(domain_result.get("success", false)), "existing MilitaryService.defend returns success")
	var action_id := str(domain_result.get("action_id", ""))
	_check(world.world.military_state.active_actions.has(action_id), "MilitaryState owns created DEFEND action")
	if world.world.military_state.active_actions.has(action_id):
		var action: Dictionary = world.world.military_state.active_actions[action_id] as Dictionary
		_equal(str(action.get("kind", "")), "defend", "exact Military action kind is DEFEND")
		_equal(str(action.get("formation_id", "")), FORMATION_A, "Military action targets exact authorized formation")
	var after_formation := world.world.military_state.get_formation(FORMATION_A).to_dict()
	_equal(str(after_formation.get("action_state", "")), VNextMilitaryFormation.ACTION_DEFENDING, "Military owns defensive action state")
	_check(float(after_formation.get("defense_posture", 1.0)) > 1.0, "Military owns defensive posture mutation")
	_equal(after_formation.get("current_city_id"), before_formation.get("current_city_id"), "DEFEND does not move formation")
	_equal(after_formation.get("personnel"), before_formation.get("personnel"), "DEFEND does not alter personnel")
	_equal(after_formation.get("equipment_sets"), before_formation.get("equipment_sets"), "DEFEND does not alter equipment")
	_equal(world.world.military_state.battle_results, before_battles, "DEFEND does not resolve battle")
	_equal(world.world.military_state.capacity_window_hour, before_capacity_window, "DEFEND does not open Military capacity window")
	_equal(world.world.military_state.link_capacity_used, before_link_capacity, "DEFEND does not reserve transport capacity")
	_equal(world.world.military_state.link_queues, before_link_queues, "DEFEND does not create transport queue entries")
	_equal(world.world.spatial_world.snapshot(), before_spatial, "authorized DEFEND makes zero Spatial mutation")
	var after_world := world.persistence.snapshot()
	for key: String in [
		"historical_evidence",
		"runtime_politics",
		"markets",
		"economy",
		"persons",
		"player",
		"organization",
		"organization",
	]:
		_equal(after_world.get(key), before_world.get(key), "authorized DEFEND leaves %s unchanged" % key)
	_check(after_world.get("military_state") != before_world.get("military_state"), "authorized DEFEND changes only Military-owned persistent state")
	_check(world.persistence.authoritative_fingerprint() != before_fingerprint, "authorized DEFEND changes Formal fingerprint deterministically")


func _test_authority_denials_and_acting_context_isolation() -> void:
	var no_authority := _new_world()
	_check(no_authority != null, "no-authority fixture composes")
	if no_authority == null:
		return
	_check(no_authority.world.player_state.set_player_id(PERSON_COMMANDER), "no-authority fixture selects commander")
	var ungranted := _commander_context()
	ungranted["authority_basis"] = ""
	_assert_denied_without_military_mutation(no_authority, ungranted, FORMATION_A, "missing authority")

	var world := _new_world()
	_check(world != null, "ActingContext isolation fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "ActingContext isolation grant registers")

	_check(world.world.player_state.set_player_id(PERSON_OTHER), "wrong-Person fixture selects explicit other Formal Person")
	var wrong_person := OrganizationState.acting_context(
		PERSON_OTHER, ARMY_ORG, ARMY_ORG, AUTHORITY_ID, "commander_primary"
	)
	_assert_denied_without_military_mutation(world, wrong_person, FORMATION_A, "wrong Person without appointment")

	_check(world.world.player_state.set_player_id(PERSON_COMMANDER), "wrong-organization fixture reselects commander")
	var wrong_acting_org := OrganizationState.acting_context(
		PERSON_COMMANDER, OTHER_ORG, ARMY_ORG, AUTHORITY_ID, "alternate_commander"
	)
	_assert_denied_without_military_mutation(world, wrong_acting_org, FORMATION_A, "wrong acting organization")

	var wrong_represented_org := OrganizationState.acting_context(
		PERSON_COMMANDER, ARMY_ORG, OTHER_ORG, AUTHORITY_ID, "commander_primary"
	)
	_assert_denied_without_military_mutation(world, wrong_represented_org, FORMATION_A, "wrong represented organization")


func _test_stale_appointment() -> void:
	var world := _new_world()
	_check(world != null, "stale Appointment fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "stale Appointment grant registers")
	_check(world.world.organization_state.remove_appointment(ARMY_ORG, "commander_primary"), "old commander Appointment ends")
	_check(
		world.world.organization_state.create_appointment(ARMY_ORG, "commander_delegate", PERSON_DELEGATE, "commander"),
		"replacement commander Appointment starts"
	)
	_check(world.world.player_state.set_player_id(PERSON_COMMANDER), "old holder remains selectable Formal Person")
	var before_stale := world.world.military_state.snapshot()
	var stale := DefendAction.execute(_commander_context(), FORMATION_A, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(str(stale["status"]), DefendAction.RESULT_ERROR, "unknown appointment reference produces explicit error")
	_equal(world.world.military_state.snapshot(), before_stale, "invalid appointment does not mutate military state")
	_check(world.world.player_state.set_player_id(PERSON_DELEGATE), "replacement holder selected as Formal Player")
	var new_holder := OrganizationState.acting_context(
		PERSON_DELEGATE, ARMY_ORG, ARMY_ORG, AUTHORITY_ID, "commander_delegate"
	)
	var result := DefendAction.execute(new_holder, FORMATION_A, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(str(result.get("status", "")), DefendAction.RESULT_EXECUTED, "replacement Position holder exercises authority without Person-level power copy")


func _test_target_and_operation_isolation() -> void:
	var world := _new_world()
	_check(world != null, "target/operation isolation fixture composes")
	if world == null:
		return
	_check(_add_defend_grant(world, [FORMATION_A]), "target-isolated grant registers")
	_check(world.world.player_state.set_player_id(PERSON_COMMANDER), "target-isolation fixture selects commander")
	var formation_a := world.world.military_state.get_formation(FORMATION_A)
	var formation_b := world.world.military_state.get_formation(FORMATION_B)
	_equal(formation_a.affiliation_id, formation_b.affiliation_id, "target isolation fixture uses same affiliation_id for A and B")
	_assert_denied_without_military_mutation(world, _commander_context(), FORMATION_B, "same-country unauthorized formation B")
	var before := world.world.military_state.snapshot()
	for operation: String in ["military.move", "military.deploy", "military.concentrate", "military.attack"]:
		var resolution := world.world.authorization_check.resolve_authority(
			_commander_context(),
			operation,
			AuthorizationCheck.STAGE_DOMAIN_EXECUTION,
			FORMATION_A
		)
		_check(
			str(resolution.get("status", "")) != AuthorizationCheck.ALLOWED,
			"DEFEND grant does not authorize %s" % operation
		)
	_equal(world.world.military_state.snapshot(), before, "operation-isolation resolution performs zero Military mutation")
	_check(not DefendAction.new().has_method("move"), "narrow bridge exposes no MOVE command")
	_check(not DefendAction.new().has_method("attack"), "narrow bridge exposes no ATTACK command")


func _test_invalid_formation_domain_rejection() -> void:
	var world := _new_world()
	_check(world != null, "missing formation fixture composes")
	if world == null:
		return
	var missing_id := "formation:missing"
	_check(_add_defend_grant(world, [missing_id]), "authority may scope an exact structurally valid missing formation ID")
	_check(world.world.player_state.set_player_id(PERSON_COMMANDER), "missing formation fixture selects commander")
	var before := world.world.military_state.snapshot()
	var result := DefendAction.execute(_commander_context(), missing_id, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(str(result.get("status", "")), DefendAction.RESULT_ERROR, "unknown formation produces explicit structural error")
	_equal(str((result.get("authorization", {}) as Dictionary).get("status", "")), "", "malformed formation never reaches authorization")
	_equal(world.world.military_state.snapshot(), before, "missing formation failure creates no placeholder and no Military mutation")


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
	_check((str(world.world.authorization_check.check_delegation(delegation)["status"]) == AuthorizationCheck.ALLOWED and world.world.organization_state.record_delegation(delegation)), "scoped DEFEND delegation is created by source commander authority")
	var delegate_context := OrganizationState.acting_context(
		PERSON_DELEGATE,
		ARMY_ORG,
		ARMY_ORG,
		AUTHORITY_ID,
		"",
		false,
		"",
		"delegation.defend.delegate"
	)
	_check(world.world.player_state.set_player_id(PERSON_DELEGATE), "delegation recipient selected as Formal Player")
	_assert_denied_without_military_mutation(world, delegate_context, FORMATION_B, "delegated target scope excludes formation B")
	var first := DefendAction.execute(delegate_context, FORMATION_A, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(str(first.get("status", "")), DefendAction.RESULT_EXECUTED, "active scoped delegation produces real DEFEND domain effect")
	var after_first := world.world.military_state.snapshot()
	_check(world.world.organization_state.revoke_delegation("delegation.defend.delegate", 0), "DEFEND delegation revokes")
	var second := DefendAction.execute(delegate_context, FORMATION_A, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(str(second.get("status", "")), DefendAction.RESULT_DENIED, "revoked delegation blocks later DEFEND before Military domain")
	_equal(str((second.get("authorization", {}) as Dictionary).get("reason", "")), AuthorizationCheck.REASON_DELEGATION_INVALID, "revocation uses existing Authority delegation semantics")
	_equal(world.world.military_state.snapshot(), after_first, "revoked second attempt causes zero additional Military mutation")


func _test_formal_round_trip_and_atomic_corruption() -> void:
	var source := _new_world()
	_check(source != null, "Formal round-trip fixture composes")
	if source == null:
		return
	_check(_composition_is_unique(source), "Formal composes one Authority and one Military command path over unique owners")
	_check(_add_defend_grant(source, [FORMATION_A]), "round-trip DEFEND grant registers")
	_check(source.world.player_state.set_player_id(PERSON_COMMANDER), "round-trip fixture selects commander")
	var executed := DefendAction.execute(_commander_context(), FORMATION_A, DURATION_HOURS, source.world.game_clock.current_hour(), source.world.player_state, source.world.person_overlay, source.world.authorization_check, source.world.military_state, source.world.military_service, source.world.military_map)
	_equal(str(executed.get("status", "")), DefendAction.RESULT_EXECUTED, "round-trip fixture records authorized DEFEND")
	var saved := source.persistence.snapshot()
	_check(saved.get("organization") is Dictionary, "Formal snapshot contains Organization Authority owner snapshot")
	_check(saved.get("military_state") is Dictionary, "Formal snapshot contains MilitaryState owner snapshot")
	var source_fingerprint := source.persistence.authoritative_fingerprint()

	var restored := WorldBootstrap.new().build(null, PERSON_IDS, PLACE_IDS)
	_check(restored.success, "fresh Formal restore target initializes")
	var candidate_1 := restored.persistence.restore_candidate(saved)
	if candidate_1.success:
		restored = candidate_1
	_check(candidate_1.success, "Formal candidate-first restore accepts valid Authority + Military state")
	_equal(restored.persistence.authoritative_fingerprint(), source_fingerprint, "Formal fingerprint survives Authority + Military round trip")
	_equal(restored.world.organization_state.state_fingerprint(), source.world.organization_state.state_fingerprint(), "Authority owner fingerprint survives round trip")
	_equal(restored.world.military_state.state_fingerprint(), source.world.military_state.state_fingerprint(), "Military owner fingerprint survives round trip")
	_equal(restored.world.person_overlay.person_ids(), source.world.person_overlay.person_ids(), "same Formal Person identities survive round trip")
	_equal(FormalWorldOrganizationView.new(restored.world.organization_state.snapshot()).organization_ids(), FormalWorldOrganizationView.new(source.world.organization_state.snapshot()).organization_ids(), "same Organization identities survive round trip")
	var restored_formation := restored.world.military_state.get_formation(FORMATION_A)
	_check(restored_formation != null, "same formation identity survives round trip")
	if restored_formation != null:
		_equal(restored_formation.action_state, VNextMilitaryFormation.ACTION_DEFENDING, "restored formation retains DEFEND Military state")
	_equal(restored.persistence.snapshot(), saved, "current Formal schema round trip is exact")

	var authority_corrupted := saved.duplicate(true)
	var authority_snapshot: Dictionary = authority_corrupted.get("organization") as Dictionary
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


func _test_previous_schema_empty_rejection() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v6"
	var candidate_2 := world.persistence.restore_candidate(old)
	if candidate_2.success:
		world = candidate_2
	_check(not candidate_2.success, "v6 save format is rejected")
	_check(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_check(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _new_world() -> WorldBuildResult:
	var core := OrganizationState.create(PERSON_IDS, PLACE_IDS)
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
	var world := WorldBootstrap.new().build(core, PERSON_IDS, PLACE_IDS)
	if not world.success:
		return null
	if not world.world.military_service.create_formation(
		world.world.military_state,
		world.world.military_map,
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
	if not world.world.military_service.create_formation(
		world.world.military_state,
		world.world.military_map,
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
	world: WorldBuildResult,
	target_scope: Array[String],
	delegable: bool = false
) -> bool:
	var stages: Array[String] = [AuthorizationCheck.STAGE_DOMAIN_EXECUTION]
	if delegable:
		stages.append(AuthorizationCheck.STAGE_DELEGATION)
	return world.world.organization_state.add_authority_grant({
		"authority_id": AUTHORITY_ID,
		"holder": OrganizationState.position_holder(ARMY_ORG, "commander"),
		"represented_entity": ARMY_ORG,
		"operation": DefendAction.OPERATION_DEFEND,
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
		"additional_constraints": OrganizationState.constraints(stages),
		"accountability": OrganizationState.accountability(ARMY_ORG),
		"revoked_at": -1,
	})


func _commander_context() -> Dictionary:
	return OrganizationState.acting_context(
		PERSON_COMMANDER,
		ARMY_ORG,
		ARMY_ORG,
		AUTHORITY_ID,
		"commander_primary"
	)


func _assert_denied_without_military_mutation(
	world: WorldBuildResult,
	context: Dictionary,
	formation_id: String,
	label: String
) -> void:
	var before := world.world.military_state.snapshot()
	var before_fingerprint := world.world.military_state.state_fingerprint()
	var result := DefendAction.execute(context, formation_id, DURATION_HOURS, world.world.game_clock.current_hour(), world.world.player_state, world.world.person_overlay, world.world.authorization_check, world.world.military_state, world.world.military_service, world.world.military_map)
	_equal(str(result.get("status", "")), DefendAction.RESULT_DENIED, "%s is rejected by Authority" % label)
	_equal(world.world.military_state.snapshot(), before, "%s leaves Military snapshot unchanged" % label)
	_equal(world.world.military_state.state_fingerprint(), before_fingerprint, "%s leaves Military fingerprint unchanged" % label)


func _composition_is_unique(world: WorldBuildResult) -> bool:
	return (world.world.organization_state != null and world.world.authorization_check != null
		and world.world.authorization_check._state == world.world.organization_state
		and world.world.military_state != null and world.world.military_service != null)


func _refresh_authority_fingerprint(snapshot_value: Dictionary) -> void:
	var payload := snapshot_value.duplicate(true)
	payload.erase("state_fingerprint")
	snapshot_value["state_fingerprint"] = JSON.stringify(payload).sha256_text()


func _assert_formal_restore_rejected_atomic(
	world: WorldBuildResult,
	rejected: Dictionary,
	label: String
) -> void:
	var before := world.persistence.snapshot()
	var before_fingerprint := world.persistence.authoritative_fingerprint()
	var candidate_3 := world.persistence.restore_candidate(rejected)
	if candidate_3.success:
		world = candidate_3
	_check(not candidate_3.success, "%s fails Formal restore closed" % label)
	_equal(world.persistence.snapshot(), before, "%s preserves all live Formal state" % label)
	_equal(world.persistence.authoritative_fingerprint(), before_fingerprint, "%s preserves whole-world fingerprint" % label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
