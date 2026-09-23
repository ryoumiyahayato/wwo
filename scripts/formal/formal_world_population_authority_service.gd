class_name FormalWorldPopulationAuthorityService
extends RefCounted
## Formal composition boundary for Current World mutable Population totals.
##
## Immutable historical/economic population evidence is used only to seed
## one-to-one territory mappings. Ambiguous multi-territory aggregates remain
## explicitly uninitialized; no area, density, weight, or random split is used.

var initialization_error: String = ""
var _authority: VNextPopulationAuthority = null
var _territory_provider: VNextProductionTerritoryUnitCatalogProvider = null
var _economy_to_territories: Dictionary = {}
var _unmapped_evidence_ids: Array[String] = []


func configure(
	territory_catalog: VNextTerritoryUnitCatalog,
	territory_provider: VNextProductionTerritoryUnitCatalogProvider,
	economic_static_view: FormalWorldEconomicStaticView,
	population_input_view: FormalWorldPopulationInputView
) -> bool:
	if is_configured():
		return _fail("Formal Population authority service is already configured")
	initialization_error = ""
	if (
		territory_catalog == null
		or not territory_catalog.is_sealed()
		or territory_provider == null
		or not territory_provider.is_loaded()
		or economic_static_view == null
		or not economic_static_view.is_configured()
		or population_input_view == null
		or not population_input_view.is_configured()
	):
		return _fail("Formal Population authority dependencies are unavailable")
	_territory_provider = territory_provider
	_authority = VNextPopulationAuthority.create(territory_catalog)
	if _authority == null:
		return _fail("Formal Population authority could not bind TerritoryUnit catalog")

	var crosswalk_by_economy: Dictionary = {}
	for record: Dictionary in economic_static_view.crosswalk_records():
		var economy_id := str(record.get("economy_entity_id", ""))
		if economy_id.is_empty() or crosswalk_by_economy.has(economy_id):
			return _fail("Population economy crosswalk contains invalid or duplicate identity")
		crosswalk_by_economy[economy_id] = record.duplicate(true)

	var initialized_territories: Dictionary = {}
	for record: Dictionary in economic_static_view.countries():
		var economy_id := str(record.get("entity_id", ""))
		if economy_id.is_empty():
			return _fail("Population evidence country is missing economy identity")
		var territory_ids := _resolve_territory_ids(
			economy_id, territory_provider, crosswalk_by_economy
		)
		_economy_to_territories[economy_id] = territory_ids.duplicate()
		if territory_ids.size() != 1:
			_unmapped_evidence_ids.append(economy_id)
			continue
		var territory_unit_id: String = territory_ids[0]
		if initialized_territories.has(territory_unit_id):
			return _fail(
				"Population evidence maps multiple aggregates to one TerritoryUnit: %s"
				% territory_unit_id
			)
		var total_population := population_input_view.population(economy_id)
		if total_population <= 0:
			return _fail("Population evidence is missing a positive total: %s" % economy_id)
		if not _authority.initialize_population(territory_unit_id, total_population):
			return _fail(
				"Population initialization failed for %s: %s"
				% [economy_id, _authority.last_error()]
			)
		initialized_territories[territory_unit_id] = true

	_unmapped_evidence_ids.sort()
	return true


func is_configured() -> bool:
	return _authority != null and _authority.is_configured()


func fingerprint() -> String:
	return _authority.fingerprint() if is_configured() else ""


func revision() -> int:
	return _authority.revision() if is_configured() else -1


func snapshot() -> Dictionary:
	return _authority.snapshot() if is_configured() else {}


func restore(snapshot_value: Variant) -> bool:
	if not is_configured():
		return false
	return _authority.restore(snapshot_value)


func population_for_territory(territory_unit_id: String) -> int:
	if not is_configured() or not _authority.has_population(territory_unit_id):
		return -1
	return int(
		_authority.population_for_territory(territory_unit_id).get(
			"total_population", -1
		)
	)


func population_for_reference(reference_id: String) -> int:
	var territory_unit_id := territory_unit_id_for_reference(reference_id)
	return population_for_territory(territory_unit_id) if not territory_unit_id.is_empty() else -1


func territory_unit_id_for_reference(reference_id: String) -> String:
	if not is_configured() or reference_id.is_empty():
		return ""
	if _authority.has_population(reference_id):
		return reference_id
	var political_mapping := _territory_provider.territory_unit_id_for_political_unit(
		reference_id
	)
	if not political_mapping.is_empty() and _authority.has_population(political_mapping):
		return political_mapping
	var economy_mapping_value: Variant = _economy_to_territories.get(reference_id, [])
	if economy_mapping_value is Array:
		var economy_mapping := economy_mapping_value as Array
		if economy_mapping.size() == 1:
			var territory_unit_id := str(economy_mapping[0])
			if _authority.has_population(territory_unit_id):
				return territory_unit_id
	return ""


func initialized_territory_count() -> int:
	return _authority.population_states().size() if is_configured() else 0


func uninitialized_territory_count() -> int:
	if not is_configured():
		return -1
	return _territory_provider.territory_unit_count() - initialized_territory_count()


func unmapped_evidence_ids() -> Array[String]:
	return _unmapped_evidence_ids.duplicate()


func unmapped_evidence_count() -> int:
	return _unmapped_evidence_ids.size()


func economy_territory_ids(economy_id: String) -> Array[String]:
	var value: Variant = _economy_to_territories.get(economy_id, [])
	var output: Array[String] = []
	if value is Array:
		for raw_id: Variant in value as Array:
			output.append(str(raw_id))
	return output


func prepare_transfer(
	source_territory_unit_id: String,
	destination_territory_unit_id: String,
	amount: Variant,
	expected_revision: Variant
) -> VNextPopulationCandidate:
	if not is_configured():
		return null
	return _authority.prepare_transfer(
		source_territory_unit_id,
		destination_territory_unit_id,
		amount,
		expected_revision
	)


func adopt_candidate(candidate: VNextPopulationCandidate) -> bool:
	return is_configured() and _authority.adopt_candidate(candidate)


func _resolve_territory_ids(
	economy_id: String,
	territory_provider: VNextProductionTerritoryUnitCatalogProvider,
	crosswalk_by_economy: Dictionary
) -> Array[String]:
	var direct := territory_provider.territory_unit_id_for_political_unit(economy_id)
	if not direct.is_empty():
		var direct_result: Array[String] = [direct]
		return direct_result
	var result: Array[String] = []
	var crosswalk_value: Variant = crosswalk_by_economy.get(economy_id, {})
	if not crosswalk_value is Dictionary:
		return result
	var crosswalk := crosswalk_value as Dictionary
	var polity_ids_value: Variant = crosswalk.get("polity_ids", [])
	if not polity_ids_value is Array:
		return result
	for raw_polity_id: Variant in polity_ids_value as Array:
		var polity_id := str(raw_polity_id)
		var territory_unit_id := territory_provider.territory_unit_id_for_political_unit(
			polity_id
		)
		if territory_unit_id.is_empty() or result.has(territory_unit_id):
			return []
		result.append(territory_unit_id)
	result.sort()
	return result


func _fail(message: String) -> bool:
	initialization_error = message
	return false
