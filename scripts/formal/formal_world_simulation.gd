class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. Immutable evidence, current political
## identity, economic aggregates, Population-evidence-backed named persons, and
## OrganizationCore remain separate owned boundaries. This root owns
## composition and lifecycle, never a second copy of domain authority.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v7"
const PREVIOUS_SCHEMA_ID: String = "formal_world_simulation_v6"
const LEGACY_ORGANIZATION_SCHEMA_ID: String = "formal_world_simulation_v5"
const EVIDENCE_STATE_SCHEMA_ID: String = "historical_political_evidence_v1"
const DEFAULT_FORMAL_PERSON_ID: String = "person:formal_generated_country_fra_0001"
const DEFAULT_FORMAL_PERSON_CLAIM_ID: String = "formal_population_claim:country_fra:0001"
const DEFAULT_FORMAL_PERSON_TERRITORY_ID: String = "country_fra"
const DEFAULT_FORMAL_PERSON_PLACE_ID: String = "place:paris"

var _provenance := HistoricalProvenanceFoundation.new()
var _historical_evidence := HistoricalPoliticalEvidenceCatalog.new()
var _political_registry := RuntimePoliticalEntityRegistry.new()
var _historical_evidence_view := HistoricalPoliticalEvidenceView.new()
var _political_registry_view := RuntimePoliticalEntityView.new()
var _economic_evidence := FormalWorldEconomicEvidenceCatalog.new()
var _economic_static_view := FormalWorldEconomicStaticView.new()
var _population_input_view := FormalWorldPopulationInputView.new()
var _market_registry := FormalWorldMarketRegistry.new()
var _market_registry_view := FormalWorldMarketView.new()
var _economy := FormalWorldEconomyService.new()
var _spatial_catalog := VNextSpatialCatalog.new()
var _spatial_world: VNextSpatialWorld = null
var _person_authority: VNextNamedPersonOverlay = null
var _player_state := VNextPlayerState.new()
var _organization: VNextOrganizationCore = null
var _organization_authority: VNextOrganizationAuthorityFoundation = null
var _military_map: VNextMilitaryMapAdapter = null
var _military_state: VNextMilitaryState = null
var _military_service := VNextMilitaryService.new()
var _military_authority_bridge: VNextMilitaryAuthorityBridge = null
var _organization_person_reference_ids: Array[String] = []
var _organization_place_reference_ids: Array[String] = []
var _organization_composition_error: String = ""
var _explicit_organization_reference_injection: bool = false
var economy: FormalWorldEconomyView:
	get:
		return economy_view()
var initialized: bool = false
var initialization_error: String = ""
var total_minutes: int = 0
var _initialization_attempted: bool = false
var _minute_remainder: int:
	get:
		return total_minutes % 60


func _init(
	organization_core_value: VNextOrganizationCore = null,
	organization_person_reference_ids: Array[String] = [],
	organization_place_reference_ids: Array[String] = []
) -> void:
	_organization_person_reference_ids = organization_person_reference_ids.duplicate()
	_organization_person_reference_ids.sort()
	_organization_place_reference_ids = organization_place_reference_ids.duplicate()
	_organization_place_reference_ids.sort()
	_explicit_organization_reference_injection = (
		organization_core_value != null
		or not _organization_person_reference_ids.is_empty()
		or not _organization_place_reference_ids.is_empty()
	)
	_organization = (
		organization_core_value
		if organization_core_value != null
		else VNextOrganizationCore.new()
	)
	if _explicit_organization_reference_injection:
		var reference_catalog := VNextOrganizationReferenceCatalog.create(
			_organization_person_reference_ids,
			_organization_place_reference_ids
		)
		if reference_catalog == null:
			_organization_composition_error = "Organization reference provider is invalid"
		elif not _organization.has_reference_catalog():
			if not _organization.configure_reference_catalog(
				_organization_person_reference_ids,
				_organization_place_reference_ids
			):
				_organization_composition_error = (
					"Organization reference provider is missing or cannot be bound"
				)
		elif (
			_organization.reference_catalog_fingerprint()
			!= reference_catalog.fingerprint()
		):
			_organization_composition_error = (
				"Organization reference provider does not match the injected core"
			)
	_economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)


func initialize() -> bool:
	if _initialization_attempted:
		initialization_error = "Formal world composition is already initialized"
		return false
	_initialization_attempted = true
	initialization_error = ""
	total_minutes = 0
	if _organization == null or not _organization_composition_error.is_empty():
		initialization_error = (
			_organization_composition_error
			if not _organization_composition_error.is_empty()
			else "Organization composition is invalid"
		)
		initialized = false
		return false
	if not _provenance.load_current():
		initialization_error = _provenance.initialization_error
		initialized = false
		return false
	if not _historical_evidence.configure(
		HistoricalPoliticalEvidenceCatalog.DEFAULT_PATH,
		_provenance.gate()
	):
		initialization_error = _historical_evidence.initialization_error
		initialized = false
		return false
	if not _political_registry.configure(_historical_evidence):
		initialization_error = _political_registry.initialization_error
		initialized = false
		return false
	if not _economic_evidence.configure(_provenance.gate()):
		initialization_error = _economic_evidence.initialization_error
		initialized = false
		return false
	_refresh_read_only_views()
	if not _configure_formal_person_composition():
		initialized = false
		return false
	if not _configure_organization_authority():
		initialized = false
		return false
	if not _configure_military_composition():
		initialized = false
		return false
	if not _configure_market_registry():
		initialization_error = _market_registry.initialization_error
		initialized = false
		return false
	_refresh_read_only_views()
	if not _economy.configure(
		_political_registry_view,
		_market_registry_view,
		_economic_static_view,
		_population_input_view
	):
		initialization_error = _economy.initialization_error
		initialized = false
		return false
	initialized = true
	state_changed.emit({"initialized": true})
	return true


func historical_evidence_view() -> HistoricalPoliticalEvidenceView:
	return _historical_evidence_view


func provenance_gate() -> HistoricalProvenanceGate:
	return _provenance.gate()


func political_registry_view() -> RuntimePoliticalEntityView:
	return _political_registry_view


func market_registry_view() -> FormalWorldMarketView:
	return _market_registry_view


func economy_view() -> FormalWorldEconomyView:
	if not _economy.is_configured():
		return FormalWorldEconomyView.new()
	return FormalWorldEconomyView.new(_economy.read_only_snapshot())


func organization_view() -> FormalWorldOrganizationView:
	if _organization == null:
		return FormalWorldOrganizationView.new()
	return FormalWorldOrganizationView.new(_organization.snapshot())


func organization_query_port() -> FormalWorldOrganizationView:
	return organization_view()


func formal_person_count() -> int:
	return _person_authority.person_count() if _person_authority != null else 0


func formal_person_ids() -> Array[String]:
	return _person_authority.person_ids() if _person_authority != null else []


func has_formal_person(person_id: String) -> bool:
	return _person_authority != null and _person_authority.has_person(person_id)


func formal_person(person_id: String) -> Dictionary:
	return _person_authority.person(person_id) if _person_authority != null else {}


func formal_person_population_claim(person_id: String) -> Dictionary:
	return _person_authority.population_claim(person_id) if _person_authority != null else {}


func formal_person_anonymous_population(population_territory_id: String) -> int:
	return (
		_person_authority.anonymous_population_for_territory(population_territory_id)
		if _person_authority != null
		else -1
	)


func organization_person_reference_ids() -> Array[String]:
	return _organization_person_reference_ids.duplicate()


func player_person_id() -> String:
	return _player_state.player_id()


func select_player_person(person_id: String) -> bool:
	return _player_state.set_player_id(person_id)


func player_defend_formation(
	acting_context: Dictionary,
	formation_id: String,
	duration_hours: int
) -> Dictionary:
	if not initialized or _military_authority_bridge == null:
		return {
			"success": false,
			"status": VNextMilitaryAuthorityBridge.RESULT_DOMAIN_REJECTED,
			"authority_status": "",
			"authorization": {},
			"domain_result": {"success": false, "message": "Formal Military composition is unavailable."},
		}
	if str(acting_context.get("person_id", "")) != player_person_id():
		return {
			"success": false,
			"status": VNextMilitaryAuthorityBridge.RESULT_AUTHORITY_DENIED,
			"authority_status": VNextOrganizationAuthorityFoundation.STATUS_INVALID_ACTING_CONTEXT,
			"authorization": {},
			"domain_result": {},
		}
	return _military_authority_bridge.defend(
		acting_context,
		formation_id,
		duration_hours,
		_authoritative_total_hour()
	)


func economy_regression_snapshot() -> Dictionary:
	return _economy.legacy_regression_snapshot()


func advance_minutes(minutes: int) -> Dictionary:
	if not initialized or minutes <= 0:
		return _economy.world_summary()
	var previous_total_hour := _authoritative_total_hour()
	total_minutes += minutes
	var current_total_hour := _authoritative_total_hour()
	var elapsed_hours := current_total_hour - previous_total_hour
	if elapsed_hours > 0:
		var summary := _economy.settle_hour_range(
			previous_total_hour, current_total_hour
		)
		state_changed.emit({
			"time": true,
			"economy": true,
			"hours": elapsed_hours,
		})
		return summary
	state_changed.emit({"time": true, "economy": false, "hours": 0})
	return _economy.world_summary()


func world_summary() -> Dictionary:
	var result := _economy.world_summary()
	result["world_political_unit_count"] = _political_registry.entity_count()
	result["historical_political_record_count"] = _historical_evidence.record_count()
	result["formal_person_count"] = formal_person_count()
	result["background_polity_count"] = maxi(
		0,
		_political_registry.entity_count()
		- int(result.get("detailed_polity_unit_count", 0))
	)
	return result


func country_summary(entity_id: String) -> Dictionary:
	return _economy.country_summary(entity_id)


func polity_summary(entity_id: String) -> Dictionary:
	var result := CurrentWorldPoliticalProjection.polity_summary(
		entity_id, _political_registry_view, _historical_evidence_view
	)
	if result.is_empty():
		return {}
	var economy_id := _economy.economy_entity_for_polity(entity_id)
	var detailed := not economy_id.is_empty()
	result["has_detailed_economy"] = detailed
	result["economy_entity_id"] = economy_id
	result["major_roster"] = detailed
	result["primary_playable"] = false
	result["playability_tier"] = "background_npc"
	result["playability_tier_zh"] = "背景政治单元"
	if detailed:
		var economy_summary := _economy.country_summary(economy_id)
		result["economy"] = economy_summary
		result["rank"] = int(economy_summary.get("rank", 0))
		result["playability_tier"] = str(
			economy_summary.get("playability_tier", "secondary_roster")
		)
		result["playability_tier_zh"] = str(
			economy_summary.get("playability_tier_zh", "次要政权候选")
		)
		result["primary_playable"] = bool(
			economy_summary.get("primary_playable", false)
		)
	return result


func has_polity(entity_id: String) -> bool:
	return _political_registry.has_entity(entity_id)


func first_polity_id() -> String:
	var ids := _political_registry.entity_ids()
	return ids[0] if not ids.is_empty() else ""


func current_world_political_units() -> Array[Dictionary]:
	return CurrentWorldPoliticalProjection.map_units(
		_political_registry_view, _historical_evidence_view
	)


func historical_political_evidence_units() -> Array[Dictionary]:
	return _historical_evidence_view.records()


func historical_record(source_historical_id: String) -> Dictionary:
	return _historical_evidence_view.record(source_historical_id)


func historical_records_active_on(date: String) -> Array[Dictionary]:
	return _historical_evidence_view.records_active_on(date)


func date_time() -> Dictionary:
	var value := V2DateTime.from_total_hour(_authoritative_total_hour())
	value["minute"] = _minute_remainder
	return value


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"total_minutes": total_minutes,
		"minute_remainder": _minute_remainder,
		"historical_evidence": {
			"schema_id": EVIDENCE_STATE_SCHEMA_ID,
			"fingerprint": _historical_evidence.fingerprint(),
		},
		"runtime_politics": _political_registry.snapshot(),
		"markets": _market_registry.get_persistent_state(),
		"economy": _economy.get_persistent_state(),
		"persons": _person_authority.snapshot(),
		"player": _player_state.snapshot(),
		"organization": _organization.snapshot(),
		"organization_authority": _organization_authority.snapshot(),
		"military_state": _military_state.snapshot(),
	}


func authoritative_fingerprint() -> String:
	if (
		not initialized
		or _organization == null
		or _person_authority == null
		or _organization_authority == null
		or _military_state == null
	):
		return ""
	return JSON.stringify({
		"schema_id": "formal_world_authoritative_fingerprint_v3",
		"total_minutes": total_minutes,
		"historical_evidence": _historical_evidence.fingerprint(),
		"runtime_politics": JSON.stringify(_political_registry.snapshot()).sha256_text(),
		"markets": JSON.stringify(_market_registry.get_persistent_state()).sha256_text(),
		"economy": JSON.stringify(_economy.get_persistent_state()).sha256_text(),
		"persons": _person_authority.state_fingerprint(),
		"player": JSON.stringify(_player_state.snapshot()).sha256_text(),
		"organization": _organization.state_fingerprint(),
		"organization_authority": _organization_authority.state_fingerprint(),
		"military_state": _military_state.state_fingerprint(),
	}).sha256_text()


func restore_persistent_state(state: Dictionary) -> bool:
	var candidate := _new_candidate_world()
	if not candidate.initialize():
		return false
	if not candidate._restore_candidate_state(state):
		return false
	_adopt_candidate(candidate)
	state_changed.emit({"restored": true})
	return true


func _restore_candidate_state(state: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	if (
		schema_id not in [
			"formal_world_simulation_v1",
			"formal_world_simulation_v2",
			"formal_world_simulation_v3",
			"formal_world_simulation_v4",
			LEGACY_ORGANIZATION_SCHEMA_ID,
			PREVIOUS_SCHEMA_ID,
			SCHEMA_ID,
		]
		or not state.get("economy", {}) is Dictionary
	):
		return false
	var validated_time := _validated_time_state(state, schema_id)
	if validated_time.is_empty():
		return false
	if schema_id in [
		"formal_world_simulation_v3",
		"formal_world_simulation_v4",
		LEGACY_ORGANIZATION_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SCHEMA_ID,
	]:
		if (
			not state.get("historical_evidence", {}) is Dictionary
			or not state.get("runtime_politics", {}) is Dictionary
		):
			return false
		var evidence_state := state.get("historical_evidence", {}) as Dictionary
		if (
			str(evidence_state.get("schema_id", ""))
			!= EVIDENCE_STATE_SCHEMA_ID
			or str(evidence_state.get("fingerprint", ""))
			!= _historical_evidence.fingerprint()
			or not _political_registry.restore_snapshot(
				state.get("runtime_politics", {}) as Dictionary,
				_historical_evidence
			)
		):
			return false
		_refresh_read_only_views()
		if not _economy.bind_runtime_political_view(_political_registry_view):
			return false
	if schema_id in [
		"formal_world_simulation_v4",
		LEGACY_ORGANIZATION_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SCHEMA_ID,
	]:
		if (
			not state.get("markets", {}) is Dictionary
			or not _market_registry.validate_persistent_state(
				state.get("markets", {}) as Dictionary
			)
		):
			return false
	if schema_id in [PREVIOUS_SCHEMA_ID, SCHEMA_ID]:
		if (
			not state.get("persons", {}) is Dictionary
			or not state.get("player", {}) is Dictionary
			or not _person_authority.restore(state.get("persons", {}) as Dictionary)
		):
			return false
		if not _rebind_player_and_organization_for_restored_persons():
			return false
		if not _player_state.restore(state.get("player", {}) as Dictionary):
			return false
	if schema_id in [LEGACY_ORGANIZATION_SCHEMA_ID, PREVIOUS_SCHEMA_ID, SCHEMA_ID]:
		if (
			not state.get("organization", {}) is Dictionary
			or not _organization.restore(
				state.get("organization", {}) as Dictionary
			)
		):
			return false
		if not _configure_organization_authority():
			return false
	if schema_id == SCHEMA_ID:
		if (
			not state.get("organization_authority", {}) is Dictionary
			or not state.get("military_state", {}) is Dictionary
			or not _organization_authority.restore(
				state.get("organization_authority", {}) as Dictionary
			)
			or not _military_state.restore(
				state.get("military_state", {}) as Dictionary,
				_military_map,
				_spatial_world
			)
		):
			return false
	total_minutes = int(validated_time.get("total_minutes", -1))
	if not _economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	):
		return false
	initialized = true
	return true


func _adopt_candidate(candidate: FormalWorldSimulation) -> void:
	total_minutes = candidate.total_minutes
	_provenance = candidate._provenance
	_historical_evidence = candidate._historical_evidence
	_political_registry = candidate._political_registry
	_historical_evidence_view = candidate._historical_evidence_view
	_political_registry_view = candidate._political_registry_view
	_economic_evidence = candidate._economic_evidence
	_economic_static_view = candidate._economic_static_view
	_population_input_view = candidate._population_input_view
	_market_registry = candidate._market_registry
	_market_registry_view = candidate._market_registry_view
	_economy = candidate._economy
	_spatial_catalog = candidate._spatial_catalog
	_spatial_world = candidate._spatial_world
	_person_authority = candidate._person_authority
	var person_population_query_rebound := (
		_person_authority != null
		and _person_authority.rebind_population_total_query(
			Callable(self, "_formal_population_total")
		)
	)
	assert(person_population_query_rebound)
	_player_state = candidate._player_state
	_organization = candidate._organization
	_organization_authority = candidate._organization_authority
	_military_map = candidate._military_map
	_military_state = candidate._military_state
	_military_service = candidate._military_service
	_organization_person_reference_ids = (
		candidate._organization_person_reference_ids.duplicate()
	)
	_organization_place_reference_ids = (
		candidate._organization_place_reference_ids.duplicate()
	)
	_explicit_organization_reference_injection = (
		candidate._explicit_organization_reference_injection
	)
	_organization_composition_error = ""
	var military_bridge_rebound := _configure_military_authority_bridge()
	assert(military_bridge_rebound)
	_economy.bind_authoritative_hour_source(
		Callable(self, "_authoritative_total_hour")
	)
	initialized = true
	initialization_error = ""
	_initialization_attempted = true


func reset_world() -> bool:
	var candidate := _new_candidate_world()
	if not candidate.initialize():
		return false
	_adopt_candidate(candidate)
	state_changed.emit({"reset": true})
	return true


func _new_candidate_world() -> FormalWorldSimulation:
	if _explicit_organization_reference_injection:
		return FormalWorldSimulation.new(
			null,
			_organization_person_reference_ids,
			_organization_place_reference_ids
		)
	return FormalWorldSimulation.new()


func _refresh_read_only_views() -> void:
	_historical_evidence_view = HistoricalPoliticalEvidenceView.new(
		_historical_evidence.read_only_snapshot()
	)
	_political_registry_view = RuntimePoliticalEntityView.new(
		_political_registry.snapshot()
	)
	_economic_static_view = FormalWorldEconomicStaticView.new(
		_economic_evidence.economic_snapshot()
	)
	_population_input_view = FormalWorldPopulationInputView.new(
		_economic_evidence.population_snapshot()
	)
	_market_registry_view = FormalWorldMarketView.new(
		_market_registry.read_only_snapshot()
	)


func _formal_population_total(population_territory_id: String) -> int:
	if not _population_input_view.is_configured():
		return -1
	return _population_input_view.population(population_territory_id)


func _configure_formal_person_composition() -> bool:
	if not _population_input_view.is_configured():
		initialization_error = "Formal Population input is not configured"
		return false
	if not _spatial_catalog.load_legacy_world_map():
		initialization_error = "Formal Person composition cannot bind Spatial places"
		return false
	_person_authority = VNextNamedPersonOverlay.create(
		Callable(self, "_formal_population_total"),
		Callable(_spatial_catalog, "has_place"),
		_population_input_view.fingerprint()
	)
	if _person_authority == null:
		initialization_error = "Formal Person authority could not be created"
		return false
	var person_ids_to_materialize: Array[String] = []
	if (
		_explicit_organization_reference_injection
		and not _organization_person_reference_ids.is_empty()
	):
		person_ids_to_materialize.assign(_organization_person_reference_ids)
	else:
		person_ids_to_materialize.append(DEFAULT_FORMAL_PERSON_ID)
	for index: int in person_ids_to_materialize.size():
		var person_id: String = person_ids_to_materialize[index]
		var claim_id := (
			DEFAULT_FORMAL_PERSON_CLAIM_ID
			if person_id == DEFAULT_FORMAL_PERSON_ID
			else "formal_population_claim:explicit:%04d" % index
		)
		if not _person_authority.materialize(
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
				"population_source_revision": _population_input_view.revision(),
				"population_source_fingerprint": _population_input_view.fingerprint(),
				"territory_mutation_converged": false,
				"prototype_character_source": false,
				"legacy_loran_vesta_source": false,
			}
		):
			initialization_error = "Formal Person materialization failed: %s" % (
				_person_authority.last_error()
			)
			return false
	if not _explicit_organization_reference_injection:
		_organization_person_reference_ids = _person_authority.person_ids()
		_organization_place_reference_ids = [DEFAULT_FORMAL_PERSON_PLACE_ID]
	if not _bind_organization_reference_catalog():
		return false
	_player_state = VNextPlayerState.new()
	if not _player_state.bind_person_authority(_person_authority):
		initialization_error = "PlayerState could not bind Formal Person authority"
		return false
	var person_ids := _person_authority.person_ids()
	if person_ids.is_empty() or not _player_state.set_player_id(person_ids[0]):
		initialization_error = "PlayerState could not select a Formal Person"
		return false
	return true


func _configure_organization_authority() -> bool:
	if _organization == null or _person_authority == null:
		initialization_error = "Organization Authority dependencies are unavailable"
		return false
	_organization_authority = VNextOrganizationAuthorityFoundation.create(
		_organization,
		_person_authority.person_ids(),
		_organization_place_reference_ids
	)
	if _organization_authority == null:
		initialization_error = "Organization Authority foundation could not be composed"
		return false
	if _military_state != null:
		return _configure_military_authority_bridge()
	return true


func _configure_military_composition() -> bool:
	_spatial_world = VNextSpatialWorld.create(_spatial_catalog)
	if _spatial_world == null or not _spatial_world.is_valid():
		initialization_error = "Formal Military composition cannot bind Spatial authority"
		return false
	_military_map = VNextMilitaryMapAdapter.new()
	if not _military_map.load_existing_map(_spatial_world):
		initialization_error = "Formal Military map adapter could not bind Spatial authority"
		return false
	_military_state = VNextMilitaryState.new()
	if not _military_state.initialize(_military_map):
		initialization_error = "Formal MilitaryState could not initialize"
		return false
	_military_service = VNextMilitaryService.new()
	return _configure_military_authority_bridge()


func _configure_military_authority_bridge() -> bool:
	_military_authority_bridge = VNextMilitaryAuthorityBridge.create(
		_organization_authority,
		_military_state,
		_military_service,
		_military_map
	)
	if _military_authority_bridge == null:
		initialization_error = "Formal Military Authority bridge could not be composed"
		return false
	return true


func _bind_organization_reference_catalog() -> bool:
	var expected := VNextOrganizationReferenceCatalog.create(
		_organization_person_reference_ids,
		_organization_place_reference_ids
	)
	if expected == null:
		initialization_error = "Organization reference provider is invalid"
		return false
	if not _organization.has_reference_catalog():
		if not _organization.configure_reference_catalog(
			_organization_person_reference_ids,
			_organization_place_reference_ids
		):
			initialization_error = "Organization reference provider cannot be bound"
			return false
	elif _organization.reference_catalog_fingerprint() != expected.fingerprint():
		initialization_error = "Organization reference provider does not match Formal Person authority"
		return false
	if not _organization.is_valid():
		initialization_error = "Organization composition is invalid"
		return false
	return true


func _rebind_player_and_organization_for_restored_persons() -> bool:
	_organization_person_reference_ids = _person_authority.person_ids()
	if not _explicit_organization_reference_injection:
		_organization_place_reference_ids = [DEFAULT_FORMAL_PERSON_PLACE_ID]
	_organization = VNextOrganizationCore.new()
	if not _bind_organization_reference_catalog():
		return false
	_player_state = VNextPlayerState.new()
	if not _player_state.bind_person_authority(_person_authority):
		return false
	return true


func _configure_market_registry() -> bool:
	var economic_aggregate_ids: Array[String] = []
	for record: Dictionary in _economic_static_view.countries():
		var economic_aggregate_id := str(record.get("entity_id", ""))
		if not economic_aggregate_id.is_empty():
			economic_aggregate_ids.append(economic_aggregate_id)
	return _market_registry.configure(
		economic_aggregate_ids, _political_registry_view.entity_ids()
	)


func save_to_user() -> SaveOperationResult:
	if not initialized:
		return SaveOperationResult.fail(
			"not_initialized",
			"正式世界尚未初始化，无法保存。",
			SAVE_PATH
		)
	var snapshot := get_persistent_state()
	var write_error := AtomicJsonFileStore.write_verified(
		SAVE_PATH,
		snapshot,
		Callable(self, "_verify_temporary_save"),
		true
	)
	if not write_error.is_empty():
		return SaveOperationResult.fail(
			"write_error",
			"正式世界保存失败：%s" % write_error,
			SAVE_PATH
		)
	state_changed.emit({"saved": true})
	var result := SaveOperationResult.ok(SAVE_PATH, snapshot)
	result.message = "正式世界已保存。"
	return result


func _verify_temporary_save(absolute_path: String) -> String:
	var loaded := _read_snapshot_file(absolute_path)
	if not loaded.success:
		return "临时存档校验失败：%s" % loaded.message
	var candidate := _new_candidate_world()
	if not candidate.initialize():
		return "临时存档校验失败：正式世界初始化失败：%s" % (
			candidate.initialization_error
		)
	if not candidate.restore_persistent_state(loaded.snapshot):
		return "临时存档校验失败：正式世界状态无效"
	return ""


func load_from_user() -> SaveOperationResult:
	var primary := _restore_snapshot_file(SAVE_PATH)
	if primary.success:
		primary.message = "正式世界存档已恢复。"
		return primary
	var backup_path := SAVE_PATH + AtomicJsonFileStore.BACKUP_SUFFIX
	var backup := _restore_snapshot_file(backup_path)
	if backup.success:
		backup.path = SAVE_PATH
		backup.message = "主存档不可用，已读取安全备份"
		return backup
	return SaveOperationResult.fail(
		"load_error",
		"主存档不可用：%s；安全备份不可用：%s" % [
			primary.message,
			backup.message,
		],
		SAVE_PATH
	)


func _restore_snapshot_file(path: String) -> SaveOperationResult:
	var loaded := _read_snapshot_file(path)
	if not loaded.success:
		return loaded
	if not restore_persistent_state(loaded.snapshot):
		return SaveOperationResult.fail(
			"restore_error",
			"存档状态校验或恢复失败",
			path
		)
	return loaded


func _read_snapshot_file(path: String) -> SaveOperationResult:
	if not FileAccess.file_exists(path):
		return SaveOperationResult.fail("not_found", "存档不存在", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveOperationResult.fail(
			"read_error",
			error_string(FileAccess.get_open_error()),
			path
		)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return SaveOperationResult.fail(
			"malformed_json",
			"第 %d 行：%s" % [
				parser.get_error_line(),
				parser.get_error_message(),
			],
			path
		)
	if not parser.data is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"存档根节点必须是对象",
			path
		)
	return SaveOperationResult.ok(path, parser.data as Dictionary)


func _authoritative_total_hour() -> int:
	return int(total_minutes / 60)


func _validated_time_state(state: Dictionary, schema_id: String) -> Dictionary:
	var economy_state := state.get("economy", {}) as Dictionary
	var saved_total_hour := int(economy_state.get("total_hour", -1))
	if saved_total_hour < 0:
		return {}
	if schema_id in [
		"formal_world_simulation_v2",
		"formal_world_simulation_v3",
		"formal_world_simulation_v4",
		LEGACY_ORGANIZATION_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SCHEMA_ID,
	] and (
		not state.has("total_minutes") or not state.has("minute_remainder")
	):
		return {}
	var has_total_minutes := state.has("total_minutes")
	var has_minute_remainder := state.has("minute_remainder")
	var total := int(state.get("total_minutes", saved_total_hour * 60))
	var remainder := int(state.get("minute_remainder", posmod(total, 60)))
	if not has_total_minutes and has_minute_remainder:
		total = saved_total_hour * 60 + remainder
	if (
		total < 0
		or remainder < 0
		or remainder > 59
		or posmod(total, 60) != remainder
		or int(total / 60) != saved_total_hour
	):
		return {}
	return {
		"total_minutes": total,
		"minute_remainder": remainder,
	}
