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
	_test_v5_backward_compatibility()
	_test_v5_nonempty_organization_compatibility()
	_test_source_boundaries()
	print("Formal person overlay integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_ordinary_formal_composition() -> void:
	var world := FormalWorldSimulation.new()
	_check(world.initialize(), "ordinary FormalWorldSimulation initializes with Person overlay: %s" % world.initialization_error)
	if not world.initialized:
		return
	_check(world.formal_person_count() > 0, "ordinary Formal composition has non-empty formal Person authority")
	var person_ids := world.formal_person_ids()
	_check(not person_ids.is_empty(), "ordinary Formal composition exposes stable Person references")
	if person_ids.is_empty():
		return
	var person_id: String = person_ids[0]
	_check(VNextStableId.is_valid(person_id), "default Formal Person ID satisfies stable ID contract")
	_equal(VNextStableId.kind_of(person_id), "person", "default Formal Person ID has person kind")
	_check(world.has_formal_person(person_id), "Formal Person authority owns default Person")
	_equal(world.player_person_id(), person_id, "PlayerState selects a Person from the same Formal authority")
	_check(world.has_formal_person(world.player_person_id()), "PlayerState Person resolves through Formal Person authority")
	_check(world.organization_person_reference_ids().has(person_id), "Organization Person reference source contains Player Person")
	var expected_catalog := VNextOrganizationReferenceCatalog.create(
		world.organization_person_reference_ids(),
		world._organization_place_reference_ids
	)
	_check(expected_catalog != null, "expected Organization reference catalog can be reconstructed")
	if expected_catalog != null:
		_equal(
			world._organization.reference_catalog_fingerprint(),
			expected_catalog.fingerprint(),
			"OrganizationCore is actually bound to the same formal Person reference set"
		)

	var person := world.formal_person(person_id)
	var claim := world.formal_person_population_claim(person_id)
	var provenance := person.get("provenance", {}) as Dictionary
	_equal(person.get("current_place_id"), FormalWorldSimulation.DEFAULT_FORMAL_PERSON_PLACE_ID, "default Formal Person has a validated residence")
	_equal(claim.get("territory_id"), FormalWorldSimulation.DEFAULT_FORMAL_PERSON_TERRITORY_ID, "default Person claims formal country-level population aggregate")
	_equal(claim.get("coverage"), 1, "one named Person covers exactly one existing population share")
	_check(bool(claim.get("active", false)), "living default Person contributes active named coverage")
	_equal(
		world.formal_person_anonymous_population(FormalWorldSimulation.DEFAULT_FORMAL_PERSON_TERRITORY_ID),
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
	_equal(provenance.get("territory_mutation_converged"), false, "default Person does not claim mutable territory Population convergence")
	_equal(provenance.get("prototype_character_source"), false, "prototype character data is explicitly excluded")
	_equal(provenance.get("legacy_loran_vesta_source"), false, "legacy Loran/Vesta person data is explicitly excluded")


func _test_current_schema_round_trip() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "current-schema source initializes")
	if not source.initialized:
		return
	source.advance_minutes(61)
	var before_state := source.get_persistent_state()
	var before_fingerprint := source.authoritative_fingerprint()
	var before_person_ids := source.formal_person_ids()
	var before_player_id := source.player_person_id()
	var before_claim := source.formal_person_population_claim(before_player_id)
	var before_organization_refs := source.organization_person_reference_ids()

	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "current-schema restore target initializes")
	_check(restored.restore_persistent_state(before_state), "current-schema Formal Person save restores through candidate/adopt")
	if not restored.initialized:
		return
	_equal(restored.formal_person_ids(), before_person_ids, "Person IDs survive save/restore")
	_equal(restored.player_person_id(), before_player_id, "Player Person survives save/restore")
	_equal(restored.formal_person_population_claim(before_player_id), before_claim, "Person claim survives save/restore")
	_equal(restored.organization_person_reference_ids(), before_organization_refs, "Organization Person references survive save/restore")
	_equal(restored.get_persistent_state(), before_state, "current-schema save/restore is state-identical")
	_equal(restored.authoritative_fingerprint(), before_fingerprint, "authoritative fingerprint survives candidate restore/adopt")
	_equal(restored._economy.get_persistent_state(), source._economy.get_persistent_state(), "candidate adopt preserves authoritative Economy service state")
	_check(restored.economy is FormalWorldEconomyView, "public economy property remains a read-only Economy view after adopt")


func _test_reset_world() -> void:
	var world := FormalWorldSimulation.new()
	var fresh := FormalWorldSimulation.new()
	_check(world.initialize() and fresh.initialize(), "reset fixtures initialize")
	if not world.initialized or not fresh.initialized:
		return
	world.advance_minutes(5 * 24 * 60)
	var old_person_authority: VNextNamedPersonOverlay = world._person_authority
	var old_player_state: VNextPlayerState = world._player_state
	_check(world.reset_world(), "reset_world creates a fresh legal Formal composition")
	_check(world._person_authority != old_person_authority, "reset replaces named Person overlay lifecycle instance")
	_check(world._player_state != old_player_state, "reset replaces PlayerState lifecycle instance")
	_check(world.formal_person_count() > 0, "reset result still has formal Persons")
	_check(world.has_formal_person(world.player_person_id()), "reset Player Person resolves through reset Person authority")
	_check(world.organization_person_reference_ids().has(world.player_person_id()), "reset Organization references the reset Player Person")
	_equal(world.get_persistent_state(), fresh.get_persistent_state(), "reset reproduces deterministic fresh Formal composition")
	_equal(world.authoritative_fingerprint(), fresh.authoritative_fingerprint(), "reset fingerprint equals fresh-world fingerprint")


func _test_v5_backward_compatibility() -> void:
	var source := FormalWorldSimulation.new()
	_check(source.initialize(), "v5 ordinary migration source initializes")
	if not source.initialized:
		return
	source.advance_minutes(125)
	var current := source.get_persistent_state()
	var v5 := _downgrade_to_v5(current)
	var expected_economy := (v5.get("economy") as Dictionary).duplicate(true)
	var expected_organization := (v5.get("organization") as Dictionary).duplicate(true)

	var restored := FormalWorldSimulation.new()
	_check(restored.initialize(), "v5 ordinary migration target initializes")
	_check(restored.restore_persistent_state(v5), "actual v5 snapshot without Person/Player fields restores")
	if not restored.initialized:
		return
	_equal(restored.get_persistent_state().get("economy"), expected_economy, "v5 migration preserves Economy state")
	_equal(restored.get_persistent_state().get("organization"), expected_organization, "v5 migration preserves Organization state")
	_equal(restored.total_minutes, 125, "v5 migration preserves formal time")
	_check(restored.formal_person_count() > 0, "v5 migration deterministically materializes current Formal Person overlay")
	_check(restored.has_formal_person(restored.player_person_id()), "v5 migration binds Player to migrated current Person authority")
	_check(restored.organization_person_reference_ids().has(restored.player_person_id()), "v5 migration binds Organization references to migrated current Person")


func _test_v5_nonempty_organization_compatibility() -> void:
	var core := VNextOrganizationCore.create(EXPLICIT_PERSON_IDS, EXPLICIT_PLACE_IDS)
	_check(core != null, "explicit v5 Organization fixture core configures")
	if core == null:
		return
	_check(core.register_organization("organization:root", "association", "place:capital"), "explicit v5 fixture organization registers")
	_check(core.add_member("organization:root", "person:alice"), "explicit v5 fixture member registers")
	var source := FormalWorldSimulation.new(core, EXPLICIT_PERSON_IDS, EXPLICIT_PLACE_IDS)
	_check(source.initialize(), "explicit-reference Formal source initializes")
	if not source.initialized:
		return
	source.advance_minutes(60)
	var source_state := source.get_persistent_state()
	var v5 := _downgrade_to_v5(source_state)
	var expected_org := (v5.get("organization") as Dictionary).duplicate(true)
	var expected_economy := (v5.get("economy") as Dictionary).duplicate(true)

	var target := FormalWorldSimulation.new(null, EXPLICIT_PERSON_IDS, EXPLICIT_PLACE_IDS)
	_check(target.initialize(), "explicit-reference v5 target initializes with legacy reference contract")
	_check(target.restore_persistent_state(v5), "non-empty v5 Organization snapshot restores with matching explicit references")
	if not target.initialized:
		return
	_equal(target.organization_view().snapshot(), expected_org, "non-empty v5 Organization state is preserved")
	_equal(target.get_persistent_state().get("economy"), expected_economy, "non-empty v5 migration preserves Economy state")
	_equal(target.formal_person_ids(), EXPLICIT_PERSON_IDS, "explicit v5 references become formal Person references without changing IDs")
	_check(target.organization_person_reference_ids().has("person:alice"), "restored Organization reference catalog includes legacy member Person")
	_equal(target.organization_view().member_ids("organization:root"), ["person:alice"], "legacy Organization member survives v5 migration")


func _test_source_boundaries() -> void:
	var formal_source := FileAccess.get_file_as_string("res://scripts/formal/formal_world_simulation.gd")
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
	v5["schema_id"] = FormalWorldSimulation.PREVIOUS_SCHEMA_ID
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
	_check(actual == expected, label)
