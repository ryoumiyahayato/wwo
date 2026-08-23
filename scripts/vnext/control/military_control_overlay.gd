class_name VNextMilitaryControlOverlay
extends RefCounted
## Narrow ownership boundary only; this is not Military gameplay.

var _spatial_catalog: VNextSpatialCatalog = null
var _known_controller_ids: Dictionary = {}
var _control_by_place: Dictionary = {}
var _revision: int = 0


static func create(
	spatial_catalog: VNextSpatialCatalog,
	controller_ids: Array[String]
) -> VNextMilitaryControlOverlay:
	var overlay := VNextMilitaryControlOverlay.new()
	return overlay if overlay.initialize(spatial_catalog, controller_ids) else null


func initialize(spatial_catalog: VNextSpatialCatalog, controller_ids: Array[String]) -> bool:
	if _spatial_catalog != null or spatial_catalog == null or not spatial_catalog.is_loaded():
		return false
	for controller_id: String in controller_ids:
		if not VNextTypedCrosswalkCatalog._is_local_id(controller_id) or _known_controller_ids.has(controller_id):
			return false
		_known_controller_ids[controller_id] = true
	if _known_controller_ids.is_empty():
		return false
	_spatial_catalog = spatial_catalog
	return true


func is_valid() -> bool:
	return _spatial_catalog != null and _spatial_catalog.is_loaded() and not _known_controller_ids.is_empty()


func set_controller(place_query: String, controller_id: String, effective_from: String) -> bool:
	if not is_valid() or not _known_controller_ids.has(controller_id) or not VNextFactProvenance.is_iso_date(effective_from):
		return false
	var place_id: String = VNextSpatialCatalog.map_id_to_place_id(
		VNextSpatialCatalog.place_query_to_map_id(place_query)
	)
	if not _spatial_catalog.has_place(place_id):
		return false
	_control_by_place[place_id] = {
		"place_id": place_id,
		"military_controller_id": controller_id,
		"effective_from": effective_from,
	}
	_revision += 1
	return true


func control_at(place_query: String) -> Dictionary:
	var place_id: String = VNextSpatialCatalog.map_id_to_place_id(
		VNextSpatialCatalog.place_query_to_map_id(place_query)
	)
	var value: Variant = _control_by_place.get(place_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func revision() -> int:
	return _revision
