class_name VNextObservationResponse
extends RefCounted

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")

var _schema_id: String = CONTRACT.SCHEMA_ID
var _observation_id: String = ""
var _world_revision: int = CONTRACT.UNSPECIFIED_WORLD_REVISION
var _observer_actor_id: String = ""
var _observed_at: int = 0
var _status: String = CONTRACT.STATUS_INVALID_REQUEST
var _error_code: String = ""
var _stale: bool = true
var _revision_mismatch: bool = false
var _records: Array[VNextObservationRecord] = []


static func success(
	world_revision_value: int,
	observer_actor_id_value: String,
	observed_at_value: int,
	records_value: Array[VNextObservationRecord],
	stale_value: bool = false
) -> VNextObservationResponse:
	var response := VNextObservationResponse.new()
	response._world_revision = world_revision_value
	response._observer_actor_id = observer_actor_id_value
	response._observed_at = observed_at_value
	response._status = CONTRACT.STATUS_OK
	response._error_code = ""
	response._stale = stale_value
	response._revision_mismatch = false
	response._records = response._copy_records(records_value)
	response._observation_id = "observation-" + response.fingerprint().left(24)
	return response


static func failure(
	status_value: String,
	observer_actor_id_value: String,
	world_revision_value: int,
	observed_at_value: int,
	error_code_value: String,
	stale_value: bool = true
) -> VNextObservationResponse:
	var response := VNextObservationResponse.new()
	response._status = status_value
	response._observer_actor_id = observer_actor_id_value
	response._world_revision = world_revision_value
	response._observed_at = observed_at_value
	response._error_code = error_code_value
	response._stale = stale_value
	response._revision_mismatch = status_value == CONTRACT.STATUS_REVISION_MISMATCH
	response._records = []
	response._observation_id = "observation-" + response.fingerprint().left(24)
	return response


func schema_id() -> String:
	return _schema_id


func observation_id() -> String:
	return _observation_id


func world_revision() -> int:
	return _world_revision


func observer_actor_id() -> String:
	return _observer_actor_id


func observed_at() -> int:
	return _observed_at


func status() -> String:
	return _status


func error_code() -> String:
	return _error_code


func is_success() -> bool:
	return _status == CONTRACT.STATUS_OK


func is_stale() -> bool:
	return _stale


func is_revision_mismatch() -> bool:
	return _revision_mismatch


func records() -> Array[VNextObservationRecord]:
	return _copy_records(_records)


func fingerprint() -> String:
	var semantic_value: Dictionary = _semantic_dictionary()
	return CONTRACT.fingerprint_for(semantic_value)


func to_detached_dict() -> Dictionary:
	var serialized_records: Array = []
	for record: VNextObservationRecord in _records:
		serialized_records.append(record.to_detached_dict())
	var result: Dictionary = {
		"schema_id": _schema_id,
		"observation_id": _observation_id,
		"world_revision": _world_revision,
		"observer_actor_id": _observer_actor_id,
		"observed_at": _observed_at,
		"status": _status,
		"stale": _stale,
		"revision_mismatch": _revision_mismatch,
		"records": serialized_records,
	}
	if not _error_code.is_empty():
		result["error_code"] = _error_code
	return result


func _semantic_dictionary() -> Dictionary:
	var serialized_records: Array = []
	for record: VNextObservationRecord in _records:
		serialized_records.append(record.to_detached_dict())
	return {
		"schema_id": _schema_id,
		"world_revision": _world_revision,
		"observer_actor_id": _observer_actor_id,
		"status": _status,
		"stale": _stale,
		"revision_mismatch": _revision_mismatch,
		"error_code": _error_code,
		"records": serialized_records,
	}


func _copy_records(source: Array[VNextObservationRecord]) -> Array[VNextObservationRecord]:
	var copied: Array[VNextObservationRecord] = []
	for record: VNextObservationRecord in source:
		var record_copy: VNextObservationRecord = record.copy_detached()
		if record_copy != null:
			copied.append(record_copy)
	return copied
