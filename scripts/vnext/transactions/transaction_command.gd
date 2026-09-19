class_name VNextTransactionCommand
extends RefCounted

var _transaction_id: String = ""
var _command_id: String = ""
var _expected_world_revision: int = -1
var _required_participant_ids: Array[String] = []
var _payload: Dictionary = {}
var _validation_failure: String = VNextTransactionContract.FAILURE_MALFORMED_COMMAND


func configure(
	transaction_id: String,
	command_id: String,
	expected_world_revision: int,
	required_participant_ids: Array[String],
	payload: Dictionary
) -> bool:
	_transaction_id = transaction_id
	_command_id = command_id
	_expected_world_revision = expected_world_revision
	_required_participant_ids = required_participant_ids.duplicate()
	_payload = VNextTransactionContract.detached_copy(payload)
	_validation_failure = _validate()
	return _validation_failure == VNextTransactionContract.FAILURE_NONE


func transaction_id() -> String:
	return _transaction_id


func command_id() -> String:
	return _command_id


func expected_world_revision() -> int:
	return _expected_world_revision


func required_participant_ids() -> Array[String]:
	return _required_participant_ids.duplicate()


func payload() -> Dictionary:
	return VNextTransactionContract.detached_copy(_payload)


func validation_failure() -> String:
	return _validation_failure


func to_detached_dict() -> Dictionary:
	return {
		"command_id": _command_id,
		"expected_world_revision": _expected_world_revision,
		"payload": VNextTransactionContract.detached_copy(_payload),
		"required_participant_ids": _required_participant_ids.duplicate(),
		"transaction_id": _transaction_id,
	}


func _validate() -> String:
	if (
		not VNextTransactionContract.is_valid_identity(_transaction_id)
		or not VNextTransactionContract.is_valid_identity(_command_id)
		or _expected_world_revision < 0
		or _required_participant_ids.is_empty()
		or not VNextTransactionContract.is_detachable_value(_payload)
	):
		return VNextTransactionContract.FAILURE_MALFORMED_COMMAND
	var sorted_ids: Array[String] = _required_participant_ids.duplicate()
	sorted_ids.sort()
	for participant_id: String in sorted_ids:
		if not VNextTransactionContract.is_valid_identity(participant_id):
			return VNextTransactionContract.FAILURE_MALFORMED_COMMAND
	if not VNextTransactionContract.sorted_unique(sorted_ids):
		return VNextTransactionContract.FAILURE_DUPLICATE_PARTICIPANT
	_required_participant_ids = sorted_ids
	return VNextTransactionContract.FAILURE_NONE
