class_name CountryData
extends RefCounted

var id: String
var name: String
var region_ids: Array[String]
var public_status: Dictionary


static func from_dict(data: Dictionary) -> CountryData:
	var model := CountryData.new()
	model.id = str(data["id"])
	model.name = str(data["name"])
	model.region_ids = DataRecordUtils.to_string_array(data["region_ids"])
	model.public_status = DataRecordUtils.to_dictionary(data["public_status"])
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"region_ids": region_ids.duplicate(),
		"public_status": public_status.duplicate(true),
	}

