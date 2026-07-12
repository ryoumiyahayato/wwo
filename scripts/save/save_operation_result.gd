class_name SaveOperationResult
extends RefCounted

var success: bool = false
var error_code: String = ""
var message: String = ""
var path: String = ""
var snapshot: Dictionary = {}


static func ok(result_path: String, data: Dictionary = {}) -> SaveOperationResult:
	var result := SaveOperationResult.new()
	result.success = true
	result.path = result_path
	result.snapshot = data
	return result


static func fail(code: String, detail: String, result_path: String = "") -> SaveOperationResult:
	var result := SaveOperationResult.new()
	result.error_code = code
	result.message = detail
	result.path = result_path
	return result
