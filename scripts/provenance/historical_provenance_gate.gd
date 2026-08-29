class_name HistoricalProvenanceGate
extends RefCounted
## Fail-closed admission boundary between evidence and runtime domain owners.

const VERIFIED: String = "VERIFIED"

var _registry: HistoricalSourceRegistry
var _catalog: HistoricalEvidenceCatalog
var _errors: Array[String] = []


func _init(registry: HistoricalSourceRegistry, catalog: HistoricalEvidenceCatalog) -> void:
	_registry = registry
	_catalog = catalog


func admit_runtime_fact(fact_id: String, domain: String, assertion: Dictionary) -> bool:
	var evidence := _catalog.fact(fact_id) if _catalog != null else null
	if evidence == null:
		return _reject("missing evidence: " + fact_id)
	if evidence.domain != domain:
		return _reject("evidence domain mismatch: " + fact_id)
	var source := _registry.source(evidence.source_id) if _registry != null else {}
	if source.is_empty():
		return _reject("missing source: " + evidence.source_id)
	if (
		evidence.source_version != str(source.get("version", ""))
		or evidence.source_locator != str(source.get("locator", ""))
		or evidence.license != str(source.get("license", ""))
		or evidence.input_hash != str(source.get("content_hash", ""))
	):
		return _reject("source binding mismatch: " + fact_id)
	if HistoricalFactEvidence.sha256(assertion) != evidence.output_hash:
		return _reject("runtime fact hash mismatch: " + fact_id)
	return true


func is_verified(fact_id: String, domain: String, assertion: Dictionary) -> bool:
	var evidence := _catalog.fact(fact_id) if _catalog != null else null
	return (
		evidence != null
		and evidence.review_status == VERIFIED
		and admit_runtime_fact(fact_id, domain, assertion)
	)


func errors() -> Array[String]:
	return _errors.duplicate()


func _reject(reason: String) -> bool:
	_errors.append(reason)
	return false
