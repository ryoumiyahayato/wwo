class_name VNextPersonalWallet
extends RefCounted

const SNAPSHOT_SCHEMA_ID: String = "vnext_personal_wallet_v1"
const MAX_BALANCE_MINOR: int = 9_007_199_254_740_991

var _owner_person_id: String
var _balance_minor: int = 0


func _init(owner_person_id: String) -> void:
	assert(_is_valid_person_id(owner_person_id))
	_owner_person_id = owner_person_id


static func create(owner_person_id: String) -> VNextPersonalWallet:
	if not _is_valid_person_id(owner_person_id):
		return null
	return VNextPersonalWallet.new(owner_person_id)


func owner_id() -> String:
	return _owner_person_id


func balance_minor() -> int:
	return _balance_minor


func can_debit(amount_minor: int) -> bool:
	return amount_minor > 0 and amount_minor <= _balance_minor


func credit(amount_minor: int) -> bool:
	if amount_minor <= 0:
		return false
	if amount_minor > MAX_BALANCE_MINOR - _balance_minor:
		return false
	_balance_minor += amount_minor
	return true


func debit(amount_minor: int) -> bool:
	if not can_debit(amount_minor):
		return false
	_balance_minor -= amount_minor
	return true


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"owner_person_id": _owner_person_id,
		"balance_minor": _balance_minor,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if not snapshot_value.has("owner_person_id") or not snapshot_value.has("balance_minor"):
		return false

	var candidate_owner_value: Variant = snapshot_value.get("owner_person_id")
	if typeof(candidate_owner_value) != TYPE_STRING:
		return false
	var candidate_owner_person_id: String = str(candidate_owner_value)
	if not _is_valid_person_id(candidate_owner_person_id):
		return false

	var normalized_balance: Dictionary = _normalize_balance_minor(
		snapshot_value.get("balance_minor")
	)
	if normalized_balance.is_empty():
		return false

	_owner_person_id = candidate_owner_person_id
	_balance_minor = int(normalized_balance["value"])
	return true


static func _is_valid_person_id(candidate_value: String) -> bool:
	return (
		VNextStableId.is_valid(candidate_value)
		and VNextStableId.kind_of(candidate_value) == "person"
	)


static func _normalize_balance_minor(candidate_value: Variant) -> Dictionary:
	var candidate_balance_minor: int
	var candidate_type: int = typeof(candidate_value)
	if candidate_type == TYPE_INT:
		candidate_balance_minor = int(candidate_value)
	elif candidate_type == TYPE_FLOAT:
		var candidate_float: float = float(candidate_value)
		if not is_finite(candidate_float):
			return {}
		if candidate_float != floor(candidate_float):
			return {}
		if candidate_float < 0.0 or candidate_float > float(MAX_BALANCE_MINOR):
			return {}
		candidate_balance_minor = int(candidate_float)
	else:
		return {}

	if candidate_balance_minor < 0 or candidate_balance_minor > MAX_BALANCE_MINOR:
		return {}
	return {"value": candidate_balance_minor}
