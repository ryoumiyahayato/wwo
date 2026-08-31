class_name VNextPopulationCandidate
extends RefCounted
## Detached proposal for one Population Authority adoption boundary.

const TRANSFER: String = "TRANSFER"
const RESTORE: String = "RESTORE"

var _configured: bool = false
var _operation: String = ""
var _expected_revision: int = -1
var _target_revision: int = -1
var _expected_authority_fingerprint: String = ""
var _territory_catalog_binding: Dictionary = {}
var _records: Array = []
var _state_fingerprint: String = ""
var _source_territory_unit_id: String = ""
var _destination_territory_unit_id: String = ""
var _amount: int = 0


func configure(
	operation_value: String,
	expected_revision_value: int,
	target_revision_value: int,
	expected_authority_fingerprint_value: String,
	territory_catalog_binding_value: Dictionary,
	records_value: Array,
	state_fingerprint_value: String,
	source_territory_unit_id_value: String = "",
	destination_territory_unit_id_value: String = "",
	amount_value: int = 0
) -> bool:
	if _configured or (operation_value != TRANSFER and operation_value != RESTORE):
		return false
	_operation = operation_value
	_expected_revision = expected_revision_value
	_target_revision = target_revision_value
	_expected_authority_fingerprint = expected_authority_fingerprint_value
	_territory_catalog_binding = territory_catalog_binding_value.duplicate(true)
	_records = records_value.duplicate(true)
	_state_fingerprint = state_fingerprint_value
	_source_territory_unit_id = source_territory_unit_id_value
	_destination_territory_unit_id = destination_territory_unit_id_value
	_amount = amount_value
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func operation() -> String:
	return _operation


func expected_revision() -> int:
	return _expected_revision


func target_revision() -> int:
	return _target_revision


func expected_authority_fingerprint() -> String:
	return _expected_authority_fingerprint


func territory_catalog_binding() -> Dictionary:
	return _territory_catalog_binding.duplicate(true)


func records() -> Array:
	return _records.duplicate(true)


func state_fingerprint() -> String:
	return _state_fingerprint


func source_territory_unit_id() -> String:
	return _source_territory_unit_id


func destination_territory_unit_id() -> String:
	return _destination_territory_unit_id


func amount() -> int:
	return _amount


func to_detached_dict() -> Dictionary:
	if not _configured:
		return {}
	return {
		"operation": _operation,
		"expected_revision": _expected_revision,
		"target_revision": _target_revision,
		"expected_authority_fingerprint": _expected_authority_fingerprint,
		"territory_catalog_binding": _territory_catalog_binding.duplicate(true),
		"records": _records.duplicate(true),
		"state_fingerprint": _state_fingerprint,
		"source_territory_unit_id": _source_territory_unit_id,
		"destination_territory_unit_id": _destination_territory_unit_id,
		"amount": _amount,
	}
