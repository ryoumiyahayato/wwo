extends SceneTree

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := FormalWorldSimulation.new()
	_expect(
		simulation.initialize(),
		"P1 formal world initializes: %s" % simulation.initialization_error
	)
	if simulation.initialized:
		_test_identity_and_dates(simulation)
		_test_economy_mapping(simulation)
		_test_projection(simulation)
		_test_missing_evidence_projection()
		_test_projection_immutability(simulation)
		_test_typed_authority_relations(simulation)
		_test_mutation_boundaries(simulation)
		_test_v3_round_trip_and_atomic_rejection(simulation)
		_test_v2_candidate_migration(simulation)
		_test_save_boundary(simulation)
		_test_deterministic_advance()
		_test_save_load_continue_determinism()
	_test_static_owner_boundaries()
	print("Runtime political identity foundation: %d checks, %d failures" % [
		checks, failures,
	])
	quit(1 if failures > 0 else 0)


func _test_identity_and_dates(simulation: FormalWorldSimulation) -> void:
	var evidence := simulation.historical_evidence_view()
	var registry := simulation.political_registry_view()
	_expect(evidence.record_count() == 151, "historical evidence retains 151 records")
	_expect(registry.entity_count() == 146, "runtime registry seeds 146 entities")
	_expect(
		evidence.records_active_on("1900-01-01").size() == 146,
		"1900-01-01 evidence query returns 146"
	)
	_expect(
		evidence.records_active_on("1900-01-24").size() == 148,
		"1900-01-24 evidence query returns 148"
	)
	_expect(
		evidence.records_active_on("1900-01-29").size() == 151,
		"1900-01-29 evidence query returns 151"
	)
	var ids := registry.entity_ids()
	var unique_ids: Dictionary = {}
	for runtime_id: String in ids:
		unique_ids[runtime_id] = true
		var entity := registry.entity(runtime_id)
		_expect(runtime_id.begins_with("state:"), "runtime ID uses state namespace")
		_expect(not entity.has("controller_id"), "runtime entity excludes controller_id")
		var source_id := registry.source_historical_id(runtime_id)
		_expect(
			runtime_id == "state:" + source_id,
			"runtime ID is deterministic from immutable source mapping"
		)
	_expect(unique_ids.size() == 146, "runtime IDs contain no duplicates")
	for future_source_id: String in [
		"cshapes_gw_522",
		"cshapes_gw_531",
		"cshapes_gw_552",
		"cshapes_gw_5518",
		"cshapes_gw_5519",
	]:
		_expect(
			registry.runtime_id_for_source(future_source_id).is_empty(),
			"future evidence does not create runtime polity: %s" % future_source_id
		)
	_expect(
		registry.authority_relations().size() == 91,
		"initial authority snapshot contains 91 source-backed relations"
	)
	simulation.advance_minutes(28 * 24 * 60)
	_expect(registry.entity_count() == 146, "date advance never changes registry membership")


func _test_economy_mapping(simulation: FormalWorldSimulation) -> void:
	var summary := simulation.world_summary()
	_expect(int(summary.get("major_economy_count", 0)) == 50, "50 economy aggregates remain")
	_expect(
		int(summary.get("detailed_polity_unit_count", 0)) == 55,
		"55 runtime political mappings remain"
	)
	for runtime_id_value: Variant in simulation.economy.economy_by_polity_id:
		_expect(
			simulation.political_registry_view().has_entity(str(runtime_id_value)),
			"economy mapping references registry identity"
		)


func _test_projection(simulation: FormalWorldSimulation) -> void:
	var units := simulation.current_world_political_units()
	_expect(units.size() == 146, "current-world projection contains 146 units")
	_expect(
		simulation.historical_political_evidence_units().size() == 151,
		"historical UI projection retains all 151 evidence records"
	)
	for unit: Dictionary in units:
		_expect(str(unit.get("id", "")).begins_with("state:"), "map unit selects runtime ID")
		_expect(
			simulation.historical_evidence_view().has_source(
				str(unit.get("source_historical_id", ""))
			),
			"map unit resolves immutable historical source"
		)
	var france := simulation.polity_summary("state:country_fra")
	_expect(
		str(france.get("source_historical_id", "")) == "country_fra",
		"current summary exposes explicit historical lookup key"
	)
	_expect(
		simulation.historical_record("cshapes_gw_5519").get("valid_from", "")
		== "1900-01-29",
		"historical lookup retains future evidence"
	)


func _test_missing_evidence_projection() -> void:
	var registry := RuntimePoliticalEntityView.new({
		"schema_id": "runtime_political_registry_test",
		"entities": [{
			"runtime_id": "state:test_future_entity",
			"source_historical_ids": [],
			"lifecycle_status": "active",
			"lineage": {},
		}],
		"authority_relations": [],
	})
	var missing_evidence := HistoricalPoliticalEvidenceView.new({
		"configured": true,
		"fingerprint": "test-only-missing-evidence",
		"snapshot_date": "1900-01-01",
		"records": [],
	})
	var units := CurrentWorldPoliticalProjection.map_units(
		registry, missing_evidence
	)
	_expect(units.size() == 1, "missing evidence cannot hide runtime membership")
	if units.size() == 1:
		_expect(
			str(units[0].get("id", "")) == "state:test_future_entity",
			"missing-evidence projection retains stable runtime ID"
		)
		_expect(
			str(units[0].get("historical_metadata_state", "")) == "missing",
			"missing-evidence projection is explicit"
		)
	_expect(
		not CurrentWorldPoliticalProjection.polity_summary(
			"state:test_future_entity", registry, missing_evidence
		).is_empty(),
		"missing evidence cannot hide runtime summary"
	)


func _test_projection_immutability(simulation: FormalWorldSimulation) -> void:
	var registry := simulation.political_registry_view()
	var original_count := registry.entity_count()
	var original_france := registry.entity("state:country_fra")
	var units := simulation.current_world_political_units()
	if not units.is_empty():
		var mutated := units[0] as Dictionary
		mutated["id"] = "state:tampered_projection"
		var runtime_entity := mutated.get("runtime_entity", {}) as Dictionary
		runtime_entity["runtime_id"] = "state:tampered_projection"
		mutated["runtime_entity"] = runtime_entity
		units.remove_at(0)
	_expect(registry.entity_count() == original_count, "projection removal cannot mutate registry")
	_expect(
		registry.entity("state:country_fra") == original_france,
		"projection field mutation cannot mutate registry entity"
	)


func _test_typed_authority_relations(
	simulation: FormalWorldSimulation
) -> void:
	var relations := simulation.political_registry_view().authority_relations()
	_expect(relations.size() == 91, "typed authority relation count remains 91")
	for relation: Dictionary in relations:
		_expect(
			relation.keys().size() == 6
			and relation.has("source_runtime_id")
			and relation.has("target_runtime_id")
			and relation.has("relation_type")
			and relation.has("valid_from")
			and relation.has("valid_to")
			and relation.get("provenance", {}) is Dictionary,
			"authority relation preserves typed source, target, interval, provenance"
		)
		_expect(
			not relation.has("controller_id")
			and not relation.has("authority_runtime_id")
			and not relation.has("subject_runtime_id")
			and not relation.has("relation_kind"),
			"typed authority relation cannot collapse into legacy controller shape"
		)
	for unit: Dictionary in simulation.current_world_political_units():
		_expect(
			not unit.has("controller_id") and not unit.has("sovereign_id"),
			"current-world projection excludes controller and sovereignty aliases"
		)


func _test_mutation_boundaries(simulation: FormalWorldSimulation) -> void:
	var before := simulation.get_persistent_state().duplicate(true)
	_expect(not simulation.initialize(), "second formal composition initialization fails closed")
	_expect(simulation.initialized, "second initialization leaves active world initialized")
	_expect(
		simulation.get_persistent_state() == before,
		"second initialization cannot mutate active world"
	)
	_expect(
		not simulation.historical_evidence_view().has_method("configure"),
		"historical consumer receives no catalog mutation API"
	)
	_expect(
		not simulation.political_registry_view().has_method("configure")
		and not simulation.political_registry_view().has_method("restore_snapshot"),
		"runtime political consumer receives no registry mutation API"
	)

	var catalog := HistoricalPoliticalEvidenceCatalog.new()
	_expect(catalog.configure(), "catalog guard fixture initializes")
	var catalog_count := catalog.record_count()
	var catalog_fingerprint := catalog.fingerprint()
	_expect(not catalog.configure(), "second catalog initialization fails closed")
	_expect(
		catalog.is_configured()
		and catalog.record_count() == catalog_count
		and catalog.fingerprint() == catalog_fingerprint,
		"catalog replacement attempt preserves active evidence"
	)
	var registry := RuntimePoliticalEntityRegistry.new()
	_expect(registry.configure(catalog), "registry guard fixture initializes")
	var registry_before := registry.snapshot()
	_expect(not registry.configure(catalog), "second registry initialization fails closed")
	_expect(
		registry.is_configured() and registry.snapshot() == registry_before,
		"registry reconfiguration attempt preserves active identities"
	)


func _test_v3_round_trip_and_atomic_rejection(
	simulation: FormalWorldSimulation
) -> void:
	var state := simulation.get_persistent_state()
	_expect(str(state.get("schema_id", "")) == "formal_world_simulation_v3", "save schema is v3")
	_expect(state.get("runtime_politics", {}) is Dictionary, "v3 saves runtime registry")
	var restored := FormalWorldSimulation.new()
	_expect(restored.initialize(), "v3 restore candidate initializes")
	_expect(restored.restore_persistent_state(state), "v3 candidate restore succeeds")
	_expect(restored.get_persistent_state() == state, "v3 round trip is exact")
	var p1_state := state.duplicate(true)
	var p1_registry := p1_state.get("runtime_politics", {}) as Dictionary
	p1_registry["schema_id"] = "runtime_political_registry_v1"
	var legacy_relations: Array[Dictionary] = []
	for relation_value: Variant in p1_registry.get("authority_relations", []) as Array:
		var relation := relation_value as Dictionary
		legacy_relations.append({
			"subject_runtime_id": str(relation.get("target_runtime_id", "")),
			"authority_runtime_id": str(relation.get("source_runtime_id", "")),
			"relation_kind": str(relation.get("relation_type", "")),
			"provenance": (
				relation.get("provenance", {}) as Dictionary
			).duplicate(true),
		})
	p1_registry["authority_relations"] = legacy_relations
	p1_state["runtime_politics"] = p1_registry
	var p1_restored := FormalWorldSimulation.new()
	_expect(p1_restored.initialize(), "P1 registry migration candidate initializes")
	_expect(
		p1_restored.restore_persistent_state(p1_state),
		"P1 registry v1 typed-relation migration succeeds"
	)
	_expect(
		str(
			(p1_restored.get_persistent_state().get(
				"runtime_politics", {}
			) as Dictionary).get("schema_id", "")
		) == "runtime_political_registry_v2",
		"P1 registry migration writes closure schema"
	)

	var before := restored.get_persistent_state().duplicate(true)
	var fingerprint_rejected := before.duplicate(true)
	var evidence_state := fingerprint_rejected.get("historical_evidence", {}) as Dictionary
	evidence_state["fingerprint"] = "mismatch"
	fingerprint_rejected["historical_evidence"] = evidence_state
	_expect(
		not restored.restore_persistent_state(fingerprint_rejected),
		"fingerprint mismatch is rejected"
	)
	_expect(restored.get_persistent_state() == before, "fingerprint failure is atomic")

	var schema_rejected := before.duplicate(true)
	var registry_state := schema_rejected.get("runtime_politics", {}) as Dictionary
	var entities := registry_state.get("entities", []) as Array
	var first_entity := (entities[0] as Dictionary).duplicate(true)
	first_entity["controller_id"] = "state:invalid"
	entities[0] = first_entity
	registry_state["entities"] = entities
	schema_rejected["runtime_politics"] = registry_state
	_expect(
		not restored.restore_persistent_state(schema_rejected),
		"runtime controller_id corruption is rejected"
	)
	_expect(restored.get_persistent_state() == before, "registry rejection is atomic")

	var mapping_rejected := before.duplicate(true)
	var economy_state := mapping_rejected.get("economy", {}) as Dictionary
	var static_reference := economy_state.get("static_evidence", {}) as Dictionary
	static_reference["fingerprint"] = "invalid"
	economy_state["static_evidence"] = static_reference
	mapping_rejected["economy"] = economy_state
	_expect(
		not restored.restore_persistent_state(mapping_rejected),
		"v5 static economic evidence mismatch is rejected"
	)
	_expect(restored.get_persistent_state() == before, "static rejection is atomic")


func _test_v2_candidate_migration(simulation: FormalWorldSimulation) -> void:
	var current := simulation.get_persistent_state()
	var legacy_economy := (
		current.get("economy", {}) as Dictionary
	).duplicate(true)
	legacy_economy["schema_id"] = "formal_world_economy_state_v3"
	var country_states := legacy_economy.get("country_states", {}) as Dictionary
	for economy_id_value: Variant in country_states:
		var economy_id := str(economy_id_value)
		var country := country_states[economy_id] as Dictionary
		var legacy_polity_ids: Array[String] = []
		for runtime_id: String in DataRecordUtils.to_string_array(
			country.get("polity_ids", [])
		):
			legacy_polity_ids.append(
				simulation.political_registry_view().source_historical_id(runtime_id)
			)
		country["polity_ids"] = legacy_polity_ids
		country_states[economy_id] = country
	legacy_economy["country_states"] = country_states
	var legacy := {
		"schema_id": "formal_world_simulation_v2",
		"total_minutes": simulation.total_minutes,
		"minute_remainder": simulation.total_minutes % 60,
		"economy": legacy_economy,
	}
	var migrated := FormalWorldSimulation.new()
	_expect(migrated.initialize(), "v2 migration candidate initializes")
	_expect(migrated.restore_persistent_state(legacy), "v2 migration succeeds")
	_expect(
		migrated.political_registry_view().entity_count() == 146,
		"v2 migration seeds 146 entities"
	)
	_expect(
		migrated.get_persistent_state().get("runtime_politics", {}) is Dictionary,
		"v2 migration produces runtime registry snapshot"
	)

	var rejected := legacy.duplicate(true)
	var rejected_economy := (rejected.get("economy", {}) as Dictionary).duplicate(true)
	var rejected_states := (rejected_economy.get("country_states", {}) as Dictionary).duplicate(true)
	var economy_ids: Array[String] = []
	for economy_id_value: Variant in rejected_states:
		economy_ids.append(str(economy_id_value))
	economy_ids.sort()
	var bad_country := (rejected_states[economy_ids[0]] as Dictionary).duplicate(true)
	bad_country["polity_ids"] = ["future_or_unknown_polity"]
	rejected_states[economy_ids[0]] = bad_country
	rejected_economy["country_states"] = rejected_states
	rejected["economy"] = rejected_economy
	var before := migrated.get_persistent_state().duplicate(true)
	_expect(not migrated.restore_persistent_state(rejected), "invalid v2 mapping is rejected")
	_expect(migrated.get_persistent_state() == before, "failed v2 migration is atomic")


func _test_save_boundary(simulation: FormalWorldSimulation) -> void:
	var state := simulation.get_persistent_state()
	var evidence_state := state.get("historical_evidence", {}) as Dictionary
	var registry_state := state.get("runtime_politics", {}) as Dictionary
	_expect(
		evidence_state.keys().size() == 2
		and evidence_state.has("schema_id")
		and evidence_state.has("fingerprint"),
		"save stores evidence identity but no catalog copy"
	)
	_expect(
		not state.has("current_world_projection")
		and not state.has("projection_cache")
		and not state.has("ui_state"),
		"save excludes projection caches and derived UI state"
	)
	_expect(
		registry_state.keys().size() == 4
		and registry_state.has("schema_id")
		and registry_state.has("evidence_fingerprint")
		and registry_state.has("entities")
		and registry_state.has("authority_relations"),
		"save contains only authoritative runtime political snapshot fields"
	)


func _test_deterministic_advance() -> void:
	var stepped := FormalWorldSimulation.new()
	var batched := FormalWorldSimulation.new()
	_expect(stepped.initialize() and batched.initialize(), "determinism worlds initialize")
	if not stepped.initialized or not batched.initialized:
		return
	for _day: int in range(30):
		stepped.advance_minutes(24 * 60)
	batched.advance_minutes(30 * 24 * 60)
	var stepped_state := stepped.get_persistent_state()
	var batched_state := batched.get_persistent_state()
	_expect(
		stepped_state == batched_state,
		"30 stepped days equal one 30-day batch: %s" % (
			_first_difference(stepped_state, batched_state)
		)
	)


func _test_save_load_continue_determinism() -> void:
	var continuous := FormalWorldSimulation.new()
	var split_source := FormalWorldSimulation.new()
	_expect(
		continuous.initialize() and split_source.initialize(),
		"save/load determinism worlds initialize"
	)
	if not continuous.initialized or not split_source.initialized:
		return
	continuous.advance_minutes(60 * 24 * 60)
	split_source.advance_minutes(30 * 24 * 60)
	var resumed := FormalWorldSimulation.new()
	_expect(resumed.initialize(), "save/load continuation candidate initializes")
	_expect(
		resumed.restore_persistent_state(split_source.get_persistent_state()),
		"mid-run v3 snapshot restores"
	)
	if not resumed.initialized:
		return
	resumed.advance_minutes(30 * 24 * 60)
	_expect(
		continuous.get_persistent_state() == resumed.get_persistent_state(),
		"continuous 60 days equal save/load at day 30 plus continuation"
	)


func _test_static_owner_boundaries() -> void:
	var economy_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_economy_service.gd"
	)
	_expect(
		not economy_source.contains("political_units_1900.json"),
		"economy cannot import historical political catalog"
	)
	_expect(
		not economy_source.contains("polity_records"),
		"economy cannot own a political registry"
	)
	_expect(
		economy_source.contains("RuntimePoliticalEntityView")
		and not economy_source.contains("RuntimePoliticalEntityRegistry"),
		"economy consumes only immutable runtime political view"
	)
	var entity_source := FileAccess.get_file_as_string(
		"res://scripts/formal/runtime_political_entity.gd"
	)
	_expect(
		not entity_source.contains("\"controller_id\""),
		"runtime entity schema cannot contain controller_id"
	)
	var application_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_application.gd"
	)
	_expect(
		not application_source.contains("historical_evidence.has_source"),
		"formal UI cannot decide current existence from evidence catalog"
	)
	_expect(
		not application_source.contains("controller_id")
		and not application_source.contains("控制方"),
		"formal current-world UI cannot present generic controller semantics"
	)
	var historical_ui_source := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd"
	)
	var legacy_history_source := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_history.gd"
	)
	_expect(
		not historical_ui_source.contains("political_units_1900.json"),
		"formal UI inheritance cannot load dated political source"
	)
	_expect(
		not legacy_history_source.contains("historical_political_entities_1900.json"),
		"formal UI inheritance cannot load legacy political source"
	)
	var simulation_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_simulation.gd"
	)
	_expect(
		simulation_source.count("HistoricalPoliticalEvidenceCatalog.new()") == 1
		and simulation_source.count("RuntimePoliticalEntityRegistry.new()") == 1,
		"formal composition root creates each political owner exactly once"
	)
	var projection_source := FileAccess.get_file_as_string(
		"res://scripts/formal/current_world_political_projection.gd"
	)
	_expect(
		not projection_source.contains("compatibility_controller_id")
		and not projection_source.contains("continue"),
		"current-world projection cannot collapse authority or skip missing evidence"
	)


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)


func _first_difference(left: Variant, right: Variant, path: String = "root") -> String:
	if typeof(left) != typeof(right):
		return "%s type %d != %d" % [path, typeof(left), typeof(right)]
	if left is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.keys().size() != right_dictionary.keys().size():
			return "%s key count differs" % path
		for key_value: Variant in left_dictionary:
			if not right_dictionary.has(key_value):
				return "%s missing key %s" % [path, str(key_value)]
			var nested := _first_difference(
				left_dictionary[key_value],
				right_dictionary[key_value],
				"%s.%s" % [path, str(key_value)]
			)
			if not nested.is_empty():
				return nested
		return ""
	if left is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return "%s size %d != %d" % [path, left_array.size(), right_array.size()]
		for index: int in range(left_array.size()):
			var nested := _first_difference(
				left_array[index], right_array[index], "%s[%d]" % [path, index]
			)
			if not nested.is_empty():
				return nested
		return ""
	return "" if left == right else "%s %s != %s" % [path, str(left), str(right)]
