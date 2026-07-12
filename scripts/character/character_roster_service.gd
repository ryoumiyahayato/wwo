class_name CharacterRosterService
extends RefCounted
## Owns tier indexes. Background records never receive AI state or scene nodes.

signal character_promoted(character_id: String)
signal character_demoted(character_id: String)

var data_set: CoreDataSet
var generation_config: CharacterGenerationConfig
var rules: SocietyRulesConfig
var player_character_id: String = ""
var background_characters: Dictionary = {}
var active_characters: Dictionary = {}
var exited_characters: Dictionary = {}
var _activation_seeds: Dictionary = {}


func _init(
	world_data: CoreDataSet,
	character_config: CharacterGenerationConfig,
	society_rules: SocietyRulesConfig
) -> void:
	data_set = world_data
	generation_config = character_config
	rules = society_rules


func initialize_background_population() -> bool:
	if not generation_config.is_valid() or rules.error_message != "":
		return false
	background_characters.clear()
	_activation_seeds.clear()
	var country_ids: Array[String] = []
	for raw_id: Variant in data_set.countries:
		country_ids.append(str(raw_id))
	country_ids.sort()
	if country_ids.is_empty():
		return false
	for index: int in range(rules.background_character_count):
		var seed_value: int = rules.background_seed_base + index
		var country_id: String = country_ids[index % country_ids.size()]
		var generator := CharacterGenerator.new(
			data_set, generation_config,
			DeterministicRandomService.new(seed_value), StableIdService.new()
		)
		var result: CharacterGenerationResult = generator.generate_character(
			country_id, CharacterGenerator.MODE_FULL_POPULATION
		)
		if not result.is_success():
			return false
		var character: CharacterData = result.character
		character.id = "character:background_%04d" % (index + 1)
		character.is_active = false
		var background := BackgroundCharacterData.from_active(character, seed_value)
		background_characters[background.id] = background
		_activation_seeds[background.id] = seed_value
	return true


func register_player(character: CharacterData) -> bool:
	if character == null or active_characters.size() >= rules.active_character_limit:
		return false
	player_character_id = character.id
	character.is_active = true
	active_characters[character.id] = character
	_activation_seeds[character.id] = character.generation_seed
	return true


func promote(character_id: String) -> CharacterData:
	if active_characters.has(character_id):
		return active_characters[character_id] as CharacterData
	if active_characters.size() >= rules.active_character_limit or not background_characters.has(character_id):
		return null
	var background: BackgroundCharacterData = background_characters[character_id] as BackgroundCharacterData
	var generator := CharacterGenerator.new(
		data_set, generation_config,
		DeterministicRandomService.new(background.activation_seed), StableIdService.new()
	)
	var generated: CharacterGenerationResult = generator.generate_character(
		background.country_id, CharacterGenerator.MODE_FULL_POPULATION
	)
	if not generated.is_success():
		return null
	var character: CharacterData = generated.character
	character.id = background.id
	character.name = background.name
	character.age = background.age
	character.country_id = background.country_id
	character.region_id = background.region_id
	character.occupation_id = background.occupation_id
	character.occupation = background.occupation
	character.public_position = background.public_position
	character.organization_ids = background.organization_ids.duplicate()
	character.relationship_ids = background.relationship_ids.duplicate()
	character.manifested_traits = background.manifested_traits.duplicate()
	character.current_status = background.current_status.duplicate(true)
	character.is_active = true
	background_characters.erase(character_id)
	active_characters[character_id] = character
	character_promoted.emit(character_id)
	return character


func demote(character_id: String) -> BackgroundCharacterData:
	if character_id == player_character_id or not active_characters.has(character_id):
		return null
	var character: CharacterData = active_characters[character_id] as CharacterData
	var seed_value: int = int(_activation_seeds.get(character_id, character.generation_seed))
	var background := BackgroundCharacterData.from_active(character, seed_value)
	character.is_active = false
	active_characters.erase(character_id)
	background_characters[character_id] = background
	character_demoted.emit(character_id)
	return background


func has_character(character_id: String) -> bool:
	return active_characters.has(character_id) or background_characters.has(character_id) or exited_characters.has(character_id)


func get_active(character_id: String) -> CharacterData:
	return active_characters.get(character_id) as CharacterData


func get_background(character_id: String) -> BackgroundCharacterData:
	return background_characters.get(character_id) as BackgroundCharacterData


func get_exited(character_id: String) -> ExitedCharacterRecord:
	return exited_characters.get(character_id) as ExitedCharacterRecord


func get_public_character(character_id: String) -> Variant:
	if active_characters.has(character_id):
		return active_characters[character_id]
	if background_characters.has(character_id):
		return background_characters[character_id]
	var exited: ExitedCharacterRecord = get_exited(character_id)
	return null if exited == null else exited.character


func exit_active_character(
	character_id: String, reason: String, current_hour: int
) -> ExitedCharacterRecord:
	if not active_characters.has(character_id) or current_hour < 0:
		return null
	var character: CharacterData = active_characters[character_id] as CharacterData
	character.is_active = false
	character.current_status["exit_reason"] = reason
	character.current_status["exit_hour"] = current_hour
	var record := ExitedCharacterRecord.new()
	record.character = character
	record.reason = reason
	record.exit_hour = current_hour
	active_characters.erase(character_id)
	exited_characters[character_id] = record
	return record


func set_player_character(character: CharacterData) -> bool:
	if character == null or not active_characters.has(character.id):
		return false
	player_character_id = character.id
	return true


func get_active_ids(include_player: bool = true) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in active_characters:
		var character_id: String = str(raw_id)
		if include_player or character_id != player_character_id:
			ids.append(character_id)
	ids.sort()
	return ids


func get_background_ids(country_id: String = "") -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in background_characters:
		var character_id: String = str(raw_id)
		var character: BackgroundCharacterData = background_characters[character_id] as BackgroundCharacterData
		if country_id.is_empty() or character.country_id == country_id:
			ids.append(character_id)
	ids.sort()
	return ids


func get_total_character_count() -> int:
	return background_characters.size() + active_characters.size() + exited_characters.size()


func get_persistent_state() -> Dictionary:
	var background: Array[Dictionary] = []
	for character_id: String in get_background_ids():
		background.append((background_characters[character_id] as BackgroundCharacterData).to_dict())
	var active: Array[Dictionary] = []
	for character_id: String in get_active_ids():
		active.append((active_characters[character_id] as CharacterData).to_dict())
	var exited: Array[Dictionary] = []
	var exited_ids: Array[String] = []
	for raw_id: Variant in exited_characters:
		exited_ids.append(str(raw_id))
	exited_ids.sort()
	for character_id: String in exited_ids:
		exited.append((exited_characters[character_id] as ExitedCharacterRecord).to_dict())
	return {
		"player_character_id": player_character_id,
		"background": background,
		"active": active,
		"exited": exited,
		"activation_seeds": _activation_seeds.duplicate(true),
	}


func restore_persistent_state(state: Dictionary) -> bool:
	var player_id: String = str(state.get("player_character_id", ""))
	var raw_background: Variant = state.get("background", [])
	var raw_active: Variant = state.get("active", [])
	var raw_exited: Variant = state.get("exited", [])
	var raw_seeds: Variant = state.get("activation_seeds", {})
	if player_id.is_empty() or not raw_background is Array or not raw_active is Array or not raw_exited is Array or not raw_seeds is Dictionary:
		return false
	var restored_background: Dictionary = {}
	var restored_active: Dictionary = {}
	var restored_exited: Dictionary = {}
	for raw_record: Variant in raw_background:
		if not raw_record is Dictionary:
			return false
		var record := BackgroundCharacterData.from_dict(raw_record as Dictionary)
		if record.id.is_empty() or not data_set.countries.has(record.country_id) or not data_set.regions.has(record.region_id) or restored_background.has(record.id):
			return false
		restored_background[record.id] = record
	for raw_character: Variant in raw_active:
		if not raw_character is Dictionary:
			return false
		var character := CharacterData.from_dict(raw_character as Dictionary)
		if character.id.is_empty() or not data_set.countries.has(character.country_id) or not data_set.regions.has(character.region_id) or restored_background.has(character.id) or restored_active.has(character.id):
			return false
		restored_active[character.id] = character
	for raw_record: Variant in raw_exited:
		if not raw_record is Dictionary:
			return false
		var record := ExitedCharacterRecord.from_dict(raw_record as Dictionary)
		if record.character == null or record.character.id.is_empty() or not data_set.countries.has(record.character.country_id) or not data_set.regions.has(record.character.region_id) or restored_background.has(record.character.id) or restored_active.has(record.character.id) or restored_exited.has(record.character.id):
			return false
		restored_exited[record.character.id] = record
	if not restored_active.has(player_id) or restored_background.size() + restored_active.size() + restored_exited.size() == 0:
		return false
	background_characters = restored_background
	active_characters = restored_active
	exited_characters = restored_exited
	_activation_seeds = (raw_seeds as Dictionary).duplicate(true)
	player_character_id = player_id
	return true
