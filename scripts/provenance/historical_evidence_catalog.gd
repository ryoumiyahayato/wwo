class_name HistoricalEvidenceCatalog
extends RefCounted
## Deterministic fact-level evidence index. Duplicate fact IDs fail closed.

const SCHEMA_ID: String = "historical_fact_evidence_catalog_v1"

var _facts_by_id: Dictionary = {}
var _errors: Array[String] = []


func load_document(document: Dictionary) -> bool:
	if not _facts_by_id.is_empty():
		return false
	if str(document.get("schema_id", "")) != SCHEMA_ID:
		_errors.append("evidence catalog schema is invalid")
		return false
	var facts_value: Variant = document.get("facts")
	if not facts_value is Array:
		_errors.append("evidence catalog requires facts array")
		return false
	for fact_value: Variant in facts_value as Array:
		if not fact_value is Dictionary or not add_fact(fact_value as Dictionary):
			return false
	return not _facts_by_id.is_empty()


func add_fact(document: Dictionary) -> bool:
	var evidence := HistoricalFactEvidence.from_dictionary(document)
	if evidence == null:
		_errors.append("fact does not satisfy HistoricalFactEvidence contract")
		return false
	var error := evidence.validation_error()
	if not error.is_empty():
		_errors.append("%s: %s" % [evidence.fact_id, error])
		return false
	if _facts_by_id.has(evidence.fact_id):
		_errors.append("duplicate fact_id: " + evidence.fact_id)
		return false
	_facts_by_id[evidence.fact_id] = evidence
	return true


func fact(fact_id: String) -> HistoricalFactEvidence:
	var value: Variant = _facts_by_id.get(fact_id)
	return value as HistoricalFactEvidence if value is HistoricalFactEvidence else null


func fact_ids() -> Array[String]:
	var output: Array[String] = []
	for fact_id: Variant in _facts_by_id.keys():
		output.append(str(fact_id))
	output.sort()
	return output


func deterministic_hash() -> String:
	var ordered: Array[Dictionary] = []
	for fact_id: String in fact_ids():
		ordered.append(fact(fact_id).to_dictionary())
	return HistoricalFactEvidence.sha256(ordered)


func size() -> int:
	return _facts_by_id.size()


func errors() -> Array[String]:
	return _errors.duplicate()
