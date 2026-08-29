class_name HistoricalProvenanceFoundation
extends RefCounted
## Loads the source and fact catalogs; it never becomes a domain data owner.

const SOURCE_REGISTRY_PATH: String = "res://data/provenance/historical_source_registry.json"
const EVIDENCE_CATALOG_PATH: String = "res://data/provenance/historical_fact_evidence.json"
const SPATIAL_BOUNDARY_FACT_ID: String = "spatial_boundary:world_boundaries_1900_03_12"

var _registry := HistoricalSourceRegistry.new()
var _catalog := HistoricalEvidenceCatalog.new()
var _gate: HistoricalProvenanceGate = null
var initialization_error: String = ""


func load_current() -> bool:
	if _gate != null:
		return _fail("Historical provenance is already initialized")
	initialization_error = ""
	# Load into isolated candidates. A malformed source or fact document must not
	# leave a partially adopted provenance boundary behind.
	var candidate_registry := HistoricalSourceRegistry.new()
	var candidate_catalog := HistoricalEvidenceCatalog.new()
	var source_document := _read_document(SOURCE_REGISTRY_PATH)
	var evidence_document := _read_document(EVIDENCE_CATALOG_PATH)
	if source_document.is_empty() or evidence_document.is_empty():
		return _fail("Historical provenance catalog is missing or invalid")
	if not candidate_registry.load_document(source_document):
		return _fail("Historical source registry rejected: %s" % ", ".join(candidate_registry.errors()))
	if not candidate_catalog.load_document(evidence_document):
		return _fail("Historical evidence catalog rejected: %s" % ", ".join(candidate_catalog.errors()))
	_registry = candidate_registry
	_catalog = candidate_catalog
	_gate = HistoricalProvenanceGate.new(_registry, _catalog)
	return true


func is_loaded() -> bool:
	return _gate != null and _catalog.size() > 0 and not _registry.source_ids().is_empty()


func gate() -> HistoricalProvenanceGate:
	return _gate


func registry() -> HistoricalSourceRegistry:
	return _registry


func catalog() -> HistoricalEvidenceCatalog:
	return _catalog


static func admit_spatial_boundary_document(
	gate: HistoricalProvenanceGate, document: Dictionary
) -> bool:
	if gate == null or document.is_empty():
		return false
	var source := document.get("source", {}) as Dictionary
	var snapshot_date := str(document.get("snapshot_date", ""))
	var features := document.get("features", []) as Array
	var feature_count := int(document.get("feature_count", features.size()))
	var assertion := {
		"lower_bound": null,
		"observation_period": {"from": snapshot_date, "to": snapshot_date},
		"spatial_scope": {"kind": "global_boundary_snapshot", "id": "world"},
		"subject_id": "world_boundaries_1900_03_12",
		"unit": "boundary_snapshot",
		"upper_bound": null,
		"value": {
			"feature_count": feature_count,
			"provider": str(document.get("provider", "")),
			"snapshot_date": snapshot_date,
			"upstream_content_hash": str(source.get("source_sha256", "")),
		},
	}
	return gate.admit_runtime_fact(SPATIAL_BOUNDARY_FACT_ID, "spatial_boundary", assertion)


static func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _fail(message: String) -> bool:
	initialization_error = message
	return false
