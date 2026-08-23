extends SceneTree
## Wave 2A-R1 architecture-only truth contract.

const PRODUCT_SCENE: String = "res://scenes/formal/formal_world_main.tscn"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_population_identity_and_provider()
	_test_population_snapshot_lineage_and_indexing()
	_test_crosswalk_contract()
	_test_economic_geography_empty_state()
	_test_spatial_control_ownership()
	_test_spatial_v1_migration()
	_test_temporal_political_catalog()
	await _test_actual_product_regression()
	print("Wave 2A-R1: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_population_identity_and_provider() -> void:
	# R1-01 / R1-02
	var alias_catalog := VNextPopulationUnitCatalog.new()
	_check(not alias_catalog.load_records([
		{
			"population_unit_id": "population:france_a",
			"scope_kind": "major_economy_aggregate",
			"source_entity_id": "country_fra",
		},
		{
			"population_unit_id": "population:france_b",
			"scope_kind": "country_aggregate",
			"source_entity_id": "country_fra",
		},
	], "alias_rejection_v1"), "R1-01 one source demographic scope cannot acquire alias identities")
	_check(
		VNextPopulationUnitId.is_valid("population:country_fra")
		and not VNextPopulationUnitId.is_valid("place:country_fra")
		and not VNextPopulationUnitId.is_valid("region:country_fra"),
		"R1-02 PopulationUnitId is distinct from SpatialRegionId"
	)

	var provider := VNextPopulationEvidenceProvider.new()
	var provider_started: int = Time.get_ticks_usec()
	_check(provider.load_current_evidence() and provider.is_loaded(), "production Population evidence provider loads")
	print("R1 PERFORMANCE provider_50_fact_load_usec=%d" % (Time.get_ticks_usec() - provider_started))
	_check(provider.population_unit_ids().size() == 50, "provider exposes only the 50 bounded aggregate evidence rows")
	var france: Dictionary = provider.fact_at("population:country_fra")
	var provenance: Dictionary = france.get("provenance", {}) as Dictionary
	_check(
		int(france.get("total_population", -1)) == 40_700_000
		and str(provenance.get("precision", "")) == VNextFactProvenance.ESTIMATED
		and str(provenance.get("applicability", "")) == VNextFactProvenance.NEAR_1900_SUPPORTED
		and str(provenance.get("valid_from", "")) == "1900-01-01"
		and str(provenance.get("reference_date", "")) == "1900-01-01",
		"R1-04 provider facts retain precision, applicability and temporal provenance"
	)
	_check(
		str(france.get("source_classification", "")) == "BOUNDED_AGGREGATE_ESTIMATE"
		and str(france.get("source_evidence_path", "")) == VNextPopulationEvidenceProvider.SOURCE_PATH
		and (france.get("source_manifest", []) as Array).size() >= 4
		and int(france.get("lower_bound", -1)) < int(france.get("total_population", -1))
		and int(france.get("upper_bound", -1)) > int(france.get("total_population", -1))
		and int(france.get("confidence_bp", -1)) > 0,
		"provider preserves bounded aggregate source, bounds and confidence"
	)
	_check(
		provider.regional_fact("place:northern_industrial_belt").is_empty()
		and provider.city_fact("place:paris").is_empty(),
		"R1-03 unsupported regional and city Population are not fabricated"
	)


func _test_population_snapshot_lineage_and_indexing() -> void:
	var provider := VNextPopulationEvidenceProvider.new()
	_check(provider.load_current_evidence(), "snapshot fixture provider loads")
	var unit_id: String = "population:country_fra"
	var population := VNextMacroPopulation.create(
		provider.catalog(), [unit_id], provider.revision()
	)
	_check(population != null and population.is_valid(), "MacroPopulation binds canonical PopulationUnit catalog")
	if population == null:
		return
	_check(
		VNextMacroPopulation.create(provider.catalog(), ["place:country_fra"], provider.revision()) == null
		and VNextMacroPopulation.create(provider.catalog(), ["region:country_fra"], provider.revision()) == null,
		"R1-01 place/region aliases cannot address Population state"
	)
	var evidence: Dictionary = provider.fact_at(unit_id)
	_check(
		population.set_initial_state(
			unit_id,
			_state(40_700_000),
			(evidence.get("provenance", {}) as Dictionary)
		),
		"canonical Population state accepts explicit evidence lineage"
	)
	var view: Dictionary = population.record_snapshot_at(unit_id)
	_check(
		str(view.get("population_unit_id", "")) == unit_id
		and int(view.get("population_revision", 0)) == population.population_revision()
		and str(view.get("provider_revision", "")) == provider.revision()
		and str(view.get("catalog_revision", "")) == provider.catalog().revision()
		and VNextFactProvenance.is_valid(view.get("lineage", {}) as Dictionary),
		"R1-04/R1-05 immutable Population view preserves revisions and fact lineage"
	)
	view["population_unit_id"] = "population:mutated_copy"
	_check(
		str(population.record_snapshot_at(unit_id).get("population_unit_id", "")) == unit_id,
		"Population snapshot is an immutable copy"
	)
	var before_legacy_restore: Dictionary = population.snapshot()
	var legacy_snapshot: Dictionary = before_legacy_restore.duplicate(true)
	legacy_snapshot["schema_id"] = "vnext_macro_population_v3"
	legacy_snapshot["known_place_ids"] = ["place:country_fra", "region:country_fra"]
	legacy_snapshot.erase("known_population_unit_ids")
	_check(
		not population.restore(legacy_snapshot)
		and population.snapshot() == before_legacy_restore,
		"legacy place/region save aliases fail closed without duplicating demographic state"
	)
	var query_started: int = Time.get_ticks_usec()
	for _index: int in range(10_000):
		population.population_at(unit_id)
	var query_usec: int = Time.get_ticks_usec() - query_started
	print("R1 PERFORMANCE population_10000_indexed_queries_usec=%d" % query_usec)
	_check(query_usec < 1_000_000, "Population indexed queries remain bounded after revision validation")


func _test_crosswalk_contract() -> void:
	var records: Array[Dictionary] = [
		_allocation("place:west", 5000, 8200, 1800),
		_allocation("place:east", 3200, 8200, 1800),
	]
	var first := VNextTypedCrosswalkCatalog.new()
	var reversed: Array[Dictionary] = records.duplicate(true)
	reversed.reverse()
	var second := VNextTypedCrosswalkCatalog.new()
	_check(first.load_records(records, "population_spatial_test_v1"), "R1-05 allocation sum equals declared coverage")
	_check(second.load_records(reversed, "population_spatial_test_v1"), "reordered crosswalk loads")
	_check(first.records() == second.records(), "R1-07 crosswalk canonical output ignores input order")
	var crosswalk_started: int = Time.get_ticks_usec()
	for _index: int in range(10_000):
		first.records_from(VNextTypedCrosswalkCatalog.POPULATION_UNIT, "population:country_fra")
	print("R1 PERFORMANCE crosswalk_10000_sparse_queries_usec=%d" % (Time.get_ticks_usec() - crosswalk_started))
	_check(
		first.unresolved_bp(
			VNextTypedCrosswalkCatalog.POPULATION_UNIT,
			"population:country_fra",
			"population"
		) == 1800,
		"R1-06 unresolved coverage remains explicit"
	)
	var wrong_sum := VNextTypedCrosswalkCatalog.new()
	var invalid_records: Array[Dictionary] = records.duplicate(true)
	invalid_records[1]["allocation_weight_bp"] = 3100
	_check(not wrong_sum.load_records(invalid_records, "wrong_sum_v1"), "R1-05 silent normalization is rejected")
	var relevance_as_weight := VNextTypedCrosswalkCatalog.new()
	var bad_relevance: Dictionary = _allocation("place:west", 10_000, 10_000, 0)
	bad_relevance["relevance_bp"] = 9000
	_check(not relevance_as_weight.load_records([bad_relevance], "bad_relevance_v1"), "R1-08 relevance_bp cannot be allocation weight")
	var relevance_only := VNextTypedCrosswalkCatalog.new()
	_check(relevance_only.load_records([{
		"source_type": VNextTypedCrosswalkCatalog.POPULATION_UNIT,
		"source_id": "population:country_fra",
		"target_type": VNextTypedCrosswalkCatalog.SPATIAL_REGION,
		"target_id": "place:west",
		"measure": "population_context",
		"mapping_kind": VNextTypedCrosswalkCatalog.RELEVANCE,
		"applicability": VNextFactProvenance.REFERENCE_ONLY,
		"valid_from": "1900-01-01",
		"valid_to": "1900-12-31",
		"provenance_id": "relevance_only_test",
		"relevance_bp": 9000,
	}], "relevance_only_v1")
	and not relevance_only.records()[0].has("allocation_weight_bp")
	and relevance_only.unresolved_bp(
		VNextTypedCrosswalkCatalog.POPULATION_UNIT,
		"population:country_fra",
		"population_context"
	) == -1, "relevance-only mapping remains non-allocative")
	var duplicate_mapping := VNextTypedCrosswalkCatalog.new()
	_check(
		not duplicate_mapping.load_records([
			_allocation("place:west", 8200, 8200, 1800),
			_allocation("place:west", 0, 8200, 1800),
		], "duplicate_mapping_v1"),
		"duplicate source/target/measure/window mapping fails closed"
	)
	var geometric_population := VNextTypedCrosswalkCatalog.new()
	_check(not geometric_population.load_records([{
		"source_type": VNextTypedCrosswalkCatalog.POPULATION_UNIT,
		"source_id": "population:country_fra",
		"target_type": VNextTypedCrosswalkCatalog.SPATIAL_REGION,
		"target_id": "place:west",
		"measure": "population",
		"mapping_kind": VNextTypedCrosswalkCatalog.GEOMETRIC_OVERLAP,
		"applicability": VNextFactProvenance.HISTORICALLY_SUPPORTED,
		"valid_from": "1900-01-01",
		"valid_to": "1900-12-31",
		"provenance_id": "geometry_only",
	}], "geometry_population_v1"), "R1-09 geometric membership alone cannot allocate Population")
	var empty_crosswalk := VNextTypedCrosswalkCatalog.new()
	_check(
		empty_crosswalk.load_records([], "empty_crosswalk_v1")
		and empty_crosswalk.is_loaded()
		and empty_crosswalk.records().is_empty()
		and empty_crosswalk.status() == "EMPTY / NOT AVAILABLE",
		"empty crosswalk remains valid and explicitly unavailable"
	)


func _test_economic_geography_empty_state() -> void:
	var catalog := VNextEconomicRegionCatalog.new()
	_check(
		catalog.initialize_empty()
		and catalog.economic_region_ids().is_empty()
		and catalog.status() == "EMPTY / NOT AVAILABLE",
		"unrecovered Economic Geography remains a valid empty catalog"
	)
	_check(
		VNextEconomicRegionId.is_valid("economic_region:example")
		and not VNextEconomicRegionId.is_valid("economy:example")
		and not VNextEconomicRegionId.is_valid("place:example"),
		"EconomicRegion identity stays distinct from Market and SpatialRegion"
	)


func _test_spatial_control_ownership() -> void:
	var spatial_catalog := VNextSpatialCatalog.new()
	_check(spatial_catalog.load_legacy_world_map(), "control boundary fixture Spatial catalog loads")
	var world := VNextSpatialWorld.create(spatial_catalog)
	_check(world != null and world.is_valid(), "physical Spatial owner constructs")
	if world == null:
		return
	_check(
		not world.has_method("get_territorial_facts")
		and not world.has_method("set_sovereign_owner")
		and not world.has_method("set_military_controller")
		and not world.snapshot().has("territories"),
		"R1-10 Spatial identity and persistence contain no controller authority"
	)
	var political := VNextPoliticalControlOverlay.create(
		spatial_catalog, ["country_fra", "british_empire"]
	)
	var military := VNextMilitaryControlOverlay.create(
		spatial_catalog, ["country_fra", "british_empire"]
	)
	_check(political != null and military != null, "independent control overlays construct")
	if political == null or military == null:
		return
	var physical_before: Dictionary = world.get_region("northern_industrial_belt")
	var spatial_snapshot_before: Dictionary = world.snapshot()
	_check(political.set_control(
		"northern_industrial_belt", "country_fra", "country_fra", "british_empire", "1900-01-01"
	), "political overlay accepts explicit controller fact")
	_check(military.set_controller(
		"northern_industrial_belt", "british_empire", "1900-01-01"
	), "military overlay accepts independent control fact")
	_check(
		world.get_region("northern_industrial_belt") == physical_before
		and world.snapshot() == spatial_snapshot_before
		and str(political.control_at("northern_industrial_belt").get("effective_controller_id", "")) == "british_empire",
		"R1-11 political control query is independent of physical place identity"
	)


func _test_spatial_v1_migration() -> void:
	var catalog := VNextSpatialCatalog.new()
	_check(catalog.load_legacy_world_map(), "migration fixture Spatial catalog loads")
	var source := VNextSpatialWorld.create(catalog)
	var restored := VNextSpatialWorld.create(catalog)
	_check(source != null and restored != null, "migration source and target construct")
	if source == null or restored == null:
		return
	var link_id: String = catalog.link_ids()[0]
	_check(
		source.set_infrastructure_status(
			link_id, VNextInfrastructureLinkState.STATUS_DAMAGED
		),
		"migration fixture changes physical infrastructure"
	)
	var expected_v2: Dictionary = source.snapshot()
	var legacy_v1: Dictionary = _legacy_spatial_snapshot(expected_v2, catalog)
	var legacy_hash: String = JSON.stringify(legacy_v1).sha256_text()
	_check(restored.restore(legacy_v1), "valid legacy v1 snapshot is accepted only as migration input")
	var migrated_v2: Dictionary = restored.snapshot()
	var migrated_hash: String = JSON.stringify(migrated_v2).sha256_text()
	print("R1 MIGRATION legacy_v1_sha256=%s migrated_v2_sha256=%s" % [legacy_hash, migrated_hash])
	_check(
		migrated_v2 == expected_v2
		and not migrated_v2.has("territories")
		and str(restored.infrastructure_state(link_id).get("status", ""))
			== VNextInfrastructureLinkState.STATUS_DAMAGED,
		"v1 migration discards controller truth and preserves physical infrastructure"
	)
	var round_trip := VNextSpatialWorld.create(catalog)
	_check(
		round_trip != null
		and round_trip.restore(migrated_v2)
		and round_trip.snapshot() == migrated_v2,
		"current v2 save-load-save is deterministic"
	)
	var before_failed_restore: Dictionary = restored.snapshot()
	var malformed: Dictionary = legacy_v1.duplicate(true)
	var malformed_rows: Array = malformed.get("territories", []) as Array
	(malformed_rows[0] as Dictionary)["unexpected_controller_alias"] = "country_fra"
	malformed["territories"] = malformed_rows
	_check(
		not restored.restore(malformed)
		and restored.snapshot() == before_failed_restore,
		"malformed legacy controller row fails atomically"
	)
	var unknown_controller: Dictionary = legacy_v1.duplicate(true)
	var unknown_rows: Array = unknown_controller.get("territories", []) as Array
	(unknown_rows[0] as Dictionary)["military_controller_id"] = "unknown_controller"
	unknown_controller["territories"] = unknown_rows
	_check(
		not restored.restore(unknown_controller)
		and restored.snapshot() == before_failed_restore,
		"unknown legacy controller fails closed without half-migration"
	)


func _test_temporal_political_catalog() -> void:
	var catalog := FormalDatedPoliticalCatalog.new()
	_check(catalog.load_documents(
		_read_json("res://data/world_map/historical/political_units_1900.json"),
		_read_json("res://data/world_map/historical/cshapes_1900_snapshot.json")
	), "dated political catalog loads existing source records")
	var dec31: Array[String] = catalog.active_unit_ids_on("1899-12-31")
	var jan1: Array[String] = catalog.active_unit_ids_on("1900-01-01")
	var jan23: Array[String] = catalog.active_unit_ids_on("1900-01-23")
	var jan24: Array[String] = catalog.active_unit_ids_on("1900-01-24")
	var jan28: Array[String] = catalog.active_unit_ids_on("1900-01-28")
	var jan29: Array[String] = catalog.active_unit_ids_on("1900-01-29")
	var mar12: Array[String] = catalog.active_unit_ids_on("1900-03-12")
	var mar13: Array[String] = catalog.active_unit_ids_on("1900-03-13")
	_check(
		dec31.size() == 145 and not dec31.has("cshapes_gw_912"),
		"1899-12-31 obeys record validity rather than snapshot reference date"
	)
	_check(jan1.size() == 146 and not jan1.has("cshapes_gw_522"), "R1-12 January 1 fails closed for five not-yet-valid records")
	_check(jan23 == jan1, "January 23 remains on the January 1 validity set")
	_check(
		jan24.size() == 148 and jan24.has("cshapes_gw_522") and jan24.has("cshapes_gw_531")
		and not jan24.has("cshapes_gw_552"),
		"R1-13 January 24 transition activates Djibouti and Eritrea"
	)
	_check(jan28 == jan24, "January 28 remains on the January 24 validity set")
	_check(
		jan29.size() == 151 and jan29.has("cshapes_gw_552")
		and jan29.has("cshapes_gw_5518") and jan29.has("cshapes_gw_5519"),
		"R1-13 January 29 transition activates the three Rhodesia records"
	)
	_check(
		mar12.size() == 151 and catalog.reference_date() == "1900-03-12",
		"R1-14 March 12 reference snapshot remains queryable without backdating"
	)
	_check(
		mar13.size() == 151 and mar13 == mar12,
		"March 13 follows explicit validity intervals, not a one-day snapshot assumption"
	)
	var jan1_unavailable: Array[String] = catalog.temporally_unavailable_unit_ids_on("1900-01-01")
	_check(
		jan1_unavailable == [
			"cshapes_gw_522", "cshapes_gw_531", "cshapes_gw_5518",
			"cshapes_gw_5519", "cshapes_gw_552",
		]
		and catalog.temporal_status("cshapes_gw_522", "1900-01-01")
			== VNextFactProvenance.TEMPORALLY_UNKNOWN
		and catalog.reference_feature_for_unit("cshapes_gw_522").has("geometry"),
		"January political gaps retain reference geometry without fabricating predecessors"
	)


func _test_actual_product_regression() -> void:
	var packed := load(PRODUCT_SCENE) as PackedScene
	var application := packed.instantiate() as FormalWorldApplication if packed != null else null
	_check(application != null, "actual Formal product scene instantiates")
	if application == null:
		return
	get_root().add_child(application)
	current_scene = application
	await process_frame
	await process_frame
	_check(
		application._history_entity_by_id.size() == 146
		and str(application.historical_evidence_report().get("query_date", "")) == "1900-01-01",
		"R1-12 actual product queries January 1 political truth"
	)
	var jan1_evidence: Dictionary = application.historical_evidence_report()
	var djibouti_land: Dictionary = application.temporally_unavailable_land_status(
		"cshapes_gw_522"
	)
	_check(
		application._countries.size() == 151
		and int(jan1_evidence.get("temporally_unavailable_count", -1)) == 5
		and int(jan1_evidence.get("physical_reference_land_count", -1)) == 5
		and not bool(jan1_evidence.get("political_truth_complete", true))
		and str(djibouti_land.get("physical_land_status", ""))
			== "PRESENT · REFERENCE GEOMETRY"
		and str(djibouti_land.get("political_identity_status", ""))
			== VNextFactProvenance.TEMPORALLY_UNKNOWN
		and not bool(djibouti_land.get("predecessor_available", true))
		and not application._country_anchor_units.has(
			str(djibouti_land.get("render_id", ""))
		),
		"January gaps keep non-selectable physical land while political truth is explicit"
	)
	_check(
		application._prototype_presentation_count() == 0
		and application.product_spatial_projection.normal_city_views("country_fra").is_empty()
		and application.product_spatial_projection.normal_region_views("country_fra").is_empty(),
		"R1-15 Wave 1 product still excludes prototype local/city truth"
	)
	var before_hour: int = application.formal_simulation.economy.total_hour
	var summary: Dictionary = application.formal_simulation.advance_minutes(60)
	_check(
		application.formal_simulation.economy.total_hour == before_hour + 1
		and int(summary.get("major_economy_count", 0)) == 50,
		"R1-16 Formal clock and Formal Economy remain active"
	)
	application._advance_simulation_minutes(23 * 24 * 60 - 60)
	_check(
		application._political_query_date() == "1900-01-24"
		and application._history_entity_by_id.size() == 148,
		"R1-13 actual product activates the January 24 political records"
	)
	application._advance_simulation_minutes(5 * 24 * 60)
	_check(
		application._political_query_date() == "1900-01-29"
		and application._history_entity_by_id.size() == 151,
		"R1-13 actual product activates the January 29 political records"
	)
	application._advance_simulation_minutes(42 * 24 * 60)
	_check(
		application._political_query_date() == "1900-03-12"
		and application._history_entity_by_id.size() == 151,
		"R1-14 actual product queries the March 12 reference date"
	)
	var owners: Dictionary = _owners_by_label(
		application.product_runtime_provenance().get("owners", []) as Array
	)
	var runtime_provenance: Dictionary = application.product_runtime_provenance()
	print("R1 CLOSURE base_head=%s worktree=%s patch_sha256=%s" % [
		str(runtime_provenance.get("base_head", "")),
		str(runtime_provenance.get("working_tree_status", "")),
		str(runtime_provenance.get("patch_sha256", "")),
	])
	_check(
		str((owners.get("POPULATION OWNER", {}) as Dictionary).get("status", "")) == "NOT INTEGRATED"
		and str((owners.get("VNEXT POPULATION CONSUMER", {}) as Dictionary).get("status", "")) == "NO",
		"R1-17/R1-18 no Economy consumer or product UI claims Population integration"
	)
	var provenance_head := str(runtime_provenance.get("base_head", ""))
	var worktree_status := str(runtime_provenance.get("working_tree_status", ""))
	var patch_sha256 := str(runtime_provenance.get("patch_sha256", ""))
	var review_patch_state := (
		provenance_head == "18fe9c52d3f97505a50e3bcc6dc095aa8f217c7e"
		and worktree_status == "DIRTY"
		and patch_sha256.length() == 64
	)
	var checkpoint_state := (
		provenance_head.length() == 40
		and worktree_status == "CLEAN"
		and patch_sha256 == "NONE"
	)
	_check(
		(review_patch_state or checkpoint_state)
		and str(runtime_provenance.get("product_entry", ""))
			== "res://scenes/formal/formal_world_menu.tscn"
		and str(runtime_provenance.get("runtime_scene", "")) == PRODUCT_SCENE,
		"closure evidence identifies the review patch or clean checkpoint and actual entry"
	)
	var economy_source: String = FileAccess.get_file_as_string("res://scripts/formal/formal_world_economy_service.gd")
	_check(not economy_source.contains("VNextPopulationEvidenceProvider"), "R1-17 Formal Economy does not consume Population provider")
	application.queue_free()
	current_scene = null
	await process_frame


func _allocation(target_id: String, weight: int, coverage: int, unresolved: int) -> Dictionary:
	return {
		"source_type": VNextTypedCrosswalkCatalog.POPULATION_UNIT,
		"source_id": "population:country_fra",
		"target_type": VNextTypedCrosswalkCatalog.SPATIAL_REGION,
		"target_id": target_id,
		"measure": "population",
		"mapping_kind": VNextTypedCrosswalkCatalog.ALLOCATION,
		"applicability": VNextFactProvenance.HISTORICALLY_SUPPORTED,
		"valid_from": "1900-01-01",
		"valid_to": "1900-12-31",
		"provenance_id": "allocation_test",
		"allocation_weight_bp": weight,
		"coverage_bp": coverage,
		"unresolved_bp": unresolved,
	}


func _legacy_spatial_snapshot(
	v2_snapshot: Dictionary, catalog: VNextSpatialCatalog
) -> Dictionary:
	var legacy: Dictionary = v2_snapshot.duplicate(true)
	legacy["schema_id"] = VNextSpatialWorld.LEGACY_SNAPSHOT_SCHEMA_ID
	var rows: Array[Dictionary] = []
	for entity_id: String in catalog.place_map_ids():
		var place: Dictionary = catalog.get_place(entity_id)
		var entity_kind: String = str(
			place.get("object_level", place.get("spatial_kind", ""))
		)
		var parent_id: String = ""
		if entity_kind != "region":
			parent_id = str(place.get("parent_region_id", ""))
		var owner_id: String = str(place.get("parent_country_id", ""))
		rows.append({
			"entity_id": entity_id,
			"entity_kind": entity_kind,
			"sovereign_owner_id": owner_id,
			"administrative_parent_id": parent_id,
			"military_controller_id": owner_id,
		})
	legacy["territories"] = rows
	return legacy


func _state(total: int) -> Dictionary:
	return {
		"total_population": total,
		"age_buckets": {
			"under_18": 10_000_000, "age_18_40": 13_000_000,
			"age_41_64": 12_000_000, "age_65_plus": 5_700_000,
		},
		"sex_structure": {"female": 20_400_000, "male": 20_300_000},
		"urban_rural": {"urban": 16_280_000, "rural": 24_420_000},
	}


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _owners_by_label(values: Array) -> Dictionary:
	var output: Dictionary = {}
	for raw_value: Variant in values:
		if raw_value is Dictionary:
			var value := raw_value as Dictionary
			output[str(value.get("label", ""))] = value
	return output


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("Wave 2A-R1: " + label)
