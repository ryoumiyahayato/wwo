class_name PopulationGroupData
extends RefCounted

var id: String
var region_id: String
var population_count: int
var social_class: String
var occupation_category: String
var average_income: float
var average_education: float
var unemployment_rate: float
var public_political_leaning: Dictionary
var basic_living_state: String


static func from_dict(data: Dictionary) -> PopulationGroupData:
	var model := PopulationGroupData.new()
	model.id = str(data["id"])
	model.region_id = str(data["region_id"])
	model.population_count = int(data["population_count"])
	model.social_class = str(data["social_class"])
	model.occupation_category = str(data["occupation_category"])
	model.average_income = float(data["average_income"])
	model.average_education = float(data["average_education"])
	model.unemployment_rate = float(data["unemployment_rate"])
	model.public_political_leaning = DataRecordUtils.to_dictionary(data["public_political_leaning"])
	model.basic_living_state = str(data["basic_living_state"])
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"region_id": region_id,
		"population_count": population_count,
		"social_class": social_class,
		"occupation_category": occupation_category,
		"average_income": average_income,
		"average_education": average_education,
		"unemployment_rate": unemployment_rate,
		"public_political_leaning": public_political_leaning.duplicate(true),
		"basic_living_state": basic_living_state,
	}

