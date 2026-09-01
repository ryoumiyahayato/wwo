class_name VNextTransactionCandidateBundle
extends RefCounted

var _transaction_id: String = ""
var _command_id: String = ""
var _base_world_revision: int = -1
var _participant_ids: Array[String] = []
var _before_snapshots: Dictionary = {}
var _candidates: Dictionary = {}
var _fingerprint: String = ""


func configure(
	command: VNextTransactionCommand,
	participant_ids: Array[String],
	before_snapshots: Dictionary,
	candidates: Dictionary
) -> bool:
	if command == null or command.validation_failure() != VNextTransactionContract.FAILURE_NONE:
		return false
	if not VNextTransactionContract.sorted_unique(participant_ids):
		return false
	if not VNextTransactionContract.is_detachable_value(before_snapshots):
		return false
	if not VNextTransactionContract.is_detachable_value(candidates):
		return false
	for participant_id: String in participant_ids:
		if not before_snapshots.has(participant_id) or not candidates.has(participant_id):
			return false
	_transaction_id = command.transaction_id()
	_command_id = command.command_id()
	_base_world_revision = command.expected_world_revision()
	_participant_ids = participant_ids.duplicate()
	_before_snapshots = VNextTransactionContract.detached_copy(before_snapshots)
	_candidates = VNextTransactionContract.detached_copy(candidates)
	_fingerprint = VNextTransactionContract.fingerprint_for(to_detached_dict())
	return true


func transaction_id() -> String:
	return _transaction_id


func participant_ids() -> Array[String]:
	return _participant_ids.duplicate()


func before_snapshot_for(participant_id: String) -> Variant:
	return VNextTransactionContract.detached_copy(_before_snapshots.get(participant_id))


func candidate_for(participant_id: String) -> Variant:
	return VNextTransactionContract.detached_copy(_candidates.get(participant_id))


func fingerprint() -> String:
	return _fingerprint


func to_detached_dict() -> Dictionary:
	return {
		"base_world_revision": _base_world_revision,
		"before_snapshots": VNextTransactionContract.detached_copy(_before_snapshots),
		"candidates": VNextTransactionContract.detached_copy(_candidates),
		"command_id": _command_id,
		"participant_ids": _participant_ids.duplicate(),
		"transaction_id": _transaction_id,
	}
