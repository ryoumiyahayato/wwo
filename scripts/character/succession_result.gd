class_name SuccessionResult
extends RefCounted

var successor: CharacterData
var exited_record: ExitedCharacterRecord
var inherited_wealth: int = 0
var inherited_reputation: int = 0
var inherited_intelligence: int = 0
var inherited_relationship_count: int = 0
var inherited_enemy_count: int = 0
var inherited_position_count: int = 0
var errors: Array[String] = []


func is_success() -> bool:
	return successor != null and exited_record != null and errors.is_empty()


func add_error(message: String) -> void:
	errors.append(message)
