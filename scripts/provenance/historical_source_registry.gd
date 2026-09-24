class_name HistoricalSourceRegistry
extends RefCounted
## Source identity and immutable content-hash registry. It owns no domain data.

const REQUIRED_FIELDS: Array[String] = [
	"source_id", "title", "publisher", "version", "license", "locator",
	"access_metadata", "content_hash",
]
const SCHEMA_ID: String = "historical_source_registry_v1"

var _sources_by_id: Dictionary = {}
var _errors: Array[String] = []


func load_document(document: Dictionary) -> bool:
	if not _sources_by_id.is_empty():
		return false
	if str(document.get("schema_id", "")) != SCHEMA_ID:
		_errors.append("source registry schema is invalid")
		return false
	var sources_value: Variant = document.get("sources")
	if not sources_value is Array:
		_errors.append("source registry requires sources array")
		return false
	for source_value: Variant in sources_value as Array:
		if not source_value is Dictionary or not register_source(source_value as Dictionary):
			return false
	return not _sources_by_id.is_empty()


func register_source(source: Dictionary) -> bool:
	for field: String in REQUIRED_FIELDS:
		if not source.has(field):
			_errors.append("source missing field: " + field)
			return false
	if not source.get("access_metadata") is Dictionary:
		_errors.append("source access_metadata must be an object")
		return false
	var source_id := str(source.get("source_id"))
	for field: String in ["source_id", "title", "publisher", "version", "license", "locator"]:
		if str(source.get(field)).strip_edges().is_empty():
			_errors.append("source field is empty: " + field)
			return false
	var content_hash := str(source.get("content_hash"))
	if not HistoricalFactEvidence.is_sha256(content_hash):
		_errors.append("source content_hash is not SHA-256")
		return false
	if source_id in _sources_by_id:
		_errors.append("duplicate source_id: " + source_id)
		return false
	var locator := str(source.get("locator"))
	if locator.begins_with("res://"):
		if not FileAccess.file_exists(locator):
			_errors.append("source locator does not exist: " + locator)
			return false
		if FileAccess.get_sha256(locator) != content_hash:
			_errors.append("source content hash mismatch: " + source_id)
			return false
	_sources_by_id[source_id] = source.duplicate(true)
	return true


func has_source(source_id: String) -> bool:
	return _sources_by_id.has(source_id)


func source(source_id: String) -> Dictionary:
	var value: Variant = _sources_by_id.get(source_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func source_ids() -> Array[String]:
	var output: Array[String] = []
	for source_id: Variant in _sources_by_id.keys():
		output.append(str(source_id))
	output.sort()
	return output


func errors() -> Array[String]:
	return _errors.duplicate()
