class_name ExitedCharacterRecord
extends RefCounted

var character: CharacterData
var reason: String
var exit_hour: int
var successor_character_id: String = ""


static func from_dict(data: Dictionary) -> ExitedCharacterRecord:
	var model := ExitedCharacterRecord.new()
	var raw_character: Variant = data.get("character", {})
	model.character = (
		CharacterData.from_dict(raw_character as Dictionary)
		if raw_character is Dictionary
		else null
	)
	model.reason = str(data.get("reason", ""))
	model.exit_hour = int(data.get("exit_hour", -1))
	model.successor_character_id = str(data.get("successor_character_id", ""))
	return model


func to_dict() -> Dictionary:
	return {
		"character": {} if character == null else character.to_dict(),
		"reason": reason,
		"exit_hour": exit_hour,
		"successor_character_id": successor_character_id,
	}
