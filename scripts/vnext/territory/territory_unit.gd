class_name VNextTerritoryUnit
extends RefCounted
## Immutable identity record for a catalog-owned geometry unit.
##
## Political ownership, runtime control, population, economy, inventory,
## occupation, and military state belong to later ledgers keyed by this ID.

const STABLE_ID = preload("res://scripts/vnext/identity/stable_id.gd")

var _configured: bool = false
var _territory_unit_id: String = ""
var _catalog_version: String = ""
var _geometry_ref: String = ""
var _source_snapshot_ref: String = ""
var _neighbor_ids: Array[String] = []


func configure(
	territory_unit_id_value: Variant,
	catalog_version_value: Variant,
	geometry_ref_value: Variant,
	source_snapshot_ref_value: Variant,
	neighbor_ids_value: Variant = []
) -> bool:
	if _configured:
		return false
	if (
		typeof(territory_unit_id_value) != TYPE_STRING
		or not is_valid_territory_unit_id(territory_unit_id_value as String)
	):
		return false
	if (
		typeof(catalog_version_value) != TYPE_STRING
		or not is_valid_catalog_version(catalog_version_value as String)
	):
		return false
	if (
		typeof(geometry_ref_value) != TYPE_STRING
		or not is_valid_reference(geometry_ref_value as String)
	):
		return false
	if (
		typeof(source_snapshot_ref_value) != TYPE_STRING
		or not is_valid_reference(source_snapshot_ref_value as String)
	):
		return false
	if typeof(neighbor_ids_value) != TYPE_ARRAY:
		return false

	var candidate_id: String = territory_unit_id_value as String
	var candidate_neighbors: Array[String] = []
	for neighbor_value: Variant in neighbor_ids_value as Array:
		if (
			typeof(neighbor_value) != TYPE_STRING
			or not is_valid_territory_unit_id(neighbor_value as String)
		):
			return false
		var neighbor_id: String = neighbor_value as String
		if neighbor_id == candidate_id or candidate_neighbors.has(neighbor_id):
			return false
		candidate_neighbors.append(neighbor_id)
	candidate_neighbors.sort()

	_territory_unit_id = candidate_id
	_catalog_version = catalog_version_value as String
	_geometry_ref = geometry_ref_value as String
	_source_snapshot_ref = source_snapshot_ref_value as String
	_neighbor_ids = candidate_neighbors
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func territory_unit_id() -> String:
	return _territory_unit_id


func catalog_version() -> String:
	return _catalog_version


func geometry_ref() -> String:
	return _geometry_ref


func source_snapshot_ref() -> String:
	return _source_snapshot_ref


func neighbor_ids() -> Array[String]:
	return _copy_strings(_neighbor_ids)


func copy_detached() -> VNextTerritoryUnit:
	if not _configured:
		return null
	var copied := VNextTerritoryUnit.new()
	if not copied.configure(
		_territory_unit_id,
		_catalog_version,
		_geometry_ref,
		_source_snapshot_ref,
		_neighbor_ids
	):
		return null
	return copied


func to_detached_dict() -> Dictionary:
	if not _configured:
		return {}
	return {
		"territory_unit_id": _territory_unit_id,
		"catalog_version": _catalog_version,
		"geometry_ref": _geometry_ref,
		"source_snapshot_ref": _source_snapshot_ref,
		"neighbor_ids": _copy_strings(_neighbor_ids),
	}


static func is_valid_territory_unit_id(candidate_value: String) -> bool:
	return (
		STABLE_ID.is_valid(candidate_value)
		and STABLE_ID.kind_of(candidate_value) == "territory_unit"
	)


static func is_valid_catalog_version(candidate_value: String) -> bool:
	if candidate_value.is_empty() or candidate_value != candidate_value.strip_edges():
		return false
	for character_index: int in candidate_value.length():
		var character: String = candidate_value.substr(character_index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_.-".contains(character):
			return false
	return true


static func is_valid_reference(candidate_value: String) -> bool:
	return (
		not candidate_value.is_empty()
		and candidate_value == candidate_value.strip_edges()
		and not candidate_value.contains(" ")
		and not candidate_value.contains("\t")
		and not candidate_value.contains("\n")
		and not candidate_value.contains("\r")
	)


static func _copy_strings(source: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	for value: String in source:
		copied.append(value)
	return copied
