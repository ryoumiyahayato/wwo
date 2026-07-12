class_name ActionStartResult
extends RefCounted

var action: ActionInstanceData
var errors: Array[String] = []


func is_success() -> bool:
	return action != null and errors.is_empty()


func add_error(message: String) -> void:
	errors.append(message)

