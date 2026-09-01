class_name RuntimePoliticalEntityRegistry
extends RefCounted
## Sole owner of political identities in the current formal world. Historical
## validity queries never mutate this registry.

const SCHEMA_ID: String = "runtime_political_registry_v2"
const LEGACY_SCHEMA_ID: String = "runtime_political_registry_v1"
const INITIAL_DATE: String = "1900-01-01"
const EXPECTED_INITIAL_ENTITY_COUNT: int = 146
const ALLOWED_RELATION_KINDS: Array[String] = [
	"administration",
	"legacy_controller",
	"occupation",
	"protection",
]

var initialization_error: String = ""
var _configured: bool = false
var _evidence_fingerprint: String = ""
var _entities_by_runtime_id: Dictionary = {}
var _runtime_id_by_source_id: Dictionary = {}
var _authority_relations: Array[Dictionary] = []


func configure(evidence: HistoricalPoliticalEvidenceCatalog) -> bool:
	if _configured:
		return _fail("Runtime political registry is already initialized")
	initialization_error = ""
	_evidence_fingerprint = ""
	_entities_by_runtime_id.clear()
	_runtime_id_by_source_id.clear()
	_authority_relations.clear()
	if evidence == null or not evidence.is_configured():
		return _fail("Runtime politics requires configured historical evidence")

	for record: Dictionary in evidence.records_active_on(INITIAL_DATE):
		var source_id := str(record.get("source_historical_id", ""))
		var entity := RuntimePoliticalEntity.historical_seed(source_id)
		if (
			entity.runtime_id.is_empty()
			or _entities_by_runtime_id.has(entity.runtime_id)
			or _runtime_id_by_source_id.has(source_id)
		):
			return _fail("Invalid or duplicate runtime political identity: %s" % source_id)
		_entities_by_runtime_id[entity.runtime_id] = entity.snapshot()
		_runtime_id_by_source_id[source_id] = entity.runtime_id

	if _entities_by_runtime_id.size() != EXPECTED_INITIAL_ENTITY_COUNT:
		return _fail(
			"1900-01-01 runtime political entity count must be %d" % (
				EXPECTED_INITIAL_ENTITY_COUNT
			)
		)
	if not _seed_authority_relations(evidence):
		return false
	_evidence_fingerprint = evidence.fingerprint()
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func entity_count() -> int:
	return _entities_by_runtime_id.size()


func has_entity(runtime_id: String) -> bool:
	return _entities_by_runtime_id.has(runtime_id)


func entity(runtime_id: String) -> Dictionary:
	return (
		(_entities_by_runtime_id.get(runtime_id, {}) as Dictionary)
		.duplicate(true)
	)


func entity_ids() -> Array[String]:
	var result: Array[String] = []
	for runtime_id_value: Variant in _entities_by_runtime_id.keys():
		result.append(str(runtime_id_value))
	result.sort()
	return result


func entities() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for runtime_id: String in entity_ids():
		result.append(entity(runtime_id))
	return result


func runtime_id_for_source(source_historical_id: String) -> String:
	return str(_runtime_id_by_source_id.get(source_historical_id, ""))


func source_historical_id(runtime_id: String) -> String:
	var candidate := _entities_by_runtime_id.get(runtime_id, {}) as Dictionary
	var sources := DataRecordUtils.to_string_array(
		candidate.get("source_historical_ids", [])
	)
	return sources[0] if sources.size() == 1 else ""


func authority_relations() -> Array[Dictionary]:
	return _authority_relations.duplicate(true)


func authority_relations_for_target(runtime_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for relation: Dictionary in _authority_relations:
		if str(relation.get("target_runtime_id", "")) == runtime_id:
			result.append(relation.duplicate(true))
	return result


func snapshot() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"evidence_fingerprint": _evidence_fingerprint,
		"entities": entities(),
		"authority_relations": authority_relations(),
	}


func restore_snapshot(
	snapshot_value: Dictionary,
	evidence: HistoricalPoliticalEvidenceCatalog
) -> bool:
	if evidence == null or not evidence.is_configured():
		return false
	if (
		str(snapshot_value.get("schema_id", "")) not in [SCHEMA_ID, LEGACY_SCHEMA_ID]
		or str(snapshot_value.get("evidence_fingerprint", ""))
		!= evidence.fingerprint()
		or not snapshot_value.get("entities", []) is Array
		or not snapshot_value.get("authority_relations", []) is Array
	):
		return false

	var candidate_entities: Dictionary = {}
	var candidate_sources: Dictionary = {}
	for entity_value: Variant in snapshot_value.get("entities", []) as Array:
		if not entity_value is Dictionary:
			return false
		var candidate := (entity_value as Dictionary).duplicate(true)
		if candidate.has("controller_id"):
			return false
		var runtime_id := str(candidate.get("runtime_id", ""))
		var sources := DataRecordUtils.to_string_array(
			candidate.get("source_historical_ids", [])
		)
		var lineage_value: Variant = candidate.get("lineage", {})
		if (
			candidate.keys().size() != 4
			or not VNextStableId.is_valid(runtime_id)
			or VNextStableId.kind_of(runtime_id) != "state"
			or candidate_entities.has(runtime_id)
			or sources.size() != 1
			or candidate_sources.has(sources[0])
			or not evidence.has_source(sources[0])
			or runtime_id
			!= RuntimePoliticalEntity.runtime_id_for_historical_source(sources[0])
			or str(candidate.get("lifecycle_status", ""))
			!= RuntimePoliticalEntity.STATUS_ACTIVE
			or not lineage_value is Dictionary
			or not _valid_seed_lineage(lineage_value as Dictionary)
		):
			return false
		candidate["source_historical_ids"] = sources
		candidate_entities[runtime_id] = candidate
		candidate_sources[sources[0]] = runtime_id

	var expected_sources := evidence.source_ids_active_on(INITIAL_DATE)
	var candidate_source_ids: Array[String] = []
	for source_value: Variant in candidate_sources.keys():
		candidate_source_ids.append(str(source_value))
	candidate_source_ids.sort()
	if candidate_source_ids != expected_sources:
		return false

	var expected_relations := _expected_authority_relations(
		evidence, candidate_sources
	)
	var candidate_relations: Array[Dictionary] = []
	if str(snapshot_value.get("schema_id", "")) == LEGACY_SCHEMA_ID:
		var legacy_relations := DataRecordUtils.to_dictionary_array(
			snapshot_value.get("authority_relations", [])
		)
		_sort_legacy_relations(legacy_relations)
		if legacy_relations != _legacy_authority_relations(expected_relations):
			return false
		candidate_relations = expected_relations
	else:
		var relation_keys: Dictionary = {}
		for relation_value: Variant in snapshot_value.get("authority_relations", []) as Array:
			if not relation_value is Dictionary:
				return false
			var relation := (relation_value as Dictionary).duplicate(true)
			var source_id := str(relation.get("source_runtime_id", ""))
			var target_id := str(relation.get("target_runtime_id", ""))
			var relation_type := str(relation.get("relation_type", ""))
			var relation_key := "%s|%s|%s" % [target_id, relation_type, source_id]
			if (
				relation.keys().size() != 6
				or not candidate_entities.has(source_id)
				or not candidate_entities.has(target_id)
				or relation_type not in ALLOWED_RELATION_KINDS
				or relation_keys.has(relation_key)
				or not relation.get("provenance", {}) is Dictionary
				or str(relation.get("valid_from", "")).is_empty()
				or str(relation.get("valid_to", "")).is_empty()
			):
				return false
			relation_keys[relation_key] = true
			candidate_relations.append(relation)
		_sort_relations(candidate_relations)
		if candidate_relations != expected_relations:
			return false

	_entities_by_runtime_id = candidate_entities
	_runtime_id_by_source_id = candidate_sources
	_authority_relations = candidate_relations
	_evidence_fingerprint = evidence.fingerprint()
	_configured = true
	initialization_error = ""
	return true


func _seed_authority_relations(
	evidence: HistoricalPoliticalEvidenceCatalog
) -> bool:
	_authority_relations = _expected_authority_relations(
		evidence, _runtime_id_by_source_id
	)
	for relation: Dictionary in _authority_relations:
		if (
			str(relation.get("source_runtime_id", "")).is_empty()
			or str(relation.get("target_runtime_id", "")).is_empty()
		):
			return _fail("Historical controller is not an initial runtime entity")
	return true


func _expected_authority_relations(
	evidence: HistoricalPoliticalEvidenceCatalog,
	runtime_ids_by_source: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in evidence.records_active_on(INITIAL_DATE):
		var controller_source_id := str(record.get("controller_id", ""))
		if controller_source_id.is_empty():
			continue
		var subject_source_id := str(record.get("source_historical_id", ""))
		result.append({
			"source_runtime_id": str(
				runtime_ids_by_source.get(controller_source_id, "")
			),
			"target_runtime_id": str(
				runtime_ids_by_source.get(subject_source_id, "")
			),
			"relation_type": _relation_kind_for(
				str(record.get("relationship", ""))
			),
			"valid_from": str(record.get("valid_from", "")),
			"valid_to": str(record.get("valid_to", "")),
			"provenance": {
				"source_historical_id": subject_source_id,
				"source_field": "controller_id",
				"source_relationship": str(record.get("relationship", "")),
			},
		})
	_sort_relations(result)
	return result


func _relation_kind_for(source_relationship: String) -> String:
	match source_relationship:
		"administered_territory": return "administration"
		"military_occupation": return "occupation"
		"protected_state", "protected_territory": return "protection"
		_: return "legacy_controller"


func _valid_seed_lineage(lineage: Dictionary) -> bool:
	return (
		str(lineage.get("origin_kind", ""))
		== RuntimePoliticalEntity.ORIGIN_HISTORICAL_SEED
		and int(lineage.get("origin_tick", -1)) == 0
		and lineage.get("predecessor_runtime_ids", []) is Array
		and (lineage.get("predecessor_runtime_ids", []) as Array).is_empty()
	)


func _sort_relations(relations: Array[Dictionary]) -> void:
	relations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key := "%s|%s|%s" % [
			str(a.get("target_runtime_id", "")),
			str(a.get("relation_type", "")),
			str(a.get("source_runtime_id", "")),
		]
		var b_key := "%s|%s|%s" % [
			str(b.get("target_runtime_id", "")),
			str(b.get("relation_type", "")),
			str(b.get("source_runtime_id", "")),
		]
		return a_key < b_key
	)


func _legacy_authority_relations(
	typed_relations: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for relation: Dictionary in typed_relations:
		result.append({
			"subject_runtime_id": str(relation.get("target_runtime_id", "")),
			"authority_runtime_id": str(relation.get("source_runtime_id", "")),
			"relation_kind": str(relation.get("relation_type", "")),
			"provenance": (
				relation.get("provenance", {}) as Dictionary
			).duplicate(true),
		})
	_sort_legacy_relations(result)
	return result


func _sort_legacy_relations(relations: Array[Dictionary]) -> void:
	relations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key := "%s|%s|%s" % [
			str(a.get("subject_runtime_id", "")),
			str(a.get("relation_kind", "")),
			str(a.get("authority_runtime_id", "")),
		]
		var b_key := "%s|%s|%s" % [
			str(b.get("subject_runtime_id", "")),
			str(b.get("relation_kind", "")),
			str(b.get("authority_runtime_id", "")),
		]
		return a_key < b_key
	)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
