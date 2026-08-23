extends SceneTree
## Wave 1 contract for the actual Formal product Spatial composition.

const MENU_SCENE := "res://scenes/formal/formal_world_menu.tscn"
const PRODUCT_SCENE := "res://scenes/formal/formal_world_main.tscn"
const FRANCE_ID := "country_fra"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(PRODUCT_SCENE) as PackedScene
	_check(packed != null, "actual Formal product scene loads")
	if packed == null:
		_finish()
		return
	var application := packed.instantiate() as FormalWorldApplication
	_check(application != null, "actual root constructs FormalWorldApplication")
	if application == null:
		_finish()
		return
	get_root().add_child(application)
	current_scene = application
	await process_frame
	await process_frame
	_check_owner_composition(application)
	_check_applicability_boundary(application)
	_check_read_only_projection(application)
	_check_entry_and_fixture_boundary(application)
	_check_stable_ordering()
	_check_runtime_provenance(application)
	_check_legacy_capacity_fence()
	_measure_queries(application)
	application.queue_free()
	current_scene = null
	await process_frame
	_finish()


func _check_owner_composition(application: FormalWorldApplication) -> void:
	# W1-01
	_check(
		application._vnext_spatial_world != null
		and application._vnext_spatial_world.is_valid(),
		"W1-01 real product root constructs vNext Spatial"
	)
	# W1-02
	_check(
		application.product_spatial_projection.owner_instance_id()
		== application._vnext_spatial_world.get_instance_id(),
		"W1-02 product projection references the one constructed Spatial owner"
	)
	# W1-03
	var owners := _owners_by_label(
		application.product_runtime_provenance().get("owners", []) as Array
	)
	_check(
		_owner_name(owners, "POLITICAL GEOMETRY PROJECTION") == "FormalWorldApplication"
		and _owner_name(owners, "VNEXT SPATIAL OWNER") == "VNextSpatialWorld",
		"W1-03 political projection and vNext Spatial are semantically distinct"
	)


func _check_applicability_boundary(application: FormalWorldApplication) -> void:
	var projection := application.product_spatial_projection
	# W1-04
	_check(
		projection.normal_region_views(FRANCE_ID).is_empty()
		and projection.source_applicability("regions")
		== ProductSpatialApplicability.PROTOTYPE_ONLY,
		"W1-04 modern Admin-1/gameplay regions cannot become 1900 local political truth"
	)
	# W1-05
	_check(
		projection.normal_city_views(FRANCE_ID).is_empty(),
		"W1-05 prototype Spatial records cannot become normal product truth"
	)
	# W1-06
	var reference_city := projection._city_identity_view({
		"place_id": "place:reference_city",
		"name": "Reference City",
		"lon_lat": [1.0, 2.0],
	}, ProductSpatialApplicability.REFERENCE_ONLY)
	_check(
		str(reference_city.get("stable_id", "")) == "place:reference_city"
		and str(reference_city.get("name", "")) == "Reference City"
		and (reference_city.get("location", []) as Array) == [1.0, 2.0]
		and not bool(reference_city.get("normal_product_eligible", true))
		and str(reference_city.get("population", "")) == ProductSpatialApplicability.UNAVAILABLE
		and str(reference_city.get("economy", "")) == ProductSpatialApplicability.UNAVAILABLE
		and str(reference_city.get("politics", "")) == ProductSpatialApplicability.UNAVAILABLE,
		"W1-06 reference-only city exposes identity/location without invented state"
	)
	# W1-07
	var paris := projection.city_reference("paris")
	_check(
		str(paris.get("population", "")) == ProductSpatialApplicability.UNAVAILABLE
		and not paris.has("regional_population"),
		"W1-07 regional population is never projected as city population"
	)
	# W1-08
	var local := projection.historical_local_geography_status(FRANCE_ID)
	_check(
		str(local.get("status", "")) == "NOT AVAILABLE"
		and not bool(local.get("normal_product_eligible", true)),
		"W1-08 unsupported historical subdivision remains unavailable"
	)
	# W1-09
	var infrastructure := projection.infrastructure_historical_status(FRANCE_ID)
	var infrastructure_counts := projection.infrastructure_reference_counts(FRANCE_ID)
	_check(
		str(infrastructure.get("status", "")) == "NOT AVAILABLE"
		and not bool(infrastructure.get("normal_product_eligible", true)),
		"W1-09 unsupported infrastructure attributes remain unavailable"
	)
	_check(
		infrastructure_counts == {
			"ports": 5, "roads": 3, "rail": 9, "shipping": 3,
		},
		"W1-09 developer infrastructure reference counts use exact class keys"
	)


func _check_read_only_projection(application: FormalWorldApplication) -> void:
	# W1-10
	var first := application.product_spatial_projection.city_reference("paris")
	first["name"] = "MUTATED PRESENTATION COPY"
	(first.get("location", []) as Array).clear()
	var second := application.product_spatial_projection.city_reference("paris")
	_check(
		str(second.get("name", "")) != "MUTATED PRESENTATION COPY"
		and (second.get("location", []) as Array).size() == 2,
		"W1-10 UI projection copies cannot mutate Spatial authoritative state"
	)


func _check_entry_and_fixture_boundary(application: FormalWorldApplication) -> void:
	# W1-11
	_check(
		str(ProjectSettings.get_setting("application/run/main_scene", "")) == MENU_SCENE
		and str(FormalWorldMenu.WORLD_SCENE) == PRODUCT_SCENE,
		"W1-11 default product entry remains the real Formal menu/main"
	)
	# W1-12
	var prototype_document := {"prototype_only": true, "cities": [{"id": "fixture"}]}
	_check(
		application._fixture_dependency_count() == 0
		and ProductSpatialApplicability.classify_document(prototype_document)
		== ProductSpatialApplicability.PROTOTYPE_ONLY
		and not ProductSpatialApplicability.may_present_as_normal_truth(
			ProductSpatialApplicability.classify_document(prototype_document)
		),
		"W1-12 prototype/test fixtures cannot satisfy product presentation eligibility"
	)


func _check_stable_ordering() -> void:
	# W1-13
	var documents := _catalog_documents()
	var reordered := documents.duplicate(true)
	for pair: Array in [
		["countries", "countries"], ["regions", "regions"],
		["cities", "cities"], ["ports", "ports"],
		["roads", "segments"], ["rail", "segments"],
		["shipping", "routes"],
	]:
		var document := reordered[str(pair[0])] as Dictionary
		var records := document[str(pair[1])] as Array
		records.reverse()
	var first := VNextSpatialCatalog.new()
	var second := VNextSpatialCatalog.new()
	_check(
		first.load_from_documents(documents)
		and second.load_from_documents(reordered)
		and first.place_ids() == second.place_ids()
		and first.link_ids() == second.link_ids(),
		"W1-13 reordered Spatial source input preserves stable identity output"
	)


func _check_runtime_provenance(application: FormalWorldApplication) -> void:
	# W1-14
	var provenance := application.product_runtime_provenance()
	var owners := _owners_by_label(provenance.get("owners", []) as Array)
	_check(
		_owner_name(owners, "VNEXT SPATIAL OWNER") == "VNextSpatialWorld"
		and str((owners.get("VNEXT SPATIAL OWNER", {}) as Dictionary).get("status", "")) == "ACTIVE"
		and str((owners.get("HISTORICAL LOCAL GEOGRAPHY STATUS", {}) as Dictionary).get("status", "")) == "NOT AVAILABLE"
		and str(provenance.get("product_entry", "")) == MENU_SCENE
		and str(provenance.get("runtime_scene", "")) == PRODUCT_SCENE,
		"W1-14 runtime provenance reports actual constructed owners and data status"
	)
	_check(
		str(provenance.get("build_head", "")).length() == 40,
		"W1-14 worktree runtime provenance resolves an actual build HEAD"
	)


func _check_legacy_capacity_fence() -> void:
	# W1-15
	var source := FileAccess.get_file_as_string(
		"res://scripts/formal/product_spatial_projection.gd"
	)
	_check(
		not source.contains(".reserve_capacity(")
		and not source.contains(".request_capacity(")
		and not source.contains(".request_capacity_batch(")
		and not source.contains(".set_nominal_capacity("),
		"W1-15 production adapter uses no legacy direct-capacity reservation API"
	)


func _measure_queries(application: FormalWorldApplication) -> void:
	application._ensure_projection_cache()
	print("W1 FRANCE_ANCHOR %s" % str(
		application._country_screen_anchors.get(FRANCE_ID, Vector2.INF)
	))
	var local_started := Time.get_ticks_usec()
	application.product_spatial_projection.historical_local_geography_status(FRANCE_ID)
	var local_usec := Time.get_ticks_usec() - local_started
	var city_started := Time.get_ticks_usec()
	application.product_spatial_projection.city_reference("paris")
	var city_usec := Time.get_ticks_usec() - city_started
	print("W1 PERFORMANCE construction_usec=%d country_local_query_usec=%d city_query_usec=%d" % [
		application._spatial_construction_usec, local_usec, city_usec,
	])
	_check(application._spatial_construction_usec > 0, "Spatial construction measurement is recorded")


func _catalog_documents() -> Dictionary:
	var output: Dictionary = {}
	for key: String in VNextSpatialCatalog.SOURCE_PATHS:
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(str(VNextSpatialCatalog.SOURCE_PATHS[key]))
		)
		output[key] = (parsed as Dictionary).duplicate(true)
	return output


func _owners_by_label(owner_values: Array) -> Dictionary:
	var output: Dictionary = {}
	for owner_value: Variant in owner_values:
		if owner_value is Dictionary:
			var owner := owner_value as Dictionary
			output[str(owner.get("label", ""))] = owner
	return output


func _owner_name(owners: Dictionary, label: String) -> String:
	return str((owners.get(label, {}) as Dictionary).get("owner", ""))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("Wave 1 Spatial: " + message)


func _finish() -> void:
	print("Wave 1 Spatial: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
