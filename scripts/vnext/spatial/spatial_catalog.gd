class_name VNextSpatialCatalog
extends RefCounted
## Read-only normalized view over the existing world-map data.
##
## The catalog owns no dynamic control, capacity, or infrastructure state. It
## keeps the legacy map IDs as the map-owned identifiers and derives the
## existing `place:<map_id>` stable ID only at the vNext query boundary.

const SOURCE_PATHS: Dictionary = {
	"countries": "res://data/world_map/countries.json",
	"regions": "res://data/world_map/regions.json",
	"cities": "res://data/world_map/cities.json",
	"ports": "res://data/world_map/ports.json",
	"roads": "res://data/world_map/road_segments.json",
	"rail": "res://data/world_map/rail_segments.json",
	"shipping": "res://data/world_map/shipping_routes.json",
}

const LINK_TYPE_ROAD: String = "road"
const LINK_TYPE_RAIL: String = "rail"
const LINK_TYPE_SHIPPING: String = "shipping"

var _loaded: bool = false
var _errors: Array[String] = []
var _countries: Array[Dictionary] = []
var _regions: Array[Dictionary] = []
var _cities: Array[Dictionary] = []
var _ports: Array[Dictionary] = []
var _links: Array[Dictionary] = []
var _countries_by_id: Dictionary = {}
var _regions_by_id: Dictionary = {}
var _cities_by_id: Dictionary = {}
var _ports_by_id: Dictionary = {}
var _links_by_id: Dictionary = {}
var _places_by_id: Dictionary = {}


static func map_id_to_place_id(map_id: String) -> String:
	if not is_valid_map_id(map_id):
		return ""
	return VNextStableId.compose("place", map_id)


static func place_query_to_map_id(candidate: String) -> String:
	if VNextStableId.is_valid(candidate):
		if VNextStableId.kind_of(candidate) != "place":
			return ""
		return VNextStableId.local_id_of(candidate)
	if is_valid_map_id(candidate):
		return candidate
	return ""


static func is_valid_map_id(candidate: String) -> bool:
	if candidate.is_empty():
		return false
	return VNextStableId.compose("place", candidate) != ""


func load_legacy_world_map() -> bool:
	var documents: Dictionary = {}
	for source_key: String in _source_keys():
		var document: Dictionary = _read_document(str(SOURCE_PATHS[source_key]))
		if document.is_empty():
			return false
		documents[source_key] = document
	return load_from_documents(documents)


func load_from_documents(documents: Dictionary) -> bool:
	_errors.clear()
	if documents.is_empty():
		_errors.append("spatial catalog requires source documents")
		return false

	var candidate_countries: Array[Dictionary] = []
	var candidate_regions: Array[Dictionary] = []
	var candidate_cities: Array[Dictionary] = []
	var candidate_ports: Array[Dictionary] = []
	var candidate_links: Array[Dictionary] = []
	var candidate_countries_by_id: Dictionary = {}
	var candidate_regions_by_id: Dictionary = {}
	var candidate_cities_by_id: Dictionary = {}
	var candidate_ports_by_id: Dictionary = {}
	var candidate_links_by_id: Dictionary = {}
	var candidate_places_by_id: Dictionary = {}

	if not _append_source_records(
		documents, "countries", "countries", candidate_countries,
		candidate_countries_by_id, {}, candidate_places_by_id
	):
		return false
	if not _append_source_records(
		documents, "regions", "regions", candidate_regions,
		candidate_regions_by_id, candidate_places_by_id, candidate_places_by_id
	):
		return false
	if not _append_source_records(
		documents, "cities", "cities", candidate_cities,
		candidate_cities_by_id, candidate_places_by_id, candidate_places_by_id
	):
		return false
	if not _append_source_records(
		documents, "ports", "ports", candidate_ports,
		candidate_ports_by_id, candidate_places_by_id, candidate_places_by_id
	):
		return false

	if not _validate_country_references(
		candidate_countries_by_id, candidate_regions, candidate_cities, candidate_ports
	):
		return false
	if not _append_link_records(
		documents, "roads", LINK_TYPE_ROAD, "segments", candidate_cities_by_id,
		candidate_ports_by_id, candidate_links, candidate_links_by_id
	):
		return false
	if not _append_link_records(
		documents, "rail", LINK_TYPE_RAIL, "segments", candidate_cities_by_id,
		candidate_ports_by_id, candidate_links, candidate_links_by_id
	):
		return false
	if not _append_link_records(
		documents, "shipping", LINK_TYPE_SHIPPING, "routes", candidate_cities_by_id,
		candidate_ports_by_id, candidate_links, candidate_links_by_id
	):
		return false

	_countries = _sort_records_by_id(candidate_countries)
	_regions = _sort_records_by_id(candidate_regions)
	_cities = _sort_records_by_id(candidate_cities)
	_ports = _sort_records_by_id(candidate_ports)
	_links = _sort_records_by_id(candidate_links)
	_countries_by_id = _reindex_records(_countries)
	_regions_by_id = _reindex_records(_regions)
	_cities_by_id = _reindex_records(_cities)
	_ports_by_id = _reindex_records(_ports)
	_links_by_id = _reindex_records(_links)
	_places_by_id = {}
	for record: Dictionary in _regions:
		_places_by_id[record["map_id"]] = record
	for record: Dictionary in _cities:
		_places_by_id[record["map_id"]] = record
	for record: Dictionary in _ports:
		_places_by_id[record["map_id"]] = record

	_loaded = true
	return true


func is_loaded() -> bool:
	return _loaded and _errors.is_empty()


func errors() -> Array[String]:
	return _errors.duplicate()


func country_ids() -> Array[String]:
	return _sorted_ids(_countries_by_id)


func region_ids() -> Array[String]:
	return _sorted_ids(_regions_by_id)


func city_ids() -> Array[String]:
	return _sorted_ids(_cities_by_id)


func port_ids() -> Array[String]:
	return _sorted_ids(_ports_by_id)


func place_map_ids() -> Array[String]:
	return _sorted_ids(_places_by_id)


func place_ids() -> Array[String]:
	var output: Array[String] = []
	for map_id: String in place_map_ids():
		output.append(map_id_to_place_id(map_id))
	return output


func link_ids() -> Array[String]:
	return _sorted_ids(_links_by_id)


func countries() -> Array[Dictionary]:
	return _copy_records(_countries)


func regions() -> Array[Dictionary]:
	return _copy_records(_regions)


func cities() -> Array[Dictionary]:
	return _copy_records(_cities)


func ports() -> Array[Dictionary]:
	return _copy_records(_ports)


func links() -> Array[Dictionary]:
	return _copy_records(_links)


func get_country(country_id: String) -> Dictionary:
	return _copy_record(_countries_by_id.get(country_id, {}))


func get_region(region_query: String) -> Dictionary:
	return _copy_record(_regions_by_id.get(place_query_to_map_id(region_query), {}))


func get_city(city_query: String) -> Dictionary:
	return _copy_record(_cities_by_id.get(place_query_to_map_id(city_query), {}))


func get_port(port_query: String) -> Dictionary:
	return _copy_record(_ports_by_id.get(place_query_to_map_id(port_query), {}))


func get_place(place_query: String) -> Dictionary:
	return _copy_record(_places_by_id.get(place_query_to_map_id(place_query), {}))


func get_link(link_id: String) -> Dictionary:
	return _copy_record(_links_by_id.get(link_id, {}))


func has_country(country_id: String) -> bool:
	return _countries_by_id.has(country_id)


func has_region(region_query: String) -> bool:
	return _regions_by_id.has(place_query_to_map_id(region_query))


func has_city(city_query: String) -> bool:
	return _cities_by_id.has(place_query_to_map_id(city_query))


func has_port(port_query: String) -> bool:
	return _ports_by_id.has(place_query_to_map_id(port_query))


func has_place(place_query: String) -> bool:
	return _places_by_id.has(place_query_to_map_id(place_query))


func has_link(link_id: String) -> bool:
	return _links_by_id.has(link_id)


func links_of_type(link_type: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for link: Dictionary in _links:
		if str(link.get("link_type", "")) == link_type:
			output.append(link.duplicate(true))
	return output


func links_between(
	origin_query: String, destination_query: String, link_type: String = ""
) -> Array[Dictionary]:
	var origin_map_id: String = place_query_to_map_id(origin_query)
	var destination_map_id: String = place_query_to_map_id(destination_query)
	if origin_map_id.is_empty() or destination_map_id.is_empty():
		return []
	var output: Array[Dictionary] = []
	for link: Dictionary in _links:
		if not link_type.is_empty() and str(link.get("link_type", "")) != link_type:
			continue
		var from_map_id: String = str(link.get("from_map_id", ""))
		var to_map_id: String = str(link.get("to_map_id", ""))
		if (
			(from_map_id == origin_map_id and to_map_id == destination_map_id)
			or (from_map_id == destination_map_id and to_map_id == origin_map_id)
		):
			output.append(link.duplicate(true))
	return output


func links_from(place_query: String, link_type: String = "") -> Array[Dictionary]:
	var place_map_id: String = place_query_to_map_id(place_query)
	if place_map_id.is_empty():
		return []
	var output: Array[Dictionary] = []
	for link: Dictionary in _links:
		if not link_type.is_empty() and str(link.get("link_type", "")) != link_type:
			continue
		if (
			str(link.get("from_map_id", "")) == place_map_id
			or str(link.get("to_map_id", "")) == place_map_id
		):
			output.append(link.duplicate(true))
	return output


func neighboring_place_ids(place_query: String, link_type: String = "") -> Array[String]:
	var place_map_id: String = place_query_to_map_id(place_query)
	if place_map_id.is_empty():
		return []
	var neighbor_map_ids: Dictionary = {}
	for link: Dictionary in links_from(place_map_id, link_type):
		var from_map_id: String = str(link.get("from_map_id", ""))
		var to_map_id: String = str(link.get("to_map_id", ""))
		var neighbor_map_id: String = to_map_id if from_map_id == place_map_id else from_map_id
		if _places_by_id.has(neighbor_map_id):
			neighbor_map_ids[neighbor_map_id] = true
	var output: Array[String] = []
	for neighbor_map_id: String in _sorted_ids(neighbor_map_ids):
		output.append(map_id_to_place_id(neighbor_map_id))
	return output


func _append_source_records(
	documents: Dictionary,
	document_key: String,
	collection_key: String,
	output: Array[Dictionary],
	by_id: Dictionary,
	place_by_id: Dictionary,
	place_registry: Dictionary
) -> bool:
	var document_value: Variant = documents.get(document_key)
	if typeof(document_value) != TYPE_DICTIONARY:
		_errors.append("spatial source is not an object: %s" % document_key)
		return false
	var document: Dictionary = document_value
	var records_value: Variant = document.get(collection_key)
	if typeof(records_value) != TYPE_ARRAY:
		_errors.append("spatial source collection is not an array: %s" % document_key)
		return false
	var records: Array = records_value
	for raw_record: Variant in records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			_errors.append("spatial source record is not an object: %s" % document_key)
			return false
		var source_record: Dictionary = raw_record
		var id_value: Variant = source_record.get("id")
		if typeof(id_value) != TYPE_STRING or not is_valid_map_id(id_value as String):
			_errors.append("invalid map id in %s" % document_key)
			return false
		var map_id: String = id_value as String
		if by_id.has(map_id):
			_errors.append("duplicate map id in %s: %s" % [document_key, map_id])
			return false
		if not place_by_id.is_empty() and place_registry.has(map_id):
			_errors.append("duplicate place map id across sources: %s" % map_id)
			return false

		var normalized: Dictionary = source_record.duplicate(true)
		normalized["map_id"] = map_id
		if document_key != "countries":
			normalized["place_id"] = map_id_to_place_id(map_id)
			normalized["spatial_kind"] = (
				"region" if document_key == "regions"
				else "city" if document_key == "cities"
				else "port" if document_key == "ports"
				else document_key.trim_suffix("s")
			)
			place_registry[map_id] = normalized
		output.append(normalized)
		by_id[map_id] = normalized
	return true


func _append_link_records(
	documents: Dictionary,
	document_key: String,
	link_type: String,
	collection_key: String,
	cities_by_id: Dictionary,
	ports_by_id: Dictionary,
	output: Array[Dictionary],
	by_id: Dictionary
) -> bool:
	var document_value: Variant = documents.get(document_key)
	if typeof(document_value) != TYPE_DICTIONARY:
		_errors.append("spatial link source is not an object: %s" % document_key)
		return false
	var document: Dictionary = document_value
	var records_value: Variant = document.get(collection_key)
	if typeof(records_value) != TYPE_ARRAY:
		_errors.append("spatial link collection is not an array: %s" % document_key)
		return false
	var records: Array = records_value
	for raw_record: Variant in records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			_errors.append("spatial link record is not an object: %s" % document_key)
			return false
		var source_record: Dictionary = raw_record
		var id_value: Variant = source_record.get("id")
		if typeof(id_value) != TYPE_STRING or not is_valid_map_id(id_value as String):
			_errors.append("invalid link id in %s" % document_key)
			return false
		var link_id: String = id_value as String
		if by_id.has(link_id):
			_errors.append("duplicate link id: %s" % link_id)
			return false

		var from_key: String = "from_city_id" if link_type != LINK_TYPE_SHIPPING else "from_port_id"
		var to_key: String = "to_city_id" if link_type != LINK_TYPE_SHIPPING else "to_port_id"
		var from_value: Variant = source_record.get(from_key)
		var to_value: Variant = source_record.get(to_key)
		if typeof(from_value) != TYPE_STRING or typeof(to_value) != TYPE_STRING:
			_errors.append("missing endpoints in link: %s" % link_id)
			return false
		var from_map_id: String = from_value as String
		var to_map_id: String = to_value as String
		var endpoint_index: Dictionary = ports_by_id if link_type == LINK_TYPE_SHIPPING else cities_by_id
		if not endpoint_index.has(from_map_id) or not endpoint_index.has(to_map_id):
			_errors.append("unknown endpoint in link: %s" % link_id)
			return false
		if from_map_id == to_map_id:
			_errors.append("self-link is not allowed: %s" % link_id)
			return false
		if source_record.has("type") and str(source_record.get("type")) != link_type:
			_errors.append("link type mismatch: %s" % link_id)
			return false

		var normalized: Dictionary = source_record.duplicate(true)
		normalized["map_id"] = link_id
		normalized["link_id"] = link_id
		normalized["link_type"] = link_type
		normalized["from_map_id"] = from_map_id
		normalized["to_map_id"] = to_map_id
		normalized["from_place_id"] = map_id_to_place_id(from_map_id)
		normalized["to_place_id"] = map_id_to_place_id(to_map_id)
		normalized["endpoint_kind"] = "port" if link_type == LINK_TYPE_SHIPPING else "city"
		output.append(normalized)
		by_id[link_id] = normalized
	return true


func _validate_country_references(
	countries_by_id: Dictionary,
	regions: Array[Dictionary],
	cities: Array[Dictionary],
	ports: Array[Dictionary]
) -> bool:
	for region: Dictionary in regions:
		if not _validate_parent_country(region, countries_by_id):
			return false
	for city: Dictionary in cities:
		if not _validate_parent_country(city, countries_by_id):
			return false
		if not _validate_optional_region(city, regions):
			return false
	for port: Dictionary in ports:
		if not _validate_parent_country(port, countries_by_id):
			return false
		if not _validate_optional_region(port, regions):
			return false
		var city_id: String = str(port.get("city_id", ""))
		if city_id.is_empty() or not _contains_record_id(cities, city_id):
			_errors.append("port references unknown city: %s" % str(port.get("id", "")))
			return false
	return true


func _validate_parent_country(record: Dictionary, countries_by_id: Dictionary) -> bool:
	var country_id: String = str(record.get("parent_country_id", ""))
	if country_id.is_empty() or not countries_by_id.has(country_id):
		_errors.append("unknown parent country: %s" % str(record.get("id", "")))
		return false
	return true


func _validate_optional_region(record: Dictionary, regions: Array[Dictionary]) -> bool:
	var region_id: String = str(record.get("parent_region_id", ""))
	if region_id.is_empty():
		return true
	if not _contains_record_id(regions, region_id):
		_errors.append("unknown parent region: %s" % str(record.get("id", "")))
		return false
	return true


func _contains_record_id(records: Array[Dictionary], record_id: String) -> bool:
	for record: Dictionary in records:
		if str(record.get("id", "")) == record_id:
			return true
	return false


func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_errors.append("missing spatial source: %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("unable to read spatial source: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("spatial source is not JSON object: %s" % path)
		return {}
	return parsed as Dictionary


func _source_keys() -> Array[String]:
	return ["countries", "regions", "cities", "ports", "roads", "rail", "shipping"]


func _copy_records(records: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for record: Dictionary in records:
		output.append(record.duplicate(true))
	return output


func _copy_record(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).is_empty():
		return {}
	return (value as Dictionary).duplicate(true)


func _sort_records_by_id(records: Array[Dictionary]) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for record: Dictionary in records:
		by_id[str(record.get("map_id", record.get("id", "")))] = record
	var output: Array[Dictionary] = []
	for map_id: String in _sorted_ids(by_id):
		output.append((by_id[map_id] as Dictionary).duplicate(true))
	return output


func _reindex_records(records: Array[Dictionary]) -> Dictionary:
	var output: Dictionary = {}
	for record: Dictionary in records:
		output[str(record.get("map_id", record.get("id", "")))] = record
	return output


func _sorted_ids(index: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key: Variant in index.keys():
		output.append(str(key))
	output.sort()
	return output
