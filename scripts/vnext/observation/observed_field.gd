class_name VNextObservedField
extends RefCounted

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")

var _field_id: String = ""
var _perceived_value: Variant = null
var _confidence: float = 0.0
var _acquired_at: int = 0
var _observed_state_at: int = 0
var _provenance_references: Array[String] = []
var _freshness_state: String = CONTRACT.FRESHNESS_FRESH
var _extensions: Dictionary = {}


func configure(
	field_id_value: Variant,
	perceived_value_value: Variant,
	confidence_value: Variant,
	acquired_at_value: Variant,
	observed_state_at_value: Variant,
	provenance_references_value: Variant,
	freshness_state_value: Variant = CONTRACT.FRESHNESS_FRESH,
	extensions_value: Variant = {}
) -> bool:
	if typeof(field_id_value) != TYPE_STRING:
		return false
	var candidate_field_id: String = str(field_id_value)
	if not CONTRACT.is_valid_token(candidate_field_id):
		return false
	if not CONTRACT.is_detachable_value(perceived_value_value):
		return false
	if typeof(confidence_value) != TYPE_FLOAT and typeof(confidence_value) != TYPE_INT:
		return false
	if typeof(confidence_value) == TYPE_BOOL:
		return false
	var candidate_confidence: float = float(confidence_value)
	if not is_finite(candidate_confidence) or candidate_confidence < 0.0 or candidate_confidence > 1.0:
		return false
	if typeof(acquired_at_value) != TYPE_INT or int(acquired_at_value) < 0:
		return false
	if typeof(observed_state_at_value) != TYPE_INT or int(observed_state_at_value) < 0:
		return false
	if not CONTRACT.is_valid_freshness(freshness_state_value):
		return false
	if typeof(provenance_references_value) != TYPE_ARRAY:
		return false
	var candidate_provenance: Array[String] = []
	for raw_reference: Variant in provenance_references_value as Array:
		if typeof(raw_reference) != TYPE_STRING:
			return false
		var reference: String = str(raw_reference)
		if not CONTRACT.is_valid_provenance_reference(reference) or candidate_provenance.has(reference):
			return false
		candidate_provenance.append(reference)
	candidate_provenance.sort()
	if typeof(extensions_value) != TYPE_DICTIONARY or not CONTRACT.is_detachable_value(extensions_value):
		return false

	_field_id = candidate_field_id
	_perceived_value = CONTRACT.detached_copy(perceived_value_value)
	_confidence = candidate_confidence
	_acquired_at = int(acquired_at_value)
	_observed_state_at = int(observed_state_at_value)
	_provenance_references = candidate_provenance
	_freshness_state = str(freshness_state_value)
	_extensions = CONTRACT.detached_copy(extensions_value) as Dictionary
	return true


func field_id() -> String:
	return _field_id


func perceived_value() -> Variant:
	return CONTRACT.detached_copy(_perceived_value)


func confidence() -> float:
	return _confidence


func acquired_at() -> int:
	return _acquired_at


func observed_state_at() -> int:
	return _observed_state_at


func provenance_references() -> Array[String]:
	return CONTRACT.copy_string_array(_provenance_references)


func freshness_state() -> String:
	return _freshness_state


func is_stale() -> bool:
	return _freshness_state == CONTRACT.FRESHNESS_STALE


func extensions() -> Dictionary:
	return CONTRACT.detached_copy(_extensions) as Dictionary


func replace_perceived_value(candidate_value: Variant) -> bool:
	if not CONTRACT.is_detachable_value(candidate_value):
		return false
	_perceived_value = CONTRACT.detached_copy(candidate_value)
	return true


func copy_detached() -> VNextObservedField:
	var copy := VNextObservedField.new()
	copy.configure(
		_field_id,
		_perceived_value,
		_confidence,
		_acquired_at,
		_observed_state_at,
		_provenance_references,
		_freshness_state,
		_extensions
	)
	return copy


func to_detached_dict() -> Dictionary:
	return {
		"field_id": _field_id,
		"perceived_value": perceived_value(),
		"confidence": _confidence,
		"acquired_at": _acquired_at,
		"observed_state_at": _observed_state_at,
		"provenance_references": provenance_references(),
		"freshness": _freshness_state,
		"extensions": extensions(),
	}
