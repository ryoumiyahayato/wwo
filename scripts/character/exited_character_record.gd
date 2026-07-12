class_name ExitedCharacterRecord
extends RefCounted

var character: CharacterData
var reason: String
var exit_hour: int
var successor_character_id: String = ""


static func from_dict(data: Dictionary) -> ExitedCharacterRecord:
	var model := ExitedCharacterRecord.new()
	model.character = CharacterData.from_dict(data.get("character", {}) as Dictionary)
	model.reason = str(data.get("reason", ""))
	model.exit_hour = int(data.get("exit_hour", -1))
	model.successor_character_id = str(data.get("successor_character_id", ""))
	return model


func to_dict() -> Dictionary:
	return {
		"character": character.to_dict(),
		"reason": reason,
		"exit_hour": exit_hour,
		"successor_character_id": successor_character_id,
	}
