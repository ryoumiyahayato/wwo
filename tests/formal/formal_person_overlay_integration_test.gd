extends SceneTree

const EXPLICIT_PERSON_IDS: Array[String] = ["person:alice", "person:bob"]
const EXPLICIT_PLACE_IDS: Array[String] = ["place:capital", "place:branch"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_ordinary_formal_composition()
	_test_current_schema_round_trip()
	_test_reset_world()
	_test_v5_format_rejection()
	_test_v5_nonempty_organization_format_rejection()
	_test_source_boundaries()
	print("Formal person overlay integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_ordinary_formal_composition() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "ordinary WorldBuildResult initializes with Person overlay: %s" % world.error)
	if not world.success:
		return
	_check(world.world.person_overlay.person_count() > 0, "ordinary Formal composition has non-empty formal Person authority")
	var person_ids := world.world.person_overlay.person_ids()
	_check(not person_ids.is_empty(), "ordinary Formal composition exposes stable Person references")
	if person_ids.is_empty():
		return
	var person_id: String = person_ids[0]
	_check(VNextStableId.is_valid(person_id), "default Formal Person ID satisfies stable ID contract")
	_equal(VNextStableId.kind_of(person_id), "person", "default Formal Person ID has person kind")
	_check(world.world.person_overlay.has_person(person_id), "Formal Person authority owns default Person")
	_equal(world.world.player_state.player_id(), person_id, "PlayerState selects a Person from the same Formal authority")
	_check(world.world.person_overlay.has_person(world.world.player_state.player_id()), "PlayerState Person resolves through Formal Person authority")
	_check(world.organization_person_reference_ids.duplicate().has(person_id), "Organization Person reference source contains Player Person")
	var expected_catalog := VNextOrganizationReferenceCatalog.create(
		world.organization_person_reference_ids.duplicate(),
		world.organization_place_reference_ids
	)
	_check(expected_catalog != null, "expected Organization reference catalog can be reconstructed")
	if expected_catalog != null:
		_equal(
			world.world.organization_state.reference_catalog_fingerprint(),
			expected_catalog.fingerprint(),
			"OrganizationState is actually bound to the same formal Person reference set"
		)

	var person := world.world.person_overlay.person(person_id)
	var claim := world.world.person_overlay.population_claim(person_id)
	var provenance := person.get("provenance", {}) as Dictionary
	_equal(person.get("current_place_id"), WorldBootstrap.DEFAULT_FORMAL_PERSON_PLACE_ID, "default Formal Person has a validated residence")
	_equal(claim.get("territory_id"), WorldBootstrap.DEFAULT_FORMAL_PERSON_TERRITORY_ID, "default Person claims formal country-level population aggregate")
	_equal(claim.get("coverage"), 1, "one named Person covers exactly one existing population share")
	_check(bool(claim.get("active", false)), "living default Person contributes active named coverage")
	_equal(
		world.world.person_overlay.anonymous_population_for_territory(WorldBootstrap.DEFAULT_FORMAL_PERSON_TERRITORY_ID),
		40_699_999,
		"named materialization does not increase France authoritative aggregate population"
	)
	_equal(provenance.get("kind"), "generated", "default Person provenance is explicitly generated")
	_equal(provenance.get("basis"), "simulation_assumption", "default Person provenance is explicitly a simulation assumption")
	_equal(
		provenance.get("population_source_kind"),
		"formal_population_evidence_aggregate",
		"default Person identifies Formal population evidence as its population source"
	)
	_equal(provenance.get("territory_mutation_converged"), false, "default Person does not claim direct mutable territory Population convergence")
	_equal(provenance.get("prototype_character_source"), false, "prototype character data is explicitly excluded")
	_equal(provenance.get("legacy_loran_vesta_source"), false, "legacy Loran/Vesta person data is explicitly excluded")


func _test_current_schema_round_trip() -> void:
	var source := WorldBootstrap.new().build()
	_check(source.success, "current-schema source initializes")
	if not source.success:
		return
	source.simulation_step.advance_minutes(61)
	var before_state := source.persistence.snapshot()
	var before_fingerprint := source.persistence.authoritative_fingerprint()
	var before_person_ids := source.world.person_overlay.person_ids()
	var before_player_id := source.world.player_state.player_id()
	var before_claim := source.world.person_overlay.population_claim(before_player_id)
	var before_organization_refs := source.organization_person_reference_ids.duplicate()

	var restored := WorldBootstrap.new().build()
	_check(restored.success, "current-schema restore target initializes")
	var candidate_1 := restored.persistence.restore_candidate(before_state)
	if candidate_1.success:
		restored = candidate_1
	_check(candidate_1.success, "current-schema Formal Person save restores through candidate/adopt")
	if not restored.success:
		return
	_equal(restored.world.person_overlay.person_ids(), before_person_ids, "Person IDs survive save/restore")
	_equal(restored.world.player_state.player_id(), before_player_id, "Player Person survives save/restore")
	_equal(restored.world.person_overlay.population_claim(before_player_id), before_claim, "Person claim survives save/restore")
	_equal(restored.organization_person_reference_ids.duplicate(), before_organization_refs, "Organization Person references survive save/restore")
	_equal(restored.persistence.snapshot(), before_state, "current-schema save/restore is state-identical")
	_equal(restored.persistence.authoritative_fingerprint(), before_fingerprint, "authoritative fingerprint survives candidate restore/adopt")
	_equal(restored.world.economy_state.get_persistent_state(), source.world.economy_state.get_persistent_state(), "candidate adopt preserves authoritative Economy service state")
	_check(FormalWorldEconomyView.new(restored.world.economy_state.read_only_snapshot()) is FormalWorldEconomyView, "public economy property remains a read-only Economy view after adopt")


func _test_reset_world() -> void:
	var world := WorldBootstrap.new().build()
	var fresh := WorldBootstrap.new().build()
	_check(world.success and fresh.success, "reset fixtures initialize")
	if not world.success or not fresh.success:
		return
	world.simulation_step.advance_minutes(5 * 24 * 60)
	var old_person_authority: VNextNamedPersonOverlay = world.world.person_overlay
	var old_player_state: VNextPlayerState = world.world.player_state
	var candidate_2 := WorldBootstrap.new().build(null, world.organization_person_reference_ids, world.organization_place_reference_ids) if world.explicit_organization_reference_injection else WorldBootstrap.new().build()
	if candidate_2.success:
		world = candidate_2
	_check(candidate_2.success, "reset_world creates a fresh legal Formal composition")
	_check(world.world.person_overlay != old_person_authority, "reset replaces named Person overlay lifecycle instance")
	_check(world.world.player_state != old_player_state, "reset replaces PlayerState lifecycle instance")
	_check(world.world.person_overlay.person_count() > 0, "reset result still has formal Persons")
	_check(world.world.person_overlay.has_person(world.world.player_state.player_id()), "reset Player Person resolves through reset Person authority")
	_check(world.organization_person_reference_ids.duplicate().has(world.world.player_state.player_id()), "reset Organization references the reset Player Person")
	_equal(world.persistence.snapshot(), fresh.persistence.snapshot(), "reset reproduces deterministic fresh Formal composition")
	_equal(world.persistence.authoritative_fingerprint(), fresh.persistence.authoritative_fingerprint(), "reset fingerprint equals fresh-world fingerprint")


func _test_v5_format_rejection() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v5"
	var candidate_3 := world.persistence.restore_candidate(old)
	if candidate_3.success:
		world = candidate_3
	_check(not candidate_3.success, "v5 save format is rejected")
	_check(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_check(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _test_v5_nonempty_organization_format_rejection() -> void:
	var world := WorldBootstrap.new().build()
	_check(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v5"
	var candidate_4 := world.persistence.restore_candidate(old)
	if candidate_4.success:
		world = candidate_4
	_check(not candidate_4.success, "v5 save format is rejected")
	_check(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_check(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _test_source_boundaries() -> void:
	var formal_source := FileAccess.get_file_as_string("res://scripts/content/world_bootstrap.gd")
	var overlay_source := FileAccess.get_file_as_string("res://scripts/vnext/population/named_person_overlay.gd")
	_check(not formal_source.contains("data/world_map/characters.json"), "Formal Person composition does not read prototype characters")
	_check(not formal_source.contains("CharacterRosterService"), "Formal Person composition does not import legacy CharacterRoster")
	_check(not formal_source.contains("SocietySimulationService"), "Formal Person composition does not import legacy SocietySimulation")
	_check(not formal_source.contains("VNextPopulationAuthority"), "Formal Person overlay does not falsely claim direct mutable territory Population convergence")
	_check(not overlay_source.contains("initialize_population("), "Named overlay cannot initialize aggregate Population")
	_check(not overlay_source.contains("prepare_transfer("), "Named overlay cannot mutate aggregate Population through transfer")
	_check(not overlay_source.contains("cash"), "Named overlay owns no cash")
	_check(not overlay_source.contains("appointment"), "Named overlay owns no Organization appointment")
	_check(not overlay_source.contains("military"), "Named overlay owns no military state")
	_check(not overlay_source.contains("political_support"), "Named overlay owns no political support")


func _downgrade_to_v5(current: Dictionary) -> Dictionary:
	var v5 := current.duplicate(true)
	v5["schema_id"] = "formal_world_simulation_v5"
	v5.erase("persons")
	v5.erase("player")
	return v5


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
