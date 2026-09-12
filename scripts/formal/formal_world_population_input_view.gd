class_name FormalWorldPopulationInputView
extends RefCounted
## Read-only demographic facts consumed by Economy. Economy cannot update them.

var _revision: String = ""
var _fingerprint: String = ""
var _records_by_economy_id: Dictionary = {}
var _provenance: Dictionary = {}


func _init(snapshot: Dictionary = {}) -> void:
	_revision = str(snapshot.get("revision", ""))
	_fingerprint = str(snapshot.get("fingerprint", ""))
	_provenance = (snapshot.get("provenance", {}) as Dictionary).duplicate(true)
	for record: Dictionary in DataRecordUtils.to_dictionary_array(
		snapshot.get("records", [])
	):
		var economy_id := str(record.get("economy_entity_id", ""))
		if not economy_id.is_empty():
			_records_by_economy_id[economy_id] = record.duplicate(true)


func is_configured() -> bool:
	return not _revision.is_empty() and not _fingerprint.is_empty()


func revision() -> String:
	return _revision


func fingerprint() -> String:
	return _fingerprint


func fact(economy_entity_id: String) -> Dictionary:
	return (
		(_records_by_economy_id.get(economy_entity_id, {}) as Dictionary)
		.duplicate(true)
	)


func population(economy_entity_id: String) -> int:
	var record := _records_by_economy_id.get(economy_entity_id, {}) as Dictionary
	return int(
		(record.get("population", {}) as Dictionary).get(
			"value", 0
		)
	)


func provenance() -> Dictionary:
	return _provenance.duplicate(true)
