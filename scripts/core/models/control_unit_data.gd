class_name ControlUnitData
extends RefCounted

var id: String
var region_id: String
var grid_x: int
var grid_y: int
var city_name: String
var neighbor_ids: Array[String]
var de_jure_country_id: String
var controller_country_id: String
var control_strength: float
var contested_level: float
var garrison_pressure: float
var enemy_pressure: float
var social_support: float
var railroad_neighbor_ids: Array[String]
var infrastructure_state: String


static func from_dict(data: Dictionary) -> ControlUnitData:
	var model := ControlUnitData.new()
	model.id = str(data["id"])
	model.region_id = str(data["region_id"])
	model.grid_x = int(data["grid_x"])
	model.grid_y = int(data["grid_y"])
	model.city_name = str(data["city_name"])
	model.neighbor_ids = DataRecordUtils.to_string_array(data["neighbor_ids"])
	model.de_jure_country_id = str(data["de_jure_country_id"])
	model.controller_country_id = str(data["controller_country_id"])
	model.control_strength = float(data["control_strength"])
	model.contested_level = float(data["contested_level"])
	model.garrison_pressure = float(data["garrison_pressure"])
	model.enemy_pressure = float(data["enemy_pressure"])
	model.social_support = float(data["social_support"])
	model.railroad_neighbor_ids = DataRecordUtils.to_string_array(data["railroad_neighbor_ids"])
	model.infrastructure_state = str(data["infrastructure_state"])
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"region_id": region_id,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"city_name": city_name,
		"neighbor_ids": neighbor_ids.duplicate(),
		"de_jure_country_id": de_jure_country_id,
		"controller_country_id": controller_country_id,
		"control_strength": control_strength,
		"contested_level": contested_level,
		"garrison_pressure": garrison_pressure,
		"enemy_pressure": enemy_pressure,
		"social_support": social_support,
		"railroad_neighbor_ids": railroad_neighbor_ids.duplicate(),
		"infrastructure_state": infrastructure_state,
	}
