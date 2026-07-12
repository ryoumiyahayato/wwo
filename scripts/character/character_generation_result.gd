class_name CharacterGenerationResult
extends RefCounted

var character: CharacterData
var errors: Array[String] = []


func is_success() -> bool:
	return character != null and errors.is_empty()


func add_error(message: String) -> void:
	errors.append(message)

