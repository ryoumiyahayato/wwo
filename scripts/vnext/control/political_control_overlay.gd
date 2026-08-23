class_name VNextPoliticalControlOverlay
extends RefCounted
## Political facts keyed by physical place. Spatial validates location only and
## never owns the controller values stored here.

const SNAPSHOT_SCHEMA_ID: String = "vnext_political_control_overlay_v1"

var _spatial_catalog: VNextSpatialCatalog = null
var _known_political_ids: Dictionary = {}
var _facts_by_place: Dictionary = {}
var _revision: int = 0


static func create(
	spatial_catalog: VNextSpatialCatalog,
	political_unit_ids: Array[String]
) -> VNextPoliticalControlOverlay:
	var overlay := VNextPoliticalControlOverlay.new()
	return overlay if overlay.initialize(spatial_catalog, political_unit_ids) else null


func initialize(spatial_catalog: VNextSpatialCatalog, political_unit_ids: Array[String]) -> bool:
	if _spatial_catalog != null or spatial_catalog == null or not spatial_catalog.is_loaded():
		return false
	var known: Dictionary = {}
	for political_id: String in political_unit_ids:
		if not VNextTypedCrosswalkCatalog._is_local_id(political_id) or known.has(political_id):
			return false
		known[political_id] = true
	if known.is_empty():
		return false
	_spatial_catalog = spatial_catalog
	_known_political_ids = known
	return true


func is_valid() -> bool:
	if _spatial_catalog == null or not _spatial_catalog.is_loaded() or _known_political_ids.is_empty():
		return false
	for raw_place_id: Variant in _facts_by_place.keys():
		var place_id: String = str(raw_place_id)
		if not _spatial_catalog.has_place(place_id) or not _valid_fact(_facts_by_place[place_id] as Dictionary):
			return false
	return true


func set_control(
	place_query: String,
	legal_sovereign_id: String,
	administrative_authority_id: String,
	effective_controller_id: String,
	effective_from: String
) -> bool:
	if not is_valid():
		return false
	var place_id: String = VNextSpatialCatalog.map_id_to_place_id(
		VNextSpatialCatalog.place_query_to_map_id(place_query)
	)
	var candidate: Dictionary = {
		"place_id": place_id,
		"legal_sovereign_id": legal_sovereign_id,
		"administrative_authority_id": administrative_authority_id,
		"effective_controller_id": effective_controller_id,
		"effective_from": effective_from,
	}
	if not _spatial_catalog.has_place(place_id) or not _valid_fact(candidate):
		return false
	_facts_by_place[place_id] = candidate
	_revision += 1
	return true


func control_at(place_query: String) -> Dictionary:
	var place_id: String = VNextSpatialCatalog.map_id_to_place_id(
		VNextSpatialCatalog.place_query_to_map_id(place_query)
	)
	var value: Variant = _facts_by_place.get(place_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func revision() -> int:
	return _revision


func snapshot() -> Dictionary:
	if not is_valid():
		return {}
	var facts: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id: Variant in _facts_by_place.keys():
		ids.append(str(raw_id))
	ids.sort()
	for place_id: String in ids:
		facts.append((_facts_by_place[place_id] as Dictionary).duplicate(true))
	return {"schema_id": SNAPSHOT_SCHEMA_ID, "revision": _revision, "facts": facts}


func _valid_fact(fact: Dictionary) -> bool:
	for field_name: String in [
		"place_id", "legal_sovereign_id", "administrative_authority_id",
		"effective_controller_id", "effective_from",
	]:
		if not fact.has(field_name) or typeof(fact.get(field_name)) != TYPE_STRING:
			return false
	if not _spatial_catalog.has_place(str(fact.get("place_id", ""))):
		return false
	for field_name: String in [
		"legal_sovereign_id", "administrative_authority_id", "effective_controller_id",
	]:
		if not _known_political_ids.has(str(fact.get(field_name, ""))):
			return false
	return VNextFactProvenance.is_iso_date(str(fact.get("effective_from", "")))
