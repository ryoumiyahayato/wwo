class_name VNextProductionTerritoryUnitCatalogProvider
extends RefCounted
## Source-backed production provider for immutable 1900 TerritoryUnit identity.
##
## Geometry identity comes from the committed CShapes snapshot. Political unit
## IDs are retained only as an explicit crosswalk and never become Territory
## identity themselves.

const TERRITORY_UNIT = preload("res://scripts/vnext/territory/territory_unit.gd")
const TERRITORY_CATALOG = preload(
	"res://scripts/vnext/territory/territory_unit_catalog.gd"
)

const CATALOG_VERSION: String = "cshapes_1900_territory_unit_v1"
const SNAPSHOT_DATE: String = "1900-03-12"
const GEOMETRY_PROVIDER: String = "cshapes_2_0"
const POLITICAL_UNITS_PATH: String = (
	"res://data/world_map/historical/political_units_1900.json"
)
const GEOMETRY_SNAPSHOT_PATH: String = (
	"res://data/world_map/historical/cshapes_1900_snapshot.json"
)
const ADJACENCY_PATH: String = (
	"res://data/vnext/territory/cshapes_1900_land_adjacency.json"
)
const ADJACENCY_SCHEMA_ID: String = "cshapes_1900_land_adjacency_v1"

var _catalog: VNextTerritoryUnitCatalog = null
var _political_to_territory: Dictionary = {}
var _territory_to_political: Dictionary = {}
var _errors: Array[String] = []


func load() -> bool:
	if _catalog != null:
		return _fail("production TerritoryUnit catalog can only load once")
	_errors.clear()
	var political_document := _read_document(POLITICAL_UNITS_PATH)
	var geometry_document := _read_document(GEOMETRY_SNAPSHOT_PATH)
	var adjacency_document := _read_document(ADJACENCY_PATH)
	if (
		political_document.is_empty()
		or geometry_document.is_empty()
		or adjacency_document.is_empty()
	):
		return false
	if (
		str(political_document.get("snapshot_date", "")) != SNAPSHOT_DATE
		or str(geometry_document.get("snapshot_date", "")) != SNAPSHOT_DATE
		or str(adjacency_document.get("snapshot_date", "")) != SNAPSHOT_DATE
	):
		return _fail("production TerritoryUnit sources do not share the 1900 snapshot date")
	if str(geometry_document.get("provider", "")) != GEOMETRY_PROVIDER:
		return _fail("production TerritoryUnit geometry provider is invalid")
	if str(adjacency_document.get("geometry_provider", "")) != GEOMETRY_PROVIDER:
		return _fail("production TerritoryUnit adjacency provider is invalid")
	if str(adjacency_document.get("schema_id", "")) != ADJACENCY_SCHEMA_ID:
		return _fail("production TerritoryUnit adjacency schema is invalid")

	var source_value: Variant = geometry_document.get("source", {})
	if typeof(source_value) != TYPE_DICTIONARY:
		return _fail("production TerritoryUnit geometry provenance is missing")
	var geometry_source := source_value as Dictionary
	var source_sha256 := str(geometry_source.get("source_sha256", ""))
	if source_sha256.length() != 64:
		return _fail("production TerritoryUnit geometry source hash is invalid")
	if str(adjacency_document.get("source_dataset_sha256", "")) != source_sha256:
		return _fail("production TerritoryUnit adjacency is not bound to the geometry source")

	var feature_index := _index_geometry_features(geometry_document)
	if feature_index.is_empty():
		return false
	var political_by_geometry := _index_political_units(
		political_document, feature_index
	)
	if political_by_geometry.is_empty():
		return false
	var adjacency_index := _index_adjacency(
		adjacency_document, feature_index
	)
	if adjacency_index.is_empty():
		return false
	if (
		feature_index.size() != political_by_geometry.size()
		or feature_index.size() != adjacency_index.size()
	):
		return _fail("production TerritoryUnit source coverage is not one-to-one")

	var candidate := VNextTerritoryUnitCatalog.new()
	if not candidate.configure(CATALOG_VERSION):
		return _fail("production TerritoryUnit catalog could not configure")
	var candidate_political_to_territory: Dictionary = {}
	var candidate_territory_to_political: Dictionary = {}
	var geometry_ids: Array[String] = []
	for raw_geometry_id: Variant in feature_index.keys():
		geometry_ids.append(str(raw_geometry_id))
	geometry_ids.sort()
	for geometry_id: String in geometry_ids:
		var territory_unit_id := VNextStableId.compose("territory_unit", geometry_id)
		if territory_unit_id.is_empty():
			return _fail("geometry feature cannot form a TerritoryUnit ID: %s" % geometry_id)
		var neighbor_ids: Array[String] = []
		for raw_neighbor_id: Variant in (adjacency_index[geometry_id] as Array):
			var neighbor_id := VNextStableId.compose(
				"territory_unit", str(raw_neighbor_id)
			)
			if neighbor_id.is_empty():
				return _fail("adjacency cannot form a TerritoryUnit ID")
			neighbor_ids.append(neighbor_id)
		var unit := VNextTerritoryUnit.new()
		if not unit.configure(
			territory_unit_id,
			CATALOG_VERSION,
			"%s#feature=%s" % [GEOMETRY_SNAPSHOT_PATH, geometry_id],
			GEOMETRY_SNAPSHOT_PATH,
			neighbor_ids
		):
			return _fail("production TerritoryUnit record is invalid: %s" % geometry_id)
		if not candidate.add_unit(unit):
			return _fail("production TerritoryUnit record could not be added: %s" % geometry_id)
		var political_record := political_by_geometry[geometry_id] as Dictionary
		var political_id := str(political_record.get("id", ""))
		candidate_political_to_territory[political_id] = territory_unit_id
		candidate_territory_to_political[territory_unit_id] = political_id

	if not candidate.seal():
		return _fail(
			"production TerritoryUnit catalog failed seal: %s"
			% "; ".join(candidate.errors())
		)
	_catalog = candidate
	_political_to_territory = candidate_political_to_territory
	_territory_to_political = candidate_territory_to_political
	_errors.clear()
	return true


func is_loaded() -> bool:
	return _catalog != null and _catalog.is_sealed() and _errors.is_empty()


func catalog() -> VNextTerritoryUnitCatalog:
	return _catalog if is_loaded() else null


func catalog_binding() -> Dictionary:
	return _catalog.binding() if is_loaded() else {}


func catalog_fingerprint() -> String:
	return _catalog.fingerprint() if is_loaded() else ""


func territory_unit_count() -> int:
	return _catalog.unit_count() if is_loaded() else 0


func territory_unit_id_for_political_unit(political_unit_id: String) -> String:
	return str(_political_to_territory.get(political_unit_id, "")) if is_loaded() else ""


func political_unit_id_for_territory_unit(territory_unit_id: String) -> String:
	return str(_territory_to_political.get(territory_unit_id, "")) if is_loaded() else ""


func political_crosswalk() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not is_loaded():
		return output
	var political_ids: Array[String] = []
	for raw_id: Variant in _political_to_territory.keys():
		political_ids.append(str(raw_id))
	political_ids.sort()
	for political_id: String in political_ids:
		output.append({
			"political_unit_id": political_id,
			"territory_unit_id": str(_political_to_territory[political_id]),
		})
	return output


func errors() -> Array[String]:
	return _errors.duplicate()


func _index_geometry_features(document: Dictionary) -> Dictionary:
	var records_value: Variant = document.get("features", [])
	if typeof(records_value) != TYPE_ARRAY:
		_fail("CShapes geometry features are missing")
		return {}
	var expected_count := int(document.get("feature_count", -1))
	var index: Dictionary = {}
	for raw_record: Variant in (records_value as Array):
		if typeof(raw_record) != TYPE_DICTIONARY:
			_fail("CShapes geometry feature is malformed")
			return {}
		var record := raw_record as Dictionary
		var geometry_id := str(record.get("id", ""))
		if (
			geometry_id.is_empty()
			or index.has(geometry_id)
			or typeof(record.get("geometry", {})) != TYPE_DICTIONARY
		):
			_fail("CShapes geometry feature identity is invalid")
			return {}
		index[geometry_id] = record
	if expected_count <= 0 or index.size() != expected_count:
		_fail("CShapes geometry feature count is inconsistent")
		return {}
	return index


func _index_political_units(
	document: Dictionary, feature_index: Dictionary
) -> Dictionary:
	var records_value: Variant = document.get("units", [])
	if typeof(records_value) != TYPE_ARRAY:
		_fail("historical political unit records are missing")
		return {}
	var expected_count := int(document.get("unit_count", -1))
	var index: Dictionary = {}
	var political_ids: Dictionary = {}
	for raw_record: Variant in (records_value as Array):
		if typeof(raw_record) != TYPE_DICTIONARY:
			_fail("historical political unit record is malformed")
			return {}
		var record := raw_record as Dictionary
		var political_id := str(record.get("id", ""))
		var geometry_id := str(record.get("geometry_feature_id", ""))
		if (
			political_id.is_empty()
			or political_ids.has(political_id)
			or geometry_id.is_empty()
			or not feature_index.has(geometry_id)
			or index.has(geometry_id)
			or str(record.get("geometry_provider", "")) != GEOMETRY_PROVIDER
		):
			_fail("historical political-to-geometry crosswalk is invalid")
			return {}
		political_ids[political_id] = true
		index[geometry_id] = record
	if expected_count <= 0 or index.size() != expected_count:
		_fail("historical political-to-geometry crosswalk coverage is incomplete")
		return {}
	return index


func _index_adjacency(
	document: Dictionary, feature_index: Dictionary
) -> Dictionary:
	var records_value: Variant = document.get("records", [])
	if typeof(records_value) != TYPE_ARRAY:
		_fail("production TerritoryUnit adjacency records are missing")
		return {}
	var expected_count := int(document.get("feature_count", -1))
	var edge_count := int(document.get("undirected_edge_count", -1))
	if edge_count <= 0:
		_fail("production TerritoryUnit adjacency has no source-derived edges")
		return {}
	var index: Dictionary = {}
	for raw_record: Variant in (records_value as Array):
		if typeof(raw_record) != TYPE_DICTIONARY:
			_fail("production TerritoryUnit adjacency record is malformed")
			return {}
		var record := raw_record as Dictionary
		var geometry_id := str(record.get("geometry_feature_id", ""))
		var neighbor_value: Variant = record.get("neighbor_geometry_feature_ids", [])
		if (
			geometry_id.is_empty()
			or not feature_index.has(geometry_id)
			or index.has(geometry_id)
			or typeof(neighbor_value) != TYPE_ARRAY
		):
			_fail("production TerritoryUnit adjacency identity is invalid")
			return {}
		var neighbors: Array[String] = []
		for raw_neighbor: Variant in (neighbor_value as Array):
			if typeof(raw_neighbor) != TYPE_STRING:
				_fail("production TerritoryUnit adjacency neighbor is malformed")
				return {}
			var neighbor_id := raw_neighbor as String
			if (
				neighbor_id == geometry_id
				or not feature_index.has(neighbor_id)
				or neighbors.has(neighbor_id)
			):
				_fail("production TerritoryUnit adjacency neighbor is invalid")
				return {}
			neighbors.append(neighbor_id)
		neighbors.sort()
		index[geometry_id] = neighbors
	if expected_count <= 0 or index.size() != expected_count:
		_fail("production TerritoryUnit adjacency coverage is incomplete")
		return {}
	for raw_geometry_id: Variant in index.keys():
		var geometry_id := str(raw_geometry_id)
		for neighbor_id: String in (index[geometry_id] as Array):
			if not (index.get(neighbor_id, []) as Array).has(geometry_id):
				_fail("production TerritoryUnit adjacency is asymmetric")
				return {}
	return index


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot read production TerritoryUnit source: %s" % path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		_fail("production TerritoryUnit source is invalid JSON: %s" % path)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _fail(message: String) -> bool:
	_errors.append(message)
	return false
