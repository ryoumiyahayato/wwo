class_name WorldBootstrap
extends RefCounted
## Creates fresh components and their explicit references. Not a runtime owner.

const TERRITORIAL_CONTROL_OWNER: String = "TerritoryState"
const TERRITORY_AUTHORITY_PRODUCTION_STATUS: String = "TERRITORY_STATE_SINGLE_AUTHORITY"
const DEFAULT_FORMAL_PERSON_ID: String = "person:formal_generated_country_fra_0001"
const DEFAULT_FORMAL_PERSON_CLAIM_ID: String = "formal_population_claim:country_fra:0001"
const DEFAULT_FORMAL_PERSON_TERRITORY_ID: String = "country_fra"
const DEFAULT_FORMAL_PERSON_PLACE_ID: String = "place:paris"

static func opening_profile(source_id: String) -> Dictionary:
	# Existing formal places and historical political IDs; no invented jobs/names.
	var profiles := {
		"country_fra":{"place_id":"place:paris","place_name":"巴黎","person_id":DEFAULT_FORMAL_PERSON_ID},
		"british_isles_1900":{"place_id":"place:london","place_name":"伦敦","place_parent_source_id":"british_empire","person_id":"person:formal_generated_british_isles_1900_0001"},
		"german_empire":{"place_id":"place:berlin","place_name":"柏林","person_id":"person:formal_generated_german_empire_0001"},
		"russian_empire":{"place_id":"place:st_petersburg","place_name":"圣彼得堡","person_id":"person:formal_generated_russian_empire_0001"}}
	var profile := profiles.get(source_id,{}) as Dictionary
	if not profile.is_empty(): profile["source_id"] = source_id
	return profile

func build(organization_state_value: OrganizationState = null, organization_person_reference_ids: Array[String] = [], organization_place_reference_ids: Array[String] = [], livelihood: String = FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, initialize_land_administration: bool = true, native_economy_config: Dictionary = {}, opening_source_id: String = DEFAULT_FORMAL_PERSON_TERRITORY_ID, prepared_provenance: HistoricalProvenanceFoundation = null) -> WorldBuildResult:
	var r := WorldBuildResult.new()
	r.world.game_clock = GameClock.new()
	r.world.provenance = prepared_provenance if prepared_provenance!=null else HistoricalProvenanceFoundation.new()
	r.world.historical_evidence = HistoricalPoliticalEvidenceCatalog.new()
	r.world.political_registry = RuntimePoliticalEntityRegistry.new()
	r.world.economic_evidence = FormalWorldEconomicEvidenceCatalog.new()
	r.world.market_registry = FormalWorldMarketRegistry.new()
	r.world.economy_state = FormalWorldEconomyState.new()
	r.world.spatial_catalog = VNextSpatialCatalog.new()
	r.world.organization_evidence = FormalWorldOrganizationEvidenceCatalog.new()
	r.organization_person_reference_ids = organization_person_reference_ids.duplicate()
	r.organization_person_reference_ids.sort()
	r.organization_place_reference_ids = organization_place_reference_ids.duplicate()
	r.organization_place_reference_ids.sort()
	r.explicit_organization_reference_injection = (
		organization_state_value != null
		or not r.organization_person_reference_ids.is_empty()
		or not r.organization_place_reference_ids.is_empty()
	)
	r.world.organization_state = (
		organization_state_value
		if organization_state_value != null
		else OrganizationState.new()
	)
	if r.explicit_organization_reference_injection:
		var reference_catalog := VNextOrganizationReferenceCatalog.create(
			r.organization_person_reference_ids,
			r.organization_place_reference_ids
		)
		if reference_catalog == null:
			r.error = "Organization reference provider is invalid"
		elif not r.world.organization_state.has_reference_catalog():
			if not r.world.organization_state.configure_reference_catalog(
				r.organization_person_reference_ids,
				r.organization_place_reference_ids
			):
				r.error = (
					"Organization reference provider is missing or cannot be bound"
				)
		elif (
			r.world.organization_state.reference_catalog_fingerprint()
			!= reference_catalog.fingerprint()
		):
			r.error = (
				"Organization reference provider does not match the injected state"
			)
	r.world.economy_state.bind_authoritative_hour_source(Callable(r.world.game_clock, "current_hour"))

	if r.world.organization_state == null or not r.error.is_empty():
		r.error = (
			r.error
			if not r.error.is_empty()
			else "Organization composition is invalid"
		)
		return _failure(r)
	if not r.world.provenance.is_loaded() and not r.world.provenance.load_current():
		r.error = r.world.provenance.initialization_error
		return _failure(r)
	if not r.world.historical_evidence.configure(
		HistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,
		r.world.provenance.gate()
	):
		r.error = r.world.historical_evidence.initialization_error
		return _failure(r)
	if not r.world.organization_evidence.configure(r.world.historical_evidence):
		r.error = r.world.organization_evidence.initialization_error
		return _failure(r)
	if not r.world.political_registry.configure(r.world.historical_evidence):
		r.error = r.world.political_registry.initialization_error
		return _failure(r)
	if not r.world.economic_evidence.configure(r.world.provenance.gate()):
		r.error = r.world.economic_evidence.initialization_error
		return _failure(r)
	_refresh_read_only_views(r)
	if not _configure_spatial_composition(r,initialize_land_administration):
		return _failure(r)
	if not _configure_population_composition(r,opening_source_id):
		return _failure(r)
	if not _configure_formal_person_composition(r,opening_source_id,native_economy_config):
		return _failure(r)
	if not _configure_personal_economy_composition(r, livelihood):
		return _failure(r)
	r.world.person_overlay.bind_formal_space(r.world)
	if not _configure_production_organization_composition(r):
		return _failure(r)
	if not _configure_authorization(r):
		return _failure(r)
	if not _configure_military_composition(r):
		return _failure(r)
	if not _configure_market_registry(r):
		r.error = r.world.market_registry.initialization_error
		return _failure(r)
	r.world.market_registry_view = FormalWorldMarketView.new(r.world.market_registry.read_only_snapshot())
	if not r.world.economy_state.configure(
		r.world.political_registry_view,
		r.world.market_registry_view,
		r.world.economic_static_view,
		r.world.population_input_view,
		r.world.population_state
	):
		r.error = r.world.economy_state.initialization_error
		return _failure(r)
	r.economy_simulation = FormalWorldEconomySimulation.new(r.world.economy_state)
	if not r.economy_simulation.initialize_state():
		r.error = r.world.economy_state.initialization_error
		return _failure(r)
	r.world.economy_state.bind_personal_ledger(r.world.ledger_state)
	r.world.personal_economy_state.bind_market(r.world.economy_state)
	r.world.economy_state.bind_personal_economy(r.world.personal_economy_state)
	r.world.person_travel = FormalPersonTravel.new()
	r.world.person_travel.bind(r.world)
	r.world.personal_economy_state.bind_travel(r.world.person_travel)
	if not native_economy_config.is_empty():
		_configure_native_economy(r, native_economy_config)
		if not r.error.is_empty(): return _failure(r)
	if r.world.economy_r1 != null and not r.world.economy_r1.config.has("person_travel") and not r.world.person_travel.configure(EconomyDevelopmentConfig.formal_passenger_routes(r.world)):
		r.error = r.world.person_travel.error
		return _failure(r)
	if r.world.economy_r1 != null and not r.world.economy_r1.config.has("person_travel"):
		r.world.person_travel.configure_notices(EconomyDevelopmentConfig.formal_arrival_notices(r.world.economy_r1.config))
	if not _configure_organization_responsibilities(r, r.world.game_clock.current_hour()):
		return _failure(r)
	r.success = true
	r.simulation_step = SimulationStep.new(r.world.game_clock, r.world.spatial_world, r.world.economy_state, r.economy_simulation, r.world.organization_responsibility, r.world.organization_state, r.world.political_registry_view, r.world.personal_economy_state, r.world.economy_r1, r.world.person_travel)
	r.persistence = FormalPersistence.new(r.world, r.organization_person_reference_ids, r.organization_place_reference_ids, r.explicit_organization_reference_injection)
	r.persistence.bind_step(r.simulation_step)
	return r

func _refresh_read_only_views(r: WorldBuildResult) -> void:
	r.world.historical_evidence_view = HistoricalPoliticalEvidenceView.new(
		r.world.historical_evidence.read_only_snapshot()
	)
	r.world.organization_evidence_view = FormalWorldOrganizationEvidenceView.new(
		r.world.organization_evidence.read_only_snapshot()
	)
	r.world.political_registry_view = RuntimePoliticalEntityView.new(
		r.world.political_registry.snapshot()
	)
	r.world.economic_static_view = FormalWorldEconomicStaticView.new(
		r.world.economic_evidence.economic_snapshot()
	)
	r.world.population_input_view = FormalWorldPopulationInputView.new(
		r.world.economic_evidence.population_snapshot()
	)

func _configure_spatial_composition(r: WorldBuildResult, initialize_land_administration: bool) -> bool:
	if not r.world.spatial_catalog.load_legacy_world_map():
		r.error = "Formal Spatial catalog could not load source topology"
		return false
	r.world.spatial_world = VNextSpatialWorld.create(r.world.spatial_catalog)
	if r.world.spatial_world == null or not r.world.spatial_world.is_valid():
		r.error = "Formal Spatial authority could not be composed"
		return false
	r.world.territory_state = TerritoryState.new()
	var pilot := LandPilotLoader.new()
	if not pilot.load_current(r.world.provenance.gate(),r.world.political_registry) or not r.world.spatial_world.install_land(pilot.topology,pilot.initial_politics,r.world.political_registry):
		r.error = "Formal land admission failed: " + pilot.error
		return false
	var administrations := AdministrativeLoader.new()
	administrations.load_france_identity(r.world.provenance.gate())
	if not administrations.errors.is_empty() or not r.world.spatial_world.configure_land_administrations(administrations.france_identity,administrations.france_boundaries):
		r.error = "Formal land administrative identities unavailable"
		return false
	administrations.load_reference_identities()
	for reference: Dictionary in administrations.reference_documents:
		if not r.world.spatial_world.configure_land_administrations(reference.identity,reference.boundaries):
			r.error = "Historical administrative reference could not be installed: "+str(reference.identity.entity_id)
			return false
	if not administrations.errors.is_empty():
		r.error = "; ".join(administrations.errors)
		return false
	r.world.territory_state.bind_land_scope(pilot.topology,r.world.political_registry)
	var controllers: Dictionary = {}
	var control_ids := r.world.spatial_catalog.place_map_ids()
	for place_id: String in r.world.spatial_catalog.place_map_ids():
		controllers[place_id] = str(r.world.spatial_catalog.get_place(place_id)["parent_country_id"])
	for id: String in pilot.topology.land_ids():
		controllers[id] = (pilot.initial_politics.land_overrides as Dictionary).get(id,pilot.initial_politics).get("controller_polity_id","")
		control_ids.append(id)
	if not r.world.territory_state.restore({"schema_id": TerritoryState.SCHEMA_ID, "controllers": controllers}, control_ids):
		r.error = r.world.territory_state.error
		return false
	if initialize_land_administration and not r.world.spatial_world.apply_historical_land_administration(r.world.territory_state,HistoricalLoader._date_key(r.world.game_clock.current_date())):
		r.error = "Historical land administration could not be initialized"
		return false
	if r.world.spatial_world.current_hour() != r.world.game_clock.current_hour():
		r.error = "Spatial initial hour %d differs from GameClock hour %d" % [r.world.spatial_world.current_hour(), r.world.game_clock.current_hour()]
		return false
	return true

func _configure_population_composition(r: WorldBuildResult, opening_source_id: String) -> bool:
	var input := r.world.economic_evidence.population_snapshot()
	var polity_units: Dictionary = {}
	for record: Dictionary in input["records"]:
		var unit_id := str(record["economy_entity_id"])
		# JSON numeric evidence is normalized before entering integer runtime facts.
		(record["population"] as Dictionary)["value"] = r.world.population_input_view.population(unit_id)
		if not r.world.political_registry_view.runtime_id_for_source(unit_id).is_empty():
			polity_units[unit_id] = unit_id
	for record: Dictionary in r.world.economic_static_view.crosswalk_records():
		var unit_id := str(record["economy_entity_id"])
		for polity_id: String in DataRecordUtils.to_string_array(record["polity_ids"]):
			if polity_units.has(polity_id) and polity_units[polity_id] != unit_id:
				r.error = "Ambiguous population statistical unit mapping: " + polity_id
				return false
			polity_units[polity_id] = unit_id
	var place_units: Dictionary = {}
	for map_id: String in r.world.spatial_catalog.place_map_ids():
		var place := r.world.spatial_catalog.get_place(map_id)
		place_units[VNextSpatialCatalog.map_id_to_place_id(map_id)] = str(polity_units.get(str(place["parent_country_id"]), ""))
	# London is an existing mainland place. Its old catalogue parent names the
	# empire; the admitted UK statistical/political scope is the British Isles.
	# This bounded opening cross-reference does not assign colonial places to UK.
	var london := r.world.spatial_catalog.get_place("place:london")
	if opening_source_id=="british_isles_1900" and not r.explicit_organization_reference_injection and str(london.get("parent_country_id",""))=="british_empire" and polity_units.has("british_isles_1900"):
		place_units["place:london"] = str(polity_units.british_isles_1900)
	r.world.population_state = FormalWorldPopulationState.new()
	if not r.world.population_state.configure(input, polity_units, place_units):
		r.error = r.world.population_state.error
		return false
	return true

func _configure_formal_person_composition(r: WorldBuildResult, source_id: String, native_request: Dictionary={}) -> bool:
	if not r.world.population_input_view.is_configured():
		r.error = "Formal Population input is not configured"
		return false
	if r.world.spatial_world == null or not r.world.spatial_world.is_valid() or not r.world.spatial_catalog.is_loaded():
		r.error = "Formal Person composition cannot bind Spatial places"
		return false
	r.world.person_overlay = VNextNamedPersonOverlay.create(
		Callable(r.world.population_state, "population"),
		Callable(r.world.spatial_catalog, "has_place"),
		r.world.population_input_view.fingerprint()
	)
	if r.world.person_overlay == null:
		r.error = "Formal Person authority could not be created"
		return false
	if not r.world.person_overlay.bind_population_state(r.world.population_state):
		r.error = "Formal Person could not bind current Population"
		return false
	var opening := opening_profile(DEFAULT_FORMAL_PERSON_TERRITORY_ID if r.explicit_organization_reference_injection else source_id)
	if opening.is_empty():
		r.error = "Opening identity is unavailable"
		return false
	var place := r.world.spatial_catalog.get_place(str(opening.place_id))
	var population_unit := r.world.population_state.unit_for_place(str(opening.place_id))
	var home := r.world.political_registry_view.runtime_id_for_source(str(opening.source_id))
	if place.is_empty() or population_unit.is_empty() or home.is_empty() or str(place.get("parent_country_id",""))!=str(opening.get("place_parent_source_id",opening.source_id)):
		r.error = "Opening place has no matching political/population reference"
		return false
	var person_ids_to_materialize: Array[String] = []
	if (
		r.explicit_organization_reference_injection
		and not r.organization_person_reference_ids.is_empty()
	):
		person_ids_to_materialize.assign(r.organization_person_reference_ids)
	else:
		person_ids_to_materialize.append(str(opening.person_id))
	var corporate_person: String=""
	var native_settings: Dictionary=native_request.get("configuration",native_request)
	var resident_openings: Dictionary = {}
	if not r.explicit_organization_reference_injection and native_settings.has("opening_residents"):
		if source_id != DEFAULT_FORMAL_PERSON_TERRITORY_ID or not EconomySliceConfig.valid_opening_residents(native_settings):
			r.error = "Invalid ordinary resident Opening"
			return false
		for resident: Dictionary in native_settings["opening_residents"]:
			resident_openings[resident["person_id"]] = resident
			person_ids_to_materialize.append(resident["person_id"])
	if native_settings.has("corporate_decisions") and not r.explicit_organization_reference_injection:
		corporate_person="person:formal_generated_country_fra_corporate_manager"
		person_ids_to_materialize.append(corporate_person)
	for index: int in person_ids_to_materialize.size():
		var person_id: String = person_ids_to_materialize[index]
		var claim_id := (
			DEFAULT_FORMAL_PERSON_CLAIM_ID
			if person_id == DEFAULT_FORMAL_PERSON_ID
			else "formal_population_claim:corporate_manager:0001" if person_id==corporate_person else "formal_population_claim:explicit:%04d" % index if r.explicit_organization_reference_injection else "formal_population_claim:"+population_unit+":0001"
		)
		var demographic: Dictionary={"birth_year":1870,"sex":"unspecified","basis":"generated_simulation_assumption","joint_distribution_claimed":false}
		if resident_openings.has(person_id):
			claim_id = resident_openings[person_id]["claim_id"]
			demographic["opening_cash_policy"] = "ZERO_CASH_GENERATED_RESIDENT"
			demographic["opening_configuration_id"] = native_settings["case_id"]
		if person_id==corporate_person:demographic["opening_cash_policy"]="ZERO_CASH_DEVELOPMENT_CORPORATE_MANAGER"
		if not r.world.person_overlay.materialize(
			person_id,
			claim_id,
			population_unit,
			demographic,
			str(opening.place_id),
			{
				"kind": "generated",
				"opening_place_id": str(opening.place_id),
				"opening_polity_source_id": str(opening.source_id),
				"basis": "simulation_assumption",
				"population_source_kind": "formal_population_evidence_aggregate",
				"population_source_revision": r.world.population_input_view.revision(),
				"population_source_fingerprint": r.world.population_input_view.fingerprint(),
				"territory_mutation_converged": false,
				"population_state_converged": true,
				"prototype_character_source": false,
				"legacy_loran_vesta_source": false,
			}
		):
			r.error = "Formal Person materialization failed: %s" % (
				r.world.person_overlay.last_error()
			)
			return false
	if not r.explicit_organization_reference_injection:
		r.organization_person_reference_ids = r.world.person_overlay.person_ids()
		r.organization_place_reference_ids = [str(opening.place_id)]
		var configuration: Variant=native_request.get("configuration",native_request)
		if configuration is Dictionary and configuration.get("capital_resale",{}) is Dictionary and configuration.get("capital_resale",{}).has("authority_places"):
			if not EconomySliceConfig.valid(configuration): r.error="Invalid explicit capital organization place scope";return false
			for capital_place: String in configuration["capital_resale"]["authority_places"]:
				if not r.world.spatial_catalog.has_place(capital_place): r.error="Unknown capital organization place";return false
				if capital_place not in r.organization_place_reference_ids: r.organization_place_reference_ids.append(capital_place)
			r.organization_place_reference_ids.sort()
	if not _bind_organization_reference_catalog(r):
		return false
	r.world.player_state = VNextPlayerState.new()
	if not r.world.player_state.bind_person_authority(r.world.person_overlay):
		r.error = "PlayerState could not bind Formal Person authority"
		return false
	var person_ids := r.world.person_overlay.person_ids()
	if person_ids.is_empty() or not r.world.player_state.set_player_id(person_ids[0]):
		r.error = "PlayerState could not select a Formal Person"
		return false
	return true

func _configure_personal_economy_composition(r: WorldBuildResult, livelihood: String) -> bool:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/formal/player_livelihood_r1.json"))
	if not document is Dictionary:
		r.error = "Personal livelihood opening policy is unavailable"
		return false
	var policy := document as Dictionary
	for field: String in ["opening_cash", "wage_amount", "pay_period_minutes", "employer_reserve"]:
		var value: Variant = policy.get(field)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			r.error = "Invalid livelihood policy amount: " + field
			return false
		if not is_finite(float(value)) or float(value) != floor(float(value)) or float(value) < 1.0 or float(value) > float(FormalLedgerState.MAX_AMOUNT):
			r.error = "Invalid livelihood policy integer: " + field
			return false
		policy[field] = int(value)
	r.world.ledger_state = FormalLedgerState.new()
	r.world.personal_economy_state = FormalPersonalEconomyState.new()
	if not r.world.personal_economy_state.configure(policy, r.world.ledger_state, r.world.game_clock, r.world.person_overlay, r.world.population_state, r.world.player_state.player_id(), livelihood):
		r.error = r.world.personal_economy_state.error
		return false
	return true

func _configure_production_organization_composition(r: WorldBuildResult) -> bool:
	if r.explicit_organization_reference_injection:
		return true
	if r.world.organization_state == null or not r.world.organization_evidence.is_configured():
		r.error = "Formal Organization production composition evidence is unavailable"
		return false
	if not r.world.organization_state.organization_ids().is_empty():
		r.error = "Formal Organization production composition requires an empty OrganizationState"
		return false
	for organization_id: String in r.world.organization_evidence.organization_ids():
		var evidence_record := r.world.organization_evidence.record(organization_id)
		if not r.world.organization_state.register_organization(
			organization_id,
			str(evidence_record.get("organization_kind", "")),
			"",
			"",
			true
		):
			r.error = "Formal Organization production composition failed: %s" % organization_id
			return false
	return true

func _configure_organization_responsibilities(r: WorldBuildResult, baseline_hour: int) -> bool:
	r.world.organization_responsibility = FormalWorldOrganizationResponsibilityService.new()
	if not r.world.organization_responsibility.configure(
		FormalWorldOrganizationView.new(r.world.organization_state.snapshot()),
		FormalWorldOrganizationEvidenceView.new(r.world.organization_evidence.read_only_snapshot()),
		r.world.political_registry_view,
		FormalWorldEconomyView.new(r.world.economy_state.read_only_country_observation_snapshot()),
		baseline_hour
	):
		r.error = r.world.organization_responsibility.initialization_error
		if r.error.is_empty():
			r.error = "Formal Organization responsibilities could not be composed"
		return false
	return true

func _configure_authorization(r: WorldBuildResult) -> bool:
	if r.world.organization_state == null or not r.world.organization_state.is_valid() or r.world.person_overlay == null:
		r.error = "Authorization dependencies are invalid"
		return false
	r.world.authorization_check = AuthorizationCheck.new(r.world.organization_state)
	return true

func _configure_military_composition(r: WorldBuildResult) -> bool:
	if r.world.spatial_world == null or not r.world.spatial_world.is_valid():
		r.error = "Formal Military composition cannot bind Spatial authority"
		return false
	r.world.military_map = VNextMilitaryMapAdapter.new()
	if not r.world.military_map.load_existing_map(r.world.spatial_world):
		r.error = "Formal Military map adapter could not bind Spatial authority"
		return false
	r.world.military_state = VNextMilitaryState.new()
	if not r.world.military_state.initialize(r.world.military_map):
		r.error = "Formal MilitaryState could not initialize"
		return false
	r.world.military_service = VNextMilitaryService.new(r.world.territory_state, r.world.spatial_catalog)
	return true

func _bind_organization_reference_catalog(r: WorldBuildResult) -> bool:
	var expected := VNextOrganizationReferenceCatalog.create(
		r.organization_person_reference_ids,
		r.organization_place_reference_ids
	)
	if expected == null:
		r.error = "Organization reference provider is invalid"
		return false
	if not r.world.organization_state.has_reference_catalog():
		if not r.world.organization_state.configure_reference_catalog(
			r.organization_person_reference_ids,
			r.organization_place_reference_ids
		):
			r.error = "Organization reference provider cannot be bound"
			return false
	elif r.world.organization_state.reference_catalog_fingerprint() != expected.fingerprint():
		r.error = "Organization reference provider does not match Formal Person authority"
		return false
	if not r.world.organization_state.is_valid():
		r.error = "Organization composition is invalid"
		return false
	return true

func _configure_market_registry(r: WorldBuildResult) -> bool:
	var economic_aggregate_ids: Array[String] = []
	for record: Dictionary in r.world.economic_static_view.countries():
		var economic_aggregate_id := str(record.get("entity_id", ""))
		if not economic_aggregate_id.is_empty():
			economic_aggregate_ids.append(economic_aggregate_id)
	return r.world.market_registry.configure(
		economic_aggregate_ids, r.world.political_registry_view.entity_ids()
	)

func _failure(r: WorldBuildResult) -> WorldBuildResult:
	r.success = false
	push_error("WORLD BOOTSTRAP ERROR: " + r.error)
	return r

static func prepare_presentation_content(provenance: HistoricalProvenanceFoundation, stage: Callable = Callable(), current: Callable = Callable()) -> HistoricalLoader:
	# Admission belongs to world installation. Dated display queries run on the
	# resulting Content object, without re-entering bootstrap during UI refresh.
	var content := HistoricalLoader.new()
	if provenance==null or not provenance.is_loaded():
		content.errors.append("历史来源目录尚未成功加载")
		return content
	if not content.load_current(provenance.gate(),stage,current):
		if content.errors.is_empty(): content.errors.append("地图资料准备已取消或未完成")
		return content # Explicit failure object; callers must check loaded/errors.
	content.provenance = provenance
	return content

## Publish ownership only after the slice, its accounts and physical state exist.
## A rejected new-world configuration leaves the ordinary formal economy usable.
func _prepare_development_business_identities(r: WorldBuildResult, settings: Dictionary) -> bool:
	if settings.get("development_organizations",[]).is_empty(): return true
	# Only explicit new-world development identities. No resources or historical
	# composition records are created. Headquarters remains in the business sites.
	var candidate := OrganizationState.new()
	if not candidate.configure_reference_catalog(r.organization_person_reference_ids,r.organization_place_reference_ids) or not candidate.restore(r.world.organization_state.snapshot()):
		r.world.native_economy_error="Development company identity candidate failed"
		return false
	for row: Dictionary in settings["development_organizations"]:
		var id := str(row["organization_id"])
		if candidate.has_organization(id) or not candidate.create_organization(id,"company"):
			r.world.native_economy_error="Development company identity already exists or is invalid: "+id
			return false
		for firm: Dictionary in settings["firms"]:
			if firm["id"]!=row["firm_id"]: continue
			var manager := str(firm.get("manager",firm["id"]))
			if manager==firm["id"]: continue # Existing bounded internal operator; no invented NPC manager.
			if not candidate.add_member(id,manager) or not candidate.define_position(id,"economic_operator","经营管理者（开发配置）",1) or not candidate.create_appointment(id,"opening_operator",manager,"economic_operator"):
				r.world.native_economy_error="Development company manager lacks actual host identity: "+manager
				return false
			# Explicit player-capital scenarios grant each financial/disposal scope
			# separately to the actual appointment. A management title alone grants none.
			if settings.get("case_id") in ["FORMAL_PLAYER_CAPITAL_TRADE_DEVELOPMENT","FORMAL_PLAYER_CAPITAL_SALE_DEVELOPMENT","FORMAL_ECONOMY_FEEDBACK_DEVELOPMENT"]:
				for permission: Dictionary in settings["capital_resale"]["authorities"]:
					if permission["firm"]!=firm["id"] or permission["controller"]!=manager or not str(permission["root_authority"]).begins_with("authority:development:player_capital:"): continue
					var operation: String=permission["operations"][0]
					var grant:={"authority_id":permission["root_authority"],"holder":{"kind":"position","organization_id":id,"local_id":"economic_operator","person_id":""},"represented_entity":id,"operation":"economy.procure" if operation=="acquire" else "economy.capital."+operation,"target_scope":[firm["id"]],"spatial_scope":[firm["sites"][0]["place_id"]],"subject_scope":["capital_asset"],"amount_or_quantity_limit":float(permission["limit"]),"valid_from":int(permission["start_minute"])/60,"valid_until":int(permission["end_minute"])/60,"basis":{"kind":"generated_simulation_assumption","id":permission["id"]},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":{"allowed_stages":["domain_execution"],"required_procedure_id":"","notes":"Exact firm, primary place, capital category and operation. Actual premises and routes remain native-domain checks. No borrowing authority."},"accountability":{"organization_id":id,"relation_id":""},"revoked_at":-1}
					if not candidate.add_authority_grant(grant):
						r.world.native_economy_error="Invalid separate player capital grant: "+str(permission["root_authority"])
						return false
			var program: Dictionary=settings.get("equity_primary",{})
			if not program.is_empty() and program["issuer"]==firm["id"] and program["controller"]==manager:
				var grant: Dictionary={"authority_id":program["authority_id"],"holder":{"kind":"position","organization_id":id,"local_id":"economic_operator","person_id":""},"represented_entity":id,"operation":"economy.equity.issue","target_scope":[firm["id"]],"spatial_scope":[firm["sites"][0]["place_id"]],"subject_scope":[program["asset_id"]],"amount_or_quantity_limit":float(program["max_new_shares"]),"valid_from":int(program["start"])/60,"valid_until":int(program["end"])/60,"basis":{"kind":"generated_simulation_assumption","id":"primary:regional_food:founders_consent"},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":{"allowed_stages":["domain_execution"],"required_procedure_id":"","notes":"Bounded founder-consented primary program; fixed denomination/price and project checked by AssetMarket. No automatic governance, borrowing or payout authority."},"accountability":{"organization_id":id,"relation_id":""},"revoked_at":-1}
				if not candidate.add_authority_grant(grant):
					r.world.native_economy_error="Invalid separate primary issuance grant";return false
			var distribution: Dictionary=settings.get("equity_distribution",{})
			if not distribution.is_empty() and distribution["issuer"]==firm["id"] and distribution["controller"]==manager:
				var grant: Dictionary={"authority_id":distribution["authority_id"],"holder":{"kind":"position","organization_id":id,"local_id":"economic_operator","person_id":""},"represented_entity":id,"operation":"economy.equity.distribute","target_scope":[firm["id"]],"spatial_scope":[firm["sites"][0]["place_id"]],"subject_scope":[distribution["asset_id"]],"amount_or_quantity_limit":float(distribution["max_total"]),"valid_from":int(distribution["start"])/60,"valid_until":int(distribution["end"])/60,"basis":{"kind":"generated_simulation_assumption","id":"distribution:regional_food:finite_founder_consent"},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":{"allowed_stages":["domain_execution"],"required_procedure_id":"","notes":"Bounded cash distribution; not net profit or historical company law. Separate from issuance and management."},"accountability":{"organization_id":id,"relation_id":""},"revoked_at":-1}
				if not candidate.add_authority_grant(grant):
					r.world.native_economy_error="Invalid separate cash distribution grant";return false
	r.world.organization_state=candidate
	r.world.authorization_check=AuthorizationCheck.new(candidate)
	return true

func _configure_native_economy(r: WorldBuildResult, settings: Dictionary) -> void:
	if settings.get("format") == "HOST_REGION_SELECTION":
		var resolved := EconomyDevelopmentConfig.resolve_regional(r.world, settings)
		if resolved.has("error"):
			r.world.native_economy_error = str(resolved["error"])
			return
		settings = resolved["configuration"]
	settings = settings.duplicate(true)
	if not EconomySliceConfig.valid(settings):
		r.world.native_economy_error="Invalid native business configuration"
		return
	var population_before := r.world.population_state.snapshot()
	if not settings.has("place_population_bindings") and settings.get("case_id") in ["DEVELOPMENT_MULTI_SITE_LIVING", "FORMAL_REGIONAL_DEVELOPMENT"]:
		settings["place_population_bindings"] = EconomyDevelopmentConfig.formal_residence_place_bindings(r.world)
	if not r.world.population_state.prepare_place_population_bindings(settings.get("place_population_bindings", [])):
		r.world.native_economy_error = r.world.population_state.error
		return
	if not settings.has("residence_permissions") and settings.get("case_id") in ["DEVELOPMENT_MULTI_SITE_LIVING", "FORMAL_REGIONAL_DEVELOPMENT"]:
		settings["residence_permissions"] = EconomyDevelopmentConfig.formal_residence_permissions(r.world, settings)
	var organization_before := r.world.organization_state.snapshot()
	for opening: Dictionary in settings.get("opening_organizations", []):
		if r.world.game_clock.total_minutes() != 0 or not r.world.organization_state.create_organization(opening.organization_id, "company", opening.place_id):
			r.world.organization_state.restore(organization_before)
			r.world.population_state.restore(population_before)
			r.world.native_economy_error = "Ordinary opening organization could not be installed"
			return
	if not _prepare_development_business_identities(r,settings):
		r.world.organization_state.restore(organization_before)
		r.world.population_state.restore(population_before)
		return
	var native := EconomyR1Slice.new()
	if not native.bind(r.world, settings) or not native.validate_formal_composition():
		r.world.native_economy_error = native.error
		if not r.world.organization_state.restore(organization_before):
			r.error = r.world.organization_state.error
			return
		r.world.population_state.restore(population_before)
		return
	var ledger_before := r.world.ledger_state.snapshot()
	var personal_before := r.world.personal_economy_state.snapshot()
	r.world.ledger_state.enable_economy_r1()
	var personal := r.world.personal_economy_state
	if personal.bind_native(native, r.world.ledger_state, r.world.game_clock, r.world.person_overlay, r.world.population_state) and native.initialize() and r.world.person_overlay.configure_formal_mobility(native.config.get("person_travel", {})) and r.world.person_travel.validate_economic_content(native) and r.world.population_state.bind_native_background(native.background_responsibilities(), native) and native.activate_formal_scope():
		r.world.economy_r1 = native
		r.world.economy_state.bind_native_economy(native)
		r.world.player_state.lock_current_player()
		return
	if not r.world.organization_state.restore(organization_before):
		r.error = r.world.organization_state.error
		return
	r.world.native_economy_error = native.error if not native.error.is_empty() else personal.error if not personal.error.is_empty() else r.world.population_state.error if not r.world.population_state.error.is_empty() else r.world.person_travel.error if not r.world.person_travel.error.is_empty() else r.world.person_overlay.last_error()
	var restored_ledger := FormalLedgerState.new()
	if not restored_ledger.restore(ledger_before):
		r.error = restored_ledger.error
		return
	r.world.ledger_state = restored_ledger
	if not personal.unbind_native(restored_ledger):
		r.error = personal.error
		return
	if not personal.restore(personal_before, r.world.player_state.player_id()):
		r.error = personal.error
	r.world.economy_state.bind_personal_ledger(restored_ledger)
	if not r.world.population_state.bind_native_background({}) or not r.world.population_state.restore(population_before): r.error = r.world.population_state.error
	# Construction failed before live ownership; discard only unactivated terms.
	r.world.person_travel = FormalPersonTravel.new()
	r.world.person_travel.bind(r.world)
	personal.bind_travel(r.world.person_travel)
