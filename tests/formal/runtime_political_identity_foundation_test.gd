extends SceneTree

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := WorldBootstrap.new().build()
	_expect(
		simulation.success,
		"P1 formal world initializes: %s" % simulation.error
	)
	if simulation.success:
		_test_identity_and_dates(simulation)
		_test_economy_mapping(simulation)
		_test_projection(simulation)
		_test_missing_evidence_projection()
		_test_projection_immutability(simulation)
		_test_typed_authority_relations(simulation)
		_test_mutation_boundaries(simulation)
		_test_v3_round_trip_and_atomic_rejection(simulation)
		_test_v2_candidate_rejection(simulation)
		_test_save_boundary(simulation)
		_test_deterministic_advance()
		_test_save_load_continue_determinism()
	_test_static_owner_boundaries()
	print("Runtime political identity foundation: %d checks, %d failures" % [
		checks, failures,
	])
	quit(1 if failures > 0 else 0)


func _test_identity_and_dates(simulation: WorldBuildResult) -> void:
	var evidence := simulation.world.historical_evidence_view
	var registry := RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot())
	var initial_records := evidence.records_active_on("1900-01-01")
	_expect(evidence.record_count() == (simulation.world.provenance.catalog().fact_ids().filter(func(id: String) -> bool: return id.begins_with("political_identity:"))).size(), "historical evidence covers every political fact")
	_expect(registry.entity_count() == initial_records.size(), "runtime registry seeds dated initial evidence")
	_expect(
		initial_records.all(func(record: Dictionary) -> bool: return str(record.valid_from) <= "1900-01-01" and "1900-01-01" <= str(record.valid_to)),
		"initial evidence respects validity intervals"
	)
	_expect(
		evidence.records_active_on("1900-01-24").any(func(record: Dictionary) -> bool: return str(record.source_historical_id) == "cshapes_gw_522"),
		"dated evidence admits the Djibouti record at its start"
	)
	_expect(
		evidence.records_active_on("1900-01-29").any(func(record: Dictionary) -> bool: return str(record.source_historical_id) == "cshapes_gw_5519"),
		"dated evidence admits northwestern Rhodesia at its start"
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
	_expect(unique_ids.size() == ids.size(), "runtime IDs contain no duplicates")
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
		registry.authority_relations().size() == initial_records.filter(func(record: Dictionary) -> bool: return not str(record.controller_id).is_empty()).size(),
		"initial authority snapshot covers sourced controller relations"
	)
	simulation.simulation_step.advance_minutes(28 * 24 * 60)
	_expect(RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()).entity_ids() == ids, "date advance never changes registry membership")


func _test_economy_mapping(simulation: WorldBuildResult) -> void:
	var summary := simulation.world.economy_state.world_summary().merged({"world_political_unit_count": simulation.world.political_registry.entity_count(), "historical_political_record_count": simulation.world.historical_evidence.record_count(), "formal_person_count": simulation.world.person_overlay.person_count(), "background_polity_count": maxi(0, simulation.world.political_registry.entity_count() - int(simulation.world.economy_state.world_summary().get("detailed_polity_unit_count", 0)))})
	_expect(int(summary.get("major_economy_count", 0)) == (simulation.world.economic_evidence.economic_snapshot().countries as Array).size(), "economy aggregates cover bootstrap records")
	_expect(
		int(summary.get("detailed_polity_unit_count", 0)) == FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).economy_by_polity_id.size(),
		"summary covers current runtime political mappings"
	)
	for runtime_id_value: Variant in FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()).economy_by_polity_id:
		_expect(
			RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()).has_entity(str(runtime_id_value)),
			"economy mapping references registry identity"
		)


func _test_projection(simulation: WorldBuildResult) -> void:
	var units := CurrentWorldPoliticalProjection.map_units(RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view)
	_expect(units.size() == simulation.world.political_registry.entity_count(), "current-world projection covers runtime units")
	_expect(
		simulation.world.historical_evidence_view.records().size() == simulation.world.historical_evidence.record_count(),
		"historical UI projection retains all evidence records"
	)
	for unit: Dictionary in units:
		_expect(str(unit.get("id", "")).begins_with("state:"), "map unit selects runtime ID")
		_expect(
			simulation.world.historical_evidence_view.has_source(
				str(unit.get("source_historical_id", ""))
			),
			"map unit resolves immutable historical source"
		)
	var france := CurrentWorldPoliticalProjection.polity_summary("state:country_fra", RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view, FormalWorldEconomyView.new(simulation.world.economy_state.read_only_snapshot()))
	_expect(
		str(france.get("source_historical_id", "")) == "country_fra",
		"current summary exposes explicit historical lookup key"
	)
	_expect(
		simulation.world.historical_evidence_view.record("cshapes_gw_5519").get("valid_from", "")
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


func _test_projection_immutability(simulation: WorldBuildResult) -> void:
	var registry := RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot())
	var original_count := registry.entity_count()
	var original_france := registry.entity("state:country_fra")
	var units := CurrentWorldPoliticalProjection.map_units(RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view)
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
	simulation: WorldBuildResult
) -> void:
	var relations := RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()).authority_relations()
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
	for unit: Dictionary in CurrentWorldPoliticalProjection.map_units(RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()), simulation.world.historical_evidence_view):
		_expect(
			not unit.has("controller_id") and not unit.has("sovereign_id"),
			"current-world projection excludes controller and sovereignty aliases"
		)


func _test_mutation_boundaries(simulation: WorldBuildResult) -> void:
	var before := simulation.persistence.snapshot().duplicate(true)
	_expect(WorldBootstrap.new().build().world.game_clock != simulation.world.game_clock, "new bootstrap creates an independent clock")
	_expect(simulation.success, "second initialization leaves active world initialized")
	_expect(
		simulation.persistence.snapshot() == before,
		"second initialization cannot mutate active world"
	)
	_expect(
		not simulation.world.historical_evidence_view.has_method("configure"),
		"historical consumer receives no catalog mutation API"
	)
	_expect(
		not RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()).has_method("configure")
		and not RuntimePoliticalEntityView.new(simulation.world.political_registry.snapshot()).has_method("restore_snapshot"),
		"runtime political consumer receives no registry mutation API"
	)

	var catalog := HistoricalPoliticalEvidenceCatalog.new()
	_expect(
		catalog.configure(
			HistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,
			simulation.world.provenance.gate()
		),
		"catalog guard fixture initializes through provenance gate"
	)
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
	simulation: WorldBuildResult
) -> void:
	var state := simulation.persistence.snapshot()
	_expect(
		str(state.get("schema_id", "")) == FormalPersistence.SCHEMA_ID,
		"save schema is current"
	)
	_expect(state.get("runtime_politics", {}) is Dictionary, "current save includes runtime registry")
	var restored := WorldBootstrap.new().build()
	_expect(restored.success, "v3 restore candidate initializes")
	var candidate_1 := restored.persistence.restore_candidate(state)
	if candidate_1.success:
		restored = candidate_1
	_expect(candidate_1.success, "v3 candidate restore succeeds")
	_expect(restored.persistence.snapshot() == state, "v3 round trip is exact")
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
	var p1_restored := WorldBootstrap.new().build()
	_expect(p1_restored.success, "P1 registry migration candidate initializes")
	var candidate_2 := p1_restored.persistence.restore_candidate(p1_state)
	if candidate_2.success:
		p1_restored = candidate_2
	_expect(
		candidate_2.success,
		"P1 registry v1 typed-relation migration succeeds"
	)
	_expect(
		str(
			(p1_restored.persistence.snapshot().get(
				"runtime_politics", {}
			) as Dictionary).get("schema_id", "")
		) == "runtime_political_registry_v2",
		"P1 registry migration writes closure schema"
	)

	var before := restored.persistence.snapshot().duplicate(true)
	var fingerprint_rejected := before.duplicate(true)
	var evidence_state := fingerprint_rejected.get("historical_evidence", {}) as Dictionary
	evidence_state["schema_id"] = "unsupported_historical_evidence_v999"
	fingerprint_rejected["historical_evidence"] = evidence_state
	var candidate_3 := restored.persistence.restore_candidate(fingerprint_rejected)
	if candidate_3.success:
		restored = candidate_3
	_expect(
		not candidate_3.success,
		"unsupported evidence schema is rejected"
	)
	_expect(restored.persistence.snapshot() == before, "schema rejection is atomic")

	var schema_rejected := before.duplicate(true)
	var registry_state := schema_rejected.get("runtime_politics", {}) as Dictionary
	var entities := registry_state.get("entities", []) as Array
	var first_entity := (entities[0] as Dictionary).duplicate(true)
	first_entity["controller_id"] = "state:invalid"
	entities[0] = first_entity
	registry_state["entities"] = entities
	schema_rejected["runtime_politics"] = registry_state
	var candidate_4 := restored.persistence.restore_candidate(schema_rejected)
	if candidate_4.success:
		restored = candidate_4
	_expect(
		not candidate_4.success,
		"runtime controller_id corruption is rejected"
	)
	_expect(restored.persistence.snapshot() == before, "registry rejection is atomic")

	var mapping_rejected := before.duplicate(true)
	var economy_state := mapping_rejected.get("economy", {}) as Dictionary
	var static_reference := economy_state.get("static_evidence", {}) as Dictionary
	static_reference["revision"] = "unsupported_static_evidence_v999"
	economy_state["static_evidence"] = static_reference
	mapping_rejected["economy"] = economy_state
	var candidate_5 := restored.persistence.restore_candidate(mapping_rejected)
	if candidate_5.success:
		restored = candidate_5
	_expect(
		not candidate_5.success,
		"v6 static economic evidence mismatch is rejected"
	)
	_expect(restored.persistence.snapshot() == before, "static rejection is atomic")


func _test_v2_candidate_rejection(simulation: WorldBuildResult) -> void:
	var world := WorldBootstrap.new().build()
	_expect(world.success, "old-format rejection target initializes")
	var before: Dictionary = world.persistence.snapshot()
	var old: Dictionary = before.duplicate(true)
	old["schema_id"] = "formal_world_simulation_v2"
	var candidate_6 := world.persistence.restore_candidate(old)
	if candidate_6.success:
		world = candidate_6
	_expect(not candidate_6.success, "v2 save format is rejected")
	_expect(world.persistence.error.contains("SAVE FORMAT VERSION MISMATCH"), "version rejection explains controller storage change")
	_expect(world.persistence.snapshot() == before, "old-format rejection leaves current world unchanged")


func _test_save_boundary(simulation: WorldBuildResult) -> void:
	var state := simulation.persistence.snapshot()
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
	var stepped := WorldBootstrap.new().build()
	var batched := WorldBootstrap.new().build()
	_expect(stepped.success and batched.success, "determinism worlds initialize")
	if not stepped.success or not batched.success:
		return
	for _day: int in range(30):
		stepped.simulation_step.advance_minutes(24 * 60)
	batched.simulation_step.advance_minutes(30 * 24 * 60)
	var stepped_state := stepped.persistence.snapshot()
	var batched_state := batched.persistence.snapshot()
	_expect(
		stepped_state == batched_state,
		"30 stepped days equal one 30-day batch: %s" % (
			_first_difference(stepped_state, batched_state)
		)
	)


func _test_save_load_continue_determinism() -> void:
	var continuous := WorldBootstrap.new().build()
	var split_source := WorldBootstrap.new().build()
	_expect(
		continuous.success and split_source.success,
		"save/load determinism worlds initialize"
	)
	if not continuous.success or not split_source.success:
		return
	continuous.simulation_step.advance_minutes(60 * 24 * 60)
	split_source.simulation_step.advance_minutes(30 * 24 * 60)
	var resumed := WorldBootstrap.new().build()
	_expect(resumed.success, "save/load continuation candidate initializes")
	var candidate_7 := resumed.persistence.restore_candidate(split_source.persistence.snapshot())
	if candidate_7.success:
		resumed = candidate_7
	_expect(
		candidate_7.success,
		"mid-run v3 snapshot restores"
	)
	if not resumed.success:
		return
	resumed.simulation_step.advance_minutes(30 * 24 * 60)
	_expect(
		continuous.persistence.snapshot() == resumed.persistence.snapshot(),
		"continuous 60 days equal save/load at day 30 plus continuation"
	)


func _test_static_owner_boundaries() -> void:
	var economy_source := FileAccess.get_file_as_string(
		"res://scripts/world/formal_world_economy_state.gd"
	) + FileAccess.get_file_as_string("res://scripts/simulation/formal_world_economy_simulation.gd")
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
	var simulation_source := FileAccess.get_file_as_string(
		"res://scripts/content/world_bootstrap.gd"
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
