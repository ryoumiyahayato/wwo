class_name VNextPopulationEconomyRegionCrosswalk
extends RefCounted
## Explicit Population-source to physical/economic Spatial-region mapping.
##
## This object contains no population values and no political facts. A source
## key is mapped exactly once to one existing Spatial region. The provider
## later requires complete coverage of the bound Population source keys.

const SNAPSHOT_SCHEMA_ID: String = "vnext_population_economy_region_crosswalk_v1"

var _initialized: bool = false
var _spatial_catalog: VNextSpatialCatalog = null
var _source_to_region: Dictionary = {}
var _ordered_source_ids: Array[String] = []


static func create(
	spatial_catalog: VNextSpatialCatalog, source_to_region: Dictionary
) -> VNextPopulationEconomyRegionCrosswalk:
	var crosswalk := VNextPopulationEconomyRegionCrosswalk.new()
	if not crosswalk.configure(spatial_catalog, source_to_region):
		return null
	return crosswalk


func configure(
	spatial_catalog: VNextSpatialCatalog, source_to_region: Dictionary
) -> bool:
	if _initialized:
		return false
	if spatial_catalog == null or not spatial_catalog.is_loaded():
		return false
	if source_to_region.is_empty():
		return false

	var candidate_mapping: Dictionary = {}
	for raw_source_id: Variant in source_to_region.keys():
		if typeof(raw_source_id) != TYPE_STRING:
			return false
		var source_id: String = _normalize_source_id(
			str(raw_source_id), spatial_catalog
		)
		var raw_region_id: Variant = source_to_region.get(raw_source_id)
		if typeof(raw_region_id) != TYPE_STRING:
			return false
		var region_id: String = _normalize_region_id(
			str(raw_region_id), spatial_catalog
		)
		if source_id.is_empty() or region_id.is_empty() or candidate_mapping.has(source_id):
			return false
		candidate_mapping[source_id] = region_id

	var candidate_source_ids: Array[String] = []
	for raw_source_id: Variant in candidate_mapping.keys():
		candidate_source_ids.append(str(raw_source_id))
	candidate_source_ids.sort()

	_initialized = true
	_spatial_catalog = spatial_catalog
	_source_to_region = candidate_mapping
	_ordered_source_ids = candidate_source_ids
	return true


func is_valid() -> bool:
	if (
		not _initialized
		or _spatial_catalog == null
		or not _spatial_catalog.is_loaded()
		or _source_to_region.is_empty()
		or _ordered_source_ids.size() != _source_to_region.size()
	):
		return false
	var seen_source_ids: Dictionary = {}
	for source_id: String in _ordered_source_ids:
		if (
			seen_source_ids.has(source_id)
			or not _source_to_region.has(source_id)
			or _normalize_source_id(source_id, _spatial_catalog).is_empty()
		):
			return false
		var region_id: String = str(_source_to_region.get(source_id, ""))
		if _normalize_region_id(region_id, _spatial_catalog).is_empty():
			return false
		seen_source_ids[source_id] = true
	return seen_source_ids.size() == _source_to_region.size()


func source_ids() -> Array[String]:
	return _ordered_source_ids.duplicate()


func source_count() -> int:
	return _ordered_source_ids.size()


func has_source(source_id: String) -> bool:
	return is_valid() and _source_to_region.has(source_id)


func region_for_source(source_id: String) -> String:
	if not is_valid():
		return ""
	return str(_source_to_region.get(source_id, ""))


func region_ids() -> Array[String]:
	if not is_valid():
		return []
	var seen_region_ids: Dictionary = {}
	for source_id: String in _ordered_source_ids:
		seen_region_ids[str(_source_to_region[source_id])] = true
	var output: Array[String] = []
	for raw_region_id: Variant in seen_region_ids.keys():
		output.append(str(raw_region_id))
	output.sort()
	return output


func mapping() -> Dictionary:
	if not is_valid():
		return {}
	var output: Dictionary = {}
	for source_id: String in _ordered_source_ids:
		output[source_id] = str(_source_to_region[source_id])
	return output


func snapshot() -> Dictionary:
	if not is_valid():
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"source_to_region": mapping(),
		"source_ids": source_ids(),
		"region_ids": region_ids(),
	}


static func _normalize_source_id(
	candidate: String, spatial_catalog: VNextSpatialCatalog
) -> String:
	var separator: int = candidate.find(":")
	if separator <= 0 or separator >= candidate.length() - 1:
		return ""
	var kind: String = candidate.left(separator)
	var local_id: String = candidate.substr(separator + 1)
	if not _is_valid_local_id(local_id):
		return ""
	if kind == "place" and spatial_catalog.has_place(candidate):
		return candidate
	if kind == "region" and spatial_catalog.has_region(local_id):
		return candidate
	return ""


static func _normalize_region_id(
	candidate: String, spatial_catalog: VNextSpatialCatalog
) -> String:
	var separator: int = candidate.find(":")
	if separator <= 0 or separator >= candidate.length() - 1:
		return ""
	if candidate.left(separator) != "region":
		return ""
	var local_id: String = candidate.substr(separator + 1)
	if not _is_valid_local_id(local_id) or not spatial_catalog.has_region(local_id):
		return ""
	return "region:" + local_id


static func _is_valid_local_id(candidate: String) -> bool:
	if candidate.is_empty():
		return false
	for character_index: int in candidate.length():
		var character: String = candidate.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true
