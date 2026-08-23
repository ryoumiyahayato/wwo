class_name ProductPopulationProjection
extends RefCounted
## Read-only product boundary around the one vNext Population owner.
## Geographic presentation remains fail-closed until an approved crosswalk exists.

const GEOGRAPHIC_UNAVAILABLE: String = "NOT AVAILABLE FOR THIS GEOGRAPHIC SELECTION"

var _owner: VNextMacroPopulation = null
var _provider: VNextPopulationEvidenceProvider = null
var _crosswalk: VNextTypedCrosswalkCatalog = null
var _economic_regions: VNextEconomicRegionCatalog = null


func initialize(
	owner: VNextMacroPopulation,
	provider: VNextPopulationEvidenceProvider,
	crosswalk: VNextTypedCrosswalkCatalog,
	economic_regions: VNextEconomicRegionCatalog
) -> bool:
	if _owner != null:
		return false
	if (
		owner == null or not owner.is_read_only_evidence_owner()
		or provider == null or not provider.is_loaded()
		or crosswalk == null or not crosswalk.is_loaded()
		or economic_regions == null or not economic_regions.is_loaded()
		or crosswalk.size() != 0
		or economic_regions.status() != "EMPTY / NOT AVAILABLE"
		or owner.provider_revision() != provider.revision()
		or owner.catalog_revision() != provider.catalog().revision()
		or owner.population_unit_ids() != provider.population_unit_ids()
		or owner.supported_fact_count() != provider.population_unit_ids().size()
	):
		return false
	for unit_id: String in provider.population_unit_ids():
		var observation: Dictionary = owner.observation_at(unit_id)
		var evidence: Dictionary = provider.fact_at(unit_id)
		if (
			observation.is_empty() or evidence.is_empty()
			or int(observation.get("total_population", -1))
				!= int(evidence.get("total_population", -2))
			or observation.get("provenance", {}) != evidence.get("provenance", {})
		):
			return false
	_owner = owner
	_provider = provider
	_crosswalk = crosswalk
	_economic_regions = economic_regions
	return true


func is_valid() -> bool:
	return (
		_owner != null and _owner.is_read_only_evidence_owner()
		and _provider != null and _provider.is_loaded()
		and _crosswalk != null and _crosswalk.is_loaded() and _crosswalk.size() == 0
		and _economic_regions != null and _economic_regions.is_loaded()
		and _economic_regions.status() == "EMPTY / NOT AVAILABLE"
		and _owner.provider_revision() == _provider.revision()
		and _owner.catalog_revision() == _provider.catalog().revision()
		and _owner.supported_fact_count() == _provider.population_unit_ids().size()
	)


func owner_instance_id() -> int:
	return 0 if _owner == null else _owner.get_instance_id()


func supported_fact_count() -> int:
	return _owner.supported_fact_count() if is_valid() else 0


func provider_revision() -> String:
	return _provider.revision() if is_valid() else ""


func catalog_revision() -> String:
	return _provider.catalog().revision() if is_valid() else ""


func crosswalk_status() -> String:
	return _crosswalk.status() if is_valid() else "NOT AVAILABLE"


func crosswalk_count() -> int:
	return _crosswalk.size() if is_valid() else -1


func economic_geography_status() -> String:
	return _economic_regions.status() if is_valid() else "NOT AVAILABLE"


func population_unit_ids() -> Array[String]:
	return _owner.population_unit_ids() if is_valid() else []


func evidence_at(unit_id: String) -> Dictionary:
	return _owner.observation_at(unit_id) if is_valid() else {}


func first_evidence() -> Dictionary:
	var ids: Array[String] = population_unit_ids()
	return evidence_at(ids[0]) if not ids.is_empty() else {}


func observation_snapshot() -> Dictionary:
	return _owner.observation_snapshot() if is_valid() else {}


func persistence_reference() -> Dictionary:
	return _owner.persistence_reference() if is_valid() else {}


func is_persistence_reference_compatible(reference: Dictionary) -> bool:
	if not is_valid() or reference.size() != 6:
		return false
	return (
		str(reference.get("schema_id", ""))
			== VNextMacroPopulation.PERSISTENCE_REFERENCE_SCHEMA_ID
		and str(reference.get("state_kind", "")) == "IMMUTABLE_INITIALIZATION_DERIVED"
		and int(reference.get("population_revision", -1)) == _owner.population_revision()
		and str(reference.get("provider_revision", "")) == provider_revision()
		and str(reference.get("catalog_revision", "")) == catalog_revision()
		and int(reference.get("supported_fact_count", -1)) == supported_fact_count()
	)


func geographic_selection_view(
	political_unit_id: String, query_date: String
) -> Dictionary:
	if not is_valid() or political_unit_id.is_empty() or not VNextFactProvenance.is_iso_date(query_date):
		return {}
	# No identity, name, geometry, or numeric shortcut can replace an approved
	# PopulationUnit↔PoliticalUnit crosswalk. The empty mapping is product truth.
	return {
		"status": GEOGRAPHIC_UNAVAILABLE,
		"political_unit_id": political_unit_id,
		"query_date": query_date,
		"population_unit_id": "",
		"crosswalk_used": false,
		"crosswalk_count": _crosswalk.size(),
		"precision": VNextFactProvenance.UNKNOWN,
		"applicability": VNextFactProvenance.UNAVAILABLE,
		"population": null,
	}


func regional_view(spatial_region_id: String) -> Dictionary:
	if not is_valid() or spatial_region_id.is_empty():
		return {}
	return {
		"status": GEOGRAPHIC_UNAVAILABLE,
		"spatial_region_id": spatial_region_id,
		"population": null,
		"crosswalk_used": false,
	}


func city_view(city_id: String) -> Dictionary:
	if not is_valid() or city_id.is_empty():
		return {}
	return {
		"status": GEOGRAPHIC_UNAVAILABLE,
		"city_id": city_id,
		"population": null,
		"crosswalk_used": false,
	}
