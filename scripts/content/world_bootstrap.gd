class_name WorldBootstrap
extends RefCounted
## Creates fresh components and their explicit references. Not a runtime owner.

const TERRITORIAL_CONTROL_OWNER: String = "TerritoryState"
const TERRITORY_AUTHORITY_PRODUCTION_STATUS: String = "TERRITORY_STATE_SINGLE_AUTHORITY"
const DEFAULT_FORMAL_PERSON_ID: String = "person:formal_generated_country_fra_0001"
const DEFAULT_FORMAL_PERSON_CLAIM_ID: String = "formal_population_claim:country_fra:0001"
const DEFAULT_FORMAL_PERSON_TERRITORY_ID: String = "country_fra"
const DEFAULT_FORMAL_PERSON_PLACE_ID: String = "place:paris"

func build(organization_state_value: OrganizationState = null, organization_person_reference_ids: Array[String] = [], organization_place_reference_ids: Array[String] = [], livelihood: String = FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT) -> WorldBuildResult:
	var r := WorldBuildResult.new()
	r.world.game_clock = GameClock.new()
	r.world.provenance = HistoricalProvenanceFoundation.new()
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
	if not r.world.provenance.load_current():
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
	if not _configure_spatial_composition(r):
		return _failure(r)
	if not _configure_population_composition(r):
		return _failure(r)
	if not _configure_formal_person_composition(r):
		return _failure(r)
	if not _configure_personal_economy_composition(r, livelihood):
		return _failure(r)
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
	if not _configure_organization_responsibilities(r, r.world.game_clock.current_hour()):
		return _failure(r)
	r.success = true
	r.simulation_step = SimulationStep.new(r.world.game_clock, r.world.spatial_world, r.world.economy_state, r.economy_simulation, r.world.organization_responsibility, r.world.organization_state, r.world.political_registry_view, r.world.personal_economy_state)
	r.persistence = FormalPersistence.new(r.world, r.organization_person_reference_ids, r.organization_place_reference_ids, r.explicit_organization_reference_injection)
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

func _configure_spatial_composition(r: WorldBuildResult) -> bool:
	if not r.world.spatial_catalog.load_legacy_world_map():
		r.error = "Formal Spatial catalog could not load source topology"
		return false
	r.world.spatial_world = VNextSpatialWorld.create(r.world.spatial_catalog)
	if r.world.spatial_world == null or not r.world.spatial_world.is_valid():
		r.error = "Formal Spatial authority could not be composed"
		return false
	r.world.territory_state = TerritoryState.new()
	var controllers: Dictionary = {}
	for place_id: String in r.world.spatial_catalog.place_map_ids():
		controllers[place_id] = str(r.world.spatial_catalog.get_place(place_id)["parent_country_id"])
	if not r.world.territory_state.restore({"schema_id": TerritoryState.SCHEMA_ID, "controllers": controllers}, r.world.spatial_catalog.place_map_ids()):
		r.error = r.world.territory_state.error
		return false
	if r.world.spatial_world.current_hour() != r.world.game_clock.current_hour():
		r.error = "Spatial initial hour %d differs from GameClock hour %d" % [r.world.spatial_world.current_hour(), r.world.game_clock.current_hour()]
		return false
	return true

func _configure_population_composition(r: WorldBuildResult) -> bool:
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
	r.world.population_state = FormalWorldPopulationState.new()
	if not r.world.population_state.configure(input, polity_units, place_units):
		r.error = r.world.population_state.error
		return false
	return true

func _configure_formal_person_composition(r: WorldBuildResult) -> bool:
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
	var person_ids_to_materialize: Array[String] = []
	if (
		r.explicit_organization_reference_injection
		and not r.organization_person_reference_ids.is_empty()
	):
		person_ids_to_materialize.assign(r.organization_person_reference_ids)
	else:
		person_ids_to_materialize.append(DEFAULT_FORMAL_PERSON_ID)
	for index: int in person_ids_to_materialize.size():
		var person_id: String = person_ids_to_materialize[index]
		var claim_id := (
			DEFAULT_FORMAL_PERSON_CLAIM_ID
			if person_id == DEFAULT_FORMAL_PERSON_ID
			else "formal_population_claim:explicit:%04d" % index
		)
		if not r.world.person_overlay.materialize(
			person_id,
			claim_id,
			DEFAULT_FORMAL_PERSON_TERRITORY_ID,
			{
				"birth_year": 1870,
				"sex": "unspecified",
				"basis": "generated_simulation_assumption",
				"joint_distribution_claimed": false,
			},
			DEFAULT_FORMAL_PERSON_PLACE_ID,
			{
				"kind": "generated",
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
		r.organization_place_reference_ids = [DEFAULT_FORMAL_PERSON_PLACE_ID]
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

static func prepare_presentation_content(provenance: HistoricalProvenanceFoundation) -> HistoricalLoader:
	# Admission belongs to world installation. Dated display queries run on the
	# resulting Content object, without re-entering bootstrap during UI refresh.
	var content := HistoricalLoader.new()
	content.load_current(provenance.gate())
	return content
