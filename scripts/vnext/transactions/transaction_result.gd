class_name VNextTransactionResult
extends RefCounted

var _status: String = VNextTransactionContract.STATUS_REJECTED
var _failure_code: String = VNextTransactionContract.FAILURE_MALFORMED_COMMAND
var _transaction_id: String = ""
var _command_id: String = ""
var _world_revision_before: int = -1
var _world_revision_after: int = -1
var _participant_ids: Array[String] = []
var _candidate_fingerprint: String = ""
var _candidate_bundle: Dictionary = {}


func configure(
	status: String,
	failure_code: String,
	transaction_id: String,
	command_id: String,
	world_revision_before: int,
	world_revision_after: int,
	participant_ids: Array[String],
	candidate_fingerprint: String = "",
	candidate_bundle: Dictionary = {}
) -> void:
	_status = status
	_failure_code = failure_code
	_transaction_id = transaction_id
	_command_id = command_id
	_world_revision_before = world_revision_before
	_world_revision_after = world_revision_after
	_participant_ids = participant_ids.duplicate()
	_candidate_fingerprint = candidate_fingerprint
	_candidate_bundle = VNextTransactionContract.detached_copy(candidate_bundle)


func is_success() -> bool:
	return _status == VNextTransactionContract.STATUS_COMMITTED


func status() -> String:
	return _status


func failure_code() -> String:
	return _failure_code


func transaction_id() -> String:
	return _transaction_id


func command_id() -> String:
	return _command_id


func world_revision_before() -> int:
	return _world_revision_before


func world_revision_after() -> int:
	return _world_revision_after


func participant_ids() -> Array[String]:
	return _participant_ids.duplicate()


func candidate_fingerprint() -> String:
	return _candidate_fingerprint


func candidate_bundle() -> Dictionary:
	return VNextTransactionContract.detached_copy(_candidate_bundle)


func to_detached_dict() -> Dictionary:
	return {
		"candidate_bundle": candidate_bundle(),
		"candidate_fingerprint": _candidate_fingerprint,
		"command_id": _command_id,
		"failure_code": _failure_code,
		"participant_ids": _participant_ids.duplicate(),
		"status": _status,
		"transaction_id": _transaction_id,
		"world_revision_after": _world_revision_after,
		"world_revision_before": _world_revision_before,
	}
