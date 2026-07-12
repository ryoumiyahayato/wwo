class_name CoreDataLoadResult
extends RefCounted
## Explicit non-throwing result for content loading and validation.

var data_set: CoreDataSet
var errors: Array[String] = []


func is_success() -> bool:
	return errors.is_empty() and data_set != null


func add_error(message: String) -> void:
	errors.append(message)


func has_error_containing(fragment: String) -> bool:
	for message: String in errors:
		if message.contains(fragment):
			return true
	return false

