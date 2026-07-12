class_name RegionData
extends RefCounted

var id: String
var name: String
var de_jure_country_id: String
var population_group_ids: Array[String]
var city_names: Array[String]
var resources: Dictionary
var infrastructure: Dictionary
var organization_ids: Array[String]
var social_influence: Dictionary


static func from_dict(data: Dictionary) -> RegionData:
	var model := RegionData.new()
	model.id = str(data["id"])
	model.name = str(data["name"])
	model.de_jure_country_id = str(data["de_jure_country_id"])
	model.population_group_ids = DataRecordUtils.to_string_array(data["population_group_ids"])
	model.city_names = DataRecordUtils.to_string_array(data["city_names"])
	model.resources = DataRecordUtils.to_dictionary(data["resources"])
	model.infrastructure = DataRecordUtils.to_dictionary(data["infrastructure"])
	model.organization_ids = DataRecordUtils.to_string_array(data["organization_ids"])
	model.social_influence = DataRecordUtils.to_dictionary(data["social_influence"])
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"de_jure_country_id": de_jure_country_id,
		"population_group_ids": population_group_ids.duplicate(),
		"city_names": city_names.duplicate(),
		"resources": resources.duplicate(true),
		"infrastructure": infrastructure.duplicate(true),
		"organization_ids": organization_ids.duplicate(),
		"social_influence": social_influence.duplicate(true),
	}

