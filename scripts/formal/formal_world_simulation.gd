class_name FormalWorldSimulation
extends RefCounted
## Formal product composition root. Immutable evidence, current political
## identity, economic aggregates, Population-evidence-backed named persons, and
## OrganizationCore remain separate owned boundaries. This root owns
## composition and lifecycle, never a second copy of domain authority.

signal state_changed(change: Dictionary)

const SAVE_PATH: String = "user://formal_world_1900.json"
const SCHEMA_ID: String = "formal_world_simulation_v10"
const PREVIOUS_SCHEMA_ID: String = "formal_world_simulation_v8"
const SPATIAL_BASELINE_SCHEMA_ID: String = "formal_world_simulation_v9"
const TERRITORIAL_CONTROL_OWNER: String = "VNextSpatialWorld"
const TERRITORY_AUTHORITY_PRODUCTION_STATUS: String = "SPATIAL_LEGACY_PLACE_AUTHORITY__TERRITORIAL_CONTROL_LEDGER_NON_PRODUCTION_UNCOMPOSED"
const TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED: bool = false
const ORGANIZATION_BASELINE_SCHEMA_ID: String = "formal_world_simulation_v7"
const FORMAL_PERSON_SCHEMA_ID: String = "formal_world_simulation_v6"
const LEGACY_ORGANIZATION_SCHEMA_ID: String = "formal_world_simulation_v5"
const ORGANIZATION_COMPOSITION_STATE_SCHEMA_ID: String = "formal_organization_composition_state_v1"
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
var _organization_evidence := FormalWorldOrganizationEvidenceCatalog.new()
var _organization_evidence_view := FormalWorldOrganizationEvidenceView.new()
var _organization_responsibilities := FormalWorldOrganizationResponsibilityService.new()
var _organization_authority: VNextOrganizationAuthorityFoundation = null
var _military_map: VNextMilitaryMapAdapter = null
var _military_state: VNextMilitaryState = null
var _military_service := VNextMilitaryService.new()
var _military_authority_bridge: VNextMilitaryAuthorityBridge = null
var _organization_person_reference_ids: Array[String] = []
var _organization_place_reference_ids: Array[String] = []
var _formal_start_plan: Dictionary = {}
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
	organization_place_reference_ids: Array[String] = [],
	formal_start_plan: Dictionary = {}
) -> void:
	_formal_start_plan = formal_start_plan.duplicate(true)
	_organization_person_reference_ids = organization_person_reference_ids.duplicate()
	_organization_person_reference_ids.sort()
	_organization_place_reference_ids = organization_place_reference_ids.duplicate()
	_organization_place_reference_ids.sort()
	_explicit_organization_reference_injection = (
		organization_core_value != null
		or not _organization_person_reference_ids.is_empty()
		or not _organization_place_reference_ids.is_empty()
	)
	if _explicit_organization_reference_injection and not _formal_start_plan.is_empty():
		_organization_composition_error = (
			"Formal start plan cannot be combined with injected Organization references"
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
	if not _organization_evidence.configure(_historical_evidence):
		initialization_error = _organization_evidence.initialization_error
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
	if not _configure_spatial_composition():
		initialized = false
		return false
	if not _configure_formal_person_composition():
		initialized = false
		return false
	if not _configure_production_organization_composition():
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
	if not _configure_organization_responsibilities(_authoritative_total_hour()):
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


func _organization_responsibility_economy_view() -> FormalWorldEconomyView:
	if not _economy.is_configured():
		return FormalWorldEconomyView.new()
	return FormalWorldEconomyView.new(
		_economy.read_only_country_observation_snapshot()
	)


func organization_view() -> FormalWorldOrganizationView:
	if _organization == null:
		return FormalWorldOrganizationView.new()
	return FormalWorldOrganizationView.new(_organization.snapshot())


func organization_query_port() -> FormalWorldOrganizationView:
	return organization_view()


func organization_evidence_view() -> FormalWorldOrganizationEvidenceView:
	return FormalWorldOrganizationEvidenceView.new(
		_organization_evidence.read_only_snapshot()
	)


func organization_responsibility_view() -> FormalWorldOrganizationResponsibilityView:
	if not _organization_responsibilities.is_configured():
		return FormalWorldOrganizationResponsibilityView.new()
	return FormalWorldOrganizationResponsibilityView.new(
		_organization_responsibilities.read_only_snapshot()
	)


func organization_responsibility_query_port() -> FormalWorldOrganizationResponsibilityView:
	return organization_responsibility_view()


func spatial_current_hour() -> int:
	return _spatial_world.current_hour() if _spatial_world != null else -1


func spatial_authoritative_fingerprint() -> String:
	if _spatial_world == null or not _spatial_world.is_valid():
		return ""
	return JSON.stringify(_spatial_world.snapshot()).sha256_text()


func spatial_snapshot() -> Dictionary:
	return _spatial_world.snapshot() if _spatial_world != null else {}


func spatial_infrastructure_state(link_id: String) -> Dictionary:
	return _spatial_world.infrastructure_state(link_id) if _spatial_world != null else {}


func spatial_capacity_summary(link_id: String) -> Dictionary:
	return _spatial_world.capacity_summary(link_id) if _spatial_world != null else {}


func spatial_territorial_facts(entity_query: String) -> Dictionary:
	return _spatial_world.get_territorial_facts(entity_query) if _spatial_world != null else {}


func spatial_effective_capacity(link_id: String) -> float:
	return _spatial_world.effective_capacity(link_id) if _spatial_world != null else 0.0


func set_spatial_infrastructure_status(link_id: String, status_value: String) -> bool:
	return (
		initialized
		and _spatial_world != null
		and _spatial_world.set_infrastructure_status(link_id, status_value)
	)


func set_spatial_infrastructure_condition(link_id: String, condition_value: Variant) -> bool:
	return (
		initialized
		and _spatial_world != null
		and _spatial_world.set_infrastructure_condition(link_id, condition_value)
	)


func set_spatial_nominal_capacity(link_id: String, capacity_value: Variant) -> bool:
	return (
		initialized
		and _spatial_world != null
		and _spatial_world.set_nominal_capacity(link_id, capacity_value)
	)


func request_spatial_capacity(
	request_id: String, link_id: String, demand: Variant
) -> Dictionary:
	if not initialized or _spatial_world == null:
		return {"success": false, "accepted": false, "reason": "invalid_world"}
	return _spatial_world.request_capacity(
		request_id, link_id, _authoritative_total_hour(), demand
	)


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


func organization_place_reference_ids() -> Array[String]:
	return _organization_place_reference_ids.duplicate()


func player_person_id() -> String:
	return _player_state.player_id()


func select_player_person(person_id: String) -> bool:
	if not initialized or _person_authority == null:
		return false
	var person := _person_authority.person(person_id)
	if person.is_empty() or not bool(person.get("alive", false)):
		return false
	if not _player_state.set_player_id(person_id):
		return false
	state_changed.emit({"player": true, "person_id": person_id})
	return true


func player_context_view() -> Dictionary:
	## Narrow detached projection for the one authoritative player identity.
	## Missing personal domains are reported as unavailable rather than fabricated.
	var person_id := player_person_id()
	if not initialized or person_id.is_empty() or _person_authority == null:
		return {
			"available": false,
			"reason": "player_person_unavailable",
			"person_id": person_id,
		}
	var person := _person_authority.person(person_id)
	if person.is_empty():
		return {
			"available": false,
			"reason": "player_person_missing",
			"person_id": person_id,
		}
	var claim := _person_authority.population_claim(person_id)
	var population_source_id := str(person.get("population_territory_id", ""))
	var place_id := str(person.get("current_place_id", ""))
	var place := (
		_spatial_catalog.get_place(place_id)
		if _spatial_catalog != null and _spatial_catalog.is_loaded()
		else {}
	)
	var source_polity_id := str(place.get("parent_country_id", population_source_id))
	var runtime_polity_id := _political_registry_view.runtime_id_for_source(
		source_polity_id
	)
	if runtime_polity_id.is_empty():
		runtime_polity_id = _political_registry_view.runtime_id_for_source(
			population_source_id
		)
	var political_observation: Dictionary = {
		"available": false,
		"reason": "no_current_polity_mapping",
		"runtime_entity_id": runtime_polity_id,
		"source_entity_id": source_polity_id,
	}
	if not runtime_polity_id.is_empty():
		var polity := CurrentWorldPoliticalProjection.polity_summary(
			runtime_polity_id,
			_political_registry_view,
			_historical_evidence_view
		)
		if not polity.is_empty():
			political_observation = {
				"available": true,
				"runtime_entity_id": runtime_polity_id,
				"source_entity_id": source_polity_id,
				"name_zh": str(polity.get(
					"name_zh", polity.get("short_name_zh", runtime_polity_id)
				)),
				"status": str(polity.get("status", "")),
				"relationship": str(polity.get("relationship", "")),
				"authority_relations": (
					polity.get("authority_relations", []) as Array
				).duplicate(true),
			}
	var economy_entity_id := _economy.economy_entity_for_polity(
		runtime_polity_id
	)
	if economy_entity_id.is_empty() and _population_input_view.fact(
		population_source_id
	).size() > 0:
		economy_entity_id = population_source_id
	var economic_observation: Dictionary = {
		"available": false,
		"reason": "no_regional_economy_mapping",
		"economy_entity_id": economy_entity_id,
	}
	if not economy_entity_id.is_empty():
		var economy_summary := _economy.country_summary(economy_entity_id)
		if not economy_summary.is_empty():
			economic_observation = {
				"available": true,
				"economy_entity_id": economy_entity_id,
				"population": int(economy_summary.get("population", 0)),
				"daily_totals": (
					economy_summary.get("daily_totals", {}) as Dictionary
				).duplicate(true),
				"admission_status": str(
					economy_summary.get("admission_status", "")
				),
			}
	var demographic_identity := (
		person.get("basic_demographic_identity", {}) as Dictionary
	).duplicate(true)
	var provenance := (person.get("provenance", {}) as Dictionary).duplicate(true)
	return {
		"available": true,
		"reason": "",
		"person_id": person_id,
		"display_label": _stable_player_label(person_id),
		"alive": bool(person.get("alive", false)),
		"population_claim": claim.duplicate(true),
		"population_source": {
			"available": not population_source_id.is_empty(),
			"id": population_source_id,
			"population": _formal_population_total(population_source_id),
			"anonymous_population": formal_person_anonymous_population(
				population_source_id
			),
			"revision": _population_input_view.revision(),
			"fingerprint": _population_input_view.fingerprint(),
			"kind": str(provenance.get("population_source_kind", "")),
		},
		"current_place": {
			"available": not place.is_empty(),
			"id": place_id,
			"map_id": VNextSpatialCatalog.place_query_to_map_id(place_id),
			"name": str(place.get("name", place.get("display_name_zh", place_id))),
			"object_level": str(place.get("object_level", "")),
			"parent_country_id": str(place.get("parent_country_id", "")),
			"parent_region_id": str(place.get("parent_region_id", "")),
		},
		"demographic_identity": demographic_identity,
		"provenance_summary": {
			"kind": str(provenance.get("kind", "")),
			"basis": str(provenance.get("basis", "")),
			"population_source_revision": str(
				provenance.get("population_source_revision", "")
			),
			"population_source_fingerprint": str(
				provenance.get("population_source_fingerprint", "")
			),
			"territory_mutation_converged": bool(
				provenance.get("territory_mutation_converged", false)
			),
			"generation_rules_version": str(
				provenance.get("generation_rules_version", "unavailable")
			),
			"generation_seed": provenance.get("generation_seed", "unavailable"),
			"accepted_draft_index": provenance.get(
				"accepted_draft_index", "unavailable"
			),
			"source_catalog_fingerprint": str(
				provenance.get("source_catalog_fingerprint", "unavailable")
			),
		},
		"memberships": _organization.memberships_for_person(person_id),
		"appointments": _organization.appointments_for_person(person_id),
		"political_observation": political_observation,
		"economic_observation": economic_observation,
		"unsupported_personal_fields": {
			"name": "unavailable",
			"occupation": "unavailable",
			"wage": "unavailable",
			"cash": "unavailable",
			"health": "unavailable",
			"friends": "unavailable",
			"relationships": "unavailable",
			"plans": "unavailable",
			"messages": "unavailable",
			"skills": "unavailable",
			"military_rank": "unavailable",
		},
	}


func _stable_player_label(person_id: String) -> String:
	if person_id.is_empty():
		return "人物 ----"
	return "人物 %s" % person_id.sha256_text().left(4).to_upper()


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
	var starting_total_hour := _authoritative_total_hour()
	var target_total_minutes := total_minutes + minutes
	var target_total_hour := int(target_total_minutes / 60)
	var settled_through_hour := starting_total_hour
	var responsibility_review_days := 0
	var responsibility_organization_view: FormalWorldOrganizationView = null

	# Formal composition owns causal cross-domain ordering. Each crossed day is
	# settled by Economy first, then observed through detached read views by
	# Organization responsibilities. The structural Organization view is immutable
	# during one advance call, so build it once on first review and never cache it
	# across calls. Economy observations remain fresh for every settled day.
	while true:
		var next_day_boundary_hour := (
			int(settled_through_hour / FormalWorldEconomyService.HOURS_PER_DAY) + 1
		) * FormalWorldEconomyService.HOURS_PER_DAY
		if next_day_boundary_hour > target_total_hour:
			break
		total_minutes = next_day_boundary_hour * 60
		if not _synchronize_spatial_to_authoritative_hour():
			assert(false, "Formal Spatial failed to follow authoritative day boundary")
			return _economy.world_summary()
		_economy.settle_hour_range(
			settled_through_hour, next_day_boundary_hour
		)
		if responsibility_organization_view == null:
			responsibility_organization_view = organization_view()
		var reviewed := _organization_responsibilities.review_settled_day(
			next_day_boundary_hour,
			responsibility_organization_view,
			_political_registry_view,
			_organization_responsibility_economy_view()
		)
		assert(
			reviewed,
			"Organization responsibility review failed at settled day boundary %d"
			% next_day_boundary_hour
		)
		responsibility_review_days += 1
		settled_through_hour = next_day_boundary_hour

	total_minutes = target_total_minutes
	var current_total_hour := _authoritative_total_hour()
	if current_total_hour > settled_through_hour:
		if not _synchronize_spatial_to_authoritative_hour():
			assert(false, "Formal Spatial failed to follow authoritative hour")
			return _economy.world_summary()
		_economy.settle_hour_range(
			settled_through_hour, current_total_hour
		)
	var elapsed_hours := current_total_hour - starting_total_hour
	state_changed.emit({
		"time": true,
		"economy": elapsed_hours > 0,
		"organization_responsibilities": responsibility_review_days > 0,
		"hours": elapsed_hours,
		"responsibility_review_days": responsibility_review_days,
	})
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
		"spatial": _spatial_world.snapshot(),
		"persons": _person_authority.snapshot(),
		"player": _player_state.snapshot(),
		"organization": _organization.snapshot(),
		"organization_composition": {
			"schema_id": ORGANIZATION_COMPOSITION_STATE_SCHEMA_ID,
			"fingerprint": _organization_evidence.fingerprint(),
		},
		"organization_responsibilities": _organization_responsibilities.snapshot(),
		"organization_authority": _organization_authority.snapshot(),
		"military_state": _military_state.snapshot(),
	}


func authoritative_fingerprint() -> String:
	if (
		not initialized
		or _organization == null
		or _person_authority == null
		or _organization_authority == null
		or not _organization_responsibilities.is_configured()
		or _spatial_world == null
		or not _spatial_world.is_valid()
		or _spatial_world.current_hour() != _authoritative_total_hour()
		or _military_state == null
	):
		return ""
	return JSON.stringify({
		"schema_id": "formal_world_authoritative_fingerprint_v6",
		"total_minutes": total_minutes,
		"historical_evidence": _historical_evidence.fingerprint(),
		"runtime_politics": JSON.stringify(_political_registry.snapshot()).sha256_text(),
		"markets": JSON.stringify(_market_registry.get_persistent_state()).sha256_text(),
		"economy": JSON.stringify(_economy.get_persistent_state()).sha256_text(),
		"spatial": spatial_authoritative_fingerprint(),
		"persons": _person_authority.state_fingerprint(),
		"player": JSON.stringify(_player_state.snapshot()).sha256_text(),
		"organization": _organization.state_fingerprint(),
		"organization_composition": _organization_evidence.fingerprint(),
		"organization_responsibilities": _organization_responsibilities.state_fingerprint(),
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
			FORMAL_PERSON_SCHEMA_ID,
			ORGANIZATION_BASELINE_SCHEMA_ID,
			PREVIOUS_SCHEMA_ID,
			SPATIAL_BASELINE_SCHEMA_ID,
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
		FORMAL_PERSON_SCHEMA_ID,
		ORGANIZATION_BASELINE_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SPATIAL_BASELINE_SCHEMA_ID,
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
		FORMAL_PERSON_SCHEMA_ID,
		ORGANIZATION_BASELINE_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SPATIAL_BASELINE_SCHEMA_ID,
		SCHEMA_ID,
	]:
		if (
			not state.get("markets", {}) is Dictionary
			or not _market_registry.validate_persistent_state(
				state.get("markets", {}) as Dictionary
			)
		):
			return false
	if schema_id in [
		FORMAL_PERSON_SCHEMA_ID,
		ORGANIZATION_BASELINE_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SPATIAL_BASELINE_SCHEMA_ID,
		SCHEMA_ID,
	]:
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
	if schema_id in [LEGACY_ORGANIZATION_SCHEMA_ID, FORMAL_PERSON_SCHEMA_ID]:
		if (
			not state.get("organization", {}) is Dictionary
			or not _organization.restore(
				state.get("organization", {}) as Dictionary
			)
		):
			return false
		if not _configure_organization_authority():
			return false
	elif schema_id == ORGANIZATION_BASELINE_SCHEMA_ID:
		if (
			not state.get("organization", {}) is Dictionary
			or not _is_canonical_empty_organization_snapshot(
				state.get("organization", {}) as Dictionary
			)
		):
			return false
		if not _configure_organization_authority():
			return false
	elif schema_id in [PREVIOUS_SCHEMA_ID, SPATIAL_BASELINE_SCHEMA_ID, SCHEMA_ID]:
		if (
			not state.get("organization", {}) is Dictionary
			or not state.get("organization_composition", {}) is Dictionary
		):
			return false
		var organization_composition_state := (
			state.get("organization_composition", {}) as Dictionary
		)
		if (
			str(organization_composition_state.get("schema_id", ""))
			!= ORGANIZATION_COMPOSITION_STATE_SCHEMA_ID
			or str(organization_composition_state.get("fingerprint", ""))
			!= _organization_evidence.fingerprint()
			or not _organization.restore(
				state.get("organization", {}) as Dictionary
			)
		):
			return false
		if not _configure_organization_authority():
			return false
	total_minutes = int(validated_time.get("total_minutes", -1))
	if schema_id == SCHEMA_ID:
		if (
			not state.get("spatial", {}) is Dictionary
			or not _spatial_world.restore(state.get("spatial", {}) as Dictionary)
			or _spatial_world.current_hour() != _authoritative_total_hour()
		):
			return false
	else:
		# Pre-v10 Formal saves have no Spatial history. Migration reconstructs only
		# the deterministic baseline and advances its explicit clock; no historical
		# infrastructure/control mutation is inferred.
		if not _spatial_world.advance_to_hour(_authoritative_total_hour()):
			return false
	if schema_id in [
		ORGANIZATION_BASELINE_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SPATIAL_BASELINE_SCHEMA_ID,
		SCHEMA_ID,
	]:
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
	if not _economy.restore_persistent_state(
		state.get("economy", {}) as Dictionary
	):
		return false
	if not _configure_organization_responsibilities(_authoritative_total_hour()):
		return false
	if schema_id in [SPATIAL_BASELINE_SCHEMA_ID, SCHEMA_ID]:
		if (
			not state.get("organization_responsibilities", {}) is Dictionary
			or not _organization_responsibilities.restore(
				state.get("organization_responsibilities", {}) as Dictionary,
				organization_view(),
				organization_evidence_view(),
				_political_registry_view,
				economy_view(),
				_authoritative_total_hour()
			)
		):
			return false
	# Older saves have no institutional monitoring history. Their migration baseline
	# starts at the saved authoritative hour; the first later day boundary reviews.
	initialized = true
	return true


func _adopt_candidate(candidate: FormalWorldSimulation) -> void:
	total_minutes = candidate.total_minutes
	_provenance = candidate._provenance
	_historical_evidence = candidate._historical_evidence
	_organization_evidence = candidate._organization_evidence
	_organization_evidence_view = candidate._organization_evidence_view
	_organization_responsibilities = candidate._organization_responsibilities
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
	_organization_evidence_view = FormalWorldOrganizationEvidenceView.new(
		_organization_evidence.read_only_snapshot()
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


func _configure_spatial_composition() -> bool:
	# Ownership closure: until a source-backed sealed TerritoryUnitCatalog exists,
	# the alternate territory-control ledger remains outside Formal production.
	# Current controller facts therefore have exactly one writable production
	# owner: this SpatialWorld's legacy-place territorial state.
	if TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED:
		initialization_error = "Duplicate production territorial-control authority is forbidden"
		return false
	if not _spatial_catalog.load_legacy_world_map():
		initialization_error = "Formal Spatial catalog could not load source topology"
		return false
	_spatial_world = VNextSpatialWorld.create(_spatial_catalog)
	if _spatial_world == null or not _spatial_world.is_valid():
		initialization_error = "Formal Spatial authority could not be composed"
		return false
	return _spatial_world.current_hour() == _authoritative_total_hour()


func _configure_formal_person_composition() -> bool:
	if not _population_input_view.is_configured():
		initialization_error = "Formal Population input is not configured"
		return false
	if _spatial_world == null or not _spatial_world.is_valid() or not _spatial_catalog.is_loaded():
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
	if not _formal_start_plan.is_empty():
		return _configure_selected_formal_person()
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


func _configure_selected_formal_person() -> bool:
	var person_id := str(_formal_start_plan.get("person_id", ""))
	var claim_id := str(_formal_start_plan.get("claim_id", ""))
	var source_id := str(_formal_start_plan.get("population_source_id", ""))
	var place_id := str(_formal_start_plan.get("start_place_id", ""))
	var demographic := (
		_formal_start_plan.get("basic_demographic_identity", {}) as Dictionary
	)
	var provenance := _formal_start_plan.get("provenance", {}) as Dictionary
	if (
		person_id.is_empty()
		or claim_id.is_empty()
		or source_id.is_empty()
		or place_id.is_empty()
		or demographic.is_empty()
		or provenance.is_empty()
	):
		initialization_error = "Formal selected-person start plan is incomplete"
		return false
	if _population_input_view.population(source_id) <= 0:
		initialization_error = "Formal selected-person population source is unavailable"
		return false
	var place := _spatial_catalog.get_place(place_id)
	if place.is_empty() or str(place.get("parent_country_id", "")) != source_id:
		initialization_error = "Formal selected-person source/place combination is incompatible"
		return false
	if not _person_authority.materialize(
		person_id,
		claim_id,
		source_id,
		demographic,
		place_id,
		provenance
	):
		initialization_error = "Formal selected Person materialization failed: %s" % (
			_person_authority.last_error()
		)
		return false
	_organization_person_reference_ids = [person_id]
	_organization_place_reference_ids = [place_id]
	if not _bind_organization_reference_catalog():
		return false
	_player_state = VNextPlayerState.new()
	if (
		not _player_state.bind_person_authority(_person_authority)
		or not _player_state.set_player_id(person_id)
	):
		initialization_error = "PlayerState could not bind selected Formal Person"
		return false
	return true


func _configure_production_organization_composition() -> bool:
	if _explicit_organization_reference_injection:
		return true
	if _organization == null or not _organization_evidence.is_configured():
		initialization_error = "Formal Organization production composition evidence is unavailable"
		return false
	if not _organization.organization_ids().is_empty():
		initialization_error = "Formal Organization production composition requires an empty OrganizationCore"
		return false
	for organization_id: String in _organization_evidence.organization_ids():
		var evidence_record := _organization_evidence.record(organization_id)
		if not _organization.register_organization(
			organization_id,
			str(evidence_record.get("organization_kind", "")),
			"",
			"",
			true
		):
			initialization_error = "Formal Organization production composition failed: %s" % organization_id
			return false
	return true


func _configure_organization_responsibilities(baseline_hour: int) -> bool:
	_organization_responsibilities = FormalWorldOrganizationResponsibilityService.new()
	if not _organization_responsibilities.configure(
		organization_view(),
		organization_evidence_view(),
		_political_registry_view,
		_organization_responsibility_economy_view(),
		baseline_hour
	):
		initialization_error = _organization_responsibilities.initialization_error
		if initialization_error.is_empty():
			initialization_error = "Formal Organization responsibilities could not be composed"
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
		_organization_place_reference_ids.clear()
		for person_id: String in _organization_person_reference_ids:
			var place_id := _person_authority.current_place(person_id)
			if not place_id.is_empty() and place_id not in _organization_place_reference_ids:
				_organization_place_reference_ids.append(place_id)
		_organization_place_reference_ids.sort()
		if _organization_place_reference_ids.is_empty():
			return false
	_organization = VNextOrganizationCore.new()
	if not _bind_organization_reference_catalog():
		return false
	if not _configure_production_organization_composition():
		return false
	_player_state = VNextPlayerState.new()
	if not _player_state.bind_person_authority(_person_authority):
		return false
	return true


func _is_canonical_empty_organization_snapshot(snapshot: Dictionary) -> bool:
	if str(snapshot.get("schema_id", "")) != VNextOrganizationCore.SNAPSHOT_SCHEMA_ID:
		return false
	var organizations_value: Variant = snapshot.get("organizations", [])
	if not organizations_value is Array or not (organizations_value as Array).is_empty():
		return false
	return int(snapshot.get("revision", -1)) == 0


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
	var persistence_document := FormalWorldPersistenceDocument.encode(snapshot)
	if persistence_document.is_empty():
		return SaveOperationResult.fail(
			"encode_error",
			"正式世界精确持久化载荷编码失败",
			SAVE_PATH
		)
	var write_error := AtomicJsonFileStore.write_verified(
		SAVE_PATH,
		persistence_document,
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
	var decoded := FormalWorldPersistenceDocument.decode(parser.data as Dictionary)
	if not bool(decoded.get("success", false)):
		return SaveOperationResult.fail(
			"invalid_snapshot",
			str(decoded.get("error", "正式世界持久化文档无效")),
			path
		)
	var snapshot: Variant = decoded.get("snapshot", {})
	if not snapshot is Dictionary:
		return SaveOperationResult.fail(
			"invalid_snapshot",
			"正式世界持久化载荷不是快照对象",
			path
		)
	return SaveOperationResult.ok(path, snapshot as Dictionary)


func _authoritative_total_hour() -> int:
	return int(total_minutes / 60)


func _synchronize_spatial_to_authoritative_hour() -> bool:
	return (
		_spatial_world != null
		and _spatial_world.is_valid()
		and _spatial_world.advance_to_hour(_authoritative_total_hour())
		and _spatial_world.current_hour() == _authoritative_total_hour()
	)


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
		ORGANIZATION_BASELINE_SCHEMA_ID,
		PREVIOUS_SCHEMA_ID,
		SPATIAL_BASELINE_SCHEMA_ID,
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
