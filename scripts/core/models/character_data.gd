class_name CharacterData
extends RefCounted

var id: String
var name: String
var age: int
var country_id: String
var region_id: String
var occupation_id: String
var occupation: String
var public_position: String
var organization_ids: Array[String]
var relationship_ids: Array[String]
var hidden_aptitudes: Dictionary
var temperament_weights: Dictionary
var skills: Dictionary
var manifested_traits: Array[String]
var tendencies: Dictionary
var known_tendencies: Dictionary
var current_status: Dictionary
var background_history: Array[Dictionary]
var domain_experience: Dictionary
var qualifications: Array[String]
var drives: Dictionary
var issue_positions: Dictionary
var current_agendas: Array[Dictionary]
var bottom_lines: Array[String]
var is_active: bool
var random_mode: String
var random_category: String
var is_challenge_start: bool
var generation_seed: int
var random_state: int


static func from_dict(data: Dictionary) -> CharacterData:
	var model := CharacterData.new()
	model.id = str(data.get("id", ""))
	model.name = str(data.get("name", ""))
	model.age = int(data.get("age", 0))
	model.country_id = str(data.get("country_id", ""))
	model.region_id = str(data.get("region_id", ""))
	model.occupation_id = str(data.get("occupation_id", ""))
	model.occupation = str(data.get("occupation", ""))
	model.public_position = str(data.get("public_position", ""))
	model.organization_ids = DataRecordUtils.to_string_array(data.get("organization_ids", []))
	model.relationship_ids = DataRecordUtils.to_string_array(data.get("relationship_ids", []))
	model.hidden_aptitudes = DataRecordUtils.to_dictionary(data.get("hidden_aptitudes", {}))
	model.temperament_weights = DataRecordUtils.to_dictionary(data.get("temperament_weights", {}))
	model.skills = DataRecordUtils.to_dictionary(data.get("skills", {}))
	model.manifested_traits = DataRecordUtils.to_string_array(data.get("manifested_traits", []))
	model.tendencies = DataRecordUtils.to_dictionary(data.get("tendencies", {}))
	model.known_tendencies = DataRecordUtils.to_dictionary(data.get("known_tendencies", {}))
	model.current_status = DataRecordUtils.to_dictionary(data.get("current_status", {}))
	model.background_history = []
	for raw_history: Variant in data.get("background_history", []) as Array:
		if raw_history is Dictionary:
			model.background_history.append((raw_history as Dictionary).duplicate(true))
	model.domain_experience = DataRecordUtils.to_dictionary(
		data.get("domain_experience", {})
	)
	model.qualifications = DataRecordUtils.to_string_array(
		data.get("qualifications", [])
	)
	model.drives = DataRecordUtils.to_dictionary(data.get("drives", {}))
	model.issue_positions = DataRecordUtils.to_dictionary(
		data.get("issue_positions", {})
	)
	model.current_agendas = []
	for raw_agenda: Variant in data.get("current_agendas", []) as Array:
		if raw_agenda is Dictionary:
			model.current_agendas.append((raw_agenda as Dictionary).duplicate(true))
	model.bottom_lines = DataRecordUtils.to_string_array(data.get("bottom_lines", []))
	model.is_active = bool(data.get("is_active", false))
	model.random_mode = str(data.get("random_mode", ""))
	model.random_category = str(data.get("random_category", ""))
	model.is_challenge_start = bool(data.get("is_challenge_start", false))
	model.generation_seed = int(data.get("generation_seed", 0))
	model.random_state = int(data.get("random_state", 0))
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"age": age,
		"country_id": country_id,
		"region_id": region_id,
		"occupation_id": occupation_id,
		"occupation": occupation,
		"public_position": public_position,
		"organization_ids": organization_ids.duplicate(),
		"relationship_ids": relationship_ids.duplicate(),
		"hidden_aptitudes": hidden_aptitudes.duplicate(true),
		"temperament_weights": temperament_weights.duplicate(true),
		"skills": skills.duplicate(true),
		"manifested_traits": manifested_traits.duplicate(),
		"tendencies": tendencies.duplicate(true),
		"known_tendencies": known_tendencies.duplicate(true),
		"current_status": current_status.duplicate(true),
		"background_history": background_history.duplicate(true),
		"domain_experience": domain_experience.duplicate(true),
		"qualifications": qualifications.duplicate(),
		"drives": drives.duplicate(true),
		"issue_positions": issue_positions.duplicate(true),
		"current_agendas": current_agendas.duplicate(true),
		"bottom_lines": bottom_lines.duplicate(),
		"is_active": is_active,
		"random_mode": random_mode,
		"random_category": random_category,
		"is_challenge_start": is_challenge_start,
		"generation_seed": generation_seed,
		"random_state": random_state,
	}


func to_public_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"age": age,
		"country_id": country_id,
		"region_id": region_id,
		"occupation_id": occupation_id,
		"occupation": occupation,
		"public_position": public_position,
		"organization_ids": organization_ids.duplicate(),
		"relationship_ids": relationship_ids.duplicate(),
		"skills": skills.duplicate(true),
		"manifested_traits": manifested_traits.duplicate(),
		"known_tendencies": known_tendencies.duplicate(true),
		"current_status": current_status.duplicate(true),
		"background_history": background_history.duplicate(true),
		"domain_experience": domain_experience.duplicate(true),
		"qualifications": qualifications.duplicate(),
		"drives": drives.duplicate(true),
		"issue_positions": issue_positions.duplicate(true),
		"current_agendas": current_agendas.duplicate(true),
		"bottom_lines": bottom_lines.duplicate(),
		"is_active": is_active,
		"random_mode": random_mode,
		"random_category": random_category,
		"is_challenge_start": is_challenge_start,
	}
