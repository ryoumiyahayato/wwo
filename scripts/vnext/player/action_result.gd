class_name VNextActionResult
extends RefCounted

var success: bool = false
var code: String = ""
var message: String = ""
var elapsed_minutes: int = 0


static func ok(minutes: int) -> VNextActionResult:
	var result := VNextActionResult.new()
	result.success = true
	result.code = "ok"
	result.message = "WAIT completed."
	result.elapsed_minutes = minutes
	return result


static func fail(result_code: String, result_message: String) -> VNextActionResult:
	var result := VNextActionResult.new()
	result.success = false
	result.code = result_code
	result.message = result_message
	result.elapsed_minutes = 0
	return result
