class_name ProductSpatialProjection
extends RefCounted
## Narrow read-only projection from the single constructed vNext Spatial owner.
## It never exposes mutable world objects or capacity reservation operations.

const SOURCE_PATHS: Dictionary = {
	"regions": "res://data/world_map/regions.json",
	"cities": "res://data/world_map/cities.json",
	"ports": "res://data/world_map/ports.json",
	"roads": "res://data/world_map/road_segments.json",
	"rail": "res://data/world_map/rail_segments.json",
	"shipping": "res://data/world_map/shipping_routes.json",
}

var _world: VNextSpatialWorld = null
var _applicability_by_type: Dictionary = {}
var _source_metadata_by_type: Dictionary = {}


func initialize(world_value: VNextSpatialWorld) -> bool:
	if world_value == null or not world_value.is_valid():
		return false
	var applicability: Dictionary = {}
	var metadata: Dictionary = {}
	for data_type: String in _sorted_keys(SOURCE_PATHS):
		var document := _read_document(str(SOURCE_PATHS[data_type]))
		applicability[data_type] = ProductSpatialApplicability.classify_document(document)
		metadata[data_type] = _metadata_only(document)
	_world = world_value
	_applicability_by_type = applicability
	_source_metadata_by_type = metadata
	return is_valid()


func is_valid() -> bool:
	return (
		_world != null
		and _world.is_valid()
		and _applicability_by_type.size() == SOURCE_PATHS.size()
	)


func owner_instance_id() -> int:
	return 0 if _world == null else _world.get_instance_id()


func source_applicability(data_type: String) -> String:
	return str(
		_applicability_by_type.get(
			data_type, ProductSpatialApplicability.UNAVAILABLE
		)
	)


func historical_local_geography_status(country_id: String) -> Dictionary:
	var candidates := _region_records_for_country(country_id)
	return _availability_status(
		"historical local geography", "regions", candidates.size()
	)


func historical_city_status(country_id: String) -> Dictionary:
	var candidates := _city_records_for_country(country_id)
	return _availability_status("historical city data", "cities", candidates.size())


func infrastructure_historical_status(country_id: String) -> Dictionary:
	var counts := infrastructure_reference_counts(country_id)
	var candidate_count := 0
	for count_value: Variant in counts.values():
		candidate_count += int(count_value)
	var classes_for_sources: Array[String] = []
	for data_type: String in ["ports", "roads", "rail", "shipping"]:
		classes_for_sources.append(source_applicability(data_type))
	var normal_supported := true
	for applicability: String in classes_for_sources:
		if not ProductSpatialApplicability.may_present_as_normal_truth(applicability):
			normal_supported = false
			break
	return {
		"status": "ACTIVE" if normal_supported and candidate_count > 0 else "NOT AVAILABLE",
		"applicability": (
			ProductSpatialApplicability.HISTORICALLY_SUPPORTED
			if normal_supported and candidate_count > 0
			else _least_eligible(classes_for_sources)
		),
		"candidate_count": candidate_count,
		"normal_product_eligible": normal_supported and candidate_count > 0,
		"detail": (
			"Historical infrastructure facts are available."
			if normal_supported and candidate_count > 0
			else "Catalog topology is developer reference only; historical attributes are unavailable."
		),
	}


func normal_region_views(country_id: String) -> Array[Dictionary]:
	if not ProductSpatialApplicability.may_present_as_normal_truth(
		source_applicability("regions")
	):
		return []
	var output: Array[Dictionary] = []
	for region: Dictionary in _region_records_for_country(country_id):
		output.append(_region_identity_view(region, source_applicability("regions")))
	return output


func developer_region_reference_views(country_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for region: Dictionary in _region_records_for_country(country_id):
		output.append(_region_identity_view(region, source_applicability("regions")))
	return output


func normal_city_views(country_id: String) -> Array[Dictionary]:
	if not ProductSpatialApplicability.may_present_as_normal_truth(
		source_applicability("cities")
	):
		return []
	var output: Array[Dictionary] = []
	for city: Dictionary in _city_records_for_country(country_id):
		output.append(_city_identity_view(city, source_applicability("cities")))
	return output


func developer_city_reference_views(country_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for city: Dictionary in _city_records_for_country(country_id):
		output.append(_city_identity_view(city, source_applicability("cities")))
	return output


func city_reference(city_query: String) -> Dictionary:
	if not is_valid():
		return {}
	var city := _world.get_city(city_query)
	if city.is_empty():
		return {}
	return _city_identity_view(city, source_applicability("cities"))


func infrastructure_reference_counts(country_id: String) -> Dictionary:
	if not is_valid():
		return {"ports": 0, "roads": 0, "rail": 0, "shipping": 0}
	var catalog := _world.catalog()
	var city_ids: Dictionary = {}
	for city: Dictionary in _city_records_for_country(country_id):
		city_ids[str(city.get("map_id", city.get("id", "")))] = true
	var port_ids: Dictionary = {}
	var port_count := 0
	for port: Dictionary in catalog.ports():
		if str(port.get("parent_country_id", "")) != country_id:
			continue
		port_ids[str(port.get("map_id", port.get("id", "")))] = true
		port_count += 1
	var counts := {"ports": port_count, "roads": 0, "rail": 0, "shipping": 0}
	for link: Dictionary in catalog.links():
		var link_type := str(link.get("link_type", ""))
		var endpoint_index := port_ids if link_type == "shipping" else city_ids
		if (
			endpoint_index.has(str(link.get("from_map_id", "")))
			or endpoint_index.has(str(link.get("to_map_id", "")))
		):
			var count_key := "roads" if link_type == "road" else link_type
			counts[count_key] = int(counts.get(count_key, 0)) + 1
	return counts.duplicate(true)


func source_summary() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for data_type: String in _sorted_keys(SOURCE_PATHS):
		output.append({
			"data_type": data_type,
			"path": str(SOURCE_PATHS[data_type]),
			"applicability": source_applicability(data_type),
			"normal_product_eligible": ProductSpatialApplicability.may_present_as_normal_truth(
				source_applicability(data_type)
			),
			"metadata": (_source_metadata_by_type.get(data_type, {}) as Dictionary).duplicate(true),
		})
	return output


func _availability_status(label: String, data_type: String, candidate_count: int) -> Dictionary:
	var applicability := source_applicability(data_type)
	var eligible := (
		candidate_count > 0
		and ProductSpatialApplicability.may_present_as_normal_truth(applicability)
	)
	return {
		"status": "ACTIVE" if eligible else "NOT AVAILABLE",
		"applicability": applicability,
		"candidate_count": candidate_count,
		"normal_product_eligible": eligible,
		"detail": (
			"%s is supported for normal presentation." % label.capitalize()
			if eligible
			else "%s candidates are not qualified as 1900 product truth." % label.capitalize()
		),
	}


func _region_records_for_country(country_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not is_valid():
		return output
	for region: Dictionary in _world.catalog().regions():
		if str(region.get("parent_country_id", "")) == country_id:
			output.append(region.duplicate(true))
	output.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("map_id", left.get("id", ""))) < str(right.get("map_id", right.get("id", "")))
	)
	return output


func _city_records_for_country(country_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not is_valid():
		return output
	for city: Dictionary in _world.catalog().cities():
		if str(city.get("parent_country_id", "")) == country_id:
			output.append(city.duplicate(true))
	output.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("map_id", left.get("id", ""))) < str(right.get("map_id", right.get("id", "")))
	)
	return output


func _region_identity_view(region: Dictionary, applicability: String) -> Dictionary:
	return {
		"stable_id": str(region.get("place_id", "")),
		"name": str(region.get("name", "")),
		"reference_anchor": (region.get("label_lon_lat", []) as Array).duplicate(true),
		"provenance": str(SOURCE_PATHS["regions"]),
		"applicability": applicability,
		"normal_product_eligible": ProductSpatialApplicability.may_present_as_normal_truth(applicability),
	}


func _city_identity_view(city: Dictionary, applicability: String) -> Dictionary:
	return {
		"stable_id": str(city.get("place_id", "")),
		"name": str(city.get("name", "")),
		"location": (city.get("lon_lat", []) as Array).duplicate(true),
		"provenance": str(SOURCE_PATHS["cities"]),
		"applicability": applicability,
		"normal_product_eligible": ProductSpatialApplicability.may_present_as_normal_truth(applicability),
		"historical_role": ProductSpatialApplicability.UNAVAILABLE,
		"population": ProductSpatialApplicability.UNAVAILABLE,
		"economy": ProductSpatialApplicability.UNAVAILABLE,
		"infrastructure": ProductSpatialApplicability.UNAVAILABLE,
		"administration": ProductSpatialApplicability.UNAVAILABLE,
		"politics": ProductSpatialApplicability.UNAVAILABLE,
	}


func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _metadata_only(document: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key: Variant in document.keys():
		if str(key) not in ["countries", "regions", "cities", "ports", "segments", "routes", "administrative_units"]:
			output[key] = document[key]
	return output


func _least_eligible(classes_for_sources: Array[String]) -> String:
	for applicability_class: String in [
		ProductSpatialApplicability.PROTOTYPE_ONLY,
		ProductSpatialApplicability.TEMPORALLY_UNKNOWN,
		ProductSpatialApplicability.REFERENCE_ONLY,
		ProductSpatialApplicability.UNAVAILABLE,
	]:
		if applicability_class in classes_for_sources:
			return applicability_class
	return ProductSpatialApplicability.UNAVAILABLE


func _sorted_keys(value: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key: Variant in value.keys():
		output.append(str(key))
	output.sort()
	return output
