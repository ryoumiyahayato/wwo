class_name VNextSyntheticTransactionParticipant
extends VNextTransactionParticipant

var _participant_id: String = ""
var _value: int = 0
var _prepare_failure: bool = false
var _local_validation_failure: bool = false
var _adopt_count: int = 0
var _prepare_order_log: Array[String] = []
var _shared_prepare_order_log: Array[String] = []


func configure(participant_id_value: String, initial_value: int) -> bool:
	if not VNextTransactionContract.is_valid_identity(participant_id_value):
		return false
	_participant_id = participant_id_value
	_value = initial_value
	return true


func participant_id() -> String:
	return _participant_id


func authoritative_snapshot() -> Variant:
	return {"participant_id": _participant_id, "value": _value}


func prepare_candidate(command: VNextTransactionCommand) -> Dictionary:
	_prepare_order_log.append(_participant_id)
	_shared_prepare_order_log.append(_participant_id)
	if _prepare_failure:
		return {"ok": false}
	var payload: Dictionary = command.payload()
	var deltas_value: Variant = payload.get("deltas", {})
	if typeof(deltas_value) != TYPE_DICTIONARY:
		return {"ok": false}
	var deltas: Dictionary = deltas_value
	var delta_value: Variant = deltas.get(_participant_id, 0)
	if typeof(delta_value) != TYPE_INT:
		return {"ok": false}
	return {
		"ok": true,
		"candidate": {"participant_id": _participant_id, "value": _value + int(delta_value)},
	}


func validate_candidate(candidate: Variant, _command: VNextTransactionCommand) -> bool:
	if _local_validation_failure or typeof(candidate) != TYPE_DICTIONARY:
		return false
	var candidate_dictionary: Dictionary = candidate
	return (
		candidate_dictionary.get("participant_id") == _participant_id
		and typeof(candidate_dictionary.get("value")) == TYPE_INT
		and int(candidate_dictionary.get("value")) >= 0
	)


func adopt_candidate(candidate: Variant) -> void:
	var candidate_dictionary: Dictionary = candidate
	_value = int(candidate_dictionary.get("value"))
	_adopt_count += 1


func value() -> int:
	return _value


func adopt_count() -> int:
	return _adopt_count


func set_prepare_failure(enabled: bool) -> void:
	_prepare_failure = enabled


func set_local_validation_failure(enabled: bool) -> void:
	_local_validation_failure = enabled


func prepare_order_log() -> Array[String]:
	return _prepare_order_log.duplicate()


func use_shared_prepare_order_log(shared_log: Array[String]) -> void:
	_shared_prepare_order_log = shared_log
