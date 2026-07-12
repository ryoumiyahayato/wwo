class_name RelationshipData
extends RefCounted

var id: String
var character_a_id: String
var character_b_id: String
var familiarity: float
var trust: float
var affinity: float
var interest_link: String
var is_public: bool
var last_interaction_hour: int


static func from_dict(data: Dictionary) -> RelationshipData:
	var model := RelationshipData.new()
	model.id = str(data.get("id", ""))
	model.character_a_id = str(data.get("character_a_id", ""))
	model.character_b_id = str(data.get("character_b_id", ""))
	model.familiarity = float(data.get("familiarity", 0.0))
	model.trust = float(data.get("trust", 0.0))
	model.affinity = float(data.get("affinity", 0.0))
	model.interest_link = str(data.get("interest_link", ""))
	model.is_public = bool(data.get("is_public", false))
	model.last_interaction_hour = int(data.get("last_interaction_hour", -1))
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"character_a_id": character_a_id,
		"character_b_id": character_b_id,
		"familiarity": familiarity,
		"trust": trust,
		"affinity": affinity,
		"interest_link": interest_link,
		"is_public": is_public,
		"last_interaction_hour": last_interaction_hour,
	}
