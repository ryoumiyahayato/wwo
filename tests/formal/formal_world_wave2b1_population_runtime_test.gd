extends SceneTree
## Wave 2B-1 contract for one truthful Population owner in the actual product.

const MENU_SCENE: String = "res://scenes/formal/formal_world_menu.tscn"
const PRODUCT_SCENE: String = "res://scenes/formal/formal_world_main.tscn"
const FRANCE_POLITICAL_ID: String = "country_fra"
const FRANCE_POPULATION_ID: String = "population:country_fra"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(
		str(ProjectSettings.get_setting("application/run/main_scene", "")) == MENU_SCENE,
		"2B1-01 actual default entry remains the Formal menu"
	)
	var packed := load(PRODUCT_SCENE) as PackedScene
	_check(packed != null, "2B1-02 actual Formal product scene loads")
	if packed == null:
		_finish()
		return
	var application := packed.instantiate() as FormalWorldApplication
	_check(application != null, "2B1-03 actual root constructs FormalWorldApplication")
	if application == null:
		_finish()
		return
	get_root().add_child(application)
	current_scene = application
	await process_frame
	await process_frame

	_check_owner(application)
	_check_evidence(application)
	_check_geographic_boundary(application)
	_check_economy_and_economic_geography(application)
	_check_temporal_regression(application)
	_check_persistence(application)
	_measure(application)

	application.queue_free()
	current_scene = null
	await process_frame
	_finish()


func _check_owner(application: FormalWorldApplication) -> void:
	var owner: VNextMacroPopulation = application._vnext_population
	var projection: ProductPopulationProjection = application.product_population_projection
	_check(
		owner != null and owner.is_read_only_evidence_owner(),
		"2B1-04 actual product constructs the immutable vNext Population owner"
	)
	if owner == null:
		return
	_check(
		projection.is_valid()
		and projection.owner_instance_id() == owner.get_instance_id(),
		"2B1-05 product adapter references exactly the constructed Population owner"
	)
	var owners := _owners_by_label(
		application.product_runtime_provenance().get("owners", []) as Array
	)
	var population_owner := owners.get("POPULATION OWNER", {}) as Dictionary
	_check(
		str(population_owner.get("status", "")) == "ACTIVE"
		and str(population_owner.get("owner", "")) == "VNextMacroPopulation"
		and "AUTHORITATIVE DEMOGRAPHIC OWNER" in str(population_owner.get("mode", "")),
		"2B1-06 runtime-derived provenance reports the real Population owner"
	)
	var gate: Dictionary = application.product_integration_gate_report()
	_check(
		str(gate.get("population_single_owner", "")) == "PASS",
		"2B1-07 uniqueness gate proves one Population owner"
	)


func _check_evidence(application: FormalWorldApplication) -> void:
	var owner: VNextMacroPopulation = application._vnext_population
	var projection: ProductPopulationProjection = application.product_population_projection
	_check(
		owner.supported_fact_count() == 50
		and owner.record_count() == 50
		and projection.supported_fact_count() == 50,
		"2B1-08 reviewed 50 aggregate facts are active"
	)
	_check(
		owner.has_population_unit(FRANCE_POPULATION_ID)
		and owner.population_at(FRANCE_POPULATION_ID) == 40_700_000
		and not owner.has_population_unit("place:country_fra")
		and not owner.has_population_unit("region:country_fra"),
		"2B1-09 canonical Population identity and alias rejection survive activation"
	)
	var fact: Dictionary = projection.evidence_at(FRANCE_POPULATION_ID)
	var provenance: Dictionary = fact.get("provenance", {}) as Dictionary
	_check(
		int(fact.get("total_population", -1)) == 40_700_000
		and int(fact.get("lower_bound", -1)) < 40_700_000
		and int(fact.get("upper_bound", -1)) > 40_700_000
		and int(fact.get("confidence_bp", -1)) > 0
		and str(provenance.get("precision", "")) == VNextFactProvenance.ESTIMATED
		and str(provenance.get("applicability", "")) == VNextFactProvenance.NEAR_1900_SUPPORTED
		and str(provenance.get("valid_from", "")) == "1900-01-01"
		and str(provenance.get("reference_date", "")) == "1900-01-01"
		and (fact.get("source_manifest", []) as Array).size() >= 4,
		"2B1-10 precision, applicability, dates, bounds, confidence and source lineage remain intact"
	)
	_check(
		bool(fact.get("authoritative_runtime_demographic_state", false))
		and not bool(fact.get("exact_historical_observation", true))
		and str(fact.get("demographic_detail_status", "")) == "NOT AVAILABLE",
		"2B1-11 runtime authority does not promote estimated evidence to exact"
	)
	_check(
		owner.working_age_at(FRANCE_POPULATION_ID) == -1
		and owner.age_bucket_at(FRANCE_POPULATION_ID, "age_18_40") == -1
		and owner.structure_at(FRANCE_POPULATION_ID).is_empty()
		and not owner.settle_elapsed_months(1),
		"2B1-12 unsupported demographic detail and mutation remain unavailable"
	)
	var snapshot: Dictionary = projection.observation_snapshot()
	_check(
		str(snapshot.get("schema_id", "")) == VNextMacroPopulation.OBSERVATION_SCHEMA_ID
		and int(snapshot.get("supported_fact_count", -1)) == 50
		and (snapshot.get("facts", []) as Array).size() == 50,
		"2B1-13 immutable observer snapshot contains the active facts"
	)
	var first_fact := (snapshot.get("facts", []) as Array)[0] as Dictionary
	var original_id: String = str(first_fact.get("population_unit_id", ""))
	first_fact["population_unit_id"] = "population:mutated_copy"
	_check(
		str((projection.observation_snapshot().get("facts", []) as Array)[0].get("population_unit_id", ""))
			== original_id,
		"2B1-14 observer snapshots are immutable copies"
	)


func _check_geographic_boundary(application: FormalWorldApplication) -> void:
	var projection: ProductPopulationProjection = application.product_population_projection
	var selection: Dictionary = projection.geographic_selection_view(
		FRANCE_POLITICAL_ID, "1900-01-01"
	)
	_check(
		projection.crosswalk_count() == 0
		and projection.crosswalk_status() == "EMPTY / NOT AVAILABLE"
		and str(selection.get("status", "")) == ProductPopulationProjection.GEOGRAPHIC_UNAVAILABLE
		and str(selection.get("population_unit_id", "x")).is_empty()
		and not bool(selection.get("crosswalk_used", true))
		and selection.get("population") == null,
		"2B1-15 unsupported PoliticalUnit query is explicitly unavailable with no crosswalk"
	)
	_check(
		projection.regional_view("place:northern_industrial_belt").get("population") == null
		and not bool(projection.regional_view("place:northern_industrial_belt").get("crosswalk_used", true))
		and projection.city_view("city:paris").get("population") == null
		and not bool(projection.city_view("city:paris").get("crosswalk_used", true)),
		"2B1-16 no country-total regional division or city Population inference exists"
	)
	_check(
		str(application.product_integration_gate_report().get("population_geographic_crosswalk", "")) == "PASS",
		"2B1-17 product gate detects any invented geographic mapping"
	)
	application.selected_country_id = FRANCE_POLITICAL_ID
	application._open_product_panel("population")
	_check(
		application.active_hud_panel == "population"
		and application._population_runtime_status().get("geographic_projection")
			== "LIMITED / NOT AVAILABLE",
		"2B1-18 actual product exposes the fail-closed Population observation panel"
	)


func _check_economy_and_economic_geography(application: FormalWorldApplication) -> void:
	var owners := _owners_by_label(
		application.product_runtime_provenance().get("owners", []) as Array
	)
	_check(
		str((owners.get("ECONOMY OWNER", {}) as Dictionary).get("owner", ""))
			== "FormalWorldEconomyService"
		and str((owners.get("VNEXT POPULATION CONSUMER", {}) as Dictionary).get("status", "")) == "NO",
		"2B1-19 Formal Economy remains active and does not consume vNext Population"
	)
	var economy_source := FileAccess.get_file_as_string(
		"res://scripts/formal/formal_world_economy_service.gd"
	)
	_check(
		not economy_source.contains("VNextMacroPopulation")
		and not economy_source.contains("VNextPopulationEvidenceProvider"),
		"2B1-20 no Population dependency entered Formal Economy"
	)
	_check(
		application._economic_region_catalog != null
		and application._economic_region_catalog.status() == "EMPTY / NOT AVAILABLE"
		and application.product_population_projection.economic_geography_status()
			== "EMPTY / NOT AVAILABLE",
		"2B1-21 Economic Geography remains honestly empty"
	)


func _check_temporal_regression(application: FormalWorldApplication) -> void:
	var evidence: Dictionary = application.historical_evidence_report()
	_check(
		application._political_query_date() == "1900-01-01"
		and int(evidence.get("unit_count", -1)) == 146
		and int(evidence.get("temporally_unavailable_count", -1)) == 5
		and int(evidence.get("physical_reference_land_count", -1)) == 5,
		"2B1-22 January 1 remains 146 active records plus five explicit land gaps"
	)
	for unit_id: String in [
		"cshapes_gw_522", "cshapes_gw_531", "cshapes_gw_552",
		"cshapes_gw_5518", "cshapes_gw_5519",
	]:
		var land: Dictionary = application.temporally_unavailable_land_status(unit_id)
		var selection: Dictionary = application.product_population_projection.geographic_selection_view(
			unit_id, "1900-01-01"
		)
		_check(
			str(land.get("physical_geometry_applicability", "")) == "REFERENCE_ONLY"
			and str(land.get("political_identity_status", "")) == "TEMPORALLY_UNKNOWN"
			and selection.get("population") == null
			and not bool(selection.get("crosswalk_used", true)),
			"2B1-23 temporal gap remains physical and receives no Population mapping: " + unit_id
		)


func _check_persistence(application: FormalWorldApplication) -> void:
	var owner: VNextMacroPopulation = application._vnext_population
	var before: Dictionary = application.product_population_projection.observation_snapshot()
	var formal_state: Dictionary = application.formal_simulation.get_persistent_state()
	_check(
		not formal_state.has("population")
		and not formal_state.has("population_facts")
		and str(application.product_population_projection.persistence_reference().get("state_kind", ""))
			== "IMMUTABLE_INITIALIZATION_DERIVED",
		"2B1-24 immutable evidence catalog is not duplicated into the Formal save"
	)
	application.formal_simulation.advance_minutes(180)
	_check(
		application.formal_simulation.restore_persistent_state(formal_state)
		and application.product_population_projection.observation_snapshot() == before
		and owner.population_at(FRANCE_POPULATION_ID) == 40_700_000,
		"2B1-25 Formal restore leaves immutable Population authority unchanged"
	)
	var reference: Dictionary = application.product_population_projection.persistence_reference()
	var incompatible: Dictionary = reference.duplicate(true)
	incompatible["provider_revision"] = "incompatible_revision"
	_check(
		application.product_population_projection.is_persistence_reference_compatible(reference)
		and not application.product_population_projection.is_persistence_reference_compatible(incompatible)
		and application._population_runtime_compatible(),
		"2B1-26 incompatible provider revisions fail closed"
	)


func _measure(application: FormalWorldApplication) -> void:
	var projection: ProductPopulationProjection = application.product_population_projection
	var snapshot_started := Time.get_ticks_usec()
	var snapshot: Dictionary = projection.observation_snapshot()
	var snapshot_usec := Time.get_ticks_usec() - snapshot_started
	var ids: Array[String] = projection.population_unit_ids()
	var queries_started := Time.get_ticks_usec()
	var checksum: int = 0
	for index: int in range(10_000):
		checksum += application._vnext_population.population_at(ids[index % ids.size()])
	var query_usec := Time.get_ticks_usec() - queries_started
	_check(not snapshot.is_empty() and checksum > 0, "2B1-27 measured queries return actual indexed evidence")
	print(
		"W2B1 PERFORMANCE owner_init_usec=%d snapshot_usec=%d indexed_queries_10000_usec=%d"
		% [application._population_construction_usec, snapshot_usec, query_usec]
	)


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
	push_error("Wave 2B-1: " + label)


func _finish() -> void:
	print("Wave 2B-1 Population runtime: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
