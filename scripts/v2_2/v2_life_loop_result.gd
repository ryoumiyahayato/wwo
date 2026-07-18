class_name V2LifeLoopResult
extends RefCounted
## Structured command result used by every V2.2 soft-failure boundary.

var success: bool = false
var error_code: String = ""
var user_message: String = ""
var technical_message: String = ""
var affected_entity_ids: Array[String] = []
var suggested_alternatives: Array[String] = []
var data: Dictionary = {}


static func ok(
	message: String = "",
	result_data: Dictionary = {},
	entity_ids: Array[String] = []
) -> V2LifeLoopResult:
	var result := V2LifeLoopResult.new()
	result.success = true
	result.user_message = message
	result.data = result_data.duplicate(true)
	result.affected_entity_ids = entity_ids.duplicate()
	return result


static func fail(
	code: String,
	message: String,
	detail: String = "",
	entity_ids: Array[String] = []
) -> V2LifeLoopResult:
	var result := V2LifeLoopResult.new()
	result.error_code = code
	result.user_message = message
	result.technical_message = detail
	result.affected_entity_ids = entity_ids.duplicate()
	return result


func to_dict() -> Dictionary:
	return {
		"success": success,
		"error_code": error_code,
		"user_message": user_message,
		"technical_message": technical_message,
		"affected_entity_ids": affected_entity_ids.duplicate(),
		"suggested_alternatives": suggested_alternatives.duplicate(),
		"data": data.duplicate(true),
	}
