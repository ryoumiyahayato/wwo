class_name BackgroundCharacterData
extends RefCounted
## Lightweight record without AI state. Persistent character core survives tier changes.

var id: String
var name: String
var age: int
var country_id: String
var region_id: String
var occupation_id: String
var occupation: String
var public_position: String
var organization_ids: Array[String] = []
var relationship_ids: Array[String] = []
var manifested_traits: Array[String] = []
var current_status: Dictionary = {}
var activation_seed: int
var persistent_core: Dictionary = {}


static func from_dict(data: Dictionary) -> BackgroundCharacterData:
	var model := BackgroundCharacterData.new()
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
	model.manifested_traits = DataRecordUtils.to_string_array(data.get("manifested_traits", []))
	model.current_status = DataRecordUtils.to_dictionary(data.get("current_status", {}))
	model.activation_seed = int(data.get("activation_seed", 0))
	model.persistent_core = DataRecordUtils.to_dictionary(data.get("persistent_core", {}))
	return model


static func from_active(character: CharacterData, seed_value: int) -> BackgroundCharacterData:
	var model := BackgroundCharacterData.new()
	model.id = character.id
	model.name = character.name
	model.age = character.age
	model.country_id = character.country_id
	model.region_id = character.region_id
	model.occupation_id = character.occupation_id
	model.occupation = character.occupation
	model.public_position = character.public_position
	model.organization_ids = character.organization_ids.duplicate()
	model.relationship_ids = character.relationship_ids.duplicate()
	model.manifested_traits = character.manifested_traits.duplicate()
	model.current_status = character.current_status.duplicate(true)
	model.activation_seed = seed_value
	model.persistent_core = {
		"hidden_aptitudes": character.hidden_aptitudes.duplicate(true),
		"temperament_weights": character.temperament_weights.duplicate(true),
		"skills": character.skills.duplicate(true),
		"tendencies": character.tendencies.duplicate(true),
		"known_tendencies": character.known_tendencies.duplicate(true),
		"random_mode": character.random_mode,
		"random_category": character.random_category,
		"is_challenge_start": character.is_challenge_start,
		"generation_seed": character.generation_seed,
		"random_state": character.random_state,
	}
	return model


func apply_persistent_core(character: CharacterData) -> void:
	if character == null or persistent_core.is_empty():
		return
	character.hidden_aptitudes = DataRecordUtils.to_dictionary(
		persistent_core.get("hidden_aptitudes", character.hidden_aptitudes)
	)
	character.temperament_weights = DataRecordUtils.to_dictionary(
		persistent_core.get("temperament_weights", character.temperament_weights)
	)
	character.skills = DataRecordUtils.to_dictionary(
		persistent_core.get("skills", character.skills)
	)
	character.tendencies = DataRecordUtils.to_dictionary(
		persistent_core.get("tendencies", character.tendencies)
	)
	character.known_tendencies = DataRecordUtils.to_dictionary(
		persistent_core.get("known_tendencies", character.known_tendencies)
	)
	character.random_mode = str(persistent_core.get("random_mode", character.random_mode))
	character.random_category = str(
		persistent_core.get("random_category", character.random_category)
	)
	character.is_challenge_start = bool(
		persistent_core.get("is_challenge_start", character.is_challenge_start)
	)
	character.generation_seed = int(
		persistent_core.get("generation_seed", character.generation_seed)
	)
	character.random_state = int(persistent_core.get("random_state", character.random_state))


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
		"manifested_traits": manifested_traits.duplicate(),
		"current_status": current_status.duplicate(true),
		"activation_seed": activation_seed,
		"persistent_core": persistent_core.duplicate(true),
	}
